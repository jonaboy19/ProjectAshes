class_name SettlementBuilder
extends Node3D

## Distance where Meshy hero buildings swap to their light LOD.
const HERO_LOD := 70.0
## Buildings and greenery are batched per model per LOD_CELL x LOD_CELL metres.
const LOD_CELL := 40.0
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

signal settlement_built(settlement: Dictionary, root: Node3D)

var focus := Vector3.ZERO
var _built: Dictionary = {}      # id -> Node3D
var _timer := 0.0
var _footprints: Dictionary = {} # asset -> Vector3 size at BUILDING_SCALE


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
	var base_h: float = s["base_h"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + s["id"]

	# Houses and shops, batched by model and LOD_CELL: a MultiMesh switches LOD as a
	# whole (by its bounds' centre), so one town-wide batch drew every house at the
	# near LOD; per-cell batches let the far side of town use LOD2/LOD3.
	var batches := {}
	for lot in plan["lots"]:
		var p: Vector2 = lot["pos"]
		var asset: String = lot["asset"]
		# (Only models with a LOD chain gain from cells; the rest stay one batch per town.)
		# (Meshy only: the Blender houses have 4-6 materials each, so per-cell batches
		# of them cost more draw calls than their triangles save.)
		var celled := Assets.building_lod_level_distance(asset, 3) > 0.0
		var bkey := "%s@%d,%d" % [asset, floori(p.x / LOD_CELL), floori(p.y / LOD_CELL)] if celled else asset + "@"
		if not batches.has(bkey):
			batches[bkey] = []
		var t := Transform3D(Basis(Vector3.UP, lot["yaw"]), Vector3(p.x, base_h, p.y))
		batches[bkey].append(t)
		var size := _footprint(asset)
		var body := BuildingProfiles.make_body(asset, size)
		body.position = Vector3(p.x, base_h, p.y)
		body.rotation.y = lot["yaw"]
		root.add_child(body)
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
				mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				mm.visibility_range_begin = chain[i][1]
				mm.visibility_range_begin_margin = 10.0 if i > 0 else 0.0
				mm.visibility_range_end = chain[i + 1][1] if i + 1 < chain.size() else 0.0
				mm.visibility_range_end_margin = 10.0 if i + 1 < chain.size() else 0.0
		else:
			_multimesh(root, Assets.building_mesh(asset), list)
		_chimney_smoke(root, asset, list, rng)

	_interior_doors(root, plan["lots"], base_h)

	# Lived-in door_clutter by the doors: photo-scanned crates, barrels, baskets, buckets.
	var door_clutter := {}
	var kinds := ["scan/wooden_crate_01", "scan/wicker_basket_01", "scan/wooden_bucket_01"]
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
			door_clutter[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, base_h, q.y)))
	for kind: String in door_clutter:
		var list2: Array[Transform3D] = []
		list2.assign(door_clutter[kind])
		_multimesh(root, Assets.nature_mesh(kind), list2)

	for lm in plan["landmarks"]:
		_piece(root, lm["asset"], lm["pos"], base_h, lm["yaw"])
	# Market stalls and carts ringing the plaza.
	var stalls: Array[Transform3D] = []
	var stalls2: Array[Transform3D] = []
	var pr: float = plan["plaza_r"]
	var n_stalls := 6 if s["kind"] == "village" else 12
	for i in n_stalls:
		var ang := TAU * i / n_stalls + 0.2
		var sp: Vector2 = s["pos"] + Vector2(cos(ang), sin(ang)) * (pr - 3.0)
		var st := Transform3D(Basis(Vector3.UP, atan2(-cos(ang), -sin(ang))), Vector3(sp.x, base_h, sp.y))
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
	_multimesh(root, Assets.building_mesh("market_stand_1"), st_a.slice(0, (st_a.size() + 1) / 2), true, true)
	_multimesh(root, Assets.building_mesh("market_stand_3"), st_a.slice((st_a.size() + 1) / 2), true, true)
	_multimesh(root, Assets.building_mesh("market_stand_2"), st_b.slice(0, (st_b.size() + 1) / 2), true, true)
	_multimesh(root, Assets.building_mesh("market_stand_4"), st_b.slice((st_b.size() + 1) / 2), true, true)

	var c: Vector2 = s["pos"]
	if plan["walls"]:
		_wall_ring(root, c, plan["wall_radius"], base_h, plan["gates"], 40, 5)
	if plan["inner_wall"] > 0.0:
		_wall_ring(root, c, plan["inner_wall"], base_h, [plan["gates"][0]], 16, 4)

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
	_footprint_clutter(root, plan, rng)
	_square_lamps(root, s, plan)
	_greenery(root, s, plan, rng)
	# Street clutter.
	var street_clutter: Array[Transform3D] = []
	for i in 30:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(plan["plaza_r"] * 0.6, plan["plaza_r"] + 3.0)
		street_clutter.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, base_h, p.y)))
	# Barrels, crates and baskets break when struck (see breakable.gd); carts stay solid.
	_multimesh(root, Assets.building_mesh("barrel"), street_clutter.slice(0, 10), true, true, "barrel")
	_multimesh(root, Assets.nature_mesh("scan/wooden_crate_01"), street_clutter.slice(10, 18), true, true, "scan/wooden_crate_01")
	_multimesh(root, Assets.nature_mesh("scan/wicker_basket_01"), street_clutter.slice(18, 24), true, true, "scan/wicker_basket_01")
	_multimesh(root, Assets.building_mesh("cart"), street_clutter.slice(24), true, true)
	_flush_contact_shadows(root)
	return root


