import bpy, sys, os
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=os.path.abspath(sys.argv[-1]))
sc = bpy.context.scene; arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]; arm.animation_data_create()
for a in bpy.data.actions:
    nm = a.name.split('|')[-1]
    if nm not in ("attack", "attack_butt", "kick", "roar", "hit"): continue
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1]); rows = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f); pb = arm.pose.bones
        rows.append((f, pb["Head"].tail.z, pb["Head"].tail.y, pb["BackLowerLeg.L"].tail.y, pb["BackLowerLeg.R"].tail.y, pb["FrontLowerLeg.L"].tail.z, pb["Torso"].tail.z, pb["Head"].head.z))
    lo = min(rows, key=lambda r: r[1]); fwd = min(rows, key=lambda r: r[2]); kick = max(rows, key=lambda r: max(r[3], r[4]))
    hi = max(rows, key=lambda r: r[7])
    print("EVT", nm, "frames", f1 - f0 + 1, "head_low@", lo[0], "head_most_forward@", fwd[0], "hind_max_back@", kick[0], "head_high@", hi[0])
    if nm == "roar":
        tz = [(r[0], r[6]) for r in rows]; mx = max(tz, key=lambda t: t[1]); print("EVT roar torso_peak", mx, [t for t in tz if t[1] > mx[1] - 0.02][:1], [t for t in tz if t[1] > mx[1] - 0.02][-1:])
