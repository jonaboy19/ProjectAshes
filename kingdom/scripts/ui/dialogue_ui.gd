extends Control
## The conversation screen (the user's DIALOGUE template): the NPC's 3D bust large on
## the left, a name plate with the spoken line under it, numbered choices on the right
## (1..9: gold highlight, keyboard number keys, arrows + Enter, touch) and a
## "Relationship: Neutral (0)" line with a small bar.
##
## It is a pure view. HUD.show_menu() routes any menu whose dict carries a "speaker"
## through here (village_services.gd _talk_page adds it); the choice callables and the
## page rebuild stay in HUD:
##   {title, body, options: [[label, Callable, enabled?]],          # the normal menu dict
##    speaker: "Tomas", role: "Blacksmith", line: "You're not from...",
##    relationship: "Neutral (0)", rel_value: 0.0 (-100..100),
##    portrait_key: "p12", model: Node3D (the NPC's live model, duplicated for the bust),
##    look: "Blacksmith" (Assets.character look used when there is no live model)}

signal option_picked(index: int)
signal leave_requested

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const Portrait := preload("res://scripts/ui/portrait.gd")

var _shade: Control
var _bust: Portrait
var _placeholder: Control
var _name_label: Label
var _role_label: Label
var _line_scroll: ScrollContainer
var _line: Label
var _choices_box: VBoxContainer
var _choices_scroll: ScrollContainer
var _rel_label: Label
var _rel_bar: Control
var _rel_value := 0.0
var _key := ""
var _buttons: Array[Button] = []
var _enabled: Array[bool] = []
var _sel := 0
var _bust_holder: Control
var _bust_tween: Tween
var _present_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	_build()


func _build() -> void:
	_shade = Control.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.draw.connect(_draw_shade)
	add_child(_shade)
	# Bust, left. The Portrait renders the NPC's model in its own tiny world.
	_bust_holder = Control.new()
	_bust_holder.anchor_left = 0.0
	_bust_holder.anchor_right = 0.55
	_bust_holder.anchor_top = 0.0
	_bust_holder.anchor_bottom = 1.0
	_bust_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bust_holder)
	_bust = Portrait.new()
	_bust.setup(Vector2i(880, 900), "bust", true)
	_bust.yaw_deg = 16.0            # turned a little toward the player, who stands to the right
	_bust.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bust_holder.add_child(_bust)
	_placeholder = Control.new()
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.draw.connect(_draw_placeholder)
	_bust_holder.add_child(_placeholder)
	# Name plate + spoken line, bottom left.
	var plate := PanelContainer.new()
	plate.anchor_left = 0.03
	plate.anchor_right = 0.52
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.offset_top = -196
	plate.offset_bottom = -34
	var sb := HudArt.card_box(0.9, 18)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	plate.add_theme_stylebox_override("panel", sb)
	add_child(plate)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	plate.add_child(pv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	pv.add_child(head)
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", AF.wfont(700))
	_name_label.add_theme_font_size_override("font_size", 27)
	_name_label.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	head.add_child(_name_label)
	_role_label = Label.new()
	_role_label.add_theme_font_override("font", AF.font(AF.ITALIC_FONT))
	_role_label.add_theme_font_size_override("font_size", 17)
	_role_label.add_theme_color_override("font_color", AF.TEXT_DIM)
	_role_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_role_label)
	pv.add_child(AF.separator())
	_line_scroll = ScrollContainer.new()
	_line_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_line_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_line_scroll)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.add_theme_font_override("font", AF.font())
	_line.add_theme_font_size_override("font_size", 21)
	_line.add_theme_color_override("font_color", HudArt.IVORY)
	_line_scroll.add_child(_line)
	# Choices, right.
	var right := VBoxContainer.new()
	right.anchor_left = 0.56
	right.anchor_right = 0.97
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_top = 40
	right.offset_bottom = -34
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 10)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	_choices_scroll = ScrollContainer.new()
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choices_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_choices_scroll)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_box.size_flags_vertical = Control.SIZE_SHRINK_END
	_choices_scroll.add_child(_choices_box)
	# Relationship line + bar under the choices.
	_rel_label = Label.new()
	_rel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rel_label.add_theme_font_override("font", AF.font(AF.ITALIC_FONT))
	_rel_label.add_theme_font_size_override("font_size", 16)
	_rel_label.add_theme_color_override("font_color", AF.TEXT_DIM)
	right.add_child(_rel_label)
	_rel_bar = Control.new()
	_rel_bar.custom_minimum_size = Vector2(0, 8)
	_rel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rel_bar.draw.connect(_draw_rel_bar)
	right.add_child(_rel_bar)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 18)
	right.add_child(foot)
	var leave := Button.new()
	leave.flat = true
	leave.text = "[Esc]   Leave"
	leave.focus_mode = Control.FOCUS_NONE
	leave.add_theme_font_override("font", AF.font())
	leave.add_theme_font_size_override("font_size", 16)
	leave.add_theme_color_override("font_color", AF.TEXT_DIM)
	leave.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	leave.custom_minimum_size = Vector2(140, 30)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	foot.add_child(leave)


