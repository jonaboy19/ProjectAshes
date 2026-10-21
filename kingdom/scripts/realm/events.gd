extends "res://scripts/realm/realm_module.gd"
## EventRecord log (LW-1.2, docs/design/LIVING_WORLD_SANDBOX.md Part C and E).
## One append-only ring of the 2,000 most recent events. Systems write, news / rumour / memory / chronicle / justice read.
## A record is a packed array (about 60-90 B of JSON):
##   [n, day, kind, where, actors[], cause, outcome, weight]
## n is the number in "ev:n" (minted by the registry, never reused), where / actors are persistent ids (legacy keys are
## resolved through the registry; one that cannot be resolved stays as written), cause and outcome are short plain
## strings, weight 0..9 (>= HIST_WEIGHT survives compaction as a historic line).
## When the ring overflows its oldest COMPACT_BATCH records are folded into counts per "where|kind", totals per kind and
## up to HISTORIC_MAX one-line history entries, so the save stays inside the doc's budget (<= 120 KB raw for the ring).
## Writing is one array append plus two dictionary lookups; compaction is amortised over COMPACT_BATCH writes.
## Readers scan the ring (2,000 rows) and are meant for UI, justice and daily jobs, never for per-frame use.
##
## From a realm module:  Events.log_to(hub, "death", sid, [who], "illness", "Aldric died", 4)
## From sim scripts:     Events.emit("marriage", ...)   (finds Life.realm)

const Registry := preload("res://scripts/realm/registry.gd")

const CAP := 2000
const COMPACT_BATCH := 200
const HIST_WEIGHT := 6
const HISTORIC_MAX := 200
const COUNT_KEYS_MAX := 600
const CAUSE_MAX := 28
const OUTCOME_MAX := 56
const ACTORS_MAX := 4
## Kinds the game writes today (others are accepted; this is the shared vocabulary).
const KINDS := ["death", "birth", "marriage", "crime", "contract", "build", "battle", "succession", "emergency", "founding", "trade"]

var _ring: Array = []
var _counts: Dictionary = {}     # "where|kind" -> n (archived events)
var _totals: Dictionary = {}     # kind -> n (every event ever, archived and live)
var _hist: Array = []            # historic one-liners from compacted events
var _own_n := 0                  # event numbers when no registry is around (tests)
var _dropped := 0
var _ser: Dictionary = {}        # serialize() cache, rebuilt only after a write
var _dirty := true


# ------------------------------------------------------------------ writing

## Appends one event. `where` is a persistent id, a legacy key or "" ; `actors` persistent ids or legacy keys.
## Returns the event number (the n of "ev:n").
func record(kind: String, where: Variant, actors: Array, cause: String, outcome: String, weight := 1, day := -1) -> int:
	var reg: RefCounted = hub.mod("registry") if hub != null else null
	var n := 0
	var w := ""
	var acts: Array = []
	if reg != null:
		n = reg.mint_n("ev")
		w = reg.resolve(where) if String(where) != "" else ""
		for a: Variant in actors:
			if acts.size() >= ACTORS_MAX:
				break
			acts.append(reg.resolve(a))
	else:
		_own_n += 1
		n = _own_n
		w = String(where)
		for a: Variant in actors:
			if acts.size() >= ACTORS_MAX:
				break
			acts.append(String(a))
	var d := day if day >= 0 else (WorldSim.day if WorldSim != null else 0)
	_ring.append([n, d, kind, w, acts, cause.substr(0, CAUSE_MAX), outcome.substr(0, OUTCOME_MAX), clampi(weight, 0, 9)])
	_totals[kind] = int(_totals.get(kind, 0)) + 1
	_dirty = true
	if _ring.size() > CAP:
		_compact()
	return n


## Folds the oldest COMPACT_BATCH records into counts / totals-by-place and historic lines.
func _compact() -> void:
	var drop := _ring.size() - (CAP - COMPACT_BATCH)
	if drop <= 0:
		return
	for i in drop:
		var r: Array = _ring[i]
		var key := "%s|%s" % [r[3], r[2]]
		if not _counts.has(key) and _counts.size() >= COUNT_KEYS_MAX:
			key = "*|%s" % r[2]
		_counts[key] = int(_counts.get(key, 0)) + 1
		if int(r[7]) >= HIST_WEIGHT:
			_hist.append("d%d %s: %s" % [int(r[1]), r[2], r[6] if String(r[6]) != "" else r[5]])
	_ring = _ring.slice(drop)
	_dropped += drop
	if _hist.size() > HISTORIC_MAX:
		_hist = _hist.slice(_hist.size() - HISTORIC_MAX)


## Static entry for realm modules: no-op when `hub` has no events module.
static func log_to(h: Variant, kind: String, where: Variant, actors: Array, cause: String, outcome: String, weight := 1) -> void:
	if h == null:
		return
	var ev: Variant = h.mod("events")
	if ev != null:
		ev.record(kind, where, actors, cause, outcome, weight)


