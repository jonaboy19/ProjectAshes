extends Node
## Trauma-based camera shake (Squirrel Eiserloh, GDC 2016) that does NOT touch the camera's
## transform, so it composes with any follow / orbit camera: it only writes Camera3D.h_offset,
## v_offset and (optionally) fov, which a controller normally leaves alone.
##
##   const CameraShake := preload("res://tools_qa/anim_tech/lib/camera_shake.gd")
##   var shake := CameraShake.new(); shake.camera = cam; add_child(shake)
##   shake.add_trauma(0.35)                       # light hit
##   shake.add_trauma(0.8, Vector2(1, 0))         # big hit, kicked along screen-x first
##
## shake = trauma^2 (small hits stay subtle), trauma decays linearly. Offsets are frustum
## offsets in metres, tuned for a third-person camera 3-5 m from the target.
## Sleeps (set_process(false)) at zero trauma. Cost: 2 noise samples per frame while shaking,
## zero otherwise. Honour a "reduce screen shake" accessibility option with `strength = 0`.

@export var camera: Camera3D
@export var max_offset := 0.10        # m at trauma 1
@export var max_fov_kick := 2.0       # degrees at trauma 1
@export var decay := 1.6              # trauma per second
@export var frequency := 22.0
@export var strength := 1.0           # global scale, 0 = off (accessibility)

var trauma := 0.0
var _kick := Vector2.ZERO
var _t := 0.0
var _noise := FastNoiseLite.new()
var _base_fov := -1.0


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	set_process(false)


func add_trauma(amount: float, kick := Vector2.ZERO) -> void:
	trauma = minf(trauma + amount, 1.0)
	_kick += kick * amount
	if camera and _base_fov < 0.0:
		_base_fov = camera.fov
	set_process(true)


## Current offset (for cameras that would rather apply it themselves).
func offset() -> Vector2:
	var s := trauma * trauma * strength
	return Vector2(_noise.get_noise_2d(_t * frequency, 0.0), _noise.get_noise_2d(_t * frequency, 100.0)) * max_offset * s + _kick * max_offset * strength


func _process(delta: float) -> void:
	_t += delta
	trauma = maxf(trauma - decay * delta, 0.0)
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-14.0 * delta))
	if camera and is_instance_valid(camera):
		var o := offset()
		camera.h_offset = o.x
		camera.v_offset = o.y
		if _base_fov > 0.0:
			camera.fov = _base_fov + max_fov_kick * trauma * trauma * strength
	if trauma <= 0.0 and _kick.length() < 0.001:
		if camera and is_instance_valid(camera):
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			if _base_fov > 0.0:
				camera.fov = _base_fov
		_base_fov = -1.0
		set_process(false)
