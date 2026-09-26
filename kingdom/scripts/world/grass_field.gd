class_name GrassField
extends RefCounted
## Builds the grass MultiMesh for one terrain chunk. Only chunks next to the
## player get grass (see TerrainStreamer.grass_radius), and each instance fades
## out by distance, so thousands of blades stay affordable.

const CLUMPS_PER_CHUNK := 2600
const FADE_END := 70.0
const SHADER := preload("res://shaders/grass.gdshader")

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


static func build(origin: Vector2, size: float, seed_value: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var transforms: Array[Transform3D] = []
	for i in CLUMPS_PER_CHUNK:
		var x := origin.x + rng.randf() * size
		var z := origin.y + rng.randf() * size
		if not _grassy(x, z):
			continue
		var s := rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		transforms.append(Transform3D(basis, Vector3(x, WorldGen.height(x, z) - 0.03, z)))
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _clump_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _get_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = FADE_END
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


static func _grassy(x: float, z: float) -> bool:
	if WorldGen.road_distance(x, z) < 3.5:
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


## One clump = five tapered blades fanned around the centre.
static func _clump_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 5:
		var ang := TAU * b / 5.0 + 0.3
		var out := Vector3(cos(ang), 0, sin(ang)) * 0.12
		var side := Vector3(-sin(ang), 0, cos(ang)) * 0.035
		var tip := out * 1.8 + Vector3(0, 0.55 + 0.1 * (b % 2), 0)
		for v in [[out - side, 0.0], [out + side, 0.0], [tip, 1.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.add_vertex(v[0])
	_mesh = st.commit()
	return _mesh


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material
