extends Node3D
## Addon proof-of-life demos (QA only, not wired into gameplay).
##   Godot --path kingdom --rendering-method mobile res://tools_qa/addons_demo/addons_demo.tscn -- --demo=<pcam|debugmenu|footsteps|grass|shatter> --capture=<abs dir>
## Without --capture the demo stays open (interactive). With --capture it takes screenshots + a perf table and quits.

const H := preload("res://tools_qa/addons_demo/harness.gd")

var demo := "pcam"
var cap_dir := ""
var cam: Camera3D
var log_lines: PackedStringArray = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="): demo = a.substr(7)
		if a.begins_with("--capture="): cap_dir = a.substr(10)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	H.sunny_world(self)
	H.ground(self)
	cam = Camera3D.new()
	cam.current = true
	add_child(cam)
	cam.position = Vector3(0, 4, 10)
	cam.look_at(Vector3(0, 1, 0))
	H.label(self, "addon demo: " + demo)
	call("_demo_" + demo)

func _finish(name_: String) -> void:
	log_lines.append("renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	if cap_dir != "":
		DirAccess.make_dir_recursive_absolute(cap_dir)
		var f := FileAccess.open(cap_dir.path_join(name_ + "_perf.txt"), FileAccess.WRITE)
		f.store_string("\n".join(log_lines) + "\n")
		f.close()
		print("\n".join(log_lines))
		get_tree().quit()

func _cube(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m

# ------------------------------------------------------------------ Phantom Camera
func _demo_pcam() -> void:
	var hero := _cube(Vector3(0, 0.9, 0), Vector3(0.8, 1.8, 0.8), Color(0.75, 0.2, 0.15))
	var tower := _cube(Vector3(14, 4, -12), Vector3(4, 8, 4), Color(0.6, 0.55, 0.5))
	for i in 6:
		_cube(Vector3(-8 + i * 3.2, 1.0, -6 - (i % 2) * 3), Vector3(1.6, 2, 1.6), Color.from_hsv(0.08 + i * 0.05, 0.4, 0.8))
	var host := PhantomCameraHost.new()
	cam.add_child(host)
	# 1) follow cam: third-person-ish follow with look-at
	var follow := PhantomCamera3D.new()
	follow.priority = 10
	follow.follow_mode = PhantomCamera3D.FollowMode.SIMPLE
	follow.follow_target = hero
	follow.follow_offset = Vector3(0, 3.2, 7.0)
	follow.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
	follow.look_at_target = hero
	add_child(follow)
	# 2) cinematic establishing shot of the tower (low priority until triggered)
	var cine := PhantomCamera3D.new()

	cine.position = Vector3(2, 2.0, -2)
	cine.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
	cine.look_at_target = tower
	var tw := PhantomCameraTween.new()
	tw.duration = 1.5
	tw.transition = PhantomCameraTween.TransitionType.SINE
	cine.tween_resource = tw
	add_child(cine)
	# 3) camera shake via noise emitter (replaces hand-rolled camera_shake.gd if desired)
	var noise := PhantomCameraNoise3D.new()
	noise.amplitude = 6.0
	noise.frequency = 0.6
	var emitter := PhantomCameraNoiseEmitter3D.new()
	emitter.noise = noise
	emitter.duration = 0.6
	add_child(emitter)
	var walker := create_tween().set_loops()
	walker.tween_property(hero, "position:x", 6.0, 3.0)
	walker.tween_property(hero, "position:x", -6.0, 3.0)
	if cap_dir == "":
		return
	await get_tree().create_timer(1.5).timeout
	await H.shot(get_tree(), cap_dir, "pcam_1_follow")
	var m0 := await H.measure(get_tree(), 200)
	log_lines.append(H.fmt("follow pcam active", m0))
	cine.priority = 20        # blend to the cinematic cam over 1.5 s
	await get_tree().create_timer(0.7).timeout
	await H.shot(get_tree(), cap_dir, "pcam_2_mid_blend")
	await get_tree().create_timer(1.6).timeout
	await H.shot(get_tree(), cap_dir, "pcam_3_cinematic")
	emitter.emit()
	await get_tree().create_timer(0.15).timeout
	await H.shot(get_tree(), cap_dir, "pcam_4_shake")
	await get_tree().create_timer(1.0).timeout
	var m1 := await H.measure(get_tree(), 200)
	log_lines.append(H.fmt("cinematic pcam active", m1))
	# baseline: no addon nodes in the tree at all (cost of the addon itself)
	for n in [follow, cine, emitter, host]:
		n.queue_free()
	await get_tree().process_frame
	cam.position = Vector3(0, 4, 10)
	cam.look_at(Vector3(0, 1, 0))
	var mb := await H.measure(get_tree(), 200)
	log_lines.append(H.fmt("baseline (no pcam nodes, plain Camera3D)", mb))
	_finish("pcam")

# ------------------------------------------------------------------ Debug Menu (Calinou)
func _demo_debugmenu() -> void:
	for i in 40:
		_cube(Vector3(-15 + (i % 8) * 4, 1, -4 - (i / 8) * 4), Vector3(2, 2, 2), Color.from_hsv(i * 0.02, 0.5, 0.85))
	var dm: CanvasLayer = load("res://addons/debug_menu/debug_menu.tscn").instantiate()
	add_child(dm)
	if cap_dir == "":
		return
	await get_tree().create_timer(1.0).timeout
	# style 2 = VISIBLE_DETAILED (F3 cycles hidden > compact > detailed)
	dm.style = 2
	await get_tree().create_timer(3.5).timeout
	await H.shot(get_tree(), cap_dir, "debugmenu_detailed")
	var m1 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("debug menu detailed", m1))
	dm.style = 0
	await get_tree().process_frame
	var m0 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("debug menu hidden", m0))
	dm.queue_free()
	await get_tree().process_frame
	var mb := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("debug menu not in tree", mb))
	_finish("debugmenu")

