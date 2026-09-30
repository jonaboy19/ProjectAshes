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
	# Sliders (photo mode): slim dark track, gold fill, a round white-rimmed grabber.
	var track := pill(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 4)
	track.set_content_margin_all(0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := pill(ACCENT.darkened(0.1), Color(0, 0, 0, 0), 4)
	fill.set_content_margin_all(0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _knob_texture(26)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_constant("center_grabber", "HSlider", 1)
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


static func _knob_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5 - 1.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				var rim := clampf(1.0 - absf(d - (r - 1.5)) / 1.5, 0.0, 1.0)
				var col := TEXT.lerp(ACCENT, rim)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static var _glyphs := {}


## White line-art glyphs drawn procedurally (no imported SVG needed) for HUD
## buttons: "map", "camera", "compass", "lock", "pause". Works as `icon_tex` for round_button().
static func glyph(glyph_name: String, size := 96) -> ImageTexture:
	var key := "%s:%d" % [glyph_name, size]
	if _glyphs.has(key):
		return _glyphs[key]
	var s := float(size)
	var w := s * 0.045                         # stroke half-width
	var segs: Array = []                       # [a, b] stroked segments
	var rings: Array = []                      # [centre, radius] stroked circles
	var discs: Array = []                      # [centre, radius] filled circles
	match glyph_name:
		"map":
			var pts := [Vector2(0.12, 0.24), Vector2(0.38, 0.14), Vector2(0.62, 0.24), Vector2(0.88, 0.14),
				Vector2(0.88, 0.76), Vector2(0.62, 0.86), Vector2(0.38, 0.76), Vector2(0.12, 0.86)]
			for i in pts.size():
				segs.append([pts[i] * s, pts[(i + 1) % pts.size()] * s])
			segs.append([pts[1] * s, pts[6] * s])
			segs.append([pts[2] * s, pts[5] * s])
		"camera":
			var body := [Vector2(0.1, 0.32), Vector2(0.34, 0.32), Vector2(0.4, 0.2), Vector2(0.6, 0.2),
				Vector2(0.66, 0.32), Vector2(0.9, 0.32), Vector2(0.9, 0.8), Vector2(0.1, 0.8)]
			for i in body.size():
				segs.append([body[i] * s, body[(i + 1) % body.size()] * s])
			rings.append([Vector2(0.5, 0.55) * s, s * 0.15])
			discs.append([Vector2(0.78, 0.43) * s, s * 0.035])
		"lock":
			# Target reticle: ring, four ticks and a centre dot (lock-on; "Look" keeps the eye).
			rings.append([Vector2(0.5, 0.5) * s, s * 0.27])
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				segs.append([(Vector2(0.5, 0.5) + d * 0.18) * s, (Vector2(0.5, 0.5) + d * 0.42) * s])
			discs.append([Vector2(0.5, 0.5) * s, s * 0.05])
		"pause":
			for dx in [-0.03, 0.0, 0.03]:
				segs.append([Vector2(0.36 + dx, 0.27) * s, Vector2(0.36 + dx, 0.73) * s])
				segs.append([Vector2(0.64 + dx, 0.27) * s, Vector2(0.64 + dx, 0.73) * s])
		"compass":
			rings.append([Vector2(0.5, 0.5) * s, s * 0.38])
			segs.append([Vector2(0.5, 0.22) * s, Vector2(0.58, 0.5) * s])
			segs.append([Vector2(0.58, 0.5) * s, Vector2(0.5, 0.78) * s])
			segs.append([Vector2(0.5, 0.78) * s, Vector2(0.42, 0.5) * s])
			segs.append([Vector2(0.42, 0.5) * s, Vector2(0.5, 0.22) * s])
		_:
			rings.append([Vector2(0.5, 0.5) * s, s * 0.3])
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := INF
			for sg: Array in segs:
				d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) - w)
			for rg: Array in rings:
				d = minf(d, absf(p.distance_to(rg[0]) - rg[1]) - w)
			for dc: Array in discs:
				d = minf(d, p.distance_to(dc[0]) - dc[1])
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_glyphs[key] = tex
	return tex


## Serif display font at a weight (Cinzel is a variable font): headings, banners.
static func title_font_weight(weight := 600) -> Font:
	var base := title_font()
	if not base is FontFile:
		return base
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv
