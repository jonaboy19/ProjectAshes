extends RefCounted
## Vertical slice dressing (data/world/slice_dressing.json): the scenario A pieces in Ashford (a hayloft with a climbable ladder,
## a vaultable field fence; the enterable house is a town-kit home) and the bandit camp on the Ashford -> Kingsreach road.
## Positions are relative to the town (first-gate axis), ground sampled at build time: relocatable with the town.
## Colliders carry SurfaceQuery tags (wood; the fence is vaultable). No class_name; preload it.

const PATH := "res://data/world/slice_dressing.json"
const SQ := preload("res://scripts/world/surface_query.gd")

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d
	return _data


## Town-relative [x along the first gate, z to its left] -> world XZ.
static func to_world(s: Dictionary, rel: Array) -> Vector2:
	var g0 := float((s["plan"]["gates"] as Array)[0])
	var fwd := Vector2(cos(g0), sin(g0))
	var left := Vector2(-fwd.y, fwd.x)
	return (s["pos"] as Vector2) + fwd * float(rel[0]) + left * float(rel[1])


static func settlement(name: String) -> Dictionary:
	for s in WorldGen.settlements:
		if String(s["name"]) == name:
			return s
	return {}


## Builds the scenario A pieces under `root` when `s` is the scenario town. Returns {ladder, fence} nodes (tests, the bot).
static func build_scenario_a(root: Node3D, s: Dictionary) -> Dictionary:
	var sa: Dictionary = data().get("scenario_a", {})
	if sa.is_empty() or String(s["name"]) != String(sa.get("town", "")):
		return {}
	var out := {}
	var g0 := float((s["plan"]["gates"] as Array)[0])
	# hayloft: a timber platform on posts, hay on top, a ladder to it
	var hl: Dictionary = sa["hayloft"]
	var hp := _clear_spot(s, to_world(s, hl["at"]), 6.0)
	var gy := WorldGen.height(hp.x, hp.y)
	var fh := float(hl["floor_h"])
	var sz := Vector2(float(hl["size"][0]), float(hl["size"][1]))
	var loft := Node3D.new()
	loft.name = "ScenarioHayloft"
	root.add_child(loft)
	loft.global_position = Vector3(hp.x, gy, hp.y)
	loft.rotation.y = g0
	var wood := _mat(Color(0.36, 0.26, 0.17))
	_solid(loft, Vector3(0, fh - 0.1, 0), Vector3(sz.x, 0.2, sz.y), wood, {})
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_solid(loft, Vector3(cx * (sz.x * 0.5 - 0.15), fh * 0.5, cz * (sz.y * 0.5 - 0.15)), Vector3(0.22, fh, 0.22), wood, {climbable = false})
	_solid(loft, Vector3(0, fh + 0.5, -sz.y * 0.25), Vector3(sz.x * 0.8, 0.8, sz.y * 0.4), _mat(Color(0.72, 0.6, 0.3)), {})   # hay
	var b := loft.to_global(Vector3(0.0, 0.0, sz.y * 0.5 + 0.6))
	var t := loft.to_global(Vector3(0.0, fh + 0.05, sz.y * 0.5 - 0.9))
	out["ladder"] = Ladder.spawn(root, b, t, "Hayloft Ladder")
	# fence across the path to the field: 1.05 m, vaultable
	var fe: Dictionary = sa["fence"]
	var fp := _clear_spot(s, to_world(s, fe["at"]), 5.0)
	var fence := Node3D.new()
	fence.name = "ScenarioFence"
	root.add_child(fence)
	fence.global_position = Vector3(fp.x, WorldGen.height(fp.x, fp.y), fp.y)
	fence.rotation.y = g0 + PI * 0.5
	var L := float(fe["length"])
	var H := float(fe["height"])
	for k in int(L / 2.0) + 1:
		_solid(fence, Vector3(-L * 0.5 + k * 2.0, H * 0.5, 0), Vector3(0.14, H, 0.14), wood, {vaultable = true})
	for y: float in [H * 0.45, H * 0.9]:
		_solid(fence, Vector3(0, y, 0), Vector3(L, 0.1, 0.08), wood, {vaultable = true})
	out["fence"] = fence
	return out


