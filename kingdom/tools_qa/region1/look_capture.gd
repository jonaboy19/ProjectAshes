extends SceneTree
## Region 1 look-dev capture: boots the real game once, then flies a free camera through a list of
## views (data JSON) and saves one PNG per view plus a perf line (avg / p95 frame ms, draw calls,
## primitives) measured with vsync off. Used for docs/regions/look/ before/after sheets.
##   Godot --path kingdom --resolution 1920x1080 -s res://tools_qa/region1/look_capture.gd -- --adult \
##       --views=res://tools_qa/region1/look_views.json --out=<abs dir> [--only=name,name] [--quality=high] [--tag=before]
## Never pass --headless (needs the GPU). A wall-clock watchdog quits after --budget seconds (default 900).
##
## View: {"name", "at": [x, z], "look": [x, z], "up": metres above ground at `at` (default 2.2),
##        "look_up": metres above ground at `look` (default 1.5), "hour": 16.2, "fov": 60,
##        "stand": false (true = keep the player visible and use the game camera instead)}

var views: Array = []
var out_dir := ""
var tag := ""
var weather_arg := "clear"   # QA captures pin the weather (the daily schedule can roll fog/rain); --weather=auto leaves it
var _env_saved: Dictionary = {}
var _t3d_saved: Dictionary = {}
var _mat_saved: Dictionary = {}
var aa_arg := 0
var quickshot := false
var only: PackedStringArray = []
var budget_s := 900
var main: Node
var cam: Camera3D
var frame := 0
var t0 := 0
var idx := -1
var phase := 0
var wait := 0
var samples: PackedFloat32Array = []
var last_us := 0
var perf_lines: Array[String] = []
var _finishing := false


