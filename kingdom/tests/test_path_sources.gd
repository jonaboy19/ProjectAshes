extends GdUnitTestSuite
## Where path knowledge comes from in Region 1, and who fights with it: manuals as items (shops, loot, teachers),
## named teachers at education.gd institutions, reading rules (old script needs glyphs), second-path terms, and NPC
## casters on real humanoid actors (soldier.gd) with spawn mixes and budgets.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const PathTeachers := preload("res://scripts/abilities/path_teachers.gd")
const PathLearning := preload("res://scripts/abilities/path_learning.gd")
const CasterSpawns := preload("res://scripts/combat/caster_spawns.gd")
const NpcCaster := preload("res://scripts/combat/npc_caster.gd")
const PathPatrols := preload("res://scripts/world/path_patrols.gd")
const Education := preload("res://scripts/realm/education.gd")
const Cult := preload("res://scripts/realm/cultivation.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")

const PATHS := ["magic", "bending", "sect", "knight", "beast"]


func _json(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))


func _items() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at("res://data/items"):
		if f.ends_with(".json"):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/" + f))
			if d is Dictionary:
				for k: String in d:
					if String(k).begins_with("pm_") and d[k] is Dictionary:
						out[k] = d[k]
	return out


func _all_power_manuals() -> Dictionary:
	var out := {}
	for p: String in PATHS:
		for m: Dictionary in PowerTrees.manuals_of(p):
			out[String(m["id"])] = m
	for m: Dictionary in Cult.data()["manuals"]:
		out[String(m["id"])] = m
	return out


func _hub_char(path := "magic") -> Dictionary:
	var hub: RefCounted = Hub.new()
	var pp: RefCounted = hub.mod("power_paths")
	var cult: RefCounted = hub.mod("cultivation")
	pp.learn(path, "academy")
	cult.begin(path, "academy")
	return {"hub": hub, "pp": pp, "cult": cult}


# --- manual items ---------------------------------------------------------------------------

func test_every_region_one_manual_is_an_item() -> void:
	var items := _items()
	var n := 0
	for mid: String in _all_power_manuals():
		var m: Dictionary = _all_power_manuals()[mid]
		var iid := "pm_" + mid
		if int(m["realm"]) > 3:
			assert_bool(items.has(iid)).override_failure_message(iid + " is Region 2+").is_false()
			continue
		assert_bool(items.has(iid)).override_failure_message("missing item " + iid).is_true()
		var it: Dictionary = items[iid]
		assert_str(it["type"]).is_equal("path_manual")
		assert_str(it["power_manual"]).is_equal(mid)
		assert_bool(it["power_path"] in PATHS).is_true()
		assert_int(int(it["rarity"])).is_less_equal(3)
		assert_int(int(it["level"])).is_less_equal(60)
		n += 1
	assert_int(n).is_greater_equal(70)
	assert_int(items.size()).is_equal(n)


