extends Node3D
## F10 Soulbeast capture harness (standalone, no world boot). Four scenes, one frame each, tiled into a 2x2 sheet:
## wary at the den, curious sniff, following in Thornfield, fighting beside the player.
##   xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan \
##       res://tools_qa/soulbeast/soulbeast_standalone.tscn -- --out=/path/soulbeast.png

const Beast := preload("res://scripts/actors/soulbeast.gd")
const Director := preload("res://scripts/world/soulbeast_director.gd")
const Brain := preload("res://scripts/actors/soulbeast_brain.gd")

class FakePlayer extends Node3D:
	var velocity := Vector3.ZERO
	var crouching := false
	var health := 120
	var dead := false
	var weapon_drawn := false
	var blocking := false
	func noise_radius() -> float:
		return 4.0 if crouching else (16.0 if velocity.length() > 4.5 else 10.0)
	func take_damage(_a: int, _f: Node = null, _k := Vector3.ZERO) -> void:
		pass

var out := "/tmp/soulbeast.png"
var cam: Camera3D
var stage: Node3D
var player: FakePlayer
var beast: Node3D
var den := Vector2.ZERO
var shots: Array[Image] = []
var step := 0
var t := 0.0
var _foe: Node3D
var _capturing := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	WorldGen.setup(2024)
	var th := Director.thornfield()
	den = Director.find_den(th["pos"], float(th["radius"]))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_begin(0)


func _clear() -> void:
	if stage:
		stage.queue_free()
	stage = Node3D.new()
	add_child(stage)
	player = null
	beast = null
	_foe = null


func _ground(c: Vector3) -> void:
	var m := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(80, 80)
	m.mesh = p
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.38, 0.22)
	m.material_override = mat
	stage.add_child(m)
	m.global_position = c


func _player_at(p: Vector3, yaw := 0.0) -> void:
	player = FakePlayer.new()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = p
	player.rotation.y = yaw
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.7
	body.mesh = cap
	body.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.2, 0.15)
	body.material_override = mat
	player.add_child(body)


func _beast_at(pos: Vector3, trust: float, bonded := false) -> void:
	beast = Beast.new()
	stage.add_child(beast)
	beast.setup(Vector2(pos.x, pos.z))
	beast.brain.hour = 22.0
	beast.brain.trust = trust
	beast.global_position = pos
	if bonded:
		beast.brain.trust = 90.0
		beast.bond_with(player, false)


func _begin(i: int) -> void:
	step = i
	t = 0.0
	_clear()
	var h := WorldGen.height(den.x, den.y)
	var base := Vector3(den.x, h, den.y)
	_ground(base)
	match i:
		0:   # wary at the den: a stranger stands off, the beast growls
			_player_at(base + Vector3(0, 0, 9.0), PI)
			_beast_at(base, 5.0)
			cam.global_position = base + Vector3(7, 2.2, 4.5)
			cam.look_at(base + Vector3(0, 0.7, 4.0))
		1:   # curious sniff
			_player_at(base + Vector3(0, 0, 2.6), PI)
			player.crouching = true
			_beast_at(base + Vector3(0, 0, 0.5), 35.0)
			cam.global_position = base + Vector3(4.5, 1.6, 3.0)
			cam.look_at(base + Vector3(0, 0.6, 1.5))
		2:   # following in Thornfield
			var th := Director.thornfield()
			var c: Vector2 = th["pos"]
			var b3 := Vector3(c.x, WorldGen.height(c.x, c.y), c.y)
			_ground(b3)
			_player_at(b3, 0.0)
			player.velocity = Vector3(0, 0, 2.4)
			_beast_at(b3 + Vector3(-1.6, 0, -2.4), 90.0, true)
			for k in 5:
				var box := MeshInstance3D.new()
				box.mesh = BoxMesh.new()
				box.scale = Vector3(5, 4, 5)
				var bm := StandardMaterial3D.new()
				bm.albedo_color = Color(0.55, 0.42, 0.3)
				box.material_override = bm
				stage.add_child(box)
				box.global_position = b3 + Vector3(-12 if k % 2 == 0 else 12, 2, 6.0 + k * 7.0)
			cam.global_position = b3 + Vector3(5.5, 2.4, -6.5)
			cam.look_at(b3 + Vector3(0, 0.9, 0))
		3:   # fighting beside the player
			_player_at(base, 0.0)
			_beast_at(base + Vector3(-1.8, 0, -0.8), 90.0, true)
			var Wolf := load("res://scripts/actors/wolf.gd")
			_foe = Wolf.new()
			_foe.home = Vector2(base.x, base.z + 6.0)
			stage.add_child(_foe)
			_foe.global_position = base + Vector3(0.5, 0, 4.0)
			cam.global_position = base + Vector3(6.0, 2.4, 1.0)
			cam.look_at(base + Vector3(-0.5, 0.8, 2.0))


func _physics_process(delta: float) -> void:
	t += delta
	if player and step == 2:
		player.global_position += Vector3(0, 0, 2.4) * delta
		player.global_position.y = WorldGen.height(player.global_position.x, player.global_position.z)
		cam.global_position += Vector3(0, 0, 2.4) * delta
	if step == 3 and beast and is_instance_valid(_foe):
		_foe.set("_provoked", 15.0)
	var dur: float = [3.5, 2.3, 6.0, 4.5][step]
	if t >= dur and not _capturing:
		_capturing = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img:
			img.resize(640, 360)
			shots.append(img)
		print("frame ", step, " state=", Brain.STATE_NAMES[beast.brain.state] if beast else "-")
		_capturing = false
		if step < 3:
			_begin(step + 1)
		else:
			_finish()
			set_physics_process(false)


func _finish() -> void:
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
