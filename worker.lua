--[[
  worker.lua  -  Reactor build worker (runs on each worker turtle).

  Responsibilities:
    * Calibrate world position + facing from GPS.
    * Register with the master and receive a build strip + a unique cruise
      altitude.
    * Build its strip layer-by-layer, bottom to top, placing every block with
      placeDown (so it can never trap itself and never collides with the
      other workers' strips).
    * Dig out any block that is in the way (terrain clearing).
    * Restock building blocks + fuel from the supply station (ME Bridge) using a
      one-at-a-time dock lock so the workers never pile up.

  Requires a GPS constellation in range and a wireless/ender modem upgrade.
]]

local cfg    = dofile("/config.lua")
local geo    = dofile("/geo.lua")
local layout = dofile("/layout.lua")

local O      = cfg.origin
local SZ     = cfg.size

-- ===========================================================================
-- State
-- ===========================================================================
local pos    = { x = 0, y = 0, z = 0 }   -- absolute world position
local facing = 0                          -- 0..3 (see geo.lua)
local myId   = os.getComputerID()
local myIndex, myCruiseY
local strip                               -- { axis=, lo=, hi= }
local stripKeys = {}                      -- set of block keys this worker places
local masterId, supplyId

local function log(s) print(("[w%d] %s"):format(myId, s)) end

-- ===========================================================================
-- Rednet
-- ===========================================================================
local function openModem()
  local m = peripheral.find("modem")
  if not m then error("no modem upgrade equipped on this turtle") end
  rednet.open(peripheral.getName(m))
end

-- Send a message and wait for a reply of an expected type from a given id.
local function rpc(id, msg, expectType, timeout)
  rednet.send(id, msg, cfg.protocol)
  local deadline = os.clock() + (timeout or 10)
  while os.clock() < deadline do
    local from, m = rednet.receive(cfg.protocol, deadline - os.clock())
    if from == id and type(m) == "table" and m.type == expectType then
      return m
    end
  end
  return nil
end

local function lookup(name)
  for _ = 1, 30 do
    local id = rednet.lookup(cfg.protocol, name)
    if id then return id end
    log("waiting for '" .. name .. "' ...")
    sleep(1)
  end
  error("could not find rednet host: " .. name)
end

-- ===========================================================================
-- Fuel
-- ===========================================================================
local function refuelIfNeeded()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() >= cfg.fuelLowMark then return end
  local s = cfg.slots.fuel
  turtle.select(s)
  while turtle.getFuelLevel() < cfg.fuelLowMark and turtle.getItemCount(s) > 0 do
    turtle.refuel(1)
  end
end

-- ===========================================================================
-- Movement (tracks absolute position; digs obstacles but never other turtles)
-- ===========================================================================
local function isTurtle(data)
  return data and type(data.name) == "string" and data.name:find("computercraft") ~= nil
end

local function turnRight() turtle.turnRight(); facing = geo.right(facing) end
local function turnLeft()  turtle.turnLeft();  facing = geo.left(facing)  end

local function face(f)
  local turns, dir = geo.turnsTo(facing, f)
  for _ = 1, turns do if dir == "right" then turnRight() else turnLeft() end end
end

-- generic forced move: try move; if blocked, dig (unless it's a turtle, then wait)
local function tryMove(moveFn, detectFn, inspectFn, digFn, attackFn, dx, dy, dz)
  for _ = 1, 300 do
    refuelIfNeeded()
    if moveFn() then
      pos.x = pos.x + dx; pos.y = pos.y + dy; pos.z = pos.z + dz
      return true
    end
    if detectFn() then
      local ok, data = inspectFn()
      if ok and isTurtle(data) then
        sleep(0.7)                 -- give the other turtle time to move
      else
        digFn()
      end
    else
      attackFn(); sleep(0.3)       -- mob or falling sand etc.
    end
  end
  error("stuck while moving at " .. textutils.serialize(pos))
end

local function forward()
  local v = geo.vecs[facing]
  return tryMove(turtle.forward, turtle.detect, turtle.inspect, turtle.dig, turtle.attack, v.x, 0, v.z)
end
local function up()   return tryMove(turtle.up,   turtle.detectUp,   turtle.inspectUp,   turtle.digUp,   turtle.attackUp,   0,  1, 0) end
local function down() return tryMove(turtle.down, turtle.detectDown, turtle.inspectDown, turtle.digDown, turtle.attackDown, 0, -1, 0) end

local function goY(targetY) while pos.y < targetY do up() end; while pos.y > targetY do down() end end
local function goX(targetX)
  if pos.x == targetX then return end
  face(targetX > pos.x and 1 or 3)
  while pos.x ~= targetX do forward() end
end
local function goZ(targetZ)
  if pos.z == targetZ then return end
  face(targetZ > pos.z and 2 or 0)
  while pos.z ~= targetZ do forward() end
end

-- ===========================================================================
-- GPS calibration
-- ===========================================================================
local function locate()
  local x, y, z = gps.locate(2)
  if x then return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) } end
  return nil
