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


## Icon colour for a place (hostile camps red, travel points teal, ...).
static func color_for(place: Dictionary) -> Color:
	if place.get("hostile", false):
		return HOSTILE
	match String(place.get("kind", "")):
		"village", "town", "castle", "capital":
			return SETTLEMENT
		"waystation":
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
		"village", "town", "farm":
			var roof := PackedVector2Array([c + Vector2(-g, -g * 0.05), c + Vector2(0, -g * 0.95), c + Vector2(g, -g * 0.05)])
			ci.draw_colored_polygon(roof, col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.68, -g * 0.05), Vector2(g * 1.36, g * 0.85)), col)
			if kind == "town":
				ci.draw_rect(Rect2(c + Vector2(g * 0.35, -g * 0.95), Vector2(g * 0.3, g * 0.6)), col)
		"waystation":
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
		"tower_ruin", "watchfort":
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


## Player arrow pointing along `heading` (radians clockwise from north, screen up).
static func draw_player(ci: CanvasItem, c: Vector2, s: float, heading: float) -> void:
	var fwd := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := c + fwd * s
	var pts := PackedVector2Array([tip, c - fwd * s * 0.6 + side * s * 0.7, c - fwd * s * 0.25, c - fwd * s * 0.6 - side * s * 0.7])
	ci.draw_circle(c, s * 1.25, Color(UITheme.ACCENT_2, 0.18))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 2))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
	ci.draw_colored_polygon(pts, UITheme.ACCENT)
	pts.append(tip)
	ci.draw_polyline(pts, Color.WHITE, 1.5, true)
