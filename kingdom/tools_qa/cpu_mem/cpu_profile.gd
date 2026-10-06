extends Node
## CPU profile by script (release QA, cloud lane: CPU / memory / save only).
## Walks the player through Ashford, Thornfield and the wilds and times every script's `_process` / `_physics_process`
## by taking those callbacks over: each node with a script callback gets `set_process(false)` and this node calls the
## callback itself between two Time.get_ticks_usec reads (so a villager's, the realm pump's or the audio director's cost
## is attributed to its script path). Nodes that switch themselves on again are handed back to the engine. Signal and
## timer handlers are not attributed: they show up as "other" (frame minus attributed minus engine process monitors).
##   godot --headless --path kingdom -- --adult --quality=low --qa=res://tools_qa/cpu_mem/cpu_profile.gd \
##       [--seconds=30] [--out=/path.json] [--phases=ashford,thornfield,wilds] [--raw]
## --census: after the route, print the memory census (tools_qa/cpu_mem/mem_census.gd).
## --raw: do not take callbacks over (frame time and monitors only: the baseline the instrumentation is compared with).
## Per-phase table: ms per rendered frame (process + the physics ticks that ran inside that frame), mean and p95.
const Probe := preload("res://scripts/core/perf_probe.gd")
const SPEED := 5.5
const SETTLE := 10.0
const TOP := 20
var main: Node
var dur := 30.0
var out := ""
var raw := false
var census := false
var phases: Array = ["ashford", "thornfield", "wilds"]
var phase_i := -1
var phase := ""
var t := 0.0
var leg_from := Vector2.ZERO
var leg_dir := Vector2.RIGHT
var leg_len := 40.0
var along := 0.0
var ring := false
var ring_c := Vector2.ZERO
var ring_r := 20.0
var ring_a := 0.0
var reg := {}                  # instance id -> [node, key, has_proc, has_phys]
var scan_t := 0.0
var frame_us := {}             # key -> usec this frame
var series := {}               # key -> PackedFloat32Array of ms per frame (only frames where the key ran)
var frames := PackedFloat32Array()
var eng_proc := PackedFloat32Array()
var eng_phys := PackedFloat32Array()
var attributed := PackedFloat32Array()
var results := {}
var meta := {}
var _last_us := 0
var ticks := 0
var tick_script_us := 0


func run(m: Node) -> void:
	main = m
	for raw_a in Array(OS.get_cmdline_user_args()):
		var a := String(raw_a)
		if a.begins_with("--seconds="):
			dur = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--phases="):
			phases = Array(a.get_slice("=", 1).split(","))
		elif a == "--raw":
			raw = true
		elif a == "--census":
			census = true
	WorldSim.time_of_day = 15.0
	Engine.max_fps = 0
	# A headless window never has focus, so the main loop sleeps up to low_processor_usage_mode_sleep_usec (6.9 ms by default,
	# i.e. a 144 fps floor on every frame) whatever Engine.max_fps says: without this the frame time is the sleep, not the work.
	OS.low_processor_usage_mode_sleep_usec = 0
	_next_phase()


func _settlement(name_part: String) -> Dictionary:
	for s: Dictionary in WorldGen.settlements:
		if String(s["name"]).to_lower().contains(name_part):
			return s
	return WorldGen.settlements[0]


func _next_phase() -> void:
	phase_i += 1
	if phase_i >= phases.size():
		_finish()
		return
	phase = String(phases[phase_i])
	t = 0.0
	along = 0.0
	_clear_series()
	match phase:
		"ashford", "thornfield":
			var s: Dictionary = WorldGen.settlements[0] if phase == "ashford" else _settlement("thornfield")
			ring = true
			ring_c = s["pos"]
			ring_r = float(s["plan"]["plaza_r"]) + 10.0
			ring_a = 0.0
			var p := ring_c + Vector2(ring_r, 0.0)
			main.call("_teleport", p, 0.0)
		"wilds":
			ring = false
			var th := _settlement("thornfield")
			var c: Vector2 = th["pos"]
			var best := -1.0
			for i in 16:
				var d := Vector2.from_angle(TAU * i / 16.0)
				var dens := 0.0
				for k in 30:
					var q := c + d * (float(th["radius"]) + 40.0 + k * 30.0)
					dens += WorldGen.forest_density(q.x, q.y)
				if dens > best:
					best = dens
					leg_dir = d
			leg_from = c + leg_dir * (float(th["radius"]) + 80.0)
			main.call("_teleport", leg_from, atan2(-leg_dir.x, -leg_dir.y))
	print("CPUPROF phase %s start" % phase)


