extends RefCounted
## Drawing helpers for the War Map: kind glyphs and the chess-like tokens of the three display styles
## (docs/design/WAR_COMMAND_RULEBOOK.md §2). Static, stateless; every call draws into the CanvasItem given.
##   style 0 Realistic  : small muted military symbols on a topographic map
##   style 1 Tactical 2D: clean bright shapes on dark ground
##   style 2 War-table  : wooden pawns with cloth banners on parchment

const REALISTIC := 0
const TACTICAL := 1
const TABLE := 2
const STYLE_NAMES := ["Realistic", "Tactical 2D", "War-table"]

const BLUE := Color("3d7be0")
const RED := Color("c23b30")
const HOSTILE_COLS := [Color("c23b30"), Color("8e44ad"), Color("d0741f"), Color("1f9d8a")]
const INK := Color("2b2115")
const CREAM := Color("f2e6c6")
const WOOD := Color("7a5533")
const WOOD_DARK := Color("4d331d")
const WOOD_LIGHT := Color("a87c4a")
const GOLD := Color("f0c860")


static func faction_color(faction: String) -> Color:
	if faction == "player":
		return BLUE
	return RED


## Human word for a 0..1 value.
static func level_word(v: float) -> String:
	if v >= 0.75:
		return "High"
	if v >= 0.5:
		return "Good"
	if v >= 0.3:
		return "Low"
	return "Broken"


static func quality_word(q: float) -> String:
	if q >= 0.8:
		return "Elite"
	if q >= 0.65:
		return "Veteran"
	if q >= 0.45:
		return "Trained"
	return "Green"


# ---------------------------------------------------------------- glyphs ----

## A kind icon centred on `c`, roughly s pixels from the centre to the edge.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color, w := 2.0) -> void:
	match kind:
		"infantry":
			ci.draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.6), col, w, true)
			ci.draw_line(c + Vector2(-s * 0.42, s * 0.1), c + Vector2(s * 0.42, s * 0.1), col, w, true)
			ci.draw_line(c + Vector2(0, s * 0.62), c + Vector2(0, s * 0.95), col, w * 1.6, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.12), c + Vector2(-s * 0.13, -s * 0.8), c + Vector2(s * 0.13, -s * 0.8)]), col)
		"spear":
			ci.draw_line(c + Vector2(-s * 0.55, s * 0.9), c + Vector2(s * 0.5, -s * 0.7), col, w, true)
			var tip := c + Vector2(s * 0.62, -s * 0.9)
			ci.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s * 0.36, s * 0.05), tip + Vector2(-s * 0.05, s * 0.36)]), col)
		"archer":
			ci.draw_arc(c + Vector2(s * 0.15, 0), s * 0.85, deg_to_rad(110), deg_to_rad(250), 14, col, w, true)
			ci.draw_line(c + Vector2(s * 0.15 + cos(deg_to_rad(110)) * s * 0.85, sin(deg_to_rad(110)) * s * 0.85),
				c + Vector2(s * 0.15 + cos(deg_to_rad(250)) * s * 0.85, sin(deg_to_rad(250)) * s * 0.85), col, w * 0.6, true)
			ci.draw_line(c + Vector2(-s * 0.7, 0), c + Vector2(s * 0.85, 0), col, w * 0.9, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 1.0, 0), c + Vector2(s * 0.6, -s * 0.22), c + Vector2(s * 0.6, s * 0.22)]), col)
		"heavy_cav":
			ci.draw_arc(c + Vector2(0, -s * 0.05), s * 0.7, deg_to_rad(-200), deg_to_rad(20), 16, col, w * 1.3, true)
			ci.draw_line(c + Vector2(-s * 0.68, s * 0.12), c + Vector2(-s * 0.68, s * 0.8), col, w * 1.3, true)
			ci.draw_line(c + Vector2(s * 0.68, s * 0.12), c + Vector2(s * 0.68, s * 0.8), col, w * 1.3, true)
		"light_cav":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.55, s * 0.15), c + Vector2(-s * 0.05, s * 0.15),
				c + Vector2(-s * 0.25, s), c + Vector2(s * 0.6, -s * 0.2), c + Vector2(s * 0.08, -s * 0.2)]), col)
		"mage":
			var pts := PackedVector2Array()
			for i in 8:
				var a := TAU * float(i) / 8.0 - PI / 2.0
				var rr := s if i % 2 == 0 else s * 0.38
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
		"engineer":
			ci.draw_arc(c, s * 0.55, 0, TAU, 18, col, w * 1.3, true)
			for i in 6:
				var a2 := TAU * float(i) / 6.0
				ci.draw_line(c + Vector2(cos(a2), sin(a2)) * s * 0.55, c + Vector2(cos(a2), sin(a2)) * s * 0.95, col, w * 1.5, true)
			ci.draw_circle(c, s * 0.16, col)
		"scout":
			var top := PackedVector2Array()
			var bot := PackedVector2Array()
			for i in 11:
				var x := -1.0 + float(i) * 0.2
				var yy := (1.0 - x * x) * s * 0.55
				top.append(c + Vector2(x * s, -yy))
				bot.append(c + Vector2(x * s, yy))
			ci.draw_polyline(top, col, w, true)
			ci.draw_polyline(bot, col, w, true)
			ci.draw_circle(c, s * 0.26, col)
		"medical":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.85), Vector2(s * 0.4, s * 1.7)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.2), Vector2(s * 1.7, s * 0.4)), col)
		"army":
			ci.draw_line(c + Vector2(-s * 0.55, s), c + Vector2(-s * 0.55, -s), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, -s), c + Vector2(s * 0.85, -s * 0.5), c + Vector2(-s * 0.55, 0)]), col)
		"swords":
			ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w * 1.3, true)
			ci.draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, w * 1.3, true)
			ci.draw_line(c + Vector2(-s * 0.7, -s * 0.15), c + Vector2(-s * 0.15, -s * 0.7), col, w, true)
			ci.draw_line(c + Vector2(s * 0.7, -s * 0.15), c + Vector2(s * 0.15, -s * 0.7), col, w, true)
		_:
			ci.draw_circle(c, s * 0.6, col)


