extends RefCounted
## Village / hamlet signatures: the landmarks that make two small places read differently from above. TownIdentity.village_sig picks
## three (hamlet: two) of green, chapel, mill, smithy, jetty, orchard, fieldring, pond, maypole per place (unique sets, by archetype,
## terrain and seed); this builds them. Called from SettlementBuilder._build after the industry yards (TownView.yards), before
## DistrictProps (it keeps off plan["town_claims"]). Preload; no class_name. Own RNG stream (hash([9300, town id])).
## Everything is batched through the builder (MultiMesh per mesh per cell), flat ground pieces (ponds) are dark vertex-coloured
## discs with a muddy feathered rim (never a pale pad: see tools_qa/lint_world "flat" audit).

const TownIdentity := preload("res://scripts/world/town_identity.gd")
const TownView := preload("res://scripts/world/town_identity_view.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const NpcWorldScript := preload("res://scripts/population/npc_world.gd")

const BUSH := "g:region/nature/bush_round"
const OAK := "g:region/nature/oak_b"


static func build(b, root: Node3D, s: Dictionary, plan: Dictionary, prof: Dictionary) -> void:
	var vsig: Dictionary = prof.get("vsig", {})
	if vsig.is_empty() or bool(prof.get("legacy", false)):
		return
	var pl := TownView.Placer.new(b, root, s, plan, prof)
	pl.rng.seed = hash([9300, int(s["id"])])
	if plan.has("town_claims"):
		pl.claims = plan["town_claims"]
	for f: String in vsig["features"]:
		match f:
			"green":
				_green(b, pl)
			"chapel":
				_chapel(b, pl)
			"mill":
				_mill(b, pl)
			"smithy":
				_smithy(b, pl)
			"jetty":
				_pond(b, pl, true)
			"pond":
				_pond(b, pl, false)
			"orchard":
				_orchard(b, pl)
			"fieldring":
				_fieldring(b, pl)
			"maypole":
				_maypole(b, pl, prof)
	pl.flush()


# ---------------------------------------------------------------------------------------------------------------- helpers
## Free ground INSIDE the village (between the square and the edge): off streets, paths, landmarks, house rectangles, water and claims.
static func _inner(b, pl: TownView.Placer, rmin: float, rmax: float, rad: float, flat := 0.7, tries := 220) -> Vector2:
	for _t in tries:
		var ang: float = pl.rng.randf() * TAU
		var p: Vector2 = pl.c + Vector2(cos(ang), sin(ang)) * pl.rng.randf_range(rmin, rmax)
		if _inner_ok(b, pl, p, rad, flat):
			return p
	return Vector2.INF


static func _inner_ok(b, pl: TownView.Placer, p: Vector2, rad: float, flat: float) -> bool:
	var plan: Dictionary = pl.plan
	if CityPlanner.street_distance(plan, p) < rad + 1.5 or CityPlanner.path_distance(plan, p) < rad * 0.6 + 1.0:
		return false
	if CityPlanner.landmark_clearance(plan, p) < rad + 2.0:
		return false
	if WorldGen.is_water(p.x, p.y) or WorldGen.near_water(p.x, p.y, rad + 2.0) or WorldGen.road_distance(p.x, p.y) < rad + 4.0:
		return false
	for lot: Dictionary in plan["lots"]:
		var lp: Vector2 = lot["pos"]
		if lp.distance_to(p) > rad + 16.0:
			continue
		var sz := BuildingProfiles.size_of(String(lot["asset"]))
		if b._rect_pt_dist(p, lp, lot["yaw"], sz.x * 0.5, sz.z * 0.5) < rad + 1.8:
			return false
	for q: Array in pl.claims:
		if p.distance_to(q[0]) < rad + float(q[1]):
			return false
	if NpcWorldScript.in_field(pl.sid, p, rad + 1.0):
		return false
	return b._ground_spread(p, 0.0, Vector3(rad * 2.0, 1.0, rad * 2.0)) <= flat


## Inside the village first, the outskirts when it is full.
static func _find(b, pl: TownView.Placer, rad: float, rmin_in: float, outer_min := 8.0, outer_max := 34.0) -> Vector2:
	var p := _inner(b, pl, rmin_in, float(pl.r) * 0.95, rad)
	if p == Vector2.INF:
		p = pl.spot(pl.wr + outer_min, pl.wr + outer_max, rad)
	return p


## put() only on ground that is free of every other claim (yards, fields, haystacks, other signature props) and claim it small.
static func _put_free(pl: TownView.Placer, id: String, p: Vector2, yaw: float, sc := 1.0, solid := false, rad := 1.0) -> bool:
	if not pl.is_free(p, rad):
		return false
	if pl.put(id, p, yaw, sc, solid):
		pl.claim(p, rad)
		return true
	return false


static func _face(pl: TownView.Placer, p: Vector2) -> float:
	return atan2(pl.c.x - p.x, pl.c.y - p.y)


## A closed rectangle of `id` pieces (hedge or rail fence) with a gap of `gap` pieces on the side facing `yaw`.
static func _rect_ring(pl: TownView.Placer, id: String, p: Vector2, yaw: float, hx: float, hz: float, step: float, scale := 1.0, gap := 2, check := true) -> void:
	var bx := Vector2(cos(yaw), -sin(yaw))
	var bz := Vector2(sin(yaw), cos(yaw))
	for side in 4:
		var along := bx if side % 2 == 0 else bz
		var across := bz if side % 2 == 0 else bx
		var half_len := hx if side % 2 == 0 else hz
		var off := (hz if side % 2 == 0 else hx) * (1.0 if side < 2 else -1.0)
		var cnt := maxi(2, int(half_len * 2.0 / step))
		for k in cnt:
			if side == 0 and absi(k - cnt / 2) < gap:
				continue
			var q: Vector2 = p + across * off + along * (-half_len + step * 0.5 + k * step)
			if not WorldGen.is_water(q.x, q.y) and WorldGen.road_distance(q.x, q.y) > 4.0 and (not check or pl.is_free(q, 0.9)):
				pl.put(id, q, pl.rng.randf() * TAU, scale, false)


# ---------------------------------------------------------------------------------------------------------------- features
## Village green: the square wrapped in a clipped hedge (open at every street), two great trees and flower beds on the common.
static func _green(b, pl: TownView.Placer) -> void:
	var pr: float = pl.plan["plaza_r"]
	var rr := pr + 2.6
	var n := maxi(16, int(TAU * rr / 3.0))
	var rot: float = pl.rng.randf() * TAU
	for i in n:
		var a := rot + TAU * i / n
		var p: Vector2 = pl.c + Vector2(cos(a), sin(a)) * rr
		if CityPlanner.street_distance(pl.plan, p) < 4.6 or CityPlanner.path_distance(pl.plan, p) < 2.0 or CityPlanner.landmark_clearance(pl.plan, p) < 3.0:
			continue
		var blocked := false
		for lot: Dictionary in pl.plan["lots"]:
			var sz := BuildingProfiles.size_of(String(lot["asset"]))
			if b._rect_pt_dist(p, lot["pos"], lot["yaw"], sz.x * 0.5, sz.z * 0.5) < 2.2:
				blocked = true
				break
		if not blocked:
			pl.put(BUSH, p, pl.rng.randf() * TAU, 0.85, false)
	for k in 2:
		var t := _inner(b, pl, pr + 6.0, float(pl.r) * 0.9, 6.0, 0.8)
		if t != Vector2.INF and pl.put(OAK, t, pl.rng.randf() * TAU, 0.95, false):
			pl.claim(t, 6.0)
	for k in 5:
		var q := _inner(b, pl, pr + 4.0, float(pl.r) * 0.9, 2.2, 0.8)
		if q != Vector2.INF and pl.put("flower_bed", q, pl.rng.randf() * TAU, 1.0, false):
			pl.claim(q, 2.2)


## A chapel in its churchyard: low rail fence round a plot, headstones behind, a yew either side of the gate.
static func _chapel(b, pl: TownView.Placer) -> void:
	var p: Vector2 = pl.spot(pl.wr + 8.0, pl.wr + 34.0, 11.0)
	if p == Vector2.INF:
		return
	var yaw := _face(pl, p) + pl.rng.randf_range(-0.3, 0.3)
	var fp: Vector3 = b._footprint("chapel")
	if b._ground_spread(p, yaw, fp) > 2.2:
		return
	b._piece(pl.root, "chapel", p, b._ground_snap(p, yaw, fp), yaw)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var yard: Vector2 = p - fwd * 3.0
	_rect_ring(pl, "fence", yard, yaw, 11.0, 12.0, 3.1, 1.0, 1)
	for k in 6:
		var q: Vector2 = p - fwd * (fp.z * 0.5 + 4.0 + (k / 3) * 3.2) + side * ((k % 3) - 1) * 3.6
		_put_free(pl, "g:region/nature/rock_slab", q, yaw + pl.rng.randf_range(-0.15, 0.15), 0.3, false)
	for sd: float in [-1.0, 1.0]:
		_put_free(pl, "g:region/nature/young_oak", p + fwd * (fp.z * 0.5 + 7.0) + side * sd * 5.2, pl.rng.randf() * TAU, 1.1, false)


## The mill on the best hill near the village: windmill, sacks, a cart and a rail pen.
	pl.claim(p, 12.0)


static func _mill(b, pl: TownView.Placer) -> void:
	var best := Vector2.INF
	var bh := -1.0e9
	for _t in 60:
		var p: Vector2 = pl.spot(pl.wr + 10.0, pl.wr + 48.0, 10.0)
		if p == Vector2.INF:
			continue
		var h := WorldGen.height(p.x, p.y)
		if h > bh and b._ground_spread(p, 0.0, b._footprint("mill")) <= 2.6:
			bh = h
			best = p
	if best == Vector2.INF:
		return
	var yaw: float = pl.rng.randf() * TAU
	b._piece(pl.root, "mill", best, b._ground_snap(best, yaw, b._footprint("mill")), yaw)
	var side := Vector2(cos(yaw), -sin(yaw))
	_put_free(pl, "sack_pile", best + side * 8.5, yaw, 1.0, false)
	_put_free(pl, "sack_pile", best + side * 9.8 + Vector2(1.2, 0.4), yaw + 0.6, 0.9, false)
	_put_free(pl, "cart", best - side * 8.8, yaw + 0.5, 1.0, true)
	_put_free(pl, "hay", best + Vector2.from_angle(yaw + 2.2) * 8.0, yaw, 1.0, false)


## A forge by the road: smithy, anvil, coal and iron, wood, a hand cart, quench barrels.
	pl.claim(best, 11.0)


static func _smithy(b, pl: TownView.Placer) -> void:
	var gi := int(pl.rng.randi() % maxi(1, pl.gates.size()))
	var g: Array = TownView._gate_side(pl, gi, 15.0, 15.0 * (1.0 if pl.rng.randf() < 0.5 else -1.0))
	var p: Vector2 = g[0]
	var fp: Vector3 = b._footprint("blacksmith")
	var tries := 0
	while not pl.is_free(p, 7.0) and tries < 10:
		p += (g[1] as Vector2) * 3.0
		tries += 1
	if not pl.is_free(p, 7.0):
		p = pl.spot(pl.wr + 8.0, pl.wr + 40.0, 7.0)
		if p == Vector2.INF:
			return
	var yaw := _face(pl, p)
	var road_dir: Vector2 = g[2]
	yaw = atan2(-road_dir.x, -road_dir.y) if pl.rng.randf() < 0.0 else yaw
	if b._ground_spread(p, yaw, fp) > 2.2:
		return
	b._piece(pl.root, "blacksmith", p, b._ground_snap(p, yaw, fp), yaw)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	_put_free(pl, "anvil_stump", p + fwd * (fp.z * 0.5 + 1.6) + side * 1.2, yaw, 1.0, false)
	_put_free(pl, "g:region/mine/ore_pile_coal", p - side * (fp.x * 0.5 + 2.4), pl.rng.randf() * TAU, 1.2, false)
	_put_free(pl, "g:region/mine/ore_pile_iron", p - side * (fp.x * 0.5 + 2.6) - fwd * 3.2, pl.rng.randf() * TAU, 1.0, false)
	_put_free(pl, "woodpile", p + side * (fp.x * 0.5 + 2.8), yaw + PI * 0.5, 1.0, false)
	_put_free(pl, "hand_cart", p + fwd * (fp.z * 0.5 + 3.4) - side * 3.0, yaw + 0.4, 1.0, true)
	_put_free(pl, "barrel_cluster", p + fwd * (fp.z * 0.5 + 1.2) - side * 1.6, 0.3, 1.0, false)


## A duck pond (and with `jetty` a bigger mere with a plank pier, a moored rowboat and reeds): dark vertex-coloured disc, muddy rim.
	pl.claim(p, 8.0)


static func _pond(b, pl: TownView.Placer, jetty: bool) -> void:
	var rad := 11.0 if jetty else 6.5
	var p := Vector2.INF
	for _k in 12:
		var cand := _find(b, pl, rad + 3.0, float(pl.plan["plaza_r"]) + 10.0, 10.0, 40.0)
		if cand != Vector2.INF and b._ground_spread(cand, 0.0, Vector3(rad * 2.3, 1.0, rad * 2.3)) <= 0.6:
			p = cand
			break
	if p == Vector2.INF:
		return       # no level ground for water: this village keeps its other signatures
	var y: float = b._ground_snap(p, 0.0, Vector3(rad * 1.6, 1.0, rad * 1.6), 0.0) + 0.1
	var mesh := _pond_mesh(rad)
	var batch: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, pl.rng.randf() * TAU), Vector3(p.x, y, p.y))]
	b._multimesh(pl.root, mesh, batch, false, false, "", false)
	pl.claim(p, rad + 2.0)
	var out_dir := (p - pl.c).normalized() if p.distance_to(pl.c) > 1.0 else Vector2.RIGHT
	for k in 9:
		var a := TAU * k / 9.0 + pl.rng.randf() * 0.3
		pl.put("g:region/nature/grass_tall", p + Vector2.from_angle(a) * (rad * 0.98), pl.rng.randf() * TAU, 1.3, false)
	var duck := _duck_mesh()
	var ducks: Array[Transform3D] = []
	for k in (6 if jetty else 4):
		var q: Vector2 = p + Vector2.from_angle(pl.rng.randf() * TAU) * pl.rng.randf_range(0.5, rad * 0.55)
		ducks.append(Transform3D(Basis(Vector3.UP, pl.rng.randf() * TAU), Vector3(q.x, y + 0.04, q.y)))
	b._multimesh(pl.root, duck, ducks, false, false, "", false)
	if jetty:
		var pier := TownIdentity.mesh_by_id("g:pier")
		if pier != null:
			var box := pier.get_aabb()
			var yaw := atan2(out_dir.x, out_dir.y)
			if box.size.x >= box.size.z:
				yaw += PI * 0.5
			var len := maxf(box.size.x, box.size.z)
			var mid: Vector2 = p - out_dir * (rad - len * 0.5 + 1.5)
			var tf: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y + 0.28, mid.y))]
			b._multimesh(pl.root, pier, tf, false, false)
		var boat := TownIdentity.mesh_by_id("g:rowboat")
		if boat != null:
			var bp: Vector2 = p + Vector2(-out_dir.y, out_dir.x) * (rad * 0.45) - out_dir * 1.0
			var bt: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, pl.rng.randf() * TAU), Vector3(bp.x, y + 0.05, bp.y))]
			b._multimesh(pl.root, boat, bt, false, false)
		pl.put("d:drying_rack", p - out_dir * (rad + 3.0) + Vector2(-out_dir.y, out_dir.x) * 4.0, atan2(out_dir.x, out_dir.y), 1.0, false)
	else:
		pl.put("bench", p + Vector2(-out_dir.y, out_dir.x) * (rad + 1.8), atan2(-out_dir.y, out_dir.x), 1.0, false)


