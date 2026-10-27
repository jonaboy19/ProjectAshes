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


static func _tex_mat(id: String, scale: float) -> StandardMaterial3D:
	var base := "res://assets/cc0/textures/%s/%s_" % [id, id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.roughness_texture = load(base + "arm_2k.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Variant) -> void:
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
	if col is Material:
		mi.material_override = col
	else:
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
	var dirt := StandardMaterial3D.new()
	var dp := "res://assets/incoming/polyhaven/textures/dirt/dirt_"
	dirt.albedo_texture = load(dp + "diff_2k.jpg")
	dirt.normal_enabled = true
	dirt.normal_texture = load(dp + "nor_gl_2k.jpg")
	dirt.uv1_triplanar = true
	dirt.uv1_scale = Vector3.ONE * 0.4
	_box(r3, Vector3(60, 1, 60), Vector3(0, BASE - 0.5, 0), dirt)
	# hayloft-like platform: deck at H, its front edge at z = 0 (the ladder leans on it), the climber comes from -z
	var deck := _tex_mat("weathered_brown_planks", 0.8)
	var posts := _tex_mat("old_planks_02", 1.2)
	_box(r3, Vector3(4, 0.12, 3), Vector3(0, BASE + H - 0.06, 1.5), deck)
	_box(r3, Vector3(4.1, 0.22, 0.2), Vector3(0, BASE + H - 0.2, 0.05), posts)      # edge beam
	for px in [-1.9, 1.9]:
		for pz in [0.1, 2.9]:
			_box(r3, Vector3(0.22, H, 0.22), Vector3(px, BASE + H * 0.5, pz), posts)
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
			var skl: Skeleton3D = _p.find_children("*", "Skeleton3D", true, false)[0]
			var hips := skl.global_transform * skl.get_bone_global_pose(skl.find_bone("pelvis")).origin
			var hl := skl.global_transform * skl.get_bone_global_pose(skl.find_bone("hand_l")).origin
			var hr := skl.global_transform * skl.get_bone_global_pose(skl.find_bone("hand_r")).origin
			print("LADPOS cap_x=%.3f hips_x=%.3f hand_l=(%.2f,%.2f) hand_r=(%.2f,%.2f) model_yaw=%.2f" % [_p.global_position.x, hips.x, hl.x, hl.y - BASE, hr.x, hr.y - BASE, (_p.get("_model") as Node3D).rotation.y])
			print("LADDBG y=%.2f vis=%s pitch=%.2f pcam=%s pivot=%s" % [_p.global_position.y - BASE, str((_p.get("_model") as Node3D).visible), float(_p.get("_pitch")), str(pc.global_position - Vector3(0, BASE, 0)) if pc else "-", str((_p.get("_pivot") as Node3D).global_position - Vector3(0, BASE, 0))])      # the player's own camera rig takes over during traversal otherwise
		if shot == 0:
			_cam.global_position = Vector3(3.8, BASE + 1.9, -2.6)    # fixed side / 3/4-behind camera (never inside the deck)
			_cam.look_at(Vector3(0, clampf(_p.global_position.y + 1.0, BASE + 1.0, BASE + H + 0.8), -0.2))
		else:
			_cam.global_position = Vector3(2.6, BASE + H + 2.0, -2.8)
			_cam.look_at(_p.global_position + Vector3(0, 1.0, 0))
