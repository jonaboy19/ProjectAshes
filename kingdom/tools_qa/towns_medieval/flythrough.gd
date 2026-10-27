extends Node
## Towns medieval pass: owner fly-through videos with Godot's Movie Maker (best tool first: --write-movie records every frame at
## --fixed-fps, so a slow machine still gives a smooth 30 fps video). Windowed, HUD and player hidden, scripted camera.
##   godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie <out.avi> -- --adult --quality=high
##       --qa=res://tools_qa/towns_medieval/flythrough.gd --town=Ashford --path=street_alley [--hour=21.5] [--secs=30]
## Paths: street_alley (gate road -> square -> into the most built-up alley), market (gate market road -> square -> rise to an
## aerial), lane_alley (side street -> alley). Prints "FLY_START <frame>" when the camera starts (trim the boot frames with ffmpeg).

var main: Node
var cam: Camera3D


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var town_name := String(args.get("town", "Ashford"))
	var kind := String(args.get("path", "street_alley"))
	var hour := float(args.get("hour", "15.0"))
	var secs := float(args.get("secs", "30"))
	main.hud.visible = false
	main.player.visible = false
	var town: Dictionary = {}
	for s in WorldGen.settlements:
		if s["name"] == town_name:
			town = s
	if town.is_empty():
		get_tree().quit(1)
		return
	var plan: Dictionary = town["plan"]
	var c: Vector2 = town["pos"]
	var g0 := float(plan["gates"][0])
	var dir := _main_dir(plan, g0)
	# build the town around its centre (same as town_sheet.gd)
	var park := c + dir * (float(plan["wall_radius"]) + 90.0)
	main.call("_teleport", park, atan2(-dir.x, -dir.y))
	await get_tree().create_timer(0.4).timeout
	var centre3 := Vector3(c.x, WorldGen.height(c.x, c.y), c.y)
	main.settlements.focus = centre3
	for i in 5:
		main.settlements.update_now()
	main.settlements.finish_prop_jobs()
	main.population.focus = centre3
	main.population.refresh()
	main.terrain.focus = centre3
	main.terrain.build_all_now()
	WorldSim.time_of_day = hour
	if OS.has_environment("ASHES_TPOSE_WATCH"):      # QA: T-pose detector (NPC lane)
		get_tree().root.add_child(preload("res://tools_qa/living_world/tpose_watch.gd").new())
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.far = 1200.0
	main.world.add_child(cam)
	cam.current = true
	reach_graph = preload("res://scripts/population/street_graph.gd").for_settlement(int(town["id"]))
	reach_from = c + dir * (float(plan["plaza_r"]) + 6.0)
	if args.has("mapout"):
		_map(plan, c, String(args["mapout"]), preload("res://scripts/population/street_graph.gd").for_settlement(int(town["id"])))
	if args.has("reach"):      # plaza/street reachability matrix (slow on big towns)
		var gg: RefCounted = preload("res://scripts/population/street_graph.gd").for_settlement(int(town["id"]))
		var probe := [c, c + dir * (float(plan["plaza_r"]) + 6.0), c + dir * float(plan["plaza_r"]) * 0.5]
		for si in (plan["streets"] as Array).size():
			var st: Dictionary = plan["streets"][si]
			probe.append((st["a"] as Vector2).lerp(st["b"], 0.5))
		for i in probe.size():
			var out := ""
			for j in probe.size():
				gg.route(probe[i], probe[j])
				out += "x" if bool(gg.get("last_route_partial")) else "."
			print("FLY_REACH %2d %s %s" % [i, out, probe[i]])
		print("FLY_PLAZA r=%s kind=%s walls=%s" % [plan["plaza_r"], plan.get("kind", ""), plan.get("walls", false)])
	var keys := _keys(town, kind)          # [[pos3, look3], ...]
	# warm the start point: stream terrain and let the town finish
	cam.global_position = keys[0][0]
	cam.look_at(keys[0][1])
	main.terrain.focus = keys[0][0]
	main.terrain.build_all_now()
	for i in 90:
		WorldSim.time_of_day = hour
		await get_tree().process_frame
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false     # footage of the world only: no work dialogs, prompts or tags (UI is judged separately)
	for ch in main.get_children():
		if ch is Control and not (ch is SubViewportContainer):
			(ch as Control).visible = false
	print("FLY_START ", Engine.get_frames_drawn())
	# walk the street graph between keyframes (the NPC router): the camera never cuts through a building
	var g: RefCounted = preload("res://scripts/population/street_graph.gd").for_settlement(int(town["id"]))
	var pts: Array[Vector3] = [keys[0][0]]
	for ki in range(1, keys.size()):
		var a2 := Vector2(keys[ki - 1][0].x, keys[ki - 1][0].z)
		var b2 := Vector2(keys[ki][0].x, keys[ki][0].z)
		var hgt: float = keys[ki][0].y - WorldGen.height(b2.x, b2.y)
		var route: PackedVector2Array = g.route(a2, b2) if g != null and hgt < 4.0 else PackedVector2Array([b2])
		for q: Vector2 in route:
			pts.append(Vector3(q.x, WorldGen.height(q.x, q.y) + clampf(hgt, 1.7, 40.0), q.y))
	# report route points that fall inside a building footprint (the review route must stay on streets)
	print("FLY_ROUTE partial=%s points=%d" % [g.get("last_route_partial") if g != null else "nograph", pts.size()])
	for q3: Vector3 in pts:
		for lot: Dictionary in plan["lots"]:
			if Geometry2D.is_point_in_polygon(Vector2(q3.x, q3.z), CityPlanner._lot_poly(lot["pos"], lot["yaw"], String(lot["asset"]))):
				print("FLY_IN_LOT %s at %s" % [lot["asset"], Vector2(q3.x, q3.z)])
	var pc := Curve3D.new()
	for q3: Vector3 in pts:
		if pc.point_count == 0 or pc.get_point_position(pc.point_count - 1).distance_to(q3) > 0.8:
			pc.add_point(q3)
	_smooth(pc)
	var lc := Curve3D.new()
	for k: Array in keys:
		lc.add_point(k[1])
	_smooth(lc)
	var frames := int(secs * 30.0)
	for f in frames:
		var t := float(f) / float(frames - 1)
		var e := t * t * (3.0 - 2.0 * t)          # ease in / out
		var p := pc.sample_baked(e * pc.get_baked_length(), true)
		# look 7 m ahead along the walk (blended toward the keyframe target near the end, e.g. the aerial rise)
		var ahead := pc.sample_baked(minf(e * pc.get_baked_length() + 7.0, pc.get_baked_length()), true)
		var rising := ahead.y - p.y > 0.6        # the closing crane shot: look at the keyframe target, not up the path
		var l := ahead + Vector3(0, -0.1, 0) if ahead.distance_to(p) > 1.0 and not rising else lc.sample_baked(e * lc.get_baked_length(), true)
		var fwd2 := Vector2(ahead.x - p.x, ahead.z - p.z).normalized() if ahead.distance_to(p) > 0.2 else Vector2(0, 1)
		_off = _off.lerp(_clear_offset(p, fwd2), 0.12)
		p += Vector3(_off.x, 0.0, _off.y)
		l += Vector3(_off.x, 0.0, _off.y)
		cam.global_position = p
		_hide_close_npcs(p)
		if f % 15 == 0 and OS.get_cmdline_user_args().has("--whatshere"):
			var ids := RenderingServer.instances_cull_aabb(AABB(p - Vector3(0.4, 0.4, 0.4), Vector3(0.8, 0.8, 0.8)), cam.get_world_3d().scenario)
			var names: Array[String] = []
			for id in ids:
				var o := instance_from_id(id)
				if o is Node and not (o is Camera3D) and not ((o as Node).get_class() in ["OmniLight3D", "SpotLight3D", "DirectionalLight3D", "Decal", "GPUParticles3D", "ReflectionProbe"]):
					names.append("%s<%s>" % [(o as Node).get_path(), (o as Node).get_class()])
			if not names.is_empty():
				print("FLY_HERE f=%d p=%s free=%s %s" % [f, p, _free(p), names.slice(0, 4)])
		if p.distance_to(l) > 0.1:
			cam.look_at(l)
		# the player stays parked (near a stall he opened a work dialog); the streamers follow the camera through their focus
		main.terrain.focus = p
		main.settlements.focus = p
		main.population.focus = p
		WorldSim.time_of_day = hour
		_hide_ui()      # dialogs and prompts that open during the walk
		await get_tree().process_frame
	print("FLY_END ", Engine.get_frames_drawn())
	# which buildings the shot ends among (gate notes name the asset, not "the houses at the edge")
	for lot: Dictionary in plan["lots"]:
		var lp: Vector2 = lot["pos"]
		if lp.distance_to(Vector2(cam.global_position.x, cam.global_position.z)) < 22.0:
			print("FLY_LOT %s at %s" % [lot.get("asset", ""), lp])
	get_tree().quit(0)


