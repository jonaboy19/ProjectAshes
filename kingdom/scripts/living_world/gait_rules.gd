class_name GaitRules
extends RefCounted
## Locomotion logic for rules L2-L6 of docs/plans/NPC_MOTION_RULES.md (package M8). Pure, static, deterministic, no nodes, no
## allocation in the per-tick calls (integer hash, scratch-free arithmetic, the lean state is one PackedFloat32Array the body owns).
##
##   L6  state_for(health, rest, drunk, limping) -> State          which gait set the body uses
##   L3  pick_rung(state, speed, cur) -> rung                      the gait clip whose ground speed keeps the rate inside 0.75..1.3
##       rate_for(state, rung, speed) -> rate                      playback rate, clamped 0.3..1.8
##       clip_for(state, rung, have) / idle_for(state, have)       clip names; `have` = {clip: true} (the library, or the VAT set at FAR);
##                                                                 an empty dictionary means "everything exists"; a missing clip falls back to Walk / Idle
##       gait_into(out, state, speed, cur, have) -> rung           writes gait_clip + gait_rate of a MotionIntent in place
##   L4  transition(speed, desired, heading_delta_deg, tier, state, have) -> clip or ""
##   L2  lean_new() / lean_step(st, speed, yaw_rate, dt, bias) -> roll, lean_roll(st), lean_pitch(st)    model-root roll + pitch
##   L5  carry_pace_mul / carry_rate_mul / carry_lean_bias(kind)   by load mass
##   L6  weave_offset(person_id, t, amp) / weave_speed(...)        drunk lateral sway (m, m/s), perpendicular to the heading
##
## Heading delta is degrees, positive = the body must turn LEFT (counter-clockwise seen from above, +yaw in Godot).

enum State { NORMAL, INJURED, LIMP, DRUNK, TIRED }
const STATE_NAMES := ["NORMAL", "INJURED", "LIMP", "DRUNK", "TIRED"]

## Same numbers as MotionRules.TIER_*.
const TIER_NEAR := 0
const TIER_MID := 1
const TIER_FAR := 2

# L6 thresholds
const INJURED_HEALTH := 0.35        # health fraction at or under this = injured gait
const LIMP_HEALTH := 0.6
const TIRED_REST := 0.2             # need `rest` under this = tired gait (rules json L6 rest_need)
const WEAVE_AMP_M := 0.4            # rules json L6 weave_m

# L3 stride band
const BAND_LO := 0.75
const BAND_HI := 1.3
const RATE_MIN := 0.3
const RATE_MAX := 1.8

# L4
const TURN_MIN_DEG := 100.0         # rules json L4 turn_deg
const TURN_180_DEG := 150.0
const TURN_MAX_SPEED := 1.0         # rules json L4 max_speed_mps
const STANDING := 0.15              # same as MotionRules.MOVING_SPEED
const START_DESIRED := 0.3
const STOP_SPEED := 0.4
const CLIP_START := "Loco_WalkStart_F"
const CLIP_STOP := "Loco_WalkStop"
const CLIP_TURN_180 := "Mx_Run_Turn_180"
const CLIP_TURN_L := "Mx_RunTurn_L"
const CLIP_TURN_R := "Mx_RunTurn_R"
const CLIP_INJ_TURN_L := "Mx_Inj_Turn_Left"
const CLIP_INJ_TURN_R := "Mx_Inj_Turn_Right"

# L2 lean (the maths of combat/lean_aim.gd on the model root: roll into the turn, pitch with speed, critically damped)
const LEAN_K := 0.02                # rad per (m/s * rad/s)
const LEAN_MAX_ROLL := 0.0873       # 5 degrees
const LEAN_PITCH_GAIN := 0.03       # rad per m/s
const LEAN_MAX_PITCH := 0.0524      # 3 degrees
const LEAN_STIFFNESS := 60.0
const LEAN_DT_MAX := 0.05
const _L_PITCH := 0
const _L_ROLL := 1
const _L_PITCH_V := 2
const _L_ROLL_V := 3

## L6 gait sets: per state a ladder of rungs, slowest first. Each rung is [clip, ground speed m/s]. `idle` is the standing clip,
## `fb_walk` / `fb_idle` the existing clips used when the set's own clip is not in the library. Clip names are section 5 /
## UAL_Life_Mocap / UAL_Mx_male_injured; Life_Walk_Tired already exists in the Life library.
const SETS := {
	State.NORMAL: {"idle": "Idle", "rungs": [["Walk", 1.35], ["Life_Walk_Brisk", 1.9], ["Jog_Fwd_Loop", 3.2]]},
	State.INJURED: {"idle": "Mx_Inj_Idle_Loop", "rungs": [["Mx_Inj_Walk_Loop", 1.0]]},
	State.LIMP: {"idle": "Idle", "rungs": [["Life_Walk_Limp", 0.8]]},
	State.DRUNK: {"idle": "Idle", "rungs": [["Life_Walk_Drunk", 0.9]]},
	State.TIRED: {"idle": "Idle", "rungs": [["Life_Walk_Tired", 1.0], ["Walk", 1.35]]},
}
const FB_WALK := "Walk"
const FB_IDLE := "Idle"

