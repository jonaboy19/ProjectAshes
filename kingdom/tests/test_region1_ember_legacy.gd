extends GdUnitTestSuite
## Ember Legacy (L10): the stone power bonus (through a real runestone network), echo
## inheritance (real echoes.gd), heirloom persistence through a JSON snapshot/restore
## round trip, biography-derived personality and the bark templates.

const Bio := preload("res://scripts/sim/biography.gd")
const Echoes := preload("res://scripts/sim/echoes.gd")
const State := preload("res://scripts/region1/region1_state.gd")


class MasteryStub extends RefCounted:
	var xp: Dictionary = {}


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


func _bio(role: String, years: int, rep_sphere: String, rep: float, deeds: int) -> Bio:
	var b := Bio.new()
	b.start_chapter(role, "Highwatch", "sergeant", "Highwatch Keep", 100)
	for i in deeds:
		b.add_highlight("Held the north pass %d" % i, 100 + i * 30)
	b.change_rep(rep_sphere, rep)
	b.close_chapter(100 + years * 12)
	return b


func _summary(role := "soldier", years := 30, sphere := "military", rep := 60.0, deeds := 5) -> Dictionary:
	var e := Echoes.new()
	e.add_echo("troll_echo", "the troll", 200, 1.0)
	var bear := e.add_echo("bear_echo", "the bear", 250, 1.0)
	e.attune(int(bear["id"]), 3)
	return EmberLegacy.build_summary(_bio(role, years, sphere, rep, deeds), e, "Maren Ashford", 71, "Ashford",
		100 + years * 12, {"place": "the Ember Road", "mastery": {"swordsmanship": 900.0, "farming": 50.0}})


func _sim() -> EmberLegacy:
	return EmberLegacy.new().setup(3) as EmberLegacy


# --- stone power bonus ------------------------------------------------------------------

func test_stone_power_bonus_is_derived_from_the_life_and_capped() -> void:
	var small := EmberLegacy.derive_profile(_summary("farmer", 5, "farming", 5.0, 0))
	var big := EmberLegacy.derive_profile(_summary("soldier", 60, "military", 100.0, 12))
	assert_float(float(small["power_bonus"])).is_greater(0.09)
	assert_float(float(big["power_bonus"])).is_greater(float(small["power_bonus"]))
	assert_float(float(big["power_bonus"])).is_less_equal(0.45 + 0.0001)


func test_ancestor_stone_makes_the_network_stronger_and_wider() -> void:
	var s := _sim()
	var id := s.on_life_ended(_summary())
	var net := RARunestoneNetwork.new()
	var st := net.add_stone(Vector2(0, 0), 100.0, -1, "Ember Road Stone")
	st["power"] = 0.6
	st["condition"] = 0.5
	var far := Vector2(108, 0)   # outside the plain radius
	var before_strength := net.strength(st)
	assert_float(net.coverage(far)).is_equal(0.0)
	var r := s.choose_runestone(id, st["id"], "Ember Road Stone")
	assert_bool(r["ok"]).is_true()
	assert_float(s.power_bonus(st["id"])).is_greater(0.2)
	assert_int(s.apply_to_network(net)).is_equal(1)
	assert_float(net.strength(st)).is_greater(before_strength + 0.1)
	assert_float(net.coverage(far)).is_greater(0.0)
	assert_str(String(st["ancestor"])).is_equal("Maren Ashford")
	# idempotent: loading a save and applying again must not stack the bonus
	var radius := float(st["radius"])
	s.apply_to_network(net)
	assert_float(float(st["radius"])).is_equal_approx(radius, 0.0001)
	assert_bool(s.is_ancestor_stone(st["id"])).is_true()
	assert_bool(s.is_ancestor_stone(99)).is_false()


func test_one_ancestor_per_stone_and_ember_is_consumed() -> void:
	var s := _sim()
	var a := s.on_life_ended(_summary())
	var b := s.on_life_ended(_summary("smith", 20, "craft", 40.0, 2))
	assert_bool(s.choose_runestone(a, 4)["ok"]).is_true()
	assert_bool(s.choose_runestone(b, 4)["ok"]).is_false()
	assert_int(s.pending().size()).is_equal(1)
	assert_bool(s.choose_runestone(a, 5)["ok"]).is_false()   # already used up


# --- personality and barks --------------------------------------------------------------

