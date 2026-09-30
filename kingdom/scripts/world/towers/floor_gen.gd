extends RefCounted
## Seeded labyrinth floors for the dungeon towers (docs/design/DUNGEON_TOWERS.md).
##
##   layout(tower, floor)  pure + deterministic: grid maze (recursive backtracker + a few loops), arrival stairs with the
##                         teleport gate, a SAFE ZONE dead end, a 3x3 BOSS ARENA behind a big door with the stairway up,
##                         chests, traps and mob groups. Connectivity is guaranteed and testable (`boss_reachable`).
##   build(layout, ...)    turns a layout into an interior Node3D: one merged vertex-coloured mesh (floor, walls, trims,
##                         ceiling, fixed props), one glowing rune mesh, one water/barrier mesh, MultiMesh prop families,
##                         one trimesh collider and a handful of lights. <= 150 draws, freed by the caller on exit.
##
## Coordinates: cell (cx, cy) has its centre at ((cx + .5) * CELL, 0, (cy + .5) * CELL) in the room's local space.
## Open bits: N = 1 (cy - 1), E = 2 (cx + 1), S = 4 (cy + 1), W = 8 (cx - 1).

const TowerData := preload("res://scripts/world/towers/tower_data.gd")

const W := 11
const H := 11
const CELL := 8.0
const WALL_T := 0.9
const N := 1
const E := 2
const S := 4
const WEST := 8
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BITS := [N, E, S, WEST]
const BOSS_BLOCK := Rect2i(8, 8, 3, 3)
const MAX_LIGHTS := 10

static var _glow_shader: Shader = null


# ====================================================================== layout (pure)

static func layout(tid: String, floor_n: int) -> Dictionary:
	var info := TowerData.floor_info(tid, floor_n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([tid, floor_n, 7171, "floor"])
	var open := PackedByteArray()
	open.resize(W * H)
	var seen := PackedByteArray()
	seen.resize(W * H)
	# the boss block is one open room, walled from the maze except the door
	for y in range(BOSS_BLOCK.position.y, BOSS_BLOCK.end.y):
		for x in range(BOSS_BLOCK.position.x, BOSS_BLOCK.end.x):
			seen[y * W + x] = 1
			var m := 0
			for d in 4:
				var n: Vector2i = Vector2i(x, y) + DIRS[d]
				if BOSS_BLOCK.has_point(n):
					m |= BITS[d]
			open[y * W + x] = m
	# recursive backtracker over the rest, from the start cell
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	seen[0] = 1
	while not stack.is_empty():
		var c: Vector2i = stack[stack.size() - 1]
		var options: Array[int] = []
		for d in 4:
			var n: Vector2i = c + DIRS[d]
			if _inside(n) and seen[n.y * W + n.x] == 0:
				options.append(d)
		if options.is_empty():
			stack.pop_back()
			continue
		var d: int = options[rng.randi() % options.size()]
		var n: Vector2i = c + DIRS[d]
		open[c.y * W + c.x] |= BITS[d]
		open[n.y * W + n.x] |= BITS[(d + 2) % 4]
		seen[n.y * W + n.x] = 1
		stack.append(n)
	# loops: knock a few walls between maze cells
	for i in 14:
		var c := Vector2i(rng.randi() % W, rng.randi() % H)
		var d := rng.randi() % 4
		var n: Vector2i = c + DIRS[d]
		if _inside(n) and not BOSS_BLOCK.has_point(c) and not BOSS_BLOCK.has_point(n):
			open[c.y * W + c.x] |= BITS[d]
			open[n.y * W + n.x] |= BITS[(d + 2) % 4]
	var L := {"tower": tid, "floor": floor_n, "theme": info["theme"], "level": info["level"], "tier": info["tier"], "w": W, "h": H,
		"cell": CELL, "open": open, "start": Vector2i(0, 0), "boss_block": BOSS_BLOCK, "info": info}
	# the boss door: the maze cell next to the arena that is farthest from the start
	var dist := bfs(L, Vector2i(0, 0))
	var best := Vector2i(-1, -1)
	var best_d := -1
	var best_dir := 0
	for y in range(BOSS_BLOCK.position.y - 1, BOSS_BLOCK.end.y):
		for x in range(BOSS_BLOCK.position.x - 1, BOSS_BLOCK.end.x):
			var c := Vector2i(x, y)
			if not _inside(c) or BOSS_BLOCK.has_point(c) or not dist.has(c):
				continue
			for d in 4:
				var n: Vector2i = c + DIRS[d]
				if BOSS_BLOCK.has_point(n) and int(dist[c]) > best_d:
					best_d = int(dist[c])
					best = c
					best_dir = d
	var bn: Vector2i = best + DIRS[best_dir]
	open[best.y * W + best.x] |= BITS[best_dir]
	open[bn.y * W + bn.x] |= BITS[(best_dir + 2) % 4]
	L["door_cell"] = best
	L["door_dir"] = best_dir
	L["arena_cell"] = bn
	L["boss_cell"] = Vector2i(BOSS_BLOCK.position.x + 1, BOSS_BLOCK.position.y + 1)
	# the stairway up sits in the arena corner farthest from the door
	var corners: Array[Vector2i] = [Vector2i(BOSS_BLOCK.position.x, BOSS_BLOCK.position.y), Vector2i(BOSS_BLOCK.end.x - 1, BOSS_BLOCK.position.y),
		Vector2i(BOSS_BLOCK.position.x, BOSS_BLOCK.end.y - 1), Vector2i(BOSS_BLOCK.end.x - 1, BOSS_BLOCK.end.y - 1)]
	var sc := corners[0]
	for c in corners:
		if Vector2(c - bn).length() > Vector2(sc - bn).length():
			sc = c
	L["stairs_cell"] = sc
	dist = bfs(L, Vector2i(0, 0))
	L["dist"] = dist
	# the safe zone: a dead end a few steps from the start
	var cands: Array[Vector2i] = []
	for c: Vector2i in dist:
		if BOSS_BLOCK.has_point(c) or c == Vector2i(0, 0) or c == best:
			continue
		if _bit_count(int(open[c.y * W + c.x])) == 1 and int(dist[c]) >= 3:
			cands.append(c)
	if cands.is_empty():
		for c: Vector2i in dist:
			if not BOSS_BLOCK.has_point(c) and c != Vector2i(0, 0) and c != best and int(dist[c]) >= 3:
				cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(int(dist[a]) - 6)
		var db := absi(int(dist[b]) - 6)
		return da < db if da != db else (a.y * W + a.x) < (b.y * W + b.x))
	L["safe_cell"] = cands[0]
	# chests in dead ends, traps in corridors, mobs in groups
	var used := {Vector2i(0, 0): true, L["safe_cell"]: true, best: true}
	var ends: Array[Vector2i] = []
	var corridors: Array[Vector2i] = []
	var rooms: Array[Vector2i] = []
	for c: Vector2i in dist:
		if BOSS_BLOCK.has_point(c) or used.has(c):
			continue
		var bc := _bit_count(int(open[c.y * W + c.x]))
		if bc == 1:
			ends.append(c)
		elif bc == 2 and int(dist[c]) >= 2:
			corridors.append(c)
		if int(dist[c]) >= 2:
			rooms.append(c)
	_shuffle(ends, rng)
	_shuffle(corridors, rng)
	_shuffle(rooms, rng)
	var chests: Array = []
	for i in mini(ends.size(), 3 + floor_n / 8):
		chests.append({"cell": ends[i], "tier": int(info["tier"]), "id": "c%d" % i, "locked": i == 0 and floor_n >= 6})
		used[ends[i]] = true
	# one hidden cache somewhere in the maze
	for c in rooms:
		if not used.has(c) and chests.size() < 7:
			chests.append({"cell": c, "tier": int(info["tier"]), "id": "c%d" % chests.size(), "locked": false})
			used[c] = true
			break
	var traps: Array = []
	var trap_kinds := ["spikes", "flame", "dart"]
	for i in mini(corridors.size(), 4 + floor_n / 4):
		var c := corridors[i]
		traps.append({"cell": c, "kind": trap_kinds[rng.randi() % trap_kinds.size()], "hidden": rng.randf() < 0.45, "id": "t%d" % i})
		used[c] = true
	var mobs: Array = []
	var theme := TowerData.theme(String(info["theme"]))
	var kinds: Array = theme["mobs"]
	var groups := 7 + floor_n / 3
	var mi := 0
	for c in rooms:
		if mi >= groups:
			break
		if used.has(c) and not (ends.has(c)):
			continue
		var count := 1 + (rng.randi() % 3 if floor_n >= 3 else rng.randi() % 2)
		var kind: String = kinds[rng.randi() % kinds.size()]
		for k in count:
			mobs.append({"cell": c, "kind": kind, "id": "m%d_%d" % [mi, k], "jitter": Vector2(rng.randf_range(-2.4, 2.4), rng.randf_range(-2.4, 2.4))})
		mi += 1
	L["chests"] = chests
	L["traps"] = traps
	L["mobs"] = mobs
	L["seed"] = rng.seed
	return L


