"""Round-trip test: import GLB, export unchanged with the pipeline's export settings, re-import and compare skinned vertices.
blender -b --python roundtrip.py -- <glb> <out.glb>"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
glb, out = sys.argv[sys.argv.index('--')+1:][:2]
arm, meshes, acts = load(glb)
mesh = [m for m in meshes if m.parent == arm][0]
sc = bpy.context.scene
ref = {}
for n, a in acts.items():
    set_clip(arm, a); f0, f1 = a.frame_range
    ref[n] = [(f, eval_verts(mesh)) for f in (f0, (f0+f1)/2, f1) if not sc.frame_set(int(f))]
    print("CLIP", n, a.name, a.frame_range, [s.name_display for s in a.slots])
for a in acts.values(): a.use_fake_user = True
for o in bpy.data.objects: o.select_set(o in (arm, mesh))
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88,
    export_animation_mode='ACTIONS', export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
    export_anim_single_armature=True, export_def_bones=False)
NV = len(mesh.data.vertices); NA = sorted(acts)
print("SIZE", os.path.getsize(glb)//1024, "->", os.path.getsize(out)//1024, "KB")
arm2, meshes2, acts2 = load(out)
mesh2 = [m for m in meshes2 if m.parent == arm2][0]
print("ARM2", tuple(arm2.scale), "bones", len(arm2.data.bones), "verts", len(mesh2.data.vertices), "vs", NV)
print("CLIPS", sorted(acts2), "orig", NA)
for n, lst in ref.items():
    a = acts2[n]; set_clip(arm2, a)
    for f, V in lst:
        sc.frame_set(int(f)); V2 = eval_verts(mesh2)
        d = np.linalg.norm(V - V2, axis=1)
        print("DIFF", n, f, "max_cm", round(float(d.max()) * 100, 3), "mean_cm", round(float(d.mean()) * 100, 4))
