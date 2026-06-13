--[[============================================================================
  depot.lua  -  Runs on the computer attached to the ME Bridge.

  Listens for "restock" requests from workers and exports the requested items
  from the AE2 network into the docked turtle (the inventory sitting in
  cfg.depot.exportDir relative to the ME Bridge). Replies "restockDone".

  Hardware: a computer (or advanced computer) with a wireless/ender modem and
  an Advanced Peripherals ME Bridge, the ME Bridge wired into your AE2 network,
  and a single docking spot where workers park (cfg.depot.dock) adjacent to the
  bridge on the cfg.depot.exportDir side.
============================================================================]]

local cfg = require("config")
local P   = require("protocol")

local bridge = peripheral.find("meBridge")
if not bridge then error("[depot] no ME Bridge found — attach one and wire it into AE2") end

P.open(cfg)
print("[depot] ready. Export direction: " .. cfg.depot.exportDir)

while true do
  local id, msg = P.receive()
  if id and type(msg) == "table" and msg.type == "restock" then
    local exported = {}
    for _, it in ipairs(msg.items or {}) do
      local ok, moved = pcall(function()
        return bridge.exportItem({ name = it.name, count = it.count }, cfg.depot.exportDir)
      end)
      if ok and type(moved) == "number" then
        exported[it.name] = moved
      else
        exported[it.name] = 0
        print("[depot] export failed for " .. tostring(it.name) ..
              (type(moved) == "string" and (" (" .. moved .. ")") or ""))
      end
    end
    P.send(id, { type = "restockDone", exported = exported })
    local summary = {}
    for n, c in pairs(exported) do summary[#summary + 1] = c .. "x " .. n end
    print("[depot] restocked id " .. id .. ": " .. table.concat(summary, ", "))
  end
end
