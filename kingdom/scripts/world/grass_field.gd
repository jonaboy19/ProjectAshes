class_name GrassField
extends RefCounted
## Builds the grass MultiMesh for one terrain chunk. Only chunks next to the
## player get grass (see TerrainStreamer.grass_radius), and each instance fades
## out by distance, so thousands of blades stay affordable.
##
## Every clump MultiMesh draws with shaders/grass.gdshader (material_override):
## the same painted meadow atlas and wind data as the imported
## meadow_wind_material.tres, plus clump colour/height noise, view-space
## widening, fake subsurface backlight, travelling gusts and trampling by the
## player, villagers and critters (fed by grass_interactors.gd).

const CLUMPS_PER_CHUNK := 3300
const FADE_END := 70.0
const FLOWER_FADE_END := 48.0     # flower cards are 88 tris: cull them sooner than grass
const SHADER := preload("res://shaders/grass.gdshader")
const Interactors := preload("res://scripts/world/grass_interactors.gd")
## Imported card material: its atlas and wind settings seed our grass material.
const MEADOW_MATERIAL := "res://assets/generated/nature/meadow_wind_material.tres"
## Weather.wind_strength (1 calm, ~2.4 storm) scales the sway via weather_wind.
const Weather := preload("res://scripts/world/weather.gd")

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


static func build(origin: Vector2, size: float, seed_value: int) -> Node3D:
	return build_from_plan(plan(origin, size, seed_value))


## Where every clump goes: pure maths on WorldGen's read-only data, so it is safe
## to run on a worker thread (TerrainStreamer does). Kind -> Array of Transform3D.
static func plan(origin: Vector2, size: float, seed_value: int) -> Dictionary:
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
		(kinds[kind] as Array).append(Transform3D(basis, Vector3(x, Region1Terrain.mesh_ground(x, z) - 0.03, z)))
	_flower_patches(kinds["flowers_a"], origin, size, seed_value)
	return kinds


## Wildflower drifts (daisies, buttercups, cornflowers, campion: the mixed flowers_a card):
## dense patches along road and path edges and scattered through the meadows, so the ground
## never reads bare between grass tufts. Deterministic per chunk, worker-thread safe. The
## list is shuffled at the end because Quality thins MultiMeshes by keeping a prefix
## (a LOW/MEDIUM tier then keeps fewer flowers in every patch, not whole patches).
const FLOWER_PATCHES := 56
static func _flower_patches(out: Array, origin: Vector2, size: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x0f10e5
	var start := out.size()
	for i in FLOWER_PATCHES:
		var cx := origin.x + rng.randf() * size
		var cz := origin.y + rng.randf() * size
		var info := WorldGen.road_info(cx, cz)
		var edge: float = float(info["dist"]) - float(info["width"]) * 0.5
		var roadside := edge > 0.4 and edge < 7.0
		if not _flowerable(cx, cz):
			continue
		# Road edges nearly always get a drift, open meadow about a third of the time.
		if rng.randf() > (0.95 if roadside else 0.6):
			continue
		var count := rng.randi_range(16, 28) if roadside else rng.randi_range(9, 18)
		var radius := 2.8 if roadside else 3.6
		for k in count:
			var a := rng.randf() * TAU
			var r := radius * sqrt(rng.randf())
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			if not _flowerable(x, z):
				continue
			var s := rng.randf_range(1.4, 2.2)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s))
			out.append(Transform3D(basis, Vector3(x, Region1Terrain.mesh_ground(x, z) - 0.03, z)))
	# Fisher-Yates over the patch part only (the meadow flowers before it are already random).
	for i in range(out.size() - 1, start, -1):
		var j := rng.randi_range(start, i)
		var tmp: Transform3D = out[i]
		out[i] = out[j]
		out[j] = tmp


