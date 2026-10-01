extends RefCounted
## District prop sets and house details for one settlement (docs/design/VERTICAL_SLICE.md P1 districts). Called by
## SettlementBuilder._build after the gate market and before the decals/contact shadows are flushed. Preload; no class_name.
##
## What it places (existing assets only, batched: one MultiMesh per mesh per 40 m cell, so a town stays a handful of
## draw calls per prop kind, never one per prop):
##   * house details: scripts/world/house_details.gd attachments per lot (district + wealth + the lot's seed)
##   * per-district street furniture and yard props (SETS below)
##   * a drill yard in the military ward, communal wells in the poor quarter, muddy lane decals there
## Everything is placed by rejection sampling against a Ctx: lots (oriented rectangles), streets, door paths, landmarks,
## the plaza ring, the wall, the gate-market stalls and everything already claimed, so nothing overlaps or blocks a door.
## Own RNG streams (8101 + town id): the town's other random layout is untouched.

const Districts := preload("res://scripts/world/districts.gd")
const HouseDetails := preload("res://scripts/world/house_details.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const GEN := "res://assets/generated/"
const CELL := 40.0
## Decal budget. The Mobile renderer applies at most 8 decals to one mesh, and the town's own wall (1 per 32 m block) and
## ground (5 per 64 m chunk) decals are already near that: so only a few roof patches (downward projectors) and at most
## MUD_PER_CHUNK mud decals per 64 m terrain chunk are added here. LOW builds none (TownDecals are not drawn there).
const DECAL_CAP := 8
## Smoking chimney stacks per town (16 particles each, culled at 140 m): craft, poor and military lots only.
const SMOKE_CAP := 10
const MUD_PER_CHUNK := 2

## district -> [{id, n (per lot of that district), r (clear radius m), from: edge|yard, face: bool, solid: bool}]
## id: a SettlementBuilder building key, or "g:<path under assets/generated>" for a raw GLB.
const SETS := {
	"market": [
		{"id": "signpost", "n": 0.30, "r": 0.9, "from": "edge", "face": true},
		{"id": "banner_pole", "n": 0.30, "r": 0.6, "from": "edge", "face": true},
		{"id": "market_stall_red", "n": 0.07, "r": 2.7, "from": "edge", "face": true, "solid": true},
		{"id": "market_stall_green", "n": 0.07, "r": 2.7, "from": "edge", "face": true, "solid": true},
		{"id": "produce_table", "n": 0.16, "r": 1.1, "from": "edge", "face": true},
		{"id": "cart", "n": 0.10, "r": 2.0, "from": "yard", "solid": true},
		{"id": "hand_cart", "n": 0.20, "r": 1.1, "from": "edge"},
		{"id": "crate_stack", "n": 0.35, "r": 0.9, "from": "edge"},
		{"id": "barrel_cluster", "n": 0.30, "r": 1.0, "from": "edge"},
		{"id": "sack_pile", "n": 0.30, "r": 1.0, "from": "edge"},
		{"id": "basket_produce", "n": 0.35, "r": 0.5, "from": "edge"},
		{"id": "flower_planter", "n": 0.30, "r": 0.7, "from": "edge", "face": true},
	],
	"craft": [
		{"id": "woodpile", "n": 0.30, "r": 1.7, "from": "yard"},
		{"id": "anvil_stump", "n": 0.10, "r": 0.8, "from": "edge"},
		{"id": "weapon_rack", "n": 0.08, "r": 1.4, "from": "edge", "face": true, "solid": true},
		{"id": "water_trough", "n": 0.18, "r": 1.3, "from": "edge", "face": true},
		{"id": "g:region/mine/ore_pile_iron", "n": 0.12, "r": 1.5, "from": "yard"},
		{"id": "g:region/mine/ore_pile_coal", "n": 0.10, "r": 1.5, "from": "yard"},
		{"id": "g:region/mine/ore_pile_copper", "n": 0.06, "r": 1.5, "from": "yard"},
		{"id": "hand_cart", "n": 0.20, "r": 1.1, "from": "edge"},
		{"id": "barrel_cluster", "n": 0.25, "r": 1.0, "from": "edge"},
		{"id": "crate_stack", "n": 0.30, "r": 0.9, "from": "edge"},
		{"id": "sack_pile", "n": 0.20, "r": 1.0, "from": "edge"},
		{"id": "hay", "n": 0.12, "r": 1.2, "from": "yard"},
		{"id": "d:drying_rack", "n": 0.16, "r": 1.5, "from": "yard", "face": true},
		{"id": "street_lamp", "n": 0.15, "r": 0.6, "from": "edge"},
	],
	"poor": [
		{"id": "well", "n": 0.07, "r": 1.7, "from": "yard", "solid": true, "min": 1},
		{"id": "hand_cart", "n": 0.18, "r": 1.1, "from": "edge"},
		{"id": "woodpile", "n": 0.22, "r": 1.7, "from": "yard"},
		{"id": "barrel", "n": 0.35, "r": 0.5, "from": "edge"},
		{"id": "d:laundry_line", "n": 0.22, "r": 2.4, "from": "yard"},
		{"id": "hay", "n": 0.14, "r": 1.2, "from": "yard"},
		{"id": "fence", "n": 0.35, "r": 1.6, "from": "yard"},
		{"id": "crate", "n": 0.25, "r": 0.6, "from": "edge"},
		{"id": "water_trough", "n": 0.07, "r": 1.3, "from": "edge", "face": true},
		{"id": "sack_pile", "n": 0.10, "r": 1.0, "from": "edge"},
	],
	"admin": [
		{"id": "g:notice_board", "n": 0.30, "r": 1.3, "from": "edge", "face": true, "solid": true},
		{"id": "banner_pole", "n": 0.50, "r": 0.6, "from": "edge", "face": true},
		{"id": "street_lamp", "n": 0.35, "r": 0.6, "from": "edge"},
		{"id": "bench", "n": 0.35, "r": 1.0, "from": "edge", "face": true},
		{"id": "flower_planter", "n": 0.40, "r": 0.7, "from": "edge", "face": true},
		{"id": "flower_bed", "n": 0.20, "r": 1.3, "from": "yard"},
		{"id": "weapon_rack", "n": 0.08, "r": 1.4, "from": "edge", "face": true, "solid": true},
		{"id": "signpost", "n": 0.12, "r": 0.9, "from": "edge", "face": true},
	],
	"inn": [
		{"id": "hay", "n": 0.30, "r": 1.2, "from": "yard"},
		{"id": "water_trough", "n": 0.35, "r": 1.3, "from": "edge", "face": true},
		{"id": "covered_wagon", "n": 0.09, "r": 2.3, "from": "yard", "solid": true},
		{"id": "g:horses/horse_cart", "n": 0.07, "r": 2.6, "from": "yard", "solid": true},
		{"id": "cart", "n": 0.08, "r": 2.0, "from": "yard", "solid": true},
		{"id": "fence", "n": 0.40, "r": 1.6, "from": "edge", "face": true},
		{"id": "barrel_cluster", "n": 0.30, "r": 1.0, "from": "edge"},
		{"id": "crate_stack", "n": 0.25, "r": 0.9, "from": "edge"},
		{"id": "bench", "n": 0.30, "r": 1.0, "from": "edge", "face": true},
		{"id": "market_stall_green", "n": 0.07, "r": 2.7, "from": "edge", "face": true, "solid": true},
		{"id": "produce_table", "n": 0.16, "r": 1.1, "from": "edge", "face": true},
		{"id": "street_lamp", "n": 0.25, "r": 0.6, "from": "edge"},
	],
	"military": [
		{"id": "weapon_rack", "n": 0.18, "r": 1.4, "from": "edge", "face": true, "solid": true},
		{"id": "g:region/farm/scarecrow", "n": 0.12, "r": 1.0, "from": "yard"},
		{"id": "hay", "n": 0.16, "r": 1.2, "from": "yard"},
		{"id": "banner_pole", "n": 0.30, "r": 0.6, "from": "edge", "face": true},
		{"id": "g:region/road/checkpoint_barrier", "n": 0.05, "r": 2.2, "from": "edge", "face": true, "solid": true},
		{"id": "g:region/ruins/campfire", "n": 0.05, "r": 1.3, "from": "yard"},
		{"id": "crate_stack", "n": 0.20, "r": 0.9, "from": "edge"},
		{"id": "barrel", "n": 0.20, "r": 0.5, "from": "edge"},
		{"id": "street_lamp", "n": 0.30, "r": 0.6, "from": "edge"},
		{"id": "water_trough", "n": 0.10, "r": 1.3, "from": "edge", "face": true},
	],
}


## Placement context: every constraint a ground prop has to respect, built once per town.
class Ctx extends RefCounted:
	var b                                   # SettlementBuilder (dynamic: its helpers are private)
	var plan: Dictionary
	var c: Vector2
	var r: float
	var plaza_r: float
	var walled: bool
	var rects: Array = []                   # [centre, yaw, hx, hz, gh] per lot (real footprint)
	var claims := {}                        # Vector2i (4 m cell) -> Array of [Vector2, radius]
	var seg_grid := {}                      # Vector2i (16 m cell) -> Array of [a, b, half width]: streets and door paths
	var rect_grid := {}                     # Vector2i (16 m cell of a lot's centre) -> Array of indices into rects

	func _init(builder, s: Dictionary, p: Dictionary) -> void:
		b = builder
		plan = p
		c = s["pos"]
		r = float(p["wall_radius"])
		plaza_r = float(p["plaza_r"])
		walled = bool(p["walls"])
		for lot: Dictionary in p["lots"]:
			var size: Vector3 = b._footprint(lot["asset"])
			var lp: Vector2 = lot["pos"]
			var rk := Vector2i(floori(lp.x / 16.0), floori(lp.y / 16.0))
			if not rect_grid.has(rk):
				rect_grid[rk] = []
			(rect_grid[rk] as Array).append(rects.size())
			rects.append([lp, float(lot["yaw"]), size.x * 0.5, size.z * 0.5, float(b._ground_snap(lp, lot["yaw"], size))])
		for st: Dictionary in p["streets"]:
			_grid_add(st["a"], st["b"], float(st["w"]) * 0.5, 0)
		for pt: Dictionary in p.get("paths", []):
			_grid_add(pt["a"], pt["b"], float(pt["w"]) * 0.5, 1)

	const GRID := 16.0
	const GRID_REACH := 18.0

	func _grid_add(a: Vector2, bb: Vector2, half: float, kind: int) -> void:
		var lo := Vector2(minf(a.x, bb.x), minf(a.y, bb.y)) - Vector2.ONE * GRID_REACH
		var hi := Vector2(maxf(a.x, bb.x), maxf(a.y, bb.y)) + Vector2.ONE * GRID_REACH
		for ix in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
			for iz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
				var k := Vector2i(ix, iz)
				if not seg_grid.has(k):
					seg_grid[k] = []
				(seg_grid[k] as Array).append([a, bb, half, kind])

	## Distance from p to the nearest street edge (kind 0) or door path edge (kind 1); exact up to GRID_REACH - 2 m, else INF.
	func edge_dist(p: Vector2, kind: int) -> float:
		var list: Variant = seg_grid.get(Vector2i(floori(p.x / GRID), floori(p.y / GRID)))
		var best := INF
		if list == null:
			return best
		for e: Array in list:
			if int(e[3]) != kind:
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, e[0], e[1])
			best = minf(best, p.distance_to(q) - float(e[2]))
		return best

	static func rect_dist(p: Vector2, cen: Vector2, yaw: float, hx: float, hz: float) -> float:
		var v := p - cen
		var lx := v.x * cos(yaw) - v.y * sin(yaw)
		var lz := v.x * sin(yaw) + v.y * cos(yaw)
		return Vector2(maxf(absf(lx) - hx, 0.0), maxf(absf(lz) - hz, 0.0)).length()

	func claim(p: Vector2, rad: float) -> void:
		var k := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		if not claims.has(k):
			claims[k] = []
		(claims[k] as Array).append([p, rad])

	func claimed(p: Vector2, rad: float) -> bool:
		var reach := int(ceil((rad + 4.0) / 4.0)) + 1
		var k0 := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var list: Variant = claims.get(Vector2i(k0.x + dx, k0.y + dz))
				if list == null:
					continue
				for e: Array in list:
					if p.distance_to(e[0]) < rad + float(e[1]):
						return true
		return false

	## Claim the yard items SettlementBuilder._homesteads placed (gardens, woodpiles, washing lines).
	func claim_yards() -> void:
		for q: Vector2 in plan.get("yard_spots", []):
			claim(q, 3.1)

	## Claim the 1.1 m door aprons of every lot (a lane straight out from the door) so nothing stands in front of a door.
	func claim_doors() -> void:
		for lot: Dictionary in plan["lots"]:
			var dp := BuildingProfiles.door_point(lot)
			var fwd := Vector2(sin(float(lot["yaw"])), cos(float(lot["yaw"])))
			for k in 4:
				claim(dp + fwd * (0.4 + k * 1.7), 1.1)

	## Free ground for a prop of clear radius `rad` (m) at p: off the plaza ring, the wall, streets, door paths, buildings,
	## landmarks, water, steep ground and anything already claimed. `street_gap` is the clearance kept from street edges.
	func ok_at(p: Vector2, rad: float, street_gap := 0.5) -> bool:
		var d := p.distance_to(c)
		if d < plaza_r + 3.0 + rad:
			return false
		if walled and d > r - 7.5 - rad:
			return false
		if not walled and d > r * 0.98:
			return false
		var inner: float = plan.get("inner_wall", 0.0)
		if inner > 0.0 and d < inner + 9.0 + rad:
			return false        # the keep wall, its towers and gates
		if edge_dist(p, 0) < rad + street_gap - 0.3:
			return false
		if edge_dist(p, 1) < rad + 0.5:
			return false
		if CityPlanner.landmark_clearance(plan, p) < rad + 1.5:
			return false
		var k0 := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var idx: Variant = rect_grid.get(Vector2i(k0.x + dx, k0.y + dz))
				if idx == null:
					continue
				for ri: int in idx:
					var rc: Array = rects[ri]
					if rect_dist(p, rc[0], rc[1], rc[2], rc[3]) < rad + 0.35:
						return false
		if claimed(p, rad):
			return false
		if WorldGen.is_water(p.x, p.y):
			return false
		return true


