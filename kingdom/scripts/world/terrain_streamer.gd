class_name TerrainStreamer
extends Node3D
## Streams terrain chunks (ground mesh, collision, forest MultiMeshes) around a
## focus point. Builds at most one chunk per frame so movement never hitches;
## chunks outside the radius are freed and rebuilt identically when revisited.

const CHUNK := 64.0
const CELL := 2.0
## Perf round 2: chunks whose centre is past GROUND_LOD_DIST swap to a quarter-triangle
## ground mesh (LOD_STEP x CELL grid, 512 tris instead of 2048) with a skirt so the
## step against the full-res neighbour shows no crack.
const GROUND_LOD_DIST := 110.0
const LOD_STEP := 2
const SKIRT_DROP := 4.0
## Distance where Blender trees hand over to the cheap stylised stand-ins.
const TREE_LOD := 200.0
## Painterly region trees (generated/region/nature): LOD0 -> LOD1 -> 4-tri impostor
## card (_lod2) at these distances (Quality scales them: LOW x0.55 = 22 / 66 m; the crossed cards read as an X from a steep aerial camera, so not closer).
const REGION_LODS := [40.0, 120.0]
const REGION := "region/nature/"

@export var view_radius := 4:        # chunks; 9x9 grid visible
	set(v):
		if v != view_radius:
			view_radius = v
			_idle_center = Vector2i(1 << 30, 0)   # a new ring size (settings screen) needs a scan even when standing still
@export var collision_radius := 1    # chunks that also get physics
@export var grass_radius := 1        # chunks that also get grass
var focus := Vector3.ZERO

var _chunks: Dictionary = {}         # Vector2i -> Node3D
var _ground_material: ShaderMaterial

## Threaded streaming: the maths for a chunk (ground grid, collision faces, forest
## and grass placement, merged impostor cards) runs on WorkerThreadPool; the main
## thread only turns a finished plan into nodes, one chunk per frame. Before this,
## every new chunk cost 120-150 ms on the main thread (visible hitches while moving).
const MAX_IN_FLIGHT := 2
var _tasks: Dictionary = {}          # Vector2i -> WorkerThreadPool task id
var _plans: Dictionary = {}          # Vector2i -> finished plan (guarded by _mutex)
var _mutex := Mutex.new()
## Impostor card geometry per region tree kind, read on the main thread once so the
## worker can merge cards without touching resources. kind -> [arrays, material]
var _cards: Dictionary = {}
const REGION_TREES := ["dead_snag", "young_oak", "spruce_a", "pine_scots", "oak_a", "oak_b", "beech_a",
	"bush_round", "bush_berry", "bush_hazel", "flowers_warm"]

## Inside the core of a region-site clearing (farm, mine, camp...): its buildings own that ground.
static func _in_clearing(x: float, z: float) -> bool:
	for c in WorldGen.clearings:
		if Vector2(x, z).distance_to(c["pos"]) < float(c["radius"]) * 0.25:
			return true
	return false


## Painted small plants and rocks scattered by _plan_forest (kind keys for Assets.nature_mesh).
const UNDERGROWTH := [REGION + "fern_a", REGION + "fern_b", REGION + "fern_a", REGION + "bush_round", REGION + "bush_hazel",
	REGION + "stump_mossy", REGION + "stump_broken", REGION + "log_mossy", REGION + "fern_b", "Mushroom_Common", REGION + "bush_hazel"]
const MEADOW_PLANTS := [REGION + "flowers_warm", REGION + "flowers_cool", REGION + "bush_berry", REGION + "bush_hazel",
	REGION + "bush_round", REGION + "grass_tall", REGION + "fern_b"]
