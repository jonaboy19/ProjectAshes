extends RefCounted
## Crafting and cooking: recipes (data/recipes.json), skills that level with use,
## quality tiers rolled from skill, and the craft stations the player can reach.
##
## Pure data plus a few static helpers, so it tests without autoloads. Anything
## that holds items works as the inventory: it needs count(id), give(id, n) and
## take(id, n) -> bool (the Life autoload does). When it also exposes a GLoot
## `inventory`, crafted gear is created as its own instance carrying the rolled
## "quality" property (GLoot keeps it apart from other stacks and saves it).
##
## Stations: world campfires come from WorldGen.sites (any part whose asset names
## a campfire, e.g. the bandit camp's); interiors register their hearth, anvil,
## workbench and alchemy table through scan_interior(room) when a room loads.
## stations_near(pos) lists what is in reach, nearest first.
##
## Skills: xp per craft, levels 1..MAX_LEVEL. Holding the right post (smithy,
## inn, woodcutters in RACareers) or carrying the skill's tool speeds learning.

signal crafted(result: Dictionary)
## A tense craft went wrong (ctx.tension): materials partly lost. Not "crafted": nothing was made.
signal craft_failed(result: Dictionary)
signal skill_up(skill: String, level: int)
signal station_invalidated(ref: String, generation: int)

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const StationIdentity := preload("res://scripts/systems/station_identity.gd")
const RECIPES_PATH := "res://data/recipes.json"
const ITEMS_PATH := "res://data/items.json"

const MAX_LEVEL := 10
enum Quality { ROUGH, FINE, MASTERWORK }
const QUALITY_NAMES := ["Rough", "Fine", "Masterwork"]
## Gear stats and durability scale by quality.
const QUALITY_MULT := [0.75, 1.0, 1.35]
const QUALITY_COLORS := [Color("9a9384"), Color("3ec7c2"), Color("f5b841")]

## Reach of a station (horizontal metres) and the height band it covers.
const STATION_RADIUS := 3.5
const CAMPFIRE_RADIUS := 6.0
const STATION_HEIGHT := 4.0

## Interior scene root -> [[station kind, node path ("" = room origin), label, radius]].
## Node paths are the markers and lights of scenes/interiors/*_interior.tscn.
const INTERIOR_STATIONS := {
	"InnInterior": [["hearth", "FireLight", "Inn Hearth", 3.5]],
	"HouseInterior": [["hearth", "FireLight", "Hearth", 3.0]],
	"GuildInterior": [["hearth", "FireLight", "Guild Hearth", 3.0]],
	"BlacksmithInterior": [["anvil", "NPCs/NPC_Blacksmith", "Anvil", 3.5], ["workbench", "", "Workbench", 6.0]],
	"HealerInterior": [["alchemy_table", "TableCandle", "Healer's Table", 3.0]],
}

## RACareers org id -> skills its members learn faster, and by how much.
const CAREER_SKILLS := {"smithy": ["smithing", "carpentry"], "inn": ["cooking"], "woodcutters": ["carpentry"]}
const CAREER_XP_MULT := 1.5
## Carrying the tool for a skill (in the pack or in hand) speeds learning.
const TOOLS := {"smithing": "hammer", "mining": "pickaxe", "carpentry": "wood_axe"}
const TOOL_XP_MULT := 1.25

## skill -> total xp
var xp: Dictionary = {}
var rng := RandomNumberGenerator.new()
var recipes: Array[Dictionary] = []
var skills: Dictionary = {}
var station_kinds: Dictionary = {}
var station_identity := StationIdentity.new()
var _adhoc_station_slot := 0
var _by_id: Dictionary = {}
## [{kind, name, pos: Vector3 (y = NAN: any height), radius, owner: instance id or 0}]
var _stations: Array[Dictionary] = []
var _sites_added := false

static var _item_db: Dictionary = {}
static var _recipe_data: Dictionary = {}


func _init(seed_value := 4242) -> void:
	rng.seed = seed_value
	var data := recipe_data()
	skills = data.get("skills", {})
	station_kinds = data.get("stations", {})
	for r: Dictionary in data.get("recipes", []):
		recipes.append(r)
		_by_id[String(r["id"])] = r
	station_identity.descriptor_invalidated.connect(_on_station_invalidated)


