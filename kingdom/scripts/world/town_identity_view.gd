extends RefCounted
## The visible, placed part of a town's identity profile (scripts/world/town_identity.gd): its wall style and the yards on its
## outskirts that carry its dominant industry (mine head-frame and spoil heaps, granary and haystacks, boatyard or quay, watch
## towers, caravan camp, charcoal kilns, salt pans, sheep pens ...). Called from SettlementBuilder._build (walls, yards).
## Preload; no class_name. Everything is batched: one MultiMesh per mesh per 40 m cell (a handful of draw calls a town), render-only
## except the pieces a player could walk into (palisade, hedge, barns, towers), which get a box collider like the stone wall does.
## Own RNG stream (hash([9100, town id])): the town's other random layout is untouched. Props are placed by rejection sampling:
## off roads, water, fields, steep ground and each other.

const TownIdentity := preload("res://scripts/world/town_identity.gd")
const NpcWorldScript := preload("res://scripts/population/npc_world.gd")
const GEN := "res://assets/generated/"
const GATE_GAP_WALLED := 8.0         # half width of the opening left in a palisade / hedge ring at a gate road (m)
const GATE_GAP_OPEN := 6.0

static func fitted(path: String, target := 0.0) -> ArrayMesh:
	return TownIdentity.fitted(path, target)


# ================================================================ walls
static func walls(b, root: Node3D, s: Dictionary, plan: Dictionary, prof: Dictionary) -> void:
	var style := String(prof.get("wall", "stone")) if not bool(prof.get("legacy", false)) else "stone"
	var c: Vector2 = s["pos"]
	var walled: bool = plan["walls"]
	var gates: Array = plan["gates"]
	match style:
		"stone":
			if walled:
				b._wall_ring(root, c, plan["wall_radius"], gates, 40, 5, float(prof.get("tower", 1.0)) if not bool(prof.get("legacy", false)) else 1.0, 1.0)
		"low":
			if walled:
				b._wall_ring(root, c, plan["wall_radius"], gates, 40, 5, 0.0, 0.5)
		"palisade":
			_ring(b, root, s, plan, fitted(GEN + "region/ruins/bandit_palisade.glb"), 4.1, 1.75, 3.4, true, 1.0)
		"hedge":
			_ring(b, root, s, plan, fitted(GEN + "region/nature/bush_round.glb"), 3.0, 1.0, 1.4, false, 1.45)
		"runestones":
			_ring(b, root, s, plan, fitted(GEN + "runestone.glb"), 15.0, 1.0, 1.0, false, 1.05)


