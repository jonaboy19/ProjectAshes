extends "res://scripts/ui/gamemenu/gm_tab.gd"
## CULTIVATION: realm and stage, qi bar, the path's own diagram (mana circles / elemental resonance /
## meridians / aura layers / soul bond), Meditate (time acceleration), Break through with its risk %,
## optional tribulation trial, resources and insight, manuals and techniques.
## Reads scripts/realm/cultivation.gd only (hub.mod("cultivation")); actions are the module's own methods.
## Tests / screenshot tools may inject `cult_override`; otherwise Life.realm is used.

const Cult := preload("res://scripts/realm/cultivation.gd")
const HOURS := [1, 4, 8]
const PATH_COL := {"magic": Color("7f8cf0"), "bending": Color("5fc3d8"), "sect": Color("e0b45a"), "knight": Color("c9d2e4"), "beast": Color("8fd07a")}

var cult_override: RefCounted = null
var sel_path := ""
var sel_loc := "wilds"
var sel_hours := 4
var face_trial := false
var use_pill := false
var status_line := ""

var _root: HBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _diagram: Diagram
var _dots: RealmDots
var _chips: HBoxContainer
var _title: Label
var _sub: Label
var _bar: Kit.Bar
var _body: VBoxContainer
var _status: Label


# ------------------------------------------------------------------ the diagram ----

