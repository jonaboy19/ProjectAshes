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
	if kind == "brazier":
		_add(iron, _cyl(0.36, 0.2, 0.26), Transform3D(Basis.IDENTITY, Vector3(0, 0.78, 0)))     # bowl
		for i in 3:
			var a := TAU * i / 3.0
			var leg := _cyl(0.03, 0.045, 0.7, 6)
			var off := Vector3(cos(a), 0, sin(a)) * 0.2
			var tilt := Basis(Vector3(-sin(a), 0, cos(a)), 0.18)
			_add(iron, leg, Transform3D(tilt, Vector3(off.x, 0.38, off.z)))
		_add(fire, _cyl(0.3, 0.3, 0.02, 10), Transform3D(Basis.IDENTITY, Vector3(0, 0.92, 0)))   # coals
		_add(fire, _cyl(0.0, 0.17, 0.42, 7), Transform3D(Basis.IDENTITY, Vector3(0, 1.13, 0)))    # flame
	else:
		_add(iron, _cyl(0.025, 0.025, 0.5, 6), Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3(0, 0.35, 0.0)))   # stick
		_add(iron, _cyl(0.07, 0.04, 0.12, 6), Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)))   # cup
		_add(iron, _cyl(0.02, 0.02, 0.3, 5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.3, 0.14)))   # wall bracket
		_add(fire, _cyl(0.0, 0.09, 0.28, 6), Transform3D(Basis.IDENTITY, Vector3(0, 0.82, 0)))
	var am := iron.commit()
	fire.commit(am)
	am.surface_set_material(0, _iron_mat())
	am.surface_set_material(1, _fire_mat())
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
