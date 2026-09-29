extends Node3D
## Octahedral impostor proof: dense forest + village, full meshes vs impostors vs hybrid, with fps/GPU numbers.
##   Godot --path kingdom --rendering-method mobile res://tools_qa/addons_demo/impostor_forest.tscn -- --capture=<abs dir> [--trees=3000] [--houses=80]
## Without --capture: interactive (keys 1 = full meshes, 2 = impostors, 3 = hybrid, 4 = compare row).

const H := preload("res://tools_qa/addons_demo/harness.gd")
const N := "res://assets/incoming/quaternius/stylized-nature-megakit/glTF/"
const G := "res://assets/generated/"
const IMP := "res://assets/generated/impostors/"
const CELL := 32.0
const NEAR := 45.0

# kind -> [source scene, impostor scene, count share]
const KINDS := {
	"oak1": [N + "CommonTree_1.gltf", IMP + "oak1_octa.tscn", 0.4],
	"oak4": [N + "CommonTree_4.gltf", IMP + "oak4_octa.tscn", 0.4],
	"twisted": [N + "TwistedTree_1.gltf", IMP + "twisted_octa.tscn", 0.2],
	"village_house": [G + "village_house_a.glb", IMP + "village_house_octa.tscn", 0.0],
}

var cap_dir := ""
var tree_count := 3000
var house_count := 80
var cam: Camera3D
var root_group: Node3D
var log_lines: PackedStringArray = []
var placements: Dictionary = {}   # kind -> Array[Transform3D]
var mesh_cache: Dictionary = {}   # kind -> [Mesh, Transform3D local]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): cap_dir = a.substr(10)
		if a.begins_with("--trees="): tree_count = int(a.substr(8))
		if a.begins_with("--houses="): house_count = int(a.substr(9))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var w := H.sunny_world(self)
	(w["env"] as Environment).fog_enabled = true
	(w["env"] as Environment).fog_light_color = Color(0.78, 0.86, 0.93)
	(w["env"] as Environment).fog_density = 0.004
	H.ground(self, 600.0, Color(0.40, 0.55, 0.26))
	cam = Camera3D.new()
	cam.current = true
	cam.fov = 65.0
	cam.far = 300.0
	add_child(cam)
	cam.position = Vector3(0, 2.6, 8)
	cam.look_at(Vector3(0, 6.0, -60))
	root_group = Node3D.new()
	add_child(root_group)
	_scatter()
	for k in KINDS:
		_load_source(k)
	if cap_dir == "":
		H.label(self, "1 full meshes | 2 impostors | 3 hybrid (<45 m full) | 4 compare row")
		_build("hybrid")
		return
	_run_capture()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_1: _build("mesh")
			KEY_2: _build("impostor")
			KEY_3: _build("hybrid")
			KEY_4: _compare_row()

func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in KINDS:
		placements[k] = []
	var shares := 0.0
	for i in tree_count:
		var r := rng.randf()
		var kind := "oak1" if r < 0.4 else ("oak4" if r < 0.8 else "twisted")
		var p := Vector3(rng.randf_range(-130, 130), 0, rng.randf_range(-230, 10))
		if absf(p.x) < 3.5 and p.z > -12:
			continue
		var s := rng.randf_range(0.8, 1.25) * (0.55 if kind == "twisted" else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		placements[kind].append(Transform3D(b, p))
	for i in house_count:
		var p := Vector3(rng.randf_range(-110, 110), 0, rng.randf_range(-200, -14))
		var b := Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5 + rng.randf_range(-0.2, 0.2)).scaled(Vector3.ONE * rng.randf_range(0.9, 1.1))
		placements["village_house"].append(Transform3D(b, p))

func _load_source(kind: String) -> void:
	var inst := (load(KINDS[kind][0]) as PackedScene).instantiate()
	var mis: Array = inst.find_children("*", "MeshInstance3D", true, false)
	var meshes: Array = []
	for mi: MeshInstance3D in mis:
		meshes.append([mi.mesh, mi.transform])
	mesh_cache[kind] = meshes
	inst.free()

func _clear() -> void:
	for c in root_group.get_children():
		c.queue_free()

