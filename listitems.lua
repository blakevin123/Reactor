-- listitems.lua  -  Print the exact registry names of items in your AE2 system.
-- Run this on the depot computer (with the ME Bridge attached) to discover the
-- correct ids to paste into config.lua's C.blocks table.
-- Optional filter:  listitems reactor   (only show names containing "reactor")

local bridge = peripheral.find("meBridge")
if not bridge then error("no ME Bridge found") end

local filter = ({...})[1]
local items = bridge.listItems() or {}
table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)

local out = fs.open("items.txt", "w")
local shown = 0
for _, it in ipairs(items) do
  local name = it.name or "?"
  if not filter or name:find(filter, 1, true) then
    local line = string.format("%-48s x%d", name, it.amount or it.count or 0)
    print(line)
    out.writeLine(line)
    shown = shown + 1
  end
end
out.close()
print("---")
print(shown .. " items listed (also saved to items.txt)")