func _initialize() -> void:
	var views_path := "res://tools_qa/region1/look_views.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="): views_path = a.substr(8)
		elif a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--tag="): tag = a.substr(6)
		elif a.begins_with("--aa="): aa_arg = int(a.substr(5))   # Quality.aa_mode: 0 tier default, 1 FXAA+FSR1, 2 TAA, 3 FSR2 (FSR2 + Terrain3D crashes on 4.6.3)
		elif a == "--quickshot": quickshot = true
		elif a.begins_with("--weather="): weather_arg = "" if a.substr(10) == "auto" else a.substr(10)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
		elif a.begins_with("--budget="): budget_s = int(a.substr(9))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(views_path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("views") is Array:
		push_error("look capture views file must be JSON with a 'views' array: " + views_path)
		quit(2)
		return
	for entry: Variant in (parsed as Dictionary)["views"]:
		if not entry is Dictionary or not (entry as Dictionary).has("name"):
			push_error("every look capture view must be an object with a name: " + views_path)
			quit(2)
			return
		var view := entry as Dictionary
		if only.is_empty() or String(view["name"]) in only:
			views.append(view)
	if views.is_empty():
		push_error("look capture selected zero views from: " + views_path)
		quit(2)
		return
	if out_dir.is_empty():
		push_error("look capture requires --out=<absolute output directory>")
		quit(2)
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_error != OK:
		push_error("could not create look capture output directory: " + out_dir)
		quit(2)
		return
	t0 = Time.get_ticks_msec()
	var ps := load("res://scenes/main.tscn") as PackedScene
	main = ps.instantiate()
	root.add_child.call_deferred(main)


func _process(_dt: float) -> bool:
	if _finishing:
		return false
	frame += 1
	if Time.get_ticks_msec() - t0 > budget_s * 1000:
		print("WATCHDOG quit")
		_finish()
		return false
	if frame < 600:
		return false
	if frame == 600:
		if aa_arg > 0 and root.has_node("Quality"):
			root.get_node("Quality").call("set_aa_mode", aa_arg)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		if not weather_arg.is_empty() and main.get("weather"):
			(main.get("weather") as Node).call("set_weather", weather_arg, 0.0)
			(main.get("weather") as Node).set("auto", false)
		var hud: Node = main.get("hud")
		if hud:
			hud.visible = false
		cam = Camera3D.new()
		cam.far = 4000.0
		(main.get("world") as Node3D).add_child(cam)
		_next()
		return false
	if idx >= views.size():
		_finish()
		return false
	# Pin the clock every frame: intro/sleep events advance_hours() and drifted shots to night (env pass 2026-10-05).
	root.get_node("WorldSim").set("time_of_day", float((views[idx] as Dictionary).get("hour", 16.2)))
	match phase:
		0:   # streaming / warm-up
			wait -= 1
			if wait <= 0:
				if quickshot:
					# Save immediately after the requested warm-up. Full-game scenes can
					# hit renderer teardown/resource limits before the longer perf window ends.
					_save()
					_finish()
					return false
				phase = 1
				_clear_overlays()
				wait = 90
				samples.clear()
				last_us = Time.get_ticks_usec()
		1:   # timing
			var now := Time.get_ticks_usec()
			samples.append((now - last_us) / 1000.0)
			last_us = now
			wait -= 1
			if wait <= 0:
				_save()
				_next()
	return false


func _next() -> void:
	idx += 1
	if idx >= views.size():
		return
	var v: Dictionary = views[idx]
	_clear_overlays()
	root.get_node("WorldSim").set("time_of_day", float(v.get("hour", 16.2)))
	var at := Vector2(float(v.get("at", [0, 0])[0]), float(v.get("at", [0, 0])[1]))
	var look := Vector2(float(v.get("look", [0, 0])[0]), float(v.get("look", [0, 0])[1]))
	if v.has("gate"):
		# Kingsreach gate market (the owner's reference view): `in` metres inside the first gate of settlement `gate`, looking out of the gate.
		var gs: Dictionary = WorldGen.settlements[int(v["gate"])]
		var ga: float = gs["plan"]["gates"][0]
		var gd := Vector2(cos(ga), sin(ga))
		at = (gs["pos"] as Vector2) + gd * (float(gs["radius"]) - float(v.get("in", 42.0)))
		look = at + gd * 80.0
	if v.has("site"):
		for st: Dictionary in WorldGen.sites:
			if String(st.get("r1id", "")).begins_with(String(v["site"])):
				var sp: Vector2 = st["pos"]
				var so: Array = v.get("site_at", [0.0, 14.0])
				var sl: Array = v.get("site_look", [0.0, 5.2])
				at = sp + Vector2(float(so[0]), float(so[1]))
				look = sp + Vector2(float(sl[0]), float(sl[1]))
	var player: Node3D = main.get("player")
	# Stream the world around the camera spot: the game follows the player.
	main.call("_teleport", at, 0.0)
	var region: Node = main.get("region")
	if region:
		# Only the sites in build range (RegionDressing.build_all_now builds the whole world: ~40 s per view).
		region.set("focus", player.global_position)
		var built: Dictionary = region.get("_built")
		for site: Dictionary in WorldGen.sites:
			if at.distance_to(site["pos"]) < 260.0 and not built.has(site["id"]):
				built[site["id"]] = region.call("_build", site)
		var look_node: Node = region.get_node_or_null("Region1Look")
		if look_node:
			look_node.set("focus", player.global_position)
			look_node.call("update_now")
			var hz: Node = look_node.get("horizon")
			if hz:
				hz.call("build_now")
		var q: Array = region.get("_queue")
		while not q.is_empty():
			var item: Array = q.pop_front()
			if not is_instance_valid(item[0]):
				continue
			if item[2] == "part":
				region.call("_build_part", item[0], item[1], item[1]["parts"][item[3]])
			else:
				region.call("_build_light", item[0], item[1]["lights"][item[3]])
	# Towns build their props in slices around the focus: finish them so a view near a settlement is complete.
	var setl: Node = main.get("settlements")
	var near_town := v.has("gate")
	for st in WorldGen.settlements:
		if at.distance_to(st["pos"]) < float(st["radius"]) + 60.0:
			near_town = true
	if setl and near_town:     # (costs 1-2 min per view on a loaded machine: only where a town is really in view)
		setl.set("focus", player.global_position)
		for _i in 4:
			setl.call("update_now")
		setl.call("finish_prop_jobs")
	var gy := WorldGen.height(at.x, at.y)
	var ly := WorldGen.height(look.x, look.y)
	var lv := WorldGen.water_level_at(look.x, look.y)
	if not is_nan(lv):
		ly = maxf(ly, lv)
	var av := WorldGen.water_level_at(at.x, at.y)
	if not is_nan(av):
		gy = maxf(gy, av)
	if bool(v.get("stand", false)):
		cam.current = false
		player.visible = true
		var d := look - at
		player.call("set_camera", atan2(-d.x, -d.y), float(v.get("pitch", -0.12)))
	else:
		player.visible = false
		cam.global_position = Vector3(at.x, gy + float(v.get("up", 2.2)), at.y)
		cam.look_at(Vector3(look.x, ly + float(v.get("look_up", 1.5)), look.y))
		cam.fov = float(v.get("fov", 60.0))
		cam.current = true
	var ts: Node = main.get("terrain") if main.get("terrain") else null
	var br: Node = ts.get("_bridge") if ts else null
	var t3h := NAN
	if br:
		t3h = br.call("sampled_height", at.x, at.y)
	print("[diag] ", v["name"], " wg_h=", WorldGen.height(at.x, at.y), " t3d_h=", t3h, " cam_y=", cam.global_position.y, " regions=", br.call("region_count") if br else -1)
	if bool(v.get("expect_t3d", false)) and (br == null or not is_finite(t3h) or int(br.call("region_count")) <= 0):
		push_error("expected Terrain3D is not ready at view %s; refusing invalid capture" % String(v["name"]))
		_finish()
		quit(3)
		return
	if br and v.has("probe"):
		var t3: Object = (br.get("terrain") as Object).get("data")
		var scar: Variant = Region1State.sim(&"scar_tide")
		for off: Array in v["probe"]:
			var px := at.x + float(off[0])
			var pz := at.y + float(off[1])
			var ctrl := int(t3.call("get_control", Vector3(px, 0, pz)))
			var scar_v := float(scar.call("intensity_at", Vector2(px, pz))) if scar != null else -1.0
			print("[probe] ", v["name"], " off=", off, " wg=", WorldGen.height(px, pz), " t3d=", t3.call("get_height", Vector3(px, 0, pz)), " ctrl=0x%x" % ctrl, " ids=", (ctrl >> 27) & 31, "/", (ctrl >> 22) & 31, " blend=", (ctrl >> 14) & 255, " scar=", scar_v, " hole=", t3.call("get_control_hole", Vector3(px, 0, pz)) if t3.has_method("get_control_hole") else "n/a")
	# per-view Environment overrides ({"env": {"ssr_enabled": false}}), restored before the next view
	var envn: Environment = main.get("env")
	if envn:
		for k: String in _env_saved:
			envn.set(k, _env_saved[k])
		_env_saved.clear()
		for k: String in (v.get("env", {}) as Dictionary):
			_env_saved[k] = envn.get(k)
			envn.set(k, (v["env"] as Dictionary)[k])
	if br:
		var tn: Object = br.get("terrain")
		for k: String in _t3d_saved:
			tn.set(k, _t3d_saved[k])
		_t3d_saved.clear()
		var tmat: Object = tn.get("material")
		for k: String in _mat_saved:
			tmat.set(k, _mat_saved[k])
		_mat_saved.clear()
		for k: String in (v.get("mat", {}) as Dictionary):
			_mat_saved[k] = tmat.get(k)
			tmat.set(k, (v["mat"] as Dictionary)[k])
		for k: String in (v.get("t3d", {}) as Dictionary):
			_t3d_saved[k] = tn.get(k)
			tn.set(k, (v["t3d"] as Dictionary)[k])
	if br:
		var tp: Object = br.get("terrain")
		print("[t3d] mesh_size=", tp.get("mesh_size"), " mesh_lods=", tp.get("mesh_lods"), " cull_margin=", tp.get("cull_margin"), " lod_dist=", tp.get("lod_distance") if "lod_distance" in tp else "n/a")
	if br:
		var dd: Object = (br.get("terrain") as Object).get("data")
		print("[hr] data height_range=", dd.call("get_height_range"), " regions=", dd.call("get_region_count"), " has_E=", dd.call("has_regionp", Vector3(at.x + 100, 0, at.y)), " has_S=", dd.call("has_regionp", Vector3(at.x, 0, at.y + 100)))
		if v.has("hr"):
			dd.call("set_height_range", Vector2(float(v["hr"][0]), float(v["hr"][1])))
			print("[hr] set ", dd.call("get_height_range"))
	if br:
		var tc: Camera3D = (br.get("terrain") as Object).call("get_camera")
		print("[t3dcam] terrain camera=", tc.get_path() if tc else "null", " pos=", tc.global_position if tc else Vector3.ZERO, " cur=", tc.current if tc else false, " mycam=", cam.global_position, " snapped=", (br.get("terrain") as Object).call("get_snapped_position"))
	if br and bool(v.get("tcam", false)):
		(br.get("terrain") as Object).call("set_camera", cam)
	print("[pcam] player camera=", (player.get("camera") as Camera3D).global_position if player.get("camera") else "none", " current=", (player.get("camera") as Camera3D).current if player.get("camera") else false)
	var hzn: Node = region.get_node_or_null("Region1Look") if region else null
	if hzn and hzn.get("horizon"):
		(hzn.get("horizon") as Node3D).visible = not bool(v.get("nohorizon", false))
	phase = 0
	wait = int(v.get("warm", 150))
	print("[look] view ", v["name"], " at ", at, " look ", look, " t=", (Time.get_ticks_msec() - t0) / 1000)


## Look-dev shots are of the world: HUD, cutscene captions,
## tutorial toasts and dialogue panels are removed (env pass 2026-10-05: they covered the first views).
func _clear_overlays() -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		# Keep the layer that presents the game's 3D SubViewport (hiding it drops the real render path).
		if not n.find_children("*", "SubViewportContainer", true, false).is_empty():
			# ...but hide its other overlays (job offers, toasts, the location card that sat on top of the W6 shots).
			for ch in n.get_children():
				if ch is CanvasItem and not ch is SubViewportContainer and ch.find_children("*", "SubViewportContainer", true, false).is_empty():
					(ch as CanvasItem).visible = false
			continue
		(n as CanvasLayer).visible = false
	if cam:
		cam.current = true


func _save() -> void:
	_clear_overlays()        # popups that opened during the warm-up frames
	var v: Dictionary = views[idx]
	if v.has("scan"):
		var cp := cam.global_position
		for n in root.find_children("*", "VisualInstance3D", true, false):
			var vi := n as VisualInstance3D
			var bb := vi.global_transform * vi.get_aabb()
			if bb.size.x > 30.0 and bb.size.z > 30.0 and bb.size.y < 60.0 and absf(bb.get_center().x - cp.x) < bb.size.x * 0.5 + 60.0 and absf(bb.get_center().z - cp.z) < bb.size.z * 0.5 + 60.0:
				print("[scan] ", vi.get_path(), " cls=", vi.get_class(), " y=", bb.position.y, "..", bb.end.y, " size=", bb.size, " vis=", vi.is_visible_in_tree())
	var img := root.get_viewport().get_texture().get_image()
	var p := "%s/%s%s.png" % [out_dir, v["name"], ("_" + tag) if tag != "" else ""]
	img.save_png(p)
	var vp: Viewport = root.get_viewport()
	var sub: SubViewport = main.get("viewport")
	var rv: Viewport = sub if sub else vp
	var line: String
	if quickshot:
		line = "%s image_only=true draws=%d prims=%d objs=%d" % [v["name"],
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)]
	else:
		var s := samples.duplicate()
		s.sort()
		var avg := 0.0
		for x in s:
			avg += x
		avg /= maxf(1.0, s.size())
		line = "%s avg_ms=%.2f p95_ms=%.2f fps=%.0f draws=%d prims=%d objs=%d" % [v["name"], avg, s[int(s.size() * 0.95)] if s.size() > 0 else 0.0,
			1000.0 / maxf(avg, 0.01),
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)]
	perf_lines.append(line)
	print("[perf] ", line)
	print("SAVED ", p, " t=", (Time.get_ticks_msec() - t0) / 1000)


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	var f := FileAccess.open("%s/perf%s.txt" % [out_dir, ("_" + tag) if tag != "" else ""], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(perf_lines) + "\n")
		f.close()
	# Keep RenderingServer/WorkerThreadPool alive while streamed scene resources
	# are released. Immediate SceneTree shutdown can stall after a saved Vulkan
	# capture with the complete terrain scene still attached.
	call_deferred("_drain_and_quit")


func _drain_and_quit() -> void:
	if is_instance_valid(main):
		main.process_mode = Node.PROCESS_MODE_DISABLED
		main.queue_free()
		main = null
	cam = null
	for i in 10:
		await process_frame
	print("LOOK_CAPTURE_DRAINED")
	quit(0)
