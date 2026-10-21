extends RefCounted
## MW-37/38/39/40 + J3: Reactive Presence for the near tier (tier 0, <= 24-48 bodies). ONE central batched manager that turns
## what bodies DO (player or NPC, same path: every body is a subject, every registered observer is an NPC) into stimuli, then
## runs a staged response per observer: notice -> check -> test -> decide -> act, with de-escalation and short memory.
## Builds on, does not replace: Perception (cone / light_term / hearing numbers), SocialPerception (status-dependent choice).
## Output is the abstract reaction contract (reaction_request.gd); keep the current activity unless escalated.
##
## Budget: far tiers never register (zero cost). tick() evaluates 1/STAGGER of the observers; per observer a distance^2
## gate rejects most bodies, <= ATT attention slots are kept, and at most one optional LOS callable per stare candidate.
## Deterministic: no randf(); chances come from hash(). Time is passed in (now_ms), never read.

const Perception := preload("res://scripts/population/perception.gd")
const SP := preload("res://scripts/realm/social_perception.gd")
const RR := preload("res://scripts/population/reaction_request.gd")

enum Stim { NONE, STARE, FOLLOW, BLOCK_DOOR, BUMP, RUN_CROWD, DRAWN_WEAPON, TRESPASS, TAKE_OBJECT, EAVESDROP, PUBLIC_MAGIC, KINDNESS, INSIGNIA, INJURED, REPEAT_VISIT }
const STIM_NAMES := ["none", "stare", "follow", "block_door", "bump", "run_crowd", "drawn_weapon", "trespass", "take_object", "eavesdrop", "public_magic", "kindness", "insignia", "injured", "repeat_visit"]
## Seconds of full-intensity stimulus to reach "decide" for a tolerance-1.0 observer.
const BASE_S := [0.0, 10.0, 12.0, 5.0, 1.0, 3.0, 2.5, 4.0, 1.5, 6.0, 4.0, 3.0, 5.0, 4.0, 3.0]
## How much the stimulus matters for ranking attention and for breaking through a busy mind.
const SEV := [0.0, 0.3, 0.6, 0.35, 0.8, 0.45, 1.0, 0.6, 0.7, 0.4, 0.6, 0.3, 0.5, 0.35, 0.3]
const POSITIVE := [false, false, false, false, false, false, false, false, false, false, false, true, false, true, true]
const URGENT := [false, false, false, false, true, false, true, false, true, false, false, false, false, false, false]

const F_RUNNING := 1
const F_DRAWN := 2
const F_PUBLIC := 4       # this body stands in a tavern/shop/temple (weapons are taboo)
const F_TRESPASS := 8
const F_CASTING := 16
const F_EAVES := 32
const F_CROUCH := 64
const F_GUARD := 128
const F_TALKING := 256

enum Stage { NONE, NOTICE, CHECK, TEST, DECIDE }
const STAGE_AT := [0.0, 0.2, 0.45, 0.7, 1.0]
const STAGE_MIN_MS := 700
const DROP_MS := 1500
const DECAY_PER_S := 0.1
const ACT_COOLDOWN_MS := 9000
const MEMORY_MS := 180000
const ATT := 2
const MAX_BODIES := 48
const STAGGER := 3
const RANGE_M := 20.0
const SIGHT_M := 20.0
const STARE_M := 12.0
const STARE_COS := 0.9
const CROWD_M := 4.0

var enabled := true
var stagger := STAGGER
var hour := 12
var light := 1.0
var los_fn: Callable
var requests: RefCounted = RR.new()
var sp: RefCounted = SP.new()
var record := false
var log: Array = []
var evals := 0
var pair_checks := 0
var los_calls := 0
var ticks := 0

