class_name AshsightGrade
extends Node3D
## The Ashsight world grade: while a replay runs the world is drained to a warm sepia-ember
## memory, with a soft vignette and drifting ash motes. The ghosts keep their own colours.
##
##   grade.set_amount(view.grade)      every frame (0 = normal world .. 1 = full Ashsight)
##   grade.follow(focus_point)         keep the 3D motes around the action
##
## Tiers (`detail`: 0 LOW, 1 MEDIUM, 2 HIGH; default from `Quality`):
##   HIGH   full-screen grade pass (desaturate + warm + vignette + 3 layers of screen flakes)
##          plus 3D ash motes for parallax
##   MEDIUM the same pass, fewer motes
##   LOW    NO grade pass: only a cheap Environment adjustment (saturation / brightness) when an
##          Environment is bound, and a few motes
## The pass is one full-screen quad that reads the screen texture; it is hidden (not drawn at
## all) while `amount` is 0, so an idle game pays nothing.

const GRADE_SHADER := preload("res://shaders/region1/ash_grade.gdshader")
const DOT_SHADER := preload("res://shaders/region1/ash_particle.gdshader")

var detail := 2
var amount := 0.0

var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _motes: GPUParticles3D
var _env: Environment
var _env_saved := {}


func _ready() -> void:
	if detail == 2 and AshGhostPool.tier_from_quality() != 2:
		detail = AshGhostPool.tier_from_quality()
	_build()
	set_amount(0.0)


func set_detail(d: int) -> void:
	detail = clampi(d, 0, 2)
	if is_inside_tree():
		_build()
		set_amount(amount)


## Bind the scene's Environment so the LOW tier can grade through it (and so HIGH can lift the
## bloom a little while the memory is on). Optional.
func bind_environment(env: Environment) -> void:
	_env = env
	_env_saved = {}
	if env != null:
		_env_saved = {"sat": env.adjustment_saturation, "bri": env.adjustment_brightness,
			"con": env.adjustment_contrast, "en": env.adjustment_enabled}


func _build() -> void:
	if _quad != null:
		_quad.queue_free()
		_quad = null
	if _motes != null:
		_motes.queue_free()
		_motes = null
	if detail >= 1:
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		_mat = ShaderMaterial.new()
		_mat.shader = GRADE_SHADER
		_mat.render_priority = -100   # before the ghosts and their particles
		_quad = MeshInstance3D.new()
		_quad.mesh = qm
		_quad.material_override = _mat
		_quad.extra_cull_margin = 16384.0
		_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_quad.visible = false
		add_child(_quad)
	# 3D ash motes around the action (parallax): a soft box of slow flakes
	_motes = GPUParticles3D.new()
	_motes.amount = [16, 48, 90][detail]
	_motes.lifetime = 7.0
	_motes.local_coords = false
	_motes.visibility_aabb = AABB(Vector3(-40, -6, -40), Vector3(80, 24, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(15, 5, 15)
	pm.direction = Vector3(0.3, -0.25, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0.05, -0.04, 0.02)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.025
	pm.scale_max = 0.07
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 0.7, 0.4, 0), Color(0.98, 0.92, 0.84, 0.85), Color(0.9, 0.84, 0.78, 0.7), Color(0.85, 0.8, 0.75, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	_motes.process_material = pm
	var dm := QuadMesh.new()
	dm.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = DOT_SHADER
	dm.material = mat
	_motes.draw_pass_1 = dm
	_motes.emitting = false
	add_child(_motes)


## 0..1. Cheap: only touches the shader/environment when the value changed.
func set_amount(a: float) -> void:
	var k := clampf(a, 0.0, 1.0)
	if is_equal_approx(k, amount) and _quad != null and _quad.visible == (k > 0.002):
		return
	amount = k
	var on := k > 0.002
	if _quad != null:
		_quad.visible = on
		if on:
			_mat.set_shader_parameter(&"amount", k)
			_mat.set_shader_parameter(&"motes", 1.0 if detail >= 2 else 0.0)   # MEDIUM: the 3D motes only
	if _motes != null:
		_motes.emitting = on
	if _env != null and detail == 0:
		# LOW: no grade pass, so use the Environment's own (free) adjustments
		_env.adjustment_enabled = true if on else bool(_env_saved.get("en", false))
		_env.adjustment_saturation = lerpf(float(_env_saved.get("sat", 1.0)), 0.7, k)
		_env.adjustment_brightness = lerpf(float(_env_saved.get("bri", 1.0)), 0.97, k)
		_env.adjustment_contrast = lerpf(float(_env_saved.get("con", 1.0)), 1.08, k)


## Keep the 3D motes centred on the action.
func follow(p: Vector3) -> void:
	if _motes != null:
		_motes.global_position = p + Vector3(0, 4.0, 0)


## Put the effect back exactly as it was (Environment restored).
func reset() -> void:
	set_amount(0.0)
	if _env != null and not _env_saved.is_empty():
		_env.adjustment_enabled = bool(_env_saved["en"])
		_env.adjustment_saturation = float(_env_saved["sat"])
		_env.adjustment_brightness = float(_env_saved["bri"])
		_env.adjustment_contrast = float(_env_saved["con"])
