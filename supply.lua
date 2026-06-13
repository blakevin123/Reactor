--[[
  supply.lua  -  Supply station server (runs on a stationary computer).

  This computer sits next to an Advanced Peripherals ME Bridge and serves the
  worker swarm two things over rednet:
    * A DOCK LOCK so only one worker draws items at a time (no pile-ups).
    * EXPORTS: on request it pushes blocks/fuel from the AE2 system into the
      supply chest, which is positioned so the docked worker can suckDown().

  Physical setup (see README):
      [ME Bridge]  with a CHEST on top (bridge exports "up" into it)
      worker dock cell is the block directly ABOVE that chest.
      This computer is placed touching the ME Bridge, plus a wireless/ender
      modem on another side for rednet.
]]

local cfg = dofile("/config.lua")

-- ---------------------------------------------------------------------------
-- Peripherals
-- ---------------------------------------------------------------------------
local me = peripheral.find("meBridge") or peripheral.find("me_bridge")
if not me then error("no ME Bridge found next to this computer") end

local modem = peripheral.find("modem")
if not modem then error("no modem found (need a wireless/ender modem for rednet)") end
rednet.open(peripheral.getName(modem))
rednet.host(cfg.protocol, cfg.supplyName)

local DIR = cfg.station.bridgeExportDir or "up"
local M = cfg.msg

-- ---------------------------------------------------------------------------
-- Startup self-check: confirm every block ID is real / in stock
-- ---------------------------------------------------------------------------
local function amountOf(id)
  local ok, item = pcall(me.getItem, { name = id })
  if ok and item and item.amount then return item.amount end
  return 0
end

local function selfCheck()
  print("=== Supply station self-check ===")
  local ids = {}
  for _, id in pairs(cfg.blocks) do if id then ids[id] = true end end
  ids[cfg.fuelItem] = true
  for id in pairs(ids) do
    local n = amountOf(id)
    if n == 0 then
      print("  WARNING: 0 in stock (or wrong ID): " .. id)
    else
      print(("  ok %8d  %s"):format(n, id))
    end
  end
  print("=================================")
end

-- ---------------------------------------------------------------------------
-- Export: push up to `count` of `id` into the supply chest
-- ---------------------------------------------------------------------------
local function exportItem(id, count)
  local filter = { name = id, count = count }
  -- Try to auto-craft if we're short and it's craftable.
  local have = amountOf(id)
  if have < count then
    local okc, craftable = pcall(me.isItemCraftable, { name = id })
    if okc and craftable then pcall(me.craftItem, { name = id, count = count - have }) end
  end
  local ok, exported = pcall(me.exportItem, filter, DIR)
  if ok and type(exported) == "number" then return exported end
  -- fallback signature used by some AP versions
  local ok2, exported2 = pcall(me.exportItemToPeripheral, filter, "minecraft:chest")
  if ok2 and type(exported2) == "number" then return exported2 end
  return 0
end

-- ---------------------------------------------------------------------------
-- Main server loop
-- ---------------------------------------------------------------------------
local holder = nil          -- workerId currently allowed at the dock

local function serve()
  while true do
    local from, msg = rednet.receive(cfg.protocol)
    if type(msg) == "table" then

      if msg.type == M.DOCK_REQ then
        if holder == nil or holder == from then
          holder = from
          rednet.send(from, { type = M.DOCK_GRANT }, cfg.protocol)
        end
        -- else: busy; the worker will retry shortly

      elseif msg.type == M.DOCK_REL then
        if holder == from then holder = nil end

      elseif msg.type == M.EXPORT_REQ then
        local exported = 0
        if holder == from then               -- only the dock holder may pull
          exported = exportItem(msg.item, msg.count or 1)
          print(("export %d x %s -> worker %d"):format(exported, tostring(msg.item), from))
        end
        rednet.send(from, { type = M.EXPORT_DONE, item = msg.item, exported = exported }, cfg.protocol)
      end
    end
  end
end

selfCheck()
print("supply online as '" .. cfg.supplyName .. "' (id " .. os.getComputerID() .. ")")
serve()
