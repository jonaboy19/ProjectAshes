extends RefCounted
## The Region 1 item set: loader and query API over data/items/*.json.
##
## data/items.json (the GLoot protoset) is left exactly as it was; everything new lives in
## data/items/<category>.json (index.json lists the files) and is MERGED into the same item
## database, so old ids and old call sites (Crafting.item_info, Life.item_prop, GLoot) keep working:
##   * Crafting.item_db() calls merge_into() when it builds its table.
##   * register(Life) (called from gathering_items.gd register, which Life already calls) adds the
##     prototypes to the live GLoot protoset and stocks Ashford's market from its shops.
##   * data/items/legacy_patch.json adds missing fields (level, tint, spoil hours ...) to old ids.
##
## Also here: shops (what each merchant stocks by settlement tier), loot tables by danger tier and theme
## (loot_table / roll_loot / monster_drops: the API dungeons, towers and exploration call), armour sets,
## salvage, crops, spoilage and equipment visuals.
##
## Pure data + static helpers: nothing here needs an autoload, so tests/test_items_db.gd runs it directly.

const DIR := "res://data/items/"
const RECIPES_DIR := "res://data/recipes/"
const CRAFTING := "res://scripts/sim/crafting.gd"

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color("cfc8b6"), Color("6fd18a"), Color("58a6ff"), Color("b47bff"), Color("ffb33d")]
const SHOP_TIER_NAMES := {1: "village", 2: "town", 3: "city"}

static var _new_entries: Dictionary = {}
static var _extras: Dictionary = {}
static var _recipe_extra: Dictionary = {}
static var _set_of: Dictionary = {}
static var _salvage: Dictionary = {}
static var _loaded := false


# --- loading -------------------------------------------------------------------------------------------------

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var idx: Variant = _read_json(DIR + "index.json")
	if not (idx is Dictionary):
		return
	for f: String in (idx as Dictionary).get("files", []):
		var d: Variant = _read_json(DIR + f + ".json")
		if d is Dictionary:
			for id: String in d:
				_new_entries[id] = d[id]
	for n: String in (idx as Dictionary).get("extras", []):
		var e: Variant = _read_json(DIR + n + ".json")
		if e is Dictionary:
			_extras[n] = e
	var meta: Variant = _read_json(RECIPES_DIR + "meta.json")
	var recipes: Array = []
	var skills := {}
	var stations := {}
	var adds := {}
	if meta is Dictionary:
		skills = (meta as Dictionary).get("skills", {})
		stations = (meta as Dictionary).get("stations", {})
		adds = (meta as Dictionary).get("station_skill_adds", {})
		for sk: String in (meta as Dictionary).get("files", []):
			var r: Variant = _read_json(RECIPES_DIR + sk + ".json")
			if r is Dictionary:
				recipes.append_array((r as Dictionary).get("recipes", []))
	_recipe_extra = {"skills": skills, "stations": stations, "station_skill_adds": adds, "recipes": recipes}
	var salv: Variant = _read_json(RECIPES_DIR + "salvage.json")
	if salv is Dictionary:
		for s: Dictionary in (salv as Dictionary).get("salvage", []):
			_salvage[String(s["item"])] = s
	var sets: Dictionary = _extras.get("sets", {})
	for sid: String in sets:
		for pid: String in (sets[sid] as Dictionary).get("pieces", []):
			_set_of[pid] = sid


static func _crafting() -> GDScript:
	return load(CRAFTING) as GDScript


## Every new item entry (id -> properties), without the old data/items.json ones.
static func new_entries() -> Dictionary:
	_load()
	return _new_entries


static func new_ids() -> Array:
	_load()
	return _new_entries.keys()


static func extra(name: String) -> Dictionary:
	_load()
	return _extras.get(name, {})


## Adds the new entries to `raw` (an id -> entry table, ids already there are kept) and fills in missing
## fields of old ids from legacy_patch.json. Used by Crafting.item_db().
static func merge_into(raw: Dictionary) -> void:
	_load()
	for id: String in _new_entries:
		if not raw.has(id):
			raw[id] = (_new_entries[id] as Dictionary).duplicate()
	var patch: Dictionary = _extras.get("legacy_patch", {})
	for id: String in patch:
		if not raw.has(id):
			continue
		var e: Dictionary = raw[id]
		for k: String in (patch[id] as Dictionary):
			if not e.has(k):
				e[k] = patch[id][k]


