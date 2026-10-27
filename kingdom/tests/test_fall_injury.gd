extends GdUnitTestSuite
## Fall injuries (blueprint §3, WP-01): RAInjuries.fall_injury(height, rolled) and the speed effect the player reads.


func test_short_falls_are_free() -> void:
	assert_str(RAInjuries.fall_injury(1.5, false)).is_equal("")
	assert_str(RAInjuries.fall_injury(3.9, false)).is_equal("")


func test_height_bands() -> void:
	assert_str(RAInjuries.fall_injury(4.5, false)).is_equal("sprained_ankle")
	assert_str(RAInjuries.fall_injury(7.0, false)).is_equal("bruised_ribs")
	assert_str(RAInjuries.fall_injury(10.0, false)).is_equal("broken_leg")


func test_landing_roll_takes_the_edge_off() -> void:
	assert_str(RAInjuries.fall_injury(5.5, true)).is_equal("")
	assert_str(RAInjuries.fall_injury(10.0, true)).is_equal("bruised_ribs")


func test_leg_injuries_slow_the_body() -> void:
	var inj := RAInjuries.new()
	inj.add("broken_leg", 1)
	assert_float(float(inj.effects().get("speed", 0.0))).is_less(-0.3)
	var inj2 := RAInjuries.new()
	inj2.add("sprained_ankle", 1)
	assert_float(float(inj2.effects().get("speed", 0.0))).is_equal_approx(-0.2, 0.001)