end

-- Determine position + facing without digging: rotate until an open side is
-- found, step into it, compare GPS before/after.
local function calibrate()
  local p1 = locate()
  if not p1 then error("no GPS fix - is a GPS constellation running in range?") end
  for _ = 0, 3 do
    if turtle.forward() then
      local p2 = locate()
      facing = geo.fromVec(p2.x - p1.x, p2.z - p1.z)
      pos = p2
      log(("calibrated at (%d,%d,%d) facing %s"):format(pos.x, pos.y, pos.z, geo.names[facing]))
      return
    end
    turtle.turnRight()
  end
  error("calibrate: turtle is boxed in - leave one horizontal side open")
end

-- ===========================================================================
-- Supply station (dock lock + ME Bridge exports)
-- ===========================================================================
local function dockAcquire()
  while true do
    local r = rpc(supplyId, { type = cfg.msg.DOCK_REQ, id = myId }, cfg.msg.DOCK_GRANT, 5)
    if r then return end
    sleep(0.5)
  end
end
local function dockRelease()
  rednet.send(supplyId, { type = cfg.msg.DOCK_REL, id = myId }, cfg.protocol)
end

local function exportInto(slot, itemId, count)
  if count <= 0 then return 0 end
  turtle.select(slot)
  local r = rpc(supplyId, { type = cfg.msg.EXPORT_REQ, id = myId, item = itemId, count = count }, cfg.msg.EXPORT_DONE, 15)
  local got = 0
  if r and r.exported and r.exported > 0 then
    local guard = 0
    local before = turtle.getItemCount(slot)
    while turtle.getItemCount(slot) < before + r.exported do
      if not turtle.suckDown() then
        guard = guard + 1
        if guard > 4 then break end
        sleep(0.2)
      end
    end
    got = turtle.getItemCount(slot) - before
  end
  return got
end

local SINGLE = { controller = true, powerTap = true, accessPort = true, computerPort = true, coolantPort = true }

-- Travel to the dock, top up fuel + every block this strip uses, return.
local function restock()
  local save = { x = pos.x, y = pos.y, z = pos.z }
  log("restock run")
  goY(myCruiseY)                       -- rise inside own strip (always clear)
  dockAcquire()                        -- only the lock holder may enter the dock
  goX(cfg.station.dock.x); goZ(cfg.station.dock.z)
  goY(cfg.station.dock.y)              -- descend onto the dock (chest is below)

  -- fuel
  if turtle.getItemCount(cfg.slots.fuel) < 16 then
    exportInto(cfg.slots.fuel, cfg.fuelItem, cfg.fuelPerTrip)
  end
  refuelIfNeeded()

  -- building blocks
  for key in pairs(stripKeys) do
    local slot = cfg.slots[key]
    local itemId = cfg.blocks[key]
    if slot and itemId then
      local target = SINGLE[key] and 4 or 64
      local have = turtle.getItemCount(slot)
      if have < target then exportInto(slot, itemId, target - have) end
    end
  end

  goY(myCruiseY)                       -- leave the dock column...
  dockRelease()                        -- ...then free it for the next worker
  goX(save.x); goZ(save.z)
  goY(save.y)
  turtle.select(cfg.slots.casing)
