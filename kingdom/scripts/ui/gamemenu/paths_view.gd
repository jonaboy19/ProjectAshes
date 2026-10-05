extends VBoxContainer
## POWER PATHS view for the Skills tab: the five path trees (magic, bending, sect martial arts, knight arts, beast
## bond) as one portrait-friendly column. A wrapping row of path chips on top, then the chosen path: header card
## (rank, cultivation stage, resource, second-path penalty, chantless gate for magic), and per sub-path a stack of
## full-width technique cards with state (Known, Ready, Locked, Beyond Region 1) and every requirement ticked or
## crossed. No side-by-side panes, so it reads the same on a phone held upright.
##
## Data: PowerTrees.view(path, profile) (scripts/abilities/power_trees.gd); this node only draws. Learning a ready
## technique emits learn_requested(id); the Skills tab calls power_paths.learn_technique and refreshes.
##   var v := PathsView.new(); v.set_profile(profile); v.show_path("sect")

signal learn_requested(id: String)
signal path_changed(path: String)

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")

const STATE_LABEL := {"known": "Known", "ready": "Ready to learn", "locked": "Locked", "beyond": "Beyond Region 1"}
const STATE_COLOR := {"known": Color("7fd18b"), "ready": Color("f3cf7a"), "locked": Color(0.93, 0.89, 0.8, 0.55), "beyond": Color("9aa4c8")}
const OK_COLOR := Color("7fd18b")
const NO_COLOR := Color("e0685a")

var profile: Dictionary = {}
var path := ""
var _chips: HFlowContainer
var _scroll: ScrollContainer
var _body: VBoxContainer


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	add_child(_chips)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)


func set_profile(p: Dictionary) -> void:
	profile = p
	if path == "":
		var learned: Array = p.get("paths", [])
		path = String(p.get("primary", ""))
		if path == "":
			path = String(learned[0]) if not learned.is_empty() else String(PowerTrees.path_ids()[0])
	rebuild()


func show_path(id: String) -> void:
	if not PowerTrees.path_ids().has(id):
		return
	path = id
	path_changed.emit(id)
	rebuild()


func rebuild() -> void:
	Kit.clear(_chips)
	for id: String in PowerTrees.path_ids():
		var known := (profile.get("paths", []) as Array).has(id)
		var label := PowerTrees.path_name(id) + ("" if known else "  (not learned)")
		_chips.add_child(Kit.tab_button(label, id == path, show_path.bind(id), 0.0))
	Kit.clear(_body)
	var v := PowerTrees.view(path, profile)
	if v.is_empty():
		_body.add_child(Kit.lbl("No such path.", 17, AF.TEXT_DIM, true, "italic"))
		return
	_body.add_child(_header(v))
	if not (v["gate"] as Dictionary).is_empty():
		_body.add_child(_gate_card(v))
	if not (v["milestones"] as Array).is_empty():
		_body.add_child(_milestones(v))
	for s: Dictionary in v["subpaths"]:
		_body.add_child(_subpath(s, v))


