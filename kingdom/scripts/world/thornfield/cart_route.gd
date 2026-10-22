extends RefCounted
## The grain cart's way from the tithe barn to the mill (hub.gd cart_route). The barn and the mill are ~280 m apart across open
## farmland with no road between them (the kingdom road passes the barn's side, the town road is far from the mill), so the
## route is planned on a grid (AStarGrid2D) over the ground between them:
##   solid     every tree, rock, bush, stump and log the terrain streamer places there (TerrainStreamer._plan_forest, the same
##             deterministic plan the world draws), the sites and towns in the way, water and steep ground, each grown by
##             the corridor half-width so the cart never brushes anything and the player can walk beside it
##   cheaper   cells on a road or a street (the cart prefers a lane to a field)
## then the cell path is string-pulled to a few waypoints. If the corridor is too tight the half-width shrinks, and in the
## worst case the straight line is returned. Computed once per world (cached by endpoints).
## No class_name; preload and call statics.

const CELL := 3.0
const PAD := 70.0
## Metres from the route's centreline that stay clear: half the cart (1 m) plus room for the player to walk beside it.
const HALF_WIDTH := 3.2
const FALLBACK_WIDTHS := [3.2, 2.4, 1.6]
const MAX_GRADE := 0.45                 # rise over run of one cell step that is too steep for a cart
const OBSTACLE_R := {"tree": 1.1, "rock": 1.6, "bush": 0.8, "log": 1.2}
const SITE_R := 10.0                    # waystones, roadside caravans and the like: their parts spread this far
const BUILDING_R := {"brewhouse": 9.0, "windmill": 4.2, "farm_barn": 8.0, "pig_sty": 4.5, "coop": 4.0}
const SKIP_NEAR_ENDPOINT := 7.0

const Sites := preload("res://scripts/world/thornfield/sites.gd")

static var _cache: Dictionary = {}
static var _tasks: Dictionary = {}       # key -> WorkerThreadPool task id of a plan still running
static var _lock := Mutex.new()


static func _key(a: Vector2, b: Vector2) -> String:
	return "%s|%s" % [a, b]


## Waypoints (world XZ) from `a` to `b`, `a` and `b` included. Cached; `force` replans. Waits for a prewarm that is still running.
static func plan(a: Vector2, b: Vector2, force := false) -> PackedVector2Array:
	var key := _key(a, b)
	_lock.lock()
	var task: Variant = _tasks.get(key)
	_lock.unlock()
	if task != null:
		WorkerThreadPool.wait_for_task_completion(int(task))
		_lock.lock()
		_tasks.erase(key)
		_lock.unlock()
	if not force and _cache.has(key):
		return _cache[key]
	var route := compute(a, b)
	_lock.lock()
	_cache[key] = route
	_lock.unlock()
	return route


## Starts planning on a worker thread (the sampling takes about a second): the hub calls this when it is built, long before
## the cart quest, so the main thread never stalls on it.
static func prewarm(a: Vector2, b: Vector2) -> void:
	var key := _key(a, b)
	_lock.lock()
	var busy := _tasks.has(key) or _cache.has(key)
	if not busy:
		_tasks[key] = WorkerThreadPool.add_task(func() -> void:
			var r := compute(a, b)
			_lock.lock()
			_cache[key] = r
			_lock.unlock())
	_lock.unlock()


static func is_ready(a: Vector2, b: Vector2) -> bool:
	return _cache.has(_key(a, b))


## The uncached plan.
static func compute(a: Vector2, b: Vector2) -> PackedVector2Array:
	var route := PackedVector2Array([a, b])
	var obstacles := obstacles_between(a, b)
	for w: float in FALLBACK_WIDTHS:
		var r := _search(a, b, obstacles, w)
		if not r.is_empty():
			route = r
			break
	return route


static func clear_cache() -> void:
	_cache.clear()


