extends Node
## Presentation audit 2 harness (docs/art/AAA_PRESENTATION_REVIEW.md "Audit 2"). Boots the real game and renders fixed scenes
## with weather forced clear and the clock pinned every frame. PC (Mobile renderer, never --headless):
##   Godot_console.exe --path kingdom --rendering-method mobile --resolution 2340x1080 res://tools_qa/aaa_audit/audit_views.tscn \
##       -- --adult --skipintro --quality=high --out=C:/.../before --tag=high [--only=gate,night] [--hud=0|1]
## Prints "AUDIT <scene> draws=N prims=P fps=F" per shot. Movie Maker: add --write-movie ... and --only=dialogue.
## PC Forward+ (RTX capture, never --headless; log must name the NVIDIA adapter):
##   Godot_console.exe --path kingdom --rendering-method forward_plus --resolution 2560x1440 res://tools_qa/aaa_audit/audit_views.tscn ##       -- --adult --skipintro --quality=high --out=C:/.../aaa_feel --pattern=pc1_{scene}_{tag} --tag=high_before ##       --only=gate,dusk,night --hud=0 --bench=20
## --pattern= uses {tag} and {scene} (default "{tag}_{scene}"). --bench=SECONDS holds each main shot N s with vsync off and
## uncapped fps, then prints "AUDITPERF <scene> tier= profile= renderer= fps_avg= ft_p50/p95/p99= vram_mb= tex_mb= draws= prims= gpu=".

const MAIN := "res://scenes/main.tscn"
const ALL := ["first_exterior", "road", "gate", "dialogue", "wolf", "dusk", "night"]

var main: Node
var player: Player
var out := "user://audit_views"
var tag := "shot"
var only: Array = []
var hud_on := true
var pattern := "{tag}_{scene}"
var bench := 0.0
var _pin := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--tag="):
			tag = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7).split(",", false)
		elif arg.begins_with("--pattern="):
			pattern = arg.substr(10)
		elif arg.begins_with("--bench="):
			bench = float(arg.substr(8))
		elif arg == "--hud=0":
			hud_on = false
	if bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(out)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _process(_d: float) -> void:
	if _pin >= 0.0:
		WorldSim.time_of_day = _pin


func _want(id: String) -> bool:
	return only.is_empty() or only.has(id)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String, hud_override := -1) -> void:
	var hide_hud := (not hud_on) if hud_override < 0 else (hud_override == 0)
	if hide_hud:
		main.hud.visible = false
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out.path_join(pattern.replace("{tag}", tag).replace("{scene}", name) + ".jpg")
	img.save_jpg(path, 0.92)
	var rv: Callable = main.viewport.get_render_info
	print("AUDIT %s draws=%d prims=%d fps=%d" % [name,
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		Engine.get_frames_per_second()])
	if bench > 0.0 and not name.ends_with("_nohud") and not name.ends_with("_lock"):
		await _bench(name)
	if hide_hud:
		main.hud.visible = true


