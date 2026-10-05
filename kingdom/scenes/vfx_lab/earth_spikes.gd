class_name EarthSpikes
extends LabFX
## EARTH SPIKES (bending): a fan of rock spikes erupts in a wave along -Z, overshoots, holds, then sinks. One MultiMesh
## (single draw call, flat-shaded 6-sided spikes, per-spike delay/height/width/lean in custom data), a crack decal
## along the line and two small dust bursts. All rise/sink motion is in earth_rock.gdshader, driven by one float.
const SHADER := preload("res://scenes/vfx_lab/earth_rock.gdshader")
const DECAL := preload("res://scenes/vfx_lab/crack.gdshader")
const COUNT := 11
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _dust: GPUParticles3D
var _chips: GPUParticles3D
var _crack: MeshInstance3D
var _crack_mat: ShaderMaterial
var _burst_at := [0.0, 0.0]
var _burst_done := [false, false]

func _init() -> void:
	duration = 2.2

func _spike_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sides := 6
	var base := []
	for i in range(sides):
		var a := TAU * i / sides + rng.randf_range(-0.12, 0.12)
		base.append(Vector3(cos(a) * 0.5 * rng.randf_range(0.85, 1.15), 0.0, sin(a) * 0.5 * rng.randf_range(0.85, 1.15)))
	var apex := Vector3(rng.randf_range(-0.08, 0.08), 1.0, rng.randf_range(-0.08, 0.08))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(sides):
		var a: Vector3 = base[i]
		var b: Vector3 = base[(i + 1) % sides]
		var n := (b - a).cross(apex - a).normalized()
		for v in [a, b, apex]:
			verts.append(v)
			norms.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 4.0, 2.4))
	return m

func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _spike_mesh()
	mm.instance_count = COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(COUNT):
		var row := i % 3                         # three staggered rows: centre line taller, flanks shorter
		var k := float(i) / (COUNT - 1)
		var dist := 1.1 + k * 4.6
		var lat := (row - 1) * (0.55 + 0.35 * k) + rng.randf_range(-0.15, 0.15)
		var tall := (2.2 if row == 1 else 1.3) * (0.8 + 0.7 * k) + rng.randf_range(-0.1, 0.15)
		var wide := (1.05 if row == 1 else 0.8) * (0.85 + 0.5 * k)
		var yaw := rng.randf() * TAU
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), Vector3(lat, 0.0, -dist)))
		# lean outward from the centre line, delay along the run
		mm.set_instance_custom_data(i, Color(k * 0.32 + rng.randf() * 0.03, tall, wide, (row - 1) * 0.28))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.custom_aabb = AABB(Vector3(-4, -1, -8), Vector3(8, 5, 8.5))
	add_child(_mmi)
	_crack = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.2, 7.4)
	qm.orientation = PlaneMesh.FACE_Y
	_crack.mesh = qm
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = DECAL
	_crack_mat.set_shader_parameter("mode", 0)
	_crack.material_override = _crack_mat
	_crack.position = Vector3(0, 0.03, -3.9)
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -1.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.8
	pm.scale_max = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.2, 0.05, 2.6)
	pm.color_ramp = _ramp([Color(0.6, 0.5, 0.38, 0.0), Color(0.6, 0.5, 0.38, 0.3), Color(0.55, 0.46, 0.35, 0)], [0.0, 0.2, 1.0])
	_dust = _particles(20, 1.1, _puff_material(0.0, 0.9, 1.0), pm, true, 0.7)
	_dust.position = Vector3(0, 0.1, -3.7)
	add_child(_dust)
	var pc := ParticleProcessMaterial.new()
	pc.direction = Vector3(0, 1, 0)
	pc.spread = 40.0
	pc.initial_velocity_min = 2.5
	pc.initial_velocity_max = 5.0
	pc.gravity = Vector3(0, -12.0, 0)
	pc.scale_min = 0.5
	pc.scale_max = 1.0
	pc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pc.emission_box_extents = Vector3(1.0, 0.05, 2.4)
	pc.color_ramp = _ramp([Color(0.34, 0.26, 0.18, 1), Color(0.3, 0.22, 0.15, 1), Color(0.3, 0.22, 0.15, 0)], [0.0, 0.7, 1.0])
	_chips = _particles(14, 0.7, _puff_material(0.0, 0.2, 1.0), pc, true, 0.09)
	_chips.position = Vector3(0, 0.1, -3.7)
	add_child(_chips)

func _on_start() -> void:
	_restart_particles(_dust)
	_restart_particles(_chips)

func _apply(t: float) -> void:
	var tl := clampf(t / duration, 0.0, 1.0)
	_mat.set_shader_parameter("t", tl)
	_mat.set_shader_parameter("rise_time", 0.09)
	_mat.set_shader_parameter("sink_start", 0.7)
	_crack_mat.set_shader_parameter("grow", ease_out(t / 0.45))
	_crack_mat.set_shader_parameter("fade", (1.0 - smoothstep(1.4, 2.1, t)) * smoothstep(0.0, 0.1, t))
