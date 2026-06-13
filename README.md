# Reactor Build Swarm (ComputerCraft + Extreme Reactors + AE2)

Automates building a **max-size Extreme Reactors** multiblock with a swarm of
ComputerCraft mining turtles. A master turtle deploys & auto-programs the
workers, the workers build the reactor layer-by-layer (clearing any blocks in
the way), and they restock blocks + fuel from your AE2 system through an
Advanced Peripherals **ME Bridge**.

> Built for ATM10-style packs (CC:Tweaked + Extreme Reactors + Advanced
> Peripherals + Applied Energistics 2). **Verify the block IDs for your exact
> pack version** — see step 3.

---

## Files

| File | Runs on | Purpose |
|------|---------|---------|
| `config.lua` | everyone | All the variables: size, location, block IDs, station coords, channels |
| `geo.lua` | everyone | Direction/vector math (pure, no turtle calls) |
| `layout.lua` | master | Generates the reactor schematic (`blockAt`, `totals`, `partition`) |
| `worker.lua` | worker turtles | Navigate, clear, place blocks, restock |
| `master.lua` | master turtle | Validate plan, partition work, deploy + coordinate |
| `supply.lua` | base computer | ME Bridge exports + single-file dock lock |
| `disk/startup.lua` | programming floppy | Bootstraps a blank turtle into a worker |

---

## How it works (the short version)

1. **layout.lua** turns your config into a rule: for every cell of the box it
   returns which block goes there (casing on edges/walls, fuel-rod columns +
   control-rod caps inside, controller/ports on the front face).
2. **master.lua** splits the footprint into vertical **strips** — one per
   worker — along the longer horizontal axis. Strips never share a column, so
   workers can't collide while building.
3. Each **worker** builds its strip **bottom-to-top, always placing the block
   directly below itself** (`placeDown`). This means a worker can never trap
   itself, and only ever occupies its own strip's airspace.
4. For transit (restock runs) each worker gets a **unique cruise altitude**, and
   the supply station hands out a **dock lock** so only one worker draws items
   at a time. Together these make collisions essentially impossible.
5. **supply.lua** uses the **ME Bridge** to push the exact blocks/fuel a worker
   asks for into the supply chest; the worker `suckDown`s them.

---

## Setup

### 1. GPS constellation (required)

Workers navigate by world coordinates, so you need a working GPS network in
range of the whole build. Standard CC setup: 4 computers high up, each with a
wireless/ender modem, each running `gps host` with its real coordinates. See the
CC:Tweaked GPS tutorial. Test with `gps locate` on a turtle at the build site —
it must return real coordinates.

### 2. Get the files onto a computer

Put this whole folder onto an in-game computer. Easiest options:

- **Pastebin / GitHub**: upload the files and `wget`/`pastebin get` them, or
- **Manual**: open each file with `edit <name>` and paste the contents.

Keep them together; the master and supply load `config.lua`, `geo.lua`,
`layout.lua` from their own root.

### 3. Verify block IDs (do this first!)

The defaults in `config.lua` use the `bigreactors:` namespace. **They may differ
in your pack.** For each reactor part: hold it, press **F3+H** to turn on
advanced tooltips, and read the registry name. Update `cfg.blocks` to match.

When you run `supply.lua` it prints a self-check and **warns about any ID it
can't find in your ME system** — use that to catch typos before building.

### 4. Edit `config.lua`

The important ones:

```lua
cfg.size   = { x = 32, y = 32, z = 32 }   -- outer size (check your pack's max!)
cfg.origin = { x = 0, y = 70, z = 0 }     -- minimum corner, in world coords
cfg.fuelPattern = "checkerboard"          -- or "full" / "spaced"
cfg.reactorType = "passive"               -- or "active"
cfg.workerCount = 4
cfg.station.dock = { x = -4, y = 72, z = 0 }  -- where workers draw items
cfg.autoDeploy   = false                  -- true to auto-place worker turtles
```

`origin` is the **min corner** (smallest X/Y/Z). The reactor grows in +X, +Y
(up), +Z from there. The **front face** (where the controller/ports go) is the
min-Z face.

### 5. Build the supply station

