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
		var t := Transform3D(Basis(Vector3.UP, lot["yaw"]).scaled(Vector3.ONE * Assets.BUILDING_SCALE), Vector3(p.x, base_h, p.y))
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
		_multimesh(root, Assets.mesh_of(asset), list)

	for lm in plan["landmarks"]:
		_piece(root, lm["asset"], lm["pos"], base_h, lm["yaw"], lm["scale"])

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
		_piece(root, "building_windmill_yellow", p, WorldGen.height(p.x, p.y), rng.randf() * TAU, 8.0)
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
	var clutter: Array[Transform3D] = []
	for i in 30:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(plan["plaza_r"] * 0.6, plan["plaza_r"] + 3.0)
		clutter.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 3.0), Vector3(p.x, base_h, p.y)))
	_multimesh(root, Assets.mesh_of("barrel"), clutter.slice(0, 12))
	_multimesh(root, Assets.mesh_of("crate_A_big"), clutter.slice(12, 22))
	_multimesh(root, Assets.mesh_of("sack"), clutter.slice(22))
	return root


func _footprint(asset: String) -> Vector3:
	if not _footprints.has(asset):
		var mesh := Assets.mesh_of(asset)
		_footprints[asset] = mesh.get_aabb().size * Assets.BUILDING_SCALE if mesh else Vector3(6, 7, 6)
	return _footprints[asset]


func _piece(root: Node3D, asset: String, p: Vector2, h: float, yaw: float, scale: float) -> Node3D:
	var node := Assets.medieval(asset, scale)
	Assets.add_footprint_collider(node)
	node.position = Vector3(p.x, h, p.y)
	node.rotation.y = yaw
	root.add_child(node)
	return node


## Stone wall ring with towers, leaving gatehouses where roads enter.
func _wall_ring(root: Node3D, c: Vector2, radius: float, h: float, gates: Array, segments: int, tower_every: int) -> void:
	var sample := Assets.medieval("wall_straight", 1.0)
	var native := Assets.visual_aabb(sample)
	sample.free()
	var native_len := maxf(native.size.x, native.size.z)
	var along_x := native.size.x > native.size.z
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
		var s := p0.distance_to(p1) / maxf(native_len, 0.01)
		var mp := (p0 + p1) * 0.5
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.9, s)), Vector3(mp.x, h, mp.y))
		var is_gate := false
		for g in gates:
			if absf(wrapf(mid - g, -PI, PI)) < PI / segments:
				is_gate = true
		(gate_walls if is_gate else walls).append(t)
		if not is_gate:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.5, 6.0, p0.distance_to(p1))
			shape.shape = box
			body.position = Vector3(mp.x, h + 3.0, mp.y)
			body.rotation.y = atan2(dir.x, dir.y)
			body.add_child(shape)
			root.add_child(body)
		if i % tower_every == 0 or is_gate:
			towers.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3(p0.x, h, p0.y)))
	_multimesh(root, Assets.mesh_of("wall_straight"), walls)
	_multimesh(root, Assets.mesh_of("wall_straight_gate"), gate_walls)
	_multimesh(root, Assets.mesh_of("building_tower_A_blue"), towers)


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
