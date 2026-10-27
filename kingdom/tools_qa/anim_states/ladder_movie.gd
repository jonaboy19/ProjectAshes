extends SceneTree
## Ladder gate clip (ashes-aaa-gate ref 02): the adult player climbs a 3.2 m ladder onto a platform through the real Ladder
## interaction and Traversal driver, filmed from the side and 3/4 behind. Movie Maker:
##   godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie out.avi -s res://tools_qa/anim_states/ladder_movie.gd
const BASE := 600.0
const H := 3.2
var _p: CharacterBody3D
var _cam: Camera3D
var _lad: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	b.add_child(mi)
	parent.add_child(b)
	b.position = pos


func _run() -> void:
	var r3 := Node3D.new()
	root.add_child(r3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.78, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	r3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	r3.add_child(sun)
	_box(r3, Vector3(60, 1, 60), Vector3(0, BASE - 0.5, 0), Color(0.45, 0.42, 0.35))
	# hayloft-like platform: deck at H, its front edge at z = 0 (the ladder leans on it), the climber comes from -z
	_box(r3, Vector3(4, 0.15, 3), Vector3(0, BASE + H - 0.075, 1.5), Color(0.42, 0.3, 0.18))
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, -2.5)
	_p.set("view", 1)
	for i in 20:
		await physics_frame
	var life: Node = root.get_node("Life")
	life.life_path.set_age(16, root.get_node("WorldSim").day, 10.0)
	_p.call("apply_age")
	_lad = (load("res://scripts/interaction/kinds/ladder.gd") as GDScript).call("spawn", r3,
			Vector3(0, BASE, -0.05), Vector3(0, BASE + H + 0.05, 0.6), "Gate Ladder")
	_cam = Camera3D.new()
	r3.add_child(_cam)
	_cam.current = true
	_cam.fov = 42
	for i in 30:
		await physics_frame
	Input.action_press("move_forward")
	await _film(1.2, 0)
	Input.action_release("move_forward")
	await _film(0.3, 0)
	_lad.call("climb", _p, true)
	await _film(12.0, 0)
	await _film(1.5, 1)
	quit()


func _film(secs: float, shot: int) -> void:
	var t := 0.0
	while t < secs:
		await process_frame
		t += 1.0 / 30.0
		_cam.make_current()
		if OS.has_environment("LAD_DBG") and Engine.get_process_frames() % 6 == 0:
			var pc: Camera3D = _p.get("camera")
			print("LADDBG y=%.2f vis=%s pitch=%.2f pcam=%s pivot=%s" % [_p.global_position.y - BASE, str((_p.get("_model") as Node3D).visible), float(_p.get("_pitch")), str(pc.global_position - Vector3(0, BASE, 0)) if pc else "-", str((_p.get("_pivot") as Node3D).global_position - Vector3(0, BASE, 0))])      # the player's own camera rig takes over during traversal otherwise
		if shot == 0:
			_cam.global_position = Vector3(3.8, BASE + 1.9, -2.6)    # fixed side / 3/4-behind camera (never inside the deck)
			_cam.look_at(Vector3(0, clampf(_p.global_position.y + 1.0, BASE + 1.0, BASE + H + 0.8), -0.2))
		else:
			_cam.global_position = Vector3(2.6, BASE + H + 2.0, -2.8)
			_cam.look_at(_p.global_position + Vector3(0, 1.0, 0))
