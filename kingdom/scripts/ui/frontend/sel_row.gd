extends PanelContainer
## One settings row: "Label      ◀ value ▶" (option), a toggle, a slider or a key rebind.
## Keyboard/gamepad: focus the row, left/right change it, accept activates. Touch: tap the arrows.

const AF := preload("res://scripts/ui/ashes_frame.gd")

signal changed(key: String, value: Variant)

var key := ""
var kind := "opt"          # opt | toggle | slider | key | info
var opts: Array = []
var value: Variant = 0
var _val_label: Label
var _slider: HSlider
var _capturing := false
var _hint := ""
var mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func setup(k: String, label: String, kd: String, options: Array, v: Variant, hint := "") -> void:
	key = k
	kind = kd
	opts = options
	value = v
	_hint = hint
	custom_minimum_size = Vector2(0, 48 if mobile else 42)
	focus_mode = Control.FOCUS_ALL
	_style(false)
	focus_entered.connect(_style.bind(true))
	focus_exited.connect(_style.bind(false))
	mouse_entered.connect(func() -> void: grab_focus())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	var l := AF.label(label, 18, AF.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	match kind:
		"slider":
			_slider = HSlider.new()
			_slider.min_value = 0
			_slider.max_value = 100
			_slider.step = 1
			_slider.value = float(value)
			_slider.custom_minimum_size = Vector2(230, 30)
			_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_slider.focus_mode = Control.FOCUS_NONE
			_slider.value_changed.connect(func(nv: float) -> void: _commit(int(nv)))
			h.add_child(_slider)
			_val_label = _value_label(48)
			_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(_val_label)
		"info":
			_val_label = _value_label(0)
			h.add_child(_val_label)
		"key":
			_val_label = _value_label(150)
			_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.add_child(_val_label)
			_val_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_val_label.size_flags_horizontal = Control.SIZE_FILL
			b.pressed.connect(_begin_capture)
			h.add_child(b)
		_:
			h.add_child(_arrow("◀", -1))
			_val_label = _value_label(150)
			_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(_val_label)
			h.add_child(_arrow("▶", 1))
	_refresh()


func _value_label(w: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", AF.wfont(500))
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", AF.TEXT)
	l.custom_minimum_size = Vector2(w, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _arrow(t: String, dir: int) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(48, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", AF.GOLD)
	var n := AF.panel(Color(0, 0, 0, 0.4), AF.GOLD_DIM, 2, 4)
	n.shadow_size = 0
	var hv := AF.panel(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.2), AF.GOLD, 2, 4)
	hv.shadow_size = 0
	b.add_theme_stylebox_override("normal", n)
	for st: String in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, hv)
	b.pressed.connect(func() -> void: step(dir))
	return b


func _style(focused: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.13) if focused else Color(1, 1, 1, 0.025)
	s.border_color = AF.GOLD if focused else Color(0, 0, 0, 0)
	s.border_width_left = 2 if focused else 0
	s.content_margin_left = 14
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	add_theme_stylebox_override("panel", s)


func set_value(v: Variant) -> void:
	value = v
	_refresh()


func _refresh() -> void:
	match kind:
		"opt":
			_val_label.text = String(opts[clampi(int(value), 0, opts.size() - 1)])
		"toggle":
			_val_label.text = "On" if bool(value) else "Off"
		"slider":
			_val_label.text = "%d" % int(value)
			if _slider and int(_slider.value) != int(value):
				_slider.set_value_no_signal(float(value))
		"key":
			_val_label.text = "Press a key..." if _capturing else String(value)
		"info":
			_val_label.text = _hint


func _commit(v: Variant) -> void:
	value = v
	_refresh()
	changed.emit(key, value)


func step(dir: int) -> void:
	match kind:
		"opt":
			var n := opts.size()
			_commit(posmod(int(value) + dir, n))
		"toggle":
			_commit(not bool(value))
		"slider":
			_commit(clampi(int(value) + dir * 5, 0, 100))


func _gui_input(e: InputEvent) -> void:
	if not has_focus() or _capturing:
		return
	if e.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif e.is_action_pressed("ui_right"):
		step(1)
		accept_event()
	elif e.is_action_pressed("ui_accept"):
		if kind == "key":
			_begin_capture()
		elif kind == "toggle" or kind == "opt":
			step(1)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and kind == "toggle":
		step(1)


func _begin_capture() -> void:
	_capturing = true
	_refresh()
	grab_focus()


func _input(e: InputEvent) -> void:
	if not _capturing:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		_capturing = false
		if e.keycode != KEY_ESCAPE:
			var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
			value = OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code as Key))
			changed.emit(key, code)
		_refresh()
	elif e is InputEventMouseButton and e.pressed:
		_capturing = false
		_refresh()
