extends RefCounted
## Alert sharing between near-NPCs (docs/research/MINING_PERCEPTION_INTERACTION.md 2.5 / 4.2, own implementation).
##
## An ALARMED guard calls out: everyone within SHOUT_RADIUS who can hear it (the radius shrinks through walls with the
## same occlusion classes as sounds, Perception.OCC_MULT) is told once per event id. Told guards go to SEARCHING at the
## last known position (alert x TELL_DEGRADE, so a relay never reaches ALARMED and cannot chain for ever); citizens
## are rattled (at most SUSPICIOUS) and duck into hiding. Every shout also raises the settlement's `guard_alert`
## (0..3, decays); at LOCKDOWN_LEVEL the town goes to ground: TownMood sets `lockdown` (curfew schedule flag) and
## micro_events pulls the market shutters down for a while, then raises them again.
##
## Static, tiny, no nodes: listeners are plain dictionaries {person, pos, guard, node (optional, duck-typed
## hear_alarm(at, event_id, guard))} so tests can drive it without a scene.

const Perception := preload("res://scripts/population/perception.gd")
const Search := preload("res://scripts/population/search.gd")
const NPC_WORLD := "res://scripts/population/npc_world.gd"

const SHOUT_RADIUS := 32.0
const SHOUT_COOLDOWN_MS := 6000
const TELL_DEGRADE := 0.6
## Civilians told of an alarm never go past this (suspicious): they hide, they do not hunt.
const CIVILIAN_CAP := 9.5
const MAX_LEVEL := 3
const LOCKDOWN_LEVEL := 2
## guard_alert falls one level per this long without a new shout.
const DECAY_MS := 60000
const POST_LOCKDOWN_MS := 90000

static var _level := {}                 # sid -> [level, last_raise_ms]
static var _lock_end := {}              # sid -> ms the lockdown ended
static var _shout_ms := {}              # person -> last shout ms
static var shouts := 0                  # QA


static func reset() -> void:
	_level.clear()
	_lock_end.clear()
	_shout_ms.clear()
	shouts = 0


# ================================================================ settlement guard_alert
## 0..MAX_LEVEL now (decays one per DECAY_MS since the last raise).
static func level(sid: int, now_ms: int) -> int:
	if not _level.has(sid):
		return 0
	var row: Array = _level[sid]
	var lv := int(row[0]) - int(float(now_ms - int(row[1])) / float(DECAY_MS))
	lv = clampi(lv, 0, MAX_LEVEL)
	if lv < LOCKDOWN_LEVEL and int(row[0]) >= LOCKDOWN_LEVEL and not _lock_end.has(sid):
		_lock_end[sid] = int(row[1]) + (int(row[0]) - LOCKDOWN_LEVEL + 1) * DECAY_MS
	return lv


static func raise(sid: int, now_ms: int, by := 1) -> int:
	if sid < 0:
		return 0
	var cur := level(sid, now_ms)
	var nl := clampi(cur + by, 0, MAX_LEVEL)
	_level[sid] = [nl, now_ms]
	if nl >= LOCKDOWN_LEVEL:
		_lock_end.erase(sid)
	return nl


static func lockdown(sid: int, now_ms: int) -> bool:
	return level(sid, now_ms) >= LOCKDOWN_LEVEL


## The lockdown ended recently (shops may reopen now).
static func post_lockdown(sid: int, now_ms: int) -> bool:
	if lockdown(sid, now_ms) or not _lock_end.has(sid):
		return false
	return now_ms - int(_lock_end[sid]) < POST_LOCKDOWN_MS


# ================================================================ shouting
static func can_shout(person: int, now_ms: int) -> bool:
	return now_ms - int(_shout_ms.get(person, -100000)) >= SHOUT_COOLDOWN_MS


## Effective hearing radius from `from` to `listener`: SHOUT_RADIUS x the occlusion class multiplier
## (same cell 1.0, open door .7, closed door .35, other building .2). `graph` (StreetGraph) is optional.
static func hearing_radius(graph: RefCounted, from: Vector2, listener: Vector2) -> float:
	return SHOUT_RADIUS * float(Perception.OCC_MULT[Perception.occlusion_class(graph, from, listener)])


