"""Foot-slide analysis. blender -b --python analyze_feet.py -- <creature> <glb|-> <out.json> [clips...]
Env MQ_SPEEDS=0.45,2.7 evaluates extra ground speeds (the current creature_models.gd numbers).
Every foot (mesh verts of the lowest part of the foot) is tracked through the clip. Stance frames = foot low and moving
backwards relative to the body. If the root travels along the facing direction (-Y in Blender) at ground speed v, a
planted foot must have y_rel(t) = y0 + v t. Reported: v* (least squares over stance frames = the speed that minimises
slip), and at v*/given v: per-frame slip in cm (foot displacement on the ground between two consecutive stance frames)
and per-stance excursion in cm (how far the foot creeps while it is meant to be planted)."""
import sys, os, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
args = sys.argv[sys.argv.index('--')+1:]
cr, glb, outj = args[:3]; clips = args[3:] or ['idle', 'walk', 'run']
path, kind = CREATURES[cr]
if glb == '-': glb = f"{repo()}/{path}.glb"
arm, meshes, acts = load(glb)
mesh = [m for m in meshes if m.name == cr][0]
sc = bpy.context.scene
arm.data.pose_position = "REST"; bpy.context.view_layer.update()
V0 = eval_verts(mesh); arm.data.pose_position = "POSE"; bpy.context.view_layer.update(); H = V0[:, 2].max() - V0[:, 2].min()
sets = {}
if kind == 'quad':
    low = np.where(V0[:, 2] < V0[:, 2].min() + 0.09 * H)[0]; ym = np.median(V0[low, 1])
    for s in 'LR':
        for fb in 'FB':
            sx = 1 if s == 'L' else -1
            m = (np.sign(V0[low, 0]) == sx) & ((V0[low, 1] < ym) == (fb == 'F')); sets[fb + s] = low[m]
else:
    for s in 'LR':
        for n in '1234':
            idx = group_verts(mesh, [f'tarsus_{s}{n}'], 0.5); z = V0[idx, 2]
            sets[s + n] = idx[z <= np.sort(z)[max(3, len(z) // 8)]]
VFRAC = float(os.environ.get("MQ_VFRAC", 0.0))
THR = float(os.environ.get('MQ_THR', 0.04)) * H
dt = 1.0 / FPS
res = {}
def runs_cyclic(st):
    """contiguous True runs over indices 0..m-1, merging the wrap-around"""
    m = len(st); idx = np.where(st)[0]
    if len(idx) == 0: return []
    if st.all(): return [list(range(m))]
    start = int(np.where(~st)[0][0])                 # rotate to begin at a False sample
    order = [(start + i) % m for i in range(m)]
    runs = []; cur = []
    for j in order:
        if st[j]: cur.append(j)
        elif cur: runs.append(cur); cur = []
    if cur: runs.append(cur)
    return runs
for clip in clips:
    if clip not in acts: continue
    a = acts[clip]; set_clip(arm, a); fr = frames_of(a); n = len(fr); m = n - 1     # m unique frames (last == first)
    P = {k: [] for k in sets}; Zm = {k: [] for k in sets}; allv = []
    for f in fr:
        sc.frame_set(int(f)); V = eval_verts(mesh); allv.append(V)
        for k, idx in sets.items(): P[k].append(V[idx].mean(axis=0)); Zm[k].append(V[idx, 2].min())
    P = {k: np.array(v) for k, v in P.items()}; Zm = {k: np.array(v) for k, v in Zm.items()}
    r = {'frames': n, 'dur': m * dt}
    r['loop_pop_cm'] = float(np.linalg.norm(allv[0] - allv[-1], axis=1).max() * 100)
    feet = {}; vs = []
    for k in P:
        y = P[k][:, 1]; x = P[k][:, 0]
        vy = np.gradient(y, dt); vy[0] = vy[-1] = (y[1] - y[-2] + (0 if True else 0)) / (2 * dt) if False else vy[0]
        z = Zm[k]; lowz = z < z.min() + THR
        st = lowz & (vy > VFRAC * max(vy.max(), 1e-6))
        # remove isolated single-frame stances
        feet[k] = dict(stance=st[:m], y=y, x=x, z=z, vy=vy)
        vs.append(vy[st])
    vv = np.concatenate(vs)
    vstar = float(vv.mean()) if len(vv) else 0.0
    r['vstar'] = vstar; r['vstar_median'] = float(np.median(vv)) if len(vv) else 0.0
    def slip(v):
        per = []; exc = []
        for k, d in feet.items():
            st = d['stance']; y = d['y']; x = d['x']
            g = y - v * dt * np.arange(n)                       # ground-frame y (world) of the foot, root at speed v along -Y
            gx = x
            for i in range(m):
                j = (i + 1)
                if st[i] and st[j % m]:
                    per.append(float(np.hypot(g[j] - g[i], gx[j] - gx[i]) * 100))
            for run in runs_cyclic(st):
                pts = []; wraps = 0
                for t, idx in enumerate(run):
                    if t and idx < run[t - 1]: wraps += 1          # unwrap across the loop seam
                    pts.append(y[idx] - v * dt * (idx + wraps * m))
                if len(pts) > 1:
                    exc.append(float((max(pts) - min(pts)) * 100))
                    if os.environ.get("MQ_DETAIL"): print("     run", k, "frames", run[0], "..", run[-1], "excursion_cm", round(exc[-1], 1), "v", round(v, 3))
        f = lambda l, fn: float(fn(l)) if l else 0.0
        return dict(max_frame_cm=f(per, max), mean_frame_cm=f(per, np.mean), max_excursion_cm=f(exc, max), mean_excursion_cm=f(exc, np.mean))
    r['stance_frac'] = float(np.mean([d['stance'].mean() for d in feet.values()]))
    r['slip_at_vstar'] = slip(vstar)
    for sv in [float(s) for s in os.environ.get('MQ_SPEEDS', '').split(',') if s]:
        r[f'slip_at_{sv}'] = slip(sv)
    r['feet'] = {k: dict(stance_frames=[int(i) for i in np.where(d['stance'])[0]], lift_cm=float((d['z'].max() - d['z'].min()) * 100), y_range_cm=float(np.ptp(d['y']) * 100)) for k, d in feet.items()}
    res[clip] = r
    print(f"CLIP {clip}: frames={n} dur={r['dur']:.3f}s loop_pop={r['loop_pop_cm']:.2f}cm stance_frac={r['stance_frac']:.2f} v*={vstar:.3f} m/s (median {r['vstar_median']:.3f})")
    print("   slip@v*:", {k: round(v, 2) for k, v in r['slip_at_vstar'].items()})
    for sv in [float(s) for s in os.environ.get('MQ_SPEEDS', '').split(',') if s]:
        print(f"   slip@{sv}:", {k: round(v, 2) for k, v in r[f'slip_at_{sv}'].items()})
    for k, d in r['feet'].items(): print("   foot", k, "stance", d['stance_frames'], "lift_cm", round(d['lift_cm'], 1), "yrange_cm", round(d['y_range_cm'], 1))
json.dump(res, open(outj, 'w'), indent=1)
