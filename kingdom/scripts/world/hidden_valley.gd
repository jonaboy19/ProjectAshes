extends RefCounted
## THE HIDDEN VALE: a secluded, untouched valley in the west of the 8 x 8 km region, reached only through a
## hidden gorge (docs/design/REALM_PLAN.md "Freedom and exploration first").
##
## Everything here is DATA + pure functions of the seed, in the same spirit as Region1Terrain: world_gen.gd
## only calls into this file (each hook is one line commented "Hidden valley hook"):
##   WorldGen.setup():          HiddenValley.setup(seed)          (before anything samples the ground)
##   WorldGen._raw_height():    return HiddenValley.shape(x, z, h)   bowl + cliff rim + gorge + knoll
##   WorldGen._place_water():   HiddenValley.add_water()          the stream and the pond (no entry in `rivers`: not on the map)
##   WorldGen.color_at():       w = HiddenValley.paint(x, z, w)   no paths, mossy banks
##   WorldGen.forest_density(): f = HiddenValley.forest(x, z, f, with_clearings)   grove / meadow mask, none in the gorge
##   RegionSites.plan():        out.append_array(HiddenValley.sites())
##   TerrainStreamer._plan_forest(): HiddenValley.plan_extra(key, origin, buckets)   denser, lusher scatter
##   Camps.score_site():        + HiddenValley.site_bonus(pos)     fertile soil: the dream settlement site
##
## Local frame: the valley centre is CENTER, +u points OUT through the gorge (OUT), +v across (PERP).
## Shape (rn = elliptical radius, 1 = the edge of the meadow floor; the rim is always at least 40 m of rock wall):
##   rn < 1      floor: meadow, gentle roll, a stream from the falls to a pond, the settler's knoll
##   1 .. 1.5    wooded foothills (+9 m)
##   1.5 .. 1.68 the rim: sheer rock faces (slope > 2, not walkable)
##   > 1.68      a forested ridge that eases down to the natural land by rn 3.5
## The one way in is the gorge: an S-bend slot 6-7 m wide, cut through the rim from the south.

## Candidate centres (first one with room wins; see setup()). The vale sits far from every road and town.
const CANDIDATES := [Vector2(-2040.0, 40.0), Vector2(-740.0, -2500.0), Vector2(2020.0, -2900.0), Vector2(2600.0, 1500.0), Vector2(-3000.0, -2900.0)]
const CLEARANCE := 720.0
const OUT := Vector2(-0.1695, 0.9855)
const PERP := Vector2(-0.9855, -0.1695)
const A := 175.0                   # lateral semi-axis of the floor (m)
const B := 140.0                   # axial semi-axis
const REACH := 680.0               # nothing beyond this distance from CENTER is touched
const REACH_SQ := REACH * REACH
const RN_FOOT0 := 1.0
const RN_FOOT1 := 1.5
const RN_CLIFF1 := 1.68
const RN_SKIRT0 := 1.95
const RN_SKIRT1 := 3.5
const FOOT_RISE := 9.0
const RIM_RISE := 64.0
const GORGE_FROM := 150.0          # u where the slot starts to bite (inside the meadow floor it does nothing)
const GORGE_MOUTH := 470.0         # u of the outer mouth
const GORGE_END := 540.0
const KNOLL := Vector2(-15.0, 15.0)     # local (u, v) of the settler's knoll (Elder's Rise)
const KNOLL_FLAT := 22.0
const KNOLL_FOOT := 56.0
const KNOLL_RISE := 12.0

## Ground the pristine look counts as "inside": the floor plus the wooded foothills.
const INSIDE_RN := 1.5

static var CENTER := CANDIDATES[0]
static var _on := false
static var floor_h := 24.0          # natural ground height at the centre (set by setup)
static var mouth_h := 18.0          # natural ground height at the outer mouth
static var _nw := FastNoiseLite.new()     # rim warp
static var _nr := FastNoiseLite.new()     # floor roll
static var _nh := FastNoiseLite.new()     # rim height
static var _nm := FastNoiseLite.new()     # meadow patches
static var _ng := FastNoiseLite.new()     # groves
static var _streams: Array[Dictionary] = []


# --- Setup -------------------------------------------------------------------------

## WorldGen.setup hook #1 (first line, before anything samples the ground): the vale is off until the layout is known.
static func reset() -> void:
	_on = false
	_streams.clear()


## WorldGen.setup hook #2 (once settlements and roads exist): picks the first candidate with room, shapes the noises,
## samples the natural ground it is sunk into and switches the vale on.
static func setup(seed_value: int) -> void:
	_on = false
	_streams.clear()
	CENTER = _pick_center()
	_nw.seed = seed_value + 9011
	_nw.frequency = 0.0046
	_nw.fractal_octaves = 2
	_nr.seed = seed_value + 9023
	_nr.frequency = 0.011
	_nr.fractal_octaves = 2
	_nh.seed = seed_value + 9037
	_nh.frequency = 0.009
	_nh.fractal_octaves = 3
	_nm.seed = seed_value + 9041
	_nm.frequency = 0.013
	_nm.fractal_octaves = 2
	_ng.seed = seed_value + 9049
	_ng.frequency = 0.02
	_ng.fractal_octaves = 2
	# The natural ground the valley is sunk into (the hook returns the input while _on is false).
	var sum := 0.0
	var n := 0
	for o: Vector2 in [Vector2.ZERO, Vector2(50, 0), Vector2(-50, 0), Vector2(0, 50), Vector2(0, -50), Vector2(35, 35), Vector2(-35, 35), Vector2(35, -35), Vector2(-35, -35)]:
		sum += WorldGen._raw_height(CENTER.x + o.x, CENTER.y + o.y)
		n += 1
	floor_h = clampf(roundf(sum / n), 12.0, 70.0)
	var m := gorge_world(GORGE_MOUTH)
	mouth_h = WorldGen._raw_height(m.x, m.y)
	_on = true


