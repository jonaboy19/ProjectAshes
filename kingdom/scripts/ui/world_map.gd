extends Control
## Full-screen storybook world map of the current region (data/world/regions.json).
##
## Terrain is painted ONCE on a worker thread from WorldGen (parchment ramp, hill
## shading, tree and mountain stamps, lakes, the Rift frontier tinted violet) into a
## cached texture; everything else (roads by tier, runestones, settlements, forts,
## sites, the player arrow) is cheap vector drawing that only re-runs when the view
## or the data changes. A soft parchment fog hides what the player has not found:
## places are shown only once Life.discovery has them, except the home settlement,
## the capital and the places on the road between them (known from the start).
## Regions come from regions.json: the current one is charted, the others are drawn
## as "Unexplored lands" beyond its border, so adding a region is adding data.
##
## One finger pans, two pinch-zoom (mouse: drag, wheel); tap a place for its card.
## Pauses the game while open (process_mode ALWAYS on this Control).

signal travel_requested(pos: Vector2, hours: float, place: Dictionary)
signal closed

const MapIcons := preload("res://scripts/ui/map_icons.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")

const REGIONS_PATH := "res://data/world/regions.json"
const TEX_SIZE := 1024                 # baked texture edge (fields are painted at half of this)
const FOG_RES := 128                   # fog mask cells across the region
const TRAVEL_SPEED := 30000.0          # metres per in-game hour (30 km/h)
const MIN_TRAVEL := 60.0               # metres: closer than this you are already there
const TAP_SLOP := 14.0
const BORDER_MARGIN := 700.0           # how far past the region border you can pan (metres)
const START_KNOWN_HOME_RADIUS := 400.0 # non-hostile places this near home are known from the start
const START_KNOWN_ROAD_RADIUS := 120.0 # ... and this near the road from home to the capital
const FOG_ALPHA := 0.8

const AREA_KINDS := ["lake", "river", "forest"]
const UNCOUNTED_KINDS := ["farm", "wayshrine", "road"]

# Painted palette (warm, saturated storybook, see ashes-art-style).
const PAPER_LIGHT := Color("f0e2bb")
const PAPER_DARK := Color("d8c08a")
const FOG_COLOR := Color("e3d2a6")
const INK := Color("3b2812")
const CREAM := Color("f6e9c8")
const LAND_RAMP := [
	[0.0, Color("86c463")], [18.0, Color("9ccb67")], [38.0, Color("b5c868")],
	[62.0, Color("aa9f62")], [90.0, Color("b6a37c")], [125.0, Color("d9cdb6")],
]
const FOREST_LIGHT := Color("5c9d47")
const FOREST_DEEP := Color("3c7538")
const ROCK := Color("a79a86")
const SAND := Color("e2d29c")
const COBBLE := Color("cdb994")
const WATER_SHALLOW := Color("79c6d8")
const WATER_DEEP := Color("3e7fb2")
const FOAM := Color("e8f6f2")
const SHADOW_TINT := Color("5b4a8c")
const SUN_TINT := Color("fff0b8")
const RIFT_TINT := Color("6d4f8e")
const RIFT_GLOW := Color("c592ff")
const ROAD_FILL := {"kingdom": Color("f3dda0"), "rural": Color("d8b878"), "frontier": Color("8a6238")}
const ROAD_CASE := Color(0.23, 0.16, 0.07, 0.85)

const KIND_LABELS := {
	"castle": "Royal Capital", "frontier_town": "Frontier Hold", "fort": "Fort", "rift_outpost": "Rift Outpost",
	"runestone": "Runestone", "rift": "The Rift", "tower_ruin": "Ancient Ruin", "hollow": "Hidden Hollow",
}
const BLURBS := {
	"castle": "Seat of the crown. The King's Ember Road runs from here to Ashford.",
	"village": "A farming village kept safe by its runestones.",
	"town": "A walled market town where the kingdom's roads meet.",
	"frontier_town": "A palisaded hold on the edge of the wild.",
	"fort": "A garrisoned bastion watching the roads.",
	"rift_outpost": "The last camp before the Rift.",
	"rift": "A wound in the world. Nothing good comes out of it.",
	"tower_ruin": "Crumbled stones of an older age.",
	"waystation": "A roadside rest with a noticeboard and fast travel.",
	"bandit_camp": "Brigands watch the road from here.",
	"goblin_warren": "A goblin warren. Best avoided.",
	"orc_village": "An orc stronghold on the frontier.",
	"mine": "An old mine in the northern hills.",
	"bridge": "A stone crossing over the Ashrun.",
	"watchfort": "A lookout tower over the valley.",
	"shrine": "A shrine to the Sleeping Flame.",
	"ruined_shrine": "A shrine to the Sleeping Flame.",
}
const PRIORITY := {
	"castle": 100, "capital": 100, "town": 80, "village": 70, "frontier_town": 65, "fort": 60, "rift": 58,
	"rift_outpost": 55, "watchfort": 50, "lake": 30, "forest": 30, "river": 28, "farm": 10, "wayshrine": 15,
}
const BIG_LABEL_KINDS := ["castle", "capital", "town", "village", "frontier_town", "fort", "rift", "rift_outpost"]

static var _texture: ImageTexture
static var _task := -1
static var _progress := 0
static var _image: Image
static var _regions_cache: Dictionary = {}
static var _legend_open := -1           # -1 = decide from the screen size on first open

var discovery: RefCounted              # scripts/sim/discovery.gd
var player: Node3D
var quest_target: Variant = null       # Vector2 or null
## Returns "" when fast travel is allowed, else the reason it is not.
var travel_check: Callable = func() -> String: return ""
## Set by the in-game tabbed menu (gamemenu/tab_map.gd) while it hosts this map inside
## a tab: hides the map's own close button and leaves Esc / M to the menu.
var embedded := false : set = set_embedded
## Optional filter, Callable(place: Dictionary) -> bool: places it rejects are hidden and not tappable.
var place_filter: Callable = Callable()
## A player-placed marker (world Vector2, x/z) or null.
var marker: Variant = null
var _close_btn: Button

var _zoom := 0.17                      # screen pixels per metre
var _center := Vector2.ZERO
var _touches: Dictionary = {}          # index -> position
var _press_pos := Vector2.ZERO
var _moved := 0.0
var _mouse_down := false
var _selected: Dictionary = {}
var _was_paused := false
var _title_font: Font
var _font: Font
var _anim := 0.0

var _region: Dictionary = {}           # the current region (bounds as Rect2)
var _neighbours: Array[Dictionary] = []
var _known: Dictionary = {}            # place id -> true: known from the start
var _shown: Array[Dictionary] = []     # known/discovered places, low priority first
var _counted := 0
var _total := 0
var _fog_texture: ImageTexture
var _fog_img: Image
var _fr: Node                       # the Frontier autoload (runestones)
var _fog_sig := ""
var _paper: NoiseTexture2D
var _hatch: ImageTexture
var _plaque := StyleBoxFlat.new()
var _panel := StyleBoxFlat.new()
var _plaque_rect := Rect2()
var _legend_rect := Rect2()
var _road_path: Array = []             # [[Vector2, Vector2]] segments home -> capital

var _title: Label
var _subtitle: Label
var _counter: Label
var _header: VBoxContainer
var _card: PanelContainer
var _card_name: Label
var _card_kind: Label
var _card_info: Label
var _travel_btn: Button
var _loading: Label
var _legend_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	theme = UITheme.theme()
	visible = false
	_title_font = UITheme.title_font_weight(700)
	_font = ThemeDB.fallback_font
	_load_region_data()
	_make_paper()
	_make_hatch()
	_build_chrome()
	resized.connect(queue_redraw)
	set_process(false)


