extends RefCounted
const StyleG := preload("res://scripts/style_g.gd")

## Draw-call cut for multi-surface meshes on LOW/MEDIUM (HIGH folds everything but the lit windows/lamps of the near LOD0 stage (keep_extras)): surfaces are folded into the MAIN surface
## (the biggest Style G material) so a house / prop is ONE surface = one draw (and one shadow draw) per LOD stage.
## Folded surfaces:
##  1. kept-material extras (lit window, lamp, glass, water: 1-14 triangles): UV = brightest texel of the atlas,
##     COLOR = target tint (warm patch / dark glass / water; no emissive glow on these tiers).
##  2. styled surfaces with the SAME atlas texture and shader (role parameters differ only): copied as they are;
##     if their albedo_color differs (town-tinted bunting, laundry, awnings), the colour is baked into the vertex colour
##     and the main material becomes a white-colour copy (cached).
##  3. small styled surfaces (<= SMALL_VERTS) with ANOTHER texture (iron/timber/canvas bits of a prop pile): flattened to
##     the texture's average colour (UV = brightest texel of the main atlas, COLOR = target / texel).
## Sets meta "orig_surfaces" so callers that cap by surface count (district_props LOW_MAX_SURFACES) keep their decision.

const SMALL_VERTS := 400

static var _bright_uv := {}       # material id -> Vector2 (uv of the brightest texel)
static var _bright_col := {}      # material id -> Color (linear colour of that texel)
static var _avg := {}             # texture id -> Color (sRGB average)
static var _white_copy := {}      # material id -> ShaderMaterial (albedo_color white)


