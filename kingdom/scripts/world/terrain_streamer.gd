class_name TerrainStreamer
extends Node3D
## Streams terrain chunks (ground mesh, collision, forest MultiMeshes) around a
## focus point. Builds at most one chunk per frame so movement never hitches;
## chunks outside the radius are freed and rebuilt identically when revisited.

const CHUNK := 64.0
const CELL := 2.0

@export var view_radius := 4         # chunks; 9x9 grid visible
@export var collision_radius := 1    # chunks that also get physics
@export var grass_radius := 1        # chunks that also get grass
var focus := Vector3.ZERO

var _chunks: Dictionary = {}         # Vector2i -> Node3D
var _ground_material: ShaderMaterial

## Poly Haven (CC0) PBR sets used for each terrain layer.
const TEX := "res://assets/incoming/polyhaven/textures/%s/%s_%s_2k.jpg"
const LAYERS := {"grass": "leafy_grass", "forest": "forest_ground_04", "path": "grass_path_2",
	"rock": "rocky_terrain_02", "cobble": "cobblestone_floor_01"}


func _ready() -> void:
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = preload("res://shaders/terrain.gdshader")
	for layer: String in LAYERS:
		var tex_name: String = LAYERS[layer]
		_ground_material.set_shader_parameter(layer + "_albedo", load(TEX % [tex_name, tex_name, "diff"]))
		_ground_material.set_shader_parameter(layer + "_normal", load(TEX % [tex_name, tex_name, "nor_gl"]))
		_ground_material.set_shader_parameter(layer + "_arm", load(TEX % [tex_name, tex_name, "arm"]))
	_ground_material.set_shader_parameter("macro_noise", _noise_texture(0.01, 3, false))


static func _noise_texture(freq: float, octaves: int, normal: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = 4.0
	t.generate_mipmaps = true
	return t


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
		var grass_near := maxi(absi(key.x - center.x), absi(key.y - center.y)) <= grass_radius
		var grass: Node = chunk.get_node_or_null("Grass")
		if grass_near and grass == null and not chunk.has_meta("no_grass"):
			var g := GrassField.build(Vector2(key.x * CHUNK, key.y * CHUNK), CHUNK, hash(key) ^ 0x6a55)
			if g:
				g.name = "Grass"
				chunk.add_child(g)
			else:
				chunk.set_meta("no_grass", true)
		elif not grass_near and grass != null:
			grass.queue_free()


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
	# Smooth, indexed grid. Normals come from the height function itself, so
	# neighbouring chunks match exactly at their seams.
	var n := int(CHUNK / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var x := origin.x + i * CELL
			var z := origin.y + j * CELL
			var h := WorldGen.height(x, z)
			var normal := Vector3(WorldGen.height(x - 1.0, z) - WorldGen.height(x + 1.0, z), 2.0,
				WorldGen.height(x, z - 1.0) - WorldGen.height(x, z + 1.0)).normalized()
			st.set_normal(normal)
			st.set_color(WorldGen.color_at(x, z, h, 1.0 - normal.y))
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	return st.commit()


func _add_forest(chunk: Node3D, key: Vector2i, origin: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5eed
	var buckets := {}
	for i in 90:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var density := WorldGen.forest_density(x, z)
		var h := WorldGen.height(x, z)
		if h > 115.0 or WorldGen.near_water(x, z, 1.5):
			continue
		var kind := ""
		var roll := rng.randf()
		if roll < density:
			# Pines on high ground, broadleaf lower down, the odd twisted or dead tree.
			var pine_bias := smoothstep(30.0, 70.0, h)
			if rng.randf() < 0.06:
				kind = ["TwistedTree_1", "TwistedTree_3", "DeadTree_2"][rng.randi() % 3]
			elif rng.randf() < 0.35 + pine_bias * 0.5:
				kind = "Pine_%d" % (1 + rng.randi() % 5)
			else:
				kind = "CommonTree_%d" % (1 + rng.randi() % 5)
		elif roll < density + 0.12 and WorldGen.road_distance(x, z) > 4.0 and WorldGen.street_distance(x, z) > 3.0:
			# Photo-scanned undergrowth under trees, wildflowers in the open.
			if density > 0.35:
				kind = ["scan/fern_02", "scan/fern_02", "scan/shrub_03", "scan/nettle_plant", "Bush_Common", "scan/tree_stump_01",
					"scan/tree_stump_02", "scan/root_cluster_01", "scan/dead_tree_trunk"][rng.randi() % 9]
			else:
				kind = ["scan/dandelion_01", "scan/nettle_plant", "Bush_Common_Flowers", "Flower_3_Group", "Flower_4_Group", "scan/shrub_03"][rng.randi() % 6]
		elif rng.randf() < 0.05:
			kind = "scan/rock_moss_set_0%d_%d" % [1 + rng.randi() % 2, 1 + rng.randi() % 6]
		if kind == "":
			continue
		var s := rng.randf_range(0.8, 1.25)
		if kind.contains("dandelion") or kind.contains("nettle"):
			s *= 2.6            # tiny real-scale plants read as a patch
		elif kind.begins_with("scan/rock"):
			s = rng.randf_range(0.5, 1.7)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.15, z))
		if not buckets.has(kind):
			buckets[kind] = []
		buckets[kind].append(t)
	for kind: String in buckets:
		var list: Array[Transform3D] = []
		list.assign(buckets[kind])
		_multimesh(chunk, Assets.nature_mesh(kind), list)


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
	mmi.visibility_range_end = 450.0
	parent.add_child(mmi)