## The road camp's world position (an offset to the side of the road at `frac` from `from` to `to`), Vector2.INF if not configured.
static func road_camp_pos() -> Vector2:
	var rc: Dictionary = data().get("road_bandit_camp", {})
	if rc.is_empty():
		return Vector2.INF
	var a := settlement(String(rc["from"]))
	var b := settlement(String(rc["to"]))
	if a.is_empty() or b.is_empty():
		return Vector2.INF
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	var d := (pb - pa).normalized()
	return pa.lerp(pb, float(rc["frac"])) + Vector2(-d.y, d.x) * float(rc["offset"])


## The spot itself if nothing planned (lot, street, landmark) is within `rad`, else the nearest clear spot further out along the gate axis.
static func _clear_spot(s: Dictionary, p: Vector2, rad: float) -> Vector2:
	var plan: Dictionary = s["plan"]
	var g0 := float((plan["gates"] as Array)[0])
	var fwd := Vector2(cos(g0), sin(g0))
	for k in 16:
		var q := p + fwd * 3.0 * k
		var ok := CityPlanner.street_distance(plan, q) > rad and CityPlanner.landmark_clearance(plan, q) > rad
		if ok:
			for lot: Dictionary in plan["lots"]:
				if (lot["pos"] as Vector2).distance_to(q) < rad + 6.0:
					ok = false
					break
		if ok:
			return q
	return p


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.resource_name = "slice_timber"
	return m


