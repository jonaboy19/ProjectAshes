extends Control
## Strategic map: one real-terrain map (war_terrain.gd, the same three styles as the War Map) with
## toggleable role layers: Political, Trade, Resources, Military, Diplomacy, Danger. Tap a settlement
## for an info card whose actions depend on who you are (merchant, lord, soldier, commoner).
## Reads the enterprise module (and the realm modules through it); the only things it changes are
## the actions the player presses. Nothing runs per frame: a redraw happens on data change, on input
## and on a 1 s timer; terrain bakes a few rows per frame only while a new field is being sampled.

signal closed
signal action_requested(action: String, sid: int)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Tokens := preload("res://scripts/ui/war/war_tokens.gd")
const Terrain := preload("res://scripts/ui/war/war_terrain.gd")
const D := preload("res://scripts/realm/enterprise_data.gd")

const LAYERS := [["political", "Political"], ["trade", "Trade"], ["resources", "Resources"], ["military", "Military"], ["diplomacy", "Diplomacy"], ["danger", "Danger"]]
const PANEL_W := 420.0
const TAP_SLOP := 12.0
const MAX_ZOOM := 1.6
const STANCE_COL := {"allied": Color("7fd18b"), "friendly": Color("b3d98a"), "neutral": Color("ece3cf"), "wary": Color("e0b45a"), "hostile": Color("e0685a"), "war": Color("e0433a")}
const TIE_COL := {"kin": Color("7fd18b"), "rivalry": Color("e0685a"), "debt": Color("e0b45a"), "alliance": Color("6fa8ff"), "vassalage": Color("b59cff")}
const DIR_VEC := {"east": Vector2(1, 0), "west": Vector2(-1, 0), "north": Vector2(0, -1), "south": Vector2(0, 1)}

## Tests / other hosts may inject a realm hub; otherwise Life.realm is used.
var realm_override: RefCounted = null
var embedded := false
var style := Tokens.TACTICAL
var layers := {"political": true, "trade": false, "resources": false, "military": false, "diplomacy": false, "danger": false}
var good := "tools"
var sel := -1
var sel_car := -1
var center := Vector2.ZERO
var zoom := 0.1
var plan_stops: Array = []               # route-planner preview (settlement ids)
var status_text := ""

var _canvas: Control
var _land: Control
var _overlay: Control
var _panel: PanelContainer
var _card: VBoxContainer
var _card_scroll: ScrollContainer
var _row: BoxContainer
var _bar: HFlowContainer
var _goods_bar: HFlowContainer
var _hdr: Label
var _toast: Label
var _layer_btns: Dictionary = {}
var _style_btn: Button
var _terrain := Terrain.new()
var _field: Object = null
var _font: Font
var _title_font: Font
var _timer: Timer
var _built := false
var _touches: Dictionary = {}
var _press := Vector2.ZERO
var _moved := 0.0
var _mouse_down := false
var _data: Dictionary = {}
var _pol_tex: ImageTexture = null
var _pol_sig := ""
var _anchors: Dictionary = {}
var _screen: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = AF.font(AF.BODY_FONT)
	_title_font = AF.title_font(700)
	_build_ui()
	refresh()
	fit_start()


static func open_modal(host: Node, realm: RefCounted = null) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 71
	layer.name = "StrategicMapLayer"
	var m: Control = load("res://scripts/ui/strategic/strategic_map.gd").new()
	m.set("realm_override", realm)
	layer.add_child(m)
	m.closed.connect(layer.queue_free)
	host.add_child(layer)
	return m


func realm() -> RefCounted:
	if realm_override != null:
		return realm_override
	var life: Node = get_node_or_null("/root/Life")
	if life != null and "realm" in life:
		return life.realm
	return null


func ent() -> RefCounted:
	var r := realm()
	return r.call("mod", "enterprise") if r != null else null


func _mod(n: String) -> RefCounted:
	var r := realm()
	return r.call("mod", n) if r != null else null


# ------------------------------------------------------------------ build ----

func _build_ui() -> void:
	if _built:
		return
	_built = true
	_row = BoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_on_canvas_resized)
	_row.add_child(_canvas)
	_land = LandLayer.new()
	_overlay = OverlayLayer.new()
	for l: Control in [_land, _overlay]:
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set("map", self)
		_canvas.add_child(l)
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 6)
	_bar.add_theme_constant_override("v_separation", 6)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 10
	_bar.offset_right = -10
	_bar.offset_top = 10
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_bar)
	_goods_bar = HFlowContainer.new()
	_goods_bar.add_theme_constant_override("h_separation", 4)
	_goods_bar.add_theme_constant_override("v_separation", 4)
	_goods_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_goods_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_goods_bar.offset_left = 10
	_goods_bar.offset_right = -70
	_goods_bar.offset_bottom = -10
	_goods_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_canvas.add_child(_goods_bar)
	_toast = Kit.lbl("", 18, AF.GOLD_BRIGHT, true, "italic")
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 120
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_canvas.add_child(_toast)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 1.0), AF.GOLD_DIM, 0, 12))
	_row.add_child(_panel)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_card_scroll)
	_card = VBoxContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_theme_constant_override("separation", 8)
	_card_scroll.add_child(_card)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_timer.start()
	_build_bar()
	_relayout()


func _chip(text: String, on: bool, cb: Callable, w := 0.0) -> Button:
	var b := Kit.tab_button(text, on, cb, w)
	b.custom_minimum_size.y = 44
	return b


func _build_bar() -> void:
	Kit.clear(_bar)
	_layer_btns.clear()
	var x := Kit.button("Close", false, 44, 15)
	x.pressed.connect(close)
	_bar.add_child(x)
	for l: Array in LAYERS:
		var id := String(l[0])
		var b := _chip(String(l[1]), bool(layers[id]), toggle_layer.bind(id), 0.0)
		_layer_btns[id] = b
		_bar.add_child(b)
	_style_btn = _chip("Style: %s" % Tokens.STYLE_NAMES[style], false, cycle_style)
	_bar.add_child(_style_btn)
	_hdr = Kit.lbl("", 15, AF.GOLD_BRIGHT)
	_hdr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.86), AF.GOLD_DIM, 3, 7))
	hp.add_child(_hdr)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(hp)
	_build_goods_bar()