## One control, five drawings. `stage` 1..9 of the current realm, `realm` 1..10, `qi` 0..1.3.
class Diagram extends Control:
	var mode := "circles"
	var stage := 1
	var realm := 1
	var qi := 0.0
	var col := Color("e0b45a")

	func _init() -> void:
		custom_minimum_size = Vector2(380, 270)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(m: String, r: int, s: int, q: float, c: Color) -> void:
		mode = m
		realm = r
		stage = s
		qi = q
		col = c
		queue_redraw()

	func _node(p: Vector2, lit: bool, current: bool, radius := 7.0) -> void:
		draw_circle(p, radius + 2.5, Color(0, 0, 0, 0.7))
		if lit:
			draw_circle(p, radius, col)
			draw_circle(p, radius * 0.45, Color(1, 1, 1, 0.55))
		else:
			draw_circle(p, radius, Color(0.16, 0.14, 0.12))
			draw_arc(p, radius, 0, TAU, 20, Color(col, 0.45), 1.5, true)
		if current:
			draw_arc(p, radius + 5.0, 0, TAU, 24, Color(col.lightened(0.4), 0.55 + 0.45 * clampf(qi, 0.0, 1.0)), 2.5, true)

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.46
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.018, 0.016, 0.55))
		draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.35), false, 1.0)
		match mode:
			"circles":
				_circles(c, R)
			"resonance":
				_resonance(c, R)
			"meridians":
				_meridians(c, R)
			"aura":
				_aura(c, R)
			_:
				_bond(c, R)

	func _ring_points(c: Vector2, rad: float, n := 9, start := -PI * 0.5) -> Array:
		var out: Array = []
		for i in n:
			var a := start + TAU * float(i) / float(n)
			out.append(c + Vector2(cos(a), sin(a)) * rad)
		return out

	func _circles(c: Vector2, R: float) -> void:
		# one ring per realm reached; the core grows with qi
		for i in 10:
			var rr := R * (0.28 + 0.072 * float(i + 1))
			var done := i + 1 < realm
			var cur := i + 1 == realm
			draw_arc(c, rr, 0, TAU, 72, Color(col, 0.95 if cur else (0.55 if done else 0.14)), 3.0 if cur else 1.5, true)
		draw_circle(c, R * 0.2 * (0.6 + 0.4 * clampf(qi, 0.0, 1.2)), Color(col, 0.30))
		draw_circle(c, R * 0.13 * (0.7 + 0.3 * clampf(qi, 0.0, 1.2)), col)
		draw_circle(c, R * 0.05, Color(1, 1, 1, 0.8))
		var pts := _ring_points(c, R * (0.28 + 0.072 * float(realm)))
		for i in 9:
			_node(pts[i], i < stage - 1 or (i == stage - 1 and qi >= 1.0), i == stage - 1)

	func _resonance(c: Vector2, R: float) -> void:
		var els := [["Water", Color("5fc3d8")], ["Earth", Color("b89a64")], ["Fire", Color("e0683c")], ["Air", Color("d8e6f0")]]
		var f := AF.font(AF.BODY_FONT)
		for k in 4:
			var a := -PI * 0.5 + TAU * float(k) / 4.0
			var p := c + Vector2(cos(a), sin(a)) * R * 0.78
			draw_line(c, p, Color(els[k][1], 0.35), 2.0)
			draw_circle(p, 13.0, Color(0, 0, 0, 0.7))
			draw_circle(p, 10.0, Color(els[k][1], 0.35 + 0.5 * clampf(float(realm) / 5.0, 0.0, 1.0)))
			draw_string(f, p + Vector2(-16, 30), String(els[k][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(els[k][1], 0.9))
		# breath wave
		var prev := Vector2.ZERO
		for i in 61:
			var x := c.x - R * 0.55 + (R * 1.1) * float(i) / 60.0
			var y := c.y + sin(float(i) * 0.36) * (10.0 + 14.0 * clampf(qi, 0.0, 1.0))
			if i > 0:
				draw_line(prev, Vector2(x, y), Color(col, 0.9), 2.5, true)
			prev = Vector2(x, y)
		var pts := _ring_points(c, R * 0.52)
		for i in 9:
			_node(pts[i], i < stage - 1 or (i == stage - 1 and qi >= 1.0), i == stage - 1, 6.0)

	func _meridians(c: Vector2, R: float) -> void:
		# a standing figure: head, torso, arms, legs; nine nodes along the main meridians
		var dim := Color(col, 0.3)
		var top := c + Vector2(0, -R * 0.95)
		draw_arc(top + Vector2(0, R * 0.12), R * 0.12, 0, TAU, 24, dim, 2.0, true)
		var nk := top + Vector2(0, R * 0.26)
		var pelvis := c + Vector2(0, R * 0.3)
		draw_line(nk, pelvis, dim, 3.0)
		draw_line(nk + Vector2(0, 14), nk + Vector2(-R * 0.45, R * 0.42), dim, 3.0)
		draw_line(nk + Vector2(0, 14), nk + Vector2(R * 0.45, R * 0.42), dim, 3.0)
		draw_line(pelvis, pelvis + Vector2(-R * 0.22, R * 0.6), dim, 3.0)
		draw_line(pelvis, pelvis + Vector2(R * 0.22, R * 0.6), dim, 3.0)
		var nodes: Array = [
			c + Vector2(0, -R * 0.68), c + Vector2(0, -R * 0.4), c + Vector2(0, -R * 0.1), c + Vector2(0, R * 0.12),
			nk + Vector2(-R * 0.22, R * 0.22), nk + Vector2(R * 0.22, R * 0.22),
			nk + Vector2(-R * 0.45, R * 0.42), nk + Vector2(R * 0.45, R * 0.42),
			pelvis + Vector2(0, R * 0.42)]
		# meridian lines between consecutive nodes (lit up to the current stage)
		for i in range(1, 9):
			var lit := i < stage
			draw_line(nodes[i - 1], nodes[i], Color(col, 0.85 if lit else 0.18), 2.5 if lit else 1.5, true)
		# dantian glows with qi
		var dan: Vector2 = c + Vector2(0, R * 0.12)
		draw_circle(dan, 14.0 + 10.0 * clampf(qi, 0.0, 1.2), Color(col, 0.22))
		for i in 9:
			_node(nodes[i], i < stage - 1 or (i == stage - 1 and qi >= 1.0), i == stage - 1)
		var f := AF.font(AF.BODY_FONT)
		draw_string(f, Vector2(10, size.y - 10), "Realm %d  Dantian %d%%" % [realm, int(clampf(qi, 0.0, 1.3) * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, 0.9))

	func _aura(c: Vector2, R: float) -> void:
		# layered armoured silhouette: nine aura layers as nested rounded shields
		for i in 9:
			var k := 8 - i
			var w := R * (0.34 + 0.07 * float(k))
			var h := R * (0.52 + 0.07 * float(k))
			var lit := k < stage - 1 or (k == stage - 1 and qi >= 1.0)
			var cur := k == stage - 1
			var pts := PackedVector2Array()
			for s in 25:
				var a := PI + PI * float(s) / 24.0
				pts.append(c + Vector2(cos(a) * w, sin(a) * h * 0.78 - h * 0.1))
			for s in 25:
				var a2 := PI * float(s) / 24.0
				pts.append(c + Vector2(cos(a2) * w, sin(a2) * h * 0.62 - h * 0.1))
			pts.append(pts[0])
			draw_polyline(pts, Color(col, 0.95 if cur else (0.6 if lit else 0.14)), 3.0 if cur else 1.6, true)
		draw_circle(c + Vector2(0, -R * 0.1), R * 0.1 * (0.6 + 0.6 * clampf(qi, 0.0, 1.2)), Color(col, 0.9))
		var f := AF.font(AF.BODY_FONT)
		draw_string(f, Vector2(10, size.y - 10), "Aura layers %d / 9   Realm %d" % [maxi(0, stage - 1), realm], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, 0.9))

	func _bond(c: Vector2, R: float) -> void:
		var pts := _ring_points(c, R * 0.78)
		for i in 9:
			var lit := i < stage - 1 or (i == stage - 1 and qi >= 1.0)
			draw_line(c, pts[i], Color(col, 0.75 if lit else 0.15), 2.5 if lit else 1.2, true)
			# a small creature mark at the end (triangle ears)
			var p: Vector2 = pts[i]
			draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 6), p + Vector2(0, -9), p + Vector2(8, 6)]), Color(col, 0.85 if lit else 0.25))
			if i == stage - 1:
				draw_arc(p, 14.0, 0, TAU, 24, Color(col.lightened(0.4), 0.9), 2.0, true)
		draw_circle(c, R * 0.22 * (0.6 + 0.4 * clampf(qi, 0.0, 1.2)), Color(col, 0.35))
		draw_circle(c, R * 0.12, col)
		draw_arc(c, R * 0.3, 0, TAU, 40, Color(col, 0.5), 2.0, true)
		var f := AF.font(AF.BODY_FONT)
		draw_string(f, Vector2(10, size.y - 10), "Bond strands %d / 9   Realm %d" % [maxi(0, stage - 1), realm], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, 0.9))


