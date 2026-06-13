--[[
  config.lua  -  Shared configuration for the Reactor build swarm.

  This single file is loaded by master.lua, worker.lua and supply.lua so that
  every computer agrees on sizes, coordinates, block IDs and the rednet
  protocol.  Edit the values here, then re-copy this file to every computer
  (the disk bootstrap does that automatically for fresh workers).

  Load it with:   local cfg = dofile("/config.lua")

  -------------------------------------------------------------------------
  COORDINATE SYSTEM
  -------------------------------------------------------------------------
  All world coordinates are Minecraft block coordinates (the X/Y/Z shown by
  F3).  `origin` is the *minimum* corner of the reactor box, i.e. the block
  with the smallest X, Y and Z.  The reactor then occupies:
      x : origin.x .. origin.x + size.x - 1
      y : origin.y .. origin.y + size.y - 1   (y is height, bottom -> top)
      z : origin.z .. origin.z + size.z - 1
  The "front" face used for ports/controller is the minimum-Z face (z=origin.z).
]]

local cfg = {}

-------------------------------------------------------------------------
-- REACTOR GEOMETRY
-------------------------------------------------------------------------
-- Outer dimensions INCLUDING the casing shell.  Minimum 3, maximum is set by
-- the Extreme Reactors config in your pack (default "max reactor size" is
-- usually 32 wide/deep; height limit is often larger).  Verify in-game before
-- going huge -- an invalid multiblock will not form.
cfg.size = { x = 32, y = 32, z = 32 }

-- Minimum corner of the reactor in world coordinates.  CHANGE THIS to where
-- you want the reactor built.  Build site should be clear air (the turtles
-- WILL dig anything inside the build volume, but a clear site is faster/safer).
cfg.origin = { x = 0, y = 70, z = 0 }

-------------------------------------------------------------------------
-- FUEL / INTERIOR PATTERN
-------------------------------------------------------------------------
-- How the interior columns are filled.  A "fuel column" is a vertical line of
-- Reactor Fuel Rod blocks running the full interior height, capped by a
-- Control Rod in the top face directly above it.
--   "checkerboard" : fuel on every other column (fuel surrounded by coolant/air)
--                    -> better fuel efficiency, recommended.
--   "full"         : every interior column is fuel -> max fuel, max heat.
--   "spaced"       : fuel every `fuelSpacing` columns in both axes.
cfg.fuelPattern = "checkerboard"
cfg.fuelSpacing = 2            -- only used when fuelPattern == "spaced"

-- If you want SOLID coolant/moderator blocks placed in the non-fuel interior
-- cells, set cfg.blocks.coolant below to a block ID.  Leave it nil for a
-- passively-cooled reactor with an empty (air) interior.

-------------------------------------------------------------------------
-- BLOCK IDS  (VERIFY THESE FOR YOUR PACK!)
-------------------------------------------------------------------------
-- These are the Extreme Reactors ("bigreactors") IDs.  They MAY differ in your
-- exact ATM10 version.  To check one in game: hold the block and press F3+H to
-- enable "Advanced tooltips", the registry name shows under the item name.
-- supply.lua will also print a warning at startup for any ID it can't find in
-- the ME system, so you can catch typos before building.
cfg.blocks = {
  casing      = "bigreactors:reactorcasing",      -- walls, edges, corners
  glass       = "bigreactors:reactorglass",       -- optional see-through walls
  fuelRod     = "bigreactors:reactorfuelrod",     -- interior fuel columns
  controlRod  = "bigreactors:reactorcontrolrod",  -- top face, above each column
  controller  = "bigreactors:reactorcontroller",  -- exactly one required
  powerTap    = "bigreactors:reactorpowertapfe",  -- passive: FE output
  accessPort  = "bigreactors:reactoraccessport",  -- fuel in / waste out
  computerPort= "bigreactors:reactorcomputerport",-- optional CC control port
  coolantPort = "bigreactors:reactorcoolantport", -- active cooling only
  coolant     = nil,                              -- e.g. "minecraft:water" / a moderator block, or nil for air
}

-- Use glass for the (non-port) side walls so you can see inside.  Edges/top/
-- bottom stay casing regardless.
cfg.useGlassWalls = false

-- Reactor type:
--   "passive" : uses powerTap(s), empty interior   (simplest, recommended)
--   "active"  : uses coolantPort(s), fluid/coolant interior
cfg.reactorType = "passive"

-------------------------------------------------------------------------
-- COMPONENT PLACEMENT  (positions on the front / min-Z face)
-------------------------------------------------------------------------
-- Each entry is a cell on the front face given as LOCAL face coordinates:
--   lx = 1 .. size.x-2   (left..right along the face)
--   ly = 1 .. size.y-2   (bottom..top of the face)
-- They must be distinct cells and must fit inside the face.  Defaults assume
-- size.x and size.y are >= 4.  Set a value to nil to omit that component.
cfg.components = {
  controller   = { lx = 1,              ly = 1 },               -- REQUIRED
  powerTap     = { lx = "size.x-2",     ly = 1 },               -- passive output
  accessPort   = { lx = 1,              ly = "size.y-2" },      -- fuel/waste
  computerPort = { lx = "size.x-2",     ly = "size.y-2" },      -- optional
  -- For active cooling, the layout substitutes coolantPort for powerTap and
  -- adds a second coolant port automatically (see layout.lua).
}

-------------------------------------------------------------------------
-- SWARM / STATIONS
-------------------------------------------------------------------------
cfg.workerCount = 4            -- how many worker turtles to run

-- Unique transit altitude per worker = cruiseBaseY + workerIndex.  Must be
-- ABOVE the finished reactor so turtles never collide in transit.  Give it
-- plenty of headroom above origin.y + size.y.
cfg.cruiseBaseY = nil          -- nil = auto (origin.y + size.y + 4)

-- SUPPLY STATION (the ME Bridge dock).  See README for the physical build.
-- `dock` is the world cell a worker sits in to draw items: it must be the
-- block directly ABOVE the supply chest (which is directly above the ME
-- Bridge).  Workers descend here, then turtle.suckDown() from the chest.
cfg.station = {
  dock = { x = -4, y = 72, z = 0 },   -- worker stands here, sucks DOWN
  -- The supply computer exports into the chest below the dock with this
  -- direction relative to the ME Bridge.  With chest-on-top-of-bridge it's "up".
  bridgeExportDir = "up",
  -- Optional junk barrel the ME Bridge imports from when workers dump mined
  -- blocks.  Set junkDock to a world cell above a barrel, or nil to disable
  -- junk return (workers will just keep mined blocks until full).
  junkDock = nil,                     -- e.g. { x = -4, y = 72, z = 2 }
  bridgeImportDir = "north",
}

-- PROGRAMMING DOCK (only used when master autoDeploy is on).  The cell where
-- the master places each fresh worker.  A disk drive holding the worker disk
-- must sit on one horizontal side of this cell.  The master must be positioned
-- directly ABOVE this cell so it can placeDown a new turtle into it.
cfg.autoDeploy = false         -- true = master physically places worker turtles
cfg.progDock   = { x = -4, y = 74, z = 0 }

-------------------------------------------------------------------------
-- TURTLE INVENTORY SLOT MAP
-------------------------------------------------------------------------
-- Which inventory slot each block key lives in on a worker.  Components are
-- single blocks so they share the high slots; bulk blocks get their own slot
-- and are refilled to a full stack on demand.  Slot 16 is reserved for fuel.
cfg.slots = {
  casing      = 1,
  glass       = 2,
  fuelRod     = 3,
  controlRod  = 4,
  coolant     = 5,
  controller  = 6,
  powerTap    = 7,
  accessPort  = 8,
  computerPort= 9,
  coolantPort = 10,
  fuel        = 16,
}
cfg.fuelItem      = "minecraft:charcoal"  -- what workers refuel with
cfg.fuelLowMark   = 200                   -- refuel when fuel level drops below this
cfg.fuelPerTrip   = 64                    -- charcoal to draw per restock

-------------------------------------------------------------------------
-- REDNET PROTOCOL
-------------------------------------------------------------------------
cfg.protocol   = "reactorswarm"
cfg.masterName = "master"      -- rednet.host name for the master
cfg.supplyName = "supply"      -- rednet.host name for the supply server

-- Message types (kept here so all programs agree)
cfg.msg = {
  REGISTER   = "register",     -- worker -> master  {id}
  ASSIGN     = "assign",       -- master -> worker  {strip, cruiseY, index}
  PROGRESS   = "progress",     -- worker -> master  {id, layer, placed}
  DONE       = "done",         -- worker -> master  {id}
  DOCK_REQ   = "dock_req",     -- worker -> supply
  DOCK_GRANT = "dock_grant",   -- supply -> worker
  DOCK_REL   = "dock_release", -- worker -> supply
  EXPORT_REQ = "export_req",   -- worker -> supply  {item, count}
  EXPORT_DONE= "export_done",  -- supply -> worker  {item, exported}
  DUMP_REQ   = "dump_req",     -- worker -> supply  (import junk now)
  DUMP_DONE  = "dump_done",
}

-- Helper: resolve a component coordinate that may be the string "size.x-2" etc.
function cfg.resolve(v)
  if type(v) == "number" then return v end
  if v == "size.x-2" then return cfg.size.x - 2 end
  if v == "size.y-2" then return cfg.size.y - 2 end
  if v == "size.z-2" then return cfg.size.z - 2 end
  error("unknown coordinate expression: " .. tostring(v))
end

function cfg.cruiseY()
  return cfg.cruiseBaseY or (cfg.origin.y + cfg.size.y + 4)
end

return cfg
