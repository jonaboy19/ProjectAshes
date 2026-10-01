extends RefCounted
## Door state machine as pure data (one instance per door) plus a static registry. The node side
## (scripts/interiors/interior_door.gd) owns an instance, animates `open_amount` with a Tween only while the
## door moves, and keeps its scene swap as the result of use("open").
##
## States: CLOSED, OPENING, OPEN, CLOSING, LOCKED, JAMMED, BROKEN. Locked is derived from the shared lock
## (locks.gd): a closed door whose lock is locked is LOCKED. Persistence (WorldState, delta from defaults):
## {open: bool, broken: bool, jammed: bool}; the locked flag lives with the lock.
## NPC routing: blocked_for(holder) is what street routing and hiding ask (TDM "forbidden area" idea):
## a locked door blocks everyone without its key; a jammed door blocks everyone; a broken one nobody.
## Verb priority: open > unlock (key) > lockpick > examine > break.

const Locks := preload("res://scripts/world/locks.gd")
const WorldState := preload("res://scripts/world/world_state.gd")

enum State { CLOSED, OPENING, OPEN, CLOSING, LOCKED, JAMMED, BROKEN }
const STATE_NAMES := ["closed", "opening", "open", "closing", "locked", "jammed", "broken"]
const SWING_SECONDS := 0.5
const DEFAULTS := {"open": false, "broken": false, "jammed": false}
## Loudness (m) of a door being forced / slammed (Perception.SOUND_LOUDNESS: BREAK_WOOD, DOOR_SLAM).
const NOISE_BREAK := 5       # Perception.Sound.BREAK_WOOD
const NOISE_SLAM := 3        # Perception.Sound.DOOR_SLAM
const NOISE_PICK := 4        # Perception.Sound.LOCKPICK

var id := ""
var pos := Vector2.ZERO
var sid := -1
var state := State.CLOSED
var open_amount := 0.0
var lock_id := ""
## The household lot this door belongs to (Vector2.INF = public / nobody's).
var owner_home := Vector2.INF
var health := 3
var broken := false
var jammed := false
var _target := 0.0

# ------------------------------------------------------------------ registry
static var _doors := {}


static func reset() -> void:
	_doors.clear()


static func register(d: RefCounted) -> void:
	_doors[d.get("id")] = d


static func unregister(door_id: String) -> void:
	_doors.erase(door_id)


static func get_door(door_id: String) -> RefCounted:
	return _doors.get(door_id)


static func count() -> int:
	return _doors.size()


## The registered door within `radius` of `p` (null when none).
static func door_near(p: Vector2, radius := 2.5) -> RefCounted:
	var best: RefCounted = null
	var best_d := radius * radius
	for k: String in _doors:
		var d: RefCounted = _doors[k]
		var dd := (d.get("pos") as Vector2).distance_squared_to(p)
		if dd <= best_d:
			best_d = dd
			best = d
	return best


## Key id convention of a household lot: the same string names the lock and the key item.
static func lot_key(lot_pos: Vector2) -> String:
	return "lot:%d_%d" % [roundi(lot_pos.x), roundi(lot_pos.y)]


## Stable id: "<settlement>/door/<x>_<z>" from the plan's lot position (plans are deterministic).
static func make_id(settlement: String, lot_pos: Vector2) -> String:
	return "%s/door/%d_%d" % [settlement, roundi(lot_pos.x), roundi(lot_pos.y)]


# ------------------------------------------------------------------ instance
## Create a door and read its saved state silently (no tween, no sound).
static func create(door_id: String, at: Vector2, p_lock := "", p_owner := Vector2.INF, ws: RefCounted = null) -> RefCounted:
	var d: RefCounted = (load("res://scripts/world/door_model.gd") as GDScript).new()
	d.set("id", door_id)
	d.set("pos", at)
	d.set("lock_id", p_lock)
	d.set("owner_home", p_owner)
	d.call("load_state", ws)
	return d


func load_state(ws: RefCounted = null) -> void:
	var store := ws if ws != null else WorldState.shared()
	var st: Dictionary = store.call("get_state", id, DEFAULTS)
	broken = bool(st["broken"])
	jammed = bool(st["jammed"])
	open_amount = 1.0 if bool(st["open"]) else 0.0
	_target = open_amount
	state = State.OPEN if open_amount > 0.5 else State.CLOSED
	_sync_state()


func save_state(ws: RefCounted = null) -> void:
	var store := ws if ws != null else WorldState.shared()
	store.call("set_state", id, {"open": state == State.OPEN or state == State.OPENING, "broken": broken, "jammed": jammed}, DEFAULTS)


## Reconcile `state` with broken / jammed / the shared lock (never while swinging).
func _sync_state() -> void:
	if broken:
		state = State.BROKEN
		return
	if jammed and state in [State.CLOSED, State.LOCKED, State.JAMMED]:
		state = State.JAMMED
		return
	if state == State.CLOSED or state == State.LOCKED:
		state = State.LOCKED if (lock_id != "" and Locks.is_locked(lock_id)) else State.CLOSED


func is_locked() -> bool:
	return state == State.LOCKED


func is_open() -> bool:
	return state == State.OPEN or state == State.OPENING or state == State.BROKEN


