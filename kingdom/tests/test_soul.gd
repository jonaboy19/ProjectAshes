extends GdUnitTestSuite
## Soul system (scripts/sim/soul.gd, scripts/sim/skill_evolution.gd,
## data/soul/*.json): tier ordering, diminishing returns, breakthrough gating
## and determinism, Path emergence, evolution thresholds and save/load.

const Soul := preload("res://scripts/sim/soul.gd")
const SkillEvolution := preload("res://scripts/sim/skill_evolution.gd")


func _fresh() -> Soul:
	return Soul.new()


func _fresh_evo() -> SkillEvolution:
	return SkillEvolution.new()


# --- tiers -------------------------------------------------------------------------

func test_twelve_tiers_ordered_by_rising_threshold() -> void:
	var s := _fresh()
	assert_int(s._tiers.size()).is_equal(12)
	var last := -1.0
	for t: Dictionary in s._tiers:
		var th := float(t["threshold"])
		assert_bool(th > last).override_failure_message("tiers must strictly rise").is_true()
		last = th
		assert_str(String(t["name"])).is_not_empty()
		assert_str(String(t["flavour"])).is_not_empty()


func test_starts_at_ember_tier_zero() -> void:
	var s := _fresh()
	assert_int(s.tier()).is_equal(0)
	assert_str(String(s.tier_info().get("id", ""))).is_equal("ember")


func test_gain_accumulates_power_and_auto_advances_early_tiers() -> void:
	var s := _fresh()
	var r := s.gain("combat", 50.0, 1)
	assert_float(r["power"] as float).is_greater(0.0)
	assert_bool(r["tier_up"] as bool).is_true()
	assert_int(s.tier()).is_greater(0)
	assert_int(s.tier()).is_less_equal(Soul.AUTO_MAX_INDEX)


func test_gain_ignores_unknown_source_and_non_positive_amount() -> void:
	var s := _fresh()
	var r := s.gain("nonsense", 10.0, 1)
	assert_float(r["power"] as float).is_equal(0.0)
	r = s.gain("combat", 0.0, 1)
	assert_float(r["power"] as float).is_equal(0.0)
	r = s.gain("combat", -5.0, 1)
	assert_float(r["power"] as float).is_equal(0.0)


func test_diminishing_returns_within_the_same_day() -> void:
	var s := _fresh()
	var first := s.gain("combat", 10.0, 1)
	var second := s.gain("combat", 10.0, 1)
	assert_float(second["gained"] as float).is_less(first["gained"] as float)


func test_diminishing_returns_reset_on_a_new_day() -> void:
	var s := _fresh()
	var day1 := s.gain("combat", 10.0, 1)
	s.gain("combat", 10.0, 1)
	var day2 := s.gain("combat", 10.0, 2)
	assert_float(day2["gained"] as float).is_equal_approx(day1["gained"] as float, 0.0001)


func test_grinding_one_source_is_slower_than_mixing_sources() -> void:
	var mono := _fresh()
	for i in 6:
		mono.gain("combat", 10.0, 1)
	var mixed := _fresh()
	for src: String in ["combat", "forge", "farm", "heal", "hunt", "meditate"]:
		mixed.gain(src, 10.0, 1)
	assert_float(mixed.power).is_greater(mono.power)


# --- breakthrough --------------------------------------------------------------------

func test_cannot_breakthrough_before_tempered() -> void:
	var s := _fresh()
	assert_bool(s.can_attempt_breakthrough()).is_false()
	var r := s.attempt_breakthrough()
	assert_bool(r["ok"] as bool).is_false()
	assert_int(s.tier()).is_equal(0)


## `source` defaults to "combat"; path-emergence tests pass "technique" (a
## source no Path currently lists) so reaching Tempered doesn't itself skew
## which Path later looks dominant.
func _push_to_tempered(s: Soul, source := "combat") -> void:
	var day := 1
	while s.tier() < Soul.AUTO_MAX_INDEX:
		s.gain(source, 40.0, day)
		day += 1
		if day > 5000:
			break


## Diminishing returns apply per day, so filling a large power gap must spread
## gains across many days (a fresh day each call) rather than hammering one.
func _fill_power(s: Soul, target: float, day_start: int) -> void:
	var day := day_start
	while s.power < target and day < day_start + 5000:
		s.gain("combat", 40.0, day)
		day += 1