static func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


static func _bit_count(m: int) -> int:
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func open_mask(L: Dictionary, c: Vector2i) -> int:
	return int((L["open"] as PackedByteArray)[c.y * W + c.x])


## Breadth-first distances (in cells) from `from` along open edges.
static func bfs(L: Dictionary, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var m := open_mask(L, c)
		for d in 4:
			if m & BITS[d]:
				var n: Vector2i = c + DIRS[d]
				if _inside(n) and not dist.has(n):
					dist[n] = int(dist[c]) + 1
					q.append(n)
	return dist


## Every cell is reachable from the start, the boss door, the arena, the stairs and the safe zone included.
static func boss_reachable(L: Dictionary) -> bool:
	var d := bfs(L, L["start"])
	return d.has(L["door_cell"]) and d.has(L["arena_cell"]) and d.has(L["boss_cell"]) and d.has(L["stairs_cell"]) and d.has(L["safe_cell"])


static func fully_connected(L: Dictionary) -> bool:
	return bfs(L, L["start"]).size() == W * H


## Edges are symmetric: a wall is open from both sides or from neither.
static func consistent(L: Dictionary) -> bool:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			for d in 4:
				var n: Vector2i = c + DIRS[d]
				var here: bool = (open_mask(L, c) & BITS[d]) != 0
				if not _inside(n):
					if here:
						return false
				elif here != ((open_mask(L, n) & BITS[(d + 2) % 4]) != 0):
					return false
	return true


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) + 0.5) * CELL, 0.0, (float(c.y) + 0.5) * CELL)


static func cell_of(local: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(local.x / CELL)), 0, W - 1), clampi(int(floor(local.z / CELL)), 0, H - 1))


## Local position of the boss-door centre (on the shared edge).
static func door_pos(L: Dictionary) -> Vector3:
	var c: Vector2i = L["door_cell"]
	var d: int = L["door_dir"]
	var dir := Vector2(DIRS[d])
	return cell_center(c) + Vector3(dir.x, 0.0, dir.y) * (CELL * 0.5)


static func spawn_pos(L: Dictionary) -> Vector3:
	var c: Vector2i = L["start"]
	return cell_center(c) + Vector3(-1.5, 0.3, -1.5)


# ====================================================================== mesh builder

