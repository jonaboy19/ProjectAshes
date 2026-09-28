extends GdUnitTestSuite
## Farming as a career path: leasing a plot from the landlord (rent and harvest
## share), crop season windows, soil quality affecting yield, hired hands
## working and quitting when unpaid, estate level thresholds, livestock
## produce, and it all surviving a JSON round trip. Homestead itself (buying,
## placing, plain crop growth) stays covered by test_homestead.gd.

const Homestead := preload("res://scripts/sim/homestead.gd")
const Seasons := preload("res://scripts/sim/seasons.gd")

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


# --- leasing -------------------------------------------------------------------------

func test_leasing_is_not_ownership_and_blocks_buying() -> void:
	assert_str(_h.can_lease(1)).is_empty()
	assert_str(_h.lease(1)).contains("lease")
	assert_bool(_h.is_leased(1)).is_true()
	assert_bool(_h.is_owned(1)).is_false()
	assert_bool(_h.owns_or_leases(1)).is_true()
	assert_str(_h.can_lease(1)).contains("already lease")
	assert_str(_h.can_buy(1)).contains("lease")
	# A leased plot can be built on, exactly like an owned one.
	assert_str(_h.can_place(1, "crop_plot", Vector2i(0, 0), 0)).is_empty()


func test_lease_rent_is_charged_once_a_season_and_lost_if_unpaid() -> void:
	_h.lease(0)
	var gold_before := Game.gold
	# Not due yet: a day later, nothing happens.
	WorldSim.day += 1
	assert_int(_h.daily_tick(WorldSim.day).size()).is_equal(0)
	assert_int(Game.gold).is_equal(gold_before)
	# A season on, rent falls due.
	WorldSim.day += Seasons.DAYS_PER_SEASON
	var msgs := _h.daily_tick(WorldSim.day)
	assert_int(msgs.size()).is_equal(1)
	assert_str(msgs[0]).contains("rent")
	assert_int(Game.gold).is_equal(gold_before - Homestead.LEASE_RENT)
	assert_bool(_h.is_leased(0)).is_true()
	# Next season, no gold to pay: the landlord takes the plot back.
	Game.gold = 0
	WorldSim.day += Seasons.DAYS_PER_SEASON
	var msgs2 := _h.daily_tick(WorldSim.day)
	assert_str(msgs2[0]).contains("takes back")
	assert_bool(_h.is_leased(0)).is_false()


func test_harvest_share_goes_to_the_landlord_on_a_leased_plot() -> void:
	_h.lease(1)
	assert_str(_h.place(1, "crop_plot", Vector2i(1, 1), 0)).is_empty()
	assert_str(_h.plant(1, Vector2i(1, 1), "wheat")).is_empty()
	assert_str(_h.water(1, Vector2i(1, 1))).is_empty()
	assert_str(_h.weed(1, Vector2i(1, 1))).is_empty()
	WorldSim.day += int(Homestead.CROPS["wheat"]["days"])
	var cr := _h.crop_at(1, Vector2i(1, 1))
	assert_bool(_h.is_ready(cr)).is_true()
	var base := 2 + 1 + Homestead.WEEDED_BONUS + (hash([1, Vector2i(1, 1), WorldSim.day]) % 2)
	var n := maxi(1, int(round(float(base) * _h.soil_quality(1))))
	var share := mini(n - 1, int(floor(float(n) * Homestead.LEASE_SHARE)))
	var before := Life.count("wheat")
	var msg := _h.harvest(1, Vector2i(1, 1))
	assert_int(Life.count("wheat") - before).is_equal(n - share)
	if share > 0:
		assert_str(msg).contains("landlord")
	Life.take("wheat", Life.count("wheat"))


# --- crop season windows ---------------------------------------------------------------

func test_crop_season_windows_restrict_planting_new_crops() -> void:
	_h.buy(0)
	assert_str(_h.place(0, "crop_plot", Vector2i(1, 1), 0)).is_empty()
	WorldSim.day = Seasons.first_day_of(Seasons.SPRING) + 5
	assert_bool(_h.can_plant_now("hops")).is_false()
	assert_str(_h.plant(0, Vector2i(1, 1), "hops")).contains("season")
	WorldSim.day = Seasons.first_day_of(Seasons.SUMMER) + 5
	assert_bool(_h.can_plant_now("hops")).is_true()
	assert_str(_h.plant(0, Vector2i(1, 1), "hops")).is_empty()


func test_wheat_and_turnip_are_plantable_in_any_season() -> void:
	_h.buy(0)
	assert_str(_h.place(0, "crop_plot", Vector2i(2, 2), 0)).is_empty()
	WorldSim.day = Seasons.first_day_of(Seasons.WINTER) + 3
	assert_bool(_h.can_plant_now("wheat")).is_true()
	assert_str(_h.plant(0, Vector2i(2, 2), "wheat")).is_empty()
	assert_bool(_h.can_plant_now("turnip")).is_true()      # winter-hardy


# --- soil quality ----------------------------------------------------------------------

func test_soil_quality_is_seeded_deterministic_and_in_range() -> void:
	var q0 := _h.soil_quality(0)
	assert_float(q0).is_between(0.6, 1.2)
	assert_float(_h.soil_quality(0)).is_equal(q0)     # cached
	var h2 := Homestead.new()
	assert_float(h2.soil_quality(0)).is_equal(q0)     # same seed -> same soil, no state needed


# --- hired hands -------------------------------------------------------------------------