static func _mesh_of(id: String) -> Mesh:
	if id.begins_with("d:"):
		return HouseDetails.mesh_for(id.substr(2))
	if id.begins_with("g:"):
		var path := GEN + id.substr(2) + ".glb"
		return Assets.merged_mesh(path) if ResourceLoader.exists(path) else null
	return Assets.building_mesh(id)


## Queue one instance of mesh `id`: snapped to the lowest ground under its (shrunk) footprint like SettlementBuilder
## does, skipped on ground too steep for it (lint: sunken / floating). Returns false when it was not placed.
static func _add(batches: Dictionary, id: String, p: Vector2, yaw: float, sc := 1.0, lift := 0.0) -> bool:
	var mesh := _mesh_of(id)
	if mesh == null:
		return false
	var box := mesh.get_aabb()
	var size := box.size * sc
	var basis := Basis(Vector3.UP, yaw)
	var lo := WorldGen.height(p.x, p.y)
	var hi := lo
	if size.x * size.z >= 0.5:
		for cx: float in [-0.4, 0.4]:
			for cz: float in [-0.4, 0.4]:
				var off := basis * Vector3(size.x * cx, 0.0, size.z * cz)
				var h := WorldGen.height(p.x + off.x, p.y + off.z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
	if hi - lo > maxf(0.25, size.y * 0.4):
		return false
	if not batches.has(id):
		batches[id] = [] as Array[Transform3D]
	var y := lo - box.position.y * sc - 0.03 + lift
	(batches[id] as Array[Transform3D]).append(Transform3D(basis.scaled(Vector3.ONE * sc), Vector3(p.x, y, p.y)))
	return true


## Batch one mesh id into 40 m cells; solid ids get colliders. Wall-mounted ids (hanging_...) are named so the world
## lint knows they hang on a wall on purpose.
static func _flush(b, root: Node3D, batches: Dictionary, solid_ids: Dictionary, hanging: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "DistrictProps"
	root.add_child(holder)
	for id: String in batches:
		var mesh := _mesh_of(id)
		if mesh == null:
			continue
		var groups := {}
		for t: Transform3D in batches[id]:
			var k := Vector2i(floori(t.origin.x / CELL), floori(t.origin.z / CELL))
			if not groups.has(k):
				groups[k] = [] as Array[Transform3D]
			(groups[k] as Array[Transform3D]).append(t)
		for k: Vector2i in groups:
			var mmi: MultiMeshInstance3D = b._multimesh(holder, mesh, groups[k], not hanging.has(id), solid_ids.has(id))
			if mmi:
				mmi.name = ("hanging_" if hanging.has(id) else "dp_") + id.replace(":", "_").replace("/", "_")


static func build(b, root: Node3D, s: Dictionary, plan: Dictionary) -> void:
	if plan.get("district_anchors", []).is_empty():
		return
	var sid: int = s["id"]
	var ctx := Ctx.new(b, s, plan)
	# Door aprons and the gate market's stalls are off limits.
	ctx.claim_doors()
	ctx.claim_yards()
	for st: Array in b.stalls_by_town.get(sid, []):
		ctx.claim(st[1], 3.4)
	var low: bool = b._low()
	var batches := {}
	var solid_ids := {}
	var hanging := {}
	var decals: Array = []      # [kind, pos Vector3, basis, size Vector3, tint]
	var marks := {"yard": Vector2.INF, "wells": [], "boards": [], "stables": [], "gates": []}
	var smoke: Array[Vector3] = []
	_house_details(ctx, s, plan, b, batches, solid_ids, hanging, decals, low, smoke)
	_district_sets(ctx, s, plan, batches, solid_ids, marks, low)
	_drill_yard(ctx, s, plan, batches, solid_ids, marks)
	if not low:
		_mud(ctx, s, plan, decals)
	_flush(b, root, batches, solid_ids, hanging)
	_flush_decals(root, decals, low)
	for pt: Vector3 in smoke:
		root.add_child(b._smoke_emitter(pt))
	plan["marks"] = marks


# --- House details ----------------------------------------------------------------------------------------------------

static func _house_details(ctx: Ctx, s: Dictionary, plan: Dictionary, b, batches: Dictionary, solid_ids: Dictionary,
		hanging: Dictionary, decals: Array, low: bool, smoke: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	var keep_every := 2 if low else 1       # LOW: every second lot gets detailed
	var li := -1
	for lot: Dictionary in plan["lots"]:
		li += 1
		if li % keep_every != 0:
			continue
		var asset := String(lot["asset"])
		var size: Vector3 = b._footprint(asset)
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		rng.seed = int(lot.get("seed", li)) + 4242
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var gh: float = b._ground_snap(p, yaw, size)
		for e: Dictionary in HouseDetails.choose(lot, size, rng):
			var key: String = e["key"]
			var at := p + side * float(e["x"]) + fwd * float(e["z"])
			if HouseDetails.is_decal(key):
				_detail_decal(decals, key, e, at, fwd, gh, size)
				continue
			var wall := bool(e.get("wall", false)) or (float(e["y"]) > 0.0 and (e["slot"] as String) in ["wall_a", "wall_b", "roof"])
			var id := "d:" + key
			if wall:
				# Wall items hang on the wall plane at a height above the building's own base.
				if HouseDetails.mesh_for(key) == null:
					continue
				# A lot on a steep bank: the lowest-corner snap leaves its uphill front below the ground; nothing hangs in the hill.
				var ground_here := WorldGen.height(at.x, at.y)
				if float(e["y"]) > 0.0:
					if ground_here > gh + float(e["y"]) - 0.3:
						continue
				elif ground_here > gh + 0.7 or ground_here < gh - 0.35:
					continue   # a ground-standing wall piece (chimney): neither buried in the bank nor hanging off it
				var basis := Basis(Vector3.UP, yaw + float(e["yaw"])).scaled(Vector3.ONE * float(e["scale"]))
				if not batches.has(id):
					batches[id] = [] as Array[Transform3D]
				(batches[id] as Array[Transform3D]).append(Transform3D(basis, Vector3(at.x, gh + float(e["y"]), at.y)))
				if key != "chimney_stack":
					hanging[id] = true
				elif not low and smoke.size() < SMOKE_CAP and (lot["district"] in ["craft", "poor", "military"]) and rng.randf() < 0.75:
					smoke.append(Vector3(at.x, gh + 4.45, at.y) + Vector3(side.x, 0.0, side.y) * signf(float(e["x"])) * 0.4)
				continue
			# Floor items: free ground only (a neighbour's wall, a street or another prop rules the spot out).
			var rad := float(e["r"])
			if not ctx.ok_at(at, rad, 0.2):
				continue
			if _add(batches, id, at, yaw + float(e["yaw"]), float(e["scale"])):
				ctx.claim(at, rad)


static func _detail_decal(decals: Array, key: String, e: Dictionary, at: Vector2, _fwd: Vector2, gh: float, _size: Vector3) -> void:
	if key == "roof_patch":
		# A downward projector over the roof: a brownish patch of mended shingles.
		decals.append(["plaster", Vector3(at.x, gh + float(e["y"]) + 0.6, at.y), Basis.IDENTITY, Vector3(2.3, 3.2, 1.9),
			Color(0.55, 0.38, 0.26, 0.95), TownDecals.WALL_LAYER, "roof"])


static func _flush_decals(root: Node3D, decals: Array, low: bool) -> void:
	if low or decals.is_empty() or not TownDecals.available():
		return
	var holder := Node3D.new()
	holder.name = "DetailDecals"
	root.add_child(holder)
	var roofs := 0
	var chunks := {}
	for d: Array in decals:
		if d.size() > 6 and d[6] == "roof":
			if roofs >= DECAL_CAP:
				continue
			roofs += 1
		else:
			var at: Vector3 = d[1]
			var ck := Vector2i(floori(at.x / 64.0), floori(at.z / 64.0))
			if int(chunks.get(ck, 0)) >= MUD_PER_CHUNK:
				continue
			chunks[ck] = int(chunks.get(ck, 0)) + 1
		var dec := TownDecals.make(String(d[0]), d[3], int(d[5]), d[4])
		holder.add_child(dec)
		dec.global_transform = Transform3D(d[2], d[1])


# --- District sets ----------------------------------------------------------------------------------------------------

## Candidate spots for every district at once, shuffled: {district: {"edge": [[pos, yaw], ...], "yard": [...]}}.
## Edge spots sit 1.6-2.6 m off the edge of a (non gate-road) street facing it; yard spots are free-standing, 1.5-15 m
## from a street. Generated once per town (the grid and the nearest-anchor lookups are the cost).
static func _all_candidates(ctx: Ctx, plan: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var anchors: Array = plan["district_anchors"]
	var out := {}
	for dk: String in Districts.KINDS:
		out[dk] = {"edge": [], "yard": []}
	for st: Dictionary in plan["streets"]:
		var w: float = st["w"]
		if w >= 11.0:
			continue        # the broad gate road belongs to the gate market
		var a: Vector2 = st["a"]
		var bb: Vector2 = st["b"]
		var length := a.distance_to(bb)
		var dir := (bb - a) / maxf(length, 0.001)
		var nrm := Vector2(-dir.y, dir.x)
		var t := rng.randf_range(2.0, 5.0)
		while t < length - 1.0:
			for sd: float in [-1.0, 1.0]:
				var p := a + dir * t + nrm * sd * (w * 0.5 + rng.randf_range(1.6, 2.6))
				if p.distance_to(ctx.c) > ctx.plaza_r + 3.0:
					var face := -nrm * sd
					(out[Districts.nearest_kind(anchors, p)]["edge"] as Array).append([p, atan2(face.x, face.y)])
			t += rng.randf_range(4.5, 8.0)
	var step := 4.0
	var gx := -ctx.r
	while gx <= ctx.r:
		var gz := -ctx.r
		while gz <= ctx.r:
			var p := ctx.c + Vector2(gx + rng.randf_range(-1.4, 1.4), gz + rng.randf_range(-1.4, 1.4))
			gz += step
			var d := p.distance_to(ctx.c)
			if d > ctx.r - 8.0 or d < ctx.plaza_r + 3.0:
				continue
			var sdist := ctx.edge_dist(p, 0)
			if sdist < 1.5 or sdist > 15.0:
				continue
			(out[Districts.nearest_kind(anchors, p)]["yard"] as Array).append([p, rng.randf() * TAU])
		gx += step
	# Deterministic shuffle.
	for dk: String in Districts.KINDS:
		for from: String in ["edge", "yard"]:
			var arr: Array = out[dk][from]
			for i in range(arr.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var tmp = arr[i]
				arr[i] = arr[j]
				arr[j] = tmp
	return out


static func _district_sets(ctx: Ctx, s: Dictionary, plan: Dictionary, batches: Dictionary, solid_ids: Dictionary, marks: Dictionary, low: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8101 + int(s["id"])
	var lots_in := {}
	for lot: Dictionary in plan["lots"]:
		var dk := String(lot.get("district", ""))
		lots_in[dk] = int(lots_in.get(dk, 0)) + 1
	var anchors_present := {}
	for a: Dictionary in plan["district_anchors"]:
		anchors_present[a["kind"]] = true
	var cands := _all_candidates(ctx, plan, rng)
	for dk: String in Districts.KINDS:
		if not anchors_present.has(dk) or not SETS.has(dk):
			continue
		var edge: Array = cands[dk]["edge"]
		var yard: Array = cands[dk]["yard"]
		var lots_n := int(lots_in.get(dk, 0))
		for spec: Dictionary in SETS[dk]:
			var want := float(spec["n"]) * lots_n * (0.6 if low else 1.0)
			var count := int(want) + (1 if rng.randf() < want - int(want) else 0)
			count = maxi(count, int(spec.get("min", 0)) if lots_n >= 8 else 0)
			var pool: Array = edge if spec["from"] == "edge" else yard
			var rad: float = spec["r"]
			var id: String = spec["id"]
			var placed := 0
			var tries := 0
			while placed < count and tries < pool.size() and tries < 700:
				var cand: Array = pool[tries]
				tries += 1
				var p: Vector2 = cand[0]
				if not ctx.ok_at(p, rad, 0.5 if spec["from"] == "edge" else 1.0):
					continue
				var yaw: float = cand[1] if bool(spec.get("face", false)) else rng.randf() * TAU
				if not _add(batches, id, p, yaw, 1.0):
					continue
				ctx.claim(p, rad)
				placed += 1
				if bool(spec.get("solid", false)):
					solid_ids[id] = true
				if id == "well":
					(marks["wells"] as Array).append(p)
				elif id == "g:notice_board":
					(marks["boards"] as Array).append(p)


## The training yard: the roomiest free ground in the military ward gets a row of straw dummies, weapon racks and hay targets.
static func _drill_yard(ctx: Ctx, s: Dictionary, plan: Dictionary, batches: Dictionary, solid_ids: Dictionary, marks: Dictionary) -> void:
	var present := false
	for a: Dictionary in plan["district_anchors"]:
		if a["kind"] == Districts.MILITARY:
			present = true
	if not present:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 8209 + int(s["id"])
	var best := Vector2.INF
	var best_room := 0.0
	var step := 2.5
	var gx := -ctx.r
	while gx <= ctx.r:
		var gz := -ctx.r
		while gz <= ctx.r:
			var p := ctx.c + Vector2(gx, gz)
			gz += step
			if p.distance_to(ctx.c) > ctx.r - 12.0 or Districts.nearest_kind(plan["district_anchors"], p) != Districts.MILITARY:
				continue
			var room := 9.0
			while room > 5.0 and not ctx.ok_at(p, room, 1.0):
				room -= 1.0
			if room > best_room or (room == best_room and best == Vector2.INF):
				best_room = room
				best = p
		gx += step
	if best == Vector2.INF or best_room < 5.5:
		return
	# Face the yard toward the nearest street.
	var sdir := Vector2.DOWN
	var bd := INF
	for st: Dictionary in plan["streets"]:
		var q := Geometry2D.get_closest_point_to_segment(best, st["a"], st["b"])
		if best.distance_to(q) < bd:
			bd = best.distance_to(q)
			sdir = (q - best).normalized()
	var yaw := atan2(sdir.x, sdir.y)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var span := best_room - 1.8
	for i in 4:
		var q := best - fwd * span * 0.35 + side * (-1.5 + i) * 2.1
		_add(batches, "g:region/farm/scarecrow", q, yaw + PI, 1.0)
	for i in 3:
		var q2 := best + fwd * span * 0.45 + side * (-1.0 + i) * 2.6
		if _add(batches, "hay", q2, yaw + PI, 1.0):
			pass
	for sg: float in [-1.0, 1.0]:
		var q3 := best + side * sg * span * 0.8
		if _add(batches, "weapon_rack", q3, yaw + sg * PI * 0.5, 1.0):
			solid_ids["weapon_rack"] = true
	_add(batches, "banner_pole", best + fwd * span * 0.8 - side * span * 0.6, yaw, 1.0)
	ctx.claim(best, best_room)
	marks["yard"] = best


## Muddy lanes: brown ground decals along the poor quarter's streets and a few puddles.
static func _mud(ctx: Ctx, s: Dictionary, plan: Dictionary, decals: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8317 + int(s["id"])
	var n := 0
	for st: Dictionary in plan["streets"]:
		var w: float = st["w"]
		if w >= 11.0:
			continue
		var a: Vector2 = st["a"]
		var bb: Vector2 = st["b"]
		var length := a.distance_to(bb)
		var dir := (bb - a) / maxf(length, 0.001)
		var t := rng.randf_range(1.0, 5.0)
		while t < length:
			var p := a + dir * t + Vector2(-dir.y, dir.x) * rng.randf_range(-1.0, 1.0)
			if Districts.nearest_kind(plan["district_anchors"], p) == Districts.POOR and p.distance_to(ctx.c) > ctx.plaza_r + 6.0 and n < 28:
				var kind := "dirt" if rng.randf() < 0.6 else "puddle"
				var tint := Color(0.62, 0.46, 0.3, 0.95) if kind == "dirt" else Color(1, 1, 1, 0.92)
				decals.append([kind, Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y), Basis(Vector3.UP, atan2(dir.x, dir.y)),
					Vector3(rng.randf_range(3.0, 4.6), 2.0, rng.randf_range(4.0, 7.0)), tint, TownDecals.GROUND_LAYER])
				n += 1
			t += rng.randf_range(5.0, 9.0)
