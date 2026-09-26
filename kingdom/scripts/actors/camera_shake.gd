class_name CameraShake
extends RefCounted
## Trauma-based noise shake, ported from the Godot TPS demo
## (camera_noise_shake_effect.gd, MIT, Juan Linietsky & Godot contributors).
## Trauma decays over time; shake strength is trauma squared, so small hits
## are subtle and big ones punchy.

const DECAY := 1.6
const MAX_YAW := 0.05
const MAX_PITCH := 0.05
const MAX_ROLL := 0.08

var trauma := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.fractal_octaves = 1


func add(amount: float) -> void:
	trauma = minf(trauma + amount, 1.2)


## Returns the rotation offset (pitch, yaw, roll) to add to the camera this frame.
func step(delta: float) -> Vector3:
	if trauma <= 0.0:
		return Vector3.ZERO
	trauma = maxf(trauma - DECAY * delta, 0.0)
	_time += delta * 5000.0
	var s := trauma * trauma
	return Vector3(MAX_PITCH * s * _sample(1), MAX_YAW * s * _sample(2), MAX_ROLL * s * _sample(3))


func _sample(channel: int) -> float:
	_noise.seed = channel
	return _noise.get_noise_1d(_time)
