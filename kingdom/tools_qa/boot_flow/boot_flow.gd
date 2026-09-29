extends SceneTree
## Drives the REAL boot flow with synthetic taps and saves stills, so the whole path can be captured
## with Godot Movie Maker and read as contact sheets (skill ashes-video-review):
##   engine splash -> studio intro (tap to skip or play out) -> title splash -> first-run (language,
##   privacy, how-to-play) -> main menu -> New Game -> loading -> world veil -> gameplay -> pause menu
##   -> Android back button -> autosave on NOTIFICATION_APPLICATION_PAUSED -> Exit to Main Menu -> Continue.
##
## Never pass user args (`-- ...`): those make boot skip straight into the game (QA mode).
##   godot --path kingdom --resolution 2400x1080 --write-movie <dir>/frame.png --fixed-fps 30 \
##         -s res://tools_qa/boot_flow/boot_flow.gd
## Environment (no user args allowed, so options come from env vars):
##   BOOT_FLOW_OUT   directory for stills (absolute)       BOOT_FLOW_TAG   file prefix, e.g. "wide"
##   BOOT_FLOW_SKIP  "1": tap-skip the studio intro after 2.5 s instead of letting it play out
##   BOOT_FLOW_FAST  "1": only intro + splash + menu (no world generation)
## First-run flags in user://settings.cfg are cleared for the run and the file is restored at the end.

const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const Flow := preload("res://scripts/ui/frontend/flow.gd")

var _out := ""
var _tag := ""
var _backup := ""
var _had_cfg := false
var _errors := 0
var _t0 := 0


func _initialize() -> void:
	_out = OS.get_environment("BOOT_FLOW_OUT")
	_tag = OS.get_environment("BOOT_FLOW_TAG")
	if _out == "":
		_out = ProjectSettings.globalize_path("user://boot_flow")
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _run() -> void:
	_reset_first_run()
	await process_frame
	root.get_window().title = "boot_flow"
	print("[flow] size ", root.size, " intro video exists: ", ResourceLoader.exists("res://assets/video/studio_intro.ogv"))
	change_scene_to_file("res://scenes/boot.tscn")
	await _frames(2)
	# --- 1. studio intro ---
	await _secs(0.25)
	await _shot("01_intro_fadein")
	await _secs(1.4)
	await _shot("02_intro_mid")
	if OS.get_environment("BOOT_FLOW_SKIP") == "1":
		await _secs(1.0)
		print("[flow] tap to skip intro")
		await _tap_center()
	else:
		var ok := await _wait(func() -> bool: return _find_script("splash.gd") != null, 14.0)
		print("[flow] intro finished by itself: ", ok)
	# --- 2. title splash ---
	if not await _wait(func() -> bool: return _find_script("splash.gd") != null, 6.0):
		return _fail("title splash never appeared")
	await _secs(1.6)
	await _shot("03_splash")
	await _key(KEY_ENTER)
	# --- 3. first run ---
	if not await _wait(func() -> bool: return _find_script("first_run.gd") != null, 4.0):
		return _fail("first-run flow never appeared")
	await _secs(0.7)
	await _shot("04_first_run_language")
	await _click_text("English")
	await _secs(0.5)
	await _shot("05_first_run_privacy")
	await _click_text("I agree")
	await _secs(0.5)
	await _shot("06_first_run_howto")
	await _click_text("Continue")
	# --- 4. main menu ---
	if not await _wait(func() -> bool: return _find_script("main_menu.gd") != null, 4.0):
		return _fail("main menu never appeared")
	await _secs(1.2)
	await _shot("07_main_menu")
	if OS.get_environment("BOOT_FLOW_FAST") == "1":
		return _finish()
	await _click_text("New Game")
	await _secs(0.9)
	await _shot("08_new_game")
	await _click_text("Start Game")
	# --- 5. loading + world veil ---
	await _secs(0.6)
	await _shot("09_loading_screen")
	if not await _wait(func() -> bool: return WorldLoading.current != null, 12.0):
		return _fail("world veil never appeared")
	await _shot("10_world_veil_start")
	var n := 11
	var last := -1
	while WorldLoading.current != null and (Time.get_ticks_msec() - _t0) < 240000:
		var pr := int(WorldLoading.current.progress * 4.0)
		if pr != last:
			last = pr
			await _shot("%d_world_veil_%d" % [n, pr * 25])
			n += 1
		await process_frame
	print("[flow] world veil done")
	# A new life opens with the birth cutscene, then a growing-up choice dialog: skip and answer them.
	if await _wait(func() -> bool: return _find_script("cutscene_player.gd") != null, 8.0):
		await _secs(1.5)
		await _shot("14_birth_cutscene")
		var cs := _find_script("cutscene_player.gd")
		if cs and cs.has_method("skip"):
			cs.call("skip")
		await _secs(1.5)
	await _dismiss_choices()
	await _secs(1.5)
	await _shot("15_gameplay")
	# --- 6. pause menu and back button ---
	await _key(KEY_ESCAPE)
	await _secs(0.7)
	if not paused:
		_fail("Esc did not open the pause menu")
	await _shot("16_pause_menu")
	await _click_text("Settings")
	await _secs(0.7)
	await _shot("17_pause_settings")
	await _key(KEY_ESCAPE)
	await _secs(0.4)
	await _key(KEY_ESCAPE)   # close pause
	await _secs(0.4)
	if paused:
		_fail("pause menu did not close")
	# Android back button while playing opens pause (App turns WM_GO_BACK_REQUEST into ui_cancel).
	root.get_node("App").notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _secs(0.5)
	if not paused:
		_fail("back button did not open the pause menu")
	await _key(KEY_ESCAPE)
	await _secs(0.4)
	# --- 7. autosave on app pause ---
	var before := _newest_save()
	get_root().propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _secs(0.5)
	get_root().propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _secs(0.5)
	var after := _newest_save()
	print("[flow] newest save before=", before, " after=", after)
	if after == "" or after == before and not FileAccess.file_exists(after):
		_fail("no save written on NOTIFICATION_APPLICATION_PAUSED")
	await _shot("18_after_resume")
	if paused:
		await _key(KEY_ESCAPE)
		await _secs(0.4)
	# --- 8. exit to menu, Continue ---
	Flow.exit_to_menu(self)
	if not await _wait(func() -> bool: return _find_script("main_menu.gd") != null, 8.0):
		return _fail("main menu after exit never appeared")
	await _secs(1.4)
	await _shot("19_menu_with_continue")
	await _click_text("Continue")
	await _secs(0.6)
	await _shot("20_continue_loading")
	if not await _wait(func() -> bool: return WorldLoading.current != null, 12.0):
		return _fail("world veil after Continue never appeared")
	await _wait(func() -> bool: return WorldLoading.current == null, 240.0)
	await _secs(4.0)
	await _shot("21_continue_gameplay")
	_finish()


