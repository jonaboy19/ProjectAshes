extends Control
## The War Map (docs/design/WAR_COMMAND_RULEBOOK.md, phase A): war played on the real map like chess.
## Reads campaign.gd only (own pieces are truth, enemies are fogged sightings), issues unit orders by courier,
## and shows movement, contact and engagements as the campaign clock advances.
##
## Zoom levels: 0 World (armies as banners), 1 Region (armies + detached pieces over the real terrain),
## 2 Local area (every unit its own token over the actual ground). Three display styles (same war, same data):
## Realistic (muted topo), Tactical 2D (dark, clean shapes), War-table (wood and parchment).
## Nothing here runs per frame: the map redraws on data change, on input and on a 1 s timer; terrain is
## sampled a few rows per frame only while a new area is being baked.

signal closed
signal orders_sent(results: Array)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Tokens := preload("res://scripts/ui/war/war_tokens.gd")
const Terrain := preload("res://scripts/ui/war/war_terrain.gd")
const Radial := preload("res://scripts/ui/war/war_radial.gd")
const WarPanel := preload("res://scripts/ui/war/war_panel.gd")
const WarInfluence := preload("res://scripts/realm/war_influence.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")

const LEVELS := ["World", "Region", "Local"]
const TAP_SLOP := 12.0
const PANEL_W := 410.0
const ZOOM_REGION := 0.2
const ZOOM_LOCAL := 0.9
const MAX_ZOOM := 2.2
const FAN_DX := 84.0
const FAN_DY := 98.0
const ORDER_COL := {"advance": Color("5aa0ff"), "charge": Color("ff7a4a"), "retreat": Color("f0d060"), "withdraw_fighting": Color("f0d060"),
	"flank": Color("5fe0d0"), "harass": Color("c58cff"), "march": Color("5aa0ff"), "intercept": Color("ff7a4a"), "capture": Color("9be36a"),
	"follow": Color("9fb4d0"), "escort": Color("9fb4d0"), "screen": Color("9fb4d0"), "defend": Color("9be36a"), "avoid": Color("f0d060")}
const STATUS_COL := {"fighting": Color("ff6a4a"), "holding": Color("f0c860"), "ended": Color("9aa0a8")}

## Tests / other hosts may inject a realm hub; otherwise Life.realm is used (may be absent).
var realm_override: RefCounted = null
var cm: RefCounted = null
var _wi: RefCounted = null
var style := Tokens.TACTICAL
var level := 1
var zoom := ZOOM_REGION
var center := Vector2.ZERO
var sel_units: Array = []
var sel_army := -1
var sel_eng := -1
var sel_enemy := ""
var tab := "units"
var target_mode := false
var status_text := ""
var playing := false
var embedded := false
var legend_open := false

# data snapshot (refresh())
var pieces: Array = []
var armies: Dictionary = {}
var enemies: Array = []
var engs: Array = []
var orders: Array = []
var scope: Dictionary = {}

var _canvas: Control
var _land_world: Control
var _land_detail: Control
var _overlay: Control
var _panel: Control
var _row: BoxContainer
var _radial: Control
var _toast: Label
var _clock: Label
var _level_btns: Array = []
var _style_btns: Array = []
var _play_btn: Button
var _title_lbl: Label
var _style_row: HBoxContainer
var _style_cycle: Button
var _layers_cycle: Button
var _strategic: Control = null
var _zoom_grid: GridContainer
var _day_btn: Button
var _terrain := Terrain.new()
var _world_field: Object = null
var _detail_field: Object = null
var _tokens: Array = []
var _roads: Array = []
var _fog_tex: ImageTexture
var _fog_sig := ""
var _font: Font
var _title_font: Font
var _touches: Dictionary = {}
var _press_pos := Vector2.ZERO
var _press_hit: Dictionary = {}
var _moved := 0.0
var _mouse_down := false
var _drag: Dictionary = {}                 # active piece drag: {units, from, to, est}
var _menu_ctx: Dictionary = {}
var _sig := 0
var _timer: Timer
var _play_timer: Timer
var _field_timer: Timer
var _toast_timer: Timer
var _built := false
var _fitted := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = AF.font(AF.BODY_FONT)
	_title_font = AF.title_font(700)
	_build_ui()
	set_campaign(_find_campaign())


func _find_campaign() -> RefCounted:
	var realm: RefCounted = realm_override
	if realm == null:
		var life: Node = get_node_or_null("/root/Life")
		if life != null and "realm" in life:
			realm = life.realm
	return realm.mod("campaign") if realm != null and realm.has_method("mod") else null


## Points the map at a campaign module and shows it.
func set_campaign(c: RefCounted) -> void:
	cm = c
	_roads = cm.call("roads_list") if cm != null else []
	fit_start()
	refresh()


## Opens the War Map full-screen over `host` (e.g. the HUD) and returns it.
static func open_modal(host: Node, realm: RefCounted = null) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 70
	layer.name = "WarMapLayer"
	var m: Control = load("res://scripts/ui/war/war_map.gd").new()
	m.set("realm_override", realm)
	m.set("embedded", false)
	layer.add_child(m)
	m.closed.connect(layer.queue_free)
	host.add_child(layer)
	return m


# ------------------------------------------------------------------- build ----

func _build_ui() -> void:
	if _built:
		return
	_built = true
	var row := BoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	_row = row
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_on_canvas_resized)
	row.add_child(_canvas)
	_land_world = LandLayer.new()
	_land_detail = LandLayer.new()
	_overlay = OverlayLayer.new()
	for l: Control in [_land_world, _land_detail, _overlay]:
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set("map", self)
		_canvas.add_child(l)
	_panel = WarPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.set("map", self)
	row.add_child(_panel)
	_build_toolbar()
	_build_zoom_cluster()
	_build_clock()
	_toast = Kit.lbl("", 18, AF.GOLD_BRIGHT, true, "italic")
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 70
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas.add_child(_toast)
	_radial = Radial.new()
	_radial.picked.connect(_on_behavior_picked)
	_radial.cancelled.connect(_on_radial_cancelled)
	_canvas.add_child(_radial)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_timer.start()
	_play_timer = Timer.new()
	_play_timer.wait_time = 0.6
	_play_timer.timeout.connect(_on_play)
	add_child(_play_timer)
	_field_timer = Timer.new()
	_field_timer.one_shot = true
	_field_timer.wait_time = 0.25
	_field_timer.timeout.connect(_update_fields)
	add_child(_field_timer)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 7.0
	_toast_timer.timeout.connect(func() -> void: _toast.text = "")
	add_child(_toast_timer)
	set_process(false)
	_relayout()


func _styled(text: String, on: bool, cb: Callable, min_w := 0.0) -> Button:
	var b := Kit.tab_button(text, on, cb, min_w)
	b.custom_minimum_size.y = 52
	return b


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.86), AF.GOLD_DIM, 4, 6))
	bar.position = Vector2(10, 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bar.add_child(v)
	var h1 := HBoxContainer.new()
	h1.add_theme_constant_override("separation", 6)
	v.add_child(h1)
	var t := Kit.lbl("WAR MAP", 20, AF.GOLD_BRIGHT, false, "title_bold")
	t.custom_minimum_size = Vector2(112, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h1.add_child(t)
	_title_lbl = t
	for i in LEVELS.size():
		var b := _styled(LEVELS[i], i == level, set_level.bind(i), 86)
		h1.add_child(b)
		_level_btns.append(b)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 6)
	v.add_child(h2)
	_style_row = h2
	for i in Tokens.STYLE_NAMES.size():
		var b2 := _styled(Tokens.STYLE_NAMES[i], i == style, set_style.bind(i), 120)
		h2.add_child(b2)
		_style_btns.append(b2)
	h2.add_child(_styled("Layers", false, open_overlays, 100))
	var key := _styled("Key", false, toggle_legend, 70)
	h1.add_child(key)
	_style_cycle = _styled("Style", false, func() -> void: set_style((style + 1) % 3), 80)
	_style_cycle.visible = false
	h1.add_child(_style_cycle)
	_layers_cycle = _styled("Layers", false, open_overlays, 80)
	_layers_cycle.visible = false
	h1.add_child(_layers_cycle)
	if not embedded:
		var x := _styled("Close", false, close, 80)
		h1.add_child(x)
	_canvas.add_child(bar)


## Opens the strategic overlay map (trade, resources, politics, danger...) over the war table.
func open_overlays() -> Control:
	if _strategic != null and is_instance_valid(_strategic):
		return _strategic
	var m: Control = load("res://scripts/ui/strategic/strategic_map.gd").new()
	m.set("realm_override", realm_override)
	m.set("embedded", true)
	m.connect("closed", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		_strategic = null)
	add_child(m)
	_strategic = m
	return m


func _restyle_toolbar() -> void:
	for i in _level_btns.size():
		_restyle(_level_btns[i], i == level)
	for i in _style_btns.size():
		_restyle(_style_btns[i], i == style)


func _restyle(b: Button, on: bool) -> void:
	var normal := Kit.box(Color(0.03, 0.028, 0.025, 0.55), AF.GOLD_DIM, 3, 8)
	var lit := Kit.box(Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.2), AF.GOLD, 3, 8)
	b.add_theme_stylebox_override("normal", lit if on else normal)
	b.add_theme_stylebox_override("focus", lit if on else normal)
	b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else AF.TEXT_DIM)


