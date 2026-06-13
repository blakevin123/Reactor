--[[============================================================================
  protocol.lua  -  Thin rednet wrapper shared by master, workers and depot

  All units load config.lua locally, so messages only carry job data, never
  the whole config. Open a modem once with P.open(cfg), then use send /
  broadcast / receive.

  Message shapes (the `type` field switches behaviour):
    worker -> master : {type="register", label=<string>}
    master -> worker : {type="assignPos", pos={x,y,z}, heading=<n>, index=<n>}
    worker -> master : {type="reqColumn"}
    master -> worker : {type="column", lx=<n>, lz=<n>}
                     | {type="allDone"}        -- nothing left, come home
    worker -> master : {type="columnDone", lx=<n>, lz=<n>}
    master -> worker : {type="recall"}         -- abort/return now
    worker -> master : {type="parked"}         -- back at pickup, idle
    worker -> depot  : {type="restock", items={ {name=,count=}, ... }}
    depot  -> worker : {type="restockDone", exported={ name=count, ... }}
============================================================================]]

local P = {}

function P.open(cfg)
  P.cfg = cfg
  P.proto = cfg.net.protocol
  local side = cfg.net.modemSide
  if side then
    rednet.open(side)
  else
    -- auto-detect: open the first wireless-capable modem we find
    local opened = false
    for _, s in ipairs(peripheral.getNames()) do
      if peripheral.getType(s) == "modem" then
        rednet.open(s)
        opened = true
        break
      end
    end
    if not opened then error("nav/protocol: no modem found — attach a wireless or ender modem") end
  end
end

function P.send(id, msg)
  return rednet.send(id, msg, P.proto)
end

function P.broadcast(msg)
  return rednet.broadcast(msg, P.proto)
end

-- Returns senderId, message  (or nil on timeout)
function P.receive(timeout)
  local id, msg = rednet.receive(P.proto, timeout)
  return id, msg
end

-- Wait for a specific message type from anyone; returns id,msg (or nil,timeout)
function P.receiveType(wanted, timeout)
  local deadline = timeout and (os.clock() + timeout) or nil
  while true do
    local t = deadline and math.max(0, deadline - os.clock()) or nil
    local id, msg = P.receive(t)
    if id == nil then return nil end
    if type(msg) == "table" and msg.type == wanted then return id, msg end
  end
end

return P