## Ten pips, one per realm: reached ones filled, the current one ringed.
class RealmDots extends Control:
	var realm := 1
	var col := Color("e0b45a")

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(r: int, c: Color) -> void:
		realm = r
		col = c
		queue_redraw()

	func _draw() -> void:
		var f := AF.font(AF.BODY_FONT)
		draw_string(f, Vector2(0, 19), "Realm %d / 10" % realm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col, 0.95))
		for i in 10:
			var p := Vector2(size.x - 14.0 - 27.0 * float(9 - i), 13.0)
			if i + 1 <= realm:
				draw_circle(p, 8.0, col)
			else:
				draw_arc(p, 8.0, 0, TAU, 20, Color(col, 0.35), 1.5, true)
			if i + 1 == realm:
				draw_arc(p, 11.0, 0, TAU, 24, Color(col.lightened(0.4), 0.9), 2.0, true)


# ----------------------------------------------------------------- build / refresh ----

func _c() -> Variant:
	if cult_override != null:
		return cult_override
	var realm: Variant = Life.get("realm")
	if realm == null:
		return null
	return realm.mod("cultivation")


func build() -> void:
	_root = page_hbox(14)
	_left = VBoxContainer.new()
	_left.custom_minimum_size.x = 400
	_left.add_theme_constant_override("separation", 8)
	_root.add_child(_left)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	_left.add_child(_chips)
	_title = Kit.lbl("", 26, AF.TEXT, false, "title_bold")
	_left.add_child(_title)
	_sub = Kit.lbl("", 16, AF.TEXT_DIM, true, "italic")
	_left.add_child(_sub)
	_dots = RealmDots.new()
	_left.add_child(_dots)
	_diagram = Diagram.new()
	_left.add_child(_diagram)
	_bar = Kit.bar(0.0, 22.0, AF.GOLD, "")
	_left.add_child(_bar)
	_status = Kit.lbl("", 15, AF.GOLD_BRIGHT, true)
	_left.add_child(_status)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12
	_root.add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	sc.add_child(_body)


func on_show() -> void:
	refresh()


func hints() -> Array:
	return [["M", "Meditate", _meditate], ["B", "Break through", _break]]


func handle_key(e: InputEventKey) -> bool:
	if not e.pressed or e.echo:
		return false
	if e.keycode == KEY_M:
		_meditate()
		return true
	if e.keycode == KEY_B:
		_break()
		return true
	return false


