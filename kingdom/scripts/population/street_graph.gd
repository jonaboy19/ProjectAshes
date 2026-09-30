extends RefCounted
## Walkable street network and building footprints of one settlement, built
## lazily from its CityPlanner layout (streets, door paths, lots, landmarks).
##
## Near villagers route along it instead of walking the straight line from
## WorldSim's position to its target, which crossed a building footprint in
## 203 of 318 audited Ashford trips (docs/concepts/NPC_ROUTE_AUDIT.md). The
## footprints mirror SettlementBuilder's lot colliders (92% of the fitted mesh
## bounds, oriented by lot yaw), so a route that clears them clears the walls
## the player collides with.
##
## Cheap by construction: footprints live in a coarse grid, the graph is built
## once per settlement on first use, and routes are only planned when a near
## villager's goal changes (a few per second at most, see take_route_budget()).

const CELL := 12.0
## Clearance kept from footprints when routing (capsule radius plus margin).
const AGENT_RADIUS := 0.4
## Merge distance for graph nodes that land on the same junction.
const MERGE := 0.6
## A street end this close to another street joins it (T-junctions, lanes
## meeting the ring street's chords).
const JOIN := 2.0
## Half width of a wall gate opening, in metres along the wall.
const GATE_HALF := 3.2
const MAX_ROUTES_PER_FRAME := 2

static var _cache := {}             # settlement id -> graph
static var _budget_frame := -1
static var _budget_used := 0

## Settlement centre and plan.
var center := Vector2.ZERO
var radius := 0.0
var plan: Dictionary = {}
## Front-door approach of the inn (Vector2.INF when the settlement has none).
var inn_door := Vector2.INF
var inn_facing := Vector2.ZERO
## True when the last route() had to stop short of its goal.
var last_route_partial := false

# Footprints: oriented boxes (centre, unit local x axis, half extents).
var _box_c := PackedVector2Array()
var _box_ax := PackedVector2Array()
var _box_h := PackedVector2Array()
var _box_grid := {}                 # Vector2i -> PackedInt32Array
var _stamp := PackedInt32Array()
var _stamp_id := 0
var _nav_obstacle_count := -1
# Walls: [radius, gate angles].
var _walls: Array = []

# Graph.
var _graph_built := false
var _nodes := PackedVector2Array()
var _adj: Array[PackedInt32Array] = []
var _edges := PackedInt32Array()    # pairs of node indices
var _edge_grid := {}                # Vector2i -> PackedInt32Array of edge ids
var _node_lookup := {}              # Vector2i -> PackedInt32Array of node ids


## Graph of settlement `id` (built on first use), or null without a plan.
static func for_settlement(id: int) -> RefCounted:
	if _cache.has(id):
		return _cache[id]
	if id < 0 or id >= WorldGen.settlements.size():
		return null
	var s: Dictionary = WorldGen.settlements[id]
	if not s.has("plan"):
		return null
	var g: RefCounted = new()
	g._setup(s)
	_cache[id] = g
	return g


## Graph of the settlement a WorldSim person lives in.
static func for_person(i: int) -> RefCounted:
	if i < 0 or i >= WorldSim.home.size():
		return null
	return for_settlement(WorldSim.home[i])


## Route planning is spread over frames: true while this physics frame still
## has budget. A villager that is refused keeps its old path and asks again.
static func take_route_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	if _budget_used >= MAX_ROUTES_PER_FRAME:
		return false
	_budget_used += 1
	return true


