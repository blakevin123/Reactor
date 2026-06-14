--[[
  disk/startup.lua  -  Worker bootstrap, lives on the programming floppy.

  When a freshly-placed (blank) turtle boots next to a disk drive holding this
  disk, CraftOS runs this file automatically.  It copies the worker program
  onto the turtle's own filesystem, installs a local startup so the turtle
  auto-resumes after any reboot/chunk reload, then reboots to start working.

  Put these files on the floppy alongside this one:
      /disk/config.lua
      /disk/geo.lua
      /disk/layout.lua
      /disk/worker.lua
      /disk/startup.lua   (this file)
]]

-- Already installed?  Let the turtle's own /startup.lua take over.
if fs.exists("/installed") then return end

-- Find the disk mount that actually holds our files.
local function findDisk()
  for _, name in ipairs({ "/disk", "/disk1", "/disk2", "/disk3", "/disk4", "/disk5", "/disk6" }) do
    if fs.exists(name .. "/worker.lua") then return name end
  end
  return nil
end

local src = findDisk()
if not src then
  print("bootstrap: cannot find worker files on any disk - aborting")
  return
end

print("bootstrap: installing worker program from " .. src)
for _, f in ipairs({ "config.lua", "geo.lua", "layout.lua", "worker.lua" }) do
  if fs.exists("/" .. f) then fs.delete("/" .. f) end
  fs.copy(src .. "/" .. f, "/" .. f)
end

-- Local startup so the worker restarts itself on reboot (no disk needed).
local h = fs.open("/startup.lua", "w")
h.write('shell.run("worker.lua")\n')
h.close()

-- Mark installed.  NOTE: we deliberately do NOT set a computer label.  A label
-- makes a turtle keep its ID/files when broken, which also makes it
-- unstackable.  Placed turtles already persist across reboots/chunk reloads
-- without a label, so leaving them unlabeled keeps spare turtles stackable for
-- redeployment.
local mark = fs.open("/installed", "w"); mark.write(tostring(os.epoch("utc"))); mark.close()

print("bootstrap: done - rebooting into worker")
sleep(0.5)
os.reboot()
