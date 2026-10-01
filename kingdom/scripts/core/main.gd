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
var region: RegionDressing
var region1: Node   # scripts/region1/region1_glue.gd (Region1 hooks)
const Flow := preload("res://scripts/ui/frontend/flow.gd")
const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
const StyleG := preload("res://scripts/style_g.gd")
const SeasonsScript := preload("res://scripts/sim/seasons.gd")
const RoadTraffic := preload("res://scripts/world/road_traffic.gd")
const RoadEvents := preload("res://scripts/world/road_events.gd")
var road_traffic: Node3D
var road_events: Node3D
const HomesteadView := preload("res://scripts/world/homestead_view.gd")
var homestead_view: Node3D
var weather: Node3D
var ambient_fx: Node3D
var noble_courts: Node3D
var lord_hall: Node3D
var realm_presence: Node3D
var build_resources: Node3D
var construction_view: Node3D
var _order_from: Variant = null   # command view: where the current drag order started
var player: Player
var hud: HUD
var army: Squad
var raiders: Squad
## An enemy host at the war front while Life.war is at war (scripts/sim/war_sim.gd).
var war_host: Squad
var captain: Captain
var services: VillageServices
var camps: MonsterCamps
var ambient: AmbientLife
var sun: DirectionalLight3D
var fill: DirectionalLight3D
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
	player.add_child(preload("res://scripts/actors/technique_caster.gd").new())
	hud = HUD.new(player)
	add_child(hud)
	hud.fast_travel_requested.connect(func(at: Vector2) -> void: _teleport(at, 0.0))
	hud.place_discovered.connect(func(_place: Variant) -> void: Audio.play_discovery())
	hud.add_action_button("lock_on", "Lock", "lock_on", "glyph:lock")
	hud.add_action_button("crouch", "Sneak", "crouch", "walk")

	hud.set_loading_text("Painting sprites...", 0.04)
	await get_tree().process_frame
	await baker.bake("soldier", "Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"])
	await baker.bake("raider", "Barbarian", ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"])
	var looks_done := 0
	for look: String in PopulationLOD.LOOK_MODEL:
		hud.set_loading_text("Painting sprites...", 0.08 + 0.32 * looks_done / maxf(1.0, PopulationLOD.LOOK_MODEL.size()))
		looks_done += 1
		var model: Array = PopulationLOD.LOOK_MODEL[look]
		var keep: Array[String] = []
		keep.assign(model[1])
		await baker.bake(look, model[0], keep, "Walking_A")

	hud.set_loading_text("Raising the land...", 0.45)
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
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	world.add_child(preload("res://scripts/region1/region1_root.gd").new())
	var spawn := Vector3(HOME_SPAWN.x, WorldGen.height(HOME_SPAWN.x, HOME_SPAWN.y) + 0.5, HOME_SPAWN.y)
	terrain.focus = spawn
	settlements.focus = spawn
	terrain.view_radius = 2
	hud.set_loading_text("Raising the land...", 0.5)
	await get_tree().process_frame
	terrain.build_all_now()
	terrain.view_radius = 4
	hud.set_loading_text("Building the villages...", 0.7)
	await get_tree().process_frame
	settlements.update_now()

	world.add_child(player)
	player.global_position = spawn
	player.spawn_point = spawn
	player.set_camera(PI * 0.15, -0.3)
	# Building doors: street doors mask only the player's trigger layer, and this
	# script's interact handler drives them (no per-door input polling).
	InteriorDoor.tag_player(player)
	InteriorDoor.external_dispatch = true
	player.health_changed.connect(_on_player_health)
	player.died.connect(_on_player_died)

	captain = Captain.new()
	world.add_child(captain)
	captain.global_position = Vector3(-7, WorldGen.height(-7, 3), 3)
	captain.recruit_requested.connect(_recruit)
	Life.player = player
	services = VillageServices.new()
	services.setup(hud, captain, func() -> int: return army.alive(), _recruit)
	world.add_child(services)
	lord_hall = preload("res://scripts/world/lord_hall.gd").new()
	lord_hall.setup(hud)
	world.add_child(lord_hall)
	for s: Dictionary in WorldGen.settlements:
		lord_hall.spawn_for(s)
	# Keepers inside the rooms get their menus (doors of towns built so far, then new ones).
	services.wire_settlement(settlements)
	settlements.settlement_built.connect(func(_s: Dictionary, root: Node3D) -> void: services.wire_settlement(root))
	hud.set_loading_text("Filling the wilds...", 0.85)
	await get_tree().process_frame
	camps = MonsterCamps.new()
	world.add_child(camps)
	world.add_child(Lakeside.new())
	region = RegionDressing.new()
	world.add_child(region)
	road_traffic = RoadTraffic.new()
	road_traffic.name = "RoadTraffic"
	world.add_child(road_traffic)
	road_events = RoadEvents.new()
	road_events.name = "RoadEvents"
	world.add_child(road_events)
	homestead_view = HomesteadView.new()
	world.add_child(homestead_view)
	weather = preload("res://scripts/world/weather.gd").new()
	weather.name = "Weather"
	weather.add_to_group("weather")
	world.add_child(weather)
	weather.setup(env, sun, player.camera)
	ambient_fx = preload("res://scripts/world/ambient_fx.gd").new()
	ambient_fx.name = "AmbientFX"
	world.add_child(ambient_fx)
	noble_courts = preload("res://scripts/world/noble_courts.gd").new()
	noble_courts.setup(hud, Life.nobility)
	world.add_child(noble_courts)
	ambient = AmbientLife.new()
	world.add_child(ambient)
	var ore := preload("res://scripts/world/ore_vein.gd").new()
	ore.name = "OreVeins"
	world.add_child(ore)
	realm_presence = preload("res://scripts/world/realm_presence.gd").new()
	realm_presence.setup(hud)
	world.add_child(realm_presence)
	build_resources = preload("res://scripts/world/build_resources.gd").new()
	build_resources.name = "BuildResources"
	world.add_child(build_resources)
	construction_view = preload("res://scripts/world/construction_view.gd").new()
	construction_view.name = "ConstructionView"
	construction_view.hud = hud
	world.add_child(construction_view)

	hud.set_loading_text("Waking the world...", 0.95)
	await get_tree().process_frame
	army = Squad.new().setup(0, "soldier", "Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"])
	army.routed.connect(func(_s: Squad) -> void: Game.say("Our men are breaking!"))
	army.leader = player
	army.order = Squad.Order.FOLLOW
	world.add_child(army)
	_spawn_raiders(FIRST_CAMP, 12)
	WorldSim.hour_changed.connect(func(_h: int) -> void: _maybe_spawn_war_battle())

	# Region1 hook (docs/regions/REGION_1_PLAN.md) C3-C8, C12: wards, Scar, embers, Ashsight, story, tutorial, audio
	region1 = preload("res://scripts/region1/region1_glue.gd").new()
	region1.name = "Region1Glue"
	world.add_child(region1)
	region1.setup(self)
	world.add_child(preload("res://scripts/world/towers/tower_site.gd").new())   # towers hook (docs/design tower plan)

	hud.set_loading_text("Ready", 1.0)
	hud.hide_loading()
	Quality.start_adaptive()
	VFX.warmup(world)   # pre-draw every effect shader so the first cast doesn't hitch
	var args := _user_args()
	if (args.has("shot") and args["shot"] != "birth") or args.has("demo") or args.has("adult"):
		Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
		player.apply_age()
	if args.has("shot"):
		_screenshot(args["shot"], args.get("out", "user://shot.png"))
	elif args.has("qa"):
		# QA driver: --qa=res://tools_qa/construction/build_qa.gd (its run(main) takes over from here)
		var qa: Node = (load(String(args["qa"])) as GDScript).new()
		add_child(qa)
		qa.call("run", self)
	elif args.has("demo"):
		_run_demo()
	elif args.has("skipintro") or Flow.wants_skip_intro():   # loading a save from the menu
		_after_birth()
	else:
		_play_birth()