func _card(bg := Color(0.03, 0.028, 0.025, 0.6), border := AF.GOLD_DIM, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", Kit.box(bg, border, 3, margin))
	return p


func _header(v: Dictionary) -> Control:
	var card := _card()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	col.add_child(Kit.lbl(String(v["name"]), 26, AF.TEXT, true, "title_bold"))
	var tradition := String(v["tradition"])
	var sub := "%s  |  %s" % [String(v["rank"]), String(v["realm_label"])] if bool(v["known"]) else "Path not learned yet"
	col.add_child(Kit.lbl(sub, 17, AF.GOLD_BRIGHT if bool(v["known"]) else AF.TEXT_DIM, true, "title"))
	col.add_child(Kit.lbl(String(v["blurb"]), 15, AF.TEXT_DIM, true, "italic"))
	if bool(v["known"]):
		var line := "Path level %d   |   Resource: %s   |   Sub-path slots: %d" % [int(v["level"]), String(v["resource"]), int(v["slots"])]
		col.add_child(Kit.lbl(line, 15, AF.TEXT, true))
		var pen: Dictionary = v["penalty"]
		if not bool(v["primary"]) and not pen.is_empty():
			col.add_child(Kit.lbl("Additional path: techniques %d%% power, %d%% cost, slower cultivation." % [
				int(round(float(pen["power"]) * 100.0)), int(round(float(pen["cost"]) * 100.0))], 15, NO_COLOR, true))
	if tradition != "":
		col.add_child(Kit.lbl("Tradition: " + tradition, 14, AF.TEXT_DIM, true))
	return card


func _gate_card(v: Dictionary) -> Control:
	var g: Dictionary = v["gate"]
	var card := _card(Color(0.05, 0.04, 0.03, 0.7), AF.GOLD if bool(g["ok"]) else AF.GOLD_DIM)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	col.add_child(Kit.lbl("Chantless casting: " + ("OPEN" if bool(g["ok"]) else "closed to beginners"), 18, OK_COLOR if bool(g["ok"]) else AF.GOLD, true, "title"))
	if bool(g["ok"]):
		col.add_child(Kit.lbl("You may cast chant-gated spells without chanting.", 15, AF.TEXT_DIM, true))
	else:
		for r: String in g["reasons"]:
			col.add_child(Kit.lbl("x  " + r, 15, NO_COLOR, true))
	return card


func _milestones(v: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(Kit.section("Path milestones", 17))
	for m: Dictionary in v["milestones"]:
		var done := bool(m["done"])
		col.add_child(Kit.lbl("%s  %s" % ["+" if done else "-", String(m["name"])], 15, OK_COLOR if done else AF.TEXT_DIM, true))
	return col


func _subpath(s: Dictionary, v: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var head := Kit.section(String(s["name"]) + ("" if bool(s["chosen"]) else "   (not followed)"), 19)
	col.add_child(head)
	if String(s["desc"]) != "":
		col.add_child(Kit.lbl(String(s["desc"]), 14, AF.TEXT_DIM, true, "italic"))
	for t: Dictionary in s["techniques"]:
		col.add_child(_technique(t, bool(v["known"])))
	return col


func _technique(t: Dictionary, path_known: bool) -> Control:
	var state := String(t["state"])
	var card := _card(Color(0.03, 0.028, 0.025, 0.55 if state != "locked" else 0.35), STATE_COLOR[state] if state != "locked" else AF.GOLD_DIM, 10)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	col.add_child(Kit.lbl(String(t["name"]), 19, AF.TEXT if state != "locked" else AF.TEXT_DIM, true, "title"))
	col.add_child(Kit.lbl("%s   |   tier %d%s" % [String(STATE_LABEL[state]), int(t["tier"]), "   |   passive" if String(t["kind"]) == "passive" else ""], 14, STATE_COLOR[state], true))
	col.add_child(Kit.lbl(String(t["desc"]), 15, AF.TEXT_DIM, true))
	if String(t["kind"]) != "passive":
		var cast_words := {"chant": "chanted", "instant": "instant", "channel": "channelled", "charge": "charged"}
		var cast_word: String = cast_words.get(String(t["cast"]), String(t["cast"]))
		col.add_child(Kit.lbl("Cost %d %s   |   cooldown %.0fs   |   %s" % [int(round(float(t["cost"]))), String(t["resource"]), float(t["cooldown"]), cast_word], 14, AF.TEXT, true))
	if state != "known":
		for r: Dictionary in t["reqs"]:
			var met := bool(r["met"])
			col.add_child(Kit.lbl("%s  %s" % ["+" if met else "x", String(r["label"])], 14, OK_COLOR if met else NO_COLOR, true))
	if state == "ready" and path_known:
		var b := Kit.button("Learn", true, 44.0, 16)
		b.pressed.connect(func() -> void: learn_requested.emit(String(t["id"])))
		col.add_child(b)
	return card