## A ring of pieces around the town with an opening at every gate road. `seg` is the arc length one piece covers; with `collide`
## the piece is a wall section stretched along its long side to the chord (palisade), otherwise it is a free-standing prop
## (bush, standing stone) of uniform scale `wscale`. The ring follows the wall line (unwalled towns: 1.12 x the radius).
static func _ring(b, root: Node3D, s: Dictionary, plan: Dictionary, mesh: Mesh, seg: float, hscale: float, wscale: float, collide: bool, _unused := 1.0) -> void:
	if mesh == null:
		return
	var c: Vector2 = s["pos"]
	var walled: bool = plan["walls"]
	var rad: float = float(plan["wall_radius"]) if walled else float(s["radius"]) * 1.12
	var box := mesh.get_aabb()
	var along_x := box.size.x >= box.size.z
	var native_len := maxf(box.size.x, box.size.z)
	var n := maxi(12, roundi(TAU * rad / seg))
	var gap := GATE_GAP_WALLED if walled else GATE_GAP_OPEN
	var gates: Array = plan["gates"]
	var list: Array[Transform3D] = []
	var half_h := box.size.y * hscale
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector2(cos(a0), sin(a0)) * rad
		var p1 := c + Vector2(cos(a1), sin(a1)) * rad
		var mp := (p0 + p1) * 0.5
		var am := (a0 + a1) * 0.5
		var in_gap := false
		for g in gates:
			if absf(wrapf(am - float(g), -PI, PI)) * rad < gap + seg * 0.5:
				in_gap = true
				break
		if in_gap:
			continue
		if WorldGen.is_water(mp.x, mp.y) or WorldGen.road_distance(mp.x, mp.y) < 5.0:
			continue
		var near_mill := false
		for mq: Vector2 in plan.get("mill_spots", []):
			if mq.distance_to(mp) < 11.0:
				near_mill = true
		for hq: Vector2 in plan.get("field_stacks", []):
			if hq.distance_to(mp) < 5.0:
				near_mill = true
		if not collide:
			var lo := INF
			var hi := -INF
			for off: Vector2 in [Vector2(1.6, 0), Vector2(-1.6, 0), Vector2(0, 1.6), Vector2(0, -1.6)]:
				var hh := WorldGen.height(mp.x + off.x, mp.y + off.y)
				lo = minf(lo, hh)
				hi = maxf(hi, hh)
			if hi - lo > 0.9:
				near_mill = true      # too steep for a bush or a standing stone to sit on
		if near_mill or absf(WorldGen.height(p0.x, p0.y) - WorldGen.height(p1.x, p1.y)) > (2.0 if collide else 1.0):
			continue
		var dir := p1 - p0
		var chord := dir.length()
		var h := minf(WorldGen.height(mp.x, mp.y), minf(WorldGen.height(p0.x, p0.y), WorldGen.height(p1.x, p1.y))) - 0.1
		var basis: Basis
		if collide:
			var yaw := atan2(dir.x, dir.y) + (PI * 0.5 if along_x else 0.0)
			var sx := chord / maxf(native_len, 0.01)
			basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sx, hscale, 1.0) if along_x else Vector3(1.0, hscale, sx))
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.6, half_h, maxf(0.5, chord))
			shape.shape = bx
			body.position = Vector3(mp.x, h + half_h * 0.5, mp.y)
			body.rotation.y = atan2(dir.x, dir.y)
			body.add_child(shape)
			root.add_child(body)
		else:
			basis = Basis(Vector3.UP, i * 1.7) * Basis.from_scale(Vector3(wscale, wscale * hscale, wscale))
		list.append(Transform3D(basis, Vector3(mp.x, h, mp.y)))
	if list.is_empty():
		return
	if not collide:
		# Hedges and standing stones: a box collider each, so the ring is a real boundary.
		b._add_instance_colliders(root, mesh, list)
	b._multimesh_cells(root, mesh, list, 70.0, 0.0, false, true, Color(0.62, 0.45, 0.3) if collide else Color.WHITE)


# ================================================================ yards
class Placer extends RefCounted:
	var b
	var root: Node3D
	var s: Dictionary
	var plan: Dictionary
	var prof: Dictionary
	var c: Vector2
	var r: float
	var wr: float
	var rng := RandomNumberGenerator.new()
	var claims: Array = []                 # [centre Vector2, radius]
	var batches := {}                      # id -> {mesh, list: Array[Transform3D], solid}
	var gates: Array = []
	var sid := 0

	func _init(builder, node: Node3D, st: Dictionary, pl: Dictionary, pr: Dictionary) -> void:
		b = builder
		root = node
		s = st
		plan = pl
		prof = pr
		c = st["pos"]
		r = float(st["radius"])
		wr = float(pl["wall_radius"]) if pl["walls"] else r * 1.1
		gates = pl["gates"]
		sid = int(st["id"])
		rng.seed = hash([9100, sid])
		for mp: Vector2 in pl.get("mill_spots", []):
			claims.append([mp, 12.0])          # the builder's windmills
		for op: Vector2 in pl.get("outskirt_spots", []):
			claims.append([op, 4.0])           # the gate-road trade
		for hp: Vector2 in pl.get("field_stacks", []):
			claims.append([hp, 4.5])           # and the haystacks at the field corners

	## Free ground for a prop of clear radius `rad` at p: dry, off roads, off fields and other yard pieces.
	func is_free(p: Vector2, rad: float) -> bool:
		if p.distance_to(c) < wr + rad + 3.0:
			return false
		if WorldGen.is_water(p.x, p.y) or WorldGen.near_water(p.x, p.y, rad + 2.0):
			return false
		if WorldGen.road_distance(p.x, p.y) < rad + 4.5:
			return false
		if NpcWorldScript.in_field(sid, p, rad + 1.5):
			return false
		for q: Array in claims:
			if p.distance_to(q[0]) < rad + float(q[1]):
				return false
		return true

	## A free spot at a random angle (optionally within `around` of angle `ang0`) between radii rmin..rmax; Vector2.INF when none.
	func spot(rmin: float, rmax: float, rad: float, ang0 := 0.0, around := PI, keep_off_gates := true, tries := 40) -> Vector2:
		for _t in tries:
			var ang := ang0 + rng.randf_range(-around, around)
			if keep_off_gates and _near_gate(ang):
				continue
			var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(rmin, rmax)
			if is_free(p, rad):
				return p
		return Vector2.INF

	func _near_gate(ang: float) -> bool:
		for g in gates:
			if absf(wrapf(ang - float(g), -PI, PI)) < 0.32:
				return true
		return false

	func claim(p: Vector2, rad: float) -> void:
		claims.append([p, rad])

	## Queue one instance of `id` (a SettlementBuilder key or "g:<path>") at p, snapped to the lowest ground under it.
	## false (nothing queued) on ground too steep for it.
	func put(id: String, p: Vector2, yaw: float, sc := 1.0, solid := false, lift := 0.0) -> bool:
		var mesh := TownIdentity.mesh_by_id(id)
		if mesh == null:
			return false
		var size := mesh.get_aabb().size * sc
		if not b._spot_ok(p, yaw, size):
			return false
		var y: float = b._ground_snap(p, yaw, size, 0.05) + lift
		if not batches.has(id):
			batches[id] = {"mesh": mesh, "list": [] as Array[Transform3D], "solid": false}
		(batches[id]["list"] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * sc), Vector3(p.x, y, p.y)))
		if solid:
			batches[id]["solid"] = true
		return true

	func flush() -> void:
		plan["town_claims"] = claims     # DistrictProps keeps its props off these
		for id: String in batches:
			var e: Dictionary = batches[id]
			var list: Array[Transform3D] = []
			list.assign(e["list"])
			b._multimesh_cells(root, e["mesh"], list, 40.0, 0.0, false)
			if bool(e["solid"]):
				b._add_instance_colliders(root, e["mesh"], list)


static func yards(b, root: Node3D, s: Dictionary, plan: Dictionary, prof: Dictionary) -> void:
	if bool(prof.get("legacy", false)):
		return
	var pl := Placer.new(b, root, s, plan, prof)
	var seen := {}
	for y: Dictionary in prof.get("yards", []):
		var kind := String(y.get("kind", ""))
		var n := int(y.get("n", 1))
		var key := "%s%d" % [kind, n]
		if seen.has(key):
			continue
		seen[key] = true
		match kind:
			"stacks":
				_stacks(pl, n)
			"granary":
				_granary(pl, n)
			"mills":
				_mills(b, pl, n)
			"pens":
				_pens(pl, n)
			"great_tree":
				_great_tree(b, pl)
			"mine_yard":
				_mine_yard(pl)
			"spoil":
				_spoil(pl, n, String(y.get("mesh", "ore")))
			"kilns":
				_kilns(pl, n)
			"wagon_park":
				_wagon_park(pl, n)
			"caravan_camp":
				_caravan_camp(pl)
			"toll":
				_toll(pl)
			"watch":
				_watch(b, pl, n, bool(y.get("tall", false)))
			"waterfront":
				_waterfront(pl)
			"salt_pans":
				_salt_pans(pl, n)
	pl.flush()


# --- farming --------------------------------------------------------------------------------------------------------------
static func _stacks(pl: Placer, n: int) -> void:
	for i in n:
		var p := pl.spot(pl.wr + 8.0, pl.wr + 30.0, 2.6)
		if p == Vector2.INF:
			continue
		if pl.put("haystack", p, pl.rng.randf() * TAU, 1.0, true):
			pl.claim(p, 2.6)
			for k in 2:
				var q := p + Vector2.from_angle(pl.rng.randf() * TAU) * 3.8
				if pl.is_free(q, 1.3) and pl.put("hay", q, pl.rng.randf() * TAU, 1.0, false):
					pl.claim(q, 1.3)


