extends Node2D
## Ink layer of the Region 1 parchment painter: everything drawn with a pen on top of the shader-painted paper.
## Trees, hachured mountains, rivers, dotted roads, settlement pictograms, labels, compass rose, cartouche, neatline.
## All positions come from WorldGen (see dump_world.gd); world metres -> image px via w2p().

const INK := Color(0.30, 0.20, 0.10)
const INK_SOFT := Color(0.30, 0.20, 0.10, 0.55)
const HALO := Color(0.95, 0.89, 0.71, 0.92)
const RED := Color(0.62, 0.16, 0.10)
const BLUE_ROOF := Color(0.27, 0.42, 0.68)
const WALL := Color(0.93, 0.88, 0.76)
const ROOF_R := Color(0.72, 0.36, 0.22)
const WATER_INK := Color(0.22, 0.42, 0.55)
const TREE_FILL := Color(0.52, 0.60, 0.40, 0.90)
const TREE_LIT := Color(0.78, 0.82, 0.55)
const TREE_DARK := Color(0.40, 0.50, 0.34, 0.92)

## Poster names shown on screen for data places (ids stay). See docs/regions/OWNER_DECISIONS.md.
const ALIASES := {"Oakvale": "Greenhollow", "Highcliff": "Highwatch Keep"}
## Poster / design places that have no WorldGen site yet (positions: data/region1/wardlines.json hubs and the plan sec 1.2).
const PROPOSED := [
	{"id": "silverford", "name": "Silverford", "kind": "town", "pos": [-640, 480], "note": "guild town at the Ashrun ford (wardlines hub)"},
]
const ELDER_STONES := [
	{"name": "Stagborn Glade", "pos": [-1345, -1062]},
	{"name": "Greyseam Seam", "pos": [75, -520]},
	{"name": "Highwatch", "pos": [110, -1290]},
	{"name": "Crownstead", "pos": [430, -190]},
	{"name": "Elden Road", "pos": [-700, -215]},
]

var world: Dictionary
var g: PackedFloat32Array
var n := 1024
var lay: Dictionary
var bare := false
var S := 2048.0
var M := 88.0
var T := 1872.0
var half := 4096.0
var ppm := 0.2285

var f_reg: Font
var f_ita: Font
var f_cin: Font
var f_cin_b: Font

var reserved: Array[Rect2] = []
var circles: Array = []            # [Vector2 px, radius] tree exclusion
var labels: Array = []             # placed labels
var icons: Array = []              # [kind, Vector2 px, Dictionary]
var features: Array = []           # for describe()
var trees: Array = []
var peaks: Array = []
var _built := false
var zones := {}
var wobble_seed := 3.0


func setup(w: Dictionary, raw: PackedByteArray, grid_n: int, l: Dictionary, bare_only: bool) -> void:
	world = w
	g = raw.to_float32_array()
	n = grid_n
	lay = l
	bare = bare_only
	S = float(l["size"])
	M = float(l["margin"])
	T = float(l["terrain"])
	half = float(l["half"])
	ppm = float(l["ppm"])
	f_reg = load("res://assets/ui/fonts/IMFellEnglish-Regular.ttf")
	f_ita = load("res://assets/ui/fonts/IMFellEnglish-Italic.ttf")
	var cin: FontFile = load("res://assets/ui/fonts/Cinzel[wght].ttf")
	f_cin = cin
	var fv := FontVariation.new()
	fv.base_font = cin
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	f_cin_b = fv
	var k := S / 2048.0
	zones = {
		"disc": Vector4(S - 250 * k, 265 * k, 175 * k, 60.0),
		"a": Vector4(100 * k, 100 * k, 790 * k, 330 * k),
		"b": Vector4(S * 0.5 - 300 * k, S - 205 * k, S * 0.5 + 300 * k, S - 100 * k),
	}
	var rifts := []
	for s: Dictionary in w["sites"]:
		if s["kind"] == "rift":
			rifts.append(w2p(Vector2(s["pos"][0], s["pos"][1])))
	zones["rift_a"] = Vector4(rifts[0].x, rifts[0].y, 210.0 * k, 0) if rifts.size() > 0 else Vector4()
	zones["rift_b"] = Vector4(rifts[1].x, rifts[1].y, 170.0 * k, 0) if rifts.size() > 1 else Vector4()


func clear_zones() -> Dictionary:
	var d: Vector4 = zones["disc"]
	var a: Vector4 = zones["a"]
	var b: Vector4 = zones["b"]
	return {"disc": d, "a": a, "b": b, "rift_a": zones["rift_a"], "rift_b": zones["rift_b"]}


# --------------------------------------------------------------------- helpers ----

func w2p(v: Vector2) -> Vector2:
	return Vector2(M, M) + (v + Vector2(half, half)) * ppm


func p2w(p: Vector2) -> Vector2:
	return (p - Vector2(M, M)) / ppm - Vector2(half, half)


func _cell(w: Vector2) -> int:
	var f := (w + Vector2(half, half)) / (2.0 * half)
	var x := clampi(int(f.x * n), 0, n - 1)
	var y := clampi(int(f.y * n), 0, n - 1)
	return (y * n + x) * 4


func hgt(w: Vector2) -> float:
	return g[_cell(w)]


func wet(w: Vector2) -> float:
	return g[_cell(w) + 1]


func forest(w: Vector2) -> float:
	return g[_cell(w) + 2]


func road_d(w: Vector2) -> float:
	return g[_cell(w) + 3]


func slope(w: Vector2) -> float:
	var d := 24.0
	var dx := (hgt(w + Vector2(d, 0)) - hgt(w - Vector2(d, 0))) / (2.0 * d)
	var dz := (hgt(w + Vector2(0, d)) - hgt(w - Vector2(0, d))) / (2.0 * d)
	return sqrt(dx * dx + dz * dz)