# --- data ------------------------------------------------------------------------

static func recipe_data() -> Dictionary:
	if _recipe_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
		_recipe_data = d if d is Dictionary else {}
		_merge_recipe_extras(_recipe_data)
	return _recipe_data


## data/recipes/*.json: new skills, stations and recipes are added to data/recipes.json's (old ids win).
static func _merge_recipe_extras(data: Dictionary) -> void:
	var ex: Dictionary = ItemsDB.recipe_extras()
	if ex.is_empty():
		return
	var skills: Dictionary = data.get("skills", {})
	for k: String in ex.get("skills", {}):
		if not skills.has(k):
			skills[k] = ex["skills"][k]
	data["skills"] = skills
	var stations: Dictionary = data.get("stations", {})
	for k: String in ex.get("stations", {}):
		if not stations.has(k):
			stations[k] = (ex["stations"][k] as Dictionary).duplicate(true)
	for k: String in ex.get("station_skill_adds", {}):
		if stations.has(k):
			var list: Array = stations[k].get("skills", [])
			for sk: String in ex["station_skill_adds"][k]:
				if not list.has(sk):
					list.append(sk)
			stations[k]["skills"] = list
	data["stations"] = stations
	var recipes: Array = data.get("recipes", [])
	var have := {}
	for r: Dictionary in recipes:
		have[String(r["id"])] = true
	for r: Dictionary in ex.get("recipes", []):
		if not have.has(String(r["id"])):
			recipes.append(r)
			have[String(r["id"])] = true
	data["recipes"] = recipes


