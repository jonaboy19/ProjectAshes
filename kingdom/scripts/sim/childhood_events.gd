extends RefCounted
## The childhood/adolescence event pool (ages 4-15): short story cards that
## fire while living, drawn weighted so two playthroughs differ, seeded from
## the save's world seed plus the character so a save always rolls the same
## sequence. Ages 4-7 and 8-11 are the "childhood" and "formative" pools from
## the design doc; 12-15 doubles as apprenticeship/social-consequence offers
## gated on Blessing flags (RAAwakening).
##
## Data: data/childhood/events.json — {"events": [{id, age_min, age_max,
## place: [...], season: [...]|["any"], weight, flags: [required...],
## not_flags: [...], text, choices: [{text, tendency: {k: delta},
## flags: [...], bond: {role: delta}, item: ""}]}]}. `place` values match
## RALife's place kinds: "home", "settlement", "forest_edge", "road",
## "outskirts", or "any".
##
## Pure data/rules (deterministic, own seeded rng, serialisable).
##
## Usage (Life):
##   childhood_events.seed_from(WorldSim.SEED, life_path.full_name())
##   var ev := childhood_events.roll(age(), place_kind, WorldSim.season, life_path.flags, now_days)
##   if not ev.is_empty(): show it (LifeEventPopup), then mark_seen(ev["id"], now_days)
##   Save/load: serialize() / deserialize(d)

const PATH := "res://data/childhood/events.json"
## In-game days between two events while a child (design: about one per 1-2 days).
const MIN_GAP_DAYS := 1.0
const MAX_GAP_DAYS := 2.2

var pool: Array = []
## Fired event ids -> true. Every event is one-shot.
var seen: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _next_due := 0.0
var _loaded := false


func load_pool(path := PATH) -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Array:
		pool = data
	elif data is Dictionary and data.get("events", []) is Array:
		pool = data["events"]


## Seeds the rng so two characters roll a different sequence, but the same
## save (same world seed, same character) always rolls the same one.
func seed_from(world_seed: int, character: String) -> void:
	_rng.seed = hash([world_seed, character, "childhood_events"])
	_next_due = 0.0


func has_fired(id: String) -> bool:
	return seen.has(id)


func eligible(ev: Dictionary, age: int, place: String, season: String, flags: Dictionary) -> bool:
	if seen.has(String(ev.get("id", ""))):
		return false
	if age < int(ev.get("age_min", 0)) or age > int(ev.get("age_max", 99)):
		return false
	var places: Array = ev.get("place", ["any"])
	if not places.has("any") and not places.has(place):
		return false
	var seasons: Array = ev.get("season", ["any"])
	if not seasons.has("any") and not seasons.has(season):
		return false
	for f: String in ev.get("flags", []):
		if not (flags.has(f) and flags[f] != null and flags[f] != false):
			return false
	for f: String in ev.get("not_flags", []):
		if flags.has(f) and flags[f] != null and flags[f] != false:
			return false
	return true


## True once enough in-game days have passed since the last event for another
## to be due (`now_days`: WorldSim.day + hour / 24.0).
func due(now_days: float) -> bool:
	return now_days >= _next_due


## Every currently eligible event (ignores the gap timer; used by tests and
## to check whether anything is waiting).
func eligible_now(age: int, place: String, season: String, flags: Dictionary) -> Array:
	load_pool()
	var out := []
	for ev: Dictionary in pool:
		if eligible(ev, age, place, season, flags):
			out.append(ev)
	return out


## Rolls the next due event for these conditions (weighted, deterministic
## given the rng state), or {} when none is eligible or none is due yet. Does
## not mark it seen: call mark_seen once it has actually been shown.
func roll(age: int, place: String, season: String, flags: Dictionary, now_days: float) -> Dictionary:
	if not due(now_days):
		return {}
	var cands := eligible_now(age, place, season, flags)
	if cands.is_empty():
		return {}
	var weights: Array[float] = []
	var total := 0.0
	for ev: Dictionary in cands:
		var w := maxf(0.1, float(ev.get("weight", 1.0)))
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	var acc := 0.0
	for i in cands.size():
		acc += weights[i]
		if r <= acc:
			return cands[i]
	return cands[cands.size() - 1]


## Marks an event as shown and rolls the next gap (call right after presenting it).
func mark_seen(id: String, now_days: float) -> void:
	seen[id] = true
	_next_due = now_days + _rng.randf_range(MIN_GAP_DAYS, MAX_GAP_DAYS)


func serialize() -> Dictionary:
	return {"seen": seen.keys(), "next_due": _next_due, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	seen.clear()
	for id: Variant in d.get("seen", []):
		seen[String(id)] = true
	_next_due = float(d.get("next_due", 0.0))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