## Rows of fruit trees inside a hedge, baskets and hay beside it.
static func _orchard(b, pl: TownView.Placer) -> void:
	var hx := 14.0
	var hz := 10.5
	var p: Vector2 = pl.spot(pl.wr + 12.0, pl.wr + 46.0, 17.0)
	if p == Vector2.INF:
		return
	var yaw := _face(pl, p) + pl.rng.randf_range(-0.3, 0.3)
	if b._ground_spread(p, yaw, Vector3(hx * 2.0, 1.0, hz * 2.0)) > 1.4:
		return
	var bx := Vector2(cos(yaw), -sin(yaw))
	var bz := Vector2(sin(yaw), cos(yaw))
	for ix in 4:
		for iz in 3:
			var q: Vector2 = p + bx * (ix - 1.5) * 6.4 + bz * (iz - 1.0) * 6.2
			_put_free(pl, "g:region/nature/young_oak", q, pl.rng.randf() * TAU, pl.rng.randf_range(0.9, 1.15), false)
	_rect_ring(pl, BUSH, p, yaw, hx, hz, 3.2, 0.9, 2)
	_put_free(pl, "basket_produce", p + bz * (hz + 2.0) + bx * 4.0, yaw, 1.0, false)
	_put_free(pl, "hay", p + bz * (hz + 2.2) - bx * 3.0, yaw, 1.0, false)


