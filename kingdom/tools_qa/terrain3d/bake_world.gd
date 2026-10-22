extends SceneTree
## W1e measurement: per-region cost of the runtime Terrain3D bake (worker maths vs the main-thread add_region hitch), macro on/off, and
## the size an offline bake (Terrain3DData.save_directory) of the 32 x 32 regions would take. Decision rule (WORLD_BRIEF W1e): only bake
## offline if the main-thread hitch exceeds 50 ms.   Godot --headless --path kingdom -s res://tools_qa/terrain3d/bake_world.gd -- [--world_macro=valencious]
func _initialize() -> void:
	WorldGen.setup(1066)
	print("MODE macro=", WorldMacro.mode(), " active=", WorldMacro.active)
	var b := Terrain3DBridge.new()
	root.add_child(b)
	await process_frame
	var locs := [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, 3), Vector2i(5, 5)]
	var worker_ms := 0.0
	var main_ms := 0.0
	for loc: Vector2i in locs:
		var t0 := Time.get_ticks_usec()
		var maps := Terrain3DBridge.build_maps(loc)
		var t1 := Time.get_ticks_usec()
		b._add_region(loc, maps)
		var t2 := Time.get_ticks_usec()
		worker_ms += (t1 - t0) / 1000.0
		main_ms = maxf(main_ms, (t2 - t1) / 1000.0)
		print("region %s build_maps %.0f ms (worker thread)  add_region %.1f ms (main thread)" % [loc, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	var per_region_bytes := 256 * 256 * 4 * 2 + 256 * 256 * 4   # height RF + control RF + colour RGBA8
	print("RESULT worker avg %.0f ms/region, main-thread worst add_region %.1f ms; raw data %.2f MB/region x 1024 = %.0f MB (uncompressed .res/.png would be similar)" % [worker_ms / locs.size(), main_ms, per_region_bytes / 1048576.0, per_region_bytes * 1024 / 1048576.0])
	print("MACRO RAM bytes ", WorldMacro.memory_bytes())
	quit(0)
