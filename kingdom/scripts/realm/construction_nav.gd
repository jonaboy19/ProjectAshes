extends RefCounted
## Walking routes for builders and haulers in the open world. Every site registers an oriented footprint
## as an obstacle; routes are A* over a coarse grid (water, steep ground and footprints are blocked,
## worn trails are cheaper) followed by line-of-sight smoothing. A settlement's own StreetGraph is used
## where the route runs inside one. Static helpers over a construction module (scripts/realm/construction.gd).

const CELL := 3.0
const MAX_CELLS := 9000
const PAD := 24.0
const STEEP := 0.9            # max rise per metre between neighbouring cells
const CLEAR_STEP := 1.2

const D := preload("res://scripts/realm/construction_data.gd")


## Obstacle box of a site: [centre, unit x axis, half extents].
static func box_of(site: Dictionary) -> Array:
	var p: Array = site["pos"]
	var yaw := float(site["yaw"])
	return [Vector2(p[0], p[1]), Vector2(cos(yaw), -sin(yaw)), D.half_size(String(site["kind"]))]


## Where people stand to use a building: in front of it, outside the footprint.
static func door_of(site: Dictionary) -> Vector2:
	var p: Array = site["pos"]
	var yaw := float(site["yaw"])
	var half := D.half_size(String(site["kind"]))
	return Vector2(p[0], p[1]) + Vector2(sin(yaw), cos(yaw)) * (half.y + 1.3)


static func in_box(box: Array, p: Vector2, r := 0.0) -> bool:
	var c: Vector2 = box[0]
	var ax: Vector2 = box[1]
	var h: Vector2 = box[2]
	var d := p - c
	var lx := d.dot(ax)
	# local z axis = (sin, cos) = (-ax.y, ax.x) for ax = (cos, -sin)
	var lz := d.dot(Vector2(-ax.y, ax.x))
	return absf(lx) <= h.x + r and absf(lz) <= h.y + r


static func boxes(mod: RefCounted, ignore_site := 0) -> Array:
	var out: Array = []
	for id: int in mod.sites:
		if id == ignore_site:
			continue
		var s: Dictionary = mod.sites[id]
		if String(s["kind"]) in ["gate", "campfire"]:
			continue
		out.append(box_of(s))
	return out


static func terrain_ok(p: Vector2) -> bool:
	return not WorldGen.is_water(p.x, p.y)


static func blocked(bxs: Array, p: Vector2, r := 0.6) -> bool:
	if not terrain_ok(p):
		return true
	for b: Array in bxs:
		var c: Vector2 = b[0]
		var reach: float = (b[2] as Vector2).length() + r
		if c.distance_squared_to(p) <= reach * reach and in_box(b, p, r):
			return true
	return false


static func clear_line(bxs: Array, a: Vector2, b: Vector2, r := 0.5) -> bool:
	var len := a.distance_to(b)
	var n := maxi(1, int(ceil(len / CLEAR_STEP)))
	var prev_h := WorldGen.height(a.x, a.y)
	for i in range(1, n + 1):
		var q := a.lerp(b, float(i) / n)
		if blocked(bxs, q, r):
			return false
		var h := WorldGen.height(q.x, q.y)
		if absf(h - prev_h) / maxf(len / n, 0.01) > STEEP * 1.15:
			return false
		prev_h = h
	return true


## Route from a to b (both included) or an empty array when there is no way through.
static func route(mod: RefCounted, a: Vector2, b: Vector2, ignore_site := 0) -> PackedVector2Array:
	var bxs := boxes(mod, ignore_site)
	if clear_line(bxs, a, b):
		return PackedVector2Array([a, b])
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(PAD, PAD)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(PAD, PAD)
	var cell := CELL
	while (hi.x - lo.x) / cell * ((hi.y - lo.y) / cell) > MAX_CELLS:
		cell *= 1.25
	var g := _Grid.new()
	g.lo = lo
	g.cell = cell
	g.w = int(ceil((hi.x - lo.x) / cell))
	g.h = int(ceil((hi.y - lo.y) / cell))
	g.state.resize(g.w * g.h)
	g.height.resize(g.w * g.h)
	g.height.fill(NAN)
	for bx: Array in bxs:
		var c: Vector2 = bx[0]
		var reach := (bx[2] as Vector2).length() + 1.5
		if c.x + reach < lo.x or c.x - reach > hi.x or c.y + reach < lo.y or c.y - reach > hi.y:
			continue
		var x0 := clampi(int((c.x - reach - lo.x) / cell), 0, g.w - 1)
		var x1 := clampi(int((c.x + reach - lo.x) / cell), 0, g.w - 1)
		var y0 := clampi(int((c.y - reach - lo.y) / cell), 0, g.h - 1)
		var y1 := clampi(int((c.y + reach - lo.y) / cell), 0, g.h - 1)
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var key := yy * g.w + xx
				if not g.boxes.has(key):
					g.boxes[key] = []
				(g.boxes[key] as Array).append(bx)
	var trails: Array = mod.trail_segments()
	var start := g.index_of(a)
	var goal := g.index_of(b)
	goal = _nearest_free(g, goal)
	if goal < 0:
		return PackedVector2Array()
	var cost_to := PackedFloat32Array()
	cost_to.resize(g.w * g.h)
	cost_to.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(g.w * g.h)
	prev.fill(-1)
	var heap: Array = []   # [f, idx]
	cost_to[start] = 0.0
	var goal_c := g.center(goal)
	_push(heap, [g.center(start).distance_to(goal_c), start])
	var expanded := 0
	var found := false
	while not heap.is_empty():
		var cur: int = _pop(heap)[1]
		if cur == goal:
			found = true
			break
		expanded += 1
		if expanded > MAX_CELLS * 2:
			break
		var cx := cur % g.w
		var cy := cur / g.w
		var cp := g.center(cur)
		var hcur := g.height_at(cur)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= g.w or ny >= g.h:
					continue
				var ni := ny * g.w + nx
				if g.is_blocked(ni) and ni != goal:
					continue
				if dx != 0 and dy != 0 and (g.is_blocked(ny * g.w + cx) or g.is_blocked(cy * g.w + nx)):
					continue   # no corner cutting
				var np := g.center(ni)
				var step := cp.distance_to(np)
				var rise := absf(g.height_at(ni) - hcur) / step
				if rise > STEEP:
					continue
				var cost := step * (1.0 + rise * 0.8) / (_trail_speed(trails, np) if not trails.is_empty() else 1.0)
				var ng: float = cost_to[cur] + cost
				if ng < cost_to[ni]:
					cost_to[ni] = ng
					prev[ni] = cur
					_push(heap, [ng + np.distance_to(goal_c), ni])
	if not found:
		return PackedVector2Array()
	var chain: Array[Vector2] = [b]
	var at := goal
	while at != start and at >= 0:
		chain.push_front(g.center(at))
		at = prev[at]
	chain.push_front(a)
	# Line-of-sight smoothing over the same grid.
	var out := PackedVector2Array([chain[0]])
	var i := 0
	while i < chain.size() - 1:
		var j := chain.size() - 1
		while j > i + 1 and not _line_free(g, chain[i], chain[j]):
			j -= 1
		out.append(chain[j])
		i = j
	return out


