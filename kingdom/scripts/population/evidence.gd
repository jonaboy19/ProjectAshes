extends RefCounted
## Evidence registry for the near-NPC layer: bodies, blood, broken doors/props and missing items that stay
## where a crime happened, so an unwitnessed crime still leaves a trace that people can stumble on.
## Static, fixed-size (MAX entries, oldest evicted). Consumers (villager.gd) scan the few entries near them
## once per (person, entry); discovery feeds Society.add_evidence and raises the finder's alert.
## Design: docs/research/MINING_PERCEPTION_INTERACTION.md 2.6 and 4.5 (own implementation).

enum Kind { BODY, KO, BLOOD, OPEN_DOOR, BROKEN_PROP, MISSING_ITEM, BROKEN_DOOR }
const KIND_NAMES := ["body", "ko", "blood", "open_door", "broken_prop", "missing_item", "broken_door"]
## Society evidence item type for each kind (scripts/realm/society.gd EVIDENCE_DECAY keys).
const SOCIETY_TYPE := ["blood", "blood", "blood", "footprints", "footprints", "stolen_goods", "footprints"]
## Alert class a finder jumps to (Perception.Cls): civilians panic at bodies, guards search.
const MAX := 32
const SEEN_PER := 8
## Reaction delay window (ms) so finders do not react in lockstep.
const DELAY_MIN_MS := 500
const DELAY_SPAN_MS := 1000
## "Saw it happen": a finder within this window of the event counts as a witness.
const HAPPEN_MS := 3000
## Entries older than this (ms) are cleared by tick_day / prune (bodies rot, are carted away).
const LIFETIME_MS := 20 * 60 * 1000

static var _kind := PackedInt32Array()
static var _pos := PackedVector2Array()
static var _t := PackedInt32Array()
static var _sid := PackedInt32Array()
static var _uid := PackedInt32Array()            # stable id, 0 = free slot
static var _fed := PackedByteArray()             # already given to Society
static var _seen := PackedInt32Array()           # MAX * SEEN_PER person ids (-1 empty)
static var _source: Array = []                   # crime id / description per slot
static var _next := 1
static var _ready_store := false
static var count := 0


static func _ensure() -> void:
	if _ready_store:
		return
	_ready_store = true
	_kind.resize(MAX)
	_pos.resize(MAX)
	_t.resize(MAX)
	_sid.resize(MAX)
	_uid.resize(MAX)
	_fed.resize(MAX)
	_seen.resize(MAX * SEEN_PER)
	_source.resize(MAX)
	_uid.fill(0)
	_seen.fill(-1)


static func reset() -> void:
	_ready_store = false
	_next = 1
	count = 0
	_ensure()


## Add an entry; returns its id (> 0). Evicts the oldest when full.
static func add(kind: int, pos: Vector2, sid := -1, now_ms := -1, source := "") -> int:
	_ensure()
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var slot := -1
	var oldest := 0
	var oldest_t := 1 << 60
	for i in MAX:
		if _uid[i] == 0:
			slot = i
			break
		if _t[i] < oldest_t:
			oldest_t = _t[i]
			oldest = i
	if slot < 0:
		slot = oldest
	else:
		count += 1
	var id := _next
	_next += 1
	_uid[slot] = id
	_kind[slot] = kind
	_pos[slot] = pos
	_t[slot] = now
	_sid[slot] = sid
	_fed[slot] = 0
	_source[slot] = source
	for k in SEEN_PER:
		_seen[slot * SEEN_PER + k] = -1
	return id


static func _slot(id: int) -> int:
	if id <= 0:
		return -1
	for i in MAX:
		if _uid[i] == id:
			return i
	return -1


static func exists(id: int) -> bool:
	return _slot(id) >= 0


static func remove(id: int) -> bool:
	var i := _slot(id)
	if i < 0:
		return false
	_uid[i] = 0
	count -= 1
	return true


static func clear() -> void:
	_ensure()
	_uid.fill(0)
	count = 0


static func kind_of(id: int) -> int:
	var i := _slot(id)
	return _kind[i] if i >= 0 else -1


static func pos_of(id: int) -> Vector2:
	var i := _slot(id)
	return _pos[i] if i >= 0 else Vector2.INF


static func age_ms(id: int, now_ms := -1) -> int:
	var i := _slot(id)
	if i < 0:
		return -1
	return (now_ms if now_ms >= 0 else Time.get_ticks_msec()) - _t[i]


