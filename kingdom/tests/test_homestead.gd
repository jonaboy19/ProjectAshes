extends GdUnitTestSuite
## The homestead: three fixed, free plots outside Ashford, buying deducts gold
## and can't be done twice, placement respects the grid's bounds and overlap,
## building pays gold and materials, crops grow over in-game days, and it all
## survives a JSON round trip.

const Homestead := preload("res://scripts/sim/homestead.gd")

var _gold_before: int
var _day_before: int
var _h: Homestead


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)
	_gold_before = Game.gold
	_day_before = WorldSim.day
	Game.gold = 1000
	_h = Homestead.new()


func after_test() -> void:
	Game.gold = _gold_before
	WorldSim.day = _day_before


# --- plots -------------------------------------------------------------------------

func test_plots_are_free_ground_outside_the_village_and_priced() -> void:
	var plots := _h.plots()
	assert_int(plots.size()).is_equal(3)
	var home: Dictionary = WorldGen.settlements[0]
	for p: Dictionary in plots:
		var pos: Vector2 = p["pos"]
		assert_bool(WorldGen.is_water(pos.x, pos.y)).override_failure_message("plot in water at %s" % pos).is_false()
		assert_float(pos.distance_to(home["pos"])).is_greater(float(home["radius"]) * 1.3)
	assert_int(int(plots[0]["price"])).is_equal(150)
	assert_int(int(plots[1]["price"])).is_equal(300)
	assert_int(int(plots[2]["price"])).is_equal(600)
	# Deterministic: a second instance (fresh RNG, same seed) finds the same spots.
	var h2 := Homestead.new()
	for i in 3:
		assert_vector(h2.plots()[i]["pos"]).is_equal(plots[i]["pos"])


# --- buying --------------------------------------------------------------------------

func test_buying_deducts_gold_and_cannot_buy_twice() -> void:
	Game.gold = 200
	assert_str(_h.can_buy(0)).is_empty()
	_h.buy(0)
	assert_int(Game.gold).is_equal(50)
	assert_bool(_h.is_owned(0)).is_true()
	assert_str(_h.can_buy(0)).contains("already own")
	assert_str(_h.buy(0)).contains("already own")
	assert_int(Game.gold).is_equal(50)      # unchanged by the failed second buy


func test_cannot_buy_without_enough_gold() -> void:
	Game.gold = 100
	assert_str(_h.can_buy(1)).is_empty()      # plot 1 costs 300; can_buy only checks ownership
	assert_str(_h.buy(1)).contains("Needs 300 gold")
	assert_bool(_h.is_owned(1)).is_false()
	assert_int(Game.gold).is_equal(100)


# --- placement -----------------------------------------------------------------------

func test_placement_checks_ownership_bounds_and_overlap() -> void:
	Game.gold = 1000
	_h.buy(0)
	Life.give("plank", 4)
	assert_str(_h.can_place(1, "fence", Vector2i(0, 0), 0)).contains("don't own")
	assert_str(_h.can_place(0, "fence", Vector2i(50, 50), 0)).contains("Outside")
	assert_str(_h.can_place(0, "unicorn_stable", Vector2i(0, 0), 0)).contains("Unknown")
	assert_str(_h.place(0, "fence", Vector2i(2, 2), 0)).is_empty()
	assert_str(_h.can_place(0, "fence", Vector2i(2, 2), 0)).contains("already")
	# A piece that would overlap even partway (a bigger footprint) is also rejected.
	assert_str(_h.can_place(0, "chicken_coop", Vector2i(1, 1), 0)).contains("already")
	assert_str(_h.can_place(0, "chicken_coop", Vector2i(4, 4), 0)).is_empty()
	Life.take("plank", Life.count("plank"))


func test_place_removes_at_the_right_cell_only() -> void:
	Game.gold = 1000
	_h.buy(0)
	Life.give("plank", 2)
	_h.place(0, "fence", Vector2i(0, 0), 0)
	assert_str(_h.remove_at(0, Vector2i(5, 5))).contains("Nothing")
	assert_str(_h.remove_at(0, Vector2i(0, 0))).is_empty()
	assert_int(_h.pieces.size()).is_equal(0)
	Life.take("plank", Life.count("plank"))


# --- costs -------------------------------------------------------------------------

