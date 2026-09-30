extends GdUnitTestSuite
## Progression spine: level 1-500 curve, region saturation, repetition decay, one-time XP, stats, saves.

const Prog := preload("res://scripts/sim/progression.gd")


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func test_curve_is_monotonic_and_reaches_500() -> void:
	assert_int(Prog.max_level()).is_equal(500)
	var prev := 0.0
	for l in range(1, 500):
		var x := Prog.xp_to_next(l)
		assert_float(x).is_greater(prev)
		prev = x
	assert_float(Prog.xp_to_next(500)).is_equal(0.0)
	for l in [1, 2, 10, 55, 60, 250, 499, 500]:
		assert_int(Prog.level_for_xp(Prog.total_xp(l))).is_equal(l)
		if l > 1:
			assert_int(Prog.level_for_xp(Prog.total_xp(l) - 1.0)).is_equal(l - 1)
	assert_float(Prog.total_xp(500)).is_greater(Prog.total_xp(60) * 1000.0)


func test_region_saturation_drops_sharply_past_the_soft_cap() -> void:
	assert_float(Prog.region_saturation("region1", 1)).is_equal(1.0)
	assert_float(Prog.region_saturation("region1", 50)).is_equal(1.0)
	assert_float(Prog.region_saturation("region1", 55)).is_equal_approx(0.6, 0.001)
	assert_float(Prog.region_saturation("region1", 56)).is_less(0.2)
	assert_float(Prog.region_saturation("region1", 58)).is_less(0.02)
	assert_float(Prog.region_saturation("region1", 60)).is_equal(0.0)
	var prev := 2.0
	for l in range(1, 70):
		var s := Prog.region_saturation("region1", l)
		assert_float(s).is_less_equal(prev)
		prev = s
	# the next region pays in full at the same level
	assert_float(Prog.region_saturation("region2", 60)).is_equal(1.0)


func test_region_one_hard_cap_stops_xp() -> void:
	var p: RefCounted = Prog.new()
	p.grant_raw(Prog.total_xp(60))
	assert_int(p.level).is_equal(60)
	var r: Dictionary = p.award("quest", {"id": "q_late", "content_level": 55})
	assert_float(r["xp"]).is_equal(0.0)
	assert_bool(r["capped"]).is_true()
	var r2: Dictionary = p.award("quest", {"id": "q_r2", "content_level": 60, "region": "region2"})
	assert_float(r2["xp"]).is_greater(0.0)


func test_repetition_decays_and_recovers_with_days() -> void:
	var p: RefCounted = Prog.new()
	var first: float = p.award("kill", {"subject": "wolf", "day": 1})["xp"]
	var last := first
	for i in 25:
		last = p.award("kill", {"subject": "wolf", "day": 1})["xp"]
	assert_float(last).is_less(first * 0.5)
	# a different species is fresh
	var other: float = p.award("kill", {"subject": "boar", "day": 1})["xp"]
	assert_float(other).is_greater(last * 1.5)
	# days later the wolf pays more again, but never beyond the first
	var later: float = p.award("kill", {"subject": "wolf", "day": 4})["xp"]
	assert_float(later).is_greater(last)
	assert_float(later).is_less_equal(first + 0.001)


func test_repetition_factor_is_floored() -> void:
	var p: RefCounted = Prog.new()
	for i in 500:
		p.award("craft", {"subject": "nail", "day": 1})
	assert_float(p.repetition_factor("craft", "nail", 1)).is_equal_approx(0.05, 0.0001)


func test_one_time_sources_pay_once() -> void:
	var p: RefCounted = Prog.new()
	var a: float = p.award("discovery", {"id": "ruin_1"})["xp"]
	var b: Dictionary = p.award("discovery", {"id": "ruin_1"})
	assert_float(a).is_greater(0.0)
	assert_float(b["xp"]).is_equal(0.0)
	assert_str(b["reason"]).is_equal("already_done")
	assert_float(p.award("discovery", {"id": "ruin_2"})["xp"]).is_greater(0.0)
	# unknown activities pay nothing
	assert_float(p.award("teleport", {})["xp"]).is_equal(0.0)


func test_over_levelled_content_pays_little() -> void:
	assert_float(Prog.diff_factor(30, 30)).is_equal(1.0)
	assert_float(Prog.diff_factor(30, 20)).is_less(0.15)
	assert_float(Prog.diff_factor(30, 35)).is_greater(1.0)
	assert_float(Prog.diff_factor(30, 100)).is_less_equal(1.4)


func test_grinding_one_thing_for_hours_cannot_shortcut_region_one() -> void:
	var p: RefCounted = Prog.new()
	# 12 days of nothing but killing wolves, 600 kills a day (far beyond normal play)
	for day in range(1, 13):
		for i in 600:
			p.award("kill", {"subject": "wolf", "day": day})
	assert_int(p.level).is_less(25)


func test_level_up_signal_and_points() -> void:
	var p: RefCounted = Prog.new()
	var seen: Array = []
	p.level_up.connect(func(l: int) -> void: seen.append(l))
	p.grant_raw(Prog.total_xp(6))
	assert_array(seen).is_equal([2, 3, 4, 5, 6])
	assert_int(p.points_unspent()).is_equal(Prog.points_earned(6))
	assert_bool(p.spend_point("strength")).is_true()
	assert_bool(p.spend_point("luck")).is_false()
	assert_int(p.points_unspent()).is_equal(Prog.points_earned(6) - 1)
	assert_int(int(p.stats()["attack"] * 10)).is_greater(int(Prog.stats_for(6)["attack"] * 10))


func test_level_is_a_small_part_of_power() -> void:
	assert_float(Prog.power_share(50)).is_less(1.5)
	assert_float(Prog.power_share(1)).is_equal(1.0)
	assert_int(Prog.stats_for(500)["hp"]).is_greater(Prog.stats_for(1)["hp"])


func test_titles() -> void:
	assert_str(Prog.title_for(1)).is_equal("Newcomer")
	assert_str(Prog.title_for(500)).is_equal("Worldsoul")


func test_save_round_trip() -> void:
	var p: RefCounted = Prog.new()
	for i in 30:
		p.award("kill", {"subject": "wolf", "day": 2})
	p.award("discovery", {"id": "x"})
	p.grant_raw(5000.0)
	p.spend_point("wisdom")
	var d: Dictionary = p.serialize()
	var q: RefCounted = Prog.new()
	q.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_str(_norm(q.serialize())).is_equal(_norm(d))
	assert_int(q.level).is_equal(p.level)
	assert_float(q.award("discovery", {"id": "x"})["xp"]).is_equal(0.0)
	assert_float(q.repetition_factor("kill", "wolf", 2)).is_equal_approx(p.repetition_factor("kill", "wolf", 2), 0.0001)
