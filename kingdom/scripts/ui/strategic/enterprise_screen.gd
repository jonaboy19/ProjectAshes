extends Control
## Enterprise screen: everything a merchant, lord or captain does with money and men, in six tabs.
##   Market    per-town prices, your trade pack, bulk buy and sell, rumours and informants
##   Routes    trade-route planner: pick towns, see profit, days, risk, tolls; mend or build roads
##   Caravans  fund a caravan (leader, guards, capital), route or "leader chooses", reports
##   Workshops buy and run workshops that burn the town's real stock
##   Fief      taxes, projects built by a crew, garrison, governor, loyalty / prosperity / security
##   Clan      renown and influence, party size, recruits, mercenary contracts, vassalage, duties
## It reads and acts through the realm "enterprise" module (scripts/realm/enterprise*.gd) and never
## ticks anything. Gold moves through the module's ledger; after each action this screen settles it
## into the purse. Rebuilt on open, on a tab or town switch and after an action.

signal closed
signal show_map
signal route_preview(stops: Array)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const D := preload("res://scripts/realm/enterprise_data.gd")

const TABS := [["market", "Market"], ["routes", "Routes"], ["caravans", "Caravans"], ["workshops", "Workshops"], ["fief", "Fief"], ["clan", "Clan"]]
const TOUCH_H := 56.0
const GOOD := Color("7fd18b")
const BAD := Color("e0685a")
const WARN := Color("e0b45a")

var realm_override: RefCounted = null
var embedded := false
var tab := "market"
var sid := -1
var status := ""
var qty: Dictionary = {}
var plan_stops: Array = []
var plan_loop := false
var plan_guards := 2
var plan_capital := 300
var car_leader := ""
var car_guards := 2
var car_capital := 300
var car_route_mode := "leader"
var fief_sid := -1

var _vbox: VBoxContainer
var _head: HBoxContainer
var _tabs_row: HFlowContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _status_lbl: Label
var _gold_lbl: Label
var _built := false
var _cols_built := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if sid < 0:
		sid = _nearest()
	rebuild()


static func open_modal(host: Node, realm: RefCounted = null, start_tab := "market", at_sid := -1) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 72
	layer.name = "EnterpriseLayer"
	var m: Control = load("res://scripts/ui/strategic/enterprise_screen.gd").new()
	m.set("realm_override", realm)
	m.set("tab", start_tab)
	m.set("sid", at_sid)
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


func _nearest() -> int:
	var e := ent()
	return int(e.call("nearest_settlement", e.call("player_pos"))) if e != null else 0


func _gname(g: String) -> String:
	return String((D.GOODS.get(g, {"name": g}) as Dictionary)["name"])


func _sname(i: int) -> String:
	return WorldGen.display_name(String(WorldGen.settlements[i]["name"])) if i >= 0 and i < WorldGen.settlements.size() else "the road"


# ------------------------------------------------------------------ frame ----

func _build() -> void:
	if _built:
		return
	_built = true
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.018, 0.015, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	m.add_child(_vbox)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 8)
	_vbox.add_child(_head)
	_tabs_row = HFlowContainer.new()
	_tabs_row.add_theme_constant_override("h_separation", 6)
	_tabs_row.add_theme_constant_override("v_separation", 6)
	_vbox.add_child(_tabs_row)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_box)
	_status_lbl = Kit.lbl("", 16, AF.GOLD_BRIGHT, true, "italic")
	_vbox.add_child(_status_lbl)


func _btn(text: String, cb: Callable, primary := false, disabled := false, h := TOUCH_H) -> Button:
	var b := Kit.button(text, primary, h, 16)
	b.disabled = disabled
	b.pressed.connect(cb)
	return b