func _build_goods_bar() -> void:
	Kit.clear(_goods_bar)
	_goods_bar.visible = bool(layers["trade"])
	if not _goods_bar.visible:
		return
	for g: String in D.GOOD_ORDER:
		var b := _chip(String((D.GOODS[g] as Dictionary)["name"]), g == good, set_good.bind(g))
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 13)
		_goods_bar.add_child(b)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built and _row != null:
		_relayout()


func _relayout() -> void:
	var portrait := size.x < size.y * 0.95
	_row.vertical = portrait
	_panel.custom_minimum_size = Vector2(0, size.y * 0.42) if portrait else Vector2(PANEL_W, 0)


func _on_canvas_resized() -> void:
	if _built:
		queue_redraw_all()


func canvas_size() -> Vector2:
	return _canvas.size if _canvas != null and _canvas.size.x > 8.0 else Vector2(860, 720)


func to_screen(w: Vector2) -> Vector2:
	return (w - center) * zoom + canvas_size() * 0.5


func to_world(s: Vector2) -> Vector2:
	return (s - canvas_size() * 0.5) / zoom + center


func _min_zoom() -> float:
	var cs := canvas_size()
	return minf(cs.x, cs.y) / (WorldGen.WORLD_HALF * 2.0) * 0.85


func fit_start() -> void:
	# frame the settled part of the world rather than the whole empty square
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s: Dictionary in WorldGen.settlements:
		var p: Vector2 = s["pos"]
		if p.length() > 3400.0:
			continue
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if lo.x == INF:
		lo = Vector2(-2000, -2000)
		hi = Vector2(2000, 2000)
	center = (lo + hi) * 0.5
	var span := (hi - lo) + Vector2(900, 900)
	var cs := canvas_size()
	zoom = clampf(minf(cs.x / span.x, cs.y / span.y), _min_zoom(), MAX_ZOOM)
	_update_fields()
	queue_redraw_all()


func zoom_in() -> void:
	_zoom_at(canvas_size() * 0.5, 1.3)


func zoom_out() -> void:
	_zoom_at(canvas_size() * 0.5, 1.0 / 1.3)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := to_world(screen_pos)
	zoom = clampf(zoom * factor, _min_zoom(), MAX_ZOOM)
	center += before - to_world(screen_pos)
	_clamp_center()
	queue_redraw_all()


func _clamp_center() -> void:
	var h := WorldGen.WORLD_HALF
	center = Vector2(clampf(center.x, -h, h), clampf(center.y, -h, h))


func focus_on(pos: Vector2) -> void:
	center = pos
	_clamp_center()
	queue_redraw_all()


# ------------------------------------------------------------- settings ----

func toggle_layer(id: String) -> void:
	layers[id] = not bool(layers[id])
	if _layer_btns.has(id):
		_build_bar()
	_build_goods_bar()
	refresh()


func set_layers(on: Array) -> void:
	for l: Array in LAYERS:
		layers[String(l[0])] = on.has(String(l[0]))
	_build_bar()
	refresh()


func set_good(g: String) -> void:
	good = g
	_build_goods_bar()
	refresh()


func cycle_style() -> void:
	set_style((style + 1) % 3)


func set_style(s: int) -> void:
	style = s
	if _style_btn != null:
		_style_btn.text = "Style: %s" % Tokens.STYLE_NAMES[style]
	_land.set("mat_for", null)
	_pol_sig = ""
	_sync_material()
	queue_redraw_all()


func close() -> void:
	closed.emit()


func _say(text: String) -> void:
	status_text = text
	_toast.text = text
	if text != "":
		var t := get_tree().create_timer(6.0)
		t.timeout.connect(func() -> void:
			if is_instance_valid(_toast) and _toast.text == text:
				_toast.text = "")


# -------------------------------------------------------------------- data ----

func queue_redraw_all() -> void:
	if _land != null:
		_land.queue_redraw()
		_overlay.queue_redraw()


func _on_timer() -> void:
	if not visible:
		return
	var e := ent()
	if e != null and not (e.get("caravans") as Dictionary).is_empty():
		refresh()


## Re-reads every module the active layers need. Cheap; redraws once.
func refresh() -> void:
	var e := ent()
	if e == null:
		_data = {}
		queue_redraw_all()
		return
	var d := {"roads": e.call("road_list"), "caravans": e.call("list_caravans"), "rifts": _dedupe(e.call("rift_positions"))}
	var sids: Array = []
	for s: Dictionary in WorldGen.settlements:
		sids.append(int(s["id"]))
	d["sids"] = sids
	var pol := {}
	for sid: int in sids:
		pol[sid] = e.call("political_of", sid)
	d["pol"] = pol
	if bool(layers["trade"]):
		var prices := {}
		for sid: int in sids:
			prices[sid] = e.call("known_price", sid, good)
		d["prices"] = prices
	if bool(layers["resources"]):
		var res := {}
		for sid: int in sids:
			res[sid] = e.call("resources_of", sid)
		d["res"] = res
	var sh := _mod("strongholds")
	if sh != null and (bool(layers["military"]) or bool(layers["danger"])):
		d["strongholds"] = sh.call("strongholds")
		d["raids"] = sh.call("raids")
		d["results"] = sh.call("recent_raid_results")
	if bool(layers["military"]):
		var cm := _mod("campaign")
		d["forces"] = cm.call("known_map") if cm != null else []
		d["own_armies"] = cm.call("player_armies") if cm != null else []
	if bool(layers["danger"]):
		var dn := {}
		for sid: int in sids:
			dn[sid] = float((e.call("danger_of", sid) as Dictionary).get("danger", 0.0))
		d["danger"] = dn
	if bool(layers["diplomacy"]):
		var fa := _mod("factions")
		if fa != null:
			d["factions"] = fa.call("factions")
			d["ties"] = fa.call("ties")
			var rel := {}
			for f: Dictionary in d["factions"]:
				if String(f["kind"]) == "nation" and String(f["id"]) != "caldrenn":
					rel[String(f["id"])] = fa.call("relation", "caldrenn", String(f["id"]))
			d["rel"] = rel
	_data = d
	_hdr.text = "%s   %d gold" % [", ".join((e.call("roles") as Array).map(func(r: String) -> String: return r.capitalize())), int(e.call("gold"))]
	_update_fields()
	if sel >= 0:
		_fill_card()
	else:
		_fill_hint()
	queue_redraw_all()


func _dedupe(points: Array) -> Array:
	var out: Array = []
	for p: Vector2 in points:
		var dup := false
		for q: Vector2 in out:
			if q.distance_to(p) < 120.0:
				dup = true
		if not dup:
			out.append(p)
	return out


