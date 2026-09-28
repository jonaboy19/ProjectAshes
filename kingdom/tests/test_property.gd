extends GdUnitTestSuite
## Property ownership: deterministic vacancy selection, rent/buy/sell money
## flow, eviction after missed rent, land tax accrual, storage round trip and
## save/load.

const RAProperty := preload("res://scripts/sim/property.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")

var _gold_before: int
var _day_before: int
var _p: RAProperty


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)
	_gold_before = Game.gold
	_day_before = WorldSim.day
	Game.gold = 1000
	_p = RAProperty.new()


func after_test() -> void:
	Game.gold = _gold_before
	WorldSim.day = _day_before


# --- vacancy -------------------------------------------------------------------------

func test_vacancy_is_about_a_fifth_of_house_lots_and_deterministic() -> void:
	var lots: Array = WorldGen.settlements[0]["plan"]["lots"]
	var house_count := 0
	for lot: Dictionary in lots:
		if BuildingProfiles.is_house(String(lot["asset"])):
			house_count += 1
	var ids := _p.available(0)
	assert_int(ids.size()).is_greater(0)
	assert_int(ids.size()).is_equal(maxi(1, int(floor(house_count * RAProperty.VACANCY_FRACTION))))
	# A second instance (same seed) picks exactly the same lots.
	var p2 := RAProperty.new()
	var ids2 := p2.available(0)
	assert_array(ids).contains_exactly(ids2)


func test_every_vacant_lot_is_actually_a_house_and_priced_by_kind() -> void:
	for lot_id: String in _p.available(0):
		var i := _p.info(lot_id)
		assert_bool(BuildingProfiles.is_house(String(i["asset"]))).is_true()
		assert_int(int(i["price"])).is_greater(0)
		assert_int(int(i["rent"])).is_greater(0)
		assert_int(int(i["tax"])).is_greater(0)
		# The fief's noble house when nobility is wired (Life.nobility), else "Lord of <town>" / the Crown.
		var expected := "Lord of %s" % String(WorldGen.settlements[0]["name"])
		if Life.get("nobility") != null:
			expected = String(Life.nobility.landlord_for_settlement(0)["name"])
		assert_str(String(i["landlord_id"])).is_equal(expected)


# --- buy / sell ------------------------------------------------------------------------

func test_buying_deducts_gold_and_removes_it_from_availability() -> void:
	var lot_id: String = _p.available(0)[0]
	var price := int(_p.info(lot_id)["price"])
	Game.gold = price
	assert_str(_p.can_buy(lot_id)).is_empty()
	assert_str(_p.buy(lot_id)).contains("You now own")
	assert_int(Game.gold).is_equal(0)
	assert_bool(_p.is_owned(lot_id)).is_true()
	assert_array(_p.available(0)).not_contains([lot_id])
	assert_str(_p.buy(lot_id)).contains("Already taken")


func test_cannot_buy_without_enough_gold() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = 1
	assert_str(_p.buy(lot_id)).contains("Needs")
	assert_bool(_p.is_owned(lot_id)).is_false()
	assert_int(Game.gold).is_equal(1)


func test_selling_refunds_eighty_percent_and_frees_the_lot() -> void:
	var lot_id: String = _p.available(0)[0]
	var price := int(_p.info(lot_id)["price"])
	Game.gold = price
	_p.buy(lot_id)
	Game.gold = 0
	assert_str(_p.sell(lot_id)).contains("gold")
	assert_int(Game.gold).is_equal(int(round(price * RAProperty.SELL_FRACTION)))
	assert_bool(_p.is_owned(lot_id)).is_false()
	assert_array(_p.available(0)).contains([lot_id])


func test_cannot_sell_with_items_in_storage() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["price"])
	_p.buy(lot_id)
	Life.give("bread", 1)
	_p.deposit(lot_id, "bread", 1)
	assert_str(_p.sell(lot_id)).contains("Empty your storage")
	_p.withdraw(lot_id, "bread", 1)
	assert_str(_p.sell(lot_id)).contains("gold")
	Life.take("bread", Life.count("bread"))


# --- rent / eviction ---------------------------------------------------------------------

func test_renting_charges_gold_and_grants_a_bed() -> void:
	var lot_id: String = _p.available(0)[0]
	var rent := int(_p.info(lot_id)["rent"])
	Game.gold = rent
	assert_str(_p.rent(lot_id, 1)).contains("rent")
	assert_int(Game.gold).is_equal(0)
	assert_bool(_p.is_held(lot_id)).is_true()
	assert_str(String(_p.home().get("lot_id", ""))).is_equal(lot_id)


