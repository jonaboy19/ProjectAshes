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
	# W1d (Valencious macro biomes): existing Poly Haven sets only, graded to Style G (warm, painterly)
	"meadow": ["leafy_grass", "disp"], "farmland": ["dirt", "disp"], "marsh": ["brown_mud_02", "disp"],
	"rift": ["rocky_terrain_02", "disp"], "snow": ["rocky_terrain_02", "disp"],
	# W3: highland / steppe scrub = rock detail mixed with leafy grass, dry gold-green
	"highland": ["rocky_terrain_02", "disp"],
}
const GRADE := ["meadow", "farmland", "marsh", "rift", "snow", "highland"]


## Offline grade (no new downloads): warm the meadow, make farmland a tilled brown, marsh a dark green-brown mud, the Rift a violet-black ash,
## snow a blue-white keeping the rock's detail.
func _grade(layer: String, im: Image) -> void:
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var l := c.get_luminance()
			var o := c
			match layer:
				"meadow": o = Color(c.r * 0.96, c.g * 1.08, c.b * 0.72)      # W3: greener than the W1 gold (Style G lush ground)
				"highland": o = Color(c.r * 1.05, c.g * 1.04, c.b * 0.80)
				"farmland": o = Color(l * 0.72 + 0.10, l * 0.66 + 0.10, l * 0.36 + 0.04)
				"marsh": o = Color(c.r * 0.70, c.g * 0.78, c.b * 0.52)
				"rift": o = Color(l * 0.44 + 0.07, l * 0.38 + 0.06, l * 0.50 + 0.09)
				"snow": o = Color(0.78 + l * 0.20, 0.82 + l * 0.17, 0.90 + l * 0.10)
			im.set_pixel(x, y, Color(clampf(o.r, 0, 1), clampf(o.g, 0, 1), clampf(o.b, 0, 1), c.a))


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
		var alb := _img(PH % [set, set, "diff"])
		if layer == "highland":
			var gr := _img(PH % ["leafy_grass", "leafy_grass", "diff"])
			for y in alb.get_height():
				for x in alb.get_width():
					alb.set_pixel(x, y, alb.get_pixel(x, y).lerp(gr.get_pixel(x, y), 0.55))
		if GRADE.has(layer):
			_grade(layer, alb)
		_pack(layer, alb, _img(PH % [set, set, "nor_gl"]), _img(PH % [set, set, "arm"]), _img(PH % [set, set, "disp"]))
	var cs := "res://assets/incoming/polyhaven/textures/cobblestone_floor_01/cobblestone_floor_01_%s_2k.jpg"
	_pack("cobble", _img("res://assets/art/textures/cobblestone.png"), _img("res://assets/art/textures/cobblestone_normal.png"),
		_img("res://assets/art/textures/cobblestone_arm.png"), _img(cs % "disp"))
	quit()