## New life: the birth cutscene, then "four years later" as a small child at home.
func _play_birth() -> Signal:
	var lp := Life.life_path
	var home: Dictionary = WorldGen.settlements[0]
	var cut := CutscenePlayer.new()
	world.add_child(cut)      # inside the SubViewport so its camera renders the world
	var saved_time := WorldSim.time_of_day
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.light_energy = 4.0
	lamp.omni_range = 14.0
	world.add_child(lamp)
	lamp.global_position = Vector3(lp.home_pos.x, WorldGen.height(lp.home_pos.x, lp.home_pos.y) + 2.2, lp.home_pos.y)
	var stage := _stage_birth_room(lp.home_pos)
	cut.shot_started.connect(func(_i: int, shot: Dictionary) -> void:
		if shot.has("time"):
			WorldSim.time_of_day = float(shot["time"])
			_update_daylight())
	hud.visible = false
	cut.play(BirthCutscene.build(lp.given_name, lp.family_name, lp.parent("mother")["name"],
		lp.parent("father")["name"], home["pos"], lp.home_pos, String(home["name"]), Callable(),
		stage.global_position if stage else Vector3.INF))
	cut.finished.connect(func() -> void:
		lamp.queue_free()
		if stage:
			stage.queue_free()
		cut.queue_free()
		WorldSim.time_of_day = maxf(saved_time, 8.0)
		_after_birth())
	return cut.finished


## The cottage interior film set, hidden 60 m under the family's house, lit by
## its hearth and candles, with the parents in place.
func _stage_birth_room(house: Vector2) -> Node3D:
	var path := "res://assets/generated/cottage_interior.glb"
	if not ResourceLoader.exists(path):
		return null
	var root := Node3D.new()
	world.add_child(root)
	root.global_position = Vector3(house.x, WorldGen.height(house.x, house.y) - 60.0, house.y)
	root.add_child(Assets.scene(path).instantiate())
	var lights := [[Vector3(0, 0.5, -1.9), Color(1.0, 0.6, 0.32), 1.8, 6.5],
		[Vector3(1.62, 1.1, 0.72), Color(1.0, 0.78, 0.5), 0.7, 3.5],
		[Vector3(-2.6, 1.5, -0.95), Color(0.55, 0.65, 1.0), 0.6, 4.5],
		[Vector3(0, 2.5, 2.0), Color(0.85, 0.8, 0.9), 0.35, 7.0]]
	for l: Array in lights:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		o.shadow_enabled = true
		root.add_child(o)
	var mother := Assets.character("Mother", 1.64, [])
	root.add_child(mother)
	mother.position = Vector3(-1.75, 0.45, -1.0)
	mother.rotation.y = PI * 0.2       # turned toward the open wall (camera)
	var mp := Assets.animation_player(mother)
	if mp:
		for a in ["Sitting_Idle", "Idle"]:
			if mp.has_animation(a):
				mp.play(a)
				break
	var father := Assets.character("Father", 1.8, [])
	root.add_child(father)
	father.position = Vector3(1.9, 0, -0.6)
	father.look_at(root.global_position + Vector3(1.0, 0, -1.2), Vector3.UP, true)
	var fp := Assets.animation_player(father)
	if fp and fp.has_animation("Idle"):
		fp.play("Idle")
	return root