class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()      # collision triangles (only what is added with collide = true)

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color, collide := false) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		var base := v.size()
		v.append_array([a, b, d])
		n.append_array([nrm, nrm, nrm])
		c.append_array([col, col, col])
		idx.append_array([base, base + 1, base + 2])
		if collide:
			faces.append_array([a, b, d])

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color, collide := false) -> void:
		tri(a, b, d, col, collide)
		tri(a, d, e, col, collide)

	## Axis-aligned box rotated by `yaw` about its centre.
	func box(center: Vector3, size: Vector3, col: Color, yaw := 0.0, collide := false, top_col := Color(0, 0, 0, 0)) -> void:
		var h := size * 0.5
		var bs := Basis(Vector3.UP, yaw)
		var p: Array[Vector3] = []
		for i in 8:
			p.append(center + bs * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		var tc := col if top_col.a == 0.0 else top_col
		# -z, +z, -x, +x, -y, +y
		quad(p[0], p[2], p[3], p[1], col, collide)
		quad(p[4], p[5], p[7], p[6], col, collide)
		quad(p[0], p[4], p[6], p[2], col, collide)
		quad(p[1], p[3], p[7], p[5], col, collide)
		quad(p[0], p[1], p[5], p[4], col, collide)
		quad(p[2], p[6], p[7], p[3], tc, collide)

	## Tapered prism (cylinder/cone) standing on `base`.
	func prism(base: Vector3, r0: float, r1: float, height: float, sides: int, col: Color, top_col := Color(0, 0, 0, 0), collide := false, yaw := 0.0) -> void:
		var tc := col if top_col.a == 0.0 else top_col
		var bs := Basis(Vector3.UP, yaw)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := base + bs * Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var b1 := base + bs * Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var t0 := base + bs * Vector3(cos(a0) * r1, height, sin(a0) * r1)
			var t1 := base + bs * Vector3(cos(a1) * r1, height, sin(a1) * r1)
			quad(b0, t0, t1, b1, col.lerp(tc, 0.0), collide)
			if r1 > 0.001:
				tri(base + Vector3(0, height, 0), t1, t0, tc, collide)

	## Flat annulus at height y (floor inlays, gate rings).
	func ring(center: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := center + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p1 := center + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var q0 := center + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var q1 := center + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			quad(p0, q0, q1, p1, col)

	func is_empty() -> bool:
		return v.is_empty()

	func mesh(mat: Material) -> ArrayMesh:
		var am := ArrayMesh.new()
		if v.is_empty():
			return am
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, mat)
		return am


# ====================================================================== materials and environment

static func lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.metallic = 0.0
	return m


## Runic glow: vertex colour as emission with a slow pulse (alpha of the colour is the pulse depth).
static func glow_material(energy := 1.25) -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = "shader_type spatial;\nrender_mode cull_disabled, shadows_disabled;\nuniform float energy = 2.4;\n" \
			+ "void fragment() {\n\tfloat p = 0.78 + 0.22 * sin(TIME * 1.6 + VERTEX.x * 0.35 + VERTEX.z * 0.27);\n" \
			+ "\tALBEDO = COLOR.rgb * 0.25;\n\tEMISSION = COLOR.rgb * energy * p;\n}\n"
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("energy", energy)
	return m


static func alpha_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.15
	m.metallic = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func environment(theme_key: String) -> Environment:
	var t := TowerData.theme(theme_key)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = t["fog"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = t["ambient"]
	var lum: float = (t["ambient"] as Color).get_luminance()
	e.ambient_light_energy = (0.9 if bool(t["ceiling"]) else 1.1) * clampf(1.5 - lum * 1.2, 0.45, 1.1)
	e.fog_enabled = true
	e.fog_light_color = t["fog"]
	e.fog_density = 0.016 if bool(t["ceiling"]) else 0.010
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.05
	return e


# ====================================================================== interior builder

## Builds the interior. Returns {root, points, explored_seed, draw_estimate, lights, door, barrier, spawn}.
## `boss_dead`: the stairway barrier starts open. `theme_override` for shots/tests.
static func build(L: Dictionary, boss_dead := false) -> Dictionary:
	var info: Dictionary = L["info"]
	var theme_key: String = L["theme"]
	var t := TowerData.theme(theme_key)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(L["seed"]) + 991
	var root := Node3D.new()
	root.name = "TowerFloor%d" % int(L["floor"])
	var lit := MB.new()
	var glow := MB.new()
	var alpha := MB.new()
	var wall_h := 7.0 if bool(t["ceiling"]) else 6.0
	var wall_c: Color = t["wall"]
	var floor_c: Color = t["floor"]
	var trim_c: Color = t["trim"]
	var acc: Color = t["accent"]
	var open: PackedByteArray = L["open"]
	var points: Array = []
	var lights: Array = []          # [pos Vector3, Color, range, energy]
	var total_w := float(W) * CELL
	var total_h := float(H) * CELL

	# ---- floor, per cell with a gentle tint
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var col := floor_c.lerp(Color.WHITE, rng.randf() * 0.06) if (x + y) % 2 == 0 else floor_c.darkened(rng.randf() * 0.08)
			if c == L["safe_cell"]:
				col = Color(0.45, 0.36, 0.26)
			elif BOSS_BLOCK.has_point(c):
				col = floor_c.darkened(0.18)
			var x0 := float(x) * CELL
			var z0 := float(y) * CELL
			lit.quad(Vector3(x0, 0, z0), Vector3(x0, 0, z0 + CELL), Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0 + CELL, 0, z0), col)
	# ---- walls (collidable): N and W of every cell, plus the south and east rims
	for y in H:
		for x in W:
			var m := int(open[y * W + x])
			var x0 := float(x) * CELL
			var z0 := float(y) * CELL
			if not (m & N):
				_wall(lit, Vector3(x0 + CELL * 0.5, 0, z0), true, wall_h, wall_c, trim_c, rng)
			if not (m & WEST):
				_wall(lit, Vector3(x0, 0, z0 + CELL * 0.5), false, wall_h, wall_c, trim_c, rng)
			if y == H - 1 and not (m & S):
				_wall(lit, Vector3(x0 + CELL * 0.5, 0, z0 + CELL), true, wall_h, wall_c, trim_c, rng)
			if x == W - 1 and not (m & E):
				_wall(lit, Vector3(x0 + CELL, 0, z0 + CELL * 0.5), false, wall_h, wall_c, trim_c, rng)
	# ---- rune strips on some wall faces
	for y in H:
		for x in W:
			var m := int(open[y * W + x])
			var x0 := float(x) * CELL
			var z0 := float(y) * CELL
			if not (m & N) and y > 0 and rng.randf() < 0.42:
				_rune(glow, Vector3(x0 + CELL * 0.5, 0, z0), true, acc, rng, rng.randf() < 0.5)
			if not (m & WEST) and x > 0 and rng.randf() < 0.42:
				_rune(glow, Vector3(x0, 0, z0 + CELL * 0.5), false, acc, rng, rng.randf() < 0.5)
	# ---- ceiling
	var roofed := bool(t["ceiling"])
	if roofed:
		var cc := wall_c.darkened(0.35)
		lit.quad(Vector3(0, wall_h, 0), Vector3(total_w, wall_h, 0), Vector3(total_w, wall_h, total_h), Vector3(0, wall_h, total_h), cc)
	# ---- fixed rooms
	var start_c: Vector2i = L["start"]
	var sc := cell_center(start_c)
	# arrival: descending stairs in the corner, teleport gate ring
	_stairs(lit, glow, sc + Vector3(-2.6, 0, -2.6), PI * 0.25, trim_c, acc, false)
	var gate_pos := sc + Vector3(1.6, 0, 1.6)
	lit.prism(gate_pos + Vector3(0, 0, 0), 0.9, 0.7, 0.35, 10, trim_c.darkened(0.2))
	glow.ring(gate_pos + Vector3(0, 0.37, 0), 0.75, 0.95, 20, acc)
	glow.prism(gate_pos + Vector3(0, 0.4, 0), 0.22, 0.0, 2.1, 6, acc.lightened(0.2))
	lights.append([sc + Vector3(0, 3.2, 0), acc.lerp(Color.WHITE, 0.35), 15.0, 1.3])
	points.append({"kind": "stairs_down", "pos": sc + Vector3(-2.6, 0.2, -2.6), "cell": start_c})
	points.append({"kind": "gate", "pos": gate_pos + Vector3(0, 0.3, 0), "cell": start_c})
	# safe zone
	var safe_c: Vector2i = L["safe_cell"]
	var safe_p := cell_center(safe_c)
	_safe_room(lit, glow, L, safe_c, trim_c, acc)
	lights.append([safe_p + Vector3(0, 2.4, 0), Color(1.0, 0.72, 0.4), 13.0, 2.0])
	points.append({"kind": "rest", "pos": safe_p + Vector3(0, 0.3, 0), "cell": safe_c})
	points.append({"kind": "merchant", "pos": safe_p + Vector3(2.4, 0.0, -1.2), "cell": safe_c})
	# boss door and arena
	var door_p := door_pos(L)
	var dd: int = L["door_dir"]
	var door_dir := Vector3(DIRS[dd].x, 0, DIRS[dd].y)
	var door := _boss_door(L, door_p, door_dir, trim_c, acc)
	root.add_child(door)
	var arena_c: Vector2i = L["boss_cell"]
	var arena_p := cell_center(arena_c)
	glow.ring(arena_p + Vector3(0, 0.03, 0), 6.0, 6.3, 40, acc.darkened(0.15))
	glow.ring(arena_p + Vector3(0, 0.03, 0), 3.0, 3.15, 28, acc.darkened(0.3))
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.3927
		lit.prism(arena_p + Vector3(cos(a) * 9.6, 0, sin(a) * 9.6).limit_length(9.6), 0.75, 0.6, wall_h - 0.6, 8, trim_c, Color(0, 0, 0, 0), false)
	lights.append([arena_p + Vector3(0, wall_h - 0.8, 0), acc.lerp(Color.WHITE, 0.3), 26.0, 1.6])
	points.append({"kind": "boss_door", "pos": door_p - door_dir * 1.6 + Vector3(0, 0.3, 0), "cell": L["door_cell"]})
	points.append({"kind": "boss_spawn", "pos": arena_p + Vector3(0, 0.1, 0), "cell": arena_c})
	# stairs up + barrier
	var up_c: Vector2i = L["stairs_cell"]
	var up_p := cell_center(up_c)
	var toward := (arena_p - up_p)
	toward.y = 0.0
	var up_yaw := atan2(toward.x, toward.z) if toward.length() > 0.1 else 0.0
	_stairs(lit, glow, up_p, up_yaw + PI, trim_c, acc, true)
	points.append({"kind": "stairs_up", "pos": up_p + Vector3(0, 0.3, 0), "cell": up_c})
	var barrier := MeshInstance3D.new()
	barrier.name = "StairBarrier"
	var bmb := MB.new()
	var bp := up_p + Vector3(toward.normalized() * 2.4) if toward.length() > 0.1 else up_p
	var side := Vector3(toward.z, 0, -toward.x).normalized() * 3.2 if toward.length() > 0.1 else Vector3(3.2, 0, 0)
	bmb.quad(bp - side, bp - side + Vector3(0, 4.8, 0), bp + side + Vector3(0, 4.8, 0), bp + side, Color(acc.r, acc.g, acc.b, 0.3))
	barrier.mesh = bmb.mesh(alpha_material(Color(1, 1, 1, 1)))
	barrier.visible = not boss_dead
	root.add_child(barrier)
	var bbody := StaticBody3D.new()
	bbody.name = "StairBarrierBody"
	bbody.collision_layer = 1
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(absf(side.x) * 2.0 + 0.6, 5.0, absf(side.z) * 2.0 + 0.6)
	bshape.shape = bbox
	bbody.position = bp + Vector3(0, 2.5, 0)
	bbody.add_child(bshape)
	if boss_dead:
		bshape.disabled = true
	barrier.add_child(bbody)
	# ---- chests (visual shells; the runtime owns their state)
	for ch: Dictionary in L["chests"]:
		var cp := cell_center(ch["cell"]) + Vector3(0, 0, 0)
		_chest_shell(lit, glow, cp, trim_c, acc, bool(ch["locked"]))
		points.append({"kind": "chest", "pos": cp + Vector3(0, 0.4, 0), "cell": ch["cell"], "id": ch["id"], "tier": ch["tier"], "locked": ch["locked"]})
		if lights.size() < MAX_LIGHTS - 2 and rng.randf() < 0.5:
			lights.append([cp + Vector3(0, 1.8, 0), acc.lerp(Color(1, 0.9, 0.6), 0.5), 6.0, 0.9])
	# ---- traps (plates on the floor, hidden ones only faint)
	for tr: Dictionary in L["traps"]:
		var tp := cell_center(tr["cell"]) + Vector3(0, 0.02, 0)
		var tcol := Color(0.55, 0.12, 0.1) if tr["kind"] != "dart" else Color(0.5, 0.42, 0.12)
		if bool(tr["hidden"]):
			lit.box(tp + Vector3(0, 0.01, 0), Vector3(2.6, 0.02, 2.6), floor_c.lerp(tcol, 0.12))
		else:
			lit.box(tp + Vector3(0, 0.03, 0), Vector3(2.6, 0.05, 2.6), trim_c.darkened(0.2))
			glow.box(tp + Vector3(0, 0.07, 0), Vector3(1.9, 0.02, 1.9), tcol)
		points.append({"kind": "trap", "pos": tp, "cell": tr["cell"], "trap": tr["kind"], "hidden": tr["hidden"], "id": tr["id"]})
	# ---- corridor lamps: a few glowing sconces along the route so the maze reads
	var lamp_cells: Array = []
	for c: Vector2i in (L["dist"] as Dictionary):
		if (int(L["dist"][c]) % 5 == 4) and not BOSS_BLOCK.has_point(c) and c != safe_c:
			lamp_cells.append(c)
	for c: Vector2i in lamp_cells:
		var lp := cell_center(c)
		glow.box(lp + Vector3(0, 2.2, 0), Vector3(0.35, 0.35, 0.35), acc.lerp(Color(1, 0.85, 0.5), 0.5))
		if lights.size() < MAX_LIGHTS:
			lights.append([lp + Vector3(0, 2.4, 0), acc.lerp(Color(1, 0.85, 0.5), 0.5), 10.0, 1.0])

	# ---- meshes
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(total_w + 16.0, 1.0, total_h + 16.0)
	fshape.shape = fbox
	fshape.position = Vector3(total_w * 0.5, -0.5, total_h * 0.5)
	body.add_child(fshape)
	if not lit.faces.is_empty():
		var cs := CollisionShape3D.new()
		var tri := ConcavePolygonShape3D.new()
		tri.set_faces(lit.faces)
		cs.shape = tri
		body.add_child(cs)
	var lit_mi := MeshInstance3D.new()
	lit_mi.name = "Architecture"
	lit_mi.mesh = lit.mesh(lit_material())
	root.add_child(lit_mi)
	var glow_mi := MeshInstance3D.new()
	glow_mi.name = "Runes"
	glow_mi.mesh = glow.mesh(glow_material())
	glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow_mi)
	# ---- theme props as MultiMesh families
	_dress(root, L, t, rng, wall_h)
	# ---- water
	if bool(t["water"]):
		var wmb := MB.new()
		wmb.quad(Vector3(-4, 0.42, -4), Vector3(-4, 0.42, total_h + 4), Vector3(total_w + 4, 0.42, total_h + 4), Vector3(total_w + 4, 0.42, -4),
			Color(0.16, 0.42, 0.52, 0.55))
		var wmi := MeshInstance3D.new()
		wmi.name = "Water"
		wmi.mesh = wmb.mesh(alpha_material(Color(1, 1, 1, 1)))
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wmi)
	# ---- a soft key light from above-left gives the walls shape (no shadows: mobile)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	key.light_energy = 0.55
	key.light_color = Color(1.0, 0.95, 0.88).lerp(acc, 0.15)
	key.shadow_enabled = false
	root.add_child(key)
	# ---- lights
	var n_lights := 0
	for l: Array in lights:
		if n_lights >= MAX_LIGHTS:
			break
		var ol := OmniLight3D.new()
		ol.position = l[0]
		ol.light_color = l[1]
		ol.omni_range = float(l[2])
		ol.light_energy = float(l[3])
		ol.shadow_enabled = false
		ol.set_meta("flicker", true)
		root.add_child(ol)
		n_lights += 1
	return {"root": root, "points": points, "door": door, "barrier": barrier, "lights": n_lights, "wall_h": wall_h,
		"spawn": spawn_pos(L), "gate_pos": gate_pos, "acc": acc}


