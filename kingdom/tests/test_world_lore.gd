extends GdUnitTestSuite
## World lore data (races, cultures, nations, sects, tribes, first region) and
## the military rank ladder.

const STANCES := ["allied", "friendly", "neutral", "wary", "hostile", "war"]


func _lore() -> RAWorldLore:
	return RAWorldLore.new()


func test_all_world_json_parses() -> void:
	for f: String in RAWorldLore.FILES:
		var path := "%s/%s.json" % [RAWorldLore.DATA_DIR, f]
		assert_bool(FileAccess.file_exists(path)).override_failure_message("missing " + path).is_true()
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(path))
		assert_int(err).override_failure_message("%s: %s" % [f, json.get_error_message()]).is_equal(OK)
	var lore := _lore()
	assert_dict(lore.errors).is_empty()
	assert_int(lore.races.size()).is_greater_equal(7)
	assert_int(lore.cultures.size()).is_between(6, 8)
	assert_int(lore.nations.size()).is_greater_equal(7)
	assert_int(lore.sects.size()).is_greater_equal(6)


func test_races_cover_the_peoples_and_evolve() -> void:
	var lore := _lore()
	for id: String in ["human", "orc", "goblin", "beastkin", "veyl", "durrow", "drakari"]:
		var r := lore.race(id)
		assert_dict(r).override_failure_message("missing race " + id).is_not_empty()
		for key: String in ["lifespan", "traits", "magicule_affinity", "civilised", "monster", "evolution", "transformation"]:
			assert_bool(r.has(key)).override_failure_message("%s lacks %s" % [id, key]).is_true()
		var aff: float = r["magicule_affinity"]
		assert_float(aff).is_between(0.0, 1.0)
	# Goblin -> hobgoblin is the first step, and every step chains from the race.
	var gob: Array = lore.evolutions("goblin")
	assert_str(str(gob[0]["to"])).is_equal("hobgoblin")
	for id: String in lore.races:
		var forms := {id: true}
		for step: Dictionary in lore.evolutions(id):
			assert_bool(forms.has(step["from"])).override_failure_message("%s: %s not reachable" % [id, step["from"]]).is_true()
			forms[step["to"]] = true
		var t: Dictionary = lore.race(id)["transformation"]
		for src: Variant in t.get("from", []):
			assert_dict(lore.race(str(src))).is_not_empty()
	assert_array(lore.transformations_from("human")).contains(["drakari", "orc", "beastkin"])
	assert_bool(lore.race("goblin")["civilised"]).is_false()


func test_referential_integrity() -> void:
	var lore := _lore()
	for id: String in lore.cultures:
		var c := lore.culture(id)
		assert_dict(lore.race(c["race"])).override_failure_message("culture %s race" % id).is_not_empty()
		for key: String in ["element", "first_names", "family_names", "architecture", "clothing_palette", "values", "food", "festivals", "greeting"]:
			assert_bool(c.has(key)).override_failure_message("%s lacks %s" % [id, key]).is_true()
	for id: String in lore.nations:
		var n := lore.nation(id)
		assert_dict(lore.culture(n["culture"])).override_failure_message("nation %s culture" % id).is_not_empty()
		for mc: Variant in n.get("minority_cultures", []):
			assert_dict(lore.culture(str(mc))).is_not_empty()
		assert_array(n["cities"]).override_failure_message("%s capital not a city" % id).contains([n["capital"]])
		assert_array(n["villages"]).is_not_empty()
		for div: Variant in n["military_divisions"]:
			assert_bool(RAMilitary.SPECIAL_DIVISIONS.has(div)).override_failure_message("unknown division %s" % div).is_true()
			assert_str(str(RAMilitary.SPECIAL_DIVISIONS[div]["nation"])).is_equal(id)
		var rel: Dictionary = n["relations"]
		for other: String in lore.nations:
			if other == id:
				continue
			assert_bool(rel.has(other)).override_failure_message("%s has no stance on %s" % [id, other]).is_true()
			assert_array(STANCES).contains([rel[other]])
			# Relations are mutual.
			assert_str(lore.stance(other, id)).override_failure_message("%s/%s asymmetric" % [id, other]).is_equal(rel[other])
	for id: String in lore.sects:
		var s := lore.sect(id)
		var n := lore.nation(s["nation"])
		assert_dict(n).override_failure_message("sect %s nation" % id).is_not_empty()
		var towns: Array = n["cities"] + n["villages"]
		assert_array(towns).override_failure_message("sect %s location" % id).contains([s["location"]])
		assert_array(s["ranks"]).is_not_empty()
		for r: Variant in s["entry_requirements"].get("races", []):
			assert_dict(lore.race(str(r))).is_not_empty()
	for id: String in lore.tribes:
		var t := lore.tribe(id)
		assert_dict(lore.race(t["race"])).is_not_empty()
		if t["culture"] != null:
			assert_dict(lore.culture(t["culture"])).is_not_empty()
		if t["nation"] != null:
			assert_dict(lore.nation(t["nation"])).is_not_empty()
		assert_dict(lore.nation(t["territory"])).is_not_empty()
		if t["home"] != null:
			assert_dict(lore.place(t["home"])).override_failure_message("tribe %s home" % id).is_not_empty()
	var rarities: Dictionary = lore.files["tribes_bloodlines"]["rarities"]
	for id: String in lore.bloodlines:
		var b := lore.bloodline(id)
		assert_bool(rarities.has(b["rarity"])).is_true()
		assert_array(b["dormant_traits"]).is_not_empty()
		for r: Variant in b["races"]:
			assert_dict(lore.race(str(r))).is_not_empty()
		for c: Variant in b["cultures"]:
			assert_dict(lore.culture(str(c))).is_not_empty()
	# The home kingdom is WorldGen's world: every WorldGen settlement belongs to it.
	var cal := lore.nation("caldrenn")
	var cal_towns: Array = cal["cities"] + cal["villages"]
	for town: String in WorldGen.NAMES:
		assert_array(cal_towns).contains([town])


