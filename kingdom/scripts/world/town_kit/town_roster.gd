extends RefCounted
## The named residents of every kit town (data/region1/towns/<id>.json `residents`, docs/design/FOUNDATION_PLAN.md F8).
##
## A kit town is a WorldSim settlement, so its people are rows of the data tier. `bind(tid)` picks one row for each
## roster entry (deterministically, spread over the settlement), gives it the entry's job, and from then on:
##   WorldSim.person_name(row)   is the roster name            (name_of)
##   WorldSim._spot(...)         walks the row to its own home and workplace door   (spot)
##   WorldSim._current_phase()   applies the entry's schedule overrides             (override_phase)
##   PopulationLOD               prefers named people when it picks who gets a body  (embody_weight)
##   VillageServices._npc_info   talks as the roster person (dialogue/<dir>/<id>.json) (info_for)
##   WorldSim.kill_person        fires `died {actor}` on the quest bus              (on_died)
## Row-keyed hooks (the ones WorldSim, PopulationLOD and the interiors call) need no town id; the rest take it.
## Preload this script (no class_name); every function is static. Roster ids are unique across the region.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownLots := preload("res://scripts/world/town_kit/town_lots.gd")
const Schedule := preload("res://scripts/population/schedule.gd")

## Roles that run a building (the others just work near it), keyed by the building type the lot is tagged with.
const KEEPER_ROLES := {"smithy": "blacksmith", "bakery": "baker", "tavern": "innkeeper", "general_shop": "shopkeeper", "healer": "herbalist"}

static var _by_id: Dictionary = {}          # roster id -> entry (every town)
static var _town_of: Dictionary = {}        # roster id -> town id
static var _loaded := false
static var _rows: Dictionary = {}           # town id -> {roster id -> WorldSim row}
static var _id_of: Dictionary = {}          # WorldSim row -> roster id (rows are unique across towns)
static var _sched: Dictionary = {}          # row -> Array of {from, to, phase:int}
static var _bound_for: Dictionary = {}      # town id -> WorldSim.population() the binding was made for
static var _outdoor: Dictionary = {}        # row -> true when the named person works at a yard, not inside a building


## WorldSim is an autoload that preloads this script, so it is reached through the tree, not by its global name.
static func _ws() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("WorldSim") if loop is SceneTree else null


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_town_of.clear()
	for tid: String in TownData.ids():
		for e: Dictionary in TownData.residents(tid):
			_by_id[String(e["id"])] = e
			_town_of[String(e["id"])] = tid


## Forgets the loaded files too (tests that edit town data, the generator's checks).
static func reload() -> void:
	_loaded = false
	TownData.clear_cache()
	clear()


static func residents(tid: String) -> Array:
	return TownData.residents(tid)


static func entry(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})


static func town_of(id: String) -> String:
	_load()
	return String(_town_of.get(id, ""))


## Forgets every binding (WorldSim.reset: the rows are about to be re-rolled).
static func clear() -> void:
	_rows.clear()
	_id_of.clear()
	_sched.clear()
	_bound_for.clear()
	_outdoor.clear()


static func settlement_id(tid: String) -> int:
	var nm := String(TownData.town(tid).get("settlement", ""))
	for s in WorldGen.settlements:
		if String(s["name"]) == nm:
			return int(s["id"])
	return -1


static func is_bound(tid: String) -> bool:
	var ws := _ws()
	return ws != null and int(_bound_for.get(tid, -1)) == int(ws.call("population")) and not (_rows.get(tid, {}) as Dictionary).is_empty()


## Binds every kit town (WorldSim._populate calls this once the population exists).
static func bind_all(force := false) -> void:
	for tid: String in TownData.ids():
		bind(tid, force)


