--[[
  master.lua  -  Worker deployer (runs on the master turtle).

  Sits next to HOME (the cell on top of the home ME Bridge, with the disk drive
  on home's other side). Places blank worker turtles into HOME one at a time;
  each boots, copies the program off the disk, refuels on the home bridge, and
  flies off to its chunk - then the master places the next.

  SETUP
    - Load a stack of blank worker turtles (each crafted WITH a pickaxe + an
      ender/wireless modem) into the master's inventory.
    - Position the master so HOME is directly to its LEFT.
    - Build HOME: worker cell on top of an ME Bridge, disk drive on a side of it
      holding the worker disk (startup.lua + worker.lua + turtle_config.lua).

  Run:  master            (deploys CONFIG.count workers)
]]

local CONFIG = {
  count = 8,            -- how many workers to deploy
  leaveTimeout = 90,    -- seconds to wait for a placed worker to program & leave
}

local function selectTurtle()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and type(d.name) == "string" and d.name:find("computercraft:turtle") then
      turtle.select(s); return true
    end
  end
  return false
end

print("master: deploying " .. CONFIG.count .. " workers to HOME (left)")
turtle.turnLeft()                                   -- face HOME

for i = 1, CONFIG.count do
  if not selectTurtle() then
    print("out of worker turtles - load more into the master")
    while not selectTurtle() do sleep(2) end
  end

  -- wait for HOME to be clear (never dig a turtle that's still there)
  while turtle.detect() do
    local ok, d = turtle.inspect()
    if ok and d.name and d.name:find("computercraft") then sleep(1) else turtle.dig() end
  end

  if turtle.place() then
    print(("placed worker %d/%d - waiting for it to program & leave"):format(i, CONFIG.count))
    local t = os.clock()
    while turtle.detect() and (os.clock() - t) < CONFIG.leaveTimeout do sleep(1) end
    sleep(2)
  else
    print("could not place worker - retrying")
    sleep(2)
  end
end

turtle.turnRight()                                  -- restore facing
print("master: deployment finished")
