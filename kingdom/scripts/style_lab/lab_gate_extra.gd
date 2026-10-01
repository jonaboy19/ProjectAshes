extends RefCounted
## Style G dressing kit for the gate market (see .claude/skills/ashes-style-g-assets): ivy and flower boxes on facades,
## baskets and flower tubs, extra stall goods, townsfolk list. Repeated props are MultiMeshes (1 draw per variant), the
## stall goods are ONE merged mesh. All colours come from StyleG.PALETTE; vertex colours are baked as LINEAR.
## No class_name (project rule).

const StyleG := preload("res://scripts/style_g.gd")

const FACADE_X := 8.45          # |x| of the house fronts (houses sit at 12.2, scale 0.8, jetty overhang)
static var _vc_mat: Material
static var _vc_mat2: Material


## Ivy clump colour with real variation (2026-10-01): mostly deep leaf greens, some dark shaded clumps, a few
## sun-yellowed and russet ones, so walls do not read as one flat bright sheet.
static func ivy_color(rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	if r < 0.12:
		return Color.from_hsv(rng.randf_range(0.14, 0.19), rng.randf_range(0.5, 0.7), rng.randf_range(0.7, 0.9))   # yellowed
	if r < 0.17:
		return Color.from_hsv(rng.randf_range(0.05, 0.09), rng.randf_range(0.45, 0.6), rng.randf_range(0.5, 0.7))  # russet
	if r < 0.42:
		return Color.from_hsv(rng.randf_range(0.27, 0.33), rng.randf_range(0.6, 0.85), rng.randf_range(0.35, 0.55)) # shaded
	return Color.from_hsv(rng.randf_range(0.22, 0.31), rng.randf_range(0.5, 0.8), rng.randf_range(0.55, 0.85))


static func lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


## Polished material fed with vertex colours (+ MultiMesh instance colour), single or double sided.
static func vc_material(double_sided := false) -> Material:
	var key := "vc2" if double_sided else "vc1"
	if not StyleG._cache.has(key):
		var base := StandardMaterial3D.new()
		base.vertex_color_use_as_albedo = true
		var m := StyleG.material_for("ivy", base) as ShaderMaterial
		StyleG._cache[key] = StyleG.double_sided(m) if double_sided else m
	return StyleG._cache[key]


# --- vertex coloured mesh builder -----------------------------------------------------------------------------------

class VC:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func add(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var a := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		for i in idx:
			v.append(xf * verts[i])
			n.append((xf.basis * norms[i]).normalized())
			c.append(col)

	func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color) -> void:
		var nn := (b - a).cross(cc - a).normalized()
		for p in [a, b, cc]:
			v.append(p)
			n.append(nn)
			c.append(col)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _puff(r: float, seg := 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = 3
	return s


static func _leaf(vc: VC, pos: Vector3, size: float, spin: float, tilt: Vector2, col: Color) -> void:
	var b := Basis(Vector3.BACK, spin) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.UP, tilt.y)
	var a := pos + b * Vector3(0, -0.5 * size, 0)
	var r := pos + b * Vector3(0.45 * size, 0, 0)
	var t := pos + b * Vector3(0, 0.6 * size, 0)
	var l := pos + b * Vector3(-0.45 * size, 0, 0)
	vc.tri(a, r, t, col)
	vc.tri(a, t, l, col)


# --- kit meshes ---------------------------------------------------------------------------------------------------

static func ivy_clump(seed_v := 1, leaves := 11) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var vc := VC.new()
	var greens := ["3a6a22", "4e8a2a", "2b5a1c", "6f9e30", "447a26"]
	for i in leaves:
		var p := Vector3(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.28, 0.28), rng.randf_range(0.0, 0.07))
		_leaf(vc, p, rng.randf_range(0.16, 0.26), rng.randf() * TAU, Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)), lin(greens[rng.randi() % greens.size()]))
	return vc.commit()


