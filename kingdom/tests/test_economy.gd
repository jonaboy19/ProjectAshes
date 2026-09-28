extends GdUnitTestSuite
## Regional economy: production/consumption drift, season/war price events,
## trade-route ranking, caravan risk determinism, contracts and save/load
## (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, Merchant career + Living world sim).

const RAEconomy := preload("res://scripts/sim/economy.gd")
const RACaravans := preload("res://scripts/sim/caravans.gd")
const RAMarket := preload("res://scripts/sim/market.gd")


func before() -> void:
	WorldGen.setup(1066)


func _village_id() -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "village" and int(s["id"]) != 0:
			return int(s["id"])
	return -1


## A "town" if this seed rolled one, else a second village (some seeds --
## 1066 included -- happen to roll none; the tests that use this only need
## *some* other settlement with its own market).
func _town_id() -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "town":
			return int(s["id"])
	var skip := _village_id()
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) != 0 and int(s["id"]) != skip and String(s["kind"]) != "castle":
			return int(s["id"])
	return -1


func _capital_id() -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			return int(s["id"])
	return -1


func _economy() -> RAEconomy:
	var eco := RAEconomy.new()
	eco.setup(0)
	eco.bind_home_market(0, RAMarket.new())
	return eco


func _idle_ctx() -> Dictionary:
	return {"season": "spring", "festival": false, "at_war": false, "mine_opened": false}


# --- production & consumption drift ---------------------------------------------------

func test_production_pulls_understocked_goods_up() -> void:
	var eco := _economy()
	var vid := _village_id()
	assert_int(vid).is_greater(-1)
	var m: RAMarket = eco.markets[vid]
	m.stock["wheat"] = 2      # deliberately short of target
	eco.tick_hour(6.0, _idle_ctx())
	assert_int(int(m.stock["wheat"])).is_greater(2)


func test_consumption_drains_imported_goods_with_no_local_production() -> void:
	var eco := _economy()
	var vid := _village_id()
	var m: RAMarket = eco.markets[vid]
	assert_int(int(m.produce.get("tools", -1))).is_equal(0)   # a village imports tools, makes none
	var before_stock := int(m.stock["tools"])
	eco.tick_hour(24.0, _idle_ctx())
	assert_int(int(m.stock["tools"])).is_less(before_stock)


# --- season & war events --------------------------------------------------------------

func test_winter_raises_food_prices() -> void:
	var eco := _economy()
	var vid := _village_id()
	var m: RAMarket = eco.markets[vid]
	eco.tick_hour(0.0, {"season": "spring", "festival": false, "at_war": false, "mine_opened": false})
	var spring_price := m.price("wheat")
	eco.tick_hour(0.0, {"season": "winter", "festival": false, "at_war": false, "mine_opened": false})
	assert_int(m.price("wheat")).is_greater(spring_price)


func test_harvest_lowers_grain() -> void:
	var eco := _economy()
	var vid := _village_id()
	var m: RAMarket = eco.markets[vid]
	eco.tick_hour(0.0, _idle_ctx())
	var normal := m.price("wheat")
	eco.tick_hour(0.0, {"season": "autumn", "festival": false, "at_war": false, "mine_opened": false})
	assert_int(m.price("wheat")).is_less(normal)


func test_war_raises_weapons_and_grain() -> void:
	var eco := _economy()
	var cid := _capital_id()
	var m: RAMarket = eco.markets[cid]
	eco.tick_hour(0.0, _idle_ctx())
	var peace_price := m.price("weapons")
	eco.tick_hour(0.0, {"season": "spring", "festival": false, "at_war": true, "mine_opened": false})
	assert_int(m.price("weapons")).is_greater(peace_price)


func test_festival_raises_ale() -> void:
	var eco := _economy()
	var tid := _town_id()
	var m: RAMarket = eco.markets[tid]
	if not m.base_price.has("ale"):
		m.add_good("ale", 4, 25, 0)
	eco.tick_hour(0.0, _idle_ctx())
	var normal := m.price("ale")
	eco.tick_hour(0.0, {"season": "spring", "festival": true, "at_war": false, "mine_opened": false})
	assert_int(m.price("ale")).is_greater(normal)