func _update_fields() -> void:
	if _land == null:
		return
	_field = _terrain.world()
	_sync_material()
	set_process(_terrain.pending())


func _sync_material() -> void:
	if _field != null and bool(_field.get("ready")) and _land.get("mat_for") != _field:
		_land.material = Terrain.make_material(_field, style)
		_land.set("mat_for", _field)
	_land.set("field", _field)
	_land.queue_redraw()


func _process(_d: float) -> void:
	var more := _terrain.step(6000)
	_sync_material()
	if not more:
		set_process(false)
		queue_redraw_all()


func bake_now() -> void:
	_update_fields()
	_terrain.finish_all()
	_sync_material()
	set_process(false)
	queue_redraw_all()


func terrain_ready() -> bool:
	return _field != null and bool(_field.get("ready"))


# ------------------------------------------------------------------ input ----

func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_press = t.position
				_moved = 0.0
			else:
				_moved = TAP_SLOP
		else:
			var single := _touches.size() == 1
			_touches.erase(t.index)
			if single and _moved < TAP_SLOP:
				_tap(t.position)
		_canvas.accept_event()
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		if d.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if not _touches.has(d.index):
			_touches[d.index] = d.position - d.relative
		var old: Vector2 = _touches[d.index]
		_touches[d.index] = d.position
		if _touches.size() == 1:
			_moved += d.relative.length()
			center -= d.relative / zoom
			_clamp_center()
			queue_redraw_all()
		elif _touches.size() >= 2:
			_moved = TAP_SLOP
			var other := Vector2.ZERO
			for k: int in _touches:
				if k != d.index:
					other = _touches[k]
			var d0 := old.distance_to(other)
			var d1 := d.position.distance_to(other)
			if d0 > 4.0:
				_zoom_at((d.position + other) * 0.5, d1 / d0)
		_canvas.accept_event()
	elif ev is InputEventMouseButton:
		var b := ev as InputEventMouseButton
		if b.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_mouse_down = true
				_press = b.position
				_moved = 0.0
			elif _mouse_down:
				_mouse_down = false
				if _moved < TAP_SLOP:
					_tap(b.position)
			_canvas.accept_event()
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(b.position, 1.2)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(b.position, 1.0 / 1.2)
	elif ev is InputEventMouseMotion and _mouse_down:
		var mm := ev as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_moved += mm.relative.length()
		center -= mm.relative / zoom
		_clamp_center()
		queue_redraw_all()
		_canvas.accept_event()
	elif ev is InputEventMagnifyGesture:
		_zoom_at((ev as InputEventMagnifyGesture).position, (ev as InputEventMagnifyGesture).factor)


func settlement_at(screen_pos: Vector2, slop := 40.0) -> int:
	var best := -1
	var bd := slop
	for s: Dictionary in WorldGen.settlements:
		var d := to_screen(s["pos"]).distance_to(screen_pos)
		if d < bd:
			bd = d
			best = int(s["id"])
	return best


func caravan_at(screen_pos: Vector2, slop := 30.0) -> int:
	var e := ent()
	if e == null:
		return -1
	for c: Dictionary in e.call("list_caravans"):
		if to_screen(e.call("caravan_pos", c)).distance_to(screen_pos) < slop:
			return int(c["id"])
	return -1


func _tap(pos: Vector2) -> void:
	var cid := caravan_at(pos)
	if cid >= 0:
		select_caravan(cid)
		return
	var sid := settlement_at(pos)
	if sid >= 0:
		select(sid)
	else:
		sel = -1
		sel_car = -1
		_fill_hint()
		queue_redraw_all()


func select(sid: int) -> void:
	sel = sid
	sel_car = -1
	_fill_card()
	queue_redraw_all()


func select_caravan(cid: int) -> void:
	sel_car = cid
	sel = -1
	_fill_caravan_card()
	queue_redraw_all()


# ------------------------------------------------------------------ cards ----

func _fill_hint() -> void:
	Kit.clear(_card)
	_card.add_child(Kit.section("Strategic map", 20))
	_card.add_child(Kit.lbl("Tap a settlement for its card. Toggle layers above: Political shows who holds what, Trade shows roads, prices and your caravans, Resources what each place makes and lacks, Military strongholds and raiders, Diplomacy the lines between lords, Danger where the road is unsafe.", 16, AF.TEXT_DIM, true))
	var e := ent()
	if e != null:
		_card.add_child(Kit.lbl("You are known as: %s." % ", ".join((e.call("roles") as Array)), 16, AF.TEXT, true))
		var n := (e.get("caravans") as Dictionary).size()
		if n > 0:
			_card.add_child(Kit.lbl("%d caravan%s on the roads." % [n, "" if n == 1 else "s"], 16, AF.GOLD_BRIGHT, true))


func _pill(text: String, col: Color) -> Control:
	var l := Kit.lbl(text, 14, Color("16120c"))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(col, col.darkened(0.3), 9, 4))
	p.add_child(l)
	return p


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _gname(g: String) -> String:
	return String((D.GOODS.get(g, {"name": g}) as Dictionary)["name"])


