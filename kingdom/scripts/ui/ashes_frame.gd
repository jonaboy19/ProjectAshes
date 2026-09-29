extends RefCounted
## The shared "dark gold" look for every Rising Ashes menu and screen (the user's
## UI templates): near-black translucent panels with a thin gold frame, Cinzel
## headings, IM Fell English body text, gold-highlighted menu rows and tabs.
## Preload it (no class_name):  const AF := preload("res://scripts/ui/ashes_frame.gd")

const PANEL := Color(0.043, 0.039, 0.035, 0.92)      # near-black warm glass
const PANEL_SOFT := Color(0.06, 0.055, 0.048, 0.78)
const PANEL_ROW := Color(1.0, 0.86, 0.55, 0.05)       # list rows / slots at rest
const GOLD := Color("d8a84e")                         # frame + accents
const GOLD_BRIGHT := Color("f3cf7a")                  # hovered / selected text
const GOLD_DIM := Color(0.85, 0.66, 0.31, 0.45)       # thin separators
const TEXT := Color("ece3cf")                         # parchment white
const TEXT_DIM := Color(0.93, 0.89, 0.8, 0.6)
const RED := Color("b8322a")                          # danger / "You died"
const TITLE_FONT := "res://assets/ui/fonts/Cinzel[wght].ttf"
const BODY_FONT := "res://assets/ui/fonts/IMFellEnglish-Regular.ttf"
const ITALIC_FONT := "res://assets/ui/fonts/IMFellEnglish-Italic.ttf"
## Placeholder backdrops until the user's AI artwork arrives (drop files with the
## same names into res://assets/ui/backgrounds/ to replace them).
const BG_DIR := "res://assets/ui/backgrounds/"

static var _theme: Theme


static func font(path := BODY_FONT, weight := 0) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var f: Font = load(path)
	if weight > 0 and f is FontFile:
		var v := FontVariation.new()
		v.base_font = f
		v.variation_opentype = {"wght": weight}
		return v
	return f


static func title_font(weight := 600) -> Font:
	return font(TITLE_FONT, weight)


## Dark panel with a 1 px gold frame and square-ish corners.
static func panel(bg := PANEL, border := GOLD, radius := 4, margin := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 14
	s.anti_aliasing = true
	return s


## A menu / list row: transparent at rest, gold gradient-ish fill + frame when selected.
static func row(selected := false, hover := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.22)
		s.border_color = GOLD
		s.set_border_width_all(1)
	elif hover:
		s.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.1)
		s.border_color = GOLD_DIM
		s.set_border_width_all(1)
	else:
		s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


## Inventory/equipment slot.
static func slot(selected := false) -> StyleBoxFlat:
	var s := panel(Color(0.08, 0.07, 0.06, 0.9), GOLD if selected else GOLD_DIM, 3, 4)
	s.shadow_size = 0
	return s


## Gold primary button (Start Game, Load Game, Apply...).
static func gold_button_box(state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var base := Color("6b4a1c")
	match state:
		"hover": base = Color("8a6224")
		"pressed": base = Color("4e3514")
		"disabled": base = Color(0.2, 0.17, 0.12, 0.6)
	s.bg_color = base
	s.border_color = GOLD_BRIGHT if state != "disabled" else GOLD_DIM
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func gold_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, gold_button_box(st))
	b.add_theme_stylebox_override("focus", gold_button_box("hover"))
	b.add_theme_font_override("font", title_font(600))
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	return b


## Section heading in Cinzel caps with a short gold underline.
static func heading(text: String, size := 26) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", title_font(700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD_BRIGHT)
	v.add_child(l)
	var line := ColorRect.new()
	line.color = GOLD
	line.custom_minimum_size = Vector2(72, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(line)
	return v


static func label(text: String, size := 18, color := TEXT, italic := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(ITALIC_FONT if italic else BODY_FONT))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Thin gold separator line.
static func separator(width := 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = GOLD_DIM
	r.custom_minimum_size = Vector2(width, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_BEGIN
	return r


## Keyboard/gamepad hint chip: [E] Equip.
static func key_hint(key: String, action: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", title_font(600))
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", TEXT)
	var box := panel(Color(0, 0, 0, 0.5), GOLD_DIM, 3, 4)
	box.shadow_size = 0
	box.content_margin_left = 7
	box.content_margin_right = 7
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", box)
	pc.add_child(k)
	h.add_child(pc)
	h.add_child(label(action, 15, TEXT_DIM))
	return h


## Full-screen backdrop: the named art in BG_DIR if present, else a warm dark gradient.
static func backdrop(name: String) -> Control:
	for ext: String in [".png", ".jpg", ".webp"]:
		var p := BG_DIR + name + ext
		if ResourceLoader.exists(p):
			var tr := TextureRect.new()
			tr.texture = load(p)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tr
	var g := Gradient.new()
	g.set_color(0, Color("1a120a"))
	g.set_color(1, Color("050403"))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.35)
	gt.fill_to = Vector2(1.1, 1.1)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Base Theme for whole screens (labels, buttons, scroll, sliders, option buttons).
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(BODY_FONT)
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("normal", "Button", row())
	t.set_stylebox("hover", "Button", row(false, true))
	t.set_stylebox("pressed", "Button", row(true))
	t.set_stylebox("focus", "Button", row(false, true))
	t.set_stylebox("disabled", "Button", row())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	t.set_color("font_focus_color", "Button", GOLD_BRIGHT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_stylebox("normal", "OptionButton", slot())
	t.set_stylebox("hover", "OptionButton", slot(true))
	t.set_stylebox("pressed", "OptionButton", slot(true))
	t.set_stylebox("focus", "OptionButton", slot(true))
	var bar_bg := panel(Color(0, 0, 0, 0.55), GOLD_DIM, 2, 0)
	bar_bg.shadow_size = 0
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(2)
	t.set_stylebox("fill", "ProgressBar", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.55)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var sfill := track.duplicate()
	sfill.bg_color = GOLD
	t.set_stylebox("grabber_area", "HSlider", sfill)
	t.set_stylebox("grabber_area_highlight", "HSlider", sfill)
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD_DIM
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	_theme = t
	return t
