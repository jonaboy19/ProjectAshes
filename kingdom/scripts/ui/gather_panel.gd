extends PanelContainer
## One-thumb mobile panel for a GatherSession (scripts/sim/gather_session.gd). It reuses the work widget's
## choice buttons (scripts/ui/work_widget.gd, 54 px rows), rebuilt per step with only the legal verbs:
## Prospect -> Extract / Care / Take. Bottom-anchored, width clamps to the viewport so it fits portrait.
## Emits finished(result) exactly once (the take() result, or {"ok": false} when closed early). No _process.

signal finished(result: Dictionary)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const WorkWidget := preload("res://scripts/ui/work_widget.gd")
const GatherSession := preload("res://scripts/sim/gather_session.gd")
const MAX_W := 620.0

var session: RefCounted
var _title: Label
var _status: Label
var _taps: Label
var _widget: Control
var _box: VBoxContainer
var _done := false
var _cancel_button: Button


func setup(s: RefCounted, title: String) -> void:
	session = s
	theme = AF.theme()
	add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD, 4, 14))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -110
	var vw := get_viewport_rect().size.x if is_inside_tree() else MAX_W
	custom_minimum_size = Vector2(minf(MAX_W, maxf(240.0, vw - 32.0)), 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	_title = Label.new()
	_title.text = title
	_title.add_theme_font_size_override("font_size", 22)
	_box.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(200, 48)
	_box.add_child(_status)
	_taps = Label.new()
	_box.add_child(_taps)
	_cancel_button = Button.new()
	_cancel_button.text = "Leave gathering"
	_cancel_button.custom_minimum_size.y = 54.0
	_cancel_button.pressed.connect(cancel)
	_box.add_child(_cancel_button)
	_status.text = "Tap Prospect to read the %s." % String(s.kind)
	_rebuild()


func _options() -> Array:
	var k: Dictionary = GatherSession.KINDS[session.kind]
	var out: Array = []
	if session.phase == GatherSession.Phase.IDLE:
		out.append({"text": "Prospect", "q": 0.0, "verb": "prospect"})
		return out
	if session.can_extract():
		out.append({"text": String(k["extract"]), "q": 0.0, "verb": "extract"})
	if session.can_care():
		out.append({"text": "%s (cancels the next hazard)" % String(k["care"]), "q": 0.0, "verb": "care"})
	if session.can_take():
		out.append({"text": String(k["take"]), "q": 1.0, "verb": "take"})
	return out


func _rebuild() -> void:
	if _widget != null:
		_box.remove_child(_widget)
		_widget.queue_free()
	_taps.text = "Taps left: %d" % session.taps_left()
	var opts := _options()
	_widget = WorkWidget.new()
	_box.add_child(_widget)
	# Keep cancellation below the current activity choices after every rebuild.
	_box.move_child(_cancel_button, -1)
	(_widget as Object).call("setup", {"widget": "choice", "options": opts})
	_widget.connect("finished", _on_pick.bind(opts))


func _on_pick(_q: float, choice: int, opts: Array) -> void:
	if _done or choice < 0 or choice >= opts.size():
		return
	match String((opts[choice] as Dictionary)["verb"]):
		"prospect":
			var p: Dictionary = session.prospect()
			_status.text = "Hazard risk %d%% per strike. Expect grade ~%d, %d units here.%s" % [
				int(round(float(p["risk"]) * 100.0)), int(p["grade"]), int(p["qty"]),
				"  Dangerous for you!" if bool(p["hard"]) else ""]
		"extract":
			var e: Dictionary = session.extract()
			var t := "+%d. " % int(e.get("units", 0))
			_status.text = t + String(e.get("text", ""))
		"care":
			session.care()
			_status.text = "Steady... the next hazard will be turned aside."
		"take":
			_close(session.take())
			return
	_rebuild()


func _close(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	finished.emit(result)
	queue_free()


## Leave without taking (menu closed, player walked off): whatever was extracted is lost with the node untouched.
func cancel() -> void:
	_close({"ok": false, "count": 0, "consumed": 0})


func _unhandled_input(event: InputEvent) -> void:
	if not _done and event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
