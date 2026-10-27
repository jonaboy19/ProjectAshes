class_name Attention
extends RefCounted
## Attention director (docs/plans/NPC_MOTION_RULES.md A1-A5). One global, fixed-size table of look requests, so at most LOOK_SLOTS
## people (6 on HIGH/ULTRA, 3 on LOW/MEDIUM, by Quality.tier) have a non-forward look at the same time. Pure, static, no nodes.
##
##   Attention.offer_event(person, pos, now)            # LivingEvents.nearest (clang, shout, ...)       -> LOUD / THREAT
##   Attention.offer_sound(person, here_xz, now)        # NpcWorld.best_sound                            -> LOUD
##   Attention.offer_presence(person, kind, p, now)     # RR.Kind.GLANCE / LOOK_AWAY from Presence       -> PLAYER
##   Attention.offer_player(person, pos, player, fwd, now, curiosity, notable)   # A2 glance within 3 m (6 m notable)
##   Attention.offer_conversation(person, speaker_pos, now)                      # A4 listener follows the speaker token
##   Attention.request(person, source, target, now)     # any other source (threat, addressed, ambient)
##   var t = Attention.target_for(person, now)          # Vector3 or null: feed it to the LookAtModifier3D target
##
## Priorities (= source ids): threat 6 > addressed 5 > loud 4 > player within 3 m 3 > conversation 2 > ambient 1.
## A request is accepted when the person is not in that source's cooldown (4-9 s after a look from it ends, by hash), and either the
## person already looks (then only a strictly higher priority replaces it; the same source refreshes its target) or a slot is free, or
## the lowest priority active look is strictly lower (it is pre-empted). A look holds 1.2-3 s by hash, a sound/event look starts after
## a 0.15-0.4 s reaction delay (A5). No randf(): every roll is _mix(person, source, serial). No per-call allocation except the
## dictionary / array LivingEvents.nearest and NpcWorld.best_sound already return.
## apply_lookat_params() configures a LookAtModifier3D per archetype (local worker wires the node, see the hook lines).

const RR := preload("res://scripts/population/reaction_request.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")

const SRC_AMBIENT := 1
const SRC_CONVERSATION := 2
const SRC_PLAYER := 3
const SRC_LOUD := 4
const SRC_ADDRESSED := 5
const SRC_THREAT := 6
const SRC_COUNT := 7

const CAP := 128                        # people tracked at once (open addressing); the rest are refused, never allocated
const SLOTS_HIGH := 6
const SLOTS_LOW := 3
const HOLD_MIN := 1.2
const HOLD_MAX := 3.0
const COOLDOWN_MIN := 4.0
const COOLDOWN_MAX := 9.0
const DELAY_MIN := 0.15
const DELAY_MAX := 0.4
const GLANCE_RANGE := 3.0
const GLANCE_RANGE_NOTABLE := 6.0
const EYE_DOT := 0.9
const EYE_RANGE := 5.0
const EYE_DWELL := 1.0
const GAZE_SHIFT_MIN := 2.0
const GAZE_SHIFT_MAX := 4.0
const THREAT_KINDS := ["fight", "scream", "alarm", "war_horn", "explosion", "crash_threat"]
const HEAD_HEIGHT := 1.5

enum Reply { NONE, NOD, LOOK_AWAY, STARE }

static var _person := PackedInt32Array()       # person id per entry, -1 free
static var _src := PackedInt32Array()          # active source per entry, 0 none
static var _from := PackedFloat64Array()
static var _until := PackedFloat64Array()
static var _target := PackedVector3Array()
static var _cool := PackedFloat64Array()       # CAP * SRC_COUNT: no new request of that source before this time
static var _gaze := PackedFloat64Array()       # eye-contact dwell start per entry, < 0 none
static var _serial := 0
static var _ready := false