## Review-camera clearance (coordinator 2026-10-27: no brushing walls/corners, never a frame inside a building): like a
## SpringArm3D margin, a 0.5 m sphere at the eye is tested against the world's static collision; when it touches, the
## sideways offset (perpendicular to the walk) that clears it is used instead, eased so the camera slides, never jumps.
var _off := Vector2.ZERO
const CAM_MARGIN := 0.65     # clears the Ashford Ring stones; larger pushed the camera sideways into a collider-less wall


func _clear_offset(p: Vector3, fwd: Vector2) -> Vector2:
	var side := Vector2(-fwd.y, fwd.x)
	# wide berth first (props like the Ashford Ring menhirs filled a third of the frame at 0.65 m), the tight margin
	# only where a lane is too narrow for it
	for margin: float in [1.2, CAM_MARGIN]:
		for d: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
			var o := side * d
			if _free(p + Vector3(o.x, 0.0, o.y), margin):
				return o
	return _off


func _free(at: Vector3, margin := CAM_MARGIN) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = margin
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collide_with_areas = false
	for hit: Dictionary in space.intersect_shape(q, 8):
		var col: Object = hit.get("collider")
		if col is Node and ((col as Node).is_in_group("villager") or (col as Node).is_in_group("player") or (col as Node).is_in_group("vehicle")):
			continue
		if col is CharacterBody3D or col is RigidBody3D:
			continue
		return false
	return true


