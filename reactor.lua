--[[
  reactor.lua  -  Single-turtle Extreme Reactors builder.

  One mining turtle builds the whole reactor by itself and restocks blocks +
  fuel directly from an Advanced Peripherals ME Bridge at a dock. No GPS, no
  rednet, no second computer.

  HOW IT NAVIGATES
    The turtle tracks its own position by dead reckoning, starting from the
    coordinates you give in CONFIG.start. So you must PLACE the turtle on that
    exact block, FACING the direction you set, before running. (Press F3 to
    read the block coords; the small "Facing" line tells you the direction.)

  HOW IT RESTOCKS (the dock)  -- vertical stack, simplest layout:
        [ turtle home cell ]   <- CONFIG.home (turtle sits here, sucks DOWN)
        [ chest / barrel    ]   <- ME Bridge fills this; turtle suckDown()s it
        [ ME Bridge         ]   <- exports "up" into the chest
    For the turtle to COMMAND the bridge it must be on the bridge's wired
    network: give the turtle a Wired Modem upgrade (plus a pickaxe), put a
    wired modem on the ME Bridge, and run a cable to a wired modem block next to
    the home cell. If you'd rather not bother, set CONFIG.useMEBridge=false and
    just keep the dock chest filled yourself (export bus / by hand) - the turtle
    will simply suckDown from it.

  EQUIP: a pickaxe (to dig/clear) and, if useMEBridge, a wired modem.
  FUEL : put coal/charcoal in slot 16 to start; it refuels itself at the dock.

  Install on the turtle:
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
  origin = { x = 0, y = 70, z = 0 },

  -- Where the turtle is PLACED and which way it faces, in world coords.
  -- facing is one of: "north" (-Z), "south" (+Z), "east" (+X), "west" (-X).
  start = { x = 0, y = 73, z = -2, facing = "south" },

  -- The dock cell the turtle returns to for restock (usually same as start).
  -- It sucks items from the block directly BELOW this cell.
  home = { x = 0, y = 73, z = -2 },

  -- Transit altitude for moving to/from the dock. Must be ABOVE the reactor.
  -- nil = auto (origin.y + size.y + 3).
  cruiseY = nil,

  -- Fuel-column pattern: "checkerboard" | "full" | "spaced".
  fuelPattern = "checkerboard",
  fuelSpacing = 2,

  reactorType  = "passive",      -- "passive" | "active"
  useGlassWalls = false,

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
    coolant      = nil,
  },

  -- Components on the front (min-Z) face. lx=1..size.x-2, ly=1..size.y-2.
  -- Use the strings below for "size.x-2"/"size.y-2", or plain numbers.
  components = {
    controller   = { lx = 1,          ly = 1 },
    powerTap     = { lx = "size.x-2", ly = 1 },
    accessPort   = { lx = 1,          ly = "size.y-2" },
    computerPort = { lx = "size.x-2", ly = "size.y-2" },
  },

  -- Inventory slots. Slot 16 reserved for fuel.
  slots = {
    casing = 1, glass = 2, fuelRod = 3, controlRod = 4, coolant = 5,
    controller = 6, powerTap = 7, accessPort = 8, computerPort = 9,
    coolantPort = 10, fuel = 16,
  },

  fuelItem    = "minecraft:coal",
  fuelLowMark = 1000,            -- refuel/return when fuel drops below this

  -- ME Bridge dock plumbing.
  useMEBridge = true,            -- false = just suckDown from a pre-filled chest
  meExportDir = "up",           -- direction the BRIDGE pushes items (into the chest)
}
-- ======================================================================

-- ----------------------------------------------------------------------
-- Direction helpers
-- ----------------------------------------------------------------------
local FNAME = { north = 0, east = 1, south = 2, west = 3 }
local VEC   = { [0]={x=0,z=-1}, [1]={x=1,z=0}, [2]={x=0,z=1}, [3]={x=-1,z=0} }

local C   = CONFIG
local SZ  = C.size
local O   = C.origin
local SINGLE = { controller=true, powerTap=true, accessPort=true, computerPort=true, coolantPort=true }

local function resolve(v)
  if type(v) == "number" then return v end
  if v == "size.x-2" then return SZ.x - 2 end
  if v == "size.y-2" then return SZ.y - 2 end
  if v == "size.z-2" then return SZ.z - 2 end
  error("bad coord expr: " .. tostring(v))
end

local cruiseY = C.cruiseY or (O.y + SZ.y + 3)

-- ----------------------------------------------------------------------
-- State + movement (dead reckoning; digs anything in the way)
-- ----------------------------------------------------------------------
local pos    = { x = C.start.x, y = C.start.y, z = C.start.z }
local facing = FNAME[C.start.facing] or error("start.facing must be north/south/east/west")

local function refuel()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() > C.fuelLowMark then return end
  local keep = turtle.getSelectedSlot()
  turtle.select(C.slots.fuel)
  while turtle.getFuelLevel() <= C.fuelLowMark and turtle.getItemCount(C.slots.fuel) > 0 do
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

