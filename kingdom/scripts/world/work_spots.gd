extends Node3D
## Job work made playable (scripts/realm/work.gd): every settlement has workplaces (smithy, farm,
## stall, gate post, ...) with real spots. Walk into one, take a shift, then walk spot to spot doing
## short tasks (tap timing, hold-and-release, choices). Routine tasks run the clock faster; problems
## run at normal speed.
##
## Cost model: no _process. A 2 s Timer checks whether the player is inside a workplace (a distance
## test against <= 15 precomputed places); only while inside does a 0.5 s Timer refresh the prompt.
## Spot markers exist only for the workplace the player stands in and are freed on leaving.

const Nameplates := preload("res://scripts/core/nameplates.gd")
const AF := preload("res://scripts/ui/ashes_frame.gd")
const Widget := preload("res://scripts/ui/work_widget.gd")
const CareerTasks := preload("res://scripts/ui/career_tasks.gd")
const SLOW := 2.0
const FAST := 0.5
const ACCEL_STEP := 0.25
const ACCEL_SECS := 0.09

var hud: Node
var _timer: Timer
var _layer: CanvasLayer
var _panel: PanelContainer
var _box: VBoxContainer
var _place: Dictionary = {}
var _dismissed := ""
var _markers: Node3D
var _marker_nodes: Dictionary = {}   # spot kind -> {disc, label}
var _busy := false
var _widget_open := false
var _last_state := ""
var _sid_cache := -1


func setup(p_hud: Node) -> void:
	hud = p_hud


func _ready() -> void:
	name = "WorkSpots"
	add_to_group("work_spots")
	_timer = Timer.new()
	_timer.wait_time = SLOW
	_timer.timeout.connect(_on_tick)
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS     # so the prompt can hide itself while a menu pauses the game
	add_child(_timer)
	_timer.start()


func _work() -> RefCounted:
	var hub: Variant = Life.get("realm")
	return hub.mod("work") if hub != null else null


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _p2(n: Node3D) -> Vector2:
	return Vector2(n.global_position.x, n.global_position.z)


func _nearest_sid(p: Vector2) -> int:
	var best := -1
	for s: Dictionary in WorldGen.settlements:
		var reach := float(s.get("radius", 60.0)) * 1.8
		if (s["pos"] as Vector2).distance_squared_to(p) < reach * reach:
			best = int(s["id"])
			break
	return best


# ------------------------------------------------------------------ polling

## True while the work widget or the "hours slip by" prompt owns the screen (realm encounters wait).
func is_modal() -> bool:
	return _widget_open or _busy


func _on_tick() -> void:
	var w := _work()
	var pl := _player()
	if w == null or pl == null or _busy:
		return
	var enc: Variant = get_parent().get("encounters") if get_parent() != null else null
	if enc != null and enc.has_method("in_session") and bool(enc.in_session()):
		if _panel != null and _panel.visible and not _widget_open:
			_hide_panel()      # a villager is talking to the player: no job prompt underneath
			_last_state = ""
		return
	# The prompt lives above the HUD (layer 18 > 10, so its buttons get clicks): a HUD menu or the pack/map screens opened
	# on top of it would be covered, so keep it hidden while any of them is open.
	if get_tree().paused or (not _widget_open and hud != null and is_instance_valid(hud) and (bool(hud.call("is_menu_open")) \
			or (hud.get_node_or_null("GameMenu") != null and bool(hud.get_node("GameMenu").visible)))):
		if _panel != null and _panel.visible:
			_hide_panel()
		return
	var p := _p2(pl)
	var sid := _nearest_sid(p)
	var place: Dictionary = w.call("workplace_at", p, sid) if sid >= 0 else {}
	if place.is_empty():
		if not _place.is_empty():
			_leave_place()
		elif bool(w.get("shift") != null and not (w.get("shift") as Dictionary).is_empty()):
			_show_away(w, p)
		return
	if _place.is_empty() or String(_place["id"]) != String(place["id"]):
		_enter_place(place)
	_refresh(w, p)


func _enter_place(place: Dictionary) -> void:
	_place = place
	_timer.wait_time = FAST
	_build_markers()


