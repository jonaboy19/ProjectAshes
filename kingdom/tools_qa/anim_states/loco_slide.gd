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
	for c in [["slow", 0.4, false], ["walk", 1.0, false], ["sprint", 1.0, true]]:
		await _case(String(c[0]), float(c[1]), bool(c[2]))
	Input.action_release("move_forward")
	Input.action_release("sprint")
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
		var row := [Engine.get_process_frames() * 1000000 / 60, _ball_w[0], _ball_w[1], _p.get_real_velocity(), _sole_h[0], _sole_h[1], _joint_p.duplicate(), _joint_h.duplicate()]
		if not _rec.is_empty() and int(_rec[_rec.size() - 1][0]) == int(row[0]):
			_rec[_rec.size() - 1] = row
		else:
			_rec.append(row)


func _ball(i: int) -> Vector3:
	return _ball_w[i]


func _case(name: String, strength: float, sprint: bool) -> void:
	_p.global_position = Vector3(0, BASE, 0)
	_p.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	Input.action_press("move_forward", strength)
	if sprint:
		Input.action_press("sprint")
	for i in 90:                      # accelerate, get through the start transition
		await physics_frame
		_p.get_viewport().get_camera_3d().global_position = _p.global_position + Vector3(3.0, 1.3, 0.0)
	_rec.clear()
	_recording = true
	for i in 240:
		await physics_frame
		_p.get_viewport().get_camera_3d().global_position = _p.global_position + Vector3(3.0, 1.3, 0.0)
	_recording = false
	Input.action_release("move_forward")
	Input.action_release("sprint")
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
					var hs: Array = _rec[run_start + 2][7]
					var j := 0
					for k in 3:
						if float(hs[f * 3 + k]) < float(hs[f * 3 + j]):
							j = k
					for m in range(run_start + 3, end - 1):
						var dt := float(int(_rec[m][0]) - int(_rec[m - 1][0])) / 1e6
						if dt < 0.004:
							continue
						var pa: Vector3 = (_rec[m - 1][6] as Array)[f * 3 + j]
						var pb: Vector3 = (_rec[m][6] as Array)[f * 3 + j]
						slips.append(Vector2(pb.x - pa.x, pb.z - pa.z).length() / dt)
				run_start = -1
	if OS.get_cmdline_user_args().has("--dump") and name == "walk":
		for i in range(60, 110):
			var hp: Array = _rec[i][7]
			var pp: Array = _rec[i][6]
			print("D %d hL=[%.3f %.3f %.3f] zL=[%.3f %.3f %.3f] hR=[%.3f %.3f %.3f] zR=[%.3f %.3f %.3f]" % [i, hp[0], hp[1], hp[2], pp[0].z, pp[1].z, pp[2].z, hp[3], hp[4], hp[5], pp[3].z, pp[4].z, pp[5].z])
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


func rig_dbg() -> String:
	var rig: Node = _p.get("_rig")
	if rig == null:
		return ""
	return "weight=%.2f near=%s hit=%s owner_speed=%.2f lock_on=%s lock_w=%s use_ik=%s attacking=%s airborne=%s susp=%s" % [rig.get("_weight"), rig.get("always_near"),
			rig.get("_hit"), rig.get("_owner_speed"), rig.get("_lock_on"), rig.get("_lock_w"), rig.get("_use_ik"), rig.get("attacking"), rig.get("airborne"), rig.get("suppressed")]
