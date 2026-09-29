extends Node
## Autoplay playtest bot for Rising Ashes.
##
## Instances the real game (res://scenes/main.tscn) as a child and plays it like a
## phone player, through the real input path:
##   - movement: touches on the on-screen VirtualJoystick (InputEventScreenTouch/Drag)
##   - camera:   touch drags on the HUD look area (InputEventScreenDrag -> Player.add_look)
##   - actions:  keyboard events (InputEventKey, physical keycodes from Game._setup_input),
##               plus taps on the HUD TouchScreenButtons (Attack, Talk)
##   - menus:    mouse clicks on the HUD menu Buttons (InputEventMouseButton)
## Test shortcuts that a player can't do are marked [HOOK] in the log (fast travel to
## far-away fights, ageing the child to 18, setting the clock to night).
##
## Run: tools_qa/autoplay/run_autoplay.sh   (see README.md)
## Output: <outdir>/NN_<step>.jpg, <outdir>/log.txt, <outdir>/summary.json

const MAIN := "res://scenes/main.tscn"
const SHOT_W := 1280
const SHOT_H := 720
const LOOK_SENS := 0.006      # Player.add_look: _yaw -= relative.x * 0.006

var main: Node
var player: Player
var hud: HUD
var out_dir := ""
var t0 := 0
var shot_n := 0
var findings: Array = []          # {sev, step, text, shot}
var steps: Array = []             # step summaries
var _log: FileAccess
var _logger: RefCounted
var _step := "boot"
var _step_t := 0.0
var _samples: Array = []
var _sample_timer := 0.0
var _max_dt := 0.0
var _hitches := 0
var _last_ticks := 0
var _stick_down := false
var _stick_center := Vector2.ZERO
var _look_down := false
var _look_pos := Vector2.ZERO
var _uncapped := false
var _errors_seen := 0
var _error_counts := {}      # message -> count (engine errors are logged 3 times, then counted)