## L5 loads: mass 0..1 and the lean bias in radians (+ forward). A sack on the shoulder pulls the body forward, a crate held
## in front pulls it back, a basket at the hip barely moves it. Mirrors CarryErrand.KINDS; the hook adds `mass` there.
const CARRY_PACE := 0.85            # pace multiplier at mass 1 (rules json L5 pace_mul)
const CARRY_RATE := 1.05            # rate multiplier at mass 1 (rules json L5 rate_mul)
const CARRY_LEAN := 0.07            # rad at mass 1
const LOADS := {
	"sack": {"mass": 0.8, "lean": 1.0},
	"crate": {"mass": 1.0, "lean": -1.0},
	"basket": {"mass": 0.3, "lean": 0.0},
	"firewood": {"mass": 0.7, "lean": 1.0},
}


# --- L6: state -> gait set -------------------------------------------------------------------------

## health 0..1 (1 = unhurt), rest 0..1 (need, 1 = rested). Priority: injured, drunk, limp, tired, normal.
static func state_for(health: float, rest: float, drunk: bool, limping: bool = false) -> int:
	if health <= INJURED_HEALTH:
		return State.INJURED
	if drunk:
		return State.DRUNK
	if limping or health <= LIMP_HEALTH:
		return State.LIMP
	if rest < TIRED_REST:
		return State.TIRED
	return State.NORMAL


static func rung_count(state: int) -> int:
	return (SETS[state]["rungs"] as Array).size()


## The clip of a rung, or the Walk fallback when `have` is given and lacks it.
static func clip_for(state: int, rung: int, have: Dictionary = {}) -> String:
	var rungs: Array = SETS[state]["rungs"]
	var clip: String = rungs[clampi(rung, 0, rungs.size() - 1)][0]
	if have.is_empty() or have.has(clip):
		return clip
	return FB_WALK


static func idle_for(state: int, have: Dictionary = {}) -> String:
	var clip: String = SETS[state]["idle"]
	if have.is_empty() or have.has(clip):
		return clip
	return FB_IDLE


static func ground_speed(state: int, rung: int) -> float:
	var rungs: Array = SETS[state]["rungs"]
	return rungs[clampi(rung, 0, rungs.size() - 1)][1]


# --- L3: stride band --------------------------------------------------------------------------------

## Playback rate = speed / the clip's ground speed, clamped 0.3..1.8.
static func rate_for(state: int, rung: int, speed: float) -> float:
	return clampf(speed / ground_speed(state, rung), RATE_MIN, RATE_MAX)


## Keeps the current rung while its rate stays inside the band 0.75..1.3 (hysteresis, no flip-flop at the border); otherwise the
## rung whose rate is nearest 1 (smallest |ln rate|, compared as max(r, 1/r)). One rung sets always return 0.
static func pick_rung(state: int, speed: float, cur: int = 0) -> int:
	var rungs: Array = SETS[state]["rungs"]
	var n := rungs.size()
	if n == 1:
		return 0
	cur = clampi(cur, 0, n - 1)
	var s := maxf(speed, 0.01)
	var r_cur: float = s / float(rungs[cur][1])
	if r_cur >= BAND_LO and r_cur <= BAND_HI:
		return cur
	var best := 0
	var best_err := INF
	for i in n:
		var r: float = s / float(rungs[i][1])
		var err := maxf(r, 1.0 / r)
		if err < best_err:
			best_err = err
			best = i
	return best


## Fills gait_clip and gait_rate of a MotionIntent dictionary in place. Returns the rung so the body can keep it as `cur`.
static func gait_into(out: Dictionary, state: int, speed: float, cur: int = 0, have: Dictionary = {}) -> int:
	if speed < STANDING:
		out["gait_clip"] = idle_for(state, have)
		out["gait_rate"] = 1.0
		return clampi(cur, 0, rung_count(state) - 1)
	var rung := pick_rung(state, speed, cur)
	out["gait_clip"] = clip_for(state, rung, have)
	out["gait_rate"] = rate_for(state, rung, speed)
	return rung


# --- L4: start, stop and turn -----------------------------------------------------------------------

## Which transition one-shot to play now, or "" for none. speed = current, desired = what the route wants next.
## NEAR: start, stop, 90 and 180 turns in place. MID: start and stop only. FAR and OUT: none. A clip missing from `have`
## (when given) returns "" so the caller just blends the loops.
static func transition(speed: float, desired: float, heading_delta_deg: float, tier: int, state: int = State.NORMAL, have: Dictionary = {}) -> String:
	if tier > TIER_MID:
		return ""
	var clip := ""
	var want_move := desired >= START_DESIRED
	if tier == TIER_NEAR and want_move and speed <= TURN_MAX_SPEED and absf(heading_delta_deg) >= TURN_MIN_DEG:
		var left := heading_delta_deg > 0.0
		if state == State.INJURED:
			clip = CLIP_INJ_TURN_L if left else CLIP_INJ_TURN_R
		elif absf(heading_delta_deg) >= TURN_180_DEG:
			clip = CLIP_TURN_180
		else:
			clip = CLIP_TURN_L if left else CLIP_TURN_R
	elif speed < STANDING and want_move:
		clip = CLIP_START
	elif speed >= STOP_SPEED and desired < STANDING:
		clip = CLIP_STOP
	if clip != "" and not have.is_empty() and not have.has(clip):
		return ""
	return clip


