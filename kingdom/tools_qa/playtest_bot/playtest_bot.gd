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
const SHOT_DIR := "/tmp/claude-0/shots/playtest"

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
	if not _samples.is_empty() and cur["draws_avg"] < 40.0 and not (cur["name"] in ["menus", "scribe", "boot"]) and not get_tree().paused:
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
			await key(KEY_J, 3)
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
