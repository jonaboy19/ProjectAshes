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
	d.texture_normal = _t(spec[1])
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