func _build_zoom_cluster() -> void:
	var v := GridContainer.new()
	v.columns = 1
	v.add_theme_constant_override("h_separation", 8)
	v.add_theme_constant_override("v_separation", 8)
	v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_right = -12
	v.offset_bottom = -12
	_zoom_grid = v
	for spec: Array in [["+", zoom_in], ["-", zoom_out], ["Fit", fit_start], ["Focus", focus_selection]]:
		var b := Kit.button(String(spec[0]), false, 64.0, 26 if String(spec[0]).length() == 1 else 15)
		b.custom_minimum_size = Vector2(64, 64)
		b.pressed.connect(spec[1])
		v.add_child(b)
	_canvas.add_child(v)


func _build_clock() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	h.offset_left = 10
	h.offset_bottom = -10
	h.offset_top = -66
	h.offset_right = 640
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.86), AF.GOLD_DIM, 4, 8))
	_clock = Kit.lbl("Day 0, 00:00", 17, AF.TEXT)
	_clock.custom_minimum_size = Vector2(150, 0)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_child(_clock)
	h.add_child(pc)
	_play_btn = Kit.button("Play", false, 56.0, 16)
	_play_btn.custom_minimum_size = Vector2(76, 56)
	_play_btn.pressed.connect(toggle_play)
	h.add_child(_play_btn)
	for spec: Array in [["+1 h", 1], ["+6 h", 6], ["+1 day", 24]]:
		var b := Kit.button(String(spec[0]), false, 56.0, 16)
		b.custom_minimum_size = Vector2(76, 56)
		b.pressed.connect(advance.bind(int(spec[1])))
		h.add_child(b)
		if int(spec[1]) == 24:
			_day_btn = b
	_canvas.add_child(h)


# ------------------------------------------------------------- view control ----

func canvas_size() -> Vector2:
	return _canvas.size if _canvas != null and _canvas.size.x > 8.0 else Vector2(880, 720)


func to_screen(w: Vector2) -> Vector2:
	return (w - center) * zoom + canvas_size() * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - canvas_size() * 0.5) / zoom + center


func _fit_zoom() -> float:
	var cs := canvas_size()
	return minf(cs.x, cs.y) / (WorldGen.WORLD_HALF * 2.0) * 0.98


func _min_zoom() -> float:
	return _fit_zoom() * 0.85


func _level_for(z: float) -> int:
	return 0 if z < 0.13 else (1 if z < 0.5 else 2)


## Called once at start and by the Fit button: the whole world, or the player's forces if there are any.
func fit_start() -> void:
	if _canvas == null:
		return
	var own := _own_centroid()
	center = own if own != Vector2.INF else Vector2.ZERO
	zoom = ZOOM_REGION
	_apply_zoom_change()


func _own_centroid() -> Vector2:
	if cm == null:
		return Vector2.INF
	var s := Vector2.ZERO
	var n := 0
	for a: Dictionary in cm.call("player_armies"):
		s += a["pos"] as Vector2
		n += 1
	return s / float(n) if n > 0 else Vector2.INF


func set_level(l: int) -> void:
	level = clampi(l, 0, 2)
	var target := [_fit_zoom(), ZOOM_REGION, ZOOM_LOCAL][level] as float
	if level == 0:
		center = Vector2.ZERO
	else:
		var f := _selection_center()
		if f != Vector2.INF:
			center = f
	zoom = target
	if level == 2 and sel_units.is_empty():
		center += Vector2(0, FAN_DY * 1.5 / zoom)
	_apply_zoom_change()


func set_style(s: int) -> void:
	style = clampi(s, 0, 2)
	for l: Control in [_land_world, _land_detail]:
		var m: Variant = l.material
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("style", style)
	_restyle_toolbar()
	_fog_sig = ""
	refresh_view()


func toggle_legend() -> void:
	legend_open = not legend_open
	_overlay.queue_redraw()


func zoom_in() -> void:
	_zoom_at(canvas_size() * 0.5, 1.5)


func zoom_out() -> void:
	_zoom_at(canvas_size() * 0.5, 1.0 / 1.5)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := to_world(screen_pos)
	zoom = clampf(zoom * factor, _min_zoom(), MAX_ZOOM)
	center = before - (screen_pos - canvas_size() * 0.5) / zoom
	_apply_zoom_change()


func _apply_zoom_change() -> void:
	level = _level_for(zoom)
	_clamp_center()
	_restyle_toolbar()
	if _field_timer != null and is_inside_tree():
		_field_timer.start()
	else:
		_update_fields()
	refresh_view()


func _clamp_center() -> void:
	var h := WorldGen.WORLD_HALF + 300.0
	center = center.clamp(Vector2(-h, -h), Vector2(h, h))


func focus_on(pos: Vector2, z: float = -1.0) -> void:
	center = pos
	if z > 0.0:
		zoom = z
	_apply_zoom_change()


func focus_selection() -> void:
	var f := _selection_center()
	if f != Vector2.INF:
		var z := maxf(zoom, ZOOM_REGION)
		focus_on(f + (Vector2(0, FAN_DY * 1.5 / z) if _level_for(z) == 2 and not armies.is_empty() else Vector2.ZERO), z)


func _selection_center() -> Vector2:
	if not sel_units.is_empty():
		var s := Vector2.ZERO
		for id in sel_units:
			s += cm.call("unit_pos", int(id)) as Vector2
		return s / float(sel_units.size())
	if armies.has(sel_army):
		return (armies[sel_army] as Dictionary)["pos"] as Vector2
	return Vector2.INF


func _on_canvas_resized() -> void:
	if _built:
		refresh_view()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built and _row != null:
		_relayout()


## Landscape: map left, panel right. Portrait (phones held upright): map on top, panel below.
func _relayout() -> void:
	var portrait := size.x < size.y * 0.95
	_row.vertical = portrait
	_panel.custom_minimum_size = Vector2(0, size.y * 0.46) if portrait else Vector2(PANEL_W, 0)
	_title_lbl.visible = not portrait
	_style_row.visible = not portrait
	_style_cycle.visible = portrait
	if _layers_cycle != null:
		_layers_cycle.visible = portrait
	_zoom_grid.columns = 2 if portrait else 1
	_zoom_grid.offset_bottom = -76 if portrait else -12
	_day_btn.visible = not portrait
	_clock.custom_minimum_size.x = 96 if portrait else 150


# -------------------------------------------------------------------- data ----

## Re-reads the campaign (call after any action or tick). Cheap; draws once.
func refresh() -> void:
	if cm == null:
		pieces = []
		armies = {}
		enemies = []
		engs = []
		orders = []
		scope = {}
	else:
		pieces = cm.call("own_pieces")
		enemies = cm.call("enemy_pieces")
		engs = cm.call("engagements")
		orders = cm.call("orders")
		scope = cm.call("command_scope")
		armies = {}
		for a: Dictionary in cm.call("player_armies"):
			armies[int(a["id"])] = a
		for p: Dictionary in pieces:
			var ad: Dictionary = armies.get(int(p["army"]), {})
			if ad.is_empty():
				continue
			if not ad.has("piece_list"):
				ad["piece_list"] = []
			(ad["piece_list"] as Array).append(p)
		# keep the selection valid
		var alive := {}
		for p2: Dictionary in pieces:
			alive[int(p2["id"])] = true
		sel_units = sel_units.filter(func(id: Variant) -> bool: return alive.has(int(id)))
		if not armies.has(sel_army):
			sel_army = int(armies.keys()[0]) if not armies.is_empty() else -1
		_sig = _signature()
	if _clock != null:
		var h: int = int(cm.call("now_hours")) if cm != null else 0
		_clock.text = "Day %d, %02d:00" % [h / 24, h % 24]
	_update_fields()
	refresh_view()
	if _panel != null:
		_panel.call("rebuild")


