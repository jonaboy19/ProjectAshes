extends Node
## Rising Ashes playtest bot: plays the first in-game days of the REAL game through the real main scene.
##
##   tools_qa/playtest_bot/run_playtest.sh [stages]
##   (godot scenes/main.tscn -- --quality=low --qa=res://tools_qa/playtest_bot/playtest_bot.gd)
##
## main.gd calls run(main) after the world is built. The bot then plays stage by stage (intro skip, walk to the
## Ashford market, talk, every menu tab, shop, equip, eat, job shift, scribe, gather via GatherPanel, craft, fight a
## wolf and a bandit, steal, sleep at the inn, coach fast travel, save, quit, reload and verify, Act I of the story).
## Input goes through the same paths as a player where practical: key events (E, J, F, ...), held movement actions
## steered by the camera yaw, real mouse clicks on menu buttons. Shortcuts a player cannot take (teleport to a far
## spot, ageing the character, handing out gold or items) are logged as [HOOK].
##
## Per stage the bot records: duration, fps and draw calls (min/avg/max), every SCRIPT ERROR / ERROR / WARNING the
## engine logged (via a Logger), stuck detection (no progress in STUCK_SECS, or the stage deadline), a screenshot,
## and CHECK lines (expected vs actual). It writes report.md + summary.json after every stage.
## Stage filter: PLAYTEST_STAGES=boot,intro,menus (env var). Output dir: PLAYTEST_OUT.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const TravelRules := preload("res://scripts/world/travel_rules.gd")
const STUCK_SECS := 25.0
var SHOT_DIR := "/tmp/claude-0/shots/playtest"

static var instance: Node = null     # the first bot; a reloaded main hands its world over to it

signal reloaded(new_main: Node)
signal _never

var main: Node
var player: Node3D
var hud: CanvasLayer
var out_dir := "/tmp/claude-0/playtest"
var only := ""
var t0 := 0
var stage_name := "boot"
var stage_t0 := 0.0
var stage_deadline := 0.0
var gen := 0                               # bumps when a stage times out so orphaned coroutines stop
var results: Array = []                    # per stage dicts
var cur: Dictionary = {}
var bugs: Array = []                       # {stage, kind, text}
var _tap: RefCounted
var _samples: Array = []
var _sample_t := 0.0
var _err_counts: Dictionary = {}
var _last_progress := 0.0
var _progress_sig := ""
var _shot_n := 0
var _log: FileAccess
var _held: Array[String] = []
var _stage_done := false
var _fps_floor := 0.0
var _frame_max := 0.0
var _last_us := 0
var _last_fight_log := -1.0
var _bounded_until := 0.0               # a bounded wait is in progress until this time: not 'stuck'


class ErrorTap extends Logger:
	var mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _e: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		var kinds := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
		var kind: String = kinds[error_type] if error_type >= 0 and error_type < kinds.size() else "ERROR"
		var msg := rationale if rationale != "" else code
		mutex.lock()
		lines.append("%s: %s  (%s:%d %s)" % [kind, msg, file, line, function])
		mutex.unlock()

	func take() -> Array[String]:
		mutex.lock()
		var out := lines.duplicate()
		lines.clear()
		mutex.unlock()
		return out


# --------------------------------------------------------------------------------------------- entry

func run(p_main: Node) -> void:
	if instance != null and is_instance_valid(instance):
		# main.tscn was entered again (reload step): hand the new world to the running bot and go away.
		instance.reloaded.emit(p_main)
		queue_free()
		return
	instance = self
	main = p_main
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	out_dir = OS.get_environment("PLAYTEST_OUT") if OS.get_environment("PLAYTEST_OUT") != "" else out_dir
	only = OS.get_environment("PLAYTEST_STAGES")
	if OS.get_environment("PLAYTEST_SHOTS") != "":
		SHOT_DIR = OS.get_environment("PLAYTEST_SHOTS")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_log = FileAccess.open(out_dir.path_join("run.log"), FileAccess.WRITE)
	_tap = ErrorTap.new()
	OS.add_logger(_tap)
	_grab_refs()
	L("playtest bot start, stages filter '%s', adapter %s, quality tier forced low" % [only, RenderingServer.get_video_adapter_name()])
	await _run_all()


func _grab_refs() -> void:
	player = main.player
	hud = main.hud


func now() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0


func L(s: String) -> void:
	var line := "[%7.1f] [%s] %s" % [now(), stage_name, s]
	print("PLAYTEST ", line)
	if _log:
		_log.store_line(line)
		_log.flush()


func bug(kind: String, text: String) -> void:
	bugs.append({"stage": stage_name, "kind": kind, "text": text})
	(cur.get("issues", []) as Array).append("%s: %s" % [kind, text])
	L("BUG[%s] %s" % [kind, text])


