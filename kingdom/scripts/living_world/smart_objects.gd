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
## Schema v2 (NPC_MOTION_RULES 3.4): every key is optional and resolves slot -> type -> default.
const SIDES := ["front", "side", "back"]
const DEFAULT_ARC := 180.0        # degrees; 180 = no arrival constraint (the old straight approach)
const ARC_MARGIN := 0.9           # the arrival point sits this fraction inside the arc edge
const FRONT_HALF := 35.0          # arrival within this many degrees of approach_dir = "front"
const BACK_FROM := 145.0          # arrival beyond this = "back", between = "side"
const SLOW_DIST := 1.2            # metres over which the last approach slows down
const SLOW_MIN := 0.35
const DEFAULT_WATCH_RING := 2.5
const WATCH_STEP := 40.0          # degrees between neighbouring watcher slots on the ring
const IK_LIMBS := ["hand_l", "hand_r", "foot_l", "foot_r", "head"]
const OCC_KEYS := ["max", "watchers", "watch_ring"]

var types: Dictionary = {}
var building_spots: Dictionary = {}
var spots: Array = []               # Array[Dictionary]: {id, identity, has_stable_identity, type, xform, settlement, holders, drift}
var _grid: Dictionary = {}          # Vector2i -> Array[int]
var _settlement_spots: Dictionary = {} # settlement id -> Array[int], for bounded local schedule queries
var _held: Dictionary = {}          # person -> [spot, slot, claim_token]
var _watching: Dictionary = {}      # person -> [spot, watcher index]
var _need_index: Dictionary = {}    # need -> Array of type names, best weight first (lazy, see types_for_need)
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
	spots.append({"id": id, "identity": stable_identity if not stable_identity.is_empty() else "runtime/%d" % id,
		"has_stable_identity": not stable_identity.is_empty(), "type": type, "xform": xform,
		"settlement": settlement, "holders": holders, "drift": 0.0, "watchers": []})
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
func find(pos: Vector3, filter: Dictionary, radius := 60.0, person := -1, avoid := PackedVector2Array(), avoid_r := 0.0) -> Array:
	var best := []
	var best_s := INF
	var needs: Dictionary = filter.get("needs", {})
	var need_mode := not needs.is_empty()
	var hour := float(filter.get("hour", -1.0))
	var candidate_ids: Array = []
	if filter.has("settlement"):
		candidate_ids = _settlement_spots.get(int(filter["settlement"]), [])
	else:
		var r := int(ceil(radius / CELL))
		var c0 := _cell(pos)
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				candidate_ids.append_array(_grid.get(c0 + Vector2i(dx, dz), []))
	for id: int in candidate_ids:
		var sp: Dictionary = spots[id]
		var t: Dictionary = types[sp["type"]]
		if not _matches(sp["type"], t, filter):
			continue
		var origin: Vector3 = (sp["xform"] as Transform3D).origin
		var d := origin.distance_to(pos)
		if d > radius:
			continue
		if avoid_r > 0.0 and _near_any(origin, avoid, avoid_r):
			continue
		var slots: Array = t["slots"]
		var occ_n := occupancy(id)
		var occ_max := max_users(id)
		var spot_full := occ_n >= occ_max
		var need_m := need_match(t, needs) if need_mode else 0.0
		for k in slots.size():
			# A data-tier resident often asks for its schedule target again on
			# every coarse simulation step. Keep its existing slot eligible so
			# refreshing the same goal does not make it churn through the queue.
			if sp["holders"][k] != -1 and sp["holders"][k] != person:
				continue
			if spot_full and sp["holders"][k] != person:
				continue   # occupancy.max reached (schema v2); defaults to the slot count, so old data never trips it
			if not _slot_matches(slots[k], filter):
				continue
			var score := d + float(absi(hash(person * 7 + id * 131 + k)) % 100) * 0.03
			if need_mode:
				# O1: the highest utility wins; the tiny hash jitter only breaks exact ties, deterministically.
				var others: int = occ_n - (1 if sp["holders"][k] == person else 0)
				score = -_utility(sp, t, need_m, others, occ_max, pos, hour) + float(absi(hash(person * 7 + id * 131 + k)) % 100) * 0.00001
			if sp["holders"][k] != person and id == int(filter.get("recent_spot", -1)):
				# Soft preference only: a sole station remains eligible; owned refreshes stay stable.
				score += clampf(float(filter.get("recent_penalty", 0.0)), 0.0, 10.0) * (0.05 if need_mode else 1.0)
			if sp["holders"][k] == person:
				score -= 0.05 if need_mode else 1.0  # small hysteresis keeps a valid activity stable
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
	if f.has("needs") and not (f["needs"] as Dictionary).is_empty():
		# O1: only types that satisfy one of the asked needs; disabled types never.
		if t.has("_disabled") or need_match(t, f["needs"]) <= 0.0:
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
	var current: Array = _held.get(person, [])
	if current.size() >= 3 and int(current[0]) == spot and int(current[1]) == slot and h[slot] == person:
		return true  # idempotent refresh: preserve the Session's lease token
	if h[slot] != person and occupancy(spot) >= max_users(spot) and not (current.size() >= 2 and int(current[0]) == spot):
		return false  # occupancy.max (schema v2): the spot is full although a slot is free
	release(person)
	_claim_serial += 1
	h[slot] = person
	_held[person] = [spot, slot, _claim_serial]
	return true


