--[[============================================================================
  master.lua  -  Deploys the worker swarm, hands out work, finishes specials.

  Setup: load this turtle's inventory with the (pre-programmed, labelled)
  worker turtles PLUS one of each special block (controller, power tap, access
  port). Run it once; it calibrates by GPS, places each worker, then serves
  columns until the shell + interior are built, then places the special blocks.
============================================================================]]

local cfg  = require("config")
local Plan = require("plan")
local Nav  = require("nav")
local P    = require("protocol")

local plan = Plan.new(cfg)
local O    = cfg.reactor.origin
local H    = cfg.reactor.height
local N    = cfg.swarm.workerCount

local masterFlight = O.y + H + cfg.move.flightBase + N + 2

--------------------------------------------------------------------------
-- Inventory helpers
--------------------------------------------------------------------------
local function slotOf(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
end

local function selectTurtleItem()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name:find("turtle") then turtle.select(s); return true end
  end
  return false
end

local function placeForwardItem(name)
  local ok, data = turtle.inspect()
  if ok and data.name == name then return true end
  if ok then turtle.dig() end
  local slot = slotOf(name)
  if not slot then print("[master] missing item: " .. name); return false end
  turtle.select(slot)
  local t = 0
  while not turtle.place() do
    if turtle.detect() then turtle.dig() else turtle.attack() end
    t = t + 1; if t > 20 then return false end; sleep(0.1)
  end
  return true
end

--------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------
P.open(cfg)
print("[master] calibrating via GPS...")
local nav = Nav.fromGPS(cfg)
local home = { x = nav.x, y = nav.y, z = nav.z }

--------------------------------------------------------------------------
-- Deploy workers, one at a time
--------------------------------------------------------------------------
local workers = {}   -- index -> rednet id
print("[master] deploying " .. N .. " workers...")
for i = 1, N do
  local sx = cfg.staging.pos.x + cfg.staging.step.x * (i - 1)
  local sy = cfg.staging.pos.y + cfg.staging.step.y * (i - 1)
  local sz = cfg.staging.pos.z + cfg.staging.step.z * (i - 1)
  nav:goTo(sx, sy + 1, sz, masterFlight)   -- hover one block above the spot
  if not selectTurtleItem() then error("[master] out of worker turtles at #" .. i) end
  while turtle.detectDown() do turtle.digDown() end
  if not turtle.placeDown() then error("[master] couldn't place worker #" .. i) end
  -- Wait for that worker to boot, calibrate and register.
  local id = P.receiveType("register", 30)
  if not id then error("[master] worker #" .. i .. " never registered") end
  P.send(id, { type = "assignIndex", index = i })
  workers[i] = id
  print("[master] worker #" .. i .. " online (id " .. id .. ")")
end

--------------------------------------------------------------------------
-- Serve the column work queue
--------------------------------------------------------------------------
local queue = plan:columnList()
local nextCol, total, doneCols, parked = 1, #queue, 0, 0
local parkedSpots = {}
print("[master] serving " .. total .. " columns...")

while parked < N do
  local id, msg = P.receive(15)
  if id and type(msg) == "table" then
    if msg.type == "reqColumn" then
      if nextCol <= total then
        local c = queue[nextCol]; nextCol = nextCol + 1
        P.send(id, { type = "column", lx = c.lx, lz = c.lz })
      else
        P.send(id, { type = "allDone" })
      end
    elseif msg.type == "columnDone" then
      doneCols = doneCols + 1
      if doneCols % 10 == 0 or doneCols == total then
        print(string.format("[master] %d/%d columns built", doneCols, total))
      end
    elseif msg.type == "parked" then
      parked = parked + 1
      if msg.x then parkedSpots[#parkedSpots + 1] = { x = msg.x, y = msg.y, z = msg.z } end
      print(string.format("[master] worker parked (%d/%d)", parked, N))
    end
    -- "restock" broadcasts are handled by the depot; master ignores them.
  end
end

--------------------------------------------------------------------------
-- Place the special blocks (controller / power tap / access port ...)
--------------------------------------------------------------------------
print("[master] placing special blocks...")
for _, sc in ipairs(plan:specialCells()) do
  local fx, fy, fz = O.x + sc.lx, O.y + sc.ly, O.z + sc.lz
  local sx, sz, face
  if sc.face == "north" then sx, sz, face = fx, fz - 1, 2
  elseif sc.face == "south" then sx, sz, face = fx, fz + 1, 0
  elseif sc.face == "west"  then sx, sz, face = fx - 1, fz, 1
  elseif sc.face == "east"  then sx, sz, face = fx + 1, fz, 3 end
  nav:goTo(sx, fy, sz, masterFlight)
  nav:face(face)
  if placeForwardItem(plan:itemFor(sc.kind)) then
    print("[master] placed " .. sc.kind)
  else
    print("[master] FAILED to place " .. sc.kind .. " (place it by hand)")
  end
end

--------------------------------------------------------------------------
-- Collect the parked workers (dig each one up into our inventory)
--------------------------------------------------------------------------
if cfg.swarm.autoCollect then
  print("[master] collecting " .. #parkedSpots .. " workers...")
  for _, sp in ipairs(parkedSpots) do
    nav:goTo(sp.x, sp.y + 1, sp.z, masterFlight)  -- hover directly above it
    local ok, data = turtle.inspectDown()
    if ok and data.name:find("turtle") then
      turtle.digDown()                             -- pick the worker up
      print("[master] collected a worker")
    else
      print("[master] no worker found below " ..
            sp.x .. "," .. sp.y .. "," .. sp.z .. " (collect by hand)")
    end
  end
end

--------------------------------------------------------------------------
-- Done
--------------------------------------------------------------------------
nav:goTo(home.x, home.y, home.z, masterFlight)
print("[master] BUILD COMPLETE.")
if not cfg.swarm.autoCollect then
  print("  Workers are parked on the staging line — pick them up.")
end
print("  Activate the reactor controller to finish.")
-- end of master.lua
