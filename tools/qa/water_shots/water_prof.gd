extends "water_shots.gd"
## Water performance ablation, interleaved so it survives a busy machine.
## For each view (lake, river, pier) and quality tier it measures frame time, main-thread
## process time, GPU time, draw calls and primitives with the water shader old vs new,
## and with one suspect switched off at a time (shader features, shadows, vegetation, NPCs,
## terrain, post effects, resolution). The configs are measured in short bursts, round
## robin, several rounds, and each config reports the BEST round's median (min over
## rounds): other processes on the PC (imports, other agents' renders) add time to
## random rounds, so the minimum is the intrinsic cost.
## Run: bash tools/qa/water_shots/prof.sh <out.jsonl> [views=lake,river,pier] [w=1600] [h=900] [--k=v ...]
## Args: --only=baseline,water_off (only these configs)  --tiers=0,1,2,3  --rounds=8  --burst=25  --sysprof (CPU ablation per game system, lake only)
##       --optshader=<abs path to a working-copy clear_water.gdshader>  --bootwait=<s>  --watchdog=<s>

var _out: FileAccess
var _view := ""
var _new_shader: Shader
var _hidden: Array[Node] = []
var _env_saved := {}


func _shot_prof() -> bool:
	var a := _args()
	_out = FileAccess.open(String(a.get("jsonl", "user://water_prof.jsonl")), FileAccess.WRITE_READ)
	if _out:
		_out.seek_end()
	for v in String(a.get("views", "lake,river,pier")).split(","):
		_view = v
		await call("_shot_" + v)
		_load_new_shader()
		if _args().has("census"):
			_census()
		for t in String(a.get("tiers", "0,1,2,3")).split(","):
			await _tier(int(t))
			_print_simtime()
	return false


## The regular shots end with a 4 s fps print; skip it here.
func _fps() -> void:
	pass


func _wm() -> ShaderMaterial:
	return main.water.get("_material")


func _load_new_shader() -> void:
	var p := String(_args().get("shader", ""))
	if p == "":
		_new_shader = preload("res://shaders/water/clear_water.gdshader")
	else:
		_new_shader = Shader.new()
		_new_shader.code = FileAccess.get_file_as_string(p)
	_wm().shader = _new_shader


func _cfg(label: String, apply: Callable = Callable(), undo: Callable = Callable()) -> Dictionary:
	return {"label": label, "apply": apply, "undo": undo}


func _tier(t: int) -> void:
	Quality.call("_set_tier", t)
	await frames(8)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _args().has("snap"):
		await frames(20)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(out_dir)
		main.viewport.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, _view, Quality.tier_name().to_lower()])
		print("PROF snap ", _view, " ", Quality.tier_name())
		var nseq := int(_args().get("seq", "0"))
		if nseq > 0 and t == 2:
			var sd := "%s/seq_%s" % [out_dir, _view]
			DirAccess.make_dir_recursive_absolute(sd)
			for k in nseq:
				await frames(4)
				main.viewport.get_texture().get_image().save_png("%s/f%03d.png" % [sd, k])
	if _args().has("rdprof"):
		await _rdprof(t)
		if _args().has("sysprof") and t == int(_args().get("systier", "2")):
			await _sysprof(t)
		return
	var cfgs: Array[Dictionary] = []
	cfgs.append(_cfg("baseline"))
	if _args().has("optshader"):
		cfgs.append(_cfg("opt_shader", func() -> void: _opt(t), func() -> void: _wm().shader = _new_shader))
	cfgs.append(_cfg("old_shader", func() -> void: _old_shader(), func() -> void: _wm().shader = _new_shader))
	cfgs.append(_cfg("water_off", func() -> void: main.water.visible = false, func() -> void: main.water.visible = true))
	cfgs.append(_cfg("lite_variant", func() -> void: _lite(), func() -> void: _unlite()))
	if t >= 2:
		if t == 2:
			cfgs.append(_cfg("q0_no_screen_read", func() -> void: _wm().set_shader_parameter("quality", 0); _wm().set_shader_parameter("use_refraction", false), func() -> void: _unlite()))
			cfgs.append(_cfg("q1_no_caustics", func() -> void: _wm().set_shader_parameter("quality", 1), func() -> void: _unlite()))
			cfgs.append(_cfg("no_glint", func() -> void: _wm().set_shader_parameter("glint_strength", 0.0), func() -> void: _wm().set_shader_parameter("glint_strength", 1.0)))
		cfgs.append(_cfg("no_shadow", func() -> void: _sun_shadow(false), func() -> void: _sun_shadow(true)))
		cfgs.append(_cfg("no_multimesh", func() -> void: _hide_class("MultiMeshInstance3D"), func() -> void: _unhide()))
		cfgs.append(_cfg("no_npcs", func() -> void: _hide_npcs(), func() -> void: _unhide()))
		cfgs.append(_cfg("no_terrain", func() -> void: main.terrain.visible = false, func() -> void: main.terrain.visible = true))
		for prop in ["ssao_enabled", "ssil_enabled", "glow_enabled", "sdfgi_enabled", "volumetric_fog_enabled"]:
			if _env().get(prop):
				cfgs.append(_cfg("no_" + prop.replace("_enabled", ""), func() -> void: _env_off(prop), func() -> void: _env_restore()))
		var vp: SubViewport = main.viewport
		if vp.msaa_3d != Viewport.MSAA_DISABLED or vp.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED:
			var m0 := vp.msaa_3d
			var s0 := vp.screen_space_aa
			cfgs.append(_cfg("no_aa", func() -> void: _aa_off(), func() -> void: _aa_restore(m0, s0)))
		cfgs.append(_cfg("half_res_3d", func() -> void: _scale(0.5), func() -> void: _scale(1.0)))
	await _bursts(t, cfgs)
	if _args().has("sysprof") and t == int(_args().get("systier", "2")) and _view == "lake":
		await _sysprof(t)