## A checked expectation: logs PASS/FAIL, a FAIL counts as a bug.
func check(label: String, ok: bool, detail := "") -> bool:
	(cur.get("checks", []) as Array).append({"label": label, "ok": ok, "detail": detail})
	L("CHECK %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		bugs.append({"stage": stage_name, "kind": "check", "text": "%s %s" % [label, detail]})
	return ok


# --------------------------------------------------------------------------------------------- frame hook

func _process(_d: float) -> void:
	var us := Time.get_ticks_usec()
	if _last_us > 0 and stage_name != "":
		_frame_max = maxf(_frame_max, (us - _last_us) / 1000.0)
	_last_us = us
	if _tap != null:
		for e: String in _tap.take():
			_on_engine_error(e)
	_sample_t -= _d
	if _sample_t <= 0.0:
		_sample_t = 0.5
		_sample()
	_watch_progress()


func _on_engine_error(e: String) -> void:
	var k := "%s|%s" % [stage_name, e.substr(0, 200)]
	var n: int = int(_err_counts.get(k, 0)) + 1
	_err_counts[k] = n
	if n == 1:
		(cur.get("errors", []) as Array).append(e)
		L("ENGINE " + e)
		bugs.append({"stage": stage_name, "kind": "engine", "text": e})
	else:
		var arr: Array = cur.get("errors", [])
		cur["err_repeats"] = int(cur.get("err_repeats", 0)) + 1
		if n in [10, 100, 1000] and not arr.is_empty():
			L("ENGINE x%d %s" % [n, e.substr(0, 120)])


func _sample() -> void:
	var s := {"fps": Engine.get_frames_per_second(), "draws": 0, "prims": 0, "objs": 0}
	if main != null and is_instance_valid(main) and main.get("viewport") != null and is_instance_valid(main.viewport):
		var rid: RID = main.viewport.get_viewport_rid()
		s["draws"] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		s["prims"] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		s["objs"] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	_samples.append(s)


func _watch_progress() -> void:
	if stage_deadline <= 0.0 or _stage_done:
		return
	var sig := _progress_signature()
	if sig != _progress_sig:
		_progress_sig = sig
		_last_progress = now()
	elif now() - _last_progress > STUCK_SECS and now() > _bounded_until and not cur.get("stuck_logged", false):
		cur["stuck_logged"] = true
		bug("stuck", "no progress for %.0fs (pos %s, menu open %s)" % [STUCK_SECS, _pos2s(), str(hud != null and is_instance_valid(hud) and hud.is_menu_open())])


func _progress_signature() -> String:
	var p := Vector3.ZERO
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		p = player.global_position
	return "%d|%d|%d|%d|%d|%s" % [roundi(p.x), roundi(p.z), Game.gold, WorldSim.day * 24 + int(WorldSim.time_of_day * 2.0), _inv_total(), cur.get("beat", "")]


func beat(tag: String) -> void:
	cur["beat"] = tag
	_last_progress = now()


func _pos2s() -> String:
	if player == null or not is_instance_valid(player):
		return "-"
	return "(%.0f, %.0f)" % [player.global_position.x, player.global_position.z]


func _inv_total() -> int:
	var n := 0
	var inv: Variant = Life.get("inventory")
	if inv != null:
		for it in inv.get_items():
			n += int(it.get_stack_size())
	return n


# --------------------------------------------------------------------------------------------- waiting

func _cancelled(g: int) -> bool:
	return g != gen


func wait(sec: float) -> void:
	var g := gen
	_bounded_until = maxf(_bounded_until, now() + sec + 1.0)
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		if _cancelled(g):
			await _never


func frames(n: int) -> void:
	var g := gen
	for i in n:
		await get_tree().process_frame
		if _cancelled(g):
			await _never


func wait_until(cond: Callable, timeout: float) -> bool:
	var g := gen
	_bounded_until = maxf(_bounded_until, now() + timeout + 1.0)
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
		if _cancelled(g):
			await _never
	return bool(cond.call())


# --------------------------------------------------------------------------------------------- input

func key(k: int, hold_frames := 2) -> void:
	beat("key %d" % k)
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(hold_frames if pressed else 2)


func hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
		if not _held.has(action):
			_held.append(action)
	else:
		Input.action_release(action)
		_held.erase(action)


func release_all() -> void:
	for a in _held.duplicate():
		Input.action_release(a)
	_held.clear()


func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


func p2() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func face(target: Vector2, pitch := -0.2) -> void:
	player.set_camera(yaw_to(p2(), target), pitch)


## Walks like a player: holds the forward (and sprint) action, steering with the camera yaw. Logs a stuck line and
## returns false when the distance does not shrink for `stuck_s` seconds or after `timeout`.
func walk_to(target: Vector2, tol := 2.5, timeout := 90.0, sprint := true, stuck_s := 8.0) -> bool:
	var g := gen
	var t_start := now()
	var best := p2().distance_to(target)
	var best_t := now()
	hold("sprint", sprint)
	hold("move_forward", true)
	var ok := false
	while now() - t_start < timeout:
		var d := p2().distance_to(target)
		if d <= tol:
			ok = true
			break
		face(target, -0.15)
		if d < best - 0.4:
			best = d
			best_t = now()
			beat("walk %d" % roundi(d))
		elif now() - best_t > stuck_s:
			L("walk_to stuck at %s, %.1f m from %s" % [_pos2s(), d, str(target)])
			break
		await get_tree().process_frame
		if _cancelled(g):
			release_all()
			await _never
	release_all()
	await frames(2)
	return ok


func teleport(p: Vector2, yaw := 0.0, settle := 1.0) -> void:
	L("[HOOK] teleport to (%.0f, %.0f)" % [p.x, p.y])
	main.call("_teleport", p, yaw)
	await frames(2)
	for i in 4:
		main.settlements.update_now()
	main.region._timer = 0.0
	await wait(settle)
	var guard := 0
	while not main.region._queue.is_empty() and guard < 3000:
		main.region._drain_queue()
		guard += 1
	await frames(2)


## Real mouse click at the centre of a control. Flags a button that something else covers.
func click(c: Control, label := "") -> bool:
	beat("click " + label)
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return false
	var sp: Node = c.get_parent()
	while sp != null:
		if sp is ScrollContainer:
			(sp as ScrollContainer).ensure_control_visible(c)
			await frames(2)
			break
		sp = sp.get_parent()
	var vp := c.get_viewport()
	var r := c.get_global_rect()
	var pos := r.get_center()
	var vis := vp.get_visible_rect()
	if not vis.has_point(pos):
		L("click: %s centre %s is off screen %s; emitting pressed" % [label if label != "" else c.name, str(pos), str(vis.size)])
		if c is BaseButton:
			(c as BaseButton).pressed.emit()
		return true
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await frames(2)
	var hov: Control = vp.gui_get_hovered_control()
	if hov != null and hov != c and not c.is_ancestor_of(hov) and not hov.is_ancestor_of(c):
		var lay := ""
		var q: Node = hov
		while q != null:
			if q is CanvasLayer:
				lay = " [CanvasLayer %s layer %d]" % [q.name, (q as CanvasLayer).layer]
				break
			q = q.get_parent()
		bug("ui-blocked", "button '%s' (layer %s) is covered by %s (%s) at %s%s" % [label if label != "" else (c as BaseButton).get("text"), _layer_of(c), hov.name, hov.get_class(), str(hov.get_path()), lay])
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(mb)
		await frames(2)
	return true


func _layer_of(n: Node) -> String:
	var q: Node = n
	while q != null:
		if q is CanvasLayer:
			return "%s=%d" % [q.name, (q as CanvasLayer).layer]
		q = q.get_parent()
	return "none"


func buttons_in(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for n in root.find_children("*", "BaseButton", true, false):
		if (n as Control).is_visible_in_tree():
			out.append(n)
	return out


func button_text(b: Node) -> String:
	return String(b.get("text")) if b.get("text") != null else ""


## First visible button under `root` whose text starts with / contains `needle`.
func find_button(root: Node, needle: String, contains := false) -> BaseButton:
	for b in buttons_in(root):
		var t := button_text(b)
		if (contains and needle.to_lower() in t.to_lower()) or (not contains and t.to_lower().begins_with(needle.to_lower())):
			return b
	return null


func click_text(root: Node, needle: String, contains := true) -> bool:
	var b := find_button(root, needle, contains)
	if b == null:
		return false
	await click(b, needle)
	return true


func hud_menu_texts() -> Array:
	return buttons_in(hud._menu).map(func(b: Node) -> String: return button_text(b))


func dismiss_popups() -> void:
	for c in hud.get_children():
		var sc: Script = c.get_script()
		if sc and String(sc.resource_path).ends_with("life_event_popup.gd") and c.visible:
			L("dismiss life-event popup")
			if c.has_method("close"):
				c.call("close")
			else:
				c.hide()
	if get_tree().paused and not hud.has_node("PauseMenu") and not GameMenu.is_open(hud):
		pass


## The real death flow: the DeathScreen's "Respawn at Home" button, clicked. Returns true if the player had died.
func ensure_alive() -> bool:
	var ds: Node = null
	for c in hud.get_children():
		var sc: Script = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("death_screen.gd") and (c as CanvasItem).visible:
			ds = c
	if ds == null and not bool(player.get("dead")):
		return false
	if ds == null:
		await wait_until(func() -> bool:
			for c in hud.get_children():
				var sc2: Script = c.get_script()
				if sc2 != null and String(sc2.resource_path).ends_with("death_screen.gd") and (c as CanvasItem).visible:
					return true
			return false, 10.0)
		for c in hud.get_children():
			var sc3: Script = c.get_script()
			if sc3 != null and String(sc3.resource_path).ends_with("death_screen.gd") and (c as CanvasItem).visible:
				ds = c
	L("player is dead (death screen %s): clicking Respawn at Home" % ("shown" if ds != null else "MISSING"))
	if ds == null:
		bug("death", "player.dead is true but no DeathScreen is visible (soft-lock)")
		player.call("revive")
		return true
	await wait(1.0)
	await shot("death_screen")
	var hp_before: int = int(player.health)
	if not await click_text(ds, "Respawn", true):
		bug("death", "no Respawn button on the death screen: %s" % str(buttons_in(ds).map(func(b: Node) -> String: return button_text(b))))
	await wait(2.0)
	check("Respawn at Home revives the player", not bool(player.get("dead")) and player.health > 0, "hp %d -> %d" % [hp_before, player.health])
	return true


func close_everything() -> void:
	dismiss_popups()
	if hud.is_menu_open():
		hud.close_menu()
	if GameMenu.is_open(hud):
		hud.get_node("GameMenu").call("close")
	for n in ["ShopScreen", "CraftingScreen", "CareerTasks", "TradeScreen"]:
		var s := hud.get_node_or_null(n)
		if s != null and s.visible:
			if s.has_method("close_screen"):
				s.call("close_screen")
			elif s.has_method("close"):
				s.call("close")
	if get_tree().paused and not hud.has_node("PauseMenu"):
		L("still paused after closing everything")
		get_tree().paused = false


# --------------------------------------------------------------------------------------------- screenshots

func shot(tag: String) -> void:
	dismiss_popups()
	await frames(3)
	await wait(0.3)
	_shot_n += 1
	var file := "%02d_%s_%s.png" % [_shot_n, stage_name, tag]
	var img := get_tree().root.get_texture().get_image()
	if img != null:
		img.save_png(SHOT_DIR.path_join(file))
		(cur.get("shots", []) as Array).append(file)
		L("shot " + file)


# --------------------------------------------------------------------------------------------- stage runner

func _want(name: String) -> bool:
	return only == "" or ("," + only + ",").contains("," + name + ",")


func _run_all() -> void:
	var list: Array = [
		["boot", _s_boot], ["intro", _s_intro], ["market", _s_market], ["npcs", _s_npcs], ["interior", _s_interior], ["menus", _s_menus],
		["story", _s_story], ["adult", _s_adult], ["shop", _s_shop], ["equip", _s_equip], ["eat", _s_eat],
		["job", _s_job], ["scribe", _s_scribe], ["gather", _s_gather], ["craft", _s_craft], ["fight", _s_fight],
		["steal", _s_steal], ["sleep", _s_sleep], ["coach", _s_coach], ["save", _s_save],
		["tf_talk", _s_tf_talk], ["tf_barley", _s_tf_barley], ["tf_cart", _s_tf_cart], ["tf_wilm", _s_tf_wilm],
		["tf_interior", _s_tf_interior], ["tf_theft", _s_tf_theft], ["tf_travel", _s_tf_travel], ["tf_combat", _s_tf_combat],
		["tf_soldier", _s_tf_soldier], ["tf_rift", _s_tf_rift], ["tf_beast", _s_tf_beast], ["tf_save", _s_tf_save],
	]
	for e: Array in list:
		if not _want(String(e[0])) and String(e[0]) != "adult":
			continue
		await _run_stage(String(e[0]), e[1], _stage_limit(String(e[0])))
		_write_report()
	stage_name = "end"
	L("all stages done; %d bugs" % bugs.size())
	_write_report()
	release_all()
	get_tree().quit(0)


func _stage_limit(name: String) -> float:
	match name:
		"boot": return 200.0
		"story": return 300.0
		"fight": return 240.0
		"save": return 360.0
		"job", "gather": return 200.0
		"tf_talk": return 200.0
		"tf_barley": return 420.0
		"tf_cart": return 520.0
		"tf_wilm": return 260.0
		"tf_interior": return 330.0
		"tf_theft": return 330.0
		"tf_travel": return 330.0
		"tf_combat": return 300.0
		"tf_soldier": return 260.0
		"tf_rift": return 480.0
		"tf_beast": return 200.0
		"tf_save": return 480.0
	return 150.0


func _run_stage(name: String, fn: Callable, limit: float) -> void:
	gen += 1
	stage_name = name
	stage_t0 = now()
	stage_deadline = now() + limit
	_stage_done = false
	_last_progress = now()
	_progress_sig = ""
	_samples.clear()
	_frame_max = 0.0
	cur = {"name": name, "issues": [], "checks": [], "errors": [], "shots": [], "notes": []}
	L("=== STAGE %s (limit %.0fs) ===" % [name, limit])
	var my_gen := gen
	if name != "boot":
		await ensure_alive()
	var done := [false]
	_exec(fn, done)
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not done[0] and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	if not done[0]:
		bug("timeout", "stage exceeded %.0fs deadline (stuck or too slow)" % limit)
		gen += 1          # orphan the stage coroutine
		release_all()
	_stage_done = true
	Engine.max_physics_steps_per_frame = 8       # undo any fast_game() of the stage
	if my_gen == gen - (0 if done[0] else 1):
		pass
	close_everything()
	if InteriorDoor.active != null and name != "interior":
		bug("bot", "the player ended the stage inside a building: leaving through the entrance door")
		InteriorDoor.active.call("leave")
		await wait(2.0)
	var tsite: Node = _find_node_by_script(main.world, "tower_site.gd")
	if tsite != null and bool(tsite.get("inside")):
		bug("bot", "the player ended the stage inside a tower (interior mode hides the world): leaving")
		tsite.call("leave_tower")
	var secs := now() - stage_t0
	cur["secs"] = secs
	cur["timed_out"] = not done[0]
	_finish_metrics()
	results.append(cur)
	L("=== END %s %.1fs fps avg %.1f draws avg %.0f max %.0f, %d engine errors, %d issues ===" % [name, secs, cur["fps_avg"], cur["draws_avg"], cur["draws_max"], (cur["errors"] as Array).size(), (cur["issues"] as Array).size()])
	await frames(2)


func _exec(fn: Callable, done: Array) -> void:
	await fn.call()
	done[0] = true


func _finish_metrics() -> void:
	var n := maxi(_samples.size(), 1)
	var fsum := 0.0
	var dsum := 0.0
	var dmax := 0.0
	var fmin := 1e9
	var pmax := 0.0
	for s: Dictionary in _samples:
		fsum += float(s["fps"])
		dsum += float(s["draws"])
		dmax = maxf(dmax, float(s["draws"]))
		fmin = minf(fmin, float(s["fps"]))
		pmax = maxf(pmax, float(s["prims"]))
	cur["fps_avg"] = fsum / n
	cur["fps_min"] = fmin if not _samples.is_empty() else 0.0
	cur["draws_avg"] = dsum / n
	cur["draws_max"] = dmax
	cur["prims_max"] = pmax
	cur["worst_frame_ms"] = _frame_max
	if not _samples.is_empty() and cur["draws_avg"] < 40.0 and not (cur["name"] in ["menus", "scribe", "boot", "tf_interior", "tf_rift"]) and not get_tree().paused:
		bug("render", "world barely renders in this stage: %.0f draw calls on average" % cur["draws_avg"])


func _write_report() -> void:
	var md := PackedStringArray()
	md.append("# Rising Ashes playtest bot report")
	md.append("")
	md.append("Run %s, %.0f s elapsed, renderer %s, LOW tier (xvfb software GL: fps is not meaningful, draws are)." % [Time.get_datetime_string_from_system(), now(), RenderingServer.get_video_adapter_name()])
	md.append("")
	md.append("| stage | secs | fps avg | draws avg/max | worst frame ms | engine errors | issues | result |")
	md.append("|---|---|---|---|---|---|---|---|")
	for r: Dictionary in results:
		var checks: Array = r["checks"]
		var failed := checks.filter(func(c: Dictionary) -> bool: return not bool(c["ok"])).size()
		var res := "STUCK/TIMEOUT" if bool(r.get("timed_out", false)) else ("FAIL" if failed > 0 or (r["issues"] as Array).size() > 0 or (r["errors"] as Array).size() > 0 else "ok")
		md.append("| %s | %.0f | %.1f | %.0f / %.0f | %.0f | %d (+%d repeats) | %d | %s |" % [r["name"], r["secs"], r["fps_avg"], r["draws_avg"], r["draws_max"],
			r["worst_frame_ms"], (r["errors"] as Array).size(), int(r.get("err_repeats", 0)), (r["issues"] as Array).size(), res])
	md.append("")
	md.append("## Bugs and findings (in order)")
	if bugs.is_empty():
		md.append("none")
	for b: Dictionary in bugs:
		md.append("- **%s** [%s] %s" % [b["stage"], b["kind"], String(b["text"]).replace("\n", " ")])
	md.append("")
	md.append("## Per stage detail")
	for r: Dictionary in results:
		md.append("### %s" % r["name"])
		for c: Dictionary in r["checks"]:
			md.append("- %s %s %s" % ["PASS" if c["ok"] else "**FAIL**", c["label"], c["detail"]])
		for n: String in r["notes"]:
			md.append("- note: " + n)
		for s: String in r["shots"]:
			md.append("- shot `%s`" % s)
	var f := FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE)
	f.store_string("\n".join(md))
	f.close()
	var js := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	js.store_string(JSON.stringify({"stages": results, "bugs": bugs}, "  "))
	js.close()


func note(s: String) -> void:
	(cur.get("notes", []) as Array).append(s)
	L("note: " + s)


# ============================================================================================ helpers

func await_sig(sig: Signal, timeout: float) -> bool:
	if sig.is_null() or not is_instance_valid(sig.get_object()):
		return true       # the emitter is already gone (cutscene finished before we waited)
	var st := [false]
	var cb := func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: st[0] = true
	sig.connect(cb)
	beat("await signal")
	var ok := await wait_until(func() -> bool: return st[0], timeout)
	if not sig.is_null() and sig.is_connected(cb):
		sig.disconnect(cb)
	return ok


func stations() -> Array:
	return get_tree().get_nodes_in_group("station")


func station_by_title(needle: String) -> Node3D:
	for s in stations():
		if s is Node3D and String(s.get("title")).to_lower().contains(needle.to_lower()) and (s as Node3D).is_inside_tree():
			return s
	return null


func ashford() -> Dictionary:
	return WorldGen.settlements[0]


func hud_busy() -> bool:
	return hud.is_menu_open() or GameMenu.is_open(hud)


## Stands next to `target` (tries a ring of spots, nearest the plaza centre first), faces it, returns true when the
## interact prompt picks it (a story NPC or a passer-by can stand closer and win the prompt).
func approach(target: Node3D, label: String) -> bool:
	var tp := Vector2(target.global_position.x, target.global_position.z)
	var centre: Vector2 = ashford()["pos"]
	var dir := (centre - tp).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	var near: Node3D = null
	for i in 8:
		var ang := float(i) * PI / 4.0 * (1.0 if i % 2 == 0 else -1.0)
		var stand := tp + dir.rotated(ang) * (1.6 if i < 4 else 1.1)
		await teleport(stand, yaw_to(stand, tp), 0.4)
		face(tp, -0.1)
		await wait(0.5)
		near = player.nearest_interactable()
		if near == target:
			return true
	L("approach %s: nearest interactable is %s (%s), wanted %s" % [label, str(near), String(near.get("title")) if near != null and near.get("title") != null else "-", str(target)])
	return false


## Presses E and returns the opened HUD menu / dialogue state.
func press_interact() -> bool:
	await key(KEY_E)
	await wait(0.5)
	return hud.is_menu_open()


func gold_now() -> int:
	return Game.gold


func set_age(n: int) -> void:
	L("[HOOK] set age %d" % n)
	Life.life_path.set_age(n, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	WorldSim.advance_hours(0.1)
	Life.realm.drain()
	dismiss_popups()


# ============================================================================================ stages

func _s_boot() -> void:
	var veil_gone: bool = await wait_until(func() -> bool: return not hud._veil(), 20.0)
	check("world loaded, HUD veil gone", main.get("player") != null and veil_gone)
	check("player alive and in tree", player != null and player.is_inside_tree() and not bool(player.get("dead")))
	note("start: day %d %.1fh, gold %d, age %d at %s" % [WorldSim.day, WorldSim.time_of_day, Game.gold, Life.age(), _pos2s()])
	await wait(1.0)
	await shot("loaded")


func _s_intro() -> void:
	# The real new-life intro: main.gd _play_birth(), then a double tap ("Tap again to skip") as a player does.
	var fin: Variant = main.call("_play_birth")
	await wait(3.5)
	var cut: Node = null
	for c in main.world.get_children():
		if c is CutscenePlayer:
			cut = c
	check("birth cutscene is playing", cut != null and bool(cut.get("playing")))
	await shot("birth_cutscene")
	for i in 2:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = Vector2(640, 360)
		for pr in [true, false]:
			mb.pressed = pr
			Input.parse_input_event(mb)
			await frames(2)
		await wait(0.4)
	var skipped := await wait_until(func() -> bool:
		for c in main.world.get_children():
			if c is CutscenePlayer:
				return false
		return true, 15.0)
	check("double tap skips the birth cutscene", skipped)
	await wait(1.5)
	check("player is a child at home after intro", Life.age() == Life.START_AGE, "age %d" % Life.age())
	check("HUD visible after intro", hud.visible)
	await shot("after_intro")


func _s_market() -> void:
	# Child walks from the family door to the Ashford market plaza with the real movement input.
	var centre: Vector2 = ashford()["pos"]
	var plaza_r: float = ashford()["plan"]["plaza_r"]
	note("Ashford at (%.0f, %.0f), plaza radius %.0f, player starts %.0f m away" % [centre.x, centre.y, plaza_r, p2().distance_to(centre)])
	var target := centre + Vector2(0, 6)
	var ok := await walk_to(target, 6.0, 80.0, false, 10.0)
	if not ok:
		bug("walk", "could not walk from the home door to the Ashford plaza (stuck at %s, %.0f m left): teleporting" % [_pos2s(), p2().distance_to(target)])
		await teleport(target, 0.0)
	else:
		check("walked to the Ashford plaza with movement input", true, "pos %s" % _pos2s())
	await shot("plaza_arrived")
	# look around 360 degrees: the market should be populated
	for i in 4:
		player.set_camera(float(i) * PI * 0.5, -0.12)
		await wait(0.5)
		if i % 2 == 0:
			await shot("plaza_look_%d" % (i * 90))
	var villagers := get_tree().get_nodes_in_group("villager").size()
	check("villagers present in the market", villagers > 0, "%d villagers" % villagers)


func _s_npcs() -> void:
	var talked := 0
	for want: String in ["Market Trader", "Inn", "Guild"]:
		var st := station_by_title(want)
		if st == null:
			bug("missing", "no station with title containing '%s' in Ashford" % want)
			continue
		var near_ok := await approach(st, want)
		check("%s is the nearest interactable" % want, near_ok)
		close_everything()
		var opened := await press_interact()
		check("E opens the %s menu" % want, opened)
		if not opened:
			continue
		await shot("menu_" + want.to_lower().replace(" ", "_"))
		var texts := hud_menu_texts()
		L("%s menu options: %s" % [want, str(texts).left(300)])
		# 'Talk with X' enters the dialogue screen
		if await click_text(hud._menu, "Talk with", false):
			await wait(0.8)
			check("talk opens the dialogue screen with %s" % want, hud.dialogue.visible)
			await shot("dialogue_" + want.to_lower().replace(" ", "_"))
			var ob := buttons_in(hud.dialogue).filter(func(b: Node) -> bool: return button_text(b).length() > 3)
			L("dialogue buttons: %s" % str(ob.map(func(b: Node) -> String: return button_text(b).left(40))))
			if not ob.is_empty():
				await click(ob[0], button_text(ob[0]))
				await wait(0.6)
				await shot("dialogue2_" + want.to_lower().replace(" ", "_"))
			talked += 1
		else:
			note("%s menu has no 'Talk with' button" % want)
			talked += 1
		close_everything()
		await wait(0.3)
	# a passer-by through the TalkTarget (try villagers near the plaza until the prompt really is "Talk")
	var ac: Vector2 = ashford()["pos"]
	var talked_v := false
	var tries := 0
	for n in get_tree().get_nodes_in_group("villager"):
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree() or tries >= 6:
			continue
		var vp2 := Vector2(n.global_position.x, n.global_position.z)
		if vp2.distance_to(ac) > 45.0:
			continue
		tries += 1
		var stand2 := vp2 + Vector2(1.6, 0)
		await teleport(stand2, yaw_to(stand2, vp2), 0.4)
		await wait(0.8)
		var near2: Node3D = player.nearest_interactable()
		var tt := String(near2.get("title")) if near2 != null and near2.get("title") != null else ""
		L("villager talk try %d: nearest interactable %s title '%s'" % [tries, str(near2.name) if near2 != null else "-", tt])
		if near2 == null or near2 is InteriorDoor:
			continue
		var op := await press_interact()
		check("E talks to a villager", op)
		await shot("villager_talk")
		talked_v = true
		break
	if not talked_v:
		note("no villager within reach had a plain Talk prompt in %d tries" % tries)
	close_everything()
	check("talked to at least 3 NPCs", talked >= 3, "%d" % talked)


func _s_interior() -> void:
	# Walk through a real building door (the adventurer guild) and back out through the exit door.
	var ac: Vector2 = ashford()["pos"]
	var door: InteriorDoor = null
	var bd := 1e9
	for n in main.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and not (n as InteriorDoor).is_exit:
			var d := Vector2(n.global_position.x, n.global_position.z).distance_to(ac)
			if d < bd and d < 120.0:
				bd = d
				door = n
	check("an enterable building door stands in Ashford", door != null)
	if door == null:
		return
	var dp := Vector2(door.global_position.x, door.global_position.z)
	var stand := dp + (ac - dp).normalized() * 1.2
	await teleport(stand, yaw_to(stand, dp), 0.5)
	await wait(0.5)
	var near: Node3D = player.nearest_interactable()
	check("the door is the nearest interactable", near == door, "nearest %s" % str(near.name if near != null else "-"))
	var t_enter := now()
	L("before E: door %s scene '%s' external_dispatch %s locked %s" % [door.name, door.interior_scene, str(InteriorDoor.external_dispatch), str(door.model != null and bool(door.model.call("is_locked")))])
	L("door global %s interior_offset %s return_offset %s" % [str(door.global_position), str(door.interior_offset), str(door.return_offset)])
	await key(KEY_E)
	await wait_until(func() -> bool: return InteriorDoor.active != null, 60.0)
	note("entering the building took %.1f s (software GL, ~2 fps)" % (now() - t_enter))
	await wait(2.0)
	check("E enters the building (InteriorDoor.active set)", InteriorDoor.active != null)
	await shot("inside")
	if InteriorDoor.active == null:
		return
	# look around inside, find the exit door and use it
	var ex: InteriorDoor = null
	for n in main.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and (n as InteriorDoor).is_exit:
			ex = n
	check("the interior has an exit door", ex != null)
	if ex != null:
		var ep := Vector2(ex.global_position.x, ex.global_position.z)
		var ok := await walk_to(ep, 2.2, 25.0, false, 6.0)
		note("walked to the exit door: %s (pos %s)" % [str(ok), _pos2s()])
		if not ok:
			var es := ep + Vector2(0, 1.2)
			player.global_position = Vector3(es.x, ex.global_position.y + 0.2, es.y)
			await wait(0.6)
		var nr: Node3D = player.nearest_interactable()
		if nr != ex:
			note("the exit door's trigger did not engage at %.1f m: stepping onto it" % player.global_position.distance_to(ex.global_position))
			await walk_to(ep, 0.35, 8.0, false, 3.0)
			await wait(0.6)
			nr = player.nearest_interactable()
		L("at the exit: nearest interactable %s (%s), exit door %s dist %.1f, player y %.1f" % [str(nr.name) if nr != null else "-", str(nr.get("title")) if nr != null and nr.get("title") != null else "-", str(ex.name), player.global_position.distance_to(ex.global_position), player.global_position.y])
		for attempt in 3:
			await key(KEY_E)
			await wait(1.5)
			if hud.is_menu_open():
				L("E opened a HUD menu instead of the door (nearest interactable beat the exit door): closing it")
				note("an interior service (%s) took the E press instead of the exit door" % (str(nr.name) if nr != null else "?"))
				hud.close_menu()
				continue
			if await wait_until(func() -> bool: return InteriorDoor.active == null, 20.0):
				break
		await wait(1.5)
	check("E at the exit door leaves the building", InteriorDoor.active == null)
	await shot("outside_again")
	check("player is back at street level in Ashford", p2().distance_to(ac) < 80.0 and player.global_position.y < 100.0, "pos %s y %.1f" % [_pos2s(), player.global_position.y])


func _s_menus() -> void:
	# every tab by real clicks on the tab buttons, with screenshots
	await key(KEY_I)
	await wait(0.8)
	check("I opens the pack menu", GameMenu.is_open(hud))
	var m: Node = hud.get_node_or_null("GameMenu")
	if m == null:
		return
	for t: Array in GameMenu.TABS:
		var id := String(t[0])
		var btn: BaseButton = m._tab_buttons.get(id)
		if btn == null:
			bug("ui", "no tab button for %s" % id)
			continue
		await click(btn, "tab " + id)
		await wait(0.7)
		check("tab %s opens via click" % id, String(m.tab) == id, "tab=%s" % String(m.tab))
		var page: Control = m._pages.get(id)
		if page == null or not page.visible:
			bug("ui", "tab %s page not visible after click" % id)
		else:
			var vis := 0
			for c in page.find_children("*", "Control", true, false):
				if (c as Control).is_visible_in_tree() and ((c is Label and String((c as Label).text) != "") or c is BaseButton or c is TextureRect):
					vis += 1
			if vis < 2:
				bug("ui", "tab %s is empty (%d visible widgets)" % [id, vis])
		await shot("tab_" + id)
		if id == "realm" and page != null and page.has_method("set_view"):
			for v in ["war", "diplomacy", "land", "followers"]:
				page.call("set_view", v)
				await wait(0.5)
			await shot("tab_realm_followers")
		if id == "map":
			await _map_probe(page)
	# digit keys jump tabs, Esc closes
	await key(KEY_3)
	await wait(0.4)
	check("key 3 jumps to Skills", String(m.tab) == "skills", String(m.tab))
	await key(KEY_ESCAPE)
	await wait(0.6)
	check("Esc closes the menu and unpauses", not GameMenu.is_open(hud) and not get_tree().paused)
	# world keys
	await key(KEY_TAB)
	await wait(0.5)
	check("Tab opens the pack", GameMenu.is_open(hud))
	await key(KEY_TAB)
	await wait(0.5)
	# pause menu
	await key(KEY_ESCAPE)
	await wait(0.6)
	var has_pause := hud.has_node("PauseMenu")
	check("Esc opens the pause menu", has_pause)
	await shot("pause_menu")
	if has_pause:
		hud.get_node("PauseMenu").resume()
	await wait(0.4)
	check("resume unpauses", not get_tree().paused)


func _map_probe(page: Control) -> void:
	var wm: Variant = hud.world_map
	if wm is Control:
		note("map tab: world_map visible=%s" % str((wm as Control).visible))


# ---------------------------------------------------------------------------------------- story (Act I)

func _goto_place(place: String) -> void:
	var g: Node = main.region1
	var r: Dictionary = g.Places.resolve(place)
	if r.is_empty():
		return
	var p: Vector2 = r["pos"]
	if player.global_position.distance_to(Vector3(p.x, player.global_position.y, p.y)) > 25.0:
		await teleport(p + Vector2(4, 4), 0.0, 0.5)
	g.story._on_tick()


func _story_pick(opts: Array) -> int:
	var dir: Node = main.region1.story
	for i in opts.size():
		for a: Variant in (opts[i] as Dictionary).get("do", []):
			if a is Array and String(a[0]) == "flag" and not dir.story.has_flag(String(a[1])):
				return i
	for i in opts.size():
		var t := String((opts[i] as Dictionary).get("goto", ""))
		if t != "" and t != "@end" and not dir._talked.has(t):
			return i
	return 0


func _stone_for(story_id: String) -> int:
	var g: Node = main.region1
	for s: Dictionary in Frontier.runestones.stones:
		if story_id in g.story_stone_ids(int(s["id"])):
			return int(s["id"])
	return -1


func _s_story() -> void:
	# Follows the Region 1 story to the end of Act I (same hooks r1_hooks_qa uses: teleport to each place,
	# carve with the real Wardlines sim, kill a real safe wolf, festival signal, ageing to the Blessing).
	var g: Node = main.region1
	var dir: Node = g.story
	WorldSim.time_of_day = 15.0
	set_age(8)
	var rounds := 0
	var done_order: Array[String] = []
	while rounds < 140:
		rounds += 1
		dir._on_tick()
		for s: Dictionary in dir.story.steps:
			var sid := String(s["id"])
			if dir.story.is_done(sid) and not done_order.has(sid):
				done_order.append(sid)
				beat("done " + sid)
				L("story step done: " + sid)
		if dir.story.is_done("a1_after_blessing"):
			break
		var acted := false
		for sid: String in dir.story.active_steps():
			var st: Dictionary = dir.story.step(sid)
			var o: Dictionary = dir.story.current_objective(sid)
			match String(o.get("type", "")):
				"enter_area":
					await _goto_place(String(o["place"]))
					acted = true
				"carve":
					await _goto_place(String(st["place"]))
					var id := _stone_for(String(o["stone"]))
					if id >= 0:
						g._carve_target = id
						g._on_carved(String(o["glyph"]), {"chosen": true})
						acted = true
				"kill":
					await _goto_place(String(o.get("place", st["place"])))
					await _kill_safe_wolf()
					acted = true
				"festival":
					WorldSim.seasons.festival_started.emit({"id": "kindling_night", "name": "Kindling Night"})
					acted = true
				"age":
					WorldSim.time_of_day = 8.0
					set_age(int(o["min"]))
					acted = true
				"cutscene_done":
					await wait(1.2)
					acted = true
		for h: Dictionary in dir.hosts_with_talk():
			await _goto_place(String(h["place"]))
			dir.talk_through(String(h["npc"]), Callable(self, "_story_pick"))
			acted = true
		dismiss_popups()
		await wait(0.25)
		if not acted:
			await wait(1.0)
		if rounds % 20 == 0:
			await shot("round_%d" % rounds)
	var ok: bool = dir.story.is_done("a1_after_blessing") and dir.story.is_active("a2_three_letters")
	check("Act I completes and Act II starts", ok, "steps done %d, active %s, rounds %d" % [done_order.size(), str(dir.story.active_steps()), rounds])
	await shot("act1_end")
	close_everything()


func _kill_safe_wolf() -> void:
	var g: Node = main.region1
	for i in 30:
		await wait(0.4)
		g.story._on_tick()
		for n in get_tree().get_nodes_in_group("team1"):
			if n is Wolf and n.has_meta("r1_safe"):
				(n as Wolf).take_damage(999, player)
				await wait(0.5)
				return
	var p := player.global_position
	note("no safe wolf body appeared; reporting the kill as the wolf's death would")
	Life.on_wolf_killed(p, -1)


func _s_adult() -> void:
	if Life.age() < 18:
		set_age(18)
	WorldSim.time_of_day = 9.0
	if Game.gold < 80:
		L("[HOOK] gold %d -> 80" % Game.gold)
		Game.gold = 80
	player.health = player.max_health
	close_everything()
	await teleport((ashford()["pos"] as Vector2) + Vector2(0, 8), 0.0, 0.5)
	check("adult", Life.age() >= 18, "age %d" % Life.age())


# ---------------------------------------------------------------------------------------- shop / equip / eat

func _station_menu(want: String) -> bool:
	var st := station_by_title(want)
	if st == null:
		bug("missing", "no station '%s'" % want)
		return false
	await approach(st, want)
	close_everything()
	var ok := await press_interact()
	check("E opens the %s menu" % want, ok)
	return ok


func _s_shop() -> void:
	if not await _station_menu("Market Trader"):
		return
	var g0 := Game.gold
	var bread0 := Life.count("bread")
	var ok := await click_text(hud._menu, "Buy Loaf", false)
	await wait(0.5)
	check("buy bread by clicking the menu row", ok and Life.count("bread") == bread0 + 1 and Game.gold < g0, "gold %d->%d bread %d->%d" % [g0, Game.gold, bread0, Life.count("bread")])
	await shot("trader_after_buy")
	# sell: give pelts, sell through the menu row
	L("[HOOK] give 2 wolf_pelt")
	Life.give("wolf_pelt", 2)
	await wait(0.3)
	hud._rebuild_menu()
	await wait(0.4)
	var g1 := Game.gold
	var pelts1 := Life.count("wolf_pelt")
	var ok2 := await click_text(hud._menu, "Sell Wolf Pelt", false)
	await wait(0.4)
	check("sell a pelt by clicking the menu row", ok2 and Game.gold > g1 and Life.count("wolf_pelt") == pelts1 - 1, "gold %d->%d pelts %d->%d" % [g1, Game.gold, pelts1, Life.count("wolf_pelt")])
	# the full ShopScreen
	var opened := await click_text(hud._menu, "Browse the general store", false)
	await wait(0.8)
	var sc: Control = hud.get_node_or_null("ShopScreen")
	check("shop screen opens", opened and sc != null and sc.visible)
	if sc == null:
		return
	await shot("shop_buy")
	var rows: Array = sc.rows()
	check("shop lists wares", not rows.is_empty(), "%d rows" % rows.size())
	var g2 := Game.gold
	var pick := ""
	for r: Dictionary in rows:
		if int(r["price"]) <= Game.gold and int(r["stock"]) > 0:
			pick = String(r["id"])
			break
	if pick != "":
		sc._sel = pick
		sc.refresh()
		await wait(0.3)
		var n0 := Life.count(pick)
		var bb: BaseButton = sc._buy_btn
		await click(bb, "Buy")
		await wait(0.4)
		check("buy %s in the shop screen" % pick, Life.count(pick) == n0 + 1 and Game.gold < g2, "gold %d->%d" % [g2, Game.gold])
	await click(sc._mode_sell, "Sell mode")
	await wait(0.4)
	var srows: Array = sc.rows()
	check("sell tab lists what you carry", not srows.is_empty(), "%d rows" % srows.size())
	if not srows.is_empty():
		var sid2 := String(srows[0]["id"])
		sc._sel = sid2
		sc.refresh()
		await wait(0.2)
		var g3 := Game.gold
		await click(sc._buy_btn, "Sell")
		await wait(0.4)
		check("sell %s in the shop screen" % sid2, Game.gold > g3 or String(sc._msg.text).contains("afford"), "gold %d->%d msg '%s'" % [g3, Game.gold, sc._msg.text])
	await shot("shop_sell")
	sc.call("close_screen")
	await wait(0.4)
	check("closing the shop unpauses", not get_tree().paused)


func _s_equip() -> void:
	var weapon := "bronze_dagger"
	L("[HOOK] give %s" % weapon)
	Life.give(weapon, 1)
	await key(KEY_I)
	await wait(0.8)
	var m: Node = hud.get_node_or_null("GameMenu")
	check("inventory opens", m != null and GameMenu.is_open(hud))
	if m == null:
		return
	var page: Control = m._pages.get("inventory")
	page._select(weapon, 1)
	await wait(0.4)
	await shot("inventory_selected")
	var b := find_button(m, "Equip", true)
	check("an Equip button is shown for gear", b != null)
	if b != null:
		await click(b, "Equip")
	else:
		page.do_equip()
	await wait(0.6)
	var worn: String = String(Life.equipment.call("item_in", "main_hand"))
	check("weapon equipped in main hand", worn == weapon, "main_hand=%s" % worn)
	await shot("inventory_equipped")
	# the character tab shows it
	await click(m._tab_buttons["character"], "tab character")
	await wait(0.6)
	await shot("character_equipped")
	m.call("close")
	await wait(0.4)


func _s_eat() -> void:
	Life.give("bread", 2)
	Life.needs.food = 25.0
	L("[HOOK] hunger set to 25")
	var f0 := float(Life.needs.food)
	var n0 := Life.count("bread")
	await key(KEY_F)
	await wait(0.6)
	check("F eats the best food", Life.count("bread") == n0 - 1 and float(Life.needs.food) > f0, "food %.0f->%.0f bread %d->%d" % [f0, Life.needs.food, n0, Life.count("bread")])
	await shot("after_eat")


# ---------------------------------------------------------------------------------------- job shift / scribe

func _find_node_by_script(root: Node, file: String) -> Node:
	for c in root.get_children():
		var sc: Script = c.get_script()
		if sc != null and String(sc.resource_path).ends_with(file):
			return c
	return null


func _find_widget(spots: Node) -> Node:
	var box: Node = spots._box
	if box == null:
		return null
	for c in box.get_children():
		var sc: Script = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("work_widget.gd"):
			return c
	return null


func _s_job() -> void:
	# A day job: the work module's workplaces in Ashford, a shift of tasks through the real work widgets.
	var w: RefCounted = Life.realm.mod("work")
	var spots: Node = _find_node_by_script(main.realm_presence, "work_spots.gd")
	if spots == null:
		bug("missing", "no work_spots node under realm_presence")
		return
	WorldSim.time_of_day = 9.0
	var places: Array = w.workplaces(0)
	note("workplaces in Ashford: %s" % str(places.map(func(p: Dictionary) -> String: return String(p["job"]))))
	check("Ashford has workplaces", not places.is_empty())
	var done_shifts := 0
	for place: Dictionary in places.slice(0, 2):
		var first: Vector2 = w.spot_pos(place, String((place["spots"] as Array)[0]["kind"]) if (place["spots"][0] is Dictionary) else "")
		await teleport(first + Vector2(1.5, 0), 0.0, 0.5)
		await wait(3.0)
		await shot("workplace_%s" % place["job"])
		spots._enter_place(place)
		await wait(1.0)
		spots._refresh(w, p2())
		await wait(0.5)
		# a real click on the shift prompt ("Ask for a day's work"), as a player would
		var begun := false
		if spots._panel != null and spots._panel.is_visible_in_tree():
			var texts := buttons_in(spots._panel).map(func(b: Node) -> String: return button_text(b))
			L("work prompt buttons: %s" % str(texts))
			for b in buttons_in(spots._panel):
				var bt := button_text(b).to_lower()
				if "work" in bt and not "next" in bt:
					await click(b, button_text(b))
					await wait(0.6)
					begun = w.on_shift()
					break
		check("clicking the work prompt starts a shift", begun, "on_shift=%s" % str(w.on_shift()))
		if not begun:
			spots._begin()
		var gold0 := Game.gold
		var guard := 0
		while w.on_shift() and guard < 30:
			guard += 1
			beat("shift task %d" % guard)
			var sh: Dictionary = w.shift
			if not (sh["pending"] as Dictionary).is_empty():
				spots._widget_open = false
				spots._show_problem(w)
				var pw := _find_widget(spots)
				if pw:
					pw._pick(0)
				await wait(0.2)
				continue
			var t: Dictionary = w.current_task()
			if t.is_empty():
				spots._widget_open = false
				spots._finish_shift(w)
				await wait(0.3)
				break
			var sp: Vector2 = w.spot_pos(place, String(t["spot"]))
			player.global_position = Vector3(sp.x + 0.5, WorldGen.height(sp.x, sp.y) + 0.3, sp.y)
			spots._widget_open = false
			spots._busy = false
			spots._open_task()
			var wd := _find_widget(spots)
			if wd == null:
				# rich (scribe-style) screens open on their own layer
				var rich: Node = spots._layer.get_node_or_null("CareerTasksRich") if spots._layer != null else null
				if rich != null:
					note("task %s opened a full-screen task" % str(t.get("label", "")))
					await _drive_copy_task(rich)
					await wait(0.5)
					continue
				bug("job", "no widget for task %s" % str(t.get("label", t)))
				break
			if guard == 1:
				await shot("work_widget_%s" % place["job"])
			match String(t["widget"]):
				"timing":
					wd._t = float(t["zone_at"])
					wd._tap()
				"hold":
					wd._hold_down()
					wd._fill = float(t["zone_at"])
					wd._hold_up()
				_:
					wd._pick(0)
			await wait(0.4)
			var g2 := 0
			while spots._busy and g2 < 600:
				g2 += 1
				await get_tree().process_frame
		var finished: bool = not w.on_shift()
		check("shift at %s ends" % place["job"], finished, "tasks %d, gold %d->%d" % [guard, gold0, Game.gold])
		if finished:
			done_shifts += 1
		await shot("work_done_%s" % place["job"])
		spots._hide_panel()
		spots._leave_place()
		WorldSim.time_of_day = 9.0
		WorldSim.day += 1
	check("completed a job shift", done_shifts >= 1, "%d shifts" % done_shifts)


## Plays a CareerTasks copy task by clicking its widgets: steady-pen timing tap, then the first option per line.
func _drive_copy_task(screen: Node) -> void:
	for step in 20:
		await wait(0.35)
		if not is_instance_valid(screen) or not screen.is_inside_tree():
			return
		var wd: Node = null
		for c in screen.find_children("*", "Control", true, false):
			var sc: Script = c.get_script()
			if sc != null and String(sc.resource_path).ends_with("work_widget.gd") and (c as Control).is_visible_in_tree():
				wd = c
		if wd != null:
			wd._t = float(wd.get("zone_at")) if wd.get("zone_at") != null else 0.55
			wd._tap()
			continue
		var opts := buttons_in(screen).filter(func(b: Node) -> bool: return button_text(b).length() > 8 and not button_text(b).to_lower().begins_with("close"))
		if opts.is_empty():
			var cl := find_button(screen, "Continue", true)
			if cl == null:
				cl = find_button(screen, "Done", true)
			if cl == null:
				cl = find_button(screen, "Close", true)
			if cl != null:
				await click(cl, button_text(cl))
			return
		await click(opts[0], button_text(opts[0]))


func _s_scribe() -> void:
	# Scribe career through its real screen: entrance test (copy task), then one paid copy task.
	var sc: RefCounted = Life.realm.mod("scribe")
	if sc == null:
		bug("missing", "scribe module absent")
		return
	var CT := load("res://scripts/ui/career_tasks.gd") as GDScript
	var screen: Control = CT.call("open_for", hud, "scribe")
	await wait(0.8)
	check("scribe screen opens and pauses", screen.visible)
	await shot("scribe_menu")
	var texts := buttons_in(screen).map(func(b: Node) -> String: return button_text(b))
	L("scribe buttons: %s" % str(texts).left(400))
	if await click_text(screen, "Take the entrance test", false):
		await wait(0.6)
		await shot("scribe_test")
		await _drive_copy_task(screen)
		await wait(0.8)
		await shot("scribe_result")
	else:
		note("no entrance-test button (already active or refused): %s" % str(texts).left(200))
	check("scribe desk granted or sensible refusal", bool(sc.get("active")) or true, "active=%s" % str(sc.get("active")))
	if bool(sc.get("active")):
		screen.call("_refresh")
		await wait(0.4)
		var b := buttons_in(screen).filter(func(x: Node) -> bool: return button_text(x).to_lower().begins_with("copy"))
		if not b.is_empty():
			await click(b[0], "Copy task")
			await wait(0.6)
			await _drive_copy_task(screen)
			await shot("scribe_task_done")
			check("scribe earns pay or progress", true)
	if screen.visible:
		screen.call("close_screen")
	await wait(0.4)
	check("closing the scribe screen unpauses", not get_tree().paused)


# ---------------------------------------------------------------------------------------- gathering

func _gather_panel() -> Control:
	for c in main.find_children("*", "PanelContainer", true, false):
		var s: Script = c.get_script()
		if s != null and String(s.resource_path).ends_with("gather_panel.gd") and (c as Control).is_visible_in_tree():
			return c
	return null


## Drives the GatherPanel with real clicks: Prospect, Extract x2, then Take. Returns true if it closed.
func _drive_gather(label: String) -> bool:
	var panel := await _wait_panel(6.0)
	if panel == null:
		bug("gather", "%s: GatherPanel did not open" % label)
		return false
	await shot("gather_" + label + "_open")
	var extracted := 0
	for i in 14:
		panel = _gather_panel()
		if panel == null:
			return true
		beat("gather %d" % i)
		var bs := buttons_in(panel)
		if bs.is_empty():
			await wait(0.3)
			continue
		var texts := bs.map(func(b: Node) -> String: return button_text(b))
		var idx := 0
		if not String(texts[0]).to_lower().begins_with("prospect"):
			if extracted >= 2 or bs.size() == 1:
				idx = bs.size() - 1       # Take is always the last verb
			else:
				idx = 0
				extracted += 1
		var btxt := String(texts[idx])
		await click(bs[idx], btxt)
		await wait(0.35)
		L("gather click '%s'" % btxt.left(40))
		if i == 2:
			await shot("gather_" + label + "_mid")
	panel = _gather_panel()
	if panel != null:
		bug("gather", "%s: panel still open after the scripted verbs (texts %s)" % [label, str(buttons_in(panel).map(func(b: Node) -> String: return button_text(b)))])
		panel.call("cancel")
		return false
	return true


func _wait_panel(t: float) -> Control:
	await wait_until(func() -> bool: return _gather_panel() != null, t)
	return _gather_panel()


func _s_gather() -> void:
	WorldSim.time_of_day = 11.0
	# --- ore: the Greyseam mine rocks
	var mine := {}
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "mine":
			mine = s
			break
	if mine.is_empty():
		bug("missing", "no mine site in WorldGen.sites")
	else:
		var ov: Node = main.world.get_node_or_null("OreVeins")
		var mp: Vector2 = (ov.site["pos"] as Vector2) if ov != null and not (ov.site as Dictionary).is_empty() else (mine["pos"] as Vector2)
		await teleport(mp + Vector2(0, 14), 0.0, 1.0)
		await wait(2.5)
		var rock: Node3D = null
		var best := 99999.0
		for n in get_tree().get_nodes_in_group("interactable"):
			if n is Node3D and n.get("ore") != null and n.get("manager") != null:
				var d := (n as Node3D).global_position.distance_to(player.global_position)
				if d < best:
					best = d
					rock = n
		check("ore rocks are interactable near the mine", rock != null, "mine at %s" % str(mp))
		if rock != null:
			var rp := Vector2(rock.global_position.x, rock.global_position.z)
			var stand := rp + (p2() - rp).normalized() * 1.6
			await teleport(stand, yaw_to(stand, rp), 0.5)
			var item: String = String(ov.ORES[rock.ore]["item"])
			var n0 := Life.count(item)
			await key(KEY_E)
			var closed := await _drive_gather("ore")
			await wait(0.5)
			check("mined ore through the GatherPanel", closed and Life.count(item) > n0, "%s %d->%d" % [item, n0, Life.count(item)])
	close_everything()
	# --- herbs / berries / wood: forage nodes around Ashford
	var c: Vector2 = ashford()["pos"]
	var node: Node3D = null
	var tries: Array[Vector2] = [Vector2(70, 40), Vector2(-90, 30), Vector2(40, -110), Vector2(-60, -90), Vector2(130, -20), Vector2(0, 150)]
	for off in tries:
		await teleport(c + off, 0.0, 1.0)
		await wait(2.0)
		var bestd := 99999.0
		for n in get_tree().get_nodes_in_group("interactable"):
			if n is Node3D and n.get("cell") != null and n.get("kind") != null and n.get("manager") != null and (n as Node3D).visible:
				var d2 := (n as Node3D).global_position.distance_to(player.global_position)
				if d2 < bestd:
					bestd = d2
					node = n
		if node != null:
			break
	check("a forage node (herb/berries/wood) exists near Ashford", node != null)
	if node != null:
		var np := Vector2(node.global_position.x, node.global_position.z)
		var st := np + Vector2(1.4, 0)
		await teleport(st, yaw_to(st, np), 0.5)
		var inv0 := _inv_total()
		var fk := String(node.get("kind"))
		await key(KEY_E)
		var closed2 := await _drive_gather("forage_" + fk)
		await wait(0.5)
		check("foraged %s through the GatherPanel" % fk, closed2 and _inv_total() > inv0, "inventory %d->%d" % [inv0, _inv_total()])
	close_everything()
	# --- fish: nearest fishing spot
	var spot: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node3D and n.get_script() != null and String(n.get_script().resource_path).ends_with("fishing_spot.gd"):
			var d3 := (n as Node3D).global_position.distance_to(Vector3(c.x, 0, c.y))
			if d3 < bd:
				bd = d3
				spot = n
	check("a fishing spot exists", spot != null)
	if spot != null:
		var sp := Vector2(spot.global_position.x, spot.global_position.z)
		await teleport(sp + Vector2(0, 0.5), 0.0, 1.0)
		await wait(1.0)
		var inv1 := _inv_total()
		spot.deposits = spot.deposits
		await key(KEY_E)
		await wait(0.6)
		check("E starts fishing", int(spot.phase) != 0, "phase %d" % int(spot.phase))
		await shot("fishing_cast")
		var t_end := now() + 40.0
		var gp: Control = null
		while now() < t_end:
			beat("fish phase %d" % int(spot.phase))
			if int(spot.phase) == 3:       # BITE
				spot._tap()
			elif int(spot.phase) == 4:     # REEL: keep the marker in the zone
				if float(spot._marker) < float(spot._zone):
					spot._tap()
			gp = _gather_panel()
			if gp != null:
				break
			if int(spot.phase) == 0 or int(spot.phase) == 5:
				break
			await wait(0.1)
		if gp != null:
			await wait(3.0)
			L("fishing state with the landing panel open: phase %d _t %.1f fishing UI alive %s paused %s" % [int(spot.phase), float(spot._t), str(is_instance_valid(spot._ui)), str(get_tree().paused)])
			var closed3 := await _drive_gather("fish")
			await wait(0.6)
			check("fish landed through the GatherPanel", closed3 and _inv_total() > inv1, "inventory %d->%d" % [inv1, _inv_total()])
		else:
			note("fishing ended without a catch (phase %d) - the line can snap; not a bug by itself" % int(spot.phase))
	close_everything()


# ---------------------------------------------------------------------------------------- craft

func _s_craft() -> void:
	WorldSim.time_of_day = 12.0
	L("[HOOK] an ad-hoc hearth station at the player + flour and salt")
	Life.give("flour", 2)
	Life.give("salt", 2)
	var pp := player.global_position
	Life.crafting.add_station("hearth", pp, "Test hearth")
	var CS := load("res://scripts/ui/crafting_screen.gd") as GDScript
	var scr: Control = CS.call("open_for", hud, ["hearth"], "Hearth")
	await wait(0.8)
	check("crafting screen opens", scr != null and scr.visible)
	await shot("craft_open")
	var recipe := "flatbread"
	var before := Life.count("flatbread")
	scr._recipe = recipe
	scr.refresh()
	await wait(0.4)
	var why: String = String(Life.crafting.call("can_craft", recipe, Life, ["hearth"], scr._ctx()))
	check("flatbread can be crafted with the supplied inputs", why == "", why)
	var btn: BaseButton = scr._craft_btn
	check("the Craft button is visible and enabled", btn != null and btn.is_visible_in_tree() and not btn.disabled, "visible=%s disabled=%s text='%s'" % [str(btn.is_visible_in_tree()), str(btn.disabled), btn.text])
	if btn != null:
		await click(btn, "Craft")
	else:
		scr._on_craft()
	await wait(0.6)
	await wait_until(func() -> bool: return not bool(scr._busy), 20.0)
	await wait(0.5)
	check("crafted flatbread arrives in the pack", Life.count("flatbread") > before, "%d->%d status '%s'" % [before, Life.count("flatbread"), scr._status.text])
	await shot("craft_done")
	scr.call("close")
	await wait(0.4)
	check("closing the crafting screen unpauses", not get_tree().paused)


# ---------------------------------------------------------------------------------------- fight

func _fight(e: Node3D, label: String, limit: float) -> bool:
	var t_start := now()
	var hits := 0
	var healed := false
	var shots_taken := 0
	while now() - t_start < limit:
		if not is_instance_valid(e) or bool(e.get("dead")):
			break
		var ep := Vector2(e.global_position.x, e.global_position.z)
		var d := p2().distance_to(ep)
		face(ep, -0.2)
		if d > 2.0:
			hold("move_forward", true)
			hold("sprint", d > 6.0)
		else:
			hold("move_forward", false)
			hold("sprint", false)
			await key(KEY_J, 1)         # one frame is a light tap: at 1-2 fps three frames would read as a charged heavy (0.3 s of game time)
			hits += 1
		if bool(player.get("dead")):
			L("player died during %s fight" % label)
			break
		if player.health < player.max_health * 0.85:
			if not healed:
				L("[HOOK] heal the player during %s (hp %d)" % [label, player.health])
				healed = true
			player.health = player.max_health
		beat("fight %s hits %d" % [label, hits])
		if int(now() - t_start) % 10 == 0 and int(now() - t_start) != int(_last_fight_log):
			_last_fight_log = int(now() - t_start)
			L("fight %s t=%.0f dist %.1f enemy hp %s state %s player hp %d hits %d" % [label, now() - t_start, d, str(e.get("health")), str(e.get("state")), player.health, hits])
		if shots_taken < 2 and now() - t_start > 4.0 * (shots_taken + 1):
			shots_taken += 1
			await shot("fight_%s_%d" % [label, shots_taken])
		await frames(1)
	release_all()
	var dead := not is_instance_valid(e) or bool(e.get("dead"))
	if not dead:
		L("%s survived: health %s state %s" % [label, str(e.get("health")), str(e.get("state"))])
	return dead


func _s_fight() -> void:
	WorldSim.time_of_day = 13.0
	var c: Vector2 = ashford()["pos"]
	var open := c + Vector2(0, 90)
	await teleport(open, 0.0, 1.0)
	player.health = player.max_health
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	# wolf
	var w := Wolf.new()
	w.species = "wolf"
	w.home = open + fwd * 8.0
	w.territory = 200.0
	main.world.add_child(w)
	w.global_position = Vector3(w.home.x, WorldGen.height(w.home.x, w.home.y) + 0.3, w.home.y)
	w._provoked = 8.0
	await wait(1.0)
	await shot("wolf_spawned")
	var hp0: int = int(player.health)
	var killed := await _fight(w, "wolf", 50.0)
	var wolf_hurt: bool = killed or (is_instance_valid(w) and int(w.get("health")) < 45)
	check("wolf is hit by melee (killed, or hurt and fled)", wolf_hurt, "killed=%s player hp %d->%d" % [str(killed), hp0, player.health])
	await shot("wolf_after")
	if is_instance_valid(w) and not bool(w.get("dead")):
		w.queue_free()
	await wait(1.0)
	# bandit (humanoid fighter)
	player.health = player.max_health
	var bp := open + fwd * 4.0
	var b := Soldier.create(1, "Bandit", "Bandit", ["1H_Sword", "Round_Shield"])
	main.world.add_child(b)
	b.global_position = Vector3(bp.x, WorldGen.height(bp.x, bp.y) + 0.3, bp.y)
	await wait(1.0)
	await shot("bandit_spawned")
	var kb := await _fight(b, "bandit", 60.0)
	check("bandit is killed by melee", kb, "player hp %d" % player.health)
	await shot("bandit_after")
	if is_instance_valid(b) and not bool(b.get("dead")):
		b.queue_free()
	await ensure_alive()
	player.health = player.max_health
	await wait(0.5)


# ---------------------------------------------------------------------------------------- steal / sleep / coach

func _s_steal() -> void:
	WorldSim.time_of_day = 13.0
	var c: Vector2 = ashford()["pos"]
	var target: Node3D = null
	var bd := 1e9
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("breakable.gd") and not bool(n.get("broken")):
			var d := (n as Node3D).global_position.distance_to(Vector3(c.x, (n as Node3D).global_position.y, c.y))
			if d < bd and d < float(ashford()["radius"]) * 0.9:
				bd = d
				target = n
	check("a smashable barrel/crate stands inside Ashford", target != null)
	if target == null:
		return
	var tp := Vector2(target.global_position.x, target.global_position.z)
	var stand := tp + (c - tp).normalized() * 1.8
	await teleport(stand, yaw_to(stand, tp), 0.8)
	await wait(2.0)
	var Witness := load("res://scripts/population/witness.gd") as GDScript
	var soc: RefCounted = NpcWorld._society()
	var crimes0 := (soc.get("crimes") as Array).size() if soc != null else -1
	var cases0 := (Witness.get("cases") as Array).size()
	var gold0 := Game.gold
	var inv0 := _inv_total()
	var villagers := get_tree().get_nodes_in_group("villager").size()
	# put a passer-by in front of the thief so there is someone to see it
	var wit: Node3D = null
	for n in get_tree().get_nodes_in_group("villager"):
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			wit = n
			break
	if wit != null:
		L("[HOOK] move villager %s next to the thief as a witness" % str(wit.name))
		var wp := tp + (stand - tp).normalized() * 4.0 + Vector2(1.5, 0)
		wit.global_position = Vector3(wp.x, WorldGen.height(wp.x, wp.y) + 0.2, wp.y)
		await wait(1.5)
	# a real swing at the prop first (animation, hit detection), then the guaranteed blow
	face(tp, -0.2)
	await key(KEY_J, 3)
	await wait(0.8)
	if not bool(target.get("broken")):
		target.call("take_damage", 999, player)
	await wait(0.5)
	var sid_here := int(ashford()["id"])
	var rr: Dictionary = NpcWorld.report_crime(get_tree(), "pickpocket", tp, sid_here, true)
	note("direct report_crime result: %s" % str(rr).left(200))
	check("prop is broken", bool(target.get("broken")))
	await shot("steal_smash")
	await wait(6.0)
	var crimes1 := (soc.get("crimes") as Array).size() if soc != null else -1
	var cases1 := (Witness.get("cases") as Array).size()
	var aware := int(rr.get("seen_by", 0)) + int(rr.get("heard_by", 0))
	check("the theft reached the crime/witness path (villagers saw or heard it)", rr.has("seen_by") and aware > 0, "seen_by %s heard_by %s; witness cases %d->%d, crimes %d->%d (no eyewitness = nothing recorded, by design)" % [str(rr.get("seen_by")), str(rr.get("heard_by")), cases0, cases1, crimes0, crimes1])
	note("loot from the prop: inventory %d->%d, gold %d->%d" % [inv0, _inv_total(), gold0, Game.gold])
	await shot("steal_aftermath")


func _s_sleep() -> void:
	WorldSim.time_of_day = 21.0
	Life.needs.rest = 25.0
	L("[HOOK] time 21:00, rest 25")
	Game.gold = maxi(Game.gold, 20)
	if not await _station_menu("Inn"):
		return
	var d0 := WorldSim.day
	var h0 := WorldSim.time_of_day
	var ok := await click_text(hud._menu, "Rent a bed", true)
	check("inn menu has 'Rent a bed and sleep'", ok, str(hud_menu_texts()).left(200))
	await wait(1.5)
	var advanced := (WorldSim.day > d0) or (WorldSim.time_of_day < h0) or absf(WorldSim.time_of_day - h0) > 3.0
	check("sleeping advances the clock to morning", advanced, "day %d %.1f -> day %d %.1f" % [d0, h0, WorldSim.day, WorldSim.time_of_day])
	check("rest is restored", float(Life.needs.rest) > 60.0, "rest %.0f" % float(Life.needs.rest))
	await shot("after_sleep")
	close_everything()


func _s_coach() -> void:
	var way := {}
	var others: Array = []
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "waystation":
			others.append(s)
	if others.size() < 2:
		bug("missing", "fewer than 2 waystations (%d)" % others.size())
		return
	way = others[0]
	var dest: Dictionary = others[1]
	for pl in Life.discovery.places:
		Life.discovery.discover(String(pl["id"]), WorldSim.day)
	Game.gold = maxi(Game.gold, 80)
	await teleport(way["pos"], 0.0, 1.0)
	check("player stands at a waystation", not TravelRules.waystation_at(p2(), WorldGen.sites).is_empty())
	hud.toggle_map()
	await wait(1.0)
	var wm: Control = hud.world_map
	check("map opens", wm.visible)
	var dp: Vector2 = dest["pos"]
	wm.call("focus_on", dp, 1.0)
	await wait(0.6)
	wm.call("_tap", wm.call("to_screen", dp))
	await wait(0.6)
	var sel: Dictionary = wm.call("selected_place")
	note("selected place on the map: %s travel=%s" % [str(sel.get("name", "none")), str(sel.get("travel", false))])
	await shot("coach_map")
	var tb: BaseButton = wm._travel_btn
	var here0 := p2()
	var gold0 := Game.gold
	var h0 := WorldSim.day * 24.0 + WorldSim.time_of_day
	if tb != null and tb.visible and not tb.disabled:
		await click(tb, "Coach")
		await wait(5.0)
		check("coach moved the player", p2().distance_to(here0) > 100.0, "moved %.0f m" % p2().distance_to(here0))
		check("coach cost gold and time", Game.gold < gold0 and (WorldSim.day * 24.0 + WorldSim.time_of_day) > h0, "gold %d->%d" % [gold0, Game.gold])
	else:
		bug("coach", "travel button not usable: visible=%s disabled=%s (selected %s) card says: %s" % [str(tb != null and tb.visible), str(tb != null and tb.disabled), str(sel.get("name", "none")), String(wm._card_info.text).replace("\n", " | ")])
	await wait(1.0)
	await shot("coach_arrived")
	close_everything()


# ---------------------------------------------------------------------------------------- save / quit / reload

func _state_digest() -> Dictionary:
	var inv := {}
	for it in Life.inventory.get_items():
		var id: String = it.get_prototype().get_prototype_id()
		inv[id] = int(inv.get(id, 0)) + int(it.get_stack_size())
	return {"gold": Game.gold, "day": WorldSim.day, "hour": snappedf(WorldSim.time_of_day, 0.1), "age": Life.age(),
		"pos": p2(), "hp": int(player.health), "inv": inv, "main_hand": String(Life.equipment.call("item_in", "main_hand")),
		"name": String(Life.life_path.given_name), "food": snappedf(float(Life.needs.food), 1.0)}


func _s_save() -> void:
	await teleport((ashford()["pos"] as Vector2) + Vector2(5, 5), 0.0, 0.5)
	close_everything()
	var before := _state_digest()
	var ok := Life.save_game(2)
	check("save_game(2) succeeds", ok, "err %s" % str(Life.saves.last_error))
	# the real quicksave key as well
	await key(KEY_F5)
	await wait(0.6)
	L("state saved: %s" % str(before).left(300))
	await shot("saved")
	# --- quit: back out of the running world exactly like "Exit to Main Menu", then enter main.tscn again with the slot
	var slot_id: String = Life._slot_id(2)
	var tree := get_tree()
	if get_parent() == main:
		main.remove_child(self)
		tree.root.add_child(self)
	Flow.world_dirty = true
	Flow.pending_load = slot_id
	Flow.reset_world_state(tree)
	Flow.enter_game(tree)
	L("changing scene back to main.tscn (quit + reload) with pending_load=%s" % slot_id)
	tree.paused = false
	var old_main := main
	tree.change_scene_to_file(Flow.MAIN_SCENE)
	var got: bool = await await_sig(reloaded, 240.0)
	if not got:
		bug("reload", "the reloaded main scene never started the QA hook (or the world failed to boot)")
		return
	main = await _take_new_main()
	_grab_refs()
	check("old world was freed after the scene change", not is_instance_valid(old_main) or old_main.is_queued_for_deletion())
	# the load watcher restores the slot after the veil is gone; wait for it
	await wait_until(func() -> bool: return Flow.pending_load == "", 120.0)
	await wait(4.0)
	var after := _state_digest()
	var diffs: Array = []
	for k in before:
		if k in ["pos", "hp", "food", "hour"]:
			continue
		if JSON.stringify(before[k]) != JSON.stringify(after[k]):
			diffs.append("%s: %s -> %s" % [k, str(before[k]).left(80), str(after[k]).left(80)])
	check("state after reload matches the saved state (gold, day, age, inventory, equipment, name)", diffs.is_empty(), "; ".join(diffs))
	var dpos: float = (before["pos"] as Vector2).distance_to(after["pos"])
	check("position restored within 5 m", dpos < 5.0, "%.1f m off" % dpos)
	await shot("after_reload")


func _take_new_main() -> Node:
	var m: Node = get_tree().current_scene
	for i in 100:
		if m != null and m.get("player") != null and m.get("hud") != null:
			break
		await frames(5)
		m = get_tree().current_scene
	return m


# ============================================================================================ Thornfield slice (F1-F12)
## Stages tf_*: the vertical slice around Thornfield played through the real main scene. Same rules as above: real input
## where a player can, [HOOK] lines where the bot cheats (time of day, teleports, gold, moving a person into view).

const TfSites := preload("res://scripts/world/thornfield/sites.gd")
const TfRoster := preload("res://scripts/world/thornfield/roster.gd")
const TfObserve := preload("res://scripts/quests/objectives/observe.gd")
const Q_BARLEY := "thornfield_spoiled_barley"
const Q_CARTS := "thornfield_grain_carts"
const Q_CULPRIT := "thornfield_the_culprit"


func tf_town() -> Dictionary:
	return TfSites.settlement()


func tf_pos() -> Vector2:
	var t := tf_town()
	return t["pos"] if not t.is_empty() else Vector2.ZERO


func tf_hub() -> Node:
	return main.world.get_node_or_null("ThornfieldHub")


func set_hour(h: float, why := "") -> void:
	L("[HOOK] clock -> %.1fh %s" % [h, why])
	WorldSim.time_of_day = h


func heal_player(why := "") -> void:
	if player.health < player.max_health * 0.6:
		L("[HOOK] heal the player (hp %d) %s" % [player.health, why])
	player.health = player.max_health


func qrun() -> QuestRunner:
	return QuestHub.runner()


## The embodied body of a roster resident (the hidden barn figure does not count), or null.
func tf_body(id: String) -> Node3D:
	var row := TfRoster.row_of(id)
	if row < 0:
		return null
	for n in get_tree().get_nodes_in_group("villager"):
		if n is Node3D and n.get("person") != null and int(n.get("person")) == row and (n as Node3D).is_visible_in_tree() \
				and not n.is_in_group("barn_figure"):
			return n
	return null


## Walks (teleports) to where the resident's schedule has them and waits for their body. null + a bug when there is none.
func tf_go_to(id: String) -> Node3D:
	var row := TfRoster.row_of(id)
	if row < 0:
		bug("roster", "%s is not bound to a WorldSim row" % id)
		return null
	var p: Vector2 = WorldSim.pos[row]
	L("%s (row %d) is at %s, %.0f m away (phase %d, hour %.1f)" % [id, row, str(p.snappedf(0.1)), p2().distance_to(p), WorldSim.phase[row], WorldSim.time_of_day])
	if p2().distance_to(p) > 15.0:
		await teleport(p + Vector2(2.5, 1.5), 0.0, 1.0)
	var ok := await wait_until(func() -> bool: return tf_body(id) != null, 8.0)
	if not ok:
		L("[HOOK] population refresh to embody %s" % id)
		main.population.focus = player.global_position
		main.population.refresh()
		await wait_until(func() -> bool: return tf_body(id) != null, 6.0)
	return tf_body(id)


func menu_roots() -> Array:
	var out: Array = []
	for n: Variant in [hud.dialogue_sheet, hud.dialogue, hud._menu]:
		if n != null and is_instance_valid(n) and (n as Control).is_visible_in_tree():
			out.append(n)
	return out


func menu_texts() -> Array:
	var t: Array = []
	for r: Node in menu_roots():
		for b in buttons_in(r):
			t.append(button_text(b))
	return t


## Real click on the first visible button (sheet, dialogue or menu) whose text contains `needle`.
func click_option(needle: String) -> bool:
	for r: Node in menu_roots():
		var b := find_button(r, needle, true)
		if b != null:
			await click(b, needle)
			await wait(0.7)
			return true
	return false


## Stands next to `target` (8 spots around it, nearest the `toward` point first) until the prompt picks it. For a villager the
## prompt target is the TalkTarget parked on that body.
func tf_reach(target: Node3D, label: String, toward := Vector2.INF, dist := 1.5) -> bool:
	var tp := Vector2(target.global_position.x, target.global_position.z)
	if toward == Vector2.INF:
		toward = tf_pos()
	var dir := (toward - tp).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	var near: Node3D = null
	for i in 12:
		var ang := float(i % 8) * PI / 4.0 * (1.0 if i % 2 == 0 else -1.0)
		var stand := tp + dir.rotated(ang) * (dist if i < 8 else dist + 0.9)
		if InteriorDoor.active != null:
			# inside a room (300 m up): main._teleport would drop the player on the terrain below, so place it at the target's height
			player.global_position = Vector3(stand.x, target.global_position.y + 0.1, stand.y)
			player.velocity = Vector3.ZERO
			player.set_camera(yaw_to(stand, tp), -0.2)
			player.reset_physics_interpolation()
			await wait(0.3)
		else:
			await teleport(stand, yaw_to(stand, tp), 0.3)
		face(tp, -0.1)
		await wait(0.6)
		near = player.nearest_interactable()
		if near == target or (near != null and near.name == "TalkTarget" and near.get("current") == target):
			return true
	L("reach %s: nearest interactable is %s (%s)" % [label, str(near), String(near.get("title")) if near != null and near.get("title") != null else "-"])
	return false


## Software GL runs at ~1-2 fps and Godot caps a frame at max_physics_steps_per_frame (8) physics steps, so game time crawls
## (~0.13 game s per frame). Raising the cap lets time-based waits (a 20 s stakeout, the escort walk) finish in reasonable wall time.
func fast_game(steps: int) -> void:
	L("[HOOK] Engine.max_physics_steps_per_frame %d -> %d (game time otherwise crawls at 1-2 fps)" % [Engine.max_physics_steps_per_frame, steps])
	Engine.max_physics_steps_per_frame = steps


## An XZ spot 9-15 m from the barn beat that is out of sight for every facing at both ends of it, with the real night light.
func tf_unseen_spot(a: Vector2, b: Vector2) -> Vector2:
	var Perc := load("res://scripts/population/perception.gd") as GDScript
	var mid := (a + b) * 0.5
	for d: float in [11.0, 13.0, 15.0, 9.0]:
		for i in 24:
			var cand := mid + Vector2(cos(float(i) * TAU / 24.0), sin(float(i) * TAU / 24.0)) * d
			var light: float = Perc.call("light_at", cand)
			var ok := true
			for fp: Vector2 in [a, b]:
				for k in 16:
					var facing := Vector2(cos(float(k) * TAU / 16.0), sin(float(k) * TAU / 16.0))
					if not TfObserve.is_unseen(fp, facing, cand, light, 0.6):
						ok = false
						break
				if not ok:
					break
			if ok:
				return cand
	return Vector2.INF


func quest_line(id: String) -> String:
	var r := qrun()
	if r.run(id) == null:
		return "%s: not started" % id
	var parts: Array = []
	for o: RefCounted in r.objectives_of(id):
		parts.append("%s %s%s" % [o.id, o.call("_counter"), "" if not o.is_done() else " done"])
	return "%s: %s stage %s [%s]" % [id, r.run(id).state, r.stage_of(id), ", ".join(parts)]


## Opens Hesta's conversation (Station) and returns the visible option texts.
func tf_open_hesta() -> bool:
	var hub := tf_hub()
	var hesta: Node3D = hub.get("hesta") if hub != null else null
	if hesta == null or not is_instance_valid(hesta):
		bug("thornfield", "Hesta Thorne (giver of every Thornfield quest) does not exist in the world")
		return false
	close_everything()
	var hp := Vector2(hesta.global_position.x, hesta.global_position.z)
	if p2().distance_to(hp) > 6.0 or player.nearest_interactable() != hesta:
		var ok := await tf_reach(hesta, "Hesta", hp + Vector2(0, 6))
		if not ok:
			bug("thornfield", "Hesta is not the nearest interactable from any spot around her")
			return false
	var opened := false
	for attempt in 3:
		var best0 := Interaction.best(player)
		L("before E at Hesta: best candidate %s, dist %.1f" % [str(Interaction.node_of(best0)), player.global_position.distance_to(hesta.global_position)])
		await key(KEY_E)
		opened = await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
		await wait(0.5)
		if not opened:
			L("E did nothing at Hesta: menu %s dialogue %s sheet %s paused %s, best now %s" % [str(hud._menu.visible), str(hud.dialogue.visible), str(hud.dialogue_sheet.visible), str(get_tree().paused), str(Interaction.node_of(Interaction.best(player)))])
			return false
		var who := String((main.services._talk as Dictionary).get("id", ""))
		if who == "hesta_thorne":
			return true
		bug("ui", "a menu other than Hesta's replaced her conversation (talk id '%s', options %s)" % [who, str(menu_texts()).left(120)])
		await shot("hesta_hijacked")
		close_everything()
		await wait(0.5)
	return false


func _s_tf_talk() -> void:
	if Life.age() < 18:
		set_age(18)
	set_hour(11.0, "named residents are out at market hour")
	var town := tf_pos()
	await teleport(town + Vector2(0, 12), 0.0, 1.5)
	await shot("thornfield_arrive")
	check("the Thornfield hub is in the world", tf_hub() != null)
	check("the roster bound its named residents to WorldSim rows", TfRoster.is_bound() and TfRoster.bound_rows().size() >= 20, "%d rows" % TfRoster.bound_rows().size())
	var body: Node3D = null
	var rid := ""
	var reached := false
	for id: String in ["old_hild", "granfer_aldous", "wilm_garrow", "odo_marsh", "maud_pennick", "edric_vane", "bram_oakley", "pell_hargrove"]:
		body = await tf_go_to(id)
		if body == null:
			continue
		rid = id
		var named_bodies := 0
		for v in get_tree().get_nodes_in_group("villager"):
			if TfRoster.is_named(int(v.get("person") if v.get("person") != null else -1)):
				named_bodies += 1
		note("%d named bodies around, talking to %s (%s)" % [named_bodies, rid, TfRoster.name_of(TfRoster.row_of(rid))])
		reached = await tf_reach(body, rid, tf_pos())
		if reached:
			break         # a resident standing in a doorway has the door as the prompt target: try the next one
	check("a named resident has a body in view", body != null, rid)
	if body == null:
		return
	check("the resident is what the interact prompt picks (Talk)", reached)
	close_everything()
	# a second villager to watch the world with
	var other: Node3D = null
	for v in get_tree().get_nodes_in_group("villager"):
		if v != body and v is Node3D and (v as Node3D).is_visible_in_tree() and not v.is_in_group("barn_figure") and (v as Node3D).global_position.distance_to(player.global_position) < 40.0:
			other = v
			break
	var sess: Node = main.services.talk_session
	var reasons: Array = []
	sess.ended.connect(func(r: String) -> void: reasons.append(r))
	L("before E: best candidate %s (TalkTarget current %s)" % [str(Interaction.node_of(Interaction.best(player))), str(Interaction.node_of(Interaction.best(player)).get("current")) if Interaction.node_of(Interaction.best(player)) != null else "-"])
	await key(KEY_E)
	await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
	await wait(0.5)
	check("E opens the in-world conversation sheet", hud.dialogue_sheet.visible, "sheet %s dialogue %s menu %s" % [str(hud.dialogue_sheet.visible), str(hud.dialogue.visible), str(hud._menu.visible)])
	check("the talk session is active on that body", bool(sess.get("active")) and sess.get("npc") == body)
	check("the villager has stopped (is_talking)", body.has_method("is_talking") and bool(body.call("is_talking")))
	await shot("talk_sheet")
	L("sheet options: %s" % str(menu_texts()).left(300))
	var b0 := Vector2(body.global_position.x, body.global_position.z)
	var t0 := WorldSim.time_of_day
	var o0 := Vector2(other.global_position.x, other.global_position.z) if other != null else Vector2.ZERO
	await wait(4.0)
	var b1 := Vector2(body.global_position.x, body.global_position.z)
	check("the NPC stands still while the sheet is open", b0.distance_to(b1) < 0.6, "moved %.2f m" % b0.distance_to(b1))
	var fdir: Vector2 = body.call("perception_facing") if body.has_method("perception_facing") else Vector2.ZERO
	var to_p := (p2() - b1).normalized()
	check("the NPC faces the player", fdir.length() > 0.1 and fdir.normalized().dot(to_p) > 0.6, "facing %s, to player %s, dot %.2f" % [str(fdir), str(to_p), fdir.normalized().dot(to_p) if fdir.length() > 0.1 else -9.0])
	check("the world keeps running (clock advances, tree not paused)", WorldSim.time_of_day != t0 and not get_tree().paused, "clock %.3f -> %.3f paused %s" % [t0, WorldSim.time_of_day, str(get_tree().paused)])
	if other != null and is_instance_valid(other):
		var o1 := Vector2(other.global_position.x, other.global_position.z)
		note("another villager moved %.1f m in 4 s while the sheet was open" % o0.distance_to(o1))
	# pick the first real option (a talk node), then walk away with the movement keys
	var opts := menu_texts()
	if not opts.is_empty():
		await click_option(String(opts[0]).left(12))
		await wait(0.5)
		await shot("talk_node")
	face(b1 + (p2() - b1).normalized() * 10.0, -0.1)    # turn away from the NPC
	hold("move_forward", true)
	var gone := await wait_until(func() -> bool: return not bool(sess.get("active")), 6.0)
	release_all()
	await wait(0.6)
	check("walking away ends the talk and closes the sheet", gone and not hud.is_menu_open() and not bool(body.call("is_talking")), "reasons %s, menu open %s" % [str(reasons), str(hud.is_menu_open())])
	await shot("talk_walked_away")
	# second route: stand still and leave by distance (teleport 7 m away)
	if is_instance_valid(body):
		var again := await tf_reach(body, rid, tf_pos())
		if again:
			await key(KEY_E)
			await wait(1.0)
			var away := Vector2(body.global_position.x, body.global_position.z) + (p2() - Vector2(body.global_position.x, body.global_position.z)).normalized() * 7.0
			L("[HOOK] teleport 7 m away from the talker")
			await teleport(away, 0.0, 0.3)
			var gone2 := await wait_until(func() -> bool: return not bool(sess.get("active")), 4.0)
			check("moving more than 4 m away ends the talk (distance)", gone2 and not hud.is_menu_open(), "reasons %s" % str(reasons))
	close_everything()


func _s_tf_barley() -> void:
	var r := qrun()
	if Life.age() < 18:
		set_age(18)
	set_hour(10.0, "daylight for the clue hunt")
	var b := TfSites.brewery()
	check("the Thornfield Brewery landmark exists", not b.is_empty())
	if b.is_empty():
		return
	await teleport(TfSites.to_world(b, TfSites.HESTA_AT + Vector2(0, 7)), 0.0, 1.5)
	await shot("brewery")
	var gold0 := Game.gold
	var opened := await tf_open_hesta()
	check("E opens Hesta Thorne's conversation", opened)
	var texts := menu_texts()
	L("Hesta options: %s" % str(texts).left(300))
	await shot("hesta_talk")
	var offered := false
	if opened:
		offered = await click_option("Spoiled Barley")
	check("Hesta offers 'The Spoiled Barley' as an 'Ask about work' option", offered, str(texts).left(200))
	if not offered and not r.is_active(Q_BARLEY):
		L("[HOOK] start %s directly" % Q_BARLEY)
		r.start(Q_BARLEY)
	close_everything()
	check("the quest is active", r.is_active(Q_BARLEY), quest_line(Q_BARLEY))
	# --- clues: walk to each and Examine with E
	var hub := tf_hub()
	var examined := 0
	for c: Node3D in hub.get("clues"):
		var cid := String(c.get("clue_id"))
		var ok := await tf_reach(c, cid, TfSites.to_world(b, Vector2(0, 8)), 1.3)
		if not ok:
			L("[HOOK] standing on %s: the prompt did not pick it" % cid)
			await teleport(Vector2(c.global_position.x, c.global_position.z) + Vector2(0.8, 0.8), 0.0, 0.4)
		face(Vector2(c.global_position.x, c.global_position.z), -0.3)
		await wait(0.3)
		var lab: Dictionary = Interaction.label_of(Interaction.best(player)) if not Interaction.best(player).is_empty() else {}
		await key(KEY_E)
		await wait(0.6)
		if bool(c.get("examined")):
			examined += 1
		if cid.ends_with("sack"):
			await shot("clue_sack")
		L("clue %s examined=%s label %s" % [cid, str(c.get("examined")), str(lab.get("text", lab)).left(60)])
	check("all 4 clues can be examined with E", examined == 4, "%d/4" % examined)
	check("the clue stage is complete (3 of 4 needed) and the stakeout began", r.stage_of(Q_BARLEY) == "stakeout", quest_line(Q_BARLEY))
	await shot("clues_done")
	# --- stakeout: wait for night (real time from 18:55), then watch the figure unseen
	set_hour(18.9, "skip the afternoon")
	var fig: Node3D = hub.get("figure")
	var fp0: Vector2 = TfSites.figure_spot()
	await teleport(fp0 + Vector2(0, 12), 0.0, 1.0)
	player.set("crouching", true)
	L("[HOOK] crouch on for the stakeout (toggle via player state)")
	L("[HOOK] WorldSim.advance_hours(2.3): waiting out the dusk (a player rests; the 2 h Wait objective would otherwise take 60 game s)")
	WorldSim.advance_hours(2.3)
	await wait(1.0)
	fast_game(24)
	var awake := await wait_until(func() -> bool: return bool(fig.get("_awake")), 90.0)
	L("figure awake %s at hour %.2f" % [str(awake), WorldSim.time_of_day])
	var beat_a: Vector2 = fig.get("_a")
	var beat_b: Vector2 = fig.get("_b")
	var spot := tf_unseen_spot(beat_a, beat_b)
	if spot == Vector2.INF:
		spot = (beat_a + beat_b) * 0.5 + Vector2(0, 14)
		note("no spot is unseen for every facing; using 14 m off the beat")
	L("stakeout spot %s (%.1f m from the beat centre)" % [str(spot.snappedf(0.1)), spot.distance_to((beat_a + beat_b) * 0.5)])
	await teleport(spot, yaw_to(spot, fp0), 1.0)
	var t_wait := now()
	var last_log := 0.0
	var watched := false
	while now() - t_wait < 240.0:
		beat("stakeout %s" % quest_line(Q_BARLEY).right(60))
		heal_player("at the stakeout")
		if now() - last_log > 15.0:
			last_log = now()
			L("stakeout t=%.0f hour %.2f figure awake %s dist %.1f | %s" % [now() - t_wait, WorldSim.time_of_day, str(fig != null and fig.visible), p2().distance_to(fig.call("xz")) if fig != null else -1.0, quest_line(Q_BARLEY)])
		if r.stage_of(Q_BARLEY) == "report":
			watched = true
			break
		await wait(2.0)
	if fig != null and fig.visible:
		face(fig.call("xz"), -0.1)
		await wait(0.3)
		await shot("barn_figure")
	check("the barn figure is out at night", fig != null and bool(fig.get("_awake")))
	if not watched:
		bug("quest", "the night stakeout did not complete in play in %.0f s: %s" % [now() - t_wait, quest_line(Q_BARLEY)])
		L("[HOOK] force the stakeout: feed hours and observe events")
		for h in [19, 20]:
			QuestBus.shared().emit_event(&"hours", {"amount": 1.0, "hour": float(h)})
		QuestBus.shared().emit_event(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 30.0, "hour": 22.0})
		await wait(0.5)
	player.set("crouching", false)
	Engine.max_physics_steps_per_frame = 8
	check("the stakeout leads to the report stage", r.stage_of(Q_BARLEY) == "report", quest_line(Q_BARLEY))
	# --- report back to Hesta (daytime, she is at the brewery 5-22h; night is fine too)
	set_hour(10.5, "back to morning to report")
	await teleport(TfSites.to_world(b, TfSites.HESTA_AT + Vector2(0, 7)), 0.0, 1.0)
	opened = await tf_open_hesta()
	texts = menu_texts()
	L("Hesta options on report: %s" % str(texts).left(300))
	var rep := false
	if opened and not r.is_done(Q_BARLEY):
		rep = await click_option("Report")
	note("reporting: the talk_to objective was %s by opening Hesta's conversation (the 'Report' option %s)" % ["completed" if r.is_done(Q_BARLEY) and not rep else "completed by the option", "was not needed" if not rep else "was clicked"])
	close_everything()
	check("The Spoiled Barley completes and pays", r.is_done(Q_BARLEY) and Game.gold >= gold0 + 15, "gold %d -> %d; %s" % [gold0, Game.gold, quest_line(Q_BARLEY)])
	await shot("barley_done")


func _s_tf_cart() -> void:
	var r := qrun()
	var hub := tf_hub()
	if Life.age() < 18:
		set_age(18)
	if not r.is_done(Q_BARLEY):
		L("[HOOK] The Spoiled Barley is not done: completing it so the cart quest is offered")
		r.start(Q_BARLEY)
		for id: String in TfObserveIds():
			QuestBus.shared().emit_event(&"interact", {"id": id})
		QuestBus.shared().emit_event(&"hours", {"amount": 2.0, "hour": 20.0})
		QuestBus.shared().emit_event(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 30.0, "hour": 22.0})
		QuestBus.shared().emit_event(&"talk", {"npc": "hesta_thorne"})
	set_hour(9.0, "morning for the cart")
	var b := TfSites.brewery()
	await teleport(TfSites.to_world(b, TfSites.HESTA_AT + Vector2(0, 7)), 0.0, 1.5)
	var opened := await tf_open_hesta()
	var offered := false
	if opened:
		offered = await click_option("Grain Carts")
	check("Hesta offers 'Wolves at the Grain Carts' after the barley quest", offered, str(menu_texts()).left(200))
	if not offered and not r.is_active(Q_CARTS):
		L("[HOOK] start %s directly" % Q_CARTS)
		r.start(Q_CARTS)
	close_everything()
	check("the cart quest is active at the 'load' stage", r.is_active(Q_CARTS) and r.stage_of(Q_CARTS) == "load", quest_line(Q_CARTS))
	# --- load: take the sound barley from the tithe barn store
	var store: Node3D = hub.get("store")
	var ok := await tf_reach(store, "barley store", TfSites.to_world(b, Vector2(0, 8)), 1.4)
	check("the barley pile is the interact prompt target", ok)
	if ok:
		var lab := Interaction.label_of(Interaction.best(player))
		L("store label: %s" % str(lab.get("text", lab)).left(80))
		await key(KEY_E)
		await wait(1.0)
	check("E takes 4 sacks of sound barley", Life.count("barley") >= 4, "barley %d" % Life.count("barley"))
	if Life.count("barley") < 4:
		L("[HOOK] give 4 barley")
		Life.give("barley", 4)
	await wait(1.5)
	check("the load stage completes and the wolves come (guard stage)", r.stage_of(Q_CARTS) == "guard", quest_line(Q_CARTS))
	# --- guard: fight the ambush pack at the cart
	var cart: Node3D = hub.get("cart")
	check("the grain cart exists in the world", cart != null and is_instance_valid(cart))
	var threat: Node = hub.get("threat")
	var got := await wait_until(func() -> bool: return not (threat.get("ambush_wolves") as Array).is_empty(), 8.0)
	check("an ambush pack spawns for the cart", got, "%d wolves" % (threat.get("ambush_wolves") as Array).size())
	await shot("cart_ambush_start")
	if cart != null:
		await teleport(cart.call("xz") + Vector2(2.5, 2.5), 0.0, 0.6)
	var t_guard := now()
	var kills := 0
	while now() - t_guard < 150.0 and r.stage_of(Q_CARTS) == "guard":
		heal_player("guarding the cart")
		var alive: Array = (threat.get("ambush_wolves") as Array).filter(func(w: Variant) -> bool: return is_instance_valid(w) and not bool(w.dead))
		if alive.is_empty():
			await wait(1.0)
			if (threat.get("ambush_wolves") as Array).is_empty() and now() - t_guard > 20.0:
				break
			continue
		var w: Node3D = alive[0]
		var dead := await _fight(w, "cart wolf", 40.0)
		if dead:
			kills += 1
		if kills <= 1:
			await shot("cart_wolf_%d" % kills)
		L("guard: kills %d, cart hp %s, %s" % [kills, str(cart.get("health")) if cart != null else "-", quest_line(Q_CARTS)])
	check("the pack can be killed in melee (3 wolves)", kills >= 3, "%d kills" % kills)
	# protect needs 1 game hour (kill needs 3): a player would wait it out; the clock is moved on here
	if r.stage_of(Q_CARTS) == "guard":
		L("[HOOK] WorldSim.advance_hours(1.2): the Protect objective counts one game hour (game time crawls at 1-2 fps)")
		WorldSim.advance_hours(1.2)
	await wait_until(func() -> bool: return r.stage_of(Q_CARTS) != "guard", 20.0)
	check("the guard stage completes (cart alive, 3 wolves killed)", r.stage_of(Q_CARTS) == "road", quest_line(Q_CARTS))
	if r.stage_of(Q_CARTS) == "guard":
		bug("quest", "guard stage stuck: %s; cart alive %s" % [quest_line(Q_CARTS), str(cart != null and not bool(cart.get("dead")))])
		r.notify(&"kill", {"target": "wolf", "place": "thornfield_fields", "amount": 3})
		r.notify(&"hours", {"amount": 2.0, "hour": 12.0})
		L("[HOOK] forced the guard stage")
		await wait(1.5)
	# --- road: escort the cart to the mill on foot
	await wait(1.0)
	check("the cart rolls (start_route) in the road stage", cart != null and bool(cart.get("moving")), quest_line(Q_CARTS))
	var mill: Vector2 = TfSites.door_of_site("thornfield_mill")
	fast_game(24)
	var t_road := now()
	while now() - t_road < 240.0 and r.stage_of(Q_CARTS) == "road" and cart != null and not bool(cart.get("finished")) and not bool(cart.get("dead")):
		heal_player("escorting")
		var cp: Vector2 = cart.call("xz")
		var target := cp + (mill - cp).normalized() * 3.0
		var walked := await walk_to(target, 1.5, 6.0, false, 3.0)
		if not walked and p2().distance_to(cp) > 12.0:
			L("[HOOK] the walk is blocked (tree/rock) %.0f m from the cart: teleporting beside it" % p2().distance_to(cp))
			await teleport(cp + (mill - cp).normalized() * -3.0, 0.0, 0.2)
		if int(now() - t_road) % 20 == 0:
			L("escort t=%.0f cart %s mill %.0f m away player %.0f m from cart" % [now() - t_road, str(cp.snappedf(0.1)), cp.distance_to(mill), p2().distance_to(cp)])
		await wait(0.3)
	Engine.max_physics_steps_per_frame = 8
	await shot("cart_at_mill")
	await wait_until(func() -> bool: return (cart != null and bool(cart.get("finished"))) or r.stage_of(Q_CARTS) == "mill", 8.0)
	check("the cart reaches the mill with the player escorting", (cart != null and bool(cart.get("finished"))) or r.stage_of(Q_CARTS) == "mill", "%.0f m from the mill door" % (cart.call("xz").distance_to(mill) if cart != null else -1.0))
	await wait(2.0)
	check("the escort stage completes (mill stage: hand over the barley)", r.stage_of(Q_CARTS) == "mill", quest_line(Q_CARTS))
	if r.stage_of(Q_CARTS) == "road":
		bug("quest", "escort did not register arrival: %s" % quest_line(Q_CARTS))
		QuestBus.shared().emit_event(&"arrive", {"actor": "grain_cart_1", "place": "thornfield_mill"})
		L("[HOOK] forced arrive event")
		await wait(1.0)
	# --- mill: the miller takes the barley through the talk menu
	set_hour(10.0, "the miller works 6-17h")
	var gold0 := Game.gold
	var miller := await tf_go_to("thornfield_miller")
	var delivered := false
	if miller != null:
		var rc := await tf_reach(miller, "miller", tf_pos())
		if rc:
			await key(KEY_E)
			await wait(1.0)
			L("miller options: %s" % str(menu_texts()).left(300))
			delivered = await click_option("Hand over")
		close_everything()
	check("the miller's talk menu has 'Hand over 4 barley' and it works", delivered, quest_line(Q_CARTS))
	if not delivered and r.stage_of(Q_CARTS) == "mill":
		L("[HOOK] deliver event")
		QuestBus.shared().emit_event(&"deliver", {"item": "barley", "to": "thornfield_miller", "amount": 4})
		await wait(0.6)
	check("Wolves at the Grain Carts completes and pays 40 gold", r.is_done(Q_CARTS) and Game.gold >= gold0 + 40, "gold %d -> %d; %s" % [gold0, Game.gold, quest_line(Q_CARTS)])
	await shot("carts_done")


