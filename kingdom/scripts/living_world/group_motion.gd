class_name GroupMotion
extends RefCounted
## Group motion rules G1-G4 and S7 of docs/plans/NPC_MOTION_RULES.md. Pure and static (plus two small state holders), no nodes,
## no randf: every choice is a hash of ids and counters, so the same world replays the same way.
## Positions are ground-plane Vector2 (x, z). Facing is a yaw with forward = (sin yaw, cos yaw), the convention of npc_world.queue_spot.
## No allocation in the per-tick paths: results are returned as Vector2/float/int, or written into caller-owned scratch.
##
## G1 conversation circle   circle_radius, circle_slot, circle_yaw, Token (speaker turns), gaze_listener, fill_clip_query
## G2 families              family_slot, child_target, leash_clamp, child_running
## G3 guard patrol in step  phase_error, phase_seek, phase_rate, pair_slot, leg_pause
## G4 children round adults orbit_point, push_out
## S7 generic queue         line_spot, queue_slot, queue_yaw, Queue (FIFO + patience give-up)

const TAU_F := TAU

# --- G1 ---
const CIRCLE_BASE := 0.55
const CIRCLE_PER := 0.25
const TURN_MIN := 3.0
const TURN_MAX := 7.0
const GAZE_MIN := 2.0
const GAZE_MAX := 4.0
const NOD_MIN := 2.5                    # a listener nods every 2.5..5.5 s
const NOD_SPAN := 3.0

# --- G2 ---
const FAMILY_SIDE := 0.6                # a child's slot beside the parent
const LEASH := 3.0                      # hard bound on child-parent distance
const LEASH_RUN := 2.4                  # beyond this the child runs back ...
const LEASH_WALK := 1.0                 # ... until it is this close again
const CHILD_AHEAD_MAX := 1.9            # how far ahead of the parent a child may drift

# --- G3 ---
const PHASE_TOL := 0.02                 # inside this the follower is left alone
const PHASE_NUDGE := 0.25               # between tol and this: rate correction; above it: hard seek
const PHASE_GAIN := 0.5                 # speed-scale per second of error, capped at +-PHASE_RATE_MAX
const PHASE_RATE_MAX := 0.06
const GUARD_SIDE := 0.9

# --- G4 ---
const ORBIT_MIN := 2.0
const ORBIT_MAX := 5.0
const ORBIT_OMEGA_MIN := 0.35           # rad/s
const ORBIT_OMEGA_SPAN := 0.55

# --- S7 ---
const QUEUE_GAP := 0.85                 # same as NpcWorld.QUEUE_GAP
const QUEUE_FIRST := 1.7                # bread-line distance of place 0 from the counter (npc_world.queue_spot)
const QUEUE_BEND := 0.18                # sideways drift per place (npc_world.queue_spot)
const QUEUE_MAX := 8
const PATIENCE_MIN := 25.0              # seconds a queuer waits, scaled 0.6..1.4 per person
const PATIENCE_SPAN := 0.8


## 0..1 from integers, deterministic.
static func _h01(a: int, b: int, c: int = 0) -> float:
	return float(absi(hash(a * 92821 + b * 68917 + c * 104729 + 7)) % 10007) / 10007.0


static func _yaw_of(d: Vector2) -> float:
	return atan2(d.x, d.y)


