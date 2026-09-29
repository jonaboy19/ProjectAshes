extends GdUnitTestSuite
## Data adapters of the in-game tabbed menu (scripts/ui/gamemenu/menu_data.gd).

const MD := preload("res://scripts/ui/gamemenu/menu_data.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Skills := preload("res://scripts/sim/skills.gd")
const Radiant := preload("res://scripts/sim/radiant_quests.gd")


class FakeProto extends RefCounted:
	var id := ""
	func get_prototype_id() -> String:
		return id


class FakeItem extends RefCounted:
	var proto := FakeProto.new()
	var n := 1
	func get_prototype() -> FakeProto:
		return proto
	func get_stack_size() -> int:
		return n
	func get_property(_k: String, d: Variant = null) -> Variant:
		return d


class FakeInv extends RefCounted:
	var items: Array = []
	func add(id: String, n := 1) -> void:
		var it := FakeItem.new()
		it.proto.id = id
		it.n = n
		items.append(it)
	func get_items() -> Array:
		return items


class FakeGuild extends RefCounted:
	func active_for(_who: int) -> Array:
		return [{"id": 7, "type": "gather", "title": "Gather 5 iron ore", "required": 5, "progress": 2, "deadline": 12,
			"reward": 30, "points": 4, "penalty": {"gold": 9, "points": 2}, "state": "accepted"}]
	func member(_who: int) -> Dictionary:
		return {"completed": 2, "failed": 1}


func test_categories_follow_the_slot_and_item_category() -> void:
	assert_str(MD.category_of("iron_sword")).is_equal("weapons")
	assert_str(MD.category_of("leather_jerkin")).is_equal("armor")
	assert_str(MD.category_of("wooden_shield")).is_equal("armor")
	assert_str(MD.category_of("bread")).is_equal("consumables")
	assert_str(MD.category_of("healing_salve")).is_equal("consumables")
	assert_str(MD.category_of("iron_ore")).is_equal("materials")
	assert_str(MD.category_of("copper_ring")).is_equal("misc")
	assert_str(MD.category_of("saddle")).is_equal("misc")


func test_rarity_comes_from_quality_for_gear_and_price_for_goods() -> void:
	assert_int(MD.rarity_of("iron_sword", 0)).is_equal(0)
	assert_int(MD.rarity_of("iron_sword", 2)).is_equal(2)
	assert_int(MD.rarity_of("bread")).is_equal(0)
	assert_int(MD.rarity_of("luxury_goods")).is_equal(2)
	assert_str(MD.rarity_name(1)).is_equal("Uncommon")


func test_item_detail_of_a_weapon_lists_the_template_stats() -> void:
	var d := MD.item_detail("iron_sword", 1)
	var labels: Array = (d["rows"] as Array).map(func(r: Dictionary) -> String: return String(r["label"]))
	assert_array(labels).contains(["Damage", "Speed", "Reach", "Weight", "Durability"])
	assert_str(String(d["name"])).is_equal("Iron Sword")
	assert_str(String(d["type"])).is_equal("One-Handed Sword")
	var dmg: Dictionary = (d["rows"] as Array)[0]
	assert_str(String(dmg["text"])).is_equal("9")
	assert_bool(bool(d["gear"])).is_true()


func test_item_detail_of_food_is_usable() -> void:
	var d := MD.item_detail("bread")
	assert_bool(bool(d["usable"])).is_true()
	assert_bool(bool(d["gear"])).is_false()
	assert_int(MD.value_of("bread")).is_equal(2)


func test_stacks_group_by_item_and_sort_by_category() -> void:
	var inv := FakeInv.new()
	inv.add("bread", 3)
	inv.add("iron_ore", 5)
	inv.add("bread", 2)
	inv.add("iron_sword", 1)
	var st := MD.stacks(inv)
	assert_int(st.size()).is_equal(3)
	assert_str(String(st[0]["id"])).is_equal("iron_sword")
	assert_str(String(st[1]["id"])).is_equal("bread")
	assert_int(int(st[1]["count"])).is_equal(5)
	assert_int(MD.filter_stacks(st, "materials").size()).is_equal(1)
	assert_int(MD.filter_stacks(st, "all").size()).is_equal(3)
	assert_int(MD.filter_stacks(st, "quest").size()).is_equal(0)
	assert_float(MD.carry_weight(st)).is_greater(3.0)


func test_compare_rows_show_the_difference_to_the_worn_item() -> void:
	var sword := MD.item_detail("iron_sword", 1)
	var rows := MD.compare_rows(sword, {"id": "iron_dagger", "quality": 1, "durability": -1})
	var dmg: Dictionary = rows[0]
	assert_str(String(dmg["label"])).is_equal("Damage")
	assert_str(String(dmg["delta_text"])).is_equal("+5")
	assert_int(int(dmg["delta"])).is_equal(1)
	# Heavier is worse.
	var weight: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["label"] == "Weight")[0]
	assert_int(int(weight["delta"])).is_equal(-1)


