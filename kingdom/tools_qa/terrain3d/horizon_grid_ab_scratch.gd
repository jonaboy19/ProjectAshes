extends SceneTree
## Scratch-only isolated Region1Horizon grid A/B. Does not instantiate main.tscn or TerrainStreamer.

const WG := preload("res://scripts/world/world_gen.gd")
const StyleG := preload("res://scripts/style_g.gd")
const HORIZON_SOURCE := "res://scripts/region1/region1_horizon.gd"
const BIOME_TEX := "res://assets/incoming/region1/terrain/biome_map.png"
const VIEWS := [120.0, 400.0]
const OUT_DIR := "res://../work/terrain_experiment_20261025/horizon_grid_ab_serial"

var camera: Camera3D
var biome: Texture2D


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(960, 540))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	WG.setup(1066)
	biome = load(BIOME_TEX) as Texture2D
	var env := Environment.new()
	StyleG.apply_environment(env, "high", true)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := StyleG.make_sun("high")
	root.add_child(sun)
	var fill := StyleG.make_fill()
	root.add_child(fill)
	StyleG.apply_daylight(env, sun, fill, 12.0, 12.0)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 60.0
	camera.far = 20000.0
	root.add_child(camera)
	# SceneTree._initialize runs before the root is attached. Let the camera enter the active tree before transforms.
	await process_frame
	for altitude in VIEWS:
		for cell in [72.0, 24.0]:
			await _capture(cell, altitude)
	quit(0)


func _capture(cell: float, altitude: float) -> void:
	var source := FileAccess.get_file_as_string(HORIZON_SOURCE)
	var needle := "const CELL := 72.0"
	if not source.contains(needle):
		push_error("Production horizon CELL declaration changed; scratch prototype stopped")
		quit(2)
		return
	if cell != 72.0:
		source = source.replace(needle, "const CELL := %.1f" % cell)
	var script := GDScript.new()
	script.source_code = source
	var compile_error := script.reload()
	if compile_error != OK:
		push_error("Could not compile scratch horizon source: %s" % compile_error)
		quit(2)
		return
	var horizon := script.new() as Node3D
	horizon.set("blob_range", 0.0)
	root.add_child(horizon)
	horizon.set("biome", biome)
	horizon.call("build_now")
	var at := Vector2(850.0, 1340.0)
	var look := Vector2(1130.0, 1004.0)
	camera.global_position = Vector3(at.x, WG.height(at.x, at.y) + altitude, at.y)
	camera.look_at(Vector3(look.x, WG.height(look.x, look.y), look.y))
	for _i in 4:
		await process_frame
	var ground := horizon.get_node("HorizonGround") as MeshInstance3D
	var mesh := ground.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var triangle_count: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var image := root.get_viewport().get_texture().get_image()
	var label := "%dm_cell%dm" % [int(altitude), int(cell)]
	var abs_path := ProjectSettings.globalize_path(OUT_DIR + "/" + label + ".png")
	image.save_png(abs_path)
	print("HORIZON_AB cell_m=", int(cell), " altitude_m=", int(altitude),
		" vertices=", vertex_count, " triangles=", triangle_count,
		" capture=", abs_path, " bytes=", image.get_data().size())
	horizon.queue_free()
	await process_frame
	await process_frame