## A ring of crop fields round the village, each in its own hedgerow.
	pl.claim(p, 17.0)


static func _fieldring(b, pl: TownView.Placer) -> void:
	var n := 8
	var a0: float = pl.rng.randf() * TAU
	var tiles: Array[Transform3D] = []
	var mesh := Assets.building_mesh("field_crops")
	for i in n:
		var a := a0 + TAU * i / n
		var yaw := a + PI * 0.5
		var fc: Vector2 = pl.c + Vector2(cos(a), sin(a)) * (pl.wr + 34.0 + pl.rng.randf_range(0.0, 10.0))
		var bx := Vector2(cos(yaw), -sin(yaw))
		var bz := Vector2(sin(yaw), cos(yaw))
		var hx := 15.0
		var hz := 10.0
		if pl._near_gate(a) or not pl.is_free(fc, 17.0) or WorldGen.road_distance(fc.x, fc.y) < 24.0:
			continue
		var ok := true
		var pts: Array[Transform3D] = []
		for ix in 3:
			for iz in 2:
				var tp: Vector2 = fc + bx * (ix - 1.0) * 10.0 + bz * (iz - 0.5) * 10.0
				if b._ground_spread(tp, yaw, Vector3(12.5, 1.0, 12.5)) > 1.0 or WorldGen.is_water(tp.x, tp.y):
					ok = false
				pts.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(tp.x, b._ground_snap(tp, yaw, Vector3(10.0, 1.0, 10.0), 0.05), tp.y)))
		if not ok:
			continue
		tiles.append_array(pts)
		NpcWorldScript.register_field(pl.sid, fc, yaw, Vector2(hx + 1.0, hz + 1.0))
		pl.claim(fc, 18.0)
		_rect_ring(pl, BUSH, fc, yaw, hx + 1.5, hz + 1.5, 3.1, 0.8, 2, false)
	if mesh != null and not tiles.is_empty():
		b._multimesh_cells(pl.root, mesh, tiles, 60.0, 0.0, false)