## Static entry for sim scripts (family, life_courses ...): writes to Life.realm's log when it exists.
static func emit(kind: String, where: Variant, actors: Array, cause: String, outcome: String, weight := 1) -> void:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return
	var life: Node = (loop as SceneTree).root.get_node_or_null("Life")
	if life == null:
		return
	var h: Variant = life.get("realm")
	if h != null:
		log_to(h, kind, where, actors, cause, outcome, weight)


# ------------------------------------------------------------------ reading

func size() -> int:
	return _ring.size()


## Events written since the game began (live + archived).
func total() -> int:
	var t := 0
	for k: Variant in _totals:
		t += int(_totals[k])
	return t


static func _row(r: Array) -> Dictionary:
	return {"id": "ev:%d" % int(r[0]), "n": int(r[0]), "day": int(r[1]), "kind": r[2], "where": r[3], "actors": r[4], "cause": r[5],
		"outcome": r[6], "weight": int(r[7])}


## Newest first.
func recent(limit := 20) -> Array:
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and out.size() < limit:
		out.append(_row(_ring[i]))
		i -= 1
	return out


## Events written after number `n` (oldest first), the ones a daily reader has not seen yet. Reads only the new tail of the ring.
func after(n: int) -> Array:
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and int(_ring[i][0]) > n:
		out.append(_row(_ring[i]))
		i -= 1
	out.reverse()
	return out


## Events whose actors include `actor` (a persistent id or a legacy key), newest first.
func by_actor(actor: String, limit := 20) -> Array:
	var reg: RefCounted = hub.mod("registry") if hub != null else null
	var key: String = reg.resolve(actor) if reg != null else actor
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and out.size() < limit:
		if (_ring[i][4] as Array).has(key):
			out.append(_row(_ring[i]))
		i -= 1
	return out


## Events at a place (persistent id or legacy key), newest first.
func at(where: String, limit := 20) -> Array:
	var reg: RefCounted = hub.mod("registry") if hub != null else null
	var key: String = reg.resolve(where) if reg != null else where
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and out.size() < limit:
		if _ring[i][3] == key:
			out.append(_row(_ring[i]))
		i -= 1
	return out


func of_kind(kind: String, limit := 20) -> Array:
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and out.size() < limit:
		if _ring[i][2] == kind:
			out.append(_row(_ring[i]))
		i -= 1
	return out


func since(day: int) -> Array:
	var out: Array = []
	var i := _ring.size() - 1
	while i >= 0 and int(_ring[i][1]) >= day:
		out.append(_row(_ring[i]))
		i -= 1
	return out


## How many events of `kind` ("" = any) happened at `where` ("" = anywhere), archived ones included.
func count(kind := "", where := "") -> int:
	var reg: RefCounted = hub.mod("registry") if hub != null else null
	var wk: String = (reg.resolve(where) if reg != null else where) if where != "" else ""
	var c := 0
	if wk == "":
		if kind == "":
			return total()
		return int(_totals.get(kind, 0))
	for r: Array in _ring:
		if r[3] == wk and (kind == "" or r[2] == kind):
			c += 1
	for k: Variant in _counts:
		var parts := String(k).split("|")
		if parts[0] == wk and (kind == "" or parts[1] == kind):
			c += int(_counts[k])
	return c


func historic() -> Array:
	return _hist.duplicate()


## Records folded away so far.
func archived() -> int:
	return _dropped


# ------------------------------------------------------------------ module hooks

func serialize() -> Dictionary:
	if _dirty or _ser.is_empty():
		_ser = {"ring": _ring.duplicate(true), "counts": _counts.duplicate(), "tot": _totals.duplicate(), "hist": _hist.duplicate(),
			"own": _own_n, "drop": _dropped}
		_dirty = false
	return _ser


func deserialize(d: Dictionary) -> void:
	_ring = []
	_counts = {}
	_totals = {}
	_hist = []
	_ser = {}
	_dirty = true
	var rg: Variant = d.get("ring", [])
	if rg is Array:
		for r: Variant in rg:
			if r is Array and (r as Array).size() >= 8:
				var a: Array = r
				var acts: Array = []
				for x: Variant in (a[4] as Array if a[4] is Array else []):
					acts.append(String(x))
				_ring.append([int(a[0]), int(a[1]), String(a[2]), String(a[3]), acts, String(a[5]), String(a[6]), int(a[7])])
		if _ring.size() > CAP:
			_ring = _ring.slice(_ring.size() - CAP)
	var c: Variant = d.get("counts", {})
	if c is Dictionary:
		for k: Variant in c:
			_counts[String(k)] = int(c[k])
	var t: Variant = d.get("tot", {})
	if t is Dictionary:
		for k: Variant in t:
			_totals[String(k)] = int(t[k])
	var h: Variant = d.get("hist", [])
	if h is Array:
		for s: Variant in h:
			_hist.append(String(s))
	_own_n = int(d.get("own", 0))
	_dropped = int(d.get("drop", 0))