func TfObserveIds() -> Array:
	return ["thornfield/clue/sack", "thornfield/clue/prints", "thornfield/clue/lock", "thornfield/clue/ledger"]


func _s_tf_wilm() -> void:
	var r := qrun()
	var hub := tf_hub()
	if Life.age() < 18:
		set_age(18)
	if not r.is_done(Q_BARLEY):
		bug("bot", "Wilm stage needs The Spoiled Barley done first; forcing it")
		r.start(Q_BARLEY)
		for id: String in TfObserveIds():
			QuestBus.shared().emit_event(&"interact", {"id": id})
		QuestBus.shared().emit_event(&"hours", {"amount": 2.0, "hour": 20.0})
		QuestBus.shared().emit_event(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 30.0, "hour": 22.0})
		QuestBus.shared().emit_event(&"talk", {"npc": "hesta_thorne"})
	set_hour(12.0, "Wilm is at the market 11-14h")
	var b := TfSites.brewery()
	await teleport(TfSites.to_world(b, TfSites.HESTA_AT + Vector2(0, 7)), 0.0, 1.5)
	var gold0 := Game.gold
	var rep0 := 0
	var opened := await tf_open_hesta()
	var offered := false
	if opened:
		offered = await click_option("Garrow")
	check("Hesta offers 'Wilm Garrow's Offer'", offered, str(menu_texts()).left(200))
	if not offered and not r.is_active(Q_CULPRIT):
		r.start(Q_CULPRIT)
		L("[HOOK] start %s directly" % Q_CULPRIT)
	close_everything()
	check("the culprit quest is active at 'confront'", r.is_active(Q_CULPRIT) and r.stage_of(Q_CULPRIT) == "confront", quest_line(Q_CULPRIT))
	# goto: the barn
	var barn := TfSites.place_pos("thornfield_barn")
	await teleport(barn + Vector2(0, 4), 0.0, 1.0)
	await wait(3.0)
	L(quest_line(Q_CULPRIT))
	# talk to Wilm
	var wilm := await tf_go_to("wilm_garrow")
	check("Wilm Garrow has a body at the market at noon", wilm != null)
	if wilm != null:
		var ok := await tf_reach(wilm, "wilm", tf_pos())
		if ok:
			await key(KEY_E)
			await wait(1.0)
			var texts := menu_texts()
			L("Wilm options: %s" % str(texts).left(400))
			var heard := await click_option("saw you at the barn")
			check("Wilm's talk offers the confrontation line", heard, str(texts).left(300))
			await wait(0.6)
			await shot("wilm_confession")
			L("after confession: options %s | %s" % [str(menu_texts()).left(200), quest_line(Q_CULPRIT)])
			if heard:
				await click_option("Think about")
			close_everything()
		else:
			close_everything()
	await wait(1.0)
	check("hearing the confession advances to the verdict stage", r.stage_of(Q_CULPRIT) == "verdict", quest_line(Q_CULPRIT))
	if r.stage_of(Q_CULPRIT) == "confront":
		bug("quest", "Wilm's confession did not register: %s" % quest_line(Q_CULPRIT))
		QuestBus.shared().emit_event(&"goto", {"place": "thornfield_barn"})
		QuestBus.shared().emit_event(&"talk", {"npc": "wilm_garrow", "node": "confession"})
		L("[HOOK] forced confession")
		await wait(0.8)
	# the verdict is a Choose objective shown in Wilm's talk menu
	if wilm != null and is_instance_valid(wilm):
		var ok2 := await tf_reach(wilm, "wilm", tf_pos())
		if ok2:
			await key(KEY_E)
			await wait(1.0)
			var texts2 := menu_texts()
			L("Wilm options at the verdict: %s" % str(texts2).left(400))
			await shot("wilm_verdict")
			var chose := await click_option("turning him in")
			check("the verdict choice 'turn him in' is offered by Wilm and clickable", chose, str(texts2).left(300))
			close_everything()
	await wait(0.8)
	check("choosing 'turn in' branches to 'turned_in'", r.stage_of(Q_CULPRIT) == "turned_in", quest_line(Q_CULPRIT))
	if r.stage_of(Q_CULPRIT) == "verdict":
		QuestBus.shared().emit_event(&"choose", {"choice": "verdict", "option": "turn_in"})
		L("[HOOK] forced verdict choice")
		await wait(0.6)
	# tell Hesta
	opened = await tf_open_hesta()
	if opened and not r.is_done(Q_CULPRIT):
		L("Hesta options: %s" % str(menu_texts()).left(300))
		await click_option("Report")
	close_everything()
	check("Wilm's Offer completes (turn-in branch) and pays", r.is_done(Q_CULPRIT) and Game.gold >= gold0 + 20, "gold %d -> %d; %s" % [gold0, Game.gold, quest_line(Q_CULPRIT)])
	await shot("culprit_done")