class _Grid extends RefCounted:
	var lo := Vector2.ZERO
	var cell := 3.0
	var w := 0
	var h := 0
	var state := PackedByteArray()        # 0 unknown, 1 free, 2 blocked
	var height := PackedFloat32Array()
	var boxes := {}                        # cell index -> Array of boxes

	func index_of(p: Vector2) -> int:
		return clampi(int((p.y - lo.y) / cell), 0, h - 1) * w + clampi(int((p.x - lo.x) / cell), 0, w - 1)

	func center(i: int) -> Vector2:
		return lo + Vector2((i % w) + 0.5, (i / w) + 0.5) * cell

	func is_blocked(i: int) -> bool:
		if state[i] == 0:
			var p := center(i)
			var bad := not terrain_free(p)
			if not bad and boxes.has(i):
				for bx: Array in boxes[i]:
					if in_box_static(bx, p, 0.9):
						bad = true
						break
			state[i] = 2 if bad else 1
		return state[i] == 2

	func height_at(i: int) -> float:
		if is_nan(height[i]):
			var p := center(i)
			height[i] = WorldGen.height(p.x, p.y)
		return height[i]

	static func terrain_free(p: Vector2) -> bool:
		return not WorldGen.is_water(p.x, p.y)

	static func in_box_static(bx: Array, p: Vector2, r: float) -> bool:
		var c: Vector2 = bx[0]
		var ax: Vector2 = bx[1]
		var hh: Vector2 = bx[2]
		var d := p - c
		return absf(d.dot(ax)) <= hh.x + r and absf(d.dot(Vector2(-ax.y, ax.x))) <= hh.y + r


static func _line_free(g: _Grid, a: Vector2, b: Vector2) -> bool:
	var len := a.distance_to(b)
	var n := maxi(1, int(ceil(len / (g.cell * 0.5))))
	var prev_i := -1
	var prev_h := NAN
	for k in range(0, n + 1):
		var q := a.lerp(b, float(k) / n)
		var qi := g.index_of(q)
		if qi != prev_i:
			if g.is_blocked(qi):
				return false
			var hq := g.height_at(qi)
			if not is_nan(prev_h) and absf(hq - prev_h) / g.cell > STEEP:
				return false
			prev_h = hq
			prev_i = qi
	return true


static func reachable(mod: RefCounted, a: Vector2, b: Vector2, ignore_site := 0) -> bool:
	return route(mod, a, b, ignore_site).size() >= 2


static func length(path: PackedVector2Array) -> float:
	var t := 0.0
	for i in range(path.size() - 1):
		t += path[i].distance_to(path[i + 1])
	return t


static func _trail_speed(trails: Array, p: Vector2) -> float:
	var best := 1.0
	for t: Array in trails:
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var ab := b - a
		var l2 := ab.length_squared()
		var k := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		if a.lerp(b, k).distance_squared_to(p) < 4.0:
			best = maxf(best, float(t[2]))
	return best


static func _nearest_free(g: _Grid, idx: int) -> int:
	var cx := idx % g.w
	var cy := idx / g.w
	for r in range(0, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= g.w or ny >= g.h:
					continue
				var ni := ny * g.w + nx
				if not g.is_blocked(ni):
					return ni
	return -1


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float((heap[p] as Array)[0]) <= float((heap[i] as Array)[0]):
			break
		var t: Array = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and float((heap[l] as Array)[0]) < float((heap[m] as Array)[0]):
				m = l
			if r < n and float((heap[r] as Array)[0]) < float((heap[m] as Array)[0]):
				m = r
			if m == i:
				break
			var t: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top
