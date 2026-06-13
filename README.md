# Reactor Swarm — automated Extreme Reactors builder

A ComputerCraft turtle swarm that builds a passive, solid-coolant Extreme
Reactors multiblock for you. One master turtle deploys a swarm of workers, each
worker builds vertical columns of the reactor (placing casing, glass, fuel rods,
control rods and your chosen coolant block), restocking from your AE2 network
through an Advanced Peripherals **ME Bridge**. Obstacles in the way get dug out.
When the build is done the workers park themselves for pickup and the master
places the controller / power tap / access port.

Everything tunable lives in **`config.lua`** — reactor size, the coolant block,
item ids, depot location, worker count, etc.

---

## How it works (the short version)

- The reactor is treated as a grid of vertical **columns** (one per x,z). Each
  column is fully determined by the plan: walls = casing/glass, interior =
  fuel-rod or coolant lattice, ceiling = control rod above each fuel column.
- The **master** calibrates by GPS, places workers one at a time, then hands out
  columns from a queue over rednet.
- Each **worker** flies to a personal altitude above the build (so they don't
  collide), drops into its assigned column, and builds it **bottom-to-top** by
  standing one block above the target cell and `placeDown`-ing as it climbs.
- When a worker is low on blocks it flies to the **depot**, where the ME Bridge
  exports a top-up directly into the docked turtle, then returns.
- The build is **idempotent**: if a cell already has the right block it's
  skipped, so you can stop and restart safely.

---

## Hardware you need

- **GPS constellation** in range of the build (4 computers + wireless modems —
  the standard CC setup). Required so every unit knows where it is.
- **1 master** = a mining turtle with a wireless/ender modem.
- **N worker** mining turtles, each with a wireless/ender modem (default N = 6).
  Mining turtles so they can dig obstructions.
- **1 depot computer** with a wireless/ender modem **and an ME Bridge** wired
  into your AE2 system. A docking block position next to the bridge.
- Ender modems strongly recommended (unlimited range, no chunk-load worries).

---

## One-time install (every unit)

Put all the `.lua` files from this folder onto each computer/turtle (via a disk,
`pastebin`, or `wget`). Then set each unit's role:

```
install master        -- on the master turtle
install worker         -- on every worker turtle
install depot          -- on the depot computer
```

`install` also **labels** the turtle. This matters: a labelled turtle keeps its
files when broken and re-placed, so the master can pick workers up and redeploy
them. Reboot after installing; `startup.lua` launches the right program.

---

## Find your real item ids

The defaults in `config.lua` are typical Extreme Reactors names but **may differ
in All the Mods 10**. On the depot computer run:

```
listitems              -- or:  listitems reactor
```

It prints (and saves to `items.txt`) the exact registry names in your AE2
network. Paste the correct ones into `C.blocks` in `config.lua`, and set
`C.blocks.coolant` to whichever solid coolant block you're using.

---

## Configure (`config.lua`)

Edit at least these:

- `C.reactor` — `width`, `height`, `depth` (your bounding box, ≤ 32×48×32).
  `origin` = the **world coordinates** of the bottom NW casing corner (press F3).
- `C.blocks` / `C.wallBlock` / `C.fuelPattern` — what to build it from.
- `C.special` — where the controller, power tap and access port go (at least one
  controller is required by the mod).
- `C.swarm.workerCount` — how many workers the master will deploy.
- `C.staging` — the world coords of the first worker drop spot (needs open air
  above and one block to the side for GPS calibration), and the step between
  workers.
- `C.depot.dock` / `exportDir` — the world coords of the docking block and which
  way the ME Bridge faces it.

Keep `config.lua` identical on every unit.

---

## Physical layout

```
          (open sky above everything for flight lanes)

   reactor.origin ●──────────────►  +x
   (bottom NW)    │  R E A C T O R
                  │  width × height × depth
                  ▼ +z

   staging line:  □ □ □ □ □ □   <- workers dropped here, master places them
   master:        ▣            <- a few blocks clear of the reactor
   depot:         [ME Bridge]+[computer]  with a dock block on exportDir side
```

Leave clear air above the reactor and over the travel paths to the depot — the
swarm cruises above the structure. Workers fly at `reactor.height + flightBase +
index`, so make sure the world ceiling allows it for tall reactors.

---

## Run it

1. Start the **depot** (`reboot`, or run `startup`). It waits for requests.
2. Make sure the **GPS** constellation is running.
3. Load the **master** turtle's inventory with the worker turtles **plus** one
   each of the special blocks (controller, power tap, access port).
4. Place the master at its spot with clear air, and run it (`reboot`).

The master calibrates, deploys each worker, then serves columns until the shell
and interior are done, then places the special blocks and reports
`BUILD COMPLETE`. Workers park on the staging line — pick them up (or have the
master dig them). Activate the controller to start the reactor.

---

## Tuning & caveats

- **Collisions:** workers separate by altitude, but they share one depot dock.
  With a big swarm two workers may want to restock at once. Start with 4–6
  workers; raise `restockTo` so they restock less often.
- **Fuel:** turtles burn any combustible they carry (`nav:ensureFuel`). Give
  each turtle some coal/charcoal, or add a fuel item to your ME system and a
  bulk kind for it. Or use a fuel mod / refueled turtles.
- **Special block placement** assumes the outside face of that wall is reachable
  open air. Keep the chosen walls clear, or place those few blocks by hand.
- **ME Bridge API:** this uses `meBridge.exportItem({name=,count=}, dir)` and
  `meBridge.listItems()`. If your Advanced Peripherals version differs, adjust
  `depot.lua` / `listitems.lua` accordingly.
- **`require`:** all files must sit in the **same directory** on each unit so
  `require("config")` etc. resolve.
- This is a large, real-world automation. Test on a **small** reactor first
  (e.g. set width/height/depth to 5) with 2 workers before going to max size.

---

## Files

| File | Role |
|------|------|
| `config.lua` | All tunables (edit this) |
| `plan.lua` | Generates the block-per-cell reactor plan |
| `nav.lua` | GPS calibration + movement + obstacle clearing |
| `protocol.lua` | rednet message helpers |
| `master.lua` | Deploys swarm, serves columns, places specials |
| `worker.lua` | Builds columns, restocks from the depot |
| `depot.lua` | Exports items from the ME Bridge to docked turtles |
| `startup.lua` | Auto-runs the right role on boot |
| `install.lua` | Sets role + label |
| `listitems.lua` | Prints real item ids from your AE2 network |
