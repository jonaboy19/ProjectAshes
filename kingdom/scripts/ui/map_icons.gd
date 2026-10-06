extends RefCounted
## Vector icons for places, drawn with CanvasItem primitives so they stay crisp
## at any zoom and cost nothing to load. Shared by the compass and the world map.
## Usage: MapIcons.draw(self, place_kind, centre, size, color).


const HOSTILE := Color("ff5d5d")
const QUEST := Color("f5b841")
const SETTLEMENT := Color("f2efe8")
const TRAVEL := Color("3ec7c2")
const NATURE := Color("8fd694")
const WATER := Color("7cc4ff")
const RUIN := Color("c9b79c")
const HOLY := Color("ffb86b")

# Storybook-map ink palette (the parchment world map; the compass bar keeps the dark badge look above).
const INK := Color("3b2812")
const CREAM := Color("f6e9c8")
const RED := Color("b3372f")
const GOLD := Color("e6ad2f")
const BLUE := Color("3f6fb5")
const STONE := Color("c9bfae")
const STONE_DARK := Color("9a8f7d")
const WOOD := Color("8a5a32")
const TILE := Color("c9573a")
const VIOLET := Color("8a4fd0")
const STONE_COLORS := {
	"glowing": Color("4fe0d6"), "dim": Color("f1c04a"), "cracked": Color("ee7a3a"), "dark": Color("7d7a86"),
}


## Icon colour for a place (hostile camps red, travel points teal, ...).
static func color_for(place: Dictionary) -> Color:
	if place.get("hostile", false):
		return HOSTILE
	match String(place.get("kind", "")):
		"village", "town", "castle", "capital", "frontier_town":
			return SETTLEMENT
		"waystation", "ferry":
			return TRAVEL
		"lake", "river", "bridge":
			return WATER
		"forest", "farm", "hollow", "hidden_place":
			return NATURE
		"shrine", "ruined_shrine", "wayshrine":
			return HOLY
	return RUIN


## Draws a round badge with a glyph for `kind`. `s` is the badge diameter.
static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, color: Color, alpha := 1.0) -> void:
	var r := s * 0.5
	var bg := Color(0.055, 0.063, 0.098, 0.88 * alpha)
	var col := Color(color, color.a * alpha)
	ci.draw_circle(c, r + 1.5, Color(0, 0, 0, 0.35 * alpha))
	ci.draw_circle(c, r, bg)
	ci.draw_arc(c, r - 0.5, 0, TAU, 28, col, maxf(1.5, s * 0.07), true)
	glyph(ci, kind, c, r * 0.62, col)


