extends Node3D
## Movie-Maker rig for the PC wall-contact / traversal-realism cases (docs/anim/aaa_wiring/). The real Player in a small test
## world, driven by programmatic input; prints a metrics line every 0.1 s ("M t=... pos=... v=... wall=... starts=...").
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim/wall_rig.tscn --write-movie o.png --fixed-fps 30 --quit-after N
##         -- --case=head_walk|head_sprint|oblique|beam|slope20|slope45|stairs|ledge|vault_run|hold [--baseline]
## --baseline switches the new wall / ground hooks off (the pre-change behaviour) to record the bug first.
## Cases run for ~5 s; the player starts 6 m from the obstacle and walks toward -Z (yaw 0).

const PlayerScript := preload("res://scripts/actors/player.gd")
## The world sits 600 m up: Player._keep_above_ground snaps the body above WorldGen's terrain otherwise.
const BASE := 600.0

## --baseline: the old behaviour (no wall / ground hooks).
class NullWall extends RefCounted:
	var state: StringName = &"none"
	func bind_rig(_r: Node) -> void: pass
	func tick(_b: Node, _d: Vector3, _dt: float) -> void: pass
	func blocked() -> bool: return false
	func lean() -> Vector2: return Vector2.ZERO
	func limit_speed(v: float) -> float: return v


class NullGround extends RefCounted:
	func bind_rig(_r: Node) -> void: pass
	func pre_move(body: CharacterBody3D, _d: Vector3, _dt: float, _r: bool, _w: RefCounted) -> Vector3: return body.velocity
	func lean_pitch() -> float: return 0.0


var _p: CharacterBody3D
var _case := "head_walk"
var _t := 0.0
var _starts := 0
var _last_kind := ""
var _min_hand := 9.0
var _wall_z := -3.0
var _log_t := 0.0
var _baseline := false
var _cam: Camera3D
var _max_pelvis_drop := 0.0
var _hand_log := ""
var _benched := false
var _hand_w: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sk: Skeleton3D
var _head_y := 0.0


