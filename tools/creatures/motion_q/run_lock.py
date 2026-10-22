"""blender -b --python run_lock.py -- <creature> <out_glb> <clip=speed> [<clip=speed> ...]
Re-plants the feet of the given clips at the given ground speeds and grafts the new clips into a copy of the creature's
LOD0 GLB (out_glb). Quadrupeds only (chains below)."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qgait import *
from glbtools import graft
args = sys.argv[sys.argv.index('--') + 1:]
cr, out = args[:2]; specs = [a.split('=') for a in args[2:]]
path, kind = CREATURES[cr]
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
CH = {'bear': {'F': ['FrontUpperLeg.{s}', 'FrontLowerLeg.{s}'], 'B': ['BackLeg.{s}', 'BackUpperLeg.{s}', 'BackLowerLeg.{s}']},
      'boar': {'F': ['FrontUpperLeg.{s}', 'FrontLowerLeg.{s}'], 'B': ['BackLeg.{s}', 'BackUpperLeg.{s}', 'BackLowerLeg.{s}']}}[cr]
chains = {fb + s: [b.format(s=s) for b in CH[fb]] for fb in 'FB' for s in 'LR'}
feet, H = quad_feet(rig, chains)
done = []
for clip, v in specs:
    ch = lock_clip(rig, feet, clip, float(v), H=H)
    write_clip(rig, clip, ch); done.append(clip)
tmp = os.path.join(os.path.dirname(out), f"anim_{cr}.glb")
export_anims(arm, mesh, tmp)
graft(f"{repo()}/{path}.glb", tmp, done, out)
print("GRAFTED", done, "->", out)