func test_placing_pays_gold_and_consumes_materials() -> void:
	Game.gold = 1000
	_h.buy(0)
	Life.give("plank", 20)
	Life.give("iron_ingot", 4)
	var gold_before := Game.gold
	assert_str(_h.can_afford("cottage")).is_empty()
	assert_str(_h.place(0, "cottage", Vector2i(5, 5), 0)).is_empty()
	assert_int(Game.gold).is_equal(gold_before - int(Homestead.CATALOG["cottage"]["gold"]))
	assert_int(Life.count("plank")).is_equal(0)
	assert_int(Life.count("iron_ingot")).is_equal(0)


func test_cannot_place_without_gold_or_materials() -> void:
	Game.gold = 1000
	_h.buy(0)
	Game.gold = 0
	assert_str(_h.can_afford("well")).contains("gold")
	assert_str(_h.place(0, "well", Vector2i(0, 0), 0)).contains("gold")
	assert_int(_h.pieces.size()).is_equal(0)
	Game.gold = 1000
	assert_str(_h.can_afford("well")).contains("iron_ingot".capitalize())
	assert_int(_h.pieces.size()).is_equal(0)


# --- crops -------------------------------------------------------------------------

func test_crops_grow_over_in_game_days_and_harvest() -> void:
	Game.gold = 1000
	_h.buy(0)
	assert_str(_h.place(0, "crop_plot", Vector2i(1, 1), 0)).is_empty()
	assert_str(_h.plant(0, Vector2i(1, 1), "unobtanium")).contains("can't grow")
	assert_str(_h.plant(0, Vector2i(1, 1), "wheat")).is_empty()
	var cr := _h.crop_at(0, Vector2i(1, 1))
	assert_str(String(cr["crop"])).is_equal("wheat")
	assert_float(_h.growth_stage(cr)).is_equal(0.0)
	assert_bool(_h.is_ready(cr)).is_false()
	assert_str(_h.harvest(0, Vector2i(1, 1))).contains("Not ready")
	WorldSim.day += int(Homestead.CROPS["wheat"]["days"]) - 1
	assert_bool(_h.is_ready(cr)).is_false()
	WorldSim.day += 1
	assert_float(_h.growth_stage(cr)).is_equal(1.0)
	assert_bool(_h.is_ready(cr)).is_true()
	var before := Life.count("wheat")
	var msg := _h.harvest(0, Vector2i(1, 1))
	assert_str(msg).contains("Harvested")
	assert_int(Life.count("wheat")).is_greater(before)
	# Harvested: tilled again, empty, ready to replant.
	var cr2 := _h.crop_at(0, Vector2i(1, 1))
	assert_str(String(cr2["crop"])).is_empty()
	Life.take("wheat", Life.count("wheat"))


func test_watering_speeds_growth() -> void:
	Game.gold = 1000
	_h.buy(0)
	_h.place(0, "crop_plot", Vector2i(2, 2), 0)
	_h.plant(0, Vector2i(2, 2), "cabbage")
	var cr := _h.crop_at(0, Vector2i(2, 2))
	var dry_days := _h.grow_days(cr)
	assert_str(_h.water(0, Vector2i(2, 2))).is_empty()
	assert_bool(bool(cr["watered"])).is_true()
	assert_float(_h.grow_days(cr)).is_less(dry_days)
	assert_str(_h.water(0, Vector2i(2, 2))).contains("Already watered")


# --- serialisation -------------------------------------------------------------------

func test_serialize_round_trip() -> void:
	Game.gold = 1000
	_h.buy(0)
	_h.buy(1)
	Life.give("plank", 2)
	assert_str(_h.place(0, "fence", Vector2i(3, 3), 1)).is_empty()
	assert_str(_h.place(0, "crop_plot", Vector2i(6, 6), 0)).is_empty()
	assert_str(_h.plant(0, Vector2i(6, 6), "wheat")).is_empty()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_h.serialize()))
	var h2 := Homestead.new()
	h2.deserialize(snap)
	assert_bool(h2.is_owned(0)).is_true()
	assert_bool(h2.is_owned(1)).is_true()
	assert_bool(h2.is_owned(2)).is_false()
	assert_int(h2.pieces.size()).is_equal(1)
	assert_str(String(h2.pieces[0]["kind"])).is_equal("fence")
	assert_int(int(h2.pieces[0]["rot"])).is_equal(1)
	assert_vector(Vector2(h2.pieces[0]["cell"])).is_equal(Vector2(3, 3))
	assert_int(h2.crops.size()).is_equal(1)
	assert_str(String(h2.crops[0]["crop"])).is_equal("wheat")
	# The restored state still enforces overlap correctly.
	assert_str(h2.can_place(0, "gate", Vector2i(3, 3), 0)).contains("already")
	Life.take("plank", Life.count("plank"))