## Every item prototype with inheritance resolved: data/items.json plus the
## hunting/fishing/foraging items that gathering_items.gd registers at runtime.
static func item_db() -> Dictionary:
	if not _item_db.is_empty():
		return _item_db
	var raw: Dictionary = {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	if d is Dictionary:
		raw = (d as Dictionary).duplicate(true)
	for id: String in Gathering.ITEMS:
		if not raw.has(id):
			raw[id] = (Gathering.ITEMS[id] as Dictionary).duplicate()
	ItemsDB.merge_into(raw)        # data/items/*.json: the Region 1 set (old ids keep working)
	for id: String in raw:
		_item_db[id] = _resolve(raw, id, 0)
	return _item_db


static func _resolve(raw: Dictionary, id: String, depth: int) -> Dictionary:
	var e: Dictionary = raw.get(id, {})
	var out := {}
	var base := String(e.get("inherits", ""))
	if base != "" and raw.has(base) and depth < 8:
		out = _resolve(raw, base, depth + 1)
	for k: String in e:
		if k != "inherits":
			out[k] = e[k]
	out["id"] = id
	return out


## Base prototypes that only exist to be inherited ("food", "gear").
static func is_abstract(id: String) -> bool:
	return id in ["food", "gear"]


static func item_exists(id: String) -> bool:
	return item_db().has(id) and not is_abstract(id)


static func item_info(id: String) -> Dictionary:
	return item_db().get(id, {})


static func item_name(id: String) -> String:
	return String(item_info(id).get("name", id.capitalize()))


## "venison|pork" -> ["venison", "pork"]
static func alternatives(spec: String) -> PackedStringArray:
	return spec.split("|", false)


static func quality_name(q: int) -> String:
	return QUALITY_NAMES[clampi(q, 0, 2)]


func recipe(id: String) -> Dictionary:
	return _by_id.get(id, {})


func recipe_name(r: Dictionary) -> String:
	if r.has("name"):
		return String(r["name"])
	var out: Dictionary = r.get("output", {})
	return item_name(String(out.get("item", r.get("id", "?"))))


func skill_name(skill: String) -> String:
	return String(skills.get(skill, {}).get("name", skill.capitalize()))


func station_name(kind: String) -> String:
	return String(station_kinds.get(kind, {}).get("name", kind.capitalize()))


## Recipes usable at any of `kinds` (all recipes when kinds is empty), by skill then level.
func recipes_for(kinds: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in recipes:
		if kinds.is_empty() or _at_station(r, kinds):
			out.append(r)
	var order := skills.keys()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := order.find(a["skill"])
		var sb := order.find(b["skill"])
		if sa != sb:
			return sa < sb
		if int(a.get("level", 1)) != int(b.get("level", 1)):
			return int(a.get("level", 1)) < int(b.get("level", 1))
		return String(a["id"]) < String(b["id"]))
	return out


func _at_station(r: Dictionary, kinds: Array) -> bool:
	for k in r.get("stations", []):
		if kinds.has(k):
			return true
	return false


## Problems in the recipe data (unknown items, skills, stations); empty when sound.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var seen := {}
	for r in recipes:
		var id := String(r.get("id", ""))
		if id == "" or seen.has(id):
			errs.append("recipe id missing or duplicated: '%s'" % id)
		seen[id] = true
		if not skills.has(r.get("skill", "")):
			errs.append("%s: unknown skill %s" % [id, r.get("skill", "")])
		var st: Array = r.get("stations", [])
		if st.is_empty():
			errs.append("%s: no stations" % id)
		for k in st:
			if not station_kinds.has(k):
				errs.append("%s: unknown station %s" % [id, k])
			elif not (station_kinds[k].get("skills", []) as Array).has(r.get("skill", "")):
				errs.append("%s: station %s doesn't teach %s" % [id, k, r.get("skill", "")])
		var inputs: Array = r.get("inputs", [])
		if inputs.is_empty():
			errs.append("%s: no inputs" % id)
		for inp: Dictionary in inputs:
			if int(inp.get("count", 0)) <= 0:
				errs.append("%s: bad count for %s" % [id, inp.get("item", "")])
			for alt in alternatives(String(inp.get("item", ""))):
				if not item_exists(alt):
					errs.append("%s: unknown ingredient %s" % [id, alt])
		if bool(r.get("repair", false)):
			continue
		var out: Dictionary = r.get("output", {})
		if not item_exists(String(out.get("item", ""))) or int(out.get("count", 0)) <= 0:
			errs.append("%s: bad output %s" % [id, out])
		if int(r.get("level", 1)) < 1 or int(r.get("level", 1)) > MAX_LEVEL:
			errs.append("%s: level out of range" % id)
	return errs


# --- skills ------------------------------------------------------------------------

## Total xp needed to reach `level` (level 1 needs 0; each level costs 30 more than the last).
static func xp_for_level(level: int) -> int:
	var l := clampi(level, 1, MAX_LEVEL) - 1
	return 15 * l * (l + 1)


static func level_from_xp(total: int) -> int:
	var l := 1
	while l < MAX_LEVEL and total >= xp_for_level(l + 1):
		l += 1
	return l


func level(skill: String) -> int:
	return level_from_xp(int(xp.get(skill, 0)))


## x = xp into the current level, y = xp the level needs (0 at the cap).
func xp_progress(skill: String) -> Vector2i:
	var total := int(xp.get(skill, 0))
	var l := level_from_xp(total)
	if l >= MAX_LEVEL:
		return Vector2i(0, 0)
	return Vector2i(total - xp_for_level(l), xp_for_level(l + 1) - xp_for_level(l))


## Adds xp; returns the new level (emits skill_up on each level gained).
func add_xp(skill: String, amount: int) -> int:
	var before := level(skill)
	xp[skill] = int(xp.get(skill, 0)) + maxi(0, amount)
	var after := level(skill)
	for l in range(before + 1, after + 1):
		skill_up.emit(skill, l)
	return after


## XP multiplier from the player's post (RACareers org id, "" for none).
static func career_xp_mult(skill: String, org_id: String) -> float:
	return CAREER_XP_MULT if (CAREER_SKILLS.get(org_id, []) as Array).has(skill) else 1.0


# --- quality ------------------------------------------------------------------------

## [rough, fine, masterwork] chances for a crafter of `lvl` making a recipe of
## `recipe_level`. Always sums to 1; every tier is possible except masterwork
## below the recipe's level.
static func quality_odds(lvl: int, recipe_level := 1) -> PackedFloat32Array:
	var margin := clampi(lvl - recipe_level, -MAX_LEVEL, MAX_LEVEL)
	var master := clampf(0.03 + 0.05 * margin, 0.0, 0.5) if margin >= 0 else 0.0
	var rough := clampf(0.55 - 0.09 * margin, 0.05, 0.95)
	var fine := maxf(0.0, 1.0 - master - rough)
	return PackedFloat32Array([rough, fine, master])


## Tier for a uniform roll in [0, 1).
static func quality_for_roll(lvl: int, recipe_level: int, roll: float) -> int:
	var o := quality_odds(lvl, recipe_level)
	var r := clampf(roll, 0.0, 0.999999)
	if r < o[2]:
		return Quality.MASTERWORK
	if r < o[2] + o[1]:
		return Quality.FINE
	return Quality.ROUGH


func roll_quality(lvl: int, recipe_level := 1) -> int:
	return quality_for_roll(lvl, recipe_level, rng.randf())


## Chance a craft succeeds when tension is on: 0.55 + 0.04 per skill level over the recipe, plus a small tool
## bonus (`tool_mult` is tool_bonus(), 1.0 without a tool), clamped to [0.35, 0.98].
static func success_chance(lvl: int, recipe_level: int, tool_mult := 1.0) -> float:
	return clampf(0.55 + 0.04 * float(lvl - recipe_level) + (tool_mult - 1.0) * 0.2, 0.35, 0.98)


## Chance a successful craft is a critical success (a quality tier up, or a bonus unit): 3% at the recipe's
## level, +1.5% per level above (nothing below the recipe's level), max 20%.
static func crit_chance(lvl: int, recipe_level: int) -> float:
	var margin := lvl - recipe_level
	return clampf(0.03 + 0.015 * float(margin), 0.0, 0.20) if margin >= 0 else 0.0


## Shifts a quality roll by the mean input grade (0..100, 50 = neutral): up to -/+ MAX_INPUT_SHIFT of the roll
## range, so rich inputs make better tiers likelier and poor ones worse. Low rolls are the good ones.
const MAX_INPUT_SHIFT := 0.20
static func shifted_roll(roll: float, input_grade: float) -> float:
	var shift := clampf((input_grade - 50.0) / 50.0, -1.0, 1.0) * MAX_INPUT_SHIFT
	return clampf(roll - shift, 0.0, 0.999999)


## Mean grade (0..100) of the inputs `r` would consume from `inv`, or -1 when the inventory does not track
## quality (then no shift). Inventories may offer quality_of(item) -> tier 0..2 or -1.
func input_grade(r: Dictionary, inv: Object) -> float:
	if inv == null or not inv.has_method("quality_of"):
		return -1.0
	var sum := 0.0
	var n := 0
	for inp: Dictionary in r.get("inputs", []):
		for alt in alternatives(String(inp["item"])):
			if int(inv.call("count", alt)) > 0:
				var t := int(inv.call("quality_of", alt))
				if t >= 0:
					sum += [20.0, 55.0, 90.0][clampi(t, 0, 2)] * float(inp["count"])
					n += int(inp["count"])
				break
	return sum / float(n) if n > 0 else -1.0


# --- requirements & crafting ---------------------------------------------------------

## One row per ingredient: {spec, name, need, have}.
func requirements(r: Dictionary, inv: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inp: Dictionary in r.get("inputs", []):
		var spec := String(inp["item"])
		var have := 0
		var names := PackedStringArray()
		for alt in alternatives(spec):
			have += int(inv.call("count", alt)) if inv != null else 0
			names.append(item_name(alt))
		out.append({"spec": spec, "name": " / ".join(names), "need": int(inp["count"]), "have": have})
	return out


## Why `id` can't be crafted now ("" when it can). `kinds` are the station kinds
## in reach; pass null to skip the station check. ctx.equipment is used by repair.
func can_craft(id: String, inv: Object, kinds: Variant = null, ctx: Dictionary = {}) -> String:
	var r := recipe(id)
	if r.is_empty():
		return "No such recipe."
	if kinds is Array and not _at_station(r, kinds):
		var names := PackedStringArray()
		for k in r.get("stations", []):
			names.append(station_name(String(k)).to_lower())
		return "Needs a %s." % " or ".join(names)
	if level(String(r["skill"])) < int(r.get("level", 1)):
		return "Needs %s %d." % [skill_name(String(r["skill"])), int(r.get("level", 1))]
	for row in requirements(r, inv):
		if int(row["have"]) < int(row["need"]):
			return "Needs %d %s (have %d)." % [row["need"], row["name"], row["have"]]
	if bool(r.get("repair", false)):
		var eq: Variant = ctx.get("equipment")
		if eq == null or not (eq as Object).call("needs_repair"):
			return "Nothing you wear needs mending."
	return ""


## Crafts once: consumes inputs, rolls quality, gives the output, grants xp.
## ctx: {equipment, xp_mult (float), org (RACareers org id), roll (0..1, fixed quality roll)}.
## Returns {ok, text, item, count, quality, xp, level, level_up}.
func craft(id: String, inv: Object, kinds: Variant = null, ctx: Dictionary = {}) -> Dictionary:
	var why := can_craft(id, inv, kinds, ctx)
	if why != "":
		return {"ok": false, "text": why}
	var r := recipe(id)
	var skill := String(r["skill"])
	var lvl := level(skill)
	var rlvl := int(r.get("level", 1))
	var grade: float = float(ctx["input_quality"]) if ctx.has("input_quality") else input_grade(r, inv)
	var tension := bool(ctx.get("tension", false))
	var mult := float(ctx.get("xp_mult", 1.0)) * career_xp_mult(skill, String(ctx.get("org", "")))
	var tmult := tool_bonus(skill, inv, ctx.get("equipment"))
	mult *= tmult
	var consumed: Array[Dictionary] = []    # [{item, n}] actually taken, to refund on failure
	for inp: Dictionary in r.get("inputs", []):
		var left := int(inp["count"])
		for alt in alternatives(String(inp["item"])):
			var n := mini(left, int(inv.call("count", alt)))
			if n > 0:
				inv.call("take", alt, n)
				consumed.append({"item": alt, "n": n})
				left -= n
			if left <= 0:
				break
	if tension and not bool(r.get("repair", false)):
		var sroll: float = float(ctx["success_roll"]) if ctx.has("success_roll") else rng.randf()
		if sroll >= success_chance(lvl, rlvl, tmult):
			# Failure: half of each input (rounded down) comes back, half the xp, tools untouched.
			var back: Array[String] = []
			for c: Dictionary in consumed:
				var n := int(c["n"]) / 2
				if n > 0:
					inv.call("give", String(c["item"]), n)
					back.append("%d %s" % [n, item_name(String(c["item"]))])
			var gained_f := int(round(float(r.get("xp", 5)) * mult * 0.5))
			var after_f := add_xp(skill, gained_f)
			var fres := {"ok": true, "failed": true, "quality": 0, "item": "", "count": 0, "xp": gained_f,
				"level": after_f, "level_up": after_f > lvl, "skill": skill,
				"tag": String(skills.get(skill, {}).get("tag", "crafted")),
				"hours": float(r.get("time", 1.5)) * 0.25,
				"text": "The %s goes wrong.%s" % [recipe_name(r).to_lower(), (" You salvage " + ", ".join(back) + ".") if not back.is_empty() else ""]}
			craft_failed.emit(fres)
			return fres
	var roll: float = float(ctx["roll"]) if ctx.has("roll") else rng.randf()
	if grade >= 0.0:
		roll = shifted_roll(roll, grade)
	var q := quality_for_roll(lvl, rlvl, roll)
	var crit := false
	if tension and not bool(r.get("repair", false)):
		var croll: float = float(ctx["crit_roll"]) if ctx.has("crit_roll") else rng.randf()
		crit = croll < crit_chance(lvl, rlvl)
		if crit and q < Quality.MASTERWORK:
			q += 1
	var res := {"ok": true, "quality": q, "item": "", "count": 0, "crit": crit}
	if bool(r.get("repair", false)):
		var eq: Object = ctx["equipment"]
		var fixed := int(eq.call("repair_all", [0.6, 1.0, 1.0][q]))
		res["text"] = "You mend %d piece%s of gear%s." % [fixed, "" if fixed == 1 else "s",
			"" if q > 0 else " (roughly)"]
	else:
		var out: Dictionary = r["output"]
		var item := String(out["item"])
		var n := int(out["count"])
		var gear := item_info(item).has("slot")
		if not gear and (q == Quality.MASTERWORK or crit):
			n += 1                         # a masterwork batch (or a critical success) yields one extra
		give_item(inv, item, n, q if gear else -1)
		res["item"] = item
		res["count"] = n
		var qtext := (quality_name(q) + " ") if gear else ("Masterwork batch: " if q == Quality.MASTERWORK else "")
		res["text"] = "%s%s%s." % [qtext, item_name(item), (" ×%d" % n) if n > 1 else ""]
	var gained := int(round(float(r.get("xp", 5)) * mult))
	var before := lvl
	var after := add_xp(skill, gained)
	res["xp"] = gained
	res["level"] = after
	res["level_up"] = after > before
	res["skill"] = skill
	res["tag"] = String(skills.get(skill, {}).get("tag", "crafted"))
	res["hours"] = float(r.get("time", 1.5)) * 0.25     # in-game hours the work takes
	if after > before:
		res["text"] = String(res["text"]) + "  %s is now %d!" % [skill_name(skill), after]
	crafted.emit(res)
	return res


## Skill -> tool property values that speed it up (items with "tool": value; tool_tier raises the bonus).
const TOOL_KINDS := {"smithing": ["smithing"], "mining": ["mining"], "carpentry": ["carpentry", "woodcutting"], "alchemy": ["alchemy"],
	"masonry": ["masonry"], "leatherwork": ["skinning"], "fletching": ["carpentry"], "cooking": [], "tailoring": []}
static var _tools_for: Dictionary = {}


## Item ids that count as the tool for a crafting skill (the old TOOLS id plus every item with a matching "tool" property).
static func tool_ids(skill: String) -> Array:
	if _tools_for.has(skill):
		return _tools_for[skill]
	var out: Array = []
	if TOOLS.has(skill):
		out.append(String(TOOLS[skill]))
	var kinds: Array = TOOL_KINDS.get(skill, [])
	for id: String in item_db():
		var t := String(item_db()[id].get("tool", ""))
		if t != "" and kinds.has(t) and not out.has(id):
			out.append(id)
	_tools_for[skill] = out
	return out


## XP multiplier from carrying or wielding a tool for `skill` (1.0 without): TOOL_XP_MULT, +0.05 per tool tier above iron.
func tool_bonus(skill: String, inv: Object, eq: Variant = null) -> float:
	var best := 0.0
	for id: String in tool_ids(skill):
		if (inv != null and int(inv.call("count", id)) > 0) or _wields(eq, id):
			var tier := int(item_info(id).get("tool_tier", 2))
			best = maxf(best, TOOL_XP_MULT + 0.05 * float(maxi(0, tier - 2)))
	return maxf(1.0, best)


static func _wields(eq: Variant, tool: String) -> bool:
	return eq is Object and (eq as Object).has_method("item_in") and String((eq as Object).call("item_in", "main_hand")) == tool


## Why `id` can't be salvaged now ("" when it can): needs the item, the station and the skill level.
func can_salvage(id: String, inv: Object, kinds: Variant = null) -> String:
	var sv: Dictionary = ItemsDB.salvage_for(id)
	if sv.is_empty():
		return "That can't be broken down."
	if int(inv.call("count", id)) <= 0:
		return "You have no %s." % item_name(id)
	if kinds is Array:
		var ok := false
		for k in sv.get("stations", []):
			if kinds.has(k):
				ok = true
		if not ok:
			var names := PackedStringArray()
			for k in sv.get("stations", []):
				names.append(station_name(String(k)).to_lower())
			return "Needs a %s." % " or ".join(names)
	if level(String(sv.get("skill", "smithing"))) < int(sv.get("level", 1)):
		return "Needs %s %d." % [skill_name(String(sv["skill"])), int(sv["level"])]
	return ""


## Breaks one `id` down into materials (about 45% of what it cost) and grants a little xp.
## Returns {ok, text, yield: [{item, count}], xp}.
func salvage(id: String, inv: Object, kinds: Variant = null) -> Dictionary:
	var why := can_salvage(id, inv, kinds)
	if why != "":
		return {"ok": false, "text": why}
	var sv: Dictionary = ItemsDB.salvage_for(id)
	if not bool(inv.call("take", id, 1)):
		return {"ok": false, "text": "You have no %s." % item_name(id)}
	var parts := PackedStringArray()
	for y: Dictionary in sv["yield"]:
		give_item(inv, String(y["item"]), int(y["count"]))
		parts.append("%d %s" % [int(y["count"]), item_name(String(y["item"]))])
	var skill := String(sv.get("skill", "smithing"))
	var gained := int(sv.get("xp", 2))
	add_xp(skill, gained)
	return {"ok": true, "text": "Salvaged %s: %s." % [item_name(id), ", ".join(parts)], "yield": sv["yield"], "xp": gained, "skill": skill}


## Gives `n` of `item`; with a quality (>= 0) and a GLoot inventory, as separate
## instances carrying the "quality" property. Fake inventories may implement
## give_quality(id, n, q) instead.
static func give_item(inv: Object, item: String, n: int, quality := -1) -> void:
	if quality < 0:
		inv.call("give", item, n)
		return
	if inv.has_method("give_quality"):
		inv.call("give_quality", item, n, quality)
		return
	var g: Variant = inv.get("inventory")
	if g is Object and (g as Object).has_method("create_item"):
		for i in n:
			var it: Object = (g as Object).call("create_item", item)
			if it == null:
				continue
			if quality != Quality.FINE:
				it.call("set_property", "quality", quality)
			(g as Object).call("add_item_automerge", it)
		if inv.has_signal("inventory_changed"):
			inv.emit_signal("inventory_changed")
		return
	inv.call("give", item, n)


# --- stations ------------------------------------------------------------------------

func _on_station_invalidated(ref: String, generation: int) -> void:
	for i in range(_stations.size() - 1, -1, -1):
		if String(_stations[i].get("ref", "")) == ref \
				and int(_stations[i].get("generation", -1)) == generation:
			_stations.remove_at(i)
	station_invalidated.emit(ref, generation)


func add_station(kind: String, pos: Vector3, label := "", radius := -1.0, owner: Object = null,
		owner_ref := "", slot := -1) -> Dictionary:
	var actual_slot := slot
	var actual_owner_ref := owner_ref
	if owner == null and actual_owner_ref.is_empty():
		_adhoc_station_slot += 1
		actual_owner_ref = "adhoc:%d" % _adhoc_station_slot
	if actual_slot < 0:
		if owner != null:
			_adhoc_station_slot += 1
			actual_slot = _adhoc_station_slot
		elif actual_owner_ref.begins_with("adhoc:"):
			actual_slot = 0
	var identity: Dictionary = station_identity.register_station(owner, actual_owner_ref, kind, actual_slot)
	if not bool(identity.get("ok", false)):
		return {}
	var st := {"kind": kind, "name": label if label != "" else station_name(kind), "pos": pos,
		"radius": radius if radius > 0.0 else STATION_RADIUS, "owner": owner.get_instance_id() if owner else 0,
		"ref": String(identity["ref"]), "generation": int(identity["generation"])}
	for i in _stations.size():
		if String(_stations[i].get("ref", "")) == st["ref"]:
			_stations[i] = st
			return st.duplicate(true)
	_stations.append(st)
	return st.duplicate(true)


## Drops every registered station whose ref starts with `prefix` and returns how many went (the build kit re-registers the
## benches that still stand with refs "kit:<grid>:<piece>:...", see build_kit.sync_realm).
func remove_stations_by_prefix(prefix: String) -> int:
	var n := 0
	for i in range(_stations.size() - 1, -1, -1):
		if String(_stations[i].get("ref", "")).begins_with(prefix):
			_stations.remove_at(i)
			n += 1
	return n


func clear_stations() -> void:
	station_identity.invalidate_all()
	_stations.clear()
	_sites_added = false


## Campfires at region sites (WorldGen.sites entries). Returns how many were added.
func add_world_sites(sites: Array) -> int:
	_sites_added = true
	var n := 0
	for site: Dictionary in sites:
		var c: Vector2 = site.get("pos", Vector2.ZERO)
		var basis := Basis(Vector3.UP, float(site.get("yaw", 0.0)))
		var found := false
		var parts: Array = site.get("parts", [])
		for part_index in parts.size():
			var part: Array = parts[part_index]
			if String(part[0]).find("campfire") < 0:
				continue
			var off: Vector2 = part[1]
			var w := Vector3(c.x, 0.0, c.y) + basis * Vector3(off.x, 0.0, off.y)
			add_station("campfire", Vector3(w.x, NAN, w.z), "%s Campfire" % site.get("name", ""),
				CAMPFIRE_RADIUS, null, "site:%s" % str(site.get("id", "unknown")), part_index)
			found = true
			n += 1
		if not found and String(site.get("kind", "")) == "bandit_camp":
			add_station("campfire", Vector3(c.x, NAN, c.y), "Bandit Campfire", CAMPFIRE_RADIUS,
				null, "site:%s" % str(site.get("id", "unknown")), -1)
			n += 1
	return n


## Registers the craft stations of a loaded interior room (see INTERIOR_STATIONS)
## and returns them. They drop out on room exit; without a stable building_ref,
## identity is explicitly scoped to this room instance.
func scan_interior(room: Node, building_ref := "") -> Array[Dictionary]:
	_prune()
	var out: Array[Dictionary] = []
	if room == null:
		return out
	var defs: Array = INTERIOR_STATIONS.get(String(room.name), [])
	for slot in defs.size():
		var d: Array = defs[slot]
		var at: Node3D = room as Node3D
		if String(d[1]) != "":
			at = room.get_node_or_null(NodePath(String(d[1]))) as Node3D
		if at == null or not at.is_inside_tree():
			continue
		var p := at.global_position
		var floor_y := (room as Node3D).global_position.y if room is Node3D else p.y
		var registered := add_station(String(d[0]), Vector3(p.x, floor_y, p.z),
			String(d[2]), float(d[3]), room, building_ref, slot)
		if not registered.is_empty():
			out.append(registered)
	return out


func _prune() -> void:
	var snapshot: Array = _stations.duplicate(true)
	for station: Dictionary in snapshot:
		var ref := String(station.get("ref", ""))
		var generation := int(station.get("generation", -1))
		if station_identity.is_live(ref, generation):
			continue
		for i in range(_stations.size() - 1, -1, -1):
			if String(_stations[i].get("ref", "")) == ref \
					and int(_stations[i].get("generation", -1)) == generation:
				_stations.remove_at(i)


## Stations within reach of `pos`, nearest first: [{kind, name, pos, radius, distance}].
func stations_near(pos: Vector3) -> Array[Dictionary]:
	if not _sites_added and not WorldGen.sites.is_empty():
		add_world_sites(WorldGen.sites)
	_prune()
	var out: Array[Dictionary] = []
	for st in _stations:
		var sp: Vector3 = st["pos"]
		var d := Vector2(sp.x, sp.z).distance_to(Vector2(pos.x, pos.z))
		if d > float(st["radius"]):
			continue
		if not is_nan(sp.y) and absf(sp.y - pos.y) > STATION_HEIGHT:
			continue
		var e := st.duplicate(true)
		e["distance"] = d
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := float(a["distance"])
		var b_distance := float(b["distance"])
		if a_distance == b_distance:
			return String(a["ref"]) < String(b["ref"])
		return a_distance < b_distance)
	return out


## Distinct station kinds within reach of `pos`.
func kinds_near(pos: Vector3) -> Array:
	var out := []
	for st in stations_near(pos):
		if not out.has(st["kind"]):
			out.append(st["kind"])
	return out


## Every registered station (for maps / debugging).
func all_stations() -> Array[Dictionary]:
	_prune()
	var out: Array[Dictionary] = []
	for station: Dictionary in _stations:
		out.append(station.duplicate(true))
	return out


## Nearest live station that satisfies a recipe, including its exact generation.
func nearest_station_for_recipe(pos: Vector3, recipe_id: String, requested_kinds: Array = []) -> Dictionary:
	var r := recipe(recipe_id)
	if r.is_empty():
		return {}
	var required: Array = r.get("stations", [])
	if required.is_empty():
		return {}
	for station: Dictionary in stations_near(pos):
		if required.has(String(station.get("kind", ""))) \
				and (requested_kinds.is_empty() or requested_kinds.has(String(station.get("kind", "")))):
			return station.duplicate(true)
	return {}


## Same descriptor and same generation must still be live and in reach.
func station_at(ref: String, generation: int, pos: Vector3) -> Dictionary:
	if not station_identity.is_live(ref, generation):
		return {}
	for station: Dictionary in stations_near(pos):
		if String(station.get("ref", "")) == ref and int(station.get("generation", -1)) == generation:
			return station.duplicate(true)
	return {}


static func station_resource_key(ref: String, generation: int) -> String:
	return "station:%s:g%d" % [ref, generation]


# --- save ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"xp": xp.duplicate()}


func deserialize(data: Dictionary) -> void:
	xp.clear()
	var d: Dictionary = data.get("xp", {})
	for k: String in d:
		xp[k] = int(d[k])
