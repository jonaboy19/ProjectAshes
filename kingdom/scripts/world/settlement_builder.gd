class_name SettlementBuilder
extends Node3D

## Distance where Meshy hero buildings swap to their light LOD.
const DistanceCull := preload("res://scripts/core/distance_cull.gd")
const HERO_LOD := 70.0
## Buildings and greenery are batched per model per LOD_CELL x LOD_CELL metres.
const LOD_CELL := 40.0
const WIDE_CELL := 100.0
const MID_CELL := 60.0
## Builds settlements from their CityPlanner layout when the focus comes within
## BUILD_RANGE and frees them past FREE_RANGE. Buildings of the same model are
## drawn as one MultiMesh (a capital has ~300 buildings but only ~15 draw
## calls); each lot still gets a cheap compound collider (BuildingProfiles:
## body + porch/eaves boxes, shapes shared per model) so streets feel solid,
## and every enterable building an InteriorDoor at its front door.

const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const Breakable := preload("res://scripts/world/breakable.gd")

const BUILD_RANGE := 650.0
const FREE_RANGE := 850.0
## Mirrors Player.CAMERA_BLOCKER_LAYER: a camera-only occlusion layer for props
## whose walk-collision box is deliberately smaller than their visual mesh
## (market stall awnings/cloth canopies extend past the ~0.9x footprint box
## used for walking), so the chase camera still gets pulled out from inside
## them. Never added to the player's own collision_mask, so movement is
## unaffected.
const CAMERA_BLOCKER_LAYER := 1 << 9
## Wall colliders beside a gate end this far short of the wall section (see _wall_ring).
const GATE_JAMB := 0.9

signal settlement_built(settlement: Dictionary, root: Node3D)

var focus := Vector3.ZERO
var _built: Dictionary = {}      # id -> Node3D
var _timer := 0.0
var _footprints: Dictionary = {} # asset -> Vector3 size at BUILDING_SCALE
## settlement id -> [[stall key, position, yaw, solid index], ...] of the gate-market stalls (QA shots, tests).
var stalls_by_town: Dictionary = {}


func _process(delta: float) -> void:
	Breakable.tick(delta)   # breakable clutter: melee sweep + regrowth (once per frame)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	update_now()


func update_now() -> void:
	var p := Vector2(focus.x, focus.z)
	for s in WorldGen.settlements:
		var d: float = p.distance_to(s["pos"]) - s["radius"]
		var id: int = s["id"]
		if d < BUILD_RANGE and not _built.has(id):
			_built[id] = _build(s)
			settlement_built.emit(s, _built[id])
			return          # one per tick keeps frame times smooth
		elif d > FREE_RANGE and _built.has(id):
			_built[id].queue_free()
			_built.erase(id)


func _build(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = s["name"]
	add_child(root)
	var plan: Dictionary = s["plan"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + s["id"]

	# Houses and shops, batched by model and LOD_CELL: a MultiMesh switches LOD as a
	# whole (by its bounds' centre), so one town-wide batch drew every house at the
	# near LOD; per-cell batches let the far side of town use LOD2/LOD3.
	# Grounding: every lot used to sit at the settlement's single flat base_h.
	# WorldGen.height() *does* flatten the ground to base_h inside the settlement
	# radius (see world_gen.gd height()), but it also cuts a shallow bed under
	# streets (-0.4 m) inside that same flattened area, and a lot's footprint can
	# poke past the flatten radius into the blended slope beyond it -- both put
	# real ground below/above the flat base_h a building was drawn at, which is
	# exactly what the grounding scanner caught (median 29 cm, max 1.9 m). Snap
	# each lot to its own footprint's ground per-instance instead, the same way
	# RegionDressing._footprint_ground() already does for region-site buildings,
	# and applied here before the per-cell MultiMesh batching below (so it costs
	# nothing per frame -- one extra WorldGen.height() sample per corner, once,
	# at settlement-build time).
	var batches := {}
	var plinths: Array = []   # [pos, yaw, size, ground_y] for _plinths() below
	for lot in plan["lots"]:
		var p: Vector2 = lot["pos"]
		var asset: String = lot["asset"]
		# (Only models with a LOD chain gain from cells; the rest stay one batch per town.)
		# (Meshy only: the Blender houses have 4-6 materials each, so per-cell batches
		# of them cost more draw calls than their triangles save.)
		var celled := Assets.building_lod_level_distance(asset, 3) > 0.0
		# Perf pass 2026-09-29: multi-material Blender houses with a single LOD used to be one
		# town-wide MultiMesh; a MultiMesh is only frustum-culled as a whole, so every house
		# (4.5k tris x 4 surfaces) was submitted even behind the camera. 100 m cells keep the
		# draw-call count low but let the far side of a capital be culled.
		var wide := not celled and Assets.building_lod_mesh(asset) != null
		# Round 2: houses with a baked LOD2 (1.2-1.4k tris, one material) switch per 60 m cell so
		# the far side of a street drops to LOD2 while the near side keeps LOD1.
		var cs := LOD_CELL if celled else (MID_CELL if Assets.building_lod2_distance(asset) > 0.0 else WIDE_CELL)
		var bkey := "%s@%d,%d" % [asset, floori(p.x / cs), floori(p.y / cs)] if (celled or wide) else asset + "@"
		if not batches.has(bkey):
			batches[bkey] = []
		var size := _footprint(asset)
		var gh := _ground_snap(p, lot["yaw"], size)
		var t := Transform3D(Basis(Vector3.UP, lot["yaw"]), Vector3(p.x, gh, p.y))
		batches[bkey].append(t)
		var body := BuildingProfiles.make_body(asset, size)
		body.position = Vector3(p.x, gh, p.y)
		body.rotation.y = lot["yaw"]
		root.add_child(body)
		plinths.append([p, lot["yaw"], size, gh, asset])
	_plinths(root, plinths)
	_seal_gaps(root, plinths)
	for bkey: String in batches:
		var asset := bkey.get_slice("@", 0)
		var list: Array[Transform3D] = []
		list.assign(batches[bkey])
		var lod := Assets.building_lod_mesh(asset)
		if lod:
			# LOD chain as MultiMeshes with hard range switches: detailed model up close,
			# its light version beyond HERO_LOD / the entry's distance, and (Meshy
			# buildings) LOD2 (3.5-7k tris) and LOD3 (~1k tris) further out.
			# LOW (old phones) never loads the 20-40k LOD0: LOD1 up close, LOD2 past
			# ~25 m, LOD3 past ~55 m (45 / 100 m x LOW's 0.55 range scale).
			# Applies to towns built after a tier change.
			var low := Assets.building_lod2_mesh(asset) != null and _low()
			var chain: Array = []      # [mesh, begin distance]
			var d1 := Assets.building_lod_distance(asset)
			if d1 <= 0.0:
				d1 = HERO_LOD
			if low:
				chain = [[lod, 0.0], [Assets.building_lod_level_mesh(asset, 2), 45.0], [Assets.building_lod_level_mesh(asset, 3), 100.0]]
			else:
				chain = [[Assets.building_mesh(asset), 0.0], [lod, d1]]
				for lv in [2, 3]:
					if Assets.building_lod_level_mesh(asset, lv):
						chain.append([Assets.building_lod_level_mesh(asset, lv), Assets.building_lod_level_distance(asset, lv)])
			chain = chain.filter(func(c: Array) -> bool: return c[0] != null)
			for i in chain.size():
				var mm := _multimesh(root, chain[i][0], list, i == 0)
				mm.layers |= TownDecals.WALL_LAYER      # receives wall decals (see _decals)
				mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				mm.visibility_range_begin = chain[i][1]
				mm.visibility_range_begin_margin = 10.0 if i > 0 else 0.0
				mm.visibility_range_end = chain[i + 1][1] if i + 1 < chain.size() else 0.0
				mm.visibility_range_end_margin = 10.0 if i + 1 < chain.size() else 0.0
		else:
			var hm := _multimesh(root, Assets.building_mesh(asset), list)
			if hm:
				hm.layers |= TownDecals.WALL_LAYER
		_chimney_smoke(root, asset, list, rng)

	_interior_doors(root, plan["lots"])

	# Lived-in door_clutter by the doors: painted crates, barrels and sacks.
	# Small props (< 4 sqm), so _ground_snap point-samples under each one instead of
	# assuming the lot's flat base_h -- avoids a crate floating/sinking by the same
	# amount the building next to it now corrects for.
	var door_clutter := {}
	var kinds := ["crate", "sack_pile", "barrel"]
	for lot in plan["lots"]:
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		for k in rng.randi_range(1, 3):
			var kind: String = kinds[rng.randi() % kinds.size()]
			var q := p + fwd * rng.randf_range(3.6, 4.4) + side * rng.randf_range(-3.2, 3.2) * (1.0 if k % 2 == 0 else -1.0)
			if not door_clutter.has(kind):
				door_clutter[kind] = []
			door_clutter[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, WorldGen.height(q.x, q.y) - 0.03, q.y)))
	for kind: String in door_clutter:
		var list2: Array[Transform3D] = []
		list2.assign(door_clutter[kind])
		# Round 2: per 40 m cell (was one town-wide MultiMesh: ~190 crates/barrels/sacks drawn from anywhere).
		_multimesh_cells(root, Assets.building_mesh(kind), list2, LOD_CELL)

	for lm in plan["landmarks"]:
		var lm_size := _footprint(lm["asset"])
		_piece(root, lm["asset"], lm["pos"], _ground_snap(lm["pos"], lm["yaw"], lm_size), lm["yaw"])
	# Market stalls and carts ringing the plaza. Plaza-radius footprint estimate
	# (real stall assets are ~3-4 m): close enough for a per-instance ground snap,
	# and cheap since it only samples the 4 corners once per stall at build time.
	var stalls: Array[Transform3D] = []
	var stalls2: Array[Transform3D] = []
	var pr: float = plan["plaza_r"]
	var n_stalls := 6 if s["kind"] == "village" else 12
	var stall_size := Vector3(3.5, 2.5, 3.5)
	for i in n_stalls:
		var ang := TAU * i / n_stalls + 0.2
		var sp: Vector2 = s["pos"] + Vector2(cos(ang), sin(ang)) * (pr - 3.0)
		var syaw := atan2(-cos(ang), -sin(ang))
		var st := Transform3D(Basis(Vector3.UP, syaw), Vector3(sp.x, _ground_snap(sp, syaw, stall_size), sp.y))
		(stalls if i % 2 == 0 else stalls2).append(st)
	# Keep the current four-model layout; each visible stall gets a box proxy.
	# Four stall palettes, alternated around the plaza.
	var st_a: Array[Transform3D] = []
	var st_b: Array[Transform3D] = []
	for k in stalls.size():
		(st_a if k % 2 == 0 else st_b).append(stalls[k])
	for k in stalls2.size():
		(st_a if k % 2 == 1 else st_b).append(stalls2[k])
	# The Meshy stalls (1 and 2) were modelled facing the other way: turn them to the plaza.
	var turn := Basis(Vector3.UP, PI)
	for k in st_a.size():
		if k < (st_a.size() + 1) / 2:
			st_a[k] = Transform3D(st_a[k].basis * turn, st_a[k].origin)
	for k in st_b.size():
		if k < (st_b.size() + 1) / 2:
			st_b[k] = Transform3D(st_b[k].basis * turn, st_b[k].origin)
	var stand_1_a := st_a.slice(0, (st_a.size() + 1) / 2)
	var stand_3_a := st_a.slice((st_a.size() + 1) / 2)
	var stand_2_b := st_b.slice(0, (st_b.size() + 1) / 2)
	var stand_4_b := st_b.slice((st_b.size() + 1) / 2)
	var activity_spots: Array[Dictionary] = []
	for group_name in ["a", "b"]:
		var placements: Array = st_a if group_name == "a" else st_b
		for i in placements.size():
			var placement: Transform3D = placements[i]
			activity_spots.append({"type": "market_stall", "position": placement.origin,
				"yaw": placement.basis.get_euler().y, "identity": "market/plaza/%s/%d" % [group_name, i]})
	plan["activity_spots"] = activity_spots
	_multimesh(root, Assets.building_mesh("market_stand_1"), stand_1_a, true, true)
	_multimesh(root, Assets.building_mesh("market_stand_3"), stand_3_a, true, true)
	_multimesh(root, Assets.building_mesh("market_stand_2"), stand_2_b, true, true)
	_multimesh(root, Assets.building_mesh("market_stand_4"), stand_4_b, true, true)
	# Camera-only occlusion: the walk-collision boxes above are shrunk 0.9x and
	# don't reliably cover cloth awnings/canopies that billow past the stall's
	# footprint, which let the chase camera dip inside them (playtest: black
	# awning-interior fill in Ashford's market). See _add_camera_blockers().
	_add_camera_blockers(root, Assets.building_mesh("market_stand_1"), stand_1_a)
	_add_camera_blockers(root, Assets.building_mesh("market_stand_3"), stand_3_a)
	_add_camera_blockers(root, Assets.building_mesh("market_stand_2"), stand_2_b)
	_add_camera_blockers(root, Assets.building_mesh("market_stand_4"), stand_4_b)

	var c: Vector2 = s["pos"]
	if plan["walls"]:
		_wall_ring(root, c, plan["wall_radius"], plan["gates"], 40, 5)
	if plan["inner_wall"] > 0.0:
		_wall_ring(root, c, plan["inner_wall"], plan["gates"], 16, 4)

	# Countryside: windmills, lumber mill and fields outside the walls.
	var r: float = s["radius"]
	var gates: Array[float] = []
	gates.assign(plan["gates"])
	for i in (2 if s["kind"] == "village" else 3):
		var ang := rng.randf() * TAU
		if CityPlanner._near_angle(ang, gates, 0.3):
			continue
		var p := c + Vector2(cos(ang), sin(ang)) * r * rng.randf_range(1.2, 1.45)
		_piece(root, "mill", p, WorldGen.height(p.x, p.y), rng.randf() * TAU)
	_fields(root, s, plan, rng, gates)
	_homesteads(root, s, plan, rng)
	_gate_outskirts(root, s, plan, gates)
	_footprint_clutter(root, plan, rng)
	_square_lamps(root, s, plan)
	if s["kind"] != "village":
		_gate_market(root, s, plan, rng)
	else:
		_village_square(root, s, plan, rng)
	_greenery(root, s, plan, rng)
	# Street clutter.
	var street_clutter: Array[Transform3D] = []
	for i in 30:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(plan["plaza_r"] * 0.6, plan["plaza_r"] + 3.0)
		street_clutter.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.03, p.y)))
	# Barrels, crates and baskets break when struck (see breakable.gd); carts stay solid.
	_multimesh(root, Assets.building_mesh("barrel"), street_clutter.slice(0, 10), true, true, "barrel")
	_multimesh(root, Assets.building_mesh("crate"), street_clutter.slice(10, 18), true, true, "crate")
	_multimesh(root, Assets.building_mesh("sack_pile"), street_clutter.slice(18, 24), true, true, "sack_pile")
	_multimesh(root, Assets.building_mesh("cart"), street_clutter.slice(24), true, true)
	_decals(root, s, plan)
	_flush_contact_shadows(root)
	return root


