extends Node3D
## Aramori region: builds the world, spawns Sugo and the villagers, and runs the
## story beats of the vertical slice (fence → bells → silence → examination).
##
## Screenshot mode (for previews): pass user args after `--`, e.g.
##   godot --path game -- --shot=gameplay --out=/tmp/shot.png

const BEAST_COUNT := 3

var terrain := Terrain.new()
var player: Player
var hud: HUD
var bells: Array[Node3D] = []
var rift_tear: MeshInstance3D
var _beasts_defeated := 0
var _bell_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
	_rng.seed = 1337
	_build_environment()
	_build_terrain()
	_build_village()
	_build_wilds()
	_spawn_player()
	_spawn_villagers()
	_spawn_beasts()
	_build_triggers()
	hud = HUD.new(player)
	add_child(hud)
	_bell_player = AudioStreamPlayer.new()
	_bell_player.stream = _make_bell_sound()
	add_child(_bell_player)
	Quests.step_started.connect(_on_step_started)

	var args := _user_args()
	if args.has("shot"):
		_screenshot(args["shot"], args.get("out", "user://shot.png"))
		return
	hud.play_title()
	await get_tree().create_timer(3.4).timeout
	Dialogue.start("intro")


func _process(delta: float) -> void:
	_time += delta
	if rift_tear:
		rift_tear.scale = Vector3(1.0 + sin(_time * 3.0) * 0.08, 1.0 + sin(_time * 1.7) * 0.05, 1.0)


# --- World construction ----------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("5f8fc7")
	sky_mat.sky_horizon_color = Color("f2c9a0")
	sky_mat.ground_horizon_color = Color("d9b48f")
	sky_mat.ground_bottom_color = Color("6b5a4a")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7d86a8")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color("e8c9a8")
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.4
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color("ffe2bd")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_terrain() -> void:
	var mesh := terrain.build_mesh()
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = Props.mat(Color.WHITE, 0.0, true, false)
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.25, 0.55, 0.75, 0.78)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.2
	water.material_override = water_mat
	water.position = Vector3(Terrain.LAKE_CENTER.x, Terrain.WATER_LEVEL, Terrain.LAKE_CENTER.y)
	add_child(water)


func _place(node: Node3D, x: float, z: float, yaw := 0.0) -> Node3D:
	node.position = Vector3(x, terrain.height(x, z), z)
	node.rotation.y = yaw
	add_child(node)
	return node


func _build_village() -> void:
	# Bell tower at the heart of the plaza.
	var tower := _place(Props.bell_tower(), 0, 0)
	for bell in tower.get_meta("bells"):
		bells.append(bell)
	var ring := Interactable.make("Stand", 5.0)
	ring.position = Vector3(0, 0, 3.5)
	tower.add_child(ring)
	ring.interacted.connect(_on_tower_used)

	_place(Props.chapel(), -22, -12, deg_to_rad(60))
	_place(Props.well(), 9, -6)

	# Houses in a loose ring facing the plaza, leaving the south road open.
	var angles := [200.0, 225.0, 250.0, 275.0, 300.0, 330.0, 355.0, 20.0, 45.0, 130.0, 155.0, 180.0]
	for a: float in angles:
		var r := _rng.randf_range(20.0, 29.0)
		var ang := deg_to_rad(a + _rng.randf_range(-6, 6))
		var pos := Vector2(cos(ang), sin(ang)) * r
		if pos.distance_to(Vector2(-22, -12)) < 10.0:
			continue
		var yaw := atan2(-pos.x, -pos.y)
		_place(Props.house(_rng), pos.x, pos.y, yaw)

	# Market by the gate road.
	for i in 3:
		_place(Props.market_stall(_rng), -9 + i * 3.2, 13, PI)
	for p: Vector2 in [Vector2(6, 11), Vector2(7, 12.2), Vector2(-13, 9), Vector2(14, -14)]:
		_place(Props.crate(), p.x, p.y, _rng.randf() * TAU)
	for p: Vector2 in [Vector2(5, 5), Vector2(-5, 5), Vector2(5, -5), Vector2(-5, -5), Vector2(-4, 30), Vector2(4, 30)]:
		_place(Props.lantern_post(), p.x, p.y)

	# The fence that Sugo has never been beyond. Gap at the south gate.
	var segments := 110
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var mid := (a0 + a1) / 2.0
		if absf(wrapf(mid - PI / 2.0, -PI, PI)) < deg_to_rad(6.0):
			continue
		var p0 := Vector2(cos(a0), sin(a0)) * Terrain.VILLAGE_RADIUS
		var p1 := Vector2(cos(a1), sin(a1)) * Terrain.VILLAGE_RADIUS
		var seg := Props.fence_segment(p0.distance_to(p1))
		var dir := p1 - p0
		_place(seg, p0.x, p0.y, atan2(dir.x, dir.y))
		Props.add_box_collider(seg, Vector3(0.3, 1.6, p0.distance_to(p1)), Vector3(0, 0.8, p0.distance_to(p1) / 2.0))
	# Gate posts.
	for sx in [-1, 1]:
		var post := Node3D.new()
		Props.part(post, Props.box(Vector3(0.5, 3.4, 0.5)), Props.WOOD, Vector3(0, 1.7, 0))
		_place(post, sx * 4.2, Terrain.VILLAGE_RADIUS)
	var beam := Node3D.new()
	Props.part(beam, Props.box(Vector3(9.4, 0.4, 0.5)), Props.WOOD, Vector3(0, 3.3, 0))
	_place(beam, 0, Terrain.VILLAGE_RADIUS)


