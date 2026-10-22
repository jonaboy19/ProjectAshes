extends Control
## The siege screen (docs/design/WAR_COMMAND_RULEBOOK.md §41-47; reference panels "Siege Map", "Siege Progress", "Fortress
## Defense"). Left: the real ground round the fortress with walls, gates, towers, breaches, inner lines, the camp, engines and
## the tunnel. Right: tabs Overview / Siege Engines / Garrison / Plan with the walls-garrison-supplies-morale summary, the plan
## checklist, build and approach controls, advisors, and Assault / Negotiate buttons. Assaults open the tactical battle map.

signal closed

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Tokens := preload("res://scripts/ui/war/war_tokens.gd")
const Extras := preload("res://scripts/ui/war/war_extras.gd")
const Siege := preload("res://scripts/realm/siege.gd")
const Tac := preload("res://scripts/realm/tactical.gd")
const WarAdvisors := preload("res://scripts/realm/war_advisors.gd")

const TABS := [["overview", "Overview"], ["engines", "Siege Engines"], ["garrison", "Garrison"], ["plan", "Plan"]]
const PANEL_W := 390.0
const SPAN := 560.0

var sg: RefCounted = null
var cm: RefCounted = null
var key := ""
var tab := "overview"
var status_text := ""
var rep: Dictionary = {}

var _canvas: Control
var _layer: Control
var _panel: VBoxContainer
var _row: BoxContainer
var _title: Label
var _tex: ImageTexture
var _ring: Dictionary = {}
var _font: Font
var _toast: Label
var _staff: Array = []
var _target_wall := -1
var _built := false


static func open_modal(host: Node, siege: RefCounted, campaign: RefCounted = null, siege_key := "") -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 72
	var v: Control = load("res://scripts/ui/war/siege_view.gd").new()
	v.set("sg", siege)
	v.set("cm", campaign)
	v.set("key", siege_key)
	layer.add_child(v)
	v.connect("closed", layer.queue_free)
	host.add_child(layer)
	return v


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = AF.font(AF.BODY_FONT)
	if sg != null:
		_build()


func set_siege(s: RefCounted) -> void:
	sg = s
	if is_inside_tree() and not _built:
		_build()


func _build() -> void:
	if _built or sg == null:
		return
	_built = true
	_staff = cm.call("war_staff") if cm != null else WarAdvisors.roster(int(sg.s["seed"]))
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
	_row.add_child(_canvas)
	_layer = DioLayer.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set("view", self)
	_canvas.add_child(_layer)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.035, 0.03, 0.027, 0.97), AF.GOLD_DIM, 0, 10))
	pc.custom_minimum_size = Vector2(PANEL_W, 260)
	_row.add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	sc.add_child(_panel)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.88), AF.GOLD_DIM, 4, 6))
	bar.position = Vector2(8, 8)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)
	_title = Kit.lbl("", 20, AF.GOLD_BRIGHT, false, "title_bold")
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title)
	var x := Kit.tab_button("Close", false, close, 80)
	x.custom_minimum_size.y = 46
	h.add_child(x)
	_canvas.add_child(bar)
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
	_row.resized.connect(_relayout)
	_relayout()
	refresh()


func _relayout() -> void:
	if _row == null:
		return
	var portrait := size.x < size.y or size.x < 820.0
	_row.vertical = portrait
	(_panel.get_parent().get_parent() as Control).custom_minimum_size = Vector2(0, size.y * 0.5) if portrait else Vector2(PANEL_W, 0)


func say(text: String) -> void:
	status_text = text
	if _toast:
		_toast.text = text
		var t := get_tree().create_timer(6.0)
		t.timeout.connect(func() -> void:
			if is_instance_valid(_toast) and _toast.text == text:
				_toast.text = "")


func close() -> void:
	closed.emit()


func set_tab(t: String) -> void:
	tab = t
	refresh()


func _war_rep() -> Dictionary:
	if not rep.is_empty():
		return rep
	return {"honour": 0.0, "ruthless": 0.0, "cowardly": 0.0, "label": "unknown"}