static func reset() -> void:
	_person.resize(CAP)
	_src.resize(CAP)
	_from.resize(CAP)
	_until.resize(CAP)
	_target.resize(CAP)
	_cool.resize(CAP * SRC_COUNT)
	_gaze.resize(CAP)
	_person.fill(-1)
	_src.fill(0)
	_from.fill(0.0)
	_until.fill(0.0)
	_target.fill(Vector3.ZERO)
	_cool.fill(0.0)
	_gaze.fill(-1.0)
	_serial = 0
	_ready = true


static func slots_for(tier: int) -> int:
	return SLOTS_HIGH if tier >= 2 else SLOTS_LOW


## Deterministic integer hash of three ints (no allocation, unlike hash([...])).
static func _mix(a: int, b: int, c: int) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


static func roll(a: int, b: int, c: int) -> float:
	return float(_mix(a, b, c) % 10000) / 10000.0


static func hold_for(person: int, source: int, serial: int) -> float:
	return lerpf(HOLD_MIN, HOLD_MAX, roll(person, source, serial))


static func cooldown_for(person: int, source: int, serial: int) -> float:
	return lerpf(COOLDOWN_MIN, COOLDOWN_MAX, roll(person, source + 17, serial))


static func delay_for(person: int, serial: int) -> float:
	return lerpf(DELAY_MIN, DELAY_MAX, roll(person, 31, serial))


## Entry index of `person`, a free/reclaimable one when `create`, else -1.
static func _find(person: int, now: float, create: bool) -> int:
	if not _ready:
		reset()
	var start := person % CAP
	var free := -1
	for k in CAP:
		var i := (start + k) % CAP
		if _person[i] == person:
			return i
		if free < 0 and create and _reclaimable(i, now):
			free = i
	if free >= 0:
		_person[free] = person
		_src[free] = 0
		_gaze[free] = -1.0
		for s in SRC_COUNT:
			_cool[free * SRC_COUNT + s] = 0.0
	return free


static func _reclaimable(i: int, now: float) -> bool:
	if _person[i] < 0:
		return true
	if _src[i] != 0 and _until[i] > now:
		return false
	if _gaze[i] >= 0.0:
		return false
	for s in SRC_COUNT:
		if _cool[i * SRC_COUNT + s] > now:
			return false
	return true


static func active_count(now: float) -> int:
	var n := 0
	for i in CAP:
		if _person[i] >= 0 and _src[i] != 0 and _until[i] > now:
			n += 1
	return n


## Ends an active look (its source cooldown starts now).
static func _end(i: int, now: float) -> void:
	if _src[i] != 0:
		_cool[i * SRC_COUNT + _src[i]] = maxf(_cool[i * SRC_COUNT + _src[i]], now + cooldown_for(_person[i], _src[i], _serial))
	_src[i] = 0


## Expires finished looks (starts their cooldown from the end time). Called lazily from request/target_for for one entry.
static func _expire(i: int, now: float) -> void:
	if _src[i] != 0 and _until[i] <= now:
		var s := _src[i]
		_cool[i * SRC_COUNT + s] = maxf(_cool[i * SRC_COUNT + s], _until[i] + cooldown_for(_person[i], s, _serial))
		_src[i] = 0


## Asks for a look. `delay` is the reaction delay before the head turns. Returns true when accepted (or refreshed).
static func request(person: int, source: int, target: Vector3, now: float, delay := 0.0, tier := -1) -> bool:
	if source < SRC_AMBIENT or source >= SRC_COUNT:
		return false
	var i := _find(person, now, true)
	if i < 0:
		return false
	_expire(i, now)
	_serial += 1
	if _src[i] == source:                      # same source: refresh the target and extend the hold, no cooldown involved
		_target[i] = target
		_until[i] = maxf(_until[i], now + delay + hold_for(person, source, _serial))
		return true
	if _cool[i * SRC_COUNT + source] > now:
		return false
	if _src[i] != 0:
		if source <= _src[i]:
			return false
		_end(i, now)                           # pre-empted by a strictly higher priority
	else:
		var slots := slots_for(Quality.tier if tier < 0 else tier)
		if active_count(now) >= slots and not _preempt_lowest(source, now):
			return false
	_src[i] = source
	_from[i] = now + delay
	_until[i] = now + delay + hold_for(person, source, _serial)
	_target[i] = target
	return true