## The first candidate centre at least CLEARANCE m from every settlement and road (else the roomiest).
static func _pick_center() -> Vector2:
	var best: Vector2 = CANDIDATES[0]
	var best_c := -INF
	for c: Vector2 in CANDIDATES:
		var room := INF
		for st in WorldGen.settlements:
			room = minf(room, c.distance_to(st["pos"]) - float(st["radius"]) * 1.5)
		for r in WorldGen.roads:
			var a: Vector2 = WorldGen.settlements[r.x]["pos"]
			var b: Vector2 = WorldGen.settlements[r.y]["pos"]
			room = minf(room, c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)))
		room = minf(room, WorldGen.WORLD_HALF - maxf(absf(c.x), absf(c.y)) - 600.0)
		if room >= CLEARANCE:
			return c
		if room > best_c:
			best_c = room
			best = c
	return best


static func enabled() -> bool:
	return _on


# --- Geometry helpers ---------------------------------------------------------------

## Local (u, v) -> world (x, z).
static func w(u: float, v: float) -> Vector2:
	return CENTER + OUT * u + PERP * v


## World (x, z) -> local (u, v).
static func to_local(p: Vector2) -> Vector2:
	var d := p - CENTER
	return Vector2(d.dot(OUT), d.dot(PERP))


## Lateral offset of the gorge centre line at u (an S bend, so no sightline runs down it).
static func gorge_offset(u: float) -> float:
	return 14.0 * sin(u * 0.022 + 0.6)


static func gorge_world(u: float) -> Vector2:
	return w(u, gorge_offset(u))


## Half width of the gorge floor at u: wide where it opens into the vale, a slot between, flared at the mouth.
static func gorge_half_width(u: float) -> float:
	return 3.4 + 9.0 * (1.0 - smoothstep(150.0, 215.0, u)) + 8.0 * smoothstep(400.0, 500.0, u)


static func gorge_wall(u: float) -> float:
	return 13.0 + 10.0 * smoothstep(400.0, 500.0, u)


## Height the gorge floor is cut down to at u: the meadow's own level, easing to the natural ground at the mouth.
static func gorge_floor(u: float) -> float:
	return lerpf(floor_h - u * 0.022, mouth_h, smoothstep(GORGE_FROM, GORGE_MOUTH, u))


## Elliptical radius with a slow warp so the rim wanders.
static func _rn(x: float, z: float, u: float, v: float) -> float:
	var q := sqrt((v / A) * (v / A) + (u / B) * (u / B))
	return q * (1.0 + 0.12 * _nw.get_noise_2d(x, z))


static func rn_at(p: Vector2) -> float:
	var l := to_local(p)
	return _rn(p.x, p.y, l.x, l.y)


## True on the meadow floor and the wooded foothills (the pristine ground).
static func in_valley(p: Vector2) -> bool:
	if not _on or p.distance_squared_to(CENTER) > REACH_SQ:
		return false
	return rn_at(p) < INSIDE_RN


## True in the vale itself or the gorge (beasts, dens and roads stay out).
static func protected_ground(p: Vector2) -> bool:
	if not _on or p.distance_squared_to(CENTER) > REACH_SQ:
		return false
	if rn_at(p) < 1.9:
		return true
	var l := to_local(p)
	return l.x > GORGE_FROM and l.x < GORGE_END and absf(l.y - gorge_offset(l.x)) < gorge_half_width(l.x) + gorge_wall(l.x) + 20.0


## Distance from the gorge centre line at p, and the local u (INF when p is outside the slot's length).
static func gorge_distance(p: Vector2) -> Vector2:
	var l := to_local(p)
	if l.x < 90.0 or l.x > GORGE_END:
		return Vector2(INF, l.x)
	return Vector2(absf(l.y - gorge_offset(l.x)), l.x)


static func knoll_world() -> Vector2:
	return w(KNOLL.x, KNOLL.y)


# --- Terrain -------------------------------------------------------------------------

static func _roll(x: float, z: float) -> float:
	return _nr.get_noise_2d(x, z) * 1.5


static func _knoll(u: float, v: float) -> float:
	var d := Vector2(u - KNOLL.x, v - KNOLL.y).length()
	return KNOLL_RISE * (1.0 - smoothstep(KNOLL_FLAT, KNOLL_FOOT, d))