## One InteriorDoor per enterable lot (inn, smithy, guild, healer, every house),
## on the ground at its front door, local +Z out into the street. They are idle
## triggers: masked to the player's trigger layer only, not monitorable, and
## with no per-frame work until the player stands in one (see interior_door.gd).
## Kept under "Doors" so VillageServices can find them.
func _interior_doors(root: Node3D, lots: Array) -> void:
	var holder := Node3D.new()
	holder.name = "Doors"
	root.add_child(holder)
	for lot: Dictionary in lots:
		var asset: String = lot["asset"]
		if not BuildingProfiles.is_enterable(asset):
			continue
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var size := _footprint(asset)
		var local := BuildingProfiles.door_local(asset, size)
		var at := BuildingProfiles.door_point(lot, size)
		var gh := _ground_snap(p, yaw, size)
		var door := InteriorDoor.new()
		door.name = "Door_%s_%d" % [asset, holder.get_child_count()]
		door.interior_scene = BuildingProfiles.interior_scene(asset)
		door.prompt_text = BuildingProfiles.prompt(asset)
		door.collision_layer = 0
		door.collision_mask = InteriorDoor.PLAYER_TRIGGER_LAYER
		door.monitorable = false
		door.set_meta("asset", asset)
		door.set_meta("lot_pos", p)
		var shape := CollisionShape3D.new()
		shape.shape = BuildingProfiles.door_shape()
		shape.position.y = 1.1
		door.add_child(shape)
		door.position = Vector3(at.x, gh + local.y, at.y)
		door.rotation.y = yaw
		holder.add_child(door)


## Footprint-aware ground height for a building/prop lot, mirroring
## RegionDressing._footprint_ground() (same corner-snap idea, applied here to
## settlement buildings/props instead of region-site parts). Lowest of the
## footprint's 4 corners (shrunk so a rotated corner doesn't oversample past a
## neighbouring lot's lower ground) minus a small sink, so the object never
## floats -- it sits very slightly into the uphill side of its own footprint
## instead. See _plinths() for hiding that with a stone base.
static func _ground_snap(p: Vector2, yaw: float, size: Vector3, sink: float = 0.08) -> float:
	var lowest := WorldGen.height(p.x, p.y)
	if size.x * size.z < 4.0:
		return lowest - sink
	var basis := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.4
	var hz := size.z * 0.4
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var off := basis * Vector3(c.x, 0.0, c.y)
		lowest = minf(lowest, WorldGen.height(p.x + off.x, p.y + off.y))
	return lowest - sink


## How much the footprint's ground varies corner to corner (0 on flat ground),
## so _plinths() can reach the highest corner too.
static func _ground_spread(p: Vector2, yaw: float, size: Vector3) -> float:
	if size.x * size.z < 4.0:
		return 0.0
	var basis := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.4
	var hz := size.z * 0.4
	var lo := INF
	var hi := -INF
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var off := basis * Vector3(c.x, 0.0, c.y)
		var h := WorldGen.height(p.x + off.x, p.y + off.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


static var _plinth_mesh: BoxMesh


## A stone plinth under every building lot, sized to its footprint and
## reaching down to the lowest corner WorldGen actually put under it (plus a
## margin) so a sloped or street-adjacent lot never shows a gap on its uphill
## side -- the Meshy/Blender house models have no base geometry of their own.
## One shared unit box mesh, one MultiMesh for the whole settlement (not per
## model): this is purely a grounding fix, it doesn't need per-asset LOD
## batching. Built once at settlement-build time, no per-frame cost.
func _plinths(root: Node3D, lots: Array) -> void:
	if lots.is_empty():
		return
	if _plinth_mesh == null:
		_plinth_mesh = BoxMesh.new()
		_plinth_mesh.size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.66, 0.60, 0.50)   # warm tan stone, not dark brown under the sun
		mat.roughness = 0.95
		_plinth_mesh.material = mat
	var transforms: Array[Transform3D] = []
	for entry in lots:
		var p: Vector2 = entry[0]
		var yaw: float = entry[1]
		var size: Vector3 = entry[2]
		var gh: float = entry[3]
		var spread: float = _ground_spread(p, yaw, size)
		var h: float = maxf(0.2, spread + 0.25)   # always at least a visible course of stone
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size.x * 0.92, h, size.z * 0.92)),
			Vector3(p.x, gh - 0.1 + h * 0.5, p.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _plinth_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BuildingPlinths"
	mmi.multimesh = mm
	mmi.visibility_range_end = 200.0
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mmi)


func _footprint(asset: String) -> Vector3:
	if not _footprints.has(asset):
		# (LOD1 is fitted to the same size; on LOW it keeps LOD0 from loading at all.)
		var low := _low() and Assets.building_lod2_distance(asset) > 0.0
		var mesh := Assets.building_lod_mesh(asset) if low else Assets.building_mesh(asset)
		_footprints[asset] = mesh.get_aabb().size if mesh else Vector3(8, 8, 8)
	return _footprints[asset]


## True on the LOW quality tier (looked up by path so tools running without autoloads still work).
static func _low() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var q: Node = tree.root.get_node_or_null("/root/Quality") if tree else null
	return q != null and q.tier == q.LOW


func _piece(root: Node3D, asset: String, p: Vector2, h: float, yaw: float) -> Node3D:
	var node := Assets.building_node(asset)
	node.position = Vector3(p.x, h, p.y)
	node.rotation.y = yaw
	root.add_child(node)
	return node


