extends Node3D
## Ashsight sandbox demo (windowed; do NOT use --headless for the visual mode).
##
## 1. LIVE: a fake raid (AshFakeRaid: 4 bandits and 2 villagers around a runestone) runs with
##    solid placeholder characters while AshMemory records it exactly the way the game
##    emitters will (1 Hz samples within 60 m).
## 2. The world drains to grey and the live figures vanish.
## 3. ASHSIGHT: the recorded incident is replayed by pooled ash ghosts (AshReplayView).
## The replayed paths are compared with the true paths (must be within 1 m).
##
## Visual capture (Movie Maker, deterministic):
##   Godot --path kingdom --rendering-method mobile --write-movie <dir>/frame.png --fixed-fps 30 \
##       res://tools_qa/region1/ashsight_demo.tscn -- --out=<dir>
## Checks only (no window needed):  ... ashsight_demo.tscn -- --check
## Real-time frame timing:          ... ashsight_demo.tscn -- --bench
## Options: --live-speed=4 (default 4)  --out=<dir>  --hold=1.0
## Prints ASHSIGHT_DEMO lines; exit code 0 = replay error < 1 m and budget met.

const ERR_LIMIT_M := 1.0
const BUDGET_MS := 0.3
const T_OFFSET := 5000.0

var live_speed := 4.0
var hold := 1.2
var out_dir := ""
var check_only := false
var bench := false

var mem: AshMemory
var incident_id := -1
var view: AshReplayView
var env: Environment
var cam: Camera3D
var title: Label
var caption: Label
var bar: ColorRect
var bar_fill: ColorRect
var chars: Dictionary = {}   # actor id -> Node3D (solid placeholder characters)

var _phase := 0            # 0 live, 1 drain, 2 replay, 3 outro, 4 done
var _sim_t := 0.0
var _phase_t := 0.0
var _cam_focus := Vector3(10, 0, -14)
var _cam_dist := 34.0
var _last_pos: Dictionary = {}
var _next_mark := 0
var _frames := 0
var _step_us := 0
var _worst_step_us := 0
var _replay_frames := 0
var _bench_delta := 0.0
var _bench_frames := 0
var _bench_process_ms := 0.0
var _errors: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--check": check_only = true
		elif a == "--bench": bench = true
		elif a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--live-speed="): live_speed = float(a.substr(13))
		elif a.begins_with("--hold="): hold = float(a.substr(7))
	mem = AshMemory.new().setup(1) as AshMemory
	Region1State.clear()
	Region1State.register_sim(mem)
	if check_only:
		get_tree().quit(_run_checks())
		return
	_build_world()
	_build_ui()
	view = AshReplayView.new()
	view.name = "AshReplayView"
	view.set_process(false)   # this demo steps the view itself so runs are deterministic
	add_child(view)
	# The raid starts: the emitter calls begin_incident once.
	mem.flag_site(AshFakeRaid.SITE_NAME, AshFakeRaid.STONE_POS)
	incident_id = mem.begin_incident(&"raid", AshFakeRaid.STONE_POS, T_OFFSET)
	for id: String in AshFakeRaid.KNOTS:
		chars[id] = _make_char(AshFakeRaid.role_of(id))
		add_child(chars[id])
	title.text = "The raid at %s" % AshFakeRaid.SITE_NAME
	caption.text = "LIVE  x%d" % int(live_speed)


# --- checks (no rendering) -----------------------------------------------------------------

func _run_checks() -> int:
	var id := AshFakeRaid.record_into(mem, T_OFFSET)
	var r := AshFakeRaid.max_replay_error(mem, id, 0.05)
	var info := mem.replay_info(id)
	print("ASHSIGHT_DEMO check: actors=%d duration=%.1fs samples_compared=%d max_error=%.3f m (worst %s)" % [
		(info["actors"] as Array).size(), info["duration"], r["samples"], r["max_error"], r["worst_actor"]])
	var ok := float(r["max_error"]) < ERR_LIMIT_M
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in 2000:
		n += mem.positions_at(id, float(i % 260) * 0.1).size()
	print("ASHSIGHT_DEMO check: positions_at avg %.4f ms (%d entries)" % [float(Time.get_ticks_usec() - t0) / 2000.0 / 1000.0, n])
	print("ASHSIGHT_DEMO ", "OK" if ok else "FAIL")
	return 0 if ok else 1


# --- frame loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_frames += 1
	_phase_t += delta
	match _phase:
		0: _live(delta)
		1: _drain(delta)
		2: _replay(delta)
		3: _outro(delta)
	env.adjustment_saturation = lerpf(1.08, 0.22, view.grade)
	env.adjustment_brightness = lerpf(1.0, 0.94, view.grade)
	env.adjustment_contrast = lerpf(1.02, 1.1, view.grade)
	_move_camera(delta)