func _box(c: Vector3, s: Vector3, rot := Vector3.ZERO, col := Color(0.55, 0.5, 0.45)) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	b.add_child(mi)
	add_child(b)
	b.position = c + Vector3(0, BASE, 0)
	b.rotation = rot
	return b


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			_case = a.substr(7)
		elif a == "--baseline":
			_baseline = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.7, 0.8, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Vector3.ZERO, Color(0.4, 0.5, 0.35))
	var start := Vector3(0, 0, 3.0)
	var yaw := 0.0
	match _case:
		"head_walk", "head_sprint", "hold", "bench":
			_box(Vector3(0, 1.5, -3.5), Vector3(6, 3, 1), Vector3.ZERO, Color(0.65, 0.55, 0.45))     # face at z = -3.0
		"shallow_walk", "shallow_sprint":
			# a wall 15 degrees off perpendicular: the stick is nearly head-on, the body slides slowly along it
			_box(Vector3(0, 1.5, -3.0), Vector3(12, 3, 0.5), Vector3(0, deg_to_rad(15.0), 0), Color(0.65, 0.55, 0.45))
		"corner", "corner_sprint":
			# a concave corner at (-3.25, -3.25); the player runs into it diagonally
			_box(Vector3(-5.5, 1.5, -3.5), Vector3(6, 3, 0.5), Vector3.ZERO, Color(0.65, 0.55, 0.45))
			_box(Vector3(-3.5, 1.5, -5.5), Vector3(0.5, 3, 6), Vector3.ZERO, Color(0.6, 0.5, 0.42))
			start = Vector3(0, 0, 0)
			yaw = deg_to_rad(45.0)
		"oblique":
			# a wall running along a 45 degree line; the player heads straight -Z into it
			_box(Vector3(0, 1.5, -3.0), Vector3(8, 3, 0.5), Vector3(0, deg_to_rad(45.0), 0), Color(0.65, 0.55, 0.45))
		"beam":
			_box(Vector3(0, 0.95, -4.0), Vector3(0.2, 0.2, 14), Vector3.ZERO, Color(0.6, 0.45, 0.3))
			start = Vector3(0, 1.05, 2.0)
		"slope20", "slope42", "slope45", "slope50", "slide42":
			var deg := float(_case.substr(5))
			var r := deg_to_rad(deg)
			# a ramp rising toward -Z, its low edge at z = 0
			var len := 12.0
			var b := _box(Vector3(0, sin(r) * len * 0.5 - 0.15, -cos(r) * len * 0.5), Vector3(8, 0.3, len), Vector3(r, 0, 0), Color(0.5, 0.45, 0.4))
			b.rotation.x = r
			if _case == "slide42":
				start = Vector3(0, tan(r) * 3.0 + 0.05, -3.0)      # standing on the ramp, no input: it should slide
		"stairs":
			for i in 8:
				_box(Vector3(0, 0.1 + i * 0.2, -2.0 - i * 0.4), Vector3(4, 0.2, 0.4), Vector3.ZERO, Color(0.55, 0.55, 0.5))
				_box(Vector3(0, 0.0 + i * 0.2 * 0.5, -2.0 - i * 0.4), Vector3(4, i * 0.2 + 0.2, 0.4), Vector3.ZERO, Color(0.55, 0.55, 0.5))
		"ledge":
			# a platform 2 m up with its edge at z = -1; the floor is 2 m below
			_box(Vector3(0, 1.0, 3.0), Vector3(30, 2, 8), Vector3.ZERO, Color(0.55, 0.5, 0.45))
			start = Vector3(0, 2.0, 3.0)
		"vault_run":
			_box(Vector3(0, 0.45, -4.0), Vector3(4, 0.9, 0.3), Vector3.ZERO, Color(0.6, 0.45, 0.3))
			start = Vector3(0, 0, 4.0)
	if not OS.get_cmdline_user_args().has("--child"):
		Life.life_path.set_age(Life.ADULT_AGE, WorldSim.day, WorldSim.time_of_day)      # the game starts the hero as a 0.58 scale child
	_p = PlayerScript.new()
	add_child(_p)
	_p.global_position = start + Vector3(0, BASE, 0)
	_p.view = 1
	if _p.has_method("set_camera"):
		_p.call("set_camera", yaw, 0.0)
	if _baseline:
		_p.set("_wall", NullWall.new())
		_p.set("_ground", NullGround.new())
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0]
	_sk.skeleton_updated.connect(_on_skeleton_updated)
	var hd := _sk.find_bone("Head")
	print("BODY head_y=%.2f shoulder_const=%s pivot=%s" % [(_sk.global_transform * _sk.get_bone_global_pose(hd).origin).y - BASE, str(_p.get("SHOULDER_HEIGHT")), str(_p.get("_pivot"))])
	var ua := _sk.find_bone("upperarm_l")
	var la := _sk.find_bone("lowerarm_l")
	var ha := _sk.find_bone("hand_l")
	var xf := _sk.global_transform
	print("ARM upper=%.3f lower=%.3f total=%.3f  scale=%.3f body_scale=%s" % [(xf * _sk.get_bone_global_rest(ua).origin).distance_to(xf * _sk.get_bone_global_rest(la).origin),
			(xf * _sk.get_bone_global_rest(la).origin).distance_to(xf * _sk.get_bone_global_rest(ha).origin),
			(xf * _sk.get_bone_global_rest(ua).origin).distance_to(xf * _sk.get_bone_global_rest(ha).origin), _p.global_basis.get_scale().y, str(_p.get("_model").scale)])
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 42
	_cam.current = true
	_place_camera()
	Input.action_release("move_forward")
	Input.action_release("sprint")


func _place_camera() -> void:
	var pp := _p.global_position
	match _case:
		"corner", "corner_sprint":
			_cam.global_position = Vector3(4.0, BASE + 2.2, 4.0)
			_cam.look_at(Vector3(-2.0, BASE + 1.0, -2.0))
		"oblique", "shallow_walk", "shallow_sprint":
			_cam.global_position = Vector3(pp.x + 5.0, BASE + 1.4, pp.z - 1.0)
			_cam.look_at(Vector3(0, BASE + 1.0, pp.z - 2.0))
		"slope20", "slope42", "slope45", "slope50", "slide42", "stairs", "ledge", "vault_run", "beam":
			_cam.global_position = Vector3(5.5, pp.y + 1.5, pp.z - 1.5)
			_cam.look_at(Vector3(0, pp.y + 0.9, pp.z - 1.5))
		_:
			_cam.global_position = Vector3(3.6, BASE + 1.3, -1.6)
			_cam.look_at(Vector3(0, BASE + 1.0, -2.0))


