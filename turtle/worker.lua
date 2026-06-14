--[[
  worker.lua  -  Reactor swarm worker (runs on each worker turtle).

  Talks to the Python backend over HTTP: registers, gets its chunk + a per-layer
  GCODE manifest, restocks the exact blocks it needs at its assigned ME-Bridge
  dock, and builds its chunk layer by layer (clearing anything in the way). When
  finished it returns to HOME (to be removed).

  EQUIP: a pickaxe (dig/clear) and a wireless/ender modem (for GPS).
  Needs: a GPS constellation in range, and `turtle_config.lua` (server URL).
]]

local CFG = dofile("/turtle_config.lua")
local SERVER = CFG.server:gsub("/$", "")
local FUEL = CFG.fuelItem or "minecraft:coal"

local id = tostring(os.getComputerID())
local function log(s) print(("[w%s] %s"):format(id, s)) end

-- ===========================================================================
-- HTTP (synchronous, with a few retries)
-- ===========================================================================
local function httpJSON(method, path, body)
  local url = SERVER .. path
  for _ = 1, 5 do
    local resp
    if method == "POST" then
      resp = http.post(url, textutils.serialiseJSON(body or {}), { ["Content-Type"] = "application/json" })
    else
      resp = http.get(url)
    end
    if resp then
      local s = resp.readAll(); resp.close()
      local ok, t = pcall(textutils.unserialiseJSON, s)
      if ok then return t end
      return nil
    end
    sleep(1)
  end
  return nil
end

-- ===========================================================================
-- Direction + state
-- ===========================================================================
local FNAME = { north = 0, east = 1, south = 2, west = 3 }
local VEC   = { [0]={x=0,z=-1}, [1]={x=1,z=0}, [2]={x=0,z=1}, [3]={x=-1,z=0} }
local function fromVec(dx, dz) for i=0,3 do if VEC[i].x==dx and VEC[i].z==dz then return i end end end

local pos    = { x = 0, y = 0, z = 0 }
local facing = 0
local A                     -- assignment from /register

-- ===========================================================================
-- Inventory
-- ===========================================================================
local function countItem(name)
  local n = 0
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and d.name == name then n = n + d.count end end
  return n
end
local function selectItem(name)
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and d.name == name then turtle.select(s); return true end end
  return false
end
local function freeSlots()
  local n = 0; for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end; return n
end

-- ===========================================================================
-- Movement (digs anything in the way; never another worker - chunks are disjoint
-- and transit altitudes are unique, so a block ahead is always terrain)
-- ===========================================================================
local function refuelMaybe()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() > 80 then return end
  if selectItem(FUEL) then turtle.refuel(1) end
end

local function isTurtle(data)
  return data and type(data.name) == "string" and data.name:find("computercraft") ~= nil
end

local function step(moveFn, digFn, detectFn, inspectFn, attackFn, dx, dy, dz)
  for _ = 1, 600 do
    if moveFn() then pos.x = pos.x + dx; pos.y = pos.y + dy; pos.z = pos.z + dz; return true end
    if detectFn() then
      local ok, data = inspectFn()
      if ok and isTurtle(data) then sleep(0.6)      -- another worker - wait, don't dig
      else digFn() end
    else
      attackFn(); sleep(0.2)
    end
    refuelMaybe()
  end
  error(("stuck at %d,%d,%d"):format(pos.x, pos.y, pos.z))
end
local function fwd()  return step(turtle.forward, turtle.dig,     turtle.detect,     turtle.inspect,     turtle.attack,     VEC[facing].x, 0, VEC[facing].z) end
local function up()   return step(turtle.up,      turtle.digUp,   turtle.detectUp,   turtle.inspectUp,   turtle.attackUp,   0,  1, 0) end
local function down() return step(turtle.down,    turtle.digDown, turtle.detectDown, turtle.inspectDown, turtle.attackDown, 0, -1, 0) end

local function turnRight() turtle.turnRight(); facing = (facing + 1) % 4 end
local function turnLeft()  turtle.turnLeft();  facing = (facing + 3) % 4 end
local function face(f)
  local d = (f - facing) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end
local function goY(ty) while pos.y < ty do up() end;   while pos.y > ty do down() end end
local function goX(tx) if pos.x ~= tx then face(tx > pos.x and 1 or 3); while pos.x ~= tx do fwd() end end end
local function goZ(tz) if pos.z ~= tz then face(tz > pos.z and 2 or 0); while pos.z ~= tz do fwd() end end end

-- ===========================================================================
-- GPS
-- ===========================================================================
local function gpsPos()
  local x, y, z = gps.locate(2)
  if x then return { x = math.floor(x+0.5), y = math.floor(y+0.5), z = math.floor(z+0.5) } end
  return nil
end
local function syncPos()
  local p = gpsPos()
  if p then pos = p; return true end
  return false
end

-- Establish position + facing. Spawned in HOME (master behind, bridge below,
-- disk to a side), so rise into open air first, then derive facing from a move.
local function calibrate()
  if not syncPos() then error("no GPS fix - is a constellation in range?") end
  for _ = 1, 3 do up() end                 -- clear the home pocket
  local p1 = gpsPos()
  fwd()
  local p2 = gpsPos()
  facing = fromVec(p2.x - p1.x, p2.z - p1.z) or 0
  pos = p2
  log(("calibrated (%d,%d,%d) facing %d"):format(pos.x, pos.y, pos.z, facing))
end