func _th(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func refresh() -> void:
	var c: Variant = _c()
	Kit.clear(_chips)
	Kit.clear(_body)
	if c == null:
		_title.text = "Cultivation"
		_sub.text = "No cultivation data."
		return
	var mine: Array = c.cultivating()
	if mine.is_empty():
		_title.text = "Begin cultivating"
		_sub.text = "Every path climbs the same ladder of realms. Choose how you will walk it."
		_diagram.set_state("circles", 1, 1, 0.0, AF.GOLD)
		_bar.set_ratio(0.0)
		_bar.text = ""
		for p: String in Cult.paths():
			var pd: Dictionary = Cult.path_def(p)
			var b := Kit.button("Begin: %s" % pd["name"], false, 52)
			b.pressed.connect(func() -> void:
				c.begin(p, "self")
				sel_path = p
				refresh())
			_body.add_child(b)
			_body.add_child(Kit.lbl(String(pd["blurb"]), 14, AF.TEXT_DIM, true, "italic"))
		return
	if sel_path == "" or not mine.has(sel_path):
		sel_path = String(c.primary) if mine.has(c.primary) else String(mine[0])
	for p: String in mine:
		var pd: Dictionary = Cult.path_def(p)
		_chips.add_child(Kit.tab_button(String(pd["name"]), p == sel_path, _pick_path.bind(p), 110))
	var sm: Dictionary = c.summary(sel_path, _opts(c))
	var pd2: Dictionary = Cult.path_def(sel_path)
	var col: Color = PATH_COL.get(sel_path, AF.GOLD)
	_title.text = String(sm["realm_name"])
	_sub.text = "%s  ·  %s%s" % [String(sm["generic_realm"]), String(pd2["structure"]), "" if sm["primary"] else "  ·  secondary path (x%.2f speed)" % float(sm["speed"])]
	_diagram.set_state(String(pd2["diagram"]), int(sm["realm"]), int(sm["stage"]), float(sm["qi_ratio"]), col)
	_bar.fill = col
	_bar.set_ratio(minf(1.0, float(sm["qi_ratio"])))
	_bar.text = "Stage %d / 9  ·  %s / %s qi" % [int(sm["stage"]), _th(int(sm["qi"])), _th(int(sm["qi_need"]))]
	_dots.set_state(int(sm["realm"]), col)
	_status.text = status_line
	_build_body(c, sm, pd2, col)
	hints_changed()


func _opts(c: Variant) -> Dictionary:
	var o := {"loc": sel_loc, "pill": use_pill}
	if face_trial and c.is_major(sel_path):
		o["score"] = c.trial_score_estimate(sel_path)
	if Engine.get_main_loop() != null and WorldSim != null:
		o["day"] = WorldSim.day
	return o


func _build_body(c: Variant, sm: Dictionary, pd: Dictionary, col: Color) -> void:
	# --- breakthrough
	_body.add_child(Kit.section("Breakthrough", 17))
	var bi: Dictionary = sm["breakthrough"]
	var nxt: Dictionary = c.next_position(sel_path)
	if nxt.is_empty():
		_body.add_child(Kit.lbl("You stand at the top of the ladder.", 16, AF.TEXT_DIM, true, "italic"))
	else:
		var head := "%s  ->  %s" % [Cult.stage_label(sel_path, int(sm["realm"]), int(sm["stage"])), Cult.stage_label(sel_path, int(nxt["realm"]), int(nxt["stage"]))]
		_body.add_child(Kit.lbl(head, 16, AF.TEXT, true))
		var pct := int(round(float(bi["chance"]) * 100.0))
		var risk_col := Kit.GREEN if pct >= 80 else (AF.GOLD_BRIGHT if pct >= 55 else Kit.BAD)
		_body.add_child(Kit.lbl("Success chance %d%%   (failure: strain, qi deviation or backlash, never death)" % pct, 17, risk_col, true, "title"))
		_body.add_child(_req("Qi bar full", float(sm["qi_ratio"]) >= 1.0))
		_body.add_child(_req("Level %d  (you are %d)" % [int(bi["level_needed"]), c.prog.level], c.prog.level >= int(bi["level_needed"])))
		if int(bi["insight_needed"]) > 0:
			_body.add_child(_req("Insight %d  (you have %d)" % [int(bi["insight_needed"]), int(c.insight)], c.insight >= float(bi["insight_needed"])))
		for cat: Dictionary in bi["catalyst"]:
			var have: int = c.stock_at_least(String(cat["kind"]), int(cat["grade"]))
			_body.add_child(_req("%d x %s (grade %d+)  (you have %d)" % [int(cat["n"]), String(Dictionary(Cult.data()["resources"][cat["kind"]])["name"]), int(cat["grade"]), have], have >= int(cat["n"])))
		if c.is_major(sel_path):
			var tr: Dictionary = c.tribulation_spec(sel_path)
			var tb := Kit.tab_button("Face the trial (optional): %s" % ("yes" if face_trial else "no"), face_trial, _toggle_trial, 0)
			_body.add_child(tb)
			_body.add_child(Kit.lbl("%s: %d waves. %s" % [tr["name"], int(tr["waves"]), tr["reward"]], 14, AF.TEXT_DIM, true, "italic"))
		if c.stock_at_least("pill", int(sm["realm"])) > 0:
			_body.add_child(Kit.tab_button("Use a breakthrough pill (+12%%): %s" % ("yes" if use_pill else "no"), use_pill, _toggle_pill, 0))
		var bb := Kit.button("Break through (%d%%)" % pct, true, 56)
		bb.disabled = not bool(bi["ok"])
		bb.pressed.connect(_break)
		_body.add_child(bb)
		if not bool(bi["ok"]):
			_body.add_child(Kit.lbl(_reason_text(String(bi["reason"])), 14, AF.TEXT_DIM, true, "italic"))
	# --- meditate
	_body.add_child(Kit.section("Meditate", 17))
	var locs := HFlowContainer.new()
	locs.add_theme_constant_override("h_separation", 6)
	locs.add_theme_constant_override("v_separation", 6)
	_body.add_child(locs)
	for l: String in Cult.locations():
		var open: bool = c.location_open(l)
		var ld: Dictionary = Cult.location(l)
		var t := "%s x%.1f" % [ld["name"], c.density(l, sel_path)] if open else "%s (closed)" % ld["name"]
		var b := Kit.tab_button(t, l == sel_loc, _pick_loc.bind(l), 0)
		b.disabled = not open
		locs.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	for h: int in HOURS:
		row.add_child(Kit.tab_button("%d h" % h, h == sel_hours, _pick_hours.bind(h), 70))
	var mb := Kit.button("Meditate", true, 52)
	mb.pressed.connect(_meditate)
	mb.disabled = c.is_deviated(_day())
	row.add_child(mb)
	if c.is_deviated(_day()) or c.is_strained(_day()):
		_body.add_child(Kit.lbl("%s: %s" % [c.injury_note if c.injury_note != "" else "Injured", "cannot meditate" if c.is_deviated(_day()) else "meditation and odds are worse"], 15, Kit.BAD))
	# --- resources
	_body.add_child(Kit.section("Resources  ·  insight %d  ·  toxicity %d%%" % [int(c.insight), int(c.toxicity * 100.0)], 17))
	var sl: Array = c.stock_list()
	if sl.is_empty():
		_body.add_child(Kit.lbl("No herbs, cores or pills. Gather, hunt and brew them.", 15, AF.TEXT_DIM, true, "italic"))
	for s: Dictionary in sl:
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 10)
		var rd: Dictionary = Cult.data()["resources"][s["kind"]]
		rr.add_child(Kit.lbl("%s (grade %d)  x%d" % [rd["name"], int(s["grade"]), int(s["n"])], 16, AF.TEXT))
		rr.add_child(Kit.hspacer())
		var ub := Kit.button("Use", false, 44, 15)
		ub.pressed.connect(func() -> void:
			var r: Dictionary = c.use_resource(sel_path, String(s["kind"]), int(s["grade"]), {"day": _day()})
			status_line = "Absorbed: +%d%% of the stage." % int(float(r.get("frac", 0.0)) * 100.0) if bool(r["ok"]) else "Cannot use it (%s)." % String(r["reason"])
			refresh())
		rr.add_child(ub)
		_body.add_child(rr)
	# --- techniques
	_body.add_child(Kit.section("Techniques & manuals", 17))
	for t: Dictionary in c.technique_states(sel_path):
		var tc := AF.TEXT if t["state"] == "ready" else (AF.GOLD if t["state"] == "sealed" else AF.TEXT_DIM)
		var st: String = {"ready": "ready", "sealed": "sealed (realm %d, stage %d)" % [int(t["realm"]), int(t["stage"])], "locked": "manual not found"}[t["state"]]
		_body.add_child(Kit.lbl("%s  ·  %s" % [t["name"], st], 16, tc))
		if t["state"] != "locked":
			_body.add_child(Kit.lbl(String(t["desc"]), 14, AF.TEXT_DIM, true, "italic"))
	var ms: Array = Cult.manuals_of(sel_path).filter(func(m: Dictionary) -> bool: return not c.knows_manual(String(m["id"])))
	for m: Dictionary in ms:
		var known_src := String(m["source"]).replace("_", " ")
		_body.add_child(Kit.lbl("Unfound: %s (from %s, realm %d)" % [m["name"], known_src, int(m["realm"])], 14, Color(AF.TEXT_DIM, 0.7)))
	# --- realm ladder
	_body.add_child(Kit.section("Realm ladder", 17))
	var ladder := HFlowContainer.new()
	ladder.add_theme_constant_override("h_separation", 6)
	ladder.add_theme_constant_override("v_separation", 4)
	_body.add_child(ladder)
	for r in range(1, 11):
		var name := Cult.realm_name(sel_path, r)
		var lab := Kit.lbl("%d %s" % [r, name], 14, col if r == int(sm["realm"]) else (AF.TEXT if r < int(sm["realm"]) else AF.TEXT_DIM))
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", Kit.box(Color(col, 0.18) if r == int(sm["realm"]) else Color(0, 0, 0, 0.35), col if r == int(sm["realm"]) else Color(AF.GOLD_DIM, 0.4), 3, 5))
		pc.add_child(lab)
		ladder.add_child(pc)
	_body.add_child(Kit.lbl("Region 1 reaches realms 1-3; Core Formation needs level %d." % Cult.level_needed(4, 1), 14, AF.TEXT_DIM, true, "italic"))


