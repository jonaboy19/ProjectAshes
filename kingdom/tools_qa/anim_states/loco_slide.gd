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
	for c in [["walk", 0.4, false], ["jog", 1.0, false], ["sprint", 1.0, true]]:
		await _case(String(c[0]), float(c[1]), bool(c[2]))
	Input.action_release("move_forward")
	Input.action_release("sprint")
	quit()


func _on_updated() -> void:
	for i in 2:
		var b := _sk.find_bone("ball_l" if i == 0 else "ball_r")
		_ball_w[i] = (_sk.global_transform * _sk.get_bone_global_pose(b)).origin
	if _recording:
		_rec.append([Time.get_ticks_usec(), _ball_w[0], _ball_w[1], _p.get_real_velocity()])


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
	var slips: Array[float] = []
	for f in 2:
		var miny := 9e9
		for r: Array in _rec:
			miny = minf(miny, (r[1 + f] as Vector3).y)
		for i in range(1, _rec.size()):
			var dt := float(int(_rec[i][0]) - int(_rec[i - 1][0])) / 1e6
			if dt < 0.004:
				continue
			var a: Vector3 = _rec[i - 1][1 + f]
			var b: Vector3 = _rec[i][1 + f]
			if b.y < miny + 0.025 and absf(b.y - a.y) / dt < 0.25:
				slips.append(Vector2(b.x - a.x, b.z - a.z).length() / dt)
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
