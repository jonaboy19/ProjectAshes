extends PanelContainer
## Side panel of the War Map (the reference's "Selected Army" / "Army Management" column): commander
## and attributes, formations, Move / Split / Merge, the units list, the orders list with courier ETAs,
## intel with fading, and the engagement cards. Rebuilt only when the map's data or selection changes.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Tokens := preload("res://scripts/ui/war/war_tokens.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")

const TABS := [["units", "Units"], ["orders", "Orders"], ["intel", "Intel"], ["battles", "Battles"], ["part", "Your part"]]
const STANCE := {"line": "Balanced", "wedge": "Aggressive", "square": "Defensive", "skirmish": "Loose", "column": "Marching"}

var map: Control
var split_open := false
var split_n := 0
var details_open := false
var _title: Label
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _built := false


func _ready() -> void:
	add_theme_stylebox_override("panel", Kit.box(Color(0.043, 0.039, 0.035, 0.97), AF.GOLD_DIM, 0, 12))
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_title = Kit.lbl("SELECTED ARMY", 22, AF.GOLD, false, "title")
	v.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	v.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_box)
	_built = true
	rebuild()


# ---------------------------------------------------------------- pieces ----

## A round commander portrait: initial on the faction colour with a gold frame.
class Portrait extends Control:
	var initial := "?"
	var col := Color.BLUE

	func _init(letter: String, c: Color, side := 84.0) -> void:
		initial = letter
		col = c
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.06, 0.055, 0.05))
		var c := size * 0.5
		draw_circle(c + Vector2(0, size.y * 0.16), size.x * 0.34, col.darkened(0.25))
		draw_circle(c + Vector2(0, -size.y * 0.12), size.x * 0.2, Color("d9b48a"))
		draw_rect(Rect2(Vector2(size.x * 0.3, size.y * 0.02), Vector2(size.x * 0.4, size.y * 0.22)), col.lightened(0.1))
		var f := AF.title_font(700)
		var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.x * 0.34)).x
		draw_string(f, Vector2(c.x - w * 0.5, size.y * 0.9), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.x * 0.34), Color(1, 1, 1, 0.9))
		draw_rect(r, AF.GOLD, false, 2.0)


## A kind glyph with a number under it (the formations row).
class Tile extends Control:
	var kind := "infantry"
	var text := ""
	var on := false

	func _init(k: String, t: String, highlight := false) -> void:
		kind = k
		text = t
		on = highlight
		custom_minimum_size = Vector2(40, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 0.86, 0.55, 0.08 if not on else 0.2))
		draw_rect(r, AF.GOLD if on else AF.GOLD_DIM, false, 1.0)
		Tokens.glyph(self, kind, Vector2(size.x * 0.5, 20), 10.0, AF.GOLD_BRIGHT if on else AF.TEXT, 1.8)
		var f := AF.font(AF.BODY_FONT)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f, Vector2((size.x - w) * 0.5, 54), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, AF.TEXT)


