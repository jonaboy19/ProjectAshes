extends SceneTree
## Hidden Vale / exploration QA capture with a LIGHT world (terrain, water, region dressing + exploration director,
## ambient life and the game's own sky/sun; no villages, population or HUD) so it fits next to other captures in the
## shared container. Steps: views, POIs (by id), the discovery cutscene (PNGs at given seconds), the Discoveries journal.
##   xvfb-run -a godot --path kingdom --rendering-driver vulkan --resolution 960x540 -s res://tools_qa/valley/valley_capture.gd -- --out=DIR --r1nohorizon [--only=a,b]
## (never --headless: it needs the GPU)
const HV := preload("res://scripts/world/hidden_valley.gd")
const POIS := preload("res://scripts/world/region_pois.gd")

var out_dir := "/tmp/claude-0/shots/valley"
var only: PackedStringArray = []
var steps: Array = []
var world: Node3D
var terrain: Node3D
var water: Node3D
var region: Node3D
var player: Node3D
var hudl: CanvasLayer
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var frame := 0
var idx := -1
var phase := 0
var wait := 0
var t0 := 0
var cut_times: Array = []
var cut_i := 0
var perf_lines: Array[String] = []
var samples: PackedFloat32Array = []
var last_us := 0


func _life() -> Node:
	return root.get_node("Life")


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	t0 = Time.get_ticks_msec()
	world = Node3D.new()
	world.name = "World"
	root.add_child.call_deferred(world)
	call_deferred("_boot")


