extends Node
## On-device frame-time bench (Android/any). The desktop tools/qa/bench/bench.gd is excluded from phone exports
## (res://tools/* is dropped) and is a `-s` SceneTree script, so this is the same idea as a scene.
## Launch (phone):
##   adb shell am start -n com.risingashes.game/com.godot.game.GodotApp --esa command_line_params \
##     "res://tools_qa/phone/phone_bench.tscn,--,--adult,--skipintro,--tiers=low:medium:high,--scenes=village:city:aerial:battle:vale,--settle=8,--seconds=10"
## Output: one `PHONEBENCH {json}` log line per (tier, scene) in logcat (tag godot), plus jpgs in user://phonebench/.
## Restores the quality choice at the end so the owner's settings are not changed.
const OUT_DIR := "user://phonebench"

var args := {}
var main: Control
var world_vp: SubViewport
var _old_choice := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	reparent.call_deferred(get_tree().root)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	_run.call_deferred()


func _q() -> Node:
	return get_node("/root/Quality")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("PHONEBENCH start device=", RenderingServer.get_video_adapter_name(), " renderer=", RenderingServer.get_current_rendering_method(),
		" cores=", OS.get_processor_count(), " mem=", OS.get_memory_info().get("physical", 0) / 1048576, "MB")
	while true:
		main = get_tree().current_scene as Control
		if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._veil():
			break
		await get_tree().process_frame
	_old_choice = _q().choice
	world_vp = main.viewport
	RenderingServer.viewport_set_measure_render_time(world_vp.get_viewport_rid(), true)
	var tiers: PackedStringArray = String(args.get("tiers", "low:medium:high")).split(":", false)
	var scenes: PackedStringArray = String(args.get("scenes", "village:city:aerial:battle:vale")).split(":", false)
	for tn in tiers:
		var ti := ["low", "medium", "high", "ultra"].find(tn.to_lower())
		if ti < 0:
			continue
		_q().set_choice(ti)
		for sc in scenes:
			await _stage(sc)
			await _wait(float(args.get("settle", "8")))
			await _measure(sc, tn)
	if not args.has("nodungeon"):
		await _dungeons(tiers)
	_q().set_choice(_old_choice)
	print("PHONEBENCH done")


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _al(n: String) -> Node:
	return get_node("/root/" + n)


func _stage(scene: String) -> void:
	_al("WorldSim").time_of_day = float(args.get("hour", "15.0"))
	var WG := load("res://scripts/world/world_gen.gd")
	match scene:
		"village":
			main._teleport(Vector2(1.0, 7.5), 0.0)
			main.player.set_camera(0.25, -0.12)
		"city":
			var cap: Dictionary = WG.settlements[1]
			var cp: Vector2 = cap["pos"]
			var gate: float = cap["plan"]["gates"][0]
			var sp: Vector2 = cp + Vector2(cos(gate), sin(gate)) * (cap["plan"]["plaza_r"] + 30.0)
			main._teleport(sp, 0.0)
			var look: Vector2 = cp - sp
			main.player.set_camera(atan2(-look.x, -look.y), -0.12)
		"aerial":
			main._teleport(Vector2(20, 26), PI * 0.2)
			main.player.zoom(1)
			main.player.zoom(1)
		"battle":
			_al("Game").rank = 2
			var p := Vector2(main.FIRST_CAMP.x - 22, main.FIRST_CAMP.y + 6)
			main._teleport(p, 0.0)
			main._recruit(24)
			for s in main.army.soldiers:
				s.global_position = main.player.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			main.army.command(2)
			main.player.set_camera(-PI * 0.5 + 0.35, -0.25)
		"vale":
			var HV := load("res://scripts/world/hidden_valley.gd")
			var at: Vector2 = HV.w(60.0, 0.0)
			main._teleport(at, 0.0)
			var look2: Vector2 = HV.w(-20.0, 0.0) - at
			main.player.set_camera(atan2(-look2.x, -look2.y), -0.1)
		"vale_gorge":
			var HV2 := load("res://scripts/world/hidden_valley.gd")
			var at2: Vector2 = HV2.w(-100.0, 0.0)
			main._teleport(at2, 0.0)
			var look3: Vector2 = HV2.w(-160.0, 0.0) - at2
			main.player.set_camera(atan2(-look3.x, -look3.y), -0.1)
	if args.has("nohud"):
		main.hud.visible = false