## Which of `listeners` hear a shout from `from` (the caller itself is skipped). Returns the listener dictionaries.
static func reached(from: Vector2, listeners: Array, caller := -1, graph: RefCounted = null) -> Array:
	var out: Array = []
	for l: Dictionary in listeners:
		if int(l.get("person", -1)) == caller:
			continue
		var pos: Vector2 = l["pos"]
		var r := hearing_radius(graph, from, pos)
		if from.distance_squared_to(pos) <= r * r:
			out.append(l)
	return out


## `caller` (an alarmed guard at `from`, alert value `alert_value`) shouts about `last_known`. Tells everyone in earshot
## once per `event_id`: guards -> SEARCHING at last_known, citizens -> rattled and hiding. Raises the settlement's
## guard_alert and files a CALL_FOR_HELP incident. Returns {"told": [persons], "guards": n, "citizens": n}.
static func shout(caller: int, from: Vector2, last_known: Vector2, alert_value: float, event_id: int, sid: int, now_ms: int,
		listeners: Array, graph: RefCounted = null) -> Dictionary:
	var out := {"told": [], "guards": 0, "citizens": 0, "shouted": false}
	if not can_shout(caller, now_ms):
		return out
	_shout_ms[caller] = now_ms
	shouts += 1
	out["shouted"] = true
	var eid := event_id if event_id != 0 else Perception.new_event_id()
	raise(sid, now_ms)
	(load(NPC_WORLD) as GDScript).call("report", 7, from, SHOUT_RADIUS, 8.0, 1.0, sid)       # Kind.CALL_FOR_HELP
	var gain := maxf(alert_value, Perception.T_ALARMED) * TELL_DEGRADE
	for l: Dictionary in reached(from, listeners, caller, graph):
		var person := int(l["person"])
		var slot := Perception.slot_of(person)
		if slot >= 0 and Perception.knows(slot, eid) and Perception.cls[slot] >= Perception.Cls.SUSPICIOUS:
			continue            # already knows this alarm: no re-reaction
		var is_guard: bool = bool(l.get("guard", false))
		if slot >= 0:
			if is_guard:
				if Perception.stimulate(slot, gain, last_known, eid, now_ms):
					Perception.set_class_at_least(slot, Perception.Cls.SEARCHING, last_known, now_ms)
			else:
				var room := clampf(CIVILIAN_CAP - Perception.alert[slot], 0.0, gain)
				if Perception.stimulate(slot, room, last_known, eid, now_ms):
					Perception.set_class_at_least(slot, Perception.Cls.SUSPICIOUS, last_known, now_ms)
		(out["told"] as Array).append(person)
		out["guards" if is_guard else "citizens"] = int(out["guards" if is_guard else "citizens"]) + 1
		var node: Variant = l.get("node")
		if node != null and is_instance_valid(node) and (node as Object).has_method("hear_alarm"):
			(node as Object).call("hear_alarm", last_known, eid, is_guard)
	if int(out["guards"]) > 0:
		Search.begin(last_known, sid, now_ms, eid)
	return out


# ================================================================ persistence
## guard_alert per town as [sid, level, ms since the last raise] (clock-relative, the session clock restarts on load).
static func serialize(now_ms: int) -> Array:
	var out: Array = []
	for sid: int in _level:
		var lv := level(sid, now_ms)
		if lv > 0:
			out.append([sid, int(_level[sid][0]), now_ms - int(_level[sid][1])])
	return out


static func deserialize(rows: Variant, now_ms: int) -> void:
	_level.clear()
	_lock_end.clear()
	if not rows is Array:
		return
	for r: Variant in rows:
		if not r is Array or (r as Array).size() < 3:
			continue
		var a: Array = r
		_level[int(a[0])] = [clampi(int(a[1]), 0, MAX_LEVEL), now_ms - maxi(int(a[2]), 0)]