# --- data ------------------------------------------------------------------------

## regions.json parsed once: {current: id, regions: [{id, name, status, bounds: Rect2, ...}]}.
static func load_regions() -> Dictionary:
	if not _regions_cache.is_empty():
		return _regions_cache
	var out := {"current": "", "regions": []}
	if FileAccess.file_exists(REGIONS_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGIONS_PATH))
		if d is Dictionary:
			out["current"] = String(d.get("current", ""))
			for r: Dictionary in d.get("regions", []):
				var b: Dictionary = r.get("bounds", {})
				var lo: Array = b.get("min", [-2048, -2048])
				var hi: Array = b.get("max", [2048, 2048])
				var reg := r.duplicate(true)
				reg["bounds"] = Rect2(Vector2(float(lo[0]), float(lo[1])), Vector2(float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1])))
				out["regions"].append(reg)
	if (out["regions"] as Array).is_empty():         # data missing: fall back to the whole streamed world
		var h := WorldGen.WORLD_HALF
		out["current"] = "first_region"
		out["regions"].append({"id": "first_region", "name": "The Ashford Vale", "status": "current",
			"bounds": Rect2(Vector2(-h, -h), Vector2(h, h) * 2.0)})
	_regions_cache = out
	return out


func _load_region_data() -> void:
	var data := load_regions()
	_neighbours.clear()
	for r: Dictionary in data["regions"]:
		if r["id"] == data["current"] or r.get("status", "") == "current":
			if _region.is_empty():
				_region = r
		else:
			_neighbours.append(r)
	if _region.is_empty():
		_region = data["regions"][0]


func _region_rect() -> Rect2:
	return _region["bounds"]


static func counter_text(found: int, total: int) -> String:
	return "%d of %d places discovered" % [found, total]


## True for places that count toward "N of M discovered" (not farms, wayshrines, roads).
static func is_countable(pl: Dictionary) -> bool:
	return not (String(pl.get("kind", "")) in UNCOUNTED_KINDS)


static func is_area(kind: String) -> bool:
	return kind in AREA_KINDS


## The road segments from the home settlement (index 0) to the capital, [[a, b], ...].
static func road_path_home_to_capital() -> Array:
	var out := []
	var capital := -1
	for s: Dictionary in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = int(s["id"])
			break
	if capital < 0 or WorldGen.settlements.is_empty():
		return out
	# Breadth-first over the road graph (it is a tree, so the path is unique).
	var prev := {0: -1}
	var queue := [0]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == capital:
			break
		for r in WorldGen.roads:
			var other := -1
			if r.x == cur:
				other = r.y
			elif r.y == cur:
				other = r.x
			if other >= 0 and not prev.has(other):
				prev[other] = cur
				queue.append(other)
	if not prev.has(capital):
		return out
	var at := capital
	while prev[at] != -1:
		out.append([WorldGen.settlements[prev[at]]["pos"], WorldGen.settlements[at]["pos"]])
		at = prev[at]
	return out


## Ids of the places every player knows from the start: the home settlement, the capital,
## and the non-hostile places near home or along the kingdom road between them.
static func known_from_start(places: Array) -> Dictionary:
	var known := {}
	if WorldGen.settlements.is_empty():
		return known
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var path := road_path_home_to_capital()
	for pl: Dictionary in places:
		var p: Vector2 = pl["pos"]
		var is_home: bool = pl["category"] == "settlement" and p.distance_to(home) < 1.0
		var is_capital: bool = pl["category"] == "settlement" and pl["kind"] == "castle"
		var near: bool = not bool(pl["hostile"]) and pl["category"] != "camp"
		if near and p.distance_to(home) <= START_KNOWN_HOME_RADIUS:
			known[pl["id"]] = true
		elif near:
			for seg: Array in path:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) <= START_KNOWN_ROAD_RADIUS:
					known[pl["id"]] = true
					break
		if is_home or is_capital:
			known[pl["id"]] = true
	return known


func is_place_known(pl: Dictionary) -> bool:
	return _known.has(pl["id"]) or (discovery != null and discovery.is_discovered(pl["id"]))


## Recomputes what the map shows from Discovery: call after the discovery data changes.
func refresh_model() -> void:
	_shown.clear()
	_counted = 0
	_total = 0
	if discovery == null:
		return
	_known = known_from_start(discovery.places)
	_road_path = road_path_home_to_capital()
	for pl: Dictionary in discovery.places:
		if String(pl["kind"]) == "road":
			continue
		var known := is_place_known(pl)
		if is_countable(pl):
			_total += 1
			if known:
				_counted += 1
		if known:
			_shown.append(pl)
	_shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _priority(String(a["kind"])) < _priority(String(b["kind"])))


## Re-reads Discovery and redraws (open() does this; call it if places are found while the map is up).
func refresh() -> void:
	refresh_model()
	_rebuild_fog()
	_refresh_header()
	_layout_chrome()
	queue_redraw()


func places_discovered() -> int:
	return _counted


func places_total() -> int:
	return _total


static func _priority(kind: String) -> int:
	return int(PRIORITY.get(kind, 40))


# --- terrain bake ----------------------------------------------------------------

## Starts painting the terrain on a worker thread (once per run; cheap to call again).
func start_bake() -> void:
	if _texture != null or _task != -1 or WorldGen.settlements.is_empty():
		return
	_progress = 0
	_task = WorkerThreadPool.add_task(_bake, false, "world map terrain")
	set_process(true)


func is_baked() -> bool:
	return _texture != null


func _bake() -> void:
	_image = paint_terrain(TEX_SIZE, func(pct: int) -> void: _progress = pct)


static func _ramp(h: float) -> Color:
	var stops: Array = LAND_RAMP
	if h <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		var b: Array = stops[i]
		if h <= float(b[0]):
			var a: Array = stops[i - 1]
			return (a[1] as Color).lerp(b[1], (h - float(a[0])) / (float(b[0]) - float(a[0])))
	return stops[stops.size() - 1][1]


