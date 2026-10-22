"""Boar motion fixes (Blender 5.2 headless):
  blender -b --python author_boar.py -- <out_dir>            -> writes <out_dir>/boar.glb and boar_lod1.glb (grafted clips)
* walk / run: feet re-planted (IK on the skinned foot point) at the ground speeds below; run loop closed (last == first)
* attack: new 1.13 s clip with a 0.5 s telegraph (weight sinks back, head lowers, right hoof paws twice, hold), a 3-frame gore,
  follow-through and recovery.  Impact at IMPACT seconds."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qpose import *
from glbtools import graft
out_dir = sys.argv[sys.argv.index('--') + 1]
os.makedirs(out_dir, exist_ok=True)
WALK_V, RUN_V = 0.455, 1.95
IMPACT = 0.55
DUR = 1.13
path, kind = CREATURES['boar']
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
chains = {fb + s: [b.format(s=s) for b in (['FrontUpperLeg.{s}', 'FrontLowerLeg.{s}'] if fb == 'F' else ['BackLeg.{s}', 'BackUpperLeg.{s}', 'BackLowerLeg.{s}'])]
          for fb in 'FB' for s in 'LR'}
feet, H = quad_feet(rig, chains)
done = []

# --- locomotion: plant the feet
from qgait import lock_clip
for clip, v in (('walk', WALK_V), ('run', RUN_V)):
    ch = lock_clip(rig, feet, clip, v, H=H); write_clip(rig, clip, ch); done.append(clip)

# --- attack
base = rig.read('idle', 0)
def P(hd=0.0, **kw):
    """pose dict: hd = total head-chain pitch in degrees (+ = nose down) spread over the neck bones; kw = other params ('root.y' -> root_y)"""
    d = {'Neck1.rx': hd * .18, 'Neck2.rx': hd * .27, 'Neck3.rx': hd * .27, 'Head.rx': hd * .28}
    for k, v in kw.items(): d[k.replace('_', '.', 1) if k.startswith(('root', 'foot')) else k.replace('_', '.')] = v
    return d
FR_UP = dict(foot_FR_z=0.12, foot_FR_y=-0.08)      # right front hoof lifted and reaching forward
FR_RAKE = dict(foot_FR_z=0.004, foot_FR_y=0.10)     # ... raked back along the ground
def fx(d): return {k.replace('foot_', 'foot.').replace('_', '.') if k.startswith('foot_') else k: v for k, v in d.items()}
def key(t, ease='smooth', **kw):
    d = {}
    for k, v in kw.items():
        if k.startswith('foot_'): a, b, c = k.split('_'); d[f'foot.{b}.{c}'] = v
        elif k.startswith('root_'): d['root.' + k[5:]] = v
        else: d[k.replace('__', '.')] = v
    return (t, d, ease)
def pk(t, hd, ease='smooth', extra=None, **kw):
    d = key(t, ease, **kw)
    d[1].update({'Neck1.rx': hd * .18, 'Neck2.rx': hd * .27, 'Neck3.rx': hd * .27, 'Head.rx': hd * .28})
    if extra: d[1].update(extra)
    return d
keys = [
    (0.00, {}, 'smooth'),
    # ---- telegraph (0.50 s): weight sinks back, head drops, right hoof paws twice, then a held coil
    pk(0.14, 40, root_y=0.05, root_z=-0.07, **FR_UP, extra={'Back.rx': -3}),
    pk(0.22, 52, 'in', root_y=0.07, root_z=-0.09, **FR_RAKE, extra={'Back.rx': -4}),
    pk(0.30, 52, root_y=0.07, root_z=-0.09, **FR_UP, extra={'Back.rx': -4}),
    pk(0.38, 62, 'in', root_y=0.10, root_z=-0.11, **FR_RAKE, extra={'Back.rx': -5, 'Tail1.rx': -10}),
    pk(0.50, 66, 'lin', root_y=0.12, root_z=-0.12, extra={'Back.rx': -6, 'Tail1.rx': -14}),
    # ---- strike (3 frames): head and chest surge up and forward, tusks sweep up
    pk(0.53, 8, 'snap', root_y=0.0, root_z=-0.07, foot_FL_y=-0.01, foot_FR_y=-0.01, extra={'Back.rx': -4, 'Tail1.rx': -6}),
    pk(0.55, -30, 'snap', root_y=-0.07, root_z=-0.03, foot_FL_y=-0.03, foot_FR_y=-0.03, foot_BL_y=-0.03, foot_BR_y=-0.03, extra={'Back.rx': -6, 'Tail1.rx': 4}),
    # ---- follow-through / landing squash / recovery
    pk(0.61, -38, 'out', root_y=-0.09, root_z=-0.01, foot_FL_y=-0.04, foot_FR_y=-0.04, foot_BL_y=-0.04, foot_BR_y=-0.04, extra={'Back.rx': -7, 'Tail1.rx': 8}),
    pk(0.70, -12, root_y=-0.06, root_z=-0.06, foot_FL_y=-0.02, foot_FR_y=-0.02, foot_BL_y=-0.02, foot_BR_y=-0.02, extra={'Back.rx': -3, 'Tail1.rx': 3}),
    pk(0.82, 14, 'in', root_y=-0.04, root_z=-0.03, extra={'Back.rx': 0}),
    (1.13, {}, 'smooth'),
]
def extra(t, v):
    if 0.40 <= t <= 0.52:          # quiver while holding the coil
        q = math.sin((t - 0.40) * 95) * 0.006
        v = dict(v); v['root.z'] = v.get('root.z', 0) + q; v['Head.rx'] = v.get('Head.rx', 0) + q * 260
    return v
ch = author(rig, feet, base, keys, DUR, extra=extra)
write_clip(rig, 'attack', ch); done.append('attack')

tmp = os.path.join(out_dir, 'anim_boar.glb')
export_anims(arm, mesh, tmp)
for tag in ('', '_lod1'):
    graft(f"{repo()}/{path}{tag}.glb", tmp, done, os.path.join(out_dir, f"boar{tag}.glb"))
print("DONE", done, "impact", IMPACT, "dur", DUR)