# ------------------------------------------------------------------ Material footsteps
var _fs_log: PackedStringArray = []

func _demo_footsteps() -> void:
	# Three pads (grass / stone / wood), each StaticBody3D carries meta "surface_type" (the addon default key).
	var kinds := {"grass": Color(0.35, 0.6, 0.25), "stone": Color(0.6, 0.6, 0.62), "wood": Color(0.55, 0.36, 0.2)}
	var i := 0
	for k in kinds:
		var body := StaticBody3D.new()
		body.set_meta("surface_type", k)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(6, 0.4, 6)
		col.shape = bs
		body.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = kinds[k]
		mi.material_override = mat
		body.add_child(mi)
		body.position = Vector3(-6.5 + i * 6.5, -0.05, 0)
		add_child(body)
		i += 1
	var chara := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	chara.add_child(cs)
	var cm := MeshInstance3D.new()
	var capm := CapsuleMesh.new()
	capm.radius = 0.35
	capm.height = 1.8
	cm.mesh = capm
	chara.add_child(cm)
	chara.position = Vector3(-8, 1.0, 0)
	add_child(chara)
	var fp := MaterialFootstepPlayer3D.new()
	fp.character = chara
	fp.debug = false
	fp.target_position = Vector3(0, -1.2, 0)
	fp.auto_play_type = MaterialFootstepPlayer3D.AutoPlayType.STATIC
	fp.auto_play_delay = 0.3
	var idx := 0
	for k in kinds:
		var s := MaterialFootstep.new()
		s.material_name = k
		s.movement_sound = _tone(k, 220.0 + 110.0 * idx)
		fp.material_footstep_sound_map.append(s)
		idx += 1
	fp.default_material_footstep_movement_sound = _tone("DEFAULT", 90.0)
	chara.add_child(fp)
	var lbl := H.label(self, "")
	lbl.position.y = 44
	cam.position = Vector3(0, 3.5, 9)
	cam.look_at(Vector3(0, 0.8, 0))

	get_tree().physics_frame.connect(func() -> void:
		chara.velocity = Vector3(3.0, -1.0, 0)
		chara.move_and_slide()
		if chara.position.x > 8.5:
			chara.position.x = -8.0
		var ap := fp.get_child(0) as AudioStreamPlayer3D
		if ap and ap.stream and ap.playing:
			var nm := String(ap.stream.resource_name)
			lbl.text = "x=%.1f  last footstep sound: %s" % [chara.position.x, nm]
			
			if _fs_log.is_empty() or not _fs_log[-1].begins_with(nm):
				_fs_log.append("%s@%.1f" % [nm, chara.position.x]))

	if cap_dir == "":
		return
	await get_tree().create_timer(1.2).timeout
	await H.shot(get_tree(), cap_dir, "footsteps_1")
	await get_tree().create_timer(1.6).timeout
	await H.shot(get_tree(), cap_dir, "footsteps_2")
	await get_tree().create_timer(2.6).timeout
	await H.shot(get_tree(), cap_dir, "footsteps_3")
	await get_tree().create_timer(1.5).timeout
	log_lines.append("surfaces detected in order while walking grass>stone>wood: " + ", ".join(_fs_log))
	var m1 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("footstep player active (1 raycast + detector chain)", m1))
	fp.auto_play_type = MaterialFootstepPlayer3D.AutoPlayType.DISABLED
	var m0 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("footstep player disabled", m0))
	_finish("footsteps")

