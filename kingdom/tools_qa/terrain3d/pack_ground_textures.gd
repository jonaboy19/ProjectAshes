extends SceneTree
## One-off packer: turns the existing ground PBR sets (Poly Haven CC0 2k + the hand-painted honey cobbles) into the two packed
## textures Terrain3D wants per layer: <layer>_alb_h.png (albedo RGB + height A) and <layer>_nrm_r.png (normal RGB + roughness A),
## 1024 px, into res://assets/terrain3d/ground/. Run (needs the GDExtension, so NOT --headless-less?  headless is fine):
##   godot --headless --path kingdom -s res://tools_qa/terrain3d/pack_ground_textures.gd
## Normal maps: Terrain3D expects DirectX (Y-) normals, the sources are OpenGL (Y+), so green is inverted. If the lit ground looks
## inside-out on the GPU, flip INVERT_GREEN and re-run.

const OUT := "res://assets/terrain3d/ground/"
const SIZE := 1024
const INVERT_GREEN := true
const PH := "res://assets/incoming/polyhaven/textures/%s/%s_%s_2k.jpg"
## layer -> [albedo, normal(GL), arm, height-or-""]; the cobble set is the hand-painted one (no height map: luminance is used).
const LAYERS := {
	"grass": ["leafy_grass", "disp"], "forest": ["forest_ground_04", "disp"], "path": ["grass_path_2", "disp"],
	"rock": ["rocky_terrain_02", "disp"],
}


func _init() -> void:
	run.call_deferred()


func _img(path: String) -> Image:
	var im := Image.load_from_file(ProjectSettings.globalize_path(path))
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != SIZE or im.get_height() != SIZE:
		im.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return im


func _pack(name: String, alb: Image, nor: Image, arm: Image, height: Image) -> void:
	var h: Image = height if height != null else Terrain3DUtil.luminance_to_height(alb)
	var a: Image = Terrain3DUtil.pack_image(alb, h, false, false, true, 0)
	var n: Image = Terrain3DUtil.pack_image(nor, arm, INVERT_GREEN, false, false, 1)   # roughness = ARM green
	a.save_png(OUT + name + "_alb_h.png")
	n.save_png(OUT + name + "_nrm_r.png")
	print("packed ", name, " ", a.get_size(), " ", n.get_size())


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for layer: String in LAYERS:
		var set: String = LAYERS[layer][0]
		_pack(layer, _img(PH % [set, set, "diff"]), _img(PH % [set, set, "nor_gl"]), _img(PH % [set, set, "arm"]), _img(PH % [set, set, "disp"]))
	var cs := "res://assets/incoming/polyhaven/textures/cobblestone_floor_01/cobblestone_floor_01_%s_2k.jpg"
	_pack("cobble", _img("res://assets/art/textures/cobblestone.png"), _img("res://assets/art/textures/cobblestone_normal.png"),
		_img("res://assets/art/textures/cobblestone_arm.png"), _img(cs % "disp"))
	quit()