# ------------------------------------------------------------------ footprints
func _setup(s: Dictionary) -> void:
	center = s["pos"]
	radius = s["radius"]
	plan = s["plan"]
	var low := SettlementBuilder._low()
	for lot: Dictionary in plan.get("lots", []):
		var asset: String = lot["asset"]
		var size := _mesh_size(asset, low)
		var half := Vector2(size.x, size.z) * 0.46
		var yaw: float = lot["yaw"]
		_add_box(lot["pos"], yaw, half)
		if asset == "inn" and inn_door == Vector2.INF:
			inn_facing = Vector2(sin(yaw), cos(yaw))
			inn_door = (lot["pos"] as Vector2) + inn_facing * (half.y + 1.6)
	for lm: Dictionary in plan.get("landmarks", []):
		var size := _mesh_size(lm["asset"], false)
		_add_box(lm["pos"], lm["yaw"], Vector2(size.x, size.z) * 0.46)
	# Market stalls ring the plaza (same layout as SettlementBuilder).
	var pr: float = plan.get("plaza_r", 12.0)
	var n_stalls := 6 if s["kind"] == "village" else 12
	for i in n_stalls:
		var ang := TAU * i / n_stalls + 0.2
		_add_box(center + Vector2(cos(ang), sin(ang)) * (pr - 3.0), atan2(-cos(ang), -sin(ang)), Vector2(1.4, 1.1))
	if plan.get("walls", false):
		_walls.append([float(plan["wall_radius"]), plan["gates"]])
	if float(plan.get("inner_wall", 0.0)) > 0.0:
		_walls.append([float(plan["inner_wall"]), [plan["gates"][0]]])
	_stamp.resize(_box_c.size())
	_sync_nav_obstacles()


func _mesh_size(asset: String, low: bool) -> Vector3:
	if not Assets.BUILDINGS.has(asset):
		return Vector3(8, 8, 8)
	var lod_low := low and Assets.building_lod2_distance(asset) > 0.0
	var mesh: Mesh = Assets.building_lod_mesh(asset) if lod_low else Assets.building_mesh(asset)
	return mesh.get_aabb().size if mesh else Vector3(8, 8, 8)


func _add_box(c: Vector2, yaw: float, half: Vector2) -> void:
	var k := _box_c.size()
	_box_c.append(c)
	_box_ax.append(Vector2(cos(yaw), -sin(yaw)))
	_box_h.append(half)
	var reach := half.length() + 1.5
	for cell in _cells(c - Vector2(reach, reach), c + Vector2(reach, reach)):
		_push(_box_grid, cell, k)


## Appends value to the packed int list stored under key (a cast-and-append on
## a dictionary value would only change a temporary copy).
static func _push(store: Dictionary, key: Vector2i, value: int) -> void:
	var list: PackedInt32Array = store.get(key, PackedInt32Array())
	list.append(value)
	store[key] = list


func _cells(lo: Vector2, hi: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for y in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			out.append(Vector2i(x, y))
	return out


## Box indices near the rectangle lo..hi, each listed once.
func _boxes_near(lo: Vector2, hi: Vector2) -> PackedInt32Array:
	if lo == hi:
		# Point query: one cell, whose list has no repeats.
		return _box_grid.get(Vector2i(floori(lo.x / CELL), floori(lo.y / CELL)), PackedInt32Array())
	_stamp_id += 1
	var out := PackedInt32Array()
	for cell in _cells(lo, hi):
		if not _box_grid.has(cell):
			continue
		for k: int in _box_grid[cell]:
			if _stamp[k] != _stamp_id:
				_stamp[k] = _stamp_id
				out.append(k)
	return out


func _local(p: Vector2, k: int) -> Vector2:
	var d := p - _box_c[k]
	var ax := _box_ax[k]
	return Vector2(d.dot(ax), d.x * -ax.y + d.y * ax.x)


func _world_dir(local_dir: Vector2, k: int) -> Vector2:
	var ax := _box_ax[k]
	return ax * local_dir.x + Vector2(-ax.y, ax.x) * local_dir.y


## True if p (with clearance r) is inside a building footprint.
func inside(p: Vector2, r := AGENT_RADIUS) -> bool:
	_sync_nav_obstacles()
	for k in _boxes_near(p, p):
		var l := _local(p, k)
		var h := _box_h[k] + Vector2(r, r)
		if absf(l.x) < h.x and absf(l.y) < h.y:
			return true
	return false


## Nearest point to p that is outside every footprint by at least r.
func push_out(p: Vector2, r := AGENT_RADIUS) -> Vector2:
	_sync_nav_obstacles()
	var q := p
	for _pass in 3:
		var moved := false
		for k in _boxes_near(q, q):
			var l := _local(q, k)
			var h := _box_h[k] + Vector2(r, r)
			if absf(l.x) >= h.x or absf(l.y) >= h.y:
				continue
			# Leave along the axis of least penetration.
			var out_local := Vector2.ZERO
			if h.x - absf(l.x) < h.y - absf(l.y):
				out_local.x = (h.x + 0.02) * signf(l.x if l.x != 0.0 else 1.0) - l.x
			else:
				out_local.y = (h.y + 0.02) * signf(l.y if l.y != 0.0 else 1.0) - l.y
			q += _world_dir(out_local, k)
			moved = true
		if not moved:
			return q
	# Wedged between overlapping footprints: nearest free spot on growing rings.
	for dist: float in [1.0, 2.0, 3.5, 5.0, 7.0]:
		for k in 16:
			var c := q + Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * dist
			if not inside(c, r):
				return c
	return q


## Steering push away from footprints closer than `reach` (zero in the open).
func repulse(p: Vector2, reach := 1.2) -> Vector2:
	_sync_nav_obstacles()
	var push := Vector2.ZERO
	var e := Vector2(reach, reach)
	for k in _boxes_near(p - e, p + e):
		var l := _local(p, k)
		var h := _box_h[k]
		var closest := Vector2(clampf(l.x, -h.x, h.x), clampf(l.y, -h.y, h.y))
		var away := l - closest
		var d := away.length()
		if d >= reach:
			continue
		if d < 0.001:
			away = Vector2(signf(l.x), 0.0) if h.x - absf(l.x) < h.y - absf(l.y) else Vector2(0.0, signf(l.y))
			d = 0.0
		else:
			away /= d
		push += _world_dir(away, k) * (1.0 - d / reach)
	return push.limit_length(1.5)


## True if an agent of radius r can walk the straight segment a -> b without
## entering a footprint or crossing a settlement wall outside its gates.
func clear_line(a: Vector2, b: Vector2, r := AGENT_RADIUS) -> bool:
	_sync_nav_obstacles()
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)
	for k in _boxes_near(lo, hi):
		if _segment_hits_box(a, b, k, r):
			return false
	for w: Array in _walls:
		if _segment_hits_wall(a, b, w[0], w[1], r):
			return false
	return true


