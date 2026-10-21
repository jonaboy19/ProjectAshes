extends RefCounted
## Sparse, bounded ties between persistent non-player people.
##
## This is distinct from Relationships, which owns how NPCs regard the player.
## Endpoints are namespaced strings so future identity domains can coexist;
## current embodied villagers use `worldsim:<seed>:<person-index>`.

const VERSION := 2
## NI-5: bonds layer (below). Version 1 saves (pair edges only) still load.
const MAX_EDGES := 2048
const MAX_ID_LENGTH := 96
const MIN_REPEAT_DAYS := 0.25
## Familiarity loses at most half its value after 200 days without a valid chat.
const DORMANCY_FADE_PER_DAY := 0.0025
const DORMANCY_FADE_CAP := 0.5

## Canonical pair key -> {a, b, first_day, last_day, conversations, affinity}.
var edges: Dictionary = {}


static func worldsim_person(seed: int, person: int) -> String:
	if person < 0:
		return ""
	return "worldsim:%d:%d" % [seed, person]


static func _valid_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= MAX_ID_LENGTH and not value.contains("|")


static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## A successful, face-to-face conversation adds familiarity. Repeated callbacks
## are coalesced; a pair can gain at most one conversation per six game hours.
func record_conversation(a: String, b: String, day: float) -> bool:
	if not _valid_id(a) or not _valid_id(b) or a == b or not is_finite(day) or day < 0.0:
		return false
	var key := _pair_key(a, b)
	if edges.has(key):
		var edge: Dictionary = edges[key]
		if day < float(edge["last_day"]):
			return false
		if day - float(edge["last_day"]) < MIN_REPEAT_DAYS:
			return true
		var elapsed_days := day - float(edge["last_day"])
		var fade := minf(DORMANCY_FADE_CAP, elapsed_days * DORMANCY_FADE_PER_DAY)
		edge["affinity"] = float(edge["affinity"]) * (1.0 - fade)
		edge["last_day"] = day
		edge["conversations"] = mini(int(edge["conversations"]) + 1, 999)
		edge["affinity"] = minf(60.0, float(edge["affinity"]) + 2.0)
		edges[key] = edge
		_bond_chat(a, b, day)
		return true
	if edges.size() >= MAX_EDGES:
		_evict_oldest()
	var left := a if a < b else b
	var right := b if a < b else a
	edges[key] = {"a": left, "b": right, "first_day": day, "last_day": day,
		"conversations": 1, "affinity": 2.0}
	_bond_chat(a, b, day)
	return true


## Neutral/default ties are absent. Returned values are copies.
func link(a: String, b: String) -> Dictionary:
	if not _valid_id(a) or not _valid_id(b) or a == b:
		return {}
	return (edges.get(_pair_key(a, b), {}) as Dictionary).duplicate(true)


func affinity(a: String, b: String, now_day := -1.0) -> float:
	var edge := link(a, b)
	var value := float(edge.get("affinity", 0.0))
	# Existing callers without a clock keep receiving the saved raw score.
	if edge.is_empty() or now_day < 0.0 or not is_finite(now_day):
		return value
	var age := maxf(0.0, now_day - float(edge["last_day"]))
	var fade := minf(DORMANCY_FADE_CAP, age * DORMANCY_FADE_PER_DAY)
	return value * (1.0 - fade)


## A person died: every tie they had goes. Returns how many edges were dropped.
func forget(id: String) -> int:
	var drop: Array = []
	for key: String in edges:
		var e: Dictionary = edges[key]
		if String(e["a"]) == id or String(e["b"]) == id:
			drop.append(key)
	for key: String in drop:
		edges.erase(key)
	bond_forget(id)
	return drop.size()


func _evict_oldest() -> void:
	var oldest_key := ""
	var oldest_day := INF
	for key: String in edges:
		var edge: Dictionary = edges[key]
		# Prefer dropping weak, stale incidental ties over repeatedly renewed ones.
		var score := float(edge["last_day"]) + float(edge["affinity"]) * 0.02
		if score < oldest_day:
			oldest_day = score
			oldest_key = key
	if oldest_key != "":
		edges.erase(oldest_key)


func serialize() -> Dictionary:
	var records: Array = []
	var keys: Array = edges.keys()
	keys.sort()
	for key: String in keys:
		records.append((edges[key] as Dictionary).duplicate(true))
	var out := {"version": VERSION, "edges": records}
	var bb := bond_serialize()
	if not bb.is_empty():
		out["bonds"] = bb
	return out


