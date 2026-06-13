--[[============================================================================
  worker.lua  -  Builds vertical columns of the reactor on command.

  Lifecycle:
    1. Calibrate position/heading via GPS.
    2. Broadcast "register"; master replies "assignIndex" -> we learn our index
       (used to pick a personal flight altitude) and the master's id.
    3. Loop: ask master for a column, fly above it, build it bottom->top,
       restocking from the ME Bridge depot whenever we'd run short.
    4. On "allDone"/"recall": fly home to our deploy spot, park, idle.

  Column build trick (turtle ends ABOVE the column, ready to fly off):
       stand one block above the target cell, placeDown, move up, repeat.
============================================================================]]

local cfg  = require("config")
local Plan = require("plan")
local Nav  = require("nav")
local P    = require("protocol")

local plan = Plan.new(cfg)
local O    = cfg.reactor.origin
local H    = cfg.reactor.height

-- Which item kinds this worker stocks in bulk (specials are master's job).
local bulkKinds = { "casing", "coolant", "fuelRod", "controlRod" }
if cfg.wallBlock == "glass" then table.insert(bulkKinds, "glass") end

--------------------------------------------------------------------------
-- Inventory helpers (search by item name; no fixed slots needed)
--------------------------------------------------------------------------
local function slotOf(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
end

local function countOf(name)
  local n = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then n = n + d.count end
  end
  return n
end

--------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------
P.open(cfg)
print("[worker] calibrating via GPS...")
local nav = Nav.fromGPS(cfg)
local index, masterId

print("[worker] registering...")
local label = os.getComputerLabel() or ("worker-" .. os.getComputerID())
repeat
  P.broadcast({ type = "register", label = label })
  local id, msg = P.receiveType("assignIndex", 3)
  if id then masterId, index = id, msg.index end
until index ~= nil
print("[worker] I am index " .. index .. " (master " .. masterId .. ")")

local flightY = O.y + H + cfg.move.flightBase + index

--------------------------------------------------------------------------
-- Restock at the ME Bridge depot
--------------------------------------------------------------------------
local function restock()
  local d = cfg.depot.dock
  nav:goTo(d.x, d.y, d.z, flightY)
  nav:face(cfg.depot.heading)
  local items = {}
  for _, kind in ipairs(bulkKinds) do
    local name = plan:itemFor(kind)
    if name then
      local want = cfg.depot.restockTo - countOf(name)
      if want > 0 then items[#items + 1] = { name = name, count = want } end
    end
  end
  -- also pull fuel if we're running low
  local fuelLow = false
  if cfg.fuel and cfg.fuel.item then
    local fl = turtle.getFuelLevel()
    if fl ~= "unlimited" and fl < cfg.fuel.refuelBelow then
      fuelLow = true
      items[#items + 1] = { name = cfg.fuel.item, count = cfg.fuel.requestCount }
    end
  end
  if #items > 0 then
    P.broadcast({ type = "restock", to = label, items = items })
    P.receiveType("restockDone", 10)   -- ok to time out; we re-check counts
  end
  -- burn the fuel we just received
  if fuelLow then
    local s = slotOf(cfg.fuel.item)
    while s do
      turtle.select(s)
      turtle.refuel()                  -- burns the whole stack in this slot
      local ns = slotOf(cfg.fuel.item)
      if ns == s then break end        -- couldn't burn (not actually fuel) -> stop
      s = ns
    end
    turtle.select(1)
  end
end

-- Trigger a depot trip if fuel is getting low (independent of block needs).
local function maybeRefuel()
  if not (cfg.fuel and cfg.fuel.item) then return end
  local fl = turtle.getFuelLevel()
  if fl ~= "unlimited" and fl < cfg.fuel.refuelBelow then restock() end
end

-- Make sure we hold enough to build this whole column without interruption.
local function ensureStock(lx, lz)
  local need = {}
  for ly = 0, H - 1 do
    local k = plan:blockAt(lx, ly, lz)
    if k and not plan:isSpecialKind(k) then
      local name = plan:itemFor(k)
      need[name] = (need[name] or 0) + 1
    end
  end
  for name, n in pairs(need) do
    if countOf(name) < n then restock(); break end
  end
end

--------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------
local function placeDownKind(kind)
  local name = plan:itemFor(kind)
  if not name then error("[worker] no item id configured for kind '" .. kind .. "'") end
  local ok, data = turtle.inspectDown()
  if ok and data.name == name then return true end   -- already correct (resume)
  if ok then turtle.digDown() end
  local slot = slotOf(name)
  while not slot do
    print("[worker] need " .. name .. ", restocking...")
    restock()
    slot = slotOf(name)
    if not slot then sleep(5) end
  end
  turtle.select(slot)
  local tries = 0
  while not turtle.placeDown() do
    if turtle.detectDown() then turtle.digDown() else turtle.attackDown() end
    tries = tries + 1
    if tries > 20 then return false end
    sleep(0.1)
  end
  return true
end

--------------------------------------------------------------------------
-- Build one column at local (lx,lz)
--------------------------------------------------------------------------
local function buildColumn(lx, lz)
  maybeRefuel()
  ensureStock(lx, lz)
  local fx, fz = O.x + lx, O.z + lz
  -- Fly above the column, then drop to one block above the floor cell.
  nav:goTo(fx, O.y + 1, fz, flightY)
  for ly = 0, H - 1 do
    local kind = plan:blockAt(lx, ly, lz)
    if kind and not plan:isSpecialKind(kind) then
      placeDownKind(kind)
    else
      -- special (master places later) or air: leave the cell empty/clear
      if turtle.detectDown() then turtle.digDown() end
    end
    if ly < H - 1 then nav:up() end   -- rise to place the next cell
  end
  nav:goY(flightY)                    -- back up to cruising altitude
end

--------------------------------------------------------------------------
-- Park at our deploy spot and idle
--------------------------------------------------------------------------
local function parkAndIdle(home)
  nav:goTo(home.x, home.y, home.z, flightY)
  P.send(masterId, { type = "parked", index = index,
                     x = nav.x, y = nav.y, z = nav.z })
  print("[worker] done. Parked — waiting for pickup.")
end

--------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------
local home = { x = nav.x, y = nav.y, z = nav.z }   -- where we calibrated

while true do
  P.send(masterId, { type = "reqColumn" })
  local id, msg = P.receive(10)
  if not id then
    -- no reply; nudge master again
  elseif msg.type == "column" then
    print(string.format("[worker] building column (%d,%d)", msg.lx, msg.lz))
    buildColumn(msg.lx, msg.lz)
    P.send(masterId, { type = "columnDone", lx = msg.lx, lz = msg.lz })
  elseif msg.type == "allDone" or msg.type == "recall" then
    parkAndIdle(home)
    break
  end
end
