extends Node3D
## Elemental VFX showcase: every element x effect type on a stage with a character placeholder.
## Open elements_gallery.tscn and press F6.
##   Left / Right  element        Up / Down  effect type        Space  replay        A  auto-cycle everything
##   1..8 jump to an element      G  toggle generic effects    F  fps/GPU label       H  hide UI
## Capture / perf modes (windowed GPU run, console exe):
##   Godot --path kingdom --rendering-method mobile --resolution 1280x720 res://tools_qa/vfx_gallery/elements_gallery.tscn -- --capture=<abs dir>
##   ... -- --perf=<abs dir>     (per effect GPU ms + particle counts -> perf.tsv)
##   optional: --only=fire,ice   --tier=0..3
## Stop-motion review (Movie Maker, deterministic, one element: charge -> projectile -> impact -> aoe):
##   Godot --path kingdom --write-movie <dir>/frame.png --fixed-fps 30 --quit-after 165 res://tools_qa/vfx_gallery/elements_gallery.tscn -- --seq=fire [--tier=2]
##   (--seq=generic plays slash / sparks / dash / level up instead.)

const CAM := {
	"charge": [Vector3(1.9, 1.5, 2.6), Vector3(0.1, 1.15, -0.1)],
	"aura": [Vector3(2.6, 1.6, 3.6), Vector3(0, 1.0, 0)],
	"status": [Vector3(2.6, 1.6, 3.6), Vector3(0, 1.0, 0)],
	"projectile": [Vector3(3.6, 2.4, 3.2), Vector3(0, 1.1, -4.0)],
	"beam": [Vector3(4.2, 2.6, 2.2), Vector3(0, 1.1, -3.5)],
	"impact": [Vector3(2.8, 2.0, -2.2), Vector3(0, 1.0, -6.0)],
	"aoe": [Vector3(5.6, 4.4, -0.2), Vector3(0, 1.2, -6.0)],
	"generic": [Vector3(1.9, 1.7, 2.3), Vector3(0, 1.15, -0.7)],
	"level_up": [Vector3(4.2, 2.4, 5.2), Vector3(0, 1.8, 0)],
	"dash": [Vector3(3.2, 1.7, 3.6), Vector3(0, 1.0, 0.5)],
}
const TARGET := Vector3(0, 1.1, -6.0)
const CAP_TIMES := {
	"charge": [0.3, 0.6, 0.9, 1.2, 1.6], "aura": [0.3, 0.6, 0.9, 1.2, 1.6], "status": [0.3, 0.6, 0.9, 1.2, 1.6],
	"projectile": [0.12, 0.3, 0.48, 0.66, 0.9], "beam": [0.2, 0.5, 0.8, 1.1, 1.4], "impact": [0.05, 0.14, 0.28, 0.5, 0.85],
	"aoe": [0.1, 0.3, 0.55, 0.95, 1.5],
	"slash_sword": [0.03, 0.08, 0.14, 0.24, 0.4], "slash_fist": [0.03, 0.07, 0.12, 0.22, 0.36], "hit_sparks": [0.03, 0.08, 0.16, 0.28, 0.45],
	"dash": [0.05, 0.15, 0.3, 0.45, 0.6], "level_up": [0.1, 0.4, 0.8, 1.3, 2.0],
}