## Stone wall ring (Quaternius RTS pieces stretched to each segment) with towers,
## leaving gatehouses where roads enter.
func _wall_ring(root: Node3D, c: Vector2, radius: float, gates: Array, segments: int, tower_every: int) -> void:
	var wall_mesh := Assets.building_mesh("wall")
	var tower_mesh := Assets.building_mesh("wall_tower")
	var gate_mesh := Assets.building_mesh("wall_gate")
	if wall_mesh == null:
		return
	var native := wall_mesh.get_aabb()
	var native_len := maxf(native.size.x, native.size.z)
	var along_x := native.size.x > native.size.z
	# Real-size sections (the Blender wall is 8 m long) instead of stretching a few;
	# a tower roughly every 48 m.
	segments = maxi(12, int(round(TAU * radius / native_len)))
	tower_every = maxi(3, int(round(48.0 / native_len)))
	var seg_len := TAU * radius / segments
	var s := seg_len / maxf(native_len, 0.01)          # uniform: keeps the wall's proportions
	# Lay the ring out from the gates: each gate opening is centred exactly on its street's
	# axis (a uniform ring left the opening up to half a section off the road, so the road's
	# own centre line ran into the wall), and the sections between two gates are divided
	# evenly (scale within a few % of s).
	var pieces: Array = []      # [a0, a1, is_gate, first_after_gate, last_before_gate]
	var gate_angles: Array[float] = []
	for g in gates:
		gate_angles.append(fposmod(float(g), TAU))
	gate_angles.sort()
	if gate_angles.is_empty():
		for i in segments:
			pieces.append([TAU * i / segments, TAU * (i + 1) / segments, false, false, false])
	else:
		var half := seg_len * 0.5 / radius
		for k in gate_angles.size():
			var g0: float = gate_angles[k]
			var g1: float = gate_angles[(k + 1) % gate_angles.size()]
			pieces.append([g0 - half, g0 + half, true, false, false])
			var arc_a := g0 + half
			var arc_b := g1 - half + (TAU if g1 <= g0 else 0.0)
			var n := maxi(1, int(round((arc_b - arc_a) * radius / seg_len)))
			if arc_b - arc_a < 0.5 * seg_len / radius:
				continue
			for i in n:
				pieces.append([arc_a + (arc_b - arc_a) * i / n, arc_a + (arc_b - arc_a) * (i + 1) / n, false, i == 0, i == n - 1])
	var walls: Array[Transform3D] = []
	var gate_walls: Array[Transform3D] = []
	var towers: Array[Transform3D] = []
	var wall_i := 0
	for piece: Array in pieces:
		var a0: float = piece[0]
		var a1: float = piece[1]
		var p0 := c + Vector2(cos(a0), sin(a0)) * radius
		var p1 := c + Vector2(cos(a1), sin(a1)) * radius
		var dir := p1 - p0
		var chord := dir.length()
		var yaw := atan2(dir.x, dir.y) + (PI * 0.5 if along_x else 0.0)
		var mp := (p0 + p1) * 0.5
		var is_gate: bool = piece[2]
		var ps := s if is_gate else chord / maxf(native_len, 0.01)
		# Per-segment ground sample (not the settlement's flat base_h): the wall
		# ring sits right at the edge of WorldGen's flatten radius, where a segment
		# can already be in the blended slope beyond it.
		var h := WorldGen.height(mp.x, mp.y) - 0.05
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * ps), Vector3(mp.x, h, mp.y))
		(gate_walls if is_gate else walls).append(t)
		if not is_gate:
			# Sections beside a gate stop GATE_JAMB short of their visual end, so the opening is
			# 8 m + 2 x 0.9 m: the gate road's kerb lanes (+-4.3 m) still fit through.
			var t0: float = GATE_JAMB if bool(piece[3]) else 0.0
			var t1: float = GATE_JAMB if bool(piece[4]) else 0.0
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.8, native.size.y * ps, maxf(0.5, chord - t0 - t1))
			shape.shape = box
			var dn := dir / maxf(chord, 0.001)
			var mc := mp + dn * ((t0 - t1) * 0.5)
			body.position = Vector3(mc.x, h + native.size.y * ps * 0.5, mc.y)
			body.rotation.y = atan2(dir.x, dir.y)
			body.add_child(shape)
			root.add_child(body)
			if wall_i % tower_every == 0:
				towers.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * ps * 1.05), Vector3(p0.x, h, p0.y)))
			wall_i += 1
	# Per 150 m stretch of wall, so the automatic mesh LODs pick the far side's
	# distance instead of the whole ring's (a capital ring is ~160 pieces, 0.4 M tris).
	# Round 2: 70 m cells (was 150) for walls/gates/towers: a MultiMesh draws every instance once any
	# part of its AABB is on screen, so a 150 m cell of 1.7-13k tri pieces was mostly wasted.
	_lod_cells(root, "wall", walls, 70.0)
	_lod_cells(root, "wall_gate" if gate_mesh else "wall", gate_walls, 70.0)
	_lod_cells(root, "wall_tower", towers, 70.0)


## Per-cell MultiMeshes of an Assets.BUILDINGS entry with its LOD1/LOD2 stages as hard visibility-range
## switches (same scheme as the house lots).
func _lod_cells(parent: Node3D, key: String, transforms: Array[Transform3D], cell: float) -> void:
	var stages: Array = [[Assets.building_mesh(key), 0.0]]
	for lv in [1, 2]:
		var m := Assets.building_lod_level_mesh(key, lv)
		if m != null:
			stages.append([m, Assets.building_lod_level_distance(key, lv)])
	var groups := {}
	for t: Transform3D in transforms:
		var k := Vector2i(floori(t.origin.x / cell), floori(t.origin.z / cell))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(t)
	for k: Vector2i in groups:
		var list: Array[Transform3D] = []
		list.assign(groups[k])
		for i in stages.size():
			var mmi := _multimesh(parent, stages[i][0], list, false)
			if mmi == null:
				continue
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.visibility_range_begin = stages[i][1]
			mmi.visibility_range_begin_margin = 10.0 if i > 0 else 0.0
			mmi.visibility_range_end = stages[i + 1][1] if i + 1 < stages.size() else 0.0
			mmi.visibility_range_end_margin = 10.0 if i + 1 < stages.size() else 0.0


## Instanced placement. Culls by object size (small clutter vanishes first) and,
## unless blob is false, grounds each instance with a soft contact shadow.
## A `breakable` kind (Breakable.KINDS) makes each instance collider breakable.
func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], blob := true, collide := false, breakable := "", shadow := true) -> MultiMeshInstance3D:
	if mesh == null or transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var box := mesh.get_aabb()
	var extent := maxf(box.size.x, box.size.z)
	# Round 2: on LOW, props under 1.6 m (crates, barrels, sacks, decals' planes) never cast shadows.
	if not shadow or (extent < 1.6 and _low()):
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # small goods: no shadow-map cost
	var cull := 70.0 if extent < 1.6 else (150.0 if extent < 4.5 else (380.0 if extent < 12.0 else 0.0))
	if cull > 0.0:
		mmi.visibility_range_end = cull
		mmi.visibility_range_end_margin = cull * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	if collide:
		_add_instance_colliders(parent, mesh, transforms, mm, breakable)
	if blob and extent < 18.0:
		_contact_shadows(parent, box, transforms, cull)
	return mmi


## _multimesh() split into cell x cell metre batches, so visibility ranges (and
## LOD) work per neighbourhood instead of per town; `cull` > 0 overrides the range.
func _multimesh_cells(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], cell: float, cull := 0.0, blob := true, shadow := true) -> void:
	var groups := {}
	for t: Transform3D in transforms:
		var k := Vector2i(floori(t.origin.x / cell), floori(t.origin.z / cell))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(t)
	for k: Vector2i in groups:
		var list: Array[Transform3D] = []
		list.assign(groups[k])
		var mmi := _multimesh(parent, mesh, list, blob, false, "", shadow)
		if mmi and cull > 0.0:
			mmi.visibility_range_end = cull
			mmi.visibility_range_end_margin = cull * 0.1


## Distance from a point to a yawed rectangle (half extents hx, hz) centred on c, in XZ.
## The rectangle's axes are the ones Basis(UP, yaw) gives a placed prop.
static func _rect_pt_dist(p: Vector2, c: Vector2, yaw: float, hx: float, hz: float) -> float:
	var v := p - c
	var lx := v.x * cos(yaw) - v.y * sin(yaw)
	var lz := v.x * sin(yaw) + v.y * cos(yaw)
	return Vector2(maxf(absf(lx) - hx, 0.0), maxf(absf(lz) - hz, 0.0)).length()


static func _rect_segment_dist(c: Vector2, yaw: float, hx: float, hz: float, a: Vector2, b: Vector2) -> float:
	var best := INF
	var n := maxi(1, int(a.distance_to(b) / 0.4))
	for i in n + 1:
		best = minf(best, _rect_pt_dist(a.lerp(b, float(i) / n), c, yaw, hx, hz))
	return best


static func _rect_poly(c: Vector2, yaw: float, hx: float, hz: float) -> PackedVector2Array:
	var ex := Vector2(cos(yaw), -sin(yaw))
	var ez := Vector2(sin(yaw), cos(yaw))
	return PackedVector2Array([c - ex * hx - ez * hz, c + ex * hx - ez * hz, c + ex * hx + ez * hz, c - ex * hx + ez * hz])


## Closest pair of boundary points of two convex polygons: [distance, on a, on b];
## distance 0 when they overlap.
static func _poly_closest(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	if not Geometry2D.intersect_polygons(a, b).is_empty():
		return [0.0, Vector2.ZERO, Vector2.ZERO]
	var best := [INF, Vector2.ZERO, Vector2.ZERO]
	for i in a.size():
		for j in b.size():
			var b0 := b[j]
			var b1 := b[(j + 1) % b.size()]
			var a0 := a[i]
			var a1 := a[(i + 1) % a.size()]
			var qb := Geometry2D.get_closest_point_to_segment(a0, b0, b1)
			if a0.distance_to(qb) < best[0]:
				best = [a0.distance_to(qb), a0, qb]
			var qa := Geometry2D.get_closest_point_to_segment(b0, a0, a1)
			if b0.distance_to(qa) < best[0]:
				best = [b0.distance_to(qa), qa, b0]
	return best


static func _rect_gap(c1: Vector2, y1: float, hx1: float, hz1: float, c2: Vector2, y2: float, hx2: float, hz2: float) -> float:
	return _poly_closest(_rect_poly(c1, y1, hx1, hz1), _rect_poly(c2, y2, hx2, hz2))[0]


## Slots between two buildings that a player can walk into but not out of comfortably
## (the capsule is 0.7 m wide) are wedge traps. A gap narrower than MIN_LOT_GAP between two
## lots' wall colliders is closed with a solid filler across the facing walls, so every
## passage between buildings is either >= 1.4 m or shut. Overlapping lots have no slot.
const MIN_LOT_GAP := 1.4


func _seal_gaps(root: Node3D, plinths: Array) -> void:
	var polys: Array = []
	for e: Array in plinths:
		var asset_size: Vector3 = e[2]
		var yaw: float = e[1]
		var wall := BuildingProfiles.HOUSE_WALL if BuildingProfiles.is_house(String(e[4])) else BuildingProfiles.HERO_WALL
		var ww := asset_size.x * wall
		var wd := asset_size.z * wall
		polys.append(_rect_poly(e[0], yaw, ww, wd))
	for i in polys.size():
		for j in range(i + 1, polys.size()):
			if (plinths[i][0] as Vector2).distance_to(plinths[j][0]) > 26.0:
				continue
			var cl := _poly_closest(polys[i], polys[j])
			var g: float = cl[0]
			if g < 0.05 or g >= MIN_LOT_GAP:
				continue
			var pa: Vector2 = cl[1]
			var pb: Vector2 = cl[2]
			var u := (pb - pa).normalized()
			var t := Vector2(-u.y, u.x)
			var lo := -INF
			var hi := INF
			for poly: PackedVector2Array in [polys[i], polys[j]]:
				var mn := INF
				var mx := -INF
				for v in poly:
					var d := (v as Vector2).dot(t)
					mn = minf(mn, d)
					mx = maxf(mx, d)
				lo = maxf(lo, mn)
				hi = minf(hi, mx)
			var mid := (pa + pb) * 0.5
			if hi - lo < 0.6:      # corner to corner: a plug across the slit
				lo = mid.dot(t) - 0.3
				hi = mid.dot(t) + 0.3
			mid += t * ((lo + hi) * 0.5 - mid.dot(t))
			var body := StaticBody3D.new()
			body.name = "GapSeal"
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(g + 0.3, 6.0, hi - lo)
			shape.shape = box
			body.position = Vector3(mid.x, WorldGen.height(mid.x, mid.y) + 2.5, mid.y)
			body.rotation.y = atan2(t.x, t.y)
			body.add_child(shape)
			root.add_child(body, true)


## MultiMesh instances are render-only. Add cheap box proxies for the small set
## of placed props that should stop the player; foliage stays non-colliding.
## Breakable kinds get a Breakable body (group "breakable", duck-typed
## take_damage) that hides its own MultiMesh instance when smashed.
func _add_instance_colliders(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], mm: MultiMesh = null, breakable := "") -> void:
	var box := mesh.get_aabb()
	if box.size == Vector3.ZERO:
		return
	if mm and Breakable.is_breakable(breakable):
		for i in transforms.size():
			var b: StaticBody3D = Breakable.new()
			b.setup_instance(mm, i, transforms[i], mesh, breakable)
			parent.add_child(b)
		return
	for instance_transform in transforms:
		var scale := instance_transform.basis.get_scale()
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var collider := BoxShape3D.new()
		collider.size = Vector3(box.size.x * scale.x * 0.9, box.size.y * scale.y, box.size.z * scale.z * 0.9)
		shape.shape = collider
		body.transform = Transform3D(instance_transform.basis.orthonormalized(), instance_transform * box.get_center())
		body.add_child(shape)
		parent.add_child(body)