static func flower_box(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + variant
	var vc := VC.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(1.1, 0.24, 0.28)
	vc.add(bx, Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0.14)), lin(StyleG.PALETTE["timber_light"]))
	var cols: Array = [["flower_red", "plaster", "flower_pink"], ["flower_yellow", "flower_purple", "plaster"], ["flower_pink", "flower_yellow", "flower_red"]][variant % 3]
	for i in 7:
		vc.add(_puff(0.1), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), Vector3(-0.46 + i * 0.153, 0.27, 0.14 + rng.randf_range(-0.04, 0.04))), lin(StyleG.PALETTE["ivy"]))
	for i in 11:
		var fp := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.31, 0.4), rng.randf_range(0.08, 0.22))
		vc.add(_puff(0.062), Transform3D(Basis.IDENTITY, fp), lin(StyleG.PALETTE[cols[rng.randi() % 3]]))
	for i in 5:   # trailing leaves over the front
		_leaf(vc, Vector3(-0.42 + i * 0.21, 0.02, 0.3), rng.randf_range(0.22, 0.34), rng.randf() * 0.4, Vector2(0.1, 0), lin("4b8a28"))
	return vc.commit()


static func basket(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70 + variant
	var vc := VC.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.27
	cm.bottom_radius = 0.2
	cm.height = 0.28
	cm.radial_segments = 8
	cm.rings = 1
	vc.add(cm, Transform3D(Basis.IDENTITY, Vector3(0, 0.14, 0)), lin("a8773a"))
	var fruit: Array = [["flower_red", "apple_hi", "flower_red"], ["flower_yellow", "banner_gold", "foliage"]][variant % 2]
	for i in 9:
		var a := TAU * i / 9.0
		var rad := 0.13 if i < 8 else 0.0
		vc.add(_puff(0.085), Transform3D(Basis.IDENTITY, Vector3(cos(a) * rad, 0.3 + (0.07 if i == 8 else 0.0), sin(a) * rad)), lin(StyleG.PALETTE.get(fruit[rng.randi() % 3], "d8342b")))
	return vc.commit()


static func flower_tub(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90 + variant
	var vc := VC.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.34
	cm.height = 0.42
	cm.radial_segments = 8
	cm.rings = 1
	vc.add(cm, Transform3D(Basis.IDENTITY, Vector3(0, 0.21, 0)), lin("7a5330"))
	for i in 6:
		var a := TAU * i / 6.0
		vc.add(_puff(0.2), Transform3D(Basis.from_scale(Vector3(1, 0.8, 1)), Vector3(cos(a) * 0.2, 0.5, sin(a) * 0.2)), lin(StyleG.PALETTE["ivy"]))
	vc.add(_puff(0.24), Transform3D(Basis.IDENTITY, Vector3(0, 0.58, 0)), lin(StyleG.PALETTE["foliage"]))
	var cols: Array = [["flower_purple", "plaster", "flower_pink"], ["flower_red", "flower_yellow", "plaster"]][variant % 2]
	for i in 14:
		var a2 := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.3)
		vc.add(_puff(0.07), Transform3D(Basis.IDENTITY, Vector3(cos(a2) * r, rng.randf_range(0.62, 0.84), sin(a2) * r)), lin(StyleG.PALETTE[cols[rng.randi() % 3]]))
	return vc.commit()


static func multimesh(mesh: Mesh, xfs: Array, cols: Array, mat: Material, nm: String, shadows := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("keep_material", true)
	return mi


# --- placement -----------------------------------------------------------------------------------------------------

## Ivy on facades (vertical vines + sprawl), flower boxes under the windows, tubs and baskets at the house feet.
static func dress_facades(parent: Node3D, rng: RandomNumberGenerator, house_zs: Array, tier: String) -> Dictionary:
	var ivy_x: Array = []
	var ivy_c: Array = []
	var boxes := [[], [], []]
	var tubs := [[], []]
	var baskets := [[], []]
	var vines := 5 if tier == "high" else (4 if tier == "medium" else 2)
	for side: int in [-1, 1]:
		var yaw: float = PI * 0.5 * (-side)
		var out := Vector3(-side, 0, 0)
		var fx: float = side * FACADE_X
		for hz: float in house_zs:
			for v in vines:
				var zc: float = hz + rng.randf_range(-3.1, 3.1)
				var y := rng.randf_range(0.2, 1.4)
				var top := rng.randf_range(2.8, 6.4)
				while y < top:
					var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.25)),
						Vector3(fx, y, zc + rng.randf_range(-0.3, 0.3)) + out * 0.04)
					ivy_x.append(xf)
					ivy_c.append(ivy_color(rng))
					y += 0.19
			# flower boxes: two rows, 2 per row, staggered
			for row in [[3.5, -1.55], [5.9, 1.45]]:
				for k in 2:
					var bz: float = hz + (-1.55 if k == 0 else 1.55) + rng.randf_range(-0.15, 0.15)
					var bxf := Transform3D(Basis(Vector3.UP, yaw), Vector3(fx, row[0] + rng.randf_range(-0.1, 0.1), bz) + out * 0.02)
					(boxes[(k + int(row[0] > 4.0)) % 3] as Array).append(bxf)
			# tubs / baskets at the foot of the facade
			for k in 3:
				var tz: float = hz + rng.randf_range(-3.3, 3.3)
				var tx: float = fx + out.x * rng.randf_range(0.5, 1.0)
				(tubs[k % 2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.3)), Vector3(tx, 0, tz)))
			for k in 2:
				var bz2: float = hz + rng.randf_range(-3.3, 3.3)
				(baskets[k % 2] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.25)),
					Vector3(fx + out.x * rng.randf_range(0.4, 1.1), 0, bz2)))
	var made := {}
	var ivy := multimesh(ivy_clump(3, 11 if tier != "low" else 6), ivy_x, ivy_c, vc_material(true), "Ivy")
	parent.add_child(ivy)
	made["ivy"] = ivy_x.size()
	for i in 3:
		parent.add_child(multimesh(flower_box(i), boxes[i], [], vc_material(), "FlowerBox%d" % i, true))
	for i in 2:
		parent.add_child(multimesh(flower_tub(i), tubs[i], [], vc_material(), "Tub%d" % i, true))
		parent.add_child(multimesh(basket(i), baskets[i], [], vc_material(), "Basket%d" % i, true))
	made["boxes"] = boxes[0].size() + boxes[1].size() + boxes[2].size()
	return made


