"""Numeric motion metrics from a GLB (run inside Blender: -b --python metrics.py -- <glb> <out.json> [speed_override_json]).
Per clip: per-frame world positions of feet/toes/hands/hips/head, mesh min z, stance-phase foot slip
(at a given ground speed and at the slip-minimising speed), hand ground clearance."""
import bpy, sys, os, json, math
import numpy as np
from mathutils import Vector
args = sys.argv[sys.argv.index('--') + 1:]
glb, outp = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=os.path.abspath(glb))
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith('Icosphere')][0]
for o in list(bpy.data.objects):
    if o.name.startswith('Icosphere'): bpy.data.objects.remove(o)
arm.animation_data_create()
BONES = ["Hips", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftHand", "RightHand", "Head", "Spine", "LeftLeg", "RightLeg", "LeftForeArm", "RightForeArm", "LeftArm", "RightArm"]
sc = bpy.context.scene
def sample(a, with_mesh=True):
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    d = {b: [] for b in BONES}; mz = []; hm = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for b in BONES:
            d[b].append(list(arm.matrix_world @ arm.pose.bones[b].head))
        if with_mesh:
            dg = bpy.context.evaluated_depsgraph_get(); ev = mesh.evaluated_get(dg); me = ev.to_mesh()
            zs = [(ev.matrix_world @ v.co).z for v in me.vertices]; mz.append(min(zs)); hm.append(max(zs)); ev.to_mesh_clear()
    return f0, f1, {k: np.array(v) for k, v in d.items()}, mz, hm
out = {}
for a in bpy.data.actions:
    name = a.name.split('|')[-1]
    f0, f1, d, mz, hm = sample(a)
    out[name] = {"f0": f0, "f1": f1, "pos": {k: v.round(4).tolist() for k, v in d.items()}, "minz": [round(x, 4) for x in mz], "maxz": [round(x, 4) for x in hm]}
    print("CLIP", name, f0, f1, "n", f1 - f0 + 1, "minz %.3f..%.3f" % (min(mz), max(mz)), "maxz %.3f" % max(hm))
json.dump(out, open(outp, 'w'))
