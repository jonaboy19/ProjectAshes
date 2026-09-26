class_name VFX
extends RefCounted
## Combat and magic effects, all procedural (no texture assets): sword arcs,
## impact sparks, elemental bursts for martial arts and magic, shockwave rings,
## flashes and a rising qi aura. Every effect frees itself.
##
##   VFX.slash(world, pos, yaw, tilt, color)        melee arc
##   VFX.sparks(world, pos, color, count)           impact
##   VFX.burst(world, pos, "fire"|"water"|"wind"|"earth"|"lightning"|"qi")
##   VFX.shockwave(world, pos, color, radius)
##   VFX.aura(node, color) -> GPUParticles3D        persistent; free it yourself
## Mobile renderer friendly: GPUParticles3D with small counts, unshaded additive.

const SHADER := preload("res://shaders/vfx_glow.gdshader")

const ELEMENTS := {
	"fire": {"color": Color(1.0, 0.45, 0.12), "up": 5.0, "gravity": 2.5, "spread": 55.0, "speed": 4.0, "count": 60, "size": 0.35, "life": 0.9},
	"water": {"color": Color(0.35, 0.75, 1.0), "up": 6.0, "gravity": -12.0, "spread": 50.0, "speed": 6.0, "count": 70, "size": 0.22, "life": 0.9},
	"wind": {"color": Color(0.85, 1.0, 0.95), "up": 1.0, "gravity": 0.0, "spread": 180.0, "speed": 9.0, "count": 50, "size": 0.18, "life": 0.6},
	"earth": {"color": Color(0.75, 0.55, 0.3), "up": 7.0, "gravity": -16.0, "spread": 35.0, "speed": 7.0, "count": 40, "size": 0.3, "life": 1.1},
	"lightning": {"color": Color(0.7, 0.8, 1.0), "up": 0.0, "gravity": 0.0, "spread": 180.0, "speed": 14.0, "count": 40, "size": 0.12, "life": 0.25},
	"qi": {"color": Color(1.0, 0.85, 0.35), "up": 2.0, "gravity": 1.5, "spread": 180.0, "speed": 3.0, "count": 50, "size": 0.2, "life": 1.0},
}


static func _material(color: Color, shape := 0, energy := 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("energy", energy)
	return m


static func _free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds).timeout.connect(node.queue_free)


## Curved ribbon arc in front of `pos`, sweeping over 0.16 s then fading.
## `tilt` rolls the arc (0 = horizontal slice, ±1.2 = diagonal).
static func slash(parent: Node, pos: Vector3, yaw: float, tilt := 0.0, color := Color(1.0, 0.9, 0.7), radius := 1.5) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18
	var arc := deg_to_rad(150.0)
	var inner := radius * 0.55
	for i in segs:
		for k in 2:
			pass
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var a0 := -arc * 0.5 + arc * t0
		var a1 := -arc * 0.5 + arc * t1
		var p0i := Vector3(sin(a0) * inner, 0, cos(a0) * inner)
		var p0o := Vector3(sin(a0) * radius, 0, cos(a0) * radius)
		var p1i := Vector3(sin(a1) * inner, 0, cos(a1) * inner)
		var p1o := Vector3(sin(a1) * radius, 0, cos(a1) * radius)
		for v in [[p0i, Vector2(t0, 0)], [p0o, Vector2(t0, 1)], [p1o, Vector2(t1, 1)],
				[p0i, Vector2(t0, 0)], [p1o, Vector2(t1, 1)], [p1i, Vector2(t1, 0)]]:
			st.set_color(Color.WHITE)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _material(color, 1, 4.0)
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(0, yaw, tilt)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.16)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 1.0, 1.6, 0.18)
	tw.tween_callback(mi.queue_free)