func release(person: int) -> void:
	release_watch(person)
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


## ---- schema v2 accessors (every key optional: slot -> type -> default) ----------------------------------------

static func _opt(t: Dictionary, sl: Dictionary, key: String, def: Variant) -> Variant:
	if sl.has(key):
		return sl[key]
	return t.get(key, def)


## Clip name out of a string-or-{front, side, back} value. A missing side falls back to front, then "".
static func pick_clip(v: Variant, side: String) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	if typeof(v) == TYPE_DICTIONARY:
		var s: Variant = v.get(side, "")
		if typeof(s) == TYPE_STRING and s != "":
			return s
		var f: Variant = v.get("front", "")
		return f if typeof(f) == TYPE_STRING else ""
	return ""


func enter_clip(spot: int, slot: int, side := "front") -> String:
	return _phase_clip(spot, slot, "enter", side)


func exit_clip(spot: int, slot: int, side := "front") -> String:
	return _phase_clip(spot, slot, "exit", side)


func _phase_clip(spot: int, slot: int, key: String, side: String) -> String:
	var sl: Dictionary = types[spots[spot]["type"]]["slots"][slot]
	if sl.has(key):
		var c := pick_clip(sl[key], side)
		if c != "":
			return c
	return pick_clip(activity(spot, slot).get(key, ""), side)


## Object-frame direction (y = 0, unit) from the stand point toward where the person comes from.
## Default: straight back out along the slot's facing, i.e. exactly the old approach_point direction.
func approach_dir_local(spot: int, slot: int) -> Vector3:
	var t: Dictionary = types[spots[spot]["type"]]
	var sl: Dictionary = t["slots"][slot]
	var v: Variant = _opt(t, sl, "approach_dir", null)
	if v is Array and (v as Array).size() == 3:
		var d := Vector3(float(v[0]), 0.0, float(v[2]))
		if d.length_squared() > 0.000001:
			return d.normalized()
	return -(Basis(Vector3.UP, deg_to_rad(float(sl.get("face", 180.0)))) * Vector3(0, 0, 1))


## World-space approach axis of a slot (unit, y = 0).
func approach_axis(spot: int, slot: int) -> Vector3:
	var w: Vector3 = (spots[spot]["xform"] as Transform3D).basis * approach_dir_local(spot, slot)
	w.y = 0.0
	return w.normalized()


## Half-width in degrees of the arrival arc around approach_axis. 180 (default) = unconstrained.
func approach_arc(spot: int, slot: int) -> float:
	var t: Dictionary = types[spots[spot]["type"]]
	return clampf(float(_opt(t, t["slots"][slot], "approach_arc", DEFAULT_ARC)), 1.0, DEFAULT_ARC)


## True when the data declares an arc < 180: only then does the Session steer its arrival (O2).
func declares_arc(spot: int, slot: int) -> bool:
	return approach_arc(spot, slot) < DEFAULT_ARC


