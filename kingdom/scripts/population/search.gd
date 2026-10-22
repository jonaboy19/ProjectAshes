extends RefCounted
## Search with claimed hiding spots (docs/research/MINING_PERCEPTION_INTERACTION.md 2.5 / 4.3, own implementation).
##
## Every alarm event opens ONE Search record (origin, radius, the `search` smart-object spots around it, who claimed
## which, which were checked, an expiry). Searchers (guards, brave citizens in the SEARCH act) claim the nearest
## free spot - doorways, alleys, behind stalls, haystacks, crates - walk there, look for CHECK_S seconds, mark it
## checked and take the next one. At most MAX_SEARCHERS comb at once, the others hold their post. When every spot
## is checked or the time is up the search ends and its searchers stand down (villager.gd writes danger memory).
##
## A crouching player inside HIDE_R of a spot that `hides` is "hidden": vision treats them as nearly invisible
## (Perception.STANCE_HIDDEN) and only a searcher who checks the spot, or walks close to it in good light, finds
## them (found()).
##
## Spots are SmartObjects of the local type "search" (npc_world.gd LOCAL_TYPES): the claim primitive is the
## smart-object claim, so two searchers never take the same spot. Static data, no nodes, clock passed in.

enum Kind { DOORWAY, ALLEY, BEHIND_STALL, HAYSTACK, CRATE }
const KIND_NAMES := ["doorway", "alley", "behind_stall", "haystack", "crate"]
const TYPE := "search"

const MAX_SEARCHES := 4
const MAX_SEARCHERS := 2
const CHECK_S := 3.0
const SEARCH_SECONDS := 45.0
const RADIUS := 26.0
## A new alarm within this distance of a live search joins it (extends it) instead of opening another.
const MERGE_R := 14.0
## Crouching this close to a hiding spot counts as hidden in it.
const HIDE_R := 1.7
## A searcher checking the spot finds anyone hidden in it from this close.
const CHECK_R := 2.2
## Walking past: found when close and lit (see found()).
const PASS_R := 4.0
const PASS_NEED := 0.42

## spot id -> {kind, pos: Vector2, sid, hides}
static var _spots := {}
static var searches: Array = []
static var _next := 1
static var _held := {}                 # person -> search id
## Debug / QA counters.
static var finds := 0


static func reset() -> void:
	_spots.clear()
	searches.clear()
	_held.clear()
	_next = 1
	finds = 0


# ================================================================ spots
## Register an existing SmartObjects spot (type "search") as a search spot.
static func add_spot(spot_id: int, kind: int, pos: Vector2, sid: int, hides := true) -> void:
	if spot_id < 0:
		return
	_spots[spot_id] = {"kind": kind, "pos": pos, "sid": sid, "hides": hides}


static func spot_count(sid := -1) -> int:
	if sid < 0:
		return _spots.size()
	var n := 0
	for k: int in _spots:
		if int(_spots[k]["sid"]) == sid:
			n += 1
	return n


static func spot_pos(spot_id: int) -> Vector2:
	return (_spots[spot_id]["pos"] as Vector2) if _spots.has(spot_id) else Vector2.INF


static func spot_kind(spot_id: int) -> int:
	return int(_spots[spot_id]["kind"]) if _spots.has(spot_id) else -1


## Spot ids within `radius` of `origin`, nearest first.
static func spots_near(origin: Vector2, radius: float) -> Array:
	var rows: Array = []
	var r2 := radius * radius
	for k: int in _spots:
		var d2 := origin.distance_squared_to(_spots[k]["pos"])
		if d2 <= r2:
			rows.append([d2, k])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) if float(a[0]) != float(b[0]) else int(a[1]) < int(b[1]))
	var out: Array = []
	for r: Array in rows:
		out.append(int(r[1]))
	return out


## Lay the search spots of settlement `sid` into `so` (the SmartObjects instance) and register them. Deterministic:
## doorways in front of every third house, alleys behind every seventh, behind and beside the market stalls, a haystack
## by each barn/stable (or one on the outskirts). `graph` (StreetGraph, optional) pushes points out of walls.
## Returns how many were placed.
static func populate(so: RefCounted, sid: int, plan: Dictionary, centre: Vector2, plaza_r: float, radius: float,
		stalls: PackedVector2Array, graph: RefCounted = null, height_fn: Callable = Callable()) -> int:
	if so == null or not (so.get("types") as Dictionary).has(TYPE):
		return 0
	var n := 0
	var lots: Array = plan.get("lots", [])
	var k := 0
	var hay := 0
	for lot: Dictionary in lots:
		k += 1
		var lp: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var face := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(-face.y, face.x)
		var asset := String(lot.get("asset", ""))
		if k % 3 == 1:
			n += _put(so, sid, Kind.DOORWAY, lp + face * 3.0 + side * 0.9, yaw + PI, graph, height_fn, "door/%d" % k)
		if k % 7 == 2:
			n += _put(so, sid, Kind.ALLEY, lp - face * 4.2 + side * 4.4, yaw, graph, height_fn, "alley/%d" % k)
		if asset.contains("barn") or asset.contains("stable") or asset.contains("farm") or asset.contains("mill"):
			n += _put(so, sid, Kind.HAYSTACK, lp + side * 5.0 - face * 1.0, yaw, graph, height_fn, "hay/%d" % k)
			hay += 1
	if hay == 0:
		var a := float(absi(hash([sid, 17])) % 628) / 100.0
		n += _put(so, sid, Kind.HAYSTACK, centre + Vector2(cos(a), sin(a)) * radius * 0.78, a, graph, height_fn, "hay/out")
	for i in stalls.size():
		var out := (stalls[i] - centre).normalized() if stalls[i].distance_to(centre) > 0.5 else Vector2.RIGHT
		var tangent := Vector2(-out.y, out.x)
		n += _put(so, sid, Kind.BEHIND_STALL, stalls[i] + out * 2.1, atan2(-out.x, -out.y), graph, height_fn, "stall/%d" % i)
		if i % 2 == 0:
			n += _put(so, sid, Kind.CRATE, stalls[i] + out * 1.2 + tangent * 2.3, atan2(-out.x, -out.y), graph, height_fn, "crate/%d" % i)
	return n


