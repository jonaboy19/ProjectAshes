extends "res://scripts/ui/gamemenu/gm_tab.gd"
## REALM: the realm simulation's screens (docs/design/REALM_PLAN.md, "UI"). Four sub-views:
##   War Room   embedded world map + known-intel overlay, army orders, couriers, war council, battles
##   Diplomacy  factions, kingship paths, marriages, ties, sects, news
##   Land       regions (loyalty, deeds, unrest), settlement identity, emergencies
##   Followers  people, summons, arrivals, disputes, tamed creatures
## UI rule (SIM_HIERARCHY.md): this page only READS module getters (and calls the player's
## own actions); it never ticks anything. Nothing runs per frame: a view is rebuilt on open,
## on a sub-view switch, after an action, and by one 1 s Timer only when its data changed.
## The War Room shows campaign.known_map() only, never the true enemy positions.

const VIEWS := [["war", "War Room"], ["diplomacy", "Diplomacy"], ["land", "Land"], ["followers", "Followers"], ["enterprise", "Enterprise"]]
const ORDER_KINDS := [["move", "Move"], ["attack", "Attack"], ["hold", "Hold"], ["camp", "Camp"], ["retreat", "Retreat"]]
const RETREATS := ["orderly", "rout", "feigned", "scorched"]
const FORMATIONS := ["line", "wedge", "square", "skirmish", "column"]
const NEEDS_TARGET := ["move", "attack", "retreat"]
const WarMap := preload("res://scripts/ui/war/war_map.gd")
const TOUCH_H := 64.0
const SIDE_W := 400.0
const EMPTY := "Nothing known yet."
const STANCE_COL := {"allied": Color("7fd18b"), "friendly": Color("b3d98a"), "neutral": Color("ece3cf"),
	"wary": Color("e0b45a"), "hostile": Color("e0685a"), "war": Color("e0433a")}
const EMERGENCY_NAME := {"fire": "Fire", "plague": "Plague", "famine": "Famine", "strike": "Strike", "raid_aftermath": "Raid aftermath"}

## Tests / other hosts may inject a realm hub; otherwise Life.realm is used (may be absent).
var realm_override: RefCounted = null
var view := "war"
var sel_army := -1
var sel_kind := "move"
var sel_retreat := "orderly"
var sel_formation := "line"
var sel_target := -1
var status_line := ""

var overlay: Overlay = null
var _seg_row: HBoxContainer
var _stack: Control
var _pages: Dictionary = {}       # view id -> root Control
var _boxes: Dictionary = {}       # view id -> VBoxContainer that holds the content
var _scrolls: Dictionary = {}     # view id -> ScrollContainer
var _sigs: Dictionary = {}
var _timer: Timer
var _host: Control
var _placeholder: Label
var _map: Control
var war_map: Control = null        # the full War Map (scripts/ui/war/war_map.gd) while it is open
var strategic: Control = null      # the strategic overlay map while it is open
var enterprise_screen: Control = null
var _home: Node
var _home_index := 0
var _hooked := false
var _need_fit := false
var _msgs: Dictionary = {}        # follower id -> last summon answer
var _army_rows: Dictionary = {}


# ----------------------------------------------------------------- overlay (map) ----

