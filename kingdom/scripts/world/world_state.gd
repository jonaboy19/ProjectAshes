extends RefCounted
## Persistent state of interactive world objects (doors, chests, gates, levers, broken props) as DELTAS from
## their spawn defaults, keyed by stable ids ("<settlement_or_site>/<kind>/<index or plan id>"; never node paths
## or instance ids). Pure data: tests and the data-tier world can use it without nodes.
##
## Save: Life.snapshot() puts snapshot() under the key "interactives", so SaveManager's atomic write,
## checksum and backup already protect it. Adding keys here needs a default in restore(), not a schema bump.
## Restore is two-phase: restore() only loads the dictionary; each object pulls its own state by id when its
## node is built (get_state) and applies it silently. Ids of regions not loaded yet simply stay in the store;
## ids no object ever asks for are harmless; unknown or malformed entries in a save are dropped.
## Design: docs/research/MINING_PERCEPTION_INTERACTION.md 2.12 and 4.6.

const VERSION := 1
## About 200 KB of JSON.
const MAX_OBJECTS := 4000
const MAX_SCHED := 64

static var _shared: RefCounted


## The live store the game uses (Life.world_state points at it). Tests may create their own instances with new().
static func shared() -> RefCounted:
	if _shared == null:
		_shared = (load("res://scripts/world/world_state.gd") as GDScript).new()
	return _shared

var objects := {}             # id -> Dictionary of delta keys
## Ids written since the last snapshot (autosave tick clears it); lets a saver chunk work.
var dirty := {}
## Deferred verbs as plain data: [{t: int game-seconds, id: String, verb: String}] - never Callables.
var sched: Array = []


func clear() -> void:
	objects.clear()
	dirty.clear()
	sched.clear()


func has_state(id: String) -> bool:
	return objects.has(id)


func size() -> int:
	return objects.size()


## State of `id`: `defaults` overlaid with the stored deltas (a fresh dictionary, safe to modify).
func get_state(id: String, defaults: Dictionary = {}) -> Dictionary:
	var out := defaults.duplicate(true)
	var d: Variant = objects.get(id)
	if d is Dictionary:
		for k: Variant in (d as Dictionary):
			out[k] = (d as Dictionary)[k]
	return out


## Merge `patch` into the delta of `id`. Keys whose value equals the default are dropped, and an id with no
## deltas left is erased, so the store only ever holds what differs from a fresh world. Returns false when the
## store is full (a new id is refused; existing ids still update).
func set_state(id: String, patch: Dictionary, defaults: Dictionary = {}) -> bool:
	if id == "":
		return false
	var cur: Dictionary = (objects[id] as Dictionary).duplicate() if objects.has(id) else {}
	if not objects.has(id) and objects.size() >= MAX_OBJECTS:
		return false
	for k: Variant in patch:
		var v: Variant = patch[k]
		if defaults.has(k) and typeof(defaults[k]) == typeof(v) and defaults[k] == v:
			cur.erase(k)
		else:
			cur[k] = v
	if cur.is_empty():
		objects.erase(id)
	else:
		objects[id] = cur
	dirty[id] = true
	return true


func erase(id: String) -> void:
	if objects.erase(id):
		dirty[id] = true


## Ids starting with `prefix` (a region chunk: "ashford/").
func ids_with_prefix(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in objects:
		if k.begins_with(prefix):
			out.append(k)
	return out


func schedule(t: int, id: String, verb: String) -> void:
	if sched.size() >= MAX_SCHED:
		return
	sched.append({"t": t, "id": id, "verb": verb})
	sched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) < int(b["t"]))


## Scheduled entries due at or before `now` (removed from the queue, in time order).
func pop_due(now: int) -> Array:
	var out: Array = []
	while not sched.is_empty() and int((sched[0] as Dictionary)["t"]) <= now:
		out.append(sched.pop_front())
	return out


func snapshot() -> Dictionary:
	dirty.clear()
	return {"v": VERSION, "objects": objects.duplicate(true), "sched": sched.duplicate(true)}


## Load a snapshot in place. Anything malformed is skipped, missing keys default; never throws.
func restore(d: Variant) -> void:
	clear()
	if not d is Dictionary:
		return
	var data: Dictionary = d
	var objs: Variant = data.get("objects", {})
	if objs is Dictionary:
		for k: Variant in (objs as Dictionary):
			if objects.size() >= MAX_OBJECTS:
				break
			var v: Variant = (objs as Dictionary)[k]
			if k is String and v is Dictionary and not (v as Dictionary).is_empty():
				objects[k] = _clean(v)
	var sc: Variant = data.get("sched", [])
	if sc is Array:
		for e: Variant in sc:
			if e is Dictionary and (e as Dictionary).has("t") and (e as Dictionary).has("id") and sched.size() < MAX_SCHED:
				sched.append({"t": int((e as Dictionary)["t"]), "id": String((e as Dictionary)["id"]), "verb": String((e as Dictionary).get("verb", ""))})


## JSON turns ints into floats: bring whole floats back to ints so a round trip compares equal.
static func _clean(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in (v as Dictionary):
			out[k] = _clean((v as Dictionary)[k])
		return out
	if v is Array:
		var arr: Array = []
		for e: Variant in (v as Array):
			arr.append(_clean(e))
		return arr
	if v is float and is_equal_approx(floorf(v), v) and absf(v) < 1.0e9:
		return int(v)
	return v
