extends RefCounted
## The named residents of Thornfield (data/region1/world/thornfield_people.json, docs/design/FOUNDATION_PLAN.md F8).
##
## Thornfield is a WorldSim settlement, so its people are rows of the data tier. `bind()` picks one row for each
## roster entry (deterministically, spread over the settlement), gives it the entry's job, and from then on:
##   WorldSim.person_name(row)   is the roster name            (name_of)
##   WorldSim._spot(...)         walks the row to its own home and workplace door   (spot)
##   WorldSim._current_phase()   applies the entry's schedule overrides             (override_phase)
##   PopulationLOD               prefers named people when it picks who gets a body  (embody_weight)
##   VillageServices._npc_info   talks as the roster person (dialogue/thornfield/<id>.json) (info_for)
##   WorldSim.kill_person        fires `died {actor}` on the quest bus              (on_died)
## Preload this script (no class_name); every function is static.

const PATH := "res://data/region1/world/thornfield_people.json"
const TOWN := "Thornfield"
const Schedule := preload("res://scripts/population/schedule.gd")
const SliceTown := preload("res://scripts/world/thornfield/slice_town.gd")

static var _doc: Dictionary = {}
static var _by_id: Dictionary = {}          # roster id -> entry
static var _row_of: Dictionary = {}         # roster id -> WorldSim row
static var _id_of: Dictionary = {}          # WorldSim row -> roster id
static var _sched: Dictionary = {}          # row -> Array of {from, to, phase:int}
static var _bound_for := -1                 # WorldSim.population() the binding was made for


## WorldSim is an autoload that preloads this script, so it is reached through the tree, not by its global name.
static func _ws() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("WorldSim") if loop is SceneTree else null


static func data() -> Dictionary:
	if _doc.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
		_doc = d if d is Dictionary else {}
		_by_id.clear()
		for e: Dictionary in _doc.get("residents", []):
			_by_id[String(e["id"])] = e
	return _doc


static func residents() -> Array:
	return data().get("residents", [])


static func entry(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func clear() -> void:
	_row_of.clear()
	_id_of.clear()
	_sched.clear()
	_bound_for = -1


static func settlement_id() -> int:
	for s in WorldGen.settlements:
		if String(s["name"]) == TOWN:
			return int(s["id"])
	return -1


static func is_bound() -> bool:
	var ws := _ws()
	return ws != null and _bound_for == int(ws.call("population")) and not _row_of.is_empty()


## Picks a WorldSim row for every bindable resident. Safe to call again (it rebinds only after a new world).
## Returns {id: row}.
static func bind(force := false) -> Dictionary:
	data()
	var ws := _ws()
	var sid := settlement_id()
	var ranges: Array = ws.get("ranges") if ws != null else []
	if sid < 0 or ranges.size() <= sid:
		return {}
	if not force and is_bound():
		return _row_of
	clear()
	var range_i: Vector2i = ranges[sid]
	var taken := {}
	var order := residents().duplicate()
	# Children first: only a stable slice of the day labourers count as children, so they pick before everyone else.
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (0 if bool(a.get("child", false)) else 1) < (0 if bool(b.get("child", false)) else 1))
	for e: Dictionary in order:
		if not bool(e.get("bind", true)):
			continue
		var id := String(e["id"])
		var want_job := int(e.get("job", 4))
		var row := _pick(ws, range_i, id, want_job, bool(e.get("child", false)), taken)
		if row < 0:
			continue
		taken[row] = true
		_row_of[id] = row
		_id_of[row] = id
		var jobs: PackedByteArray = ws.get("job")
		if int(jobs[row]) != want_job:
			jobs[row] = want_job
			ws.set("job", jobs)
		_sched[row] = _compile(e.get("schedule", []))
	_bound_for = int(ws.call("population"))
	return _row_of


