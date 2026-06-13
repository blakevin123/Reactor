--[[
  geo.lua  -  Pure direction / vector helpers.

  No turtle or peripheral calls, so this file loads safely on ANY computer
  (master turtle, worker turtle, or the stationary supply computer).

  Facing is an index 0..3 using the Minecraft compass:
      0 = north  (-Z)
      1 = east   (+X)
      2 = south  (+Z)
      3 = west   (-X)
  Turning right increments the index (clockwise viewed from above).
]]

local geo = {}

geo.names = { [0] = "north", [1] = "east", [2] = "south", [3] = "west" }

-- unit step (dx,dz) for each facing
geo.vecs = {
  [0] = { x =  0, z = -1 },
  [1] = { x =  1, z =  0 },
  [2] = { x =  0, z =  1 },
  [3] = { x = -1, z =  0 },
}

-- Find the facing index that matches a unit step, or nil.
function geo.fromVec(dx, dz)
  for i = 0, 3 do
    if geo.vecs[i].x == dx and geo.vecs[i].z == dz then return i end
  end
  return nil
end

function geo.right(f) return (f + 1) % 4 end
function geo.left(f)  return (f + 3) % 4 end

-- Number of right-turns (0..3) to get from facing a to facing b; choose the
-- shorter direction.  Returns turns, dir where dir is "right" or "left".
function geo.turnsTo(a, b)
  local d = (b - a) % 4
  if d == 3 then return 1, "left" end
  return d, "right"
end

return geo
