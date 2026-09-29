"""blender -b --python dump_feet.py -- <creature> <glb|-> <clip>  : per-frame foot z(cm) and y(cm)"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
cr, glb, clip = sys.argv[sys.argv.index('--')+1:][:3]
path, kind = CREATURES[cr]
if glb == '-': glb = f"{repo()}/{path}.glb"
arm, meshes, acts = load(glb); mesh = [m for m in meshes if m.name == cr][0]
sc = bpy.context.scene; a = acts[clip]; set_clip(arm, a); sc.frame_set(0)
V0 = eval_verts(mesh); H = V0[:,2].max()-V0[:,2].min()
if kind == 'quad':
    low = np.where(V0[:, 2] < V0[:, 2].min() + 0.09 * H)[0]; ym = np.median(V0[low, 1]); sets={}
    for s in 'LR':
        for fb in 'FB':
            sx = 1 if s=='L' else -1
            m = (np.sign(V0[low,0])==sx) & ((V0[low,1]<ym)==(fb=='F')); sets[fb+s]=low[m]
else:
    sets={}
    for s in 'LR':
        for n in '1234':
            idx=group_verts(mesh,[f'tarsus_{s}{n}'],0.5); z=V0[idx,2]; sets[s+n]=idx[z<=np.sort(z)[max(3,len(z)//8)]]
print("frame", *[f"{k}_z {k}_y" for k in sets])
for f in frames_of(a):
    sc.frame_set(int(f)); V = eval_verts(mesh)
    print(int(f), *[f"{V[i,2].min()*100:5.1f} {V[i,1].mean()*100:6.1f}" for i in sets.values()])