## SettlementBuilder adds actual solid cart placements to its shared plan after
## creating the plaza clutter. Sync them lazily so this graph still works if it
## was cached before that build completed.
func _sync_nav_obstacles() -> void:
	var obstacles: Array = plan.get("npc_nav_obstacles", [])
	if obstacles.size() == _nav_obstacle_count:
		return
	_nav_obstacle_count = obstacles.size()
	for record: Array in obstacles:
		if record.size() < 3:
			continue
		var center_point: Vector2 = record[0]
		var half_extent: Vector2 = record[2]
		_add_box(center_point, float(record[1]), half_extent)
	_stamp.resize(_box_c.size())
	if _graph_built:
		_graph_built = false
		_nodes.clear()
		_adj.clear()
		_edges.clear()
		_edge_grid.clear()
		_node_lookup.clear()


func _segment_hits_box(a: Vector2, b: Vector2, k: int, r: float) -> bool:
	var p0 := _local(a, k)
	var p1 := _local(b, k)
	var h := _box_h[k] + Vector2(r, r)
	var d := p1 - p0
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p := p0[axis]
		var dd := d[axis]
		var hh := h[axis]
		if absf(dd) < 0.000001:
			if absf(p) > hh:
				return false
			continue
		var ta := (-hh - p) / dd
		var tb := (hh - p) / dd
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


func _segment_hits_wall(a: Vector2, b: Vector2, wall_r: float, gates: Array, r: float) -> bool:
	var d := b - a
	var f := a - center
	var qa := d.dot(d)
	if qa < 0.000001:
		return false
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - wall_r * wall_r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return false
	var sq := sqrt(disc)
	for t: float in [(-qb - sq) / (2.0 * qa), (-qb + sq) / (2.0 * qa)]:
		if t < 0.0 or t > 1.0:
			continue
		var q := a + d * t - center
		var ang := atan2(q.y, q.x)
		var in_gate := false
		for g: float in gates:
			if absf(wrapf(ang - g, -PI, PI)) * wall_r < GATE_HALF - r:
				in_gate = true
				break
		if not in_gate:
			return true
	return false


