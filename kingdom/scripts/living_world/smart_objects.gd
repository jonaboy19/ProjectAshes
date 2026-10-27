class_name SmartObjects
extends RefCounted
## Data-driven activity spots ("smart objects"): anvils, wells, benches, field rows, market stalls, bar counters,
## chapel pews, guard posts ... that villagers find, CLAIM (one person per slot), approach, align to, use with
## enter / loop / exit clips and props, and release. Types live in data/living_world/smart_objects.json.
##
## Pure data + math (no nodes): WorldSim can own one instance for the whole world and query it for data-tier
## residents (approach points as schedule targets), while embodied villagers drive a Session for the visible part.
##
##   var so := SmartObjects.new()
##   so.populate_settlement(settlement)            # spots around the plan's lots / landmarks (building_spots)
##   var id := so.add("anvil", Transform3D(...))   # or place them by hand
##   var pick := so.find(pos, {"act": "work", "job": "Blacksmith", "hour": 9.5}, 60.0)   # [spot, slot] or []
##   so.claim(pick[0], pick[1], person)            # false when taken
##   var s := so.session(person, pick[0], pick[1]) # SmartObjects.Session: step it every frame (see class)
##   so.release(person)
##
## Stand points: a slot's "stand" is in the object's frame (+Z = the object's front), or "auto": computed from the
## loop clip's sidecar anchor.at (LifeLibrary), so the hand-authored contact (hammer on the anvil face) lines up.

const DATA := "res://data/living_world/smart_objects.json"
const CELL := 16.0
## Pelvis distance behind the root that seated slots are laid out for (Life_Rest_Sit_Bench).
const SEAT_REF := 0.35
const JOBS := ["Farmer", "Blacksmith", "Merchant", "Guard", "Laborer", "Woodcutter"]
## Schema v2 (NPC_MOTION_RULES O1-O5). Every key below is optional; the defaults reproduce the v1 behaviour.
## Need names are the ones utility_brain restores (RESTORE table).
const NEEDS := ["water", "food", "rest", "social", "faith", "breath"]
const IK_LIMBS := ["hand_l", "hand_r", "foot_l", "foot_r"]
const ENTER_SIDES := ["front", "side", "back"]
const DEFAULT_ARC := 180.0          # approach_arc is a half-angle in degrees; 180 = any direction (v1)
const DEFAULT_WATCH_RING := 2.0
const WATCH_SPREAD := 0.6           # radians between neighbouring watcher points on the ring
const FRONT_HALF := 45.0            # side classification: |bearing| <= 45 front, <= 135 side, else back
const SIDE_HALF := 135.0
const SLOW_DIST := 1.2              # O2: slow down over the last metres of the approach
const SLOW_MIN := 0.35
const ARC_MARGIN := 12.0            # arrival waypoints stay this far inside the arc edge (reach slack)
const ARC_REACH := 0.15             # reach radius of an arc waypoint (v1: 0.35)
const NEED_EPS := 0.001

var types: Dictionary = {}
var building_spots: Dictionary = {}
var spots: Array = []               # Array[Dictionary]: {id, identity, has_stable_identity, type, xform, settlement, holders, drift}
var _grid: Dictionary = {}          # Vector2i -> Array[int]
var _settlement_spots: Dictionary = {} # settlement id -> Array[int], for bounded local schedule queries
var _held: Dictionary = {}          # person -> [spot, slot, claim_token]
var _watching: Dictionary = {}      # person -> [spot, watcher index] (O5)
var _spot_by_identity: Dictionary = {} # stable identity -> transient spot index
var _claim_serial := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else {}
	if typeof(d) == TYPE_DICTIONARY:
		types = d.get("types", {})
		building_spots = d.get("building_spots", {})
	_rng.seed = 1066


func add(type: String, xform: Transform3D, settlement := -1, stable_identity := "") -> int:
	if not types.has(type):
		push_warning("SmartObjects: unknown type " + type)
		return -1
	if not stable_identity.is_empty() and _spot_by_identity.has(stable_identity):
		var existing := int(_spot_by_identity[stable_identity])
		if String(spots[existing]["type"]) != type:
			push_warning("SmartObjects: identity reused for a different type: " + stable_identity)
			return -1
		return existing
	var id := spots.size()
	var cap := (types[type]["slots"] as Array).size()
	var holders := []
	holders.resize(cap)
	holders.fill(-1)
	var watchers := []
	watchers.resize(watchers_max(types[type]))
	watchers.fill(-1)
	spots.append({"id": id, "identity": stable_identity if not stable_identity.is_empty() else "runtime/%d" % id,
		"has_stable_identity": not stable_identity.is_empty(), "type": type, "xform": xform,
		"settlement": settlement, "holders": holders, "watchers": watchers, "drift": 0.0})
	if not stable_identity.is_empty():
		_spot_by_identity[stable_identity] = id
	if settlement >= 0:
		if not _settlement_spots.has(settlement):
			_settlement_spots[settlement] = []
		(_settlement_spots[settlement] as Array).append(id)
	var c := _cell(xform.origin)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(id)
	return id


## Stable slot key for an authoritative action lease. Runtime-only manually added
## demo spots deliberately have no persistent resource key.
func slot_resource_key(spot: int, slot: int) -> String:
	if spot < 0 or spot >= spots.size():
		return ""
	var sp: Dictionary = spots[spot]
	if not bool(sp.get("has_stable_identity", false)):
		return ""
	var holders: Array = sp["holders"]
	if slot < 0 or slot >= holders.size():
		return ""
	return "%s/slot/%d" % [String(sp["identity"]), slot]


