extends RefCounted
## Shared helpers for the addon demos: sunny environment, fps/GPU measurement, screenshot.
## Demos are QA-only and are NOT wired into gameplay.

static func sunny_world(root: Node3D) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.36, 0.60, 0.92)
	pm.sky_horizon_color = Color(0.80, 0.88, 0.95)
	pm.ground_horizon_color = Color(0.72, 0.80, 0.78)
	pm.ground_bottom_color = Color(0.42, 0.52, 0.40)
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)
	return {"env": env, "sun": sun}

static func ground(root: Node3D, size := 120.0, color := Color(0.42, 0.58, 0.28)) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	m.mesh = p
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	m.material_override = mat
	root.add_child(m)
	return m

static func label(root: Node, text: String) -> Label:
	var cl := CanvasLayer.new()
	cl.layer = 50
	root.add_child(cl)
	var l := Label.new()
	l.text = text
	l.position = Vector2(14, 10)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	cl.add_child(l)
	return l

static func shot(tree: SceneTree, dir: String, name_: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	tree.root.get_viewport().get_texture().get_image().save_png(dir.path_join(name_ + ".png"))

## Averages wall-clock ms/frame, GPU ms and render-CPU ms over `frames` (after a 30 frame warmup).
static func measure(tree: SceneTree, frames := 240) -> Dictionary:
	var vp := tree.root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 30:
		await tree.process_frame
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	var cpu := 0.0
	for i in frames:
		await tree.process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var dt := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	return {
		"frame_ms": snappedf(dt, 0.01), "fps": snappedf(1000.0 / dt, 0.1),
		"gpu_ms": snappedf(gpu / frames, 0.01), "render_cpu_ms": snappedf(cpu / frames, 0.01),
		"draw_calls": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
	}

static func fmt(label_: String, m: Dictionary) -> String:
	return "%s | %.2f ms (%.0f fps) | GPU %.2f ms | render-CPU %.2f ms | draws %d | tris %d" % [label_, m["frame_ms"], m["fps"], m["gpu_ms"], m["render_cpu_ms"], m["draw_calls"], m["primitives"]]
