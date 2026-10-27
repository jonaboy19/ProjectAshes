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
	var dir := Vector2(cos(g0), sin(g0))
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
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.far = 1200.0
	main.world.add_child(cam)
	cam.current = true
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
		cam.global_position = p
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
	get_tree().quit(0)


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
	var dir := Vector2(cos(g0), sin(g0))
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


func _best_lane(plan: Dictionary, first: int) -> Dictionary:
	var streets: Array = plan["streets"]
	var best: Dictionary = {}
	var bs := -1
	for i in first:
		if float(streets[i]["w"]) >= 8.0 or bool(streets[i].get("link", false)):
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