## A maypole on the common: striped ribbons in the village colours, a ring of flower beds.
static func _maypole(b, pl: TownView.Placer, prof: Dictionary) -> void:
	var p := _find(b, pl, 4.5, float(pl.plan["plaza_r"]) + 6.0, 6.0, 26.0)
	if p == Vector2.INF:
		return
	var banner: Array = prof["banner"]
	var mesh := _maypole_mesh(banner[0], banner[1])
	var y: float = b._ground_snap(p, 0.0, Vector3(5.0, 1.0, 5.0), 0.0)
	var tf: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, pl.rng.randf() * TAU), Vector3(p.x, y, p.y))]
	b._multimesh(pl.root, mesh, tf, true, false, "", true)
	pl.claim(p, 5.0)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = 6.0
	shape.shape = cyl
	body.position = Vector3(p.x, y + 3.0, p.y)
	body.add_child(shape)
	pl.root.add_child(body)
	for k in 4:
		var q: Vector2 = p + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 4.2
		if pl.is_free(q, 1.2) or _inner_ok(b, pl, q, 1.2, 0.8):
			pl.put("flower_bed", q, pl.rng.randf() * TAU, 0.9, false)


# ---------------------------------------------------------------------------------------------------------------- meshes
static var _pond_cache := {}
static var _duck: ArrayMesh
static var _pole_cache := {}