var _idx := {}                       # id -> body index
var _free: Array[int] = []
var _n := 0
var id_of := PackedInt32Array()
var pos := PackedVector2Array()
var face := PackedVector2Array()
var head := PackedVector2Array()
var vel := PackedVector2Array()
var flags := PackedInt32Array()
var used := PackedByteArray()
var observer := PackedByteArray()
var acuity := PackedFloat32Array()
var busy := PackedFloat32Array()
var tol := PackedFloat32Array()      # personal tolerance multiplier, 0.5 .. 1.8
var dest := PackedVector2Array()
var last_eval := PackedInt32Array()
var data: Array = []                 # per body: SocialPerception dict (status, persona, kingdom, insignia, injury, ...)
var crowd_tick := PackedInt32Array()
var crowd_n := PackedInt32Array()
# attention slots (MAX_BODIES * ATT)
var a_subj := PackedInt32Array()
var a_kind := PackedInt32Array()
var a_level := PackedFloat32Array()
var a_stage := PackedInt32Array()
var a_stage_ms := PackedInt32Array()
var a_act_ms := PackedInt32Array()
var a_seen_ms := PackedInt32Array()
var a_acted := PackedByteArray()
var a_esc := PackedByteArray()       # reached CHECK or beyond: the NPC owes a return_to_work
var _doors := PackedVector2Array()
var _memory := {}                    # observer_id * 100003 + subject_id -> [strikes, last_ms]
var _visits := {}                    # same key -> count
var _observers: Array[int] = []
var _best_w := 0.0
var _best_k := 0
var _best_i := 0.0


func _init() -> void:
	for a in [id_of, flags, last_eval, crowd_tick, crowd_n]:
		a.resize(MAX_BODIES)
	pos.resize(MAX_BODIES)
	face.resize(MAX_BODIES)
	head.resize(MAX_BODIES)
	vel.resize(MAX_BODIES)
	dest.resize(MAX_BODIES)
	dest.fill(Vector2.INF)
	used.resize(MAX_BODIES)
	observer.resize(MAX_BODIES)
	acuity.resize(MAX_BODIES)
	busy.resize(MAX_BODIES)
	tol.resize(MAX_BODIES)
	crowd_tick.fill(-1)
	data.resize(MAX_BODIES)
	a_subj.resize(MAX_BODIES * ATT)
	a_kind.resize(MAX_BODIES * ATT)
	a_level.resize(MAX_BODIES * ATT)
	a_stage.resize(MAX_BODIES * ATT)
	a_stage_ms.resize(MAX_BODIES * ATT)
	a_act_ms.resize(MAX_BODIES * ATT)
	a_seen_ms.resize(MAX_BODIES * ATT)
	a_acted.resize(MAX_BODIES * ATT)
	a_esc.resize(MAX_BODIES * ATT)
	a_subj.fill(-1)
	last_eval.fill(0)
	for i in MAX_BODIES:
		_free.append(MAX_BODIES - 1 - i)


# ------------------------------------------------------------------ registry
## Adds or updates a body. Observers (NPCs that can react) pass opts {busy, acuity, tolerance 0..1, status, persona{}, kingdom, guard_near, ...}.
## Subjects without opts are just things that can be watched. `opts` keys are copied into the SocialPerception dict.
func set_body(id: int, p: Vector2, facing: Vector2, velocity := Vector2.ZERO, head_dir := Vector2.ZERO, flag_bits := 0) -> int:
	var i := _slot_for(id)
	if i < 0:
		return -1
	pos[i] = p
	face[i] = facing.normalized() if facing != Vector2.ZERO else face[i]
	head[i] = head_dir.normalized() if head_dir != Vector2.ZERO else face[i]
	vel[i] = velocity
	flags[i] = flag_bits
	return i


func _slot_for(id: int) -> int:
	if _idx.has(id):
		return _idx[id]
	if _free.is_empty():
		return -1
	var i: int = _free.pop_back()
	_idx[id] = i
	id_of[i] = id
	used[i] = 1
	observer[i] = 0
	acuity[i] = 1.0
	busy[i] = 0.0
	tol[i] = lerpf(0.5, 1.8, float(absi(hash([id, "tol"])) % 1000) / 1000.0)
	dest[i] = Vector2.INF
	flags[i] = 0
	last_eval[i] = 0
	face[i] = Vector2(0, 1)
	data[i] = {"id": str(id)}
	for k in ATT:
		_clear_att(i * ATT + k)
	_n += 1
	return i