# ---- geometry helpers ----------------------------------------------------------------

static func _wall(mb: MB, mid: Vector3, along_x: bool, h: float, col: Color, trim: Color, rng: RandomNumberGenerator) -> void:
	var len := CELL + WALL_T
	var size := Vector3(len, h, WALL_T) if along_x else Vector3(WALL_T, h, len)
	var k := 0.93 + rng.randf() * 0.14
	mb.box(mid + Vector3(0, h * 0.5, 0), size, Color(col.r * k, col.g * k, col.b * k), 0.0, true, col.lightened(0.08))
	var tsize := Vector3(len, 0.7, WALL_T + 0.3) if along_x else Vector3(WALL_T + 0.3, 0.7, len)
	mb.box(mid + Vector3(0, 0.35, 0), tsize, trim)
	var csize := Vector3(len, 0.4, WALL_T + 0.35) if along_x else Vector3(WALL_T + 0.35, 0.4, len)
	mb.box(mid + Vector3(0, h - 0.2, 0), csize, trim)


static func _rune(mb: MB, mid: Vector3, along_x: bool, col: Color, rng: RandomNumberGenerator, tall: bool) -> void:
	var off := WALL_T * 0.5 + 0.03
	for sgn in [-1.0, 1.0]:
		var o := Vector3(0, 0, sgn * off) if along_x else Vector3(sgn * off, 0, 0)
		var y := 2.6 + rng.randf() * 0.8
		var sz_h := Vector3(3.0, 0.14, 0.04) if along_x else Vector3(0.04, 0.14, 3.0)
		mb.box(mid + o + Vector3(0, y, 0), sz_h, col)
		var sz_v := Vector3(0.14, 1.3 if tall else 0.7, 0.04) if along_x else Vector3(0.04, 1.3 if tall else 0.7, 0.14)
		mb.box(mid + o + Vector3(0, y - 0.6, 0), sz_v, col.darkened(0.1))
		var sz_d := Vector3(0.45, 0.45, 0.04) if along_x else Vector3(0.04, 0.45, 0.45)
		mb.box(mid + o + Vector3(0, y + 0.0, 0), sz_d, col.lightened(0.25), 0.78)