## Paints the overview (a pure function of WorldGen; safe on a worker thread).
## `n` is the output edge in pixels; the terrain fields are sampled at n/2 and the
## picture is upscaled, then trees and peaks are stamped on at full size.
## `progress` receives 0..100.
static func paint_terrain(n: int, progress := Callable()) -> Image:
	var half := WorldGen.WORLD_HALF
	var m := clampi(n / 2, 16, n)
	var cell := half * 2.0 / m
	var count := m * m
	var hts := PackedFloat32Array()
	hts.resize(count)
	var wet := PackedFloat32Array()
	wet.resize(count)
	var forest := PackedFloat32Array()
	forest.resize(count)
	for y in m:
		var wz := -half + (y + 0.5) * cell
		for x in m:
			var wx := -half + (x + 0.5) * cell
			var h := WorldGen.height(wx, wz)
			hts[y * m + x] = h
			var lv := WorldGen.water_level_at(wx, wz)
			if not is_nan(lv) and lv > h:
				wet[y * m + x] = lv - h
			else:
				forest[y * m + x] = clampf(WorldGen.forest_density(wx, wz) * 1.3, 0.0, 1.0)
		if progress.is_valid():
			progress.call(int((y + 1) * 60.0 / m))
	forest = _blur(forest, m, 1)
	var rock := PackedFloat32Array()
	rock.resize(count)
	var slope := PackedFloat32Array()
	slope.resize(count)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()   # from the north-west, like old maps
	for y in m:
		for x in m:
			var i := y * m + x
			var nrm := Vector3((hts[y * m + maxi(x - 1, 0)] - hts[y * m + mini(x + 1, m - 1)]) / (2.0 * cell), 1.0,
				(hts[maxi(y - 1, 0) * m + x] - hts[mini(y + 1, m - 1) * m + x]) / (2.0 * cell)).normalized()
			slope[i] = 1.0 - nrm.y
			rock[i] = smoothstep(0.2, 0.34, slope[i]) + smoothstep(105.0, 135.0, hts[i])
	rock = _blur(rock, m, 1)
	var rift := _rift_pos()
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.02
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = 19
	edge_noise.frequency = 0.05
	var img := Image.create(m, m, false, Image.FORMAT_RGBA8)
	var cols := PackedColorArray()
	cols.resize(count)
	for y in m:
		var wz := -half + (y + 0.5) * cell
		for x in m:
			var wx := -half + (x + 0.5) * cell
			var i := y * m + x
			var h := hts[i]
			var col: Color
			var depth := wet[i]
			if depth > 0.0:
				var k := snappedf(smoothstep(0.0, 4.5, depth), 0.25)
				col = WATER_SHALLOW.lerp(WATER_DEEP, k)
				if _wet_neighbours(wet, m, x, y) < 4:
					col = col.lerp(FOAM, 0.55)          # pale rim along the shore
			else:
				col = _ramp(snappedf(h, 4.0))
				var tone := noise.get_noise_2d(x, y)                 # broad brush-stroke mottling
				col = col.lightened(tone * 0.10) if tone > 0.0 else col.darkened(-tone * 0.10)
				var f := forest[i]
				if f > 0.3:
					col = col.lerp(FOREST_LIGHT.lerp(FOREST_DEEP, smoothstep(0.55, 0.95, f)), smoothstep(0.3, 0.6, f) * 0.92)
				var r := rock[i]
				if r > 0.3:
					col = col.lerp(ROCK.lerp(Color("e8e0d0"), smoothstep(100.0, 140.0, h)), smoothstep(0.3, 0.7, r) * 0.9)
				var shore := _wet_neighbours(wet, m, x, y)
				if shore > 0:
					col = col.lerp(SAND, 0.75)
				# Terrace lines where a height band changes, like an engraved contour.
				var b0 := int(floor(h / 14.0))
				if int(floor(hts[y * m + mini(x + 1, m - 1)] / 14.0)) != b0 or int(floor(hts[mini(y + 1, m - 1) * m + x] / 14.0)) != b0:
					col = col.darkened(0.06)
				# Hill shading: warm sun on the north-west faces, violet in the lee.
				var nrm := Vector3((hts[y * m + maxi(x - 1, 0)] - hts[y * m + mini(x + 1, m - 1)]) / (2.0 * cell), 1.0,
					(hts[maxi(y - 1, 0) * m + x] - hts[mini(y + 1, m - 1) * m + x]) / (2.0 * cell)).normalized()
				var s := clampf((nrm.dot(light) - light.y) * 5.5, -1.0, 1.0)
				col = col.lerp(SHADOW_TINT, -s * 0.34) if s < 0.0 else col.lerp(SUN_TINT, s * 0.3)
			# Warm parchment grade.
			col = Color(col.r * 1.03, col.g * 0.99, col.b * 0.9)
			# The Rift frontier: dead violet land bleeding out from the wound.
			if rift != Vector2.INF:
				var d := Vector2(wx, wz).distance_to(rift)
				var t := smoothstep(820.0, 240.0, d)
				if t > 0.0:
					var gray := Color(col.get_luminance(), col.get_luminance(), col.get_luminance()).lerp(RIFT_TINT, 0.7)
					col = col.lerp(gray, t * 0.78)
					col = col.lerp(RIFT_GLOW, smoothstep(160.0, 0.0, d + noise.get_noise_2d(x * 3.0, y * 3.0) * 60.0) * 0.6)
			# Ragged edge: the painted land fades into bare parchment at the region border.
			var ed := minf(half - absf(wx), half - absf(wz))
			var alpha := 1.0
			if ed < 260.0:
				alpha = clampf((ed + edge_noise.get_noise_2d(wx, wz) * 110.0 - 30.0) / 150.0, 0.0, 1.0)
			col.a = alpha
			cols[i] = col
		if progress.is_valid():
			progress.call(60 + int((y + 1) * 25.0 / m))
	for i in count:
		img.set_pixel(i % m, i / m, cols[i])
	if n != m:
		img.resize(n, n, Image.INTERPOLATE_CUBIC)
	_stamp_relief(img, n, m, hts, wet, forest, rock, half)
	if progress.is_valid():
		progress.call(100)
	return img


## Tree crowns on forest, little peaks on rock: painted straight into the final image.
static func _stamp_relief(img: Image, n: int, m: int, hts: PackedFloat32Array, wet: PackedFloat32Array,
		forest: PackedFloat32Array, rock: PackedFloat32Array, half: float) -> void:
	var k := float(n) / 1024.0
	var rc := maxf(2.0, 4.2 * k)                   # crown radius in pixels
	var sp := rc * 1.55
	var fscale := float(m) / n
	var y := sp
	while y < n - sp:
		var x := sp
		while x < n - sp:
			var jx := x + (_hash(int(x), int(y)) - 0.5) * sp
			var jy := y + (_hash(int(y), int(x) + 91) - 0.5) * sp
			var fi := clampi(int(jy * fscale), 0, m - 1) * m + clampi(int(jx * fscale), 0, m - 1)
			if wet[fi] <= 0.0 and img.get_pixel(int(jx), int(jy)).a > 0.95:
				var f := forest[fi]
				if f > 0.42 and rock[fi] < 0.5 and _hash(int(x) * 3, int(y) * 7) < smoothstep(0.42, 0.8, f) * 0.95:
					_tree(img, jx, jy, rc * (0.85 + 0.3 * _hash(int(y), int(x))), n)
			x += sp
		y += sp
	# Peaks over a sparser grid so they read as landmarks.
	var pw := rc * 3.4
	var psp := pw * 0.78
	y = psp
	while y < n - psp:
		var x := psp
		while x < n - psp:
			var jx := x + (_hash(int(x) + 5, int(y)) - 0.5) * psp
			var jy := y + (_hash(int(y), int(x) + 17) - 0.5) * psp
			var fi := clampi(int(jy * fscale), 0, m - 1) * m + clampi(int(jx * fscale), 0, m - 1)
			if wet[fi] <= 0.0 and rock[fi] > 0.55 and hts[fi] > 40.0 and _hash(int(x), int(y) + 3) < 0.85 \
					and img.get_pixel(int(jx), int(jy)).a > 0.95:
				_peak(img, jx, jy, pw * (0.8 + 0.5 * smoothstep(60.0, 130.0, hts[fi])), hts[fi] > 105.0, n)
			x += psp
		y += psp


static func _tree(img: Image, cx: float, cy: float, r: float, n: int) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > r:
				continue
			var px := int(cx) + dx
			var py := int(cy) + dy
			if px < 0 or py < 0 or px >= n or py >= n:
				continue
			var lit := clampf(0.5 - (dx * 0.6 + dy * 0.8) / (r * 1.6), 0.0, 1.0)
			var col := Color("3f7d3b").lerp(Color("9ccf55"), lit)
			if d > r - 1.0:
				col = col.darkened(0.35)
			img.set_pixel(px, py, col)