func hs(x: float, y: float, salt := 0) -> float:
	var h := (int(x * 73.0) * 374761393 + int(y * 91.0) * 668265263 + salt * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func poly(pts: PackedVector2Array, fill: Color, line := INK, w := 1.3) -> void:
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
	if line.a > 0.0:
		var p2 := pts.duplicate()
		p2.append(pts[0])
		draw_polyline(p2, line, w, true)


func _rect_of(text: String, font: Font, fs: int, pos: Vector2) -> Rect2:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	return Rect2(pos.x, pos.y - font.get_ascent(fs), sz.x, font.get_height(fs))


func spaced_width(text: String, font: Font, fs: int, sp: float) -> float:
	var w := 0.0
	for ch in text:
		w += font.get_char_size(ch.unicode_at(0), fs).x + sp
	return w - sp


func draw_spaced(text: String, pos: Vector2, font: Font, fs: int, col: Color, sp: float, halo := true) -> void:
	var x := pos.x
	for ch in text:
		var cw := font.get_char_size(ch.unicode_at(0), fs).x
		if halo:
			draw_string_outline(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, HALO)
		x += cw + sp
	x = pos.x
	for ch in text:
		var cw2 := font.get_char_size(ch.unicode_at(0), fs).x
		draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += cw2 + sp


func draw_label(text: String, pos: Vector2, font: Font, fs: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, HALO)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func path_text(pts: PackedVector2Array, text: String, font: Font, fs: int, col: Color, sp: float, normal_off: float) -> void:
	if pts.size() < 2:
		return
	if pts[pts.size() - 1].x < pts[0].x:
		pts = _reversed(pts)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := cum[cum.size() - 1]
	var tw := spaced_width(text, font, fs, sp)
	var s := (total - tw) * 0.5
	for pass_i in 2:
		var s2 := s
		for ch in text:
			var cw := font.get_char_size(ch.unicode_at(0), fs).x
			var mid := s2 + cw * 0.5
			var seg := 1
			while seg < cum.size() - 1 and cum[seg] < mid:
				seg += 1
			var a := pts[seg - 1]
			var b := pts[seg]
			var t := clampf((mid - cum[seg - 1]) / maxf(cum[seg] - cum[seg - 1], 0.001), 0.0, 1.0)
			var pos := a.lerp(b, t)
			var dir := (b - a).normalized()
			var nrm := Vector2(dir.y, -dir.x)
			draw_set_transform(pos + nrm * normal_off, dir.angle(), Vector2.ONE)
			if pass_i == 0:
				draw_string_outline(font, Vector2(-cw * 0.5, fs * 0.3), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, HALO)
			else:
				draw_string(font, Vector2(-cw * 0.5, fs * 0.3), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			s2 += cw + sp
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		o.append(pts[i])
	return o


# -------------------------------------------------------------------- layout ----

func _icon_radius(kind: String) -> float:
	match kind:
		"castle": return 46.0
		"town": return 30.0
		"frontier_town": return 24.0
		"village": return 19.0
		"fort": return 15.0
		"watchfort": return 12.0
		"mine": return 15.0
		"academy": return 16.0
		"rift": return 22.0
		"rift_outpost": return 12.0
		"tower_ruin": return 12.0
		"shrine": return 11.0
		"hollow": return 10.0
		"bridge": return 9.0
		"waystation": return 10.0
		"bandit_camp", "goblin_warren", "orc_village": return 12.0
		"elder": return 14.0
		"waterfall", "windmill_hill", "sunken_chapel", "bones", "glade": return 14.0
		"standing_stones", "ruins", "lookout", "ferry", "old_bridge": return 11.0
	return 10.0


func _place_label(text: String, anchor: Vector2, r: float, font: Font, fs: int, col: Color, prefs: Array, kind: String, spaced := 0.0) -> Dictionary:
	var w := spaced_width(text, font, fs, spaced) if spaced > 0.0 else font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := font.get_height(fs)
	var asc := font.get_ascent(fs)
	var best := {}
	var best_ov := 1.0e12
	for ring in 3:
		var rr := r + 3.0 + ring * (fs * 0.7)
		for pref: String in prefs:
			var top_left := Vector2.ZERO
			match pref:
				"S": top_left = Vector2(anchor.x - w * 0.5, anchor.y + rr)
				"N": top_left = Vector2(anchor.x - w * 0.5, anchor.y - rr - h)
				"E": top_left = Vector2(anchor.x + rr + 2, anchor.y - h * 0.5)
				"W": top_left = Vector2(anchor.x - rr - 2 - w, anchor.y - h * 0.5)
				"SE": top_left = Vector2(anchor.x + rr * 0.6, anchor.y + rr * 0.55)
				"NE": top_left = Vector2(anchor.x + rr * 0.6, anchor.y - rr * 0.55 - h)
				"SW": top_left = Vector2(anchor.x - rr * 0.6 - w, anchor.y + rr * 0.55)
				"NW": top_left = Vector2(anchor.x - rr * 0.6 - w, anchor.y - rr * 0.55 - h)
				"C": top_left = Vector2(anchor.x - w * 0.5, anchor.y - h * 0.5)
			var rect := Rect2(top_left, Vector2(w, h)).grow(2.0)
			var ov := 0.0
			for q in reserved:
				var inter := rect.intersection(q)
				ov += inter.size.x * inter.size.y
			if rect.position.x < M + 6.0 or rect.position.y < M + 6.0 or rect.end.x > S - M - 6.0 or rect.end.y > S - M - 6.0:
				ov += 1.0e6
			if ov < best_ov:
				best_ov = ov
				best = {"text": text, "pos": Vector2(top_left.x, top_left.y + asc), "font": font, "fs": fs, "col": col, "sp": spaced, "rect": rect}
			if ov <= 0.0:
				reserved.append(rect)
				return best
	if not best.is_empty():
		reserved.append(best["rect"])
	return best


func _build() -> void:
	_built = true
	var k := S / 2048.0
	# Fixed zones are reserved first so no label ends up under the compass, cartouche or scale bar.
	var d: Vector4 = zones["disc"]
	reserved.append(Rect2(d.x - d.z, d.y - d.z, d.z * 2, d.z * 2))
	var a: Vector4 = zones["a"]
	reserved.append(Rect2(a.x, a.y, a.z - a.x, a.w - a.y))
	var b: Vector4 = zones["b"]
	reserved.append(Rect2(b.x, b.y, b.z - b.x, b.w - b.y))
	_make_path_labels()

	# ---- gather places -------------------------------------------------------------
	var items: Array = []     # {kind, name, pos(Vector2 world), prio}
	for s: Dictionary in world["settlements"]:
		var kind: String = String(s["kind"])
		items.append({"kind": kind, "name": String(s["name"]), "pos": Vector2(s["pos"][0], s["pos"][1]), "prio": {"castle": 100, "town": 80, "frontier_town": 65, "village": 70}.get(kind, 60), "cat": "settlement"})
	for p: Dictionary in PROPOSED:
		items.append({"kind": p["kind"], "name": p["name"], "pos": Vector2(p["pos"][0], p["pos"][1]), "prio": 78, "cat": "proposed"})
	var skip_kinds := ["farm", "waystone", "wayshrine", "bridge_skip", "roadside"]
	for s: Dictionary in world["sites"]:
		var kind2: String = String(s["kind"])
		if kind2 in skip_kinds:
			continue
		var nm := String(s["name"])
		if kind2 == "bridge" and nm == "Bridge":
			nm = ""
		var prio: int = {"rift": 58, "academy": 40, "fort": 55, "watchfort": 45, "mine": 50, "shrine": 56, "hollow": 52, "tower_ruin": 44, "bandit_camp": 42, "waystation": 41, "rift_outpost": 46, "bridge": 30}.get(kind2, 35)
		items.append({"kind": kind2, "name": nm, "pos": Vector2(s["pos"][0], s["pos"][1]), "prio": prio, "cat": "site"})
	for p: Dictionary in world["places"]:
		if p["category"] == "camp":
			items.append({"kind": String(p["kind"]), "name": String(p["name"]), "pos": Vector2(p["pos"][0], p["pos"][1]), "prio": 43, "cat": "camp"})
	for e: Dictionary in ELDER_STONES:
		items.append({"kind": "elder", "name": "", "pos": Vector2(e["pos"][0], e["pos"][1]), "prio": 54, "cat": "elder", "elder": e["name"]})
	items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["prio"] > y["prio"])

	# reserve icon rects + tree exclusion circles
	for it: Dictionary in items:
		var pp := w2p(it["pos"])
		it["px"] = pp
		var r := _icon_radius(String(it["kind"]))
		it["r"] = r
		reserved.append(Rect2(pp - Vector2(r, r), Vector2(r, r) * 2.0))
		circles.append([pp, r + 5.0])
		icons.append([it["kind"], pp, it])

	# ---- labels: settlements & sites by priority ---------------------------------------
	for it: Dictionary in items:
		var kind3 := String(it["kind"])
		var nm2 := String(ALIASES.get(it["name"], it["name"]))
		it["display"] = nm2
		if kind3 == "old_bridge":
			continue      # icon only: the valley labels already crowd this corner
		if nm2 == "" or kind3 == "elder":
			continue
		var font: Font = f_reg
		var fs := 26
		var col := INK
		var prefs := ["S", "E", "W", "N", "SE", "SW", "NE", "NW"]
		var sp := 0.0
		if kind3 == "valley":
			nm2 = nm2.to_upper()
			it["display"] = String(it["name"])
			sp = 4.0
			col = Color(0.28, 0.36, 0.16)
			prefs = ["W", "NW", "SW", "E"]
		match kind3:
			"castle":
				font = f_cin_b
				fs = 40
				col = RED
				sp = 3.0
			"town", "frontier_town":
				fs = 34
			"village":
				fs = 28
			"fort", "watchfort", "mine", "rift", "rift_outpost", "tower_ruin", "shrine", "hollow", "academy", "waystation", "bridge", "bandit_camp", "goblin_warren", "orc_village", "waterfall", "standing_stones", "ruins", "lookout", "old_bridge", "sunken_chapel", "ferry", "windmill_hill", "glade", "bones":
				font = f_ita
				fs = 22 if kind3 != "rift" else 26
				if kind3 in ["rift", "rift_outpost"]:
					col = Color(0.36, 0.20, 0.50)
				elif kind3 in ["bandit_camp", "goblin_warren", "orc_village"]:
					col = Color(0.50, 0.18, 0.12)
		if String(it["name"]) in ["Highcliff"] or nm2 in ["Silverford", "Greenhollow", "Highwatch Keep"]:
			fs = maxi(fs, 34)        # poster names read a little larger
		if it["name"] == "Kingsreach Academy of Arms and Arts":
			nm2 = "Royal Ember Academy"
			it["display"] = nm2
		var lab := _place_label(nm2, it["px"], float(it["r"]), font, int(round(fs * k)) if k != 1.0 else fs, col, prefs, kind3, sp)
		if not lab.is_empty():
			labels.append(lab)

	# ---- geographic labels (spaced italic caps), placed after the settlements ----------------
	var geo := [
		["Duskbriar Wood", Vector2(380, 480), Color(0.27, 0.40, 0.22), 30, 5.0],
		["Mistwood", Vector2(-3221, -614), Color(0.27, 0.40, 0.22), 32, 6.0],
		["Greywood", Vector2(-1494, 1789), Color(0.27, 0.40, 0.22), 32, 6.0],
		["Thornwold", Vector2(2908, -1820), Color(0.27, 0.40, 0.22), 32, 6.0],
		["Emberglass Mere", Vector2(-420, 300), WATER_INK, 26, 3.0],
		["Crownstead", Vector2(470, -95), INK, 34, 0.0],
		["Whisper Hollow", Vector2(-560, 520), Color(0.30, 0.34, 0.30), 22, 0.0],
	]
	for e: Array in geo:
		var pp2 := w2p(e[1])
		var nm3: String = e[0]
		var fnt: Font = f_ita if nm3 != "Crownstead" else f_reg
		var fsz := int(round(float(e[3]) * k))
		if nm3 == "Whisper Hollow":
			continue     # drawn with its site icon
		var lab2 := _place_label(nm3.to_upper() if e[4] > 0.0 and nm3 != "Emberglass Mere" else nm3, pp2, 4.0 if e[4] > 0.0 else 26.0, fnt, fsz, e[2], ["C", "S", "N", "E", "W"], "geo", float(e[4]))
		if not lab2.is_empty():
			labels.append(lab2)
	features.clear()
	for it: Dictionary in items:
		features.append({"name": String(it["display"]) if it.has("display") else String(it["name"]), "id_name": it["name"], "kind": it["kind"], "cat": it["cat"],
			"pos_m": [it["pos"].x, it["pos"].y], "pos_px": [snappedf(it["px"].x, 0.1), snappedf(it["px"].y, 0.1)]})

	# ---- forests and mountains ---------------------------------------------------------------
	var road_px := PackedVector2Array()
	var step := 11.5 * k
	var y := M + 6.0
	while y < M + T - 6.0:
		var x := M + 6.0 + (int((y - M) / step) % 2) * step * 0.5
		while x < M + T - 6.0:
			var jx := x + (hs(x, y, 1) - 0.5) * step * 0.9
			var jy := y + (hs(y, x, 2) - 0.5) * step * 0.9
			var pos := Vector2(jx, jy)
			var wp := p2w(pos)
			var f := forest(wp)
			if f > 0.5 and wet(wp) <= 0.0 and road_d(wp) > 30.0 and hgt(wp) < 95.0 and minf(minf(jx, jy), minf(S - jx, S - jy)) > M + 14.0:
				if hs(jx, jy, 3) < smoothstep(0.5, 0.95, f) * 0.72:
					if not _blocked(pos, 3.0):
						trees.append([pos, 8.5 + hs(jx, jy, 4) * 5.5 + f * 3.0, hs(jx, jy, 5), f])
			x += step
		y += step * 0.86
	trees.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	# peaks
	var pstep := 44.0 * k
	y = M + 10.0
	var pi_ := 0
	while y < M + T - 10.0:
		var x2 := M + 10.0 + (pi_ % 2) * pstep * 0.5
		while x2 < M + T - 10.0:
			var pos2 := Vector2(x2 + (hs(x2, y, 6) - 0.5) * pstep * 0.8, y + (hs(y, x2, 7) - 0.5) * pstep * 0.8)
			var w3 := p2w(pos2)
			var hh := hgt(w3)
			var sl := slope(w3)
			var score := smoothstep(58.0, 125.0, hh) * 0.9 + smoothstep(0.10, 0.32, sl) * 0.6
			if score > 0.62 and wet(w3) <= 0.0 and road_d(w3) > 50.0 and hs(pos2.x, pos2.y, 8) < score * 0.7 and minf(minf(pos2.x, pos2.y), minf(S - pos2.x, S - pos2.y)) > M + 70.0 and not _blocked(pos2, 14.0):
				peaks.append([pos2, 22.0 + score * 26.0 + hs(pos2.x, pos2.y, 9) * 10.0, hs(pos2.x, pos2.y, 10)])
			x2 += pstep
		y += pstep * 0.8
		pi_ += 1
	peaks.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	print("layout: trees=", trees.size(), " peaks=", peaks.size(), " labels=", labels.size(), " icons=", icons.size())


func _blocked(pos: Vector2, pad: float) -> bool:
	for c in circles:
		if pos.distance_to(c[0]) < float(c[1]) + pad:
			return true
	for q in reserved:
		if q.grow(pad).has_point(pos):
			return true
	return false


func describe() -> Dictionary:
	return {
		"version": 1,
		"image": "res://assets/ui/maps/region1_parchment.png",
		"image_size": [int(S), int(S)],
		"seed": world["seed"],
		"world_min": [-half, -half],
		"world_max": [half, half],
		"terrain_rect_px": [M, M, T, T],
		"px_per_m": ppm,
		"m_per_px": 1.0 / ppm,
		"transform": "px = origin_px + (world - world_min) * px_per_m, origin_px = [margin, margin]; world = [x, z], north = -z = up in the image",
		"uv_of_world": "uv = (px) / image_size",
		"margin_px": M,
		"discovery_hint": "Use data/world/discovery ids; features[].name is the poster display name, id_name the data name.",
		"aliases": ALIASES,
		"proposed_places": PROPOSED,
		"elder_stones": ELDER_STONES,
		"features": features,
	}


# ------------------------------------------------------------------------ draw ----

func _draw() -> void:
	if not _built:
		_build()
	_draw_peaks()
	_draw_cliffs()
	_draw_trees()
	_draw_rivers()
	_draw_roads()
	_draw_rift_cracks()
	for ic: Array in icons:
		_draw_icon(String(ic[0]), ic[1], ic[2])
	if not bare:
		_draw_geo_paths()
		for lab: Dictionary in labels:
			if int(lab["sp"]) > 0 or float(lab["sp"]) > 0.0:
				draw_spaced(String(lab["text"]), lab["pos"], lab["font"], int(lab["fs"]), lab["col"], float(lab["sp"]))
			else:
				draw_label(String(lab["text"]), lab["pos"], lab["font"], int(lab["fs"]), lab["col"])
		_draw_edge_notes()
	_draw_neatline()
	_draw_compass()
	_draw_cartouche()
	_draw_scale_bar()


## Cliff hachures (Region 1 look): short ink ticks down every very steep face, so the Hollin's Reach
## walls and other stamped cliffs read as a valley silhouette on the sheet, poster style.
func _draw_cliffs() -> void:
	var step := 5.0
	var col := Color(INK, 0.75)
	var y := lay["margin"] as float
	while y < float(lay["margin"]) + float(lay["terrain"]):
		var x := lay["margin"] as float
		while x < float(lay["margin"]) + float(lay["terrain"]):
			var w := p2w(Vector2(x, y))
			var s := slope(w)
			if s > 1.05 and wet(w) <= 0.0:
				var d := 16.0
				var gdir := Vector2(hgt(w + Vector2(d, 0)) - hgt(w - Vector2(d, 0)), hgt(w + Vector2(0, d)) - hgt(w - Vector2(0, d))).normalized()
				var p := Vector2(x, y) + Vector2(hs(x, y) - 0.5, hs(y, x) - 0.5) * 2.0
				var ln := clampf(3.0 + (s - 1.05) * 4.0, 3.0, 8.0)
				draw_line(p, p - gdir * ln, col, 1.3, true)
			x += step
		y += step


func _draw_trees() -> void:
	for t: Array in trees:
		var c: Vector2 = t[0]
		var s: float = t[1]
		var kind := float(t[2])
		if kind < 0.45 + (1.0 - float(t[3])) * 0.2:
			_tree_round(c, s)
		else:
			_tree_pine(c, s)


func _tree_round(c: Vector2, s: float) -> void:
	draw_line(c + Vector2(0, s * 0.1), c + Vector2(0, s * 0.55), INK, 1.3)
	var cc := c + Vector2(0, -s * 0.18)
	var r := s * 0.5
	draw_circle(cc, r, TREE_FILL)
	draw_circle(cc + Vector2(-r * 0.28, -r * 0.30), r * 0.55, Color(TREE_LIT, 0.55))
	draw_arc(cc, r, 0.35, TAU - 0.15, 14, Color(INK, 0.85), 1.2, true)
	draw_arc(cc + Vector2(r * 0.15, r * 0.1), r * 0.6, 0.2, 1.7, 6, Color(INK, 0.45), 1.0, true)


func _tree_pine(c: Vector2, s: float) -> void:
	draw_line(c + Vector2(0, s * 0.35), c + Vector2(0, s * 0.62), INK, 1.3)
	var w := s * 0.55
	for i in 3:
		var yy := c.y + s * 0.4 - i * s * 0.33
		var ww := w * (1.0 - i * 0.27)
		var tri := PackedVector2Array([Vector2(c.x - ww, yy), Vector2(c.x + ww, yy), Vector2(c.x, yy - s * 0.5)])
		draw_colored_polygon(tri, TREE_DARK.lerp(TREE_FILL, i * 0.35))
		draw_line(tri[0], tri[2], Color(INK, 0.9), 1.15, true)
		draw_line(tri[2], tri[1], Color(INK, 0.9), 1.15, true)
		draw_line(Vector2(c.x + ww * 0.05, yy - s * 0.5 * 0.4), Vector2(c.x + ww * 0.7, yy - 1.0), Color(INK, 0.45), 1.0, true)


func _draw_peaks() -> void:
	for p: Array in peaks:
		if float(p[1]) > 34.0:
			_peak(p[0] + Vector2(-float(p[1]) * 0.42, 2.0), float(p[1]) * 0.62, 1.0 - float(p[2]))
		_peak(p[0], p[1], p[2])
		if float(p[2]) > 0.5:
			_peak(p[0] + Vector2(float(p[1]) * 0.48, 3.0), float(p[1]) * 0.5, float(p[2]) * 0.7)


func _peak(c: Vector2, w: float, r: float) -> void:
	var h := w * 0.95
	var apex := c + Vector2((r - 0.5) * w * 0.25, -h)
	var l := c + Vector2(-w * 0.5, 0)
	var rr := c + Vector2(w * 0.5, 0)
	var mid_l := c + Vector2(-w * 0.14, -h * 0.55)
	var mid_r := c + Vector2(w * 0.18, -h * 0.5)
	# light (left) face, shade (right) face
	draw_colored_polygon(PackedVector2Array([l, mid_l, apex, c + Vector2(0, 0)]), Color(0.90, 0.83, 0.68, 0.95))
	draw_colored_polygon(PackedVector2Array([apex, mid_r, rr, c + Vector2(0, 0)]), Color(0.72, 0.62, 0.48, 0.95))
	# hatch on the shade face
	var cnt := int(w / 3.2)
	for i in cnt:
		var u := (i + 0.5) / cnt
		var top := apex.lerp(rr, u * 0.85) + Vector2(-2.0, 3.0)
		var bot := top + Vector2(-w * 0.13 * (1.0 - u * 0.4), h * (0.5 - u * 0.25))
		bot.y = minf(bot.y, c.y)
		draw_line(top, bot, Color(INK, 0.55), 1.0, true)
	# ink outline with a little wobble and a ridge crease
	var o := PackedVector2Array([l, l.lerp(mid_l, 0.5) + Vector2(1.5, -1), mid_l, apex, mid_r, mid_r.lerp(rr, 0.5) + Vector2(-1, 1.5), rr])
	draw_polyline(o, INK, 1.5, true)
	draw_line(apex, c + Vector2(w * 0.02, 0), Color(INK, 0.55), 1.1, true)
	draw_line(l, rr, Color(INK, 0.35), 1.0, true)
	if h > 34.0:
		draw_line(apex + Vector2(-2, 6), mid_l + Vector2(-w * 0.1, h * 0.15), Color(INK, 0.4), 1.0, true)
		draw_colored_polygon(PackedVector2Array([apex, apex + Vector2(-w * 0.13, h * 0.24), apex + Vector2(0, h * 0.18), apex + Vector2(w * 0.11, h * 0.22)]), Color(0.98, 0.96, 0.9, 0.85))


func _draw_rivers() -> void:
	for river: Array in world["rivers"]:
		var pts := PackedVector2Array()
		var wsum := 0.0
		var wn := 0
		for p: Array in river:
			var v := Vector2(p[0], p[1])
			if absf(v.x) <= half and absf(v.y) <= half and not _in_zone(w2p(v)):
				pts.append(w2p(v))
				wsum += float(p[2])
				wn += 1
		if pts.size() < 2:
			continue
		var wm := maxf(wsum / maxi(wn, 1) * ppm * 1.3, 3.0)
		# smooth a little so it reads as a hand-drawn stroke
		var sm := _smooth(pts, 2)
		draw_polyline(sm, Color(INK, 0.75), wm + 2.4, true)
		draw_polyline(sm, Color(0.62, 0.80, 0.86), wm, true)
		draw_polyline(sm, Color(0.40, 0.62, 0.74, 0.7), maxf(wm * 0.4, 1.0), true)


func _in_zone(p: Vector2) -> bool:
	var d: Vector4 = zones["disc"]
	if p.distance_to(Vector2(d.x, d.y)) < d.z + 20.0:
		return true
	for key in ["a", "b"]:
		var r: Vector4 = zones[key]
		if Rect2(r.x, r.y, r.z - r.x, r.w - r.y).grow(10.0).has_point(p):
			return true
	return false


func _smooth(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := pts
	for it in iters:
		var o := PackedVector2Array()
		o.append(cur[0])
		for i in range(1, cur.size() - 1):
			o.append(cur[i - 1] * 0.25 + cur[i] * 0.5 + cur[i + 1] * 0.25)
		o.append(cur[cur.size() - 1])
		cur = o
	return cur


func _road_pts(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var len := a.distance_to(b)
	var steps := maxi(2, int(len / 14.0))
	var nrm := (b - a).orthogonal().normalized()
	for i in steps + 1:
		var t := float(i) / steps
		var wob := sin(t * len * 0.035 + a.x * 0.01) * 1.4 + sin(t * len * 0.09 + a.y * 0.02) * 0.6
		out.append(a.lerp(b, t) + nrm * wob * sin(t * PI) * 1.0)
	return out


func _dots_along(pts: PackedVector2Array, spacing: float, r: float, col: Color) -> void:
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		var dir := (b - a) / maxf(d, 0.001)
		var s := carry
		while s < d:
			draw_circle(a + dir * s, r, col)
			s += spacing
		carry = s - d


func _dashes_along(pts: PackedVector2Array, on: float, off: float, w: float, col: Color) -> void:
	var phase := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		var dir := (b - a) / maxf(d, 0.001)
		var s := 0.0
		while s < d:
			var seg := phase
			var run_on := fmod(seg, on + off) < on
			var step := minf(d - s, (on - fmod(seg, on + off)) if run_on else (on + off - fmod(seg, on + off)))
			step = maxf(step, 0.5)
			if run_on:
				draw_line(a + dir * s, a + dir * (s + step), col, w, true)
			s += step
			phase += step


func _draw_roads() -> void:
	var setts: Array = world["settlements"]
	for r: Dictionary in world["roads"]:
		var a := w2p(Vector2(setts[int(r["a"])]["pos"][0], setts[int(r["a"])]["pos"][1]))
		var b := w2p(Vector2(setts[int(r["b"])]["pos"][0], setts[int(r["b"])]["pos"][1]))
		var pts := _road_pts(a, b)
		match String(r["tier"]):
			"kingdom":
				draw_polyline(pts, Color(0.99, 0.95, 0.82, 0.9), 8.5, true)
				draw_polyline(pts, Color(INK, 0.55), 1.1, true)
				_dots_along(pts, 6.5, 2.0, Color(INK, 0.9))
			"rural":
				draw_polyline(pts, Color(0.97, 0.92, 0.76, 0.5), 5.0, true)
				_dots_along(pts, 7.0, 1.6, Color(INK, 0.85))
			_:
				_dashes_along(pts, 7.0, 7.0, 1.8, Color(INK, 0.7))


func _draw_rift_cracks() -> void:
	for s: Dictionary in world["sites"]:
		if s["kind"] != "rift":
			continue
		var c := w2p(Vector2(s["pos"][0], s["pos"][1]))
		for i in 7:
			var ang := i * TAU / 7.0 + hs(c.x, c.y, i) * 0.6
			var len := 26.0 + hs(c.y, c.x, i + 20) * 46.0
			var pts := PackedVector2Array([c])
			var cur := c
			for j in 4:
				cur += Vector2.from_angle(ang + (hs(cur.x, cur.y, j) - 0.5) * 0.9) * len * 0.25
				pts.append(cur)
			draw_polyline(pts, Color(0.32, 0.14, 0.42, 0.85), 2.0, true)
			draw_polyline(pts, Color(0.78, 0.55, 0.95, 0.5), 0.9, true)


var path_labels: Array = []


func _make_path_labels() -> void:
	var rivers: Array = world["rivers"]
	var k := S / 2048.0
	if rivers.size() > 0:
		var pts := PackedVector2Array()
		var r0: Array = rivers[0]
		for i in range(int(r0.size() * 0.42), int(r0.size() * 0.8)):
			pts.append(w2p(Vector2(r0[i][0], r0[i][1])))
		path_labels.append([_smooth(pts, 4), "The Ashrun", f_ita, int(24 * k), WATER_INK, 3.0, -16.0])
	if rivers.size() > 2:
		var r2: Array = rivers[2]
		var pts2 := PackedVector2Array()
		for i in range(int(r2.size() * 0.26), int(r2.size() * 0.60)):
			pts2.append(w2p(Vector2(r2[i][0], r2[i][1])))
		path_labels.append([_smooth(pts2, 4), "The Silverrun", f_ita, int(24 * k), WATER_INK, 3.0, 16.0])
	# Elden Road: the old runestone road Ashford -> Oakvale (Greenhollow), past the Ashrun bridge and the Shrine of the Sleeping Flame
	var setts: Array = world["settlements"]
	for r: Dictionary in world["roads"]:
		if int(r["a"]) == 0 and int(r["b"]) == 8:
			var a := w2p(Vector2(setts[0]["pos"][0], setts[0]["pos"][1]))
			var b := w2p(Vector2(setts[8]["pos"][0], setts[8]["pos"][1]))
			path_labels.append([_road_pts(a.lerp(b, 0.36), a.lerp(b, 0.98)), "Elden Road", f_ita, int(27 * k), INK, 3.0, -15.0])
	for pl: Array in path_labels:
		var bb := Rect2(pl[0][0], Vector2.ZERO)
		for p: Vector2 in pl[0]:
			bb = bb.expand(p)
		reserved.append(bb.grow(float(pl[3]) * 0.8))


func _draw_geo_paths() -> void:
	for pl: Array in path_labels:
		path_text(pl[0], pl[1], pl[2], pl[3], pl[4], pl[5], pl[6])


func _draw_edge_notes() -> void:
	var k := S / 2048.0
	var fs := int(26 * k)
	var col := Color(0.36, 0.24, 0.12, 0.9)
	var notes := [
		["To the Frostcrown Holds", Vector2(S * 0.5, M * 0.56), 0.0],
		["To the Solkar Dominion", Vector2(S * 0.5, S - M * 0.32), 0.0],
		["To the Aurelis Patriarchate", Vector2(S - M * 0.42, S * 0.5), 90.0],
		["The Western Reaches", Vector2(M * 0.46, S * 0.5), -90.0],
	]
	for nt: Array in notes:
		var txt: String = nt[0]
		var w := f_ita.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(nt[1], deg_to_rad(float(nt[2])), Vector2.ONE)
		draw_string(f_ita, Vector2(-w * 0.5, fs * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --------------------------------------------------------------------- icons ----

func _house(base: Vector2, s: float, roof: Color, wall := WALL) -> void:
	var w := s
	var hgt_ := s * 0.62
	draw_rect(Rect2(base.x - w * 0.5, base.y - hgt_, w, hgt_), wall)
	draw_rect(Rect2(base.x - w * 0.5, base.y - hgt_, w, hgt_), INK, false, 1.2)
	poly(PackedVector2Array([Vector2(base.x - w * 0.66, base.y - hgt_), Vector2(base.x + w * 0.66, base.y - hgt_), Vector2(base.x, base.y - hgt_ - s * 0.62)]), roof, INK, 1.3)
	draw_rect(Rect2(base.x - w * 0.1, base.y - hgt_ * 0.55, w * 0.2, hgt_ * 0.55), Color(0.35, 0.22, 0.12))


func _tower(base: Vector2, w: float, h: float, roof: Color, cone := true) -> void:
	draw_rect(Rect2(base.x - w * 0.5, base.y - h, w, h), Color(0.89, 0.84, 0.74))
	draw_rect(Rect2(base.x - w * 0.5, base.y - h, w * 0.32, h), Color(0.80, 0.74, 0.64))
	draw_rect(Rect2(base.x - w * 0.5, base.y - h, w, h), INK, false, 1.3)
	if cone:
		poly(PackedVector2Array([Vector2(base.x - w * 0.62, base.y - h), Vector2(base.x + w * 0.62, base.y - h), Vector2(base.x, base.y - h - w * 1.05)]), roof, INK, 1.3)
	else:
		for i in 3:
			draw_rect(Rect2(base.x - w * 0.5 + i * w * 0.36, base.y - h - w * 0.22, w * 0.28, w * 0.22), Color(0.89, 0.84, 0.74))
			draw_rect(Rect2(base.x - w * 0.5 + i * w * 0.36, base.y - h - w * 0.22, w * 0.28, w * 0.22), INK, false, 1.1)
	draw_rect(Rect2(base.x - w * 0.1, base.y - h * 0.55, w * 0.2, w * 0.3), Color(0.25, 0.17, 0.10))


func _draw_icon(kind: String, c: Vector2, it: Dictionary) -> void:
	match kind:
		"castle": _icon_castle(c)
		"town": _icon_town(c, false)
		"frontier_town": _icon_town(c, true)
		"village": _icon_village(c, String(it["name"]) == "Ashford")
		"fort":
			_tower(c + Vector2(0, 9), 16, 20, BLUE_ROOF, false)
			draw_line(c + Vector2(0, -16), c + Vector2(0, -30), INK, 1.3)
			poly(PackedVector2Array([c + Vector2(0, -30), c + Vector2(11, -26), c + Vector2(0, -22)]), RED, INK, 1.0)
		"watchfort":
			_tower(c + Vector2(0, 8), 9, 20, ROOF_R, true)
		"academy":
			_tower(c + Vector2(-8, 9), 11, 20, BLUE_ROOF)
			_tower(c + Vector2(8, 9), 11, 26, BLUE_ROOF)
			draw_rect(Rect2(c.x - 8, c.y - 4, 16, 13), WALL)
			draw_rect(Rect2(c.x - 8, c.y - 4, 16, 13), INK, false, 1.2)
		"mine":
			_peak_small(c + Vector2(0, 10), 26)
			draw_circle(c + Vector2(0, 5), 4.5, Color(0.16, 0.10, 0.06))
			draw_line(c + Vector2(6, -6), c + Vector2(15, 1), INK, 1.6, true)
			draw_line(c + Vector2(10, -8), c + Vector2(17, -2), INK, 1.6, true)
		"tower_ruin":
			poly(PackedVector2Array([c + Vector2(-6, 10), c + Vector2(-6, -8), c + Vector2(-2, -12), c + Vector2(1, -6), c + Vector2(4, -14), c + Vector2(7, -4), c + Vector2(7, 10)]), Color(0.80, 0.75, 0.66), INK, 1.3)
			draw_line(c + Vector2(-12, 10), c + Vector2(13, 10), INK, 1.3)
		"shrine":
			poly(PackedVector2Array([c + Vector2(-7, 9), c + Vector2(-7, -3), c + Vector2(0, -10), c + Vector2(7, -3), c + Vector2(7, 9)]), Color(0.86, 0.82, 0.74), INK, 1.3)
			draw_circle(c + Vector2(0, 0), 3.6, Color(0.95, 0.55, 0.15))
			draw_circle(c + Vector2(0, -1), 1.7, Color(1.0, 0.86, 0.4))
		"hollow":
			draw_arc(c, 7.0, 0, TAU, 16, INK, 1.4, true)
			for i in 5:
				var an := i * TAU / 5.0
				draw_circle(c + Vector2.from_angle(an) * 7.0, 2.1, Color(0.62, 0.60, 0.56))
			draw_circle(c, 2.0, Color(0.5, 0.7, 0.9, 0.9))
		"bridge":
			draw_arc(c + Vector2(0, 5), 8.0, PI, TAU, 10, INK, 1.8, true)
			draw_line(c + Vector2(-9, 5), c + Vector2(9, 5), INK, 1.8, true)
		"waystation":
			_house(c + Vector2(0, 8), 12, ROOF_R)
			draw_line(c + Vector2(10, 8), c + Vector2(10, -6), INK, 1.4)
			draw_rect(Rect2(c.x + 10, c.y - 6, 8, 5), Color(0.85, 0.7, 0.4))
			draw_rect(Rect2(c.x + 10, c.y - 6, 8, 5), INK, false, 1.0)
		"bandit_camp", "goblin_warren", "orc_village":
			var tc := Color(0.66, 0.22, 0.14) if kind == "bandit_camp" else (Color(0.42, 0.35, 0.22) if kind == "goblin_warren" else Color(0.32, 0.36, 0.24))
			poly(PackedVector2Array([c + Vector2(-10, 9), c + Vector2(0, -10), c + Vector2(10, 9)]), tc, INK, 1.4)
			draw_line(c + Vector2(0, -10), c + Vector2(0, -19), INK, 1.2)
			if kind == "orc_village":
				poly(PackedVector2Array([c + Vector2(0, -19), c + Vector2(8, -16), c + Vector2(0, -13)]), RED, INK, 1.0)
			draw_line(c + Vector2(-6, -4), c + Vector2(6, 4), Color(INK, 0.7), 1.3)
			draw_line(c + Vector2(6, -4), c + Vector2(-6, 4), Color(INK, 0.7), 1.3)
		"rift":
			draw_circle(c, 15.0, Color(0.42, 0.20, 0.58, 0.55))
			draw_circle(c, 9.0, Color(0.16, 0.05, 0.24, 0.95))
			draw_arc(c, 15.0, 0, TAU, 20, Color(0.75, 0.5, 0.95), 1.6, true)
			draw_arc(c, 9.0, 0, TAU, 16, INK, 1.4, true)
		"rift_outpost":
			poly(PackedVector2Array([c + Vector2(-8, 8), c + Vector2(0, -8), c + Vector2(8, 8)]), Color(0.55, 0.42, 0.68), INK, 1.4)
		"elder":
			_elder_stone(c)
		"orc_camp":
			pass
		# Region 1 look landmarks (docs/regions/LOOK_R1.md).
		"waterfall":
			poly(PackedVector2Array([c + Vector2(-11, 10), c + Vector2(-9, -12), c + Vector2(-4, -12), c + Vector2(-5, 10)]), Color(0.80, 0.72, 0.58), INK, 1.2)
			poly(PackedVector2Array([c + Vector2(4, 10), c + Vector2(5, -12), c + Vector2(10, -12), c + Vector2(11, 10)]), Color(0.72, 0.62, 0.48), INK, 1.2)
			for i in 3:
				draw_line(c + Vector2(-2.5 + i * 2.5, -12), c + Vector2(-2.5 + i * 2.5, 8), Color(0.35, 0.55, 0.8), 1.5, true)
			draw_arc(c + Vector2(0, 10), 7.0, PI, TAU, 10, Color(0.35, 0.55, 0.8), 1.4, true)
		"standing_stones", "glade":
			if kind == "glade":
				draw_circle(c, 13.0, Color(0.55, 0.68, 0.36, 0.45))
			for i in 5:
				var an := -PI * 0.5 + i * TAU / 5.0
				var sp := c + Vector2.from_angle(an) * (9.0 if kind == "glade" else 6.0)
				poly(PackedVector2Array([sp + Vector2(-2.2, 4), sp + Vector2(-1.6, -4), sp + Vector2(1.6, -4.5), sp + Vector2(2.2, 4)]), Color(0.78, 0.76, 0.70), INK, 1.0)
			if kind == "glade":
				_tree_round(c + Vector2(0, -4), 1.3)
		"ruins":
			poly(PackedVector2Array([c + Vector2(-11, 9), c + Vector2(-11, -2), c + Vector2(-6, -8), c + Vector2(-3, -3), c + Vector2(-3, 9)]), Color(0.84, 0.80, 0.70), INK, 1.2)
			poly(PackedVector2Array([c + Vector2(1, 9), c + Vector2(1, -5), c + Vector2(4, -2), c + Vector2(6, -9), c + Vector2(10, -4), c + Vector2(10, 9)]), Color(0.78, 0.74, 0.64), INK, 1.2)
		"lookout":
			_tower(c + Vector2(0, 8), 8, 18, Color(0.62, 0.58, 0.52), false)
			draw_line(c + Vector2(0, -10), c + Vector2(0, -20), INK, 1.2)
			poly(PackedVector2Array([c + Vector2(0, -20), c + Vector2(8, -17), c + Vector2(0, -14)]), RED, INK, 0.9)
		"old_bridge":
			draw_arc(c + Vector2(0, 5), 7.0, PI, TAU, 10, INK, 2.0, true)
			draw_line(c + Vector2(-9, -2), c + Vector2(9, -2), INK, 1.6, true)
		"sunken_chapel":
			poly(PackedVector2Array([c + Vector2(-5, 6), c + Vector2(-5, -6), c + Vector2(0, -16), c + Vector2(5, -6), c + Vector2(5, 6)]), Color(0.82, 0.76, 0.64), INK, 1.2)
			for i in 3:
				draw_arc(c + Vector2(0, 7 + i * 2.5), 9.0 - i * 1.5, PI * 1.05, PI * 1.95, 8, WATER_INK, 1.2, true)
		"ferry":
			draw_line(c + Vector2(-10, 4), c + Vector2(10, 4), INK, 1.6, true)
			poly(PackedVector2Array([c + Vector2(-8, 4), c + Vector2(8, 4), c + Vector2(5, 9), c + Vector2(-5, 9)]), Color(0.6, 0.42, 0.26), INK, 1.1)
			draw_line(c + Vector2(-9, 4), c + Vector2(-9, -9), INK, 1.2)
			draw_circle(c + Vector2(-9, -10), 2.6, Color(1.0, 0.75, 0.3))
		"windmill_hill":
			_peak_small(c + Vector2(0, 11), 30)
			for i in 2:
				var mc := c + Vector2(-6 + i * 12, -4 - i * 2)
				draw_rect(Rect2(mc.x - 2.5, mc.y - 2, 5, 9), WALL)
				draw_rect(Rect2(mc.x - 2.5, mc.y - 2, 5, 9), INK, false, 1.0)
				draw_line(mc + Vector2(-6, -6), mc + Vector2(6, 6), INK, 1.3, true)
				draw_line(mc + Vector2(6, -6), mc + Vector2(-6, 6), INK, 1.3, true)
		"bones":
			for i in 4:
				var bx := c.x - 11 + i * 6
				draw_arc(Vector2(bx, c.y + 8), 7.0 - i * 0.6, PI * 1.1, PI * 1.9, 8, Color(0.93, 0.88, 0.76), 2.6, true)
				draw_arc(Vector2(bx, c.y + 8), 7.0 - i * 0.6, PI * 1.1, PI * 1.9, 8, INK, 0.9, true)
			draw_circle(c + Vector2(13, 5), 4.0, Color(0.93, 0.88, 0.76))
			draw_arc(c + Vector2(13, 5), 4.0, 0, TAU, 10, INK, 1.0, true)


func _peak_small(c: Vector2, w: float) -> void:
	var apex := c + Vector2(0, -w * 0.9)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.5, 0), apex, c]), Color(0.90, 0.83, 0.68))
	draw_colored_polygon(PackedVector2Array([apex, c + Vector2(w * 0.5, 0), c]), Color(0.72, 0.62, 0.48))
	draw_polyline(PackedVector2Array([c + Vector2(-w * 0.5, 0), apex, c + Vector2(w * 0.5, 0)]), INK, 1.5, true)


func _elder_stone(c: Vector2) -> void:
	draw_circle(c + Vector2(0, -2), 15.0, Color(0.35, 0.75, 0.95, 0.18))
	poly(PackedVector2Array([c + Vector2(-6, 9), c + Vector2(-7, -3), c + Vector2(-3, -12), c + Vector2(3, -13), c + Vector2(7, -3), c + Vector2(6, 9)]), Color(0.72, 0.72, 0.72), INK, 1.5)
	var glow := Color(0.20, 0.62, 0.90)
	draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(0, 5)]), glow, 1.8, true)
	draw_polyline(PackedVector2Array([c + Vector2(-3, -3), c + Vector2(0, -6), c + Vector2(3, -3)]), glow, 1.5, true)
	draw_polyline(PackedVector2Array([c + Vector2(-3, 1), c + Vector2(3, 3)]), glow, 1.5, true)


