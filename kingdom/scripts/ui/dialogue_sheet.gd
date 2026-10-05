extends Control
## The in-world conversation: a compact bottom sheet (lower ~35% of the screen) that leaves the world visible
## and running (docs/design/FOUNDATION_PLAN.md F4). Same page dict and signals as dialogue_ui.gd, so HUD feeds
## either one from the same menu source; only the presentation differs. dialogue_ui.gd stays the full-screen
## conversation for the cases that need it (shop / trade screens are plain menus and stay full-screen).
##
## Layout: portrait = one column (name, line, choices); landscape = line on the left, choices on the right.
## Choices are >= 52 px tall tap targets (1-9 keys, arrows + Enter, Esc to leave).

signal option_picked(index: int)
signal leave_requested

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

const SHEET_TOP := 0.65          # fraction of the screen height where the sheet starts (lower 35%)
const CHOICE_H := 52.0
const MARGIN := 10.0

var _panel: PanelContainer
var _split: BoxContainer
var _name_label: Label
var _role_label: Label
var _rel_label: Label
var _line: Label
var _line_scroll: ScrollContainer
var _choices_box: VBoxContainer
var _choices_scroll: ScrollContainer
var _leave: Button
var _buttons: Array[Button] = []
var _enabled: Array[bool] = []
var _sel := 0
var _present_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # the world above the sheet stays touchable / visible
	theme = AF.theme()
	visible = false
	_build()
	resized.connect(_layout)
	_layout()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = SHEET_TOP
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := HudArt.card_box(0.93, 12)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_split = BoxContainer.new()
	_split.add_theme_constant_override("separation", 12)
	_panel.add_child(_split)
	# Speaker + line.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	_split.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", AF.wfont(700))
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	head.add_child(_name_label)
	_role_label = Label.new()
	_role_label.add_theme_font_override("font", AF.font(AF.ITALIC_FONT))
	_role_label.add_theme_font_size_override("font_size", 16)
	_role_label.add_theme_color_override("font_color", AF.TEXT_DIM)
	_role_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_role_label)
	_rel_label = Label.new()
	_rel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rel_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_rel_label.add_theme_font_override("font", AF.font(AF.ITALIC_FONT))
	_rel_label.add_theme_font_size_override("font_size", 15)
	_rel_label.add_theme_color_override("font_color", AF.TEXT_DIM)
	head.add_child(_rel_label)
	_line_scroll = ScrollContainer.new()
	_line_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_line_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_line_scroll)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.add_theme_font_override("font", AF.font())
	_line.add_theme_font_size_override("font_size", 20)
	_line.add_theme_color_override("font_color", HudArt.IVORY)
	_line_scroll.add_child(_line)
	# Choices + Leave.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_child(right)
	_choices_scroll = ScrollContainer.new()
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choices_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_choices_scroll)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 5)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_scroll.add_child(_choices_box)
	_leave = Button.new()
	_leave.flat = true
	_leave.text = "Leave"
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.custom_minimum_size = Vector2(0, 44)
	_leave.add_theme_font_override("font", AF.font())
	_leave.add_theme_font_size_override("font_size", 17)
	_leave.add_theme_color_override("font_color", AF.TEXT_DIM)
	_leave.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	_leave.pressed.connect(func() -> void: leave_requested.emit())
	right.add_child(_leave)


## Portrait: stacked. Landscape: line left, choices right.
func _layout() -> void:
	if _split == null:
		return
	var s := get_viewport_rect().size if not is_inside_tree() or size.x < 2.0 else size
	_split.vertical = s.y > s.x
	if _line_scroll:
		_line_scroll.custom_minimum_size.y = 56.0 if _split.vertical else 0.0


func set_page(data: Dictionary) -> void:
	_name_label.text = String(data.get("speaker", data.get("title", "")))
	var role := String(data.get("role", ""))
	_role_label.text = role
	_role_label.visible = role != ""
	_line.text = AF.typographic(String(data.get("line", data.get("body", ""))))
	_line_scroll.scroll_vertical = 0
	var rel := String(data.get("relationship", ""))
	_rel_label.text = rel
	_rel_label.visible = rel != ""
	_build_choices(data.get("options", []))


func present() -> void:
	if _present_tween and _present_tween.is_running():
		_present_tween.kill()
	modulate.a = 0.0
	_present_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_present_tween.tween_property(self, "modulate:a", 1.0, 0.2)


func _build_choices(options: Array) -> void:
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_enabled.clear()
	for i in options.size():
		var opt: Array = options[i]
		var ok: bool = not (opt.size() > 2 and not opt[2])
		var b := Button.new()
		b.text = AF.typographic(String(opt[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, CHOICE_H)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ok
		b.add_theme_font_override("font", AF.font())
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", _row_box(false, false))
		b.add_theme_stylebox_override("hover", _row_box(true, false))
		b.add_theme_stylebox_override("pressed", _row_box(true, true))
		b.add_theme_stylebox_override("focus", _row_box(true, false))
		b.add_theme_stylebox_override("disabled", _row_box(false, false))
		b.add_theme_color_override("font_color", HudArt.IVORY)
		b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
		b.add_theme_color_override("font_pressed_color", AF.GOLD_BRIGHT)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.32))
		var idx := i
		b.pressed.connect(func() -> void: option_picked.emit(idx))
		_choices_box.add_child(b)
		_buttons.append(b)
		_enabled.append(ok)
	_sel = 0
	for i in _enabled.size():
		if _enabled[i]:
			_sel = i
			break
	_select(_sel)


func _row_box(gold: bool, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if gold:
		s.bg_color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.34 if pressed else 0.24)
		s.border_color = AF.GOLD
	else:
		s.bg_color = Color(0.045, 0.04, 0.036, 0.86)
		s.border_color = Color(AF.GOLD, 0.28)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 14
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


func _select(i: int) -> void:
	if i < 0 or i >= _buttons.size():
		return
	_sel = i
	for k in _buttons.size():
		var on := k == i and _enabled[k]
		_buttons[k].add_theme_stylebox_override("normal", _row_box(on, false))
		_buttons[k].add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else HudArt.IVORY)


func choice_count() -> int:
	return _buttons.size()


## Picks option `i` as if tapped. False when there is none (or it is disabled).
func pick(i: int) -> bool:
	if i < 0 or i >= _buttons.size() or not _enabled[i]:
		return false
	option_picked.emit(i)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var n := int(k.physical_keycode) - KEY_1
	if n >= 0 and n < 9:
		if pick(n):
			get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_DOWN:
			_step(1)
			get_viewport().set_input_as_handled()
		KEY_UP:
			_step(-1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if pick(_sel):
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			leave_requested.emit()
			get_viewport().set_input_as_handled()


func _step(dir: int) -> void:
	if _buttons.is_empty():
		return
	var i := _sel
	for _n in _buttons.size():
		i = posmod(i + dir, _buttons.size())
		if _enabled[i]:
			_select(i)
			return