func _measure(scene: String, tier: String) -> void:
	var frames := PackedFloat32Array()
	var gpu := PackedFloat32Array()
	var cpu := PackedFloat32Array()
	var draws := PackedFloat32Array()
	var prims := PackedFloat32Array()
	var t := 0.0
	var secs := float(args.get("seconds", "10"))
	while t < secs:
		await get_tree().process_frame
		var d := get_process_delta_time()
		t += d
		frames.append(d * 1000.0)
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(world_vp.get_viewport_rid()))
	var over33 := 0
	var over50 := 0
	for f in frames:
		if f > 33.4:
			over33 += 1
		if f > 50.0:
			over50 += 1
	var r := {
		"scene": scene, "tier": tier, "quality_now": _q().tier_name(), "frames": frames.size(), "fps_avg": 1000.0 / _mean(frames),
		"ms_avg": _mean(frames), "ms_p95": _pct(frames, 0.95), "ms_p99": _pct(frames, 0.99), "ms_max": _pct(frames, 1.0),
		"over33": over33, "over50": over50, "gpu_ms": _mean(gpu), "cpu_ms": _mean(cpu),
		"draws": _mean(draws), "prims_k": _mean(prims) / 1000.0, "vp": "%dx%d" % [world_vp.size.x, world_vp.size.y], "scale": world_vp.scaling_3d_scale,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"npc_full": main.population.full_count, "npc_sprites": main.population.sprite_count,
		"max_fps": Engine.max_fps, "battery_saver": _q().battery_saver,
	}
	print("PHONEBENCH ", JSON.stringify(r))
	var img := get_tree().root.get_texture().get_image()
	img.save_jpg("%s/%s_%s.jpg" % [OUT_DIR, scene, tier], 0.85)


func _dungeons(tiers: PackedStringArray) -> void:
	# Free the world first: the dungeon runs alone like tools_qa/caves/caves_standalone.gd.
	if main:
		main.queue_free()
		main = null
	for i in 20:
		await get_tree().process_frame
	var Gen: GDScript = load("res://scripts/interiors/dungeon_gen.gd")
	var Build: GDScript = load("res://scripts/interiors/dungeon_build.gd")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	for theme in String(args.get("themes", "cave:crypt")).split(":", false):
		for tn in tiers:
			var ti := ["low", "medium", "high", "ultra"].find(tn.to_lower())
			_q().set_choice(ti)
			var g: Dictionary = Gen.generate(11, theme, 2, {"id": "qa_" + theme, "rooms": 9})
			var interior: Node3D = Build.build(g, {}, {"creatures": true})
			interior.position = Vector3(0, 300, 0)
			world.add_child(interior)
			var env := interior.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
			cam.environment = env.environment
			var sp := interior.get_node("PlayerSpawn") as Node3D
			player.global_position = sp.global_position
			var c0: Vector3 = interior.global_position + Gen.cell_pos(g, g["rooms"][0]["center"])
			cam.global_position = sp.global_position + Vector3(0, 1.8, 0)
			cam.look_at(c0 + Vector3(0, 1.0, 0), Vector3.UP)
			await _wait(3.0)
			var vp := get_tree().root
			var frames := PackedFloat32Array()
			var draws := PackedFloat32Array()
			var prims := PackedFloat32Array()
			var t := 0.0
			while t < float(args.get("seconds", "10")):
				await get_tree().process_frame
				var d := get_process_delta_time()
				t += d
				frames.append(d * 1000.0)
				draws.append(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
				prims.append(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
			var r := {"scene": "dungeon_" + theme, "tier": tn, "frames": frames.size(), "fps_avg": 1000.0 / _mean(frames), "ms_avg": _mean(frames),
				"ms_p95": _pct(frames, 0.95), "ms_p99": _pct(frames, 0.99), "ms_max": _pct(frames, 1.0), "draws": _mean(draws), "prims_k": _mean(prims) / 1000.0}
			print("PHONEBENCH ", JSON.stringify(r))
			get_tree().root.get_texture().get_image().save_jpg("%s/dungeon_%s_%s.jpg" % [OUT_DIR, theme, tn], 0.85)
			interior.queue_free()
			await _wait(0.5)


static func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(b.size() * p))]
