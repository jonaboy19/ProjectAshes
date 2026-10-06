extends Node
## Perf route (release QA): the same town walk on the PC and on the S22, so numbers compare.
## Walks the player (no input needed) through: Ashford's plaza ring -> Kingsreach from its gate into the
## market -> past the placed Meshy sites around Kingsreach, then loops until --seconds is up.
## Prints ROUTE lines (one per 10 s window) and a ROUTE_SUM line, then quits.
##   PC:    godot --path kingdom --rendering-method mobile --resolution 1280x720 -- --adult --quality=low \
##            --qa=res://tools_qa/perf/town_route.gd --seconds=120 [--noquit]
##   Phone: adb shell am start -n com.risingashes.game/com.godot.game.GodotApp --esa command_line_params \
##            ... (not forwarded on the S22: build a QA APK with these args baked in, tier/seconds from user://qa_args.txt,
##            see tools/qa/phone/route.sh)
## Ablation switches for profiling are the game's own (--no-goods, --no-decals, --r1filloff, --medievaloff ...).
const SPEED := 5.5          # m/s, a jog
var main: Node
var legs: Array = []         # [[from: Vector2, to: Vector2, name], ...]
var leg := 0
var along := 0.0
var t := 0.0
var dur := 120.0
var win := PackedFloat32Array()
var all := PackedFloat32Array()
var win_t := 0.0
var max_draws := 0
var max_prims := 0
var sum_draws := 0.0
var sum_prims := 0.0
var samples := 0
var leg_stats := {}
var quit_at_end := true
var uncap := false
var cpu := PackedFloat32Array()
var gpu := PackedFloat32Array()
var census_at: Array = []     # --census=20,40,65: route seconds at which to print a draw census


func run(m: Node) -> void:
	main = m
	for raw in Array(OS.get_cmdline_user_args()) + Array(Quality.qa_file_args()):
		var a := String(raw).strip_edges()
		if a.begins_with("--seconds="):
			dur = float(a.get_slice("=", 1))
		elif a.begins_with("--census="):
			for v in a.get_slice("=", 1).split(","):
				census_at.append(float(v))
		elif a == "--uncap":
			uncap = true
		elif a == "--noquit":
			quit_at_end = false
	if Array(Quality.qa_file_args()).has("--ablate") or OS.get_cmdline_user_args().has("--ablate"):
		var ab: Node = load("res://tools_qa/perf/ablate.gd").new()      # the S22 QA APK has this driver baked in
		get_parent().add_child(ab)
		ab.call("run", main)
		set_process(false)
		set_physics_process(false)
		return
	WorldSim.time_of_day = 15.0
	RenderingServer.viewport_set_measure_render_time(main.viewport.get_viewport_rid(), true)
	_build_route()
	_start_leg(0)
	set_physics_process(true)


func _build_route() -> void:
	var st: Array = WorldGen.settlements
	var ash: Dictionary = st[0]
	var c0: Vector2 = ash["pos"]
	var r0: float = float(ash["plan"]["plaza_r"]) + 12.0
	for i in 6:      # plaza ring, 6 chords
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		legs.append([c0 + Vector2(cos(a0), sin(a0)) * r0, c0 + Vector2(cos(a1), sin(a1)) * r0, "ashford"])
	var cap: Dictionary = st[1]
	var cp: Vector2 = cap["pos"]
	var gate: float = cap["plan"]["gates"][0] if not (cap["plan"]["gates"] as Array).is_empty() else 0.0
	var gdir := Vector2(cos(gate), sin(gate))
	legs.append([cp + gdir * (float(cap["radius"]) + 25.0), cp + gdir * (float(cap["plan"]["plaza_r"]) + 4.0), "kingsreach_gate"])
	var pr: float = float(cap["plan"]["plaza_r"]) + 6.0
	for i in 3:
		var a0 := gate + TAU * i / 3.0
		var a1 := gate + TAU * (i + 1) / 3.0
		legs.append([cp + Vector2(cos(a0), sin(a0)) * pr, cp + Vector2(cos(a1), sin(a1)) * pr, "kingsreach_market"])
	# Meshy fill/extra sites nearest Kingsreach: walk past the three closest.
	var R1W := load("res://scripts/world/region1_world.gd")
	var sites: Array = []
	var extra: Dictionary = R1W.data("meshy_extra.json")
	for es: Dictionary in extra.get("extra_sites", []):
		var s: Dictionary = R1W.site(String(es.get("id", "")))
		if not s.is_empty():
			sites.append(s)
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).distance_to(cp) < (b["pos"] as Vector2).distance_to(cp))
	for s: Dictionary in sites.slice(0, 3):
		var p: Vector2 = s["pos"]
		var side := (p - cp).normalized().orthogonal() * (float(s.get("clear", 10.0)) + 6.0)
		legs.append([p - side * 2.0, p + side * 2.0, "meshy_site"])
	print("ROUTE legs=%d meshy_sites=%d" % [legs.size(), mini(3, sites.size())])