## Rebuilds the terrain backdrop (once) and the panel.
func refresh() -> void:
	if sg == null or not _built:
		return
	var v: Dictionary = sg.view()
	_title.text = "%s - Siege, day %d" % [String(v["name"]), int(sg.s["day"])]
	if _tex == null:
		_build_backdrop()
	_rebuild_panel(v)
	_layer.queue_redraw()


func _build_backdrop() -> void:
	_ring = sg.call("_ring_opts")
	var pos: Array = sg.s["pos"]
	var g := Tac.gen_grid(Vector2(float(pos[0]), float(pos[1])), 56, 10.0, _ring)
	var n := 56
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cols := [Color("2a332a"), Color("17301f"), Color("3a382d"), Color("4c4a42"), Color("163f5e"), Color("1d506c"), Color("b8ae98"), Color("d0c8b0"), Color("5a544c"), Color("1e3b35"), Color("8a8a8a"), Color("b07a30"), Color("6a5a40"), Color("a07a30"), Color("b0b0b0"), Color("4a3a2a"), Color("403a34"), Color("c8a848")]
	for j in n:
		var row: String = (g["rows"] as Array)[j]
		for i in n:
			var code := maxi(Tac.CHARS.find(row[i]), 0)
			var c: Color = cols[code]
			var hv := float((g["h"] as Array)[j * n + i]) * 0.1
			var hl := float((g["h"] as Array)[j * n + maxi(i - 1, 0)]) * 0.1
			var sh := clampf((hl - hv) * 0.05, -0.15, 0.15)
			img.set_pixel(i, j, c.lightened(sh) if sh > 0.0 else c.darkened(-sh))
	_tex = ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ panel --

func _card(border := AF.GOLD_DIM) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.6), border, 3, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	_panel.add_child(pc)
	return v


func _btn(text: String, cb: Callable, primary := false, h := 48.0) -> Button:
	var b := Kit.button(text, primary, h, 16)
	b.pressed.connect(cb)
	return b


