extends SceneTree
## Bakes vertex AO for every town building/prop LOD into res://assets/baked/vao/ (see scripts/world/baked_vao.gd).
## Run (GDScript, ~0.5-2 s per mesh): godot --headless --path kingdom -s res://tools_qa/baked_quality/bake_town_vao.gd [-- --only=house_1,wall]
## Re-run after a building GLB changes (a blob whose vertex count no longer matches is ignored at runtime).
const BakedVao := preload("res://scripts/world/baked_vao.gd")

const SKIP_ROLES := ["goods", "tree", "ivy", "banner", "flag", "foliage", "char"]


func _initialize() -> void:
	await process_frame
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	var cls = Assets
	var StyleG = load("res://scripts/style_g.gd")
	BakedVao.bake_mode = true
	var t0 := Time.get_ticks_msec()
	var n := 0
	for key: String in cls.BUILDINGS:
		if not only.is_empty() and not key in only:
			continue
		if StyleG.role_for_asset(key) in SKIP_ROLES:
			print("skip ", key, " role ", StyleG.role_for_asset(key))
			continue
		var entry: Array = cls.BUILDINGS[key]
		for lod in entry.size() / 2:
			var k := key if lod == 0 else "%s:lod%d" % [key, lod]
			cls.building_mesh(k)
			n += 1
	print("baked_vao done: %d meshes in %.1f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