## Marks a body as a reacting NPC and sets its traits. Keys: busy 0..1, acuity, tolerance 0..1 (else derived from id),
## plus any SocialPerception observer keys (status, persona, kingdom, perception, magic_sense, guard_near: bool).
func make_observer(id: int, opts := {}) -> void:
	var i := _slot_for(id)
	if i < 0:
		return
	if observer[i] == 0:
		observer[i] = 1
		_observers.append(i)
	if opts.has("busy"):
		busy[i] = clampf(float(opts["busy"]), 0.0, 1.0)
	if opts.has("acuity"):
		acuity[i] = float(opts["acuity"])
	if opts.has("tolerance"):
		tol[i] = lerpf(0.5, 1.8, clampf(float(opts["tolerance"]), 0.0, 1.0))
	var d: Dictionary = data[i]
	for k: String in opts:
		if k != "busy" and k != "acuity" and k != "tolerance":
			d[k] = opts[k]


## Extra SocialPerception facts about a subject (title_rank, insignia, origin, weapons, injury, aura_emit, ...).
func describe_subject(id: int, facts: Dictionary) -> void:
	var i := _slot_for(id)
	if i >= 0:
		(data[i] as Dictionary).merge(facts, true)


func set_busy(id: int, v: float) -> void:
	if _idx.has(id):
		busy[_idx[id]] = clampf(v, 0.0, 1.0)


func set_dest(id: int, p: Vector2) -> void:
	if _idx.has(id):
		dest[_idx[id]] = p


func add_door(p: Vector2) -> void:
	_doors.append(p)


func remove_body(id: int) -> void:
	if not _idx.has(id):
		return
	var i: int = _idx[id]
	for o in MAX_BODIES:
		for k in ATT:
			if a_subj[o * ATT + k] == i:
				_clear_att(o * ATT + k)
	for k in ATT:
		_clear_att(i * ATT + k)
	_observers.erase(i)
	_idx.erase(id)
	used[i] = 0
	observer[i] = 0
	_free.append(i)
	_n -= 1
	requests.clear_slot(i)


func clear() -> void:
	for id in _idx.keys():
		remove_body(id)
	_memory.clear()
	_visits.clear()
	_doors.clear()
	log.clear()


func slot_of(id: int) -> int:
	return _idx.get(id, -1)


func _clear_att(s: int) -> void:
	a_subj[s] = -1
	a_kind[s] = 0
	a_level[s] = 0.0
	a_stage[s] = 0
	a_stage_ms[s] = 0
	a_act_ms[s] = -100000
	a_seen_ms[s] = 0
	a_acted[s] = 0
	a_esc[s] = 0


# ------------------------------------------------------------------ queries (tests / debug / HUD)
func stage_of(observer_id: int, subject_id: int) -> int:
	var s := _att_of(slot_of(observer_id), slot_of(subject_id))
	return a_stage[s] if s >= 0 else 0


func level_of(observer_id: int, subject_id: int) -> float:
	var s := _att_of(slot_of(observer_id), slot_of(subject_id))
	return a_level[s] if s >= 0 else 0.0


func tracked_count(observer_id: int) -> int:
	var o := slot_of(observer_id)
	var c := 0
	for k in ATT:
		if o >= 0 and a_subj[o * ATT + k] >= 0:
			c += 1
	return c


func memory_strikes(observer_id: int, subject_id: int, now_ms: int) -> int:
	var m: Array = _memory.get(observer_id * 100003 + subject_id, [])
	return int(m[0]) if not m.is_empty() and now_ms - int(m[1]) < MEMORY_MS else 0


func visits(observer_id: int, subject_id: int) -> int:
	return int(_visits.get(observer_id * 100003 + subject_id, 0))


func _att_of(o: int, s: int) -> int:
	if o < 0 or s < 0:
		return -1
	for k in ATT:
		if a_subj[o * ATT + k] == s:
			return o * ATT + k
	return -1


func _log(o: int, kind: int, s: int, now: int, note := "") -> void:
	if record:
		if log.size() > 256:
			log.pop_front()
		log.append({"t": now, "obs": id_of[o], "subj": id_of[s], "reaction": RR.name_of(kind), "note": note})