## Extra crafting data: {skills, stations, station_skill_adds, recipes[]}.
static func recipe_extras() -> Dictionary:
	_load()
	return _recipe_extra


## Adds the prototypes to the live GLoot protoset (idempotent) and stocks Ashford's market. Safe to call
## any number of times; gathering_items.gd register() calls it.
static func register(life: Node) -> void:
	if life == null:
		return
	_load()
	var inv: Variant = life.get("inventory")
	if inv != null and inv.protoset != null:
		var json: JSON = inv.protoset
		var tree: Variant = inv.get_prototree()
		var data: Variant = json.data
		for id: String in _new_entries:
			var entry: Dictionary = _new_entries[id]
			if data is Dictionary and not (data as Dictionary).has(id):
				(data as Dictionary)[id] = entry.duplicate()
			if tree.has_prototype(id):
				continue
			var proto: Variant = tree.get_root().inherit(id)
			for key: String in entry:
				proto.set_property(key, entry[key])
		var patch: Dictionary = _extras.get("legacy_patch", {})
		for id: String in patch:
			if not tree.has_prototype(id):
				continue
			var legacy_proto: Variant = tree.get_prototype(id)
			for key: String in (patch[id] as Dictionary):
				if not legacy_proto.has_property(key):
					legacy_proto.set_property(key, patch[id][key])
	var market: Variant = life.get("market")
	if market != null and not bool((market as Object).get_meta("items_db_stocked", false)):
		(market as Object).set_meta("items_db_stocked", true)
		var pop := 120
		if not WorldGen.settlements.is_empty():
			pop = int(WorldGen.settlements[0].get("population", 120))
		stock_settlement(market, "village", pop, ["smithy", "market"], 0)


# --- item info -------------------------------------------------------------------------------------------------

static func info(id: String) -> Dictionary:
	return _crafting().call("item_info", id)


static func rarity(id: String) -> int:
	return clampi(int(info(id).get("rarity", 0)), 0, 4)


static func rarity_name(r: int) -> String:
	return RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)]


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]


static func req_level(id: String) -> int:
	var d := info(id)
	return int(d.get("req_level", d.get("level", 1)))


## True when a character of `level` may use the item (no requirement: always).
static func meets_requirements(id: String, level: int) -> bool:
	return level >= req_level(id)


static func type_of(id: String) -> String:
	return String(info(id).get("type", ""))


static func ids_of_type(type: String) -> Array[String]:
	var out: Array[String] = []
	var db: Dictionary = _crafting().call("item_db")
	for id: String in db:
		if String((db[id] as Dictionary).get("type", "")) == type:
			out.append(id)
	out.sort()
	return out


static func ids_in_category(category: String) -> Array[String]:
	var out: Array[String] = []
	var db: Dictionary = _crafting().call("item_db")
	for id: String in db:
		if String((db[id] as Dictionary).get("category", "")) == category:
			out.append(id)
	out.sort()
	return out


## Short stat line for tooltips: "Dmg 9 · Reach 1.2 · Req lv 14".
static func stat_line(id: String) -> String:
	var d := info(id)
	var parts := PackedStringArray()
	if d.has("damage") and float(d["damage"]) > 0.0:
		parts.append("Dmg %d" % int(d["damage"]))
	if d.has("magic"):
		parts.append("Magic %d" % int(d["magic"]))
	if d.has("armour") and float(d["armour"]) > 0.0:
		parts.append("Armour %d" % int(d["armour"]))
	if d.has("block"):
		parts.append("Block %d%%" % int(round(float(d["block"]) * 100.0)))
	if d.has("nutrition") and float(d["nutrition"]) > 0.0:
		parts.append("Food %d" % int(d["nutrition"]))
	if d.has("heal") and int(d["heal"]) > 0:
		parts.append("Heal %d" % int(d["heal"]))
	if d.has("req_level") and int(d["req_level"]) > 1:
		parts.append("Req lv %d" % int(d["req_level"]))
	return " · ".join(parts)


# --- spoilage --------------------------------------------------------------------------------------------------------

## Hours until the item spoils; 0 = never.
static func spoil_hours(id: String) -> float:
	return float(info(id).get("spoil_hours", 0.0))