func test_hiring_needs_land_and_respects_the_cap() -> void:
	assert_str(_h.can_hire(0)).contains("don't own")
	_h.buy(0)
	assert_str(_h.can_hire(0)).is_empty()
	# Hiring more hands can itself grow the estate (a "farm" needs 2+ workers),
	# which raises the cap — hire until can_hire actually refuses, then check
	# the count matches whatever cap that growth landed on.
	var hired := 0
	while _h.can_hire(0) == "" and hired < 100:
		assert_str(_h.hire(0, "Hand%d" % hired)).contains("joins")
		hired += 1
	assert_int(_h.workers.size()).is_equal(_h.max_workers())
	assert_str(_h.can_hire(0)).contains("more than")
	assert_str(_h.hire(0, "One too many")).contains("more than")


func test_hands_work_the_fields_daily_and_quit_when_unpaid() -> void:
	_h.buy(0)
	assert_str(_h.place(0, "crop_plot", Vector2i(3, 3), 0)).is_empty()
	assert_str(_h.plant(0, Vector2i(3, 3), "cabbage")).is_empty()
	_h.hire(0, "Steady Hand", Homestead.HAND_WAGE_MIN)
	# Ready to harvest, wages affordable: the hand waters/weeds/harvests it
	# straight into farm storage (not the player's own Inventory) and gets paid.
	WorldSim.day += int(Homestead.CROPS["cabbage"]["days"]) + 2
	Game.gold = 1000
	_h.daily_tick(WorldSim.day)
	assert_int(int(_h.workers[0]["unpaid_days"])).is_equal(0)
	assert_int(_h.storage_used()).is_greater(0)
	# No gold for HANDS_QUIT_DAYS running: the hand quits.
	Game.gold = 0
	for i in Homestead.HANDS_QUIT_DAYS:
		WorldSim.day += 1
		_h.daily_tick(WorldSim.day)
	assert_int(_h.workers.size()).is_equal(0)


# --- estate level ------------------------------------------------------------------------

func test_estate_level_grows_with_plots_workers_and_buildings() -> void:
	Game.gold = 5000
	assert_int(_h.estate_level()).is_equal(0)
	assert_str(_h.estate_level_name()).is_equal("Smallholding")
	_h.buy(0)
	_h.hire(0, "A")
	_h.hire(0, "B")
	assert_int(_h.estate_level()).is_equal(1)
	_h.buy(1)
	_h.hire(1, "C")
	_h.hire(1, "D")
	Life.give("plank", 24)
	Life.give("iron_ingot", 2)
	assert_str(_h.place(0, "granary", Vector2i(0, 0), 0)).is_empty()
	Life.give("plank", 20)
	Life.give("iron_ingot", 6)
	assert_str(_h.place(0, "mill", Vector2i(3, 0), 0)).is_empty()
	assert_int(_h.estate_level()).is_equal(2)
	assert_str(_h.estate_level_name()).is_equal("Estate")
	Life.take("plank", Life.count("plank"))
	Life.take("iron_ingot", Life.count("iron_ingot"))


# --- livestock and the mill --------------------------------------------------------------

func test_livestock_and_mill_produce_into_storage_daily() -> void:
	_h.buy(0)
	Life.give("plank", 8)
	assert_str(_h.place(0, "chicken_coop", Vector2i(0, 0), 0)).is_empty()
	Life.give("plank", 8)
	assert_str(_h.place(0, "pig_sty", Vector2i(3, 0), 0)).is_empty()
	for i in 10:
		WorldSim.day += 1
		_h.daily_tick(WorldSim.day)
	assert_int(int(_h.storage.get("egg", 0))).is_greater(0)
	assert_int(int(_h.storage.get("pork", 0))).is_greater(0)
	Life.take("plank", Life.count("plank"))
	# A mill grinds stored wheat into flour.
	_h.storage["wheat"] = 10
	Life.give("plank", 20)
	Life.give("iron_ingot", 6)
	assert_str(_h.place(0, "mill", Vector2i(5, 5), 0)).is_empty()
	WorldSim.day += 1
	_h.daily_tick(WorldSim.day)
	assert_int(int(_h.storage.get("wheat", 0))).is_less(10)
	assert_int(int(_h.storage.get("flour", 0))).is_greater(0)
	Life.take("plank", Life.count("plank"))
	Life.take("iron_ingot", Life.count("iron_ingot"))


# --- selling storage -----------------------------------------------------------------

func test_sell_storage_pays_gold_and_empties_it() -> void:
	_h.storage["wheat"] = 3
	var gold_before := Game.gold
	var r := _h.sell_storage("wheat", 3)
	assert_int(int(r["sold"])).is_equal(3)
	assert_int(int(_h.storage.get("wheat", 0))).is_equal(0)
	assert_int(Game.gold).is_equal(gold_before + int(r["gold"]))


# --- serialisation ---------------------------------------------------------------------

func test_serialize_round_trip_leasing_workers_and_storage() -> void:
	_h.buy(0)
	_h.lease(1)
	_h.hire(0, "Hand", Homestead.HAND_WAGE_MIN, 0.4)
	_h.storage["wheat"] = 12
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_h.serialize()))
	var h2 := Homestead.new()
	h2.deserialize(snap)
	assert_bool(h2.is_owned(0)).is_true()
	assert_bool(h2.is_leased(1)).is_true()
	assert_bool(h2.is_owned(1)).is_false()
	assert_int(h2.workers.size()).is_equal(1)
	assert_str(String(h2.workers[0]["name"])).is_equal("Hand")
	assert_int(int(h2.workers[0]["wage"])).is_equal(Homestead.HAND_WAGE_MIN)
	assert_int(int(h2.storage.get("wheat", 0))).is_equal(12)
