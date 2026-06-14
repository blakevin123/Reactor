"""
server.py - Reactor swarm backend.

Generates the build plan from config.json, divides the footprint into one chunk
per worker, and serves each worker its per-layer GCODE + resource manifest over
HTTP. Manages a per-dock lock so workers sharing an ME Bridge don't collide, and
hosts a live monitor page where you can edit the reactor size and position.

Run:  python server/server.py
Then open  http://localhost:8080/  (or your LAN IP / ngrok URL).

No third-party dependencies - stdlib only.
"""

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import layout

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "config.json")

# ---------------------------------------------------------------------------
# Shared state (guarded by LOCK)
# ---------------------------------------------------------------------------
LOCK = threading.Lock()
cfg = {}
chunks = []          # list of chunk dicts
totals = {}          # id -> count for the whole reactor
workers = {}         # turtleId -> {chunkIndex, dockIndex, cruiseY, layer, placed, done}
dock_holder = {}     # dockIndex -> turtleId or None
next_chunk = 0       # next chunk to hand out


def load_config():
    global cfg
    with open(CONFIG_PATH, "r") as f:
        cfg = json.load(f)


def save_config():
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)


def regenerate():
    """(Re)build the plan and reset all runtime state. Call under LOCK."""
    global chunks, totals, workers, dock_holder, next_chunk
    chunks = layout.partition(cfg, cfg.get("workerCount", 8))
    totals = layout.totals(cfg)
    workers = {}
    dock_holder = {i: None for i in range(len(cfg["restock"]["docks"]))}
    next_chunk = 0


# ---------------------------------------------------------------------------
# Request handling
# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass  # quiet

    # -- helpers ------------------------------------------------------------
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, html, code=200):
        body = html.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n).decode() if n else ""

    def _read_json(self):
        raw = self._read_body()
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            return {}

    # -- GET ----------------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            self._html(monitor_html())
        elif u.path == "/status":
            with LOCK:
                self._json(status_obj())
        elif u.path == "/work":
            q = parse_qs(u.query)
            wid = (q.get("id") or ["?"])[0]
            layer = int((q.get("layer") or ["0"])[0])
            with LOCK:
                self._json(work_for(wid, layer))
        else:
            self._json({"error": "not found"}, 404)

    # -- POST ---------------------------------------------------------------
    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/register":
            data = self._read_json()
            with LOCK:
                self._json(register(str(data.get("id"))))
        elif u.path == "/dock/acquire":
            data = self._read_json()
            with LOCK:
                self._json(dock_acquire(str(data.get("id")), int(data.get("dock", -1))))
        elif u.path == "/dock/release":
            data = self._read_json()
            with LOCK:
                dock_release(str(data.get("id")), int(data.get("dock", -1)))
                self._json({"ok": True})
        elif u.path == "/progress":
            data = self._read_json()
            with LOCK:
                progress(str(data.get("id")), data)
                self._json({"ok": True})
        elif u.path == "/done":
            data = self._read_json()
            with LOCK:
                w = workers.get(str(data.get("id")))
                if w:
                    w["done"] = True
                self._json({"ok": True})
        elif u.path == "/config":
            self.apply_config_form(self._read_body())
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
        else:
            self._json({"error": "not found"}, 404)

    def apply_config_form(self, raw):
        form = parse_qs(raw)

        def num(key, default):
            try:
                return int(form.get(key, [default])[0])
            except (ValueError, TypeError):
                return default

        with LOCK:
            cfg["size"] = {"x": num("sx", cfg["size"]["x"]),
                           "y": num("sy", cfg["size"]["y"]),
                           "z": num("sz", cfg["size"]["z"])}
            cfg["origin"] = {"x": num("ox", cfg["origin"]["x"]),
                             "y": num("oy", cfg["origin"]["y"]),
                             "z": num("oz", cfg["origin"]["z"])}
            cfg["home"] = {"x": num("hx", cfg["home"]["x"]),
                           "y": num("hy", cfg["home"]["y"]),
                           "z": num("hz", cfg["home"]["z"])}
            cfg["fuelPattern"] = (form.get("fuelPattern", [cfg.get("fuelPattern")])[0])
            cfg["useGlassWalls"] = ("useGlassWalls" in form)
            coolant = form.get("coolant", [""])[0].strip()
            cfg["blocks"]["coolant"] = coolant or None
            # docks: one "x,y,z" per line. Only replace if at least one parses,
            # so a stray submit can't wipe them.
            docks = []
            for line in form.get("docks", [""])[0].replace("\r", "").split("\n"):
                parts = [p.strip() for p in line.split(",")]
                if len(parts) == 3:
                    try:
                        docks.append({"x": int(parts[0]), "y": int(parts[1]), "z": int(parts[2])})
                    except ValueError:
                        pass
            if docks:
                cfg["restock"]["docks"] = docks
            save_config()
            regenerate()


