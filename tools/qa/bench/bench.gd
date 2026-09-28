extends SceneTree
## Frame-time benchmark for Rising Ashes. Boots the real game (scenes/main.tscn),
## teleports to a scene, lets streaming settle, then records frame times, GPU time
## of the world viewport and the render monitors (draw calls, primitives, objects).
##
## Run from the repo root (a real GPU window; see run.sh):
##   godot --path kingdom -s <abs>/tools/qa/bench/bench.gd -- --adult --skipintro \
##         --quality=low --scene=village [--seconds=10] [--png=<file>] [--csv=<file>] [--uncapped]
## Add `--rendering-method gl_compatibility` (engine arg, before --) for the Compatibility renderer.
## Scenes: village (Ashford plaza, street level), city (capital gate street),
##         battle (24 soldiers charging the raider camp), aerial (over Ashford).

var main: Control
var args := {}
var phase := "boot"
var t := 0.0
var frames: PackedFloat32Array = []
var gpu: PackedFloat32Array = []
var cpu: PackedFloat32Array = []
var draws: PackedFloat32Array = []
var prims: PackedFloat32Array = []
var objs: PackedFloat32Array = []
var world_vp: SubViewport


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._loading.visible:
				_stage()
				phase = "settle"
				t = 0.0
		"settle":
			if t > float(args.get("settle", "6")):
				phase = "measure"
				t = 0.0
				if args.has("uncapped"):
					Engine.max_fps = 0
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"gpuprof":
			_gpuprof_step(delta)
		"profile":
			_profile_step(delta)
		"finish":
			_finish()
			phase = "done"
		"measure":
			frames.append(delta * 1000.0)
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			if world_vp:
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(world_vp.get_viewport_rid()))
			if t > float(args.get("seconds", "10")) and args.has("gpuprof"):
				phase = "gpuprof"
				_gpuprof_start()
			elif t > float(args.get("seconds", "10")) and args.has("profile"):
				phase = "profile"
				_profile_start()
			elif t > float(args.get("seconds", "10")):
				_finish()
				phase = "done"
	return false


func _stage() -> void:
	world_vp = main.viewport
	RenderingServer.viewport_set_measure_render_time(world_vp.get_viewport_rid(), true)
	var scene: String = args.get("scene", "village")
	_al("WorldSim").time_of_day = float(args.get("hour", "15.0"))
	match scene:
		"village":
			main._teleport(Vector2(1.0, 7.5), 0.0)
			main.player.set_camera(0.25, -0.12)
		"city":
			var cap: Dictionary = _wg().settlements[1]
			var cp: Vector2 = cap["pos"]
			var gate: float = cap["plan"]["gates"][0]
			var sp: Vector2 = cp + Vector2(cos(gate), sin(gate)) * (cap["plan"]["plaza_r"] + 30.0)
			main._teleport(sp, 0.0)
			var look: Vector2 = cp - sp
			main.player.set_camera(atan2(-look.x, -look.y), -0.12)
		"battle":
			_al("Game").rank = 2
			var p := Vector2(main.FIRST_CAMP.x - 22, main.FIRST_CAMP.y + 6)
			main._teleport(p, 0.0)
			main._recruit(24)
			for s in main.army.soldiers:
				s.global_position = main.player.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			main.army.command(2)   # Squad.Order.CHARGE
			main.player.set_camera(-PI * 0.5 + 0.35, -0.25)
		"aerial":
			main._teleport(Vector2(20, 26), PI * 0.2)
			main.player.zoom(1)
			main.player.zoom(1)
	if args.has("ui"):
		# --ui=settings|credits: open that screen (HUD stays visible) for UI screenshots.
		if args["ui"] == "credits":
			load("res://scripts/ui/credits_screen.gd").open(main.hud)
		else:
			main.hud.show_menu(load("res://scripts/ui/settings_menu.gd").menu.bind(main.hud))
	elif args.has("png"):
		main.hud.visible = false


