-- install.lua  -  set this unit's role and give it a persistent label.
-- Labelling matters: a LABELLED turtle keeps its files (and id) when broken and
-- replaced, so the master can pick workers up and redeploy them later.
--
-- Usage:  install <master|worker|depot> [label]

local args = { ... }
local role = args[1]
local valid = { master = true, worker = true, depot = true }

if not role or not valid[role] then
  print("Usage: install <master|worker|depot> [label]")
  return
end

local f = fs.open("role", "w")
f.write(role)
f.close()

local label = args[2]
if label then
  os.setComputerLabel(label)
elseif not os.getComputerLabel() then
  os.setComputerLabel(role .. "-" .. os.getComputerID())
end

print("Role set to '" .. role .. "'.")
print("Label: " .. (os.getComputerLabel() or "(none)"))
print("Reboot (or run 'startup') to launch.")