## Invalid optional social data is rejected as a whole; older saves remain empty.
func deserialize(data: Variant) -> bool:
	var restored: Dictionary = {}
	if not data is Dictionary or not (int(data.get("version", -1)) in [1, VERSION]):
		edges = restored
		_bond_reset()
		return false
	var raw_edges: Variant = data.get("edges", [])
	if not raw_edges is Array or raw_edges.size() > MAX_EDGES:
		edges = restored
		return false
	for raw: Variant in raw_edges:
		if not raw is Dictionary:
			edges = {}
			return false
		var row: Dictionary = raw
		var a: Variant = row.get("a", null)
		var b: Variant = row.get("b", null)
		var first: Variant = row.get("first_day", null)
		var last: Variant = row.get("last_day", null)
		var conversations: Variant = row.get("conversations", null)
		var affinity_value: Variant = row.get("affinity", null)
		if not a is String or not b is String or not _valid_id(String(a)) or not _valid_id(String(b)) \
		or String(a) == String(b) or not (first is float or first is int) or not (last is float or last is int) \
		or not is_finite(float(first)) or not is_finite(float(last)) or float(first) < 0.0 \
		or float(last) < float(first) or not (conversations is int or conversations is float) \
		or not is_finite(float(conversations)) or float(conversations) != floorf(float(conversations)) \
		or float(conversations) < 1.0 or float(conversations) > 999.0 \
		or not (affinity_value is int or affinity_value is float) or not is_finite(float(affinity_value)) \
		or float(affinity_value) < 0.0 or float(affinity_value) > 60.0:
			edges = {}
			return false
		var left := String(a) if String(a) < String(b) else String(b)
		var right := String(b) if String(a) < String(b) else String(a)
		var key := _pair_key(left, right)
		if restored.has(key):
			edges = {}
			return false
		restored[key] = {"a": left, "b": right, "first_day": float(first), "last_day": float(last),
			"conversations": int(conversations), "affinity": float(affinity_value)}
	edges = restored
	_bond_reset()
	if data.has("bonds"):
		bond_deserialize(data["bonds"])
	return true


# ====================================================================================================================
# NI-5 bonds: multi-axis, asymmetric, bounded ties between registry characters ("ch:N"), packed.
# ====================================================================================================================
# Each character owns one slot of BSLOT bytes: a count and up to BOND_K ties (top-K by salience). A tie is the OWNER's view of the other
# person, so A's view of B and B's view of A are separate records and need not agree (A may admire B who fears A).
#   tie (BREC = 13 bytes): other number (3, little endian) | eight axes as signed bytes (-127..127) | day last written (u16)
# Axes decay toward zero in closed form at every read, each with its own half-life (BOND_DECAY), so nothing is ticked: a quiet tie fades
# by itself, a grudge outlasts a crush, fear fades fastest. A tie whose axes have all faded is dropped when next touched.
# Save: only used slots, zlib + base64 (about 30 B per tie before compression). realm/bonds.gd is the adapter that turns world events
# into deltas (it holds no store of its own); everything stored lives here, next to the pair edges.

const BOND_AXES := ["trust", "affection", "respect", "fear", "resentment", "rivalry", "attraction", "obligation"]
const AX_TRUST := 0
const AX_AFFECTION := 1
const AX_RESPECT := 2
const AX_FEAR := 3
const AX_RESENT := 4
const AX_RIVAL := 5
const AX_ATTRACT := 6
const AX_OBLIG := 7
const BOND_N := 8
const BOND_K := 6
const BREC := 13
const BSLOT := 1 + BOND_K * BREC
const BOND_SLOTS := 1100
## ln 2 / half-life in days: trust 600, affection 500, respect 800, fear 160, resentment 400, rivalry 260, attraction 220, obligation 200.
const BOND_DECAY := [0.001155, 0.001386, 0.000866, 0.004332, 0.001733, 0.002666, 0.003151, 0.003466]

var _bb := PackedByteArray()
var _bid := PackedInt32Array()          # slot -> owner number (0 = free)
var _bslot: Dictionary = {}             # owner number -> slot
var _bfree: Array = []
var _bout := PackedFloat32Array()       # reused by bond_get
var bond_refused := 0


static func person_number(id: String) -> int:
	if not id.begins_with("ch:"):
		return 0
	var rest := id.substr(3)
	return int(rest) if rest.is_valid_int() and int(rest) > 0 else 0