func _start_leg(i: int) -> void:
	leg = i % legs.size()
	along = 0.0
	var from: Vector2 = legs[leg][0]
	var prev_to: Vector2 = legs[(leg - 1 + legs.size()) % legs.size()][1]
	if leg == 0 or from.distance_to(prev_to) > 2.0:
		var d: Vector2 = (legs[leg][1] as Vector2) - from
		main.call("_teleport", from, atan2(-d.x, -d.y))


func _physics_process(delta: float) -> void:
	if legs.is_empty():
		return
	var from: Vector2 = legs[leg][0]
	var to: Vector2 = legs[leg][1]
	var len := maxf(from.distance_to(to), 0.1)
	along += SPEED * delta
	var p := from.lerp(to, minf(along / len, 1.0))
	var pl: Node3D = main.player
	pl.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.1, p.y)
	var d := to - from
	main.player.set_camera(atan2(-d.x, -d.y) + sin(t * 0.4) * 0.5, -0.14)
	if along >= len:
		_start_leg(leg + 1)


func _process(delta: float) -> void:
	if legs.is_empty():
		return
	t += delta
	if uncap:
		Engine.max_fps = 0
	if t < 6.0:          # streaming settle after the first teleport
		return
	win.append(delta * 1000.0)
	cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(main.viewport.get_viewport_rid()))
	all.append(delta * 1000.0)
	var dr := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	max_draws = maxi(max_draws, dr)
	max_prims = maxi(max_prims, pr)
	sum_draws += dr
	sum_prims += pr
	samples += 1
	var nm: String = legs[leg][2]
	var ls: Array = leg_stats.get(nm, [0, 0, 0.0, 0])
	leg_stats[nm] = [maxi(ls[0], dr), maxi(ls[1], pr), float(ls[2]) + delta * 1000.0, int(ls[3]) + 1]
	if not census_at.is_empty() and t >= float(census_at[0]):
		census_at.pop_front()
		_census(nm)
	win_t += delta
	if win_t >= 10.0:
		print("ROUTE t=%d leg=%s %s cpu=%.1f gpu=%.1f" % [int(t), nm, _summary(win), _mean(cpu), _mean(gpu)])
		win.clear()
		cpu.clear()
		gpu.clear()
		win_t = 0.0
	if t >= dur + 6.0:
		var per := ""
		for k: String in leg_stats:
			var v: Array = leg_stats[k]
			per += " %s:ms=%.1f,maxdraws=%d,maxprims=%d" % [k, float(v[2]) / maxi(1, int(v[3])), v[0], v[1]]
		print("ROUTE_SUM %s avgdraws=%d avgprims=%d maxdraws=%d maxprims=%d legs:%s" % [_summary(all), int(sum_draws / maxi(1, samples)), int(sum_prims / maxi(1, samples)), max_draws, max_prims, per])
		legs.clear()
		if quit_at_end:
			get_tree().quit(0)


func _summary(ft: PackedFloat32Array) -> String:
	var s := ft.duplicate()
	s.sort()
	var n := s.size()
	var tot := 0.0
	for v in s:
		tot += v
	return "fps=%.1f p50=%.1f p95=%.1f p99=%.1f draws=%d prims=%d vram=%d tex=%d buf=%d static=%d nodes=%d objs=%d res=%d" % [
		1000.0 * n / maxf(tot, 0.001), s[n / 2], s[mini(n - 1, n * 95 / 100)], s[mini(n - 1, n * 99 / 100)],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))]


