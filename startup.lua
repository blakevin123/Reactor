-- startup.lua  -  runs automatically when the computer/turtle powers on.
-- It reads a one-word "role" file and launches the matching program.
-- Set the role once with:  install <master|worker|depot> [label]

local role = ""
if fs.exists("role") then
  local f = fs.open("role", "r")
  role = (f.readAll() or ""):gsub("%s", "")
  f.close()
end

if role == "master" then
  shell.run("master.lua")
elseif role == "worker" then
  shell.run("worker.lua")
elseif role == "depot" then
  shell.run("depot.lua")
else
  print("No role set.")
  print("Run:  install worker   (or master / depot)")
end
