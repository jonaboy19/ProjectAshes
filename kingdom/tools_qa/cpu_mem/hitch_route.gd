extends Node
## Frame-spike route (release QA, cloud lane: CPU only). A scripted ~10 minute headless route: Ashford (time passes through the
## 06:00 trade, autosave, talk, a quest step, an interior), the road to Thornfield, a fast-travel hop, Thornfield (interior, fight,
## talk), the wilds, a teleport into a generated town (interior, autosave). Every frame is recorded; every frame over 8 ms is
## written out with its step, whether a physics tick ran in it, the Probe sections of >= 1 ms that ran inside it (perf_probe.gd,
## `Probe.capture`) and the three scripts with the most `_process` / `_physics_process` time (callbacks are taken over exactly as
## in cpu_profile.gd, which costs about 3 %).
##   godot --headless --path kingdom -- --adult --quality=low --qa=res://tools_qa/cpu_mem/hitch_route.gd \
##       [--scale=1.0] [--out=/path.json] [--raw]
## --scale multiplies every step's duration (1.0 = about 10 minutes of wall time). --raw skips the callback takeover.
const Probe := preload("res://scripts/core/perf_probe.gd")
const SPEED := 5.5
const KEEP_MIN_MS := 8.0
var main: Node
var scale_t := 1.0
var out := ""
var raw := false
var step_name := "boot"
var step_t := 0.0
var t_total := 0.0
var reg := {}
var scan_t := 0.0
var frame_us := {}
var frames := PackedFloat32Array()
var step_of := PackedInt32Array()
var steps: Array = []
var slow: Array = []
var ticks := 0
var last_ticks := 0
var path_mode := ""             # "ring" | "leg" | ""
var ring_c := Vector2.ZERO
var ring_r := 20.0
var ring_a := 0.0
var leg_from := Vector2.ZERO
var leg_dir := Vector2.RIGHT
var along := 0.0
var notes: Array = []
var recording := false
var only_approach := false      # --only-approach: skip to the generated-town approach (debugging this step)
var last_us := 0
var _beat_ms := 0
var overhead_us := 0            # this harness's own scan time inside the current frame: subtracted from it


func run(m: Node) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS      # a pause (a menu, a death screen) must not stop the route or its heartbeat
	process_priority = -1000       # first in the frame: the interval between two of this node's _process calls is one frame
	for raw_a in Array(OS.get_cmdline_user_args()):
		var a := String(raw_a)
		if a.begins_with("--scale="):
			scale_t = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a == "--raw":
			raw = true
		elif a == "--only-approach":
			only_approach = true
	Engine.max_fps = 0
	OS.low_processor_usage_mode_sleep_usec = 0
	Probe.on = true
	Probe.capture = true
	Probe.min_us = 1000
	Probe.reset()
	_route()


# --- helpers ------------------------------------------------------------------------------------------

func _settlement(name_part: String) -> Dictionary:
	for s: Dictionary in WorldGen.settlements:
		if String(s["name"]).to_lower().contains(name_part):
			return s
	return WorldGen.settlements[0]


func _begin(nm: String) -> void:
	step_name = nm
	step_t = 0.0
	steps.append(nm)
	print("HITCH step %s (t=%.0fs)" % [nm, t_total])


func _wait(seconds: float) -> void:
	var until := step_t + seconds * scale_t
	while step_t < until:
		await get_tree().process_frame


## A teleport / fast travel: main._teleport builds terrain, water and the town synchronously (behind the fade in the game), so its
## frame is a loading step, tagged "route.travel_teleport" and left out of the hitch counts (listed separately).
func _tp(p: Vector2, yaw: float) -> void:
	var t0 := Time.get_ticks_usec()
	main.call("_teleport", p, yaw)
	var d := Time.get_ticks_usec() - t0
	Probe.add_us("route.travel_teleport", d)
	_note("teleport took %.0f ms" % (d / 1000.0))


func _ring(s: Dictionary) -> void:
	path_mode = "ring"
	ring_c = s["pos"]
	ring_r = float(s["plan"]["plaza_r"]) + 10.0
	ring_a = 0.0
	_tp(ring_c + Vector2(ring_r, 0.0), 0.0)


func _leg(from: Vector2, dir: Vector2) -> void:
	path_mode = "leg"
	leg_from = from
	leg_dir = dir
	along = 0.0
	_tp(from, atan2(-dir.x, -dir.y))


func _note(s: String) -> void:
	notes.append("%s: %s" % [step_name, s])
	print("HITCH note ", notes[-1])