## WorldGen._raw_height hook: natural height `h` -> height with the valley in it.
static func shape(x: float, z: float, h: float) -> float:
	if not _on:
		return h
	var dx := x - CENTER.x
	var dz := z - CENTER.y
	if dx * dx + dz * dz > REACH_SQ:
		return h
	var u := dx * OUT.x + dz * OUT.y
	var v := dx * PERP.x + dz * PERP.y
	var rn := _rn(x, z, u, v)
	var out := h
	if rn < RN_SKIRT1:
		var k_cliff := smoothstep(RN_FOOT1, RN_CLIFF1, rn)
		var k_out := 1.0 - smoothstep(RN_SKIRT0, RN_SKIRT1, rn)
		var kn := _knoll(u, v)
		var inner := floor_h - u * 0.022 + _roll(x, z) * (1.0 - kn / KNOLL_RISE) + kn + FOOT_RISE * smoothstep(RN_FOOT0, RN_FOOT1, rn)
		# Mountains are tamed so the wall never becomes a 150 m curtain.
		var nat := floor_h if h <= floor_h + 10.0 else floor_h + 10.0 + (h - floor_h - 10.0) * 0.45
		var rim := RIM_RISE + 14.0 * _nh.get_noise_2d(x, z)
		var outer := lerpf(h, nat + rim, k_out)
		out = lerpf(inner, outer, k_cliff)
	# The gorge: a slot cut through the rim and the skirt, only ever lowering the ground.
	if u > 100.0 and u < GORGE_END:
		var dv := absf(v - gorge_offset(u))
		var hw := gorge_half_width(u)
		var ww := gorge_wall(u)
		if dv < hw + ww:
			var c := (1.0 - smoothstep(hw, hw + ww, dv)) * smoothstep(110.0, 160.0, u)
			var g := gorge_floor(u) + _nr.get_noise_2d(x * 2.0, z * 2.0) * 0.5
			if out > g:
				out = lerpf(out, g, c)
	return out


## Extra fertility for the settlement score: rich meadow soil inside the valley.
static func site_bonus(pos: Vector2) -> float:
	if not _on or pos.distance_squared_to(CENTER) > REACH_SQ:
		return 0.0
	return 0.3 * (1.0 - smoothstep(0.72, 1.0, rn_at(pos)))


# --- Water ------------------------------------------------------------------------------

## Control points of the stream, local (u, v): from the foot of the falls to the pond's inlet.
const STREAM := [Vector2(-147, 10), Vector2(-128, 22), Vector2(-104, 10), Vector2(-80, -8), Vector2(-56, -26),
	Vector2(-32, -38), Vector2(-8, -46), Vector2(12, -50)]
const POND := [Vector2(40, -60), Vector2(14, -52)]
const POND_WIDTH := 23.0
const POND_DEPTH := 2.6


## Adds the stream and the pond to WorldGen's water index (not to `rivers`: they stay off the world map).
## Called at the end of WorldGen._place_water().
static func add_water() -> void:
	if not _on:
		return
	var ctrl := PackedVector2Array()
	for p: Vector2 in STREAM:
		ctrl.append(w(p.x, p.y))
	var pts := _resample(ctrl, 10.0)
	var n := pts.size()
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i in n:
		hs[i] = WorldGen._raw_height(pts[i].x, pts[i].y)
	var lv := PackedFloat32Array()
	lv.resize(n)
	var run := INF
	for i in n:
		var sum := 0.0
		var cnt := 0
		for j in range(maxi(0, i - 3), mini(n, i + 4)):
			sum += hs[j]
			cnt += 1
		run = minf(run, sum / cnt - 0.55)
		lv[i] = run
	var wd := PackedFloat32Array()
	var dp := PackedFloat32Array()
	wd.resize(n)
	dp.resize(n)
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		wd[i] = lerpf(2.4, 3.6, t)
		dp[i] = lerpf(0.65, 0.95, t)
	_inject(pts, lv, wd, dp)
	# The pond sits at the stream's final level.
	var pl := lv[n - 1] - 0.05
	var pp := PackedVector2Array([w(POND[0].x, POND[0].y), w(POND[1].x, POND[1].y)])
	var plv := PackedFloat32Array([pl, pl])
	var pwd := PackedFloat32Array([POND_WIDTH, POND_WIDTH])
	var pdp := PackedFloat32Array([POND_DEPTH, POND_DEPTH])
	_inject(pp, plv, pwd, pdp)
	_streams.append({"points": pts, "level": lv})
	_streams.append({"points": pp, "level": plv})


## The same tail as WorldGen._add_river: segments into the flat array and the spatial hash.
static func _inject(pts: PackedVector2Array, lv: PackedFloat32Array, wd: PackedFloat32Array, dp: PackedFloat32Array) -> void:
	for i in pts.size() - 1:
		var id := WorldGen._seg.size() / 10
		var a := pts[i]
		var b := pts[i + 1]
		WorldGen._seg.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, lv[i], lv[i + 1], wd[i], wd[i + 1], dp[i], dp[i + 1]]))
		var grow := WorldGen.RIVER_REACH + maxf(wd[i], wd[i + 1])
		var cell := WorldGen.RIVER_CELL
		var lo := Vector2i(floori((minf(a.x, b.x) - grow) / cell), floori((minf(a.y, b.y) - grow) / cell))
		var hi := Vector2i(floori((maxf(a.x, b.x) + grow) / cell), floori((maxf(a.y, b.y) + grow) / cell))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var key := Vector2i(cx, cz)
				if not WorldGen._river_grid.has(key):
					WorldGen._river_grid[key] = PackedInt32Array()
				var ids: PackedInt32Array = WorldGen._river_grid[key]
				ids.append(id)
				WorldGen._river_grid[key] = ids