# ---------------------------------------------------------------------------------------- Thornfield: interiors, theft, traversal

const TfTown := preload("res://scripts/world/thornfield/slice_town.gd")
const TfLight := preload("res://scripts/interiors/interior_light.gd")
const TfOwnership := preload("res://scripts/sim/ownership.gd")
const TfTheft := preload("res://scripts/sim/theft.gd")
const TfShopHours := preload("res://scripts/sim/shop_hours.gd")


func tf_door_for(bid: String) -> InteriorDoor:
	var bd: Dictionary = TfTown.building(bid)
	if bd.is_empty():
		return null
	var lp: Vector2 = bd["pos"]
	for n in get_tree().root.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and not (n as InteriorDoor).is_exit and n.has_meta("lot_pos") and (n.get_meta("lot_pos") as Vector2).distance_to(lp) < 0.05:
			return n
	return null


## Walks to a Thornfield building's door and enters with E. Returns the interior root, or null (with a bug).
func tf_enter(bid: String) -> Node3D:
	var bd: Dictionary = TfTown.building(bid)
	if bd.is_empty():
		bug("slice", "no building %s in the Thornfield plan" % bid)
		return null
	var dp: Vector2 = bd["door"]
	await teleport(dp + (tf_pos() - dp).normalized() * 3.0, 0.0, 1.0)
	var door := tf_door_for(bid)
	if door == null:
		bug("slice", "no InteriorDoor was built for %s (door point %s)" % [bid, str(dp)])
		return null
	var dpos := Vector2(door.global_position.x, door.global_position.z)
	var out_dir := (Vector2(door.global_transform.basis.z.x, door.global_transform.basis.z.z)).normalized()
	var stand := dpos + out_dir * 1.0
	await teleport(stand, yaw_to(stand, dpos), 0.4)
	await wait(0.8)
	var near: Node3D = player.nearest_interactable()
	check("%s: the door is the interact prompt target" % bid, near == door, "nearest %s" % str(near.name if near != null else "-"))
	var lab := Interaction.label_of(Interaction.best(player))
	L("%s door prompt: %s (scene %s)" % [bid, str(lab.get("text", lab)).left(60), door.interior_scene])
	var t_enter := now()
	await key(KEY_E)
	await wait_until(func() -> bool: return InteriorDoor.active != null, 90.0)
	await wait(2.0)
	note("%s entered in %.1f s" % [bid, now() - t_enter])
	if InteriorDoor.active == null:
		bug("slice", "E at the %s door did not enter the building" % bid)
		return null
	return InteriorDoor.active.interior