func test_every_manual_can_be_found_somewhere() -> void:
	var loot: Dictionary = _json("res://data/items/loot.json")["themes"]
	var shops: Dictionary = _json("res://data/items/shops.json")["shops"]
	var in_loot := {}
	var loot_themes := {}
	var shop_ids := {}
	for th: String in loot:
		for t: String in loot[th]["tiers"]:
			for e: Array in loot[th]["tiers"][t]["entries"]:
				if String(e[0]).begins_with("pm_"):
					in_loot[e[0]] = th
					loot_themes[th] = true
	var in_shop := {}
	for sid: String in shops:
		for t: String in shops[sid]["tiers"]:
			for e: Array in shops[sid]["tiers"][t]:
				if String(e[0]).begins_with("pm_"):
					in_shop[e[0]] = sid
					shop_ids[sid] = true
	var teacher_manuals := {}
	for tid: String in PathTeachers.ids():
		for gm: String in PathTeachers.teacher(tid).get("gives", []):
			teacher_manuals[gm] = tid
		for lesson: String in PathTeachers.lessons(tid):
			var req: Dictionary = PowerTrees.technique(lesson)["req"]
			for mid: String in req.get("manual", []):
				teacher_manuals[mid] = tid
	for iid: String in _items():
		var it: Dictionary = _items()[iid]
		var mid := String(it["power_manual"])
		var src := String(it["power_source"])
		var found := in_loot.has(iid) or in_shop.has(iid) or teacher_manuals.has(mid)
		assert_bool(found).override_failure_message("%s (%s) cannot be found anywhere" % [iid, src]).is_true()
		match src:
			"academy", "sect_hall":
				assert_bool(in_shop.has(iid) or in_loot.has(iid)).override_failure_message(iid + " is not sold").is_true()
			"dungeon":
				assert_bool(in_loot.has(iid)).override_failure_message(iid + " does not drop from a dungeon/tower/boss/arcane chest").is_true()
				assert_int(int(it["old_script"])).is_greater_equal(3)         # written in old script
	assert_bool(loot_themes.has("tower") and loot_themes.has("chest_arcane") and loot_themes.has("boss")).is_true()
	assert_bool(loot_themes.has("dungeon_crypt") or loot_themes.has("dungeon_ruin")).is_true()
	var seller := "bookseller"
	assert_bool(shop_ids.has(seller)).is_true()
	assert_bool((shops[seller]["services"] as Array).has("translate_old_script")).is_true()
	var sect_shops := 0
	for v: String in shop_ids:
		if v.begins_with("sect_"):
			sect_shops += 1
	assert_int(sect_shops).is_greater(10)


# --- reading -------------------------------------------------------------------------------

func test_reading_a_power_manual_teaches_it_and_keeps_the_book() -> void:
	var c := _hub_char("magic")
	var info := {"power_manual": "m_mg_fire1", "power_path": "magic", "old_script": 0}
	var r := PathLearning.read_manual(c["pp"], c["cult"], "m_mg_fire1", info)
	assert_bool(r["ok"]).is_true()
	assert_array(c["pp"].manuals()).contains(["m_mg_fire1"])
	assert_bool(PathLearning.read_manual(c["pp"], c["cult"], "m_mg_fire1", info)["ok"]).is_false()   # already known
	var prof: Dictionary = c["pp"].profile({"realms": {"magic": {"realm": 1, "stage": 5}}})
	prof["subpaths"] = {"magic": ["fire"]}
	assert_str(PowerTrees.state("mg_fire_ember", prof)["state"]).is_equal("ready")


func test_reading_a_cultivation_manual_and_wrong_path_refusals() -> void:
	var c := _hub_char("magic")
	assert_bool(PathLearning.read_manual(c["pp"], c["cult"], "m_mg1", {})["ok"]).is_true()
	assert_bool(c["cult"].knows_manual("m_mg1")).is_true()
	assert_bool(c["pp"].profile()["manuals"].has("m_mg1")).is_true()            # the profile merges both lists
	var wrong := PathLearning.read_manual(c["pp"], c["cult"], "m_st_palm1", {})
	assert_bool(wrong["ok"]).is_false()
	assert_str(wrong["text"]).contains("walk no")
	var far := PathLearning.read_manual(c["pp"], c["cult"], "m_mg_fire3", {})
	assert_bool(far["ok"]).is_false()
	assert_str(far["text"]).contains("Too advanced")
	assert_bool(PathLearning.read_manual(c["pp"], c["cult"], "", {})["ok"]).is_false()
	assert_bool(PathLearning.read_manual(null, null, "m_mg1", {})["ok"]).is_false()


func test_old_script_manuals_need_glyphs_and_a_refusal_costs_nothing() -> void:
	var c := _hub_char("magic")
	c["cult"].add_insight(0.0)
	var info := {"power_manual": "m_mg_fire2", "power_path": "magic", "old_script": 3}
	var no := PathLearning.read_manual(c["pp"], c["cult"], "m_mg_fire2", info, {"glyphs": 1})
	assert_bool(no["ok"]).is_false()
	assert_str(no["text"]).contains("old script")
	assert_str(no["text"]).contains("scribe")
	assert_array(c["pp"].manuals()).is_empty()
	var yes := PathLearning.read_manual(c["pp"], c["cult"], "m_mg_fire2", info, {"glyphs": 3})
	assert_bool(yes["ok"]).override_failure_message(str(yes["text"])).is_true()
	assert_array(c["pp"].manuals()).contains(["m_mg_fire2"])


