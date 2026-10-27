extends SceneTree
## Guard-turn review (lock-on pivot): the player locks a bandit standing behind him; side camera. Movie Maker:
##   godot --path kingdom --fixed-fps 30 --write-movie out.avi -s res://tools_qa/anim_states/guard_turn_movie.gd
const BASE := 600.0
var _p
var _cam: Camera3D
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var r3 := Node3D.new()
	root.add_child(r3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	r3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	r3.add_child(sun)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	fb.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	mi.mesh = pm
	mi.position.y = 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.42, 0.36)
	mi.material_override = m
	fb.add_child(mi)
	r3.add_child(fb)
	fb.position = Vector3(0, BASE - 0.5, 0)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	_p.view = 1
	var Soldier = load("res://scripts/army/soldier.gd")
	var foe: Node3D = Soldier.call("create", 1, "Bandit", "Bandit", ["1H_Sword", "Round_Shield"] as Array[String])
	r3.add_child(foe)
	foe.global_position = Vector3(0.6, BASE, -3.0)    # behind (the player faces +Z)
	foe.set_process(false)
	foe.set_physics_process(false)
	_cam = Camera3D.new()
	r3.add_child(_cam)
	for i in 30:
		await physics_frame
	_p.set("sheathed", false)
	_p.call("set_sheathed", false, true)
	_p.call("_set_lock", foe)
	_cam.current = true
	var t := 0.0
	while t < 3.0:
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		var pp: Vector3 = _p.global_position
		_cam.fov = 38.0
		_cam.global_position = pp + Vector3(5.0, 0.8, 0.0)
		_cam.look_at(pp + Vector3(0, 0.6, 0))
		_cam.make_current()
		if t < 0.5:
			print("GT t=%.2f clip=%s yaw=%.1f strafing=%s style=%s ms=%.2f turnclip=%s floor=%s" % [t, _p.get("_gturn_clip"), rad_to_deg(_p.get("_model").rotation.y), _p.get("_strafing"), _p.get("combat_style"), _p.get("_move_speed"), _p.get("_turn_clip"), _p.is_on_floor()])
	quit()