func _dismiss_choices() -> void:
	for i in 4:
		var hit: Button = null
		var until := Time.get_ticks_msec() + (12000 if i == 0 else 1500)
		while hit == null and Time.get_ticks_msec() < until:
			hit = _find_long_button()
			await process_frame
		if hit == null:
			return
		print("[flow] answering dialog: ", hit.text)
		await _tap(hit.get_global_rect().get_center())
		await _secs(1.2)


func _find_long_button() -> Button:
	var all := []
	_walk(root, all)
	for n: Node in all:
		if n is Button and (n as Button).is_visible_in_tree() and not (n as Button).disabled and (n as Button).text.length() > 20:
			return n
	return null


func _finish() -> void:
	_restore_cfg()
	print("[flow] BOOTFLOW ", "OK" if _errors == 0 else "FAILED (%d)" % _errors)
	quit(0 if _errors == 0 else 1)


func _fail(msg: String) -> void:
	_errors += 1
	printerr("[flow] FAIL: ", msg)
	if msg.contains("never appeared"):
		_finish()


# --- helpers -----------------------------------------------------------------------------------


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _wait(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s%s.png" % [_out, _tag, name]
	img.save_png(path)
	print("[flow] shot ", path, " ", img.get_size())


func _walk(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _find_script(file: String) -> Node:
	var all := []
	_walk(root, all)
	for n: Node in all:
		var s: Script = n.get_script()
		if s and s.resource_path.ends_with(file) and (not n is CanvasItem or (n as CanvasItem).is_visible_in_tree()):
			return n
	return null


func _click_text(text: String) -> void:
	var all := []
	_walk(root, all)
	for n: Node in all:
		if n is Button and (n as Button).text.strip_edges() == text and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
			var r := (n as Button).get_global_rect()
			await _tap(r.get_center())
			return
	_fail("button not found: " + text)


func _tap(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	root.push_input(mm)
	await process_frame
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		ev.global_position = p
		root.push_input(ev)
		await process_frame
	await process_frame


func _tap_center() -> void:
	await _tap(Vector2(root.size) * 0.5)


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _newest_save() -> String:
	var best := ""
	var best_t := 0
	var d := DirAccess.open("user://saves")
	if d == null:
		return ""
	for f in d.get_files():
		var t := FileAccess.get_modified_time("user://saves/" + f)
		if t >= best_t:
			best_t = t
			best = "user://saves/" + f
	return best + "@" + str(best_t)


func _reset_first_run() -> void:
	_had_cfg = FileAccess.file_exists(SS.PATH)
	if _had_cfg:
		_backup = FileAccess.get_file_as_string(SS.PATH)
	var cf := ConfigFile.new()
	cf.load(SS.PATH)
	if cf.has_section("flow"):
		cf.erase_section("flow")
	cf.save(SS.PATH)


func _restore_cfg() -> void:
	if _had_cfg:
		var f := FileAccess.open(SS.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SS.PATH))
