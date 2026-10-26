extends GdUnitTestSuite
## Element growth by place: weights per spot, hours + tendencies nudges, milestones, save round-trip.

const EP := preload("res://scripts/sim/element_places.gd")
const Tend := preload("res://scripts/sim/tendencies.gd")


func test_weights_by_place() -> void:
	var river := EP.weights(2.0, 0.5, false, 20.0, 0.0, 0.1, false, 1.0)
	assert_float(float(river["water"])).is_equal(1.0)
	assert_float(float(river["earth"])).is_equal(0.0)
	var forge := EP.weights(400.0, 0.0, true, 20.0, 0.0, 0.0, false, 1.0)
	assert_float(float(forge["fire"])).is_equal(1.0)
	var peak := EP.weights(400.0, 0.0, false, 150.0, 0.6, 0.0, false, 2.0)
	assert_float(float(peak["earth"])).is_greater(0.5)
	assert_float(float(peak["wind"])).is_greater(0.5)
	var wood := EP.weights(400.0, 0.0, false, 20.0, 0.0, 0.95, true, 1.0)
	assert_float(float(wood["qi"])).is_greater(0.5)
	assert_float(float(wood["lightning"])).is_equal(1.0)


func test_tick_nudges_tendencies_and_reports_milestones() -> void:
	var e := EP.new()
	var t := Tend.new()
	var before := float(t.elements["water"])
	var lines := e.tick(10.0, {"water": 1.0, "fire": 0.0}, t)
	assert_float(float(t.elements["water"])).is_greater(before)
	assert_float(float(t.elements["fire"])).is_equal(0.4)
	assert_int(lines.size()).is_equal(1)
	assert_str(e.leading()).is_equal("water")


func test_save_round_trip() -> void:
	var e := EP.new()
	e.tick(3.0, {"earth": 1.0}, null)
	var f := EP.new()
	f.deserialize(e.serialize())
	assert_float(float(f.hours["earth"])).is_equal(3.0)