func _build_wilds() -> void:
	# Trees and rocks as MultiMeshes: hundreds of props for a handful of draw calls.
	var trunks: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var pine_colors: Array[Color] = []
	var oaks: Array[Transform3D] = []
	var oak_colors: Array[Color] = []
	var rocks: Array[Transform3D] = []
	var half := Terrain.SIZE / 2.0 - 8.0
	for i in 5200:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var density := terrain.tree_density(x, z)
		if _rng.randf() > density * 0.55:
			if density > 0.0 and _rng.randf() < 0.02:
				rocks.append(_basis_at(x, z, _rng.randf_range(0.6, 1.8)))
			continue
		var s := _rng.randf_range(0.8, 1.5)
		trunks.append(_basis_at(x, z, s))
		if _rng.randf() < 0.6:
			pines.append(_basis_at(x, z, s).translated_local(Vector3(0, 3.2, 0)))
			pine_colors.append(Color("3f6b45").lerp(Color("5a8a4a"), _rng.randf()))
		else:
			oaks.append(_basis_at(x, z, s).translated_local(Vector3(0, 3.3, 0)))
			oak_colors.append(Color("5f9448").lerp(Color("a3b04a"), _rng.randf() * 0.7))
	_multimesh(Props.cylinder(0.18, 0.28, 2.4, 6), Props.WOOD, trunks, [], Vector3(0, 1.2, 0))
	_multimesh(Props.cylinder(0.0, 1.5, 4.0, 7), Color.WHITE, pines, pine_colors)
	_multimesh(Props.sphere(1.6, 7, 4), Color.WHITE, oaks, oak_colors)
	_multimesh(Props.sphere(1.0, 6, 3), Props.STONE, rocks, [])

	var scar := Props.rift_scar(_rng)
	_place(scar, Terrain.RIFT_SITE.x, Terrain.RIFT_SITE.y)
	rift_tear = scar.get_meta("tear")


func _basis_at(x: float, z: float, s: float) -> Transform3D:
	var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, terrain.height(x, z) - 0.1, z))
	return t


func _multimesh(mesh: Mesh, color: Color, transforms: Array[Transform3D], colors: Array[Color], offset := Vector3.ZERO) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i].translated_local(offset))
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Props.mat(color, 0.0, mm.use_colors)
	add_child(mmi)


func _spawn_player() -> void:
	player = Player.new()
	player.position = Vector3(6, terrain.height(6, 18) + 0.2, 18)
	add_child(player)
	player.set_camera_angles(0.0, -0.3)


