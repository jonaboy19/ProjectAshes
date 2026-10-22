extends Control
## The Lord's Council: the settlement-management screen a Steward Station
## opens (scripts/world/lord_hall.gd) once the player holds a village
## (scripts/sim/lordship.gd). Open issues as cards with decision buttons,
## projects with progress bars, the treasury and tax rate, and a small ledger
## of yesterday's income and expenses. Pauses the game, the same as
## CareerScreen and FarmLedger.
##
##   LordCouncil.open_for(hud, settlement_idx)

const Lordship := preload("res://scripts/sim/lordship.gd")
const SELF_PATH := "res://scripts/ui/lord_council.gd"

var _was_paused := false
var _box: VBoxContainer
var _settlement := -1


static func open_for(hud: CanvasLayer, settlement_idx: int) -> Control:
	var s: Control = hud.get_node_or_null("LordCouncil")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "LordCouncil"
		hud.add_child(s)
	if hud.has_method("close_menu"):
		hud.call("close_menu")
	s.call("open", settlement_idx)
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	var head := Label.new()
	head.name = "Head"
	head.add_theme_font_override("font", UITheme.title_font())
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	_box.add_child(head)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_box.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(close_screen)
	_box.add_child(close)
	get_viewport().size_changed.connect(_layout)
	_layout()


func open(settlement_idx: int) -> void:
	_settlement = settlement_idx
	if not visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
		Audio.play_ui("open")
	_refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		close_screen()


func _layout() -> void:
	var vw := get_viewport().get_visible_rect().size
	# (full-rect anchors from _ready already size this root; assigning size warned)
	var panel: Control = get_child(1)
	var w := clampf(vw.x * 0.94, 320.0, 820.0)
	var h := vw.y * 0.92
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _lordship() -> Variant:
	return Life.get("lordship")


# --- content --------------------------------------------------------------------------

func _refresh() -> void:
	var lord: Variant = _lordship()
	var content: VBoxContainer = _content()
	for c in content.get_children():
		c.queue_free()
	if lord == null or not lord.is_lord_of(_settlement):
		_box.get_node("Head").text = "Steward's Post"
		content.add_child(_body("You hold no lordship here."))
		return
	var v: Dictionary = lord.village(_settlement)
	var name := String(lord.settlement_name(_settlement))
	_box.get_node("Head").text = "The Lord's Council — %s" % name
	content.add_child(_status(lord, v))
	content.add_child(_heading("Tax rate"))
	content.add_child(_tax_row(lord, v))
	var issues: Array = v["issues"]
	content.add_child(_heading("Open matters (%d)" % issues.size()))
	if issues.is_empty():
		content.add_child(_body("Nothing needs your word today."))
	else:
		for issue: Dictionary in issues:
			content.add_child(_issue_card(lord, v, issue))
	content.add_child(_heading("Projects"))
	var projects: Array = v["projects"]
	if projects.is_empty():
		content.add_child(_body("No project under way."))
	else:
		for p: Dictionary in projects:
			content.add_child(_project_row(p))
	content.add_child(_heading("Start a project"))
	content.add_child(_project_menu(lord))
	content.add_child(_heading("Ledger (yesterday)"))
	content.add_child(_ledger_body(v))


func _status(lord: Variant, v: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_body("Population %d  ·  Treasury %dg  ·  Militia %d" % [int(v["population"]), int(v["treasury"]), int(v["militia"])]))
	box.add_child(_body("Loyalty %d / 100  ·  Food stores %d  ·  Liege opinion %+d" % [int(v["loyalty"]), int(v["food"]), int(v["liege_opinion"])]))
	var infra: Dictionary = v["infra"]
	var parts := PackedStringArray()
	for key: String in ["well", "mill", "granary", "walls", "roads"]:
		parts.append("%s %d%%" % [key.capitalize(), int(float(infra.get(key, 1.0)) * 100)])
	box.add_child(_body("Infrastructure: " + ", ".join(parts)))
	return box