func test_random_names_follow_culture() -> void:
	var lore := _lore()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id: String in lore.cultures:
		var c := lore.culture(id)
		for i in 10:
			var n := lore.random_name(id, rng)
			assert_str(n).is_not_empty()
			var family_first: bool = c.get("name_order", "") == "family_first"
			var matched := false
			for fam: String in c["family_names"]:
				if (family_first and n.begins_with(fam + " ")) or (not family_first and n.ends_with(" " + fam)):
					matched = true
			assert_bool(matched).override_failure_message("%s: %s" % [id, n]).is_true()
	assert_str(lore.random_name("nope", rng)).is_empty()


func test_xiava_access_is_rare() -> void:
	var lore := _lore()
	var access := lore.sects_with_xiava_access()
	assert_array(access).contains(["royal_ember_academy"])
	assert_int(access.size()).is_between(2, 3)
	assert_int(access.size() * 3).is_less_equal(lore.sects.size())
	var sect_count := 0
	for id: String in access:
		if lore.sect(id)["type"] == "sect":
			sect_count += 1
	assert_int(sect_count).is_between(1, 2)


func test_first_region_layout() -> void:
	var lore := _lore()
	var ps := lore.places_in_region()
	assert_int(ps.size()).is_greater_equal(10)
	for p: Dictionary in ps:
		var pos: Vector2 = p["pos"]
		assert_bool(absf(pos.x) <= WorldGen.WORLD_HALF and absf(pos.y) <= WorldGen.WORLD_HALF).override_failure_message(p["id"]).is_true()
	for kind: String in ["village", "lake", "river", "forest", "orc_village", "goblin_warren", "ruined_shrine", "waystation", "road"]:
		assert_array(lore.places_in_region(kind)).override_failure_message("no " + kind).is_not_empty()
	var ashford: Vector2 = lore.place("ashford")["pos"]
	assert_vector(ashford).is_equal(Vector2.ZERO)
	var lake: Vector2 = lore.places_in_region("lake")[0]["pos"]
	assert_float(lake.length()).is_between(300.0, 700.0)
	var orc: Dictionary = lore.places_in_region("orc_village")[0]
	assert_float((orc["pos"] as Vector2).length()).is_greater_equal(900.0)
	assert_str(str(orc["chief"]["name"])).is_not_empty()
	# The capital matches WorldGen's fixed castle position.
	assert_vector(lore.place("kingsreach")["pos"]).is_equal(Vector2(560, -420))
	var road: Dictionary = lore.places_in_region("road")[0]
	var path: PackedVector2Array = road["path"]
	assert_vector(path[0]).is_equal(ashford)
	assert_vector(path[path.size() - 1]).is_equal(Vector2(560, -420))
	var river: PackedVector2Array = lore.places_in_region("river")[0]["path"]
	assert_int(river.size()).is_greater_equal(4)


func test_military_ladder_is_monotonic() -> void:
	var ranks := RAMilitary.RANKS
	assert_int(ranks.size()).is_greater_equal(12)
	for i in range(1, ranks.size()):
		var a: Dictionary = ranks[i - 1]
		var b: Dictionary = ranks[i]
		assert_int(int(b["merit"])).override_failure_message("merit at " + str(b["id"])).is_greater(int(a["merit"]))
		assert_int(int(b["pay"])).override_failure_message("pay at " + str(b["id"])).is_greater(int(a["pay"]))
		assert_int(int(b["command"])).is_greater_equal(int(a["command"]))
		assert_int(RAMilitary.pay(b["id"])).is_greater(RAMilitary.pay(a["id"]))
		assert_int(RAMilitary.command_size(b["id"])).is_greater_equal(RAMilitary.command_size(a["id"]))
	# Balanced against the guard career: guard 9, sergeant 18, captain 30.
	assert_int(RAMilitary.pay("soldier")).is_equal(9)
	assert_int(RAMilitary.pay("banner_sergeant")).is_equal(18)
	assert_int(RAMilitary.pay("captain")).is_equal(30)
	# Every unit's leader commands at least that unit.
	for u: Dictionary in RAMilitary.UNITS:
		assert_int(RAMilitary.command_size(u["leader"])).is_greater_equal(int(u["size"]))
	# rank_for_merit never goes down as merit rises.
	var last := -1
	for m in range(0, 7000, 25):
		var idx := RAMilitary.rank_index(RAMilitary.rank_for_merit(m)["id"])
		assert_int(idx).is_greater_equal(last)
		last = idx
	assert_str(str(RAMilitary.rank_for_merit(0)["id"])).is_equal("recruit")
	assert_str(str(RAMilitary.rank_for_merit(400)["id"])).is_equal("captain")
	assert_str(str(RAMilitary.next_rank("captain")["id"])).is_equal("battalion_second")
	assert_dict(RAMilitary.next_rank("grand_marshal")).is_empty()


