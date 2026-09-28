extends SceneTree
## Visual performance recorder for Rising Ashes: SEE the lag, don't just count it.
## Boots the real game, moves the player along a route at running (or riding) speed
## so streaming and NPC spawning happen as in play, and saves:
##   - a frame every --every seconds, with a frame-time graph (last 3 s) drawn in the corner
##   - every hitch frame (frame time > --spike ms), with what was happening
##   - timeline.png: the whole run's frame times with hitch markers
##   - log.txt: per-sample fps/ms/cpu/draws/prims/nodes/chunks/npcs + hitch list
## Run (real GPU):
##   godot --path kingdom -s <abs>/tools/qa/perf_visual/perf_visual.gd -- --adult --skipintro \
##     --quality=high --route=village_forest --speed=7 --out=<abs dir> [--every=1.0] [--spike=33]

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
	change_scene_to_file("res://scenes/main.tscn")


func _al(n: String) -> Node:
	return root.get_node_or_null("/root/" + n)


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._loading.visible:
				_build_route()
				main._teleport(route[0], 0.0)
				_al("WorldSim").time_of_day = float(args.get("hour", "15.0"))
				phase = "settle"
				t = 0.0
		"settle":
			if t > float(args.get("settle", "8")):
				phase = "run"
				t = 0.0
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

	# Move along the route at a steady ground speed (streaming reacts as in real play).
	var a: Vector2 = route[seg]
	var b: Vector2 = route[seg + 1]
	var len := maxf(a.distance_to(b), 0.01)
	seg_t += delta * speed / len
	if seg_t >= 1.0:
		seg_t = 0.0
		seg += 1
		if seg >= route.size() - 1:
			_finish()
			return
		a = route[seg]
		b = route[seg + 1]
	var p := a.lerp(b, seg_t)
	var dir := (b - a).normalized()
	var pl: Node3D = main.player
	pl.global_position = Vector3(p.x, _wg().height(p.x, p.y) + 0.05, p.y)
	pl.rotation.y = atan2(-dir.x, -dir.y)
	main.player.set_camera(atan2(-dir.x, -dir.y), -0.14)
	main.terrain.focus = pl.global_position
	main.population.focus = pl.global_position

	var chunks: int = main.terrain.loaded_count()
	var full: int = main.population.full_count
	var note := ""
	if chunks != last_chunks:
		note += "chunks %d->%d " % [last_chunks, chunks]
	if full != last_full:
		note += "npc_full %d->%d " % [last_full, full]
	last_chunks = chunks
	last_full = full

	log_lines.append("%.2f ms=%.1f cpu=%.1f draws=%d prims=%d nodes=%d chunks=%d npc=%d/%d pos=(%.0f,%.0f) %s" % [
		run_t, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), chunks, full, main.population.sprite_count, p.x, p.y, note])

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
	var summary := "PERFVIS quality=%s route=%s speed=%.1f frames=%d avg=%.1fms fps=%.0f p95=%.1f p99=%.1f max=%.1f hitches>%dms=%d" % [
		_al("Quality").tier_name(), args.get("route", "village_forest"), speed, all_ms.size(), mean, 1000.0 / mean,
		sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1], int(spike_ms), hitches.size()]
	print(summary)
	var f := FileAccess.open(out_dir + "/log.txt", FileAccess.WRITE)
	f.store_line(summary)
	f.store_line("HITCHES (t, ms, what changed that frame):")
	for hh in hitches:
		f.store_line("  %.2fs  %.1f ms  %s" % [hh[0], hh[1], hh[2]])
	f.store_line("SAMPLES:")
	for l in log_lines:
		f.store_line(l)
	quit()


## Game classes are loaded at runtime (a SceneTree script can't see class_name globals).
func _wg() -> Script:
	return load("res://scripts/world/world_gen.gd")