func _spawn_villagers() -> void:
	var people := [
		["elder", "Village Elder", Color("6b5b7a"), Color("d8d4cc"), 1.0, Vector2(-3, 6)],
		["acolyte", "Church Acolyte", Color("e8e2d4"), Color("5a3b28"), 1.0, Vector2(-17, -4)],
		["child_a", "Village Child", Color("b85c3c"), Color("2f2420"), 0.75, Vector2(3.5, 7.5)],
		["child_b", "Village Child", Color("4f7f5a"), Color("7a4a2a"), 0.72, Vector2(6, 6)],
		["child_c", "Village Child", Color("c9a247"), Color("222222"), 0.7, Vector2(-6.5, 8)],
		["mother", "Villager", Color("8a4f5f"), Color("3b2a20"), 1.0, Vector2(12, 16)],
	]
	for p: Array in people:
		var npc := NPC.create(p[0], p[1], p[2], p[3], p[4])
		var pos: Vector2 = p[5]
		_place(npc, pos.x, pos.y, atan2(-pos.x, -pos.y))


func _spawn_beasts() -> void:
	for i in BEAST_COUNT:
		var ang := TAU * i / BEAST_COUNT
		var x := Terrain.RIFT_SITE.x + cos(ang) * 8.0
		var z := Terrain.RIFT_SITE.y - 10.0 + sin(ang) * 6.0
		var beast := RiftBeast.new()
		beast.position = Vector3(x, terrain.height(x, z) + 0.3, z)
		add_child(beast)
		beast.died.connect(_on_beast_died)


func _build_triggers() -> void:
	# Stepping past the gate = "The World Beyond the Fence".
	var gate := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 8, 6)
	shape.shape = box
	gate.add_child(shape)
	gate.position = Vector3(terrain.road_x(52.0), 2, 52.0)
	add_child(gate)
	gate.body_entered.connect(func(body: Node3D) -> void:
		if body is Player and Quests.is_on_step("day_of_bells", "beyond_fence"):
			Dialogue.start("beyond_fence"))


# --- Story beats -------------------------------------------------------------------

func _on_step_started(quest_id: String, step_id: String) -> void:
	if quest_id == "day_of_bells" and step_id == "examination":
		GameState.toast("Follow the road south, past the gate, to the Rift scar.")


func _on_tower_used(_by: Node) -> void:
	if Quests.is_on_step("day_of_bells", "ring_bells"):
		_run_ceremony()
	elif GameState.get_flag("no_bell_rang"):
		GameState.toast("The thirteenth bell hangs silent.")
	else:
		GameState.toast("Thirteen bells. Each one waits for a child's name.")


## PLACEHOLDER staging of Chapters 2–3 from their titles: the bells ring for the
## other children, then fall silent for Sugo. Replace with the approved scene.
func _run_ceremony() -> void:
	player.input_locked = true
	hud.set_controls_visible(false)
	player.global_position = Vector3(0, terrain.height(0, 7) + 0.2, 7)
	player.face_direction(PI)
	player.set_camera_angles(0.0, -0.05)
	GameState.toast("The Ceremony of the Thirteen Bells begins.")
	await get_tree().create_timer(2.0).timeout
	for i in 12:
		_ring_bell(bells[i])
		await get_tree().create_timer(0.55).timeout
	GameState.toast("One by one, the bells answer the children of Aramori.")
	await get_tree().create_timer(2.6).timeout
	GameState.toast("Sugo steps forward.")
	await get_tree().create_timer(2.4).timeout
	GameState.toast("...")
	await get_tree().create_timer(2.4).timeout
	GameState.toast("No bell rang.")
	await get_tree().create_timer(3.0).timeout
	GameState.set_flag("no_bell_rang")
	player.input_locked = false
	hud.set_controls_visible(true)
	Quests.advance("day_of_bells", "ring_bells")


func _ring_bell(bell: Node3D) -> void:
	var glow: StandardMaterial3D = (bell.get_meta("mesh") as MeshInstance3D).material_override
	var tween := create_tween().set_parallel()
	tween.tween_property(bell, "rotation:z", 0.5, 0.15)
	tween.tween_property(glow, "emission_energy_multiplier", 1.2, 0.15)
	tween.chain().tween_property(bell, "rotation:z", -0.35, 0.3)
	tween.chain().tween_property(bell, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC)
	_bell_player.pitch_scale = _rng.randf_range(0.85, 1.25)
	_bell_player.play()


