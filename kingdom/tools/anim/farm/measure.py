"""Measure rigged farm animal clips. blender -b --python measure.py -- <rigged.glb> <clip> [cow|chicken]
cow: min height of the muzzle (verts weighted mostly to 'head', front 12 cm) and hoof min z per frame.
chicken: wing tip spread (max |x| of verts weighted to wing bones/feather bones)."""
import bpy, sys, numpy as np
a = sys.argv[sys.argv.index('--') + 1:]
glb, clip, kind = a[0], a[1], a[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
me = [o for o in bpy.data.objects if o.type == 'MESH' and o.modifiers][0]
act = [x for x in bpy.data.actions if x.name.split('.')[0] == clip or x.name.startswith(clip)]
act = [x for x in act if x.name == clip] or act
act = act[0]
ad = arm.animation_data or arm.animation_data_create()
for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
ad.action = act
try: ad.action_slot = act.slots[0]
except Exception: pass
vg = {g.index: g.name for g in me.vertex_groups}
n = len(me.data.vertices)
gw = {}
for v in me.data.vertices:
    for g in v.groups:
        gw.setdefault(vg[g.group], {})[v.index] = g.weight
def sel(pred):
    idx = set()
    for name, d in gw.items():
        if pred(name):
            idx |= {i for i, w in d.items() if w > 0.4}
    return sorted(idx)
if kind == 'cow':
    head = sel(lambda s: s == 'head')
    hoof = sel(lambda s: s.endswith('_hoof'))
else:
    wing = sel(lambda s: s.startswith('wing') or s.startswith('feat'))
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
dg = bpy.context.evaluated_depsgraph_get()
res = []
for f in range(f0, f1 + 1):
    bpy.context.scene.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = me.evaluated_get(dg)
    m = ev.to_mesh()
    P = np.empty(n * 3); m.vertices.foreach_get('co', P); P = P.reshape(n, 3)
    ev.to_mesh_clear()
    if kind == 'cow':
        hp = P[head]
        front = hp[hp[:, 1] < hp[:, 1].min() + 0.12]
        res.append((f, front[:, 2].min(), P[hoof][:, 2].min(), P[:, 2].max()))
    else:
        wp = P[wing]
        res.append((f, np.abs(wp[:, 0]).max(), wp[:, 2].min(), wp[:, 2].max()))
r = np.array(res)
print("MEASURE", clip, kind, "frames", len(r))
for row in r[::max(1, len(r)//15)]:
    print("  f%3d %s" % (row[0], " ".join("%.3f" % x for x in row[1:])))
if kind == 'cow':
    print("MUZZLE min z %.3f  (min over clip) ; hoof min z range %.3f..%.3f" % (r[:,1].min(), r[:,2].min(), r[:,2].max()))
else:
    print("WING max|x| %.3f  min %.3f  zrange %.3f..%.3f" % (r[:,1].max(), r[:,1].min(), r[:,2].min(), r[:,3].max()))