## One InteriorDoor per enterable lot (inn, smithy, guild, healer, every house),
## on the ground at its front door, local +Z out into the street. They are idle
## triggers: masked to the player's trigger layer only, not monitorable, and
## with no per-frame work until the player stands in one (see interior_door.gd).
## Kept under "Doors" so VillageServices can find them.
func _interior_doors(root: Node3D, lots: Array, base_h: float) -> void:
	var holder := Node3D.new()
	holder.name = "Doors"
	root.add_child(holder)
	for lot: Dictionary in lots:
		var asset: String = lot["asset"]
		if not BuildingProfiles.is_enterable(asset):
			continue
		var p: Vector2 = lot["pos"]
		var yaw: float = lot["yaw"]
		var local := BuildingProfiles.door_local(asset, _footprint(asset))
		var at := BuildingProfiles.door_point(lot, _footprint(asset))
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
		door.position = Vector3(at.x, base_h + local.y, at.y)
		door.rotation.y = yaw
		holder.add_child(door)


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
func _wall_ring(root: Node3D, c: Vector2, radius: float, h: float, gates: Array, segments: int, tower_every: int) -> void:
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
	var tower_s := s * 1.05
	var walls: Array[Transform3D] = []
	var gate_walls: Array[Transform3D] = []
	var towers: Array[Transform3D] = []
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var mid := (a0 + a1) * 0.5
		var p0 := c + Vector2(cos(a0), sin(a0)) * radius
		var p1 := c + Vector2(cos(a1), sin(a1)) * radius
		var dir := p1 - p0
		var yaw := atan2(dir.x, dir.y) + (PI * 0.5 if along_x else 0.0)
		var mp := (p0 + p1) * 0.5
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(mp.x, h, mp.y))
		var is_gate := false
		for g in gates:
			if absf(wrapf(mid - g, -PI, PI)) < PI / segments:
				is_gate = true
		(gate_walls if is_gate else walls).append(t)
		if not is_gate:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.8, native.size.y * s, seg_len)
			shape.shape = box
			body.position = Vector3(mp.x, h + native.size.y * s * 0.5, mp.y)
			body.rotation.y = atan2(dir.x, dir.y)
			body.add_child(shape)
			root.add_child(body)
		if i % tower_every == 0 and not is_gate:
			towers.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * tower_s), Vector3(p0.x, h, p0.y)))
	# Per 150 m stretch of wall, so the automatic mesh LODs pick the far side's
	# distance instead of the whole ring's (a capital ring is ~160 pieces, 0.4 M tris).
	_multimesh_cells(root, wall_mesh, walls, 150.0, 0.0, false)
	_multimesh(root, gate_mesh if gate_mesh else wall_mesh, gate_walls, false)
	_multimesh_cells(root, tower_mesh, towers, 150.0, 0.0, false)


## Instanced placement. Culls by object size (small clutter vanishes first) and,
## unless blob is false, grounds each instance with a soft contact shadow.
## A `breakable` kind (Breakable.KINDS) makes each instance collider breakable.
func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], blob := true, collide := false, breakable := "") -> MultiMeshInstance3D:
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
func _multimesh_cells(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], cell: float, cull := 0.0, blob := true) -> void:
	var groups := {}
	for t: Transform3D in transforms:
		var k := Vector2i(floori(t.origin.x / cell), floori(t.origin.z / cell))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(t)
	for k: Vector2i in groups:
		var list: Array[Transform3D] = []
		list.assign(groups[k])
		var mmi := _multimesh(parent, mesh, list, blob)
		if mmi and cull > 0.0:
			mmi.visibility_range_end = cull
			mmi.visibility_range_end_margin = cull * 0.1


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
		var d := r * sqrt(rng.randf_range(0.12, 2.3))
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
		if d < r * 0.9:
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
		for ix in nx:
			for iz in nz:
				var p := fc + bx * (ix - (nx - 1) * 0.5) * 10.0 + bz * (iz - (nz - 1) * 0.5) * 10.0
				tiles.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.05, p.y)))
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
	# One batch instead of a node per haystack (5 surfaces each: 25 draws in view).
	_multimesh(root, Assets.building_mesh("haystack"), stacks, false)
	_multimesh(root, Assets.building_mesh("field_crops"), tiles, false)
	_multimesh(root, Assets.building_mesh("fence"), fences, false)


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
		posts.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, s["base_h"], p.y)))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.4)
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.add_to_group("street_lamp")
		root.add_child(light)
		light.global_position = Vector3(p.x, s["base_h"] + 2.35, p.y) + Vector3(sin(yaw), 0, cos(yaw)) * 0.62
	_multimesh(root, Assets.building_mesh("lamp_post"), posts)
	var gates: Array = plan["gates"]
	if not gates.is_empty():
		var ga: float = gates[0]
		var sp: Vector2 = c + Vector2(cos(ga), sin(ga)) * (float(s["radius"]) + 8.0) + Vector2(-sin(ga), cos(ga)) * 5.0
		_piece(root, "signpost", sp, WorldGen.height(sp.x, sp.y), ga)


## A couple of small stones or weeds tucked against each building's base (the
## dirt ring from WorldGen.color_at() gives the ground colour; this adds a little
## 3D relief so the wall doesn't meet flat grass in a hard line). Cheap: 2 pieces
## per lot, one shared MultiMesh batch per kind per settlement.
func _footprint_clutter(root: Node3D, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var kinds := {"scan/rock_moss_set_01_2": [], "scan/dandelion_01": [], "scan/fern_02": []}
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
			var kind: String = ["scan/rock_moss_set_01_2", "scan/dandelion_01", "scan/fern_02"][rng.randi() % 3]
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
	_multimesh(root, Assets.building_mesh("planter_box"), planters)


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
