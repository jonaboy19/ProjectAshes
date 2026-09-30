"""blender -b --python check_loops.py -- <creature> <glb|-> [clips...] : loop pop (first vs last frame, max vertex cm), max per-frame vertex step (cm), and diff vs idle"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
a = sys.argv[sys.argv.index('--')+1:]; cr, glb = a[:2]; clips = a[2:] or ['idle', 'walk', 'run']
path, kind = CREATURES[cr]
if glb == '-': glb = f"{repo()}/{path}.glb"
arm, meshes, acts = load(glb); mesh = [m for m in meshes if m.parent == arm][0]; sc = bpy.context.scene
data = {}
for c in clips:
    if c not in acts: continue
    set_clip(arm, acts[c]); V = []
    for f in frames_of(acts[c]): sc.frame_set(int(f)); V.append(eval_verts(mesh))
    data[c] = V
    pop = np.linalg.norm(V[0] - V[-1], axis=1).max() * 100
    step = max(np.linalg.norm(V[i + 1] - V[i], axis=1).max() for i in range(len(V) - 1)) * 100
    print(f"LOOP {cr} {c}: frames={len(V)} dur={(len(V)-1)/30:.3f}s pop(first-last)={pop:.2f}cm max_step={step:.2f}cm")
if 'idle' in data:
    for c, V in data.items():
        if c != 'idle' and len(V) == len(data['idle']): print("DIFF_vs_idle", c, round(float(max(np.linalg.norm(V[i] - data['idle'][i], axis=1).max() for i in range(len(V))) * 100), 3), "cm")