## Catmull-Rom through the control points, a gentle lateral wobble, sampled every `step` metres.
static func _resample(ctrl: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([ctrl[0]])
	var travelled := 0.0
	for c in ctrl.size() - 1:
		var p0 := ctrl[maxi(c - 1, 0)]
		var p1 := ctrl[c]
		var p2 := ctrl[c + 1]
		var p3 := ctrl[mini(c + 2, ctrl.size() - 1)]
		var len := p1.distance_to(p2)
		var n := maxi(2, ceili(len / step))
		for i in range(1, n + 1):
			var t := float(i) / n
			var pt := p1.cubic_interpolate(p2, p0, p3, t)
			var side := (p2 - p1).normalized().orthogonal()
			var wob := _nw.get_noise_2d((travelled + t * len) * 0.05, 7.0) * 2.2 * sin(PI * t) if c > 0 else 0.0
			out.append(pt + side * wob)
		travelled += len
	return out


## Stream polylines (world x, z) and levels, for the waterfall and for tests.
static func streams() -> Array[Dictionary]:
	return _streams


# --- Paint and trees --------------------------------------------------------------------

## WorldGen.color_at hook: no paths or cobbles in the vale, softer banks, mossy gorge floor.
static func paint(x: float, z: float, wt: Color) -> Color:
	if not _on:
		return wt
	var dx := x - CENTER.x
	var dz := z - CENTER.y
	if dx * dx + dz * dz > REACH_SQ:
		return wt
	var u := dx * OUT.x + dz * OUT.y
	var v := dx * PERP.x + dz * PERP.y
	var rn := _rn(x, z, u, v)
	if rn < INSIDE_RN:
		# A touch of forest floor through the meadow grass (local look pass: the biome map now paints the vale lush itself,
		# so this dropped from 0.3 to 0.1; at 0.3 the leaf-litter texture turned the whole floor olive).
		wt.a = maxf(wt.a, 0.1 + 0.08 * _nm.get_noise_2d(x * 1.7, z * 1.7))
	if rn < 1.9:
		var k := 1.0 - smoothstep(1.55, 1.9, rn)
		wt.r *= 1.0 - 0.82 * k
		wt.b = 0.0
		# The rim's faces are bare rock (the shader's own slope test misses the steepest, stretched texels).
		wt.g = maxf(wt.g, 0.85 * smoothstep(1.46, 1.54, rn) * (1.0 - smoothstep(1.66, 1.78, rn)))
	if u > 100.0 and u < GORGE_END:
		var dv := absf(v - gorge_offset(u))
		var hw := gorge_half_width(u)
		if dv > hw - 0.5 and dv < hw + gorge_wall(u) * 0.9:
			wt.g = maxf(wt.g, 0.8 * smoothstep(hw - 0.5, hw + 3.0, dv) * smoothstep(120.0, 170.0, u) * (1.0 - smoothstep(430.0, 500.0, u)))
		if dv < hw + 2.0:
			var k := (1.0 - smoothstep(hw - 1.0, hw + 2.0, dv)) * smoothstep(150.0, 200.0, u) * (1.0 - smoothstep(420.0, 480.0, u))
			wt.a = maxf(wt.a, 0.55 * k)
			wt.g = maxf(wt.g, 0.25 * k)
			wt.r *= 1.0 - k
	return wt


## Open meadow share (0..1) at a point of the floor: the big central meadow plus wandering glades.
static func _open(x: float, z: float, rn: float) -> float:
	var core := 1.0 - smoothstep(0.40, 0.62, rn)
	var patch := smoothstep(0.16, 0.42, _nm.get_noise_2d(x, z))
	var o := maxf(core, patch * (1.0 - smoothstep(0.85, 1.05, rn)))
	if o < 1.0:
		var p := Vector2(x, z) - CENTER
		var u := p.dot(OUT)
		var v := p.dot(PERP)
		for sp: Vector3 in GLADES:
			var d := Vector2(u - sp.x, v - sp.y).length()
			if d < sp.z * 1.5:
				o = maxf(o, 1.0 - smoothstep(sp.z, sp.z * 1.5, d))
	return o


## Local (u, v, radius m) of the hand-placed places that keep a clear glade around them (ruin, stones, gazebo, spring).
const GLADES := [Vector3(38.0, 108.0, 26.0), Vector3(-70.0, -105.0, 19.0), Vector3(54.0, -14.0, 14.0), Vector3(-168.0, -14.0, 12.0),
	Vector3(-40.0, 95.0, 9.0), Vector3(62.0, -98.0, 9.0), Vector3(-132.0, -44.0, 9.0)]


## WorldGen.forest_density hook: groves of old trees between the meadows, bare cliffs, a clear gorge floor,
## a thick wood on the ridge. `with_clearings` false answers "how wooded is this ground" (glades count as wood).
static func forest(x: float, z: float, f: float, with_clearings: bool) -> float:
	if not _on:
		return f
	var dx := x - CENTER.x
	var dz := z - CENTER.y
	if dx * dx + dz * dz > REACH_SQ:
		return f
	var u := dx * OUT.x + dz * OUT.y
	var v := dx * PERP.x + dz * PERP.y
	var rn := _rn(x, z, u, v)
	if u > 100.0 and u < GORGE_END:
		var dv := absf(v - gorge_offset(u))
		if dv < gorge_half_width(u) + gorge_wall(u) + 2.0:
			return 0.0           # the slot and its walls: bare rock (boulders and overgrowth are placed by hand)
	if rn < RN_FOOT1:
		var grove := clampf(0.8 + 0.2 * _ng.get_noise_2d(x, z) * 2.0, 0.55, 1.0)
		var open := _open(x, z, rn)
		if with_clearings:
			return grove * (1.0 - open)
		# "How wooded is this ground": meadows count as the light wood they sit in, but under the streamer's leaf-litter
		# threshold (no flat litter discs on the grass).
		return lerpf(grove, 0.18, open)
	if rn < 1.8:
		return 0.0               # the rim's faces
	if rn < RN_SKIRT1:
		return clampf(f * 1.25 + 0.3 * (1.0 - smoothstep(1.8, 2.6, rn)), 0.0, 1.0)
	return f


# --- Lusher scatter (TerrainStreamer hook, worker thread) -----------------------------------

const REGION := "region/nature/"
const FLOWERS := [REGION + "flowers_warm", REGION + "flowers_cool", REGION + "flowers_warm", REGION + "flowers_cool", REGION + "grass_tall"]
## (Kept to the kinds the streamer's own forest already draws, few of them: every kind is one MultiMesh per chunk.)
const FLOOR := [REGION + "fern_a", REGION + "fern_b", REGION + "fern_a", REGION + "fern_b", REGION + "bush_hazel", REGION + "bush_round",
	REGION + "bush_berry", "Mushroom_Common", "floor/moss_patch", "floor/moss_patch", REGION + "grass_tall", REGION + "flowers_cool"]
const GIANTS := [REGION + "oak_a", REGION + "oak_b", REGION + "beech_a", REGION + "oak_a"]
const DEADFALL := [REGION + "log_mossy", REGION + "log_mossy"]
const CHUNK := 64.0

## Adds old-growth giants, meadow flowers and a thick forest floor to the chunk at `origin` when it overlaps the vale.
## Buckets use the same kind keys as the streamer's own forest, so they share its MultiMesh chains and LODs.
static func plan_extra(key: Vector2i, origin: Vector2, buckets: Dictionary) -> void:
	if not _on:
		return
	var mid := origin + Vector2(CHUNK, CHUNK) * 0.5
	if mid.distance_squared_to(CENTER) > 640.0 * 640.0:
		return
	var rn_mid := rn_at(mid)
	if rn_mid > 1.95 and mid.distance_squared_to(CENTER) > 480.0 * 480.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x7a1e0b
	# Meadow flowers
	for i in 360:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var q := _scatter_ok(x, z, 1.25)
		if q.x < 0.0:
			continue
		var open := _open(x, z, q.y)
		if open < 0.25 or rng.randf() > open:
			continue
		_put(buckets, FLOWERS[rng.randi() % FLOWERS.size()], x, z, rng.randf_range(0.9, 1.5), rng)
	# Forest floor under the groves, ferns thicker toward the rim
	for i in 330:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var q := _scatter_ok(x, z, 1.6)
		if q.x < 0.0:
			continue
		var open := _open(x, z, q.y)
		var grove := 1.0 - open * 0.8
		if rng.randf() > 0.35 + 0.65 * grove:
			continue
		var kind: String = FLOOR[rng.randi() % FLOOR.size()]
		if open > 0.3 and kind.begins_with("floor/"):
			kind = REGION + "flowers_warm"      # flat litter and moss belong under trees, not on the meadow
		_put(buckets, kind, x, z, rng.randf_range(0.8, 1.45), rng)
	# Fallen logs and stumps: the wood has stood an age
	for i in 10:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var q := _scatter_ok(x, z, 2.5)
		if q.x < 0.0 or _open(x, z, q.y) > 0.4:
			continue
		_put(buckets, DEADFALL[rng.randi() % DEADFALL.size()], x, z, rng.randf_range(0.9, 1.4), rng)
	# Old-growth giants in the groves
	for i in 14:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var q := _scatter_ok(x, z, 4.0)
		if q.x < 0.0 or q.y > 1.42 or _open(x, z, q.y) > 0.15:
			continue
		if WorldGen._raw_height(x + 3.0, z) - WorldGen._raw_height(x - 3.0, z) > 2.5:
			continue
		_put(buckets, GIANTS[rng.randi() % GIANTS.size()], x, z, rng.randf_range(1.45, 2.0), rng)


## [ok (1) / rejected (-1), rn]: dry ground inside the vale's wooded ground, off the gorge and the knoll's flat top.
static func _scatter_ok(x: float, z: float, water_margin: float) -> Vector2:
	var dx := x - CENTER.x
	var dz := z - CENTER.y
	var u := dx * OUT.x + dz * OUT.y
	var v := dx * PERP.x + dz * PERP.y
	var rn := _rn(x, z, u, v)
	if rn > 1.46:
		return Vector2(-1.0, rn)
	if u > 100.0 and absf(v - gorge_offset(u)) < gorge_half_width(u) + 1.5:
		return Vector2(-1.0, rn)
	if Vector2(u - KNOLL.x, v - KNOLL.y).length() < KNOLL_FLAT - 2.0:
		return Vector2(-1.0, rn)
	if WorldGen.near_water(x, z, water_margin):
		return Vector2(-1.0, rn)
	return Vector2(1.0, rn)


static func _put(buckets: Dictionary, kind: String, x: float, z: float, s: float, rng: RandomNumberGenerator) -> void:
	var h := WorldGen.height(x, z)
	var slope := absf(WorldGen.height(x + 0.6, z) - h) + absf(WorldGen.height(x, z + 0.6) - h)
	var sink := 0.15 + minf(slope * 0.7, 0.55)
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - sink, z))
	if kind.begins_with("floor/"):   # local look fix: flat moss cards follow the slope instead of floating as strips
		var nrm := Vector3(WorldGen.height(x - 1.0, z) - WorldGen.height(x + 1.0, z), 2.0, WorldGen.height(x, z - 1.0) - WorldGen.height(x, z + 1.0)).normalized()
		t = Transform3D(Basis(Quaternion(Vector3.UP, nrm)) * t.basis, Vector3(x, h - 0.05, z))
	if not buckets.has(kind):
		buckets[kind] = []
	buckets[kind].append(t)


