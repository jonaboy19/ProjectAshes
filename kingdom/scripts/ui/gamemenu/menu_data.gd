extends RefCounted
## Data adapters for the in-game tabbed menu (game_menu.gd): everything the tabs
## show is computed here from the real game systems, as plain Dictionaries and
## Arrays, so it can be unit-tested without any UI. Autoload objects are passed in
## (defaulting to Life) so tests can hand over fakes.
##
## Where the game has no data yet the value is DERIVED and marked so in the
## comments: weight and reach of items, the six attributes, the level XP bar, the
## Stealth / Soul Power summary rows and the Completed / Failed quest history.

const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Skills := preload("res://scripts/sim/skills.gd")
const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")

# ------------------------------------------------------------------ inventory ----

const CATEGORIES := [["all", "All"], ["weapons", "Weapons"], ["armor", "Armor"],
	["consumables", "Consumables"], ["materials", "Materials"], ["quest", "Quest Items"], ["misc", "Misc"]]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic"]
const RARITY_COLORS := [Color("cfc8b6"), Color("6fd18a"), Color("58a6ff"), Color("b47bff")]
const QUEST_COLOR := Color("f0b85a")
## Item slots in the pack grid (the empty ones are drawn as dark cells).
const PACK_SLOTS := 48

## Weight (kg) and reach (m) are not in data/items.json yet: derived from the
## slot / category, with a few overrides. An item may define "weight" / "reach".
const WEIGHT_BY_CATEGORY := {"food": 0.4, "healing": 0.2, "material": 0.8, "ore": 1.5, "tack": 6.0, "other": 0.5}
const WEIGHT_BY_SLOT := {"main_hand": 2.5, "off_hand": 3.0, "head": 1.5, "body": 4.5, "hands": 0.6, "feet": 1.4, "trinket": 0.1}
const WEIGHT_OVERRIDE := {"iron_dagger": 1.0, "iron_sword": 3.1, "hammer": 3.2, "pickaxe": 3.5, "wood_axe": 2.8,
	"plank": 2.0, "iron_ingot": 2.0, "copper_ingot": 1.8, "coal": 1.0, "saddle": 9.0, "leather": 0.6, "cloth": 0.4,
	"arrowheads": 0.1, "horseshoe": 0.5, "bandage": 0.1, "iron_helm": 2.0, "wooden_shield": 3.4}
const REACH_OVERRIDE := {"iron_dagger": 0.8, "iron_sword": 1.2, "hammer": 0.9, "wood_axe": 1.0, "pickaxe": 1.1}
const TYPE_LABELS := {"iron_dagger": "Dagger", "iron_sword": "One-Handed Sword", "hammer": "Smithing Hammer",
	"wood_axe": "Woodcutting Axe", "pickaxe": "Mining Pick", "iron_helm": "Helm", "leather_cap": "Cap",
	"leather_jerkin": "Body Armour", "leather_gloves": "Gloves", "leather_boots": "Boots",
	"wooden_shield": "Shield", "copper_ring": "Ring", "belt_pouch": "Trinket"}
const FLAVOUR := {"food": "Plain fare, honestly earned.", "healing": "A remedy that has seen a few battlefields.",
	"material": "Raw stuff for someone with patient hands.", "ore": "Heavy, honest rock. The smith will want it.",
	"gear": "Serviceable, and made by someone who cared.", "tack": "For beasts that carry more than you can."}


static func category_of(id: String) -> String:
	var info := Crafting.item_info(id)
	if bool(info.get("quest_item", false)) or String(info.get("category", "")) == "quest":
		return "quest"
	match String(info.get("slot", "")):
		"main_hand":
			return "weapons"
		"off_hand", "head", "body", "hands", "feet":
			return "armor"
		"trinket":
			return "misc"
	match String(info.get("category", "other")):
		"food", "healing":
			return "consumables"
		"material", "ore":
			return "materials"
	return "misc"


static func category_name(cat: String) -> String:
	for c: Array in CATEGORIES:
		if c[0] == cat:
			return String(c[1])
	return cat.capitalize()


static func item_type_label(id: String) -> String:
	if TYPE_LABELS.has(id):
		return String(TYPE_LABELS[id])
	var info := Crafting.item_info(id)
	var slot := String(info.get("slot", ""))
	if slot != "":
		return String(Equipment.SLOT_NAMES.get(slot, slot.capitalize()))
	match String(info.get("category", "other")):
		"food": return "Food"
		"healing": return "Remedy"
		"material": return "Material"
		"ore": return "Ore"
		"tack": return "Tack"
	return "Item"


static func item_weight(id: String) -> float:
	var info := Crafting.item_info(id)
	if info.has("weight"):
		return float(info["weight"])
	if WEIGHT_OVERRIDE.has(id):
		return float(WEIGHT_OVERRIDE[id])
	var slot := String(info.get("slot", ""))
	if slot != "" and WEIGHT_BY_SLOT.has(slot):
		return float(WEIGHT_BY_SLOT[slot])
	return float(WEIGHT_BY_CATEGORY.get(String(info.get("category", "other")), 0.5))