## Shows a page. `data` is a menu dict with the dialogue keys (see the header).
func set_page(data: Dictionary) -> void:
	_name_label.text = String(data.get("speaker", data.get("title", "")))
	var role := String(data.get("role", ""))
	_role_label.text = role
	_role_label.visible = role != ""
	_line.text = AF.typographic(String(data.get("line", data.get("body", ""))))
	_line_scroll.scroll_vertical = 0
	var key := String(data.get("portrait_key", _name_label.text))
	if key != _key:
		_key = key
		_set_bust(data.get("model") as Node3D, String(data.get("look", "")))
	var rel_text := String(data.get("relationship", ""))
	_rel_label.text = ("Relationship: " + rel_text) if rel_text != "" else ""
	_rel_label.visible = rel_text != ""
	_rel_bar.visible = rel_text != ""
	_rel_value = float(data.get("rel_value", 0.0))
	_rel_bar.queue_redraw()
	_build_choices(data.get("options", []))


## Starts the dialogue overlay with a short ease so the world shade and UI do not pop
## onto the screen in one frame. HUD calls this only when opening a new conversation.
func present() -> void:
	if _present_tween and _present_tween.is_running():
		_present_tween.kill()
	var tint := modulate
	tint.a = 0.0
	modulate = tint
	_present_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_present_tween.tween_property(self, "modulate", Color.WHITE, 0.25)


func _set_bust(model: Node3D, look: String) -> void:
	if _bust_tween and _bust_tween.is_running():
		_bust_tween.kill()
	_placeholder.visible = true
	if model != null and is_instance_valid(model) and _model_ok(model):
		_bust.set_model_copy(model)
		_placeholder.visible = false
		_bust.visible = true
	elif look != "":
		_bust.set_model(Assets.character(look, 1.75))
		_placeholder.visible = false
		_bust.visible = true
	else:
		_bust.visible = false
	var tint := _bust_holder.modulate
	tint.a = 0.0
	_bust_holder.modulate = tint
	_bust_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bust_tween.tween_property(_bust_holder, "modulate", Color.WHITE, 0.25)
	_shade.queue_redraw()
	_placeholder.queue_redraw()


