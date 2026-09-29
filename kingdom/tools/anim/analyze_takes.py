# Segment CMU BVH takes into candidate "moves" (pure numpy, no Blender needed - run
# with any python that has numpy, or `blender -b --python analyze_takes.py -- ...`).
#
# For every take: forward kinematics of hips/hands/feet, an overall motion-energy
# curve, pauses (energy below threshold) split the take into segments, and each
# segment reports its dominant effector (which hand/foot moved fastest), peak
# effector height relative to the hips (kick height), path travel and duration.
# Output: JSON list used to author cfg_free_*.json trims.
#
# usage: python analyze_takes.py <bvh_dir> out.json 144/144_05 144/144_06 ...
import sys, json, re, os, math
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
bvh_dir, out_json, takes = argv[0], argv[1], argv[2:]

def parse(path):
    txt = open(path).read()
    hier, motion = txt.split("MOTION")
    names, parents, offs, chans = [], [], [], []
    stack = []
    for ln in hier.splitlines():
        t = ln.split()
        if not t:
            continue
        if t[0] in ("ROOT", "JOINT"):
            names.append(t[1]); parents.append(stack[-1] if stack else -1)
            stack.append(len(names) - 1); offs.append(None); chans.append([])
            cur = len(names) - 1
        elif t[0] == "End":
            names.append("End" + str(len(names))); parents.append(stack[-1])
            stack.append(len(names) - 1); offs.append(None); chans.append([])
        elif t[0] == "OFFSET":
            offs[stack[-1]] = np.array([float(x) for x in t[1:4]])
        elif t[0] == "CHANNELS":
            chans[stack[-1]] = t[2:]
        elif t[0] == "}":
            stack.pop()
    m = motion.strip().splitlines()
    n = int(m[0].split()[1]); ft = float(m[1].split()[2])
    data = np.array([[float(x) for x in l.split()] for l in m[2:2 + n]])
    return names, parents, offs, chans, data, ft

def rot(axis, a):
    c, s = np.cos(a), np.sin(a)
    o, z = np.ones_like(a), np.zeros_like(a)
    if axis == "X": r = [[o, z, z], [z, c, -s], [z, s, c]]
    elif axis == "Y": r = [[c, z, s], [z, o, z], [-s, z, c]]
    else: r = [[c, -s, z], [s, c, z], [z, z, o]]
    return np.array(r).transpose(2, 0, 1)

def fk(names, parents, offs, chans, data):
    n = len(data)
    glob = [None] * len(names); pos = [None] * len(names)
    col = 0
    for i, nm in enumerate(names):
        R = np.tile(np.eye(3), (n, 1, 1)); T = np.zeros((n, 3))
        for ch in chans[i]:
            v = data[:, col]; col += 1
            if ch.endswith("position"):
                T[:, "XYZ".index(ch[0])] = v
            else:
                R = R @ rot(ch[0], np.radians(v))
        if parents[i] < 0:
            glob[i] = R; pos[i] = T + offs[i]
        else:
            p = parents[i]
            glob[i] = glob[p] @ R
            pos[i] = pos[p] + (glob[p] @ (offs[i] + T)[:, :, None])[:, :, 0]
    return dict(zip(names, pos)), dict(zip(names, glob))

def gauss(x, s):
    r = int(3 * s) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2); k /= k.sum()
    pad = np.concatenate([np.repeat(x[:1], r, 0), x, np.repeat(x[-1:], r, 0)], 0)
    return np.stack([np.convolve(pad[:, c], k, "valid") for c in range(x.shape[1])], 1)

def minima_segments(e, fps):
    """Boundaries = quiet local minima of the energy curve (prominent dips), merged within 0.35 s."""
    p90 = np.percentile(e, 92)
    lim = 0.42 * p90
    mins = [i for i in range(1, len(e) - 1) if e[i] <= e[i - 1] and e[i] <= e[i + 1] and e[i] < lim]
    merged = []
    for i in mins:
        if merged and i - merged[-1][-1] < 0.35 * fps:
            merged[-1].append(i)
        else:
            merged.append([i])
    cuts = [int(round(np.mean(g))) for g in merged]
    bounds = [0] + cuts + [len(e) - 1]
    return [(a, b) for a, b in zip(bounds[:-1], bounds[1:]) if b - a >= 0.5 * fps and e[a:b].max() > 0.6 * p90]