## A unit of the selected army: glyph, name, men, strength bar, morale dot, current order.
class UnitRow extends Button:
	var u: Dictionary = {}
	var selected := false

	func _init(unit: Dictionary, sel: bool) -> void:
		u = unit
		selected = sel
		custom_minimum_size = Vector2(0, 66)
		focus_mode = Control.FOCUS_NONE
		flat = true
		for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(AF.row(selected, is_hovered()), r)
		if selected:
			draw_rect(r, AF.GOLD, false, 2.0)
		var can := bool(u.get("can_command", true))
		Tokens.glyph(self, String(u["kind"]), Vector2(30, size.y * 0.5), 12.0, AF.GOLD_BRIGHT if can else AF.TEXT_DIM, 2.0)
		var f := AF.font(AF.BODY_FONT)
		var nm := String(u["name"])
		draw_string(f, Vector2(58, 25), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x - 150.0, 19, AF.TEXT if can else AF.TEXT_DIM)
		var men := str(int(u["men"]))
		var w := f.get_string_size(men, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(f, Vector2(size.x - w - 44, 25), men, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, AF.GOLD_BRIGHT)
		var ratio := clampf(float(u["men"]) / maxf(1.0, float(u["max_men"])), 0.0, 1.0)
		var bw := size.x - 58.0 - 150.0
		draw_rect(Rect2(58, size.y - 24, bw, 9), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(58, size.y - 24, bw * ratio, 9), Color("5fae4c") if ratio > 0.5 else (Color("d8a84e") if ratio > 0.25 else Color("c2412f")))
		draw_rect(Rect2(58, size.y - 24, bw, 9), AF.GOLD_DIM, false, 1.0)
		var o: Dictionary = u["order"]
		var bn := String(o.get("then", o.get("behavior", "hold")))
		var state := String((WarUnits.behaviour(bn) as Dictionary)["name"])
		if int(u["eng"]) != 0:
			state = "In battle"
		elif not bool(u["detached"]):
			state = "With army"
		draw_string(f, Vector2(58 + bw + 8, size.y - 15), state, HORIZONTAL_ALIGNMENT_LEFT, 96, 15, AF.TEXT_DIM)
		var mc := Color("5fae4c") if float(u["morale"]) >= 0.6 else (Color("d8a84e") if float(u["morale"]) >= 0.35 else Color("c2412f"))
		draw_circle(Vector2(size.x - 20, 19), 6.0, mc)
		if not can:
			draw_string(f, Vector2(size.x - 34, size.y - 15), "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(AF.RED, 0.9))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()


# ---------------------------------------------------------------- helpers ----

func _card(border := AF.GOLD_DIM) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p := Kit.framed(v, Color(0.03, 0.028, 0.025, 0.72), border, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(p)
	return v


func _btn(text: String, cb: Callable, primary := false, disabled := false, h := 58.0) -> Button:
	var b := Kit.button(text, primary, h, 17)
	b.disabled = disabled
	b.pressed.connect(cb)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _line(parent: Control, text: String, size := 16, col := AF.TEXT) -> Label:
	var l := Kit.lbl(text, size, col, true)
	parent.add_child(l)
	return l


func _empty(text: String) -> void:
	_box.add_child(Kit.lbl(text, 17, AF.TEXT_DIM, true, "italic"))


func _bar(caption: String, ratio: float, col: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Kit.lbl(caption, 15, AF.TEXT_DIM)
	l.custom_minimum_size.x = 78
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Kit.bar(ratio, 20.0, col, text)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return h


func _plural_kinds(comp: Dictionary) -> String:
	var parts: Array = []
	for k: String in WarUnits.KIND_ORDER:
		if comp.has(k) and int(comp[k]) > 0:
			parts.append("%d %s" % [int(comp[k]), String((WarUnits.kind(k) as Dictionary)["name"]).to_lower()])
	return ", ".join(parts)


func rebuild() -> void:
	if not _built or map == null:
		return
	Kit.clear(_tabs)
	for t: Array in TABS:
		var b := Kit.tab_button(String(t[1]), String(t[0]) == String(map.tab), _pick_tab.bind(String(t[0])), 0.0)
		b.custom_minimum_size.y = 52
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(b)
	var keep := _scroll.scroll_vertical
	Kit.clear(_box)
	match String(map.tab):
		"orders":
			_title.text = "ORDERS AND COMMAND"
			_tab_orders()
		"intel":
			_title.text = "INTELLIGENCE"
			_tab_intel()
		"battles":
			_title.text = "ENGAGEMENTS"
			_tab_battles()
		"part":
			_title.text = "YOUR PART IN THE WAR"
			_tab_part()
		_:
			_title.text = "SELECTED ARMY"
			_tab_units()
	if keep > 0:
		_scroll.set_deferred("scroll_vertical", keep)


func _pick_tab(t: String) -> void:
	map.set_tab(t)


# ------------------------------------------------------------------ units ----

func _tab_units() -> void:
	if map.cm == null:
		_empty("The war room is empty. No campaign is underway.")
		return
	var army: Dictionary = map.armies.get(map.sel_army, {})
	if army.is_empty():
		_empty("You command no armies yet.")
		return
	var aid := int(army["id"])
	var cmdr: Dictionary = map.cm.call("army_command", aid)
	var c: Dictionary = cmdr.get("commander", {})
	var units: Array = army.get("piece_list", [])
	# army switcher when there is more than one
	if map.armies.size() > 1:
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 6)
		fl.add_theme_constant_override("v_separation", 6)
		for id: int in map.armies:
			var a2: Dictionary = map.armies[id]
			var b := Kit.tab_button(String(a2["name"]), id == aid, map.select_army.bind(id, true), 0.0)
			b.custom_minimum_size.y = 46
			fl.add_child(b)
		_box.add_child(fl)
	# army card
	var card := _card(AF.GOLD)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	card.add_child(top)
	top.add_child(Portrait.new(String(c.get("name", "?")).substr(0, 1), Tokens.faction_color("player")))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(Kit.lbl(String(army["name"]), 20, AF.GOLD_BRIGHT, false, "title_bold"))
	var men := int(army["strength"])
	info.add_child(Kit.lbl("%s / %s men" % [_th(men), _th(int(army["max_strength"]))], 17, AF.TEXT))
	var bar := Kit.bar(float(men) / maxf(1.0, float(army["max_strength"])), 10.0, Color("5fae4c"))
	info.add_child(bar)
	info.add_child(Kit.lbl("Commander: %s (%s)" % [c.get("name", "?"), c.get("personality", "?")], 16, AF.TEXT_DIM))
	var attrs := VBoxContainer.new()
	attrs.add_theme_constant_override("separation", 0)
	card.add_child(attrs)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 0)
	for kv: Array in [["Tactics", "tactics"], ["Leadership", "leadership"], ["Logistics", "logistics"], ["Discipline", "discipline"], ["Scouting", "scouting"], ["Command", "capacity"]]:
		var val: Variant = c.get(kv[1], 0)
		g.add_child(Kit.lbl("%s  %s" % [kv[0], _th(int(val)) if kv[1] == "capacity" else str(int(val))], 16, AF.TEXT))
	card.add_child(g)
	var morale := float(army["morale"])
	var mrow := HBoxContainer.new()
	mrow.add_child(Kit.lbl("Morale: ", 16, AF.TEXT_DIM))
	mrow.add_child(Kit.lbl(Tokens.level_word(morale), 16, Color("7fd18b") if morale >= 0.6 else (Color("e0b45a") if morale >= 0.35 else Color("e0685a"))))
	mrow.add_child(Kit.hspacer())
	var load := float(c.get("load", 0.0))
	mrow.add_child(Kit.lbl("Command load %d%%" % int(load * 100.0), 15, AF.TEXT if load <= 1.0 else Color("e0685a")))
	card.add_child(mrow)
	card.add_child(_btn("Details" if not details_open else "Hide details", _toggle_details, false, false, 46.0))
	if details_open:
		for s: Dictionary in cmdr.get("subs", []):
			var sl := Kit.lbl("%s, %s wing (%s): %s men, %d%% of command capacity. Tactics %d." % [s["name"], s["wing"], s["personality"], _th(int(s["men"])), int(float(s["load"]) * 100.0), int(s["tactics"])], 15, AF.TEXT, true)
			card.add_child(sl)
	# formations
	_box.add_child(Kit.section("Formations", 17))
	var comp: Dictionary = {}
	for p: Dictionary in units:
		comp[String(p["kind"])] = int(comp.get(String(p["kind"]), 0)) + int(p["men"])
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 5)
	fr.add_theme_constant_override("v_separation", 5)
	var sel_kind := ""
	if map.sel_units.size() == 1:
		for p2: Dictionary in units:
			if int(p2["id"]) == int(map.sel_units[0]):
				sel_kind = String(p2["kind"])
	for k: String in WarUnits.KIND_ORDER:
		if comp.has(k):
			fr.add_child(Tile.new(k, str(int(comp[k])), k == sel_kind))
	_box.add_child(fr)
	# actions
	var one: bool = map.sel_units.size() == 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_btn("Move", map.begin_target_mode, map.target_mode))
	row.add_child(_btn("Split", _toggle_split, split_open, not one))
	row.add_child(_btn("Merge", map.do_merge, false, map.sel_units.is_empty()))
	_box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	var detached := false
	for p3: Dictionary in map.selected_pieces():
		detached = detached or bool(p3["detached"])
	row2.add_child(_btn("All units", _select_all.bind(aid), false, false, 50.0))
	row2.add_child(_btn("Detach", map.do_detach, false, not one, 50.0))
	row2.add_child(_btn("Rejoin", map.do_attach, false, not (one and detached), 50.0))
	_box.add_child(row2)
	if split_open and one:
		_split_card()
	var stance := String(STANCE.get(String(army["formation"]), "Balanced"))
	var line := Kit.lbl("Stance: %s     Supplies: %.1f days" % [stance, float(army["supply"])], 16, AF.TEXT_DIM)
	_box.add_child(line)
	# units
	_box.add_child(Kit.section("Units", 17))
	if units.is_empty():
		_empty("No formations.")
	for p4: Dictionary in units:
		var r := UnitRow.new(p4, map.sel_units.has(int(p4["id"])))
		r.pressed.connect(_pick_unit.bind(int(p4["id"])))
		_box.add_child(r)
	if map.sel_units.size() == 1:
		_unit_card(map.sel_units[0])