func test_missing_two_rent_payments_evicts_and_keeps_storage_for_a_week() -> void:
	var lot_id: String = _p.available(0)[0]
	var rent := int(_p.info(lot_id)["rent"])
	Game.gold = rent
	_p.rent(lot_id, 1)
	Life.give("bread", 3)
	_p.deposit(lot_id, "bread", 3)
	Game.gold = 0
	# First missed payment: still held, debt recorded.
	var msgs := _p.daily(WorldSim.day + RAProperty.DAYS_PER_WEEK)
	assert_bool(_p.is_held(lot_id)).is_true()
	assert_int(int(_p.info(lot_id)["debt"])).is_equal(rent)
	# Second missed payment: evicted.
	msgs = _p.daily(WorldSim.day + RAProperty.DAYS_PER_WEEK * 2)
	assert_array(msgs).is_not_empty()
	assert_bool(_p.is_held(lot_id)).is_false()
	# Storage is kept during the grace period...
	assert_array(_p.storage_of(lot_id)).contains_exactly([{"item": "bread", "qty": 3}])
	assert_array(_p.available(0)).not_contains([lot_id])
	# ...and cleared, the lot vacant again, once it elapses.
	_p.daily(WorldSim.day + RAProperty.DAYS_PER_WEEK * 2 + RAProperty.EVICTION_GRACE_DAYS)
	assert_array(_p.available(0)).contains([lot_id])
	Life.take("bread", Life.count("bread"))


func test_a_repeat_call_the_same_day_does_not_double_charge_debt() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["rent"])
	_p.rent(lot_id, 1)
	var rent := int(_p.info(lot_id)["rent"])
	Game.gold = 0
	var due_day := WorldSim.day + RAProperty.DAYS_PER_WEEK
	_p.daily(due_day)
	assert_int(int(_p.info(lot_id)["debt"])).is_equal(rent)
	_p.daily(due_day)   # same day again: a no-op
	assert_int(int(_p.info(lot_id)["debt"])).is_equal(rent)


# --- land tax --------------------------------------------------------------------------

func test_unpaid_land_tax_accrues_as_debt_and_hurts_trade_reputation() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["price"])
	_p.buy(lot_id)
	var tax := int(_p.info(lot_id)["tax"])
	var rep_before := Life.biography.rep("trade")
	Game.gold = 0
	_p.daily(WorldSim.day + RAProperty.SEASON_DAYS)
	assert_int(int(_p.info(lot_id)["tax_debt"])).is_equal(tax)
	assert_float(Life.biography.rep("trade")).is_less(rep_before)
	Game.gold = tax
	assert_str(_p.pay_due(lot_id)).contains("Paid")
	assert_int(int(_p.info(lot_id)["tax_debt"])).is_equal(0)


func test_owning_pays_tax_automatically_when_gold_allows() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["price"])
	_p.buy(lot_id)
	Game.gold = 1000
	var before := Game.gold
	var tax := int(_p.info(lot_id)["tax"])
	_p.daily(WorldSim.day + RAProperty.SEASON_DAYS)
	assert_int(Game.gold).is_equal(before - tax)
	assert_int(int(_p.info(lot_id)["tax_debt"])).is_equal(0)


# --- storage -----------------------------------------------------------------------------

func test_storage_round_trip() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["price"])
	_p.buy(lot_id)
	Life.give("bread", 5)
	assert_str(_p.deposit(lot_id, "bread", 5)).contains("Stored")
	assert_int(Life.count("bread")).is_equal(0)
	assert_str(_p.withdraw(lot_id, "bread", 2)).contains("Took")
	assert_int(Life.count("bread")).is_equal(2)
	assert_int(int(_p.storage_of(lot_id)[0]["qty"])).is_equal(3)
	_p.withdraw(lot_id, "bread", 3)
	assert_array(_p.storage_of(lot_id)).is_empty()
	Life.take("bread", Life.count("bread"))


func test_the_inn_room_has_a_bed_but_no_storage() -> void:
	if not _p.has_inn_room(0):
		return
	var lot_id := _p.inn_room_id(0)
	Game.gold = int(_p.info(lot_id)["rent"])
	_p.rent_room(0, 1)
	assert_bool(_p.can_store(lot_id)).is_false()
	assert_str(String(_p.home().get("lot_id", ""))).is_equal(lot_id)


# --- serialisation -------------------------------------------------------------------

func test_serialize_round_trip() -> void:
	var lot_id: String = _p.available(0)[0]
	Game.gold = int(_p.info(lot_id)["price"])
	_p.buy(lot_id)
	Life.give("bread", 4)
	_p.deposit(lot_id, "bread", 4)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_p.serialize()))
	var p2 := RAProperty.new()
	p2.deserialize(snap)
	assert_bool(p2.is_owned(lot_id)).is_true()
	assert_int(int(p2.storage_of(lot_id)[0]["qty"])).is_equal(4)
	Life.take("bread", Life.count("bread"))