func _bond_reset() -> void:
	_bb = PackedByteArray()
	_bid = PackedInt32Array()
	_bslot = {}
	_bfree = []


func bond_owner_count() -> int:
	return _bslot.size()


func bond_tie_count() -> int:
	var t := 0
	for n: Variant in _bslot:
		t += int(_bb[int(_bslot[n]) * BSLOT])
	return t


func bond_count(owner: String) -> int:
	var s: Variant = _bslot.get(person_number(owner))
	return int(_bb[int(s) * BSLOT]) if s != null else 0


func _bond_slot(n: int, make: bool) -> int:
	var s: Variant = _bslot.get(n)
	if s != null:
		return int(s)
	if not make:
		return -1
	var slot := -1
	if not _bfree.is_empty():
		slot = int(_bfree.pop_back())
	elif _bid.size() < BOND_SLOTS:
		slot = _bid.size()
		_bid.append(0)
		_bb.resize(_bb.size() + BSLOT)
	if slot < 0:
		bond_refused += 1
		return -1
	_bid[slot] = n
	_bslot[n] = slot
	_bb[slot * BSLOT] = 0
	return slot


func _brec_other(o: int) -> int:
	return int(_bb[o]) | (int(_bb[o + 1]) << 8) | (int(_bb[o + 2]) << 16)


func _brec_day(o: int) -> int:
	return int(_bb[o + 11]) | (int(_bb[o + 12]) << 8)


## The axes of the record at byte offset `o` as of `day`, decayed, into `out` (8 floats).
func _brec_read(o: int, day: int, out: PackedFloat32Array) -> void:
	var age := float(maxi(0, day - _brec_day(o)))
	for i in BOND_N:
		var v := float(_bb.decode_s8(o + 3 + i))
		out[i] = v * exp(-age * float(BOND_DECAY[i])) if age > 0.0 and v != 0.0 else v


func _brec_write(o: int, other: int, vals: PackedFloat32Array, day: int) -> void:
	_bb[o] = other & 255
	_bb[o + 1] = (other >> 8) & 255
	_bb[o + 2] = (other >> 16) & 255
	for i in BOND_N:
		_bb.encode_s8(o + 3 + i, clampi(roundi(vals[i]), -127, 127))
	var dd := clampi(day, 0, 65535)
	_bb[o + 11] = dd & 255
	_bb[o + 12] = (dd >> 8) & 255


static func bond_salience(vals: PackedFloat32Array) -> float:
	var s := 0.0
	for i in BOND_N:
		s += absf(vals[i])
	return s


## The owner's view of `other` on `day`: 8 floats in BOND_AXES order (all zero when there is no tie). The array is reused by the next call.
func bond_get(owner: String, other: String, day: int) -> PackedFloat32Array:
	if _bout.size() != BOND_N:
		_bout.resize(BOND_N)
	_bout.fill(0.0)
	var slot := _bond_slot(person_number(owner), false)
	var on := person_number(other)
	if slot < 0 or on == 0:
		return _bout
	var base := slot * BSLOT
	for t in int(_bb[base]):
		var o := base + 1 + t * BREC
		if _brec_other(o) == on:
			_brec_read(o, day, _bout)
			return _bout
	return _bout


## Ties of `owner` as [other id, PackedFloat32Array(8)] pairs on `day`, strongest first (at most `limit`).
func bond_list(owner: String, day: int, limit := BOND_K, sorted := true) -> Array:
	var out: Array = []
	var slot := _bond_slot(person_number(owner), false)
	if slot < 0:
		return out
	var base := slot * BSLOT
	for t in int(_bb[base]):
		var o := base + 1 + t * BREC
		var vals := PackedFloat32Array()
		vals.resize(BOND_N)
		_brec_read(o, day, vals)
		out.append([ "ch:%d" % _brec_other(o), vals])
	if not sorted:
		return out
	out.sort_custom(func(a: Array, b: Array) -> bool: return bond_salience(a[1]) > bond_salience(b[1]))
	return out.slice(0, limit) if out.size() > limit else out