func test_the_equipment_consume_path_routes_to_life_and_keeps_the_book() -> void:
	var eq: RefCounted = load("res://scripts/sim/equipment.gd").new()
	var fake := FakeLife.new()
	var msg: String = eq.consume(fake, "pm_m_mg_fire1")
	assert_str(msg).is_equal("read pm_m_mg_fire1")
	assert_int(fake.takes).is_equal(0)                                         # never spent


class FakeLife extends RefCounted:
	var takes := 0

	func count(_id: String) -> int:
		return 1

	func take(_id: String, _n := 1) -> void:
		takes += 1

	func read_power_manual(id: String, _info: Dictionary) -> Dictionary:
		return {"ok": true, "text": "read " + id}


# --- teachers ------------------------------------------------------------------------------

func test_teacher_data_is_consistent() -> void:
	var kinds: Array = Education.KINDS.keys()
	kinds.append("barracks")
	var referenced := {}
	for p: String in PATHS:
		for t: Dictionary in PowerTrees.techniques_of(p):
			var req: Dictionary = t["req"]
			var ts: Array = req.get("teacher", [])
			for id: String in ts:
				referenced[id] = true
				assert_bool(PathTeachers.teacher(id).is_empty()).override_failure_message("%s names unknown teacher %s" % [t["id"], id]).is_false()
	for id: String in PathTeachers.ids():
		var t: Dictionary = PathTeachers.teacher(id)
		assert_int((t["venues"] as Array).size()).is_greater_equal(1)
		for v: String in t["venues"]:
			assert_bool(v in kinds).override_failure_message("%s venue %s" % [id, v]).is_true()
		assert_bool(t["path"] == "" or t["path"] in PATHS).is_true()
		assert_int((t["names"] as Array).size()).is_greater_equal(2)
		for w: String in t["ways"]:
			assert_bool(w in ["gold", "favour", "quest"]).is_true()
		if t["path"] != "":
			assert_bool(referenced.has(id)).override_failure_message(id + " opens nothing").is_true()
			assert_int(PathTeachers.lessons(id).size()).is_greater_equal(1)
		# every school kind of each path has at least one first teacher
	for path_kind: Array in [["magic_academy", "magic"], ["bending_school", "bending"], ["martial_sect", "sect"], ["knight_academy", "knight"], ["monster_lodge", "beast"]]:
		var any := false
		for id: String in PathTeachers.at_venue(path_kind[0]):
			any = any or PathTeachers.teacher(id)["path"] == path_kind[1]
		assert_bool(any).override_failure_message(path_kind[0]).is_true()


func test_teaching_terms_gold_favour_quest_and_all() -> void:
	assert_bool(PathTeachers.check("sect_elder", {"gold": 99})["ok"]).is_false()
	var g := PathTeachers.check("sect_elder", {"gold": 100})
	assert_bool(g["ok"]).is_true()
	assert_str(g["via"]).is_equal("gold")
	assert_int(g["fee"]).is_equal(100)
	var f := PathTeachers.check("sect_elder", {"gold": 500, "favour": 3})
	assert_str(f["via"]).is_equal("favour")           # free ways come first
	assert_int(f["fee"]).is_equal(0)
	var q := PathTeachers.check("sect_elder", {"quests": ["elder_herb_gathering"]})
	assert_str(q["via"]).is_equal("quest")
	assert_bool(PathTeachers.check("palm_master", {"gold": 9999})["ok"]).is_false()   # does not take coin
	assert_bool(PathTeachers.check("palm_master", {"favour": 4})["ok"]).is_true()
	# The examiner wants all three.
	assert_bool(PathTeachers.check("second_path_examiner", {"gold": 500, "favour": 4})["ok"]).is_false()
	assert_bool(PathTeachers.check("second_path_examiner", {"gold": 500, "favour": 4, "quests": ["second_path_trial_quest"], "path_level": 12})["ok"]).is_true()
	assert_bool(PathTeachers.check("nobody", {})["ok"]).is_false()
	assert_str(" ".join(PackedStringArray(PathTeachers.check("sect_elder", {})["reasons"]))).contains("Needs one of")


