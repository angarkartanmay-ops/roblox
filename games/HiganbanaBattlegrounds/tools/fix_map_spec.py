"""Section 3: rewrite design/map.json so the prover passes on the terrain map.

Facts this script works from (roblox-map SKILL.md, measured there):
- P1 grounds against parts only, so a part standing on terrain takes its y from
  the heightfield (build/map/terrain/height.npy) + the ~2-stud surface bias and
  leaves `grounded` off.
- Reachability (P2/P3) walks parts only, so the landing is a flagstone quay part
  that holds the spawns, and a walk part joins it to the bridge.
- T4 counts any column above high tide - 2 as dry land, so the sea floor must
  sit below the tide or the mist sea becomes a trap you cannot climb out of.

Run from the game folder: python tools/fix_map_spec.py
"""

import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "design" / "map.json"
HEIGHT = ROOT / "build" / "map" / "terrain" / "height.npy"
BIAS = 2.0  # smooth terrain surface above the heightfield
SINK = 0.5  # sink a part's base this far below the lowest surface under it

h = np.load(HEIGHT)


def surface(x, z):
    ix = min(max(int((x + 320) / 4), 0), h.shape[1] - 1)
    iz = min(max(int((z + 320) / 4), 0), h.shape[0] - 1)
    return float(h[iz, ix]) + BIAS


