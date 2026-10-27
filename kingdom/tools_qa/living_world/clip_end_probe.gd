extends Node3D
## Where a once-clip leaves the body relative to its root, in the root's frame (Godot axes): feeds sidecar
## exit_offset / exit_yaw. godot --headless --path kingdom res://tools_qa/living_world/clip_end_probe.tscn -- --clip=Life_Mz_Wake_Bed


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var clip := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
	var m := Assets.mh_character("villager_man_a", 1.7)
	add_child(m)
	var ap := Assets.animation_player(m)
	LifeLibrary.install(ap)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
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
