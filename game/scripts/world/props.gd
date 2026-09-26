class_name Props
extends RefCounted
## Procedural low-poly props for story-specific pieces the asset packs lack
## (bell tower, Rift scar, lanterns).
## Every builder returns a Node3D whose origin sits on the ground.

const WOOD := Color("6b4a2f")
const WOOD_LIGHT := Color("9a7048")
const STONE := Color("8d8a86")
const BRONZE := Color("c08a3e")
const PLASTER := Color("e8d9bc")

static var _materials: Dictionary = {}


static func mat(color: Color, emission := 0.0, vertex_colors := false, toon := true) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), emission, vertex_colors, toon]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if toon else BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.vertex_color_use_as_albedo = vertex_colors
	m.vertex_color_is_srgb = true
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


static func part(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(top: float, bottom: float, height: float, segments := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, segments := 8, rings := 5) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func add_box_collider(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.position = pos
	body.add_child(shape)
	parent.add_child(body)






## Bell tower with thirteen bells. Returns the root; bells are in root.get_meta("bells").
static func bell_tower() -> Node3D:
	var root := Node3D.new()
	part(root, cylinder(3.6, 4.2, 1.2, 12), STONE, Vector3(0, 0.6, 0))
	part(root, box(Vector3(4.4, 1.4, 4.4)), STONE, Vector3(0, 1.9, 0))
	part(root, box(Vector3(4.8, 0.25, 4.8)), Color("6f6b66"), Vector3(0, 2.7, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			part(root, box(Vector3(0.45, 8.4, 0.45)), WOOD, Vector3(sx * 1.7, 7.0, sz * 1.7))
			part(root, box(Vector3(0.12, 0.12, 3.4)), WOOD_LIGHT, Vector3(sx * 1.7, 5.0, 0))
			part(root, box(Vector3(3.4, 0.12, 0.12)), WOOD_LIGHT, Vector3(0, 7.5, sz * 1.7))
	part(root, box(Vector3(4.4, 0.35, 4.4)), WOOD, Vector3(0, 11.2, 0))
	part(root, cylinder(0.0, 4.0, 3.4, 4), Color("7a2f26"), Vector3(0, 13.1, 0), Vector3(0, PI / 4.0, 0))
	# Twelve bells in a ring around the thirteenth, larger centre bell.
	var bells: Array[Node3D] = []
	for i in 13:
		var pivot := Node3D.new()
		var is_center := i == 12
		var angle := TAU * float(i) / 12.0
		pivot.position = Vector3(0, 10.9, 0) if is_center else Vector3(cos(angle) * 1.25, 10.9, sin(angle) * 1.25)
		root.add_child(pivot)
		var scale := 1.5 if is_center else 0.75
		var bell := part(pivot, cylinder(0.18 * scale, 0.42 * scale, 0.6 * scale, 10), BRONZE, Vector3(0, -0.45 * scale, 0))
		bell.material_override = bell_material()
		part(pivot, sphere(0.08 * scale, 6, 3), Color("3a2c22"), Vector3(0, -0.8 * scale, 0))
		pivot.set_meta("mesh", bell)
		bells.append(pivot)
	root.set_meta("bells", bells)
	add_box_collider(root, Vector3(4.4, 2.8, 4.4), Vector3(0, 1.4, 0))
	return root


## Each bell gets its own material so it can glow independently while ringing.
static func bell_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(BRONZE).duplicate()
	m.emission_enabled = true
	m.emission = Color("ffd27a")
	m.emission_energy_multiplier = 0.0
	return m










static func lantern_post() -> Node3D:
	var root := Node3D.new()
	part(root, box(Vector3(0.14, 2.6, 0.14)), WOOD, Vector3(0, 1.3, 0))
	var glow := part(root, box(Vector3(0.35, 0.45, 0.35)), Color("ffc46b"), Vector3(0, 2.75, 0))
	glow.material_override = mat(Color("ffc46b"), 2.5)
	return root


## Jagged crystals and a tear in the air: the Rift scar on the south road.
static func rift_scar(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var purple := Color("9b4dff")
	for i in 14:
		var h := rng.randf_range(1.0, 4.5)
		var crystal := part(root, cylinder(0.0, rng.randf_range(0.25, 0.6), h, 5), purple,
			Vector3(rng.randf_range(-6, 6), h / 2.0 - 0.2, rng.randf_range(-6, 6)),
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
		crystal.material_override = mat(purple, 1.6)
	part(root, cylinder(6.5, 7.0, 0.1, 14), Color("2a1b35"), Vector3(0, 0.05, 0))
	var tear := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 5.0)
	tear.mesh = quad
	var tear_mat := StandardMaterial3D.new()
	tear_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tear_mat.albedo_color = Color(0.85, 0.55, 1.0, 0.85)
	tear_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tear_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tear_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	tear.material_override = tear_mat
	tear.position = Vector3(0, 3.2, 0)
	root.add_child(tear)
	root.set_meta("tear", tear)
	return root
