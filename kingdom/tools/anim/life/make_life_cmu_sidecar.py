# Writes <lib>.life.json (living-world sidecar, same schema as author_life.py) for the CMU-mocap life library
# UAL_Life_Mocap.glb, from cfg_life_cmu.json (per clip: take, window, category, tags, note, pair_key) + the
# retarget report <lib>.clips.json (frames, seconds, root travel) + the raw BVH takes (partner geometry of the A/B pairs).
#
#   ANIM_SRC=... python tools/anim/life/make_life_cmu_sidecar.py [cfg] [glb]
#
# pair = {"partner": "<other clip>", "distance": m, "yaw_deg": deg, ...}, measured on the raw BVHs at the clip window:
#   distance   hip-to-hip distance in metres (BVH units x the mean retarget hip scale) at the moment the pair meets
#              (handshake: the last frame of the window; every other pair: the mean over the window)
#   yaw_deg    facing of the partner minus the facing of this clip's actor (+ = counter-clockwise from above).
#              ~180 = the two face each other. Every clip is retargeted with the actor's mean facing = UAL forward.
#   bearing_deg  direction from this actor to the partner, relative to this actor's facing (+ = to the actor's left, 0 = ahead)
#   distance_start  distance at the first frame (handshake: how far apart the actors start; root travel of the clip closes it)
import json, os, re, sys, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
CFG = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "cfg_life_cmu.json")
cfg = json.load(open(CFG, encoding="utf-8"))
OUT = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.normpath(os.path.join(os.path.dirname(CFG), cfg["out"]))
ANIM_SRC = os.environ.get("ANIM_SRC", os.path.join(os.path.expanduser("~"), ".cache", "ashes_anim_src"))
BVH_DIR = os.path.expandvars(cfg["bvh_dir"]).replace("${ANIM_SRC}", ANIM_SRC)
if not os.path.isabs(BVH_DIR) or "${" in BVH_DIR:
    BVH_DIR = os.path.join(ANIM_SRC, "cmu-mocap", "data")
report = {c["name"]: c for c in json.load(open(OUT + ".clips.json"))}
lib = "res://" + os.path.relpath(OUT, KING).replace("\\", "/")

# CMU index text (take -> description)
INDEX = {}
idx_path = os.path.join(ANIM_SRC, "cmu-mocap", "cmu-mocap-index-text.txt")
if os.path.exists(idx_path):
    for ln in open(idx_path, encoding="utf-8", errors="replace"):
        m = re.match(r"(\d+)_(\d+)\s+(.*)", ln)
        if m:
            INDEX["%d_%02d" % (int(m.group(1)), int(m.group(2)))] = m.group(3).strip()


def load_bvh(take):
    s, n = take.split("_")
    f = os.path.join(BVH_DIR, "%03d" % int(s), "%02d_%02d.bvh" % (int(s), int(n)))
    txt = open(f).read()
    hier, mot = txt.split("MOTION")
    names = re.search(r"ROOT Hips.*?CHANNELS (\d+) (.*?)\n", hier, re.S).group(2).split()
    ft = float(re.search(r"Frame Time:\s*([\d.]+)", mot).group(1))
    data = np.array([[float(x) for x in l.split()] for l in mot.split("\n")[3:] if l.strip()])
    return data, names, ft


def rot(names, row):
    M = np.eye(3)
    for i, n in enumerate(names):
        if n.endswith("rotation"):
            a = math.radians(row[i]); c, s = math.cos(a), math.sin(a)
            R = {"X": [[1, 0, 0], [0, c, -s], [0, s, c]], "Y": [[c, 0, s], [0, 1, 0], [-s, 0, c]],
                 "Z": [[c, -s, 0], [s, c, 0], [0, 0, 1]]}[n[0]]
            M = M @ np.array(R)
    return M


def track(take, t0, t1, k):
    """hip xz (metres) and facing unit vector (xz) per 0.1 s inside [t0,t1]"""
    data, names, ft = load_bvh(take)
    ix, iz = names.index("Xposition"), names.index("Zposition")
    P, F = [], []
    for t in np.arange(t0, t1 + 1e-6, 0.1):
        r = min(len(data) - 1, int(round(t / ft)))
        P.append((data[r, ix] * k, data[r, iz] * k))
        f = rot(names, data[r]) @ np.array([0, 0, 1.0])
        F.append((f[0], f[2]))
    return np.array(P), np.array(F)


def ang(v):
    return math.atan2(v[1], v[0])


def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