static func item_reach(id: String) -> float:
	var info := Crafting.item_info(id)
	if info.has("reach"):
		return float(info["reach"])
	return float(REACH_OVERRIDE.get(id, 1.0))


static func is_weapon(id: String) -> bool:
	return String(Crafting.item_info(id).get("slot", "")) == "main_hand"


## 0 Common .. 2 Rare: gear by crafted quality (Rough / Fine / Masterwork), other
## goods by price. -1 for quest items.
static func rarity_of(id: String, quality := 1) -> int:
	if category_of(id) == "quest":
		return -1
	if Equipment.is_equippable(id):
		return clampi(quality, 0, 2)
	var price := int(Crafting.item_info(id).get("price", 0))
	if price >= 40:
		return 2
	if price >= 12:
		return 1
	return 0


static func rarity_name(r: int) -> String:
	return "Quest" if r < 0 else String(RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)])


static func rarity_color(r: int) -> Color:
	return QUEST_COLOR if r < 0 else RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]


## What the market pays for one (0 when nothing).
static func value_of(id: String, quality := 1) -> int:
	var base := int(Crafting.item_info(id).get("price", 0))
	if Equipment.is_equippable(id):
		base = int(round(base * float(Crafting.QUALITY_MULT[clampi(quality, 0, 2)])))
	return maxi(0, base)


## Carried stacks grouped by item and quality: [{id, quality, count}], sorted by
## category then name. `inv` is a GLoot inventory (defaults to Life.inventory).
static func stacks(inv: Object = null) -> Array[Dictionary]:
	if inv == null:
		inv = Life.inventory
	var by := {}
	var order: Array[String] = []
	for it: Object in inv.call("get_items"):
		var id := String(it.call("get_prototype").call("get_prototype_id"))
		var q := Equipment.quality_of(it) if Equipment.is_equippable(id) else 1
		var key := "%s#%d" % [id, q]
		if not by.has(key):
			by[key] = {"id": id, "quality": q, "count": 0}
			order.append(key)
		by[key]["count"] = int(by[key]["count"]) + int(it.call("get_stack_size"))
	var out: Array[Dictionary] = []
	for k: String in order:
		out.append(by[k])
	var cat_order := ["weapons", "armor", "consumables", "materials", "quest", "misc"]
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := cat_order.find(category_of(String(a["id"])))
		var cb := cat_order.find(category_of(String(b["id"])))
		if ca != cb:
			return ca < cb
		var na := Crafting.item_name(String(a["id"]))
		var nb := Crafting.item_name(String(b["id"]))
		if na != nb:
			return na < nb
		return int(a["quality"]) > int(b["quality"]))
	return out


