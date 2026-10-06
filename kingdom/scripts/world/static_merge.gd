extends RefCounted
## Baked quality phase 2 (2026-10-06): static merge of a streamed town's SMALL-prop MultiMesh batches.
## SettlementBuilder emits one MultiMeshInstance3D per model per cell (+ LOD stage): a market street is 40+ kinds, each its own
## draw call (and again in the shadow pass). This pass concatenates every small-prop batch in the same cell with the same
## visibility range / shadow mode into ONE ArrayMesh with one surface per distinct CANONICAL material:
##   - albedo_color is baked into vertex colour and the material becomes a shared white-colour copy, so flat-colour props of
##     different colours (notice boards, flower beds, braziers, shields...) share one material per look;
##   - COLOR = baked vertex colour x albedo_color x MultiMesh instance colour (town tints, quantised to 1/24 for the variant cache);
##   - UV2.x = vertex height above the instance origin (the polished shaders' contact-AO ramp used MODEL_MATRIX, now identity).
## Only batches whose model is <= MAX_INST_VERTS vertices merge (geometry is copied per instance: buildings stay MultiMesh).
## Geometry is appended natively by SurfaceTool.append_from, time-sliced by the caller (step()).
## Opt out per node with meta "keep" (breakables hide single instances of their MultiMesh). NO_STATIC_MERGE=1 disables the pass.

const CELL := 40.0
const MAX_VERTS := 60000            # per merged mesh
const MAX_INST_VERTS := 1500        # per-instance vertices above which a plain prop batch stays a MultiMesh
const MAX_ATLAS_VERTS := 6000       # far building stages on the shared texture page merge up to this size
const POLISHED_FLAG := "uv2_base"   # uniform that marks shaders patched for merged meshes
const SKIP_PARAMS := ["albedo_color", "use_vertex_color", "vcol_srgb", POLISHED_FLAG]
const SKIP_PROPS := ["albedo_color", "vertex_color_use_as_albedo", "vertex_color_is_srgb", "resource_name", "resource_path", "resource_local_to_scene"]

static var enabled := not OS.has_environment("NO_STATIC_MERGE")
static var stats := {"jobs": 0, "groups": 0, "members": 0, "meshes": 0, "verts": 0, "ms": 0.0}

static var _var := {}        # "mesh:surface:mat:tint" -> one-surface ArrayMesh (UV2 height, baked COLOR)
static var _info := {}       # source material instance id -> {mat, col, srgb, src_vc}
static var _canon := {}      # look signature -> canonical material
static var _ok := {}         # material instance id -> bool


## Plan a merge of every eligible MultiMeshInstance3D below `root`. Returns a job for step(), or {} when there is nothing to do.
static func begin(root: Node3D) -> Dictionary:
	# LOW only: on HIGH the merge copies geometry (+90 MB, +1 s CPU) for ~4 % fewer draws; on LOW it cuts draws ~25 %.
	if not enabled or root == null or preload("res://scripts/style_g.gd").current_tier() != "low":
		return {}
	var by_key := {}
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if not _eligible(mmi):
			continue
		var c := mmi.multimesh.get_aabb().get_center()
		var key := "%d|%d,%d|%d|%d|%.1f|%.1f|%.1f|%.1f|%d|%d" % [mmi.get_parent().get_instance_id(), floori(c.x / CELL), floori(c.z / CELL),
			mmi.cast_shadow, mmi.layers, mmi.visibility_range_begin, mmi.visibility_range_begin_margin, mmi.visibility_range_end,
			mmi.visibility_range_end_margin, mmi.visibility_range_fade_mode, mmi.gi_mode]
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(mmi)
	var groups: Array = []
	for k in by_key:
		var cur: Array = []
		var verts := 0
		for m: MultiMeshInstance3D in by_key[k]:
			var v := m.multimesh.instance_count * _mesh_verts(m.multimesh.mesh as ArrayMesh)
			if verts + v > MAX_VERTS and not cur.is_empty():
				if cur.size() >= 2:
					groups.append(cur)
				cur = []
				verts = 0
			cur.append(m)
			verts += v
		if cur.size() >= 2:
			groups.append(cur)
	stats["jobs"] += 1
	return {"groups": groups, "i": 0}


