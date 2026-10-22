import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from authoring import *
a = sys.argv[sys.argv.index('--')+1:]
rig = Rig(a[0])
print("SCALE", rig.s, "f", tuple(rig.f), "r", tuple(rig.r), "frames attack", rig.frames('attack'))
print("ARM len m", {k: round(rig.len[k]*rig.s,3) for k in ("RightArm","RightForeArm","RightUpLeg","RightLeg","Hips","Spine")})
Mb = rig.base_at('attack', 1)
fb = author_clip(rig, 'attack', 1, [(0, {}), (0.5, {})], 0.5)
rig.replace_action('testclip', fb)
rig.set_action('testclip'); bpy.context.scene.frame_set(1)
M = rig.pose_matrices()
print("MAXDEV(m)", max((M[n].translation - Mb[n].translation).length for n in rig.order) * rig.s)
# now with some mods
fb = author_clip(rig, 'attack', 1, [(0, {}), (0.3, dict(hips=(0,0,-0.1), rhand=(0.2,0.3,0.8), hips_rot=(10,0,0)))], 0.3)
rig.replace_action('testclip', fb); rig.set_action('testclip'); bpy.context.scene.frame_set(10)
M = rig.pose_matrices()
print("hips", tuple(M['Hips'].translation*rig.s), "rhand", tuple(M['RightHand'].translation*rig.s), "rshoulder", tuple(M['RightArm'].translation*rig.s), "rfoot", tuple(M['RightFoot'].translation*rig.s), "base rfoot", tuple(Mb['RightFoot'].translation*rig.s))
Mb = rig.base_at('attack', 1)
fb = rig.basis_from(Mb)
for n in rig.order[:8]:
    pb = rig.arm.pose.bones[n]
    print("BASIS", n, tuple(round(x,3) for x in pb.location), tuple(round(x,3) for x in pb.rotation_quaternion), tuple(round(x,3) for x in pb.scale), "| mine", tuple(round(x,3) for x in fb[n][0]), tuple(round(x,3) for x in fb[n][1]), pb.rotation_mode)
print("----")
rig.replace_action('testclip', [fb, fb])
rig.set_action('testclip'); bpy.context.scene.frame_set(2); bpy.context.scene.frame_set(1)
M = rig.pose_matrices()
for n in rig.order[:6]:
    pb = rig.arm.pose.bones[n]
    print("DEV", n, round((M[n].translation - Mb[n].translation).length*rig.s,4), tuple(round(x,3) for x in pb.rotation_quaternion), tuple(round(x,3) for x in fb[n][1]))
print("ACT", rig.arm.animation_data.action.name, [ (fc.data_path, fc.array_index) for fc in rig.arm.animation_data.action.layers[0].strips[0].channelbags[0].fcurves][:4])
