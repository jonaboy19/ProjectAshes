extends Control
## Career work and ladder screen (portrait first). Two tabs per trade:
##   Work    the trade's tasks as real mini-games: for the Scribe copying (pick the faithful line, steady
##           the pen), forgery (examine seal, hand, date and ink against the archive specimen), old
##           script (glyphs you know read themselves), tax ledgers, restricted records and what to do with
##           a noble secret, exams, the steward's estate, the envoy's embassy. For farmer, soldier,
##           merchant and blacksmith the steps of scripts/realm/career_trades.gd.
##   Ladder  every rank, the next rank's requirements with ticks and crosses, patron and standing.
## Embedded mode (open_rich) runs one scribe task for the work-shift UI (work_spots.gd) and reports
## the quality through task_done.
## Reads the realm hub through Life.realm; `modules` lets tests and screenshot scenes inject their own.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const Widget := preload("res://scripts/ui/work_widget.gd")
const Data := preload("res://scripts/realm/scribe_data.gd")
const SELF_PATH := "res://scripts/ui/career_tasks.gd"
const OK_COL := Color("7be0a0")
const BAD_COL := Color("ff7a6e")
const CAREER_NAMES := {"scribe": "Scribe", "farmer": "Farmer", "soldier": "Soldier", "merchant": "Merchant", "blacksmith": "Blacksmith"}
const CAREER_ORDER := ["scribe", "farmer", "soldier", "merchant", "blacksmith"]

signal task_done(quality: float, result: Dictionary)
signal closed

static var modules: Dictionary = {}     # injected {"scribe": module, "trades": module}
static var day_override := -1

var career := "scribe"
var embedded := false
var _was_paused := false
var _tab := "work"
var _title: Label
var _sub: Label
var _msg: Label
var _content: VBoxContainer
var _panel: PanelContainer
var _tabs: HBoxContainer
var _scratch: Dictionary = {}
var _entrance := false
var _pending_hours := 0.0


## Opens the screen for a trade under `parent` (a CanvasLayer such as the HUD).
static func open_for(parent: Node, trade := "scribe") -> Control:
	var s: Control = parent.get_node_or_null("CareerTasks")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "CareerTasks"
		parent.add_child(s)
	s.call("open", trade)
	return s


