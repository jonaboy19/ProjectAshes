extends "res://scripts/ui/frontend/screen.gd"
## "YOU DIED": dark red veil, Reload Last Save / Load Game / Return to Main Menu.
##   DeathScreen.open(hud_or_any_node)     (call when the player dies)

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const SlotScreen := preload("res://scripts/ui/frontend/slot_screen.gd")

var _was_paused := false
var _reload: Button


static func open(parent: Node) -> Control:
	var existing := parent.get_node_or_null("DeathScreen")
	if existing:
		return existing
	var s: Variant = load("res://scripts/ui/frontend/death_screen.gd").new()
	s.name = "DeathScreen"
	parent.add_child(s)
	return s


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	add_child(FE.dim(0.78, Color(0.05, 0.0, 0.0)))
	# Red bloom from the middle.
	var g := Gradient.new()
	g.set_color(0, Color(0.42, 0.03, 0.03, 0.55))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.0, 0.42)
	var bloom := TextureRect.new()
	bloom.texture = gt
	bloom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bloom.stretch_mode = TextureRect.STRETCH_SCALE
	bloom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bloom)
	add_child(FE.vignette(0.85))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var t := Label.new()
	t.text = "YOU DIED"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", AF.wfont(700))
	t.add_theme_font_size_override("font_size", 104)
	t.add_theme_color_override("font_color", Color("b3241d"))
	t.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_shadow_color", Color(0.5, 0.0, 0.0, 0.5))
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	var line := CenterContainer.new()
	var r := ColorRect.new()
	r.color = Color(0.7, 0.16, 0.13, 0.7)
	r.custom_minimum_size = Vector2(340, 1)
	line.add_child(r)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 16)
	col.add_child(sp)
	var have: bool = get_tree().root.has_node("Life") and Life.saves.latest_id() != ""
	_reload = _btn("Reload Last Save", _do_reload)
	_reload.disabled = not have
	col.add_child(_center(_reload))
	col.add_child(_center(_btn("Load Game", func() -> void: SlotScreen.open(self, "load", Callable(), true))))
	col.add_child(_center(_btn("Return to Main Menu", func() -> void: Flow.exit_to_menu(get_tree()))))
	(col.get_child(3 + (0 if have else 1)).get_child(0) as Control).call_deferred("grab_focus")
	# Slow fade in of the whole thing.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)
	t.scale = Vector2.ONE


func _center(b: Control) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(b)
	return c


func _btn(text: String, cb: Callable) -> Button:
	var b := FE.ghost_button(text, cb, 360)
	b.custom_minimum_size = Vector2(360, 52)
	var n := AF.panel(Color(0.02, 0.0, 0.0, 0.6), Color(0.55, 0.13, 0.1, 0.75), 3, 8)
	n.shadow_size = 0
	var h := AF.panel(Color(0.35, 0.05, 0.04, 0.55), Color(0.85, 0.22, 0.17), 3, 8)
	h.shadow_size = 0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("disabled", n)
	for st: String in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, h)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _do_reload() -> void:
	var id: String = Life.saves.latest_id()
	if id != "" and Life.saves.load_slot(id):
		get_tree().paused = _was_paused
		queue_free()