func _leave_place() -> void:
	_place = {}
	_dismissed = ""
	_timer.wait_time = SLOW
	_free_markers()
	if not _widget_open:
		_hide_panel()


func _show_away(w: RefCounted, p: Vector2) -> void:
	var sh: Dictionary = w.get("shift")
	if _widget_open:
		return
	var pl: Dictionary = {}
	for wp: Dictionary in w.call("workplaces", int(sh["sid"])):
		if String(wp["job"]) == String(sh["job"]):
			pl = wp
	if pl.is_empty():
		return
	var d := int(p.distance_to(pl["center"]))
	_prompt("On shift: %s" % String((w.call("job_def", String(sh["job"])) as Dictionary)["title"]), "Return to the workplace (%d m) to carry on." % d, [])


# ------------------------------------------------------------------ prompts

func _ensure_ui() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 18
	# parent to the game scene (root viewport), not the world SubViewport behind the HUD: clicks never reached it there
	(get_tree().current_scene if get_tree().current_scene != null else self).add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_panel = PanelContainer.new()
	_panel.theme = AF.theme()
	_panel.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD, 4, 14))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -110
	_panel.custom_minimum_size = Vector2(620, 0)
	root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)


func _hide_panel() -> void:
	_last_state = ""
	if _panel != null:
		_panel.visible = false


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


## Shows a heading, body and buttons ([[text, Callable]]). `key` avoids rebuilding an unchanged prompt.
func _prompt(title: String, body: String, buttons: Array, key := "") -> void:
	_ensure_ui()
	var k := key if key != "" else "%s|%s|%d" % [title, body, buttons.size()]
	if k == _last_state and _panel.visible:
		return
	_last_state = k
	_clear()
	_panel.visible = true
	_box.add_child(AF.heading(title, 22))
	if body != "":
		_box.add_child(AF.label(body, 18, AF.TEXT))
	for b: Array in buttons:
		var btn := AF.gold_button(String(b[0]))
		btn.add_theme_font_size_override("font_size", 18)
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(b[1])
		btn.disabled = b.size() > 2 and not bool(b[2])
		_box.add_child(btn)


func _refresh(w: RefCounted, p: Vector2) -> void:
	if _widget_open or _busy:
		return
	var sh: Dictionary = w.get("shift")
	if sh.is_empty():
		_refresh_off_shift(w)
		return
	if not (sh["pending"] as Dictionary).is_empty():
		_show_problem(w)
		return
	var t: Dictionary = w.call("current_task")
	if t.is_empty():
		_finish_shift(w)
		return
	var spot: Vector2 = w.call("spot_pos", _place, String(t["spot"]))
	var d := p.distance_to(spot)
	_highlight(String(t["spot"]))
	var head := "%s  (%d of %d)" % [String(t["label"]), int(t["step"]) + 1, int(t["of"])]
	if d <= float(w.get("SPOT_REACH")):
		_prompt(head, String(t["text"]), [["Start: %s" % String(t["label"]), _open_task]], "at:%s" % String(t["id"]))
	else:
		var label := _spot_label(String(t["spot"]))
		_prompt(head, "Go to the %s, %d m away." % [label.to_lower(), int(d)], [], "go:%s:%d" % [String(t["id"]), int(d / 3.0)])


func _spot_label(kind: String) -> String:
	for s: Dictionary in _place.get("spots", []):
		if String(s["kind"]) == kind:
			return String(s["label"])
	return kind