## Villager bodies are not obstacles for the review camera (they walk into it): any within 1.6 m of the eye is hidden for
## that frame, so the shot never goes through a head or a torso.
var _hidden_npcs: Array[Node3D] = []


func _hide_close_npcs(p: Vector3) -> void:
	for n in _hidden_npcs:
		if is_instance_valid(n):
			n.visible = true
	_hidden_npcs.clear()
	for n in get_tree().get_nodes_in_group("villager"):
		var n3 := n as Node3D
		if n3 != null and n3.visible and Vector2(n3.global_position.x - p.x, n3.global_position.z - p.z).length() < 1.6:
			n3.visible = false
			_hidden_npcs.append(n3)


## The main street's direction (plaza -> gate). In the real world gates[0] points at the real road, which need not be
## street 0 (the old world built street 0 on gates[0]): the slice route walked over open grass and through houses.
func _main_dir(plan: Dictionary, g0: float) -> Vector2:
	var streets: Array = plan.get("streets", [])
	if not streets.is_empty():
		var d := ((streets[0]["b"] as Vector2) - (streets[0]["a"] as Vector2))
		if d.length() > 1.0:
			return d.normalized()
	return Vector2(cos(g0), sin(g0))


## Debug: plan map PNG (120 m around the centre, 4 px/m): lots grey, streets blue, frontage lots orange, main street red.
func _map(plan: Dictionary, c: Vector2, path: String, gg: RefCounted = null) -> void:
	var n := 960
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.15, 0.25, 0.12))
	var to_px := func(v: Vector2) -> Vector2i: return Vector2i(int((v.x - c.x) * 4.0 + n * 0.5), int((v.y - c.y) * 4.0 + n * 0.5))
	var si := 0
	for st: Dictionary in plan["streets"]:
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var steps := int(a.distance_to(b) * 4.0) + 1
		var hw := int(float(st["w"]) * 2.0)
		for k in steps:
			var q: Vector2i = to_px.call(a.lerp(b, float(k) / steps))
			for dx in range(-hw, hw + 1, 2):
				for dy in range(-hw, hw + 1, 2):
					var x := q.x + dx
					var y := q.y + dy
					if x >= 0 and y >= 0 and x < n and y < n:
						img.set_pixel(x, y, Color(0.8, 0.2, 0.2) if si == 0 else Color(0.3, 0.45, 0.8))
		si += 1
	var li := 0
	for lot: Dictionary in plan["lots"]:
		var poly := CityPlanner._lot_poly(lot["pos"], lot["yaw"], String(lot["asset"]))
		var bb := Rect2(poly[0], Vector2.ZERO)
		for v: Vector2 in poly:
			bb = bb.expand(v)
		for x in range(int(bb.position.x), int(bb.end.x) + 1):
			for y in range(int(bb.position.y), int(bb.end.y) + 1):
				for fx in 4:
					for fy in 4:
						var w := Vector2(x + fx * 0.25, y + fy * 0.25)
						if Geometry2D.is_point_in_polygon(w, poly):
							var q: Vector2i = to_px.call(w)
							if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
								img.set_pixel(q.x, q.y, Color(0.95, 0.6, 0.2) if lot.has("tier") else Color(0.7, 0.7, 0.7))
		li += 1
	if gg != null:      # the street graph's own obstacle boxes (purple outline) and its nodes (white)
		var bc: PackedVector2Array = gg.get("_box_c")
		var bh: PackedVector2Array = gg.get("_box_h")
		var bax: PackedVector2Array = gg.get("_box_ax")
		for k in bc.size():
			var ax: Vector2 = bax[k]
			var ay := Vector2(-ax.y, ax.x)
			for t in 80:
				var u := float(t) / 20.0
				var e: Vector2
				match int(u):
					0: e = bc[k] + ax * bh[k].x * (u * 2.0 - 1.0) - ay * bh[k].y
					1: e = bc[k] + ax * bh[k].x + ay * bh[k].y * ((u - 1.0) * 2.0 - 1.0)
					2: e = bc[k] - ax * bh[k].x * ((u - 2.0) * 2.0 - 1.0) + ay * bh[k].y
					_: e = bc[k] - ax * bh[k].x - ay * bh[k].y * ((u - 3.0) * 2.0 - 1.0)
				var q: Vector2i = to_px.call(e)
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
					img.set_pixel(q.x, q.y, Color(0.8, 0.2, 0.9))
		gg.call("_ensure_graph")
		var nodes: PackedVector2Array = gg.get("_nodes")
		var edges: PackedInt32Array = gg.get("_edges")
		for ei in range(0, edges.size(), 2):
			var ea: Vector2 = nodes[edges[ei]]
			var eb: Vector2 = nodes[edges[ei + 1]]
			var ns := int(ea.distance_to(eb) * 4.0) + 1
			for t in ns:
				var q: Vector2i = to_px.call(ea.lerp(eb, float(t) / ns))
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
					img.set_pixel(q.x, q.y, Color(1, 1, 0.6))
		for v: Vector2 in nodes:
			var q: Vector2i = to_px.call(v)
			for dx in 3:
				for dy in 3:
					if q.x + dx < n and q.y + dy < n and q.x >= 0 and q.y >= 0:
						img.set_pixel(q.x + dx, q.y + dy, Color.WHITE)
	img.save_png(path)
	print("FLY_MAP ", path)


