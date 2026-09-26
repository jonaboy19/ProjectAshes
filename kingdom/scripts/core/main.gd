extends Control
## Entry point. Renders the 3D world into a SubViewport with modern lighting
## (Forward+: SDFGI, SSAO, SSIL, volumetric fog, glow). An optional retro mode
## (--pixel) renders at 1/PIXEL_SCALE with a colour-quantising shader instead.
## The UI is drawn on top at full resolution. Also owns the day/night cycle and the early-game loop:
## enlist -> lead a militia -> clear raider camps -> rise in rank.
##
## Preview screenshots: godot --path kingdom -- --shot=explore --out=/tmp/x.png
## (shots: explore, first, town, command, battle, castle)

const PIXEL_SCALE := 3
## Retro pixel look; off by default, enable with the --pixel launch argument.
var pixel_mode := false
const HOME_SPAWN := Vector2(2, 4.5)
const FIRST_CAMP := Vector2(190, 120)

var viewport: SubViewport
var world: Node3D
var baker: ImpostorBaker
var terrain: TerrainStreamer
var water: WaterStreamer
var settlements: SettlementBuilder
var population: PopulationLOD
var frontier: FrontierPresence
var player: Player
var hud: HUD
var army: Squad
var raiders: Squad
var captain: Captain
var services: VillageServices
var sun: DirectionalLight3D
var env: Environment
var _status_timer := 0.0
var _raids_cleared := 0


func _ready() -> void:
	pixel_mode = _user_args().has("pixel")
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if pixel_mode:
		container.stretch_shrink = PIXEL_SCALE
		container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var post := ShaderMaterial.new()
		post.shader = load("res://shaders/pixel_post.gdshader")
		post.set_shader_parameter("undo_double_srgb", RenderingServer.get_current_rendering_method() == "gl_compatibility")
		container.material = post
	add_child(container)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)

	baker = ImpostorBaker.new()
	baker.add_to_group("impostor_baker")
	add_child(baker)

	_build_environment()
	player = Player.new()
	hud = HUD.new(player)
	add_child(hud)

	hud.set_loading_text("Painting sprites...")
	await get_tree().process_frame
	await baker.bake("soldier", "Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"])
	await baker.bake("raider", "Barbarian", ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"])
	for look: String in PopulationLOD.LOOK_MODEL:
		var model: Array = PopulationLOD.LOOK_MODEL[look]
		var keep: Array[String] = []
		keep.assign(model[1])
		await baker.bake(look, model[0], keep, "Walking_A")

	hud.set_loading_text("Raising the land...")
	await get_tree().process_frame
	terrain = TerrainStreamer.new()
	world.add_child(terrain)
	water = WaterStreamer.new()
	world.add_child(water)
	settlements = SettlementBuilder.new()
	world.add_child(settlements)
	population = PopulationLOD.new()
	world.add_child(population)
	population.setup(baker)
	frontier = FrontierPresence.new()
	world.add_child(frontier)
	Frontier.frontier_event.connect(func(text: String, _pos: Vector2) -> void: Game.say(text))
	var spawn := Vector3(HOME_SPAWN.x, WorldGen.height(HOME_SPAWN.x, HOME_SPAWN.y) + 0.5, HOME_SPAWN.y)
	terrain.focus = spawn
	settlements.focus = spawn
	terrain.view_radius = 2
	terrain.build_all_now()
	terrain.view_radius = 4
	settlements.update_now()

	world.add_child(player)
	player.global_position = spawn
	player.spawn_point = spawn
	player.set_camera(PI * 0.15, -0.3)

	captain = Captain.new()
	world.add_child(captain)
	captain.global_position = Vector3(-7, WorldGen.height(-7, 3), 3)
	captain.recruit_requested.connect(_recruit)
	Life.player = player
	services = VillageServices.new()
	services.setup(hud, captain, func() -> int: return army.alive(), _recruit)
	world.add_child(services)

	army = Squad.new().setup(0, "soldier", "Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"])
	army.leader = player
	army.order = Squad.Order.FOLLOW
	world.add_child(army)
	_spawn_raiders(FIRST_CAMP, 12)

	hud.hide_loading()
	var args := _user_args()
	if args.has("shot"):
		_screenshot(args["shot"], args.get("out", "user://shot.png"))
	elif args.has("demo"):
		_run_demo()
	else:
		Game.say("Ashford. The Guard is hiring: see the Captain, or read the notice board by the well.")