func _icon_village(c: Vector2, home: bool) -> void:
	if home:
		for i in 7:
			var an := i * TAU / 7.0 + 0.3
			var sp := c + Vector2.from_angle(an) * 21.0
			draw_circle(sp + Vector2(0, -2), 4.5, Color(0.35, 0.75, 0.95, 0.30))
			poly(PackedVector2Array([sp + Vector2(-2.5, 3), sp + Vector2(-2.5, -3), sp + Vector2(0, -6), sp + Vector2(2.5, -3), sp + Vector2(2.5, 3)]), Color(0.75, 0.75, 0.75), INK, 1.0)
	_house(c + Vector2(-8, 4), 12, ROOF_R)
	_house(c + Vector2(8, 7), 11, ROOF_R.darkened(0.1))
	_house(c + Vector2(1, -3), 10, BLUE_ROOF)


func _icon_town(c: Vector2, palisade: bool) -> void:
	var r := 22.0 if not palisade else 17.0
	if palisade:
		for i in 22:
			var an := i * TAU / 22.0
			var p := c + Vector2.from_angle(an) * r + Vector2(0, 2)
			draw_line(p, p + Vector2(0, -6), INK, 1.8, true)
		draw_arc(c + Vector2(0, 2), r, 0, TAU, 28, Color(INK, 0.8), 1.2, true)
		_house(c + Vector2(-5, 7), 10, ROOF_R)
		_house(c + Vector2(6, 9), 10, ROOF_R)
		_house(c + Vector2(0, -1), 9, ROOF_R.darkened(0.15))
	else:
		draw_circle(c + Vector2(0, 2), r, Color(0.94, 0.88, 0.72, 0.9))
		draw_arc(c + Vector2(0, 2), r, 0, TAU, 32, INK, 2.4, true)
		for i in 8:
			var an2 := i * TAU / 8.0
			var pp := c + Vector2.from_angle(an2) * r + Vector2(0, 2)
			draw_rect(Rect2(pp.x - 3, pp.y - 4, 6, 8), Color(0.86, 0.80, 0.70))
			draw_rect(Rect2(pp.x - 3, pp.y - 4, 6, 8), INK, false, 1.1)
		_house(c + Vector2(-9, 9), 11, ROOF_R)
		_house(c + Vector2(9, 10), 11, ROOF_R)
		_house(c + Vector2(-8, -1), 10, BLUE_ROOF)
		_tower(c + Vector2(4, 4), 9, 16, BLUE_ROOF)