# ------------------------------------------------------------------ discrete events
## Bump, taking an object, kindness, eavesdropping caught etc. `observer_id` -1 = everyone who perceives it within `radius`.
func report(stim: int, subject_id: int, strength := 1.0, now_ms := 0, observer_id := -1, radius := 12.0) -> int:
	var s := slot_of(subject_id)
	if s < 0:
		return 0
	var n := 0
	for o in _observers:
		if o == s or (observer_id >= 0 and id_of[o] != observer_id):
			continue
		var off := pos[s] - pos[o]
		if off.length_squared() > radius * radius:
			continue
		var sees := _sight(o, s, off, off.length())
		if sees <= 0.0 and off.length() > 1.5 and stim != Stim.BUMP:
			continue
		n += 1
		_feed(o, s, stim, clampf(strength, 0.0, 1.5), now_ms, true)
	return n


## Counts a visit of `subject` to the place `observer` keeps (shopkeeper, innkeeper); the Nth visit becomes a stimulus.
func note_visit(observer_id: int, subject_id: int, now_ms := 0) -> int:
	var key := observer_id * 100003 + subject_id
	var c: int = int(_visits.get(key, 0)) + 1
	_visits[key] = c
	if c >= 3:
		report(Stim.REPEAT_VISIT, subject_id, minf(0.25 * (c - 2), 1.0), now_ms, observer_id, 8.0)
	return c


## The subject apologises or makes amends: concern drops fast and a held act can end.
func apologise(subject_id: int, observer_id: int, now_ms := 0) -> void:
	var o := slot_of(observer_id)
	var a := _att_of(o, slot_of(subject_id))
	if a >= 0:
		a_level[a] *= 0.25
		a_acted[a] = 0
		a_stage_ms[a] = now_ms - STAGE_MIN_MS
		if a_stage[a] >= Stage.CHECK:
			requests.request(o, RR.Kind.RETURN_TO_WORK, id_of[slot_of(subject_id)], now_ms)


# ------------------------------------------------------------------ tick
## Call at ~10 Hz from the near-tier director (any rate works; each observer is evaluated every `stagger` calls).
func tick(now_ms: int) -> int:
	if not enabled or _observers.is_empty():
		return 0
	ticks += 1
	var done := 0
	for n in _observers.size():
		var o: int = _observers[n]
		if (n + ticks) % stagger != 0:
			continue
		var dt := clampf(float(now_ms - last_eval[o]) / 1000.0, 0.05, 2.0)
		last_eval[o] = now_ms
		_eval_observer(o, now_ms, dt)
		done += 1
	evals += done
	return done


func _eval_observer(o: int, now: int, dt: float) -> void:
	var cap := 2 - int(busy[o] >= 0.5) - int(busy[o] >= 0.85)
	var seen_mask := 0
	var cand_s := -1
	var cand_k := 0
	var cand_i := 0.0
	var cand_w := 0.0
	var cand2_s := -1
	var cand2_k := 0
	var cand2_i := 0.0
	var cand2_w := 0.0
	var po := pos[o]
	var a0 := o * ATT
	for s: int in _idx.values():
		if s == o:
			continue
		var off := pos[s] - po
		var d2 := off.length_squared()
		if d2 > RANGE_M * RANGE_M:
			continue
		pair_checks += 1
		_assess(o, s, off, d2, now)
		var a := a0 if a_subj[a0] == s else (a0 + 1 if a_subj[a0 + 1] == s else -1)
		if _best_k == 0:
			continue
		if a >= 0:
			_stimulate(o, s, a, _best_k, _best_i, dt, now)
			seen_mask |= 1 << a
			continue
		if _best_w > cand_w:
			cand2_s = cand_s
			cand2_k = cand_k
			cand2_i = cand_i
			cand2_w = cand_w
			cand_s = s
			cand_k = _best_k
			cand_i = _best_i
			cand_w = _best_w
		elif _best_w > cand2_w:
			cand2_s = s
			cand2_k = _best_k
			cand2_i = _best_i
			cand2_w = _best_w
	# decay / de-escalate slots not stimulated this eval
	for k in ATT:
		var a := o * ATT + k
		if a_subj[a] >= 0 and (seen_mask & (1 << a)) == 0:
			_decay(o, a, dt, now)
	# admit the best new candidates (attention budget, busy mind misses things)
	for c in 2:
		var s := cand_s if c == 0 else cand2_s
		if s < 0:
			continue
		var kind := cand_k if c == 0 else cand2_k
		var inten := cand_i if c == 0 else cand2_i
		var w := cand_w if c == 0 else cand2_w
		_admit(o, s, kind, inten, w, cap, dt, now)