static func _pick(ws: Node, r: Vector2i, id: String, want_job: int, child: bool, taken: Dictionary) -> int:
	var cands: Array[int] = []
	var any: Array[int] = []
	var jobs: PackedByteArray = ws.get("job")
	var health: PackedByteArray = ws.get("health")
	for i in range(r.x, r.y):
		if taken.has(i) or health[i] == 0:
			continue
		var is_kid := int(jobs[i]) == 4 and absi(hash(i * 977 + 3)) % 10 == 0
		if child != is_kid:
			continue
		any.append(i)
		if int(jobs[i]) == want_job:
			cands.append(i)
	var pool := cands if not cands.is_empty() else any
	if pool.is_empty():
		return -1
	return pool[absi(hash(id)) % pool.size()]


static func _is_child_row(i: int) -> bool:
	var jobs: PackedByteArray = _ws().get("job")
	return int(jobs[i]) == 4 and absi(hash(i * 977 + 3)) % 10 == 0


static func _compile(list: Array) -> Array:
	var out: Array = []
	for s: Dictionary in list:
		var ph := Schedule.NAMES.find(String(s.get("phase", "home")))
		if ph >= 0:
			out.append({"from": float(s.get("from", 0.0)), "to": float(s.get("to", 24.0)), "phase": ph})
	return out


# --- lookups ------------------------------------------------------------------------------

static func row_of(id: String) -> int:
	return int(_row_of.get(id, -1))


static func id_of(row: int) -> String:
	return String(_id_of.get(row, ""))


static func is_named(row: int) -> bool:
	return _id_of.has(row)


static func bound_rows() -> Array:
	return _id_of.keys()


## The roster name of a bound row, "" when the row is an ordinary resident.
static func name_of(row: int) -> String:
	var id := String(_id_of.get(row, ""))
	return String(_by_id.get(id, {}).get("name", "")) if id != "" else ""


## Identity for the talk system: {id, name, role, file, quest_role} or {} for an ordinary resident.
static func info_for(row: int) -> Dictionary:
	var id := String(_id_of.get(row, ""))
	if id == "":
		return {}
	var e: Dictionary = _by_id.get(id, {})
	return {"id": id, "name": String(e.get("name", id)), "role": String(e.get("role", "villager")),
		"file": "thornfield/" + id, "quest_role": "villager", "age": int(e.get("age", 30))}


## Bound rows of settlement `sid` whose home (which 0) or workplace (which 1) is building lot `lot` of its plan. A named person
## lives and works where the roster says (their door in WorldSim._spot), so a building's interior shows them, not the people
## the hash formula would have put there (interiors/household.gd).
static func rows_at(sid: int, lot: int, which: int) -> Array[int]:
	var out: Array[int] = []
	if _row_of.is_empty() or sid != settlement_id():
		return out
	for id: String in _row_of:
		var bid := String(_by_id.get(id, {}).get("home" if which == 0 else "work", ""))
		var b := SliceTown.building(bid)
		if not b.is_empty() and int(b["lot"]) == lot:
			out.append(int(_row_of[id]))
	out.sort()
	return out


## Same as info_for for a resident that is not a WorldSim row (Hesta Thorne, a Station at the brewery), by roster id.
static func info_for_id(id: String) -> Dictionary:
	var e: Dictionary = entry(id)
	if e.is_empty():
		return {}
	return {"id": id, "name": String(e.get("name", id)), "role": String(e.get("role", "villager")),
		"file": "thornfield/" + id, "quest_role": "villager", "age": int(e.get("age", 30))}


## Others' opinion of `id` as dialogue lines is in the dialogue files; this is the data side (kind, value) of
## how `a` relates to `b` ({} when unrelated).
static func relationship(a: String, b: String) -> Dictionary:
	return (_by_id.get(a, {}).get("relationships", {}) as Dictionary).get(b, {})


