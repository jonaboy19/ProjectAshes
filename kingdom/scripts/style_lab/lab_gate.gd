extends Node3D
## Style Lab box G: the Kingsreach gate market, recreated from docs/art/reference/03_TARGET_gate_market_detailed.webp
## with the game's own assets plus a code-built gatehouse (two round crenellated towers, arch, portcullis).
## Composition: a long cobbled street running -Z toward the gate, jettied timber townhouses both sides, striped stalls
## with goods, banners, lamps, guards with spears, townsfolk, and the hero seen from behind in the foreground.
## Roles for restyling: ground, house, stall, goods, wood, lamp, tree, gate_stone, flag, banner, hero_new, villager, guard.

const Chars := preload("res://scripts/style_lab/lab_chars.gd")
const Common := preload("res://scripts/style_lab/lab_common.gd")

const STREET_HALF := 7.2
var lamp_top := Vector3(-5.0, 3.2, -9.0)
var tri_note := {}
var _rng := RandomNumberGenerator.new()


func build(_style_id := "G") -> void:
	name = "GateMarket"
	_rng.seed = 11
	_ground()
	_gatehouse(Vector3(0, 0, -38))
	_street_rows()
	_extras()
	_people()


# --- ground -----------------------------------------------------------------------------------------------------

static func ground_color(x: float, z: float) -> Color:
	var ax := absf(x)
	var street := 1.0 - smoothstep(STREET_HALF - 0.6, STREET_HALF + 0.9, ax)
	var through_gate := 1.0 - smoothstep(-70.0, -60.0, z)          # past the gate the road narrows to a lane
	street = maxf(street * 1.0, 0.0)
	var mud := (1.0 - smoothstep(STREET_HALF, STREET_HALF + 4.5, ax)) * (1.0 - street)
	return Color(clampf(mud, 0.0, 1.0), 0.0, clampf(street, 0.0, 1.0) * clampf(through_gate + 0.0, 0.0, 1.0) + (1.0 - through_gate) * street, 0.0)


func _ground() -> void:
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = _ground_mesh(120.0, 150.0, Vector3(0, 0, -45), 2.0)
	g.set_meta("role", "ground")
	add_child(g)


