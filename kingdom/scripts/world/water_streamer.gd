class_name WaterStreamer
extends Node3D
## Streams water surface meshes (lake + rivers) around a focus point, following
## the TerrainStreamer pattern: same 64 m chunks, at most one chunk built per
## frame, far chunks freed. Chunks without water cost one cheap scan and are
## remembered as empty. The surface follows WorldGen.water_level_at() and is
## drawn a little past the shoreline; the terrain hides the overlap and the
## shader softens the contact line with depth-based foam.

const CHUNK := TerrainStreamer.CHUNK
const CELL := 4.0                    # water needs far fewer vertices than ground

@export var view_radius := 4
var focus := Vector3.ZERO

var _chunks: Dictionary = {}         # Vector2i -> MeshInstance3D (or null when dry)
var _material: ShaderMaterial
var _sun: Object


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/water/clear_water.gdshader")
	_material.set_shader_parameter("normal_a", _noise(0.012, 4, true, 3.0, 11))
	_material.set_shader_parameter("normal_b", _noise(0.03, 3, true, 2.0, 29))
	_material.set_shader_parameter("foam_noise", _noise(0.02, 3, false, 0.0, 47))
	_material.set_shader_parameter("caustics_tex", _caustics())
	# The Compatibility renderer has no screen texture copy worth paying for.
	apply_quality()
	if get_tree().root.get_node_or_null("Quality"):
		get_tree().root.get_node("Quality").changed.connect(apply_quality)


## Weather and light on the water: rain rings (0..1) and the ember sunset glow (0..1).
func set_weather(rain: float, sunset: float) -> void:
	if _material:
		_feed_sun()
		_material.set_shader_parameter("rain_ripples", clampf(rain, 0.0, 1.0))
		_material.set_shader_parameter("sunset", clampf(sunset, 0.0, 1.0))


static func _noise(freq: float, octaves: int, normal: bool, bump: float, seed_value: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = bump
	t.generate_mipmaps = true
	return t


func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func loaded_count() -> int:
	var n := 0
	for key: Vector2i in _chunks:
		if _chunks[key] != null:
			n += 1
	return n


func build_all_now() -> void:
	while _step():
		pass


func _process(_delta: float) -> void:
	_step()


func _step() -> bool:
	var center := chunk_of(focus)
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > view_radius + 1:
			if _chunks[key] != null:
				(_chunks[key] as Node).queue_free()
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
		return false
	_chunks[best] = _build_chunk(best)
	return true


func _build_chunk(key: Vector2i) -> MeshInstance3D:
	var mesh := build_mesh(Vector2(key.x * CHUNK, key.y * CHUNK))
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Water_%d_%d" % [key.x, key.y]
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Water surface for one chunk, or null if the chunk is dry. Vertex data:
## COLOR.rg = current direction (0.5 = still), COLOR.b = speed / 2 m/s,
## UV.x = static water depth, negative on dry ground (wave damping in the
## shallows, and the shader's fallback when no depth texture is available).
static func build_mesh(origin: Vector2) -> ArrayMesh:
	var n := int(CHUNK / CELL)
	var levels := PackedFloat32Array()
	levels.resize((n + 1) * (n + 1))
	var any := false
	for j in n + 1:
		for i in n + 1:
			var lv := WorldGen.water_level_at(origin.x + i * CELL, origin.y + j * CELL)
			levels[j * (n + 1) + i] = lv
			any = any or not is_nan(lv)
	if not any:
		return null
	# Which vertices are near or below the waterline (skip quads buried in the shore).
	var depth := PackedFloat32Array()
	depth.resize(levels.size())
	for j in n + 1:
		for i in n + 1:
			var k := j * (n + 1) + i
			depth[k] = -INF if is_nan(levels[k]) else levels[k] - WorldGen.height(origin.x + i * CELL, origin.y + j * CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index := {}
	var quads := 0
	for j in n:
		for i in n:
			var k := [j * (n + 1) + i, j * (n + 1) + i + 1, (j + 1) * (n + 1) + i, (j + 1) * (n + 1) + i + 1]
			var ok := true
			var wet := false
			for c: int in k:
				if is_nan(levels[c]):
					ok = false
				elif depth[c] > -1.0:
					wet = true
			if not ok or not wet:
				continue
			quads += 1
			var ids: Array[int] = []
			for c: int in k:
				if not index.has(c):
					index[c] = index.size()
					var x := origin.x + (c % (n + 1)) * CELL
					var z := origin.y + (c / (n + 1)) * CELL
					var fl := WorldGen.water_flow(x, z)
					var fd := fl.normalized()
					st.set_color(Color(fd.x * 0.5 + 0.5, fd.y * 0.5 + 0.5, clampf(fl.length() * 0.5, 0.0, 1.0)))
					st.set_uv(Vector2(maxf(depth[c], -2.0), 0.0))
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(x, levels[c], z))
				ids.append(index[c])
			st.add_index(ids[0])
			st.add_index(ids[1])
			st.add_index(ids[2])
			st.add_index(ids[1])
			st.add_index(ids[3])
			st.add_index(ids[2])
	if quads == 0:
		return null
	return st.commit()


## Seamless cellular-noise tile the shader turns into caustic light nets.
static func _caustics() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.03
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.cellular_jitter = 1.0
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.invert = true
	t.generate_mipmaps = true
	return t


## Map the Quality autoload tier onto the water shader tiers.
## LOW/Compatibility: no screen texture (fake transparency from depth + alpha).
## MEDIUM: refraction, no caustics. HIGH/ULTRA: everything.
func apply_quality() -> void:
	if _material == null:
		return
	var tier: int = 2
	var q := get_tree().root.get_node_or_null("Quality")
	if q:
		tier = int(q.get("tier"))
	var level := 2
	if tier <= 0 or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		level = 0
	elif tier == 1:
		level = 1
	_material.set_shader_parameter("quality", level)
	_material.set_shader_parameter("use_refraction", level >= 1)


## Sun direction and strength for glints and caustics (sun is found once).
func _feed_sun() -> void:
	if not is_instance_valid(_sun):
		_sun = null  # (untyped: assigning over a freed typed ref errors)
		for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			_sun = l
			break
	if _sun == null:
		return
	_material.set_shader_parameter("sun_dir", (_sun as DirectionalLight3D).global_transform.basis.z.normalized())
	_material.set_shader_parameter("sun_energy", clampf((_sun as DirectionalLight3D).light_energy / 1.7, 0.0, 1.5) * (1.0 if (_sun as DirectionalLight3D).visible else 0.0))
