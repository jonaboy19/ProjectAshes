extends RefCounted
## Drawing helpers for the in-game HUD, dialogue, notifications and banners: the
## user's dark-gold look (see ashes_frame.gd for panels/fonts/colours). Kept in its
## own file so ashes_frame.gd stays untouched by this work.
##   const HudArt := preload("res://scripts/ui/hud_art.gd")

const AF := preload("res://scripts/ui/ashes_frame.gd")

const IVORY := Color("f3e6c8")
const IVORY_DIM := Color(0.95, 0.9, 0.78, 0.62)
const GOLD := AF.GOLD
const GOLD_BRIGHT := AF.GOLD_BRIGHT
const GOLD_DARK := Color("8a6224")
const INK := Color(0.043, 0.039, 0.035, 0.9)             # panel fill
const HEART_RED := Color("d43a35")
const STAMINA_GOLD := Color("efb632")
const SOUL_BLUE := Color("4f8fe8")
const OK_GREEN := Color("5fd07a")
const CREST_FILL := Color("34285a")                       # heraldic indigo, like the user's crest

const ICON_DIR := "res://assets/art/icons/"
const EMBLEM_DIR := "res://assets/art/emblems/"
## Legacy SVG names (assets/ui/icons) -> the user's painted PNG icons in assets/art/icons.
const LEGACY_ICONS := {
	"broadsword": "attack", "checked-shield": "block", "eye-target": "eye_lock", "hand": "talk",
	"knapsack": "inventory", "walk": "sneak", "glyph:map": "map",
}
## Rank index (Game.RANKS) -> emblem file in assets/art/emblems.
const RANK_EMBLEMS := ["hammer_wheat", "hammer_wheat", "oak_tree", "oak_tree", "tower_crown", "tower_crown", "phoenix"]

static var _tex := {}
static var _faces := {}


## The user's PNG icon (attack, block, eye_lock, health, inventory, map, sneak, stamina, talk).
static func icon(icon_name: String) -> Texture2D:
	return _load(ICON_DIR + icon_name + ".png")


static func emblem(emblem_name: String) -> Texture2D:
	return _load(EMBLEM_DIR + emblem_name + ".png")


static func rank_emblem(rank: int) -> Texture2D:
	return emblem(RANK_EMBLEMS[clampi(rank, 0, RANK_EMBLEMS.size() - 1)])


static func _load(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex[path] = t
	return t


## Vector (SVG) icons drawn straight from their imported texture showed as white squares in
## the game, so HUD code draws a CPU-rasterised copy instead (cached).
static func bake(tex: Texture2D, px := 96) -> Texture2D:
	if tex == null:
		return null
	var key := "bake|%d|%s" % [px, tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())]
	if _tex.has(key):
		return _tex[key]
	var img := tex.get_image()
	var out: Texture2D = tex
	if img:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_tex[key] = out
	return out


static func item_icon(item_id: String) -> Texture2D:
	return bake(UITheme.icon("items/" + item_id))


## Any HUD icon name (old SVG names, "glyph:map", or a user PNG name) as a texture, plus
## whether it is a flat white glyph that should be tinted ivory.
static func resolve_icon(icon_name: String) -> Array:
	if icon_name == "":
		return [null, false]
	if LEGACY_ICONS.has(icon_name):
		return [icon(LEGACY_ICONS[icon_name]), false]
	var png := icon(icon_name)
	if png != null:
		return [png, false]
	if icon_name.begins_with("glyph:"):
		return [UITheme.glyph(icon_name.trim_prefix("glyph:")), true]
	return [bake(UITheme.icon(icon_name)), true]


