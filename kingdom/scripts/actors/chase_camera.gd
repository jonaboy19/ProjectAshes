extends RefCounted
## ChaseCamera: the framing model behind the player's third-person camera. Pure maths (no nodes), so it is unit
## tested; player.gd feeds it a small context every frame and adds the results ON TOP of its own rig:
##   fov     = BASE_FOV + fov_offset()  (+ landing / hit punches player.gd already layers on top)
##   distance += dist_offset;   pivot height += lift;   pitch += pitch_offset
## It never touches the spring arm, the camera-only occlusion ray or the foliage fade: those still run after it
## and win, because this only changes the distance/FOV/pivot the arm is asked for.
##
## Contexts (see step()):
##   speed_k   0..1  planar speed / RUN
##   sprinting bool  sprint held while moving fast
##   dashing   bool  roll / Shadow Dash / dodge impulse
##   gallop    bool  mounted gallop
##   combat    bool  hostile near, swinging, blocking or locked
##   locked    bool  lock-on active
##   open      bool  nothing near the camera (arm unobstructed) and not in combat
##   rooftop   bool  well above the ground
##   strength  0..1  accessibility scale (the Screen Shake setting); 0 = no FOV/distance motion at all
##
## FOV impulses from combat feel: add_fov_impulse(deg) (positive = outward punch). They decay by themselves and are
## clamped, so the combat code can fire them freely without owning the base FOV.

const BASE_FOV := 65.0
const MAX_FOV := 86.0
const SPRINT_FOV := 7.0
const DASH_FOV := 10.0
const GALLOP_FOV := 9.0
const SPRINT_DIST := 0.9
const DASH_DIST := 1.4
const GALLOP_DIST := 1.3
const OPEN_DIST := 0.7
const OPEN_LIFT := 0.3
const OPEN_PITCH := -0.05
const ROOF_DIST := 1.0
const ROOF_LIFT := 0.5
const ROOF_PITCH := -0.08
const COMBAT_DIST := -0.6
const COMBAT_LIFT := -0.15
const COMBAT_FOV := -2.0
const IMPULSE_MIN := -6.0
const IMPULSE_MAX := 10.0
const IMPULSE_DECAY := 7.0
const CAST_TIME := 0.9
const CAST_FOV := -6.0
const CAST_DIST := -1.3
const CAST_LIFT := 0.12
const CAST_PITCH := 0.04
const RISE := 4.5         # 1/s response when a boost builds
const FALL := 2.6         # slower release, so a boost eases away instead of snapping

var _fov := 0.0
var _dist := 0.0
var _lift := 0.0
var _pitch := 0.0
var _impulse := 0.0
var _cast_left := 0.0
var _cast_len := CAST_TIME
var cast_enabled := true


func fov_offset() -> float:
	return _fov + _impulse + _cast_env() * CAST_FOV


func dist_offset() -> float:
	return _dist + _cast_env() * CAST_DIST


func lift() -> float:
	return _lift + _cast_env() * CAST_LIFT


func pitch_offset() -> float:
	return _pitch + _cast_env() * CAST_PITCH


## The FOV the camera rests at before landing / hit punches: BASE_FOV plus the smoothed framing offset.
func fov_base() -> float:
	return clampf(BASE_FOV + _fov + _cast_env() * CAST_FOV, BASE_FOV - 8.0, MAX_FOV)


func fov_total() -> float:
	return clampf(BASE_FOV + fov_offset(), BASE_FOV - 8.0, MAX_FOV)


func add_fov_impulse(degrees: float) -> void:
	_impulse = clampf(_impulse + degrees, IMPULSE_MIN, IMPULSE_MAX)


func impulse() -> float:
	return _impulse


# --- cast camera --------------------------------------------------------------------

## Big techniques: a short push in. Returns false when disabled or one is already running.
func begin_cast(seconds := CAST_TIME) -> bool:
	if not cast_enabled or _cast_left > 0.0:
		return false
	_cast_len = maxf(seconds, 0.2)
	_cast_left = _cast_len
	return true


func cancel_cast() -> void:
	_cast_left = 0.0


func casting() -> bool:
	return _cast_left > 0.0


## 0 -> 1 -> 0 over the cast (ease in and out, so it never snaps).
func _cast_env() -> float:
	if _cast_left <= 0.0:
		return 0.0
	var t := 1.0 - _cast_left / _cast_len
	return sin(clampf(t, 0.0, 1.0) * PI)


## A technique worth a camera moment: tier 3+ or a 10 s+ cooldown (flat def from the ability/skills data).
static func is_big_technique(flat: Dictionary) -> bool:
	return int(flat.get("tier", 1)) >= 3 or float(flat.get("cooldown", 0.0)) >= 10.0


# --- framing ------------------------------------------------------------------------

func step(delta: float, ctx: Dictionary) -> void:
	var strength := clampf(float(ctx.get("strength", 1.0)), 0.0, 1.0)
	var speed_k := clampf(float(ctx.get("speed_k", 0.0)), 0.0, 1.0)
	var sprinting := bool(ctx.get("sprinting", false))
	var combat := bool(ctx.get("combat", false))
	var locked := bool(ctx.get("locked", false))
	var open := bool(ctx.get("open", false)) and not combat and not locked
	var rooftop := bool(ctx.get("rooftop", false)) and not combat
	var move_fov := 0.0
	var move_dist := 0.0
	if sprinting:
		var k := smoothstep(0.35, 1.0, speed_k)
		move_fov = SPRINT_FOV * k
		move_dist = SPRINT_DIST * k
	if bool(ctx.get("dashing", false)):
		move_fov = maxf(move_fov, DASH_FOV)
		move_dist = maxf(move_dist, DASH_DIST)
	if bool(ctx.get("gallop", false)):
		move_fov = maxf(move_fov, GALLOP_FOV)
		move_dist = maxf(move_dist, GALLOP_DIST)
	var fov_t := move_fov
	var dist_t := move_dist
	var lift_t := 0.0
	var pitch_t := 0.0
	if rooftop:
		dist_t += ROOF_DIST
		lift_t += ROOF_LIFT
		pitch_t += ROOF_PITCH
	elif open:
		dist_t += OPEN_DIST
		lift_t += OPEN_LIFT
		pitch_t += OPEN_PITCH
	if combat:
		fov_t += COMBAT_FOV
		dist_t += COMBAT_DIST
		lift_t += COMBAT_LIFT
	fov_t *= strength
	dist_t *= strength
	_fov = _ease(_fov, fov_t, delta)
	_dist = _ease(_dist, dist_t, delta)
	_lift = _ease(_lift, lift_t * strength, delta)
	_pitch = _ease(_pitch, pitch_t * strength, delta)
	_impulse = move_toward(_impulse, 0.0, maxf(absf(_impulse), 1.0) * IMPULSE_DECAY * delta)
	if _cast_left > 0.0:
		_cast_left = maxf(_cast_left - delta, 0.0)


func _ease(cur: float, goal: float, delta: float) -> float:
	var rate := RISE if absf(goal) > absf(cur) else FALL
	return lerpf(cur, goal, 1.0 - exp(-rate * delta))


## Lock-on framing that keeps player and target both on screen: how much farther the arm sits and how far the
## pivot slides toward the target for a horizontal gap (m). -> {dist: m, shift: m}
static func lock_frame(gap: float) -> Dictionary:
	var g := maxf(gap, 0.0)
	return {"dist": clampf(g * 0.12 + maxf(g - 5.0, 0.0) * 0.3, 0.0, 3.4),
		"shift": clampf(g * 0.28, 0.0, 2.2)}
