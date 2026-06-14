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

### 1. Set up the dock (just two blocks)
```
   [ turtle start/home ]   <- turtle sits on top of the bridge
   [ ME Bridge          ]   <- exports "up" straight into the turtle
```
The turtle restocks by calling `me.exportItem({name=ID, count=N}, "up")`, which
pushes items directly up into its own inventory — **no chest, no wired modem**.
It pulls fuel the same way, so it can even start with an empty tank.

### 2. Equip the turtle
- A **pickaxe** (to dig/clear). That's it — fuel comes from the ME system.

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
| `ME Bridge: NOT FOUND` | turtle isn't sitting on top of the ME Bridge, or the block isn't an Advanced Peripherals ME Bridge |
| turtle won't move | tank empty and ME has no coal, or it's boxed in |
| builds in the wrong place | `start` coords/facing don't match where you actually placed it |
| item shows SHORT | not enough in AE2 — craft/stock more (the plan lists the needed count) |
| multiblock won't form | wrong IDs, size over the pack's max, or a misplaced/duplicate component |
