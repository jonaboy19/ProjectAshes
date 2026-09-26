class_name RATitles
extends RefCounted
## Titles and achievements. Each definition has data conditions over the
## action log, stats, age and flags, and a small passive effect expressed as a
## data dictionary ({"stamina_regen": 0.05} = +5% stamina regen). Hidden titles
## are not listed until earned. Some titles are grant-only (hidden triggers,
## quest rewards) and are never earned by evaluate().
##
## Condition keys (all optional, all must hold):
##   actions:   {tag: min_total}        from RALifePath.actions
##   stats:     {stat: min_value}       any numeric stats the caller supplies
##   stats_max: {stat: max_value}
##   age_min / age_max: int            whole years, inclusive
##   flags:     [flag, ...]            all must be set (truthy)
##   not_flags: [flag, ...]            none may be set
##   titles:    [title_id, ...]        already earned
##   grant_only: true                  only grant() can award it
##
## Pure data. Hooking it in (later, from the Life autoload):
##   var titles := RATitles.new()
##   titles.earned.connect(func(t: Dictionary) -> void: Game.say("Title earned: " + t["name"]))
##   # On hour_changed, or after record():
##   titles.evaluate({"actions": life_path.actions, "flags": life_path.flags,
##       "age": life_path.age_years(WorldSim.day, WorldSim.time_of_day),
##       "stats": {"merit": merit, "family_bond": life_path.family_bond()},
##       "day": WorldSim.day})
##   # Apply passives: var fx := titles.effects()   # {"stamina_regen": 0.1, ...}
##   #   e.g. stamina regen *= 1.0 + fx.get("stamina_regen", 0.0)
##   # Save/load: titles.serialize() / titles.deserialize(d)

signal earned(title: Dictionary)

## Seed titles. Keep effects small: they flavour a build, they don't make it.
const DEFAULTS := [
	{"id": "first_steps", "name": "First Steps", "desc": "You walked before you could talk.",
		"cond": {"age_min": 1}, "effect": {"move_speed": 0.01}},
	{"id": "little_helper", "name": "Little Helper", "desc": "Always underfoot, always useful.",
		"cond": {"actions": {"helped_parent": 10}, "age_max": 11}, "effect": {"family_bond_gain": 0.1}},
	{"id": "farmhand", "name": "Farmhand", "desc": "The fields know your footsteps.",
		"cond": {"actions": {"helped_farmer": 12}}, "effect": {"stamina_regen": 0.05}},
	{"id": "young_hunter", "name": "Young Hunter", "desc": "Brought home game before your twelfth year.",
		"cond": {"actions": {"hunted": 5}, "age_max": 11}, "effect": {"bow_draw": 0.05}},
	{"id": "bookworm", "name": "Bookworm", "desc": "Read everything the village had. Twice.",
		"cond": {"actions": {"studied": 15}}, "effect": {"xp_gain": 0.03}},
	{"id": "blade_novice", "name": "Blade Novice", "desc": "A thousand practice cuts.",
		"cond": {"actions": {"trained_sword": 20}}, "effect": {"sword_damage": 0.03}},
	{"id": "iron_body", "name": "Iron Body", "desc": "Trained your body until it stopped complaining.",
		"cond": {"actions": {"trained_fist": 20, "meditated": 5}}, "effect": {"max_stamina": 0.05}},
	{"id": "haggler", "name": "Haggler", "desc": "Nobody in the market cheats you any more.",
		"cond": {"actions": {"traded": 20}}, "effect": {"buy_price": -0.03}},
	{"id": "beloved_child", "name": "Beloved Child", "desc": "Your parents would do anything for you.",
		"cond": {"stats": {"family_bond": 90}, "age_max": 15}, "effect": {"health_regen": 0.03}},
	# Hidden: not listed until earned.
	{"id": "sticky_fingers", "name": "Sticky Fingers", "desc": "Things just... end up in your pockets.",
		"hidden": true, "cond": {"actions": {"stole": 3}, "not_flags": ["caught_stealing"]},
		"effect": {"pickpocket": 0.1}},
	{"id": "forest_child", "name": "Child of the Wood", "desc": "The forest raised you as much as your parents.",
		"hidden": true, "cond": {"actions": {"explored_forest": 15}, "age_max": 10},
		"effect": {"forest_stealth": 0.05}},
	{"id": "unseen", "name": "Unseen", "desc": "The watch never learned your face.",
		"hidden": true, "cond": {"actions": {"sneaked": 25, "stole": 10}, "not_flags": ["caught_stealing"]},
		"effect": {"stealth": 0.05}},
	# Grant-only (hidden triggers and quests).
	{"id": "spirit_touched", "name": "Spirit-touched", "desc": "Something at the fallen shrine chose you.",
		"hidden": true, "cond": {"grant_only": true}, "effect": {"magicule_regen": 0.05}},
	{"id": "moon_child", "name": "Moon Child", "desc": "The pond answered you under a full night sky.",
		"hidden": true, "cond": {"grant_only": true}, "effect": {"night_vision": 0.1}},
	{"id": "keen_eye", "name": "Keen Eye", "desc": "Your father's old blind taught you to watch.",
		"hidden": true, "cond": {"grant_only": true}, "effect": {"crit_chance": 0.02}},
	{"id": "ash_walker", "name": "Ash Walker", "desc": "You climbed the burnt tower alone and came back changed.",
		"hidden": true, "cond": {"grant_only": true}, "effect": {"fire_resist": 0.05}},
]