func _finish() -> void:
	var r := {
		"scene": args.get("scene", "village"), "quality": _al("Quality").tier_name(), "renderer": _al("Quality").renderer(),
		"gpu_name": RenderingServer.get_video_adapter_name(),
		"size": "%dx%d" % [world_vp.size.x, world_vp.size.y], "scale": world_vp.scaling_3d_scale,
		"frames": frames.size(), "fps_avg": 1000.0 / _mean(frames), "ms_avg": _mean(frames),
		"ms_p95": _pct(frames, 0.95), "ms_p99": _pct(frames, 0.99),
		"gpu_ms_avg": _mean(gpu), "cpu_process_ms": _mean(cpu),
		"draw_calls": _mean(draws), "primitives": _mean(prims), "objects": _mean(objs),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"npc_full": main.population.full_count, "npc_sprites": main.population.sprite_count,
		"chunks": main.terrain.loaded_count(),
	}
	if args.has("textures"):
		_texture_census()
	if args.has("census"):
		_census()
	if args.has("drawcensus"):
		_draw_census()
	var line := JSON.stringify(r)
	print("BENCH ", line)
	if args.has("csv"):
		var path: String = args["csv"]
		var exists := FileAccess.file_exists(path)
		var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(line)
	if args.has("png"):
		var img := root.get_texture().get_image()
		img.save_png(args["png"])
		print("Saved ", args["png"])
	await _shutdown()


## See perf_visual.gd's _shutdown() for why: quitting while main.tscn is still live
## races WorkerThreadPool/threaded-load cleanup against RenderingServer teardown and
## produced the ntdll heap-corruption crashes logged in docs/qa/stability.md.
func _shutdown() -> void:
	if main:
		main.queue_free()
		main = null
	for i in 10:
		await process_frame
	quit()


static func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(b.size() * p))]


## Autoloads by path: `-s` scripts are compiled before autoload names exist.
func _al(n: String) -> Node:
	return root.get_node("/root/" + n)


## Game classes are loaded at runtime for the same reason.
func _wg() -> Script:
	return load("res://scripts/world/world_gen.gd")


## --census: LOD0 triangles in view range, grouped by mesh, biggest first. Shows
## where the primitives come from (before LOD/culling; shadow passes add more).
func _census() -> void:
	var cam := world_vp.get_camera_3d()
	var cp := cam.global_position
	var groups := {}
	var shadow_tris := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var count := 1
		var positions: Array[Vector3] = []
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			positions.append(g.global_position)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
			for i in count:
				positions.append(g.global_transform * mm.get_instance_transform(i).origin)
		if mesh == null:
			continue
		var tris := 0
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s) if mesh is ArrayMesh else []
			if arr.is_empty():
				continue
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var end := g.visibility_range_end
		var begin := g.visibility_range_begin
		var inside := 0
		for p in positions:
			var d := p.distance_to(cp)
			if (end <= 0.0 or d < end) and d >= begin and d < 900.0:
				inside += 1
		if inside == 0:
			continue
		var key := mesh.resource_path.get_file() if mesh.resource_path != "" else "runtime mesh #%d under %s" % [mesh.get_instance_id() % 100000, String(g.get_parent().name).get_slice("_", 0)]
		key += " (%d tris)" % tris
		key = "%s [%s]" % [key, g.get_class()]
		groups[key] = groups.get(key, 0) + tris * inside
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_tris[key] = true
	var keys := groups.keys()
	keys.sort_custom(func(a, b) -> bool: return groups[a] > groups[b])
	var total := 0
	for k in keys:
		total += groups[k]
	print("CENSUS total LOD0 tris in range: %d" % total)
	for k in keys.slice(0, int(args.get("census_n", "40"))):
		print("CENSUS %9d  %s%s" % [groups[k], k, "  (casts shadow)" if shadow_tris.has(k) else ""])


