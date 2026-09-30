extends GdUnitTestSuite
## The Region 1 item set (data/items/*.json, data/recipes/*.json): unique ids, old ids intact, every recipe
## resolvable and obtainable, shops and loot tables valid, prices consistent with tier and materials.

const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const RAMarketScript := preload("res://scripts/sim/market.gd")
const Homestead := preload("res://scripts/sim/homestead.gd")
const Gathering := preload("res://scripts/sim/gathering_items.gd")

const EXTRA_FILES := ["index", "shops", "loot", "sets", "crops", "visuals", "legacy_patch"]
const WEAPON_TYPES := ["dagger", "sword", "sabre", "greatsword", "axe", "battleaxe", "mace", "warhammer", "spear", "halberd", "fist", "shortbow", "longbow", "crossbow", "staff", "wand"]


class FakeInv extends RefCounted:
	var items := {}

	func count(id: String) -> int:
		return int(items.get(id, 0))

	func give(id: String, n := 1) -> void:
		items[id] = count(id) + n

	func take(id: String, n := 1) -> bool:
		if count(id) < n:
			return false
		items[id] = count(id) - n
		return true


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _legacy() -> Dictionary:
	return _json("res://data/items.json")


func _price(id: String) -> int:
	return int(Crafting.item_info(id).get("price", 0))


# --- ids ---------------------------------------------------------------------------------------------------

func test_ids_unique_across_files_and_legacy() -> void:
	var legacy := _legacy()
	var seen := {}
	var errs: Array[String] = []
	var idx: Dictionary = _json("res://data/items/index.json")
	assert_int((idx["files"] as Array).size()).is_greater_equal(8)
	for f: String in idx["files"]:
		var d: Dictionary = _json("res://data/items/%s.json" % f)
		assert_bool(d.is_empty()).override_failure_message(f).is_false()
		for id: String in d:
			if seen.has(id):
				errs.append("%s in %s and %s" % [id, seen[id], f])
			if legacy.has(id):
				errs.append("%s in %s duplicates data/items.json" % [id, f])
			if Gathering.ITEMS.has(id):
				errs.append("%s in %s duplicates gathering_items.gd" % [id, f])
			seen[id] = f
	assert_array(errs).is_empty()
	assert_int(seen.size()).is_greater_equal(900)


func test_recipe_ids_unique() -> void:
	var c := Crafting.new()
	var seen := {}
	for r: Dictionary in c.recipes:
		assert_bool(seen.has(String(r["id"]))).override_failure_message("duplicate recipe " + String(r["id"])).is_false()
		seen[String(r["id"])] = true
	assert_int(c.recipes.size()).is_greater_equal(600)


func test_old_ids_still_load() -> void:
	var legacy := _legacy()
	var db := Crafting.item_db()
	for id: String in legacy:
		assert_bool(db.has(id)).override_failure_message(id).is_true()
		var e: Dictionary = legacy[id]
		if e.has("name"):
			assert_str(String(db[id]["name"])).override_failure_message(id).is_equal(String(e["name"]))
		if e.has("price"):
			assert_int(int(db[id]["price"])).override_failure_message(id).is_equal(int(e["price"]))
		for stat in ["armour", "damage", "slot", "durability"]:
			if e.has(stat):
				assert_bool(db[id][stat] == e[stat]).override_failure_message("%s.%s changed" % [id, stat]).is_true()
	for id in ["iron_sword", "leather_jerkin", "bread", "stew", "healing_salve", "iron_ingot", "copper_ring", "wooden_shield"]:
		assert_bool(Crafting.item_exists(id)).is_true()
	assert_int(Crafting.item_db().size()).is_greater_equal(1100)
	# Old recipes are still there and untouched.
	var c := Crafting.new()
	assert_bool(c.recipe("iron_sword").is_empty()).is_false()
	assert_int(int(c.recipe("iron_sword")["level"])).is_equal(4)


func test_items_are_well_formed() -> void:
	var errs: Array[String] = []
	var db := Crafting.item_db()
	for id: String in ItemsDB.new_ids():
		var e: Dictionary = db[id]
		if String(e.get("name", "")) == "":
			errs.append(id + ": no name")
		if not e.has("category"):
			errs.append(id + ": no category")
		if int(e.get("max_stack_size", 0)) < 1:
			errs.append(id + ": bad stack")
		var r := int(e.get("rarity", 0))
		if r < 0 or r > 4:
			errs.append(id + ": rarity %d" % r)
		if float(e.get("weight", 0.0)) < 0.0:
			errs.append(id + ": weight")
		if int(e.get("price", -1)) < 0:
			errs.append(id + ": no price")
		if int(e.get("level", 0)) < 1 or int(e.get("level", 0)) > 60:
			errs.append(id + ": level %d outside Region 1 (1-60)" % int(e.get("level", 0)))
		if e.has("slot") and not Equipment.SLOTS.has(String(e["slot"])):
			errs.append(id + ": unknown slot " + String(e["slot"]))
		if e.has("slot") and int(e.get("durability", 0)) < 1:
			errs.append(id + ": gear without durability")
		if not FileAccess.file_exists("res://assets/ui/icons/items/%s.svg" % id):
			errs.append(id + ": no icon")
		if e.get("category", "") != "quest" and e.get("category", "") != "key" and not e.has("unique") and int(e["price"]) <= 0 and not bool(e.get("spoiled", false)) and not e.has("teaches"):
			errs.append(id + ": free item")
	assert_array(errs).is_empty()


