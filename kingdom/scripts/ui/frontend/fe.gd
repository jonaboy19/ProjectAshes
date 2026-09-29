extends RefCounted
## Front-end widgets shared by the boot / menu / settings / pause screens, all built
## on the shared look in ashes_frame.gd (AF). Preload:
##   const FE := preload("res://scripts/ui/frontend/fe.gd")

const AF := preload("res://scripts/ui/ashes_frame.gd")
const LOGO_PATH := "res://assets/ui/logo_studio.png"
const STEEL := Color("aab7c8")
const STEEL_DARK := Color("5d7088")
const TEAL := Color("2ea6c9")


## Gold diamond bullet + (when selected) gold rule lines, drawn over a menu row.
class RowDeco extends Control:
	var row: Control

	func _init(r: Control) -> void:
		row = r
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for sig: String in ["focus_entered", "focus_exited", "mouse_entered", "mouse_exited"]:
			row.connect(sig, queue_redraw)

	func _draw() -> void:
		var on: bool = row.has_focus() or (row as Button).is_hovered()
		var disabled: bool = (row as Button).disabled
		var c: Color = AF.GOLD_BRIGHT if on else AF.GOLD
		if disabled:
			c = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.3)
		var cy := size.y * 0.5
		var s := 5.0
		var cx := 22.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - s), Vector2(cx + s, cy),
			Vector2(cx, cy + s), Vector2(cx - s, cy)]), c)
		if on and not disabled:
			draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.55), 1.0)
			draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.35), 1.0)


static func _grad_tex(a: Color, b: Color, horizontal := true) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	return t


static func sel_box() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _grad_tex(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.34), Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.02))
	return s


## Main-menu style row: gold diamond, Cinzel text, gold gradient when focused/hovered.
static func menu_row(text: String, cb: Callable, size := 22, height := 54) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, height)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", AF.wfont(500))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", AF.TEXT)
	b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	b.add_theme_color_override("font_focus_color", AF.GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", AF.GOLD_BRIGHT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.28))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 46
	empty.content_margin_right = 12
	var sel := sel_box()
	sel.content_margin_left = 46
	sel.content_margin_right = 12
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("disabled", empty)
	for st: String in ["hover", "focus", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sel)
	b.add_child(RowDeco.new(b))
	if cb.is_valid():
		b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## Dark gradient that fades to transparent (left panel behind menus).
static func fade_rect(from_left := true, alpha := 0.9, width_frac := 0.42) -> Control:
	var t := TextureRect.new()
	t.texture = _grad_tex(Color(0.02, 0.018, 0.015, alpha), Color(0.02, 0.018, 0.015, 0.0))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.flip_h = not from_left
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.anchor_left = 0.0 if from_left else 1.0 - width_frac
	t.anchor_right = width_frac if from_left else 1.0
	t.anchor_top = 0.0
	t.anchor_bottom = 1.0
	t.offset_left = 0
	t.offset_right = 0
	return t


static func vignette(alpha := 0.55) -> Control:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, alpha))
	g.set_offset(0, 0.45)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func dim(alpha := 0.4, color := Color.BLACK) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(color.r, color.g, color.b, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Backdrop art with a vignette + dim, ready to add as the first child.
static func backdrop_stack(name: String, dim_alpha := 0.35) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(AF.backdrop(name))
	root.add_child(dim(dim_alpha))
	root.add_child(vignette(0.6))
	return root


static func icon(name: String) -> Texture2D:
	var p := "res://assets/ui/icons/%s.svg" % name
	return load(p) if ResourceLoader.exists(p) else null


## Full-width screen title (Cinzel caps) with the optional close (x) button.
static func header(title: String, on_close := Callable(), size := 22) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title.to_upper()
	l.add_theme_font_override("font", AF.wfont(600))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AF.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if on_close.is_valid():
		h.add_child(close_button(on_close))
	return h


static func close_button(cb: Callable) -> Button:
	var b := Button.new()
	b.text = "×"
	b.custom_minimum_size = Vector2(48, 48)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b


## Secondary (outlined) button used for Reset / Back / Delete.
static func ghost_button(text: String, cb: Callable, min_w := 120) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.add_theme_font_override("font", AF.wfont(500))
	b.add_theme_font_size_override("font_size", 17)
	var n := AF.panel(Color(0, 0, 0, 0.35), AF.GOLD_DIM, 3, 8)
	n.shadow_size = 0
	n.content_margin_left = 22
	n.content_margin_right = 22
	var h := AF.panel(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.16), AF.GOLD, 3, 8)
	h.shadow_size = 0
	h.content_margin_left = 22
	h.content_margin_right = 22
	for st: String in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, n)
	for st: String in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, h)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func gold_btn(text: String, cb: Callable, min_w := 200) -> Button:
	var b := AF.gold_button(text)
	b.custom_minimum_size = Vector2(min_w, 52)
	b.add_theme_font_size_override("font_size", 19)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Key-hint chip row: [Enter] Select ... (no wrapping, unlike a bare AF.key_hint in a tight box).