func _live(delta: float) -> void:
	_sim_t += delta * live_speed
	var t := minf(_sim_t, AshFakeRaid.DURATION)
	var truth := AshFakeRaid.truth(t)
	# the emitter side: call sample() every frame, it keeps its own 1 Hz gate
	mem.sample(T_OFFSET + t, truth)
	while _next_mark < AshFakeRaid.MARKS.size() and float(AshFakeRaid.MARKS[_next_mark][0]) <= t:
		var m: Array = AshFakeRaid.MARKS[_next_mark]
		_next_mark += 1
		mem.mark(incident_id, T_OFFSET + float(m[0]), String(m[1]))
		caption.text = "LIVE  x%d   %s" % [int(live_speed), String(m[1])]
	for id: String in chars:
		var c: Node3D = chars[id]
		var alive := AshFakeRaid.alive_at(id, t)
		c.visible = alive
		if alive:
			var p := AshFakeRaid.position_of(id, t)
			var prev: Vector2 = _last_pos.get(id, p)
			var v := p - prev
			c.position = Vector3(p.x, 0.05 * absf(sin(t * 9.0 + float(id.hash() % 7))), p.y)
			if v.length_squared() > 0.0001:
				c.rotation.y = lerp_angle(c.rotation.y, atan2(-v.x, -v.y), 0.3)
			_last_pos[id] = p
	_focus_on(truth.map(func(e: Dictionary) -> Vector2: return e["pos"]))
	if t >= AshFakeRaid.DURATION:
		mem.end_incident(incident_id, T_OFFSET + AshFakeRaid.DURATION)
		_phase = 1
		_phase_t = 0.0
		title.text = "Ashsight"
		caption.text = "the ashes are still warm..."
		# start the replay now so the ghosts fade in while the world drains to grey
		view.show_incident(mem, incident_id, 1.0)
		view.cursor.playing = false


func _drain(_delta: float) -> void:
	view.grade = minf(1.0, _phase_t / 1.4)
	for id: String in chars:
		(chars[id] as Node3D).visible = false
	if _phase_t >= 1.5:
		_phase = 2
		_phase_t = 0.0
		view.cursor.playing = true
		var info := mem.replay_info(incident_id)
		caption.text = "%s   heat %d%%" % [String(info["site"]), int(round(float(info["heat"]) * 100.0))]