## The glyph alone, fitting a circle of radius g.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, g: float, col: Color) -> void:
	var w := maxf(1.5, g * 0.22)
	match kind:
		"castle", "capital":
			var base := PackedVector2Array([c + Vector2(-g, g * 0.8), c + Vector2(-g, -g * 0.5), c + Vector2(-g * 0.55, -g * 0.5),
				c + Vector2(-g * 0.55, -g * 0.1), c + Vector2(-g * 0.2, -g * 0.1), c + Vector2(-g * 0.2, -g * 0.9),
				c + Vector2(g * 0.2, -g * 0.9), c + Vector2(g * 0.2, -g * 0.1), c + Vector2(g * 0.55, -g * 0.1),
				c + Vector2(g * 0.55, -g * 0.5), c + Vector2(g, -g * 0.5), c + Vector2(g, g * 0.8)])
			ci.draw_colored_polygon(base, col)
		"village", "town", "farm", "frontier_town":
			var roof := PackedVector2Array([c + Vector2(-g, -g * 0.05), c + Vector2(0, -g * 0.95), c + Vector2(g, -g * 0.05)])
			ci.draw_colored_polygon(roof, col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.68, -g * 0.05), Vector2(g * 1.36, g * 0.85)), col)
			if kind == "town":
				ci.draw_rect(Rect2(c + Vector2(g * 0.35, -g * 0.95), Vector2(g * 0.3, g * 0.6)), col)
		"waystation", "ferry":
			ci.draw_line(c + Vector2(-g * 0.6, g * 0.9), c + Vector2(-g * 0.6, -g * 0.9), col, w, true)
			var flag := PackedVector2Array([c + Vector2(-g * 0.6, -g * 0.9), c + Vector2(g * 0.9, -g * 0.55), c + Vector2(-g * 0.6, -g * 0.15)])
			ci.draw_colored_polygon(flag, col)
		"goblin_warren", "orc_village", "bandit_camp":
			# Crossed blades.
			ci.draw_line(c + Vector2(-g, -g), c + Vector2(g, g), col, w * 1.2, true)
			ci.draw_line(c + Vector2(g, -g), c + Vector2(-g, g), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-g * 0.95, g * 0.35), c + Vector2(-g * 0.35, g * 0.95), col, w, true)
			ci.draw_line(c + Vector2(g * 0.95, g * 0.35), c + Vector2(g * 0.35, g * 0.95), col, w, true)
		"rift":
			var bolt := PackedVector2Array([c + Vector2(g * 0.2, -g), c + Vector2(-g * 0.55, g * 0.1), c + Vector2(-g * 0.05, g * 0.1),
				c + Vector2(-g * 0.25, g), c + Vector2(g * 0.6, -g * 0.15), c + Vector2(g * 0.05, -g * 0.15)])
			ci.draw_colored_polygon(bolt, col)
		"shrine", "ruined_shrine", "wayshrine":
			var flame := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				var rr := g * (0.62 + 0.38 * pow(maxf(0.0, -sin(a)), 3.0))
				flame.append(c + Vector2(cos(a) * rr * 0.75, sin(a) * rr + g * 0.2))
			ci.draw_colored_polygon(flame, col)
		"lake", "river", "bridge":
			for k in 2:
				var pts := PackedVector2Array()
				for i in 9:
					var x := -g + g * 2.0 * i / 8.0
					pts.append(c + Vector2(x, (k - 0.5) * g * 0.8 + sin(i * 0.8) * g * 0.22))
				ci.draw_polyline(pts, col, w, true)
		"forest", "hollow", "hidden_place":
			var tree := PackedVector2Array([c + Vector2(0, -g), c + Vector2(g * 0.8, g * 0.45), c + Vector2(-g * 0.8, g * 0.45)])
			ci.draw_colored_polygon(tree, col)
			ci.draw_line(c + Vector2(0, g * 0.4), c + Vector2(0, g), col, w, true)
		"mine":
			ci.draw_line(c + Vector2(-g * 0.8, g * 0.9), c + Vector2(g * 0.5, -g * 0.4), col, w, true)
			ci.draw_arc(c + Vector2(g * 0.2, -g * 0.15), g * 0.8, -PI * 0.95, -PI * 0.05, 10, col, w, true)
		"tower_ruin", "watchfort", "fort", "rift_outpost", "academy":
			ci.draw_rect(Rect2(c + Vector2(-g * 0.45, -g * 0.55), Vector2(g * 0.9, g * 1.45)), col)
			for i in 3:
				ci.draw_rect(Rect2(c + Vector2(-g * 0.6 + i * g * 0.45, -g), Vector2(g * 0.3, g * 0.4)), col)
		"quest":
			ci.draw_line(c + Vector2(-g * 0.55, g), c + Vector2(-g * 0.55, -g), col, w, true)
			var qf := PackedVector2Array([c + Vector2(-g * 0.55, -g), c + Vector2(g * 0.85, -g * 0.6), c + Vector2(-g * 0.55, -g * 0.15)])
			ci.draw_colored_polygon(qf, col)
		_:
			var diamond := PackedVector2Array([c + Vector2(0, -g * 0.8), c + Vector2(g * 0.8, 0), c + Vector2(0, g * 0.8), c + Vector2(-g * 0.8, 0)])
			ci.draw_colored_polygon(diamond, col)