static func key_hints(pairs: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p: Array in pairs:
		var hb := AF.key_hint(String(p[0]), String(p[1]))
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for l in hb.find_children("*", "Label", true, false):
			(l as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(hb)
	return h


## Cinzel at an explicit weight through the OpenType tag (robust across Godot versions).
static func bold(weight: int) -> Font:
	return AF.wfont(weight)


## Runs `fn` after a short black fade when an ancestor supports transitions (boot).
static func go(node: Node, fn: Callable) -> void:
	var n := node
	while n:
		if n.has_method("transition"):
			n.call("transition", fn)
			return
		n = n.get_parent()
	fn.call()


static func fade_in(node: CanvasItem, t := 0.35) -> void:
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, t)


static func play(sound: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var a := tree.root.get_node_or_null("Audio")
	if a and a.has_method("play_ui"):
		a.call("play_ui", sound)


## Modal yes/no box over `parent` (deleting saves, exit to menu...).
static func confirm(parent: Node, text: String, on_yes: Callable, yes_label := "Confirm", danger := false) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = AF.theme()
	root.add_child(dim(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(440, 0)
	pc.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.RED if danger else AF.GOLD, 4, 24))
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	pc.add_child(v)
	var l := AF.label(text, 20, AF.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var no := ghost_button("Cancel", func() -> void: root.queue_free(), 130)
	var yes := gold_btn(yes_label, func() -> void:
		root.queue_free()
		on_yes.call(), 150)
	row.add_child(no)
	row.add_child(yes)
	parent.add_child(root)
	no.grab_focus()
	root.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			root.queue_free())
	return root


# --- Studio logo (text-built placeholder; drop res://assets/ui/logo_studio.png to replace) ---

class LogoMark extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var pts := PackedVector2Array()
		for i in 6:
			var a := -PI / 2.0 + i * TAU / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		pts.append(pts[0])
		draw_polyline(pts, Color("d8a84e"), 3.0, true)
		var inner := PackedVector2Array()
		for i in 6:
			var a := -PI / 2.0 + i * TAU / 6.0
			inner.append(c + Vector2(cos(a), sin(a)) * r * 0.82)
		inner.append(inner[0])
		draw_polyline(inner, Color(0.85, 0.66, 0.31, 0.5), 1.0, true)
		var f: Font = ThemeDB.fallback_font
		var path := "res://assets/ui/fonts/Cinzel[wght].ttf"
		if ResourceLoader.exists(path):
			var fv := FontVariation.new()
			fv.base_font = load(path)
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
			f = fv
		var fs := int(r * 1.0)
		var ts := f.get_string_size("T", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - ts.x * 1.05, c.y + fs * 0.34), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2ea6c9"))
		draw_string(f, Vector2(c.x - ts.x * 0.1, c.y + fs * 0.34), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f3cf7a"))


## "TOTAL SHOWDOWN / GENERAL GROUP" logo. `k` scales it (1.0 ~ 340 px wide).
static func logo(k := 1.0) -> Control:
	if ResourceLoader.exists(LOGO_PATH):
		var tr := TextureRect.new()
		tr.texture = load(LOGO_PATH)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(340, 200) * k
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(-4 * k))
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := LogoMark.new()
	mark.custom_minimum_size = Vector2(84, 84) * k
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mark)
	v.add_child(_logo_label("TOTAL", int(46 * k), 800, Color("dfe6ee"), Color(0.05, 0.08, 0.12), int(6 * k)))
	v.add_child(_logo_label("SHOWDOWN", int(58 * k), 900, Color("f0bf55"), Color(0.16, 0.08, 0.02), int(8 * k)))
	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", int(10 * k))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(_rule(int(46 * k)))
	sub.add_child(_logo_label("GENERAL GROUP", int(13 * k), 600, STEEL, Color(0, 0, 0, 0), 0, 3))
	sub.add_child(_rule(int(46 * k)))
	v.add_child(sub)
	return v


static func _rule(w: int) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.7)
	r.custom_minimum_size = Vector2(w, 1)
	c.add_child(r)
	return c


static func _logo_label(text: String, size: int, weight: int, color: Color, outline: Color, outline_size: int, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	var f := bold(weight)
	if spacing > 0 and f is FontVariation:
		(f as FontVariation).spacing_glyph = spacing
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline_size > 0:
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", outline_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Game wordmark "RISING ASHES".
static func title_label(size := 64) -> Label:
	var l := _logo_label("RISING ASHES", size, 800, AF.GOLD_BRIGHT, Color(0.1, 0.05, 0.02), maxi(4, size / 8), maxi(2, size / 16))
	return l
