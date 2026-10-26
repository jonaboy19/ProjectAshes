extends GdUnitTestSuite
## Per-day/time deterministic variety for equivalent smart-object animation takes.

const SmartObjects := preload("res://scripts/living_world/smart_objects.gd")


func test_same_day_variant_order_is_stable_and_uses_each_take_once() -> void:
	var old_day := int(WorldSim.day)
	WorldSim.day = 12
	var a := _loop_sequence(12, 502)
	var b := _loop_sequence(12, 502)
	WorldSim.day = old_day
	assert_array(a).is_equal(b)
	assert_int(a.size()).is_equal(3)
	assert_bool(a[0] != a[1] and a[1] != a[2] and a[0] != a[2]).is_true()


func test_first_take_changes_on_adjacent_days() -> void:
	var old_day := int(WorldSim.day)
	var a := _loop_sequence(20, 811)
	var b := _loop_sequence(21, 811)
	WorldSim.day = old_day
	assert_bool(a[0] != b[0]).is_true()


func test_same_day_visits_at_different_times_get_different_sequences() -> void:
	var old_day := int(WorldSim.day)
	var old_time := float(WorldSim.time_of_day)
	var morning := _loop_sequence(42, 933, 8.0)
	var afternoon := _loop_sequence(42, 933, 15.0)
	WorldSim.day = old_day
	WorldSim.time_of_day = old_time
	assert_bool(morning != afternoon).is_true()


func test_activity_duration_and_cycles_keep_the_original_rng_stream() -> void:
	var old_day := int(WorldSim.day)
	WorldSim.day = 37
	var so := SmartObjects.new()
	var spot := so.add("field_row", Transform3D.IDENTITY)
	var person := 928
	var session := so.session(person, spot, 0)
	var expected := RandomNumberGenerator.new()
	expected.seed = hash(person * 7919 + spot)
	var duration := expected.randf_range(40.0, 120.0)
	var cycles := expected.randi_range(2, 4)
	WorldSim.day = old_day
	assert_float(session.time_left).is_equal_approx(duration, 0.0001)
	assert_int(session.cycles_left).is_equal(cycles)


func _loop_sequence(day: int, person: int, hour := -1.0) -> Array[String]:
	WorldSim.day = day
	if hour >= 0.0:
		WorldSim.time_of_day = hour
	var so := SmartObjects.new()
	var spot := so.add("field_row", Transform3D.IDENTITY)
	var session := so.session(person, spot, 0)
	var clips: Array[String] = []
	for _i in 3:
		session._go(SmartObjects.Session.LOOP)
		clips.append(session.clip)
	return clips
