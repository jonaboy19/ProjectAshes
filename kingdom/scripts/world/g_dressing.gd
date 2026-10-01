extends RefCounted
## Style G facade dressing for towns (skills ashes-style-g section 7, kit = style_lab/lab_gate_extra.gd): ivy vines, flower boxes
## under the windows, flower tubs and baskets at the house feet, every repeat a MultiMesh (about 8 draws per town).
## Density follows the tier (vines 5/4/2 per house) and the town (Thornfield, the vertical slice, gets the full G density;
## other towns half, villages a third). Seeded by the town id: a rebuilt town looks identical, no two towns alike.
## Preload this script; no class_name.

const Extra := preload("res://scripts/style_lab/lab_gate_extra.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const SLICE_TOWN := "Thornfield"
const CULL := 110.0


static func density_for(s: Dictionary) -> float:
	if String(s["name"]) == SLICE_TOWN:
		return 1.0
	return 0.5 if String(s.get("kind", "village")) != "village" else 0.34


## footprint: Callable(asset) -> Vector3 (fitted mesh size). Returns counts (QA / tests).
static func dress_town(root: Node3D, s: Dictionary, plan: Dictionary, footprint: Callable, tier: String) -> Dictionary:
	var dens := density_for(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173 + int(s["id"]) * 31
	var ivy_x: Array = []
	var ivy_c: Array = []
	var boxes := [[], [], []]
	var tubs := [[], []]
	var baskets := [[], []]
	var vines := maxi(int(round((5 if tier == "high" else (4 if tier == "medium" else 2)) * dens)), 1)
	var step := 0.19 if tier != "low" else 0.3
	var n_tub := maxi(int(round((3 if tier != "low" else 1) * dens)), 1)
	var n_bas := maxi(int(round((2 if tier != "low" else 1) * dens)), 1)
	var n_box := 2 if dens > 0.4 else 1
	var hues_olive := 0.12
	for lot: Dictionary in plan["lots"]:
		var asset := String(lot["asset"])
		if not (BuildingProfiles.is_house(asset) or asset.begins_with("house_town")):
			continue
		var size: Vector3 = footprint.call(asset)
		var wall := BuildingProfiles.HOUSE_WALL
		var half_w := size.x * wall * 0.8
		var yaw: float = lot["yaw"]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var door_x := BuildingProfiles.door_local(asset, size).x
		var base := (lot["pos"] as Vector2) + fwd * (size.z * wall + 0.05)
		var gy := minf(WorldGen.height(base.x, base.y), WorldGen.height(base.x + side.x * half_w * 0.6, base.y + side.y * half_w * 0.6))
		gy = minf(gy, WorldGen.height(base.x - side.x * half_w * 0.6, base.y - side.y * half_w * 0.6))
		var face := Basis(Vector3.UP, yaw)
		var tall := minf(size.y * 0.62, 6.4)
		for v in vines:
			var u := rng.randf_range(-half_w, half_w)
			if absf(u - door_x) < 1.3:
				u += signf(u - door_x + 0.01) * 1.6
			var y := rng.randf_range(0.2, 1.4)
			var top := rng.randf_range(tall * 0.45, tall)
			var olive := rng.randf() < hues_olive
			while y < top:
				var p := base + side * (u + rng.randf_range(-0.3, 0.3))
				ivy_x.append(Transform3D(face * Basis(Vector3.BACK, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.25)),
					Vector3(p.x, gy + y, p.y) + Vector3(fwd.x, 0, fwd.y) * 0.04))
				# Desaturated, varied leaf green (pass 6: neon ivy fix): hue 0.22-0.30 (olive 0.15-0.19 on some vines), s 0.40-0.60, v 0.55-0.80
				var hh := rng.randf_range(0.15, 0.19) if olive else rng.randf_range(0.22, 0.30)
				ivy_c.append(Color.from_hsv(hh, rng.randf_range(0.40, 0.60), rng.randf_range(0.55, 0.80)))
				y += step
		if dens > 0.4 or rng.randf() < 0.6:
			for row in [[size.y * 0.25, -0.5], [size.y * 0.42, 0.5]]:
				for k in n_box:
					var u2 := (-0.55 if k == 0 else 0.55) * half_w + rng.randf_range(-0.2, 0.2)
					if absf(u2 - door_x) < 1.0 and row[0] < 4.0:
						continue
					var p2 := base + side * u2
					(boxes[(k + int(row[0] > 4.0)) % 3] as Array).append(Transform3D(face, Vector3(p2.x, gy + clampf(row[0], 2.4, 6.0) + rng.randf_range(-0.1, 0.1), p2.y) + Vector3(fwd.x, 0, fwd.y) * 0.02))
		for k in n_tub:
			var u3 := rng.randf_range(-half_w, half_w)
			if absf(u3 - door_x) < 1.2:
				continue
			var p3 := base + side * u3 + fwd * rng.randf_range(0.5, 1.0)
			(tubs[k % 2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.3)), Vector3(p3.x, WorldGen.height(p3.x, p3.y) - 0.02, p3.y)))
		for k in n_bas:
			var u4 := rng.randf_range(-half_w, half_w)
			if absf(u4 - door_x) < 1.2:
				continue
			var p4 := base + side * u4 + fwd * rng.randf_range(0.4, 1.1)
			(baskets[k % 2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.25)), Vector3(p4.x, WorldGen.height(p4.x, p4.y) - 0.02, p4.y)))
	var made := {"ivy": ivy_x.size(), "boxes": 0, "tubs": 0, "baskets": 0}
	var lite := tier == "low"
	var holder := Node3D.new()
	holder.name = "GDressing"
	root.add_child(holder)
	# Baked per 48 m cell (visibility culling per neighbourhood, 2 draws per cell: leaves + kit) instead of one MultiMesh per
	# variant for the whole town: LOW drew 259 heavy tubs at once. Instance tints become pre-tinted mesh variants.
	var ivy_v: Array = []
	for i in 3:
		ivy_v.append(_clump(3 + i, 11 if not lite else 6))
	var kit := {}   # cell -> SurfaceTool
	var leaf := {}
	for i in ivy_x.size():
		var cell := _cell(ivy_x[i].origin)
		if not leaf.has(cell):
			leaf[cell] = _st()
		(leaf[cell] as SurfaceTool).append_from(_tinted_cached(ivy_v, i % 3, ivy_c[i]), 0, ivy_x[i])
	for i in 3:
		made["boxes"] += boxes[i].size()
		_bake(kit, Extra.flower_box(i, lite), boxes[i])
	for i in 2:
		made["tubs"] += tubs[i].size()
		made["baskets"] += baskets[i].size()
		_bake(kit, Extra.flower_tub(i, lite), tubs[i])
		_bake(kit, Extra.basket(i, lite), baskets[i])
	var range_end := 60.0 if lite else CULL
	_emit(holder, leaf, Extra.vc_material(true), "Ivy", range_end)
	_emit(holder, kit, Extra.vc_material(), "Kit", range_end * 0.8)
	return made


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 48.0), floori(p.z / 48.0))