## Adds `deltas` (8 floats, signed) to the owner's view of `other` on `day`. A new tie enters a full slot only by being stronger than the
## weakest one it replaces. Returns false when nothing was stored.
func bond_adjust(owner: String, other: String, deltas: PackedFloat32Array, day: int) -> bool:
	var on := person_number(other)
	var n := person_number(owner)
	if n == 0 or on == 0 or n == on or deltas.size() != BOND_N or day < 0:
		return false
	var slot := _bond_slot(n, true)
	if slot < 0:
		return false
	var base := slot * BSLOT
	var cnt := int(_bb[base])
	var vals := PackedFloat32Array()
	vals.resize(BOND_N)
	for t in cnt:
		var o := base + 1 + t * BREC
		if _brec_other(o) == on:
			_brec_read(o, day, vals)
			for i in BOND_N:
				vals[i] = clampf(vals[i] + deltas[i], -127.0, 127.0)
			_brec_write(o, on, vals, day)
			return true
	for i in BOND_N:
		vals[i] = clampf(deltas[i], -127.0, 127.0)
	if bond_salience(vals) < 1.0:
		return false
	if cnt < BOND_K:
		_brec_write(base + 1 + cnt * BREC, on, vals, day)
		_bb[base] = cnt + 1
		return true
	# full: replace the weakest tie if the newcomer is stronger
	var weakest := -1
	var ws := 1.0e9
	var tmp := PackedFloat32Array()
	tmp.resize(BOND_N)
	for t in cnt:
		var o2 := base + 1 + t * BREC
		_brec_read(o2, day, tmp)
		var sal := bond_salience(tmp)
		if sal < ws:
			ws = sal
			weakest = t
	if bond_salience(vals) <= ws:
		return false
	_brec_write(base + 1 + weakest * BREC, on, vals, day)
	return true


## Removes every tie of and to `id` and frees its slot.
func bond_forget(id: String) -> void:
	var n := person_number(id)
	if n == 0:
		return
	var own: Variant = _bslot.get(n)
	if own != null:
		_bslot.erase(n)
		_bid[int(own)] = 0
		_bb[int(own) * BSLOT] = 0
		_bfree.append(int(own))
	for sl in _bid.size():
		if _bid[sl] == 0:
			continue
		var base := sl * BSLOT
		var cnt := int(_bb[base])
		var t := 0
		while t < cnt:
			var o := base + 1 + t * BREC
			if _brec_other(o) == n:
				var last := base + 1 + (cnt - 1) * BREC
				if o != last:
					for k in BREC:
						_bb[o + k] = _bb[last + k]
				cnt -= 1
				_bb[base] = cnt
			else:
				t += 1


func _bond_chat(a: String, b: String, day: float) -> void:
	if person_number(a) == 0 or person_number(b) == 0:
		return
	var d := PackedFloat32Array([0.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	bond_adjust(a, b, d, int(day))
	bond_adjust(b, a, d, int(day))


func bond_serialize() -> Dictionary:
	if _bslot.is_empty():
		return {}
	var raw := PackedByteArray()
	var owners: Array = _bslot.keys()
	owners.sort()
	for n: Variant in owners:
		var base := int(_bslot[n]) * BSLOT
		var cnt := int(_bb[base])
		if cnt == 0:
			continue
		raw.append(int(n) & 255)
		raw.append((int(n) >> 8) & 255)
		raw.append((int(n) >> 16) & 255)
		raw.append(cnt)
		raw.append_array(_bb.slice(base + 1, base + 1 + cnt * BREC))
	return {"v": 1, "len": raw.size(), "z": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}


func bond_deserialize(d: Variant) -> bool:
	_bond_reset()
	if not d is Dictionary or int(d.get("v", 0)) != 1:
		return false
	var len_raw := int(d.get("len", 0))
	if len_raw <= 0 or len_raw > BOND_SLOTS * (4 + BOND_K * BREC):
		return false
	var raw := Marshalls.base64_to_raw(String(d.get("z", ""))).decompress(len_raw, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != len_raw:
		return false
	var p := 0
	while p + 4 <= raw.size():
		var n := int(raw[p]) | (int(raw[p + 1]) << 8) | (int(raw[p + 2]) << 16)
		var cnt := int(raw[p + 3])
		p += 4
		if n == 0 or cnt < 1 or cnt > BOND_K or p + cnt * BREC > raw.size() or _bslot.has(n):
			_bond_reset()
			return false
		var slot := _bond_slot(n, true)
		if slot < 0:
			_bond_reset()
			return false
		for k in cnt * BREC:
			_bb[slot * BSLOT + 1 + k] = raw[p + k]
		_bb[slot * BSLOT] = cnt
		p += cnt * BREC
	return true