func _tone(nm: String, hz: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.08)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := int(sin(TAU * hz * i / rate) * 9000.0 * (1.0 - float(i) / n))
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.resource_name = nm
	return w

# ------------------------------------------------------------------ SimpleGrassTextured
func _demo_grass() -> void:
	# The grass nodes look up /root/SimpleGrass (wind + optional interactive height map). The addon registers it as an
	# autoload; we do NOT autoload it in the game (integration plan: add it at runtime only on levels that use grass).
	# SimpleGrass global shader parameters (the addon plugin normally adds these to project.godot when enabled)
	var gp := {
		"sgt_legacy_renderer": [RenderingServer.GLOBAL_VAR_TYPE_INT, 0],
		"sgt_player_position": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1000000, 1000000, 1000000)],
		"sgt_player_mov": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO],
		"sgt_normal_displacement": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, load("res://addons/simplegrasstextured/images/normal.png")],
		"sgt_motion_texture": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, load("res://addons/simplegrasstextured/images/motion.png")],
		"sgt_wind_direction": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1, 0, 0)],
		"sgt_wind_movement": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO],
		"sgt_wind_strength": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.15],
		"sgt_wind_turbulence": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		"sgt_wind_pattern": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, load("res://addons/simplegrasstextured/images/wind_pattern.png")],
	}
	for k in gp:
		if RenderingServer.global_shader_parameter_get(k) == null:
			RenderingServer.global_shader_parameter_add(k, gp[k][0], gp[k][1])
	var sg: Node3D = load("res://addons/simplegrasstextured/singleton.tscn").instantiate()
	sg.name = "SimpleGrass"
	get_tree().root.add_child.call_deferred(sg)
	await get_tree().process_frame
	var grass := MultiMeshInstance3D.new()
	grass.set_script(load("res://addons/simplegrasstextured/grass.gd"))
	grass.set("interactive", false)
	grass.set("optimization_by_distance", true)
	grass.set("optimization_dist_min", 12.0)
	grass.set("optimization_dist_max", 45.0)
	grass.set("scale_h", 1.4)
	grass.set("scale_w", 1.2)
	grass.set("grass_strength", 0.7)
	grass.set("albedo", Color(0.62, 0.78, 0.42))  # tint toward the storybook palette (default is neon lime)
	add_child(grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xf: Array = []
	for i in 30000:
		var p := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 8))
		xf.append(grass.call("eval_grass_transform", p, Vector3.UP, Vector3.ONE * rng.randf_range(0.7, 1.3), rng.randf() * TAU))
	grass.call("add_grass_batch", xf)
	grass.call("_update_multimesh")  # runtime: process is off, so flush the buffer ourselves (normally painted+saved in editor)
	cam.position = Vector3(0, 1.6, 12)
	cam.look_at(Vector3(0, 0.8, 0))
	for j in 5:
		_cube(Vector3(-8 + j * 4, 0.6, 2 - (j % 2) * 3), Vector3(1.2, 1.2, 1.2), Color(0.55, 0.5, 0.45))
	if cap_dir == "":
		return
	await get_tree().create_timer(2.0).timeout
	await H.shot(get_tree(), cap_dir, "grass_1")
	cam.position = Vector3(0, 6.0, 14)
	cam.look_at(Vector3(0, 0, -4))
	await get_tree().create_timer(0.5).timeout
	await H.shot(get_tree(), cap_dir, "grass_2_high")
	var m1 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("30000 grass blades (1 MultiMesh, distance opt on) high cam", m1))
	cam.position = Vector3(0, 1.6, 12)
	cam.look_at(Vector3(0, 0.8, 0))
	var m2 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("30000 grass blades low cam", m2))
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m3 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("30000 blades, shadow casting OFF", m3))
	grass.multimesh.visible_instance_count = 10000
	var m4 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("10000 blades, shadow casting OFF", m4))
	grass.visible = false
	var m0 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("grass hidden (baseline)", m0))
	_finish("grass")