func _after_birth() -> void:
	hud.visible = true
	var lp := Life.life_path
	var door: Vector2 = lp.home_pos + Vector2(0, 5.5)
	# Face away from the family house, toward the street and village.
	var away := door - lp.home_pos
	_teleport(door, atan2(-away.x, -away.y) + PI)
	player.apply_age()
	Game.say("%d years later. %s, child of %s and %s, wakes to a bright morning in %s." % [Life.START_AGE,
		lp.given_name, lp.parent("mother")["name"], lp.parent("father")["name"], WorldGen.settlements[0]["name"]])


func _process(delta: float) -> void:
	if player == null or not player.is_inside_tree() or terrain == null or army == null:   # still loading (awaits in _ready)
		return
	var focus := player.global_position
	# Region1 look hook: a cutscene may stream the ground around its camera path (Hidden Vale flyover, exploration_director.gd).
	terrain.focus = Engine.get_meta("stream_focus", focus)
	water.focus = terrain.focus
	settlements.focus = focus
	population.focus = focus
	frontier.focus = focus
	region.focus = focus
	road_traffic.focus = focus
	road_events.focus = focus
	homestead_view.focus = focus
	build_resources.focus = focus
	construction_view.focus = focus
	ambient_fx.focus = focus
	noble_courts.focus = focus
	camps.focus = focus
	ambient.focus = focus
	# The settings screen's View Distance (Quality tier or override) sets the chunk ring; the command view sees one ring further.
	terrain.view_radius = Quality.view_radius + (1 if player.view == Player.View.COMMAND and Quality.view_radius >= 4 else 0)
	water.view_radius = terrain.view_radius
	_update_daylight()
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.2
		var perf := "%d fps · %d chunks · %d people nearby (%d full / %d sprites) · %d soldiers" % [
			Engine.get_frames_per_second(), terrain.loaded_count(), population.full_count + population.sprite_count,
			population.full_count, population.sprite_count, get_tree().get_nodes_in_group("combatant").size()]
		hud.update_status(army.alive(), army.order_name(), player.nearest_interactable(), perf)
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
	elif event.is_action_pressed("ability_dash"):
		player.ability_dash()
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
		elif target is Station and (target as Station).name == "WarTable":
			# the War Room table opens the war map directly, in war-table style (docs/design/WAR_COMMAND_RULEBOOK.md §2)
			var wm: Control = load("res://scripts/ui/war/war_map.gd").open_modal(hud, Life.realm)
			wm.call("set_style", 2)
		elif target is Station:
			hud.show_menu((target as Station).open)
		elif target is CampMonster:
			hud.show_menu(services.naming_menu.bind(target))
		elif target is InteriorDoor:
			(target as InteriorDoor).use()
	elif event.is_action_pressed("journal"):
		if hud.is_menu_open():
			hud.close_menu()
		else:
			GameMenu.toggle(hud, "inventory")   # the tabbed menu; the Pack button keeps the full pack list
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
	elif event.is_action_pressed("order_retreat"):
		Game.say("Fall back!" if army.command(Squad.Order.RETREAT) else "They won't listen.")
	elif event.is_action_pressed("order_formation"):
		Game.say(army.cycle_formation())
	elif player.view == Player.View.COMMAND and (event is InputEventScreenTouch or event is InputEventMouseButton):
		# Command view: press marks the spot, drag sets the facing, release gives the order.
		if event.pressed:
			_order_from = Squad.pick_ground(player.camera, event.position)
		elif _order_from != null:
			var to: Variant = Squad.pick_ground(player.camera, event.position)
			var face: Vector3 = (to - _order_from) if to != null and (to - _order_from).length() > 2.0 else Vector3.ZERO
			army.clear_preview()
			army.move_to(_order_from, face)
			_order_from = null
	elif player.view == Player.View.COMMAND and (event is InputEventScreenDrag or event is InputEventMouseMotion) and _order_from != null:
		var cur: Variant = Squad.pick_ground(player.camera, event.position)
		if cur != null:
			army.preview_order(_order_from, cur - _order_from)


## Dying inside a building: leave the room first, so the respawn (player.gd puts
## the player back at spawn_point) lands in a visible world with its own camera
## environment and view restored.
func _on_player_health(current: int, _maximum: int) -> void:
	if current <= 0 and InteriorDoor.active != null:
		InteriorDoor.active.leave()


## The fall has played: the death screen offers respawn at home / last save / load / main menu.
func _on_player_died() -> void:
	const DeathScreen := preload("res://scripts/ui/frontend/death_screen.gd")
	DeathScreen.open(hud, _respawn_at_home)