## Ivy up the front of a round tower (outward normal = yaw about Y), clumps between angles a0..a1 (radians, 0 = +x, PI/2 = +z).
static func ivy_tower(parent: Node3D, centre: Vector3, radius: float, a0: float, a1: float, rows: int, rng: RandomNumberGenerator) -> void:
	var xs: Array = []
	var cs: Array = []
	for k in 6:
		var a := rng.randf_range(a0, a1)
		var top := rng.randf_range(4.0, 10.0)
		var y := rng.randf_range(0.2, 1.2)
		while y < top:
			var n := Vector3(cos(a), 0, sin(a))
			var yaw := atan2(n.x, n.z)
			xs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(1.2, 2.0)),
				centre + n * (radius - 0.02) + Vector3(0, y, 0)))
			cs.append(ivy_color(rng))
			y += 0.4
			a += rng.randf_range(-0.03, 0.03)
	parent.add_child(multimesh(ivy_clump(5), xs, cs, vc_material(true), "TowerIvy"))


# --- stall dressing (2x goods) -------------------------------------------------------------------------------------

const THEME_COUNTER := {
	"produce": ["apple_red", "orange", "tomato", "cabbage", "apple_green"],
	"bakery": ["bread_round", "bread", "bread_round", "cheese_round"],
	"pottery": ["jar", "vase_tall", "jar", "mug", "plate"],
	"fish": ["fish", "fish", "bucket_wood"],
	"apothecary": ["potion_a", "potion_b", "potion_c", "bottles_row", "book_stack_a"],
	"tools": ["pot_iron", "bucket_metal", "axe", "shield", "rope_coil"],
}
const THEME_FLOOR := {
	"produce": ["crate_apples", "crate_carrots", "barrel_apples", "sack_grain", "pumpkin", "cabbage"],
	"bakery": ["sack_grain", "barrel_apples", "crate_empty", "sack_grain", "bucket_wood"],
	"pottery": ["vase_big", "vase_tall", "vase_big", "jar", "bucket_wood"],
	"fish": ["bucket_wood", "crate_empty", "barrel_apples", "bucket_wood"],
	"apothecary": ["crate_wood", "vase_tall", "barrel_apples", "sack_grain"],
	"tools": ["crate_wood", "bucket_metal", "barrel_apples", "rope_coil", "sack_grain"],
}


