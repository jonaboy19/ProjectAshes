extends SceneTree
## S3.1 locomotion slide probe (docs/plans/AAA_FINISH_PLAN.md B2): the real Player walks / runs / sprints on a flat floor,
## the planted-foot slip (ball bones, world space) is measured per case. Prints "LOCO <case> ..." lines.
##   godot --headless --path kingdom -s res://tools_qa/anim_states/loco_slide.gd -- [--no-lock]
## Slip = horizontal speed of a ball bone while it is within 2.5 cm of its lowest height and moving < 0.25 m/s vertically.
const BASE := 600.0
var _p: CharacterBody3D
var _sk: Skeleton3D
var _root3: Node3D
var _ball_w: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # ball bones after every modifier ran (skeleton_updated)
var _rec: Array = []                                          # [usec, left, right, body_v] per skeleton update while recording
var _recording := false
var _by_joint: Array = [[], [], []]
var _lat: Array[float] = []
var _lon: Array[float] = []
var _local_balls: Array = [Vector3.ZERO, Vector3.ZERO]
var _joint_p: Array[Vector3] = []     # per foot x (ankle, ball, toe tip): world position
var _joint_h: Array[float] = []       # ... and height above its own rest height
var _sole_h: Array[float] = [0.0, 0.0]     # lowest of ankle / ball / toe tip against their rest heights (0 = flat on the floor)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_root3 = Node3D.new()
	root.add_child(_root3)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	floor_body.add_child(cs)
	_root3.add_child(floor_body)
	floor_body.position = Vector3(0, BASE - 0.5, 0)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	_root3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	_p.view = 1
	var cam := Camera3D.new()
	_root3.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(3.0, BASE + 1.3, 0.0)    # the foot rig only runs near the current camera
	if OS.get_cmdline_user_args().has("--adult"):
		var life: Node = root.get_node("Life")
		life.life_path.set_age(16, root.get_node("WorldSim").day, root.get_node("WorldSim").time_of_day)    # full-size body (the game starts at age 4: 0.58)
		_p.apply_age()
	for i in 40:
		await physics_frame
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0]
	_sk.skeleton_updated.connect(_on_updated)
	var rig: Node = _p.get("_rig")
	var lock := not OS.get_cmdline_user_args().has("--no-lock")
	if rig != null and "foot_lock" in rig:
		rig.set("foot_lock", lock)
	print("LOCO lock=", lock, " rig=", rig != null)
	var an: RefCounted = _p.get("_animator")
	if an != null:
		print("LOCO gait points ", an.get("_pt_speed"), " strides ", an.get("_pt_stride"))
	# case, stick strength, sprint, extra input ("" | move_back | move_left | move_right with block | crouch), golden clip it scores
	var cases := [["slow", 0.4, false, "", "Walk"], ["walk", 1.0, false, "", "Jog_Fwd"], ["sprint", 1.0, true, "", "Sprint"]]
	if OS.get_cmdline_user_args().has("--points"):
		# each gait blend point on its own (body at the point's speed): which clip of the blend slides
		cases = [["p101", 1.01 / 2.4, false, "", "Walk"], ["p157", 1.57 / 2.4, false, "", "Mx_Walk_Standard"], ["p240", 1.0, false, "", "blend_2.4"],
				["p333", 3.33 / 6.5, true, "", "Mx_Run_Slow"], ["p443", 4.43 / 6.5, true, "", "Mx_Run_Standard"], ["p615", 6.15 / 6.5, true, "", "Jog_Fwd"]]
	if OS.get_cmdline_user_args().has("--all"):
		cases += [["back", 1.0, false, "move_back", "Walk_Backwards"], ["strafe_l", 1.0, false, "move_left", "Strafe_left"],
				["strafe_r", 1.0, false, "move_right", "Strafe_right"], ["crouch", 1.0, false, "crouch", "Crouch_Fwd"]]
	var results := {}
	for c in cases:
		var r: Dictionary = await _case(String(c[0]), float(c[1]), bool(c[2]), String(c[3]))
		r["case"] = c[0]
		results[String(c[4])] = r
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			var f := FileAccess.open(a.substr(7), FileAccess.WRITE)
			f.store_string(JSON.stringify({"_doc": "In-game planted-foot slip of the player's locomotion clips (tools_qa/anim_states/loco_slide.gd --all): the real Player at its game speed, foot lock " + ("on" if lock else "off") + "; m/s. golden_gate.py scores these clips' slide from here.", "lock": lock, "clips": results}, "	"))
			f.close()
	quit()


