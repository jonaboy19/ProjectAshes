"""blender -b --python dump_bones.py -- <creature> : world (m) bone heads of the rest/idle pose + verify our FK against Blender"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qrig import *
cr = sys.argv[sys.argv.index('--')+1]
path, kind = CREATURES[cr]
arm, meshes, acts = load(f"{repo()}/{path}.glb"); mesh = [m for m in meshes if m.parent == arm][0]
rig = Rig(arm, mesh, acts)
print("s", rig.s, "clips", sorted(acts))
for clip in sorted(acts):
    for f in (0, 5):
        ch = rig.read(clip, f); P = rig.fk(ch)
        err = max((P[n].translation - arm.pose.bones[n].matrix.translation).length for n in rig.names)
        print("FK check", clip, f, "max head err (arm units)", err)
ch = rig.read('idle', 0); P = rig.fk(ch)
for n in rig.names:
    h = P[n].translation * rig.s
    print(f"{n:22s} {rig.parent[n] or '-':18s} head_m=({h.x:6.3f},{h.y:6.3f},{h.z:6.3f})")
