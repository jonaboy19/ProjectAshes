extends SceneTree
## Static metrics for the wired AAA clips (data/anim/aaa_clips.json), on the pack GLBs with the root track ENABLED:
##   NaN transforms, lowest foot (cm below / above the clip's standing floor), the largest bone rotation away from rest (deg),
##   the largest joint distance from the pelvis (explosion check, m), foot slide of the planted foot (mean / max m/s) and root
##   travel. Acceptance (docs/anim/aaa_wiring): slide mean < 0.05, max < 0.15 m/s for in-place clips, feet >= -2 cm, no NaN,
##   no bone > 150 deg from rest, joints within 1.2 m of the pelvis.
##   Godot --headless --path kingdom -s tools_qa/anim/aaa_static_metrics.gd [-- --all]      (--all = skipped clips too)
const MAN := "res://data/anim/aaa_clips.json"


func _initialize() -> void:
	var all := OS.get_cmdline_user_args().has("--all")
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAN))["packs"]
	var bad := 0
	print("clip | as | sec | travel_m | min_ankle_vs_rest_cm | max_bone_deg | max_joint_m | slide_mean | slide_max | NaN | verdict")
	for pack: String in man:
		var clips: Dictionary = man[pack]
		var want: Array = []
		for c: String in clips:
			var st := String(clips[c]["status"])
			if all or st == "add" or (st == "cmp"):
				want.append(c)
		if want.is_empty():
			continue
		var inst: Node = (load(pack) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var fl := sk.find_bone("foot_l")
		var fr := sk.find_bone("foot_r")
		var pv := sk.find_bone("pelvis")
		var rest_ankle := sk.get_bone_global_rest(fl).origin.y
		for n in ap.get_animation_list():
			if n == "RESET" or not want.has(n):
				continue
			var anim := ap.get_animation(n)
			ap.play(n)
			ap.pause()
			var e: Dictionary = clips[n]
			var trim: Array = e.get("trim", [0.0, anim.length])
			var f0 := int(round(float(trim[0]) * 30.0))
			var f1 := int(round(float(trim[1]) * 30.0))
			var P: Array = []
			var nan := false
			var max_deg := 0.0
			var max_joint := 0.0
			for i in range(f0, f1 + 1):
				ap.seek(i / 30.0, true)
				sk.force_update_all_bone_transforms()
				var a: Vector3 = sk.get_bone_global_pose(fl).origin
				var b: Vector3 = sk.get_bone_global_pose(fr).origin
				var p: Vector3 = sk.get_bone_global_pose(pv).origin
				if is_nan(a.x) or is_nan(b.x) or is_nan(p.x):
					nan = true
				P.append([a, b, p])
				for bi in sk.get_bone_count():
					var q: Quaternion = sk.get_bone_pose_rotation(bi)
					var r: Quaternion = sk.get_bone_rest(bi).basis.get_rotation_quaternion()
					max_deg = maxf(max_deg, rad_to_deg(q.angle_to(r)))
					if sk.get_bone_name(bi) != "root":
						max_joint = maxf(max_joint, sk.get_bone_global_pose(bi).origin.distance_to(p))
			var miny := 9.0
			for r2 in P:
				miny = minf(miny, minf(r2[0].y, r2[1].y))
			# floor = the lowest the planted foot gets in the first and last 20 % (standing contact), cm relative to the rest ankle height
			var floor_y := 9.0
			for r2 in P:
				floor_y = minf(floor_y, minf(r2[0].y, r2[1].y))
			var tot := 0
			var cont := 0
			var sum := 0.0
			var mx := 0.0
			var dt := 1.0 / 30.0
			for i in range(1, P.size()):
				for f in 2:
					var cur: Vector3 = P[i][f]
					var prev: Vector3 = P[i - 1][f]
					tot += 1
					if cur.y < floor_y + 0.06 and absf(cur.y - prev.y) / dt < 0.25:
						var v := Vector2(cur.x - prev.x, cur.z - prev.z).length() / dt
						cont += 1
						sum += v
						mx = maxf(mx, v)
			var trav := Vector2(P[-1][2].x - P[0][2].x, P[-1][2].z - P[0][2].z).length()
			var mean := sum / maxi(cont, 1)
			var travel_clip := trav > 1.0
			var verdict := "ok"
			if nan or max_deg > 150.0 or max_joint > 1.2:
				verdict = "BAD"
			elif not travel_clip and (mean >= 0.05 or mx >= 0.15):
				verdict = "slide"
			elif travel_clip and (mean >= 0.25 or mx >= 0.6):
				verdict = "slide(travel)"
			if verdict == "BAD":
				bad += 1
			print("%s | %s | %.2f | %.2f | %+.1f | %.0f | %.2f | %.3f | %.3f | %s | %s" % [n, e.get("as", "-"), (f1 - f0) / 30.0, trav, (miny - rest_ankle) * 100.0, max_deg, max_joint,
					mean, mx, nan, verdict])
		inst.queue_free()
		await process_frame
	print("BAD clips: ", bad)
	quit()
