extends SceneTree
## CC0 lookdev renderer (GPU, not headless). One tile per asset on a neutral ground.
## godot --path kingdom --resolution 640x480 -s res://assets/cc0/_lookdev/lookdev.gd -- --list=<abs txt> --out=<abs dir>
## list lines: res:// path to a .gltf/.glb, or a res:// texture folder (renders a material swatch).

var _items: PackedStringArray = []
var _out := ""
var _holder: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--list="):
			_items = FileAccess.get_file_as_string(a.substr(7)).strip_edges().split("\n")
		elif a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	var sky := Sky.new()
	var hdr: Texture2D = load("res://assets/cc0/hdri/belfast_open_field/belfast_open_field_2k.hdr")
	if hdr:
		var pm := PanoramaSkyMaterial.new(); pm.panorama = hdr; sky.sky_material = pm
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	root.add_child(sun)
	_sun = sun
	var g := MeshInstance3D.new(); var pm2 := PlaneMesh.new(); pm2.size = Vector2(40, 40); g.mesh = pm2
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.33, 0.32, 0.30); gm.roughness = 0.95
	g.material_override = gm; g.position.y = -0.002; root.add_child(g)
	_holder = Node3D.new(); root.add_child(_holder)
	_cam = Camera3D.new(); _cam.fov = 38.0; root.add_child(_cam); _cam.current = true
	_run.call_deferred()

func _tex(dir: String, keys: Array) -> Texture2D:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import"): continue
		var lf := f.to_lower()
		for k in keys:
			if lf.contains(k):
				return load(dir.path_join(f))
	return null

func _run() -> void:
	for line in _items:
		var p := line.strip_edges()
		if p == "" or p.begins_with("#"): continue
		print("LOOKDEV ", p)
		for c in _holder.get_children(): c.queue_free()
		await process_frame
		var label := p.get_file().get_basename() if (p.ends_with(".gltf") or p.ends_with(".glb")) else p.trim_suffix("/").get_file()
		if FileAccess.file_exists(_out.path_join(label + ".png")): continue
		var aabb := AABB()
		if p.ends_with(".gltf") or p.ends_with(".glb"):
			var ps: PackedScene = load(p)
			if ps == null:
				push_error("LOOKDEV load failed " + p); continue
			var inst := ps.instantiate(); _holder.add_child(inst)
			var first := true
			var tris := 0
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var ab: AABB = mi.global_transform * mi.get_aabb()
				aabb = ab if first else aabb.merge(ab); first = false
				for s in mi.mesh.get_surface_count():
					tris += mi.mesh.surface_get_array_index_len(s) / 3 if mi.mesh is ArrayMesh else 0
			inst.position.y -= aabb.position.y  # sit on ground
			aabb.position.y = 0.0
			_log_dim("%s\t%.2f x %.2f x %.2f m\t%d tris" % [p, aabb.size.x, aabb.size.y, aabb.size.z, tris])
		else:
			label = p.trim_suffix("/").get_file()
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _tex(p, ["diff", "color"])
			var n := _tex(p, ["nor_gl", "normalgl"])
			if n: mat.normal_enabled = true; mat.normal_texture = n
			var arm := _tex(p, ["_arm_"])
			if arm:
				mat.roughness_texture = arm; mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				mat.ao_enabled = true; mat.ao_texture = arm; mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			else:
				var r := _tex(p, ["roughness"]); if r: mat.roughness_texture = r
				var ao := _tex(p, ["ambientocclusion"]); if ao: mat.ao_enabled = true; mat.ao_texture = ao
			var plane := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(4, 4); plane.mesh = pm
			mat.uv1_scale = Vector3(2, 2, 1)  # 2 m per tile
			plane.material_override = mat; plane.position.y = 0.003; _holder.add_child(plane)
			aabb = AABB(Vector3(-0.7, 0, -0.7), Vector3(1.4, 0.2, 1.4))
			_sun.rotation_degrees = Vector3(-24, -60, 0); _sun.light_energy = 1.1
			_log_dim("%s\ttexture swatch (2 m tile)" % p)
		var c := aabb.get_center()
		var r := maxf(aabb.size.length() * 0.5, 0.15)
		var d := Vector3(1.0, 0.65, 1.15).normalized()
		_cam.position = c + d * (r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.05)
		_cam.look_at(c, Vector3.UP)
		_cam.near = 0.02
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png(_out.path_join(label + ".png"))
	quit()

func _log_dim(line: String) -> void:
	var fp := _out.path_join("dims.txt")
	var f := FileAccess.open(fp, FileAccess.READ_WRITE if FileAccess.file_exists(fp) else FileAccess.WRITE)
	f.seek_end(); f.store_line(line); f.close()