# --- Sites (WorldGen.sites entries) ----------------------------------------------------------

## The vale as a secret place for Discovery / the map: only listed once found. Its position is the Old Stones,
## away from the open meadow where settlers will build.
static func stones_world() -> Vector2:
	return w(-70.0, -105.0)


static func sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _on:
		return out
	out.append({"name": "The Hidden Vale", "kind": "hidden_vale", "pos": stones_world(), "yaw": 0.0, "clear": 0.0, "flatten": false,
		"parts": [], "lights": [], "secret": true, "radius": 70.0, "poi": "hidden_vale"})
	return out


# --- Content (landmarks for the vale presenter, leads, facts) -----------------------------------

const FREE := "free:"
const GAP_PILLAR_U := 178.0

## Facts the discovery teaches (Society knowledge, text shown in the journal).
const FACT_LORE := "lore:hidden_vale"
const LORE_TEXT := "Beyond a slot in the western ridges lies a bowl of green nobody has named: a stream that falls from the rock, a still pond, old oaks and a ring of standing stones. The soil is black and deep, the water sweet, and the only way in is one narrow pass. It would make a fine place to found a home."
const FACT_LEAD := "lead:hidden_vale_home"
const LEAD_TEXT := "The Hidden Vale: a sheltered valley in the far west with rich soil, sweet water and one easy-to-hold pass. A settlement founded on the rise by the pond would want for nothing."