## Camera-only box proxies covering the FULL visual AABB (no shrink, unlike the
## 0.9x walk-collision boxes from _add_instance_colliders): keeps the chase
## camera out of stall awnings/canopies whose cloth extends past the footprint
## used for walking, without changing what the player can walk through. Layer
## CAMERA_BLOCKER_LAYER only; mask 0 (never collides with anything itself).
func _add_camera_blockers(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var box := mesh.get_aabb()
	if box.size == Vector3.ZERO:
		return
	for instance_transform in transforms:
		var scale := instance_transform.basis.get_scale()
		var body := StaticBody3D.new()
		body.collision_layer = CAMERA_BLOCKER_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var collider := BoxShape3D.new()
		collider.size = Vector3(box.size.x * scale.x, box.size.y * scale.y, box.size.z * scale.z)
		shape.shape = collider
		body.transform = Transform3D(instance_transform.basis.orthonormalized(), instance_transform * box.get_center())
		body.add_child(shape)
		parent.add_child(body)


static var _blob_mesh: PlaneMesh


## Contact-shadow quads are batched per settlement (one draw per cull class and
## 48 m cell instead of one per model kind: ~30 -> ~8 draws in a village) and
## written out by _flush_contact_shadows() at the end of _build().
var _blob_batch := {}     # Vector3i(cell x, cell z, cull) -> Array[Transform3D]


func _contact_shadows(_parent: Node3D, box: AABB, transforms: Array[Transform3D], cull: float) -> void:
	var centre := Vector3(box.get_center().x, 0.0, box.get_center().z)
	var size := Vector3(box.size.x * 1.35 + 0.6, 1.0, box.size.z * 1.35 + 0.6)
	# Big-range blobs (houses) can share one batch per town; small props stay in cells
	# so their short visibility range still works per neighbourhood.
	var cell := 48.0 if cull > 0.0 and cull < 300.0 else 100000.0
	for t: Transform3D in transforms:
		var b := t.basis * Basis.from_scale(size)
		var o := t * centre + Vector3(0, 0.04, 0)
		var k := Vector3i(floori(o.x / cell), floori(o.z / cell), int(cull))
		if not _blob_batch.has(k):
			_blob_batch[k] = []
		(_blob_batch[k] as Array).append(Transform3D(b, o))


func _flush_contact_shadows(parent: Node3D) -> void:
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/contact_shadow.gdshader")
		_blob_mesh.material = mat
	for k: Vector3i in _blob_batch:
		var list: Array = _blob_batch[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _blob_mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "ContactShadows"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k.z > 0:
			mmi.visibility_range_end = k.z * 0.8
		parent.add_child(mmi)
	_blob_batch.clear()


## Trees, saplings and bushes where people would leave or plant them: behind the
## houses, at lot corners, and thinning out through the village edge. Never on
## streets, paths, the plaza, or inside another building's footprint.
func _greenery(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["pos"]
	var r: float = s["radius"]
	var lots: Array = plan["lots"]
	var picks := {}
	var tries := 260 if s["kind"] == "village" else 420
	for i in tries:
		var ang := rng.randf() * TAU
		# Range widened from 2.3 to 3.4 so a tree (see the d < r*1.8 split below)
		# can still land past the settlement's flatten-to-natural slope instead
		# of only ever inside it.
		var d := r * sqrt(rng.randf_range(0.12, 3.4))
		var p := c + Vector2(cos(ang), sin(ang)) * d
		if d < plan["plaza_r"] + 6.0 or CityPlanner.street_distance(plan, p) < 3.0 \
				or CityPlanner.path_distance(plan, p) < 1.5 or WorldGen.road_distance(p.x, p.y) < 5.0 \
				or WorldGen.near_water(p.x, p.y, 2.0):
			continue
		var blocked := false
		for lot: Dictionary in lots:
			if p.distance_to(lot["pos"]) < 7.0:
				blocked = true
				break
		if blocked:
			continue
		# Denser near the edge, sparse inside; trees outside, bushes inside.
		var edge := smoothstep(r * 0.5, r * 1.3, d)
		if rng.randf() > 0.35 + edge * 0.5:
			continue
		var kind: String
		var roll := rng.randf()
		# height() blends this settlement's flat plateau into natural terrain out
		# to radius*1.8 (see height() in world_gen.gd). A wide-canopy tree's
		# footprint corners, sampled several metres from the trunk, could land on
		# that slope and read as floating by several metres (tools/qa/grounding's
		# single biggest bad category) even though the trunk itself was grounded
		# correctly -- so full-size trees are only picked past that point; the
		# small-footprint bushes below it are unaffected by the same slope.
		if d < r * 1.8:
			kind = ["region/nature/bush_round", "region/nature/bush_hazel", "region/nature/young_oak", "region/nature/beech_a"][mini(int(roll * 4.0), 3)]
		else:
			kind = ["region/nature/oak_a", "region/nature/oak_b", "region/nature/beech_a", "region/nature/young_oak", "region/nature/bush_round"][mini(int(roll * 5.0), 4)]
		var sc := rng.randf_range(0.8, 1.15)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.1, p.y))
		var gkey := "%s@%d,%d" % [kind, floori(p.x / LOD_CELL), floori(p.y / LOD_CELL)]   # per cell: see LOD_CELL
		if not picks.has(gkey):
			picks[gkey] = []
		picks[gkey].append(t)
	for gkey: String in picks:
		var kind := gkey.get_slice("@", 0)
		var list: Array[Transform3D] = []
		list.assign(picks[gkey])
		if kind.begins_with("region/") and ResourceLoader.exists("res://assets/generated/%s_lod2.glb" % kind):
			TerrainStreamer.region_tree_chain(root, kind, list)   # painterly trees with LOD1 + impostor
		else:
			_multimesh(root, Assets.nature_mesh(kind), list, false)


## Fenced crop fields outside the village: 10 m wheat tiles on the terrain,
## a rustic fence around each field with a gap for the farmer.
func _fields(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator, gates: Array[float]) -> void:
	var c: Vector2 = s["pos"]
	var r: float = s["radius"]
	var tiles: Array[Transform3D] = []
	var activity_spots: Array = plan.get("activity_spots", []).duplicate()
	var fences: Array[Transform3D] = []
	var stacks: Array[Transform3D] = []
	var placed: Array[Vector2] = []
	for i in (7 if s["kind"] == "village" else 10):
		var ang := rng.randf() * TAU
		if CityPlanner._near_angle(ang, gates, 0.35):
			continue
		var fc := c + Vector2(cos(ang), sin(ang)) * r * rng.randf_range(1.35, 1.9)
		var ok := not WorldGen.near_water(fc.x, fc.y, 20.0) and WorldGen.road_distance(fc.x, fc.y) > 22.0
		for q in placed:
			ok = ok and q.distance_to(fc) > 38.0
		if not ok:
			continue
		placed.append(fc)
		var nx := rng.randi_range(2, 3)
		var nz := rng.randi_range(2, 3)
		var yaw := ang + PI * 0.5
		var bx := Vector2(cos(yaw), -sin(yaw))
		var bz := Vector2(sin(yaw), cos(yaw))
		var field_index := placed.size() - 1
		for ix in nx:
			for iz in nz:
				var p := fc + bx * (ix - (nx - 1) * 0.5) * 10.0 + bz * (iz - (nz - 1) * 0.5) * 10.0
				# Fields sit well outside the settlement's flattened plateau (1.35-1.9x
				# its radius, see fc above), on real, often sloped terrain -- a flat 10 m
				# tile sampled only at its centre (the old code) could float or bury by
				# most of the local slope across its width. Corner-snap it like a
				# building lot instead.
				var tile_xform := Transform3D(Basis(Vector3.UP, yaw),
					Vector3(p.x, _ground_snap(p, yaw, Vector3(10.0, 1.0, 10.0), 0.05), p.y))
				tiles.append(tile_xform)
				activity_spots.append({"type": "field_row", "position": tile_xform.origin, "yaw": yaw,
					"identity": "farm/field/%d/tile/%d" % [field_index, ix * nz + iz]})
		# Fence around the field (3 m sections), leaving a gap on one side.
		var hx := nx * 5.0 + 1.0
		var hz := nz * 5.0 + 1.0
		for side in 4:
			var along := bx if side % 2 == 0 else bz
			var across := bz if side % 2 == 0 else bx
			var half_len := hx if side % 2 == 0 else hz
			var off := (hz if side % 2 == 0 else hx) * (1.0 if side < 2 else -1.0)
			var n := int(half_len * 2.0 / 3.0)
			for k in n:
				if side == 0 and k == n / 2:
					continue
				var p := fc + across * off + along * (-half_len + 1.5 + k * 3.0)
				var fyaw := yaw + (0.0 if side % 2 == 0 else PI * 0.5)
				fences.append(Transform3D(Basis(Vector3.UP, fyaw), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.05, p.y)))
		# A haystack at the field corner.
		var hp := fc + bx * (hx + 3.0) + bz * (hz - 2.0)
		var hy := rng.randf() * TAU
		stacks.append(Transform3D(Basis(Vector3.UP, hy), Vector3(hp.x, WorldGen.height(hp.x, hp.y), hp.y)))
		var hsize := _footprint("haystack")
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var hbox := BoxShape3D.new()
		hbox.size = Vector3(hsize.x * 0.85, hsize.y, hsize.z * 0.85)
		shape.shape = hbox
		body.position = stacks[-1].origin + Vector3(0, hsize.y * 0.5, 0)
		body.rotation.y = hy
		body.add_child(shape)
		root.add_child(body)
	plan["activity_spots"] = activity_spots
	# One batch instead of a node per haystack (5 surfaces each: 25 draws in view).
	_multimesh_cells(root, Assets.building_mesh("haystack"), stacks, 60.0, 0.0, false)
	_multimesh_cells(root, Assets.building_mesh("field_crops"), tiles, 60.0, 0.0, false)
	_multimesh_cells(root, Assets.building_mesh("fence"), fences, 60.0, 0.0, false)


