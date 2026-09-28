extends GdUnitTestSuite
## Crafting, cooking and equipment: recipe data is sound, crafting consumes and
## produces, quality rolls stay in bounds, equipment stats add up, and both
## save and load through JSON.

const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const OreVein := preload("res://scripts/world/ore_vein.gd")


## Dictionary-backed stand-in for the Life autoload's count / give / take.
class FakeInv extends RefCounted:
	var items := {}
	var quality := {}

	func count(id: String) -> int:
		return int(items.get(id, 0))

	func give(id: String, n := 1) -> void:
		items[id] = count(id) + n

	func take(id: String, n := 1) -> bool:
		if count(id) < n:
			return false
		items[id] = count(id) - n
		return true

	func give_quality(id: String, n: int, q: int) -> void:
		give(id, n)
		quality[id] = q


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_recipes_validate() -> void:
	var c := Crafting.new()
	assert_int(c.recipes.size()).is_greater_equal(25)
	assert_array(Array(c.validate())).is_empty()


func test_every_ingredient_and_output_is_an_item() -> void:
	var c := Crafting.new()
	for r: Dictionary in c.recipes:
		for inp: Dictionary in r["inputs"]:
			for alt in Crafting.alternatives(String(inp["item"])):
				assert_bool(Crafting.item_exists(alt)).override_failure_message("%s: no item %s" % [r["id"], alt]).is_true()
		if not bool(r.get("repair", false)):
			var out := String(r["output"]["item"])
			assert_bool(Crafting.item_exists(out)).override_failure_message("%s: no item %s" % [r["id"], out]).is_true()
			assert_int(int(Crafting.item_info(out).get("price", 0))).override_failure_message(out).is_greater(0)


func test_every_skill_and_station_is_covered() -> void:
	var c := Crafting.new()
	for skill: String in ["cooking", "alchemy", "smithing", "leatherwork", "carpentry"]:
		assert_bool(c.recipes.any(func(r: Dictionary) -> bool: return r["skill"] == skill)).override_failure_message(skill).is_true()
	for kind: String in ["hearth", "campfire", "anvil", "workbench", "alchemy_table"]:
		assert_array(c.recipes_for([kind])).override_failure_message(kind).is_not_empty()
	# Cooked food fills more than what it is made from, and gives a buff.
	for id: String in ["grilled_fish", "venison_roast", "berry_pie", "mushroom_soup"]:
		var info := Crafting.item_info(id)
		assert_float(float(info["nutrition"])).is_greater(float(Crafting.item_info("trout")["nutrition"]))
		assert_bool(info.has("buff_stat")).override_failure_message(id).is_true()


func test_crafting_consumes_and_produces() -> void:
	var c := Crafting.new()
	var inv := FakeInv.new()
	inv.give("trout", 1)
	inv.give("perch", 1)
	var r := c.craft("grilled_fish", inv, ["campfire"], {"roll": 0.5})
	assert_bool(r["ok"]).is_true()
	assert_int(inv.count("grilled_fish")).is_equal(1)
	assert_int(inv.count("perch") + inv.count("trout")).is_equal(1)
	assert_int(int(c.xp["cooking"])).is_equal(5)
	# Wrong station, missing input, too low a level: nothing changes.
	assert_bool(c.craft("grilled_fish", inv, ["anvil"])["ok"]).is_false()
	assert_str(c.can_craft("healing_salve", inv, ["alchemy_table"])).contains("Needs 3")
	inv.give("venison", 2)
	inv.give("firewood", 1)
	assert_str(c.can_craft("venison_roast", inv, ["hearth"])).contains("Cooking 3")
	assert_int(inv.count("venison")).is_equal(2)
	# Ore -> ingot -> blade, with the multi-input takes.
	c.xp["smithing"] = Crafting.xp_for_level(2)
	inv.give("iron_ore", 2)
	inv.give("coal", 1)
	inv.give("plank", 1)
	assert_bool(c.craft("iron_ingot", inv, ["anvil"])["ok"]).is_true()
	assert_int(inv.count("iron_ore")).is_equal(0)
	assert_int(inv.count("coal")).is_equal(0)
	var blade := c.craft("iron_dagger", inv, ["anvil"], {"roll": 0.0})
	assert_bool(blade["ok"]).is_true()
	assert_int(inv.count("iron_dagger")).is_equal(1)
	assert_int(int(inv.quality["iron_dagger"])).is_equal(int(blade["quality"]))