func _on_updated() -> void:
	if _joint_p.is_empty():
		_joint_p.resize(6)
		_joint_h.resize(6)
	for i in 2:
		var b := _sk.find_bone("ball_l" if i == 0 else "ball_r")
		_ball_w[i] = (_sk.global_transform * _sk.get_bone_global_pose(b)).origin
		var sx := "_l" if i == 0 else "_r"
		var low := 9e9
		for jn in ["foot", "ball", "ball_leaf"]:
			var jb := _sk.find_bone(jn + sx)
			var rest_y := (_sk.global_transform * _sk.get_bone_global_rest(jb)).origin.y
			var jp := (_sk.global_transform * _sk.get_bone_global_pose(jb)).origin
			_joint_p[i * 3 + ["foot", "ball", "ball_leaf"].find(jn)] = jp
			_joint_h[i * 3 + ["foot", "ball", "ball_leaf"].find(jn)] = jp.y - rest_y
			low = minf(low, jp.y - rest_y)
		_sole_h[i] = low
	if _recording:
		# skeleton_updated fires twice per frame with different poses (before / after the modifier stack): keep the LAST per frame
		var mdl: Node3D = _p.get("_model")
		var bl := mdl.global_transform.affine_inverse() * _ball_w[0]
		var br := mdl.global_transform.affine_inverse() * _ball_w[1]
		_local_balls = [bl * mdl.scale.x, br * mdl.scale.x]     # model space in world metres (undo the body scale)
		var rig_lw: Variant = _p.get("_rig").get("_lock_w") if _p.get("_rig") != null else [0.0, 0.0]
		var row := [Engine.get_process_frames() * 1000000 / 60, _ball_w[0], _ball_w[1], _p.get_real_velocity(), _sole_h[0], _sole_h[1], _joint_p.duplicate(), _joint_h.duplicate(), (rig_lw as Array).duplicate(), _local_balls.duplicate()]
		if not _rec.is_empty() and int(_rec[_rec.size() - 1][0]) == int(row[0]):
			_rec[_rec.size() - 1] = row
		else:
			_rec.append(row)


func _ball(i: int) -> Vector3:
	return _ball_w[i]