# ----------------------------------------------------------------------- graph
func _ensure_graph() -> void:
	if _graph_built:
		return
	_graph_built = true
	var segs: Array = []          # [a, b]
	var streets: Array = plan.get("streets", [])
	for st: Dictionary in streets:
		segs.append([st["a"], st["b"]])
	# Door paths: from a door approach outside the footprint to the nearest street.
	for k in (plan.get("lots", []) as Array).size():
		var lot: Dictionary = plan["lots"][k]
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var door: Vector2 = (lot["pos"] as Vector2) + fwd * maxf(3.8, _box_h[k].y + AGENT_RADIUS + 0.35)
		var best := Vector2.INF
		var bd := 16.0
		for st: Dictionary in streets:
			var q := Geometry2D.get_closest_point_to_segment(door, st["a"], st["b"])
			if door.distance_to(q) < bd:
				bd = door.distance_to(q)
				best = q
		if best != Vector2.INF:
			segs.append([door, best])
	# A loop around the well so trips across the plaza don't cut through it.
	if plan.get("inner_wall", 0.0) <= 0.0:
		var pr: float = plan.get("plaza_r", 12.0)
		var ring: Array[Vector2] = []
		for i in 8:
			var ang := TAU * i / 8.0
			ring.append(center + Vector2(cos(ang), sin(ang)) * pr * 0.6)
		for i in 8:
			segs.append([ring[i], ring[(i + 1) % 8]])
		for st: Dictionary in streets:
			var a: Vector2 = st["a"]
			if absf(a.distance_to(center) - pr) < 1.0:
				var near := ring[0]
				for rp in ring:
					if rp.distance_to(a) < near.distance_to(a):
						near = rp
				segs.append([a, near])

	# Paths hugging each wall ring, so trips to fields and posts on the other side
	# of the wall walk round to a gate instead of stopping at the stones.
	for w: Array in _walls:
		var wall_r: float = w[0]
		for ring_r: float in [wall_r * 1.05, wall_r - 3.0]:
			var n := maxi(16, int(TAU * ring_r / 9.0))
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				segs.append([center + Vector2(cos(a0), sin(a0)) * ring_r, center + Vector2(cos(a1), sin(a1)) * ring_r])

	# Split every segment where it crosses or meets another one.
	var splits: Array[PackedFloat32Array] = []
	var seg_grid := {}
	for i in segs.size():
		splits.append(PackedFloat32Array([0.0, 1.0]))
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var j2 := Vector2(JOIN, JOIN)
		for cell in _cells(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - j2, Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + j2):
			_push(seg_grid, cell, i)
	var links: Array = []         # extra [p, q] joins for near-miss junctions
	var seen := {}
	for cell in seg_grid:
		var list: PackedInt32Array = seg_grid[cell]
		for x in list.size():
			for y in range(x + 1, list.size()):
				var i := mini(list[x], list[y])
				var j := maxi(list[x], list[y])
				var key := i * 65536 + j
				if i == j or seen.has(key):
					continue
				seen[key] = true
				_join_segments(segs, splits, links, i, j)
	for i in segs.size():
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var ts: PackedFloat32Array = splits[i].duplicate()
		ts.sort()
		var prev := -1
		for t in ts:
			var n := _node_at(a.lerp(b, t))
			if prev >= 0 and n != prev:
				_link(prev, n)
			prev = n
	for pair: Array in links:
		var n0 := _node_at(pair[0])
		var n1 := _node_at(pair[1])
		if n0 != n1:
			_link(n0, n1)
	_index_edges()


func _join_segments(segs: Array, splits: Array[PackedFloat32Array], links: Array, i: int, j: int) -> void:
	var a1: Vector2 = segs[i][0]
	var b1: Vector2 = segs[i][1]
	var a2: Vector2 = segs[j][0]
	var b2: Vector2 = segs[j][1]
	var hit: Variant = Geometry2D.segment_intersects_segment(a1, b1, a2, b2)
	if hit != null:
		var q: Vector2 = hit
		splits[i].append(_param(a1, b1, q))
		splits[j].append(_param(a2, b2, q))
		return
	# T-junctions: an end of one segment that stops short of (or just past) the other.
	for pair: Array in [[i, a1, j, a2, b2], [i, b1, j, a2, b2], [j, a2, i, a1, b1], [j, b2, i, a1, b1]]:
		var p: Vector2 = pair[1]
		var sa: Vector2 = pair[3]
		var sb: Vector2 = pair[4]
		var q := Geometry2D.get_closest_point_to_segment(p, sa, sb)
		if p.distance_to(q) < JOIN:
			splits[int(pair[2])].append(_param(sa, sb, q))
			links.append([p, q])


