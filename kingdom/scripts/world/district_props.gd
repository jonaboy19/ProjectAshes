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
const TownIdentity := preload("res://scripts/world/town_identity.gd")    # kit specs, prop multipliers and town-coloured banners per town
const GEN := "res://assets/generated/"
const CELL := 40.0
## LOW: district props with this many material surfaces or more are not built (each is that many draws).
const LOW_MAX_SURFACES := 4
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


## Meshy free pack pieces (Assets.BUILDINGS "mf_*" keys, native size; docs/qa/ASSET_AUDIT.md "use the unused models"): extra street
## furniture per district, appended AFTER SETS and before a town's identity-kit specs so the base sets keep their own order.
const MF_SETS := {
	"market": [
		{"id": "mf_street_lantern_whimsical", "n": 0.18, "r": 0.6, "from": "edge"},
		{"id": "mf_stall_open_roof", "n": 0.05, "r": 2.6, "from": "edge", "face": true, "solid": true},
		{"id": "mf_stall_potatoes", "n": 0.04, "r": 2.8, "from": "edge", "face": true, "solid": true},
		{"id": "mf_table_barrel_top", "n": 0.10, "r": 0.8, "from": "edge", "face": true},
		{"id": "mf_bouquet_wild", "n": 0.12, "r": 0.4, "from": "edge"},
	],
	"craft": [
		{"id": "mf_axe_long_handle", "n": 0.08, "r": 0.8, "from": "edge"},
		{"id": "mf_chest_metal_wood", "n": 0.05, "r": 0.7, "from": "edge", "face": true},
		{"id": "mf_hay_bale_rect_a", "n": 0.10, "r": 0.9, "from": "yard"},
	],
	"poor": [
		{"id": "mf_well_stone_shingle", "n": 0.03, "r": 1.9, "from": "yard", "solid": true},
		{"id": "mf_well_covered_planks", "n": 0.03, "r": 1.9, "from": "yard", "solid": true},
		{"id": "mf_well_stone_roofed", "n": 0.02, "r": 1.9, "from": "yard", "solid": true},
		{"id": "mf_hay_bale_round", "n": 0.10, "r": 1.0, "from": "yard"},
		{"id": "mf_fence_picket_low", "n": 0.20, "r": 1.5, "from": "yard", "face": true},
		{"id": "mf_fence_plank_panel", "n": 0.12, "r": 1.5, "from": "yard", "face": true},
		{"id": "mf_shed_thatch_small", "n": 0.04, "r": 2.0, "from": "yard", "solid": true},
		{"id": "mf_chicken_coop_fenced", "n": 0.03, "r": 1.8, "from": "yard", "solid": true},
		{"id": "mf_bush_raspberry", "n": 0.10, "r": 1.0, "from": "yard"},
		{"id": "mf_bouquet_wild", "n": 0.12, "r": 0.4, "from": "edge"},
	],
	"admin": [
		{"id": "mf_street_lamp_twin_gold", "n": 0.22, "r": 0.8, "from": "edge"},
		{"id": "mf_street_lantern_gothic", "n": 0.22, "r": 0.7, "from": "edge"},
		{"id": "mf_chest_gold", "n": 0.02, "r": 0.7, "from": "edge", "face": true},
	],
	"inn": [
		{"id": "mf_table_tavern_trestle", "n": 0.10, "r": 1.6, "from": "edge", "face": true, "solid": true},
		{"id": "mf_table_tavern_thick", "n": 0.08, "r": 1.3, "from": "edge", "face": true, "solid": true},
		{"id": "mf_chair_simple_a", "n": 0.16, "r": 0.5, "from": "edge", "face": true},
		{"id": "mf_chair_simple_b", "n": 0.16, "r": 0.5, "from": "edge", "face": true},
		{"id": "mf_tavern_set_barrels_b", "n": 0.07, "r": 2.0, "from": "yard"},
		{"id": "mf_hay_bale_yellow_large", "n": 0.10, "r": 1.0, "from": "yard"},
		{"id": "mf_shed_wood_shingle", "n": 0.03, "r": 1.9, "from": "yard", "solid": true},
	],
	"military": [
		{"id": "mf_lamp_post_timber_cross", "n": 0.20, "r": 0.7, "from": "edge"},
		{"id": "mf_shed_plank_low", "n": 0.04, "r": 1.8, "from": "yard", "solid": true},
		{"id": "mf_chest_red_black", "n": 0.04, "r": 0.7, "from": "edge", "face": true},
		{"id": "mf_axe_long_handle", "n": 0.08, "r": 0.8, "from": "edge"},
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

	var segs: Array = []                    # [a, b, half width, kind] of every street and door path, fed to the grid by add_segs

	## Cheap: the lots and the segment grid are filled in slices by the build job (add_lots / add_segs).
	func _init(builder, s: Dictionary, p: Dictionary) -> void:
		b = builder
		plan = p
		c = s["pos"]
		r = float(p["wall_radius"])
		plaza_r = float(p["plaza_r"])
		walled = bool(p["walls"])
		for st: Dictionary in p["streets"]:
			segs.append([st["a"], st["b"], float(st["w"]) * 0.5, 0])
		for pt: Dictionary in p.get("paths", []):
			segs.append([pt["a"], pt["b"], float(pt["w"]) * 0.5, 1])

	func add_lots(i0: int, i1: int) -> void:
		for i in range(i0, i1):
			var lot: Dictionary = plan["lots"][i]
			var size: Vector3 = b._footprint(lot["asset"])
			var lp: Vector2 = lot["pos"]
			var rk := Vector2i(floori(lp.x / 16.0), floori(lp.y / 16.0))
			if not rect_grid.has(rk):
				rect_grid[rk] = []
			(rect_grid[rk] as Array).append(rects.size())
			rects.append([lp, float(lot["yaw"]), size.x * 0.5, size.z * 0.5, float(b._ground_snap(lp, lot["yaw"], size))])

	func add_segs(i0: int, i1: int) -> void:
		for i in range(i0, i1):
			var sg: Array = segs[i]
			_grid_add(sg[0], sg[1], float(sg[2]), int(sg[3]))

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
		for e: Array in plan.get("town_claims", []):
			claim(e[0], float(e[1]))
		for q: Vector2 in plan.get("outskirt_spots", []):
			claim(q, 3.6)

	## Claim the 1.1 m door aprons of every lot (a lane straight out from the door) so nothing stands in front of a door.
	func claim_doors(i0: int, i1: int) -> void:
		for i in range(i0, i1):
			var lot: Dictionary = plan["lots"][i]
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


## Time-sliced build of one town's district props. Created by build(); step(budget_ms) advances it. The phases run in the
## same order, with the same RNG streams, as the old all-at-once build, so the result is identical; only the cost is
## spread over frames (SettlementBuilder drains it with DP_BUDGET_MS per frame). While it runs the town root carries
## the meta "props_pending" (AmbientFx reads the chimneys only after it is cleared).
class Job extends RefCounted:
	var b
	var root: Node3D
	var s: Dictionary
	var plan: Dictionary
	var ctx: Ctx
	var low := false
	var runner := Callable()
	var done := false
	var phase := 0
	var cur := 0                            # generic cursor of the current phase
	# shared build state
	var batches := {}
	var solid_ids := {}
	var hanging := {}
	var decals: Array = []                  # [kind, pos Vector3, basis, size Vector3, tint, layer, (tag)]
	var marks := {"yard": Vector2.INF, "wells": [], "boards": [], "stables": [], "gates": []}
	var smoke: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	# house details
	var keep_every := 1
	var prof: Dictionary = {}               # TownIdentity profile of this town
	var specs := {}                         # district kind -> [spec] (the base SETS filtered by the profile + its kit specs)
	# district sets
	var cands := {}
	var lots_in := {}
	var anchors_present := {}
	var dk_i := 0
	var spec_i := 0
	var spec_on := false
	var spec_pool: Array = []
	var spec_count := 0
	var spec_placed := 0
	var spec_tries := 0
	var gx := 0.0
	# drill yard / mud
	var best := Vector2.INF
	var best_room := 0.0
	var mud_n := 0
	# flush
	var ids: Array = []
	var work: Array = []                    # [id, mesh, transforms] cells waiting for their MultiMesh
	var holder: Node3D
	var roofs := 0
	var chunks := {}
	# stats (QA)
	var ms_total := 0.0
	var ms_worst := 0.0
	var slices := 0
	var phase_worst := {}                   # QA: phase -> longest single unit in ms

	## Run units until the budget (ms; <= 0 = run to the end) is spent. Returns true when the job is finished.
	func step(budget_ms: float) -> bool:
		if not done:
			runner.call(self, budget_ms)
		return done


const PH_LOTS := 0
const PH_SEGS := 1
const PH_CLAIMS := 2
const PH_DETAILS := 3
const PH_CAND_INIT := 4
const PH_CAND_STREETS := 5
const PH_CAND_GRID := 6
const PH_CAND_SHUFFLE := 7
const PH_SETS := 8
const PH_DRILL_SCAN := 9
const PH_DRILL_PLACE := 10
const PH_MUD := 11
const PH_FLUSH := 12
const PH_DECALS := 13
const PH_SMOKE := 14
const LOTS_PER_UNIT := 6
const SEGS_PER_UNIT := 3
const TRIES_PER_UNIT := 3
const DOORS_PER_UNIT := 16


## Start the district props of one town. `sync` runs it to the end before returning (tests, the world lint); otherwise the
## caller drives it with job.step(budget_ms) once per frame. Returns null for a town without districts.
static func build(b, root: Node3D, s: Dictionary, plan: Dictionary, sync := true) -> Job:
	if plan.get("district_anchors", []).is_empty():
		return null
	var j := Job.new()
	j.b = b
	j.root = root
	j.s = s
	j.plan = plan
	j.low = b._low()
	j.prof = TownIdentity.profile(s)
	j.runner = _run
	j.ctx = Ctx.new(b, s, plan)
	j.keep_every = 2 if j.low else 1        # LOW: every second lot gets detailed
	root.set_meta("props_pending", true)
	if sync:
		# The job flushes its own contact-shadow blobs when it ends (a sliced job ends after the builder's flush): keep the
		# builder's pending blobs out of that flush so the sync and the sliced build give the same nodes.
		var pending: Dictionary = b._blob_batch.duplicate()
		b._blob_batch.clear()
		j.step(0.0)
		for k in pending:
			b._blob_batch[k] = pending[k]
	return j


static func _run(j: Job, budget_ms: float) -> void:
	var t0 := Time.get_ticks_usec()
	var lim := budget_ms * 1000.0
	while not j.done:
		if not is_instance_valid(j.root):
			j.done = true                   # the town was freed while it was building
			break
		var u0 := Time.get_ticks_usec()
		var ph := j.phase
		_unit(j)
		var now := Time.get_ticks_usec()
		j.phase_worst[ph] = maxf(float(j.phase_worst.get(ph, 0.0)), (now - u0) / 1000.0)
		if budget_ms > 0.0 and now - t0 >= lim:
			break
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	j.ms_total += ms
	j.ms_worst = maxf(j.ms_worst, ms)
	j.slices += 1


## One small unit of work of the current phase (a few lots, one street, one column of the grid, a handful of placement
## tries, one MultiMesh...).
static func _unit(j: Job) -> void:
	var ctx := j.ctx
	match j.phase:
		PH_LOTS:
			var n: int = (j.plan["lots"] as Array).size()
			ctx.add_lots(j.cur, mini(j.cur + LOTS_PER_UNIT, n))
			j.cur += LOTS_PER_UNIT
			if j.cur >= n:
				_next(j, PH_SEGS)
		PH_SEGS:
			var n: int = ctx.segs.size()
			ctx.add_segs(j.cur, mini(j.cur + SEGS_PER_UNIT, n))
			j.cur += SEGS_PER_UNIT
			if j.cur >= n:
				_next(j, PH_CLAIMS)
		PH_CLAIMS:
			# Door aprons and the gate market's stalls are off limits.
			var n: int = (j.plan["lots"] as Array).size()
			ctx.claim_doors(j.cur, mini(j.cur + DOORS_PER_UNIT, n))
			j.cur += DOORS_PER_UNIT
			if j.cur >= n:
				ctx.claim_yards()
				for st: Array in j.b.stalls_by_town.get(int(j.s["id"]), []):
					ctx.claim(st[1], 3.4)
				_next(j, PH_DETAILS)
		PH_DETAILS:
			var n: int = (j.plan["lots"] as Array).size()
			if j.cur < n and j.cur % j.keep_every == 0:
				_house_lot(j, j.cur)
			j.cur += 1
			if j.cur >= n:
				_next(j, PH_CAND_INIT)
		PH_CAND_INIT:
			j.rng.seed = 8101 + int(j.s["id"])
			for lot: Dictionary in j.plan["lots"]:
				var dk := String(lot.get("district", ""))
				j.lots_in[dk] = int(j.lots_in.get(dk, 0)) + 1
			for a: Dictionary in j.plan["district_anchors"]:
				j.anchors_present[a["kind"]] = true
			for dk: String in Districts.KINDS:
				j.cands[dk] = {"edge": [], "yard": []}
			_next(j, PH_CAND_STREETS)
		PH_CAND_STREETS:
			var streets: Array = j.plan["streets"]
			if j.cur < streets.size():
				_cand_street(j, streets[j.cur])
				j.cur += 1
			if j.cur >= streets.size():
				_next(j, PH_CAND_GRID)
				j.gx = -ctx.r
		PH_CAND_GRID:
			_cand_column(j)
			j.gx += 4.0
			if j.gx > ctx.r:
				_next(j, PH_CAND_SHUFFLE)
		PH_CAND_SHUFFLE:
			# Deterministic shuffle, one (district, edge|yard) list per unit.
			var dk: String = Districts.KINDS[j.cur / 2]
			var arr: Array = j.cands[dk]["edge" if j.cur % 2 == 0 else "yard"]
			for i in range(arr.size() - 1, 0, -1):
				var k := j.rng.randi() % (i + 1)
				var tmp = arr[i]
				arr[i] = arr[k]
				arr[k] = tmp
			j.cur += 1
			if j.cur >= Districts.KINDS.size() * 2:
				_next(j, PH_SETS)
		PH_SETS:
			_sets_unit(j)
		PH_DRILL_SCAN:
			_drill_column(j)
		PH_DRILL_PLACE:
			_drill_place(j)
		PH_MUD:
			_mud_street(j)
		PH_FLUSH:
			_flush_unit(j)
		PH_DECALS:
			_decal_unit(j)
		PH_SMOKE:
			if j.cur < j.smoke.size():
				j.root.add_child(j.b._smoke_emitter(j.smoke[j.cur]))
				j.cur += 1
			if j.cur >= j.smoke.size():
				j.b._flush_contact_shadows(j.root)     # the blobs of this job's props belong to THIS town (a sliced job ends after _build's own flush)
				j.plan["marks"] = j.marks
				j.root.set_meta("props_pending", false)
				j.done = true


static func _next(j: Job, phase: int) -> void:
	j.phase = phase
	j.cur = 0


# --- House details ----------------------------------------------------------------------------------------------------

static func _house_lot(j: Job, li: int) -> void:
	var ctx := j.ctx
	var b = j.b
	var lot: Dictionary = j.plan["lots"][li]
	var rng := j.rng
	var batches := j.batches
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
			_detail_decal(j.decals, key, e, at, fwd, gh, size)
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
				j.hanging[id] = true
			elif not j.low and j.smoke.size() < SMOKE_CAP and (lot["district"] in ["craft", "poor", "military"]) and rng.randf() < 0.75:
				j.smoke.append(Vector3(at.x, gh + 4.45, at.y) + Vector3(side.x, 0.0, side.y) * signf(float(e["x"])) * 0.4)
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


# --- District sets ----------------------------------------------------------------------------------------------------

## Candidate spots for every district at once, shuffled: {district: {"edge": [[pos, yaw], ...], "yard": [...]}}.
## Edge spots sit 1.6-2.6 m off the edge of a (non gate-road) street facing it; yard spots are free-standing, 1.5-15 m
## from a street. Generated once per town (the grid and the nearest-anchor lookups are the cost), a street / a grid
## column per unit.
static func _cand_street(j: Job, st: Dictionary) -> void:
	var rng := j.rng
	var anchors: Array = j.plan["district_anchors"]
	var w: float = st["w"]
	if w >= 11.0:
		return        # the broad gate road belongs to the gate market
	var a: Vector2 = st["a"]
	var bb: Vector2 = st["b"]
	var length := a.distance_to(bb)
	var dir := (bb - a) / maxf(length, 0.001)
	var nrm := Vector2(-dir.y, dir.x)
	var t := rng.randf_range(2.0, 5.0)
	while t < length - 1.0:
		for sd: float in [-1.0, 1.0]:
			var p := a + dir * t + nrm * sd * (w * 0.5 + rng.randf_range(1.6, 2.6))
			if p.distance_to(j.ctx.c) > j.ctx.plaza_r + 3.0:
				var face := -nrm * sd
				(j.cands[Districts.nearest_kind(anchors, p)]["edge"] as Array).append([p, atan2(face.x, face.y)])
		t += rng.randf_range(4.5, 8.0)


static func _cand_column(j: Job) -> void:
	var ctx := j.ctx
	var rng := j.rng
	var anchors: Array = j.plan["district_anchors"]
	var gz := -ctx.r
	while gz <= ctx.r:
		var p := ctx.c + Vector2(j.gx + rng.randf_range(-1.4, 1.4), gz + rng.randf_range(-1.4, 1.4))
		gz += 4.0
		var d := p.distance_to(ctx.c)
		if d > ctx.r - 8.0 or d < ctx.plaza_r + 3.0:
			continue
		var sdist := ctx.edge_dist(p, 0)
		if sdist < 1.5 or sdist > 15.0:
			continue
		(j.cands[Districts.nearest_kind(anchors, p)]["yard"] as Array).append([p, rng.randf() * TAU])


## A handful of placement tries of the current (district, spec); moves on to the next spec / district / phase.
## The prop specs of district `dk` in this town: the shared SETS (minus what the town's character rules out) followed by its
## identity kit specs (ore carts in a mining town, drying racks in a dyers', haystacks in a farm village ...).
static func _specs_of(j: Job, dk: String) -> Array:
	if not j.specs.has(dk):
		var out: Array = []
		for sp: Dictionary in SETS.get(dk, []):
			if TownIdentity.prop_mult(j.prof, String(sp["id"])) > 0.0:
				out.append(sp)
		for sp: Dictionary in MF_SETS.get(dk, []):
			if TownIdentity.prop_mult(j.prof, String(sp["id"])) > 0.0:
				out.append(sp)
		out.append_array(TownIdentity.kit_specs(j.prof, dk))
		j.specs[dk] = out
	return j.specs[dk]


static func _sets_unit(j: Job) -> void:
	var ctx := j.ctx
	var rng := j.rng
	var kinds: Array = Districts.KINDS
	if j.dk_i >= kinds.size():
		_start_drill(j)
		return
	var dk: String = kinds[j.dk_i]
	if not j.anchors_present.has(dk) or j.spec_i >= _specs_of(j, dk).size():
		j.dk_i += 1
		j.spec_i = 0
		j.spec_on = false
		return
	var spec: Dictionary = _specs_of(j, dk)[j.spec_i]
	var edge_spec: bool = spec["from"] == "edge"
	if not j.spec_on:
		var lots_n := int(j.lots_in.get(dk, 0))
		var want := float(spec["n"]) * lots_n * (0.6 if j.low else 1.0) * TownIdentity.prop_mult(j.prof, String(spec["id"]))
		var count := int(want) + (1 if rng.randf() < want - int(want) else 0)
		count = maxi(count, int(spec.get("min", 0)) if lots_n >= 8 else 0)
		j.spec_count = count
		j.spec_pool = j.cands[dk]["edge" if edge_spec else "yard"]
		j.spec_placed = 0
		j.spec_tries = 0
		j.spec_on = true
	var rad: float = spec["r"]
	var id: String = spec["id"]
	var pool: Array = j.spec_pool
	var n := 0
	while j.spec_placed < j.spec_count and j.spec_tries < pool.size() and j.spec_tries < 700 and n < TRIES_PER_UNIT:
		var cand: Array = pool[j.spec_tries]
		j.spec_tries += 1
		n += 1
		var p: Vector2 = cand[0]
		if not ctx.ok_at(p, rad, 0.5 if edge_spec else 1.0):
			continue
		var yaw: float = cand[1] if bool(spec.get("face", false)) else rng.randf() * TAU
		if not _add(j.batches, id, p, yaw, float(spec.get("sc", 1.0))):
			continue
		ctx.claim(p, rad)
		j.spec_placed += 1
		if bool(spec.get("solid", false)):
			j.solid_ids[id] = true
		if id == "well" or id.begins_with("mf_well_"):
			(j.marks["wells"] as Array).append(p)
		elif id == "g:notice_board":
			(j.marks["boards"] as Array).append(p)
	if j.spec_placed >= j.spec_count or j.spec_tries >= pool.size() or j.spec_tries >= 700:
		j.spec_i += 1
		j.spec_on = false


# --- Drill yard -------------------------------------------------------------------------------------------------------

static func _start_drill(j: Job) -> void:
	var present := false
	for a: Dictionary in j.plan["district_anchors"]:
		if a["kind"] == Districts.MILITARY:
			present = true
	if not present:
		_start_mud(j)
		return
	j.best = Vector2.INF
	j.best_room = 0.0
	_next(j, PH_DRILL_SCAN)
	j.gx = -j.ctx.r


## The training yard: the roomiest free ground in the military ward gets a row of straw dummies, weapon racks and hay
## targets. The scan takes one grid column per unit.
static func _drill_column(j: Job) -> void:
	var ctx := j.ctx
	var step := 2.5
	var gz := -ctx.r
	while gz <= ctx.r:
		var p := ctx.c + Vector2(j.gx, gz)
		gz += step
		if p.distance_to(ctx.c) > ctx.r - 12.0 or Districts.nearest_kind(j.plan["district_anchors"], p) != Districts.MILITARY:
			continue
		var room := 9.0
		while room > 5.0 and not ctx.ok_at(p, room, 1.0):
			room -= 1.0
		if room > j.best_room or (room == j.best_room and j.best == Vector2.INF):
			j.best_room = room
			j.best = p
	j.gx += step
	if j.gx > ctx.r:
		_next(j, PH_DRILL_PLACE)


static func _drill_place(j: Job) -> void:
	var best := j.best
	var best_room := j.best_room
	if best == Vector2.INF or best_room < 5.5:
		_start_mud(j)
		return
	var batches := j.batches
	var stage := j.cur
	j.cur += 1                              # three stages (dummies / hay + racks / banner), one per unit
	# Face the yard toward the nearest street.
	var sdir := Vector2.DOWN
	var bd := INF
	for st: Dictionary in j.plan["streets"]:
		var q := Geometry2D.get_closest_point_to_segment(best, st["a"], st["b"])
		if best.distance_to(q) < bd:
			bd = best.distance_to(q)
			sdir = (q - best).normalized()
	var yaw := atan2(sdir.x, sdir.y)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var span := best_room - 1.8
	if stage == 0:
		for i in 4:
			var q := best - fwd * span * 0.35 + side * (-1.5 + i) * 2.1
			_add(batches, "g:region/farm/scarecrow", q, yaw + PI, 1.0)
	elif stage == 1:
		for i in 3:
			var q2 := best + fwd * span * 0.45 + side * (-1.0 + i) * 2.6
			_add(batches, "hay", q2, yaw + PI, 1.0)
		for sg: float in [-1.0, 1.0]:
			var q3 := best + side * sg * span * 0.8
			if _add(batches, "weapon_rack", q3, yaw + sg * PI * 0.5, 1.0):
				j.solid_ids["weapon_rack"] = true
	else:
		_add(batches, "banner_pole", best + fwd * span * 0.8 - side * span * 0.6, yaw, 1.0)
		j.ctx.claim(best, best_room)
		j.marks["yard"] = best
		_start_mud(j)


# --- Mud --------------------------------------------------------------------------------------------------------------

## After the drill yard (the phase order of the old build): the mud lanes, or straight to the flush on LOW.
static func _start_mud(j: Job) -> void:
	if j.low:
		_flush_init(j)
	else:
		j.rng.seed = 8317 + int(j.s["id"])
		j.mud_n = 0
		_next(j, PH_MUD)


## Muddy lanes: brown ground decals along the poor quarter's streets and a few puddles (one street per unit).
static func _mud_street(j: Job) -> void:
	var ctx := j.ctx
	var rng := j.rng
	var streets: Array = j.plan["streets"]
	if j.cur >= streets.size():
		_flush_init(j)
		return
	var st: Dictionary = streets[j.cur]
	j.cur += 1
	var w: float = st["w"]
	if w >= 11.0:
		return
	var a: Vector2 = st["a"]
	var bb: Vector2 = st["b"]
	var length := a.distance_to(bb)
	var dir := (bb - a) / maxf(length, 0.001)
	var t := rng.randf_range(1.0, 5.0)
	while t < length:
		var p := a + dir * t + Vector2(-dir.y, dir.x) * rng.randf_range(-1.0, 1.0)
		if Districts.nearest_kind(j.plan["district_anchors"], p) == Districts.POOR and p.distance_to(ctx.c) > ctx.plaza_r + 6.0 and j.mud_n < 28:
			var kind := "dirt" if rng.randf() < 0.6 else "puddle"
			var tint := Color(0.62, 0.46, 0.3, 0.95) if kind == "dirt" else Color(1, 1, 1, 0.92)
			j.decals.append([kind, Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y), Basis(Vector3.UP, atan2(dir.x, dir.y)),
				Vector3(rng.randf_range(3.0, 4.6), 2.0, rng.randf_range(4.0, 7.0)), tint, TownDecals.GROUND_LAYER])
			j.mud_n += 1
		t += rng.randf_range(5.0, 9.0)


# --- Flush: MultiMeshes, decals, smoke --------------------------------------------------------------------------------

## Batch one mesh id into 40 m cells; solid ids get colliders. Wall-mounted ids (hanging_...) are named so the world
## lint knows they hang on a wall on purpose. One id is split into cells per unit, one cell becomes a MultiMesh per unit.
static func _flush_init(j: Job) -> void:
	j.holder = Node3D.new()
	j.holder.name = "DistrictProps"
	j.root.add_child(j.holder)
	j.ids = j.batches.keys()
	_next(j, PH_FLUSH)


static func _flush_unit(j: Job) -> void:
	if not j.work.is_empty():
		var w: Array = j.work.pop_back()
		var wid: String = w[0]
		var mmi: MultiMeshInstance3D = j.b._multimesh(j.holder, w[1], w[2], not j.hanging.has(wid), j.solid_ids.has(wid))
		if mmi:
			mmi.name = ("hanging_" if j.hanging.has(wid) else "dp_") + wid.replace(":", "_").replace("/", "_")
		return
	if j.cur >= j.ids.size():
		# Decals next (none on LOW, none without the decal shader).
		if j.low or j.decals.is_empty() or not TownDecals.available():
			_next(j, PH_SMOKE)
		else:
			var dh := Node3D.new()
			dh.name = "DetailDecals"
			j.root.add_child(dh)
			j.holder = dh
			_next(j, PH_DECALS)
		return
	var id: String = j.ids[j.cur]
	j.cur += 1
	var mesh := TownIdentity.mesh_variant(j.prof, id)     # banners, wall banners and awnings in the town's colours
	if mesh == null:
		mesh = _mesh_of(id)
	if mesh == null:
		return
	if j.low and not j.hanging.has(id) and maxi(mesh.get_surface_count(), int(mesh.get_meta("orig_surfaces", 0))) >= LOW_MAX_SURFACES:
		return     # LOW: a 4+ material prop (haystack, ore pile) is 4+ draw calls for a speck of the street
	var cell := CELL
	var groups := {}
	for t: Transform3D in j.batches[id]:
		var k := Vector2i(floori(t.origin.x / cell), floori(t.origin.z / cell))
		if not groups.has(k):
			groups[k] = [] as Array[Transform3D]
		(groups[k] as Array[Transform3D]).append(t)
	# Same cell order as the old flush: the queue is popped from the back, so push reversed.
	var keys: Array = groups.keys()
	keys.reverse()
	for k: Vector2i in keys:
		j.work.append([id, mesh, groups[k]])


static func _decal_unit(j: Job) -> void:
	if j.cur >= j.decals.size():
		_next(j, PH_SMOKE)
		return
	var d: Array = j.decals[j.cur]
	j.cur += 1
	if d.size() > 6 and d[6] == "roof":
		if j.roofs >= DECAL_CAP:
			return
		j.roofs += 1
	else:
		var at: Vector3 = d[1]
		var ck := Vector2i(floori(at.x / 64.0), floori(at.z / 64.0))
		if int(j.chunks.get(ck, 0)) >= MUD_PER_CHUNK:
			return
		j.chunks[ck] = int(j.chunks.get(ck, 0)) + 1
	var dec := TownDecals.make(String(d[0]), d[3], int(d[5]), d[4])
	j.holder.add_child(dec)
	dec.global_transform = Transform3D(d[2], d[1])
