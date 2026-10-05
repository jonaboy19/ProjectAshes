extends RefCounted
## Pure combat-feel rules (no scene access, headless-testable): hit tiers, hit-stop frames, FOV/roll/flash
## limits with a stacking budget, and attack magnetism. combat_feedback.gd applies them to the player's
## signals; docs/design/AAA_POLISH_PLAN.md "P0 combat feel".

enum Tier { LIGHT, HEAVY, FINISHER }
const TIER_NAMES := ["light", "heavy", "finisher"]

const FRAME := 1.0 / 60.0
## Hit-stop in frames per tier: light 0, heavy 2, finisher / guard break 3.
const HIT_STOP_FRAMES := [0, 2, 3]
const FOV_PUNCH := [0.0, 2.0, 4.0]          # degrees (player._fov_punch also clamps at 6)
const FOV_MAX := 6.0
const ROLL := [0.0, 0.012, 0.026]           # radians of camera roll
const ROLL_MAX := 0.035
const SHAKE := [0.22, 0.34, 0.5]
const FLASH := [0.0, 0.0, 0.16]             # short warm full-screen tint, ONE frame, finishers only

## A blow counts as heavy at this knockback, poise damage or damage (riposte hits are heavy too).
const HEAVY_KNOCK := 3.0
const HEAVY_POISE := 20.0
const HEAVY_DAMAGE := 24

## Never stack: no hit-stop inside GAP of the last one, at most WINDOW_MAX seconds of it per WINDOW.
const STOP_GAP := 0.10
const STOP_WINDOW := 1.0
const STOP_WINDOW_MAX := 0.10
const FLASH_GAP := 0.35

## Attack magnetism (no clip changes): face and step toward a valid target in a cone, small capped step.
const MAGNET_RANGE := 3.8
const MAGNET_CONE_DOT := 0.1                # ~84 degrees either side: the old target-assist cone
const MAGNET_STANDOFF := 1.3
const MAGNET_STEP_CAP := 0.6                # metres of lunge, ever
const MAGNET_STEP_CAP_FINISHER := 0.8


static func tier_for(finisher: bool, guard_break := false, knockback := 0.0, damage := 0, poise_damage := 0.0,
		riposte := false) -> int:
	if finisher or guard_break:
		return Tier.FINISHER
	if riposte or knockback >= HEAVY_KNOCK or poise_damage >= HEAVY_POISE or damage >= HEAVY_DAMAGE:
		return Tier.HEAVY
	return Tier.LIGHT


static func hit_stop_seconds(tier: int) -> float:
	return float(HIT_STOP_FRAMES[clampi(tier, 0, 2)]) * FRAME


static func fov_punch(tier: int) -> float:
	return minf(float(FOV_PUNCH[clampi(tier, 0, 2)]), FOV_MAX)


static func roll(tier: int) -> float:
	return minf(float(ROLL[clampi(tier, 0, 2)]), ROLL_MAX)


## Cues combine by max, never by sum, so a flurry cannot exceed the limits.
static func merge_fov(current: float, add: float) -> float:
	return minf(maxf(current, add), FOV_MAX)


static func merge_roll(current: float, add: float) -> float:
	return clampf(maxf(absf(current), absf(add)) * (signf(add) if add != 0.0 else signf(current)), -ROLL_MAX, ROLL_MAX)


## Stacking budget for hit-stop and the finisher flash. One per player.
class Budget extends RefCounted:
	var _stops: Array = []        # [time, seconds]
	var _last_stop := -99.0
	var _last_flash := -99.0

	## Seconds of hit-stop actually granted for a request at clock `now` (0 = skip it).
	func request_stop(seconds: float, now: float) -> float:
		if seconds <= 0.0 or now - _last_stop < STOP_GAP:
			return 0.0
		_stops = _stops.filter(func(s: Array) -> bool: return now - float(s[0]) < STOP_WINDOW)
		var used := 0.0
		for s: Array in _stops:
			used += float(s[1])
		var granted := minf(seconds, STOP_WINDOW_MAX - used)
		if granted < FRAME * 0.99:
			return 0.0
		_stops.append([now, granted])
		_last_stop = now
		return granted

	func request_flash(now: float) -> bool:
		if now - _last_flash < FLASH_GAP:
			return false
		_last_flash = now
		return true


## Best valid target for a swing: `locked` (a Vector3 or null) wins inside MAGNET_RANGE, else the candidate
## with the best distance x angle score inside the cone. `candidates` are world positions of living
## enemies. -> {"pos": Vector3 or null, "index": int (-1 = locked/none)}.
static func pick_target(origin: Vector3, facing: Vector3, candidates: Array, locked: Variant = null,
		max_range := MAGNET_RANGE, cone_dot := MAGNET_CONE_DOT) -> Dictionary:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	if locked is Vector3:
		var d := _flat(locked as Vector3 - origin).length()
		if d <= max_range + 2.0:
			return {"pos": locked, "index": -1}
	var best := -1
	var best_score := INF
	for i in candidates.size():
		var to := _flat((candidates[i] as Vector3) - origin)
		var d := to.length()
		if d > max_range:
			continue
		var dot := f.dot(to / maxf(d, 0.01))
		if dot <= cone_dot:
			continue
		var score := d * (1.6 - dot)
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		return {"pos": null, "index": -1}
	return {"pos": candidates[best], "index": best}


## Initial lunge speed so a body under `decel` travels min(gap, cap) metres: always a small step, never into
## the target (gap = distance - standoff).
static func lunge_speed(distance: float, decel: float, finisher := false, max_speed := 99.0) -> float:
	var gap := maxf(distance - MAGNET_STANDOFF, 0.0)
	var step := minf(gap, MAGNET_STEP_CAP_FINISHER if finisher else MAGNET_STEP_CAP)
	return minf(sqrt(2.0 * decel * step), max_speed)


static func lunge_distance(speed: float, decel: float) -> float:
	return speed * speed / (2.0 * decel)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Telegraph-worthy enemy move: heavy poise or knockback, unblockable, or a long windup.
static func is_heavy_move(m: Resource) -> bool:
	if m == null:
		return false
	return m.poise_damage >= HEAVY_POISE or m.knockback >= HEAVY_KNOCK + 1.0 or m.unblockable or m.windup >= 0.8
