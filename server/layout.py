"""
layout.py - Reactor schematic, footprint partition, and per-layer GCODE.

Mirrors the block rules of the old single-turtle builder, but with NO component
cells: the controller / power taps / ports are left as casing or glass and you
place the real ones by hand afterwards (per the design doc).

Block keys returned by block_at: "casing", "glass", "fuelRod", "controlRod",
"coolant" (or None for air). The server maps keys -> real registry IDs via
config["blocks"].

Local coords lx,ly,lz are 0-based offsets from origin:
    lx 0..size.x-1, ly 0..size.y-1 (height), lz 0..size.z-1
"""


def is_fuel_column(cfg, lx, lz):
    p = cfg.get("fuelPattern", "checkerboard")
    if p == "full":
        return True
    if p == "spaced":
        s = cfg.get("fuelSpacing", 2) or 2
        return (lx - 1) % s == 0 and (lz - 1) % s == 0
    return (lx + lz) % 2 == 0  # checkerboard


def block_at(cfg, lx, ly, lz):
    sx, sy, sz = cfg["size"]["x"], cfg["size"]["y"], cfg["size"]["z"]
    minx, maxx = lx == 0, lx == sx - 1
    miny, maxy = ly == 0, ly == sy - 1
    minz, maxz = lz == 0, lz == sz - 1
    ex = sum((minx, maxx, miny, maxy, minz, maxz))

    if ex >= 2:
        return "casing"                       # edges & corners
    if ex == 1:                               # a flat face
        if maxy and is_fuel_column(cfg, lx, lz):
            return "controlRod"               # top cap above a fuel column
        if cfg.get("useGlassWalls") and not miny and not maxy:
            return "glass"                    # see-through side walls only
        return "casing"
    # interior
    if is_fuel_column(cfg, lx, lz):
        return "fuelRod"
    if cfg["blocks"].get("coolant"):
        return "coolant"
    return None                               # empty (air) interior


def cruise_base_y(cfg):
    if cfg.get("cruiseBaseY") is not None:
        return cfg["cruiseBaseY"]
    return cfg["origin"]["y"] + cfg["size"]["y"] + 4


# ---------------------------------------------------------------------------
# Footprint partition into a compact grid of N chunks
# ---------------------------------------------------------------------------
def _grid_dims(n, sx, sz):
    """Pick cols(x) x rows(z) == n with chunk aspect closest to square."""
    best = None
    for cols in range(1, n + 1):
        if n % cols:
            continue
        rows = n // cols
        score = abs((sx / cols) - (sz / rows))
        if best is None or score < best[0]:
            best = (score, cols, rows)
    return best[1], best[2]


def _splits(total, parts):
    base, extra = divmod(total, parts)
    out, cur = [], 0
    for i in range(parts):
        w = base + (1 if i < extra else 0)
        out.append((cur, cur + w - 1))
        cur += w
    return out


def partition(cfg, n):
    sx, sz = cfg["size"]["x"], cfg["size"]["z"]
    n = max(1, min(n, sx * sz))
    cols, rows = _grid_dims(n, sx, sz)
    chunks, idx = [], 0
    for (x0, x1) in _splits(sx, cols):
        for (z0, z1) in _splits(sz, rows):
            chunks.append({"index": idx, "x0": x0, "x1": x1, "z0": z0, "z1": z1})
            idx += 1
    return chunks


# ---------------------------------------------------------------------------
# Per-layer GCODE for one chunk: ordered placements + resource manifest
# ---------------------------------------------------------------------------
def layer_plan(cfg, chunk, ly):
    ox, oy, oz = cfg["origin"]["x"], cfg["origin"]["y"], cfg["origin"]["z"]
    blocks = cfg["blocks"]
    needs, place = {}, []
    fwd = True
    for lx in range(chunk["x0"], chunk["x1"] + 1):
        zr = (range(chunk["z0"], chunk["z1"] + 1) if fwd
              else range(chunk["z1"], chunk["z0"] - 1, -1))
        for lz in zr:
            key = block_at(cfg, lx, ly, lz)
            if key:
                bid = blocks.get(key)
                if bid:
                    place.append({"x": ox + lx, "y": oy + ly, "z": oz + lz, "b": bid})
                    needs[bid] = needs.get(bid, 0) + 1
        fwd = not fwd
    return needs, place


def totals(cfg):
    t = {}
    sx, sy, sz = cfg["size"]["x"], cfg["size"]["y"], cfg["size"]["z"]
    for lx in range(sx):
        for ly in range(sy):
            for lz in range(sz):
                k = block_at(cfg, lx, ly, lz)
                if k:
                    bid = cfg["blocks"].get(k)
                    if bid:
                        t[bid] = t.get(bid, 0) + 1
    return t


def validate(cfg):
    s = cfg["size"]
    if min(s["x"], s["y"], s["z"]) < 3:
        return False, "reactor must be at least 3x3x3"
    if not cfg.get("restock", {}).get("docks"):
        return False, "no restock docks configured"
    return True, "ok"