## Fills _best_k/_best_i/_best_w: the most salient thing subject `s` is doing as seen/heard by observer `o`.
func _assess(o: int, s: int, off: Vector2, d2: float, now: int) -> void:
	_best_w = 0.0
	_best_k = 0
	_best_i = 0.0
	var d := sqrt(d2)
	var fl := flags[s]
	_sees_v = -1.0
	_hears_v = -1.0
	var dd: Dictionary = data[s]
	# --- stare: the subject's HEAD points at the observer, observer can see them, LOS if a callable is set
	if d <= STARE_M and d > 0.3 and head[s].dot(-off / d) >= STARE_COS:
		var sees := _sees(o, s, off, d)
		if sees > 0.0:
			if not los_fn.is_valid() or _los(pos[s], pos[o]):
				_consider(Stim.STARE, clampf(1.25 - d / 10.0, 0.2, 1.0) * (0.6 + 0.4 * sees))
	# --- follow: subject trails the observer's own movement at a distance; footsteps count when not seen
	var so := vel[o].length()
	var ss := vel[s].length()
	if so > 0.3 and ss > 0.6 and d >= 1.2 and d <= 10.0:
		var ov := vel[o] / so
		if (vel[s] / ss).dot(ov) > 0.55 and off.dot(ov) < 0.0:
			var perceived := maxf(_sees(o, s, off, d), 0.55 * _hears(s, d))
			if perceived > 0.0:
				_consider(Stim.FOLLOW, clampf(1.1 - d / 10.0, 0.2, 1.0) * (0.5 + 0.5 * perceived))
	# --- blocking the doorway the observer is heading for
	if ss < 0.3 and d < 6.0 and dest[o] != Vector2.INF and _sees(o, s, off, d) > 0.0:
		for dp in _doors:
			if pos[s].distance_squared_to(dp) < 1.7 and dest[o].distance_squared_to(dp) < 4.0:
				_consider(Stim.BLOCK_DOOR, clampf(1.2 - d / 6.0, 0.3, 1.0))
				break
	# --- running through a crowd
	if (fl & F_RUNNING) != 0 and d < 9.0 and maxf(_sees(o, s, off, d), _hears(s, d)) > 0.0 and _crowd(s) >= 2:
		_consider(Stim.RUN_CROWD, clampf(0.5 + 0.1 * _crowd(s), 0.0, 1.0) * clampf(1.1 - d / 9.0, 0.3, 1.0))
	# --- drawn weapon (taboo indoors in a public place, merely tense outdoors)
	if (fl & F_DRAWN) != 0 and _sees(o, s, off, d) > 0.0:
		var sees := _sees(o, s, off, d)
		_consider(Stim.DRAWN_WEAPON, (0.7 + 0.3 * sees) if (flags[o] & F_PUBLIC) != 0 else 0.3 + 0.2 * sees)
	if (fl & F_TRESPASS) != 0 and _sees(o, s, off, d) > 0.0:
		_consider(Stim.TRESPASS, (0.6 + 0.4 * _sees(o, s, off, d)) * (1.25 if (flags[o] & F_GUARD) != 0 else 1.0))
	# --- eavesdropping on a talking observer
	if (fl & F_EAVES) != 0 and (flags[o] & F_TALKING) != 0 and d <= 5.0 and (d < 2.5 or _sees(o, s, off, d) > 0.0):
		_consider(Stim.EAVESDROP, 0.5 + 0.5 * (1.0 - d / 5.0))
	# --- public magic: sight or sound, plus the aura read from SocialPerception
	if (fl & F_CASTING) != 0 and maxf(_sees(o, s, off, d), _hears(s, d)) > 0.0:
		var mp: float = sp.magic_pressure(data[o], dd, {"day": hour})
		_consider(Stim.PUBLIC_MAGIC, clampf(0.4 * maxf(_sees(o, s, off, d), _hears(s, d)) + 0.8 * mp, 0.0, 1.0))
	# --- enemy insignia
	var ins := float(dd.get("insignia", 0.0))
	if ins >= 0.5 and d < 12.0 and _sees(o, s, off, d) > 0.3 and dd.has("origin") and SP.legitimacy(String(dd["origin"]), String((data[o] as Dictionary).get("kingdom", SP.HOME))) <= 0.0:
		_consider(Stim.INSIGNIA, ins * _sees(o, s, off, d))
	# --- injured subject
	var inj := float(dd.get("injury", 0.0))
	if inj >= 0.3 and d < 8.0 and _sees(o, s, off, d) > 0.2:
		_consider(Stim.INJURED, inj * _sees(o, s, off, d))


