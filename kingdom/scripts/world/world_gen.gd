class_name WorldGen
extends RefCounted
## Deterministic world layout: terrain height/colour, settlements and roads.
## Everything is a pure function of the seed so chunks can be generated in any
## order, on demand, and regenerated identically after unloading.

const WORLD_HALF := 2048.0          # 4 km x 4 km
const SETTLEMENT_COUNT := 10
const NAMES := ["Ashford", "Kingsreach", "Millbrook", "Stonehollow", "Eastmere", "Redwater",
	"Thornfield", "Greywatch", "Oakvale", "Highcliff", "Brackenmoor", "Westfen"]

## Each settlement: {id, name, pos: Vector2, radius, base_h, kind: "village"|"town"|"castle", population}
static var settlements: Array[Dictionary] = []
## Road segments as pairs of settlement ids.
static var roads: Array[Vector2i] = []

static var _hills := FastNoiseLite.new()
static var _ridges := FastNoiseLite.new()
static var _detail := FastNoiseLite.new()
static var _forest := FastNoiseLite.new()
static var _initialized := false


static func setup(seed_value: int) -> void:
	_hills.seed = seed_value
	_hills.frequency = 0.0022
	_hills.fractal_octaves = 4
	_ridges.seed = seed_value + 11
	_ridges.frequency = 0.0009
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 3
	_detail.seed = seed_value + 23
	_detail.frequency = 0.05
	_forest.seed = seed_value + 37
	_forest.frequency = 0.006
	_forest.fractal_octaves = 2
	_initialized = true
	_place_settlements(seed_value)
	_connect_roads()


static func _raw_height(x: float, z: float) -> float:
	var hills := (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * 38.0
	var ridge := maxf(_ridges.get_noise_2d(x, z), 0.0)
	# Mountains rise away from the home valley so they frame the horizon.
	var valley := smoothstep(300.0, 700.0, Vector2(x, z).length())
	var mountains := pow(ridge, 2.2) * 160.0 * valley
	var edge := maxf(absf(x), absf(z))
	var rim := pow(smoothstep(WORLD_HALF - 250.0, WORLD_HALF, edge), 1.5) * 200.0
	return hills + mountains + rim + _detail.get_noise_2d(x, z) * 0.6


static func height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	var p := Vector2(x, z)
	# Flatten settlements into plateaus.
	for s in settlements:
		var d := p.distance_to(s["pos"])
		var r: float = s["radius"]
		if d < r * 1.8:
			h = lerpf(s["base_h"], h, smoothstep(r, r * 1.8, d))
	# Roads cut a gentle bed.
	var rd := road_distance(x, z)
	if rd < 10.0:
		h = lerpf(h - 0.4, h, smoothstep(2.0, 10.0, rd))
	return h


static func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for r in roads:
		var a: Vector2 = settlements[r.x]["pos"]
		var b: Vector2 = settlements[r.y]["pos"]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


static func color_at(x: float, z: float, h: float, slope: float) -> Color:
	var tint := _detail.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5
	var c := Color("4d7a34").lerp(Color("6b8f3c"), tint)
	var forest := forest_density(x, z)
	c = c.lerp(Color("3a5f2c"), forest * 0.5)
	if slope > 0.5 or h > 90.0:
		c = Color("7d7768").lerp(Color("948c7a"), tint)
	if h > 150.0:
		c = Color("e8ecef")
	var near := nearest_settlement(Vector2(x, z))
	if not near.is_empty() and Vector2(x, z).distance_to(near["pos"]) < near["radius"] * 0.35:
		c = Color("8a6d45").lerp(Color("977a50"), tint)
	if road_distance(x, z) < 3.0:
		c = Color("83633d").lerp(Color("8f6e45"), tint)
	return c


static func forest_density(x: float, z: float) -> float:
	var f := clampf(_forest.get_noise_2d(x, z) * 1.8 + 0.25, 0.0, 1.0)
	var near := nearest_settlement(Vector2(x, z))
	if not near.is_empty():
		f *= smoothstep(near["radius"] * 1.2, near["radius"] * 2.2, Vector2(x, z).distance_to(near["pos"]))
	if road_distance(x, z) < 8.0:
		f = 0.0
	return f


static func nearest_settlement(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in settlements:
		var d := p.distance_squared_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best


static func _place_settlements(seed_value: int) -> void:
	settlements.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Home village at the origin, the royal castle a ride away to the north-east.
	var fixed := [
		{"pos": Vector2(0, 0), "kind": "village", "radius": 45.0},
		{"pos": Vector2(520, -380), "kind": "castle", "radius": 80.0},
	]
	var attempts := 0
	while fixed.size() < SETTLEMENT_COUNT and attempts < 4000:
		attempts += 1
		var p := Vector2(rng.randf_range(-1600, 1600), rng.randf_range(-1600, 1600))
		if _raw_height(p.x, p.y) > 70.0:
			continue
		var ok := true
		for f in fixed:
			if p.distance_to(f["pos"]) < 480.0:
				ok = false
				break
		if ok:
			var town := rng.randf() < 0.35
			fixed.append({"pos": p, "kind": "town" if town else "village", "radius": 60.0 if town else 45.0})
	for i in fixed.size():
		var f: Dictionary = fixed[i]
		var pos: Vector2 = f["pos"]
		var pop: int = {"village": 320, "town": 1100, "castle": 2400}[f["kind"]]
		settlements.append({
			"id": i, "name": NAMES[i % NAMES.size()], "pos": pos, "radius": f["radius"],
			"base_h": _raw_height(pos.x, pos.y), "kind": f["kind"], "population": pop,
		})


static func _connect_roads() -> void:
	# Minimum spanning tree over settlements: every town reachable by road.
	roads.clear()
	var linked := {0: true}
	while linked.size() < settlements.size():
		var best := Vector2i(-1, -1)
		var best_d := INF
		for a in linked:
			for s in settlements:
				var b: int = s["id"]
				if linked.has(b):
					continue
				var d: float = settlements[a]["pos"].distance_to(s["pos"])
				if d < best_d:
					best_d = d
					best = Vector2i(a, b)
		roads.append(best)
		linked[best.y] = true
