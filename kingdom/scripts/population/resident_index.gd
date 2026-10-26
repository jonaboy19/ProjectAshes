extends RefCounted
## Spatial index over WorldSim's resident rows: a 16 m cell grid per settlement. Each cell holds the rows standing in it
## (PackedInt32Array); `cell_of[row]` is the cell key a row is filed under. WorldSim owns one instance and calls `move()` whenever
## a row's position changes (only the cell change costs anything). Dead rows stay filed by position; callers filter by health,
## exactly as the old full scan did, so results are identical to the scan.
##
## Queries visit cells instead of every resident of every settlement in range:
##   rows_in_circle()  : all rows with r0^2 <= d^2 < r1^2 (parity with the old WorldSim.people_near)
##   rows_in_ring()    : the nearest `max_n` of those, nearest first, visiting cells ring by ring and stopping early.

const CELL := 16.0
const INV_CELL := 1.0 / CELL
const BIAS := 4096
const STRIDE := 8192

var cell_of := PackedInt32Array()          # row -> cell key (home settlement's grid)
var grids: Array[Dictionary] = []          # settlement id -> { cell key: PackedInt32Array of rows }


static func key_of(p: Vector2) -> int:
	return (int(floorf(p.x * INV_CELL)) + BIAS) * STRIDE + (int(floorf(p.y * INV_CELL)) + BIAS)


func clear(settlements: int) -> void:
	cell_of = PackedInt32Array()
	grids.clear()
	for _s in settlements:
		grids.append({})


func add(row: int, sid: int, p: Vector2) -> void:
	var k := key_of(p)
	if row >= cell_of.size():
		cell_of.resize(row + 1)
	cell_of[row] = k
	_file(grids[sid], k, row)


## Packed arrays have value semantics: read the cell, change it, store it back.
static func _file(g: Dictionary, k: int, row: int) -> void:
	var a: PackedInt32Array = g.get(k, PackedInt32Array())
	a.append(row)
	g[k] = a


## The row moved to `p`: re-file it only when the cell changed.
func move(row: int, sid: int, p: Vector2) -> void:
	var k := key_of(p)
	var old := cell_of[row]
	if k == old:
		return
	var g: Dictionary = grids[sid]
	var from: PackedInt32Array = g.get(old, PackedInt32Array())
	var at := from.find(row)
	if at >= 0:
		from[at] = from[from.size() - 1]
		from.resize(from.size() - 1)
		if from.is_empty():
			g.erase(old)
		else:
			g[old] = from
	_file(g, k, row)
	cell_of[row] = k


## Squared distance from p to the nearest point of the cell (cx, cy).
static func _cell_min_d2(p: Vector2, cx: int, cy: int) -> float:
	var x0 := float(cx) * CELL
	var y0 := float(cy) * CELL
	var dx := maxf(maxf(x0 - p.x, p.x - (x0 + CELL)), 0.0)
	var dy := maxf(maxf(y0 - p.y, p.y - (y0 + CELL)), 0.0)
	return dx * dx + dy * dy


## Every living row of settlement `sid` with r0^2 <= d^2 < r1^2 (unordered), appended to out_ids / out_d2.
func _collect_box(sid: int, p: Vector2, r0: float, r1: float, health: PackedByteArray, pos: PackedVector2Array,
		out_ids: PackedInt32Array, out_d2: PackedFloat32Array) -> void:
	var g: Dictionary = grids[sid]
	if g.is_empty():
		return
	var lo2 := r0 * r0
	var hi2 := r1 * r1
	var cx0 := int(floorf((p.x - r1) * INV_CELL))
	var cx1 := int(floorf((p.x + r1) * INV_CELL))
	var cy0 := int(floorf((p.y - r1) * INV_CELL))
	var cy1 := int(floorf((p.y + r1) * INV_CELL))
	# A sparse grid with fewer cells than the box: walk the cells themselves.
	if g.size() < (cx1 - cx0 + 1) * (cy1 - cy0 + 1):
		for k: int in g:
			var cx := k / STRIDE - BIAS
			var cy := k % STRIDE - BIAS
			if cx < cx0 or cx > cx1 or cy < cy0 or cy > cy1 or _cell_min_d2(p, cx, cy) >= hi2:
				continue
			_take_cell(g[k], p, lo2, hi2, health, pos, out_ids, out_d2)
		return
	for cx in range(cx0, cx1 + 1):
		var kx := (cx + BIAS) * STRIDE + BIAS
		for cy in range(cy0, cy1 + 1):
			var k := kx + cy
			if g.has(k):
				if _cell_min_d2(p, cx, cy) >= hi2:
					continue
				_take_cell(g[k], p, lo2, hi2, health, pos, out_ids, out_d2)


