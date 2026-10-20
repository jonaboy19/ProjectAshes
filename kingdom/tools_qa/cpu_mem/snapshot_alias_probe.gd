extends SceneTree
## Thread-safety audit of the async autosave (scripts/sim/save_manager.gd): a worker thread stringifies the snapshot while the game
## keeps running, so nothing in it may be a container the game still mutates. This takes Life.snapshot_steps() at game day N, keeps
## the dictionary, plays N more days hour by hour (every hourly handler and every realm-hub job, as sim_save_probe.gd does), and
## compares the JSON of the kept dictionary with what it was. Prints ALIAS lines for every top-level key that changed (none = detached).
##   godot --headless --path kingdom -s res://tools_qa/cpu_mem/snapshot_alias_probe.gd -- days=3
var done := false


func _process(_dt: float) -> bool:
	if done:
		return false
	done = true
	var days := 3
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "days":
			days = int(kv[1])
	var life: Node = root.get_node("Life")
	var ws: Node = root.get_node("WorldSim")
	var hub: RefCounted = life.realm
	hub.warm_up()
	for d in range(1, days + 1):
		for h in 24:
			_hour(ws, hub, d, h)
	var snap := {}
	var sm := load("res://scripts/sim/save_manager.gd") as GDScript
	for st: Array in life.snapshot_steps():           # exactly what the async autosave collects (detach = true)
		var v: Variant = (st[1] as Callable).call()
		if v != null:
			sm.call("put", snap, String(st[0]), v)
	var before := {}
	for k: String in snap:
		before[k] = JSON.stringify(snap[k])
	var total_before := JSON.stringify(snap).length()
	var sizes := []
	for k: String in snap:
		sizes.append([String(before[k]).length(), k])
	sizes.sort()
	sizes.reverse()
	for i in 8:
		print("ALIAS size %-14s %7d chars" % [sizes[i][1], sizes[i][0]])
	for d in range(days + 1, days * 2 + 1):
		for h in 24:
			_hour(ws, hub, d, h)
		life.give("bread", 1)
		life.record("traded", 1.0)
	var changed := 0
	for k: String in snap:
		if JSON.stringify(snap[k]) != before[k]:
			changed += 1
			print("ALIAS section '%s' changed after the snapshot was taken (%d -> %d chars)" % [k, String(before[k]).length(), JSON.stringify(snap[k]).length()])
	print("ALIAS checked %d sections, %d chars, %d days later: %d changed" % [snap.size(), total_before, days, changed])
	quit(0 if changed == 0 else 1)
	return true


func _hour(ws: Node, hub: RefCounted, day: int, h: int) -> void:
	ws.day = day
	ws.time_of_day = float(h)
	for c: Dictionary in ws.hour_changed.get_connections():
		(c["callable"] as Callable).call(h)
	while not hub._queue.is_empty():
		hub._run_job(hub._queue.pop_front())
