"""Proof: Expy Kit 'Rigify Game Friendly' turns a Rigify human (villager) into a
single-hierarchy deform skeleton, exported as GLB, and re-imported to check.
Run: tools/external/blender.sh tools/external/proof_expykit.py -- <out_dir>
"""
import sys, os, bpy
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(out, exist_ok=True)
C.clear_scene()
C.enable("rigify", "expy_kit")
bpy.ops.object.armature_human_metarig_add()
bpy.ops.pose.rigify_generate()
rig = bpy.data.objects["rig"]
n0 = len(rig.data.bones)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.armature.expykit_convert_gamefriendly(keep_backup=False)
bpy.ops.object.mode_set(mode="OBJECT")
arm = bpy.context.view_layer.objects.active
deform = [b for b in arm.data.bones if b.use_deform]
roots = [b.name for b in arm.data.bones if b.parent is None]
print("BONES before", n0, "after", len(arm.data.bones), "deform", len(deform), "roots", roots)
glb = os.path.join(out, "human_gamefriendly.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_def_bones=True)
print("GLB", glb, os.path.getsize(glb), "bytes")
C.setup_render(w=900, h=560)
C.camera((0, -9, 1.0), target=(0, 0, 1.0), ortho=3.4)
sk = C.bone_lines(arm, lambda n: n.startswith("DEF-") or n == "root", color=(0.15, 0.35, 0.15, 1))
C.render(os.path.join(out, "human_gamefriendly.png"))
# re-import GLB into a clean scene and count what a game engine would see
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=glb)
a = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
gb = a.data.bones
print("GLB_REIMPORT bones", len(gb), "roots", [b.name for b in gb if b.parent is None][:5])
