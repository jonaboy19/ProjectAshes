"""Re-import an exported wolf GLB and print: clips (frames, seconds), tris, image sizes, bones, size in metres."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
arm, mesh = load_glb(sys.argv[sys.argv.index('--') + 1])
acts = clip_actions()
print("VER bones", len(arm.data.bones), "tris", sum(len(p.vertices) - 2 for p in mesh.data.polygons), "arm scale", tuple(round(x, 4) for x in arm.matrix_world.to_scale()))
for n, a in sorted(acts.items()):
    f0, f1 = frame_range(a)
    print(f"VER clip {n:12s} frames {f0}-{f1}  {(f1 - f0) / 30:.2f}s")
for im in bpy.data.images: print("VER image", im.name, tuple(im.size))
P = mesh_world_np(mesh)
print("VER bbox m", P.min(0).round(3), P.max(0).round(3))