func _param(a: Vector2, b: Vector2, q: Vector2) -> float:
	var len2 := a.distance_squared_to(b)
	return clampf((q - a).dot(b - a) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0


func _node_at(p: Vector2) -> int:
	var key := Vector2i(floori(p.x / MERGE), floori(p.y / MERGE))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k2 := key + Vector2i(dx, dy)
			if _node_lookup.has(k2):
				for n: int in _node_lookup[k2]:
					if _nodes[n].distance_to(p) < MERGE:
						return n
	var n := _nodes.size()
	_nodes.append(p)
	_adj.append(PackedInt32Array())
	_push(_node_lookup, key, n)
	return n


func _link(a: int, b: int) -> void:
	if _adj[a].has(b):
		return
	# Streets that run through a landmark or stall are not walkable there.
	if not clear_line(_nodes[a], _nodes[b], 0.1):
		return
	_adj[a].append(b)
	_adj[b].append(a)
	_edges.append(a)
	_edges.append(b)


func _index_edges() -> void:
	for e in _edges.size() / 2:
		var a := _nodes[_edges[e * 2]]
		var b := _nodes[_edges[e * 2 + 1]]
		for cell in _cells(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(maxf(a.x, b.x), maxf(a.y, b.y))):
			_push(_edge_grid, cell, e)


## Closest reachable point on the network from p: [node a, node b, point], or [].
func _attach(p: Vector2) -> Array:
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	# Nearby cells first; a field or forest edge far outside town scans every edge.
	for ring in [1, 3, -1]:
		var cands: Array = []
		if ring < 0:
			for e in _edges.size() / 2:
				cands.append(_edge_candidate(p, e))
		else:
			var seen := {}
			for dx in range(-ring, ring + 1):
				for dy in range(-ring, ring + 1):
					var cell := c + Vector2i(dx, dy)
					if not _edge_grid.has(cell):
						continue
					for e: int in _edge_grid[cell]:
						if not seen.has(e):
							seen[e] = true
							cands.append(_edge_candidate(p, e))
		if cands.is_empty():
			continue
		cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		# Far from town the nearest edges are often behind houses or the wall:
		# look further down the list before giving up.
		for n in mini(cands.size(), 8 if ring == 1 else (24 if ring == 3 else 160)):
			var q: Vector2 = cands[n][2]
			if clear_line(p, q):
				var e: int = cands[n][1]
				return [_edges[e * 2], _edges[e * 2 + 1], q]
		if ring == 3:
			var detour := _attach_detour(p)
			if not detour.is_empty():
				return detour
		if ring < 0:
			# Nothing in clear sight (e.g. standing in a back yard): take the nearest
			# and let the body slide along the wall to it.
			var e0: int = cands[0][1]
			return [_edges[e0 * 2], _edges[e0 * 2 + 1], cands[0][2]]
	return []


## Behind a house no street is in sight: step into the open first (a back yard
## or the gap between two houses) and attach from there. Returns
## [node a, node b, point, via] or [].
func _attach_detour(p: Vector2) -> Array:
	for dist: float in [4.0, 8.0, 13.0]:
		for k in 12:
			var ang := TAU * k / 12.0
			var via := p + Vector2(cos(ang), sin(ang)) * dist
			if inside(via) or not clear_line(p, via):
				continue
			var c := Vector2i(floori(via.x / CELL), floori(via.y / CELL))
			var cands: Array = []
			var seen := {}
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var cell := c + Vector2i(dx, dy)
					if not _edge_grid.has(cell):
						continue
					for e: int in _edge_grid[cell]:
						if not seen.has(e):
							seen[e] = true
							cands.append(_edge_candidate(via, e))
			cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			for n in mini(cands.size(), 6):
				var q: Vector2 = cands[n][2]
				if clear_line(via, q):
					var e: int = cands[n][1]
					return [_edges[e * 2], _edges[e * 2 + 1], q, via]
	return []


func _edge_candidate(p: Vector2, e: int) -> Array:
	var q := Geometry2D.get_closest_point_to_segment(p, _nodes[_edges[e * 2]], _nodes[_edges[e * 2 + 1]])
	return [p.distance_squared_to(q), e, q]


## Waypoints from `from` to `to` (excluding `from`) along streets and door paths,
## shortened wherever a straight line is clear. The goal is moved out of any
## footprint first. If the network can't reach it, the route stops at the
## closest reachable point and last_route_partial is set.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	last_route_partial = false
	var goal := push_out(to)
	if clear_line(from, goal):
		return PackedVector2Array([goal])
	_ensure_graph()
	var sa := _attach(from)
	var ga := _attach(goal)
	if sa.is_empty() or ga.is_empty():
		last_route_partial = true
		return PackedVector2Array([goal])
	var n := _nodes.size()
	var start := n
	var end := n + 1
	var pos := _nodes.duplicate()
	pos.append(sa[2])
	pos.append(ga[2])
	var g := PackedFloat32Array()
	g.resize(n + 2)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n + 2)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n + 2)
	var heap_f := PackedFloat32Array()
	var heap_n := PackedInt32Array()
	g[start] = 0.0
	_heap_push(heap_f, heap_n, pos[start].distance_to(pos[end]), start)
	var same_edge: bool = (sa[0] == ga[0] and sa[1] == ga[1]) or (sa[0] == ga[1] and sa[1] == ga[0])
	var found := false
	while not heap_n.is_empty():
		var u := _heap_pop(heap_f, heap_n)
		if closed[u] == 1:
			continue
		closed[u] = 1
		if u == end:
			found = true
			break
		var nbrs := PackedInt32Array()
		if u == start:
			nbrs.append(sa[0])
			nbrs.append(sa[1])
			if same_edge:
				nbrs.append(end)
		else:
			nbrs = _adj[u].duplicate()
			if u == ga[0] or u == ga[1]:
				nbrs.append(end)
		for v in nbrs:
			if closed[v] == 1:
				continue
			var cost := g[u] + pos[u].distance_to(pos[v])
			if cost < g[v]:
				g[v] = cost
				came[v] = u
				_heap_push(heap_f, heap_n, cost + pos[v].distance_to(pos[end]), v)
	var last := end
	if not found:
		# Closest settled node to the goal.
		last_route_partial = true
		var best := INF
		for v in n + 1:
			if closed[v] == 1 and pos[v].distance_to(goal) < best:
				best = pos[v].distance_to(goal)
				last = v
	var chain: Array[Vector2] = []
	var v := last
	while v != -1:
		chain.push_front(pos[v])
		v = came[v]
	if sa.size() > 3:
		chain.push_front(sa[3])
	chain.push_front(from)
	if found:
		if ga.size() > 3:
			chain.append(ga[3])
		chain.append(goal)
	return _smooth(chain)