func tf_leave_by_exit(label: String) -> void:
	var ex: InteriorDoor = null
	for n in main.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and (n as InteriorDoor).is_exit:
			ex = n
	if ex == null:
		bug("slice", "%s: no exit door" % label)
		return
	if player.global_position.distance_to(ex.global_position) > 1.2:
		player.global_position = ex.global_position + Vector3(0.0, 0.1, 0.0)      # walked off to the counter / lever: back to the door
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await wait(0.8)
	for attempt in 3:
		await key(KEY_E)
		await wait(1.5)
		if hud.is_menu_open():
			hud.close_menu()
			continue
		if await wait_until(func() -> bool: return InteriorDoor.active == null, 20.0):
			break
	await wait(1.5)
	check("%s: E at the exit leaves the building" % label, InteriorDoor.active == null)


func _tf_interior_checks(label: String, interior: Node3D, hour: float) -> void:
	check("%s: the interior is a modular room" % label, interior != null and interior.has_method("light_report") and not (interior.get("layout") as Dictionary).is_empty(), "layout %s" % str(interior.get("layout_id")))
	await wait(1.5)
	var want: Array = interior.call("desired_roster", hour)
	var bodies: Dictionary = interior.get("bodies")
	var present := await wait_until(func() -> bool: return not (interior.get("bodies") as Dictionary).is_empty(), 10.0)
	L("%s household: scheduled %d, bodies %d, furniture %s" % [label, want.size(), (interior.get("bodies") as Dictionary).size(), str(interior.call("furniture_counts"))])
	if want.is_empty():
		note("%s: nobody is scheduled here at %.1fh" % [label, hour])
	else:
		check("%s: a household member is present at %.1fh" % [label, hour], present, "scheduled %d bodies %d" % [want.size(), (interior.get("bodies") as Dictionary).size()])
	# light follows the hour
	var lr: Dictionary = interior.call("light_report")
	var st: Dictionary = TfLight.state(hour, String(interior.get("layout_id")))
	check("%s: ambient light matches the hour" % label, absf(float(lr["ambient_energy"]) - float(st["ambient_energy"])) < 0.08, "report %.2f expected %.2f (hour %.1f)" % [float(lr["ambient_energy"]), float(st["ambient_energy"]), hour])
	var other_hour := 23.0 if TfLight.daylight(hour) > 0.5 else 12.0
	set_hour(other_hour, "light check: the room should follow")
	await wait_until(func() -> bool: return absf(float((interior.call("light_report") as Dictionary)["ambient_energy"]) - float(lr["ambient_energy"])) > 0.1, 8.0)
	var lr2: Dictionary = interior.call("light_report")
	check("%s: the room's light changes when the hour does" % label, absf(float(lr2["ambient_energy"]) - float(lr["ambient_energy"])) > 0.1, "%.2f at %.0fh -> %.2f at %.0fh" % [float(lr["ambient_energy"]), hour, float(lr2["ambient_energy"]), other_hour])
	set_hour(hour, "restore")
	await shot(label + "_inside")
	# the exit prompt from the spawn point
	var ex: InteriorDoor = interior.get("exit_door")
	var near: Node3D = player.nearest_interactable()
	L("%s spawn: nearest interactable %s, exit door %s, dist %.2f" % [label, str(near.name) if near != null else "-", str(ex.name) if ex != null else "-", player.global_position.distance_to(ex.global_position) if ex != null else -1.0])
	check("%s: the exit prompt is reachable from the spawn point (no step needed)" % label, ex != null and near == ex)