const ROCKS := ["rock_medium", "rock_cluster", "rock_slab", "rock_medium", "boulder_large"]
## Forest-floor scatter: [kind, min scale, max scale]; repeats weight the mix.
const FLOOR_ATTEMPTS := 2600
const FLOOR_KINDS := [
	[REGION + "fern_a", 0.7, 1.2], [REGION + "fern_b", 0.8, 1.4], [REGION + "fern_a", 0.6, 1.0], [REGION + "fern_b", 0.7, 1.2],
	[REGION + "fern_a", 0.8, 1.3], [REGION + "fern_b", 0.9, 1.5], [REGION + "grass_tall", 0.9, 1.5],
	["Mushroom_Common", 0.9, 1.6], ["Mushroom_Laetiporus", 0.4, 0.7],
	["floor/leaf_litter", 0.8, 1.6], ["floor/leaf_litter", 0.8, 1.6], ["floor/leaf_litter_green", 0.8, 1.5], ["floor/leaf_litter", 1.0, 1.8],
	["floor/moss_patch", 0.8, 1.6], ["floor/moss_patch", 0.7, 1.3],
	[REGION + "bush_round", 0.45, 0.8], [REGION + "bush_hazel", 0.5, 0.9], [REGION + "bush_hazel", 0.4, 0.7],
	[REGION + "grass_tall", 0.9, 1.4], [REGION + "flowers_cool", 0.8, 1.2],
]
## Kinds that only matter close to the camera: culled early.
const FLOOR_NEAR := ["floor/", "Mushroom", REGION + "fern", REGION + "grass_tall", REGION + "flowers"]

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
	# Streets: the user's hand-painted honey cobbles (art reference) instead of the scanned set.
	_ground_material.set_shader_parameter("cobble_albedo", load("res://assets/art/textures/cobblestone.png"))
	_ground_material.set_shader_parameter("cobble_normal", load("res://assets/art/textures/cobblestone_normal.png"))
	_ground_material.set_shader_parameter("cobble_arm", load("res://assets/art/textures/cobblestone_arm.png"))   # AO, rough, metal
	_ground_material.set_shader_parameter("macro_noise", _noise_texture(0.01, 3, false))
	for tree: String in REGION_TREES:
		var kind: String = REGION + tree
		if not ResourceLoader.exists("res://assets/generated/" + kind + "_lod2.glb"):
			continue
		var card := Assets.nature_mesh(kind + "_lod2")
		if card and card.get_surface_count() > 0:
			var surfs := []
			for s in card.get_surface_count():
				surfs.append(card.surface_get_arrays(s))
			_cards[kind] = [surfs, card.surface_get_material(0)]


func _exit_tree() -> void:
	for key: Vector2i in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


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


## Build every chunk in range right now (used on spawn / teleport; blocks on purpose).
func build_all_now() -> void:
	while _step(true):
		pass


## Once every chunk around the player is built (and its collision and grass are in),
## nothing changes until the player crosses into another chunk, so skip the scan.
## (The per-frame scan cost ~5 ms/frame in the capital profile, 2026-09-28.)
var _idle_center := Vector2i(1 << 30, 0)


func _process(_delta: float) -> void:
	var center := chunk_of(focus)
	if center == _idle_center:
		return
	if not _step(false) and _tasks.is_empty():
		_idle_center = center


## Frees far chunks, queues the nearest missing ones on worker threads and turns at
## most one finished plan into nodes. Returns true if work remains (sync mode only).
func _step(sync: bool) -> bool:
	var center := chunk_of(focus)
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > view_radius + 1:
			_chunks[key].queue_free()
			_chunks.erase(key)
	# Collect finished worker plans.
	for key: Vector2i in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	var missing: Array = []
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var key := center + Vector2i(dx, dz)
			if not _chunks.has(key):
				missing.append([dx * dx + dz * dz, key])
	missing.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if missing.is_empty():
		# Still true while collision/grass are being added one per frame.
		return _update_collision(center)
	if sync:
		var key: Vector2i = missing[0][1]
		if _tasks.has(key):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
		var p: Dictionary = _take_plan(key)
		_chunks[key] = _build_chunk(key, p if not p.is_empty() else _plan_chunk(key))
		_update_collision(center)
		return true
	# Async: finish the nearest ready chunk (one per frame), keep the workers fed.
	var built := false
	for m: Array in missing:
		var key: Vector2i = m[1]
		if not built:
			var p: Dictionary = _take_plan(key)
			if not p.is_empty():
				_chunks[key] = _build_chunk(key, p)
				built = true
				continue
		if _tasks.size() < MAX_IN_FLIGHT and not _tasks.has(key) and not _has_plan(key):
			_tasks[key] = WorkerThreadPool.add_task(_plan_worker.bind(key), false, "terrain chunk")
	# Drop plans that fell out of range before they were used.
	_mutex.lock()
	for key: Vector2i in _plans.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > view_radius + 1:
			_plans.erase(key)
	_mutex.unlock()
	_update_collision(center)
	return true