static func collapse(mesh: ArrayMesh, tier: String, keep_extras := false) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() < 2 or mesh.has_meta("surf_collapsed"):
		return mesh
	var main := -1
	var main_n := -1
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is ShaderMaterial and StyleG.is_styled(m):
			var n := mesh.surface_get_array_len(i)
			if n > main_n:
				main_n = n
				main = i
	if main < 0:
		return mesh
	var main_mat := mesh.surface_get_material(main) as ShaderMaterial
	var base: Array = mesh.surface_get_arrays(main)
	if base[Mesh.ARRAY_TEX_UV] == null or base[Mesh.ARRAY_COLOR] == null or base[Mesh.ARRAY_INDEX] == null:
		return mesh
	# plan: surface index -> kind (0 kept extra, 1 same atlas, 2 flatten)
	var plan := {}
	var recolor := false
	var main_tex: Variant = main_mat.get_shader_parameter("albedo_tex")
	for i in mesh.get_surface_count():
		var fm := mesh.surface_get_material(i)
		if i == main or fm == null or mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(i)
		if arr[Mesh.ARRAY_INDEX] == null:
			continue
		if not StyleG.is_styled(fm):
			if keep_extras:
				continue            # HIGH near stage: lit windows and lamps keep their own emissive material
			plan[i] = 0
			continue
		var sm := fm as ShaderMaterial
		if sm.shader != main_mat.shader or sm.get_shader_parameter("use_vertex_color") != main_mat.get_shader_parameter("use_vertex_color") \
				or sm.get_shader_parameter("vcol_srgb") != main_mat.get_shader_parameter("vcol_srgb") \
				or sm.get_shader_parameter("uv_scale") != main_mat.get_shader_parameter("uv_scale"):
			continue
		if arr[Mesh.ARRAY_TEX_UV] == null or arr[Mesh.ARRAY_COLOR] == null:
			continue
		if sm.get_shader_parameter("albedo_tex") == main_tex:
			plan[i] = 1
			if sm.get_shader_parameter("albedo_color") != main_mat.get_shader_parameter("albedo_color"):
				recolor = true
		elif mesh.surface_get_array_len(i) <= SMALL_VERTS and sm.get_shader_parameter("alpha_cut") in [null, 0.0]:
			plan[i] = 2
	if plan.is_empty():
		return mesh
	var main_srgb: bool = bool(main_mat.get_shader_parameter("vcol_srgb")) if main_mat.get_shader_parameter("vcol_srgb") != null else true
	var out_mat: ShaderMaterial = _white(main_mat) if recolor else main_mat
	var uv0: Vector2 = _brightest(main_mat)
	var texel: Color = _bright_col.get(main_mat.get_instance_id(), Color.WHITE)
	if not recolor and main_mat.get_shader_parameter("albedo_color") != null:
		texel = texel * (main_mat.get_shader_parameter("albedo_color") as Color).srgb_to_linear()
	var v: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = base[Mesh.ARRAY_NORMAL] if base[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uv: PackedVector2Array = base[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = base[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = base[Mesh.ARRAY_INDEX]
	if recolor:
		_bake(col, main_mat.get_shader_parameter("albedo_color"), main_srgb)
	for i in plan:
		var a := mesh.surface_get_arrays(i)
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var fm := mesh.surface_get_material(i)
		var off := v.size()
		v.append_array(av)
		if not nrm.is_empty():
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			an.resize(av.size())
			nrm.append_array(an)
		var kind: int = plan[i]
		if kind == 1:
			uv.append_array(a[Mesh.ARRAY_TEX_UV])
			var c1: PackedColorArray = a[Mesh.ARRAY_COLOR]
			if recolor:
				c1 = c1.duplicate()
				_bake(c1, (fm as ShaderMaterial).get_shader_parameter("albedo_color"), main_srgb)
			col.append_array(c1)
		else:
			var tint: Color
			if kind == 0:
				tint = _tint_for(fm)
			else:
				tint = _flat_tint(fm as ShaderMaterial, texel, main_srgb)
			var own: PackedColorArray = a[Mesh.ARRAY_COLOR] if (kind == 2 and a[Mesh.ARRAY_COLOR] != null) else PackedColorArray()
			for k in av.size():
				uv.append(uv0)
				var t := tint
				if kind == 2 and not own.is_empty():
					t = Color(tint.r * own[k].r, tint.g * own[k].g, tint.b * own[k].b, own[k].a)
				col.append(t)
		for ix in a[Mesh.ARRAY_INDEX] as PackedInt32Array:
			idx.append(ix + off)
	base[Mesh.ARRAY_VERTEX] = v
	if not nrm.is_empty():
		base[Mesh.ARRAY_NORMAL] = nrm
	base[Mesh.ARRAY_TEX_UV] = uv
	base[Mesh.ARRAY_COLOR] = col
	base[Mesh.ARRAY_INDEX] = idx
	base[Mesh.ARRAY_TANGENT] = null
	var keep: Array = []
	for i in mesh.get_surface_count():
		if i == main:
			keep.append([base, out_mat])
		elif not plan.has(i):
			keep.append([mesh.surface_get_arrays(i), mesh.surface_get_material(i)])
	var aabb := mesh.get_aabb()
	var orig := mesh.get_surface_count()
	mesh.clear_surfaces()
	for k in keep:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, k[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, k[1])
	mesh.custom_aabb = aabb
	mesh.set_meta("surf_collapsed", true)
	mesh.set_meta("orig_surfaces", maxi(orig, int(mesh.get_meta("orig_surfaces", 0))))
	return mesh


static func _white(m: ShaderMaterial) -> ShaderMaterial:
	var id := m.get_instance_id()
	if not _white_copy.has(id):
		var c := m.duplicate() as ShaderMaterial
		c.set_shader_parameter("albedo_color", Color.WHITE)
		c.set_meta("g_src", m.get_meta("g_src"))
		_white_copy[id] = c
	return _white_copy[id]


static func _bake(col: PackedColorArray, ac: Color, srgb: bool) -> void:
	for k in col.size():
		col[k] = _baked(col[k], ac, srgb)


static func _baked(c: Color, ac: Color, srgb: bool) -> Color:
	var m := ac if srgb else ac.srgb_to_linear()
	return Color(c.r * m.r, c.g * m.g, c.b * m.b, c.a)


## Stored vertex colour that makes (atlas texel x vertex colour x albedo_color) of the main material show the folded
## surface's own flat average colour.
static func _flat_tint(sm: ShaderMaterial, texel: Color, srgb: bool) -> Color:
	var tex := sm.get_shader_parameter("albedo_tex") as Texture2D
	var avg := _average(tex)
	var ac: Color = sm.get_shader_parameter("albedo_color") if sm.get_shader_parameter("albedo_color") != null else Color.WHITE
	var target := Color(avg.r * ac.r, avg.g * ac.g, avg.b * ac.b).srgb_to_linear()
	var lin := Color(minf(target.r / maxf(texel.r, 0.02), 1.0), minf(target.g / maxf(texel.g, 0.02), 1.0), minf(target.b / maxf(texel.b, 0.02), 1.0))
	return lin.linear_to_srgb() if srgb else lin


static func _average(tex: Texture2D) -> Color:
	if tex == null:
		return Color.WHITE
	var id := tex.get_instance_id()
	if _avg.has(id):
		return _avg[id]
	var c := Color(0.6, 0.6, 0.6)
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
		var r := 0.0
		var g := 0.0
		var b := 0.0
		for y in 4:
			for x in 4:
				var p := img.get_pixel(x, y)
				r += p.r
				g += p.g
				b += p.b
		c = Color(r / 16.0, g / 16.0, b / 16.0)
	_avg[id] = c
	return c


static func _tint_for(m: Material) -> Color:
	var n := m.resource_name.to_lower() if m != null else ""
	if n.contains("water"):
		return Color(0.30, 0.42, 0.46, 1.0)
	if n.contains("glass"):
		return Color(0.22, 0.27, 0.34, 1.0)
	return Color(1.0, 0.80, 0.45, 1.0)           # lit window / lamp: warm patch


static func _brightest(sm: ShaderMaterial) -> Vector2:
	var id := sm.get_instance_id()
	if _bright_uv.has(id):
		return _bright_uv[id]
	var best := Vector2(0.5, 0.5)
	var bc := Color.WHITE
	var tex := sm.get_shader_parameter("albedo_tex") as Texture2D
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var w := img.get_width()
			var h := img.get_height()
			var bl := -1.0
			for gy in 16:
				for gx in 16:
					var c := img.get_pixel(int((gx + 0.5) / 16.0 * w), int((gy + 0.5) / 16.0 * h))
					var l := c.r + c.g + c.b
					if l > bl:
						bl = l
						best = Vector2((gx + 0.5) / 16.0, (gy + 0.5) / 16.0)
						bc = c
	_bright_uv[id] = best
	_bright_col[id] = bc.srgb_to_linear()
	return best
