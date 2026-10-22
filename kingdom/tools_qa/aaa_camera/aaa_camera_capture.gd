extends Node
## Screenshot harness for the P0 camera + HUD work (docs/design/AAA_POLISH_PLAN.md): sprint camera, combat lock-on with
## threat plate, a player-pinned world marker (on screen and clamped to the edge) and the open technique wheel.
## Boots the real game like tools_qa/feel_capture. Never use --headless.
##   xvfb-run -a -s "-screen 0 2340x1080x24" Godot --path kingdom --rendering-driver vulkan --resolution 2340x1080 \
##       res://tools_qa/aaa_camera/aaa_camera_capture.tscn -- --adult --skipintro --technique-ring --out=/tmp/claude-0/shots

const MAIN := "res://scenes/main.tscn"

var main: Node
var player: Player
var out := "/tmp/claude-0/shots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join("aaa_%s.png" % name))
	print("AAACAP saved ", name, " ", img.get_size())


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _flat_spot() -> Vector2:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	var a := 0.0
	if s.has("plan") and not (s["plan"]["gates"] as Array).is_empty():
		a = float(s["plan"]["gates"][0])
	var dir := Vector2(cos(a), sin(a))
	var d := float(s.get("radius", 60.0)) + 170.0
	for k in 40:
		for side in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var p: Vector2 = c + dir.rotated(side) * d
			var slope := absf(WorldGen.height(p.x + 4, p.y) - WorldGen.height(p.x - 4, p.y)) \
					+ absf(WorldGen.height(p.x, p.y + 4) - WorldGen.height(p.x, p.y - 4))
			if not WorldGen.is_water(p.x, p.y) and slope < 1.0:
				return p
		d += 20.0
	return c + dir * d


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	player = main.player
	var hud: Node = main.hud
	WorldSim.time_of_day = 15.0
	player.set_view(Player.View.THIRD)
	var spot := _flat_spot()
	main._teleport(spot, 0.0)
	player.set_camera(0.0, -0.28)
	await frames(60)
	hud.close_menu()
	await frames(30)
	# 1. Sprint camera: forward + shift, long enough for the FOV and distance to bloom.
	Input.action_press("sprint")
	player.touch_move = Vector2(0, -1)
	await frames(110)
	print("AAACAP sprint fov=%.1f chase_fov=%.1f dist=%.2f speed=%.1f" % [player.camera.fov, player._chase.fov_offset(), player._distance, player.get_real_velocity().length()])
	await shot("1_sprint")
	player.touch_move = Vector2.ZERO
	Input.action_release("sprint")
	await frames(40)
	# 2. Combat lock-on: an orc ahead and to the side, locked, threat plate up.
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var m := CampMonster.new()
	m.species = "orc"
	m.home = Vector2(player.global_position.x, player.global_position.z) + fwd * 9.0 + fwd.orthogonal() * 3.0
	m.home_radius = 30.0
	main.world.add_child(m)
	m.global_position = ground(m.home)
	m.set_physics_process(false)    # stand still: the shot is about framing
	m.set_process(false)
	await frames(40)
	player._invulnerable = 9999.0
	player.health = player.max_health
	player.toggle_lock()
	await frames(60)
	player._invulnerable = 9999.0
	player.health = player.max_health
	await frames(60)
	print("AAACAP lock locked=%s fov=%.1f dist=%.2f combat=%s" % [str(player.locked_target() != null), player.camera.fov, player._distance, str(player._chase_combat)])
	var tp: Control = hud.threat_plates
	print("AAACAP plates picked=%d size=%s vis=%s fade=%s" % [tp._picked.size(), str(tp.size), str(tp.is_visible_in_tree()), str(tp._fade)])
	await shot("2_lockon")
	player.toggle_lock()
	m.queue_free()
	await frames(120)
	# 3. Player-pinned marker: on screen, then clamped at the edge with the camera turned away.
	player.set_camera(0.0, -0.3)
	var here := Vector2(player.global_position.x, player.global_position.z)
	hud.close_menu()
	hud.pin_target(here + Vector2(14, -82), "Old Watchtower", "Travel")
	await frames(40)
	hud.close_menu()
	await frames(20)
	var mk: Control = hud.objective_marker
	print("AAACAP marker shown=%s screen=%s dist=%.1f size=%s vis=%s dim=%.2f pin=%s proc=%s" % [str(mk._shown), str(mk._screen), mk._dist, str(mk.size), str(mk.is_visible_in_tree()), mk.dim, str(mk.pin), str(mk.is_processing())])
	await shot("3_pin_onscreen")
	player.set_camera(-1.25, -0.3)
	hud.close_menu()
	await frames(60)
	await shot("3b_pin_edge")
	player.set_camera(0.0, -0.3)
	hud.clear_pin()
	# 4. Technique wheel.
	var caster: Node = player.get_node_or_null("TechniqueCaster")
	var sk: RefCounted = caster.get("skills")
	var ids: Array = []
	for id: String in sk.techniques:
		if String(sk.techniques[id].get("kind", "active")) == "active" and int(sk.techniques[id].get("tier", 1)) <= 3:
			ids.append(id)
	ids.shuffle()
	var picked := 0
	for tree in ["fire", "wind", "lightning", "water", "earth", "qi", "swordsmanship", "fist_palm"]:
		for id: String in ids:
			if String(sk.techniques[id].get("tree", "")) == tree and picked < 7:
				sk.grant(id)
				picked += 1
				break
	for k in 4:
		if k < sk.ranks.size():
			sk.loadout[k] = sk.ranks.keys()[k]
	sk.qi = sk.qi_max()
	if sk.ranks.size() > 2:
		sk.cooldowns[sk.ranks.keys()[2]] = 4.2
	hud.close_menu()
	await frames(10)
	var wheel: Control = hud.technique_wheel
	wheel.caster = caster
	print("AAACAP ranks=%d caster=%s" % [sk.ranks.size(), str(caster)])
	var opened: bool = wheel.open_wheel("key")
	print("AAACAP wheel opened=%s entries=%d time_scale=%.2f" % [str(opened), wheel.entries.size(), Engine.time_scale])
	await frames(30)
	wheel._point(wheel.ring_centre() + Vector2(110, -90))
	await frames(20)
	await shot("4_wheel")
	wheel.close_wheel(false)
	print("AAACAP wheel closed time_scale=%.2f" % Engine.time_scale)
	await frames(10)
	print("AAACAP DONE")
	get_tree().quit()
