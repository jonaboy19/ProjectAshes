"""Foot-slip / ground-speed measurement of every clip in a GLB (world space, metres).
blender -b --python measure.py -- <glb> [clip ...]   (prints a table; also writes <glb basename>_measure.json next to the tmp dir if MEASURE_OUT set)
Method: sole point of each paw = lowest paw vertices. A paw is 'planted' when its sole height < 0.02 m above the lowest sole
seen in the clip. Ground speed v = -median(forward velocity of planted soles in the body frame); slip = RMS of planted-sole
horizontal velocity relative to the ground when the body travels at v (m/s). Turn clips: pass YAW_RATE env (deg/s) via
yaw table in clips.py instead (see measure_turn.py)."""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
args = sys.argv[sys.argv.index('--') + 1:]
arm, mesh = load_glb(args[0]); acts = clip_actions()
names = args[1:] or sorted(acts)
ps = paw_sets(mesh, arm)
res = {}
for nm in names:
    a = acts[nm]; assign(arm, a); f0, f1 = frame_range(a)
    soles = {k: [] for k in ps}; zs = {k: [] for k in ps}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f); P = mesh_world_np(mesh)
        for k, idx in ps.items():
            p = P[idx]; lo = p[np.argsort(p[:, 2])[:max(3, len(idx)//6)]]
            soles[k].append(lo.mean(0)); zs[k].append(p[:, 2].min())
    T = (f1 - f0) / 30.0; n = f1 - f0 + 1
    allz = min(min(v) for v in zs.values())
    fv = []; rows = {}
    for k in ps:
        s = np.array(soles[k]); z = np.array(zs[k]); pl = z < 0.03
        v = np.gradient(s[:, 1], 1 / 30.0)          # forward is -Y
        vfwd = -v
        rows[k] = (pl, np.array(s), vfwd)
        fv += list(vfwd[pl])
    ground = -float(np.mean(fv)) if fv else 0.0   # planted soles move backward at ground speed
    # slip
    sl = []
    for k in ps:
        pl, s, vfwd = rows[k]; vx = np.gradient(s[:, 0], 1 / 30.0)
        for i in range(n):
            if pl[i]: sl.append(math.hypot(vx[i], vfwd[i] + ground))
    slip = float(np.sqrt(np.mean(np.square(sl)))) if sl else 0.0
    dz = min(min(v) for v in zs.values())
    print(f"MEAS {nm:10s} T={T:5.2f}s planted_frac={np.mean([r[0].mean() for r in rows.values()]):.2f} ground={ground:5.2f} m/s slip_rms={slip:5.3f} m/s  stride={ground*T:5.2f} m/cycle  min_sole_z={dz:+.3f}")
    res[nm] = dict(T=T, ground=ground, slip=slip, minz=float(dz))
if os.environ.get("MEASURE_OUT"): json.dump(res, open(os.environ["MEASURE_OUT"], "w"), indent=1)
