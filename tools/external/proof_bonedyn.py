"""Proof: Bone Dynamics (spring + wind) on the Rigify horse tail, baked to keyframes.
Run: tools/external/blender.sh tools/external/proof_bonedyn.py -- <out_dir>
"""
import sys, os, bpy, math
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(out, exist_ok=True)
C.clear_scene()
C.enable("rigify", "bone_dynamics")
bpy.ops.object.armature_horse_metarig_add()
bpy.ops.pose.rigify_generate()
rig = bpy.data.objects["rig"]
sc = bpy.context.scene
sc.frame_start, sc.frame_end = 1, 48
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
for f in range(1, 49):
    t = (f - 1) / 47 * 2 * math.pi * 2
    pb["torso"].location = (0, 0.35 * math.sin(t), 0.12 * abs(math.sin(t)))
    pb["torso"].keyframe_insert("location", frame=f)
tail = [b for b in pb if b.name.startswith("tail.00")]
for b in tail:
    b.bdyn.enabled = True
    b.bdyn.stiffness = 0.25
    b.bdyn.damping = 0.15
sc.bdyn.enabled = True
sc.bdyn.wind_strength = 6.0
tip = "tail.005"


def tip_pos():
    ev = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return (rig.matrix_world @ ev.pose.bones[tip].tail).copy()


def run(enabled):
    sc.bdyn.enabled = enabled
    res = {}
    for f in range(1, 49):
        sc.frame_set(f)
        res[f] = tip_pos()
    return res

off = run(False)
on = run(True)
maxd = max((on[f] - off[f]).length for f in on)
print("MAX_TIP_DELTA_M", round(maxd, 4))
assert maxd > 0.05
C.setup_render(w=640, h=420)
C.camera((9, -0.3, 1.2), target=(0, -0.3, 1.1), ortho=6.0)
for f in (8, 16, 24, 32):
    sc.frame_set(f)
    bpy.context.view_layer.update()
    sk = C.bone_lines(rig, lambda n: n.startswith("DEF-"), color=(0.15, 0.3, 0.55, 1))
    C.render(os.path.join(out, f"bdyn_f{f}.png"))
    bpy.data.objects.remove(sk)
bpy.ops.bdyn.bake()
act = rig.animation_data.action
fcs = [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
fcs = [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
n = sum(1 for fc in fcs if "tail" in fc.data_path)
print("BAKED tail fcurves", n)
