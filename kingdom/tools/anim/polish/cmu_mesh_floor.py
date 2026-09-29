# Per-frame lowest point of the SKINNED mannequin mesh for every clip of a UAL clip GLB (Blender, no render).
# The bone-based metrics of render_clips.py miss body thickness (a lying pelvis joint is ~0.1 m above the floor), this uses the
# evaluated mesh. Output json: {clip: {"fps": 30, "minz": [per frame], "maxz": [...], "root": [[x,y] per frame], "seconds": s}}
#   blender -b -P cmu_mesh_floor.py -- <clips.glb> <out.json> [--clips=A,B]
import bpy, sys, os, json
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
GLB = os.path.abspath(argv[0]); OUT = os.path.abspath(argv[1])
ONLY = None
for a in argv[2:]:
    if a.startswith("--clips="):
        ONLY = a[8:].split(",")
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
bpy.ops.import_scene.gltf(filepath=UAL)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for o in [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Mannequin"]:
    bpy.data.objects.remove(o)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
acts = {a.name: a for a in bpy.data.actions}
for a in acts.values():
    a.use_fake_user = True
for o in list(bpy.data.objects):
    if o not in before:
        bpy.data.objects.remove(o)
arm.animation_data_create()
mann = bpy.data.objects["Mannequin"]
res = {}
for name, act in ([("_warm", list(acts.values())[0])] + list(acts.items())):
    if ONLY and name not in ONLY and name != "_warm":
        continue
    arm.animation_data.action = act
    nf = int(round(act.frame_range[1] - act.frame_range[0]))
    f0 = int(round(act.frame_range[0]))
    sc.frame_set(f0 + 1); bpy.context.view_layer.update()
    mn, mx, rt = [], [], []
    for f in range(nf + 1):
        sc.frame_set(f0 + f)
        dg = bpy.context.evaluated_depsgraph_get()
        me = mann.evaluated_get(dg).to_mesh()
        co = np.empty(len(me.vertices) * 3, dtype=np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        M = np.array(mann.matrix_world)
        z = co @ M[2, :3] + M[2, 3]
        mn.append(round(float(z.min()), 4)); mx.append(round(float(z.max()), 4))
        r = arm.matrix_world @ arm.pose.bones["root"].head
        rt.append([round(r.x, 4), round(r.y, 4)])
        mann.evaluated_get(dg).to_mesh_clear()
    if name == "_warm":
        continue
    res[name] = {"fps": 30, "minz": mn, "maxz": mx, "root": rt, "seconds": round(nf / 30, 3)}
    print("MESH", name, nf, "minz %.3f..%.3f" % (min(mn), max(mn)), flush=True)
json.dump(res, open(OUT, "w"))