## Behind and beside homes: vegetable gardens, woodpiles, washing lines.
func _homesteads(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var lots: Array = plan["lots"]
	var sets := {"garden_plot": [], "woodpile": [], "washing_line": []}
	for lot: Dictionary in lots:
		if not (String(lot["asset"]).begins_with("house") or String(lot["asset"]).begins_with("mhouse")):
			continue
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var p: Vector2 = lot["pos"]
		var roll := rng.randf()
		var kind := "garden_plot" if roll < 0.45 else ("woodpile" if roll < 0.75 else "washing_line")
		var at := p - fwd * 7.0 if kind == "garden_plot" else p + side * (5.2 if rng.randf() < 0.5 else -5.2) - fwd * 1.0
		if CityPlanner.street_distance(plan, at) < 3.0 or CityPlanner.path_distance(plan, at) < 1.5:
			continue
		var clear := true
		for other: Dictionary in lots:
			if other != lot and at.distance_to(other["pos"]) < 6.5:
				clear = false
				break
		if clear:
			var ky := yaw + (0.0 if kind == "garden_plot" else PI * 0.5)
			(sets[kind] as Array).append(Transform3D(Basis(Vector3.UP, ky), Vector3(at.x, WorldGen.height(at.x, at.y) - 0.03, at.y)))
	for kind: String in sets:
		var list: Array[Transform3D] = []
		list.assign(sets[kind])
		# Yard clutter per 80 m cell with a 120 m range (66 m on LOW): a capital has
		# ~200 of these, and as one town-wide batch they were all drawn from anywhere.
		_multimesh_cells(root, Assets.building_mesh(kind), list, 80.0, 120.0)
	_front_gardens(root, plan, rng)


## Outside every gate: the road lined with the small trade a town collects on its approach (a stall or
## two, crates, barrels, hay, a parked wagon), lamp posts and flower planters. Own RNG stream so the
## rest of the town's layout is unchanged; MultiMesh cells like everything else here.
func _gate_outskirts(root: Node3D, s: Dictionary, plan: Dictionary, gates: Array[float]) -> void:
	if gates.is_empty():
		return
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4242 + int(s["id"])
	var c: Vector2 = s["pos"]
	var wr: float = float(plan["wall_radius"]) if plan["walls"] else float(s["radius"]) * 1.1
	var lists := {}
	for ga: float in gates:
		var dir := Vector2(cos(ga), sin(ga))
		var side := Vector2(-dir.y, dir.x)
		var u := wr + 16.0
		var stalls := 0
		while u < wr + 78.0:
			var q := c + dir * u
			var half := float(WorldGen.road_info(q.x, q.y)["width"]) * 0.5
			for sg: float in [1.0, -1.0]:
				var base := q + side * sg * (half + 4.5)
				if WorldGen.is_water(base.x, base.y) or WorldGen.near_water(base.x, base.y, 2.0):
					continue
				var face := Vector2(-side.x * sg, -side.y * sg)
				var yaw := atan2(face.x, face.y)
				var roll := rng2.randf()
				var kind := ""
				var at := base
				if roll < 0.28 and stalls < 4:
					kind = "market_stall_red" if rng2.randf() < 0.5 else "market_stall_green"
					at = q + side * sg * (half + 6.2)
					stalls += 1
				elif roll < 0.5:
					kind = "crate_stack"
				elif roll < 0.62:
					kind = "barrel"
				elif roll < 0.76:
					kind = "hay"
				elif roll < 0.84 and u > wr + 30.0:
					kind = "covered_wagon"
					at = q + side * sg * (half + 8.0)
					yaw = atan2(dir.x, dir.y) + (0.0 if sg > 0.0 else PI) + rng2.randf_range(-0.3, 0.3)
				elif roll < 0.95:
					kind = "flower_planter"
				if kind == "":
					continue
				if not lists.has(kind):
					lists[kind] = []
				(lists[kind] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, WorldGen.height(at.x, at.y) - 0.03, at.y)))
			u += 7.0 + rng2.randf() * 5.0
		var lu := wr + 12.0
		while lu < wr + 80.0:
			var lq := c + dir * lu
			var lhalf := float(WorldGen.road_info(lq.x, lq.y)["width"]) * 0.5
			for sg2: float in [1.0, -1.0]:
				var lp := lq + side * sg2 * (lhalf + 1.6)
				if not lists.has("lamp_post"):
					lists["lamp_post"] = []
				(lists["lamp_post"] as Array).append(Transform3D(Basis(Vector3.UP, atan2(-side.x * sg2, -side.y * sg2)), Vector3(lp.x, WorldGen.height(lp.x, lp.y) - 0.03, lp.y)))
			lu += 26.0
	for kind: String in lists:
		var list: Array[Transform3D] = []
		list.assign(lists[kind])
		var solid := kind in ["market_stall_red", "market_stall_green", "covered_wagon", "crate_stack", "hay"]
		var mesh := Assets.building_mesh(kind)
		if solid:
			_multimesh(root, mesh, list, true, true)
		else:
			_multimesh_cells(root, mesh, list, LOD_CELL)


## Lamp posts around the square that glow at night, and a signpost where the road leaves.
func _square_lamps(root: Node3D, s: Dictionary, plan: Dictionary) -> void:
	var c: Vector2 = s["pos"]
	var pr: float = plan["plaza_r"]
	var n := 6 if s["kind"] == "village" else 10
	var posts: Array[Transform3D] = []
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p := c + Vector2(cos(a), sin(a)) * (pr + 1.2)
		var yaw := atan2(c.x - p.x, c.y - p.y)
		var gy := WorldGen.height(p.x, p.y) - 0.03
		posts.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, gy, p.y)))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.4)
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.add_to_group("street_lamp")
		root.add_child(light)
		light.global_position = Vector3(p.x, gy + 2.35, p.y) + Vector3(sin(yaw), 0, cos(yaw)) * 0.62
	_multimesh_cells(root, Assets.building_mesh("lamp_post"), posts, LOD_CELL)
	var gates: Array = plan["gates"]
	if not gates.is_empty():
		var ga: float = gates[0]
		var sp: Vector2 = c + Vector2(cos(ga), sin(ga)) * (float(s["radius"]) + 8.0) + Vector2(-sin(ga), cos(ga)) * 5.0
		_piece(root, "signpost", sp, WorldGen.height(sp.x, sp.y), ga)


## The gate road as in the Kingsreach reference: striped stalls packed with goods
## on both sides near the gate, tall lanterns, red-and-gold banner poles, bunting
## strung across the street and flowers along the edges, thinning toward the plaza.
## Every piece is one MultiMesh batch per settlement.
## Village squares in the same storybook dressing as the towns (smaller scale):
## bunting strung from the square's lamps to the well, crown banners at the
## entrances, flowers and a barrel or two at every house front.
func _village_square(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(Assets.GEN + "bunting.glb"):
		return
	var c: Vector2 = s["pos"]
	var pr: float = plan["plaza_r"]
	var batches := {}
	var add := func(key: String, p: Vector2, yaw: float, lift := 0.0, stretch := 1.0) -> void:
		if not batches.has(key):
			batches[key] = [] as Array[Transform3D]
		(batches[key] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(stretch, 1.0, 1.0)),
			Vector3(p.x, WorldGen.height(p.x, p.y) - 0.03 + lift, p.y)))
	# Bunting: spokes from the ring of square lamps toward the well, meeting overhead.
	var n := 6
	for i in n:
		var a := TAU * (i + 0.5) / n
		var mid := c + Vector2(cos(a), sin(a)) * (pr + 1.2) * 0.5
		add.call("bunting", mid, atan2(-sin(a), cos(a)), 3.6, (pr + 1.2) / 8.0)
	for g: float in plan["gates"]:
		var gd := Vector2(cos(g), sin(g))
		var gs := Vector2(-gd.y, gd.x)
		for sd: float in [-1.0, 1.0]:
			add.call("banner_pole", c + gd * (pr + 3.0) + gs * sd * 4.5, atan2(-gd.x, -gd.y))
	for lot: Dictionary in plan["lots"]:
		var asset := String(lot["asset"])
		if not BuildingProfiles.is_house(asset):
			continue
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(fwd.y, -fwd.x)
		var front: Vector2 = lot["pos"] + fwd * (BuildingProfiles.size_of(asset).z * 0.5 + 0.2)
		for sd: float in [-1.0, 1.0]:
			add.call("flower_strip", front + right * sd * 2.2, yaw + PI * 0.5)
		if rng.randf() < 0.35:
			add.call("barrel_cluster", front + right * 2.8 + fwd * 0.6, yaw + rng.randf_range(-0.5, 0.5))
	for key: String in batches:
		var mesh := Assets.building_mesh(key)
		if mesh != null:
			_multimesh_cells(root, mesh, batches[key], 40.0, 0.0, key != "bunting")
	_square_edge(root, s, plan, rng)