## --drawcensus: geometry instances the camera draws (in frustum and visibility
## range), grouped by owner and mesh, with their surface count (~ draw calls in the
## colour pass; shadow and depth passes add more). Shows what to merge.
func _draw_census() -> void:
	var cam := world_vp.get_camera_3d()
	var cp := cam.global_position
	var planes := cam.get_frustum()
	var names := {}
	var cache: Dictionary = load("res://scripts/world/assets.gd").get("_building_cache")
	for k in cache:
		names[cache[k]] = String(k)
	var groups := {}
	var tri_groups := {}
	var by_owner := {}
	var total := 0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var d := box.get_center().distance_to(cp)
		if (g.visibility_range_end > 0.0 and d > g.visibility_range_end) or d < g.visibility_range_begin:
			continue
		var inside := true
		for pl in planes:
			var c := box.get_center()
			var e := box.size * 0.5
			var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
			if pl.distance_to(c) > r:
				inside = false
				break
		if not inside:
			continue
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		var surf := mesh.get_surface_count() if mesh else 1
		var owner := "?"
		var p := g.get_parent()
		while p != null and p != main.world:
			owner = String(p.name).get_slice("_", 0).get_slice("@", 0)
			if p.get_parent() == main.world or p.get_parent() == main.terrain or p.get_parent() == main.settlements:
				break
			p = p.get_parent()
		owner = owner.rstrip("0123456789")
		var mname := (mesh.resource_path.get_file() if mesh and mesh.resource_path != "" else (mesh.get_class() if mesh else g.get_class()))
		if mesh and names.has(mesh):
			mname = names[mesh]
		var inst := 1
		if g is MultiMeshInstance3D:
			var mmx := (g as MultiMeshInstance3D).multimesh
			inst = mmx.instance_count if mmx.visible_instance_count < 0 else mmx.visible_instance_count
		var tris := 0
		if mesh is ArrayMesh:
			for si in mesh.get_surface_count():
				var ia: PackedInt32Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
				tris += ia.size() / 3 if ia.size() > 0 else (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var key := "%-14s %-22s %-34s %6d tris x%-4d" % [owner.left(14), g.get_class().left(22), mname.left(34), tris, inst]
		groups[key] = groups.get(key, 0) + surf
		tri_groups[key] = tri_groups.get(key, 0) + tris * inst
		by_owner[owner] = by_owner.get(owner, 0) + surf
		total += surf
	print("DRAWS total surfaces in view: %d" % total)
	for o in by_owner:
		print("DRAWS owner %-14s %d" % [o, by_owner[o]])
	var keys := groups.keys()
	keys.sort_custom(func(a, b) -> bool: return groups[a] > groups[b])
	for k in keys.slice(0, 30):
		print("DRAWS %4d  %s" % [groups[k], k])
	keys.sort_custom(func(a, b) -> bool: return tri_groups[a] > tri_groups[b])
	var tsum := 0
	for k in keys:
		tsum += tri_groups[k]
	print("TRIS in view (LOD0 of each in-range level, before mesh LOD): %d" % tsum)
	for k in keys.slice(0, 30):
		print("TRIS %8d  %s" % [tri_groups[k], k])


## --profile: after measuring, switch off _process/_physics_process on one system
## at a time for 2 s and report how much frame time it saves (main-thread cost).
var _prof_targets: Array = []
var _prof_i := -1
var _prof_t := 0.0
var _prof_acc := 0.0
var _prof_n := 0
var _prof_base := 0.0


func _profile_start() -> void:
	for n in ["WorldSim", "Life", "Frontier", "Audio"]:
		_prof_targets.append(root.get_node("/root/" + n))
	for c in main.world.get_children():
		if c.is_processing() or c.is_physics_processing() or c.get_child_count() > 0:
			_prof_targets.append(c)
	_prof_base = _mean(frames)
	_prof_i = -1
	_prof_next()


func _prof_next() -> void:
	if _prof_i >= 0:
		var n: Node = _prof_targets[_prof_i]
		var sn: String = n.get_script().resource_path.get_file() if n.get_script() else n.get_class()
		print("PROFILE %-28s %-26s saves %6.1f ms/frame (%.1f -> %.1f)" % [String(n.name).left(28), sn.left(26), _prof_base - _prof_acc / maxi(_prof_n, 1), _prof_base, _prof_acc / maxi(_prof_n, 1)])
		n.process_mode = Node.PROCESS_MODE_INHERIT
	_prof_i += 1
	_prof_t = 0.0
	_prof_acc = 0.0
	_prof_n = 0
	if _prof_i >= _prof_targets.size():
		phase = "finish"
		return
	(_prof_targets[_prof_i] as Node).process_mode = Node.PROCESS_MODE_DISABLED


func _profile_step(delta: float) -> void:
	_prof_t += delta
	if _prof_t > 0.7:
		_prof_acc += delta * 1000.0
		_prof_n += 1
	if _prof_t > 2.7:
		_prof_next()


## --gpuprof: hide one layer of the world at a time for 2 s and report the GPU
## time of the world viewport without it (what that layer costs to draw).
var _gp_tests: Array = []
var _gp_i := -1
var _gp_t := 0.0
var _gp_acc := 0.0
var _gp_n := 0
var _gp_undo := Callable()


func _gpuprof_start() -> void:
	var terr: Node = main.terrain
	var env: Environment = main.env
	var sun: DirectionalLight3D = main.sun
	var set_vis := func(nodes: Array, v: bool) -> void:
		for n in nodes:
			(n as Node3D).visible = v
	var chunk_parts := func(name_filter: String) -> Array:
		var out := []
		for c in terr.get_children():
			for p in c.get_children():
				if p is Node3D and (name_filter == "" or String(p.name) == name_filter):
					out.append(p)
		return out
	var trees := func() -> Array:
		var out := []
		for c in terr.get_children():
			for p in c.get_children():
				if p is MultiMeshInstance3D:
					out.append(p)
		return out
	_gp_tests = [
		["baseline", func() -> void: pass, func() -> void: pass],
		["terrain ground", func() -> void: set_vis.call(chunk_parts.call("Ground"), false), func() -> void: set_vis.call(chunk_parts.call("Ground"), true)],
		["grass", func() -> void: set_vis.call(chunk_parts.call("Grass"), false), func() -> void: set_vis.call(chunk_parts.call("Grass"), true)],
		["trees+scatter", func() -> void: set_vis.call(trees.call(), false), func() -> void: set_vis.call(trees.call(), true)],
		["water", func() -> void: main.water.visible = false, func() -> void: main.water.visible = true],
		["settlements", func() -> void: main.settlements.visible = false, func() -> void: main.settlements.visible = true],
		["people", func() -> void: main.population.visible = false, func() -> void: main.population.visible = true],
		["sun shadows", func() -> void: sun.shadow_enabled = false, func() -> void: sun.shadow_enabled = main.sun.get_meta("q_shadow", true) and _al("Quality").value("shadow") > 0],
		["sky -> clear colour", func() -> void: env.background_mode = Environment.BG_COLOR, func() -> void: env.background_mode = Environment.BG_SKY],
		["post (glow/ssao/fog)", func() -> void:
			env.set_meta("b_post", [env.glow_enabled, env.ssao_enabled, env.fog_enabled, env.volumetric_fog_enabled, env.ssil_enabled, env.sdfgi_enabled])
			env.glow_enabled = false; env.ssao_enabled = false; env.fog_enabled = false; env.volumetric_fog_enabled = false; env.ssil_enabled = false; env.sdfgi_enabled = false,
			func() -> void:
				var b: Array = env.get_meta("b_post")
				env.glow_enabled = b[0]; env.ssao_enabled = b[1]; env.fog_enabled = b[2]; env.volumetric_fog_enabled = b[3]; env.ssil_enabled = b[4]; env.sdfgi_enabled = b[5]],
	]
	_gp_i = -1
	_gpuprof_next()


func _gpuprof_next() -> void:
	if _gp_i >= 0:
		print("GPUPROF without %-22s gpu %6.2f ms   frame %6.2f ms   prims %8d   draws %5d" % [_gp_tests[_gp_i][0], _gp_acc / maxi(_gp_n, 1), _prof_acc / maxi(_gp_n, 1), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		(_gp_tests[_gp_i][2] as Callable).call()
	_gp_i += 1
	_gp_t = 0.0
	_gp_acc = 0.0
	_prof_acc = 0.0
	_gp_n = 0
	if _gp_i >= _gp_tests.size():
		phase = "finish"
		return
	(_gp_tests[_gp_i][1] as Callable).call()


func _gpuprof_step(delta: float) -> void:
	_gp_t += delta
	if _gp_t > 0.6:
		_gp_acc += RenderingServer.viewport_get_measured_render_time_gpu(world_vp.get_viewport_rid())
		_prof_acc += delta * 1000.0
		_gp_n += 1
	if _gp_t > 2.6:
		_gpuprof_next()


## --textures: textures referenced by materials in the scene, largest first
## (pixels incl. mips; ~1 byte/px on phones with ASTC 4x4 / ETC2 RGBA).
func _texture_census() -> void:
	var seen := {}
	var add_mat := func(m: Material) -> void:
		if m == null:
			return
		var props := m.get_property_list()
		if m is ShaderMaterial and (m as ShaderMaterial).shader:
			for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
				var v: Variant = (m as ShaderMaterial).get_shader_parameter(u["name"])
				if v is Texture2D:
					seen[v] = true
		for p in props:
			if p["type"] == TYPE_OBJECT:
				var v: Variant = m.get(p["name"])
				if v is Texture2D:
					seen[v] = true
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		add_mat.call(g.material_override)
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			for s in (g as MeshInstance3D).get_surface_override_material_count():
				add_mat.call((g as MeshInstance3D).get_surface_override_material(s))
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for s in mesh.get_surface_count():
				add_mat.call(mesh.surface_get_material(s))
	for e in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (e as WorldEnvironment).environment
		if env and env.sky:
			add_mat.call(env.sky.sky_material)
	var list := seen.keys()
	list.sort_custom(func(a, b) -> bool: return a.get_width() * a.get_height() > b.get_width() * b.get_height())
	var total := 0.0
	for t in list:
		total += t.get_width() * t.get_height() * 1.33
	print("TEXTURES %d textures in use, %.0f Mpx incl. mips (~%.0f MB at 1 B/px ASTC/ETC2)" % [list.size(), total / 1e6, total / 1048576.0])
	# What a phone export holds: addons/mobile_texture_limit caps res://assets/ textures at
	# 1024 px (512 for scans/animals); lossless (non-VRAM) textures cost 4 B/px.
	var mobile := 0.0
	var lossless := 0
	for t in list:
		var path: String = t.resource_path
		var cap := 512 if (path.begins_with("res://assets/generated/scan/") or path.begins_with("res://assets/incoming/animals/")) else 1024
		var k := minf(1.0, float(cap) / maxf(t.get_width(), t.get_height())) if path.begins_with("res://assets/") and not path.ends_with(".hdr") else 1.0
		var bpp := 1.0
		if t is CompressedTexture2D and (t as CompressedTexture2D).get_image() and not (t as CompressedTexture2D).get_image().is_compressed():
			bpp = 4.0
			lossless += 1
		mobile += t.get_width() * t.get_height() * k * k * 1.33 * bpp
	print("TEXTURES mobile export estimate: ~%.0f MB (%d uncompressed textures at 4 B/px)" % [mobile / 1048576.0, lossless])
	for t in list.slice(0, int(args.get("tex_n", "40"))):
		print("TEXTURES %5dx%-5d %s" % [t.get_width(), t.get_height(), t.resource_path if t.resource_path != "" else t.get_class()])