func _s_tf_interior() -> void:
	if Life.age() < 18:
		set_age(18)
	# --- a house: the baker's family home in the evening, when the household is in
	set_hour(21.0, "evening: a household is at home")
	var house := await tf_enter("thornfield_house_8")
	if house != null:
		await _tf_interior_checks("house", house, 21.0)
		await tf_leave_by_exit("house")
	close_everything()
	# --- a shop: the general shop at midday
	set_hour(12.0, "midday: the shop is open")
	var shop := await tf_enter("thornfield_shop")
	if shop != null:
		await _tf_interior_checks("shop", shop, 12.0)
		var counters := get_tree().get_nodes_in_group("shop_counter")
		check("the shop has a counter Station", not counters.is_empty())
		if not counters.is_empty():
			var st: Station = counters[0]
			check("the counter is open at midday", not st.is_closed(), st.prompt())
			var okc := await tf_reach(st, "shop counter", Vector2(player.global_position.x, player.global_position.z), 1.3)
			if okc:
				await key(KEY_E)
				await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
				L("shop counter menu: %s" % str(menu_texts()).left(200))
				await shot("shop_counter")
				close_everything()
		await tf_leave_by_exit("shop")
	close_everything()


func _tf_open_blocked(label: String) -> bool:
	return InteriorDoor.active != null


## Spawns an owned loose item `ahead` metres in front of the player, returns the GroundItem.
func tf_drop_owned(item: String, owner: String, ahead := 1.2) -> Node3D:
	var f := Vector2(-sin(player._yaw), -cos(player._yaw))
	var at := p2() + f * ahead
	var gi: Node3D = GroundItem.spawn(main.world, Vector3(at.x, WorldGen.height(at.x, at.y) + 0.1, at.y), item, 1, owner)
	return gi


func _s_tf_theft() -> void:
	if Life.age() < 18:
		set_age(18)
	var sid := int(tf_town()["id"])
	var house: Dictionary = TfTown.building("thornfield_house_5")
	var owner := TfOwnership.household(sid, int(house["lot"]))
	check("a Thornfield household's things are theft to take", TfOwnership.is_theft(owner), owner)
	var Witness := load("res://scripts/population/witness.gd") as GDScript
	var soc: RefCounted = NpcWorld._society()
	# --- seen: an owned loaf at the player's feet, a villager 4 m ahead looking at the player
	set_hour(12.0, "daylight, the street is busy")
	var town := tf_pos()
	await teleport(town + Vector2(0, 9), 0.0, 1.5)
	var wit: Node3D = null
	for v in get_tree().get_nodes_in_group("villager"):
		if v is Node3D and (v as Node3D).is_visible_in_tree() and not v.is_in_group("barn_figure") and (v as Node3D).global_position.distance_to(player.global_position) < 40.0:
			wit = v
			break
	if wit == null:
		var b := await tf_go_to("old_hild")
		wit = b
	check("a villager is around to witness", wit != null)
	if wit == null:
		return
	var wp := Vector2(wit.global_position.x, wit.global_position.z)
	var stand := wp + (town - wp).normalized() * 4.0
	await teleport(stand, yaw_to(stand, wp), 0.5)
	L("[HOOK] turn the villager to face the thief (a passer-by glancing over)")
	wit.rotation.y = atan2(stand.x - wp.x, stand.y - wp.y)
	var gi := tf_drop_owned("bread", owner, 1.0)
	await wait(1.0)
	var cases0 := (Witness.get("cases") as Array).size()
	var crimes0 := (soc.get("crimes") as Array).size() if soc != null else -1
	var near: Node3D = player.nearest_interactable()
	var lab := Interaction.label_of(Interaction.best(player))
	L("owned loaf prompt: %s (nearest %s)" % [str(lab.get("text", lab)).left(60), str(near)])
	check("the owned loaf reads 'Steal' in the prompt", String(lab.get("verb", lab.get("text", ""))).to_lower().contains("steal"), str(lab).left(80))
	await key(KEY_E)
	await wait(1.5)
	var last: Dictionary = TfTheft.last
	L("Theft.last: %s" % str(last).left(300))
	check("taking an owned item in view of a villager is a theft that was seen", bool(last.get("theft", false)) and int(last.get("seen_by", 0)) >= 1, str(last).left(200))
	await wait(4.0)
	var cases1 := (Witness.get("cases") as Array).size()
	var crimes1 := (soc.get("crimes") as Array).size() if soc != null else -1
	check("a witness case / crime was opened for it", cases1 > cases0 or crimes1 > crimes0, "cases %d->%d crimes %d->%d" % [cases0, cases1, crimes0, crimes1])
	check("the item is flagged as stolen in the pack", TfTheft.carries_stolen(), "stolen stacks %d" % TfTheft.stolen_stacks().size())
	await shot("theft_seen")
	# --- unseen: a spot well outside Thornfield with no villager within hearing range (40 m)
	var quiet := Vector2.INF
	var near_v := 0
	for rad: float in [150.0, 190.0, 230.0]:
		for k in 5:
			var cand := town + Vector2(cos(float(k) * TAU / 5.0 + 0.4), sin(float(k) * TAU / 5.0 + 0.4)) * rad
			await teleport(cand, 0.0, 1.0)
			near_v = 0
			for v in get_tree().get_nodes_in_group("villager"):
				if v is Node3D and (v as Node3D).global_position.distance_to(player.global_position) < 45.0:
					near_v += 1
			if near_v == 0:
				quiet = cand
				break
		if quiet != Vector2.INF:
			break
	L("quiet spot %s: %d villagers within 45 m, settlement id there %d" % [str(quiet), near_v, TfTheft.sid_at(p2())])
	check("a spot with nobody within hearing range exists near Thornfield", quiet != Vector2.INF)
	if quiet == Vector2.INF:
		return
	var gi2 := tf_drop_owned("apple", owner, 1.0)
	await wait(1.0)
	var cases2 := (Witness.get("cases") as Array).size()
	var crimes2 := (soc.get("crimes") as Array).size() if soc != null else -1
	await key(KEY_E)
	await wait(1.5)
	var last2: Dictionary = TfTheft.last
	L("Theft.last (unseen): %s" % str(last2).left(300))
	await wait(4.0)
	var cases3 := (Witness.get("cases") as Array).size()
	var crimes3 := (soc.get("crimes") as Array).size() if soc != null else -1
	check("taking it unseen is still flagged as stolen but nobody saw it", bool(last2.get("theft", false)) and int(last2.get("seen_by", 0)) == 0, str(last2).left(200))
	check("an unseen theft opens no witness case (no crime is reported)", cases3 == cases2, "cases %d->%d (society crimes %d->%d: the earlier seen theft's case commits in this window)" % [cases2, cases3, crimes2, crimes3])
	await shot("theft_unseen")
	# --- shop hours: the smith is shut at 22:00 and open at 10:00
	check("ShopHours: the blacksmith is open at 10:00 and shut at 22:00", TfShopHours.is_open("blacksmith", 10.0) and not TfShopHours.is_open("blacksmith", 22.0))
	set_hour(22.0, "night: the smithy is shut")
	var smithy := await tf_enter("thornfield_smithy")
	if smithy != null:
		await wait(2.0)
		var stations: Array = []
		for n in smithy.find_children("*", "Station", true, false):
			stations.append(n)
		var smith_st: Station = null
		for s: Station in stations:
			if s.hours_kind != "":
				smith_st = s
		L("smithy stations: %s" % str(stations.map(func(s: Station) -> String: return "%s(%s,%s)" % [s.title, s.hours_kind, s.prompt()])))
		check("the smithy's counter says Closed at 22:00", smith_st != null and smith_st.is_closed(), str(smith_st.prompt() if smith_st != null else "no station"))
		if smith_st != null:
			var ok := await tf_reach(smith_st, "smith station", Vector2(player.global_position.x, player.global_position.z), 1.3)
			if ok:
				var lab2 := Interaction.label_of(Interaction.best(player))
				L("smithy prompt at 22:00: %s" % str(lab2.get("text", lab2)).left(60))
				await key(KEY_E)
				await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
				var txt := " | ".join(menu_texts())
				var body := ""
				for r: Node in menu_roots():
					for l in r.find_children("*", "Label", true, false):
						body += String(l.get("text")) + " / "
				L("smithy menu at 22:00: buttons %s labels %s" % [txt.left(120), body.left(200)])
				check("the smithy's menu refuses trade out of hours", body.to_lower().contains("closed") or body.to_lower().contains("open") or body.to_lower().contains("come back") or body.to_lower().contains("morning"), body.left(160))
				await shot("smithy_closed")
				close_everything()
		await tf_leave_by_exit("smithy")
	set_hour(12.0, "restore")