static func _stairs(mb: MB, glow: MB, at: Vector3, yaw: float, trim: Color, acc: Color, up: bool) -> void:
	var bs := Basis(Vector3.UP, yaw)
	for i in 6:
		var hgt := 0.22 * float(i + 1) if up else 0.22 * float(6 - i)
		mb.box(at + bs * Vector3(0, hgt * 0.5, float(i) * 0.7 - 1.75), Vector3(3.0, hgt, 0.7), trim.lightened(0.05 * float(i)), yaw)
	# arch
	mb.box(at + bs * Vector3(-1.7, 1.6, 1.9), Vector3(0.45, 3.2, 0.6), trim, yaw)
	mb.box(at + bs * Vector3(1.7, 1.6, 1.9), Vector3(0.45, 3.2, 0.6), trim, yaw)
	mb.box(at + bs * Vector3(0, 3.3, 1.9), Vector3(3.9, 0.45, 0.6), trim, yaw)
	glow.box(at + bs * Vector3(0, 3.3, 1.55), Vector3(2.6, 0.1, 0.05), acc, yaw)


static func _safe_room(mb: MB, glow: MB, L: Dictionary, c: Vector2i, trim: Color, acc: Color) -> void:
	var p := cell_center(c)
	var warm := Color(1.0, 0.62, 0.28)
	# bonfire
	mb.prism(p + Vector3(0, 0, 0), 0.9, 0.7, 0.3, 10, Color(0.3, 0.27, 0.24))
	glow.prism(p + Vector3(0, 0.3, 0), 0.45, 0.0, 1.3, 6, warm)
	glow.prism(p + Vector3(0, 0.3, 0), 0.28, 0.0, 1.9, 5, Color(1.0, 0.85, 0.45), Color(0, 0, 0, 0), false, 0.5)
	for i in 5:
		var a := TAU * float(i) / 5.0
		mb.box(p + Vector3(cos(a) * 1.0, 0.25, sin(a) * 1.0), Vector3(0.5, 0.5, 0.5), Color(0.38, 0.36, 0.33), a)
	# merchant stall and a cot
	mb.box(p + Vector3(2.4, 0.5, -1.2), Vector3(1.8, 1.0, 0.9), Color(0.4, 0.28, 0.16))
	mb.box(p + Vector3(2.4, 1.05, -1.2), Vector3(2.0, 0.1, 1.1), Color(0.6, 0.18, 0.14))
	mb.box(p + Vector3(-2.3, 0.22, 1.6), Vector3(1.0, 0.3, 2.2), Color(0.5, 0.4, 0.3))
	mb.box(p + Vector3(-2.3, 0.42, 0.9), Vector3(0.9, 0.12, 0.6), Color(0.85, 0.82, 0.74))
	# warding arch at the entrance: glows where the corridor opens
	var m := open_mask(L, c)
	for d in 4:
		if m & BITS[d]:
			var dir := Vector3(DIRS[d].x, 0, DIRS[d].y)
			var side := Vector3(dir.z, 0, dir.x).abs()
			var mid := p + dir * (CELL * 0.5 - 0.6)
			mb.box(mid + side * 1.8 + Vector3(0, 1.7, 0), Vector3(0.5 + absf(dir.x) * 0.0, 3.4, 0.5), trim)
			mb.box(mid - side * 1.8 + Vector3(0, 1.7, 0), Vector3(0.5, 3.4, 0.5), trim)
			glow.box(mid + Vector3(0, 3.5, 0), Vector3(4.1 * side.x + 0.4 * dir.x, 0.22, 4.1 * side.z + 0.4 * dir.z), warm)