func test_masterwork_batch_and_repair() -> void:
	var c := Crafting.new()
	var inv := FakeInv.new()
	c.xp["alchemy"] = Crafting.xp_for_level(Crafting.MAX_LEVEL)
	inv.give("healing_herb", 3)
	var r := c.craft("healing_salve", inv, ["alchemy_table"], {"roll": 0.0})
	assert_int(int(r["quality"])).is_equal(Crafting.Quality.MASTERWORK)
	assert_int(inv.count("healing_salve")).is_equal(2)
	# Repair needs worn gear and an ingot.
	var eq := Equipment.new()
	eq.equip("leather_jerkin")
	inv.give("iron_ingot", 1)
	assert_str(c.can_craft("repair_gear", inv, ["anvil"], {"equipment": eq})).is_not_empty()
	eq.wear("body", 40)
	assert_bool(eq.needs_repair()).is_true()
	# A master smith restores it fully (a rough repair only brings it back to 60%).
	c.xp["smithing"] = Crafting.xp_for_level(Crafting.MAX_LEVEL)
	assert_bool(c.craft("repair_gear", inv, ["anvil"], {"equipment": eq, "roll": 0.0})["ok"]).is_true()
	assert_bool(eq.needs_repair()).is_false()
	assert_int(inv.count("iron_ingot")).is_equal(0)


func test_skill_levels_and_career_bonus() -> void:
	var c := Crafting.new()
	assert_int(c.level("cooking")).is_equal(1)
	for l in range(1, Crafting.MAX_LEVEL):
		assert_int(Crafting.xp_for_level(l + 1)).is_greater(Crafting.xp_for_level(l))
		assert_int(Crafting.level_from_xp(Crafting.xp_for_level(l + 1))).is_equal(l + 1)
		assert_int(Crafting.level_from_xp(Crafting.xp_for_level(l + 1) - 1)).is_equal(l)
	assert_int(c.add_xp("smithing", 100000)).is_equal(Crafting.MAX_LEVEL)
	assert_float(Crafting.career_xp_mult("smithing", "smithy")).is_greater(1.0)
	assert_float(Crafting.career_xp_mult("cooking", "smithy")).is_equal(1.0)
	var inv := FakeInv.new()
	inv.give("firewood", 4)
	var plain := c.craft("plank", inv, ["workbench"])
	var paid := c.craft("plank", inv, ["workbench"], {"org": "woodcutters"})
	assert_int(int(paid["xp"])).is_greater(int(plain["xp"]))


func test_quality_roll_bounds() -> void:
	for lvl in range(1, Crafting.MAX_LEVEL + 1):
		for rl in range(1, lvl + 1):
			var o := Crafting.quality_odds(lvl, rl)
			assert_float(o[0] + o[1] + o[2]).is_equal_approx(1.0, 0.0001)
			for p in o:
				assert_float(p).is_between(0.0, 1.0)
			for i in 21:
				var q := Crafting.quality_for_roll(lvl, rl, i / 20.0)
				assert_int(q).is_between(Crafting.Quality.ROUGH, Crafting.Quality.MASTERWORK)
	# Skill shifts the odds: more masterwork, less rough.
	var novice := Crafting.quality_odds(1, 1)
	var master := Crafting.quality_odds(Crafting.MAX_LEVEL, 1)
	assert_float(master[2]).is_greater(novice[2])
	assert_float(master[0]).is_less(novice[0])
	assert_float(novice[2]).is_less(0.1)
	# Rolled with the RNG, a novice mostly makes rough/fine work.
	var c := Crafting.new(7)
	var counts := [0, 0, 0]
	for i in 2000:
		counts[c.roll_quality(1, 1)] += 1
	assert_int(counts[2]).is_less(200)
	assert_int(counts[0]).is_greater(800)


