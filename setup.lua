-- setup.lua  -  run this FROM THE DISK to install a unit in one command.
-- Put this file (and all the other .lua files) on a floppy disk, then on each
-- turtle/computer run:   /disk/setup worker      (or master / depot)
-- It copies every program from the disk, sets the role, and labels the unit.
-- It does NOT auto-start, so freshly-set-up workers won't wander off — pick
-- them up into the master, or reboot the master/depot yourself when ready.

local args = { ... }
local role = args[1]
local valid = { master = true, worker = true, depot = true }

if not role or not valid[role] then
  print("Usage: /disk/setup <master|worker|depot> [label]")
  return
end

-- figure out where this script is running from (the disk mount)
local src = "/disk"
if not fs.exists(src) then
  -- fall back: directory of this program
  src = fs.getDir(shell and shell.getRunningProgram() or "disk/setup.lua")
end

-- copy every .lua file (except this installer) into the root
local copied = 0
for _, f in ipairs(fs.list(src)) do
  if f:match("%.lua$") and f ~= "setup.lua" then
    local dst = "/" .. f
    if fs.exists(dst) then fs.delete(dst) end
    fs.copy(fs.combine(src, f), dst)
    copied = copied + 1
  end
end

-- set the role
local fr = fs.open("role", "w")
fr.write(role)
fr.close()

-- give it a persistent label (so it keeps its files when picked up & replaced)
local label = args[2]
if label then
  os.setComputerLabel(label)
elseif not os.getComputerLabel() then
  os.setComputerLabel(role .. "-" .. os.getComputerID())
end

print("Installed " .. copied .. " files.")
print("Role:  " .. role)
print("Label: " .. (os.getComputerLabel() or "(none)"))
if role == "worker" then
  print("Done. Pick this worker up into the master.")
else
  print("Done. Reboot when you're ready to start.")
end
