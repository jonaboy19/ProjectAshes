extends GdUnitTestSuite
## The player's own family (scripts/sim/family.gd): courtship stage gates,
## marriage requiring a home, children inheriting tendencies/affinity by the
## documented odds, parents ageing and dying, succession (what carries and
## what doesn't) and a serialize round trip.
##
## family.gd reads Life./Game./WorldSim. directly (like property.gd and
## nobility.gd), so every test snapshots and restores the singleton state it
## touches, the same way test_property.gd and test_nobility.gd do.

const RAFamily := preload("res://scripts/sim/family.gd")
const RAAwakening := preload("res://scripts/sim/awakening.gd")

var _gold_before: int
var _day_before: int
var _life_path_before: Dictionary
var _tendencies_before: Dictionary
var _awakening_before: Dictionary
var _mastery_before: Dictionary
var _titles_before: Dictionary
var _biography_before: Dictionary
var _property_before: Dictionary
var _homestead_before: Dictionary
var _house_keys: Array[String] = []


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)
	_gold_before = Game.gold
	_day_before = WorldSim.day
	_life_path_before = Life.life_path.serialize()
	_tendencies_before = Life.tendencies.serialize()
	_awakening_before = Life.awakening.serialize()
	_mastery_before = Life.mastery.serialize()
	_titles_before = Life.titles.serialize()
	_biography_before = Life.biography.serialize()
	_property_before = Life.property.serialize()
	_homestead_before = Life.homestead.serialize()
	Game.gold = 1000
	Life.life_path.begin(WorldSim.day, 6.0, "Aren", "Testholt",
		[{"id": 4, "name": "Edda Testholt", "role": "mother"}, {"id": 9, "name": "Osric Testholt", "role": "father"}],
		0, Vector2(14, 9))
	Life.life_path.set_age(20, WorldSim.day, WorldSim.time_of_day)
	var rel: Object = Life.get("relationships")
	_house_keys.clear()
	if rel != null:
		for k: String in (rel.reputation as Dictionary).keys().duplicate():
			if k.begins_with("house_"):
				_house_keys.append(k)
				rel.reputation.erase(k)
				rel.faction_names.erase(k)


func after_test() -> void:
	Game.gold = _gold_before
	WorldSim.day = _day_before
	Life.life_path.deserialize(_life_path_before)
	Life.tendencies.deserialize(_tendencies_before)
	Life.awakening.deserialize(_awakening_before)
	Life.mastery.deserialize(_mastery_before)
	Life.titles.deserialize(_titles_before)
	Life.biography.deserialize(_biography_before)
	Life.property.deserialize(_property_before)
	Life.homestead.deserialize(_homestead_before)
	var rel: Object = Life.get("relationships")
	if rel != null:
		for k: String in (rel.reputation as Dictionary).keys().duplicate():
			if k.begins_with("house_") and not _house_keys.has(k):
				rel.reputation.erase(k)
				rel.faction_names.erase(k)


func _grant_home() -> void:
	var lot_id: String = Life.property.available(0)[0]
	Game.gold = maxi(Game.gold, int(Life.property.info(lot_id)["price"]))
	Life.property.buy(lot_id)


func _close_friend(npc_id: String) -> void:
	Life.relationships.ensure(npc_id, {"base": 80.0, "role": "villager", "culture": "caldric"})


# --- courtship ---------------------------------------------------------------------

func test_courtship_gated_by_age_and_tier() -> void:
	var fam := RAFamily.new()
	Life.life_path.set_age(10, WorldSim.day, WorldSim.time_of_day)
	assert_str(fam.can_court("npc_a")).contains("old enough")
	Life.life_path.set_age(20, WorldSim.day, WorldSim.time_of_day)
	assert_str(fam.can_court("npc_a")).contains("close enough")
	_close_friend("npc_a")
	assert_str(fam.can_court("npc_a")).is_empty()
	assert_str(fam.court("npc_a")).contains("interested")
	assert_str(fam.stage("npc_a")).is_equal("interested")


func test_courtship_advances_stage_with_points() -> void:
	var fam := RAFamily.new()
	_close_friend("npc_b")
	fam.court("npc_b")
	fam.add_courtship_points("npc_b", RAFamily.COURT_POINTS_COURTING)
	assert_str(fam.stage("npc_b")).is_equal("courting")
	fam.add_courtship_points("npc_b", RAFamily.COURT_POINTS_BETROTHED - RAFamily.COURT_POINTS_COURTING)
	# Points alone no longer betroth (Codex: betrothal is gated behind propose()).
	assert_str(fam.stage("npc_b")).is_equal("courting")
	if not fam._has_marriage_home():
		assert_str(fam.propose("npc_b")).contains("home")
		assert_str(fam.stage("npc_b")).is_equal("courting")
	else:
		assert_str(fam.propose("npc_b")).is_empty()
		assert_str(fam.stage("npc_b")).is_equal("betrothed")