## Rumours, hunter hints and the map fragment: text only, never a marker. A direction and a sound, never a coordinate.
const RUMOURS := [
	"They say the stagborn go west past the last farms in the dry months, and come back fat and unhurried. Nobody has followed them far enough to see where.",
	"A drover swore he heard water falling in the western hills where there is no river. He went looking and lost the light.",
	"Old Hob the trapper swears there is a valley in the western ridges that no road reaches. His dogs wouldn't follow him in, he says, and he doesn't say why.",
	"My grandmother said the first families of Ashford came from a green bowl in the west, before the ash. She never said where.",
	"There's a place past the western hills with untouched soil, they say. Anyone who finds it doesn't come back to tell, because they've no reason to.",
	"A trader out of Cindermoor saw stag tracks going into solid rock at the foot of the ridges. He called it a trick of the light.",
]
const HUNTER_LINES := [
	"Stag tracks don't lie. Follow them west past Cindermoor where the land folds under the ridge, and listen for water that falls where there's no river. The pass is a slot behind a rockfall, no wider than two men.",
	"I lost a wounded hind in the western ridges once. She walked into a wall of ferns and boulders and was gone. There's a way through there, I'd wager my knives on it.",
]
const FRAGMENT_TEXT := "Half a map, burnt at the edges. A ridge like a horseshoe, open to the south. A line wanders north through ferns and fallen rock into the horseshoe's bowl, where someone has drawn a ring of stones and written one word: Home."
const FRAGMENT_REVEAL := 380.0


static func rumour() -> String:
	if not _on:
		return ""
	# (Life is an autoload compiled after WorldGen: reach it by path, never by name, in this file.)
	var tree := Engine.get_main_loop() as SceneTree
	var life: Node = tree.root.get_node_or_null("Life") if tree else null
	var d: Variant = life.get("discovery") if life else null
	if d is Object and (d as Object).has_method("is_discovered") and bool((d as Object).call("is_discovered", place_id())):
		return ""
	return String(RUMOURS[randi() % RUMOURS.size()])


## Reads the half-burnt map fragment (dropped by the Cartographer's camp; the dungeon code may give the item elsewhere and
## call this): a torn corner of the region's fog lifts around the ridges (never on the vale itself), and a lead is learned.
## Returns true the first time.
static func read_fragment() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var life: Node = tree.root.get_node_or_null("Life") if tree else null
	if life == null:
		return false
	var d: Variant = life.get("discovery")
	if not (d is Object) or bool((d as Object).call("noted", "fragment:read")):
		return false
	var at := w(250.0, 330.0)       # the southern ridges: the torn corner shows the outer rim, never the vale or its pass
	(d as Object).call("note", "fragment:read", 0)
	(d as Object).call("note", "reveal:%d:%d:%d" % [roundi(at.x), roundi(at.y), roundi(FRAGMENT_REVEAL)], 0)
	var realm: Variant = life.get("realm")
	if realm is RefCounted:
		var soc: Variant = (realm as RefCounted).call("mod", "society")
		if soc is RefCounted:
			(soc as RefCounted).call("learn", "lead:hidden_vale_map", FRAGMENT_TEXT)
	return true


## Discovery id of the vale (Discovery keys sites as "site:<name>:<x>:<z>").
static func place_id() -> String:
	var p := stones_world()
	return "site:The Hidden Vale:%d:%d" % [roundi(p.x), roundi(p.y)]


## Landmark definitions in Region1Look's format (id, name, kind, pos, near, parts, scatter, lights, waterfalls).
static func landmarks() -> Array[Dictionary]:
	if not _on:
		return []
	var out: Array[Dictionary] = []
	out.append(_core())
	out.append(_gorge_dressing())
	out.append(_nodes_landmark())
	return out


static func _p(a: String, at: Vector2, h: float, yaw := 0.0, extra := {}) -> Dictionary:
	var d := {"a": a, "w": [at.x, at.y], "h": h, "yaw": yaw}
	d.merge(extra, true)
	return d