func _fill_card() -> void:
	Kit.clear(_card)
	var e := ent()
	if e == null or sel < 0:
		_fill_hint()
		return
	var c: Dictionary = e.call("settlement_card", sel)
	_card.add_child(Kit.lbl(String(c["name"]), 26, AF.GOLD_BRIGHT, false, "title_bold"))
	var meta := "%s, %d souls. Held by %s." % [String(c["kind"]).replace("_", " ").capitalize(), int(c["pop"]), c["holder_label"]]
	_card.add_child(Kit.lbl(meta, 16, AF.TEXT, true))
	var chips := _flow()
	if String(c["identity"]) != "":
		chips.add_child(_pill(String(c["identity"]).capitalize(), Color("d8c690")))
	if bool(c["fief"]):
		chips.add_child(_pill("Your fief", Color("7fd18b")))
	if bool(c["rift"]):
		chips.add_child(_pill("Rift crystal", Color("b59cff")))
	if int(c["workshops"]) > 0:
		chips.add_child(_pill("%d workshop%s" % [c["workshops"], "" if int(c["workshops"]) == 1 else "s"], Color("e0b45a")))
	if int(c["caravans"]) > 0:
		chips.add_child(_pill("Caravan here", Color("6fd0e0")))
	_card.add_child(chips)
	# actions first: what this player can do here
	_card.add_child(Kit.section("Actions", 18))
	for a: Dictionary in c["actions"]:
		var b := Kit.button(String(a["label"]), bool(a["ok"]) and String(a["id"]) in ["trade", "fief"], 52, 17)
		b.disabled = not bool(a["ok"])
		b.pressed.connect(_do_action.bind(String(a["id"]), sel))
		_card.add_child(b)
		if not bool(a["ok"]) and String(a["reason"]) != "":
			_card.add_child(Kit.lbl(String(a["reason"]), 13, AF.TEXT_DIM, true, "italic"))
	# market
	_card.add_child(Kit.section("Market", 18))
	var age := int(c["age"])
	_card.add_child(Kit.lbl("Prices %s." % e.call("age_text", age), 15, AF.TEXT_DIM if age != 0 else AF.GOLD_BRIGHT, true, "italic"))
	var sells: Array = c["sells"]
	var needs: Array = c["needs"]
	if not sells.is_empty():
		_card.add_child(Kit.lbl("Plentiful and cheap:", 15, AF.TEXT_DIM))
		var f1 := _flow()
		for g: String in sells.slice(0, 6):
			f1.add_child(_pill(_gname(g), Color("8fd694")))
		_card.add_child(f1)
	if not needs.is_empty():
		_card.add_child(Kit.lbl("Short and dear:", 15, AF.TEXT_DIM))
		var f2 := _flow()
		for g: String in needs.slice(0, 6):
			f2.add_child(_pill(_gname(g), Color("e9857a")))
		_card.add_child(f2)
	var kp := {}
	for g: String in ["grain", "tools", "ale", "cloth", "iron"]:
		kp[g] = e.call("known_price", sel, g)
	var line := []
	for g: String in kp:
		if not (kp[g] as Dictionary).is_empty():
			line.append("%s %dg" % [_gname(g), int((kp[g] as Dictionary)["p"])])
	if not line.is_empty():
		_card.add_child(Kit.lbl("  ".join(line), 15, AF.TEXT, true))
	# danger
	var dg: Dictionary = c["danger"]
	_card.add_child(Kit.section("Road and wilds", 18))
	_card.add_child(Kit.bar(float(dg.get("danger", 0.0)), 16.0, Color("d8493c"), "Danger %d%%" % int(float(dg.get("danger", 0.0)) * 100.0)))
	_card.add_child(Kit.lbl(String(dg.get("text", "")), 15, AF.TEXT, true))
	_card.add_child(Kit.lbl("Your standing here: %d. Loyalty of the people: %d." % [int(c["standing"]), int(c["loyalty"])], 15, AF.TEXT_DIM, true))


func _fill_caravan_card() -> void:
	Kit.clear(_card)
	var e := ent()
	var c: Dictionary = e.call("get_caravan", sel_car) if e != null else {}
	if c.is_empty():
		_fill_hint()
		return
	var prof: Dictionary = e.call("leader_profile", String(c["leader"]))
	_card.add_child(Kit.lbl(String(c["name"]), 24, AF.GOLD_BRIGHT, false, "title_bold"))
	_card.add_child(Kit.lbl(String(e.call("caravan_status", c)), 17, AF.TEXT, true))
	_card.add_child(Kit.lbl("Led by %s (%s). %d guards. Loyalty %d." % [prof["name"], ", ".join(prof["traits"]), int(c["guards"]), int(prof["loyalty"])], 15, AF.TEXT_DIM, true))
	_card.add_child(Kit.lbl("Purse %d of %d gold. %d trips, %+d gold so far. %d raids." % [int(c["cash"]), int(c["capital"]), int(c["trips"]), int(c["profit"]), int(c["raids"])], 15, AF.TEXT, true))
	var cargo: Dictionary = c["cargo"]
	var parts := []
	for g: String in cargo:
		parts.append("%d %s" % [int((cargo[g] as Array)[0]), _gname(g).to_lower()])
	_card.add_child(Kit.lbl("Carrying: %s." % (", ".join(parts) if not parts.is_empty() else "nothing"), 15, AF.TEXT, true))
	for r: Dictionary in (c["reports"] as Array).slice(-3):
		_card.add_child(Kit.lbl("Day %d: %s" % [int(r["day"]), r["text"]], 13, AF.TEXT_DIM, true, "italic"))
	var b := Kit.button("Open caravans", true, 52, 17)
	b.pressed.connect(_do_action.bind("caravans", int(c["home"])))
	_card.add_child(b)


func _do_action(action: String, sid: int) -> void:
	var e := ent()
	match action:
		"license":
			if e != null:
				var r: Dictionary = e.call("buy_license")
				_say("You are now a licensed trader." if bool(r["ok"]) else String(r["reason"]))
				_settle()
				refresh()
			return
		"buy_fief":
			if e != null:
				var r2: Dictionary = e.call("buy_fief", sid)
				_say("The estate is yours." if bool(r2["ok"]) else String(r2["reason"]))
				_settle()
				refresh()
			return
	action_requested.emit(action, sid)
	var tab_for := {"trade": "market", "workshop": "workshops", "caravan": "caravans", "caravans": "caravans", "recruit": "clan", "fief": "fief", "duty": "clan"}
	if tab_for.has(action):
		open_screen(String(tab_for[action]), sid)


## The enterprise screen (trade, routes, caravans, workshops, fief, clan) opened over the map.
func open_screen(tab: String, at_sid: int) -> Control:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	var m: Control = load("res://scripts/ui/strategic/enterprise_screen.gd").new()
	m.set("realm_override", realm_override)
	m.set("tab", tab)
	m.set("sid", at_sid)
	m.set("plan_stops", plan_stops.duplicate())
	m.connect("closed", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		_screen = null
		refresh())
	m.connect("show_map", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		_screen = null
		refresh())
	m.connect("route_preview", func(stops: Array) -> void:
		plan_stops = stops.duplicate()
		queue_redraw_all())
	add_child(m)
	_screen = m
	return m


## Applies the enterprise ledger to the purse after a player action.
func _settle() -> void:
	var e := ent()
	if e == null or int(e.get("purse_override")) >= 0:
		return
	var g := int(e.call("take_pending_gold"))
	var game: Node = get_node_or_null("/root/Game")
	if g != 0 and game != null:
		game.call("add_gold", g)


# ----------------------------------------------------------------- drawing ----