## Flowers, daisies and grass tufts along the ragged rim of a village's cobbled square (the paving
## itself is WorldGen.color_at(): channel B out to plaza_r + ~3.4 m), thickest where the cobbles
## give way to grass and thinning into the yard, never on the street spokes or footpaths.
func _square_edge(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["pos"]
	var pr: float = plan["plaza_r"]
	var sets := {"nature/flowers_a": [], "nature/grass_clump_tall": [], "region/nature/flowers_warm": [], "flower_strip": []}
	var want := 46 if _low() else 90
	var count := 0
	for i in want * 4:
		if count >= want:
			break
		var a := rng.randf() * TAU
		var d := pr + rng.randf_range(1.6, 7.0)
		var p := c + Vector2(cos(a), sin(a)) * d
		if CityPlanner.street_distance(plan, p) < 2.6 or CityPlanner.path_distance(plan, p) < 1.4:
			continue
		var blocked := false
		for lot: Dictionary in plan["lots"]:
			if p.distance_to(lot["pos"]) < 5.5:
				blocked = true
				break
		if blocked or WorldGen.near_water(p.x, p.y, 1.5):
			continue
		var here := WorldGen.color_at(p.x, p.y, 0.0, 0.0)
		var inner := p + (c - p).normalized() * 2.4
		if here.b > 0.85 or WorldGen.color_at(inner.x, inner.y, 0.0, 0.0).b < 0.4:
			continue       # only along the rim: cobbles inside, grass outside
		var roll := rng.randf()
		var kind := "nature/flowers_a" if roll < 0.4 else ("nature/grass_clump_tall" if roll < 0.7 else ("region/nature/flowers_warm" if roll < 0.9 else "flower_strip"))
		var sc := rng.randf_range(0.9, 1.5) if kind != "flower_strip" else 1.0
		var yaw := rng.randf() * TAU if kind != "flower_strip" else atan2(-(c - p).y, (c - p).x) + PI * 0.5
		(sets[kind] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.02, p.y)))
		count += 1
	for kind: String in sets:
		var list: Array[Transform3D] = []
		list.assign(sets[kind])
		var mesh: Mesh = Assets.building_mesh(kind) if kind == "flower_strip" else Assets.nature_mesh(kind)
		if mesh != null:
			_multimesh_cells(root, mesh, list, LOD_CELL, 90.0, false)


func _gate_market(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(Assets.GEN + "market_stall_red.glb"):
		return
	var c: Vector2 = s["pos"]
	var r: float = plan["wall_radius"]
	var pr: float = plan["plaza_r"]
	var batches := {}   # asset key -> Array[Transform3D]
	var lights: Array[Vector3] = []
	var add := func(key: String, p: Vector2, yaw: float, lift := 0.0, stretch := 1.0) -> void:
		if not batches.has(key):
			batches[key] = [] as Array[Transform3D]
		(batches[key] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(stretch, 1.0, 1.0)),
			Vector3(p.x, WorldGen.height(p.x, p.y) - 0.03 + lift, p.y)))
	# Solid props (stalls, barrel clusters) must leave every front door reachable: a 2 m wide
	# corridor from each door to the street and straight out from it, and >= 1.4 m between
	# one solid prop and the next. A prop is slid along the street to the nearest spot that
	# keeps both; if none exists it stays as scenery but stops colliding (no_collide).
	var corridors: Array = []     # [Vector2 from, Vector2 to]
	for pth: Dictionary in plan["paths"]:
		corridors.append([pth["a"], pth["b"]])
	for lot: Dictionary in plan["lots"]:
		var ly: float = lot["yaw"]
		var dp := BuildingProfiles.door_point(lot)
		corridors.append([dp, dp + Vector2(sin(ly), cos(ly)) * 10.0])
	var solid: Array = []         # [centre, yaw, half x, half z] of every solid prop placed so far
	var stall_spots: Array = []   # [key, position, yaw, index into solid or -1] of every market stall, for MarketGoods
	var no_collide := {}          # key -> Array[Transform3D] scenery that must not collide
	var placed_solid := func(key: String, p: Vector2, yaw: float, dir: Vector2) -> Vector2:
		var mesh := Assets.building_mesh(key)
		if mesh == null:
			return p
		var bx := mesh.get_aabb()
		var hx := bx.size.x * 0.45
		var hz := bx.size.z * 0.45
		var cen := Vector2(bx.get_center().x, bx.get_center().z)
		var near_cor: Array = corridors.filter(func(cor: Array) -> bool:
			return Geometry2D.get_closest_point_to_segment(p, cor[0], cor[1]).distance_to(p) < 12.0)
		var near_solid: Array = solid.filter(func(o: Array) -> bool: return (o[0] as Vector2).distance_to(p) < 14.0)
		for off: float in [0.0, 0.75, -0.75, 1.5, -1.5, 2.25, -2.25, 3.0, -3.0, 3.75, -3.75, 4.5, -4.5]:
			var q: Vector2 = p + dir * off
			var centre: Vector2 = q + cen.rotated(-yaw)
			var ok := true
			for cor: Array in near_cor:
				if _rect_segment_dist(centre, yaw, hx, hz, cor[0], cor[1]) < 1.0:
					ok = false
					break
			if ok:
				for o: Array in near_solid:
					if _rect_gap(centre, yaw, hx, hz, o[0], o[1], o[2], o[3]) < 1.4:
						ok = false
						break
			if ok:
				solid.append([centre, yaw, hx, hz])
				return q
		if not no_collide.has(key):
			no_collide[key] = [] as Array[Transform3D]
		return Vector2(INF, INF)   # caller adds it as scenery
	var add_scenery := func(key: String, p: Vector2, yaw: float) -> void:
		add.call(key, p, yaw)
		(no_collide[key] as Array).append((batches[key] as Array[Transform3D]).back())
	for st: Dictionary in plan["streets"]:
		if float(st["w"]) < 7.5:
			continue   # main streets only (plaza to gate)
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var half := float(st["w"]) * 0.5
		var start := 6.0
		var stop := minf(a.distance_to(b), r - pr) - 8.0   # stay inside the gate
		var t := start
		var k := 0
		while t < stop:
			var p := a + dir * t
			var near_gate := t > (stop - start) * 0.35
			for side: float in [-1.0, 1.0]:
				var edge := p + nrm * side * (half + 0.6)
				var face := atan2(-nrm.x * side, -nrm.y * side)   # toward the street centre
				if k % 3 == 0:
					add.call("street_lamp", edge, face)
					lights.append(Vector3(edge.x, WorldGen.height(edge.x, edge.y) + 3.4, edge.y))
				elif k % 3 == 1 and side > 0.0 or k % 3 == 2 and side < 0.0:
					add.call("banner_pole", edge, face)
				if near_gate and (k % 3 != 0 or rng.randf() < 0.5):
					var sp := p + nrm * side * (half + 1.7)
					var stall_key := "market_stall_red" if rng.randf() < 0.55 else "market_stall_green"
					var spx: Vector2 = placed_solid.call(stall_key, sp, face, dir)
					if is_inf(spx.x):
						add_scenery.call(stall_key, sp, face)
						stall_spots.append([stall_key, sp, face, -1])
					else:
						sp = spx
						add.call(stall_key, sp, face)
						stall_spots.append([stall_key, sp, face, solid.size() - 1])
					if rng.randf() < 0.6:
						var bp: Vector2 = sp + dir * 2.5 + nrm * side * 0.3
						var by := face + rng.randf_range(-0.4, 0.4)
						var bpx: Vector2 = placed_solid.call("barrel_cluster", bp, by, dir)
						if is_inf(bpx.x):
							add_scenery.call("barrel_cluster", bp, by)
						else:
							add.call("barrel_cluster", bpx, by)
				elif k % 2 == 0:
					add.call("flower_strip", p + nrm * side * (half + 1.4), face + PI * 0.5)
			if k % 4 == 1:
				add.call("bunting", p, atan2(nrm.x, nrm.y) + PI * 0.5, 4.2, (half * 2.0 + 1.2) / 8.0)
			t += 5.5
			k += 1
	# Flowers and a barrel or two at the foot of every townhouse front, either side of the door.
	for lot: Dictionary in plan["lots"]:
		if not String(lot["asset"]).begins_with("house_town"):
			continue
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var right := Vector2(fwd.y, -fwd.x)
		var front: Vector2 = lot["pos"] + fwd * 4.3
		for sd: float in [-1.0, 1.0]:
			add.call("flower_strip", front + right * sd * 2.4, yaw + PI * 0.5)
		if rng.randf() < 0.5:
			var tb: Vector2 = front + right * 3.0 + fwd * 0.8
			var ty := yaw + rng.randf_range(-0.5, 0.5)
			var tbx: Vector2 = placed_solid.call("barrel_cluster", tb, ty, right)
			if is_inf(tbx.x):
				add_scenery.call("barrel_cluster", tb, ty)
			else:
				add.call("barrel_cluster", tbx, ty)
	# Goods on and around every stall and at the townhouse shop fronts (MarketGoods): render-only.
	stalls_by_town[s["id"]] = stall_spots
	# Publish the final, clearance-adjusted placements as data so WorldSim's
	# SmartObjects index can send shoppers to the actual stalls, not guessed points.
	var activity_spots: Array = plan.get("activity_spots", []).duplicate()
	for i in stall_spots.size():
		var stall: Array = stall_spots[i]
		var p: Vector2 = stall[1]
		activity_spots.append({"type": "market_stall",
			"position": Vector3(p.x, WorldGen.height(p.x, p.y), p.y),
			"yaw": float(stall[2]), "identity": "market/street/%d" % i})
	plan["activity_spots"] = activity_spots
	_market_dressing(root, s, plan, stall_spots, solid, corridors)
	# A pair of town guards standing watch just inside every gate, as in the reference.
	if plan["walls"]:
		for g: float in plan["gates"]:
			var gd := Vector2(cos(g), sin(g))
			var gside := Vector2(-gd.y, gd.x)
			for sd: float in [-1.0, 1.0]:
				var gp: Vector2 = c + gd * (r - 7.0) + gside * sd * 4.2
				var guard := Assets.character("Guard", 1.8, [])
				if guard == null:
					continue
				root.add_child(guard)
				guard.global_position = Vector3(gp.x, WorldGen.height(gp.x, gp.y), gp.y)
				guard.rotation.y = atan2(-gd.x, -gd.y)   # facing into town, watching the street
				var ganim := Assets.animation_player(guard)
				if ganim:
					ganim.play("Idle" if ganim.has_animation("Idle") else ganim.get_animation_list()[0])
				DistanceCull.attach(guard, 80.0, ganim)
	# Red-and-gold banners hung along the inner face of the walls either side of each gate.
	var wall_mesh := Assets.building_mesh("wall")
	if plan["walls"] and wall_mesh != null:
		var wall_h := wall_mesh.get_aabb().size.y
		for g: float in plan["gates"]:
			for j in range(-6, 7):
				if absi(j) < 2:
					continue   # the gatehouse itself
				var ang := g + j * 7.5 / r
				var wp := c + Vector2(cos(ang), sin(ang)) * (r - 1.3)
				var inward := atan2(c.x - wp.x, c.y - wp.y)
				add.call("wall_banner", wp, inward, wall_h - 1.4)
				add.call("flower_strip", c + Vector2(cos(ang), sin(ang)) * (r - 2.2), inward + PI * 0.5)
	for key: String in batches:
		var mesh := Assets.building_mesh(key)
		if mesh != null:
			# Per-neighbourhood batches: a town-wide MultiMesh's AABB centre is the plaza,
			# so its visibility range would hide stalls standing right beside the player.
			_multimesh_cells(root, mesh, batches[key], 40.0, 0.0, key != "bunting")
			if key.begins_with("market_stall") or key == "barrel_cluster":
				var walk: Array[Transform3D] = []
				for tr: Transform3D in batches[key]:
					if not (no_collide.has(key) and (no_collide[key] as Array).has(tr)):
						walk.append(tr)
				_add_instance_colliders(root, mesh, walk)
				_add_camera_blockers(root, mesh, batches[key])
	for lp: Vector3 in lights.slice(0, 24):
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.4)
		light.omni_range = 8.0
		light.light_energy = 0.0
		light.add_to_group("street_lamp")
		root.add_child(light)
		light.global_position = lp


