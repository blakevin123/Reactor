--[[
  install.lua  -  One-command downloader for the Reactor build swarm.

  Run on any in-game computer/turtle (needs HTTP enabled, which ATM10 has):

      wget run https://raw.githubusercontent.com/blakevin123/Reactor/main/install.lua

  By default it grabs every core file. Pass a role to also prep extras:

      install master     -> core files (run 'master' after)
      install worker      -> core files (run 'worker' after)
      install supply      -> core files (run 'supply' after)
      install disk         -> also writes the worker files onto an inserted floppy
                              at /disk so it becomes a programming disk
]]

local USER, REPO, BRANCH = "blakevin123", "Reactor", "main"
local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)

-- files every computer needs
local CORE = { "config.lua", "geo.lua", "layout.lua" }
-- role programs
local PROGRAMS = { "worker.lua", "master.lua", "supply.lua" }

local function fetch(remote, localPath)
  print("GET " .. remote)
  local resp = http.get(BASE .. remote)
  if not resp then error("download failed (HTTP off or bad URL?): " .. remote) end
  local data = resp.readAll()
  resp.close()
  local dir = fs.getDir(localPath)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  if fs.exists(localPath) then fs.delete(localPath) end
  local h = fs.open(localPath, "w")
  h.write(data)
  h.close()
end

local role = (...) or "all"

-- always grab core + all programs to the local computer
for _, f in ipairs(CORE) do fetch(f, f) end
for _, f in ipairs(PROGRAMS) do fetch(f, f) end

-- build a programming floppy if asked and a disk is mounted
if role == "disk" then
  if not fs.exists("/disk") then
    error("no floppy found - put a disk in an adjacent drive, then run: install disk")
  end
  fetch("disk/startup.lua", "/disk/startup.lua")
  for _, f in ipairs({ "config.lua", "geo.lua", "layout.lua", "worker.lua" }) do
    if fs.exists("/disk/" .. f) then fs.delete("/disk/" .. f) end
    fs.copy(f, "/disk/" .. f)
  end
  print("Programming floppy ready. Place a blank turtle next to this drive.")
end

print("")
print("Done. Now run one of:  master  |  worker  |  supply")
