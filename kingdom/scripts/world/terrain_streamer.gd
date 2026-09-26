class_name TerrainStreamer
extends Node3D
## Streams terrain chunks (ground mesh, collision, forest MultiMeshes) around a
## focus point. Builds at most one chunk per frame so movement never hitches;
## chunks outside the radius are freed and rebuilt identically when revisited.

const CHUNK := 64.0
const CELL := 4.0
const TREE_KINDS := ["tree_single_A", "tree_single_B", "trees_A_medium", "trees_B_medium", "trees_A_large"]

@export var view_radius := 4         # chunks; 9x9 grid visible
@export var collision_radius := 1    # chunks that also get physics
var focus := Vector3.ZERO

var _chunks: Dictionary = {}         # Vector2i -> Node3D
var _ground_material: StandardMaterial3D


func _ready() -> void:
	_ground_material = Assets.flat_material(Color.WHITE, true)


func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func loaded_count() -> int:
	return _chunks.size()


## Build every chunk in range right now (used on spawn / teleport).
func build_all_now() -> void:
	while _step():
		pass


func _process(_delta: float) -> void:
	_step()


## Builds the nearest missing chunk and frees far ones. Returns true if work was done.
func _step() -> bool:
	var center := chunk_of(focus)
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > view_radius + 1:
			_chunks[key].queue_free()
			_chunks.erase(key)
	var best := Vector2i.ZERO
	var best_d := INF
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var key := center + Vector2i(dx, dz)
			if _chunks.has(key):
				continue
			var d := float(dx * dx + dz * dz)
			if d < best_d:
				best_d = d
				best = key
	if best_d == INF:
		_update_collision(center)
		return false
	_chunks[best] = _build_chunk(best)
	_update_collision(center)
	return true


func _update_collision(center: Vector2i) -> void:
	for key: Vector2i in _chunks:
		var chunk: Node3D = _chunks[key]
		var near := maxi(absi(key.x - center.x), absi(key.y - center.y)) <= collision_radius
		var body: StaticBody3D = chunk.get_node_or_null("Body")
		if near and body == null:
			body = StaticBody3D.new()
			body.name = "Body"
			var shape := CollisionShape3D.new()
			shape.shape = (chunk.get_node("Ground") as MeshInstance3D).mesh.create_trimesh_shape()
			body.add_child(shape)
			chunk.add_child(body)
		elif not near and body != null:
			body.queue_free()


func _build_chunk(key: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [key.x, key.y]
	var origin := Vector2(key.x * CHUNK, key.y * CHUNK)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = _ground_mesh(origin)
	ground.material_override = _ground_material
	chunk.add_child(ground)
	_add_forest(chunk, key, origin)
	add_child(chunk)
	return chunk


func _ground_mesh(origin: Vector2) -> ArrayMesh:
	var n := int(CHUNK / CELL)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			heights[j * (n + 1) + i] = WorldGen.height(origin.x + i * CELL, origin.y + j * CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for j in n:
		for i in n:
			var x0 := origin.x + i * CELL
			var z0 := origin.y + j * CELL
			var p00 := Vector3(x0, heights[j * (n + 1) + i], z0)
			var p10 := Vector3(x0 + CELL, heights[j * (n + 1) + i + 1], z0)
			var p01 := Vector3(x0, heights[(j + 1) * (n + 1) + i], z0 + CELL)
			var p11 := Vector3(x0 + CELL, heights[(j + 1) * (n + 1) + i + 1], z0 + CELL)
			_tri(st, p00, p10, p01)
			_tri(st, p10, p11, p01)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center := (a + b + c) / 3.0
	var normal := (c - a).cross(b - a).normalized()
	st.set_color(WorldGen.color_at(center.x, center.z, center.y, 1.0 - absf(normal.y)))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _add_forest(chunk: Node3D, key: Vector2i, origin: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed
	var buckets := {}
	for kind in TREE_KINDS:
		buckets[kind] = []
	var rocks: Array[Transform3D] = []
	for i in 70:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var density := WorldGen.forest_density(x, z)
		var h := WorldGen.height(x, z)
		if h > 110.0:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(5.0, 7.5)), Vector3(x, h - 0.2, z))
		if rng.randf() < density:
			var kind: String = TREE_KINDS[rng.randi() % TREE_KINDS.size()]
			buckets[kind].append(t)
		elif rng.randf() < 0.04:
			rocks.append(t)
	for kind: String in buckets:
		var list: Array[Transform3D] = []
		list.assign(buckets[kind])
		_multimesh(chunk, Assets.mesh_of(kind), list)
	var rock_kind: String = ["rock_single_A", "rock_single_C", "rock_single_E"][absi(key.x + key.y) % 3]
	_multimesh(chunk, Assets.mesh_of(rock_kind), rocks)


func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