static func _fwd(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


# =============================================================== G1 conversation circles

static func circle_radius(n: int) -> float:
	return CIRCLE_BASE + CIRCLE_PER * float(n)


## Position of member `idx` (0..n-1) of an n-person circle round `center`. One arc of 360/(n+1) degrees stays open, centred on `open_dir`
## (toward the path or the player); the n members sit in the middle of n equal arcs of the rest. Join or leave = call again with the new n
## (neighbour chord is 1.8..1.9 m for n 2..5, never below 1.8 m).
static func circle_slot(center: Vector2, n: int, idx: int, open_dir: Vector2) -> Vector2:
	if n <= 0:
		return center
	var open_a := atan2(open_dir.y, open_dir.x) if open_dir.length_squared() > 0.0001 else 0.0
	var gap := TAU_F / float(n + 1)
	var step := (TAU_F - gap) / float(n)
	var a := open_a + gap * 0.5 + step * (float(idx) + 0.5)
	return center + Vector2(cos(a), sin(a)) * circle_radius(n)


## Yaw that makes member `slot_pos` face the circle centre.
static func circle_yaw(center: Vector2, slot_pos: Vector2) -> float:
	return _yaw_of(center - slot_pos)


## Speaker token of one conversation: who talks now, until when. Allocate once per group, call advance() each think.
## Turns last 3..7 s by hash. A cycle of n turns is a hash-ordered permutation of the members, so everybody talks once per cycle (fair),
## and nobody talks twice in a row across cycles.
class Token extends RefCounted:
	var group := 0
	var n := 0
	var turn := 0
	var started := 0.0
	var ends := 0.0
	var speaker := 0

	func reset(group_id: int, members: int, now: float) -> void:
		group = group_id
		n = members
		turn = 0
		started = now
		ends = now + GroupMotion.turn_length(group, 0)
		speaker = GroupMotion.speaker_of(group, 0, n)

	## Member count changed (someone joined or left): keep the running turn, re-derive the speaker from the new count.
	func set_members(members: int) -> void:
		n = members
		speaker = GroupMotion.speaker_of(group, turn, n)

	## Moves to the turn that contains `now`. Returns true when the speaker changed.
	func advance(now: float) -> bool:
		var changed := false
		while now >= ends and turn < 1000000:
			turn += 1
			started = ends
			ends = started + GroupMotion.turn_length(group, turn)
			var s := GroupMotion.speaker_of(group, turn, n)
			if s != speaker:
				changed = true
			speaker = s
		return changed


static func turn_length(group: int, turn: int) -> float:
	return TURN_MIN + (TURN_MAX - TURN_MIN) * _h01(group, turn, 1)


## Member index (0..n-1) that speaks in `turn`.
static func speaker_of(group: int, turn: int, n: int) -> int:
	if n <= 1:
		return 0
	var cycle := turn / n
	var pos := turn % n
	if n == 2:
		return (turn + int(_h01(group, 0, 2) * 2.0)) % 2
	var first := _nth_in_order(group, cycle, n, 0)
	var second := _nth_in_order(group, cycle, n, 1)
	# Cycle boundary: if this cycle would open with the previous cycle's last speaker, its first two swap.
	var swap := cycle > 0 and first == _nth_in_order(group, cycle - 1, n, n - 1)
	if pos == 0 and swap:
		return second
	if pos == 1 and swap:
		return first
	return _nth_in_order(group, cycle, n, pos)


## Member with the pos-th smallest hash key in this cycle (ties by index). n <= 5 in practice, O(n^2), no allocation.
static func _nth_in_order(group: int, cycle: int, n: int, pos: int) -> int:
	for i in n:
		var ki := _h01(group, cycle, 100 + i)
		var rank := 0
		for j in n:
			var kj := _h01(group, cycle, 100 + j)
			if kj < ki or (kj == ki and j < i):
				rank += 1
		if rank == pos:
			return i
	return 0


## The listener index the speaker looks at; shifts every 2..4 s. Never the speaker itself.
static func gaze_listener(group: int, turn: int, n: int, speaker: int, t_in_turn: float) -> int:
	if n <= 1:
		return speaker
	var period := GAZE_MIN + (GAZE_MAX - GAZE_MIN) * _h01(group, turn, 3)
	var k := int(t_in_turn / period)
	var pick := int(_h01(group, turn, 4 + k) * float(n - 1))
	return pick + 1 if pick >= speaker else pick


## True during the short window in which this listener nods (additive neck pitch, A2). One window of 0.8 s every 2.5..5.5 s per person.
static func nod_now(person: int, now: float) -> bool:
	var period := NOD_MIN + NOD_SPAN * _h01(person, 5)
	var phase := fmod(now + _h01(person, 6) * period, period)
	return phase < 0.8


## Fills `out` (a dictionary the caller owns and reuses) with a ClipPicker query for the speaker or a listener of this turn.
## `turn` is the picker cycle, so a clip is held for a turn and changes on the next one.
static func fill_clip_query(out: Dictionary, speaker: bool, mood: String, day: int, turn: int) -> void:
	out["verb"] = "talk" if speaker else "listen"
	out["posture"] = "stand"
	out["mood"] = mood
	out["day"] = day
	out["cycle"] = turn


# =============================================================== G2 families

## Slot of child `idx` of `n_children` beside the parent: alternate sides, 0.6 m out, stepped back a little for each extra child.
static func family_slot(parent: Vector2, parent_yaw: float, idx: int, _n_children: int) -> Vector2:
	var f := _fwd(parent_yaw)
	var side := Vector2(-f.y, f.x)
	var sgn := 1.0 if idx % 2 == 0 else -1.0
	var ring := 1 + idx / 2
	return parent + side * (sgn * FAMILY_SIDE * float(ring)) - f * (0.15 * float(idx / 2))


## Where a child wants to be at time `t`: its slot plus a bounded drift ahead (0..1.9 m) and out (+-0.8 m), different per child and slow.
## Always inside the leash.
static func child_target(parent: Vector2, parent_yaw: float, child: int, idx: int, n_children: int, t: float) -> Vector2:
	var slot := family_slot(parent, parent_yaw, idx, n_children)
	var f := _fwd(parent_yaw)
	var side := Vector2(-f.y, f.x)
	var w := 0.2 + 0.25 * _h01(child, 7)
	var ph := _h01(child, 8) * TAU_F
	var ahead := (0.5 + 0.5 * sin(t * w + ph)) * CHILD_AHEAD_MAX
	var out := side * (0.8 * sin(t * w * 1.7 + ph * 0.5))
	return leash_clamp(slot + f * ahead + out, parent)


## Pulls `p` back inside LEASH of the parent.
static func leash_clamp(p: Vector2, parent: Vector2) -> Vector2:
	var d := p - parent
	var l := d.length()
	if l <= LEASH:
		return p
	return parent + d * (LEASH / l)


## Run/walk with hysteresis: starts running past 2.4 m, stops when back within 1 m. `was_running` is the child's current state.
static func child_running(dist_to_parent: float, was_running: bool) -> bool:
	if dist_to_parent > LEASH_RUN:
		return true
	if dist_to_parent < LEASH_WALK:
		return false
	return was_running


# =============================================================== G3 guard phase lock

## Signed phase error (follower - leader) wrapped into (-len/2, len/2] for a looping clip of `length` seconds.
static func phase_error(leader_time: float, follower_time: float, length: float) -> float:
	if length <= 0.0:
		return 0.0
	var e := fposmod(follower_time - leader_time, length)
	return e - length if e > length * 0.5 else e


## Follower seek target for AnimationPlayer.seek: the leader's time when the error is past PHASE_NUDGE, else -1 (use phase_rate instead).
static func phase_seek(leader_time: float, follower_time: float, length: float) -> float:
	if absf(phase_error(leader_time, follower_time, length)) > PHASE_NUDGE:
		return fposmod(leader_time, length)
	return -1.0


## Follower speed-scale multiplier that closes a small error without a visible pop; 1.0 inside the tolerance.
static func phase_rate(leader_time: float, follower_time: float, length: float) -> float:
	var e := phase_error(leader_time, follower_time, length)
	if absf(e) <= PHASE_TOL:
		return 1.0
	return 1.0 - clampf(e * PHASE_GAIN, -PHASE_RATE_MAX, PHASE_RATE_MAX)


## Side-by-side slot of guard `idx` (0 = leader) for a pair or file: 0.9 m to the right of the previous one.
static func pair_slot(leader: Vector2, yaw: float, idx: int) -> Vector2:
	var f := _fwd(yaw)
	return leader + Vector2(f.y, -f.x) * (GUARD_SIDE * float(idx))


## Patrol leg timing: 0 = walking, 1 = the shared pause at the end of the leg (synchronised stop and look). `leg_len` and `pause` in seconds.
static func leg_pause(t: float, leg_len: float, pause: float) -> int:
	var c := fposmod(t, leg_len + pause)
	return 1 if c >= leg_len else 0


# =============================================================== G4 children round adults

## A point on the orbit of child `child` round a (moving) anchor. Radius 2..5 m wobbling by +-0.3, speed 0.35..0.9 rad/s, direction by hash.
static func orbit_point(anchor: Vector2, child: int, t: float) -> Vector2:
	var base_r := ORBIT_MIN + 0.3 + (ORBIT_MAX - ORBIT_MIN - 0.6) * _h01(child, 9)
	var r := base_r + 0.3 * sin(t * 0.7 + _h01(child, 10) * TAU_F)
	var omega := (ORBIT_OMEGA_MIN + ORBIT_OMEGA_SPAN * _h01(child, 11)) * (1.0 if _h01(child, 12) < 0.5 else -1.0)
	var a := _h01(child, 13) * TAU_F + omega * t
	return anchor + Vector2(cos(a), sin(a)) * r


## Children give way: pushes `p` out of a 0.7 m bubble round another adult.
static func push_out(p: Vector2, adult: Vector2, min_dist := 0.7) -> Vector2:
	var d := p - adult
	var l := d.length()
	if l >= min_dist:
		return p
	if l < 0.0001:
		return adult + Vector2(min_dist, 0.0)
	return adult + d * (min_dist / l)


# =============================================================== S7 generic queue

## The bread-line maths of NpcWorld.queue_spot as a pure static: place `idx` of a line leaving `origin` along `front` (unit), bending
## sideways. Returns the spot; the queuer faces -front.
static func line_spot(origin: Vector2, front: Vector2, idx: int, first := QUEUE_FIRST, gap := QUEUE_GAP, bend := QUEUE_BEND) -> Vector2:
	var side := Vector2(-front.y, front.x)
	return origin + front * (first + float(idx) * gap) + side * (float(idx) * bend)


## World position of place `idx` of a SmartObject `queue` declaration. `decl` is the JSON list of local [x, y, z] points (the first ones are
## authored, e.g. the two well spots); places past the list continue the last authored step, QUEUE_GAP apart. With no declaration the line
## leaves the object along its local +Z (line_spot). `xform` is the object's world transform (SmartObjects spot "xform").
static func queue_slot(xform: Transform3D, decl: Array, idx: int) -> Vector2:
	var k := decl.size()
	var local: Vector3
	if k == 0:
		var l0 := line_spot(Vector2.ZERO, Vector2(0.0, 1.0), idx)
		local = Vector3(l0.x, 0.0, l0.y)
	elif idx < k:
		local = _vec3(decl[idx])
	else:
		var last := _vec3(decl[k - 1])
		var dir := Vector3(0.0, 0.0, 1.0)
		if k > 1:
			var d := last - _vec3(decl[k - 2])
			d.y = 0.0
			if d.length_squared() > 0.0001:
				dir = d.normalized()
		local = last + dir * (QUEUE_GAP * float(idx - k + 1))
	var w := xform * local
	return Vector2(w.x, w.z)


static func _vec3(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Yaw a queuer at `spot` faces: the object it waits for, so the line looks at the stall or well.
static func queue_yaw(xform: Transform3D, spot: Vector2) -> float:
	return _yaw_of(Vector2(xform.origin.x, xform.origin.z) - spot)


## Seconds a person waits before giving up: base x 0.6..1.4 by person hash. `base` <= 0 means PATIENCE_MIN... times 1, so a persona can scale it.
static func patience_of(person: int, base := 60.0) -> float:
	return maxf(base, PATIENCE_MIN) * (0.6 + PATIENCE_SPAN * _h01(person, 14))


## FIFO queue for one SmartObject. Allocate once per object with a `queue` declaration; join/leave/tick never allocate.
## Order is arrival order; a place is its index, so when the front is served or someone gives up everyone behind shuffles forward by one.
class Queue extends RefCounted:
	var people := PackedInt32Array()
	var since := PackedFloat32Array()      # join time
	var patience := PackedFloat32Array()   # seconds this person waits
	var count := 0
	var gave_up := PackedInt32Array()      # people who gave up in the last tick, in order
	var gave_up_count := 0

	func _init(capacity := GroupMotion.QUEUE_MAX) -> void:
		people.resize(capacity)
		since.resize(capacity)
		patience.resize(capacity)
		gave_up.resize(capacity)

	## Place of `person`, or -1.
	func index_of(person: int) -> int:
		for i in count:
			if people[i] == person:
				return i
		return -1

	## Joins at the back (or keeps the place already held). Returns the place, or -1 when the line is full.
	func join(person: int, now: float, patience_s: float) -> int:
		var at := index_of(person)
		if at >= 0:
			return at
		if count >= people.size():
			return -1
		people[count] = person
		since[count] = now
		patience[count] = patience_s
		count += 1
		return count - 1

	func leave(person: int) -> void:
		var at := index_of(person)
		if at >= 0:
			_remove(at)

	func _remove(at: int) -> void:
		for i in range(at, count - 1):
			people[i] = people[i + 1]
			since[i] = since[i + 1]
			patience[i] = patience[i + 1]
		count -= 1

	## The front of the line is served: removes and returns it (-1 when empty). Call when the object has a free slot.
	func pop_front() -> int:
		if count == 0:
			return -1
		var p := people[0]
		_remove(0)
		return p

	## Gives up everyone whose patience has run out (front included: a line that never moves empties). The people are listed in
	## `gave_up[0..gave_up_count)`. Returns how many gave up.
	func tick(now: float) -> int:
		gave_up_count = 0
		var i := 0
		while i < count:
			if now - since[i] >= patience[i]:
				gave_up[gave_up_count] = people[i]
				gave_up_count += 1
				_remove(i)
			else:
				i += 1
		return gave_up_count
