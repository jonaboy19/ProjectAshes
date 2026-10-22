extends GdUnitTestSuite
## Persistent deposits: overlay in the WorldState delta store, depletion, closed-form regrowth,
## catch-up equals stepping, save round trip, untouched nodes cost nothing.

const Deposits := preload("res://scripts/world/deposits.gd")
const WorldState := preload("res://scripts/world/world_state.gd")

var ws: RefCounted
var dep: RefCounted
var def: Dictionary


func before_test() -> void:
	ws = WorldState.new()
	dep = Deposits.new(ws)
	def = Deposits.make_def("ore", "iron_ore", {"cap": 8, "regrow": 2.0, "level": 2})


func test_untouched_deposit_is_full_and_stores_nothing() -> void:
	var id := Deposits.key("mine", "ore", 0)
	assert_int(dep.units(id, def, 1)).is_equal(8)
	assert_int(ws.size()).is_equal(0)


func test_consume_depletes_and_writes_only_overlay() -> void:
	var id := Deposits.key("mine", "ore", 0)
	assert_int(dep.consume(id, def, 3, 5)).is_equal(3)
	assert_int(dep.units(id, def, 5)).is_equal(5)
	assert_int(ws.size()).is_equal(1)
	var st: Dictionary = ws.get_state(id)
	assert_float(float(st["q"])).is_equal_approx(5.0, 0.001)
	assert_int(int(st["d"])).is_equal(5)
	assert_int(dep.consume(id, def, 99, 5)).is_equal(5)
	assert_bool(dep.is_depleted(id, def, 5)).is_true()
	assert_int(dep.consume(id, def, 1, 5)).is_equal(0)


func test_regrows_per_day_closed_form() -> void:
	var id := Deposits.key("mine", "ore", 1)
	dep.consume(id, def, 8, 10)
	assert_int(dep.units(id, def, 10)).is_equal(0)
	assert_int(dep.units(id, def, 11)).is_equal(2)
	assert_int(dep.units(id, def, 12)).is_equal(4)
	assert_int(dep.units(id, def, 14)).is_equal(8)
	assert_int(dep.units(id, def, 400)).is_equal(8)      # capped, no overflow
	assert_int(dep.units(id, def, 9)).is_equal(0)        # a clock that went back never adds units


func test_fractional_regrow_catch_up_matches_stepping() -> void:
	var slow := Deposits.make_def("herb", "healing_herb", {"cap": 10, "regrow": 0.7})
	var id := "x/dep/herb/0"
	dep.consume(id, slow, 10, 1)
	var jump: int = dep.units(id, slow, 8)       # catch-up in one step: 0 + 7*0.7 = 4.9 -> 4
	assert_int(jump).is_equal(4)
	# Stepping: take 1 unit each day when available, compare with the closed form total.
	var ws2: RefCounted = WorldState.new()
	var dep2: RefCounted = Deposits.new(ws2)
	dep2.consume(id, slow, 10, 1)
	var got := 0
	for day in range(2, 9):
		got += dep2.consume(id, slow, 1, day)
	assert_int(got).is_equal(4)          # 4.9 units regrown over 7 days, one taken whenever >= 1 is there


func test_fully_regrown_after_partial_take_clears_overlay() -> void:
	var id := Deposits.key("mine", "ore", 2)
	dep.consume(id, def, 1, 3)
	assert_int(ws.size()).is_equal(1)
	# Taking from a regrown node starts a fresh overlay only for what is left.
	assert_int(dep.consume(id, def, 0, 9)).is_equal(0)
	assert_int(dep.prune("mine", {id: def}, 3)).is_equal(0)
	assert_int(dep.prune("mine", {id: def}, 9)).is_equal(1)
	assert_int(ws.size()).is_equal(0)


func test_quality_fixed_per_id_and_in_range() -> void:
	var id := Deposits.key("mine", "ore", 3)
	var q := Deposits.quality(id, def)
	assert_int(q).is_between(int(def["qmin"]), int(def["qmax"]))
	assert_int(Deposits.quality(id, def)).is_equal(q)
	dep.consume(id, def, 2, 4)
	assert_int(int(dep.node(id, def, 4)["quality"])).is_equal(q)
	assert_int(int(dep.node(id, def, 4)["qty"])).is_equal(6)


func test_commit_from_session_result() -> void:
	var id := Deposits.key("mine", "ore", 4)
	var GS := preload("res://scripts/sim/gather_session.gd")
	var s := GS.new()
	assert_bool(s.start(dep.node(id, def, 2), 4, 1, 12)).is_true()
	var res: Dictionary = s.run(3, false)
	var n: int = dep.commit(id, def, res, 2)
	assert_int(n).is_equal(int(res["count"]))
	assert_int(dep.units(id, def, 2)).is_equal(8 - n)


func test_survives_json_save_round_trip() -> void:
	var id := Deposits.key("mine", "ore", 5)
	dep.consume(id, def, 5, 20)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(ws.snapshot()))
	var ws2: RefCounted = WorldState.new()
	ws2.restore(snap)
	var dep2: RefCounted = Deposits.new(ws2)
	assert_int(dep2.units(id, def, 20)).is_equal(3)
	assert_int(dep2.units(id, def, 22)).is_equal(7)


func test_many_deposits_stay_small() -> void:
	for i in 300:
		dep.consume(Deposits.key("region%d" % (i % 5), "ore", i), def, 1 + i % 4, 7)
	var bytes := JSON.stringify(ws.snapshot()).length()
	assert_int(bytes).is_less(60 * 1024)
