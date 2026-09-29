extends Node3D
## Ashsight sandbox 2: a burned farm on real-looking ground (Region 1 nature and farm assets),
## a raid recorded from a scripted stand-in (AshFakeRaid: 4 bandits, 2 villagers), and the whole
## Ashsight moment: soft camera pull-in, warm world grade, real humanoid ghosts, slow motion at
## the blow, and the scrub bar. WINDOWED (never --headless for the visual mode).
##
## Movie Maker capture (deterministic):
##   Godot --path kingdom --rendering-method mobile --resolution 1600x720 \
##       --write-movie <dir>/frame.png --fixed-fps 30 res://tools_qa/region1/ashsight_farm.tscn -- --out=<dir>
## Options after `--`:
##   --tier=low|med|high   ghost / grade detail (default: from Quality)
##   --no-slowmo           skip the slow-motion beat
##   --bench               real-time frame timing (windowed, no movie): prints ASHSIGHT_FARM lines
##   --check               data checks only (no rendering)
##   --gallery             closeup gallery of the ghost clips and dissolve states
##   --scrub               also drag the scrub bar during the capture
##   --out=<dir>           where the report text goes

const T_OFFSET := 5000.0
const INTRO_S := 3.0
const OUTRO_S := 2.4
const YARD := Vector2(-6.0, 0.0)
const YARD_R := 7.5
const TERRAIN_SIZE := 170.0
const TERRAIN_STEP := 1.0
const ROAD := [Vector2(70, -62), Vector2(34, -30), Vector2(10, -8), Vector2(-4, 2), Vector2(-30, 6), Vector2(-80, -8)]

const REGION := "res://assets/generated/region/"

var tier := -1
var slowmo := true
var bench := false
var check_only := false
var gallery := false
var stepbench := false
var dissolve_view := false
var scrub_demo := false
var out_dir := ""
var shots_dir := ""
var shot_every := 15
var _shot_i := 0

var mem: AshMemory
var incident_id := -1
var ash: AshsightController
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var noise: FastNoiseLite

var _phase := 0        # 0 intro, 1 replay, 2 outro, 3 done
var _t := 0.0
var _cam_t := 0.0
var _outro_t := 0.0
var _frames := 0
var _slow_on := false
var _scrubbed := false
var _cam_a: Vector3
var _cam_b: Vector3
# bench
var _bench_base_n := 0
var _bench_base_gpu := 0.0
var _bench_base_cpu := 0.0
var _bench_n := 0
var _bench_gpu := 0.0
var _bench_cpu := 0.0
var _bench_frame := 0.0
var _bench_base_frame := 0.0
var _bench_step := 0.0
var _bench_step_worst := 0.0
var _bench_spikes: Array[String] = []
var _errors := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--check": check_only = true
		elif a == "--bench": bench = true
		elif a == "--no-slowmo": slowmo = false
		elif a == "--stepbench": stepbench = true
		elif a == "--gallery": gallery = true
		elif a == "--dissolve": gallery = true; dissolve_view = true
		elif a == "--scrub": scrub_demo = true
		elif a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--shots="): shots_dir = a.substr(8)
		elif a.begins_with("--shot-every="): shot_every = int(a.substr(13))
		elif a.begins_with("--tier="):
			tier = {"low": 0, "med": 1, "high": 2}.get(a.substr(7), -1)
	mem = AshMemory.new().setup(1) as AshMemory
	Region1State.clear()
	Region1State.register_sim(mem)
	if check_only:
		get_tree().quit(_run_checks())
		return
	noise = FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.011
	noise.fractal_octaves = 3
	_build_world()
	if gallery:
		_build_gallery()
		return
	# record the raid the way the game emitters do
	incident_id = AshFakeRaid.record_into(mem, T_OFFSET)
	ash = AshsightController.new()
	ash.name = "Ashsight"
	ash.cinematic = slowmo
	if tier >= 0:
		ash.detail = tier
	add_child(ash)
	ash.setup(cam, env, Callable(self, "terrain_h_v"))
	ash.ended.connect(func() -> void: _phase = 2; _outro_t = 0.0)
	await ash.warm()   # ghost bodies are built one per frame, before the moment starts
	if stepbench:
		_run_stepbench()
		return
	_t = 0.0
	_cam_t = 0.0