static func _ground_mesh(w: float, d: float, center: Vector3, step: float) -> ArrayMesh:
	var nx := int(w / step)
	var nz := int(d / step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := center.x - w * 0.5 + ix * step
			var z := center.z - d * 0.5 + iz * step
			verts.append(Vector3(x, 0, z))
			cols.append(ground_color(x, z))
	for iz in nz:
		for ix in nx:
			var i0 := iz * (nx + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + nx + 1
			var i3 := i2 + 1
			for idx in [i0, i1, i2, i1, i3, i2]:
				st.set_color(cols[idx])
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(verts[idx].x, verts[idx].z) / 4.0)
				st.add_vertex(verts[idx])
	return st.commit()


# --- placement helpers ------------------------------------------------------------------------------------------

func _place(role: String, key: String, pos: Vector3, yaw: float, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = key
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale
	root.set_meta("role", role)
	var mi := MeshInstance3D.new()
	var mesh := Assets.building_mesh(key)
	if mesh == null:
		mesh = Assets.building_mesh(key.get_slice(":lod", 0))
	mi.mesh = mesh
	root.add_child(mi)
	add_child(root)
	return root


func _street_rows() -> void:
	var keys := ["house_town_a", "house_town_b", "house_town_c", "house_town_d"]
	var themes := ["produce", "bakery", "pottery", "fish", "apothecary", "tools"]
	var n := 0
	for side: int in [-1, 1]:
		var z := -5.0
		var i := 0
		while z > -44.0:
			var key: String = keys[(i + (0 if side < 0 else 2)) % 4]
			var lod := 0 if z > -22.0 else (1 if z > -36.0 else 2)
			var yaw: float = PI * 0.5 * (-side)           # facing the street
			_place("house", key + (":lod%d" % lod if lod > 0 else ""), Vector3(side * 12.2, 0, z), yaw, 0.8)
			# stall in front of every other house, awning over the pavement
			if i % 2 == 0 and z > -36.0:
				var stall_key := "market_stall_red" if (i / 2 + (0 if side < 0 else 1)) % 2 == 0 else "market_stall_green"
				var sp := Vector3(side * 6.7, 0, z)
				_place("stall", stall_key, sp, yaw, 1.0)
				var goods := MarketGoods.layout(themes[n % themes.size()])
				n += 1
				if goods:
					var gm := MeshInstance3D.new()
					gm.mesh = goods
					gm.position = sp
					gm.rotation.y = yaw
					gm.set_meta("role", "goods")
					add_child(gm)
			z -= 6.6
			i += 1


func _extras() -> void:
	# barrels, crates and sacks along the stall fronts, flower beds at the house feet
	var zs := [-4.5, -10.5, -17.0, -23.5, -30.0]
	for si: int in [-1, 1]:
		for k in zs.size():
			var z: float = zs[k] + _rng.randf_range(-1.0, 1.0)
			var yaw: float = PI * 0.5 * (-si)
			var which: String = ["barrel_cluster", "crate_stack", "sack_pile", "barrel_cluster", "crate_stack"][(k + (si + 1)) % 5]
			_place("wood", which, Vector3(si * 5.3, 0, z + 2.3), yaw + _rng.randf_range(-0.4, 0.4), 1.0)
			_place("flowers", "flower_strip" if k % 2 == 0 else "flower_bed", Vector3(si * 8.1, 0, z - 1.2), yaw, 1.0)
	# lamps and red banner poles with a flag each, every 12 m
	for k in 4:
		var z := -7.0 - k * 11.0
		_place("lamp", "street_lamp", Vector3(-4.6, 0, z), 0.0, 0.8)
		_place("banner", "banner_pole", Vector3(4.6, 0, z - 5.5), PI * 0.5, 1.0)
	# foreground left dressing (target 03: flower tubs, barrels, crates fill the screen edge)
	_place("flowers", "flower_bed", Vector3(-5.6, 0, -1.2), 0.6, 1.4)
	_place("wood", "barrel_cluster", Vector3(-6.4, 0, -3.0), 0.3, 1.0)
	_place("wood", "crate_stack", Vector3(-5.0, 0, -2.6), 0.5, 1.0)
	# hanging shop signs on the house fronts and bunting across the street
	for k in 6:
		var zs2 := -6.0 - k * 6.6
		for sd: int in [-1, 1]:
			_place("wood", "shop_sign", Vector3(sd * 8.4, 3.4, zs2 + 1.2), PI * 0.5 * (-sd), 1.0)
	# trees peeking over the roofs
	for p in [Vector3(-17, 0, -12), Vector3(18, 0, -26), Vector3(-19, 0, -34), Vector3(17, 0, -8)]:
		var t := MeshInstance3D.new()
		t.mesh = Assets.nature_mesh("CommonTree_%d" % _rng.randi_range(1, 4))
		t.position = p
		t.scale = Vector3.ONE * _rng.randf_range(0.8, 1.15)
		t.set_meta("role", "tree")
		add_child(t)
	# the town beyond the gate: a few lit, red-roofed houses seen through the arch
	for p in [Vector3(-6, 0, -78), Vector3(5, 0, -84), Vector3(-1, 0, -95), Vector3(10, 0, -75)]:
		_place("house", "house_%d" % _rng.randi_range(1, 8), p, _rng.randf_range(-0.4, 0.4), 1.1)


# --- people -----------------------------------------------------------------------------------------------------

func _people() -> void:
	var hero := Chars.hero_new("G")
	hero.name = "Hero"
	hero.position = Vector3(0, 0, 0)
	hero.rotation.y = PI
	hero.set_meta("blob", 0.6)
	add_child(hero)
	_walk(hero, "Walk", 0.28)
	var folk := [
		["villager_woman_a", Vector3(-3.2, 0, -7.0), 0.5, "Idle"],       # blue dress, facing us
		["villager_woman_b", Vector3(-5.6, 0, -5.2), 1.3, "Idle"],        # red dress at the stall
		["villager_merchant", Vector3(-8.1, 0, -6.4), 1.5, "Idle"],       # stallholder
		["villager_man_b", Vector3(1.6, 0, -15.0), PI, "Walk"],           # orange tunic walking away
		["villager_man_a", Vector3(-1.3, 0, -17.5), PI + 0.2, "Walk"],
		["villager_farmer", Vector3(3.5, 0, -22.0), 0.3, "Walk"],
		["villager_baker", Vector3(-4.0, 0, -26.0), PI - 0.3, "Walk"],
		["villager_woman_b", Vector3(0.4, 0, -29.0), 0.1, "Walk"],
		["villager_man_b", Vector3(5.6, 0, -33.0), PI, "Walk"],
	]
	for f in folk:
		var m := Assets.mh_character(f[0], 1.68 if f[0].contains("woman") else 1.76)
		m.set_meta("role", "villager")
		m.position = f[1]
		m.rotation.y = f[2]
		m.set_meta("blob", 0.5)
		add_child(m)
		_walk(m, f[3], _rng.randf())
	# guards with spears
	for gp in [[Vector3(6.0, 0, -6.0), 0.45], [Vector3(7.0, 0, -11.5), 0.2], [Vector3(-3.4, 0, -44.0), -0.2], [Vector3(3.4, 0, -44.0), 0.2]]:
		var g := Assets.mh_character("res://assets/incoming/ai3d/meshy/armored/guard", 1.85)
		g.set_meta("role", "guard")
		g.position = gp[0]
		g.rotation.y = gp[1] + (PI if gp[0].z < -40.0 else 0.0)
		g.set_meta("blob", 0.6)
		add_child(g)
		_walk(g, "Idle", 0.2)
		var sp := _spear()
		sp.position = gp[0] + Vector3(0.45, 0, 0.1).rotated(Vector3.UP, g.rotation.y)
		add_child(sp)


func _spear() -> Node3D:
	var root := Node3D.new()
	root.set_meta("role", "wood")
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 2.6
	cm.radial_segments = 6
	cm.rings = 1
	shaft.mesh = cm
	shaft.position.y = 1.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.24, 0.13)
	mat.roughness = 0.9
	shaft.material_override = mat
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.06
	hm.height = 0.3
	hm.radial_segments = 4
	hm.rings = 1
	head.mesh = hm
	head.position.y = 2.7
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.75, 0.77, 0.8)
	hmat.metallic = 0.8
	hmat.roughness = 0.35
	head.material_override = hmat
	root.add_child(head)
	root.set_meta("role", "")
	return root