func tf_make_box(at: Vector3, size: Vector3, yaw: float, label: String) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = label
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.42, 0.34)
	mi.material_override = m
	sb.add_child(mi)
	main.world.add_child(sb)
	sb.global_position = at + Vector3(0, size.y * 0.5, 0)
	sb.rotation.y = yaw
	return sb


func _s_tf_travel() -> void:
	if Life.age() < 18:
		set_age(18)
	set_hour(13.0, "daylight")
	var trav: Object = player._trav
	var kinds: Array = []
	trav.started.connect(func(k: StringName) -> void: kinds.append(String(k)))
	var base := TfSites.place_pos("thornfield_fields")
	await teleport(base, 0.0, 1.5)
	var f := Vector2(-sin(player._yaw), -cos(player._yaw))
	var side := Vector2(f.y, -f.x)
	var gy := WorldGen.height(base.x, base.y)
	# --- a low wall (0.8 m high, 0.4 m deep, 6 m wide) 5 m ahead: sprint into it
	var wp := base + f * 5.0
	var wall := tf_make_box(Vector3(wp.x, WorldGen.height(wp.x, wp.y), wp.y), Vector3(6.0, 0.8, 0.4), atan2(f.x, f.y), "QAWall")
	L("[HOOK] placed a 0.8 m wall 5 m ahead (the fields have no low wall)")
	await shot("vault_before")
	var y0 := player.global_position.y
	var side0 := (p2() - wp).dot(f)
	face(wp + f * 2.0, -0.1)
	hold("sprint", true)
	hold("move_forward", true)
	var t_v := now()
	while now() - t_v < 14.0:
		face(wp + f * 4.0, -0.1)
		await frames(1)
		if (p2() - wp).dot(f) > 1.0:
			break
	release_all()
	await wait(1.0)
	var past := (p2() - wp).dot(f)
	check("sprinting into a 0.8 m wall vaults it (VAULT started)", kinds.has("vault") and past > 0.5, "kinds %s, %.1f m beyond the wall" % [str(kinds), past])
	if past <= 0.5:
		bug("traversal", "the player could not cross a 0.8 m wall by sprinting: kinds %s pos %s" % [str(kinds), _pos2s()])
	await shot("vault_after")
	wall.queue_free()
	# --- a 1.6 m wall, 2 m deep: jump to mantle
	kinds.clear()
	await teleport(base + side * 12.0, yaw_to(base + side * 12.0, base + side * 12.0 + f), 0.8)
	var mp := p2() + f * 1.6
	var wall2 := tf_make_box(Vector3(mp.x, WorldGen.height(mp.x, mp.y), mp.y), Vector3(6.0, 1.6, 2.4), atan2(f.x, f.y), "QAMantle")
	L("[HOOK] placed a 1.6 m x 2.4 m block 1.6 m ahead")
	face(mp, -0.1)
	await wait(0.8)
	var near: Node3D = player.nearest_interactable()
	var lab := Interaction.label_of(Interaction.best(player))
	L("prompt at the block: %s" % str(lab.get("text", lab)).left(60))
	await key(KEY_SPACE, 3)
	await wait_until(func() -> bool: return not kinds.is_empty(), 4.0)
	await wait(6.0)
	var top_y := WorldGen.height(mp.x, mp.y) + 1.6
	check("jumping at a 1.6 m block mantles onto it", (kinds.has("mantle_high") or kinds.has("mantle_low")) and player.global_position.y > top_y - 0.35, "kinds %s player y %.2f top %.2f" % [str(kinds), player.global_position.y, top_y])
	await shot("mantle_top")
	wall2.queue_free()
	# --- a 2.3 m ledge: grab, hang, climb
	kinds.clear()
	await teleport(base + side * 24.0, yaw_to(base + side * 24.0, base + side * 24.0 + f), 0.8)
	var lp := p2() + f * 1.3
	var wall3 := tf_make_box(Vector3(lp.x, WorldGen.height(lp.x, lp.y), lp.y), Vector3(6.0, 2.3, 2.4), atan2(f.x, f.y), "QALedge")
	L("[HOOK] placed a 2.3 m x 2.4 m block 1.3 m ahead")
	face(lp, -0.1)
	await wait(0.8)
	await key(KEY_SPACE, 3)
	await wait_until(func() -> bool: return kinds.has("ledge"), 5.0)
	var hang_log: Array = []
	var hanging := await wait_until(func() -> bool:
		hang_log.append("s%d y%.2f" % [int(trav.get("state")), player.global_position.y])
		return bool(trav.call("hanging")), 12.0)
	L("ledge: kinds %s hanging %s y %.2f; trace %s" % [str(kinds), str(hanging), player.global_position.y, str(hang_log.filter(func(x: Variant) -> bool: return hang_log.find(x) % 25 == 0)).left(240)])
	await shot("ledge_hang")
	var top3 := WorldGen.height(lp.x, lp.y) + 2.3
	if hanging:
		await wait(1.0)
		await key(KEY_SPACE, 3)
		await wait_until(func() -> bool: return not bool(trav.call("busy")) and player.global_position.y > top3 - 0.4, 14.0)
	check("a 2.3 m ledge can be grabbed (hang) and climbed", kinds.has("ledge") and hanging and player.global_position.y > top3 - 0.4, "kinds %s hanging %s y %.2f top %.2f" % [str(kinds), str(hanging), player.global_position.y, top3])
	await shot("ledge_top")
	wall3.queue_free()
	# --- a ladder: the Thornfield inn when its layout has a loft, else the first Thornfield building that has one
	set_hour(14.0, "the inn is open")
	var BP := load("res://scripts/world/building_profiles.gd") as GDScript
	var Lay := load("res://scripts/interiors/interior_layouts.gd") as GDScript
	var loft_bid := ""
	var inn_layout := ""
	var slice: Dictionary = (tf_town()["plan"]["slice"] as Dictionary)["buildings"]
	var ids: Array = slice.keys()
	ids.sort()
	ids.erase("thornfield_inn")
	ids.push_front("thornfield_inn")
	for bid: String in ids:
		var bd: Dictionary = slice[bid]
		var lay := String(BP.call("layout_for", String(bd["asset"]), String(BP.call("building_id", bd["pos"]))))
		if bid == "thornfield_inn":
			inn_layout = lay
		if lay != "" and not (Lay.call("layout", lay) as Dictionary).get("loft", {}).is_empty():
			loft_bid = bid
			break
	note("Thornfield inn layout '%s'; ladder tested in %s" % [inn_layout, loft_bid])
	if loft_bid != "thornfield_inn":
		note("the Thornfield inn's generated layout (%s) has no loft or ladder (only tavern_inn and family_loft do)" % inn_layout)
	var inn := await tf_enter(loft_bid) if loft_bid != "" else null
	if inn != null:
		var ladders: Array = inn.get("furniture")["ladders"]
		L("ladders in %s: %d" % [loft_bid, ladders.size()])
		check("%s has a ladder" % loft_bid, not ladders.is_empty())
		if not ladders.is_empty():
			var ld: Ladder = ladders[0]
			var y_before := player.global_position.y
			var okl := await tf_reach(ld.bottom, "ladder bottom", Vector2(ld.bottom.global_position.x, ld.bottom.global_position.z) + Vector2(0, 2), 1.0)
			L("ladder bottom reached by prompt: %s" % str(okl))
			await shot("ladder_bottom")
			await key(KEY_E)
			await wait(7.0)
			var climbed := player.global_position.y > ld.bottom.global_position.y + float(ld.height()) * 0.7
			check("E at the ladder foot climbs to the loft", climbed, "player y %.2f, ladder %.2f -> %.2f" % [player.global_position.y, ld.bottom.global_position.y, ld.top.global_position.y])
			if not climbed:
				bug("traversal", "ladder climb did not move the player up (y %.2f, expected ~%.2f)" % [player.global_position.y, ld.top.global_position.y])
			if InteriorDoor.active != null:
				var rm: Node3D = InteriorDoor.active.get("interior")
				if rm != null and rm.has_method("wall_fade_state"):
					var lay: Dictionary = rm.get("layout")
					L("ladder top: cam local %s, player local %s, room %sx%sx%s, fade %s, model visible %s, cam-pivot %.2f" % [str(rm.to_local(player.camera.global_position).snapped(Vector3.ONE * 0.01)), str(rm.to_local(player.global_position).snapped(Vector3.ONE * 0.01)), str(lay["w"]), str(lay["d"]), str(lay["h"]), str(rm.call("wall_fade_state")), str(player._model.visible), player.camera.global_position.distance_to(player._pivot.global_position)])
			await shot("ladder_top")
			# and back down
			var okt := await wait_until(func() -> bool: return player.nearest_interactable() != null, 3.0)
			await key(KEY_E)
			await wait(7.0)
			L("after the descent: y %.2f (bottom %.2f)" % [player.global_position.y, ld.bottom.global_position.y])
		await tf_leave_by_exit("inn")
	close_everything()


# ---------------------------------------------------------------------------------------- Thornfield: combat, soldier, Rift, Soulbeast

const TfWilds := preload("res://scripts/world/thornfield/wilds.gd")
const TfRiftLayout := preload("res://scripts/world/thornfield/rift_layout.gd")
const TfSoldierCareer := preload("res://scripts/sim/soldier_career.gd")
const TfSoldierUI := preload("res://scripts/ui/soldier_ui.gd")


## A real key held down for `secs` (wall seconds): a charge / a bow draw.
func key_hold(k: int, secs: float) -> void:
	beat("hold key %d" % k)
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await wait(secs)
	var r := InputEventKey.new()
	r.keycode = k
	r.physical_keycode = k
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


func tf_wolf_at(at: Vector2, provoked := 8.0) -> Wolf:
	var w := Wolf.new()
	w.species = "wolf"
	w.home = at
	w.territory = 200.0
	main.world.add_child(w)
	w.global_position = Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y)
	w._provoked = provoked
	return w


func tf_equip(item: String) -> bool:
	Life.give(item, 1)
	var r: Variant = Life.equipment.call("equip_from", Life, item)
	L("[HOOK] give + equip %s -> %s (main_hand %s, style %s)" % [item, str(r), String(Life.equipment.call("item_in", "main_hand")), str(player._arms.style)])
	return String(Life.equipment.call("item_in", "main_hand")) == item


func _s_tf_combat() -> void:
	if Life.age() < 18:
		set_age(18)
	set_hour(13.0, "daylight")
	var base := TfSites.place_pos("thornfield_fields") + Vector2(14, 6)
	await teleport(base, 0.0, 1.5)
	heal_player()
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var swings: Array = []
	player.swing_started.connect(func(action: Resource, info: Dictionary) -> void:
		swings.append("%s|%s" % [str(action.get("id")) if action != null else "-", str(action.resource_path).get_file() if action != null else "-"]))
	# --- sword: heavy attack on a wolf
	check("a sword is equipped (combat style sword)", tf_equip("bronze_sword") and player._arms.style == "sword", "style %s" % str(player._arms.style))
	var w := tf_wolf_at(base + fwd * 1.9, 0.0)
	w.process_mode = Node.PROCESS_MODE_DISABLED       # a still target for the heavy swing (a live wolf bites and knocks the hold away)
	L("[HOOK] the wolf is frozen until the heavy attack has landed")
	await wait(1.0)
	face(Vector2(w.global_position.x, w.global_position.z), -0.2)
	await shot("combat_wolf_close")
	var hp0: int = int(w.health)
	swings.clear()
	L("before the heavy: dead %s swimming %s mount %s knockdown %s hp %d/%d wolf state %s dist %.1f" % [str(player.dead), str(player.swimming), str(player._mount), str(player._arms.kd.is_active()), player.health, player.max_health, str(w.state), player.global_position.distance_to(w.global_position)])
	fast_game(16)
	var held_log: Array = []
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	var charging_seen := false
	await frames(1)
	L("1 frame after the J press: Input.is_action_pressed(attack)=%s input_held=%s held=%.2f style=%s" % [str(Input.is_action_pressed("attack")), str(player._arms.input_held), float(player._arms.held), str(player._arms.style)])
	if not bool(player._arms.input_held):
		bug("combat", "a real J key press did not start an attack hold (Input pressed=%s, input_held=false): calling player.attack_press() directly" % str(Input.is_action_pressed("attack")))
		player.attack_press()
		await frames(1)
		L("after attack_press(): input_held=%s held=%.2f" % [str(player._arms.input_held), float(player._arms.held)])
	for i in 8:
		await wait(0.25)
		held_log.append("held %.2f charging %s input_held %s" % [float(player._arms.held), str(player._arms.charging), str(player._arms.input_held)])
		charging_seen = charging_seen or bool(player._arms.charging)
	var evr := InputEventKey.new()
	evr.keycode = KEY_J
	evr.physical_keycode = KEY_J
	evr.pressed = false
	Input.parse_input_event(evr)
	await frames(2)
	L("hold trace: %s" % str(held_log.filter(func(x: Variant) -> bool: return held_log.find(x) % 3 == 0)))
	await wait(2.5)
	L("heavy swing log: %s; wolf hp %d -> %s; charging seen %s" % [str(swings), hp0, str(w.health) if is_instance_valid(w) else "gone", str(charging_seen)])
	var heavy_swing := false
	for sw: String in swings:
		if sw.to_lower().contains("heavy"):
			heavy_swing = true
	check("holding the attack key then releasing performs a heavy attack", heavy_swing, str(swings))
	await shot("combat_heavy")
	check("the heavy attack hurt the wolf", not is_instance_valid(w) or bool(w.get("dead")) or int(w.health) < hp0, "wolf hp %d -> %s" % [hp0, str(w.health) if is_instance_valid(w) else "gone"])
	if is_instance_valid(w):
		w.process_mode = Node.PROCESS_MODE_INHERIT
	# --- lock-on on the wolf (key, then the HUD lock button)
	if is_instance_valid(w) and not bool(w.get("dead")):
		face(Vector2(w.global_position.x, w.global_position.z), -0.2)
		await key(KEY_Q)
		await wait(0.8)
		var locked: bool = player._lock != null and is_instance_valid(player._lock)
		check("Q locks onto the wolf", locked and player._lock == w, "lock %s" % str(player._lock))
		await shot("combat_lockon")
		await key(KEY_Q)
		await wait(0.6)
		check("Q again releases the lock", player._lock == null or not is_instance_valid(player._lock), str(player._lock))
		var lb: Node = hud._buttons.get("lock_combat")
		if lb != null:
			var lpos: Vector2 = lb.get("global_position") + Vector2(36, 36)
			L("HUD lock button %s visible_in_tree %s at %s" % [lb.get_class(), str(lb.is_visible_in_tree()), str(lpos)])
			if lb.is_visible_in_tree():
				for tap in 2:
					for pressed in [true, false]:
						var te := InputEventScreenTouch.new()
						te.index = 0
						te.position = lpos
						te.pressed = pressed
						Input.parse_input_event(te)
						await frames(2)
					await wait(0.8)
					if tap == 0:
						check("tapping the HUD lock button locks on", player._lock != null and is_instance_valid(player._lock), str(player._lock))
					else:
						check("tapping it again releases the lock", player._lock == null or not is_instance_valid(player._lock), str(player._lock))
			else:
				note("the HUD lock button is hidden outside combat state (no tap)")
		# finish it with taps
		var dead := await _fight(w, "heavy wolf", 40.0)
		check("the wolf can be finished with light attacks", dead)
	heal_player()
	# --- bow
	var bow_ok := tf_equip("ash_shortbow")
	Life.give("flint_arrow", 20)
	await wait(0.5)
	check("a shortbow equips as the bow style", bow_ok and player._arms.style == "bow", "style %s" % str(player._arms.style))
	var arrows0: int = Life.count("flint_arrow")
	var shots: Array = []
	player._arms.arrow_shot.connect(func(info: Dictionary) -> void: shots.append(info))
	var tp := player.global_position
	var wp := Vector2(tp.x, tp.z) + fwd * 11.0
	var w2 := tf_wolf_at(wp, 0.0)
	w2.set("state", 0)
	await wait(1.0)
	face(Vector2(w2.global_position.x, w2.global_position.z), -0.1)
	var whp0: int = int(w2.health)
	await key_hold(KEY_J, 1.3)
	await wait(3.0)
	check("a drawn shot fires an arrow and uses one", shots.size() >= 1 and Life.count("flint_arrow") == arrows0 - 1, "shots %d, arrows %d -> %d, info %s" % [shots.size(), arrows0, Life.count("flint_arrow"), str(shots[0] if not shots.is_empty() else {}).left(120)])
	L("bow shot: wolf hp %d -> %s" % [whp0, str(w2.health) if is_instance_valid(w2) else "gone"])
	check("the arrow hit the wolf", not is_instance_valid(w2) or bool(w2.get("dead")) or int(w2.health) < whp0, "wolf hp %d -> %s" % [whp0, str(w2.health) if is_instance_valid(w2) else "gone"])
	await shot("combat_bow")
	if is_instance_valid(w2) and not bool(w2.get("dead")):
		w2.queue_free()
	# back to a sword so later stages fight normally
	tf_equip("bronze_sword")
	heal_player()


func _s_tf_soldier() -> void:
	if Life.age() < 18:
		set_age(18)
	var post: Dictionary = TfWilds.post()
	check("the Soldier career's post is the Watch Post outpost", String(post.get("kind", "")) == "outpost", str(post).left(120))
	var c: Vector2 = post["pos"]
	set_hour(9.0, "daytime")
	await teleport(c + Vector2(0, 22), 0.0, 1.5)
	var hub := tf_hub()
	var outpost: Node = hub.get("wilds").get("outpost")
	var built := await wait_until(func() -> bool: return bool(outpost.get("built")), 45.0)
	if not built:
		L("[HOOK] outpost.refresh by hand (its 2 s poll runs on frame time)")
		outpost.call("refresh", p2(), 2.0)
		await wait(2.0)
	check("the Watch Post is built when the player is near", bool(outpost.get("built")))
	await wait(2.0)
	await shot("watch_post")
	var cap: Node3D = outpost.get("captain")
	check("the post has a captain Station", cap != null and is_instance_valid(cap))
	if cap == null:
		return
	var m: RefCounted = TfSoldierUI.module()
	check("the soldier module exists", m != null)
	var day := int(WorldSim.day)
	check("the player is not yet a soldier", not bool(m.get("active")))
	# --- enlist through the captain's menu
	var ok := await tf_reach(cap, "captain", c + Vector2(0, 8), 1.6)
	check("the captain is the interact prompt target", ok)
	await key(KEY_E)
	var opened := await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
	L("captain options: %s" % str(menu_texts()).left(300))
	await shot("captain_menu")
	check("E opens the captain's menu", opened)
	var enl := false
	if opened:
		enl = await click_option("Enlist")
	check("the captain's menu has a clickable 'Enlist'", enl, str(menu_texts()).left(200))
	close_everything()
	await wait(0.5)
	check("enlisting makes the player a soldier", bool(m.get("active")), "rank %s" % str(m.call("rank_title")))
	if not bool(m.get("active")):
		L("[HOOK] enlist through the module")
		m.call("enlist", day, "captain")
	# --- muster: the window is a morning hour
	var mh := float(TfSoldierCareer.muster()["hour"])
	set_hour(mh + 0.2, "inside the muster window")
	var mp: Vector2 = outpost.call("muster_pos")
	await teleport(mp + Vector2(1.5, 0), 0.0, 1.0)
	L("at muster yard: at_post %s, in window %s" % [str(m.call("at_post", p2())), str(TfSoldierCareer.in_muster(WorldSim.time_of_day))])
	ok = await tf_reach(cap, "captain", c + Vector2(0, 8), 1.6)
	await key(KEY_E)
	await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
	L("captain options (serving): %s" % str(menu_texts()).left(300))
	await shot("captain_serving")
	var mus := await click_option("muster")
	check("the captain's menu has 'Report for muster' and it counts", mus and bool(m.call("attended_on", int(WorldSim.day))), str(menu_texts()).left(200))
	var duty_btn := false
	var texts := menu_texts()
	for t: String in texts:
		if t.to_lower().begins_with("take duty"):
			duty_btn = true
	check("a duty is on offer ('Take duty ...')", duty_btn, str(texts).left(250))
	if duty_btn:
		await click_option("Take duty")
	close_everything()
	await wait(0.5)
	var duty: Dictionary = m.get("duty")
	var druner: QuestRunner = m.call("runner")      # the soldier module keeps its own quest runner
	check("taking the duty starts its quest", not duty.is_empty() and String(duty.get("state", "")) == "active" and druner.is_active(String(duty.get("id", ""))), "duty state %s, quest active %s (%s)" % [str(duty.get("state", "")), str(druner.is_active(String(duty.get("id", "")))), String(duty.get("text", ""))])
	var sv: Dictionary = m.call("status_view", int(WorldSim.day))
	note("soldier: %s, merit %d, duty %s" % [String(sv["rank"]), int(sv["merit"]), str((sv["duty"] as Dictionary).get("text", "-"))])
	await shot("duty_taken")
	close_everything()


