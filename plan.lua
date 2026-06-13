--[[============================================================================
  plan.lua  -  Parametric Extreme Reactors block plan

  plan.new(config) returns an object describing what block belongs at every
  cell of the reactor bounding box, in LOCAL reactor coordinates:

      lx in [0 .. width-1]   (+x east)
      ly in [0 .. height-1]  (+y up)
      lz in [0 .. depth-1]   (+z south)

  Cell "kinds" returned by :blockAt(lx,ly,lz):
      "casing","glass","fuelRod","controlRod","coolant",
      "controller","powerTap","accessPort","computerPort", or nil (air)

  Convert a kind to an item id with :itemFor(kind).
============================================================================]]

local Plan = {}
Plan.__index = Plan

local SPECIAL_KINDS = {
  controller = true, powerTap = true, accessPort = true, computerPort = true,
}

function Plan.new(cfg)
  local self = setmetatable({}, Plan)
  self.cfg = cfg
  self.W = cfg.reactor.width
  self.H = cfg.reactor.height
  self.D = cfg.reactor.depth

  -- Precompute special-block overrides keyed "lx,ly,lz" -> kind
  self.specials = {}
  self.specialList = {}
  for _, s in ipairs(cfg.special or {}) do
    local lx, ly, lz
    ly = s.b
    if s.face == "north" then     lx, lz = s.a, 0
    elseif s.face == "south" then lx, lz = s.a, self.D - 1
    elseif s.face == "west"  then lx, lz = 0, s.a
    elseif s.face == "east"  then lx, lz = self.W - 1, s.a
    else error("special block: bad face '" .. tostring(s.face) .. "'") end
    local key = lx .. "," .. ly .. "," .. lz
    self.specials[key] = s.block
    table.insert(self.specialList,
      { lx = lx, ly = ly, lz = lz, kind = s.block, face = s.face })
  end
  return self
end

-- Is (lx,lz) an interior column that should be a vertical fuel-rod assembly?
function Plan:isFuelColumn(lx, lz)
  if lx < 1 or lx > self.W - 2 or lz < 1 or lz > self.D - 2 then return false end
  local ix, iz = lx - 1, lz - 1
  local p = self.cfg.fuelPattern
  if p == "full" then
    return true
  elseif p == "grid2" then
    return (ix % 2 == 0) and (iz % 2 == 0)
  else -- "checkerboard" (default)
    return (ix + iz) % 2 == 0
  end
end

-- Main query: what kind of block lives at this local cell?
function Plan:blockAt(lx, ly, lz)
  local W, H, D = self.W, self.H, self.D

  -- Special wall blocks win over everything on their cell.
  local sp = self.specials[lx .. "," .. ly .. "," .. lz]
  if sp then return sp end

  local atX = (lx == 0 or lx == W - 1)
  local atY = (ly == 0 or ly == H - 1)
  local atZ = (lz == 0 or lz == D - 1)
  local extremes = (atX and 1 or 0) + (atY and 1 or 0) + (atZ and 1 or 0)

  if extremes == 0 then
    -- Interior: fuel rod column or solid coolant
    return self:isFuelColumn(lx, lz) and "fuelRod" or "coolant"
  end

  if extremes >= 2 then
    -- Edge or corner: always casing
    return "casing"
  end

  -- A single face (extremes == 1)
  if ly == H - 1 then
    -- Ceiling: control rod directly above each fuel column, else casing
    if self:isFuelColumn(lx, lz) then return "controlRod" end
    return "casing"
  elseif ly == 0 then
    return "casing"            -- floor
  else
    -- Side wall (atX or atZ, interior height)
    return (self.cfg.wallBlock == "glass") and "glass" or "casing"
  end
end

function Plan:isSpecialKind(kind)
  return SPECIAL_KINDS[kind] == true
end

-- Map a cell kind to a concrete item id from config.blocks.
function Plan:itemFor(kind)
  if not kind then return nil end
  local id = self.cfg.blocks[kind]
  return id
end

-- Every (lx,lz) column in the bounding box, row-major with serpentine rows
-- (alternating direction) to shorten master->worker travel between columns.
function Plan:columnList()
  local out = {}
  for lz = 0, self.D - 1 do
    if lz % 2 == 0 then
      for lx = 0, self.W - 1 do out[#out + 1] = { lx = lx, lz = lz } end
    else
      for lx = self.W - 1, 0, -1 do out[#out + 1] = { lx = lx, lz = lz } end
    end
  end
  return out
end

-- The cells the MASTER must place by hand (special blocks).
function Plan:specialCells()
  return self.specialList
end

-- Convenience: which bulk item kinds appear in a given column (top..bottom),
-- ignoring special blocks (those are skipped by workers). Returns a set.
function Plan:columnKinds(lx, lz)
  local set = {}
  for ly = 0, self.H - 1 do
    local k = self:blockAt(lx, ly, lz)
    if k and not self:isSpecialKind(k) then set[k] = true end
  end
  return set
end

return Plan