## Spots for one WorldGen settlement: every lot / landmark whose asset has a building_spots entry
## ("house" matches any house_* / mhouse_* / townhouse asset). height_fn(x, z) -> ground y (WorldGen.height).
func populate_settlement(s: Dictionary, height_fn: Callable = Callable()) -> int:
	var n := 0
	var plan: Dictionary = s.get("plan", {})
	var items: Array = []
	items.append_array(plan.get("lots", []))
	items.append_array(plan.get("landmarks", []))
	var settlement_id := int(s.get("id", -1))
	var lot_count := (plan.get("lots", []) as Array).size()
	for item_i in items.size():
		var lot: Dictionary = items[item_i]
		var key := String(lot.get("asset", ""))
		var list: Array = building_spots.get(key, [])
		if list.is_empty() and (key.begins_with("house") or key.begins_with("mhouse") or key.contains("townhouse")):
			list = building_spots.get("house", [])
		var p2: Vector2 = lot.get("pos", Vector2.ZERO)
		var yaw := float(lot.get("yaw", 0.0))
		var b := Basis(Vector3.UP, yaw)
		var item_kind := "lot" if item_i < lot_count else "landmark"
		var item_identity := "%s/%d/%d/%d" % [item_kind, roundi(p2.x * 10.0), roundi(p2.y * 10.0), item_i]
		for spot_i in list.size():
			var e: Dictionary = list[spot_i]
			var h := hash(p2) ^ hash(e["type"])
			if e.has("chance") and float(absi(h) % 1000) / 1000.0 > float(e["chance"]):
				continue
			var at: Array = e["at"]
			var o := Vector3(p2.x, 0.0, p2.y) + b * Vector3(float(at[0]), float(at[1]), float(at[2]))
			if height_fn.is_valid():
				o.y = float(height_fn.call(o.x, o.z))
			var identity := "settlement/%d/%s/%s/%d/%s" % [settlement_id, item_identity, key, spot_i, String(e["type"])]
			add(e["type"], Transform3D(b * Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0)))), o), settlement_id, identity)
			n += 1
	# Some activity spots are laid out only when their streamed presentation is
	# built (market stalls receive exact collision-clearance adjustments there).
	# Consume the resulting plain data without owning or instancing those visuals.
	for external_i in (plan.get("activity_spots", []) as Array).size():
		var e: Dictionary = plan["activity_spots"][external_i]
		var type := String(e.get("type", ""))
		var identity := String(e.get("identity", ""))
		if type.is_empty() or identity.is_empty() or typeof(e.get("position")) != TYPE_VECTOR3:
			continue
		var p: Vector3 = e["position"]
		var yaw := float(e.get("yaw", 0.0))
		add(type, Transform3D(Basis(Vector3.UP, yaw), p), settlement_id,
			"settlement/%d/%s" % [settlement_id, identity])
		n += 1
	return n


## Best free [spot, slot] near pos for a filter {act, job (name or index), hour, kid, tags: [...], type, role},
## optionally limited to one `settlement` candidate list; [] when nothing fits. `avoid` points are danger memory.
## O1: a `needs` filter {need: urgency 0..1} switches to need-weighted ranking: a type scores
## sum(urgency * type.needs[need]) and the cost is distance * crowding / score (types that serve none of the needs
## are skipped). Without that key the ranking is the v1 distance ranking, unchanged.
func find(pos: Vector3, filter: Dictionary, radius := 60.0, person := -1, avoid := PackedVector2Array(), avoid_r := 0.0) -> Array:
	var best := []
	var best_s := INF
	var want_needs: Dictionary = filter.get("needs", {})
	var use_needs := not want_needs.is_empty()
	var slot_filtered := filter.has("role") or filter.has("job")
	var recent_spot := int(filter.get("recent_spot", -1))
	var recent_penalty := clampf(float(filter.get("recent_penalty", 0.0)), 0.0, 10.0)
	var r2 := radius * radius * 1.0001      # cheap squared pre-check; the exact radius test follows
	var check_avoid := avoid_r > 0.0
	# type name -> [passes the filter (and serves the wanted needs), need score, occupancy max]; filter-only, so once per call
	var per_type := {}
	# Walk the grid cells (or the settlement list) in place: same visit order as before, no merged candidate array.
	var lists: Array = []
	if filter.has("settlement"):
		lists.append(_settlement_spots.get(int(filter["settlement"]), []))
	else:
		var r := int(ceil(radius / CELL))
		var c0 := _cell(pos)
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var cell: Variant = _grid.get(c0 + Vector2i(dx, dz))
				if cell != null:
					lists.append(cell)
	for list: Array in lists:
		for id: int in list:
			var sp: Dictionary = spots[id]
			var origin: Vector3 = (sp["xform"] as Transform3D).origin
			var d2 := origin.distance_squared_to(pos)
			if d2 > r2:
				continue
			var tname: String = sp["type"]
			var info: Variant = per_type.get(tname)
			if info == null:
				var tt: Dictionary = types[tname]
				var ok := _matches(tname, tt, filter)
				var ns := 1.0
				if ok and use_needs:
					ns = need_match(tt, want_needs)
					ok = ns > NEED_EPS
				info = [ok, ns, occupancy_max(tt)]
				per_type[tname] = info
			if not info[0]:
				continue
			var d := sqrt(d2)
			if d > radius:
				continue
			if check_avoid and _near_any(origin, avoid, avoid_r):
				continue
			var need_score: float = info[1]
			var slots: Array = types[tname]["slots"]
			var holders: Array = sp["holders"]
			var crowd := 1.0
			if use_needs:
				crowd = 1.0 + 0.5 * float(occupancy(id)) / float(info[2])
			for k in slots.size():
				# A data-tier resident often asks for its schedule target again on
				# every coarse simulation step. Keep its existing slot eligible so
				# refreshing the same goal does not make it churn through the queue.
				var holder: int = holders[k]
				if holder != -1 and holder != person:
					continue
				if slot_filtered and not _slot_matches(slots[k], filter):
					continue
				var score := d + float(absi(hash(person * 7 + id * 131 + k)) % 100) * 0.03
				if use_needs:
					score = (score + 1.0) * crowd / need_score
				if holder != person and id == recent_spot:
					# Soft preference only: a sole station remains eligible; owned refreshes stay stable.
					score += recent_penalty
				if holder == person:
					score = score * 0.9 if use_needs else score - 1.0  # small hysteresis keeps a valid activity stable
				if score < best_s:
					best_s = score
					best = [id, k]
	return best