## Round dark button face with a gold rim and an ivory glyph. Cached by look.
##   fill: centre colour (dark; tinted for attack / block / dodge), glyph: Texture2D or null.
static func round_face(size: int, fill: Color, glyph: Texture2D = null, tint_glyph := false, glyph_scale := 0.62,
		rim_color := GOLD) -> ImageTexture:
	var key := "%d|%s|%s|%s|%s|%s" % [size, fill.to_html(), glyph.get_rid().get_id() if glyph else 0, tint_glyph, glyph_scale, rim_color.to_html()]
	if _faces.has(key):
		return _faces[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var big_r := size * 0.5 - 1.0
	var rim_w := maxf(2.5, size * 0.055)
	var rim_hi := rim_color.lightened(0.45)
	var rim_lo := rim_color.darkened(0.55)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var cover := clampf(big_r - d + 0.5, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var col: Color
			if d > big_r - rim_w:
				# Metal rim: lit from the top left, darker on the far side, hairline inside.
				var lit := clampf(0.5 + ((c.x - p.x) + (c.y - p.y)) / (size * 1.1), 0.0, 1.0)
				col = rim_lo.lerp(rim_hi, lit)
				var edge := clampf((d - (big_r - rim_w)) / rim_w, 0.0, 1.0)
				col = col.lerp(rim_lo.darkened(0.3), smoothstep(0.75, 1.0, edge) * 0.6)
			else:
				var t := d / big_r
				col = fill.lerp(fill.darkened(0.45), smoothstep(0.2, 1.0, t))
				col = col.lerp(Color.WHITE, clampf(1.0 - p.y / size * 2.0, 0.0, 1.0) * 0.06)
				var inner := big_r - rim_w - 1.6
				if absf(d - inner) < 0.9:
					col = col.lerp(rim_color, 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, cover * (0.96 if d < big_r - rim_w else 1.0)))
	if glyph:
		var src := glyph.get_image()
		if src:
			var ic := src.duplicate() as Image
			ic.convert(Image.FORMAT_RGBA8)
			var s := int(size * glyph_scale)
			ic.resize(s, s, Image.INTERPOLATE_LANCZOS)
			if tint_glyph:
				for y in s:
					for x in s:
						var q := ic.get_pixel(x, y)
						if q.a > 0.0:
							ic.set_pixel(x, y, Color(IVORY.r, IVORY.g, IVORY.b, q.a))
			img.blend_rect(ic, Rect2i(0, 0, s, s), Vector2i((size - s) / 2, (size - s) / 2))
	var tex := ImageTexture.create_from_image(img)
	_faces[key] = tex
	return tex


# --- shapes ------------------------------------------------------------------------

static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Heater-shield outline inside `r` (flat top, curved point at the bottom).
static func shield_points(r: Rect2, steps := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0 := r.position.x
	var y0 := r.position.y
	var w := r.size.x
	var h := r.size.y
	pts.append(Vector2(x0, y0 + h * 0.06))
	pts.append(Vector2(x0 + w * 0.5, y0))
	pts.append(Vector2(x0 + w, y0 + h * 0.06))
	pts.append(Vector2(x0 + w, y0 + h * 0.5))
	for i in range(1, steps):
		var t := i / float(steps)
		var a := Vector2(x0 + w, y0 + h * 0.5)
		var b := Vector2(x0 + w * 0.5, y0 + h)
		var ctrl := Vector2(x0 + w, y0 + h * 0.86)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	pts.append(Vector2(x0 + w * 0.5, y0 + h))
	for i in range(1, steps):
		var t := i / float(steps)
		var a := Vector2(x0 + w * 0.5, y0 + h)
		var b := Vector2(x0, y0 + h * 0.5)
		var ctrl := Vector2(x0, y0 + h * 0.86)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	pts.append(Vector2(x0, y0 + h * 0.5))
	return pts


## Heraldic crest badge: indigo shield, double gold outline, a gold emblem in the middle.
static func draw_crest(ci: CanvasItem, r: Rect2, emblem_tex: Texture2D, fill := CREST_FILL, alpha := 1.0) -> void:
	var outer := shield_points(r)
	var shadow := PackedVector2Array()
	for p in outer:
		shadow.append(p + Vector2(0, 2))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.4 * alpha))
	ci.draw_colored_polygon(outer, Color(fill, alpha))
	# Lighter top half for a satin look.
	var top := shield_points(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, r.size.y * 0.5)), 2)
	ci.draw_colored_polygon(PackedVector2Array([top[0], top[1], top[2], top[3], top[top.size() - 1]]), Color(1, 1, 1, 0.07 * alpha))
	var closed := outer.duplicate()
	closed.append(outer[0])
	ci.draw_polyline(closed, Color(GOLD_BRIGHT, alpha), maxf(1.5, r.size.x * 0.05), true)
	var inset := shield_points(Rect2(r.position + r.size * 0.09, r.size * 0.82))
	inset.append(inset[0])
	ci.draw_polyline(inset, Color(GOLD, 0.55 * alpha), 1.0, true)
	if emblem_tex:
		var s := minf(r.size.x, r.size.y) * 0.62
		ci.draw_texture_rect(emblem_tex, Rect2(r.position + Vector2((r.size.x - s) * 0.5, r.size.y * 0.15), Vector2(s, s)), false, Color(1, 1, 1, alpha))


## Gold hairline frame with small L-shaped corner ornaments and a diamond on each edge.
static func draw_ornate_frame(ci: CanvasItem, r: Rect2, col := GOLD, alpha := 1.0, corner := 14.0) -> void:
	var c := Color(col, alpha)
	var dim := Color(col, 0.4 * alpha)
	ci.draw_rect(r, dim, false, 1.0)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0     # which corner: 0 tl, 1 tr, 2 bl, 3 br
		var sy := -1.0 if i < 2 else 1.0
		var corner_pt := Vector2(r.end.x if sx > 0 else r.position.x, r.end.y if sy > 0 else r.position.y)
		var q := corner_pt + Vector2(-sx * 4.0, -sy * 4.0)
		ci.draw_polyline(PackedVector2Array([q + Vector2(-sx * corner, 0), q, q + Vector2(0, -sy * corner)]), c, 1.5, true)
		ci.draw_polyline(PackedVector2Array([q + Vector2(-sx * (corner - 5.0), -sy * 5.0), q + Vector2(-sx * 5.0, -sy * 5.0),
			q + Vector2(-sx * 5.0, -sy * (corner - 5.0))]), dim, 1.0, true)
		diamond(ci, corner_pt, 2.6, c)
	diamond(ci, Vector2(r.get_center().x, r.position.y), 3.0, c)
	diamond(ci, Vector2(r.get_center().x, r.end.y), 3.0, c)


