--[[
  layout.lua  -  Generates the Extreme Reactors multiblock schematic.

  The reactor is a hollow rectangular box:
    * The 12 EDGES (and 8 corners) must be Reactor Casing.
    * The 6 FACES can be casing / glass, with components (controller, taps,
      ports) substituted on the chosen "front" (min-Z) face, and Control Rods
      placed on the TOP face directly above each fuel column.
    * The INTERIOR holds vertical fuel-rod columns (full interior height) in a
      configurable pattern; the rest is coolant block (if set) or air.

  The single source of truth is layout.blockAt(cfg, lx, ly, lz) which returns a
  block KEY (an index into cfg.blocks) or nil for "leave empty / air".

  Local coordinates lx,ly,lz are 0-based offsets from cfg.origin:
      lx in 0..size.x-1 ,  ly in 0..size.y-1 ,  lz in 0..size.z-1

  Loaded with:  local layout = dofile("/layout.lua")
]]

local layout = {}

-- ---------------------------------------------------------------------------
-- Fuel-column pattern.  Only meaningful for interior (lx,lz) cells, i.e.
-- lx in 1..size.x-2 and lz in 1..size.z-2.
-- ---------------------------------------------------------------------------
function layout.isFuelColumn(cfg, lx, lz)
  local p = cfg.fuelPattern
  if p == "full" then
    return true
  elseif p == "spaced" then
    local s = cfg.fuelSpacing or 2
    return ((lx - 1) % s == 0) and ((lz - 1) % s == 0)
  else -- "checkerboard" (default)
    return ((lx + lz) % 2) == 0
  end
end

-- ---------------------------------------------------------------------------
-- Resolved component positions on the front (min-Z) face.  Returns a list of
-- { key=, lx=, ly= } after substituting active-vs-passive parts.
-- ---------------------------------------------------------------------------
local function resolvedComponents(cfg)
  local out = {}
  for key, pos in pairs(cfg.components) do
    if pos then
      local realKey = key
      -- For active cooling, swap the FE power tap for a coolant port.
      if key == "powerTap" and cfg.reactorType == "active" then
        realKey = "coolantPort"
      end
      table.insert(out, { key = realKey, lx = cfg.resolve(pos.lx), ly = cfg.resolve(pos.ly) })
    end
  end
  -- Active reactors need an IN and an OUT coolant port; add a second one
  -- opposite the first if we only have one defined.
  if cfg.reactorType == "active" then
    local ports = 0
    for _, c in ipairs(out) do if c.key == "coolantPort" then ports = ports + 1 end end
    if ports == 1 then
      table.insert(out, { key = "coolantPort", lx = math.floor(cfg.size.x / 2), ly = 1 })
    end
  end
  return out
end

-- Cache resolved components per cfg table so blockAt stays cheap.
local compCache = setmetatable({}, { __mode = "k" })
local function componentAt(cfg, lx, ly, lz)
  if lz ~= 0 then return nil end                          -- front face only
  if lx == 0 or lx == cfg.size.x - 1 then return nil end  -- not on an edge
  if ly == 0 or ly == cfg.size.y - 1 then return nil end
  local list = compCache[cfg]
  if not list then list = resolvedComponents(cfg); compCache[cfg] = list end
  for _, c in ipairs(list) do
    if c.lx == lx and c.ly == ly then return c.key end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Block at a local cell.  Returns a key into cfg.blocks, or nil for air.
-- ---------------------------------------------------------------------------
function layout.blockAt(cfg, lx, ly, lz)
  local sx, sy, sz = cfg.size.x, cfg.size.y, cfg.size.z
  local minx, maxx = (lx == 0), (lx == sx - 1)
  local miny, maxy = (ly == 0), (ly == sy - 1)
  local minz, maxz = (lz == 0), (lz == sz - 1)
  local extremes = (minx and 1 or 0) + (maxx and 1 or 0)
                 + (miny and 1 or 0) + (maxy and 1 or 0)
                 + (minz and 1 or 0) + (maxz and 1 or 0)

  if extremes >= 2 then
    return "casing"                 -- every edge & corner

  elseif extremes == 1 then         -- a flat face
    local comp = componentAt(cfg, lx, ly, lz)
    if comp then return comp end
    if maxy and layout.isFuelColumn(cfg, lx, lz) then
      return "controlRod"           -- top face cap above a fuel column
    end
    if cfg.useGlassWalls and not miny and not maxy then
      return "glass"                -- see-through side walls only
    end
    return "casing"

  else                              -- interior
    if layout.isFuelColumn(cfg, lx, lz) then
      return "fuelRod"
    elseif cfg.blocks.coolant then
      return "coolant"
    else
      return nil                    -- empty interior (passive)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Totals: how many of each block key the whole reactor needs.
-- ---------------------------------------------------------------------------
function layout.totals(cfg)
  local t = {}
  for lx = 0, cfg.size.x - 1 do
    for ly = 0, cfg.size.y - 1 do
      for lz = 0, cfg.size.z - 1 do
        local k = layout.blockAt(cfg, lx, ly, lz)
        if k then t[k] = (t[k] or 0) + 1 end
      end
    end
  end
  return t
end

-- ---------------------------------------------------------------------------
-- Partition the footprint into N contiguous strips along the longer axis.
-- Each worker owns a strip = a range of lx (or lz) across the full other axis
-- and the full height.  Strips never share a column, so workers building with
-- placeDown can never collide horizontally.  Returns a list of:
--   { axis = "x"|"z", lo =, hi = }   (inclusive local bounds on that axis)
-- ---------------------------------------------------------------------------
function layout.partition(cfg, n)
  local axis = (cfg.size.x >= cfg.size.z) and "x" or "z"
  local span = (axis == "x") and cfg.size.x or cfg.size.z
  n = math.max(1, math.min(n, span))
  local strips = {}
  local base = math.floor(span / n)
  local extra = span % n
  local cur = 0
  for i = 1, n do
    local w = base + (i <= extra and 1 or 0)
    table.insert(strips, { axis = axis, lo = cur, hi = cur + w - 1 })
    cur = cur + w
  end
  return strips
end

-- ---------------------------------------------------------------------------
-- Basic sanity check of the configuration; returns ok, message.
-- ---------------------------------------------------------------------------
function layout.validate(cfg)
  local s = cfg.size
  if s.x < 3 or s.y < 3 or s.z < 3 then
    return false, "reactor must be at least 3x3x3"
  end
  -- components must fit on the face and be unique cells
  local seen = {}
  for _, c in ipairs(resolvedComponents(cfg)) do
    if c.lx < 1 or c.lx > s.x - 2 or c.ly < 1 or c.ly > s.y - 2 then
      return false, ("component %s at (%d,%d) is off the front face"):format(c.key, c.lx, c.ly)
    end
    local id = c.lx .. ":" .. c.ly
    if seen[id] then
      return false, ("two components share front-face cell (%d,%d)"):format(c.lx, c.ly)
    end
    seen[id] = true
  end
  -- need a controller
  local hasController = false
  for _, c in ipairs(resolvedComponents(cfg)) do
    if c.key == "controller" then hasController = true end
  end
  if not hasController then return false, "no reactor controller defined in cfg.components" end
  return true, "ok"
end

return layout
