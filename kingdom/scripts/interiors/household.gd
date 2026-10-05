extends RefCounted
## Who is inside a building right now (package F6). WorldSim has no per-building home: `WorldSim.home[i]` is the
## settlement id, and the home / workshop BUILDING of a person is derived (deterministically) in WorldSim._spot():
## `lots[hash(i * 131) % lots.size()]` for the home, `lots[hash(i * 131 + 17) % lots.size()]` for a craftsman's shop.
## This script mirrors those two formulas so the interior shows exactly the people the street simulation sends there,
## then applies the one daily timetable (scripts/population/schedule.gd) to decide who is in, and what they do.
##
## Pure static functions over plain arrays (a `job_of` Callable instead of WorldSim), plus thin wrappers that read the
## live WorldSim / WorldGen. Acts: sleep, eat, hearth, table, counter, drink. Preload this script; no class_name.

const Schedule := preload("res://scripts/population/schedule.gd")

## Cap on bodies inside one room (phones: every body is a skinned mesh).
const MAX_INSIDE := 6
## Door-to-door walking speed of people entering or leaving, m/s.
const WALK := 1.5

const ACTS := ["sleep", "eat", "hearth", "table", "counter", "drink"]


# ------------------------------------------------------------------ the two WorldSim formulas
static func home_lot(person: int, lot_count: int) -> int:
	return (hash(person * 131) % lot_count) if lot_count > 0 else -1


static func work_lot(person: int, lot_count: int) -> int:
	return (hash(person * 131 + 17) % lot_count) if lot_count > 0 else -1


## People of settlement rows [first, last) whose home building is lot `lot`.
static func residents_of(lot: int, lot_count: int, first: int, last: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(first, last):
		if home_lot(i, lot_count) == lot:
			out.append(i)
	return out


## Craftsmen and merchants (jobs 1 and 2) whose workshop is lot `lot`.
static func workers_of(lot: int, lot_count: int, first: int, last: int, job_of: Callable) -> Array[int]:
	var out: Array[int] = []
	for i in range(first, last):
		var j := int(job_of.call(i))
		if (j == 1 or j == 2) and work_lot(i, lot_count) == lot:
			out.append(i)
	return out


# ------------------------------------------------------------------ acts by hour
## What a person at home does at this hour. Beds from 22:00 to 06:00, meals at breakfast, noon and supper, otherwise
## the fire (evenings, mornings, odd rows) or the table.
static func home_act(hour: float, person: int) -> String:
	var h := fposmod(hour, 24.0)
	if h >= 22.0 or h < 6.0:
		return "sleep"
	if (h >= 6.0 and h < 7.0) or (h >= 12.0 and h < 13.0) or (h >= 18.0 and h < 19.5):
		return "eat"
	if h >= 19.5 or h < 8.0 or person % 2 == 0:
		return "hearth"
	return "table"


## Who is indoors and what they do. Each entry: {person, act, role}.
##   house / tavern bedrooms: residents whose schedule phase is HOME (act from `home_act`)
##   shops: the merchants and craftsmen of this workshop whose phase is WORK ("counter") and residents at HOME
##   taverns: also anyone whose phase is INN in the evening ("drink"), up to `inn_cap`
## `everyone` is the candidate patron list for taverns (the whole settlement); empty for homes and shops.
static func roster(residents: Array, workers: Array, everyone: Array, hour: float, day: int, flags: int, job_of: Callable,
		category: String, inn_cap := 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for p: int in residents:
		if Schedule.phase(int(job_of.call(p)), hour, flags, p, day) == Schedule.Phase.HOME:
			out.append({"person": p, "act": home_act(hour, p), "role": "resident"})
			seen[p] = true
	if category == "shop":
		for p: int in workers:
			if seen.has(p):
				continue
			if Schedule.phase(int(job_of.call(p)), hour, flags, p, day) == Schedule.Phase.WORK:
				out.append({"person": p, "act": "counter", "role": "worker"})
				seen[p] = true
				break      # one shopkeeper at the counter
	if category == "tavern":
		var n := 0
		for p: int in everyone:
			if n >= inn_cap:
				break
			if seen.has(p):
				continue
			if Schedule.phase(int(job_of.call(p)), hour, flags, p, day) == Schedule.Phase.INN:
				out.append({"person": p, "act": "drink", "role": "patron"})
				seen[p] = true
				n += 1
	if out.size() > MAX_INSIDE:
		out.resize(MAX_INSIDE)
	return out


# ------------------------------------------------------------------ placing the acts on waypoints
## Waypoint lists (from InteriorLayouts) that an act may use, best first.
static func slots_for(act: String, wp: Dictionary) -> Array:
	match act:
		"sleep": return wp.get("bed", [])
		"eat": return (wp.get("table", []) as Array) + (wp.get("hearth", []) as Array)
		"hearth": return (wp.get("hearth", []) as Array) + (wp.get("table", []) as Array)
		"table": return (wp.get("table", []) as Array) + (wp.get("hearth", []) as Array)
		"counter": return wp.get("counter", [])
		"drink": return (wp.get("bar", []) as Array) + (wp.get("table", []) as Array)
	return []


## Gives every roster entry its own waypoint (never two people on one chair or bed); entries that find no free slot
## are dropped. Returns [{person, act, role, wp}].
static func place(entries: Array, wp: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used := {}
	for e: Dictionary in entries:
		var slots: Array = slots_for(String(e["act"]), wp)
		var chosen: Variant = null
		for s: Dictionary in slots:
			var key := "%s|%d" % [s["p"], int(s.get("level", 0))]
			if not used.has(key):
				used[key] = true
				chosen = s
				break
		if chosen == null:
			continue
		var o: Dictionary = e.duplicate()
		o["wp"] = chosen
		out.append(o)
	return out


# ------------------------------------------------------------------ live world wrappers
## {sid, lot, asset, lots} for the lot standing at `lot_pos` (the InteriorDoor's meta), or {} when unknown.
static func lot_at(lot_pos: Vector2) -> Dictionary:
	var settlements: Array = WorldGen.settlements
	for si in settlements.size():
		var lots: Array = (settlements[si] as Dictionary).get("plan", {}).get("lots", [])
		for li in lots.size():
			var pos: Vector2 = lots[li].get("pos", Vector2.INF)
			if pos.distance_squared_to(lot_pos) < 0.0001:
				return {"sid": si, "lot": li, "asset": String(lots[li].get("asset", "")), "count": lots.size()}
	return {}


## The live roster for a lot at `hour`: [{person, act, role}] (not yet placed).
static func roster_for_lot(info: Dictionary, hour: float, category: String) -> Array[Dictionary]:
	if info.is_empty() or WorldSim.ranges.is_empty():
		return []
	var sid := int(info["sid"])
	if sid < 0 or sid >= WorldSim.ranges.size():
		return []
	var r: Vector2i = WorldSim.ranges[sid]
	var count := int(info["count"])
	var job_of := func(i: int) -> int: return int(WorldSim.job[i])
	var res: Array[int] = []
	for i in residents_of(int(info["lot"]), count, r.x, r.y):
		if not WorldSim.is_dead(i):
			res.append(i)
	var work: Array[int] = []
	if category == "shop":
		for i in workers_of(int(info["lot"]), count, r.x, r.y, job_of):
			if not WorldSim.is_dead(i):
				work.append(i)
	var all: Array[int] = []
	if category == "tavern":
		for i in range(r.x, r.y):
			if not WorldSim.is_dead(i):
				all.append(i)
	return roster(res, work, all, hour, WorldSim.day, WorldSim.mood_flags(sid), job_of, category)
