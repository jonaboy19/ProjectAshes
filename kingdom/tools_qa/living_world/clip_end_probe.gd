extends Node3D
## Where a once-clip leaves the body relative to its root, in the root's frame (Godot axes): feeds sidecar
## exit_offset / exit_yaw. godot --headless --path kingdom res://tools_qa/living_world/clip_end_probe.tscn -- --clip=Life_Mz_Wake_Bed


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var clip := ""
	var back := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
		elif a == "--back":
			back = true      # lean clips: how far behind the root (-Z, root frame) each body joint reaches over the loop
	var m := Assets.mh_character("villager_man_a", 1.7)
	add_child(m)
	var ap := Assets.animation_player(m)
	LifeLibrary.install(ap)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	if back:
		ap.play(clip)
		var L := ap.current_animation_length
		var mins := {}
		for i in 41:
			ap.seek(L * float(i) / 40.0, true)
			ap.advance(0.0)
			await get_tree().process_frame
			for bn in ["pelvis", "spine_02", "spine_03", "neck_01", "Head", "upperarm_l", "upperarm_r", "foot_l", "foot_r", "ball_l", "ball_r", "hand_l", "hand_r"]:
				var bi := sk.find_bone(bn)
				if bi < 0:
					continue
				var p: Vector3 = m.global_transform.inverse() * (sk.global_transform * sk.get_bone_global_pose(bi).origin)
				if not mins.has(bn):
					mins[bn] = [p.z, p.y, p.x, p.x]
				if p.z < float(mins[bn][0]):
					mins[bn][0] = p.z
					mins[bn][1] = p.y
				mins[bn][2] = minf(float(mins[bn][2]), p.x)
				mins[bn][3] = maxf(float(mins[bn][3]), p.x)
		for bn: String in mins:
			print("BACK %s %s z=%.3f y=%.2f x=[%.3f, %.3f]" % [clip, bn, float(mins[bn][0]), float(mins[bn][1]), float(mins[bn][2]), float(mins[bn][3])])
		get_tree().quit(0)
		return
	for c in [clip, "Idle"]:
		ap.play(c)
		ap.seek(0.0 if c == "Idle" else ap.current_animation_length - 0.001, true)
		ap.advance(0.0)
		await get_tree().process_frame
		var g := func(b: String) -> Vector3: return m.global_transform.inverse() * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin)
		var mid: Vector3 = (g.call("foot_l") + g.call("foot_r")) * 0.5
		var side: Vector3 = g.call("thigh_l") - g.call("thigh_r")
		var fwd := Vector3.UP.cross(side)
		print("ENDPOSE %s feet_mid=(%.3f, %.3f, %.3f) yaw_deg=%.1f" % [c, mid.x, mid.y, mid.z, rad_to_deg(atan2(fwd.x, fwd.z))])
	get_tree().quit(0)