func _slot_matches(slot: Dictionary, filter: Dictionary) -> bool:
	var role := String(slot.get("role", ""))
	if filter.has("role") and role != filter["role"]:
		return false
	# Slot-specific eligibility supports shared affordances such as a
	# merchant-only vendor position beside public customer positions.
	if filter.has("job") and slot.has("jobs"):
		var j = filter["job"]
		var jn: String = JOBS[j] if typeof(j) == TYPE_INT and j >= 0 and j < JOBS.size() else String(j)
		if not (slot["jobs"] as Array).has(jn):
			return false
	return true


static func _near_any(o: Vector3, pts: PackedVector2Array, r: float) -> bool:
	for p in pts:
		if p != Vector2.INF and (p.x - o.x) * (p.x - o.x) + (p.y - o.z) * (p.y - o.z) < r * r:
			return true
	return false


func _matches(type: String, t: Dictionary, f: Dictionary) -> bool:
	if (f.get("exclude_types", []) as Array).has(type):
		return false
	if f.has("type") and f["type"] != type:
		return false
	if f.has("act") and not (t.get("acts", []) as Array).has(f["act"]):
		return false
	if f.has("job") and t.has("jobs"):
		var j = f["job"]
		var jn: String = JOBS[j] if typeof(j) == TYPE_INT and j >= 0 and j < JOBS.size() else String(j)
		if not (t["jobs"] as Array).has(jn):
			return false
	if bool(f.get("job_required", false)) and not t.has("jobs"):
		return false
	if f.has("hour") and t.has("hours"):
		var h := float(f["hour"])
		var hr: Array = t["hours"]
		if h < float(hr[0]) or h >= float(hr[1]):
			return false
	if f.has("kid") and t.has("kids") and bool(t["kids"]) != bool(f["kid"]):
		return false
	for tag: String in f.get("tags", []):
		if not (t.get("tags", []) as Array).has(tag):
			return false
	for tag: String in f.get("not_tags", []):
		if (t.get("tags", []) as Array).has(tag):
			return false
	return true


func claim(spot: int, slot: int, person: int) -> bool:
	if spot < 0 or spot >= spots.size():
		return false
	var h: Array = spots[spot]["holders"]
	if slot < 0 or slot >= h.size() or (h[slot] != -1 and h[slot] != person):
		return false
	if h[slot] != person and occupancy(spot) >= occupancy_max(types[spots[spot]["type"]]):
		return false  # schema v2 occupancy.max (default = slot count, so v1 data is unaffected)
	var current: Array = _held.get(person, [])
	if current.size() >= 3 and int(current[0]) == spot and int(current[1]) == slot and h[slot] == person:
		return true  # idempotent refresh: preserve the Session's lease token
	release(person)
	release_watch(person)
	_claim_serial += 1
	h[slot] = person
	_held[person] = [spot, slot, _claim_serial]
	return true


func release(person: int) -> void:
	var w: Array = _held.get(person, [])
	if w.is_empty():
		return
	var h: Array = spots[w[0]]["holders"]
	if h[w[1]] == person:
		h[w[1]] = -1
	_held.erase(person)


func held_by(person: int) -> Array:
	var held: Array = _held.get(person, [])
	return held.slice(0, 2) if held.size() >= 2 else held


## Monotonic per-claim token. A Session keeps this token so an old activity
## cannot release or continue using a newer claim made by the same person id.
func claim_token(person: int) -> int:
	var held: Array = _held.get(person, [])
	return int(held[2]) if held.size() >= 3 else -1


func owns_claim(person: int, spot: int, slot: int, token: int) -> bool:
	var held: Array = _held.get(person, [])
	return (token >= 0 and held.size() >= 3 and int(held[0]) == spot
		and int(held[1]) == slot and int(held[2]) == token)


func release_claim(person: int, spot: int, slot: int, token: int) -> void:
	if owns_claim(person, spot, slot, token):
		release(person)


func occupancy(spot: int) -> int:
	var n := 0
	for p: int in spots[spot]["holders"]:
		if p != -1:
			n += 1
	return n


## World transform the character's root takes while using the slot (position + facing).
const _GM := preload("res://scripts/living_world/group_motion.gd")   # by path: no dependency on the global class cache
static var _CIRCLE_OFF := OS.has_environment("ASHES_MOTION_OFF")   # A/B gate recordings: the old fixed slots


func stand_xform(spot: int, slot: int) -> Transform3D:
	var sp: Dictionary = spots[spot]
	var t: Dictionary = types[sp["type"]]
	if bool(t.get("group", false)) and not _CIRCLE_OFF:
		# conversation circle (GroupMotion G1): members on a ring sized for the slot count, facing the centre, one arc left open
		# toward the spot's forward (the street side); fixed n = slot count so nobody slides when someone joins
		var ox: Transform3D = sp["xform"]
		var c2 := Vector2(ox.origin.x, ox.origin.z)
		var open := Vector2(ox.basis.z.x, ox.basis.z.z)
		var p2 := _GM.circle_slot(c2, (t["slots"] as Array).size(), slot, open if open.length_squared() > 0.0001 else Vector2(0, 1))
		return Transform3D(Basis(Vector3.UP, _GM.circle_yaw(c2, p2)), Vector3(p2.x, ox.origin.y, p2.y))
	var sl: Dictionary = t["slots"][slot]
	var face := deg_to_rad(float(sl.get("face", 180.0)))
	var fb := Basis(Vector3.UP, face)
	var local: Vector3
	if typeof(sl.get("stand")) == TYPE_STRING:
		local = _auto_stand(t, fb)
	else:
		var a: Array = sl["stand"]
		local = Vector3(float(a[0]), float(a[1]), float(a[2]))
	var drift := float(sp.get("drift", 0.0))
	local += Vector3(drift, 0, 0)   # field rows: the worker works along the row (object +X)
	var ox: Transform3D = sp["xform"]
	return Transform3D(ox.basis * fb, ox * local)