## Painted map marker: an illustrated little landmark on a soft cream halo.
## `s` is the icon's nominal size in pixels (a village is about s wide).
static func draw_marker(ci: CanvasItem, kind: String, c: Vector2, s: float, hostile := false, selected := false) -> void:
	var g := s * 0.5
	ci.draw_circle(c + Vector2(0, g * 0.12), g * 1.08, Color(CREAM, 0.62))
	ci.draw_arc(c + Vector2(0, g * 0.12), g * 1.08, 0, TAU, 28, Color(RED if hostile else INK, 0.85 if hostile else 0.55),
		maxf(1.5, s * 0.06) * (1.5 if hostile else 1.0), true)
	if selected:
		ci.draw_arc(c + Vector2(0, g * 0.12), g * 1.08 + 5.0, 0, TAU, 32, GOLD, 3.0, true)
		ci.draw_arc(c + Vector2(0, g * 0.12), g * 1.08 + 5.0, 0, TAU, 32, Color(INK, 0.6), 1.0, true)
	var w := maxf(1.2, s * 0.05)
	match kind:
		"castle", "capital":
			_castle(ci, c, g, w)
		"village":
			_house(ci, c + Vector2(0, g * 0.05), g * 0.72, TILE, w)
		"town":
			_house(ci, c + Vector2(-g * 0.38, g * 0.22), g * 0.5, BLUE, w)
			_house(ci, c + Vector2(g * 0.34, g * 0.08), g * 0.62, BLUE, w)
			_house(ci, c + Vector2(-g * 0.02, -g * 0.08), g * 0.58, TILE, w)
		"frontier_town":
			_palisade(ci, c, g, w)
		"fort":
			_fort(ci, c, g, w)
		"watchfort", "academy", "keep", "estate", "chapel":
			_tower(ci, c, g, STONE, BLUE if kind in ["watchfort", "keep"] else GOLD, w, false)
		"elder_stone":
			_menhir(ci, c, g, w)
		"border_gate":
			_gate(ci, c, g, w)
		"pass":
			_peaks(ci, c, g, w)
		"scar_arena":
			_rift(ci, c, g, w)
		"caravan_camp":
			_tent(ci, c, g, GOLD, w, RED)
		"landmark", "glade", "windmill_hill":
			_signpost(ci, c, g, w)
		"tower_ruin":
			_tower(ci, c, g, STONE_DARK, Color(0, 0, 0, 0), w, true)
		"rift_outpost":
			_tent(ci, c, g, VIOLET.lightened(0.15), w, VIOLET)
		"rift":
			_rift(ci, c, g, w)
		"bandit_camp":
			_tent(ci, c, g, RED, w, INK)
		"goblin_warren", "orc_village":
			_warren(ci, c, g, w)
		"waystation", "ferry":
			_signpost(ci, c, g, w)
		"shrine", "ruined_shrine", "wayshrine":
			_shrine(ci, c, g, w)
		"mine":
			_mine(ci, c, g, w)
		"bridge":
			_bridge(ci, c, g, w)
		"hollow", "hidden_place":
			_grove(ci, c, g, w, true)
		"forest":
			_grove(ci, c, g, w, false)
		"farm":
			_house(ci, c + Vector2(0, g * 0.05), g * 0.6, WOOD, w)
		"quest":
			glyph(ci, "quest", c, g * 0.7, GOLD)
		_:
			var d := PackedVector2Array([c + Vector2(0, -g * 0.6), c + Vector2(g * 0.6, 0), c + Vector2(0, g * 0.6), c + Vector2(-g * 0.6, 0)])
			ci.draw_colored_polygon(d, STONE_DARK)
			ci.draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), INK, w, true)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w: float) -> void:
	if fill.a > 0.0:
		ci.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, INK, w, true)


static func _rectp(c: Vector2, x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(x0, y0), c + Vector2(x1, y0), c + Vector2(x1, y1), c + Vector2(x0, y1)])


static func _house(ci: CanvasItem, c: Vector2, g: float, roof: Color, w: float) -> void:
	_poly(ci, _rectp(c, -g * 0.7, -g * 0.05, g * 0.7, g * 0.8), CREAM, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.92, -g * 0.02), c + Vector2(0, -g * 0.92), c + Vector2(g * 0.92, -g * 0.02)]), roof, w)
	ci.draw_rect(Rect2(c + Vector2(-g * 0.14, g * 0.3), Vector2(g * 0.28, g * 0.5)), WOOD)