static func _granary(pl: Placer, n: int) -> void:
	for i in n:
		var p := pl.spot(pl.wr + 14.0, pl.wr + 36.0, 8.0)
		if p == Vector2.INF:
			continue
		var yaw := atan2(pl.c.x - p.x, pl.c.y - p.y) + pl.rng.randf_range(-0.4, 0.4)
		if pl.put("stable", p, yaw, 1.3, true):
			pl.claim(p, 8.5)
			for k in 3:
				var q := p + Vector2.from_angle(yaw + 1.2 + k * 1.7) * 9.5
				if pl.is_free(q, 1.4) and pl.put("sack_pile" if k == 2 else "hay", q, pl.rng.randf() * TAU, 1.0, false):
					pl.claim(q, 1.4)


static func _mills(b, pl: Placer, n: int) -> void:
	for i in n:
		var p := pl.spot(pl.wr + 12.0, pl.wr + 40.0, 9.0)
		if p == Vector2.INF:
			continue
		var yaw := pl.rng.randf() * TAU
		if b._ground_spread(p, yaw, b._footprint("mill")) > 3.0:
			continue
		pl.claim(p, 9.5)
		b._piece(pl.root, "mill", p, b._ground_snap(p, yaw, b._footprint("mill")), yaw)


static func _pens(pl: Placer, n: int) -> void:
	for i in n:
		var p := pl.spot(pl.wr + 14.0, pl.wr + 40.0, 10.0)
		if p == Vector2.INF:
			continue
		var yaw := pl.rng.randf() * TAU
		var bx := Vector2(cos(yaw), -sin(yaw))
		var bz := Vector2(sin(yaw), cos(yaw))
		var hx := 7.0
		var hz := 5.0
		if pl.b._ground_spread(p, yaw, Vector3(hx * 2.0, 1.0, hz * 2.0)) > 1.2:
			continue
		var placed := 0
		for side in 4:
			var along := bx if side % 2 == 0 else bz
			var across := bz if side % 2 == 0 else bx
			var half_len := hx if side % 2 == 0 else hz
			var off := (hz if side % 2 == 0 else hx) * (1.0 if side < 2 else -1.0)
			var cnt := int(half_len * 2.0 / 3.1)
			for k in cnt:
				if side == 0 and k == cnt / 2:
					continue   # the gate
				var q := p + across * off + along * (-half_len + 1.55 + k * 3.1)
				if pl.put("fence", q, yaw + (0.0 if side % 2 == 0 else PI * 0.5), 1.0, true):
					placed += 1
		if placed > 6:
			pl.claim(p, 10.5)
			for k in 3:
				var q2 := p + bx * (k - 1) * 3.6 + bz * pl.rng.randf_range(-1.5, 1.5)
				pl.put("hay" if k != 1 else "water_trough", q2, pl.rng.randf() * TAU, 1.0, false)


static func _great_tree(b, pl: Placer) -> void:
	var p := pl.spot(pl.wr + 10.0, pl.wr + 26.0, 9.0)
	if p == Vector2.INF:
		return
	var mesh := fitted(GEN + "region/nature/oak_a.glb")
	if mesh == null:
		return
	var sc := 2.0
	var yaw := pl.rng.randf() * TAU
	if not pl.put("g:region/nature/oak_a", p, yaw, sc, false):
		return
	pl.claim(p, 9.0)
	# A trunk-sized collider (the canopy is walked under).
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.3
	cyl.height = 3.0
	shape.shape = cyl
	body.position = Vector3(p.x, WorldGen.height(p.x, p.y) + 1.5, p.y)
	body.add_child(shape)
	pl.root.add_child(body)


# --- mining ---------------------------------------------------------------------------------------------------------------
static func _axis_spot(pl: Placer, sign_i: float, rmin: float, rmax: float, rad: float, lat_max := 22.0) -> Vector2:
	var axis := TownIdentity.main_axis(pl.gates)
	var n := Vector2(-axis.y, axis.x)
	for _t in 80:
		var p := pl.c + axis * sign_i * pl.rng.randf_range(rmin, rmax) + n * pl.rng.randf_range(-lat_max, lat_max)
		if pl.is_free(p, rad):
			return p
	return Vector2.INF