static func _put(so: RefCounted, sid: int, kind: int, p: Vector2, yaw: float, graph: RefCounted, height_fn: Callable, key: String) -> int:
	var q := p
	if graph != null:
		q = graph.call("push_out", p, 0.6)
	var y := float(height_fn.call(q.x, q.y)) if height_fn.is_valid() else 0.0
	var id: int = so.call("add", TYPE, Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y, q.y)), sid, "settlement/%d/search/%s" % [sid, key])
	if id < 0:
		return 0
	add_spot(id, kind, q, sid, true)
	return 1


# ================================================================ search records
static func _record(id: int) -> Dictionary:
	for r: Dictionary in searches:
		if int(r["id"]) == id:
			return r
	return {}


static func is_active(id: int, now_ms: int) -> bool:
	var r := _record(id)
	return not r.is_empty() and String(r["state"]) == "active" and now_ms < int(r["expires"])


static func state_of(id: int) -> String:
	return String(_record(id).get("state", "none"))


static func origin_of(id: int) -> Vector2:
	return _record(id).get("origin", Vector2.INF)


static func active_count(now_ms: int) -> int:
	var n := 0
	for r: Dictionary in searches:
		if String(r["state"]) == "active" and now_ms < int(r["expires"]):
			n += 1
	return n


## Open (or join) the search for an alarm at `origin`. The same `event_id`, or an origin within MERGE_R of a live
## search, returns that search (and extends it). Returns the search id.
static func begin(origin: Vector2, sid: int, now_ms: int, event_id := 0, radius := RADIUS, seconds := SEARCH_SECONDS) -> int:
	for r: Dictionary in searches:
		if String(r["state"]) != "active" or now_ms >= int(r["expires"]):
			continue
		if (event_id != 0 and int(r["event"]) == event_id) or (Vector2(r["origin"]).distance_to(origin) < MERGE_R):
			r["expires"] = maxi(int(r["expires"]), now_ms + int(seconds * 1000.0))
			if Vector2(r["origin"]).distance_to(origin) < MERGE_R:
				r["origin"] = origin          # a fresher sighting nearby moves the focus
			if event_id != 0 and int(r["event"]) == 0:
				r["event"] = event_id
			return int(r["id"])
	var rec := {"id": _next, "event": event_id, "origin": origin, "radius": radius, "sid": sid, "t0": now_ms,
		"expires": now_ms + int(seconds * 1000.0), "spots": spots_near(origin, radius), "checked": {}, "claims": {},
		"state": "active", "found": false}
	_next += 1
	searches.append(rec)
	if searches.size() > MAX_SEARCHES:
		var old: Dictionary = searches.pop_front()
		for p: int in (old["claims"] as Dictionary).keys():
			_held.erase(p)
	return int(rec["id"])


static func search_of(person: int) -> int:
	return int(_held.get(person, 0))


static func searchers(id: int) -> int:
	return (_record(id).get("claims", {}) as Dictionary).size()


static func claimed_spot(person: int) -> int:
	var r := _record(search_of(person))
	if r.is_empty():
		return -1
	return int((r["claims"] as Dictionary).get(person, -1))


## `person` claims the nearest free, unchecked spot of search `id` (through the smart-object claim, so nobody shares
## one). Idempotent while their claim stands. -1 when the searcher cap is reached or nothing is left: they hold.
static func claim(id: int, person: int, here: Vector2, so: RefCounted = null) -> int:
	var r := _record(id)
	if r.is_empty() or String(r["state"]) != "active":
		return -1
	var claims: Dictionary = r["claims"]
	if claims.has(person):
		return int(claims[person])
	if claims.size() >= MAX_SEARCHERS:
		return -1
	var taken := {}
	for p: int in claims:
		taken[int(claims[p])] = true
	var rows: Array = []
	for sp: int in r["spots"]:
		if taken.has(sp) or (r["checked"] as Dictionary).has(sp):
			continue
		var pos: Vector2 = _spots[sp]["pos"]
		rows.append([here.distance_to(pos) + 0.35 * pos.distance_to(r["origin"]), sp])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) if float(x[0]) != float(y[0]) else int(x[1]) < int(y[1]))
	var best := -1
	for row: Array in rows:
		var cand := int(row[1])
		if so == null or bool(so.call("claim", cand, 0, person)):
			best = cand
			break
	if best < 0:
		return -1
	claims[person] = best
	_held[person] = id
	return best