func _timed(label: String, c: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	c.call()
	var d := Time.get_ticks_usec() - t0
	Probe.add_us("route." + label, d)
	_note("%s took %.1f ms in its own call" % [label, d / 1000.0])


func _talk_someone() -> void:
	var best: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("villager"):
		if n is Node3D and n.get("person") != null:
			var d := (n as Node3D).global_position.distance_to(main.player.global_position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		_note("no villager near to talk to")
		return
	var info := {"id": "", "person": int(best.get("person"))}
	_timed("talk_menu_first", func() -> void: main.hud.show_menu(main.services.talk_menu.bind(info)))
	await _wait(1.5)
	main.hud.close_menu()


func _quest_step() -> void:
	var r: Variant = QuestHub.runner()
	if r == null:
		_note("no quest runner")
		return
	var started := ""
	for d in r.get("defs").values() if r.get("defs") is Dictionary else []:
		started = String(d.id)
		break
	if started == "":
		_note("no quest defs found")
		return
	_timed("quest_start", func() -> void: r.start(started))
	await _wait(1.0)
	_timed("quest_notify", func() -> void: r.notify(&"talk", {"npc": "route_probe"}))


func _interior() -> void:
	var best: InteriorDoor = null
	var bd := INF
	for d in main.world.find_children("*", "Area3D", true, false):
		if d is InteriorDoor and not (d as InteriorDoor).is_exit:
			var dd := (d as Node3D).global_position.distance_to(main.player.global_position)
			if dd < bd and (d as InteriorDoor).interior_scene != "":
				bd = dd
				best = d
	if best == null:
		_note("no interior door")
		return
	var door := best
	main.player.global_position = door.global_position + Vector3(0, 0.3, 0)
	await get_tree().process_frame
	door.set("_player", main.player)
	_timed("interior_enter", func() -> void: door.use())       # the player's press (a door verb, then the room: one or two frames)
	await _wait(5.0)
	_timed("interior_leave", func() -> void: door.leave())
	await _wait(2.0)


func _autosave() -> void:
	Life.saves.reset_autosave_clock()
	_timed("autosave_call", func() -> void: Life.saves.autosave("route", false, true))


func _fight() -> void:
	var p: Vector2 = Vector2(main.player.global_position.x, main.player.global_position.z)
	main.call("_spawn_raiders", p + Vector2(14, 0), 6)
	var until := step_t + 20.0 * scale_t
	var k := 0
	while step_t < until:
		k += 1
		if k % 20 == 0:
			main.player.attack()
		await get_tree().process_frame


func _route() -> void:
	WorldSim.time_of_day = 5.5
	var ashford: Dictionary = WorldGen.settlements[0]
	var thorn := _settlement("thornfield")
	await get_tree().process_frame
	await get_tree().process_frame
	if only_approach:
		recording = true
		await _approach_and_town(ashford, thorn, thorn["pos"])
		recording = false
		_finish()
		return
	# 1 Ashford: settle (boot streaming, not recorded), then through the 06:00 trade.
	_begin("boot_settle")
	_ring(ashford)
	await _wait(8.0 / scale_t)
	recording = true
	_begin("ashford_plaza")
	await _wait(45.0)
	_begin("ashford_autosave")
	_autosave()
	await _wait(8.0)
	_begin("ashford_talk")
	await _talk_someone()
	_begin("ashford_quest")
	await _quest_step()
	await _wait(5.0)
	_begin("ashford_interior")
	await _interior()
	_begin("ashford_ring2")
	_ring(ashford)
	await _wait(20.0)
	# 2 the road to Thornfield.
	_begin("road")
	var dir := ((thorn["pos"] as Vector2) - (ashford["pos"] as Vector2)).normalized()
	_leg((ashford["pos"] as Vector2) + dir * (float(ashford["radius"]) + 20.0), dir)
	await _wait(80.0)
	_begin("fast_travel")
	var th_pos: Vector2 = thorn["pos"]
	WorldSim.advance_hours(2.0)
	path_mode = ""
	_tp(th_pos + Vector2(float(thorn["plan"]["plaza_r"]) + 10.0, 0.0), 0.0)
	await _wait(10.0)
	_begin("thornfield_plaza")
	_ring(thorn)
	await _wait(40.0)
	_begin("thornfield_interior")
	await _interior()
	_begin("thornfield_fight")
	await _fight()
	_begin("thornfield_talk")
	await _talk_someone()
	_begin("thornfield_autosave")
	_autosave()
	await _wait(10.0)
	# 3 the wilds.
	_begin("wilds")
	var best := -1.0
	var bdir := Vector2.RIGHT
	for i in 16:
		var d := Vector2.from_angle(TAU * i / 16.0)
		var dens := 0.0
		for k in 30:
			var q: Vector2 = th_pos + d * (float(thorn["radius"]) + 40.0 + k * 30.0)
			dens += WorldGen.forest_density(q.x, q.y)
		if dens > best:
			best = dens
			bdir = d
	_leg(th_pos + bdir * (float(thorn["radius"]) + 80.0), bdir)
	await _wait(100.0)
	await _approach_and_town(ashford, thorn, th_pos)


func _approach_and_town(ashford: Dictionary, thorn: Dictionary, th_pos: Vector2) -> void:
	# 4 a generated town far away: walk in from 720 m (it streams in over frames at 650 m), then teleport into its plaza.
	var gen: Dictionary = {}
	var far := 0.0
	for s: Dictionary in WorldGen.settlements:
		var dd := (s["pos"] as Vector2).distance_to(th_pos)
		if s != thorn and s != ashford and dd > far and dd < 4000.0:
			far = dd
			gen = s
	if gen.is_empty():
		gen = WorldGen.settlements[WorldGen.settlements.size() - 1]
	_note("generated town %s at %.0f m" % [gen["name"], far])
	_begin("approach_town")
	var gdir := Vector2.from_angle(1.0)
	_leg((gen["pos"] as Vector2) - gdir * (float(gen["radius"]) + 720.0), gdir)
	await _wait(90.0)
	_begin("town_teleport")
	WorldSim.advance_hours(3.0)
	_ring(gen)
	await _wait(10.0)
	_begin("town_plaza")
	await _wait(50.0)
	_begin("town_interior")
	await _interior()
	_begin("town_talk")
	await _talk_someone()
	_begin("town_autosave")
	_autosave()
	await _wait(10.0)
	_begin("town_ring2")
	_ring(gen)
	await _wait(40.0)
	if not only_approach:
		recording = false
		_finish()


# --- frame loop ---------------------------------------------------------------------------------------

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
			if node.is_processing() or node.is_physics_processing():
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
	ticks += 1
	main.player.set("_invulnerable", 1.0)      # the route walks the wilds at night: a death screen would pause the tree and freeze the run
	if path_mode != "":
		var pl: Node3D = main.player
		var p := Vector2.ZERO
		if path_mode == "ring":
			ring_a += SPEED * delta / ring_r
			p = ring_c + Vector2.from_angle(ring_a) * ring_r
			main.player.set_camera(ring_a + PI, -0.14)
		else:
			along += SPEED * delta
			p = leg_from + leg_dir * along
			main.player.set_camera(atan2(-leg_dir.x, -leg_dir.y), -0.14)
		if InteriorDoor.active == null:
			pl.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.1, p.y)
	if raw:
		return
	for id: int in reg:
		var e: Array = reg[id]
		if e[3] and is_instance_valid(e[0]) and (e[0] as Node).is_inside_tree() and (e[0] as Node).can_process():
			var u := Time.get_ticks_usec()
			(e[0] as Node).call("_physics_process", delta)
			var k: String = "phys " + String(e[1])
			frame_us[k] = int(frame_us.get(k, 0)) + Time.get_ticks_usec() - u


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if now / 1000 - _beat_ms >= 20000:      # a heartbeat every 20 real seconds: a run that stops advancing says where it stands
		_beat_ms = now / 1000
		print("HITCH beat step=%s step_t=%.1f total=%.0f paused=%s time_scale=%.2f player=%s interior=%s dead=%s" % [step_name, step_t, t_total,
			get_tree().paused, Engine.time_scale, main.player.global_position, InteriorDoor.active != null, main.player.dead])
	if get_tree().paused:
		# A "Growing Up" life-event card (life_event_popup.gd) pauses the tree until a choice is picked: nobody is here to pick one.
		var pop: Node = main.hud.get_node_or_null("LifeEventPopup")
		if pop != null and pop.visible:
			pop.call("close")
		get_tree().paused = false
		_note("a pause (life event card or a menu) was dismissed")
	if last_us > 0:
		_record_frame((now - last_us - overhead_us) / 1000.0, delta)
	overhead_us = 0
	last_us = Time.get_ticks_usec()
	step_t += delta
	t_total += delta
	scan_t += delta
	if not raw and (scan_t > 2.0 or reg.is_empty()):
		scan_t = 0.0
		_scan()
		overhead_us = Time.get_ticks_usec() - last_us
	if not raw:
		for id: int in reg:
			var e: Array = reg[id]
			if e[2] and is_instance_valid(e[0]) and (e[0] as Node).is_inside_tree() and (e[0] as Node).can_process():
				var u := Time.get_ticks_usec()
				(e[0] as Node).call("_process", delta)
				var k: String = e[1]
				frame_us[k] = int(frame_us.get(k, 0)) + Time.get_ticks_usec() - u


## One frame = the time from this node's previous _process to this one (everything the engine and the scripts did in between).
func _record_frame(ms: float, _delta: float) -> void:
	if recording:
		frames.append(ms)
		step_of.append(steps.size() - 1)
		if ms >= KEEP_MIN_MS:
			var top: Array = []
			for k: String in frame_us:
				top.append([k, snappedf(frame_us[k] / 1000.0, 0.01)])
			top.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
			var ev: Array = []
			var scripted := false
			for pe: Array in Probe.events:
				ev.append([pe[0], snappedf(pe[1] / 1000.0, 0.01)])
				if String(pe[0]) == "route.travel_teleport":     # the teleport itself runs behind the fade (a loading step), not a hitch
					scripted = true
			slow.append({"frame": frames.size() - 1, "ms": snappedf(ms, 0.01), "step": step_name, "t": snappedf(t_total, 0.1),
				"phys_tick": ticks != last_ticks, "scripted": scripted, "events": ev, "top": top.slice(0, 3)})
	last_ticks = ticks
	Probe.events.clear()
	frame_us.clear()


func _finish() -> void:
	_release_all()
	Probe.capture = false
	var n := frames.size()
	var s := frames.duplicate()
	s.sort()
	var c8 := 0
	var c16 := 0
	var c33 := 0
	var c50 := 0
	var c8_np := 0         # over 8 ms with no physics tick in the frame
	var scripted_ms: Array = []
	for sf: Dictionary in slow:
		if sf["scripted"]:
			scripted_ms.append(sf["ms"])
	for f in frames:
		if f > 8.0:
			c8 += 1
		if f > 16.0:
			c16 += 1
		if f > 33.0:
			c33 += 1
		if f > 50.0:
			c50 += 1
	for sf: Dictionary in slow:
		if not sf["phys_tick"]:
			c8_np += 1
	var worst: Array = slow.filter(func(w: Dictionary) -> bool: return not w["scripted"])
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms"] > b["ms"])
	var per_step := {}
	for sf: Dictionary in slow:
		var d: Dictionary = per_step.get(sf["step"], {"over8": 0, "max": 0.0})
		d["over8"] += 1
		d["max"] = maxf(d["max"], sf["ms"])
		per_step[sf["step"]] = d
	var probes: Array = []
	for k: String in Probe.us:
		probes.append({"key": k, "calls": int(Probe.calls[k]), "total_ms": Probe.us[k] / 1000.0, "worst_ms": Probe.worst[k] / 1000.0})
	probes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["worst_ms"] > b["worst_ms"])
	var res := {
		"frames": n, "wall_s": t_total, "mean_ms": 0.0, "p50": s[n / 2] if n > 0 else 0.0, "p95": s[n * 95 / 100] if n > 0 else 0.0,
		"p99": s[n * 99 / 100] if n > 0 else 0.0, "p999": s[mini(n - 1, n * 999 / 1000)] if n > 0 else 0.0, "max": s[n - 1] if n > 0 else 0.0,
		"over8": c8, "over16": c16, "over33": c33, "over50": c50, "over8_no_phys_tick": c8_np,
		"scripted_frames_ms": scripted_ms, "per_step": per_step, "worst": worst.slice(0, 60), "all_slow": slow, "probes": probes, "notes": notes,
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	var tot := 0.0
	for f in frames:
		tot += f
	res["mean_ms"] = tot / maxf(1.0, n)
	print("HITCH frames=%d wall=%.0fs mean=%.2f p50=%.2f p95=%.2f p99=%.2f p99.9=%.2f max=%.1f" % [n, t_total, res["mean_ms"], res["p50"], res["p95"], res["p99"], res["p999"], res["max"]])
	print("HITCH over8=%d (no physics tick: %d) over16=%d over33=%d over50=%d  static=%.0f MB nodes=%d" % [c8, c8_np, c16, c33, c50, res["memory_static_mb"], res["nodes"]])
	for st: String in per_step:
		print("HITCH   step %-22s over8=%4d max=%.1f" % [st, per_step[st]["over8"], per_step[st]["max"]])
	for i in mini(40, worst.size()):
		var w: Dictionary = worst[i]
		print("HITCH worst %6.1f ms  %-20s t=%.0f tick=%s events=%s top=%s" % [w["ms"], w["step"], w["t"], w["phys_tick"], str(w["events"]), str(w["top"])])
	for pr: Dictionary in probes.slice(0, 30):
		print("HITCH probe %-40s calls=%6d total=%9.1f ms worst=%7.2f" % [pr["key"], pr["calls"], pr["total_ms"], pr["worst_ms"]])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(res, "\t"))
			f.close()
	print("HITCH done")
	get_tree().quit(0)