func test_item_set_is_large_and_covers_every_category() -> void:
	var cats := {}
	for id: String in ItemsDB.new_ids():
		var c := String(Crafting.item_info(id)["category"])
		cats[c] = int(cats.get(c, 0)) + 1
	for c in ["gear", "food", "healing", "material", "ore", "tool", "manual", "lore", "key", "quest", "furniture", "seed", "feed", "tack", "ammo"]:
		assert_int(int(cats.get(c, 0))).override_failure_message(c).is_greater(0)
	assert_int(int(cats["gear"])).is_greater_equal(350)
	assert_int(int(cats["food"])).is_greater_equal(120)
	var rarities := {}
	for id: String in ItemsDB.new_ids():
		rarities[int(Crafting.item_info(id).get("rarity", 0))] = true
	for r in [0, 1, 2, 3, 4]:
		assert_bool(rarities.has(r)).override_failure_message("no rarity %d" % r).is_true()
	# Legendary only as a handful of uniques.
	var legends := 0
	for id: String in ItemsDB.new_ids():
		if int(Crafting.item_info(id).get("rarity", 0)) == 4:
			legends += 1
			assert_bool(bool(Crafting.item_info(id).get("unique", false))).override_failure_message(id).is_true()
	assert_int(legends).is_between(8, 16)


func test_weapon_and_armour_families_exist() -> void:
	for t: String in WEAPON_TYPES:
		var n := 0
		for id: String in ItemsDB.ids_of_type(t):
			if not bool(Crafting.item_info(id).get("unique", false)):
				n += 1
		assert_int(n).override_failure_message(t).is_greater_equal(5)
	for t in ["head_armour", "body_armour", "hands_armour", "legs_armour", "feet_armour", "cloak_armour", "ring", "amulet", "talisman", "shield"]:
		assert_int(ItemsDB.ids_of_type(t).size()).override_failure_message(t).is_greater_equal(4)
	for slot: String in Equipment.SLOTS:
		assert_bool(Crafting.item_db().values().any(func(i: Dictionary) -> bool: return i.get("slot", "") == slot)).override_failure_message(slot).is_true()


# --- recipes -------------------------------------------------------------------------------------------------

func test_every_recipe_resolves() -> void:
	var c := Crafting.new()
	assert_array(Array(c.validate())).is_empty()
	for sk: String in ["smithing", "carpentry", "tailoring", "leatherwork", "cooking", "baking", "brewing", "alchemy", "jewelry", "fletching", "masonry"]:
		assert_bool(c.recipes.any(func(r: Dictionary) -> bool: return r["skill"] == sk)).override_failure_message(sk).is_true()
	for st in ["hearth", "campfire", "anvil", "workbench", "alchemy_table", "oven", "brew_vat", "loom", "jeweler_bench"]:
		assert_array(c.recipes_for([st])).override_failure_message(st).is_not_empty()


func test_every_craftable_item_has_a_recipe_path_and_every_input_is_obtainable() -> void:
	var c := Crafting.new()
	var obtainable := {}
	for r: Dictionary in c.recipes:
		if r.has("output"):
			obtainable[String(r["output"]["item"])] = true
	for sid: String in ItemsDB.shop_ids():
		for t in [1, 2, 3]:
			for g: Dictionary in ItemsDB.shop_goods(sid, t):
				obtainable[String(g["item"])] = true
	var loot: Dictionary = ItemsDB.extra("loot")
	for th: String in loot["themes"]:
		for t: String in loot["themes"][th]["tiers"]:
			for e: Array in loot["themes"][th]["tiers"][t]["entries"]:
				obtainable[String(e[0])] = true
	for sp: String in loot["monsters"]:
		for d: Array in loot["monsters"][sp]["drops"]:
			obtainable[String(d[0])] = true
	for id: String in _legacy():
		obtainable[id] = true
	for id: String in Gathering.ITEMS:
		obtainable[id] = true
	for crop: String in ItemsDB.crops():
		obtainable[crop] = true
	var missing: Array[String] = []
	for r: Dictionary in c.recipes:
		for inp: Dictionary in r["inputs"]:
			var any := false
			for alt in Crafting.alternatives(String(inp["item"])):
				if obtainable.has(alt):
					any = true
			if not any:
				missing.append("%s needs %s" % [r["id"], inp["item"]])
	assert_array(missing).is_empty()


