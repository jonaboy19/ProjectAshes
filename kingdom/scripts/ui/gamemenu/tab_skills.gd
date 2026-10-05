extends "res://scripts/ui/gamemenu/gm_tab.gd"
## SKILLS / PROGRESSION: sub-tabs Attribute, Skills, Mastery, Reputation, Biography,
## each a list of entries on the left and the selected one on the right. Data from
## Life.mastery, Life.skills (techniques), Life.soul, Life.biography, Life.relationships.

const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const PathsView := preload("res://scripts/ui/gamemenu/paths_view.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const SUBS := [["attributes", "Attribute"], ["skills", "Skills"], ["paths", "Paths"], ["mastery", "Mastery"],
	["reputation", "Reputation"], ["biography", "Biography"]]

var _sub := "skills"
var _sub_bar: FlowContainer           # wraps on a narrow (portrait) screen
var _ld: Kit.ListDetail
var _paths: PathsView
var _picked := {}                     # sub -> selected id


func build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_sub_bar = HFlowContainer.new()
	_sub_bar.add_theme_constant_override("h_separation", 6)
	_sub_bar.add_theme_constant_override("v_separation", 6)
	col.add_child(_sub_bar)
	_ld = Kit.ListDetail.new(260)
	_ld.selected.connect(func(id: String) -> void:
		_picked[_sub] = id
		_show_detail())
	col.add_child(_ld)
	_paths = PathsView.new()
	_paths.visible = false
	_paths.learn_requested.connect(_on_learn_path_technique)
	col.add_child(_paths)


## The power-path profile of the live character (empty profile before the realm exists).
func _power_profile() -> Dictionary:
	var pp: Variant = Life.realm.mod("power_paths") if Life.realm != null and (Life.realm.get("mods") as Dictionary).has("power_paths") else null
	return pp.profile() if pp != null else PowerTrees.empty_profile()


func _on_learn_path_technique(id: String) -> void:
	var pp: Variant = Life.realm.mod("power_paths") if Life.realm != null else null
	if pp != null:
		pp.learn_technique(id)
	refresh()


func open_sub(sub: String, id := "") -> void:
	_sub = sub
	if id != "":
		_picked[sub] = id
	refresh()


func on_show() -> void:
	refresh()


func refresh() -> void:
	Kit.clear(_sub_bar)
	for s: Array in SUBS:
		_sub_bar.add_child(Kit.tab_button(String(s[1]), String(s[0]) == _sub, func() -> void: open_sub(String(s[0])), 150))
	_sub_bar.add_child(Kit.hspacer())
	var pts := Kit.lbl("Skill Points  %d" % int(Life.skills.points), 16, AF.GOLD_BRIGHT, false, "title")
	pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub_bar.add_child(pts)
	var on_paths := _sub == "paths"
	_ld.visible = not on_paths
	_paths.visible = on_paths
	if on_paths:
		_paths.set_profile(_power_profile())
		hints_changed()
		return
	_ld.set_items(_items(), false)
	var want := String(_picked.get(_sub, ""))
	if want != "":
		_ld.select(want)
	if _ld.current != "":
		_ld.select(_ld.current)
	else:
		_show_detail()
	hints_changed()


func _items() -> Array:
	var out: Array = []
	var lvl := Life.player_level()
	match _sub:
		"attributes":
			for a: Dictionary in MD.attributes(Life.mastery, lvl):
				out.append({"id": a["id"], "name": a["name"], "icon": "attr_" + String(a["id"]), "right": str(a["value"])})
		"skills":
			var ctx := MD.Skills.ctx_from_life(Life)
			for g: Dictionary in MD.GROUPS:
				var info := MD.group_info(String(g["id"]), Life.mastery, Life.skills, ctx)
				out.append({"id": g["id"], "name": g["name"], "icon": g["icon"], "right": str(info["level"])})
		"mastery":
			out.append({"id": "__soul", "name": "Soul Power", "icon": "sk_soul", "right": String(Life.soul.call("tier_info").get("name", ""))})
			for r: Dictionary in MD.mastery_rows(Life.mastery):
				out.append({"id": r["id"], "name": r["name"], "icon": "perk", "right": str(r["level"])})
		"reputation":
			var rep := MD.reputation(Life.biography, Life.relationships)
			out.append({"header": "Factions"})
			for f: Dictionary in rep["factions"]:
				out.append({"id": "f:" + String(f["id"]), "name": f["name"], "icon": "rep", "right": String(f["standing"])})
			out.append({"header": "Spheres of life"})
			for s: Dictionary in rep["spheres"]:
				out.append({"id": "s:" + String(s["id"]), "name": s["name"], "icon": "rep", "right": str(int(round(float(s["value"]))))})
		"biography":
			for e: Array in [["summary", "Life summary", "jr_bio"], ["career", "Career", "sk_social"],
					["titles", "Titles", "rep"], ["deeds", "Deeds", "jr_chronicle"]]:
				out.append({"id": e[0], "name": e[1], "icon": e[2]})
	return out