## Seeds the NPC social graph (scripts/sim/npc_social_graph.gd, read by the near AI when it picks chat partners)
## with the roster's warm ties: family, friends, colleagues start out acquainted, so they seek each other out.
## Negative ties (rivals, creditors) stay in the dialogue; the graph only models familiarity. Returns edges added.
static func seed_social_graph(graph: Variant, seed_value: int) -> int:
	if graph == null or not graph.has_method("link"):
		return 0
	var added := 0
	for id: String in _row_of:
		var ra := int(_row_of[id])
		for other: String in (_by_id.get(id, {}).get("relationships", {}) as Dictionary):
			if not _row_of.has(other):
				continue
			var v := float(_by_id[id]["relationships"][other].get("value", 0))
			if v <= 0.0:
				continue
			var a := "worldsim:%d:%d" % [seed_value, ra]
			var b := "worldsim:%d:%d" % [seed_value, int(_row_of[other])]
			if not (graph.call("link", a, b) as Dictionary).is_empty():
				continue
			var left := a if a < b else b
			var right := b if a < b else a
			(graph.get("edges") as Dictionary)[left + "|" + right] = {"a": left, "b": right, "first_day": 0.0, "last_day": 0.0,
				"conversations": 1, "affinity": clampf(v * 0.5, 2.0, 40.0)}
			added += 1
	return added


# --- hooks used by WorldSim / PopulationLOD ----------------------------------------------------

## Schedule phase for a bound row at hour `h` (the baseline `base` when no override applies).
static func override_phase(row: int, h: float, base: int) -> int:
	var list: Array = _sched.get(row, [])
	for s: Dictionary in list:
		var a: float = s["from"]
		var b: float = s["to"]
		if (h >= a and h < b) if a <= b else (h >= a or h < b):
			return int(s["phase"])
	return base


## Where a bound row stands for a phase (home door, workplace door), or Vector2.INF to use the default spot.
static func spot(row: int, which: int) -> Vector2:
	var id := String(_id_of.get(row, ""))
	if id == "":
		return Vector2.INF
	var e: Dictionary = _by_id.get(id, {})
	var bid := ""
	match which:
		0: bid = String(e.get("home", ""))
		1: bid = String(e.get("work", ""))
		_: return Vector2.INF
	var p := SliceTown.door_of(bid, row)
	return p


## Distance-squared multiplier for who gets a body (named people are preferred over the crowd).
static func embody_weight(row: int) -> float:
	return 0.55 if _id_of.has(row) else 1.0


## WorldSim.kill_person hook: the quest bus hears who died (the roster id, plus the row's own id).
static func on_died(row: int) -> void:
	var id := String(_id_of.get(row, ""))
	var bus := QuestBus.shared()
	if id != "":
		bus.emit_event(&"died", {"actor": id})
	bus.emit_event(&"died", {"actor": "p%d" % row})


# --- workplace keepers (interiors) ---------------------------------------------------------------

## Roles that run a building (the others just work near it). Keyed by the building type SliceTown tags the lot with.
const KEEPER_ROLES := {"smithy": "blacksmith", "bakery": "baker", "tavern": "innkeeper", "general_shop": "shopkeeper", "healer": "herbalist"}


## The roster entry that runs building `bid` ("thornfield_smithy"): the resident whose `work` is `bid` and whose role is the
## keeper role of that building type. {} for a building with no named keeper.
static func keeper_of(bid: String) -> Dictionary:
	if bid == "":
		return {}
	for e: Dictionary in residents():
		if String(e.get("work", "")) != bid or bool(e.get("child", false)):
			continue
		for t: String in KEEPER_ROLES:
			if String(KEEPER_ROLES[t]) == String(e.get("role", "")) and SliceTown.building(bid).get("type", "") == t:
				return e
	return {}


## The interior character model for a roster entry: the same look the street body of its job wears (PopulationLOD).
static func look_of(e: Dictionary) -> String:
	var pop: GDScript = load("res://scripts/population/population_lod.gd")
	var job := clampi(int(e.get("job", 4)), 0, pop.JOB_LOOK.size() - 1)
	return String((pop.LOOK_MODEL[pop.JOB_LOOK[job]] as Array)[0])


## "Hale's Smithy", "Pennick's Bakery", "Vane's General Store" for a building with a named keeper; "" otherwise (the inn keeps its
## hashed inn name).
static func building_name(bid: String) -> String:
	var e := keeper_of(bid)
	if e.is_empty():
		return ""
	var last := String(e["name"]).get_slice(" ", 1)
	match String(SliceTown.building(bid).get("type", "")):
		"smithy": return "%s's Smithy" % last
		"bakery": return "%s's Bakery" % last
		"general_shop": return "%s's General Store" % last
	return ""
