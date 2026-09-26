class_name UITheme
extends RefCounted
## One place for the UI's look: palette tokens, fonts, the Godot Theme used by
## menus, and the round action buttons for touch. Change the palette here and
## every panel, button and bar follows.

# Palette (placeholder until the reference palette is confirmed).
const BG := Color(0.055, 0.063, 0.098, 0.86)        # glass panel
const BG_SOLID := Color("0e1019")
const SURFACE := Color(1, 1, 1, 0.06)               # buttons at rest
const SURFACE_HOVER := Color(1, 1, 1, 0.12)
const STROKE := Color(1, 1, 1, 0.14)
const TEXT := Color("f2efe8")
const TEXT_DIM := Color(0.95, 0.94, 0.9, 0.62)
const ACCENT := Color("f5b841")                     # gold
const ACCENT_2 := Color("3ec7c2")                   # teal
const DANGER := Color("ff5d5d")
const HEALTH := Color("ff4d5e")
const STAMINA := Color("ffc24a")
const MAGIC := Color("6d8bff")
const OK := Color("7be0a0")

const ACTION_ATTACK := Color("ff5a4f")
const ACTION_DODGE := Color("3ec7c2")
const ACTION_BLOCK := Color("8f7cff")
const ACTION_TALK := Color("f5b841")
const ACTION_UTIL := Color("6c7a99")

const TITLE_FONT := "res://assets/ui/fonts/Cinzel[wght].ttf"
const ICONS := "res://assets/ui/icons/"
const RADIUS := 14

static var _theme: Theme


static func title_font() -> Font:
	return load(TITLE_FONT) if ResourceLoader.exists(TITLE_FONT) else ThemeDB.fallback_font


static func icon(icon_name: String) -> Texture2D:
	var p := ICONS + icon_name + ".svg"
	return load(p) if ResourceLoader.exists(p) else null


static func panel_box(radius := RADIUS, bg := BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = STROKE
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(20)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 18
	s.anti_aliasing = true
	return s


static func pill(bg: Color, border := Color(0, 0, 0, 0), radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


## Theme for menus: glass panels, pill buttons with a gold focus edge.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("normal", "Button", pill(SURFACE, STROKE))
	t.set_stylebox("hover", "Button", pill(SURFACE_HOVER, ACCENT.darkened(0.2)))
	t.set_stylebox("pressed", "Button", pill(ACCENT.darkened(0.35), ACCENT))
	t.set_stylebox("focus", "Button", pill(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("disabled", "Button", pill(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.05)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_constant("h_separation", "Button", 10)
	var bar_bg := pill(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 6)
	bar_bg.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	_theme = t
	return t


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := pill(color, Color(0, 0, 0, 0), 6)
	s.set_content_margin_all(0)
	return s


## Anti-aliased circular button face: soft radial glass in `color`, a bright
## rim, and an optional white icon centred on it.
static func round_button(size: int, color: Color, icon_tex: Texture2D = null, pressed := false) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5 - 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var edge := clampf(r - d + 0.5, 0.0, 1.0)
			if edge <= 0.0:
				continue
			var t := d / r
			var base := color.darkened(0.35).lerp(color, 1.0 - t * 0.6)
			if pressed:
				base = base.lightened(0.2)
			var a := 0.78 if not pressed else 0.92
			# Top highlight for a glassy feel.
			var hl := clampf(1.0 - (y / float(size)) * 2.2, 0.0, 1.0) * 0.18
			base = base.lerp(Color.WHITE, hl)
			# Rim.
			var rim := clampf(1.0 - absf(d - (r - 2.0)) / 1.6, 0.0, 1.0)
			base = base.lerp(color.lightened(0.55), rim * 0.8)
			img.set_pixel(x, y, Color(base.r, base.g, base.b, a * edge))
	if icon_tex:
		var ic := icon_tex.get_image()
		if ic:
			ic = ic.duplicate()
			ic.convert(Image.FORMAT_RGBA8)
			var s := int(size * 0.5)
			ic.resize(s, s, Image.INTERPOLATE_LANCZOS)
			var off := Vector2i((size - s) / 2, (size - s) / 2)
			for y in s:
				for x in s:
					var p := ic.get_pixel(x, y)
					if p.a > 0.0:
						var dst := img.get_pixel(off.x + x, off.y + y)
						img.set_pixel(off.x + x, off.y + y, dst.lerp(Color(1, 1, 1, maxf(dst.a, p.a)), p.a * 0.95))
	return ImageTexture.create_from_image(img)