func _icon_castle(c: Vector2) -> void:
	# city houses ring
	for i in 9:
		var an := i * TAU / 9.0 + 0.4
		var p := c + Vector2(cos(an) * 40.0, sin(an) * 26.0 + 14.0)
		_house(p, 12, ROOF_R if i % 2 == 0 else BLUE_ROOF.lightened(0.1))
	draw_arc(c + Vector2(0, 12), 36.0, PI * 1.05, PI * 1.95, 12, Color(INK, 0.5), 1.4, true)
	# curtain wall + towers
	draw_rect(Rect2(c.x - 30, c.y - 4, 60, 22), Color(0.90, 0.85, 0.75))
	draw_rect(Rect2(c.x - 30, c.y - 4, 60, 22), INK, false, 1.6)
	for i in 6:
		draw_rect(Rect2(c.x - 30 + i * 10.5, c.y - 9, 6.5, 5), Color(0.90, 0.85, 0.75))
		draw_rect(Rect2(c.x - 30 + i * 10.5, c.y - 9, 6.5, 5), INK, false, 1.0)
	_tower(c + Vector2(-25, 18), 13, 34, BLUE_ROOF)
	_tower(c + Vector2(25, 18), 13, 34, BLUE_ROOF)
	_tower(c + Vector2(0, 14), 20, 48, BLUE_ROOF)
	draw_line(c + Vector2(0, -35 - 21), c + Vector2(0, -35 - 34), INK, 1.5)
	poly(PackedVector2Array([c + Vector2(0, -69), c + Vector2(14, -64), c + Vector2(0, -59)]), RED, INK, 1.2)
	draw_arc(c + Vector2(0, 18), 5.0, PI, TAU, 8, INK, 1.6, true)
	# gold crest dot on the keep
	draw_circle(c + Vector2(0, -14), 3.0, Color(0.90, 0.70, 0.20))


