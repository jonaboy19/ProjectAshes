extends RefCounted
## LampGlow: torches, braziers and lanterns without omni lights. One call per town / site:
##
##   LampGlow.build(root, [{pos: Vector3 (world), color: Color, range: float, size: float}...]) -> Array of LampNode
##
## adds ONE MultiMeshInstance3D of flickering billboard glows (shaders/vfx/flame_glow.gdshader; the whole street is a
## single draw call) plus one LampNode per lamp, which keeps the "street_lamp" group contract
## (light_energy, omni_range) for main.gd's night switch and Perception, and adds a real OmniLight3D only on
## HIGH / ULTRA (lamp_node.gd). Props with their own emissive mesh (braziers, wall torches) live in torch_props.gd.

const LampNode := preload("res://scripts/world/lamp_node.gd")
const SHADER := preload("res://shaders/vfx/flame_glow.gdshader")

static var _quad: QuadMesh


static func _mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static func build(root: Node3D, specs: Array, glow_size := 1.3) -> Array:
	var out: Array = []
	if root == null or specs.is_empty():
		return out
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = specs.size()
	var first_col: Color = specs[0].get("color", Color(1.0, 0.62, 0.25))
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var size := float(sp.get("size", glow_size))
		var pos: Vector3 = sp["pos"]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), pos))
		var col: Color = sp.get("color", Color(1.0, 0.62, 0.25))
		mm.set_instance_custom_data(i, Color(randf(), col.r, col.g, col.b))
	var mi := MultiMeshInstance3D.new()
	mi.name = "LampGlowBatch"
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("glow_color", first_col)
	mat.set_shader_parameter("lit", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 80, 400))   # instances spread over the whole town
	mi.visible = false
	root.add_child(mi)
	for sp: Dictionary in specs:
		var n := LampNode.new()
		n.name = "Lamp"
		n.omni_range = float(sp.get("range", 9.0))
		n.light_color = sp.get("color", Color(1.0, 0.72, 0.4))
		n.batch = mi
		root.add_child(n)
		n.global_position = sp["pos"]
		out.append(n)
	return out
