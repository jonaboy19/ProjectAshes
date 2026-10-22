extends Node
## Paints kingdom/assets/ui/maps/region1_parchment.png (+ region1_parchment.json) from the REAL WorldGen data.
## 1) dump:  Godot --headless --path kingdom -s res://tools_qa/map/dump_world.gd -- --out=<dir> --grid=1024
## 2) paint: Godot --path kingdom res://tools_qa/map/paint_parchment.tscn --resolution 1280x720 -- --data=<dir> --out=res://assets/ui/maps [--size=2048] [--bare]
## Never --headless for step 2 (needs the GPU). Quits by itself.

const Ink := preload("res://tools_qa/map/parchment_ink.gd")

var data_dir := ""
var out_dir := "res://assets/ui/maps"
var size := 2048
var bare := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--data="): data_dir = a.substr(7)
		elif a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--size="): size = int(a.substr(7))
		elif a == "--bare": bare = true
	var t0 := Time.get_ticks_msec()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_dir + "/region1_world.json"))
	var n := int(world["grid"])
	var raw := FileAccess.get_file_as_bytes(data_dir + "/region1_grid.bin")
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBAF, raw)
	var gtex := ImageTexture.create_from_image(img)
	var margin := 88.0 * size / 2048.0
	var terrain := size - 2.0 * margin
	var lay := {"size": size, "margin": margin, "terrain": terrain, "half": float(world["half"]), "ppm": terrain / (2.0 * float(world["half"]))}
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	add_child(vp)
	var ink: Node2D = Ink.new()
	ink.setup(world, raw, n, lay, bare)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://tools_qa/map/parchment_paper.gdshader")
	sm.set_shader_parameter("grid", gtex)
	sm.set_shader_parameter("img_px", float(size))
	sm.set_shader_parameter("margin_px", margin)
	sm.set_shader_parameter("terrain_px", terrain)
	sm.set_shader_parameter("cell_m", float(world["cell_m"]))
	sm.set_shader_parameter("grid_n", float(n))
	var cl: Dictionary = ink.clear_zones()
	sm.set_shader_parameter("clear_disc", cl["disc"])
	sm.set_shader_parameter("clear_a", cl["a"])
	sm.set_shader_parameter("clear_b", cl["b"])
	sm.set_shader_parameter("rift_a", cl["rift_a"])
	sm.set_shader_parameter("rift_b", cl["rift_b"])
	var cr := ColorRect.new()
	cr.size = Vector2(size, size)
	cr.material = sm
	vp.add_child(cr)
	vp.add_child(ink)
	for i in 6:
		await get_tree().process_frame
	var out := vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGB8)
	var png := ProjectSettings.globalize_path(out_dir + "/" + ("region1_parchment_bare.png" if bare else "region1_parchment.png"))
	DirAccess.make_dir_recursive_absolute(png.get_base_dir())
	print("save png: ", out.save_png(png), " ", png, " ", out.get_size(), " ms=", Time.get_ticks_msec() - t0)
	if not bare:
		var jf := FileAccess.open(ProjectSettings.globalize_path(out_dir + "/region1_parchment.json"), FileAccess.WRITE)
		jf.store_string(JSON.stringify(ink.describe(), "\t"))
		jf.close()
	get_tree().quit()
