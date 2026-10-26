extends SceneTree
## Gait phase probe: for each looping gait clip, samples foot_l / foot_r forward position relative to the pelvis (character +Z),
## finds the number of gait cycles in the loop (autocorrelation of foot_l) and the loop fraction at which the LEFT foot is furthest
## forward (heel strike), the phase CharacterAnimator's shared one-second timeline expects at t = 0.
##   godot --headless --path kingdom -s res://tools/anim/loco/gait_phase.gd -- --clips=Walk,Walk_Brisk,... [--dump=Clip]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var clips: PackedStringArray = []
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = a.substr(8).split(",", false)
		elif a.begins_with("--dump="):
			dump = a.substr(7)
	var node: Node3D = Assets.mh_character("player_young", 1.8)
	root.add_child(node)
	await process_frame
	var sk: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = Assets.animation_player(node)
	var pel := sk.find_bone("pelvis")
	var fl := sk.find_bone("foot_l")
	var fr := sk.find_bone("foot_r")
	for c in clips:
		if not ap.has_animation(c):
			print("PHASE %s missing" % c)
			continue
		var anim := ap.get_animation(c)
		var lm := anim.loop_mode
		anim.loop_mode = Animation.LOOP_NONE
		ap.play(c, 0.0)
		var n := maxi(int(round(anim.length * 60.0)), 4)
		var zl := PackedFloat32Array()
		var zr := PackedFloat32Array()
		for i in n:
			ap.seek(anim.length * i / n, true)
			var p := sk.get_bone_global_pose(pel).origin
			zl.append(sk.get_bone_global_pose(fl).origin.z - p.z)
			zr.append(sk.get_bone_global_pose(fr).origin.z - p.z)
		anim.loop_mode = lm
		# cycle count: smallest lag (fraction of the loop) with minimal circular difference of foot_l, tested at 1, 1/2, 1/3
		var best_k := 1
		var best_err := 1e9
		for k in [1, 2, 3]:
			var lag := int(round(float(n) / k))
			var err := 0.0
			for i in n:
				err += absf(zl[i] - zl[(i + lag) % n])
			if k == 1:
				continue
			if err / n < 0.01 and best_err == 1e9:
				best_k = k
				best_err = err
		var period := n / best_k
		var imax := 0
		for i in period:
			if zl[i] > zl[imax]:
				imax = i
		# stance-core ground speed: backward speed of the lowest joint (ankle / ball / toe) relative to the pelvis while that foot's
		# sole is < 2 cm above its rest height, first / last 2 frames of every stance run dropped (what a planted foot must cover).
		var spd := _stance_speed(sk, ap, anim, c)
		print("PHASE %s len=%.2f stance_speed=%.2f cycles=%d left_forward_at=%.3f (of loop) cycle_s=%.2f" % [c, anim.length, spd, best_k, float(imax) / n, anim.length / best_k])
		if dump == c:
			for i in range(0, n, 3):
				print("  %.3f zl=%.3f zr=%.3f" % [float(i) / n, zl[i], zr[i]])
	quit()


func _stance_speed(sk: Skeleton3D, ap: AnimationPlayer, anim: Animation, clip: String) -> float:
	var lm := anim.loop_mode
	anim.loop_mode = Animation.LOOP_NONE
	ap.play(clip, 0.0)
	var n := maxi(int(round(anim.length * 120.0)), 6)
	var pel := sk.find_bone("pelvis")
	var speeds: Array[float] = []
	for f in 2:
		var joints: Array[int] = []
		var rest_y: Array[float] = []
		for jn in ["foot", "ball", "ball_leaf"]:
			var b := sk.find_bone(jn + ("_l" if f == 0 else "_r"))
			joints.append(b)
			rest_y.append(sk.get_bone_global_rest(b).origin.y)
		var rel: Array = []       # per frame: [lowest height, position of lowest joint relative to pelvis (z)]
		for i in n + 1:
			ap.seek(anim.length * i / n, true)
			var pz := sk.get_bone_global_pose(pel).origin.z
			var lo := 9e9
			var z := 0.0
			for k in 3:
				var o := sk.get_bone_global_pose(joints[k]).origin
				var h := o.y - rest_y[k]
				if h < lo:
					lo = h
					z = o.z - pz
			rel.append([lo, z])
		var dt := anim.length / n
		var run_start := -1
		for i in range(n + 2):
			var planted := i <= n and float(rel[i][0]) < 0.02
			if planted and run_start < 0:
				run_start = i
			elif not planted and run_start >= 0:
				var end := i - 1
				if end - run_start + 1 >= 8:
					# forward-backward travel of the foot relative to the pelvis across the run core: slope of z over time
					var a := run_start + 2
					var b := end - 2
					if b > a:
						speeds.append(-(float(rel[b][1]) - float(rel[a][1])) / ((b - a) * dt))
				run_start = -1
	anim.loop_mode = lm
	speeds.sort()
	return speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
