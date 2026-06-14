--[[
  reactor.lua  -  Single-turtle Extreme Reactors builder.

  One mining turtle builds the whole reactor by itself and restocks blocks +
  fuel directly from an Advanced Peripherals ME Bridge. No GPS, no rednet, no
  second computer, no chest, no wired modem.

  THE DOCK
    The turtle's home is the block directly ON TOP of the ME Bridge. To restock
    it simply calls  me.exportItem({name=ID, count=N}, "up")  and the bridge
    pushes the items straight up into the turtle's own inventory. So:
        [ turtle home ]  <- CONFIG.home / CONFIG.start  (sits on the bridge)
        [ ME Bridge   ]  <- exports "up" into the turtle
    Fuel works the same way - it pulls coal from the ME system, so the turtle
    can even start with an empty fuel tank.

  NAVIGATION (dead reckoning, no GPS)
    The turtle tracks its position starting from CONFIG.start. PLACE it on that
    exact block, FACING the set direction, before running. (F3 shows coords +
    facing.) Since home is on top of the bridge, start == home.

  EQUIP: a pickaxe (to dig / clear blocks in the way).

  Install:
     wget https://raw.githubusercontent.com/blakevin123/Reactor/main/reactor.lua
     reactor
]]

-- ======================================================================
-- CONFIG  -- edit everything in here
-- ======================================================================
local CONFIG = {
  -- Reactor outer size (including the casing shell). Min 3 each.
  size = { x = 5, y = 5, z = 5 },

  -- Minimum corner of the reactor (smallest X/Y/Z), in world coords.
  origin = { x = -80, y = -58, z = -176 },

  -- Where the turtle is PLACED (on top of the ME Bridge) and which way it
  -- faces: "north"(-Z) "south"(+Z) "east"(+X) "west"(-X).
  start = { x = -45, y = -59, z = -167, facing = "west" },

  -- Dock cell it returns to for restock = same block, on top of the bridge.
  home = { x = -45, y = -59, z = -167 },

  -- Transit altitude for moving to/from the dock. Must be ABOVE the reactor.
  -- nil = auto (origin.y + size.y + 3).
  cruiseY = nil,

  -- Use a GPS constellation (if one is in range) to auto-detect the start
  -- position and CORRECT dead-reckoning drift before every layer. Strongly
  -- recommended for large builds - without it, one mis-reported move shifts the
  -- rest of the build (e.g. fuel rods ending up on the walls). Needs a wireless
  -- or ender modem on the turtle. With GPS on, start.x/y/z is auto-detected and
  -- only start.facing matters. Harmless if no constellation is found.
  useGPS = true,

  -- Fuel-column pattern: "checkerboard" | "full" | "spaced".
  fuelPattern = "checkerboard",
  fuelSpacing = 2,

  reactorType  = "passive",      -- "passive" | "active"
  useGlassWalls = true,

  -- Block IDs (verify with F3+H advanced tooltips). coolant = nil -> air interior.
  blocks = {
    casing       = "bigreactors:reinforced_reactorcasing",
    glass        = "bigreactors:reinforced_reactorglass",
    fuelRod      = "bigreactors:reinforced_reactorfuelrod",
    controlRod   = "bigreactors:reinforced_reactorcontrolrod",
    controller   = "bigreactors:reinforced_reactorcontroller",
    powerTap     = "bigreactors:reinforced_reactorpowertapfe_active",
    accessPort   = "bigreactors:reinforced_reactorsolidaccessport",
    computerPort = "bigreactors:reinforced_reactorcomputerport",
    coolantPort  = "bigreactors:reinforced_reactorcoolantport",
    coolant      = "allthemodium:unobtainium_block",  -- nil = air interior
  },

  -- Components on the front (min-Z) face. lx=1..size.x-2, ly=1..size.y-2.
  -- Use the strings below for "size.x-2"/"size.y-2", or plain numbers.
  components = {
    controller   = { lx = 1,          ly = 1 },
    powerTap     = { lx = "size.x-2", ly = 1 },
    accessPort   = { lx = 1,          ly = "size.y-2" },
    computerPort = { lx = "size.x-2", ly = "size.y-2" },
  },

  fuelItem    = "minecraft:coal",
  fuelLowMark = 1000,            -- refuel / return to dock when fuel below this

  meExportDir = "up",           -- direction the bridge pushes items (into the turtle)
  craftTimeout = 300,           -- seconds to wait for an ME autocraft before giving up
  returnLeftovers = true,       -- when done, push all leftover items back into the ME system
}
-- ======================================================================