func test_personality_comes_from_the_biography() -> void:
	var soldier := EmberLegacy.derive_profile(_summary("soldier", 30, "military", 60.0, 3))
	var farmer := EmberLegacy.derive_profile(_summary("smallholder", 30, "farming", 40.0, 3))
	var small_rep := EmberLegacy.derive_profile(_summary("hunter", 3, "military", 2.0, 0))   # rep too small: the role decides
	assert_str(String(soldier["archetype"])).is_equal("military")
	assert_str(String(farmer["archetype"])).is_equal("farming")
	assert_str(String(small_rep["archetype"])).is_equal("farming")   # hunter -> farming sphere
	assert_float(float((farmer["traits"] as Dictionary)["warmth"])).is_greater(float((soldier["traits"] as Dictionary)["warmth"]))
	assert_float(float((soldier["traits"] as Dictionary)["stern"])).is_greater(float((farmer["traits"] as Dictionary)["stern"]))
	# a distrusted ancestor is colder than a loved one
	var loved := EmberLegacy.derive_profile(_summary("guard", 30, "military", 60.0, 1))
	var hated := EmberLegacy.derive_profile(_summary("guard", 30, "military", -60.0, 1))
	assert_float(float((hated["traits"] as Dictionary)["warmth"])).is_less(float((loved["traits"] as Dictionary)["warmth"]))


func test_barks_use_the_biography_and_are_deterministic() -> void:
	var s := _sim()
	var id := s.on_life_ended(_summary())
	s.choose_runestone(id, 7)
	var ctx := {"heir": "Tam Ashford", "place": "Cinderpost"}
	var a := s.bark(7, "greet", ctx)
	assert_str(a).is_not_empty()
	assert_str(a).is_equal(s.bark(7, "greet", ctx))
	assert_bool(a.contains("{")).is_false()   # every placeholder filled
	for sit in EmberLegacy.SITUATIONS:
		var line := s.bark(7, sit, ctx)
		assert_str(line).is_not_empty()
		assert_bool(line.contains("{")).is_false()
	assert_str(s.bark(999, "greet", ctx)).is_empty()   # not an ancestor stone
	# situation priority
	assert_str(EmberLegacy.situation_for({"raid": true, "pack": true})).is_equal("warn_raid")
	assert_str(EmberLegacy.situation_for({"pack": true})).is_equal("warn_pack")
	assert_str(EmberLegacy.situation_for({}, 0.2)).is_equal("dim")
	assert_str(EmberLegacy.situation_for({}, 1.0, true)).is_equal("rumour")
	assert_str(EmberLegacy.situation_for({})).is_equal("greet")
	assert_str(String(s.card(7)["title"])).contains("Maren Ashford")


# --- echo inheritance -------------------------------------------------------------------

func test_heir_inherits_the_attuned_echo_and_a_skill_trace() -> void:
	var s := _sim()
	var id := s.on_life_ended(_summary())
	var res := s.choose_heir(id)
	assert_bool(res["ok"]).is_true()
	assert_str(String(res["echo"]["type"])).is_equal("bear_echo")   # the attuned one wins
	assert_str(String(res["skill"]["discipline"])).is_equal("swordsmanship")
	var heir_echoes := Echoes.new()
	var m := MasteryStub.new()
	m.xp = {"swordsmanship": 10.0}
	var added := s.apply_blessing(res, heir_echoes, 500, m)
	assert_int(heir_echoes.echoes.size()).is_equal(1)
	assert_str(String(added["type"])).is_equal("bear_echo")
	assert_str(String(added["source_name"])).is_equal("the bear")
	assert_float(float(m.xp["swordsmanship"])).is_equal_approx(70.0, 0.001)
	# applying twice must not duplicate the echo
	s.apply_blessing(res, heir_echoes, 501, m)
	assert_int(heir_echoes.echoes.size()).is_equal(1)
	# and the inherited echo really works: it can be attuned and gives modifiers
	assert_bool(heir_echoes.attune(int(added["id"]), 1)["ok"]).is_true()
	assert_float(float(heir_echoes.modifiers().get("carry_weight", 0.0))).is_greater(0.0)


