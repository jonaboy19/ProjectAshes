extends Node
## Steady-state CPU ablation (release QA): stand in Kingsreach's market (no streaming), uncapped, and compare the MEDIAN frame
## time of interleaved windows with one system switched off: "proc" = process/physics off (script cost), "hide" = subtree
## hidden (render submission + culling cost). Medians ignore hitches, so the numbers are steady-state costs.
##   godot --path kingdom --rendering-method mobile --resolution 1280x720 -- --adult --quality=low \
##       --qa=res://tools_qa/perf/ablate.gd [--where=market|ashford]
var main: Node
var targets: Array = []      # [node, mode]
var i := -1
var phase := "settle"
var t := 0.0
var buf := PackedFloat32Array()
var base := PackedFloat32Array()
var _f0 := 0
const NpcWorld := preload("res://scripts/population/npc_world.gd")


func run(m: Node) -> void:
	main = m
	var where := "market"
	for a in _args():
		if a.begins_with("--where="):
			where = a.get_slice("=", 1)
	WorldSim.time_of_day = 15.0
	var s: Dictionary = WorldGen.settlements[1 if where == "market" else 0]
	var c: Vector2 = s["pos"]
	var gate: float = s["plan"]["gates"][0] if not (s["plan"]["gates"] as Array).is_empty() else 0.0
	var p: Vector2 = c + Vector2(cos(gate), sin(gate)) * (float(s["plan"]["plaza_r"]) + 6.0)
	main.call("_teleport", p, gate + PI * 0.5)
	main.player.set_camera(atan2(-(c - p).x, -(c - p).y), -0.12)
	if _args().has("--groups"):
		_group_targets()
		return
	for n in ["WorldSim", "Life", "Frontier", "Audio"]:
		targets.append([get_node("/root/" + n), "proc"])
	for ch in main.world.get_children():
		if ch == self:
			continue
		if ch.get_child_count() > 0 or ch.is_processing() or ch.is_physics_processing():
			targets.append([ch, "proc"])
		if ch is Node3D and ch.get_child_count() > 0:
			targets.append([ch, "hide"])


func _process(delta: float) -> void:
	Engine.max_fps = 0
	if main == null:
		return
	t += delta
	match phase:
		"settle":
			for a in _args():
				if String(a).begins_with("--physhz="):
					Engine.physics_ticks_per_second = int(String(a).get_slice("=", 1))
			if t > 15.0 and not NpcWorld.profile:
				NpcWorld.profile = true
				_f0 = Engine.get_process_frames()
			if t > 15.0:
				base.append(delta * 1000.0)
			if t > 20.0:
				var fr := maxi(1, Engine.get_process_frames() - _f0)
				var pl: Node = main.population
				print("ABLATE hz=%d npc: villager_phys=%.2f ms/frame (%d calls) frame=%.2f lod=%.2f ms/frame full=%d sprites=%d soldiers=%d frame_med=%.2f" % [Engine.physics_ticks_per_second, 
					NpcWorld.prof_usec / 1000.0 / fr, NpcWorld.prof_calls, NpcWorld.prof_frame_usec / 1000.0 / fr, NpcWorld.prof_lod_usec / 1000.0 / fr,
					pl.full_count, pl.sprite_count, get_tree().get_nodes_in_group("soldier").size(), _med(base)])
				NpcWorld.profile = false
				if _args().has("--npconly"):
					get_tree().quit(0)
				phase = "base"
				t = 0.0
		"base":
			if t > 0.5:
				base.append(delta * 1000.0)
			if t > 2.5:
				_next()
		"off":
			if t > 0.8:
				buf.append(delta * 1000.0)
			if t > 3.3:
				_report()
				phase = "base"
				t = 0.0


func _next() -> void:
	i += 1
	if i >= targets.size():
		print("ABLATE done base_median=%.2f" % _med(base))
		get_tree().quit(0)
		return
	_toggle(targets[i], false)
	buf.clear()
	phase = "off"
	t = 0.0


func _report() -> void:
	var n0: Variant = targets[i][0]
	var mode: String = targets[i][1]
	var b := _med(base)
	var o := _med(buf)
	var n: Node = n0 if n0 is Node else null
	var sn: String = ("%d nodes" % (n0 as Array).size()) if n == null else (n.get_script().resource_path.get_file() if n.get_script() else n.get_class())
	var label: String = ((n0 as Array)[0].get_script().resource_path.get_file() + "[]") if n == null and not (n0 as Array).is_empty() else (String(n.name) if n else "-")
	print("ABLATE %-4s %-26s %-28s saves %6.2f ms (median %.2f -> %.2f) draws_off=%d" % [mode, label.left(26), sn.left(28), b - o, b, o,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	_toggle(targets[i], true)
	base.clear()


func _toggle(tg: Array, on: bool) -> void:
	var nodes: Array = tg[0] if tg[0] is Array else [tg[0]]
	for n: Node in nodes:
		if not is_instance_valid(n):
			continue
		if tg[1] == "proc":
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		elif n is Node3D:
			(n as Node3D).visible = on


static func _med(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


## --groups: many nodes of one kind at once (all soldiers, all full villagers) and the children of the heavy roots one by one.
func _group_targets() -> void:
	var soldiers: Array = []
	var villagers: Array = []
	for n in main.world.find_children("*", "CharacterBody3D", true, false):
		var sp: String = n.get_script().resource_path.get_file() if n.get_script() else ""
		if sp == "soldier.gd":
			soldiers.append(n)
		elif sp == "villager.gd":
			villagers.append(n)
	targets.append([soldiers, "proc"])
	targets.append([soldiers, "hide"])
	targets.append([villagers, "proc"])
	targets.append([villagers, "hide"])
	for root_name in ["Region1Root", "RegionDressing", "VillageServices", "SettlementBuilder"]:
		for ch in main.world.get_children():
			var sn: String = ch.get_script().get_global_name() if ch.get_script() else ""
			if String(ch.name) == root_name or sn == root_name:
				for c in ch.get_children():
					if c is Node3D and (c.get_child_count() > 0 or c is GeometryInstance3D):
						targets.append([c, "hide"])
					if c.is_processing() or c.is_physics_processing() or c.get_child_count() > 0:
						targets.append([c, "proc"])


static func _args() -> Array:
	var out: Array = []
	for a in Array(OS.get_cmdline_user_args()) + Array(Quality.qa_file_args()):
		out.append(String(a).strip_edges())
	return out