func _show_detail() -> void:
	var d := _ld.detail
	Kit.clear(d)
	var id := _ld.current
	if id == "":
		d.add_child(Kit.lbl("Nothing here yet.", 17, AF.TEXT_DIM, true, "italic"))
		return
	match _sub:
		"attributes":
			_detail_attribute(d, id)
		"skills":
			_detail_group(d, id)
		"mastery":
			if id == "__soul":
				_detail_soul(d)
			else:
				_detail_mastery(d, id)
		"reputation":
			_detail_rep(d, id)
		"biography":
			_detail_bio(d, id)


# ---------------------------------------------------------------- shared bits ----

func _head(d: VBoxContainer, icon_name: String, title: String, right: String, ratio := -1.0, bar_text := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	d.add_child(h)
	h.add_child(Kit.framed_icon(icon_name, 56, AF.GOLD_BRIGHT, AF.GOLD))
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_theme_constant_override("separation", 6)
	h.add_child(t)
	var line := HBoxContainer.new()
	t.add_child(line)
	line.add_child(Kit.lbl(title, 26, AF.TEXT, false, "title_bold"))
	line.add_child(Kit.hspacer())
	var rl := Kit.lbl(right, 18, AF.GOLD_BRIGHT, false, "title")
	rl.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(rl)
	if ratio >= 0.0:
		t.add_child(Kit.bar(ratio, 14.0, AF.GOLD, bar_text))


func _kv(d: Control, k: String, v: String, color := AF.TEXT) -> void:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 30
	h.add_child(Kit.lbl(k, 17, AF.TEXT_DIM))
	h.add_child(Kit.hspacer())
	h.add_child(Kit.lbl(v, 18, color, false, "title"))
	d.add_child(h)
	d.add_child(AF.separator())


# ------------------------------------------------------------------ attributes ----

func _detail_attribute(d: VBoxContainer, id: String) -> void:
	var a := {}
	for x: Dictionary in MD.ATTRIBUTES:
		if x["id"] == id:
			a = x
	var value := MD.attribute_value(Life.mastery, a["from"], Life.player_level())
	_head(d, "attr_" + id, String(a["name"]), str(value), clampf(float(value) / 30.0, 0.0, 1.0), "%d / 30" % value)
	d.add_child(Kit.lbl(String(a["blurb"]), 17, AF.TEXT, true))
	d.add_child(Kit.section("Derived from", 17))
	for disc: String in a["from"]:
		var lv := int(Life.mastery.call("level", disc))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.custom_minimum_size.y = 30
		h.add_child(Kit.lbl(disc.replace("_", " ").capitalize(), 17, AF.TEXT))
		h.add_child(Kit.hspacer())
		var b := Kit.bar(float(lv) / 100.0, 8.0)
		b.custom_minimum_size.x = 160
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		h.add_child(Kit.lbl(str(lv), 17, AF.GOLD_BRIGHT, false, "title"))
		d.add_child(h)
	d.add_child(Kit.lbl("Base 8, plus a sixth of the average mastery level and one per four character levels. The game has no attribute points yet: attributes follow what you practise.", 14, AF.TEXT_DIM, true, "italic"))


# ---------------------------------------------------------------------- skills ----

func _detail_group(d: VBoxContainer, id: String) -> void:
	var ctx := MD.Skills.ctx_from_life(Life)
	var info := MD.group_info(id, Life.mastery, Life.skills, ctx)
	if info.is_empty():
		return
	_head(d, String(info["icon"]), String(info["name"]), "Level %d  ·  %s" % [info["level"], info["rank_word"]],
		float(info["ratio"]), String(info["bar_text"]))
	d.add_child(Kit.lbl(String(info["desc"]), 16, AF.TEXT_DIM, true, "italic"))
	d.add_child(Kit.section("Perks & Techniques", 17))
	var perks: Array = info["perks"]
	if perks.is_empty():
		var g := MD.group_by_id(id)
		if (g["trees"] as Array).is_empty():
			var manuals: Dictionary = Life.skills.manuals
			if manuals.is_empty():
				d.add_child(Kit.lbl("No manuals read yet. Knowledge grows from scholarship, alchemy and beast lore; manuals found in the world unlock techniques.", 16, AF.TEXT_DIM, true, "italic"))
			for mid: String in manuals:
				var md: Dictionary = Life.skills.manual_defs.get(mid, {})
				d.add_child(_perk_row({"name": String(md.get("name", mid)), "desc": "Manual read on day %d." % int(manuals[mid]),
					"icon": "sk_knowledge", "color": AF.GOLD, "learned": true, "rank": 1, "max_rank": 1, "id": "", "can_learn": false,
					"maxed": true, "reason": "", "cost": 0}))
		else:
			d.add_child(Kit.lbl("Nothing revealed yet.", 16, AF.TEXT_DIM, true, "italic"))
	for p: Dictionary in perks:
		d.add_child(_perk_row(p))


func _perk_row(p: Dictionary) -> Control:
	var learned := bool(p["learned"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var ic := Kit.framed_icon(String(p["icon"]), 48, (p["color"] as Color) if learned else Color(AF.TEXT, 0.35),
		(p["color"] as Color) if learned else AF.GOLD_DIM)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_constant_override("separation", 1)
	h.add_child(t)
	var nl := HBoxContainer.new()
	nl.add_child(Kit.lbl(String(p["name"]), 18, AF.TEXT if learned else AF.TEXT_DIM, false, "title"))
	nl.add_child(Kit.hspacer())
	if int(p["max_rank"]) > 1 or learned:
		nl.add_child(Kit.lbl("Rank %d/%d" % [int(p["rank"]), int(p["max_rank"])], 15, AF.GOLD if learned else AF.TEXT_DIM))
	t.add_child(nl)
	t.add_child(Kit.lbl(String(p["desc"]), 15, AF.TEXT_DIM, true))
	if bool(p["can_learn"]):
		var b := Kit.button("%s  (%d pt)" % ["Learn" if not learned else "Rank up", int(p["cost"])], true, 48, 15)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pid := String(p["id"])
		b.pressed.connect(func() -> void: _learn(pid))
		h.add_child(b)
	elif String(p["reason"]) != "":
		t.add_child(Kit.lbl(String(p["reason"]), 14, Color(AF.GOLD, 0.7), true, "italic"))
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.add_child(h)
	wrap.add_child(AF.separator())
	return wrap


func _learn(pid: String) -> void:
	var r: Dictionary = Life.skills.call("learn", pid, MD.Skills.ctx_from_life(Life))
	Game.say(String(r.get("text", "")))
	Audio.play_ui("pickup")
	refresh()


# --------------------------------------------------------------------- mastery ----

func _detail_mastery(d: VBoxContainer, id: String) -> void:
	var row := {}
	for r: Dictionary in MD.mastery_rows(Life.mastery):
		if r["id"] == id:
			row = r
	if row.is_empty():
		return
	var prog: Vector2 = Life.mastery.call("xp_progress", id)
	_head(d, "perk", String(row["name"]), "Level %d  ·  %s" % [row["level"], row["word"]], float(row["ratio"]),
		"%d / %d" % [int(prog.x * 100.0), int(prog.y * 100.0)] if prog.y > 0.0 else "Max")
	_kv(d, "Rank", String(row["word"]))
	_kv(d, "Years practised", str(row["years"]))
	_kv(d, "Days of practice", str(int(Life.mastery.days_practised.get(id, 0))))
	var feeds: Dictionary = MD.Mastery.OVERLAPS.get(id, {})
	for f: String in feeds:
		_kv(d, "Also trains", "%s (%d%%)" % [f.replace("_", " ").capitalize(), int(float(feeds[f]) * 100.0)])
	d.add_child(Kit.lbl("Mastery only grows by doing: there is no free experience, and changing careers never hands you a level.", 14, AF.TEXT_DIM, true, "italic"))


func _detail_soul(d: VBoxContainer) -> void:
	var soul: Object = Life.soul
	var prog: Dictionary = soul.call("progress")
	_head(d, "sk_soul", "Soul Power", String(prog.get("tier_name", "")), float(prog.get("ratio", 0.0)),
		"%d / %d" % [int(prog.get("into", 0.0)), int(prog.get("needed", 0.0))] if float(prog.get("ratio", 0.0)) < 1.0 else "Peak")
	d.add_child(Kit.lbl(String((soul.call("tier_info") as Dictionary).get("flavour", "")), 16, AF.TEXT_DIM, true, "italic"))
	if float(prog.get("ratio", 0.0)) < 1.0:
		d.add_child(Kit.lbl("Toward %s." % String(prog.get("next_tier", "?")), 16, AF.TEXT, true))
	d.add_child(Kit.section("Path", 17))
	var path_info: Dictionary = soul.call("path_info")
	if not path_info.is_empty():
		d.add_child(Kit.lbl("%s: %s" % [path_info.get("name", ""), path_info.get("flavour", "")], 16, AF.TEXT, true))
	else:
		var disciplines := {}
		for r: Dictionary in (Life.mastery.call("top", 6) as Array):
			disciplines[String(r["discipline"])] = int(r["level"])
		var dom: Dictionary = soul.call("dominant_path", disciplines)
		if dom.is_empty():
			d.add_child(Kit.lbl("No Path has emerged yet. Keep living; it will show itself.", 16, AF.TEXT_DIM, true, "italic"))
		else:
			d.add_child(Kit.lbl("Emerging: %s. %s" % [dom.get("name", ""), dom.get("flavour", "")], 16, AF.TEXT, true))
			var b := Kit.button("Take up " + String(dom.get("name", "")), true, 48, 16)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var pid := String(dom.get("id", ""))
			b.pressed.connect(func() -> void:
				soul.call("choose_path", pid)
				refresh())
			d.add_child(b)
	d.add_child(Kit.section("Evolutions", 17))
	var evos: Dictionary = Life.skill_evolution.call("evolutions")
	if evos.is_empty():
		d.add_child(Kit.lbl("No abilities have evolved yet: how you use them shapes what they become.", 16, AF.TEXT_DIM, true, "italic"))
	for eid: String in evos:
		var def: Dictionary = evos[eid]
		d.add_child(Kit.lbl("%s  (%s)" % [def.get("name", eid), def.get("element", "")], 17, AF.TEXT))
	if bool(soul.call("can_attempt_breakthrough")):
		var bb := Kit.button("Attempt breakthrough", true, 48, 16)
		bb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bb.pressed.connect(func() -> void:
			var res: Dictionary = soul.call("attempt_breakthrough", -1, {})
			Game.say(String(res.get("text", "")))
			refresh())
		d.add_child(bb)


# ------------------------------------------------------------------ reputation ----

func _detail_rep(d: VBoxContainer, id: String) -> void:
	var rep := MD.reputation(Life.biography, Life.relationships)
	var is_f := id.begins_with("f:")
	var key := id.substr(2)
	var entry := {}
	for e: Dictionary in rep["factions" if is_f else "spheres"]:
		if e["id"] == key:
			entry = e
	if entry.is_empty():
		return
	var v := float(entry["value"])
	_head(d, "rep", String(entry["name"]), String(entry["standing"]) if is_f else ("%+d" % int(round(v))),
		clampf((v + 100.0) / 200.0, 0.0, 1.0), "%+d" % int(round(v)))
	if is_f:
		d.add_child(Kit.lbl("How %s regards you. Standing runs from Hated to Revered; deeds done for them, or against them, move it." % String(entry["name"]), 17, AF.TEXT, true))
	else:
		d.add_child(Kit.lbl("How %s circles talk about you. It is earned by the work you do in that trade and by what you are seen doing." % String(entry["name"]).to_lower(), 17, AF.TEXT, true))
	d.add_child(Kit.lbl("Scale: -100 (hated) to +100 (revered).", 14, AF.TEXT_DIM, true, "italic"))


# ------------------------------------------------------------------- biography ----

func _detail_bio(d: VBoxContainer, id: String) -> void:
	var day := int(WorldSim.day)
	match id:
		"summary":
			var lp: Object = Life.life_path
			_head(d, "jr_bio", ("%s %s" % [lp.get("given_name"), lp.get("family_name")]).strip_edges(), "Age %d" % Life.age())
			for line: String in (Life.biography.call("summary", day) as Array):
				d.add_child(Kit.lbl(line, 17, AF.TEXT, true))
			d.add_child(Kit.spacer(4))
			d.add_child(Kit.lbl(String(Life.tendencies.call("describe")), 15, AF.TEXT_DIM, true, "italic"))
		"career":
			_detail_career(d)
		"titles":
			d.add_child(Kit.section("Titles earned", 18))
			var list: Array = Life.titles.call("earned_list")
			if list.is_empty():
				d.add_child(Kit.lbl("No titles yet.", 16, AF.TEXT_DIM, true, "italic"))
			for t: Dictionary in list:
				var v := VBoxContainer.new()
				v.add_theme_constant_override("separation", 1)
				v.add_child(Kit.lbl(String(t.get("name", "")), 18, AF.GOLD_BRIGHT, false, "title"))
				v.add_child(Kit.lbl(String(t.get("desc", "")), 15, AF.TEXT_DIM, true, "italic"))
				d.add_child(v)
		"deeds":
			d.add_child(Kit.section("Deeds", 18))
			var deeds: Array = Life.biography.call("all_highlights")
			if deeds.is_empty():
				d.add_child(Kit.lbl("Nothing worth writing down yet.", 16, AF.TEXT_DIM, true, "italic"))
			deeds.reverse()
			for h: Dictionary in deeds.slice(0, 30):
				d.add_child(Kit.lbl("Day %d  ·  %s" % [int(h["day"]), String(h["text"])], 16, AF.TEXT, true))


func _detail_career(d: VBoxContainer) -> void:
	var career := String(Life.career_id)
	var rank := String(Life.career_rank)
	if career == "":
		_head(d, "sk_social", "No career yet", "")
		d.add_child(Kit.lbl("Take up work in the village to begin one.", 17, AF.TEXT_DIM, true, "italic"))
		return
	_head(d, "sk_social", career.capitalize(), CareerLadders.title_for(career, rank))
	var flags: Dictionary = Life.life_path.flags
	var ctx := {"career": career, "rank": rank, "since_day": int(Life.career_since_day), "day": WorldSim.day,
		"mastery": Life.mastery, "biography": Life.biography, "careers": Life.careers, "gold": Game.gold,
		"at_war": bool(flags.get("at_war", false)), "sponsor_tier": int(Life.career_sponsor_tier),
		"leased_plot": not Life.homestead.leased.is_empty(), "owns_plot": not Life.homestead.owned.is_empty()}
	var check: Dictionary = CareerLadders.check_promotion(ctx)
	d.add_child(Kit.section("Next rank", 17))
	var nxt: Dictionary = check.get("next", {})
	if nxt.is_empty():
		d.add_child(Kit.lbl("At the top of this ladder.", 17, AF.TEXT, true))
		return
	d.add_child(Kit.lbl(String(nxt["title"]), 18, AF.GOLD_BRIGHT, false, "title"))
	var missing: PackedStringArray = check.get("missing", PackedStringArray())
	if missing.is_empty():
		d.add_child(Kit.lbl("Ready. Report to whoever can sign for it.", 16, Kit.GREEN, true))
	for m: String in missing:
		d.add_child(Kit.lbl("• " + m, 16, AF.TEXT, true))


func handle_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_UP:
			_ld.step(-1)
		KEY_DOWN:
			_ld.step(1)
		KEY_LEFT, KEY_RIGHT:
			var i := 0
			for k in SUBS.size():
				if SUBS[k][0] == _sub:
					i = k
			i = clampi(i + (1 if e.keycode == KEY_RIGHT else -1), 0, SUBS.size() - 1)
			open_sub(String(SUBS[i][0]))
		_:
			return false
	return true


func hints() -> Array:
	return [["Up/Dn", "Select", func() -> void: _ld.step(1), false], ["L/R", "Section", func() -> void: handle_key(_fake(KEY_RIGHT)), false]]


func _fake(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e
