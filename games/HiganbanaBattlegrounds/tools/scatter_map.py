"""Section 3: scatter dressing stand-ins over the dry land so no stretch reads empty (T9).

Each prop is a decor box that names the mesh that replaces it (`dressing`). It is
seeded, so re-running gives the same map. Regions decide the kind:
  pine bluff / north rise edge -> PineTree, bamboo ridge -> BambooClump,
  lily hill and the banks      -> SpiderLilyCluster, elsewhere -> Boulder / StoneCairn.
Keeps clear of the riverbed floor (arena), pads, paths, structures and the grove arena.

Run after the terrain is built: python tools/scatter_map.py, then re-prove.
"""

import json
import math
import random
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "design" / "map.json"
h = np.load(ROOT / "build" / "map" / "terrain" / "height.npy")
BIAS, SINK = 2.0, 0.5

SIZES = {
    "PineTree": (16, 26, 16),
    "BambooClump": (8, 20, 8),
    "SpiderLilyCluster": (3, 2.5, 3),
    "Boulder": (8, 5, 7),
    "StoneCairn": (3, 3, 3),
}
COLORS = {
    "PineTree": (52, 74, 50), "BambooClump": (96, 130, 72), "SpiderLilyCluster": (196, 34, 40),
    "Boulder": (120, 118, 112), "StoneCairn": (201, 194, 178),
}


def H(x, z):
    ix = int((x + 320) / 4)
    iz = int((z + 320) / 4)
    if not (0 <= ix < h.shape[1] and 0 <= iz < h.shape[0]):
        return -1e9
    return float(h[iz, ix])


def slope(x, z):
    d = 4.0
    return math.degrees(math.atan(max(abs(H(x + d, z) - H(x - d, z)), abs(H(x, z + d) - H(x, z - d))) / (2 * d)))


spec = json.loads(SPEC.read_text(encoding="utf-8"))
spec["parts"] = [p for p in spec["parts"] if not p["id"].startswith("Scatter")]
t = spec["terrain"]
keepout = [(pd["center"], pd["radius"] + 6) for pd in t["pads"]]
keepout.append(([0, -200], 50))  # the Elder's arena stays open
paths = [pp["points"] for pp in t["paths"]]
solids = [p for p in spec["parts"]]


def near_path(x, z, w=10):
    for pts in paths:
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            vx, vz = bx - ax, bz - az
            L2 = vx * vx + vz * vz or 1
            u = max(0, min(1, ((x - ax) * vx + (z - az) * vz) / L2))
            if math.hypot(ax + u * vx - x, az + u * vz - z) < w:
                return True
    return False


def clear_of_parts(x, z, r):
    for p in solids:
        px, _, pz = p["pos"]
        sx, _, sz = p["size"]
        if abs(px - x) < sx / 2 + r and abs(pz - z) < sz / 2 + r:
            return False
    return True


def kind_at(x, z, y, rng):
    if math.hypot((x - 170) / 80, (z + 140) / 60) < 1 or (z < -150 and abs(x) > 70):
        return "PineTree"
    if math.hypot((x + 120) / 80, (z - 180) / 50) < 1:
        return "BambooClump"
    if math.hypot((x - 150) / 80, (z - 140) / 65) < 1 or rng.random() < 0.45:
        return "SpiderLilyCluster"
    return "Boulder" if rng.random() < 0.6 else "StoneCairn"


rng = random.Random(23)
props = []
STEP = 40
for gz in range(-300, 301, STEP):
    for gx in range(-300, 301, STEP):
        for _ in range(6):
            x = gx + rng.uniform(-STEP / 2, STEP / 2)
            z = gz + rng.uniform(-STEP / 2, STEP / 2)
            y = H(x, z)
            if y < 28 or slope(x, z) > 30:  # skip the riverbed floor, the void and cliffs
                continue
            if any(math.hypot(x - c[0], z - c[1]) < r for c, r in keepout):
                continue
            if near_path(x, z):
                continue
            kind = kind_at(x, z, y, rng)
            sx, sy, sz = SIZES[kind]
            if not clear_of_parts(x, z, max(sx, sz) / 2 + 2):
                continue
            base = min(H(x + dx, z + dz) for dx in (-sx / 2, 0, sx / 2) for dz in (-sz / 2, 0, sz / 2)) + BIAS - SINK
            p = {"id": f"Scatter{len(props)}", "size": [sx, sy, sz],
                 "pos": [round(x, 1), round(base + sy / 2, 2), round(z, 1)],
                 "yaw": rng.randrange(0, 360, 15), "material": "SmoothPlastic",
                 "color": list(COLORS[kind]), "roles": ["prop"], "decor": True, "dressing": kind}
            props.append(p)
            solids.append(p)
            break

spec["parts"] += props
SPEC.write_text(json.dumps(spec, indent=1) + "\n", encoding="utf-8")
counts = {}
for p in props:
    counts[p["dressing"]] = counts.get(p["dressing"], 0) + 1
print(f"scattered {len(props)} props: {counts}")
