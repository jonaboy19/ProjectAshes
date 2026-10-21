extends RefCounted
## MW-41 reaction CONTRACT (frozen): the AI side asks for an abstract reaction, the animation side maps it to clips/LookAt.
## No clip names or blend values live here (Codex owns those). Request cost: a few packed-array writes, no allocation.
##
## Rules (see can_preempt):
##  - A request lands on its LAYER. Different layers coexist (a head glance while stepping aside).
##  - Same layer: a strictly higher PRIORITY preempts; equal or lower waits until the current one expires.
##  - FLEE is exclusive: while it runs only a higher priority (none today) may preempt, on any layer.
##  - keeps_activity == true: the animation layer adapts OVER the current activity (additive / short displacement) and the
##    activity resumes by itself. false (confront, warn, call_guard, flee): the activity is paused; RETURN_TO_WORK resumes it.

enum Kind { NONE, GLANCE, LOOK_AWAY, STEP_BACK, STEP_ASIDE, BOW, FLINCH, CONFRONT, WAVE, WARN, CALL_GUARD, FLEE, RETURN_TO_WORK }
enum Layer { HEAD, UPPER, LOCO, BODY }

const NAMES := ["none", "glance", "look_away", "step_back", "step_aside", "bow", "flinch", "confront", "wave", "warn", "call_guard", "flee", "return_to_work"]
const PRIORITY := [0, 1, 1, 3, 3, 2, 4, 5, 2, 5, 6, 7, 1]
const DURATION_MS := [0, 1200, 1500, 900, 1100, 1400, 600, 3000, 1500, 2500, 3500, 6000, 800]
const LAYER_OF := [0, 0, 0, 2, 2, 1, 1, 3, 1, 3, 3, 2, 2]
const KEEPS_ACTIVITY := [true, true, true, true, true, true, true, false, true, false, false, false, true]
const EXCLUSIVE_KIND := 11
const PER_SLOT := 4          # one current request per layer
const PENDING := 6           # ring of unconsumed requests per slot
const MAX_SLOTS := 64

var cur_kind := PackedInt32Array()
var cur_until := PackedInt32Array()
var cur_target := PackedInt32Array()
var pend := PackedInt32Array()       # kind | (target & 0xFFFF) << 8
var pend_n := PackedInt32Array()
var accepted := 0
var rejected := 0


func _init() -> void:
	cur_kind.resize(MAX_SLOTS * PER_SLOT)
	cur_until.resize(MAX_SLOTS * PER_SLOT)
	cur_target.resize(MAX_SLOTS * PER_SLOT)
	pend.resize(MAX_SLOTS * PENDING)
	pend_n.resize(MAX_SLOTS)
	cur_kind.fill(0)
	cur_until.fill(-1)
	cur_target.fill(-1)


static func name_of(kind: int) -> String:
	return NAMES[kind] if kind >= 0 and kind < NAMES.size() else "none"


static func kind_from_name(n: String) -> int:
	return NAMES.find(n) if NAMES.has(n) else 0


## Pure rule: may `incoming` replace what is running on its layer at `now`?
static func can_preempt(cur: int, cur_until_ms: int, incoming: int, now: int) -> bool:
	if cur == Kind.NONE or now >= cur_until_ms:
		return true
	return PRIORITY[incoming] > PRIORITY[cur]


func request(slot: int, kind: int, target: int, now: int, priority_boost := 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or kind <= 0 or kind >= NAMES.size():
		return false
	# exclusive flee blocks everything on every layer except a higher priority
	for l in PER_SLOT:
		var i := slot * PER_SLOT + l
		if cur_kind[i] == EXCLUSIVE_KIND and now < cur_until[i] and PRIORITY[kind] + priority_boost <= PRIORITY[EXCLUSIVE_KIND]:
			rejected += 1
			return false
	var idx := slot * PER_SLOT + int(LAYER_OF[kind])
	if not can_preempt(cur_kind[idx], cur_until[idx], kind, now) and priority_boost <= 0:
		rejected += 1
		return false
	cur_kind[idx] = kind
	cur_until[idx] = now + int(DURATION_MS[kind])
	cur_target[idx] = target
	if kind == Kind.RETURN_TO_WORK:
		# resuming the activity ends the pausing layers
		for l in [Layer.BODY]:
			cur_kind[slot * PER_SLOT + l] = 0
	var n := pend_n[slot]
	pend[slot * PENDING + (n % PENDING)] = kind | ((target & 0xFFFF) << 8)
	pend_n[slot] = mini(n + 1, PENDING)
	accepted += 1
	return true


## What is running on `layer` now (Kind.NONE if expired).
func current(slot: int, layer: int, now: int) -> int:
	var i := slot * PER_SLOT + layer
	return cur_kind[i] if now < cur_until[i] else 0


func current_target(slot: int, layer: int, now: int) -> int:
	var i := slot * PER_SLOT + layer
	return cur_target[i] if now < cur_until[i] else -1


## True while any running reaction pauses the activity (adapter: hold the schedule/utility brain action).
func pausing_activity(slot: int, now: int) -> bool:
	for l in PER_SLOT:
		var i := slot * PER_SLOT + l
		if now < cur_until[i] and cur_kind[i] != 0 and not KEEPS_ACTIVITY[cur_kind[i]]:
			return true
	return false


func pending_count(slot: int) -> int:
	return pend_n[slot]


## Pops the oldest unconsumed request as [kind, target], or [] when none.
func pop(slot: int) -> Array:
	var n := pend_n[slot]
	if n <= 0:
		return []
	var first := 0
	var v := pend[slot * PENDING + first]
	for k in range(1, n):
		pend[slot * PENDING + k - 1] = pend[slot * PENDING + k]
	pend_n[slot] = n - 1
	var t := (v >> 8) & 0xFFFF
	return [v & 0xFF, -1 if t == 0xFFFF else t]


func clear_slot(slot: int) -> void:
	for l in PER_SLOT:
		cur_kind[slot * PER_SLOT + l] = 0
		cur_until[slot * PER_SLOT + l] = -1
	pend_n[slot] = 0