## stalls: Array of [Vector3 pos, float yaw, String theme]. Returns one merged MeshInstance3D (role "goods").
static func dress_stalls(stalls: Array, rng: RandomNumberGenerator, density := 1.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for s: Array in stalls:
		var T := Transform3D(Basis(Vector3.UP, s[1]), s[0])
		var theme: String = s[2]
		var counter: Array = THEME_COUNTER[theme]
		var floor_items: Array = THEME_FLOOR[theme]
		# floor row in front of the awning, two deep
		var fx := -1.9
		while fx < 1.95:
			var nm: String = floor_items[rng.randi() % floor_items.size()]
			var lvl := 0
			var cluster := nm in ["pumpkin", "cabbage"]
			var reps := 3 if cluster else 1
			for r in reps:
				var p := Vector3(fx + (r * 0.26 if cluster else 0.0), 0.0, 2.35 + rng.randf_range(-0.12, 0.12) + (0.2 if r == 1 else 0.0))
				n += _put(st, T, nm, p, rng.randf_range(-40, 40), rng.randf_range(1.1, 1.3))
			if nm.begins_with("crate") and rng.randf() < 0.7:
				n += _put(st, T, "crate_apples" if theme == "produce" else "crate_empty", Vector3(fx, 0.25, 2.35), rng.randf_range(-15, 15), 1.0)
			fx += rng.randf_range(0.62, 0.95) / maxf(density, 0.35)
		# a second, shorter row beside the stall frame
		for sd in [-1, 1]:
			var nm2: String = floor_items[rng.randi() % floor_items.size()]
			n += _put(st, T, nm2, Vector3(sd * 2.1, 0, 1.0 + rng.randf_range(-0.2, 0.3)), rng.randf_range(0, 360), 1.1)
			n += _put(st, T, "sack_grain" if rng.randf() < 0.6 else "bucket_wood", Vector3(sd * 2.55, 0, 0.6), rng.randf_range(0, 360), 1.0)
		# counter clusters (packed pyramids), z 0.35 .. 0.85
		var clusters := maxi(int(round(5 * density)), 2)
		for k in clusters:
			var nm3: String = counter[rng.randi() % counter.size()]
			var cx := -1.4 + k * (2.8 / maxf(clusters - 1, 1)) + rng.randf_range(-0.1, 0.1)
			var tall := nm3 in ["vase_tall", "bucket_wood", "pot_iron", "bucket_metal", "axe", "shield", "potion_b", "bottles_row", "book_stack_a", "plate"]
			if tall:
				n += _put(st, T, nm3, Vector3(cx, 0.9, 0.55), rng.randf_range(-30, 30), 1.2)
			else:
				for q in (6 if density > 0.6 else 3):
					var layer := 0 if q < 4 else 1
					var off := Vector2(0.11 if q % 2 == 0 else -0.11, 0.11 if (q / 2) % 2 == 0 else -0.11) if layer == 0 else Vector2.ZERO
					n += _put(st, T, nm3, Vector3(cx + off.x * 1.25, 0.9 + layer * 0.15, 0.55 + off.y * 1.25), rng.randf_range(0, 360), 1.25)
		# hanging goods under the front beam
		for q in int(round(5 * density)):
			var hx := -1.5 + q * 0.75
			n += _put(st, T, "sausage_hang" if theme in ["produce", "bakery", "pottery"] else ("fish_hang" if theme == "fish" else "lantern_hang"),
				Vector3(hx, 1.45, 1.08), 0.0, 1.0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, MarketGoods.material())
	var mi := MeshInstance3D.new()
	mi.name = "StallDressing"
	mi.mesh = mesh
	mi.set_meta("role", "goods")
	mi.set_meta("pieces", n)
	return mi


static func _put(st: SurfaceTool, T: Transform3D, nm: String, p: Vector3, yaw_deg: float, sc: float) -> int:
	var m: Mesh = MarketGoods.piece(nm)
	if m == null:
		return 0
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis.from_scale(Vector3.ONE * sc)
	st.append_from(m, 0, T * Transform3D(b, p))
	return 1


# --- townsfolk -----------------------------------------------------------------------------------------------------

const MEN := ["villager_man_a", "villager_man_b", "villager_farmer", "villager_baker", "elder_man", "father", "villager_smith", "villager_merchant"]
const WOMEN := ["villager_woman_a", "villager_woman_b", "elder_woman", "mother", "villager_healer"]
const WALKS := ["Walk", "Walk_Formal", "Walking_A", "Walk_Carry"]
const IDLES := ["Idle_Talking", "Idle_FoldArms", "Idle_Listening", "Idle_Subtle", "Greeting", "Interact", "Idle"]

## ~26 people at all depths: [model, pos, yaw, clip]. yaw 0 faces the camera (+Z), PI walks away.
static func folk(rng: RandomNumberGenerator, count: int) -> Array:
	var spots := [
		[Vector3(-3.2, 0, -7.0), 0.5, "idle"], [Vector3(-5.6, 0, -5.2), 1.3, "idle"], [Vector3(-8.1, 0, -6.4), 1.5, "idle"],
		[Vector3(1.6, 0, -15.0), PI, "walk"], [Vector3(-1.3, 0, -17.5), PI + 0.2, "walk"], [Vector3(3.5, 0, -22.0), 0.3, "walk"],
		[Vector3(-4.0, 0, -26.0), PI - 0.3, "walk"], [Vector3(0.4, 0, -29.0), 0.1, "walk"], [Vector3(5.6, 0, -33.0), PI, "walk"],
		# new: near and mid
		[Vector3(2.6, 0, -6.0), PI + 0.3, "walk"], [Vector3(4.4, 0, -8.5), 2.2, "idle"], [Vector3(5.4, 0, -9.4), 4.0, "idle"],
		[Vector3(-2.0, 0, -10.5), 0.2, "walk"], [Vector3(-4.6, 0, -13.0), 1.0, "idle"], [Vector3(3.0, 0, -12.0), PI - 0.2, "walk"],
		[Vector3(-0.8, 0, -13.8), 0.0, "walk"], [Vector3(5.0, 0, -17.0), 2.0, "idle"], [Vector3(-5.2, 0, -19.5), 0.6, "idle"],
		[Vector3(1.0, 0, -20.0), 0.2, "walk"], [Vector3(-2.6, 0, -23.0), PI, "walk"], [Vector3(4.2, 0, -25.5), 0.4, "walk"],
		[Vector3(-0.2, 0, -31.0), PI + 0.2, "walk"], [Vector3(-5.0, 0, -34.5), 1.2, "idle"], [Vector3(2.2, 0, -36.0), PI, "walk"],
		[Vector3(-2.8, 0, -39.0), 0.1, "walk"], [Vector3(0.8, 0, -41.0), PI - 0.1, "walk"],
	]
	var out := []
	for i in mini(count, spots.size()):
		var s: Array = spots[i]
		var woman := rng.randf() < 0.42
		var names: Array = WOMEN if woman else MEN
		var nm: String = names[(i * 3 + rng.randi() % 3) % names.size()]
		var clips: Array = WALKS if s[2] == "walk" else IDLES
		var clip: String = clips[rng.randi() % clips.size()]
		if woman and s[2] == "walk" and rng.randf() < 0.5:
			clip = "Walk_Female"
		var h := rng.randf_range(1.56, 1.7) if woman else rng.randf_range(1.7, 1.84)
		out.append({"model": nm, "pos": s[0], "yaw": s[1], "clip": clip, "h": h})
	return out


static func roof_material(color_key: String) -> Material:
	var key := "roof_" + color_key
	if not StyleG._cache.has(key):
		var base := StandardMaterial3D.new()
		base.albedo_color = Color(StyleG.PALETTE[color_key])
		var m := StyleG.material_for("roof", base) as ShaderMaterial
		StyleG._cache[key] = m
	return StyleG._cache[key]