## The walk-to point of a claimed spot (the smart object's approach point when `so` is given).
static func approach(spot_id: int, so: RefCounted = null) -> Vector2:
	if so != null and _spots.has(spot_id):
		var p: Vector3 = so.call("approach_point", spot_id, 0)
		return Vector2(p.x, p.z)
	return spot_pos(spot_id)


## `person` finished looking at their spot: it counts as checked and they are free to take another.
static func finish_check(person: int, so: RefCounted = null) -> int:
	var r := _record(search_of(person))
	if r.is_empty():
		return -1
	var spot := int((r["claims"] as Dictionary).get(person, -1))
	if spot >= 0:
		(r["checked"] as Dictionary)[spot] = true
	(r["claims"] as Dictionary).erase(person)
	_held.erase(person)
	if so != null:
		so.call("release", person)
	return spot


## `person` leaves the search without finishing (distracted, fled, died): the spot stays unchecked.
static func release(person: int, so: RefCounted = null) -> void:
	var r := _record(search_of(person))
	if not r.is_empty():
		(r["claims"] as Dictionary).erase(person)
	_held.erase(person)
	if so != null:
		so.call("release", person)


static func unchecked(id: int) -> int:
	var r := _record(id)
	if r.is_empty():
		return 0
	var n := 0
	for sp: int in r["spots"]:
		if not (r["checked"] as Dictionary).has(sp):
			n += 1
	return n


## Expire searches (time up, or every spot checked and nobody still looking). Returns the ids that just ended.
static func tick(now_ms: int, so: RefCounted = null) -> Array:
	var ended: Array = []
	for r: Dictionary in searches:
		if String(r["state"]) != "active":
			continue
		var done := (r["spots"] as Array).size() > 0 and unchecked(int(r["id"])) == 0 and (r["claims"] as Dictionary).is_empty()
		if now_ms >= int(r["expires"]) or done:
			r["state"] = "done" if done else "expired"
			for p: int in (r["claims"] as Dictionary).keys():
				_held.erase(p)
				if so != null:
					so.call("release", p)
			(r["claims"] as Dictionary).clear()
			ended.append(int(r["id"]))
	return ended


## The search is over without a find: its searchers' alert should drop. Returns true once per ended search state read.
static func mark_found(id: int) -> void:
	var r := _record(id)
	if not r.is_empty():
		r["found"] = true
		finds += 1


# ================================================================ hiding and finding
## The hiding spot a player at `pos` is crouched in (-1 when not crouching or none near).
static func hidden_spot(pos: Vector2, crouching: bool) -> int:
	if not crouching or _spots.is_empty():
		return -1
	var best := -1
	var best_d := HIDE_R * HIDE_R
	for k: int in _spots:
		if not bool(_spots[k]["hides"]):
			continue
		var d2 := pos.distance_squared_to(_spots[k]["pos"])
		if d2 < best_d:
			best_d = d2
			best = k
	return best


## Does a searcher at `searcher` find whoever hides in `spot`? `checking`: they are standing at it looking. `light`
## 0..1 at the spot (Perception.light_at). Proximity decides, light helps: lit and close finds, dark needs a check.
static func found(spot_id: int, searcher: Vector2, light: float, checking: bool) -> bool:
	if not _spots.has(spot_id):
		return false
	var d := searcher.distance_to(_spots[spot_id]["pos"])
	if checking and d <= CHECK_R:
		return true
	if d >= PASS_R:
		return false
	var prox := 1.0 - d / PASS_R
	return prox * (0.35 + 0.65 * clampf(light, 0.0, 1.0)) >= PASS_NEED


# ================================================================ persistence
## Live searches (origin, remaining seconds, event id) - spots and claims are rebuilt, the town is the same.
static func serialize(now_ms: int) -> Array:
	var out: Array = []
	for r: Dictionary in searches:
		if String(r["state"]) == "active" and now_ms < int(r["expires"]):
			out.append([snappedf(Vector2(r["origin"]).x, 0.1), snappedf(Vector2(r["origin"]).y, 0.1), int(r["sid"]),
				int(r["event"]), float(int(r["expires"]) - now_ms) / 1000.0])
	return out


static func deserialize(rows: Variant, now_ms: int) -> void:
	searches.clear()
	_held.clear()
	if not rows is Array:
		return
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 5:
			continue
		var a: Array = row
		begin(Vector2(float(a[0]), float(a[1])), int(a[2]), now_ms, int(a[3]), RADIUS, clampf(float(a[4]), 1.0, SEARCH_SECONDS))
