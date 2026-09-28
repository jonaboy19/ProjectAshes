extends Control
## Full-screen world map. The terrain is painted once into a 256x256 Image from
## WorldGen.height / color_at on a worker thread, in a hand-painted style:
## posterised greens banded by height with contour edges, stepped hill shading,
## dark forest, grey rock, blue water with a pale shoreline and a paper grain.
## Roads and rivers are drawn over it as lines, then discovered places, the quest
## marker and the player arrow. One finger pans, two pinch-zoom (wheel and
## trackpad gestures on desktop); tapping a place selects it, and discovered
## settlements and waystations offer fast travel.
##
## Pauses the game while open (process_mode ALWAYS on this Control).

signal travel_requested(pos: Vector2, hours: float, place: Dictionary)
signal closed

const MapIcons := preload("res://scripts/ui/map_icons.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")

const RES := 256
const TRAVEL_SPEED := 30000.0          # metres per in-game hour (30 km/h)
const MIN_TRAVEL := 60.0               # metres: closer than this you are already there
const TAP_SLOP := 14.0

# Hand-painted palette.
const PAPER := Color("1a1c24")
const GRASS := [Color("8fbf6a"), Color("79ad5c"), Color("679a50"), Color("7c8f58"), Color("8d8c6c")]
const FOREST := Color("3f6b3c")
const FOREST_DEEP := Color("30562f")
const ROCK := Color("8f8b86")
const PEAK := Color("cfcac2")
const SAND := Color("d2bd86")
const COBBLE := Color("b3a58f")
const WATER_SHALLOW := Color("78b8d8")
const WATER_DEEP := Color("3a78a6")
const FOAM := Color("d6ecf2")
const ROAD := Color("e2cb96")
const ROAD_EDGE := Color(0.18, 0.13, 0.08, 0.7)

static var _texture: ImageTexture
static var _task := -1
static var _rows_done := 0
static var _image: Image

var discovery: RefCounted              # scripts/sim/discovery.gd
var player: Node3D
var quest_target: Variant = null       # Vector2 or null
## Returns "" when fast travel is allowed, else the reason it is not.
var travel_check: Callable = func() -> String: return ""

var _zoom := 0.3                       # screen pixels per metre
var _center := Vector2.ZERO
var _touches: Dictionary = {}          # index -> position
var _press_pos := Vector2.ZERO
var _moved := 0.0
var _selected: Dictionary = {}
var _was_paused := false
var _title_font: Font
var _font: Font

var _title: Label
var _subtitle: Label
var _card: PanelContainer
var _card_name: Label
var _card_kind: Label
var _card_info: Label
var _travel_btn: Button
var _loading: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	theme = UITheme.theme()
	visible = false
	_title_font = UITheme.title_font_weight(700)
	_font = ThemeDB.fallback_font
	_build_chrome()
	set_process(false)


# --- terrain bake ----------------------------------------------------------------

## Starts painting the terrain on a worker thread (once per run; cheap to call again).
func start_bake() -> void:
	if _texture != null or _task != -1 or WorldGen.settlements.is_empty():
		return
	_rows_done = 0
	_task = WorkerThreadPool.add_task(_bake, false, "world map terrain")
	set_process(true)


func is_baked() -> bool:
	return _texture != null


func _bake() -> void:
	_image = paint_terrain(RES, func(row: int) -> void: _rows_done = row)


