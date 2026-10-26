extends Control
## "Found a camp" (READY_V1 C3): the player's way to start a settlement. The `found_camp` action (default F4, rebindable) or the
## "Found a camp" button on the build menu opens a site card for the ground the player stands on (water, food, safety, claim law:
## `founding.evaluate_site` + `land_claim.gd`), then a name card, then the C2 claim (`build_kit.claim`: one founding record, one
## civilization row, one grid). The same steps run without a scene through the static helpers (tests and the headless bot).
##   FoundCamp.open_for(hud)
##   var card := FoundCamp.site_card(kit, pos);  FoundCamp.found(kit, pos, "Ashhold")

signal closed
signal founded(result: Dictionary)

const SELF_PATH := "res://scripts/ui/found_camp.gd"
const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const Tutorial := preload("res://scripts/region1/tutorial_director.gd")
const FOUNDED_FLAG := "r1.a3.camp_founded"      ## the story step a3_found_camp waits for (set here, read by the quest through the life flags)
const MIN_OVERALL := 0.2                        ## founding.begin refuses a site that scores less
const NAME_MAX := 24

var hud: Node
var kit: RefCounted
var card: Dictionary = {}
var _was_paused := false
var _title: Label
var _body: Label
var _name_edit: LineEdit
var _row: HBoxContainer
var _phase := "card"           # card | name


static func open_for(host: Node) -> Control:
	var s: Control = host.get_node_or_null("FoundCamp")
	if s == null:
		s = (load(SELF_PATH) as GDScript).new()
		s.name = "FoundCamp"
		host.add_child(s)
	if host.has_method("close_menu"):
		host.call("close_menu")
	s.hud = host
	s.call("open")
	return s


# ------------------------------------------------------------------ logic (no scene tree)

static func build_kit_of() -> RefCounted:
	var realm: Variant = Life.get("realm")
	return realm.mod("build_kit") if realm != null else null


## What the card shows for ground `pos` (x, z): {can, reason, overall, verdict, lines, blocked, slots_left, default_name, pos, inside}.
## `can` mirrors what founding.begin and build_kit.claim would accept, so the button is only live for a claim that will succeed.
static func site_card(p_kit: RefCounted, pos: Vector2) -> Dictionary:
	var out := {"can": false, "reason": "", "overall": 0.0, "verdict": "", "lines": [], "blocked": "", "slots_left": 0, "default_name": "",
		"pos": pos, "inside": 0}
	if p_kit == null:
		out["reason"] = "There is no one to found a camp with."
		return out
	var hub: Variant = p_kit.get("hub")
	var fd: Variant = hub.mod("founding") if hub != null else null
	out["slots_left"] = maxi(0, BuildKit.MAX_GRIDS - (p_kit.grids as Dictionary).size())
	out["inside"] = int(p_kit.call("grid_at", Vector3(pos.x, 0.0, pos.y)))
	if fd == null:
		out["reason"] = "The realm has no founders' register here."
		return out
	var ev: Dictionary = fd.call("evaluate_site", pos)
	out["overall"] = float(ev["overall"])
	out["verdict"] = String(ev["verdict"])
	out["lines"] = ev["lines"]
	out["blocked"] = String(ev["blocked"])
	out["default_name"] = String(fd.call("suggest_name", pos))
	var cm: Variant = hub.mod("camps")
	var why := ""
	if int(out["inside"]) > 0:
		why = "You already hold a camp here."
	elif int(out["slots_left"]) <= 0:
		why = "You can found at most %d settlements." % BuildKit.MAX_GRIDS
	elif String(out["blocked"]) != "":
		why = String(out["blocked"])
	elif float(out["overall"]) < MIN_OVERALL or (cm != null and float(ev["camp"]) < float(cm.get("MIN_CAMP_SCORE"))):
		why = "The ground is too poor to settle: " + String(out["verdict"])
	out["reason"] = why
	out["can"] = why == ""
	return out


