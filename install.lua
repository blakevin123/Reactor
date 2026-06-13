--[[
  install.lua  -  One-command downloader for the Reactor build swarm.

  Run on any in-game computer/turtle (needs HTTP enabled, which ATM10 has).

  Install the programs onto THIS computer/turtle:
      wget run https://raw.githubusercontent.com/blakevin123/Reactor/main/install.lua

  Build a programming FLOPPY (insert a disk in an adjacent drive first):
      wget run https://raw.githubusercontent.com/blakevin123/Reactor/main/install.lua disk

  NOTE: with `wget run`, arguments go AFTER the url. The word `disk` above is
  what selects floppy mode.
]]

local USER, REPO, BRANCH = "blakevin123", "Reactor", "main"
local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)

local CORE     = { "config.lua", "geo.lua", "layout.lua" }
local PROGRAMS = { "worker.lua", "master.lua", "supply.lua" }
local WORKER   = { "config.lua", "geo.lua", "layout.lua", "worker.lua" }  -- what a worker needs

local function fetch(remote, localPath)
  print("GET " .. remote .. " -> " .. localPath)
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

if role == "disk" then
  -- Find the mounted floppy via the drive peripheral (works for /disk, /disk1, ...)
  local drive = peripheral.find("drive", function(_, d) return d.getMountPath() ~= nil end)
  if not drive then
    error("no floppy found - put a disk in an adjacent drive, then run: install disk")
  end
  local mount = "/" .. drive.getMountPath()
  print("writing programming floppy at " .. mount)
  fetch("disk/startup.lua", mount .. "/startup.lua")   -- bootstrap that auto-runs on a blank turtle
  for _, f in ipairs(WORKER) do
    fetch(f, mount .. "/" .. f)
  end
  print("")
  print("Floppy ready. Move it to the dock's disk drive and place a blank turtle beside it.")
  return
end

-- normal: install programs onto this computer/turtle
for _, f in ipairs(CORE) do fetch(f, f) end
for _, f in ipairs(PROGRAMS) do fetch(f, f) end
print("")
print("Done. Now run one of:  master  |  worker  |  supply")
