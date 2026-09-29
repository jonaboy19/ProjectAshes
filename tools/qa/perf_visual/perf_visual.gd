extends SceneTree
## Visual performance recorder for Rising Ashes: SEE the lag, don't just count it.
## Boots the real game and drives the player along a route through the REAL input
## path (touches on the on-screen VirtualJoystick + camera drags, exactly like
## tools_qa/autoplay/autoplay.gd), so movement, collisions and the walk/run/idle
## animation blend all run as they would for a real player -- not a teleport.
## Saves:
##   - a frame every --every seconds, with a frame-time graph (last 3 s) drawn in the corner
##   - every hitch frame (frame time > --spike ms), with what was happening
##   - timeline.png: the whole run's frame times with hitch markers
##   - log.txt: per-sample fps/ms/cpu/draws/prims/nodes/chunks/npcs/speed-vs-anim + hitch list
##   - anim_timing.txt: player speed vs. CharacterAnimator.shown_speed() mismatches
##     (idle while moving, walk/run cadence lagging the actual speed, foot-slide)
## Run (real GPU):
##   godot --path kingdom -s <abs>/tools/qa/perf_visual/perf_visual.gd -- --adult --skipintro \
##     --quality=high --route=village_forest --speed=7 --out=<abs dir> [--every=1.0] [--spike=33]
## Add --teleport for the old teleport-along-the-route mode (pure streaming/GPU
## benchmarks where you don't want the real controller in the loop at all; no
## walking/running animation will play in that mode since the body never moves
## under its own physics).

var main: Control
var args := {}
var phase := "boot"
var t := 0.0
var out_dir := ""
var route: PackedVector2Array = []
var seg := 0
var seg_t := 0.0
var speed := 7.0
var every := 1.0
var spike_ms := 33.0
var next_shot := 0.0
var shot_n := 0
var hist: PackedFloat32Array = []          # last ~3 s of frame times (ms)
var all_ms: PackedFloat32Array = []
var all_t: PackedFloat32Array = []
var hitches: Array = []                    # [t, ms, note]
var log_lines: PackedStringArray = []
var run_t := 0.0
var last_chunks := 0
var last_full := 0
var capture := true      # --nocapture: pure measurement pass (screenshots cost 20-30 ms each)
var skip_next := false   # the frame after a capture is polluted by the capture itself
var last_hitch_shot := -10.0

## --- real-input driving (mirrors tools_qa/autoplay/autoplay.gd's stick()/turn_to()) ---
const LOOK_SENS := 0.006          # Player.add_look: _yaw -= relative.x * 0.006
var teleport_mode := false
var _stick_down := false
var _stick_center := Vector2.ZERO
var _wp_elapsed := 0.0
var _wp_timeout := 22.0
var _wp_check_t := 1.0
var _wp_last := Vector2.ZERO
var _wp_stuck := 0
var _cadence_report: PackedStringArray = []   # mismatches for anim_timing.txt
var _cadence_n := 0
var _cadence_bad := 0
var _cadence_worst := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	out_dir = args.get("out", OS.get_user_data_dir() + "/perf_visual")
	DirAccess.make_dir_recursive_absolute(out_dir)
	speed = float(args.get("speed", "7"))
	every = float(args.get("every", "1.0"))
	spike_ms = float(args.get("spike", "33"))
	capture = not args.has("nocapture")
	teleport_mode = args.has("teleport")
	# Make it obvious on-screen that this window is a QA recorder driving itself,
	# not the user playing (it looks like nothing is holding the controls).
	DisplayServer.window_set_title("Rising Ashes QA recorder (test, not gameplay)")
	change_scene_to_file("res://scenes/main.tscn")


func _al(n: String) -> Node:
	return root.get_node_or_null("/root/" + n)


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._veil():
				_build_route()
				main._teleport(route[0], 0.0)
				_al("WorldSim").time_of_day = float(args.get("hour", "15.0"))
				phase = "settle"
				t = 0.0
		"settle":
			if t > float(args.get("settle", "8")):
				phase = "run"
				t = 0.0
				_ablate()
				if args.has("uncapped"):
					Engine.max_fps = 0
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"run":
			_step(delta)
	return false