var cam: Camera3D
var character: Node3D
var hand: Node3D
var label: Label
var ui: CanvasLayer
var el_i := 0
var ty_i := 0
var types: Array[StringName] = []
var _live: Array = []
var _auto := false
var _auto_t := 0.0
var _capture_dir := ""
var _perf_dir := ""
var _only := ""
var _tier := -1
var _auto_els: PackedStringArray = []
var _cam_target := Vector3.ZERO
var _seq := ""
var _seq_t := 0.0
var _seq_i := 0
var _seq_fx: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_capture_dir = a.substr(10)
		elif a.begins_with("--perf="):
			_perf_dir = a.substr(7)
		elif a.begins_with("--only="):
			_only = a.substr(7)
		elif a.begins_with("--auto="):
			_auto_els = a.substr(7).split(",")
			_auto = true
		elif a.begins_with("--tier="):
			_tier = int(a.substr(7))
		elif a.begins_with("--seq="):
			_seq = a.substr(6)
	types.assign(ElementFX.TYPES)
	types.append_array(ElementFX.GENERIC)
	if not _auto_els.is_empty():
		el_i = maxi(ElementFX.ELEMENTS.find(StringName(_auto_els[0])), 0)
	_build_stage()
	_build_ui()
	if _tier >= 0:
		var q := get_node_or_null("/root/Quality")
		if q:
			q.set("tier", _tier)
	_focus()
	if _seq != "":
		ui.visible = false
		if _seq == "generic":
			cam.position = Vector3(2.6, 1.9, 2.8)
			cam.look_at(Vector3(0.0, 1.1, -0.6))
		else:
			cam.position = Vector3(6.2, 3.3, -0.6)
			cam.look_at(Vector3(0.0, 1.0, -3.4))
		return
	if _capture_dir != "" or _perf_dir != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		if _capture_dir != "":
			_run_capture.call_deferred()
		else:
			_run_perf.call_deferred()
	else:
		_replay.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_RIGHT:
			el_i = (el_i + 1) % ElementFX.ELEMENTS.size()
			_replay()
		KEY_LEFT:
			el_i = (el_i + ElementFX.ELEMENTS.size() - 1) % ElementFX.ELEMENTS.size()
			_replay()
		KEY_DOWN:
			ty_i = (ty_i + 1) % types.size()
			_replay()
		KEY_UP:
			ty_i = (ty_i + types.size() - 1) % types.size()
			_replay()
		KEY_SPACE:
			_replay()
		KEY_A:
			_auto = not _auto
		KEY_H:
			ui.visible = not ui.visible
		KEY_G:
			ty_i = ElementFX.TYPES.size() if ty_i < ElementFX.TYPES.size() else 0
			_replay()
		_:
			if e.keycode >= KEY_1 and e.keycode <= KEY_8:
				el_i = e.keycode - KEY_1
				_replay()


## Scripted timeline (seconds): charge 0-1.1, projectile released 1.1 (impact on arrival), aoe 3.0.
const SEQ := [[0.0, "charge"], [1.1, "release"], [3.0, "aoe"]]
const SEQ_GENERIC := [[0.0, "slash_sword"], [0.9, "slash_fist"], [1.8, "hit_sparks"], [2.6, "dash"], [3.6, "level_up"]]


func _seq_step(delta: float) -> void:
	_seq_t += delta
	var el: StringName = &"light" if _seq == "generic" else StringName(_seq)
	var list: Array = SEQ_GENERIC if _seq == "generic" else SEQ
	while _seq_i < list.size() and _seq_t >= float(list[_seq_i][0]):
		var what: String = list[_seq_i][1]
		_seq_i += 1
		match what:
			"charge":
				_seq_fx.append(ElementFX.attach(el, &"charge", hand, 1.0))
			"release":
				for f in _seq_fx:
					ElementFX.stop(f, 0.15)
				ElementFX.projectile(el, hand.global_position, TARGET, 9.0, 1.0)
			"aoe":
				ElementFX.aoe(el, Vector3(0, 0, -6), 3.0)
			"slash_sword":
				ElementFX.slash(el, Vector3(0, 1.2, -0.4), 0.0, 0.5, 1.6, false)
			"slash_fist":
				ElementFX.slash(el, Vector3(0, 1.2, -0.4), 0.0, -0.3, 1.6, true)
			"hit_sparks":
				ElementFX.hit_sparks(el, Vector3(0, 1.2, -1.0), Vector3(0, 0, 1))
			"dash":
				ElementFX.dash(el, character, Vector3(0, 0, -1), 3)
			"level_up":
				ElementFX.level_up(character.global_position, el)


func _process(delta: float) -> void:
	if _seq != "":
		_seq_step(delta)
		return
	if _auto:
		_auto_t += delta
		if _auto_t > 2.2:
			_auto_t = 0.0
			ty_i += 1
			if ty_i >= ElementFX.TYPES.size() and not _auto_els.is_empty():
				ty_i = 0
				var names: Array = _auto_els
				var k := names.find(String(ElementFX.ELEMENTS[el_i]))
				el_i = ElementFX.ELEMENTS.find(StringName(names[(k + 1) % names.size()]))
			elif ty_i >= types.size():
				ty_i = 0
				el_i = (el_i + 1) % ElementFX.ELEMENTS.size()
			_replay()
	if cam:
		cam.position = cam.position.lerp(_cam_pos, minf(delta * 5.0, 1.0))
		_cam_look = _cam_look.lerp(_cam_target, minf(delta * 5.0, 1.0))
		cam.look_at(_cam_look)
	label.text = "%s / %s   [%d/%d]   %d fps   A auto  G generic  H hide" % [ElementFX.ELEMENTS[el_i], types[ty_i], ty_i + 1, types.size(), Engine.get_frames_per_second()]