func _walk(m: Node3D, clip: String, t: float) -> void:
	var ap := Assets.animation_player(m)
	if ap and ap.has_animation(clip):
		ap.play(clip)
		ap.advance(t)


# --- the gatehouse ----------------------------------------------------------------------------------------------

func _gatehouse(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Gatehouse"
	root.position = at
	root.scale = Vector3.ONE * 1.2
	add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_gate := 9.0
	var wall_h := 12.0
	var depth := 5.0
	var arch_w := 4.4
	var arch_spring := 5.4
	# front + back faces with the arch opening (polygon, then extruded as a tunnel)
	var poly := PackedVector2Array([Vector2(-half_gate, 0), Vector2(-arch_w, 0), Vector2(-arch_w, arch_spring)])
	var arc := 14
	for i in range(1, arc):
		var a := PI - PI * float(i) / arc
		poly.append(Vector2(cos(a) * arch_w, arch_spring + sin(a) * (arch_w * 1.2)))
	poly.append(Vector2(arch_w, arch_spring))
	poly.append(Vector2(arch_w, 0))
	poly.append(Vector2(half_gate, 0))
	poly.append(Vector2(half_gate, wall_h))
	poly.append(Vector2(-half_gate, wall_h))
	var idx := Geometry2D.triangulate_polygon(poly)
	for face in [[0.0, 1.0], [-depth, -1.0]]:      # z of the face, normal sign
		for k in range(0, idx.size(), 3):
			for j in ([2, 1, 0] if face[1] > 0.0 else [0, 1, 2]):
				var pt := poly[idx[k + j]]
				st.set_normal(Vector3(0, 0, face[1]))
				st.add_vertex(Vector3(pt.x, pt.y, face[0]))
	# tunnel walls along the opening, normals toward the passage
	var open: Array[Vector2] = []
	for i in range(1, poly.size() - 6):
		pass
	var tunnel_pts: Array[Vector2] = [Vector2(-arch_w, 0), Vector2(-arch_w, arch_spring)]
	for i in range(1, arc):
		var a2 := PI - PI * float(i) / arc
		tunnel_pts.append(Vector2(cos(a2) * arch_w, arch_spring + sin(a2) * (arch_w * 1.2)))
	tunnel_pts.append(Vector2(arch_w, arch_spring))
	tunnel_pts.append(Vector2(arch_w, 0))
	for i in tunnel_pts.size() - 1:
		var p0 := tunnel_pts[i]
		var p1 := tunnel_pts[i + 1]
		var edge := p1 - p0
		var nrm := Vector3(-edge.y, edge.x, 0).normalized()
		for v in [Vector3(p0.x, p0.y, 0), Vector3(p1.x, p1.y, 0), Vector3(p0.x, p0.y, -depth), Vector3(p1.x, p1.y, 0), Vector3(p1.x, p1.y, -depth), Vector3(p0.x, p0.y, -depth)]:
			st.set_normal(nrm)
			st.add_vertex(v)
	# walkway slab on top of the gate block
	_box(st, Vector3(0, wall_h - 0.1, -depth * 0.5), Vector3(half_gate * 2, 0.3, depth), false, false)
	# crenellated parapet on the gate and the flanking curtain walls
	_crenels(st, Vector3(-half_gate, wall_h, -depth * 0.5), Vector3(half_gate, wall_h, -depth * 0.5), depth, 1.5, 1.3)
	for sgn in [-1.0, 1.0]:
		var x0: float = sgn * 17.0
		var x1: float = sgn * 56.0
		_box(st, Vector3((x0 + x1) * 0.5, 3.75, -depth * 0.5 + 0.0), Vector3(absf(x1 - x0), 7.5, depth), false, false)
		_crenels(st, Vector3(minf(x0, x1), 7.5, -depth * 0.5), Vector3(maxf(x0, x1), 7.5, -depth * 0.5), depth, 1.5, 1.2)
	# the two round towers (own surfaces: SurfaceTool.append_from does not mix with hand-built triangles)
	var tst := SurfaceTool.new()
	tst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sgn in [-1.0, 1.0]:
		var cx: float = sgn * 11.2
		var cyl := CylinderMesh.new()
		cyl.top_radius = 5.0
		cyl.bottom_radius = 5.3
		cyl.height = 17.0
		cyl.radial_segments = 20
		cyl.rings = 1
		var tmi := MeshInstance3D.new()
		tmi.mesh = cyl
		tmi.position = Vector3(cx, 8.5, -depth * 0.5)
		tmi.set_meta("role", "gate_stone")
		root.add_child(tmi)
		var cap := CylinderMesh.new()
		cap.top_radius = 5.8
		cap.bottom_radius = 5.1
		cap.height = 1.3
		cap.radial_segments = 20
		cap.rings = 1
		var cmi := MeshInstance3D.new()
		cmi.mesh = cap
		cmi.position = Vector3(cx, 17.65, -depth * 0.5)
		cmi.set_meta("role", "gate_stone")
		root.add_child(cmi)
		for k in 16:
			var a3 := TAU * k / 16.0
			_box_at(tst, Vector3(cx + cos(a3) * 5.45, 19.0, -depth * 0.5 + sin(a3) * 5.45), Vector3(1.75, 1.5, 1.2), a3)
		for lvl in [6.5, 11.0, 14.5]:
			for k in 3:
				var a4 := PI * 0.5 + (k - 1) * 0.6
				_box_at(tst, Vector3(cx + cos(a4) * 5.2, lvl, -depth * 0.5 + sin(a4) * 5.2), Vector3(0.35, 1.2, 0.3), a4)
	var tmesh := MeshInstance3D.new()
	tmesh.mesh = tst.commit()
	tmesh.set_meta("role", "gate_stone")
	root.add_child(tmesh)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("role", "gate_stone")
	root.add_child(mi)
	# portcullis: raised, bars visible high in the arch
	var pc := SurfaceTool.new()
	pc.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 9:
		_box(pc, Vector3(-arch_w + 0.5 + k * (arch_w * 2 - 1.0) / 8.0, 8.0, -1.1), Vector3(0.14, 3.0, 0.14), false, false)
	for r in 4:
		_box(pc, Vector3(0, 6.7 + r * 0.85, -1.1), Vector3(arch_w * 2 - 0.4, 0.12, 0.14), false, false)
	var pmi := MeshInstance3D.new()
	pmi.mesh = pc.commit()
	pmi.set_meta("role", "iron")
	root.add_child(pmi)
	# red lion banners and flags
	for b in [[Vector3(-6.4, 9.0, 0.12), 5.2], [Vector3(6.4, 9.0, 0.12), 5.2], [Vector3(0, 11.2, 0.12), 3.0]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.3, b[1]) if b[1] > 4 else Vector2(1.6, b[1])
		q.mesh = qm
		q.position = b[0] + Vector3(0, -float(b[1]) * 0.5, 0)
		q.set_meta("role", "banner")
		q.set_meta("lion", true)
		root.add_child(q)
	for fp in [Vector3(-11.2, 22.0, -2.5), Vector3(11.2, 22.0, -2.5), Vector3(-5, 15.0, -2.5), Vector3(5, 15.0, -2.5), Vector3(0, 15.2, -2.5)]:
		var pole := MeshInstance3D.new()
		pole.set_meta('role', 'wood')
		var pcm := CylinderMesh.new()
		pcm.top_radius = 0.05
		pcm.bottom_radius = 0.07
		pcm.height = 5.0
		pcm.radial_segments = 5
		pcm.rings = 1
		pole.mesh = pcm
		pole.position = fp
		pole.set_meta("role", "wood")
		root.add_child(pole)
		var flag := MeshInstance3D.new()
		var fm := QuadMesh.new()
		fm.size = Vector2(2.2, 1.2)
		flag.mesh = fm
		flag.position = fp + Vector3(1.15, 1.6, 0)
		flag.rotation.y = 0.0
		flag.set_meta("role", "flag")
		root.add_child(flag)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, _unused: bool, _top: bool) -> void:
	_box_at(st, c, s, 0.0)


static func _box_at(st: SurfaceTool, c: Vector3, s: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, -yaw - PI * 0.5) if yaw != 0.0 else Basis.IDENTITY
	var h := s * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.FORWARD, [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.BACK, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
	]
	for f in faces:
		var n: Vector3 = b * (f[0] as Vector3)
		var q: Array = f[1]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(c + b * (q[k] as Vector3))


static func _crenels(st: SurfaceTool, a: Vector3, b: Vector3, depth: float, merlon: float, h: float) -> void:
	var len := absf(b.x - a.x)
	var n := int(len / (merlon * 2.0))
	for i in n:
		var x := a.x + merlon * 0.5 + i * merlon * 2.0 + merlon * 0.5
		_box_at(st, Vector3(x, a.y + h * 0.5, a.z), Vector3(merlon, h, depth), 0.0)