-- Resolve component cells on the front face into a lookup "lx:ly" -> key.
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

-- Set of keys actually used, and total count per key.
local totals, usedKeys = {}, {}
for lx = 0, SZ.x-1 do for ly = 0, SZ.y-1 do for lz = 0, SZ.z-1 do
  local k = blockAt(lx, ly, lz)
  if k then totals[k] = (totals[k] or 0) + 1; usedKeys[k] = true end
end end end

-- ----------------------------------------------------------------------
-- ME Bridge dock
-- ----------------------------------------------------------------------
local me = C.useMEBridge and (peripheral.find("me_bridge")) or nil

local function meStock()
  local map = {}
  if not me then return map end
  local ok, items = pcall(me.getItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do if it.name then map[it.name] = it.count or it.amount or 0 end end
  end
  return map
end

-- Pull `want` of itemId into `slot` via the dock chest below the turtle.
local function pullInto(slot, itemId, want)
  if want <= 0 then return 0 end
  turtle.select(slot)
  local before = turtle.getItemCount(slot)
  if me then pcall(me.exportItem, { name = itemId, count = want }, C.meExportDir) end
  local target = math.min(64, before + want)
  local guard = 0
  while turtle.getItemCount(slot) < target do
    if not turtle.suckDown() then
      guard = guard + 1
      if guard > 4 then break end
      sleep(0.2)
    end
  end
  return turtle.getItemCount(slot) - before
end

local saved
local function goHome()
  saved = { x = pos.x, y = pos.y, z = pos.z }
  goY(cruiseY); goX(C.home.x); goZ(C.home.z); goY(C.home.y)
end
local function goBack()
  goY(cruiseY); goX(saved.x); goZ(saved.z); goY(saved.y)
end

local function restock()
  goHome()
  -- fuel
  if turtle.getItemCount(C.slots.fuel) < 16 then pullInto(C.slots.fuel, C.fuelItem, 64) end
  refuel()
  -- blocks
  for key in pairs(usedKeys) do
    local slot, id = C.slots[key], C.blocks[key]
    if slot and id then
      local target = SINGLE[key] and 4 or 64
      local have = turtle.getItemCount(slot)
      if have < target then pullInto(slot, id, target - have) end
    end
  end
  goBack()
end

local function ensure(key)
  if turtle.getItemCount(C.slots[key]) == 0 then restock() end
end

-- ----------------------------------------------------------------------
-- Placing + build
-- ----------------------------------------------------------------------
local function placeDownKey(key)
  ensure(key)
  local slot = C.slots[key]
  turtle.select(slot)
  if turtle.detectDown() then
    local ok, data = turtle.inspectDown()
    if ok and data.name == C.blocks[key] then return end
    turtle.digDown()
  end
  if not turtle.placeDown() then
    ensure(key); turtle.select(slot)
    if turtle.detectDown() then turtle.digDown() end
    turtle.placeDown()
  end
end

local function lowOnStock()
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < C.fuelLowMark then return true end
  for key in pairs(usedKeys) do
    if not SINGLE[key] and turtle.getItemCount(C.slots[key]) < 8 then return true end
  end
  return false
end

local function build()
  for ly = 0, SZ.y - 1 do
    local flightY = O.y + ly + 1
    if lowOnStock() then restock() end
    goY(flightY)
    local fwdDir = true
    for lx = 0, SZ.x - 1 do
      local zs, ze, zstep = 0, SZ.z - 1, 1
      if not fwdDir then zs, ze, zstep = SZ.z - 1, 0, -1 end
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
  print(("=== Reactor builder ==="))
  print(("size %dx%dx%d at (%d,%d,%d)  %s/%s")
    :format(SZ.x, SZ.y, SZ.z, O.x, O.y, O.z, C.reactorType, C.fuelPattern))
  local stock = meStock()
  local grand = 0
  for key, n in pairs(totals) do
    grand = grand + n
    local id = C.blocks[key]
    if me and id then
      local have = stock[id] or 0
      local flag = (have < n) and "  <-- SHORT" or ""
      print(("  %-12s need %5d  have %6d%s"):format(key, n, have, flag))
    else
      print(("  %-12s need %5d   %s"):format(key, n, id or "?"))
    end
  end
  print(("  TOTAL blocks: %d"):format(grand))
  if me then print("ME Bridge: connected") else
    print(C.useMEBridge and "ME Bridge: NOT FOUND (equip wired modem / check network)"
                        or  "ME Bridge: disabled - turtle will suck from the dock chest")
  end
  print("Place confirmed at " .. C.start.x .. "," .. C.start.y .. "," .. C.start.z ..
        " facing " .. C.start.facing .. "? Building in 5s (Ctrl+T to abort)...")
end

summary()
sleep(5)
restock()      -- fill up before the first layer
build()
goHome()       -- park at the dock
print("DONE. Insert fuel via the Access Port and activate the Controller.")
