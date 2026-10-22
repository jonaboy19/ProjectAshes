class_name LabFX
extends Node3D
## Base for the vfx_lab prototypes (Godot-native bending effects). Deterministic timeline: `age` advances in
## _process (or via seek() for sheets), subclasses implement _apply(age). Effects point along -Z, origin = the hand.
## Budget per effect (mobile): <= 40 GPUParticles3D particles in total, <= 4 transparent meshes, 1 optional light
## (HIGH tier only), no screen-texture reads, no depth-texture reads. Nothing allocates after _ready().
signal finished
@export var duration := 1.2
@export var quality := 2          ## 0 LOW (fewer particles, no light, no secondary shells), 1 MEDIUM, 2 HIGH
@export var autoplay := false
var age := -1.0
var playing := false
var _built := false

const PUFF := preload("res://scenes/vfx_lab/puff.gdshader")

func _ready() -> void:
	_ensure_built()
	if autoplay:
		play()

func _ensure_built() -> void:
	if not _built:
		_built = true
		_build()

func _build() -> void:
	pass

func _apply(_t: float) -> void:
	pass

func _on_start() -> void:
	pass

func play() -> void:
	_ensure_built()
	age = 0.0
	playing = true
	visible = true
	_on_start()
	_apply(0.0)

func seek(t: float) -> void:
	_ensure_built()
	age = t
	_apply(t)

func _process(delta: float) -> void:
	if not playing:
		return
	age += delta
	_apply(age)
	if age >= duration:
		playing = false
		visible = false
		finished.emit()

# ---- helpers shared by the effects --------------------------------------------------------------------------
func _puff_material(additive: float, softness := 0.55, intensity := 1.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PUFF
	m.set_shader_parameter("additive", additive)
	m.set_shader_parameter("softness", softness)
	m.set_shader_parameter("intensity", intensity)
	if additive > 0.5:
		m.render_priority = 1
	return m

func _ramp(cols: Array, offs: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 32
	return t

## Small GPU particle emitter with a procedural soft sprite. amount is scaled by `quality`.
func _particles(amount: int, life: float, mat: ShaderMaterial, pm: ParticleProcessMaterial, one_shot := false, size := 0.2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(amount * [0.5, 0.75, 1.0][clampi(quality, 0, 2)]))
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.fixed_fps = 30
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-8, -2, -12), Vector3(16, 8, 14))
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.draw_pass_1 = q
	p.process_material = pm
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	return p

func _restart_particles(p: GPUParticles3D) -> void:
	p.restart()
	p.emitting = true

## Tube mesh whose positions are all computed in the vertex shader: UV.x = along (0..1), UV.y = around (0..1).
func _tube_mesh(segments: int, sides: int, aabb: AABB) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in range(segments + 1):
		for j in range(sides + 1):
			verts.append(Vector3.ZERO)
			norms.append(Vector3.UP)
			uvs.append(Vector2(float(i) / segments, float(j) / sides))
	for i in range(segments):
		for j in range(sides):
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = aabb
	return m

static func ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)