def low_surface(x, z, sx, sz, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    pts = []
    for fx in (-0.5, 0.0, 0.5):
        for fz in (-0.5, 0.0, 0.5):
            lx, lz = fx * sx, fz * sz
            pts.append(surface(x + lx * c + lz * s, z - lx * s + lz * c))
    return min(pts)


def on_terrain(part):
    sx, sy, sz = part["size"]
    x, _, z = part["pos"]
    base = low_surface(x, z, sx, sz, part.get("yaw", 0.0)) - SINK
    part["pos"][1] = round(base + sy / 2, 2)
    part.pop("grounded", None)
    return part


spec = json.loads(SPEC.read_text(encoding="utf-8"))
by_id = {p["id"]: p for p in spec["parts"]}

# --- sea floor below the tide (T4) -----------------------------------------
t = spec["terrain"]
t["seaFloor"] = -104
for lf in t["landforms"]:
    if lf["name"] == "FarShore":
        lf["profile"][0] = [-32, -104]
t["note_tide"] = (
    "The sea floor sits below low tide so the mist sea is open water to the "
    "prover (T4) and never a trap; it is 34 studs under the kill plane, so no "
    "player ever reaches it. The edge reads as a sea of mist (Atmosphere)."
)

LAND_TOP = 47.0  # flagstone top; the pad surface is 46
STONE = [214, 208, 196]

parts = []
keep = lambda pid: by_id[pid]  # noqa: E731

# --- bridge ------------------------------------------------------------------
deck = keep("BridgeDeck")
deck.update(size=[18, 3, 160], pos=[0, 44.7, 0])
deck["note"] = "the stone bridge over the riverbed, top at 46.2"
parts.append(deck)
for side, x in (("E", 8.25), ("W", -8.25)):
    p = keep("BridgeParapet" + side)
    p.update(size=[1.5, 3, 160], pos=[x, 47.7, 0])
    parts.append(p)
ramp = keep("BridgeRampN")
ramp.update(size=[18, 1.6, 10], pos=[0, 45.4, -85])
ramp.pop("grounded", None)
parts.append(ramp)
pier = keep("BridgePier")
pier_base = low_surface(0, 0, 12, 10) - SINK
pier_top = 44.7 - 1.5
pier.update(size=[12, round(pier_top - pier_base, 2), 10],
            pos=[0, round((pier_top + pier_base) / 2, 2), 0])
pier["grounded"] = True  # it carries the deck... P1 checks below, so drop it
pier.pop("grounded")
parts.append(pier)

# --- the landing: quay + walk to the bridge (spawns stand on parts) ----------
parts.append({
    "id": "LandingQuay", "size": [66, 1.4, 50], "pos": [0, LAND_TOP - 0.7, 155],
    "material": "Slate", "color": [190, 184, 172], "roles": ["floor", "safe_zone"],
    "note": "the flagstone quay where every soul lands; spawns, the select lantern, the safe zone",
})
parts.append({
    "id": "LandingWalk", "size": [22, 1.4, 50], "pos": [0, LAND_TOP - 0.7, 105],
    "material": "Slate", "color": STONE, "roles": ["floor", "path"],
    "note": "flagstones from the quay through the torii to the bridge's south end",
})
pd = keep("PierDeck")
pd.update(size=[12, 2, 70], pos=[-39, LAND_TOP - 0.6, 105])
pd["note"] = "the ferry pier off the quay's west edge, ending in the air over the dry bank"
parts.append(pd)

for side, x in (("E", 9), ("W", -9)):
    p = keep("ToriiPost" + side)
    p["pos"] = [x, LAND_TOP + 11.5, 104]
    p["grounded"] = True  # stands on LandingWalk
    parts.append(p)
lin = keep("ToriiLintel")
lin["pos"] = [0, LAND_TOP + 23 + 1.2, 104]
parts.append(lin)

lan = keep("SelectLantern")
lan["pos"] = [0, LAND_TOP + 3.5, 128]
lan["grounded"] = True  # on LandingWalk
parts.append(lan)

hut = keep("FerrymanHut")
hut["pos"] = [46, 0, 168]
parts.append(on_terrain(hut))

# --- riverbed cover, Elder -----------------------------------------------------
for pid in ("BoatA", "BoatB", "BoatC", "BoatD", "BoatE",
            "CairnA", "CairnB", "CairnC", "CairnD", "ElderTrunkBlock"):
    parts.append(on_terrain(keep(pid)))

# --- greybox dressing: decor stand-ins the meshes replace (P13) ---------------
def prop(pid, kind, x, z, size, yaw=0, color=(201, 194, 178), material="Slate"):
    p = {"id": pid, "size": list(size), "pos": [x, 0, z], "yaw": yaw,
         "material": material, "color": list(color), "roles": ["prop"],
         "decor": True, "dressing": kind}
    return on_terrain(p)


LANTERN = (2.4, 6, 2.4)
CAIRN = (3, 3, 3)
JIZO = (1.6, 3.2, 1.4)
props = []
# stone lanterns along both sides of the walk (they stand beside it on terrain)
for i, z in enumerate((86, 100, 114, 126)):
    for side, x in (("E", 15), ("W", -15)):
        props.append(prop(f"WalkLantern{side}{i}", "StoneLantern", x, z, LANTERN))
# lanterns either side of the select lantern sit on the walk itself
for side, x in (("E", 5), ("W", -5)):
    p = {"id": f"SelectLanternSide{side}", "size": list(LANTERN),
         "pos": [x, LAND_TOP + 3, 128], "material": "Slate", "color": [201, 194, 178],
         "roles": ["prop"], "decor": True, "dressing": "StoneLantern"}
    props.append(p)
# around the hut
for i, (dx, dz) in enumerate(((-14, -4), (-14, 6), (14, -6), (14, 6), (-6, -12), (6, -12))):
    kind = "StoneLantern" if i < 2 else "StoneCairn"
    props.append(prop(f"HutProp{i}", kind, 46 + dx, 168 + dz, LANTERN if i < 2 else CAIRN))
# along the pier's shore (cairns on the bank beside it)
for i, z in enumerate((76, 88, 100, 112, 124)):
    props.append(prop(f"PierCairn{i}", "StoneCairn", -52, z, CAIRN))
# the Elder's grove: lanterns and cairns ringed round the trunk
for i in range(8):
    a = math.radians(i * 45 + 22.5)
    x, z = round(34 * math.cos(a), 1), round(-215 + 34 * math.sin(a), 1)
    kind = "StoneLantern" if i % 2 == 0 else "StoneCairn"
    props.append(prop(f"GroveProp{i}", kind, x, z, LANTERN if i % 2 == 0 else CAIRN))
# the Jizo beach: a row of statues along the cove's back and cairns on the bar
for i in range(10):
    a = math.radians(200 + i * 14)
    x, z = round(-196 + 30 * math.cos(a), 1), round(40 + 30 * math.sin(a), 1)
    props.append(prop(f"Jizo{i}", "JizoStatue", x, z, JIZO,
                      yaw=round(-math.degrees(a) - 90), color=(170, 166, 158)))
for i, (x, z) in enumerate(((-210, 30), (-186, 54), (-176, 28), (-204, 58), (-190, 18), (-218, 46))):
    props.append(prop(f"BeachCairn{i}", "StoneCairn", x, z, CAIRN))

spec["parts"] = parts + props
spec["spawns"] = [[x, LAND_TOP + 1, z] for x, z in
                  ((0, 150), (-16, 146), (16, 146), (-12, 164), (12, 164), (0, 174))]
spec["intent"] = {
    "reachable": ["BridgeDeck", "PierDeck", "LandingQuay", "LandingWalk", "BridgeRampN"],
    "transit": ["BridgePier", "ToriiPost*", "ToriiLintel", "BridgeParapet*",
                "SelectLantern", "FerrymanHut", "ElderTrunkBlock"],
    "note": (
        "Parts-only reachability: the quay, the walk, the pier and the bridge form one "
        "walkable stone network from the spawns. Terrain reachability (banks, riverbed, "
        "beach, grove, hills) is proven by T4 on the heightfield. Posts, lantern, hut, "
        "pier and trunk are not destinations."
    ),
}
spec["parts_are_deliberate"] = (
    "greybox: every decor part names the dressing mesh that replaces it (dressing field); "
    "section 3 swaps them for meshes"
)
SPEC.write_text(json.dumps(spec, indent=1) + "\n", encoding="utf-8")
print(f"wrote {SPEC}: {len(parts)} structural + {len(props)} decor parts")
