extends "res://scripts/ui/gamemenu/gm_tab.gd"
## JOURNAL: the chronicle (news and rumours), the biography, the family and the
## people met. Data: Life.life_courses, Life.biography, Life.life_path, Life.family.

const LC := preload("res://scripts/sim/life_courses.gd")

var _ld: Kit.ListDetail
var _data := {}


func build() -> void:
	_ld = Kit.ListDetail.new(300)
	_ld.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ld.selected.connect(func(_id: String) -> void: _show_detail())
	add_child(_ld)


func on_show() -> void:
	refresh()


func refresh() -> void:
	_data = MD.journal()
	var items: Array = [{"id": "chronicle", "name": "Chronicle", "icon": "jr_chronicle"},
		{"id": "biography", "name": "Biography", "icon": "jr_bio"}, {"id": "family", "name": "Family", "icon": "jr_family"}]
	var people: Array = _data["people"]
	items.append({"header": "People met"})
	if people.is_empty():
		items.append({"note": "You have not met anyone worth remembering yet. Talk to people and they will be listed here."})
	for p: Dictionary in people:
		items.append({"id": "p:%d" % int(p["id"]), "name": String(p["name"]) + ("" if bool(p["alive"]) else " (deceased)"),
			"icon": "jr_people", "right": str(int(p["age"]))})
	_ld.set_items(items)
	if _ld.current != "":
		_ld.select(_ld.current)
	hints_changed()


func _show_detail() -> void:
	var d := _ld.detail
	Kit.clear(d)
	var id := _ld.current
	match id:
		"chronicle":
			_chronicle(d)
		"biography":
			_biography(d)
		"family":
			_family(d)
		_:
			if id.begins_with("p:"):
				_person(d, int(id.substr(2)))


func _title(d: VBoxContainer, text: String, sub := "") -> void:
	d.add_child(Kit.lbl(text, 28, AF.TEXT, true, "title_bold"))
	if sub != "":
		d.add_child(Kit.lbl(sub, 16, AF.GOLD))


func _line(d: VBoxContainer, text: String, dim := false) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Kit.diamond(8.0, AF.GOLD_DIM if dim else AF.GOLD))
	h.add_child(Kit.lbl(text, 17, AF.TEXT_DIM if dim else AF.TEXT, true))
	d.add_child(h)


func _chronicle(d: VBoxContainer) -> void:
	_title(d, "Chronicle", "What the realm has been saying")
	d.add_child(Kit.section("Recent news", 18))
	var news: Array = _data["chronicle"]
	if news.is_empty():
		d.add_child(Kit.lbl("Nothing new, but the world is still turning.", 17, AF.TEXT_DIM, true, "italic"))
	for n: String in news.slice(0, 14):
		_line(d, n)
	d.add_child(Kit.section("Rumours", 18))
	var rumours: Array = Life.life_courses.call("rumours", 6)
	if rumours.is_empty():
		d.add_child(Kit.lbl("No one is whispering anything worth repeating.", 17, AF.TEXT_DIM, true, "italic"))
	for r: String in rumours:
		_line(d, r, true)


func _biography(d: VBoxContainer) -> void:
	var lp: Object = Life.life_path
	_title(d, ("%s %s" % [lp.get("given_name"), lp.get("family_name")]).strip_edges(), "Age %d  ·  Day %d" % [Life.age(), int(WorldSim.day)])
	d.add_child(Kit.section("Life so far", 18))
	for line: String in _data["biography"]:
		d.add_child(Kit.lbl(line, 17, AF.TEXT, true))
	d.add_child(Kit.section("Deeds", 18))
	var deeds: Array = Life.biography.call("all_highlights")
	if deeds.is_empty():
		d.add_child(Kit.lbl("Nothing worth writing down yet.", 17, AF.TEXT_DIM, true, "italic"))
	deeds.reverse()
	for h: Dictionary in deeds.slice(0, 10):
		_line(d, "Day %d  ·  %s" % [int(h["day"]), String(h["text"])])
	d.add_child(Kit.section("Titles", 18))
	var titles: Array = _data["titles"]
	if titles.is_empty():
		d.add_child(Kit.lbl("No titles yet.", 17, AF.TEXT_DIM, true, "italic"))
	for t: Dictionary in titles:
		d.add_child(Kit.lbl(String(t["name"]), 17, AF.GOLD_BRIGHT, false, "title"))
		d.add_child(Kit.lbl(String(t["desc"]), 15, AF.TEXT_DIM, true, "italic"))


func _family(d: VBoxContainer) -> void:
	_title(d, "Family", "Those who share your name")
	var lines: Array = _data["family"]
	if lines.is_empty():
		d.add_child(Kit.lbl("No family on record.", 17, AF.TEXT_DIM, true, "italic"))
	for l: String in lines:
		_line(d, l)
	var fam: Object = Life.family
	if fam != null and not (fam.get("courtships") as Dictionary).is_empty():
		d.add_child(Kit.section("Courtships", 18))
		for npc: String in (fam.get("courtships") as Dictionary):
			_line(d, "%s  ·  %s" % [String(fam.call("_npc_name", npc)), String(fam.call("stage", npc)).capitalize()])


func _person(d: VBoxContainer, pid: int) -> void:
	var p: Dictionary = Life.life_courses.call("person", pid)
	if p.is_empty():
		return
	var alive := bool(p.get("alive", true))
	var meta := "Age %d  ·  %s" % [int(Life.life_courses.call("age_years", pid, int(WorldSim.day))), String(p.get("occupation", "")).capitalize()]
	for entry: Dictionary in _data["people"]:
		if int(entry["id"]) == pid and String(entry["place"]) != "":
			meta += "  ·  " + String(entry["place"])
	_title(d, String(p.get("name", "?")) + ("" if alive else " (deceased)"), meta)
	if not alive:
		var cause := String(p.get("cause_of_death", ""))
		if cause != "":
			d.add_child(Kit.lbl("Died %s." % String(LC.CAUSE_TEXT.get(cause, cause)), 17, AF.TEXT_DIM, true, "italic"))
	var tree: Dictionary = Life.life_courses.call("family_tree", pid)
	d.add_child(Kit.section("Family", 18))
	var any := false
	for label: String in ["parents", "children"]:
		var names := PackedStringArray()
		for rel: Dictionary in tree.get(label, []):
			names.append(String(rel.get("name", "?")))
		if not names.is_empty():
			any = true
			_line(d, "%s: %s" % [label.capitalize(), ", ".join(names)])
	var sp: Dictionary = tree.get("spouse", {})
	if not sp.is_empty():
		any = true
		_line(d, "Spouse: %s" % String(sp.get("name", "?")))
	if not any:
		d.add_child(Kit.lbl("No known family on record.", 17, AF.TEXT_DIM, true, "italic"))
	var events: Array = p.get("events", [])
	if not events.is_empty():
		d.add_child(Kit.section("Remembered", 18))
		for ev: Variant in events.slice(maxi(0, events.size() - 6), events.size()):
			_line(d, String(ev.get("text", "")) if ev is Dictionary else String(ev), true)


func handle_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_UP:
			_ld.step(-1)
		KEY_DOWN:
			_ld.step(1)
		_:
			return false
	return true


func hints() -> Array:
	return [["Up/Dn", "Select", func() -> void: _ld.step(1), false]]