func _signature() -> int:
	if cm == null:
		return 0
	return hash([cm.call("now_hours"), (cm.call("couriers") as Array).size(), (cm.call("engagements") as Array).size(), (cm.call("enemy_pieces") as Array).size()])


func _on_timer() -> void:
	if not is_visible_in_tree() or cm == null:
		return
	if _signature() != _sig:
		refresh()


func refresh_view() -> void:
	if _canvas == null:
		return
	_layout_tokens()
	_overlay.queue_redraw()
	_land_world.queue_redraw()
	_land_detail.queue_redraw()


func advance(hours: int) -> void:
	if cm == null:
		return
	var out: Array = cm.call("advance_hours", hours, {})
	for m in out.slice(0, 2):
		say(String(m))
	refresh()


func toggle_play() -> void:
	playing = not playing
	_play_btn.text = "Pause" if playing else "Play"
	if playing:
		_play_timer.start()
	else:
		_play_timer.stop()


func _on_play() -> void:
	advance(1)


func say(text: String) -> void:
	status_text = text
	if _toast != null:
		_toast.text = text
		_toast_timer.start()


func close() -> void:
	if playing:
		toggle_play()
	closed.emit()
	if not embedded and get_parent() is CanvasLayer:
		pass


# ------------------------------------------------------------------ terrain ----

func _update_fields() -> void:
	if _land_world == null:
		return
	_world_field = _terrain.world()
	if level >= 1:
		var span := Terrain.REGION_SPAN if level == 1 else Terrain.LOCAL_SPAN
		var n := Terrain.REGION_RES if level == 1 else Terrain.LOCAL_RES
		_detail_field = _terrain.request(center, span, n)
	else:
		_detail_field = null
	_land_world.set("field", _world_field)
	_land_detail.set("field", _detail_field)
	_sync_materials()
	set_process(_terrain.pending())


func _sync_materials() -> void:
	for pair: Array in [[_land_world, _world_field], [_land_detail, _detail_field]]:
		var l: Control = pair[0]
		var f: Object = pair[1]
		if f != null and bool(f.get("ready")) and l.get("mat_for") != f:
			l.material = Terrain.make_material(f, style)
			l.set("mat_for", f)
		elif f == null:
			l.material = null
			l.set("mat_for", null)
		l.queue_redraw()


func _process(_d: float) -> void:
	var more := _terrain.step(6000)
	_sync_materials()
	if not more:
		set_process(false)
		_overlay.queue_redraw()


## Bakes every pending terrain field right away (screenshots, tests).
func bake_now() -> void:
	_update_fields()
	_terrain.finish_all()
	_sync_materials()
	set_process(false)
	refresh_view()


func terrain_ready() -> bool:
	return _world_field != null and bool(_world_field.get("ready")) and (level == 0 or (_detail_field != null and bool(_detail_field.get("ready"))))


# ------------------------------------------------------------------- layout ----

func _kind_dominant(comp: Dictionary) -> String:
	var best := ""
	var bn := -1
	for k: String in comp:
		if int(comp[k]) > bn:
			bn = int(comp[k])
			best = k
	return best


## Rebuilds the token list (screen positions) for the current view.
func _layout_tokens() -> void:
	_tokens.clear()
	if cm == null or _canvas == null:
		return
	var r_army := [22.0, 30.0, 26.0][level] as float
	var r_unit := [16.0, 27.0, 32.0][level] as float
	for aid: int in armies:
		var a: Dictionary = armies[aid]
		var apos: Vector2 = a["pos"]
		var attached: Array = []
		var detached: Array = []
		for p: Dictionary in (a.get("piece_list", []) as Array):
			(detached if bool(p["detached"]) else attached).append(p)
		if not attached.is_empty():
			var men := 0
			for p2: Dictionary in attached:
				men += int(p2["men"])
			var scr := to_screen(apos)
			if level == 2:
				_tokens.append({"t": "anchor", "id": aid, "army": aid, "w": apos, "scr": scr, "r": 18.0, "kind": "army", "men": men, "own": true,
					"label": String(a["name"]), "stack": attached.size(), "sel": aid == sel_army and sel_units.is_empty()})
				var offs := _fan(attached)
				for i in attached.size():
					var p3: Dictionary = attached[i]
					_tokens.append({"t": "unit", "id": int(p3["id"]), "army": aid, "w": apos, "scr": scr + (offs[i] as Vector2), "r": r_unit, "kind": p3["kind"],
						"men": int(p3["men"]), "own": true, "label": _short(String(p3["name"])), "sel": sel_units.has(int(p3["id"])), "eng": int(p3["eng"]) != 0,
						"attached": true, "tether": scr})
			else:
				_tokens.append({"t": "army", "id": aid, "army": aid, "w": apos, "scr": scr, "r": r_army, "kind": "army", "men": men, "own": true,
					"label": String(a["name"]) if level == 1 else "", "stack": attached.size(),
					"sel": aid == sel_army and (sel_units.is_empty() or _all_attached_selected(attached)), "eng": _any_engaged(attached)})
		for p4: Dictionary in detached:
			var wp: Vector2 = p4["pos"]
			_tokens.append({"t": "unit", "id": int(p4["id"]), "army": aid, "w": wp, "scr": to_screen(wp), "r": r_unit if level > 0 else 11.0, "mini": level == 0, "kind": p4["kind"],
				"men": int(p4["men"]), "own": true, "label": _short(String(p4["name"])) if level >= 1 else "", "sel": sel_units.has(int(p4["id"])),
				"eng": int(p4["eng"]) != 0, "attached": false})
	for e: Dictionary in enemies:
		var comp: Dictionary = e["comp"]
		var kind := _kind_dominant(comp) if bool(e["exact"]) and not comp.is_empty() else "army"
		var ct := ("%d" % int(e["est_max"])) if bool(e["exact"]) and int(e["age_hours"]) == 0 else "%d-%d" % [int(e["est_min"]), int(e["est_max"])]
		_tokens.append({"t": "enemy", "id": String(e["key"]), "army": int(e["army_id"]), "w": e["pos"], "scr": to_screen(e["pos"] as Vector2), "r": r_army if level > 0 else 18.0,
			"kind": kind, "men": 0, "own": false, "faction": e["faction"], "unknown": not bool(e["exact"]), "count_text": ct, "sel": sel_enemy == String(e["key"]),
			"faded": clampf(float(e["confidence"]) + 0.3, 0.4, 1.0), "label": String(e["label"]) if level >= 1 else "", "radius": float(e["radius"]),
			"live": bool(e["live"])})
	for g: Dictionary in engs:
		if String(g["status"]) == "ended" and int(cm.call("now_hours")) - int(g["end_hour"]) > 24:
			continue
		_tokens.append({"t": "eng", "id": int(g["id"]), "army": 0, "w": g["pos"], "scr": to_screen(g["pos"] as Vector2), "r": 24.0, "kind": "swords", "men": 0, "own": false,
			"sel": sel_eng == int(g["id"]), "status": g["status"], "label": String(g["name"]), "faded": 1.0 if String(g["status"]) != "ended" else 0.55})
	_relax()
	_spread_clashes()
	_tokens.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return _order_key(x) < _order_key(y))


## Pieces in the same engagement are drawn on opposite sides of its marker (us left, them right) so the clash is readable.
func _spread_clashes() -> void:
	if level == 0:
		return
	for g: Dictionary in _tokens:
		if String(g["t"]) != "eng" or String(g["status"]) == "ended":
			continue
		var gw: Vector2 = g["w"]
		var mine: Array = []
		var theirs: Array = []
		for t: Dictionary in _tokens:
			var ts := String(t["t"])
			if ts == "unit" or ts == "army":
				if bool(t.get("eng", false)) and (t["w"] as Vector2).distance_to(gw) < 350.0:
					mine.append(t)
			elif ts == "enemy" and (t["w"] as Vector2).distance_to(gw) < 350.0:
				theirs.append(t)
		var sp := float(mine[0]["r"]) * 2.1 if not mine.is_empty() else 60.0
		g["label_dy"] = -(float(mini(4, maxi(mine.size(), theirs.size()))) * sp * 0.68 + 70.0) if maxi(mine.size(), theirs.size()) > 1 else 52.0
		for side: Array in [[mine, -1.0], [theirs, 1.0]]:
			var lst: Array = side[0]
			for i in lst.size():
				var col := i / 4
				var row := i % 4
				var n_in := mini(4, lst.size() - col * 4)
				(lst[i] as Dictionary)["scr"] = (g["scr"] as Vector2) + Vector2(float(side[1]) * (sp * 0.95 + float(col) * sp * 1.1), (float(row) - float(n_in - 1) * 0.5) * sp * 1.35 + 4.0)
				(lst[i] as Dictionary)["tether"] = g["scr"]


