extends RefCounted
## Small drawn widgets for the build menu (build_menu.gd, construction_panel.gd): a building icon per kind
## (procedural line art, no assets), cost chips coloured by have / need, a locked-requirements banner and the
## placement status banner. Everything is built from StyleBoxFlat and _draw, sized for touch.

const OK := Color("8fdc8f")
const WARN := Color("e0c060")
const BAD := Color("e07070")
const GOLD := Color("e8c468")
const PARCHMENT := Color("efe4cc")

## Role -> glyph colour.
const ROLE_COLOR := {"shelter": Color("d9b28a"), "storage": Color("c9a26a"), "water": Color("7fc3ea"), "food": Color("d7c35f"),
	"trade": Color("e8c468"), "defence": Color("b8bcc6"), "craft": Color("e69a5a"), "command": Color("d98a8a"), "faith": Color("cfc1ee")}
## Kind -> glyph (defaults to the role's).
const KIND_GLYPH := {"campfire": "flame", "tent": "tent", "lean_to": "tent", "hut": "house", "timber_house": "house", "stone_house": "house",
	"fence": "fence", "palisade": "fence", "stone_wall": "wall", "gate": "gate", "watchtower": "tower", "stone_tower": "tower",
	"well": "well", "field": "wheat", "drying_rack": "rack", "storage_pile": "crate", "barn": "barn", "granary": "barn",
	"workbench": "hammer", "sawhorse": "saw", "mason_bench": "hammer", "workshop": "saw", "smithy": "anvil", "market": "stall",
	"keep": "keep", "temple": "temple", "guild_hall": "stall",
	# homestead pieces
	"cottage": "house", "chicken_coop": "barn", "pig_sty": "barn", "woodpile": "crate", "lamp_post": "flame", "bench": "rack",
	"crop_plot": "wheat", "tilled_plot": "wheat"}


## Building icon for `kind` (catalogue kind) drawn in the colour of `role`.
static func icon(kind: String, role := "", size := 40) -> Control:
	var i := Icon.new()
	i.glyph = String(KIND_GLYPH.get(kind, {"shelter": "house", "storage": "crate", "water": "well", "food": "wheat", "trade": "stall",
		"defence": "wall", "craft": "hammer", "command": "keep", "faith": "temple"}.get(role, "house")))
	i.tint = ROLE_COLOR.get(role, PARCHMENT)
	i.custom_minimum_size = Vector2(size, size)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