func test_attributes_start_at_eight_and_follow_mastery_and_level() -> void:
	var m := Mastery.new()
	var base := MD.attributes(m, 1)
	assert_int(base.size()).is_equal(6)
	assert_str(String(base[0]["name"])).is_equal("Strength")
	assert_int(int(base[0]["value"])).is_equal(8)
	for i in 400:
		m.gain("soldiering", 1.0, i)
		m.gain("smithing", 1.0, i)
		m.gain("mining", 1.0, i)
		m.gain("swordsmanship", 1.0, i)
	var later := MD.attributes(m, 9)
	assert_int(int(later[0]["value"])).is_greater(int(base[0]["value"]) + 2)
	assert_int(int(later[4]["value"])).is_equal(10)  # wisdom: only the level bonus (9 -> +2)


func test_level_info_reads_merit_inside_the_sqrt_step() -> void:
	var info := MD.level_info(30, 7)
	assert_int(int(info["into"])).is_equal(5)
	assert_int(int(info["needed"])).is_equal(11)
	assert_float(float(info["ratio"])).is_equal_approx(5.0 / 11.0, 0.001)
	assert_int(int(MD.level_info(0, 1)["into"])).is_equal(0)


func test_skill_summary_has_the_six_template_rows() -> void:
	var rows := MD.skill_summary(Mastery.new(), Skills.new(), preload("res://scripts/sim/soul.gd").new())
	var names: Array = rows.map(func(r: Dictionary) -> String: return String(r["name"]))
	assert_array(names).is_equal(["Combat", "Survival", "Crafting", "Social", "Stealth", "Soul Power"])
	assert_int(int(rows[4]["value"])).is_equal(1)


func test_group_info_lists_perks_and_a_level_bar() -> void:
	var m := Mastery.new()
	m.gain("swordsmanship", 12.0, 1)
	var sk := Skills.new()
	var ctx := {"level": 1, "titles": {}, "flags": {}, "sects": []}
	var info := MD.group_info("combat", m, sk, ctx)
	assert_str(String(info["name"])).is_equal("Combat")
	assert_int(int(info["level"])).is_greater(1)
	assert_float(float(info["ratio"])).is_between(0.0, 1.0)
	assert_int((info["perks"] as Array).size()).is_greater(0)
	var first: Dictionary = (info["perks"] as Array)[0]
	assert_bool(first.has("icon") and first.has("desc") and first.has("rank")).is_true()
	# Groups without a mastery use learned techniques as the level.
	var stealth := MD.group_info("stealth", m, sk, ctx)
	assert_int(int(stealth["level"])).is_equal(1)
	assert_int(MD.GROUPS.size()).is_equal(9)


func test_mastery_rows_cover_every_discipline_highest_first() -> void:
	var m := Mastery.new()
	for i in 60:
		m.gain("hunting", 1.0, i)
	var rows := MD.mastery_rows(m)
	assert_int(rows.size()).is_equal(Mastery.DISCIPLINES.size())
	assert_str(String(rows[0]["id"])).is_equal("hunting")