func _physics_process(delta: float) -> void:
	_t += delta
	var fwd := false
	var sprint := false
	match _case:
		"head_walk", "oblique", "ledge", "stairs", "beam", "slope20", "shallow_walk", "corner":
			fwd = _t > 0.5 and _t < 4.5
		"slope42", "slope45", "slope50":
			fwd = _t > 0.5 and _t < 4.5
		"hold", "bench":
			fwd = _t > 0.5
		"head_sprint", "shallow_sprint", "corner_sprint":
			fwd = _t > 0.5 and _t < 4.0
			sprint = true
		"vault_run":
			fwd = _t > 0.3
			sprint = true
	if fwd:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")
	if sprint:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	_place_camera()
	if _case == "bench" and _t > 6.0 and not _benched:
		_benched = true
		_bench()
	var kind := String(_p.get("_loco_kind"))
	if kind == "start" and _last_kind != "start":
		_starts += 1
	_last_kind = kind
	# hand-to-wall distance while braced: the hand bones after the modifiers ran (Skeleton3D.skeleton_updated)
	if _case == "hold" or _case == "head_walk" or _case == "head_sprint" or _case == "bench":
		var dl := _hand_w[0].z - _wall_z
		var dr := _hand_w[1].z - _wall_z
		if str(_p.get("_wall").state) == "brace" and not _baseline:
			_min_hand = minf(_min_hand, minf(absf(dl), absf(dr)))
			_hand_log = "dl=%.3f dr=%.3f hy=(%.2f,%.2f)" % [dl, dr, _hand_w[0].y - BASE, _hand_w[1].y - BASE]
	_log_t += delta
	if _log_t >= 0.1:
		_log_t = 0.0
		var v: Vector3 = _p.get_real_velocity()
		var st := String(_p.get("_wall").state) if not _baseline else "off"
		print("M t=%.1f pos=(%.2f,%.2f,%.2f) v=%.2f wall=%s starts=%d kind=%s loco=%.2f floor=%s hand_min=%.3f shown=%.2f mv=%.2f %s" % [_t, _p.global_position.x,
				_p.global_position.y, _p.global_position.z, Vector2(v.x, v.z).length(), st, _starts, kind,
				float(_p.get("_loco_transition_time")), _p.is_on_floor(), _min_hand, float(_p.get("_animator").call("shown_speed")), float(_p.get("_move_speed")), _dbg()])


## Cost of the two per-frame hooks in the worst case (braced against a wall: collision list + ray + hand rays + IK weights).
func _bench() -> void:
	var w: RefCounted = _p.get("_wall")
	var g: RefCounted = _p.get("_ground")
	var dir := Vector3(0, 0, -1)
	var n := 3000
	var t0 := Time.get_ticks_usec()
	for i in n:
		w.call("tick", _p, dir, 1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	for i in n:
		_p.velocity = g.call("pre_move", _p, dir, 1.0 / 60.0, false, w)
	var t2 := Time.get_ticks_usec()
	print("BENCH wall_tick %.1f us  ground_pre_move %.1f us  (state=%s)" % [float(t1 - t0) / n, float(t2 - t1) / n, String(w.get("state"))])


func _dbg() -> String:
	if _baseline:
		return _hand_log
	var w: RefCounted = _p.get("_wall")
	var rig: Node = _p.get("_rig")
	var ik_info := ""
	var ax: Vector3 = rig.call("shoulder_axis")
	var tp := ""
	var trav: Variant = _p.get("_trav")
	if trav != null and bool(trav.call("busy")):
		tp = " TRAV=%s rate=%.2f" % [str((trav.get("plan") as Dictionary).get("clip", "?")), float((trav.get("plan") as Dictionary).get("rate", 0.0))]
	return tp + " cool=%.2f byaw=%.2f shax=(%.2f,%.2f) head_y=%.2f %s w=(%.2f,%.2f) arms=%s gap=%.2f push=%.2f%s" % [float(w.get("_cool")), float(w.get("_brace_yaw")), ax.x, ax.z, _head_y, _hand_log, w.get("_w")[0], w.get("_w")[1], str(rig.get("_arms_state")), float(w.get("gap")), float(w.get("push")), ik_info]


func _on_skeleton_updated() -> void:
	var hl := _sk.find_bone("hand_l")
	var hr := _sk.find_bone("hand_r")
	_hand_w[0] = (_sk.global_transform * _sk.get_bone_global_pose(hl)).origin
	_hand_w[1] = (_sk.global_transform * _sk.get_bone_global_pose(hr)).origin
	_head_y = (_sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("Head"))).origin.y - BASE