static func _castle(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	c += Vector2(0, g * 0.1)
	# Flank towers with blue cones, central keep, gold-and-red pennant.
	for sx in [-1.0, 1.0]:
		var tx: float = sx * g * 0.66
		_poly(ci, _rectp(c, tx - g * 0.24, -g * 0.35, tx + g * 0.24, g * 0.82), STONE, w)
		_poly(ci, PackedVector2Array([c + Vector2(tx - g * 0.34, -g * 0.35), c + Vector2(tx, -g * 0.98), c + Vector2(tx + g * 0.34, -g * 0.35)]), BLUE, w)
	var keep := PackedVector2Array()
	var x := -g * 0.42
	keep.append(c + Vector2(x, g * 0.82))
	keep.append(c + Vector2(x, -g * 0.5))
	for i in 4:
		var cx := -g * 0.42 + i * g * 0.28
		keep.append(c + Vector2(cx, -g * 0.5))
		keep.append(c + Vector2(cx, -g * 0.72))
		keep.append(c + Vector2(cx + g * 0.14, -g * 0.72))
		keep.append(c + Vector2(cx + g * 0.14, -g * 0.5))
	keep.append(c + Vector2(g * 0.42, -g * 0.5))
	keep.append(c + Vector2(g * 0.42, g * 0.82))
	_poly(ci, keep, STONE, w)
	ci.draw_rect(Rect2(c + Vector2(-g * 0.11, g * 0.3), Vector2(g * 0.22, g * 0.52)), Color(INK, 0.85))
	ci.draw_line(c + Vector2(0, -g * 0.72), c + Vector2(0, -g * 1.18), INK, w, true)
	_poly(ci, PackedVector2Array([c + Vector2(0, -g * 1.18), c + Vector2(g * 0.5, -g * 1.02), c + Vector2(0, -g * 0.86)]), RED, w * 0.8)


static func _palisade(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_house(ci, c + Vector2(0, -g * 0.05), g * 0.5, WOOD, w)
	for i in 7:
		var x := -g * 0.9 + i * g * 0.3
		_poly(ci, PackedVector2Array([c + Vector2(x - g * 0.13, g * 0.85), c + Vector2(x - g * 0.13, g * 0.28), c + Vector2(x, g * 0.1), c + Vector2(x + g * 0.13, g * 0.28), c + Vector2(x + g * 0.13, g * 0.85)]), WOOD.lightened(0.15), w * 0.8)


static func _fort(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_poly(ci, _rectp(c, -g * 0.85, -g * 0.25, g * 0.85, g * 0.8), STONE, w)
	for i in 4:
		var x := -g * 0.85 + i * g * 0.5
		_poly(ci, _rectp(c, x, -g * 0.55, x + g * 0.3, -g * 0.25), STONE, w * 0.8)
	_poly(ci, _rectp(c, -g * 0.28, -g * 0.85, g * 0.28, g * 0.05), STONE_DARK, w)
	ci.draw_line(c + Vector2(0, -g * 0.85), c + Vector2(0, -g * 1.2), INK, w, true)
	_poly(ci, PackedVector2Array([c + Vector2(0, -g * 1.2), c + Vector2(g * 0.5, -g * 1.05), c + Vector2(0, -g * 0.9)]), RED, w * 0.8)
	ci.draw_rect(Rect2(c + Vector2(-g * 0.14, g * 0.3), Vector2(g * 0.28, g * 0.5)), Color(INK, 0.85))


static func _tower(ci: CanvasItem, c: Vector2, g: float, stone: Color, roof: Color, w: float, ruin: bool) -> void:
	var top := -g * 0.55
	var pts := PackedVector2Array([c + Vector2(-g * 0.42, g * 0.85), c + Vector2(-g * 0.42, top)])
	if ruin:
		pts.append_array(PackedVector2Array([c + Vector2(-g * 0.2, top - g * 0.1), c + Vector2(-g * 0.05, top + g * 0.25), c + Vector2(g * 0.15, top - g * 0.3), c + Vector2(g * 0.42, top + g * 0.1)]))
	else:
		pts.append(c + Vector2(g * 0.42, top))
	pts.append(c + Vector2(g * 0.42, g * 0.85))
	_poly(ci, pts, stone, w)
	if not ruin:
		_poly(ci, PackedVector2Array([c + Vector2(-g * 0.58, top), c + Vector2(0, -g * 1.1), c + Vector2(g * 0.58, top)]), roof, w)
	else:
		ci.draw_line(c + Vector2(-g * 0.1, g * 0.1), c + Vector2(g * 0.05, g * 0.5), INK, w, true)
	ci.draw_rect(Rect2(c + Vector2(-g * 0.1, g * 0.4), Vector2(g * 0.2, g * 0.45)), Color(INK, 0.85))


static func _tent(ci: CanvasItem, c: Vector2, g: float, col: Color, w: float, flag: Color) -> void:
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.9, g * 0.8), c + Vector2(0, -g * 0.7), c + Vector2(g * 0.9, g * 0.8)]), col, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.22, g * 0.8), c + Vector2(0, g * 0.15), c + Vector2(g * 0.22, g * 0.8)]), Color(INK, 0.85), w * 0.6)
	ci.draw_line(c + Vector2(0, -g * 0.7), c + Vector2(0, -g * 1.15), INK, w, true)
	_poly(ci, PackedVector2Array([c + Vector2(0, -g * 1.15), c + Vector2(g * 0.5, -g * 1.0), c + Vector2(0, -g * 0.85)]), flag, w * 0.8)


