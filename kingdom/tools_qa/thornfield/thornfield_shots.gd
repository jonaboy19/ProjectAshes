extends Node
## QA driver for Thornfield as a place (F8): four views of the slice town.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom --rendering-driver vulkan -- --adult --quality=high \
##       --qa=res://tools_qa/thornfield/thornfield_shots.gd [--out=/tmp/claude-0/shots/thornfield] [--only=brewery,plaza,farm,forest]
## Saves <out>_brewery.png (the Brewery with Hesta, kegs and the tithe granary), <out>_plaza.png (named residents about the
## well), <out>_farm.png (pens, pigs, hens, sheep and the windmill) and <out>_forest.png (the forest edge at dusk with the pack
## prowling). Never run with --headless (black image). Gate on free memory first (ashes-cloud-testing).

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const Roster := preload("res://scripts/world/thornfield/roster.gd")
const WolfThreat := preload("res://scripts/world/thornfield/wolf_threat.gd")

var main: Node
var cam: Camera3D
var out_base := "/tmp/claude-0/shots/thornfield"


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	out_base = String(args.get("out", out_base))
	var only := String(args.get("only", "brewery,plaza,farm,forest"))
	DirAccess.make_dir_recursive_absolute(out_base.get_base_dir())
	main.hud.visible = false
	main.player.visible = false
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	main.world.add_child(cam)
	var town := Sites.settlement()
	var hub: Node = main.world.get_node_or_null("ThornfieldHub")
	print("hub ", hub, " roster rows ", Roster.bound_rows().size())

	if only.contains("brewery"):
		var b := Sites.brewery()
		WorldSim.time_of_day = 14.0
		var look := Sites.to_world(b, Vector2(-1.0, 2.0))
		var from := Sites.to_world(b, Vector2(4.0, 22.0))
		await _shot(from, look, "brewery", 2.4, 2.2)
	if only.contains("plaza"):
		WorldSim.time_of_day = 11.0
		var c: Vector2 = town["pos"]
		var plaza_r: float = town["plan"]["plaza_r"]
		# Put the named residents about the well, as if it were market hour, before the crowd is chosen.
		var k := 0
		for row: Variant in Roster.bound_rows():
			var a := float(k) * 0.9
			var p := c + Vector2(cos(a), sin(a)) * (plaza_r * 0.55 + float(k % 3) * 2.0)
			WorldSim.pos[int(row)] = p
			WorldSim.target[int(row)] = p
			WorldSim.phase[int(row)] = 2
			k += 1
		var from2 := c + Vector2(plaza_r * 0.95, plaza_r * 0.35)
		await _shot(from2, c, "plaza", 2.2, 3.0)
		var named := 0
		for v in main.get_tree().get_nodes_in_group("villager"):
			if Roster.is_named(int(v.get("person") if v.get("person") != null else -1)):
				named += 1
		print("NAMED_BODIES ", named)
	if only.contains("farm"):
		var f := Sites.farm()
		WorldSim.time_of_day = 15.0
		var pens := Sites.to_world(f, Vector2(14.0, -8.0))
		var from3 := Sites.to_world(f, Vector2(2.0, 14.0))
		await _shot(from3, pens, "farm", 2.6, 4.5)
	if only.contains("forest"):
		WorldSim.time_of_day = 19.3
		var fields := Sites.place_pos("thornfield_fields")
		var threat: Node = hub.get("threat") if hub != null else null
		var den := Vector2.INF
		if threat != null:
			threat.call("ensure_den")
			den = threat.call("_den_pos")
		var dir := (den - fields).normalized() if den != Vector2.INF else Vector2(0, -1)
		var edge := fields + dir * 55.0
		var from4 := fields + dir * 30.0
		if threat != null:
			threat.call("probe", fields + dir * 62.0, 3)
		await _shot(from4, edge + dir * 40.0, "forest", 1.8, 4.5)
	get_tree().quit(0)


## Builds the region sites around p now (build_all_now() would build the whole world).
func _build_near(p: Vector2) -> void:
	var rd = main.region
	for site in WorldGen.sites:
		if (site["pos"] as Vector2).distance_to(p) < rd.BUILD and not rd._built.has(site["id"]) and rd._in_season(site):
			rd._built[site["id"]] = rd._build(site)
	while not rd._queue.is_empty():
		var item: Array = rd._queue.pop_front()
		if not is_instance_valid(item[0]):
			continue
		if item[2] == "part":
			rd._build_part(item[0], item[1], item[1]["parts"][item[3]])
		else:
			rd._build_light(item[0], item[1]["lights"][item[3]])


func _mem(tag: String) -> void:
	print("MEM ", tag, " ", OS.get_static_memory_usage() / 1048576, " MB")


func _shot(from: Vector2, at: Vector2, name: String, height: float, settle: float) -> void:
	_mem("before " + name)
	main.call("_teleport", from, 0.0)
	_mem("teleported")
	main.region.focus = main.player.global_position
	main.ambient.focus = main.player.global_position
	_build_near(from)
	_build_near(at)
	for n in main.region.get_children():
		if n.has_method("refresh_now"):
			n.call("refresh_now")
	main.terrain.focus = main.player.global_position
	_mem("built sites")
	var gy := WorldGen.height(from.x, from.y) + height
	cam.global_position = Vector3(from.x, gy, from.y)
	cam.look_at(Vector3(at.x, WorldGen.height(at.x, at.y) + 1.4, at.y))
	cam.current = true
	# Let the crowd, the animals and the light settle (AmbientLife and PopulationLOD spawn on their own timers).
	await get_tree().create_timer(settle).timeout
	main.population.focus = main.player.global_position
	main.population.refresh()
	for i in 40:
		await get_tree().process_frame
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [out_base, name]
	img.save_png(path)
	print("SHOT ", path)