func _plan_worker(key: Vector2i) -> void:
	var p := _plan_chunk(key)
	_mutex.lock()
	_plans[key] = p
	_mutex.unlock()


func _take_plan(key: Vector2i) -> Dictionary:
	_mutex.lock()
	var p: Dictionary = _plans.get(key, {})
	_plans.erase(key)
	_mutex.unlock()
	return p


func _has_plan(key: Vector2i) -> bool:
	_mutex.lock()
	var h := _plans.has(key)
	_mutex.unlock()
	return h


## Physics and grass for chunks next to the player. Creating either costs a few ms,
## so at most one body and one grass field are added per frame (the rest follow
## on the next frames instead of all landing in the frame a boundary is crossed).
func _update_collision(center: Vector2i) -> bool:
	var added_body := false
	var added_grass := false
	for key: Vector2i in _chunks:
		var chunk: Node3D = _chunks[key]
		var ring := maxi(absi(key.x - center.x), absi(key.y - center.y))
		var body: StaticBody3D = chunk.get_node_or_null("Body")
		if ring <= collision_radius and body == null:
			# The chunk under the player first (ring 0), never deferred.
			if added_body and ring > 0:
				continue
			body = StaticBody3D.new()
			body.name = "Body"
			var shape := CollisionShape3D.new()
			var faces: PackedVector3Array = chunk.get_meta("faces", PackedVector3Array())
			if faces.is_empty():
				shape.shape = (chunk.get_node("Ground") as MeshInstance3D).mesh.create_trimesh_shape()
			else:
				var cs := ConcavePolygonShape3D.new()
				cs.set_faces(faces)
				shape.shape = cs
			body.add_child(shape)
			chunk.add_child(body)
			added_body = true
		elif ring > collision_radius and body != null:
			body.queue_free()
		var grass: Node = chunk.get_node_or_null("Grass")
		if ring <= grass_radius and grass == null and not chunk.has_meta("no_grass"):
			if added_grass:
				continue
			var plan: Dictionary = chunk.get_meta("grass_plan", {})
			var g := GrassField.build_from_plan(plan) if not plan.is_empty() \
				else GrassField.build(Vector2(key.x * CHUNK, key.y * CHUNK), CHUNK, hash(key) ^ 0x6a55)
			if g:
				g.name = "Grass"
				chunk.add_child(g)
			else:
				chunk.set_meta("no_grass", true)
			added_grass = true
		elif ring > grass_radius and grass != null:
			grass.queue_free()
	return added_body or added_grass


