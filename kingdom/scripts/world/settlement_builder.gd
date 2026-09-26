class_name SettlementBuilder
extends Node3D
## Builds settlements from KayKit pieces when the focus comes within BUILD_RANGE
## and frees them past FREE_RANGE. Layouts are seeded by settlement id, so a
## village looks the same every time you return to it.

const BUILD_RANGE := 520.0
const FREE_RANGE := 700.0
const HOMES := ["building_home_A_red", "building_home_B_red", "building_home_A_blue", "building_home_B_blue",
	"building_home_A_yellow", "building_home_B_yellow", "building_home_A_green", "building_home_B_green"]

signal settlement_built(settlement: Dictionary, root: Node3D)

var focus := Vector3.ZERO
var _built: Dictionary = {}      # id -> Node3D
var _timer := 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	update_now()


func update_now() -> void:
	var p := Vector2(focus.x, focus.z)
	for s in WorldGen.settlements:
		var d := p.distance_to(s["pos"])
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + s["id"]
	var r: float = s["radius"]
	var gaps := _road_angles(s)
	match s["kind"]:
		"castle":
			_piece(root, s, "building_castle_blue", Vector2.ZERO, 0.0, 16.0)
			_walls(root, s, r * 0.55, gaps)
			_ring_of_homes(root, s, rng, r * 0.75, r * 1.05, 16, gaps)
			_piece(root, s, "building_barracks_blue", Vector2(r * 0.3, r * 0.25), PI * 0.8)
			_piece(root, s, "building_church_red", Vector2(-r * 0.3, r * 0.2), PI * 0.2)
		"town":
			_piece(root, s, "building_well_red", Vector2.ZERO, 0.0, 6.0)
			_piece(root, s, "building_church_blue", Vector2(-r * 0.25, -r * 0.2), 0.6)
			_piece(root, s, "building_tavern_red", Vector2(r * 0.25, -r * 0.15), -0.8)
			_piece(root, s, "building_barracks_blue", Vector2(r * 0.2, r * 0.3), PI)
			_piece(root, s, "building_market_red", Vector2(-r * 0.1, r * 0.15), PI, 6.0)
			_piece(root, s, "building_market_yellow", Vector2(r * 0.05, r * 0.18), PI + 0.4, 6.0)
			_ring_of_homes(root, s, rng, r * 0.45, r * 0.7, 12, gaps)
			_ring_of_homes(root, s, rng, r * 0.8, r * 1.0, 14, gaps)
		_:
			_piece(root, s, "building_well_red", Vector2.ZERO, 0.0, 6.0)
			_piece(root, s, "building_church_blue", Vector2(-r * 0.4, -r * 0.3), 0.7)
			_piece(root, s, "building_tavern_green", Vector2(r * 0.4, -r * 0.2), -0.9)
			_piece(root, s, "building_blacksmith_blue", Vector2(-r * 0.45, r * 0.3), 2.2)
			_piece(root, s, "building_market_red", Vector2(r * 0.1, r * 0.25), PI, 6.0)
			_ring_of_homes(root, s, rng, r * 0.5, r * 0.8, 9, gaps)
	# Fields, windmill and a lumber mill outside every settlement.
	_piece(root, s, "building_windmill_yellow", Vector2(r * 1.35, -r * 0.6), 0.3)
	_piece(root, s, "building_lumbermill_red", Vector2(-r * 1.9, r * 1.2), 1.2)
	for i in 6:
		var ang := rng.randf() * TAU
		if _near_gap(ang, gaps):
			continue
		var field := Assets.medieval("building_grain", 9.0)
		_place(root, field, s, Vector2(cos(ang), sin(ang)) * rng.randf_range(r * 1.3, r * 1.8), rng.randf() * TAU)
	for i in 8:
		var prop := Assets.medieval(["barrel", "crate_A_big", "sack", "barrel"][i % 4], 3.0)
		_place(root, prop, s, Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.3, rng.randf() * TAU)
	return root


func _piece(root: Node3D, s: Dictionary, asset: String, offset: Vector2, yaw: float, scale := Assets.BUILDING_SCALE) -> Node3D:
	var node := Assets.medieval(asset, scale)
	Assets.add_footprint_collider(node)
	return _place(root, node, s, offset, yaw)


func _place(root: Node3D, node: Node3D, s: Dictionary, offset: Vector2, yaw: float) -> Node3D:
	var p: Vector2 = s["pos"] + offset
	node.position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	node.rotation.y = yaw
	root.add_child(node)
	return node


func _ring_of_homes(root: Node3D, s: Dictionary, rng: RandomNumberGenerator, r0: float, r1: float, count: int, gaps: Array[float]) -> void:
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.15, 0.15)
		if _near_gap(ang, gaps):
			continue
		var off := Vector2(cos(ang), sin(ang)) * rng.randf_range(r0, r1)
		_piece(root, s, HOMES[rng.randi() % HOMES.size()], off, atan2(-off.x, -off.y))


func _walls(root: Node3D, s: Dictionary, radius: float, gaps: Array[float]) -> void:
	var segments := 20
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var mid := (a0 + a1) * 0.5
		var p0 := Vector2(cos(a0), sin(a0)) * radius
		var p1 := Vector2(cos(a1), sin(a1)) * radius
		var gate := _near_gap(mid, gaps, 0.2)
		var wall := Assets.medieval("wall_straight_gate" if gate else "wall_straight", 1.0)
		var native := Assets.visual_aabb(wall)
		var length := maxf(native.size.x, native.size.z)
		wall.get_child(0).scale = Vector3.ONE * (p0.distance_to(p1) / maxf(length, 0.01))
		var dir := p1 - p0
		_place(root, wall, s, (p0 + p1) * 0.5, atan2(dir.x, dir.y) + (PI * 0.5 if native.size.x > native.size.z else 0.0))
		if not gate:
			Assets.add_footprint_collider(wall, 1.0)
		if i % 4 == 0:
			_piece(root, s, "building_tower_A_blue", p0, 0.0, 9.0)


## Directions (radians) of roads leaving this settlement, kept clear of buildings.
func _road_angles(s: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for r in WorldGen.roads:
		var other := -1
		if r.x == s["id"]:
			other = r.y
		elif r.y == s["id"]:
			other = r.x
		if other >= 0:
			var d: Vector2 = WorldGen.settlements[other]["pos"] - s["pos"]
			out.append(atan2(d.y, d.x))
	return out


func _near_gap(ang: float, gaps: Array[float], width := 0.28) -> bool:
	for g in gaps:
		if absf(wrapf(ang - g, -PI, PI)) < width:
			return true
	return false