## CPU-only cost of the replay step (script + AnimationPlayer + material params) for the 6 ghosts, at
## a fixed 60 Hz, best of 5 passes so a busy PC does not inflate it. Works with or without a window.
func _run_stepbench() -> void:
	AshGhost.profile = true
	var view := ash.view
	cam.global_position = Vector3(-4.0, 4.5, 15.0)   # about where the pull-in frames the yard
	cam.look_at(Vector3(-7.0, 1.0, 2.0), Vector3.UP)
	var best := 1.0e9
	var best_parts := ""
	for pass_i in 5:
		view.show_incident(mem, incident_id, 1.0)
		view.cursor.speed = 1.0
		AshGhost.prof_anim_us = 0
		AshGhost.prof_look_us = 0
		AshGhost.prof_part_us = 0
		AshGhost.prof_adv_us = 0
		AshGhost.prof_adv_n = 0
		AshReplayView.prof_frame_us = 0
		AshReplayView.prof_ground_us = 0
		var n := 0
		var us := 0
		for i in 900:
			var t0 := Time.get_ticks_usec()
			view.step(1.0 / 60.0)
			var d := Time.get_ticks_usec() - t0
			if view.pool.active_count() >= 4 and view.cursor != null and view.cursor.t > 8.0 and view.cursor.t < 22.0:
				us += d
				n += 1
		var avg := float(us) / 1000.0 / maxf(1.0, float(n))
		if avg < best:
			best = avg
			best_parts = "anim=%.3f (advance %.1f calls, %.0f us each) look=%.3f particles=%.3f positions_at=%.3f ground=%.3f ms" % [
				float(AshGhost.prof_anim_us) / 1000.0 / 900.0, float(AshGhost.prof_adv_n) / 900.0, float(AshGhost.prof_adv_us) / maxf(1.0, float(AshGhost.prof_adv_n)),
				float(AshGhost.prof_look_us) / 1000.0 / 900.0, float(AshGhost.prof_part_us) / 1000.0 / 900.0,
				float(AshReplayView.prof_frame_us) / 1000.0 / 900.0, float(AshReplayView.prof_ground_us) / 1000.0 / 900.0]
		view.stop()
	print("ASHSIGHT_FARM stepbench tier=%d: view.step (6 ghosts, 60 Hz, replay 8-22 s) best-of-5 avg = %.4f ms (budget 0.30)" % [view.pool.detail, best])
	print("ASHSIGHT_FARM stepbench parts (per 60 Hz frame): " + best_parts)
	get_tree().quit(0 if best < 0.3 else 1)


# --- data checks ------------------------------------------------------------------------------

func _run_checks() -> int:
	var id := AshFakeRaid.record_into(mem, T_OFFSET)
	var r := AshFakeRaid.max_replay_error(mem, id, 0.05)
	var info := mem.replay_info(id)
	var ok := float(r["max_error"]) < 1.0
	print("ASHSIGHT_FARM check: actors=%d duration=%.1fs acts=%d max_error=%.3f m (%s)" % [
		(info["actors"] as Array).size(), info["duration"], (info["acts"] as Array).size(), r["max_error"], r["worst_actor"]])
	# acts must come back at the recorded instants, and the path must end in ash
	var saw_attack := false
	var saw_ash := false
	for e: Dictionary in mem.positions_at(id, 12.1):
		if String(e["id"]) == "b3" and e["act"] == &"attack" and absf(float(e["act_dt"]) - 0.1) < 0.02:
			saw_attack = true
	for i in 90:   # actors leave the 60 m circle at different times: someone must be crumbling at some point
		for e: Dictionary in mem.positions_at(id, 18.0 + float(i) * 0.1):
			if float(e["ash"]) > 0.05 and float(e["alpha"]) < 0.95:
				saw_ash = true
	# acts survive a save / load round trip (JSON), and a fallen actor stays where it fell
	var mem2 := AshMemory.new().setup(2) as AshMemory
	mem2.deserialize(JSON.parse_string(JSON.stringify(mem.serialize())))
	var info2 := mem2.replay_info(id)
	var acts_ok := (info2["acts"] as Array).size() == (info["acts"] as Array).size() and (info2["acts"] as Array).size() > 0
	mem2.act(id, T_OFFSET + 15.0, "v1", &"death")   # (recording API also works on a loaded, closed incident)
	var fell: Vector2 = Vector2.ZERO
	var still := true
	for i in 12:
		for e: Dictionary in mem2.positions_at(id, 16.0 + float(i) * 0.5):
			if String(e["id"]) == "v1":
				if i == 0: fell = e["pos"]
				still = still and (e["pos"] as Vector2).distance_to(fell) < 0.05 and float(e["speed"]) == 0.0
	# gait hysteresis: no flicker around a threshold
	var g := 0
	var flips := 0
	for i in 200:
		var sp := 2.7 + 0.15 * sin(float(i) * 0.9)
		var ng := AshGhostClips.next_gait(g, sp)
		if ng != g: flips += 1
		g = ng
	ok = ok and saw_attack and saw_ash and acts_ok and still and flips <= 2
	print("ASHSIGHT_FARM check: attack_at_instant=%s ash_at_end=%s acts_roundtrip=%s fallen_stay=%s gait_flips=%d" % [saw_attack, saw_ash, acts_ok, still, flips])
	print("ASHSIGHT_FARM ", "OK" if ok else "FAIL")
	return 0 if ok else 1