func _tax_row(lord: Variant, v: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for rate: String in ["low", "fair", "harsh"]:
		var b := Button.new()
		b.text = rate.capitalize() + ("  (current)" if String(v["tax_rate"]) == rate else "")
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = String(v["tax_rate"]) == rate
		b.pressed.connect(func() -> void:
			lord.set_tax_rate(_settlement, rate)
			_refresh())
		h.add_child(b)
	return h


func _issue_card(lord: Variant, v: Dictionary, issue: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(10, Color(1, 1, 1, 0.04)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = lord.issue_title(v, issue)
	title.add_theme_color_override("font_color", UITheme.ACCENT_2)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var desc := String(lord.issue_desc(v, issue))
	if desc != "":
		col.add_child(_body(desc))
	var decisions: Array = lord.decisions_for(v, issue)
	for i in decisions.size():
		var d: Dictionary = decisions[i]
		var b := Button.new()
		b.text = String(d["label"])
		b.disabled = not bool(d.get("affordable", true))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_decide.bind(int(issue["id"]), i))
		col.add_child(b)
	return panel


func _decide(issue_id: int, choice: int) -> void:
	var lord: Variant = _lordship()
	if lord == null:
		return
	var r: Dictionary = lord.decide(_settlement, issue_id, choice)
	if bool(r.get("ok", false)):
		Game.say(String(r["text"]))
		var sphere := String(r.get("sphere", ""))
		var rep := float(r.get("reputation", 0.0))
		if sphere != "" and rep != 0.0 and Life.get("biography") != null:
			Life.biography.change_rep(sphere, rep)
		if r.has("quest_spec") and Life.get("radiant") != null:
			Life.radiant.add_lord_task(r["quest_spec"], WorldSim.day)
		if r.has("biography") and Life.get("biography") != null:
			Life.biography.add_highlight(String(r["biography"]), WorldSim.day)
	else:
		Game.say(String(r.get("text", "")))
	_refresh()


func _project_row(p: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	var kind := String(p["kind"])
	var info: Dictionary = Lordship.PROJECTS.get(kind, {})
	label.text = "%s — %d / %d days" % [String(info.get("label", kind)), int(p["total_days"]) - int(p["days_left"]), int(p["total_days"])]
	label.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = int(p["total_days"])
	bar.value = int(p["total_days"]) - int(p["days_left"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(bar)
	return box


func _project_menu(lord: Variant) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for kind: String in Lordship.PROJECTS:
		var info: Dictionary = Lordship.PROJECTS[kind]
		box.add_child(_row("%s  —  %dg, %d days" % [String(info["label"]), int(info["gold"]), int(info["days"])],
			"Start", _start_project.bind(kind)))
	return box


func _start_project(kind: String) -> void:
	var lord: Variant = _lordship()
	if lord == null:
		return
	var why := String(lord.start_project(_settlement, kind))
	Game.say(why if why != "" else "%s begins." % String(Lordship.PROJECTS[kind]["label"]))
	_refresh()


func _ledger_body(v: Dictionary) -> Control:
	var ledger: Dictionary = v.get("ledger", {})
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_body("Tax income  +%dg" % int(ledger.get("income", 0))))
	box.add_child(_body("Militia wages  -%dg" % int(ledger.get("wages", 0))))
	box.add_child(_body("Food produced  +%d  ·  consumed  -%d" % [int(ledger.get("food_produced", 0.0)), int(ledger.get("food_consumed", 0.0))]))
	return box


func _content() -> VBoxContainer:
	return _box.get_child(2).get_child(0)   # ScrollContainer -> Content


func _row(text: String, button_text: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _body(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.text = button_text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	h.add_child(b)
	return h


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.title_font_weight(600))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", UITheme.ACCENT_2)
	return l


func _body(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.TEXT)
	return l