## Everything about a chunk that is pure maths (thread-safe: reads WorldGen's
## static data and the pre-read impostor cards only).
func _plan_chunk(key: Vector2i) -> Dictionary:
	var origin := Vector2(key.x * CHUNK, key.y * CHUNK)
	# Smooth, indexed grid. Normals come from the height function itself, so
	# neighbouring chunks match exactly at their seams.
	var n := int(CHUNK / CELL)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize((n + 1) * (n + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	var vi := 0
	for j in n + 1:
		for i in n + 1:
			var x := origin.x + i * CELL
			var z := origin.y + j * CELL
			var h := WorldGen.height(x, z)
			var normal := Vector3(WorldGen.height(x - 1.0, z) - WorldGen.height(x + 1.0, z), 2.0,
				WorldGen.height(x, z - 1.0) - WorldGen.height(x, z + 1.0)).normalized()
			verts[vi] = Vector3(x, h, z)
			normals[vi] = normal
			colors[vi] = WorldGen.color_at(x, z, h, 1.0 - normal.y)
			vi += 1
	var indices := PackedInt32Array()
	indices.resize(n * n * 6)
	var faces := PackedVector3Array()
	faces.resize(n * n * 6)
	var ii := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			for idx in [a, b, c, b, d, c]:
				indices[ii] = idx
				faces[ii] = verts[idx]
				ii += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var forest := _plan_forest(key, origin)
	return {
		"ground": arrays, "ground_lod": _lod_arrays(verts, normals, colors, n), "faces": faces, "forest": forest,
		"impostors": _plan_impostors(forest),
		"grass": GrassField.plan(origin, CHUNK, hash(key) ^ 0x6a55),
	}


## Every LOD_STEP-th vertex of the (n+1)^2 grid, plus a skirt hanging SKIRT_DROP m below the
## four edges (same normals/colours as the edge vertices) to hide T-junction cracks.
static func _lod_arrays(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, n: int) -> Array:
	var m := n / LOD_STEP
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var lc := PackedColorArray()
	for j in m + 1:
		for i in m + 1:
			var src := j * LOD_STEP * (n + 1) + i * LOD_STEP
			lv.append(verts[src])
			ln.append(normals[src])
			lc.append(colors[src])
	var idx := PackedInt32Array()
	for j in m:
		for i in m:
			var a := j * (m + 1) + i
			var b := a + 1
			var c := a + m + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# Skirt: duplicate each border vertex lowered, then quads between border neighbours.
	var border: Array = []      # ordered loops as lists of vertex indices, one list per side
	var top: Array[int] = []
	var bottom: Array[int] = []
	var left: Array[int] = []
	var right: Array[int] = []
	for i in m + 1:
		top.append(i)
		bottom.append(m * (m + 1) + i)
		left.append(i * (m + 1))
		right.append(i * (m + 1) + m)
	border = [[top, false], [bottom, true], [left, true], [right, false]]
	for side: Array in border:
		var list: Array = side[0]
		var flip: bool = side[1]
		var low_ids := {}
		for vi: int in list:
			low_ids[vi] = lv.size()
			lv.append(lv[vi] - Vector3(0, SKIRT_DROP, 0))
			ln.append(ln[vi])
			lc.append(lc[vi])
		for k in list.size() - 1:
			var t0: int = list[k]
			var t1: int = list[k + 1]
			var b0: int = low_ids[t0]
			var b1: int = low_ids[t1]
			# Clockwise seen from outside (Godot front face); `flip` marks the sides whose
			# border list runs the other way round.
			if flip:
				idx.append_array([t0, t1, b0, t1, b1, b0])
			else:
				idx.append_array([t0, b0, t1, t1, b0, b1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = lv
	arr[Mesh.ARRAY_NORMAL] = ln
	arr[Mesh.ARRAY_COLOR] = lc
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _build_chunk(key: Vector2i, plan: Dictionary) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [key.x, key.y]
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plan["ground"])
	ground.mesh = mesh
	ground.material_override = _ground_material
	ground.layers |= TownDecals.GROUND_LAYER      # ground decals (ruts, puddles) project only onto the terrain
	ground.visibility_range_end = GROUND_LOD_DIST
	ground.visibility_range_end_margin = 6.0
	ground.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	chunk.add_child(ground)
	if plan.has("ground_lod"):
		var far := MeshInstance3D.new()
		far.name = "GroundFar"
		var far_mesh := ArrayMesh.new()
		far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plan["ground_lod"])
		far.mesh = far_mesh
		far.material_override = _ground_material
		far.layers |= TownDecals.GROUND_LAYER
		far.visibility_range_begin = GROUND_LOD_DIST
		far.visibility_range_begin_margin = 6.0
		far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		chunk.add_child(far)
	chunk.set_meta("faces", plan["faces"])
	var grass_plan: Dictionary = plan["grass"]
	var any_grass := false
	for k: String in grass_plan:
		if not (grass_plan[k] as Array).is_empty():
			any_grass = true
	if any_grass:
		chunk.set_meta("grass_plan", grass_plan)
	else:
		chunk.set_meta("no_grass", true)
	_add_forest(chunk, plan["forest"], plan["impostors"])
	add_child(chunk)
	return chunk


## kind -> Array[Transform3D] for the trees, undergrowth and rocks of a chunk.
func _plan_forest(key: Vector2i, origin: Vector2) -> Dictionary:
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
		# Rocks roll independently of forest_density (unlike trees/undergrowth
		# below), so without this they could still spawn right inside a
		# settlement's height() flatten-to-natural slope (radius..radius*1.8,
		# see height() in world_gen.gd) -- a rock's footprint corners sampled on
		# that slope produced the same bogus multi-metre "floating" the tree
		# canopy fix above addresses. Skip that band for rocks too.
		var on_settlement_slope := false
		var near_settlement := WorldGen.nearest_settlement(Vector2(x, z))
		if not near_settlement.is_empty():
			on_settlement_slope = Vector2(x, z).distance_to(near_settlement["pos"]) < float(near_settlement["radius"]) * 1.8
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
			# Painted undergrowth under trees, wildflowers in the open (no photo scans:
			# everything here comes from the painted region set / Quaternius kit).
			if density > 0.35:
				kind = UNDERGROWTH[rng.randi() % UNDERGROWTH.size()]
			else:
				kind = MEADOW_PLANTS[rng.randi() % MEADOW_PLANTS.size()]
		elif not on_settlement_slope and rng.randf() < 0.05:
			kind = REGION + ROCKS[rng.randi() % ROCKS.size()]
		if kind == "":
			continue
		var s := rng.randf_range(0.8, 1.25)
		if kind.begins_with(REGION + "rock") or kind.begins_with(REGION + "boulder"):
			s = rng.randf_range(0.6, 1.4)
		# A flat -0.15 sink hides the base on flat ground, but on a slope the
		# uphill edge of a wide canopy/root footprint still pokes up out of the
		# ground (found by tools/qa/grounding: forest scatter was the single
		# biggest floating/buried source, far more than buildings or props,
		# which snap to their footprint's lowest corner -- see
		# RegionDressing._footprint_ground()). Individual per-instance footprint
		# sampling isn't affordable here (up to ~90 placements/chunk on the
		# worker thread already), so scale the sink with the local slope instead
		# -- two more WorldGen.height() samples per instance, still worker-thread
		# side, no per-frame cost.
		var slope := absf(WorldGen.height(x + 0.6, z) - h) + absf(WorldGen.height(x, z + 0.6) - h)
		var sink := 0.15 + minf(slope * 0.7, 0.55)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - sink, z))
		if not buckets.has(kind):
			buckets[kind] = []
		buckets[kind].append(t)
	_plan_roadside(key, origin, buckets)
	_plan_floor(key, origin, buckets)
	preload("res://scripts/world/hidden_valley.gd").plan_extra(key, origin, buckets)   # Hidden valley hook: lusher vale (worker-safe)
	return buckets


