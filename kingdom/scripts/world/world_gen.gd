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
## Flattened grounds for monster camps from data/world/first_region.json: [{pos, radius, base_h}]
static var camp_grounds: Array[Dictionary] = []
## Road segments as pairs of settlement ids.
static var roads: Array[Vector2i] = []
## Places between settlements (RegionSites.plan): farms, bridges, ruins, landmarks.
static var sites: Array[Dictionary] = []
## Ground those sites claim: [{pos, radius, flatten, base_h}]. No trees inside;
## flattened ones level the terrain like camp grounds.
static var clearings: Array[Dictionary] = []

static var _hills := FastNoiseLite.new()
static var _ridges := FastNoiseLite.new()
static var _detail := FastNoiseLite.new()
static var _forest := FastNoiseLite.new()
static var _initialized := false

## Water: one lake near the home valley, fed by a river from the hills and
## drained by another toward the world edge. See _place_water().
const LAKE_DISTANCE := 450.0        # from Ashford (fallback search only)
const LAKE_RADIUS := 110.0          # mean shoreline radius (noise adds about +-30%)
## First-region layout from the lore (data/world/first_region.json), x/z metres
## from Ashford, north = -z. Emberglass Mere is the lake; the Ashrun runs from
## the northern hills, under the Ashrun Bridge (Oakvale road, about (-318, -214)),
## into the mere and out toward the south-west edge of the world.
const MERE_CENTER := Vector2(-420, 300)
const ASHRUN_UPSTREAM := [Vector2(-150, -900), Vector2(-330, -150)]
const ASHRUN_DOWNSTREAM := [Vector2(-1500, 1200)]
const LAKE_DEPTH := 6.5
const RIVER_STEP := 16.0            # polyline sample spacing
const RIVER_CELL := 64.0            # spatial hash cell for river segments
const RIVER_REACH := 150.0          # how far a river can reshape terrain
static var lake_center := Vector2(1.0e6, 1.0e6)
static var lake_radius := LAKE_RADIUS
static var lake_level := 0.0
## River polylines, each {points: PackedVector2Array, level/width/depth: PackedFloat32Array}.
## Points run downstream: arm 0 = source -> lake, arm 1 = lake -> world edge.
static var rivers: Array[Dictionary] = []
static var _shore := FastNoiseLite.new()
static var _lake_reach_sq := 0.0
static var _seg := PackedFloat32Array()          # stride 10 per segment: ax, az, bx, bz, la, lb, wa, wb, da, db
static var _river_grid: Dictionary = {}           # Vector2i -> PackedInt32Array of segment ids


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
	for st in settlements:
		st["plan"] = CityPlanner.plan(st, gate_angles(st), seed_value)
	_place_water(seed_value)
	_place_camp_grounds()
	clearings.clear()
	sites = RegionSites.plan(seed_value)
	for site in sites:
		if float(site["clear"]) > 0.0:
			var c: Vector2 = site["pos"]
			clearings.append({"pos": c, "radius": float(site["clear"]), "flatten": bool(site["flatten"]),
				"base_h": _raw_height(c.x, c.y)})


static func _place_camp_grounds() -> void:
	camp_grounds.clear()
	var path := "res://data/world/first_region.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return
	for pl: Dictionary in data.get("places", []):
		if String(pl.get("kind", "")) in ["goblin_warren", "orc_village"]:
			var arr: Array = pl["pos"]
			var c := Vector2(float(arr[0]), float(arr[1]))
			camp_grounds.append({"pos": c, "radius": float(pl.get("radius", 30.0)) * 1.15, "base_h": _raw_height(c.x, c.y)})


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
	for g in camp_grounds:
		var gd := p.distance_to(g["pos"])
		var gr: float = g["radius"]
		if gd < gr * 2.0:
			h = lerpf(g["base_h"], h, smoothstep(gr, gr * 2.0, gd))
	for c in clearings:
		if c["flatten"]:
			var cr: float = c["radius"]
			var cd := p.distance_to(c["pos"])
			if cd < cr * 1.8:
				h = lerpf(c["base_h"], h, smoothstep(cr * 0.8, cr * 1.8, cd))
	# Roads cut a gentle bed, wider under a kingdom road than a frontier trail.
	var rinfo := road_info(x, z)
	var half_w: float = float(rinfo["width"]) * 0.5
	var rd: float = rinfo["dist"]
	var cut_r := half_w + 6.0
	if rd < cut_r:
		h = lerpf(h - 0.4, h, smoothstep(half_w, cut_r, rd))
	# Lake basin and river channel (cheap rejects keep this fast away from water).
	var lake_s := 99.0
	if p.distance_squared_to(lake_center) < _lake_reach_sq:
		lake_s = _lake_s(p)
		h = _carve(h, _lake_profile(lake_s), (lake_s - 1.0) * lake_radius, lake_radius * 0.3, 0.25)
	var cell := Vector2i(floori(x / RIVER_CELL), floori(z / RIVER_CELL))
	if _river_grid.has(cell):
		var q := _river_query(p, _river_grid[cell])
		if not q.is_empty():
			var d: float = q["d"]
			var w: float = q["w"]
			var lv: float = q["level"]
			var dep: float = q["depth"]
			var f := lv - dep * (1.0 - (d / w) * (d / w)) if d < w else lv + (d - w) * 0.18
			var hr := _carve(h, f, d - w, 12.0, 0.14)
			# Inside the lake the river may only deepen the bed, never raise it.
			h = lerpf(minf(h, hr), hr, smoothstep(0.55, 0.95, lake_s))
	return h