func _clear_series() -> void:
	series.clear()
	frames = PackedFloat32Array()
	eng_proc = PackedFloat32Array()
	eng_phys = PackedFloat32Array()
	attributed = PackedFloat32Array()
	frame_us.clear()
	Probe.reset()
	ticks = 0
	tick_script_us = 0


func _scan() -> void:
	var seen := {}
	for n in get_tree().root.find_children("*", "", true, false):
		var node := n as Node
		if node == self or node == main or node.get_script() == null or not node.is_inside_tree():
			continue
		var id := node.get_instance_id()
		seen[id] = true
		if reg.has(id):
			var e: Array = reg[id]
			if node.is_processing() or node.is_physics_processing():   # woke itself: the engine drives it again
				if e[2] and node.is_processing():
					e[2] = false
				if e[3] and node.is_physics_processing():
					e[3] = false
			continue
		var hp := node.is_processing() and node.has_method("_process")
		var hy := node.is_physics_processing() and node.has_method("_physics_process")
		if not hp and not hy:
			continue
		var sc: Script = node.get_script()
		var key := sc.resource_path if sc.resource_path != "" else String(node.get_class())
		reg[id] = [node, key, hp, hy]
		if hp:
			node.set_process(false)
		if hy:
			node.set_physics_process(false)
	for id: int in reg.keys():
		if not seen.has(id) or not is_instance_valid(reg[id][0]):
			reg.erase(id)


func _release_all() -> void:
	for id: int in reg:
		var e: Array = reg[id]
		if is_instance_valid(e[0]):
			if e[2]:
				(e[0] as Node).set_process(true)
			if e[3]:
				(e[0] as Node).set_physics_process(true)
	reg.clear()


func _physics_process(delta: float) -> void:
	if phase == "":
		return
	var pl: Node3D = main.player
	var p: Vector2
	if ring:
		ring_a += SPEED * delta / ring_r
		p = ring_c + Vector2.from_angle(ring_a) * ring_r
		main.player.set_camera(ring_a + PI, -0.14)
	else:
		along += SPEED * delta
		p = leg_from + leg_dir * along
		main.player.set_camera(atan2(-leg_dir.x, -leg_dir.y), -0.14)
	pl.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.1, p.y)
	if raw:
		return
	var t0 := Time.get_ticks_usec()
	for id: int in reg:
		var e: Array = reg[id]
		if e[3] and is_instance_valid(e[0]) and (e[0] as Node).is_inside_tree() and (e[0] as Node).can_process():
			var u := Time.get_ticks_usec()
			(e[0] as Node).call("_physics_process", delta)
			var k: String = "phys " + String(e[1])
			frame_us[k] = int(frame_us.get(k, 0)) + Time.get_ticks_usec() - u
	var tick_us := Time.get_ticks_usec() - t0
	if t > SETTLE:
		ticks += 1
		tick_script_us += tick_us


func _process(delta: float) -> void:
	if phase == "":
		return
	t += delta
	scan_t += delta
	if not raw and (scan_t > 2.0 or reg.is_empty()):
		scan_t = 0.0
		_scan()
	var proc_t0 := Time.get_ticks_usec()
	if not raw:
		for id: int in reg:
			var e: Array = reg[id]
			if e[2] and is_instance_valid(e[0]) and (e[0] as Node).is_inside_tree() and (e[0] as Node).can_process():
				var u := Time.get_ticks_usec()
				(e[0] as Node).call("_process", delta)
				var k: String = e[1]
				frame_us[k] = int(frame_us.get(k, 0)) + Time.get_ticks_usec() - u
	if t > SETTLE and not Probe.on:
		Probe.on = true
		Probe.reset()
	if t > SETTLE:
		var tot := 0
		for k: String in frame_us:
			var arr: PackedFloat32Array = series.get(k, PackedFloat32Array())
			arr.append(frame_us[k] / 1000.0)
			series[k] = arr
			tot += int(frame_us[k])
		frames.append(delta * 1000.0)
		eng_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		eng_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		attributed.append(tot / 1000.0)
	frame_us.clear()
	if t >= dur + SETTLE:
		_end_phase()