## "auto" stand point: the character root such that the loop clip's anchor.at lands on the object's origin.
func _auto_stand(t: Dictionary, fb: Basis) -> Vector3:
	var loops: Array = t.get("activity", {}).get("loop", [])
	var at := [0.0, 0.6, 0.0]
	for c: String in loops:
		var an = LifeLibrary.info(c).get("anchor")
		if typeof(an) == TYPE_DICTIONARY and an.has("at"):
			at = an["at"]
			break
	# character frame: +x left, +y forward. Godot character forward = +Z, left = +X (rotated by fb)
	var fwd := fb * Vector3(0, 0, 1)
	var left := fb * Vector3(1, 0, 0)
	return -fwd * float(at[1]) - left * float(at[0])


## Where to walk before aligning: straight back out from the stand point.
func approach_point(spot: int, slot: int) -> Vector3:
	var sx := stand_xform(spot, slot)
	var t: Dictionary = types[spots[spot]["type"]]
	if _slot_or_type(t, slot, "approach_dir", null) != null:
		return sx.origin + approach_dir_world(spot, slot) * float(t.get("approach", 1.0))
	return sx.origin - sx.basis.z * float(t.get("approach", 1.0))


func activity(spot: int, slot := 0) -> Dictionary:
	var t: Dictionary = types[spots[spot]["type"]]
	var role := String(t["slots"][slot].get("role", ""))
	var ra: Dictionary = t.get("role_activity", {})
	return ra[role] if ra.has(role) else t.get("activity", {})


## WorldSim hook for data-tier people: 2D approach target for (person, act, job) near a settlement centre,
## soft-claimed (occupancy counted) so a crowd spreads over the spots. Vector2.INF when none.
func target_for(person: int, center: Vector3, act: String, job: int, hour: float, radius := 120.0, role := "", settlement_id := -1) -> Vector2:
	var filter := {"act": act, "job": job, "hour": hour}
	if settlement_id >= 0:
		filter["settlement"] = settlement_id
	if not role.is_empty():
		filter["role"] = role
	# Public workers can visit stalls as customers, but should not treat a
	# customer position as their work station during the work phase.
	if act == "work" and job != JOBS.find("Merchant"):
		filter["exclude_types"] = ["market_stall"]
		filter["job_required"] = true
	if act == "work" and job == JOBS.find("Guard"):
		filter["tags"] = ["guard"]
	# Most schedule-goal refreshes ask for the same reservation again. Reuse it
	# directly rather than scanning this settlement's complete activity list.
	var current := held_by(person)
	if current.size() >= 2:
		var spot_id := int(current[0])
		var slot_id := int(current[1])
		if spot_id >= 0 and spot_id < spots.size():
			var sp: Dictionary = spots[spot_id]
			var t: Dictionary = types[sp["type"]]
			var slots: Array = t["slots"]
			var within_range := (sp["xform"] as Transform3D).origin.distance_to(center) <= radius
			var same_settlement := (not filter.has("settlement")
				or int(sp.get("settlement", -1)) == int(filter["settlement"]))
			if (within_range and same_settlement and _matches(String(sp["type"]), t, filter)
					and slot_id >= 0 and slot_id < slots.size()
					and _slot_matches(slots[slot_id], filter)):
				var held_target := approach_point(spot_id, slot_id)
				return Vector2(held_target.x, held_target.z)
	var pick := find(center, filter, radius, person)
	if pick.is_empty():
		return Vector2.INF
	claim(pick[0], pick[1], person)
	var p := approach_point(pick[0], pick[1])
	return Vector2(p.x, p.z)


# ================================================================ schema v2: defaults and accessors (all optional keys)

## Slot value with a type-level fallback: a key in the slot wins, then the type, then `default`.
static func _slot_or_type(t: Dictionary, slot: int, key: String, default: Variant) -> Variant:
	var slots: Array = t.get("slots", [])
	if slot >= 0 and slot < slots.size() and (slots[slot] as Dictionary).has(key):
		return slots[slot][key]
	return t.get(key, default)


static func occupancy_max(t: Dictionary) -> int:
	var o: Dictionary = t.get("occupancy", {})
	return maxi(1, int(o.get("max", (t.get("slots", []) as Array).size())))


static func watchers_max(t: Dictionary) -> int:
	return maxi(0, int((t.get("occupancy", {}) as Dictionary).get("watchers", 0)))


static func watch_ring(t: Dictionary) -> float:
	return float((t.get("occupancy", {}) as Dictionary).get("watch_ring", DEFAULT_WATCH_RING))


static func needs_of(t: Dictionary) -> Dictionary:
	return t.get("needs", {})


static func clip_tags_of(t: Dictionary) -> Dictionary:
	return t.get("clip_tags", {})


static func ik_targets_of(t: Dictionary) -> Dictionary:
	return t.get("ik_targets", {})


static func ik_of(t: Dictionary, slot: int) -> Array:
	return _slot_or_type(t, slot, "ik", [])


## O1: how well a type serves the wanted needs {need: urgency}: sum(urgency * type weight). 0 = serves none.
static func need_match(t: Dictionary, wanted: Dictionary) -> float:
	var have: Dictionary = t.get("needs", {})
	if have.is_empty():
		return 0.0
	var sum := 0.0
	for n in wanted:
		if have.has(n):
			sum += float(wanted[n]) * float(have[n])
	return sum


## O2: half-angle (degrees) of the arrival arc around approach_dir. Default 180 = from anywhere (v1).
static func arc_of(t: Dictionary, slot: int) -> float:
	return clampf(float(_slot_or_type(t, slot, "approach_arc", DEFAULT_ARC)), 1.0, 180.0)


## Enter clip for a side ("front"/"side"/"back"): `spec` is a string (one clip for every side) or
## {front, side, back}. O3: the side's clip, else the front clip, else `fallback` (the type's single enter clip).
static func resolve_enter(spec: Variant, side: String, fallback := "") -> String:
	if spec is Dictionary:
		var d: Dictionary = spec
		if String(d.get(side, "")) != "":
			return String(d[side])
		if String(d.get("front", "")) != "":
			return String(d["front"])
		return fallback
	if spec is String and spec != "":
		return spec
	return fallback


## O3: which side of the slot someone arrives from. `bearing` = angle in degrees between the arrival direction
## (slot -> body, XZ) and the approach direction.
static func classify_side(bearing_deg: float) -> String:
	var a := absf(bearing_deg)
	if a <= FRONT_HALF:
		return "front"
	return "side" if a <= SIDE_HALF else "back"