## Picks a WorldSim row for every bindable resident of `tid`. Safe to call again (it rebinds only after a new world).
## Returns {id: row}.
static func bind(tid: String, force := false) -> Dictionary:
	_load()
	var ws := _ws()
	var sid := settlement_id(tid)
	var ranges: Array = ws.get("ranges") if ws != null else []
	if sid < 0 or ranges.size() <= sid:
		return {}
	if not force and is_bound(tid):
		return _rows[tid]
	_unbind(tid)
	var range_i: Vector2i = ranges[sid]
	var rows := {}
	var order := residents(tid).duplicate()
	# Children first: only a stable slice of the day labourers count as children, so they pick before everyone else.
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (0 if bool(a.get("child", false)) else 1) < (0 if bool(b.get("child", false)) else 1))
	var pools := _pools(ws, range_i)
	var jobs: PackedByteArray = ws.get("job")
	var jobs_changed := false
	for e: Dictionary in order:
		if not bool(e.get("bind", true)):
			continue
		var id := String(e["id"])
		var want_job := int(e.get("job", 4))
		var row := _pick(pools, id, want_job, bool(e.get("child", false)))
		if row < 0:
			continue
		rows[id] = row
		_id_of[row] = id
		if int(jobs[row]) != want_job:
			jobs[row] = want_job
			jobs_changed = true
		_sched[row] = _compile(e.get("schedule", []))
	if jobs_changed:
		ws.set("job", jobs)
	_rows[tid] = rows
	_bound_for[tid] = int(ws.call("population"))
	return rows


static func _unbind(tid: String) -> void:
	for id: String in (_rows.get(tid, {}) as Dictionary):
		var row := int(_rows[tid][id])
		_id_of.erase(row)
		_sched.erase(row)
	_rows.erase(tid)
	_bound_for.erase(tid)


## One pass over a settlement's living rows: `lists[kid * 8 + job]` is the ascending rows of that age group and job (a child is a day
## labourer in a stable tenth of the crowd, as NpcWorld.is_child says). Classifying every row once (not once per resident), with
## integer keys, keeps the binding of all 30 kit towns to a few milliseconds.
static func _pools(ws: Node, r: Vector2i) -> Array:
	var jobs: PackedByteArray = ws.get("job")
	var health: PackedByteArray = ws.get("health")
	var lists: Array = []
	for k in 16:
		lists.append([])
	for i in range(r.x, r.y):
		if health[i] == 0:
			continue
		var j := int(jobs[i])
		var kid := 8 if (j == 4 and absi(hash(i * 977 + 3)) % 10 == 0) else 0
		(lists[kid + j] as Array).append(i)
	return lists


## The row for roster entry `id`: among the free rows of the right age group, those with the wanted job first; the choice is a
## hash of the id. The row leaves the pools.
static func _pick(pools: Array, id: String, want_job: int, child: bool) -> int:
	var base := 8 if child else 0
	var cands: Array = pools[base + want_job]
	var pool: Array = cands
	if cands.is_empty():
		pool = []
		for j in 8:
			pool.append_array(pools[base + j])
		pool.sort()
	if pool.is_empty():
		return -1
	var row := int(pool[absi(hash(id)) % pool.size()])
	for j in 8:
		(pools[base + j] as Array).erase(row)
	return row


static func _compile(list: Array) -> Array:
	var out: Array = []
	for s: Dictionary in list:
		var ph := Schedule.NAMES.find(String(s.get("phase", "home")))
		if ph >= 0:
			out.append({"from": float(s.get("from", 0.0)), "to": float(s.get("to", 24.0)), "phase": ph})
	return out


# --- lookups ------------------------------------------------------------------------------

static func rows_of(tid: String) -> Dictionary:
	return _rows.get(tid, {})


static func row_of(id: String) -> int:
	var tid := town_of(id)
	return int((_rows.get(tid, {}) as Dictionary).get(id, -1)) if tid != "" else -1


static func id_of(row: int) -> String:
	return String(_id_of.get(row, ""))


static func is_named(row: int) -> bool:
	return _id_of.has(row)


static func bound_rows() -> Array:
	return _id_of.keys()


## The roster name of a bound row, "" when the row is an ordinary resident.
static func name_of(row: int) -> String:
	var id := String(_id_of.get(row, ""))
	return String(entry(id).get("name", "")) if id != "" else ""