func test_equipment_stat_sums() -> void:
	var eq := Equipment.new()
	eq.equip("leather_jerkin")          # armour 5
	eq.equip("iron_helm")               # armour 4, speed -0.01
	eq.equip("iron_sword")              # damage 9
	eq.equip("leather_boots")           # armour 1, speed +0.04
	var s := eq.stats()
	assert_float(float(s["armour"])).is_equal_approx(10.0, 0.001)
	assert_float(float(s["damage"])).is_equal_approx(9.0, 0.001)
	assert_float(float(s["speed"])).is_equal_approx(0.03, 0.001)
	# Quality scales, a new main-hand item replaces the old one, worn-out gear halves.
	var old := eq.equip("iron_dagger", Crafting.Quality.MASTERWORK)
	assert_str(String(old["id"])).is_equal("iron_sword")
	assert_float(float(eq.stats()["damage"])).is_equal_approx(4.0 * 1.35, 0.001)
	eq.wear("body", 1000)
	assert_float(float(eq.stats()["armour"])).is_equal_approx(7.5, 0.001)
	assert_dict(eq.unequip("body")).is_not_empty()
	assert_str(eq.item_in("body")).is_empty()
	# Buffs add while active.
	eq.add_buff("Hearty", "damage", 2.0, 4.0, 10.0)
	assert_float(float(eq.stats(12.0)["damage"])).is_equal_approx(4.0 * 1.35 + 2.0, 0.001)
	assert_float(float(eq.stats(15.0)["damage"])).is_equal_approx(4.0 * 1.35, 0.001)
	# Everything with a slot names a real one.
	for id: String in Crafting.item_db():
		var slot := String(Crafting.item_info(id).get("slot", ""))
		if slot != "":
			assert_bool(Equipment.SLOTS.has(slot)).override_failure_message(id).is_true()
	for slot: String in Equipment.SLOTS:
		assert_bool(Crafting.item_db().values().any(func(i: Dictionary) -> bool: return i.get("slot", "") == slot)) \
			.override_failure_message("nothing fits %s" % slot).is_true()


func test_serialisation_roundtrip() -> void:
	var c := Crafting.new()
	c.add_xp("cooking", 77)
	c.add_xp("mining", 12)
	var c2 := Crafting.new()
	c2.deserialize(_roundtrip(c.serialize()))
	assert_int(c2.level("cooking")).is_equal(c.level("cooking"))
	assert_int(int(c2.xp["mining"])).is_equal(12)
	var eq := Equipment.new()
	eq.equip("leather_jerkin", Crafting.Quality.ROUGH)
	eq.equip("copper_ring", Crafting.Quality.MASTERWORK)
	eq.wear("body", 7)
	eq.add_buff("Second wind", "stamina_regen", 0.6, 2.0, 100.0)
	var eq2 := Equipment.new()
	eq2.deserialize(_roundtrip(eq.serialize()))
	assert_dict(eq2.equipped("body")).is_equal(eq.equipped("body"))
	assert_int(int(eq2.equipped("trinket")["quality"])).is_equal(Crafting.Quality.MASTERWORK)
	assert_dict(eq2.stats(101.0)).is_equal(eq.stats(101.0))
	# Junk in a save is dropped rather than worn.
	var eq3 := Equipment.new()
	eq3.deserialize({"slots": {"head": {"id": "bread"}, "feet": {"id": "leather_boots", "quality": 2}}})
	assert_str(eq3.item_in("head")).is_empty()
	assert_str(eq3.item_in("feet")).is_equal("leather_boots")


func test_stations_by_proximity() -> void:
	var c := Crafting.new()
	c.clear_stations()
	c.add_world_sites([{"name": "Bandit Camp", "kind": "bandit_camp", "pos": Vector2(100, 50), "yaw": 0.0,
		"parts": [["ruins/campfire", Vector2.ZERO, 0.0, false]]}])
	c.add_station("anvil", Vector3(0, 300, 0), "Anvil")
	assert_array(c.kinds_near(Vector3(102, 12, 51))).contains_exactly(["campfire"])
	assert_array(c.kinds_near(Vector3(1, 300.5, 1))).contains_exactly(["anvil"])
	assert_array(c.kinds_near(Vector3(1, 0, 1))).is_empty()            # the room is 300 m up
	assert_array(c.kinds_near(Vector3(200, 0, 200))).is_empty()


func test_ore_yield_and_layout() -> void:
	for ore: String in OreVein.ORES:
		var o: Dictionary = OreVein.ORES[ore]
		assert_bool(Crafting.item_exists(String(o["item"]))).is_true()
		for i in 11:
			var n := OreVein.yield_for(ore, i / 10.0, 1.0, false, 1)
			assert_int(n).is_between(int(o["min"]), int(o["max"]))
		assert_int(OreVein.yield_for(ore, 0.0, 1.0, true, 1)).is_equal(int(o["min"]) + 1)
	var site := {"pos": Vector2(75, -470), "yaw": 1.0, "kind": "mine"}
	var spots := OreVein.layout_for(site)
	assert_int(spots.size()).is_equal(OreVein.LAYOUT.size())
	for e: Array in spots:
		assert_float((e[0] as Vector2).distance_to(site["pos"])).is_between(8.0, 30.0)