func _order_key(t: Dictionary) -> float:
	var base := {"anchor": 0.0, "army": 1.0, "unit": 1.0, "enemy": 1.0, "eng": 2.0}.get(String(t["t"]), 1.0) as float
	return base * 100000.0 + (500000.0 if bool(t.get("sel", false)) else 0.0) + float((t["scr"] as Vector2).y)


func _short(n: String) -> String:
	return n.replace(" Battalion", "").replace(" Company", "").replace("Infantry", "Inf.").replace("Cavalry", "Cav.").replace("Detachment", "Det.")


func _all_attached_selected(att: Array) -> bool:
	for p: Dictionary in att:
		if not sel_units.has(int(p["id"])):
			return false
	return true


func _any_engaged(att: Array) -> bool:
	for p: Dictionary in att:
		if int(p["eng"]) != 0:
			return true
	return false


## Rows facing up: infantry line, cavalry on the flanks, archers behind, casters and support at the rear, scouts ahead (R§26).
func _fan(units: Array) -> Array:
	var rows := {-1: [], 0: [], 1: [], 2: []}
	var cav: Array = []
	for i in units.size():
		var k := String((units[i] as Dictionary)["kind"])
		if k in ["heavy_cav", "light_cav"]:
			cav.append(i)
		elif k == "scout":
			(rows[-1] as Array).append(i)
		elif k in ["archer"]:
			(rows[1] as Array).append(i)
		elif k in ["mage", "engineer", "medical"]:
			(rows[2] as Array).append(i)
		else:
			(rows[0] as Array).append(i)
	var line: Array = rows[0]
	var flip := false
	for c: int in cav:
		if flip:
			line.push_front(c)
		else:
			line.append(c)
		flip = not flip
	var used: Array = []
	for r: int in [-1, 0, 1, 2]:
		if not (rows[r] as Array).is_empty():
			used.append(r)
	var offs: Array = []
	offs.resize(units.size())
	for ri in used.size():
		var lst: Array = rows[used[ri]]
		# very wide rows wrap onto a second line
		var per := 5
		for j in lst.size():
			var line_i := j / per
			var col_i := j % per
			var n_in := mini(per, lst.size() - line_i * per)
			offs[lst[j]] = Vector2((float(col_i) - float(n_in - 1) * 0.5) * FAN_DX, 70.0 + float(ri) * FAN_DY + float(line_i) * FAN_DY * 0.9)
	return offs


func _relax() -> void:
	if level == 2:
		return
	var idx: Array = []
	for i in _tokens.size():
		if String((_tokens[i] as Dictionary)["t"]) in ["army", "enemy", "unit"] and (level < 2):
			idx.append(i)
	for pass_i in 3:
		for a in idx.size():
			for b in range(a + 1, idx.size()):
				var ta: Dictionary = _tokens[idx[a]]
				var tb: Dictionary = _tokens[idx[b]]
				var d: Vector2 = (tb["scr"] as Vector2) - (ta["scr"] as Vector2)
				var need := (float(ta["r"]) + float(tb["r"])) * 1.15
				if d.length() < need:
					var push := (Vector2(1, 0) if d.length() < 0.5 else d.normalized()) * (need - d.length()) * 0.5
					ta["scr"] = (ta["scr"] as Vector2) - push
					tb["scr"] = (tb["scr"] as Vector2) + push


func token_at(s: Vector2) -> Dictionary:
	for i in range(_tokens.size() - 1, -1, -1):
		var t: Dictionary = _tokens[i]
		var r := float(t["r"])
		var hc := (t["scr"] as Vector2) + Vector2(0, -r * 0.9)
		if hc.distance_to(s) <= r * 1.25 + 8.0:
			return t
	return {}


func tokens() -> Array:
	return _tokens


# ---------------------------------------------------------------- selection ----

func select_units(ids: Array, focus := false) -> void:
	sel_units = ids.duplicate()
	sel_enemy = ""
	sel_eng = -1
	if not ids.is_empty():
		for p: Dictionary in pieces:
			if int(p["id"]) == int(ids[0]):
				sel_army = int(p["army"])
	tab = "units"
	if focus:
		focus_selection()
	_panel.call("rebuild")
	refresh_view()


func select_army(id: int, focus := false) -> void:
	sel_army = id
	sel_units = []
	sel_enemy = ""
	sel_eng = -1
	tab = "units"
	if focus:
		focus_selection()
	_panel.call("rebuild")
	refresh_view()


func select_enemy(key: String, focus := false) -> void:
	sel_enemy = key
	sel_eng = -1
	tab = "intel"
	if focus:
		for e: Dictionary in enemies:
			if String(e["key"]) == key:
				focus_on(e["pos"] as Vector2, maxf(zoom, ZOOM_REGION))
	_panel.call("rebuild")
	refresh_view()


func select_engagement(id: int, focus := false) -> void:
	sel_eng = id
	sel_enemy = ""
	tab = "battles"
	if focus:
		for g: Dictionary in engs:
			if int(g["id"]) == id:
				focus_on(g["pos"] as Vector2, maxf(zoom, ZOOM_LOCAL))
	_panel.call("rebuild")
	refresh_view()


func set_tab(t: String) -> void:
	tab = t
	_panel.call("rebuild")


## "Your part in the war" (scripts/realm/war_influence.gd) for the Life in the tree and this map's realm hub.
func influence() -> RefCounted:
	if _wi == null:
		var life: Node = get_node_or_null("/root/Life")
		var realm: RefCounted = realm_override
		if realm == null and life != null and "realm" in life:
			realm = life.realm
		_wi = WarInfluence.new(life, realm)
	return _wi


## Runs one of the player's war actions, shows its result line on the map and in the log, and redraws.
func do_war_action(id: String, params: Dictionary = {}) -> Dictionary:
	var r: Dictionary = influence().do(id, params)
	var text := String(r.get("text", ""))
	say(text)
	if bool(r.get("ok", false)) and text != "":
		Game.say(text)
	refresh()
	_panel.call("rebuild")
	return r


func selected_pieces() -> Array:
	var out: Array = []
	for p: Dictionary in pieces:
		if sel_units.has(int(p["id"])):
			out.append(p)
	return out


## The units an order will go to: the selected units, or every unit of the selected army.
func order_targets() -> Array:
	if not sel_units.is_empty():
		return sel_units.duplicate()
	var out: Array = []
	for p: Dictionary in pieces:
		if int(p["army"]) == sel_army and not bool(p["detached"]):
			out.append(int(p["id"]))
	return out


# ------------------------------------------------------------------- orders ----

## Orders every target unit to `behavior` at `dest`. Units outside the player's command are not ordered:
## their superior is asked instead (R§13). Returns the results.
func issue(behavior: String, dest: Vector2, target_unit := 0) -> Array:
	if cm == null:
		return []
	var ids := order_targets()
	var out: Array = []
	var sent := 0
	var eta := 0
	var denied_msgs: Array = []
	var n := ids.size()
	for i in n:
		var id := int(ids[i])
		var off := Vector2.ZERO
		if n > 1:
			var a := TAU * float(i) / float(n)
			off = Vector2(cos(a), sin(a)) * (18.0 + 14.0 * sqrt(float(n)))
		var order := {"behavior": behavior}
		var needs := String((WarUnits.behaviour(behavior) as Dictionary)["needs"])
		if needs != "unit" or target_unit == 0:
			order["x"] = dest.x + off.x
			order["y"] = dest.y + off.y
		if target_unit != 0:
			order["target_unit"] = target_unit
		var r: Dictionary = cm.call("order_unit", id, order)
		if bool(r["ok"]):
			sent += 1
			eta = maxi(eta, int((r["courier"] as Dictionary).get("eta_hours", 0)))
		elif bool(r.get("denied", false)):
			var ask: Dictionary = cm.call("request_assistance", id, order)
			denied_msgs.append(String(ask["text"]))
			if bool(ask["ok"]):
				sent += 1
				eta = maxi(eta, int((ask["courier"] as Dictionary).get("eta_hours", 0)))
			r = ask
		out.append(r)
	if n == 0:
		say("Select a unit first.")
	elif not denied_msgs.is_empty():
		say(String(denied_msgs[0]) + ("" if sent == 0 else "  (%d order%s riding, about %d h.)" % [sent, "" if sent == 1 else "s", eta]))
	elif sent > 0:
		say("%d courier%s ride%s out with the order (about %d h)." % [sent, "" if sent == 1 else "s", "s" if sent == 1 else "", eta])
	orders_sent.emit(out)
	refresh()
	return out


