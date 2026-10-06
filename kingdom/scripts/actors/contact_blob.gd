extends RefCounted
## Cheap contact shadow under a character (AAA pass 2026-10-06): one shared flat quad with the multiply-blend radial falloff
## of shaders/contact_shadow.gdshader. The Mobile renderer has no SSAO, so without it people and horses looked pasted onto the
## cobbles. One draw per nearby character, culled at RANGE; props already get batched blobs (settlement_builder.gd).

const RANGE := 30.0
static var _mesh: PlaneMesh


static func attach(parent: Node3D, radius := 0.45, strength := 0.5) -> MeshInstance3D:
	var q: Node = Engine.get_main_loop().root.get_node_or_null("Quality") if Engine.get_main_loop() is SceneTree else null
	if q != null and int(q.get("tier")) <= 0:
		return MeshInstance3D.new()     # LOW: one draw per character is over the 135 budget; a detached dummy keeps callers simple
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/contact_shadow.gdshader")
		mat.set_shader_parameter("strength", strength)
		_mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "ContactBlob"
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = RANGE
	mi.set_meta("no_camera_fade", true)
	mi.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	mi.position.y = 0.03
	parent.add_child(mi)
	return mi