class LandLayer extends Control:
	var map: Control
	var field: Object = null
	var mat_for: Object = null

	func _draw() -> void:
		if map == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), map.call("_bg_color"))
		if field == null or not bool(field.get("ready")):
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
			return {"road": Color("efe1b8"), "road_case": Color(0.25, 0.2, 0.12, 0.8), "label": Color("2b2115"), "label_out": Color(0.95, 0.9, 0.75, 0.85), "town": Color("3b2c1a"), "panel": Color(0.93, 0.88, 0.74, 0.88)}
		Tokens.TACTICAL:
			return {"road": Color("e6dcc0"), "road_case": Color(0, 0, 0, 0.55), "label": Color("e8e4d8"), "label_out": Color(0, 0, 0, 0.85), "town": Color("e8e4d8"), "panel": Color(0.03, 0.04, 0.06, 0.82)}
	return {"road": Color("f4e6bd"), "road_case": Color(0.3, 0.2, 0.08, 0.8), "label": Color("3a2611"), "label_out": Color(0.96, 0.9, 0.72, 0.9), "town": Color("4a3016"), "panel": Color(0.93, 0.84, 0.64, 0.9)}


func _bg_color() -> Color:
	match style:
		Tokens.REALISTIC:
			return Color("8d9278")
		Tokens.TACTICAL:
			return Color("0f1215")
	return Color("b99a66")


func _holder_color(h: String) -> Color:
	match h:
		"crown":
			return Color("d8a84e")
		"church":
			return Color("9a7fd1")
		"commons":
			return Color("6fae6a")
		"player":
			return Color("4f9dea")
		"rebels":
			return Color("d8493c")
	var hv := float(absi(hash(h)) % 1000) / 1000.0
	return Color.from_hsv(hv, 0.55, 0.85)


func _faction_color(f: String) -> Color:
	match f:
		"caldrenn":
			return Color("d8a84e")
		"player":
			return Color("4f9dea")
		"independent":
			return Color("b59cff")
	return Tokens.HOSTILE_COLS[absi(hash(f)) % Tokens.HOSTILE_COLS.size()]


func _text(ci: Control, p: Vector2, txt: String, fs: int, col: Color, out: Color, ow := 4) -> void:
	Tokens.text_centered(ci, _title_font, txt, p, fs, col, out, ow)


func _draw_overlay(ci: Control) -> void:
	if _canvas == null or _data.is_empty():
		return
	var pal := _palette()
	if bool(layers["political"]):
		_draw_political(ci, pal)
	if bool(layers["danger"]):
		_draw_danger_heat(ci)
	_draw_roads(ci, pal)
	if bool(layers["diplomacy"]):
		_draw_diplomacy(ci, pal)
	if bool(layers["military"]):
		_draw_military(ci, pal)
	if bool(layers["danger"]):
		_draw_danger_marks(ci, pal)
	_draw_rifts(ci, pal)
	_draw_settlements(ci, pal)
	if bool(layers["trade"]):
		_draw_trade(ci, pal)
	if bool(layers["resources"]):
		_draw_resources(ci, pal)
	_draw_plan(ci, pal)
	_draw_caravans(ci, pal)
	_draw_selection(ci, pal)
	_draw_legend(ci, pal)


func _node_pos(n: String) -> Vector2:
	var cm := _mod("camps")
	return cm.call("node_pos", n) if cm != null else Vector2.ZERO


func _build_political() -> void:
	var holders := {}
	var sig_parts: Array = []
	for sid: int in _data["sids"]:
		var p: Dictionary = _data["pol"][sid]
		holders[sid] = String(p["holder"])
		sig_parts.append("%d%s%d" % [sid, String(p["holder"]), style])
	var sig := "|".join(sig_parts)
	if sig == _pol_sig and _pol_tex != null:
		return
	_pol_sig = sig
	var n := 112
	var half := WorldGen.WORLD_HALF
	var cell := half * 2.0 / float(n)
	var owner_idx := PackedInt32Array()
	owner_idx.resize(n * n)
	var sites: Array = []
	for s: Dictionary in WorldGen.settlements:
		sites.append([int(s["id"]), s["pos"]])
	for y in n:
		for x in n:
			var wp := Vector2((float(x) + 0.5) * cell - half, (float(y) + 0.5) * cell - half)
			var best := 0
			var bd := INF
			for st: Array in sites:
				var dd: float = wp.distance_squared_to(st[1])
				if dd < bd:
					bd = dd
					best = int(st[0])
			# the wilds beyond ~1.6 km of any town belong to nobody
			owner_idx[y * n + x] = best if bd < 1700.0 * 1700.0 else -1
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for y in n:
		for x in n:
			var i := y * n + x
			var o := owner_idx[i]
			var col := Color(0, 0, 0, 0)
			if o >= 0:
				var h := String(holders.get(o, "crown"))
				col = _holder_color(h)
				col.a = 0.30
				var edge := false
				if x + 1 < n and owner_idx[i + 1] >= 0 and String(holders.get(owner_idx[i + 1], "")) != h:
					edge = true
				if y + 1 < n and owner_idx[i + n] >= 0 and String(holders.get(owner_idx[i + n], "")) != h:
					edge = true
				if x > 0 and owner_idx[i - 1] >= 0 and String(holders.get(owner_idx[i - 1], "")) != h:
					edge = true
				if y > 0 and owner_idx[i - n] >= 0 and String(holders.get(owner_idx[i - n], "")) != h:
					edge = true
				if edge:
					col = col.darkened(0.45)
					col.a = 0.85
			data[i * 4] = int(col.r * 255.0)
			data[i * 4 + 1] = int(col.g * 255.0)
			data[i * 4 + 2] = int(col.b * 255.0)
			data[i * 4 + 3] = int(col.a * 255.0)
	_pol_tex = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data))


func _draw_political(ci: Control, pal: Dictionary) -> void:
	_build_political()
	var half := WorldGen.WORLD_HALF
	var a := to_screen(Vector2(-half, -half))
	var b := to_screen(Vector2(half, half))
	ci.draw_texture_rect(_pol_tex, Rect2(a, b - a), false)
	# war owners of strongholds: a soft disc
	for s: Dictionary in _data.get("strongholds", []):
		pass
	var cm := _mod("campaign")
	if cm != null:
		for k: Variant in (cm.call("captured") as Dictionary):
			var sid := int(k)
			if sid >= 0 and sid < WorldGen.settlements.size():
				var p := to_screen(WorldGen.settlements[sid]["pos"])
				ci.draw_arc(p, 26.0, 0, TAU, 28, Tokens.faction_color(String((cm.call("captured") as Dictionary)[k])), 4.0, true)