func _smooth(cv: Curve3D) -> void:
	for i in cv.point_count:
		var prev := cv.get_point_position(maxi(i - 1, 0))
		var nxt := cv.get_point_position(mini(i + 1, cv.point_count - 1))
		var tan := (nxt - prev) * 0.25
		cv.set_point_in(i, -tan)
		cv.set_point_out(i, tan)


func _eye(p: Vector2, h := 1.7) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y) + h, p.y)


func _keys(town: Dictionary, kind: String) -> Array:
	var plan: Dictionary = town["plan"]
	var c: Vector2 = town["pos"]
	var g0 := float(plan["gates"][0])
	var dir := _main_dir(plan, g0)
	var pr := float(plan["plaza_r"])
	var streets: Array = plan["streets"]
	var first_alley := int(plan.get("alleys_from", streets.size()))
	var alley := _best_alley(plan, first_alley)
	var keys: Array = []
	match kind:
		"market":
			var gate := c + dir * (float(plan["wall_radius"]) * 0.8)
			var edge := c + dir * (pr + 8.0)
			keys.append([_eye(gate, 2.2), _eye(c, 3.0)])
			keys.append([_eye(gate.lerp(edge, 0.5), 2.2), _eye(c, 3.0)])
			keys.append([_eye(edge, 2.4), _eye(c, 3.0)])
			keys.append([_eye(edge, 32.0), _eye(c, 0.0)])     # rise straight up at the plaza edge (a castle's centre is the keep)
		"slice":
			# benchmark slice route (BENCHMARK_SLICE.md): up the main street to the square, then into the most built-up side street
			var start2 := c + dir * (pr + 34.0)
			keys.append([_eye(start2), _eye(c, 2.0)])
			keys.append([_eye(c + dir * (pr + 6.0)), _eye(c, 2.0)])
			var lane2 := _best_lane(plan, first_alley)
			if not lane2.is_empty():
				var la: Vector2 = lane2["a"]
				var lb: Vector2 = lane2["b"]
				if la.distance_to(c) > lb.distance_to(c):
					var tmp := la
					la = lb
					lb = tmp
				keys.append([_eye(la), _eye(lb)])
				keys.append([_eye(la.lerp(lb, 0.85)), _eye(lb + (lb - la).normalized() * 10.0)])
		"lane_alley":
			var lane := _best_lane(plan, first_alley)
			if not lane.is_empty():
				keys.append([_eye(lane["a"]), _eye(lane["b"])])
				keys.append([_eye((lane["a"] as Vector2).lerp(lane["b"], 0.6)), _eye(lane["b"])])
			if not alley.is_empty():
				keys.append([_eye((alley["a"] as Vector2) - ((alley["b"] - alley["a"]) as Vector2).normalized() * 3.0), _eye(alley["b"])])
				keys.append([_eye((alley["a"] as Vector2).lerp(alley["b"], 0.7)), _eye(alley["b"])])
		_:
			var start := c + dir * (pr + 34.0)
			keys.append([_eye(start), _eye(c, 2.0)])
			keys.append([_eye(c + dir * (pr + 8.0)), _eye(c, 2.0)])
			if not alley.is_empty():
				var am: Vector2 = alley["a"]
				keys.append([_eye(am - ((alley["b"] - alley["a"]) as Vector2).normalized() * 4.0), _eye(alley["b"])])
				keys.append([_eye(am.lerp(alley["b"], 0.75)), _eye(alley["b"])])
			else:
				keys.append([_eye(c - dir * pr * 0.5), _eye(c - dir * (pr + 20.0))])
	if keys.size() < 2:
		keys = [[_eye(c + dir * 40.0, 20.0), _eye(c)], [_eye(c - dir * 40.0, 20.0), _eye(c)]]
	return keys


