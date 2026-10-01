extends Node
## QA driver: one game boot, a similar camera on several contrasting towns ("could I tell them apart without names?").
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom --rendering-driver vulkan -- --adult --quality=high --shot=none \
##       --qa=res://tools_qa/town_identity/town_sheet.gd [--towns=Skarholm,Longmeadow,...] [--out=/tmp/claude-0/shots/towns] [--hour=14]
## Saves <out>/<town>_air.png (an elevated 3/4 view from outside the first gate: the same camera relative to every town) and
## <out>/<town>_street.png (eye level at the first gate road toward the square); the caller tiles them (PIL). Never run with --headless.

const DEFAULT_TOWNS := ["Skarholm", "Longmeadow", "Highcliff", "Harrowgate", "Amberley", "Marrowick", "Saltwick", "Ashford"]
## --towns=villages: 8 villages with different signatures + 4 towns (the village signature sheet).
const VILLAGE_SET := ["Eastmere", "Oakvale", "Cindermoor", "Amberley", "Marrowick", "Ashford", "Harrowgate", "Frostmere", "Ironmarch", "Highcliff", "Longmeadow", "Saltwick"]
var main: Node
var cam: Camera3D
var _hour := 15.0


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var out_dir := String(args.get("out", "/tmp/claude-0/shots/towns"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var towns: Array = String(args.get("towns", "")).split(",", false) if args.has("towns") else DEFAULT_TOWNS
	if towns == ["villages"]:
		towns = VILLAGE_SET
	main.hud.visible = false
	main.player.visible = false
	WorldSim.time_of_day = float(args.get("hour", "15.0"))
	_hour = float(args.get("hour", "15.0"))
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 1200.0
	main.world.add_child(cam)
	for name: String in towns:
		var town: Dictionary = {}
		for s in WorldGen.settlements:
			if s["name"] == name:
				town = s
		if town.is_empty():
			push_error("no town " + name)
			continue
		await _visit(town, out_dir)
	get_tree().quit(0)


func _visit(town: Dictionary, out_dir: String) -> void:
	WorldSim.time_of_day = _hour      # the world clock runs: pin the hour for every town
	var plan: Dictionary = town["plan"]
	var c: Vector2 = town["pos"]
	var r: float = float(town["radius"])
	var g0: float = float(plan["gates"][0])
	var dir := Vector2(cos(g0), sin(g0))
	var wr: float = float(plan["wall_radius"]) if plan["walls"] else r * 1.1
	# The player is parked well outside the town (a station next to him opens a work dialog): the town is built around its centre.
	var park := c + dir * (wr + 90.0)
	main.call("_teleport", park, atan2(-dir.x, -dir.y))
	await get_tree().create_timer(0.4).timeout
	WorldSim.time_of_day = _hour
	var centre3 := Vector3(c.x, WorldGen.height(c.x, c.y), c.y)
	main.settlements.focus = centre3
	for i in 5:
		main.settlements.update_now()
	main.settlements.finish_prop_jobs()
	main.population.focus = centre3
	main.population.refresh()
	main.terrain.focus = centre3
	main.terrain.build_all_now()
	for i in 90:
		await get_tree().process_frame
	# 1) the elevated three-quarter view: the same offset relative to every town's size
	var back := 66.0 + 0.55 * r
	var side := Vector2(-dir.y, dir.x)
	var from := c + dir * back + side * back * 0.35
	cam.fov = 72.0
	cam.global_position = Vector3(from.x, maxf(WorldGen.height(from.x, from.y) + 22.0, WorldGen.height(c.x, c.y) + 36.0 + 0.16 * r), from.y)
	# The streamers follow the player: put him under the camera and rebuild the ground there (a chunk missing = a hole in the town).
	main.player.global_position = Vector3(from.x, WorldGen.height(from.x, from.y) + 0.3, from.y)
	main.terrain.focus = main.player.global_position
	main.terrain.build_all_now()
	main.settlements.focus = centre3
	main.settlements.update_now()
	cam.look_at(Vector3(c.x, WorldGen.height(c.x, c.y) + 3.0, c.y))
	cam.current = true
	for i in 60:
		await get_tree().process_frame
	await _wait_ring(main.player.global_position, String(town["name"]) + " air")
	_save(town, out_dir, "air")
	if OS.get_cmdline_user_args().has("--probe"):
		var troot: Node = main.settlements._built.get(town["id"])
		for m in troot.find_children("*", "MultiMeshInstance3D", true, false):
			(m as MultiMeshInstance3D).material_override = null if (m as MultiMeshInstance3D).material_override != null and false else (m as MultiMeshInstance3D).material_override
		var ov := 0
		for m in troot.find_children("*", "MultiMeshInstance3D", true, false):
			var mi := m as MultiMeshInstance3D
			if mi.material_override != null and mi.multimesh.use_colors:
				mi.set_meta("ov", mi.material_override)
				mi.material_override = null
				ov += 1
		print("PROBE overrides removed ", ov)
		for i in 6:
			await get_tree().process_frame
		_save(town, out_dir, "probe_noover")
		for m in troot.find_children("*", "MultiMeshInstance3D", true, false):
			var mi2 := m as MultiMeshInstance3D
			if mi2.has_meta("ov"):
				mi2.material_override = mi2.get_meta("ov")
			mi2.visibility_range_begin = 0.0
			mi2.visibility_range_end = 0.0
		for i in 6:
			await get_tree().process_frame
		_save(town, out_dir, "probe_noranges")
	# 2) eye level from the first gate road toward the square
	var eye := c + dir * (float(plan["plaza_r"]) + 30.0)
	cam.global_position = Vector3(eye.x, WorldGen.height(eye.x, eye.y) + 2.6, eye.y)
	cam.look_at(Vector3(c.x, WorldGen.height(c.x, c.y) + 3.2, c.y))
	cam.fov = 62.0
	main.player.global_position = Vector3(park.x, WorldGen.height(park.x, park.y) + 0.3, park.y)
	main.terrain.focus = Vector3(eye.x, 0, eye.y)
	main.terrain.build_all_now()
	for i in 30:
		await get_tree().process_frame
	await _wait_ring(Vector3(eye.x, 0, eye.y), String(town["name"]) + " street")
	_save(town, out_dir, "street")
	await _feature_shot(town, out_dir)


## A close look at the town's signature piece (mine head-frame, palisade, standing stones, boat, caravan wagon, tower ...).
func _feature_shot(town: Dictionary, out_dir: String) -> void:
	var TI := load("res://scripts/world/town_identity.gd")
	var troot: Node = main.settlements._built.get(town["id"])
	if troot == null:
		return
	var ids := ["g:region/mine/mine_winch", "g:runestone", "g:region/road/caravan_wagon", "g:rowboat", "watchtower", "g:region/ruins/bandit_palisade", "g:region/nature/bush_round", "g:region/mine/ore_pile_coal"]
	var c: Vector2 = town["pos"]
	for id in ids:
		var mesh: Mesh = TI.mesh_by_id(id)
		var best := Vector3.ZERO
		var found := false
		var bd := INF
		for m in troot.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (m as MultiMeshInstance3D).multimesh
			if mm.mesh != mesh:
				continue
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				var d := Vector2(o.x, o.z).distance_to(c)
				if d < bd:
					bd = d
					best = o
					found = true
		if not found:
			continue
		var dir := (Vector2(best.x, best.z) - c).normalized()
		var from := Vector2(best.x, best.z) + dir * 26.0 + Vector2(-dir.y, dir.x) * 8.0
		cam.global_position = Vector3(from.x, WorldGen.height(from.x, from.y) + 7.0, from.y)
		cam.look_at(best + Vector3(0, 2.0, 0))
		main.player.global_position = Vector3(from.x, WorldGen.height(from.x, from.y) + 0.3, from.y)
		main.terrain.focus = main.player.global_position
		main.terrain.build_all_now()
		for i in 40:
			await get_tree().process_frame
		_save(town, out_dir, "feature")
		print("FEATURE ", town["name"], " ", id)
		return


## True when every terrain chunk of the streamer's ring around `p` is built, its worker tasks are done and no plan is waiting.
func _ring_ok(p: Vector3) -> bool:
	var t = main.terrain
	t.focus = p
	var center: Vector2i = t.chunk_of(p)
	for dz in range(-t.view_radius, t.view_radius + 1):
		for dx in range(-t.view_radius, t.view_radius + 1):
			if not t._chunks.has(center + Vector2i(dx, dz)):
				return false
	return t._tasks.is_empty()


## Blocks until the terrain streamer reports the ring under the camera complete (up to ~900 frames); logs the outcome.
func _wait_ring(p: Vector3, label: String) -> void:
	main.terrain.focus = p
	main.terrain.build_all_now()
	var n := 0
	while not _ring_ok(p) and n < 900:
		main.terrain.build_all_now()
		await get_tree().process_frame
		n += 1
	for i in 6:
		await get_tree().process_frame     # one more frame: collision / grass of the last chunk
	print("RING %s complete=%s frames=%d chunks=%d" % [label, str(_ring_ok(p)), n, main.terrain.loaded_count()])


func _save(town: Dictionary, out_dir: String, tag: String) -> void:
	WorldSim.time_of_day = _hour
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [out_dir, String(town["name"]), tag]
	img.save_png(path)
	print("SHOT ", path)
