extends GdUnitTestSuite
## GatherSession: 3-6 tap flow, care cancels the next hazard, hazards scale with skill vs node level,
## yield/quality from skill and tool tier, determinism by seed.

const GatherSession := preload("res://scripts/sim/gather_session.gd")


func _node(kind := "ore", level := 2, qty := 8, q := 50) -> Dictionary:
	return {"kind": kind, "item": "iron_ore", "level": level, "qty": qty, "quality": q}


func _session(node: Dictionary, skill: int, tier: int, seed_value: int) -> RefCounted:
	var s := GatherSession.new()
	assert_bool(s.start(node, skill, tier, seed_value)).is_true()
	return s


func test_minimum_session_is_three_taps() -> void:
	var s := _session(_node(), 3, 1, 7)
	assert_bool(s.can_take()).is_false()
	s.prospect()
	assert_bool(s.can_take()).is_false()
	s.extract()
	var r: Dictionary = s.take()
	assert_int(int(r["taps"])).is_equal(3)
	assert_str(String(r["item"])).is_equal("iron_ore")


func test_never_more_than_six_taps_and_three_extracts() -> void:
	for seed_value in 40:
		var s := _session(_node("ore", 1, 50), 5, 2, seed_value)
		s.prospect()
		var guard := 0
		while s.can_extract() or s.can_care():
			if s.can_care() and seed_value % 2 == 0:
				s.care()
			else:
				s.extract()
			guard += 1
			assert_int(guard).is_less(10)
		var r: Dictionary = s.take()
		assert_int(int(r["taps"])).is_less_equal(GatherSession.MAX_TAPS)
		assert_int(s.extracts).is_less_equal(GatherSession.MAX_EXTRACT)


func test_care_cancels_next_hazard() -> void:
	# Skill far below the node: hazard chance is at its cap (0.70). Find a seed where an unguarded
	# first extract hazards, then show care on the same seed cancels it.
	var found := 0
	for seed_value in 200:
		var a := _session(_node("ore", 10), 1, 0, seed_value)
		a.prospect()
		var ea: Dictionary = a.extract()
		if String(ea["hazard"]) == "":
			continue
		found += 1
		var b := _session(_node("ore", 10), 1, 0, seed_value)
		b.prospect()
		assert_bool(b.care()).is_true()
		var eb: Dictionary = b.extract()
		# care consumed one rng-free tap; the random stream is the same, so the hazard is cancelled.
		assert_str(String(eb["hazard"])).is_equal("")
		assert_bool(bool(eb["cancelled"])).is_true()
		assert_int(b.damage).is_equal(0)
		if found >= 5:
			break
	assert_int(found).is_greater(0)


func test_care_is_single_use_per_session() -> void:
	var s := _session(_node(), 3, 0, 3)
	s.prospect()
	s.extract()
	assert_bool(s.care()).is_true()
	assert_bool(s.can_care()).is_false()


func test_hazard_chance_falls_with_skill() -> void:
	assert_float(GatherSession.hazard_chance(1, 1)).is_equal_approx(0.40, 0.001)
	assert_float(GatherSession.hazard_chance(6, 1)).is_less(GatherSession.hazard_chance(3, 1))
	assert_float(GatherSession.hazard_chance(1, 8)).is_equal_approx(0.70, 0.001)
	assert_float(GatherSession.hazard_chance(10, 1)).is_equal_approx(0.04, 0.001)
	var hi := 0
	var lo := 0
	for seed_value in 300:
		var a := _session(_node("herb", 5, 20), 1, 0, seed_value)
		a.prospect()
		var b := _session(_node("herb", 5, 20), 9, 0, seed_value)
		b.prospect()
		for i in 3:
			if String(a.extract().get("hazard", "")) != "":
				hi += 1
			if String(b.extract().get("hazard", "")) != "":
				lo += 1
	assert_int(hi).is_greater(lo * 2)


func test_hazards_per_kind() -> void:
	var expect := {"ore": "cave_in", "herb": "thorns", "tree": "kickback", "fish": "snapped_line"}
	for kind: String in expect:
		var seen := false
		for seed_value in 100:
			var s := _session(_node(kind, 10, 20), 1, 0, seed_value)
			s.prospect()
			var e: Dictionary = s.extract()
			if String(e["hazard"]) != "":
				assert_str(String(e["hazard"])).is_equal(expect[kind])
				seen = true
				break
		assert_bool(seen).override_failure_message(kind).is_true()


func test_skill_and_tool_raise_quality_and_yield() -> void:
	var weak := 0.0
	var strong := 0.0
	var wy := 0
	var sy := 0
	for seed_value in 100:
		var a: Dictionary = _session(_node("ore", 3, 30, 50), 1, 0, seed_value).run(3, false)
		var b: Dictionary = _session(_node("ore", 3, 30, 50), 8, 3, seed_value).run(3, false)
		weak += float(a["grade"])
		strong += float(b["grade"])
		wy += int(a["count"])
		sy += int(b["count"])
	assert_float(strong).is_greater(weak)
	assert_int(sy).is_greater(wy)


func test_tier_thresholds() -> void:
	assert_int(GatherSession.tier_for_grade(10.0)).is_equal(0)
	assert_int(GatherSession.tier_for_grade(50.0)).is_equal(1)
	assert_int(GatherSession.tier_for_grade(95.0)).is_equal(2)


func test_yield_capped_by_node_quantity() -> void:
	var r: Dictionary = _session(_node("ore", 1, 2), 9, 3, 11).run(3, false)
	assert_int(int(r["count"])).is_less_equal(2)
	assert_int(int(r["consumed"])).is_equal(int(r["count"]))


func test_empty_node_cannot_start() -> void:
	var s := GatherSession.new()
	assert_bool(s.start(_node("ore", 1, 0), 3, 0, 1)).is_false()
	assert_bool(s.start({"kind": "bogus", "item": "x", "qty": 3}, 3, 0, 1)).is_false()


func test_deterministic_by_seed() -> void:
	var a: Dictionary = _session(_node(), 3, 1, 99).run(3, true)
	var b: Dictionary = _session(_node(), 3, 1, 99).run(3, true)
	assert_dict(a).is_equal(b)


func test_take_without_extracting_gives_nothing() -> void:
	var s := _session(_node(), 3, 0, 5)
	s.prospect()
	var r: Dictionary = s.take()
	assert_bool(bool(r["ok"])).is_false()
	assert_int(int(r.get("count", 0))).is_equal(0)