# ------------------------------------------------------------------ VoronoiShatter
func _demo_shatter() -> void:
	var crate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.4, 1.4)
	crate.mesh = bm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.42, 0.22)
	wood.roughness = 0.9
	crate.material_override = wood
	var gen := VoronoiGenerator.new()
	add_child(gen)
	var vs := VoronoiShatter.new()
	vs.random_color = true
	vs.samples = 22
	vs.seed = 4
	vs.voronoi_generator = gen
	vs.position = Vector3(0, 0.7, 0)
	add_child(vs)
	vs.add_child(crate)
	var t0 := Time.get_ticks_usec()
	vs.started = t0
	vs.generate_fracture_meshes(vs.get_config())
	await get_tree().create_timer(1.0).timeout
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var coll: VoronoiCollection
	for c in vs.get_children():
		if c is VoronoiCollection:
			coll = c
	log_lines.append("fracture generation (editor-time step, 22 samples, box): %.0f ms incl. 1 s wait, %d pieces" % [gen_ms, coll.get_child_count() if coll else 0])
	if coll == null or coll.get_child_count() == 0:
		log_lines.append("NO PIECES GENERATED")
		_finish("shatter")
		return
	cam.position = Vector3(0, 2.2, 5.5)
	cam.look_at(Vector3(0, 0.8, 0))
	if cap_dir != "":
		await H.shot(get_tree(), cap_dir, "shatter_1_intact_pieces")
	coll.create_rigid_bodies()
	await get_tree().process_frame
	var bodies: Array = []
	for c in coll.get_children():
		if c is RigidBody3D:
			bodies.append(c)
	log_lines.append("rigid bodies: %d" % bodies.size())
	for b in bodies:
		var dir: Vector3 = (b.global_position - vs.global_position).normalized() + Vector3.UP * 0.6
		b.apply_central_impulse(dir * 2.6)
		b.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	if cap_dir == "":
		return
	await get_tree().create_timer(0.35).timeout
	await H.shot(get_tree(), cap_dir, "shatter_2_exploding")
	await get_tree().create_timer(1.2).timeout
	await H.shot(get_tree(), cap_dir, "shatter_3_settled")
	var m1 := await H.measure(get_tree(), 240)
	log_lines.append(H.fmt("%d rigid shards (Jolt)" % bodies.size(), m1))
	_finish("shatter")
