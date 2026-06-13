--[[============================================================================
  nav.lua  -  Dead-reckoning movement with obstacle clearing

  Each unit calibrates its absolute position + heading once at boot via a GPS
  fix (Nav.fromGPS), then tracks every move by dead reckoning. So you need a
  GPS constellation in range, and all config coordinates are WORLD coordinates.
  (If you really have no GPS, you can build a Nav with Nav.new(pos,heading,cfg)
  and place every unit facing a known heading by hand.)

  Heading: 0 = north(-z), 1 = east(+x), 2 = south(+z), 3 = west(-x)

  Safety: it will NOT dig another turtle/computer out of the way (so the swarm
  doesn't eat itself) -- it waits for the other unit to move instead. Terrain,
  leaves, etc. are dug if config.move.clearObstacles is true.
============================================================================]]

local Nav = {}
Nav.__index = Nav

local DIR = { [0] = {0,0,-1}, [1] = {1,0,0}, [2] = {0,0,1}, [3] = {-1,0,0} }

function Nav.new(pos, heading, cfg)
  local self = setmetatable({}, Nav)
  self.x, self.y, self.z = pos.x, pos.y, pos.z
  self.h = heading or 0
  self.cfg = cfg
  return self
end

function Nav:where() return self.x, self.y, self.z, self.h end

--------------------------------------------------------------------------
-- GPS calibration  (recommended; needs a GPS constellation in range)
-- Locates the turtle and works out its facing by moving one block and
-- comparing GPS fixes. All config coordinates are then WORLD coordinates.
--------------------------------------------------------------------------
function Nav.fromGPS(cfg)
  local x, y, z = gps.locate(4)
  if not x then
    error("GPS not available. Build a GPS constellation, or use Nav.new with a known start.")
  end
  local self = Nav.new({ x = x, y = y, z = z }, 0, cfg)
  local moved = false
  for _ = 1, 4 do
    if turtle.forward() then moved = true; break end
    if cfg.move.clearObstacles and turtle.detect() then
      turtle.dig()
      if turtle.forward() then moved = true; break end
    end
    turtle.turnRight()
  end
  if not moved then error("calibration: give the turtle clear air to move one block") end
  local x2, _, z2 = gps.locate(4)
  if not x2 then error("calibration: lost GPS after moving") end
  local dx, dz = x2 - x, z2 - z
  local h
  if dx == 1 then h = 1 elseif dx == -1 then h = 3
  elseif dz == 1 then h = 2 elseif dz == -1 then h = 0
  else error("calibration: GPS showed no movement") end
  self.x, self.y, self.z, self.h = x2, y, z2, h
  return self
end

--------------------------------------------------------------------------
-- Fuel
--------------------------------------------------------------------------
function Nav:ensureFuel()
  local lvl = turtle.getFuelLevel()
  if lvl == "unlimited" then return true end
  if lvl >= (self.cfg.move.fuelReserve or 200) then return true end
  -- Try to burn anything combustible we happen to carry.
  for s = 1, 16 do
    turtle.select(s)
    if turtle.refuel(1) then
      while turtle.refuel(1) do end
      if turtle.getFuelLevel() >= (self.cfg.move.fuelReserve or 200) then
        turtle.select(1); return true
      end
    end
  end
  turtle.select(1)
  return turtle.getFuelLevel() > 0
end

--------------------------------------------------------------------------
-- Low-level guarded step
--------------------------------------------------------------------------
local function isUnit(name)
  if not name then return false end
  return name:find("turtle") ~= nil or name:find("computer") ~= nil
end

function Nav:_step(moveFn, detectFn, digFn, attackFn, inspectFn, dx, dy, dz)
  local attempts = 0
  while true do
    self:ensureFuel()
    if moveFn() then
      self.x = self.x + dx; self.y = self.y + dy; self.z = self.z + dz
      return true
    end
    attempts = attempts + 1
    if attempts > 240 then return false, "stuck" end
    if detectFn() then
      local ok, data = inspectFn()
      local name = ok and data and data.name or nil
      if isUnit(name) then
        sleep(0.5)               -- another swarm unit; let it pass
      elseif self.cfg.move.clearObstacles then
        digFn()
      else
        return false, "blocked"
      end
    else
      attackFn()                 -- probably a mob; shove it
      sleep(0.2)
    end
  end
end

--------------------------------------------------------------------------
-- Turning
--------------------------------------------------------------------------
function Nav:turnRight() turtle.turnRight(); self.h = (self.h + 1) % 4 end
function Nav:turnLeft()  turtle.turnLeft();  self.h = (self.h + 3) % 4 end

function Nav:face(target)
  target = target % 4
  local diff = (target - self.h) % 4
  if diff == 1 then self:turnRight()
  elseif diff == 2 then self:turnRight(); self:turnRight()
  elseif diff == 3 then self:turnLeft() end
end

--------------------------------------------------------------------------
-- Single-block moves
--------------------------------------------------------------------------
function Nav:forward()
  local d = DIR[self.h]
  return self:_step(turtle.forward, turtle.detect, turtle.dig, turtle.attack,
                    turtle.inspect, d[1], d[2], d[3])
end

function Nav:up()
  return self:_step(turtle.up, turtle.detectUp, turtle.digUp, turtle.attackUp,
                    turtle.inspectUp, 0, 1, 0)
end

function Nav:down()
  return self:_step(turtle.down, turtle.detectDown, turtle.digDown,
                    turtle.attackDown, turtle.inspectDown, 0, -1, 0)
end

--------------------------------------------------------------------------
-- Multi-block helpers
--------------------------------------------------------------------------
function Nav:goY(ty)
  while self.y < ty do if not self:up() then return false end end
  while self.y > ty do if not self:down() then return false end end
  return true
end

function Nav:goXZ(tx, tz)
  -- x first
  while self.x ~= tx do
    self:face(self.x < tx and 1 or 3)
    if not self:forward() then return false end
  end
  -- then z
  while self.z ~= tz do
    self:face(self.z < tz and 2 or 0)
    if not self:forward() then return false end
  end
  return true
end

-- Travel to (tx,ty,tz). `travelY` (optional) is a safe altitude to rise to
-- before moving horizontally, so we fly OVER the structure rather than through.
function Nav:goTo(tx, ty, tz, travelY)
  if travelY then
    if not self:goY(math.max(self.y, travelY)) then return false end
  end
  if not self:goXZ(tx, tz) then return false end
  if not self:goY(ty) then return false end
  return true
end

return Nav
