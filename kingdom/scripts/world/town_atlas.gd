extends RefCounted
## Baked quality phase 2: one shared texture page for the far stages of town buildings (LOD2/LOD3 and 256 px LOD1).
## tools_qa/baked_quality/bake_town_atlas.gd packs each stage's atlas texture into a 256 px tile of
## res://assets/baked/atlas/town_far.png and records the UV transform per "key:lodN" in town_atlas.json.
## At load Assets.building_mesh calls fold(): the single Style G surface gets its UVs moved into its tile and the page material
## (one per look, so houses of different kinds share a material and StaticMerge can fuse them into one draw call).
## Missing/stale entry (source texture name differs, UVs outside 0..1) = mesh untouched. TOWN_ATLAS=0 disables it.

const JSON_PATH := "res://assets/baked/atlas/town_atlas.json"

static var enabled := not OS.has_environment("NO_TOWN_ATLAS")
static var _data: Dictionary = {}
static var _loaded := false
static var _page: Texture2D
static var _mats := {}       # look signature -> page material


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(JSON_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	if parsed is Dictionary:
		_data = parsed
		_page = load(String(_data["page"])) as Texture2D


## "" when the mesh is a single Style G surface the atlas can take, else why not.
static func fold_reject(mesh: ArrayMesh) -> String:
	if mesh.get_surface_count() != 1:
		return "%d surfaces" % mesh.get_surface_count()
	var sm := mesh.surface_get_material(0) as ShaderMaterial
	if sm == null or not sm.has_meta("g_src"):
		return "not a Style G material"
	var tex := sm.get_shader_parameter("albedo_tex") as Texture2D
	if tex == null or tex.resource_path == "" or tex.resource_path.begins_with("res://.godot"):
		return "no file texture"
	if sm.get_shader_parameter("uv_scale") != Vector2.ONE or sm.get_shader_parameter("uv_offset") != Vector2.ZERO:
		return "uv transform"
	var ac = sm.get_shader_parameter("albedo_color")
	if ac != null and ac != Color.WHITE:
		return "albedo colour"
	var cut = sm.get_shader_parameter("alpha_cut")
	if cut != null and float(cut) > 0.0:
		return "alpha cut"
	var arr := mesh.surface_get_arrays(0)
	var uv = arr[Mesh.ARRAY_TEX_UV]
	if uv == null:
		return "no UVs"
	for p: Vector2 in (uv as PackedVector2Array):
		if p.x < -0.002 or p.x > 1.002 or p.y < -0.002 or p.y > 1.002:
			return "UVs tile outside 0..1"
	return ""


static func main_texture(mesh: ArrayMesh) -> Texture2D:
	return (mesh.surface_get_material(0) as ShaderMaterial).get_shader_parameter("albedo_tex") as Texture2D


## Move the mesh's single surface onto the shared page. Returns true when folded. Idempotent (meta "atlas").
static func fold(mesh: ArrayMesh, key: String) -> bool:
	if not enabled or mesh == null or mesh.has_meta("atlas"):
		return false
	_load()
	if _data.is_empty() or _page == null:
		return false
	var e: Dictionary = (_data["entries"] as Dictionary).get(key, {})
	if e.is_empty() or fold_reject(mesh) != "":
		return false
	var sm := mesh.surface_get_material(0) as ShaderMaterial
	if main_texture(mesh).resource_path.get_file() != String(e["src"]):
		return false                       # texture changed since the bake
	var off := Vector2(e["off"][0], e["off"][1])
	var sc := float(e["scale"])
	var arr := mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for i in uv.size():
		uv[i] = off + uv[i] * sc
	arr[Mesh.ARRAY_TEX_UV] = uv
	var aabb := mesh.get_aabb()
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _page_material(sm))
	mesh.custom_aabb = aabb
	mesh.set_meta("atlas", true)
	return true


## Page material for the look of `sm` (same shader and parameters except the texture): created once, shared by every mesh.
static func _page_material(sm: ShaderMaterial) -> Material:
	var sig := "%d" % sm.shader.get_instance_id()
	for u: Dictionary in sm.shader.get_shader_uniform_list():
		var n: String = u["name"]
		if n == "albedo_tex":
			continue
		var v: Variant = sm.get_shader_parameter(n)
		sig += "|%s=%s" % [n, (v.resource_path if v.resource_path != "" else str(v.get_instance_id())) if v is Resource else str(v)]
	if not _mats.has(sig):
		var d := sm.duplicate() as ShaderMaterial
		for k in sm.get_meta_list():
			d.set_meta(k, sm.get_meta(k))
		d.set_shader_parameter("albedo_tex", _page)
		_mats[sig] = d
	return _mats[sig]