## Drawn over the embedded world map: only campaign.known_map() entries, faded by
## confidence. Taps (not drags) are reported as world positions; events still reach the map.
class Overlay extends Control:
	var map: Control
	var entries: Array = []
	var target_node_pos: Variant = null
	var on_tap := Callable()
	var _press := Vector2.ZERO
	var _moved := 0.0
	var _down := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _gui_input(e: InputEvent) -> void:
		var pos := Vector2.ZERO
		var released := false
		if e is InputEventScreenTouch:
			pos = (e as InputEventScreenTouch).position
			if (e as InputEventScreenTouch).pressed:
				_press = pos
				_moved = 0.0
				_down = true
			else:
				released = _down
				_down = false
		elif e is InputEventScreenDrag:
			_moved += (e as InputEventScreenDrag).relative.length()
		elif e is InputEventMouseButton and (e as InputEventMouseButton).device != InputEvent.DEVICE_ID_EMULATION \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pos = (e as InputEventMouseButton).position
			if (e as InputEventMouseButton).pressed:
				_press = pos
				_moved = 0.0
				_down = true
			else:
				released = _down
				_down = false
		elif e is InputEventMouseMotion and _down and (e as InputEventMouseMotion).device != InputEvent.DEVICE_ID_EMULATION:
			_moved += (e as InputEventMouseMotion).relative.length()
		if released and _moved < 14.0 and map != null and on_tap.is_valid():
			on_tap.call(map.call("to_world", pos))

	func _draw() -> void:
		if map == null or not is_instance_valid(map):
			return
		var f := AF.font(AF.BODY_FONT)
		var view_rect := Rect2(Vector2.ZERO, size).grow(60.0)
		if target_node_pos is Vector2:
			var t: Vector2 = map.call("to_screen", target_node_pos)
			draw_arc(t, 22.0, 0, TAU, 32, Color("3b2812"), 5.0, true)
			draw_arc(t, 22.0, 0, TAU, 32, AF.GOLD_BRIGHT, 3.0, true)
		var stacked: Dictionary = {}     # node -> forces already drawn there (fan them out)
		for e: Dictionary in entries:
			var s: Vector2 = map.call("to_screen", e["pos"])
			if not view_rect.has_point(s):
				continue
			var lab_dy := 0.0
			if String(e.get("kind", "")) == "force":
				var nk := int(e.get("node", -1))
				var idx := int(stacked.get(nk, 0))
				stacked[nk] = idx + 1
				s += Vector2(40.0 * idx, 0.0)
				lab_dy = 44.0 * idx
			var conf := clampf(float(e.get("confidence", 0.5)), 0.0, 1.0)
			var a := clampf(0.28 + 0.72 * conf, 0.28, 1.0)
			var kind := String(e.get("kind", ""))
			if kind == "force":
				var own := String(e.get("faction", "")) == "player"
				var col := Color("4f86d6") if own else Color("d8493c")
				draw_circle(s, 17.0, Color(0.06, 0.05, 0.04, 0.85 * a))
				draw_circle(s, 14.0, Color(col, a))
				draw_arc(s, 17.0, 0, TAU, 24, Color("f6e9c8", a), 2.0, true)
				# pennant glyph
				draw_line(s + Vector2(-4, 8), s + Vector2(-4, -8), Color("f6e9c8", a), 2.0)
				draw_colored_polygon(PackedVector2Array([s + Vector2(-4, -8), s + Vector2(8, -4), s + Vector2(-4, 0)]), Color("f6e9c8", a))
				var age := int(e.get("age_days", 0))
				var when := "seen today" if age == 0 else "seen %d day%s ago" % [age, "" if age == 1 else "s"]
				var est := "" if own else "est. %d–%d" % [int(e.get("est_min", 0)), int(e.get("est_max", 0))]
				_text(f, s + Vector2(0, 36 + lab_dy), when, 14, a)
				if est != "":
					_text(f, s + Vector2(0, 56 + lab_dy), est, 15, a)
			elif kind == "stronghold" or kind == "fort":
				var MI := load("res://scripts/ui/map_icons.gd")
				MI.call("draw", self, "fort", s, 24.0, Color("c9bfae"), a)
				_text(f, s + Vector2(0, 30), String(e.get("name", "")), 14, a)
			else:
				var pts := PackedVector2Array([s + Vector2(0, -5), s + Vector2(5, 0), s + Vector2(0, 5), s + Vector2(-5, 0)])
				draw_colored_polygon(pts, Color("3b2812", 0.65 * a))

	func _text(f: Font, centre_below: Vector2, txt: String, fs: int, a: float) -> void:
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := centre_below + Vector2(-w * 0.5, 0)
		draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.96, 0.91, 0.78, 0.9 * a))
		draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2c1d0c", a))


# ------------------------------------------------------------------ data access ----

func realm() -> RefCounted:
	if realm_override != null:
		return realm_override
	var r: Variant = Life.get("realm")
	return r if r is RefCounted else null


func mod(name: String) -> RefCounted:
	var h := realm()
	return h.call("mod", name) if h != null else null


func _const(m: RefCounted, name: String) -> Variant:
	var s: Variant = m.get_script()
	if s is GDScript:
		return (s as GDScript).get_script_constant_map().get(name)
	return null


func _player_pos() -> Vector2:
	var p: Variant = Life.get("player")
	if p is Node3D and is_instance_valid(p):
		return Vector2((p as Node3D).global_position.x, (p as Node3D).global_position.z)
	return Vector2.ZERO


func _node_name(n: int) -> String:
	if n >= 0 and n < WorldGen.settlements.size():
		return String(WorldGen.settlements[n]["name"])
	return "the wilds"


func _fname(id: String) -> String:
	var fa := mod("factions")
	if fa != null:
		var f: Dictionary = fa.call("faction", id)
		if not f.is_empty():
			return String(f.get("name", id))
	return id.capitalize()


func _region_name(key: Variant) -> String:
	var s := String(key)
	if s.is_valid_int():
		return _node_name(int(s))
	return s.capitalize()


## What the overlay draws: campaign.known_map() and nothing else.
func overlay_entries() -> Array:
	var cm := mod("campaign")
	return cm.call("known_map") if cm != null else []


## Intel rows of the side list: known forces only, newest first.
func intel_forces() -> Array:
	var out: Array = overlay_entries().filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "force")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age_days"]) < int(b["age_days"]))
	return out


# ------------------------------------------------------------------------ build ----

func build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_seg_row = HBoxContainer.new()
	_seg_row.add_theme_constant_override("separation", 8)
	col.add_child(_seg_row)
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_stack)
	# War room: map host + side column.
	var war := HBoxContainer.new()
	war.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	war.add_theme_constant_override("separation", 12)
	_stack.add_child(war)
	_host = Control.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.clip_contents = true
	war.add_child(_host)
	_placeholder = Kit.lbl("The war map is not available here. Use the intelligence list.", 17, AF.TEXT_DIM, true, "italic")
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_host.add_child(_placeholder)
	var side_scroll := _make_scroll()
	side_scroll.custom_minimum_size.x = SIDE_W
	war.add_child(side_scroll)
	_pages["war"] = war
	_scrolls["war"] = side_scroll
	_boxes["war"] = side_scroll.get_child(0)
	for id: String in ["diplomacy", "land", "followers", "enterprise"]:
		var sc := _make_scroll()
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sc.visible = false
		_stack.add_child(sc)
		_pages[id] = sc
		_scrolls[id] = sc
		_boxes[id] = sc.get_child(0)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.autostart = false
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_style_segments()


func _make_scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return sc


func _style_segments() -> void:
	Kit.clear(_seg_row)
	for v: Array in VIEWS:
		var b := Kit.tab_button(String(v[1]), String(v[0]) == view, set_view.bind(String(v[0])))
		b.custom_minimum_size.y = TOUCH_H
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seg_row.add_child(b)