var _sees_v := -1.0
var _hears_v := -1.0


func _sees(o: int, s: int, off: Vector2, d: float) -> float:
	if _sees_v < 0.0:
		_sees_v = _sight(o, s, off, d)
	return _sees_v


func _hears(s: int, d: float) -> float:
	if _hears_v < 0.0:
		_hears_v = _hear(s, d)
	return _hears_v


func _consider(kind: int, inten: float) -> void:
	var w: float = inten * SEV[kind]
	if w > _best_w:
		_best_w = w
		_best_k = kind
		_best_i = inten


func _sight(o: int, s: int, off: Vector2, d: float) -> float:
	var rng := SIGHT_M * Perception.light_term(light) * clampf(acuity[o], 0.3, 1.3)
	if (flags[s] & F_CROUCH) != 0:
		rng *= 0.6
	if d >= rng:
		return 0.0
	var c := Perception.cone(face[o], off)
	return c * clampf(1.2 - d / rng, 0.0, 1.0)


func _hear(s: int, d: float) -> float:
	var fl := flags[s]
	var rad := 0.0
	if (fl & F_CASTING) != 0:
		rad = 18.0
	elif (fl & F_RUNNING) != 0:
		rad = 14.0
	elif (fl & F_CROUCH) != 0:
		rad = 1.5
	elif vel[s].length_squared() > 0.25:
		rad = 6.0
	return 0.0 if rad <= 0.0 or d >= rad else 1.0 - d / rad


func _los(a: Vector2, b: Vector2) -> bool:
	los_calls += 1
	return bool(los_fn.call(a, b))


func _crowd(s: int) -> int:
	if crowd_tick[s] == ticks:
		return crowd_n[s]
	var c := 0
	for j in MAX_BODIES:
		if j != s and used[j] != 0 and pos[j].distance_squared_to(pos[s]) < CROWD_M * CROWD_M:
			c += 1
	crowd_tick[s] = ticks
	crowd_n[s] = c
	return c


# ------------------------------------------------------------------ staged response
func _tol_of(o: int, s: int, now: int) -> float:
	var m: Array = _memory.get(id_of[o] * 100003 + id_of[s], [])
	var strikes := 0 if m.is_empty() or now - int(m[1]) >= MEMORY_MS else int(m[0])
	return tol[o] * maxf(0.5, pow(0.8, strikes))


func _capacity(o: int) -> int:
	return 2 - int(busy[o] >= 0.5) - int(busy[o] >= 0.85)


func _stimulate(o: int, s: int, a: int, kind: int, inten: float, dt: float, now: int, jump := false) -> void:
	a_kind[a] = kind
	a_seen_ms[a] = now
	a_level[a] = minf(a_level[a] + inten * dt / (BASE_S[kind] * _tol_of(o, s, now)), 1.2)
	_advance(o, s, a, now, jump or URGENT[kind])


