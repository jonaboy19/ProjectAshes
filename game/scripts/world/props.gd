class_name Props
extends RefCounted
## Procedural low-poly props: stand-ins for real art so the world is playable now.
## Every builder returns a Node3D whose origin sits on the ground.

const WOOD := Color("6b4a2f")
const WOOD_LIGHT := Color("9a7048")
const STONE := Color("8d8a86")
const BRONZE := Color("c08a3e")
const PLASTER := Color("e8d9bc")
const ROOF_COLORS := [Color("9c3b2e"), Color("7a4632"), Color("5b5f7a"), Color("8a5a2b")]

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


static func house(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var w := rng.randf_range(4.5, 6.5)
	var d := rng.randf_range(4.0, 5.5)
	var h := rng.randf_range(2.6, 3.4)
	var roof_color: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()]
	# Stone footing, plaster walls, timber corners.
	part(root, box(Vector3(w + 0.3, 0.5, d + 0.3)), STONE, Vector3(0, 0.25, 0))
	part(root, box(Vector3(w, h, d)), PLASTER, Vector3(0, 0.5 + h / 2.0, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			part(root, box(Vector3(0.25, h, 0.25)), WOOD, Vector3(sx * w / 2.0, 0.5 + h / 2.0, sz * d / 2.0))
	part(root, box(Vector3(w + 0.1, 0.25, d + 0.1)), WOOD, Vector3(0, 0.5 + h, 0))
	# Gabled roof.
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 1.0, 2.0, d + 1.0)
	part(root, roof, roof_color, Vector3(0, 0.5 + h + 1.1, 0))
	# Door faces +Z (toward the plaza once rotated), plus windows.
	part(root, box(Vector3(1.1, 1.9, 0.12)), WOOD, Vector3(0, 1.45, d / 2.0 + 0.02))
	for sx in [-1, 1]:
		part(root, box(Vector3(0.8, 0.7, 0.1)), Color("3a2c22"), Vector3(sx * w * 0.3, 2.2, d / 2.0 + 0.02))
	# Chimney on some houses.
	if rng.randf() < 0.6:
		part(root, box(Vector3(0.6, 1.8, 0.6)), STONE, Vector3(w * 0.25, 0.5 + h + 1.6, -d * 0.2))
	add_box_collider(root, Vector3(w, h + 1.5, d), Vector3(0, (h + 1.5) / 2.0, 0))
	return root


static func chapel() -> Node3D:
	var root := Node3D.new()
	part(root, box(Vector3(7.4, 0.5, 11.4)), STONE, Vector3(0, 0.25, 0))
	part(root, box(Vector3(7, 4.5, 11)), Color("efe8dc"), Vector3(0, 2.75, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(8, 3, 12)
	part(root, roof, Color("4d5570"), Vector3(0, 6.5, 0))
	# Steeple over the entrance (+Z).
	part(root, box(Vector3(2.6, 5, 2.6)), Color("efe8dc"), Vector3(0, 7.5, 4.2))
	part(root, cylinder(0.0, 2.0, 4.0, 4), Color("4d5570"), Vector3(0, 12, 4.2), Vector3(0, PI / 4.0, 0))
	part(root, box(Vector3(0.15, 1.4, 0.15)), Color("e9c46a"), Vector3(0, 14.6, 4.2))
	part(root, box(Vector3(0.8, 0.15, 0.15)), Color("e9c46a"), Vector3(0, 14.8, 4.2))
	part(root, box(Vector3(1.6, 2.6, 0.15)), WOOD, Vector3(0, 1.8, 5.52))
	for z in [-3.0, 0.0]:
		for sx in [-1, 1]:
			part(root, box(Vector3(0.12, 1.8, 0.9)), Color("6f8fb5"), Vector3(sx * 3.52, 3.0, z))
	add_box_collider(root, Vector3(7, 6, 11), Vector3(0, 3, 0))
	return root


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


static func fence_segment(length: float) -> Node3D:
	var root := Node3D.new()
	part(root, box(Vector3(0.22, 1.6, 0.22)), WOOD, Vector3(0, 0.8, 0))
	for y in [0.55, 1.15]:
		part(root, box(Vector3(0.1, 0.14, length)), WOOD_LIGHT, Vector3(0, y, length / 2.0))
	return root


static func well() -> Node3D:
	var root := Node3D.new()
	part(root, cylinder(1.0, 1.1, 0.9, 10), STONE, Vector3(0, 0.45, 0))
	part(root, cylinder(0.8, 0.8, 0.05, 10), Color("2d4b66"), Vector3(0, 0.8, 0))
	for sx in [-1, 1]:
		part(root, box(Vector3(0.15, 2.0, 0.15)), WOOD, Vector3(sx * 0.9, 1.4, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(2.4, 0.8, 1.6)
	part(root, roof, ROOF_COLORS[0], Vector3(0, 2.7, 0))
	add_box_collider(root, Vector3(2.2, 1.2, 2.2), Vector3(0, 0.6, 0))
	return root


static func market_stall(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var cloth: Color = [Color("c9533c"), Color("d9a441"), Color("5b8c6b"), Color("6a5d9c")][rng.randi() % 4]
	part(root, box(Vector3(2.4, 0.9, 1.2)), WOOD, Vector3(0, 0.45, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			part(root, box(Vector3(0.1, 2.2, 0.1)), WOOD, Vector3(sx * 1.15, 1.1, sz * 0.55))
	part(root, box(Vector3(2.7, 0.08, 1.6)), cloth, Vector3(0, 2.25, 0), Vector3(0.15, 0, 0))
	for i in 3:
		part(root, sphere(0.16, 6, 3), [Color("d94f3d"), Color("e3b448"), Color("7fae4d")][i], Vector3(-0.6 + i * 0.6, 1.0, 0))
	add_box_collider(root, Vector3(2.4, 1.0, 1.2), Vector3(0, 0.5, 0))
	return root


static func crate() -> Node3D:
	var root := Node3D.new()
	part(root, box(Vector3(0.9, 0.9, 0.9)), WOOD_LIGHT, Vector3(0, 0.45, 0))
	return root


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