func test_radiant_quest_is_normalised_with_objectives_and_rewards() -> void:
	var q := {"id": "q1", "kind": "clear_wolves", "title": "Wolves north", "desc": "Kill them.", "giver_name": "Old Wren",
		"stage": 1, "state": "active", "progress": 2, "deadline": 9,
		"stages": [{"type": "kill_den", "text": "Kill 3 wolves", "pos": Vector2(1, 2), "radius": 40.0, "den_id": 1, "kills": 3},
			{"type": "return", "text": "Report back", "pos": Vector2(5, 6), "radius": 6.0}],
		"reward": {"gold": 25, "rep": {"ashford": 4}}}
	var n := MD.normalise_radiant(q)
	assert_str(String(n["group"])).is_equal("side")
	assert_bool(bool(n["objectives"][0]["done"])).is_true()
	assert_bool(bool(n["objectives"][1]["done"])).is_false()
	assert_str(String(n["subtitle"])).contains("Due day 9")
	assert_that(n["pos"]).is_equal(Vector2(5, 6))
	assert_str(String(n["rewards"][0]["text"])).is_equal("25")
	assert_int((n["rewards"] as Array).size()).is_equal(2)
	q["kind"] = "war_battle"
	assert_str(String(MD.normalise_radiant(q)["group"])).is_equal("main")


func test_quests_merge_radiant_and_guild_and_count_history() -> void:
	var rq := Radiant.new()
	rq.active.append({"id": "a", "kind": "deliver", "title": "Delivery", "desc": "", "stage": 0, "state": "active", "progress": 0,
		"deadline": 5, "stages": [{"type": "reach", "text": "Deliver it", "pos": Vector2.ZERO, "radius": 10.0}], "reward": {"gold": 5}})
	rq.tracked = "a"
	rq.completed = 3
	rq.failed = 1
	var qs := MD.quests(rq, FakeGuild.new())
	assert_int((qs["active"] as Array).size()).is_greater_equal(2)
	assert_bool(bool(qs["active"][0]["tracked"])).is_true()
	var guild_q: Dictionary = (qs["active"] as Array).filter(func(x: Dictionary) -> bool: return x["source"] == "guild")[0]
	assert_str(String(guild_q["objectives"][0]["text"])).contains("2/5")
	var counts := MD.quest_counts(rq, FakeGuild.new())
	assert_int(int(counts["completed"])).is_equal(5)
	assert_int(int(counts["failed"])).is_equal(2)


func test_map_filters_pick_places_by_category_and_kind() -> void:
	var town := {"kind": "town", "category": "settlement", "travel": true}
	var camp := {"kind": "goblin_warren", "category": "camp", "travel": false}
	var mine := {"kind": "mine", "category": "site", "travel": false}
	var shrine := {"kind": "shrine", "category": "lore", "travel": false}
	assert_bool(MD.map_filter("all", camp)).is_true()
	assert_bool(MD.map_filter("settlement", town)).is_true()
	assert_bool(MD.map_filter("settlement", camp)).is_false()
	assert_bool(MD.map_filter("camp", camp)).is_true()
	assert_bool(MD.map_filter("cave", mine)).is_true()
	assert_bool(MD.map_filter("poi", shrine)).is_true()
	assert_bool(MD.map_filter("poi", mine)).is_false()
	assert_bool(MD.map_filter("dungeon", camp)).is_true()
	assert_bool(MD.map_filter("fast", town)).is_true()
	assert_bool(MD.map_filter("main", town)).is_false()


func test_direction_text() -> void:
	assert_str(MD.direction_text(Vector2.ZERO, Vector2(0, -540))).is_equal("540 m north")
	assert_str(MD.direction_text(Vector2.ZERO, Vector2(300, 300))).is_equal("424 m south-east")
	assert_str(MD.direction_text(Vector2.ZERO, Vector2(-2500, 0))).is_equal("2.5 km west")
