extends RefCounted
## Echoes: imprints powerful souls leave behind — a defeated apex monster (troll,
## bear, wyvern, corrupted wolf, ...), a Soul-Named companion who died, a fallen
## mentor or family member, or a Rift phenomenon witnessed too closely. The player
## may "attune" to a limited number of echoes at once (the limit grows with soul
## tier) for passive modifiers, plus a rare active "Echo call" per attuned echo,
## each on its own cooldown in days.
##
## At tier 9+ the accumulated, attuned echoes and the player's Path unlock a
## personal Inner World: a small realm described as data only (biome, landmarks,
## residents drawn from Soul-Named bonds) for future content to build on.
##
## Data-driven: echo *types* (name, flavour, passive modifiers, active call) live
## in data/soul/echoes.json; this script only tracks which echoes the player has
## earned, which are attuned, and cooldowns. Pure data (serialisable), no scene
## tree, deterministic (nothing here rolls dice, so no RNG to seed).
##
## INTEGRATION (for Life; not wired yet):
## - Life owns `var echoes := preload("res://scripts/sim/echoes.gd").new()`.
## - When an apex monster dies (Life.on_wolf_killed's den lookup, or any place a
##   den's species is troll/bear/wyvern/corrupted_wolf):
##     echoes.add_echo(species + "_echo", "the " + species.capitalize(), WorldSim.day, 1.0)
## - When a Soul-Named companion or a family member dies:
##     echoes.add_echo("companion_echo", companion_name, WorldSim.day, 1.0)
##     echoes.add_echo("family_echo", person_name, WorldSim.day, 1.0)
## - Save: snapshot["echoes"] = echoes.serialize().

const DATA_PATH := "res://data/soul/echoes.json"

## Number of echoes that may be attuned at once, keyed by the lowest tier that
## grants the count (mirrors naming.gd's BOND_LIMITS_BY_TIER shape).
const ATTUNE_LIMITS_BY_TIER := [[1, 1], [3, 2], [5, 3], [7, 4], [9, 5], [11, 6]]
## Soul tier at which an Inner World is unlocked.
const INNER_WORLD_TIER := 9

## echo type id -> {name, kind, source_hint, desc, modifiers, active} (from JSON).
var _types: Dictionary = {}

## Earned echoes: [{id (int), type, source_name, day, strength}]
var echoes: Array[Dictionary] = []
## ids (int) of echoes.id currently attuned, in the order attuned.
var attuned: Array[int] = []
## echo id (int) -> last day its active "Echo call" was used.
var last_call_day: Dictionary = {}
var _next_id := 1


func _init(load_data := true) -> void:
	if load_data:
		load_types(DATA_PATH)


# --- data --------------------------------------------------------------------

