extends SceneTree
## Benchmark slice: the SAME countryside route every time (BENCHMARK_SLICE.md acceptance), framed like ref 01: the player walks the
## route on the gameplay camera (behind, ~2.5 m up, slight downward look). Driven by real input: move_forward held, the camera yaw
## steered toward the path 8 m ahead (the player moves relative to the camera). A pause at the Waymark Stone turns the camera north.
## Movie Maker; hour pinned; weather clear; HUD hidden.
## Godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie <abs>.avi -s res://tools_qa/world/route_walk.gd -- --adult
##   --world_macro=real --terrain_backend=terrain3d --profile=pc --quality=high [--slice_off] [--hour=10.5]

const BOOT := 600
const PAUSE_S := 5.0
const PITCH := -0.22
var main: Node
var frame := 0
var hour := 10.5
var pts := PackedVector2Array()
var stone := Vector2(318, 58)
var _seg := 0
var _pause_left := -1.0
var _paused_done := false
var _yaw := 0.0
var _last_p := Vector2.INF
var _stuck_t := 0.0
const MAX_S := 200.0
var _ft := PackedFloat32Array()
var _mon := [0.0, 0.0, 0.0, 0.0]   # sums: draw calls, primitives, objects, gpu ms
var _last_us := 0
var _bd: Array = []          # --breakdown: [node, phase, base_prims, base_draws]
var _bd_on := false


func _collect(n: Node, depth: int) -> void:
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible and not (c is Camera3D) and not (c is Light3D):
			if c.get_child_count() > 0 or c is GeometryInstance3D:
				_bd.append([c, 0, 0.0, 0.0])
			if depth < 7 and c.get_child_count() < 400 and String(c.name) != "Player":
				_collect(c, depth + 1)
		elif not (c is Node3D) and depth < 4:
			_collect(c, depth + 1)


