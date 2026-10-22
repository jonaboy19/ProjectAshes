"""Bear motion fixes (Blender 5.2 headless):  blender -b --python author_bear.py -- <out_dir>
* walk: feet re-planted at WALK_V (IK on the skinned foot point).  run: original kept (already plants within ~5 cm at 4.05 m/s).
* attack: new 1.5 s clip. Telegraph 0.75 s: rears up onto its haunches, head reared, right paw cocked back, hold; then a
  2-frame downward swipe (impact 0.75 s), body drops onto the front paws (landing squash), recovery."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qpose import *
from glbtools import graft
out_dir = sys.argv[sys.argv.index('--') + 1]; os.makedirs(out_dir, exist_ok=True)
WALK_V = 1.4; IMPACT = 0.75; DUR = 1.5
path, kind = CREATURES['bear']
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
chains = {fb + s: [b.format(s=s) for b in (['FrontUpperLeg.{s}', 'FrontLowerLeg.{s}'] if fb == 'F' else ['BackLeg.{s}', 'BackUpperLeg.{s}', 'BackLowerLeg.{s}'])]
          for fb in 'FB' for s in 'LR'}
feet, H = quad_feet(rig, chains)
done = []
ch = lock_clip(rig, feet, 'walk', WALK_V, H=H); write_clip(rig, 'walk', ch); done.append('walk')

base = rig.read('idle', 0)
def pk(t, up=0.0, hd=0.0, ease='smooth', **kw):
    """up = chest rear-up angle (deg, spread over Torso/Torso2/Torso3), hd = extra head pitch (+ down)"""
    d = {'Torso.rx': -up * .40, 'Torso2.rx': -up * .30, 'Torso3.rx': -up * .30,
         'Neck1.rx': hd * .25, 'Neck2.rx': hd * .25, 'Neck3.rx': hd * .25, 'Head.rx': hd * .25}
    for k, v in kw.items():
        if k.startswith('foot_'): a, b, c = k.split('_'); d[f'foot.{b}.{c}'] = v
        elif k.startswith('root_'): d['root.' + k[5:]] = v
        else: d[k.replace('__', '.')] = v
    return (t, d, ease)
keys = [
    (0.00, {}, 'smooth'),
    # ---- telegraph: sit back on the haunches and rear up, right paw cocked, head reared
    pk(0.20, 12, -6, root_y=0.05, root_z=-0.06, foot_FR_z=0.10, foot_FR_y=0.05, foot_FL_z=0.05),
    pk(0.45, 42, -22, root_y=0.13, root_z=-0.10, foot_FR_x=-0.10, foot_FR_y=0.12, foot_FR_z=0.60, foot_FL_x=0.05, foot_FL_y=-0.10, foot_FL_z=0.55),
    pk(0.69, 47, -26, 'lin', root_y=0.15, root_z=-0.10, foot_FR_x=-0.14, foot_FR_y=0.18, foot_FR_z=0.66, foot_FL_x=0.05, foot_FL_y=-0.12, foot_FL_z=0.58),
    # ---- strike: 2 frames, chest and right paw slam down and forward
    pk(0.72, 24, 4, 'snap', root_y=0.0, root_z=-0.08, foot_FR_x=-0.08, foot_FR_y=-0.20, foot_FR_z=0.50, foot_FL_x=0.05, foot_FL_y=-0.20, foot_FL_z=0.40),
    pk(0.75, 4, 16, 'snap', root_y=-0.14, root_z=-0.12, foot_FR_x=-0.02, foot_FR_y=-0.48, foot_FR_z=0.06, foot_FL_y=-0.30, foot_FL_z=0.20),
    # ---- follow-through: weight lands on the front paws, squash, then recovery
    pk(0.84, -4, 10, 'out', root_y=-0.16, root_z=-0.13, foot_FR_y=-0.36, foot_FR_z=0.0, foot_FL_y=-0.30, foot_FL_z=0.0),
    pk(1.00, 0, 4, root_y=-0.10, root_z=-0.06, foot_FR_y=-0.25, foot_FL_y=-0.22),
    pk(1.20, 0, 0, 'smooth', root_y=-0.04, foot_FR_y=-0.06, foot_FR_z=0.05, foot_FL_y=-0.06),
    (1.50, {}, 'smooth'),
]
def extra(t, v):
    if 0.62 <= t < 0.69: # tremble on the hold
        v = dict(v); v['root.z'] = v.get('root.z', 0) + math.sin(t * 200) * 0.004
    return v
ch = author(rig, feet, base, keys, DUR, extra=extra)
write_clip(rig, 'attack', ch); done.append('attack')
tmp = os.path.join(out_dir, 'anim_bear.glb'); export_anims(arm, mesh, tmp)
for tag in ('', '_lod1'):
    graft(f"{repo()}/{path}{tag}.glb", tmp, done, os.path.join(out_dir, f"bear{tag}.glb"))
print("DONE", done, "impact", IMPACT, "dur", DUR)
