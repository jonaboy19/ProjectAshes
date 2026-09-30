"""World-space foot-slip measurement of clips in an exported GLB, using the root-motion + planted-frame table written by author.py.
blender -b --python measure2.py -- <glb> <rootmotion.json> [clip ...]
For each clip: the body is moved by the clip's root motion (game-side: forward/left/yaw per frame); the paw centroid (xy) of every foot
is followed in WORLD space; over the frames the authoring marked planted we report slip speed (rms, max, m/s) and the sole height
(min paw vertex z: mean/max/min, cm). Old clips (no table) are skipped: use measure.py."""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
args = sys.argv[sys.argv.index('--') + 1:]
glb, js = args[0], json.load(open(args[1]))
arm, mesh = load_glb(glb); acts = clip_actions(); ps = paw_sets(mesh, arm)
names = args[2:] or [n for n in js if n in acts]
out = {}
for nm in names:
    meta = js[nm]; a = acts[nm]; assign(arm, a); f0, f1 = frame_range(a)
    n = f1 - f0 + 1
    if meta['root_motion']: rm = meta['root_motion']
    else: rm = [[0, 0, 0]] * n
    W = {k: [] for k in ps}; Z = {k: [] for k in ps}
    for i, f in enumerate(range(f0, f1 + 1)):
        bpy.context.scene.frame_set(f); P = mesh_world_np(mesh)
        rf, rl, psi = rm[i]
        c, s = math.cos(psi), math.sin(psi)
        for k, idx in ps.items():
            p = P[idx]; cen = p.mean(0); bF, bL = -cen[1], cen[0]
            W[k].append((rf + c * bF - s * bL, rl + s * bF + c * bL)); Z[k].append(p[:, 2].min())
    sp = []; zz = []; per = {}
    for k in ps:
        w = np.array(W[k]); v = np.gradient(w, 1 / 30.0, axis=0); spd = np.hypot(v[:, 0], v[:, 1])
        pl = [bool(meta['planted'][i].get(k, False)) for i in range(n)]
        # drop the first/last frame of each planted run (boundary of a lift) from the speed sample
        sel = [i for i in range(n) if pl[i] and 0 < i < n - 1 and pl[i - 1] and pl[i + 1]]
        per[k] = float(np.sqrt(np.mean(spd[sel] ** 2))) if sel else 0.0
        sp += list(spd[sel]); zz += [Z[k][i] for i in range(n) if pl[i]]
    sp = np.array(sp); zz = np.array(zz) * 100
    r = dict(slip_rms=float(np.sqrt(np.mean(sp ** 2))) if len(sp) else 0.0, slip_max=float(sp.max()) if len(sp) else 0.0,
             sole_mean_cm=float(zz.mean()) if len(zz) else 0.0, sole_min_cm=float(zz.min()) if len(zz) else 0.0, sole_max_cm=float(zz.max()) if len(zz) else 0.0,
             planted_frames=len(sp), per_leg={k: round(v, 3) for k, v in per.items()})
    out[nm] = r
    print(f"SLIP {nm:12s} rms={r['slip_rms']:.3f} max={r['slip_max']:.3f} m/s  sole mean={r['sole_mean_cm']:+.1f} min={r['sole_min_cm']:+.1f} max={r['sole_max_cm']:+.1f} cm  n={r['planted_frames']} {r['per_leg']}")
if os.environ.get("MEASURE_OUT"): json.dump(out, open(os.environ["MEASURE_OUT"], "w"), indent=1)