## Direction `dir` pulled onto the arc edge when it falls outside `arc` degrees of `axis` (both unit, y = 0).
static func clamp_to_arc(axis: Vector3, dir: Vector3, arc_deg: float) -> Vector3:
	var a := axis.signed_angle_to(dir, Vector3.UP)
	var lim := deg_to_rad(arc_deg)
	if absf(a) <= lim:
		return dir
	return axis.rotated(Vector3.UP, signf(a) * lim)


## Where to walk before aligning. Without a declared arc this is approach_point (old behaviour); with one it is the
## point at the same distance from the stand point, in the direction of `from` pulled inside the arc (O2).
func arrival_point(spot: int, slot: int, from: Vector3) -> Vector3:
	if not declares_arc(spot, slot):
		return approach_point(spot, slot)
	var sx := stand_xform(spot, slot)
	var dist := float(types[spots[spot]["type"]].get("approach", 1.0))
	var axis := approach_axis(spot, slot)
	var v := Vector3(from.x - sx.origin.x, 0.0, from.z - sx.origin.z)
	var dir := axis
	if v.length_squared() > 0.0001:
		dir = clamp_to_arc(axis, v.normalized(), approach_arc(spot, slot) * ARC_MARGIN)
	return sx.origin + dir * dist


## True when `body` stands inside the slot's arrival arc.
func in_arc(spot: int, slot: int, body: Vector3) -> bool:
	var sx := stand_xform(spot, slot)
	var v := Vector3(body.x - sx.origin.x, 0.0, body.z - sx.origin.z)
	if v.length_squared() < 0.0001:
		return true
	return absf(rad_to_deg(approach_axis(spot, slot).signed_angle_to(v.normalized(), Vector3.UP))) <= approach_arc(spot, slot) + 0.01


## O3: "front" / "side" / "back" for a person arriving from `from`, relative to the slot's approach axis.
func classify_side(spot: int, slot: int, from: Vector3) -> String:
	var sx := stand_xform(spot, slot)
	var v := Vector3(from.x - sx.origin.x, 0.0, from.z - sx.origin.z)
	if v.length_squared() < 0.0001:
		return "front"
	var a := absf(rad_to_deg(approach_axis(spot, slot).signed_angle_to(v.normalized(), Vector3.UP)))
	if a <= FRONT_HALF:
		return "front"
	return "back" if a >= BACK_FROM else "side"


## Hand/foot IK requests of a slot [{limb, target, weight, phase}] (O4 data only; prop_ik.gd consumes it).
func ik_list(spot: int, slot: int) -> Array:
	var t: Dictionary = types[spots[spot]["type"]]
	var v: Variant = _opt(t, t["slots"][slot], "ik", [])
	return v if v is Array else []


## World position of a named ik target of the spot, or Vector3.INF when the type does not declare it.
func ik_target_world(spot: int, target: String) -> Vector3:
	var tg: Dictionary = types[spots[spot]["type"]].get("ik_targets", {})
	var a: Variant = tg.get(target)
	if not (a is Array and (a as Array).size() == 3):
		return Vector3.INF
	return (spots[spot]["xform"] as Transform3D) * Vector3(float(a[0]), float(a[1]), float(a[2]))


func clip_tag(spot: int, slot: int, phase: String) -> String:
	var t: Dictionary = types[spots[spot]["type"]]
	var tags: Variant = _opt(t, t["slots"][slot], "clip_tags", {})
	return String(tags.get(phase, "")) if tags is Dictionary else ""


func needs_of(type: String) -> Dictionary:
	return types.get(type, {}).get("needs", {})


## occupancy {max, watchers, watch_ring}; defaults: max = slot count, no watchers.
func max_users(spot: int) -> int:
	var t: Dictionary = types[spots[spot]["type"]]
	var n := (t["slots"] as Array).size()
	var occ: Variant = t.get("occupancy")
	if occ is Dictionary and (occ as Dictionary).has("max"):
		return clampi(int(occ["max"]), 1, n)
	return n


func watch_capacity(spot: int) -> int:
	var occ: Variant = types[spots[spot]["type"]].get("occupancy")
	return maxi(0, int(occ.get("watchers", 0))) if occ is Dictionary else 0