static func _take_cell(rows: PackedInt32Array, p: Vector2, lo2: float, hi2: float, health: PackedByteArray,
		pos: PackedVector2Array, out_ids: PackedInt32Array, out_d2: PackedFloat32Array) -> void:
	for r in rows:
		if health[r] == 0:
			continue
		var d2 := pos[r].distance_squared_to(p)
		if d2 >= lo2 and d2 < hi2:
			out_ids.append(r)
			out_d2.append(d2)


## Drop-in for the old scan: all living rows with d < radius of every settlement within `radius + 2 * settlement radius`,
## in ascending row order (the old order within a settlement; settlements are contiguous ascending ranges).
func rows_in_circle(p: Vector2, radius: float, settlements: Array, health: PackedByteArray, pos: PackedVector2Array) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var d2 := PackedFloat32Array()
	for s: Dictionary in settlements:
		if p.distance_to(s["pos"]) > radius + float(s["radius"]) * 2.0:
			continue
		_collect_box(int(s["id"]), p, 0.0, radius, health, pos, ids, d2)
	ids.sort()
	return ids


## The nearest `max_n` living rows with r0 <= d < r1, nearest first. Occupied cells are bucketed by Chebyshev ring around p and
## visited ring by ring; it stops once the max_n-th nearest found is certainly nearer than anything in the rings left
## (they lie at least `ring * CELL` away). The few candidates are ordered with a native sort of packed (distance, row) keys.
func rows_in_ring(p: Vector2, r0: float, r1: float, max_n: int, settlements: Array, health: PackedByteArray,
		pos: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if max_n <= 0:
		return out
	var lo2 := r0 * r0
	var hi2 := r1 * r1
	var pcx := int(floorf(p.x * INV_CELL))
	var pcy := int(floorf(p.y * INV_CELL))
	var max_ring := int(ceilf(r1 * INV_CELL)) + 1
	var buckets: Array = []
	buckets.resize(max_ring + 1)
	for k in max_ring + 1:
		buckets[k] = []
	var any := false
	for s: Dictionary in settlements:
		var sid := int(s["id"])
		if p.distance_to(s["pos"]) > r1 + float(s["radius"]) * 2.0:
			continue
		var g: Dictionary = grids[sid]
		for key: int in g:
			var cx := key / STRIDE - BIAS
			var cy := key % STRIDE - BIAS
			var ring := maxi(absi(cx - pcx), absi(cy - pcy))
			if ring > max_ring:
				continue
			if _cell_min_d2(p, cx, cy) >= hi2:
				continue
			(buckets[ring] as Array).append(g[key])      # the cell's rows (PackedInt32Array) itself
			any = true
	if not any:
		return out
	var ids := PackedInt32Array()
	var d2 := PackedFloat32Array()
	for ring in max_ring + 1:
		for rows: PackedInt32Array in buckets[ring]:
			_take_cell(rows, p, lo2, hi2, health, pos, ids, d2)
		if ids.size() >= max_n:
			var probe := d2.duplicate()
			probe.sort()
			var safe := float(ring) * CELL
			if probe[max_n - 1] <= safe * safe:
				break
	var n := ids.size()
	var keys := PackedFloat64Array()
	keys.resize(n)
	for k in n:
		keys[k] = floorf(d2[k] * 4096.0) * 131072.0 + float(ids[k])
	keys.sort()
	for k in mini(n, max_n):
		out.append(int(fposmod(keys[k], 131072.0)))
	return out
