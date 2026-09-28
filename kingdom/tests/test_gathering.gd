extends GdUnitTestSuite
## Hunting, fishing and foraging tables: drops, rarity by water and hour, prices.

const Gathering := preload("res://scripts/sim/gathering_items.gd")


func _count(kind: String, item: String) -> int:
	for pair: Array in Gathering.drops_for(kind):
		if pair[0] == item:
			return int(pair[1])
	return 0


func test_hunting_drops() -> void:
	assert_int(_count("deer", "venison")).is_equal(1)
	assert_int(_count("deer", "deer_hide")).is_equal(1)
	assert_int(_count("rabbit", "rabbit_meat")).is_equal(1)
	assert_int(Gathering.drops_for("rabbit").size()).is_equal(1)
	assert_int(_count("boar", "pork")).is_greater_equal(1)
	assert_int(_count("boar", "boar_tusk")).is_equal(1)
	assert_int(_count("stag", "venison")).is_greater(_count("deer", "venison"))


func test_livestock_and_pets_are_not_game() -> void:
	for kind in ["deer", "stag", "rabbit", "fox"]:
		assert_bool(Gathering.is_game(kind)).override_failure_message(kind).is_true()
		assert_int(int(Gathering.GAME_HEALTH[kind])).is_greater(0)
	for kind in ["cow", "ox", "sheep", "pig", "goat", "chicken", "rooster", "dog", "sheepdog",
			"cat", "cat_ginger", "horse", "horse_grey", "horse_draft", "donkey"]:
		assert_bool(Gathering.is_game(kind)).override_failure_message(kind).is_false()
		assert_array(Gathering.drops_for(kind)).is_empty()


func test_every_gathered_item_is_defined_and_priced() -> void:
	var items := {}
	for kind: String in Gathering.HUNT_DROPS:
		for pair: Array in Gathering.drops_for(kind):
			items[pair[0]] = true
	for id: String in Gathering.FISH:
		items[id] = true
	for kind: String in Gathering.FORAGE:
		items[Gathering.FORAGE[kind]["item"]] = true
	items.erase("firewood")    # already in data/items.json and the market
	for id: String in items:
		assert_bool(Gathering.ITEMS.has(id)).override_failure_message("no prototype for %s" % id).is_true()
		assert_bool(Gathering.MARKET.has(id)).override_failure_message("no market price for %s" % id).is_true()
		assert_int(int(Gathering.MARKET[id][0])).is_equal(int(Gathering.ITEMS[id]["price"]))
		assert_str(String(Gathering.ITEMS[id]["name"])).is_not_empty()


func test_rarer_fish_are_worth_more() -> void:
	var prev := 0
	for id: String in Gathering.FISH_ORDER:
		var price := int(Gathering.ITEMS[id]["price"])
		assert_int(price).is_greater(prev)
		prev = price
		assert_float(float(Gathering.FISH[id]["lake"])).is_less_equal(float(Gathering.FISH["perch"]["lake"]))


func test_emberfin_only_at_sunset() -> void:
	assert_bool(Gathering.is_sunset(18.5)).is_true()
	assert_bool(Gathering.is_sunset(12.0)).is_false()
	assert_bool(Gathering.is_sunset(2.0)).is_false()
	for river in [false, true]:
		assert_float(float(Gathering.fish_weights(12.0, river)["emberfin"])).is_equal(0.0)
		assert_float(float(Gathering.fish_weights(18.5, river)["emberfin"])).is_greater(0.0)
	# Sweep the whole roll range at noon: never an emberfin.
	for i in 200:
		assert_str(Gathering.roll_fish(i / 200.0, 12.0)).is_not_equal("emberfin")
	# The very top of the roll at sunset is the emberfin.
	assert_str(Gathering.roll_fish(0.9999, 18.5)).is_equal("emberfin")


func test_fish_roll_follows_weights() -> void:
	assert_str(Gathering.roll_fish(0.0, 12.0)).is_equal("perch")
	assert_str(Gathering.roll_fish(1.0, 12.0)).is_equal("pike")
	# Histogram over an even sweep of rolls matches the weight shares.
	for river in [false, true]:
		for hour: float in [9.0, 18.5]:
			var w := Gathering.fish_weights(hour, river)
			var total := 0.0
			for id: String in w:
				total += float(w[id])
			var hits := {}
			var n := 4000
			for i in n:
				var f := Gathering.roll_fish((i + 0.5) / n, hour, river)
				hits[f] = int(hits.get(f, 0)) + 1
			for id: String in w:
				var share := float(hits.get(id, 0)) / n
				assert_float(share).override_failure_message("%s river=%s hour=%s" % [id, river, hour]) \
					.is_equal_approx(float(w[id]) / total, 0.01)


func test_trout_prefer_the_river() -> void:
	var lake := Gathering.fish_weights(10.0, false)
	var river := Gathering.fish_weights(10.0, true)
	assert_float(float(river["trout"])).is_greater(float(lake["trout"]))
	assert_float(float(lake["perch"])).is_greater(float(river["perch"]))


func test_forage_kinds_by_ground() -> void:
	for i in 50:
		var r := i / 50.0
		assert_str(Gathering.forage_kind(0.7, r)).is_not_equal("berries")
		assert_str(Gathering.forage_kind(0.1, r)).is_not_equal("mushroom")
		assert_str(Gathering.forage_kind(0.1, r)).is_not_equal("firewood")
	for kind: String in Gathering.FORAGE:
		var f: Dictionary = Gathering.FORAGE[kind]
		assert_int(int(f["respawn_days"])).is_greater_equal(1)
		assert_int(int(f["max"])).is_greater_equal(int(f["min"]))