## Waypoints (x, z) in world metres, built from the game's own settlement data.
func _build_route() -> void:
	var wg: Script = _wg()
	var sets: Array = wg.settlements
	var home: Vector2 = sets[0]["pos"]
	match String(args.get("route", "village_forest")):
		"village_forest":
			# plaza -> out along the road -> fields -> into the woods -> the first camp -> back
			var camp: Vector2 = main.FIRST_CAMP
			route = PackedVector2Array([home + Vector2(1, 7.5), home + Vector2(30, 20), home + Vector2(90, 40),
				home.lerp(camp, 0.5), camp + Vector2(-25, 8), home.lerp(camp, 0.25), home + Vector2(1, 7.5)])
		"to_capital":
			var cap: Vector2 = sets[1]["pos"]
			route = PackedVector2Array([home + Vector2(1, 7.5), home.lerp(cap, 0.33), home.lerp(cap, 0.66), cap + Vector2(0, 40), cap])
		"village_loop":
			route = PackedVector2Array([home + Vector2(1, 7.5), home + Vector2(25, 0), home + Vector2(0, -25),
				home + Vector2(-25, 0), home + Vector2(0, 25), home + Vector2(1, 7.5)])


func _step(delta: float) -> void:
	var ms := delta * 1000.0
	run_t += delta
	var polluted := skip_next     # this frame paid for the previous frame's screenshot
	skip_next = false
	if not polluted:
		all_ms.append(ms)
		all_t.append(run_t)
		hist.append(ms)
		if hist.size() > 240:
			hist.remove_at(0)

	var pl: Node3D = main.player
	var p: Vector2
	if teleport_mode:
		p = _drive_teleport(delta)
	else:
		p = _drive_real(delta)
		if phase == "done":   # _drive_real can finish the route early (timeout on last leg)
			return
	main.terrain.focus = pl.global_position
	main.population.focus = pl.global_position
	_sample_anim(pl)

	var chunks: int = main.terrain.loaded_count()
	var full: int = main.population.full_count
	var note := ""
	if chunks != last_chunks:
		note += "chunks %d->%d " % [last_chunks, chunks]
	if full != last_full:
		note += "npc_full %d->%d " % [last_full, full]
	last_chunks = chunks
	last_full = full

	var speed_now := Vector2(pl.velocity.x, pl.velocity.z).length() if pl.get("velocity") != null else 0.0
	var shown := 0.0
	var animr: Object = pl.get("_animator")
	if animr and animr.has_method("shown_speed"):
		shown = animr.shown_speed()
	log_lines.append("%.2f ms=%.1f cpu=%.1f draws=%d prims=%d nodes=%d chunks=%d npc=%d/%d pos=(%.0f,%.0f) spd=%.2f shown=%.2f %s" % [
		run_t, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), chunks, full, main.population.sprite_count, p.x, p.y, speed_now, shown, note])

	var is_spike := ms > spike_ms and run_t > 1.0 and not polluted
	if is_spike:
		hitches.append([run_t, ms, note])
	if not capture:
		return
	# Sparse captures: one per `every` seconds, plus at most one hitch frame per 1.5 s
	# (each capture stalls the game ~20-30 ms, so the next frame is excluded from stats).
	var hitch_shot := is_spike and run_t - last_hitch_shot > 1.5
	if run_t >= next_shot or hitch_shot:
		if run_t >= next_shot:
			next_shot = run_t + every
		if hitch_shot:
			last_hitch_shot = run_t
		_save_frame(("HITCH_%.0fms_" % ms) if is_spike else "", note)
		skip_next = true


## Old pure-streaming mode: no real physics/animation, just moves the body.
func _drive_teleport(delta: float) -> Vector2:
	var a: Vector2 = route[seg]
	var b: Vector2 = route[seg + 1]
	var len := maxf(a.distance_to(b), 0.01)
	seg_t += delta * speed / len
	if seg_t >= 1.0:
		seg_t = 0.0
		seg += 1
		if seg >= route.size() - 1:
			_finish()
			return a
		a = route[seg]
		b = route[seg + 1]
	var p := a.lerp(b, seg_t)
	var dir := (b - a).normalized()
	var pl: Node3D = main.player
	pl.global_position = Vector3(p.x, _wg().height(p.x, p.y) + 0.05, p.y)
	pl.rotation.y = atan2(-dir.x, -dir.y)
	main.player.set_camera(atan2(-dir.x, -dir.y), -0.14)
	return p