func _process(delta: float) -> void:
	if player == null or not player.is_inside_tree():
		return
	var focus := player.global_position
	terrain.focus = focus
	water.focus = focus
	settlements.focus = focus
	population.focus = focus
	frontier.focus = focus
	terrain.view_radius = 5 if player.view == Player.View.COMMAND else 4
	_update_daylight()
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.2
		var perf := "%d fps · %d chunks · %d people nearby (%d full / %d sprites) · %d soldiers" % [
			Engine.get_frames_per_second(), terrain.loaded_count(), population.full_count + population.sprite_count,
			population.full_count, population.sprite_count, get_tree().get_nodes_in_group("combatant").size()]
		hud.update_status(army.alive(), ["Follow", "Hold", "Charge"][army.order], player.nearest_interactable(), perf)
		hud.update_danger(Frontier.threat_at(Vector2(focus.x, focus.z)))
		_update_mood()


## Music follows the situation: battle > night > town > wilderness.
func _update_mood() -> void:
	Audio.listener = player.camera
	var p := player.global_position
	for enemy in get_tree().get_nodes_in_group("team1"):
		if (enemy as Node3D).global_position.distance_to(p) < 45.0:
			Audio.set_mood("battle")
			return
	var t := WorldSim.time_of_day
	if t < 5.5 or t >= 21.0:
		Audio.set_mood("night")
		return
	var near := WorldGen.nearest_settlement(Vector2(p.x, p.z))
	var in_town: bool = not near.is_empty() and Vector2(p.x, p.z).distance_to(near["pos"]) < near["radius"] * 1.3
	Audio.set_mood("town" if in_town else "wild")


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("attack"):
		player.attack()
	elif event.is_action_pressed("dodge"):
		player.dodge()
	elif event.is_action_pressed("view_cycle"):
		player.cycle_first_third()
	elif event.is_action_pressed("zoom_out"):
		player.zoom(1)
	elif event.is_action_pressed("zoom_in"):
		player.zoom(-1)
	elif event.is_action_pressed("interact"):
		if hud.is_menu_open():
			hud.close_menu()
			return
		var target := player.nearest_interactable()
		if target is Captain:
			hud.show_menu(services.captain_menu)
		elif target is Station:
			hud.show_menu((target as Station).open)
	elif event.is_action_pressed("journal"):
		if hud.is_menu_open():
			hud.close_menu()
		else:
			hud.show_menu(services.pack_menu)
	elif event.is_action_pressed("eat"):
		var food := Life.best_food()
		Game.say(Life.use_item(food) if food != "" else "You have nothing to eat.")
	elif event.is_action_pressed("quick_save"):
		Game.say("Game saved." if Life.save_game() else "Could not save.")
	elif event.is_action_pressed("quick_load"):
		Game.say("Game loaded." if Life.load_game() else "No save found.")
	elif event.is_action_pressed("order_follow"):
		army.command(Squad.Order.FOLLOW)
		Game.say("Form up on me!")
	elif event.is_action_pressed("order_hold"):
		army.command(Squad.Order.HOLD)
		Game.say("Hold this ground!")
	elif event.is_action_pressed("order_charge"):
		army.command(Squad.Order.CHARGE)
		Game.say("CHARGE!")


func _recruit(count: int) -> void:
	army.add_soldiers(count, player.global_position - player.forward() * 4.0)


