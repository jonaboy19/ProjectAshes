extends GdUnitTestSuite
## Noble houses (scripts/sim/nobility.gd): deterministic generation, every
## settlement has a landlord, road tolls, a feud's border-risk effect, a
## struggling house selling a holding, opinion-gated audience options and a
## serialize/deserialize round trip.

const RANobility := preload("res://scripts/sim/nobility.gd")

var _gold_before: int
var _day_before: int
var _n: RANobility


func before_test() -> void:
	WorldGen.setup(WorldSim.SEED)
	_gold_before = Game.gold
	_day_before = WorldSim.day
	Game.gold = 1000
	_n = RANobility.new()
	# Life.relationships is a real, persistent singleton: clear any "house_*"
	# faction reputation a previous test left behind so opinion starts at 0.
	var rel: Object = Life.get("relationships")
	if rel != null:
		for k: String in (rel.reputation as Dictionary).keys().duplicate():
			if k.begins_with("house_"):
				rel.reputation.erase(k)
				rel.faction_names.erase(k)


func after_test() -> void:
	Game.gold = _gold_before
	WorldSim.day = _day_before


# --- generation --------------------------------------------------------------------

func test_generates_about_six_houses_deterministically() -> void:
	assert_int(_n.houses.size()).is_equal(RANobility.HOUSE_COUNT)
	var n2 := RANobility.new()
	assert_int(n2.houses.size()).is_equal(_n.houses.size())
	for i in _n.houses.size():
		assert_str(String(n2.houses[i]["id"])).is_equal(String(_n.houses[i]["id"]))
		assert_str(String(n2.houses[i]["name"])).is_equal(String(_n.houses[i]["name"]))
		assert_str(String(n2.houses[i]["head"]["name"])).is_equal(String(_n.houses[i]["head"]["name"]))


func test_house_names_come_from_the_caldric_culture() -> void:
	var culture: Dictionary = Life.lore.culture("caldric")
	var families: Array = culture.get("family_names", [])
	for h: Dictionary in _n.houses:
		var family := String(h["name"]).trim_prefix("House ")
		assert_bool(families.has(family)).is_true()


func test_holdings_are_deterministic() -> void:
	var n2 := RANobility.new()
	for s: Dictionary in WorldGen.settlements:
		assert_str(_n.settlement_owner(int(s["id"]))).is_equal(n2.settlement_owner(int(s["id"])))


# --- landlords ----------------------------------------------------------------------

func test_every_non_capital_settlement_has_a_landlord() -> void:
	assert_bool(_n.all_settlements_have_landlords()).is_true()
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			continue
		var info := _n.landlord_for_settlement(int(s["id"]))
		assert_str(String(info["name"])).is_not_empty()


func test_capital_belongs_to_the_crown() -> void:
	var capital_idx := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			capital_idx = int(s["id"])
	assert_int(capital_idx).is_greater_equal(0)
	assert_str(_n.landlord_for_settlement(capital_idx)["name"]).is_equal("the Crown")


func test_every_house_holds_at_least_one_fief() -> void:
	for h: Dictionary in _n.houses:
		assert_int(_n.fiefs_of(String(h["id"])).size()).is_greater(0)


# --- tolls -------------------------------------------------------------------------

func test_roads_touching_the_capital_are_toll_free() -> void:
	var capital_idx := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			capital_idx = int(s["id"])
	for r: Vector2i in WorldGen.roads:
		if r.x == capital_idx or r.y == capital_idx:
			assert_int(_n.toll_for_road(r.x, r.y)).is_equal(0)


func test_some_roads_are_tolled_by_a_house() -> void:
	var total := 0
	for r: Vector2i in WorldGen.roads:
		total += _n.toll_for_road(r.x, r.y)
	assert_int(total).is_greater(0)


# --- feuds ---------------------------------------------------------------------------