static func _peak(img: Image, cx: float, cy: float, w: float, snow: bool, n: int) -> void:
	var hgt := w * 0.85
	var top := int(cy - hgt * 0.5)
	for row in int(hgt):
		var half_w := (row + 1.0) / hgt * w * 0.5
		for dx in range(-int(ceil(half_w)), int(ceil(half_w)) + 1):
			if absf(dx) > half_w:
				continue
			var px := int(cx) + dx
			var py := top + row
			if px < 0 or py < 0 or px >= n or py >= n:
				continue
			var col: Color
			if dx < 0:
				col = Color("cbb99a")
			else:
				col = Color("8a7a9a")
			if snow and row < hgt * 0.35:
				col = Color("f7f2e6") if dx < 0 else Color("cfc8e0")
			if absf(dx) > half_w - 1.2 or row >= int(hgt) - 1:
				col = Color("4a3a30")
			img.set_pixel(px, py, col)


static func _rift_pos() -> Vector2:
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "rift":
			return s["pos"]
	return Vector2.INF


## Separable box blur of an n x n field.
static func _blur(src: PackedFloat32Array, n: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(n * n)
	var out := PackedFloat32Array()
	out.resize(n * n)
	var k := 1.0 / (2 * r + 1)
	for y in n:
		for x in n:
			var s := 0.0
			for o in range(-r, r + 1):
				s += src[y * n + clampi(x + o, 0, n - 1)]
			tmp[y * n + x] = s * k
	for y in n:
		for x in n:
			var s := 0.0
			for o in range(-r, r + 1):
				s += tmp[clampi(y + o, 0, n - 1) * n + x]
			out[y * n + x] = s * k
	return out


## How many of the 4 neighbours are dry (0 = fully surrounded by water) for a wet cell,
## or how many are wet for a dry one: callers use it as a shoreline test.
static func _wet_neighbours(wet: PackedFloat32Array, n: int, x: int, y: int) -> int:
	var here := wet[y * n + x] > 0.0
	var c := 0
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var w := wet[clampi(y + o.y, 0, n - 1) * n + clampi(x + o.x, 0, n - 1)] > 0.0
		if w != here:
			c += 1
	return 4 - c if here else c


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func _make_paper() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, PAPER_DARK)
	ramp.set_color(1, PAPER_LIGHT)
	_paper = NoiseTexture2D.new()
	_paper.width = 512
	_paper.height = 512
	_paper.noise = noise
	_paper.color_ramp = ramp
	_paper.changed.connect(queue_redraw)


func _make_hatch() -> void:
	var s := 40
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := (x + y) % s
			if d < 2 or (d > 19 and d < 21):
				img.set_pixel(x, y, Color(0.35, 0.24, 0.1, 0.22 if d < 2 else 0.1))
	_hatch = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _image:
			_texture = ImageTexture.create_from_image(_image)
			_image = null
		queue_redraw()
	if _loading:
		_loading.visible = visible and _texture == null
		if _texture == null:
			_loading.text = "Surveying the realm...  %d%%" % _progress
	if visible and quest_target is Vector2:
		_anim += delta
		if _anim > 0.06:                 # the quest ring pulses at ~16 fps, not every frame
			_anim = 0.0
			queue_redraw()
	if not visible and _task == -1:
		set_process(false)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# --- fog of war ------------------------------------------------------------------

## Reveal sources: [[Vector2 pos, radius metres]] around every known place, along the
## known road and around the player.
func _fog_sources() -> Array:
	var src := []
	for pl: Dictionary in _shown:
		var kind := String(pl["kind"])
		var r := 330.0
		match kind:
			"castle", "capital": r = 760.0
			"town": r = 600.0
			"village", "frontier_town": r = 520.0
			"lake", "forest", "river": r = 520.0
			"fort": r = 400.0
			"farm": r = 200.0
		src.append([pl["pos"], r])
	for seg: Array in _road_path:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var steps := maxi(1, int(a.distance_to(b) / 110.0))
		for i in steps + 1:
			src.append([a.lerp(b, float(i) / steps), 230.0])
	if player and is_instance_valid(player):
		src.append([_player_pos(), 340.0])
	return src


## Fog alpha field (0 revealed .. 1 hidden) of FOG_RES x FOG_RES cells over `rect`.
static func fog_field(sources: Array, rect: Rect2, res: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(res * res)
	out.fill(1.0)
	var cell := rect.size / res
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	for s: Array in sources:
		var p: Vector2 = s[0]
		var r := float(s[1])
		var lo := ((p - Vector2(r, r) * 1.3 - rect.position) / cell).floor()
		var hi := ((p + Vector2(r, r) * 1.3 - rect.position) / cell).ceil()
		for cy in range(maxi(int(lo.y), 0), mini(int(hi.y), res - 1) + 1):
			for cx in range(maxi(int(lo.x), 0), mini(int(hi.x), res - 1) + 1):
				var c := rect.position + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * cell
				var d := c.distance_to(p) + noise.get_noise_2d(cx, cy) * r * 0.28
				var v := smoothstep(r * 0.55, r, d)
				var i := cy * res + cx
				if v < out[i]:
					out[i] = v
	return out


func _rebuild_fog() -> void:
	var sig := "%d:%d:%d:%d" % [_counted, _known.size(), int(_player_pos().x / 80.0), int(_player_pos().y / 80.0)]
	if sig == _fog_sig and _fog_texture != null:
		return
	_fog_sig = sig
	var field := fog_field(_fog_sources(), _region_rect(), FOG_RES)
	var img := Image.create(FOG_RES, FOG_RES, false, Image.FORMAT_RGBA8)
	for y in FOG_RES:
		for x in FOG_RES:
			var v := field[y * FOG_RES + x]
			var tone := 0.96 + 0.08 * _hash(x, y)
			img.set_pixel(x, y, Color(FOG_COLOR.r * tone, FOG_COLOR.g * tone, FOG_COLOR.b * tone, v * FOG_ALPHA))
	_fog_img = img
	_fog_texture = ImageTexture.create_from_image(img)


# --- open / close ----------------------------------------------------------------

func open() -> void:
	if visible:
		return
	start_bake()
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	set_process(true)
	if size.x < 16.0 or size.y < 16.0:
		size = get_viewport_rect().size
	_touches.clear()
	_mouse_down = false
	if _legend_open < 0:
		_legend_open = 1 if (size.x >= 1200.0 and not DisplayServer.is_touchscreen_available()) else 0
	refresh()
	_select({})
	fit_region()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible or embedded:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("world_map"):
		close()
		get_viewport().set_input_as_handled()


# --- coordinates -----------------------------------------------------------------

func _player_pos() -> Vector2:
	if player and is_instance_valid(player):
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.ZERO


func _fit_zoom() -> float:
	var r := _region_rect().size
	return minf(size.x / r.x, size.y / r.y) * 0.96


func _min_zoom() -> float:
	var r := _region_rect().size + Vector2(BORDER_MARGIN, BORDER_MARGIN) * 2.0
	return minf(size.x / r.x, size.y / r.y) * 0.9


func _max_zoom() -> float:
	return 1.6


## Shows the whole current region centred.
func fit_region() -> void:
	_zoom = clampf(_fit_zoom(), _min_zoom(), _max_zoom())
	_center = _region_rect().get_center()


## Centres the view on a world position at the given zoom (screen px per metre).
func focus_on(pos: Vector2, zoom: float) -> void:
	_zoom = clampf(zoom, _min_zoom(), _max_zoom())
	_center = pos
	_clamp_center()
	queue_redraw()


func set_embedded(on: bool) -> void:
	embedded = on
	if _close_btn:
		_close_btn.visible = not on


## Zooms about the centre of the view (factor > 1 zooms in).
func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


## Centres on the player.
func focus_player() -> void:
	focus_on(_player_pos(), maxf(_zoom, 0.55))


func toggle_legend() -> void:
	_legend_open = 0 if _legend_open == 1 else 1
	queue_redraw()


func is_legend_open() -> bool:
	return _legend_open == 1


## Puts the player marker at `pos` (world x/z), or removes it when `pos` is null.
func place_marker(pos: Variant) -> void:
	marker = pos
	queue_redraw()


## The place selected by the last tap ({} when none).
func selected_place() -> Dictionary:
	return _selected


## The view centre in world metres.
func view_center() -> Vector2:
	return _center


func _passes(pl: Dictionary) -> bool:
	return not place_filter.is_valid() or bool(place_filter.call(pl))


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _zoom


func to_world(s: Vector2) -> Vector2:
	return _center + (s - size * 0.5) / _zoom


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _min_zoom(), _max_zoom())
	_center = before - (screen_pos - size * 0.5) / _zoom
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	var r := _region_rect().grow(BORDER_MARGIN)
	_center = _center.clamp(r.position, r.end)


