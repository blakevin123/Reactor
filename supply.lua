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
local me = peripheral.find("me_bridge")
if not me then error("no ME Bridge found next to this computer") end

local modem = peripheral.find("modem")
if not modem then error("no modem found (need a wireless/ender modem for rednet)") end
rednet.open(peripheral.getName(modem))
rednet.host(cfg.protocol, cfg.supplyName)

local DIR = cfg.station.bridgeExportDir or "up"
local M = cfg.msg

-- ---------------------------------------------------------------------------
-- Stock query.  Newer Advanced Peripherals uses me.getItems() (a full list)
-- instead of the removed me.getItem(filter).  We scan it once and build a
-- name -> count map.  Item count field may be `count` or `amount` depending
-- on AP version, so we accept either.
-- ---------------------------------------------------------------------------
local function stockMap()
  local map = {}
  local ok, items = pcall(me.getItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do
      if it.name then map[it.name] = it.count or it.amount or 0 end
    end
  end
  return map
end

-- Set of craftable item names (so we can auto-craft shortfalls).
local function craftableSet()
  local set = {}
  local ok, items = pcall(me.getCraftableItems)
  if ok and type(items) == "table" then
    for _, it in ipairs(items) do if it.name then set[it.name] = true end end
  end
  return set
end

local CRAFTABLE = craftableSet()
local CAN_CRAFT = type(me.craftItem) == "function"

local function selfCheck()
  print("=== Supply station self-check ===")
  local online = true
  local ok, v = pcall(me.isOnline)
  if ok then online = v end
  print("ME Bridge online: " .. tostring(online))
  local stock = stockMap()
  local ids = {}
  for _, id in pairs(cfg.blocks) do if id then ids[id] = true end end
  ids[cfg.fuelItem] = true
  for id in pairs(ids) do
    local n = stock[id] or 0
    if n == 0 then
      local tag = CRAFTABLE[id] and " (craftable)" or ""
      print("  WARNING: 0 in stock" .. tag .. ": " .. id)
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
  local ok, exported = pcall(me.exportItem, filter, DIR)
  exported = (ok and type(exported) == "number") and exported or 0
  -- If we couldn't fully supply it and it's craftable, kick off a craft so the
  -- next trip can finish.  (Crafting is async; the worker takes what it can.)
  if exported < count and CAN_CRAFT and CRAFTABLE[id] then
    pcall(me.craftItem, { name = id, count = count - exported })
  end
  return exported
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
