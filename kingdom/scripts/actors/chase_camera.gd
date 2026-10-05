extends RefCounted
## Framing offsets only. Player's SpringArm3D retains collision ownership.
## No scene queries, allocations of nodes or global time changes.

const BASE_FOV := 65.0
const CAST_DURATION := 0.65
var cast_enabled := false
var _cast_left := 0.0
var _fov := BASE_FOV
var _distance := 0.0
var _height := 0.0
var _pitch := 0.0
var _impulse := 0.0


func step(delta: float, ctx: Dictionary) -> void:
	var strength := clampf(float(ctx.get("strength", 1.0)), 0.0, 1.0)
	if not cast_enabled or strength <= 0.0:
		_cast_left = 0.0
	_cast_left = maxf(0.0, _cast_left - delta)
	_impulse = move_toward(_impulse, 0.0, 18.0 * delta)
	var fast := bool(ctx.get("sprinting", false)) or bool(ctx.get("gallop", false))
	var dash := bool(ctx.get("dashing", false))
	var combat := bool(ctx.get("combat", false)) or bool(ctx.get("locked", false))
	var open_ground := bool(ctx.get("open", false)) and not combat
	var roof := bool(ctx.get("rooftop", false)) and not combat
	var speed := clampf(float(ctx.get("speed_k", 0.0)), 0.0, 1.0)
	var lens := (7.0 if dash else (5.0 * speed if fast else 0.0))
	var distance := 0.55 if dash else (0.35 * speed if fast else 0.0)
	var height := 0.25 if roof else (0.1 if open_ground else 0.0)
	var pitch := -0.04 if roof else 0.0
	if _cast_left > 0.0:
		var beat := sin(PI * (1.0 - _cast_left / CAST_DURATION))
		lens -= 4.0 * beat
		distance -= 0.25 * beat
	var blend := 1.0 - exp(-6.0 * maxf(delta, 0.0))
	_fov = lerpf(_fov, BASE_FOV + lens * strength, blend)
	_distance = lerpf(_distance, distance * strength, blend)
	_height = lerpf(_height, height * strength, blend)
	_pitch = lerpf(_pitch, pitch * strength, blend)


func fov_base() -> float:
	return _fov

func dist_offset() -> float:
	return _distance

func lift() -> float:
	return _height

func pitch_offset() -> float:
	return _pitch

func impulse() -> float:
	return _impulse

func add_fov_impulse(degrees: float) -> void:
	_impulse = clampf(_impulse + degrees, -8.0, 8.0)

func begin_cast() -> void:
	if cast_enabled:
		_cast_left = CAST_DURATION

func cancel_cast() -> void:
	_cast_left = 0.0

func casting() -> bool:
	return _cast_left > 0.0

static func lock_frame(distance: float) -> Dictionary:
	return {"dist": clampf((distance - 2.0) * 0.12, 0.0, 1.0),
		"shift": clampf(distance * 0.18, 0.0, 0.8)}

static func is_big_technique(def: Dictionary) -> bool:
	return int(def.get("tier", 1)) >= 3 or float(def.get("radius", 0.0)) >= 4.0