func test_crafting_gates_on_station_and_level_and_consumes() -> void:
	var c := Crafting.new()
	var inv := FakeInv.new()
	inv.give("tin_ore", 2)
	inv.give("coal", 1)
	assert_str(c.can_craft("tin_ingot", inv, ["hearth"])).contains("Needs a")
	assert_str(c.can_craft("tin_ingot", inv, ["anvil"])).is_empty()
	var res := c.craft("tin_ingot", inv, ["anvil"], {"roll": 0.5})
	assert_bool(bool(res["ok"])).is_true()
	assert_int(inv.count("tin_ingot")).is_greater_equal(1)
	assert_int(inv.count("tin_ore")).is_equal(0)
	# A mastery-gated recipe refuses a beginner.
	inv.give("rift_crystal", 3)
	inv.give("spirit_iron_ingot", 1)
	inv.give("spirit_stone", 1)
	assert_str(c.can_craft("rift_crystal_ingot", inv, ["anvil"])).contains("Needs Smithing")
	c.add_xp("smithing", Crafting.xp_for_level(10))
	assert_str(c.can_craft("rift_crystal_ingot", inv, ["anvil"])).is_empty()


func test_recipe_levels_follow_tiers() -> void:
	var c := Crafting.new()
	var prev := 0
	for id in ["wooden_sword", "bronze_sword", "steel_sword", "finesteel_sword", "spiritiron_sword", "rift_sword"]:
		var lvl := int(c.recipe(id)["level"])
		assert_int(lvl).override_failure_message(id).is_greater_equal(prev)
		prev = lvl
	assert_int(int(c.recipe("rift_sword")["level"])).is_greater_equal(9)
	assert_int(int(c.recipe("wooden_sword")["level"])).is_less_equal(2)


func test_salvage_returns_materials() -> void:
	var c := Crafting.new()
	var inv := FakeInv.new()
	assert_str(c.can_salvage("steel_sword", inv)).contains("You have no")
	inv.give("steel_sword", 1)
	assert_str(c.can_salvage("steel_sword", inv, ["hearth"])).contains("Needs a")
	c.add_xp("smithing", Crafting.xp_for_level(5))
	var res := c.salvage("steel_sword", inv, ["anvil"])
	assert_bool(bool(res["ok"])).override_failure_message(String(res["text"])).is_true()
	assert_int(inv.count("steel_sword")).is_equal(0)
	assert_int(inv.count("steel_ingot")).is_greater(0)
	# Every salvage table yields real items and never more than was put in.
	for id: String in ItemsDB.new_ids():
		var sv := ItemsDB.salvage_for(id)
		if sv.is_empty():
			continue
		var r := c.recipe(id)
		assert_bool(r.is_empty()).override_failure_message("salvage without recipe " + id).is_false()
		for y: Dictionary in sv["yield"]:
			assert_bool(Crafting.item_exists(String(y["item"]))).override_failure_message(id).is_true()
	assert_int(ItemsDB.salvage_for("iron_helm").size()).is_equal(0)  # old ids have no salvage table


# --- shops ---------------------------------------------------------------------------------------------------------

func test_shops_are_valid() -> void:
	var ids := ItemsDB.shop_ids()
	assert_int(ids.size()).is_greater_equal(30)
	for must in ["blacksmith", "armourer", "bowyer", "tailor", "grocer", "butcher", "baker", "tavern", "alchemist", "general_store", "temple", "stable", "jeweller"]:
		assert_bool(ids.has(must)).override_failure_message(must).is_true()
	assert_bool(ids.any(func(s: String) -> bool: return s.begins_with("sect_"))).is_true()
	var errs: Array[String] = []
	for sid: String in ids:
		var total := 0
		for t in [1, 2, 3]:
			var goods := ItemsDB.shop_goods(sid, t)
			total = goods.size()
			var seen := {}
			for g: Dictionary in goods:
				var item := String(g["item"])
				if not Crafting.item_exists(item):
					errs.append("%s sells unknown %s" % [sid, item])
				elif int(g["price"]) <= 0:
					errs.append("%s sells free %s" % [sid, item])
				if seen.has(item):
					errs.append("%s lists %s twice" % [sid, item])
				seen[item] = true
				if int(g["stock"]) < 1:
					errs.append("%s: %s has no stock" % [sid, item])
		if total < 3:
			errs.append("%s is nearly empty (%d goods at tier 3)" % [sid, total])
	assert_array(errs).is_empty()


func test_shop_tiers_grow_and_respect_level_caps() -> void:
	for sid in ["blacksmith", "armourer", "alchemist", "tavern"]:
		var n1 := ItemsDB.shop_goods(sid, 1).size()
		var n2 := ItemsDB.shop_goods(sid, 2).size()
		var n3 := ItemsDB.shop_goods(sid, 3).size()
		assert_int(n2).override_failure_message(sid).is_greater_equal(n1)
		assert_int(n3).override_failure_message(sid).is_greater_equal(n2)
	for g: Dictionary in ItemsDB.shop_goods("blacksmith", 1):
		assert_int(int(Crafting.item_info(String(g["item"])).get("level", 1))).override_failure_message(String(g["item"])).is_less_equal(14)
	# Shops never sell uniques or quest items, and epic gear stays out of ordinary shops.
	for sid: String in ItemsDB.shop_ids():
		if sid.begins_with("sect_"):
			continue
		for g: Dictionary in ItemsDB.shop_goods(sid, 3):
			var info := Crafting.item_info(String(g["item"]))
			assert_bool(bool(info.get("unique", false)) or bool(info.get("quest_item", false))).override_failure_message("%s sells %s" % [sid, g["item"]]).is_false()
			assert_int(int(info.get("rarity", 0))).override_failure_message("%s sells %s" % [sid, g["item"]]).is_less_equal(3)