## What an item of `age_hours` has become ("" = still fine, else the spoiled item id).
static func spoiled_into(id: String, age_hours: float) -> String:
	var h := spoil_hours(id)
	if h <= 0.0 or age_hours < h:
		return ""
	return String(info(id).get("spoils_into", "spoiled_food"))


## Shelf life of at least this many hours counts as preserved (jerky, smoked, salted, pickled, dried, hardtack ...): it
## keeps its nutrition longer before it goes off.
const PRESERVED_HOURS := 1000.0
## Fresh food loses nutrition from this share of its shelf life on (preserved food later), down to STALE_FLOOR just before it spoils.
const STALE_START := 0.5
const STALE_START_PRESERVED := 0.8
const STALE_FLOOR := 0.6
## Stack property that carries a pack stack's age in game hours (absent = fresh).
const AGE_PROP := "age_hours"


static func is_preserved(id: String) -> bool:
	return spoil_hours(id) >= PRESERVED_HOURS


## Nutrition multiplier of food that is `age_hours` old: 1.0 while fresh, falling to STALE_FLOOR as it nears spoiling
## (0.0 once spoiled). Items without spoil data are always 1.0.
static func freshness(id: String, age_hours: float) -> float:
	var h := spoil_hours(id)
	if h <= 0.0:
		return 1.0
	var f := age_hours / h
	if f >= 1.0:
		return 0.0
	var start := STALE_START_PRESERVED if is_preserved(id) else STALE_START
	if f <= start:
		return 1.0
	return lerpf(1.0, STALE_FLOOR, (f - start) / (1.0 - start))


## Closed-form ageing of one stack: {age: new age in hours, into: the spoiled item id ("" = still good)}. Any amount of time
## (a night's sleep, a week of fast travel) costs the same single step.
static func age_by(id: String, age_hours: float, add_hours: float) -> Dictionary:
	var age := maxf(age_hours, 0.0) + maxf(add_hours, 0.0)
	return {"age": age, "into": spoiled_into(id, age)}


# --- sets --------------------------------------------------------------------------------------------------------------

static func set_of(id: String) -> String:
	_load()
	return String(_set_of.get(id, ""))


static func set_info(set_id: String) -> Dictionary:
	return extra("sets").get(set_id, {})


## Summed set bonuses for the worn item ids: {stat: value}. A set gives the bonus of its highest threshold met.
static func set_bonus_stats(worn: Array) -> Dictionary:
	_load()
	var counts := {}
	for id: Variant in worn:
		var s := set_of(String(id))
		if s != "":
			counts[s] = int(counts.get(s, 0)) + 1
	var out := {}
	for s: String in counts:
		var bonuses: Dictionary = set_info(s).get("bonuses", {})
		var best := 0
		for k: String in bonuses:
			if int(k) <= int(counts[s]) and int(k) > best:
				best = int(k)
		if best > 0:
			for stat: String in (bonuses[str(best)] as Dictionary):
				out[stat] = float(out.get(stat, 0.0)) + float(bonuses[str(best)][stat])
	return out


# --- salvage -------------------------------------------------------------------------------------------------------------

## {item, yield: [{item, count}], skill, stations, level, xp} or {} when the item can't be broken down.
static func salvage_for(id: String) -> Dictionary:
	_load()
	return _salvage.get(id, {})


# --- crops ---------------------------------------------------------------------------------------------------------------------

## crop item id -> {days, seasons: ["SPRING", ...], winter_hardy, asset}
static func crops() -> Dictionary:
	return extra("crops")


## The crop a seed item plants ("" when it isn't a seed).
static func crop_of_seed(seed_id: String) -> String:
	return String(info(seed_id).get("plants", ""))


# --- shops ------------------------------------------------------------------------------------------------------------------------

static func shop_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in extra("shops").get("shops", {}):
		out.append(id)
	out.sort()
	return out


static func shop(id: String) -> Dictionary:
	return extra("shops").get("shops", {}).get(id, {})


