--[[============================================================================
  config.lua  -  Reactor swarm configuration
  --------------------------------------------------------------------------
  EDIT THIS FILE to match your world. Every tunable lives here.

  COORDINATE FRAME  (WORLD coordinates — units self-locate via GPS)
  ----------------
  Every position below is ad real Minecraft WORLD coordinate. Each unit gets a
  GPS fix at boot to learn where it is and which way it faces, so you need a
  GPS constellation in range of the build site. Press F3 in-game to read the
  coordinates you type in here.

  reactor.origin = the MIN corner of the reactor bounding box
                   (smallest x, smallest y, smallest z = bottom NW casing block).

  Axes:   +x = east,  +y = up,  +z = south   (standard Minecraft)
  Heading: 0 = north(-z), 1 = east(+x), 2 = south(+z), 3 = west(-x)
============================================================================]]

local C = {}

--==========================================================================
-- 1. REACTOR DIMENSIONS  (outer bounding box, INCLUDING the casing shell)
--==========================================================================
-- Max in this pack is 32 x 48 x 32. width/depth include the 2 wall blocks.
C.reactor = {
  origin = { x = -63, y = -8, z = -144 }, -- min corner; keep at 0,0,0 unless you know why not
  width  = 6,   -- size along x  (>=3, <=32)
  height = 6,   -- size along y  (>=3, <=48)
  depth  = 6,   -- size along z  (>=3, <=32)
}

--==========================================================================
-- 2. BLOCK / ITEM IDs
--==========================================================================
-- These are the registry names the ME Bridge and turtle.place use.
-- VERIFY them in-game: run `listitems.lua` on the depot computer to print the
-- exact names of everything in your ME system, then paste them here.
-- Defaults below are typical Extreme Reactors names but MAY differ in your pack.
C.blocks = {
  casing     = "bigreactors:reactor_casing",
  glass      = "bigreactors:reactor_glass",        -- used if wallBlock = "glass"
  fuelRod    = "bigreactors:reactor_fuelrod",
  controlRod = "bigreactors:reactor_controlrod",
  coolant    = "minecraft:iron_block",             -- your chosen SOLID coolant
  controller = "bigreactors:reactor_controller",
  powerTap   = "bigreactors:reactor_powertap_fe_active",
  accessPort = "bigreactors:reactor_accessport",
  -- optional, leave as nil to skip:
  computerPort = nil, -- e.g. "bigreactors:reactor_computerport"
}

-- Which block forms the four vertical WALLS: "casing" or "glass".
-- Floor and ceiling are always casing. Edges/corners are always casing.
C.wallBlock = "casing"

--==========================================================================
-- 3. INTERIOR FUEL PATTERN
--==========================================================================
-- "checkerboard" : fuel rod where (ix+iz) is even -> ~half the cells are fuel,
--                  each surrounded by coolant on 4 sides. Good general choice.
-- "grid2"        : fuel rod every other cell in both axes (ix even AND iz even).
--                  Fewer rods, more coolant, lower fuel use.
-- "full"         : every interior column is a fuel rod (max output, max fuel use,
--                  no solid coolant between rods).
C.fuelPattern = "checkerboard"

--==========================================================================
-- 4. SPECIAL BLOCKS (placed on a wall; at least 1 controller is REQUIRED)
--==========================================================================
-- Position is given as { face, a, b } where:
--   face = "north" | "south" | "east" | "west"  (which wall)
--   a,b  = offsets ALONG that wall and UP from the floor, measured from the
--          wall's min corner. a runs along the wall (1..len-2), b is height
--          above the floor (1..height-2). Must NOT be on an edge.
-- The master turtle carries and places these last.
C.special = {
  { block = "controller", face = "north", a = 2, b = 1 },
  { block = "powerTap",   face = "north", a = 4, b = 1 },
  { block = "accessPort", face = "north", a = 6, b = 1 },
}

--==========================================================================
-- 5. SWARM / DEPLOYMENT
--==========================================================================
C.swarm = {
  workerCount = 6,        -- how many worker turtles the master will deploy
  autoCollect = true,     -- after the build, master flies over each parked
                          -- worker and digs it up into its own inventory.
  -- Put the master a few blocks OUTSIDE the reactor footprint with clear air
  -- above it, so it and the workers can climb to flight level safely.
}

-- Fuel: workers can pull a burnable item from AE2 at the depot and burn it.
-- Set item = nil to disable (then give turtles fuel by hand / use a fuel mod).
C.fuel = {
  item        = "minecraft:coal", -- burnable item to pull from the ME system
  refuelBelow = 1000,                 -- top up when fuel level drops under this
  requestCount = 16,                  -- how many to pull per restock trip
}

C.master = {
  pos     = { x = -3, y = 0, z = -3 },
  heading = 1,            -- 1 = facing +x (east)
}

-- Workers are placed one at a time in a line starting here, stepping +x each.
-- Each placed worker boots, registers, and the master tells it this position.
C.staging = {
  pos     = { x = -3, y = 0, z = -1 }, -- first worker goes here
  step    = { x = 1,  y = 0, z = 0 },  -- offset between consecutive workers
  heading = 1,
}

--==========================================================================
-- 6. DEPOT / ME BRIDGE
--==========================================================================
-- The depot is a computer with an ME Bridge attached, next to a "dock" block
-- position where a worker parks to receive items. The ME Bridge exports items
-- into the docked turtle's inventory in `exportDir` (relative to the BRIDGE).
C.depot = {
  -- Coordinate the worker flies to and sits on to dock (its body occupies this).
  dock      = { x = -5, y = 0, z = 0 },
  -- Heading the worker faces while docked (cosmetic, keep consistent).
  heading   = 3,
  -- Direction the ME Bridge exports toward the docked turtle.
  -- One of: "up","down","north","south","east","west" (relative to the bridge).
  exportDir = "up",
  -- How full to top each bulk item, per restock (per item type).
  restockTo = 64,
}

--==========================================================================
-- 7. MOVEMENT / SAFETY
--==========================================================================
C.move = {
  -- Workers travel above the build at a personal altitude to avoid collisions:
  --   flightLevel(workerIndex) = reactor.height + flightBase + workerIndex
  flightBase     = 2,
  clearObstacles = true,   -- dig blocks that are in the way (terrain, leaves...)
  digFuelCost    = true,   -- refuel from inventory junk if it runs low
  fuelReserve    = 200,    -- refuel when fuel level drops below this
}

--==========================================================================
-- 8. NETWORKING
--==========================================================================
C.net = {
  protocol = "reactorSwarm",
  channel  = 4321,         -- informational; rednet uses protocol strings
  modemSide = nil,         -- nil = auto-detect any modem on the turtle/computer
}

return C
-- end of config.lua