## Merge groups until `budget_ms` is spent (0 = no limit). True when the job is finished (or empty).
static func step(job: Dictionary, budget_ms: float) -> bool:
	if job.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	var groups: Array = job["groups"]
	while job["i"] < groups.size():
		_merge_group(groups[job["i"]])
		job["i"] += 1
		if budget_ms > 0.0 and (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	stats["ms"] += (Time.get_ticks_usec() - t0) / 1000.0
	return job["i"] >= groups.size()


## Everything at once (sync builds, tests).
static func merge_now(root: Node3D) -> void:
	step(begin(root), 0.0)


static func _mesh_verts(mesh: ArrayMesh) -> int:
	var n := 0
	for si in mesh.get_surface_count():
		n += mesh.surface_get_array_len(si)
	return n


static func _eligible(mmi: MultiMeshInstance3D) -> bool:
	if not is_instance_valid(mmi) or mmi.multimesh == null or mmi.has_meta("keep") or mmi.get_script() != null:
		return false
	if not mmi.visible or mmi.transform != Transform3D.IDENTITY or mmi.get_parent() == null:
		return false
	var mm := mmi.multimesh
	if mm.transform_format != MultiMesh.TRANSFORM_3D or mm.use_custom_data or mm.instance_count <= 0:
		return false
	if mm.visible_instance_count >= 0 and mm.visible_instance_count != mm.instance_count:
		return false
	var mesh := mm.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0 or mmi.custom_aabb.size != Vector3.ZERO:
		return false
	if not mesh.has_meta("atlas"):      # plain props merged too in testing: black wall-window patches for 7 draws, so atlas stages only
		return false
	if _mesh_verts(mesh) > (MAX_ATLAS_VERTS if mesh.has_meta("atlas") else MAX_INST_VERTS):
		return false
	for si in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var m: Material = mmi.material_override if mmi.material_override else mesh.surface_get_material(si)
		if not _material_ok(m):
			return false
		var fmt := mesh.surface_get_format(si)
		if (fmt & Mesh.ARRAY_FORMAT_VERTEX) == 0 or (fmt & Mesh.ARRAY_FORMAT_NORMAL) == 0 or (fmt & Mesh.ARRAY_FORMAT_BONES) != 0:
			return false
	return true


static func _material_ok(m: Material) -> bool:
	if m == null:
		return false
	var id := m.get_instance_id()
	if _ok.has(id):
		return _ok[id]
	var ok := true
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		ok = b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS \
			and b.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and not b.normal_enabled and not b.heightmap_enabled \
			and not b.uv1_triplanar and not b.grow and not b.emission_enabled
	elif m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			ok = false
		elif sh.resource_path.ends_with("contact_shadow.gdshader"):
			ok = true
		else:
			var code := sh.code
			ok = code.contains(POLISHED_FLAG) or not (code.contains("MODEL_MATRIX") or code.contains("INSTANCE_") or code.contains("NODE_POSITION")
				or code.contains("ALPHA =") or code.contains("ALPHA=") or code.contains("VERTEX +=") or code.contains("VERTEX ="))
	else:
		ok = false
	_ok[id] = ok
	return ok


## Canonical material of `m` plus how to bake what it dropped into vertex colour:
## {mat, col (albedo_color to bake), srgb (vertex colours are sRGB-coded), src_vc (the source read COLOR)}.
static func _material_info(m: Material) -> Dictionary:
	var id := m.get_instance_id()
	if _info.has(id):
		return _info[id]
	var info := {"mat": m, "col": Color.WHITE, "srgb": true, "src_vc": true}
	if m is ShaderMaterial and (m as ShaderMaterial).shader and (m as ShaderMaterial).shader.code.contains(POLISHED_FLAG):
		var sm := m as ShaderMaterial
		var src_vc := bool(sm.get_shader_parameter("use_vertex_color")) if sm.get_shader_parameter("use_vertex_color") != null else false
		var srgb := bool(sm.get_shader_parameter("vcol_srgb")) if sm.get_shader_parameter("vcol_srgb") != null else false
		if not src_vc:
			srgb = true
		var col: Color = sm.get_shader_parameter("albedo_color") if sm.get_shader_parameter("albedo_color") != null else Color.WHITE
		var sig := "sm|%d|%d" % [sm.shader.get_instance_id(), int(srgb)]
		for u: Dictionary in sm.shader.get_shader_uniform_list():
			var n: String = u["name"]
			if n in SKIP_PARAMS:
				continue
			sig += "|%s=%s" % [n, _sig_value(sm.get_shader_parameter(n))]
		if not _canon.has(sig):
			var d := sm.duplicate() as ShaderMaterial
			for k in sm.get_meta_list():
				d.set_meta(k, sm.get_meta(k))
			d.set_shader_parameter("albedo_color", Color.WHITE)
			d.set_shader_parameter("use_vertex_color", true)
			d.set_shader_parameter("vcol_srgb", srgb)
			d.set_shader_parameter(POLISHED_FLAG, true)
			_canon[sig] = d
		info = {"mat": _canon[sig], "col": col, "srgb": srgb, "src_vc": src_vc}
	elif m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var src_vc := b.vertex_color_use_as_albedo
		var srgb := b.vertex_color_is_srgb if src_vc else true
		var sig := "bm|%d" % int(srgb)
		for p: Dictionary in b.get_property_list():
			if (int(p["usage"]) & PROPERTY_USAGE_STORAGE) == 0 or String(p["name"]) in SKIP_PROPS:
				continue
			sig += "|%s=%s" % [p["name"], _sig_value(b.get(p["name"]))]
		if not _canon.has(sig):
			var d := b.duplicate() as BaseMaterial3D
			d.albedo_color = Color.WHITE
			d.vertex_color_use_as_albedo = true
			d.vertex_color_is_srgb = srgb
			_canon[sig] = d
		info = {"mat": _canon[sig], "col": b.albedo_color, "srgb": srgb, "src_vc": src_vc}
	_info[id] = info
	return info


static func _sig_value(v: Variant) -> String:
	if v is Resource:
		var r := v as Resource
		return r.resource_path if r.resource_path != "" else str(r.get_instance_id())
	return str(v)


## One-surface ArrayMesh of a source surface with UV2.x = local vertex height and COLOR = vertex x albedo x tint, cached per
## (mesh, surface, material, tint): SurfaceTool.append_from then transforms and appends it natively per instance.
static func _variant(mesh: ArrayMesh, si: int, info: Dictionary, tint: Color) -> ArrayMesh:
	var key := "%d:%d:%d:%s" % [mesh.get_instance_id(), si, (info["mat"] as Material).get_instance_id(), tint.to_html(false)]
	if _var.has(key):
		return _var[key]
	var a := mesh.surface_get_arrays(si)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n := v.size()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = a[Mesh.ARRAY_NORMAL]
	var uv = a[Mesh.ARRAY_TEX_UV]
	if uv == null or (uv as PackedVector2Array).size() != n:
		var z := PackedVector2Array()
		z.resize(n)
		uv = z
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var h := PackedVector2Array()
	h.resize(n)
	for k in n:
		h[k] = Vector2(v[k].y, 0.0)
	arrays[Mesh.ARRAY_TEX_UV2] = h
	var col = a[Mesh.ARRAY_COLOR]
	var has_col: bool = bool(info["src_vc"]) and col != null and (col as PackedColorArray).size() == n
	var ac: Color = info["col"]
	var c := PackedColorArray()
	if has_col and ac == Color.WHITE and tint == Color.WHITE:
		c = col
	else:
		c.resize(n)
		var srgb: bool = info["srgb"]
		var albedo_lin := ac.srgb_to_linear()
		if not has_col:
			# flat colour: encode albedo once (a vertex-colour-reading source with no COLOR array drew white)
			var flat := Color(ac.r, ac.g, ac.b, 1.0) if srgb else albedo_lin
			c.fill(Color(flat.r * tint.r, flat.g * tint.g, flat.b * tint.b, tint.a))
		else:
			var sc: PackedColorArray = col
			for k in n:
				var s := sc[k]
				var o: Color
				if ac == Color.WHITE:
					o = s
				elif srgb:
					var l := s.srgb_to_linear()
					o = Color(l.r * albedo_lin.r, l.g * albedo_lin.g, l.b * albedo_lin.b, s.a).linear_to_srgb()
					o.a = s.a
				else:
					o = Color(s.r * albedo_lin.r, s.g * albedo_lin.g, s.b * albedo_lin.b, s.a)
				c[k] = Color(o.r * tint.r, o.g * tint.g, o.b * tint.b, o.a * tint.a)
	arrays[Mesh.ARRAY_COLOR] = c
	if a[Mesh.ARRAY_INDEX] != null:
		arrays[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_var[key] = m
	return m


static func _quant(c: Color) -> Color:
	if c == Color.WHITE:
		return c
	const Q := 24.0
	return Color(roundf(c.r * Q) / Q, roundf(c.g * Q) / Q, roundf(c.b * Q) / Q, roundf(c.a * Q) / Q)


static func _merge_group(members: Array) -> void:
	var first: MultiMeshInstance3D = members[0]
	for m in members:
		if not is_instance_valid(m):
			return
	var parent := first.get_parent()
	var tools := {}                # canonical material -> SurfaceTool
	var order: Array = []
	for mmi: MultiMeshInstance3D in members:
		var mm := mmi.multimesh
		var mesh := mm.mesh as ArrayMesh
		var sts: Array = []
		var infos: Array = []
		for si in mesh.get_surface_count():
			var base: Material = mmi.material_override if mmi.material_override else mesh.surface_get_material(si)
			var info := _material_info(base)
			var mat: Material = info["mat"]
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			sts.append(tools[mat])
			infos.append(info)
		for ii in mm.instance_count:
			var t := mm.get_instance_transform(ii)
			var tint := _quant(mm.get_instance_color(ii)) if mm.use_colors else Color.WHITE
			for si in sts.size():
				(sts[si] as SurfaceTool).append_from(_variant(mesh, si, infos[si], tint), 0, t)
	var out := ArrayMesh.new()
	var verts := 0
	for mat: Material in order:
		(tools[mat] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		verts += out.surface_get_array_len(out.get_surface_count() - 1)
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = out
	mi.cast_shadow = first.cast_shadow
	mi.layers = first.layers
	mi.gi_mode = first.gi_mode
	mi.visibility_range_begin = first.visibility_range_begin
	mi.visibility_range_begin_margin = first.visibility_range_begin_margin
	mi.visibility_range_end = first.visibility_range_end
	mi.visibility_range_end_margin = first.visibility_range_end_margin
	mi.visibility_range_fade_mode = first.visibility_range_fade_mode
	parent.add_child(mi)
	for m: MultiMeshInstance3D in members:
		m.get_parent().remove_child(m)
		m.queue_free()
	stats["groups"] += 1
	stats["members"] += members.size()
	stats["meshes"] += 1
	stats["verts"] += verts
	stats["surfaces"] = int(stats.get("surfaces", 0)) + out.get_surface_count()
	stats["canon"] = _canon.size()