static var _tint_cache := {}
static var _clumps := {}


static func _clump(seed_v: int, leaves: int) -> ArrayMesh:
	var k := seed_v * 100 + leaves
	if not _clumps.has(k):
		_clumps[k] = Extra.ivy_clump(seed_v, leaves)
	return _clumps[k]


static func _tinted(m: ArrayMesh, tint: Color) -> ArrayMesh:
	var arr := m.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	for i in cols.size():
		cols[i] = cols[i] * tint
	arr[Mesh.ARRAY_COLOR] = cols
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Base clump tinted by the instance colour, quantised (about 40 distinct meshes per town) and cached.
static func _tinted_cached(variants: Array, vi: int, c: Color) -> ArrayMesh:
	var q := Color(snappedf(c.r, 0.06), snappedf(c.g, 0.06), snappedf(c.b, 0.06))
	var key := "%d|%s" % [variants[vi].get_instance_id(), q.to_html(false)]
	if not _tint_cache.has(key):
		_tint_cache[key] = _tinted(variants[vi], q)
	return _tint_cache[key]


static func _bake(cells: Dictionary, mesh: ArrayMesh, xfs: Array) -> void:
	for xf: Transform3D in xfs:
		var cell := _cell(xf.origin)
		if not cells.has(cell):
			cells[cell] = _st()
		(cells[cell] as SurfaceTool).append_from(mesh, 0, xf)


static func _emit(parent: Node3D, cells: Dictionary, mat: Material, nm: String, range_end: float) -> void:
	for cell: Vector2i in cells:
		var st: SurfaceTool = cells[cell]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d_%d" % [nm, cell.x, cell.y]
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = range_end * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
