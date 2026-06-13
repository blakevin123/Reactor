--[[
  master.lua  -  Swarm brain + (optional) deployer (runs on the master turtle).

  Does three things:
    1. Validates the config and prints the build plan (block totals).
    2. Partitions the reactor footprint into one strip per worker and hands each
       registering worker a strip + a unique cruise altitude.
    3. (Optional) Physically deploys fresh worker turtles: it places a blank
       turtle into the programming dock, where an adjacent disk drive holding
       the worker disk boots and programs it (see disk/startup.lua).

  Needs a wireless/ender modem upgrade.  If cfg.autoDeploy is false you place
  the workers by hand next to the programming disk drive instead.
]]

local cfg    = dofile("/config.lua")
local layout = dofile("/layout.lua")

-- Master inventory slot holding the stack of blank worker turtles (autoDeploy).
local WORKER_SLOT = 1

-- ===========================================================================
-- Plan summary
-- ===========================================================================
local function summary()
  local ok, why = layout.validate(cfg)
  if not ok then error("CONFIG ERROR: " .. why) end

  local t = layout.totals(cfg)
  local strips = layout.partition(cfg, cfg.workerCount)

  print("=== Reactor build plan ===")
  print(("size %dx%dx%d at (%d,%d,%d)  type=%s  pattern=%s")
    :format(cfg.size.x, cfg.size.y, cfg.size.z, cfg.origin.x, cfg.origin.y, cfg.origin.z,
            cfg.reactorType, cfg.fuelPattern))
  local order = { "casing", "glass", "fuelRod", "controlRod", "coolant",
                  "controller", "powerTap", "coolantPort", "accessPort", "computerPort" }
  local grand = 0
  for _, k in ipairs(order) do
    if t[k] then
      print(("  %-13s %6d   %s"):format(k, t[k], cfg.blocks[k] or "?"))
      grand = grand + t[k]
    end
  end
  print(("  %-13s %6d"):format("TOTAL", grand))
  print(("workers: %d  (strips along %s)"):format(#strips, strips[1].axis))
  for i, s in ipairs(strips) do
    print(("  worker %d -> %s %d..%d, cruiseY=%d"):format(i, s.axis, s.lo, s.hi, cfg.cruiseY() + (i - 1)))
  end
  print("==========================")
  return strips
end

-- ===========================================================================
-- Coordinator
-- ===========================================================================
local function coordinator(strips)
  local nextStrip = 1
  local assigned  = {}     -- workerId -> { strip, index, cruiseY }
  local done      = {}     -- workerId -> true
  local doneCount = 0
  local M = cfg.msg

  while true do
    local from, m = rednet.receive(cfg.protocol)
    if type(m) == "table" then
      if m.type == M.REGISTER then
        local a = assigned[from]
        if not a and nextStrip <= #strips then
          a = { strip = strips[nextStrip], index = nextStrip - 1, cruiseY = cfg.cruiseY() + (nextStrip - 1) }
          assigned[from] = a
          nextStrip = nextStrip + 1
          print(("assigned worker #%d (id %d) -> %s %d..%d")
            :format(a.index + 1, from, a.strip.axis, a.strip.lo, a.strip.hi))
        end
        if a then
          rednet.send(from, { type = M.ASSIGN, strip = a.strip, index = a.index, cruiseY = a.cruiseY }, cfg.protocol)
        end

      elseif m.type == M.PROGRESS then
        print(("worker %d: layer %d/%d"):format(from, m.layer or 0, m.total or 0))

      elseif m.type == M.DONE then
        if not done[from] then
          done[from] = true
          doneCount = doneCount + 1
          print(("worker %d FINISHED (%d/%d)"):format(from, doneCount, #strips))
          if doneCount >= #strips then
            print("*** ALL STRIPS COMPLETE - reactor shell built. ***")
            print("Now insert fuel via the Access Port and activate the Controller.")
            return
          end
        end
      end
    end
  end
end

-- ===========================================================================
-- Optional auto-deploy
-- ===========================================================================
local function deploy()
  if not cfg.autoDeploy then
    print("autoDeploy off - place " .. cfg.workerCount .. " workers by the programming disk yourself.")
    return
  end
  print("auto-deploying " .. cfg.workerCount .. " workers...")
  for i = 1, cfg.workerCount do
    turtle.select(WORKER_SLOT)
    if turtle.getItemCount(WORKER_SLOT) == 0 then
      print("OUT OF WORKER TURTLES in slot " .. WORKER_SLOT .. " - load more and they'll keep deploying.")
      while turtle.getItemCount(WORKER_SLOT) == 0 do sleep(2) end
    end
    -- clear the dock cell only if it is empty terrain (never dig a turtle)
    if turtle.detectDown() then
      local ok, data = turtle.inspectDown()
      if not (ok and data.name and data.name:find("computercraft")) then
        turtle.digDown()
      end
    end
    if turtle.placeDown() then
      print(("placed worker %d/%d - waiting for it to program & leave dock"):format(i, cfg.workerCount))
      local deadline = os.clock() + 60
      while turtle.detectDown() and os.clock() < deadline do sleep(1) end
      sleep(2)   -- small gap so the next placement is clean
    else
      print("could not place worker (dock blocked?) - retrying")
      sleep(2)
    end
  end
  print("deployment finished.")
end

-- ===========================================================================
-- Main
-- ===========================================================================
local strips = summary()

local m = peripheral.find("modem")
if not m then error("master needs a wireless/ender modem upgrade") end
rednet.open(peripheral.getName(m))
rednet.host(cfg.protocol, cfg.masterName)
print("master online as '" .. cfg.masterName .. "' (id " .. os.getComputerID() .. ")")

parallel.waitForAll(
  function() coordinator(strips) end,
  deploy
)