static func _mine_yard(pl: Placer) -> void:
	# The yard stands off the road axis (on a ridge there is no room on it) and its rails run AWAY from the road.
	var axis0 := TownIdentity.main_axis(pl.gates)
	var nrm := Vector2(-axis0.y, axis0.x)
	var made := 0
	for sg: float in [1.0, -1.0]:
		for lat_sign: float in [1.0, -1.0]:
			if made >= 2:
				break
			var p := Vector2.INF
			for _t in 60:
				var cand := pl.c + axis0 * sg * pl.rng.randf_range(pl.wr * 0.3, pl.wr + 40.0) + nrm * lat_sign * pl.rng.randf_range(pl.wr * 0.5 + 6.0, pl.wr + 34.0)
				if cand.distance_to(pl.c) > pl.wr + 14.0 and pl.is_free(cand, 11.0):
					p = cand
					break
			if p == Vector2.INF:
				continue
			var axis := (p - pl.c).normalized()
			var side := Vector2(-axis.y, axis.x)
			var yaw := atan2(axis.x, axis.y)
			var at := func(u: float, v: float) -> Vector2:
				return p + axis * u + side * v
			if not pl.put("g:region/mine/mine_winch", p, yaw + PI * 0.5, 2.0, true):
				continue
			made += 1
			pl.claim(p, 15.0)
			for k in 4:
				pl.put("g:region/mine/rail_straight", at.call(5.0 + k * 4.0, 0.0), yaw, 1.0, false)
			for k in 2:
				pl.put("g:region/mine/mine_cart", at.call(7.0 + k * 5.0, 0.0), yaw, 1.15, false, 0.25)
			pl.put("g:region/mine/tunnel_support", at.call(22.0, 0.0), yaw, 1.3, false)
			pl.put("g:region/mine/miners_hut", at.call(-7.0, 8.0), yaw + PI * 0.5, 1.0, true)
			pl.put("g:region/mine/ore_pile_iron", at.call(12.0, 7.5), pl.rng.randf() * TAU, 1.6, false)
			pl.put("g:region/mine/ore_pile_coal", at.call(16.0, -7.5), pl.rng.randf() * TAU, 1.6, false)
			pl.put("g:region/mine/mine_props", at.call(-6.0, -6.5), pl.rng.randf() * TAU, 1.0, false)
			pl.put("barrel_cluster", at.call(-3.0, 6.0), pl.rng.randf() * TAU, 1.0, false)


static func _spoil(pl: Placer, n: int, kind: String) -> void:
	for i in n:
		var sg := 1.0 if i % 2 == 0 else -1.0
		var p := _axis_spot(pl, sg, pl.wr + 8.0, pl.wr + 50.0, 6.0, 30.0)
		if p == Vector2.INF:
			p = pl.spot(pl.wr + 10.0, pl.wr + 50.0, 6.0)
		if p == Vector2.INF:
			continue
		if kind == "rock":
			var ok := false
			for k in 4:
				var q := p + Vector2.from_angle(k * 1.57 + 0.4) * (0.0 if k == 0 else 7.0)     # spaced: the slabs are up to 6 m wide
				ok = pl.put("g:region/nature/rock_slab", q, pl.rng.randf() * TAU, pl.rng.randf_range(2.0, 2.8), false) or ok
			if ok:
				pl.claim(p, 10.0)
		else:
			var mesh_id := "g:region/mine/ore_pile_coal" if i % 2 == 0 else "g:region/mine/ore_pile_iron"
			if pl.put(mesh_id, p, pl.rng.randf() * TAU, pl.rng.randf_range(2.4, 3.4), false):
				pl.claim(p, 6.0)


static func _kilns(pl: Placer, n: int) -> void:
	for i in n:
		var p := pl.spot(pl.wr + 10.0, pl.wr + 46.0, 5.0)
		if p == Vector2.INF:
			continue
		if pl.put("g:region/mine/ore_pile_coal", p, pl.rng.randf() * TAU, 1.9, false):
			pl.claim(p, 5.0)
			pl.put("woodpile", p + Vector2.from_angle(pl.rng.randf() * TAU) * 4.4, pl.rng.randf() * TAU, 1.0, false)


# --- roads, camps, towers, water -------------------------------------------------------------------------------------------
static func _gate_side(pl: Placer, gi: int, dist: float, lateral: float) -> Array:
	var ga := float(pl.gates[gi % pl.gates.size()])
	var dir := Vector2(cos(ga), sin(ga))
	var side := Vector2(-dir.y, dir.x)
	return [pl.c + dir * (pl.wr + dist) + side * lateral, dir, side]


