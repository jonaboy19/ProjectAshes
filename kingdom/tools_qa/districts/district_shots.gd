extends Node
## QA driver for the Thornfield districts and the Rising Ashes road identity:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom --rendering-driver vulkan -- --adult --quality=high --shot=none \
##       --qa=res://tools_qa/districts/district_shots.gd [--town=Thornfield] [--out=/tmp/claude-0/shots/districts]
## Saves <out>_<name>.png for each district (a lot of the district seen from the street), the ward boundary, a checkpoint,
## a caravan, a cracked runestone and a Rift trader, then tools/qa contact-sheet is built by the caller (python PIL).
## Never run with --headless (black image).

const Districts := preload("res://scripts/world/districts.gd")
var main: Node
var cam: Camera3D
var out_base := "/tmp/claude-0/shots/districts"


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	out_base = String(args.get("out", out_base))
	var town_name := String(args.get("town", "Thornfield"))
	DirAccess.make_dir_recursive_absolute(out_base.get_base_dir())
	main.hud.visible = false
	main.player.visible = false
	WorldSim.time_of_day = float(args.get("hour", "14.5"))
	var town: Dictionary = {}
	for s in WorldGen.settlements:
		if s["name"] == town_name:
			town = s
	if town.is_empty():
		push_error("no town " + town_name)
		get_tree().quit(1)
		return
	main.call("_teleport", town["pos"], 0.0)
	await get_tree().create_timer(1.0).timeout
	main.region.focus = main.player.global_position
	_build_near(town["pos"])
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	main.world.add_child(cam)
	var plan: Dictionary = town["plan"]
	var only := String(args.get("only", ""))
	# Districts: look at the lot nearest each anchor, from out in its street.
	for dk: String in Districts.KINDS:
		if only != "" and not only.contains(dk):
			continue
		var anchors := Districts.anchors_of(plan.get("district_anchors", []), dk)
		if anchors.is_empty():
			continue
		# The anchor with the most lots of its district around it, and the lot nearest that anchor.
		var anchor: Dictionary = anchors[0]
		var most := -1
		for a: Dictionary in anchors:
			var n := 0
			for lot: Dictionary in plan["lots"]:
				if lot["district"] == dk and (lot["pos"] as Vector2).distance_to(a["pos"]) < 24.0:
					n += 1
			if n > most:
				most = n
				anchor = a
		var best: Dictionary = {}
		var bd := INF
		# Show the building that names the district when there is one (courthouse, smithy, inn), else the lot nearest the anchor.
		var star := {Districts.ADMIN: "courthouse", Districts.CRAFT: "blacksmith", Districts.INN: "inn"}
		for lot: Dictionary in plan["lots"]:
			if lot["district"] != dk:
				continue
			var d := (lot["pos"] as Vector2).distance_to(anchor["pos"])
			if star.has(dk) and (lot.get("role", "") == star[dk] or lot["asset"] == star[dk]):
				d -= 1000.0
			if d < bd:
				bd = d
				best = lot
		var target: Vector2 = (anchor["pos"] as Vector2) if best.is_empty() else (best["pos"] as Vector2)
		var from := _street_view(plan, target, float(args.get("dist", "13")))
		var back := (from - target).normalized()
		await _shot(town, from, target, "d_" + dk, float(args.get("h", "3.0")))
		if dk == Districts.MILITARY and plan.get("marks", {}).get("yard", Vector2.INF) != Vector2.INF:
			var yp: Vector2 = plan["marks"]["yard"]
			await _shot(town, _street_view(plan, yp, 12.0), yp, "d_yard", 4.0)
	# Outside the walls.
	if only == "" or only.contains("road"):
		var wm: Dictionary = _nearest_site("ward_marker", town["pos"], 220.0)
		if not wm.is_empty():
			var p: Vector2 = wm["pos"]
			var beyond: Vector2 = wm["beyond"]
			await _shot(town, p - beyond * 13.0 + Vector2(beyond.y, -beyond.x) * 3.0, p + beyond * 8.0, "r_boundary", 2.6)
			await _shot(town, p + beyond * 26.0 + Vector2(beyond.y, -beyond.x) * 5.0, p - beyond * 6.0, "r_boundary_back", 2.6)
		for ident: String in ["checkpoint", "caravan", "cracked_stone", "rift_trader", "warning_post", "abandoned_cart", "shrine"]:
			var st := _nearest_site(ident, town["pos"])
			if st.is_empty():
				continue
			var sp: Vector2 = st["pos"]
			var yaw: float = st["yaw"]
			var fwd := Vector2(sin(yaw), cos(yaw))
			await _shot(town, sp + fwd * 14.0 + Vector2(fwd.y, -fwd.x) * 5.0, sp, "r_" + ident, 3.0)
	get_tree().quit(0)


