extends Node3D
## WeaponTrail perf + visual test.
##   Shots (windowed, fixed 30 fps, NOT headless):
##     Godot --path kingdom --rendering-method mobile --resolution 1280x720 --fixed-fps 30 \
##       res://tools_qa/combat_audit/trail_bench.tscn -- --shots=<abs dir> [--n=1] [--els=fire,ice,light] [--tier=2]
##   Bench (fixed 60 fps stepping, as fast as possible):
##     Godot --path kingdom --rendering-method mobile --resolution 640x360 --fixed-fps 60 \
##       res://tools_qa/combat_audit/trail_bench.tscn -- --bench=<abs json> --n=1,4,8

const CLIP := "Sword_Regular_A"
const RATE := 1.7
const ELEMENTS := ["light", "fire", "ice", "lightning", "earth", "wind", "water", "dark"]

var args := {}
var chars: Array[Node3D] = []
var aps: Array[AnimationPlayer] = []
var trails: Array[WeaponTrail] = []
var cam: Camera3D
var use_trails := true
var running := false
var swing_count := 0
var next_play := 0.0
var clock := 0.0
const GAP := 0.6


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	process_priority = -100
	_build_stage()
	if args.has("bench"):
		_run_bench.call_deferred()
	else:
		_run_shots.call_deferred()


func _set_tier(t: int) -> void:
	var q := get_node_or_null("/root/Quality")
	if q:
		q.set("tier", t)


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.6, 0.35)
	ground.material_override = gm
	add_child(ground)
	cam = Camera3D.new()
	add_child(cam)


func _spawn(n: int, els: Array) -> void:
	for c in chars:
		c.free()
	chars.clear()
	aps.clear()
	trails.clear()
	var spacing := 1.7
	for i in n:
		var body := Assets.character("Player", 1.8, ["1H_Sword", "Round_Shield"])
		add_child(body)
		body.position = Vector3((i - (n - 1) * 0.5) * spacing, 0, 0)
		var ap := Assets.animation_player(body)
		chars.append(body)
		aps.append(ap)
		var t: WeaponTrail = null
		if use_trails:
			t = WeaponTrail.attach(body, els[i % els.size()])
		trails.append(t)
	var w := maxf(n * spacing, 3.0)
	cam.fov = 40
	cam.position = Vector3(0.4, 1.3, w * 1.25 + 1.2)
	cam.look_at(Vector3(0.0, 1.05, 0.0))


func _play(i: int) -> void:
	var ap := aps[i]
	if ap == null:
		return
	ap.play(CLIP, -1, RATE)
	if swing_count == 0 and ap.has_animation(CLIP):
		var an := ap.get_animation(CLIP)
		print("CLIP length %.3f loop=%d" % [an.length, an.loop_mode])
	if trails[i]:
		trails[i].swing(CLIP, RATE)
	swing_count += 1


func _process(d: float) -> void:
	if not running:
		return
	clock += d
	if clock >= next_play:
		next_play = clock + 0.433 / RATE + GAP
		_restart_all()


func _restart_all() -> void:
	for i in chars.size():
		_play(i)


# ---- shots -----------------------------------------------------------------------------

func _run_shots() -> void:
	var out := String(args["shots"])
	DirAccess.make_dir_recursive_absolute(out)
	_set_tier(int(args.get("tier", 2)))
	var n := int(args.get("n", 1))
	var els: Array = String(args.get("els", "fire,ice,lightning")).split(",")
	_spawn(n, els)
	if n == 1:
		cam.position = Vector3(1.3, 1.4, 2.6)
		cam.look_at(Vector3(0.0, 1.15, 0.2))
	WeaponTrail.warmup(8)
	running = true
	for i in 45:
		await get_tree().process_frame
	# wait for a fresh replay, then capture 24 consecutive frames from just before the swing
	var start_count := swing_count
	while swing_count < start_count + n:
		await get_tree().process_frame
	for f in 24:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join("f_%08d.png" % f))
	print("SHOTS_DONE active=%d" % WeaponTrail.active_count())
	get_tree().quit()


# ---- bench -----------------------------------------------------------------------------

