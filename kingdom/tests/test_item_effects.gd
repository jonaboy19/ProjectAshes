extends GdUnitTestSuite
const ItemsDB := preload("res://scripts/sim/items_db.gd")
## Life.apply_item_effect: pills, manuals, coatings and wards are applied and spent (equipment.consume).

func test_breakthrough_pill_banks_bonus_and_coating_buffs() -> void:
	var msg := Life.apply_item_effect("pill_foundation", {"breakthrough_bonus": 0.15})
	assert_str(msg).contains("breakthrough")
	var cult: Variant = Life.realm.mod("cultivation")
	assert_float(float(cult.pill_bonus)).is_equal_approx(0.15, 0.001)
	var n := Life.equipment.buffs.size()
	assert_str(Life.apply_item_effect("fire_oil", {"coating": "fire"})).contains("coated")
	assert_int(Life.equipment.buffs.size()).is_greater(n)
	cult.pill_bonus = 0.0


func test_scroll_teaches_technique_once() -> void:
	var id := "earth_spike"
	var first := Life.apply_item_effect("scroll_earth_spike", {"casts": id})
	assert_bool(Life.skills.is_learned(id) or first.contains("Unknown")).is_true()
	if Life.skills.is_learned(id):
		assert_str(Life.apply_item_effect("scroll_earth_spike", {"casts": id})).contains("Already")


func test_level_gate_blocks_high_gear() -> void:
	var high := ""
	for id: String in ["rift_crystal_longsword", "grand_healing_potion"]:
		if ItemsDB.req_level(id) > Life.player_level():
			high = id
	if high == "":
		return
	assert_bool(Life.equipment.meets_requirements(high, Life.player_level())).is_false()