# --- Water ------------------------------------------------------------------------

## Water surface height at (x, z), or NAN where there is no lake or river nearby.
## Defined over a band a little wider than the wet area (so surface meshes can
## tuck under the shore); use is_water() / water_depth() to know if it is wet.
static func water_level_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if p.distance_squared_to(lake_center) < _lake_reach_sq and _lake_s(p) < 1.25:
		return lake_level
	var cell := Vector2i(floori(x / RIVER_CELL), floori(z / RIVER_CELL))
	if _river_grid.has(cell):
		var q := _river_query(p, _river_grid[cell])
		if not q.is_empty() and float(q["d"]) < float(q["w"]) + 10.0:
			return q["level"]
	return NAN


## Metres of water above the ground (0 on land).
static func water_depth(x: float, z: float) -> float:
	var lv := water_level_at(x, z)
	if is_nan(lv):
		return 0.0
	return maxf(lv - height(x, z), 0.0)


static func is_water(x: float, z: float) -> bool:
	return water_depth(x, z) > 0.0


## Surface current in m/s: rivers run downstream, fastest mid-channel; the lake is still.
static func water_flow(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var calm := 1.0
	if p.distance_squared_to(lake_center) < _lake_reach_sq:
		calm = smoothstep(0.75, 1.15, _lake_s(p))
	var cell := Vector2i(floori(x / RIVER_CELL), floori(z / RIVER_CELL))
	if calm <= 0.0 or not _river_grid.has(cell):
		return Vector2.ZERO
	var q := _river_query(p, _river_grid[cell])
	if q.is_empty():
		return Vector2.ZERO
	var d: float = q["d"]
	var w: float = q["w"]
	if d > w + 10.0:
		return Vector2.ZERO
	var across := clampf(1.0 - (d / w) * (d / w), 0.15, 1.0)
	var speed := lerpf(1.5, 0.9, clampf((w - 3.5) / 9.0, 0.0, 1.0))
	var dir: Vector2 = q["dir"]
	return dir * speed * across * calm


## Approximate metres from (x, z) to the nearest lake shore or river edge
## (negative inside the water, INF far away). Cheap: does not call height().
static func shore_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	if p.distance_squared_to(lake_center) < _lake_reach_sq:
		best = (_lake_s(p) - 1.0) * lake_radius
	var cell := Vector2i(floori(x / RIVER_CELL), floori(z / RIVER_CELL))
	if _river_grid.has(cell):
		var q := _river_query(p, _river_grid[cell])
		if not q.is_empty():
			best = minf(best, float(q["d"]) - float(q["w"]))
	return best


static func near_water(x: float, z: float, margin: float) -> bool:
	return shore_distance(x, z) < margin


## Normalised lake coordinate: 0 at the centre, 1 on the (noisy) shoreline.
static func _lake_s(p: Vector2) -> float:
	var v := p - lake_center
	var l := v.length()
	if l < 0.001:
		return 0.0
	var dir := v / l
	var r := lake_radius * (1.0 + 0.3 * _shore.get_noise_2d(dir.x * 0.9, dir.y * 0.9) + 0.14 * dir.x * dir.y)
	return l / r


## Ideal lake terrain at lake coordinate s: a bowl with a shallow sandy shelf.
static func _lake_profile(s: float) -> float:
	if s < 1.0:
		return lake_level + 0.25 - (LAKE_DEPTH + 0.25) * (1.0 - smoothstep(0.3, 1.0, s))
	return lake_level + 0.25 + (s - 1.0) * lake_radius * 0.06


## Blends terrain height `h` toward an ideal water profile `f`. `d_out` is the
## distance outside the water edge (negative inside). Higher ground is cut back
## with a slope-limited bank; lower ground is raised into a levee that stays
## flat for `flat` metres then falls away at `fill_slope`, so the water never
## spills past its intended edge.
static func _carve(h: float, f: float, d_out: float, flat: float, fill_slope: float) -> float:
	if h >= f:
		var bank := minf(5.0 + (h - f) * 1.3, 85.0)
		return lerpf(f, h, smoothstep(0.0, bank, d_out))
	var ff := f if d_out < flat else f - (d_out - flat) * fill_slope
	return maxf(h, ff)


## Nearest river segment among `ids`: {d, level, w, depth, dir}.
static func _river_query(p: Vector2, ids: PackedInt32Array) -> Dictionary:
	var best := INF
	var bi := -1
	var bt := 0.0
	for i in ids:
		var o := i * 10
		var a := Vector2(_seg[o], _seg[o + 1])
		var ab := Vector2(_seg[o + 2], _seg[o + 3]) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var dsq := p.distance_squared_to(a + ab * t)
		if dsq < best:
			best = dsq
			bi = i
			bt = t
	if bi < 0:
		return {}
	var k := bi * 10
	return {"d": sqrt(best), "level": lerpf(_seg[k + 4], _seg[k + 5], bt), "w": lerpf(_seg[k + 6], _seg[k + 7], bt),
		"depth": lerpf(_seg[k + 8], _seg[k + 9], bt),
		"dir": Vector2(_seg[k + 2] - _seg[k], _seg[k + 3] - _seg[k + 1]).normalized()}


static func _place_water(seed_value: int) -> void:
	_shore.seed = seed_value + 51
	_shore.frequency = 1.0
	_shore.fractal_octaves = 2
	rivers.clear()
	_seg = PackedFloat32Array()
	_river_grid.clear()
	lake_center = Vector2(1.0e6, 1.0e6)
	_lake_reach_sq = 0.0
	var hp: Vector2 = settlements[0]["pos"]
	if _lore_layout_fits(hp):
		lake_center = hp + MERE_CENTER
		_finish_lake()
		var up := PackedVector2Array()
		for c: Vector2 in ASHRUN_UPSTREAM:
			up.append(hp + c)
		up.append(lake_center)
		var down := PackedVector2Array([lake_center])
		for c: Vector2 in ASHRUN_DOWNSTREAM:
			down.append(hp + c)
		var last := down[down.size() - 1]
		var out_dir := (last - down[down.size() - 2]).normalized()
		down.append(last + out_dir * _edge_distance(last, out_dir))
		_add_river(_polyline(up, 3.0, 28.0), true)
		_add_river(_polyline(down, 17.0, 45.0), false)
		return
	# Fallback for other seeds/layouts: the spot about LAKE_DISTANCE out that keeps
	# clearest of every road and town, on the calmest ground.
	var best_score := -INF
	var best := hp + Vector2(LAKE_DISTANCE, 0)
	for i in 72:
		var ang := TAU * i / 72.0
		for dist: float in [LAKE_DISTANCE - 30.0, LAKE_DISTANCE, LAKE_DISTANCE + 30.0]:
			var c := hp + Vector2(cos(ang), sin(ang)) * dist
			var ring := _ring_stats(c, lake_radius * 1.15)
			var score := minf(_lake_clearance(c), 60.0) - (ring.y - ring.x) * 1.5
			if score > best_score:
				best_score = score
				best = c
	lake_center = best
	_finish_lake()
	# Rivers: upstream (from the hills) and downstream (to the world edge) courses
	# that stay away from towns and cross the fewest roads.
	var out := (lake_center - hp).normalized()
	var ups: Array[Dictionary] = []
	var downs: Array[Dictionary] = []
	for k in range(-4, 5):
		var dir := out.rotated(deg_to_rad(22.0 * k))
		var up := _polyline(PackedVector2Array([lake_center + dir * 850.0, lake_center]), 3.0 + k, 110.0)
		ups.append({"pts": up, "dir": dir, "score": _course_score(up) + _raw_height(up[0].x, up[0].y) * 0.4})
		var far := _edge_distance(lake_center, dir)
		var down := _polyline(PackedVector2Array([lake_center, lake_center + dir * far]), 17.0 + k, 110.0)
		downs.append({"pts": down, "dir": dir, "score": _course_score(down) - far * 0.03})
	var pick := Vector2i(0, 0)
	var pick_score := -INF
	for a in ups.size():
		for b in downs.size():
			var sep := absf((ups[a]["dir"] as Vector2).angle_to(downs[b]["dir"]))
			if sep < deg_to_rad(95.0):
				continue
			var sc: float = ups[a]["score"] + downs[b]["score"]
			if sc > pick_score:
				pick_score = sc
				pick = Vector2i(a, b)
	_add_river(ups[pick.x]["pts"], true)
	_add_river(downs[pick.y]["pts"], false)


## Metres of margin between the lake's reach and the nearest road or town.
static func _lake_clearance(c: Vector2) -> float:
	var clear := road_distance(c.x, c.y) - lake_radius * 1.45
	for s in settlements:
		clear = minf(clear, c.distance_to(s["pos"]) - float(s["radius"]) * 1.8 - lake_radius * 1.45)
	return clear


## The lore layout is used when the lake and river keep clear of towns and roads.
static func _lore_layout_fits(hp: Vector2) -> bool:
	if _lake_clearance(hp + MERE_CENTER) < 0.0:
		return false
	var pts := PackedVector2Array()
	for c: Vector2 in ASHRUN_UPSTREAM + ASHRUN_DOWNSTREAM:
		pts.append(hp + c)
	return _course_score(pts) > -1000.0


static func _finish_lake() -> void:
	var stats := _ring_stats(lake_center, lake_radius * 1.15)
	lake_level = lerpf(stats.x, stats.y, 0.3) - 1.0
	_lake_reach_sq = pow(lake_radius * 1.5 + 200.0, 2.0)


## (min, max) raw terrain height around a ring.
static func _ring_stats(c: Vector2, r: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in 24:
		var a := TAU * i / 24.0
		var h := _raw_height(c.x + cos(a) * r, c.y + sin(a) * r)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


## Distance from `c` along `dir` to just past the world edge.
static func _edge_distance(c: Vector2, dir: Vector2) -> float:
	var half := WORLD_HALF + 40.0
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, ((half if dir.x > 0.0 else -half) - c.x) / dir.x)
	if absf(dir.y) > 0.001:
		t = minf(t, ((half if dir.y > 0.0 else -half) - c.y) / dir.y)
	return t


## A gently meandering polyline through control points (which it passes
## exactly), resampled every RIVER_STEP metres.
static func _polyline(ctrl: PackedVector2Array, salt: float, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array([ctrl[0]])
	var travelled := 0.0
	for c in ctrl.size() - 1:
		var a := ctrl[c]
		var b := ctrl[c + 1]
		var length := a.distance_to(b)
		var n := maxi(2, ceili(length / RIVER_STEP))
		var side := (b - a).normalized().orthogonal()
		for i in range(1, n + 1):
			var t := float(i) / n
			var along := travelled + t * length
			var wiggle := _shore.get_noise_2d(along * 0.004, salt * 37.0) + _shore.get_noise_2d(along * 0.012, salt * 37.0 + 9.0) * 0.2
			pts.append(a.lerp(b, t) + side * wiggle * amp * sin(PI * t))
		travelled += length
	return pts


## Penalises courses that pass through towns or near home, or cross roads.
static func _course_score(pts: PackedVector2Array) -> float:
	var score := 0.0
	var on_road := false
	for p in pts:
		if absf(p.x) > WORLD_HALF or absf(p.y) > WORLD_HALF:
			continue
		for s in settlements:
			var keep := float(s["radius"]) * 1.8 + (140.0 if s["id"] == 0 else 50.0)
			if p.distance_to(s["pos"]) < keep:
				score -= 1000.0
		var rd := road_distance(p.x, p.y)
		if rd < 14.0 and not on_road:
			score -= 60.0
		elif rd < 40.0:
			score -= 2.0     # running alongside a road
		on_road = rd < 14.0
	return score


## Adds a river arm (points ordered downstream): levels that only ever fall
## downstream, width/depth growing with the flow, shallow fords at road crossings.
static func _add_river(pts: PackedVector2Array, feeds_lake: bool) -> void:
	var n := pts.size()
	var lv := PackedFloat32Array()
	var wd := PackedFloat32Array()
	var dp := PackedFloat32Array()
	lv.resize(n)
	wd.resize(n)
	dp.resize(n)
	var in_lake: Array[bool] = []
	# The river follows a smoothed (+-100 m) version of the ground, so it neither
	# climbs every hill nor has to be banked up across every hollow.
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = _raw_height(pts[i].x, pts[i].y)
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		var sum := 0.0
		var cnt := 0
		for j in range(maxi(0, i - 6), mini(n, i + 7)):
			sum += raw[j]
			cnt += 1
		smooth[i] = minf(sum / cnt, raw[i] + 2.0)
	var run := INF if feeds_lake else lake_level
	for i in n:
		var p := pts[i]
		var t := float(i) / (n - 1)
		in_lake.append(_lake_s(p) < 1.3)
		if in_lake[i]:
			lv[i] = lake_level
		else:
			run = minf(run, smooth[i] - 1.0)
			lv[i] = maxf(run, lake_level) if feeds_lake else run
		wd[i] = lerpf(3.5, 8.0, t) if feeds_lake else lerpf(9.0, 12.5, t)
		var depth := lerpf(0.9, 1.9, t) if feeds_lake else 2.1
		dp[i] = lerpf(0.4, depth, smoothstep(6.0, 26.0, road_distance(p.x, p.y)))
	if feeds_lake:
		# Keep the approach to the lake gentle (<= 3.5 % grade) rather than a cliff.
		for i in range(n - 2, -1, -1):
			lv[i] = minf(lv[i], lv[i + 1] + 0.035 * RIVER_STEP)
	for pass_i in 3:
		var sm := lv.duplicate()
		for i in range(1, n - 1):
			if not in_lake[i]:
				sm[i] = lv[i - 1] * 0.25 + lv[i] * 0.5 + lv[i + 1] * 0.25
		lv = sm
	rivers.append({"points": pts, "level": lv, "width": wd, "depth": dp})
	for i in n - 1:
		var id := _seg.size() / 10
		var a := pts[i]
		var b := pts[i + 1]
		_seg.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, lv[i], lv[i + 1], wd[i], wd[i + 1], dp[i], dp[i + 1]]))
		var grow := RIVER_REACH + maxf(wd[i], wd[i + 1])
		var lo := Vector2i(floori((minf(a.x, b.x) - grow) / RIVER_CELL), floori((minf(a.y, b.y) - grow) / RIVER_CELL))
		var hi := Vector2i(floori((maxf(a.x, b.x) + grow) / RIVER_CELL), floori((maxf(a.y, b.y) + grow) / RIVER_CELL))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var key := Vector2i(cx, cz)
				if not _river_grid.has(key):
					_river_grid[key] = PackedInt32Array()
				var ids: PackedInt32Array = _river_grid[key]
				ids.append(id)
				_river_grid[key] = ids


