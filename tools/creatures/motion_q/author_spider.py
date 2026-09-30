"""Spider attack (Blender 5.2 headless): blender -b --python author_spider.py -- <out_dir>
New 1.0 s attack: front legs rise and pull back while the body lowers and tilts up (telegraph 0.5 s, held), then a 3-frame stab
(impact 0.50 s), follow-through and recovery.  Six rear legs stay IK-planted (3-bone CCD on the skinned tip)."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qpose import *
from glbtools import graft
out_dir = sys.argv[sys.argv.index('--') + 1]; os.makedirs(out_dir, exist_ok=True)
IMPACT = 0.50; DUR = 1.0
path, kind = CREATURES['spider']
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
feet = {}
rig.arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
V0 = eval_verts(mesh); rig.arm.data.pose_position = 'POSE'; bpy.context.view_layer.update()
for s in 'LR':
    for n in '1234':
        nm = f'{s}{n}'; idx = group_verts(mesh, [f'tarsus_{nm}'], 0.5); z = V0[idx, 2]
        idx = idx[z <= np.sort(z)[max(3, len(z) // 8)]]
        feet[nm] = Foot(rig, nm, idx, [f'femur_{nm}', f'tibia_{nm}', f'tarsus_{nm}'])
base = rig.read('idle', 0)
def pk(t, ease='smooth', **kw):
    d = {}
    for k, v in kw.items():
        if k.startswith('foot_'): a, b, c = k.split('_'); d[f'foot.{b}.{c}'] = v
        elif k.startswith('root_'): d['root.' + k[5:]] = v
        else: d[k.replace('__', '.')] = v
    return (t, d, ease)
def front(x, y, z): return {'foot_L1_x': x, 'foot_L1_y': y, 'foot_L1_z': z, 'foot_R1_x': -x, 'foot_R1_y': y, 'foot_R1_z': z}
keys = [
    (0.00, {}, 'smooth'),
    pk(0.16, root_z=-0.02, body__rx=-5, **front(0.0, 0.05, 0.12)),
    pk(0.34, root_z=-0.03, root_y=0.02, body__rx=-9, **front(0.06, 0.22, 0.42)),
    pk(0.47, 'lin', root_z=-0.035, root_y=0.025, body__rx=-11, **front(0.07, 0.24, 0.46)),
    pk(0.485, 'snap', root_z=-0.03, root_y=-0.02, body__rx=-4, **front(0.04, -0.10, 0.15)),
    pk(0.50, 'snap', root_z=-0.03, root_y=-0.06, body__rx=6, **front(0.02, -0.22, 0.0)),
    pk(0.60, 'out', root_z=-0.035, root_y=-0.06, body__rx=5, **front(0.02, -0.21, 0.0)),
    pk(0.78, root_z=-0.015, root_y=-0.03, body__rx=2, **front(0.0, -0.10, 0.06)),
    (1.00, {}, 'smooth'),
]
ch = author(rig, feet, base, keys, DUR)
write_clip(rig, 'attack', ch)
# ---- death: recoil, then the legs curl under the body (IK, so the leg meshes never stretch) while it sinks; held on the ground
P0 = rig.fk(base); s_ = rig.s
F0 = {k: ft.point(P0) * s_ for k, ft in feet.items()}
cx = sum(v.x for v in F0.values()) / 8; cy = sum(v.y for v in F0.values()) / 8
def curl(f, lift):
    d = {}
    for k, v in F0.items():
        d[f'foot.{k}.x'] = -(v.x - cx) * f; d[f'foot.{k}.y'] = -(v.y - cy) * f; d[f'foot.{k}.z'] = lift
    return d
def dk(t, ease='smooth', rz=0.0, rx=0.0, f=0.0, lift=0.0, ry=0.0, front=0.0):
    d = curl(f, lift); d['root.z'] = rz; d['body.rx'] = rx; d['body.ry'] = ry
    d['foot.L1.z'] = d['foot.L1.z'] + front; d['foot.R1.z'] = d['foot.R1.z'] + front
    return (t, d, ease)
dkeys = [(0.0, {}, 'smooth'), dk(0.15, rz=0.01, rx=-7, front=0.14), dk(0.45, rz=-0.05, rx=-2, f=0.18, lift=0.02, front=0.05),
         dk(0.90, rz=-0.11, rx=2, f=0.42, lift=0.05, ry=3), dk(1.50, rz=-0.12, rx=2, f=0.48, lift=0.06, ry=3)]
chd = author(rig, feet, base, dkeys, 1.5)
write_clip(rig, 'death', chd)
# hit: the old hit was a near-invisible 3 cm tilt; new = shoved back, front half flinches up, legs stay planted
hk = [(0.0, {}, 'smooth'),
      pk(0.05, 'snap', root_y=0.10, root_z=0.012, body__rx=-13, **front(0.03, 0.10, 0.12)),
      pk(0.16, 'out', root_y=0.07, root_z=-0.01, body__rx=-7, **front(0.02, 0.05, 0.05)),
      pk(0.31, root_y=0.02, body__rx=-2),
      (0.47, {}, 'smooth')]
write_clip(rig, 'hit', author(rig, feet, base, hk, 0.47))
tmp = os.path.join(out_dir, 'anim_spider.glb'); export_anims(arm, mesh, tmp)
for tag in ('', '_lod1'):
    graft(f"{repo()}/{path}{tag}.glb", tmp, ['attack', 'death', 'hit'], os.path.join(out_dir, f"spider{tag}.glb"))
print("DONE attack impact", IMPACT, "dur", DUR)