func _mm(mesh: Mesh, xforms: Array, mat: Material, cast_shadows: bool, margin := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = margin
	return mi

## mode: "mesh" (all full), "impostor" (all impostors), "hybrid" (< NEAR from camera full, rest impostor)
func _build(mode: String) -> Dictionary:
	_clear()
	await get_tree().process_frame
	var stats := {"instances_full": 0, "instances_imp": 0, "multimeshes": 0}
	var cpos := cam.global_position
	for kind in KINDS:
		var imp_scene := (load(KINDS[kind][1]) as PackedScene).instantiate() as MeshInstance3D
		var imp_mesh := imp_scene.mesh
		var imp_mat := imp_scene.material_override
		var margin := imp_scene.extra_cull_margin
		# bucket by cell so every MultiMesh is frustum-culled as a unit (same as the game's cell batching)
		var full_cells := {}
		var imp_cells := {}
		for t: Transform3D in placements[kind]:
			var use_full := mode == "mesh" or (mode == "hybrid" and t.origin.distance_to(cpos) < NEAR)
			var key := Vector2i(int(floor(t.origin.x / CELL)), int(floor(t.origin.z / CELL)))
			var cells := full_cells if use_full else imp_cells
			if not cells.has(key):
				cells[key] = []
			cells[key].append(t)
		for key in full_cells:
			for m in mesh_cache[kind]:
				var xs: Array = []
				for t: Transform3D in full_cells[key]:
					xs.append(t * (m[1] as Transform3D))
				root_group.add_child(_mm(m[0], xs, null, true))
				stats["multimeshes"] += 1
			stats["instances_full"] += full_cells[key].size()
		for key in imp_cells:
			root_group.add_child(_mm(imp_mesh, imp_cells[key], imp_mat, false, margin))
			stats["multimeshes"] += 1
			stats["instances_imp"] += imp_cells[key].size()
		imp_scene.free()
	await get_tree().process_frame
	return stats

func _compare_row() -> void:
	_clear()
	var x := -30.0
	for kind in KINDS:
		var imp_scene := (load(KINDS[kind][1]) as PackedScene).instantiate() as MeshInstance3D
		for m in mesh_cache[kind]:
			var mi := MeshInstance3D.new()
			mi.mesh = m[0]
			mi.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(x, 0, -34)) * (m[1] as Transform3D)
			root_group.add_child(mi)
		imp_scene.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(x, 0, -60))
		root_group.add_child(imp_scene)
		var mi2 := MeshInstance3D.new()   # second row: the impostor at the same depth as the mesh row for a fair side by side
		mi2.mesh = imp_scene.mesh
		mi2.material_override = imp_scene.material_override
		mi2.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(x + 14.0, 0, -34))
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root_group.add_child(mi2)
		x += 26.0
	cam.position = Vector3(0, 2.6, 8)
	cam.look_at(Vector3(4, 5, -34))

func _run_capture() -> void:
	log_lines.append("renderer=%s adapter=%s | %d trees + %d houses, 32 m cells, hybrid switch at %d m" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), tree_count, house_count, int(NEAR)])
	DirAccess.make_dir_recursive_absolute(cap_dir)
	for mode in ["mesh", "impostor", "hybrid"]:
		var st: Dictionary = await _build(mode)
		await get_tree().create_timer(1.0).timeout
		await H.shot(get_tree(), cap_dir, "impostors_forest_" + mode)
		var m := await H.measure(get_tree(), 300)
		log_lines.append(H.fmt("%-8s full=%d imp=%d multimeshes=%d" % [mode, st["instances_full"], st["instances_imp"], st["multimeshes"]], m))
	# low-angle look along the forest at walking height (hybrid), plus a compare row
	cam.position = Vector3(0, 1.7, 8)
	cam.look_at(Vector3(0, 4.5, -70))
	await _build("hybrid")
	await get_tree().create_timer(0.5).timeout
	await H.shot(get_tree(), cap_dir, "impostors_forest_hybrid_lowcam")
	_compare_row()
	await get_tree().create_timer(1.0).timeout
	await H.shot(get_tree(), cap_dir, "impostors_compare_row")
	var f := FileAccess.open(cap_dir.path_join("impostors_perf.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	print("\n".join(log_lines))
	get_tree().quit()