class Icon extends Control:
	var glyph := "house"
	var tint := Color.WHITE
	var locked := false

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		draw_circle(o + Vector2(s, s) * 0.5, s * 0.5, Color(0.07, 0.06, 0.05, 0.9))
		draw_arc(o + Vector2(s, s) * 0.5, s * 0.5 - 1.0, 0.0, TAU, 28, Color(tint, 0.55 if not locked else 0.25), 1.5, true)
		var c := tint if not locked else Color(tint, 0.4)
		var w := maxf(1.6, s * 0.055)
		var p := func(x: float, y: float) -> Vector2:
			return o + Vector2(x, y) * s
		match glyph:
			"house":
				draw_colored_polygon(PackedVector2Array([p.call(0.22, 0.5), p.call(0.5, 0.26), p.call(0.78, 0.5)]), c)
				draw_rect(Rect2(p.call(0.3, 0.5), Vector2(0.4, 0.26) * s), c.darkened(0.15))
				draw_rect(Rect2(p.call(0.45, 0.6), Vector2(0.1, 0.16) * s), Color(0.1, 0.08, 0.06))
			"tent":
				draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.74), p.call(0.5, 0.26), p.call(0.8, 0.74)]), c)
				draw_colored_polygon(PackedVector2Array([p.call(0.44, 0.74), p.call(0.5, 0.5), p.call(0.56, 0.74)]), Color(0.1, 0.08, 0.06))
			"flame":
				draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.2), p.call(0.66, 0.46), p.call(0.64, 0.68), p.call(0.5, 0.78),
					p.call(0.36, 0.68), p.call(0.34, 0.46), p.call(0.45, 0.5)]), c)
				draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.5), p.call(0.58, 0.64), p.call(0.5, 0.74), p.call(0.42, 0.64)]), Color(1.0, 0.9, 0.5))
			"fence":
				for i in 4:
					draw_rect(Rect2(p.call(0.2 + 0.18 * i, 0.34), Vector2(0.09, 0.4) * s), c)
				draw_line(p.call(0.18, 0.46), p.call(0.82, 0.46), c.darkened(0.2), w)
				draw_line(p.call(0.18, 0.62), p.call(0.82, 0.62), c.darkened(0.2), w)
			"wall":
				for r in 3:
					for k in 3:
						var off := 0.0 if r % 2 == 0 else 0.1
						draw_rect(Rect2(p.call(0.2 + k * 0.2 - off, 0.3 + r * 0.14), Vector2(0.18, 0.12) * s), c.darkened(0.1 * (k % 2)))
			"gate":
				draw_rect(Rect2(p.call(0.22, 0.3), Vector2(0.56, 0.44) * s), c)
				draw_rect(Rect2(p.call(0.4, 0.44), Vector2(0.2, 0.3) * s), Color(0.1, 0.08, 0.06))
			"tower":
				draw_rect(Rect2(p.call(0.36, 0.32), Vector2(0.28, 0.44) * s), c)
				for k in 3:
					draw_rect(Rect2(p.call(0.32 + k * 0.13, 0.24), Vector2(0.08, 0.1) * s), c)
			"well":
				draw_arc(p.call(0.5, 0.56), s * 0.2, 0.0, TAU, 16, c, w * 1.3, true)
				draw_line(p.call(0.3, 0.56), p.call(0.3, 0.3), c, w)
				draw_line(p.call(0.7, 0.56), p.call(0.7, 0.3), c, w)
				draw_line(p.call(0.26, 0.3), p.call(0.74, 0.3), c, w)
			"wheat":
				for k in 3:
					var x := 0.32 + 0.18 * k
					draw_line(p.call(x, 0.78), p.call(x, 0.34), c.darkened(0.25), w)
					for j in 3:
						draw_circle(p.call(x + (0.05 if j % 2 == 0 else -0.05), 0.36 + j * 0.1), s * 0.04, c)
			"rack":
				draw_line(p.call(0.22, 0.38), p.call(0.78, 0.38), c, w)
				draw_line(p.call(0.26, 0.38), p.call(0.26, 0.76), c, w)
				draw_line(p.call(0.74, 0.38), p.call(0.74, 0.76), c, w)
				for k in 4:
					draw_line(p.call(0.34 + 0.11 * k, 0.4), p.call(0.34 + 0.11 * k, 0.56), c.lightened(0.15), w * 0.7)
			"crate":
				draw_rect(Rect2(p.call(0.26, 0.32), Vector2(0.48, 0.44) * s), c.darkened(0.1))
				draw_rect(Rect2(p.call(0.26, 0.32), Vector2(0.48, 0.44) * s), c.lightened(0.2), false, w)
				draw_line(p.call(0.26, 0.32), p.call(0.74, 0.76), c.lightened(0.2), w * 0.8)
			"barn":
				draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.46), p.call(0.35, 0.28), p.call(0.65, 0.28), p.call(0.8, 0.46)]), c)
				draw_rect(Rect2(p.call(0.26, 0.46), Vector2(0.48, 0.3) * s), c.darkened(0.15))
				draw_line(p.call(0.38, 0.76), p.call(0.62, 0.46), Color(0.1, 0.08, 0.06), w)
			"hammer":
				draw_line(p.call(0.3, 0.72), p.call(0.62, 0.36), c.darkened(0.3), w * 1.3)
				draw_rect(Rect2(p.call(0.5, 0.26), Vector2(0.3, 0.16) * s), c)
			"saw":
				draw_line(p.call(0.2, 0.6), p.call(0.8, 0.6), c, w)
				for k in 6:
					draw_line(p.call(0.24 + 0.1 * k, 0.6), p.call(0.29 + 0.1 * k, 0.68), c, w * 0.8)
				draw_rect(Rect2(p.call(0.2, 0.4), Vector2(0.1, 0.2) * s), c.darkened(0.3))
			"anvil":
				draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.4), p.call(0.8, 0.4), p.call(0.7, 0.5), p.call(0.6, 0.5),
					p.call(0.64, 0.7), p.call(0.36, 0.7), p.call(0.4, 0.5), p.call(0.3, 0.5)]), c)
			"stall":
				draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.44), p.call(0.26, 0.28), p.call(0.74, 0.28), p.call(0.8, 0.44)]), c)
				for k in 4:
					draw_rect(Rect2(p.call(0.2 + k * 0.15, 0.3), Vector2(0.075, 0.14) * s), c.lightened(0.3))
				draw_rect(Rect2(p.call(0.26, 0.5), Vector2(0.48, 0.2) * s), c.darkened(0.25))
			"keep":
				draw_rect(Rect2(p.call(0.3, 0.36), Vector2(0.4, 0.4) * s), c)
				for k in 3:
					draw_rect(Rect2(p.call(0.3 + k * 0.15, 0.28), Vector2(0.1, 0.1) * s), c)
				draw_rect(Rect2(p.call(0.44, 0.56), Vector2(0.12, 0.2) * s), Color(0.1, 0.08, 0.06))
			"temple":
				draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.4), p.call(0.5, 0.24), p.call(0.8, 0.4)]), c)
				for k in 4:
					draw_rect(Rect2(p.call(0.26 + 0.14 * k, 0.42), Vector2(0.07, 0.3) * s), c.darkened(0.12))
				draw_rect(Rect2(p.call(0.22, 0.72), Vector2(0.56, 0.06) * s), c)
			_:
				draw_circle(o + Vector2(s, s) * 0.5, s * 0.18, c)
		if locked:
			draw_rect(Rect2(o + Vector2(0.58, 0.58) * s, Vector2(0.3, 0.26) * s), Color(0.85, 0.3, 0.26))
			draw_arc(o + Vector2(0.73, 0.58) * s, s * 0.09, PI, TAU, 10, Color(0.85, 0.3, 0.26), w)


## One coloured chip: "3/10 logs". state: "ok" | "some" (enough to start) | "short" | "dim".
static func chip(text: String, state: String) -> PanelContainer:
	var col := {"ok": OK, "some": WARN, "short": BAD, "dim": Color(0.7, 0.68, 0.62)}.get(state, PARCHMENT) as Color
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.85)
	sb.border_color = Color(col, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = ("✓ " if state == "ok" else "") + text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	pc.add_child(l)
	return pc


## Row of cost chips. `parts`: Array of [text, state].
static func chips(parts: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 5)
	f.add_theme_constant_override("v_separation", 3)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e: Array in parts:
		f.add_child(chip(String(e[0]), String(e[1])))
	return f


## "Locked" banner listing each unmet requirement on its own line.
static func locked_banner(needs: Array) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.1, 0.09, 0.55)
	sb.border_color = Color(BAD, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	for n in needs:
		var l := Label.new()
		l.text = "✗ " + String(n)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", BAD)
		v.add_child(l)
	return pc


## Status banner style (green when placement is fine, red with the reason otherwise).
static func banner_style(ok: bool) -> StyleBoxFlat:
	var col := OK if ok else BAD
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.9)
	sb.border_color = Color(col, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
