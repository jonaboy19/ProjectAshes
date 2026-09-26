class_name GrassField
extends RefCounted
## Builds the grass MultiMesh for one terrain chunk. Only chunks next to the
## player get grass (see TerrainStreamer.grass_radius), and each instance fades
## out by distance, so thousands of blades stay affordable.

const CLUMPS_PER_CHUNK := 1500
const FADE_END := 70.0
const SHADER := preload("res://shaders/grass.gdshader")

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


static func build(origin: Vector2, size: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Blender-made alpha-card clumps (tools/blender/make_nature.py) with the wind
	# material assigned at import; a few tall tufts and wildflowers mixed in.
	var kinds := {"grass_clump": [], "grass_clump_tall": [], "flowers_a": []}
	for i in CLUMPS_PER_CHUNK:
		var x := origin.x + rng.randf() * size
		var z := origin.y + rng.randf() * size
		if not _grassy(x, z):
			continue
		var roll := rng.randf()
		var kind := "grass_clump" if roll < 0.82 else ("grass_clump_tall" if roll < 0.95 else "flowers_a")
		var s := rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.25), s))
		(kinds[kind] as Array).append(Transform3D(basis, Vector3(x, WorldGen.height(x, z) - 0.03, z)))
	var root := Node3D.new()
	for kind: String in kinds:
		var list: Array = kinds[kind]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _clump_mesh(kind)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = FADE_END
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)
	return root if root.get_child_count() > 0 else null


static func _grassy(x: float, z: float) -> bool:
	if WorldGen.road_distance(x, z) < 3.5 or WorldGen.is_water(x, z):
		return false
	var near := WorldGen.nearest_settlement(Vector2(x, z))
	if not near.is_empty():
		var dc := Vector2(x, z).distance_to(near["pos"])
		if dc < near["plan"]["plaza_r"] + 3.0 or WorldGen.street_distance(x, z) < 1.5:
			return false
		if near["kind"] != "village" and dc < near["radius"]:
			return false
	var h := WorldGen.height(x, z)
	var slope := absf(WorldGen.height(x + 1.0, z) - h) + absf(WorldGen.height(x, z + 1.0) - h)
	return slope < 0.9 and h < 90.0


static var _meshes := {}


static func _clump_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var scene := load("res://assets/generated/nature/%s.glb" % kind) as PackedScene
	var mesh: Mesh = null
	if scene:
		var n := scene.instantiate()
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			mesh = (mis[0] as MeshInstance3D).mesh
		n.free()
	_meshes[kind] = mesh
	return mesh


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material
