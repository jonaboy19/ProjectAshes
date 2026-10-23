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


## The nearest `max_n` living rows with r0 <= d < r1, nearest first. Visits cells by Chebyshev ring around p and stops once
## `max_n` rows are certainly the nearest (everything left lies at least `ring * CELL` away).
func rows_in_ring(p: Vector2, r0: float, r1: float, max_n: int, settlements: Array, health: PackedByteArray,
		pos: PackedVector2Array) -> PackedInt32Array:
	var near_sids: Array[int] = []
	for s: Dictionary in settlements:
		if p.distance_to(s["pos"]) <= r1 + float(s["radius"]) * 2.0 and not grids[int(s["id"])].is_empty():
			near_sids.append(int(s["id"]))
	var ids := PackedInt32Array()
	var d2 := PackedFloat32Array()
	if near_sids.is_empty() or max_n <= 0:
		return ids
	var lo2 := r0 * r0
	var hi2 := r1 * r1
	var pcx := int(floorf(p.x * INV_CELL))
	var pcy := int(floorf(p.y * INV_CELL))
	var max_ring := int(ceilf(r1 * INV_CELL)) + 1
	for ring in range(0, max_ring + 1):
		# Everything in rings < `ring` is already collected; a row in ring >= `ring` is at least (ring - 1) * CELL away.
		if ids.size() >= max_n:
			var guaranteed := 0
			var safe := float(maxi(ring - 1, 0)) * CELL
			var safe2 := safe * safe
			for d in d2:
				if d <= safe2:
					guaranteed += 1
			if guaranteed >= max_n:
				break
		for sid in near_sids:
			var g: Dictionary = grids[sid]
			if ring == 0:
				_ring_cell(g, pcx, pcy, p, lo2, hi2, health, pos, ids, d2)
				continue
			for dx in range(-ring, ring + 1):
				_ring_cell(g, pcx + dx, pcy - ring, p, lo2, hi2, health, pos, ids, d2)
				_ring_cell(g, pcx + dx, pcy + ring, p, lo2, hi2, health, pos, ids, d2)
			for dy in range(-ring + 1, ring):
				_ring_cell(g, pcx - ring, pcy + dy, p, lo2, hi2, health, pos, ids, d2)
				_ring_cell(g, pcx + ring, pcy + dy, p, lo2, hi2, health, pos, ids, d2)
	# Order the (at most a couple of rings' worth of) candidates nearest first and cut to max_n.
	var n := ids.size()
	var order := range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		return d2[a] < d2[b] or (d2[a] == d2[b] and ids[a] < ids[b]))
	var out := PackedInt32Array()
	for k in mini(n, max_n):
		out.append(ids[order[k]])
	return out


func _ring_cell(g: Dictionary, cx: int, cy: int, p: Vector2, lo2: float, hi2: float, health: PackedByteArray,
		pos: PackedVector2Array, ids: PackedInt32Array, d2: PackedFloat32Array) -> void:
	var k := (cx + BIAS) * STRIDE + (cy + BIAS)
	if g.has(k) and _cell_min_d2(p, cx, cy) < hi2:
		_take_cell(g[k], p, lo2, hi2, health, pos, ids, d2)
