extends RefCounted
## Crime witnessing as a task, not a roll (docs/research/MINING_PERCEPTION_INTERACTION.md 4.4).
##
## NpcWorld.report_crime asks perception who actually SAW the culprit (cone, light, distance, stance, line),
## and opens a case with those witnesses. The crime reaches Society.commit_crime only when
##  - a witness reaches a guard (deliver) - at once, or
##  - TIMEOUT_MS passes with at least one witness still running (the town crier / a shout carries),
## and never when every witness was silenced (killed, knocked out, bribed) or gave up (fled, hid): then the
## case stays "unreported" and only the evidence on the ground (evidence.gd) can raise it later.
##
## Pure static data (no nodes), clock passed in so tests can step time. Society is duck-typed:
## anything with commit_crime(kind, sid, witnesses, opts) -> Dictionary.

const Perception := preload("res://scripts/population/perception.gd")

enum W { RUNNING, DELIVERED, SILENCED, LOST }
const WNAMES := ["running", "delivered", "silenced", "lost"]
const MAX_CASES := 8
const MAX_WITNESSES := 12
const TIMEOUT_MS := 25000
## A running witness within this many metres of a guard has reported.
const REPORT_RADIUS := 8.0
## Visibility at or above which a person SAW the culprit (below: only heard).
const SEEN_VIS := 0.12

## Each case: {id, kind, sid, pos, t0, deadline, status: pending|committed|unreported, culprit_player,
##   ws: [{id: String, person: int, vis: float, state: int}], result: Dictionary}
static var cases: Array = []
static var _next := 1
## Last committed result (QA / callers that want the Society answer).
static var last_result := {}


static func reset() -> void:
	cases.clear()
	_next = 1
	last_result = {}


## Visibility of the culprit at `culprit_pos` for one candidate witness (0 when not seen).
## `clear` is the line check (StreetGraph.clear_line or a ray) the caller already did.
static func sight(npc_pos: Vector2, facing: Vector2, acuity: float, culprit_pos: Vector2, light: float, stance: float, clear := true) -> float:
	if not clear:
		return 0.0
	return Perception.vis(npc_pos, facing, culprit_pos, light, stance, false, acuity)


## Anonymous witness id when the villager is not a Society notable.
static func witness_id(sid: int, person: int) -> String:
	return "anon:%d:%d" % [sid, person]


## Open a case. `witnesses`: [{id, person, vis, guard}] - only entries with vis >= SEEN_VIS are witnesses.
## Guards who saw it have reported already. Returns the case id (0 when nobody saw: the crime is unreported
## and no case is kept). `soc` may be null (then nothing can commit; used by tests of the task itself).
static func begin(kind: String, sid: int, pos: Vector2, witnesses: Array, now_ms: int, soc: RefCounted = null, culprit_player := true) -> int:
	var ws: Array = []
	for w: Dictionary in witnesses:
		if float(w.get("vis", 0.0)) < SEEN_VIS or ws.size() >= MAX_WITNESSES:
			continue
		var guard: bool = bool(w.get("guard", false))
		ws.append({"id": String(w.get("id", "")), "person": int(w.get("person", -1)), "vis": float(w["vis"]),
			"state": W.DELIVERED if guard else W.RUNNING})
	if ws.is_empty():
		return 0
	var c := {"id": _next, "kind": kind, "sid": sid, "pos": pos, "t0": now_ms, "deadline": now_ms + TIMEOUT_MS,
		"status": "pending", "culprit_player": culprit_player, "ws": ws, "result": {}}
	_next += 1
	cases.append(c)
	if cases.size() > MAX_CASES:
		cases.pop_front()
	_resolve(c, now_ms, soc)
	return int(c["id"])


static func case_of(case_id: int) -> Dictionary:
	for c: Dictionary in cases:
		if int(c["id"]) == case_id:
			return c
	return {}


static func status(case_id: int) -> String:
	var c := case_of(case_id)
	return String(c.get("status", "none"))


## True while `person` is a running witness of a pending case.
static func is_running(person: int) -> bool:
	for c: Dictionary in cases:
		if c["status"] != "pending":
			continue
		for w: Dictionary in c["ws"]:
			if int(w["person"]) == person and int(w["state"]) == W.RUNNING:
				return true
	return false


static func pending_count() -> int:
	var n := 0
	for c: Dictionary in cases:
		if c["status"] == "pending":
			n += 1
	return n


static func _set_state(person: int, state: int, now_ms: int, soc: RefCounted) -> int:
	var changed := 0
	for c: Dictionary in cases:
		if c["status"] != "pending":
			continue
		for w: Dictionary in c["ws"]:
			if int(w["person"]) == person and int(w["state"]) == W.RUNNING:
				w["state"] = state
				changed += 1
		if changed > 0:
			_resolve(c, now_ms, soc)
	return changed


## `person` (a running witness) reached a guard / was heard by one: the report is delivered.
static func deliver(person: int, now_ms: int, soc: RefCounted = null) -> bool:
	return _set_state(person, W.DELIVERED, now_ms, soc) > 0


## `person` was killed, knocked out or bribed before reporting.
static func silence(person: int, now_ms: int, soc: RefCounted = null) -> bool:
	return _set_state(person, W.SILENCED, now_ms, soc) > 0


## `person` gave up (fled indoors, lost track): the report will not be made by them.
static func abandon(person: int, now_ms: int, soc: RefCounted = null) -> bool:
	return _set_state(person, W.LOST, now_ms, soc) > 0


## Timeouts: a pending case whose deadline passed with a running witness commits (town crier).
static func tick(now_ms: int, soc: RefCounted = null) -> void:
	for c: Dictionary in cases:
		if c["status"] == "pending":
			_resolve(c, now_ms, soc)


static func _resolve(c: Dictionary, now_ms: int, soc: RefCounted) -> void:
	if c["status"] != "pending":
		return
	var running := 0
	var delivered := 0
	for w: Dictionary in c["ws"]:
		match int(w["state"]):
			W.RUNNING: running += 1
			W.DELIVERED: delivered += 1
	if delivered > 0:
		_commit(c, now_ms, soc, true)
	elif running == 0:
		c["status"] = "unreported"
	elif now_ms >= int(c["deadline"]):
		_commit(c, now_ms, soc, false)


static func _commit(c: Dictionary, _now_ms: int, soc: RefCounted, only_delivered: bool) -> void:
	var ids: Array = []
	var vis: Array = []
	for w: Dictionary in c["ws"]:
		var st := int(w["state"])
		if st == W.DELIVERED or (not only_delivered and st == W.RUNNING):
			ids.append(String(w["id"]))
			vis.append(float(w["vis"]))
	c["status"] = "committed"
	c["witness_ids"] = ids
	if soc != null and bool(c["culprit_player"]):
		var res: Dictionary = soc.call("commit_crime", String(c["kind"]), int(c["sid"]), ids, {"vis": vis})
		c["result"] = res
		last_result = res
	else:
		c["result"] = {"ok": false}