# --- L2: lean spring --------------------------------------------------------------------------------

## The per-body lean state (pitch, roll, pitch velocity, roll velocity). Create once, reuse.
static func lean_new() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


static func lean_reset(st: PackedFloat32Array) -> void:
	st[0] = 0.0
	st[1] = 0.0
	st[2] = 0.0
	st[3] = 0.0


## One critically damped spring step toward the goal: roll = -speed * yaw_rate * k (<= 5 deg, into the turn), pitch = speed * gain
## (<= 3 deg forward) + `bias` (L5 load lean, radians, + forward; the sum is still capped at max pitch + |bias|). Returns the roll.
static func lean_step(st: PackedFloat32Array, speed: float, yaw_rate: float, dt: float, bias: float = 0.0, weight: float = 1.0) -> float:
	var h := minf(dt, LEAN_DT_MAX)
	if h <= 0.0:
		return st[_L_ROLL]
	var goal_roll := clampf(-speed * yaw_rate * LEAN_K, -LEAN_MAX_ROLL, LEAN_MAX_ROLL) * weight
	var goal_pitch := (clampf(speed * LEAN_PITCH_GAIN, 0.0, LEAN_MAX_PITCH) + bias) * weight
	var damp := 2.0 * sqrt(LEAN_STIFFNESS)
	st[_L_PITCH_V] += ((goal_pitch - st[_L_PITCH]) * LEAN_STIFFNESS - st[_L_PITCH_V] * damp) * h
	st[_L_ROLL_V] += ((goal_roll - st[_L_ROLL]) * LEAN_STIFFNESS - st[_L_ROLL_V] * damp) * h
	st[_L_PITCH] += st[_L_PITCH_V] * h
	st[_L_ROLL] += st[_L_ROLL_V] * h
	return st[_L_ROLL]


static func lean_roll(st: PackedFloat32Array) -> float:
	return st[_L_ROLL]


static func lean_pitch(st: PackedFloat32Array) -> float:
	return st[_L_PITCH]


# --- L5: carrying load -----------------------------------------------------------------------------

static func load_mass(kind: String) -> float:
	var l: Variant = LOADS.get(kind)
	return float(l["mass"]) if l != null else 0.0


## Pace multiplier on the route speed: 1 unloaded down to 0.85 at mass 1.
static func carry_pace_mul(kind: String) -> float:
	return 1.0 - (1.0 - CARRY_PACE) * load_mass(kind)


## Playback rate multiplier (shorter stride): 1 unloaded up to 1.05 at mass 1.
static func carry_rate_mul(kind: String) -> float:
	return 1.0 + (CARRY_RATE - 1.0) * load_mass(kind)


## Pitch bias for lean_step: forward (+) for a shoulder load, back (-) for a crate held in front.
static func carry_lean_bias(kind: String) -> float:
	var l: Variant = LOADS.get(kind)
	return CARRY_LEAN * float(l["mass"]) * float(l["lean"]) if l != null else 0.0


# --- L6: drunk weave -------------------------------------------------------------------------------

## Deterministic 32-bit mix of (id, salt); no array, so no allocation.
static func _mix(id: int, salt: int) -> int:
	var x := (id * 2654435761 + salt * 40503 + 0x9E3779B9) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return x ^ (x >> 16)


## Sway frequency in rad/s, 0.8..1.4 (periods of 4.5-7.5 s), per person.
static func weave_omega(person_id: int) -> float:
	return 0.8 + 0.6 * float(_mix(person_id, 1) & 1023) / 1023.0


## Lateral offset in metres (+ = to the body's left), always within +-amp: a main sine plus a slower irregular one.
static func weave_offset(person_id: int, t: float, amp: float = WEAVE_AMP_M) -> float:
	var w := weave_omega(person_id)
	var p1 := TAU * float(_mix(person_id, 2) & 1023) / 1023.0
	var p2 := TAU * float(_mix(person_id, 3) & 1023) / 1023.0
	return amp * (0.75 * sin(w * t + p1) + 0.25 * sin(w * 0.37 * t + p2))


## Time derivative of weave_offset (m/s lateral): add it to the steer velocity perpendicular to the heading.
static func weave_speed(person_id: int, t: float, amp: float = WEAVE_AMP_M) -> float:
	var w := weave_omega(person_id)
	var p1 := TAU * float(_mix(person_id, 2) & 1023) / 1023.0
	var p2 := TAU * float(_mix(person_id, 3) & 1023) / 1023.0
	return amp * (0.75 * w * cos(w * t + p1) + 0.25 * w * 0.37 * cos(w * 0.37 * t + p2))