## "Respawn at Home": the life-sim cost of dying (gold, a minor injury; Life.apply_death_penalty),
## then back on your feet at the last bed or the village.
func _respawn_at_home() -> void:
	var r: Dictionary = Life.apply_death_penalty()
	player.revive()
	Game.say(String(r["text"]))


func _recruit(count: int) -> void:
	# Once on the soldier ladder, the troops you may lead follow your rank (0, 5, 20, 60, 200).
	var room := count
	if String(Life.career_id) == "soldier":
		room = mini(count, maxi(0, Life.CareerLadders.troops_for_rank(Life.career_rank) - army.alive()))
	army.add_soldiers(room, player.global_position - player.forward() * 4.0)


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


## While the realm is at war, the most contested front holds an enemy host; ride
## within reach of it and it is there to fight.
func _maybe_spawn_war_battle() -> void:
	if war_host != null and is_instance_valid(war_host):
		if not Life.war.is_at_war():
			war_host.queue_free()
			war_host = null
		return
	if not Life.war.is_at_war() or player == null:
		return
	var b: Dictionary = Life.war.battle_at_front()
	if b.is_empty():
		return
	var at: Vector2 = b["pos"]
	var p := Vector2(player.global_position.x, player.global_position.z)
	if p.distance_to(at) > 400.0:
		return
	var base := Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	war_host = Squad.new().setup(1, "raider", "Barbarian", ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"])
	war_host.anchor = base
	war_host.aggro_radius = 40.0
	world.add_child(war_host)
	war_host.add_soldiers(clampi(int(b.get("size", 10)), 6, 30), base)
	war_host.wiped_out.connect(func(_s: Squad) -> void:
		Game.add_gold(150)
		Life.biography.add_highlight("Broke an enemy host at %s" % String(b.get("name", "the front")), WorldSim.day)
		Game.say("The enemy host at %s is broken! +150 gold." % String(b.get("name", "the front")))
		war_host = null)
	Game.say("An enemy host holds the field at %s." % String(b.get("name", "the front")))


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
	# Style G (skills ashes-style-g): ONE look. Environment, sun and bounce fill come from scripts/style_g.gd; the
	# Quality autoload re-applies SSAO / glow / shadows per tier when these nodes enter the tree.
	StyleG.game_mode = true
	var tier := StyleG.tier_name(Quality.tier)
	env = Environment.new()
	StyleG.apply_environment(env, tier, true)
	# SSIL, SDFGI and volumetric fog are Forward+ only; Quality switches them on for ULTRA.
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = StyleG.make_sun(tier)
	sun.light_volumetric_fog_energy = 1.4
	world.add_child(sun)
	fill = StyleG.make_fill()
	world.add_child(fill)


func _update_daylight() -> void:
	var t := WorldSim.time_of_day
	# The seasons' day length (Seasons.daylight_of) is squeezed into Style G's solar hours: 6 = sunrise, 18 = sunset.
	var dl: Vector2 = SeasonsScript.daylight_of(WorldSim.day, t)
	var solar := StyleG.solar_hour(t, dl.x, dl.y)
	var day_amount := clampf(sin((solar - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)   # 0 at night, 1 at noon
	var night := 1.0 - smoothstep(0.0, 0.25, day_amount)
	StyleG.apply_daylight(env, sun, fill, solar, solar)
	baker.set_light(lerpf(0.35, 1.0, day_amount))
	# Emberglass Mere turns ember-coloured around sunset (lore); rain rings follow the weather.
	var rain: float = weather.rain_amount() if weather else 0.0
	water.set_weather(rain, clampf(1.0 - absf(t - 18.3) / 1.3, 0.0, 1.0) * (1.0 - rain))
	if weather:
		Audio.set_weather_intensity(rain)
		Audio.set_wind(preload("res://scripts/world/weather.gd").wind_strength)
	var lamp_energy := 1.6 * night
	for l in get_tree().get_nodes_in_group("street_lamp"):
		(l as OmniLight3D).light_energy = lamp_energy
		(l as OmniLight3D).visible = lamp_energy > 0.01


# --- Scripted demo (for trailer capture with --write-movie) ------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _teleport(p: Vector2, yaw: float) -> void:
	var pos := Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.set_camera(yaw, -0.28)
	# With physics/common/physics_interpolation on, a teleport would otherwise
	# smear the camera across the screen for one frame as it interpolates from
	# the old position to the new one. reset_physics_interpolation() snaps the
	# whole subtree (player, camera rig, viewmodel, lock marker) to the new
	# transform with nothing to interpolate from.
	player.reset_physics_interpolation()
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

func args_frame_time() -> float:
	return float(_user_args().get("t", "25"))


func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


## HUD QA shots (--shot=hud_explore|hud_npc|hud_door|hud_work|hud_combat): the exploration / combat HUD at a
## street, beside a villager, at a door, at a work spot and in a fight (see docs in .claude/skills/ashes-visual-qa).
func _hud_shot(shot: String) -> void:
	_teleport(Vector2(1.0, 7.5), 0.0)
	player.set_camera(0.25, -0.12)
	for i in 30:
		await get_tree().process_frame
	match shot:
		"hud_npc":
			var best: Node3D = null
			var bd := 1e9
			for v in get_tree().get_nodes_in_group("villager"):
				var d := (v as Node3D).global_position.distance_to(player.global_position)
				if (v as Node3D).is_visible_in_tree() and d < bd:
					bd = d
					best = v
			if best:
				var at := best.global_position + Vector3(1.8, 0, 1.0)
				_teleport(Vector2(at.x, at.z), 0.0)
				var look := best.global_position - player.global_position
				player.set_camera(atan2(-look.x, -look.z), -0.12)
		"hud_door":
			var door: InteriorDoor = null
			for n in world.find_children("*", "InteriorDoor", true, false):
				if (n as InteriorDoor).interior_scene.contains("inn_interior"):
					door = n
					break
			if door:
				_teleport(Vector2(door.global_position.x, door.global_position.z), 0.0)
				var fwd := -door.global_transform.basis.z
				player.set_camera(atan2(-fwd.x, -fwd.z) + PI, -0.12)
		"hud_work":
			var spot: Node3D = null
			for st in get_tree().get_nodes_in_group("station"):
				if (st as Station).verb == "Work":
					spot = st
					break
			if spot == null:      # no career work spot in this build yet: a stand-in so the label can be judged
				spot = Station.new("Blacksmith", "Work", Callable())
				world.add_child(spot)
				spot.global_position = player.global_position + player.forward() * 1.5
			else:
				_teleport(Vector2(spot.global_position.x + 1.5, spot.global_position.z + 1.5), 0.0)
			var lk := spot.global_position - player.global_position
			player.set_camera(atan2(-lk.x, -lk.z), -0.15)
		"hud_combat":
			_teleport(FIRST_CAMP + Vector2(-15, 6), 0.0)
			player._invulnerable = 999.0      # QA: stay alive long enough to read the combat HUD
			var cd := Vector3(FIRST_CAMP.x, 0, FIRST_CAMP.y) - player.global_position
			player.set_camera(atan2(-cd.x, -cd.z), -0.15)
	for i in 40:
		await get_tree().process_frame


func _screenshot(shot: String, path: String) -> void:
	WorldSim.time_of_day = float(_user_args().get("hour", "16.2"))   # late-afternoon side light
	var warmup := 60
	var late_fx := Callable()
	var forced_weather := String(_user_args().get("weather", ""))
	if forced_weather != "" and weather:
		weather.set_weather(forced_weather, 0.1)
	if shot.begins_with("site_"):
		# A region site (RegionSites kind) seen from in front, e.g. site_farm, site_mine.
		var kind := shot.substr(5)
		for site in WorldGen.sites:
			if site["kind"] == kind:
				var c: Vector2 = site["pos"]
				var yaw: float = site["yaw"]
				var dist := 12.0 + float(site["clear"]) * 0.8
				var front := Vector2(sin(yaw), cos(yaw))
				var sp := c + front.rotated(0.45) * dist
				_teleport(sp, 0.0)
				var look := c - sp
				player.set_camera(atan2(-look.x, -look.y), -0.14)
				region.focus = player.global_position
				region.build_all_now()
				break
		warmup = 90
		shot = ""
	elif shot.begins_with("interior_"):
		# Walk through a building's door: interior_inn, interior_blacksmith, interior_guild, interior_healer, interior_house.
		var want := shot.substr(9)
		var door: InteriorDoor = null
		for n in world.find_children("*", "InteriorDoor", true, false):
			var id := n as InteriorDoor
			if id.interior_scene.contains(want + "_interior"):
				door = id
				break
		if door:
			_teleport(Vector2(door.global_position.x, door.global_position.z), 0.0)
			await get_tree().process_frame
			door.enter(player)
			await get_tree().process_frame
		warmup = 60
		shot = ""
	match shot:
		"stronghold":
			# Nearest stronghold to the player (--n=k for the kth nearest), framed from --dist metres (default 40).
			var sh_list: Array = Life.realm.mod("strongholds").strongholds()
			var here := Vector2(player.global_position.x, player.global_position.z)
			sh_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return here.distance_to(a["pos"]) < here.distance_to(b["pos"]))
			for si in mini(sh_list.size(), 30):
				print("[stronghold-list] ", si, " ", sh_list[si]["name"], " ", sh_list[si]["kind"], " ", snapped(here.distance_to(sh_list[si]["pos"]), 1.0))
			var sh: Dictionary = sh_list[clampi(int(_user_args().get("n", "0")), 0, sh_list.size() - 1)]
			var shp: Vector2 = sh["pos"]
			var ent: Dictionary = realm_presence.nearest_stronghold(shp)
			var focus2: Vector2 = ent["pos"] if not ent.is_empty() else shp
			var back := Vector2(sin(deg_to_rad(float(_user_args().get("yaw", "20")))), cos(deg_to_rad(float(_user_args().get("yaw", "20")))))
			var sd := float(_user_args().get("dist", "40"))
			var ssp: Vector2 = focus2 + back * sd
			_teleport(ssp, 0.0)
			var sl := focus2 - ssp
			player.set_camera(atan2(-sl.x, -sl.y), float(_user_args().get("pitch", "-0.16")))
			region.focus = player.global_position
			region.build_all_now()
			realm_presence.refresh_now()
			print("[stronghold] ", sh["name"], " kind=", sh["kind"], " owner=", sh["owner"], " at ", shp, " frame at ", focus2)
			warmup = 120
		"wartable":
			# Walk into the first guild hall, then look at the War Room table.
			var wdoor: InteriorDoor = null
			for n in world.find_children("*", "InteriorDoor", true, false):
				var wid := n as InteriorDoor
				if wid.interior_scene.contains("guild_interior"):
					wdoor = wid
					break
			if wdoor:
				_teleport(Vector2(wdoor.global_position.x, wdoor.global_position.z), 0.0)
				await get_tree().process_frame
				wdoor.enter(player)
				await get_tree().process_frame
				realm_presence._check_war_table()
				var tbl: Node3D = wdoor.interior.get_node_or_null("WarTable")
				if tbl:
					var tp: Vector3 = tbl.global_position
					player.global_position = tp + Vector3(float(_user_args().get("dx", "-2.6")), 0.1, float(_user_args().get("dz", "2.6")))
					var wl := tp - player.global_position
					player.set_camera(atan2(-wl.x, -wl.z), float(_user_args().get("pitch", "-0.35")))
			warmup = 60
		"aerial":
			# High 3/4 view over Ashford and its fields.
			hud.visible = false
			var cam := Camera3D.new()
			world.add_child(cam)
			var gy := WorldGen.height(0, 0)
			cam.global_position = Vector3(95, gy + 62, 105)
			cam.look_at(Vector3(0, gy, -5))
			cam.fov = 55.0
			cam.current = true
			terrain.focus = Vector3(20, 0, 20)
			terrain.build_all_now()
			warmup = 80
		"guildhall", "orcs":
			# Establishing views of the Blender-built guild hall and the orc village.
			var at := Vector2.ZERO
			var look := Vector2.ZERO
			if shot == "guildhall":
				for lot: Dictionary in WorldGen.settlements[0]["plan"]["lots"]:
					if lot["asset"] == "adventurer_guild":
						var yaw: float = lot["yaw"]
						look = lot["pos"]
						at = look + Vector2(sin(yaw), cos(yaw)) * 11.5
			else:
				var hold: Dictionary = Life.lore.place("tuskridge_hold")
				look = hold["pos"]
				at = look + Vector2(30, 6)
			_teleport(at, 0.0)
			hud.visible = false
			camps.spawn_all_near(player.global_position)
			for m in camps.get_children():
				if m is CampMonster:
					(m as CampMonster).hostile = false
					(m as CampMonster)._set_team(false)
			var dv := Vector3(look.x, 0, look.y) - player.global_position
			player.set_camera(atan2(-dv.x, -dv.z), -0.02 if shot == "guildhall" else -0.2)
			if shot == "guildhall":
				# Free camera above the street, 3/4 view down onto the hall's front.
				var cam := Camera3D.new()
				world.add_child(cam)
				var gy := WorldGen.height(look.x, look.y)
				var dir := (at - look).normalized()
				var side := Vector2(dir.y, -dir.x)
				var cp := look + dir * 13.0 + side * 9.0
				cam.global_position = Vector3(cp.x, gy + 10.0, cp.y)
				cam.look_at(Vector3(look.x, gy + 4.5, look.y))
				cam.fov = 62.0
				cam.current = true
			warmup = 70
		"camp":
			# The goblin warren from its edge; one goblin has yielded, naming menu open.
			var w: Dictionary = Life.lore.place("mossfang_warren")
			var wc: Vector2 = w["pos"]
			_teleport(wc + Vector2(-22, 10), 0.0)
			camps.spawn_all_near(player.global_position)
			await get_tree().process_frame
			var d := Vector3(wc.x, 0, wc.y) - player.global_position
			player.set_camera(atan2(-d.x, -d.z), -0.15)
			for m in camps.get_children():
				if m is CampMonster:
					(m as CampMonster).hostile = false
					(m as CampMonster)._set_team(false)
			var first: CampMonster = null
			for m in camps.get_children():
				if m is CampMonster:
					first = m
					break
			if first:
				first.global_position = player.global_position + player.forward() * 3.0
				first._yield()
				hud.show_menu(services.naming_menu.bind(first))
			warmup = 60
		"vfx":
			# Martial-arts / magic effects lined up in a field, frozen mid-burst.
			hud.visible = false
			_teleport(Vector2(105, -40), 0.0)
			player.set_camera(0.0, -0.2)
			var base := player.global_position + player.forward() * 7.0
			var right := player.forward().cross(Vector3.UP).normalized()
			late_fx = func() -> void:
				var origin := base + right * 0.0
				origin.y = WorldGen.height(origin.x, origin.z)
				VFX.showcase(world, origin)
			warmup = 60
		"explore":
			# Street level on the plaza's south side, looking north across the square.
			_teleport(Vector2(1.0, 7.5), 0.0)
			player.set_camera(0.25, -0.12)
		"hud_explore", "hud_npc", "hud_door", "hud_work", "hud_combat":
			await _hud_shot(shot)
			warmup = 100
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
		"birth":
			# Frame from the birth cutscene (the crane onto the lit house).
			_play_birth()
			await get_tree().create_timer(0.1).timeout
			warmup = 40
			var cps := world.get_children().filter(func(n: Node) -> bool: return n is CutscenePlayer)
			if not cps.is_empty():
				var cp: CutscenePlayer = cps[0]
				cp.advance(float(args_frame_time()))
		"market", "board", "guild":
			# Standing in the plaza facing a station with its menu open.
			var spots := {"market": Vector2(1.5, 1.0), "board": Vector2(1.0, 2.5), "guild": Vector2(-1.0, -4.0)}
			var names := {"market": "Market Trader", "board": "Notice Board", "guild": "Adventurer Guild"}
			_teleport(spots[shot], 0.0)
			var tgt: Node3D = null
			for st in get_tree().get_nodes_in_group("station"):
				if (st as Station).title == names[shot]:
					tgt = st
			if tgt:
				var d := tgt.global_position - player.global_position
				player.set_camera(atan2(-d.x, -d.z), -0.18)
				Life.give("wolf_pelt", 2)
				if shot == "guild":
					Game.gold = 60
					Life.join_guild()
				var menus := {"market": services.merchant_menu, "board": services.notice_menu, "guild": services.guild_menu}
				hud.show_menu(menus[shot])
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
		"homestead":
			# A furnished homestead on plot 1 (QA view of the build system).
			Game.gold = 5000
			Life.give("plank", 60)
			Life.give("iron_ingot", 20)
			Life.homestead.buy(0)
			Life.homestead.place(0, "cottage", Vector2i(2, 6), 0)
			Life.homestead.place(0, "barn", Vector2i(7, 6), 1)
			Life.homestead.place(0, "fence", Vector2i(0, 2), 0)
			Life.homestead.place(0, "fence", Vector2i(1, 2), 0)
			Life.homestead.place(0, "gate", Vector2i(2, 2), 0)
			Life.homestead.place(0, "fence", Vector2i(3, 2), 0)
			Life.homestead.place(0, "chicken_coop", Vector2i(6, 1), 0)
			Life.homestead.place(0, "pig_sty", Vector2i(3, 1), 0)
			Life.homestead.place(0, "well", Vector2i(1, 4), 0)
			Life.homestead.place(0, "woodpile", Vector2i(0, 5), 0)
			Life.homestead.place(0, "lamp_post", Vector2i(9, 4), 0)
			Life.homestead.place(0, "bench", Vector2i(9, 5), 0)
			Life.homestead.place(0, "crop_plot", Vector2i(4, 8), 0)
			Life.homestead.place(0, "crop_plot", Vector2i(5, 8), 0)
			Life.homestead.place(0, "crop_plot", Vector2i(6, 8), 0)
			Life.homestead.plant(0, Vector2i(4, 8), "wheat")
			Life.homestead.plant(0, Vector2i(5, 8), "wheat")
			Life.homestead.plant(0, Vector2i(6, 8), "cabbage")
			WorldSim.day += 3
			var hpos: Vector2 = Life.homestead.plots()[0]["pos"]
			var hyaw: float = Life.homestead.plots()[0]["yaw"]
			var hfront := Vector2(sin(hyaw), cos(hyaw))
			var hspot := hpos - hfront.rotated(-0.5) * 20.0
			_teleport(hspot, 0.0)
			player.set_camera(atan2(-(hpos - hspot).x, -(hpos - hspot).y), -0.16)
			homestead_view.focus = player.global_position
			homestead_view.build_all_now()
			warmup = 90
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
		"gate":   # Kingsreach gate market, as in the main art reference: down the gate road toward the gatehouse
			var capg: Dictionary = WorldGen.settlements[1]
			var cpg: Vector2 = capg["pos"]
			var ga: float = capg["plan"]["gates"][0]
			var dirg := Vector2(cos(ga), sin(ga))
			var spg: Vector2 = cpg + dirg * (float(capg["radius"]) - float(_user_args().get("gate_in", "42")))
			_teleport(spg, 0.0)
			player.set_camera(atan2(-dirg.x, -dirg.y), -0.05)
			warmup = 120
		"academy":
			# QA view of the Kingsreach Academy campus (--dist=60 --rot=0.5 rad off the front axis, --pitch=-0.12).
			for asite: Dictionary in WorldGen.sites:
				if asite["kind"] != "academy":
					continue
				var ac: Vector2 = asite["pos"]
				var afront := Vector2(sin(float(asite["yaw"])), cos(float(asite["yaw"])))
				var asp: Vector2 = ac + afront.rotated(float(_user_args().get("rot", "0.5"))) * float(_user_args().get("dist", "60"))
				_teleport(asp, 0.0)
				var alk: Vector2 = ac - asp
				player.set_camera(atan2(-alk.x, -alk.y), float(_user_args().get("pitch", "-0.12")))
				region.focus = player.global_position
				region.build_all_now()
				break
			warmup = 90
		"stall":
			# QA close-up of the Nth market stall on Kingsreach's gate road (--n=2), from 6 m in front of it.
			var capst: Dictionary = WorldGen.settlements[1]
			var gas: float = capst["plan"]["gates"][0]
			settlements.focus = Vector3(capst["pos"].x + cos(gas) * (float(capst["radius"]) - 40.0), 0, capst["pos"].y + sin(gas) * (float(capst["radius"]) - 40.0))
			for _i in 4:
				settlements.update_now()
			settlements.finish_prop_jobs()   # QA shot: the town props stream over frames in the game
			var spots: Array = settlements.stalls_by_town.get(capst["id"], [])
			var pick: Array = spots[clampi(int(_user_args().get("n", "3")), 0, maxi(spots.size() - 1, 0))] if not spots.is_empty() else []
			if not pick.is_empty():
				var sp2: Vector2 = pick[1]
				var syaw: float = pick[2]
				var ez := Vector2(sin(syaw), cos(syaw))
				var stand := sp2 + ez * float(_user_args().get("dist", "6.5")) + Vector2(cos(syaw), -sin(syaw)) * float(_user_args().get("side", "1.5"))
				_teleport(stand, 0.0)
				var lk: Vector2 = sp2 - stand
				player.set_camera(atan2(-lk.x, -lk.y), float(_user_args().get("pitch", "-0.16")))
			warmup = 120
		"settle":
			# QA view of any settlement (--shot=settle --town=2), from the first gate's side toward the centre (--dist=14 m
			# beyond the plaza edge, --yaw=deg to swing around the centre).
			var tn: Dictionary = WorldGen.settlements[clampi(int(_user_args().get("town", "2")), 0, WorldGen.settlements.size() - 1)]
			var tc: Vector2 = tn["pos"]
			var ta := deg_to_rad(float(_user_args().get("yaw", "0"))) + (float(tn["plan"]["gates"][0]) if not tn["plan"]["gates"].is_empty() else 0.0)
			var tsp: Vector2 = tc + Vector2(cos(ta), sin(ta)) * (float(tn["plan"]["plaza_r"]) + float(_user_args().get("dist", "14")))
			_teleport(tsp, 0.0)
			var tl: Vector2 = tc - tsp
			player.set_camera(atan2(-tl.x, -tl.y), float(_user_args().get("pitch", "-0.12")))
			settlements.focus = player.global_position
			settlements.update_now()
			settlements.finish_prop_jobs()   # QA shot: the town props stream over frames in the game
			if _user_args().has("air"):      # --air=55: a camera 55 m above the square looking down at it
				hud.visible = false
				player.visible = false
				var acam := Camera3D.new()
				viewport.get_child(0).add_child(acam)
				var back := Vector2(cos(ta), sin(ta)) * float(_user_args().get("airback", "26"))
				acam.global_position = Vector3(tc.x + back.x, WorldGen.height(tc.x, tc.y) + float(_user_args().get("air", "55")), tc.y + back.y)
				acam.look_at(Vector3(tc.x, WorldGen.height(tc.x, tc.y), tc.y))
				acam.fov = 60.0
				acam.current = true
				terrain.focus = Vector3(tc.x, 0, tc.y)
				terrain.build_all_now()
			warmup = 120
		"decal":
			# QA close-up of the Nth decal of a settlement (--town=2 --n=0 --kind=wall|ground|soot), 6 m off its wall / 5 m above the ground.
			var dtn: Dictionary = WorldGen.settlements[clampi(int(_user_args().get("town", "2")), 0, WorldGen.settlements.size() - 1)]
			var dc0: Vector2 = dtn["pos"]
			_teleport(dc0 + Vector2(1.0, 1.0) * 25.0, 0.0)
			settlements.focus = player.global_position
			for _i in 4:
				settlements.update_now()
			settlements.finish_prop_jobs()   # QA shot: the town props stream over frames in the game
			var droot: Node3D = settlements._built.get(dtn["id"])
			var picks: Array[Decal] = []
			var want := String(_user_args().get("kind", "wall"))
			if droot:
				for dd in droot.find_children("*", "Decal", true, false):
					var dcl := dd as Decal
					var is_wall := dcl.cull_mask == TownDecals.WALL_LAYER
					var soot := dcl.texture_albedo != null and String(dcl.texture_albedo.resource_path).ends_with("soot.png")
					if (want == "wall" and is_wall and not soot) or (want == "ground" and not is_wall) or (want == "soot" and soot):
						picks.append(dcl)
			if not picks.is_empty():
				var dsel: Decal = picks[clampi(int(_user_args().get("n", "0")), 0, picks.size() - 1)]
				var dpos := dsel.global_position
				var away := dsel.global_transform.basis.y
				var stand3 := dpos + (away * 6.0 if want != "ground" else Vector3(4.0, 0.0, 4.0))
				_teleport(Vector2(stand3.x, stand3.z), 0.0)
				var dl := dpos - player.global_position
				player.set_camera(atan2(-dl.x, -dl.z), float(_user_args().get("pitch", "-0.12")) if want != "ground" else -0.35)
			print("[decal] ", want, " candidates ", picks.size())
			warmup = 120
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
		if i == warmup - 4 and late_fx.is_valid():
			late_fx.call()
		await get_tree().process_frame
	var rv := viewport.get_render_info
	print("[perf] fps=%d draw_calls=%d objects=%d primitives=%d process_ms=%.2f physics_ms=%.2f nodes=%d skinned=%d" % [Engine.get_frames_per_second(),
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		PerfOverlay.count_skinned(get_tree())])
	if _user_args().has("census"):
		PerfOverlay.print_skeleton_census(get_tree())
	if _user_args().has("ablate"):
		var ab_root: Node = world
		# --ablate=settlement_builder.gd/Kingsreach : descend by script file or name prefix.
		for part in String(_user_args().get("ablate", "")).split("/", false):
			for c in ab_root.get_children():
				var sc: String = c.get_script().resource_path.get_file() if c.get_script() else ""
				if sc == part or String(c.name).begins_with(part):
					ab_root = c
					break
		await PerfOverlay.ablate(get_tree(), viewport, ab_root)
	if _user_args().has("drawcensus"):
		PerfOverlay.print_draw_census(get_tree(), viewport)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot: ", path)
	get_tree().quit()