func test_settlements_get_shops_by_kind_and_identity() -> void:
	var village := ItemsDB.shops_for_settlement("village", 120)
	var town := ItemsDB.shops_for_settlement("town", 400)
	var castle := ItemsDB.shops_for_settlement("castle", 1500)
	assert_bool(village.has("general_store") and village.has("tavern")).is_true()
	assert_bool(village.has("armourer")).is_false()
	assert_bool(town.has("armourer") and town.has("alchemist")).is_true()
	assert_int(castle.size()).is_greater(town.size())
	assert_bool(ItemsDB.shops_for_settlement("hamlet", 30).has("blacksmith")).is_false()
	assert_bool(ItemsDB.shops_for_settlement("village", 120, ["temple"]).has("temple")).is_true()
	for kind in ["hamlet", "village", "frontier_town", "town", "castle"]:
		for s in ItemsDB.shops_for_settlement(kind, 200):
			assert_bool(ItemsDB.shop_ids().has(s)).override_failure_message("%s: %s" % [kind, s]).is_true()


func test_market_stocking_and_restocking() -> void:
	var m := RAMarketScript.new()
	m.add_good("bread", 2, 30, 6)
	var n := ItemsDB.stock_settlement(m, "town", 300, [], 11)
	assert_int(n).is_greater(60)
	assert_int(int(m.base_price["bread"])).is_equal(2)        # existing goods untouched
	assert_bool(m.base_price.has("steel_sword") or m.base_price.has("bronze_sword")).is_true()
	assert_bool(m.base_price.has("healing_potion")).is_true()
	for item: String in m.base_price:
		assert_bool(Crafting.item_exists(item)).override_failure_message(item).is_true()
		assert_int(m.price(item)).is_greater(0)
	# Empty a shelf: the day tick restocks from local production or imports.
	var restockable := ""
	for item: String in m.base_price:
		if float(m.produce.get(item, 0.0)) > 0.0 and int(m.target[item]) >= 6:
			restockable = item
			break
	assert_str(restockable).is_not_empty()
	m.stock[restockable] = 0
	for i in 5:
		m.tick_day(300)
	assert_int(int(m.stock[restockable])).is_greater(0)
	var gear := ""
	for item: String in m.imports:
		if Crafting.item_info(item).get("category", "") == "gear":
			gear = item
			break
	assert_str(gear).is_not_empty()
	m.stock[gear] = 0
	for i in 30:
		m.add_stock(gear, float(m.imports[gear]))
	assert_int(int(m.stock[gear])).is_greater(0)
	# A market bought from and sold to still works.
	assert_int(m.buy("healing_potion", 1000)).is_greater(0)


# --- loot -------------------------------------------------------------------------------------------------------------

func test_loot_tables_are_valid() -> void:
	var themes := ItemsDB.loot_themes()
	for must in ["beast", "humanoid", "undead", "rift", "chest_common", "chest_military", "chest_arcane", "chest_treasure", "dungeon_crypt", "dungeon_cave", "dungeon_ruin", "dungeon_warren", "tower", "boss", "bandit_camp", "orc_camp"]:
		assert_bool(themes.has(must)).override_failure_message(must).is_true()
	var errs: Array[String] = []
	for th in themes:
		for tier in [1, 2, 3, 4, 5]:
			var t := ItemsDB.loot_table(tier, th)
			if t.is_empty():
				errs.append("%s tier %d missing" % [th, tier])
				continue
			if (t["entries"] as Array).is_empty() and th != "village_home":
				errs.append("%s tier %d has no entries" % [th, tier])
			for e: Array in t["entries"]:
				if not Crafting.item_exists(String(e[0])):
					errs.append("%s/%d: unknown %s" % [th, tier, e[0]])
				if float(e[1]) <= 0.0 or int(e[2]) < 1 or int(e[3]) < int(e[2]):
					errs.append("%s/%d: bad entry %s" % [th, tier, e])
			if int(t["rolls"][0]) < 1 or int(t["rolls"][1]) < int(t["rolls"][0]):
				errs.append("%s/%d: bad rolls" % [th, tier])
	assert_array(errs).is_empty()