static func _rift(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	var bolt := PackedVector2Array([c + Vector2(g * 0.25, -g * 1.0), c + Vector2(-g * 0.6, g * 0.05), c + Vector2(-g * 0.08, g * 0.05),
		c + Vector2(-g * 0.3, g * 0.95), c + Vector2(g * 0.65, -g * 0.2), c + Vector2(g * 0.1, -g * 0.2)])
	ci.draw_circle(c, g * 0.95, Color(VIOLET, 0.35))
	_poly(ci, bolt, Color("d9a8ff"), w)


static func _warren(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	var mound := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		mound.append(c + Vector2(cos(a) * g * 0.95, g * 0.6 + sin(a) * g * 0.95))
	_poly(ci, mound, Color("6d7c46"), w)
	ci.draw_line(c + Vector2(-g * 0.55, -g * 0.45), c + Vector2(g * 0.55, g * 0.55), RED, w * 2.0, true)
	ci.draw_line(c + Vector2(g * 0.55, -g * 0.45), c + Vector2(-g * 0.55, g * 0.55), RED, w * 2.0, true)
	ci.draw_circle(c + Vector2(0, g * 0.6), g * 0.2, Color(INK, 0.9))


static func _signpost(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	ci.draw_line(c + Vector2(-g * 0.05, g * 0.85), c + Vector2(-g * 0.05, -g * 0.8), WOOD, w * 2.2, true)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.05, -g * 0.7), c + Vector2(g * 0.8, -g * 0.7), c + Vector2(g * 1.0, -g * 0.45), c + Vector2(g * 0.8, -g * 0.2), c + Vector2(-g * 0.05, -g * 0.2)]), Color("d6a55a"), w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.05, g * 0.0), c + Vector2(-g * 0.8, g * 0.0), c + Vector2(-g * 1.0, g * 0.22), c + Vector2(-g * 0.8, g * 0.44), c + Vector2(-g * 0.05, g * 0.44)]), Color("c48a44"), w)
	ci.draw_circle(c + Vector2(g * 0.5, g * 0.62), g * 0.16, Color("ffcf5a"))


static func _shrine(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.6, g * 0.85), c + Vector2(-g * 0.45, g * 0.15), c + Vector2(g * 0.45, g * 0.15), c + Vector2(g * 0.6, g * 0.85)]), STONE, w)
	var flame := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		var rr := g * (0.5 + 0.5 * pow(maxf(0.0, -sin(a)), 3.0))
		flame.append(c + Vector2(cos(a) * rr * 0.55, sin(a) * rr - g * 0.22))
	_poly(ci, flame, Color("ff9a3c"), w * 0.8)
	ci.draw_circle(c + Vector2(0, -g * 0.2), g * 0.12, Color("fff0a0"))


static func _mine(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	var arch := PackedVector2Array([c + Vector2(-g * 0.85, g * 0.8)])
	for i in 9:
		var a := PI + PI * i / 8.0
		arch.append(c + Vector2(cos(a) * g * 0.85, g * 0.1 + sin(a) * g * 0.85))
	arch.append(c + Vector2(g * 0.85, g * 0.8))
	_poly(ci, arch, STONE_DARK, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.35, g * 0.8), c + Vector2(-g * 0.35, g * 0.2), c + Vector2(0, -g * 0.05), c + Vector2(g * 0.35, g * 0.2), c + Vector2(g * 0.35, g * 0.8)]), Color(INK, 0.9), w * 0.6)
	ci.draw_line(c + Vector2(-g * 0.7, -g * 0.7), c + Vector2(g * 0.7, -g * 0.05), WOOD, w * 1.4, true)


