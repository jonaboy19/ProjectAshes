extends RefCounted
## Ashford quality benchmark street (AAA pass 2, 2026-10-06; docs/art/AAA_PRESENTATION_REVIEW.md "golden rule": polish ONE
## street block until it looks finished, then every settlement copies the standard). The first gate street of Ashford, plaza
## to gate, ~60 m. Each house facing it is tied to the street: worn mud at the door, a barrel or bench by it, firewood stacked
## against the side wall, a washing line strung between neighbours, a trough every few houses; the road gets puddles and
## worn verges. All MultiMesh (one draw per kind) with contact blobs; decals only on MEDIUM+ (TownDecals budget rules).
## Called from SettlementBuilder._build for Ashford only. Preload; no class_name.

const LampGlow := preload("res://scripts/world/lamp_glow.gd")
const STREET := 0              # plan["streets"][0]: plaza -> first gate
const REACH := 17.0            # lots whose centre is within this of the street line face it
const DOOR := 4.4              # lot centre -> door line (houses are fitted to ~10 m lots)


static func build(b: Node, root: Node3D, s: Dictionary, plan: Dictionary, market := false) -> int:
	if (plan["streets"] as Array).size() <= STREET:
		return 0
	var st: Dictionary = plan["streets"][STREET]
	var a: Vector2 = st["a"]
	var e: Vector2 = st["b"]
	var half := float(st["w"]) * 0.5
	var dir := (e - a).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + int(s["id"])
	var lists := {"woodpile": [], "washing_line": [], "water_trough": [], "barrel": [], "bench": [], "crate_stack": [], "sack_pile": [], "mf_lantern_wall_scroll": [], "flower_bed": [], "planter_box": [], "banner_pole": [], "market_stall_red": [], "mf_lamp_post_timber_cross": [], "mf_fence_picket_low": [], "mf_bush_raspberry": []}
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
	# Market edge (AAA pass 10, the Kingsreach gate market target): the street reads narrow and framed when its verges carry
	# stalls, flower beds, banner poles and lamp posts in a rhythm, the middle left as cobbled road. Every ~7 m each side.
	if market:
		var len2 := a.distance_to(e)
		var t3 := 5.0
		var k3 := 0
		while t3 < len2 - 6.0:
			for sg: float in [1.0, -1.0]:
				var edge := a + dir * (t3 + (1.8 if sg < 0.0 else 0.0)) + dir.orthogonal() * sg * (half - 2.0)     # pass 11: stalls step in, the road reads narrow
				var face := atan2(-dir.orthogonal().x * sg, -dir.orthogonal().y * sg)
				match (k3 + (1 if sg < 0.0 else 0)) % 4:
					0:
						_add(lists, "market_stall_red", edge + dir.orthogonal() * sg * 0.6, face, 0.0)
						# goods piled at the stall (AAA pass 14): crates, sacks and a barrel at its front corners
						_add(lists, "crate_stack", edge - dir * 1.3 - dir.orthogonal() * sg * 0.5, face + 0.2, 0.0)
						_add(lists, "sack_pile", edge + dir * 1.4 - dir.orthogonal() * sg * 0.4, rng.randf() * TAU, 0.0)
						_add(lists, "barrel", edge + dir * 2.2 + dir.orthogonal() * sg * 0.3, rng.randf() * TAU, 0.0)
					1:
						_add(lists, "planter_box", edge, face, 0.0)
						_add(lists, "banner_pole", edge + dir * 1.6, face, 0.0)
					2:
						_add(lists, "mf_lamp_post_timber_cross", edge, face, 0.0)
						_add(lists, "barrel", edge + dir * 1.0, rng.randf() * TAU, 0.0)
					3:
						_add(lists, "planter_box", edge, face, 0.0)
				# outer verge: low picket fence and bushes between the stall row and the house fronts (frame edges)
				var outer := a + dir * (t3 + 3.5) + dir.orthogonal() * sg * (half + 1.4)
				_add(lists, "mf_fence_picket_low", outer, atan2(dir.x, dir.y) + PI * 0.5, 0.0)
				if k3 % 2 == 0:
					_add(lists, "mf_bush_raspberry", outer + dir * 2.0, rng.randf() * TAU, 0.0)
			t3 += 7.0
			k3 += 1
		# tall red heraldic banners flanking the gate opening (the target's gate reads by its banners): banner poles at 2x
		var gwr: float = float(plan["wall_radius"]) if plan["walls"] else float(s["radius"]) * 1.1
		var gc := (s["pos"] as Vector2) + dir * (gwr - 2.2)
		# the art target's gatehouse (Style Lab G, code-built twin round towers, pointed arch, portcullis, lion banners), set
		# over the wall gate: its front face 3.5 m inside the wall line, 6 m deep, so it encloses the ring's own gate piece.
		# Materials by role from StyleG, as the lab applies them. MEDIUM+ only (LOW draw budget keeps the plain wall gate).
		if not bool(b.call("_low")):
			var LabGate: GDScript = load("res://scripts/style_lab/lab_gate.gd")
			var lg: Node3D = LabGate.new()
			lg.name = "HeroGatehouse"
			holder.add_child(lg)
			var gp := (s["pos"] as Vector2) + dir * (gwr - 3.5)
			lg.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y) + PI), Vector3(gp.x, WorldGen.height(gp.x, gp.y) - 0.05, gp.y))
			lg.call("_gatehouse", Vector3.ZERO)
			# hide the ring's own wall-gate piece inside the new gatehouse (it showed as a pale inner arch)
			var gate_pt := (s["pos"] as Vector2) + dir * gwr
			for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
				var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null or mm.mesh.get_aabb().size.y < 6.0:
					continue
				for ii in mm.instance_count:
					var wt := (mmi as Node3D).global_transform * mm.get_instance_transform(ii)
					if Vector2(wt.origin.x, wt.origin.z).distance_to(gate_pt) < 2.5:
						mm.set_instance_transform(ii, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), mm.get_instance_transform(ii).origin))
			var StyleG := load("res://scripts/style_g.gd")
			var tier: String = StyleG.current_tier()
			for mi in lg.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.has_meta("role") and not m.has_meta("keep_material"):
					m.material_override = StyleG.material_for(String(m.get_meta("role")), m.material_override, 1, tier)
				m.layers |= TownDecals.WALL_LAYER
		# overhanging trees framing the near edges of the gate view (camera stands ~40 m inside the wall), MEDIUM+
		if not bool(b.call("_low")):
			var trees: Array[Transform3D] = []
			for tt: Array in [[-36.0, 1.0], [-30.0, -1.0], [-22.0, 1.0]]:
				var tp2 := (s["pos"] as Vector2) + dir * (gwr + float(tt[0])) + dir.orthogonal() * float(tt[1]) * (half + 3.2)
				trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.85), Vector3(tp2.x, WorldGen.height(tp2.x, tp2.y) - 0.1, tp2.y)))
			TerrainStreamer.region_tree_chain(holder, "region/nature/oak_a", trees)
		for sg2: float in [1.0, -1.0]:
			var bp := gc + dir.orthogonal() * sg2 * 6.2
			(lists["banner_pole"] as Array).append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)).scaled(Vector3.ONE * 2.1), Vector3(bp.x, WorldGen.height(bp.x, bp.y) - 0.05, bp.y)))
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
	# the street's daily work routine (dawn farmers .. night watch) and warm door lanterns at night
	var routines: Node = preload("res://scripts/world/street_routines.gd").new()
	routines.set("enabled_tier", not bool(b.call("_low")))     # LOW: no extra vignettes (skinned draw budget)
	routines.set("centre", a + dir * a.distance_to(e) * 0.5)
	var dpts: Array = []
	for d: Array in doors:
		dpts.append(d[0])
	routines.set("doors", dpts)
	holder.add_child(routines)
	var lamps: Array = []
	for d: Array in doors:
		var lp2: Vector2 = (d[0] as Vector2) + (d[1] as Vector2) * 0.35
		_add(lists, "mf_lantern_wall_scroll", lp2, atan2((d[1] as Vector2).x, (d[1] as Vector2).y), 1.75)
		lamps.append({"pos": Vector3(lp2.x, WorldGen.height(lp2.x, lp2.y) + 2.1, lp2.y), "color": Color(1.0, 0.66, 0.32), "range": 6.0, "size": 0.7})
	if not lamps.is_empty() and not bool(b.call("_low")):
		var lnodes: Array = LampGlow.build(holder, lamps)
		# warm light spill on the facade around each door lantern (emission decal on the wall batches), parented to the
		# glow batch so it only exists at night; MEDIUM+ only (decal budget rules)
		if decals and not lnodes.is_empty() and lnodes[0].get("batch") != null:
			var batch: Node3D = lnodes[0].get("batch")
			var g := GradientTexture2D.new()
			g.fill = GradientTexture2D.FILL_RADIAL
			g.fill_from = Vector2(0.5, 0.5)
			g.fill_to = Vector2(1.0, 0.5)
			var grad := Gradient.new()
			grad.set_color(0, Color(1.0, 0.7, 0.4, 1.0))
			grad.set_color(1, Color(1.0, 0.6, 0.3, 0.0))
			g.gradient = grad
			for d: Array in doors:
				var out3 := Vector3((d[1] as Vector2).x, 0.0, (d[1] as Vector2).y)
				var wp: Vector2 = d[0]
				var dec := Decal.new()
				dec.size = Vector3(5.0, 2.4, 4.4)
				dec.texture_emission = g
				dec.emission_energy = 3.0
				dec.modulate = Color(1, 1, 1, 0.0)        # emission only, keep the wall albedo
				dec.cull_mask = TownDecals.WALL_LAYER
				dec.distance_fade_enabled = true
				dec.distance_fade_begin = 35.0
				dec.distance_fade_length = 10.0
				batch.add_child(dec)
				dec.top_level = true
				dec.global_transform = Transform3D(TownDecals.wall_basis(out3), Vector3(wp.x, WorldGen.height(wp.x, wp.y) + 2.0, wp.y) + out3 * 0.6)
	if bool(b.call("_low")):
		# LOW draw budget (<= 135 in the gate view): keep only the kinds that carry the composition
		for kk: String in lists.keys():
			if true:     # pass 14: LOW adds no props (draw budget); the town's own stalls remain
				lists[kk] = []
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
		b.call("_multimesh", holder, mesh, list, not bool(b.call("_low")), false)
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