func _run_bench() -> void:
	var counts := []
	for s: String in String(args.get("n", "1,4,8")).split(","):
		counts.append(int(s))
	var results := {}
	for tier in [0, 2]:
		_set_tier(tier)
		for n: int in counts:
			for with_t in [false, true]:
				use_trails = with_t
				_spawn(n, ELEMENTS)
				WeaponTrail.warmup(8)
				running = false
				for i in 20:
					await get_tree().process_frame
				running = true
				_restart_all()
				for i in 60:
					await get_tree().process_frame
				var frame_us: Array[float] = []
				var per_frame_trail_us: Array[float] = []
				var last_us := Time.get_ticks_usec()
				var base_us: Array[int] = []
				var base_fr: Array[int] = []
				var base_pose: Array[int] = []
				for t in trails:
					base_us.append(t.t_process_usec if t else 0)
					base_fr.append(t.t_frames if t else 0)
					base_pose.append(t.t_pose_usec if t else 0)
				var prev_sum := 0
				var active_frames := 0
				for f in 300:
					await get_tree().process_frame
					var now := Time.get_ticks_usec()
					frame_us.append(float(now - last_us))
					last_us = now
					var sum := 0
					for i in trails.size():
						if trails[i]:
							sum += trails[i].t_process_usec - base_us[i]
					per_frame_trail_us.append(float(sum - prev_sum))
					prev_sum = sum
				var pose_us := 0
				for i in trails.size():
					if trails[i]:
						active_frames += trails[i].t_frames - base_fr[i]
						pose_us += trails[i].t_pose_usec - base_pose[i]
				var key := "%s_N%d_%s" % ["LOW" if tier == 0 else "HIGH", n, "trails" if with_t else "notrails"]
				var r := {"frame_ms_avg": _avg(frame_us) / 1000.0, "frame_ms_p99": _p99(frame_us) / 1000.0}
				if with_t:
					r["trail_ms_per_frame_total_avg"] = _avg(per_frame_trail_us) / 1000.0
					r["trail_ms_per_frame_total_p99"] = _p99(per_frame_trail_us) / 1000.0
					r["ms_per_active_trail_frame"] = (float(prev_sum) / maxf(active_frames, 1)) / 1000.0
					r["ms_per_active_trail_frame_ex_pose"] = (float(prev_sum - pose_us) / maxf(active_frames, 1)) / 1000.0
					r["active_trail_frames_of_possible"] = "%d/%d" % [active_frames, 300 * n]
					r["ms_per_trail_per_frame_all_cycle"] = _avg(per_frame_trail_us) / 1000.0 / n
				results[key] = r
				print(key, " ", r)
	results["mesh_update_compare"] = _compare_update_paths()
	var f := FileAccess.open(String(args["bench"]), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("BENCH_DONE")
	get_tree().quit()


func _avg(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


func _p99(a: Array[float]) -> float:
	var b := a.duplicate()
	b.sort()
	return b[int(b.size() * 0.99)] if b.size() > 0 else 0.0


## Synthetic: write 27 columns x 3 rows of positions+colours, ImmediateMesh vs region update.
func _compare_update_paths() -> Dictionary:
	var cols := 27
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	var iters := 2000
	var t0 := Time.get_ticks_usec()
	for k in iters:
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for c in cols:
			for r in 3:
				im.surface_set_color(Color(1, 0.5, 0.2, 0.5))
				im.surface_add_vertex(Vector3(c * 0.1, r * 0.3, k * 0.001))
		im.surface_end()
	var t_im := float(Time.get_ticks_usec() - t0) / iters
	mi.queue_free()
	WeaponTrail.warmup(1)
	var r := WeaponTrail._pool[0]
	var fv := PackedVector3Array()
	fv.resize(WeaponTrail.MAX_COLS * 3)
	var fc := PackedInt32Array()
	fc.resize(WeaponTrail.MAX_COLS * 3)
	var rid := r.mesh.get_rid()
	t0 = Time.get_ticks_usec()
	for k in iters:
		for c in cols:
			for row in 3:
				fv[c * 3 + row] = Vector3(c * 0.1, row * 0.3, k * 0.001)
				fc[c * 3 + row] = 0x80ffaa44
		RenderingServer.mesh_surface_update_vertex_region(rid, 0, 0, fv.to_byte_array())
		RenderingServer.mesh_surface_update_attribute_region(rid, 0, 0, fc.to_byte_array())
	var t_rg := float(Time.get_ticks_usec() - t0) / iters
	return {"immediate_mesh_us_per_update": t_im, "region_update_us_per_update": t_rg}