func _road_color(risk: float, trade: float) -> Color:
	var t := clampf(risk / 0.25, 0.0, 1.0)
	return Color("7fd18b").lerp(Color("e0b45a"), clampf(t * 2.0, 0.0, 1.0)).lerp(Color("e0433a"), clampf(t * 2.0 - 1.0, 0.0, 1.0))


func _draw_roads(ci: Control, pal: Dictionary) -> void:
	var colour_by_risk := bool(layers["trade"]) or bool(layers["danger"])
	for r: Dictionary in _data["roads"]:
		var pa := to_screen(_node_pos(String(r["a"])))
		var pb := to_screen(_node_pos(String(r["b"])))
		var w := 3.0
		var col: Color = pal["road"]
		if colour_by_risk:
			col = _road_color(float(r["risk"]), float(r["trade"]))
		if bool(layers["trade"]):
			w = 2.5 + 5.5 * clampf(float(r["trade"]) / 1.4, 0.0, 1.0)
		ci.draw_line(pa, pb, pal["road_case"], w + 2.0, true)
		if style == Tokens.TABLE and not colour_by_risk:
			Tokens.dashed(ci, pa, pb, col, w * 0.8, 10.0, 5.0)
		else:
			ci.draw_line(pa, pb, col, w, true)
		if bool(r["guarded"]):
			var m := (pa + pb) * 0.5
			ci.draw_circle(m, 7.0, Color("4f9dea"))
			ci.draw_arc(m, 7.0, 0, TAU, 14, Color("f6e9c8"), 1.5, true)


func _draw_settlements(ci: Control, pal: Dictionary) -> void:
	var view := Rect2(Vector2.ZERO, canvas_size()).grow(40)
	var ink: Color = pal["town"]
	var big := canvas_size().x > 700.0
	var fs := 17 if big else 15
	for s: Dictionary in WorldGen.settlements:
		var p := to_screen(s["pos"])
		if not view.has_point(p):
			continue
		var kind := String(s["kind"])
		var sz := 11.0 if kind in ["town", "castle", "capital"] else 8.0
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
		var sid := int(s["id"])
		var e := ent()
		if e != null and bool(e.call("is_fief", sid)):
			ci.draw_arc(p, sz + 6.0, 0, TAU, 28, Color("4f9dea"), 3.0, true)
		if e != null and not (e.call("workshops_at", sid) as Array).is_empty():
			ci.draw_rect(Rect2(p + Vector2(sz + 3, -sz - 2), Vector2(8, 8)), Color("e0b45a"))
		_text(ci, p + Vector2(0, sz + fs + 3), String(s["name"]), fs, pal["label"], pal["label_out"], 4)


func _draw_trade(ci: Control, pal: Dictionary) -> void:
	var prices: Dictionary = _data.get("prices", {})
	var base := float((D.GOODS[good] as Dictionary)["base"])
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var p := to_screen(s["pos"])
		var kp: Dictionary = prices.get(sid, {})
		if kp.is_empty():
			ci.draw_arc(p, 19.0, 0, TAU, 20, Color(0.75, 0.75, 0.75, 0.6), 2.0, true)
			_text(ci, p + Vector2(22, 4), "?", 15, Color("d9d9d9"), Color(0, 0, 0, 0.85), 4)
			continue
		var ratio := float(kp["p"]) / base
		var col := Color("7fd18b").lerp(Color("e0b45a"), clampf((ratio - 0.75) / 0.25, 0.0, 1.0)).lerp(Color("e0433a"), clampf((ratio - 1.0) / 0.5, 0.0, 1.0))
		var fade := lerpf(1.0, 0.35, clampf(float(kp["age"]) / 20.0, 0.0, 1.0))
		ci.draw_circle(p, 19.0, Color(col, 0.5 * fade))
		ci.draw_arc(p, 19.0, 0, TAU, 24, Color(col, fade), 3.0, true)
		var txt := "%dg" % int(kp["p"])
		if int(kp["age"]) > 0:
			txt += " (%dd)" % int(kp["age"])
		_text(ci, p + Vector2(28, 5), txt, 15, Color(1, 1, 1, fade), Color(0, 0, 0, 0.9), 4)


func _draw_resources(ci: Control, pal: Dictionary) -> void:
	var res: Dictionary = _data.get("res", {})
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var r: Dictionary = res.get(sid, {})
		if r.is_empty():
			continue
		var p := to_screen(s["pos"])
		var y := 40.0
		for pair: Array in [[r["sells"], Color("8fd694")], [r["needs"], Color("e9857a")]]:
			var goods: Array = pair[0]
			if goods.is_empty():
				continue
			var names: Array = []
			for g: String in goods.slice(0, 2):
				names.append(String((D.GOODS[g] as Dictionary)["name"]))
			if goods.size() > 2:
				names.append("+%d" % (goods.size() - 2))
			_pill_at(ci, p + Vector2(0, y), ", ".join(names), pair[1])
			y += 20.0


func _pill_at(ci: Control, c: Vector2, txt: String, col: Color) -> void:
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
	var r := Rect2(c - Vector2(w * 0.5, 9), Vector2(w, 18))
	ci.draw_rect(r, Color(col, 0.92))
	ci.draw_rect(r, col.darkened(0.4), false, 1.0)
	ci.draw_string(_font, Vector2(r.position.x + 6, r.position.y + 13.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("16120c"))


func _draw_rifts(ci: Control, pal: Dictionary) -> void:
	if not (bool(layers["danger"]) or bool(layers["trade"]) or bool(layers["resources"])):
		return
	for rp: Vector2 in _data.get("rifts", []):
		var p := to_screen(rp)
		var r := D.RIFT_DANGER_REACH * zoom * 0.5
		ci.draw_circle(p, r, Color(0.55, 0.3, 0.85, 0.16))
		ci.draw_arc(p, r, 0, TAU, 36, Color(0.7, 0.45, 1.0, 0.7), 2.0, true)
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(8, 0), p + Vector2(0, 11), p + Vector2(-8, 0)]), Color("b59cff"))
		_text(ci, p + Vector2(0, 26), "Rift", 14, Color("d9c8ff"), Color(0, 0, 0, 0.85), 4)


