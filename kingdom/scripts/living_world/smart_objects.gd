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
const JOBS := ["Farmer", "Blacksmith", "Merchant", "Guard", "Laborer", "Woodcutter"]

var types: Dictionary = {}
var building_spots: Dictionary = {}
var spots: Array = []               # Array[Dictionary]: {id, identity, has_stable_identity, type, xform, settlement, holders, drift}
var _grid: Dictionary = {}          # Vector2i -> Array[int]
var _held: Dictionary = {}          # person -> [spot, slot, claim_token]
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
		"settlement": settlement, "holders": holders, "drift": 0.0})
	if not stable_identity.is_empty():
		_spot_by_identity[stable_identity] = id
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
## or [] when nothing fits. Score = distance, a little noise per person so neighbours spread out.
func find(pos: Vector3, filter: Dictionary, radius := 60.0, person := -1) -> Array:
	var best := []
	var best_s := INF
	var r := int(ceil(radius / CELL))
	var c0 := _cell(pos)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id: int in _grid.get(c0 + Vector2i(dx, dz), []):
				var sp: Dictionary = spots[id]
				var t: Dictionary = types[sp["type"]]
				if not _matches(sp["type"], t, filter):
					continue
				var d := (sp["xform"] as Transform3D).origin.distance_to(pos)
				if d > radius:
					continue
				var slots: Array = t["slots"]
				for k in slots.size():
					# A data-tier resident often asks for its schedule target again on
					# every coarse simulation step. Keep its existing slot eligible so
					# refreshing the same goal does not make it churn through the queue.
					if sp["holders"][k] != -1 and sp["holders"][k] != person:
						continue
					var role := String(slots[k].get("role", ""))
					if filter.has("role") and role != filter["role"]:
						continue
					# Slot-specific eligibility supports shared affordances such as a
					# merchant-only vendor position beside public customer positions.
					if filter.has("job") and slots[k].has("jobs"):
						var j = filter["job"]
						var jn: String = JOBS[j] if typeof(j) == TYPE_INT and j >= 0 and j < JOBS.size() else String(j)
						if not (slots[k]["jobs"] as Array).has(jn):
							continue
					var score := d + float(absi(hash(person * 7 + id * 131 + k)) % 100) * 0.03
					if sp["holders"][k] == person:
						score -= 1.0  # small hysteresis keeps a valid activity stable
					if score < best_s:
						best_s = score
						best = [id, k]
	return best


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
	release(person)
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
func target_for(person: int, center: Vector3, act: String, job: int, hour: float, radius := 120.0, role := "") -> Vector2:
	var filter := {"act": act, "job": job, "hour": hour}
	if not role.is_empty():
		filter["role"] = role
	# Public workers can visit stalls as customers, but should not treat a
	# customer position as their work station during the work phase.
	if act == "work" and job != JOBS.find("Merchant"):
		filter["exclude_types"] = ["market_stall"]
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
	var act: Dictionary
	var time_left := 30.0
	var cycles_left := 2
	var clip := ""
	var _restart := false
	var _rng := RandomNumberGenerator.new()
	var _t := 0.0
	var _event_sent := false
	var _claim_token := -1

	func _init(o: SmartObjects, p: int, sp: int, sl: int, sd: int) -> void:
		so = o
		person = p
		spot = sp
		slot = sl
		_claim_token = o.claim_token(p)
		_rng.seed = hash(sd * 7919 + sp)
		act = o.activity(sp, sl)
		var dur: Array = act.get("duration", [30, 60])
		time_left = _rng.randf_range(float(dur[0]), float(dur[1]))
		_new_cycles()

	func _new_cycles() -> void:
		var c: Array = act.get("cycles", [2, 4])
		cycles_left = _rng.randi_range(int(c[0]), int(c[1]))

	func interrupt() -> void:
		if phase in [ENTER, LOOP, BETWEEN]:
			_go(EXIT if act.get("exit", "") != "" else DONE)
		elif phase in [APPROACH, ALIGN]:
			_go(DONE)


	## Immediate teardown path for a body that is being removed and cannot play
	## its exit animation. Normal gameplay interruptions should use interrupt().
	func cancel_now() -> void:
		_go(DONE)

	func stand() -> Transform3D:
		return so.stand_xform(spot, slot)

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
				var loops: Array = act.get("loop", ["Idle"])
				clip = loops[_rng.randi() % loops.size()]
			BETWEEN:
				var b: Array = act.get("between", [])
				clip = b[_rng.randi() % b.size()]
			EXIT:
				clip = act.get("exit", "")
				if clip == "":
					_go(DONE)
			DONE:
				so.release_claim(person, spot, slot, _claim_token)

	func update(delta: float, body: Vector3, clip_done: bool) -> Dictionary:
		# A replacement schedule, despawn, or LOD handoff may revoke this claim.
		# Stop producing clips/events immediately, without touching a newer lease.
		if phase != DONE and not so.owns_claim(person, spot, slot, _claim_token):
			phase = DONE
			clip = ""
			return {"phase": DONE, "move_to": null, "face": NAN, "clip": "",
				"restart": false, "props": [], "event": null}
		_t += delta
		var out := {"phase": phase, "move_to": null, "face": NAN, "clip": clip, "restart": false, "props": [], "event": null}
		var sx := stand()
		match phase:
			APPROACH:
				var ap := so.approach_point(spot, slot)
				if Vector2(body.x - ap.x, body.z - ap.z).length() < 0.35 or Vector2(body.x - sx.origin.x, body.z - sx.origin.z).length() < 0.5:
					_go(ALIGN)
				else:
					out["move_to"] = ap
					out["clip"] = ""
			ALIGN:
				out["move_to"] = sx.origin
				out["face"] = atan2(sx.basis.z.x, sx.basis.z.z)
				out["clip"] = ""
				var alignment_error := Vector2(body.x - sx.origin.x, body.z - sx.origin.z).length()
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
				if clip_done and _t > 0.1:
					_go(DONE)
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