# --- frame loop ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ash == null and not gallery:
		return
	if gallery:
		_gallery_frame(delta)
		return
	_frames += 1
	_t += delta
	match _phase:
		0:
			_drift_camera(delta)
			if bench and _t > 0.5:
				_bench_sample(true)
			if _t >= INTRO_S:
				_phase = 1
				_t = 0.0
				ash.show_incident(mem, incident_id, 1.0)
		1:
			var t := ash.view.cursor.t if ash.view.cursor != null else 0.0
			if scrub_demo and not _scrubbed and t > 18.0:
				_scrubbed = true
				ash.view.seek(6.0)   # jump back to the arrival, as a thumb drag would
			if bench:
				_bench_sample(false)
			_track_errors(t)
			_shot()
		2:
			_outro_t += delta
			if _outro_t >= OUTRO_S and ash.grade < 0.01 and not ash.cam_rig.active:
				_phase = 3
				_finish()


## Phone-size stills (run windowed at e.g. --resolution 2400x1080 with --fixed-fps 30, no movie).
func _shot() -> void:
	if shots_dir == "" or _frames % shot_every != 0:
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1800:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png(shots_dir.path_join("shot%08d.png" % _shot_i))
	_shot_i += 1


func _track_errors(t: float) -> void:
	if ash.view.cursor == null:
		return
	for e: Dictionary in ash.view.cursor.frame():
		var id := String(e["id"])
		if float(e["alpha"]) >= 0.999 and float(e["ash"]) == 0.0 and AshFakeRaid.alive_at(id, t) and not _scrubbed:
			var err := (e["pos"] as Vector2).distance_to(AshFakeRaid.position_of(id, t))
			_errors[id] = maxf(float(_errors.get(id, 0.0)), err)


func _bench_sample(baseline: bool) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var frame := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if baseline:
		_bench_base_n += 1
		_bench_base_gpu += gpu
		_bench_base_cpu += cpu
		_bench_base_frame += frame
	elif ash.view.cursor != null and ash.view.max_active >= 4:
		if _bench_n == 0:
			AshGhost.profile = true
			AshGhost.prof_anim_us = 0
			AshGhost.prof_look_us = 0
			AshGhost.prof_part_us = 0
			AshGhost.prof_adv_us = 0
			AshGhost.prof_adv_n = 0
			AshReplayView.prof_frame_us = 0
			AshReplayView.prof_ground_us = 0
		_bench_n += 1
		_bench_gpu += gpu
		_bench_cpu += cpu
		_bench_frame += frame
		_bench_step += ash.view.last_frame_ms
		if ash.view.last_frame_ms > 1.5:
			_bench_spikes.append("t=%.2f %.2fms active=%d" % [ash.view.cursor.t, ash.view.last_frame_ms, ash.view.pool.active_count()])
		_bench_step_worst = maxf(_bench_step_worst, ash.view.last_frame_ms)