def pair_info(ca, cb):
    """geometry of partner b as seen from actor a (raw BVH, the same world frame for both subjects)"""
    ra, rb = report[ca["name"]], report[cb["name"]]
    k = 0.5 * (ra["hip_scale"] + rb["hip_scale"])
    t0, t1 = ca["start"], ca["end"]
    Pa, Fa = track(ca["take"], t0, t1, k)
    Pb, Fb = track(cb["take"], t0, t1, k)
    d = np.hypot(*(Pb - Pa).T)
    fa = Fa.mean(0); fb = Fb.mean(0)
    face_a = ang(fa)
    yaw = wrap(math.degrees(ang(fb) - face_a))
    sel = slice(-3, None) if ca["pair_key"] == "handshake" else slice(None)
    rel = (Pb - Pa)[sel].mean(0)
    # raw BVH world: x = left/right, z = forward-ish; angle measured in the (x,z) plane, so a positive angle is
    # clockwise seen from above. Convert to counter-clockwise (+ = left of the actor) by negating.
    bearing = wrap(-math.degrees(ang(rel) - face_a))
    return {"partner": cb["name"], "distance": round(float(d[sel].mean()), 2), "yaw_deg": round(-yaw, 1),
            "bearing_deg": round(bearing, 1), "distance_start": round(float(d[0]), 2), "distance_end": round(float(d[-1]), 2)}


cl = {c["name"]: c for c in cfg["clips"]}
pairs = {}
for c in cfg["clips"]:
    if c.get("pair_key"):
        pairs.setdefault(c["pair_key"], []).append(c["name"])

LINKS = {"Life_Mocap_Sit_Stool_Idle": ("Life_Mocap_Sit_Stool_Enter", "Life_Mocap_Sit_Stool_Exit")}
EVENTS = {"Life_Mocap_Sit_Stool_Enter": "seated"}

clips = {}
for c in cfg["clips"]:
    name = c["name"]
    if name not in report:
        print("SKIP (not in report)", name)
        continue
    r = report[name]
    loop = bool(c.get("loop"))
    is_walk = c["category"] == "walk/style" or name == "Life_Mocap_Carry_Heavy"
    speed = round(r["travel_m"] / r["seconds"], 2) if (is_walk and loop and r["seconds"] > 0) else 0.0
    pair = None
    if c.get("pair_key"):
        other = [n for n in pairs[c["pair_key"]] if n != name]
        if other:
            pair = pair_info(c, cl[other[0]])
    enter, exit_ = LINKS.get(name, (None, None))
    ev = {}
    if name in EVENTS:
        ev[EVENTS[name]] = [r["frames"] - 1]
    if loop:
        ev["loop_seam"] = [r["frames"] - 1]
    txt = INDEX.get(c["take"], "")
    src = "CMU %s '%s' %g-%g s" % (c["take"], txt, c["start"], c["end"])
    if r.get("loop_pts"):
        src += " (loop cut %.2f-%.2f s into the window, seam error %.1f deg-sum)" % tuple(r["loop_pts"])
    note = c["note"]
    if name == "Life_Mocap_Sit_Stool_Idle":
        note += "; hips end ~0.5 m above the floor, seat top ~0.45 m; play Enter -> Idle loop -> Exit"
    if speed:
        note += "; in-place cycle speed %.2f m/s" % speed
    e = {"category": c["category"], "loop": loop, "layer": "full", "props": [],
         "enter": enter, "exit": exit_,
         "blend_in": 0.2 if is_walk else 0.25, "blend_out": 0.25 if is_walk else 0.3,
         "events": ev, "anchor": None, "note": note, "speed_mps": speed, "pair": pair,
         "ik_l_on_prop": None, "mask_from": None, "tags": ["cmu", "mocap"] + list(c["tags"]),
         "source": src, "frames": r["frames"], "seconds": r["seconds"]}
    if r.get("travel_m", 0) > 0.15 and not is_walk:
        e["root_travel_m"] = r["travel_m"]
    clips[name] = e

notes = ["Source: CMU Graphics Lab Motion Capture Database (free for commercial use; credit in kingdom/CREDITS.md), BVH by Bruce Hahne / cgspeed via una-dinosauria/cmu-mocap.",
         "Rebuild: bash tools/anim/life/fetch_life_cmu.sh; blender -b --python tools/anim/retarget_bvh.py -- tools/anim/life/cfg_life_cmu.json; python tools/anim/glb_reduce_anim.py <glb> --rot-deg 0.3 --pos-m 0.0015; python tools/anim/life/make_life_cmu_sidecar.py",
         "Takes (clip <- take, window s): " + "; ".join("%s <- %s %g-%g" % (n.replace("Life_", ""), c["take"], c["start"], c["end"]) for n, c in cl.items() if n in clips),
         "Every clip faces UAL forward (mean body heading of the window), is in place (travel on the root bone; root_travel_m where > 15 cm) and 30 fps.",
         "Pair clips (_A/_B): same window and length; place B at pair.distance / pair.bearing_deg from A and rotate B by pair.yaw_deg relative to A.",
         "Mocap of pantomime takes (subject 79/80) has no props: tool clips only close the hands (fist fingers); a prop must be attached in game."]
json.dump({"library": lib, "fps": 30, "notes": notes, "clips": clips}, open(OUT + ".life.json", "w"), indent=1)
print("LIFE_SIDECAR", OUT + ".life.json", len(clips))