var _cam_pos := Vector3(3, 2, 3)
var _cam_look := Vector3.ZERO


func _focus(snap := false) -> void:
	var t := String(types[ty_i])
	var c: Array = CAM.get(t, CAM["generic"])
	_cam_pos = c[0]
	_cam_target = c[1]
	if snap:
		cam.position = _cam_pos
		_cam_look = _cam_target
		cam.look_at(_cam_look)


func _clear() -> void:
	for fx in _live:
		if is_instance_valid(fx):
			fx.halt()
	_live.clear()


func _replay() -> void:
	_clear()
	_focus()
	_spawn(ElementFX.ELEMENTS[el_i], types[ty_i])


func _spawn(el: StringName, t: StringName) -> void:
	var hand_pos := hand.global_position
	match t:
		&"charge":
			_live.append(ElementFX.attach(el, t, hand, 1.0))
		&"aura", &"status":
			_live.append(ElementFX.attach(el, t, character, 1.0))
		&"projectile":
			_live.append(ElementFX.projectile(el, hand_pos, TARGET, 9.0, 1.0))
		&"beam":
			_live.append(ElementFX.beam(el, hand_pos, TARGET + Vector3(0, -0.2, 0), 1.0, 1.6))
		&"impact":
			_live.append(ElementFX.play(el, t, TARGET, Vector3(0, 0, 1), 1.0))
		&"aoe":
			_live.append(ElementFX.aoe(el, Vector3(0, 0, -6), 3.0))
		&"slash_sword":
			_live.append(ElementFX.slash(el, Vector3(0, 1.2, -0.4), 0.0, 0.5, 1.6, false))
		&"slash_fist":
			_live.append(ElementFX.slash(el, Vector3(0, 1.2, -0.4), 0.0, -0.3, 1.6, true))
		&"hit_sparks":
			_live.append(ElementFX.hit_sparks(el, Vector3(0, 1.2, -1.0), Vector3(0, 0, 1)))
		&"dash":
			_live.append(ElementFX.dash(el, character, Vector3(0, 0, -1), 3))
		&"level_up":
			_live.append(ElementFX.level_up(character.global_position, el))


# ---------------------------------------------------------------- stage
func _build_stage() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/free/storybook_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.95)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.46, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(0, 0, -6)
	add_child(ground)
	# warm stone paving around the caster and the target
	for c in [Vector3(0, 0.01, 0), Vector3(0, 0.01, -6)]:
		var d := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.6
		cyl.bottom_radius = 3.6
		cyl.height = 0.02
		cyl.radial_segments = 40
		d.mesh = cyl
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.6, 0.52, 0.4)
		sm.roughness = 1.0
		d.material_override = sm
		d.position = c
		add_child(d)
	character = Node3D.new()
	character.name = "Character"
	add_child(character)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.26
	cm.height = 1.35
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.36, 0.72)
	body.material_override = bm
	body.position = Vector3(0, 0.85, 0)
	character.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	hm.height = 0.32
	head.mesh = hm
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.76, 0.6)
	head.material_override = skin
	head.position = Vector3(0, 1.72, 0)
	character.add_child(head)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.05, 0.05, 0.09)
	nose.mesh = nm
	nose.material_override = skin
	nose.position = Vector3(0, 1.7, -0.16)
	character.add_child(nose)
	hand = Node3D.new()
	hand.name = "HandR"
	hand.position = Vector3(0.36, 1.2, -0.28)
	character.add_child(hand)
	var hmesh := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 0.07
	hsm.height = 0.14
	hmesh.mesh = hsm
	hmesh.material_override = skin
	hand.add_child(hmesh)
	var target := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.28
	tm.bottom_radius = 0.34
	tm.height = 1.6
	target.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.6, 0.42, 0.26)
	target.material_override = tmat
	target.position = Vector3(0, 0.8, -6.0)
	add_child(target)
	cam = Camera3D.new()
	cam.fov = 52.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.position = Vector3(3, 2, 3)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(14, 10)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	ui.add_child(label)


# ---------------------------------------------------------------- capture
func _shot() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < int(sec * 1000.0):
		await get_tree().process_frame


func _elements() -> Array:
	var out: Array = []
	for e in ElementFX.ELEMENTS:
		if _only == "" or _only.split(",").has(String(e)):
			out.append(e)
	return out