## Signed angle in degrees from XZ direction `a` to XZ direction `b`, in the sense of Vector3.rotated(Vector3.UP, +angle):
## a.rotated(UP, deg_to_rad(yaw_between(a, b))) points along b.
static func yaw_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(atan2(a.z * b.x - a.x * b.z, a.x * b.x + a.z * b.z))


## O2: where to aim the last leg so the arrival bearing lies inside the arc. `from` is the body, `centre` the
## stand point, `dir` the world approach direction (XZ unit), `half_arc` degrees, `dist` the approach distance.
## Bearing already inside the arc: arrive along it (no sideways shuffle); outside: clamp onto the arc edge.
static func arrival_point(from: Vector3, centre: Vector3, dir: Vector3, half_arc: float, dist: float) -> Vector3:
	var to_body := Vector3(from.x - centre.x, 0.0, from.z - centre.z)
	if to_body.length_squared() < 0.0001:
		to_body = dir
	var ang := yaw_between(dir, to_body)
	var lim := maxf(half_arc - ARC_MARGIN, half_arc * 0.5)
	var clamped := clampf(ang, -lim, lim)
	var d := dir.rotated(Vector3.UP, deg_to_rad(clamped))
	return centre + d * dist


## O2: walk speed multiplier over the last SLOW_DIST metres.
static func arrival_speed(dist_left: float) -> float:
	return clampf(dist_left / SLOW_DIST, SLOW_MIN, 1.0)


## World approach direction (XZ unit) of a slot: the declared object-frame approach_dir, else straight back out
## from the stand point (the v1 approach line).
func approach_dir_world(spot: int, slot: int) -> Vector3:
	var sp: Dictionary = spots[spot]
	var t: Dictionary = types[sp["type"]]
	var declared: Variant = _slot_or_type(t, slot, "approach_dir", null)
	var v: Vector3
	if declared is Array and (declared as Array).size() == 3:
		var a: Array = declared
		v = (sp["xform"] as Transform3D).basis * Vector3(float(a[0]), 0.0, float(a[2]))
	else:
		v = -stand_xform(spot, slot).basis.z
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.BACK


# ================================================================ O5 watchers

## Occupied to the type's limit: nobody else can use it, so extra people may stand and watch instead.
func is_full(spot: int) -> bool:
	return occupancy(spot) >= occupancy_max(types[spots[spot]["type"]])


## Nearest full spot matching `filter` (same keys as find) with a free watcher slot: [spot, watcher_index], or [].
func find_watch(pos: Vector3, filter: Dictionary, radius := 30.0, person := -1) -> Array:
	var best := []
	var best_d := INF
	var r := int(ceil(radius / CELL))
	var c0 := _cell(pos)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id: int in _grid.get(c0 + Vector2i(dx, dz), []):
				var sp: Dictionary = spots[id]
				var t: Dictionary = types[sp["type"]]
				if watchers_max(t) == 0 or not _matches(sp["type"], t, filter) or not is_full(id):
					continue
				var d := (sp["xform"] as Transform3D).origin.distance_to(pos)
				if d > radius or d >= best_d:
					continue
				var w: Array = sp["watchers"]
				var mine := w.find(person)
				var free := mine if mine >= 0 else w.find(-1)
				if free >= 0:
					best_d = d
					best = [id, free]
	return best


## Take watcher slot `idx` of `spot`. False when the spot is not full, the slot is out of range or taken by someone else.
func claim_watch(spot: int, idx: int, person: int) -> bool:
	if spot < 0 or spot >= spots.size() or not is_full(spot):
		return false
	var w: Array = spots[spot]["watchers"]
	if idx < 0 or idx >= w.size() or (w[idx] != -1 and w[idx] != person):
		return false
	if w[idx] == person:
		return true
	release_watch(person)
	w[idx] = person
	_watching[person] = [spot, idx]
	return true


func release_watch(person: int) -> void:
	var cur: Array = _watching.get(person, [])
	if cur.is_empty():
		return
	var w: Array = spots[cur[0]]["watchers"]
	if cur[1] < w.size() and w[cur[1]] == person:
		w[cur[1]] = -1
	_watching.erase(person)


func watching(person: int) -> Array:
	return _watching.get(person, [])


## Watcher points are spread on the ring (metres from the object) around the front slot's approach direction.
func watch_point(spot: int, idx: int) -> Vector3:
	var sp: Dictionary = spots[spot]
	var t: Dictionary = types[sp["type"]]
	var n := watchers_max(t)
	var centre: Vector3 = (sp["xform"] as Transform3D).origin
	var dir := approach_dir_world(spot, 0)
	var off := (float(idx) - float(n - 1) * 0.5) * WATCH_SPREAD
	return centre + dir.rotated(Vector3.UP, off) * watch_ring(t)


## Yaw (radians, Godot +Z forward) that makes a watcher at watch_point look at the object.
func watch_face(spot: int, idx: int) -> float:
	var to := (spots[spot]["xform"] as Transform3D).origin - watch_point(spot, idx)
	return atan2(to.x, to.z)


# ================================================================ validation

