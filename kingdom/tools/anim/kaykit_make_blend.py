# Merge all KayKit "Rig_Medium" animation GLBs into one .blend (actions at 30 fps) and
# report which actions are natively looping (first pose == last pose).
# blender -b -P kaykit_make_blend.py -- <Rig_Medium dir> <out.blend> <out.json>
import bpy, sys, glob, os, json, math
d, out, rep = sys.argv[sys.argv.index("--") + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
main = None
seen = {}
for f in sorted(glob.glob(d + "/Rig_Medium_*.glb")):
    pack = os.path.basename(f)[11:-4]
    before_o = set(bpy.data.objects); before_a = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=f)
    arms = [o for o in bpy.data.objects if o not in before_o and o.type == "ARMATURE"]
    new_a = [a for a in bpy.data.actions if a not in before_a]
    if main is None:
        main = arms[0]; main.name = "Armature"
    for a in new_a:
        if a.name == "T-Pose" or "_Pose" in a.name:
            continue
        seen[a.name] = pack
    for o in [o for o in bpy.data.objects if o not in before_o and o is not main]:
        if o is not main and o.name != "Armature":
            bpy.data.objects.remove(o)
    for a in new_a:
        if a.name == "T-Pose" or "_Pose" in a.name:
            bpy.data.actions.remove(a); continue
        a.use_fake_user = True
        a.name = a.name  # keep
info = {}
main.animation_data_create()
for name, pack in seen.items():
    a = bpy.data.actions[name]
    main.animation_data.action = a
    if len(a.slots):
        main.animation_data.action_slot = a.slots[0]
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    bpy.context.scene.frame_set(f0)
    q0 = {b.name: b.rotation_quaternion.copy() for b in main.pose.bones}
    p0 = main.pose.bones["hips"].head.copy()
    bpy.context.scene.frame_set(f1)
    dq = max(q0[b.name].rotation_difference(b.rotation_quaternion).angle for b in main.pose.bones)
    dp = (main.pose.bones["hips"].head - p0).length
    info[name] = {"pack": pack, "frames": f1 - f0, "seconds": round((f1 - f0) / 30, 2),
                  "loop_dq_deg": round(math.degrees(dq), 1), "loop_dp_m": round(dp, 3)}
main.animation_data.action = None
bpy.ops.wm.save_as_mainfile(filepath=out)
json.dump(info, open(rep, "w"), indent=1)
print("SAVED", out, len(info))