# ---------------------------------------------------------------------------
# Endpoint logic (call under LOCK)
# ---------------------------------------------------------------------------
def register(wid):
    global next_chunk
    if wid in workers:
        w = workers[wid]
    else:
        if next_chunk >= len(chunks):
            return {"assigned": False, "reason": "no chunks left"}
        ci = next_chunk
        next_chunk += 1
        di = ci % len(cfg["restock"]["docks"])
        w = {"chunkIndex": ci, "dockIndex": di,
             "cruiseY": layout.cruise_base_y(cfg) + ci,
             "layer": 0, "placed": 0, "done": False}
        workers[wid] = w
    dock = cfg["restock"]["docks"][w["dockIndex"]]
    return {"assigned": True, "chunkIndex": w["chunkIndex"], "dockIndex": w["dockIndex"],
            "cruiseY": w["cruiseY"], "dock": dock, "home": cfg["home"],
            "origin": cfg["origin"], "size": cfg["size"],
            "fuelItem": cfg.get("fuelItem", "minecraft:coal")}


def work_for(wid, layer):
    w = workers.get(wid)
    if not w:
        return {"error": "not registered"}
    if layer >= cfg["size"]["y"]:
        return {"done": True}
    chunk = chunks[w["chunkIndex"]]
    needs, place = layout.layer_plan(cfg, chunk, layer)
    return {"done": False, "layer": layer, "cruiseY": w["cruiseY"],
            "needs": needs, "place": place}


def dock_acquire(wid, di):
    if di not in dock_holder:
        return {"granted": False}
    if dock_holder[di] in (None, wid):
        dock_holder[di] = wid
        return {"granted": True}
    return {"granted": False}


def dock_release(wid, di):
    if dock_holder.get(di) == wid:
        dock_holder[di] = None


def progress(wid, data):
    w = workers.get(wid)
    if w:
        w["layer"] = int(data.get("layer", w["layer"]))
        w["placed"] = w.get("placed", 0) + int(data.get("placed", 0))


def status_obj():
    return {
        "size": cfg["size"], "origin": cfg["origin"],
        "fuelPattern": cfg.get("fuelPattern"), "useGlassWalls": cfg.get("useGlassWalls"),
        "coolant": cfg["blocks"].get("coolant"),
        "layers": cfg["size"]["y"], "chunks": len(chunks),
        "totals": totals,
        "docks": dock_holder,
        "workers": workers,
    }


