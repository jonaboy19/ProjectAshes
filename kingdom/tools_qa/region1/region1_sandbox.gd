extends Node
## Region 1 sandbox: runs one sim module for N days without main.tscn, headless-safe.
##
##   Godot --headless --path kingdom res://tools_qa/region1/region1_sandbox.tscn -- \
##       --module=demo_sim --days=60 --seed=1 --step=0.5 --png-every=10 --log-every=5 --out=<dir>
##
## --module     script name in res://scripts/region1/<module>.gd (extends Region1Sim). Default demo_sim.
## --days       simulated days (default 30).       --seed  world seed (default 1).
## --step       game days per advance (<= 1, default 0.5).
## --png-every  save the module's debug_image() every N days (0 = only the final one).
## --log-every  print a summary line every N days (default 10).
## --out        output directory (default user://region1_sandbox/<module>).
## Output: <module>.log, <module>_dayNNN.png, summary.json. Exit code 0 = all checks passed.
## Checks: (1) same seed + same steps => identical digest; (2) snapshot -> JSON -> restore into a
## fresh sim, then 2 more days, matches the original; (3) average tick cost is printed.

const MODULE_DIR := "res://scripts/region1/"

var module_name := "demo_sim"
var days := 30.0
var seed_value := 1
var step := 0.5
var png_every := 0
var log_every := 10
var out_dir := ""
var _log: PackedStringArray = []
var _clock := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--module="): module_name = a.substr(9)
		elif a.begins_with("--days="): days = float(a.substr(7))
		elif a.begins_with("--seed="): seed_value = int(a.substr(7))
		elif a.begins_with("--step="): step = clampf(float(a.substr(7)), 0.01, 1.0)
		elif a.begins_with("--png-every="): png_every = int(a.substr(12))
		elif a.begins_with("--log-every="): log_every = maxi(1, int(a.substr(12)))
		elif a.begins_with("--out="): out_dir = a.substr(6)
	if out_dir == "":
		out_dir = "user://region1_sandbox/" + module_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	var code := _run()
	_write(module_name + ".log", "\n".join(_log) + "\n")
	get_tree().quit(code)


func _out(line: String) -> void:
	_log.append(line)
	print(line)


func _make() -> Region1Sim:
	var path := MODULE_DIR + module_name + ".gd"
	if not ResourceLoader.exists(path):
		_out("FAIL: no module script " + path)
		return null
	var s: Variant = (load(path) as GDScript).new()
	if not (s is Region1Sim):
		_out("FAIL: %s does not extend Region1Sim" % path)
		return null
	return (s as Region1Sim).setup(seed_value)


func _run() -> int:
	_out("region1 sandbox: module=%s days=%s seed=%d step=%s renderer=%s" % [
		module_name, days, seed_value, step, RenderingServer.get_current_rendering_method()])
	var sim := _make()
	if sim == null:
		return 2
	Region1State.clear()
	Region1State.register_sim(sim)

	var root := Region1Root.new()
	root.auto_bootstrap = false
	root.auto_timer = false
	root.clock = func() -> float: return _clock
	add_child(root)
	root.advance_to(_clock)   # anchor

	var events := {}
	sim.event.connect(func(kind: StringName, _d: Dictionary) -> void:
		events[String(kind)] = int(events.get(String(kind), 0)) + 1)

	var t_all := Time.get_ticks_usec()
	var next_log := float(log_every)
	var next_png := float(png_every)
	var steps := int(ceil(days / step))
	for i in steps:
		_clock += minf(step, days - _clock)
		root.advance_to(_clock)
		if _clock >= next_log:
			_out("day %6.1f  %s" % [_clock, sim.summary()])
			next_log += log_every
		if png_every > 0 and _clock >= next_png:
			_save_png(sim, "day%03d" % int(_clock))
			next_png += png_every
	var total_ms := float(Time.get_ticks_usec() - t_all) / 1000.0
	_save_png(sim, "final")
	_out("final: %s" % sim.summary())
	_out("events: %s" % JSON.stringify(events))
	_out("cost: total %.1f ms, avg %.3f ms per advance, worst advance %.3f ms" % [
		total_ms, total_ms / maxf(1.0, steps), root.worst_tick_ms])

	var ok := true
	# Check 1: determinism.
	var twin := _make()
	var c := 0.0
	for i in steps:
		var dt := minf(step, days - c)
		c += dt
		twin.tick(dt)
	var d1 := sim.digest()
	var d2 := twin.digest()
	_out("determinism: %s (%s vs %s)" % ["PASS" if d1 == d2 else "FAIL", d1.left(8), d2.left(8)])
	ok = ok and d1 == d2

	# Check 2: save/restore round trip through JSON, then keep simulating.
	var text := JSON.stringify(Region1State.snapshot())
	var fresh := _make()
	Region1State.clear()
	Region1State.register_sim(fresh)
	Region1State.restore(JSON.parse_string(text))
	var rt := fresh.digest() == d1
	sim.tick(1.0); sim.tick(1.0)
	fresh.tick(1.0); fresh.tick(1.0)
	var rt2 := fresh.digest() == sim.digest()
	_out("round-trip: %s, continues identically: %s (save %d bytes)" % [
		"PASS" if rt else "FAIL", "PASS" if rt2 else "FAIL", text.length()])
	ok = ok and rt and rt2

	_write("summary.json", JSON.stringify({
		"module": module_name, "days": days, "seed": seed_value, "digest": d1,
		"events": events, "total_ms": total_ms, "ok": ok}, "\t"))
	_out("REGION1_SANDBOX " + ("OK" if ok else "FAIL"))
	return 0 if ok else 1


func _save_png(sim: Region1Sim, tag: String) -> void:
	var img := sim.debug_image(256)
	if img == null:
		return
	var path := out_dir.path_join("%s_%s.png" % [module_name, tag])
	if img.save_png(path) == OK:
		_out("wrote " + ProjectSettings.globalize_path(path))


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(out_dir.path_join(file), FileAccess.WRITE)
	if f:
		f.store_string(text)