static func _bridge(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	var deck := PackedVector2Array([c + Vector2(-g * 0.95, g * 0.55)])
	for i in 9:
		var t := i / 8.0
		deck.append(c + Vector2(-g * 0.95 + t * g * 1.9, -g * 0.3 - sin(t * PI) * g * 0.35))
	deck.append(c + Vector2(g * 0.95, g * 0.55))
	_poly(ci, deck, STONE, w)
	var arch := PackedVector2Array()
	for i in 9:
		var a := PI + PI * i / 8.0
		arch.append(c + Vector2(cos(a) * g * 0.45, g * 0.55 + sin(a) * g * 0.6))
	_poly(ci, arch, Color(0.3, 0.55, 0.78), w * 0.8)


static func _grove(ci: CanvasItem, c: Vector2, g: float, w: float, sparkle: bool) -> void:
	ci.draw_rect(Rect2(c + Vector2(-g * 0.1, g * 0.3), Vector2(g * 0.2, g * 0.55)), WOOD)
	for off in [Vector2(0, -g * 0.15), Vector2(-g * 0.35, g * 0.15), Vector2(g * 0.35, g * 0.15)]:
		ci.draw_circle(c + off, g * 0.5, Color("4f9a47"))
		ci.draw_arc(c + off, g * 0.5, 0, TAU, 16, INK, w * 0.8, true)
	if sparkle:
		var sp := c + Vector2(g * 0.5, -g * 0.6)
		ci.draw_line(sp + Vector2(-g * 0.3, 0), sp + Vector2(g * 0.3, 0), GOLD, w * 1.2, true)
		ci.draw_line(sp + Vector2(0, -g * 0.3), sp + Vector2(0, g * 0.3), GOLD, w * 1.2, true)


## A runestone: a small standing rune with a glow in its condition colour.
static func draw_runestone(ci: CanvasItem, c: Vector2, s: float, condition_name: String, selected := false) -> void:
	var col: Color = STONE_COLORS.get(condition_name, STONE_COLORS["dark"])
	var g := s * 0.5
	if condition_name == "glowing" or condition_name == "dim":
		ci.draw_circle(c, g * 1.9, Color(col, 0.22))
	if selected:
		ci.draw_arc(c, g * 1.9, 0, TAU, 20, GOLD, 2.0, true)
	var d := PackedVector2Array([c + Vector2(0, -g * 1.15), c + Vector2(g * 0.75, 0), c + Vector2(0, g * 1.15), c + Vector2(-g * 0.75, 0)])
	ci.draw_colored_polygon(d, col)
	d.append(d[0])
	ci.draw_polyline(d, INK, maxf(1.0, s * 0.12), true)
	if condition_name == "cracked":
		ci.draw_line(c + Vector2(-g * 0.3, -g * 0.4), c + Vector2(g * 0.2, g * 0.5), INK, 1.0, true)


## Player arrow pointing along `heading` (radians clockwise from north, screen up).
static func draw_player(ci: CanvasItem, c: Vector2, s: float, heading: float) -> void:
	var fwd := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := c + fwd * s * 1.15
	var pts := PackedVector2Array([tip, c - fwd * s * 0.7 + side * s * 0.75, c - fwd * s * 0.28, c - fwd * s * 0.7 - side * s * 0.75])
	ci.draw_circle(c, s * 1.6, Color(GOLD, 0.3))
	ci.draw_arc(c, s * 1.6, 0, TAU, 28, Color(GOLD, 0.95), 2.0, true)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(1.5, 2.5))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(pts, Color("2f6fd0"))
	var loop := pts.duplicate()
	loop.append(tip)
	ci.draw_polyline(loop, Color.WHITE, 2.2, true)
	ci.draw_circle(c, s * 0.16, Color.WHITE)