func _replay(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	view.step(delta)
	var us := Time.get_ticks_usec() - t0
	_step_us += us
	_worst_step_us = maxi(_worst_step_us, us)
	_replay_frames += 1
	if bench:
		_bench_delta += delta
		_bench_frames += 1
		_bench_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	# per-frame accuracy: compare the replay with the truth at the same instant
	var t := view.cursor.t
	for e: Dictionary in view.cursor.frame():
		var id := String(e["id"])
		if float(e["alpha"]) >= 0.999 and AshFakeRaid.alive_at(id, t):
			var err := (e["pos"] as Vector2).distance_to(AshFakeRaid.position_of(id, t))
			_errors[id] = maxf(float(_errors.get(id, 0.0)), err)
	var pts: Array = []
	for id: String in view._active:
		var g: AshGhost = view._active[id]
		pts.append(Vector2(g.position.x, g.position.z))
	if not pts.is_empty():
		_focus_on(pts)
	# scrub bar and beat captions
	bar_fill.size.x = bar.size.x * view.cursor.progress()
	for m: Dictionary in mem.replay_info(incident_id)["marks"]:
		if absf(float(m["t"]) - t) < 1.6:
			caption.text = String(m["label"]).capitalize()
	if not view.is_playing():
		_phase = 3
		_phase_t = 0.0
		caption.text = "The trail leads north-east."


func _outro(_delta: float) -> void:
	view.grade = maxf(0.0, view.grade - _delta * 0.9)
	if _phase_t >= hold:
		_phase = 4
		_finish()


func _finish() -> void:
	var worst := 0.0
	var who := ""
	for id: String in _errors:
		if float(_errors[id]) > worst:
			worst = float(_errors[id])
			who = id
	var avg_ms := float(_step_us) / 1000.0 / maxf(1.0, float(_replay_frames))
	var ok := worst < ERR_LIMIT_M and avg_ms < BUDGET_MS
	var line := "ASHSIGHT_DEMO frames=%d replay_frames=%d ghosts_max=%d step_avg=%.4f ms step_worst=%.4f ms (budget %.1f) max_path_error=%.3f m (%s)" % [
		_frames, _replay_frames, view.max_active, avg_ms, float(_worst_step_us) / 1000.0, BUDGET_MS, worst, who]
	print(line)
	if bench:
		print("ASHSIGHT_DEMO bench: replay phase avg frame %.3f ms (%.0f fps), engine TIME_PROCESS avg %.3f ms, draw calls %d" % [
			_bench_delta / maxf(1.0, float(_bench_frames)) * 1000.0, float(_bench_frames) / maxf(0.001, _bench_delta),
			_bench_process_ms / maxf(1.0, float(_bench_frames)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	print("ASHSIGHT_DEMO ", "OK" if ok else "FAIL")
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("ashsight_demo.txt"), FileAccess.WRITE)
		if f:
			f.store_string(line + "\n" + ("OK" if ok else "FAIL") + "\n")
	get_tree().quit(0 if ok else 1)


# --- camera --------------------------------------------------------------------------------

func _focus_on(points: Array) -> void:
	if points.is_empty():
		return
	var c := Vector2.ZERO
	for p: Vector2 in points:
		c += p
	c /= float(points.size())
	var spread := 0.0
	for p: Vector2 in points:
		spread = maxf(spread, p.distance_to(c))
	_cam_focus = _cam_focus.lerp(Vector3(c.x, 1.0, c.y), 0.06)
	_cam_dist = lerpf(_cam_dist, clampf(20.0 + spread * 0.9, 24.0, 52.0), 0.03)


func _move_camera(_delta: float) -> void:
	if cam == null:
		return
	var off := Vector3(0.55, 0.62, 0.9).normalized() * _cam_dist
	cam.position = _cam_focus + off
	cam.look_at(_cam_focus + Vector3(0, 0.5, 0), Vector3.UP)


# --- scenery and placeholder characters (demo only) --------------------------------------------

func _mat(c: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _make_char(role: String) -> Node3D:
	# Simple solid placeholders: robe + chest + head (+ hood for bandits, hat for villagers).
	var n := Node3D.new()
	var bandit := role == "bandit"
	var cloth := _mat(Color(0.62, 0.20, 0.16) if bandit else Color(0.22, 0.42, 0.72))
	var skin := _mat(Color(0.93, 0.76, 0.60))
	var trim := _mat(Color(0.20, 0.15, 0.13) if bandit else Color(0.86, 0.72, 0.30))
	var robe := CylinderMesh.new(); robe.top_radius = 0.22; robe.bottom_radius = 0.34; robe.height = 1.0; robe.radial_segments = 14
	var chest := CapsuleMesh.new(); chest.radius = 0.25; chest.height = 0.72
	var head := SphereMesh.new(); head.radius = 0.2; head.height = 0.4
	var arm := CapsuleMesh.new(); arm.radius = 0.07; arm.height = 0.62
	_mesh(robe, cloth, Vector3(0, 0.5, 0), n)
	_mesh(chest, cloth, Vector3(0, 1.15, 0), n)
	_mesh(head, skin, Vector3(0, 1.6, 0), n)
	var al := _mesh(arm, cloth, Vector3(0.33, 1.08, 0), n)
	al.rotation.z = -0.35
	var ar := _mesh(arm, cloth, Vector3(-0.33, 1.08, 0), n)
	ar.rotation.z = 0.35
	if bandit:
		var hood := CylinderMesh.new(); hood.top_radius = 0.0; hood.bottom_radius = 0.26; hood.height = 0.36
		_mesh(hood, trim, Vector3(0, 1.82, 0), n)
		var belt := CylinderMesh.new(); belt.top_radius = 0.27; belt.bottom_radius = 0.27; belt.height = 0.08
		_mesh(belt, trim, Vector3(0, 0.9, 0), n)
	else:
		var hat := CylinderMesh.new(); hat.top_radius = 0.16; hat.bottom_radius = 0.34; hat.height = 0.08
		_mesh(hat, _mat(Color(0.86, 0.72, 0.36)), Vector3(0, 1.78, 0), n)
		var apron := BoxMesh.new(); apron.size = Vector3(0.36, 0.7, 0.05)
		_mesh(apron, _mat(Color(0.96, 0.94, 0.88)), Vector3(0, 0.75, -0.3), n)
	return n


func _build_world() -> void:
	# sky, sun, warm storybook light
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.55, 0.92)
	sm.sky_horizon_color = Color(0.72, 0.85, 0.96)
	sm.ground_horizon_color = Color(0.72, 0.85, 0.96)
	sm.ground_bottom_color = Color(0.45, 0.62, 0.40)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.76)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-48, 130, 0)
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.current = true
	add_child(cam)
	# meadow, road, farm patch
	var ground := PlaneMesh.new(); ground.size = Vector2(400, 400)
	_mesh(ground, _mat(Color(0.47, 0.66, 0.30)), Vector3.ZERO)
	var road := PlaneMesh.new(); road.size = Vector2(220, 5.0)
	var rm := _mesh(road, _mat(Color(0.83, 0.72, 0.52)), Vector3(-20, 0.02, 9.5))
	rm.rotation.y = deg_to_rad(-7.0)
	var patch := PlaneMesh.new(); patch.size = Vector2(11, 8)
	_mesh(patch, _mat(Color(0.52, 0.36, 0.22)), Vector3(-10, 0.03, 4))
	var wheat := BoxMesh.new(); wheat.size = Vector3(0.06, 0.6, 0.06)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = wheat
	mm.instance_count = 90
	for i in 90:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-15 + float(i % 15) * 0.72, 0.3, 0.6 + floorf(float(i) / 15.0) * 1.2)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(0.96, 0.80, 0.30))
	add_child(mmi)
	# the runestone
	var stone := BoxMesh.new(); stone.size = Vector3(1.0, 2.4, 0.6)
	_mesh(stone, _mat(Color(0.80, 0.76, 0.68)), Vector3(0, 1.2, 0))
	var cap := SphereMesh.new(); cap.radius = 0.5; cap.height = 0.5
	var capm := _mesh(cap, _mat(Color(0.80, 0.76, 0.68)), Vector3(0, 2.4, 0))
	capm.scale = Vector3(1, 0.7, 0.6)
	var glyph := QuadMesh.new(); glyph.size = Vector2(0.5, 1.1)
	_mesh(glyph, _mat(Color(0.35, 0.65, 1.0), 0.5, 2.2), Vector3(0, 1.3, 0.31))
	var base := CylinderMesh.new(); base.top_radius = 1.0; base.bottom_radius = 1.2; base.height = 0.25
	_mesh(base, _mat(Color(0.66, 0.62, 0.56)), Vector3(0, 0.12, 0))
	# round storybook trees and daisies
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.25; trunk.bottom_radius = 0.35; trunk.height = 2.4
	var crown := SphereMesh.new(); crown.radius = 2.0; crown.height = 3.6
	for i in 26:
		var p := Vector3(rng.randf_range(-70, 60), 0, rng.randf_range(-70, 30))
		if absf(p.z - 9.0) < 6.0 or Vector2(p.x, p.z).length() < 16.0:
			continue
		var s := rng.randf_range(0.8, 1.5)
		var tn := Node3D.new()
		tn.position = p
		tn.scale = Vector3(s, s, s)
		add_child(tn)
		_mesh(trunk, _mat(Color(0.45, 0.30, 0.20)), Vector3(0, 1.2, 0), tn)
		_mesh(crown, _mat(Color(0.32 + rng.randf() * 0.12, 0.62 + rng.randf() * 0.1, 0.24)), Vector3(0, 3.6, 0), tn)
	var daisy := SphereMesh.new(); daisy.radius = 0.09; daisy.height = 0.12
	for col: Color in [Color(1, 1, 0.95), Color(1.0, 0.85, 0.25), Color(0.95, 0.4, 0.4)]:
		var dm := MultiMesh.new()
		dm.transform_format = MultiMesh.TRANSFORM_3D
		dm.mesh = daisy
		dm.instance_count = 70
		for i in 70:
			var q := Vector3(rng.randf_range(-60, 60), 0.08, rng.randf_range(-55, 40))
			if absf(q.z - 9.0) < 3.5:
				q.z += 6.0
			dm.set_instance_transform(i, Transform3D(Basis(), q))
		var di := MultiMeshInstance3D.new()
		di.multimesh = dm
		di.material_override = _mat(col)
		add_child(di)


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	title = Label.new()
	title.position = Vector2(28, 20)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.08))
	title.add_theme_constant_override("outline_size", 8)
	cl.add_child(title)
	caption = Label.new()
	caption.position = Vector2(28, 70)
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color(1, 1, 1))
	caption.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.08))
	caption.add_theme_constant_override("outline_size", 6)
	cl.add_child(caption)
	bar = ColorRect.new()
	bar.color = Color(0.15, 0.1, 0.06, 0.6)
	var vs := get_viewport().get_visible_rect().size
	bar.position = Vector2(28, vs.y - 44)
	bar.size = Vector2(vs.x - 56, 10)
	cl.add_child(bar)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(1.0, 0.75, 0.35)
	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(0, 10)
	bar.add_child(bar_fill)