## Roadside life for chunks the roads pass through (worker-thread maths, same MultiMesh chains and
## LODs as the forest): small woods a stone's throw off the road, a tree, bush, rock or flower drift
## now and then along the verge, so a long road is never a bare ribbon. Twice as generous in the new
## land (beyond the +-2 km valley) where the roads used to run through open meadow.
const ROADSIDE_REACH := 75.0
static func _woodland_kind(rng: RandomNumberGenerator, h: float) -> String:
	if rng.randf() < 0.08:
		return REGION + "young_oak"
	if rng.randf() < 0.2 + smoothstep(30.0, 70.0, h) * 0.6:
		return REGION + ["spruce_a", "pine_scots"][rng.randi() % 2]
	return REGION + ["oak_a", "oak_b", "beech_a"][rng.randi() % 3]


static func _roadside_ok(x: float, z: float, road_min: float, road_max: float) -> bool:
	var d := WorldGen.road_distance(x, z)
	if d < road_min or d > road_max or WorldGen.near_water(x, z, 2.5) or WorldGen.street_distance(x, z) < 6.0:
		return false
	if WorldGen.height(x, z) > 100.0:
		return false
	var near := WorldGen.nearest_settlement(Vector2(x, z))
	if not near.is_empty() and Vector2(x, z).distance_to(near["pos"]) < float(near["radius"]) * 1.8:
		return false
	for c in WorldGen.clearings:
		if Vector2(x, z).distance_to(c["pos"]) < float(c["radius"]) + 4.0:
			return false
	return true


