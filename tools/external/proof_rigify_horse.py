"""Proof: Rigify horse metarig -> generated rig -> pose controls -> render.
Run: tools/external/blender.sh tools/external/proof_rigify_horse.py -- <out_dir>
"""
import sys, os, bpy
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(out, exist_ok=True)
C.clear_scene()
C.enable("rigify")
bpy.ops.object.armature_horse_metarig_add()
bpy.ops.pose.rigify_generate()
rig = bpy.data.objects["rig"]
print("GENERATED bones:", len(rig.data.bones))
C.setup_render()
C.camera((9, -0.3, 1.2), target=(0, -0.3, 1.2), ortho=5.2)
is_def = lambda n: n.startswith("DEF-")
sk = C.bone_lines(rig, is_def)
C.render(os.path.join(out, "horse_rest.png"))
bpy.data.objects.remove(sk)
# rear up: lift both fore-foot IK controls and pitch the torso
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
for s in "LR":
    pb[f"forefoot_ik.{s}"].location.z = 0.55
    pb[f"forefoot_ik.{s}"].location.y = -0.2
pb["torso"].rotation_mode = "XYZ"
pb["torso"].rotation_euler.x = -0.35
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.update()
sk = C.bone_lines(rig, is_def, color=(0.55, 0.15, 0.1, 1))
C.render(os.path.join(out, "horse_rear.png"))
