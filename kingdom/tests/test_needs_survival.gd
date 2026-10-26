extends GdUnitTestSuite
## RANeeds thirst + body warmth: drain, exposure targets, penalties, save round-trip.

const Needs := preload("res://scripts/sim/needs.gd")


func test_thirst_drains_and_drink_restores() -> void:
	var n := Needs.new()
	n.water = 50.0
	n.tick(5.0)
	assert_float(n.water).is_equal_approx(37.5, 0.01)
	n.drink(40.0)
	assert_float(n.water).is_equal_approx(77.5, 0.01)


func test_cold_wet_night_chills_fire_warms() -> void:
	var n := Needs.new()
	n.warmth = 80.0
	n.env = Needs.exposure(true, false, true, true, 50.0, false, false)
	n.tick(6.0)
	assert_float(n.warmth).is_less(20.0)
	n.env = Needs.exposure(true, false, true, false, 50.0, false, true)
	n.tick(8.0)
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


func test_encumbrance_slows_and_tires() -> void:
	var n := Needs.new()
	n.load_ratio = 0.9
	assert_float(n.speed()).is_equal(1.0)
	n.load_ratio = 1.2
	assert_float(n.speed()).is_less(0.75)
	assert_float(n.stamina_regen()).is_less(1.0)
	assert_str(n.load_label()).is_equal("Overburdened")
	n.load_ratio = 3.0
	assert_float(n.speed()).is_equal_approx(0.45, 0.001)


func test_sleep_drains_thirst_at_half_rate_and_warms() -> void:
	var n := Needs.new()
	n.water = 60.0
	n.warmth = 10.0
	n.sleep(8.0, 1.0)
	assert_float(n.water).is_equal_approx(60.0 - 10.0, 0.01)
	assert_float(n.warmth).is_greater_equal(80.0)


func test_revive_floor_breaks_death_loops() -> void:
	var n := Needs.new()
	n.food = 0.0
	n.water = 0.0
	n.warmth = 0.0
	n.revive_floor()
	assert_float(n.starvation()).is_equal(0.0)
	assert_float(n.water).is_equal(30.0)