func _refresh_off_shift(w: RefCounted) -> void:
	var job := String(_place["job"])
	var jd: Dictionary = w.call("job_def", job)
	var day := int(WorldSim.day)
	var why: String = w.call("start_refusal", job, WorldSim.time_of_day, day)
	var pw: Dictionary = w.call("player_work")
	var mine := bool(pw["employed"]) and String(pw["job"]) == job
	# Walking past a workplace shouldn't open a menu: strangers only get the
	# offer when they step right up to one of its work spots (<= 4 m).
	if not mine:
		var pl := _player()
		var near := false
		if pl != null:
			var pp := _p2(pl)
			for s: Dictionary in _place.get("spots", []):
				if (s["pos"] as Vector2).distance_squared_to(pp) < 16.0:
					near = true
					break
		if not near:
			_hide_panel()
			return
	var who := String(w.call("employer_name", int(_place["sid"]), job, day)) if not mine else String(pw["employer"])
	var body := ""
	var board: Array = w.call("board", int(_place["sid"]), job, day)
	if not board.is_empty():
		body = "Work orders today:\n" + "\n".join((board.map(func(o: Dictionary) -> String: return "- " + String(o["text"]))))
	body += "\n%s%s" % [who, " is expecting you." if mine else " will pay for a day's work by the task."]
	if why != "":
		body += "\n" + why
	if _dismissed == String(_place["id"]):
		_hide_panel()
		return
	var btns: Array = [[("Begin your shift" if mine else "Ask for a day's work"), _begin, why == ""], ["Not now", _dismiss]]
	_prompt("%s: %s" % [_sname(int(_place["sid"])), String(jd["title"])], body, btns, "off:%s:%s" % [why, String(_place["id"])])


func _sname(sid: int) -> String:
	return String(WorldGen.settlements[sid]["name"]) if sid >= 0 and sid < WorldGen.settlements.size() else "the road"


func _dismiss() -> void:
	_dismissed = String(_place.get("id", ""))
	_hide_panel()


func _begin() -> void:
	var w := _work()
	var r: Dictionary = w.call("begin", String(_place["job"]), int(_place["sid"]), int(WorldSim.day), WorldSim.season, WorldSim.time_of_day)
	_last_state = ""
	if not bool(r["ok"]):
		_toast(String(r["reason"]))
		return
	_refresh(w, _p2(_player()))


func _open_task() -> void:
	var w := _work()
	var t: Dictionary = w.call("current_task")
	if t.is_empty():
		return
	_widget_open = true
	_ensure_ui()
	# The scribe's copy / seal-comparison / ledger tasks are full mini-tasks (scribe.gd) on their own screen.
	if String(t.get("rich", "")) != "" and _open_rich(String(t["rich"])):
		return
	_last_state = "widget"
	_clear()
	_panel.visible = true
	_box.add_child(AF.heading(String(t["label"]), 22))
	_box.add_child(AF.label(String(t["text"]), 18, AF.TEXT))
	var wd := Widget.new()
	wd.setup(t)
	wd.finished.connect(_on_task_done)
	_box.add_child(wd)


## Opens the full-screen scribe task; its quality comes back like any widget's. False when the player
## has no standing for it (freelancers copy only), so the plain widget is used instead.
func _open_rich(kind: String) -> bool:
	var screen: Control = CareerTasks.open_rich(_layer, kind)
	if screen == null:
		return false
	_last_state = "widget"
	_hide_panel()
	var done := [false]
	screen.task_done.connect(func(q: float, _res: Dictionary) -> void:
		done[0] = true
		_on_task_done(q, -1))
	screen.closed.connect(func() -> void:
		if not done[0]:
			var hub: Variant = Life.get("realm")
			if hub != null:
				hub.mod("scribe").call("abandon_task")
			_widget_open = false
			_last_state = "")
	return true


func _on_task_done(q: float, choice: int) -> void:
	_widget_open = false
	var w := _work()
	var r: Dictionary = w.call("resolve_task", q, choice)
	_flush_gold(w)
	if not bool(r["ok"]):
		return
	_toast("%s: %s" % [String(r["label"]), _grade(float(r["quality"]))])
	_last_state = ""
	if float(r["hours"]) > 0.0:
		await _accelerate(float(r["hours"]))
	_refresh(w, _p2(_player()))


func _grade(q: float) -> String:
	return "masterful" if q >= 0.9 else ("well done" if q >= 0.7 else ("passable" if q >= 0.45 else "botched"))


## Routine work: run the clock in small steps so hourly listeners still fire.
func _accelerate(hours: float) -> void:
	_busy = true
	_prompt("Working...", "The hours slip by.", [], "busy")
	var steps := maxi(1, int(ceil(hours / ACCEL_STEP)))
	for i in steps:
		WorldSim.advance_hours(hours / float(steps))
		await get_tree().create_timer(ACCEL_SECS).timeout
	_busy = false