func test_breakthrough_gated_until_enough_power_past_threshold() -> void:
	var s := _fresh()
	_push_to_tempered(s)
	assert_int(s.tier()).is_equal(Soul.AUTO_MAX_INDEX)
	assert_bool(s.can_attempt_breakthrough()).is_false()
	var next_th := float(s.tier_info(s.tier() + 1).get("threshold", 0.0))
	_fill_power(s, next_th, 9000)
	assert_bool(s.can_attempt_breakthrough()).is_true()


func test_breakthrough_is_deterministic_with_a_seeded_roll() -> void:
	var s := _fresh()
	_push_to_tempered(s)
	var next_th := float(s.tier_info(s.tier() + 1).get("threshold", 0.0))
	_fill_power(s, next_th * 1.5, 9000)
	var r1 := s.attempt_breakthrough(-1, {"roll": 0.1})
	assert_bool(r1["ok"] as bool).is_true()
	assert_bool(r1["success"] as bool).is_true()
	assert_int(s.tier()).is_equal(Soul.AUTO_MAX_INDEX + 1)


func test_breakthrough_failure_is_a_setback_not_death() -> void:
	var s := _fresh()
	_push_to_tempered(s)
	var next_th := float(s.tier_info(s.tier() + 1).get("threshold", 0.0))
	_fill_power(s, next_th * 1.05, 9000)
	var before_power := s.power
	var before_tier := s.tier()
	var r := s.attempt_breakthrough(-1, {"roll": 0.999})
	assert_bool(r["ok"] as bool).is_true()
	assert_bool(r["success"] as bool).is_false()
	assert_int(s.tier()).is_equal(before_tier)
	assert_float(s.power).is_less(before_power)
	assert_float(r["power_lost"] as float).is_greater(0.0)


func test_injury_lowers_breakthrough_chance() -> void:
	var s := _fresh()
	_push_to_tempered(s)
	var next_th := float(s.tier_info(s.tier() + 1).get("threshold", 0.0))
	_fill_power(s, next_th * 1.4, 9000)
	# A roll that succeeds uninjured must fail once a heavy injury penalty applies.
	var clean := _fresh()
	_push_to_tempered(clean)
	_fill_power(clean, next_th * 1.4, 9000)
	var ok_clean := clean.attempt_breakthrough(-1, {"roll": 0.5})
	var hurt := s.attempt_breakthrough(-1, {"roll": 0.5, "injury": 1.0})
	assert_bool(ok_clean["success"] as bool).is_true()
	assert_bool(hurt["success"] as bool).is_false()


# --- paths -----------------------------------------------------------------------

func test_no_path_candidates_before_tempered() -> void:
	var s := _fresh()
	s.gain("forge", 5.0, 1)
	assert_array(s.path_candidates()).is_empty()


func test_path_emerges_from_dominant_usage() -> void:
	var s := _fresh()
	_push_to_tempered(s, "technique")
	for i in 20:
		s.gain("forge", 30.0, 1000 + i)
	# "the Merchant's Weight" also lists "forge" as a source (it represents the
	# overlap between crafts); crediting a smithing discipline (which only
	# "the Forge" lists) breaks that tie the way a real smith's history would.
	var dominant := s.dominant_path({"smithing": 40})
	assert_bool(dominant.is_empty()).is_false()
	assert_str(String(dominant["id"])).is_equal("forge")


func test_blessing_element_nudges_path_choice() -> void:
	var s := _fresh()
	_push_to_tempered(s, "technique")
	s.gain("combat", 5.0, 1)
	s.gain("hunt", 5.0, 1)
	s.set_blessing("earth")
	var candidates := s.path_candidates()
	var forge_score := 0.0
	for c: Dictionary in candidates:
		if String(c["id"]) == "forge":
			forge_score = float(c["score"])
	assert_float(forge_score).is_greater(0.0)


func test_choose_path_locks_it_in_and_exposes_modifiers() -> void:
	var s := _fresh()
	_push_to_tempered(s, "technique")
	for i in 20:
		s.gain("forge", 30.0, 2000 + i)
	var dominant := s.dominant_path({"smithing": 40})
	var r := s.choose_path(String(dominant["id"]))
	assert_bool(r["ok"] as bool).is_true()
	assert_str(s.chosen_path).is_equal(String(dominant["id"]))
	assert_bool(s.path_modifiers().is_empty()).is_false()
	var second := s.choose_path("blade")
	assert_bool(second["ok"] as bool).is_false()


# --- serialize ---------------------------------------------------------------------