func test_loot_scales_with_danger_tier() -> void:
	var low := ItemsDB.loot_table(1, "chest_military")
	var high := ItemsDB.loot_table(5, "chest_military")
	var low_max := 0
	var high_max := 0
	for e: Array in low["entries"]:
		low_max = maxi(low_max, int(Crafting.item_info(String(e[0])).get("level", 1)))
	for e: Array in high["entries"]:
		high_max = maxi(high_max, int(Crafting.item_info(String(e[0])).get("level", 1)))
	assert_int(low_max).is_less_equal(14)
	assert_int(high_max).is_greater_equal(46)
	assert_int(int(high["gold"][1])).is_greater(int(low["gold"][1]))
	# Tier 1 never drops epic gear; boss/tower tier 5 can drop uniques.
	for e: Array in low["entries"]:
		assert_int(int(Crafting.item_info(String(e[0])).get("rarity", 0))).override_failure_message(String(e[0])).is_less_equal(1)
	var uniques := 0
	for e: Array in ItemsDB.loot_table(5, "boss")["entries"]:
		if bool(Crafting.item_info(String(e[0])).get("unique", false)):
			uniques += 1
	assert_int(uniques).is_greater(0)
	assert_bool(ItemsDB.loot_table(9, "tower").is_empty()).is_false()     # out-of-range tier clamps
	assert_bool(ItemsDB.loot_table(1, "no_such_theme").is_empty()).is_true()
	assert_bool(ItemsDB.loot_table(1, "no_such_theme", true).is_empty()).is_false()


func test_rolling_loot_and_monster_drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for theme in ItemsDB.loot_themes():
		var res := ItemsDB.roll_loot(3, theme, rng)
		for e: Dictionary in res["items"]:
			assert_bool(Crafting.item_exists(String(e["item"]))).override_failure_message(theme).is_true()
			assert_int(int(e["count"])).is_greater(0)
	var any := 0
	for i in 40:
		any += ItemsDB.roll_loot(2, "chest_common", rng)["items"].size()
	assert_int(any).is_greater(30)
	assert_int(ItemsDB.roll_loot(4, "boss", rng, 2)["items"].size()).is_greater(0)
	for sp in ItemsDB.monster_species():
		for i in 20:
			for d: Dictionary in ItemsDB.monster_drops(sp, rng, 1):
				assert_bool(Crafting.item_exists(String(d["item"]))).override_failure_message(sp).is_true()
	for sp in ["wolf", "boar", "bear", "troll", "wyvern", "goblin", "orc", "bandit", "skeleton", "rift_creature"]:
		assert_bool(ItemsDB.monster_species().has(sp)).override_failure_message(sp).is_true()
	var wolf_drops := 0
	for i in 50:
		wolf_drops += ItemsDB.monster_drops("wolf", rng).size()
	assert_int(wolf_drops).is_greater(40)
	assert_array(ItemsDB.monster_drops("unicorn", rng)).is_empty()


# --- prices ------------------------------------------------------------------------------------------------------------------

func test_prices_follow_materials_and_tiers() -> void:
	var c := Crafting.new()
	var errs: Array[String] = []
	for r: Dictionary in c.recipes:
		if r.has("repair") or not ItemsDB.new_entries().has(String(r["output"]["item"])):
			continue
		var out := String(r["output"]["item"])
		var cost := 0.0
		for inp: Dictionary in r["inputs"]:
			cost += float(_price(Crafting.alternatives(String(inp["item"]))[0])) * float(inp["count"])
		var value := float(_price(out)) * float(r["output"]["count"])
		if value < 0.4 * cost:
			errs.append("%s sells for %d but costs %d" % [out, value, cost])
		if value * 0.6 > cost + 6.0:
			errs.append("%s: crafting then selling would profit (%d vs %d)" % [out, value * 0.6, cost])
	assert_array(errs).is_empty()


func test_weapon_prices_rise_with_tier() -> void:
	var errs: Array[String] = []
	for t: String in WEAPON_TYPES:
		var rows: Array = []
		for id: String in ItemsDB.ids_of_type(t):
			var e := Crafting.item_info(id)
			if bool(e.get("unique", false)) or not e.has("tier"):
				continue
			rows.append([int(e["tier"]), _price(id), id, int(e.get("damage", 0)) + int(e.get("magic", 0)), int(e.get("level", 1))])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		for i in range(1, rows.size()):
			if int(rows[i][1]) < int(rows[i - 1][1]):
				errs.append("%s (%d g) cheaper than %s (%d g)" % [rows[i][2], rows[i][1], rows[i - 1][2], rows[i - 1][1]])
			if int(rows[i][3]) < int(rows[i - 1][3]):
				errs.append("%s weaker than %s" % [rows[i][2], rows[i - 1][2]])
			if int(rows[i][4]) < int(rows[i - 1][4]):
				errs.append("%s has a lower level than %s" % [rows[i][2], rows[i - 1][2]])
	assert_array(errs).is_empty()
	# Top tier is worth far more than the start, and iron keeps its old price.
	assert_int(_price("rift_sword")).is_greater(_price("iron_sword") * 20)
	assert_int(_price("iron_sword")).is_equal(45)


