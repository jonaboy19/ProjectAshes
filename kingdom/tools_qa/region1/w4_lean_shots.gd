extends SceneTree
## W4 lean capture: no game boot (no population, HUD, story), just WorldGen + TerrainStreamer + WaterStreamer + RegionDressing + Region1Look
## around each view of tools_qa/region1/w4_views.json (same view format as look_capture.gd). One PNG per view.
##   Godot --path kingdom --resolution 1600x900 -s res://tools_qa/region1/w4_lean_shots.gd -- --out=<abs dir> [--only=a,b] [--world_macro=valencious|noise]
##       [--views=res://tools_qa/region1/w4_views.json] [--tag=x]
var views: Array = []
var out_dir := ""
var tag := ""
var only: PackedStringArray = []
var terrain: Node3D
var water: Node3D
var region: Node3D
var cam: Camera3D
var world: Node3D
var WG: GDScript


func _initialize() -> void:
	var vp := "res://tools_qa/region1/w4_views.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
		elif a.begins_with("--views="): vp = a.substr(8)
		elif a.begins_with("--tag="): tag = a.substr(6)
	for v: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(vp)) as Dictionary)["views"]:
		if only.is_empty() or String(v["name"]) in only:
			views.append(v)
	DirAccess.make_dir_recursive_absolute(out_dir)
	WG = load("res://scripts/world/world_gen.gd")
	WG.setup(1066)
	world = Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0006
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	world.add_child(sun)
	terrain = load("res://scripts/world/terrain_streamer.gd").new()
	world.add_child(terrain)
	water = load("res://scripts/world/water_streamer.gd").new()
	world.add_child(water)
	region = load("res://scripts/world/region_dressing.gd").new()
	world.add_child(region)
	world.add_child(preload("res://scripts/region1/region1_root.gd").new())
	cam = Camera3D.new()
	cam.far = 3000.0
	world.add_child(cam)
	_run.call_deferred()


func _run() -> void:
	for v: Dictionary in views:
		print("VIEW ", v["name"], " start ", Time.get_ticks_msec() / 1000)
		var at := Vector2(float(v["at"][0]), float(v["at"][1]))
		var look := Vector2(float(v["look"][0]), float(v["look"][1]))
		var f3: Vector3 = Vector3(at.x, WG.height(at.x, at.y), at.y)
		terrain.focus = f3
		terrain.view_radius = 2
		region.focus = f3
		for n in [terrain, water]:
			n.set("focus", f3)
		var built: Dictionary = region.get("_built")
		for site: Dictionary in WG.sites:
			if at.distance_to(site["pos"]) < 200.0 and not built.has(site["id"]):
				built[site["id"]] = region.call("_build", site)
		var look_node: Node = region.get_node_or_null("Region1Look")
		var r1 := world.get_node_or_null("Region1Root")
		for ch in world.get_children():
			if ch.get_script() != null and String(ch.get_script().resource_path).ends_with("region1_root.gd"):
				r1 = ch
		if r1:
			for n in r1.get_children():
				if n.get("focus") != null:
					n.set("focus", f3)
					if n.has_method("update_now"):
						n.call("update_now")
		print("  terrain build ", Time.get_ticks_msec() / 1000)
		terrain.build_all_now()
		print("  terrain done ", Time.get_ticks_msec() / 1000)
		if water.has_method("build_all_now"):
			water.set("focus", f3)
			water.call("build_all_now")
		for i in 6:
			await process_frame
		var q: Array = region.get("_queue")
		while not q.is_empty():
			var item: Array = q.pop_front()
			if not is_instance_valid(item[0]):
				continue
			if item[2] == "part":
				region.call("_build_part", item[0], item[1], item[1]["parts"][item[3]])
			else:
				region.call("_build_light", item[0], item[1]["lights"][item[3]])
		root.get_node("WorldSim").set("time_of_day", float(v.get("hour", 15.0)))
		var gy: float = maxf(WG.height(at.x, at.y), WG.water_level_at(at.x, at.y) if not is_nan(WG.water_level_at(at.x, at.y)) else -1e9)
		var ly: float = WG.height(look.x, look.y)
		cam.global_position = Vector3(at.x, gy + float(v.get("up", 3.0)), at.y)
		cam.look_at(Vector3(look.x, ly + float(v.get("look_up", 2.0)), look.y))
		cam.fov = float(v.get("fov", 60.0))
		cam.current = true
		for i in 25:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var p := "%s/%s%s.png" % [out_dir, v["name"], ("_" + tag) if tag != "" else ""]
		img.save_png(p)
		print("SAVED ", p)
	quit(0)