func _finish() -> void:
	var worst := 0.0
	var who := ""
	for id: String in _errors:
		if float(_errors[id]) > worst:
			worst = float(_errors[id])
			who = id
	var lines: Array[String] = []
	lines.append("ASHSIGHT_FARM frames=%d ghosts_max=%d path_error_max=%.3f m (%s) tier=%d" % [_frames, ash.view.max_active, worst, who, ash.view.pool.detail])
	if bench and _bench_n > 0:
		var n := float(_bench_n)
		var bn := maxf(1.0, float(_bench_base_n))
		lines.append("ASHSIGHT_FARM view.step avg=%.4f ms worst=%.4f ms (budget 0.30 ms, %d frames, tier=%d)" % [_bench_step / n, _bench_step_worst, _bench_n, ash.view.pool.detail])
		lines.append("ASHSIGHT_FARM   parts per frame: animation=%.4f ms look/materials=%.4f ms particles=%.4f ms (sum over all ghosts)" % [
			float(AshGhost.prof_anim_us) / 1000.0 / n, float(AshGhost.prof_look_us) / 1000.0 / n, float(AshGhost.prof_part_us) / 1000.0 / n])
		lines.append("ASHSIGHT_FARM   spikes over 1.5 ms: %s" % [", ".join(_bench_spikes.slice(0, 12))])
		lines.append("ASHSIGHT_FARM   AnimationPlayer.advance/seek: %.4f ms per frame, %.1f calls per frame, %.1f us per call" % [
			float(AshGhost.prof_adv_us) / 1000.0 / n, float(AshGhost.prof_adv_n) / n, float(AshGhost.prof_adv_us) / maxf(1.0, float(AshGhost.prof_adv_n))])
		lines.append("ASHSIGHT_FARM   positions_at=%.4f ms terrain height callable=%.4f ms (per frame, sandbox noise terrain)" % [
			float(AshReplayView.prof_frame_us) / 1000.0 / n, float(AshReplayView.prof_ground_us) / 1000.0 / n])
		lines.append("ASHSIGHT_FARM TIME_PROCESS baseline=%.3f ms replay=%.3f ms delta=%.3f ms" % [_bench_base_frame / bn, _bench_frame / n, _bench_frame / n - _bench_base_frame / bn])
		lines.append("ASHSIGHT_FARM render gpu baseline=%.3f ms replay=%.3f ms delta=%.3f ms | cpu baseline=%.3f replay=%.3f" % [
			_bench_base_gpu / bn, _bench_gpu / n, _bench_gpu / n - _bench_base_gpu / bn, _bench_base_cpu / bn, _bench_cpu / n])
		lines.append("ASHSIGHT_FARM draw calls (last frame)=%d primitives=%d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	var ok := worst < 1.0
	lines.append("ASHSIGHT_FARM " + ("OK" if ok else "FAIL"))
	for l in lines:
		print(l)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("ashsight_farm.txt"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
	get_tree().quit(0 if ok else 1)


# --- camera (the player's own view, before Ashsight takes over) ---------------------------------

func _drift_camera(delta: float) -> void:
	_cam_t += delta
	var k := clampf(_cam_t / INTRO_S, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var p := _cam_a.lerp(_cam_b, k)
	cam.global_position = p
	cam.look_at(Vector3(-7, 2.4, -2), Vector3.UP)


# --- terrain ------------------------------------------------------------------------------------

func terrain_h(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(YARD)
	var flat := smoothstep(20.0, 52.0, d)
	return (noise.get_noise_2d(x, z) * 5.5 + 0.35 * sin(x * 0.21) * cos(z * 0.17)) * flat


func terrain_h_v(p: Vector2) -> float:
	return terrain_h(p.x, p.y)


func _road_dist(p: Vector2) -> float:
	var best := 1.0e9
	for i in ROAD.size() - 1:
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


const SCORCH := [[Vector2(-15, -10), 7.0], [Vector2(-24, -1), 4.5], [Vector2(-33, -17), 5.0], [Vector2(-13, 6.5), 2.6], [Vector2(6, 9), 3.4], [Vector2(-21, 9), 3.6], [Vector2(0.5, -0.5), 2.0]]
const FIELD_MIN := Vector2(-30, 12)
const FIELD_MAX := Vector2(-9, 26)


func _ground_color(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var n := noise.get_noise_2d(x * 3.1, z * 3.1) * 0.5 + 0.5
	var n2 := noise.get_noise_2d(x * 0.9 + 100.0, z * 0.9) * 0.5 + 0.5
	# storybook meadow: saturated warm greens with yellow patches
	var grass := Color(0.30, 0.57, 0.18).lerp(Color(0.56, 0.68, 0.24), smoothstep(0.35, 0.8, n2))
	grass = grass.lerp(Color(0.28, 0.55, 0.20), smoothstep(0.55, 0.9, n) * 0.5)
	var col := grass
	var road := 1.0 - smoothstep(1.8, 3.4 + n * 0.8, _road_dist(p))
	col = col.lerp(Color(0.72, 0.57, 0.37), road * 0.95)
	var yard := 1.0 - smoothstep(YARD_R, YARD_R + 7.0 + n * 4.0, p.distance_to(YARD))
	col = col.lerp(Color(0.58, 0.44, 0.28).lerp(Color(0.50, 0.40, 0.26), n), yard * 0.8)
	var a := 0.0
	if x > FIELD_MIN.x and x < FIELD_MAX.x and z > FIELD_MIN.y and z < FIELD_MAX.y:
		var edge := minf(minf(x - FIELD_MIN.x, FIELD_MAX.x - x), minf(z - FIELD_MIN.y, FIELD_MAX.y - z))
		var m := smoothstep(0.0, 1.5, edge)
		col = col.lerp(Color(0.46, 0.31, 0.19), m)
		a = m
	for s: Array in SCORCH:
		var d := p.distance_to(s[0] as Vector2) + (n - 0.5) * 3.5
		var r: float = s[1]
		var burnt := 1.0 - smoothstep(r * 0.35, r * 1.15, d)
		var rim := (1.0 - smoothstep(r * 0.9, r * 1.7, d)) * 0.55
		col = col.lerp(Color(0.36, 0.32, 0.28), rim * 0.5)
		col = col.lerp(Color(0.17, 0.14, 0.12), burnt * 0.72)
	return Color(col.r, col.g, col.b, a)


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(TERRAIN_SIZE / TERRAIN_STEP)
	var half := TERRAIN_SIZE * 0.5
	var cols: Array[Color] = []
	var pts: Array[Vector3] = []
	for j in n + 1:
		for i in n + 1:
			var x := -half + float(i) * TERRAIN_STEP
			var z := -half + float(j) * TERRAIN_STEP
			pts.append(Vector3(x, terrain_h(x, z), z))
			cols.append(_ground_color(x, z))
	for j in n:
		for i in n:
			var i00 := j * (n + 1) + i
			var i10 := i00 + 1
			var i01 := i00 + n + 1
			var i11 := i01 + 1
			for idx: int in [i00, i10, i01, i10, i11, i01]:
				st.set_color(cols[idx])
				st.add_vertex(pts[idx])
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/region1/ashsight_ground.gdshader")
	mi.material_override = m
	mi.name = "Terrain"
	add_child(mi)


# --- world --------------------------------------------------------------------------------------

func _spawn(path: String, pos: Vector2, yaw := 0.0, scl := 1.0, scorch := -1.0, parent: Node = null) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("missing " + path)
		return null
	var n := ps.instantiate() as Node3D
	n.position = Vector3(pos.x, terrain_h(pos.x, pos.y), pos.y)
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scl
	(parent if parent != null else self).add_child(n)
	if path.contains("/nature/"):
		_nature_fix(n, path)
	if scorch >= 0.0:
		_scorch(n, scorch)
	return n


## Char a building: each surface keeps its own painted albedo under soot, ash and slow embers.
func _scorch(root: Node, amount: float) -> void:
	var shader := load("res://shaders/region1/ashsight_scorch.gdshader") as Shader
	var seed := float(root.get_instance_id() % 50)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(s)
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter(&"scorch", amount)
			m.set_shader_parameter(&"seed", seed)
			if orig is BaseMaterial3D:
				var b := orig as BaseMaterial3D
				m.set_shader_parameter(&"albedo_color", b.albedo_color)
				m.set_shader_parameter(&"use_vertex_color", b.vertex_color_use_as_albedo)
				if b.albedo_texture != null:
					m.set_shader_parameter(&"albedo_tex", b.albedo_texture)
					m.set_shader_parameter(&"use_tex", true)
				else:
					m.set_shader_parameter(&"use_tex", false)
			mi.set_surface_override_material(s, m)


## Burnt trees: the bark surfaces go charcoal, the twig cards stay.
func _char_bark(root: Node) -> void:
	if root == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.155, 0.13)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var is_bark := false
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
				is_bark = (mat as ShaderMaterial).shader.resource_path.contains("nature_opaque")
			if is_bark or (mat != null and mat.resource_path.contains("bark")):
				mi.set_surface_override_material(s, m)


func _face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


func _mesh_of(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var out: Mesh = null
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		out = mi.mesh
		break
	if out != null:
		for s in out.get_surface_count():
			var m := _nature_mat(out.surface_get_material(s), path)
			if m != null:
				out.surface_set_material(s, m)
	inst.free()
	return out


## The region nature GLBs carry wind data in COLOR_0 and are meant to use the ShaderMaterials in
## nature/ (rg_bark.tres, rg_foliage.tres ...). This checkout's .import files do not swap them yet,
## so the sandbox does it here (otherwise the vertex colour tints bark teal and leaves purple).
func _nature_mat(orig: Material, path: String) -> Material:
	if orig == null:
		return null
	var ground := path.contains("grass") or path.contains("flowers") or path.contains("fern")
	var n := REGION + "nature/"
	match orig.resource_name:
		"RG_Bark": return load(n + "rg_bark.tres")
		"RG_Foliage": return load(n + ("rg_foliage_ground.tres" if ground else "rg_foliage.tres"))
		"RG_Rock": return load(n + "rg_rock.tres")
		"RG_Moss": return load(n + "rg_moss.tres")
	return null


func _nature_fix(root: Node, path: String) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := _nature_mat(mi.get_active_material(s), path)
			if m != null:
				mi.set_surface_override_material(s, m)


func _scatter(path: String, count: int, rng: RandomNumberGenerator, area: Rect2, keep: Callable, smin: float, smax: float, lift := 0.0) -> void:
	var mesh := _mesh_of(path)
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var xf: Array[Transform3D] = []
	var guard := 0
	while xf.size() < count and guard < count * 12:
		guard += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if not keep.call(p):
			continue
		var s := rng.randf_range(smin, smax)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s))
		xf.append(Transform3D(b, Vector3(p.x, terrain_h(p.x, p.y) + lift, p.y)))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_world() -> void:
	# sky, light, haze: the sunny storybook day (docs/art/reference/00_MAIN...)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.26, 0.52, 0.92)
	sm.sky_horizon_color = Color(0.78, 0.88, 0.97)
	sm.ground_horizon_color = Color(0.74, 0.84, 0.90)
	sm.ground_bottom_color = Color(0.45, 0.62, 0.40)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.80, 0.88)   # cool sky bounce: blue-violet shadows, never black
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.85, 0.96)
	env.fog_density = 0.0042
	env.fog_aerial_perspective = 0.35
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.89, 0.70)
	sun.light_energy = 1.45
	sun.rotation_degrees = Vector3(-46, 128, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.04
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 44.0
	cam.far = 500.0
	cam.current = true
	add_child(cam)
	_cam_a = Vector3(6, 5.2, 27)
	_cam_b = Vector3(3, 4.4, 22)
	cam.global_position = _cam_a
	cam.look_at(Vector3(-7, 2.4, -2), Vector3.UP)
	_build_terrain()
	_build_farm()
	_build_dressing()


func _build_farm() -> void:
	var f := REGION + "farm/"
	var yard := YARD
	# the site marker the raiders chiselled: the wayshrine at the origin (the Runeward stone)
	_spawn(REGION + "road/wayshrine.glb", Vector2(0, 0), _face(Vector2(0, 0), Vector2(20, -12)), 1.35)
	# burned steadings around the yard
	_spawn(f + "barn.glb", Vector2(-15, -11), _face(Vector2(-15, -11), yard), 1.0, 0.7)
	_spawn(f + "granary.glb", Vector2(-24, -1), _face(Vector2(-24, -1), yard), 1.0, 0.6)
	var wm := _spawn(f + "windmill.glb", Vector2(-33, -17), _face(Vector2(-33, -17), yard), 1.0, 0.55)
	if wm != null:
		var hub := wm.find_child("sail_hub", true, false) as Node3D
		var sails := load(f + "windmill_sails.glb") as PackedScene
		if hub != null and sails != null:
			var sn := sails.instantiate() as Node3D
			hub.add_child(sn)
			sn.rotation.z = 0.5
			_scorch(sn, 0.6)
	_spawn(f + "chicken_coop.glb", Vector2(-13, 6.5), _face(Vector2(-13, 6.5), yard), 1.0, 0.75)
	_spawn(f + "hay_wagon.glb", Vector2(6, 9), 0.7, 1.0, 0.7)
	_spawn(f + "pig_sty.glb", Vector2(-21, 9), _face(Vector2(-21, 9), yard), 1.0, 0.65)
	_spawn(f + "scarecrow.glb", Vector2(-17, 18), 0.4, 1.0, 0.3)
	# a smouldering camp fire, crates, a fallen log: the yard should not be bare
	var cf := _spawn(REGION + "ruins/campfire.glb", Vector2(-9.5, -7.5), 0.6, 0.8)
	if cf != null:
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.55, 0.22)
		lt.light_energy = 1.2
		lt.omni_range = 7.0
		lt.position = Vector3(0, 0.6, 0)
		cf.add_child(lt)
	_spawn(REGION + "mine/mine_props.glb", Vector2(-19.5, 3.5), 0.9, 1.0, 0.5)
	_spawn(REGION + "nature/log_branchy.glb", Vector2(-2.5, -8), 0.3, 1.0)
	_spawn(REGION + "nature/stump_broken.glb", Vector2(-20, -8), 1.3, 1.0)
	_spawn(REGION + "nature/rock_slab.glb", Vector2(3.5, 4.5), 0.8, 1.0)
	# the field: trampled crops, some burned patches
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for cx in 5:
		for cz in 3:
			var p := Vector2(-27.5 + float(cx) * 4.1, 14.5 + float(cz) * 4.2)
			var burnt := rng.randf() < 0.35
			var n := _spawn(f + "crop_wheat.glb", p, 0.0, 1.0 if not burnt else 0.5)
			if n != null and burnt:
				_scorch(n, 0.85)
	# fence line along the road side of the yard, some panels fallen
	for i in 9:
		var p := Vector2(-31.0 + float(i) * 3.25, 27.5)
		var fell := i in [3, 4, 7]
		var n := _spawn(f + "fence_rail.glb", p, 0.0 if not fell else 0.5, 1.0, 0.45 if not fell else 0.9)
		if n != null and fell:
			n.rotation.z = 0.25
			n.position.y -= 0.1
	for i in 6:
		var p := Vector2(-8.0, 12.0 + float(i) * 3.25)
		_spawn(f + "fence_rail.glb", p, PI * 0.5, 1.0, 0.5)
	# smoke from the barn, the granary and the coop
	_smoke(Vector3(-15, terrain_h(-15, -11) + 5.5, -11), 1.3)
	_smoke(Vector3(-24, terrain_h(-24, -1) + 3.5, -1), 0.9)
	_smoke(Vector3(-13, terrain_h(-13, 6.5) + 1.8, 6.5), 0.7)
	_smoke(Vector3(-33, terrain_h(-33, -17) + 6.0, -17), 0.8)


