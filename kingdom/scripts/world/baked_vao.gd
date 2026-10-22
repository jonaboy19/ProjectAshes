extends RefCounted
## Baked quality (2026-10-06): offline-baked vertex AO + painterly warm/cool light for town buildings and props.
## Mobile quality comes from baking, not runtime power: the bake runs once in tools
## (`tools_qa/baked_quality/bake_town_vao.gd`), ships as tiny zstd blobs in res://assets/baked/vao/, and at load
## `Assets._transformed` writes it into COLOR. The polished shaders already multiply COLOR.rgb (vertex tint) and
## COLOR.a * vao_strength, so the look costs zero extra GPU work on every tier, including LOW (no sun shadows).
##   COLOR.a   = AO (0.35 open crease .. 1.0 fully open)
##   COLOR.rgb = painterly light: occluded -> cool shade, open + up-facing -> warm sunlit, low band -> earthy grime.
## Missing blob = mesh unchanged (never computed at runtime).

const StyleGVao := preload("res://scripts/style_g_vao.gd")
const DIR := "res://assets/baked/vao/"
# linear multipliers; written sRGB-encoded because game materials decode COLOR as sRGB (vcol_srgb)
const COOL := Color(0.74, 0.80, 0.97)
const WARM := Color(1.0, 0.95, 0.84)
const GRIME := Color(0.80, 0.72, 0.62)
const STRENGTH := 0.9

static var enabled := not OS.has_environment("NO_BAKED_VAO")
static var bake_mode := false      # tools: compute + save the blob instead of loading it


static func path_for(key: String) -> String:
	return DIR + key.replace(":", "_") + ".res"


## Surface arrays (already in final building space, base at y = 0) -> same arrays with baked COLOR.
static func apply(key: String, surfaces: Array) -> bool:
	if not enabled or key == "":
		return false
	if bake_mode:
		print("baked_vao ", key, " verts ", bake(key, surfaces))
	if not ResourceLoader.exists(path_for(key)):
		return false
	var r := load(path_for(key))
	if r == null:
		return false
	var any := false
	for si in surfaces.size():
		var blob: PackedByteArray = r.get_meta("s%d" % si, PackedByteArray())
		var a: Array = surfaces[si]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if blob.is_empty():
			continue
		var ao := blob.decompress(v.size(), FileAccess.COMPRESSION_ZSTD)
		if ao.size() != v.size():
			continue          # source mesh changed since the bake: skip rather than smear
		a[Mesh.ARRAY_COLOR] = paint(a, ao)
		any = true
	return any


static var _mats := {}


## After StyleG restyling: baked surfaces need their material to multiply COLOR.rgb. Cached duplicates per material,
## so unbaked meshes sharing the original material are untouched. Shaders without a vertex-colour switch are left alone.
static func fix_materials(mesh: ArrayMesh) -> void:
	for i in mesh.get_surface_count():
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			continue
		var m := mesh.surface_get_material(i)
		if m == null:
			continue
		var id := m.get_instance_id()
		if not _mats.has(id):
			var d: Material = null
			if m is BaseMaterial3D:
				if (m as BaseMaterial3D).vertex_color_use_as_albedo:
					d = m          # already multiplies COLOR
				else:
					d = m.duplicate()
					(d as BaseMaterial3D).vertex_color_use_as_albedo = true
					(d as BaseMaterial3D).vertex_color_is_srgb = true
			elif m is ShaderMaterial and (m as ShaderMaterial).shader and (m as ShaderMaterial).shader.code.contains("uniform bool use_vertex_color"):
				d = m.duplicate()
				for k in m.get_meta_list():
					d.set_meta(k, m.get_meta(k))
				(d as ShaderMaterial).set_shader_parameter("use_vertex_color", true)
				(d as ShaderMaterial).set_shader_parameter("vcol_srgb", true)
				(d as ShaderMaterial).set_shader_parameter("vao_strength", 0.0)     # AO already in rgb
			_mats[id] = d if d != null else m
		mesh.surface_set_material(i, _mats[id])


## AO bytes + normals/heights -> painterly vertex colours (rgb multiplies existing vertex colours).
static func paint(a: Array, ao: PackedByteArray) -> PackedColorArray:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var has_col := cols.size() == v.size()
	var out := PackedColorArray()
	out.resize(v.size())
	for i in v.size():
		var o := ao[i] / 255.0
		var up := nrm[i].y if nrm.size() == v.size() else 0.0
		var lit := clampf((o - 0.35) / 0.65 * 0.8 + maxf(up, 0.0) * 0.3, 0.0, 1.0)
		var c := COOL.lerp(WARM, lit)
		var g := 1.0 - smoothstep(0.0, 1.4, v[i].y)        # grime / damp band at the foot of walls
		c = c.lerp(c * GRIME, g * 0.4)
		c *= lerpf(1.0, o, STRENGTH)                         # AO lives in rgb: works on polished AND standard materials
		c = Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)).linear_to_srgb()
		if has_col:
			c = Color(c.r * cols[i].r, c.g * cols[i].g, c.b * cols[i].b)
		c.a = o
		out[i] = c
	return out


## Tool side: compute AO for surface arrays and save the blob.
static func bake(key: String, surfaces: Array) -> int:
	var tmp := ArrayMesh.new()
	for a in surfaces:
		var b: Array = (a as Array).duplicate()
		b[Mesh.ARRAY_COLOR] = null
		tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
	var baked := StyleGVao.baked(tmp)
	if baked == tmp:
		return 0
	var r := Resource.new()
	var n := 0
	for si in baked.get_surface_count():
		var cols: PackedColorArray = baked.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
		var bytes := PackedByteArray()
		bytes.resize(cols.size())
		for i in cols.size():
			bytes[i] = clampi(roundi(cols[i].a * 255.0), 0, 255)
		r.set_meta("s%d" % si, bytes.compress(FileAccess.COMPRESSION_ZSTD))
		n += cols.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	ResourceSaver.save(r, path_for(key), ResourceSaver.FLAG_COMPRESS)
	return n