```
        [ worker dock cell ]   <- cfg.station.dock   (worker sits here)
        [ supply chest      ]   <- bridge exports "up" into this
        [ ME Bridge         ]   <- wired into your AE2 network
   [supply computer] touches the ME Bridge, + a wireless/ender modem on another side
```

- The **dock cell** must be the block directly above the chest, and its world
  coordinates must match `cfg.station.dock`.
- Make sure the column **above the dock is clear air** up to cruise altitude so
  workers can descend/ascend freely.
- Put the AE2 stock of every reactor block (and charcoal, `cfg.fuelItem`) in the
  network, or mark them auto-craftable (supply.lua will try to craft shortfalls).

Run it:

```
supply
```

It hosts as `supply`, prints the stock self-check, and waits.

### 6. Run the master

Master turtle needs a **wireless/ender modem upgrade**.

```
master
```

It validates the config, prints the full block plan + per-worker strips, hosts
as `master`, then either auto-deploys (if `cfg.autoDeploy`) or waits for you to
place workers.

### 7. Workers

**Option A — manual (reliable, recommended first run):**
Pre-program a few turtles, or place blank turtles next to a disk drive holding
the programming floppy (see step 8). On boot they install themselves and join.
Make sure each worker has a **wireless/ender modem** and some starting fuel.

**Option B — auto-deploy (`cfg.autoDeploy = true`):**
- Build a **programming dock**: a cell with a disk drive (holding the worker
  floppy) on one horizontal side, the other sides open.
- Position the **master turtle directly above** that dock cell (`cfg.progDock`).
- Load a stack of **blank turtles** into master slot 1.
- The master places one turtle at a time; each boots, programs itself from the
  disk, calibrates, registers, and flies off to its strip.

### 8. Make the programming floppy

On a computer with a disk drive + floppy:

```
copy config.lua  disk/config.lua
copy geo.lua     disk/geo.lua
copy layout.lua  disk/layout.lua
copy worker.lua  disk/worker.lua
copy startup.lua disk/startup.lua     -- this is disk/startup.lua from the repo
```

(The repo already keeps the bootstrap at `disk/startup.lua`.) A blank turtle
placed next to this drive auto-runs the bootstrap on boot.

---

## After the build

When every strip reports done the master prints **ALL STRIPS COMPLETE**. Then:

1. Insert fuel (Yellorium/etc.) through the **Access Port**.
2. Activate the **Reactor Controller**.
3. (Optional) wire the **Computer Port** and a **Reactor Computer Port** program
   for live control.

---

## Tuning & notes

- **Reactor type**: `passive` uses a Power Tap and an empty interior (simplest).
  `active` swaps in Coolant Ports and (if you set `cfg.blocks.coolant`) fills the
  non-fuel interior with a coolant/moderator block.
- **Fuel pattern**: `checkerboard` (default) spaces fuel for efficiency; `full`
  packs every interior column with fuel; `spaced` uses `cfg.fuelSpacing`.
- **More workers = faster + fewer restock trips** (smaller strips, fewer blocks
  per layer per worker). Keep `cfg.workerCount` ≤ the longer horizontal size.
- **Clearing**: workers dig anything inside the build volume or in their flight
  path (but never other turtles). A pre-cleared, open-air site is fastest and
  safest. Mined junk that overflows a turtle's inventory is dropped in-world; add
  an AE2 import bus / hopper if you want it auto-returned.
- **Fuel**: workers refuel from charcoal (`cfg.fuelItem`) drawn at the dock.
  Keep plenty in AE2.
- **Restarts**: workers install a local `startup.lua`, so they resume after a
  reboot/chunk reload. The master/supply should be restarted manually if the
  server stops.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `no GPS fix` | GPS constellation not running / out of range |
| `could not find rednet host` | master/supply not started, or wrong modem |
| supply self-check warns `0 in stock / wrong ID` | wrong block ID or not in AE2 |
| Multiblock won't form after build | wrong IDs, size over the pack's max, or a missing/duplicated component cell (master's `validate` catches the obvious cases) |
| Worker `boxed in` on calibrate | leave at least one horizontal side of its start cell open |
| Turtles bunch up at the base | expected briefly during deploy; the dock lock + unique cruise altitudes resolve it |