func do_split(n: int) -> int:
	if cm == null or sel_units.size() != 1:
		return 0
	var id: int = cm.call("split_unit", int(sel_units[0]), n)
	if id == 0:
		say("That split is not possible (each piece needs at least 5 men).")
	else:
		say("Split off %d men." % n)
		sel_units = [id]
	refresh()
	return id


func do_merge() -> bool:
	if cm == null or sel_units.is_empty():
		return false
	var ids := sel_units.duplicate()
	var a_id := int(ids[0])
	var b_id := 0
	if ids.size() >= 2:
		b_id = int(ids[1])
	else:
		var me: Dictionary = {}
		for p: Dictionary in pieces:
			if int(p["id"]) == a_id:
				me = p
		var best := 1e18
		for p2: Dictionary in pieces:
			if int(p2["id"]) != a_id and int(p2["army"]) == int(me.get("army", -1)) and String(p2["kind"]) == String(me.get("kind", "")):
				var d := (p2["pos"] as Vector2).distance_to(me["pos"] as Vector2)
				if d < best:
					best = d
					b_id = int(p2["id"])
	if b_id == 0:
		say("There is nothing of the same kind to merge with.")
		return false
	var ok: bool = cm.call("merge_units", a_id, b_id)
	say("The formations merge." if ok else "They must be the same kind, close together, and out of combat.")
	if ok:
		sel_units = [a_id]
	refresh()
	return ok


func do_detach() -> void:
	if cm == null or sel_units.size() != 1:
		return
	var id: int = cm.call("detach", int(sel_units[0]))
	say("%s is now an independent piece." % String(cm.call("unit", id).get("name", "The unit")) if id != 0 else "It cannot detach right now.")
	refresh()


func do_attach() -> void:
	if cm == null or sel_units.size() != 1:
		return
	var ok: bool = cm.call("attach", int(sel_units[0]))
	say("It rejoins its army." if ok else "It is too far from its army to rejoin. Bring it back first.")
	refresh()


func do_intervene(action: String) -> void:
	if cm == null or sel_eng < 0:
		return
	var r: Dictionary = cm.call("intervene", sel_eng, action)
	if not bool(r["ok"]):
		say(String(r.get("reason", "Not possible.")))
	else:
		match action:
			"take_command":
				say("You take direct command of the fight.")
			"leave_command":
				say("You leave it to the commander.")
			"press":
				say("You urge them to press the attack.")
			"withdraw":
				say("Withdrawal ordered: %d courier%s riding." % [int(r.get("sent", 0)), "" if int(r.get("sent", 0)) == 1 else "s"])
	refresh()


## Acts on a war-council plan (campaign.follow_advice): the lead army is sent by courier; the plan may prove flawed.
func follow_advice(index: int) -> void:
	if cm == null:
		return
	var r: Dictionary = cm.call("follow_advice", index)
	say("You follow your advisor's plan." if not r.is_empty() and not (r["courier"] as Dictionary).is_empty() else "There is no army to carry out that plan.")
	refresh()


## "Command battle": the engagement's battlefield on the real ground (scripts/ui/war/tactical_view.gd).
func open_tactical(eng_id: int) -> Control:
	if cm == null:
		return null
	var tt: RefCounted = cm.call("tactical_open", eng_id)
	if tt == null:
		say("There is no battle to command there.")
		return null
	var v: Control = load("res://scripts/ui/war/tactical_view.gd").open_modal(self, tt, cm, eng_id, Callable(self, "refresh"))
	return v


## A siege of a stronghold (scripts/ui/war/siege_view.gd).
func open_siege(key: String) -> Control:
	if cm == null:
		return null
	var sg: RefCounted = cm.call("siege", key)
	if sg == null:
		return null
	return load("res://scripts/ui/war/siege_view.gd").open_modal(self, sg, cm, key)


func begin_target_mode() -> void:
	target_mode = true
	say("Tap the map where the selection should go.")


# ------------------------------------------------------------------- radial ----

func open_menu(dest: Vector2, target_unit := 0, screen_pos := Vector2.INF) -> void:
	if cm == null or order_targets().is_empty():
		say("Select a unit first.")
		return
	var ids := order_targets()
	var first := int(ids[0])
	var est: Dictionary = cm.call("estimate_order", first, dest)
	var info := ""
	if not est.is_empty():
		var ground := String(est["terrain"]) if String(est["terrain"]) == String(est["slowest"]) else "%s (slowest on the way: %s)" % [est["terrain"], String(est["slowest"]).to_lower()]
		info = "Distance %.1f km, march about %d h\nGround: %s\nVisibility %s, risk: %s\nCourier about %d h" % [
			float(est["distance"]) / 1000.0, maxi(1, int(ceil(float(est["hours"])))), ground, String(est["visibility"]).to_lower(), String(est["risk"]).to_lower(), int(est["courier_hours"])]
	var can := false
	for id in ids:
		can = can or bool((cm.call("can_command", int(id)) as Dictionary)["ok"])
	if not can:
		info += "\nNot your command: your superior will decide."
	_menu_ctx = {"dest": dest, "target": target_unit}
	var pref := "advance"
	if target_unit != 0:
		pref = "intercept"
	var enabled := func(b: String) -> bool:
		var needs := String((WarUnits.behaviour(b) as Dictionary)["needs"])
		return needs != "unit" or target_unit != 0
	var at := screen_pos if screen_pos != Vector2.INF else to_screen(dest)
	_radial.call("open_at", at, Rect2(Vector2.ZERO, canvas_size()), "%d unit%s" % [ids.size(), "" if ids.size() == 1 else "s"], info, pref, enabled)


func _on_behavior_picked(b: String) -> void:
	issue(b, _menu_ctx.get("dest", center) as Vector2, int(_menu_ctx.get("target", 0)))
	_drag = {}
	target_mode = false
	_overlay.queue_redraw()


func _on_radial_cancelled() -> void:
	_drag = {}
	_overlay.queue_redraw()


func radial_open() -> bool:
	return _radial != null and _radial.visible


# -------------------------------------------------------------------- input ----

func _canvas_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_pointer_down(t.position)
			else:
				_drag = {}
				_moved = TAP_SLOP
		else:
			var single := _touches.size() == 1
			_touches.erase(t.index)
			if single:
				_pointer_up(t.position)
		_canvas.accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if not _touches.has(d.index):
			_touches[d.index] = d.position - d.relative
		var old: Vector2 = _touches[d.index]
		_touches[d.index] = d.position
		if _touches.size() == 1:
			_pointer_move(d.position, d.relative)
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
			center -= ((d.position + o) * 0.5 - (old + o) * 0.5) / zoom
			if d0 > 4.0:
				_zoom_at((d.position + o) * 0.5, d1 / d0)
			else:
				_apply_zoom_change()
		_canvas.accept_event()
	elif e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		if b.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_mouse_down = true
				_pointer_down(b.position)
			elif _mouse_down:
				_mouse_down = false
				_pointer_up(b.position)
			_canvas.accept_event()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(b.position, 1.2)
			_canvas.accept_event()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(b.position, 1.0 / 1.2)
			_canvas.accept_event()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if _mouse_down:
			_pointer_move(mm.position, mm.relative)
			_canvas.accept_event()
	elif e is InputEventMagnifyGesture:
		_zoom_at((e as InputEventMagnifyGesture).position, (e as InputEventMagnifyGesture).factor)
		_canvas.accept_event()


func _pointer_down(pos: Vector2) -> void:
	_press_pos = pos
	_moved = 0.0
	_press_hit = token_at(pos)
	_drag = {}