func _on_beast_died(_beast: RiftBeast) -> void:
	if not Quests.is_on_step("day_of_bells", "examination"):
		GameState.toast("The beast dissolves into violet ash.")
		return
	_beasts_defeated += 1
	if _beasts_defeated >= BEAST_COUNT:
		Quests.advance("day_of_bells", "examination")
		GameState.toast("The Examination is passed. The road beyond Aramori opens.")
	else:
		GameState.toast("Rift beast defeated (%d/%d)" % [_beasts_defeated, BEAST_COUNT])


# --- Audio ---------------------------------------------------------------------------

## Synthesised bronze bell: a few inharmonic partials with exponential decay.
func _make_bell_sound() -> AudioStreamWAV:
	var rate := 22050
	var length := int(rate * 2.2)
	var data := PackedByteArray()
	data.resize(length * 2)
	var partials := [[1.0, 1.0], [2.0, 0.6], [2.4, 0.4], [3.0, 0.25], [4.2, 0.2]]
	for i in length:
		var t := float(i) / rate
		var s := 0.0
		for p: Array in partials:
			s += sin(TAU * 440.0 * p[0] * t) * p[1] * exp(-t * (1.5 + p[0]))
		data.encode_s16(i * 2, int(clampf(s * 0.3, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


# --- Preview screenshots ---------------------------------------------------------------

func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _screenshot(shot: String, path: String) -> void:
	hud.hide_title()
	match shot:
		"gameplay":
			Quests.start("day_of_bells")
			Quests.advance("day_of_bells", "beyond_fence")
			player.global_position = Vector3(3.0, terrain.height(3.0, 12) + 0.1, 12)
			player.set_camera_angles(deg_to_rad(8), -0.12)
			player.face_direction(PI + 0.3)
		"dialogue":
			Quests.start("day_of_bells")
			Quests.advance("day_of_bells", "beyond_fence")
			player.global_position = Vector3(-2.2, terrain.height(-2.2, 8.6) + 0.1, 8.6)
			player.set_camera_angles(deg_to_rad(20), -0.22)
			player.face_direction(PI)
			await get_tree().process_frame
			Dialogue.start_for_npc("elder")
		"beyond":
			Quests.start("day_of_bells")
			for step in ["beyond_fence", "return_elder", "ring_bells", "after_silence"]:
				Quests.advance("day_of_bells", step)
			var z := Terrain.RIFT_SITE.y - 24.0
			player.global_position = Vector3(terrain.road_x(z), terrain.height(terrain.road_x(z), z) + 0.1, z)
			player.set_camera_angles(PI + 0.15, -0.22)
			player.face_direction(0.1)
		"ceremony":
			Quests.start("day_of_bells")
			Quests.advance("day_of_bells", "beyond_fence")
			Quests.advance("day_of_bells", "return_elder")
			player.global_position = Vector3(0, terrain.height(0, 7) + 0.1, 7)
			player.face_direction(PI)
			player.set_camera_angles(0.0, 0.18)
			hud.set_controls_visible(false)
			for i in 12:
				(bells[i].get_meta("mesh") as MeshInstance3D).material_override.emission_energy_multiplier = 1.0
				bells[i].rotation.z = 0.3 if i % 2 == 0 else -0.25
			hud.show_toast("Sugo steps forward... No bell rang.", 30.0)
		"overview":
			hud.visible = false
			player.visible = false
			(get_node("WorldEnvironment") as WorldEnvironment).environment.fog_enabled = false
			var cam := Camera3D.new()
			cam.far = 800.0
			cam.fov = 55.0
			add_child(cam)
			cam.global_position = Vector3(70, 75, 95)
			cam.look_at(Vector3(0, 0, 10))
			cam.current = true
		"title":
			hud.play_title(60.0)
	for i in 40:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot: ", path)
	get_tree().quit()