## --breakdown (perf gate): at the first route stop, hide each world child in turn and print how many primitives / draws it costs.
func _breakdown_step() -> bool:
	if _bd.is_empty():
		print("[route] BREAKDOWN done")
		_perf()
		quit()
		return true
	var e: Array = _bd[0]
	if not is_instance_valid(e[0]):
		_bd.pop_front()
		return false
	var n: Node3D = e[0]
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	e[1] += 1
	if e[1] == 3:
		e[2] = prims
		e[3] = draws
		n.visible = false
	elif e[1] == 6:
		print("[route] BREAKDOWN %-40s prims=%9.0f draws=%5.0f" % [String(root.get_path_to(n)).right(60), e[2] - prims, e[3] - draws])
		n.visible = true
		_bd.pop_front()
	return false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			hour = float(a.get_slice("=", 1))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/real/slice_route.json"))
	for p: Array in d["path"]["points"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	stone = Vector2(float(d["landmark"]["at"][0]), float(d["landmark"]["at"][1]))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _hide_overlays() -> void:
	var hud: Node = main.get("hud")
	if hud:
		hud.visible = false
	for n in root.find_children("*", "CanvasLayer", true, false):
		if not n.find_children("*", "SubViewportContainer", true, false).is_empty():
			for ch in n.get_children():
				if ch is CanvasItem and not ch is SubViewportContainer and ch.find_children("*", "SubViewportContainer", true, false).is_empty():
					(ch as CanvasItem).visible = false
			continue
		(n as CanvasLayer).visible = false


## Real frame times of the walk (meaningful without --write-movie): avg / p95 / worst ms and fps.
func _perf() -> void:
	if _ft.is_empty():
		print("[route] PERF none")
		return
	var a := Array(_ft)
	a.sort()
	var tot := 0.0
	for v in a:
		tot += float(v)
	var avg := tot / a.size()
	var n := float(a.size())
	print("[route] MON avg draws=%.0f prims=%.0f objects=%.0f gpu_ms=%.2f" % [_mon[0] / n, _mon[1] / n, _mon[2] / n, _mon[3] / n])
	print("[route] PERF frames=%d avg_ms=%.2f p95_ms=%.2f worst_ms=%.2f fps=%.1f quality=%s" % [a.size(), avg, float(a[int(a.size() * 0.95)]), float(a[a.size() - 1]), 1000.0 / avg, OS.get_cmdline_user_args()])


static func _yaw_to(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func _process(dt: float) -> bool:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > BOOT + 90 and _last_us > 0:
		_ft.append((now - _last_us) / 1000.0)
		_mon[0] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_mon[1] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_mon[2] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_mon[3] += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	_last_us = now
	if frame < BOOT:
		return false
	var player: Node3D = main.get("player")
	if frame == BOOT:
		var w: Node = main.get("weather")
		if w:
			w.call("set_weather", "clear", 0.0)
			w.set("auto", false)
		main.call("_teleport", pts[0], 0.0)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		_yaw = _yaw_to(pts[1] - pts[0])
		player.visible = true
		print("[route] config world_macro=", WorldMacro.mode(), " real=", RealWorld.active(), " t3d_region_m=", Terrain3DBridge.region_m(), " slice=", not OS.get_cmdline_user_args().has("--slice_off"))
		return false
	if frame == BOOT + 240 and OS.get_cmdline_user_args().has("--breakdown"):
		_bd_on = true
		Input.action_release("move_forward")
		_collect(root, 0)
		print("[route] BREAKDOWN nodes=", _bd.size())
	if _bd_on:
		return _breakdown_step()
	if frame < BOOT + 60:          # settle after the teleport
		player.call("set_camera", _yaw, PITCH)
		return false
	root.get_node("WorldSim").set("time_of_day", hour)
	if frame % 15 == 0:
		_hide_overlays()
	var p := Vector2(player.global_position.x, player.global_position.z)
	if (frame - BOOT) / 30.0 > MAX_S:
		print("[route] time cap frames=", _ft.size())
		_perf()
		Input.action_release("move_forward")
		quit()
		return true
	# stuck guard (a wall, a fence): 3 s without 1 m of progress -> hop to the next path point and log it
	if _pause_left < 0.0:
		if _last_p == Vector2.INF or p.distance_to(_last_p) > 1.0:
			_last_p = p
			_stuck_t = 0.0
		else:
			_stuck_t += 1.0 / 30.0
			if _stuck_t > 3.0:
				var nxt := pts[mini(_seg + 1, pts.size() - 1)]
				print("[route] STUCK at ", p, " -> hop to ", nxt)
				main.call("_teleport", nxt, 0.0)
				_stuck_t = 0.0
				_last_p = Vector2.INF
	# advance along the path when the next point is near
	while _seg < pts.size() - 1 and p.distance_to(pts[_seg + 1]) < 6.0:
		_seg += 1
	if _seg >= pts.size() - 2 and p.distance_to(pts[pts.size() - 1]) < 18.0:
		Input.action_release("move_forward")
		_perf()
		quit()
		return true
	# the Waymark Stone pause: stop and look north to the fells
	if not _paused_done and p.distance_to(stone) < 48.0 and _pause_left < 0.0:
		_pause_left = PAUSE_S
	if _pause_left > 0.0:
		Input.action_release("move_forward")
		_pause_left -= 1.0 / 30.0
		var k := sin(PI * (1.0 - _pause_left / PAUSE_S))
		player.call("set_camera", lerp_angle(_yaw, _yaw_to(Vector2(0, -1)), k), PITCH + 0.12 * k)
		if _pause_left <= 0.0:
			_paused_done = true
			_pause_left = -1.0
		return false
	var target := pts[mini(_seg + 1, pts.size() - 1)]
	var want := _yaw_to(target - p)
	_yaw = lerp_angle(_yaw, want, 0.08)
	player.call("set_camera", _yaw, PITCH)
	Input.action_press("move_forward")
	return false