## A horizontal gold rule that fades out at both ends, with a centre diamond.
static func draw_rule(ci: CanvasItem, from: Vector2, to: Vector2, col := GOLD, alpha := 1.0) -> void:
	var m := (from + to) * 0.5
	var gap := 9.0
	var clear := Color(col, 0.0)
	var solid := Color(col, 0.85 * alpha)
	ci.draw_polyline_colors(PackedVector2Array([from, m - Vector2(gap, 0)]), PackedColorArray([clear, solid]), 1.5, true)
	ci.draw_polyline_colors(PackedVector2Array([m + Vector2(gap, 0), to]), PackedColorArray([solid, clear]), 1.5, true)
	diamond(ci, m, 3.5, Color(col, alpha))


static func draw_sun(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r * 0.55, col)
	for i in 8:
		var a := i * TAU / 8.0
		ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.78, c + Vector2(cos(a), sin(a)) * r * 1.05, col, maxf(1.2, r * 0.14), true)


static func draw_moon(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var c2 := c + Vector2(r * 0.42, -r * 0.2)
	var r2 := r * 0.82
	var outer_pts: Array[Vector2] = []
	var inner_pts: Array[Vector2] = []
	var n := 40
	# Start the outer walk just after a dropped point so the kept arc is contiguous.
	var start := 0
	for i in n:
		var p := c + Vector2(cos(i * TAU / n), sin(i * TAU / n)) * r
		var pp := c + Vector2(cos((i - 1) * TAU / n), sin((i - 1) * TAU / n)) * r
		if p.distance_to(c2) >= r2 and pp.distance_to(c2) < r2:
			start = i
			break
	for k in n:
		var i := (start + k) % n
		var p := c + Vector2(cos(i * TAU / n), sin(i * TAU / n)) * r
		if p.distance_to(c2) >= r2:
			outer_pts.append(p)
	for i in n:
		var q := c2 + Vector2(cos(i * TAU / n), sin(i * TAU / n)) * r2
		if q.distance_to(c) <= r:
			inner_pts.append(q)
	if outer_pts.size() < 3 or inner_pts.size() < 2:
		ci.draw_circle(c, r, col)
		return
	if outer_pts[outer_pts.size() - 1].distance_to(inner_pts[0]) > outer_pts[outer_pts.size() - 1].distance_to(inner_pts[inner_pts.size() - 1]):
		inner_pts.reverse()
	var poly := PackedVector2Array()
	poly.append_array(outer_pts)
	# Walk the inner arc back towards the start of the outer arc.
	inner_pts.reverse()
	poly.append_array(inner_pts)
	if Geometry2D.triangulate_polygon(poly).is_empty():
		poly = PackedVector2Array(outer_pts)
		inner_pts.reverse()
		poly.append_array(inner_pts)
	if Geometry2D.triangulate_polygon(poly).is_empty():
		ci.draw_circle(c, r, col)
		return
	ci.draw_colored_polygon(poly, col)


## Ivory outlined text used over the 3D world (no panel behind it).
static func outline_label(l: Label, size: int, color := IVORY, font: Font = null, outline := 5) -> void:
	l.add_theme_font_override("font", font if font else AF.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The HUD's small dark card: panel colour + a thin gold frame, sharper than AF.panel.
static func card_box(alpha := 0.86, margin := 12) -> StyleBoxFlat:
	var s := AF.panel(Color(0.045, 0.04, 0.036, alpha), Color(GOLD, 0.8), 6, margin)
	s.shadow_size = 8
	s.shadow_color = Color(0, 0, 0, 0.45)
	return s


## Is this a phone / tablet (or `--touch`)? Touch keeps the technique ring around the attack
## button. (DisplayServer.is_touchscreen_available() is always true here because the project
## emulates touch from the mouse, so it cannot be used.)
static func touch_mode() -> bool:
	if "--touch" in OS.get_cmdline_user_args():
		return true
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## Imported textures can draw as white placeholders for their first few frames; canvas items
## that draw them only when something changes call this once after building so they repaint.
static func redraw_soon(ci: CanvasItem, seconds := 0.4) -> void:
	if ci.is_inside_tree():
		var wr: WeakRef = weakref(ci)
		ci.get_tree().create_timer(seconds).timeout.connect(func() -> void:
			var n: Variant = wr.get_ref()
			if n != null:
				(n as CanvasItem).queue_redraw())