func _advance(o: int, s: int, a: int, now: int, jump: bool) -> void:
	var target := 0
	for i in range(1, 5):
		if a_level[a] >= STAGE_AT[i]:
			target = i
	if target <= a_stage[a]:
		return
	if not jump and now - a_stage_ms[a] < STAGE_MIN_MS:
		return
	var ns := target if jump else a_stage[a] + 1
	a_stage[a] = ns
	a_stage_ms[a] = now
	if ns >= Stage.CHECK:
		a_esc[a] = 1
	var kind := a_kind[a]
	if ns == Stage.DECIDE:
		if a_acted[a] == 0 and now - a_act_ms[a] >= ACT_COOLDOWN_MS:
			_act(o, s, a, kind, now)
	else:
		var rk: int = STAGE_REACT[kind][ns - 1]
		if rk != 0 and requests.request(o, rk, id_of[s], now):
			_log(o, rk, s, now, "stage%d" % ns)


const STAGE_REACT := [
	[0, 0, 0], [1, 1, 2], [1, 1, 4], [1, 1, 3], [6, 6, 3], [1, 6, 4], [6, 3, 3], [1, 1, 1], [1, 1, 3], [1, 2, 1],
	[6, 3, 3], [1, 0, 0], [1, 1, 4], [1, 1, 1], [1, 0, 0]]
# kinds: NONE | GLANCE=1 LOOK_AWAY=2 STEP_BACK=3 STEP_ASIDE=4 BOW=5 FLINCH=6 ... (order = Stim enum)


func _admit(o: int, s: int, kind: int, inten: float, w: float, cap: int, dt: float, now: int, jump := false) -> void:
	var breakthrough := w >= 0.55
	if not breakthrough:
		if cap <= 0:
			return
		if busy[o] > 0.0:
			var roll := float(absi(hash([id_of[o], id_of[s], now / 1000])) % 100) / 100.0
			if roll >= 1.0 - busy[o] * 0.85:
				return
	var free := -1
	var weakest := -1
	var tracked := 0
	for k in ATT:
		var a := o * ATT + k
		if a_subj[a] < 0:
			if free < 0:
				free = a
		else:
			tracked += 1
			if weakest < 0 or a_level[a] < a_level[weakest]:
				weakest = a
	if not breakthrough and tracked >= cap:
		return
	var slot := free
	if slot < 0:
		if weakest < 0 or (not breakthrough and a_level[weakest] >= 0.35):
			return
		slot = weakest
	_clear_att(slot)
	a_subj[slot] = s
	a_stage_ms[slot] = now - STAGE_MIN_MS
	a_seen_ms[slot] = now
	var m: Array = _memory.get(id_of[o] * 100003 + id_of[s], [])
	if not m.is_empty() and now - int(m[1]) < MEMORY_MS:
		a_level[slot] = minf(0.15 * float(m[0]), 0.45)
	_stimulate(o, s, slot, kind, inten, dt, now, jump)


func _feed(o: int, s: int, stim: int, strength: float, now: int, jump: bool) -> void:
	var a := _att_of(o, s)
	if a >= 0:
		_stimulate(o, s, a, stim, strength, 4.0, now, true)
	else:
		_admit(o, s, stim, strength, strength * SEV[stim], _capacity(o), 4.0, now, true)


func _decay(o: int, a: int, dt: float, now: int) -> void:
	var gone := a_subj[a] < 0
	var s: int = a_subj[a]
	var far := s >= 0 and pos[s].distance_squared_to(pos[o]) > RANGE_M * RANGE_M
	a_level[a] -= DECAY_PER_S * dt * (2.5 if far else 1.0)
	if a_stage[a] > 0 and now - a_stage_ms[a] >= DROP_MS and a_level[a] < STAGE_AT[a_stage[a]] * 0.6:
		a_stage[a] -= 1
		a_stage_ms[a] = now
		if a_stage[a] < Stage.DECIDE:
			a_acted[a] = 0
	if a_level[a] <= 0.02:
		if a_esc[a] == 1:
			if requests.request(o, RR.Kind.RETURN_TO_WORK, id_of[s], now):
				_log(o, RR.Kind.RETURN_TO_WORK, s, now, "de-escalated")
		_clear_att(a)
	elif gone:
		_clear_att(a)


