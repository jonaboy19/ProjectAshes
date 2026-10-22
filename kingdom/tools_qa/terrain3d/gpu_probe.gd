extends SceneTree
## GPU smoke test for Terrain3D (never run headless): flat region(s) + optional assets, a few frames. Variant by --v=flat|assets|bridge.
##   Godot --path kingdom --resolution 640x360 -s res://tools_qa/terrain3d/gpu_probe.gd -- --v=assets
var frames := 0
var variant := "flat"
var _late: Terrain3DAssets
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v="):
			variant = a.substr(4)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 80, 0)
	cam.look_at_from_position(Vector3(0, 80, 0), Vector3(100, 0, 100))
	if variant == "bridge":
		WorldGen.setup(1066)
		var b := Terrain3DBridge.new()
		root.add_child(b)
		await process_frame
		b.build_all_now(Vector3(0, 0, 0))
		cam.position = Vector3(0, 80, 0)
		print("PROBE bridge regions ", b.region_count())
		return
	var t := Terrain3D.new()
	t.vertex_spacing = 1.5
	t.region_size = 256
	t.collision_mode = 0
	root.add_child(t)
	await process_frame
	if variant.begins_with("assets"):
		var n := int(variant.substr(6, 1)) if variant.length() > 6 else Terrain3DBridge.SLOTS.size()
		var assets := Terrain3DAssets.new()
		for i in n:
			var name: String = Terrain3DBridge.SLOTS[i]
			var ta := Terrain3DTextureAsset.new()
			ta.name = name
			ta.id = i
			if variant.ends_with("img") or variant.contains("img"):
				var ai := Image.load_from_file(ProjectSettings.globalize_path(Terrain3DBridge.TEX_DIR + name + "_alb_h.png"))
				var ni := Image.load_from_file(ProjectSettings.globalize_path(Terrain3DBridge.TEX_DIR + name + "_nrm_r.png"))
				ai.convert(Image.FORMAT_RGBA8)
				ni.convert(Image.FORMAT_RGBA8)
				ai.generate_mipmaps()
				ni.generate_mipmaps()
				ta.albedo_texture = ImageTexture.create_from_image(ai)
				ta.normal_texture = ImageTexture.create_from_image(ni)
			else:
				ta.albedo_texture = load(Terrain3DBridge.TEX_DIR + name + "_alb_h.png")
				ta.normal_texture = load(Terrain3DBridge.TEX_DIR + name + "_nrm_r.png")
			print("PROBE tex ", name, " ", ta.albedo_texture.get_size(), " ", ta.albedo_texture.get_image().get_format(), " / ", ta.normal_texture.get_size(), " ", ta.normal_texture.get_image().get_format())
			assets.set_texture(i, ta)
		if variant.contains("late"):
			_late = assets
		else:
			t.assets = assets
	var himg := Image.create_empty(256, 256, false, Image.FORMAT_RF)
	himg.fill(Color(5, 0, 0, 1))
	var cimg := Image.create_empty(256, 256, false, Image.FORMAT_RF)
	var col := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	col.fill(Color(1, 1, 1, 0.5))
	var r := Terrain3DRegion.new()
	r.region_size = 256
	r.vertex_spacing = 1.5
	r.location = Vector2i(0, 0)
	r.height_map = himg
	r.control_map = cimg
	r.color_map = col
	r.calc_height_range()
	t.data.add_region(r, true)
	print("PROBE ", variant, " region added")
	if _late != null:
		await process_frame
		await process_frame
		t.assets = _late
		print("PROBE late assets set")
func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		print("PROBE survived 30 frames")
		quit(0)
	return false
