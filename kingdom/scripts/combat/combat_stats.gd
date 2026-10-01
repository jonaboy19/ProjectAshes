extends RefCounted
## Combat stat table (data/combat/archetypes.json) plus the level curve. The table holds HP, damage multiplier,
## cooldown multiplier, poise and rank per archetype at MATCHING level (enemy level == player level); stats()
## scales HP/poise/damage by (enemy level - player level). SPECIES rows in monster.gd/wolf.gd stay for visuals,
## clips, speeds and reach only.

const PATH := "res://data/combat/archetypes.json"
static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			_data = {"curve": {}, "archetypes": {}}
	return _data


static func archetypes() -> Dictionary:
	return _load()["archetypes"]


static func has(arch: String) -> bool:
	return archetypes().has(arch)


## Player character level (progression.gd via the cultivation module); 1 when no game is running.
static func player_level() -> int:
	# Looked up by name so this script (and the headless arena) compiles without autoloads.
	var loop := Engine.get_main_loop()
	var life: Node = (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null
	if life == null:
		return 1
	var realm: Variant = life.get("realm")
	if realm == null:
		return 1
	var cult: Variant = realm.mod("cultivation")
	if cult == null or cult.get("prog") == null:
		return 1
	return maxi(1, int(cult.prog.level))


## {hp, dmg, cdm, poise, rank} for `arch` with an enemy of `enemy_level` meeting a player of `player_level`.
static func stats(arch: String, enemy_level: int, player_level := -1) -> Dictionary:
	var d: Dictionary = archetypes().get(arch, {})
	var c: Dictionary = _load().get("curve", {})
	var pl := player_level if player_level > 0 else player_level()
	var diff := float(enemy_level - pl)
	var hp_m := clampf(1.0 + float(c.get("hp_per_level", 0.06)) * diff, float(c.get("hp_min", 0.4)), float(c.get("hp_max", 3.0)))
	var dmg_m := clampf(1.0 + float(c.get("dmg_per_level", 0.04)) * diff, float(c.get("dmg_min", 0.5)), float(c.get("dmg_max", 2.5)))
	return {"hp": maxi(1, int(round(float(d.get("hp", 40)) * hp_m))),
		"dmg": float(d.get("dmg", 1.0)) * dmg_m, "cdm": float(d.get("cdm", 1.0)),
		"poise": float(d.get("poise", 30.0)) * hp_m, "rank": int(d.get("rank", 3))}
