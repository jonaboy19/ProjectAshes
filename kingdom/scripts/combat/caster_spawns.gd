extends RefCounted
## Which NPC casters (scripts/combat/npc_caster.gd) join a squad: bandit mages among raiders, a knight captain over a
## garrison, sect disciples on a sect hall's patrol. Pure and seeded (data/powers/spawn_mix.json), so spawners and tests
## get the same answer. Squad.add_soldiers(count, near, mix(...)) hands the ids to the first soldiers of the squad.

const PATH := "res://data/powers/spawn_mix.json"
const NpcCaster := preload("res://scripts/combat/npc_caster.gd")

static var _cache: Dictionary = {}


static func contexts() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = (d as Dictionary).get("contexts", {}) if d is Dictionary else {}
	return _cache


## -> Array of NpcCaster ids, never longer than `count` (captains/leaders come first).
static func mix(context: String, count: int, seed_value := 1) -> Array:
	var out: Array = []
	var rules: Dictionary = contexts().get(context, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_value) + 1
	for id: String in rules:
		var r: Dictionary = rules[id]
		if count < int(r.get("min_count", 1)) or not NpcCaster.has(id):
			continue
		if rng.randf() > float(r.get("chance", 1.0)):
			continue
		var n := mini(int(r.get("max", 1)), maxi(1, count / maxi(1, int(r.get("per", 4)))))
		for i in n:
			out.append(id)
	if out.size() > count:
		out.resize(count)
	return out