static func _info(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return {}
	var tid := String(_town_of.get(id, ""))
	var dir := String(TownData.town(tid).get("dialogue_dir", tid))
	return {"id": id, "name": String(e.get("name", id)), "role": String(e.get("role", "villager")),
		"file": dir + "/" + id, "quest_role": "villager", "age": int(e.get("age", 30))}


## Identity for the talk system: {id, name, role, file, quest_role} or {} for an ordinary resident.
static func info_for(row: int) -> Dictionary:
	var id := String(_id_of.get(row, ""))
	return _info(id) if id != "" else {}


## Same for a resident that is not a WorldSim row (a Station such as Hesta Thorne), by roster id.
static func info_for_id(id: String) -> Dictionary:
	return _info(id)


## Bound rows of settlement `sid` whose home (which 0) or workplace (which 1) is building lot `lot` of its plan. A named person
## lives and works where the roster says (their door in WorldSim._spot), so a building's interior shows them, not the people
## the hash formula would have put there (interiors/household.gd).
static func rows_at(sid: int, lot: int, which: int) -> Array[int]:
	var out: Array[int] = []
	if _rows.is_empty():
		return out
	for tid: String in _rows:
		if settlement_id(tid) != sid:
			continue
		for id: String in _rows[tid]:
			var bid := String(entry(id).get("home" if which == 0 else "work", ""))
			var b := TownLots.building_in(tid, bid)
			if not b.is_empty() and int(b["lot"]) == lot:
				out.append(int(_rows[tid][id]))
	out.sort()
	return out


## Others' opinion of `id` as dialogue lines is in the dialogue files; this is the data side (kind, value) of
## how `a` relates to `b` ({} when unrelated).
static func relationship(a: String, b: String) -> Dictionary:
	return (entry(a).get("relationships", {}) as Dictionary).get(b, {})


## Seeds the NPC social graph (scripts/sim/npc_social_graph.gd, read by the near AI when it picks chat partners)
## with the roster's warm ties: family, friends, colleagues start out acquainted, so they seek each other out.
## Negative ties (rivals, creditors) stay in the dialogue; the graph only models familiarity. Returns edges added.
## `tid` limits it to one town ("" = every bound town).
static func seed_social_graph(graph: Variant, seed_value: int, tid := "") -> int:
	if graph == null or not graph.has_method("link"):
		return 0
	var added := 0
	var towns: Array = [tid] if tid != "" else _rows.keys()
	for t: String in towns:
		var rows: Dictionary = _rows.get(t, {})
		for id: String in rows:
			var ra := int(rows[id])
			for other: String in (entry(id).get("relationships", {}) as Dictionary):
				if not rows.has(other):
					continue
				var v := float(entry(id)["relationships"][other].get("value", 0))
				if v <= 0.0:
					continue
				var a := "worldsim:%d:%d" % [seed_value, ra]
				var b := "worldsim:%d:%d" % [seed_value, int(rows[other])]
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
	var e := entry(id)
	var bid := ""
	match which:
		0: bid = String(e.get("home", ""))
		1: bid = String(e.get("work", ""))
		_: return Vector2.INF
	return TownLots.door_of(bid, row)


## True for a named craftsman or merchant (job 1 / 2) of a town whose file says `outdoor_work` who works at a yard or gate (a work site door
## such as the capital's keep gate), not in a shop of the plan: WorldSim.is_indoors keeps 3 in 4 of such people inside their building, and
## a yard has no inside to find them in.
static func outdoor_work(row: int) -> bool:
	if not _id_of.has(row):
		return false
	if _outdoor.has(row):
		return bool(_outdoor[row])
	var id := String(_id_of[row])
	var tid := String(_town_of.get(id, ""))
	var bid := String(entry(id).get("work", ""))
	var doc := TownData.town(tid)
	var yes := bool(doc.get("outdoor_work", false)) and (doc.get("doors", {}) as Dictionary).has(bid) and TownLots.building(bid).is_empty()
	_outdoor[row] = yes
	return yes


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

## The roster entry that runs building `bid` ("thornfield_smithy"): the resident whose `work` is `bid` and whose role is the
## keeper role of that building type. {} for a building with no named keeper.
static func keeper_of(bid: String) -> Dictionary:
	if bid == "":
		return {}
	var tid := TownLots.tid_of_bid(bid)
	if tid == "":
		return {}
	var btype := String(TownLots.building_in(tid, bid).get("type", ""))
	for e: Dictionary in residents(tid):
		if String(e.get("work", "")) != bid or bool(e.get("child", false)):
			continue
		if KEEPER_ROLES.has(btype) and String(KEEPER_ROLES[btype]) == String(e.get("role", "")):
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
	match String(TownLots.building(bid).get("type", "")):
		"smithy": return "%s's Smithy" % last
		"bakery": return "%s's Bakery" % last
		"general_shop": return "%s's General Store" % last
	return ""