func _boot() -> void:
	_build_environment()
	var ts: GDScript = load("res://scripts/world/terrain_streamer.gd")
	terrain = ts.new()
	terrain.set("view_radius", 3)   # 7 x 7 chunks: keeps the capture small enough for the shared container
	world.add_child(terrain)
	water = (load("res://scripts/world/water_streamer.gd") as GDScript).new()
	world.add_child(water)
	region = (load("res://scripts/world/region_dressing.gd") as GDScript).new()
	world.add_child(region)
	var fx: Node = (load("res://scripts/world/ambient_fx.gd") as GDScript).new()
	fx.name = "AmbientFX"
	world.add_child(fx)
	var amb: Node = (load("res://scripts/world/ambient_life.gd") as GDScript).new()
	world.add_child(amb)
	player = Node3D.new()
	player.name = "DummyPlayer"
	world.add_child(player)
	_life().set("player", player)
	cam = Camera3D.new()
	cam.far = 4000.0
	world.add_child(cam)
	hudl = CanvasLayer.new()
	root.add_child(hudl)
	print("[valley] light world ready")


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/storybook_sky.gdshader")
	sky_mat.set_shader_parameter("panorama", load("res://assets/generated/sky/kloofendal_43d_clear_puresky_2k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.ambient_light_color = Color("ffe2bd")
	env.ambient_light_sky_contribution = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.tonemap_white = 7.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.07
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("c9d4e6")
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.28
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 0.8
	world.add_child(sun)


## main.gd's _update_daylight, without the baker/weather/audio parts.
func _daylight(t: float) -> void:
	root.get_node("WorldSim").set("time_of_day", t)
	var day_amount := clampf(sin((t - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	sun.rotation = Vector3(-lerpf(0.15, 1.1, day_amount), PI * 0.25 + (t - 12.0) / 12.0 * PI * 0.5, 0)
	var night := 1.0 - smoothstep(0.0, 0.25, day_amount)
	var sky_amount := clampf(day_amount * 1.8, 0.0, 1.0)
	sun.light_energy = lerpf(lerpf(0.05, 1.7, day_amount), 0.42, night)
	sun.light_color = Color("ff9a5a").lerp(Color("ffd9a2"), day_amount).lerp(Color("8fa8ff"), night)
	env.ambient_light_energy = lerpf(lerpf(0.25, 0.7, sky_amount), 0.4, night)
	env.fog_light_color = Color("1b2238").lerp(Color("c9d4e6"), sky_amount)
	env.background_energy_multiplier = lerpf(0.08, 1.0, sky_amount) + night * 0.12
	var lamp := 1.6 * night
	for l in get_nodes_in_group("street_lamp"):
		(l as OmniLight3D).light_energy = lamp
		(l as OmniLight3D).visible = lamp > 0.01


func _build_steps() -> void:
	steps = [
		{"name": "gorge_entrance", "at": HV.gorge_world(HV.GORGE_MOUTH + 70.0), "look": HV.gorge_world(HV.GORGE_MOUTH - 40.0), "up": 1.8, "look_up": 3.0, "hour": 14.5, "fov": 62},
		{"name": "gorge_inside", "at": HV.gorge_world(330.0), "look": HV.gorge_world(250.0), "up": 1.7, "look_up": 6.0, "hour": 14.5, "fov": 62},
		{"type": "cutscene", "name": "cut", "times": [1.6, 5.2, 8.8, 11.6], "hour": 14.5},
		{"name": "vale_day_meadow", "at": HV.w(70.0, 40.0), "look": HV.w(-60.0, -20.0), "up": 2.0, "look_up": 6.0, "hour": 14.5, "fov": 66},
		{"name": "vale_day_aerial", "at": HV.w(150.0, 60.0), "look": HV.w(-80.0, -10.0), "up": 45.0, "look_up": 0.0, "hour": 14.5, "fov": 66},
		{"name": "vale_day_pond", "at": HV.w(60.0, -15.0), "look": HV.w(20.0, -65.0), "up": 1.7, "look_up": 1.0, "hour": 14.5, "fov": 64},
		{"name": "vale_day_falls", "at": HV.w(-70.0, 12.0), "look": HV.w(-165.0, 10.0), "up": 2.2, "look_up": 26.0, "hour": 14.5, "fov": 66},
		{"name": "vale_dusk_meadow", "at": HV.w(70.0, 40.0), "look": HV.w(-60.0, -20.0), "up": 2.0, "look_up": 6.0, "hour": 16.7, "fov": 66},
		{"name": "vale_dusk_aerial", "at": HV.w(150.0, 60.0), "look": HV.w(-80.0, -10.0), "up": 45.0, "look_up": 0.0, "hour": 16.7, "fov": 66},
		{"name": "vale_stones", "at": HV.stones_world() + Vector2(14, 10), "look": HV.stones_world(), "up": 1.8, "look_up": 2.0, "hour": 15.5, "fov": 62},
		{"name": "vale_ruin", "at": HV.w(38.0, 70.0), "look": HV.w(38.0, 108.0), "up": 2.0, "look_up": 4.0, "hour": 15.5, "fov": 62},
		{"name": "vale_knoll", "at": HV.w(-15.0, -40.0), "look": HV.knoll_world(), "up": 2.0, "look_up": 8.0, "hour": 15.0, "fov": 62},
		{"name": "baseline_meadow", "at": Vector2(-1500.0, 300.0), "look": Vector2(-1450.0, 350.0), "up": 2.0, "look_up": 6.0, "hour": 14.5, "fov": 66},
	]
	for id in ["kestrel", "hind_shrine", "builders_stone", "surveyor", "moon_hollow", "leaning_oak", "broken_lances", "hermit", "shimmer_fen"]:
		var pl: Dictionary = POIS.placed.get(id, {})
		if pl.is_empty():
			continue
		var p: Vector2 = pl["pos"]
		var yaw: float = pl["yaw"]
		var d := Vector2(sin(yaw), cos(yaw))
		var best := -1.0e9
		for k in 8:   # stand on the lowest ground around it, looking up at the place
			var dk := Vector2.from_angle(TAU * k / 8.0)
			var h := -WorldGen.height(p.x + dk.x * 12.0, p.y + dk.y * 12.0)
			if h > best or best < -1.0e8:
				best = h
				d = dk
		steps.append({"name": "poi_" + id, "at": p + d * 8.5, "look": p, "up": 1.7, "look_up": 1.4, "fov": 68,
			"hour": 22.0 if id == "shimmer_fen" else 15.0})
	steps.append({"type": "journal", "name": "journal"})
	if not only.is_empty():
		steps = steps.filter(func(s: Dictionary) -> bool: return String(s["name"]) in only)


func _process(_dt: float) -> bool:
	frame += 1
	if Time.get_ticks_msec() - t0 > 1500 * 1000:
		print("WATCHDOG")
		_finish()
		return true
	if frame < 60 or terrain == null:
		return false
	if frame == 60:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		var disc: RefCounted = _life().discovery
		if disc.places.is_empty():
			disc.build_from_world(_life().lore.places_in_region())
		_build_steps()
		_next()
		return false
	if idx >= steps.size():
		_finish()
		return true
	var st: Dictionary = steps[idx]
	match String(st.get("type", "view")):
		"view":
			if phase == 0:
				wait -= 1
				if wait <= 0:
					phase = 1
					wait = 40
					samples.clear()
					last_us = Time.get_ticks_usec()
			else:
				var now := Time.get_ticks_usec()
				samples.append((now - last_us) / 1000.0)
				last_us = now
				wait -= 1
				if wait <= 0:
					_save(String(st["name"]))
					_next()
		"cutscene":
			_cutscene_tick()
		"journal":
			wait -= 1
			if wait <= 0:
				_save("journal")
				_next()
	return false


func _director() -> Node:
	return region.get_node("ExplorationDirector")


func _stream_to(at: Vector2, hour: float) -> void:
	_daylight(hour)
	var pos := Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y)
	player.global_position = pos
	terrain.set("focus", pos)
	terrain.call("build_all_now")
	water.set("focus", pos)
	water.call("build_all_now")
	region.set("focus", pos)
	var built: Dictionary = region.get("_built")
	for site: Dictionary in WorldGen.sites:
		if at.distance_to(site["pos"]) < 260.0 and not built.has(site["id"]):
			built[site["id"]] = region.call("_build", site)
	var dir := _director()
	dir.set("focus", pos)
	var lk: Node = dir.get("look")
	lk.set("focus", pos)
	lk.call("update_now")
	for n in world.get_children():
		if n.has_method("scatter") or n.has_method("_group"):
			n.set("focus", pos)
	var q: Array = region.get("_queue")
	while not q.is_empty():
		var item: Array = q.pop_front()
		if not is_instance_valid(item[0]):
			continue
		if item[2] == "part":
			region.call("_build_part", item[0], item[1], item[1]["parts"][item[3]])
		else:
			region.call("_build_light", item[0], item[1]["lights"][item[3]])


func _next() -> void:
	idx += 1
	phase = 0
	if idx >= steps.size():
		return
	var st: Dictionary = steps[idx]
	var type := String(st.get("type", "view"))
	print("[valley] step ", st["name"])
	if type == "view":
		var at: Vector2 = st["at"]
		var look: Vector2 = st["look"]
		_stream_to(at, float(st.get("hour", 15.0)))
		var gy := WorldGen.height(at.x, at.y)
		var ly := WorldGen.height(look.x, look.y)
		var lv := WorldGen.water_level_at(look.x, look.y)
		if not is_nan(lv):
			ly = maxf(ly, lv)
		cam.global_position = Vector3(at.x, gy + float(st.get("up", 2.0)), at.y)
		cam.look_at(Vector3(look.x, ly + float(st.get("look_up", 1.5)), look.y))
		cam.fov = float(st.get("fov", 62.0))
		cam.current = true
		wait = 120
	elif type == "cutscene":
		cam.current = false
		_stream_to(HV.gorge_world(185.0), float(st.get("hour", 14.5)))
		_life().discovery.found.erase(HV.place_id())
		_director().call("start_vale_sequence", player)
		# Like main.gd: the cutscene streams the ground around its camera path (async, as in game).
		terrain.set("focus", Engine.get_meta("stream_focus", terrain.get("focus")))
		water.set("focus", terrain.get("focus"))
		cut_times = st["times"]
		cut_i = 0
		wait = 0
	elif type == "journal":
		for id in ["kestrel", "hind_shrine", "builders_stone", "surveyor", "hermit", "silent_pool"]:
			for s: Dictionary in WorldGen.sites:
				if String(s.get("poi", "")) == id:
					_life().discovery.discover("site:%s:%d:%d" % [s["name"], roundi(s["pos"].x), roundi(s["pos"].y)], 12)
		_life().discovery.discover(HV.place_id(), 20)
		cam.current = false
		var menu: Control = (load("res://scripts/ui/gamemenu/game_menu.gd") as GDScript).call("open", hudl, "journal")
		var page: Control = menu.call("_page", "journal")
		(page.get("_ld") as Object).call("select", "discoveries")
		wait = 40


func _cutscene_tick() -> void:
	var v: Variant = _director().get("vista")
	if v == null or not is_instance_valid(v):
		if cut_i >= cut_times.size() or frame % 120 == 0:
			_next()
		return
	var cp: Variant = (v as Node).get("cut")
	if cp == null:
		return
	var t: float = cp.get("elapsed")
	if cut_i < cut_times.size() and t >= float(cut_times[cut_i]):
		_save("cut_%d" % (cut_i + 1))
		cut_i += 1


## GeometryInstance3D nodes of the vale/POI presenter inside their visibility range and in front of the camera: the
## presenter's share of the draw calls (the terrain streamer's own MultiMeshes are counted in `draws` only).
func _count_dressing() -> int:
	var n := 0
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	for g in _director().get("look").find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var to := gi.global_position - cp
		var d := to.length()
		if (gi.visibility_range_end > 0.0 and d > gi.visibility_range_end) or d < gi.visibility_range_begin or (d > 4.0 and to.dot(fwd) < 0.0):
			continue
		var surfaces := 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			surfaces = maxi(1, (gi as MeshInstance3D).mesh.get_surface_count())
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			surfaces = maxi(1, (gi as MultiMeshInstance3D).multimesh.mesh.get_surface_count())
		n += surfaces
	return n


func _save(nm: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [out_dir, nm]
	img.save_png(p)
	var s := samples.duplicate()
	s.sort()
	var avg := 0.0
	for x in s:
		avg += x
	avg /= maxf(1.0, s.size())
	var vp: Viewport = root.get_viewport()
	var line := "%s dressing_nodes=%d avg_ms=%.2f fps=%.0f draws=%d prims=%d" % [nm, _count_dressing(), avg, 1000.0 / maxf(avg, 0.01),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)]
	perf_lines.append(line)
	print("[perf] ", line)
	print("SAVED ", p)


func _finish() -> void:
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(perf_lines) + "\n")
		f.close()
	quit(0)
