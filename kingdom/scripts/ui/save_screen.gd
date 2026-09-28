extends Control
## Full-screen save/load screen: one card per slot (quicksave, 3 manual, 3
## autosave) with its thumbnail, character summary, day/time, location and
## playtime. Manual slots get a Save button; every slot with a save gets Load
## and Delete (with a confirm step). Errors from Life.saves surface as a
## message under the header.
##
## Pauses the game while open (process_mode ALWAYS), like the world map and
## the inventory screen.
##   SaveScreen.open_for(hud)

signal closed

const SaveManager := preload("res://scripts/sim/save_manager.gd")
const SELF_PATH := "res://scripts/ui/save_screen.gd"
const CARD_HEIGHT := 168
const THUMB_SIZE := Vector2(176, 99)

var _was_paused := false
var _title_font: Font
var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _confirm: ConfirmationDialog
var _confirm_id := ""


## Opens (creating on first use) the screen as a child of `host` (the HUD layer).
static func open_for(host: Node) -> Control:
	var s: Control = host.get_node_or_null("SaveScreen")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "SaveScreen"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.call("open")
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	visible = false
	_title_font = UITheme.title_font_weight(600)
	_build()


func open() -> void:
	if visible:
		refresh()
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Audio.play_ui("open")
	_status.text = ""
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- build ----------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := _label(titles, 28, UITheme.ACCENT)
	title.text = "SAVE & LOAD"
	title.add_theme_font_override("font", _title_font)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(rule)
	head.add_child(_round_button("×", 60, 34, close))

	_status = _label(col, 15, UITheme.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	_scroll.add_child(_list)

	_confirm = ConfirmationDialog.new()
	_confirm.theme = UITheme.theme()
	_confirm.title = "Delete save"
	_confirm.confirmed.connect(_on_confirm_delete)
	add_child(_confirm)


func _panel() -> StyleBoxFlat:
	var s := UITheme.panel_box(18)
	s.set_content_margin_all(14)
	s.shadow_size = 8
	return s


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _round_button(text: String, diameter: int, font_size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	var r := diameter / 2
	for pair: Array in [["normal", UITheme.BG, UITheme.STROKE], ["hover", UITheme.BG, UITheme.ACCENT.darkened(0.2)],
			["pressed", UITheme.ACCENT.darkened(0.35), UITheme.ACCENT]]:
		var sb := UITheme.pill(pair[1], pair[2], r)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override(pair[0], sb)
	b.pressed.connect(cb)
	return b


func _action_button(parent: Control, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 48)
	b.add_theme_font_size_override("font_size", 16)
	if primary:
		var acc := UITheme.ACCENT
		b.add_theme_stylebox_override("normal", UITheme.pill(acc.darkened(0.25), acc, 22))
		b.add_theme_stylebox_override("hover", UITheme.pill(acc.darkened(0.1), acc, 22))
		b.add_theme_stylebox_override("pressed", UITheme.pill(acc, Color.WHITE, 22))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, Color("1b1407"))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# --- refresh ----------------------------------------------------------------------------

func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for row: Dictionary in Life.saves.list_slots():
		_list.add_child(_build_card(row))
	_show_error(Life.saves.last_error)


func _show_error(text: String) -> void:
	_status.visible = text != ""
	_status.text = text


func _build_card(row: Dictionary) -> Control:
	var id := String(row["id"])
	var exists: bool = row["exists"]
	var kind := String(row["kind"])
	var meta: Dictionary = row["meta"]

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel())
	panel.custom_minimum_size.y = CARD_HEIGHT
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)

	# Thumbnail.
	var thumb_box := PanelContainer.new()
	thumb_box.custom_minimum_size = THUMB_SIZE
	var thumb_style := StyleBoxFlat.new()
	thumb_style.bg_color = Color(0, 0, 0, 0.4)
	thumb_style.set_corner_radius_all(10)
	thumb_style.anti_aliasing = true
	thumb_box.add_theme_stylebox_override("panel", thumb_style)
	body.add_child(thumb_box)
	var tex: Texture2D = Life.saves.load_thumbnail(id) if exists else null
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		thumb_box.add_child(tr)
	else:
		var placeholder := _label(thumb_box, 14, UITheme.TEXT_DIM)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.text = "Empty" if not exists else "No preview"

	# Text.
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	body.add_child(texts)
	var head := _label(texts, 18, UITheme.ACCENT if exists else UITheme.TEXT_DIM)
	head.add_theme_font_override("font", _title_font)
	head.text = SaveManager.slot_label(id).to_upper()
	if not exists:
		var empty_l := _label(texts, 14, UITheme.TEXT_DIM)
		empty_l.text = "No save yet." if kind != "quick" else "No quicksave yet."
	else:
		var name_line := String(meta.get("name", "Wanderer"))
		var age := int(meta.get("age", -1))
		if age >= 0:
			name_line += ", age %d" % age
		var title := String(meta.get("title", ""))
		if title != "":
			name_line += "  ·  %s" % title
		_label(texts, 16, UITheme.TEXT).text = name_line
		var day := int(meta.get("day", 1))
		var t := float(meta.get("time", 8.0))
		var when := "Day %d, %02d:%02d" % [day, int(t), int(fmod(t, 1.0) * 60.0)]
		var loc := String(meta.get("location", ""))
		if loc != "":
			when += "  ·  %s" % loc
		_label(texts, 14, UITheme.TEXT_DIM).text = when
		_label(texts, 13, UITheme.TEXT_DIM).text = "Played %s  ·  Saved %s" % [
			_fmt_playtime(float(meta.get("playtime", 0.0))), String(meta.get("saved_at_text", "")).split("T")[0]]

	# Buttons.
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(btns)
	if kind == "manual":
		_action_button(btns, "Save", not exists, _on_save.bind(id))
	if exists:
		_action_button(btns, "Load", true, _on_load.bind(id))
		var del := _action_button(btns, "Delete", false, _on_delete_pressed.bind(id))
		del.add_theme_color_override("font_color", UITheme.DANGER.lightened(0.2))
		del.add_theme_color_override("font_hover_color", UITheme.DANGER.lightened(0.35))

	return panel


static func _fmt_playtime(seconds: float) -> String:
	var mins := int(seconds) / 60
	return "%dh %02dm" % [mins / 60, mins % 60] if mins >= 60 else "%d min" % mins


# --- actions ----------------------------------------------------------------------------

func _on_save(id: String) -> void:
	var ok: bool = Life.saves.save_slot(id)
	_show_error("" if ok else Life.saves.last_error)
	refresh()


func _on_load(id: String) -> void:
	var ok: bool = Life.saves.load_slot(id)
	if ok:
		close()
	else:
		_show_error(Life.saves.last_error)
		refresh()


func _on_delete_pressed(id: String) -> void:
	_confirm_id = id
	_confirm.dialog_text = "Delete %s? This cannot be undone." % SaveManager.slot_label(id)
	_confirm.popup_centered()


func _on_confirm_delete() -> void:
	if _confirm_id == "":
		return
	var ok: bool = Life.saves.delete_slot(_confirm_id)
	_confirm_id = ""
	if not ok:
		_show_error(Life.saves.last_error)
	refresh()