## Paints the overview (pure function of WorldGen; safe on a worker thread).
static func paint_terrain(n: int, progress := Callable()) -> Image:
	var half := WorldGen.WORLD_HALF
	var cell := half * 2.0 / n
	var count := n * n
	var hts := PackedFloat32Array()
	hts.resize(count)
	var wet := PackedFloat32Array()
	wet.resize(count)
	for y in n:
		var wz := -half + (y + 0.5) * cell
		for x in n:
			var wx := -half + (x + 0.5) * cell
			hts[y * n + x] = WorldGen.height(wx, wz)
			wet[y * n + x] = WorldGen.water_depth(wx, wz)
	# Material weights from the same function that paints the 3D terrain.
	var forest := PackedFloat32Array()
	forest.resize(count)
	var rock := PackedFloat32Array()
	rock.resize(count)
	var dirt := PackedFloat32Array()
	dirt.resize(count)
	var paved := PackedFloat32Array()
	paved.resize(count)
	var normals: Array[Vector3] = []
	normals.resize(count)
	for y in n:
		var wz := -half + (y + 0.5) * cell
		for x in n:
			var i := y * n + x
			var normal := Vector3((hts[y * n + maxi(x - 1, 0)] - hts[y * n + mini(x + 1, n - 1)]) / (2.0 * cell), 1.0,
				(hts[maxi(y - 1, 0) * n + x] - hts[mini(y + 1, n - 1) * n + x]) / (2.0 * cell)).normalized()
			normals[i] = normal
			if wet[i] > 0.05:
				continue
			var w := WorldGen.color_at(-half + (x + 0.5) * cell, wz, hts[i], 1.0 - normal.y)
			forest[i] = w.a
			rock[i] = w.g
			dirt[i] = w.r
			paved[i] = w.b
		if progress.is_valid():
			progress.call(int((y + 1) * 0.9))
	# Broad brush strokes: blur the masks before thresholding them into flat areas.
	forest = _blur(forest, n, 2)
	rock = _blur(rock, n, 1)
	var band_step := 14.0
	var light := Vector3(-0.6, 0.75, -0.45).normalized()   # from the north-west, like old maps
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var wz := -half + (y + 0.5) * cell
		for x in n:
			var wx := -half + (x + 0.5) * cell
			var i := y * n + x
			var h := hts[i]
			var normal: Vector3 = normals[i]
			var col: Color
			var depth := wet[i]
			if depth > 0.05:
				var k := snappedf(smoothstep(0.0, 5.0, depth), 0.34)
				col = WATER_SHALLOW.lerp(WATER_DEEP, k)
				if _wet_neighbours(wet, n, x, y) in [2, 3]:
					col = col.lerp(FOAM, 0.6)          # pale rim on lake shores (not along thin rivers)
			else:
				var band := clampi(int(floor(h / band_step)), 0, GRASS.size() - 1)
				col = GRASS[band]
				if forest[i] > 0.48:
					col = FOREST if forest[i] < 0.72 else FOREST_DEEP
				if rock[i] > 0.5:
					col = PEAK if h > 100.0 else ROCK
				if paved[i] > 0.5:
					col = COBBLE
				elif dirt[i] > 0.55 or _wet_neighbours(wet, n, x, y) > 0:
					col = SAND
				# Stepped hill shading and contour edges where the height band changes.
				var shade := snappedf(clampf(normal.dot(light), 0.0, 1.0), 0.2)
				col = col.darkened(0.22 * (1.0 - shade)) if shade < 0.8 else col.lightened(0.06)
				var b0 := int(floor(h / band_step))
				if int(floor(hts[y * n + mini(x + 1, n - 1)] / band_step)) != b0 \
						or int(floor(hts[mini(y + 1, n - 1) * n + x] / band_step)) != b0:
					col = col.darkened(0.14)
			# Paper grain and a soft darkening toward the world's edge.
			var grain := (_hash(x, y) - 0.5) * 0.05
			col = Color(col.r + grain, col.g + grain, col.b + grain)
			var edge := maxf(absf(wx), absf(wz)) / half
			col = col.darkened(smoothstep(0.82, 1.0, edge) * 0.35)
			img.set_pixel(x, y, col)
	if progress.is_valid():
		progress.call(n)
	return img


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