# --- input -----------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_press_pos = t.position
				_moved = 0.0
		else:
			var was_single := _touches.size() == 1
			_touches.erase(t.index)
			if was_single and _moved < TAP_SLOP:
				_tap(t.position)
		accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if not _touches.has(d.index):
			_touches[d.index] = d.position - d.relative
		var old: Vector2 = _touches[d.index]
		_touches[d.index] = d.position
		if _touches.size() == 1:
			_moved += d.relative.length()
			if _moved >= TAP_SLOP:
				_center -= d.relative / _zoom
				_clamp_center()
				queue_redraw()
		elif _touches.size() >= 2:
			_moved = TAP_SLOP
			var other := -1
			for k: int in _touches:
				if k != d.index:
					other = k
					break
			var o: Vector2 = _touches[other]
			var d0 := old.distance_to(o)
			var d1 := d.position.distance_to(o)
			var mid0 := (old + o) * 0.5
			var mid1 := (d.position + o) * 0.5
			_center -= (mid1 - mid0) / _zoom
			if d0 > 4.0:
				_zoom_at(mid1, d1 / d0)
			_clamp_center()
			queue_redraw()
		accept_event()
	elif e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		if b.device == InputEvent.DEVICE_ID_EMULATION:
			accept_event()          # a touch already handled above
			return
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_mouse_down = true
				_press_pos = b.position
				_moved = 0.0
			else:
				if _mouse_down and _moved < TAP_SLOP:
					_tap(b.position)
				_mouse_down = false
			accept_event()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(b.position, 1.15)
			accept_event()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(b.position, 1.0 / 1.15)
			accept_event()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _mouse_down and mm.device != InputEvent.DEVICE_ID_EMULATION:
			_moved += mm.relative.length()
			if _moved >= TAP_SLOP:
				_center -= mm.relative / _zoom
				_clamp_center()
				queue_redraw()
			accept_event()
	elif e is InputEventMagnifyGesture:
		var mg := e as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
		accept_event()
	elif e is InputEventPanGesture:
		var pg := e as InputEventPanGesture
		_center += pg.delta * 12.0 / _zoom
		_clamp_center()
		queue_redraw()
		accept_event()