## Round-robin bursts; reports min over rounds of each config's median.
func _bursts(_t: int, all_cfgs: Array[Dictionary]) -> void:
	var cfgs: Array[Dictionary] = []
	var only := String(_args().get("only", ""))
	for c in all_cfgs:
		if only == "" or String(c["label"]) in only.split(","):
			cfgs.append(c)
	var rounds := int(_args().get("rounds", "8"))
	var burst := int(_args().get("burst", "25"))
	var vp: SubViewport = main.viewport
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var res := {}
	for c in cfgs:
		res[c["label"]] = {"ms": [], "proc": [], "gpu": [], "draws": 0, "prims": 0, "p99": []}
	for r in rounds:
		for c in cfgs:
			var ap: Callable = c["apply"]
			if ap.is_valid():
				ap.call()
			await frames(5)
			var ft: Array[float] = []
			var pr: Array[float] = []
			var gp: Array[float] = []
			var last := Time.get_ticks_usec()
			for i in burst:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				ft.append((now - last) / 1000.0)
				last = now
				pr.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				gp.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			var e: Dictionary = res[c["label"]]
			e["ms"].append(_pct(ft, 0.5))
			e["p99"].append(_pct(ft, 0.99))
			e["proc"].append(_pct(pr, 0.5))
			e["gpu"].append(_pct(gp, 0.5))
			e["draws"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			e["prims"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			var un: Callable = c["undo"]
			if un.is_valid():
				un.call()
	for c in cfgs:
		var e: Dictionary = res[c["label"]]
		var line := JSON.stringify({
			"view": _view, "tier": Quality.tier_name(), "renderer": RenderingServer.get_current_rendering_method(),
			"cfg": c["label"], "size": "%dx%d" % [vp.size.x, vp.size.y],
			"ms_best": snappedf(_min(e["ms"]), 0.01), "ms_med": snappedf(_pct(e["ms"], 0.5), 0.01),
			"fps_best": snappedf(1000.0 / maxf(_min(e["ms"]), 0.01), 0.1),
			"proc_best": snappedf(_min(e["proc"]), 0.01), "gpu_best": snappedf(_min(e["gpu"]), 0.01), "gpu_med": snappedf(_pct(e["gpu"], 0.5), 0.01),
			"p99_best": snappedf(_min(e["p99"]), 0.01), "draws": e["draws"], "prims": e["prims"], "rounds": rounds,
		})
		print("PROF ", line)
		if _out:
			_out.store_line(line)
			_out.flush()


## CPU ablation: switch off one autoload or world child at a time (process and physics).
func _sysprof(t: int) -> void:
	var targets: Array[Node] = []
	for n in ["WorldSim", "Life", "Frontier", "Audio"]:
		var a := get_tree().root.get_node_or_null(n)
		if a:
			targets.append(a)
	for c in main.world.get_children():
		if c is Camera3D or c == main.water:
			continue
		if c.is_processing() or c.is_physics_processing() or c.get_child_count() > 0:
			targets.append(c)
	var cfgs: Array[Dictionary] = [_cfg("baseline")]
	cfgs.append(_cfg("hide_multimesh", func() -> void: _hide_class("MultiMeshInstance3D"), func() -> void: _unhide()))
	cfgs.append(_cfg("hide_terrain", func() -> void: main.terrain.visible = false, func() -> void: main.terrain.visible = true))
	cfgs.append(_cfg("hide_npcs", func() -> void: _hide_npcs(), func() -> void: _unhide()))
	cfgs.append(_cfg("hide_world_all", func() -> void: main.world.visible = false, func() -> void: main.world.visible = true))
	for n in targets:
		var nm := "sys_%s_%s" % [n.name, (n.get_script() as Script).resource_path.get_file() if n.get_script() else n.get_class()]
		cfgs.append(_cfg(nm, func() -> void: n.process_mode = Node.PROCESS_MODE_DISABLED, func() -> void: n.process_mode = Node.PROCESS_MODE_INHERIT))
	await _bursts(t, cfgs)


func _lite() -> void:
	var s := Shader.new()
	s.code = "#define WATER_LITE\n" + _new_shader.code
	_wm().shader = s
	_wm().set_shader_parameter("quality", 0)
	_wm().set_shader_parameter("use_refraction", false)


func _unlite() -> void:
	_wm().shader = _new_shader
	main.water.call("apply_quality")


## The edited shader from a working copy: lite variant on LOW, full otherwise, like WaterStreamer.apply_quality().
func _opt(t: int) -> void:
	var s := Shader.new()
	s.code = ("#define WATER_LITE\n" if t == 0 else "") + FileAccess.get_file_as_string(String(_args()["optshader"]))
	_wm().shader = s


func _old_shader() -> void:
	var m := _wm()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("use_refraction", true)


func _env() -> Environment:
	return main.get("env")


func _env_off(prop: String) -> void:
	_env_saved[prop] = _env().get(prop)
	_env().set(prop, false)


func _env_restore() -> void:
	for k in _env_saved:
		_env().set(k, _env_saved[k])
	_env_saved.clear()


func _aa_off() -> void:
	var vp: SubViewport = main.viewport
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func _aa_restore(m: int, s: int) -> void:
	var vp: SubViewport = main.viewport
	vp.msaa_3d = m as Viewport.MSAA
	vp.screen_space_aa = s as Viewport.ScreenSpaceAA


func _scale(s: float) -> void:
	var vp: SubViewport = main.viewport
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


func _sun_shadow(on: bool) -> void:
	for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = on


func _hide_class(cls: String) -> void:
	for n in main.world.find_children("*", cls, true, false):
		if (n as Node3D).visible and n.get_parent() != main.water:
			(n as Node3D).visible = false
			_hidden.append(n)


func _hide_npcs() -> void:
	var pop: Node = main.get("population")
	if pop is Node3D and (pop as Node3D).visible:
		(pop as Node3D).visible = false
		_hidden.append(pop)


func _unhide() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden.clear()


func _min(a: Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m


func _pct(a: Array, p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(b.size() * p), 0, b.size() - 1)]


## Control view: Ashford village (the route that ran at 60 fps), same measurement.
func _shot_village() -> bool:
	hour(float(_args().get("hour", "11.5")))
	teleport(Vector2(1.0, 7.5))
	player.visible = true
	await wait(6.0)
	player.call("set_camera", 0.25, -0.12)
	await wait(2.0)
	return false


## What runs per frame in the world: processing nodes by script and class, lights, physics bodies.
func _census() -> void:
	var by_script := {}
	var by_class := {}
	var lights := 0
	var lights_shadow := 0
	var total := 0
	for n in main.world.find_children("*", "", true, false):
		total += 1
		by_class[n.get_class()] = int(by_class.get(n.get_class(), 0)) + 1
		if n is Light3D and (n as Light3D).is_visible_in_tree():
			lights += 1
			lights_shadow += 1 if (n as Light3D).shadow_enabled else 0
		if n.is_processing() or n.is_physics_processing():
			var sp: String = (n.get_script() as Script).resource_path.get_file() if n.get_script() else n.get_class()
			by_script[sp] = int(by_script.get(sp, 0)) + 1
	print("CENSUS nodes=%d lights=%d (shadowed %d)" % [total, lights, lights_shadow])
	var keys := by_script.keys()
	keys.sort_custom(func(a, b) -> bool: return by_script[a] > by_script[b])
	for k in keys.slice(0, 25):
		print("CENSUS processing %-40s %d" % [k, by_script[k]])
	var ck := by_class.keys()
	ck.sort_custom(func(a, b) -> bool: return by_class[a] > by_class[b])
	for k in ck.slice(0, 20):
		print("CENSUS class %-32s %d" % [k, by_class[k]])
	var rd: Node = null
	for c in main.world.get_children():
		if c.get_script() and (c.get_script() as Script).resource_path.ends_with("region_dressing.gd"):
			rd = c
	if rd:
		var proc := {}
		var cnt := 0
		var ls := 0
		for n in rd.find_children("*", "", true, false):
			cnt += 1
			if n is Light3D:
				ls += 1
			if n.is_processing() or n.is_physics_processing():
				var sp2: String = (n.get_script() as Script).resource_path.get_file() if n.get_script() else n.get_class()
				proc[sp2] = int(proc.get(sp2, 0)) + 1
		print("CENSUS region_dressing subtree nodes=%d lights=%d processing=%s built=%d flicker=%d" % [cnt, ls, str(proc), rd.call("built_count"), (rd.get("_flicker") as Array).size()])


## RegionDressing cost split (--rdprof): script vs colliders vs lights vs meshes vs shadows, plus its own _process time.
func _rd() -> Node:
	for c in main.world.get_children():
		if c.get_script() and (c.get_script() as Script).resource_path.ends_with("region_dressing.gd"):
			return c
	return null


func _rdprof(t: int) -> void:
	var rd := _rd()
	if rd == null:
		return
	var shapes: Array[Node] = rd.find_children("*", "CollisionShape3D", true, false)
	var lights: Array[Node] = rd.find_children("*", "Light3D", true, false)
	var geos: Array[Node] = rd.find_children("*", "GeometryInstance3D", true, false)
	print("RDPROF %s %s nodes=%d shapes=%d lights=%d geoms=%d built=%d" % [_view, Quality.tier_name(),
		rd.find_children("*", "", true, false).size(), shapes.size(), lights.size(), geos.size(), rd.call("built_count")])
	var cfgs: Array[Dictionary] = [_cfg("baseline")]
	cfgs.append(_cfg("rd_script_off", func() -> void: rd.set_process(false), func() -> void: rd.set_process(true)))
	cfgs.append(_cfg("rd_colliders_off", func() -> void: _shapes(shapes, true), func() -> void: _shapes(shapes, false)))
	cfgs.append(_cfg("rd_lights_off", func() -> void: _vis(lights, false), func() -> void: _vis(lights, true)))
	cfgs.append(_cfg("rd_meshes_hidden", func() -> void: _vis(geos, false), func() -> void: _vis(geos, true)))
	cfgs.append(_cfg("rd_noshadow", func() -> void: _shad(geos, false), func() -> void: _shad(geos, true)))
	cfgs.append(_cfg("rd_hidden_all", func() -> void: (rd as Node3D).visible = false, func() -> void: (rd as Node3D).visible = true))
	cfgs.append(_cfg("rd_disabled", func() -> void: rd.process_mode = Node.PROCESS_MODE_DISABLED, func() -> void: rd.process_mode = Node.PROCESS_MODE_INHERIT))
	await _bursts(t, cfgs)
	print("RDPROF %s script _process avg %.3f ms over %d frames" % [_view, float(rd.get("dbg_usec")) / maxf(float(rd.get("dbg_frames")), 1.0) / 1000.0, int(rd.get("dbg_frames"))])
	print("RDPROF physics active=%d islands=%d pairs=%d objects=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.OBJECT_COUNT)])


func _shapes(a: Array[Node], off: bool) -> void:
	for n in a:
		if is_instance_valid(n):
			(n as CollisionShape3D).disabled = off


func _vis(a: Array[Node], on: bool) -> void:
	for n in a:
		if is_instance_valid(n):
			(n as Node3D).visible = on


func _shad(a: Array[Node], on: bool) -> void:
	for n in a:
		if is_instance_valid(n):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Mean WorldSim._simulate_slice time (needs the dbg counters in world_sim.gd).
func _print_simtime() -> void:
	var ws := get_tree().root.get_node_or_null("WorldSim")
	if ws and ws.get("dbg_frames") != null and int(ws.get("dbg_frames")) > 0:
		print("PROF simslice_ms_per_frame %.3f over %d frames" % [float(ws.get("dbg_slice_usec")) / float(ws.get("dbg_frames")) / 1000.0, int(ws.get("dbg_frames"))])