# ---------------------------------------------------------------------------
# Monitor page
# ---------------------------------------------------------------------------
def monitor_html():
    s = status_obj()
    rows = ""
    for wid, w in sorted(s["workers"].items()):
        pct = int(100 * w["layer"] / max(1, s["layers"]))
        rows += (f"<tr><td>{wid}</td><td>{w['chunkIndex']}</td><td>{w['dockIndex']}</td>"
                 f"<td>{w['layer']}/{s['layers']}</td><td>{pct}%</td>"
                 f"<td>{'done' if w['done'] else 'building'}</td></tr>")
    if not rows:
        rows = "<tr><td colspan=6><i>no workers registered yet</i></td></tr>"

    tot = "".join(f"<tr><td>{bid}</td><td>{n}</td></tr>" for bid, n in sorted(s["totals"].items()))
    grand = sum(s["totals"].values())
    docks = ", ".join(f"#{i}:{(h or '-')}" for i, h in s["docks"].items())
    glass_checked = "checked" if s["useGlassWalls"] else ""
    home = cfg["home"]
    docks_text = "\n".join(f"{d['x']},{d['y']},{d['z']}" for d in cfg["restock"]["docks"])

    return f"""<!doctype html><html><head><meta charset=utf-8>
<meta http-equiv=refresh content=3>
<title>Reactor Swarm</title>
<style>
 body{{font-family:monospace;background:#111;color:#ddd;margin:24px;}}
 h2{{color:#7cf}} table{{border-collapse:collapse;margin:8px 0}}
 td,th{{border:1px solid #444;padding:3px 8px;text-align:left}}
 input[type=number]{{width:70px;background:#222;color:#ddd;border:1px solid #555}}
 input[type=text]{{background:#222;color:#ddd;border:1px solid #555}}
 button{{background:#284;color:#fff;border:0;padding:6px 14px;cursor:pointer}}
 .box{{display:inline-block;vertical-align:top;margin-right:40px}}
</style></head><body>
<h2>Reactor Build Swarm</h2>
<div class=box>
<h3>Reactor (edit &amp; regenerate)</h3>
<form method=post action=/config>
 size&nbsp; X<input type=number name=sx value={s['size']['x']}>
 Y<input type=number name=sy value={s['size']['y']}>
 Z<input type=number name=sz value={s['size']['z']}><br>
 origin X<input type=number name=ox value={s['origin']['x']}>
 Y<input type=number name=oy value={s['origin']['y']}>
 Z<input type=number name=oz value={s['origin']['z']}><br>
 home&nbsp; X<input type=number name=hx value={home['x']}>
 Y<input type=number name=hy value={home['y']}>
 Z<input type=number name=hz value={home['z']}><br>
 pattern<input type=text name=fuelPattern value="{s['fuelPattern']}">
 coolant<input type=text name=coolant value="{s['coolant'] or ''}">
 glass<input type=checkbox name=useGlassWalls {glass_checked}><br>
 restock docks (one <b>x,y,z</b> per line - the cell ON TOP of each bridge):<br>
 <textarea name=docks rows=5 cols=22 style="background:#222;color:#ddd;border:1px solid #555">{docks_text}</textarea><br>
 <button type=submit>Save &amp; Regenerate</button>
 <small>(resets build state - do before deploying)</small>
</form>
</div>
<div class=box>
<h3>Plan</h3>
layers: {s['layers']} &nbsp; chunks: {s['chunks']}<br>
<table><tr><th>block</th><th>count</th></tr>{tot}
<tr><th>TOTAL</th><th>{grand}</th></tr></table>
</div>
<h3>Workers</h3>
<table><tr><th>id</th><th>chunk</th><th>dock</th><th>layer</th><th>%</th><th>state</th></tr>
{rows}</table>
<p>dock holders: {docks}</p>
</body></html>"""


# ---------------------------------------------------------------------------
def main():
    load_config()
    with LOCK:
        regenerate()
    ok, why = layout.validate(cfg)
    if not ok:
        print("CONFIG WARNING:", why)
    host = cfg["server"]["host"]
    port = cfg["server"]["port"]
    print(f"Reactor swarm server on http://{host}:{port}/  (monitor)")
    print(f"  reactor {cfg['size']['x']}x{cfg['size']['y']}x{cfg['size']['z']} "
          f"at ({cfg['origin']['x']},{cfg['origin']['y']},{cfg['origin']['z']}), "
          f"{len(chunks)} chunks, {len(cfg['restock']['docks'])} docks")
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