-- ===========================================================================
-- ME bridge restock (worker sits on its dock; bridge below exports "up")
-- ===========================================================================
local function pull(me, name, count)
  while count > 0 do
    if freeSlots() == 0 and not selectItem(name) then break end
    local ok, n = pcall(me.exportItem, { name = name, count = math.min(count, 64) }, "up")
    if ok and type(n) == "number" and n > 0 then count = count - n else break end
  end
end

local function dumpJunk(me, keep)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not keep[d.name] then
      turtle.select(s); pcall(me.importItem, { name = d.name, count = 9999 }, "up")
    end
  end
end

-- Top fuel to the turtle's max with coal, then return any leftover coal (the
-- design doc: refuel to max, don't hoard coal - inventory is small).
local function refuelToMax(me)
  if turtle.getFuelLevel() == "unlimited" then return end
  local limit = turtle.getFuelLimit()
  while turtle.getFuelLevel() < limit do
    local before = turtle.getFuelLevel()
    pull(me, FUEL, 64)
    if not selectItem(FUEL) then break end
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and d.name == FUEL then turtle.select(s); turtle.refuel() end
    end
    if turtle.getFuelLevel() <= before then break end   -- ME had no more coal
  end
  for s = 1, 16 do                                       -- return leftover coal
    local d = turtle.getItemDetail(s)
    if d and d.name == FUEL then turtle.select(s); pcall(me.importItem, { name = FUEL, count = 64 }, "up") end
  end
end

-- Make a dock run: go to the dock, lock it, do `fn(me)`, unlock, return to where
-- we were. `keep` is the set of block ids we're allowed to hold.
local function dockTrip(fn, keep)
  local save = { x = pos.x, y = pos.y, z = pos.z }
  goY(A.cruiseY); goX(A.dock.x); goZ(A.dock.z)
  while true do
    local r = httpJSON("POST", "/dock/acquire", { id = id, dock = A.dockIndex })
    if r and r.granted then break end
    sleep(0.5)
  end
  goY(A.dock.y)
  local me = peripheral.find("me_bridge")
  if me then
    if keep then dumpJunk(me, keep) end
    fn(me)
  else
    log("WARNING: no me_bridge under dock")
  end
  goY(A.cruiseY)
  httpJSON("POST", "/dock/release", { id = id, dock = A.dockIndex })
  goX(save.x); goZ(save.z); goY(save.y)
end

-- ===========================================================================
-- Placing
-- ===========================================================================
local keepSet = {}                                   -- block ids this layer keeps

local function emergency(bid)
  dockTrip(function(me) pull(me, bid, 64) end, keepSet)
end

local function placeKey(bid)                          -- turtle already at (x, y+1, z)
  if not selectItem(bid) then emergency(bid); selectItem(bid) end
  if turtle.detectDown() then
    local ok, data = turtle.inspectDown()
    if ok and data.name == bid then return end
    turtle.digDown()
  end
  if not turtle.placeDown() then
    emergency(bid); selectItem(bid)
    if turtle.detectDown() then turtle.digDown() end
    turtle.placeDown()
  end
end

-- ===========================================================================
-- Build
-- ===========================================================================
local function buildLayer(work)
  -- which block ids matter this layer (for junk-keep + emergency)
  keepSet = { [FUEL] = true }
  for bid in pairs(work.needs) do keepSet[bid] = true end

  -- restock exactly what this layer needs (also dumps junk + tops fuel)
  dockTrip(function(me)
    refuelToMax(me)
    for bid, n in pairs(work.needs) do
      if countItem(bid) < n then pull(me, bid, n - countItem(bid)) end
    end
  end, keepSet)

  for _, p in ipairs(work.place) do
    goY(p.y + 1); goX(p.x); goZ(p.z)
    placeKey(p.b)
  end
end

-- ===========================================================================
-- Main
-- ===========================================================================
local function main()
  if not http then error("HTTP API disabled - enable it / allow the server address in the CC config") end

  -- cold start: we spawn on the HOME ME Bridge - grab fuel here before moving
  local homeBridge = peripheral.find("me_bridge")
  if homeBridge then refuelToMax(homeBridge) end

  calibrate()

  repeat
    A = httpJSON("POST", "/register", { id = id })
    if not (A and A.assigned) then log("waiting for assignment..."); sleep(2) end
  until A and A.assigned
  log(("chunk %d, dock %d, cruiseY %d"):format(A.chunkIndex, A.dockIndex, A.cruiseY))

  local layer = 0
  while true do
    local work = httpJSON("GET", ("/work?id=%s&layer=%d"):format(id, layer))
    if not work then sleep(1)
    elseif work.done then break
    else
      syncPos()                                       -- correct drift before the layer
      buildLayer(work)
      httpJSON("POST", "/progress", { id = id, layer = layer + 1, placed = #work.place })
      log(("layer %d done"):format(layer + 1))
      layer = layer + 1
    end
  end

  httpJSON("POST", "/done", { id = id })
  log("chunk complete - waiting to be collected")
  goY(A.cruiseY)                                  -- hover at my unique altitude

  -- wait our turn (HOME holds one worker at a time for the master to mine)
  while true do
    local r = httpJSON("GET", "/collect_slot?id=" .. id)
    if r and r.go then break end
    sleep(1)
  end

  -- descend onto HOME, in front of the master, and idle until it mines us
  goX(A.home.x); goZ(A.home.z); goY(A.home.y)
  httpJSON("POST", "/parked", { id = id })
  log("parked at home - awaiting pickup")
  while true do sleep(5) end
end

main()