## Street routing / hiding: can this holder not go through?
func blocked_for(h: Dictionary) -> bool:
	match state:
		State.BROKEN:
			return false
		State.JAMMED:
			return true
		State.LOCKED:
			return not Locks.has_key(h, lock_id)
	return false


## Ordered verbs for `h` (Locks.holder): [{id, label, enabled, reason}].
func verbs(h: Dictionary) -> Array:
	var out: Array = []
	match state:
		State.CLOSED, State.OPENING:
			out.append({"id": "open", "label": "Open", "enabled": true, "reason": ""})
			if lock_id != "" and Locks.has_lock(lock_id) and Locks.has_key(h, lock_id):
				out.append({"id": "lock", "label": "Lock", "enabled": true, "reason": ""})
		State.OPEN, State.CLOSING:
			out.append({"id": "close", "label": "Close", "enabled": true, "reason": ""})
		State.LOCKED:
			var key_ok := Locks.has_key(h, lock_id)
			out.append({"id": "open", "label": "Locked", "enabled": false, "reason": "It is locked."})
			out.append({"id": "unlock", "label": "Unlock", "enabled": key_ok, "reason": "" if key_ok else "You have no key."})
			var pick_ok := bool(h.get("lockpick", false))
			out.append({"id": "lockpick", "label": "Pick lock", "enabled": pick_ok, "reason": "" if pick_ok else "You need a lockpick."})
		State.JAMMED:
			out.append({"id": "open", "label": "Jammed", "enabled": false, "reason": "It is stuck fast."})
		State.BROKEN:
			out.append({"id": "open", "label": "Pass", "enabled": true, "reason": ""})
	out.append({"id": "examine", "label": "Examine", "enabled": true, "reason": ""})
	if state != State.BROKEN:
		out.append({"id": "break", "label": "Break down", "enabled": true, "reason": ""})
	return out


## Do `verb`. Returns {ok, reason, noise: Perception.Sound or -1, crime: "" or crime kind (owned door forced),
## evidence: Evidence.Kind or -1}. The node plays tweens/sounds and reports the noise and crime.
func use(verb: String, h: Dictionary) -> Dictionary:
	var res := {"ok": false, "reason": "", "noise": -1, "crime": "", "evidence": -1}
	match verb:
		"open":
			match state:
				State.CLOSED:
					_begin_swing(1.0)
					res["ok"] = true
				State.BROKEN, State.OPEN, State.OPENING:
					res["ok"] = true
				State.LOCKED:
					res["reason"] = "It is locked."
				State.JAMMED:
					res["reason"] = "It is stuck fast."
				_:
					res["reason"] = "It is moving."
		"close":
			if state == State.OPEN or state == State.OPENING:
				_begin_swing(0.0)
				res["ok"] = true
				res["noise"] = -1
		"unlock":
			if state != State.LOCKED:
				res["ok"] = true
			elif Locks.unlock(lock_id, h):
				state = State.CLOSED
				res["ok"] = true
			else:
				res["reason"] = "You have no key."
		"lock":
			if state == State.CLOSED and lock_id != "" and Locks.has_key(h, lock_id):
				Locks.set_locked(lock_id, true)
				state = State.LOCKED
				res["ok"] = true
		"lockpick":
			if state != State.LOCKED:
				res["ok"] = true
			else:
				var r := Locks.try_pick(lock_id, h)
				res["noise"] = int(r["noise"])
				res["ok"] = bool(r["ok"])
				res["reason"] = String(r.get("reason", "" if bool(r["ok"]) else "The pick slips."))
				if bool(r["ok"]):
					state = State.CLOSED
				elif owner_home != Vector2.INF:
					res["crime"] = ""      # a failed attempt is noise only; being seen is perception's job
		"break":
			if state != State.BROKEN:
				health -= 1
				res["noise"] = NOISE_BREAK
				res["ok"] = true
				if health <= 0:
					broken = true
					open_amount = 1.0
					_target = 1.0
					state = State.BROKEN
					res["evidence"] = 6      # Evidence.Kind.BROKEN_DOOR
					if owner_home != Vector2.INF:
						res["crime"] = "burglary"
				else:
					res["reason"] = "The door shudders."
		"examine":
			res["ok"] = true
			res["reason"] = STATE_NAMES[state]
	save_state()
	return res


func _begin_swing(to: float) -> void:
	_target = to
	state = State.OPENING if to > open_amount else State.CLOSING
	if is_equal_approx(open_amount, to):
		_settle()


## Advance the swing by `dt` seconds (the node calls this only while moving, or lets a Tween do it and calls
## settle()). Returns true while still moving.
func step(dt: float) -> bool:
	if state != State.OPENING and state != State.CLOSING:
		return false
	open_amount = move_toward(open_amount, _target, dt / SWING_SECONDS)
	if is_equal_approx(open_amount, _target):
		_settle()
		return false
	return true


func target_amount() -> float:
	return _target


## The swing finished (Tween callback or step): land in OPEN or CLOSED(/LOCKED).
func settle() -> void:
	_settle()


func _settle() -> void:
	open_amount = _target
	state = State.OPEN if _target > 0.5 else State.CLOSED
	_sync_state()
	save_state()