func test_armour_sets_rise_with_tier() -> void:
	var errs: Array[String] = []
	var sets: Dictionary = ItemsDB.extra("sets")
	assert_int(sets.size()).is_greater_equal(25)
	for cls in ["light", "medium", "heavy", "robe"]:
		var ladder: Array = []
		for sid: String in sets:
			if String(sets[sid]["class"]) == cls and not sid.begins_with("sect_"):
				ladder.append([int(sets[sid]["level"]), sid])
		ladder.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		for i in range(1, ladder.size()):
			var prev_pieces: Array = sets[ladder[i - 1][1]]["pieces"]
			var pieces: Array = sets[ladder[i][1]]["pieces"]
			for k in pieces.size():
				var a := Crafting.item_info(String(pieces[k]))
				var b := Crafting.item_info(String(prev_pieces[k]))
				if float(a.get("armour", 0)) + float(a.get("magic", 0)) < float(b.get("armour", 0)) + float(b.get("magic", 0)):
					errs.append("%s weaker than %s" % [pieces[k], prev_pieces[k]])
				if int(a.get("price", 0)) < int(b.get("price", 0)):
					errs.append("%s cheaper than %s" % [pieces[k], prev_pieces[k]])
	assert_array(errs).is_empty()
	# Heavier classes protect more than lighter ones at comparable levels.
	assert_float(float(Crafting.item_info("steelplate_cuirass")["armour"])).is_greater(float(Crafting.item_info("steelmail_hauberk")["armour"]))
	assert_float(float(Crafting.item_info("steelmail_hauberk")["armour"])).is_greater(float(Crafting.item_info("hardened_cuirass")["armour"]))
	assert_float(float(Crafting.item_info("sage_robe")["magic"])).is_greater(float(Crafting.item_info("adept_robe")["magic"]))


func test_rarity_matches_price_band() -> void:
	var by_r := {0: [], 1: [], 2: [], 3: [], 4: []}
	for id: String in ItemsDB.new_ids():
		var e := Crafting.item_info(id)
		if String(e.get("category", "")) != "gear" or not e.has("weapon_type") or bool(e.get("unique", false)):
			continue
		by_r[int(e.get("rarity", 0))].append(_price(id))
	for r in [1, 2, 3]:
		if by_r[r].is_empty() or by_r[r - 1].is_empty():
			continue
		by_r[r].sort()
		by_r[r - 1].sort()
		# medians rise with rarity
		assert_int(int(by_r[r][by_r[r].size() / 2])).override_failure_message("rarity %d" % r).is_greater_equal(int(by_r[r - 1][by_r[r - 1].size() / 2]))
	for id: String in ItemsDB.new_ids():
		var e := Crafting.item_info(id)
		if bool(e.get("unique", false)) and int(e.get("rarity", 0)) >= 3:
			assert_int(int(e["price"])).override_failure_message(id).is_greater_equal(1500)


# --- equipment ----------------------------------------------------------------------------------------------------------------------

func test_new_slots_and_stats() -> void:
	var eq := Equipment.new()
	for id in ["steelplate_greaves", "mantle_of_ash", "ring_might_2", "amulet_vigor_2", "riftplate_helm"]:
		assert_bool(Equipment.is_equippable(id)).override_failure_message(id).is_true()
	assert_str(Equipment.slot_of("steelplate_greaves")).is_equal("legs")
	assert_str(Equipment.slot_of("mantle_of_ash")).is_equal("cloak")
	assert_str(Equipment.slot_of("ring_might_2")).is_equal("ring")
	assert_str(Equipment.slot_of("amulet_vigor_2")).is_equal("amulet")
	eq.equip("ring_might_2")
	eq.equip("amulet_vigor_2")
	eq.equip("sage_robe")
	var s := eq.stats()
	assert_float(float(s["damage"])).is_greater(0.0)
	assert_float(float(s["max_health"])).is_greater(0.0)
	assert_float(float(s["magic"])).is_greater(0.0)
	# Old items keep the exact stats they had.
	var old := Equipment.new()
	old.equip("iron_sword")
	assert_float(float(old.stats()["damage"])).is_equal_approx(9.0, 0.001)
	assert_float(float(old.stats()["magic"])).is_equal_approx(0.0, 0.001)
	# Save/load keeps the new slots.
	var eq2 := Equipment.new()
	eq2.deserialize(JSON.parse_string(JSON.stringify(eq.serialize())))
	assert_str(eq2.item_in("ring")).is_equal("ring_might_2")
	assert_bool(Equipment.meets_requirements("rift_sword", 10)).is_false()
	assert_bool(Equipment.meets_requirements("rift_sword", 55)).is_true()