## Everything the shop sells at `tier` (1 village, 2 town, 3 city), tiers are cumulative:
## [{item, stock, daily (made locally per day), import (wagons per day), price}].
static func shop_goods(shop_id: String, tier: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := shop(shop_id)
	if s.is_empty():
		return out
	var tiers: Dictionary = s.get("tiers", {})
	for t in range(1, clampi(tier, 1, 3) + 1):
		for e: Array in tiers.get(str(t), []):
			out.append({"item": String(e[0]), "stock": int(e[1]), "daily": float(e[2]), "import": float(e[3]),
				"price": int(info(String(e[0])).get("price", 1))})
	return out


## Which shops a settlement has: by kind ("hamlet", "village", "frontier_town", "town", "castle"), population
## and its identity tags (settlements.gd ident: smithy, market, tower, temple, library, barracks, wall, gate).
static func shops_for_settlement(kind: String, population := 100, idents: Array = []) -> Array[String]:
	var cfg: Dictionary = extra("shops").get("settlements", {})
	var def: Dictionary = cfg.get(kind, cfg.get("village", {}))
	var out: Array[String] = []
	for s: String in def.get("shops", []):
		if kind == "village" and population < 45 and s in ["blacksmith", "baker", "carpenter", "farm_supply"]:
			continue
		out.append(s)
	var idm: Dictionary = extra("shops").get("identity", {})
	for tag: Variant in idents:
		for s: String in idm.get(String(tag), []):
			if not out.has(s):
				out.append(s)
	return out


static func settlement_tier(kind: String) -> int:
	var cfg: Dictionary = extra("shops").get("settlements", {})
	return int((cfg.get(kind, cfg.get("village", {})) as Dictionary).get("tier", 1))


## Adds the goods of `shop_ids` at `tier` to an RAMarket (scripts/sim/market.gd). Goods already on the market are
## left alone; made-per-day and import trickle give the shelves their restocking. Returns the goods added.
static func stock_market(market: Object, shop_ids_: Array, tier: int, rng_seed := 0) -> int:
	var added := 0
	var rng := RandomNumberGenerator.new()
	var base: Dictionary = market.get("base_price")
	for sid: Variant in shop_ids_:
		rng.seed = hash([rng_seed, String(sid)])
		for g: Dictionary in _shelf(shop_goods(String(sid), tier), rng):
			var item := String(g["item"])
			if base.has(item):
				continue
			var stock := maxi(1, int(round(float(g["stock"]) * (0.8 + 0.4 * rng.randf()))))
			market.call("add_good", item, int(g["price"]), stock, 0)
			if float(g["daily"]) > 0.0:
				(market.get("produce") as Dictionary)[item] = float(g["daily"])
			if float(g["import"]) > 0.0:
				(market.get("imports") as Dictionary)[item] = float(g["import"])
			added += 1
	return added


## A shop never stocks everything it could: the first ESSENTIAL goods (the cheap staples) always, then a random
## share of the rest up to SHELF_CAP, so neighbouring towns differ and markets stay a readable size.
const ESSENTIAL := 10
const SHELF_CAP := 30


static func _shelf(goods: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	if goods.size() <= SHELF_CAP:
		return goods
	var rest: Array[Dictionary] = goods.slice(ESSENTIAL)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Dictionary = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	var out: Array[Dictionary] = goods.slice(0, ESSENTIAL)
	out.append_array(rest.slice(0, SHELF_CAP - ESSENTIAL))
	return out


## Stocks a settlement's market from the shops its kind, size and identity give it.
static func stock_settlement(market: Object, kind: String, population := 100, idents: Array = [], rng_seed := 0) -> int:
	return stock_market(market, shops_for_settlement(kind, population, idents), settlement_tier(kind), rng_seed)


# --- loot --------------------------------------------------------------------------------------------------------------------------------

static func loot_themes() -> Array[String]:
	var out: Array[String] = []
	for t: String in extra("loot").get("themes", {}):
		out.append(t)
	out.sort()
	return out


## Danger tier 1..5 (tier 1 = levels 1-14, 5 = 46-60). Used by dungeons, towers, chests and exploration.
## Returns {tier, theme, rolls: [min, max], gold: [min, max], entries: [[item, weight, min, max]]}, or {} for
## an unknown theme. The theme falls back to "chest_common" when `fallback` is true.
static func loot_table(tier: int, theme: String, fallback := false) -> Dictionary:
	var themes: Dictionary = extra("loot").get("themes", {})
	var th := theme
	if not themes.has(th):
		if not fallback:
			return {}
		th = "chest_common"
	var t := clampi(tier, 1, 5)
	var tab: Dictionary = (themes[th] as Dictionary).get("tiers", {}).get(str(t), {})
	if tab.is_empty():
		return {}
	return {"tier": t, "theme": th, "rolls": tab.get("rolls", [1, 1]), "gold": tab.get("gold", [0, 0]), "entries": tab.get("entries", [])}


## Rolls a table: {items: [{item, count}], gold}. `bonus_rolls` adds rolls (boss rooms, big chests).
static func roll_loot(tier: int, theme: String, rng: RandomNumberGenerator = null, bonus_rolls := 0) -> Dictionary:
	var tab := loot_table(tier, theme, true)
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var out := {"items": [], "gold": 0}
	if tab.is_empty():
		return out
	var entries: Array = tab["entries"]
	var total := 0.0
	for e: Array in entries:
		total += float(e[1])
	var rolls: Array = tab["rolls"]
	var n := r.randi_range(int(rolls[0]), int(rolls[1])) + maxi(0, bonus_rolls)
	var merged := {}
	for i in n:
		if total <= 0.0:
			break
		var pick := r.randf() * total
		for e: Array in entries:
			pick -= float(e[1])
			if pick <= 0.0:
				var c := r.randi_range(int(e[2]), int(e[3]))
				merged[String(e[0])] = int(merged.get(String(e[0]), 0)) + c
				break
	for id: String in merged:
		out["items"].append({"item": id, "count": int(merged[id])})
	var g: Array = tab["gold"]
	out["gold"] = r.randi_range(int(g[0]), int(g[1]))
	return out


## A monster's drops: its guaranteed-chance table plus (when `extra_roll` > 0) rolls on its theme table.
## species: wolf, corrupted_wolf, boar, bear, troll, wyvern, goblin, goblin_chief, orc, orc_chief, bandit, bandit_leader,
## skeleton, ash_ghost, giant_spider, scar_beast, rift_creature, rabbit, deer, fox. Returns [{item, count}].
static func monster_drops(species: String, rng: RandomNumberGenerator = null, extra_roll := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: Dictionary = extra("loot").get("monsters", {}).get(species, {})
	if m.is_empty():
		return out
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	for d: Array in m.get("drops", []):
		if r.randf() < float(d[1]):
			out.append({"item": String(d[0]), "count": r.randi_range(int(d[2]), int(d[3]))})
	if extra_roll > 0:
		var res := roll_loot(int(m.get("tier", 1)), String(m.get("theme", "beast")), r, extra_roll - 1)
		for e: Dictionary in res["items"]:
			out.append(e)
	return out


static func monster_species() -> Array[String]:
	var out: Array[String] = []
	for s: String in extra("loot").get("monsters", {}):
		out.append(s)
	out.sort()
	return out


# --- equipment visuals -------------------------------------------------------------------------------------------------------------------------

## {model (res path), model_l?, mirror_l?, attach (bone), scale, tint?} or {tint_only, attach}; {} when the item has no mesh.
static func visual(id: String) -> Dictionary:
	return extra("visuals").get(id, {})


## A ready Node3D for the item's model, tinted; null without a model. `left` picks the left-hand variant
## (mirrored when the piece has only one). Attach it to a BoneAttachment3D named after visual(id)["attach"].
static func visual_node(id: String, left := false) -> Node3D:
	var v := visual(id)
	if v.is_empty() or not v.has("model"):
		return null
	var path := String(v["model"])
	if left and v.has("model_l"):
		path = String(v["model_l"])
	if not ResourceLoader.exists(path):
		return null
	var scene: Variant = load(path)
	if not (scene is PackedScene):
		return null
	var root := Node3D.new()
	root.name = "Vis_" + id
	var inst: Node = (scene as PackedScene).instantiate()
	root.add_child(inst)
	var s := float(v.get("scale", 1.0))
	root.scale = Vector3(s, s, s)
	if left and bool(v.get("mirror_l", false)):
		root.scale.x = -s
	var tint: Variant = v.get("tint")
	if tint is String and String(tint) != "":
		_tint_meshes(inst, Color(String(tint)))
	return root


static func _tint_meshes(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is StandardMaterial3D:
					var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = dup.albedo_color * c.lerp(Color.WHITE, 0.35)
					mi.set_surface_override_material(i, dup)
	for ch in n.get_children():
		_tint_meshes(ch, c)
