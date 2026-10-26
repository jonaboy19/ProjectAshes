extends GdUnitTestSuite
## Ready v1 C8: taming. The Calm hold rules (when a beast is calmable, how long the hold is), the success curve of
## followers.calm_step, the never-tamable list, and the save round trip of a tamed creature with its mode and post.

const Hub := preload("res://scripts/realm/realm_hub.gd")


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func _holds_to_tame(fm: RefCounted, id: String, fear: float, day: int) -> int:
	fm.start_taming(id, "wolf")
	for n in range(1, 30):
		var r: Dictionary = fm.calm_step(id, fear, day)
		if r["status"] == "tamed":
			return n
		if r["status"] == "fled":
			return -1
	return -1


func test_calmable_rules() -> void:
	assert_bool(TameTarget.calmable_stats("wolf", 10.0, 45.0)).is_true()
	assert_bool(TameTarget.calmable_stats("wolf", 40.0, 45.0)).is_false()     # not beaten
	assert_bool(TameTarget.calmable_stats("wolf", 10.0, 45.0, true)).is_false()   # dead
	assert_bool(TameTarget.calmable_stats("stagborn_elk", 20.0, 70.0)).is_true()


func test_never_tamable_list() -> void:
	for sp in ["stagborn_warden", "goblin", "orc", "troll", "rift_wraith", "bandit", "dragon"]:
		assert_bool(TameTarget.never_tamable(sp)).is_true()
		assert_bool(TameTarget.calmable_stats(sp, 1.0, 100.0)).is_false()
	assert_bool(TameTarget.never_tamable("wolf")).is_false()
	var fm: RefCounted = _hub().mod("followers")
	assert_bool(fm.start_taming("w", "rift_wraith")).is_true()
	var r: Dictionary = fm.calm_step("w", 1.0, 1)
	assert_bool(r["ok"]).is_false()
	assert_str(r["status"]).is_equal("wild")


func test_hold_length_shrinks_with_trust_and_fear() -> void:
	var h0 := TameTarget.hold_seconds(0.0, 0.0)
	assert_float(TameTarget.hold_seconds(0.5, 0.0)).is_less(h0)
	assert_float(TameTarget.hold_seconds(0.0, 0.8)).is_less(h0)
	assert_float(TameTarget.hold_seconds(1.0, 1.0)).is_greater_equal(TameTarget.HOLD_MIN)
	assert_float(h0).is_less_equal(TameTarget.HOLD_MAX)


func test_success_curve() -> void:
	var fm: RefCounted = _hub().mod("followers")
	assert_float(fm.calm_chance(0.0, 0.0)).is_less(fm.calm_chance(0.5, 0.0))
	assert_float(fm.calm_chance(0.0, 0.0)).is_less(fm.calm_chance(0.0, 0.9))
	assert_float(fm.calm_chance(1.0, 1.0)).is_less_equal(0.95)
	# 200 wolves: a badly beaten one is tamed in a few holds, a barely beaten one takes longer and flees more.
	var tamed_hi := 0
	var tamed_lo := 0
	var holds_hi := 0
	var holds_lo := 0
	for i in 200:
		var a: int = _holds_to_tame(fm, "hi%d" % i, 0.8, i)
		var b: int = _holds_to_tame(fm, "lo%d" % i, 0.0, i)
		if a > 0:
			tamed_hi += 1
			holds_hi += a
		if b > 0:
			tamed_lo += 1
			holds_lo += b
	assert_int(tamed_hi).is_greater(tamed_lo)
	assert_int(tamed_hi).is_greater(150)                           # most beaten wolves can be won over
	assert_float(float(holds_hi) / tamed_hi).is_less(4.0)          # about two to four holds
	assert_float(float(holds_hi) / tamed_hi).is_less(float(holds_lo) / tamed_lo + 0.001)


func test_never_instant_on_first_hold() -> void:
	var fm: RefCounted = _hub().mod("followers")
	fm.start_taming("x", "wolf")
	assert_str(fm.calm_step("x", 1.0, 3)["status"]).is_not_equal("tamed")   # one success is only half the trust


func test_save_round_trip() -> void:
	var hub := _hub()
	var fm: RefCounted = hub.mod("followers")
	fm.start_taming("wild_wolf_1", "wolf")
	var guard := 0
	while fm.creature("wild_wolf_1")["status"] != "tamed" and guard < 40:
		guard += 1
		fm.calm_step("wild_wolf_1", 0.9, guard)
	assert_str(fm.creature("wild_wolf_1")["status"]).is_equal("tamed")
	assert_bool(fm.assign_role("wild_wolf_1", "guarding", "s0")).is_true()
	var c: Dictionary = fm.creature("wild_wolf_1")
	c["pet"] = true
	c["mode"] = "guard"
	c["post"] = [12.5, -3.0]
	var json := JSON.stringify(hub.serialize())
	var hub2 := _hub()
	hub2.deserialize(JSON.parse_string(json))
	var c2: Dictionary = hub2.mod("followers").creature("wild_wolf_1")
	assert_str(c2["status"]).is_equal("tamed")
	assert_str(c2["role"]).is_equal("guarding")
	assert_str(c2["mode"]).is_equal("guard")
	assert_float(float(c2["post"][0])).is_equal(12.5)
	assert_float(hub2.mod("followers").guard_bonus("s0")).is_greater(0.0)