func on_show() -> void:
	_show_view(view)
	_timer.start()


func on_hide() -> void:
	if _timer != null:
		_timer.stop()
	for n: Control in [strategic, enterprise_screen]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	strategic = null
	enterprise_screen = null
	_close_war_map()
	_detach_map()


func refresh() -> void:
	_rebuild(view, true)


func hints() -> Array:
	if view != "war":
		return []
	return [["M", "War Map", open_war_map, mod("campaign") == null], ["Tap", "Choose target on map", func() -> void: pass, true]]


## Opens the War Map (formations as pieces, fog of war, engagements) over this page.
func open_war_map() -> Control:
	if war_map != null and is_instance_valid(war_map):
		return war_map
	var m: Control = WarMap.new()
	m.set("realm_override", realm_override)
	m.set("embedded", false)
	m.closed.connect(_close_war_map)
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	war_map = m
	return m


## The strategic overlay map (political / trade / resources / military / diplomacy / danger layers).
func open_strategic() -> Control:
	if strategic != null and is_instance_valid(strategic):
		return strategic
	var m: Control = load("res://scripts/ui/strategic/strategic_map.gd").new()
	m.set("realm_override", realm_override)
	m.set("embedded", true)
	m.connect("closed", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		strategic = null)
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strategic = m
	return m


func open_enterprise(tab := "market") -> Control:
	if enterprise_screen != null and is_instance_valid(enterprise_screen):
		enterprise_screen.queue_free()
	var m: Control = load("res://scripts/ui/strategic/enterprise_screen.gd").new()
	m.set("realm_override", realm_override)
	m.set("tab", tab)
	m.connect("closed", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		enterprise_screen = null
		refresh())
	m.connect("show_map", func() -> void:
		if is_instance_valid(m):
			m.queue_free()
		enterprise_screen = null
		open_strategic())
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enterprise_screen = m
	return m


func _close_war_map() -> void:
	if war_map != null and is_instance_valid(war_map):
		war_map.queue_free()
	war_map = null


func set_view(id: String) -> void:
	if not _pages.has(id):
		return
	view = id
	_style_segments()
	_show_view(id)


func _show_view(id: String) -> void:
	for k: String in _pages:
		(_pages[k] as Control).visible = k == id
	if id == "war":
		_attach_map()
	else:
		_detach_map()
	_rebuild(id, true)
	hints_changed()


func _on_timer() -> void:
	if visible:
		_rebuild(view, false)


## Rebuilds one view. Unless forced, skipped when the underlying data has not changed.
func _rebuild(id: String, force: bool) -> void:
	var sig := hash(_signature(id))
	if not force and _sigs.get(id, -1) == sig:
		return
	_sigs[id] = sig
	var box: VBoxContainer = _boxes[id]
	var sc: ScrollContainer = _scrolls[id]
	var keep := sc.scroll_vertical
	Kit.clear(box)
	match id:
		"war":
			_fill_war(box)
		"diplomacy":
			_fill_diplomacy(box)
		"land":
			_fill_land(box)
		"followers":
			_fill_followers(box)
		"enterprise":
			_fill_enterprise(box)
	if keep > 0:
		sc.set_deferred("scroll_vertical", keep)


func _signature(id: String) -> Array:
	var s: Array = [Game.gold if id == "land" else 0]
	match id:
		"war":
			var cm := mod("campaign")
			if cm != null:
				s.append_array([cm.call("known_map"), cm.call("couriers"), cm.call("player_armies"), cm.call("battles"),
					cm.call("pending_live_battle"), cm.call("council_advice")])
		"diplomacy":
			var fa := mod("factions")
			if fa != null:
				s.append_array([fa.call("factions").size(), fa.call("relation", "player", "church"), fa.call("kingship_paths"),
					fa.call("marriages"), fa.call("sects"), fa.call("news", 6)])
		"land":
			var la := mod("land")
			var se := mod("settlements")
			if la != null:
				var r: Array = la.call("regions")
				for k: Variant in r:
					s.append([la.call("loyalty", k), la.call("deed", k)])
				s.append(la.call("rebellions"))
			if se != null:
				s.append_array([se.call("emergencies"), se.call("digest")])
		"followers":
			var fo := mod("followers")
			if fo != null:
				s.append_array([fo.call("list"), fo.call("arrivals"), fo.call("disputes"), fo.call("tamed"), _msgs])
		"enterprise":
			var en := mod("enterprise")
			if en != null:
				s.append_array([(en.get("caravans") as Dictionary).size(), (en.get("workshops") as Array).size(), en.call("gold"), en.get("log_lines"), en.call("fief_ids")])
	return s


# ------------------------------------------------------------------- shared UI ----