static func _chest_shell(mb: MB, glow: MB, p: Vector3, trim: Color, acc: Color, locked: bool) -> void:
	var wood := Color(0.42, 0.27, 0.14)
	mb.box(p + Vector3(0, 0.35, 0), Vector3(1.3, 0.7, 0.8), wood)
	mb.box(p + Vector3(0, 0.78, 0), Vector3(1.36, 0.22, 0.86), wood.lightened(0.1))
	mb.box(p + Vector3(0, 0.5, 0.41), Vector3(1.4, 0.12, 0.05), Color(0.6, 0.5, 0.2))
	glow.box(p + Vector3(0, 0.62, 0.44), Vector3(0.22, 0.26, 0.06), Color(1.0, 0.3, 0.2) if locked else acc.lerp(Color(1, 0.9, 0.5), 0.6))


static func _boss_door(L: Dictionary, at: Vector3, dir: Vector3, trim: Color, acc: Color) -> Node3D:
	var door := Node3D.new()
	door.name = "BossDoor"
	var yaw := atan2(dir.x, dir.z)
	door.position = at
	door.rotation.y = yaw
	var mb := MB.new()
	var gmb := MB.new()
	var stone := trim.darkened(0.1)
	# frame (fixed) and two leaves that slide apart
	mb.box(Vector3(-CELL * 0.5 + 0.2, 3.6, 0), Vector3(0.9, 7.2, 1.3), stone.lightened(0.05))
	mb.box(Vector3(CELL * 0.5 - 0.2, 3.6, 0), Vector3(0.9, 7.2, 1.3), stone.lightened(0.05))
	mb.box(Vector3(0, 7.0, 0), Vector3(CELL, 1.0, 1.3), stone.lightened(0.08))
	gmb.box(Vector3(0, 6.35, -0.7), Vector3(5.2, 0.16, 0.05), acc)
	gmb.box(Vector3(0, 6.35, 0.7), Vector3(5.2, 0.16, 0.05), acc)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = mb.mesh(lit_material())
	door.add_child(frame)
	var fg := MeshInstance3D.new()
	fg.mesh = gmb.mesh(glow_material())
	fg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door.add_child(fg)
	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.name = "Leaf%s" % ("L" if side < 0 else "R")
		leaf.position = Vector3(float(side) * (CELL * 0.25 - 0.1), 0, 0)
		var lmb := MB.new()
		var lgl := MB.new()
		lmb.box(Vector3(0, 3.2, 0), Vector3(CELL * 0.5 - 0.5, 6.4, 0.7), stone.darkened(0.12))
		lmb.box(Vector3(0, 3.2, 0.0), Vector3(CELL * 0.5 - 1.3, 5.6, 0.9), stone.darkened(0.25))
		lgl.box(Vector3(0, 3.4, 0.47), Vector3(0.25, 4.0, 0.05), acc)
		lgl.box(Vector3(0, 3.4, -0.47), Vector3(0.25, 4.0, 0.05), acc)
		lgl.box(Vector3(float(-side) * 0.7, 3.4, 0.47), Vector3(0.9, 0.2, 0.05), acc.darkened(0.1))
		lgl.box(Vector3(float(-side) * 0.7, 3.4, -0.47), Vector3(0.9, 0.2, 0.05), acc.darkened(0.1))
		var lm := MeshInstance3D.new()
		lm.mesh = lmb.mesh(lit_material())
		leaf.add_child(lm)
		var lg := MeshInstance3D.new()
		lg.mesh = lgl.mesh(glow_material())
		lg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.add_child(lg)
		door.add_child(leaf)
	var blocker := StaticBody3D.new()
	blocker.name = "DoorBody"
	blocker.collision_layer = 1
	var bs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(CELL - 1.0, 7.0, 1.0)
	bs.shape = bb
	bs.position = Vector3(0, 3.5, 0)
	blocker.add_child(bs)
	door.add_child(blocker)
	return door


