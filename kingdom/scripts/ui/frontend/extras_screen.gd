extends "res://scripts/ui/frontend/screen.gd"
## Extras: placeholder gallery + credits entry.

const Credits := preload("res://scripts/ui/credits_screen.gd")


static func open(parent: Node) -> Control:
	var s: Variant = load("res://scripts/ui/frontend/extras_screen.gd").new()
	parent.add_child(s)
	return s


func _ready() -> void:
	add_backdrop("settings", 0.6)
	var mc := margin_box(36)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	mc.add_child(col)
	col.add_child(FE.header("Extras", back))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	row.add_child(_tile("Gallery", "Concept art, screenshots and the world map.\nComing soon.", "eye-target", Callable()))
	row.add_child(_tile("Credits", "The people and open-source work behind Rising Ashes.", "flag-objective",
		func() -> void: Credits.open(self)))
	FE.fade_in(self, 0.25)
	focus_first()


func _tile(title: String, text: String, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(330, 250)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 16)
	var s := AF.panel(Color(0.2, 0.15, 0.07, 0.94), AF.GOLD, 4, 16)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("disabled", n)
	for st: String in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, s)
	b.disabled = not cb.is_valid()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20
	v.offset_right = -20
	v.offset_top = 20
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := TextureRect.new()
	ic.texture = FE.icon(icon_name)
	ic.custom_minimum_size = Vector2(64, 64)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = AF.GOLD if cb.is_valid() else AF.GOLD_DIM
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var t := Label.new()
	t.text = title.to_upper()
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", AF.wfont(700))
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", AF.GOLD_BRIGHT if cb.is_valid() else AF.TEXT_DIM)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := AF.label(text, 17, AF.TEXT_DIM)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
