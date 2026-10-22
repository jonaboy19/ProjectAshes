extends SceneTree
## Simulation, memory and save probe (release QA, cloud lane). No 3D world: ticks WorldSim.hour_changed hour by hour
## (each connected handler timed on its own, then the realm hub queue drained job by job, like the balance harness),
## and at the checkpoint days measures MEMORY_STATIC, object counts, the size of every save section, JSON / zstd sizes
## and the save, parse and restore times.
##   godot --headless --path kingdom -s res://tools_qa/cpu_mem/sim_save_probe.gd -- days=120 tag=before [checkpoints=1,30,120]
## Writes user://cpu_mem_<tag>.json (printed path) and prints SIMPROBE lines.
const Probe := preload("res://scripts/core/perf_probe.gd")
var args := {}
var done := false
var life: Node
var ws: Node
var hub: RefCounted
var job_us := {}          # "module.method" -> PackedInt32Array of usec
var handler_us := {}      # "Object.method" -> PackedInt32Array of usec
var report := {}


func _process(_dt: float) -> bool:
	if done:
		return false
	done = true
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var tag: String = args.get("tag", "run")
	var days := int(args.get("days", "30"))
	var cps: Array = []
	for c in String(args.get("checkpoints", "1,%d" % days)).split(","):
		cps.append(int(c))
	Probe.on = true
	life = root.get_node("Life")
	ws = root.get_node("WorldSim")
	hub = life.realm
	report["memory_start_mb"] = _mem()
	report["objects_start"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	hub.warm_up()
	report["warm_up_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	report["memory_after_warm_mb"] = _mem()
	report["objects_after_warm"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	report["population"] = ws.population()
	# What one economy (30 markets) costs on the heap: build a second one and look at MEMORY_STATIC around it.
	var eco_script := load("res://scripts/sim/economy.gd") as GDScript
	var m_before := _mem()
	var extra_eco: RefCounted = eco_script.new()
	extra_eco.call("setup", 0)
	report["economy_build_mb"] = _mem() - m_before
	print("SIMPROBE one extra economy (setup) costs %.1f MB of MEMORY_STATIC" % report["economy_build_mb"])
	extra_eco = null
	var items := 0
	for mid in life.economy.markets:
		items += (life.economy.markets[mid] as RefCounted).get("stock").size()
	report["markets"] = life.economy.markets.size()
	report["market_items"] = items
	report["settlements"] = (load("res://scripts/world/world_gen.gd") as GDScript).get("settlements").size()   # no global class names at compile time: the -s script compiles before the autoloads exist
	print("SIMPROBE markets %d, market items %d, settlements %d" % [report["markets"], items, report["settlements"]])
	print("SIMPROBE warm_up %.0f ms, static %.0f -> %.0f MB, population %d" % [report["warm_up_ms"], report["memory_start_mb"], report["memory_after_warm_mb"], ws.population()])
	report["checkpoints"] = {}
	var last_day := 0
	for d in range(1, days + 1):
		if cps.has(d):
			report["checkpoints"][str(d)] = _checkpoint(d)
		for h in 24:
			_hour(d, h)
		last_day = d
	report["checkpoints"][str(last_day + 1)] = _checkpoint(last_day + 1)
	report["jobs"] = _table(job_us)
	report["handlers"] = _table(handler_us)
	_print_table("job", report["jobs"])
	_print_table("hour handler", report["handlers"])
	var pr := []
	for k: String in Probe.us:
		pr.append({"key": k, "calls": Probe.calls[k], "total_ms": Probe.us[k] / 1000.0, "mean_ms": Probe.us[k] / 1000.0 / Probe.calls[k], "worst_ms": Probe.worst[k] / 1000.0})
	pr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total_ms"] > b["total_ms"])
	report["probes"] = pr
	for r: Dictionary in pr:
		print("SIMPROBE probe %-44s calls=%5d total=%8.1f ms mean=%7.3f worst=%7.3f" % [r["key"], r["calls"], r["total_ms"], r["mean_ms"], r["worst_ms"]])
	var path := "user://cpu_mem_%s.json" % tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("SIMPROBE wrote ", ProjectSettings.globalize_path(path))
	quit()
	return false


func _mem() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0


func _hour(day: int, h: int) -> void:
	ws.day = day
	ws.time_of_day = float(h)
	for c: Dictionary in ws.hour_changed.get_connections():
		var cb: Callable = c["callable"]
		var t0 := Time.get_ticks_usec()
		cb.call(h)
		var key := "%s.%s" % [cb.get_object().get_class() if cb.get_object() else "?", cb.get_method()]
		if cb.get_object() and cb.get_object().get_script():
			key = "%s.%s" % [String((cb.get_object().get_script() as Script).resource_path).get_file(), cb.get_method()]
		_add(handler_us, key, Time.get_ticks_usec() - t0)
	while not hub._queue.is_empty():
		var j: Array = hub._queue.pop_front()
		var t1 := Time.get_ticks_usec()
		hub._run_job(j)
		var key2 := "chunk" if j[1] is Callable else "%s.%s" % [j[0], j[1]]
		_add(job_us, key2, Time.get_ticks_usec() - t1)


func _add(d: Dictionary, k: String, us: int) -> void:
	var a: PackedInt32Array = d.get(k, PackedInt32Array())
	a.append(us)
	d[k] = a


func _table(d: Dictionary) -> Array:
	var rows := []
	for k: String in d:
		var a: PackedInt32Array = (d[k] as PackedInt32Array).duplicate()
		a.sort()
		var tot := 0
		for v in a:
			tot += v
		rows.append({"key": k, "calls": a.size(), "total_ms": tot / 1000.0, "mean_ms": tot / 1000.0 / a.size(), "p95_ms": a[mini(a.size() - 1, a.size() * 95 / 100)] / 1000.0, "max_ms": a[a.size() - 1] / 1000.0})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["total_ms"] > y["total_ms"])
	return rows


func _print_table(what: String, rows: Array) -> void:
	for i in mini(14, rows.size()):
		var r: Dictionary = rows[i]
		print("SIMPROBE %s %-40s calls=%5d total=%8.1f ms mean=%6.3f p95=%6.3f max=%6.3f" % [what, r["key"], r["calls"], r["total_ms"], r["mean_ms"], r["p95_ms"], r["max_ms"]])


func _checkpoint(day: int) -> Dictionary:
	var out := {}
	out["day"] = day
	out["memory_static_mb"] = _mem()
	out["objects"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	var snap: Dictionary = life.snapshot()
	out["snapshot_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var sections := {}
	for k: String in snap:
		sections[k] = JSON.stringify(snap[k]).length()
	t0 = Time.get_ticks_usec()
	var text := JSON.stringify(snap)
	out["stringify_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["json_bytes"] = text.length()
	var rows := []
	for k: String in sections:
		var zs := 0
		if int(sections[k]) > 2000:
			zs = JSON.stringify(snap[k]).to_utf8_buffer().compress(FileAccess.COMPRESSION_ZSTD).size()
		rows.append([k, sections[k], zs])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	out["sections"] = rows.slice(0, 25)
	var realm: Dictionary = snap.get("realm", {})
	var rr := []
	for k: String in realm:
		rr.append([k, JSON.stringify(realm[k]).length()])
	rr.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	out["realm_modules"] = rr.slice(0, 15)
	var paths := {}
	_walk_paths(snap, "", paths)
	var pr := []
	for k: String in paths:
		pr.append([k, paths[k]])
	pr.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	out["heavy_paths"] = pr.slice(0, 60)
	if args.has("dump"):
		var df := FileAccess.open("user://snap_%s_day%d.json" % [args.get("tag", "run"), day], FileAccess.WRITE)
		df.store_string(text)
		df.close()
	var buf := text.to_utf8_buffer()
	out["utf8_bytes"] = buf.size()
	t0 = Time.get_ticks_usec()
	out["zstd_bytes"] = buf.compress(FileAccess.COMPRESSION_ZSTD).size()
	out["zstd_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["deflate_bytes"] = buf.compress(FileAccess.COMPRESSION_DEFLATE).size()
	out["gzip_bytes"] = buf.compress(FileAccess.COMPRESSION_GZIP).size()
	t0 = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(text)
	out["parse_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	# Whole-save write and read through the real SaveManager (temp folder), restore timed separately.
	var sm: Node = load("res://scripts/sim/save_manager.gd").new()
	sm.root_dir = "user://cpu_mem_saves/"
	sm.snapshot_fn = func() -> Dictionary: return snap
	var restored := [false]
	sm.restore_fn = func(_d: Dictionary) -> void: restored[0] = true
	t0 = Time.get_ticks_usec()
	sm.write_envelope("manual_1", snap, {"name": "probe", "kind": "manual"})
	out["write_envelope_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["file_bytes"] = FileAccess.get_file_as_bytes(sm.path_of("manual_1")).size()
	t0 = Time.get_ticks_usec()
	var env: Dictionary = sm.read_slot("manual_1")
	out["read_slot_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	if not env.is_empty() and parsed is Dictionary:
		t0 = Time.get_ticks_usec()
		life.restore(env["data"])
		out["restore_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	sm.free()
	print("SIMPROBE day %d: json %d B, file %d B, zstd %d B | snapshot %.0f ms stringify %.0f ms write %.0f ms read %.0f ms restore %.0f ms | static %.0f MB objs %d" % [
		day, out["json_bytes"], out["file_bytes"], out["zstd_bytes"], out["snapshot_ms"], out["stringify_ms"], out["write_envelope_ms"], out["read_slot_ms"], out.get("restore_ms", -1.0), out["memory_static_mb"], out["objects"]])
	for r: Array in out["sections"].slice(0, 12):
		print("SIMPROBE   section %-18s %8d B (zstd alone %7d B)" % [r[0], r[1], r[2]])
	for r: Array in out["heavy_paths"].slice(0, 40):
		print("SIMPROBE   path %-70s %8d B" % [r[0], r[1]])
	for r: Array in out["realm_modules"].slice(0, 8):
		print("SIMPROBE   realm.%-14s %8d B" % [r[0], r[1]])
	return out


## Bytes of JSON text by key path (array elements collapsed to "[]", digit-only keys to "#"): where the save weight is.
func _walk_paths(v: Variant, path: String, acc: Dictionary) -> int:
	var total := 0
	if v is Dictionary:
		for k: Variant in v:
			var ks := String(k)
			var seg := "#" if ks.is_valid_int() else ks
			var n := _walk_paths(v[k], path + "/" + seg, acc) + ks.length() + 4
			total += n
	elif v is Array:
		for e: Variant in v:
			total += _walk_paths(e, path + "[]", acc) + 1
	else:
		total = JSON.stringify(v).length()
	if v is Dictionary or v is Array:
		acc[path] = int(acc.get(path, 0)) + total
	return total