## Every blocking thing near the way: [[Vector2 centre, float radius, String what]]. Public for tests and tools.
static func obstacles_between(a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(PAD, PAD)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(PAD, PAD)
	var ts := TerrainStreamer.new()
	var chunk := TerrainStreamer.CHUNK
	for cx in range(floori(lo.x / chunk), floori(hi.x / chunk) + 1):
		for cz in range(floori(lo.y / chunk), floori(hi.y / chunk) + 1):
			var buckets: Dictionary = ts.call("_plan_forest", Vector2i(cx, cz), Vector2(cx, cz) * chunk)
			for kind: String in buckets:
				var what := _what_is(kind)
				if what == "":
					continue
				var r: float = OBSTACLE_R[what]
				for t: Transform3D in buckets[kind]:
					var p := Vector2(t.origin.x, t.origin.z)
					if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
						out.append([p, r * t.basis.get_scale().x, what])
	ts.free()
	for s in WorldGen.sites:
		var p: Vector2 = s["pos"]
		if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
			continue
		if String(s["name"]) == "Thornfield Brewery" or String(s["name"]) == Sites.FARM_NAME:
			continue
		out.append([p, SITE_R, "site"])
	var b0 := Sites.brewery()
	if not b0.is_empty():
		out.append([Sites.to_world(b0, Sites.BREWHOUSE_AT), BUILDING_R["brewhouse"], "building"])
	var f0 := Sites.farm()
	if not f0.is_empty():
		out.append([Sites.to_world(f0, Sites.WINDMILL_AT), BUILDING_R["windmill"], "building"])
		out.append([Sites.to_world(f0, Sites.FARM_BARN_AT), BUILDING_R["farm_barn"], "building"])
		out.append([Sites.to_world(f0, Sites.PIG_STY_AT), BUILDING_R["pig_sty"], "building"])
		out.append([Sites.to_world(f0, Sites.COOP_AT), BUILDING_R["coop"], "building"])
	for st in WorldGen.settlements:
		var p2: Vector2 = st["pos"]
		var rr := float(st["radius"]) + 4.0
		if p2.x + rr >= lo.x and p2.x - rr <= hi.x and p2.y + rr >= lo.y and p2.y - rr <= hi.y:
			out.append([p2, rr, "town"])
	return out


## "tree" | "rock" | "bush" | "log" for a streamer kind, "" for what a cart drives over (ferns, grass, flowers, mushrooms).
static func _what_is(kind: String) -> String:
	var n := kind.get_file()
	if n in ["dead_snag", "young_oak", "spruce_a", "pine_scots", "oak_a", "oak_b", "beech_a"]:
		return "tree"
	if n.begins_with("rock") or n.begins_with("boulder"):
		return "rock"
	if n.begins_with("bush"):
		return "bush"
	if n.begins_with("stump") or n.begins_with("log"):
		return "log"
	return ""


## Minimum distance from `p` to any obstacle edge (negative inside one): the clearance of a route point.
static func clearance_at(p: Vector2, obstacles: Array) -> float:
	var best := INF
	for o: Array in obstacles:
		best = minf(best, p.distance_to(o[0]) - float(o[1]))
	return best


static func _search(a: Vector2, b: Vector2, obstacles: Array, half_width: float) -> PackedVector2Array:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(PAD, PAD)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(PAD, PAD)
	var size := Vector2i(ceili((hi.x - lo.x) / CELL), ceili((hi.y - lo.y) / CELL))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	grid.update()
	# Terrain: water, steep ground, roads.
	for y in size.y:
		for x in size.x:
			var c := lo + (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL
			var steep := absf(WorldGen.height(c.x + CELL, c.y) - WorldGen.height(c.x - CELL, c.y)) / (2.0 * CELL) > MAX_GRADE \
				or absf(WorldGen.height(c.x, c.y + CELL) - WorldGen.height(c.x, c.y - CELL)) / (2.0 * CELL) > MAX_GRADE
			if steep or WorldGen.near_water(c.x, c.y, half_width):
				grid.set_point_solid(Vector2i(x, y), true)
			elif WorldGen.road_distance(c.x, c.y) < 3.0 or WorldGen.street_distance(c.x, c.y) < 2.5:
				grid.set_point_weight_scale(Vector2i(x, y), 0.6)       # a lane is cheaper than a field
	for o: Array in obstacles:
		var pc: Vector2 = o[0]
		var reach := float(o[1]) + half_width + CELL * 0.35      # the margin covers a line cutting a cell corner
		var x0 := maxi(0, floori((pc.x - reach - lo.x) / CELL))
		var x1 := mini(size.x - 1, floori((pc.x + reach - lo.x) / CELL))
		var y0 := maxi(0, floori((pc.y - reach - lo.y) / CELL))
		var y1 := mini(size.y - 1, floori((pc.y + reach - lo.y) / CELL))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var c := lo + (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL
				if c.distance_to(pc) <= reach:
					grid.set_point_solid(Vector2i(x, y), true)
	var ia := _cell_of(a, lo, size)
	var ib := _cell_of(b, lo, size)
	_open_around(grid, ia, size)
	_open_around(grid, ib, size)
	var ids := grid.get_id_path(ia, ib)
	if ids.size() < 2:
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for id: Vector2i in ids:
		pts.append(lo + (Vector2(id) + Vector2(0.5, 0.5)) * CELL)
	pts[0] = a
	pts[pts.size() - 1] = b
	return _pull(pts, grid, lo, size)


static func _cell_of(p: Vector2, lo: Vector2, size: Vector2i) -> Vector2i:
	return Vector2i(clampi(floori((p.x - lo.x) / CELL), 0, size.x - 1), clampi(floori((p.y - lo.y) / CELL), 0, size.y - 1))


## The yard around an endpoint is walkable (the door itself sits next to a building the grid grows over).
static func _open_around(grid: AStarGrid2D, c: Vector2i, size: Vector2i) -> void:
	var r := ceili(SKIP_NEAR_ENDPOINT / CELL)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and Vector2(dx, dy).length() <= r:
				grid.set_point_solid(q, false)


## String pulling: from each point jump to the farthest later one the straight line to which crosses no solid cell.
static func _pull(pts: PackedVector2Array, grid: AStarGrid2D, lo: Vector2, size: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _line_clear(pts[i], pts[j], grid, lo, size):
			j -= 1
		out.append(pts[j])
		i = j
	return out


static func _line_clear(p: Vector2, q: Vector2, grid: AStarGrid2D, lo: Vector2, size: Vector2i) -> bool:
	var n := maxi(1, ceili(p.distance_to(q) / (CELL * 0.5)))
	for k in n + 1:
		var c := _cell_of(p.lerp(q, float(k) / n), lo, size)
		if grid.is_point_solid(c):
			return false
	return true