local C  = CONFIG
local SZ = C.size
local O  = C.origin
local SINGLE = { controller=true, powerTap=true, accessPort=true, computerPort=true, coolantPort=true }

local FNAME = { north = 0, east = 1, south = 2, west = 3 }
local VEC   = { [0]={x=0,z=-1}, [1]={x=1,z=0}, [2]={x=0,z=1}, [3]={x=-1,z=0} }

local function resolve(v)
  if type(v) == "number" then return v end
  if v == "size.x-2" then return SZ.x - 2 end
  if v == "size.y-2" then return SZ.y - 2 end
  if v == "size.z-2" then return SZ.z - 2 end
  error("bad coord expr: " .. tostring(v))
end

local cruiseY = C.cruiseY or (O.y + SZ.y + 3)

-- ----------------------------------------------------------------------
-- Inventory (find blocks by NAME, since the bridge drops them anywhere)
-- ----------------------------------------------------------------------
local function countItem(id)
  local n = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == id then n = n + d.count end
  end
  return n
end

local function selectItem(id)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == id then turtle.select(s); return true end
  end
  return false
end

local function freeSlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

-- Items we keep (everything the build uses + fuel). Anything else in the
-- inventory is dug junk to be cleared out at the dock.
local wanted = { [C.fuelItem] = true }
for _, id in pairs(C.blocks) do if id then wanted[id] = true end end

-- ----------------------------------------------------------------------
-- ME Bridge (turtle sits on top; export pushes items up into us)
-- ----------------------------------------------------------------------
local me = peripheral.find("me_bridge")

