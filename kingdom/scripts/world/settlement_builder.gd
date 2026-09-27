class_name SettlementBuilder
extends Node3D

## Distance where Meshy hero buildings swap to their light LOD.
const HERO_LOD := 70.0
## Builds settlements from their CityPlanner layout when the focus comes within
## BUILD_RANGE and frees them past FREE_RANGE. Buildings of the same model are
## drawn as one MultiMesh (a capital has ~300 buildings but only ~15 draw
## calls); each lot still gets a simple box collider so streets feel solid.

const BUILD_RANGE := 650.0
const FREE_RANGE := 850.0

signal settlement_built(settlement: Dictionary, root: Node3D)

var focus := Vector3.ZERO
var _built: Dictionary = {}      # id -> Node3D
var _timer := 0.0
var _footprints: Dictionary = {} # asset -> Vector3 size at BUILDING_SCALE


func _process(delta: float) -> void:
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

	# Houses and shops, batched by model.
	var batches := {}
	for lot in plan["lots"]:
		var asset: String = lot["asset"]
		if not batches.has(asset):
			batches[asset] = []
		var p: Vector2 = lot["pos"]
		var t := Transform3D(Basis(Vector3.UP, lot["yaw"]), Vector3(p.x, base_h, p.y))
		batches[asset].append(t)
		var size := _footprint(asset)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x * 0.8, size.y, size.z * 0.8)
		shape.shape = box
		body.position = Vector3(p.x, base_h + size.y * 0.5, p.y)
		body.rotation.y = lot["yaw"]
		body.add_child(shape)
		root.add_child(body)
	for asset: String in batches:
		var list: Array[Transform3D] = []
		list.assign(batches[asset])
		var lod := Assets.building_lod_mesh(asset)
		if lod:
			# Detailed hero model up close, its light version beyond HERO_LOD metres.
			var near_mm := _multimesh(root, Assets.building_mesh(asset), list)
			var far_mm := _multimesh(root, lod, list, false)
			near_mm.visibility_range_end = HERO_LOD
			near_mm.visibility_range_end_margin = 10.0
			near_mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			far_mm.visibility_range_begin = HERO_LOD
			far_mm.visibility_range_begin_margin = 10.0
			far_mm.visibility_range_end = 0.0
			far_mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			_multimesh(root, Assets.building_mesh(asset), list)

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
	_multimesh(root, Assets.building_mesh("market_stand_1"), stalls)
	_multimesh(root, Assets.building_mesh("market_stand_2"), stalls2)

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
	_square_lamps(root, s, plan)
	_greenery(root, s, plan, rng)
	# Street clutter.
	var street_clutter: Array[Transform3D] = []
	for i in 30:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(plan["plaza_r"] * 0.6, plan["plaza_r"] + 3.0)
		street_clutter.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, base_h, p.y)))
	_multimesh(root, Assets.building_mesh("barrel"), street_clutter.slice(0, 10))
	_multimesh(root, Assets.nature_mesh("scan/wooden_crate_01"), street_clutter.slice(10, 18))
	_multimesh(root, Assets.nature_mesh("scan/wicker_basket_01"), street_clutter.slice(18, 24))
	_multimesh(root, Assets.building_mesh("cart"), street_clutter.slice(24))
	return root


func _footprint(asset: String) -> Vector3:
	if not _footprints.has(asset):
		var mesh := Assets.building_mesh(asset)
		_footprints[asset] = mesh.get_aabb().size if mesh else Vector3(8, 8, 8)
	return _footprints[asset]


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
	_multimesh(root, wall_mesh, walls, false)
	_multimesh(root, gate_mesh if gate_mesh else wall_mesh, gate_walls, false)
	_multimesh(root, tower_mesh, towers, false)


## Instanced placement. Culls by object size (small clutter vanishes first) and,
## unless blob is false, grounds each instance with a soft contact shadow.
func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], blob := true) -> MultiMeshInstance3D:
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
	if blob and extent < 18.0:
		_contact_shadows(parent, box, transforms, cull)
	return mmi


static var _blob_mesh: PlaneMesh


func _contact_shadows(parent: Node3D, box: AABB, transforms: Array[Transform3D], cull: float) -> void:
	if _blob_mesh == null:
		_blob_mesh = PlaneMesh.new()
		_blob_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/contact_shadow.gdshader")
		_blob_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blob_mesh
	mm.instance_count = transforms.size()
	var centre := Vector3(box.get_center().x, 0.0, box.get_center().z)
	var size := Vector3(box.size.x * 1.35 + 0.6, 1.0, box.size.z * 1.35 + 0.6)
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		var b := t.basis * Basis.from_scale(size)
		mm.set_instance_transform(i, Transform3D(b, t * centre + Vector3(0, 0.04, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cull > 0.0:
		mmi.visibility_range_end = cull * 0.8
	parent.add_child(mmi)


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
			kind = ["nature/bush_a", "nature/bush_b", "nature/sapling", "nature/birch_a"][mini(int(roll * 4.0), 3)]
		else:
			kind = ["nature/oak_a", "nature/oak_b", "nature/birch_a", "nature/sapling", "nature/bush_a"][mini(int(roll * 5.0), 4)]
		var sc := rng.randf_range(0.8, 1.15)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.1, p.y))
		if not picks.has(kind):
			picks[kind] = []
		picks[kind].append(t)
	for kind: String in picks:
		var list: Array[Transform3D] = []
		list.assign(picks[kind])
		_multimesh(root, Assets.nature_mesh(kind), list, false)


## Fenced crop fields outside the village: 10 m wheat tiles on the terrain,
## a rustic fence around each field with a gap for the farmer.
func _fields(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator, gates: Array[float]) -> void:
	var c: Vector2 = s["pos"]
	var r: float = s["radius"]
	var tiles: Array[Transform3D] = []
	var fences: Array[Transform3D] = []
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
		_piece(root, "haystack", hp, WorldGen.height(hp.x, hp.y), rng.randf() * TAU)
	_multimesh(root, Assets.building_mesh("field_crops"), tiles, false)
	_multimesh(root, Assets.building_mesh("fence"), fences, false)


## Behind and beside homes: vegetable gardens, woodpiles, washing lines.
func _homesteads(root: Node3D, s: Dictionary, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var lots: Array = plan["lots"]
	var sets := {"garden_plot": [], "woodpile": [], "washing_line": []}
	for lot: Dictionary in lots:
		if not String(lot["asset"]).begins_with("house"):
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
		_multimesh(root, Assets.building_mesh(kind), list)
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


## Flowers and bushes hugging house fronts and corners, as in the reference art:
## clumps either side of the door (never on the footpath), a bush at a corner.
func _front_gardens(root: Node3D, plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var sets := {"nature/flowers_a": [], "nature/bush_b": [], "nature/grass_clump_tall": []}
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
		if rng.randf() < 0.7:
			var corner := p + fwd * 3.4 + side * (4.2 if rng.randf() < 0.5 else -4.2)
			if CityPlanner.street_distance(plan, corner) > 1.2:
				(sets["nature/bush_b"] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.0)),
					Vector3(corner.x, WorldGen.height(corner.x, corner.y) - 0.05, corner.y)))
	for kind: String in sets:
		var list: Array[Transform3D] = []
		list.assign(sets[kind])
		_multimesh(root, Assets.nature_mesh(kind), list, false)
