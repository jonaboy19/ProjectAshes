"""Proof: Wiggle 2 spring physics on a Rigify horse tail + mane, driven by a torso bounce.
Run: tools/external/blender.sh tools/external/proof_wiggle2.py -- <out_dir>
Steps: enable add-on -> flag bones (wiggle_tail, stiff, damp) -> step frames
(handler simulates) -> bpy.ops.wiggle.bake -> tail tip world positions + frames.
"""
import sys, os, bpy, math
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(out, exist_ok=True)
C.clear_scene()
C.enable("rigify", "wiggle_2")
bpy.ops.object.armature_horse_metarig_add()
bpy.ops.pose.rigify_generate()
rig = bpy.data.objects["rig"]
sc = bpy.context.scene
sc.frame_start, sc.frame_end = 1, 48
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
# motion: horse body bounces and lunges (gallop-like), controls keyed
for f in range(1, 49):
    t = (f - 1) / 47 * 2 * math.pi * 2
    pb["torso"].location = (0, 0.35 * math.sin(t), 0.12 * abs(math.sin(t)))
    pb["torso"].keyframe_insert("location", frame=f)
# flag tail FK controls + mane bones as springs
tail = [b for b in pb if b.name.startswith("tail.00")]
print("TAIL", [b.name for b in tail])
sc.wiggle_enable = True
for b in tail:
    b.wiggle_tail = True
    b.wiggle_stiff = 400.0
    b.wiggle_damp = 6.0
    b.wiggle_mass = 1.0
bpy.ops.wiggle.select() if False else None
tip = "tail.005"


def tip_pos():
    return (rig.matrix_world @ rig.evaluated_get(bpy.context.evaluated_depsgraph_get()).pose.bones[tip].tail).copy()


# reference (wiggle off) vs simulated tip positions at the frames we render
def run(enabled):
    sc.wiggle_enable = enabled
    if enabled:
        bpy.ops.wiggle.reset()
    res = {}
    for f in range(1, 49):
        sc.frame_set(f)
        res[f] = tip_pos()
    return res

# NOTE: toggling sc.wiggle_enable triggers build_list; run wiggle-off first
off = run(False)
on = run(True)
maxd = max((on[f] - off[f]).length for f in on)
print("MAX_TIP_DELTA_M", round(maxd, 4))
assert maxd > 0.05, "wiggle produced no secondary motion"
# render 4 frames with wiggle
C.setup_render(w=640, h=420)
C.camera((9, -0.3, 1.2), target=(0, -0.3, 1.1), ortho=6.0)
is_def = lambda n: n.startswith("DEF-")
files = []
for f in (8, 16, 24, 32):
    sc.frame_set(f)
    bpy.context.view_layer.update()
    sk = C.bone_lines(rig, is_def, color=(0.55, 0.15, 0.1, 1))
    p = os.path.join(out, f"wiggle_f{f}.png")
    C.render(p)
    files.append(p)
    bpy.data.objects.remove(sk)
# bake
try:
    bpy.ops.wiggle.bake()
    act = rig.animation_data.action
    fcs = [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
    print("BAKED action", act.name, "fcurves", len(fcs))
except Exception as e:
    print("BAKE_FAILED", e)