## Sparse painted decals (TownDecals): moss and dirt at wall feet, worn plaster patches, soot above the
## forge door and around chimneys on the house batches; cart ruts and puddles on the streets and square.
## Budget: one wall decal per 32 m block and at most TownDecals.CHUNK_CAP ground decals per 64 m terrain
## chunk keep every mesh under the Mobile renderer's 8 decals; each fades out at 30-40 m from the camera;
## none on LOW (and they hide if the tier drops to LOW, see Quality.changed).
func _decals(root: Node3D, s: Dictionary, plan: Dictionary) -> void:
	if _low() or not TownDecals.available():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4111 + int(s["id"])      # own stream: the town's other random layout is untouched
	var holder := Node3D.new()
	holder.name = "Decals"
	root.add_child(holder)
	var q: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Quality")
	if q != null and q.has_signal("changed"):
		q.changed.connect(func() -> void:
			if is_instance_valid(holder):
				holder.visible = q.tier != q.LOW)
	var blocks := {}        # Vector2i (32 m block) -> true: one wall decal per block
	var chunks := {}        # Vector2i (64 m terrain chunk) -> ground decals placed
	var lots: Array = plan["lots"]
	var order := range(lots.size())
	for i in range(order.size() - 1, 0, -1):     # shuffle: which lot of a block gets the decal varies
		var j := rng.randi() % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for li: int in order:
		var lot: Dictionary = lots[li]
		var asset := String(lot["asset"])
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var size := _footprint(asset)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var gh := _ground_snap(p, yaw, size)
		var smith := asset == "blacksmith"
		var block := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
		if blocks.has(block) and not smith:
			continue
		var roll := rng.randf()
		if not smith and roll > 0.78:
			continue                     # not every block: keep it sparse
		blocks[block] = true
		var wall := BuildingProfiles.HERO_WALL if BuildingProfiles.HERO.has(asset) else BuildingProfiles.HOUSE_WALL
		var door_x := BuildingProfiles.door_local(asset, size).x
		var kind := "moss"
		if smith:
			kind = "soot"
		elif roll < 0.22:
			kind = "moss"
		elif roll < 0.42:
			kind = "dirt"
		elif roll < 0.60:
			kind = "plaster"
		else:
			kind = "chimney" if not Assets.chimney_points(asset).is_empty() else "dirt"
		if kind == "chimney":
			var pts := Assets.chimney_points(asset)
			var pt: Vector3 = pts[rng.randi() % pts.size()]
			var w := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, gh, p.y)) * pt
			var d := TownDecals.make("soot", Vector3(3.0, 2.6, 3.0), TownDecals.WALL_LAYER, Color(1, 1, 1, 0.85))
			holder.add_child(d)
			d.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), w + Vector3(0, -0.5, 0))
			continue
		# Choose a wall: 0 front, 1 back, 2 left, 3 right (moss and dirt like the back and sides).
		var wall_i := 0 if (smith or kind == "plaster" and rng.randf() < 0.5) else (rng.randi() % 4)
		var n2 := fwd
		var half_len := size.x * wall
		var depth := size.z * wall
		match wall_i:
			1:
				n2 = -fwd
			2:
				n2 = -side
				half_len = size.z * wall
				depth = size.x * wall
			3:
				n2 = side
				half_len = size.z * wall
				depth = size.x * wall
		var lat_axis := Vector2(-n2.y, n2.x)     # along the wall
		var lat := 0.0
		var anchor := 0.0
		if smith:
			var porch: float = BuildingProfiles.HERO["blacksmith"]["porch"]
			depth = size.z * wall - porch          # the entrance wall sits `porch` behind the front
			lat = door_x
		elif wall_i == 0:
			var away := 2.4 if rng.randf() < 0.5 else -2.4
			lat = door_x + away
			if absf(lat) > half_len - 1.2:
				lat = door_x - away
				if absf(lat) > half_len - 1.2:
					continue
		else:
			lat = rng.randf_range(-1.0, 1.0) * maxf(half_len - 1.7, 0.0)
		anchor = depth
		var origin2 := p + n2 * anchor + lat_axis * lat
		var n3 := Vector3(n2.x, 0.0, n2.y)
		var dsize := Vector3(3.0, 1.4, 1.2)
		var cy := gh
		match kind:
			"moss":
				dsize = Vector3(rng.randf_range(2.6, 3.6), 1.4, 1.25)
				cy = gh + dsize.z * 0.5 - 0.15
			"dirt":
				dsize = Vector3(rng.randf_range(2.8, 3.6), 1.4, 1.0)
				cy = gh + dsize.z * 0.5 - 0.12
			"plaster":
				dsize = Vector3(rng.randf_range(1.8, 2.4), 1.4, rng.randf_range(1.5, 1.9))
				cy = gh + rng.randf_range(1.3, 2.2)
			"soot":
				dsize = Vector3(2.8, 1.4, 2.6)
				cy = gh + 2.2 + dsize.z * 0.5      # bottom edge at the door / forge opening's top
		var d := TownDecals.make(kind, dsize, TownDecals.WALL_LAYER)
		holder.add_child(d)
		d.global_transform = Transform3D(TownDecals.wall_basis(n3), Vector3(origin2.x, cy, origin2.y) + n3 * 0.35)
	# Ground decals: cart ruts along the streets, puddles on streets and the square.
	var c: Vector2 = s["pos"]
	var pr: float = plan["plaza_r"]
	var put_ground := func(kind: String, at: Vector2, yaw: float, dsize: Vector3, tint := Color.WHITE) -> void:
		var ck := Vector2i(floori(at.x / 64.0), floori(at.y / 64.0))
		if int(chunks.get(ck, 0)) >= TownDecals.CHUNK_CAP:
			return
		chunks[ck] = int(chunks.get(ck, 0)) + 1
		var d := TownDecals.make(kind, dsize, TownDecals.GROUND_LAYER, tint)
		holder.add_child(d)
		d.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y))
	var spans: Array = []       # [street a, dir, length, width]
	for st: Dictionary in plan["streets"]:
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var len := a.distance_to(b)
		if len < 20.0:
			continue
		spans.append([a, (b - a) / len, len, float(st["w"])])
		var dir := (b - a) / len
		var nrm := Vector2(-dir.y, dir.x)
		var t := pr + 5.0 + rng.randf_range(0.0, 6.0)
		while t < len - 8.0:
			if rng.randf() < 0.7:
				var at := a + dir * t + nrm * rng.randf_range(-0.9, 0.9)
				put_ground.call("ruts", at, atan2(dir.x, dir.y), Vector3(2.8, 2.0, rng.randf_range(9.0, 13.0)))
			t += rng.randf_range(12.0, 22.0)
	var n_pud := 6 if s["kind"] == "village" else 9
	for i in n_pud:
		var at: Vector2
		var ang := rng.randf() * TAU
		if spans.is_empty() or rng.randf() < 0.4:
			at = c + Vector2(cos(ang), sin(ang)) * rng.randf_range(pr * 0.35, pr * 0.95)      # on the square
		else:
			var sp: Array = spans[rng.randi() % spans.size()]
			var dir: Vector2 = sp[1]
			at = (sp[0] as Vector2) + dir * rng.randf_range(pr + 2.0, sp[2] - 8.0) + Vector2(-dir.y, dir.x) * rng.randf_range(-1.0, 1.0) * (float(sp[3]) * 0.5 - 1.2)
		put_ground.call("puddle", at, rng.randf() * TAU, Vector3(rng.randf_range(2.6, 4.2), 2.0, rng.randf_range(2.0, 3.0)), Color(1, 1, 1, 0.92))