static func _wet_neighbours(wet: PackedFloat32Array, n: int, x: int, y: int) -> int:
	var c := 0
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if wet[clampi(y + o.y, 0, n - 1) * n + clampi(x + o.x, 0, n - 1)] > 0.05:
			c += 1
	return c


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func _process(_delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _image:
			_texture = ImageTexture.create_from_image(_image)
			_image = null
		queue_redraw()
	if _loading:
		_loading.visible = _texture == null
		if _texture == null:
			_loading.text = "Surveying the realm…  %d%%" % int(100.0 * _rows_done / RES)
	if visible and quest_target is Vector2:
		queue_redraw()          # the quest ring pulses
	if not visible and _task == -1:
		set_process(false)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# --- open / close ----------------------------------------------------------------

func open() -> void:
	if visible:
		return
	start_bake()
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	set_process(true)
	_touches.clear()
	_zoom = clampf(size.x / 1600.0, _min_zoom(), _max_zoom())
	_center = _player_pos()
	_select({})
	_refresh_header()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("world_map"):
		close()
		get_viewport().set_input_as_handled()


# --- coordinates -----------------------------------------------------------------

func _player_pos() -> Vector2:
	if player and is_instance_valid(player):
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.ZERO


func _min_zoom() -> float:
	return minf(size.x, size.y) / (WorldGen.WORLD_HALF * 2.0) * 0.92


func _max_zoom() -> float:
	return 1.6


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
	var h := WorldGen.WORLD_HALF
	_center = _center.clamp(Vector2(-h, -h), Vector2(h, h))


# --- input -----------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_press_pos = e.position
				_moved = 0.0
		else:
			var was_single := _touches.size() == 1
			_touches.erase(e.index)
			if was_single and _moved < TAP_SLOP:
				_tap(e.position)
		accept_event()
	elif e is InputEventScreenDrag:
		if not _touches.has(e.index):
			_touches[e.index] = e.position - e.relative
		var old: Vector2 = _touches[e.index]
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_moved += e.relative.length()
			if _moved >= TAP_SLOP:
				_center -= e.relative / _zoom
				_clamp_center()
				queue_redraw()
		elif _touches.size() >= 2:
			_moved = TAP_SLOP
			var other := -1
			for k: int in _touches:
				if k != e.index:
					other = k
					break
			var o: Vector2 = _touches[other]
			var d0 := old.distance_to(o)
			var d1 := (e.position as Vector2).distance_to(o)
			var mid0 := (old + o) * 0.5
			var mid1 := ((e.position as Vector2) + o) * 0.5
			_center -= (mid1 - mid0) / _zoom
			if d0 > 4.0:
				_zoom_at(mid1, d1 / d0)
			_clamp_center()
			queue_redraw()
		accept_event()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(e.position, 1.15)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(e.position, 1.0 / 1.15)
			accept_event()
	elif e is InputEventMagnifyGesture:
		_zoom_at(e.position, e.factor)
		accept_event()
	elif e is InputEventPanGesture:
		_center += e.delta * 12.0 / _zoom
		_clamp_center()
		queue_redraw()
		accept_event()


func _tap(pos: Vector2) -> void:
	var best := {}
	var best_d := 34.0
	for pl: Dictionary in _visible_places():
		var d := to_screen(pl["pos"]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = pl
	_select(best)


func _visible_places() -> Array:
	if discovery == null:
		return []
	var out := []
	for pl: Dictionary in discovery.places:
		if discovery.is_discovered(pl["id"]):
			out.append(pl)
	return out


# --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var h := WorldGen.WORLD_HALF
	var world_rect := Rect2(to_screen(Vector2(-h, -h)), Vector2(h, h) * 2.0 * _zoom)
	if _texture:
		draw_texture_rect(_texture, world_rect, false)
	else:
		draw_rect(world_rect, Color("2a3a2c"))
	draw_rect(world_rect.grow(3.0), Color(UITheme.ACCENT, 0.35), false, 2.0)
	_draw_rivers()
	_draw_roads()
	_draw_places()
	if quest_target is Vector2:
		var q := to_screen(quest_target)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		draw_arc(q, 18.0 + pulse * 6.0, 0, TAU, 32, Color(MapIcons.QUEST, 0.5 * (1.0 - pulse)), 2.0, true)
		MapIcons.draw(self, "quest", q, 30.0, MapIcons.QUEST)
	var heading := 0.0
	if player and is_instance_valid(player):
		var cam: Variant = player.get("camera")
		var node: Node3D = cam if cam is Node3D and (cam as Node3D).is_inside_tree() else player
		var f := -node.global_transform.basis.z
		heading = atan2(f.x, -f.z)
	MapIcons.draw_player(self, to_screen(_player_pos()), 13.0, heading)
	_draw_rose(Vector2(64, size.y - 76))


func _draw_rivers() -> void:
	for r: Dictionary in WorldGen.rivers:
		var pts: PackedVector2Array = r["points"]
		var widths: PackedFloat32Array = r.get("width", PackedFloat32Array())
		var sp := PackedVector2Array()
		for p in pts:
			sp.append(to_screen(p))
		var avg := 10.0
		if widths.size() > 0:
			avg = 0.0
			for wv in widths:
				avg += wv
			avg /= widths.size()
		var w := maxf(2.0, avg * _zoom)
		draw_polyline(sp, WATER_DEEP.darkened(0.2), w + 2.0, true)
		draw_polyline(sp, WATER_SHALLOW, w, true)


func _draw_roads() -> void:
	var w := clampf(6.0 * _zoom, 2.0, 7.0)
	for r in WorldGen.roads:
		var a := to_screen(WorldGen.settlements[r.x]["pos"])
		var b := to_screen(WorldGen.settlements[r.y]["pos"])
		draw_line(a, b, ROAD_EDGE, w + 2.5, true)
	for r in WorldGen.roads:
		var a := to_screen(WorldGen.settlements[r.x]["pos"])
		var b := to_screen(WorldGen.settlements[r.y]["pos"])
		draw_line(a, b, ROAD, w, true)


func _draw_places() -> void:
	var places := _visible_places()
	# Settlement footprints first so icons and names sit on top.
	for pl: Dictionary in places:
		if pl["category"] == "settlement":
			var c := to_screen(pl["pos"])
			var rr := float(pl["radius"]) * _zoom
			if rr > 6.0:
				draw_circle(c, rr, Color(0.35, 0.25, 0.15, 0.28))
				draw_arc(c, rr, 0, TAU, 40, Color(0.2, 0.14, 0.08, 0.6), 1.5, true)
	var view := Rect2(Vector2(-60, -60), size + Vector2(120, 120))
	for pl: Dictionary in places:
		var c := to_screen(pl["pos"])
		if not view.has_point(c):
			continue
		var is_town: bool = pl["category"] == "settlement"
		var s := 34.0 if is_town else 26.0
		var sel: bool = not _selected.is_empty() and _selected["id"] == pl["id"]
		if sel:
			draw_arc(c, s * 0.5 + 6.0, 0, TAU, 32, UITheme.ACCENT, 2.5, true)
		MapIcons.draw(self, String(pl["kind"]), c, s, MapIcons.color_for(pl))
		if pl["travel"]:
			draw_circle(c + Vector2(s * 0.36, -s * 0.36), 5.0, MapIcons.TRAVEL)
		if is_town or sel or _zoom > 0.32:
			var fs := 17 if is_town else 13
			var font := _title_font if is_town else _font
			var text := String(pl["name"])
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := c + Vector2(-tw * 0.5, s * 0.5 + fs + 2.0)
			draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT if not pl["hostile"] else MapIcons.HOSTILE)


func _draw_rose(c: Vector2) -> void:
	var r := 30.0
	draw_circle(c, r + 8.0, Color(UITheme.BG, 0.7))
	draw_arc(c, r + 8.0, 0, TAU, 40, UITheme.STROKE, 1.0, true)
	for i in 4:
		var a := i * PI * 0.5
		var d := Vector2(sin(a), -cos(a))
		var sd := Vector2(-d.y, d.x)
		var col := UITheme.ACCENT if i == 0 else UITheme.TEXT_DIM
		draw_colored_polygon(PackedVector2Array([c + d * r, c + sd * 5.0, c - sd * 5.0]), col)
	var fs := 13
	var nw := _title_font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_title_font, c + Vector2(-nw * 0.5, -r - 11.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.ACCENT)


# --- chrome (header, buttons, place card) ----------------------------------------

func _build_chrome() -> void:
	var header := VBoxContainer.new()
	header.position = Vector2(28, 20)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_title = _mk_label(header, 30, UITheme.ACCENT)
	_title.add_theme_font_override("font", _title_font)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(rule)
	_subtitle = _mk_label(header, 15, UITheme.TEXT_DIM)

	var close_btn := _round_button("×", 64, 36)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -88
	close_btn.offset_right = -24
	close_btn.offset_top = 20
	close_btn.offset_bottom = 84
	close_btn.pressed.connect(close)
	add_child(close_btn)

	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	tools.anchor_left = 1.0
	tools.anchor_right = 1.0
	tools.anchor_top = 1.0
	tools.anchor_bottom = 1.0
	tools.offset_left = -84
	tools.offset_right = -24
	tools.offset_top = -224
	tools.offset_bottom = -24
	add_child(tools)
	var zin := _round_button("+", 60, 30)
	zin.pressed.connect(func() -> void: _zoom_at(size * 0.5, 1.4))
	tools.add_child(zin)
	var zout := _round_button("−", 60, 30)
	zout.pressed.connect(func() -> void: _zoom_at(size * 0.5, 1.0 / 1.4))
	tools.add_child(zout)
	var me := _round_button("", 60, 20)
	me.icon = UITheme.glyph("compass", 40)
	me.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me.pressed.connect(func() -> void:
		_center = _player_pos()
		queue_redraw())
	tools.add_child(me)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.panel_box(18))
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_bottom = -20
	_card.custom_minimum_size = Vector2(440, 0)
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	_card_kind = _mk_label(box, 13, UITheme.ACCENT_2)
	_card_name = _mk_label(box, 26, UITheme.TEXT)
	_card_name.add_theme_font_override("font", _title_font)
	_card_info = _mk_label(box, 15, UITheme.TEXT_DIM)
	_card_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_info.custom_minimum_size.x = 400
	_travel_btn = Button.new()
	_travel_btn.custom_minimum_size = Vector2(400, 56)
	_travel_btn.add_theme_font_size_override("font_size", 19)
	_travel_btn.add_theme_stylebox_override("normal", UITheme.pill(UITheme.ACCENT.darkened(0.25), UITheme.ACCENT, 28))
	_travel_btn.add_theme_stylebox_override("hover", UITheme.pill(UITheme.ACCENT.darkened(0.1), UITheme.ACCENT, 28))
	_travel_btn.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT, Color.WHITE, 28))
	_travel_btn.add_theme_stylebox_override("disabled", UITheme.pill(Color(1, 1, 1, 0.04), UITheme.STROKE, 28))
	_travel_btn.add_theme_color_override("font_color", Color("1b1407"))
	_travel_btn.add_theme_color_override("font_hover_color", Color("1b1407"))
	_travel_btn.add_theme_color_override("font_pressed_color", Color("1b1407"))
	_travel_btn.pressed.connect(_on_travel)
	box.add_child(_travel_btn)

	_loading = _mk_label(self, 18, UITheme.TEXT_DIM)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _mk_label(parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _round_button(text: String, diameter: int, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	var r := diameter / 2
	b.add_theme_stylebox_override("normal", UITheme.pill(UITheme.BG, UITheme.STROKE, r))
	b.add_theme_stylebox_override("hover", UITheme.pill(UITheme.BG, UITheme.ACCENT.darkened(0.2), r))
	b.add_theme_stylebox_override("pressed", UITheme.pill(UITheme.ACCENT.darkened(0.35), UITheme.ACCENT, r))
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.set_content_margin_all(0)
	return b


func _refresh_header() -> void:
	var region := "The Realm"
	if FileAccess.file_exists("res://data/world/first_region.json"):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/first_region.json"))
		if d is Dictionary:
			region = String(d.get("name", region))
	_title.text = region.to_upper()
	var found := 0
	var total := 0
	if discovery:
		found = discovery.discovered_count()
		total = discovery.places.size()
	var ws: Node = get_node_or_null("/root/WorldSim")
	var clock := ""
	if ws:
		var t: float = ws.get("time_of_day")
		clock = "Day %d  ·  %02d:%02d  ·  " % [int(ws.get("day")), int(t), int(fmod(t, 1.0) * 60.0)]
	_subtitle.text = "%s%d of %d places discovered" % [clock, found, total]


func _select(pl: Dictionary) -> void:
	_selected = pl
	_card.visible = not pl.is_empty()
	queue_redraw()
	if pl.is_empty():
		return
	_card_kind.text = Discovery.kind_label(String(pl["kind"])).to_upper()
	_card_name.text = String(pl["name"])
	var dist := _player_pos().distance_to(pl["travel_pos"])
	var info := "%s away" % _fmt_dist(_player_pos().distance_to(pl["pos"]))
	if pl["hostile"]:
		info += "  ·  Hostile"
	_travel_btn.visible = bool(pl["travel"])
	if pl["travel"]:
		var hours := travel_hours(dist)
		var reason := travel_check.call() as String if travel_check.is_valid() else ""
		if reason == "" and dist < MIN_TRAVEL:
			reason = "You are already here."
		_travel_btn.disabled = reason != ""
		_travel_btn.text = "Fast Travel  ·  %s" % fmt_hours(hours)
		if reason != "":
			info += "\n" + reason
	_card_info.text = info
	# Keep the card compact after its text changes.
	_card.reset_size()
	_card.offset_left = -_card.get_combined_minimum_size().x * 0.5
	_card.offset_right = _card.get_combined_minimum_size().x * 0.5
	_card.offset_top = _card.offset_bottom - _card.get_combined_minimum_size().y


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