func _pointer_move(pos: Vector2, rel: Vector2) -> void:
	_moved += rel.length()
	if _moved < TAP_SLOP:
		return
	if _drag.is_empty() and not _press_hit.is_empty() and bool(_press_hit.get("own", false)) and String(_press_hit["t"]) in ["unit", "army", "anchor"]:
		_begin_drag(_press_hit)
	if not _drag.is_empty():
		_drag["to"] = pos
		_overlay.queue_redraw()
	else:
		center -= rel / zoom
		_clamp_center()
		refresh_view()
		_field_timer.start()


func _begin_drag(t: Dictionary) -> void:
	# dragging a token selects it (its whole army if it is an army banner) and starts an order drag
	match String(t["t"]):
		"unit":
			if not sel_units.has(int(t["id"])):
				select_units([int(t["id"])])
		_:
			select_army(int(t["army"]))
	_drag = {"from": t["scr"], "to": t["scr"], "active": true}


func _pointer_up(pos: Vector2) -> void:
	if not _drag.is_empty():
		var dest := to_world(pos)
		var moved_px := (pos - (_drag["from"] as Vector2)).length()
		_drag["to"] = pos
		if moved_px > 30.0:
			var hit := token_at(pos)
			var target := 0
			if not hit.is_empty() and String(hit["t"]) == "unit" and not order_targets().has(int(hit["id"])):
				target = int(hit["id"])
			elif not hit.is_empty() and String(hit["t"]) == "enemy":
				target = _enemy_unit_id(hit)
			open_menu(dest, target, pos)
		else:
			_drag = {}
		_overlay.queue_redraw()
		return
	if _moved < TAP_SLOP:
		_tap(pos)
	else:
		_field_timer.start()


func _enemy_unit_id(t: Dictionary) -> int:
	for e: Dictionary in enemies:
		if String(e["key"]) == String(t["id"]):
			return int(e["unit_id"])
	return 0


func _tap(pos: Vector2) -> void:
	var hit := token_at(pos)
	if target_mode and order_targets().size() > 0 and (hit.is_empty() or String(hit["t"]) in ["enemy"]):
		var tu := _enemy_unit_id(hit) if not hit.is_empty() else 0
		target_mode = false
		open_menu(to_world(pos), tu, pos)
		return
	if hit.is_empty():
		sel_units = []
		sel_enemy = ""
		sel_eng = -1
		_panel.call("rebuild")
		refresh_view()
		return
	match String(hit["t"]):
		"unit":
			select_units([int(hit["id"])])
		"army", "anchor":
			select_army(int(hit["army"]))
		"enemy":
			select_enemy(String(hit["id"]))
		"eng":
			select_engagement(int(hit["id"]))


# ------------------------------------------------------------------- drawing ----

class LandLayer extends Control:
	var map: Control
	var field: Object = null
	var mat_for: Object = null

	func _draw() -> void:
		if map == null or field == null or not bool(field.get("ready")):
			return
		var r: Rect2 = field.get("rect")
		var a: Vector2 = map.call("to_screen", r.position)
		var b: Vector2 = map.call("to_screen", r.end)
		draw_texture_rect(field.get("tex"), Rect2(a, b - a), false)


class OverlayLayer extends Control:
	var map: Control

	func _draw() -> void:
		if map != null:
			map.call("_draw_overlay", self)


func _palette() -> Dictionary:
	match style:
		Tokens.REALISTIC:
			return {"river": Color("6e8f99"), "road": Color("efe1b8"), "road_case": Color(0.25, 0.2, 0.12, 0.8), "label": Color("2b2115"), "label_out": Color(0.95, 0.9, 0.75, 0.8),
				"town": Color("3b2c1a"), "fog": Color(0.3, 0.26, 0.2, 0.34), "line": Color("34506e")}
		Tokens.TACTICAL:
			return {"river": Color("2f6c9a"), "road": Color("e6dcc0"), "road_case": Color(0, 0, 0, 0.55), "label": Color("e8e4d8"), "label_out": Color(0, 0, 0, 0.85),
				"town": Color("e8e4d8"), "fog": Color(0.02, 0.04, 0.07, 0.5), "line": Color("8fc0ff")}
		_:
			return {"river": Color("7fa3a0"), "road": Color("f4e6bd"), "road_case": Color(0.3, 0.2, 0.08, 0.8), "label": Color("3a2611"), "label_out": Color(0.96, 0.9, 0.72, 0.85),
				"town": Color("4a3016"), "fog": Color(0.24, 0.16, 0.08, 0.36), "line": Color("6a4a20")}


func _draw_overlay(ci: Control) -> void:
	if _canvas == null:
		return
	var pal := _palette()
	var cs := canvas_size()
	if cm == null:
		_draw_frame(ci, cs)
		return
	_draw_rivers(ci, pal)
	_draw_roads(ci, pal)
	_draw_fog(ci, pal)
	_draw_settlements(ci, pal)
	if style == Tokens.TACTICAL:
		_draw_supply(ci)
	_draw_orders(ci, pal)
	_draw_enemy_rings(ci)
	for t: Dictionary in _tokens:
		_draw_token(ci, t)
	_draw_drag(ci, pal)
	if legend_open:
		_draw_legend(ci, pal)
	_draw_scale(ci, pal, cs)
	_draw_frame(ci, cs)


func _draw_rivers(ci: Control, pal: Dictionary) -> void:
	var w := clampf(zoom * 7.0, 1.6, 11.0)
	var view := Rect2(Vector2.ZERO, canvas_size()).grow(60)
	for r: Dictionary in WorldGen.rivers:
		var pts: PackedVector2Array = r["points"]
		var widths: PackedFloat32Array = r["width"]
		var out := PackedVector2Array()
		var lo := 0
		for i in pts.size():
			var s := to_screen(pts[i])
			if view.has_point(s):
				out.append(s)
			elif out.size() > 1:
				ci.draw_polyline(out, pal["river"], w * (0.8 + minf(widths[i] / 8.0, 1.2)), true)
				out = PackedVector2Array()
			else:
				out = PackedVector2Array()
			lo += 1
		if out.size() > 1:
			ci.draw_polyline(out, pal["river"], w * (0.8 + minf(widths[widths.size() - 1] / 8.0, 1.2)), true)


func _draw_roads(ci: Control, pal: Dictionary) -> void:
	var w := clampf(zoom * 14.0, 2.2, 7.0)
	var view := Rect2(Vector2.ZERO, canvas_size()).grow(80)
	for rd: Array in _roads:
		var a := to_screen(rd[0] as Vector2)
		var b := to_screen(rd[1] as Vector2)
		if not (view.has_point(a) or view.has_point(b) or view.has_point((a + b) * 0.5)):
			continue
		ci.draw_line(a, b, pal["road_case"], w + 2.0, true)
	for rd2: Array in _roads:
		var a2 := to_screen(rd2[0] as Vector2)
		var b2 := to_screen(rd2[1] as Vector2)
		if not (view.has_point(a2) or view.has_point(b2) or view.has_point((a2 + b2) * 0.5)):
			continue
		if style == Tokens.TABLE:
			Tokens.dashed(ci, a2, b2, pal["road"], w * 0.8, 10.0, 5.0)
		else:
			ci.draw_line(a2, b2, pal["road"], w, true)


func _draw_fog(ci: Control, pal: Dictionary) -> void:
	if cm == null:
		return
	if _fog_tex == null or _fog_sig != "%s" % [cm.call("now_hours") / 6]:
		_build_fog(pal)
	var half := WorldGen.WORLD_HALF
	var a := to_screen(Vector2(-half, -half))
	var b := to_screen(Vector2(half, half))
	if _fog_tex != null:
		ci.draw_texture_rect(_fog_tex, Rect2(a, b - a), false)