## The name as the claim will use it: trimmed, one line, at most NAME_MAX characters; "" when blank.
static func clean_name(raw: String) -> String:
	var s := raw.strip_edges().replace("\n", " ").replace("\t", " ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.left(NAME_MAX).strip_edges()


## Founds the camp (the C2 claim) and reports it to the story and the tutorial. {ok, gid, fid, reason, name}.
static func found(p_kit: RefCounted, pos: Vector2, raw_name: String) -> Dictionary:
	var c := site_card(p_kit, pos)
	if not bool(c["can"]):
		return {"ok": false, "gid": 0, "fid": 0, "reason": String(c["reason"]), "name": ""}
	var nm := clean_name(raw_name)
	if nm == "":
		nm = String(c["default_name"])
	if not WorldGen.settlements.is_empty():
		p_kit.height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)
	var r: Dictionary = p_kit.call("claim", Vector3(pos.x, float(p_kit.height_fn.call(pos.x, pos.y)), pos.y), "squat", nm)
	if not bool(r.get("ok", false)):
		return {"ok": false, "gid": 0, "fid": 0, "reason": String(r.get("reason", "")), "name": ""}
	var gid := int(r["gid"])
	var link: Dictionary = p_kit.call("link_of", gid)
	if Life.get("life_path") != null:
		Life.life_path.flags[FOUNDED_FLAG] = true      # the quest reads the life flags every second (r1_story_director.ctx)
	Tutorial.tell(&"found_camp")
	return {"ok": true, "gid": gid, "fid": int(link["fid"]), "reason": "", "name": String((p_kit.grids[gid] as Dictionary)["name"])}


# ------------------------------------------------------------------ UI

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	_build()


func open() -> void:
	kit = build_kit_of()
	var p: Node3D = hud.get("player") if hud != null else null
	var pos := Vector2(p.global_position.x, p.global_position.z) if p != null else Vector2.ZERO
	card = site_card(kit, pos)
	if not visible:
		_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Audio.play_ui("open")
	_show_card()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel"):
		if _phase == "name":
			_show_card()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_card() -> void:
	_phase = "card"
	_title.text = "FOUND A CAMP"
	_name_edit.visible = false
	var lines: Array = card["lines"]
	var txt := "%s\n\n" % String(card["verdict"])
	for l: Variant in lines:
		txt += "• %s\n" % String(l)
	txt += "\nCamps you can still found: %d of %d." % [int(card["slots_left"]), BuildKit.MAX_GRIDS]
	if not bool(card["can"]):
		txt += "\n\n%s" % String(card["reason"])
	_body.text = txt
	_clear_row()
	var go := _button("Found a camp here", _to_name)
	go.disabled = not bool(card["can"])
	_row.add_child(go)
	_row.add_child(_button("Not here", close))


func _to_name() -> void:
	_phase = "name"
	_title.text = "NAME YOUR CAMP"
	_body.text = "What will the settlers call it?"
	_name_edit.visible = true
	_name_edit.text = String(card["default_name"])
	_name_edit.max_length = NAME_MAX
	_name_edit.grab_focus()
	_name_edit.select_all()
	_clear_row()
	_row.add_child(_button("Raise the camp", _submit))
	_row.add_child(_button("Back", _show_card))


func _submit() -> void:
	var res := found(kit, card["pos"] as Vector2, _name_edit.text)
	if not bool(res["ok"]):
		_phase = "card"
		card["reason"] = String(res["reason"])
		card["can"] = false
		_show_card()
		return
	close()
	if hud != null and hud.has_method("notify"):
		hud.call("notify", "quest", "Camp founded", "%s. Open the build menu to lay its first foundations." % String(res["name"]))
	founded.emit(res)


func _clear_row() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.016, 0.012, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := AF.panel(Color(0.043, 0.039, 0.035, 0.96), AF.GOLD, 5, 26)
	sb.shadow_size = 24
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	_title.add_theme_font_override("font", AF.title_font(700))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	col.add_child(AF.separator())
	_body = Label.new()
	_body.add_theme_font_override("font", AF.font())
	_body.add_theme_font_size_override("font_size", 18)
	_body.add_theme_color_override("font_color", HudArt.IVORY)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	col.add_child(_name_edit)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	col.add_child(_row)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	var rest := AF.row(false)
	rest.bg_color = Color(1, 1, 1, 0.035)
	rest.border_color = Color(AF.GOLD, 0.28)
	rest.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("hover", AF.row(true))
	b.add_theme_stylebox_override("pressed", AF.row(true))
	b.pressed.connect(cb)
	return b