func test_learning_from_a_teacher_opens_their_lessons() -> void:
	var c := _hub_char("sect")
	var pp: RefCounted = c["pp"]
	var r := PathTeachers.learn_from("sect_elder", pp, {"gold": 100})
	assert_bool(r["ok"]).is_true()
	assert_int(r["fee"]).is_equal(100)
	assert_array(pp.teachers()).contains(["sect_elder"])
	assert_bool(PathTeachers.learn_from("sect_elder", pp, {"gold": 100})["ok"]).is_false()      # once
	var prof: Dictionary = pp.profile({"realms": {"sect": {"realm": 1, "stage": 3}}})
	assert_str(PowerTrees.state("st_palm", prof)["state"]).is_equal("ready")
	# Too early for the palm master (path level 6).
	var early := PathTeachers.learn_from("palm_master", pp, {"favour": 4})
	assert_bool(early["ok"]).is_false()
	assert_str(early["text"]).contains("level must reach 6")


func test_a_teacher_of_a_new_path_still_meets_the_second_path_gate() -> void:
	var c := _hub_char("sect")
	var pp: RefCounted = c["pp"]
	var r := PathTeachers.learn_from("academy_magister", pp, {"gold": 1000, "favour": 5})
	assert_bool(r["ok"]).is_false()
	assert_bool(pp.knows("magic")).is_false()
	assert_str(r["text"]).contains("level must reach")
	# A first path is taken on freely when the character has none.
	var fresh: RefCounted = Hub.new().mod("power_paths")
	var ok := PathTeachers.learn_from("drill_sergeant", fresh, {"gold": 60})
	assert_bool(ok["ok"]).is_true()
	assert_bool(fresh.knows("knight")).is_true()
	assert_array(fresh.teachers()).contains(["drill_sergeant"])


func test_the_examiner_grants_the_second_path_trial() -> void:
	var c := _hub_char("sect")
	var pp: RefCounted = c["pp"]
	pp.gain_xp("sect", 12.0 * 50.0 / pp.xp_multiplier("sect") + 1.0)
	assert_int(pp.level("sect")).is_greater_equal(12)
	var r := PathTeachers.learn_from("second_path_examiner", pp, {"gold": 500, "favour": 4, "quests": ["second_path_trial_quest"]})
	assert_bool(r["ok"]).override_failure_message(str(r["text"])).is_true()
	assert_array(pp.milestones("sect")).contains(["second_path_trial"])
	assert_int(r["fee"]).is_equal(500)


func test_education_seats_named_teachers_and_charges_through_the_ledger() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var edu: RefCounted = hub.mod("education")
	edu.set_player({"home_sid": 5, "sid": 5, "age": 20, "gold": 300})
	edu._ensure()
	var sect_inst := ""
	var knight_inst := ""
	for i: Dictionary in edu.institutions():
		if i["kind"] == "martial_sect" and not i["minor"] and sect_inst == "":
			sect_inst = i["id"]
		if i["kind"] == "knight_academy" and not i["minor"] and knight_inst == "":
			knight_inst = i["id"]
	assert_str(sect_inst).is_not_equal("")
	var roster: Array = edu.path_teachers(sect_inst)
	var ids: Array = []
	for p: Dictionary in roster:
		ids.append(p["id"])
		assert_str(p["name"]).is_not_equal("")
		if p["path"] != "":
			assert_array(p["lessons"]).is_not_empty()
	assert_array(ids).contains(["sect_elder", "palm_master"])
	assert_str(edu.path_teachers(sect_inst)[0]["name"]).is_equal(roster[0]["name"])        # stable names
	assert_array(edu.path_teachers(knight_inst).map(func(p: Dictionary) -> String: return p["id"])).contains(["drill_sergeant", "knight_captain"])
	# The path must exist for a teacher to teach a lesson; a newcomer is taken on as a first path.
	var r: Dictionary = edu.learn_from_path_teacher(sect_inst, "sect_elder", {})
	assert_bool(r["ok"]).override_failure_message(str(r["text"])).is_true()
	assert_int(edu.take_pending_gold()).is_equal(-100)
	assert_bool(hub.mod("power_paths").knows("sect")).is_true()
	assert_bool(edu.learn_from_path_teacher(sect_inst, "drill_sergeant", {})["ok"]).is_false()   # not seated here
	assert_bool(edu.path_teachers(sect_inst).filter(func(p: Dictionary) -> bool: return p["id"] == "sect_elder")[0]["taught"]).is_true()
	# A student of the school has standing there.
	assert_float(edu.path_favour(sect_inst, 1.0)).is_equal(1.0)