static func _particles(parent: Node, pos: Vector3, color: Color, count: int, life: float, size: float,
		speed: float, spread: float, gravity: Vector3, direction := Vector3.UP, stretch := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = gravity
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size * (0.35 if stretch else 1.0), size * (2.2 if stretch else 1.0))
	quad.material = _material(color, 0, 3.0)
	if stretch:
		pm.particle_flag_align_y = true
	else:
		(quad.material as ShaderMaterial).set_shader_parameter("shape", 0)
	p.draw_pass_1 = quad
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD if not stretch else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, life + 0.5)
	return p


static func sparks(parent: Node, pos: Vector3, color := Color(1.0, 0.75, 0.35), count := 24) -> void:
	_particles(parent, pos, color, count, 0.35, 0.16, 9.0, 70.0, Vector3(0, -14, 0), Vector3.UP, true)
	flash(parent, pos, color, 1.5, 0.12)


static func flash(parent: Node, pos: Vector3, color: Color, energy := 2.0, seconds := 0.2, light_range := 5.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, seconds)
	tw.tween_callback(l.queue_free)


## Expanding flat ring on the ground (landing strikes, qi release, spell impacts).
static func shockwave(parent: Node, pos: Vector3, color := Color(1.0, 0.85, 0.4), radius := 4.0, seconds := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 4
	mi.mesh = ring
	var mat := _material(color, 0, 3.0)
	mat.set_shader_parameter("shape", 1)
	mat.set_shader_parameter("progress", 1.2)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 0.05, 0.3)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("tint", Color(color, v)), 1.0, 0.0, seconds)
	tw.chain().tween_callback(mi.queue_free)


## Elemental burst: the building block for martial arts and spells.
static func burst(parent: Node, pos: Vector3, element := "qi", power := 1.0) -> void:
	var e: Dictionary = ELEMENTS.get(element, ELEMENTS["qi"])
	var col: Color = e["color"]
	_particles(parent, pos, col, int(float(e["count"]) * power), float(e["life"]), float(e["size"]) * sqrt(power),
		float(e["speed"]) * power, float(e["spread"]), Vector3(0, float(e["gravity"]), 0), Vector3.UP,
		element == "water" or element == "lightning" or element == "earth")
	flash(parent, pos + Vector3(0, 0.6, 0), col, 3.0 * power, 0.3, 7.0 * power)
	shockwave(parent, pos, col, 3.0 * power)
	if element == "lightning":
		_bolt(parent, pos + Vector3(0, 9, 0), pos, col)
	if element == "fire":
		_particles(parent, pos, Color(0.25, 0.22, 0.2), 16, 1.6, 0.9, 1.5, 30.0, Vector3(0, 1.2, 0))


static func _bolt(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [from]
	for i in range(1, 9):
		var t := i / 9.0
		pts.append(from.lerp(to, t) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))
	pts.append(to)
	var w := 0.12
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(Vector3.FORWARD).normalized() * w
		for v in [[a - side, Vector2(0, 0)], [a + side, Vector2(0, 1)], [b + side, Vector2(1, 1)],
				[a - side, Vector2(0, 0)], [b + side, Vector2(1, 1)], [b - side, Vector2(1, 0)]]:
			st.set_color(Color.WHITE)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _material(color, 1, 6.0)
	mat.set_shader_parameter("progress", 1.0)
	mi.material_override = mat
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_interval(0.08)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("tint", Color(color, v)), 1.0, 0.0, 0.18)
	tw.tween_callback(mi.queue_free)


## Rising qi aura around a character (cultivation, power-up, martial stance).
static func aura(node: Node3D, color := Color(1.0, 0.85, 0.35), height := 1.8) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.2
	p.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.55
	pm.emission_ring_inner_radius = 0.35
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = height * 0.6
	pm.initial_velocity_max = height * 1.1
	pm.gravity = Vector3.ZERO
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.2, Color(1, 1, 1, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.5)
	quad.material = _material(color, 0, 2.5)
	pm.particle_flag_align_y = true
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(p)
	return p
