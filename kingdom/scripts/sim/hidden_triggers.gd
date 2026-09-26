class_name RAHiddenTriggers
extends RefCounted
## Hidden, age-gated spot triggers ("go to the fallen shrine in the forest at
## exactly age 8 and something happens"). Each trigger is a circle on the map
## (x/z ground plane as Vector2), an inclusive age range in whole years, an
## optional time-of-day window, required and forbidden flags. Every trigger is
## one-shot. When it fires it grants a quest id, flags, a title id and an
## ability and/or class id. Nothing announces them: most players never find them.
##
## Trigger: {id, desc, pos: Vector2, radius: float, age_min: int, age_max: int,
##           hour_min: float, hour_max: float   (-1 = any time; wraps past midnight
##                                               when hour_min > hour_max),
##           flags: [required...], not_flags: [forbidden...],
##           grants: {quest: String, flags: [..], title: String, ability: String, class: String}}
##
## Pure data. Hooking it in (later, e.g. from the Life autoload a few times per
## second or on each hour, with the player's position):
##   var triggers := RAHiddenTriggers.new()
##   triggers.seed_first_region(WorldGen.settlements[0]["pos"], WorldGen.settlements[0]["radius"])
##   var p := Vector2(player.global_position.x, player.global_position.z)
##   for t in triggers.check(p, life_path.age_years(WorldSim.day, WorldSim.time_of_day),
##           WorldSim.time_of_day, life_path.flags):
##       var g: Dictionary = t["grants"]
##       for f: String in g["flags"]: life_path.set_flag(f)
##       if g["title"] != "": titles.grant(g["title"], WorldSim.day)
##       if g["quest"] != "": start the quest (QuestWeaver) and play its cutscene
##       if g["class"] != "" / g["ability"] != "": unlock it on the player
##   # Save/load: triggers.serialize() / triggers.deserialize(d)

signal triggered(trigger: Dictionary)

var triggers: Array[Dictionary] = []
## Fired trigger ids -> true. One-shot.
var fired: Dictionary = {}


## Adds a trigger; missing fields get permissive defaults. Returns it.
func add(t: Dictionary) -> Dictionary:
	var g: Dictionary = t.get("grants", {})
	var gf: Array = g.get("flags", [])
	var fl: Array = t.get("flags", [])
	var nf: Array = t.get("not_flags", [])
	var entry := {
		"id": String(t["id"]), "desc": String(t.get("desc", "")),
		"pos": t.get("pos", Vector2.ZERO), "radius": float(t.get("radius", 5.0)),
		"age_min": int(t.get("age_min", 0)), "age_max": int(t.get("age_max", 999)),
		"hour_min": float(t.get("hour_min", -1.0)), "hour_max": float(t.get("hour_max", -1.0)),
		"flags": fl.duplicate(), "not_flags": nf.duplicate(),
		"grants": {"quest": String(g.get("quest", "")), "flags": gf.duplicate(),
			"title": String(g.get("title", "")), "ability": String(g.get("ability", "")),
			"class": String(g.get("class", ""))},
	}
	triggers.append(entry)
	return entry


func get_trigger(id: String) -> Dictionary:
	for t in triggers:
		if t["id"] == id:
			return t
	return {}


func has_fired(id: String) -> bool:
	return fired.has(id)


## Fires (and returns) every unfired trigger whose conditions hold now.
func check(pos: Vector2, age: int, hour: float, flags: Dictionary) -> Array:
	var out := []
	for t in triggers:
		if fired.has(t["id"]):
			continue
		if not matches(t, pos, age, hour, flags):
			continue
		fired[t["id"]] = true
		out.append(t)
		triggered.emit(t)
	return out


## True if trigger `t` would fire for these inputs (ignores whether it already fired).
func matches(t: Dictionary, pos: Vector2, age: int, hour: float, flags: Dictionary) -> bool:
	var at: Vector2 = t["pos"]
	if pos.distance_to(at) > float(t["radius"]):
		return false
	if age < int(t["age_min"]) or age > int(t["age_max"]):
		return false
	if not in_window(hour, float(t["hour_min"]), float(t["hour_max"])):
		return false
	var need: Array = t["flags"]
	for f: String in need:
		if not (flags.has(f) and flags[f] != null and flags[f] != false):
			return false
	var bad: Array = t["not_flags"]
	for f: String in bad:
		if flags.has(f) and flags[f] != null and flags[f] != false:
			return false
	return true


## Hour window [lo, hi); wraps past midnight when lo > hi. Negative = always.
static func in_window(hour: float, lo: float, hi: float) -> bool:
	if lo < 0.0 or hi < 0.0:
		return true
	if lo <= hi:
		return hour >= lo and hour < hi
	return hour >= lo or hour < hi


## Seeds the first region's secrets around the home village. All spots lie
## outside the village radius, in places a curious child might wander.
func seed_first_region(center := Vector2.ZERO, village_radius := 60.0) -> void:
	var r := village_radius
	add({"id": "fallen_shrine", "desc": "A moss-eaten shrine, toppled in the north-east wood.",
		"pos": center + Vector2(r + 95.0, -(r + 60.0)), "radius": 6.0,
		"age_min": 8, "age_max": 8,
		"grants": {"quest": "q_fallen_shrine", "flags": ["spirit_seen"],
			"title": "spirit_touched", "class": "Spirit-touched", "ability": "spirit_sight"}})
	add({"id": "moonlit_pond", "desc": "A still pond west of the fields that mirrors the stars.",
		"pos": center + Vector2(-(r + 70.0), r + 55.0), "radius": 5.0,
		"age_min": 6, "age_max": 10, "hour_min": 22.0, "hour_max": 3.0,
		"grants": {"quest": "q_pond_whisper", "flags": ["pond_whisper"],
			"title": "moon_child", "ability": "tide_sense"}})
	add({"id": "old_hunters_blind", "desc": "Your father's old hunting blind, high in an oak east of the village.",
		"pos": center + Vector2(r + 120.0, r * 0.5), "radius": 4.0,
		"age_min": 10, "age_max": 13, "flags": ["hunted_with_father"],
		"grants": {"quest": "q_old_blind", "flags": ["found_blind"],
			"title": "keen_eye", "ability": "keen_eye", "class": "Tracker"}})
	add({"id": "burnt_watchtower", "desc": "A burnt-out watchtower on the south-west ridge.",
		"pos": center + Vector2(-(r + 90.0), -(r + 65.0)), "radius": 5.0,
		"age_min": 12, "age_max": 15, "not_flags": ["caught_stealing"],
		"grants": {"quest": "q_ash_tower", "flags": ["tower_climbed"],
			"title": "ash_walker", "ability": "ember_step"}})


func serialize() -> Dictionary:
	return {"fired": fired.keys()}


func deserialize(d: Dictionary) -> void:
	fired.clear()
	var f: Array = d.get("fired", [])
	for id: Variant in f:
		fired[String(id)] = true