func test_heir_without_echoes_receives_the_family_echo() -> void:
	var s := _sim()
	var sum := EmberLegacy.build_summary(_bio("farmer", 10, "farming", 20.0, 1), Echoes.new(),
		"Old Dara Ashford", 80, "Ashford", 4000)
	var id := s.on_life_ended(sum)
	var res := s.choose_heir(id)
	assert_str(String(res["echo"]["type"])).is_equal("family_echo")
	assert_str(String(res["echo"]["source_name"])).is_equal("Old Dara Ashford")
	var heir_echoes := Echoes.new()
	s.apply_blessing(res, heir_echoes, 10)
	assert_str(String(heir_echoes.echoes[0]["type"])).is_equal("family_echo")


# --- heirloom persistence ---------------------------------------------------------------

func test_heirloom_levels_with_the_family_and_survives_a_save_round_trip() -> void:
	var s := _sim()
	State.register_sim(s)
	var id := s.on_life_ended(_summary())
	var res := s.choose_heirloom(id)
	assert_bool(res["ok"]).is_true()
	var hid := int(res["heirloom"]["id"])
	assert_str(String(res["heirloom"]["name"])).is_equal("Ashford Watchblade")
	assert_int(int(s.heirloom(hid)["level"])).is_equal(1)
	s.on_succession()
	s.on_succession()
	assert_int(int(s.heirloom(hid)["level"])).is_equal(3)
	var power := s.heirloom_power(hid)
	assert_float(power).is_greater(1.1)
	var digest := s.digest()
	# save -> JSON text -> a brand new sim and registry -> restore
	var text := JSON.stringify(State.snapshot())
	State.clear()
	var fresh := EmberLegacy.new().setup(999) as EmberLegacy
	State.register_sim(fresh)
	State.restore(JSON.parse_string(text))
	assert_str(fresh.digest()).is_equal(digest)
	assert_int(fresh.heirlooms.size()).is_equal(1)
	assert_int(int(fresh.heirloom(hid)["level"])).is_equal(3)
	assert_float(fresh.heirloom_power(hid)).is_equal_approx(power, 0.0001)
	var item := fresh.heirloom_item(hid)
	assert_str(String(item["id"])).is_equal("heirloom_blade")
	assert_int(int(item["level"])).is_equal(3)
	# it keeps levelling after a load, and stops at the cap
	for i in 20:
		fresh.on_succession()
	assert_int(int(fresh.heirloom(hid)["level"])).is_equal(10)


func test_stone_and_lineage_also_survive_a_round_trip() -> void:
	var s := _sim()
	State.register_sim(s)
	var a := s.on_life_ended(_summary())
	var b := s.on_life_ended(_summary("smith", 20, "craft", 40.0, 2))
	s.choose_runestone(a, 12, "Mere Stone")
	s.choose_heir(b)
	var pending := s.on_life_ended(_summary("innkeeper", 15, "trade", 30.0, 1))   # still undecided
	var digest := s.digest()
	var text := JSON.stringify(State.snapshot())
	State.clear()
	var fresh := EmberLegacy.new().setup(1) as EmberLegacy
	State.register_sim(fresh)
	State.restore(JSON.parse_string(text))
	assert_str(fresh.digest()).is_equal(digest)
	assert_bool(fresh.is_ancestor_stone(12)).is_true()
	assert_int(fresh.pending().size()).is_equal(1)
	assert_int(int(fresh.pending()[0]["id"])).is_equal(pending)
	assert_int(fresh.lineage.size()).is_equal(2)
	# the same bark comes back after loading
	assert_str(fresh.bark(12, "greet", {"heir": "Tam"})).is_equal(s.bark(12, "greet", {"heir": "Tam"}))
	assert_int(fresh.choices_for(pending).size()).is_equal(3)


func test_h7_static_emit_files_an_ember_only_when_the_module_runs() -> void:
	var bio := _bio("soldier", 10, "military", 30.0, 1)
	assert_int(EmberLegacy.emit_life_ended(bio, Echoes.new(), "A B", 70, "B", 5000)).is_equal(-1)
	var s := _sim()
	State.register_sim(s)
	var seen := []
	s.life_ended.connect(func(sum: Dictionary) -> void: seen.append(sum["name"]))
	var id := EmberLegacy.emit_life_ended(bio, Echoes.new(), "A B", 70, "B", 5000)
	assert_int(id).is_greater(0)
	assert_array(seen).is_equal(["A B"])
	assert_int(s.pending().size()).is_equal(1)
	assert_int(s.choices_for(id).size()).is_equal(3)