## Real-input mode: touches the on-screen joystick (same InputEventScreenTouch/Drag
## path as tools_qa/autoplay/autoplay.gd's stick()), so Player._physics_process,
## collisions and CharacterAnimator all run for real. The camera is aimed at the
## next waypoint each frame (Player.set_camera, the same public call cutscenes use)
## so the body turns and moves toward it under its own steering/turn-rate code.
## Cycles idle -> walk -> run every ~9 s so the animation-timing check (item 4 of
## the QA task) sees all three gaits, not just a run the whole time.
func _drive_real(delta: float) -> Vector2:
	var pl: Node3D = main.player
	var p2 := Vector2(pl.global_position.x, pl.global_position.z)
	_wp_elapsed += delta
	var target: Vector2 = route[seg + 1]
	var dist := p2.distance_to(target)
	if dist < 2.5 or _wp_elapsed > _wp_timeout:
		seg += 1
		_wp_elapsed = 0.0
		_wp_stuck = 0
		if seg >= route.size() - 1:
			_stick_release()
			_finish()
			phase = "done"
			return p2
		target = route[seg + 1]
		dist = p2.distance_to(target)
	var to := target - p2
	var yaw := atan2(-to.x, -to.y) if dist > 0.05 else pl.rotation.y
	main.player.set_camera(yaw, -0.14)

	# idle (0-1.2s) -> walk (1.2-3.0s) -> run (3.0-9.0s), repeating.
	var cyc := fmod(run_t, 9.0)
	var mag := 1.0 if cyc >= 3.0 else (0.0 if cyc < 1.2 else 0.45)

	_wp_check_t -= delta
	if _wp_check_t <= 0.0:
		_wp_check_t = 1.0
		if mag > 0.05 and p2.distance_to(_wp_last) < 0.4:
			_wp_stuck += 1
		else:
			_wp_stuck = 0
		_wp_last = p2

	if mag <= 0.01:
		_stick_release()
	elif _wp_stuck >= 2:
		var side := 1.0 if int(run_t) % 2 == 0 else -1.0
		_stick(Vector2(side * 0.9, -0.3))    # sidestep round whatever's blocking us
	else:
		_stick(Vector2(0, -mag))
	return p2


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	ev.screen_relative = rel
	Input.parse_input_event(ev)


## Holds the left-thumb joystick touch, same geometry as autoplay.gd's stick().
func _stick(v: Vector2) -> void:
	var s := root.get_visible_rect().size
	if not _stick_down:
		_stick_center = Vector2(160, s.y - 160)
		_touch(0, _stick_center, true)
		_stick_down = true
	var p := _stick_center + v.limit_length(1.0) * 90.0
	_drag(0, p, p - _stick_center)


func _stick_release() -> void:
	if _stick_down:
		_touch(0, _stick_center, false)
		_stick_down = false


## Player speed vs. CharacterAnimator.shown_speed(): flags idle-while-moving,
## walk/run cadence lagging the real speed, and foot-slide (shown speed far
## from actual). Feeds docs/qa/grounding/animation_timing.md via _finish().
func _sample_anim(pl: Node3D) -> void:
	var animr: Object = pl.get("_animator")
	if animr == null or not animr.has_method("shown_speed"):
		return
	var actual := Vector2(pl.velocity.x, pl.velocity.z).length() if pl.get("velocity") != null else 0.0
	var shown: float = animr.shown_speed()
	_cadence_n += 1
	var diff := absf(actual - shown)
	var bad := ""
	if actual > 0.3 and shown < 0.15:
		bad = "idle-while-moving (actual %.2f m/s, anim shows %.2f)" % [actual, shown]
	elif diff > 1.2 and run_t > 2.0:
		bad = "cadence lag / foot-slide (actual %.2f m/s, anim shows %.2f, diff %.2f)" % [actual, shown, diff]
	if bad != "":
		_cadence_bad += 1
		_cadence_worst = maxf(_cadence_worst, diff)
		if _cadence_report.size() < 60:      # keep the file readable
			_cadence_report.append("  %.2fs pos=(%.0f,%.0f) %s" % [run_t, pl.global_position.x, pl.global_position.z, bad])


func _save_frame(tag: String, note: String) -> void:
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	_draw_graph(img, Rect2i(8, 8, 360, 110))
	shot_n += 1
	img.save_jpg("%s/%04d_%s%.1fs.jpg" % [out_dir, shot_n, tag, run_t], 0.82)


## Frame-time graph: green < 16.7 ms, yellow < 33 ms, red above; lines at 16.7 and 33 ms.
func _draw_graph(img: Image, r: Rect2i) -> void:
	img.fill_rect(r, Color(0, 0, 0, 0.55))
	var max_ms := 50.0
	for ref in [16.7, 33.3]:
		var y := r.end.y - 1 - int(ref / max_ms * (r.size.y - 2))
		for x in range(r.position.x, r.end.x):
			img.set_pixel(x, y, Color(1, 1, 1, 0.5))
	var n := hist.size()
	for i in n:
		var x := r.end.x - n + i
		if x < r.position.x:
			continue
		var v := hist[i]
		var h := int(clampf(v / max_ms, 0.0, 1.0) * (r.size.y - 2))
		var c := Color(0.3, 0.9, 0.3) if v < 16.7 else (Color(1.0, 0.85, 0.2) if v < 33.3 else Color(1.0, 0.25, 0.2))
		for y in range(r.end.y - 1 - h, r.end.y - 1):
			img.set_pixel(x, y, c)


