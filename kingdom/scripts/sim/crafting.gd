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
signal skill_up(skill: String, level: int)

const Gathering := preload("res://scripts/sim/gathering_items.gd")
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


# --- data ------------------------------------------------------------------------

static func recipe_data() -> Dictionary:
	if _recipe_data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
		_recipe_data = d if d is Dictionary else {}
	return _recipe_data


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
	for inp: Dictionary in r.get("inputs", []):
		var left := int(inp["count"])
		for alt in alternatives(String(inp["item"])):
			var n := mini(left, int(inv.call("count", alt)))
			if n > 0:
				inv.call("take", alt, n)
				left -= n
			if left <= 0:
				break
	var lvl := level(skill)
	var roll: float = float(ctx["roll"]) if ctx.has("roll") else rng.randf()
	var q := quality_for_roll(lvl, int(r.get("level", 1)), roll)
	var res := {"ok": true, "quality": q, "item": "", "count": 0}
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
		if not gear and q == Quality.MASTERWORK:
			n += 1                         # a masterwork batch yields one extra
		give_item(inv, item, n, q if gear else -1)
		res["item"] = item
		res["count"] = n
		var qtext := (quality_name(q) + " ") if gear else ("Masterwork batch: " if q == Quality.MASTERWORK else "")
		res["text"] = "%s%s%s." % [qtext, item_name(item), (" ×%d" % n) if n > 1 else ""]
	var mult := float(ctx.get("xp_mult", 1.0)) * career_xp_mult(skill, String(ctx.get("org", "")))
	var tool := String(TOOLS.get(skill, ""))
	if tool != "" and (int(inv.call("count", tool)) > 0 or _wields(ctx.get("equipment"), tool)):
		mult *= TOOL_XP_MULT
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


static func _wields(eq: Variant, tool: String) -> bool:
	return eq is Object and (eq as Object).has_method("item_in") and String((eq as Object).call("item_in", "main_hand")) == tool


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

func add_station(kind: String, pos: Vector3, label := "", radius := -1.0, owner: Object = null) -> Dictionary:
	var st := {"kind": kind, "name": label if label != "" else station_name(kind), "pos": pos,
		"radius": radius if radius > 0.0 else STATION_RADIUS, "owner": owner.get_instance_id() if owner else 0}
	_stations.append(st)
	return st


func clear_stations() -> void:
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
		for part: Array in site.get("parts", []):
			if String(part[0]).find("campfire") < 0:
				continue
			var off: Vector2 = part[1]
			var w := Vector3(c.x, 0.0, c.y) + basis * Vector3(off.x, 0.0, off.y)
			add_station("campfire", Vector3(w.x, NAN, w.z), "%s Campfire" % site.get("name", ""), CAMPFIRE_RADIUS)
			found = true
			n += 1
		if not found and String(site.get("kind", "")) == "bandit_camp":
			add_station("campfire", Vector3(c.x, NAN, c.y), "Bandit Campfire", CAMPFIRE_RADIUS)
			n += 1
	return n


## Registers the craft stations of a loaded interior room (see INTERIOR_STATIONS)
## and returns them. They drop out on their own once the room is freed.
func scan_interior(room: Node) -> Array[Dictionary]:
	_prune()
	var out: Array[Dictionary] = []
	if room == null:
		return out
	var defs: Array = INTERIOR_STATIONS.get(String(room.name), [])
	for d: Array in defs:
		var at: Node3D = room as Node3D
		if String(d[1]) != "":
			at = room.get_node_or_null(NodePath(String(d[1]))) as Node3D
		if at == null or not at.is_inside_tree():
			continue
		var p := at.global_position
		var floor_y := (room as Node3D).global_position.y if room is Node3D else p.y
		out.append(add_station(String(d[0]), Vector3(p.x, floor_y, p.z), String(d[2]), float(d[3]), room))
	return out


func _prune() -> void:
	for i in range(_stations.size() - 1, -1, -1):
		var o := int(_stations[i]["owner"])
		if o != 0 and not is_instance_id_valid(o):
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
		var e := st.duplicate()
		e["distance"] = d
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
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
	return _stations.duplicate()


# --- save ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"xp": xp.duplicate()}


func deserialize(data: Dictionary) -> void:
	xp.clear()
	var d: Dictionary = data.get("xp", {})
	for k: String in d:
		xp[k] = int(d[k])