## Slides the leaves apart and removes the blocker.
static func open_door(door: Node3D, tween_parent: Node = null) -> void:
	var body := door.get_node_or_null("DoorBody") as StaticBody3D
	if body:
		body.collision_layer = 0
		for ch in body.get_children():
			if ch is CollisionShape3D:
				(ch as CollisionShape3D).set_deferred("disabled", true)
	for n in ["LeafL", "LeafR"]:
		var leaf := door.get_node_or_null(n) as Node3D
		if leaf == null:
			continue
		var to := leaf.position + Vector3((-1.0 if n == "LeafL" else 1.0) * (CELL * 0.25 - 0.3), 0, 0)
		if tween_parent != null and tween_parent.is_inside_tree():
			tween_parent.create_tween().tween_property(leaf, "position", to, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		else:
			leaf.position = to


static func close_door(door: Node3D) -> void:
	var body := door.get_node_or_null("DoorBody") as StaticBody3D
	if body:
		body.collision_layer = 1
		for ch in body.get_children():
			if ch is CollisionShape3D:
				(ch as CollisionShape3D).disabled = false
	for n in ["LeafL", "LeafR"]:
		var leaf := door.get_node_or_null(n) as Node3D
		if leaf:
			leaf.position = Vector3((-1.0 if n == "LeafL" else 1.0) * (CELL * 0.25 - 0.1), 0, 0)


# ---- prop families --------------------------------------------------------------------

static func _family_mesh(fam: String, acc: Color, t: Dictionary) -> Array:
	# returns [ArrayMesh builder MB, glow?: bool]
	var mb := MB.new()
	var glow := false
	match fam:
		"tree":
			mb.prism(Vector3.ZERO, 0.32, 0.22, 2.4, 6, Color(0.36, 0.25, 0.14))
			mb.prism(Vector3(0, 1.8, 0), 1.9, 0.0, 2.4, 7, Color(0.16, 0.38, 0.14), Color(0.22, 0.46, 0.18))
			mb.prism(Vector3(0, 3.0, 0), 1.4, 0.0, 2.0, 7, Color(0.18, 0.42, 0.15), Color(0.26, 0.5, 0.2))
		"pine":
			mb.prism(Vector3.ZERO, 0.25, 0.2, 1.2, 6, Color(0.3, 0.22, 0.14))
			mb.prism(Vector3(0, 0.9, 0), 1.6, 0.0, 2.0, 7, Color(0.13, 0.3, 0.2), Color(0.85, 0.92, 0.95))
			mb.prism(Vector3(0, 2.2, 0), 1.2, 0.0, 1.8, 7, Color(0.15, 0.34, 0.22), Color(0.88, 0.94, 0.97))
		"rock":
			mb.prism(Vector3.ZERO, 1.1, 0.55, 0.9, 6, Color(0.4, 0.4, 0.38), Color(0.5, 0.5, 0.47))
		"root":
			mb.prism(Vector3.ZERO, 0.45, 0.12, 1.6, 5, Color(0.25, 0.17, 0.1), Color(0.3, 0.2, 0.12), false, 0.4)
		"column":
			mb.prism(Vector3.ZERO, 0.62, 0.55, 5.6, 8, Color(0.46, 0.44, 0.4), Color(0.5, 0.48, 0.44))
			mb.box(Vector3(0, 0.25, 0), Vector3(1.6, 0.5, 1.6), Color(0.4, 0.38, 0.34))
			mb.box(Vector3(0, 5.6, 0), Vector3(1.5, 0.45, 1.5), Color(0.4, 0.38, 0.34))
		"rubble":
			mb.box(Vector3(0, 0.25, 0), Vector3(1.2, 0.5, 0.9), Color(0.4, 0.38, 0.34), 0.3)
			mb.box(Vector3(0.7, 0.15, 0.4), Vector3(0.6, 0.3, 0.6), Color(0.36, 0.34, 0.3), 1.1)
			mb.box(Vector3(-0.5, 0.2, -0.6), Vector3(0.7, 0.4, 0.5), Color(0.44, 0.41, 0.37), 0.7)
		"weed":
			mb.prism(Vector3.ZERO, 0.12, 0.02, 2.2, 4, Color(0.15, 0.4, 0.25), Color(0.3, 0.6, 0.35))
			mb.prism(Vector3(0.25, 0, 0.1), 0.1, 0.02, 1.6, 4, Color(0.14, 0.36, 0.22), Color(0.26, 0.55, 0.32))
		"crystal":
			glow = true
			mb.prism(Vector3.ZERO, 0.55, 0.0, 3.0, 6, acc.darkened(0.15), acc.lightened(0.3))
			mb.prism(Vector3(0.6, 0, 0.3), 0.36, 0.0, 1.8, 5, acc.darkened(0.25), acc.lightened(0.15), false, 0.6)
			mb.prism(Vector3(-0.5, 0, -0.3), 0.3, 0.0, 1.3, 5, acc.darkened(0.3), acc.lightened(0.1), false, 1.2)
		"gear":
			mb.prism(Vector3(0, 1.4, 0), 1.25, 1.2, 0.5, 14, Color(0.5, 0.36, 0.16), Color(0.56, 0.42, 0.2), false)
			for i in 8:
				var a := TAU * float(i) / 8.0
				mb.box(Vector3(cos(a) * 1.3, 1.4 + sin(a) * 0.0, sin(a) * 1.3), Vector3(0.35, 0.5, 0.35), Color(0.46, 0.32, 0.14), a)
			mb.box(Vector3(0, 0.6, 0), Vector3(0.3, 1.2, 0.3), Color(0.3, 0.22, 0.12))
		"pipe":
			mb.prism(Vector3.ZERO, 0.28, 0.28, 4.4, 8, Color(0.42, 0.3, 0.16), Color(0.5, 0.36, 0.2))
			mb.box(Vector3(0, 1.2, 0), Vector3(0.6, 0.25, 0.6), Color(0.3, 0.22, 0.12))
			mb.box(Vector3(0, 3.2, 0), Vector3(0.6, 0.25, 0.6), Color(0.3, 0.22, 0.12))
		"drift":
			mb.prism(Vector3.ZERO, 1.6, 0.8, 0.9, 7, Color(0.78, 0.83, 0.88), Color(0.95, 0.97, 1.0))
		"brazier":
			glow = true
			mb.prism(Vector3.ZERO, 0.4, 0.5, 0.9, 6, Color(0.3, 0.26, 0.22))
			mb.prism(Vector3(0, 0.9, 0), 0.4, 0.0, 0.9, 6, Color(1.0, 0.55, 0.22), Color(1.0, 0.85, 0.4))
		_:
			mb.prism(Vector3.ZERO, 1.0, 0.5, 0.8, 6, Color(0.4, 0.4, 0.4))
	return [mb, glow]


static func _dress(root: Node3D, L: Dictionary, t: Dictionary, rng: RandomNumberGenerator, wall_h: float) -> void:
	var fams: Array = t["props"]
	var acc: Color = t["accent"]
	var spots: Dictionary = {}          # family -> Array[Transform3D]
	var dist: Dictionary = L["dist"]
	var safe_c: Vector2i = L["safe_cell"]
	for c: Vector2i in dist:
		if c == Vector2i(0, 0) or c == safe_c:
			continue
		var in_boss := BOSS_BLOCK.has_point(c)
		var n := 1 + (rng.randi() % 2)
		if in_boss:
			n = 0
		for i in n:
			if rng.randf() < 0.45:
				continue
			var fam: String = fams[rng.randi() % fams.size()]
			var corner := Vector3(-1.0 if rng.randf() < 0.5 else 1.0, 0, -1.0 if rng.randf() < 0.5 else 1.0)
			var pos := cell_center(c) + Vector3(corner.x * (2.4 + rng.randf() * 0.9), 0, corner.z * (2.4 + rng.randf() * 0.9))
			var sc := 0.8 + rng.randf() * 0.6
			if fam == "column":
				sc = 1.0 if bool(t["ceiling"]) else 0.0
				if wall_h != 7.0:
					sc = 0.8
			if fam == "gear":
				pos.y = 0.0
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * maxf(sc, 0.01)), pos)
			if fam == "pipe":
				xf = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos)
			if not spots.has(fam):
				spots[fam] = []
			(spots[fam] as Array).append(xf)
	# the arena gets a ring of braziers / crystals in the theme's accent family
	var arena_p := cell_center(L["boss_cell"])
	var ring_fam: String = "brazier" if not fams.has("crystal") else "crystal"
	for i in 10:
		var a := TAU * float(i) / 10.0
		var pos := arena_p + Vector3(cos(a) * 10.6, 0, sin(a) * 10.6)
		pos.x = clampf(pos.x, float(BOSS_BLOCK.position.x) * CELL + 2.0, float(BOSS_BLOCK.end.x) * CELL - 2.0)
		pos.z = clampf(pos.z, float(BOSS_BLOCK.position.y) * CELL + 2.0, float(BOSS_BLOCK.end.y) * CELL - 2.0)
		if pos.distance_to(cell_center(L["stairs_cell"])) < 4.0 or pos.distance_to(door_pos(L)) < 4.5:
			continue
		if not spots.has(ring_fam):
			spots[ring_fam] = []
		(spots[ring_fam] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos))
	var glow_mat := glow_material(1.2)
	var lit_mat := lit_material()
	for fam: String in spots:
		var arr: Array = spots[fam]
		if arr.is_empty():
			continue
		var built := _family_mesh(fam, acc, t)
		var mb: MB = built[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mb.mesh(glow_mat if bool(built[1]) else lit_mat)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_" + fam
		mmi.multimesh = mm
		if bool(built[1]):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


## Rough draw-call estimate for a built floor (nodes with meshes, multimesh families, each surface one draw).
static func draw_estimate(root: Node) -> int:
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null and (mi as MeshInstance3D).visible:
			n += m.get_surface_count()
	n += root.find_children("*", "MultiMeshInstance3D", true, false).size()
	return n
