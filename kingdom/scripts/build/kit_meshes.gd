extends RefCounted
## Build-kit meshes and the shared Style G kit materials (skill ashes-build-kit).
## Blender-built pieces carry material slots named kit_<role>; every piece gets the SAME material per role, textured with the
## Poly Haven sets already in the repo and graded by StyleG, so a whole settlement batches by material.
## Meshy-derived pieces (meshy_*) keep their baked atlas and are restyled by StyleG.restyle_mesh like any other prop.

const StyleG := preload("res://scripts/style_g.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")

## kit material -> [Style G role, Poly Haven set ("" = flat colour), tint, uv scale]
const KIT_MATS := {
	"kit_plaster": ["plaster", "clay_plaster", "efe3c8", 0.5],
	"kit_timber": ["timber", "medieval_wood", "6a4a34", 0.5],
	"kit_plank": ["timber", "brown_planks_05", "b89a78", 0.5],
	"kit_log": ["timber", "medieval_wood", "8a6a4c", 0.5],
	"kit_stone": ["stone", "medieval_blocks_02", "d6cfc2", 0.5],
	"kit_cobble": ["cobble", "cobblestone_floor_01", "cfc8bb", 0.5],
	"kit_thatch": ["roof", "thatch_roof_angled", "e8c88a", 0.5],
	"kit_slate": ["roof", "red_slate_roof_tiles_01", "8592a8", 0.5],
	"kit_shingle": ["roof", "clay_roof_tiles", "a07a5a", 0.5],
	"kit_iron": ["timber", "", "3a3a3e", 1.0],
	"kit_cloth": ["cloth", "", "b8463a", 1.0],
	"kit_clay": ["plaster", "clay_plaster", "c88a68", 0.5],
	"kit_dirt": ["cobble", "brown_mud_02", "a08a70", 0.5],
	"kit_hay": ["roof", "thatch_roof_angled", "f0d070", 0.5],
	"kit_coal": ["timber", "", "2a2420", 1.0],
}

static var _mats := {}
static var _meshes := {}
static var _ghost: Dictionary = {}


static func kit_material(name: String, tier := "") -> Material:
	var key := name + "|" + tier
	if _mats.has(key):
		return _mats[key]
	var spec: Array = KIT_MATS.get(name, ["timber", "", "8a6a48", 1.0])
	var base := StandardMaterial3D.new()
	base.resource_name = name
	base.albedo_color = Color(String(spec[2]))
	if String(spec[1]) != "":
		var tex := StyleG.ph(String(spec[1]), "diff", "1k")
		if tex != null:
			base.albedo_texture = tex
			base.uv1_scale = Vector3.ONE * float(spec[3]) * 2.0
	base.roughness = 0.92
	var m: Material = StyleG.material_for(String(spec[0]), base, 1, tier if tier != "" else StyleG.current_tier(), false)
	if m == null:
		m = base
	_mats[key] = m
	return m


## One merged, restyled mesh per piece and LOD (cached for the session).
static func mesh(kind: String, lod := 0) -> ArrayMesh:
	var key := "%s:%d" % [kind, lod]
	if _meshes.has(key):
		return _meshes[key]
	var path := BuildKit.mesh_path(kind, lod)
	var m: ArrayMesh = null
	if ResourceLoader.exists(path):
		m = Assets.merged_mesh(path, false)
		if m != null:
			var restyle_rest := false
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				var nm := mat.resource_name if mat != null else ""
				var base := nm.get_slice(".", 0)
				if KIT_MATS.has(base):
					m.surface_set_material(i, kit_material(base))
				else:
					restyle_rest = true
			if restyle_rest:
				var role := String(BuildKit.def(kind).get("role", ""))
				StyleG.restyle_mesh(m, kind, "", role)
	elif lod > 0:
		m = mesh(kind, 0)
	else:
		m = _fallback(kind)
	_meshes[key] = m
	return m


## A plain box of the piece's footprint, so the system works before the art lands (and in headless tests).
static func _fallback(kind: String) -> ArrayMesh:
	var d := BuildKit.def(kind)
	var fp: Array = d.get("fp", [1, 1])
	var size := Vector3(2.0 * int(fp[0]), 1.0, 2.0 * int(fp[1]))
	var off := Vector3.ZERO
	match String(d.get("layer", "")):
		"foundation":
			size.y = 1.0
		"wall", "gable", "door":
			size = Vector3(2.0 * int(fp[0]), 3.0 if not bool(d.get("low", false)) else 1.2, 0.24)
			off.y = size.y * 0.5
		"floor", "ground":
			size.y = 0.15
			off.y = -0.075
		"roof":
			size.y = 0.25
			off.y = 1.0
		"fence":
			size = Vector3(2.0, 1.1, 0.12)
			off.y = 0.55
		_:
			size = Vector3(0.9, 1.0, 0.9)
			off.y = 0.5
	var b := BoxMesh.new()
	b.size = size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(b, 0, Transform3D(Basis.IDENTITY, off))
	var out := st.commit()
	out.surface_set_material(0, kit_material("kit_stone" if String(d.get("mat", "")) == "stone" else "kit_plank"))
	return out


## Translucent blueprint material for plans and the ghost: blue = OK, amber = plan (missing materials), red = blocked.
static func ghost_material(state: String) -> Material:
	if _ghost.has(state):
		return _ghost[state]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	match state:
		"ok":
			m.albedo_color = Color(0.35, 0.95, 0.45, 0.45)
		"plan":
			m.albedo_color = Color(1.0, 0.75, 0.25, 0.45)
		"bad":
			m.albedo_color = Color(1.0, 0.25, 0.2, 0.5)
		_:
			m.albedo_color = Color(0.45, 0.7, 1.0, 0.32)       # a laid plan waiting for the crew
	_ghost[state] = m
	return m