func _roadside_put(buckets: Dictionary, kind: String, x: float, z: float, s: float, rng: RandomNumberGenerator) -> void:
	var h := WorldGen.height(x, z)
	var slope := absf(WorldGen.height(x + 0.6, z) - h) + absf(WorldGen.height(x, z + 0.6) - h)
	var sink := 0.15 + minf(slope * 0.7, 0.55)
	if not buckets.has(kind):
		buckets[kind] = []
	(buckets[kind] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - sink, z)))


func _plan_roadside(key: Vector2i, origin: Vector2, buckets: Dictionary) -> void:
	var centre := origin + Vector2(CHUNK, CHUNK) * 0.5
	if WorldGen.road_distance(centre.x, centre.y) > CHUNK * 0.75 + ROADSIDE_REACH:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x70ad51de
	var k := 1.0 if maxf(absf(centre.x), absf(centre.y)) > 2000.0 else 0.5
	# Small woods: a knot of trees with bushes, a rock or a stump under them.
	for w in 2:
		if rng.randf() > 0.5 * k:
			continue
		for attempt in 8:
			var a := origin + Vector2(rng.randf(), rng.randf()) * CHUNK
			if not _roadside_ok(a.x, a.y, 16.0, 60.0) or _slope_at(a.x, a.y) > 0.4:
				continue
			var n := rng.randi_range(6, 12)
			for i in n:
				var q := a + Vector2.from_angle(rng.randf() * TAU) * (3.0 + 11.0 * sqrt(rng.randf()))
				if not _roadside_ok(q.x, q.y, 8.0, 90.0):
					continue
				_roadside_put(buckets, _woodland_kind(rng, WorldGen.height(q.x, q.y)), q.x, q.y, rng.randf_range(0.85, 1.3), rng)
			for i in rng.randi_range(4, 8):
				var q2 := a + Vector2.from_angle(rng.randf() * TAU) * (2.0 + 14.0 * sqrt(rng.randf()))
				if _roadside_ok(q2.x, q2.y, 6.0, 90.0):
					var under := ["bush_hazel", "bush_round", "fern_b", "fern_a", "bush_berry", "flowers_cool", "stump_mossy", "log_mossy", "rock_medium"]
					_roadside_put(buckets, REGION + under[rng.randi() % under.size()], q2.x, q2.y, rng.randf_range(0.7, 1.2), rng)
			break
	# The verge: single trees, bushes, rocks and flower drifts a few metres off the road.
	for i in int(16.0 * k):
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var half := float(WorldGen.road_info(x, z)["width"]) * 0.5
		if not _roadside_ok(x, z, half + 2.5, half + 22.0):
			continue
		var roll := rng.randf()
		if roll < 0.32:
			var bushes := ["bush_hazel", "bush_round", "bush_berry"]
			_roadside_put(buckets, REGION + bushes[rng.randi() % 3], x, z, rng.randf_range(0.8, 1.3), rng)
		elif roll < 0.55:
			var rocks := ["rock_medium", "rock_cluster", "rock_slab", "boulder_large"]
			_roadside_put(buckets, REGION + rocks[rng.randi() % rocks.size()], x, z, rng.randf_range(0.6, 1.3), rng)
		elif roll < 0.8:
			for j in rng.randi_range(3, 6):
				var q := Vector2(x, z) + Vector2.from_angle(rng.randf() * TAU) * (2.5 * sqrt(rng.randf()))
				if _roadside_ok(q.x, q.y, half + 1.5, half + 25.0):
					_roadside_put(buckets, REGION + ("flowers_warm" if rng.randf() < 0.55 else "flowers_cool"), q.x, q.y, rng.randf_range(0.8, 1.3), rng)
		else:
			_roadside_put(buckets, _woodland_kind(rng, WorldGen.height(x, z)), x, z, rng.randf_range(0.85, 1.25), rng)


