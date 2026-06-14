# Reactor Build Swarm

Builds a large **Extreme Reactors** multiblock with a swarm of ComputerCraft
turtles coordinated by a **Python backend**. The server generates the schematic,
splits the footprint into one chunk per worker, and serves each worker a
per-layer GCODE manifest over HTTP. Workers restock the exact blocks they need
from a row of **ME Bridges** (Advanced Peripherals), build their chunk, and
return home when done.

Ports/controller are **left as casing/glass** — you place the real ones by hand
afterwards.

```
   Python server (PC) ── HTTP ──┬── master turtle (deploys 8 workers)
   plan · chunks · GCODE ·      └── 8 workers (GPS nav + ME restock)
   dock locks · monitor page
```

## Layout
```
server/   config.json   layout.py   server.py
turtle/   master.lua    worker.lua  startup.lua   turtle_config.lua
```

## 1. Run the server
Needs Python 3 (stdlib only — no pip installs).
```
python server/server.py
```
Open the monitor at `http://localhost:8080/`. You can **edit size and origin** there and hit *Save & Regenerate* (do this before deploying — it resets build state). The page shows block totals and live per-worker progress.

### Let the turtles reach the server (important)
CC:Tweaked **blocks HTTP to local/private IPs by default**, so a turtle can't hit your PC until you do one of:
- **Allow your LAN IP** in the CC config: in `computercraft-server.toml` add an allow rule for your PC's address *above* the `$private` deny rule, then put `http://<PC-LAN-IP>:8080` in `turtle/turtle_config.lua`; **or**
- **Tunnel** with ngrok: `ngrok http 8080`, and put the `https://…ngrok-free.app` URL in `turtle_config.lua` (public URLs aren't blocked).

## 2. config.json
```jsonc
size, origin        // reactor dimensions + min corner (world coords)
fuelPattern         // "checkerboard" | "full" | "spaced"
useGlassWalls       // glass side walls
workerCount         // 8
blocks              // registry IDs (verify with F3+H!); coolant: null = air interior
home                // worker cell on top of the HOME bridge (deploy/refuel/return)
restock.docks[]     // one world cell per restock ME Bridge (cell sits ON TOP of each bridge)
```

## 3. Build the two zones in-game
**HOME** (deploy + initial fuel + final return; you delete it afterwards):
```
[ master turtle ] ── faces ──> [ HOME cell ]   <- worker spawns here
                                [ ME Bridge ]   (under HOME)
            [ disk drive ] on a side of HOME, holding the worker disk
```
**RESTOCK zone** (a row of ME Bridges so workers restock in parallel):
```
[dock0][dock1][dock2][dock3]      <- worker cells, each ON TOP of a bridge
[ ME  ][ ME  ][ ME  ][ ME  ]      <- all on the same AE2 network
```
Each dock cell's world coords go in `restock.docks`. Keep **open air above each dock** up to the cruise altitude (`origin.y + size.y + 4 + workerIndex`). Also need a **GPS constellation** in range of the whole work area.

## 4. Make the worker disk
On a computer with a disk drive + floppy, copy these onto `/disk/`:
`startup.lua`, `worker.lua`, `turtle_config.lua` (with your server URL). Move the floppy into HOME's disk drive.

## 5. Worker turtles
Craft **8 turtles, each with a pickaxe + an ender/wireless modem** (modem for GPS), and load them into the **master's inventory**. They boot blank, copy the program off the disk, refuel on the home bridge, and fly to their chunk. (No labels are set, so spares stay stackable.)

## 6. Go
```
python server/server.py     # PC
master                      # master turtle: deploys all 8
```
Watch the monitor reach 100%. Then **manually swap in the real parts** (controller, power tap, access port, etc.) by replacing some casing/glass blocks, insert fuel, and activate.

## Test small first
Set `size` to `5×5×5` and `workerCount` to `2` (give 2 docks), deploy, and confirm a valid shell forms + the restock/refuel/junk cycle works before scaling to 32³ / 8 workers.

## Notes & troubleshooting
| Symptom | Cause |
|---|---|
| worker errors `HTTP API disabled` / can't reach server | CC http not allowed to your IP — see step 1 (config rule or ngrok) |
| `no GPS fix` | GPS constellation not in range / no modem on the turtle |
| monitor shows item totals but build leaves holes | ME ran out of a block mid-build — stock it or make it autocraftable in AE2 |
| workers pile up at a dock | expected briefly; the per-dock lock + unique cruise altitudes resolve it |
| underground build very slow | solid rock = lots of digging + junk; **hollow the reactor volume first** for a far faster, cleaner run |

- Block IDs are pack-specific — verify each with **F3+H** advanced tooltips and put them in `config.json`.
- The single AE2 network feeds all bridges; ensure enough storage/craft capacity (and a trash/void for dug junk if building in rock).