func test_nation_overrides_and_divisions() -> void:
	assert_str(RAMilitary.title("captain", "seirune_isles")).is_equal("House Captain")
	assert_str(RAMilitary.title("captain", "caldrenn")).is_equal("Captain of a Hundred")
	assert_int(RAMilitary.pay("captain", "urrokai_clanlands")).is_less(RAMilitary.pay("captain", "caldrenn"))
	for n: String in RAMilitary.NATION_OVERRIDES:
		for r in range(1, RAMilitary.RANKS.size()):
			assert_int(RAMilitary.pay(RAMilitary.RANKS[r]["id"], n)).is_greater_equal(RAMilitary.pay(RAMilitary.RANKS[r - 1]["id"], n))
	var lantern := {"rank": "soldier", "merit": 150, "nation": "seirune_isles", "sects": [], "skills": {"stealth": 50}}
	assert_str(RAMilitary.check_division("veiled_lantern_corps", lantern)).contains("hollow_moon_school")
	lantern["sects"] = ["hollow_moon_school"]
	assert_str(RAMilitary.check_division("veiled_lantern_corps", lantern)).is_empty()
	lantern["nation"] = "caldrenn"
	assert_str(RAMilitary.check_division("veiled_lantern_corps", lantern)).is_not_empty()
	var orc := {"rank": "soldier", "merit": 100, "nation": "urrokai_clanlands", "race": "human", "skills": {"axe": 40}}
	assert_str(RAMilitary.check_division("bloodtusk_berserkers", orc)).contains("orc")
	assert_int(RAMilitary.pay("soldier", "caldrenn", "royal_soulbeast_riders")).is_equal(9 + 25)


func test_formation_tree_sums_to_troop_count() -> void:
	for n: int in [1, 4, 5, 7, 10, 37, 50, 99, 100, 101, 430, 999, 4700, 12500, 12501, 30000]:
		var f := RAMilitary.build_formation(n)
		assert_int(int(f["troops"])).is_equal(n)
		assert_int(RAMilitary.formation_troops(f)).override_failure_message("n=%d" % n).is_equal(n)
		_check_node(f)
	var company := RAMilitary.build_formation(100)
	assert_str(str(company["unit"])).is_equal("hundred")
	assert_dict(RAMilitary.formation_counts(company)).is_equal({"hundred": 1, "fifty": 2, "ten": 10, "five": 20})
	assert_str(str(RAMilitary.build_formation(4700)["unit"])).is_equal("army")
	assert_str(str(RAMilitary.build_formation(430)["unit"])).is_equal("battalion")
	assert_str(str(RAMilitary.build_formation(30000)["unit"])).is_equal("host")
	assert_str(str(RAMilitary.build_formation(100, "ongur_khanate")["leader_title"])).is_equal("Hundred-Khanling")


func _check_node(node: Dictionary) -> void:
	var kids: Array = node["children"]
	if kids.is_empty():
		assert_int(int(node["troops"])).is_between(1, 5)
		return
	var total := 0
	for c: Dictionary in kids:
		total += int(c["troops"])
		_check_node(c)
	assert_int(total).is_equal(int(node["troops"]))


func test_roster_promotion_and_roundtrip() -> void:
	var m := RAMilitary.new("caldrenn")
	m.enlist(7)
	assert_int(m.daily_pay(7)).is_equal(7)
	var eligible := m.add_merit(7, 30)
	assert_str(str(eligible["id"])).is_equal("soldier")
	assert_bool(m.eligible_for_promotion(7)).is_true()
	assert_str(m.promote(7)).is_empty()
	assert_str(m.promote(7)).contains("merit")
	assert_int(m.daily_pay(7)).is_equal(9)
	m.add_merit(7, 20)
	assert_str(m.join_division(7, "runeward_legion", {"skills": {"runecraft": 12}})).is_empty()
	var data: Variant = JSON.parse_string(JSON.stringify(m.serialize()))
	var m2 := RAMilitary.new("ongur_khanate")
	m2.deserialize(data)
	assert_str(m2.home_nation).is_equal("caldrenn")
	assert_str(str(m2.members[7]["rank"])).is_equal("soldier")
	assert_int(int(m2.members[7]["merit"])).is_equal(50)
	assert_int(m2.daily_pay(7)).is_equal(12)