## Extra market goods from the MarketGoods kit (CC0 Quaternius props + food, one shared atlas):
## every stall gets its themed counter goods and hanging goods, and -- when the space is free --
## crates, barrels and baskets in front of the counter and a crate/sack stack beside its posts;
## townhouse shop fronts get a small themed set beside the door. All render-only (no colliders),
## one MultiMesh per composed layout per 40 m cell, no shadow casting, culled at 70 m.
## Clearances mirror _gate_market(): >= 1 m from every door corridor centre line (2 m wide lanes)
## and >= 1.4 m from every solid prop / neighbouring house wall. LOW keeps the same stall dressing but
## drops the stacks behind the stalls and half the shop fronts (its visibility ranges are shorter too).
func _market_dressing(root: Node3D, s: Dictionary, plan: Dictionary, stall_spots: Array, solid: Array, corridors: Array) -> void:
	if not MarketGoods.available():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331 + int(s["id"])      # own stream: the rest of the town's random layout is untouched
	var low := _low()
	var batches := {}                   # layout id -> Array[Transform3D]
	var placed: Array = []              # rects of the extras placed here: [centre, yaw, hx, hz]
	var stats := {"stalls": 0, "front": 0, "side": 0, "rear": 0, "shops": 0}
	var put := func(id: String, origin: Vector2, yaw: float) -> void:
		if not batches.has(id):
			batches[id] = [] as Array[Transform3D]
		(batches[id] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, WorldGen.height(origin.x, origin.y) - 0.03, origin.y)))
	var clear_of := func(centre: Vector2, yaw: float, hx: float, hz: float, own: int) -> bool:
		for cor: Array in corridors:
			if Geometry2D.get_closest_point_to_segment(centre, cor[0], cor[1]).distance_to(centre) > 12.0:
				continue
			if _rect_segment_dist(centre, yaw, hx, hz, cor[0], cor[1]) < 1.0:
				return false
		for i in solid.size():
			if i == own:
				continue
			var o: Array = solid[i]
			if (o[0] as Vector2).distance_to(centre) > 14.0:
				continue
			if _rect_gap(centre, yaw, hx, hz, o[0], o[1], o[2], o[3]) < MIN_LOT_GAP:
				return false
		for o: Array in placed:
			if (o[0] as Vector2).distance_to(centre) < 8.0 and _rect_gap(centre, yaw, hx, hz, o[0], o[1], o[2], o[3]) < 1.0:
				return false
		return true
	var themes := MarketGoods.THEMES
	var offset := rng.randi() % themes.size()
	for n in stall_spots.size():
		var spot: Array = stall_spots[n]
		var sp: Vector2 = spot[1]
		var yaw: float = spot[2]
		var own: int = spot[3]
		var ex := Vector2(cos(yaw), -sin(yaw))
		var ez := Vector2(sin(yaw), cos(yaw))
		var theme: String = themes[(n * 5 + offset) % themes.size()]
		# Ground goods in front of the awning: only where nothing blocks a lane or a door.
		var front_c: Vector2 = sp + ez * (MarketGoods.FRONT_RECT.position.y + MarketGoods.FRONT_RECT.size.y * 0.5) \
			+ ex * (MarketGoods.FRONT_RECT.position.x + MarketGoods.FRONT_RECT.size.x * 0.5)
		var front_ok: bool = clear_of.call(front_c, yaw, MarketGoods.FRONT_RECT.size.x * 0.5, MarketGoods.FRONT_RECT.size.y * 0.5, own)
		put.call("stall_%s%s" % [theme, "" if front_ok else "_lite"], sp, yaw)
		stats["stalls"] += 1
		if front_ok:
			placed.append([front_c, yaw, MarketGoods.FRONT_RECT.size.x * 0.5, MarketGoods.FRONT_RECT.size.y * 0.5])
			stats["front"] += 1
		for side: float in [1.0, -1.0]:
			var sc: Vector2 = sp + ex * side * MarketGoods.SIDE_X + ez * 0.15
			if not clear_of.call(sc, yaw, MarketGoods.SIDE_HALF.x, MarketGoods.SIDE_HALF.y, own):
				continue
			if rng.randf() < 0.3:
				continue        # not every stall has a stack beside it
			placed.append([sc, yaw, MarketGoods.SIDE_HALF.x, MarketGoods.SIDE_HALF.y])
			put.call("side_a" if rng.randf() < 0.5 else "side_b", sc, yaw + (0.0 if side > 0.0 else PI))
			stats["side"] += 1
		# ... and one stack behind the stall (stacks are 2 m long, so turned a quarter to run along the back).
		var rc: Vector2 = sp - ez * 1.85 + ex * rng.randf_range(-0.9, 0.9)
		if not low and rng.randf() < 0.7 and clear_of.call(rc, yaw + PI * 0.5, MarketGoods.SIDE_HALF.x, 1.05, own):
			placed.append([rc, yaw + PI * 0.5, MarketGoods.SIDE_HALF.x, 1.05])
			put.call("side_a" if rng.randf() < 0.5 else "side_b", rc, yaw + PI * 0.5)
			stats["rear"] += 1
	# Townhouse shop fronts: a small themed set beside the door (never on the door line).
	var polys: Array = []
	for lot: Dictionary in plan["lots"]:
		var lsz := _footprint(lot["asset"])
		var wall := BuildingProfiles.HOUSE_WALL if BuildingProfiles.is_house(lot["asset"]) else BuildingProfiles.HERO_WALL
		polys.append([lot["pos"], _rect_poly(lot["pos"], lot["yaw"], lsz.x * wall, lsz.z * wall)])
	for li in plan["lots"].size():
		var lot: Dictionary = plan["lots"][li]
		if not String(lot["asset"]).begins_with("house_town"):
			continue
		if rng.randf() < (0.6 if low else 0.25):
			continue        # LOW: about half as many shop fronts
		var lyaw: float = lot["yaw"]
		var lfwd := Vector2(sin(lyaw), cos(lyaw))
		var lside := Vector2(lfwd.y, -lfwd.x)
		var lsize := _footprint(lot["asset"])
		var wall_z := lsize.z * BuildingProfiles.HOUSE_WALL
		var first := 1.0 if rng.randf() < 0.5 else -1.0
		for tries in 2:
			var sgn := first if tries == 0 else -first
			var c: Vector2 = lot["pos"] + lfwd * (wall_z + MarketGoods.SHOP_Z) + lside * sgn * MarketGoods.SHOP_X
			if CityPlanner.street_distance(plan, c) < 0.3:
				continue
			var ok: bool = clear_of.call(c, lyaw, MarketGoods.SHOP_HALF.x, MarketGoods.SHOP_HALF.y, -1)
			if ok:
				var poly := _rect_poly(c, lyaw, MarketGoods.SHOP_HALF.x, MarketGoods.SHOP_HALF.y)
				for k in polys.size():
					if k == li or (polys[k][0] as Vector2).distance_to(c) > 20.0:
						continue
					if float(_poly_closest(poly, polys[k][1])[0]) < MIN_LOT_GAP:
						ok = false
						break
			if not ok:
				continue
			placed.append([c, lyaw, MarketGoods.SHOP_HALF.x, MarketGoods.SHOP_HALF.y])
			put.call(MarketGoods.SHOPS[rng.randi() % MarketGoods.SHOPS.size()], c, lyaw)
			stats["shops"] += 1
			break
	for id: String in batches:
		var mesh := MarketGoods.layout(id)
		if mesh == null:
			continue
		var list: Array[Transform3D] = []
		list.assign(batches[id])
		# Per-neighbourhood batches (as for the stalls), no blob shadow, no shadow casting.
		_multimesh_cells(root, mesh, list, LOD_CELL, 70.0, false, false)
	if OS.get_cmdline_user_args().has("--goods-stats"):
		print("[goods] %s: %s" % [s["name"], stats])


## A couple of small stones or weeds tucked against each building's base (the
## dirt ring from WorldGen.color_at() gives the ground colour; this adds a little
## 3D relief so the wall doesn't meet flat grass in a hard line). Cheap: 2 pieces
## per lot, one shared MultiMesh batch per kind per settlement.
func _footprint_clutter(root: Node3D, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var kinds := {"region/nature/rock_medium": [], "region/nature/flowers_warm": [], "region/nature/fern_b": []}
	for lot: Dictionary in plan["lots"]:
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var p: Vector2 = lot["pos"]
		var size := _footprint(lot["asset"])
		var hug := maxf(size.x, size.z) * 0.5 + rng.randf_range(0.15, 0.5)
		for k in 2:
			var corner_side := side if k == 0 else -side
			var along := rng.randf_range(-0.6, 0.6) * size.z * 0.5
			var at := p + corner_side * hug + fwd * along
			if CityPlanner.path_distance(plan, at) < 0.6 or CityPlanner.street_distance(plan, at) < 0.8:
				continue
			var kind: String = ["region/nature/rock_medium", "region/nature/flowers_warm", "region/nature/fern_b"][rng.randi() % 3]
			(kinds[kind] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)),
				Vector3(at.x, WorldGen.height(at.x, at.y) - 0.03, at.y)))
	for kind: String in kinds:
		var list: Array[Transform3D] = []
		list.assign(kinds[kind])
		_multimesh_cells(root, Assets.nature_mesh(kind), list, 80.0, 90.0)


## Flowers and bushes hugging house fronts and corners, as in the reference art:
## clumps either side of the door (never on the footpath), a bush at a corner.
func _front_gardens(root: Node3D, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var sets := {"nature/flowers_a": [], "region/nature/bush_round": [], "nature/grass_clump_tall": []}
	var planters: Array[Transform3D] = []
	for lot: Dictionary in plan["lots"]:
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var p: Vector2 = lot["pos"]
		for k in rng.randi_range(3, 6):
			var sgn := 1.0 if k % 2 == 0 else -1.0
			var at := p + fwd * rng.randf_range(3.9, 4.6) + side * sgn * rng.randf_range(1.4, 3.6)
			if CityPlanner.path_distance(plan, at) < 0.6 or CityPlanner.street_distance(plan, at) < 0.8:
				continue
			var kind := "nature/flowers_a" if rng.randf() < 0.7 else "nature/grass_clump_tall"
			var sc := rng.randf_range(0.9, 1.5)
			(sets[kind] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc),
				Vector3(at.x, WorldGen.height(at.x, at.y) - 0.02, at.y)))
		if rng.randf() < 0.4:
			var pl := p + fwd * 3.9 + side * (1.6 if rng.randf() < 0.5 else -1.6)
			if CityPlanner.path_distance(plan, pl) > 0.8:
				planters.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pl.x, WorldGen.height(pl.x, pl.y), pl.y)))
		if rng.randf() < 0.7:
			var corner := p + fwd * 3.4 + side * (4.2 if rng.randf() < 0.5 else -4.2)
			if CityPlanner.street_distance(plan, corner) > 1.2:
				(sets["region/nature/bush_round"] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.0)),
					Vector3(corner.x, WorldGen.height(corner.x, corner.y) - 0.05, corner.y)))
	for kind: String in sets:
		var list: Array[Transform3D] = []
		list.assign(sets[kind])
		_multimesh(root, Assets.nature_mesh(kind), list, false)
	_multimesh_cells(root, Assets.building_mesh("planter_box"), planters, LOD_CELL)


## Thin wood smoke from some chimneys (read from the models' chimney_top markers).
## A few particles each, culled with distance; not every house has its fire lit.
func _chimney_smoke(root: Node3D, asset: String, transforms: Array[Transform3D], rng: RandomNumberGenerator) -> void:
	var points := Assets.chimney_points(asset)
	if points.is_empty():
		return
	for t in transforms:
		if rng.randf() > 0.55:
			continue
		for pt in points:
			root.add_child(_smoke_emitter(t * pt))


static var _smoke_mat: ParticleProcessMaterial
static var _smoke_mesh: QuadMesh


static func _smoke_emitter(at: Vector3) -> GPUParticles3D:
	if _smoke_mat == null:
		_smoke_mat = ParticleProcessMaterial.new()
		_smoke_mat.direction = Vector3(0.25, 1, 0.1)
		_smoke_mat.spread = 12.0
		_smoke_mat.initial_velocity_min = 0.35
		_smoke_mat.initial_velocity_max = 0.6
		_smoke_mat.gravity = Vector3(0.18, 0.12, 0.05)
		_smoke_mat.scale_min = 0.6
		_smoke_mat.scale_max = 1.0
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 2.6))
		var sct := CurveTexture.new()
		sct.curve = sc
		_smoke_mat.scale_curve = sct
		var g := Gradient.new()
		g.set_color(0, Color(0.8, 0.78, 0.75, 0.0))
		g.add_point(0.15, Color(0.75, 0.73, 0.7, 0.35))
		g.set_color(g.get_point_count() - 1, Color(0.85, 0.85, 0.85, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		_smoke_mat.color_ramp = gt
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(1.8, 1.8)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.8)))
		m.albedo_texture = ImageTexture.create_from_image(img)
		_smoke_mesh.material = m
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 7.0
	p.preprocess = 6.0
	p.process_material = _smoke_mat
	p.draw_pass_1 = _smoke_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 140.0
	p.visibility_aabb = AABB(Vector3(-4, 0, -4), Vector3(8, 10, 8))
	p.position = at
	return p