func test_set_bonuses_apply_at_thresholds() -> void:
	var eq := Equipment.new()
	eq.equip("steelplate_helm")
	var base := float(eq.stats()["armour"])
	eq.equip("steelplate_cuirass")
	var plain2 := float(Crafting.item_info("steelplate_helm")["armour"]) + float(Crafting.item_info("steelplate_cuirass")["armour"])
	assert_float(float(eq.stats()["armour"])).is_equal_approx(plain2, 0.001)     # two pieces: no bonus yet
	eq.equip("steelplate_greaves")
	var plain3 := plain2 + float(Crafting.item_info("steelplate_greaves")["armour"])
	assert_float(float(eq.stats()["armour"])).is_greater(plain3)                 # 3-piece bonus
	assert_float(base).is_greater(0.0)
	for sid: String in ItemsDB.extra("sets"):
		for pid: String in ItemsDB.extra("sets")[sid]["pieces"]:
			assert_bool(Crafting.item_exists(pid)).override_failure_message("%s: %s" % [sid, pid]).is_true()
			assert_str(ItemsDB.set_of(pid)).is_equal(sid)


func test_consuming_new_food_and_potions() -> void:
	var eq := Equipment.new()
	var life := _FakeLife.new()
	life.inv.give("roast_chicken", 1)
	var msg := eq.consume(life, "roast_chicken", 0.0)
	assert_str(msg).is_not_empty()
	assert_int(life.inv.count("roast_chicken")).is_equal(0)
	assert_int(eq.active_buffs(0.0).size()).is_equal(1)
	life.inv.give("qi_draught", 1)
	life.magicules.current = 5.0
	eq.consume(life, "qi_draught", 0.0)
	assert_float(life.magicules.current).is_greater(5.0)
	life.inv.give("healing_potion", 1)
	eq.consume(life, "healing_potion", 0.0)
	assert_int(life.healed).is_equal(90)
	# Pills need the cultivation system to hook in; until then they are not wasted.
	life.inv.give("pill_qi_gathering", 1)
	assert_str(eq.consume(life, "pill_qi_gathering", 0.0)).contains("can't use")
	assert_int(life.inv.count("pill_qi_gathering")).is_equal(1)
	var hooked := _FakeLifeHook.new()
	hooked.inv.give("pill_qi_gathering", 1)
	assert_str(eq.consume(hooked, "pill_qi_gathering", 0.0)).contains("pill ok")
	assert_int(hooked.inv.count("pill_qi_gathering")).is_equal(0)


class _FakeMag extends RefCounted:
	var current := 40.0
	var max_pool := 100.0

	func effective_max() -> float:
		return max_pool


class _FakeLife extends RefCounted:
	var inv := FakeInv.new()
	var magicules := _FakeMag.new()
	var healed := 0
	var player: Object = null

	func _init() -> void:
		player = _FakePlayer.new(self)

	func count(id: String) -> int:
		return inv.count(id)

	func take(id: String, n := 1) -> bool:
		return inv.take(id, n)

	func use_item(id: String) -> String:
		inv.take(id, 1)
		return "ate %s" % id


class _FakeLifeHook extends _FakeLife:
	func apply_item_effect(_id: String, _info: Dictionary) -> String:
		return "pill ok"


class _FakePlayer extends RefCounted:
	var life: Object

	func _init(l: Object) -> void:
		life = l

	func heal(n: int) -> void:
		life.set("healed", int(life.get("healed")) + n)


# --- systems that read items --------------------------------------------------------------------------------------------------------

func test_food_and_drink_data() -> void:
	var errs: Array[String] = []
	var stats := ["damage", "armour", "speed", "stamina_regen", "max_health", "magic", "qi_regen", "max_stamina", "resist", "luck", "stealth", "night_vision", "heal_power"]
	var n_dish := 0
	var n_drink := 0
	for id: String in ItemsDB.new_ids():
		var e := Crafting.item_info(id)
		if e.get("category", "") != "food":
			continue
		if not bool(e.get("spoiled", false)) and float(e.get("nutrition", 0.0)) <= 0.0 and not ["produce", "drink"].has(String(e.get("type", ""))) and int(e.get("price", 0)) < 10:
			errs.append(id + ": no nutrition")
		if e.has("buff_stat"):
			if not stats.has(String(e["buff_stat"])):
				errs.append(id + ": odd buff stat " + String(e["buff_stat"]))
			if float(e.get("buff_hours", 0.0)) <= 0.0 or float(e.get("buff_value", 0.0)) == 0.0:
				errs.append(id + ": bad buff")
		if e.has("spoil_hours"):
			if float(e["spoil_hours"]) <= 0.0 or not Crafting.item_exists(String(e.get("spoils_into", ""))):
				errs.append(id + ": bad spoilage")
		if e.get("type", "") == "dish":
			n_dish += 1
		if bool(e.get("drink", false)):
			n_drink += 1
	assert_array(errs).is_empty()
	assert_int(n_dish).is_greater_equal(30)
	assert_int(n_drink).is_greater_equal(20)
	# Spoilage helper.
	assert_str(ItemsDB.spoiled_into("chicken", 10.0)).is_empty()
	assert_str(ItemsDB.spoiled_into("chicken", 100.0)).is_equal("spoiled_food")
	assert_str(ItemsDB.spoiled_into("hardtack", 100.0)).is_empty()
	# Regional dishes exist for each culture.
	for region in ["caldrenn", "shenlu", "seirune", "veylwood", "solmarch", "ongur", "hollowdeep"]:
		assert_bool(Crafting.item_db().values().any(func(i: Dictionary) -> bool: return i.get("region", "") == region and i.get("category", "") == "food")).override_failure_message(region).is_true()