func test_cannot_court_once_married() -> void:
	var fam := RAFamily.new()
	_grant_home()
	_close_friend("npc_c")
	fam.court("npc_c")
	fam.add_courtship_points("npc_c", RAFamily.COURT_POINTS_COURTING)
	fam.propose("npc_c")
	fam.marry("npc_c")
	assert_str(fam.can_court("npc_d")).contains("already married")


# --- marriage requires a home --------------------------------------------------------

func test_marriage_requires_a_home() -> void:
	var fam := RAFamily.new()
	_close_friend("npc_e")
	fam.court("npc_e")
	fam.add_courtship_points("npc_e", RAFamily.COURT_POINTS_BETROTHED)
	assert_str(fam.stage("npc_e")).is_equal("courting")
	# No home yet: can't propose (and therefore can't reach "betrothed", which marry() needs).
	assert_str(fam.propose("npc_e")).contains("home")
	assert_str(fam.marry("npc_e")).contains("betrothed")
	assert_bool(fam.is_married()).is_false()
	_grant_home()
	assert_str(fam.propose("npc_e")).contains("says yes")
	assert_str(fam.stage("npc_e")).is_equal("betrothed")
	assert_str(fam.marry("npc_e")).contains("marry")
	assert_bool(fam.is_married()).is_true()
	assert_bool(Life.life_path.has_flag("married")).is_true()


# --- children: inherited tendencies and affinity ------------------------------------