func _build_fog(pal: Dictionary) -> void:
	var n := 128
	var cell := WorldGen.WORLD_HALF * 2.0 / float(n)
	var base: Color = pal["fog"]
	var alpha := PackedByteArray()
	alpha.resize(n * n)
	alpha.fill(int(base.a * 255.0))
	var areas: Array = cm.call("known_areas")
	for ar: Dictionary in areas:
		var p: Vector2 = ar["pos"]
		var r := float(ar["radius"])
		var soft := r * 1.35
		var x0 := maxi(0, int((p.x - soft + WorldGen.WORLD_HALF) / cell))
		var x1 := mini(n - 1, int((p.x + soft + WorldGen.WORLD_HALF) / cell))
		var y0 := maxi(0, int((p.y - soft + WorldGen.WORLD_HALF) / cell))
		var y1 := mini(n - 1, int((p.y + soft + WorldGen.WORLD_HALF) / cell))
		var stale := clampf(float(ar["age_days"]) / 30.0, 0.0, 0.55)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var c := Vector2((float(x) + 0.5) * cell - WorldGen.WORLD_HALF, (float(y) + 0.5) * cell - WorldGen.WORLD_HALF)
				var d := c.distance_to(p)
				if d < soft:
					var k := 0.0 if d < r * 0.75 else (d - r * 0.75) / (soft - r * 0.75)
					var want := int(base.a * 255.0 * maxf(k, stale))
					alpha[y * n + x] = mini(int(alpha[y * n + x]), want)
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for i in n * n:
		data[i * 4] = int(base.r * 255.0)
		data[i * 4 + 1] = int(base.g * 255.0)
		data[i * 4 + 2] = int(base.b * 255.0)
		data[i * 4 + 3] = alpha[i]
	_fog_tex = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data))
	_fog_sig = "%s" % [cm.call("now_hours") / 6]


func _draw_settlements(ci: Control, pal: Dictionary) -> void:
	var view := Rect2(Vector2.ZERO, canvas_size()).grow(40)
	var fs := [15, 18, 20][level] as int
	var ink: Color = pal["town"]
	var owner_map: Dictionary = cm.call("captured") if cm != null else {}
	for i in WorldGen.settlements.size():
		var s: Dictionary = WorldGen.settlements[i]
		var p := to_screen(s["pos"] as Vector2)
		if not view.has_point(p):
			continue
		var kind := String(s["kind"])
		var sz := (11.0 if kind in ["town", "castle", "capital"] else 8.0) * (1.0 if level > 0 else 0.8)
		match kind:
			"castle":
				ci.draw_rect(Rect2(p - Vector2(sz, sz), Vector2(sz * 2, sz * 2)), ink)
				for k in 3:
					ci.draw_rect(Rect2(p + Vector2(-sz + float(k) * sz * 0.85, -sz - 5), Vector2(sz * 0.55, 6)), ink)
			"town", "capital":
				ci.draw_rect(Rect2(p - Vector2(sz, sz) * 0.85, Vector2(sz, sz) * 1.7), ink)
				ci.draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(pal["road"], 0.9))
			"frontier_town":
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz), p + Vector2(sz, sz * 0.8), p + Vector2(-sz, sz * 0.8)]), ink)
			_:
				ci.draw_circle(p, sz * 0.7, ink)
				ci.draw_circle(p, sz * 0.32, Color(pal["road"], 0.95))
		if owner_map.has(str(i)):
			var col := Tokens.faction_color(String(owner_map[str(i)]))
			ci.draw_line(p + Vector2(0, -sz), p + Vector2(0, -sz - 26), ink, 2.0)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz - 26), p + Vector2(18, -sz - 20), p + Vector2(0, -sz - 13)]), col)
		if level == 0 and kind not in ["town", "castle", "capital", "frontier_town"]:
			continue
		Tokens.text_centered(ci, _title_font, String(s["name"]), p + Vector2(0, sz + fs + 3), fs, pal["label"], pal["label_out"], 4)


func _draw_supply(ci: Control) -> void:
	for ln: Array in cm.call("supply_routes"):
		var a := to_screen(ln[0] as Vector2)
		var b := to_screen(ln[1] as Vector2)
		if a.distance_to(b) > 4.0:
			Tokens.dashed(ci, a, b, Color("e0b060", 0.75), 2.0, 4.0, 6.0)
			ci.draw_circle(b, 6.0, Color("e0b060", 0.9))


func _piece_pos(id: int) -> Vector2:
	for t: Dictionary in _tokens:
		if String(t["t"]) == "unit" and int(t["id"]) == id:
			return t["scr"] as Vector2
	return Vector2.INF


func _draw_orders(ci: Control, pal: Dictionary) -> void:
	# executing orders: from the piece to where it is going
	for p: Dictionary in pieces:
		var o: Dictionary = p["order"]
		var bn := String(o.get("behavior", "hold"))
		if not bool(p["detached"]) or not o.has("x") or not (WarUnits.behaviour(bn) as Dictionary)["moves"]:
			continue
		var from := _piece_pos(int(p["id"]))
		if from == Vector2.INF:
			continue
		var to := to_screen(Vector2(float(o["x"]), float(o["y"])))
		var col: Color = ORDER_COL.get(bn, Color.WHITE)
		Tokens.dashed(ci, from + Vector2(0, -8), to, Color(col, 0.9), 3.0, 12.0, 8.0)
		Tokens.arrow_head(ci, to, to - from, col, 13.0)
	# army routes along roads
	for aid: int in armies:
		var a: Dictionary = armies[aid]
		var route: Array = a.get("route", [])
		if route.is_empty():
			continue
		var pts: Array = [to_screen(a["pos"] as Vector2)]
		for n in route:
			pts.append(to_screen(cm.call("node_pos", int(n)) as Vector2))
		for i in range(1, pts.size()):
			Tokens.dashed(ci, pts[i - 1] as Vector2, pts[i] as Vector2, Color(ORDER_COL["advance"], 0.85), 3.0, 12.0, 8.0)
		Tokens.arrow_head(ci, pts[-1] as Vector2, (pts[-1] as Vector2) - (pts[-2] as Vector2), ORDER_COL["advance"], 13.0)
	# orders still on the road: faint dotted line to where they will send the piece
	for od: Dictionary in orders:
		if String(od["state"]) not in ["riding", "awaiting"] or not (od["pos"] as Vector2).is_finite():
			continue
		var from2 := _piece_pos(int(od["unit_id"]))
		if from2 == Vector2.INF:
			continue
		var to2 := to_screen(od["pos"] as Vector2)
		Tokens.dashed(ci, from2, to2, Color(1, 1, 1, 0.4), 2.0, 3.0, 7.0)
		ci.draw_circle(to2, 7.0, Color(1, 1, 1, 0.55))
		if level >= 1:
			Tokens.text_centered(ci, _font, "courier %d h" % int(od["eta_left"]), to2 + Vector2(0, 26), 15, Color("f0e0b0"), Color(0, 0, 0, 0.85), 4)
	# vision cone of the selected piece (tactical)
	if style == Tokens.TACTICAL and sel_units.size() == 1:
		for p2: Dictionary in pieces:
			if int(p2["id"]) == int(sel_units[0]):
				var vr := float((WarUnits.kind(String(p2["kind"])) as Dictionary)["vision"]) * zoom
				var c := _piece_pos(int(p2["id"]))
				if c != Vector2.INF and vr > 10.0:
					ci.draw_circle(c, vr, Color(0.55, 0.8, 1.0, 0.07))
					ci.draw_arc(c, vr, 0, TAU, 48, Color(0.55, 0.8, 1.0, 0.45), 1.5, true)
					var o2: Dictionary = p2["order"]
					if o2.has("x"):
						var dir := (to_screen(Vector2(float(o2["x"]), float(o2["y"]))) - c).normalized()
						var pts2 := PackedVector2Array([c])
						for k in 9:
							var ang := dir.angle() - 0.6 + 1.2 * float(k) / 8.0
							pts2.append(c + Vector2(cos(ang), sin(ang)) * vr)
						ci.draw_colored_polygon(pts2, Color(0.55, 0.8, 1.0, 0.1))


func _draw_enemy_rings(ci: Control) -> void:
	for t: Dictionary in _tokens:
		if String(t["t"]) != "enemy":
			continue
		var r := float(t["radius"]) * zoom
		if r > 14.0:
			var col := Tokens.faction_color(String(t["faction"]))
			ci.draw_arc(t["scr"], minf(r, 900.0), 0, TAU, 56, Color(col, 0.5), 2.0, true)
			ci.draw_circle(t["scr"], minf(r, 900.0), Color(col, 0.07))


