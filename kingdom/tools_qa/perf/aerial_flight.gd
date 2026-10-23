extends Node
## Perf QA driver (--qa=res://tools_qa/perf/aerial_flight.gd): a long aerial flight. The player is moved along a path over the world at ground level
## (so the terrain/scatter/horizon stream exactly as for a walker, only fast) while the active camera hovers `--alt` metres above it looking along the path
## and 25 deg down. Default path: Ashford -> Kingsreach -> north ridge -> Ironmarch -> Silverrun valley -> Rift -> Ashen Scar -> Westfen (about 9 km).
## Prints FLIGHT lines (one per 10 s window: fps p50 / p95 / p99, vram) and FLIGHT_SUM with the Terrain3D region bake hitch (main-thread add_region).
##   Godot --path kingdom --resolution 2560x1440 -- --adult --profile=pc --quality=high [--terrain_backend=terrain3d --world_macro=valencious] \
##       --qa=res://tools_qa/perf/aerial_flight.gd [--speed=60] [--alt=400]
const WAYPOINTS := [Vector2(0, 0), Vector2(560, -420), Vector2(300, -1700), Vector2(2092, -2007), Vector2(2650, 230), Vector2(1130, 1004), Vector2(2700, 2513), Vector2(0, 1500), Vector2(-1500, 1800)]
var main: Node
var speed := 60.0
var alt := 400.0
var cam: Camera3D
var legs: Array = []
var leg := 0
var along := 0.0
var t := 0.0
var win := PackedFloat32Array()
var all := PackedFloat32Array()
var win_t := 0.0
var hitches := 0          # frames over 50 ms after the settle


func run(m: Node) -> void:
	main = m
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--speed="):
			speed = float(a.get_slice("=", 1))
		elif a.begins_with("--alt="):
			alt = float(a.get_slice("=", 1))
	WorldSim.time_of_day = 12.0
	RenderingServer.viewport_set_measure_render_time(main.viewport.get_viewport_rid(), true)
	for i in WAYPOINTS.size() - 1:
		legs.append([WAYPOINTS[i], WAYPOINTS[i + 1]])
	cam = Camera3D.new()
	cam.far = 4000.0
	(main.get("world") as Node3D).add_child(cam)
	var hud: Node = main.get("hud")
	if hud:
		hud.visible = false
	main.player.visible = false
	main.call("_teleport", WAYPOINTS[0], 0.0)
	cam.current = true
	set_physics_process(true)
	print("FLIGHT start speed=%.0f alt=%.0f legs=%d" % [speed, alt, legs.size()])


func _physics_process(delta: float) -> void:
	if legs.is_empty():
		return
	var from: Vector2 = legs[leg][0]
	var to: Vector2 = legs[leg][1]
	var len := maxf(from.distance_to(to), 0.1)
	along += speed * delta
	var p := from.lerp(to, minf(along / len, 1.0))
	main.player.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.1, p.y)
	var d := (to - from).normalized()
	cam.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + alt, p.y)
	cam.look_at(cam.global_position + Vector3(d.x, -0.45, d.y) * 100.0)
	if along >= len:
		along = 0.0
		leg += 1
		if leg >= legs.size():
			_finish()


func _process(delta: float) -> void:
	if legs.is_empty():
		return
	t += delta
	if t < 8.0:
		return
	win.append(delta * 1000.0)
	all.append(delta * 1000.0)
	if delta > 0.05:
		hitches += 1
	win_t += delta
	if win_t >= 10.0:
		print("FLIGHT t=%d %s" % [int(t), _summary(win)])
		win.clear()
		win_t = 0.0


func _finish() -> void:
	var st: Array = Terrain3DBridge.add_stats
	var mem := OS.get_memory_info()
	print("FLIGHT_SUM %s hitch_frames_over_50ms=%d t3d_regions_added=%d t3d_add_avg_ms=%.2f t3d_add_max_ms=%.2f static_mb=%d" % [_summary(all), hitches, int(st[0]),
		float(st[1]) / 1000.0 / maxf(1.0, float(st[0])), float(st[2]) / 1000.0, int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
	print("FLIGHT_MEM physical_mb=%d available_mb=%d" % [int(mem["physical"] / 1048576), int(mem["available"] / 1048576)])
	legs.clear()
	get_tree().quit(0)


func _summary(ft: PackedFloat32Array) -> String:
	var s := ft.duplicate()
	s.sort()
	var n := s.size()
	var tot := 0.0
	for v in s:
		tot += v
	return "fps=%.1f p50=%.1f p95=%.1f p99=%.1f max=%.1f draws=%d prims=%d vram=%d tex=%d buf=%d" % [1000.0 * n / maxf(tot, 0.001), s[n / 2], s[mini(n - 1, n * 95 / 100)],
		s[mini(n - 1, n * 99 / 100)], s[n - 1], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0)]
