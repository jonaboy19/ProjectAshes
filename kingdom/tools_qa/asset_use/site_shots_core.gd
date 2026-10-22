extends RefCounted
## See site_shots.gd. One view = {name, at [x, z], look [x, z], up, look_up, hour}.

const PATCH := 150.0         # half size of the terrain patch under a view, metres
const STEP := 2.0


func run(tree: SceneTree, args: Dictionary) -> void:
	var root := tree.root
	WorldGen.setup(int(args.get("seed", 1066)))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(args.get("views", "res://tools_qa/asset_use/asset_use_views.json"))))
	var views: Array = (parsed as Dictionary)["views"]
	var only: PackedStringArray = String(args.get("only", "")).split(",", false)
	var out := String(args.get("out", "/tmp/site_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var StyleGs: GDScript = load("res://scripts/style_g.gd")
	var env: Environment = StyleGs.call("make_environment", "medium")
	we.environment = env
	world.add_child(we)
	var sun: DirectionalLight3D = StyleGs.call("make_sun", "medium")
	world.add_child(sun)
	var fill: DirectionalLight3D = StyleGs.call("make_fill")
	world.add_child(fill)
	var rd := RegionDressing.new()
	world.add_child(rd)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	world.add_child(cam)
	cam.current = true
	var ground := MeshInstance3D.new()
	world.add_child(ground)
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	ground.material_override = gm
	for v: Dictionary in views:
		if not only.is_empty() and not (String(v["name"]) in only):
			continue
		var at: Array = v["at"]
		var lk: Array = v["look"]
		var centre := Vector2((float(at[0]) + float(lk[0])) * 0.5, (float(at[1]) + float(lk[1])) * 0.5)
		ground.mesh = _terrain(centre)
		var h := WorldGen.height(centre.x, centre.y)
		rd.focus = Vector3(centre.x, h, centre.y)
		var rl := rd.get_node_or_null("Region1Look")
		if rl != null:
			rl.set("focus", rd.focus)
			rl.call("update_now")
		var frames := 0
		while frames < 600 and (frames < 30 or not rd._queue.is_empty()):
			await tree.process_frame
			frames += 1
		for k in 20:
			await tree.process_frame
		var ground_a := WorldGen.height(float(at[0]), float(at[1])) + float(v.get("up", 2.2))
		var ground_l := WorldGen.height(float(lk[0]), float(lk[1])) + float(v.get("look_up", 1.5))
		cam.global_position = Vector3(float(at[0]), ground_a, float(at[1]))
		cam.look_at(Vector3(float(lk[0]), ground_l, float(lk[1])))
		sun.rotation_degrees = Vector3(-40.0, rad_to_deg(cam.rotation.y) + 30.0, 0.0)
		fill.rotation_degrees = Vector3(-20.0, rad_to_deg(cam.rotation.y) + 180.0, 0.0)
		for k in 6:
			await tree.process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, String(v["name"])])
		print("SAVED %s/%s.png  built sites %d  frames %d" % [out, String(v["name"]), rd.built_count(), frames])


func _terrain(c: Vector2) -> ArrayMesh:
	var n := int(PATCH * 2.0 / STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := c.x - PATCH
	var z0 := c.y - PATCH
	for i in n:
		for j in n:
			var q := [Vector2(i, j), Vector2(i + 1, j), Vector2(i, j + 1), Vector2(i + 1, j + 1)]
			var p: Array = []
			for e: Vector2 in q:
				var x := x0 + e.x * STEP
				var z := z0 + e.y * STEP
				var hh := WorldGen.height(x, z)
				var sl := 0.0
				p.append([Vector3(x, hh, z), WorldGen.color_at(x, z, hh, sl)])
			for idx in [0, 2, 1, 1, 2, 3]:
				st.set_color(p[idx][1])
				st.add_vertex(p[idx][0])
	st.generate_normals()
	return st.commit()