# ------------------------------------------------------------ frame and props ----

func _draw_neatline() -> void:
	var x0 := M - 12.0
	var x1 := M + T + 12.0
	draw_rect(Rect2(x0, x0, x1 - x0, x1 - x0), INK, false, 2.6)
	draw_rect(Rect2(x0 + 7, x0 + 7, x1 - x0 - 14, x1 - x0 - 14), Color(INK, 0.8), false, 1.1)
	# alternating 500 m graticule band between the lines
	var seg := 500.0 * ppm
	var cnt := int(ceil(T / seg))
	for i in cnt:
		if i % 2 == 0:
			var s := M + i * seg
			var e := minf(s + seg, M + T)
			draw_rect(Rect2(s, x0 + 1, e - s, 6), Color(INK, 0.85))
			draw_rect(Rect2(s, x1 - 7, e - s, 6), Color(INK, 0.85))
			draw_rect(Rect2(x0 + 1, s, 6, e - s), Color(INK, 0.85))
			draw_rect(Rect2(x1 - 7, s, 6, e - s), Color(INK, 0.85))
	# outer page border
	var o := 30.0
	draw_rect(Rect2(o, o, S - 2 * o, S - 2 * o), Color(INK, 0.85), false, 3.0)
	draw_rect(Rect2(o + 8, o + 8, S - 2 * o - 16, S - 2 * o - 16), Color(INK, 0.55), false, 1.2)
	for cx: float in [o, S - o]:
		for cy: float in [o, S - o]:
			var pc := Vector2(cx, cy)
			poly(PackedVector2Array([pc + Vector2(0, -12), pc + Vector2(12, 0), pc + Vector2(0, 12), pc + Vector2(-12, 0)]), Color(0.86, 0.66, 0.25), INK, 1.6)