static func filter_stacks(all: Array, cat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in all:
		if cat == "all" or category_of(String(s["id"])) == cat:
			out.append(s)
	return out


static func carry_weight(all: Array) -> float:
	var w := 0.0
	for s: Dictionary in all:
		w += item_weight(String(s["id"])) * int(s["count"])
	return w


## Carry limit in kg: 60 plus 4 per point of derived Strength.
static func carry_capacity(strength: int) -> float:
	return 60.0 + 4.0 * strength


static func slot_of(id: String) -> String:
	return Equipment.slot_of(id)


## One stat row for the detail card / compare view.
static func _row(icon: String, label: String, text: String, num := NAN, higher_better := true) -> Dictionary:
	return {"icon": icon, "label": label, "text": text, "num": num, "higher_better": higher_better}


## Everything the detail card shows for one item.
## durability < 0 = like new (pack items). -> {id, name, rarity, rarity_color, type, rows, flavour, ...}
static func item_detail(id: String, quality := 1, durability := -1) -> Dictionary:
	var info := Crafting.item_info(id)
	var gear := Equipment.is_equippable(id)
	var r := rarity_of(id, quality)
	var rows: Array[Dictionary] = []
	var st := Equipment.item_stats(id, quality, durability) if gear else {}
	if is_weapon(id):
		rows.append(_row("stat_damage", "Damage", str(int(round(float(st["damage"])))), float(st["damage"])))
		rows.append(_row("stat_speed", "Speed", "%.2f" % (1.0 + float(st["speed"])), 1.0 + float(st["speed"])))
		rows.append(_row("stat_reach", "Reach", "%.1f m" % item_reach(id), item_reach(id)))
	elif gear:
		rows.append(_row("stat_armour", "Armour", str(int(round(float(st["armour"])))), float(st["armour"])))
		if float(st["damage"]) != 0.0:
			rows.append(_row("stat_damage", "Damage", "+%d" % int(round(float(st["damage"]))), float(st["damage"])))
		if float(st["speed"]) != 0.0:
			rows.append(_row("stat_speed", "Speed", "%+d%%" % int(round(float(st["speed"]) * 100.0)), float(st["speed"])))
	else:
		if float(info.get("nutrition", 0.0)) > 0.0:
			rows.append(_row("stat_nutrition", "Nourishes", str(int(info["nutrition"])), float(info["nutrition"])))
		if int(info.get("heal", 0)) > 0:
			rows.append(_row("stat_heal", "Heals", str(int(info["heal"])), float(info["heal"])))
		if info.has("buff_stat"):
			rows.append(_row("stat_speed", String(info.get("buff_name", "Effect")), "%s  %dh" % [
				stat_text(String(info["buff_stat"]), float(info.get("buff_value", 0.0))), int(info.get("buff_hours", 1))]))
		if info.has("cures"):
			rows.append(_row("stat_heal", "Cures", String(info["cures"]).replace("_", " ").capitalize()))
	rows.append(_row("stat_weight", "Weight", "%.1f kg" % item_weight(id), item_weight(id), false))
	if gear:
		var maxd := Equipment.max_durability(id, quality)
		var cur := maxd if durability < 0 else durability
		rows.append(_row("stat_durability", "Durability", "%d / %d" % [cur, maxd], float(cur)))
	else:
		rows.append(_row("stat_value", "Value", "%d g" % value_of(id, quality), float(value_of(id, quality))))
	var flav := String(info.get("description", ""))
	if flav == "":
		flav = String(FLAVOUR.get(String(info.get("category", "")), ""))
	var usable := float(info.get("nutrition", 0.0)) > 0.0 or int(info.get("heal", 0)) > 0 \
		or info.has("buff_stat") or info.has("cures")
	var typ := item_type_label(id)
	if info.has("tool"):
		typ += " · tool"
	return {"id": id, "name": Crafting.item_name(id), "rarity": r, "rarity_name": rarity_name(r),
		"rarity_color": rarity_color(r), "type": typ, "category": category_of(id), "rows": rows,
		"flavour": flav, "gear": gear, "usable": usable, "slot": slot_of(id), "quality": quality,
		"value": value_of(id, quality)}


static func stat_text(stat: String, v: float) -> String:
	match stat:
		"speed":
			return "%+d%% speed" % int(round(v * 100.0))
		"stamina_regen":
			return "%+d%% stamina" % int(round(v * 100.0))
		"max_health":
			return "%+d health" % int(v)
		"damage":
			return "%+d damage" % int(v)
	return "%+d %s" % [int(v), stat]


## Rows of `detail` with the difference to what is worn in the same slot:
## [{icon, label, text, delta_text, delta (-1/0/1 good/bad sign)}].
static func compare_rows(detail: Dictionary, worn: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var other := item_detail(String(worn.get("id", "")), int(worn.get("quality", 1)), int(worn.get("durability", -1))) \
		if not worn.is_empty() else {}
	for row: Dictionary in detail["rows"]:
		var d := {"icon": row["icon"], "label": row["label"], "text": row["text"], "delta_text": "", "delta": 0}
		if not other.is_empty() and not is_nan(float(row["num"])):
			for orow: Dictionary in other["rows"]:
				if orow["label"] == row["label"] and not is_nan(float(orow["num"])):
					var diff := float(row["num"]) - float(orow["num"])
					if absf(diff) > 0.0001:
						d["delta_text"] = ("%+d" % int(roundf(diff))) if absf(diff - roundf(diff)) < 0.001 else (("%+.2f" % diff) if absf(diff) < 1.0 else ("%+.1f" % diff))
						d["delta"] = 1 if ((diff > 0.0) == bool(row["higher_better"])) else -1
		out.append(d)
	return out


# ------------------------------------------------------------------ character ----

## The six attributes are DERIVED (the game has no attribute system yet): a base of
## 8, plus a share of the average mastery level of the disciplines each leans on,
## plus one per four character levels.
const ATTRIBUTES := [
	{"id": "strength", "name": "Strength", "from": ["soldiering", "smithing", "mining", "swordsmanship"],
		"blurb": "Raw power: blows, hauling, forging. Grows with soldiering, smithing and mining."},
	{"id": "dexterity", "name": "Dexterity", "from": ["archery", "hunting", "leatherwork", "fishing"],
		"blurb": "Quick hands and feet. Grows with archery, hunting and fine handwork."},
	{"id": "endurance", "name": "Endurance", "from": ["farming", "hunting", "soldiering"],
		"blurb": "How long you work and how much you can take. Grows from hard labour."},
	{"id": "intelligence", "name": "Intelligence", "from": ["scholarship", "alchemy", "beast_lore"],
		"blurb": "Learning and reasoning. Grows with scholarship, alchemy and lore."},
	{"id": "wisdom", "name": "Wisdom", "from": ["faith", "healing", "herbalism"],
		"blurb": "Judgement and inner calm. Grows with faith, healing and herb-craft."},
	{"id": "charisma", "name": "Charisma", "from": ["trading", "leadership", "command"],
		"blurb": "Presence and persuasion. Grows with trade, leadership and command."},
]


static func attribute_value(mastery: Object, from: Array, level: int) -> int:
	var extra := 0.0
	if mastery != null and not from.is_empty():
		for d: String in from:
			extra += float(mastery.call("level", d)) - 1.0
		extra /= float(from.size())
	return 8 + int(round(extra / 6.0 + float(maxi(1, level) - 1) / 4.0))


## [{id, name, value, blurb}] in template order.
static func attributes(mastery: Object = null, level := 1) -> Array[Dictionary]:
	if mastery == null:
		mastery = Life.mastery
	var out: Array[Dictionary] = []
	for a: Dictionary in ATTRIBUTES:
		out.append({"id": a["id"], "name": a["name"], "blurb": a["blurb"],
			"value": attribute_value(mastery, a["from"], level)})
	return out


## Level and progress to the next: Life.player_level() = 1 + floor(sqrt(merit)) + age/4 - penalty,
## so the XP shown is War Merit into the current sqrt step. -> {level, into, needed, ratio}
static func level_info(merit: int, level: int) -> Dictionary:
	var m := int(floor(sqrt(float(maxi(0, merit)))))
	var lo := m * m
	var hi := (m + 1) * (m + 1)
	return {"level": level, "into": merit - lo, "needed": hi - lo, "ratio": clampf(float(merit - lo) / float(hi - lo), 0.0, 1.0)}


const SUMMARY := [
	{"id": "combat", "name": "Combat", "icon": "sk_combat", "from": ["swordsmanship", "soldiering", "archery"]},
	{"id": "survival", "name": "Survival", "icon": "sk_survival", "from": ["hunting", "healing", "herbalism", "fishing"]},
	{"id": "crafting", "name": "Crafting", "icon": "sk_crafting", "from": ["smithing", "carpentry", "leatherwork", "cooking", "alchemy"]},
	{"id": "social", "name": "Social", "icon": "sk_social", "from": ["trading", "leadership", "command"]},
	{"id": "stealth", "name": "Stealth", "icon": "sk_stealth", "from": []},
	{"id": "soul", "name": "Soul Power", "icon": "sk_soul", "from": []},
]


## Skills summary for the Character tab: the best mastery level of each family;
## Stealth counts learned Shadow Arts techniques (there is no stealth mastery) and
## Soul Power is the soul tier number.
static func skill_summary(mastery: Object = null, skills: Object = null, soul: Object = null) -> Array[Dictionary]:
	if mastery == null:
		mastery = Life.mastery
	if skills == null:
		skills = Life.skills
	if soul == null:
		soul = Life.soul
	var out: Array[Dictionary] = []
	for s: Dictionary in SUMMARY:
		var v := 1
		var sub := ""
		match String(s["id"]):
			"stealth":
				v = 1 + _learned_in(skills, ["shadow"])
			"soul":
				v = 1 + int(soul.get("tier_index")) if soul != null else 1
				sub = String((soul.call("tier_info") as Dictionary).get("name", "")) if soul != null else ""
			_:
				for d: String in s["from"]:
					v = maxi(v, int(mastery.call("level", d)))
		out.append({"id": s["id"], "name": s["name"], "icon": s["icon"], "value": v, "sub": sub})
	return out


static func _learned_in(skills: Object, trees: Array) -> int:
	var n := 0
	if skills == null:
		return 0
	var ranks: Dictionary = skills.get("ranks")
	var defs: Dictionary = skills.get("techniques")
	for id: String in ranks:
		if defs.has(id) and trees.has(String((defs[id] as Dictionary).get("tree", ""))):
			n += 1
	return n


## Equipment slots around the paper doll: [{slot, label, icon, id, quality, durability, available}].
## The game has no legs slot yet, so "legs" is shown locked.
const DOLL_LEFT := ["head", "body", "hands", "legs"]
const DOLL_RIGHT := ["main_hand", "off_hand", "feet", "trinket"]
const DOLL_LABELS := {"head": "Head", "body": "Chest", "hands": "Hands", "legs": "Legs", "feet": "Feet",
	"main_hand": "Weapon", "off_hand": "Off-hand", "trinket": "Trinket"}


static func doll_slot(slot: String, equipment: Object = null) -> Dictionary:
	if equipment == null:
		equipment = Life.equipment
	var out := {"slot": slot, "label": DOLL_LABELS.get(slot, slot), "icon": "slot_" + slot, "id": "", "quality": 1,
		"durability": -1, "available": Equipment.SLOTS.has(slot)}
	if bool(out["available"]):
		var e: Dictionary = equipment.call("equipped", slot)
		if not e.is_empty():
			out["id"] = String(e["id"])
			out["quality"] = int(e.get("quality", 1))
			out["durability"] = int(e.get("durability", -1))
	return out


# --------------------------------------------------------------------- skills ----

## Discipline groups of the Skills tab. `mastery`: Life.mastery disciplines feeding the
## level bar (the highest counts), `trees`: skills.gd technique trees listing the
## perks; an empty mastery list uses learned techniques as the level instead.
const GROUPS := [
	{"id": "combat", "name": "Combat", "icon": "sk_combat", "mastery": ["swordsmanship", "soldiering"],
		"trees": ["swordsmanship", "fist_palm", "iaido"],
		"desc": "Steel, fists and footwork: how you fight up close."},
	{"id": "defense", "name": "Defense", "icon": "sk_defense", "mastery": ["soldiering"], "trees": ["earth", "water"],
		"desc": "Holding the line, turning blows, mending what is hurt."},
	{"id": "ranged", "name": "Ranged", "icon": "sk_ranged", "mastery": ["archery"], "trees": ["wind", "lightning", "fire"],
		"desc": "Arrows and thrown power: strike before they reach you."},
	{"id": "stealth", "name": "Stealth", "icon": "sk_stealth", "mastery": [], "trees": ["shadow"],
		"desc": "Quiet steps and hidden blades."},
	{"id": "crafting", "name": "Crafting", "icon": "sk_crafting", "mastery": ["smithing", "carpentry", "leatherwork", "cooking", "alchemy"],
		"trees": ["crafting"], "desc": "Things that last are made by patient hands."},
	{"id": "gathering", "name": "Gathering", "icon": "sk_gathering", "mastery": ["farming", "hunting", "fishing", "herbalism", "mining"],
		"trees": ["farming"], "desc": "What the land gives to those who know where to look."},
	{"id": "survival", "name": "Survival", "icon": "sk_survival", "mastery": ["healing", "beast_lore"], "trees": ["qi"],
		"desc": "Staying alive out there: healing, beasts and breath."},
	{"id": "social", "name": "Social", "icon": "sk_social", "mastery": ["trading", "leadership", "command", "faith"],
		"trees": ["command"], "desc": "Coin, words and command: how people answer you."},
	{"id": "knowledge", "name": "Knowledge", "icon": "sk_knowledge", "mastery": ["scholarship", "alchemy", "beast_lore"],
		"trees": [], "desc": "Letters, lore and the manuals you have found."},
]
const SHAPE_ICONS := {"melee": "stat_damage", "projectile": "sk_ranged", "aoe": "sk_soul", "target_aoe": "sk_soul",
	"cone": "sk_soul", "chain": "sk_soul", "dash": "stat_speed", "blink": "stat_speed", "buff": "sk_defense",
	"utility": "sk_crafting"}


static func group_by_id(id: String) -> Dictionary:
	for g: Dictionary in GROUPS:
		if g["id"] == id:
			return g
	return {}


## Level, bar and perks of one discipline group.
## -> {id, name, icon, desc, level, rank_word, ratio, bar_text, perks: [...]}
static func group_info(id: String, mastery: Object = null, skills: Object = null, ctx: Dictionary = {}) -> Dictionary:
	if mastery == null:
		mastery = Life.mastery
	if skills == null:
		skills = Life.skills
	var g := group_by_id(id)
	if g.is_empty():
		return {}
	var perks: Array[Dictionary] = []
	var learned := 0
	var total := 0
	for tid: String in g["trees"]:
		var tree: Dictionary = (skills.get("trees") as Dictionary).get(tid, {})
		for pid: String in tree.get("techniques", []):
			var d: Dictionary = skills.call("get_def", pid)
			if d.is_empty() or not bool(skills.call("is_visible", pid, ctx)):
				continue
			var chk: Dictionary = skills.call("check", pid, ctx)
			var rank := int(skills.call("rank_of", pid))
			total += 1
			learned += 1 if rank > 0 else 0
			var reasons: Array = chk.get("reasons", [])
			perks.append({"id": pid, "name": String(d["name"]), "desc": String(d["desc"]), "kind": String(d["kind"]),
				"tier": int(d["tier"]), "rank": rank, "max_rank": int(d["max_rank"]), "learned": rank > 0,
				"can_learn": bool(chk["ok"]), "maxed": bool(chk["maxed"]), "cost": int(chk["cost"]),
				"reason": String(reasons[0]) if not reasons.is_empty() and not bool(chk["maxed"]) else "",
				"color": Color.from_string(String(tree.get("color", "#f5b841")), Color("f5b841")),
				"icon": "perk" if String(d["kind"]) == "passive" else String(SHAPE_ICONS.get(String(d["shape"]), "sk_combat")),
				"tree": String(tree.get("name", tid))})
	perks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["learned"] != b["learned"]:
			return bool(a["learned"])
		return int(a["tier"]) < int(b["tier"]))
	var lvl := 1
	var ratio := 0.0
	var bar_text := ""
	var word := ""
	if not (g["mastery"] as Array).is_empty():
		var best := ""
		for d: String in g["mastery"]:
			if best == "" or int(mastery.call("level", d)) > int(mastery.call("level", best)):
				best = d
		lvl = int(mastery.call("level", best))
		word = Mastery.rank_word(lvl)
		var prog: Vector2 = mastery.call("xp_progress", best)
		ratio = clampf(prog.x / prog.y, 0.0, 1.0) if prog.y > 0.0 else 1.0
		bar_text = "%d / %d" % [int(prog.x * 100.0), int(prog.y * 100.0)] if prog.y > 0.0 else "Max"
	else:
		lvl = 1 + learned
		ratio = float(learned) / float(maxi(1, total))
		bar_text = "%d / %d" % [learned, total]
		word = "Learned %d of %d" % [learned, total]
	return {"id": id, "name": String(g["name"]), "icon": String(g["icon"]), "desc": String(g["desc"]),
		"level": lvl, "rank_word": word, "ratio": ratio, "bar_text": bar_text, "perks": perks,
		"learned": learned, "total": total}


## The Mastery sub-tab: every discipline with level, rank word, years practised.
## -> [{id, name, level, word, ratio, years}] highest first (practised ones first).
static func mastery_rows(mastery: Object = null) -> Array[Dictionary]:
	if mastery == null:
		mastery = Life.mastery
	var out: Array[Dictionary] = []
	for d: String in Mastery.DISCIPLINES:
		var lvl := int(mastery.call("level", d))
		var prog: Vector2 = mastery.call("xp_progress", d)
		out.append({"id": d, "name": d.replace("_", " ").capitalize(), "level": lvl, "word": Mastery.rank_word(lvl),
			"ratio": clampf(prog.x / prog.y, 0.0, 1.0) if prog.y > 0.0 else 1.0,
			"years": int(mastery.call("years_practised", d))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["level"] != b["level"]:
			return int(a["level"]) > int(b["level"])
		return String(a["name"]) < String(b["name"]))
	return out


## Reputation sub-tab: spheres of the biography plus standing with each faction.
## -> {spheres: [{id, name, value}], factions: [{id, name, value, standing}]}
static func reputation(biography: Object = null, relationships: Object = null, now := 0.0) -> Dictionary:
	if biography == null:
		biography = Life.biography
	if relationships == null:
		relationships = Life.relationships
	var spheres: Array[Dictionary] = []
	for s: String in ["military", "trade", "craft", "farming", "faith", "underworld"]:
		spheres.append({"id": s, "name": s.capitalize(), "value": float(biography.call("rep", s))})
	var factions: Array[Dictionary] = []
	var fnames: Dictionary = relationships.get("faction_names")
	var reps: Dictionary = relationships.get("reputation")
	var ids: Array = []
	for f: String in fnames:
		ids.append(f)
	for f: String in reps:
		if not ids.has(f):
			ids.append(f)
	for f: String in ids:
		factions.append({"id": f, "name": String(relationships.call("faction_name", f)), "value": float(relationships.call("rep", f)),
			"standing": String(relationships.call("standing", f))})
	factions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["value"]) > float(b["value"]))
	return {"spheres": spheres, "factions": factions}