func load_types(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("echoes: no data at " + path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	for e: Dictionary in (parsed as Dictionary).get("echoes", []):
		_types[String(e["id"])] = e.duplicate(true)


func type_info(kind: String) -> Dictionary:
	return _types.get(kind, {"id": kind, "name": kind.capitalize(), "kind": "unknown",
		"source_hint": "", "desc": "An imprint nobody has recorded.", "modifiers": {}, "active": {}})


func known_types() -> Array:
	return _types.keys()


# --- earning & attuning --------------------------------------------------------

## Records a new Echo. `kind` is an id from data/soul/echoes.json (e.g.
## "troll_echo"); unknown kinds still work with a generic fallback. `strength`
## scales nothing yet (reserved for future content) but is kept for lore/UI.
func add_echo(kind: String, source_name: String, day: int, strength := 1.0) -> Dictionary:
	var e := {"id": _next_id, "type": kind, "source_name": source_name, "day": day,
		"strength": strength}
	_next_id += 1
	echoes.append(e)
	return e


func echo(id: int) -> Dictionary:
	for e in echoes:
		if int(e["id"]) == id:
			return e
	return {}


func has_echo(id: int) -> bool:
	return not echo(id).is_empty()


## How many echoes may be attuned at once at this soul tier.
static func attune_limit(tier: int) -> int:
	var n := 0
	for pair in ATTUNE_LIMITS_BY_TIER:
		if tier >= int(pair[0]):
			n = int(pair[1])
	return n


## Attunes to an earned echo (returns {ok, text}). Refused past the tier's limit,
## for an unknown echo, or one already attuned.
func attune(id: int, tier: int) -> Dictionary:
	if not has_echo(id):
		return {"ok": false, "text": "There is no such Echo to attune to."}
	if id in attuned:
		return {"ok": false, "text": "Already attuned to that Echo."}
	var limit := attune_limit(tier)
	if attuned.size() >= limit:
		return {"ok": false, "text": "Your soul can only hold %d Echo%s attuned at once." % [
			limit, "" if limit == 1 else "s"]}
	attuned.append(id)
	return {"ok": true, "text": "%s settles into you." % type_info(String(echo(id)["type"]))["name"]}


func unattune(id: int) -> void:
	attuned.erase(id)


## Combined passive modifiers from every currently attuned Echo, summed.
func modifiers() -> Dictionary:
	var out := {}
	for id in attuned:
		var e := echo(id)
		if e.is_empty():
			continue
		var mods: Dictionary = type_info(String(e["type"])).get("modifiers", {})
		for key: String in mods:
			out[key] = out.get(key, 0.0 if typeof(mods[key]) != TYPE_INT else 0) + mods[key]
	return out


## Uses an attuned Echo's rare active "Echo call". Refused if not attuned or the
## call is still on cooldown. Returns {ok, text, effect, cooldown_days,
## available_again_day}.
func echo_call(id: int, day: int) -> Dictionary:
	var out := {"ok": false, "text": "", "effect": {}, "cooldown_days": 0, "available_again_day": day}
	if not id in attuned:
		out["text"] = "That Echo is not attuned; it cannot be called."
		return out
	var info := type_info(String(echo(id)["type"]))
	var active: Dictionary = info.get("active", {})
	if active.is_empty():
		out["text"] = "%s has no call to make." % info["name"]
		return out
	var cd := int(active.get("cooldown_days", 0))
	out["cooldown_days"] = cd
	var last := int(last_call_day.get(id, -999999))
	var ready_day := last + cd
	if day < ready_day:
		out["text"] = "%s has not gathered strength again; %d day%s left." % [active["name"],
			ready_day - day, "" if ready_day - day == 1 else "s"]
		out["available_again_day"] = ready_day
		return out
	last_call_day[id] = day
	out["ok"] = true
	out["effect"] = (active.get("effect", {}) as Dictionary).duplicate()
	out["available_again_day"] = day + cd
	out["text"] = "%s: %s" % [active["name"], active.get("desc", "")]
	return out


# --- Inner World hooks (data only, for future content) -------------------------

func inner_world_unlocked(tier: int) -> bool:
	return tier >= INNER_WORLD_TIER


## A small personal realm shaped by the attuned Echoes and the player's Path.
## Returns {unlocked, biome, landmarks: [String], residents: [{name, source}]}.
## `soul_bonds` is naming.gd's `soul_bonds` array (person-kind bonds become
## residents); `path` is a free-form string (e.g. from soul.gd's chosen Path).
func inner_world_state(tier: int, path := "", soul_bonds: Array = []) -> Dictionary:
	var out := {"unlocked": inner_world_unlocked(tier), "biome": "", "landmarks": [], "residents": []}
	if not out["unlocked"]:
		return out
	var biome := "an ember-lit hollow"
	if path != "":
		biome = "a hollow shaped by %s" % path
	out["biome"] = biome
	var landmarks: Array = []
	for id in attuned:
		var e := echo(id)
		if e.is_empty():
			continue
		var info := type_info(String(e["type"]))
		landmarks.append("A marker for %s, left by %s." % [info["name"], e["source_name"]])
	out["landmarks"] = landmarks
	var residents: Array = []
	for b: Dictionary in soul_bonds:
		if String(b.get("kind", "")) == "person":
			residents.append({"name": String(b.get("target_name", "")), "source": "soul_bond"})
	out["residents"] = residents
	return out


# --- save/load -----------------------------------------------------------------

func serialize() -> Dictionary:
	var e := []
	for x in echoes:
		e.append(x.duplicate())
	return {"echoes": e, "attuned": attuned.duplicate(), "last_call_day": last_call_day.duplicate(),
		"next_id": _next_id}


func deserialize(d: Dictionary) -> void:
	echoes.clear()
	for x: Dictionary in d.get("echoes", []):
		echoes.append({"id": int(x["id"]), "type": String(x["type"]), "source_name": String(x["source_name"]),
			"day": int(x["day"]), "strength": float(x.get("strength", 1.0))})
	attuned.clear()
	for id: Variant in d.get("attuned", []):
		attuned.append(int(id))
	last_call_day.clear()
	var lcd: Dictionary = d.get("last_call_day", {})
	for k: Variant in lcd.keys():
		last_call_day[int(k)] = int(lcd[k])
	_next_id = int(d.get("next_id", _next_id))
