extends GdUnitTestSuite
## Food spoilage: stacks with spoil data age in the pack by game time (stack property age_hours), turn into Spoiled Food past their
## shelf life or feed less when stale; cured food lasts longer; ageing is closed-form (one step for any elapsed time).

const ItemsDB := preload("res://scripts/sim/items_db.gd")


func _reset_pack() -> void:
	for it: InventoryItem in Life.inventory.get_items().duplicate():
		Life.inventory.remove_item(it)


func before_test() -> void:
	_reset_pack()
	Life._spoil_abs = Life.NO_CLOCK


func after_test() -> void:
	_reset_pack()


func test_pure_functions() -> void:
	assert_float(ItemsDB.spoil_hours("bread")).is_equal(120.0)
	assert_bool(ItemsDB.is_preserved("jerky")).is_true()
	assert_bool(ItemsDB.is_preserved("bread")).is_false()
	assert_float(ItemsDB.freshness("bread", 0.0)).is_equal(1.0)
	assert_float(ItemsDB.freshness("bread", 59.0)).is_equal(1.0)
	assert_float(ItemsDB.freshness("bread", 110.0)).is_between(0.6, 0.8)
	assert_float(ItemsDB.freshness("bread", 120.0)).is_equal(0.0)
	assert_float(ItemsDB.freshness("sword_of_nothing", 5000.0)).is_equal(1.0)    # no spoil data: never stale
	var r := ItemsDB.age_by("bread", 100.0, 30.0)
	assert_str(String(r["into"])).is_equal("spoiled_food")
	assert_str(String(ItemsDB.age_by("bread", 0.0, 24.0)["into"])).is_equal("")


func test_cured_food_outlasts_fresh_food() -> void:
	# After a month, bread and fish are gone, jerky and smoked fish are fine.
	for id in ["bread", "grilled_fish", "jerky", "smoked_fish", "hardtack"]:
		Life.give(id, 2)
	var r := Life.age_pack(24.0 * 30.0)
	assert_int(int(r["spoiled"])).is_equal(4)
	assert_int(Life.count("bread")).is_equal(0)
	assert_int(Life.count("grilled_fish")).is_equal(0)
	assert_int(Life.count("jerky")).is_equal(2)
	assert_int(Life.count("smoked_fish")).is_equal(2)
	assert_int(Life.count("hardtack")).is_equal(2)
	assert_int(Life.count("spoiled_food")).is_equal(4)


func test_ageing_is_closed_form_and_stacks_carry_the_age() -> void:
	Life.give("bread", 3)
	Life.age_pack(24.0)
	assert_float(Life.food_age("bread")).is_equal(24.0)
	Life.age_pack(24.0 * 2.0)                  # one step for two days, same as 3 single days
	assert_float(Life.food_age("bread")).is_equal(72.0)
	assert_int(Life.count("bread")).is_equal(3)
	# bought later = a fresher stack of its own; it does not merge into the old one
	Life.give("bread", 2)
	assert_int(Life.count("bread")).is_equal(5)
	var stacks := Life.inventory.get_items_with_prototype_id("bread")
	assert_int(stacks.size()).is_equal(2)
	Life.age_pack(24.0)
	var ages := []
	for it in Life.inventory.get_items_with_prototype_id("bread"):
		ages.append(float(it.get_property(ItemsDB.AGE_PROP, 0.0)))
	ages.sort()
	assert_array(ages).is_equal([24.0, 96.0])


func test_stacks_of_equal_age_merge_back() -> void:
	Life.give("bread", 2)
	Life.age_pack(24.0)
	Life.give("bread", 2)
	Life.age_pack(0.5)                          # sub-hour step still ages the fresh stack
	assert_int(Life.inventory.get_items_with_prototype_id("bread").size()).is_equal(2)
	Life.age_pack(24.0)
	Life.age_pack(0.0)
	assert_int(Life.count("bread")).is_equal(4)


func test_stale_food_feeds_less() -> void:
	Life.give("bread", 1)
	var fresh := float(Life.item_prop("bread", "nutrition", 0.0))
	assert_float(fresh).is_greater(0.0)
	Life.age_pack(110.0)                         # 92 % of its shelf life
	var f := ItemsDB.freshness("bread", Life.food_age("bread"))
	assert_float(f).is_between(0.6, 0.85)
	var before: float = Life.needs.food
	Life.needs.food = 0.0
	Life.use_item("bread")
	var fed: float = Life.needs.food
	Life.needs.food = before
	assert_float(fed).is_less(fresh)
	assert_float(fed).is_greater(fresh * 0.55)


func test_day_tick_ages_by_the_time_since_last_time() -> void:
	Life.give("bread", 1)
	var now := Life._abs_hours()
	Life._spoil_abs = now - 48.0                # two days passed unnoticed (sleep, fast travel)
	Life._spoilage_tick()
	assert_float(Life.food_age("bread")).is_between(47.9, 48.1)
	Life._spoilage_tick()                        # nothing more elapsed
	assert_float(Life.food_age("bread")).is_between(47.9, 48.1)
	Life._spoil_abs = now - 24.0 * 10.0
	Life._spoilage_tick()
	assert_int(Life.count("bread")).is_equal(0)
	assert_int(Life.count("spoiled_food")).is_equal(1)


func test_age_survives_a_save() -> void:
	Life.give("bread", 2)
	Life.age_pack(30.0)
	var data: Dictionary = Life.inventory.serialize()
	_reset_pack()
	Life.inventory.deserialize(data)
	assert_float(Life.food_age("bread")).is_equal(30.0)
	assert_int(Life.count("bread")).is_equal(2)
