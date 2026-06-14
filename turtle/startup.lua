--[[
  startup.lua  -  Worker bootstrap. Lives on the programming disk in HOME's disk
  drive. When the master places a blank turtle on HOME, it boots, runs this off
  the disk, copies the program onto itself, and reboots into the worker.

  Put on the floppy:  /disk/startup.lua  /disk/worker.lua  /disk/turtle_config.lua

  Deliberately does NOT label the turtle - a label makes turtles keep their ID
  when broken, which also makes spare turtles unstackable.
]]

if fs.exists("/installed") then return end       -- already a worker; let local startup run

local function findDisk()
  for _, n in ipairs({ "/disk", "/disk1", "/disk2", "/disk3", "/disk4", "/disk5", "/disk6" }) do
    if fs.exists(n .. "/worker.lua") then return n end
  end
end

local src = findDisk()
if not src then print("bootstrap: worker.lua not found on any disk"); return end

print("bootstrap: installing worker from " .. src)
for _, f in ipairs({ "worker.lua", "turtle_config.lua" }) do
  if fs.exists("/" .. f) then fs.delete("/" .. f) end
  fs.copy(src .. "/" .. f, "/" .. f)
end

local h = fs.open("/startup.lua", "w"); h.write('shell.run("worker.lua")\n'); h.close()
local m = fs.open("/installed", "w"); m.write("1"); m.close()

print("bootstrap: done - rebooting into worker")
sleep(0.5)
os.reboot()
