# Import an eroded r16 heightmap (from erode_heightmap.py / ant_terrain.py) into Terrain3D
# headlessly and save the region files.  Run:
#   Godot_v4.6.3-stable_win64_console.exe --headless --path <project with addons/terrain_3d> \
#     -s res://../../path/terrain3d_import_r16.gd -- <r16 file> <size> <max_height_m> <out_dir>
extends SceneTree

func _init() -> void:
	run.call_deferred()


func run() -> void:
	var a := OS.get_cmdline_user_args()
	var path := a[0]
	var size := int(a[1])
	var max_h := float(a[2])
	var out_dir := a[3]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var t := Terrain3D.new()
	root.add_child(t)
	await process_frame
	t.data_directory = out_dir
	await process_frame
	var img: Image = Terrain3DUtil.load_image(path, ResourceLoader.CACHE_MODE_IGNORE, Vector2(0, 1), Vector2i(size, size))
	print("LOADED ", img.get_size(), " format ", img.get_format())
	var imgs: Array[Image] = []
	imgs.resize(Terrain3DRegion.TYPE_MAX)
	imgs[Terrain3DRegion.TYPE_HEIGHT] = img
	var origin := Vector3(-size / 2.0, 0, -size / 2.0)
	t.data.import_images(imgs, origin, 0.0, max_h)
	print("REGIONS ", t.data.get_region_count())
	var lo := 1e9
	var hi := -1e9
	for i in 20:
		for j in 20:
			var h := t.data.get_height(Vector3(origin.x + 8 + i * size / 20.0, 0, origin.z + 8 + j * size / 20.0))
			lo = min(lo, h)
			hi = max(hi, h)
	print("HEIGHT_RANGE ", lo, " ", hi)
	t.data.save_directory(out_dir)
	print("SAVED ", DirAccess.get_files_at(out_dir))
	quit()
