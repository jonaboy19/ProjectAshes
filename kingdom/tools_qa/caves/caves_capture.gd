extends SceneTree
## Caves QA: boots the real game once, then (1) walks into one cave per theme (7) through its real
## DungeonDoor and shoots the spawn room, a middle room and the boss chamber, printing draw calls and
## triangles of the game viewport, and (2) shoots hidden entrances from outside (waterfall, vines, rockfall,
## night). Never pass --headless (needs the GPU). Example:
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan \
##       -s res://tools_qa/caves/caves_capture.gd -- --adult --out=/tmp/claude-0/shots/caves [--only=cave,crypt] [--quality=medium]
## Build the sheet afterwards with tools_qa/caves/make_sheet.py.

var View: GDScript
var Plan: GDScript
var Gen: GDScript

var main: Node
var view: Node
var out_dir := "/tmp/claude-0/shots/caves"
var only: PackedStringArray = []
var frame := 0
var started := false
var perf: Array[String] = []


func _initialize() -> void:
	View = load("res://scripts/world/region_caves_view.gd")
	Plan = load("res://scripts/world/region_caves.gd")
	Gen = load("res://scripts/interiors/dungeon_gen.gd")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ps := load("res://scenes/main.tscn") as PackedScene
	main = ps.instantiate()
	root.add_child.call_deferred(main)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 600 and not started:
		started = true
		_run()
	return false


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, extra := "") -> void:
	await _wait(45)
	var sub: SubViewport = main.get("viewport")
	var rv: Viewport = sub if sub else root.get_viewport()
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	var line := "%s draws=%d prims=%d objs=%d %s" % [name,
		rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME), extra]
	perf.append(line)
	print("[caves] ", line)


func _face(player: Node3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	player.call("set_camera", atan2(-d.x, -d.z), -0.2)


func _site_of_theme(theme: String, prefer_visible := true) -> Dictionary:
	var best := {}
	for s: Dictionary in Plan.cave_sites():
		if s["cave"]["theme"] == theme:
			if best.is_empty() or (prefer_visible and not s["hidden"] and best["hidden"]):
				best = s
	return best


func _site_named(n: String) -> Dictionary:
	for s: Dictionary in Plan.cave_sites():
		if String(s["name"]) == n:
			return s
	return {}


func _run() -> void:
	var hud: Node = main.get("hud")
	if hud:
		hud.visible = false
	var player: Node3D = main.get("player")
	view = View.new()
	(main.get("region") as Node).add_child(view)
	root.get_node("WorldSim").set("time_of_day", 15.0)
	for theme: String in Gen.THEMES:
		if not only.is_empty() and not (theme in only):
			continue
		await _interior(theme, player)
	if only.is_empty() or "ext" in only:
		await _exteriors(player)
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(perf) + "\n")
	f.close()
	print("DONE")
	quit(0)


func _interior(theme: String, player: Node3D) -> void:
	var s := _site_of_theme(theme)
	if s.is_empty():
		return
	var id: String = s["cave"]["dungeon_id"]
	var p: Vector2 = s["pos"]
	main.call("_teleport", p + Vector2(sin(float(s["yaw"])), cos(float(s["yaw"]))) * 6.0, 0.0)
	view._built[id] = view._build(s)
	await _wait(10)
	var door = view.door_for(id)
	door.monitoring = true
	door.enter(player)
	await _wait(20)
	var interior = door.interior
	var g: Dictionary = interior.g
	_face(player, player.global_position, interior.global_position + Gen.cell_pos(g, g["rooms"][0]["center"]))
	await _shot("%s_1_entrance" % theme, "tris=%d rooms=%d tier=%d" % [int(interior.get_meta("tris")), g["rooms"].size(), g["tier"]])
	# a middle room with something in it (first chest / lore / node), else room 1
	var rid := 1
	for r: Dictionary in g["rooms"]:
		if r["role"] in ["lore", "resource", "vault", "den"]:
			rid = r["id"]
			break
	var c: Vector2i = g["rooms"][rid]["center"]
	var at: Vector3 = interior.global_position + Gen.cell_pos(g, c) + Vector3(0, 0.3, 0)
	player.global_position = at + Vector3(0, 0, 3.0)
	player.velocity = Vector3.ZERO
	_face(player, player.global_position, at)
	player.reset_physics_interpolation()
	await _shot("%s_2_%s" % [theme, g["rooms"][rid]["role"]])
	var bc: Vector2i = g["rooms"][g["boss_room"]]["center"]
	var bat: Vector3 = interior.global_position + Gen.cell_pos(g, bc) + Vector3(0, 0.3, 0)
	player.global_position = bat + Vector3(0, 0, 7.0)
	player.velocity = Vector3.ZERO
	_face(player, player.global_position, bat)
	player.reset_physics_interpolation()
	await _shot("%s_3_boss" % theme, "boss_lv=%d" % int(g["content"]["boss"]["level"]))
	door.leave()
	await _wait(10)


func _exteriors(player: Node3D) -> void:
	var shots := [["Hollin Falls Grotto", 17.5, 9.0, "ext_waterfall"], ["Foxlantern Cave", 15.0, 9.0, "ext_vines"],
		["Stonehollow Barrow", 15.0, 10.0, "ext_rockfall"], ["Scarlight Grotto", 22.5, 10.0, "ext_night"], ["Bramblewick Burrow", 15.0, 9.0, "ext_visible"]]
	for e: Array in shots:
		var s := _site_named(String(e[0]))
		if s.is_empty():
			continue
		var p: Vector2 = s["pos"]
		var yaw := float(s["yaw"])
		var at := p + Vector2(sin(yaw), cos(yaw)) * float(e[2])
		root.get_node("WorldSim").set("time_of_day", float(e[1]))
		main.call("_teleport", at, 0.0)
		var id: String = s["cave"]["dungeon_id"]
		if not view._built.has(id):
			view._built[id] = view._build(s)
		var d := p - at
		player.call("set_camera", atan2(-d.x, -d.y), -0.12)
		await _wait(40)
		await _shot(String(e[3]))
