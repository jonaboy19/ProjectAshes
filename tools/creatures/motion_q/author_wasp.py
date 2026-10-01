"""Giant wasp attack (Blender 5.2 headless): blender -b --python author_wasp.py -- <out_dir>
New 1.0 s attack on top of the looping flight (wings keep beating from the idle clip): abdomen curls forward, the body pulls back
and rises (telegraph 0.45 s, held with a wing flutter), then a 3-frame dive with the sting forward (impact 0.50 s), overshoot,
recovery.  The wasp faces +X in Blender (glTF +X); +ry pitches the nose down."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qpose import *
from glbtools import graft
out_dir = sys.argv[sys.argv.index('--') + 1]; os.makedirs(out_dir, exist_ok=True)
IMPACT = 0.50; DUR = 1.0
path, kind = CREATURES['giant_wasp']
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
n_idle = int(round(acts['idle'].frame_range[1] - acts['idle'].frame_range[0]))
idle = [rig.read('idle', f) for f in range(n_idle + 1)]
def base_at(f): return idle[f % n_idle]
def curl(a): return {'Abdomen.ry': -a * .30, 'Abdomen2.ry': -a * .30, 'Abdomen3.ry': -a * .25, 'Sting.ry': -a * .15}
def pk(t, ease='smooth', c=0.0, pitch=0.0, **kw):
    d = dict(curl(c)); d['Body.ry'] = pitch
    for k, v in kw.items(): d['root.' + k[5:] if k.startswith('root_') else k.replace('__', '.')] = v
    return (t, d, ease)
keys = [
    (0.00, {}, 'smooth'),
    pk(0.20, c=60, pitch=-8, root_x=-0.10, root_z=0.07),
    pk(0.34, c=95, pitch=-16, root_x=-0.20, root_z=0.14),
    pk(0.45, 'lin', c=100, pitch=-18, root_x=-0.22, root_z=0.16),
    pk(0.48, 'snap', c=80, pitch=14, root_x=0.10, root_z=-0.02),
    pk(0.50, 'snap', c=55, pitch=32, root_x=0.42, root_z=-0.20),
    pk(0.60, 'out', c=45, pitch=28, root_x=0.50, root_z=-0.22),
    pk(0.78, c=15, pitch=8, root_x=0.22, root_z=-0.06),
    (1.00, {}, 'smooth'),
]
def extra(t, v):
    if 0.34 <= t <= 0.45:      # flutter while holding the tell
        v = dict(v); v['root.z'] = v.get('root.z', 0) + math.sin(t * 150) * 0.012
    return v
ch = author(rig, {}, base_at(0), keys, DUR, extra=extra, base_at=base_at)
write_clip(rig, 'attack', ch)
# hit: the old synthesised hit only nudged the body 18 deg with frozen wings; new one = knock back + nose-up flinch + abdomen tuck, wings keep beating
hkeys = [(0.0, {}, 'smooth'),
         pk(0.05, 'snap', c=40, pitch=-24, root_x=-0.22, root_z=0.06),
         pk(0.16, 'out', c=25, pitch=-14, root_x=-0.16, root_z=0.03),
         pk(0.31, c=8, pitch=-4, root_x=-0.05, root_z=0.0),
         (0.47, {}, 'smooth')]
write_clip(rig, 'hit', author(rig, {}, base_at(0), hkeys, 0.47, base_at=base_at))
# loop close: the flight loop ended 5 cm (wing tip) away from its first pose; make the last frame identical to the first
for clip in ('idle', 'walk', 'run'):
    chs = [rig.read(clip, f) for f in range(n_idle + 1)]
    chs[-1] = {b: (c[0].copy(), c[1].copy(), c[2].copy()) for b, c in chs[0].items()}
    write_clip(rig, clip, chs)
tmp = os.path.join(out_dir, 'anim_wasp.glb'); export_anims(arm, mesh, tmp)
for tag in ('', '_lod1'):
    graft(f"{repo()}/{path}{tag}.glb", tmp, ['attack', 'hit', 'idle', 'walk', 'run'], os.path.join(out_dir, f"giant_wasp{tag}.glb"))
print("DONE attack impact", IMPACT, "dur", DUR)
