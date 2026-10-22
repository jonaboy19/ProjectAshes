class_name FireBlast
extends LabFX
## FIRE BLAST (bending): a roaring cone of flame leaves the palm, front runs out in 0.3 s, burns for ~0.5 s and
## gutters out. Two additive shells (outer orange, inner white-yellow; the inner is dropped on LOW), embers, a scorch
## decal where it ends and (HIGH only) a warm light that flickers. No heat-haze (needs the screen texture: skipped on mobile).
const SHADER := preload("res://scenes/vfx_lab/fire_blast.gdshader")
const DECAL := preload("res://scenes/vfx_lab/crack.gdshader")
var _outer: MeshInstance3D
var _core: MeshInstance3D
var _om: ShaderMaterial
var _cm: ShaderMaterial
var _embers: GPUParticles3D
var _scorch: MeshInstance3D
var _scorch_mat: ShaderMaterial
var _light: OmniLight3D

func _init() -> void:
	duration = 1.3

func _build() -> void:
	var aabb := AABB(Vector3(-4, -3, -7), Vector3(8, 7, 7.5))
	_om = ShaderMaterial.new()
	_om.shader = SHADER
	_outer = MeshInstance3D.new()
	_outer.mesh = _tube_mesh(20, 14, aabb)
	_outer.material_override = _om
	_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outer)
	_cm = ShaderMaterial.new()
	_cm.shader = SHADER
	_cm.set_shader_parameter("core_mix", 1.0)
	_cm.set_shader_parameter("flicker", 11.0)
	_core = MeshInstance3D.new()
	_core.mesh = _outer.mesh
	_core.material_override = _cm
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_core.visible = quality >= 1
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, -1)
	pm.spread = 22.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.5
	pm.gravity = Vector3(0, 1.4, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.scale_min = 0.4
	pm.scale_max = 1.1
	pm.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.5, 0.1, 0.9), Color(0.5, 0.1, 0.02, 0)], [0.0, 0.45, 1.0])
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	_embers = _particles(28, 0.9, _puff_material(1.0, 0.5, 2.0), pm, false, 0.1)
	_embers.position = Vector3(0, 1.1, -0.3)
	add_child(_embers)
	_scorch = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.2, 4.2)
	qm.orientation = PlaneMesh.FACE_Y
	_scorch.mesh = qm
	_scorch_mat = ShaderMaterial.new()
	_scorch_mat.shader = DECAL
	_scorch_mat.set_shader_parameter("mode", 1)
	_scorch_mat.set_shader_parameter("tint", Color(0.05, 0.035, 0.03))
	_scorch.material_override = _scorch_mat
	_scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scorch.position = Vector3(0, 0.03, -3.6)
	add_child(_scorch)
	if quality >= 2:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.2)
		_light.omni_range = 7.0
		_light.light_energy = 0.0
		_light.shadow_enabled = false
		_light.position = Vector3(0, 1.3, -2.0)
		add_child(_light)

func _on_start() -> void:
	_restart_particles(_embers)

func _apply(t: float) -> void:
	var prog := ease_out(t / 0.32)
	var life := 1.0 - smoothstep(0.55, 1.25, t)
	life = minf(life, smoothstep(0.0, 0.05, t) * 1.0 + 0.0001)
	for m in [_om, _cm]:
		m.set_shader_parameter("progress", prog)
		m.set_shader_parameter("life", life)
		m.set_shader_parameter("length_m", 5.2)
	_outer.position = Vector3(0, 1.15, -0.2)
	_core.position = _outer.position
	_embers.emitting = playing and t < 0.85
	_scorch_mat.set_shader_parameter("grow", ease_out((t - 0.2) / 0.5))
	_scorch_mat.set_shader_parameter("fade", (1.0 - smoothstep(0.9, 1.3, t)) * smoothstep(0.15, 0.3, t))
	if _light:
		_light.light_energy = 2.4 * life * (0.85 + 0.15 * sin(t * 60.0))
