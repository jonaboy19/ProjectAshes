class_name TerrainStreamer
extends Node3D
## Streams terrain chunks (ground mesh, collision, forest MultiMeshes) around a
## focus point. Builds at most one chunk per frame so movement never hitches;
## chunks outside the radius are freed and rebuilt identically when revisited.

const CHUNK := 64.0
const CELL := 2.0
## Distance where Blender trees hand over to the cheap stylised stand-ins.
const TREE_LOD := 200.0
## Painterly region trees (generated/region/nature): LOD0 -> LOD1 -> 4-tri impostor
## card (_lod2) at these distances (Quality scales them: LOW x0.55 = 22 / 50 m).
const REGION_LODS := [40.0, 90.0]
const REGION := "region/nature/"

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
			# Blender-made trees near the player; the cheap stylised set stands in far away.
			var pine_bias := smoothstep(30.0, 70.0, h)
			var r2 := rng.randf()
			# Painterly region trees (0.7-1.6k tris, 1024 atlases) with their own LOD chain.
			if r2 < 0.05:
				kind = REGION + "dead_snag"
			elif r2 < 0.12:
				kind = REGION + "young_oak"
			elif rng.randf() < 0.35 + pine_bias * 0.5:
				kind = REGION + ["spruce_a", "pine_scots"][rng.randi() % 2]
			else:
				# (7 tree kinds per chunk like the old set: every kind is a draw call per LOD.)
				kind = REGION + ["oak_a", "oak_b", "beech_a"][rng.randi() % 3]
		elif roll < density + 0.12 and WorldGen.road_distance(x, z) > 4.0 and WorldGen.street_distance(x, z) > 3.0:
			# Photo-scanned undergrowth under trees, wildflowers in the open.
			if density > 0.35:
				kind = ["scan/fern_02", "scan/fern_02", "scan/shrub_03", "scan/nettle_plant", REGION + "bush_round", "scan/tree_stump_01",
					"scan/tree_stump_02", "scan/root_cluster_01", "scan/fern_02"][rng.randi() % 9]
			else:
				kind = ["scan/dandelion_01", REGION + "bush_berry", REGION + "bush_hazel", REGION + "flowers_warm", "scan/shrub_03", "scan/fern_02"][rng.randi() % 6]
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
	var impostors := SurfaceTool.new()
	var impostor_n := 0
	for kind: String in buckets:
		var list: Array[Transform3D] = []
		list.assign(buckets[kind])
		if kind.begins_with(REGION) and ResourceLoader.exists("res://assets/generated/" + kind + "_lod2.glb"):
			region_tree_chain(chunk, kind, list, false)
			# Far impostor cards of every kind in this chunk share one atlas material:
			# merged into one mesh, so a distant chunk is a single draw call.
			var card := Assets.nature_mesh(kind + "_lod2")
			if card:
				if impostor_n == 0:
					impostors.begin(Mesh.PRIMITIVE_TRIANGLES)
					impostors.set_material(card.surface_get_material(0))
				for t: Transform3D in list:
					for surf in card.get_surface_count():
						impostors.append_from(card, surf, t)
				impostor_n += list.size()
		elif kind.contains("|"):
			# "near|far": realistic mesh up close, stylised stand-in beyond TREE_LOD metres.
			var near_far := kind.split("|")
			var near_mm := _multimesh(chunk, Assets.nature_mesh(near_far[0]), list)
			var far_mm := _multimesh(chunk, Assets.nature_mesh(near_far[1]), list)
			if near_mm:
				near_mm.visibility_range_end = TREE_LOD
				near_mm.visibility_range_end_margin = 15.0
				near_mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if far_mm:
				far_mm.visibility_range_begin = TREE_LOD
				far_mm.visibility_range_begin_margin = 15.0
				far_mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			_multimesh(chunk, Assets.nature_mesh(kind), list)
	if impostor_n > 0:
		var mi := MeshInstance3D.new()
		mi.name = "TreeImpostors"
		mi.mesh = impostors.commit()
		mi.visibility_range_begin = REGION_LODS[1]
		mi.visibility_range_begin_margin = 5.0
		mi.visibility_range_end = 450.0
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		chunk.add_child(mi)


## A region tree kind as three MultiMeshes: LOD0, LOD1 and the impostor card past
## REGION_LODS[1] (out to _multimesh's 450 m). Hard switches with a margin: fading
## would put every tree in the transparent pass while it crosses over.
static func region_tree_chain(parent: Node3D, kind: String, list: Array[Transform3D], with_impostor := true) -> void:
	var keys := [kind, kind + "_lod1", kind + "_lod2"]
	for i in (3 if with_impostor else 2):
		var mmi := _multimesh(parent, Assets.nature_mesh(keys[i]), list)
		if mmi == null:
			continue
		if i > 0:
			mmi.visibility_range_begin = REGION_LODS[i - 1]
			mmi.visibility_range_begin_margin = 5.0
		if i < 2:
			mmi.visibility_range_end = REGION_LODS[i]
			mmi.visibility_range_end_margin = 5.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	if mesh == null or transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Small undergrowth vanishes early; trees and big rocks stay to the horizon.
	var box := mesh.get_aabb()
	var extent := maxf(maxf(box.size.x, box.size.z), box.size.y)
	mmi.visibility_range_end = 60.0 if extent < 1.2 else (140.0 if extent < 3.5 else 450.0)
	mmi.visibility_range_end_margin = 8.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if extent < 3.5:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
