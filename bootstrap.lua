--[[ bootstrap.lua  -  one-command install/update over HTTP (GitHub raw).

  Host all the reactor .lua files (including this one) at a base URL — a GitHub
  repo or gist is ideal because the raw URLs never change, so pushing an edit is
  just `git push` then re-run this on each unit.

  USAGE — once BASE below points at your repo:
    wget run <BASE>bootstrap.lua worker        -- install as a worker
    wget run <BASE>bootstrap.lua master Bob     -- install as master, label Bob
    wget run <BASE>bootstrap.lua                -- refresh files, keep role

  (Or save this file locally and run:  bootstrap worker )
]]

local args  = { ... }
local role  = args[1]
local label = args[2]
local valid = { master = true, worker = true, depot = true }

if role and not valid[role] then
  print("Usage: wget run <BASE>bootstrap.lua [master|worker|depot] [label]")
  print("  (no role given = just refresh files, keep current role)")
  return
end

-- >>> SET THIS to where your raw files live, and keep the trailing slash <<<
-- GitHub repo:  https://raw.githubusercontent.com/USER/REPO/main/
-- GitHub gist:  https://gist.githubusercontent.com/USER/GISTID/raw/
local BASE = "https://raw.githubusercontent.com/USER/REPO/main/"

local FILES = {
  "config.lua", "plan.lua", "nav.lua", "protocol.lua",
  "worker.lua", "master.lua", "depot.lua", "startup.lua", "listitems.lua",
}

local function fetch(name)
  if fs.exists(name) then fs.delete(name) end
  local url = BASE .. name .. "?t=" .. os.epoch("utc")  -- bust the CDN cache
  io.write("get " .. name .. " ... ")
  local ok = shell.run("wget", url, name)
  print(ok and "ok" or "FAILED")
  return ok
end

local fails = 0
for _, name in ipairs(FILES) do
  if not fetch(name) then fails = fails + 1 end
end

if role then
  local fr = fs.open("role", "w"); fr.write(role); fr.close()
  if label then
    os.setComputerLabel(label)
  elseif not os.getComputerLabel() then
    os.setComputerLabel(role .. "-" .. os.getComputerID())
  end
  print("Role: " .. role .. ", label: " .. (os.getComputerLabel() or "(none)"))
end

if fails > 0 then
  print(fails .. " file(s) failed — check BASE url and the HTTP whitelist.")
elseif role == "worker" then
  print("Done. Pick this worker up into the master.")
elseif role then
  print("Done. Reboot when you're ready to start.")
else
  print("Files refreshed. Reboot to run the new code.")
end
