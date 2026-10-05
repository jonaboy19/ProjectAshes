class_name WaterWhip
extends LabFX
## WATER WHIP (bending): a tube of water cracks forward from the hand along a swinging Bezier, grows a bulb head,
## sheds droplets, then the tail catches up and it splashes. 1 mesh (13*... = 25x9 verts), 2 small particle systems
## (<= 40 particles), 1 wet-ring decal. All motion is shader/uniform driven.
const SHADER := preload("res://scenes/vfx_lab/water_whip.gdshader")
const DECAL := preload("res://scenes/vfx_lab/crack.gdshader")
var _mat: ShaderMaterial
var _tube: MeshInstance3D
var _drops: GPUParticles3D
var _splash: GPUParticles3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _splash_done := false

func _init() -> void:
	duration = 1.35

func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_tube = MeshInstance3D.new()
	_tube.mesh = _tube_mesh(28, 10, AABB(Vector3(-4, -1, -8), Vector3(8, 5, 9)))
	_tube.material_override = _mat
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tube)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -7.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(0.85, 0.97, 1, 0.9), Color(0.5, 0.82, 1, 0.7), Color(0.4, 0.7, 1, 0)], [0.0, 0.5, 1.0])
	_drops = _particles(24, 0.6, _puff_material(0.0, 0.35, 1.0), pm, false, 0.12)
	add_child(_drops)
	var pm2 := ParticleProcessMaterial.new()
	pm2.direction = Vector3(0, 1, 0)
	pm2.spread = 55.0
	pm2.initial_velocity_min = 1.8
	pm2.initial_velocity_max = 4.2
	pm2.gravity = Vector3(0, -9.0, 0)
	pm2.scale_min = 0.6
	pm2.scale_max = 1.5
	pm2.color_ramp = _ramp([Color(0.95, 1, 1, 1), Color(0.55, 0.85, 1, 0.8), Color(0.4, 0.7, 1, 0)], [0.0, 0.4, 1.0])
	_splash = _particles(16, 0.55, _puff_material(0.0, 0.4, 1.0), pm2, true, 0.16)
	add_child(_splash)
	_ring = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 3.4)
	qm.orientation = PlaneMesh.FACE_Y
	_ring.mesh = qm
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = DECAL
	_ring_mat.set_shader_parameter("mode", 2)
	_ring_mat.set_shader_parameter("tint", Color(0.7, 0.92, 1.0))
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.visible = false

func _on_start() -> void:
	_splash_done = false
	_ring.visible = false
	_drops.emitting = true

## 0..0.5 s: head whips out (ease-out) while the control points swing from right to left; 0.35..1.0: tail follows.
func _apply(t: float) -> void:
	var head := ease_out(t / 0.5)
	var tail := ease_out((t - 0.5) / 0.6) * 0.985
	var swing := ease_out(t / 0.55)
	var p0 := Vector3(0.0, 1.15, -0.2)
	var p1 := Vector3(lerpf(1.9, -0.6, swing), lerpf(2.7, 1.9, swing), -1.4)
	var p2 := Vector3(lerpf(-1.5, 1.1, swing), lerpf(0.2, 1.2, swing), -3.0)
	var p3 := Vector3(lerpf(0.4, -0.2, swing), lerpf(0.5, 0.35, swing), -5.2)
	_mat.set_shader_parameter("p0", p0)
	_mat.set_shader_parameter("p1", p1)
	_mat.set_shader_parameter("p2", p2)
	_mat.set_shader_parameter("p3", p3)
	_mat.set_shader_parameter("head", head)
	_mat.set_shader_parameter("tail", minf(tail, head - 0.04))
	_mat.set_shader_parameter("fade", 1.0 - smoothstep(1.0, 1.33, t))
	# droplets ride the head
	var hp := _bez(p0, p1, p2, p3, head)
	_drops.position = hp
	_drops.emitting = playing and t < 1.0
	if t >= 0.5 and not _splash_done:
		_splash_done = true
		_splash.position = Vector3(p3.x, 0.15, p3.z)
		_restart_particles(_splash)
		_ring.visible = true
		_ring.position = Vector3(p3.x, 0.03, p3.z)
	if _ring.visible:
		var g := clampf((t - 0.5) / 0.6, 0.0, 1.0)
		_ring_mat.set_shader_parameter("grow", g)
		_ring_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.7, 1.3, t - 0.1))

static func _bez(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var s := 1.0 - t
	return a * s * s * s + b * 3.0 * s * s * t + c * 3.0 * s * t * t + d * t * t * t