static func _ring(a: String, at: Vector2, h: float, n: int, r: float, start := 0.0, extra := {}) -> Dictionary:
	var d := {"a": a, "w": [at.x, at.y], "h": h, "ring": {"n": n, "r": r, "start": start}}
	d.merge(extra, true)
	return d


static func _sc(kind: String, at: Vector2, r: float, n: int, r0 := 0.0, smin := 0.85, smax := 1.4, end := 120.0) -> Dictionary:
	return {"kind": kind, "w": [at.x, at.y], "r": r, "r0": r0, "n": n, "s": [smin, smax], "end": end}


static func _core() -> Dictionary:
	var stones := stones_world()
	var ruin := w(38.0, 108.0)
	var gaze := w(54.0, -14.0)
	var parts: Array = []
	# The Old Stones: a ring of menhirs on a mossy mound, a rune stone at its heart
	parts.append(_ring("r1:stones/road_stone_b_menhir", stones, 3.6, 6, 11.0, 12.0, {"collide": true}))
	parts.append(_p(FREE + "magic/runestone_face_moss", stones, 3.0, 40.0, {"collide": true}))
	parts.append(_p(FREE + "nature/rocks_mossy_mushroom", stones + Vector2(6, 5), 1.3, 20.0))
	parts.append(_p(FREE + "flora/stump_grass_rocks", stones + Vector2(-8, 4), 1.2, 120.0))
	# The builders' terrace: a mossy ruin above the meadow's southern edge
	parts.append(_p(FREE + "ruins/ruin_arch_pillars", ruin, 7.0, 200.0, {"collide": true}))
	parts.append(_p(FREE + "ruins/ruin_wall_broken_a", ruin + Vector2(-12, 3), 3.2, 80.0))
	parts.append(_p(FREE + "ruins/ruin_wall_broken_b", ruin + Vector2(11, -2), 2.8, 270.0))
	parts.append(_p(FREE + "ruins/ruin_wall_corner", ruin + Vector2(-5, -11), 3.0, 30.0))
	parts.append(_p(FREE + "ruins/pillar_mossy_a", ruin + Vector2(18, 9), 4.0, 10.0, {"collide": true}))
	parts.append(_p(FREE + "ruins/pillar_mossy_b", ruin + Vector2(-19, 8), 3.4, 60.0, {"collide": true}))
	parts.append(_p(FREE + "props/altar_stone_slab", ruin + Vector2(0, -4), 1.1, 200.0, {"collide": true}))
	# The gazebo by the pond: someone sat here once
	parts.append(_p(FREE + "ruins/ruin_gazebo", gaze, 4.8, 250.0, {"collide": true}))
	# The Elder oaks: four hero trees around the meadow, one on the knoll
	var kn := knoll_world()
	parts.append(_p(FREE + "nature/tree_old_a", w(KNOLL.x + 6.0, KNOLL.y + 30.0), 27.0, 160.0, {"collide": true, "far": true}))
	parts.append(_p(FREE + "nature/tree_old_b", w(-60.0, 80.0), 24.0, 30.0, {"collide": true, "far": true}))
	parts.append(_p(FREE + "nature/tree_old_twisted", w(80.0, -10.0), 21.0, 200.0, {"collide": true, "far": true}))
	parts.append(_p(FREE + "nature/tree_old_rocks", w(-110.0, -60.0), 22.0, 75.0, {"collide": true, "far": true}))
	# The crystal spring at the foot of the falls
	var spring := w(-168.0, -14.0)
	parts.append(_p(FREE + "nature/rock_blue_crystal", spring, 1.8, 30.0, {"collide": true}))
	parts.append(_p(FREE + "magic/crystal_ice_shard", spring + Vector2(2.5, 1.5), 1.6, 10.0))
	parts.append(_p(FREE + "magic/crystal_ice_shard", spring + Vector2(-1.5, 3.0), 1.1, 70.0))
	parts.append(_p(FREE + "magic/crystal_ice_shard", spring + Vector2(0.5, -2.5), 0.9, 140.0))
	var scatter: Array = []
	scatter.append(_sc(REGION + "flowers_cool", stones, 28.0, 300, 0.0, 0.9, 1.5, 150.0))
	scatter.append(_sc(REGION + "flowers_warm", kn, 60.0, 420, 14.0, 0.9, 1.5, 150.0))
	scatter.append(_sc(REGION + "fern_a", ruin, 34.0, 200, 6.0, 0.8, 1.4, 110.0))
	scatter.append(_sc(REGION + "fern_b", spring, 22.0, 120, 3.0, 0.8, 1.4, 90.0))
	var lights: Array = []
	var falls_foot := w(-147.0, 10.0)
	var waterfalls: Array = [{"at": [falls_foot.x, falls_foot.y], "dir": [-OUT.x, -OUT.y], "width": 6.0, "pool_r": 8.0, "reach": 120.0, "over": 6, "pool_off": 5.0}]
	return {"id": "hidden_vale", "name": "The Hidden Vale", "kind": "hidden_vale", "pos": [CENTER.x, CENTER.y], "near": 400.0,
		"yaw": 0.0, "parts": parts, "scatter": scatter, "lights": lights, "waterfalls": waterfalls}


