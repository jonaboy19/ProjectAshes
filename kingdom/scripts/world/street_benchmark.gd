extends RefCounted
## Ashford quality benchmark street (AAA pass 2, 2026-10-06; docs/art/AAA_PRESENTATION_REVIEW.md "golden rule": polish ONE
## street block until it looks finished, then every settlement copies the standard). The first gate street of Ashford, plaza
## to gate, ~60 m. Each house facing it is tied to the street: worn mud at the door, a barrel or bench by it, firewood stacked
## against the side wall, a washing line strung between neighbours, a trough every few houses; the road gets puddles and
## worn verges. All MultiMesh (one draw per kind) with contact blobs; decals only on MEDIUM+ (TownDecals budget rules).
## Called from SettlementBuilder._build for Ashford only. Preload; no class_name.

const STREET := 0              # plan["streets"][0]: plaza -> first gate
const REACH := 17.0            # lots whose centre is within this of the street line face it
const DOOR := 4.4              # lot centre -> door line (houses are fitted to ~10 m lots)


static func build(b: Node, root: Node3D, s: Dictionary, plan: Dictionary) -> int:
	if (plan["streets"] as Array).size() <= STREET:
		return 0
	var st: Dictionary = plan["streets"][STREET]
	var a: Vector2 = st["a"]
	var e: Vector2 = st["b"]
	var half := float(st["w"]) * 0.5
	var dir := (e - a).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + int(s["id"])
	var lists := {"woodpile": [], "washing_line": [], "water_trough": [], "barrel": [], "bench": [], "crate_stack": [], "sack_pile": []}
	var doors: Array = []          # [door point, out normal toward street, side sign, t along street]
	for lot: Dictionary in plan["lots"]:
		var lp: Vector2 = lot["pos"]
		var t := (lp - a).dot(dir)
		if t < 2.0 or t > a.distance_to(e) - 2.0:
			continue
		var q := a + dir * t
		if lp.distance_to(q) > REACH:
			continue
		var out := (q - lp).normalized()
		doors.append([lp + out * DOOR, out, signf(dir.orthogonal().dot(lp - q)), t])
	doors.sort_custom(func(x: Array, y: Array) -> bool: return float(x[3]) < float(y[3]))
	var holder := Node3D.new()
	holder.name = "BenchmarkStreet"
	root.add_child(holder)
	var decals: bool = TownDecals.available() and not bool(b.call("_low"))
	var i := 0
	for d: Array in doors:
		var dp: Vector2 = d[0]
		var out: Vector2 = d[1]
		var side := out.orthogonal()
		var yaw_out := atan2(out.x, out.y)
		if decals:
			_decal(holder, "dirt", dp + out * 0.8, yaw_out, Vector3(3.4, 2.0, 2.6), Color(1, 1, 1, 0.9))
		var flip := 1.0 if i % 2 == 0 else -1.0
		# by the door: a barrel or a bench, sometimes crates / sacks for a trade house
		var by := dp + out * 0.7 + side * 1.6 * flip
		match i % 4:
			0, 2:
				_add(lists, "barrel", by, rng.randf() * TAU, 0.0)
			1:
				_add(lists, "bench", dp + out * 0.6 + side * 1.9 * flip, yaw_out + PI, 0.0)
			3:
				_add(lists, "crate_stack", by, yaw_out + rng.randf_range(-0.3, 0.3), 0.0)
				_add(lists, "sack_pile", by + side * 1.1 * flip, rng.randf() * TAU, 0.0)
		# firewood against the side wall, end on to the street
		if i % 3 != 2:
			_add(lists, "woodpile", dp - out * 1.6 + side * 4.1 * -flip, yaw_out + PI * 0.5, 0.0)
		# a trough at the street edge every third house
		if i % 3 == 1:
			_add(lists, "water_trough", dp + out * 2.6 + side * 2.8 * flip, yaw_out + PI * 0.5, 0.0)
		i += 1
	# washing lines between neighbours on the same side, set back from the street
	for k in doors.size() - 1:
		var d0: Array = doors[k]
		var d1: Array = []
		for j in range(k + 1, doors.size()):
			if float(doors[j][2]) == float(d0[2]):
				d1 = doors[j]
				break
		if d1.is_empty() or (d0[0] as Vector2).distance_to(d1[0]) > 15.0 or k % 2 == 1:
			continue
		var mid: Vector2 = ((d0[0] as Vector2) + (d1[0] as Vector2)) * 0.5 - (d0[1] as Vector2) * 2.4
		var along: Vector2 = ((d1[0] as Vector2) - (d0[0] as Vector2)).normalized()
		_add(lists, "washing_line", mid, atan2(along.x, along.y) + PI * 0.5, 0.0)
	# the road: puddles in the ruts and worn verges along both edges
	if decals:
		var len := a.distance_to(e)
		var t2 := 6.0
		while t2 < len - 4.0:
			var off := rng.randf_range(-0.35, 0.35) * half
			_decal(holder, "puddle", a + dir * t2 + dir.orthogonal() * off, rng.randf() * TAU, Vector3(rng.randf_range(1.4, 2.4), 1.0, rng.randf_range(1.0, 1.8)))
			for sg: float in [1.0, -1.0]:
				_decal(holder, "dirt", a + dir * (t2 + 4.0) + dir.orthogonal() * sg * (half + 0.6), atan2(dir.x, dir.y), Vector3(2.2, 2.0, 6.0), Color(1, 1, 1, 0.75))
			t2 += rng.randf_range(9.0, 14.0)
	var placed := 0
	for kind: String in lists:
		var list: Array[Transform3D] = []
		list.assign(lists[kind])
		if list.is_empty():
			continue
		var mesh: Mesh = Assets.building_mesh(kind)
		if kind == "washing_line":
			mesh = load("res://scripts/build/kit_meshes.gd").mesh("laundry_line")     # coloured cloth (washing_line.glb read as white boards)
		if mesh == null:
			continue
		b.call("_multimesh", holder, mesh, list, true, false)
		placed += list.size()
	return placed


static func _add(lists: Dictionary, kind: String, p: Vector2, yaw: float, lift: float) -> void:
	if WorldGen.is_water(p.x, p.y):
		return
	(lists[kind] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, WorldGen.height(p.x, p.y) + lift, p.y)))


static func _decal(holder: Node3D, kind: String, at: Vector2, yaw: float, size: Vector3, tint := Color.WHITE) -> void:
	var d := TownDecals.make(kind, size, TownDecals.GROUND_LAYER, tint)
	holder.add_child(d)
	d.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y))
