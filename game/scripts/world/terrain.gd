class_name Terrain
extends RefCounted
## Heightfield for the Aramori region: a flat village clearing ringed by a fence,
## rolling hills, a lake to the west, a road south, and a mountain rim at the edge.
## Faceted flat-shaded triangles give the stylized low-poly look.

const SIZE := 320.0
const CELL := 2.0
const VILLAGE_RADIUS := 38.0
const WATER_LEVEL := 0.35
const LAKE_CENTER := Vector2(-72.0, -40.0)
const RIFT_SITE := Vector2(12.0, 118.0)

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(seed_value := 7) -> void:
	_hills.seed = seed_value
	_hills.frequency = 0.009
	_hills.fractal_octaves = 4
	_detail.seed = seed_value + 1
	_detail.frequency = 0.09
	_forest.seed = seed_value + 2
	_forest.frequency = 0.02


## The road leaves the south gate (+Z) and snakes toward the Rift scar.
func road_x(z: float) -> float:
	return sin((z - VILLAGE_RADIUS) * 0.03) * 12.0 * smoothstep(VILLAGE_RADIUS, 70.0, z)


func distance_to_road(x: float, z: float) -> float:
	if z < VILLAGE_RADIUS - 6.0:
		return INF
	return absf(x - road_x(z))


func height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var wild := smoothstep(VILLAGE_RADIUS + 4.0, 100.0, d)
	var hills := (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * 16.0
	var h := 1.0 + hills * wild + _detail.get_noise_2d(x, z) * 0.25
	# Flatten the road.
	var road := 1.0 - smoothstep(3.0, 8.0, distance_to_road(x, z))
	h = lerpf(h, 1.0 + hills * wild * 0.25, road)
	# Lake basin.
	var lake := 1.0 - smoothstep(12.0, 30.0, Vector2(x, z).distance_to(LAKE_CENTER))
	h -= lake * 4.5
	# Rift crater.
	var rift := 1.0 - smoothstep(4.0, 12.0, Vector2(x, z).distance_to(RIFT_SITE))
	h = lerpf(h, 1.3, rift)
	# Mountain rim closes the region.
	var edge := maxf(absf(x), absf(z))
	h += pow(smoothstep(115.0, SIZE / 2.0, edge), 1.4) * 42.0
	return h


func color_at(x: float, z: float, h: float, slope: float) -> Color:
	var d := Vector2(x, z).length()
	var tint := _detail.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5
	var c := Color("7da453").lerp(Color("96b85c"), tint)
	if d < VILLAGE_RADIUS:
		c = c.lerp(Color("a3b86a"), 0.35)
	if h < WATER_LEVEL + 0.6 and Vector2(x, z).distance_to(LAKE_CENTER) < 34.0:
		c = Color("c9b98a")
	if slope > 0.55 or h > 18.0:
		c = Color("8b8577").lerp(Color("a39c8c"), tint)
	if h > 34.0:
		c = Color("eef0f2")
	if distance_to_road(x, z) < 3.2 or d < 9.0:
		c = Color("b8935f").lerp(Color("a6804f"), tint)
	if Vector2(x, z).distance_to(RIFT_SITE) < 10.0:
		c = c.lerp(Color("4a2f5c"), 1.0 - smoothstep(6.0, 10.0, Vector2(x, z).distance_to(RIFT_SITE)))
	return c


## True where a tree may stand: outside the fence, off the road, dry, not too steep.
func tree_density(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	if d < VILLAGE_RADIUS + 7.0 or distance_to_road(x, z) < 7.0:
		return 0.0
	if Vector2(x, z).distance_to(RIFT_SITE) < 16.0:
		return 0.0
	var h := height(x, z)
	if h < WATER_LEVEL + 0.8 or h > 26.0:
		return 0.0
	return clampf(_forest.get_noise_2d(x, z) * 1.4 + 0.45, 0.0, 1.0)


func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var cells := int(SIZE / CELL)
	var half := SIZE / 2.0
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for j in cells + 1:
		for i in cells + 1:
			heights[j * (cells + 1) + i] = height(-half + i * CELL, -half + j * CELL)
	for j in cells:
		for i in cells:
			var x0 := -half + i * CELL
			var z0 := -half + j * CELL
			var p00 := Vector3(x0, heights[j * (cells + 1) + i], z0)
			var p10 := Vector3(x0 + CELL, heights[j * (cells + 1) + i + 1], z0)
			var p01 := Vector3(x0, heights[(j + 1) * (cells + 1) + i], z0 + CELL)
			var p11 := Vector3(x0 + CELL, heights[(j + 1) * (cells + 1) + i + 1], z0 + CELL)
			_triangle(st, p00, p10, p01)
			_triangle(st, p10, p11, p01)
	st.generate_normals()
	return st.commit()


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center := (a + b + c) / 3.0
	var normal := (c - a).cross(b - a).normalized()
	var slope := 1.0 - absf(normal.y)
	st.set_color(color_at(center.x, center.z, center.y, slope))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
