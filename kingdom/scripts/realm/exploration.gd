extends "res://scripts/realm/realm_module.gd"
## Exploration (docs/design/REALM_PLAN.md "Freedom and exploration first"): what the player has done in
## the region's caves, mines, hideouts, warrens and crypts, and which hidden entrances they have found.
## Pure data, JSON-safe, no nodes. The dungeon runtime (scripts/interiors/dungeon_root.gd) writes straight
## into the dictionaries handed out by state(id), so looted chests, opened doors, killed creatures and
## harvested nodes persist with the realm save (Life.realm.serialize -> "exploration").
##
## Leads are rumours: "lead:<dungeon id>" knowledge facts (society.learn) that make a hidden entrance
## glow a little and show on the journal; a settlement rumour (rumour_for) or a journal found inside
## another dungeon gives one. Nothing here is required for progress.

const SAVE_VERSION := 1
const REPOPULATE_DAYS := 21          # creatures come back this long after the last kill
const RUMOUR_TEXT := {
	"waterfall": "the falls hide a dry ledge behind the water",
	"vines": "a cave behind ivy where a fox was seen going in",
	"rockfall": "a sealed gallery under a rockfall",
	"night": "violet light seeping from a rock face after dark",
}

var _states: Dictionary = {}         # dungeon id -> state dict (see dungeon_build.gd _ensure_state)
var revealed: Dictionary = {}        # hidden dungeon id -> day found
var leads: Dictionary = {}           # dungeon id -> day the lead was learned
var entered: Dictionary = {}         # dungeon id -> day first entered
var _last_kill_day: Dictionary = {}
var relics: Dictionary = {}          # dungeon id -> {text, day}: gear of a lost expedition (notables.gd)


func state(id: String) -> Dictionary:
	if not _states.has(id):
		_states[id] = {"opened": {}, "looted": {}, "harvested": {}, "read": {}, "killed": {}, "boss_dead": false,
			"cleared": false, "visits": 0}
	return _states[id]


func on_enter(id: String, day: int) -> void:
	if not entered.has(id):
		entered[id] = day
	_last_kill_day[id] = day


func reveal(id: String, day: int) -> bool:
	if revealed.has(id):
		return false
	revealed[id] = day
	return true


func is_revealed(id: String) -> bool:
	return revealed.has(id)


func knows_lead(id: String) -> bool:
	return leads.has(id) or revealed.has(id)


## Learns a rumour about a hidden place. Returns true the first time.
func learn_lead(id: String, day := 0) -> bool:
	if leads.has(id):
		return false
	leads[id] = day
	var soc: Variant = hub.mod("society") if hub != null else null
	if soc != null:
		var site := _site(id)
		var why := String(RUMOUR_TEXT.get(String(site.get("cave", {}).get("reveal", "")), "a hidden place"))
		soc.learn("lead:%s" % id, "Rumour of %s: %s." % [String(site.get("name", "a hidden place")), why])
	return true


## A lost expedition's gear turns up deep in `id` (CIV-B notables.gd): stores the relic and gives a lead.
func plant_relic(id: String, text: String, day := 0) -> void:
	if relics.has(id):
		return
	relics[id] = {"text": text, "day": day}
	if not leads.has(id):
		leads[id] = day
		var soc: Variant = hub.mod("society") if hub != null else null
		if soc != null:
			soc.learn("lead:%s" % id, "Rumour of %s: %s" % [String(_site(id).get("name", "a hidden place")), text])


## A rumour to drop into a dialogue for someone in `region_pos`: nearest hidden place not yet found.
## Returns {site_id, text} or {} . The caller decides when to call learn_lead(site_id).
func rumour_for(region_pos: Vector2, rng_seed := 0) -> Dictionary:
	var best := {}
	var best_d := 1.0e9
	for s: Dictionary in WorldGen.sites:
		if not s.has("cave") or not bool(s["cave"]["hidden"]):
			continue
		var id := String(s["cave"]["dungeon_id"])
		if revealed.has(id) or leads.has(id):
			continue
		var d := (s["pos"] as Vector2).distance_to(region_pos) + float(hash([rng_seed, id]) % 400)
		if d < best_d:
			best_d = d
			best = s
	if best.is_empty():
		return {}
	var c: Dictionary = best["cave"]
	var dir := _compass(region_pos, best["pos"])
	return {"site_id": String(c["dungeon_id"]), "text": "They say %s, somewhere %s of here." % [
		String(RUMOUR_TEXT.get(String(c["reveal"]), "a hidden place")), dir]}


func _compass(a: Vector2, b: Vector2) -> String:
	var d := b - a
	var ns := "north" if d.y < 0 else "south"
	var ew := "west" if d.x < 0 else "east"
	if absf(d.x) > absf(d.y) * 2.0:
		return ew
	if absf(d.y) > absf(d.x) * 2.0:
		return ns
	return "%s-%s" % [ns, ew]


func _site(id: String) -> Dictionary:
	for s: Dictionary in WorldGen.sites:
		if s.has("cave") and String(s["cave"]["dungeon_id"]) == id:
			return s
	return {}


func stats() -> Dictionary:
	var looted := 0
	var cleared := 0
	var bosses := 0
	for id: String in _states:
		var st: Dictionary = _states[id]
		looted += (st["looted"] as Dictionary).size()
		if bool(st.get("cleared", false)):
			cleared += 1
		if bool(st.get("boss_dead", false)):
			bosses += 1
	return {"entered": entered.size(), "cleared": cleared, "bosses": bosses, "looted": looted, "hidden_found": revealed.size(), "leads": leads.size()}


## Weekly: a dungeon nobody has cleared recently slowly refills (creatures only; loot and bosses stay gone).
func tick_day(day: int, _ctx: Dictionary) -> Array:
	for id: String in _states:
		var st: Dictionary = _states[id]
		var killed: Dictionary = st["killed"]
		if killed.is_empty():
			continue
		var seen := int(_last_kill_day.get(id, 0))
		if day - seen >= REPOPULATE_DAYS:
			var keep := {}
			if killed.has("boss"):
				keep["boss"] = true
			st["killed"] = keep
			st["cleared"] = false
			_last_kill_day[id] = day
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	return tick_day(int(ctx.get("day", 0)) + days, ctx)


func serialize() -> Dictionary:
	return {"v": SAVE_VERSION, "states": _states.duplicate(true), "revealed": revealed.duplicate(), "leads": leads.duplicate(),
		"entered": entered.duplicate(), "last_kill": _last_kill_day.duplicate(), "relics": relics.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	_states.clear()
	revealed.clear()
	leads.clear()
	entered.clear()
	_last_kill_day.clear()
	relics = (d.get("relics", {}) as Dictionary).duplicate(true)
	var s: Variant = d.get("states", {})
	if s is Dictionary:
		for id: Variant in s:
			if s[id] is Dictionary:
				var st := state(String(id))
				for k: Variant in (s[id] as Dictionary):
					st[String(k)] = s[id][k]
				for k in ["opened", "looted", "harvested", "read", "killed"]:
					if not st[k] is Dictionary:
						st[k] = {}
	for key in ["revealed", "leads", "entered", "last_kill"]:
		var src: Variant = d.get(key, {})
		var dst: Dictionary = {"revealed": revealed, "leads": leads, "entered": entered, "last_kill": _last_kill_day}[key]
		if src is Dictionary:
			for id: Variant in src:
				dst[String(id)] = int(src[id])