func _act(o: int, s: int, a: int, kind: int, now: int) -> void:
	var rk := _decide(o, s, kind)
	a_acted[a] = 1
	a_act_ms[a] = now
	if rk == 0:
		return
	if requests.request(o, rk, id_of[s], now, 1):
		_log(o, rk, s, now, "act:" + STIM_NAMES[kind])
	if not POSITIVE[kind]:
		var key: int = id_of[o] * 100003 + id_of[s]
		var m: Array = _memory.get(key, [])
		var n: int = 1 + (int(m[0]) if not m.is_empty() and now - int(m[1]) < MEMORY_MS else 0)
		_memory[key] = [mini(n, 4), now]


## Status-dependent choice. Uses SocialPerception (authority, threat, magic pressure, bump reaction) plus the observer's persona.
func _decide(o: int, s: int, kind: int) -> int:
	var od: Dictionary = data[o]
	var sd: Dictionary = (data[s] as Dictionary).duplicate()
	if (flags[s] & F_DRAWN) != 0:
		sd["weapons"] = maxf(float(sd.get("weapons", 0.0)), 0.7)
	sp.clear()
	var ctx := {"hour": hour}
	var r: Dictionary = sp.read(od, sd, ctx)
	var pe: Dictionary = od.get("persona", {})
	var courage := clampf(float(pe.get("courage", 0.5)), 0.0, 1.0)
	var pious := clampf(float(pe.get("pious", 0.3)), 0.0, 1.0)
	var sociable := clampf(float(pe.get("sociable", 0.5)), 0.0, 1.0)
	var guard := (flags[o] & F_GUARD) != 0
	var gnear := bool(od.get("guard_near", false))
	var fear: float = maxf(float(r["threat"]), float(r["magic_pressure"])) * (1.2 - courage)
	var K := RR.Kind
	match kind:
		Stim.STARE:
			if r["authority"] >= 0.5:
				return K.LOOK_AWAY
			if guard or (courage >= 0.6 and r["threat"] < 0.3):
				return K.CONFRONT
			return K.LOOK_AWAY if fear > 0.45 else K.WARN
		Stim.FOLLOW:
			if guard:
				return K.CONFRONT
			if r["authority"] >= 0.5:
				return K.STEP_ASIDE
			if fear > 0.6 or courage < 0.35:
				return K.CALL_GUARD if gnear else K.FLEE
			return K.CONFRONT if courage >= 0.6 else K.WARN
		Stim.BLOCK_DOOR:
			if r["authority"] >= 0.5 or float(od.get("status", 0.2)) < 0.15:
				return K.STEP_ASIDE
			return K.WARN if courage > 0.5 else K.STEP_ASIDE
		Stim.BUMP:
			match sp.bump_reaction(od, sd, ctx):
				"flee": return K.FLEE
				"bow", "apologise": return K.BOW
				"insult", "demand_apology": return K.CONFRONT
			return K.RETURN_TO_WORK
		Stim.RUN_CROWD:
			return K.WARN if courage > 0.65 else K.STEP_ASIDE
		Stim.DRAWN_WEAPON:
			if guard:
				return K.CONFRONT
			if gnear:
				return K.CALL_GUARD
			return K.FLEE if courage < 0.5 else K.WARN
		Stim.TRESPASS:
			return K.CONFRONT if guard else (K.CALL_GUARD if gnear else K.WARN)
		Stim.TAKE_OBJECT:
			return K.CONFRONT if (guard or courage > 0.5) else (K.CALL_GUARD if gnear else K.FLEE)
		Stim.EAVESDROP:
			return K.CONFRONT if courage >= 0.5 else K.WARN
		Stim.PUBLIC_MAGIC:
			if fear > 0.7 or courage < 0.3:
				return K.FLEE
			if fear > 0.4:
				return K.STEP_BACK
			return K.BOW if pious > 0.6 else K.FLINCH
		Stim.INSIGNIA:
			if guard:
				return K.CONFRONT
			if fear > 0.5:
				return K.FLEE
			return K.CALL_GUARD if gnear else K.WARN
		Stim.KINDNESS:
			return K.WAVE
		Stim.INJURED:
			return K.WAVE if sociable >= 0.4 else K.LOOK_AWAY
		Stim.REPEAT_VISIT:
			return K.WAVE if sociable >= 0.3 else K.GLANCE
	return K.GLANCE
