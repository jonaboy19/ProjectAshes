"""Foot-slip analysis from metrics.json (run with Blender's bundled python.exe; needs numpy).
usage: python analyze.py <metrics.json> <height_m> [walk_speed run_speed]
Cyclic clips: last frame duplicates first and is dropped. Stance = toe within 0.02*H of its cycle minimum
(and ankle within 0.04*H of its minimum). Slip = deviation (cm) of the toe's ground position from its
stance mean, root advancing at v along the forward axis."""
import sys, json, numpy as np
d = json.load(open(sys.argv[1])); H = float(sys.argv[2])
sp = {"walk": float(sys.argv[3]) if len(sys.argv) > 3 else None, "run": float(sys.argv[4]) if len(sys.argv) > 4 else None}
FPS = 30.0
def A(c, b): return np.array(c["pos"][b])[:-1]
FW = None
def fwd_axis(c):
    global FW
    if FW is not None: return FW
    c = d.get("walk", c)
    v = (A(c,"LeftToeBase") - A(c,"LeftFoot") + A(c,"RightToeBase") - A(c,"RightFoot")).mean(0); v[2] = 0
    FW = v / np.linalg.norm(v); return FW
def contacts(c):
    out = []
    for side in ("Left", "Right"):
        toe = A(c, side + "ToeBase"); an = A(c, side + "Foot"); n = len(toe)
        st = (toe[:, 2] < toe[:, 2].min() + 0.02 * H) & (an[:, 2] < an[:, 2].min() + 0.04 * H)
        if st.all() or not st.any(): continue
        s0 = int(np.where(~st)[0][0]); order = [(s0 + i) % n for i in range(n)]   # rotate to start in swing
        cur = []
        for i in order:
            if st[i]: cur.append(i)
            elif cur: out.append((side, cur)); cur = []
        if cur: out.append((side, cur))
    return out
def slip(c, v):
    f = fwd_axis(c); res = []
    for side, idx in contacts(c):
        if len(idx) < 3: continue
        toe = A(c, side + "ToeBase")
        t = np.array([(k - idx[0]) % len(toe) for k in idx]) / FPS
        pos = toe[idx][:, :2] + np.outer(t * v, f[:2])
        dev = np.linalg.norm(pos - pos.mean(0), axis=1)
        rel = (toe[idx][:, :2] @ f[:2]); implied = -(rel[-1] - rel[0]) / max(t[-1], 1e-6)
        res.append((dev.max() * 100, dev.mean() * 100, implied, len(idx), side))
    return res
def best_speed(c):
    best = None
    for v in np.arange(0.2, 12.0, 0.02):
        r = slip(c, v)
        if r:
            m = np.mean([x[0] for x in r])
            if best is None or m < best[1]: best = (v, m)
    return best
for name, c in d.items():
    hips = A(c, "Hips")
    print(f"== {name}: {len(hips)+1} frames ({len(hips)/FPS:.2f}s) mesh minz {min(c['minz']):.3f} hipsZ {hips[:,2].min():.2f}..{hips[:,2].max():.2f}")
    if name in ("walk", "run"):
        pd = max(np.linalg.norm(np.array(c["pos"][b][0]) - np.array(c["pos"][b][-1])) for b in c["pos"])
        print(f"   loop closure delta {pd*100:.2f} cm; feet mesh-min z {min(c['minz']):.3f}")
        bv = best_speed(c)
        for v, tag in ((sp[name], "stated"), (bv[0], "best")):
            if v is None: continue
            r = slip(c, v)
            print(f"   {tag} v={v:.2f}: contacts {len(r)} max slip {max(x[0] for x in r):.1f} cm, mean-of-max {np.mean([x[0] for x in r]):.1f}, mean-dev {np.mean([x[1] for x in r]):.1f}; stance frames {[x[3] for x in r]}; implied v {[round(float(x[2]),2) for x in r]}")