static func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for r in roads:
		var a: Vector2 = settlements[r.x]["pos"]
		var b: Vector2 = settlements[r.y]["pos"]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Road tiers by the size of the settlements they join: "kingdom" (touches the
## capital), "rural" (touches a town) or "frontier" (village to village).
const ROAD_WIDTH := {"kingdom": 7.0, "rural": 4.5, "frontier": 2.5}


static func _settlement_rank(kind: String) -> int:
	match kind:
		"castle": return 2
		"town": return 1
		_: return 0


static func road_tier(a: int, b: int) -> String:
	var top := maxi(_settlement_rank(settlements[a]["kind"]), _settlement_rank(settlements[b]["kind"]))
	if top >= 2:
		return "kingdom"
	elif top >= 1:
		return "rural"
	return "frontier"


## Cheap per-point road lookup: {tier, width (metres, full road width), dist
## (metres to the centreline)}. Reuses road_distance's loop so callers that
## need both distance and tier (colour, height, traffic, ambush placement)
## pay for the settlement loop once.
static func road_info(x: float, z: float) -> Dictionary:
	var p := Vector2(x, z)
	var best := INF
	var best_tier := "frontier"
	for r in roads:
		var a: Vector2 = settlements[r.x]["pos"]
		var b: Vector2 = settlements[r.y]["pos"]
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d < best:
			best = d
			best_tier = road_tier(r.x, r.y)
	return {"tier": best_tier, "width": float(ROAD_WIDTH[best_tier]), "dist": best}


## Directions (radians) of roads leaving a settlement: where its gates go.
static func gate_angles(s: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for r in roads:
		var other := -1
		if r.x == s["id"]:
			other = r.y
		elif r.y == s["id"]:
			other = r.x
		if other >= 0:
			var d: Vector2 = settlements[other]["pos"] - s["pos"]
			out.append(atan2(d.y, d.x))
	return out


## Distance to the nearest city street (INF outside settlements).
static func street_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var near := nearest_settlement(p)
	if near.is_empty() or not near.has("plan") or p.distance_to(near["pos"]) > near["radius"] * 1.15:
		return INF
	return CityPlanner.street_distance(near["plan"], p)


## Terrain material weights packed in a Color (see shaders/terrain.gdshader):
## r = dirt path, g = rock, b = cobblestone street, a = forest floor; grass = rest.
static func color_at(x: float, z: float, h: float, slope: float) -> Color:
	var w := Color(0, 0, 0, 0)
	w.a = clampf(forest_density(x, z) * 1.3, 0.0, 1.0)
	w.g = smoothstep(0.35, 0.55, slope) + smoothstep(80.0, 110.0, h)
	var near := nearest_settlement(Vector2(x, z))
	if not near.is_empty():
		var dc := Vector2(x, z).distance_to(near["pos"])
		var paved: bool = near["kind"] != "village"
		var sd := street_distance(x, z)
		if near.has("plan") and dc < near["plan"]["plaza_r"] + 2.0:
			var pr: float = near["plan"]["plaza_r"]
			if paved or dc < pr - 1.5: w.b = 1.0
			else: w.r = 1.0
			w.a = 0.0
		elif sd < 1.0:
			var k := 1.0 - smoothstep(-0.5, 1.0, sd)
			if paved: w.b = maxf(w.b, k)
			else: w.r = maxf(w.r, k)
			w.a = 0.0
		elif dc < near["radius"] * 0.95 and paved:
			w.r = maxf(w.r, 0.35)   # trampled yards inside the walls
		if near.has("plan") and dc < near["radius"] * 1.1:
			var pd := CityPlanner.path_distance(near["plan"], Vector2(x, z))
			if pd < 0.8:
				w.r = maxf(w.r, (1.0 - smoothstep(-0.4, 0.8, pd)) * 0.9)
				w.a = 0.0
			# Worn dirt ring around every building's base, so a house never meets grass
			# with a hard edge (the "sits like a sticker" look). Lots are a short list
			# (tens per settlement), and this only runs near a settlement already.
			if dc < near["radius"] * 1.05:
				for lot: Dictionary in near["plan"]["lots"]:
					var lp: Vector2 = lot["pos"]
					var ld := Vector2(x, z).distance_to(lp)
					if ld < 7.0:
						var k := (1.0 - smoothstep(2.8, 7.0, ld)) * 0.65
						w.r = maxf(w.r, k)
						w.a *= 1.0 - clampf(k * 1.5, 0.0, 1.0)
						break   # one nearby lot is enough; footprints rarely overlap
	var rinfo := road_info(x, z)
	var rd: float = rinfo["dist"]
	var half_w: float = float(rinfo["width"]) * 0.5
	# Painterly edge: a little noise wobble so the road margin isn't a ruler line.
	var wobble := _detail.get_noise_2d(x * 0.35, z * 0.35) * 0.5
	var edge := half_w + 1.5 + wobble
	if rd < edge:
		var k := 1.0 - smoothstep(half_w - 0.5, edge, rd)
		var paved_here := not near.is_empty() and Vector2(x, z).distance_to(near["pos"]) < float(near["radius"]) * 1.8
		if paved_here:
			w.b = maxf(w.b, k)          # cobble near settlements, on any tier
		else:
			w.r = maxf(w.r, k)          # packed dirt / trail out on the open road
		w.a = 0.0
		# Drainage ditch: a darker, slightly rockier verge just outside the surface.
		if rd > half_w - 0.4:
			var ditch := (1.0 - smoothstep(half_w - 0.4, edge + 1.0, rd)) * 0.3
			w.g = maxf(w.g, ditch)
	# Worn dirt around region sites (farms, mines, bandit camps, wayshrines, ruins):
	# their buildings and clutter otherwise sit straight on unbroken grass. `clearings`
	# is a short list (one entry per site), already walked by forest_density().
	for c in clearings:
		var cd: float = Vector2(x, z).distance_to(c["pos"])
		var cr: float = c["radius"]
		if cd < cr + 6.0:
			var k := (1.0 - smoothstep(cr - 1.0, cr + 6.0, cd)) * 0.55
			w.r = maxf(w.r, k)
			w.a *= 1.0 - clampf(k * 1.4, 0.0, 1.0)
	# Shores: sandy dirt at the waterline, pebbles (rock) on the bed, more with depth.
	var lv := water_level_at(x, z)
	if not is_nan(lv):
		var above := h - lv
		var sand := 1.0 - smoothstep(0.2, 1.8, above)
		w.r = maxf(w.r, sand * 0.85)
		w.g = maxf(w.g, sand * (0.35 + clampf(-above * 0.2, 0.0, 0.45)))
		w.a *= 1.0 - sand
	return w


## Footstep family follows the same material weights used to paint the terrain.
static func footstep_surface(x: float, z: float) -> String:
	var h := height(x, z)
	var normal := Vector3(height(x - 1.0, z) - height(x + 1.0, z), 2.0,
		height(x, z - 1.0) - height(x, z + 1.0)).normalized()
	var weights := color_at(x, z, h, 1.0 - normal.y)
	return "stone" if weights.b > 0.3 or weights.g > 0.5 else "grass"


static func forest_density(x: float, z: float) -> float:
	var f := clampf(_forest.get_noise_2d(x, z) * 1.8 + 0.25, 0.0, 1.0)
	var near := nearest_settlement(Vector2(x, z))
	if not near.is_empty():
		# Fade starts at radius*1.8, not 1.2: height() blends a settlement's flat
		# plateau into natural terrain out to radius*1.8 (see height() above), so
		# starting the forest fade earlier let trees roll (at partial density) on
		# ground that was still mid-slope-transition. A tree's wide canopy AABB
		# samples WorldGen.height() at its footprint corners, several metres from
		# the trunk -- on that transition slope those corners could land metres
		# above/below the trunk's own ground, reading as a 3-5 m "floating" tree
		# in tools/qa/grounding even though the trunk itself was correctly
		# grounded. Waiting until the terrain is fully natural again removes the
		# slope, not just the probability.
		f *= smoothstep(near["radius"] * 1.8, near["radius"] * 2.8, Vector2(x, z).distance_to(near["pos"]))
	if road_distance(x, z) < 8.0:
		f = 0.0
	for c in clearings:
		if f > 0.0:
			f *= smoothstep(float(c["radius"]), float(c["radius"]) + 10.0, Vector2(x, z).distance_to(c["pos"]))
	if f > 0.0:
		f *= smoothstep(6.0, 20.0, shore_distance(x, z))   # no trees (or wolf dens) in water or on beaches
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


## Beyond Duskbriar Wood toward Tuskridge Hold (data/world/first_region.json,
## both fixed lore anchors), where the fortified frontier holds sit.
const TUSKRIDGE_POS := Vector2(300, 930)
const DUSKBRIAR_POS := Vector2(380, 480)
const DUSKBRIAR_RADIUS := 330.0
const TOWN_RADIUS := 115.0
const FRONTIER_TOWN_RADIUS := 75.0


static func _place_settlements(seed_value: int) -> void:
	settlements.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Home village at the origin, the royal castle a ride away to the north-east.
	var fixed := [
		{"pos": Vector2(0, 0), "kind": "village", "radius": 60.0},
		{"pos": Vector2(560, -420), "kind": "castle", "radius": 175.0},
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
			fixed.append({"pos": p, "kind": "town" if town else "village", "radius": 115.0 if town else 60.0})
	# Frontier towns: small fortified holds toward the dangerous edges, added on
	# top of SETTLEMENT_COUNT rather than competing with it for a slot. Its own
	# RNG stream (not the one above, whose state at this point depends on how
	# many attempts the random-village loop happened to take) keeps this step
	# reproducible on its own terms.
	var frontier_rng := RandomNumberGenerator.new()
	frontier_rng.seed = seed_value + 4051
	_place_frontier_towns(fixed, frontier_rng)
	# Guarantee kingdom rings: a fixed seed can otherwise roll zero "town"-kind
	# settlements at all (see docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "World
	# structure (rings)"), leaving nothing between the capital and the villages.
	_promote_kingdom_towns(fixed)
	for i in fixed.size():
		var f: Dictionary = fixed[i]
		var pos: Vector2 = f["pos"]
		# ~33-35% fewer residents than the original 320/1100/2400: markets and
		# streets stayed lively but too crowded (docs/qa/PERFORMANCE.md).
		var pop: int = {"village": 210, "town": 720, "castle": 1600, "frontier_town": 380}[f["kind"]]
		settlements.append({
			"id": i, "name": NAMES[i % NAMES.size()], "pos": pos, "radius": f["radius"],
			"base_h": _raw_height(pos.x, pos.y), "kind": f["kind"], "population": pop,
		})


## The minimum-spanning-tree road edges over `positions` (same algorithm as
## _connect_roads(), duplicated here since roads aren't built yet when
## settlements are still being placed/promoted).
static func _mst_edges(positions: Array[Vector2]) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	var linked := {0: true}
	while linked.size() < positions.size():
		var best := Vector2i(-1, -1)
		var best_d := INF
		for a in linked:
			for b in positions.size():
				if linked.has(b):
					continue
				var d: float = positions[a].distance_to(positions[b])
				if d < best_d:
					best_d = d
					best = Vector2i(a, b)
		edges.append(best)
		linked[best.y] = true
	return edges


## True if every road the final MST would draw over `positions` keeps at least
## `margin` clear of `danger` -- used so a new settlement's own road, or the
## way it reshapes everyone else's MST edges, never cuts across a stretch of
## road the design (or a test) relies on staying open ground.
static func _mst_clears_point(positions: Array[Vector2], danger: Vector2, margin: float) -> bool:
	for e in _mst_edges(positions):
		var a: Vector2 = positions[e.x]
		var b: Vector2 = positions[e.y]
		if Geometry2D.get_closest_point_to_segment(danger, a, b).distance_to(danger) < margin:
			return false
	return true


## 1-2 small palisade-style holds beyond Duskbriar Wood on the way to Tuskridge,
## clear of the orc hold itself, the wood's centre and every other settlement,
## and never routed (directly or by reshaping the road network) across the
## safe stretch of the King's Ember Road 500 m south of its midpoint.
static func _place_frontier_towns(fixed: Array, rng: RandomNumberGenerator) -> void:
	var base_dir := (TUSKRIDGE_POS - DUSKBRIAR_POS).normalized()
	var home: Vector2 = fixed[0]["pos"]
	var capital: Vector2 = fixed[1]["pos"]
	var kingdom_road_danger := home.lerp(capital, 0.5) + Vector2(0, 500)
	var placed: Array[Vector2] = []
	for n in 2:
		var best := Vector2.INF
		var best_score := -INF
		for i in 900:
			var ang := rng.randf_range(-0.8, 0.8)
			var dist := DUSKBRIAR_RADIUS * 1.05 + rng.randf_range(60.0, 480.0)
			var p := DUSKBRIAR_POS + base_dir.rotated(ang) * dist
			if _raw_height(p.x, p.y) > 130.0 or p.distance_to(TUSKRIDGE_POS) < 150.0:
				continue
			var ok := true
			for f in fixed:
				if p.distance_to(f["pos"]) < 340.0:
					ok = false
					break
			if ok:
				for q in placed:
					if p.distance_to(q) < 260.0:
						ok = false
						break
			if not ok:
				continue
			var positions: Array[Vector2] = []
			for f in fixed:
				positions.append(f["pos"])
			positions.append(p)
			if not _mst_clears_point(positions, kingdom_road_danger, 320.0):
				continue
			var score := -absf(p.distance_to(TUSKRIDGE_POS) - 230.0) + rng.randf() * 15.0
			if score > best_score:
				best_score = score
				best = p
		if best != Vector2.INF:
			placed.append(best)
			fixed.append({"pos": best, "kind": "frontier_town", "radius": FRONTIER_TOWN_RADIUS})


## The settlements closest to the King's Ember Road corridor (Ashford to the
## capital), or simply nearest the capital, become "town" kind: larger, walled,
## with a real market -- so the kingdom always has towns between the capital
## and the villages, not just the two lore anchors. Never touches Ashford
## (index 0) or the capital (index 1), and never demotes an existing town.
static func _promote_kingdom_towns(fixed: Array) -> void:
	var home: Vector2 = fixed[0]["pos"]
	var capital: Vector2 = fixed[1]["pos"]
	var scored: Array = []
	for i in range(2, fixed.size()):
		var f: Dictionary = fixed[i]
		if f["kind"] == "frontier_town":
			continue
		var p: Vector2 = f["pos"]
		var corridor := p.distance_to(Geometry2D.get_closest_point_to_segment(p, home, capital))
		var to_capital := p.distance_to(capital)
		scored.append({"i": i, "score": minf(corridor, to_capital * 0.4)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
	for n in mini(3, scored.size()):
		var idx: int = scored[n]["i"]
		fixed[idx]["kind"] = "town"
		fixed[idx]["radius"] = TOWN_RADIUS


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
