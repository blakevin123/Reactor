# Reactor Builder (ComputerCraft + Extreme Reactors + AE2)

Automates building an **Extreme Reactors** multiblock with a ComputerCraft
mining turtle. The turtle places the whole structure (clearing anything in the
way) and restocks blocks + fuel straight from an Advanced Peripherals **ME
Bridge**.

> For ATM10-style packs (CC:Tweaked + Extreme Reactors + Advanced Peripherals +
> AE2). **Verify the block IDs for your pack** (F3+H advanced tooltips).

---

## Recommended: single turtle — `reactor.lua`

One turtle, one program, no GPS / rednet / second computer. **Start here.**

### 1. Set up the dock (vertical stack)
```
   [ turtle start/home ]   <- turtle sits here, sucks DOWN
   [ chest / barrel     ]   <- ME Bridge fills this
   [ ME Bridge          ]   <- exports "up" into the chest
```
For the turtle to **command** the ME Bridge it must be on the bridge's wired
network: give the turtle a **Wired Modem** upgrade (+ a pickaxe), put a wired
modem on the ME Bridge, and cable it to a wired modem block next to the home
cell. Don't want to bother? Set `useMEBridge = false` and just keep the dock
chest filled yourself — the turtle will `suckDown` from it.

### 2. Equip & fuel the turtle
- A **pickaxe** (to dig/clear), and a **wired modem** if `useMEBridge = true`.
- Some **coal/charcoal in slot 16** to get started.

### 3. Install
```
wget https://raw.githubusercontent.com/blakevin123/Reactor/main/reactor.lua
```

### 4. Edit the CONFIG block at the top of `reactor.lua`
```
edit reactor.lua
```
Key fields:
- `size` — reactor outer size (incl. casing). Verify your pack's max.
- `origin` — min corner of the reactor (smallest X/Y/Z), world coords.
- `start` — the block the turtle is **placed on** + the way it **faces**
  (`north/south/east/west`). The turtle dead-reckons from here, so this must be
  exact. Read it with F3.
- `home` — dock cell it returns to (usually = `start`); it sucks from the block
  **below** this cell.
- `blocks` — registry IDs for your pack.
- `fuelPattern` (`checkerboard`/`full`/`spaced`), `reactorType`
  (`passive`/`active`), `useGlassWalls`, `coolant`.

### 5. Place the turtle on `start` (facing the set direction) and run
```
reactor
```
It prints a plan + ME stock check, flags any **SHORT** items, waits 5s
(Ctrl+T aborts), tops up at the dock, then builds bottom-to-top. When it
finishes: insert fuel via the **Access Port** and activate the **Controller**.

### Tips
- **Test small first:** set `size = {x=5,y=5,z=5}` and confirm it forms a valid
  multiblock before scaling to 32³.
- The turtle always restocks **before** the first layer and whenever it runs
  low, so it starts empty and that's fine.
- Pre-craft the single components (controller, power tap, access/computer port)
  and enough bulk blocks; the plan printout tells you exactly how many.
- Build site clear of obstructions is fastest, but it will dig through terrain
  inside the build volume and along its path.

---

## Advanced: the multi-turtle swarm

The repo also contains the original swarm (`master.lua`, `worker.lua`,
`supply.lua`, `config.lua`, `layout.lua`, `geo.lua`, `disk/startup.lua`) which
splits the build across several turtles coordinated over rednet, with a separate
ME Bridge supply server. It's faster but much more setup (GPS constellation,
programming dock, per-turtle modems/fuel, dock locks). Prefer `reactor.lua`
unless you specifically need the parallelism.

---

## Block IDs (verify!)

Defaults use the `bigreactors:reinforced_*` IDs. Confirm each with F3+H, or in
the Lua prompt next to the bridge:
```
m = peripheral.find("me_bridge")
for _,it in ipairs(m.getItems()) do if it.name:find("reactor") then print(it.name, it.count) end end
```
The bare registry name (no `[axis=y]` / `[facings=none]` blockstate suffix) is
what goes in `blocks`.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `ME Bridge: NOT FOUND` | turtle not on the wired network — equip a wired modem, check the modem/cable to the bridge, or set `useMEBridge=false` |
| turtle won't move | no fuel (put coal in slot 16) or boxed in |
| builds in the wrong place | `start` coords/facing don't match where you actually placed it |
| item shows SHORT | not enough in AE2 — craft/stock more (the plan lists the needed count) |
| multiblock won't form | wrong IDs, size over the pack's max, or a misplaced/duplicate component |