## Draw census: geometry the camera draws (frustum + visibility range), by owner and by mesh, with surfaces
## (~ colour-pass draws), triangles (LOD0) and shadow-casting surfaces within the sun's shadow distance.
func _census(tag: String) -> void:
	var cam := main.viewport.get_camera_3d() as Camera3D
	var cp := cam.global_position
	var planes := cam.get_frustum()
	var sd := 40.0
	for l in main.world.find_children("*", "DirectionalLight3D", true, false):
		if (l as DirectionalLight3D).shadow_enabled:
			sd = (l as DirectionalLight3D).directional_shadow_max_distance
	var own := {}
	var mesh_d := {}
	var tot := [0, 0, 0]
	for n in main.world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var d := box.get_center().distance_to(cp)
		if (g.visibility_range_end > 0.0 and d > g.visibility_range_end) or d < g.visibility_range_begin:
			continue
		var inside := true
		var c := box.get_center()
		var e := box.size * 0.5
		for pl in planes:
			if pl.distance_to(c) > absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z:
				inside = false
				break
		var mesh: Mesh = null
		var inst := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
			var mm := (g as MultiMeshInstance3D).multimesh
			inst = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		var surf := mesh.get_surface_count() if mesh else 1
		var shadow := g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and d < sd + e.length()
		if not inside and not shadow:
			continue
		var tris := 0
		if mesh is ArrayMesh:
			for si in mesh.get_surface_count():
				var n_idx: int = (mesh as ArrayMesh).surface_get_array_index_len(si)
				tris += n_idx / 3 if n_idx > 0 else (mesh as ArrayMesh).surface_get_array_len(si) / 3
		var owner := _owner_of(g)
		var o: Array = own.get(owner, [0, 0, 0])
		var vis := surf if inside else 0
		own[owner] = [o[0] + vis, o[1] + (tris * inst if inside else 0), o[2] + (surf if shadow else 0)]
		tot = [tot[0] + vis, tot[1] + (tris * inst if inside else 0), tot[2] + (surf if shadow else 0)]
		var mn := (mesh.resource_path.get_file() if mesh and mesh.resource_path != "" else (String(g.name) if mesh else g.get_class())).left(40)
		var k := "%-22s %-40s" % [owner.right(22), mn]
		var m: Array = mesh_d.get(k, [0, 0, 0])
		mesh_d[k] = [m[0] + vis, m[1] + (tris * inst if inside else 0), m[2] + (surf if shadow else 0)]
	print("CENSUS %s t=%d draws(surf)=%d tris=%d shadow_surf=%d (sun shadow %.0f m)" % [tag, int(t), tot[0], tot[1], tot[2], sd])
	var ks := own.keys()
	ks.sort_custom(func(a, b) -> bool: return own[a][0] + own[a][2] > own[b][0] + own[b][2])
	for k in ks.slice(0, 14):
		print("CENSUS  owner %-34s surf=%4d tris=%7d shadow=%4d" % [k, own[k][0], own[k][1], own[k][2]])
	var mk := mesh_d.keys()
	mk.sort_custom(func(a, b) -> bool: return mesh_d[a][0] + mesh_d[a][2] > mesh_d[b][0] + mesh_d[b][2])
	for k in mk.slice(0, 70):
		print("CENSUS  mesh %s surf=%4d tris=%7d shadow=%4d" % [k, mesh_d[k][0], mesh_d[k][1], mesh_d[k][2]])
	mk.sort_custom(func(a, b) -> bool: return mesh_d[a][1] > mesh_d[b][1])
	for k in mk.slice(0, 8):
		print("CENSUS  tris %s surf=%4d tris=%7d" % [k, mesh_d[k][0], mesh_d[k][1]])


func _owner_of(g: Node) -> String:
	var chain: Array[String] = []
	var p := g.get_parent()
	while p != null and p != main.world and p != get_tree().root:
		var nm := String(p.name)
		if p.get_script() != null and String(p.get_script().get_global_name()) != "":
			nm = String(p.get_script().get_global_name())
		elif nm.begins_with("@"):
			nm = p.get_class()
		chain.push_front(nm.rstrip("0123456789_-"))
		p = p.get_parent()
	return "/".join(chain.slice(0, 2)) if not chain.is_empty() else "world"


static func _mean(a: PackedFloat32Array) -> float:
	var tot := 0.0
	for v in a:
		tot += v
	return tot / maxf(1.0, a.size())