func test_soul_serialize_round_trip() -> void:
	var s := _fresh()
	_push_to_tempered(s)
	s.gain("forge", 12.0, 500)
	s.set_blessing("fire", "earth")
	var d := s.serialize()
	var r := _fresh()
	r.deserialize(d)
	assert_float(r.power).is_equal_approx(s.power, 0.001)
	assert_int(r.tier()).is_equal(s.tier())
	assert_str(r.blessing_element).is_equal("fire")
	assert_str(r.blessing_dual).is_equal("earth")


# --- skill evolution -----------------------------------------------------------------

func test_evolution_data_has_every_element_with_at_least_three_variants() -> void:
	var e := _fresh_evo()
	for el: String in ["fire", "water", "earth", "wind", "lightning", "qi"]:
		assert_bool(e._variants.has(el)).override_failure_message("missing element " + el).is_true()
		assert_int((e._variants[el] as Array).size()).is_greater_equal(3)


func test_evolution_unlocks_after_enough_uses_in_context() -> void:
	var e := _fresh_evo()
	var threshold := int((e._variants["fire"][0] as Dictionary)["uses"])
	var context := String((e._variants["fire"][0] as Dictionary)["context"])
	var last := {}
	for i in threshold:
		last = e.record_use("fire", context, 1)
	assert_bool((last["newly_unlocked"] as Array).size() > 0).is_true()
	assert_bool(e.evolutions().has(String((e._variants["fire"][0] as Dictionary)["id"]))).is_true()


func test_different_context_evolves_into_a_different_variant() -> void:
	var e := _fresh_evo()
	var fire_defs: Array = e._variants["fire"]
	var forge_ctx := ""
	var combat_ctx := ""
	for def: Dictionary in fire_defs:
		if def["context"] == "forge":
			forge_ctx = def["id"]
		elif def["context"] == "combat":
			combat_ctx = def["id"]
	var uses_needed := int((fire_defs[0] as Dictionary)["uses"])
	for i in uses_needed:
		e.record_use("fire", "forge", 1)
	assert_bool(e.evolutions().has(forge_ctx)).is_true()
	assert_bool(e.evolutions().has(combat_ctx)).is_false()


func test_mutation_unlocks_when_two_contexts_are_both_high() -> void:
	var e := _fresh_evo()
	var mutation: Dictionary = {}
	for m: Dictionary in e._mutations:
		if m["element"] == "fire":
			mutation = m
			break
	assert_bool(mutation.is_empty()).is_false()
	var contexts: Array = mutation["contexts"]
	var needed := int(mutation["uses"])
	for c: String in contexts:
		for i in needed:
			e.record_use("fire", String(c), 1)
	assert_bool(e.evolutions().has(String(mutation["id"]))).is_true()


func test_newly_available_drains_the_pending_queue() -> void:
	var e := _fresh_evo()
	var threshold := int((e._variants["fire"][0] as Dictionary)["uses"])
	var context := String((e._variants["fire"][0] as Dictionary)["context"])
	for i in threshold:
		e.record_use("fire", context, 1)
	assert_array(e.newly_available()).is_not_empty()
	assert_array(e.newly_available()).is_empty()


func test_evolution_modifiers_sum_across_unlocked() -> void:
	var e := _fresh_evo()
	var fire_defs: Array = e._variants["fire"]
	var forge_def: Dictionary = {}
	for def: Dictionary in fire_defs:
		if def["context"] == "forge":
			forge_def = def
	for i in int(forge_def["uses"]):
		e.record_use("fire", "forge", 1)
	var mods := e.modifiers()
	var expect_key: String = (forge_def["modifiers"] as Dictionary).keys()[0]
	assert_float(float(mods[expect_key])).is_equal_approx(float((forge_def["modifiers"] as Dictionary)[expect_key]), 0.0001)


func test_evolution_serialize_round_trip() -> void:
	var e := _fresh_evo()
	var fire_defs: Array = e._variants["fire"]
	var forge_def: Dictionary = {}
	for def: Dictionary in fire_defs:
		if def["context"] == "forge":
			forge_def = def
	for i in int(forge_def["uses"]):
		e.record_use("fire", "forge", 3)
	var d := e.serialize()
	var r := _fresh_evo()
	r.deserialize(d)
	assert_bool(r.evolutions().has(String(forge_def["id"]))).is_true()
	assert_int(r.use_count("fire", "forge")).is_equal(int(forge_def["uses"]))
