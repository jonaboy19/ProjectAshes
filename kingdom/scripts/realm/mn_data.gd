extends RefCounted
## MN (docs/design/MONSTER_NAMING_AND_STATUS.md): cached loader for the data/world/*.json tables the monster-naming and
## status packages read, plus the owner-question flags. Pure; nothing here is saved.

const DIR := "res://data/world/"
static var _cache: Dictionary = {}


static func table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out: Dictionary = {}
	var f := FileAccess.open(DIR + name + ".json", FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			out = j
	_cache[name] = out
	return out


static func reset() -> void:
	_cache.clear()


## Owner open questions as data flags (conservative defaults when the file is missing).
static func flag(key: String) -> Variant:
	var defaults := {"undead_naming_forbidden": true, "undead_sealed_servants_only": true, "intermarriage": "story_only",
		"monsters_can_vote": false, "dragonkin_mode": "late_lizardfolk_form", "dragonkin_recruitable": false, "free_dragons": false}
	return table("mn_flags").get(key, defaults.get(key))


static func species_row(species: String) -> Dictionary:
	return (table("species_tracks").get("species", {}) as Dictionary).get(species, {})


## Culture id for a kingdom, a culture id, or an Array of culture tags (first known wins).
static func culture_of(where: Variant) -> String:
	var cults: Dictionary = table("culture_attitudes").get("cultures", {})
	if where is Array:
		for w: Variant in where:
			var c := culture_of(w)
			if c != "":
				return c
		return "folk"
	var s := String(where)
	if cults.has(s):
		return s
	return String((table("culture_attitudes").get("kingdom_culture", {}) as Dictionary).get(s, "folk"))