func _th(n: int) -> String:
	var s := str(n)
	return s if n < 1000 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]


func _toggle_details() -> void:
	details_open = not details_open
	rebuild()


func _toggle_split() -> void:
	split_open = not split_open
	split_n = 0
	rebuild()


func _select_all(aid: int) -> void:
	var ids: Array = []
	for p: Dictionary in (map.armies[aid] as Dictionary).get("piece_list", []):
		ids.append(int(p["id"]))
	map.select_units(ids)


func _pick_unit(id: int) -> void:
	if map.sel_units.has(id) and map.sel_units.size() >= 1 and Input.is_key_pressed(KEY_SHIFT):
		var s: Array = map.sel_units.duplicate()
		s.erase(id)
		map.select_units(s)
	elif Input.is_key_pressed(KEY_SHIFT) or (map.sel_units.size() > 1 and map.sel_units.has(id) == false and Input.is_key_pressed(KEY_CTRL)):
		var s2: Array = map.sel_units.duplicate()
		s2.append(id)
		map.select_units(s2)
	else:
		map.select_units([id], true)


func _unit_card(id: int) -> void:
	var u: Dictionary = map.cm.call("unit", int(id))
	if u.is_empty():
		return
	var v := _card(AF.GOLD)
	var k: Dictionary = WarUnits.kind(String(u["kind"]))
	v.add_child(Kit.lbl(String(u["name"]), 20, AF.GOLD_BRIGHT, false, "title_bold"))
	v.add_child(Kit.lbl(String(k["name"]), 15, AF.TEXT_DIM, false, "italic"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	for kv: Array in [["Men", "%s / %s" % [_th(int(u["men"])), _th(int(u["max_men"]))]], ["Experience", Tokens.quality_word(float(u["quality"]))],
			["Morale", Tokens.level_word(float(u["morale"]))], ["Stamina", "%d%%" % int((1.0 - float(u["fatigue"])) * 100.0)],
			["Leader", String(u["commander_name"])], ["Temper", String(u["personality"]).capitalize()]]:
		g.add_child(Kit.lbl("%s: %s" % [kv[0], kv[1]], 16, AF.TEXT))
	v.add_child(g)
	var o: Dictionary = u["order"]
	var bn := String(o.get("behavior", "hold"))
	var bname := String((WarUnits.behaviour(String(o.get("then", bn))) as Dictionary)["name"])
	var where := "with the army" if not bool(u["detached"]) else "on its own, in %s" % String(u["terrain"]).to_lower()
	v.add_child(Kit.lbl("Order: %s. %s." % [bname if not bool(u["detached"]) else ("March, then " + bname.to_lower() if bn == "march" else bname), where.capitalize()], 15, AF.TEXT_DIM, true))
	var can: Dictionary = map.cm.call("can_command", int(id))
	if bool(can["ok"]):
		var src := String(can["source"])
		v.add_child(Kit.lbl("You command this unit (%s)." % {"personal": "your own troops", "appointed": "campaign appointment", "rank": "by your rank"}.get(src, src), 14, Color("7fd18b")))
	else:
		v.add_child(Kit.lbl(String(can["reason"]), 14, Color("e0b45a"), true))


func _split_card() -> void:
	var id: int = int(map.sel_units[0])
	var u: Dictionary = map.cm.call("unit", id)
	if u.is_empty():
		return
	var men := int(u["men"])
	if split_n <= 0 or split_n > men - 5:
		split_n = clampi(int(round(float(men) * 0.4 / 5.0)) * 5, 5, maxi(5, men - 5))
	var v := _card(AF.GOLD)
	v.add_child(Kit.lbl("Split Unit: %s (%d men)" % [u["name"], men], 18, AF.GOLD_BRIGHT, false, "title"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var minus := _btn("-", _step_split.bind(-10), false, false, 58.0)
	minus.custom_minimum_size.x = 70
	minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(minus)
	var lab := Kit.lbl("%d" % split_n, 26, AF.TEXT, false, "title")
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	var plus := _btn("+", _step_split.bind(10), false, false, 58.0)
	plus.custom_minimum_size.x = 70
	plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(plus)
	v.add_child(row)
	var sl := HSlider.new()
	sl.min_value = 5
	sl.max_value = maxi(6, men - 5)
	sl.step = 5
	sl.value = split_n
	sl.custom_minimum_size = Vector2(0, 36)
	sl.value_changed.connect(_slide_split)
	v.add_child(sl)
	v.add_child(Kit.lbl("Leaves %d with the parent and %d in the new piece." % [men - split_n, split_n], 15, AF.TEXT_DIM, true))
	v.add_child(_btn("Confirm", _confirm_split, true))


func _step_split(d: int) -> void:
	split_n += d
	rebuild()


func _slide_split(val: float) -> void:
	split_n = int(val)
	# do not rebuild while dragging the slider


func _confirm_split() -> void:
	var n := split_n
	split_open = false
	split_n = 0
	map.do_split(n)


# ------------------------------------------------------------------ orders ----

func _tab_orders() -> void:
	if map.cm == null:
		_empty("No campaign.")
		return
	var sc: Dictionary = map.scope
	var v := _card(AF.GOLD)
	v.add_child(Kit.lbl("Your authority", 18, AF.GOLD_BRIGHT, false, "title"))
	var rank_title := String(sc.get("rank_title", ""))
	v.add_child(Kit.lbl("Rank: %s" % (rank_title if rank_title != "" else "none"), 16, AF.TEXT))
	v.add_child(Kit.lbl("You can order %s men in %d pieces. Practical command: %s men." % [_th(int(sc.get("men", 0))), (sc.get("units", []) as Array).size(), _th(int(sc.get("capacity", 0)))], 16, AF.TEXT, true))
	var ov := float(sc.get("overload", 0.0))
	if ov > 0.0:
		v.add_child(Kit.lbl("Overstretched: orders will be slow and may be misread.", 15, Color("e0b45a"), true))
	v.add_child(Kit.lbl("Other troops answer to their own commanders. You can ask for help; their superior decides.", 14, AF.TEXT_DIM, true, "italic"))
	_box.add_child(Kit.section("Orders on the road", 17))
	if map.orders.is_empty():
		_empty("No orders have been sent.")
	var ords: Array = map.orders.duplicate()
	ords.reverse()
	for o: Dictionary in ords.slice(0, 14):
		var oc := _card(AF.GOLD_DIM)
		var head := HBoxContainer.new()
		head.add_child(Kit.lbl("%s: %s" % [o["behavior_name"], o["name"]], 17, AF.TEXT, true))
		head.add_child(Kit.hspacer())
		var col := AF.GOLD_BRIGHT
		match String(o["state"]):
			"acked":
				col = Color("7fd18b")
			"silent":
				col = Color("e0685a")
			"awaiting":
				col = Color("e0b45a")
		oc.add_child(head)
		oc.add_child(Kit.lbl(String(o["text"]) + ("  (a request)" if bool(o["requested"]) else ""), 15, col, true))
		if float(o["mult"]) > 1.05:
			oc.add_child(Kit.lbl("Slowed by an overstretched command (x%.1f)." % float(o["mult"]), 14, Color("e0b45a"), true))
	_box.add_child(Kit.section("Pieces in the field", 17))
	var any := false
	for p: Dictionary in map.pieces:
		if not bool(p["detached"]):
			continue
		any = true
		var bn := String((p["order"] as Dictionary).get("behavior", "hold"))
		var r := Kit.row("%s" % p["name"], "", String((WarUnits.behaviour(bn) as Dictionary)["name"]), "", 52.0, false)
		r.pressed.connect(map.select_units.bind([int(p["id"])], true))
		_box.add_child(r)
	if not any:
		_empty("Every formation marches with its army.")


# ------------------------------------------------------------------- intel ----

func _tab_intel() -> void:
	if map.cm == null:
		_empty("No campaign.")
		return
	_box.add_child(Kit.lbl("Only what your scouts have seen. Markers keep their last known place and grow uncertain with time.", 15, AF.TEXT_DIM, true, "italic"))
	if map.enemies.is_empty():
		_empty("No enemy movements are known. Send scouts.")
	var list: Array = map.enemies.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age_hours"]) < int(b["age_hours"]))
	var here := Vector2.ZERO
	var army: Dictionary = map.armies.get(map.sel_army, {})
	if not army.is_empty():
		here = army["pos"] as Vector2
	for e: Dictionary in list:
		var sel := String(e["key"]) == String(map.sel_enemy)
		var d := (e["pos"] as Vector2).distance_to(here) / 1000.0
		var right := "in sight" if bool(e["live"]) else "%d h ago" % int(e["age_hours"])
		var r := Kit.row("%s" % ("Force, %s men" % (str(int(e["est_max"])) if bool(e["exact"]) else "%d-%d" % [int(e["est_min"]), int(e["est_max"])])), "", right, "", 60.0, true)
		r.set_selected(sel)
		r.pressed.connect(map.select_enemy.bind(String(e["key"]), true))
		_box.add_child(r)
		if sel:
			var v := _card(AF.GOLD)
			v.add_child(Kit.lbl(String(e["label"]), 17, AF.TEXT, true))
			v.add_child(Kit.lbl("%.1f km from the selected army. Ground: %s." % [d, String(map.cm.call("terrain_at", e["pos"])["name"])], 15, AF.TEXT_DIM, true))
			if not (e["comp"] as Dictionary).is_empty():
				v.add_child(Kit.lbl("Confirmed by scouts%s: %s." % ["" if int(e["comp_age"]) <= 0 else " %d h ago" % int(e["comp_age"]), _plural_kinds(e["comp"])], 15, Color("7fd18b") if int(e["comp_age"]) <= 0 else Color("e0b45a"), true))
			else:
				v.add_child(Kit.lbl("Composition unknown%s. Send scouts to confirm." % (", possibly mounted" if bool(e["mounted"]) else ""), 15, Color("e0b45a"), true))
			if float(e["radius"]) > 60.0:
				v.add_child(Kit.lbl("It could have moved up to %.1f km since." % (float(e["radius"]) / 1000.0), 15, AF.TEXT_DIM, true))
			v.add_child(_bar("Confidence", float(e["confidence"]), AF.GOLD, "%d%%" % int(float(e["confidence"]) * 100.0)))
	_box.add_child(Kit.section("War Council", 17))
	var advice: Array = map.cm.call("council_advice")
	if advice.is_empty():
		_empty("Your advisors have no counsel yet.")
	for ad: Dictionary in advice:
		var ac := _card()
		ac.add_child(Kit.lbl("%s, %s (%s)" % [ad["advisor"], ad["role"], ad["personality"]], 16, AF.GOLD_BRIGHT, true, "title"))
		ac.add_child(Kit.lbl(String(ad["text"]), 15, AF.TEXT, true))
		ac.add_child(_bar("Confidence", float(ad["confidence"]), AF.GOLD, "%d%%" % int(float(ad["confidence"]) * 100.0)))
		ac.add_child(_btn("Follow", map.follow_advice.bind(int(ad["index"])), false, map.armies.is_empty(), 50.0))


# ------------------------------------------------------------------ your part ----

const NATION_COL := {"war": Color("e0433a"), "truce": Color("7fd18b"), "peace": Color("e0b45a")}


## "Your part in the war": diplomacy at the borders, plain-text leads, and every action the character can take
## (gated by role, rank, relations and gold; a gated one says why). Nothing here is a map marker.
func _tab_part() -> void:
	var wi: RefCounted = map.call("influence")
	var war: Variant = wi.call("war")
	if war == null:
		_empty("No war or diplomacy data is available.")
		return
	if String(map.status_text) != "":
		_box.add_child(Kit.lbl(String(map.status_text), 16, AF.GOLD_BRIGHT, true, "italic"))
	_box.add_child(Kit.section("Borders and courts", 17))
	for n: Dictionary in war.all_diplomacy():
		var v := _card(AF.GOLD if bool(n["at_war"]) else AF.GOLD_DIM)
		var head := HBoxContainer.new()
		head.add_child(Kit.lbl(String(n["name"]), 19, AF.GOLD_BRIGHT, false, "title_bold"))
		head.add_child(Kit.hspacer())
		var st := String(n["state"])
		head.add_child(Kit.lbl(st.capitalize() if st != "truce" else "Truce, %d days" % int(n["truce_days"]), 16, NATION_COL.get(st, AF.TEXT), false, "title"))
		v.add_child(head)
		v.add_child(_bar("Tension", float(n["tension"]) / 100.0, Color("c2412f") if float(n["tension"]) > 60.0 else Color("e0b45a"), str(int(n["tension"]))))
		for reason: String in (n["reasons"] as Array):
			_line(v, "Reason to fight: " + reason, 15, AF.TEXT_DIM)
		if (n["reasons"] as Array).is_empty() and st != "war":
			_line(v, "No quarrel with a cause, only old grudges.", 15, AF.TEXT_DIM)
		for h: String in (n["hostages"] as Array):
			_line(v, "Hostage held: %s." % h, 15, AF.TEXT_DIM)
	if war.is_at_war():
		var wc := _card(AF.GOLD)
		wc.add_child(Kit.lbl("The war: day %d, for %s" % [war.war_day(), String(war.war.get("goal", "tribute"))], 17, AF.TEXT, true))
		wc.add_child(_bar("Crown weary", clampf(war.exhaustion(), 0.0, 1.0), Color("5fae4c"), "%d%%" % int(war.exhaustion() * 100.0)))
		wc.add_child(_bar("Enemy weary", clampf(war.enemy_exhaustion(), 0.0, 1.0), Color("c2412f"), "%d%%" % int(war.enemy_exhaustion() * 100.0)))
	var leads: Array = wi.call("leads")
	if not leads.is_empty():
		_box.add_child(Kit.section("Word on the road", 17))
		for l: String in leads:
			_box.add_child(Kit.lbl(l, 15, AF.TEXT, true, "italic"))
	_box.add_child(Kit.section("What you can do", 17))
	for a: Dictionary in wi.call("actions"):
		var c := _card(AF.GOLD if bool(a["ok"]) else AF.GOLD_DIM)
		var h2 := HBoxContainer.new()
		h2.add_child(Kit.lbl(String(a["label"]), 17, AF.GOLD_BRIGHT if bool(a["ok"]) else AF.TEXT_DIM, false, "title_bold"))
		h2.add_child(Kit.hspacer())
		if int(a["cost"]) > 0:
			h2.add_child(Kit.lbl("%d gold" % int(a["cost"]), 15, AF.TEXT_DIM))
		c.add_child(h2)
		c.add_child(Kit.lbl(String(a["blurb"]), 14, AF.TEXT_DIM, true))
		if not bool(a["ok"]):
			c.add_child(Kit.lbl(String(a["reason"]), 15, Color("e0b45a"), true, "italic"))
			continue
		_action_buttons(c, String(a["id"]), wi)
	var log: Array = war.act_log
	if not log.is_empty():
		_box.add_child(Kit.section("What you have done", 17))
		for i in range(log.size() - 1, maxi(-1, log.size() - 5), -1):
			_box.add_child(Kit.lbl("Day %d: %s" % [int(log[i]["day"]), String(log[i]["text"])], 14, AF.TEXT_DIM, true))


func _action_buttons(c: Control, id: String, wi: RefCounted) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	match id:
		"supply_army":
			var goods: Dictionary = wi.call("supply_goods")
			for g: String in goods:
				row.add_child(_btn("Sell %d %s" % [mini(int(goods[g]), 5), g.replace("_", " ")], map.do_war_action.bind(id, {"good": g, "qty": 5}), false, false, 50.0))
		"run_caravan":
			var goods2: Dictionary = wi.call("supply_goods")
			for g2: String in goods2:
				row.add_child(_btn("Haul %s" % g2.replace("_", " "), map.do_war_action.bind(id, {"good": g2, "qty": 5}), false, false, 50.0))
			if goods2.is_empty():
				row.add_child(_btn("Send a company caravan", map.do_war_action.bind(id, {"caravan_id": 1}), false, false, 50.0))
		"broker_peace":
			for t: String in ["lenient", "fair", "harsh"]:
				row.add_child(_btn(t.capitalize(), map.do_war_action.bind(id, {"terms": t}), t == "fair", false, 50.0))
		"push_goal":
			for g3: String in ["land", "tribute", "hostages", "marriage"]:
				row.add_child(_btn(g3.capitalize(), map.do_war_action.bind(id, {"goal": g3}), false, false, 50.0))
		"raise_militia":
			row.add_child(_btn("40 men", map.do_war_action.bind(id, {"men": 40}), true, false, 50.0))
			row.add_child(_btn("80 men", map.do_war_action.bind(id, {"men": 80}), false, false, 50.0))
		_:
			row.add_child(_btn("Do it", map.do_war_action.bind(id, {}), true, false, 50.0))
	c.add_child(row)


# ----------------------------------------------------------------- battles ----

func _tab_battles() -> void:
	if map.cm == null:
		_empty("No campaign.")
		return
	for sv: Dictionary in map.cm.call("sieges"):
		var sc := _card(AF.GOLD)
		sc.add_child(Kit.lbl("Siege of %s" % String(sv["name"]), 19, AF.GOLD_BRIGHT, true))
		sc.add_child(Kit.lbl("Day %d. Walls: %s. Garrison ~%d. Supplies %d days. Morale %s." % [int(sv["day"]), String(sv["walls"]), int(round(float(sv["garrison"]) / 10.0)) * 10, int(round(float(sv["food_days"]))), String(sv["morale_label"])], 15, AF.TEXT, true))
		sc.add_child(_btn("Open siege map", map.open_siege.bind(String(sv["key"])), true, false, 54.0))
	if map.engs.is_empty():
		_empty("No engagements. When your pieces meet the enemy the fight appears here and on the map.")
	var list: Array = map.engs.duplicate()
	list.reverse()
	for g: Dictionary in list:
		var sel := int(g["id"]) == int(map.sel_eng)
		var col: Color = map.STATUS_COL.get(String(g["status"]), AF.GOLD)
		var v := _card(AF.GOLD if sel else AF.GOLD_DIM)
		var head := Button.new()
		head.flat = true
		head.text = String(g["name"])
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.focus_mode = Control.FOCUS_NONE
		head.custom_minimum_size = Vector2(0, 48)
		head.add_theme_font_override("font", AF.title_font(700))
		head.add_theme_font_size_override("font_size", 19)
		head.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
		head.pressed.connect(map.select_engagement.bind(int(g["id"]), true))
		v.add_child(head)
		if not bool(g["player_involved"]):
			v.add_child(Kit.lbl("Not your battle. You only know it is happening.", 15, AF.TEXT_DIM, true, "italic"))
		v.add_child(Kit.lbl("Your forces:", 15, AF.GOLD))
		v.add_child(Kit.lbl(_plural_kinds(g["your_forces"]) if not (g["your_forces"] as Dictionary).is_empty() else "none left", 16, AF.TEXT, true))
		v.add_child(Kit.lbl("Enemy estimate:", 15, AF.GOLD))
		var est := "%d men" % int(g["enemy_max"]) if bool(g["enemy_exact"]) else "%d-%d men" % [int(g["enemy_min"]), int(g["enemy_max"])]
		var comp: Dictionary = g["enemy_comp"]
		var et := est
		if not comp.is_empty() and bool(g["enemy_exact"]):
			et = _plural_kinds(comp)
		elif not comp.is_empty():
			et = "%s (%s)" % [est, _plural_kinds(comp)]
		if bool(g["enemy_unknown_support"]) and not bool(g["enemy_exact"]):
			et += ", unknown support"
		v.add_child(Kit.lbl(et, 16, AF.TEXT, true))
		v.add_child(Kit.lbl("Commander: %s" % (String(g["commander"]) if String(g["commander"]) != "" else "none"), 16, AF.TEXT))
		var stat := String(g["status"]).capitalize()
		if String(g["status"]) == "ended":
			stat = {"stalemate": "Ended, drawn apart"}.get(String(g["outcome"]), "Ended: %s" % ("you won" if String(g["outcome"]) == String(g["player_side"]) else "you lost"))
		var srow := HBoxContainer.new()
		srow.add_child(Kit.lbl("Status: ", 16, AF.TEXT_DIM))
		srow.add_child(Kit.lbl("%s%s" % [stat, " (you command)" if String(g["control"]) == "player" and String(g["status"]) != "ended" else ""], 17, col))
		v.add_child(srow)
		v.add_child(_bar("Advantage", float(g["ratio_player"]), Color("5fae4c") if float(g["ratio_player"]) >= 0.5 else Color("c2412f"), "%d%%" % int(float(g["ratio_player"]) * 100.0)))
		v.add_child(Kit.lbl("After %d h. You lost %d, they lost %d." % [int(g["hours"]), int(g["casualties_player"]), int(g["casualties_enemy"])], 15, AF.TEXT_DIM, true))
		if bool(g["player_involved"]) and String(g["status"]) != "ended":
			v.add_child(_btn("Command battle", map.open_tactical.bind(int(g["id"])), true, false, 56.0))
		if sel:
			var fp: Dictionary = (g["factors"] as Dictionary).get(String(g["player_side"]), {})
			var fe: Dictionary = (g["factors"] as Dictionary).get("b" if String(g["player_side"]) == "a" else "a", {})
			if not fp.is_empty() and not fe.is_empty():
				v.add_child(Kit.lbl("Why (you vs them): terrain %.2f/%.2f, quality %.2f/%.2f, morale %.2f/%.2f, commander %.2f/%.2f, numbers %.2f/%.2f, supply %.2f/%.2f, ground %s." % [
					fp.get("terrain", 1.0), fe.get("terrain", 1.0), fp.get("quality", 1.0), fe.get("quality", 1.0), fp.get("morale", 1.0), fe.get("morale", 1.0),
					fp.get("commander", 1.0), fe.get("commander", 1.0), fp.get("numbers", 1.0), fe.get("numbers", 1.0), fp.get("supply", 1.0), fe.get("supply", 1.0),
					String(map.cm.call("terrain", String(g["terrain"]))["name"]).to_lower()], 14, AF.TEXT_DIM, true))
			for ln: String in (g["log"] as Array).slice(-4):
				v.add_child(Kit.lbl(ln, 14, AF.TEXT_DIM, true, "italic"))
			if bool(g["player_involved"]) and String(g["status"]) != "ended":
				var br := HBoxContainer.new()
				br.add_theme_constant_override("separation", 6)
				var mine := String(g["control"]) == "player"
				br.add_child(_btn("Leave to commander" if mine else "Take command", map.do_intervene.bind("leave_command" if mine else "take_command"), false, false, 54.0))
				br.add_child(_btn("Press", map.do_intervene.bind("press"), false, false, 54.0))
				br.add_child(_btn("Withdraw", map.do_intervene.bind("withdraw"), false, false, 54.0))
				v.add_child(br)