func _bench(name: String) -> void:
	var deltas: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	var vram_peak := 0.0
	while (Time.get_ticks_usec() - t0) / 1e6 < bench + 2.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if (now - t0) / 1e6 >= 2.0:
			deltas.append(float(now - last) / 1000.0)
		last = now
		vram_peak = maxf(vram_peak, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	if deltas.is_empty():
		return
	var total := 0.0
	for d: float in deltas:
		total += d
	deltas.sort()
	var n := deltas.size()
	var rv: Callable = main.viewport.get_render_info
	var q: Node = get_node_or_null("/root/Quality")
	print("AUDITPERF %s tier=%s profile=%s renderer=%s fps_avg=%.1f ft_p50=%.2fms ft_p95=%.2fms ft_p99=%.2fms vram_mb=%.0f tex_mb=%.0f draws=%d prims=%d gpu=%s" % [name,
		str(q.call("tier_name")) if q != null and q.has_method("tier_name") else "n/a",
		str(q.get("profile")) if q != null and q.get("profile") != null else "n/a",
		RenderingServer.get_current_rendering_method(),
		1000.0 * n / total, deltas[int(n * 0.5)], deltas[mini(n - 1, int(n * 0.95))], deltas[mini(n - 1, int(n * 0.99))],
		vram_peak / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rv.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.get_video_adapter_name()])


static func yaw_for(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func _home() -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var dd := (s["pos"] as Vector2).distance_to(main.HOME_SPAWN)
		if dd < bd and s.has("plan"):
			bd = dd
			best = s
	return best


func _place(p: Vector2, look: Vector2) -> void:
	main._teleport(p, 0.0)
	var pitch := float(Player.VIEW_RIG[Player.View.THIRD][1])
	player.set_camera(yaw_for(look.normalized()), pitch)
	await frames(150)
	main.hud.close_menu()
	await frames(20)


func _bench_spot(plan: Dictionary) -> Array:
	var bst: Dictionary = plan["streets"][0]
	var bd := ((bst["b"] as Vector2) - (bst["a"] as Vector2)).normalized()
	return [(bst["a"] as Vector2) + bd * 22.0 - bd.orthogonal() * 1.5, bd.rotated(0.3)]


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	main.weather.auto = false
	main.weather.set_weather("clear", 0.1)
	player = main.player
	_pin = 15.0
	player.set_view(Player.View.THIRD)
	await frames(30)
	var s := _home()
	var plan: Dictionary = s["plan"]
	var spot := _bench_spot(plan)

	if _want("first_exterior"):
		_pin = 8.0
		var c: Vector2 = s["pos"]
		var sp: Vector2 = main.HOME_SPAWN
		await _place(sp, c - sp if c.distance_to(sp) > 3.0 else Vector2(1, -1))
		await shot("first_exterior")
	if _want("road"):
		_pin = 11.0
		var a: Vector2 = WorldGen.settlements[0]["pos"]
		var b: Vector2 = WorldGen.settlements[1]["pos"]
		await _place(a.lerp(b, 0.55), b - a)
		await shot("road")
	if _want("gate"):
		_pin = 15.0
		var cap: Dictionary = WorldGen.settlements[1]
		var ga: float = cap["plan"]["gates"][0]
		var dir := Vector2(cos(ga), sin(ga))
		var gs: Vector2 = (cap["pos"] as Vector2) + dir * (float(cap["radius"]) - 42.0)
		main._teleport(gs, 0)
		player.set_camera(atan2(-dir.x, -dir.y), -0.05)
		main.settlements.focus = player.global_position
		for _i in 4:
			main.settlements.update_now()
		main.settlements.finish_prop_jobs()
		await frames(120)
		await shot("gate", 1)
		await shot("gate_nohud", 0)
	if _want("dialogue"):
		_pin = 15.5
		await _place(spot[0], spot[1])
		var tt: Node = main.services.get("talk_target") if main.get("services") != null else null
		if tt != null and tt.call("qa_open"):
			var pp: Variant = player._talk_partner
			print("AUDIT talking partner=", WorldSim.person_name(int(pp.get("person"))) if pp and pp.get("person") != null else "none")
			await frames(90)
			await shot("dialogue")
			main.hud.close_menu()
			await frames(40)
		else:
			print("AUDIT dialogue: no talk target")
	if _want("wolf"):
		_pin = 15.0
		var ws: Dictionary = Frontier.runestones.stones[7] if Frontier.runestones.stones.size() > 7 else Frontier.runestones.stones[0]
		var den: Dictionary = Frontier.ecology.dens[0]
		var wd: Vector2 = (den["pos"] - ws["pos"]).normalized()
		var side := Vector2(-wd.y, wd.x)
		var wsp: Vector2 = den["pos"] - wd * 40.0 - side * 2.5
		main._teleport(wsp, 0.0)
		player.set_camera(atan2(-wd.x, -wd.y), -0.14)
		main.frontier.focus = Vector3(den["pos"].x, 0, den["pos"].y)
		main.frontier._timer = 0.0
		main.frontier._process(0.0)
		for w in get_tree().get_nodes_in_group("team1"):
			if w is Wolf:
				var q: Vector2 = wsp + wd * randf_range(12.0, 22.0) + side * randf_range(-7.0, 7.0)
				w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
				w.home = q
				w.state = Wolf.State.STALK
		player._invulnerable = 9999.0
		await frames(90)
		await shot("wolf")
		player.toggle_lock()
		await frames(45)
		await shot("wolf_lock")
	for pair in [["dusk", 18.6], ["night", 22.0]]:
		if _want(pair[0]):
			_pin = pair[1]
			await _place(spot[0], spot[1])
			await frames(60)
			await shot(pair[0])
	print("AUDIT DONE")
	get_tree().quit()