func _draw_military(ci: Control, pal: Dictionary) -> void:
	for s: Dictionary in _data.get("strongholds", []):
		var p := to_screen(s["pos"])
		var col := _faction_color(String(s["owner"]))
		var MI := load("res://scripts/ui/map_icons.gd")
		ci.draw_circle(p, 15.0, Color(0.05, 0.05, 0.05, 0.75))
		ci.draw_arc(p, 15.0, 0, TAU, 24, col, 3.0, true)
		MI.call("draw", ci, "fort", p, 20.0, Color("e8e4d8"), 1.0)
		var ratio := float(int(s["garrison"])) / maxf(float(int(s["garrison_max"])), 1.0)
		ci.draw_rect(Rect2(p + Vector2(-14, 17), Vector2(28, 4)), Color(0, 0, 0, 0.7))
		ci.draw_rect(Rect2(p + Vector2(-14, 17), Vector2(28.0 * ratio, 4)), col)
		if not (s["siege"] as Dictionary).is_empty():
			ci.draw_arc(p, 21.0, 0, TAU, 20, Color("ff6a4a"), 3.0, true)
	for f: Dictionary in _data.get("forces", []):
		if String(f.get("kind", "")) != "force":
			continue
		var p2 := to_screen(f["pos"])
		var own := String(f.get("faction", "")) == "player"
		var fc := Tokens.BLUE if own else Tokens.RED
		var a := clampf(0.3 + 0.7 * float(f.get("confidence", 0.5)), 0.3, 1.0)
		ci.draw_circle(p2, 13.0, Color(0.06, 0.05, 0.04, 0.85 * a))
		ci.draw_circle(p2, 10.0, Color(fc, a))
		Tokens.glyph(ci, "infantry", p2, 6.0, Color("f6e9c8", a), 1.8)
	for ar: Dictionary in _data.get("own_armies", []):
		var p3 := to_screen(ar["pos"])
		ci.draw_circle(p3, 13.0, Color(0.06, 0.05, 0.04, 0.9))
		ci.draw_circle(p3, 10.0, Tokens.BLUE)
		Tokens.glyph(ci, "infantry", p3, 6.0, Color("f6e9c8"), 1.8)


func _draw_danger_heat(ci: Control) -> void:
	var dn: Dictionary = _data.get("danger", {})
	for s: Dictionary in WorldGen.settlements:
		var d: float = float(dn.get(int(s["id"]), 0.0))
		if d <= 0.02:
			continue
		var p := to_screen(s["pos"])
		for k in 4:
			var rr := (720.0 - 150.0 * float(k)) * zoom
			ci.draw_circle(p, rr, Color(0.85, 0.2, 0.12, 0.05 + 0.10 * d * (1.0 + float(k) * 0.3) * 0.5))


func _draw_danger_marks(ci: Control, pal: Dictionary) -> void:
	for r: Dictionary in _data.get("results", []):
		if bool(r["success"]):
			var p := to_screen(r["pos"])
			for w: Array in [[6.0, Color(0, 0, 0, 0.9)], [3.0, Color("ff6a4a")]]:
				ci.draw_line(p + Vector2(-9, -9), p + Vector2(9, 9), w[1], w[0], true)
				ci.draw_line(p + Vector2(-9, 9), p + Vector2(9, -9), w[1], w[0], true)
	for rd: Dictionary in _data.get("raids", []):
		var p2 := to_screen(rd["pos"])
		var tp := to_screen(rd["target_pos"])
		Tokens.dashed(ci, p2, tp, Color("ff6a4a"), 2.5, 8.0, 6.0)
		ci.draw_circle(p2, 10.0, Color("b8322a"))
		ci.draw_arc(p2, 10.0, 0, TAU, 16, Color("f6e9c8"), 2.0, true)
		_text(ci, p2 + Vector2(0, 26), String(rd["kind"]).replace("_", " ").capitalize(), 13, Color("ffb3a0"), Color(0, 0, 0, 0.85), 4)


func _anchor_of(faction: Dictionary) -> Vector2:
	var id := String(faction["id"])
	if _anchors.has(id):
		return _anchors[id]
	var pos := Vector2.ZERO
	if id == "caldrenn":
		pos = WorldGen.settlements[1]["pos"] if WorldGen.settlements.size() > 1 else Vector2.ZERO
	elif String(faction["kind"]) == "nation":
		var dir := Vector2.ZERO
		var text := ""
		for n: Dictionary in _nations():
			if String(n.get("id", "")) == id:
				text = String(n.get("direction", ""))
		for k: String in DIR_VEC:
			if text.contains(k):
				dir += DIR_VEC[k]
		if dir == Vector2.ZERO:
			dir = Vector2(0.7, -0.7)
		pos = dir.normalized() * WorldGen.WORLD_HALF * 0.86
	else:
		# a house sits at the first settlement it holds (by name), else somewhere stable
		for sid: int in _data["sids"]:
			if String((_data["pol"][sid] as Dictionary)["holder"]) == String(faction["name"]):
				pos = WorldGen.settlements[sid]["pos"]
				break
		if pos == Vector2.ZERO and not WorldGen.settlements.is_empty():
			pos = WorldGen.settlements[absi(hash(id)) % WorldGen.settlements.size()]["pos"]
	_anchors[id] = pos
	return pos


func _nations() -> Array:
	var fa := _mod("factions")
	if fa == null:
		return []
	var s: Variant = fa.get_script()
	return s.call("nations_data") if s != null else []