class ErrorTap extends Logger:
	var bot: Object
	var mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kinds := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
		var kind: String = kinds[error_type] if error_type >= 0 and error_type < kinds.size() else "ERROR"
		var msg := rationale if rationale != "" else code
		mutex.lock()
		lines.append("%s: %s  (%s:%d %s)" % [kind, msg, file, line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		mutex.lock()
		var out := lines.duplicate()
		lines.clear()
		mutex.unlock()
		return out


# --- setup -------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	_last_ticks = t0
	var args := _args()
	out_dir = String(args.get("outdir", ProjectSettings.globalize_path("res://").path_join("../docs/qa/playtest"))).simplify_path()
	_uncapped = args.has("uncapped")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in DirAccess.get_files_at(out_dir):
		if f.ends_with(".jpg") or f.ends_with(".png"):
			DirAccess.remove_absolute(out_dir.path_join(f))
	_log = FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	_logger = ErrorTap.new()
	OS.add_logger(_logger)
	get_window().size = Vector2i(SHOT_W, SHOT_H)
	get_window().move_to_center()
	log_line("Rising Ashes autoplay playtest  %s" % Time.get_datetime_string_from_system())
	log_line("GPU: %s | %s | renderer %s | Godot %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method(),
		Engine.get_version_info()["string"]])
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


func now() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0


func log_line(text: String) -> void:
	var line := "[%7.2f] %s" % [now(), text]
	print("AUTOPLAY ", line)
	if _log:
		_log.store_line(line)
		_log.flush()


func finding(sev: String, text: String) -> void:
	findings.append({"sev": sev, "step": _step, "text": text, "shot": shot_n})
	log_line("FINDING [%s] %s" % [sev, text])


# --- metrics -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	var ticks := Time.get_ticks_msec()
	var dt := (ticks - _last_ticks) / 1000.0
	_last_ticks = ticks
	if now() > 1.0:
		_max_dt = maxf(_max_dt, dt)
		if dt > 0.05:
			_hitches += 1
	for e: String in _logger.take():
		_engine_error(e)
	_sample_timer -= dt
	if _sample_timer <= 0.0:
		_sample_timer = 0.5
		_sample()


func _engine_error(e: String) -> void:
	_errors_seen += 1
	var k := e.substr(0, 160)
	_error_counts[k] = int(_error_counts.get(k, 0)) + 1
	if _error_counts[k] <= 3:
		log_line("ENGINE " + e)


func _sample() -> void:
	var s := {
		"fps": Engine.get_frames_per_second(),
		"cpu_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"gpu_ms": 0.0, "rcpu_ms": 0.0,
	}
	if main and main.get("viewport") and is_instance_valid(main.viewport):
		var rid: RID = main.viewport.get_viewport_rid()
		s["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		s["rcpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_samples.append(s)
	if _log:
		_log.store_line("[%7.2f]   perf %-14s fps %3d | frame %5.1f ms | cpu %5.2f ms | 3D gpu %5.2f ms | draws %5d | prims %8d | objs %5d | nodes %6d | vram %4d MB" % [
			now(), _step, s["fps"], 1000.0 / maxf(s["fps"], 1.0), s["cpu_ms"], s["gpu_ms"], s["draws"], s["prims"], s["objs"], s["nodes"], s["vram_mb"]])


func step(name: String) -> void:
	_end_step()
	_step = name
	_step_t = now()
	_samples.clear()
	_max_dt = 0.0
	_hitches = 0
	log_line("=== STEP %s ===" % name)


func _end_step() -> void:
	if _samples.is_empty():
		return
	var agg := {"step": _step, "start": _step_t, "secs": now() - _step_t, "samples": _samples.size()}
	for k in ["fps", "gpu_ms", "cpu_ms", "draws", "prims", "nodes", "objs", "vram_mb"]:
		var total := 0.0
		var lo := INF
		var hi := -INF
		for s: Dictionary in _samples:
			total += float(s[k])
			lo = minf(lo, float(s[k]))
			hi = maxf(hi, float(s[k]))
		agg[k + "_avg"] = total / _samples.size()
		agg[k + "_min"] = lo
		agg[k + "_max"] = hi
	agg["worst_frame_ms"] = _max_dt * 1000.0
	agg["hitches_50ms"] = _hitches
	steps.append(agg)
	log_line("SUMMARY %s: fps avg %.0f (min %.0f) | 3D gpu %.2f ms avg (max %.2f) | draws avg %.0f max %.0f | prims avg %.0f max %.0f | nodes %.0f | worst frame %.0f ms | hitches>50ms %d" % [
		_step, agg["fps_avg"], agg["fps_min"], agg["gpu_ms_avg"], agg["gpu_ms_max"], agg["draws_avg"], agg["draws_max"],
		agg["prims_avg"], agg["prims_max"], agg["nodes_avg"], agg["worst_frame_ms"], _hitches])


func shot(name: String) -> String:
	await frames(2)
	shot_n += 1
	var file := "%02d_%s.jpg" % [shot_n, name]
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1600:
		img.resize(1600, int(img.get_height() * 1600.0 / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(out_dir.path_join(file), 0.86)
	log_line("SHOT %s  (pos %s, yaw %.2f, hour %.1f, hp %d)" % [file, _v(player.global_position) if player else "-",
		float(player.get("_yaw")) if player else 0.0, WorldSim.time_of_day, int(player.get("health")) if player else 0])
	return file


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


# --- waiting -----------------------------------------------------------------------

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Real-time wait (ignores Engine.time_scale hit-stops).
func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


# --- input: keyboard ---------------------------------------------------------------

func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func tap_key(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(1)


# --- input: touch ------------------------------------------------------------------

func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	ev.screen_relative = rel
	Input.parse_input_event(ev)


func tap(pos: Vector2, index := 2) -> void:
	touch(index, pos, true)
	await frames(3)
	touch(index, pos, false)
	await frames(1)


## Hold the left thumb on the virtual joystick. v: x right, y down (-1 = forward).
func stick(v: Vector2) -> void:
	var s := _screen()
	if not _stick_down:
		# VirtualJoystick covers x < 0.4w, y > 0.3h; put the thumb well inside it.
		_stick_center = Vector2(160, s.y - 160)
		touch(0, _stick_center, true)
		_stick_down = true
	var p := _stick_center + v.limit_length(1.0) * 90.0
	drag(0, p, p - _stick_center)


func stick_release() -> void:
	if _stick_down:
		touch(0, _stick_center, false)
		_stick_down = false


## Swipe on the right side of the screen to turn the camera.
func look_drag(rel: Vector2) -> void:
	if not _look_down:
		var s := _screen()
		_look_pos = Vector2(s.x * 0.6, s.y * 0.35)
		touch(1, _look_pos, true)
		_look_down = true
	drag(1, _look_pos, rel)


func look_release() -> void:
	if _look_down:
		touch(1, _look_pos, false)
		_look_down = false


func yaw() -> float:
	return float(player.get("_yaw"))


## Turns the camera toward a yaw by swiping, a bit per frame like a thumb would.
func turn_to(target_yaw: float, max_px := 45.0) -> bool:
	var d := wrapf(target_yaw - yaw(), -PI, PI)
	if absf(d) < 0.03:
		return true
	var rel := clampf(-d / LOOK_SENS, -max_px, max_px)
	look_drag(Vector2(rel, 0))
	return false


func face(target: Vector3, timeout := 1.5) -> void:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		var to := target - player.global_position
		if turn_to(atan2(-to.x, -to.z)):
			break
		await get_tree().process_frame
	look_release()
	await frames(2)


func pitch_by(px: float) -> void:
	for i in 6:
		look_drag(Vector2(0, px / 6.0))
		await get_tree().process_frame
	look_release()


## Real 360 look: swipe the camera round in 4 quarter turns with a screenshot each.
func look_around(label: String) -> void:
	var start := yaw()
	for q in 4:
		var target := start - (q + 1) * PI * 0.5
		var end := Time.get_ticks_msec() + 2500
		while Time.get_ticks_msec() < end and not turn_to(target, 30.0):
			await get_tree().process_frame
		look_release()
		await wait(0.5)
		await shot("%s_look_%d" % [label, (q + 1) * 90])


# --- walking -----------------------------------------------------------------------

## Walks to a ground point with the joystick, steering the camera by swiping.
## Returns {ok, secs, left, stuck}.
func walk_to(target: Vector2, tol := 1.5, timeout := 30.0, run := true) -> Dictionary:
	var start := now()
	var stuck := 0
	var check_at := now() + 1.0
	var last := _p2()
	var side := 1.0
	var sidestep_until := 0.0
	var res := {"ok": false, "secs": 0.0, "left": 0.0, "stuck": 0}
	while now() - start < timeout:
		var to := target - _p2()
		var dist := to.length()
		if dist < tol:
			res["ok"] = true
			break
		turn_to(atan2(-to.x, -to.y))
		var mag := 1.0 if run and dist > 4.0 else clampf(dist / 4.0, 0.45, 0.85)
		if now() < sidestep_until:
			stick(Vector2(side * 0.95, -0.25))
		else:
			stick(Vector2(0, -mag))
		if now() > check_at:
			check_at = now() + 1.0
			if _p2().distance_to(last) < 0.5 and now() > sidestep_until:
				stuck += 1
				side = -side
				sidestep_until = now() + 0.7
				if stuck == 3:
					log_line("  walk_to %s: stuck near %s (blocked by geometry?)" % [target, _p2()])
				if stuck >= 8:
					break
			last = _p2()
		await get_tree().process_frame
	stick_release()
	look_release()
	res["secs"] = now() - start
	res["left"] = (target - _p2()).length()
	res["stuck"] = stuck
	log_line("  walk_to (%.1f, %.1f): %s in %.1fs, %.1f m left, stuck %d" % [target.x, target.y,
		"arrived" if res["ok"] else "FAILED", res["secs"], res["left"], stuck])
	await frames(3)
	return res


func _p2() -> Vector2:
	var p: Vector3 = player.global_position
	return Vector2(p.x, p.z)


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


# --- HUD menus ---------------------------------------------------------------------

func menu_open() -> bool:
	return hud.is_menu_open()


func menu_title() -> String:
	var m: Control = hud.get("_menu")
	for l in m.find_children("*", "Label", true, false):
		return (l as Label).text
	return ""


func menu_buttons() -> Array:
	var m: Control = hud.get("_menu")
	return m.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.is_visible_in_tree() and not b.is_queued_for_deletion())


## Clicks the first menu button whose text contains `needle` (a real mouse click).
func click_menu(needle: String) -> String:
	for b: Button in menu_buttons():
		if needle.to_lower() in b.text.to_lower():
			if b.disabled:
				log_line("  menu button '%s' is disabled" % b.text)
				return "disabled"
			var hit := [false]
			var text := b.text
			var at := b.get_global_rect().get_center()
			b.pressed.connect(func() -> void: hit[0] = true, CONNECT_ONE_SHOT)
			await click(at)
			await wait(0.3)   # the menu rebuilds after an action
			log_line("  clicked '%s' at %s: %s" % [text, at, "pressed" if hit[0] else "CLICK DID NOT PRESS THE BUTTON"])
			if not hit[0]:
				finding("minor", "Mouse click on menu button '%s' did not register" % text)
			return text
	log_line("  no menu button matching '%s' (have: %s)" % [needle, ", ".join(menu_buttons().map(func(x: Button) -> String: return x.text))])
	return ""


func click(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await frames(1)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(2)


## Presses the HUD "Talk" TouchScreenButton (what a phone player taps).
func tap_talk() -> void:
	var s := _screen()
	await tap(s - Vector2(102, 252), 3)


func tap_attack() -> void:
	var s := _screen()
	await tap(s - Vector2(104, 104), 2)


## UI check: the open menu panel must fit on screen.
func check_menu_on_screen(label: String) -> void:
	var m: Control = hud.get("_menu")
	var r := m.get_global_rect()
	var screen := Rect2(Vector2.ZERO, _screen())
	var box: Control = m.get_child(m.get_child_count() - 1) if m.get_child_count() > 0 else null
	log_line("  menu rect %s (min %s, %d children, box min %s)" % [r, m.get_combined_minimum_size(), m.get_child_count(),
		box.get_combined_minimum_size() if box else Vector2.ZERO])
	if not screen.grow(2.0).encloses(r):
		finding("major", "The %s menu panel is off screen: rect %s on a %s screen (its buttons can't be seen or tapped)" % [label, r, screen.size])


func interact_with(node: Node3D, label: String, use_touch := false) -> bool:
	var near: Node3D = player.nearest_interactable()
	if near != node:
		log_line("  nearest interactable is %s, not %s" % [_name(near), _name(node)])
	if use_touch:
		await tap_talk()
	else:
		await tap_key(KEY_E)
	var ok := await wait_until(func() -> bool: return menu_open(), 1.5)
	if ok:
		await wait(0.4)   # let the menu lay out before looking at or clicking it
	log_line("  interact %s -> menu %s '%s'" % [label, "OPEN" if ok else "none", menu_title() if ok else ""])
	if ok:
		check_menu_on_screen(label)
	return ok


func close_menu() -> void:
	if menu_open():
		await tap_key(KEY_E)
		await frames(3)
		if menu_open():
			hud.close_menu()


func _name(n: Node) -> String:
	if n == null:
		return "nothing"
	if n.get("title") != null:
		return "%s '%s'" % [n.get_class(), n.get("title")]
	return "%s %s" % [n.get_class(), n.name]


# --- world lookup ------------------------------------------------------------------

func lots(asset_prefix: String) -> Array:
	var out: Array = []
	for lot: Dictionary in WorldGen.settlements[0]["plan"]["lots"]:
		if String(lot["asset"]).begins_with(asset_prefix):
			out.append(lot)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).length() < (b["pos"] as Vector2).length())
	return out


func lot_front(lot: Dictionary, dist: float) -> Vector2:
	var yaw: float = lot["yaw"]
	return lot["pos"] + Vector2(sin(yaw), cos(yaw)) * dist


func station(title_part: String) -> Node3D:
	for st in get_tree().get_nodes_in_group("station"):
		if title_part in String(st.get("title")):
			return st
	return null


## Walks up to a building front, faces it and takes a screenshot.
func visit_building(asset: String, label: String, front: float) -> void:
	var l := lots(asset)
	if l.is_empty():
		finding("minor", "No '%s' lot in Ashford's plan" % asset)
		return
	var lot: Dictionary = l[0]
	var spot := lot_front(lot, front)
	var r := await walk_to(spot, 1.6, 35.0)
	if not r["ok"]:
		finding("major", "Could not walk to the %s (stuck %d times, %.1f m short)" % [label, r["stuck"], r["left"]])
	await face(ground(lot["pos"]) + Vector3(0, 3, 0))
	await wait(0.4)
	await shot(label)


func enemies_near(radius: float) -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("team1"):
		if e is Node3D and not e.get("dead") and (e as Node3D).global_position.distance_to(player.global_position) < radius:
			out.append(e)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	return out


func danger() -> String:
	var t: Dictionary = Frontier.threat_at(_p2())
	var parts := PackedStringArray()
	for k in t:
		var v: Variant = t[k]
		if v is float:
			parts.append("%s=%.1f" % [k, v])
		elif v is int or v is String:
			parts.append("%s=%s" % [k, v])
	return ", ".join(parts)


# --- the scenario --------------------------------------------------------------------

func _run() -> void:
	# --steps=village,interact,... runs a subset (boot always runs).
	var only := String(_args().get("steps", "village,interact,interior,combat,night,save"))
	await _step_boot()
	if "village" in only:
		await _step_village()
	else:
		Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
		player.apply_age()
	if "interact" in only:
		await _step_interact()
	if "interior" in only:
		await _step_interior()
	if "combat" in only:
		await _step_combat()
	if "night" in only:
		await _step_night()
	if "save" in only:
		await _step_save_load()
	_finish()


func _step_boot() -> void:
	step("01_boot")
	var ok := await wait_until(func() -> bool: return main.get("player") != null and main.player.is_inside_tree(), 180.0)
	player = main.player
	hud = main.hud
	if not ok:
		finding("critical", "Player never entered the tree within 180 s")
	var load_done := await wait_until(func() -> bool:
		var ld: Variant = hud.get("_loading")
		return not is_instance_valid(ld) or not ld.visible, 180.0)
	log_line("Loading screen gone at %.2fs (%s)" % [now(), "ok" if load_done else "TIMEOUT"])
	RenderingServer.viewport_set_measure_render_time(main.viewport.get_viewport_rid(), true)
	if _uncapped:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cut: CutscenePlayer = null
	var cut_end := Time.get_ticks_msec() + 5000
	while cut == null and Time.get_ticks_msec() < cut_end:
		for c in main.world.get_children():
			if c is CutscenePlayer:
				cut = c
		await get_tree().process_frame
	if cut:
		var cut_len := CutscenePlayer.total_duration(cut.shots)
		log_line("Birth cutscene playing (%d shots, %.1f s long)" % [cut.shots.size(), cut_len])
		await wait(3.5)
		await shot("birth_cutscene")
		await wait(2.0)
		await shot("birth_cutscene_2")
		# A phone player taps twice to skip ("Tap again to skip").
		var s := _screen()
		await tap(s * 0.5, 4)
		await wait(0.4)
		var hint: Label = cut.get("_hint")
		log_line("  after first tap: skip hint alpha %.2f" % (hint.modulate.a if hint else -1.0))
		await tap(s * 0.5, 4)
		var skipped := await wait_until(func() -> bool: return not is_instance_valid(cut) or not cut.playing, 3.0)
		log_line("  double tap skip: %s" % ("skipped" if skipped else "DID NOT SKIP"))
		if not skipped:
			finding("major", "Double tap did not skip the birth cutscene; pressing Esc")
			await tap_key(KEY_ESCAPE)
	else:
		finding("minor", "No birth cutscene found at boot")
	await wait_until(func() -> bool: return hud.visible, 5.0)
	await frames(2)
	log_line("FIRST PLAYABLE FRAME at %.2fs after launch (player at %s, age %d)" % [now(), _v(player.global_position),
		int(Life.life_path.age_years(WorldSim.day, WorldSim.time_of_day)) if Life.life_path.has_method("age_years") else -1])
	steps.append({"step": "first_playable", "t": now()})
	await wait(1.5)
	await shot("first_playable_child")
	# Walk a few steps as the child to check the young body animates.
	var home_door: Vector2 = _p2() + Vector2(0, 6)
	await walk_to(home_door, 1.2, 6.0, false)
	await shot("child_walks")


func _step_village() -> void:
	step("02_village")
	# [HOOK] The rest of the scenario is played as an adult (as main.gd's --adult does).
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	WorldSim.time_of_day = 10.0
	log_line("[HOOK] aged the player to 18, clock 10:00")
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	var assets := {}
	for lot: Dictionary in WorldGen.settlements[0]["plan"]["lots"]:
		assets[lot["asset"]] = assets.get(lot["asset"], 0) + 1
	log_line("Ashford lots: %s" % assets)
	log_line("Danger in village: %s" % danger())
	var r := await walk_to(c + Vector2(0, 4), 2.0, 40.0)
	if not r["ok"]:
		finding("major", "Could not reach the plaza from the home door")
	await look_around("plaza")
	await visit_building("adventurer_guild", "guild_hall", 11.0)
	await visit_building("inn", "inn", 9.0)
	await visit_building("blacksmith", "blacksmith", 8.0)
	await visit_building("healer", "healer", 7.0)
	var houses := lots("house")
	log_line("%d house lots" % houses.size())
	for i in mini(2, houses.size()):
		var lot: Dictionary = houses[i]
		await walk_to(lot_front(lot, 8.0), 1.6, 30.0)
		await face(ground(lot["pos"]) + Vector3(0, 2.5, 0))
		await shot("house_%s" % lot["asset"])
	var stalls := lots("stall")
	if stalls.is_empty():
		stalls = lots("market")
	if not stalls.is_empty():
		await walk_to(lot_front(stalls[0], 4.0), 1.6, 30.0)
		await face(ground(stalls[0]["pos"]) + Vector3(0, 1.2, 0))
		await shot("market_stall")
	# NPCs: innkeeper, captain of the guard, a guard/villager in the street.
	var inn := station(" Inn")
	if inn:
		var ip := Vector2(inn.global_position.x, inn.global_position.z)
		await walk_to(ip + (_p2() - ip).normalized() * 2.0, 1.0, 30.0)
		await face(inn.global_position + Vector3(0, 1.5, 0))
		await shot("npc_innkeeper")
	var cap: Node3D = main.captain
	await walk_to(Vector2(cap.global_position.x, cap.global_position.z) + (_p2() - Vector2(cap.global_position.x, cap.global_position.z)).normalized() * 2.2, 1.0, 30.0)
	await face(cap.global_position + Vector3(0, 1.5, 0))
	await shot("npc_captain_guard")
	var vills := get_tree().get_nodes_in_group("villager")
	log_line("%d villager nodes (full 3D) in the tree" % vills.size())
	var guard: Node3D = null
	var any_v: Node3D = null
	for v in vills:
		if not (v is Node3D) or (v as Node3D).global_position.distance_to(player.global_position) > 60.0:
			continue
		if any_v == null:
			any_v = v
		if "guard" in str(v.get("look")) or "Knight" in str(v.get("look")):
			guard = v
			break
	var who: Node3D = guard if guard else any_v
	if who:
		var wp := Vector2(who.global_position.x, who.global_position.z)
		await walk_to(wp + (_p2() - wp).normalized() * 2.0, 1.4, 20.0)
		await face(who.global_position + Vector3(0, 1.4, 0))
		await shot("npc_villager" if guard == null else "npc_guard")
	else:
		finding("minor", "No full-3D villager within 60 m of the plaza")


func _step_interact() -> void:
	step("03_interact")
	var board := station("Notice Board")
	if board:
		var bp := Vector2(board.global_position.x, board.global_position.z)
		await walk_to(bp + (_p2() - bp).normalized() * 1.6, 0.8, 25.0)
		await face(board.global_position + Vector3(0, 1.2, 0))
		if await interact_with(board, "notice board"):
			await wait(0.4)
			await shot("notice_board_menu")
			await close_menu()
		else:
			finding("major", "Notice board menu did not open with E")
	var guild := station("Adventurer Guild")
	if guild:
		var gp := Vector2(guild.global_position.x, guild.global_position.z)
		await walk_to(gp + (_p2() - gp).normalized() * 1.6, 0.8, 30.0)
		await face(guild.global_position + Vector3(0, 1.4, 0))
		if await interact_with(guild, "guild receptionist", true):
			await wait(0.4)
			await shot("guild_menu")
			var joined := await click_menu("Register")
			if joined != "":
				await wait(0.5)
				await shot("guild_menu_after_join")
			await close_menu()
		else:
			finding("major", "Guild menu did not open with the Talk button")
	var trader := station("Market Trader")
	if trader:
		var tp := Vector2(trader.global_position.x, trader.global_position.z)
		await walk_to(tp + (_p2() - tp).normalized() * 1.6, 0.8, 30.0)
		await face(trader.global_position + Vector3(0, 1.4, 0))
		Life.give("wolf_pelt", 2)
		log_line("[HOOK] gave 2 wolf pelts to test selling")
		var gold0: int = Game.gold
		if await interact_with(trader, "market trader"):
			await wait(0.3)
			await shot("trader_menu")
			await click_menu("Buy Loaf")
			var gold1: int = Game.gold
			await click_menu("Sell")
			var gold2: int = Game.gold
			log_line("  trade: gold %d -> after buy %d -> after sell %d; bread %d, pelts %d" % [gold0, gold1, gold2,
				Life.count("bread"), Life.count("wolf_pelt")])
			if gold1 >= gold0:
				finding("major", "Buying bread did not cost gold (%d -> %d)" % [gold0, gold1])
			if gold2 <= gold1:
				finding("major", "Selling a pelt did not pay (%d -> %d)" % [gold1, gold2])
			await wait(0.3)
			await shot("trader_after_trade")
			await close_menu()
		else:
			finding("major", "Trader menu did not open")
	var cap: Node3D = main.captain
	var cp := Vector2(cap.global_position.x, cap.global_position.z)
	await walk_to(cp + (_p2() - cp).normalized() * 1.8, 0.8, 30.0)
	await face(cap.global_position + Vector3(0, 1.5, 0))
	if await interact_with(cap, "captain"):
		await wait(0.3)
		await shot("talk_captain")
		await close_menu()
	else:
		finding("major", "Talking to the Captain did not open a menu")


func _step_interior() -> void:
	step("04_interior")
	var doors: Array = []
	for n in main.world.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and not (n as InteriorDoor).is_exit:
			doors.append(n)
	log_line("InteriorDoor entrances in the world: %d" % doors.size())
	var door: InteriorDoor = null
	var inn_lot: Array = lots("inn")
	if doors.is_empty():
		finding("major", "Interior doors are not wired into the world (0 InteriorDoor nodes); buildings can't be entered. The bot adds a test door at the inn to check the room itself.")
		if inn_lot.is_empty():
			return
		# [HOOK] Test-only door, built exactly as scenes/interiors/README.md describes.
		var lot: Dictionary = inn_lot[0]
		var holder := Node3D.new()
		holder.name = "AutoplayTestDoor"
		main.world.add_child(holder)
		door = InteriorDoor.new()
		door.interior_scene = "res://scenes/interiors/inn_interior.tscn"
		door.prompt_text = "Enter the inn"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 2.2, 2.0)
		shape.shape = box
		shape.position.y = 1.1
		door.add_child(shape)
		holder.add_child(door)
		var yaw: float = lot["yaw"]
		door.global_position = ground(lot_front(lot, 3.6))
		door.rotation.y = yaw
		log_line("[HOOK] test InteriorDoor at the inn front %s" % _v(door.global_position))
	else:
		# The nearest inn: every town has one, and the first match could be in the capital.
		door = doors[0]
		var best := INF
		for d: InteriorDoor in doors:
			var dd := player.global_position.distance_to(d.global_position)
			if "inn" in d.interior_scene and dd < best:
				best = dd
				door = d
	var dp := Vector2(door.global_position.x, door.global_position.z)
	# Stand in the door area; the innkeeper stands close by, so step to the side of him.
	await walk_to(dp, 0.5, 30.0)
	await face(door.global_position - Vector3(sin(door.rotation.y), 0, cos(door.rotation.y)) * 4.0 + Vector3(0, 1.5, 0))
	await shot("interior_door_outside")
	var near: Node3D = player.nearest_interactable()
	log_line("  nearest interactable at the door: %s" % _name(near))
	await tap_key(KEY_E)
	var entered := await wait_until(func() -> bool: return InteriorDoor.active != null, 1.5)
	if not entered and menu_open():
		finding("major", "At the inn door, E opens the innkeeper's menu instead of entering: the innkeeper Station (3.2 m interact radius) is closer than the door, and InteriorDoor yields to any nearer interactable")
		await close_menu()
		door.enter(player)
		entered = InteriorDoor.active != null
		log_line("[HOOK] called door.enter() directly")
	if not entered:
		finding("major", "Could not enter the interior")
		return
	await wait(1.0)
	log_line("  inside: player %s, interior %s" % [_v(player.global_position), door.interior.name])
	await shot("interior_inside")
	# Walk around inside: forward, turn, and look around.
	var start := _p2()
	var room_c := Vector2(door.interior.global_position.x, door.interior.global_position.z)
	await walk_to(room_c + Vector2(0, -2.0), 1.0, 8.0, false)
	await shot("interior_walk")
	await look_around("interior")
	var ex: InteriorDoor = null
	for d in door.interior.find_children("*", "Area3D", true, false):
		if d is InteriorDoor and (d as InteriorDoor).is_exit:
			ex = d
	if ex == null:
		finding("major", "Interior has no ExitDoor")
		door.leave()
	else:
		var ep := Vector2(ex.global_position.x, ex.global_position.z)
		await walk_to(ep, 0.5, 12.0, false)
		await tap_key(KEY_E)
		var left := await wait_until(func() -> bool: return InteriorDoor.active == null, 1.5)
		log_line("  exit via ExitDoor + E: %s" % ("ok" if left else "FAILED"))
		if not left:
			finding("major", "Pressing E at the interior ExitDoor did not leave")
			door.leave()
	await wait(0.8)
	log_line("  back outside at %s (start inside was %s)" % [_v(player.global_position), start])
	await shot("interior_exit_outside")


func _step_combat() -> void:
	step("05_combat_wolves")
	var village_danger := danger()
	# Head for the wolf den nearest to Ashford.
	var dens: Array = Frontier.ecology.dens
	var den: Dictionary = {}
	for d: Dictionary in dens:
		if den.is_empty() or (d["pos"] as Vector2).length() < (den["pos"] as Vector2).length():
			den = d
	if den.is_empty():
		finding("major", "No wolf dens in the ecology")
	else:
		var dpos: Vector2 = den["pos"]
		var dir := dpos.normalized()
		var sp: Vector2 = dpos - dir * 55.0
		log_line("[HOOK] fast travel toward den %s at %s (%.0f m from Ashford)" % [den.get("id", "?"), dpos, dpos.length()])
		main._teleport(sp, atan2(-dir.x, -dir.y))
		await wait(1.0)
		log_line("Danger: village {%s} -> here {%s}" % [village_danger, danger()])
		await shot("outside_runestone_danger")
		# Walk toward the den until the pack notices us.
		var engaged := false
		var t_end := now() + 25.0
		while now() < t_end:
			if not enemies_near(22.0).is_empty():
				engaged = true
				break
			var r := await walk_to(dpos, 3.0, 2.0)
			if r["ok"]:
				break
		log_line("Wolves within 22 m: %d (all team1 within 80 m: %d)" % [enemies_near(22.0).size(), enemies_near(80.0).size()])
		if not engaged and enemies_near(80.0).is_empty():
			finding("major", "No wolves spawned at the den nearest Ashford")
		await shot("wolves_approach")
		await fight(35.0, "wolf")
	step("05b_combat_goblins")
	var w: Dictionary = Life.lore.place("mossfang_warren")
	if w.is_empty():
		finding("minor", "No mossfang_warren in the lore")
		return
	var wc: Vector2 = w["pos"]
	var from := wc + Vector2(-30, 12)
	log_line("[HOOK] fast travel to the goblin warren edge %s" % from)
	main._teleport(from, 0.0)
	main.camps.spawn_all_near(player.global_position)
	await wait(1.0)
	await face(ground(wc) + Vector3(0, 1.0, 0))
	await shot("goblin_warren")
	var t_end2 := now() + 20.0
	while now() < t_end2 and enemies_near(14.0).is_empty():
		await walk_to(wc, 4.0, 2.0)
	await fight(35.0, "goblin")


## Melee loop: close in, attack (key J and the on-screen Attack button), block (L),
## dodge (Space). Screenshots at contact, mid-fight, block, dodge, first hurt, kills.
func fight(duration: float, label: String) -> void:
	var hp0: int = player.health
	var min_hp := hp0
	var kills := 0
	var swings := 0
	var blocks := 0
	var dodges := 0
	var hurt_shot := false
	var contact_shot := false
	var block_shot := false
	var dodge_shot := false
	var kill_shots := 0
	var died := false
	var start := now()
	var next_attack := 0.0
	var next_block := now() + 3.0
	var next_dodge := now() + 5.5
	var known: Array = enemies_near(60.0)
	var ehp := {}   # enemy -> [first hp, last hp]
	var last_hp := hp0
	var mid_shot_at := now() + 4.0
	while now() - start < duration:
		if player.dead:
			if not died:
				died = true
				log_line("  PLAYER DIED at %.1fs into the %s fight" % [now() - start, label])
				var h0 := hips_height()
				var anim0 := current_anim()
				await wait(1.2)
				var h1 := hips_height()
				log_line("  death anim: '%s' -> '%s', hips %.2f m -> %.2f m above the feet" % [anim0, current_anim(), h0, h1])
				if h1 > h0 - 0.3:
					finding("major", "Player death animation does not play: hips stay at %.2f m 1.2 s after dying (%s fight)" % [h1, label])
				await shot("%s_player_death" % label)
			await wait(0.1)
			continue
		var hp: int = player.health
		if hp < last_hp:
			min_hp = mini(min_hp, hp)
			if not hurt_shot:
				hurt_shot = true
				await shot("%s_player_hurt" % label)
		last_hp = hp
		# Kills: known enemies that died (or yielded).
		for e in known.duplicate():
			if not is_instance_valid(e) or e.get("dead") or not (e as Node).is_in_group("team1"):
				known.erase(e)
				kills += 1
				log_line("  %s down (%s)" % [label, "dead" if (is_instance_valid(e) and e.get("dead")) else "yielded/freed"])
				if kill_shots < 2 and is_instance_valid(e):
					kill_shots += 1
					stick_release()
					await face((e as Node3D).global_position + Vector3(0, 0.5, 0), 0.5)
					await wait(0.7)
					await shot("%s_death_anim_%d" % [label, kill_shots])
		for e in enemies_near(40.0):
			if not known.has(e):
				known.append(e)
		var foes := enemies_near(40.0)
		if foes.is_empty():
			if now() - start > 3.0:
				break
			await get_tree().process_frame
			continue
		for e in foes:
			var h: Variant = e.get("health")
			if h != null:
				if not ehp.has(e):
					ehp[e] = [int(h), int(h)]
				ehp[e][1] = int(h)
		var f: Node3D = foes[0]
		var to := f.global_position - player.global_position
		var dist := Vector2(to.x, to.z).length()
		turn_to(atan2(-to.x, -to.z), 60.0)
		if dist > 2.1:
			stick(Vector2(0, -1.0 if dist > 5.0 else 0.6))
		else:
			stick_release()
			if not contact_shot:
				contact_shot = true
				await shot("%s_contact" % label)
			if now() > next_block:
				next_block = now() + 4.0
				blocks += 1
				key(KEY_L, true)
				await wait(0.35)
				if not block_shot:
					block_shot = true
					await shot("%s_block" % label)
				await wait(0.5)
				key(KEY_L, false)
			elif now() > next_dodge:
				next_dodge = now() + 6.0
				dodges += 1
				stick(Vector2(1, 0))
				await frames(2)
				await tap_key(KEY_SPACE)
				await wait(0.15)
				if not dodge_shot:
					dodge_shot = true
					await shot("%s_dodge" % label)
				stick_release()
			elif now() > next_attack:
				next_attack = now() + 0.3
				swings += 1
				if swings % 3 == 0:
					await tap_attack()   # the on-screen Attack button
				else:
					await tap_key(KEY_J)
		if now() > mid_shot_at:
			mid_shot_at = now() + 1e9
			await shot("%s_melee" % label)
		await get_tree().process_frame
	stick_release()
	look_release()
	key(KEY_L, false)
	var left := enemies_near(40.0).size()
	var hps := PackedStringArray()
	for e in ehp:
		hps.append("%d->%d" % [ehp[e][0], ehp[e][1]])
	log_line("  enemy hp (first seen -> last seen): %s" % ", ".join(hps))
	log_line("FIGHT %s: %.1fs, swings %d, blocks %d, dodges %d, kills/yields %d, enemies left %d, hp %d -> min %d -> %d, died %s" % [
		label, now() - start, swings, blocks, dodges, kills, left, hp0, min_hp, player.health, died])
	if swings > 10 and kills == 0:
		finding("major", "%d swings at %ss but none went down" % [swings, label])
	if min_hp == hp0 and not died and swings > 0:
		finding("minor", "Player took no damage fighting %ss (enemies passive or too weak?)" % label)
	await shot("%s_after_fight" % label)


func _step_night() -> void:
	step("06_sleep_night")
	var inn := station(" Inn")
	if inn == null:
		finding("major", "No innkeeper station")
		return
	var ip := Vector2(inn.global_position.x, inn.global_position.z)
	log_line("[HOOK] fast travel back to Ashford")
	main._teleport(WorldGen.settlements[0]["pos"] + Vector2(0, 4), 0.0)   # the open plaza
	await wait(0.8)
	await walk_to(ip + (_p2() - ip).normalized() * 1.6, 0.8, 20.0)
	await face(inn.global_position + Vector3(0, 1.5, 0))
	WorldSim.time_of_day = 19.5
	Life.needs.rest = 30.0
	if Game.gold < 10:
		Game.gold = 20
	log_line("[HOOK] clock 19:30, rest 30 (tired), gold %d" % Game.gold)
	var hour0 := WorldSim.time_of_day
	var day0 := WorldSim.day
	if await interact_with(inn, "innkeeper"):
		await shot("inn_menu")
		var r := await click_menu("Rent a bed")
		await wait(0.6)
		log_line("  slept: %s -> day %d %.1fh -> day %d %.1fh" % [r, day0, hour0, WorldSim.day, WorldSim.time_of_day])
		if WorldSim.day == day0 and absf(WorldSim.time_of_day - hour0) < 0.5:
			finding("major", "Renting a bed did not advance time")
		await shot("after_sleep")
		await close_menu()
	else:
		finding("major", "Innkeeper menu did not open")
	# Night lighting.
	WorldSim.time_of_day = 22.5
	log_line("[HOOK] clock 22:30 for the night check")
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	await walk_to(c + Vector2(0, 6), 2.0, 25.0)
	await face(ground(c) + Vector3(0, 2.0, 0))
	await wait(1.5)
	var lamps := get_tree().get_nodes_in_group("street_lamp")
	var lit := 0
	for l in lamps:
		if (l as Light3D).visible and (l as Light3D).light_energy > 0.1:
			lit += 1
	log_line("Night: %d street lamps, %d lit; sun energy %.2f" % [lamps.size(), lit, main.sun.light_energy])
	if lit == 0:
		finding("major", "No street lamps lit at 22:30")
	await shot("night_plaza")
	await look_around("night")
	WorldSim.time_of_day = 12.0


func _step_save_load() -> void:
	step("07_save_load")
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	await walk_to(c + Vector2(-3, 8), 1.5, 20.0)
	player.take_damage(25)
	await wait(0.5)
	var before := _state()
	log_line("state before save: %s" % before)
	await tap_key(KEY_F5)
	await wait(0.5)
	await shot("saved")
	# Change things: walk away, earn gold, heal, wait an hour.
	await walk_to(c + Vector2(12, -12), 1.5, 20.0)
	Game.add_gold(77)
	player.heal(50)
	WorldSim.time_of_day += 1.5
	Life.give("apple", 3)
	var changed := _state()
	log_line("state changed:     %s" % changed)
	await shot("changed_before_load")
	await tap_key(KEY_F9)
	await wait(1.0)
	var after := _state()
	log_line("state after load:  %s" % after)
	await shot("after_load")
	var bad := PackedStringArray()
	for k: String in before:
		var a: Variant = before[k]
		var b: Variant = after[k]
		var same := false
		if a is Vector3:
			same = (a as Vector3).distance_to(b) < 0.6
		elif a is float:
			same = absf(float(a) - float(b)) < 0.25   # the clock keeps running (~0.03 h per real second)
		else:
			same = a == b
		log_line("  restore %-8s %s" % [k, "OK" if same else "MISMATCH (%s vs %s)" % [a, b]])
		if not same:
			bad.append(k)
	if not bad.is_empty():
		finding("major", "Quick load (F9) did not restore: %s" % ", ".join(bad))


func _state() -> Dictionary:
	return {"pos": player.global_position, "health": int(player.health), "gold": int(Game.gold),
		"hour": snappedf(WorldSim.time_of_day, 0.01), "day": int(WorldSim.day), "apples": Life.count("apple"),
		"bread": Life.count("bread")}


func _finish() -> void:
	step("end")
	_end_step()
	for e: String in _logger.take():
		_engine_error(e)
	log_line("=== FINDINGS (%d) ===" % findings.size())
	for f: Dictionary in findings:
		log_line("  [%s] %s: %s (after shot %02d)" % [f["sev"], f["step"], f["text"], f["shot"]])
	log_line("Engine errors/warnings captured in-process: %d" % _errors_seen)
	var keys := _error_counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _error_counts[a] > _error_counts[b])
	for k: String in keys:
		log_line("  %6dx %s" % [_error_counts[k], k])
	var sf := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	sf.store_string(JSON.stringify({"steps": steps, "findings": findings, "engine_errors": _errors_seen, "engine_error_counts": _error_counts,
		"gpu": RenderingServer.get_video_adapter_name()}, "  "))
	sf.close()
	log_line("done in %.1fs" % now())
	_log.close()
	_log = null
	# Free the game scene and give it several frames to unwind (TerrainStreamer's
	# WorkerThreadPool tasks, threaded resource loads, RenderingServer RIDs) before
	# quit(). Calling get_tree().quit() while `main` was still a live child left
	# thousands of RIDs and worker threads mid-flight, racing RenderingServer
	# teardown -- the root cause of the ntdll heap-corruption crashes (0xc0000005)
	# in the Windows event log. See docs/qa/stability.md.
	if is_instance_valid(main):
		main.queue_free()
		main = null
	for i in 10:
		await get_tree().process_frame
	get_tree().quit()


# --- animation probes ----------------------------------------------------------------

func _skeleton() -> Skeleton3D:
	var sk := player.find_children("*", "Skeleton3D", true, false)
	return sk[0] if not sk.is_empty() else null


## Height of the hips/pelvis bone above the player's origin (about 1 m standing, ~0.2 m lying).
func hips_height() -> float:
	var sk := _skeleton()
	if sk == null:
		return -1.0
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i).to_lower()
		if n.contains("pelvis") or n.contains("hips"):
			return (sk.global_transform * sk.get_bone_global_pose(i)).origin.y - player.global_position.y
	return -1.0


func current_anim() -> String:
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	for ap: AnimationPlayer in aps:
		if ap.is_playing():
			return "%s%s" % [ap.current_animation, "" if ap.active else " (player inactive)"]
	return "none"