-- What can the ME autocraft, and does this bridge expose a craft call?
local craftable = {}
if me then
  local ok, items = pcall(me.getCraftableItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do if it.name then craftable[it.name] = true end end
  end
end
local canCraft = me and type(me.craftItem) == "function"

local function meStock()
  local map = {}
  if not me then return map end
  local ok, items = pcall(me.getItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do if it.name then map[it.name] = it.count or it.amount or 0 end end
  end
  return map
end

local function meAmount(id)
  if not me then return 0 end
  local ok, items = pcall(me.getItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do if it.name == id then return it.count or it.amount or 0 end end
  end
  return 0
end

local function isCrafting(id)
  if not me or type(me.isItemCrafting) ~= "function" then return false end
  local ok, v = pcall(me.isItemCrafting, { name = id })
  return ok and v == true
end

-- Ask the ME to craft `count` of id (if it can) and wait until some is
-- available. Returns true once at least one is in stock, false if it can't be
-- crafted or the wait times out.  craftItem returns (ok, err); a false with an
-- err usually just means "already crafting", so we still wait either way.
local function craftAndWait(id, count)
  if not canCraft or not craftable[id] then return false end
  if not isCrafting(id) then
    print(("ME out of %s - requesting craft of %d"):format(id, count))
    local ok, started, err = pcall(me.craftItem, { name = id, count = count })
    if ok and started == false and err then print("  craftItem: " .. tostring(err)) end
  end
  local deadline = os.clock() + (C.craftTimeout or 300)
  while os.clock() < deadline do
    if meAmount(id) >= 1 then return true end
    sleep(3)
  end
  print("  craft timed out for " .. id)
  return false
end

-- Pull up to `want` of an item into the turtle, in 64-chunks so multi-stack
-- requests fill several inventory slots. If the ME runs out mid-pull it asks
-- for a craft and waits, then keeps pulling.
local function pull(id, want)
  if not me or not id then return end
  while want > 0 do
    local ok, n = pcall(me.exportItem, { name = id, count = math.min(want, 64) }, C.meExportDir)
    if ok and type(n) == "number" and n > 0 then
      want = want - n
    elseif craftAndWait(id, want) then
      -- crafted some; loop and export again
    else
      break                                     -- not craftable / timed out
    end
  end
end

-- Kick off crafts up front for everything the build needs but the ME is short
-- on, so they craft in parallel while the turtle works.
local function precraft(totals, blocks)
  if not canCraft then return end
  local stock = meStock()
  for key, need in pairs(totals) do
    local id = blocks[key]
    if id and craftable[id] then
      local short = need - (stock[id] or 0)
      if short > 0 and not isCrafting(id) then
        print(("pre-crafting %d x %s"):format(short, key))
        local ok, started, err = pcall(me.craftItem, { name = id, count = short })
        if ok and started == false and err then print("  craftItem: " .. tostring(err)) end
      end
    end
  end
end

-- ----------------------------------------------------------------------
-- Movement (dead reckoning; digs anything in the way)
-- ----------------------------------------------------------------------
local pos    = { x = C.start.x, y = C.start.y, z = C.start.z }
local facing = FNAME[C.start.facing] or error("start.facing must be north/south/east/west")

-- Correct `pos` from GPS when a constellation is reachable. Facing is never
-- corrected here (turn tracking can't drift); only position can, and that is
-- exactly what causes blocks to land a row off. Returns true if it got a fix.
local hasWirelessModem = peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end) ~= nil
local function syncPos()
  if not (C.useGPS and hasWirelessModem) then return false end
  local x, y, z = gps.locate(1)
  if x then
    pos.x = math.floor(x + 0.5); pos.y = math.floor(y + 0.5); pos.z = math.floor(z + 0.5)
    return true
  end
  return false
end

local function refuel()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() > C.fuelLowMark then return end
  local keep = turtle.getSelectedSlot()
  while turtle.getFuelLevel() <= C.fuelLowMark and selectItem(C.fuelItem) do
    if not turtle.refuel(1) then break end
  end
  turtle.select(keep)
end

local function step(moveFn, digFn, detectFn, attackFn, dx, dy, dz)
  for _ = 1, 400 do
    if moveFn() then pos.x = pos.x + dx; pos.y = pos.y + dy; pos.z = pos.z + dz; return true end
    if detectFn() then digFn() else attackFn(); sleep(0.2) end
    refuel()
  end
  error(("stuck at %d,%d,%d"):format(pos.x, pos.y, pos.z))
end

local function fwd()  return step(turtle.forward, turtle.dig,     turtle.detect,     turtle.attack,     VEC[facing].x, 0, VEC[facing].z) end
local function up()   return step(turtle.up,      turtle.digUp,   turtle.detectUp,   turtle.attackUp,   0,  1, 0) end
local function down() return step(turtle.down,    turtle.digDown, turtle.detectDown, turtle.attackDown, 0, -1, 0) end

local function turnRight() turtle.turnRight(); facing = (facing + 1) % 4 end
local function turnLeft()  turtle.turnLeft();  facing = (facing + 3) % 4 end
local function face(f)
  local d = (f - facing) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

local function goY(ty) while pos.y < ty do up() end;   while pos.y > ty do down() end end
local function goX(tx) if pos.x ~= tx then face(tx > pos.x and 1 or 3); while pos.x ~= tx do fwd() end end end
local function goZ(tz) if pos.z ~= tz then face(tz > pos.z and 2 or 0); while pos.z ~= tz do fwd() end end end

local function atHome() return pos.x == C.home.x and pos.y == C.home.y and pos.z == C.home.z end

-- ----------------------------------------------------------------------
-- Layout: which block goes at local (lx,ly,lz)? returns a key or nil(air)
-- ----------------------------------------------------------------------
local function isFuelColumn(lx, lz)
  if C.fuelPattern == "full" then return true end
  if C.fuelPattern == "spaced" then
    local s = C.fuelSpacing or 2
    return ((lx - 1) % s == 0) and ((lz - 1) % s == 0)
  end
  return ((lx + lz) % 2) == 0
end

local compLookup = {}
do
  local list = {}
  for key, p in pairs(C.components) do
    if p then
      local k = key
      if key == "powerTap" and C.reactorType == "active" then k = "coolantPort" end
      list[#list+1] = { key = k, lx = resolve(p.lx), ly = resolve(p.ly) }
    end
  end
  if C.reactorType == "active" then
    local n = 0
    for _, c in ipairs(list) do if c.key == "coolantPort" then n = n + 1 end end
    if n == 1 then list[#list+1] = { key = "coolantPort", lx = math.floor(SZ.x/2), ly = 1 } end
  end
  for _, c in ipairs(list) do compLookup[c.lx .. ":" .. c.ly] = c.key end
end

local function blockAt(lx, ly, lz)
  local minx, maxx = lx == 0, lx == SZ.x - 1
  local miny, maxy = ly == 0, ly == SZ.y - 1
  local minz, maxz = lz == 0, lz == SZ.z - 1
  local ex = (minx and 1 or 0)+(maxx and 1 or 0)+(miny and 1 or 0)+(maxy and 1 or 0)+(minz and 1 or 0)+(maxz and 1 or 0)
  if ex >= 2 then
    return "casing"
  elseif ex == 1 then
    if minz then
      local c = compLookup[lx .. ":" .. ly]
      if c then return c end
    end
    if maxy and isFuelColumn(lx, lz) then return "controlRod" end
    if C.useGlassWalls and not miny and not maxy then return "glass" end
    return "casing"
  else
    if isFuelColumn(lx, lz) then return "fuelRod" end
    if C.blocks.coolant then return "coolant" end
    return nil
  end
end

local totals, usedKeys = {}, {}
for lx = 0, SZ.x-1 do for ly = 0, SZ.y-1 do for lz = 0, SZ.z-1 do
  local k = blockAt(lx, ly, lz)
  if k then totals[k] = (totals[k] or 0) + 1; usedKeys[k] = true end
end end end

-- How many of each block to carry. Budget the 16 inventory slots: 1 for fuel,
-- 1 per single component, and split the rest among the bulk blocks weighted by
-- how many the build needs - so casing/fuel rods carry several stacks and the
-- turtle makes far fewer dock trips.
local targets = {}
do
  local bulk, singles = {}, 0
  for k in pairs(usedKeys) do
    if SINGLE[k] then singles = singles + 1; targets[k] = math.min(4, totals[k])
    else bulk[#bulk+1] = k; targets[k] = 64 end
  end
  local extra = math.max(0, 16 - 1 - singles - #bulk)   -- spare slots for more stacks
  while extra > 0 and #bulk > 0 do
    local best, bestScore
    for _, k in ipairs(bulk) do
      local score = totals[k] / (targets[k] / 64 + 1)    -- biggest unmet demand
      if not bestScore or score > bestScore then bestScore = score; best = k end
    end
    targets[best] = math.min(targets[best] + 64, math.ceil(totals[best] / 64) * 64)
    extra = extra - 1
  end
end

-- ----------------------------------------------------------------------
-- Restock at the dock
-- ----------------------------------------------------------------------
local saved
local function goHome()
  saved = { x = pos.x, y = pos.y, z = pos.z }
  if atHome() then return end
  goY(cruiseY); goX(C.home.x); goZ(C.home.z); goY(C.home.y)
end
local function goBack()
  if pos.x == saved.x and pos.y == saved.y and pos.z == saved.z then return end
  goY(cruiseY); goX(saved.x); goZ(saved.z); goY(saved.y)
end

-- Push dug junk (anything not in `wanted`) from the turtle into the ME system,
-- freeing inventory slots. Reliable underground where dropping in the world
-- isn't possible (solid rock all around).
local function dumpJunk()
  if not me then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not wanted[d.name] then
      turtle.select(s)
      pcall(me.importItem, { name = d.name, count = 9999 }, C.meExportDir)
    end
  end
end

local function restock()
  goHome()
  dumpJunk()                                  -- clear dug junk so there is room to refill
  if countItem(C.fuelItem) < 64 then pull(C.fuelItem, 128 - countItem(C.fuelItem)) end
  refuel()
  for key in pairs(usedKeys) do
    local id = C.blocks[key]
    if id then
      local have = countItem(id)
      if have < targets[key] then pull(id, targets[key] - have) end
    end
  end
  goBack()
end

-- When finished, dock and push every leftover item back into the ME system
-- (the turtle sits on the bridge, so importItem pulls "up" out of the turtle).
local function returnAll()
  if not me then return end
  goHome()
  print("returning leftovers to the ME system...")
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      local guard = 0
      while countItem(d.name) > 0 do
        local ok, n = pcall(me.importItem, { name = d.name, count = 9999 }, C.meExportDir)
        if not (ok and type(n) == "number" and n > 0) then
          guard = guard + 1
          if guard > 3 then break end
          sleep(0.3)
        end
      end
    end
  end
end

-- ----------------------------------------------------------------------
-- Placing + build
-- ----------------------------------------------------------------------
local function placeDownKey(key)
  local id = C.blocks[key]
  if not selectItem(id) then restock(); selectItem(id) end
  if turtle.detectDown() then
    local ok, data = turtle.inspectDown()
    if ok and data.name == id then return end
    turtle.digDown()
  end
  if not turtle.placeDown() then
    restock(); selectItem(id)
    if turtle.detectDown() then turtle.digDown() end
    turtle.placeDown()
  end
end

-- Out of fuel for real = tank below the mark AND no coal left to burn.
local function needFuel()
  if turtle.getFuelLevel() == "unlimited" then return false end
  refuel()
  return turtle.getFuelLevel() < C.fuelLowMark and countItem(C.fuelItem) == 0
end

local function build()
  for ly = 0, SZ.y - 1 do
    local flightY = O.y + ly + 1
    if needFuel() then restock() end          -- only return for fuel when truly out
    syncPos()                                 -- correct any drift before placing this layer
    goY(flightY)
    local fwdDir = true
    for lx = 0, SZ.x - 1 do
      local zs, ze, zstep = 0, SZ.z - 1, 1
      if not fwdDir then zs, ze, zstep = SZ.z - 1, 0, -1 end
      if me and freeSlots() <= 1 then restock() end   -- clear dug junk before slots clog
      goX(O.x + lx)
      for lz = zs, ze, zstep do
        goZ(O.z + lz)
        local key = blockAt(lx, ly, lz)
        if key then placeDownKey(key) end
      end
      fwdDir = not fwdDir
    end
    print(("layer %d/%d done"):format(ly + 1, SZ.y))
  end
end

-- ----------------------------------------------------------------------
-- Startup summary + go
-- ----------------------------------------------------------------------
local function summary()
  print("=== Reactor builder ===")
  print(("size %dx%dx%d at (%d,%d,%d)  %s/%s")
    :format(SZ.x, SZ.y, SZ.z, O.x, O.y, O.z, C.reactorType, C.fuelPattern))
  local stock = meStock()
  local grand = 0
  for key, n in pairs(totals) do
    grand = grand + n
    local id = C.blocks[key]
    if me and id then
      local have = stock[id] or 0
      local note = ""
      if have < n then note = (canCraft and craftable[id]) and "  (will craft)" or "  <-- SHORT" end
      print(("  %-12s need %5d  have %6d%s"):format(key, n, have, note))
    else
      print(("  %-12s need %5d   %s"):format(key, n, id or "?"))
    end
  end
  print(("  TOTAL blocks: %d"):format(grand))
  print(me and "ME Bridge: connected" or "ME Bridge: NOT FOUND - place the turtle on top of the bridge")
  if me then
    print("ME autocraft: " .. (canCraft and "available" or "NOT available (no craftItem method on this bridge)"))
  end
  if C.useGPS and not hasWirelessModem then
    print("GPS: no modem - running on dead reckoning (drift possible)")
  elseif C.useGPS then
    print("GPS: " .. (syncPos() and "locked (drift correction on)" or "NO FIX - check constellation"))
  else
    print("GPS: disabled (dead reckoning)")
  end
  print("Building in 5s (Ctrl+T to abort)...")
end

summary()
sleep(5)
syncPos()                 -- GPS fix before we start (auto-detects start position if available)
precraft(totals, C.blocks) -- kick off crafts for any shortfalls so they run in parallel
restock()                 -- fill up (and fuel) before the first layer
build()
if C.returnLeftovers then returnAll() else goHome() end   -- park on the dock, empty inventory
print("DONE. Insert fuel via the Access Port and activate the Controller.")