## id -> definition {id, name, desc, hidden, cond, effect}
var defs: Dictionary = {}
## Earned titles: id -> day earned (-1 if unknown).
var earned_ids: Dictionary = {}
## Registration order, so lists are stable.
var _order: Array[String] = []


func _init(with_defaults := true) -> void:
	if with_defaults:
		for d: Dictionary in DEFAULTS:
			add(d)


## Adds or replaces a title definition.
func add(def: Dictionary) -> void:
	var id := String(def["id"])
	var copy := def.duplicate(true)
	copy["hidden"] = bool(def.get("hidden", false))
	copy["cond"] = copy.get("cond", {})
	copy["effect"] = copy.get("effect", {})
	if not defs.has(id):
		_order.append(id)
	defs[id] = copy


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func has(id: String) -> bool:
	return earned_ids.has(id)


## Checks every unearned title against `ctx` = {actions, stats, age, flags, day}
## and awards those whose conditions hold. Returns the newly earned definitions.
func evaluate(ctx: Dictionary) -> Array:
	var out := []
	for id in _order:
		if earned_ids.has(id):
			continue
		var d: Dictionary = defs[id]
		if meets(d["cond"], ctx):
			out.append(_award(id, int(ctx.get("day", -1))))
	return out


## Awards a title regardless of conditions (quests, hidden triggers).
## Returns the definition, or {} if unknown or already earned.
func grant(id: String, day := -1) -> Dictionary:
	if not defs.has(id) or earned_ids.has(id):
		return {}
	return _award(id, day)


func _award(id: String, day: int) -> Dictionary:
	earned_ids[id] = day
	var d: Dictionary = defs[id]
	earned.emit(d)
	return d


## True if `cond` holds for `ctx`.
func meets(cond: Dictionary, ctx: Dictionary) -> bool:
	if bool(cond.get("grant_only", false)):
		return false
	var actions: Dictionary = ctx.get("actions", {})
	var stats: Dictionary = ctx.get("stats", {})
	var flags: Dictionary = ctx.get("flags", {})
	var age: int = int(ctx.get("age", 0))
	var need_actions: Dictionary = cond.get("actions", {})
	for tag: String in need_actions:
		if float(actions.get(tag, 0.0)) < float(need_actions[tag]):
			return false
	var need_stats: Dictionary = cond.get("stats", {})
	for s: String in need_stats:
		if float(stats.get(s, 0.0)) < float(need_stats[s]):
			return false
	var max_stats: Dictionary = cond.get("stats_max", {})
	for s: String in max_stats:
		if float(stats.get(s, 0.0)) > float(max_stats[s]):
			return false
	if cond.has("age_min") and age < int(cond["age_min"]):
		return false
	if cond.has("age_max") and age > int(cond["age_max"]):
		return false
	var need_flags: Array = cond.get("flags", [])
	for f: String in need_flags:
		if not _flag(flags, f):
			return false
	var bad_flags: Array = cond.get("not_flags", [])
	for f: String in bad_flags:
		if _flag(flags, f):
			return false
	var need_titles: Array = cond.get("titles", [])
	for t: String in need_titles:
		if not earned_ids.has(t):
			return false
	return true


static func _flag(flags: Dictionary, f: String) -> bool:
	return flags.has(f) and flags[f] != null and flags[f] != false


## Titles to show the player: all visible ones plus hidden ones already earned,
## as [{id, name, desc, earned: bool, effect}] in definition order.
func listed() -> Array:
	var out := []
	for id in _order:
		var d: Dictionary = defs[id]
		var got := earned_ids.has(id)
		if bool(d["hidden"]) and not got:
			continue
		out.append({"id": id, "name": d.get("name", id), "desc": d.get("desc", ""),
			"earned": got, "effect": d["effect"]})
	return out


## Earned titles as definitions, in definition order.
func earned_list() -> Array:
	var out := []
	for id in _order:
		if earned_ids.has(id):
			out.append(defs[id])
	return out


## Sum of the passive effects of every earned title: {key: total}.
func effects() -> Dictionary:
	var out := {}
	for id: String in earned_ids:
		if not defs.has(id):
			continue
		var fx: Dictionary = defs[id]["effect"]
		for k: String in fx:
			out[k] = float(out.get(k, 0.0)) + float(fx[k])
	return out


func serialize() -> Dictionary:
	return {"earned": earned_ids.duplicate()}


func deserialize(d: Dictionary) -> void:
	earned_ids.clear()
	var e: Dictionary = d.get("earned", {})
	for id: String in e:
		earned_ids[id] = int(e[id])