func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	ui.visible = false
	await _wait(1.5)
	var cw := 384
	var ch := 216
	var sheets := {}
	var groups: Array = []
	for e in _elements():
		groups.append([String(e), ElementFX.TYPES])
	if _only == "" or _only.split(",").has("generic"):
		groups.append(["generic", ElementFX.GENERIC])
	for g in groups:
		var name_: String = g[0]
		var tl: Array = g[1]
		var sheet := Image.create(cw * 5, ch * tl.size(), false, Image.FORMAT_RGB8)
		var row := 0
		for t: StringName in tl:
			ty_i = types.find(t)
			el_i = maxi(ElementFX.ELEMENTS.find(StringName(name_)), 0) if name_ != "generic" else 6
			_clear()
			await _wait(0.25)
			_focus(true)
			await _wait(0.2)
			_replay()
			var times: Array = CAP_TIMES[String(t)]
			var t0 := Time.get_ticks_msec()
			for i in times.size():
				while (Time.get_ticks_msec() - t0) < int(float(times[i]) * 1000.0):
					await get_tree().process_frame
				var img := await _shot()
				img.convert(sheet.get_format())
				img.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
				sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i(i * cw, row * ch))
				if _only != "" or i == 2:
					var full := get_viewport().get_texture().get_image()
					full.save_png(_capture_dir.path_join("%s_%s_%d.png" % [name_, t, i]))
			row += 1
			_clear()
			await _wait(0.3)
		sheet.save_png(_capture_dir.path_join("sheet_%s.png" % name_))
		print("sheet ", name_)
	get_tree().quit()


# ---------------------------------------------------------------- perf
func _particles(n: Node) -> int:
	var c := 0
	for ch in n.find_children("*", "GPUParticles3D", true, false):
		var p := ch as GPUParticles3D
		if p.visible and p.emitting:
			c += int(p.amount * p.amount_ratio)
	for ch in n.find_children("*", "CPUParticles3D", true, false):
		var p := ch as CPUParticles3D
		if p.visible and p.emitting:
			c += p.amount
	return c


func _meshes(n: Node) -> int:
	var c := 0
	for ch in n.find_children("*", "MeshInstance3D", true, false):
		if (ch as MeshInstance3D).is_visible_in_tree():
			c += 1
	return c


func _run_perf() -> void:
	DirAccess.make_dir_recursive_absolute(_perf_dir)
	ui.visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(2.0)
	var lines: PackedStringArray = []
	lines.append("renderer=%s adapter=%s window=%s tier=%d" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_window().size, ElementFX._tier()])
	lines.append("effect\tgpu_avg_ms\tgpu_peak_ms\tdelta_avg_ms\tdelta_peak_ms\tparticles_peak\tmeshes\tdraw_calls_peak_delta")
	var groups: Array = []
	for e in _elements():
		groups.append([String(e), ElementFX.TYPES])
	if _only == "" or _only.split(",").has("generic"):
		groups.append(["generic", ElementFX.GENERIC])
	# baseline per view
	var jobs: Array = []
	for g in groups:
		for t: StringName in g[1]:
			jobs.append([g[0], t])
	var base_by_cam := {}
	for j in jobs:
		var t: StringName = j[1]
		ty_i = types.find(t)
		el_i = maxi(ElementFX.ELEMENTS.find(StringName(j[0])), 0) if j[0] != "generic" else 6
		_clear()
		_focus(true)
		await _wait(0.5)
		var b_gpu := 0.0
		var b_dc := 0
		var n := 0
		var key := str(_cam_pos)
		if not base_by_cam.has(key):
			for i in 90:
				await get_tree().process_frame
				b_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				b_dc += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				n += 1
			base_by_cam[key] = [b_gpu / n, float(b_dc) / n]
		var base: Array = base_by_cam[key]
		_replay()
		var life := 2.0 if t != &"level_up" else 3.0
		var t0 := Time.get_ticks_msec()
		var sum := 0.0
		var peak := 0.0
		var fr := 0
		var pmax := 0
		var mesh_n := 0
		var dcmax := 0.0
		while (Time.get_ticks_msec() - t0) < int(life * 1000.0):
			await get_tree().process_frame
			var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			sum += g
			peak = maxf(peak, g)
			fr += 1
			dcmax = maxf(dcmax, float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			for fx in _live:
				if is_instance_valid(fx):
					pmax = maxi(pmax, _particles(fx))
					mesh_n = maxi(mesh_n, _meshes(fx))
		var avg := sum / maxf(fr, 1)
		lines.append("%s/%s\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%d\t%d" % [j[0], t, avg, peak, avg - base[0], peak - base[0], pmax, mesh_n, int(dcmax - base[1])])
		print(lines[-1])
		_clear()
	var f := FileAccess.open(_perf_dir.path_join("perf.tsv"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	get_tree().quit()