func test_new_mine_lowers_ore() -> void:
	var eco := _economy()
	var mine_id := -1
	for id in eco.markets:
		if (eco.markets[id] as RAMarket).base_price.has("iron_ore"):
			mine_id = id
	assert_int(mine_id).is_greater(-1)
	var m: RAMarket = eco.markets[mine_id]
	eco.tick_hour(0.0, _idle_ctx())
	var normal := m.price("iron_ore")
	eco.tick_hour(0.0, {"season": "spring", "festival": false, "at_war": false, "mine_opened": true})
	assert_int(m.price("iron_ore")).is_less(normal)


func test_road_danger_raises_import_prices() -> void:
	var eco := _economy()
	var vid := _village_id()
	var m: RAMarket = eco.markets[vid]
	eco.tick_hour(0.0, _idle_ctx())
	var calm := m.price("tools")   # a village imports tools
	eco.road_risk[vid] = 1.0
	eco.tick_hour(0.0, _idle_ctx())
	assert_int(m.price("tools")).is_greater(calm)


# --- trade routes & rumours -------------------------------------------------------------

func test_best_trade_routes_orders_by_profit() -> void:
	var eco := _economy()
	var vid := _village_id()
	var tid := _town_id()
	# Ashford (home, id 0) makes bread cheap and stockpiled; a town has none and
	# would pay well for it -- an obviously good route versus everything else.
	var home: RAMarket = eco.markets[0]
	home.add_good("bread", 2, 100, 0)
	home.stock["bread"] = 100
	var town: RAMarket = eco.markets[tid]
	town.add_good("bread", 2, 100, 0)
	town.stock["bread"] = 2
	var routes := eco.best_trade_routes(0, 10)
	assert_bool(routes.is_empty()).is_false()
	var best: Dictionary = routes[0]
	assert_str(String(best["item"])).is_equal("bread")
	assert_int(int(best["to"])).is_equal(tid)
	for i in range(routes.size() - 1):
		assert_float(float(routes[i]["score"])).is_greater_equal(float(routes[i + 1]["score"]))
	assert_int(vid).is_greater(-1)   # sanity: a village exists too, just not the best route here


func test_rumour_prices_reports_a_large_gap() -> void:
	var eco := _economy()
	var vid := _village_id()
	var tid := _town_id()
	eco.markets[vid].add_good("wool", 5, 20, 0)
	eco.markets[vid].stock["wool"] = 100     # glutted, cheap
	eco.markets[tid].add_good("wool", 5, 20, 0)
	eco.markets[tid].stock["wool"] = 1       # scarce, expensive
	var rumours := eco.rumour_prices()
	var found := false
	for r: String in rumours:
		if r.findn("wool") >= 0:
			found = true
	assert_bool(found).is_true()


# --- caravans ---------------------------------------------------------------------------

func test_caravan_resolution_is_deterministic_per_seed() -> void:
	var a := RACaravans.new()
	var b := RACaravans.new()
	var vid := _village_id()
	var ca := a.send(0, vid, {"wool": 10}, 1, "rural", 0.5, 0.0, 777)
	var cb := b.send(0, vid, {"wool": 10}, 1, "rural", 0.5, 0.0, 777)
	assert_float(ca["risk"]).is_equal_approx(cb["risk"], 0.0001)
	var ra := a.tick(ca["arrive"])[0]
	var rb := b.tick(cb["arrive"])[0]
	assert_bool(ra["ambushed"]).is_equal(rb["ambushed"])
	assert_int(ra["revenue"]).is_equal(rb["revenue"])


func test_more_guards_reduce_caravan_risk() -> void:
	var c := RACaravans.new()
	var vid := _village_id()
	var unguarded := c.send(0, vid, {"wool": 5}, 0, "frontier", 0.8, 0.0, 1)
	var guarded := c.send(0, vid, {"wool": 5}, 5, "frontier", 0.8, 0.0, 1)
	assert_float(float(guarded["risk"])).is_less(float(unguarded["risk"]))