static func has_seen(id: int, person: int) -> bool:
	var i := _slot(id)
	if i < 0:
		return true
	for k in SEEN_PER:
		if _seen[i * SEEN_PER + k] == person:
			return true
	return false


static func mark_seen(id: int, person: int) -> void:
	var i := _slot(id)
	if i < 0 or has_seen(id, person):
		return
	for k in SEEN_PER:
		if _seen[i * SEEN_PER + k] == -1:
			_seen[i * SEEN_PER + k] = person
			return
	_seen[i * SEEN_PER + (person & (SEEN_PER - 1))] = person


## Nearest entry within `radius` of `here` that `person` has not seen (0 when none). 32 entries, spatial early out.
static func nearest_unseen(here: Vector2, radius: float, person: int) -> int:
	if count <= 0:
		return 0
	var best := 0
	var best_d := radius * radius
	for i in MAX:
		if _uid[i] == 0:
			continue
		var d := here.distance_squared_to(_pos[i])
		if d >= best_d:
			continue
		var seen := false
		for k in SEEN_PER:
			if _seen[i * SEEN_PER + k] == person:
				seen = true
				break
		if not seen:
			best_d = d
			best = _uid[i]
	return best


## Id of an entry of `kind` within `tol` of `pos` (0 when none): lets a restored body re-link to its saved evidence.
static func find_at(kind: int, pos: Vector2, tol := 0.3) -> int:
	for i in MAX:
		if _uid[i] != 0 and _kind[i] == kind and _pos[i].distance_to(pos) <= tol:
			return _uid[i]
	return 0


## Deterministic reaction delay in ms for `person` finding entry `id` (0.5 - 1.5 s).
static func reaction_delay_ms(person: int, id: int) -> int:
	return DELAY_MIN_MS + absi(hash([person, id])) % DELAY_SPAN_MS


## Hand the entry to Society once (`soc` is a RefCounted with add_evidence(crime, type, strength, sid)).
## Returns the Society evidence id ("" when already fed, unknown or no society).
static func feed(id: int, soc: RefCounted) -> String:
	var i := _slot(id)
	if i < 0 or _fed[i] == 1 or soc == null:
		return ""
	_fed[i] = 1
	var strength := 0.6 if _kind[i] <= Kind.KO else 0.4
	return String(soc.call("add_evidence", String(_source[i]) if String(_source[i]) != "" else "found", SOCIETY_TYPE[_kind[i]], strength, _sid[i]))


## Bodies rot, blood dries: drop entries older than LIFETIME_MS (BLOOD half that). Returns how many went.
static func prune(now_ms := -1) -> int:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var n := 0
	for i in MAX:
		if _uid[i] == 0:
			continue
		var life := LIFETIME_MS / 2 if _kind[i] == Kind.BLOOD else LIFETIME_MS
		if now - _t[i] > life:
			_uid[i] = 0
			count -= 1
			n += 1
	return n


## What a crime of `kind` leaves behind at `pos` (producers: NpcWorld.report_crime). Returns the entry ids.
static func leave_traces(crime_kind: String, pos: Vector2, sid: int, now_ms := -1, source := "") -> Array:
	var out: Array = []
	match crime_kind:
		"murder":
			out.append(add(Kind.BODY, pos, sid, now_ms, source))
			out.append(add(Kind.BLOOD, pos, sid, now_ms, source))
		"assault":
			out.append(add(Kind.BLOOD, pos, sid, now_ms, source))
		"pickpocket", "robbery", "burglary":
			out.append(add(Kind.MISSING_ITEM, pos, sid, now_ms, source))
		_:
			pass
	return out


# ------------------------------------------------------------------ persistence
static func serialize() -> Array:
	_ensure()
	var out: Array = []
	for i in MAX:
		if _uid[i] != 0:
			out.append([_kind[i], snappedf(_pos[i].x, 0.1), snappedf(_pos[i].y, 0.1), _sid[i], String(_source[i])])
	return out


## Entries are restored as fresh (age 0, nobody has seen them). Garbage rows are ignored.
static func deserialize(rows: Variant, now_ms := -1) -> void:
	reset()
	if not rows is Array:
		return
	for r: Variant in rows:
		if not r is Array or (r as Array).size() < 4:
			continue
		var a: Array = r
		var k := int(a[0])
		if k < 0 or k >= KIND_NAMES.size():
			continue
		add(k, Vector2(float(a[1]), float(a[2])), int(a[3]), now_ms, String(a[4]) if a.size() > 4 else "")