static func _slope_at(x: float, z: float) -> float:
	var e := 3.0
	var dx := WorldGen.height(x + e, z) - WorldGen.height(x - e, z)
	var dz := WorldGen.height(x, z + e) - WorldGen.height(x, z - e)
	return Vector2(dx, dz).length() / (2.0 * e)


## Forest-floor dressing for Duskbriar and every other wood: ferns, mushrooms, fallen leaves,
## moss and small bushes scattered densely under the canopy (thinly at forest edges), so the
## ground between the trunks never reads as bare. Worker-thread maths only. The per-kind
## lists are in random order, so Quality's scatter share (a prefix of each small MultiMesh
## under the terrain, see quality.gd _thin_scatter) thins them evenly per tier.
func _plan_floor(key: Vector2i, origin: Vector2, buckets: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0xf1002
	for i in FLOOR_ATTEMPTS:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		# Glades count as woodland at a lower weight; site clearings keep their own dressing.
		var density := maxf(WorldGen.forest_density(x, z), WorldGen.woodland(x, z) * 0.6)
		if density < 0.12 or rng.randf() > 0.25 + density * 0.75:
			continue
		if WorldGen.forest_density(x, z) < 0.05 and not WorldGen.clearings.is_empty() and _in_clearing(x, z):
			continue
		if WorldGen.near_water(x, z, 1.5) or WorldGen.road_distance(x, z) < 4.0 or WorldGen.street_distance(x, z) < 3.0:
			continue
		var h := WorldGen.height(x, z)
		if h > 115.0:
			continue
		var pick: Array = FLOOR_KINDS[rng.randi() % FLOOR_KINDS.size()]
		var kind: String = pick[0]
		var s := rng.randf_range(float(pick[1]), float(pick[2]))
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.05, z))
		if not buckets.has(kind):
			buckets[kind] = []
		buckets[kind].append(t)


## Far impostor cards of every region tree in the chunk share one atlas material:
## merged into one mesh (a distant chunk is a single draw call). Built from the card
## arrays read in _ready, so it runs on the worker. Returns [arrays, material] or [].
func _plan_impostors(forest: Dictionary) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var mat: Material = null
	for kind: String in forest:
		if not _cards.has(kind):
			continue
		mat = _cards[kind][1]
		for t: Transform3D in forest[kind]:
			for s: Array in _cards[kind][0]:
				var base := v.size()
				var sv: PackedVector3Array = s[Mesh.ARRAY_VERTEX]
				var sn: PackedVector3Array = s[Mesh.ARRAY_NORMAL] if s[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				var su: PackedVector2Array = s[Mesh.ARRAY_TEX_UV] if s[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				for k in sv.size():
					v.append(t * sv[k])
					nrm.append((t.basis * (sn[k] if k < sn.size() else Vector3.UP)).normalized())
					uv.append(su[k] if k < su.size() else Vector2.ZERO)
				var si: PackedInt32Array = s[Mesh.ARRAY_INDEX] if s[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if si.is_empty():
					for k in sv.size():
						idx.append(base + k)
				else:
					for k in si:
						idx.append(base + k)
	if v.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	return [arrays, mat]


## Nodes for a planned forest (main thread): one MultiMesh chain per kind.
func _add_forest(chunk: Node3D, buckets: Dictionary, impostor: Array) -> void:
	for kind: String in buckets:
		var list: Array[Transform3D] = []
		list.assign(buckets[kind])
		if _cards.has(kind):
			region_tree_chain(chunk, kind, list, false)
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
			var mmi := _multimesh(chunk, Assets.nature_mesh(kind), list)
			if mmi:
				for near: String in FLOOR_NEAR:
					if kind.begins_with(near):
						mmi.visibility_range_end = 55.0
						break
	if not impostor.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "TreeImpostors"
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, impostor[0])
		am.surface_set_material(0, impostor[1])
		mi.mesh = am
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
