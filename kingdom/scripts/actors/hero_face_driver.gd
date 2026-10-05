extends Node
## Tier-A hero face + secondary motion driver (added by HeroTierA.upgrade, child of the skeleton; no bone changes).
## - Blink: both lids every 2-6 s (0.14 s close/open), sometimes a double blink.
## - Expressions: set_expression("Smile" | "Jaw_Open" | "Brow_Up", weight, seconds) eases toward the weight (dialogue).
##   talk(seconds): jaw flaps 6-9 Hz while a line plays.
## - Secondary motion: a damped spring on the pelvis/head world acceleration feeds the `sway` uniform of the hair cards and
##   the HeroOutfit garment shader (hood tip, satchel, skirt hem lag and settle). Vertex-shader sway = zero bone cost.
## Cost: one _process per hero, ~10 blend-shape/uniform writes.

var sk: Skeleton3D
var parts := {}
var outfit: MeshInstance3D
var _face: MeshInstance3D
var _blink_t := 2.0
var _blink_phase := -1.0
var _double := false
var _expr := {}          # name -> [current, target, rate]
var _talk_left := 0.0
var _talk_ph := 0.0
var _pel := -1
var _head := -1
var _prev_p := Vector3.ZERO
var _prev_v := Vector3.ZERO
var _spring := Vector3.ZERO
var _spring_v := Vector3.ZERO
var _spring_h := Vector3.ZERO
var _spring_hv := Vector3.ZERO
var _prev_hp := Vector3.ZERO
var _prev_hv := Vector3.ZERO
var _primed := false


func setup(skeleton: Skeleton3D, p: Dictionary, garment: MeshInstance3D) -> void:
	sk = skeleton
	parts = p
	outfit = garment
	_face = parts.get("FaceSkin")
	_pel = sk.find_bone("pelvis")
	_head = sk.find_bone("Head")
	for n in ["Smile", "Jaw_Open", "Brow_Up"]:
		_expr[n] = [0.0, 0.0, 4.0]
	_blink_t = randf_range(1.0, 3.0)


func set_expression(n: String, weight: float, seconds := 0.25) -> void:
	if _expr.has(n):
		_expr[n][1] = clampf(weight, 0.0, 1.0)
		_expr[n][2] = 1.0 / maxf(0.02, seconds)


func talk(seconds: float) -> void:
	_talk_left = seconds


func _bs(n: String, w: float) -> void:
	if _face == null:
		return
	var i := _face.find_blend_shape_by_name(n)
	if i >= 0:
		_face.set_blend_shape_value(i, w)


func _process(dt: float) -> void:
	if sk == null or dt <= 0.0:
		return
	# blink
	_blink_t -= dt
	if _blink_t <= 0.0 and _blink_phase < 0.0:
		_blink_phase = 0.0
	if _blink_phase >= 0.0:
		_blink_phase += dt / 0.14
		var w := 1.0 - absf(_blink_phase - 1.0)
		w = clampf(w, 0.0, 1.0)
		_bs("Blink_L", w)
		_bs("Blink_R", w)
		if _blink_phase >= 2.0:
			_blink_phase = -1.0
			_bs("Blink_L", 0.0)
			_bs("Blink_R", 0.0)
			_double = not _double and randf() < 0.2
			_blink_t = 0.12 if _double else randf_range(2.0, 6.0)
	# expressions + talking
	for n in _expr:
		var e: Array = _expr[n]
		e[0] = move_toward(e[0], e[1], e[2] * dt)
	var jaw: float = _expr["Jaw_Open"][0]
	if _talk_left > 0.0:
		_talk_left -= dt
		_talk_ph += dt * randf_range(6.0, 9.0) * TAU
		jaw = maxf(jaw, (sin(_talk_ph) * 0.5 + 0.5) * 0.7)
	_bs("Jaw_Open", jaw)
	_bs("Smile", _expr["Smile"][0])
	_bs("Brow_Up", _expr["Brow_Up"][0])
	# secondary motion: springs on world acceleration of the pelvis (garments) and the head (hair)
	var p := (sk.global_transform * sk.get_bone_global_pose(_pel)).origin if _pel >= 0 else sk.global_position
	var hp := (sk.global_transform * sk.get_bone_global_pose(_head)).origin if _head >= 0 else p
	if not _primed:
		_prev_p = p
		_prev_hp = hp
		_primed = true
	var v := (p - _prev_p) / dt
	var a := (v - _prev_v) / dt
	_prev_p = p
	_prev_v = v
	var hv := (hp - _prev_hp) / dt
	var ha := (hv - _prev_hv) / dt
	_prev_hp = hp
	_prev_hv = hv
	# target: cloth trails the motion (drag) and swings back against acceleration; spring k=60, damping 9
	var tgt := (-v * 0.018 - a * 0.004).limit_length(0.09)
	tgt.y = minf(tgt.y, 0.02)
	_spring_v += ((tgt - _spring) * 60.0 - _spring_v * 9.0) * dt
	_spring += _spring_v * dt
	var tgt_h := (-hv * 0.012 - ha * 0.003).limit_length(0.05)
	_spring_hv += ((tgt_h - _spring_h) * 90.0 - _spring_hv * 10.0) * dt
	_spring_h += _spring_hv * dt
	if outfit and outfit.material_override is ShaderMaterial:
		(outfit.material_override as ShaderMaterial).set_shader_parameter("sway", outfit.global_transform.basis.inverse() * _spring)
	var hair: MeshInstance3D = parts.get("HairCards")
	if hair and hair.material_override is ShaderMaterial:
		(hair.material_override as ShaderMaterial).set_shader_parameter("sway", hair.global_transform.basis.inverse() * _spring_h)
