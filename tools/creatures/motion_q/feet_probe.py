"""Dump foot height/y per frame for a clip. blender -b --python feet_probe.py -- <creature> <clip>"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
cr, clip = sys.argv[sys.argv.index('--')+1:][:2]
path, kind = CREATURES[cr]
arm, meshes, acts = load(f"{repo()}/{path}.glb")
mesh = [m for m in meshes if m.name == cr][0]
print("VGROUPS", [v.name for v in mesh.vertex_groups])
a = acts[clip]; set_clip(arm, a); sc = bpy.context.scene
print("range", a.frame_range)
sc.frame_set(int(a.frame_range[0]))
V0 = eval_verts(mesh); print("rest verts z", V0[:,2].min(), V0[:,2].max(), "y", V0[:,1].min(), V0[:,1].max())
