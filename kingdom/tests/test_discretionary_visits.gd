extends GdUnitTestSuite
const Brain := preload("res://scripts/population/utility_brain.gd")
const Act := Brain.Act

func _spots(distances: Array) -> SmartObjects:
	var so := SmartObjects.new()
	so.types["visit_test"] = {"slots": [{"stand": [0, 0, 0], "role": "customer"}], "acts": ["shop", "play", "home", "work", "water"], "activity": {"loop": ["Idle"], "duration": [1, 1]}}
	for d: float in distances:
		so.add("visit_test", Transform3D(Basis.IDENTITY, Vector3(d, 0, 0)))
	return so

func _pick(b: RefCounted, so: SmartObjects, action: int, now := 1000) -> Array:
	var f: Dictionary = b.spot_filter(action)
	b._apply_visit_preference(action, f, now)
	return so.find(Vector3.ZERO, f, 60, 42)

func test_completed_discretionary_visit_prefers_nearby_alternative() -> void:
	for action in [Act.SHOP, Act.PLAY, Act.CHORE]:
		var b := Brain.new(42)
		var so := _spots([0.0, 4.0])
		assert_int(_pick(b, so, action)[0]).is_equal(0)
		b.note_completed_visit(action, 0, true, 1000)
		assert_int(_pick(b, so, action)[0]).is_equal(1)

func test_single_station_fallback_and_extra_travel_is_bounded() -> void:
	var b := Brain.new(42)
	b.note_completed_visit(Act.SHOP, 0, true, 1000)
	assert_int(_pick(b, _spots([0.0]), Act.SHOP)[0]).is_equal(0)
	assert_int(_pick(b, _spots([0.0, 20.0]), Act.SHOP)[0]).is_equal(0)

func test_work_water_and_owned_refresh_remain_stable() -> void:
	var b := Brain.new(42)
	for action in [Act.WORK, Act.WATER]:
		b.note_completed_visit(action, 0, true, 1000)
	assert_int(b._completed_visits.size()).is_equal(0)
	var so := _spots([0.0, 4.0])
	so.claim(0, 0, 42)
	b.note_completed_visit(Act.SHOP, 0, true, 1000)
	assert_int(_pick(b, so, Act.SHOP)[0]).is_equal(0)
	# Normal data-tier queries carry no preference filter.
	so.release(42)
	assert_int(so.find(Vector3.ZERO, {"act": "shop"}, 60, 42)[0]).is_equal(0)

func test_interruptions_do_not_record_and_memory_expires() -> void:
	var b := Brain.new(42)
	b.note_completed_visit(Act.SHOP, 0, false, 1000)
	assert_int(b._completed_visits.size()).is_equal(0)
	b.note_completed_visit(Act.SHOP, 0, true, 1000)
	assert_int(_pick(b, _spots([0.0, 4.0]), Act.SHOP, 121000)[0]).is_equal(0)

func test_session_marks_only_completed_duration_as_natural() -> void:
	var so := _spots([0.0])
	so.claim(0, 0, 42)
	var s := so.session(42, 0, 0)
	s._go(SmartObjects.Session.LOOP)
	s.time_left = 0.0
	s.update(0.2, Vector3.ZERO, true)
	assert_bool(s.completed_naturally).is_true()
	so.claim(0, 0, 42)
	s = so.session(42, 0, 0)
	s._go(SmartObjects.Session.LOOP)
	s.interrupt()
	assert_bool(s.completed_naturally).is_false()
	so.claim(0, 0, 42)
	s = so.session(42, 0, 0)
	s._go(SmartObjects.Session.LOOP)
	so.release(42)
	s.update(0.2, Vector3.ZERO, true)
	assert_bool(s.completed_naturally).is_false()
