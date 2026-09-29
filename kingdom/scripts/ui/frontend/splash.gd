extends "res://scripts/ui/frontend/screen.gd"
## Splash: studio logo, game title, "PRESS ANY KEY / TAP TO START", platform line.

signal finished

var _ready_for_input := false
var _done := false


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	add_backdrop("splash", 0.25)
	add_child(FE.fade_rect(true, 0.55, 0.62))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var logo_c := CenterContainer.new()
	logo_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_c.add_child(FE.logo(1.25))
	col.add_child(logo_c)
	var t := FE.title_label(54)
	col.add_child(t)
	var sep := CenterContainer.new()
	sep.add_child(AF.separator(260))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sep)
	var prompt := Label.new()
	prompt.text = "TAP TO START" if _touch() else "PRESS ANY KEY"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_override("font", AF.wfont(500))
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", AF.TEXT)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(prompt)
	# Platform line.
	var plat := Label.new()
	plat.text = "GODOT   ·   MOBILE   ·   PC"
	plat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plat.add_theme_font_override("font", AF.wfont(500))
	plat.add_theme_font_size_override("font_size", 13)
	plat.add_theme_color_override("font_color", AF.TEXT_DIM)
	plat.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	plat.anchor_left = 0.0
	plat.anchor_right = 1.0
	plat.offset_left = 0
	plat.offset_right = 0
	plat.offset_top = -46
	plat.offset_bottom = -20
	plat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plat)
	var ver := Label.new()
	ver.text = "v" + preload("res://scripts/ui/frontend/flow.gd").version_text()
	ver.add_theme_font_override("font", AF.wfont(500))
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", AF.TEXT_DIM)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -120
	ver.offset_top = -40
	ver.offset_right = -20
	ver.offset_bottom = -16
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	# Fade in, then blink the prompt (a single looping tween).
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.1)
	tw.tween_callback(func() -> void: _ready_for_input = true)
	var blink := prompt.create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", 0.35, 0.9).set_trans(Tween.TRANS_SINE)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _input(e: InputEvent) -> void:
	if _done or not _ready_for_input:
		return
	var press := false
	if e is InputEventKey:
		press = e.pressed and not e.echo
	elif e is InputEventMouseButton or e is InputEventScreenTouch or e is InputEventJoypadButton:
		press = e.pressed
	if press:
		_done = true
		get_viewport().set_input_as_handled()
		finished.emit()