func _draw_compass() -> void:
	var d: Vector4 = zones["disc"]
	var c := Vector2(d.x, d.y)
	var k := S / 2048.0
	var r := 118.0 * k
	draw_arc(c, r + 22 * k, 0, TAU, 72, INK, 2.6, true)
	draw_arc(c, r + 15 * k, 0, TAU, 72, Color(INK, 0.6), 1.2, true)
	draw_arc(c, r * 0.72, 0, TAU, 60, Color(INK, 0.7), 1.3, true)
	for i in 64:
		var an := i * TAU / 64.0 - PI / 2.0
		var len := 13.0 * k if i % 8 == 0 else (8.0 * k if i % 4 == 0 else 4.0 * k)
		draw_line(c + Vector2.from_angle(an) * (r + 15 * k), c + Vector2.from_angle(an) * (r + 15 * k - len), INK, 1.4, true)
	# 8-point star: long cardinal, short intercardinal
	for i in 8:
		var an2 := i * TAU / 8.0 - PI / 2.0
		var long := i % 2 == 0
		var ln := (r + 8 * k) if long else r * 0.62
		var wd := 0.17 if long else 0.13
		var tip := c + Vector2.from_angle(an2) * ln
		var lft := c + Vector2.from_angle(an2 - PI / 2.0) * ln * wd * 0.6 + Vector2.from_angle(an2) * ln * 0.12
		var rgt := c + Vector2.from_angle(an2 + PI / 2.0) * ln * wd * 0.6 + Vector2.from_angle(an2) * ln * 0.12
		draw_colored_polygon(PackedVector2Array([c, lft, tip]), Color(0.28, 0.19, 0.10) if long else Color(0.45, 0.33, 0.20))
		draw_colored_polygon(PackedVector2Array([c, tip, rgt]), Color(0.96, 0.90, 0.74))
		draw_polyline(PackedVector2Array([c, lft, tip, rgt, c]), INK, 1.3, true)
	draw_circle(c, 7.0 * k, Color(0.96, 0.90, 0.74))
	draw_arc(c, 7.0 * k, 0, TAU, 16, INK, 1.5, true)
	# north: red pointer + N
	poly(PackedVector2Array([c + Vector2(0, -r - 12 * k), c + Vector2(-9 * k, -r * 0.35), c + Vector2(9 * k, -r * 0.35)]), Color(0.66, 0.16, 0.10, 0.85), INK, 1.4)
	var fs := int(40 * k)
	draw_label("N", Vector2(c.x - f_cin_b.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, c.y - r - 30 * k), f_cin_b, fs, INK)
	var fs2 := int(24 * k)
	for pr: Array in [["E", Vector2(1, 0)], ["S", Vector2(0, 1)], ["W", Vector2(-1, 0)]]:
		var ss: Vector2 = f_cin.get_string_size(pr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
		var pp: Vector2 = c + (pr[1] as Vector2) * (r + 40 * k) - Vector2(ss.x * 0.5, -fs2 * 0.3)
		draw_string(f_cin, pp, pr[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, INK)


func _draw_cartouche() -> void:
	var a: Vector4 = zones["a"]
	var k := S / 2048.0
	var r := Rect2(a.x + 26 * k, a.y + 22 * k, a.z - a.x - 52 * k, a.w - a.y - 44 * k)
	var fill := Color(0.97, 0.92, 0.77, 0.94)
	draw_rect(r, fill)
	draw_rect(r, INK, false, 3.0)
	draw_rect(r.grow(-9), Color(INK, 0.75), false, 1.3)
	for cp: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		poly(PackedVector2Array([cp + Vector2(0, -9), cp + Vector2(9, 0), cp + Vector2(0, 9), cp + Vector2(-9, 0)]), Color(0.86, 0.66, 0.25), INK, 1.5)
	var cx := r.get_center().x
	var title := "THE ASHFORD VALE"
	var fs := int(56 * k)
	while f_cin_b.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 60 and fs > 20:
		fs -= 2
	var tw := f_cin_b.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f_cin_b, Vector2(cx - tw * 0.5, r.position.y + 72 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.26, 0.15, 0.08))
	# flourish
	var fy := r.position.y + 90 * k
	draw_line(Vector2(cx - 210 * k, fy), Vector2(cx - 18 * k, fy), INK, 1.4, true)
	draw_line(Vector2(cx + 18 * k, fy), Vector2(cx + 210 * k, fy), INK, 1.4, true)
	poly(PackedVector2Array([Vector2(cx, fy - 8), Vector2(cx + 10, fy), Vector2(cx, fy + 8), Vector2(cx - 10, fy)]), RED, INK, 1.3)
	var sub := "Heartland of the Kingdom of Valencious"
	var sfs := int(30 * k)
	var sw := f_ita.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	draw_string(f_ita, Vector2(cx - sw * 0.5, r.position.y + 128 * k), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, INK)
	var tag := "A realm rooted. A people enduring."
	var tfs := int(23 * k)
	var tgw := f_ita.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	draw_string(f_ita, Vector2(cx - tgw * 0.5, r.position.y + 160 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.45, 0.30, 0.16))


func _draw_scale_bar() -> void:
	var b: Vector4 = zones["b"]
	var k := S / 2048.0
	var km := 1000.0 * ppm
	var x0 := b.x + 60 * k
	var y := b.y + 52 * k
	for i in 2:
		draw_rect(Rect2(x0 + i * km, y, km, 11 * k), INK if i % 2 == 0 else Color(0.96, 0.90, 0.74))
	draw_rect(Rect2(x0, y, km * 2, 11 * k), INK, false, 1.6)
	var fs := int(24 * k)
	for i in 3:
		var t := "0" if i == 0 else ("%d km" % i if i == 2 else "1")
		var sw := f_reg.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f_reg, Vector2(x0 + i * km - sw * 0.5, y - 8 * k), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
