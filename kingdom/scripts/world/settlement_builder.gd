class_name SettlementBuilder
extends Node3D
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
		_multimesh(root, Assets.building_mesh(asset), list)

	# Lived-in door_clutter by the doors: photo-scanned crates, barrels, baskets, buckets.
	var door_clutter := {}
	var kinds := ["scan/wooden_crate_01", "scan/wooden_barrels_01", "scan/wicker_basket_01", "scan/wooden_bucket_01"]
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
	var fields: Array[Transform3D] = []
	for i in 14:
		var ang := rng.randf() * TAU
		if CityPlanner._near_angle(ang, gates, 0.25):
			continue
		var p := c + Vector2(cos(ang), sin(ang)) * r * rng.randf_range(1.15, 1.7)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 9.0), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.05, p.y))
		fields.append(t)
	_multimesh(root, Assets.mesh_of("building_grain"), fields)
	# Street clutter.
	var street_clutter: Array[Transform3D] = []
	for i in 30:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(plan["plaza_r"] * 0.6, plan["plaza_r"] + 3.0)
		street_clutter.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, base_h, p.y)))
	_multimesh(root, Assets.nature_mesh("scan/wooden_barrels_01"), street_clutter.slice(0, 10))
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
	_multimesh(root, wall_mesh, walls)
	_multimesh(root, gate_mesh if gate_mesh else wall_mesh, gate_walls)
	_multimesh(root, tower_mesh, towers)


func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