## One dot per 100 men (max 8), or a bar for the very large.
static func dots(ci: CanvasItem, men: int, c: Vector2, col: Color, dot_r := 2.6) -> void:
	var n := clampi(int(ceil(float(men) / 100.0)), 1, 8)
	var total := float(n) * (dot_r * 2.0 + 2.0)
	for i in n:
		ci.draw_circle(c + Vector2(-total * 0.5 + (float(i) + 0.5) * (dot_r * 2.0 + 2.0), 0), dot_r, col)


static func shadow(ci: CanvasItem, c: Vector2, rx: float, ry: float, alpha := 0.35) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, Color(0, 0, 0, alpha))


static func _text_centered(ci: CanvasItem, font: Font, text: String, at: Vector2, fs: int, col: Color, outline := Color(0, 0, 0, 0.85), ow := 4) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w * 0.5, 0)
	if outline.a > 0.0:
		ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, outline)
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func text_centered(ci: CanvasItem, font: Font, text: String, at: Vector2, fs: int, col: Color, outline := Color(0, 0, 0, 0.85), ow := 4) -> void:
	_text_centered(ci, font, text, at, fs, col, outline, ow)


# ---------------------------------------------------------------- tokens ----

## Draws a piece. `c` is the token's ground point (centre of its base), r its radius in pixels.
## opts: selected, faded (0..1 alpha), font, men, label (name under the token), stack (number of units when it is
## a whole army), unknown (an enemy estimate: "?" instead of a kind glyph), moving, engaged, count_text.
static func piece(ci: CanvasItem, style: int, c: Vector2, r: float, col: Color, kind: String, opts: Dictionary) -> void:
	var a := float(opts.get("faded", 1.0))
	var font: Font = opts.get("font", ThemeDB.fallback_font)
	var men := int(opts.get("men", 0))
	var sel := bool(opts.get("selected", false))
	var count_text := String(opts.get("count_text", str(men) if men > 0 else ""))
	var fs := int(clampf(r * 0.52, 15.0, 24.0))
	match style:
		REALISTIC:
			var w := r * 1.55
			var h := r * 1.1
			var rect := Rect2(c + Vector2(-w * 0.5, -h - r * 0.15), Vector2(w, h))
			var fill := Color(col.r * 0.72 + 0.1, col.g * 0.72 + 0.1, col.b * 0.72 + 0.08, 0.92 * a)
			shadow(ci, c + Vector2(1.5, 1.5), r * 0.7, r * 0.22, 0.25 * a)
			ci.draw_rect(rect, fill)
			ci.draw_rect(rect, Color(INK, 0.9 * a), false, 2.0)
			if bool(opts.get("unknown", false)):
				_text_centered(ci, font, "?", rect.get_center() + Vector2(0, fs * 0.36), int(fs * 1.4), Color(CREAM, a), Color(0, 0, 0, 0))
			else:
				glyph(ci, kind, rect.get_center(), h * 0.34, Color(CREAM, a), 2.0)
			ci.draw_line(c + Vector2(0, -r * 0.15), c, Color(INK, a), 2.0)
			if men > 0:
				dots(ci, men, rect.position + Vector2(w * 0.5, -5), Color(INK, 0.85 * a), 2.3)
			if count_text != "":
				_text_centered(ci, font, count_text, c + Vector2(0, fs + 3), fs, Color(INK, a), Color(CREAM, 0.7 * a), 3)
			if sel:
				ci.draw_rect(rect.grow(5), GOLD, false, 3.0)
		TACTICAL:
			var bright := Color(minf(col.r * 1.12 + 0.05, 1.0), minf(col.g * 1.12 + 0.05, 1.0), minf(col.b * 1.12 + 0.05, 1.0), a)
			var cc := c + Vector2(0, -r)
			shadow(ci, c + Vector2(0, 2), r * 0.85, r * 0.25, 0.4 * a)
			var pts: PackedVector2Array
			match kind:
				"heavy_cav", "light_cav":
					pts = PackedVector2Array([cc + Vector2(0, -r), cc + Vector2(r * 1.02, 0), cc + Vector2(0, r), cc + Vector2(-r * 1.02, 0)])
				"archer", "mage":
					pts = PackedVector2Array()
					for i in 20:
						pts.append(cc + Vector2(cos(TAU * float(i) / 20.0), sin(TAU * float(i) / 20.0)) * r * 0.95)
				"scout", "army":
					pts = PackedVector2Array([cc + Vector2(0, -r), cc + Vector2(r * 0.95, r * 0.8), cc + Vector2(-r * 0.95, r * 0.8)])
				"engineer", "medical":
					pts = PackedVector2Array([cc + Vector2(-r * 0.85, -r * 0.85), cc + Vector2(r * 0.85, -r * 0.85), cc + Vector2(r * 0.85, r * 0.85), cc + Vector2(-r * 0.85, r * 0.85)])
				_:
					pts = PackedVector2Array([cc + Vector2(-r * 0.9, -r * 0.8), cc + Vector2(r * 0.9, -r * 0.8), cc + Vector2(r * 0.9, r * 0.25), cc + Vector2(0, r * 0.95), cc + Vector2(-r * 0.9, r * 0.25)])
			ci.draw_colored_polygon(pts, bright)
			var closed := pts.duplicate()
			closed.append(pts[0])
			ci.draw_polyline(closed, Color(1, 1, 1, 0.92 * a) if not sel else GOLD, 3.0 if sel else 2.0, true)
			if bool(opts.get("unknown", false)):
				_text_centered(ci, font, "?", cc + Vector2(0, fs * 0.38), int(fs * 1.5), Color(1, 1, 1, a), Color(0, 0, 0, 0))
			else:
				glyph(ci, kind, cc + (Vector2(0, r * 0.12) if kind in ["scout", "army"] else Vector2.ZERO), r * 0.44, Color(0.05, 0.06, 0.08, a) if col.get_luminance() > 0.45 else Color(1, 1, 1, a), 2.2)
			if count_text != "":
				_text_centered(ci, font, count_text, c + Vector2(0, fs + 4), fs, Color(1, 1, 1, a))
			if int(opts.get("stack", 0)) > 1:
				ci.draw_circle(cc + Vector2(r * 0.85, -r * 0.85), r * 0.36, Color(0.05, 0.06, 0.08, 0.95 * a))
				_text_centered(ci, font, str(int(opts["stack"])), cc + Vector2(r * 0.85, -r * 0.85 + fs * 0.32), int(fs * 0.8), Color(1, 1, 1, a), Color(0, 0, 0, 0))
		_:
			# war-table: a turned wooden pawn with a cloth banner
			var base_rx := r * 0.95
			var base_ry := r * 0.36
			shadow(ci, c + Vector2(r * 0.25, r * 0.12), base_rx * 1.05, base_ry, 0.4 * a)
			var wood := Color(WOOD, a)
			var wood_d := Color(WOOD_DARK, a)
			var wood_l := Color(WOOD_LIGHT, a)
			# base: two stacked ellipses
			_ellipse(ci, c + Vector2(0, -2), base_rx, base_ry, wood_d)
			_ellipse(ci, c + Vector2(0, -r * 0.14), base_rx, base_ry, wood)
			_ellipse(ci, c + Vector2(0, -r * 0.16), base_rx * 0.8, base_ry * 0.7, wood_l)
			# tapered body
			var body := PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.2), c + Vector2(r * 0.5, -r * 0.2), c + Vector2(r * 0.26, -r * 1.05), c + Vector2(-r * 0.26, -r * 1.05)])
			ci.draw_colored_polygon(body, wood)
			ci.draw_line(c + Vector2(-r * 0.1, -r * 0.24), c + Vector2(-r * 0.06, -r * 1.02), Color(wood_l, 0.8 * a), 3.0)
			# faction band
			var band := PackedVector2Array([c + Vector2(-r * 0.42, -r * 0.48), c + Vector2(r * 0.42, -r * 0.48), c + Vector2(r * 0.34, -r * 0.72), c + Vector2(-r * 0.34, -r * 0.72)])
			ci.draw_colored_polygon(band, Color(col.r, col.g, col.b, a))
			# head and pole
			ci.draw_circle(c + Vector2(0, -r * 1.2), r * 0.24, wood_l)
			ci.draw_arc(c + Vector2(0, -r * 1.2), r * 0.24, 0, TAU, 14, wood_d, 1.5, true)
			var pole_top := c + Vector2(0, -r * 2.0)
			ci.draw_line(c + Vector2(0, -r * 1.3), pole_top, wood_d, 3.0, true)
			var cloth := PackedVector2Array([pole_top + Vector2(0, 0), pole_top + Vector2(r * 1.15, r * 0.06), pole_top + Vector2(r * 0.95, r * 0.42), pole_top + Vector2(r * 1.15, r * 0.78), pole_top + Vector2(0, r * 0.84)])
			ci.draw_colored_polygon(cloth, Color(col.r, col.g, col.b, a))
			var cl := cloth.duplicate()
			cl.append(cloth[0])
			ci.draw_polyline(cl, Color(0, 0, 0, 0.55 * a), 1.5, true)
			if bool(opts.get("unknown", false)):
				_text_centered(ci, font, "?", pole_top + Vector2(r * 0.5, r * 0.62), int(fs * 1.05), Color(CREAM, a), Color(0, 0, 0, 0))
			else:
				glyph(ci, kind, pole_top + Vector2(r * 0.5, r * 0.42), r * 0.27, Color(CREAM, a), 1.8)
			if count_text != "":
				var tw := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
				var plate := Rect2(c + Vector2(-tw * 0.5, r * 0.22), Vector2(tw, fs + 6.0))
				ci.draw_rect(plate, Color(CREAM.r, CREAM.g, CREAM.b, 0.92 * a))
				ci.draw_rect(plate, Color(INK, 0.8 * a), false, 1.5)
				_text_centered(ci, font, count_text, plate.get_center() + Vector2(0, fs * 0.36), fs, Color(INK, a), Color(0, 0, 0, 0))
			if sel:
				ci.draw_arc(c + Vector2(0, -r * 0.1), base_rx * 1.25, 0, TAU, 28, GOLD, 3.0, true)
	if sel and style != TABLE:
		ci.draw_arc(c + Vector2(0, -r * 0.5), r * 1.45, 0, TAU, 28, Color(GOLD, 0.9), 2.0, true)
	var lab := String(opts.get("label", ""))
	if lab != "":
		var ly := fs + (10.0 if style != TABLE else fs + 18.0)
		_text_centered(ci, font, lab, c + Vector2(0, ly + fs * 0.5), maxi(14, int(fs * 0.85)), Color(1, 1, 1, a) if style != REALISTIC else Color(INK, a), Color(0, 0, 0, 0.8) if style != REALISTIC else Color(CREAM, 0.75), 4)
	if bool(opts.get("engaged", false)):
		ci.draw_circle(c + Vector2(-r * 0.95, -r * 1.3), r * 0.36, Color(0, 0, 0, 0.75))
		glyph(ci, "swords", c + Vector2(-r * 0.95, -r * 1.3), r * 0.26, Color("ffb35a"), 2.2)


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * float(i) / 22.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


## Dashed line (movement / order arrows).
static func dashed(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, w := 2.5, dash := 12.0, gap := 8.0) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 1.0:
		return
	var dir := d / dist
	var t := 0.0
	while t < dist:
		ci.draw_line(from + dir * t, from + dir * minf(t + dash, dist), col, w, true)
		t += dash + gap


static func arrow_head(ci: CanvasItem, tip: Vector2, dir: Vector2, col: Color, size := 14.0) -> void:
	var n := dir.normalized()
	var p := n.orthogonal()
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - n * size + p * size * 0.55, tip - n * size - p * size * 0.55]), col)