func _draw_diplomacy(ci: Control, pal: Dictionary) -> void:
	var home := Vector2.ZERO
	if WorldGen.settlements.size() > 1:
		home = WorldGen.settlements[1]["pos"]
	var rel: Dictionary = _data.get("rel", {})
	var hp := to_screen(home)
	for f: Dictionary in _data.get("factions", []):
		if String(f["kind"]) != "nation" or String(f["id"]) == "caldrenn":
			continue
		var r: Dictionary = rel.get(String(f["id"]), {})
		var col: Color = STANCE_COL.get(String(r.get("stance", "neutral")), Color.WHITE)
		var ap := to_screen(_anchor_of(f))
		ap = ap.clamp(Vector2(110, 110), canvas_size() - Vector2(110, 110))
		Tokens.dashed(ci, hp, ap, col, 3.0, 14.0, 8.0)
		ci.draw_circle(ap, 13.0, Color(0.05, 0.05, 0.05, 0.85))
		ci.draw_circle(ap, 9.0, col)
		_text(ci, ap + Vector2(0, -20), String(f["name"]), 15, pal["label"], pal["label_out"], 4)
		_text(ci, ap + Vector2(0, 30), "%s, trade %d" % [String(r.get("stance", "neutral")), int(r.get("trade", 0))], 14, col, Color(0, 0, 0, 0.85), 4)
	# the houses: ties between the lords who hold land
	var seats := {}
	for f: Dictionary in _data.get("factions", []):
		if String(f["kind"]) == "house":
			var ap2 := _anchor_of(f)
			if ap2 != Vector2.ZERO:
				seats[String(f["id"])] = ap2
	for t: Dictionary in _data.get("ties", []):
		var a := String(t["a"])
		var b := String(t["b"])
		if seats.has(a) and seats.has(b) and String(t["kind"]) in TIE_COL:
			Tokens.dashed(ci, to_screen(seats[a]), to_screen(seats[b]), TIE_COL[String(t["kind"])], 2.5, 6.0, 5.0)
	for id: String in seats:
		var sp := to_screen(seats[id])
		ci.draw_rect(Rect2(sp - Vector2(9, 9), Vector2(18, 18)), Color("b59cff"))
		ci.draw_rect(Rect2(sp - Vector2(9, 9), Vector2(18, 18)), Color(0, 0, 0, 0.8), false, 2.0)


func _draw_plan(ci: Control, pal: Dictionary) -> void:
	if plan_stops.size() < 2:
		if plan_stops.size() == 1:
			ci.draw_arc(to_screen(WorldGen.settlements[int(plan_stops[0])]["pos"]), 24.0, 0, TAU, 28, AF.GOLD_BRIGHT, 4.0, true)
		return
	var e := ent()
	if e == null:
		return
	for i in range(plan_stops.size() - 1):
		var ri: Dictionary = e.call("route_info", int(plan_stops[i]), int(plan_stops[i + 1]))
		var pts := PackedVector2Array()
		for n: String in ri["nodes"]:
			pts.append(to_screen(_node_pos(n)))
		if pts.size() > 1:
			ci.draw_polyline(pts, Color(0, 0, 0, 0.7), 8.0, true)
			ci.draw_polyline(pts, AF.GOLD_BRIGHT, 5.0, true)
	for k in plan_stops.size():
		var p := to_screen(WorldGen.settlements[int(plan_stops[k])]["pos"])
		ci.draw_circle(p, 13.0, Color(0.05, 0.05, 0.05, 0.9))
		_text(ci, p + Vector2(0, 5), str(k + 1), 15, AF.GOLD_BRIGHT, Color(0, 0, 0, 0.0), 0)


func _draw_caravans(ci: Control, pal: Dictionary) -> void:
	var e := ent()
	if e == null:
		return
	for c: Dictionary in _data.get("caravans", []):
		var p := to_screen(e.call("caravan_pos", c))
		if String(c["state"]) == "travel":
			var pts := PackedVector2Array([p])
			var legs: Array = c["legs"]
			for i in range(int(c["leg"]), legs.size()):
				pts.append(to_screen(_node_pos(String((legs[i] as Dictionary)["b"]))))
			if pts.size() > 1:
				var prev := pts[0]
				for k in range(1, pts.size()):
					Tokens.dashed(ci, prev, pts[k], Color("6fd0e0"), 3.0, 8.0, 6.0)
					prev = pts[k]
		var sel_c := int(c["id"]) == sel_car
		ci.draw_rect(Rect2(p - Vector2(13, 9), Vector2(26, 16)), Color("6b4a2a"))
		ci.draw_rect(Rect2(p - Vector2(13, 9), Vector2(26, 16)), Color("f6e9c8") if sel_c else Color("1a120a"), false, 2.0)
		ci.draw_rect(Rect2(p - Vector2(10, 14), Vector2(20, 6)), Color("e8dcc0"))
		ci.draw_circle(p + Vector2(-8, 8), 4.0, Color("1a120a"))
		ci.draw_circle(p + Vector2(8, 8), 4.0, Color("1a120a"))
		_text(ci, p + Vector2(0, -20), String(c["name"]).get_slice("'", 0), 13, Color("9be8f5"), Color(0, 0, 0, 0.9), 4)


func _draw_selection(ci: Control, pal: Dictionary) -> void:
	if sel >= 0 and sel < WorldGen.settlements.size():
		var p := to_screen(WorldGen.settlements[sel]["pos"])
		ci.draw_arc(p, 26.0, 0, TAU, 32, Color("3b2812"), 6.0, true)
		ci.draw_arc(p, 26.0, 0, TAU, 32, AF.GOLD_BRIGHT, 3.0, true)


func _draw_legend(ci: Control, pal: Dictionary) -> void:
	var lines: Array = []
	if bool(layers["political"]):
		lines.append(["Political: territory by holder", Color("d8a84e")])
		lines.append(["  Crown / Church / Houses / Commons / You", Color(1, 1, 1, 0.6)])
	if bool(layers["trade"]):
		lines.append(["Trade: %s price, green cheap to red dear" % _gname(good), Color("7fd18b")])
		lines.append(["  Road width = traffic, colour = raid risk", Color(1, 1, 1, 0.6)])
		lines.append(["  ? = never seen, faded = old news", Color(1, 1, 1, 0.6)])
	if bool(layers["resources"]):
		lines.append(["Resources: green = makes plenty, red = short", Color("8fd694")])
	if bool(layers["military"]):
		lines.append(["Military: rings = owner, bar = garrison", Color("e0685a")])
	if bool(layers["diplomacy"]):
		lines.append(["Diplomacy: line colour = stance", Color("6fa8ff")])
	if bool(layers["danger"]):
		lines.append(["Danger: red glow, X = raid, purple = rift", Color("ff6a4a")])
	if lines.is_empty():
		return
	var h := 10.0 + 19.0 * lines.size()
	var o := Vector2(10, canvas_size().y - h - (52.0 if bool(layers["trade"]) else 10.0) - (0.0 if not bool(layers["trade"]) else 40.0))
	ci.draw_rect(Rect2(o, Vector2(330, h)), pal["panel"])
	ci.draw_rect(Rect2(o, Vector2(330, h)), AF.GOLD_DIM, false, 1.0)
	var y := 0.0
	for l: Array in lines:
		var c: Color = l[1]
		var tc: Color = c if style != Tokens.REALISTIC and style != Tokens.TABLE else Color("2b2115")
		ci.draw_string(_font, o + Vector2(8, 18 + y), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tc)
		y += 19.0