## Eight-point compass rose in the storybook style, `r` = radius of the long points.
static func draw_rose(ci: CanvasItem, c: Vector2, r: float, font: Font) -> void:
	ci.draw_circle(c, r * 1.12, Color(CREAM, 0.82))
	ci.draw_arc(c, r * 1.12, 0, TAU, 40, INK, 2.0, true)
	ci.draw_arc(c, r * 0.72, 0, TAU, 32, Color(INK, 0.5), 1.0, true)
	for i in 8:
		var a := i * PI * 0.25
		var d := Vector2(sin(a), -cos(a))
		var sd := Vector2(-d.y, d.x)
		var len := r if i % 2 == 0 else r * 0.62
		var wd := r * (0.2 if i % 2 == 0 else 0.13)
		var dark := PackedVector2Array([c + d * len, c + sd * wd, c])
		var light := PackedVector2Array([c + d * len, c - sd * wd, c])
		var lc := RED if i == 0 else (INK if i % 2 == 0 else STONE_DARK)
		ci.draw_colored_polygon(dark, lc)
		ci.draw_colored_polygon(light, lc.lightened(0.45))
	ci.draw_circle(c, r * 0.1, GOLD)
	var fs := int(r * 0.6)
	var nw := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(font, c + Vector2(-nw * 0.5, -r * 1.2), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, CREAM)
	ci.draw_string(font, c + Vector2(-nw * 0.5, -r * 1.2), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RED)


# --- Region 1 kinds (scripts/world/region1_world.gd) ----------------------------------------------------------------

## An Elder Stone: a carved standing stone on a dais with blue rune light.
static func _menhir(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.75, g * 0.85), c + Vector2(-g * 0.55, g * 0.55), c + Vector2(g * 0.55, g * 0.55), c + Vector2(g * 0.75, g * 0.85)]), STONE_DARK, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.3, g * 0.6), c + Vector2(-g * 0.22, -g * 0.85), c + Vector2(g * 0.05, -g * 1.0), c + Vector2(g * 0.3, -g * 0.8), c + Vector2(g * 0.28, g * 0.6)]), STONE, w)
	for k in 3:
		ci.draw_line(c + Vector2(-g * 0.05, -g * 0.55 + k * g * 0.38), c + Vector2(g * 0.12, -g * 0.4 + k * g * 0.38), Color("3aa6ff"), w * 1.2, true)
	ci.draw_circle(c + Vector2(0, -g * 0.95), g * 0.14, Color("8fd6ff"))


## A closed border gate: two towers, a barred arch and a red bar across it.
static func _gate(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_poly(ci, _rectp(c, -g * 0.95, -g * 0.55, -g * 0.4, g * 0.85), STONE, w)
	_poly(ci, _rectp(c, g * 0.4, -g * 0.55, g * 0.95, g * 0.85), STONE, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 1.05, -g * 0.55), c + Vector2(-g * 0.68, -g * 1.0), c + Vector2(-g * 0.3, -g * 0.55)]), BLUE, w)
	_poly(ci, PackedVector2Array([c + Vector2(g * 0.3, -g * 0.55), c + Vector2(g * 0.68, -g * 1.0), c + Vector2(g * 1.05, -g * 0.55)]), GOLD, w)
	ci.draw_line(c + Vector2(-g * 0.42, g * 0.2), c + Vector2(g * 0.42, g * 0.2), RED, w * 2.4, true)
	ci.draw_line(c + Vector2(-g * 0.42, g * 0.52), c + Vector2(g * 0.42, g * 0.52), RED, w * 2.4, true)


## A snowed-shut pass: two peaks with snow caps.
static func _peaks(ci: CanvasItem, c: Vector2, g: float, w: float) -> void:
	_poly(ci, PackedVector2Array([c + Vector2(-g * 1.0, g * 0.8), c + Vector2(-g * 0.3, -g * 0.8), c + Vector2(g * 0.25, g * 0.8)]), STONE_DARK, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.1, g * 0.8), c + Vector2(g * 0.5, -g * 0.45), c + Vector2(g * 1.05, g * 0.8)]), STONE, w)
	_poly(ci, PackedVector2Array([c + Vector2(-g * 0.52, -g * 0.3), c + Vector2(-g * 0.3, -g * 0.8), c + Vector2(-g * 0.08, -g * 0.3), c + Vector2(-g * 0.22, -g * 0.42), c + Vector2(-g * 0.38, -g * 0.22)]), Color("f4f8ff"), w * 0.7)
	ci.draw_line(c + Vector2(-g * 0.9, g * 0.85), c + Vector2(g * 0.95, g * 0.85), Color("f4f8ff"), w * 1.6, true)
