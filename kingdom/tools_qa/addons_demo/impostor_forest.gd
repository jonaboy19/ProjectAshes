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
var FADE := 5.0   # dithered crossfade length (m) between full mesh and impostor, centred on NEAR

# kind -> [source scene, impostor scene, count share]
const KINDS := {
	"oak1": [N + "CommonTree_1.gltf", IMP + "oak1_octa.tscn", 0.4],
	"oak4": [N + "CommonTree_4.gltf", IMP + "oak4_octa.tscn", 0.4],
	"twisted": [N + "TwistedTree_1.gltf", IMP + "twisted_octa.tscn", 0.2],
	"village_house": [G + "village_house_a.glb", IMP + "village_house_octa.tscn", 0.0],
}

var cap_dir := ""
var fly_mode := ""   # --fly=fade|hard : camera flies through the 45 m switch (use with --write-movie)
var fly_speed := 7.0
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
		if a.begins_with("--fly="): fly_mode = a.substr(6)
		if a.begins_with("--fade="): FADE = float(a.substr(7))
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
	if fly_mode != "":
		_cluster()   # sparse, readable test set: a row of trees and two houses 70 m ahead; the camera flies through the 45 m switch
		fly_speed = 13.0
		cam.position = Vector3(0, 2.4, 10)
		cam.look_at(Vector3(0, 5.0, -70))
		_build("fade" if fly_mode == "fade" else "hard")
		return
	if cap_dir == "":
		H.label(self, "1 full meshes | 2 impostors | 3 hybrid (<45 m full) | 4 compare row")
		_build("hybrid")
		return
	_run_capture()

func _cluster() -> void:
	for k in KINDS:
		placements[k] = []
	var i := 0
	for x in range(-16, 17, 4):
		var kind: String = ["oak1", "oak4", "twisted"][i % 3]
		var b := Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * (0.55 if kind == "twisted" else 1.0))
		placements[kind].append(Transform3D(b, Vector3(x, 0, -70 + (i % 2) * 6.0)))
		i += 1
	placements["village_house"].append(Transform3D(Basis(Vector3.UP, 0.4), Vector3(-9, 0, -64)))
	placements["village_house"].append(Transform3D(Basis(Vector3.UP, -0.3), Vector3(10, 0, -66)))

func _process(delta: float) -> void:
	if fly_mode != "":
		cam.position.z -= fly_speed * delta

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

func _mm(mesh: Mesh, xforms: Array, mat: Material, cast_shadows: bool, margin := 0.0, cell_center := Vector3.INF) -> MultiMeshInstance3D:
	# with a cell_center the MultiMeshInstance3D sits at the cell centre (visibility ranges measure from the node), instances are local
	if cell_center != Vector3.INF:
		var moved: Array = []
		for t: Transform3D in xforms:
			moved.append(Transform3D(t.basis, t.origin - cell_center))
		xforms = moved
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
	if cell_center != Vector3.INF:
		mi.position = cell_center
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
		var imp_center: Vector3 = (imp_mat as ShaderMaterial).get_shader_parameter("center")
		var imp_mat_i: Material = imp_mat
		if mode == "fade":
			imp_mat_i = (imp_mat as ShaderMaterial).duplicate()
			(imp_mat_i as ShaderMaterial).set_shader_parameter("fade_in_end", NEAR + FADE * 0.5)
			(imp_mat_i as ShaderMaterial).set_shader_parameter("fade_in_len", FADE)
		# bucket by cell so every MultiMesh is frustum-culled as a unit (same as the game's cell batching)
		var full_cells := {}
		var imp_cells := {}
		for t: Transform3D in placements[kind]:
			var use_full := mode == "mesh" or (mode == "hybrid" and t.origin.distance_to(cpos) < NEAR)
			var key := Vector2i(int(floor(t.origin.x / CELL)), int(floor(t.origin.z / CELL)))
			if mode == "fade" or mode == "hard":   # every cell exists twice, the engine's visibility ranges do the dithered crossfade
				for cells in [full_cells, imp_cells]:
					if not cells.has(key):
						cells[key] = []
					cells[key].append(t)
				continue
			var cells := full_cells if use_full else imp_cells
			if not cells.has(key):
				cells[key] = []
			cells[key].append(t)
		for key in full_cells:
			for m in mesh_cache[kind]:
				var xs: Array = []
				for t: Transform3D in full_cells[key]:
					xs.append(t * (m[1] as Transform3D))
				var mesh_i: Mesh = m[0]
				if mode == "fade":
					mesh_i = _fade_mesh(m[0], imp_center)
				var mmi := _mm(mesh_i, xs, null, true, 0.0, _cell_center(key) if mode in ["fade", "hard"] else Vector3.INF)
				if mode == "fade":
					mmi.visibility_range_end = NEAR + FADE * 0.5 + CELL * 0.75
				elif mode == "hard":
					mmi.visibility_range_end = NEAR
				root_group.add_child(mmi)
				stats["multimeshes"] += 1
			stats["instances_full"] += full_cells[key].size()
		for key in imp_cells:
			var imi := _mm(imp_mesh, imp_cells[key], imp_mat_i, false, margin, _cell_center(key) if mode in ["fade", "hard"] else Vector3.INF)
			if mode == "fade":
				imi.visibility_range_begin = maxf(0.0, NEAR - FADE * 0.5 - CELL * 0.75)
			elif mode == "hard":
				imi.visibility_range_begin = NEAR
			root_group.add_child(imi)
			stats["multimeshes"] += 1
			stats["instances_imp"] += imp_cells[key].size()
		imp_scene.free()
	await get_tree().process_frame
	return stats

func _cell_center(key: Vector2i) -> Vector3:
	return Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)

## Crossfade: the mesh dithers out over [NEAR-FADE/2, NEAR+FADE/2] (mesh_fade.gdshader, per instance) while the impostor dithers in over the same band with
## complementary noise (fade_in_end / fade_in_len uniforms of impostor_octa.gdshader). Cells only get hard visibility ranges for culling.
func _fade_mesh(mesh: Mesh, center: Vector3) -> Mesh:
	var m2: Mesh = mesh.duplicate()
	var sh := load("res://tools_qa/addons_demo/mesh_fade.gdshader") as Shader
	for i in m2.get_surface_count():
		var src := m2.surface_get_material(i)
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			if b.albedo_texture:
				sm.set_shader_parameter("albedo_tex", b.albedo_texture)
			sm.set_shader_parameter("albedo", b.albedo_color)
			sm.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
			sm.set_shader_parameter("roughness", b.roughness)
		sm.set_shader_parameter("center", center)
		sm.set_shader_parameter("fade_out_start", NEAR - FADE * 0.5)
		sm.set_shader_parameter("fade_len", FADE)
		m2.surface_set_material(i, sm)
	return m2

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