# --------------------------------------------------------------------- quests ----

const MAIN_KINDS := ["war_muster", "war_battle", "apex_hunt", "lord_task"]
## Completed / failed quests are only counted by the game (no records), so the menu
## keeps a session log (GameMenu.log_quest) that Life could feed and persist.
static var quest_log: Array[Dictionary] = []


static func log_quest(q: Dictionary, state: String) -> void:
	var entry := normalise_radiant(q)
	entry["state"] = state
	for e: Dictionary in quest_log:
		if e["id"] == entry["id"]:
			e["state"] = state
			return
	quest_log.append(entry)


static func _reward_rows(reward: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if int(reward.get("gold", 0)) > 0:
		rows.append({"icon": "rw_gold", "text": "%d" % int(reward["gold"]), "kind": "gold"})
	if int(reward.get("xp", 0)) > 0:
		rows.append({"icon": "rw_xp", "text": "%d XP" % int(reward["xp"]), "kind": "xp"})
	if int(reward.get("points", 0)) > 0:
		rows.append({"icon": "rw_xp", "text": "%d Guild points" % int(reward["points"]), "kind": "xp"})
	var rep: Dictionary = reward.get("rep", {})
	for f: String in rep:
		var nm := String(Life.relationships.call("faction_name", f)) if Life.get("relationships") != null else f.capitalize()
		rows.append({"icon": "rw_rep", "text": "Reputation (%s) %+d" % [nm, int(rep[f])], "kind": "rep"})
	for it: Variant in reward.get("items", []):
		rows.append({"icon": "rw_item", "text": Crafting.item_name(String(it)), "kind": "item", "item": String(it)})
	return rows


## A radiant quest (radiant_quests.gd) in the shape the quest tab shows.
static func normalise_radiant(q: Dictionary) -> Dictionary:
	var stages: Array = q.get("stages", [])
	var cur := int(q.get("stage", 0))
	var state := String(q.get("state", "active"))
	var objectives: Array[Dictionary] = []
	for i in stages.size():
		var s: Dictionary = stages[i]
		var text := String(s.get("text", ""))
		if i == cur and state != "done":
			match String(s.get("type", "")):
				"gather":
					text += " (%d/%d)" % [int(q.get("progress", 0)), int(s.get("amount", 1))]
				"kill_den":
					text += " (%d/%d)" % [int(q.get("progress", 0)), int(s.get("kills", 1))]
		objectives.append({"text": text, "done": i < cur or state == "done"})
	var kind := String(q.get("kind", ""))
	var main := MAIN_KINDS.has(kind)
	var pos: Variant = null
	var s2 := RadiantQuests.current_stage(q)
	if s2.has("pos"):
		pos = s2["pos"]
	var giver := String(q.get("giver_name", ""))
	var sub := "Main Quest" if main else "Side Quest"
	if int(q.get("deadline", -1)) >= 0:
		sub += " · Due day %d" % int(q["deadline"])
	elif giver != "":
		sub += " · " + giver
	return {"id": String(q.get("id", "")), "title": String(q.get("title", "Quest")), "subtitle": sub,
		"desc": String(q.get("desc", "")), "group": "main" if main else "side", "state": state,
		"objectives": objectives, "rewards": _reward_rows(q.get("reward", {})), "pos": pos, "source": "radiant"}


## A guild commission (adventurer_guild.gd).
static func normalise_commission(c: Dictionary) -> Dictionary:
	var req := int(c.get("required", 1))
	var prog := int(c.get("progress", 0))
	var t := String(c.get("type", ""))
	var text := String(c.get("title", "Commission"))
	var objectives: Array[Dictionary] = []
	if req > 1:
		objectives.append({"text": "%s (%d/%d)" % [text, prog, req], "done": prog >= req})
	else:
		objectives.append({"text": text, "done": prog >= req})
	objectives.append({"text": "Hand it in at the Guild Hall", "done": false})
	return {"id": "guild_%d" % int(c.get("id", 0)), "title": text, "subtitle": "Guild Commission · Due day %d" % int(c.get("deadline", 0)),
		"desc": "A %s commission posted by the Adventurer Guild. Finish it before the deadline or pay the fine (%d gold)." % [
			t if t != "" else "guild", int((c.get("penalty", {}) as Dictionary).get("gold", 0))],
		"group": "side", "state": String(c.get("state", "accepted")).replace("accepted", "active"),
		"objectives": objectives,
		"rewards": _reward_rows({"gold": int(c.get("reward", 0)), "points": int(c.get("points", 0))}),
		"pos": null, "source": "guild"}


## All quests by state: {active: [], completed: [], failed: []}, each quest
## {id, title, subtitle, desc, group ("main"/"side"), objectives, rewards, pos, tracked, ...}.
## Sources: Life.radiant (radiant + lord + career quests), Life.guild commissions and
## Quest Weaver graph quests when any are running.
static func quests(radiant: Object = null, guild: Object = null) -> Dictionary:
	if radiant == null:
		radiant = Life.radiant
	if guild == null:
		guild = Life.guild
	var out := {"active": [], "completed": [], "failed": []}
	var tracked := String(radiant.get("tracked")) if radiant != null else ""
	if radiant != null:
		for q: Dictionary in radiant.get("active"):
			var n := normalise_radiant(q)
			n["tracked"] = tracked == String(q.get("id", ""))
			out["active"].append(n)
	if guild != null:
		for c: Dictionary in guild.call("active_for", -1):
			var n2 := normalise_commission(c)
			n2["tracked"] = false
			out["active"].append(n2)
	var qw: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/QuestWeaverGlobal") if Engine.get_main_loop() is SceneTree else null
	if qw != null and qw.has_method("get_active_quests"):
		for id: Variant in qw.call("get_active_quests"):
			var objs: Array[Dictionary] = []
			for o: Variant in qw.call("get_active_objectives", id):
				var txt := String(o.get("description", o.get("id", ""))) if o is Dictionary else String(o)
				objs.append({"text": txt, "done": false})
			out["active"].append({"id": "qw_" + String(id), "title": String(id).replace("_", " ").capitalize(),
				"subtitle": "Main Quest", "desc": "", "group": "main", "state": "active", "objectives": objs,
				"rewards": _reward_rows(qw.call("get_quest_rewards", id) if qw.has_method("get_quest_rewards") else {}),
				"pos": null, "tracked": false, "source": "questweaver"})
		for id: Variant in qw.call("get_completed_quests"):
			out["completed"].append({"id": "qw_" + String(id), "title": String(id).replace("_", " ").capitalize(),
				"subtitle": "Main Quest · Completed", "desc": "", "group": "main", "state": "done", "objectives": [],
				"rewards": [], "pos": null, "tracked": false, "source": "questweaver"})
		for id: Variant in qw.call("get_failed_quests"):
			out["failed"].append({"id": "qw_" + String(id), "title": String(id).replace("_", " ").capitalize(),
				"subtitle": "Main Quest · Failed", "desc": "", "group": "main", "state": "failed", "objectives": [],
				"rewards": [], "pos": null, "tracked": false, "source": "questweaver"})
	for e: Dictionary in quest_log:
		if e["state"] == "done":
			out["completed"].append(e)
		elif e["state"] == "failed":
			out["failed"].append(e)
	return out


## Counts the game keeps even without records: {completed, failed}.
static func quest_counts(radiant: Object = null, guild: Object = null) -> Dictionary:
	if radiant == null:
		radiant = Life.radiant
	if guild == null:
		guild = Life.guild
	var done := int(radiant.get("completed")) if radiant != null else 0
	var failed := int(radiant.get("failed")) if radiant != null else 0
	if guild != null:
		var m: Dictionary = guild.call("member", -1)
		done += int(m.get("completed", 0))
		failed += int(m.get("failed", 0))
	return {"completed": done, "failed": failed}


## "540 m north-east" from one world position (Vector2 x/z) to another.
static func direction_text(from: Vector2, to: Vector2) -> String:
	var d := to - from
	var dist := d.length()
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var bearing := fposmod(atan2(d.x, -d.y), TAU)
	var dir := String(names[int(round(bearing / (TAU / 8.0))) % 8])
	return ("%d m %s" % [int(dist), dir]) if dist < 1000.0 else ("%.1f km %s" % [dist / 1000.0, dir])


# ------------------------------------------------------------------------ map ----

const MAP_FILTERS := [["all", "All", "map_all"], ["main", "Main Quest", "map_main"], ["side", "Side Quest", "map_side"],
	["settlement", "Settlement", "map_settlement"], ["poi", "Point of Interest", "map_poi"], ["camp", "Camp", "map_camp"],
	["cave", "Cave", "map_cave"], ["dungeon", "Dungeon", "map_dungeon"], ["fast", "Fast Travel", "map_fast"]]
const CAVE_KINDS := ["mine", "hollow", "cave"]
const DUNGEON_KINDS := ["tower_ruin", "rift", "rift_outpost", "goblin_warren"]


## Does a discovery place (discovery.gd) show under a map filter? Quest filters show
## the quest marker only, so they hide every place.
static func map_filter(filter_id: String, pl: Dictionary) -> bool:
	var kind := String(pl.get("kind", ""))
	match filter_id:
		"all":
			return true
		"main", "side":
			return false
		"settlement":
			return String(pl.get("category", "")) == "settlement"
		"camp":
			return String(pl.get("category", "")) == "camp"
		"cave":
			return CAVE_KINDS.has(kind)
		"dungeon":
			return DUNGEON_KINDS.has(kind)
		"fast":
			return bool(pl.get("travel", false))
		"poi":
			return String(pl.get("category", "")) in ["site", "lore"] and not CAVE_KINDS.has(kind) and not DUNGEON_KINDS.has(kind)
	return true


# -------------------------------------------------------------------- journal ----

## Journal data: {chronicle: [String], biography: [String], titles: [{name, desc}], family: [String], people: [...]}.
static func journal() -> Dictionary:
	var day := int(WorldSim.day)
	var out := {"chronicle": [], "biography": [], "titles": [], "family": [], "people": []}
	var lc: Object = Life.life_courses
	for line: String in (lc.call("news_since", maxi(0, day - 14)) as Array):
		(out["chronicle"] as Array).append(line)
	(out["chronicle"] as Array).reverse()
	for line: String in (Life.biography.call("summary", day) as Array):
		(out["biography"] as Array).append(line)
	for t: Dictionary in (Life.titles.call("earned_list") as Array):
		(out["titles"] as Array).append({"name": String(t.get("name", "")), "desc": String(t.get("desc", t.get("text", "")))})
	out["family"] = family_lines()
	for id: int in (lc.call("known_people") as Array):
		var p: Dictionary = lc.call("person", id)
		var sidx := int(p.get("settlement", -1))
		var place := ""
		if sidx >= 0 and sidx < WorldGen.settlements.size():
			place = String(WorldGen.settlements[sidx]["name"])
		var occ := String(p.get("occupation", ""))
		(out["people"] as Array).append({"id": id, "name": String(p.get("name", "?")), "alive": bool(p.get("alive", true)),
			"age": int(lc.call("age_years", id, day)), "role": occ.capitalize(), "place": place,
			"relation": String(p.get("relation", ""))})
	return out


static func family_lines() -> Array[String]:
	var out: Array[String] = []
	var lp: Object = Life.life_path
	for p: Dictionary in (lp.get("parents") as Array):
		out.append("%s: %s" % [String(p.get("role", "Parent")).capitalize(), String(p.get("name", "?"))])
	var fam: Object = Life.family
	if fam != null:
		var sp: Dictionary = fam.get("spouse")
		if not sp.is_empty():
			out.append("Spouse: %s" % String(sp.get("name", "?")))
		for c: Dictionary in (fam.call("children_list") as Array):
			out.append("Child: %s (age %d)" % [String(c.get("name", "?")), int(c.get("age", 0))])
	return out
