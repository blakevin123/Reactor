--[[
  master.lua  -  Worker deployer + collector (runs on the master turtle).

  Phase 1 - DEPLOY: places blank worker turtles into HOME (to its left) one at a
  time; each boots, copies the program off the disk, refuels on the home bridge,
  and flies off to its chunk.

  Phase 2 - COLLECT: when workers finish, the server sends them back to HOME one
  at a time; the master mines each one up (back into its inventory as a blank,
  reusable turtle).

  SETUP
    - Load a stack of blank worker turtles (each crafted WITH a pickaxe + ender
      modem) into the master's inventory.
    - Position the master so HOME is directly to its LEFT.
    - Build HOME: worker cell on top of an ME Bridge, disk drive on a side with
      the worker disk (startup.lua + worker.lua + turtle_config.lua).
    - Copy turtle_config.lua onto the master too (it needs the server URL).

  Run:  master
]]

local CONFIG = {
  count = 8,            -- how many workers to deploy
  leaveTimeout = 90,    -- seconds to wait for a placed worker to program & leave
}

local TC = fs.exists("/turtle_config.lua") and dofile("/turtle_config.lua") or {}
local SERVER = (TC.server or "http://127.0.0.1:8080"):gsub("/$", "")

local function httpJSON(method, path, body)
  for _ = 1, 5 do
    local resp
    if method == "POST" then
      resp = http.post(SERVER .. path, textutils.serialiseJSON(body or {}), { ["Content-Type"] = "application/json" })
    else
      resp = http.get(SERVER .. path)
    end
    if resp then
      local s = resp.readAll(); resp.close()
      local ok, t = pcall(textutils.unserialiseJSON, s)
      return ok and t or nil
    end
    sleep(1)
  end
  return nil
end

local function selectTurtle()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and type(d.name) == "string" and d.name:find("computercraft:turtle") then
      turtle.select(s); return true
    end
  end
  return false
end

-- ===========================================================================
-- Phase 1: deploy
-- ===========================================================================
print("master: deploying " .. CONFIG.count .. " workers to HOME (left)")
turtle.turnLeft()                                   -- face HOME (kept for collection)

for i = 1, CONFIG.count do
  if not selectTurtle() then
    print("out of worker turtles - load more into the master")
    while not selectTurtle() do sleep(2) end
  end
  while turtle.detect() do                           -- wait for HOME to clear
    local ok, d = turtle.inspect()
    if ok and d.name and d.name:find("computercraft") then sleep(1) else turtle.dig() end
  end
  if turtle.place() then
    print(("placed worker %d/%d"):format(i, CONFIG.count))
    local t = os.clock()
    while turtle.detect() and (os.clock() - t) < CONFIG.leaveTimeout do sleep(1) end
    sleep(2)
  else
    print("could not place worker - retrying"); sleep(2)
  end
end
print("master: deployment done - waiting to collect finished workers")

-- ===========================================================================
-- Phase 2: collect (still facing HOME). The server parks one finished worker
-- at HOME at a time; we mine it, then tell the server so the next can come.
-- ===========================================================================
if not http then
  print("master: no HTTP - cannot auto-collect; do it by hand")
else
  while true do
    local r = httpJSON("GET", "/collect")
    if r and r.done then break end
    if r and r.mine then
      local tries = 0
      while turtle.detect() and tries < 15 do turtle.dig(); sleep(0.4); tries = tries + 1 end
      httpJSON("POST", "/collected", {})
      print("master: mined up a finished worker")
    end
    sleep(1)
  end
  print("master: all workers collected")
end

turtle.turnRight()                                  -- restore facing