func _finish() -> void:
	phase = "done"
	# Timeline of the whole run.
	var w := 1600
	var h := 300
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.08, 0.08, 0.1))
	var tmax := all_t[all_t.size() - 1] if all_t.size() > 0 else 1.0
	var max_ms := 60.0
	for ref in [16.7, 33.3]:
		var y := h - 1 - int(ref / max_ms * (h - 1))
		for x in w:
			img.set_pixel(x, y, Color(0.5, 0.5, 0.5))
	for i in all_ms.size():
		var x := int(all_t[i] / tmax * (w - 1))
		var v := all_ms[i]
		var hh := int(clampf(v / max_ms, 0.0, 1.0) * (h - 1))
		var c := Color(0.3, 0.9, 0.3) if v < 16.7 else (Color(1.0, 0.85, 0.2) if v < 33.3 else Color(1.0, 0.25, 0.2))
		for y in range(h - 1 - hh, h):
			img.set_pixel(x, y, c)
	img.save_png(out_dir + "/timeline.png")

	var sorted := all_ms.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in all_ms:
		mean += v
	mean /= maxi(all_ms.size(), 1)
	var summary := "PERFVIS quality=%s route=%s speed=%.1f mode=%s frames=%d avg=%.1fms fps=%.0f p95=%.1f p99=%.1f max=%.1f hitches>%dms=%d anim_bad=%d/%d" % [
		_al("Quality").tier_name(), args.get("route", "village_forest"), speed,
		"teleport" if teleport_mode else "real-input", all_ms.size(), mean, 1000.0 / mean,
		sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1],
		int(spike_ms), hitches.size(), _cadence_bad, _cadence_n]
	print(summary)
	var f := FileAccess.open(out_dir + "/log.txt", FileAccess.WRITE)
	f.store_line(summary)
	f.store_line("HITCHES (t, ms, what changed that frame):")
	for hh in hitches:
		f.store_line("  %.2fs  %.1f ms  %s" % [hh[0], hh[1], hh[2]])
	f.store_line("SAMPLES:")
	for l in log_lines:
		f.store_line(l)
	f.close()
	if not teleport_mode:
		var af := FileAccess.open(out_dir + "/anim_timing.txt", FileAccess.WRITE)
		af.store_line("player animation-timing samples: %d, mismatches: %d, worst diff: %.2f m/s" % [_cadence_n, _cadence_bad, _cadence_worst])
		for l in _cadence_report:
			af.store_line(l)
		af.close()
	await _shutdown()


## Clean exit: free the loaded game scene and give freed nodes (TerrainStreamer's
## WorkerThreadPool tasks, ResourceLoader threaded requests, RenderingServer RIDs)
## several frames to unwind before quit(). Calling quit() while res://scenes/main.tscn
## is still live left thousands of RIDs (meshes/materials/textures/shaders) and worker
## threads mid-flight; the resulting race during engine teardown was the root cause of
## the ntdll heap-corruption crashes (exit code 0xc0000005) seen in the Windows event
## log for every QA harness that skipped this step. See docs/qa/stability.md.
func _shutdown() -> void:
	if main:
		main.queue_free()
		main = null
	for i in 10:
		await process_frame
	quit()


## Game classes are loaded at runtime (a SceneTree script can't see class_name globals).
func _wg() -> Script:
	return load("res://scripts/world/world_gen.gd")


## --ablate=soldier.gd,procedural_rig.gd,...: switch off processing on every node
## whose script file name is listed (re-checked every 2 s so newly spawned ones are
## caught too), to find what a hitch pattern costs by comparing runs.
var _ablate_list: PackedStringArray = []


func _ablate() -> void:
	if not args.has("ablate"):
		return
	_ablate_list = String(args["ablate"]).split(",", false)
	print("PERFVIS ablating: ", _ablate_list)
	_ablate_pass()


func _ablate_pass() -> void:
	var n := 0
	for node in root.find_children("*", "", true, false):
		var s: Script = node.get_script()
		if s and s.resource_path.get_file() in _ablate_list:
			if node.process_mode != Node.PROCESS_MODE_DISABLED:
				node.process_mode = Node.PROCESS_MODE_DISABLED
				n += 1
	if n > 0:
		print("PERFVIS ablated %d nodes" % n)
	if phase == "run":
		root.get_tree().create_timer(2.0).timeout.connect(_ablate_pass)