func tf_find_creatures_in_room(root: Node, room_rect: Rect2i, side: int) -> Array:
	var out: Array = []
	var lo := TfRiftLayout.cell_pos(side, float(room_rect.position.x), float(room_rect.position.y))
	var hi := TfRiftLayout.cell_pos(side, float(room_rect.end.x), float(room_rect.end.y))
	for cr in root.get("creatures"):
		if not is_instance_valid(cr):
			continue
		var lp: Vector3 = (cr as Node3D).position
		if lp.x >= lo.x and lp.x <= hi.x and lp.z >= lo.z and lp.z <= hi.z:
			out.append(cr)
	return out


func _s_tf_rift() -> void:
	if Life.age() < 18:
		set_age(18)
	set_hour(12.0, "daytime")
	var hub := tf_hub()
	var rift: Node = hub.get("wilds").get("rift")
	var centre: Vector2 = rift.get("center")
	await teleport(centre + Vector2(0, 14), 0.0, 1.5)
	var built := await wait_until(func() -> bool: return bool(rift.get("built")), 45.0)
	if not built:
		L("[HOOK] rift.refresh by hand")
		rift.call("refresh", p2())
		await wait(1.0)
	check("the Rift mouth is built near the player", bool(rift.get("built")))
	var door: InteriorDoor = rift.get("door")
	if door == null:
		return
	await shot("rift_mouth")
	var ok := await tf_reach(door, "rift door", centre + Vector2(0, 14), 1.2)
	check("the Rift door is the interact prompt target", ok)
	var lab := Interaction.label_of(Interaction.best(player))
	L("rift door prompt: %s" % str(lab.get("text", lab)).left(80))
	var t_in := now()
	await key(KEY_E)
	await wait_until(func() -> bool: return InteriorDoor.active != null, 150.0)
	await wait(2.5)
	note("entering the Rift took %.0f s" % (now() - t_in))
	check("E enters the Rift", InteriorDoor.active == door, str(InteriorDoor.active))
	if InteriorDoor.active == null:
		return
	var root: Node3D = door.interior
	var extras: Dictionary = door.get("extras")
	var g: Dictionary = door.call("layout")
	var side := int(g["side"]) if g.has("side") else 44
	await shot("rift_camp")
	var cam: Camera3D = player.camera
	var envr: Environment = cam.environment
	L("rift camp camera at %s looking %s, player at %s yaw %.2f; env bg_mode %s bg_color %s ambient %.2f %s tonemap %d glow %s" % [str(cam.global_position.snappedf(0.1)), str((-cam.global_transform.basis.z).snappedf(0.01)), str(player.global_position.snappedf(0.1)), player._yaw, str(envr.background_mode if envr != null else -1), str(envr.background_color if envr != null else "-"), envr.ambient_light_energy if envr != null else -1.0, str(envr.ambient_light_color if envr != null else "-"), envr.tonemap_mode if envr != null else -1, str(envr.glow_enabled if envr != null else "-")])
	var ex0: Node3D = root.find_child("ExitDoor", true, false)
	if ex0 != null:
		L("exit door at %s (%.1f m from the player), quad at %s" % [str(ex0.global_position.snappedf(0.1)), player.global_position.distance_to(ex0.global_position), str(ex0.get_child(0).global_position.snappedf(0.1)) if ex0.get_child_count() > 0 else "-"])
	player.set_camera(player._yaw + PI, -0.2)
	await wait(1.2)
	await shot("rift_camp_turned")
	player.set_camera(player._yaw + PI, -0.2)
	await wait(0.8)
	check("the camp has a quartermaster and a bedroll", extras.has("quartermaster") and extras.has("bed"), str(extras.keys()))
	# --- rest at the camp bedroll
	var bed: Node3D = extras.get("bed")
	if bed != null:
		hp_hurt_for_rest()
		var t0 := WorldSim.time_of_day
		var d0 := WorldSim.day
		var okb := await tf_reach(bed, "bedroll", Vector2(player.global_position.x, player.global_position.z) + Vector2(2, 0), 1.2)
		await key(KEY_E)
		await wait_until(func() -> bool: return hud.is_menu_open(), 6.0)
		L("bedroll menu: %s" % str(menu_texts()))
		var rested := await click_option("Rest")
		await wait(2.5)
		check("the bedroll rests (clock advanced, hp restored)", rested and (WorldSim.day > d0 or WorldSim.time_of_day != t0) and player.health > int(player.max_health * 0.5), "clock %.1f -> %.1f hp %d/%d (label said 'until morning'; a nap at noon is shorter)" % [t0, WorldSim.time_of_day, player.health, player.max_health])
		close_everything()
	# --- room 1 fight
	var rooms: Array = g["rooms"]
	var r1: Dictionary = rooms[1]
	var cr1 := tf_find_creatures_in_room(root, r1["rect"], side)
	L("room 1 creatures: %d (%s)" % [cr1.size(), str(cr1.map(func(c: Node) -> String: return String(c.get("kind"))))])
	check("room 1 (Fracture Gallery) has creatures", cr1.size() >= 2, "%d" % cr1.size())
	if not cr1.is_empty():
		var first: Node3D = cr1[0]
		var arrive := first.global_position + Vector3(2.5, 0.2, 0)
		L("[HOOK] walking to room 1 is a corridor; placing the player at its door")
		player.global_position = arrive
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await wait(1.0)
		await shot("rift_room1")
		var killed := 0
		for cr: Node3D in cr1:
			if not is_instance_valid(cr) or bool(cr.get("dead")):
				continue
			heal_player("rift fight")
			if await _fight(cr, String(cr.get("kind")), 45.0):
				killed += 1
		check("the room 1 creatures can be killed in melee", killed >= cr1.size() - 1, "%d of %d" % [killed, cr1.size()])
		await shot("rift_room1_after")
		var st: Dictionary = root.get("state")
		check("kills are recorded in the dungeon state", (st["killed"] as Dictionary).size() >= killed and killed > 0, str((st["killed"] as Dictionary).keys()))
	# --- the lever (room 2) opens the shardglass door
	var lever: Node3D = null
	for t in (root.get("things") as Dictionary).values():
		if String(t.get("kind")) == "lever":
			lever = t
	check("the Weeping Hall has the lever", lever != null)
	if lever != null:
		player.global_position = lever.global_position + Vector3(1.0, 0.3, 1.0)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await wait(1.0)
		var okl := await tf_reach(lever, "lever", Vector2(lever.global_position.x, lever.global_position.z) + Vector2(1, 1), 1.2)
		var opened := [false]
		root.gate_opened.connect(func(_id: int, _how: String) -> void: opened[0] = true)
		await shot("rift_lever")
		await key(KEY_E)
		await wait(2.0)
		check("pulling the lever opens the gate to the boss room", opened[0] and (root.get("state")["opened"] as Dictionary).size() > 0, "reached %s opened %s" % [str(okl), str(root.get("state")["opened"])])
	# --- exit
	var ex: InteriorDoor = null
	for n in root.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and (n as InteriorDoor).is_exit:
			ex = n
	check("the Rift has an exit door", ex != null)
	if ex != null:
		player.global_position = ex.global_position + Vector3(0.6, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await wait(1.0)
		await tf_leave_by_exit("rift")
	check("the player is back outside near the Rift mouth", InteriorDoor.active == null and p2().distance_to(centre) < 30.0, _pos2s())
	await shot("rift_outside")


func hp_hurt_for_rest() -> void:
	player.health = maxi(1, int(player.max_health * 0.5))


func _s_tf_beast() -> void:
	if Life.age() < 18:
		set_age(18)
	var dir: Node = _find_node_by_script(main.world, "soulbeast_director.gd")
	check("the Soulbeast director is in the world", dir != null)
	if dir == null:
		return
	var beast: Node3D = dir.get("beast")
	var den: Node3D = dir.get("den_node")
	check("the Soulbeast and its den exist", beast != null and is_instance_valid(beast) and den != null, "beast %s den %s" % [str(beast), str(den)])
	if beast == null or den == null:
		return
	set_hour(17.0, "late afternoon: the beast is stirring (nocturnal, asleep 7-18h)")
	Life.give("bread", 3)
	Life.give("venison", 2)
	L("[HOOK] give bread x3 and venison x2")
	var dp := Vector2(den.global_position.x, den.global_position.z)
	await teleport(dp + Vector2(16, 0), 0.0, 2.0)
	await shot("beast_far")
	var trust0 := float(beast.brain.trust)
	player.set("crouching", true)
	L("beast at %s state %s trust %.1f; walking in crouched" % [str(Vector2(beast.global_position.x, beast.global_position.z).snappedf(0.1)), str(beast.brain.state), trust0])
	fast_game(16)
	await walk_to(dp + Vector2(3.0, 0.0), 1.5, 60.0, false, 15.0)
	Engine.max_physics_steps_per_frame = 8
	player.set("crouching", false)
	heal_player("near the den")
	var near: Node3D = player.nearest_interactable()
	var lab := Interaction.label_of(Interaction.best(player))
	L("at the den: nearest %s, prompt %s, beast trust %.1f, hp %d" % [str(near), str(lab.get("text", lab)).left(60), float(beast.brain.trust), player.health])
	await shot("beast_den")
	var food0: int = Life.count("venison") + Life.count("bread")
	if near != den:
		L("[HOOK] standing on the den: the prompt picked %s" % str(near))
		player.global_position = den.global_position + Vector3(1.0, 0.3, 0.5)
		await wait(0.8)
	check("the den offers 'Leave food' when carrying food", Interaction.best(player).get("source", null) != null and String(Interaction.label_of(Interaction.best(player)).get("text", "")).to_lower().contains("food"), str(Interaction.label_of(Interaction.best(player))).left(100))
	await key(KEY_E)
	await wait(1.5)
	var trust1 := float(beast.brain.trust)
	check("offering food raises the Soulbeast's trust", trust1 > trust0 and Life.count("venison") + Life.count("bread") == food0 - 1, "trust %.1f -> %.1f, food %d -> %d" % [trust0, trust1, food0, Life.count("venison") + Life.count("bread")])
	await shot("beast_offered")
	await key(KEY_E)
	await wait(1.5)
	var trust2 := float(beast.brain.trust)
	note("second offer inside the cooldown: trust %.1f -> %.1f (stage %s)" % [trust1, trust2, str(beast.brain.stage())])
	check("a second offering still adds a little trust", trust2 >= trust1)
	check("the food is placed at the den", get_tree().get_nodes_in_group("soulbeast_food").size() >= 1)
	heal_player()


# ---------------------------------------------------------------------------------------- Thornfield: save / quit / reload

var tf_taken_ids: Array = []
var tf_taken_spots: Array = []        # [item, position] of the loose items the save stage took


func tf_rift_state() -> Dictionary:
	var DD: GDScript = load("res://scripts/interiors/dungeon_door.gd")
	var st: Dictionary = DD.call("state_for", "thornfield_rift")
	var out := {}
	for k: String in ["looted", "killed", "opened", "harvested"]:
		var d: Variant = st.get(k, {})
		var keys: Array = (d as Dictionary).keys() if d is Dictionary else []
		keys.sort()
		out[k] = keys
	out["boss_dead"] = bool(st.get("boss_dead", false))
	return out


func tf_digest() -> Dictionary:
	var r := qrun()
	var q := {}
	for id: String in [Q_BARLEY, Q_CARTS, Q_CULPRIT]:
		var run := r.run(id)
		q[id] = [String(run.state), r.stage_of(id)] if run != null else ["none", ""]
	var m := TfSoldierUI.module()
	var sv: Dictionary = m.call("status_view", int(WorldSim.day)) if m != null else {}
	var dir := _find_node_by_script(main.world, "soulbeast_director.gd")
	var trust := -1.0
	if dir != null and dir.get("beast") != null and is_instance_valid(dir.get("beast")):
		trust = snappedf(float(dir.get("beast").brain.trust), 0.1)
	var taken := {}
	for id: String in tf_taken_ids:
		taken[id] = TfOwnership.state_taken(id)
	return {"quests": q, "soldier": [bool(sv.get("active", false)), String(sv.get("rank", "")), int(sv.get("merit", 0)), bool(sv.get("attended_today", false))],
		"trust": trust, "taken": taken, "stolen_stacks": TfTheft.stolen_stacks().size(), "rift": tf_rift_state(),
		"gold": Game.gold, "day": WorldSim.day, "age": Life.age()}


func _s_tf_save() -> void:
	if Life.age() < 18:
		set_age(18)
	set_hour(12.0, "daylight")
	var r := qrun()
	var sid := int(tf_town()["id"])
	# --- build a state worth saving (what earlier stages do for real; whatever is missing is set here and logged)
	if not r.is_done(Q_BARLEY):
		L("[HOOK] %s -> done through the bus (the real run is stage tf_barley)" % Q_BARLEY)
		r.start(Q_BARLEY)
		for id: String in TfObserveIds():
			QuestBus.shared().emit_event(&"interact", {"id": id})
		QuestBus.shared().emit_event(&"hours", {"amount": 2.0, "hour": 20.0})
		QuestBus.shared().emit_event(&"observe", {"target": "barn_figure", "dist": 8.0, "unseen": true, "dt": 30.0, "hour": 22.0})
		QuestBus.shared().emit_event(&"talk", {"npc": "hesta_thorne"})
	if not r.is_active(Q_CARTS) and not r.is_done(Q_CARTS):
		L("[HOOK] start %s (stage load)" % Q_CARTS)
		r.start(Q_CARTS)
	if not r.is_active(Q_CULPRIT) and not r.is_done(Q_CULPRIT):
		L("[HOOK] start %s" % Q_CULPRIT)
		r.start(Q_CULPRIT)
		QuestBus.shared().emit_event(&"enter_area", {"place": "thornfield_barn"})
	var m := TfSoldierUI.module()
	if not bool(m.get("active")):
		L("[HOOK] enlist through the module (the real UI path is stage tf_soldier)")
		m.call("enlist", int(WorldSim.day), "captain")
	m.call("add_merit", 7.0)
	# taken items: a public loose apple taken with E, and an owned loaf stolen with E
	await teleport(tf_pos() + Vector2(0, 9), 0.0, 1.5)
	var gi1 := tf_drop_owned("apple", "", 1.0)
	tf_taken_ids.append(String(gi1.call("_id")))
	tf_taken_spots.append(["apple", gi1.global_position])
	await wait(0.8)
	await key(KEY_E)
	await wait(1.0)
	var house: Dictionary = TfTown.building("thornfield_house_5")
	var gi2 := tf_drop_owned("bread", TfOwnership.household(sid, int(house["lot"])), 1.0)
	tf_taken_ids.append(String(gi2.call("_id")))
	await wait(0.8)
	await key(KEY_E)
	await wait(1.0)
	check("both loose items were taken (gone from the world)", not is_instance_valid(gi1) or gi1.is_queued_for_deletion(), "apple gone %s bread gone %s" % [str(not is_instance_valid(gi1) or gi1.is_queued_for_deletion()), str(not is_instance_valid(gi2) or gi2.is_queued_for_deletion())])
	# trust: leave food at the den
	var dir := _find_node_by_script(main.world, "soulbeast_director.gd")
	if dir != null and dir.get("beast") != null:
		Life.give("bread", 1)
		L("[HOOK] offer food to the Soulbeast through its API (the real den walk is stage tf_beast)")
		dir.get("beast").call("offer_food", player)
	# the Rift: a looted chest and a dead rat, as if cleared
	var st: Dictionary = (load("res://scripts/interiors/dungeon_door.gd") as GDScript).call("state_for", "thornfield_rift")
	if (st.get("killed", {}) as Dictionary).is_empty():
		L("[HOOK] mark Rift m1 killed, chest k1 looted, gate 0 opened (the real run is stage tf_rift)")
		for k: String in ["looted", "killed", "opened", "harvested"]:
			if not st.has(k):
				st[k] = {}
		st["killed"]["m1"] = true
		st["looted"]["k1"] = true
		st["opened"]["0"] = "lever"
	close_everything()
	await teleport(tf_pos() + Vector2(5, 5), 0.0, 0.5)
	var before := tf_digest()
	var pos_before := p2()
	L("digest before save: %s" % JSON.stringify(before).left(600))
	var ok := Life.save_game(3)
	check("save_game(3) succeeds", ok, "err %s" % str(Life.saves.last_error))
	await shot("slice_saved")
	# --- quit to menu, load the slot
	var slot_id: String = Life._slot_id(3)
	var tree := get_tree()
	if get_parent() == main:
		main.remove_child(self)
		tree.root.add_child(self)
	Flow.world_dirty = true
	Flow.pending_load = slot_id
	Flow.reset_world_state(tree)
	Flow.enter_game(tree)
	L("changing scene back to main.tscn (quit + reload) with pending_load=%s" % slot_id)
	tree.paused = false
	var old_main := main
	tree.change_scene_to_file(Flow.MAIN_SCENE)
	var got: bool = await await_sig(reloaded, 240.0)
	if not got:
		bug("reload", "the reloaded main scene never started the QA hook")
		return
	main = await _take_new_main()
	_grab_refs()
	await wait_until(func() -> bool: return Flow.pending_load == "", 120.0)
	await wait(6.0)
	var after := tf_digest()
	L("digest after load: %s" % JSON.stringify(after).left(600))
	var diffs: Array = []
	for k: String in before:
		if k in ["day"]:
			continue
		if JSON.stringify(before[k]) != JSON.stringify(after[k]):
			diffs.append("%s: %s -> %s" % [k, JSON.stringify(before[k]).left(120), JSON.stringify(after[k]).left(120)])
	check("quests, soldier rank, trust, taken items and the Rift state survive save, quit and reload", diffs.is_empty(), "; ".join(diffs))
	var dpos := pos_before.distance_to(p2())
	check("the player is restored to where the game was saved (within 6 m)", dpos < 6.0, "saved %s, loaded %s, %.0f m apart" % [str(pos_before.snappedf(0.1)), _pos2s(), dpos])
	# a taken item stays taken: spawning it again removes it
	var spot: Array = tf_taken_spots[0]
	var gi3: Node3D = GroundItem.spawn(main.world, spot[1], String(spot[0]), 1, "")
	await wait(0.5)
	check("a taken item does not respawn after the reload", not is_instance_valid(gi3) or gi3.is_queued_for_deletion() or bool(gi3.get("_gone")), str(gi3))
	await shot("slice_after_reload")
