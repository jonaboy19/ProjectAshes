"""blender -b --python dump_weights.py -- <creature> : per bone, centroid + z/y range of the vertices it dominates (rest pose, metres)"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qrig import *
cr = sys.argv[sys.argv.index('--')+1]
path, kind = CREATURES[cr]
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
n = len(mesh.data.vertices)
V = rig.rest_points(np.arange(n)) * rig.s
dom = {}
for v in mesh.data.vertices:
    if not v.groups: continue
    g = max(v.groups, key=lambda g: g.weight)
    dom.setdefault(mesh.vertex_groups[g.group].name, []).append(v.index)
ch = rig.read('idle', 0); P = rig.fk(ch)
for name in rig.names:
    idx = dom.get(name, [])
    h = P[name].translation * rig.s
    if len(idx) == 0: print(f"{name:20s} head=({h.x:6.3f},{h.y:6.3f},{h.z:6.3f})  no dominated verts"); continue
    p = V[idx]; c = p.mean(axis=0)
    print(f"{name:20s} head=({h.x:6.3f},{h.y:6.3f},{h.z:6.3f}) n={len(idx):5d} centroid=({c[0]:6.3f},{c[1]:6.3f},{c[2]:6.3f}) z[{p[:,2].min():.2f},{p[:,2].max():.2f}] y[{p[:,1].min():.2f},{p[:,1].max():.2f}]")