## The alley with the most new houses along it (same rule as town_sheet.gd's owner shots).
func _best_alley(plan: Dictionary, first: int) -> Dictionary:
	var streets: Array = plan["streets"]
	var best: Dictionary = {}
	var bs := -1.0
	for i in range(first, streets.size()):
		if not bool(streets[i].get("alley", false)):
			continue
		var n := 0
		for lot: Dictionary in plan["lots"]:
			var lp: Vector2 = lot["pos"]
			if bool(lot.get("infill", false)) and lp.distance_to(Geometry2D.get_closest_point_to_segment(lp, streets[i]["a"], streets[i]["b"])) < 6.5:
				n += 1
		var sc := float(n) * 100.0 + (streets[i]["a"] as Vector2).distance_to(streets[i]["b"])
		if sc > bs:
			bs = sc
			best = streets[i]
	return best


var reach_graph: RefCounted = null     # StreetGraph: when set, lanes the plaza cannot route to are skipped (and logged)
var reach_from := Vector2.INF


func _best_lane(plan: Dictionary, first: int) -> Dictionary:
	var streets: Array = plan["streets"]
	var best: Dictionary = {}
	var bs := -1
	for i in first:
		if float(streets[i]["w"]) >= 8.0 or bool(streets[i].get("link", false)):
			continue
		if reach_graph != null and reach_from != Vector2.INF:
			var mid: Vector2 = (streets[i]["a"] as Vector2).lerp(streets[i]["b"], 0.5)
			reach_graph.route(reach_from, mid)
			if bool(reach_graph.get("last_route_partial")):
				print("FLY_ISLAND street %d %s-%s unreachable from the plaza" % [i, streets[i]["a"], streets[i]["b"]])
				continue
		var n := 0
		for lot: Dictionary in plan["lots"]:
			var lp: Vector2 = lot["pos"]
			if lp.distance_to(Geometry2D.get_closest_point_to_segment(lp, streets[i]["a"], streets[i]["b"])) < 9.0:
				n += 1
		if n > bs:
			bs = n
			best = streets[i]
	return best


func _hide_ui() -> void:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for ch in main.get_children():
		if ch is Control and not (ch is SubViewportContainer):
			(ch as Control).visible = false