func test_manuals_point_at_real_techniques_and_realms() -> void:
	var realms: Dictionary = {}
	for r: Dictionary in _json("res://data/skills/realms.json")["realms"]:
		realms[String(r["id"])] = true
	var techs := {}
	for tree: String in _json("res://data/skills/index.json")["trees"]:
		for t: Dictionary in _json("res://data/skills/%s.json" % tree)["techniques"]:
			techs[String(t["id"])] = true
	var n := 0
	for id: String in ItemsDB.ids_in_category("manual"):
		var e := Crafting.item_info(id)
		if e.get("type", "") == "manual":
			n += 1
			assert_bool(realms.has(String(e["realm"]))).override_failure_message("%s: realm %s" % [id, e["realm"]]).is_true()
			assert_array(e["teaches"]).is_not_empty()
			for t: String in e["teaches"]:
				assert_bool(techs.has(t)).override_failure_message("%s teaches unknown %s" % [id, t]).is_true()
		elif e.get("type", "") == "scroll" and e.has("casts"):
			assert_bool(techs.has(String(e["casts"]))).override_failure_message("%s casts unknown %s" % [id, e["casts"]]).is_true()
	assert_int(n).is_greater_equal(50)
	for id in ["manual_heaven_splitting", "manual_basic_breathing", "manual_swordsmanship_t1", "manual_fire_t3"]:
		assert_bool(Crafting.item_exists(id)).override_failure_message(id).is_true()
	# Cultivation pills name real realms.
	for id: String in ItemsDB.ids_of_type("pill"):
		var e2 := Crafting.item_info(id)
		if e2.has("cultivation_realm"):
			assert_bool(realms.has(String(e2["cultivation_realm"]))).override_failure_message(id).is_true()


func test_crops_and_seeds_feed_the_homestead() -> void:
	var crops := ItemsDB.crops()
	assert_int(crops.size()).is_greater_equal(20)
	for crop: String in crops:
		assert_bool(Crafting.item_exists(crop)).override_failure_message(crop).is_true()
		assert_bool(Homestead.CROPS.has(crop)).override_failure_message(crop).is_true()
		assert_int(int(Homestead.CROPS[crop]["days"])).is_greater(0)
	for id: String in ItemsDB.ids_in_category("seed"):
		assert_bool(Homestead.CROPS.has(ItemsDB.crop_of_seed(id))).override_failure_message(id).is_true()
	# The old crops are exactly as before.
	assert_int(int(Homestead.CROPS["wheat"]["days"])).is_equal(4)
	assert_bool(bool(Homestead.CROPS["turnip"].get("winter_hardy", false))).is_true()


func test_enterprise_and_construction_goods_are_items() -> void:
	var Ent := load("res://scripts/realm/enterprise_data.gd")
	for g: String in Ent.GOODS:
		assert_bool(Crafting.item_exists(g)).override_failure_message("enterprise good " + g).is_true()
	var CD := load("res://scripts/realm/construction_data.gd")
	for m: String in CD.MATERIALS:
		assert_bool(Crafting.item_exists(m)).override_failure_message("construction material " + m).is_true()


func test_equipment_visuals_exist() -> void:
	var vis: Dictionary = ItemsDB.extra("visuals")
	assert_int(vis.size()).is_greater_equal(250)
	var errs: Array[String] = []
	for id: String in vis:
		if not Crafting.item_exists(id):
			errs.append("visual for unknown item " + id)
		var v: Dictionary = vis[id]
		for f in ["model", "model_l"]:
			if v.has(f) and not FileAccess.file_exists(String(v[f])):
				errs.append("%s: missing %s" % [id, v[f]])
		if not v.has("attach"):
			errs.append(id + ": no attach bone")
	assert_array(errs).is_empty()
	# Every weapon type and every armour slot maps to a model somewhere.
	for t: String in WEAPON_TYPES:
		assert_bool(ItemsDB.ids_of_type(t).any(func(i: String) -> bool: return ItemsDB.visual(i).has("model"))).override_failure_message(t).is_true()
	for t in ["head_armour", "body_armour", "hands_armour", "feet_armour", "cloak_armour", "shield"]:
		assert_bool(ItemsDB.ids_of_type(t).any(func(i: String) -> bool: return ItemsDB.visual(i).has("model"))).override_failure_message(t).is_true()
	assert_bool(ItemsDB.visual("rift_sword").is_empty()).is_false()


func test_rarity_helpers_and_stat_line() -> void:
	assert_str(ItemsDB.rarity_name(4)).is_equal("Legendary")
	assert_int(ItemsDB.rarity("oathblade_of_caldrenn")).is_equal(4)
	assert_str(ItemsDB.stat_line("steel_sword")).contains("Dmg")
	assert_int(ItemsDB.req_level("rift_sword")).is_greater(50)
	assert_int(ItemsDB.req_level("bread")).is_equal(1)
