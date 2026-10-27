extends Control
## READY_V1 C3: the "Found a camp" card. Shows what founding here would mean (water, slope, danger, the land law, food, trade),
## lets the player name the camp and confirm. Confirm -> FoundFlow.found (BuildKit.claim: grid + founding + settlement row).
## Open with the found_camp key (X), the "Found a camp" button of the build menu, or FoundCampCard.open_for(hud).
##   FoundCampCard.open_for(hud)            # at the player's feet
##   FoundCampCard.open_for(hud, Vector2)   # at a given spot (tests, the bot)

signal closed(result: Dictionary)

const SELF_PATH := "res://scripts/ui/found_camp_card.gd"
const AF := preload("res://scripts/ui/ashes_frame.gd")
const FoundFlow := preload("res://scripts/realm/found_flow.gd")
const GOOD := Color("8fcf7a")
const MID := Color("e0b84a")
const BAD := Color("d65a4a")

var pos := Vector2.ZERO
var card: Dictionary = {}
var result: Dictionary = {}
var name_edit: LineEdit
var confirm_button: Button
var _was_paused := false
var _rows_box: VBoxContainer
var _verdict: Label
var _reason: Label
var _hud: Node


static func open_for(host: Node, at := Vector2(INF, INF)) -> Control:
	var c: Control = host.get_node_or_null("FoundCampCard")
	if c == null:
		c = (load(SELF_PATH) as GDScript).new()
		c.name = "FoundCampCard"
		host.add_child(c)
	if host.has_method("close_menu"):
		host.call("close_menu")
	c.set("_hud", host)
	c.call("open", at)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	_build()


func open(at := Vector2(INF, INF)) -> void:
	if at.x == INF:
		var pl: Node3D = Life.player if Life.player != null and is_instance_valid(Life.player) else null
		at = Vector2(pl.global_position.x, pl.global_position.z) if pl != null else Vector2.ZERO
	pos = at
	card = FoundFlow.site_card(Life.realm, pos)
	result = {}
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Audio.play_ui("open")
	_verdict.text = String(card["verdict"])
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	for r: Array in card["rows"]:
		_rows_box.add_child(_row(String(r[0]), String(r[1]), float(r[2])))
	var ok := bool(card["ok"])
	_reason.visible = not ok
	_reason.text = String(card["reason"])
	name_edit.text = String(card["name"])
	name_edit.editable = ok
	confirm_button.disabled = not ok
	confirm_button.text = "Found the camp  (%d of %d left)" % [int(card["left"]), 3]
	if ok:
		name_edit.grab_focus()
		name_edit.select_all()


## Confirms with the typed name (public: the bot and the tests press this).
func confirm() -> Dictionary:
	if not visible or not bool(card.get("ok", false)):
		return {"ok": false}
	result = FoundFlow.found(Life.realm, pos, name_edit.text)
	if bool(result["ok"]):
		if _hud != null and _hud.has_method("notify"):
			_hud.notify("quest", "Camp founded", "%s. Lay foundations to build it up." % String(result["name"]))
		var T := preload("res://scripts/region1/tutorial_director.gd")
		T.tell(&"found")
		Audio.play_ui("confirm")
	else:
		_reason.visible = true
		_reason.text = String(result["reason"])
		return result
	close()
	return result


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit(result)


func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _row(label: String, text: String, score: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = GOOD if score >= 0.6 else (MID if score >= 0.35 else BAD)
	h.add_child(dot)
	var l := AF.label(label, 17, AF.GOLD_BRIGHT)
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	var t := AF.label(text, 17)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	return h


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.016, 0.012, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AF.panel(Color(0.043, 0.039, 0.035, 0.96), AF.GOLD, 5, 26))
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(AF.heading("Found a camp", 26))
	_verdict = AF.label("", 19, AF.TEXT_DIM, true)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_verdict)
	col.add_child(AF.separator())
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	col.add_child(_rows_box)
	_reason = AF.label("", 17, BAD)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_reason)
	col.add_child(AF.separator())
	col.add_child(AF.label("Name your camp", 16, AF.TEXT_DIM))
	name_edit = LineEdit.new()
	name_edit.max_length = FoundFlow.NAME_MAX
	name_edit.custom_minimum_size = Vector2(0, 40)
	name_edit.text_submitted.connect(func(_t: String) -> void: confirm())
	col.add_child(name_edit)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	col.add_child(btns)
	confirm_button = AF.gold_button("Found the camp")
	confirm_button.focus_mode = Control.FOCUS_NONE
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(func() -> void: confirm())
	btns.add_child(confirm_button)
	var no := AF.gold_button("Not here")
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(close)
	btns.add_child(no)