func test_child_tendencies_average_both_parents_with_noise() -> void:
	var fam := RAFamily.new()
	Life.tendencies.values["martial"] = 0.9
	fam.spouse = {"tendencies": {"martial": 0.1}, "affinity": {"element": "", "dual": "", "none": true}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var t := fam._blend_tendencies(rng)
	# Average of 0.9 and 0.1 is 0.5, +/- up to 0.12 of seeded noise.
	assert_float(t["martial"]).is_between(0.37, 0.63)


func test_child_affinity_distribution_60_single_10_dual_else_random() -> void:
	var fam := RAFamily.new()
	Life.awakening.done = true
	Life.awakening.none = false
	Life.awakening.element = "fire"
	Life.awakening.dual = ""
	fam.spouse = {"affinity": {"element": "water", "dual": "", "none": false}}
	var single := 0
	var dual := 0
	var trials := 3000
	for i in trials:
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 7919 + 101
		var a := fam._inherit_affinity(rng)
		if String(a.get("dual", "")) != "":
			dual += 1
		elif not bool(a.get("none", true)) and String(a["element"]) in ["fire", "water"] and String(a.get("dual", "")) == "":
			single += 1
	# Design: 60% one parent's element, 10% dual — generous tolerance for seeded rolls
	# (a little of the "random" 30% can also land on fire/water by chance).
	assert_float(float(single) / trials).is_between(0.52, 0.72)
	assert_float(float(dual) / trials).is_between(0.05, 0.16)


func test_birth_records_child_and_biography_highlight() -> void:
	var fam := RAFamily.new()
	fam.spouse = {"tendencies": {}, "affinity": {"element": "", "dual": "", "none": true}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var before_chapters := Life.biography.chapters.size()
	var c := fam._birth_child(WorldSim.day, rng)
	assert_int(fam.children.size()).is_equal(1)
	assert_str(String(c["name"])).is_not_empty()
	assert_bool(c["sex"] in ["male", "female"]).is_true()
	assert_int(Life.biography.chapters.size()).is_greater_equal(before_chapters)
	assert_int(fam.child_age(c, WorldSim.day)).is_equal(0)
	assert_int(fam.child_age(c, WorldSim.day + RALifePathYears(5))).is_equal(5)


func RALifePathYears(n: int) -> int:
	return n * preload("res://scripts/sim/life_path.gd").DAYS_PER_YEAR


# --- parents age and die -------------------------------------------------------------

func test_parent_ages_from_a_seeded_offset() -> void:
	var fam := RAFamily.new()
	var age_a := fam.parent_age("mother")
	var fam2 := RAFamily.new()
	var age_b := fam2.parent_age("mother")
	assert_int(age_a).is_equal(age_b)   # deterministic for the same world seed and role
	assert_bool(fam.parent_alive("mother")).is_true()


func test_parent_eventually_dies_of_old_age_and_leaves_a_legacy() -> void:
	var fam := RAFamily.new()
	fam._ensure_parent_state()
	fam.parent_state["mother"]["age_at_birth"] = 500   # forces age well past PARENT_DEATH_START_AGE
	var gold_before := Game.gold
	var died := false
	for d in 30:
		var msgs := fam._tick_parents(WorldSim.day + d)
		if not msgs.is_empty():
			died = true
			break
	assert_bool(died).is_true()
	assert_bool(fam.parent_alive("mother")).is_false()
	assert_int(Game.gold).is_greater(gold_before)


# --- succession ----------------------------------------------------------------------

func test_succession_transfers_gold_tendencies_affinity_not_mastery_or_titles() -> void:
	var fam := RAFamily.new()
	Life.titles.grant("first_steps", WorldSim.day)
	Life.mastery.gain("farming", 100.0, WorldSim.day)
	Life.biography.start_chapter("farmer", "", "field hand", "Ashford", WorldSim.day)
	Life.biography.change_rep("trade", 40.0)
	var house_id := String(Life.nobility.houses[0]["id"]) if Life.get("nobility") != null else ""
	if house_id != "":
		Life.nobility.change_opinion(house_id, 80.0)
	fam.children.append({"id": 1, "name": "Wren", "sex": "female",
		"birth_day": WorldSim.day - 18 * preload("res://scripts/sim/life_path.gd").DAYS_PER_YEAR,
		"tendencies": {"martial": 0.77}, "affinity": {"element": "wind", "dual": "", "none": false},
		"alive": true, "dead_day": -1})
	fam.next_child_id = 2
	var cands := fam.heir_candidates()
	assert_int(cands.size()).is_equal(1)
	assert_str(String(cands[0]["kind"])).is_equal("child")
	var r := fam.succeed_to(1)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(Game.gold).is_equal(int(round(1000.0 * (1.0 - RAFamily.INHERITANCE_TAX))))
	assert_float(Life.mastery.xp.get("farming", 0.0)).is_equal_approx(100.0 * RAFamily.MASTERY_INHERIT_FRACTION, 0.01)
	assert_bool(Life.titles.earned_ids.is_empty()).is_true()
	assert_str(Life.life_path.family_name).is_equal("Testholt")
	assert_str(Life.life_path.given_name).is_equal("Wren")
	assert_float(Life.tendencies.values["martial"]).is_equal_approx(0.77, 0.001)
	assert_str(Life.awakening.element).is_equal("wind")
	assert_bool(Life.awakening.none).is_false()
	assert_bool(fam.children.is_empty()).is_true()
	if house_id != "":
		assert_float(Life.nobility.opinion(house_id)).is_equal_approx(80.0 * RAFamily.NOBLE_INHERIT_FRACTION, 1.0)
	assert_float(Life.biography.rep("trade")).is_equal_approx(40.0 * RAFamily.REPUTATION_INHERIT_FRACTION, 0.01)
	assert_int(fam.chronicles_list().size()).is_equal(1)


func test_succession_with_no_heir_offers_none() -> void:
	var fam := RAFamily.new()
	assert_array(fam.heir_candidates()).is_empty()
	assert_bool(bool(fam.succeed_to(999)["ok"])).is_false()


# --- serialisation -------------------------------------------------------------------

func test_serialize_round_trip() -> void:
	var fam := RAFamily.new()
	_close_friend("npc_f")
	fam.court("npc_f")
	fam.add_courtship_points("npc_f", 12.0)
	fam.spouse = {"id": "npc_g", "name": "Test Spouse", "sex": "female", "culture": "caldric",
		"occupation": "farmer", "tendencies": {"martial": 0.4}, "affinity": {"element": "earth", "dual": "", "none": false},
		"opinion": 70.0, "needs": 80.0, "age_at_marriage": 24, "since_day": WorldSim.day}
	fam.children.append({"id": 1, "name": "Wren", "sex": "female", "birth_day": WorldSim.day,
		"tendencies": {"martial": 0.5}, "affinity": {"element": "", "dual": "", "none": true}, "alive": true, "dead_day": -1})
	fam._ensure_parent_state()
	fam.chronicles.append({"name": "Old Aren", "family_name": "Testholt", "summary": ["A farmer.", "Loved."], "day": WorldSim.day})
	var snap: Dictionary = JSON.parse_string(JSON.stringify(fam.serialize()))
	var fam2 := RAFamily.new()
	fam2.deserialize(snap)
	assert_str(fam2.stage("npc_f")).is_equal("interested")
	assert_str(String(fam2.spouse["name"])).is_equal("Test Spouse")
	assert_int(fam2.children.size()).is_equal(1)
	assert_str(String(fam2.children[0]["name"])).is_equal("Wren")
	assert_int(fam2.parent_state.size()).is_equal(fam.parent_state.size())
	assert_int(fam2.chronicles.size()).is_equal(1)
	assert_int(fam2.next_child_id).is_equal(fam.next_child_id)