end

local function ensureItem(key)
  local slot = cfg.slots[key]
  if turtle.getItemCount(slot) > 0 then return end
  restock()
end

-- ===========================================================================
-- Placing
-- ===========================================================================
local function placeKeyDown(key)
  ensureItem(key)
  local slot = cfg.slots[key]
  turtle.select(slot)
  if turtle.detectDown() then
    local ok, data = turtle.inspectDown()
    if ok and data.name == cfg.blocks[key] then return end   -- already correct
    turtle.digDown()
  end
  if not turtle.placeDown() then
    ensureItem(key)                    -- maybe ran dry mid-place
    turtle.select(slot)
    if turtle.detectDown() then turtle.digDown() end
    turtle.placeDown()
  end
end

-- ===========================================================================
-- Build
-- ===========================================================================
local function computeStripKeys()
  stripKeys = {}
  local aLo, aHi, bLo, bHi
  if strip.axis == "x" then aLo, aHi, bLo, bHi = strip.lo, strip.hi, 0, SZ.z - 1
  else                      aLo, aHi, bLo, bHi = strip.lo, strip.hi, 0, SZ.x - 1 end
  for a = aLo, aHi do
    for b = bLo, bHi do
      local lx, lz = (strip.axis == "x") and a or b, (strip.axis == "x") and b or a
      for ly = 0, SZ.y - 1 do
        local k = layout.blockAt(cfg, lx, ly, lz)
        if k then stripKeys[k] = true end
      end
    end
  end
end

-- Top up before a layer if anything is low, so we don't trip constantly.
local function maybeRestock()
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < cfg.fuelLowMark then return restock() end
  for key in pairs(stripKeys) do
    if not SINGLE[key] and turtle.getItemCount(cfg.slots[key]) < 8 then return restock() end
  end
end

local function buildStrip()
  local aLo, aHi = strip.lo, strip.hi
  local bLo, bHi = 0, (strip.axis == "x") and (SZ.z - 1) or (SZ.x - 1)

  for ly = 0, SZ.y - 1 do
    local flightY = O.y + ly + 1
    maybeRestock()
    -- climb into the layer's flight level inside our own (clear) airspace
    goY(flightY)
    local fwd = true
    for a = aLo, aHi do
      local bs, be, st = bLo, bHi, 1
      if not fwd then bs, be, st = bHi, bLo, -1 end
      for b = bs, be, st do
        local lx, lz = (strip.axis == "x") and a or b, (strip.axis == "x") and b or a
        goX(O.x + lx); goZ(O.z + lz)
        local key = layout.blockAt(cfg, lx, ly, lz)
        if key then placeKeyDown(key) end
      end
      fwd = not fwd
    end
    rednet.send(masterId, { type = cfg.msg.PROGRESS, id = myId, layer = ly + 1, total = SZ.y }, cfg.protocol)
    log(("layer %d/%d done"):format(ly + 1, SZ.y))
  end
end

-- ===========================================================================
-- Main
-- ===========================================================================
local function main()
  openModem()
  masterId = lookup(cfg.masterName)
  supplyId = lookup(cfg.supplyName)

  calibrate()

  -- register and wait for an assignment
  local a
  repeat
    a = rpc(masterId, { type = cfg.msg.REGISTER, id = myId }, cfg.msg.ASSIGN, 5)
    if not a then log("registering...") end
  until a
  strip     = a.strip
  myIndex   = a.index
  myCruiseY = a.cruiseY
  log(("assigned strip %s[%d..%d], cruiseY=%d, index=%d"):format(strip.axis, strip.lo, strip.hi, myCruiseY, myIndex))
  computeStripKeys()

  buildStrip()

  goY(myCruiseY)                          -- park above the build
  rednet.send(masterId, { type = cfg.msg.DONE, id = myId }, cfg.protocol)
  log("strip complete - parked.")
end

main()