# --- spawn mixes and budgets -----------------------------------------------------------------

func test_spawn_mixes_only_name_real_casters_and_respect_caps() -> void:
	for ctx: String in CasterSpawns.contexts():
		for id: String in CasterSpawns.contexts()[ctx]:
			assert_bool(NpcCaster.has(id)).override_failure_message("%s names %s" % [ctx, id]).is_true()
	assert_array(CasterSpawns.mix("bandit_camp", 3, 1)).is_empty()                     # too small a band
	var camp := CasterSpawns.mix("bandit_camp", 12, 4)
	assert_bool(camp.size() <= 2).is_true()
	for id: String in camp:
		assert_str(id).is_equal("bandit_mage")
	assert_array(CasterSpawns.mix("garrison", 8, 3)).is_equal(["knight_captain"])        # exactly one captain
	assert_array(CasterSpawns.mix("garrison", 4, 3)).is_empty()
	assert_array(CasterSpawns.mix("nothing", 9, 1)).is_empty()
	assert_array(CasterSpawns.mix("sect_patrol", 3, 1)).is_equal(["sect_disciple", "sect_disciple", "sect_disciple"])
	assert_array(CasterSpawns.mix("sect_patrol", 2, 1)).has_size(2)                    # never longer than the squad
	# Deterministic, and the chance really bites.
	assert_array(CasterSpawns.mix("road_ambush", 6, 77)).is_equal(CasterSpawns.mix("road_ambush", 6, 77))
	var with := 0
	for i in 200:
		if not CasterSpawns.mix("road_ambush", 6, i).is_empty():
			with += 1
	assert_int(with).is_between(60, 130)                                                # chance 0.45


func test_active_caster_budget() -> void:
	var before := NpcCaster.active
	var got := 0
	for i in NpcCaster.MAX_ACTIVE + 3:
		if NpcCaster.try_acquire():
			got += 1
	assert_int(got).is_equal(NpcCaster.MAX_ACTIVE - before)
	assert_int(NpcCaster.active).is_equal(NpcCaster.MAX_ACTIVE)
	assert_bool(NpcCaster.try_acquire()).is_false()
	for i in got:
		NpcCaster.release()
	assert_int(NpcCaster.active).is_equal(before)
	NpcCaster.release()
	assert_int(NpcCaster.active).is_greater_equal(0)


func test_patrol_plan_from_institutions() -> void:
	var settlements := [{"pos": Vector2(100, 100)}, {"pos": Vector2(400, 100)}, {"pos": Vector2(0, 400)}]
	var insts := [
		{"id": "a", "kind": "martial_sect", "sid": 0, "minor": false, "hidden": false, "name": "Azure Peak Sect"},
		{"id": "b", "kind": "martial_sect", "sid": 1, "minor": true, "hidden": false, "name": "Sect Hall of X"},
		{"id": "c", "kind": "knight_academy", "sid": 2, "minor": false, "hidden": false, "name": "Ironvale"},
		{"id": "d", "kind": "knight_academy", "sid": 1, "minor": true, "hidden": false, "name": "Minor Knights"},
		{"id": "e", "kind": "magic_academy", "sid": 0, "minor": false, "hidden": false, "name": "Mages"},
		{"id": "f", "kind": "martial_sect", "sid": 9, "minor": false, "hidden": false, "name": "Lost"},
		{"id": "g", "kind": "martial_sect", "sid": 0, "minor": false, "hidden": true, "name": "Hidden"}]
	var plan := PathPatrols.plan(insts, settlements)
	var by := {}
	for e: Dictionary in plan:
		by[e["id"]] = e
	assert_array(by.keys()).is_equal(["a", "b", "c"])
	assert_int(by["a"]["n"]).is_equal(3)
	assert_int(by["b"]["n"]).is_equal(2)
	assert_str(by["a"]["context"]).is_equal("sect_patrol")
	assert_str(by["c"]["context"]).is_equal("knight_patrol")
	assert_int(by["c"]["n"]).is_equal(4)
	assert_bool((by["a"]["pos"] as Vector2).distance_to(Vector2(100, 100)) < 20.0).is_true()
	assert_int(PathPatrols.MAX_PATROLS).is_less_equal(3)
	assert_int(CasterSpawns.mix("knight_patrol", 4, 1).size()).is_equal(1)