res = {}
for tk in takes:
    names, parents, offs, chans, data, ft = parse(os.path.join(bvh_dir, tk + ".bvh"))
    fps = 1 / ft
    pos, glob = fk(names, parents, offs, chans, data)
    scale = np.linalg.norm(pos["Head"][0] - pos["Hips"][0]) if "Head" in pos else 1
    hip = pos["Hips"]
    eff = {k: pos[k] for k in ("LeftHand", "RightHand", "LeftFoot", "RightFoot")}
    # y is up in CMU BVH
    spd = {}
    for k, p in eff.items():
        rel = p - hip                       # relative to the hips: ignore whole-body travel
        v = np.linalg.norm(np.diff(gauss(rel, fps * 0.03), axis=0), axis=1) * fps / scale
        spd[k] = np.concatenate([[v[0]], v])
    body = np.zeros(len(data))
    for k in ("LeftHand", "RightHand", "LeftFoot", "RightFoot"):
        body += spd[k]
    e = gauss(body[:, None], fps * 0.08)[:, 0]
    segs = minima_segments(e, fps)
    out = []
    for a, b in segs:
        dur = (b - a) / fps
        if dur < 0.5: continue
        pk = {k: float(spd[k][a:b].max()) for k in spd}
        dom = max(pk, key=pk.get)
        ph = {k: float(((eff[k][a:b, 1] - hip[a:b, 1]) / scale).max()) for k in eff}
        low = float(((hip[a:b, 1]) / scale).min())
        trav = float(np.linalg.norm(hip[b - 1, [0, 2]] - hip[a, [0, 2]]) / scale)
        out.append({"t0": round(a / fps, 2), "t1": round(b / fps, 2), "dur": round(dur, 2), "dom": dom,
                    "peak": round(pk[dom], 1), "foot_up": round(max(ph["LeftFoot"], ph["RightFoot"]), 2),
                    "hip_min": round(low, 2), "travel": round(trav, 2), "energy": round(float(e[a:b].mean()), 1)})
    # strike events: per-effector speed peaks, each with the quiet frames around it
    events = []
    for k in eff:
        v = gauss(spd[k][:, None], fps * 0.04)[:, 0]
        vmax = v.max()
        for i in range(2, len(v) - 2):
            if v[i] >= v[i - 1] and v[i] >= v[i + 1] and v[i] > 0.45 * vmax and v[i] == v[max(0, i - int(0.4 * fps)):i + int(0.4 * fps) + 1].max():
                a0, a1 = max(0, i - int(1.6 * fps)), max(1, i - int(0.15 * fps))
                b0, b1 = min(len(e) - 1, i + int(0.15 * fps)), min(len(e), i + int(2.0 * fps))
                ta = a0 + int(np.argmin(e[a0:a1])) if a1 > a0 else i
                tb = b0 + int(np.argmin(e[b0:b1])) if b1 > b0 else i
                up = float((eff[k][i, 1] - hip[i, 1]) / scale)
                fwd = float(np.linalg.norm(eff[k][i, [0, 2]] - hip[i, [0, 2]]) / scale)
                events.append({"t": round(i / fps, 2), "eff": k, "speed": round(float(v[i]), 1), "up": round(up, 2), "reach": round(fwd, 2),
                               "from": round(ta / fps, 2), "to": round(tb / fps, 2)})
    events.sort(key=lambda x: x["t"])
    res[tk] = {"len_s": round(len(data) / fps, 1), "fps": round(fps), "segments": out, "events": events}
    print(tk, res[tk]["len_s"], "s", len(out), "segments")
json.dump(res, open(out_json, "w"), indent=1)