func _case(name: String, strength: float, sprint: bool, extra := "") -> Dictionary:
	_p.global_position = Vector3(0, BASE, 0)
	_p.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var move := "move_forward"
	if extra == "move_back" or extra == "move_left" or extra == "move_right":
		move = extra
	if extra == "move_left" or extra == "move_right":
		Input.action_press("block")          # strafe footwork: the guard keeps the body facing forward
	if extra == "crouch" and not bool(_p.get("crouching")):
		_p.call("toggle_crouch")
	Input.action_press(move, strength)
	if sprint:
		Input.action_press("sprint")
	for i in 90:                      # accelerate, get through the start transition
		await physics_frame
		_p.get_viewport().get_camera_3d().global_position = _p.global_position + Vector3(3.0, 1.3, 0.0)
	var an2: RefCounted = _p.get("_animator")
	if an2 != null and OS.get_cmdline_user_args().has("--dbg"):
		var tr: AnimationTree = an2.get("tree")
		print("LOCO dbg %s pos=%.2f rate=%.2f loco=%.2f speed=%.2f" % [name, tr["parameters/gait/blend_position"], tr["parameters/gait_rate/scale"], tr["parameters/loco/blend_amount"], float(an2.get("_speed"))])
	_rec.clear()
	_recording = true
	for i in 600:            # 10 s: enough stances at sprint cadence for a stable mean
		await physics_frame
		_p.set("stamina", 100.0)       # never winded: the measured speed stays the case speed
		_p.set("_run_time", 0.0)
		_p.get_viewport().get_camera_3d().global_position = _p.global_position + Vector3(3.0, 1.3, 0.0)
	_recording = false
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "block"]:
		Input.action_release(a)
	if extra == "crouch" and bool(_p.get("crouching")):
		_p.call("toggle_crouch")
	# Stance core: per foot, runs of >= 6 consecutive frames whose lowest joint (ankle / ball / toe tip, against its rest height)
	# stays below 2 cm; the first and last 2 frames of a run (heel strike / toe-off roll) are dropped. Slip = world horizontal
	# speed of the run's lowest joint (the same joint tracked through the run).
	var slips: Array[float] = []
	for f in 2:
		var run_start := -1
		for i in range(0, _rec.size() + 1):
			var planted := false
			if i < _rec.size():
				var hp: Array = _rec[i][7]
				var low_j := 0
				for k in 3:
					if float(hp[f * 3 + k]) < float(hp[f * 3 + low_j]):
						low_j = k
				planted = float(hp[f * 3 + low_j]) < 0.02
			if planted and run_start < 0:
				run_start = i
			elif not planted and run_start >= 0:
				var end := i - 1
				if end - run_start + 1 >= 6:
					# Contact point slip: each frame the lowest of ankle / ball / toe tip is the contact; it slips when the SAME joint
					# is still the contact on the next frame and moved across the ground (heel-to-ball roll hands the contact over
					# from one joint to the next and is not slip). --tracked: the old metric (one joint through the whole stance).
					var tracked := OS.get_cmdline_user_args().has("--tracked")
					var hs: Array = _rec[run_start + 2][7]
					var j := 0
					for k in 3:
						if float(hs[f * 3 + k]) < float(hs[f * 3 + j]):
							j = k
					for m in range(run_start + 3, end - 1):
						var dt := float(int(_rec[m][0]) - int(_rec[m - 1][0])) / 1e6
						if dt < 0.004:
							continue
						if not tracked:
							var ha: Array = _rec[m - 1][7]
							var hb: Array = _rec[m][7]
							var ja := 0
							var jb := 0
							for k in 3:
								if float(ha[f * 3 + k]) < float(ha[f * 3 + ja]):
									ja = k
								if float(hb[f * 3 + k]) < float(hb[f * 3 + jb]):
									jb = k
							if ja != jb:
								continue
							j = jb
						var pa: Vector3 = (_rec[m - 1][6] as Array)[f * 3 + j]
						var pb: Vector3 = (_rec[m][6] as Array)[f * 3 + j]
						var sv := Vector2(pb.x - pa.x, pb.z - pa.z) / dt
						slips.append(sv.length())
						_by_joint[j].append(sv.length())
						var fwd3: Vector3 = (_p.get("_model") as Node3D).global_basis.z
						var fw := Vector2(fwd3.x, fwd3.z).normalized()
						_lat.append(absf(sv.x * fw.y - sv.y * fw.x))
						_lon.append(sv.dot(fw))
				run_start = -1
	if OS.get_cmdline_user_args().has("--dump") and name == "walk":
		for i in range(60, 110):
			var hp: Array = _rec[i][7]
			var pp: Array = _rec[i][6]
			print("D %d hL=[%.3f %.3f %.3f] zL=[%.3f %.3f %.3f] hR=[%.3f %.3f %.3f] zR=[%.3f %.3f %.3f]" % [i, hp[0], hp[1], hp[2], pp[0].z, pp[1].z, pp[2].z, hp[3], hp[4], hp[5], pp[3].z, pp[4].z, pp[5].z])
	# diagnostic (coordinator, walk mismatch): planted ball speed relative to the body (model space, world metres) vs capsule speed
	var ratios: Array[float] = []
	for m in range(1, _rec.size()):
		for f in 2:
			if float((_rec[m][7] as Array)[f * 3 + 1]) < 0.02:
				var la: Vector3 = (_rec[m - 1][9] as Array)[f]
				var lb: Vector3 = (_rec[m][9] as Array)[f]
				var fv := Vector2(lb.x - la.x, lb.z - la.z).length() * 60.0
				var bv := Vector2((_rec[m][3] as Vector3).x, (_rec[m][3] as Vector3).z).length()
				if bv > 0.1:
					ratios.append(fv / bv)
	ratios.sort()
	if not ratios.is_empty():
		var mdl2: Node3D = _p.get("_model")
		var an3: Object = _p.get("_animator")
		print("LOCO %s foot/body ratio median %.3f p25 %.3f p75 %.3f n %d | model scale %.3f stride_scale %s rate %.3f" % [name,
				ratios[ratios.size() / 2], ratios[ratios.size() / 4], ratios[ratios.size() * 3 / 4], ratios.size(), mdl2.scale.x,
				str(an3.get("stride_scale")), float((an3.get("tree") as AnimationTree)["parameters/gait_rate/scale"])])
	# diagnostic: slip of the ball bone on frames where the rig holds the foot fully locked
	var lk: Array[float] = []
	for m in range(1, _rec.size()):
		for f in 2:
			if float((_rec[m][8] as Array)[f]) >= 0.99 and float((_rec[m - 1][8] as Array)[f]) >= 0.99:
				var pa: Vector3 = _rec[m - 1][1 + f]
				var pb: Vector3 = _rec[m][1 + f]
				lk.append(Vector2(pb.x - pa.x, pb.z - pa.z).length() * 60.0)
	var lkm := 0.0
	var lkx := 0.0
	for v in lk:
		lkm += v
		lkx = maxf(lkx, v)
	print("LOCO %s locked_ball frames=%d mean=%.3f max=%.3f" % [name, lk.size(), lkm / maxf(lk.size(), 1), lkx])
	var parts := []
	for jj in 3:
		var sm := 0.0
		for v in _by_joint[jj]:
			sm += v
		parts.append("%s n=%d mean=%.3f" % [["ankle", "ball", "toe"][jj], _by_joint[jj].size(), sm / maxf(_by_joint[jj].size(), 1)])
	var lat_m := 0.0
	for v in _lat:
		lat_m += v
	var lon_m := 0.0
	for v in _lon:
		lon_m += v
	print("LOCO %s contact joints: %s | sideways %.3f, along facing %.3f (signed mean)" % [name, ", ".join(parts), lat_m / maxf(_lat.size(), 1), lon_m / maxf(_lon.size(), 1)])
	_by_joint = [[], [], []]
	_lat.clear()
	_lon.clear()
	var mean := 0.0
	var mx := 0.0
	for s in slips:
		mean += s
		mx = maxf(mx, s)
	mean /= maxf(slips.size(), 1)
	var spd := 0.0
	for r: Array in _rec:
		spd += Vector2((r[3] as Vector3).x, (r[3] as Vector3).z).length()
	spd /= maxf(_rec.size(), 1)
	print("LOCO %s body=%.2f m/s contact_samples=%d slide_mean=%.3f slide_max=%.3f" % [name, spd, slips.size(), mean, mx])
	return {"body_speed": snappedf(spd, 0.01), "samples": slips.size(), "slide_mean": snappedf(mean, 0.001), "slide_max": snappedf(mx, 0.001)}


func rig_dbg() -> String:
	var rig: Node = _p.get("_rig")
	if rig == null:
		return ""
	return "weight=%.2f near=%s hit=%s owner_speed=%.2f lock_on=%s lock_w=%s use_ik=%s attacking=%s airborne=%s susp=%s" % [rig.get("_weight"), rig.get("always_near"),
			rig.get("_hit"), rig.get("_owner_speed"), rig.get("_lock_on"), rig.get("_lock_w"), rig.get("_use_ik"), rig.get("attacking"), rig.get("airborne"), rig.get("suppressed")]
