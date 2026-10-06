extends RefCounted
## TorchProps: braziers and wall torches for towns, made of ONE merged emissive mesh each (iron surface lit, fire
## surface unlit/emissive) and NO omni light: the flicker comes from LampGlow's billboard batch.
##
##   TorchProps.brazier(root, pos, yaw := 0.0) -> Dictionary {node, glow_pos}   freestanding fire bowl, 1.1 m
##   TorchProps.wall_torch(root, pos, yaw := 0.0) -> Dictionary                 bracket torch, 0.9 m
## The returned glow_pos is the world position for a LampGlow.build() spec so the caller can batch the glows.

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}


static func _iron_mat() -> StandardMaterial3D:
	if not _mats.has("iron"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.17, 0.15)
		m.roughness = 0.8
		m.metallic = 0.4
		_mats["iron"] = m
	return _mats["iron"]


static func _flame_mat(kind: String) -> ShaderMaterial:
	if not _mats.has("flame_" + kind):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/brazier_fire.gdshader")
		m.set_shader_parameter("flipbook", load("res://assets/vfx/flipbooks/flame_loop.png"))
		_mats["flame_" + kind] = m
	return _mats["flame_" + kind]


static func _coal_mat() -> StandardMaterial3D:
	if not _mats.has("coal"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.08, 0.05)
		m.roughness = 0.9
		m.emission_enabled = true
		m.emission = Color(1.0, 0.32, 0.08)
		m.emission_energy_multiplier = 1.4
		_mats["coal"] = m
	return _mats["coal"]


static func _fire_mat() -> StandardMaterial3D:
	if not _mats.has("fire"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.62, 0.22)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.15)
		m.emission_energy_multiplier = 2.0
		_mats["fire"] = m
	return _mats["fire"]


static func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D) -> void:
	st.append_from(prim, 0, xf)


static func _low() -> bool:
	var ml := Engine.get_main_loop()
	var q: Node = (ml as SceneTree).root.get_node_or_null("Quality") if ml is SceneTree else null
	return q != null and int(q.get("tier")) <= 0


static func _flame_quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


static func _cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## kind: "brazier" | "wall_torch" -> ArrayMesh with surface 0 = iron, surface 1 = fire.
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fire := SurfaceTool.new()
	fire.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coals := SurfaceTool.new()
	coals.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "brazier":
		# AAA pass 2026-10-06: a wrought fire basket instead of a cylinder and a flat yellow cone. Flared bowl with a rolled
		# rim and straps, three curved legs with splayed feet and a tie ring, a heap of glowing coals and five crossed flame
		# tongues (gradient + sway in brazier_fire.gdshader). Still one mesh, three surfaces, no light.
		_add(iron, _cyl(0.34, 0.17, 0.22, 12), Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))       # bowl
		_add(iron, _cyl(0.07, 0.17, 0.08, 12), Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0)))      # bowl foot
		var rim := TorusMesh.new()
		rim.inner_radius = 0.33
		rim.outer_radius = 0.38
		rim.rings = 16
		rim.ring_segments = 6
		_add(iron, rim, Transform3D(Basis.IDENTITY, Vector3(0, 0.91, 0)))
		for i in 6:      # vertical straps round the bowl
			var a := TAU * i / 6.0
			var strap := BoxMesh.new()
			strap.size = Vector3(0.035, 0.24, 0.02)
			_add(iron, strap, Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, -0.62), Vector3(cos(a), 0, sin(a)) * 0.27 + Vector3(0, 0.8, 0)))
		for i in 3:
			var a := TAU * i / 3.0 + 0.5
			var out := Vector3(cos(a), 0, sin(a))
			var axis := Vector3(-sin(a), 0, cos(a))
			_add(iron, _cyl(0.028, 0.034, 0.42, 6), Transform3D(Basis(axis, -0.32), out * 0.2 + Vector3(0, 0.52, 0)))   # upper leg
			_add(iron, _cyl(0.034, 0.03, 0.34, 6), Transform3D(Basis(axis, -0.05), out * 0.27 + Vector3(0, 0.17, 0)))   # lower leg
			_add(iron, _cyl(0.06, 0.07, 0.03, 8), Transform3D(Basis.IDENTITY, out * 0.28 + Vector3(0, 0.015, 0)))        # foot
		var ring := TorusMesh.new()
		ring.inner_radius = 0.2
		ring.outer_radius = 0.235
		ring.rings = 14
		ring.ring_segments = 5
		_add(iron, ring, Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0)))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 11:     # coal heap
			var lump := SphereMesh.new()
			lump.radius = rng.randf_range(0.06, 0.1)
			lump.height = lump.radius * 1.4
			lump.radial_segments = 6
			lump.rings = 3
			var r := sqrt(rng.randf()) * 0.22
			var t := rng.randf() * TAU
			_add(coals, lump, Transform3D(Basis.IDENTITY, Vector3(cos(t) * r, 0.9 + (0.22 - r) * 0.35, sin(t) * r)))
		_add(fire, _flame_quad(Vector2(0.78, 1.0)), Transform3D(Basis.IDENTITY, Vector3(0, 0.86 + 0.5, 0)))   # flipbook billboard
	else:
		_add(iron, _cyl(0.025, 0.025, 0.5, 6), Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3(0, 0.35, 0.0)))   # stick
		_add(iron, _cyl(0.07, 0.04, 0.12, 6), Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)))   # cup
		_add(iron, _cyl(0.02, 0.02, 0.3, 5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.3, 0.14)))   # wall bracket
		_add(fire, _flame_quad(Vector2(0.34, 0.46)), Transform3D(Basis.IDENTITY, Vector3(0, 0.64 + 0.23, 0)))
	var am := iron.commit()
	fire.commit(am)
	am.surface_set_material(0, _iron_mat())
	am.surface_set_material(1, _flame_mat(kind))
	if kind == "brazier" and not _low():
		coals.commit(am)
		am.surface_set_material(2, _coal_mat())     # LOW: 2 surfaces, no coal heap (pass 12 draw census: 3 draws per brazier)
	_meshes[kind] = am
	return am


static func _place(root: Node3D, kind: String, pos: Vector3, yaw: float, glow_y: float) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [kind, root.get_child_count()]      # unique, keeps the kind as prefix (a second "wall_torch" under one root was auto-renamed to @MeshInstance3D@N and lost its name in the world lint)
	mi.mesh = mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw
	return {"node": mi, "glow_pos": pos + Vector3(0, glow_y, 0)}


static func brazier(root: Node3D, pos: Vector3, yaw := 0.0) -> Dictionary:
	return _place(root, "brazier", pos, yaw, 1.2)


static func wall_torch(root: Node3D, pos: Vector3, yaw := 0.0) -> Dictionary:
	return _place(root, "wall_torch", pos, yaw, 0.95)
