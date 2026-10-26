extends GdUnitTestSuite
## RANeeds thirst + body warmth: drain, exposure targets, penalties, save round-trip.

const Needs := preload("res://scripts/sim/needs.gd")


func test_thirst_drains_and_drink_restores() -> void:
	var n := Needs.new()
	n.water = 50.0
	n.tick(5.0)
	assert_float(n.water).is_equal_approx(30.0, 0.01)
	n.drink(40.0)
	assert_float(n.water).is_equal_approx(70.0, 0.01)


func test_cold_wet_night_chills_fire_warms() -> void:
	var n := Needs.new()
	n.warmth = 80.0
	n.env = Needs.exposure(true, false, true, true, 50.0, false, false)
	n.tick(3.0)
	assert_float(n.warmth).is_less(20.0)
	n.env = Needs.exposure(true, false, true, false, 50.0, false, true)
	n.tick(3.0)
	assert_float(n.warmth).is_greater(80.0)


func test_shelter_floors_the_target() -> void:
	assert_float(Needs.warmth_target(Needs.exposure(true, true, true, false, 200.0, true, false))).is_greater_equal(70.0)


func test_penalties() -> void:
	var n := Needs.new()
	n.water = 0.0
	n.warmth = 0.0
	assert_float(n.starvation()).is_greater(0.0)
	assert_float(n.stamina_regen()).is_less(0.5)
	assert_float(n.speed()).is_less(1.0)
	assert_str(n.thirst_label()).is_equal("Parched")
	assert_str(n.warmth_label()).is_equal("Freezing")


func test_save_round_trip_and_old_saves() -> void:
	var n := Needs.new()
	n.water = 12.0
	n.warmth = 33.0
	var m := Needs.new()
	m.deserialize(n.serialize())
	assert_float(m.water).is_equal(12.0)
	assert_float(m.warmth).is_equal(33.0)
	var old := Needs.new()
	old.deserialize({"food": 10.0, "rest": 20.0})
	assert_float(old.water).is_equal(85.0)