func watch_ring(spot: int) -> float:
	var occ: Variant = types[spots[spot]["type"]].get("occupancy")
	return maxf(0.5, float(occ.get("watch_ring", DEFAULT_WATCH_RING))) if occ is Dictionary else DEFAULT_WATCH_RING


## ---- O1 need-weighted pick -------------------------------------------------------------------------------------

## How well a type satisfies a {need: urgency} request: sum of urgency * the type's need weight.
func need_match(t: Dictionary, needs: Dictionary) -> float:
	var tn: Variant = t.get("needs")
	if not tn is Dictionary:
		return 0.0
	var m := 0.0
	for n: String in needs:
		m += maxf(0.0, float(needs[n])) * float((tn as Dictionary).get(n, 0.0))
	return m


## Utility of using (spot, slot) for a need request from `pos`: need match x distance x occupancy x opening hours.
## Roughly 0..1, higher is better. `hour` < 0 skips the hours term.
func need_utility(spot: int, slot: int, needs: Dictionary, pos: Vector3, hour := -1.0, person := -1) -> float:
	var sp: Dictionary = spots[spot]
	var t: Dictionary = types[sp["type"]]
	var others := occupancy(spot) - (1 if person != -1 and (sp["holders"] as Array).has(person) else 0)
	return _utility(sp, t, need_match(t, needs), others, max_users(spot), pos, hour)


func _utility(sp: Dictionary, t: Dictionary, m: float, others: int, occ_max: int, pos: Vector3, hour: float) -> float:
	if m <= 0.0:
		return 0.0
	var d := (sp["xform"] as Transform3D).origin.distance_to(pos)
	var dist_f := 1.0 / (1.0 + d / 20.0)
	var occ_f := 1.0 - 0.5 * float(others) / float(maxi(1, occ_max))
	var hour_f := 1.0
	if hour >= 0.0 and t.has("hours"):
		var hr: Array = t["hours"]
		hour_f = clampf(0.5 + 0.5 * minf(hour - float(hr[0]), float(hr[1]) - hour), 0.5, 1.0)
	return m * dist_f * occ_f * hour_f