func _draw_token(ci: Control, t: Dictionary) -> void:
	var s: Vector2 = t["scr"]
	var view := Rect2(Vector2.ZERO, canvas_size()).grow(80)
	if not view.has_point(s):
		return
	match String(t["t"]):
		"eng":
			var col: Color = STATUS_COL.get(String(t["status"]), Color.WHITE)
			var a := float(t["faded"])
			ci.draw_circle(s, 30.0, Color(col, 0.22 * a))
			ci.draw_arc(s, 30.0, 0, TAU, 32, Color(col, a), 3.0 if not bool(t["sel"]) else 5.0, true)
			Tokens.glyph(ci, "swords", s, 13.0, Color(1, 1, 1, a), 3.0)
			if level >= 1:
				var ldy := float(t.get("label_dy", 52.0))
				Tokens.text_centered(ci, _font, String(t["label"]), s + Vector2(0, ldy), 17, Color("ffe6b0", a), Color(0, 0, 0, 0.9), 5)
				Tokens.text_centered(ci, _font, String(t["status"]).capitalize(), s + Vector2(0, ldy + 18.0), 15, Color(col, a), Color(0, 0, 0, 0.9), 4)
		"anchor":
			if bool(t["sel"]):
				ci.draw_arc(s, 24.0, 0, TAU, 24, Tokens.GOLD, 3.0, true)
			Tokens.glyph(ci, "army", s + Vector2(0, -12), 14.0, Tokens.faction_color("player").lightened(0.25), 3.0)
			ci.draw_circle(s, 4.0, Tokens.faction_color("player"))
			Tokens.text_centered(ci, _title_font, String(t["label"]), s + Vector2(0, -36), 16, Color("ffffff") if style != Tokens.REALISTIC else Color("2b2115"),
				Color(0, 0, 0, 0.85) if style != Tokens.REALISTIC else Color(0.95, 0.9, 0.75, 0.8), 4)
		_:
			if bool(t.get("mini", false)):
				var mc: Color = Tokens.faction_color("player")
				ci.draw_circle(s + Vector2(0, -6), 9.0, Color(1, 1, 1, 0.9))
				ci.draw_circle(s + Vector2(0, -6), 7.0, Color(mc, 1.0) if not bool(t["sel"]) else Tokens.GOLD)
				return
			if t.has("tether") and (level == 2 or t.get("eng", false)):
				Tokens.dashed(ci, t["tether"], s, Color(1, 1, 1, 0.28), 1.5, 3.0, 5.0)
			var col2 := Tokens.faction_color("player") if bool(t["own"]) else Tokens.faction_color(String(t.get("faction", "enemy")))
			var opts := {"selected": bool(t["sel"]), "font": _font, "men": int(t["men"]), "faded": float(t.get("faded", 1.0)), "label": String(t.get("label", "")),
				"stack": int(t.get("stack", 0)), "unknown": bool(t.get("unknown", false)), "engaged": bool(t.get("eng", false))}
			if t.has("count_text"):
				opts["count_text"] = String(t["count_text"])
			elif String(t["t"]) == "army":
				opts["count_text"] = _thousands(int(t["men"]))
			Tokens.piece(ci, style, s, float(t["r"]), col2, String(t["kind"]), opts)


func _thousands(n: int) -> String:
	var s := str(n)
	return s if n < 1000 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]


func _draw_drag(ci: Control, pal: Dictionary) -> void:
	if _drag.is_empty():
		return
	var from: Vector2 = _drag["from"]
	var to: Vector2 = _drag["to"]
	Tokens.dashed(ci, from + Vector2(0, -10), to, Color(1, 1, 1, 0.95), 4.0, 14.0, 8.0)
	Tokens.arrow_head(ci, to, to - from, Color(1, 1, 1, 0.95), 16.0)
	ci.draw_circle(to, 18.0, Color(1, 1, 1, 0.22))
	ci.draw_arc(to, 18.0, 0, TAU, 28, Color(1, 1, 1, 0.9), 3.0, true)


func _draw_legend(ci: Control, pal: Dictionary) -> void:
	var rows := [["Your forces (exact)", "own"], ["Enemy: last sighting, estimate only", "enemy"], ["Engagement", "eng"], ["Order being carried out", "order"],
		["Order still with the courier", "courier"], ["Scouted ground", "seen"], ["Unknown ground", "fog"], ["Supply line", "supply"]]
	var x := 12.0
	var y := 150.0
	var w := 290.0
	var h := 24.0 + float(rows.size()) * 30.0
	ci.draw_rect(Rect2(x, y, w, h), Color(0.03, 0.028, 0.025, 0.9))
	ci.draw_rect(Rect2(x, y, w, h), AF.GOLD_DIM, false, 1.5)
	var f := _font
	for i in rows.size():
		var ry := y + 26.0 + float(i) * 30.0
		var c := Vector2(x + 26.0, ry)
		match String((rows[i] as Array)[1]):
			"own":
				ci.draw_rect(Rect2(c - Vector2(11, 8), Vector2(22, 16)), Tokens.faction_color("player"))
				ci.draw_rect(Rect2(c - Vector2(11, 8), Vector2(22, 16)), Color.WHITE, false, 1.5)
			"enemy":
				ci.draw_rect(Rect2(c - Vector2(11, 8), Vector2(22, 16)), Color(Tokens.RED, 0.6))
				ci.draw_arc(c, 13.0, 0, TAU, 20, Color(Tokens.RED, 0.7), 1.5, true)
			"eng":
				Tokens.glyph(ci, "swords", c, 9.0, Color("ff6a4a"), 2.4)
			"order":
				Tokens.dashed(ci, c - Vector2(14, 0), c + Vector2(12, 0), ORDER_COL["advance"], 3.0, 6.0, 4.0)
			"courier":
				Tokens.dashed(ci, c - Vector2(14, 0), c + Vector2(12, 0), Color(1, 1, 1, 0.6), 2.0, 3.0, 5.0)
			"seen":
				ci.draw_rect(Rect2(c - Vector2(12, 8), Vector2(24, 16)), Color(1, 1, 1, 0.12))
			"fog":
				ci.draw_rect(Rect2(c - Vector2(12, 8), Vector2(24, 16)), Color(pal["fog"], 0.9))
			"supply":
				Tokens.dashed(ci, c - Vector2(14, 0), c + Vector2(12, 0), Color("e0b060"), 2.0, 4.0, 5.0)
		ci.draw_string(f, Vector2(x + 50.0, ry + 6.0), String((rows[i] as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 58.0, 16, AF.TEXT)


func _draw_scale(ci: Control, pal: Dictionary, cs: Vector2) -> void:
	var metres := 500.0
	for m in [100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		if float(m) * zoom >= 90.0:
			metres = float(m)
			break
	var len_px := metres * zoom
	var y := cs.y - 82.0
	var x := 14.0
	var col: Color = pal["label"]
	var out: Color = pal["label_out"]
	ci.draw_line(Vector2(x, y), Vector2(x + len_px, y), out, 6.0)
	ci.draw_line(Vector2(x, y), Vector2(x + len_px, y), col, 3.0)
	ci.draw_line(Vector2(x, y - 6), Vector2(x, y + 6), col, 3.0)
	ci.draw_line(Vector2(x + len_px, y - 6), Vector2(x + len_px, y + 6), col, 3.0)
	ci.draw_string_outline(_font, Vector2(x + 4, y - 10), "%s" % ("%d m" % int(metres) if metres < 1000.0 else "%d km" % int(metres / 1000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, out)
	ci.draw_string(_font, Vector2(x + 4, y - 10), "%s" % ("%d m" % int(metres) if metres < 1000.0 else "%d km" % int(metres / 1000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


func _draw_frame(ci: Control, cs: Vector2) -> void:
	match style:
		Tokens.TABLE:
			var wood := Color("5a3b20")
			var edge := Color("2f1d0e")
			ci.draw_rect(Rect2(0, 0, cs.x, 14), wood)
			ci.draw_rect(Rect2(0, cs.y - 14, cs.x, 14), wood)
			ci.draw_rect(Rect2(0, 0, 14, cs.y), wood)
			ci.draw_rect(Rect2(cs.x - 14, 0, 14, cs.y), wood)
			ci.draw_rect(Rect2(14, 14, cs.x - 28, cs.y - 28), edge, false, 3.0)
			for k in 12:
				var y := 3.0 + float(k) * 1.1
				ci.draw_line(Vector2(0, y), Vector2(cs.x, y), Color(0, 0, 0, 0.12), 1.0)
			for c: Vector2 in [Vector2(7, 7), Vector2(cs.x - 7, 7), Vector2(7, cs.y - 7), Vector2(cs.x - 7, cs.y - 7)]:
				ci.draw_circle(c, 5.0, Color("b08a4a"))
		Tokens.TACTICAL:
			ci.draw_rect(Rect2(0, 0, cs.x, cs.y), Color(0.55, 0.75, 1.0, 0.22), false, 3.0)
		_:
			ci.draw_rect(Rect2(2, 2, cs.x - 4, cs.y - 4), Color(0.25, 0.2, 0.12, 0.6), false, 3.0)