func _smoke(pos: Vector3, size: float) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 34
	p.lifetime = 7.5
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -6, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.9 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.35, 0.05, 0.1)
	pm.scale_min = 1.4 * size
	pm.scale_max = 2.6 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.7))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.30, 0.26, 0.24, 0.0), Color(0.34, 0.30, 0.27, 0.42), Color(0.55, 0.50, 0.46, 0.22), Color(0.72, 0.68, 0.62, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/region1/ash_particle.gdshader")
	q.material = m
	p.draw_pass_1 = q
	add_child(p)


func _build_dressing() -> void:
	var n := REGION + "nature/"
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var away := func(p: Vector2, r: float) -> bool: return p.distance_to(YARD) > r
	var off_road := func(p: Vector2) -> bool: return _road_dist(p) > 9.0
	# living trees in a ring and in loose groves, dead snags near the burnt buildings
	for i in 46:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(38.0, 78.0)
		var p := YARD + Vector2(cos(ang), sin(ang)) * r
		if not off_road.call(p) or absf(p.x) > 80.0 or absf(p.y) > 80.0:
			continue
		var kinds := ["oak_a", "oak_b", "beech_a", "beech_b", "spruce_a", "young_oak", "dark_oak"]
		var k: String = kinds[rng.randi() % kinds.size()]
		_spawn(n + k + ".glb", p, rng.randf() * TAU, rng.randf_range(0.9, 1.3))
	for p: Vector2 in [Vector2(-4, -15), Vector2(-27, -10), Vector2(-31, 4), Vector2(9, -13), Vector2(-18, -20)]:
		var sn := _spawn(n + "dead_snag.glb", p, rng.randf() * TAU, rng.randf_range(0.7, 1.0))
		_char_bark(sn)
	# a few living oaks near the yard for warmth and shade
	_spawn(n + "oak_a.glb", Vector2(-2, -29), 0.5, 1.2)
	_spawn(n + "oak_b.glb", Vector2(-46, 14), 1.9, 1.1)
	_spawn(n + "oak_a.glb", Vector2(-40, -36), 2.4, 1.0)
	for i in 14:
		var p := YARD + Vector2(rng.randf_range(-46, 40), rng.randf_range(-40, 40))
		if p.distance_to(YARD) < 24.0 or not off_road.call(p):
			continue
		_spawn(n + ["bush_round.glb", "bush_hazel.glb", "bush_berry.glb", "bush_dark.glb"][rng.randi() % 4], p, rng.randf() * TAU, rng.randf_range(0.8, 1.3))
	for i in 9:
		var p := Vector2(rng.randf_range(-50, 40), rng.randf_range(-45, 35))
		if p.distance_to(YARD) < 20.0 or not off_road.call(p):
			continue
		_spawn(n + ["rock_medium.glb", "rock_cluster.glb", "boulder_large.glb", "stump_broken.glb", "log_mossy.glb"][rng.randi() % 5], p, rng.randf() * TAU, rng.randf_range(0.8, 1.4))
	# grass tufts and flowers, thin where the ground burned
	var meadow := func(p: Vector2) -> bool:
		if _road_dist(p) < 2.6 or p.distance_to(YARD) < YARD_R - 0.5:
			return false
		var c := _ground_color(p.x, p.y)
		return c.g > 0.42 and c.a < 0.1
	_scatter(n + "grass_a.glb", 2600, rng, Rect2(-55, -45, 96, 85), meadow, 0.8, 1.5)
	_scatter(n + "grass_tall.glb", 700, rng, Rect2(-55, -45, 96, 85), meadow, 0.8, 1.4)
	_scatter(n + "flowers_warm.glb", 220, rng, Rect2(-55, -50, 100, 90), meadow, 0.9, 1.5)
	_scatter(n + "flowers_cool.glb", 160, rng, Rect2(-55, -50, 100, 90), meadow, 0.9, 1.5)
	_scatter(n + "fern_a.glb", 60, rng, Rect2(-50, -50, 90, 80), meadow, 1.0, 1.6)


# --- gallery: the ghosts up close (--gallery) ------------------------------------------------------
## Back lanes: walkers (walk / jog / sprint) on a treadmill. Front row: an attack, a chisel, a hit,
## a fall, and a ghost crumbling into ash on a loop.

const GAL := Vector2(-6.0, 40.0)
var _gal_pool: AshGhostPool
var _gal_t := 0.0
var _gal: Array = []


func _build_gallery() -> void:
	cam.fov = 38.0
	var gy := terrain_h(GAL.x, GAL.y)
	cam.global_position = Vector3(GAL.x, gy + 1.9, GAL.y + 8.2)
	cam.look_at(Vector3(GAL.x, gy + 0.95, GAL.y), Vector3.UP)
	if dissolve_view:
		cam.fov = 34.0
		cam.global_position = Vector3(GAL.x, gy + 1.3, GAL.y + 4.6)
		cam.look_at(Vector3(GAL.x, gy + 1.0, GAL.y), Vector3.UP)
	# a clean stretch of the farm ground behind them
	_gal_pool = AshGhostPool.new()
	_gal_pool.capacity = 10
	_gal_pool.bandit_bodies = 6
	if tier >= 0:
		_gal_pool.detail_override = tier
	add_child(_gal_pool)
	await _gal_pool.warm()
	var rows := [
		# role, lane z, x0, speed, act, ash-cycle
		["bandit", 0.0, -1.1, 0.0, &"", true], ["villager", 0.0, 1.1, 0.0, &"", true],
	] if dissolve_view else [
		["bandit", -3.6, -6.0, 1.4, &"", false], ["bandit", -2.4, -6.0, 3.4, &"", false],
		["bandit", -1.2, -6.0, 5.6, &"", false], ["villager", -4.8, -6.0, 1.4, &"", false],
		["bandit", 1.4, -5.6, 0.0, &"attack", false], ["bandit", 1.4, -2.8, 0.0, &"chisel", false],
		["villager", 1.4, 0.0, 0.0, &"hit", false], ["villager", 1.4, 2.8, 0.0, &"death", false],
		["bandit", 1.4, 5.6, 0.0, &"", true],
	]
	for r: Array in rows:
		var g := _gal_pool.acquire(r[0])
		if g != null:
			_gal.append({"g": g, "r": r})
	_phase = 1


func _gallery_frame(delta: float) -> void:
	if _gal.is_empty():
		return
	_gal_t += delta
	var cyc := fposmod(_gal_t, 4.0)
	var i := 0
	for e: Dictionary in _gal:
		i += 1
		var r: Array = e["r"]
		var spd := float(r[3])
		var x := float(r[2])
		var heading := 0.0
		if spd > 0.0:
			x = -7.0 + fposmod(_gal_t * spd + float(i) * 1.7, 14.0)
			heading = -PI * 0.5   # walking towards +x
		var act: StringName = r[4]
		var ash := 0.0
		if bool(r[5]):
			ash = clampf((fposmod(_gal_t, 5.0) - 1.0) / 3.0, 0.0, 1.0)
		var entry := {"id": "g%d" % i, "heading": heading, "alpha": 1.0 - ash, "ash": ash, "speed": spd, "act": act,
			"act_dt": cyc - 1.0 if act != &"" else 0.0}
		var wx := GAL.x + x
		var wz := GAL.y + float(r[1])
		(e["g"] as AshGhost).apply(entry, Vector3(wx, terrain_h(wx, wz), wz), delta, 1.0)
		if int(_gal_t * 30.0) % 60 == 0 and delta > 0.0:
			var gg: AshGhost = e["g"]
			print("GAL t=%.2f %s act=%s dt=%.2f clip=%s pos=%.2f has_ap=%s" % [_gal_t, r[0], act, float(entry["act_dt"]), gg._clip, gg._ap.current_animation_position if gg._ap != null else -1.0, gg._ap != null])
	if _gal_t > 6.5:
		get_tree().quit(0)
