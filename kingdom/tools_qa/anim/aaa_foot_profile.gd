extends SceneTree
## Per-frame foot / pelvis heights (m above the clip's lowest foot) of clips in a pack GLB, root travel INCLUDED, plus
## foot-slide (planted foot speed) and the heights of the airborne window, for run-vault timing (touch_down / handover).
##   Godot --headless --path kingdom -s tools_qa/anim/aaa_foot_profile.gd -- --glb=res://...glb --clips=A,B [--every=3]
func _initialize() -> void:
	var glb := ""
	var only: PackedStringArray = []
	var every := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): glb = a.substr(6)
		elif a.begins_with("--clips="): only = a.substr(8).split(",")
		elif a.begins_with("--every="): every = int(a.substr(8))
	var inst: Node = (load(glb) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var fl := sk.find_bone("foot_l"); var fr := sk.find_bone("foot_r"); var pv := sk.find_bone("pelvis")
	for n in ap.get_animation_list():
		if n == "RESET" or (not only.is_empty() and not only.has(n)): continue
		var anim := ap.get_animation(n)
		ap.play(n); ap.pause()
		var steps := int(anim.length * 30.0)
		var rows: Array = []
		var lo := 9.0
		for i in range(steps + 1):
			ap.seek(i / 30.0, true)
			sk.force_update_all_bone_transforms()
			var a: Vector3 = sk.get_bone_global_pose(fl).origin
			var b: Vector3 = sk.get_bone_global_pose(fr).origin
			var p: Vector3 = sk.get_bone_global_pose(pv).origin
			lo = minf(lo, minf(a.y, b.y))
			rows.append([a, b, p])
		print("== %s  %.2fs  %d frames  lowest foot %.3f" % [n, anim.length, steps + 1, lo])
		var line := ""
		for i in range(0, rows.size(), every):
			var r: Array = rows[i]
			line += "f%d: L%.2f R%.2f P%.2f z%.2f | " % [i, r[0].y - lo, r[1].y - lo, r[2].y, r[2].z]
			if (i / every) % 4 == 3:
				print(line); line = ""
		print(line)
	quit()