static func _solid(parent: Node3D, at: Vector3, size: Vector3, mat: Material, tags: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = at
	parent.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = at
	parent.add_child(body)
	SQ.tag(body, &"wood", tags)


## Benchmark slice: the gated Meshy / CC0 set pieces along the scenario town's main street (data "street_set"), each on the street
## edge where it clears every house footprint and keeps 2 m in front of every door; clay pots with a plant by the main-street doors.
## Colliders tagged wood (SurfaceQuery). Returns the placed nodes.
static func build_street_set(root: Node3D, s: Dictionary) -> Array:
	var ss: Dictionary = data().get("street_set", {})
	var out: Array = []
	if ss.is_empty() or String(s["name"]) != String(ss.get("town", "")):
		return out
	var plan: Dictionary = s["plan"]
	var st: Dictionary = (plan["streets"] as Array)[int(ss.get("street", 0))]
	var a: Vector2 = st["a"]
	var b: Vector2 = st["b"]
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var L := a.distance_to(b)
	var polys: Array = []
	var doors: Array[Vector2] = []
	for lot: Dictionary in plan["lots"]:
		polys.append(CityPlanner._lot_poly(lot["pos"], lot["yaw"], String(lot["asset"])))
		doors.append(CityPlanner.door_point(lot))
	for pc: Dictionary in ss.get("pieces", []):
		var key := String(pc["key"])
		var mesh: ArrayMesh = Assets.building_mesh(key)
		if mesh == null:
			continue
		var bb := mesh.get_aabb()
		var side := float(pc["side"])
		var reach := maxf(bb.size.x, bb.size.z) * 0.5
		var p := a + dir * L * float(pc["t"]) + nrm * side * (float(st["w"]) * 0.5 + float(pc["setback"]) + reach)
		var ok := true
		for q: PackedVector2Array in polys:
			if q[0].distance_to(p) < 20.0 and Geometry2D.is_point_in_polygon(p, Geometry2D.offset_polygon(q, reach)[0]):
				ok = false
				break
		for dp: Vector2 in doors:
			if dp.distance_to(p) < reach + 2.0:
				ok = false
				break
		if not ok:
			continue
		var yaw := atan2(-nrm.x * side, -nrm.y * side) + deg_to_rad(float(pc.get("yaw_off", 0.0)))
		var node := Assets.building_node(key, true)
		root.add_child(node)
		node.global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
		node.rotation.y = yaw
		for body in node.find_children("*", "StaticBody3D", true, false):
			SQ.tag(body, &"wood", {vaultable = bb.size.y < 1.3})
		out.append(node)
	if bool(ss.get("door_pots", false)) and Assets.building_mesh("cc0_pot") != null:
		var pots: Array[Transform3D] = []
		for i in (plan["lots"] as Array).size():
			var lot: Dictionary = plan["lots"][i]
			var dp: Vector2 = doors[i]
			if dp.distance_to(Geometry2D.get_closest_point_to_segment(dp, a, b)) > float(st["w"]) * 0.5 + 6.0:
				continue
			var yaw2 := float(lot["yaw"])
			var sidev := Vector2(cos(yaw2), -sin(yaw2))
			for k: float in [-1.0, 1.0]:
				var q2 := dp + sidev * k * 0.95
				pots.append(Transform3D(Basis(Vector3.UP, yaw2 + k), Vector3(q2.x, WorldGen.height(q2.x, q2.y) - 0.02, q2.y)))
		if not pots.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Assets.building_mesh("cc0_pot")
			mm.instance_count = pots.size()
			for i in pots.size():
				mm.set_instance_transform(i, pots[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 70.0
			root.add_child(mmi)
	return out


## Benchmark slice: a landmark that closes the view down the main street (data "view_closer"; refs 05/08). It stands on the street's
## axis beyond the square, at the first distance where its footprint clears every lot, street and landmark, facing the gate.
static func build_view_closer(root: Node3D, s: Dictionary) -> Node3D:
	var vc: Dictionary = data().get("view_closer", {})
	if vc.is_empty() or String(s["name"]) != String(vc.get("town", "")):
		return null
	var plan: Dictionary = s["plan"]
	var st: Dictionary = (plan["streets"] as Array)[int(vc.get("street", 0))]
	var c: Vector2 = s["pos"]
	var dir := ((st["b"] as Vector2) - (st["a"] as Vector2)).normalized()   # plaza -> gate
	var key := String(vc["asset"])
	var mesh: ArrayMesh = Assets.building_mesh(key)
	if mesh == null:
		return null
	var bb := mesh.get_aabb()
	var hx := bb.size.x * 0.5 + 0.8
	var hz := bb.size.z * 0.5 + 0.8
	var yaw := atan2(dir.x, dir.y)          # front (+Z) toward the gate, down the street
	var polys: Array = []
	for lot: Dictionary in plan["lots"]:
		polys.append(CityPlanner._lot_poly(lot["pos"], lot["yaw"], String(lot["asset"])))
	var d := float(vc["min"])
	while d <= float(vc["max"]):
		var p := c - dir * (float(plan["plaza_r"]) + d + hz)
		var poly := CityPlanner._rect(p, yaw, hx, hz)
		var ok := CityPlanner.landmark_clearance(plan, p) > maxf(hx, hz)
		if ok:
			for q: PackedVector2Array in polys:
				if q[0].distance_to(p) < 40.0 and CityPlanner._poly_gap(poly, q) < 0.5:
					ok = false
					break
		if ok:
			for st2: Dictionary in plan["streets"]:
				for v: Vector2 in Array(poly) + [p]:
					if v.distance_to(Geometry2D.get_closest_point_to_segment(v, st2["a"], st2["b"])) < float(st2["w"]) * 0.5:
						ok = false
						break
				if not ok:
					break
		if ok:
			var node := Assets.building_node(key, true)
			root.add_child(node)
			node.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) - 0.1, p.y)
			node.rotation.y = yaw
			for body in node.find_children("*", "StaticBody3D", true, false):
				SQ.tag(body, &"stone", {climbable = true})
			# occlusion culling (audit P0): the landmark hides the town behind it; box inset so it never culls what peeks round it
			var occ := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = bb.size * Vector3(0.8, 0.85, 0.8)
			occ.occluder = bo
			occ.position = bb.get_center() * Vector3(1, 0.925, 1)
			node.add_child(occ)
			return node
		d += 2.0
	return null
