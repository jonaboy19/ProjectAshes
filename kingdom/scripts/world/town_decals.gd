class_name TownDecals
extends RefCounted
## Small painted decal library for towns and villages (Godot Decal nodes, albedo + normal, the puddle
## with an ORM for a wet sheen). Textures are drawn by tools/make_town_decals.py.
##
## Budget (Mobile renderer: at most 8 decals affect one mesh):
##   * wall decals only project onto the house batches (visual layer WALL_LAYER), ground decals only onto
##     the terrain chunk ground meshes (GROUND_LAYER), so the two never compete for a mesh's 8 slots;
##   * SettlementBuilder caps them per 40 m house cell / per 64 m terrain chunk (see CELL_CAP, CHUNK_CAP);
##   * every decal fades out between 30 and 40 m from the camera (distance_fade);
##   * LOW (old phones, Compatibility renderer) builds none, and hides the existing ones if the tier drops.

const DIR := "res://assets/art/decals/"
## Visual layers (VisualInstance3D.layers bit masks) used as Decal.cull_mask; layers 11 and 12.
const WALL_LAYER := 1 << 10
const GROUND_LAYER := 1 << 11
const FADE_BEGIN := 30.0
const FADE_LEN := 10.0
const CELL_CAP := 6
const CHUNK_CAP := 5

## kind -> [albedo, normal or "", orm or ""]
const KINDS := {
	"moss": ["moss_base", "moss_base_n", ""],
	"dirt": ["dirt_base", "dirt_base_n", ""],
	"soot": ["soot", "", ""],
	"plaster": ["plaster", "plaster_n", ""],
	"ruts": ["ruts", "ruts_n", ""],
	"puddle": ["puddle", "", "puddle_orm"],
}

static var _tex := {}


## QA switch for before/after shots and benches: `-- --no-decals` builds the towns without decals.
static var _off := OS.get_cmdline_user_args().has("--no-decals")


static func available() -> bool:
	return not _off and ResourceLoader.exists(DIR + "moss_base.png")


static func _t(name: String) -> Texture2D:
	if name == "":
		return null
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


## One Decal. `size` = (width x, projection depth y, height z); walls project along their local Y,
## which the caller points out of the wall (see wall_basis).
static func make(kind: String, size: Vector3, mask: int, tint := Color.WHITE) -> Decal:
	var spec: Array = KINDS[kind]
	var d := Decal.new()
	d.size = size
	d.texture_albedo = _t(spec[0])
	d.texture_normal = _masked_normal(spec[1], spec[0])
	d.texture_orm = _t(spec[2])
	d.modulate = tint
	d.cull_mask = mask
	d.distance_fade_enabled = true
	d.distance_fade_begin = FADE_BEGIN
	d.distance_fade_length = FADE_LEN
	d.upper_fade = 0.35
	d.lower_fade = 0.35
	d.normal_fade = 0.25
	d.add_to_group("town_decal")
	return d


## Basis for a decal on a vertical wall whose outward normal is `n` (horizontal, unit): local Y = n (the
## decal looks into the wall), image up = world up, image right = the viewer's right.
static func wall_basis(n: Vector3) -> Basis:
	return Basis(Vector3.UP.cross(n), n, Vector3.DOWN)


## One ground-decal budget per settlement root, shared by every builder that paints the terrain (SettlementBuilder, the
## district mud, the benchmark street): at most CHUNK_CAP per 64 m terrain chunk. Returns true and takes a slot when free.
## Ground decals per 64 m chunk: Forward+ (PC) clusters decals, so the street-edge mud of the benchmark slice fits; Mobile keeps 5.
static func chunk_cap() -> int:
	return 16 if RenderingServer.get_current_rendering_method() == "forward_plus" else CHUNK_CAP


static func claim_ground(root: Node, x: float, z: float) -> bool:
	var counts: Dictionary = root.get_meta("ground_decal_chunks", {})
	var ck := Vector2i(floori(x / 64.0), floori(z / 64.0))
	# Forward+ (PC) clusters decals (no 8-per-mesh limit of the Mobile renderer): room for the street-edge mud of the benchmark slice
	var cap := chunk_cap()
	if int(counts.get(ck, 0)) >= cap:
		return false
	counts[ck] = int(counts.get(ck, 0)) + 1
	root.set_meta("ground_decal_chunks", counts)
	return true


## Benchmark slice (night glare on the Ashford inn): the decal normal maps have alpha 1 everywhere, and Godot uses the normal map's
## alpha as its blend mask, so a decal replaced the normals of EVERY surface in its projection box (sign boards, lanterns, crates on the
## inn porch), which lit up as flat slabs at night. The normal map gets the albedo's alpha (built once per kind, cached).
static func _masked_normal(normal_name: String, albedo_name: String) -> Texture2D:
	if normal_name == "":
		return null
	var key := normal_name + "|masked"
	if _tex.has(key):
		return _tex[key]
	var n := _t(normal_name)
	var a := _t(albedo_name)
	if n == null or a == null:
		return n
	var ni := n.get_image()
	var ai := a.get_image()
	if ni == null or ai == null:
		return n
	ni = ni.duplicate()
	ai = ai.duplicate()
	if ni.is_compressed():
		ni.decompress()
	if ai.is_compressed():
		ai.decompress()
	ni.convert(Image.FORMAT_RGBA8)
	ai.convert(Image.FORMAT_RGBA8)
	if ai.get_size() != ni.get_size():
		ai.resize(ni.get_width(), ni.get_height())
	for y in ni.get_height():
		for x in ni.get_width():
			var c := ni.get_pixel(x, y)
			c.a = ai.get_pixel(x, y).a
			ni.set_pixel(x, y, c)
	ni.generate_mipmaps()
	var t := ImageTexture.create_from_image(ni)
	_tex[key] = t
	return t