func _chip(text: String, on: bool, cb: Callable, w := 0.0) -> Button:
	var b := Kit.tab_button(text, on, cb, w)
	b.custom_minimum_size.y = 48
	return b


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _card() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _framed(v: Control, border := AF.GOLD_DIM) -> PanelContainer:
	var p := Kit.framed(v, Color(0.05, 0.045, 0.04, 0.85), border, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _want_cols() -> int:
	var w := minf(size.x if size.x > 8.0 else 99999.0, get_viewport_rect().size.x if is_inside_tree() else 99999.0)
	return 2 if w >= 860.0 else 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built and _want_cols() != _cols_built:
		rebuild()


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = _want_cols()
	_cols_built = g.columns
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _stepper(value: int, small: int, big: int, lo: int, hi: int, cb: Callable, suffix := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for d: int in [-big, -small]:
		var b := _btn("%+d" % d, func() -> void: cb.call(clampi(value + d, lo, hi)), false, value <= lo, 48.0)
		b.custom_minimum_size.x = 56
		h.add_child(b)
	var l := Kit.lbl("%d%s" % [value, suffix], 18, AF.GOLD_BRIGHT)
	l.custom_minimum_size.x = 70
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	for d2: int in [small, big]:
		var b2 := _btn("%+d" % d2, func() -> void: cb.call(clampi(value + d2, lo, hi)), false, value >= hi, 48.0)
		b2.custom_minimum_size.x = 56
		h.add_child(b2)
	return h


func set_status(text: String) -> void:
	status = text
	if _status_lbl != null:
		_status_lbl.text = text


## Applies the module's ledger to the purse (the game's Life does the same hourly).
func _settle() -> void:
	var e := ent()
	if e == null or int(e.get("purse_override")) >= 0:
		return
	var g := int(e.call("take_pending_gold"))
	var game: Node = get_node_or_null("/root/Game")
	if g != 0 and game != null:
		game.call("add_gold", g)


func _act(result: Variant, ok_text := "") -> void:
	var r: Dictionary = result if result is Dictionary else {}
	if bool(r.get("ok", false)):
		set_status(ok_text if ok_text != "" else String(r.get("reason", "")))
	else:
		set_status(String(r.get("reason", "Not possible.")))
	_settle()
	rebuild()


func set_tab(t: String) -> void:
	tab = t
	rebuild()


func set_sid(i: int) -> void:
	sid = clampi(i, 0, WorldGen.settlements.size() - 1)
	qty.clear()
	rebuild()


func rebuild() -> void:
	if not _built:
		return
	var e := ent()
	Kit.clear(_head)
	Kit.clear(_tabs_row)
	Kit.clear(_box)
	_head.add_child(Kit.lbl("Enterprise", 26, AF.GOLD_BRIGHT, false, "title_bold"))
	var prev := _btn("<", func() -> void: set_sid((sid - 1 + WorldGen.settlements.size()) % WorldGen.settlements.size()), false, false, 48.0)
	prev.custom_minimum_size.x = 52
	_head.add_child(prev)
	var nm := Kit.lbl(_sname(sid), 22, AF.TEXT, false, "title")
	nm.custom_minimum_size.x = 190
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(nm)
	var nxt := _btn(">", func() -> void: set_sid((sid + 1) % WorldGen.settlements.size()), false, false, 48.0)
	nxt.custom_minimum_size.x = 52
	_head.add_child(nxt)
	_head.add_child(Kit.hspacer())
	if e != null:
		_gold_lbl = Kit.lbl("%d gold" % int(e.call("gold")), 22, AF.GOLD_BRIGHT, false, "title")
		_gold_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_head.add_child(_gold_lbl)
	_head.add_child(_btn("Map", func() -> void: show_map.emit(), false, false, 48.0))
	_head.add_child(_btn("Close", func() -> void: closed.emit(), false, false, 48.0))
	for t: Array in TABS:
		_tabs_row.add_child(_chip(String(t[1]), String(t[0]) == tab, set_tab.bind(String(t[0])), 100.0))
	_status_lbl.text = status
	if e == null:
		_box.add_child(Kit.lbl("The enterprise ledger is not available here.", 18, AF.TEXT_DIM, true, "italic"))
		return
	match tab:
		"market":
			_fill_market(e)
		"routes":
			_fill_routes(e)
		"caravans":
			_fill_caravans(e)
		"workshops":
			_fill_workshops(e)
		"fief":
			_fill_fief(e)
		"clan":
			_fill_clan(e)


func _section(text: String) -> void:
	_box.add_child(Kit.section(text, 20))


func _note(text: String, col := AF.TEXT_DIM) -> Label:
	var l := Kit.lbl(text, 15, col, true, "italic")
	_box.add_child(l)
	return l


# ----------------------------------------------------------------- market ----

func _best_elsewhere(e: RefCounted, g: String) -> Dictionary:
	var best := {}
	var bp := 0
	for s: Dictionary in WorldGen.settlements:
		var o := int(s["id"])
		if o == sid:
			continue
		var kp: Dictionary = e.call("known_price", o, g)
		if not kp.is_empty() and int(kp["p"]) > bp:
			bp = int(kp["p"])
			best = {"sid": o, "p": bp, "age": int(kp["age"])}
	return best


func _fill_market(e: RefCounted) -> void:
	var here := bool(e.call("at_settlement", sid))
	var age := int(e.call("known_age", sid))
	var cap := int(e.call("capacity"))
	var used := int(e.call("pack_total"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var bar := Kit.bar(float(used) / float(maxi(cap, 1)), 22.0, AF.GOLD, "Pack %d / %d" % [used, cap])
	bar.custom_minimum_size = Vector2(240, 22)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(bar)
	top.add_child(Kit.lbl("Prices here: %s" % e.call("age_text", age), 16, AF.TEXT_DIM, true, "italic"))
	_box.add_child(top)
	if not here:
		_note("You are %.1f days from %s. Travel there to buy or sell; the board below is what you last saw." % [float(e.call("days_away", sid)), _sname(sid)], WARN)
	var acts := _flow()
	acts.add_child(_btn("Buy rumours at the inn (%dg)" % D.RUMOUR_COST, func() -> void: _rumours(e), false, not here))
	var inf_why := String(e.call("can", "informant"))
	acts.add_child(_btn("Informant here (%dg)" % D.INFORMANT_COST, func() -> void: _act(e.call("hire_informant", sid), "An informant will send word of %s for two weeks." % _sname(sid)),
		false, inf_why != "" or bool(e.call("has_informant", sid))))
	_box.add_child(acts)
	if inf_why != "":
		_note(inf_why)
	_section("Goods")
	var grid := _grid()
	_box.add_child(grid)
	for g: String in D.GOOD_ORDER:
		grid.add_child(_good_row(e, g, here))


func _rumours(e: RefCounted) -> void:
	var r: Dictionary = e.call("buy_rumour", sid)
	if bool(r["ok"]):
		var names: Array = (r["towns"] as Array).map(func(t: int) -> String: return _sname(t))
		set_status("At the inn you hear about prices in %s." % ", ".join(names))
	else:
		set_status(String(r["reason"]))
	_settle()
	rebuild()


func _good_row(e: RefCounted, g: String, here: bool) -> Control:
	var def: Dictionary = D.GOODS[g]
	var stock := int(floor(float(e.call("stock_of", sid, g))))
	var avail := int(floor(float(e.call("available", sid, g))))
	var p := int(e.call("price", sid, g))
	var base := int(def["base"])
	var carried := int(e.call("pack_qty", g))
	var n := int(qty.get(g, 10))
	var v := _card()
	var l1 := HBoxContainer.new()
	l1.add_theme_constant_override("separation", 10)
	var icon_col := GOOD if p < base else (BAD if p > base * 1.2 else WARN)
	var nm := Kit.lbl(String(def["name"]), 20, AF.TEXT, false, "title")
	nm.custom_minimum_size.x = 150
	l1.add_child(nm)
	var pl := Kit.lbl("%dg" % p, 22, icon_col)
	pl.custom_minimum_size.x = 64
	l1.add_child(pl)
	l1.add_child(Kit.lbl("stock %d" % stock, 15, AF.TEXT_DIM))
	if carried > 0:
		l1.add_child(Kit.lbl("carrying %d (avg %dg)" % [carried, int(round(float(e.call("pack_cost", g))))], 15, AF.GOLD_BRIGHT))
	v.add_child(l1)
	var be := _best_elsewhere(e, g)
	if not be.is_empty():
		var profit := int(be["p"]) - p
		var col := GOOD if profit > 0 else AF.TEXT_DIM
		v.add_child(Kit.lbl("Best known price: %dg in %s (%s)" % [int(be["p"]), _sname(int(be["sid"])), e.call("age_text", int(be["age"]))], 14, col))
	if String(def["cat"]) == "rare":
		v.add_child(Kit.lbl("Rift crystal: rare, valuable and dangerous to haul.", 14, Color("b59cff"), true, "italic"))
	v.add_child(_stepper(n, 1, 10, 1, 200, func(v2: int) -> void:
		qty[g] = v2
		rebuild()))
	var qb: Dictionary = e.call("quote", sid, g, n, "buy")
	var qs: Dictionary = e.call("quote", sid, g, mini(n, carried), "sell") if carried > 0 else {"total": 0, "qty": 0}
	var l2 := _flow()
	l2.add_child(_btn("Buy %d: %dg" % [int(qb["qty"]), int(qb["total"])], func() -> void: _act(e.call("buy", sid, g, n), "Bought."), true, not here or avail < 1 or int(qb["qty"]) < 1, 48.0))
	l2.add_child(_btn("Sell %d: +%dg" % [int(qs["qty"]), int(qs["total"])], func() -> void: _act(e.call("sell", sid, g, n), "Sold."), false, not here or carried < 1, 48.0))
	l2.add_child(_btn("Sell all", func() -> void: _act(e.call("sell", sid, g, carried), "Sold everything."), false, not here or carried < 1, 48.0))
	v.add_child(l2)
	return _framed(v)


# ----------------------------------------------------------------- routes ----

func _last_stop() -> int:
	return int(plan_stops[plan_stops.size() - 1]) if not plan_stops.is_empty() else sid


func _fill_routes(e: RefCounted) -> void:
	if plan_stops.is_empty() or int(plan_stops[0]) != sid and plan_stops.size() == 1:
		plan_stops = [sid]
	_section("Plan a trade route")
	_note("Pick the towns in order. The estimate uses only prices you know, and says so when it is guessing.")
	var bar := _flow()
	for i in plan_stops.size():
		var idx := i
		bar.add_child(_chip("%d. %s" % [i + 1, _sname(int(plan_stops[i]))], true, func() -> void:
			if idx > 0:
				plan_stops.remove_at(idx)
				route_preview.emit(plan_stops)
				rebuild(), 0.0))
	_box.add_child(bar)
	var opts_row := _flow()
	opts_row.add_child(_chip("Return to start", plan_loop, func() -> void:
		plan_loop = not plan_loop
		rebuild()))
	opts_row.add_child(_btn("Clear", func() -> void:
		plan_stops = [sid]
		route_preview.emit(plan_stops)
		rebuild(), false, false, 48.0))
	_box.add_child(opts_row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	row2.add_child(Kit.lbl("Guards", 16, AF.TEXT_DIM))
	row2.add_child(_stepper(plan_guards, 1, 2, 0, 8, func(v: int) -> void:
		plan_guards = v
		rebuild()))
	_box.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	row3.add_child(Kit.lbl("Capital", 16, AF.TEXT_DIM))
	row3.add_child(_stepper(plan_capital, 50, 100, 50, 2000, func(v: int) -> void:
		plan_capital = v
		rebuild(), "g"))
	_box.add_child(row3)
	_section("Estimate")
	var est: Dictionary = e.call("estimate_route", plan_stops, {"budget": float(plan_capital), "guards": plan_guards, "cap": D.CARAVAN_CAP, "loop": plan_loop, "wage": float(plan_guards * D.GUARD_WAGE + 4)})
	if (est["legs"] as Array).is_empty():
		_note("Add at least one more town below.")
	else:
		var card := _card()
		for leg: Dictionary in est["legs"]:
			var line := "%s to %s: " % [_sname(int(leg["from"])), _sname(int(leg["to"]))]
			if String(leg["good"]) == "":
				line += "nothing worth hauling"
			else:
				line += "%d %s, cost %dg, sells %dg (%+dg)" % [int(leg["qty"]), _gname(String(leg["good"])).to_lower(), int(leg["buy"]), int(leg["sell"]), int(leg["profit"])]
			card.add_child(Kit.lbl(line, 16, AF.TEXT, true))
			var info := "%.1f days, road risk %d%%, toll %dg" % [float(leg["hours"]) / 24.0, int(float(leg["risk"]) * 100.0), int(leg["toll"])]
			info += ". Price %s." % ("guessed, never seen" if not bool(leg["known"]) else e.call("age_text", int(leg["age"])))
			card.add_child(Kit.lbl(info, 14, WARN if not bool(leg["known"]) else AF.TEXT_DIM, true, "italic"))
		card.add_child(AF.separator())
		var net_col := GOOD if int(est["net"]) > 0 else BAD
		card.add_child(Kit.lbl("Expected profit %dg over %.1f days. Tolls %dg, running costs %dg, expected raid losses %dg." % [int(est["profit"]), float(est["days"]), int(est["toll"]), int(est["wage"]), int(est["loss"])], 16, AF.TEXT, true))
		card.add_child(Kit.lbl("Net %+dg (%+dg a day). Chance of a raid on the way: %d%%." % [int(est["net"]), int(est["per_day"]), int(float(est["risk"]) * 100.0)], 18, net_col, true))
		if bool(est["rift"]):
			card.add_child(Kit.lbl("The road passes a Rift: rare crystal, deadly ground.", 15, Color("b59cff"), true))
		if bool(est["hostile"]):
			card.add_child(Kit.lbl("Part of the road is held by another power: expect tolls and trouble.", 15, WARN, true))
		_box.add_child(_framed(card))
		var acts := _flow()
		acts.add_child(_btn("Fund a caravan on this route", func() -> void:
			car_route_mode = "route"
			set_tab("caravans"), true))
		acts.add_child(_btn("Show on map", func() -> void: route_preview.emit(plan_stops)))
		_box.add_child(acts)
		# roads on the route
		var rl := _card()
		var any := false
		for i in range(est["stops"].size() - 1):
			var a := int(est["stops"][i])
			var b := int(est["stops"][i + 1])
			var ri: Dictionary = e.call("route_info", a, b)
			for leg2: Dictionary in ri["legs"]:
				if not String(leg2["a"]).begins_with("s") or not String(leg2["b"]).begins_with("s"):
					continue
				var ia := int(String(leg2["a"]).substr(1))
				var ib := int(String(leg2["b"]).substr(1))
				var rd: Dictionary = {}
				for r2: Dictionary in e.call("road_list"):
					if (r2["a"] == leg2["a"] and r2["b"] == leg2["b"]) or (r2["a"] == leg2["b"] and r2["b"] == leg2["a"]):
						rd = r2
				any = true
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 8)
				var tx := "%s - %s: %s road, %d%% repair" % [_sname(ia), _sname(ib), String(rd.get("level", "?")), int(float(rd.get("cond", 0.0)) * 100.0)]
				var lb := Kit.lbl(tx, 15, AF.TEXT, true)
				lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				h.add_child(lb)
				var mw := String(e.call("can", "road_works"))
				var mc := int(e.call("maintain_cost", ia, ib))
				h.add_child(_btn("Mend %dg" % mc, func() -> void: _act(e.call("maintain_road", ia, ib), "The road is mended."), false, mw != "" or mc <= 0, 48.0))
				var next_level := "stone" if String(rd.get("level", "dirt")) in ["dirt", "road"] else "military"
				if String(rd.get("level", "")) == "dirt":
					next_level = "road"
				var uc := int(e.call("road_cost", ia, ib, next_level))
				var uw := String(e.call("can_plan_road", ia, ib, next_level))
				h.add_child(_btn("%s %dg" % [next_level.capitalize(), uc], func() -> void: _act(e.call("plan_road", ia, ib, next_level), "Work begins: a crew is on the road."), false, uw != "", 48.0))
				rl.add_child(h)
		if any:
			_section("Roads on this route")
			_note("Better roads mean more traffic and fewer raids; they take days of real labour.")
			_box.add_child(_framed(rl))
	_section("Add a stop")
	var ranked: Array = e.call("rank_destinations", _last_stop(), {"budget": float(plan_capital), "guards": plan_guards, "cap": D.CARAVAN_CAP})
	var f := _flow()
	for r: Dictionary in ranked.slice(0, 12):
		var to := int(r["to"])
		var label := "%s %+d" % [_sname(to), int(r["expected"])]
		if not bool(r["known"]) and String(r["good"]) != "":
			label += " ?"
		f.add_child(_chip(label, plan_stops.has(to), func() -> void:
			plan_stops.append(to)
			route_preview.emit(plan_stops)
			rebuild(), 150.0))
	_box.add_child(f)
	_note("A ? means you have never seen that town's prices: the figure is a guess.")


# --------------------------------------------------------------- caravans ----

func _fill_caravans(e: RefCounted) -> void:
	_section("Your caravans (%d of %d)" % [(e.get("caravans") as Dictionary).size(), int(e.call("caravan_limit"))])
	var cars: Array = e.call("list_caravans")
	if cars.is_empty():
		_note("No caravans yet. A caravan is a cart, guards and a leader from your companions who buys low and sells high on his own judgement.")
	var grid := _grid()
	_box.add_child(grid)
	for c: Dictionary in cars:
		grid.add_child(_caravan_card(e, c))
	_section("Fund a new caravan at %s" % _sname(sid))
	var why_role := String(e.call("can", "caravan"))
	if why_role != "":
		_note(why_role, WARN)
		_box.add_child(_btn("Buy a trader's licence (%dg)" % D.LICENSE_COST, func() -> void: _act(e.call("buy_license"), "You are a licensed trader."), true, false))
		return
	var leaders: Array = e.call("free_leaders")
	var lf := _flow()
	if car_leader == "" and not leaders.is_empty():
		car_leader = String((leaders[0] as Dictionary)["id"])
	for f: Dictionary in leaders:
		var prof: Dictionary = e.call("leader_profile", String(f["id"]))
		var fid := String(f["id"])
		lf.add_child(_chip("%s (%s)" % [f["name"], ", ".join((prof["traits"] as Array).slice(0, 2))], car_leader == fid, func() -> void:
			car_leader = fid
			rebuild(), 200.0))
	lf.add_child(_btn("Hire a scout-master", func() -> void:
		var nf: String = e.call("hire_leader", sid)
		if nf != "":
			car_leader = nf
		set_status("A scout-master joins you.")
		rebuild(), false, false, 48.0))
	_box.add_child(Kit.lbl("Leader", 16, AF.TEXT_DIM))
	_box.add_child(lf)
	if car_leader != "":
		var pf: Dictionary = e.call("leader_profile", car_leader)
		_note("%s: haggling %d%%, appetite for risk %s, loyalty %d. Brave or greedy leaders take shortcuts; disloyal ones skim the takings." % [pf["name"], int(float(pf["haggle"]) * 100.0), "high" if float(pf["appetite"]) > 0.3 else ("low" if float(pf["appetite"]) < 0.0 else "middling"), int(pf["loyalty"])])
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 14)
	r1.add_child(Kit.lbl("Guards", 16, AF.TEXT_DIM))
	r1.add_child(_stepper(car_guards, 1, 2, 0, 8, func(v: int) -> void:
		car_guards = v
		rebuild()))
	_box.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 14)
	r2.add_child(Kit.lbl("Capital", 16, AF.TEXT_DIM))
	r2.add_child(_stepper(car_capital, 50, 100, 50, 2000, func(v: int) -> void:
		car_capital = v
		rebuild(), "g"))
	_box.add_child(r2)
	var rm := _flow()
	rm.add_child(_chip("Leader chooses the route", car_route_mode == "leader", func() -> void:
		car_route_mode = "leader"
		rebuild(), 220.0))
	var route_txt := "Follow the planned route (%d towns)" % plan_stops.size() if plan_stops.size() >= 2 else "Follow a route (plan one in Routes)"
	rm.add_child(_chip(route_txt, car_route_mode == "route", func() -> void:
		car_route_mode = "route"
		rebuild(), 220.0))
	_box.add_child(rm)
	var cost := int(e.call("caravan_cost", car_guards, car_capital))
	var why := String(e.call("can_fund_caravan", sid, car_guards, car_capital, car_leader))
	_box.add_child(Kit.lbl("Cost: cart %dg, guards %dg, capital %dg = %dg. Guards cost %dg a day." % [D.CART_COST, car_guards * D.GUARD_COST, car_capital, cost, D.GUARD_WAGE], 16, AF.TEXT, true))
	if why != "":
		_note(why, WARN)
	_box.add_child(_btn("Fund the caravan (%dg)" % cost, func() -> void:
		var route: Array = []
		if car_route_mode == "route" and plan_stops.size() >= 2:
			route = plan_stops.duplicate()
		_act(e.call("fund_caravan", sid, car_guards, car_capital, car_leader, route), "The wagons roll out."), true, why != ""))


func _caravan_card(e: RefCounted, c: Dictionary) -> Control:
	var id := int(c["id"])
	var prof: Dictionary = e.call("leader_profile", String(c["leader"]))
	var v := _card()
	v.add_child(Kit.lbl(String(c["name"]), 21, AF.GOLD_BRIGHT, false, "title"))
	v.add_child(Kit.lbl(String(e.call("caravan_status", c)), 16, AF.TEXT, true))
	v.add_child(Kit.lbl("%s leads (%s), loyalty %d. %d guards. %s." % [prof["name"], ", ".join(prof["traits"]), int(prof["loyalty"]), int(c["guards"]), String(e.call("tier_of", c)).capitalize() + " tier"], 14, AF.TEXT_DIM, true))
	v.add_child(Kit.bar(clampf(float(c["cash"]) / maxf(float(c["capital"]), 1.0), 0.0, 1.0), 18.0, AF.GOLD, "Purse %d / %d" % [int(c["cash"]), int(c["capital"])]))
	var cargo: Dictionary = c["cargo"]
	var parts := []
	for g: String in cargo:
		parts.append("%d %s" % [int((cargo[g] as Array)[0]), _gname(g).to_lower()])
	v.add_child(Kit.lbl("Carrying: %s. %d trips, %+d gold, %d raids." % [", ".join(parts) if not parts.is_empty() else "nothing", int(c["trips"]), int(c["profit"]), int(c["raids"])], 15, AF.TEXT, true))
	var route: Array = c["route"]
	var rt := "the leader chooses" if route.is_empty() else " - ".join(route.map(func(i: int) -> String: return _sname(i)))
	v.add_child(Kit.lbl("Route: %s." % rt, 14, AF.TEXT_DIM, true, "italic"))
	for r: Dictionary in (c["reports"] as Array).slice(-3):
		v.add_child(Kit.lbl("Day %d: %s" % [int(r["day"]), r["text"]], 13, AF.TEXT_DIM, true, "italic"))
	var acts := _flow()
	acts.add_child(_btn("Recall home", func() -> void:
		e.call("recall_caravan", id)
		set_status("%s turns for home." % c["name"])
		rebuild(), false, false, 48.0))
	acts.add_child(_btn("Leader chooses", func() -> void:
		e.call("set_caravan_route", id, [])
		rebuild(), false, false, 48.0))
	if plan_stops.size() >= 2:
		acts.add_child(_btn("Use planned route", func() -> void:
			e.call("set_caravan_route", id, plan_stops.duplicate())
			rebuild(), false, false, 48.0))
	acts.add_child(_btn("Disband", func() -> void: _act(e.call("disband_caravan", id), "The caravan is disbanded."), false, false, 48.0))
	v.add_child(acts)
	return _framed(v)


# -------------------------------------------------------------- workshops ----

func _fill_workshops(e: RefCounted) -> void:
	_section("Your workshops")
	var mine: Array = e.get("workshops")
	if mine.is_empty():
		_note("None yet. A workshop turns the town's own goods into better ones; it buys inputs from local stock and sells outputs into the local market, so a busy one can drain a town.")
	var grid := _grid()
	_box.add_child(grid)
	for w: Dictionary in mine:
		grid.add_child(_workshop_card(e, w))
	_section("Buy a workshop in %s" % _sname(sid))
	var why_role := String(e.call("can", "workshop"))
	if why_role != "":
		_note(why_role, WARN)
		_box.add_child(_btn("Buy a trader's licence (%dg)" % D.LICENSE_COST, func() -> void: _act(e.call("buy_license"), "You are a licensed trader."), true))
	var grid2 := _grid()
	_box.add_child(grid2)
	for k: String in D.WORKSHOP_ORDER:
		grid2.add_child(_workshop_offer(e, k))


func _recipe_text(def: Dictionary) -> String:
	var ins := []
	for g: String in (def["in"] as Dictionary):
		ins.append("%s %s" % [str(snappedf(float((def["in"] as Dictionary)[g]), 0.1)), _gname(g).to_lower()])
	var outs := []
	for g: String in (def["out"] as Dictionary):
		outs.append("%s %s" % [str(snappedf(float((def["out"] as Dictionary)[g]), 0.1)), _gname(g).to_lower()])
	return "%s into %s" % [", ".join(ins), ", ".join(outs)]


func _workshop_offer(e: RefCounted, kind: String) -> Control:
	var def: Dictionary = D.WORKSHOPS[kind]
	var v := _card()
	v.add_child(Kit.lbl(String(def["name"]), 20, AF.GOLD_BRIGHT, false, "title"))
	v.add_child(Kit.lbl("Per batch: %s." % _recipe_text(def), 15, AF.TEXT, true))
	var gs: Dictionary = e.call("guild_stance", sid, kind)
	if bool(gs["present"]):
		var gt := "You are a member of %s: better prices." % gs["name"] if bool(gs["member"]) else ("%s is closed to outsiders." % gs["name"] if bool(gs["blocked"]) else "%s taxes outsiders." % gs["name"])
		v.add_child(Kit.lbl(gt, 14, GOOD if bool(gs["member"]) else WARN, true, "italic"))
	var why := String(e.call("can_buy_workshop", sid, kind))
	var row := _flow()
	row.add_child(_btn("Buy for %dg" % int(e.call("workshop_price", sid, kind)), func() -> void: _act(e.call("buy_workshop", sid, kind), "Your new %s opens." % String(def["name"]).to_lower()), true, why != ""))
	if bool(gs["present"]) and not bool(gs["member"]):
		row.add_child(_btn("Join guild", func() -> void:
			var r: Dictionary = e.call("join_workshop_guild", sid, kind)
			set_status(String(r.get("reason", "")) if not bool(r.get("ok", false)) else "You are in.")
			_settle()
			rebuild(), false, false, 48.0))
	v.add_child(row)
	if why != "":
		v.add_child(Kit.lbl(why, 13, AF.TEXT_DIM, true, "italic"))
	return _framed(v)


func _workshop_card(e: RefCounted, w: Dictionary) -> Control:
	var def: Dictionary = D.WORKSHOPS[String(w["kind"])]
	var id := int(w["id"])
	var fc: Dictionary = e.call("workshop_run", w, false)
	var v := _card()
	v.add_child(Kit.lbl("%s, %s (level %d)" % [def["name"], _sname(int(w["sid"])), int(w["level"])], 20, AF.GOLD_BRIGHT, false, "title"))
	v.add_child(Kit.lbl("Per batch: %s. %.1f batches a day at full supply." % [_recipe_text(def), float(fc["batches"])], 14, AF.TEXT_DIM, true))
	var net_col := GOOD if int(fc["net"]) > 0 else BAD
	v.add_child(Kit.lbl("Today: sells %dg, inputs %dg, wages %dg, upkeep %dg: net %+dg." % [int(fc["revenue"]), int(fc["in_cost"]), int(fc["wages"]), int(fc["upkeep"]), int(fc["net"])], 16, net_col, true))
	if float(fc["supplied"]) < 0.85 and String(fc["short"]) != "":
		v.add_child(Kit.lbl("The town is short of %s: only %d%% supplied." % [_gname(String(fc["short"])).to_lower(), int(float(fc["supplied"]) * 100.0)], 15, WARN, true))
	if abs(float(fc["guild"])) > 0.0:
		v.add_child(Kit.lbl("Guild effect on sales: %+d%%." % int(float(fc["guild"]) * 100.0), 14, AF.TEXT_DIM, true, "italic"))
	var hist: Array = w["history"]
	if not hist.is_empty():
		v.add_child(Kit.lbl("Last days: %s" % ", ".join(hist.map(func(n: int) -> String: return "%+d" % n)), 14, AF.TEXT_DIM, true, "italic"))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hrow.add_child(Kit.lbl("Workers", 15, AF.TEXT_DIM))
	hrow.add_child(_stepper(int(w["workers"]), 1, 2, 0, int(w["level"]) * 4, func(n: int) -> void: _act(e.call("set_workers", id, n))))
	v.add_child(hrow)
	var acts := _flow()
	var up := int(e.call("upgrade_cost", w))
	acts.add_child(_btn("Upgrade %dg" % up, func() -> void: _act(e.call("upgrade_workshop", id), "Bigger premises."), false, int(w["level"]) >= D.MAX_LEVEL, 48.0))
	acts.add_child(_btn("Sell", func() -> void: _act(e.call("sell_workshop", id), "Sold."), false, false, 48.0))
	v.add_child(acts)
	var free: Array = e.call("free_leaders")
	if String(w["manager"]) == "" and not free.is_empty():
		var mf := _flow()
		mf.add_child(Kit.lbl("Manager:", 15, AF.TEXT_DIM))
		for f: Dictionary in free.slice(0, 3):
			var fid := String(f["id"])
			mf.add_child(_btn(String(f["name"]), func() -> void: _act(e.call("set_manager", id, fid), "A manager takes charge."), false, false, 44.0))
		v.add_child(mf)
	elif String(w["manager"]) != "":
		v.add_child(_btn("Dismiss the manager", func() -> void: _act(e.call("set_manager", id, "")), false, false, 44.0))
	return _framed(v)


# ------------------------------------------------------------------- fief ----

func _fill_fief(e: RefCounted) -> void:
	var fiefs: Array = e.call("fief_ids")
	if fiefs.is_empty():
		_section("No land")
		_note(String(e.call("can", "fief")))
		var why := String(e.call("can_buy_fief", sid))
		_box.add_child(Kit.lbl("%s can be bought for %d gold." % [_sname(sid), int(e.call("fief_price", sid))], 17, AF.TEXT, true))
		_box.add_child(_btn("Buy the estate of %s" % _sname(sid), func() -> void: _act(e.call("buy_fief", sid), "The estate is yours."), true, why != ""))
		if why != "":
			_note(why, WARN)
		return
	if fief_sid < 0 or not fiefs.has(fief_sid):
		fief_sid = int(sid if fiefs.has(sid) else fiefs[0])
	if fiefs.size() > 1:
		var fc := _flow()
		for f: int in fiefs:
			fc.add_child(_chip(_sname(f), f == fief_sid, func() -> void:
				fief_sid = f
				rebuild(), 130.0))
		_box.add_child(fc)
	var info: Dictionary = e.call("fief_info", fief_sid)
	if info.is_empty():
		return
	var fs := fief_sid
	_section("%s: your fief" % _sname(fs))
	var bars := _card()
	bars.add_child(_bar_row("Loyalty", float(info["loyalty"]) / 100.0, Color("7fd18b"), "%d" % int(info["loyalty"])))
	bars.add_child(_bar_row("Prosperity", float(info["prosperity"]) / 100.0, Color("d8c690"), "%d" % int(info["prosperity"])))
	bars.add_child(_bar_row("Security", float(info["security"]) / 100.0, Color("6fa8ff"), "%d" % int(info["security"])))
	bars.add_child(_bar_row("Food", clampf(float(info["food"]) / maxf(float(info["pop"]) * 0.2, 1.0), 0.0, 1.0), Color("e0b45a"), "%d" % int(info["food"])))
	_box.add_child(_framed(bars))
	var inc: Dictionary = info["income"]
	_box.add_child(Kit.lbl("Treasury %dg. Each day: taxes %+d, share of the fief's production %+d, wages %d, crew %d = %+dg." % [int(info["treasury"]), int(inc["tax"]), int(inc["share"]), -int(inc["wages"]), -int(inc["crew"]), int(inc["net"])], 16, AF.TEXT, true))
	var tr := _flow()
	tr.add_child(_btn("Take 100", func() -> void: _act({"ok": int(e.call("treasury_withdraw", fs, 100)) > 0, "reason": "The treasury is empty."}), false, false, 48.0))
	tr.add_child(_btn("Take all", func() -> void: _act({"ok": int(e.call("treasury_withdraw", fs, int(info["treasury"]))) > 0, "reason": "The treasury is empty."}), false, false, 48.0))
	tr.add_child(_btn("Put in 100", func() -> void: _act({"ok": int(e.call("treasury_deposit", fs, 100)) > 0, "reason": "You have nothing to give."}), false, false, 48.0))
	_box.add_child(tr)
	_section("Taxes")
	var tx := _flow()
	var notes := {"low": "Loved, poorer: the people remember fair rule.", "fair": "Steady.", "harsh": "Rich now, resented for generations."}
	for r: String in ["low", "fair", "harsh"]:
		tx.add_child(_chip(r.capitalize(), String(info["tax_rate"]) == r, func() -> void:
			var why2 := String(e.call("set_tax", fs, r))
			set_status(why2 if why2 != "" else String(notes[r]))
			rebuild(), 110.0))
	_box.add_child(tx)
	_note(String(notes[String(info["tax_rate"])]))
	var mem: Array = info["memory"]
	if not mem.is_empty():
		var kinds := {}
		for m: Dictionary in mem:
			kinds[String(m["kind"])] = float(kinds.get(String(m["kind"]), 0.0)) + float(m["weight"])
		var parts := []
		for k: String in kinds:
			parts.append("%s" % k.replace("_", " "))
		_note("The people remember: %s." % ", ".join(parts))
	_section("Projects")
	var works: Array = info["projects"]
	for w: Dictionary in works:
		_box.add_child(_work_card(e, w))
	var grid := _grid()
	_box.add_child(grid)
	for k: String in D.PROJECT_ORDER:
		var def: Dictionary = D.PROJECTS[k]
		var why3 := String(e.call("can_start_project", fs, k))
		var pv := _card()
		pv.add_child(Kit.lbl("%s  (%dg, %d man-days)" % [def["label"], int(def["gold"]), int(def["work"])], 17, AF.TEXT, true))
		pv.add_child(Kit.lbl(String(def["text"]), 14, AF.TEXT_DIM, true, "italic"))
		var built := int(info["built"].get(k, 0))
		if built > 0:
			pv.add_child(Kit.lbl("Built: %d" % built, 14, GOOD))
		pv.add_child(_btn("Begin", func() -> void: _act(e.call("start_project", fs, k, 6), "A crew begins work."), false, why3 != "", 48.0))
		if why3 != "" and why3 != "Already built.":
			pv.add_child(Kit.lbl(why3, 13, AF.TEXT_DIM, true, "italic"))
		grid.add_child(_framed(pv))
	_section("Garrison and governor")
	var gar: Dictionary = info["garrison"]
	var gtxt := []
	for t: String in gar:
		gtxt.append("%d %s" % [int(gar[t]), String((D.TROOPS[t] as Dictionary)["name"]).to_lower()])
	_box.add_child(Kit.lbl("%d militia. Garrison: %s." % [int(info["militia"]), ", ".join(gtxt) if not gtxt.is_empty() else "none"], 16, AF.TEXT, true))
	var gf := _flow()
	var troops: Dictionary = e.get("troops")
	for t: String in troops:
		gf.add_child(_btn("Post 5 %s" % String((D.TROOPS[t] as Dictionary)["name"]).to_lower(), func() -> void: _act({"ok": int(e.call("garrison_assign", fs, t, 5)) > 0, "reason": "None to spare."}), false, false, 48.0))
	for t2: String in gar:
		gf.add_child(_btn("Recall 5 %s" % String((D.TROOPS[t2] as Dictionary)["name"]).to_lower(), func() -> void: _act({"ok": int(e.call("garrison_recall", fs, t2, 5)) > 0, "reason": "Your party is full."}), false, false, 48.0))
	_box.add_child(gf)
	var gov: Dictionary = info["governor"]
	if not gov.is_empty():
		_box.add_child(Kit.lbl("Governor: %s (+%d%% to the fief's work). A steward sends the surplus home each week." % [gov["name"], int(float(e.call("governor_efficiency", fs)) * 100.0)], 16, AF.TEXT, true))
		_box.add_child(_btn("Dismiss the governor", func() -> void:
			e.call("clear_governor", fs)
			rebuild(), false, false, 48.0))
	else:
		var free: Array = e.call("free_leaders")
		if free.is_empty():
			_note("No free companion to govern. Recruit one in Followers.")
		else:
			var govrow := _flow()
			for f: Dictionary in free:
				var fid := String(f["id"])
				govrow.add_child(_btn("Appoint %s" % f["name"], func() -> void: _act(e.call("set_governor", fs, fid), "A governor is appointed."), false, false, 48.0))
			_box.add_child(govrow)


func _bar_row(caption: String, ratio: float, col: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Kit.lbl(caption, 16, AF.TEXT_DIM)
	l.custom_minimum_size.x = 100
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Kit.bar(ratio, 22.0, col, text)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return h


func _work_card(e: RefCounted, w: Dictionary) -> Control:
	var id := int(w["id"])
	var v := _card()
	var done := 1.0 - float(w["left"]) / maxf(float(w["total"]), 1.0)
	v.add_child(Kit.lbl("%s: crew of %d at work" % [w["label"], int(w["crew"])], 17, AF.GOLD_BRIGHT, true))
	v.add_child(Kit.bar(done, 20.0, Color("e0b45a"), "%d%% (%d man-days left)" % [int(done * 100.0), int(ceil(float(w["left"])))]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Kit.lbl("Crew", 15, AF.TEXT_DIM))
	row.add_child(_stepper(int(w["crew"]), 1, 2, 1, D.CREW_MAX, func(n: int) -> void:
		e.call("set_crew", id, n)
		rebuild()))
	row.add_child(_btn("Lend a hand", func() -> void:
		e.call("help_build", id, 0.8)
		set_status("You work a shift on the site. The people notice.")
		rebuild(), false, false, 48.0))
	v.add_child(row)
	return _framed(v, AF.GOLD)


# ------------------------------------------------------------------- clan ----

func _fill_clan(e: RefCounted) -> void:
	var ci: Dictionary = e.call("clan_info")
	_section("%s, a %s" % [ci["name"], ci["tier_name"]])
	_box.add_child(Kit.lbl(String(ci["text"]), 16, AF.TEXT, true))
	var nxt := float(ci["next_renown"])
	var ratio := 1.0 if nxt <= 0.0 else clampf(float(ci["renown"]) / nxt, 0.0, 1.0)
	_box.add_child(_bar_row("Renown", ratio, AF.GOLD, "%d%s" % [int(ci["renown"]), (" / %d for %s" % [int(nxt), ci["next_name"]]) if nxt > 0.0 else ""]))
	_box.add_child(_bar_row("Party", float(ci["party_size"]) / maxf(float(ci["party_limit"]), 1.0), Color("6fa8ff"), "%d / %d" % [int(ci["party_size"]), int(ci["party_limit"])]))
	_box.add_child(Kit.lbl("Influence %.1f. Roles: %s.%s" % [float(ci["influence"]), ", ".join(e.call("roles")), (" Sworn to %s." % ci["liege"]) if String(ci["liege"]) != "" else ""], 16, AF.TEXT_DIM, true))
	var troops: Dictionary = e.get("troops")
	_section("Your troops (wages %dg a day)" % int(e.call("troop_wages")))
	if troops.is_empty():
		_note("None. Raise men in a town that trusts you.")
	for t: String in D.TROOP_ORDER:
		if int(troops.get(t, 0)) > 0:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			var lb := Kit.lbl("%d %s" % [int(troops[t]), String((D.TROOPS[t] as Dictionary)["name"])], 17, AF.TEXT)
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(lb)
			h.add_child(_btn("Dismiss 5", func() -> void:
				e.call("dismiss", t, 5)
				rebuild(), false, false, 44.0))
			_box.add_child(h)
	_section("Recruits in %s" % _sname(sid))
	var why := String(e.call("can", "recruit"))
	if why != "":
		_note(why, WARN)
	else:
		var pool: Dictionary = e.call("recruit_pool", sid)
		_box.add_child(Kit.lbl("Standing here %d. The pool refills daily and depends on how the town sees you." % int(e.call("standing", sid)), 15, AF.TEXT_DIM, true, "italic"))
		var grid := _grid()
		_box.add_child(grid)
		for t: String in D.TROOP_ORDER:
			var def: Dictionary = D.TROOPS[t]
			var v := _card()
			v.add_child(Kit.lbl("%s  %dg  (wage %dg)" % [def["name"], int(e.call("recruit_cost", sid, t)), int(def["wage"])], 17, AF.TEXT, true))
			v.add_child(Kit.lbl("%d volunteers. Needs standing %d." % [int(pool.get(t, 0)), int(def["standing"])], 14, AF.TEXT_DIM, true))
			var why2 := String(e.call("can_recruit", sid, t, 1))
			var row := _flow()
			row.add_child(_btn("Recruit 1", func() -> void: _act(e.call("recruit", sid, t, 1), "Recruited."), true, why2 != "", 48.0))
			row.add_child(_btn("Recruit 5", func() -> void: _act(e.call("recruit", sid, t, 5), "Recruited."), false, String(e.call("can_recruit", sid, t, 5)) != "", 48.0))
			v.add_child(row)
			if why2 != "":
				v.add_child(Kit.lbl(why2, 13, AF.TEXT_DIM, true, "italic"))
			grid.add_child(_framed(v))
	_section("Mercenary contracts")
	var mw := String(e.call("can", "mercenary"))
	var contract: Dictionary = e.get("merc")
	if not contract.is_empty():
		_box.add_child(Kit.lbl("Under contract to %s: %d days left, %dg earned so far." % [contract["name"], int(contract["days_left"]), int(contract["earned"])], 17, GOOD, true))
		_box.add_child(_btn("Break the contract", func() -> void:
			e.call("break_merc")
			rebuild(), false, false, 48.0))
	elif mw != "":
		_note(mw, WARN)
	else:
		for o: Dictionary in e.call("merc_offers"):
			var v2 := _card()
			v2.add_child(Kit.lbl("%s: %.1fg per man per day, %d days, at least %d troops, bonus %dg" % [o["name"], float(o["rate"]), int(o["days"]), int(o["min_troops"]), int(o["bonus"])], 16, AF.TEXT, true))
			v2.add_child(_btn("Accept", func() -> void: _act(e.call("accept_merc", String(o["id"])), "You sign the contract."), false, false, 48.0))
			_box.add_child(_framed(v2))
	_section("Vassalage")
	var vw := String(e.call("can", "vassal"))
	if String(ci["liege"]) != "":
		_box.add_child(Kit.lbl("You hold your lands from %s. A weekly tithe is due; in return your roads are safer and your name grows." % ci["liege"], 16, AF.TEXT, true))
		_box.add_child(_btn("Renounce your oath", func() -> void:
			e.call("renounce_vassal")
			rebuild(), false, false, 48.0))
	elif vw != "":
		_note(vw, WARN)
	else:
		var vf := _flow()
		var fa := _mod("factions")
		if fa != null:
			for f: Dictionary in fa.call("factions"):
				if String(f["kind"]) in ["nation", "house"] and String(f["id"]) != "player":
					var fid2 := String(f["id"])
					vf.add_child(_btn("Swear to %s" % f["name"], func() -> void: _act(e.call("swear_vassal", fid2), "You kneel."), false, false, 48.0))
		_box.add_child(vf)
	_section("Army duties")
	var dw := String(e.call("can", "duty"))
	var duty: Dictionary = e.get("duty")
	if dw != "":
		_note(dw)
	elif not duty.is_empty():
		_box.add_child(Kit.lbl("On duty: %s, %d days left." % [String((D.DUTIES[String(duty["kind"])] as Dictionary)["name"]), int(duty["days_left"])], 17, GOOD, true))
	else:
		for o: Dictionary in e.call("duty_board", sid):
			var v3 := _card()
			v3.add_child(Kit.lbl("%s: %d days, %dg a day. %s" % [o["name"], int(o["days"]), int(o["pay"]), o["text"]], 16, AF.TEXT, true))
			v3.add_child(_btn("Take the duty", func() -> void: _act(e.call("take_duty", String(o["kind"]), sid), "You report for duty."), false, false, 48.0))
			_box.add_child(_framed(v3))