## Check a `types` dictionary against the schema (v1 keys and the optional v2 keys). Returns one message per problem;
## empty = valid. Pure data, no nodes.
static func validate(types: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for name in types:
		var t: Variant = types[name]
		if not (t is Dictionary):
			errs.append("%s: type must be an object" % name)
			continue
		_validate_type(String(name), t, errs)
	return errs


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _is_vec3(v: Variant) -> bool:
	if not (v is Array) or (v as Array).size() != 3:
		return false
	for x in v:
		if not _is_num(x):
			return false
	return true


static func _validate_enter(name: String, where: String, e: Variant, errs: Array[String]) -> void:
	if e is String:
		return
	if not (e is Dictionary):
		errs.append("%s: %s enter must be a string or {front, side, back}" % [name, where])
		return
	for k in e:
		if not ENTER_SIDES.has(k):
			errs.append("%s: %s enter has unknown side '%s'" % [name, where, k])
		elif not (e[k] is String):
			errs.append("%s: %s enter.%s must be a clip name" % [name, where, k])


static func _validate_type(name: String, t: Dictionary, errs: Array[String]) -> void:
	var slots: Variant = t.get("slots")
	if not (slots is Array) or (slots as Array).is_empty():
		errs.append("%s: slots must be a non-empty array" % name)
		slots = []
	var targets: Variant = t.get("ik_targets", {})
	if not (targets is Dictionary):
		errs.append("%s: ik_targets must be an object" % name)
		targets = {}
	else:
		for k in targets:
			if not _is_vec3(targets[k]):
				errs.append("%s: ik_targets.%s must be [x, y, z]" % [name, k])
	if t.has("enter"):
		_validate_enter(name, "type", t["enter"], errs)
	var act: Variant = t.get("activity", {})
	if act is Dictionary and (act as Dictionary).has("enter"):
		_validate_enter(name, "activity", act["enter"], errs)
	for i in (slots as Array).size():
		var sl: Variant = slots[i]
		var w := "slot %d" % i
		if not (sl is Dictionary):
			errs.append("%s: %s must be an object" % [name, w])
			continue
		var st: Variant = sl.get("stand")
		if not ((st is String and st == "auto") or _is_vec3(st)):
			errs.append("%s: %s stand must be \"auto\" or [x, y, z]" % [name, w])
		if not _is_num(sl.get("face", 0.0)):
			errs.append("%s: %s face must be a number" % [name, w])
		if sl.has("enter"):
			_validate_enter(name, w, sl["enter"], errs)
		_validate_approach(name, w, sl, errs)
		_validate_ik(name, w, sl.get("ik", []), targets, errs)
	_validate_approach(name, "type", t, errs)
	_validate_ik(name, "type", t.get("ik", []), targets, errs)
	if t.has("occupancy"):
		var o: Variant = t["occupancy"]
		if not (o is Dictionary):
			errs.append("%s: occupancy must be an object" % name)
		else:
			for k in o:
				if not ["max", "watchers", "watch_ring"].has(k):
					errs.append("%s: occupancy has unknown key '%s'" % [name, k])
			if o.has("max") and not (_is_num(o["max"]) and int(o["max"]) >= 1 and int(o["max"]) <= (slots as Array).size()):
				errs.append("%s: occupancy.max must be 1..slot count (%d)" % [name, (slots as Array).size()])
			if o.has("watchers") and not (_is_num(o["watchers"]) and int(o["watchers"]) >= 0 and int(o["watchers"]) <= 8):
				errs.append("%s: occupancy.watchers must be 0..8" % name)
			if o.has("watch_ring") and not (_is_num(o["watch_ring"]) and float(o["watch_ring"]) > 0.5):
				errs.append("%s: occupancy.watch_ring must be > 0.5 m" % name)
	if t.has("needs"):
		var nd: Variant = t["needs"]
		if not (nd is Dictionary):
			errs.append("%s: needs must be an object" % name)
		else:
			for k in nd:
				if not NEEDS.has(k):
					errs.append("%s: unknown need '%s'" % [name, k])
				elif not (_is_num(nd[k]) and float(nd[k]) > 0.0 and float(nd[k]) <= 2.0):
					errs.append("%s: needs.%s must be a weight in (0, 2]" % [name, k])
	if t.has("clip_tags"):
		var ct: Variant = t["clip_tags"]
		if not (ct is Dictionary):
			errs.append("%s: clip_tags must be an object" % name)
		else:
			for k in ct:
				if not (ct[k] is String):
					errs.append("%s: clip_tags.%s must be a tag string" % [name, k])


static func _validate_approach(name: String, where: String, d: Dictionary, errs: Array[String]) -> void:
	if d.has("approach_dir"):
		var v: Variant = d["approach_dir"]
		if not _is_vec3(v) or (absf(float(v[0])) + absf(float(v[2]))) < 0.001:
			errs.append("%s: %s approach_dir must be [x, y, z] with a horizontal part" % [name, where])
	if d.has("approach_arc"):
		var a: Variant = d["approach_arc"]
		if not (_is_num(a) and float(a) > 0.0 and float(a) <= 180.0):
			errs.append("%s: %s approach_arc must be a half-angle in (0, 180] degrees" % [name, where])


static func _validate_ik(name: String, where: String, ik: Variant, targets: Dictionary, errs: Array[String]) -> void:
	if not (ik is Array):
		errs.append("%s: %s ik must be an array" % [name, where])
		return
	for j in (ik as Array).size():
		var e: Variant = ik[j]
		if not (e is Dictionary):
			errs.append("%s: %s ik[%d] must be an object" % [name, where, j])
			continue
		if not IK_LIMBS.has(e.get("limb", "")):
			errs.append("%s: %s ik[%d] limb must be one of %s" % [name, where, j, IK_LIMBS])
		if not targets.has(e.get("target", "")):
			errs.append("%s: %s ik[%d] target '%s' is not in ik_targets" % [name, where, j, e.get("target", "")])
		if not (_is_num(e.get("weight", 1.0)) and float(e.get("weight", 1.0)) >= 0.0 and float(e.get("weight", 1.0)) <= 1.0):
			errs.append("%s: %s ik[%d] weight must be 0..1" % [name, where, j])
		var ph: Variant = e.get("phase", "loop")
		var ok: bool = (ph is String and ph == "loop") or (ph is Array and (ph as Array).size() == 2 and _is_num(ph[0]) and _is_num(ph[1]) and float(ph[0]) >= 0.0 and float(ph[1]) <= 1.0 and float(ph[0]) < float(ph[1]))
		if not ok:
			errs.append("%s: %s ik[%d] phase must be \"loop\" or [from, to] within 0..1" % [name, where, j])


func session(person: int, spot: int, slot: int, seed_i := -1) -> Session:
	return Session.new(self, person, spot, slot, seed_i if seed_i >= 0 else person)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## One person using one slot, as a small state machine the body's controller steps each frame:
##   var out := s.update(delta, body_pos, clip_done)
##   out.move_to (Vector3 or null: walk there at normal pace), out.face (yaw to turn to), out.clip / out.restart
##   (play it; restart = play from the start even if it is the current clip), out.props (for LifeProps.Holder),
##   out.phase (APPROACH ALIGN ENTER LOOP BETWEEN EXIT DONE), out.event (activity event to emit, once).
## s.interrupt() plays the exit clip and releases the slot at DONE (NPC_ANIMATION_TRANSITION_DESIGN: switch-out).
class Session:
	enum { APPROACH, ALIGN, ENTER, LOOP, BETWEEN, EXIT, DONE }
	var so: SmartObjects
	var person := -1
	var spot := -1
	var slot := 0
	var phase := APPROACH
	var completed_naturally := false
	var act: Dictionary
	var time_left := 30.0
	var cycles_left := 2
	var clip := ""
	var _restart := false
	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _event_sent := false
	var _claim_token := -1
	## O3: the side ("front" / "side" / "back") the person arrived from, set when the approach ends.
	var side := "front"
	var _arrive := Vector3.ZERO     # O2: latched arrival waypoint when the slot declares an approach_arc
	var _arrive_set := false
	# Keep activity timing on the original stable RNG. Visual clip variation gets
	# its own day/time-scoped bags so later visits get an independent take order,
	# while same-time reloads stay stable. A random permutation may still recur.
	var _variant_day := 1
	var _variant_time_bucket := 0
	var _variant_seed_person := -1
	var _variant_bags: Dictionary = {}
	var _variant_bag_cycles: Dictionary = {}
	var _last_variant: Dictionary = {}

	func _init(o: SmartObjects, p: int, sp: int, sl: int, sd: int) -> void:
		so = o
		person = p
		spot = sp
		slot = sl
		_claim_token = o.claim_token(p)
		_rng.seed = hash(sd * 7919 + sp)
		_variant_day = int(WorldSim.day)
		_variant_time_bucket = int(floor(float(WorldSim.time_of_day) * 60.0))
		_variant_seed_person = sd
		act = o.activity(sp, sl)
		var dur: Array = act.get("duration", [30, 60])
		time_left = _rng.randf_range(float(dur[0]), float(dur[1]))
		_new_cycles()

	static func _offset(clip: String, key: String) -> Vector3:
		if clip == "":
			return Vector3.ZERO
		var a: Variant = LifeLibrary.info(clip).get(key)
		return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() == 3 else Vector3.ZERO

	func _new_cycles() -> void:
		var c: Array = act.get("cycles", [2, 4])
		cycles_left = _rng.randi_range(int(c[0]), int(c[1]))

	func interrupt() -> void:
		completed_naturally = false
		if phase in [ENTER, LOOP, BETWEEN]:
			_go(EXIT if act.get("exit", "") != "" else DONE)
		elif phase in [APPROACH, ALIGN]:
			_go(DONE)


	## Immediate teardown path for a body that is being removed and cannot play
	## its exit animation. Normal gameplay interruptions should use interrupt().
	func cancel_now() -> void:
		completed_naturally = false
		_go(DONE)

	func stand() -> Transform3D:
		return so.stand_xform(spot, slot)

	## O3: the enter clip for the arrival side. The slot's `enter` (string or {front, side, back}) overrides the
	## activity's; the type's single enter clip is the fallback.
	func enter_clip() -> String:
		var single: Variant = act.get("enter", "")
		var sl: Dictionary = so.types[so.spots[spot]["type"]]["slots"][slot]
		return SmartObjects.resolve_enter(sl.get("enter", single), side, single if single is String else "")

	func _arrive_side(body: Vector3, sx: Transform3D) -> void:
		var to_body := Vector3(body.x - sx.origin.x, 0.0, body.z - sx.origin.z)
		if to_body.length_squared() > 0.0001:
			side = SmartObjects.classify_side(SmartObjects.yaw_between(so.approach_dir_world(spot, slot), to_body))

	## Seated slots ("seat" in the slot) are laid out for a pelvis SEAT_REF behind the root (Life_Rest_Sit_Bench).
	## Sit clips carry their own `seat_back` (sidecar); the root moves along the character's forward so every clip's
	## pelvis lands on the same seat point instead of floating in front of / behind the bench.
	func seated(sx: Transform3D, c: String) -> Transform3D:
		var sl: Dictionary = so.types[so.spots[spot]["type"]]["slots"][slot]
		if not sl.has("seat") or c == "":
			return sx
		var info := LifeLibrary.info(c)
		if not info.has("seat_back"):
			return sx
		var fwd := sx.basis.z.normalized()
		return Transform3D(sx.basis, sx.origin + fwd * (float(info["seat_back"]) - SEAT_REF))

	func _go(p: int) -> void:
		phase = p
		_t = 0.0
		_restart = true
		match p:
			ENTER:
				clip = enter_clip()
				if clip == "":
					_go(LOOP)
			LOOP:
				clip = _next_variant("loop", act.get("loop", ["Idle"]))
			BETWEEN:
				var b: Array = act.get("between", [])
				clip = _next_variant("between", b)
			EXIT:
				clip = act.get("exit", "")
				if clip == "":
					_go(DONE)
			DONE:
				so.release_claim(person, spot, slot, _claim_token)

	func _variant_seed(kind: String, day: int, cycle: int) -> int:
		var material := "%d|%d|%d|%d|%d|%d|%d|%s|%d" % [
			WorldSim.SEED, day, _variant_time_bucket, person, spot, slot, _variant_seed_person, kind, cycle]
		var result := hash(material)
		return 1 if result == 0 else result

	func _shuffled_variants(choices: Array, kind: String, day: int, cycle: int) -> Array:
		var bag: Array = []
		for choice in choices:
			if not bag.has(choice):
				bag.append(choice)
		var rng := RandomNumberGenerator.new()
		rng.seed = _variant_seed(kind, day, cycle)
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
		return bag

	func _next_variant(kind: String, source: Array) -> String:
		if source.is_empty():
			return ""
		var bag: Array = _variant_bags.get(kind, [])
		if bag.is_empty():
			var cycle := int(_variant_bag_cycles.get(kind, 0))
			bag = _shuffled_variants(source, kind, _variant_day, cycle)
			var avoid := String(_last_variant.get(kind, ""))
			if cycle == 0 and _variant_day > 1:
				var previous := _shuffled_variants(source, kind, _variant_day - 1, 0)
				if not previous.is_empty():
					avoid = String(previous[0])
			if bag.size() > 1 and String(bag[0]) == avoid:
				for i in range(1, bag.size()):
					if String(bag[i]) != avoid:
						var tmp: Variant = bag[0]
						bag[0] = bag[i]
						bag[i] = tmp
						break
			_variant_bag_cycles[kind] = cycle + 1
		var selected := String(bag.pop_front())
		_variant_bags[kind] = bag
		_last_variant[kind] = selected
		return selected

	func update(delta: float, body: Vector3, clip_done: bool) -> Dictionary:
		# A replacement schedule, despawn, or LOD handoff may revoke this claim.
		# Stop producing clips/events immediately, without touching a newer lease.
		if phase != DONE and not so.owns_claim(person, spot, slot, _claim_token):
			completed_naturally = false
			phase = DONE
			clip = ""
			return {"phase": DONE, "move_to": null, "face": NAN, "clip": "",
				"restart": false, "props": [], "event": null}
		_t += delta
		var phase_in := phase
		var out := {"phase": phase, "move_to": null, "face": NAN, "clip": clip, "restart": false, "props": [], "event": null}
		var sx := stand()
		# seated clips: align the pelvis on the seat (ENTER aligns on the clip it ends in: the first loop clip)
		if phase in [ENTER, LOOP, BETWEEN, EXIT] or phase == ALIGN:
			var ref_clip: String = clip if phase in [LOOP, BETWEEN] else (enter_clip() if phase in [ALIGN, ENTER] else String(act.get("exit", clip)))
			sx = seated(sx, ref_clip)
		match phase:
			APPROACH:
				var ap := so.approach_point(spot, slot)
				var tt: Dictionary = so.types[so.spots[spot]["type"]]
				var arc := SmartObjects.arc_of(tt, slot)
				if arc < SmartObjects.DEFAULT_ARC:
					# O2: arrive inside the declared arc, latched on the first step so the leg does not wander.
					if not _arrive_set:
						_arrive_set = true
						_arrive = SmartObjects.arrival_point(body, sx.origin, so.approach_dir_world(spot, slot), arc, float(tt.get("approach", 1.0)))
					ap = _arrive
				var left := Vector2(body.x - ap.x, body.z - ap.z).length()
				if left < (SmartObjects.ARC_REACH if arc < SmartObjects.DEFAULT_ARC else 0.35) or Vector2(body.x - sx.origin.x, body.z - sx.origin.z).length() < 0.5:
					_arrive_side(body, sx)
					_go(ALIGN)
				else:
					out["move_to"] = ap
					out["speed_scale"] = SmartObjects.arrival_speed(left)
					out["clip"] = ""
			ALIGN:
				# Root-motion enters (sidecar "entry_offset", character frame: +Z forward): the clip starts with the body
				# that far from its root, so stand there; the root jumps onto the slot when the enter starts (no visible move).
				var entry := sx.origin + sx.basis * _offset(enter_clip(), "entry_offset")
				out["move_to"] = entry
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["clip"] = ""
				var alignment_error := Vector2(body.x - entry.x, body.z - entry.z).length()
				if alignment_error < 0.06:
					_go(ENTER)
				elif _t > 1.5:
					# Never play a contact animation from a visibly wrong position.
					_go(DONE)
			ENTER:
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["snap"] = sx
				if clip_done and _t > 0.1:
					_go(LOOP)
			LOOP:
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["snap"] = sx
				time_left -= delta
				if clip_done and _t > 0.1:
					cycles_left -= 1
					var d := float(act.get("drift", 0.0))
					if d > 0.0:
						so.spots[spot]["drift"] = fposmod(float(so.spots[spot]["drift"]) + d, 6.0)
					if time_left <= 0.0:
						completed_naturally = true
						_go(EXIT if act.get("exit", "") != "" else DONE)
					elif cycles_left <= 0 and not (act.get("between", []) as Array).is_empty():
						_go(BETWEEN)
					else:
						_go(LOOP)
			BETWEEN:
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["snap"] = sx
				if clip_done and _t > 0.1:
					_new_cycles()
					_go(LOOP)
			EXIT:
				out["snap"] = sx
				if clip_done and _t > 0.1:
					_go(DONE)
					# root-motion exits (sidecar "exit_offset"): the clip ends with the body away from the root, move it there
					var xo := _offset(String(act.get("exit", "")), "exit_offset")
					if xo != Vector3.ZERO:
						out["exit_to"] = sx.origin + sx.basis * xo
					# turning exits (sidecar "exit_yaw", degrees about +Y): the clip ends facing away from the slot; turn the root
					# with it so the next clip does not snap the body back round
					var xy: Variant = LifeLibrary.info(String(act.get("exit", ""))).get("exit_yaw")
					if xy != null:
						out["face"] = atan2(sx.basis.z.x, sx.basis.z.z) + deg_to_rad(float(xy))
		if phase != phase_in and phase in [ENTER, EXIT] and clip != "" and (LifeLibrary.info(clip).has("entry_offset") or LifeLibrary.info(clip).has("seat_back")):
			# Cut into an enter / exit: the clip may start with the body away from its root (entry_offset, seat_back);
			# place the root for THIS clip in the same frame the clip starts (blend_in 0 on those clips): no pop.
			out["snap"] = seated(stand(), clip)
			out["snap_hard"] = true
		out["phase"] = phase
		out["clip"] = clip if phase in [ENTER, LOOP, BETWEEN, EXIT] else ""
		out["restart"] = _restart
		_restart = false
		if phase in [ENTER, LOOP, BETWEEN, EXIT]:
			out["props"] = LifeLibrary.info(clip).get("props", [])
			var ev = so.types[so.spots[spot]["type"]].get("event")
			if ev and phase == LOOP and not _event_sent:
				_event_sent = true
				out["event"] = ev
		return out