func _pick_path(p: String) -> void:
	sel_path = p
	refresh()


func _pick_loc(l: String) -> void:
	sel_loc = l
	refresh()


func _pick_hours(h: int) -> void:
	sel_hours = h
	refresh()


func _toggle_trial() -> void:
	face_trial = not face_trial
	refresh()


func _toggle_pill() -> void:
	use_pill = not use_pill
	refresh()


func _req(text: String, ok: bool) -> Control:
	return Kit.lbl("%s  %s" % ["[x]" if ok else "[ ]", text], 15, Kit.GREEN if ok else AF.TEXT_DIM)


func _reason_text(r: String) -> String:
	match r:
		"qi_low":
			return "Meditate until the qi bar is full."
		"level":
			return "Your level is too low for this stage. Level opens the ladder; cultivation fills it."
		"insight":
			return "Not enough insight. Explore, read lore and learn from teachers."
		"catalyst":
			return "Missing the realm's catalyst (herbs, cores or pills)."
		"deviated":
			return "A qi deviation: rest until it passes."
		"primary_behind":
			return "A secondary path cannot out-realm your primary path."
		"pill":
			return "You have no spare breakthrough pill."
	return ""


func _day() -> int:
	return int(WorldSim.day) if WorldSim != null else 0


func _meditate() -> void:
	var c: Variant = _c()
	if c == null or sel_path == "":
		return
	if WorldSim != null and WorldSim.has_method("advance_hours"):
		WorldSim.advance_hours(float(sel_hours))
	var r: Dictionary = c.meditate(sel_path, float(sel_hours), sel_loc, {"day": _day()})
	if bool(r["ok"]):
		status_line = "Meditated %d h: +%d qi%s." % [sel_hours, int(r["qi"]), "  (the stage is full)" if bool(r.get("full", false)) else ""]
		if (r["events"] as Array).has("backlash"):
			status_line += "  Raw qi lashed back!"
	else:
		status_line = "Cannot meditate (%s)." % String(r["reason"])
	refresh()


func _break() -> void:
	var c: Variant = _c()
	if c == null or sel_path == "":
		return
	var r: Dictionary = c.attempt_breakthrough(sel_path, _opts(c))
	status_line = String(r["msg"])
	face_trial = false
	use_pill = false
	refresh()