## Runs one scribe task (copy, forgery, tax) for the shift UI. Returns null when it cannot start.
static func open_rich(parent: Node, kind: String) -> Control:
	var s: Control = (load(SELF_PATH) as GDScript).new()
	s.name = "CareerTasksRich"
	s.set("embedded", true)
	parent.add_child(s)
	if not bool(s.call("open_task", kind)):
		s.queue_free()
		return null
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD, 4, 14))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", AF.wfont(700))
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_sub = AF.label("", 16, AF.TEXT_DIM, true)
	box.add_child(_sub)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	box.add_child(_tabs)
	for t: Array in [["work", "Work"], ["ladder", "Ladder"]]:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_set_tab.bind(String(t[0])))
		b.name = "Tab_" + String(t[0])
		_tabs.add_child(b)
	_msg = AF.label("", 17, AF.GOLD_BRIGHT, true)
	box.add_child(_msg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var close := AF.gold_button("Close")
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(close_screen)
	box.add_child(close)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vw := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vw
	var w := clampf(vw.x * 0.96, 320.0, 720.0)
	var h := vw.y * 0.95
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -w * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func open(trade := "scribe") -> void:
	career = trade
	if not visible:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
	_tab = "work"
	_scratch = {}
	_refresh()


func close_screen() -> void:
	if not visible and not embedded:
		return
	visible = false
	get_tree().paused = _was_paused
	closed.emit()
	if embedded:
		queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if visible and not embedded and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_screen()


# ------------------------------------------------------------------ module access

func _mod(name: String) -> RefCounted:
	if modules.has(name):
		return modules[name]
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod(name) if hub != null else null


func _sc() -> RefCounted:
	return _mod("scribe")


func _tr() -> RefCounted:
	return _mod("trades")


func _day() -> int:
	return day_override if day_override >= 0 else int(WorldSim.day)


func _is_scribe() -> bool:
	return career == "scribe"


# ------------------------------------------------------------------ widgets

func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_msg.text = ""


func _add(n: Control) -> Control:
	_content.add_child(n)
	return n


func _text(t: String, size := 18, col := AF.TEXT, italic := false) -> Label:
	var l := AF.label(t, size, col, italic)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(l)
	return l


func _card(title: String, body: String, accent := AF.GOLD) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", AF.panel(AF.PANEL_SOFT, accent, 3, 12))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	if title != "":
		var t := AF.label(title, 20, AF.GOLD_BRIGHT)
		t.add_theme_font_override("font", AF.wfont(600))
		v.add_child(t)
	if body != "":
		v.add_child(AF.label(body, 17, AF.TEXT))
	_content.add_child(pc)
	return v


func _btn(text: String, cb: Callable, enabled := true) -> Button:
	var b := AF.gold_button(text)
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.disabled = not enabled
	b.pressed.connect(cb)
	_content.add_child(b)
	return b


func _option(parent: Control, text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", AF.slot())
	b.add_theme_stylebox_override("hover", AF.slot(true))
	b.add_theme_stylebox_override("pressed", AF.slot(true))
	b.toggle_mode = toggle
	if toggle:
		b.toggled.connect(func(on: bool) -> void: cb.call(on))
	else:
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _bar(q: float) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = 100
	p.value = q * 100.0
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 14)
	_content.add_child(p)
	return p


## Width for a timing bar that fits the panel (a 540 px wide portrait phone leaves about 460).
func _bar_width() -> float:
	return clampf(_panel.size.x - 70.0 if _panel != null and _panel.size.x > 100.0 else get_viewport().get_visible_rect().size.x * 0.96 - 70.0, 240.0, 560.0)


func _set_tab(t: String) -> void:
	_tab = t
	_scratch = {}
	_refresh()


func _say(t: String) -> void:
	_msg.text = t


# ------------------------------------------------------------------ chrome

func _refresh() -> void:
	_clear()
	if _tabs != null:
		_tabs.visible = not embedded
		for c: Node in _tabs.get_children():
			if c is Button:
				(c as Button).set_pressed_no_signal(String(c.name) == "Tab_" + _tab)
	_title.text = "%s: %s" % [String(CAREER_NAMES.get(career, career)), _rank_title()]
	_sub.text = _subtitle()
	if _tab == "ladder":
		_show_ladder()
	else:
		_show_work()


func _rank_title() -> String:
	if _is_scribe():
		var sc := _sc()
		return sc.rank_title() if sc != null and bool(sc.get("active")) else ("Unemployed" if sc != null and int(sc.get("rank")) == 0 else "Out of post")
	var tr := _tr()
	return tr.rank_title(career) if tr != null else "-"


func _subtitle() -> String:
	if _is_scribe():
		var sc := _sc()
		if sc == null:
			return ""
		if not bool(sc.get("active")):
			return "Piece work only. Apply at a scriptorium for a post."
		var p: Dictionary = sc.get("patron")
		return "Patron %s (regard %d). Standing %d. Blots %d of %d." % [String(p.get("name", "-")), int(sc.patron_regard()), int(sc.get("standing")), int(sc.get("blots")), int(sc.BLOTS_TO_FIRE)]
	var tr := _tr()
	if tr == null:
		return ""
	return "Rank: %s. %s" % [tr.rank_title(career), "Hours left today: %d" % int(tr.hours_left(_day()))]


# ------------------------------------------------------------------ work tab

func _show_work() -> void:
	if _is_scribe():
		_show_scribe_menu()
	else:
		_show_trade_menu()


func _show_scribe_menu() -> void:
	var sc := _sc()
	if sc == null:
		_text("The scriptorium is closed.")
		return
	var day := _day()
	if sc.is_jailed(day):
		_card("In the cells", "You are held until day %d. Your fingers are stained and your name is on a roll." % int(sc.get("jail_until")), AF.RED)
	elif not bool(sc.get("active")):
		var why: String = sc.apply_refusal(int(sc.get("home_sid")), day)
		var v := _card("A desk for hire", "The scriptorium takes copyists who can hold a pen. Make a clean copy for the entrance test; better than half faithful earns a desk." if why == "" else why)
		_btn("Take the entrance test", _entrance_test, why == "")
	for o: Dictionary in sc.offers(day):
		if String(o["kind"]) in ["estate", "embassy"] and not bool(o["available"]) and int(sc.get("rank")) < int(o["rank_min"]):
			continue
		var label := "%s  (%d h)" % [String(o["label"]), int(o["hours"])]
		var b := _btn(label if bool(o["available"]) else "%s  -  %s" % [label, String(o["why"])], _start.bind(String(o["kind"])), bool(o["available"]))
		b.tooltip_text = String(o["text"])
		if bool(o["available"]):
			var d := AF.label(String(o["text"]), 15, AF.TEXT_DIM, true)
			_content.add_child(d)
	_show_secrets_summary()


func _show_secrets_summary() -> void:
	var sc := _sc()
	var held := 0
	for s: Dictionary in sc.get("secrets"):
		if String(s["state"]) == "held":
			held += 1
	if held > 0:
		_card("Secrets you hold: %d" % held, "Secrets kept folded in your private book. They will be worth something, or be your ruin.")


func _entrance_test() -> void:
	_entrance = true
	_start("copy")


func _start(kind: String) -> void:
	var sc := _sc()
	var day := _day()
	_scratch = {}
	match kind:
		"audience":
			_render_audience()
		"study":
			var r: Dictionary = sc.study_glyphs(day)
			_refresh()
			_say(String(r.get("text", r.get("reason", ""))))
			if bool(r.get("ok", false)):
				_pending_hours += float(sc.TASK_HOURS["study"])
				_advance_clock()
		"restricted":
			_render_restricted()
		"estate":
			_render_estate()
		"embassy":
			_render_embassy()
		_:
			var b: Dictionary = sc.begin(kind, day)
			if not bool(b["ok"]):
				_say(String(b["reason"]))
				return
			_render_task()


## Embedded entry: begin a scribe task and show it straight away.
func open_task(kind: String) -> bool:
	career = "scribe"
	var sc := _sc()
	if sc == null:
		return false
	var b: Dictionary = sc.begin(kind, _day())
	if not bool(b["ok"]):
		return false
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_refresh()
	_render_task()
	return true


func _render_task() -> void:
	_clear()
	var sc := _sc()
	var v: Dictionary = sc.task_view()
	if v.is_empty():
		_refresh()
		return
	match String(v["kind"]):
		"copy":
			_render_copy(v)
		"forgery":
			_render_forgery(v)
		"translate":
			_render_translate(v)
		"tax":
			_render_tax(v)
		"exam":
			_render_exam(v)


# ------------------------------------------------------------------ copy

func _render_copy(v: Dictionary) -> void:
	var doc: Dictionary = v["doc"]
	var lines: Array = doc["lines"]
	var c: Dictionary = _scratch.get("copy", {"i": -1, "picks": [], "steady": 1.0})
	_scratch["copy"] = c
	_add(AF.heading(String(doc["title"]), 20))
	if int(c["i"]) < 0:
		_text("Steady your pen before you begin. Tap when the marker is in the gold; a shaky hand blots a line.", 17, AF.TEXT_DIM, true)
		var wd := Widget.new()
		wd.setup({"widget": "timing", "diff": 0.3, "zone": clampf(0.3 + float(v["level"]) * 0.002, 0.2, 0.42), "zone_at": 0.55, "options": [], "bar_w": _bar_width()})
		wd.finished.connect(func(q: float, _ch: int) -> void:
			c["steady"] = q
			c["i"] = 0
			_render_task())
		_add(wd)
		return
	var i := int(c["i"])
	if i >= lines.size():
		var res: Dictionary = _sc().submit_copy(c["picks"], float(c["steady"]))
		_after_copy(res)
		return
	var l: Dictionary = lines[i]
	_text("Line %d of %d%s" % [i + 1, lines.size(), "   (a sum, name or date: take care)" if bool(l["crit"]) else ""], 16, AF.TEXT_DIM)
	var src := _card("Copy exactly", "")
	src.add_child(AF.label("\"%s\"" % String(l["src"]), 22, AF.GOLD_BRIGHT, true))
	_text("Which line did your pen write?", 17, AF.TEXT_DIM)
	var opts: Array = l["options"]
	for k in opts.size():
		_option(_content, String(opts[k]), func() -> void:
			(c["picks"] as Array).append(k)
			c["i"] = i + 1
			_render_task())


func _after_copy(res: Dictionary) -> void:
	if _entrance:
		_entrance = false
		var sc := _sc()
		var ap: Dictionary = sc.apply(int(sc.get("home_sid")), _day(), float(res["quality"]))
		res["texts"] = (res.get("texts", []) as Array) + [String(ap.get("text", ap.get("reason", "")))]
	_show_result(res, float(_sc().TASK_HOURS["copy"]))


# ------------------------------------------------------------------ forgery

func _render_forgery(v: Dictionary) -> void:
	var doc: Dictionary = v["doc"]
	var st: Dictionary = _scratch.get("forge", {"named": [], "lens": false})
	_scratch["forge"] = st
	_add(AF.heading("Is it genuine?", 20))
	var card := _card("%s of %s" % [String(doc["kind"]).capitalize(), String(doc["house"])],
		"Issued in the name of %s, dated day %d. The archive holds a specimen of the issuer's seal and hand." % [String(doc["issuer"]), int(doc["day"])])
	_text("Examine it. Each look compares one thing with the specimen. A sharper eye, or the lens (an hour), sees finer differences.", 16, AF.TEXT_DIM, true)
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	var examined: Dictionary = v["examined"]
	for ch: String in Data.CHANNELS:
		var b := AF.gold_button("Examine the %s" % ch)
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = examined.has(ch)
		b.pressed.connect(func() -> void:
			var r: Dictionary = _sc().examine_channel(ch, bool(st["lens"]))
			if not bool(r["ok"]):
				_say(String(r["reason"]))
			_render_task())
		row.add_child(b)
	var lens := CheckButton.new()
	lens.text = "Use the lens on the next look (%d left)" % int(v["lens"])
	lens.button_pressed = bool(st["lens"])
	lens.disabled = int(v["lens"]) <= 0
	lens.add_theme_font_size_override("font_size", 17)
	lens.toggled.connect(func(on: bool) -> void: st["lens"] = on)
	_content.add_child(lens)
	for ch2: String in Data.CHANNELS:
		if examined.has(ch2):
			var fc := _card(ch2.capitalize(), String(examined[ch2]["text"]))
			var sus := CheckBox.new()
			sus.text = "Suspicious"
			sus.button_pressed = (st["named"] as Array).has(ch2)
			sus.add_theme_font_size_override("font_size", 17)
			sus.toggled.connect(func(on: bool) -> void:
				if on and not (st["named"] as Array).has(ch2):
					(st["named"] as Array).append(ch2)
				elif not on:
					(st["named"] as Array).erase(ch2))
			fc.add_child(sus)
	_add(AF.separator())
	_btn("Genuine: pass it", func() -> void: _after_forgery(_sc().submit_forgery("genuine", [], false)))
	_btn("Forged: set it aside", func() -> void: _after_forgery(_sc().submit_forgery("forged", st["named"], false)))
	if int(v.get("bribe", 0)) > 0:
		var tempt := _btn("A purse of %dg lies under the page. Pass it for coin." % int(v["bribe"]), func() -> void: _after_forgery(_sc().submit_forgery("genuine", [], true)))
		tempt.add_theme_color_override("font_color", BAD_COL)


func _after_forgery(res: Dictionary) -> void:
	var flaws: Array = res.get("flaws", [])
	if not flaws.is_empty():
		res["texts"] = (res.get("texts", []) as Array) + ["The flaws were in: %s." % ", ".join(flaws)]
	_show_result(res, float(_sc().TASK_HOURS["forgery"]))


# ------------------------------------------------------------------ translate

func _render_translate(v: Dictionary) -> void:
	var t: Dictionary = v["text"]
	var known: Array = v["known"]
	var st: Dictionary = _scratch.get("tr", {"g": []})
	_scratch["tr"] = st
	var choices: Array = t["choices"]
	if (st["g"] as Array).size() != choices.size():
		st["g"] = []
		for i in choices.size():
			(st["g"] as Array).append(-1)
	_add(AF.heading(String(t["title"]), 20))
	_text("Old script. Glyphs you have learned read themselves; for the others choose the meaning that fits.", 16, AF.TEXT_DIM, true)
	for i in choices.size():
		var c: Dictionary = choices[i]
		var g := String(c["glyph"])
		var cardv := _card("", "")
		var head := AF.label("[ %s ]" % g.to_upper(), 24, AF.GOLD_BRIGHT)
		cardv.add_child(head)
		if known.has(g):
			cardv.add_child(AF.label("known: %s" % String(Data.GLYPHS[g]), 17, OK_COL))
		else:
			var grp := HBoxContainer.new()
			grp.add_theme_constant_override("separation", 6)
			var bg := ButtonGroup.new()
			for k in (c["options"] as Array).size():
				var ob := Button.new()
				ob.text = String(c["options"][k])
				ob.toggle_mode = true
				ob.button_group = bg
				ob.button_pressed = int(st["g"][i]) == k
				ob.custom_minimum_size = Vector2(0, 50)
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ob.add_theme_font_size_override("font_size", 18)
				ob.pressed.connect(func() -> void: st["g"][i] = k)
				grp.add_child(ob)
			cardv.add_child(grp)
	_add(AF.separator())
	_btn("Read it", func() -> void:
		var guesses: Array = (st["g"] as Array).map(func(x: int) -> int: return maxi(x, 0))
		var res: Dictionary = _sc().submit_translation(guesses)
		if not (res.get("learned", []) as Array).is_empty():
			res["texts"] = (res.get("texts", []) as Array) + ["You have learned: %s." % ", ".join(res["learned"])]
		_show_result(res, float(_sc().TASK_HOURS["translate"])))


# ------------------------------------------------------------------ tax

func _render_tax(v: Dictionary) -> void:
	var led: Dictionary = v["ledger"]
	var st: Dictionary = _scratch.get("tax", {"marked": []})
	_scratch["tax"] = st
	_add(AF.heading("Tax ledger", 20))
	_text("The rate here is %d%% of declared income. Each line: declared, due, the receipt, and what the roll records. Flag every line that is wrong." % int(round(float(led["rate"]) * 100.0)), 16, AF.TEXT_DIM, true)
	var rows: Array = led["rows"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var txt := "%s\ndeclared %dg  |  due %dg  |  receipt %dg  |  roll %dg   (usual for a %s: about %dg)" % [String(r["house"]).capitalize(), int(r["income"]), int(r["due"]), int(r["receipt"]), int(r["ledger"]), String(r["trade"]), int(r["usual"])]
		_option(_content, txt, func(on: bool) -> void:
			if on and not (st["marked"] as Array).has(i):
				(st["marked"] as Array).append(i)
			elif not on:
				(st["marked"] as Array).erase(i), true).button_pressed = (st["marked"] as Array).has(i)
	_add(AF.separator())
	_btn("Report the errors", func() -> void:
		var res: Dictionary = _sc().submit_tax(st["marked"])
		var lines: Array = []
		for row: Dictionary in res["rows"]:
			if String(row["err"]) != "":
				lines.append("%s: %s" % [String(row["house"]).capitalize(), {"skim": "the collector kept part of the coin", "slip": "a slip of the pen in the roll", "under": "income declared far below what the trade earns"}[String(row["err"])]])
		res["texts"] = (res.get("texts", []) as Array) + lines
		_show_result(res, float(_sc().TASK_HOURS["tax"])))


# ------------------------------------------------------------------ exam

func _render_exam(v: Dictionary) -> void:
	var qs: Array = v["questions"]
	var st: Dictionary = _scratch.get("exam", {"i": 0, "a": []})
	_scratch["exam"] = st
	var i := int(st["i"])
	_add(AF.heading("Examination", 20))
	if i >= qs.size():
		var res: Dictionary = _sc().submit_exam(st["a"])
		_show_result(res, float(_sc().TASK_HOURS["exam"]))
		return
	_text("Question %d of %d" % [i + 1, qs.size()], 16, AF.TEXT_DIM)
	_card("", String(qs[i]["q"]))
	var opts: Array = qs[i]["o"]
	for k in opts.size():
		_option(_content, String(opts[k]), func() -> void:
			(st["a"] as Array).append(k)
			st["i"] = i + 1
			_render_task())


# ------------------------------------------------------------------ audience, restricted, estate, embassy

func _render_audience() -> void:
	_clear()
	var sc := _sc()
	var day := _day()
	var st: Dictionary = sc.promotion_status(day)
	_add(AF.heading("Petition your patron", 20))
	var p: Dictionary = sc.get("patron")
	_text("%s considers your request." % String(p.get("name", "Your patron")), 18, AF.TEXT, true)
	var nxt: Dictionary = st.get("next", {})
	if nxt.is_empty():
		_card("At the top", "There is no higher office to ask for.")
	else:
		_card("Next: %s" % String(nxt["title"]), "")
		_show_req_lines(CareerLadders.next_lines(sc.ladder_ctx(day)))
	_btn("Petition for promotion", func() -> void:
		var r: Dictionary = sc.petition(day)
		_refresh()
		_say(String(r["text"])), bool(st["eligible"]))
	_btn("Back", _refresh)


func _render_restricted() -> void:
	_clear()
	var sc := _sc()
	_add(AF.heading("The sealed archive", 20))
	_text("Registrars hold the keys. What lies in the sealed volumes is not meant for you, and you may not forget it once read.", 17, AF.TEXT_DIM, true)
	_btn("Open a sealed volume", func() -> void:
		var r: Dictionary = sc.read_restricted(_day(), false)
		if not bool(r["ok"]):
			_say(String(r["reason"]))
			return
		_pending_hours += float(sc.TASK_HOURS["restricted"])
		_render_secret(r["secret"]))
	_btn("Back", _refresh)


func _render_secret(s: Dictionary) -> void:
	_clear()
	var sc := _sc()
	_add(AF.heading("A noble secret", 20))
	_card(String(s["house"]), String(s["text"]), AF.RED)
	_text("What do you do with it?", 17, AF.TEXT_DIM)
	var acts := [["blackmail", "Blackmail them. Gold now, a crime, and a house that wants you ruined."],
		["report", "Report it to the magistrate. A fair reward and an honest name."],
		["sell", "Sell it to a stranger in a hood. Quick gold, a stain on your reputation."],
		["keep", "Keep it in your private book for later."]]
	for a: Array in acts:
		_btn(String(a[1]), func() -> void:
			var r: Dictionary = sc.use_secret(String(s["id"]), String(a[0]), _day())
			_refresh()
			_say(String(r.get("text", r.get("reason", ""))) + ("  You are arrested." if bool(r.get("jailed", false)) else "")))
	_advance_clock()


func _render_estate() -> void:
	_clear()
	var sc := _sc()
	var e: Dictionary = sc.get("estate")
	_add(AF.heading("The estate of %s" % String(e.get("name", "")), 20))
	var last: Dictionary = e.get("last", {})
	var loyalty := "-"
	var land: RefCounted = _mod("land")
	if land != null:
		loyalty = "%d" % int(land.loyalty(e["region"]))
	_card("Held for %s" % String(e["house"]), "Tenants: %d.  Stores: %d.  Treasury: %dg.  Tenant loyalty: %s.\nLast week: income %dg, costs %dg, net %dg." % [int(e["tenants"]), int(e["stores"]), int(e["treasury"]), loyalty, int(last.get("income", 0)), int(last.get("cost", 0)), int(last.get("net", 0))])
	_text("Rent", 17, AF.TEXT_DIM)
	var rent_row := HBoxContainer.new()
	_content.add_child(rent_row)
	for k in 3:
		var lb: String = ["Low", "Fair", "High"][k]
		var b := _option(rent_row, lb, func() -> void:
			sc.set_estate_policy(k, int(sc.estate["repairs"]))
			_render_estate(), false)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		if int(e["rent"]) == k:
			b.add_theme_stylebox_override("normal", AF.slot(true))
	_text("Repairs", 17, AF.TEXT_DIM)
	var rep_row := HBoxContainer.new()
	_content.add_child(rep_row)
	for k2 in 3:
		var lb2: String = ["None", "Some", "Full"][k2]
		var b2 := _option(rep_row, lb2, func() -> void:
			sc.set_estate_policy(int(sc.estate["rent"]), k2)
			_render_estate(), false)
		b2.alignment = HORIZONTAL_ALIGNMENT_CENTER
		if int(e["repairs"]) == k2:
			b2.add_theme_stylebox_override("normal", AF.slot(true))
	var sk := _btn("Take 25g from the treasury for yourself (the auditors will count it)", func() -> void:
		var r: Dictionary = sc.estate_skim(25)
		_render_estate()
		_say("You pocket %dg." % int(r["gold"]) if bool(r["ok"]) else "The treasury is too thin."), int(e["treasury"]) >= 25)
	sk.add_theme_color_override("font_color", BAD_COL)
	_btn("Back", _refresh)


func _render_embassy() -> void:
	_clear()
	var sc := _sc()
	var day := _day()
	_add(AF.heading("An embassy", 20))
	var ms: Array = sc.missions(day)
	if ms.is_empty():
		_text("No court is expecting an envoy this week.")
		_btn("Back", _refresh)
		return
	var st: Dictionary = _scratch.get("emb", {"m": -1, "tones": []})
	_scratch["emb"] = st
	if int(st["m"]) < 0:
		_text("Choose where to carry the king's word.", 17, AF.TEXT_DIM)
		for i in ms.size():
			var m: Dictionary = ms[i]
			var cv := _card("%s: %s" % [String(m["target_name"]), String(m["purpose"])], "Stance: %s. %s  Pay about %dg." % [String(m["stance"]), String(m["hint"]), int(m["pay"])])
			var sel := _option(cv, "Go", func() -> void:
				st["m"] = i
				_render_embassy())
			sel.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_btn("Back", _refresh)
		return
	var m2: Dictionary = ms[int(st["m"])]
	var tones: Array = st["tones"]
	if tones.size() >= 3:
		var r: Dictionary = sc.run_mission(m2, tones, day)
		_pending_hours += float(sc.TASK_HOURS["embassy"])
		_scratch = {}
		_show_result({"ok": true, "quality": float(r.get("score", 0.0)), "pay": int(r.get("pay", 0)), "text": String(r.get("text", r.get("reason", ""))), "texts": []}, 0.0)
		return
	_card("%s: %s" % [String(m2["target_name"]), String(m2["purpose"])], String(m2["hint"]))
	_text("Round %d of 3. How do you speak?" % (tones.size() + 1), 18)
	for tone: Array in [["flatter", "Flatter their pride and soothe old wounds"], ["bargain", "Bargain fairly, favour for favour"], ["press", "Press firmly; remind them of our strength"]]:
		_option(_content, String(tone[1]), func() -> void:
			tones.append(String(tone[0]))
			_render_embassy())


# ------------------------------------------------------------------ result

func _show_result(res: Dictionary, hours: float) -> void:
	_clear()
	_pending_hours += hours
	var q := float(res.get("quality", 0.0))
	_add(AF.heading("Done", 20))
	_text(String(res.get("text", "")), 20, AF.GOLD_BRIGHT)
	if res.has("quality") and not res.has("passed"):
		_text("Quality", 16, AF.TEXT_DIM)
		_bar(q)
	for t: Variant in res.get("texts", []):
		_text(String(t), 17, AF.TEXT)
	if int(res.get("pay", 0)) != 0:
		_text("Pay: %dg" % int(res["pay"]), 18, OK_COL if int(res["pay"]) > 0 else BAD_COL)
	if bool(res.get("fired", false)):
		_card("Dismissed", "You are shown the door. The scriptorium will not hear you for a while.", AF.RED)
	_sub.text = _subtitle()
	if embedded:
		_btn("Continue", func() -> void:
			task_done.emit(q, res)
			close_screen())
	else:
		_btn("Continue", func() -> void:
			_advance_clock()
			_refresh())


func _advance_clock() -> void:
	if _pending_hours > 0.0 and not embedded:
		WorldSim.advance_hours(_pending_hours)
	_pending_hours = 0.0


# ------------------------------------------------------------------ ladder tab

func _show_ladder() -> void:
	var day := _day()
	var ladder := CareerLadders.ladder(career)
	var ctx: Dictionary = {}
	var cur := ""
	if _is_scribe():
		var sc := _sc()
		if sc != null:
			ctx = sc.ladder_ctx(day)
			cur = String(sc.rank_id()) if bool(sc.get("active")) or int(sc.get("rank")) > 0 else ""
	else:
		var tr := _tr()
		if tr != null:
			ctx = tr.ladder_ctx(career, day)
			cur = String(tr.rank_of(career))
	_add(AF.heading("The ladder", 20))
	var cur_i := CareerLadders.rank_index(career, cur) if cur != "" else -1
	for i in ladder.size():
		var r: Dictionary = ladder[i]
		var mark := "[x]" if i < cur_i else ("[>]" if i == cur_i else "[ ]")
		var col := OK_COL if i < cur_i else (AF.GOLD_BRIGHT if i == cur_i else AF.TEXT_DIM)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var m := AF.label(mark, 18, col)
		m.custom_minimum_size = Vector2(34, 0)
		row.add_child(m)
		var tl := AF.label(String(r["title"]), 21 if i == cur_i else 19, col)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tl)
		_content.add_child(row)
		if i == cur_i and i + 1 < ladder.size():
			var nxt_title := String((ladder[i + 1] as Dictionary)["title"])
			var cv := _card("To become %s" % nxt_title, "")
			for l: Dictionary in CareerLadders.next_lines(ctx):
				var lab := AF.label(("[ok] " if bool(l["met"]) else "[  ] ") + String(l["text"]), 16, OK_COL if bool(l["met"]) else BAD_COL)
				cv.add_child(lab)
	if cur_i < 0:
		_text("You have not taken up this trade yet.", 17, AF.TEXT_DIM, true)
	if _is_scribe() and _sc() != null:
		var sc2 := _sc()
		if bool(sc2.get("active")):
			var cv2 := _card("Your patron", "")
			var p: Dictionary = sc2.get("patron")
			cv2.add_child(AF.label("%s of %s. Regard %d of 100; a friend is 60 or more." % [String(p.get("name", "-")), String(p.get("house", "-")), int(sc2.patron_regard())], 16, AF.TEXT))
			_btn("Petition for promotion", func() -> void:
				var r2: Dictionary = sc2.petition(day)
				_refresh()
				_say(String(r2["text"])), true)
	elif not _is_scribe() and _tr() != null and cur_i >= 0:
		var tr2 := _tr()
		_btn("Ask for promotion", func() -> void:
			var r3: Dictionary = tr2.promote(career, day)
			_refresh()
			_say(String(r3["text"])), true)


func _show_req_lines(lines: Array) -> void:
	for l: Dictionary in lines:
		_text(("[ok] " if bool(l["met"]) else "[  ] ") + String(l["text"]), 16, OK_COL if bool(l["met"]) else BAD_COL)


# ------------------------------------------------------------------ trades (farmer, soldier, merchant, blacksmith)

func _show_trade_menu() -> void:
	var tr := _tr()
	if tr == null:
		_text("Nobody here teaches this trade.")
		return
	var day := _day()
	if not tr.is_member(career):
		_card("Take up the trade", "Start at the bottom of the %s's ladder and earn each rank by doing the work." % String(CAREER_NAMES[career]).to_lower())
		_btn("Take up %s work" % career, func() -> void:
			tr.join(career, day)
			_refresh(), true)
		return
	for o: Dictionary in tr.offers(career, day):
		var label := "%s  (%d h)" % [String(o["label"]), int(o["hours"])]
		_btn(label if bool(o["available"]) else "%s  -  %s" % [label, String(o["why"])], _start_trade.bind(String(o["kind"])), bool(o["available"]))
		if bool(o["available"]):
			_content.add_child(AF.label(String(o["text"]), 15, AF.TEXT_DIM, true))
	if career == "farmer":
		if tr.is_tenant():
			var tn: Dictionary = tr.get("tenancy")
			_card("Your lease", "You work leased land: the landlord keeps a quarter of each harvest and rent falls due each season. Weeks held: %d. Miss the rent and the plot is taken back." % int(tn.get("weeks", 0)))
		var es: Dictionary = tr.get("estate")
		if int(es.get("tenants", 0)) > 0:
			_card("Your estate", "%d tenant families pay %dg each a week." % [int(es["tenants"]), int(tr.TENANT_RENT)])
	if career == "soldier":
		var sq: Dictionary = tr.get("squad")
		_card("Your squad", "Men under you: %d. Lost so far: %d." % [int(sq["men"]), int(sq["lost"])])


func _start_trade(kind: String) -> void:
	var tr := _tr()
	_scratch = {}
	if kind == "muster":
		var m: Dictionary = tr.muster(_day())
		_refresh()
		_say(String(m.get("text", m.get("reason", ""))))
		return
	var b: Dictionary = tr.begin(career, kind, _day())
	if not bool(b["ok"]):
		_say(String(b["reason"]))
		return
	_render_trade_step(b["view"])


func _render_trade_step(v: Dictionary) -> void:
	_clear()
	var tr := _tr()
	_add(AF.heading(String(v["title"]), 20))
	_text("Step %d of %d" % [int(v["step"]) + 1, int(v["of"])], 16, AF.TEXT_DIM)
	_card("", String(v["text"]))
	if String(v["widget"]) == "timing":
		var wd := Widget.new()
		wd.setup({"widget": "timing", "diff": float(v.get("diff", 0.5)), "zone": float(v["zone"]), "zone_at": float(v["zone_at"]), "options": [], "bar_w": _bar_width()})
		wd.finished.connect(func(q: float, _c: int) -> void: _trade_submit(tr.submit(q)))
		_add(wd)
	else:
		var opts: Array = v["options"]
		for k in opts.size():
			_option(_content, String(opts[k]["text"]), func() -> void: _trade_submit(tr.submit(float(k))))


func _trade_submit(r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		_say(String(r.get("reason", "")))
		return
	if not bool(r["done"]):
		_render_trade_step(r["next"])
		return
	r["pay"] = int(r.get("gold", 0))
	_show_result(r, float(_tr().TASK_HOURS.get(String(r["kind"]), 1.0)))