## Like _grassy, but flowers may sit right at the verge of a road (grass keeps 3.5 m clear).
static func _flowerable(x: float, z: float) -> bool:
	if WorldGen.is_water(x, z):
		return false
	var info := WorldGen.road_info(x, z)
	if float(info["dist"]) < float(info["width"]) * 0.5 + 0.5:
		return false
	var near := WorldGen.nearest_settlement(Vector2(x, z))
	if not near.is_empty():
		var dc := Vector2(x, z).distance_to(near["pos"])
		if dc < near["plan"]["plaza_r"] + 3.0 or WorldGen.street_distance(x, z) < 1.5:
			return false
		if near["kind"] != "village" and dc < near["radius"] and not _town_yard(near, x, z, dc):
			return false
	var h := WorldGen.height(x, z)
	var slope := absf(WorldGen.height(x + 1.0, z) - h) + absf(WorldGen.height(x, z + 1.0) - h)
	return slope < 0.9 and h < 90.0


## The nodes for a plan (main thread only). Null if the plan is empty.
static func build_from_plan(kinds: Dictionary) -> Node3D:
	Interactors.ensure_running()
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
		var mat := _get_material()
		if mat != null:
			mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = FLOWER_FADE_END if kind == "flowers_a" else FADE_END
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
		if dc < near["plan"]["plaza_r"] + 3.0 or WorldGen.street_distance(x, z) < 1.5 \
				or (dc < near["radius"] * 1.1 and CityPlanner.path_distance(near["plan"], Vector2(x, z)) < 0.5):
			return false
		if near["kind"] != "village" and dc < near["radius"] and not _town_yard(near, x, z, dc):
			return false
	var h := WorldGen.height(x, z)
	var slope := absf(WorldGen.height(x + 1.0, z) - h) + absf(WorldGen.height(x, z + 1.0) - h)
	return slope < 0.9 and h < 90.0


## Green yards between a town's lots: clear of streets, paths, the plaza margin and
## the market ring, and only where the terrain is painted grass (not cobble/dirt).
static func _town_yard(near: Dictionary, x: float, z: float, dc: float) -> bool:
	if dc < near["plan"]["plaza_r"] + 10.0 or WorldGen.street_distance(x, z) < 3.5:
		return false
	if CityPlanner.path_distance(near["plan"], Vector2(x, z)) < 1.5:
		return false
	for lot: Dictionary in near["plan"]["lots"]:
		if Vector2(x, z).distance_to(lot["pos"]) < 5.0:
			return false
	var w := WorldGen.color_at(x, z, WorldGen.height(x, z), 0.0)
	return w.r < 0.3 and w.b < 0.1 and w.g < 0.2 and w.a < 0.3


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


## One shared grass material for every chunk and clump kind. Returns null (and
## the clumps keep their imported material) if the meadow material is missing.
static func _get_material() -> ShaderMaterial:
	if _material == null:
		Interactors.ensure_globals()
		var src := load(MEADOW_MATERIAL) as ShaderMaterial
		if src == null or src.get_shader_parameter("albedo_texture") == null:
			return null
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		# Copy the art-tuned values (atlas, tint, cutout, wind) so edits to the
		# imported material keep flowing through.
		for u: Dictionary in SHADER.get_shader_uniform_list():
			var v: Variant = src.get_shader_parameter(u["name"])
			if v != null:
				_material.set_shader_parameter(u["name"], v)
		# Warmer, more saturated meadow (art reference: lush sunny yellow-green).
		_material.set_shader_parameter("tint", Color(1.06, 1.06, 0.86))
		_material.set_shader_parameter("lush_tint", Color(1.0, 1.06, 0.78))
		_material.set_shader_parameter("dry_tint", Color(1.12, 1.06, 0.74))
		Interactors.on_slow_tick(_sync_weather)
		_sync_weather()
	return _material


static var _weather_wind := -1.0


## 2 Hz (from the interactor feeder): push the weather's wind into the grass.
static func _sync_weather() -> void:
	if _material == null:
		return
	var w: float = Weather.wind_strength
	if absf(w - _weather_wind) > 0.01:
		_weather_wind = w
		_material.set_shader_parameter("weather_wind", w)
