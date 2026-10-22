extends Node
## Town-kit scale harness (headless, CPU only): boot cost and idle per-frame cost of every kit town hub while the player is far away,
## plus the size of the save with every roster bound. Run from kingdom/:
##   $GODOT --headless --path . res://tools_qa/perf/town_kit_perf.tscn [-- --frames=1800 [--ungated] [--each]]
## Default: hubs gated (asleep outside the settlement tier, what main.gd does). --ungated: every hub always awake (the cost without sleeping).
## Prints one `TOWNPERF key=value ...` line per measurement. "far" is the dry spot with the largest distance to any town.
const TownHub := preload("res://scripts/world/town_kit/town_hub.gd")
const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _ready() -> void:
	var process_frame := get_tree().process_frame
	var ws: Node = WorldSim
	var life: Node = Life
	var frames := 1800
	var gated := not OS.get_cmdline_user_args().has("--ungated")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames = int(a.get_slice("=", 1))
	var t0 := Time.get_ticks_usec()
	WorldGen.setup(int(ws.get("SEED")))
	var worldgen_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	ws.call("reset")
	var reset_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	TownRoster.bind_all(true)
	var bind_ms := _ms(t0)
	var holder := Node3D.new()
	add_child(holder)
	var dens_before: int = Frontier.ecology.alive_count()
	# the far spot first: the streamer must know the focus before gated hubs register
	var far := Vector2.ZERO
	var best := -1.0
	for gx in range(-3000, 3001, 250):
		for gz in range(-3000, 3001, 250):
			var p := Vector2(gx, gz)
			var m := INF
			for s in WorldGen.settlements:
				m = minf(m, p.distance_to(s["pos"]))
			if m > best:
				best = m
				far = p
	var cs := CellStreamer.shared()
	cs.update(Vector3(far.x, 0.0, far.y))
	t0 = Time.get_ticks_usec()
	var hubs: Array = []
	var each := []
	for id: String in TownData.ids():
		var h0 := Time.get_ticks_usec()
		hubs.append(TownHub.attach(holder, id, gated))
		each.append("%s=%.0f" % [id, _ms(h0)])
	var attach_ms := _ms(t0)
	if OS.get_cmdline_user_args().has("--each"):
		print("TOWNPERF attach_each_ms ", " ".join(each))
	var nodes := 0
	var stack: Array = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		stack.append_array(n.get_children())
	print("TOWNPERF mode=%s towns=%d worldgen_ms=%.1f worldsim_reset_ms=%.1f bind_all_ms=%.1f attach_all_ms=%.1f hub_subtree_nodes=%d dens_alive %d -> %d" % [
		"gated" if gated else "ungated", TownData.ids().size(), worldgen_ms, reset_ms, bind_ms, attach_ms, nodes, dens_before, Frontier.ecology.alive_count()])
	var player := Node3D.new()
	var sc := GDScript.new()                  # a stand-in player: the properties the quest pump reads
	sc.source_code = "extends Node3D\nvar crouching := false\nvar dead := false\n"
	sc.reload()
	player.set_script(sc)
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(far.x, 0.0, far.y)
	await process_frame
	TownHub.prof = true
	TownHub.prof_usec = 0
	TownHub.prof_calls = 0
	var worst := 0
	var f_t0 := Time.get_ticks_usec()
	for i in frames:
		cs.update(Vector3(far.x, 0.0, far.y))
		var before := TownHub.prof_usec
		await process_frame
		worst = maxi(worst, TownHub.prof_usec - before)
	var wall := _ms(f_t0)
	print("TOWNPERF far=(%d,%d) nearest_town_m=%.0f frames=%d hub_us_per_frame=%.2f hub_calls_per_frame=%.1f worst_frame_hub_us=%d wall_ms_per_frame=%.3f" % [
		far.x, far.y, best, frames, float(TownHub.prof_usec) / frames, float(TownHub.prof_calls) / frames, worst, wall / frames])
	# the same frames with the hubs switched off, for the engine share
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	f_t0 = Time.get_ticks_usec()
	for i in frames:
		cs.update(Vector3(far.x, 0.0, far.y))
		await process_frame
	var wall_off := _ms(f_t0)
	print("TOWNPERF hubs_disabled_wall_ms_per_frame=%.3f" % [wall_off / frames])
	holder.process_mode = Node.PROCESS_MODE_INHERIT
	# what the player's interaction scan walks while the hubs sleep (every node of the "interactable" group, each frame it picks)
	var inter := get_tree().get_nodes_in_group("interactable").size()
	var t1 := Time.get_ticks_usec()
	for i in 200:
		Interaction.candidates(player)
	print("TOWNPERF interactables_in_scan=%d scan_us=%.1f" % [inter, float(Time.get_ticks_usec() - t1) / 200.0])
	if gated:
		# the lazy cost: what each town pays the first time the player comes within range
		var costs: Array = []
		var hubs_wake: Array = []
		for h: Node in hubs:
			if not bool(h.call("is_awake")):
				hubs_wake.append(h)
		for h: Node in hubs_wake:
			var a0 := Time.get_ticks_usec()
			h.call("_set_awake", true)
			costs.append(float(Time.get_ticks_usec() - a0) / 1000.0)
		costs.sort()
		var sum := 0.0
		for c: float in costs:
			sum += c
		print("TOWNPERF first_wake_ms n=%d avg=%.2f median=%.2f max=%.2f total=%.1f  dens_alive_after=%d" % [costs.size(), sum / maxf(1.0, costs.size()), costs[costs.size() / 2], costs[-1], sum, Frontier.ecology.alive_count()])
		var inter2 := get_tree().get_nodes_in_group("interactable").size()
		var t2 := Time.get_ticks_usec()
		for i in 200:
			Interaction.candidates(player)
		print("TOWNPERF all_awake interactables_in_scan=%d scan_us=%.1f" % [inter2, float(Time.get_ticks_usec() - t2) / 200.0])
		for h: Node in hubs_wake:
			h.call("_set_awake", false)
	# the save
	var snap: Dictionary = life.call("snapshot")
	var text := JSON.stringify(snap)
	var parts := []
	for k: String in snap:
		parts.append([JSON.stringify(snap[k]).length(), k])
	parts.sort()
	parts.reverse()
	print("TOWNPERF save_bytes=%d biggest=%s" % [text.length(), str(parts.slice(0, 5))])
	get_tree().quit(0)