func _stat(parent: Control, name_: String, value: String, col := AF.TEXT) -> void:
	var h := HBoxContainer.new()
	var l := Kit.lbl(name_, 15, AF.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(Kit.lbl(value, 16, col))
	parent.add_child(h)


func _rebuild_panel(v: Dictionary) -> void:
	Kit.clear(_panel)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	for t: Array in TABS:
		var b := Kit.tab_button(String(t[1]), String(t[0]) == tab, set_tab.bind(String(t[0])), 90)
		b.custom_minimum_size.y = 44
		tabs.add_child(b)
	_panel.add_child(tabs)
	if String(v["status"]) != "active":
		var e := _card(AF.GOLD)
		e.add_child(Kit.lbl("The siege is over: %s." % String(v["status"]), 19, AF.GOLD_BRIGHT, true, "title_bold"))
		if String(v["status"]) == "fallen":
			e.add_child(Kit.lbl("How will you treat the place?", 15, AF.TEXT_DIM, true))
			for spec: Array in [["Spare the people", "spare"], ["Let the men plunder", "plunder"], ["Massacre", "massacre"]]:
				e.add_child(_btn(String(spec[0]), _conduct.bind(String(spec[1])), false, 44.0))
		if String(v["status"]) == "fallen":
			var node := -1
			if cm != null:
				node = int(cm.call("nearest_node", Vector2(float((sg.s["pos"] as Array)[0]), float((sg.s["pos"] as Array)[1]))))
			var info := Extras.occupation_info(cm.get("hub") if cm != null else null, node, maxi(int(v["garrison"]), 30))
			info["name"] = String(v["name"])
			Extras.build_occupation(_panel, info, Callable())
		return
	match tab:
		"overview":
			_tab_overview(v)
		"engines":
			_tab_engines(v)
		"garrison":
			_tab_garrison(v)
		"plan":
			_tab_plan(v)
	_advisors(v)


func _tab_overview(v: Dictionary) -> void:
	var c := _card(AF.GOLD)
	c.add_child(Kit.lbl("Siege Plan", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	for it: Dictionary in v["plan"]:
		var row := HBoxContainer.new()
		row.add_child(Kit.lbl("[x] " if bool(it["done"]) else "[ ] ", 16, Color("9be36a") if bool(it["done"]) else AF.TEXT_DIM))
		row.add_child(Kit.lbl(String(it["label"]), 16, AF.TEXT if not bool(it["done"]) else AF.TEXT_DIM))
		c.add_child(row)
	var s := _card()
	_stat(s, "Walls", String(v["walls"]))
	_stat(s, "Garrison", "~%d" % (int(round(float(v["garrison"]) / 10.0)) * 10))
	_stat(s, "Supplies", "%d days" % int(round(float(v["food_days"]))), AF.TEXT if float(v["food_days"]) > 6.0 else Color("ff9a6a"))
	_stat(s, "Water", "%d days" % int(round(float(v["water_days"]))))
	_stat(s, "Morale", String(v["morale_label"]))
	_stat(s, "Civilians", str(v["civilians"]))
	_stat(s, "Battle layer", String(v["layer"]))
	if int(v["inner_lines"]) > 0:
		_stat(s, "Inner lines", str(v["inner_lines"]), Color("ffb070"))
	var camp: Dictionary = v["camp"]
	var k := _card()
	k.add_child(Kit.lbl("Your Camp", 16, AF.GOLD))
	_stat(k, "Men", str(camp["men"]))
	_stat(k, "Engineers", str(camp["engineers"]))
	_stat(k, "Guards", str(camp["guards"]))
	_stat(k, "Food", "%d days" % int(round(float(camp["food_days"]))))
	_stat(k, "Timber", str(int(round(float(camp["wood"])))))
	var a := _card()
	a.add_child(_btn("Assault (command the battle)", _assault_manual, true, 54.0))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	row2.add_child(_btn("Auto-assault", _assault_auto, false, 46.0))
	row2.add_child(_btn("Negotiate", _negotiate, false, 46.0))
	a.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	row3.add_child(_btn("Wait a day", _wait.bind(1), false, 46.0))
	row3.add_child(_btn("Wait a week", _wait.bind(7), false, 46.0))
	a.add_child(row3)
	_log_card(v)


func _log_card(_v: Dictionary) -> void:
	var l := _card()
	l.add_child(Kit.lbl("Reports", 16, AF.GOLD))
	var lg: Array = sg.s["log"]
	for e: Dictionary in lg.slice(maxi(0, lg.size() - 5)):
		l.add_child(Kit.lbl("Day %d: %s" % [int(e["day"]), String(e["text"])], 13, AF.TEXT_DIM, true))


func _tab_engines(v: Dictionary) -> void:
	var c := _card(AF.GOLD)
	c.add_child(Kit.lbl("Siege Progress", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	for i in 4:
		var w: Dictionary = (sg.s["walls"] as Array)[i]
		var frac: float = sg.wall_fraction(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var lb := Kit.lbl(String(w["name"]), 14, AF.GOLD_BRIGHT if _target_wall == i else AF.TEXT)
		lb.custom_minimum_size = Vector2(92, 0)
		row.add_child(lb)
		var bar := Kit.bar(frac, 12.0, Color("c2412f") if frac < 0.4 else (Color("d0a040") if frac < 0.75 else Color("5fae4c")), "%d%%" % int(frac * 100.0))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var tb := Kit.button("Aim", _target_wall == i, 40.0, 13)
		tb.custom_minimum_size.x = 56
		tb.pressed.connect(_aim.bind(i))
		row.add_child(tb)
		c.add_child(row)
	for gt: Dictionary in sg.s["gates"]:
		var gf := clampf(float(gt["hp"]) / float(gt["max"]), 0.0, 1.0)
		var gr := HBoxContainer.new()
		var gl := Kit.lbl(String(gt["name"]), 14, AF.TEXT)
		gl.custom_minimum_size = Vector2(92, 0)
		gr.add_child(gl)
		var gb := Kit.bar(gf, 12.0, Color("c2412f") if gf < 0.4 else Color("d0a040"), "%d%%" % int(gf * 100.0))
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gr.add_child(gb)
		c.add_child(gr)
	var e := _card()
	e.add_child(Kit.lbl("Siege Engines", 17, AF.GOLD))
	if (v["engines"] as Array).is_empty():
		e.add_child(Kit.lbl("No engines yet. Engineers build them over days: a ram for the gate, a tower for the wall, catapults and trebuchets for the stone.", 14, AF.TEXT_DIM, true, "italic"))
	for en: Dictionary in v["engines"]:
		var st := String(en["state"])
		var tail := "Ready" if st == "ready" else ("%d day%s" % [int(en["days_left"]), "" if int(en["days_left"]) == 1 else "s"] if st == "building" else "Destroyed")
		_stat(e, String(en["name"]), tail, Color("9be36a") if st == "ready" else (AF.TEXT if st == "building" else Color("ff7a6a")))
	var b := _card()
	b.add_child(Kit.lbl("Build Siege Engines (%d engineers, %d timber)" % [int(v["camp"]["engineers"]), int(round(float(v["camp"]["wood"])))], 15, AF.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	for k: String in Siege.ENGINE_ORDER:
		var d: Dictionary = Siege.ENGINES[k]
		var chk: Dictionary = sg.can_build(k)
		var bt := Kit.button("%s (%dd)" % [String(d["name"]), int(sg.build_days(k))], false, 44.0, 13)
		bt.disabled = not bool(chk["ok"])
		bt.tooltip_text = String(chk["reason"])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.pressed.connect(_build_engine.bind(k))
		grid.add_child(bt)
	b.add_child(grid)
	_log_card(v)


func _aim(i: int) -> void:
	_target_wall = i
	var es: Array = sg.s["engines"]
	for k in es.size():
		sg.set_target(k, i)
	say("Engines aimed at the %s." % String(((sg.s["walls"] as Array)[i] as Dictionary)["name"]).to_lower())
	refresh()


func _build_engine(k: String) -> void:
	var r: Dictionary = sg.build_engine(k)
	say("Construction begins: %d days." % int(r["days"]) if bool(r["ok"]) else String(r["reason"]))
	refresh()


func _tab_garrison(v: Dictionary) -> void:
	var c := _card(AF.GOLD)
	c.add_child(Kit.lbl("Fortress Defence", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	c.add_child(Kit.lbl("Assign Troops (garrison %d)" % int(v["garrison"]), 15, AF.TEXT_DIM))
	var df: Dictionary = v["defence"]
	for spec: Array in [["Gate", "gate"], ["Wall West", "wall_w"], ["Wall East", "wall_e"], ["Inner Court", "inner"], ["Reserve", "reserve"]]:
		_stat(c, String(spec[0]), "(%d)" % int(df[spec[1]]))
	c.add_child(_btn("Auto Assign", func() -> void: sg.auto_assign(); refresh(), false, 44.0))
	var s := _card()
	s.add_child(Kit.lbl("Defensive Structures", 16, AF.GOLD))
	var st: Dictionary = v["structures"]
	for spec2: Array in [["Boiling oil", "oil"], ["Stakes and trenches", "stakes"], ["Barricades", "barricades"], ["Archers on the walls", "archers"]]:
		var cb := CheckButton.new()
		cb.text = String(spec2[0])
		cb.button_pressed = bool(st[spec2[1]])
		cb.toggled.connect(func(on: bool) -> void: sg.set_structure(String(spec2[1]), on))
		s.add_child(cb)
	var g := _card()
	g.add_child(Kit.lbl("Commander: %s (%s)" % [String(v["commander"]["name"]), String(v["commander"]["personality"])], 15, AF.TEXT, true))
	_stat(g, "Inner lines", str(v["inner_lines"]))
	_stat(g, "Street layers", " > ".join(PackedStringArray(v["layers"])))
	g.add_child(Kit.lbl("Tower and wall fighters: %d towers" % _tower_count(), 13, AF.TEXT_DIM))
	_log_card(v)


func _tower_count() -> int:
	var n := 0
	for w: Dictionary in sg.s["walls"]:
		n += int(w["tower"])
	return n


func _tab_plan(v: Dictionary) -> void:
	var c := _card(AF.GOLD)
	c.add_child(Kit.lbl("Approaches", 18, AF.GOLD_BRIGHT, false, "title_bold"))
	c.add_child(Kit.lbl("Several can run together. Sieges consume enormous resources.", 13, AF.TEXT_DIM, true, "italic"))
	var ap: Dictionary = v["approaches"]
	for k: String in Siege.APPROACHES:
		if k in ["negotiate", "bribe"]:
			continue
		var cb := CheckButton.new()
		cb.text = String(Siege.APPROACH_NAMES[k])
		cb.button_pressed = bool(ap.get(k, false))
		cb.toggled.connect(_toggle_approach.bind(k))
		c.add_child(cb)
	var b := _card()
	b.add_child(Kit.lbl("Agents", 16, AF.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_btn("Bribe (300)", _bribe.bind(300), false, 44.0))
	row.add_child(_btn("Bribe (1000)", _bribe.bind(1000), false, 44.0))
	b.add_child(row)
	var t := _card()
	t.add_child(Kit.lbl("Tunnel", 16, AF.GOLD))
	var tn: Dictionary = v["tunnel"]
	if int(tn["wall"]) >= 0:
		t.add_child(Kit.bar(clampf(float(tn["progress"]), 0.0, 1.0), 12.0, Color("d0a040"), "%d%%" % int(float(tn["progress"]) * 100.0)))
	else:
		var tr := HBoxContainer.new()
		for i in 4:
			tr.add_child(_btn(["N", "E", "S", "W"][i], _tunnel.bind(i), false, 44.0))
		t.add_child(tr)
	_log_card(v)


func _toggle_approach(on: bool, k: String) -> void:
	sg.approach(k, on)
	say("%s%s." % [String(Siege.APPROACH_NAMES[k]), "" if on else " stopped"])
	refresh()


func _tunnel(i: int) -> void:
	var r: Dictionary = sg.start_tunnel(i)
	say("Sappers start digging." if bool(r["ok"]) else String(r["reason"]))
	refresh()


func _bribe(gold: int) -> void:
	var r: Dictionary = sg.bribe(gold)
	say("A gate will be left open tonight." if bool(r["ok"]) else "The offer was refused.")
	refresh()


func _advisors(v: Dictionary) -> void:
	var lines: Array
	if cm != null and key != "":
		lines = cm.call("siege_advice", key)
	else:
		lines = WarAdvisors.siege_advice(v, _staff, int(sg.s["seed"]), int(sg.s["day"]) / 3, sg.s["walls"])
	if lines.is_empty():
		return
	var c := _card()
	c.add_child(Kit.lbl("Advisors", 16, AF.GOLD))
	for l: Dictionary in lines:
		c.add_child(Kit.lbl("%s (%s): %s" % [String(l["title"]), String(l["confidence"]), String(l["text"])], 14, AF.TEXT, true, "italic"))


# ---------------------------------------------------------------- actions --

func _wait(days: int) -> void:
	var out: Array = []
	for i in days:
		out.append_array(sg.tick_day())
		if bool(sg.s["sortie_due"]):
			sg.auto_sortie()
		if String(sg.s["status"]) != "active":
			break
	say(String(out[out.size() - 1]) if not out.is_empty() else "The siege goes on.")
	if String(sg.s["status"]) == "fallen" and cm != null and key != "":
		cm.call("siege_conduct", key, "")
	refresh()


func _assault_auto() -> void:
	var r: Dictionary = cm.call("siege_assault", key) if cm != null and key != "" else sg.auto_assault()
	if r.is_empty():
		r = {"lines": ["The assault is over."]}
	say(String((r["lines"] as Array)[0]) if not (r.get("lines", []) as Array).is_empty() else "The assault is over.")
	refresh()


func _assault_manual() -> void:
	var spec: Dictionary = sg.assault_spec()
	var tt: RefCounted = Tac.create(spec)
	var host: Node = get_parent() if get_parent() != null else self
	var view: Control = load("res://scripts/ui/war/tactical_view.gd").open_modal(host, tt, null, -1, Callable())
	view.connect("finished", func(res: Dictionary) -> void:
		var r: Dictionary = sg.apply_assault(res)
		say(String((r["lines"] as Array)[0]) if not (r["lines"] as Array).is_empty() else "The assault is over.")
		refresh())


func _negotiate() -> void:
	var ev: Dictionary = cm.call("siege_negotiate", key) if cm != null and key != "" else sg.negotiate(_war_rep())
	if bool(ev.get("surrendered", false)):
		say("The garrison surrenders.")
	else:
		say("Refused: %s." % String(", ".join(PackedStringArray(ev.get("reasons", [])))) if not (ev.get("reasons", []) as Array).is_empty() else "Refused.")
	refresh()


func _conduct(kind: String) -> void:
	if cm != null and key != "":
		cm.call("siege_conduct", key, kind)
	else:
		sg.conduct(kind)
	say({"spare": "You spare the townsfolk.", "plunder": "The men plunder the town.", "massacre": "The town is put to the sword. Others will remember."}[kind])
	refresh()


func _canvas_input(_e: InputEvent) -> void:
	pass


# ---------------------------------------------------------------- drawing --

class DioLayer extends Control:
	var view: Control

	func _draw() -> void:
		if view != null:
			view.call("_draw_dio", self)


func _w2s(p: Vector2, rect: Rect2) -> Vector2:
	var c := Vector2(float((sg.s["pos"] as Array)[0]), float((sg.s["pos"] as Array)[1]))
	return rect.position + rect.size * 0.5 + (p - c) * (rect.size.x / SPAN)


func _draw_dio(ci: Control) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color("0a0c0c"))
	if _tex == null:
		return
	var side := minf(ci.size.x - 20.0, ci.size.y - 130.0)
	var rect := Rect2(Vector2((ci.size.x - side) * 0.5, 100.0 + maxf(0.0, (ci.size.y - 130.0 - side) * 0.5)), Vector2(side, side))
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ci.draw_texture_rect(_tex, rect, false)
	ci.draw_rect(rect, AF.GOLD_DIM, false, 2.0)
	var k := side / SPAN
	var cpos := Vector2(float((sg.s["pos"] as Array)[0]), float((sg.s["pos"] as Array)[1]))
	var c := rect.position + rect.size * 0.5
	var r := float(sg.s["radius"]) * k
	# walls as four arcs coloured by condition
	for i in 4:
		var w: Dictionary = (sg.s["walls"] as Array)[i]
		var frac: float = sg.wall_fraction(i)
		var a0 := float(w["dir"]) - PI * 0.25
		var col := Color("5fae4c").lerp(Color("c2412f"), 1.0 - frac)
		if bool(w["breach"]):
			col = Color("ff5030")
		ci.draw_arc(c, r, a0 + 0.04, a0 + PI * 0.5 - 0.04, 20, Color(col, 0.95), maxf(5.0, 9.0 * k * 2.0), true)
		var mid := c + Vector2.from_angle(float(w["dir"])) * (r + 16.0 * k * 2.0)
		Tokens.text_centered(ci, _font, "%s %d%%" % [String(w["name"]).replace(" wall", ""), int(frac * 100.0)], mid + Vector2.from_angle(float(w["dir"])) * 26.0, 14, Color.WHITE, Color(0, 0, 0, 0.9), 4)
		if bool(w["breach"]):
			var bp := c + Vector2.from_angle(float(w["dir"])) * r
			ci.draw_circle(bp, 9.0, Color("ff7030"))
			Tokens.text_centered(ci, _font, "BREACH", bp + Vector2(0, 22), 13, Color("ffb080"), Color(0, 0, 0, 0.9), 4)
	for gt: Dictionary in sg.s["gates"]:
		var gp := c + Vector2.from_angle(float(gt["dir"])) * r
		var gc := Color("c8a060") if float(gt["hp"]) > 0.0 else Color("ff5030")
		ci.draw_rect(Rect2(gp - Vector2(9, 9), Vector2(18, 18)), gc)
		ci.draw_rect(Rect2(gp - Vector2(9, 9), Vector2(18, 18)), Color.BLACK, false, 2.0)
	for t in 10:
		var ta := TAU * float(t) / 10.0
		ci.draw_circle(c + Vector2.from_angle(ta) * r, maxf(4.5, 5.0 * k * 2.0), Color("d8d0b8"))
	# inner lines behind breaches
	var inner: Array = (_ring.get("ring", {}) as Dictionary).get("inner", [])
	for il: Dictionary in inner:
		ci.draw_arc(c, float(il["r"]) * k, float(il["a"]) - float(il["span"]), float(il["a"]) + float(il["span"]), 14, Color("ffb040"), 3.0, true)
	Tokens.glyph(ci, "army", c, 14.0, Color("ff8a7a"), 3.0)
	Tokens.text_centered(ci, _font, "%d defenders" % int(sg.s["garrison"]), c + Vector2(0, 26), 15, Color("ffb0a0"), Color(0, 0, 0, 0.9), 4)
	# camp
	var cp: Array = (sg.s["camp"] as Dictionary)["pos"]
	var cs := _w2s(Vector2(float(cp[0]), float(cp[1])), rect)
	for t2 in 9:
		var o := Vector2(float(t2 % 3) - 1.0, float(t2 / 3) - 1.0) * 17.0
		ci.draw_colored_polygon(PackedVector2Array([cs + o + Vector2(0, -9), cs + o + Vector2(-8, 6), cs + o + Vector2(8, 6)]), Color("4a78c0"))
	Tokens.text_centered(ci, _font, "Camp: %d men" % int((sg.s["camp"] as Dictionary)["men"]), cs + Vector2(0, 36), 15, Color("a8c8ff"), Color(0, 0, 0, 0.9), 4)
	# engines lined up before the walls they aim at
	var ready := 0
	for e: Dictionary in sg.s["engines"]:
		if String(e["state"]) == "destroyed":
			continue
		var tw := int(e["target"])
		var dir := float((sg.s["walls"] as Array)[tw if tw >= 0 else 1]["dir"])
		var ep := c + Vector2.from_angle(dir + 0.25 + float(ready) * 0.12) * (r + 62.0)
		ready += 1
		var done := String(e["state"]) == "ready"
		var ec := Color("9be36a") if done else Color("d0a040")
		ci.draw_rect(Rect2(ep - Vector2(9, 6), Vector2(18, 12)), ec)
		ci.draw_line(ep, ep + Vector2.from_angle(dir + PI) * 26.0, Color(ec, 0.7), 2.0)
		if not done:
			Tokens.text_centered(ci, _font, "%dd" % int(ceil(float(e["left"]))), ep + Vector2(0, -14), 12, Color("ffe6a0"), Color(0, 0, 0, 0.9), 3)
	var tn: Dictionary = sg.s["tunnel"]
	if int(tn["wall"]) >= 0:
		var td := float((sg.s["walls"] as Array)[int(tn["wall"])]["dir"])
		Tokens.dashed(ci, c + Vector2.from_angle(td) * (r + 86.0), c + Vector2.from_angle(td) * (r + 86.0 - (86.0 * float(tn["progress"]))), Color("d8b070"), 3.0, 8.0, 6.0)
	# bombardment arrows
	if bool((sg.s["approaches"] as Dictionary).get("bombard", false)) and ready > 0:
		var tw2 := maxi(_target_wall, 0)
		var d2 := float((sg.s["walls"] as Array)[tw2]["dir"])
		Tokens.arrow_head(ci, c + Vector2.from_angle(d2) * (r + 4.0), Vector2.from_angle(d2 + PI), Color("ffb040"), 14.0)
	# legend line
	ci.draw_string(_font, Vector2(rect.position.x + 6.0, rect.end.y + 18.0), "Real ground around %s. Walls show condition; orange arcs are the inner defence lines." % String(sg.s["name"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 13, AF.TEXT_DIM)