## Build the region sites within BUILD metres of p right now (build_all_now() builds the whole world: gigabytes).
func _build_near(p: Vector2) -> void:
	var rd = main.region
	for site in WorldGen.sites:
		if (site["pos"] as Vector2).distance_to(p) < rd.BUILD and not rd._built.has(site["id"]) and rd._in_season(site):
			rd._built[site["id"]] = rd._build(site)
	while not rd._queue.is_empty():
		var item: Array = rd._queue.pop_front()
		if not is_instance_valid(item[0]):
			continue
		if item[2] == "part":
			rd._build_part(item[0], item[1], item[1]["parts"][item[3]])
		else:
			rd._build_light(item[0], item[1]["lights"][item[3]])


## A camera spot on a street within ~dist metres of `target` (streets are clear of buildings): the street point nearest the
## target, shifted along the street to the side that stays inside a street.
func _street_view(plan: Dictionary, target: Vector2, dist: float) -> Vector2:
	var best_q := target
	var best_dir := Vector2.RIGHT
	var bd := INF
	for st: Dictionary in plan["streets"]:
		var q := Geometry2D.get_closest_point_to_segment(target, st["a"], st["b"])
		var d := q.distance_to(target)
		if d < bd:
			bd = d
			best_q = q
			best_dir = ((st["b"] as Vector2) - (st["a"] as Vector2)).normalized()
	var pick := best_q
	var pick_score := -INF
	for sg: float in [1.0, -1.0]:
		for k: float in [1.0, 0.7, 0.45]:
			var c := best_q + best_dir * sg * dist * k
			var inside := CityPlanner.street_distance(plan, c) < 0.5
			var score := (100.0 if inside else 0.0) + c.distance_to(target) * 0.1 + k * 10.0
			if score > pick_score:
				pick_score = score
				pick = c
	return pick


func _nearest_site(ident: String, near: Vector2, min_dist := 0.0) -> Dictionary:
	var best := {}
	var bd := INF
	for s in WorldGen.sites:
		if String(s.get("ident", "")) != ident:
			continue
		var d := (s["pos"] as Vector2).distance_to(near)
		if d >= min_dist and d < bd:
			bd = d
			best = s
	return best


func _shot(_town: Dictionary, from: Vector2, at: Vector2, name: String, height: float) -> void:
	main.call("_teleport", from, 0.0)
	main.region.focus = main.player.global_position
	_build_near(from)
	_build_near(at)
	for n in main.region.get_children():
		if n.has_method("refresh_now"):
			n.call("refresh_now")
	var gy := WorldGen.height(from.x, from.y) + height
	cam.global_position = Vector3(from.x, gy, from.y)
	cam.look_at(Vector3(at.x, WorldGen.height(at.x, at.y) + 1.8, at.y))
	cam.current = true
	main.terrain.focus = main.player.global_position
	main.terrain.build_all_now()
	for i in 40:
		await get_tree().process_frame
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [out_base, name]
	img.save_png(path)
	print("SHOT ", path)
