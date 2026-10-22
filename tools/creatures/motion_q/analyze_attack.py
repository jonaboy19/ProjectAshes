"""blender -b --python analyze_attack.py -- <creature> <glb|-> <out.json> [clip=attack]
Attack timing + weight metrics from the skinned mesh: wind-up start (first frame the pose leaves frame 0 by > 3 cm),
impact = time of peak speed of the extremities (the 3% of vertices farthest from the centroid; the game's definition),
recovery = first frame after the impact when the pose is back within 5 cm (max vertex) of frame 0, tell = time the
pose is held (extremity speed < 0.25 m/s) before the strike, mass shift = max centroid displacement and height change,
dip = lowest centroid height relative to frame 0."""
import sys, os, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
args = sys.argv[sys.argv.index('--') + 1:]
cr, glb, outj = args[:3]; clip = args[3] if len(args) > 3 else 'attack'
path, kind = CREATURES[cr]
if glb == '-': glb = f"{repo()}/{path}.glb"
arm, meshes, acts = load(glb); mesh = [m for m in meshes if m.parent == arm][0]
sc = bpy.context.scene; a = acts[clip]; set_clip(arm, a); fr = frames_of(a); dt = 1 / FPS
Vs = []
for f in fr:
    sc.frame_set(int(f)); Vs.append(eval_verts(mesh))
V0 = Vs[0]; C = np.array([v.mean(axis=0) for v in Vs])
d0 = np.linalg.norm(V0 - V0.mean(axis=0), axis=1); ext = np.argsort(d0)[-max(5, len(d0) * 3 // 100):]
E = np.array([v[ext].mean(axis=0) for v in Vs]); sp = np.linalg.norm(np.gradient(E, dt, axis=0), axis=1)
dev = np.array([np.linalg.norm(v - V0, axis=1).max() for v in Vs])
i_imp = int(np.argmax(sp)); start = int(np.argmax(dev > 0.03)); n = len(fr)
rec = next((i for i in range(i_imp + 1, n) if dev[i] < 0.05), n - 1)
hold = 0.0
for i in range(start, i_imp):
    if sp[i] < 0.25 and i > start + 3: hold += dt
r = dict(clip=clip, frames=n, dur=(n - 1) * dt, windup_start_s=start * dt, impact_s=i_imp * dt, peak_extremity_speed_mps=float(sp[i_imp]),
         telegraph_s=(i_imp - start) * dt, hold_s=hold, recovery_s=rec * dt, end_pose_dev_cm=float(dev[-1] * 100),
         centroid_shift_cm=float(np.linalg.norm(C - C[0], axis=1).max() * 100), centroid_dz_cm=[float((C[:, 2] - C[0, 2]).min() * 100), float((C[:, 2] - C[0, 2]).max() * 100)],
         min_z_cm=float(min(v[:, 2].min() for v in Vs) * 100))
print("ATTACK", cr, json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()}))
json.dump(r, open(outj, 'w'), indent=1)