func _show_problem(w: RefCounted) -> void:
	var p: Dictionary = w.call("pending_problem")
	if p.is_empty():
		return
	_widget_open = true
	_ensure_ui()
	_last_state = "problem"
	_clear()
	_panel.visible = true
	_box.add_child(AF.heading("Trouble", 22))
	_box.add_child(AF.label(String(p["text"]), 18, AF.TEXT))
	var wd := Widget.new()
	var opts: Array = (p["options"] as Array).map(func(o: Dictionary) -> Dictionary:
		return {"text": o["text"], "q": o["q"], "tip": o.get("tip", 0), "regard": o.get("regard", 0.0)})
	wd.setup({"widget": "choice", "options": opts})
	wd.finished.connect(_on_problem_done)
	_box.add_child(wd)


func _on_problem_done(_q: float, choice: int) -> void:
	_widget_open = false
	var w := _work()
	var r: Dictionary = w.call("resolve_problem", choice)
	_flush_gold(w)
	if not bool(r["ok"]):
		return
	var cu: Dictionary = r["callup"]
	if not cu.is_empty():
		_toast("Word will spread; someone may ask for your help.")
	_last_state = ""
	_refresh(w, _p2(_player()))


func _finish_shift(w: RefCounted) -> void:
	var r: Dictionary = w.call("finish", {"careers": Life.careers, "attendance_auto": true})
	_flush_gold(w)
	if not bool(r["ok"]):
		return
	var body := "%s\nQuality %d%%.  Earned %dg." % [String(r["comment"]), int(float(r["quality"]) * 100.0), int(r["gold"])]
	if not (r["order"] as Dictionary).is_empty():
		body += "\nOrder filled: " + String((r["order"] as Dictionary)["text"])
	_free_markers()
	_build_markers()
	_prompt("Shift done", body, [["Good", _hide_panel]], "done")
	Game.say(String(r["comment"]))


func _flush_gold(w: RefCounted) -> void:
	var g := int(w.call("take_pending_gold"))
	if g != 0:
		Game.add_gold(g)


func _toast(text: String) -> void:
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", text)


# ------------------------------------------------------------------ markers (only while inside a workplace)

func _build_markers() -> void:
	_free_markers()
	if _place.is_empty():
		return
	_markers = Node3D.new()
	add_child(_markers)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.05
	disc.radial_segments = 16
	disc.rings = 1
	for s: Dictionary in _place["spots"]:
		var p: Vector2 = s["pos"]
		var root := Node3D.new()
		root.position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.08, p.y)
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var lab := Label3D.new()
		lab.text = String(s["label"])
		Nameplates.style(lab, Color("f0e0b0"), 28)
		lab.position.y = 1.6
		root.add_child(lab)
		_markers.add_child(root)
		_marker_nodes[String(s["kind"])] = {"mat": mat, "label": lab}


func _highlight(kind: String) -> void:
	for k: String in _marker_nodes:
		var e: Dictionary = _marker_nodes[k]
		var on := k == kind
		(e["mat"] as StandardMaterial3D).albedo_color = Color(AF.GOLD_BRIGHT.r, AF.GOLD_BRIGHT.g, AF.GOLD_BRIGHT.b, 0.7) if on else Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.2)


func _free_markers() -> void:
	if _markers != null and is_instance_valid(_markers):
		_markers.queue_free()
	_markers = null
	_marker_nodes.clear()


# ------------------------------------------------------------------ driver hook (tests / screenshots)

## Begin a shift at (job, sid) and open the first task's widget immediately.
func debug_present(job: String, sid: int, to_task := 0) -> void:
	var w := _work()
	var places: Array = w.call("workplaces", sid)
	for pl: Dictionary in places:
		if String(pl["job"]) == job:
			_place = pl
	w.call("begin", job, sid, int(WorldSim.day), WorldSim.season, maxf(WorldSim.time_of_day, 9.0))
	for i in to_task:
		w.call("resolve_task", 0.8, 0)
	_build_markers()
	_open_task()