## Frees one slot by ending the lowest priority active look when it is strictly lower than `source`.
static func _preempt_lowest(source: int, now: float) -> bool:
	var low := -1
	for i in CAP:
		if _person[i] < 0 or _src[i] == 0 or _until[i] <= now:
			continue
		if low < 0 or _src[i] < _src[low] or (_src[i] == _src[low] and _until[i] < _until[low]):
			low = i
	if low < 0 or _src[low] >= source:
		return false
	_end(low, now)
	return true


## The look target of `person` right now (Vector3), or null: no look, still in its reaction delay, or expired.
static func target_for(person: int, now: float) -> Variant:
	var i := _find(person, now, false)
	if i < 0:
		return null
	_expire(i, now)
	if _src[i] == 0 or now < _from[i]:
		return null
	return _target[i]


static func source_of(person: int, now: float) -> int:
	var i := _find(person, now, false)
	if i < 0:
		return 0
	_expire(i, now)
	return _src[i]


## Drops a person's look and dwell (despawn, LOOK_AWAY), no cooldown.
static func release(person: int) -> void:
	var i := _find(person, 0.0, false)
	if i >= 0:
		_src[i] = 0
		_gaze[i] = -1.0


# -- inputs ---------------------------------------------------------------------------------------------------------------

## LivingEvents.nearest: a threat kind outranks a plain loud event. `after` = last serial this person reacted to. Returns the event serial.
static func offer_event(person: int, pos: Vector3, now: float, after := -1, tier := -1) -> int:
	var e := LivingEvents.nearest(pos, after)
	if e.is_empty():
		return after
	var src := SRC_THREAT if THREAT_KINDS.has(String(e["kind"])) else SRC_LOUD
	var p: Vector3 = e["pos"]
	request(person, src, Vector3(p.x, maxf(p.y, 1.0), p.z), now, delay_for(person, int(e["serial"])), tier)
	return int(e["serial"])


## NpcWorld.best_sound: [gain, pos(Vector2 xz), event_id]. Returns the event id it reacted to (0 none).
static func offer_sound(person: int, here: Vector2, now: float, tier := -1) -> int:
	var s: Array = NpcWorld.best_sound(here)
	if float(s[0]) <= 0.0 or (s[1] as Vector2) == Vector2.INF:
		return 0
	var p: Vector2 = s[1]
	request(person, SRC_LOUD, Vector3(p.x, HEAD_HEIGHT, p.y), now, delay_for(person, int(s[2])), tier)
	return int(s[2])


## Presence reaction: GLANCE looks at the player; LOOK_AWAY ends a player look and keeps the forward target.
static func offer_presence(person: int, kind: int, player_pos: Vector3, now: float, tier := -1) -> bool:
	if kind == RR.Kind.GLANCE:
		return request(person, SRC_PLAYER, player_pos + Vector3(0, HEAD_HEIGHT, 0), now, 0.0, tier)
	if kind == RR.Kind.LOOK_AWAY:
		var i := _find(person, now, true)
		if i >= 0:
			_expire(i, now)
			if _src[i] == SRC_PLAYER:
				_end(i, now)
			_gaze[i] = -1.0
		return false
	return false