static func _wagon_park(pl: Placer, n: int) -> void:
	for i in n:
		var g: Array = _gate_side(pl, i, 16.0 + i * 7.0, (19.0 + pl.rng.randf() * 4.0) * (1.0 if i % 2 == 0 else -1.0))
		var p: Vector2 = g[0]
		if not pl.is_free(p, 3.4) and not pl.is_free(p, 2.4):
			continue
		var ids := ["covered_wagon", "cart", "g:region/road/caravan_wagon", "cart"]
		var yaw := atan2((g[1] as Vector2).x, (g[1] as Vector2).y) + pl.rng.randf_range(-0.5, 0.5) + (0.0 if i % 2 == 0 else PI)
		if pl.put(ids[i % ids.size()], p, yaw, 1.0, true):
			pl.claim(p, 3.4)
			pl.put("hay", p + (g[2] as Vector2) * 3.4, pl.rng.randf() * TAU, 1.0, false)


static func _caravan_camp(pl: Placer) -> void:
	var gi := 1 if pl.gates.size() > 1 else 0
	var g: Array = _gate_side(pl, gi, 48.0, 36.0)
	var p: Vector2 = g[0]
	for _t in 14:
		if pl.is_free(p, 14.0):
			break
		p += (g[2] as Vector2) * 4.0 + (g[1] as Vector2) * 3.0
	if not pl.is_free(p, 12.0):
		return
	pl.claim(p, 14.0)
	pl.put("g:region/ruins/campfire", p, 0.0, 1.0, false)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var q := p + Vector2.from_angle(a) * 8.0
		pl.put("g:region/road/caravan_wagon", q, a + PI * 0.5, 1.0, true)
	for k in 2:
		var q2 := p + Vector2.from_angle(2.6 + k * 1.9) * 5.5
		pl.put("g:region/ruins/bandit_tent", q2, 2.6 + k * 1.9, 1.0, true)
	pl.put("hay", p + Vector2(3.0, 3.0), 0.7, 1.0, false)
	pl.put("barrel_cluster", p + Vector2(-3.4, 2.4), 0.2, 1.0, false)


static func _toll(pl: Placer) -> void:
	var g: Array = _gate_side(pl, 0, 8.0, 6.2)
	var p: Vector2 = g[0]
	var yaw := atan2(-(g[2] as Vector2).x, -(g[2] as Vector2).y)
	if WorldGen.is_water(p.x, p.y):
		return
	if pl.put("g:region/road/toll_booth", p, yaw, 1.15, true):
		pl.claim(p, 3.4)
	var q: Vector2 = (_gate_side(pl, 0, 90.0, 4.4) as Array)[0]
	if not WorldGen.is_water(q.x, q.y):
		pl.put("g:region/road/milestone", q, yaw, 1.3, false)


static func _watch(b, pl: Placer, n: int, tall: bool) -> void:
	var mesh := Assets.building_mesh("watchtower")
	if mesh == null:
		return
	for i in n:
		var p := Vector2.INF
		var yaw := 0.0
		if i < pl.gates.size():
			# Outposts either side of a gate road.
			var g: Array = _gate_side(pl, i, 12.0 + 6.0 * (i % 2), (13.0 + pl.rng.randf() * 4.0) * (1.0 if i % 2 == 0 else -1.0))
			if pl.is_free(g[0], 4.2):
				p = g[0]
		if p == Vector2.INF:
			p = pl.spot(pl.wr + 6.0, pl.wr + 30.0, 4.5)
		if p == Vector2.INF:
			continue
		yaw = atan2(pl.c.x - p.x, pl.c.y - p.y)
		if b._ground_spread(p, yaw, b._footprint("watchtower")) > 2.0:
			continue
		pl.claim(p, 4.5)
		b._piece(pl.root, "watchtower", p, b._ground_snap(p, yaw, b._footprint("watchtower")), yaw)