func _card() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _framed(v: Control, border := AF.GOLD_DIM) -> PanelContainer:
	var p := Kit.framed(v, Color(0.03, 0.028, 0.025, 0.7), border, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _empty(box: Control, text := EMPTY) -> void:
	box.add_child(Kit.lbl(text, 17, AF.TEXT_DIM, true, "italic"))


func _btn(text: String, cb: Callable, primary := false, disabled := false) -> Button:
	var b := Kit.button(text, primary, TOUCH_H, 17)
	b.disabled = disabled
	b.pressed.connect(cb)
	return b


func _stat_bar(caption: String, ratio: float, color: Color, value_text := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Kit.lbl(caption, 15, AF.TEXT_DIM)
	l.custom_minimum_size.x = 84
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Kit.bar(ratio, 20.0, color, value_text)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return h


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _chip(text: String, on: bool, cb: Callable) -> Button:
	var b := Kit.tab_button(text, on, cb, 84.0)
	b.custom_minimum_size.y = TOUCH_H
	return b


func _cols() -> int:
	return 2 if size.x >= 900.0 else 1


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = _cols()
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _say(text: String) -> void:
	status_line = text
	if text != "":
		Game.say(text)


# ---------------------------------------------------------------------- War Room ----

func _fill_war(box: VBoxContainer) -> void:
	var cm := mod("campaign")
	if cm == null:
		_empty(box, "The war room is empty. No campaign is underway.")
		_refresh_overlay()
		return
	if status_line != "":
		box.add_child(Kit.lbl(status_line, 16, AF.GOLD_BRIGHT, true, "italic"))
	box.add_child(_btn("Open War Map", open_war_map, true))
	# --- armies
	box.add_child(Kit.section("Your Armies"))
	var armies: Array = cm.call("player_armies")
	_army_rows.clear()
	if armies.is_empty():
		_empty(box, "You command no armies yet.")
		sel_army = -1
	else:
		var found := false
		for a: Dictionary in armies:
			found = found or int(a["id"]) == sel_army
		if not found:
			sel_army = int(armies[0]["id"])
		for a: Dictionary in armies:
			var r := Kit.row("%s" % a["name"], "", "%d men" % int(a["strength"]), "", TOUCH_H, true)
			r.set_selected(int(a["id"]) == sel_army)
			r.pressed.connect(_select_army.bind(int(a["id"])))
			box.add_child(r)
			_army_rows[int(a["id"])] = r
		_order_panel(box, cm)
	# --- couriers
	box.add_child(Kit.section("Couriers in Flight"))
	var cs: Array = cm.call("couriers")
	if cs.is_empty():
		_empty(box, "No orders on the road.")
	for c: Dictionary in cs:
		var o: Dictionary = c["order"]
		var left := maxi(0, int(c["eta_hours"]) - int(c["elapsed"]))
		var v := _card()
		v.add_child(Kit.lbl("%s: %s %s" % [_army_name(cm, int(c["army_id"])), String(o.get("kind", "?")).capitalize(),
			"" if not o.has("target") else "to " + _node_name(int(o["target"]))], 17, AF.TEXT, true))
		v.add_child(Kit.lbl("Arrives in about %d hour%s" % [left, "" if left == 1 else "s"], 15, AF.GOLD))
		box.add_child(_framed(v))
	# --- council
	box.add_child(Kit.section("War Council"))
	var advice: Array = cm.call("council_advice")
	if advice.is_empty():
		_empty(box, "Your advisors have no counsel yet.")
	for ad: Dictionary in advice:
		var v2 := _card()
		v2.add_child(Kit.lbl("%s, %s (%s)" % [ad["advisor"], ad["role"], ad["personality"]], 17, AF.GOLD_BRIGHT, true, "title"))
		v2.add_child(Kit.lbl(String(ad["text"]), 16, AF.TEXT, true))
		v2.add_child(_stat_bar("Confidence", float(ad["confidence"]), AF.GOLD, "%d%%" % int(float(ad["confidence"]) * 100.0)))
		v2.add_child(_btn("Follow", _follow.bind(int(ad["index"])), false, armies.is_empty()))
		box.add_child(_framed(v2))
	# --- battles
	box.add_child(Kit.section("Battles"))
	var pend: Dictionary = cm.call("pending_live_battle")
	var battles: Array = cm.call("battles")
	if pend.is_empty() and battles.is_empty():
		_empty(box, "No battles yet.")
	if not pend.is_empty():
		var v3 := _card()
		v3.add_child(Kit.lbl("Pending: battle at %s" % pend["name"], 18, AF.RED.lightened(0.3), true, "title"))
		v3.add_child(Kit.lbl("Your presence may turn it. Unresolved battles are settled by the generals.", 15, AF.TEXT_DIM, true))
		box.add_child(_framed(v3, AF.RED))
	for i in range(battles.size() - 1, maxi(-1, battles.size() - 6), -1):
		var b: Dictionary = battles[i]
		box.add_child(Kit.lbl("Day %d, %s: %s won%s" % [int(b["day"]), b["name"], b["winner_faction"],
			" (live)" if bool(b["live"]) else ""], 16, AF.TEXT, true))
	# --- intel list
	box.add_child(Kit.section("Known Intelligence"))
	var forces := intel_forces()
	if forces.is_empty():
		_empty(box, "No enemy movements are known.")
	for e: Dictionary in forces:
		var r2 := Kit.row(_intel_text(e), "", "", "", TOUCH_H, false)
		r2.pressed.connect(_set_target.bind(int(e["node"])))
		box.add_child(r2)
	_refresh_overlay()


func _intel_text(e: Dictionary) -> String:
	var age := int(e["age_days"])
	var when := "seen today" if age == 0 else "seen %d day%s ago" % [age, "" if age == 1 else "s"]
	if String(e.get("faction", "")) == "player":
		return "Your force at %s, %s" % [e["name"], when]
	return "Unknown force at %s, %s, est. %d–%d" % [e["name"], when, int(e["est_min"]), int(e["est_max"])]


func _army_name(cm: RefCounted, id: int) -> String:
	for a: Dictionary in cm.call("player_armies"):
		if int(a["id"]) == id:
			return String(a["name"])
	return "Army"


func _order_panel(box: VBoxContainer, cm: RefCounted) -> void:
	var army: Dictionary = {}
	for a: Dictionary in cm.call("player_armies"):
		if int(a["id"]) == sel_army:
			army = a
	if army.is_empty():
		return
	var v := _card()
	v.add_child(Kit.lbl("Orders for %s" % army["name"], 19, AF.GOLD_BRIGHT, true, "title_bold"))
	var cmd: Dictionary = army["commander"]
	v.add_child(Kit.lbl("Commander %s (%s). At %s. Morale %d%%, supply %.1f days." % [cmd["name"], cmd["personality"],
		_node_name(int(army["node"])), int(float(army["morale"]) * 100.0), float(army["supply"])], 15, AF.TEXT_DIM, true))
	var kinds := _flow()
	for k: Array in ORDER_KINDS:
		kinds.add_child(_chip(String(k[1]), sel_kind == String(k[0]), _set_kind.bind(String(k[0]))))
	v.add_child(kinds)
	if sel_kind == "retreat":
		v.add_child(Kit.lbl("Retreat type", 15, AF.GOLD))
		var rt := _flow()
		for r: String in RETREATS:
			rt.add_child(_chip(r.capitalize(), sel_retreat == r, _set_retreat.bind(r)))
		v.add_child(rt)
	v.add_child(Kit.lbl("Formation", 15, AF.GOLD))
	var fm := _flow()
	for f: String in FORMATIONS:
		fm.add_child(_chip(f.capitalize(), sel_formation == f, _set_formation.bind(f)))
	v.add_child(fm)
	var need := NEEDS_TARGET.has(sel_kind)
	if need:
		if sel_target >= 0:
			var eta: float = cm.call("estimated_arrival_hours", sel_army, sel_target)
			v.add_child(Kit.lbl("Target: %s%s" % [_node_name(sel_target), "" if eta < 0.0 else " (about %.0f h march)" % eta], 17, AF.TEXT, true))
		else:
			v.add_child(Kit.lbl("Tap a place on the map (or an intel report) to choose a target.", 16, AF.TEXT_DIM, true, "italic"))
	v.add_child(_btn("Send Order by Courier", _send_order, true, need and sel_target < 0))
	box.add_child(_framed(v, AF.GOLD))


func _select_army(id: int) -> void:
	sel_army = id
	_rebuild("war", true)


func _set_kind(k: String) -> void:
	sel_kind = k
	_rebuild("war", true)


func _set_retreat(r: String) -> void:
	sel_retreat = r
	_rebuild("war", true)


func _set_formation(f: String) -> void:
	sel_formation = f
	_rebuild("war", true)


func _set_target(node: int) -> void:
	sel_target = node
	_rebuild("war", true)


## A map tap: the campaign graph node nearest to that world position becomes the target.
func map_tapped(world_pos: Vector2) -> void:
	var cm := mod("campaign")
	if cm == null:
		return
	_set_target(int(cm.call("nearest_node", world_pos)))


func _send_order() -> Dictionary:
	var cm := mod("campaign")
	if cm == null or sel_army < 0:
		return {}
	var order := {"kind": sel_kind, "formation": sel_formation}
	if NEEDS_TARGET.has(sel_kind):
		if sel_target < 0:
			return {}
		order["target"] = sel_target
	else:
		for a: Dictionary in cm.call("player_armies"):
			if int(a["id"]) == sel_army:
				order["target"] = int(a["node"])
	if sel_kind == "retreat":
		order["retreat"] = sel_retreat
	var c: Dictionary = cm.call("issue_order", sel_army, order)
	if c.is_empty():
		_say("The order could not be sent.")
	else:
		_say("A courier rides out with your order (about %d hour%s)." % [int(c["eta_hours"]), "" if int(c["eta_hours"]) == 1 else "s"])
	_rebuild("war", true)
	return c


func _follow(index: int) -> void:
	var cm := mod("campaign")
	if cm == null:
		return
	var r: Dictionary = cm.call("follow_advice", index)
	_say("You follow your advisor's plan." if not r.is_empty() and not (r["courier"] as Dictionary).is_empty() else "There is no army to carry out that plan.")
	_rebuild("war", true)


func _refresh_overlay() -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var cm := mod("campaign")
	overlay.entries = overlay_entries()
	overlay.target_node_pos = cm.call("node_pos", sel_target) if cm != null and sel_target >= 0 else null
	overlay.queue_redraw()


# ---------------------------------------------------------------- map hosting ----

func _attach_map() -> void:
	if menu == null:
		return
	var hud: Object = menu.get("hud")
	var m: Variant = hud.get("world_map") if hud != null else null
	if not (m is Control):
		_placeholder.visible = true
		return
	_placeholder.visible = false
	_map = m
	_home = _map.get_parent()
	_home_index = _map.get_index()
	_map.set("embedded", true)
	if hud.has_method("get_discovery"):
		_map.set("discovery", hud.call("get_discovery"))
	_map.clip_contents = true
	_map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_home.move_child(_map, -1)
	if overlay == null or not is_instance_valid(overlay):
		overlay = Overlay.new()
		overlay.name = "RealmOverlay"
		overlay.map = _map
		overlay.on_tap = map_tapped
		_map.add_child(overlay)
		_map.connect("draw", overlay.queue_redraw)
	if not _hooked:
		_hooked = true
		_host.resized.connect(_place)
		menu.resized.connect(_place)
	_need_fit = true
	_place()
	if _map.visible:
		_map.call("refresh")
	else:
		_map.call("open")
	_map.set("place_filter", Callable())
	_map.set("quest_target", null)
	_place.call_deferred()


func _place() -> void:
	if _map == null or not is_instance_valid(_map) or _host.size.x < 32.0:
		return
	_map.global_position = _host.global_position
	_map.size = _host.size
	if _need_fit:
		_need_fit = false
		_map.call("fit_region")
	_map.queue_redraw()
	_refresh_overlay()


func _detach_map() -> void:
	if _map == null or not is_instance_valid(_map):
		_map = null
		return
	if overlay != null and is_instance_valid(overlay):
		if _map.is_connected("draw", overlay.queue_redraw):
			_map.disconnect("draw", overlay.queue_redraw)
		overlay.queue_free()
	overlay = null
	if _map.visible:
		_map.call("close")
	_map.set("embedded", false)
	_map.clip_contents = false
	if _home != null and is_instance_valid(_home) and _map.get_parent() == _home:
		_home.move_child(_map, mini(_home_index, _home.get_child_count() - 1))
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map = null


# --------------------------------------------------------------------- Diplomacy ----

func _fill_diplomacy(box: VBoxContainer) -> void:
	var fa := mod("factions")
	if fa == null:
		_empty(box)
		return
	box.add_child(Kit.section("Powers of the Realm"))
	var grid := _grid()
	box.add_child(grid)
	var n := 0
	for f: Dictionary in fa.call("factions"):
		var id := String(f["id"])
		if id == "player":
			continue
		n += 1
		var rel: Dictionary = fa.call("relation", "player", id)
		var wr: Dictionary = fa.call("war_rep", id)
		var v := _card()
		var head := HBoxContainer.new()
		head.add_child(Kit.lbl(String(f["name"]), 19, AF.TEXT, false, "title_bold"))
		head.add_child(Kit.hspacer())
		var stance := String(rel["stance"])
		head.add_child(Kit.lbl(stance.capitalize(), 17, STANCE_COL.get(stance, AF.TEXT), false, "title"))
		v.add_child(head)
		v.add_child(Kit.lbl("%s. Power %.0f. War reputation: %s." % [String(f["kind"]).capitalize(), float(f["power"]), wr["label"]], 15, AF.TEXT_DIM, true))
		v.add_child(_stat_bar("Trust", float(rel["trust"]) / 100.0, Kit.GREEN, str(int(rel["trust"]))))
		v.add_child(_stat_bar("Fear", float(rel["fear"]) / 100.0, Color("e0b45a"), str(int(rel["fear"]))))
		v.add_child(_stat_bar("Grievance", float(rel["grievance"]) / 100.0, Kit.BAD, str(int(rel["grievance"]))))
		v.add_child(_stat_bar("Trade", float(rel["trade"]) / 100.0, AF.GOLD, str(int(rel["trade"]))))
		grid.add_child(_framed(v))
	if n == 0:
		_empty(box)
	var mine: Dictionary = fa.call("war_rep", "player")
	box.add_child(Kit.lbl("Your war reputation: %s (%d acts of war)" % [mine["label"], int(mine["acts"])], 16, AF.GOLD, true))
	box.add_child(Kit.section("Paths to the Crown"))
	var paths: Dictionary = fa.call("kingship_paths")
	if paths.is_empty():
		_empty(box)
	for p: String in paths:
		var d: Dictionary = paths[p]
		var v2 := _card()
		v2.add_child(_stat_bar(p.capitalize(), float(d["progress"]) / 100.0, AF.GOLD, "%d%%" % int(d["progress"])))
		var notes: Array = d["notes"]
		if not notes.is_empty():
			v2.add_child(Kit.lbl(String(notes[-1]), 14, AF.TEXT_DIM, true, "italic"))
		box.add_child(v2)
	box.add_child(Kit.section("Marriages and Ties"))
	var ms: Array = fa.call("marriages")
	var ts: Array = fa.call("ties")
	if ms.is_empty() and ts.is_empty():
		_empty(box, "No marriages or known ties.")
	for m: Dictionary in ms:
		box.add_child(Kit.lbl("%s and %s wed (day %d)%s" % [_fname(String(m["a"])), _fname(String(m["b"])), int(m["day"]),
			", with an inheritance claim" if bool(m.get("claim", false)) else ""], 16, AF.TEXT, true))
	for t: Dictionary in ts:
		box.add_child(Kit.lbl("%s: %s and %s" % [String(t["kind"]).capitalize(), _fname(String(t["a"])), _fname(String(t["b"]))], 15, AF.TEXT_DIM, true))
	box.add_child(Kit.section("Sects and Independent Powers"))
	var sects: Array = fa.call("sects")
	if sects.is_empty():
		_empty(box, "No sects are known.")
	for s: Dictionary in sects:
		box.add_child(Kit.lbl("%s (%s), power %.0f" % [s["name"], String(s["kind"]).replace("_", " "), float(s["power"])], 16, AF.TEXT, true))
	box.add_child(Kit.section("News"))
	var news: Array = fa.call("news", 6)
	if news.is_empty():
		_empty(box, "No news has reached you.")
	for line: Variant in news:
		box.add_child(Kit.lbl(String(line), 15, AF.TEXT_DIM, true))


# -------------------------------------------------------------------------- Land ----

func _fill_land(box: VBoxContainer) -> void:
	var la := mod("land")
	var se := mod("settlements")
	if la == null and se == null:
		_empty(box)
		return
	if la != null:
		box.add_child(Kit.section("Regions"))
		var keys: Array = la.call("regions")
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(la.call("unrest", a)) > float(la.call("unrest", b)))
		if keys.is_empty():
			_empty(box)
		var grid := _grid()
		box.add_child(grid)
		var shown := 0
		for k: Variant in keys:
			if shown >= 40:
				break
			shown += 1
			var d: Dictionary = la.call("deed", k)
			var loy: float = la.call("loyalty", k)
			var un: float = la.call("unrest", k)
			var v := _card()
			var head := HBoxContainer.new()
			head.add_child(Kit.lbl(_region_name(k), 18, AF.TEXT, false, "title_bold"))
			head.add_child(Kit.hspacer())
			if se != null and String(k).is_valid_int():
				head.add_child(Kit.lbl(String(se.call("dominant", int(String(k)))).capitalize(), 15, AF.GOLD))
			v.add_child(head)
			v.add_child(_stat_bar("Loyalty", loy / 100.0, Kit.GREEN if loy >= 45.0 else Kit.BAD, str(int(loy))))
			v.add_child(_stat_bar("Unrest", un, Kit.BAD, "%d%%" % int(un * 100.0)))
			if not d.is_empty():
				var line := "%s land. Held by %s" % [String(d["kind"]).replace("_", " ").capitalize(), _fname(String(d["holder"]))]
				if bool(la.call("in_conflict", k)):
					line += ", occupied by %s" % _fname(String(d["occupier"]))
				v.add_child(Kit.lbl(line, 15, AF.TEXT_DIM, true))
			var reb: Dictionary = la.call("rebellion_at", k)
			if not reb.is_empty():
				v.add_child(Kit.lbl("Rebellion %s, led by %s" % [reb["status"], (reb["leader"] as Dictionary)["name"]], 16, Kit.BAD, true, "title"))
			grid.add_child(_framed(v, AF.RED if not reb.is_empty() else AF.GOLD_DIM))
	if se != null:
		box.add_child(Kit.section("Emergencies"))
		var es: Array = se.call("emergencies")
		if es.is_empty():
			_empty(box, "No emergencies. The settlements are quiet.")
		for e: Dictionary in es:
			var remaining := maxi(0, int(e["cost"]) - int(e["paid"]))
			var v2 := _card()
			v2.add_child(Kit.lbl("%s in %s" % [EMERGENCY_NAME.get(String(e["kind"]), String(e["kind"]).capitalize()), se.call("sname", int(e["sid"]))], 18, Kit.BAD, true, "title"))
			v2.add_child(Kit.lbl("About %d hours left. Severity %d%%." % [int(e["hours_left"]), int(float(e["severity"]) * 100.0)], 15, AF.TEXT_DIM, true))
			v2.add_child(_btn("Respond (%dg)" % remaining, _respond.bind(int(e["id"]), remaining), true, Game.gold < remaining or remaining <= 0))
			box.add_child(_framed(v2, AF.RED))
		box.add_child(Kit.section("While You Were Away"))
		var dg: Array = se.call("digest")
		if dg.is_empty():
			_empty(box, "Nothing to report.")
		for line2: Variant in dg:
			box.add_child(Kit.lbl(String(line2), 15, AF.TEXT_DIM, true))


func _respond(eid: int, gold: int) -> void:
	var se := mod("settlements")
	if se == null or gold <= 0 or Game.gold < gold:
		return
	Game.gold -= gold
	_say(String(se.call("respond", eid, gold)))
	_rebuild("land", true)


# --------------------------------------------------------------------- Followers ----

func _fill_followers(box: VBoxContainer) -> void:
	var fo := mod("followers")
	if fo == null:
		_empty(box)
		return
	box.add_child(Kit.section("Followers"))
	var list: Array = fo.call("list")
	if list.is_empty():
		_empty(box, "You have no followers yet.")
	var grid := _grid()
	box.add_child(grid)
	for f: Dictionary in list:
		var fid := String(f["id"])
		var v := _card()
		var head := HBoxContainer.new()
		head.add_child(Kit.lbl(String(f["name"]), 19, AF.TEXT, false, "title_bold"))
		head.add_child(Kit.hspacer())
		head.add_child(Kit.lbl(String(f["status"]).capitalize(), 15, AF.GOLD))
		v.add_child(head)
		v.add_child(Kit.lbl("%s, age %d. %s" % [String(f["occupation"]).capitalize(), int(f["age"]), ", ".join(PackedStringArray(f["traits"]))], 15, AF.TEXT_DIM, true))
		v.add_child(_stat_bar("Loyalty", float(f["loyalty"]) / 100.0, Kit.GREEN if float(f["loyalty"]) >= 40.0 else Kit.BAD, str(int(f["loyalty"]))))
		v.add_child(Kit.lbl("Post: %s" % (String(f["post"]).capitalize() if String(f["post"]) != "" else "none"), 15, AF.TEXT))
		if _msgs.has(fid):
			v.add_child(Kit.lbl(String(_msgs[fid]), 15, AF.GOLD_BRIGHT, true, "italic"))
		v.add_child(_btn("Summon", _summon.bind(fid), false, String(f["status"]) == "traveling"))
		grid.add_child(_framed(v))
	box.add_child(Kit.section("On the Road"))
	var arr: Array = fo.call("arrivals")
	if arr.is_empty():
		_empty(box, "No one is travelling to you.")
	for s: Dictionary in arr:
		var who: Dictionary = fo.call("get_follower", String(s["fid"]))
		box.add_child(Kit.lbl("%s is on the way. About %.0f hours left." % [who.get("name", "Someone"), float(s["hours_left"])], 16, AF.TEXT, true))
	box.add_child(Kit.section("Disputes"))
	var ds: Array = fo.call("disputes")
	if ds.is_empty():
		_empty(box, "No quarrels in the company.")
	for d: Dictionary in ds:
		var a: Dictionary = fo.call("get_follower", String(d["a"]))
		var b: Dictionary = fo.call("get_follower", String(d["b"]))
		box.add_child(Kit.lbl("%s and %s: %s (day %d)" % [a.get("name", "?"), b.get("name", "?"), String(d["kind"]).replace("_", " "), int(d["day"])], 15, AF.TEXT, true))
	box.add_child(Kit.section("Tamed Creatures"))
	var tm: Array = fo.call("tamed")
	if tm.is_empty():
		_empty(box, "You have tamed nothing yet.")
	var species: Variant = _const(fo, "SPECIES")
	for c: Dictionary in tm:
		var v2 := _card()
		v2.add_child(Kit.lbl("%s (%s)" % [String(c["name"]).capitalize(), String(c["species"]).replace("_", " ")], 18, AF.TEXT, true, "title"))
		v2.add_child(_stat_bar("Trust", float(c["trust"]), Kit.GREEN, "%d%%" % int(float(c["trust"]) * 100.0)))
		v2.add_child(Kit.lbl("Role: %s" % (String(c["role"]).capitalize() if String(c["role"]) != "" else "none"), 15, AF.TEXT_DIM))
		var roles := _flow()
		if species is Dictionary and (species as Dictionary).has(c["species"]):
			for role: String in ((species as Dictionary)[c["species"]] as Dictionary)["roles"]:
				roles.add_child(_chip(role.capitalize(), String(c["role"]) == role, _assign.bind(String(c["id"]), role)))
		v2.add_child(roles)
		box.add_child(_framed(v2))


func _summon(fid: String) -> void:
	var fo := mod("followers")
	if fo == null:
		return
	var r: Dictionary = fo.call("summon", fid, _player_pos())
	var txt := String(r.get("response", ""))
	if bool(r.get("ok", false)) and float(r.get("eta", 0.0)) > 0.0:
		txt += " (arrives in about %.0f h)" % float(r["eta"])
	_msgs[fid] = txt if txt != "" else "No answer."
	_rebuild("followers", true)


func _assign(cid: String, role: String) -> void:
	var fo := mod("followers")
	if fo == null:
		return
	var loc := "s0"
	var ca := mod("camps")
	if ca != null:
		loc = String(ca.call("nearest_node", _player_pos()))
	fo.call("assign_role", cid, role, loc)
	_rebuild("followers", true)


# ------------------------------------------------------------------ enterprise ----

## Summary page for the Bannerlord-style sandbox: what you own, what it earns, and the doors into the
## strategic map and the enterprise screen. Everything shown depends on your roles.
func _fill_enterprise(box: VBoxContainer) -> void:
	var en := mod("enterprise")
	if en == null:
		_empty(box)
		return
	var ci: Dictionary = en.call("clan_info")
	var head := _card()
	head.add_child(Kit.lbl("%s, a %s" % [ci["name"], ci["tier_name"]], 22, AF.GOLD_BRIGHT, false, "title"))
	head.add_child(Kit.lbl("You are known as: %s. %s" % [", ".join(en.call("roles")), String(ci["text"])], 16, AF.TEXT, true))
	head.add_child(_stat_bar("Renown", 1.0 if float(ci["next_renown"]) <= 0.0 else float(ci["renown"]) / float(ci["next_renown"]), AF.GOLD, "%d" % int(ci["renown"])))
	head.add_child(_stat_bar("Party", float(ci["party_size"]) / maxf(float(ci["party_limit"]), 1.0), Color("6fa8ff"), "%d / %d" % [int(ci["party_size"]), int(ci["party_limit"])]))
	box.add_child(_framed(head))
	var doors := _grid()
	var door_btns: Array = [_btn("Strategic map", open_strategic, true), _btn("Markets and trade routes", open_enterprise.bind("market")),
		_btn("Caravans", open_enterprise.bind("caravans")), _btn("Workshops", open_enterprise.bind("workshops")),
		_btn("Fief", open_enterprise.bind("fief")), _btn("Clan and troops", open_enterprise.bind("clan"))]
	for b: Button in door_btns:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		doors.add_child(b)
	box.add_child(doors)
	var own := _card()
	var cars: Array = en.call("list_caravans")
	own.add_child(Kit.lbl("Caravans: %d. Workshops: %d. Fiefs: %d. Troops: %d." % [cars.size(), (en.get("workshops") as Array).size(), (en.call("fief_ids") as Array).size(), int(en.call("troop_count"))], 17, AF.TEXT, true))
	for c: Dictionary in cars:
		own.add_child(Kit.lbl("%s: %s" % [c["name"], en.call("caravan_status", c)], 15, AF.TEXT_DIM, true))
	for w: Dictionary in en.get("workshops"):
		own.add_child(Kit.lbl("%s in %s: %+dg yesterday" % [String(w["kind"]).capitalize(), _node_name(int(w["sid"])), int(w["history"][-1]) if not (w["history"] as Array).is_empty() else 0], 15, AF.TEXT_DIM, true))
	var log: Array = en.get("log_lines")
	for line: String in log.slice(maxi(0, log.size() - 4)):
		own.add_child(Kit.lbl(line, 14, AF.TEXT_DIM, true, "italic"))
	box.add_child(_framed(own))
