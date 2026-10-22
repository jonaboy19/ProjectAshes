extends GdUnitTestSuite
## Path trees as data (data/powers/*.json, scripts/abilities/power_trees.gd): five paths with levels, sub-paths,
## manuals, milestones and techniques whose unlock requirements tie to cultivation stage, path level, manuals/teachers,
## milestones and prerequisites; Region 1 caps; sect (donghua) and knight (own tree) kept separate; the second-path
## penalty in power_paths.gd; the Skills tab view model and widget.

const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const Cult := preload("res://scripts/realm/cultivation.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const PathsView := preload("res://scripts/ui/gamemenu/paths_view.gd")

const PATHS := ["magic", "bending", "sect", "knight", "beast"]


func _profile(path: String, level := 1, realm := 1, stage := 1, extra := {}) -> Dictionary:
	var p := PowerTrees.empty_profile()
	p["paths"] = [path]
	p["primary"] = path
	p["levels"] = {path: level}
	p["realms"] = {path: {"realm": realm, "stage": stage}}
	p["theory"] = {path: 0.0}
	for k: String in extra:
		p[k] = extra[k]
	return p


# --- data integrity -------------------------------------------------------------------

func test_five_paths_load_with_levels_subpaths_manuals_and_milestones() -> void:
	assert_array(PowerTrees.path_ids()).is_equal(PATHS)
	for path: String in PATHS:
		var d := PowerTrees.path_data(path)
		assert_int((d["levels"] as Array).size()).is_greater_equal(6)
		assert_int((d["subpaths"] as Array).size()).is_greater_equal(3)
		assert_int((d["manuals"] as Array).size()).is_greater_equal(6)
		assert_int((d["milestones"] as Array).size()).is_greater_equal(3)
		assert_int((d["techniques"] as Array).size()).is_greater_equal(14)
		assert_bool(d.has("subpath_slots")).is_true()
		assert_str(PowerTrees.rank_name(path, 1)).is_not_equal("")
		assert_str(PowerTrees.rank_name(path, 30)).is_not_equal(PowerTrees.rank_name(path, 1))


func test_every_ability_row_validates_and_ids_are_unique() -> void:
	assert_array(AbilityLib.validate_all()).is_empty()
	var seen := {}
	for path: String in PATHS:
		for t: Dictionary in PowerTrees.techniques_of(path):
			var id := String(t["id"])
			assert_bool(seen.has(id)).override_failure_message("duplicate id " + id).is_false()
			seen[id] = path
			assert_str(AbilityLib.get_def(id)["path"]).is_equal(path)
	# No path-tree id shadows a legacy skills.gd technique.
	for id: String in AbilityLib.legacy_ids():
		assert_bool(seen.has(id)).override_failure_message("shadows legacy " + id).is_false()


func test_costs_use_the_paths_own_resource_and_cooldown_covers_windup() -> void:
	for path: String in PATHS:
		for t: Dictionary in PowerTrees.techniques_of(path):
			var ab := PowerTrees.ability(String(t["id"]))
			if ab["kind"] != "active":
				continue
			for r: String in ab["costs"]:
				assert_bool(r in (AbilityDef.PATH_RESOURCES[path] as Array)).override_failure_message("%s costs %s" % [t["id"], r]).is_true()
			assert_float(float(ab["cooldown"])).is_greater_equal(float(ab["windup"]) + float(ab["recover"]))
			assert_bool(PowerTrees.subpaths(path).any(func(s: Dictionary) -> bool: return s["id"] == t["subpath"]) or t["subpath"] == "core").is_true()


func test_requirements_reference_real_things() -> void:
	for path: String in PATHS:
		var manual_ids := {}
		for m: Dictionary in PowerTrees.manuals_of(path):
			manual_ids[m["id"]] = true
			for tid: String in m["techniques"]:
				assert_str(PowerTrees.path_of(tid)).is_equal(path)
		for t: Dictionary in PowerTrees.techniques_of(path):
			var req: Dictionary = t["req"]
			assert_bool(req.has("realm")).is_true()
			assert_bool(req.has("path_level")).is_true()
			assert_bool(req.has("manual") or req.has("teacher")).override_failure_message(t["id"] + " has no manual or teacher").is_true()
			for mid: String in req.get("manual", []):
				assert_bool(manual_ids.has(mid) or not Cult.manual(mid).is_empty()).override_failure_message("%s unknown manual %s" % [t["id"], mid]).is_true()
			for q: String in req.get("prereq", []):
				assert_str(PowerTrees.path_of(q)).is_equal(path)
				assert_int(int(PowerTrees.technique(q)["tier"])).is_less(int(t["tier"]))     # no cycles
			var ms_ids: Array = []
			for m: Dictionary in PowerTrees.milestones(path):
				ms_ids.append(m["id"])
			for m: String in req.get("milestone", []):
				assert_bool(ms_ids.has(m)).override_failure_message("%s unknown milestone %s" % [t["id"], m]).is_true()


func test_matches_the_cultivation_module_where_they_overlap() -> void:
	# The six techniques per path that cultivation.json already lists keep its realm, stage and manual.
	var n := 0
	for ct: Dictionary in Cult.data()["techniques"]:
		var id := String(ct["id"])
		assert_bool(PowerTrees.has_technique(id)).override_failure_message("missing " + id).is_true()
		var req: Dictionary = PowerTrees.technique(id)["req"]
		assert_int(int(req["realm"])).is_equal(int(ct["realm"]))
		assert_int(int(req["stage"])).is_equal(int(ct["stage"]))
		assert_str(PowerTrees.path_of(id)).is_equal(String(ct["path"]))
		var cm := ""
		for m: Dictionary in Cult.data()["manuals"]:
			if (m["techniques"] as Array).has(id):
				cm = String(m["id"])
		assert_bool((req["manual"] as Array).has(cm)).override_failure_message(id + " manual").is_true()
		n += 1
	assert_int(n).is_equal(31)


# --- Region 1 -------------------------------------------------------------------------

func test_region_one_content_stays_inside_the_caps() -> void:
	var cap := PowerTrees.region_cap()
	assert_int(int(cap["level"])).is_equal(60)
	assert_int(int(cap["realm"])).is_equal(3)
	for path: String in PATHS:
		var in_r1 := 0
		var beyond := 0
		for t: Dictionary in PowerTrees.techniques_of(path):
			var id := String(t["id"])
			if PowerTrees.in_region_one(id):
				in_r1 += 1
				assert_int(int(t["req"]["realm"])).is_less_equal(3)
				assert_int(int(t["req"]["path_level"])).is_less_equal(int(cap["path_level"]))
			else:
				beyond += 1
				assert_int(int(t["region"])).is_greater_equal(2)
				assert_int(int(t["req"]["realm"])).is_greater_equal(4)      # Core Formation or later
		assert_int(in_r1).override_failure_message(path).is_greater_equal(10)
		assert_int(beyond).is_greater_equal(1)
		assert_bool(beyond < in_r1).is_true()
	# Every Region 1 stage position is reachable at or under the level cap (cultivation gate table).
	for path: String in PATHS:
		for t: Dictionary in PowerTrees.techniques_of(path):
			if PowerTrees.in_region_one(String(t["id"])):
				assert_int(Cult.level_needed(int(t["req"]["realm"]), int(t["req"]["stage"]))).is_less_equal(60)


func test_beyond_region_techniques_show_as_beyond_not_learnable() -> void:
	var p := _profile("sect", 12, 3, 3, {"manuals": ["m_st4"]})
	var st := PowerTrees.state("st_core", p)
	assert_str(st["state"]).is_equal("beyond")
	assert_bool((st["reasons"] as Array).is_empty()).is_false()


# --- sect and knight stay separate traditions ------------------------------------------

func test_sect_is_donghua_and_strains_the_channels() -> void:
	var d := PowerTrees.path_data("sect")
	assert_str(d["tradition"]).is_equal("donghua")
	assert_str(d["blurb"].to_lower()).contains("manual")
	var attacks := 0
	for t: Dictionary in PowerTrees.techniques_of("sect"):
		var ab := PowerTrees.ability(String(t["id"]))
		if ab["kind"] == "active" and ab["damage"] > 0:
			attacks += 1
			assert_float(float(ab["strain"])).override_failure_message(t["id"] + " has no meridian strain").is_greater(0.0)
			assert_bool(ab["costs"].has("qi")).is_true()
	assert_int(attacks).is_greater_equal(6)
	var sub_ids: Array = []
	for s: Dictionary in PowerTrees.subpaths("sect"):
		sub_ids.append(s["id"])
	assert_array(sub_ids).contains(["palm", "sword_qi", "body", "breath"])
	# The strain-relief breathing exists.
	assert_bool(PowerTrees.has_technique("st_nine_breaths")).is_true()


func test_knight_arts_are_their_own_tree_and_work_on_empty_qi() -> void:
	var d := PowerTrees.path_data("knight")
	assert_str(d["tradition"]).is_equal("knight")
	var sub_ids: Array = []
	for s: Dictionary in PowerTrees.subpaths("knight"):
		sub_ids.append(s["id"])
	assert_array(sub_ids).is_equal(["forms", "charge", "armour"])
	var has_aura := false
	var has_charge := false
	var has_armour := false
	for t: Dictionary in PowerTrees.techniques_of("knight"):
		var ab := PowerTrees.ability(String(t["id"]))
		assert_bool(ab["costs"].has("qi")).override_failure_message(t["id"] + " needs qi").is_false()
		assert_bool(ab["costs"].has("magicules")).is_false()
		for e: Dictionary in ab["effects"]:
			if e["type"] == "aura":
				has_aura = true
		has_charge = has_charge or (t["subpath"] == "charge" and ab["targeting"]["kind"] == "dash")
		has_armour = has_armour or t["subpath"] == "armour"
		assert_float(float(ab["strain"])).is_equal(0.0)      # no meridians: not a reskin of the sect tree
	assert_bool(has_aura and has_charge and has_armour).is_true()
	# No technique id, name or manual is shared between the two traditions.
	var sect_names := {}
	for t: Dictionary in PowerTrees.techniques_of("sect"):
		sect_names[String(t["name"])] = true
	for t: Dictionary in PowerTrees.techniques_of("knight"):
		assert_bool(sect_names.has(String(t["name"]))).is_false()
	# And a knight meets her requirements with an empty qi pool: no qi anywhere in her manuals' techniques.
	var p := _profile("knight", 13, 3, 4, {"manuals": ["m_kn1", "m_kn2", "m_kn3"], "milestones": {"knight": ["aura_woken"]}})
	assert_str(PowerTrees.state("kn_aura", p)["state"]).is_equal("ready")


# --- states and requirements ---------------------------------------------------------

func test_fresh_character_has_everything_locked() -> void:
	var p := PowerTrees.empty_profile()
	for path: String in PATHS:
		for t: Dictionary in PowerTrees.techniques_of(path):
			var st := PowerTrees.state(String(t["id"]), p)
			assert_bool(st["state"] in ["locked", "beyond"]).is_true()
			assert_int((st["reasons"] as Array).size()).is_greater_equal(1)


func test_a_technique_needs_path_stage_manual_and_level_together() -> void:
	# mg_spark: Mana Awakening-less: realm 1 stage 4, manual m_mg1, path level 1.
	var base := _profile("magic", 1, 1, 3)
	assert_str(PowerTrees.state("mg_spark", base)["state"]).is_equal("locked")           # stage 3 and no manual
	var staged := _profile("magic", 1, 1, 4)
	assert_str(PowerTrees.state("mg_spark", staged)["state"]).is_equal("locked")         # still no manual
	var with_manual := _profile("magic", 1, 1, 4, {"manuals": ["m_mg1"]})
	assert_str(PowerTrees.state("mg_spark", with_manual)["state"]).is_equal("ready")
	var known := _profile("magic", 1, 1, 4, {"manuals": ["m_mg1"], "known": ["mg_spark"]})
	assert_str(PowerTrees.state("mg_spark", known)["state"]).is_equal("known")
	# The wrong path never helps.
	var other := _profile("knight", 20, 3, 9, {"manuals": ["m_mg1"]})
	assert_str(PowerTrees.state("mg_spark", other)["state"]).is_equal("locked")


func test_teacher_or_manual_either_opens_the_same_technique() -> void:
	var p := _profile("sect", 1, 1, 3, {"teachers": ["sect_elder"]})
	assert_str(PowerTrees.state("st_palm", p)["state"]).is_equal("ready")               # taught in person
	var q := _profile("sect", 1, 1, 3, {"manuals": ["m_st1"]})
	assert_str(PowerTrees.state("st_palm", q)["state"]).is_equal("ready")               # or from the manual
	var none := _profile("sect", 1, 1, 3)
	var reasons: Array = PowerTrees.state("st_palm", none)["reasons"]
	assert_str(" ".join(PackedStringArray(reasons))).contains("taught by Sect Elder")


func test_subpath_and_prerequisites_and_milestones_gate() -> void:
	var p := _profile("magic", 6, 2, 4, {"manuals": ["m_mg_fire2", "m_mg2"], "teachers": ["academy_magister"], "subpaths": {"magic": []}})
	# Fire's second spell needs the fire sub-path chosen and Ember Orb known.
	var st := PowerTrees.state("mg_fire_wave", p)
	assert_str(st["state"]).is_equal("locked")
	var joined := " ".join(PackedStringArray(st["reasons"]))
	assert_str(joined).contains("Sub-path: Fire")
	assert_str(joined).contains("Know Ember Orb")
	p["subpaths"] = {"magic": ["fire"]}
	p["known"] = ["mg_fire_ember"]
	assert_str(PowerTrees.state("mg_fire_wave", p)["state"]).is_equal("ready")
	# Milestones: the knight's aura needs the waking-aura milestone.
	var k := _profile("knight", 13, 3, 4, {"manuals": ["m_kn3"]})
	assert_str(" ".join(PackedStringArray(PowerTrees.state("kn_aura", k)["reasons"]))).contains("Aura Woken")


func test_ready_lists_what_can_be_learned_now() -> void:
	var p := _profile("magic", 2, 1, 7, {"manuals": ["m_mg1"]})
	var ready := PowerTrees.ready("magic", p)
	assert_array(ready).contains(["mg_spark", "mg_ward"])
	assert_bool(ready.has("mg_circle_bolt")).is_false()


func test_realm_names_in_requirement_labels_are_path_specific() -> void:
	var labels: Array = []
	for r: Dictionary in PowerTrees.requirements("st_palm", PowerTrees.empty_profile()):
		labels.append(String(r["label"]))
	assert_str(" | ".join(PackedStringArray(labels))).contains("Body Tempering")    # sect keeps the donghua names
	labels.clear()
	for r: Dictionary in PowerTrees.requirements("kn_brace", PowerTrees.empty_profile()):
		labels.append(String(r["label"]))
	assert_str(" | ".join(PackedStringArray(labels))).contains("Conditioning")


# --- power_paths integration -----------------------------------------------------------

func _pp(paths: Array = []) -> RefCounted:
	var pp: RefCounted = Hub.new().mod("power_paths")
	for p: String in paths:
		pp.learn(p, "academy")
	return pp


func test_power_paths_tracks_milestones_theory_subpaths_manuals_and_mastery() -> void:
	var pp := _pp(["magic"])
	assert_float(pp.theory("magic")).is_equal(0.0)
	assert_float(pp.study_theory("magic", 0.4)).is_equal_approx(0.4, 0.0001)
	assert_float(pp.study_theory("magic", 0.9)).is_equal_approx(1.0, 0.0001)
	assert_bool(pp.add_milestone("magic", "first_circle")).is_true()
	assert_bool(pp.add_milestone("magic", "first_circle")).is_false()
	assert_bool(pp.choose_subpath("magic", "fire", 1)).is_true()
	assert_bool(pp.choose_subpath("magic", "water", 1)).is_false()          # realm 1 follows one sub-path
	assert_bool(pp.choose_subpath("magic", "water", 2)).is_true()
	assert_bool(pp.choose_subpath("magic", "fire", 3)).is_false()           # already followed
	assert_bool(pp.choose_subpath("magic", "gravity", 3)).is_false()
	assert_bool(pp.learn_manual("m_mg_fire1")["ok"]).is_true()
	assert_str(pp.learn_manual("m_mg_fire1")["reason"]).is_equal("known")
	assert_str(pp.learn_manual("m_bn1")["reason"]).is_equal("unknown")      # not a power-tree manual
	assert_str(pp.learn_manual("m_bn_fire1")["reason"]).is_equal("not_cultivating")
	assert_str(pp.learn_manual("m_mg_fire3", {"realms": {"magic": 1}})["reason"]).is_equal("too_advanced")
	assert_float(pp.technique_mastery("mg_spark")).is_equal(0.0)
	for i in 20:
		pp.use("magic", 1.0, {"technique": "mg_spark"})
	assert_float(pp.technique_mastery("mg_spark")).is_equal_approx(0.5, 0.0001)


func test_learn_technique_applies_the_requirements() -> void:
	var pp := _pp(["sect"])
	pp.add_teacher("sect_elder")
	var cult_stub := {"realms": {"sect": {"realm": 1, "stage": 3}}}
	assert_bool(pp.learn_technique("st_palm", cult_stub)["ok"]).is_true()
	assert_str(" ".join(PackedStringArray(pp.learn_technique("st_palm", cult_stub)["reasons"]))).contains("Already known")
	assert_bool(pp.learn_technique("st_nine", cult_stub)["ok"]).is_false()
	assert_array(pp.known_techniques()).is_equal(["st_palm"])


func test_power_paths_save_roundtrip_keeps_the_tree_state() -> void:
	var pp := _pp(["magic", "sect"])
	pp.study_theory("magic", 0.3)
	pp.add_milestone("magic", "duel_won")
	pp.choose_subpath("magic", "fire", 1)
	pp.learn_manual("m_st_palm1")
	pp.add_teacher("sect_elder")
	pp.set_primary("sect")
	var d: Dictionary = pp.serialize()
	var back := _pp()
	back.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_str(JSON.stringify(back.serialize())).is_equal(JSON.stringify(d))
	assert_str(back.primary_path()).is_equal("sect")
	assert_float(back.theory("magic")).is_equal_approx(0.3, 0.0001)
	# Old saves without the new keys still load.
	var old: Dictionary = JSON.parse_string(JSON.stringify(d))
	for k: String in ["manuals", "teachers", "known", "primary"]:
		old.erase(k)
	for p: String in old["p"]:
		for k: String in ["theory", "milestones", "subpaths", "uses"]:
			(old["p"][p] as Dictionary).erase(k)
	var legacy := _pp()
	legacy.deserialize(old)
	assert_float(legacy.theory("magic")).is_equal(0.0)
	assert_array(legacy.milestones("magic")).is_empty()


# --- second path -----------------------------------------------------------------------

func test_first_path_is_free_a_second_is_very_hard() -> void:
	var fresh := PowerTrees.empty_profile()
	assert_bool(PowerTrees.second_path_gate(fresh, "magic")["ok"]).is_true()
	var p := _profile("sect", 5, 1, 5, {"level": 8})
	var g := PowerTrees.second_path_gate(p, "magic", "academy")
	assert_bool(g["ok"]).is_false()
	assert_int((g["reasons"] as Array).size()).is_greater_equal(4)           # level, cultivation, character level, trial
	var joined := " ".join(PackedStringArray(g["reasons"]))
	assert_str(joined).contains("level must reach 12")
	assert_str(joined).contains("trial")
	assert_bool(PowerTrees.second_path_gate(p, "sect")["ok"]).is_false()     # already known
	var ready := _profile("sect", 12, 2, 5, {"level": 20, "milestones": {"sect": ["second_path_trial"]}})
	assert_bool(PowerTrees.second_path_gate(ready, "knight", "academy")["ok"]).is_true()
	assert_bool(PowerTrees.second_path_gate(ready, "knight", "self")["ok"]).is_false()     # not self-taught
	assert_bool(PowerTrees.second_path_gate(ready, "knight", "manual")["ok"]).is_false()


func test_a_fourth_path_is_refused() -> void:
	var p := _profile("sect", 14, 3, 1, {"level": 40, "milestones": {"sect": ["second_path_trial"]}})
	p["paths"] = ["sect", "knight", "magic"]
	p["levels"] = {"sect": 14, "knight": 6, "magic": 3}
	assert_bool(PowerTrees.second_path_gate(p, "beast", "teacher")["ok"]).is_false()


func test_additional_paths_pay_a_power_and_cost_penalty() -> void:
	var a := PowerTrees.path_penalty(0)
	var b := PowerTrees.path_penalty(1)
	var c := PowerTrees.path_penalty(2)
	assert_float(a["power"]).is_equal(1.0)
	assert_float(b["power"]).is_less(a["power"])
	assert_float(c["power"]).is_less(b["power"])
	assert_float(b["cost"]).is_greater(a["cost"])
	assert_float(c["xp"]).is_less(b["xp"])
	var pp := _pp(["knight", "magic"])
	pp.set_primary("knight")
	assert_int(pp.path_order("knight")).is_equal(0)
	assert_int(pp.path_order("magic")).is_equal(1)
	var plain: Dictionary = pp.can_use("magic", 4.0, {})
	assert_bool(plain["ok"]).is_true()
	# With the penalty on, the second path is dearer: cost 4 * 1.25 = 5 against a pool of 30 still fits, 30 does not.
	var u_plain: Dictionary = _pp(["magic"]).use("magic", 10.0, {})
	var u_second: Dictionary = pp.use("magic", 10.0, {"path_penalty": true})
	assert_float(u_second["power"]).is_less(u_plain["power"])
	assert_float(u_second["power"]).is_equal_approx(u_plain["power"] * 0.75, 0.0001)
	var tight := _pp(["knight", "magic"])
	tight.set_primary("knight")
	assert_bool(tight.can_use("magic", 28.0, {"path_penalty": true})["ok"]).is_true()    # 35 > 30 + 15 overdraw? 35 <= 45
	assert_bool(tight.can_use("magic", 40.0, {"path_penalty": true})["ok"]).is_false()   # 50 > 45
	assert_bool(tight.can_use("magic", 40.0, {})["ok"]).is_true()


func test_power_paths_can_learn_checks_the_gate_and_the_source() -> void:
	var pp := _pp()
	assert_bool(pp.can_learn("magic", "academy")["ok"]).is_true()
	assert_bool(pp.can_learn("magic", "bribery")["ok"]).is_false()
	assert_bool(pp.learn_checked("sect", "teacher")["ok"]).is_true()
	assert_bool(pp.knows("sect")).is_true()
	var second: Dictionary = pp.learn_checked("knight", "academy")
	assert_bool(second["ok"]).is_false()
	assert_bool(pp.knows("knight")).is_false()
	assert_int((second["reasons"] as Array).size()).is_greater_equal(1)


# --- Skills tab view model and widget --------------------------------------------------------

func test_view_model_lists_every_technique_once_with_state_and_requirements() -> void:
	var p := _profile("sect", 3, 1, 4, {"manuals": ["m_st1"]})
	for path: String in PATHS:
		var v := PowerTrees.view(path, p)
		var n := 0
		for s: Dictionary in v["subpaths"]:
			for t: Dictionary in s["techniques"]:
				n += 1
				assert_bool(t["state"] in ["known", "ready", "locked", "beyond"]).is_true()
				assert_bool((t["reqs"] as Array).is_empty()).is_false()
		assert_int(n).is_equal((PowerTrees.techniques_of(path) as Array).size())
	var sv := PowerTrees.view("sect", p)
	assert_bool(sv["known"]).is_true()
	assert_bool(sv["primary"]).is_true()
	assert_bool(PowerTrees.view("magic", p)["known"]).is_false()
	assert_bool((PowerTrees.view("magic", p)["gate"] as Dictionary).is_empty()).is_false()    # magic shows the chantless gate
	assert_bool((PowerTrees.view("sect", p)["gate"] as Dictionary).is_empty()).is_true()


func test_paths_view_builds_for_a_phone_width_column() -> void:
	var v: Control = auto_free(PathsView.new())
	add_child(v)
	v.size = Vector2(360, 780)                                  # portrait phone
	v.set_profile(_profile("magic", 4, 1, 5, {"manuals": ["m_mg1"], "teachers": ["academy_magister"]}))
	assert_int(v.get_child_count()).is_equal(2)                 # chip row + scroll
	assert_str(v.path).is_equal("magic")
	var blank: Control = auto_free(PathsView.new())
	add_child(blank)
	blank.set_profile(PowerTrees.empty_profile())              # a fresh character still gets a readable first path
	assert_str(blank.path).is_equal("magic")
	var body: Node = v.get("_body")
	assert_int(body.get_child_count()).is_greater_equal(4)      # header, gate, milestones, sub-paths...
	for path: String in PATHS:
		v.show_path(path)
		assert_int(v.get("_body").get_child_count()).is_greater_equal(3)
	var learn_signals := []
	v.learn_requested.connect(func(id: String) -> void: learn_signals.append(id))
	v.show_path("magic")
	var buttons: Array = _find_buttons(v, "Learn")
	assert_int(buttons.size()).is_greater_equal(1)              # ready techniques carry a Learn button
	(buttons[0] as Button).pressed.emit()
	assert_int(learn_signals.size()).is_equal(1)
	await await_idle_frame()                                    # let the cleared cards free


func _find_buttons(node: Node, text: String) -> Array:
	var out: Array = []
	if node is Button and (node as Button).text == text:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_buttons(c, text))
	return out


func test_skills_tab_hosts_the_paths_view_next_to_the_old_sub_tabs() -> void:
	var tab: Control = auto_free(load("res://scripts/ui/gamemenu/tab_skills.gd").new())
	add_child(tab)
	tab.build()
	tab.open_sub("paths")
	assert_bool(tab.get("_paths").visible).is_true()
	assert_bool(tab.get("_ld").visible).is_false()
	assert_int(tab.get("_paths").get("_body").get_child_count()).is_greater_equal(3)
	tab.open_sub("skills")
	assert_bool(tab.get("_paths").visible).is_false()
	assert_bool(tab.get("_ld").visible).is_true()
	var names: Array = []
	for s: Array in tab.SUBS:
		names.append(s[0])
	assert_array(names).contains(["attributes", "skills", "paths", "mastery"])
	await await_idle_frame()