func test_caravan_sells_surviving_cargo_into_destination_market() -> void:
	var eco := _economy()
	var vid := _village_id()
	eco.markets[vid].add_good("wool", 5, 20, 0)
	var c := eco.caravans.send(0, vid, {"wool": 4}, 3, "rural", 0.0, 0.0, 42)
	var reports := eco.caravans.tick(c["arrive"], eco)
	assert_int(reports.size()).is_equal(1)
	assert_bool(bool(reports[0]["ok"])).is_true()


# --- contracts --------------------------------------------------------------------------

func test_contract_offered_for_a_settlement_short_of_a_good() -> void:
	var eco := _economy()
	var vid := _village_id()
	var m: RAMarket = eco.markets[vid]
	m.stock["wool"] = 0   # well short of target, produced locally
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var found := false
	for _i in 20:
		var c := eco.roll_contract(1, rng)
		if not c.is_empty() and int(c["to"]) == vid and String(c["item"]) == "wool":
			found = true
			break
		if not c.is_empty():
			eco.contracts.erase(eco.contracts.back())   # only one offer open per roll in this test
	assert_bool(found).is_true()


func test_contract_completes_once_fully_delivered() -> void:
	var eco := _economy()
	var vid := _village_id()
	eco.markets[vid].stock["wool"] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := eco.roll_contract(1, rng)
	assert_bool(c.is_empty()).is_false()
	var r := eco.complete_contract(int(c["id"]), 1)
	assert_bool(bool(r["ok"])).is_false()   # not delivered yet
	eco.contract_progress(int(c["id"]), int(c["amount"]))
	r = eco.complete_contract(int(c["id"]), int(c["due_day"]))
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(r["reward"])).is_greater(0)


func test_contract_lapses_after_its_due_day() -> void:
	var eco := _economy()
	var vid := _village_id()
	eco.markets[vid].stock["wool"] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := eco.roll_contract(1, rng)
	eco.contract_progress(int(c["id"]), int(c["amount"]))
	var r := eco.complete_contract(int(c["id"]), int(c["due_day"]) + 5)
	assert_bool(bool(r["ok"])).is_false()


# --- merchant ladder flags ---------------------------------------------------------------

func test_ladder_ctx_reflects_merchant_assets() -> void:
	var eco := _economy()
	var ctx := eco.ladder_ctx()
	assert_bool(bool(ctx["owns_cart"])).is_false()
	var cid := _capital_id()   # buy_cart needs a town or the capital, never a village
	assert_str(eco.buy_cart(cid, 1000)).is_equal("")
	ctx = eco.ladder_ctx()
	assert_bool(bool(ctx["owns_cart"])).is_true()


# --- save / load --------------------------------------------------------------------------

func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_serialize_round_trip() -> void:
	var eco := _economy()
	var vid := _village_id()
	eco.markets[vid].stock["wool"] = 3
	eco.road_risk[vid] = 0.6
	eco.owns_cart = true
	eco.trade_volume = 42
	eco.learn_prices(vid, 12.5)
	eco.caravans.send(0, vid, {"wool": 2}, 1, "rural", 0.2, 0.0, 9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	eco.markets[vid].stock["wool"] = 0
	eco.roll_contract(1, rng)
	var snap := _roundtrip(eco.serialize())
	var home := RAMarket.new()
	var restored := RAEconomy.new()
	restored.deserialize(snap, 0, home)
	assert_int(int(restored.markets[vid].stock["wool"])).is_equal(0)
	assert_float(float(restored.road_risk[vid])).is_equal_approx(0.6, 0.001)
	assert_bool(restored.owns_cart).is_true()
	assert_int(restored.trade_volume).is_equal(42)
	assert_bool(restored.known_prices.has(vid)).is_true()
	assert_int(restored.caravans.caravans.size()).is_equal(1)
	assert_int(restored.contracts.size()).is_equal(1)