## A2: the player within 3 m (6 m when notable) is glanced at with probability `curiosity` per cooldown window.
static func offer_player(person: int, pos: Vector3, player_pos: Vector3, now: float, curiosity := 0.5, notable := false, tier := -1) -> bool:
	var r := GLANCE_RANGE_NOTABLE if notable else GLANCE_RANGE
	if pos.distance_squared_to(player_pos) > r * r:
		return false
	var i := _find(person, now, true)
	if i < 0:
		return false
	_expire(i, now)
	var window := int(now / COOLDOWN_MAX)     # one dice roll per window, so frame rate does not raise the odds
	if roll(person, SRC_PLAYER + 101, window) >= curiosity:
		return false
	return request(person, SRC_PLAYER, player_pos + Vector3(0, HEAD_HEIGHT, 0), now, 0.0, tier)


## A3: the player's camera faces this person (dot > 0.9) within 5 m for 1 s -> a reply by standing
## (player_pos = the camera / eye position; >= 0.3 friendly: NOD, 0..0.3 shy: LOOK_AWAY, < 0 hostile: STARE). Call every think tick; NONE until the dwell completes.
static func eye_contact(person: int, pos: Vector3, player_pos: Vector3, player_fwd: Vector3, now: float, standing := 0.0) -> int:
	var i := _find(person, now, true)
	if i < 0:
		return Reply.NONE
	var to := pos + Vector3(0, HEAD_HEIGHT, 0) - player_pos
	var d := to.length()
	if d > EYE_RANGE or d < 0.001 or to.dot(player_fwd) / d <= EYE_DOT:
		_gaze[i] = -1.0
		return Reply.NONE
	if _gaze[i] < 0.0:
		_gaze[i] = now
		return Reply.NONE
	if now - _gaze[i] < EYE_DWELL:
		return Reply.NONE
	_gaze[i] = -1.0
	if standing >= 0.3:
		return Reply.NOD
	return Reply.LOOK_AWAY if standing >= 0.0 else Reply.STARE


## A4: listeners look at the current speaker token's position.
static func offer_conversation(person: int, speaker_pos: Vector3, now: float, tier := -1) -> bool:
	return request(person, SRC_CONVERSATION, speaker_pos + Vector3(0, HEAD_HEIGHT, 0), now, 0.0, tier)


## A4: which of `n_listeners` the speaker looks at; shifts every 2-4 s by hash.
static func speaker_gaze_index(person: int, n_listeners: int, now: float) -> int:
	if n_listeners <= 0:
		return -1
	var period := lerpf(GAZE_SHIFT_MIN, GAZE_SHIFT_MAX, roll(person, 53, 0))
	return _mix(person, 59, int(now / period)) % n_listeners


# -- LookAtModifier3D ------------------------------------------------------------------------------------------------------

const _FALLBACK_TURN_DEG := 70.0

## Duration and ease per archetype: the nervous child snaps a bit faster, the elder and noble turn slowly.
const _LOOK_DURATION := {"child": 0.25, "villager": 0.35, "merchant": 0.35, "follower": 0.3, "guard": 0.3, "bandit": 0.3, "elder": 0.5, "noble": 0.45}


## Sets duration, transition and angle limits on a LookAtModifier3D from the archetype's head_turn_deg (motion_rules.json).
## The primary axis is the yaw (turn), the secondary the pitch (nod): head_turn_deg yaw each way, a quarter of it up and down.
static func apply_lookat_params(mod: LookAtModifier3D, archetype: String) -> void:
	var arch: Dictionary = MotionRules.default_registry().archetypes.get(archetype, {})
	var turn := float(arch.get("head_turn_deg", _FALLBACK_TURN_DEG))
	mod.duration = float(_LOOK_DURATION.get(archetype, 0.35))
	mod.transition_type = Tween.TRANS_SINE
	mod.ease_type = Tween.EASE_IN_OUT
	mod.use_angle_limitation = true
	mod.symmetry_limitation = true
	mod.primary_limit_angle = deg_to_rad(turn)
	mod.primary_damp_threshold = 0.4
	mod.secondary_limit_angle = deg_to_rad(turn * 0.25)
	mod.secondary_damp_threshold = 0.4