## Type names that satisfy `need`, strongest weight first (ties by name): the need -> type table.
func types_for_need(need: String) -> Array:
	if _need_index.is_empty():
		var by: Dictionary = {}
		for name: String in types:
			if (types[name] as Dictionary).has("_disabled"):
				continue
			var tn: Variant = types[name].get("needs")
			if tn is Dictionary:
				for n: String in tn:
					if float(tn[n]) > 0.0:
						if not by.has(n):
							by[n] = []
						(by[n] as Array).append([float(tn[n]), name])
		for n: String in by:
			(by[n] as Array).sort_custom(func(a: Array, b: Array) -> bool:
				return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
			_need_index[n] = (by[n] as Array).map(func(e: Array) -> String: return e[1])
		_need_index["_built"] = []
	return (_need_index.get(need, []) as Array).duplicate()


## ---- O5 watchers -----------------------------------------------------------------------------------------------

func watcher_count(spot: int) -> int:
	var n := 0
	for p: int in spots[spot]["watchers"]:
		if p != -1:
			n += 1
	return n


## Takes the lowest free watcher slot of a spot; returns the index, or -1 when the ring is full / the type has none.
## Idempotent for the same person; a person watches one spot at a time and a user is not also a watcher.
func claim_watch(spot: int, person: int) -> int:
	if spot < 0 or spot >= spots.size():
		return -1
	var cur: Array = _watching.get(person, [])
	if cur.size() == 2 and int(cur[0]) == spot:
		return int(cur[1])
	var cap := watch_capacity(spot)
	if cap <= 0:
		return -1
	var w: Array = spots[spot]["watchers"]
	while w.size() < cap:
		w.append(-1)
	var idx := -1
	for i in cap:
		if w[i] == -1:
			idx = i
			break
	if idx < 0:
		return -1
	release_watch(person)
	w[idx] = person
	_watching[person] = [spot, idx]
	return idx


func release_watch(person: int) -> void:
	var cur: Array = _watching.get(person, [])
	if cur.is_empty():
		return
	var w: Array = spots[int(cur[0])]["watchers"]
	if int(cur[1]) < w.size() and w[int(cur[1])] == person:
		w[int(cur[1])] = -1
	_watching.erase(person)


func watching(person: int) -> Array:
	return _watching.get(person, [])


## Where watcher `idx` stands: on the ring around the object, spread about the slot-0 approach axis
## (0, +40, -40, +80 ... degrees), facing the object so A1 can look at it.
func watch_xform(spot: int, idx: int) -> Transform3D:
	var o := (spots[spot]["xform"] as Transform3D).origin
	@warning_ignore("integer_division")
	var step := (idx + 1) / 2
	var sgn := 1.0 if idx % 2 == 1 else -1.0
	var dir := approach_axis(spot, 0).rotated(Vector3.UP, deg_to_rad(WATCH_STEP) * float(step) * sgn)
	var p := o + dir * watch_ring(spot)
	return Transform3D(Basis.looking_at(-dir, Vector3.UP, true), p)


## [spot, watcher index] of the nearest matching spot that is FULL and still has a free watcher slot, for a person who
## could not use any spot. [] while a matching spot is free (use it instead) or no ring slot is open.
func watch_pick(pos: Vector3, filter: Dictionary, radius := 60.0, person := -1) -> Array:
	if not find(pos, filter, radius, person).is_empty():
		return []
	var best := []
	var best_d := INF
	var r := int(ceil(radius / CELL))
	var c0 := _cell(pos)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id: int in _grid.get(c0 + Vector2i(dx, dz), []):
				var t: Dictionary = types[spots[id]["type"]]
				if watch_capacity(id) <= 0 or not _matches(spots[id]["type"], t, filter):
					continue
				var d := (spots[id]["xform"] as Transform3D).origin.distance_to(pos)
				if d > radius or d >= best_d:
					continue
				var w: Array = spots[id]["watchers"]
				var free := -1
				for i in watch_capacity(id):
					if i >= w.size() or w[i] == -1:
						free = i
						break
				if free >= 0:
					best_d = d
					best = [id, free]
	return best


## ---- validator -------------------------------------------------------------------------------------------------

static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _is_vec3(v: Variant) -> bool:
	if not (v is Array and (v as Array).size() == 3):
		return false
	for e in v:
		if not _is_num(e):
			return false
	return true


static func _is_whole(v: Variant) -> bool:
	return _is_num(v) and float(v) == floorf(float(v))


static func _check_clip(errs: Array[String], where: String, key: String, v: Variant) -> void:
	if typeof(v) == TYPE_STRING:
		if v == "":
			errs.append("%s: %s is an empty string" % [where, key])
	elif typeof(v) == TYPE_DICTIONARY:
		if (v as Dictionary).is_empty():
			errs.append("%s: %s has no front/side/back entry" % [where, key])
		for k in v:
			if not SIDES.has(k):
				errs.append("%s: %s has unknown side '%s' (front, side, back)" % [where, key, k])
			elif typeof(v[k]) != TYPE_STRING or v[k] == "":
				errs.append("%s: %s.%s must be a clip name" % [where, key, k])
	else:
		errs.append("%s: %s must be a clip name or {front, side, back}" % [where, key])


## v2 keys that may sit on a type or on a slot.
static func _check_common(errs: Array[String], where: String, d: Dictionary, targets: Dictionary) -> void:
	if d.has("approach_dir"):
		var a: Variant = d["approach_dir"]
		if not _is_vec3(a):
			errs.append("%s: approach_dir must be [x, y, z]" % where)
		elif Vector2(float(a[0]), float(a[2])).length() < 0.001:
			errs.append("%s: approach_dir has no horizontal part" % where)
	if d.has("approach_arc"):
		if not _is_num(d["approach_arc"]) or float(d["approach_arc"]) <= 0.0 or float(d["approach_arc"]) > 180.0:
			errs.append("%s: approach_arc must be in (0, 180] degrees" % where)
	for key in ["enter", "exit"]:
		if d.has(key):
			_check_clip(errs, where, key, d[key])
	if d.has("ik"):
		if not d["ik"] is Array:
			errs.append("%s: ik must be an array" % where)
		else:
			for i in (d["ik"] as Array).size():
				var e: Variant = d["ik"][i]
				var w := "%s/ik[%d]" % [where, i]
				if not e is Dictionary:
					errs.append("%s: must be an object" % w)
					continue
				if not IK_LIMBS.has(e.get("limb")):
					errs.append("%s: limb must be one of %s" % [w, ", ".join(IK_LIMBS)])
				if typeof(e.get("target")) != TYPE_STRING or not targets.has(e.get("target")):
					errs.append("%s: target '%s' is not in ik_targets" % [w, e.get("target")])
				if not _is_num(e.get("weight", 1.0)) or float(e.get("weight", 1.0)) < 0.0 or float(e.get("weight", 1.0)) > 1.0:
					errs.append("%s: weight must be 0..1" % w)
				var ph: Variant = e.get("phase", "loop")
				if typeof(ph) == TYPE_STRING:
					if ph != "loop":
						errs.append("%s: phase must be \"loop\" or [t0, t1]" % w)
				elif not (ph is Array and (ph as Array).size() == 2 and _is_num(ph[0]) and _is_num(ph[1])
						and float(ph[0]) >= 0.0 and float(ph[0]) <= float(ph[1]) and float(ph[1]) <= 1.0):
					errs.append("%s: phase must be \"loop\" or 0 <= t0 <= t1 <= 1" % w)
	if d.has("occupancy"):
		var o: Variant = d["occupancy"]
		if not o is Dictionary:
			errs.append("%s: occupancy must be an object" % where)
		else:
			for k in o:
				if not OCC_KEYS.has(k):
					errs.append("%s: occupancy has unknown key '%s'" % [where, k])
			if o.has("max") and (not _is_whole(o["max"]) or float(o["max"]) < 1.0 or float(o["max"]) > 16.0):
				errs.append("%s: occupancy.max must be a whole number 1..16" % where)
			if o.has("watchers") and (not _is_whole(o["watchers"]) or float(o["watchers"]) < 0.0 or float(o["watchers"]) > 8.0):
				errs.append("%s: occupancy.watchers must be a whole number 0..8" % where)
			if o.has("watch_ring") and (not _is_num(o["watch_ring"]) or float(o["watch_ring"]) < 0.5 or float(o["watch_ring"]) > 10.0):
				errs.append("%s: occupancy.watch_ring must be 0.5..10 m" % where)
	if d.has("needs"):
		if not d["needs"] is Dictionary:
			errs.append("%s: needs must be {need: weight}" % where)
		else:
			for n in d["needs"]:
				var wv: Variant = d["needs"][n]
				if not _is_num(wv) or float(wv) < 0.0 or float(wv) > 2.0:
					errs.append("%s: needs.%s must be a weight 0..2" % [where, n])
	if d.has("clip_tags"):
		if not d["clip_tags"] is Dictionary:
			errs.append("%s: clip_tags must be {phase: tag}" % where)
		else:
			for k in d["clip_tags"]:
				if typeof(d["clip_tags"][k]) != TYPE_STRING:
					errs.append("%s: clip_tags.%s must be a string" % [where, k])


## Schema check for a `types` dictionary (smart_objects.json "types"). One message per problem, prefixed
## "<type>:" or "<type>/slot<i>:"; an empty array means the data is valid. Legacy data (no v2 key) validates clean.
static func validate(types: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for name: String in types:
		var t: Variant = types[name]
		if not t is Dictionary:
			errs.append("%s: not an object" % name)
			continue
		var slots: Variant = t.get("slots")
		if not slots is Array or (slots as Array).is_empty():
			errs.append("%s: slots must be a non-empty array" % name)
			continue
		if t.has("hours") and not (t["hours"] is Array and (t["hours"] as Array).size() == 2 and _is_num(t["hours"][0]) and _is_num(t["hours"][1])):
			errs.append("%s: hours must be [from, to]" % name)
		var targets: Dictionary = {}
		if t.has("ik_targets"):
			if not t["ik_targets"] is Dictionary:
				errs.append("%s: ik_targets must be {name: [x, y, z]}" % name)
			else:
				targets = t["ik_targets"]
				for k in targets:
					if not _is_vec3(targets[k]):
						errs.append("%s: ik_targets.%s must be [x, y, z]" % [name, k])
		_check_common(errs, name, t, targets)
		if t.get("activity") is Dictionary:
			for k in ["enter", "exit"]:
				if t["activity"].has(k):
					_check_clip(errs, name, "activity." + k, t["activity"][k])
		for i in (slots as Array).size():
			var sl: Variant = slots[i]
			var w := "%s/slot%d" % [name, i]
			if not sl is Dictionary:
				errs.append("%s: not an object" % w)
				continue
			var st: Variant = sl.get("stand")
			if not ((typeof(st) == TYPE_STRING and st == "auto") or _is_vec3(st)):
				errs.append("%s: stand must be \"auto\" or [x, y, z]" % w)
			if sl.has("face") and not _is_num(sl["face"]):
				errs.append("%s: face must be degrees" % w)
			_check_common(errs, w, sl, targets)
	return errs


## World transform the character's root takes while using the slot (position + facing).
func stand_xform(spot: int, slot: int) -> Transform3D:
	var sp: Dictionary = spots[spot]
	var t: Dictionary = types[sp["type"]]
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
	# Keep activity timing on the original stable RNG. Visual clip variation gets
	# its own day/time-scoped bags so later visits get an independent take order,
	# while same-time reloads stay stable. A random permutation may still recur.
	var _variant_day := 1
	var _variant_time_bucket := 0
	var _variant_seed_person := -1
	var _variant_bags: Dictionary = {}
	var _variant_bag_cycles: Dictionary = {}
	var _last_variant: Dictionary = {}
	# O2/O3: where the person walks to, whether the declared arc steers it, and which side it comes from.
	var _ap := Vector3.INF
	var _arc_mode := false
	var _side := "front"

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
		# Shallow copy: enter / exit are resolved to plain strings for the chosen side (O3), so every reader of
		# `act` (villager, follower_body) keeps seeing a clip name even when the data holds {front, side, back}.
		act = o.activity(sp, sl).duplicate()
		_resolve_clips()
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

	func _resolve_clips() -> void:
		var en := so.enter_clip(spot, slot, _side)
		var ex := so.exit_clip(spot, slot, _side)
		if en != "" or act.has("enter"):
			act["enter"] = en
		if ex != "" or act.has("exit"):
			act["exit"] = ex

	## Which side of the object the person arrived from ("front", "side", "back").
	func side() -> String:
		return _side

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
				clip = act.get("enter", "")
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
			var ref_clip: String = clip if phase in [LOOP, BETWEEN] else String(act.get("enter" if phase in [ALIGN, ENTER] else "exit", clip))
			sx = seated(sx, ref_clip)
		match phase:
			APPROACH:
				if _ap == Vector3.INF:
					# first step: fix the arrival point inside the declared arc (O2) and the side the person comes from (O3)
					_arc_mode = so.declares_arc(spot, slot)
					_ap = so.arrival_point(spot, slot, body) if _arc_mode else so.approach_point(spot, slot)
					_side = so.classify_side(spot, slot, _ap if _arc_mode else body)
					_resolve_clips()
				var ap := _ap if _arc_mode else so.approach_point(spot, slot)
				var to_ap := Vector2(body.x - ap.x, body.z - ap.z).length()
				if Vector2(body.x - sx.origin.x, body.z - sx.origin.z).length() < 0.5 or (to_ap < 0.35 and (not _arc_mode or so.in_arc(spot, slot, body))):
					_go(ALIGN)
				else:
					out["move_to"] = ap
					out["clip"] = ""
					out["speed_scale"] = clampf(to_ap / SLOW_DIST, SLOW_MIN, 1.0)
			ALIGN:
				# Root-motion enters (sidecar "entry_offset", character frame: +Z forward): the clip starts with the body
				# that far from its root, so stand there; the root jumps onto the slot when the enter starts (no visible move).
				var entry := sx.origin + sx.basis * _offset(String(act.get("enter", "")), "entry_offset")
				out["move_to"] = entry
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["clip"] = ""
				var alignment_error := Vector2(body.x - entry.x, body.z - entry.z).length()
				out["speed_scale"] = clampf(alignment_error / SLOW_DIST, SLOW_MIN, 1.0)
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