func _spawn_raiders(where: Vector2, count: int) -> void:
	var base := Vector3(where.x, WorldGen.height(where.x, where.y), where.y)
	var camp := Node3D.new()
	camp.name = "RaiderCamp"
	world.add_child(camp)
	for i in 4:
		var tent := Assets.medieval("tent", 5.0)
		var a := TAU * i / 4.0
		var p := where + Vector2(cos(a), sin(a)) * 9.0
		tent.position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
		tent.rotation.y = -a
		camp.add_child(tent)
	var rack := Assets.medieval("weaponrack", 3.0)
	rack.position = base
	camp.add_child(rack)
	raiders = Squad.new().setup(1, "raider", "Barbarian", ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"])
	raiders.anchor = base
	raiders.facing = Vector3(-1, 0, 0)
	raiders.aggro_radius = 32.0
	world.add_child(raiders)
	raiders.add_soldiers(count, base)
	raiders.wiped_out.connect(func(_s: Squad) -> void: _on_raiders_defeated(camp))


func _on_raiders_defeated(camp: Node3D) -> void:
	_raids_cleared += 1
	var reward := 120 + 60 * _raids_cleared
	Game.add_gold(reward)
	Game.say("The raiders are broken! +%d gold." % reward)
	Game.promote()
	await get_tree().create_timer(4.0).timeout
	camp.queue_free()
	await get_tree().create_timer(40.0).timeout
	var target: Dictionary = WorldGen.settlements[1 + _raids_cleared % (WorldGen.settlements.size() - 1)]
	var where: Vector2 = target["pos"] + Vector2(target["radius"] * 2.6, 0).rotated(float(_raids_cleared))
	_spawn_raiders(where, 12 + _raids_cleared * 8)
	Game.say("Raiders spotted near %s!" % target["name"])


# --- Environment & day/night ------------------------------------------------------

func _build_environment() -> void:
	# Real captured sky (Poly Haven HDRI, CC0) lights the scene and fills reflections.
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/incoming/polyhaven/hdris/kloofendal_48d_partly_cloudy_puresky_4k.hdr")
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	# Modern lighting (Forward+ on desktop; the Mobile renderer skips what it can't do).
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("c9d4e6")
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color("e8dccb")
	env.volumetric_fog_length = 90.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 0.8
	sun.light_volumetric_fog_energy = 1.4
	world.add_child(sun)


func _update_daylight() -> void:
	var t := WorldSim.time_of_day
	var day_amount := clampf(sin((t - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)   # 0 at night, 1 at noon
	sun.rotation = Vector3(-lerpf(0.15, 1.1, day_amount), PI * 0.25 + (t - 12.0) / 12.0 * PI * 0.5, 0)
	sun.light_energy = lerpf(0.05, 1.5, day_amount)
	sun.light_color = Color("ff9a5a").lerp(Color("fff1dc"), day_amount)
	env.ambient_light_energy = lerpf(0.25, 0.7, day_amount)
	env.fog_light_color = Color("1b2238").lerp(Color("c9d4e6"), day_amount)
	env.background_energy_multiplier = lerpf(0.08, 1.0, day_amount)
	baker.set_light(lerpf(0.35, 1.0, day_amount))


# --- Scripted demo (for trailer capture with --write-movie) ------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _teleport(p: Vector2, yaw: float) -> void:
	var pos := Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.set_camera(yaw, -0.28)
	terrain.focus = pos
	terrain.build_all_now()
	water.focus = pos
	water.build_all_now()
	settlements.focus = pos
	for i in 4:
		settlements.update_now()
	population.focus = pos
	population.refresh()


func _run_demo() -> void:
	WorldSim.time_of_day = 15.0
	# 1. Morning bustle in Ashford.
	_teleport(Vector2(20, 26), PI * 0.2)
	Game.say("Ashford — 5,000 simulated people live in this realm.")
	player.touch_move = Vector2(0, -0.55)
	for i in 60:
		player.add_look(Vector2(1.2, 0))
		await get_tree().process_frame
	await _wait(2.0)
	player.touch_move = Vector2.ZERO
	# 2. Enlist with the captain.
	_teleport(Vector2(-7, 6.5), PI)
	await _wait(0.8)
	captain.interact(player, army.alive())
	await _wait(2.5)
	# 3. Town view as the militia forms up.
	player.set_view(Player.View.TOWN)
	player.touch_move = Vector2(0.3, -0.7)
	await _wait(3.0)
	player.touch_move = Vector2.ZERO
	player.set_view(Player.View.THIRD)
	# 4. The raider camp.
	var approach := FIRST_CAMP + Vector2(-26, 4)
	_teleport(approach, -PI * 0.5 + 0.1)
	for s in army.soldiers:
		s.global_position = player.global_position + Vector3(randf_range(-7, -2), 0, randf_range(-5, 5))
	await _wait(1.0)
	Game.say("CHARGE!")
	army.command(Squad.Order.CHARGE)
	player.touch_move = Vector2(0, -1)
	await _wait(2.2)
	player.touch_move = Vector2.ZERO
	for i in 14:
		player.attack()
		await _wait(0.28)
		if i == 5:
			player.dodge()
			await _wait(0.5)
		if i == 9:
			Input.action_press("block")
			await _wait(1.0)
			Input.action_release("block")
	# 5. First person in the melee.
	player.set_view(Player.View.FIRST)
	for i in 8:
		player.attack()
		await _wait(0.35)
	player.set_view(Player.View.THIRD)
	# 6. Pull back to command the field.
	player.zoom(1)
	await _wait(1.5)
	player.zoom(1)
	await _wait(3.0)
	player.set_view(Player.View.THIRD)
	# 7. The road to the royal castle.
	var c: Dictionary = WorldGen.settlements[1]
	var road: Vector2 = c["pos"] + Vector2(-150, 110)
	var d: Vector2 = c["pos"] - road
	_teleport(road, atan2(-d.x, -d.y))
	player.set_camera(atan2(-d.x, -d.y), -0.12)
	Game.say("Kingsreach — seat of the crown.")
	player.touch_move = Vector2(0, -0.6)
	await _wait(5.0)
	get_tree().quit()


# --- Preview screenshots ----------------------------------------------------------

func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


func _screenshot(shot: String, path: String) -> void:
	WorldSim.time_of_day = 13.5
	var warmup := 60
	match shot:
		"explore":
			player.set_camera(PI * 0.2, -0.22)
		"first":
			player.set_view(Player.View.FIRST)
			player.set_camera(PI * 0.9, -0.05)
		"town":
			player.set_view(Player.View.TOWN)
			player.set_camera(PI * 0.1, -0.7)
		"command", "battle":
			Game.rank = 2
			_recruit(24)
			var p := Vector3(FIRST_CAMP.x - 22, 0, FIRST_CAMP.y + 6)
			p.y = WorldGen.height(p.x, p.z) + 0.5
			player.global_position = p
			player.set_camera(-PI * 0.5 + 0.35, -0.25)
			await get_tree().process_frame
			for s in army.soldiers:
				s.global_position = p + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			army.command(Squad.Order.CHARGE)
			if shot == "command":
				player.set_view(Player.View.TOWN)
			warmup = 70 if shot == "command" else 18
		"castle":
			var c: Dictionary = WorldGen.settlements[1]
			var p2: Vector2 = c["pos"] + Vector2(-250, 185)
			player.global_position = Vector3(p2.x, WorldGen.height(p2.x, p2.y) + 0.5, p2.y)
			var d: Vector2 = c["pos"] - p2
			player.set_camera(atan2(-d.x, -d.y), -0.12)
			settlements.focus = player.global_position
			warmup = 240
		"lineup":
			hud.visible = false
			_teleport(Vector2(105, -40), 0.0)
			var base := player.global_position + player.forward() * 3.4
			var looks := [["Knight", ["1H_Sword", "Round_Shield"], "Idle"], ["Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"], "1H_Melee_Attack_Chop"],
				["Barbarian", ["1H_Axe", "Barbarian_Round_Shield"], "Blocking"], ["Rogue_Hooded", [], "Walking_A"],
				["Mage", [], "Idle"], ["Rogue", [], "Cheer"]]
			var right := player.forward().cross(Vector3.UP).normalized()
			for i in looks.size():
				var keep: Array[String] = []
				keep.assign(looks[i][1])
				var c := Assets.character(looks[i][0], 1.78, keep)
				world.add_child(c)
				var pos: Vector3 = base + right * (i - 2.5) * 1.1
				pos.y = WorldGen.height(pos.x, pos.z)
				c.global_position = pos
				c.look_at(player.global_position, Vector3.UP, true)
				var ap := Assets.animation_player(c)
				if ap:
					ap.play(looks[i][2])
			player.visible = false
			player.set_view(Player.View.FIRST)
			player.set_camera(player._yaw, -0.12)
			warmup = 45
		"market", "board":
			# Standing in the plaza: the trader (market) or the notice board (board), menu open.
			var spot := Vector2(1.5, 1.0) if shot == "market" else Vector2(1.0, 2.5)
			_teleport(spot, 0.0)
			var tgt: Node3D = null
			for st in get_tree().get_nodes_in_group("station"):
				if (st as Station).title == ("Market Trader" if shot == "market" else "Notice Board"):
					tgt = st
			if tgt:
				var d := tgt.global_position - player.global_position
				player.set_camera(atan2(-d.x, -d.z), -0.18)
				Life.give("wolf_pelt", 2)
				hud.show_menu(services.merchant_menu if shot == "market" else services.notice_menu)
			warmup = 90
		"frontier":
			var ws: Dictionary = Frontier.runestones.stones[7] if Frontier.runestones.stones.size() > 7 else Frontier.runestones.stones[0]
			var den: Dictionary = Frontier.ecology.dens[0]
			var dir: Vector2 = (den["pos"] - ws["pos"]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var sp: Vector2 = den["pos"] - dir * 40.0 - side * 2.5   # out in the forest near a den
			_teleport(sp, 0.0)
			player.set_camera(atan2(-dir.x, -dir.y), -0.14)
			frontier.focus = Vector3(den["pos"].x, 0, den["pos"].y)
			frontier._timer = 0.0
			frontier._process(0.0)
			for w in get_tree().get_nodes_in_group("team1"):
				if w is Wolf:
					var q: Vector2 = sp + dir * randf_range(12.0, 22.0) + side * randf_range(-7.0, 7.0)
					w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
					w.home = q
					w.state = Wolf.State.STALK
			warmup = 25
		"lake":
			# On the lake shore at midday, looking out over the water.
			var lc := WorldGen.lake_center
			var to_home := (Vector2.ZERO - lc).normalized()
			var spot := lc + to_home * WorldGen.lake_radius
			for step in 60:   # walk inward from the shore until the feet are just dry
				var q := lc + to_home * (WorldGen.lake_radius * 1.4 - step * 2.0)
				if WorldGen.water_depth(q.x, q.y) > 0.0:
					break
				spot = q
			_teleport(spot, 0.0)
			var look := lc - spot
			player.set_camera(atan2(-look.x, -look.y) + 0.35, -0.16)
			warmup = 90
		"city", "street":
			var cap: Dictionary = WorldGen.settlements[1]
			var cp: Vector2 = cap["pos"]
			var gate: float = cap["plan"]["gates"][0]
			var sp: Vector2 = cp + Vector2(cos(gate), sin(gate)) * (cap["plan"]["plaza_r"] + 30.0)
			_teleport(sp, 0.0)
			var look: Vector2 = cp - sp
			player.set_camera(atan2(-look.x, -look.y), -0.12)
			if shot == "city":
				hud.visible = false
				player.visible = false
				var cam := Camera3D.new()
				cam.far = 1500.0
				viewport.get_child(0).add_child(cam)
				var off := Vector2(cos(gate + 0.6), sin(gate + 0.6)) * 330.0
				cam.global_position = Vector3(cp.x + off.x, cap["base_h"] + 190.0, cp.y + off.y)
				cam.look_at(Vector3(cp.x, cap["base_h"], cp.y))
				cam.current = true
				terrain.focus = Vector3(cp.x, 0, cp.y)
				terrain.view_radius = 6
				terrain.build_all_now()
			warmup = 90
	for i in warmup:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot: ", path)
	get_tree().quit()