# --- the actor ------------------------------------------------------------------------------

class StubFoe extends Node3D:
	var dead := false
	var hits: Array = []
	var statuses: Array = []

	func take_damage(amount: int, _from: Node = null, _k := Vector3.ZERO) -> void:
		hits.append(amount)

	func apply_status(s: String, d: float) -> void:
		statuses.append([s, d])


func _soldier(cid: String, team := 1) -> Node:
	var keep: Array[String] = ["1H_Axe"]
	var s: Node = load("res://scripts/army/soldier.gd").create(team, "raider", "Barbarian", keep)
	s.caster_id = cid
	add_child(s)
	auto_free(s)
	return s


func test_a_soldier_with_a_caster_id_becomes_a_caster_within_budget() -> void:
	NpcCaster.active = 0
	var before := NpcCaster.active
	var mage := _soldier("bandit_mage")
	assert_str(mage.caster_id).is_equal("bandit_mage")
	assert_bool(mage.is_in_group("caster")).is_true()
	assert_int(NpcCaster.active).is_equal(before + 1)
	assert_str(mage._fighter.archetype).is_equal("bandit")          # the mage's body is a bandit's
	var plain := _soldier("")
	assert_bool(plain.is_in_group("caster")).is_false()
	var cap: Array = []
	while NpcCaster.active < NpcCaster.MAX_ACTIVE:
		cap.append(_soldier("sect_disciple", 0))
	var over := _soldier("knight_captain", 0)
	assert_str(over.caster_id).is_equal("")                         # over the cap: a plain fighter
	assert_bool(over.is_in_group("caster")).is_false()
	for s: Node in cap + [mage]:
		s.queue_free()
	await await_idle_frame()
	assert_int(NpcCaster.active).is_less_equal(before + 1)          # freed casters give their slots back


func test_a_caster_soldier_hits_with_its_ability_and_wards_soak_blows() -> void:
	NpcCaster.active = 0
	var mage := _soldier("bandit_mage")
	var foe := StubFoe.new()
	add_child(foe)
	auto_free(foe)
	foe.global_position = Vector3(0, 0, -3)
	var ab := AbilityLib.get_def("mg_spark_chain")                  # an instant-range ability, no chant in the way
	mage._on_cast_executed("mg_spark_chain", ab, {"target": foe, "damage": int(ab["damage"]), "power": 1.0})
	assert_int(foe.hits.size()).is_equal(1)
	assert_int(foe.hits[0]).is_equal(int(round(float(ab["damage"]) * float(mage._caster.row["dmg_mult"]) * float(mage.damage) / mage.BASE_DAMAGE)))
	assert_array(foe.statuses).is_equal([["stun", 0.2]])
	# A ward cast on itself soaks the next blow completely, then is spent.
	var ward := AbilityLib.get_def("mg_ward")
	mage._on_cast_executed("mg_ward", ward, {"target": foe, "damage": 0, "power": 1.0})
	assert_bool(mage._caster.effects().has("ward")).is_true()
	var hp: int = mage.health
	mage.take_damage(20, foe)
	assert_int(mage.health).is_equal(hp)
	mage.take_damage(20, foe)
	assert_int(mage.health).is_less(hp)
	# A big blow while chanting breaks the chant.
	mage._caster.cast("mg_spark", foe)
	assert_bool(mage._caster.is_casting()).is_true()
	mage._busy = 0.0
	mage.take_damage(12, foe)
	assert_bool(mage._caster.is_casting()).is_false()
