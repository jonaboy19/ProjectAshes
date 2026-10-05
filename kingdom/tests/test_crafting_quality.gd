extends GdUnitTestSuite
## Crafting tension: success chance from skill minus recipe level, input quality feeding output quality,
## partial material loss + half xp on failure, critical successes. Tension is opt-in (ctx.tension).

const Crafting := preload("res://scripts/sim/crafting.gd")


class FakeInv extends RefCounted:
	var items := {}
	var tiers := {}

	func count(id: String) -> int:
		return int(items.get(id, 0))

	func give(id: String, n := 1) -> void:
		items[id] = count(id) + n

	func take(id: String, n := 1) -> bool:
		if count(id) < n:
			return false
		items[id] = count(id) - n
		return true

	func give_quality(id: String, n: int, _q: int) -> void:
		give(id, n)

	func quality_of(id: String) -> int:
		return int(tiers.get(id, -1))


func _pick_recipe(c: RefCounted) -> Dictionary:
	for r: Dictionary in c.recipes:
		if not bool(r.get("repair", false)) and int(r.get("level", 1)) == 1 and (r["inputs"] as Array).size() >= 1 \
				and not (r.get("stations", []) as Array).has("never"):
			var total := 0
			for inp: Dictionary in r["inputs"]:
				total += int(inp["count"])
			if total >= 4:
				return r
	return {}


func _stock(c: RefCounted, r: Dictionary, mult := 1) -> FakeInv:
	var inv := FakeInv.new()
	for inp: Dictionary in r["inputs"]:
		var alts: PackedStringArray = Crafting.alternatives(String(inp["item"]))
		inv.give(alts[0], int(inp["count"]) * mult)
	return inv


func test_success_chance_formula() -> void:
	assert_float(Crafting.success_chance(3, 3)).is_equal_approx(0.55, 0.001)
	assert_float(Crafting.success_chance(8, 3)).is_equal_approx(0.75, 0.001)
	assert_float(Crafting.success_chance(1, 9)).is_equal_approx(0.35, 0.001)
	assert_float(Crafting.success_chance(10, 1)).is_equal_approx(0.91, 0.001)
	assert_float(Crafting.success_chance(10, 1, 1.5)).is_equal_approx(0.98, 0.001)
	assert_float(Crafting.success_chance(3, 3, 1.25)).is_greater(Crafting.success_chance(3, 3))


func test_crit_chance_rises_with_skill_margin() -> void:
	assert_float(Crafting.crit_chance(1, 5)).is_equal(0.0)
	assert_float(Crafting.crit_chance(5, 5)).is_equal_approx(0.03, 0.001)
	assert_float(Crafting.crit_chance(10, 5)).is_greater(Crafting.crit_chance(6, 5))
	assert_float(Crafting.crit_chance(10, 1)).is_less_equal(0.20)


func test_input_quality_shifts_roll_within_cap() -> void:
	assert_float(Crafting.shifted_roll(0.5, 50.0)).is_equal_approx(0.5, 0.0001)
	assert_float(Crafting.shifted_roll(0.5, 100.0)).is_equal_approx(0.3, 0.0001)
	assert_float(Crafting.shifted_roll(0.5, 0.0)).is_equal_approx(0.7, 0.0001)
	assert_float(Crafting.shifted_roll(0.5, 900.0)).is_equal_approx(0.3, 0.0001)   # capped at +/-20%
	assert_float(Crafting.shifted_roll(0.05, 100.0)).is_equal(0.0)


func test_better_inputs_never_lower_quality_and_help_on_average() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	assert_bool(r.is_empty()).is_false()
	c.add_xp(String(r["skill"]), Crafting.xp_for_level(4))
	var rough := 0
	var rich := 0
	for i in 21:
		var roll := float(i) / 21.0
		var a := _stock(c, r)
		var b := _stock(c, r)
		var ra: Dictionary = c.craft(String(r["id"]), a, null, {"roll": roll, "input_quality": 0.0})
		var rb: Dictionary = c.craft(String(r["id"]), b, null, {"roll": roll, "input_quality": 100.0})
		assert_int(int(rb["quality"])).is_greater_equal(int(ra["quality"]))
		rough += int(ra["quality"])
		rich += int(rb["quality"])
	assert_int(rich).is_greater(rough)


func test_input_grade_read_from_inventory_quality() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	var lo := _stock(c, r)
	var hi := _stock(c, r)
	for k: String in lo.items:
		lo.tiers[k] = 0
		hi.tiers[k] = 2
	assert_float(c.input_grade(r, lo)).is_less(c.input_grade(r, hi))
	assert_float(c.input_grade(r, _stock(c, r))).is_equal(-1.0)     # untracked: no shift


func test_failure_returns_half_materials_half_xp_and_keeps_tools() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	var inv := _stock(c, r)
	var before := inv.items.duplicate()
	var xp_before := int(c.xp.get(String(r["skill"]), 0))
	var res: Dictionary = c.craft(String(r["id"]), inv, null, {"tension": true, "success_roll": 0.999})
	assert_bool(bool(res["ok"])).is_true()
	assert_bool(bool(res["failed"])).is_true()
	assert_int(int(res["count"])).is_equal(0)
	for k: String in before:
		var had := int(before[k])
		assert_int(inv.count(k)).is_equal(had / 2)
	assert_int(int(res["xp"])).is_greater_equal(0)
	assert_int(int(c.xp.get(String(r["skill"]), 0)) - xp_before).is_equal(int(res["xp"]))


func test_failure_xp_is_half_of_success_xp() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	var ok: Dictionary = c.craft(String(r["id"]), _stock(c, r), null, {"tension": true, "success_roll": 0.0, "crit_roll": 0.999})
	var c2 := Crafting.new()
	var bad: Dictionary = c2.craft(String(r["id"]), _stock(c2, r), null, {"tension": true, "success_roll": 0.999})
	assert_int(int(bad["xp"])).is_equal(int(round(float(ok["xp"]) * 0.5)))


func test_success_with_crit_raises_tier_and_adds_bonus_unit() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	var plain: Dictionary = c.craft(String(r["id"]), _stock(c, r), null, {"tension": true, "success_roll": 0.0, "crit_roll": 0.999, "roll": 0.99})
	var c2 := Crafting.new()
	var crit: Dictionary = c2.craft(String(r["id"]), _stock(c2, r), null, {"tension": true, "success_roll": 0.0, "crit_roll": 0.0, "roll": 0.99})
	assert_bool(bool(crit["crit"])).is_true()
	assert_bool(bool(plain["crit"])).is_false()
	assert_int(int(crit["quality"])).is_greater(int(plain["quality"]))
	assert_int(int(crit["count"])).is_greater_equal(int(plain["count"]))


func test_without_tension_behaviour_unchanged() -> void:
	var c := Crafting.new()
	var r := _pick_recipe(c)
	for i in 30:
		var res: Dictionary = c.craft(String(r["id"]), _stock(c, r), null, {})
		assert_bool(bool(res["ok"])).is_true()
		assert_bool(res.has("failed")).is_false()
		assert_int(int(res["count"])).is_greater(0)


func test_failure_rate_tracks_chance() -> void:
	var r := _pick_recipe(Crafting.new())
	var fails := 0
	var n := 300
	for i in n:
		var c := Crafting.new(1000 + i)
		var res: Dictionary = c.craft(String(r["id"]), _stock(c, r), null, {"tension": true})
		if res.get("failed", false):
			fails += 1
	var expect := 1.0 - Crafting.success_chance(1, 1)
	assert_float(float(fails) / float(n)).is_between(expect - 0.12, expect + 0.12)