static func _stats(a: PackedFloat32Array, n: int) -> Array:
	## [mean over n frames, p95 over n frames] (frames where the key did not run count as 0).
	var s := a.duplicate()
	var zeros := maxi(0, n - s.size())
	s.sort()
	var tot := 0.0
	for v in s:
		tot += v
	var idx := int(ceil(0.95 * n)) - 1 - zeros
	var p95 := 0.0 if idx < 0 else s[mini(idx, s.size() - 1)]
	return [tot / maxf(1.0, n), p95]


func _end_phase() -> void:
	var n := frames.size()
	var rows: Array = []
	for k: String in series:
		var st := _stats(series[k], n)
		rows.append({"key": k, "mean": st[0], "p95": st[1]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["mean"] > b["mean"])
	var ft := _stats(frames, n)
	var at := _stats(attributed, n)
	var ep := _stats(eng_proc, n)
	var eh := _stats(eng_phys, n)
	var fs := frames.duplicate()
	fs.sort()
	var info := {
		"frames": n, "frame_ms_mean": ft[0], "frame_ms_p95": ft[1], "frame_ms_p99": fs[mini(n - 1, n * 99 / 100)] if n > 0 else 0.0,
		"attributed_ms_mean": at[0], "attributed_ms_p95": at[1],
		"engine_process_max_1s_ms_mean": ep[0], "engine_physics_max_1s_ms_mean": eh[0],     # TIME_PROCESS / TIME_PHYSICS_PROCESS report the MAX of the last second
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"registered": reg.size(),
		"phys_active_objects": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"phys_collision_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"phys_islands": int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		"physics_hz": Engine.physics_ticks_per_second,
		"physics_ticks": ticks,
		"physics_script_ms_per_tick": tick_script_us / 1000.0 / maxf(1.0, ticks),
	}
	var probes: Array = []
	for k: String in Probe.us:
		probes.append({"key": k, "ms_per_frame": float(Probe.us[k]) / 1000.0 / maxf(1.0, n), "calls": int(Probe.calls[k]), "ms_per_call": float(Probe.us[k]) / 1000.0 / maxf(1, int(Probe.calls[k])), "worst_ms": float(Probe.worst[k]) / 1000.0})
	probes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms_per_frame"] > b["ms_per_frame"])
	Probe.on = false
	results[phase] = {"info": info, "rows": rows.slice(0, 60), "probes": probes}
	for pr: Dictionary in probes:
		print("CPUPROF   probe %-30s %7.3f ms/frame  calls=%d  %7.3f ms/call  worst=%.2f ms" % [pr["key"], pr["ms_per_frame"], pr["calls"], pr["ms_per_call"], pr["worst_ms"]])
	print("CPUPROF phase %s physics: %d ticks, scripts %.2f ms/tick" % [phase, ticks, info["physics_script_ms_per_tick"]])
	print("CPUPROF phase %s frames=%d frame=%.2f ms (p95 %.2f p99 %.2f) attributed=%.2f ms engine_proc_max1s=%.2f phys_max1s=%.2f static=%.0f MB objs=%d nodes=%d registered=%d" % [
		phase, n, ft[0], ft[1], info["frame_ms_p99"], at[0], ep[0], eh[0], info["memory_static_mb"], info["objects"], info["nodes"], reg.size()])
	for i in mini(TOP, rows.size()):
		print("CPUPROF   %-58s mean=%7.3f p95=%7.3f" % [String(rows[i]["key"]).replace("res://scripts/", "").replace("res://", ""), rows[i]["mean"], rows[i]["p95"]])
	_next_phase()


func _finish() -> void:
	phase = ""
	_release_all()
	if census:
		results["census"] = (load("res://tools_qa/cpu_mem/mem_census.gd") as GDScript).new().run(get_tree())
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(results, "\t"))
			f.close()
	print("CPUPROF done")
	get_tree().quit(0)