## String-pulling: skip waypoints the agent can walk past in a straight line.
func _smooth(chain: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < chain.size() - 1:
		var j := mini(chain.size() - 1, i + 10)
		while j > i + 1 and not clear_line(chain[i], chain[j]):
			j -= 1
		if chain[j].distance_to(chain[i]) > 0.05 or j == chain.size() - 1:
			out.append(chain[j])
		i = j
	return out


func _heap_push(f: PackedFloat32Array, n: PackedInt32Array, key: float, node: int) -> void:
	f.append(key)
	n.append(node)
	var i := f.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if f[parent] <= f[i]:
			break
		var tf := f[parent]
		f[parent] = f[i]
		f[i] = tf
		var tn := n[parent]
		n[parent] = n[i]
		n[i] = tn
		i = parent


func _heap_pop(f: PackedFloat32Array, n: PackedInt32Array) -> int:
	var top := n[0]
	var last := f.size() - 1
	f[0] = f[last]
	n[0] = n[last]
	f.resize(last)
	n.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and f[l] < f[m]:
			m = l
		if r < last and f[r] < f[m]:
			m = r
		if m == i:
			break
		var tf := f[m]
		f[m] = f[i]
		f[i] = tf
		var tn := n[m]
		n[m] = n[i]
		n[i] = tn
		i = m
	return top