func test_feud_raises_border_risk_on_the_house_lands() -> void:
	var a := String(_n.houses[0]["id"])
	var b := String(_n.houses[1]["id"])
	var fief := _n.fiefs_of(a)[0]
	assert_float(_n.border_risk_bonus(fief)).is_equal(0.0)
	_n.feuds_list.append({"house_a": a, "house_b": b, "since_day": 1, "cause": "a border dispute"})
	assert_float(_n.border_risk_bonus(fief)).is_greater(0.0)
	assert_bool(_n.feud_between(a, b)).is_true()
	assert_int(_n.feuds().size()).is_equal(1)


# --- struggling houses sell holdings --------------------------------------------------

func test_struggling_house_eventually_sells_a_holding() -> void:
	var hid := String(_n.houses[0]["id"])
	var sold := false
	for d in 1000:
		WorldSim.day = d
		_n.wealth[hid] = 0    # kept perpetually poor so it stays struggling every day
		for line: String in _n.daily(d):
			if line.contains("sold"):
				sold = true
	assert_bool(sold).is_true()


# --- opinion-gated services ------------------------------------------------------------

func test_sponsorship_is_gated_by_opinion() -> void:
	var hid := String(_n.houses[0]["id"])
	_n.change_opinion(hid, -100.0)
	assert_bool(bool(_n.sponsor(hid)["ok"])).is_false()
	_n.change_opinion(hid, 200.0)
	var r := _n.sponsor(hid)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(r["tier"])).is_greater_equal(4)


func test_hostile_house_taxes_more() -> void:
	var hid := String(_n.houses[0]["id"])
	_n.change_opinion(hid, -100.0)
	assert_bool(_n.is_hostile(hid)).is_true()
	assert_float(_n.tax_multiplier(hid)).is_greater(1.0)


func test_buying_a_holding_requires_the_house_to_be_struggling() -> void:
	var hid := String(_n.houses[0]["id"])
	var fief := _n.fiefs_of(hid)[0]
	_n.wealth[hid] = 5000
	assert_str(_n.can_buy_holding(hid, "settlement", fief)).is_not_empty()
	_n.wealth[hid] = 0
	assert_str(_n.can_buy_holding(hid, "settlement", fief)).is_empty()
	Game.gold = 100000
	var r := _n.buy_holding(hid, "settlement", fief)
	assert_bool(bool(r["ok"])).is_true()
	assert_str(_n.settlement_owner(fief)).is_equal(RANobility.PLAYER)


# --- rumours ---------------------------------------------------------------------------

func test_rumours_mention_feuding_houses() -> void:
	var a := String(_n.houses[0]["id"])
	var b := String(_n.houses[1]["id"])
	_n.feuds_list.append({"house_a": a, "house_b": b, "since_day": 1, "cause": "a border dispute"})
	var rumours := _n.rumours()
	var found := false
	for r: String in rumours:
		if r.contains(_n.house_name(a)) and r.contains(_n.house_name(b)):
			found = true
	assert_bool(found).is_true()


# --- serialize / deserialize -------------------------------------------------------------

func test_serialize_round_trip() -> void:
	var hid := String(_n.houses[0]["id"])
	_n.wealth[hid] = 4242
	_n.influence[hid] = 55.5
	var b := String(_n.houses[1]["id"])
	_n.feuds_list.append({"house_a": hid, "house_b": b, "since_day": 3, "cause": "a border dispute"})
	_n.alliances.append([hid, b, 5])
	var fief := _n.fiefs_of(b)[0]
	_n.wealth[b] = 0
	Game.gold = 100000
	_n.buy_holding(b, "settlement", fief)
	_n.loans.append({"house_id": hid, "amount": 100, "owed": 120, "due_day": 50})
	var d := _n.serialize()
	var n2 := RANobility.new()
	n2.deserialize(d)
	assert_int(int(n2.wealth[hid])).is_equal(4242)
	assert_float(float(n2.influence[hid])).is_equal_approx(55.5, 0.01)
	assert_int(n2.feuds().size()).is_equal(1)
	assert_int(n2.alliances.size()).is_equal(1)
	assert_str(n2.settlement_owner(fief)).is_equal(RANobility.PLAYER)
	assert_int(n2.loans.size()).is_equal(1)
