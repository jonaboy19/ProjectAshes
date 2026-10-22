extends Control
## World-map overlay for the Region 1 mechanics (packages C3, C4, C5), added with world_map.add_layer().
## It never replaces the terrain (paint_under returns false); it draws over whatever the map shows:
##   * Wardlines: every stone's bubble, blue by strength, a bright rim for a carved glyph (lure pink,
##     alarm yellow, bless green), the wardlines themselves, dark stones as grey rings;
##   * Scar Tide: the violet front, cell by cell;
##   * Ember Legacy: a gold ring on each ancestor stone.
## All of it is read from the live sims each redraw (Region1State.sim), so it costs nothing while the
## map is closed, and a carve is visible the moment the map is reopened.

const GLYPH_COLORS := [Color(0, 0, 0, 0), Color("2ff0d8"), Color("ff7ad9"), Color("ffd23f"), Color("7be08a")]
const GOLD := Color("f0c060")
const VIOLET := Color("8a3cc8")

var show_wards := true
var show_scar := true
var show_ancestors := true
var bakes_labels := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO


func bind_map(_m: Control) -> void:
	pass


## Called from world_map._draw(): paint into the map's own canvas, under its icons.
func paint_under(canvas: Control) -> bool:
	var zoom := float(canvas.get("_zoom"))
	var view := Rect2(Vector2(-80, -80), canvas.size + Vector2(160, 160))
	if show_scar:
		_scar(canvas, zoom, view)
	var wl := Region1State.sim(&"wardlines") as Wardlines
	if show_wards and wl != null and wl.n > 0:
		_wards(canvas, wl, zoom, view)
	if show_ancestors:
		_ancestors(canvas, view)
	return false


## What _wards() reads per stone, flattened: [radius, strength, glyph] for each stone. A carve must change it
## (used by tests/test_region1_wardlines.gd to prove the map shows a carve without drawing).
func coverage_data() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var wl := Region1State.sim(&"wardlines") as Wardlines
	if wl == null:
		return out
	var rad: PackedFloat64Array = wl.get("_rad")
	for i in wl.n:
		out.append(rad[i] if i < rad.size() else wl.st_radius[i])
		out.append(wl.stone_strength(i))
		out.append(float(wl.glyph[i]))
	return out


func _scar(canvas: Control, zoom: float, view: Rect2) -> void:
	var st: Variant = Region1State.sim(&"scar_tide")
	if st == null:
		return
	var cells: PackedByteArray = st.cells
	var N: int = st.N
	var half := float(st.HALF)
	var cell := float(st.CELL)
	var px := cell * zoom
	var lo: Vector2 = canvas.to_world(view.position)
	var hi: Vector2 = canvas.to_world(view.end)
	var x0 := clampi(int(floor((lo.x + half) / cell)), 0, N - 1)
	var x1 := clampi(int(floor((hi.x + half) / cell)), 0, N - 1)
	var y0 := clampi(int(floor((lo.y + half) / cell)), 0, N - 1)
	var y1 := clampi(int(floor((hi.y + half) / cell)), 0, N - 1)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 60000:
		return
	for y in range(y0, y1 + 1):
		var row := y * N
		for x in range(x0, x1 + 1):
			var v := int(cells[row + x])
			if v == 0:
				continue
			var a := 0.25 + 0.5 * float(v) / 255.0
			var tl: Vector2 = canvas.to_screen(Vector2(x * cell - half, y * cell - half))
			canvas.draw_rect(Rect2(tl, Vector2(px + 0.6, px + 0.6)), Color(VIOLET, a))


func _wards(canvas: Control, wl: Wardlines, zoom: float, view: Rect2) -> void:
	var rad: PackedFloat64Array = wl.get("_rad")
	# Wardlines first (thin lines under the bubbles).
	for l: Dictionary in wl.links:
		if bool(l.get("cut", false)):
			continue
		var a: Vector2 = canvas.to_screen(wl.st_pos[int(l["a"])])
		var b: Vector2 = canvas.to_screen(wl.st_pos[int(l["b"])])
		if not (view.has_point(a) or view.has_point(b)):
			continue
		canvas.draw_line(a, b, Color(0.4, 0.75, 1.0, 0.55 if String(l.get("kind", "")) == "player" else 0.22), 1.6 if String(l.get("kind", "")) == "player" else 1.0, true)
	for i in wl.n:
		var c: Vector2 = canvas.to_screen(wl.st_pos[i])
		if not view.has_point(c):
			continue
		var r := (rad[i] if i < rad.size() else wl.st_radius[i]) * zoom
		var s := wl.stone_strength(i)
		var g := int(wl.glyph[i])
		var col: Color = GLYPH_COLORS[g] if g > 0 else Color(0.35, 0.7, 1.0)
		if s > 0.05 and r > 2.0:
			canvas.draw_circle(c, r, Color(col, 0.05 + 0.2 * s))
			canvas.draw_arc(c, r, 0.0, TAU, 40, Color(col, 0.25 + 0.4 * s), 1.4 if g == 0 else 2.6, true)
		elif r > 2.0:
			canvas.draw_arc(c, minf(r, 14.0), 0.0, TAU, 16, Color(0.4, 0.4, 0.45, 0.6), 1.2, true)
	for e in wl.elder_ids:
		var c2: Vector2 = canvas.to_screen(wl.st_pos[e])
		if view.has_point(c2):
			canvas.draw_arc(c2, 13.0, 0.0, TAU, 24, Color("9ad8ff"), 2.4, true)
			canvas.draw_circle(c2, 4.0, Color("d8f0ff"))


func _ancestors(canvas: Control, view: Rect2) -> void:
	var el := Region1State.sim(&"ember_legacy") as EmberLegacy
	if el == null or el.ancestor_stones.is_empty():
		return
	for s: Dictionary in Frontier.runestones.stones:
		if not el.is_ancestor_stone(s["id"]):
			continue
		var c: Vector2 = canvas.to_screen(s["pos"])
		if view.has_point(c):
			canvas.draw_arc(c, 11.0, 0.0, TAU, 24, GOLD, 2.6, true)
			canvas.draw_circle(c, 4.5, GOLD)
