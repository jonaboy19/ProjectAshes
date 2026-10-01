extends GdUnitTestSuite
## HitResolver truth table: every outcome, parry grades, lanes, poise, seeded clashes.

const R := preload("res://scripts/combat/hit_resolver.gd")
const O := R.Outcome


func _rng(s := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _atk(d := 10, p := 10.0) -> Dictionary:
	return {"damage": d, "poise_damage": p, "lane": 1, "parryable": true, "unblockable": false, "stat": 0.0}


func _def(extra := {}) -> Dictionary:
	var d := {"guarding": false, "guard_age": 99.0, "guard_pool": 100.0, "guard_cost": 0.6, "poise": 30.0,
		"evading": false, "from_front": true}
	d.merge(extra, true)
	return d


func test_plain_hit() -> void:
	var r := R.resolve(_atk(), _def(), _rng())
	assert_int(r["result"]).is_equal(O.HIT)
	assert_int(r["damage"]).is_equal(10)


func test_dodge_beats_everything() -> void:
	var r := R.resolve(_atk(), _def({"evading": true, "guarding": true, "guard_age": 0.0}), _rng())
	assert_int(r["result"]).is_equal(O.DODGED)
	assert_int(r["damage"]).is_equal(0)


func test_block_costs_guard_and_chips() -> void:
	var r := R.resolve(_atk(20), _def({"guarding": true}), _rng())
	assert_int(r["result"]).is_equal(O.BLOCKED)
	assert_float(r["guard_cost"]).is_equal_approx(12.0, 0.001)
	assert_int(r["damage"]).is_equal(3)          # 15% chip
	# player tuning (1.6x) reproduces the old stamina cost
	var p := R.resolve(_atk(20), _def({"guarding": true, "guard_cost": 1.6}), _rng())
	assert_float(p["guard_cost"]).is_equal_approx(32.0, 0.001)


func test_block_from_behind_is_a_hit() -> void:
	var r := R.resolve(_atk(), _def({"guarding": true, "from_front": false}), _rng())
	assert_int(r["result"]).is_equal(O.HIT)


func test_guard_break_when_pool_runs_out() -> void:
	var r := R.resolve(_atk(20), _def({"guarding": true, "guard_pool": 5.0}), _rng())
	assert_int(r["result"]).is_equal(O.GUARD_BROKEN)
	assert_float(r["defender_stun"]).is_equal_approx(R.GUARD_BREAK_STUN, 0.001)


func test_guard_break_on_poise_overflow() -> void:
	var r := R.resolve(_atk(10, 70.0), _def({"guarding": true, "poise": 30.0}), _rng())
	assert_int(r["result"]).is_equal(O.GUARD_BROKEN)


func test_unblockable_ignores_guard() -> void:
	var a := _atk()
	a["unblockable"] = true
	assert_int(R.resolve(a, _def({"guarding": true}), _rng())["result"]).is_equal(O.HIT)


func test_lane_mismatch_blocks_worse() -> void:
	var a := _atk(20)
	a["lane"] = 0
	var same := R.resolve(a, _def({"guarding": true, "guard_lane": 0}), _rng())
	var off := R.resolve(a, _def({"guarding": true, "guard_lane": 2}), _rng())
	assert_float(off["guard_cost"]).is_greater(same["guard_cost"])
	assert_int(off["damage"]).is_greater(same["damage"])


func test_parry_grades() -> void:
	var perfect := R.resolve(_atk(), _def({"guarding": true, "guard_age": 0.03}), _rng())
	assert_int(perfect["result"]).is_equal(O.PARRIED)
	assert_str(perfect["grade"]).is_equal("perfect")
	var knock := R.resolve(_atk(), _def({"guarding": true, "guard_age": 0.12}), _rng())
	assert_str(knock["grade"]).is_equal("knockaway")
	assert_float(knock["refund"]).is_equal_approx(8.0, 0.001)    # the old fixed refund
	assert_float(perfect["attacker_stun"]).is_greater(knock["attacker_stun"])
	assert_float(perfect["riposte"]).is_greater(knock["riposte"])
	var late := R.resolve(_atk(), _def({"guarding": true, "guard_age": 0.3}), _rng())
	assert_int(late["result"]).is_equal(O.BLOCKED)


func test_broken_parry_on_heavy_blow() -> void:
	var r := R.resolve(_atk(30, 80.0), _def({"guarding": true, "guard_age": 0.05, "poise": 30.0}), _rng())
	assert_int(r["result"]).is_equal(O.PARRIED)
	assert_str(r["grade"]).is_equal("broken")
	assert_int(r["damage"]).is_greater(0)
	assert_float(r["refund"]).is_equal(0.0)


func test_unparryable_cannot_be_parried() -> void:
	var a := _atk()
	a["parryable"] = false
	assert_int(R.resolve(a, _def({"guarding": true, "guard_age": 0.02}), _rng())["result"]).is_equal(O.BLOCKED)


func test_poise_break_staggers_on_hit() -> void:
	var r := R.resolve(_atk(10, 40.0), _def({"poise": 30.0}), _rng())
	assert_int(r["result"]).is_equal(O.HIT)
	assert_float(r["defender_stun"]).is_greater(0.0)


func test_clash_on_simultaneous_strikes_is_seeded() -> void:
	var d := _def({"swing": {"active_age": 0.05, "parryable": true, "poise_damage": 10.0, "stat": 0.0}})
	var r1 := R.resolve(_atk(10, 10.0), d, _rng(3))
	var r2 := R.resolve(_atk(10, 10.0), d, _rng(3))
	assert_int(r1["result"]).is_equal(O.CLASHED)
	assert_str(r1["winner"]).is_equal(r2["winner"])      # same seed, same beat
	assert_int(r1["damage"]).is_equal(0)


func test_clash_prefers_stronger_blow_and_loser_is_staggered() -> void:
	var wins := 0
	for s in 40:
		var d := _def({"swing": {"active_age": 0.0, "parryable": true, "poise_damage": 5.0, "stat": 0.0}})
		var r := R.resolve(_atk(30, 40.0), d, _rng(s))
		if r["winner"] == "attacker":
			wins += 1
			assert_float(r["defender_stun"]).is_equal_approx(R.CLASH_STUN, 0.001)
	assert_int(wins).is_equal(40)


func test_clash_needs_overlap_and_parryable() -> void:
	var far := _def({"swing": {"active_age": 0.5, "parryable": true, "poise_damage": 10.0}})
	assert_int(R.resolve(_atk(), far, _rng())["result"]).is_equal(O.HIT)
	var heavy := _def({"swing": {"active_age": 0.0, "parryable": false, "poise_damage": 10.0}})
	assert_int(R.resolve(_atk(), heavy, _rng())["result"]).is_equal(O.HIT)