## The hidden mouth: a rockfall, fallen oaks and overgrowth across the slot, and the two moss pillars that frame the reveal.
static func _gorge_dressing() -> Dictionary:
	var m := gorge_world(GORGE_MOUTH - 10.0)
	var inner := gorge_world(GAP_PILLAR_U)
	var parts: Array = []
	# Rockfall across the mouth, leaving a gap a person can squeeze through
	for i in 6:
		var off := Vector2(OUT.x, OUT.y) * (i % 3) * 3.0 + PERP * (-9.0 + i * 3.6)
		var h := 4.0 + (i % 3) * 1.6
		parts.append(_p(FREE + "nature/rock_grey_plain" if i % 2 == 0 else FREE + "nature/rock_limestone_tall", m + off, h, i * 57.0, {"collide": true}))
	parts.append(_p("nature:log_mossy", m + PERP * 6.0 + OUT * 7.0, 1.6, 75.0, {"collide": true}))
	parts.append(_p("nature:log_branchy", m + PERP * -8.0 + OUT * 11.0, 1.6, 20.0, {"collide": true}))
	parts.append(_p(FREE + "nature/rock_limestone_tall", gorge_world(GORGE_MOUTH - 45.0) + PERP * 8.0, 9.0, 140.0, {"collide": true}))
	# The pillars that frame the first sight of the vale
	for s: float in [-1.0, 1.0]:
		var at := inner + PERP * s * (gorge_half_width(GAP_PILLAR_U) + 1.2)
		parts.append(_p(FREE + "ruins/pillar_mossy_a" if s < 0.0 else FREE + "ruins/pillar_mossy_b", at, 5.2, 90.0 + s * 20.0, {"collide": true}))
	var scatter: Array = []
	scatter.append(_sc(REGION + "bush_dark", m, 18.0, 70, 2.0, 1.1, 1.8, 140.0))
	scatter.append(_sc(REGION + "fern_a", m, 22.0, 170, 1.0, 1.1, 1.8, 120.0))
	scatter.append(_sc(REGION + "fern_b", gorge_world(GORGE_MOUTH - 60.0), 26.0, 140, 3.0, 1.0, 1.7, 120.0))
	scatter.append(_sc(REGION + "young_oak", m + OUT * 4.0, 16.0, 7, 4.0, 1.1, 1.7, 160.0))
	return {"id": "vale_gorge", "name": "The Gorge", "kind": "hidden_vale", "pos": [inner.x, inner.y], "near": 520.0,
		"yaw": 0.0, "parts": parts, "scatter": scatter, "lights": [], "waterfalls": []}


## The vale's unique resources, as interactable spots (handled by exploration_director.gd; harvest days are saved in
## Life.discovery as "res:<id>"). `days` = regrowth (0 = once). Positions are local (u, v) unless "at" is given.
const NODES := [
	{"id": "moon_a", "u": -40.0, "v": 95.0, "item": "moonpetal", "min": 2, "max": 3, "days": 8, "prompt": "Gather moonpetal"},
	{"id": "moon_b", "u": 62.0, "v": -98.0, "item": "moonpetal", "min": 2, "max": 3, "days": 8, "prompt": "Gather moonpetal"},
	{"id": "moon_c", "u": -132.0, "v": -44.0, "item": "moonpetal", "min": 1, "max": 3, "days": 8, "prompt": "Gather moonpetal"},
	{"id": "crystal", "u": -168.0, "v": -14.0, "item": "spring_crystal", "min": 1, "max": 2, "days": 6, "prompt": "Collect spring crystal"},
	{"id": "heart_a", "u": -88.0, "v": 78.0, "item": "heartwood", "min": 2, "max": 3, "days": 9, "prompt": "Split heartwood from the windfall"},
	{"id": "heart_b", "u": 92.0, "v": 34.0, "item": "heartwood", "min": 2, "max": 3, "days": 9, "prompt": "Split heartwood from the windfall"},
	{"id": "builders", "u": 38.0, "v": 104.0, "dx": 0.0, "dz": -4.0, "know": ["build:carpentry", "build:masonry"], "days": 0, "prompt": "Study the builders' carvings"},
]


static func nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _on:
		return out
	for n: Dictionary in NODES:
		var d := n.duplicate()
		d["pos"] = w(float(n["u"]), float(n["v"])) + Vector2(float(n.get("dx", 0.0)), float(n.get("dz", 0.0)))
		out.append(d)
	return out


static func _nodes_landmark() -> Dictionary:
	var parts: Array = []
	var scatter: Array = []
	var lights: Array = []
	for n: Dictionary in nodes():
		var at: Vector2 = n["pos"]
		match String(n["id"]).substr(0, 4):
			"moon":
				for i in 7:
					var a := TAU * i / 7.0
					parts.append(_p(FREE + "flora/bellflower_purple", at + Vector2(cos(a), sin(a)) * 2.4, 0.95, a * 57.3))
				parts.append(_p(FREE + "flora/mushrooms_blue_glow", at + Vector2(0.4, 0.6), 0.5, 20.0))
				scatter.append(_sc(REGION + "flowers_cool", at, 7.0, 90, 0.0, 0.9, 1.5, 80.0))
				lights.append({"w": [at.x, at.y], "y": 0.8, "color": "9cc8ff", "range": 6.0})
			"hear":
				parts.append(_p("nature:log_mossy", at, 2.3, 40.0 + at.x, {"collide": true}))
				parts.append(_p(FREE + "flora/stump_dead_tall", at + Vector2(4.0, 2.0), 2.4, at.y))
				scatter.append(_sc(REGION + "fern_b", at, 8.0, 40, 2.0))
	return {"id": "vale_nodes", "name": "Vale resources", "kind": "hidden_vale", "pos": [CENTER.x, CENTER.y], "near": 400.0,
		"yaw": 0.0, "parts": parts, "scatter": scatter, "lights": lights, "waterfalls": []}
