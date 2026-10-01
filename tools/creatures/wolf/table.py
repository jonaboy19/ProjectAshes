"""Numbers for creature_models.gd and the patch doc: attack impact time (head-tip speed peak), root-motion tables.
blender -b --python table.py -- <glb> <rootmotion.json> <out_dir>"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
glb, js, outd = sys.argv[sys.argv.index('--') + 1:][:3]
js = json.load(open(js))
arm, mesh = load_glb(glb)
acts = clip_actions()
co = np.array([v.co[:] for v in mesh.data.vertices])
tip = int(np.argmin(co[:, 1]))                       # forward-most vertex of the rest mesh = muzzle tip
res = {}
for nm in ("attack", "lunge", "hit"):
    a = acts[nm]
    assign(arm, a)
    f0, f1 = frame_range(a)
    pos = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        pos.append(mesh_world_np(mesh)[tip])
    pos = np.array(pos)
    rm = js.get(nm, {}).get('root_motion')
    if rm:
        # remove the game-side root motion so we look at the muzzle relative to the ground-frame body node
        pass
    v = np.linalg.norm(np.gradient(pos, 1 / 30.0, axis=0), axis=1)
    fwd = -pos[:, 1]
    res[nm] = dict(speed_peak_t=float(np.argmax(v) / 30.0), speed_peak=float(v.max()), fwd_max_t=float(np.argmax(fwd) / 30.0), fwd_max=float(fwd.max()),
                   duration=(f1 - f0) / 30.0)
    print("TIP", nm, res[nm])
os.makedirs(outd, exist_ok=True)
json.dump(res, open(os.path.join(outd, "impact_measure.json"), "w"), indent=1)
lines = []
for nm in ("turn_l90", "turn_r90", "turn_l180", "turn_r180"):
    m = js[nm]
    lines.append(f"{nm}: T={m['frames'] / 30:.3f}s ({m['frames']} frames); heading change (deg) every 3 frames:")
    lines.append("  " + " ".join(f"{math.degrees(r[2]):.1f}" for r in m['root_motion'][::3]))
m = js['lunge']
lines.append(f"lunge: T={m['frames'] / 30:.3f}s; forward travel (m) every 2 frames:")
lines.append("  " + " ".join(f"{r[0]:.2f}" for r in m['root_motion'][::2]))
for nm in ("circle_l", "circle_r", "run_turn_l", "run_turn_r"):
    m = js[nm]
    r = m['root_motion']
    lines.append(f"{nm}: T={m['frames'] / 30:.3f}s; per-cycle root motion forward {r[-1][0]:.3f} m, left {r[-1][1]:.3f} m, heading {math.degrees(r[-1][2]):.1f} deg")
for nm in ("stalk", "limp", "walk", "run"):
    m = js[nm]
    r = m['root_motion']
    lines.append(f"{nm}: T={m['frames'] / 30:.3f}s; per-cycle root motion forward {r[-1][0]:.3f} m => {r[-1][0] / (m['frames'] / 30):.3f} m/s")
open(os.path.join(outd, "root_motion_tables.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