func _tap(pos: Vector2) -> void:
	var best := {}
	var best_d := 34.0
	for pl: Dictionary in _shown:
		if not _passes(pl):
			continue
		var d := to_screen(pl["pos"]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = pl
	if best.is_empty():
		best = _stone_at(pos)
	_select(best)


func _frontier_node() -> Node:
	if _fr == null or not is_instance_valid(_fr):
		_fr = get_node_or_null("/root/Frontier")
	return _fr


func _runestones() -> Array:
	var fr := _frontier_node()
	if fr == null:
		return []
	var net: Variant = fr.get("runestones")
	return net.stones if net != null else []


func _stone_condition(s: Dictionary) -> String:
	var fr := _frontier_node()
	if fr == null:
		return "dark"
	return String(fr.runestones.condition_name(s))


func _stone_at(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := 22.0
	for s: Dictionary in _runestones():
		if not _stone_visible(s):
			continue
		var d := to_screen(s["pos"]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = {"id": "stone:%d" % int(s["id"]), "name": String(s["name"]), "kind": "runestone", "category": "stone",
				"pos": s["pos"], "hostile": false, "travel": false, "travel_pos": s["pos"], "stone": s}
	return best


## A runestone is shown once the fog around it is lifted.
func _stone_visible(s: Dictionary) -> bool:
	if _fog_img == null:
		return true
	var r := _region_rect()
	var f: Vector2 = (s["pos"] - r.position) / r.size
	if f.x < 0.0 or f.y < 0.0 or f.x >= 1.0 or f.y >= 1.0:
		return false
	return _fog_img.get_pixel(int(f.x * FOG_RES), int(f.y * FOG_RES)).a < 0.5 * FOG_ALPHA


# --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if _paper:
		draw_texture_rect(_paper, full, false)
	else:
		draw_rect(full, PAPER_LIGHT)
	_draw_neighbours()
	var h := WorldGen.WORLD_HALF
	var world_rect := Rect2(to_screen(Vector2(-h, -h)), Vector2(h, h) * 2.0 * _zoom)
	if _texture:
		draw_texture_rect(_texture, world_rect, false)
		if _paper:
			draw_texture_rect(_paper, world_rect, false, Color(1, 1, 1, 0.1))
	else:
		draw_rect(world_rect, Color("b9c98a"))
	_draw_border()
	_draw_rivers()
	_draw_roads()
	_draw_runestones()
	if _fog_texture:
		var rr := _region_rect()
		draw_texture_rect(_fog_texture, Rect2(to_screen(rr.position), rr.size * _zoom), false)
	_draw_places()
	if quest_target is Vector2:
		var q := to_screen(quest_target)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		draw_arc(q, 18.0 + pulse * 6.0, 0, TAU, 32, Color(MapIcons.RED, 0.6 * (1.0 - pulse)), 3.0, true)
		MapIcons.draw_marker(self, "quest", q, 32.0)
	if marker is Vector2:
		var mk := to_screen(marker)
		var pts := PackedVector2Array([mk + Vector2(0, -16), mk + Vector2(11, 0), mk + Vector2(0, 16), mk + Vector2(-11, 0)])
		draw_colored_polygon(pts, Color("d8a84e"))
		pts.append(pts[0])
		draw_polyline(pts, INK, 2.0, true)
		draw_circle(mk, 3.0, INK)
	MapIcons.draw_player(self, to_screen(_player_pos()), 12.0 * clampf(0.8 + _zoom, 0.9, 1.4), _heading())
	_draw_vignette(full)
	_draw_plaque()
	_draw_scale_bar()
	MapIcons.draw_rose(self, Vector2(64, size.y - 72), 30.0, _title_font)
	if _legend_open == 1:
		_draw_legend()


func _heading() -> float:
	if player and is_instance_valid(player):
		var cam: Variant = player.get("camera")
		var node: Node3D = cam if cam is Node3D and (cam as Node3D).is_inside_tree() else player
		var f := -node.global_transform.basis.z
		return atan2(f.x, -f.z)
	return 0.0


func _draw_vignette(full: Rect2) -> void:
	for i in 7:
		draw_rect(full.grow(-i * 9.0 - 4.0), Color(0.25, 0.15, 0.05, 0.075 * (7 - i) / 7.0), false, 9.0)


func _draw_border() -> void:
	var rr := _region_rect()
	var a := to_screen(rr.position)
	var b := to_screen(rr.end)
	var col := Color(INK, 0.6)
	draw_dashed_line(a, Vector2(b.x, a.y), col, 2.0, 12.0)
	draw_dashed_line(Vector2(b.x, a.y), b, col, 2.0, 12.0)
	draw_dashed_line(b, Vector2(a.x, b.y), col, 2.0, 12.0)
	draw_dashed_line(Vector2(a.x, b.y), a, col, 2.0, 12.0)


func _draw_neighbours() -> void:
	var view := Rect2(Vector2.ZERO, size)
	for r: Dictionary in _neighbours:
		var b: Rect2 = r["bounds"]
		var sr := Rect2(to_screen(b.position), b.size * _zoom)
		if not sr.intersects(view):
			continue
		draw_rect(sr, Color(0.62, 0.48, 0.28, 0.16))
		draw_texture_rect(_hatch, sr, true)
		draw_rect(sr, Color(INK, 0.35), false, 2.0)
		var vis := sr.intersection(view)
		if vis.size.x > 160.0 and vis.size.y > 60.0:
			var c := vis.get_center()
			var nm := String(r.get("name", "Unexplored lands")).to_upper()
			var nw := nm.length() * 17.0
			c.x = clampf(c.x, vis.position.x + nw * 0.5 + 8.0, maxf(vis.end.x - nw * 0.5 - 8.0, vis.position.x + nw * 0.5 + 8.0))
			_draw_spaced(nm, c + Vector2(0, -4), 18, Color(INK, 0.55), 4.0)
			var hint := String(r.get("hint", ""))
			if hint != "":
				var tw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(_font, c + Vector2(-tw * 0.5, 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK, 0.5))


func _draw_spaced(text: String, centre: Vector2, fs: int, col: Color, spacing: float, outline := false) -> void:
	var widths := []
	var total := 0.0
	for ch in text:
		var w := _title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w + spacing
	total -= spacing
	var x := centre.x - total * 0.5
	for i in text.length():
		if outline:
			draw_string_outline(_title_font, Vector2(x, centre.y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(CREAM, 0.9))
		draw_string(_title_font, Vector2(x, centre.y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += float(widths[i]) + spacing


func _draw_rivers() -> void:
	for r: Dictionary in WorldGen.rivers:
		var pts: PackedVector2Array = r["points"]
		var widths: PackedFloat32Array = r.get("width", PackedFloat32Array())
		var sp := PackedVector2Array()
		var rr := _region_rect()
		for p in pts:
			if rr.has_point(p):
				sp.append(to_screen(p))
		if sp.size() < 2:
			continue
		var avg := 10.0
		if widths.size() > 0:
			avg = 0.0
			for wv in widths:
				avg += wv
			avg /= widths.size()
		var w := maxf(2.5, avg * _zoom * 1.3)
		draw_polyline(sp, WATER_DEEP.darkened(0.15), w + 2.5, true)
		draw_polyline(sp, WATER_SHALLOW, w, true)


func _draw_roads() -> void:
	var wk := clampf(30.0 * _zoom, 4.0, 10.0)
	var wr := clampf(20.0 * _zoom, 3.0, 7.0)
	var wf := clampf(11.0 * _zoom, 2.0, 4.0)
	for pass_i in 2:
		for r in WorldGen.roads:
			var tier := WorldGen.road_tier(r.x, r.y)
			var a := to_screen(WorldGen.settlements[r.x]["pos"])
			var b := to_screen(WorldGen.settlements[r.y]["pos"])
			if tier == "frontier":
				if pass_i == 1:
					draw_dashed_line(a, b, ROAD_FILL["frontier"], wf, 9.0)
				continue
			var w := wk if tier == "kingdom" else wr
			if pass_i == 0:
				draw_line(a, b, ROAD_CASE, w + 3.0, true)
			else:
				draw_line(a, b, ROAD_FILL[tier], w, true)


func _draw_runestones() -> void:
	if _zoom < 0.1:
		return
	var s := clampf(_zoom * 34.0, 7.0, 13.0)
	var view := Rect2(Vector2(-20, -20), size + Vector2(40, 40))
	var sel_id := int(_selected["stone"]["id"]) if _selected.has("stone") else -1
	for st: Dictionary in _runestones():
		var c := to_screen(st["pos"])
		if view.has_point(c):
			MapIcons.draw_runestone(self, c, s, _stone_condition(st), int(st["id"]) == sel_id)


func _draw_places() -> void:
	var view := Rect2(Vector2(-60, -60), size + Vector2(120, 120))
	var sc := clampf(0.8 + _zoom * 0.9, 0.8, 1.4)
	var used: Array[Rect2] = []
	# Settlement footprints first, so icons sit on top of them.
	for pl: Dictionary in _shown:
		if pl["category"] == "settlement" and _passes(pl):
			var c := to_screen(pl["pos"])
			var rr := float(pl["radius"]) * _zoom
			if rr > 10.0:
				draw_circle(c, rr, Color(0.45, 0.3, 0.15, 0.13))
				draw_arc(c, rr, 0, TAU, 48, Color(INK, 0.4), 1.5, true)
	# Icons low to high priority, then labels high to low so important names win the space.
	var sizes := {}
	for pl: Dictionary in _shown:
		var kind := String(pl["kind"])
		if is_area(kind) or not _passes(pl):
			continue
		var c := to_screen(pl["pos"])
		if not view.has_point(c):
			continue
		var s := _icon_size(kind) * sc
		sizes[pl["id"]] = s
		var sel: bool = not _selected.is_empty() and _selected["id"] == pl["id"]
		MapIcons.draw_marker(self, kind, c, s, bool(pl["hostile"]), sel)
		if pl["travel"]:
			draw_circle(c + Vector2(s * 0.5, -s * 0.5), 5.0, MapIcons.TRAVEL)
			draw_arc(c + Vector2(s * 0.5, -s * 0.5), 5.0, 0, TAU, 12, MapIcons.INK, 1.2, true)
	for i in range(_shown.size() - 1, -1, -1):
		var pl: Dictionary = _shown[i]
		var kind := String(pl["kind"])
		var c := to_screen(pl["pos"])
		if not view.has_point(c) or not _passes(pl):
			continue
		var sel: bool = not _selected.is_empty() and _selected["id"] == pl["id"]
		if is_area(kind):
			_draw_area_label(pl, c, used)
			continue
		if not (kind in BIG_LABEL_KINDS or sel or _zoom > 0.3):
			continue
		if kind in ["farm", "wayshrine"] and not sel and _zoom < 0.7:
			continue
		var s: float = sizes.get(pl["id"], 26.0)
		var big := kind in ["castle", "capital"]
		var fs := 22 if big else (17 if kind in ["town", "village", "frontier_town"] else 14)
		var col := Color("7a1f1a") if big else (Color("5a2a0e") if not pl["hostile"] else Color("9a1f1f"))
		_draw_label(String(pl["name"]), c + Vector2(0, s * 0.62 + fs * 0.9), fs, col, used, sel)


func _icon_size(kind: String) -> float:
	match kind:
		"castle", "capital": return 50.0
		"town": return 38.0
		"village", "frontier_town": return 32.0
		"fort", "rift", "rift_outpost", "watchfort": return 34.0
		"farm": return 18.0
		"wayshrine": return 22.0
	return 28.0


func _draw_label(text: String, anchor: Vector2, fs: int, col: Color, used: Array[Rect2], force := false) -> void:
	var tw := _title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(anchor + Vector2(-tw * 0.5 - 3, -fs), Vector2(tw + 6, fs + 5))
	if not force:
		for u in used:
			if u.intersects(rect):
				return
	used.append(rect)
	var p := anchor + Vector2(-tw * 0.5, 0)
	draw_string_outline(_title_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(CREAM, 0.92))
	draw_string(_title_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_area_label(pl: Dictionary, c: Vector2, used: Array[Rect2]) -> void:
	var kind := String(pl["kind"])
	var col := Color("2b5f8a") if kind != "forest" else Color("2c5a2a")
	var fs := 15 if _zoom < 0.4 else 18
	var text := String(pl["name"]).to_upper()
	var tw := 0.0
	for ch in text:
		tw += _title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 3.0
	var rect := Rect2(c + Vector2(-tw * 0.5, -fs), Vector2(tw, fs + 4))
	for u in used:
		if u.intersects(rect):
			return
	used.append(rect)
	_draw_spaced(text, c, fs, col, 3.0, true)


func _draw_plaque() -> void:
	if _plaque_rect.size.x > 0.0:
		draw_style_box(_plaque, _plaque_rect)


func _draw_scale_bar() -> void:
	var metres := 1000.0
	for cand in [5000.0, 2000.0, 1000.0, 500.0, 200.0, 100.0, 50.0]:
		if cand * _zoom <= 150.0:
			metres = cand
			break
	var px := metres * _zoom
	var x0 := 120.0
	var y := size.y - 34.0
	var segs := 4
	draw_rect(Rect2(x0 - 6, y - 26, px + 12, 44), Color(CREAM, 0.78))
	for i in segs:
		draw_rect(Rect2(x0 + px * i / segs, y - 6, px / segs, 8), INK if i % 2 == 0 else CREAM)
	draw_rect(Rect2(x0, y - 6, px, 8), INK, false, 1.5)
	var txt := "%d m" % int(metres) if metres < 1000.0 else "%d km" % int(metres / 1000.0)
	draw_string(_font, Vector2(x0, y - 11), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(x0 + px - tw, y - 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


func _draw_legend() -> void:
	var rows := [
		["castle", "Capital"], ["town", "Town"], ["village", "Village"], ["frontier_town", "Frontier hold"],
		["fort", "Fort"], ["rift_outpost", "Rift outpost"], ["tower_ruin", "Ruins"], ["waystation", "Waystation"],
		["bandit_camp", "Camp (hostile)"],
	]
	var lines := [
		["kingdom", "King's road"], ["rural", "Country road"], ["frontier", "Frontier trail"],
		["stone:glowing", "Runestone (strong)"], ["stone:dim", "Runestone (weak)"], ["stone:dark", "Runestone (dark)"],
		["rift", "Rift frontier"], ["fog", "Undiscovered"],
	]
	var row_h := 30.0
	var w := 372.0
	var h := 40.0 + rows.size() * row_h * 0.5 + 12.0 + ceilf(rows.size() / 2.0) * 0.0
	h = 48.0 + ceilf(rows.size() / 2.0) * row_h + 10.0 + ceilf(lines.size() / 2.0) * 26.0
	var bottom := size.y - 190.0
	_legend_rect = Rect2(16, bottom - h, w, h)
	draw_style_box(_panel, _legend_rect)
	var p := _legend_rect.position
	draw_string(_title_font, p + Vector2(18, 30), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("7a1f1a"))
	draw_line(p + Vector2(18, 38), p + Vector2(w - 18, 38), Color(INK, 0.4), 1.0)
	for i in rows.size():
		var col := i % 2
		var row := i / 2
		var c := p + Vector2(38 + col * 176, 62 + row * row_h)
		MapIcons.draw_marker(self, rows[i][0], c, 24.0, rows[i][0] == "bandit_camp")
		draw_string(_font, c + Vector2(20, 5), String(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	var y0 := 62.0 + ceilf(rows.size() / 2.0) * row_h + 4.0
	for i in lines.size():
		var col := i % 2
		var row := i / 2
		var c := p + Vector2(38 + col * 176, y0 + row * 26.0)
		var id: String = lines[i][0]
		match id:
			"kingdom", "rural":
				var lw := 7.0 if id == "kingdom" else 5.0
				draw_line(c + Vector2(-16, 0), c + Vector2(16, 0), ROAD_CASE, lw + 3.0, true)
				draw_line(c + Vector2(-16, 0), c + Vector2(16, 0), ROAD_FILL[id], lw, true)
			"frontier":
				draw_dashed_line(c + Vector2(-16, 0), c + Vector2(16, 0), ROAD_FILL["frontier"], 3.0, 7.0)
			"rift":
				draw_rect(Rect2(c + Vector2(-14, -8), Vector2(28, 16)), RIFT_TINT.lerp(RIFT_GLOW, 0.3))
				draw_rect(Rect2(c + Vector2(-14, -8), Vector2(28, 16)), INK, false, 1.0)
			"fog":
				draw_rect(Rect2(c + Vector2(-14, -8), Vector2(28, 16)), FOG_COLOR)
				draw_rect(Rect2(c + Vector2(-14, -8), Vector2(28, 16)), INK, false, 1.0)
			_:
				MapIcons.draw_runestone(self, c, 12.0, id.substr(6))
		draw_string(_font, c + Vector2(24, 5), String(lines[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


# --- chrome (header, buttons, place card) ----------------------------------------

func _parchment_box(radius := 14, bg := Color(CREAM, 0.94), border := Color("6b4a22")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0.2, 0.1, 0.0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


func _build_chrome() -> void:
	_plaque = _parchment_box(12)
	_panel = _parchment_box(12)
	_header = VBoxContainer.new()
	_header.position = Vector2(32, 22)
	_header.add_theme_constant_override("separation", 1)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_title = _mk_label(_header, 30, Color("7a1f1a"))
	_title.add_theme_font_override("font", _title_font)
	var rule := ColorRect.new()
	rule.color = Color("b3372f")
	rule.custom_minimum_size = Vector2(64, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(rule)
	_subtitle = _mk_label(_header, 15, Color(INK, 0.75))
	_counter = _mk_label(_header, 19, INK)

	var close_btn := _round_button("×", 76, 48, Color("b3372f"), CREAM)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -96
	close_btn.offset_right = -20
	close_btn.offset_top = 18
	close_btn.offset_bottom = 94
	close_btn.pressed.connect(close)
	add_child(close_btn)
	_close_btn = close_btn

	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.anchor_left = 1.0
	tools.anchor_right = 1.0
	tools.anchor_top = 1.0
	tools.anchor_bottom = 1.0
	tools.offset_left = -88
	tools.offset_right = -20
	tools.offset_top = -244
	tools.offset_bottom = -20
	add_child(tools)
	var zin := _round_button("+", 68, 36, Color(CREAM, 0.95), INK)
	zin.pressed.connect(func() -> void: _zoom_at(size * 0.5, 1.4))
	tools.add_child(zin)
	var zout := _round_button("−", 68, 36, Color(CREAM, 0.95), INK)
	zout.pressed.connect(func() -> void: _zoom_at(size * 0.5, 1.0 / 1.4))
	tools.add_child(zout)
	var me := _round_button("", 68, 20, Color(CREAM, 0.95), INK)
	me.icon = UITheme.glyph("compass", 44)
	me.expand_icon = false
	me.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me.add_theme_color_override("icon_normal_color", INK)
	me.add_theme_color_override("icon_hover_color", INK)
	me.add_theme_color_override("icon_pressed_color", INK)
	me.pressed.connect(func() -> void: focus_on(_player_pos(), maxf(_zoom, 0.55)))
	tools.add_child(me)

	_legend_btn = Button.new()
	_legend_btn.text = "Legend"
	_legend_btn.focus_mode = Control.FOCUS_NONE
	_legend_btn.anchor_top = 1.0
	_legend_btn.anchor_bottom = 1.0
	_legend_btn.offset_left = 16
	_legend_btn.offset_right = 136
	_legend_btn.offset_top = -176
	_legend_btn.offset_bottom = -126
	_legend_btn.add_theme_font_size_override("font_size", 17)
	_legend_btn.add_theme_font_override("font", _title_font)
	_style_button(_legend_btn, Color(CREAM, 0.95), INK, 25)
	_legend_btn.pressed.connect(func() -> void:
		_legend_open = 0 if _legend_open == 1 else 1
		queue_redraw())
	add_child(_legend_btn)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _parchment_box(18, Color(CREAM, 0.97)))
	_card.custom_minimum_size = Vector2(440, 0)
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	_card_kind = _mk_label(box, 13, Color("b3372f"))
	_card_name = _mk_label(box, 26, INK)
	_card_name.add_theme_font_override("font", _title_font)
	_card_info = _mk_label(box, 15, Color(INK, 0.85))
	_card_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_info.custom_minimum_size.x = 400
	_travel_btn = Button.new()
	_travel_btn.custom_minimum_size = Vector2(400, 60)
	_travel_btn.add_theme_font_size_override("font_size", 19)
	_travel_btn.add_theme_stylebox_override("normal", UITheme.pill(Color("e6ad2f"), Color("6b4a22"), 30))
	_travel_btn.add_theme_stylebox_override("hover", UITheme.pill(Color("f2c04a"), Color("6b4a22"), 30))
	_travel_btn.add_theme_stylebox_override("pressed", UITheme.pill(Color("c88f1c"), Color("6b4a22"), 30))
	_travel_btn.add_theme_stylebox_override("disabled", UITheme.pill(Color(0.4, 0.3, 0.15, 0.15), Color(INK, 0.3), 30))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		_travel_btn.add_theme_color_override(c, Color("2a1806"))
	_travel_btn.add_theme_color_override("font_disabled_color", Color(INK, 0.45))
	_travel_btn.pressed.connect(_on_travel)
	box.add_child(_travel_btn)

	_loading = _mk_label(self, 20, INK)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _mk_label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(CREAM, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _style_button(b: Button, bg: Color, fg: Color, radius: int) -> void:
	var border := Color("6b4a22")
	b.add_theme_stylebox_override("normal", UITheme.pill(bg, border, radius))
	b.add_theme_stylebox_override("hover", UITheme.pill(bg.lightened(0.15), border, radius))
	b.add_theme_stylebox_override("pressed", UITheme.pill(bg.darkened(0.15), border, radius))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fg)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.set_border_width_all(3)
		sb.set_content_margin_all(0)


func _round_button(text: String, diameter: int, font_size: int, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	_style_button(b, bg, fg, diameter / 2)
	return b


func _layout_chrome() -> void:
	if _header == null:
		return
	_header.reset_size()
	var sz := _header.get_combined_minimum_size()
	_plaque_rect = Rect2(Vector2(16, 12), sz + Vector2(32, 20))
	_header.position = _plaque_rect.position + Vector2(16, 8)


func _refresh_header() -> void:
	_title.text = String(_region.get("name", "The Realm")).to_upper()
	var ws: Node = get_node_or_null("/root/WorldSim")
	var clock := ""
	if ws:
		var t: float = ws.get("time_of_day")
		clock = "  ·  Day %d  ·  %02d:%02d" % [int(ws.get("day")), int(t), int(fmod(t, 1.0) * 60.0)]
	var realm := String(_region.get("realm", ""))
	_subtitle.text = ("Realm of %s" % realm if realm != "" else "The known world") + clock
	_counter.text = counter_text(_counted, _total)


func _select(pl: Dictionary) -> void:
	_selected = pl
	_card.visible = not pl.is_empty()
	queue_redraw()
	if pl.is_empty():
		return
	var kind := String(pl["kind"])
	_card_kind.text = String(KIND_LABELS.get(kind, Discovery.kind_label(kind))).to_upper()
	_card_name.text = String(pl["name"])
	var info := "%s away" % _fmt_dist(_player_pos().distance_to(pl["pos"]))
	if pl["hostile"]:
		info += "  ·  Hostile"
	var blurb := String(BLURBS.get(kind, ""))
	if pl.has("stone"):
		var st: Dictionary = pl["stone"]
		var cn := _stone_condition(st)
		var fr := _frontier_node()
		var pct := int(round(100.0 * float(fr.runestones.strength(st)))) if fr else 0
		blurb = "Condition: %s (%d%%). Protects about %d m around it." % [cn, pct, int(st["radius"])]
	elif pl["category"] == "settlement":
		for s: Dictionary in WorldGen.settlements:
			if String(s["name"]) == String(pl["name"]):
				blurb = "%s  Home to about %d people." % [blurb, int(s["population"])]
				break
	if blurb != "":
		info += "\n" + blurb
	_travel_btn.visible = bool(pl["travel"])
	if pl["travel"]:
		var dist := _player_pos().distance_to(pl["travel_pos"])
		var hours := travel_hours(dist)
		var reason := travel_check.call() as String if travel_check.is_valid() else ""
		if reason == "" and dist < MIN_TRAVEL:
			reason = "You are already here."
		_travel_btn.disabled = reason != ""
		_travel_btn.text = "Fast Travel  ·  %s" % fmt_hours(hours)
		if reason != "":
			info += "\n" + reason
	_card_info.text = info
	# Compact card, bottom centre: sized to its wrapped text, then placed above the bottom edge.
	_place_card()
	_place_card.call_deferred()


func _place_card() -> void:
	if not _card.visible:
		return
	_card.reset_size()
	var cs := _card.get_combined_minimum_size()
	_card.size = cs
	_card.position = Vector2((size.x - cs.x) * 0.5, size.y - 20.0 - cs.y)


func _on_travel() -> void:
	if _selected.is_empty():
		return
	var pl := _selected
	var dist := _player_pos().distance_to(pl["travel_pos"])
	close()
	travel_requested.emit(pl["travel_pos"], travel_hours(dist), pl)


static func travel_hours(distance: float) -> float:
	return distance / TRAVEL_SPEED


static func fmt_hours(h: float) -> String:
	var mins := maxi(1, roundi(h * 60.0))
	return "%dh %02dm" % [mins / 60, mins % 60] if mins >= 60 else "%d min" % mins


static func _fmt_dist(d: float) -> String:
	return "%d m" % int(d) if d < 1000.0 else "%.1f km" % (d / 1000.0)