static func _pond_mesh(rad: float) -> ArrayMesh:
	var key := roundi(rad * 10.0)
	if _pond_cache.has(key):
		return _pond_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deep := Color(0.13, 0.30, 0.36)
	var shallow := Color(0.22, 0.42, 0.44)
	var mud := Color(0.30, 0.25, 0.17)
	var segs := 28
	# (radius fraction, colour, height): water, shallows, mud bank that dips under the grass (the blend)
	var rings: Array = [[0.0, deep, 0.0], [0.55, deep, 0.0], [0.82, shallow, 0.0], [0.95, mud, -0.02], [1.1, mud, -0.12]]
	for r in rings.size() - 1:
		var r0: Array = rings[r]
		var r1: Array = rings[r + 1]
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var pts := [[float(r0[0]), a0, r0], [float(r1[0]), a0, r1], [float(r1[0]), a1, r1], [float(r0[0]), a1, r0]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var e: Array = pts[idx]
				var info: Array = e[2]
				st.set_color(info[1])
				st.add_vertex(Vector3(cos(float(e[1])) * rad * float(e[0]), float(info[2]), sin(float(e[1])) * rad * float(e[0])))
	var m := TownIdentity._finish(st)
	m.resource_name = "village_pond"
	_pond_cache[key] = m
	return m


static func _duck_mesh() -> ArrayMesh:
	if _duck != null:
		return _duck
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	TownIdentity._box(st, Vector3(0, 0.16, 0), Vector3(0.42, 0.26, 0.62), Color(0.93, 0.92, 0.88))
	TownIdentity._box(st, Vector3(0, 0.42, 0.26), Vector3(0.17, 0.2, 0.17), Color(0.2, 0.42, 0.28))
	TownIdentity._box(st, Vector3(0, 0.40, 0.38), Vector3(0.08, 0.05, 0.12), Color(0.95, 0.62, 0.15))
	_duck = TownIdentity._finish(st)
	_duck.resource_name = "village_duck"
	return _duck


static func _maypole_mesh(c1: Color, c2: Color) -> ArrayMesh:
	var key := "%s%s" % [c1.to_html(false), c2.to_html(false)]
	if _pole_cache.has(key):
		return _pole_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.52, 0.38, 0.22)
	TownIdentity._box(st, Vector3(0, 3.2, 0), Vector3(0.26, 6.4, 0.26), wood)
	TownIdentity._box(st, Vector3(0, 6.45, 0), Vector3(0.9, 0.14, 0.9), Color(0.35, 0.6, 0.28))
	TownIdentity._box(st, Vector3(0, 6.7, 0), Vector3(0.4, 0.3, 0.4), Color(0.9, 0.75, 0.3))
	var cols := [c1, c2, Color(0.95, 0.9, 0.8)]
	for k in 8:
		var a := TAU * k / 8.0
		var top := Vector3(cos(a) * 0.15, 6.3, sin(a) * 0.15)
		var foot := Vector3(cos(a + 0.5) * 2.7, 0.35, sin(a + 0.5) * 2.7)
		var tang := Vector3(-sin(a), 0.0, cos(a)) * 0.09
		var col: Color = cols[k % 3]
		for sg in [1.0, -1.0]:
			var q := [top - tang, top + tang, foot + tang, foot - tang]
			var order := [0, 1, 2, 0, 2, 3] if sg > 0.0 else [0, 2, 1, 0, 3, 2]
			for idx in order:
				st.set_color(col)
				st.add_vertex(q[idx])
	var m := TownIdentity._finish(st)
	m.resource_name = "village_maypole"
	_pole_cache[key] = m
	return m