static func _waterfront(pl: Placer) -> void:
	var w := TownIdentity.water_info(pl.s)
	var wd := float(w["dist"])
	if wd < pl.wr + 220.0:
		_real_quay(pl, w)
		return
	# Dry boatyard on the downhill (open) side of the town: hulls on the ground, nets on racks, barrels and rope.
	var axis := TownIdentity.main_axis(pl.gates)
	var n := Vector2(-axis.y, axis.x)
	var side := 1.0
	var h1 := WorldGen.height((pl.c + n * pl.r).x, (pl.c + n * pl.r).y)
	var h2 := WorldGen.height((pl.c - n * pl.r).x, (pl.c - n * pl.r).y)
	side = 1.0 if h1 < h2 else -1.0
	var base := pl.c + n * side * (pl.wr + 20.0)
	var placed := 0
	for i in 5:
		var p := base + axis * (i - 2) * 9.0 + n * side * pl.rng.randf_range(0.0, 6.0)
		if not pl.is_free(p, 2.6):
			continue
		var yaw := atan2(n.x, n.y) * 1.0 + PI * 0.5 + pl.rng.randf_range(-0.25, 0.25)
		if pl.put("g:rowboat", p, yaw, 1.6, true, 0.15):
			pl.claim(p, 2.8)
			placed += 1
			var q := p + n * side * 3.6
			if pl.is_free(q, 1.3):
				pl.put("d:drying_rack" if i % 2 == 0 else "barrel_cluster", q, yaw, 1.0, false)


static func _real_quay(pl: Placer, w: Dictionary) -> void:
	# Water is close: a pier from the shore, a moored boat and a stack of crates (the Lakeside recipe).
	var target: Vector2 = w["point"]
	var dir := (target - pl.c).normalized()
	var shore := Vector2.INF
	var t := pl.wr
	while t < pl.wr + 260.0:
		var q := pl.c + dir * t
		if WorldGen.is_water(q.x, q.y):
			shore = pl.c + dir * (t - 1.0)
			break
		t += 1.0
	if shore == Vector2.INF:
		return
	var level := WorldGen.water_level_at(shore.x, shore.y)
	var mesh := fitted(GEN + "pier.glb")
	if mesh == null:
		return
	var yaw := atan2(dir.x, dir.y)
	var mid := shore + dir * 7.0
	var y := level + 0.6
	var batch: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y, mid.y))]
	pl.b._multimesh(pl.root, mesh, batch, false, true)
	var boat := fitted(GEN + "rowboat.glb")
	if boat != null:
		var bp := shore + dir * 6.0 + Vector2(-dir.y, dir.x) * 5.0
		var bb: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, yaw + 0.3), Vector3(bp.x, level - 0.05, bp.y))]
		pl.b._multimesh(pl.root, boat, bb, false)
	pl.claim(shore, 14.0)


static func _salt_pans(pl: Placer, n: int) -> void:
	var mesh := _slab()
	var axis := TownIdentity.main_axis(pl.gates)
	var nrm := Vector2(-axis.y, axis.x)
	var h1 := WorldGen.height((pl.c + nrm * pl.r).x, (pl.c + nrm * pl.r).y)
	var h2 := WorldGen.height((pl.c - nrm * pl.r).x, (pl.c - nrm * pl.r).y)
	var side := 1.0 if h1 < h2 else -1.0
	var list: Array[Transform3D] = []
	var yaw := atan2(axis.x, axis.y)
	var base := pl.c + nrm * side * (pl.wr + 34.0)
	for i in n * 3:
		var p := base + axis * (i % n - n / 2.0) * 13.0 + nrm * side * (i / n) * 11.0
		if not pl.is_free(p, 6.0):
			continue
		if pl.b._ground_spread(p, yaw, Vector3(10.0, 0.4, 8.0)) > 0.25:
			continue
		list.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.12, p.y)))
		pl.claim(p, 6.0)
	if not list.is_empty():
		pl.b._multimesh_cells(pl.root, mesh, list, 60.0, 0.0, false, false)


static var _slab_mesh: ArrayMesh


## A shallow rimmed pan: a pale salt crust inside a low earth rim.
static func _slab() -> ArrayMesh:
	if _slab_mesh != null:
		return _slab_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := Color(0.55, 0.43, 0.3)
	var salt := Color(0.95, 0.94, 0.9)
	TownIdentity._box(st, Vector3(0, 0.15, 0), Vector3(9.0, 0.3, 7.0), rim)
	TownIdentity._box(st, Vector3(0, 0.27, 0), Vector3(8.0, 0.14, 6.0), salt)
	_slab_mesh = TownIdentity._finish(st)
	return _slab_mesh