func _model_ok(model: Node3D) -> bool:
	return not model.find_children("*", "Skeleton3D", true, false).is_empty()


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
		b.text = ("%d.  " % (i + 1) if i < 9 else "     ") + AF.typographic(String(opt[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ok
		b.add_theme_font_override("font", AF.font())
		b.add_theme_font_size_override("font_size", 19)
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
		b.mouse_entered.connect(func() -> void: _select(idx))
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
	s.set_corner_radius_all(4)
	s.content_margin_left = 16
	s.content_margin_right = 14
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	s.anti_aliasing = true
	return s


func _select(i: int) -> void:
	if i < 0 or i >= _buttons.size():
		return
	_sel = i
	for k in _buttons.size():
		var b := _buttons[k]
		var on := k == i and _enabled[k]
		b.add_theme_stylebox_override("normal", _row_box(on, false))
		b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else HudArt.IVORY)


func choice_count() -> int:
	return _buttons.size()


## Picks option `i` as if tapped. Returns false when there is none (or it is disabled).
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


# --- drawing -------------------------------------------------------------------------

func _draw_shade() -> void:
	var s := _shade.size
	# Left-to-right: dark behind the bust and plate, clearing over the scene, dark again behind the choices.
	var xs := [0.0, s.x * 0.34, s.x * 0.55, s.x * 0.66, s.x]
	var al := [0.5, 0.2, 0.05, 0.4, 0.68]
	for i in 4:
		_shade.draw_polygon(PackedVector2Array([Vector2(xs[i], 0), Vector2(xs[i + 1], 0), Vector2(xs[i + 1], s.y), Vector2(xs[i], s.y)]),
			PackedColorArray([Color(0.02, 0.015, 0.01, al[i]), Color(0.02, 0.015, 0.01, al[i + 1]),
				Color(0.02, 0.015, 0.01, al[i + 1]), Color(0.02, 0.015, 0.01, al[i])]))
	# Bottom band so the plate reads on bright scenes.
	_shade.draw_polygon(PackedVector2Array([Vector2(0, s.y * 0.55), Vector2(s.x, s.y * 0.55), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.62)]))
	# Thin gold frame lines at the top and bottom edge.
	_shade.draw_rect(Rect2(Vector2(14, 14), s - Vector2(28, 28)), Color(AF.GOLD, 0.22), false, 1.0)


func _draw_placeholder() -> void:
	# A painted stand-in when there is no model: a warm glow, head and shoulders in silhouette.
	var s := _placeholder.size
	var c := Vector2(s.x * 0.5, s.y * 0.62)
	_placeholder.draw_circle(c + Vector2(0, -s.y * 0.12), s.y * 0.34, Color(AF.GOLD, 0.06))
	var col := Color(0.09, 0.075, 0.06, 0.95)
	_placeholder.draw_circle(c + Vector2(0, -s.y * 0.19), s.y * 0.105, col)
	var sh := PackedVector2Array()
	for i in 21:
		var a := PI + i * PI / 20.0
		sh.append(c + Vector2(cos(a) * s.y * 0.34, sin(a) * s.y * 0.2 + s.y * 0.07))
	sh.append(c + Vector2(s.y * 0.34, s.y * 0.45))
	sh.append(c + Vector2(-s.y * 0.34, s.y * 0.45))
	_placeholder.draw_colored_polygon(sh, col)
	var f := AF.wfont(700)
	var initial := _name_label.text.left(1).to_upper() if _name_label else "?"
	_placeholder.draw_string(f, c + Vector2(-s.y * 0.1, -s.y * 0.15), initial, HORIZONTAL_ALIGNMENT_CENTER, s.y * 0.2, int(s.y * 0.11), Color(AF.GOLD, 0.7))


func _draw_rel_bar() -> void:
	var s := _rel_bar.size
	var r := Rect2(Vector2(0, s.y * 0.5 - 3), Vector2(s.x, 6))
	_rel_bar.draw_rect(r, Color(0, 0, 0, 0.55))
	_rel_bar.draw_rect(r, Color(AF.GOLD, 0.35), false, 1.0)
	var t := clampf((_rel_value + 100.0) / 200.0, 0.0, 1.0)
	_rel_bar.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * t, r.size.y - 2)), Color(AF.GOLD, 0.85) if _rel_value >= 0.0 else Color("b8622a"))
	# Neutral tick in the middle.
	_rel_bar.draw_line(Vector2(s.x * 0.5, r.position.y - 2), Vector2(s.x * 0.5, r.end.y + 2), Color(AF.TEXT_DIM, 0.6), 1.0)
