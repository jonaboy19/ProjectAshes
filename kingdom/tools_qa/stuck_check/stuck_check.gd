extends Node
## Village stuck detector for Rising Ashes.
##
## Boots the real game, then for each settlement walks (real player input path:
## Player.touch_move + camera yaw, full-speed run = the worst case) along
##   - every main street: centre line and both lanes / kerbs, both directions,
##   - every front-door footpath: street -> door and back,
##   - the plaza ring.
## A "stuck event" is: while trying to move, the player travelled < STUCK_DIST
## metres over STUCK_WINDOW seconds of simulated time. Each event logs the
## position, the blocked direction, and every solid collider within 2.5 m
## (owner, shape type, size, world centre) so the culprit can be named.
## After an event the walker hops 2.5 m along the route and carries on, so one
## run lists every blocked spot rather than just the first.
##
## Run: kingdom/tools_qa/stuck_check/run_stuck_check.sh  (headless is fine).

const MAIN := "res://scenes/main.tscn"
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const STUCK_DIST := 0.2
const STUCK_WINDOW := 2.0
const PLAYER_MASK := 1 | 2 | 4

var main: Node
var player: Player
var out_dir := ""
var _log: FileAccess
var events: Array = []
var routes_run := 0
var routes_ok := 0
var tscale := 3.0
var _town := ""
var _route := ""
var npc_events := 0
var _cur_plan := {}
var _focus := Vector2(1e9, 1e9)


func _ready() -> void:
	var args := _args()
	out_dir = String(args.get("out", "")).strip_edges()
	var base := ProjectSettings.globalize_path("res://").path_join("../docs/qa/stuck_check")
	out_dir = base.path_join(out_dir if out_dir != "" else "latest").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	tscale = float(args.get("scale", 3.0))
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run(args)


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


func log_line(text: String) -> void:
	print("STUCKQA ", text)
	if _log:
		_log.store_line(text)
		_log.flush()


func _p2() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y)


func _place(p: Vector2, yaw := 0.0) -> void:
	player.global_position = _ground(p)
	player.velocity = Vector3.ZERO
	player.set_camera(yaw, 0.0)
	player.reset_physics_interpolation()


func _wait_ready() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._loading.visible):
		await get_tree().process_frame
	player = main.player


## Walk the polyline `pts` from its first point. Returns true if it arrived with no stuck event.
func walk_route(label: String, pts: Array) -> bool:
	routes_run += 1
	_route = label
	var clean := true
	# Stream the ground in first: an unloaded chunk drops the player and Player snaps it home.
	if (pts[0] as Vector2).distance_to(_focus) > 40.0:
		_focus = pts[0]
		main.terrain.focus = _ground(_focus)
		main.terrain.build_all_now()
	_place(pts[0], 0.0)
	for _i in 6:
		await get_tree().physics_frame
	# The very first placement can be overridden (spawn / intro still settling): re-place until it holds.
	for _try in 20:
		if _p2().distance_to(pts[0]) < 1.0:
			break
		_place(pts[0], 0.0)
		for _i in 10:
			await get_tree().physics_frame
	var wi := 1
	var win_t := 0.0
	var win_pos := _p2()
	var total_t := 0.0
	var cap := 0.0
	for i in range(1, pts.size()):
		cap += (pts[i] as Vector2).distance_to(pts[i - 1])
	var max_t := cap / 2.0 + 10.0
	while wi < pts.size() and total_t < max_t:
		var to: Vector2 = (pts[wi] as Vector2) - _p2()
		if to.length() < 0.9:
			wi += 1
			win_t = 0.0
			win_pos = _p2()
			continue
		player.set_camera(atan2(-to.x, -to.y), 0.0)
		player.touch_move = Vector2(0, -1)
		await get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		win_t += dt
		total_t += dt
		if win_t >= STUCK_WINDOW:
			if _p2().distance_to(win_pos) < STUCK_DIST:
				clean = false
				_report(to.normalized())
				# hop 2.5 m along the route past the blocker and carry on
				_place(_p2() + to.normalized() * 2.5, 0.0)
				for _i in 4:
					await get_tree().physics_frame
			win_t = 0.0
			win_pos = _p2()
	player.touch_move = Vector2.ZERO
	if clean:
		routes_ok += 1
	return clean


func _report(dir: Vector2) -> void:
	var p := player.global_position
	var ev := {"town": _town, "route": _route, "pos": [snappedf(p.x, 0.01), snappedf(p.z, 0.01)],
			"dir": [snappedf(dir.x, 0.01), snappedf(dir.y, 0.01)], "colliders": []}
	log_line("STUCK %s / %s at (%.2f, %.2f) heading (%.2f, %.2f)" % [_town, _route, p.x, p.z, dir.x, dir.y])
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.5
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
	q.collision_mask = PLAYER_MASK
	q.exclude = [player.get_rid()]
	var seen := {}
	for hit in space.intersect_shape(q, 48):
		var col: Object = hit["collider"]
		var key := "%s:%s" % [hit["rid"], hit["shape"]]
		if seen.has(key):
			continue
		seen[key] = true
		var owner_name := "?"
		var desc := ""
		if col is CollisionObject3D:
			var co := col as CollisionObject3D
			owner_name = "%s (parent %s, layer %d)" % [co.name, co.get_parent().name if co.get_parent() else "", co.collision_layer]
			var sid := co.shape_find_owner(int(hit["shape"]))
			if sid >= 0:
				var cs := co.shape_owner_get_owner(sid) as CollisionShape3D
				if cs and cs.shape is BoxShape3D:
					var b := cs.shape as BoxShape3D
					var c := cs.global_position
					desc = "box %.2fx%.2fx%.2f at (%.2f, %.2f, %.2f) yaw %.0f" % [b.size.x, b.size.y, b.size.z, c.x, c.y, c.z, rad_to_deg(cs.global_rotation.y)]
				elif cs and cs.shape:
					desc = "%s at %s" % [cs.shape.get_class(), cs.global_position]
		var line := "    %s  %s" % [owner_name, desc]
		log_line(line)
		(ev["colliders"] as Array).append(line.strip_edges())
		if col is CharacterBody3D and (col as Node3D).global_position.distance_to(p) < 1.6:
			ev["npc"] = true
	# Lateral clearance across the heading (chest and knee height), how wide the gap really is.
	var side := Vector3(-dir.y, 0.0, dir.x)
	var widths: Array = []
	for h in [0.4, 1.2]:
		var o := p + Vector3(0, h, 0)
		var l := _ray_len(space, o, side, 3.0)
		var r := _ray_len(space, o, -side, 3.0)
		widths.append("h%.1f: %.2f+%.2f=%.2f m" % [h, l, r, l + r])
	var ahead := _ray_len(space, p + Vector3(0, 0.6, 0), Vector3(dir.x, 0, dir.y), 3.0)
	ev["ahead_m"] = snappedf(ahead, 0.01)
	ev["lateral"] = widths
	log_line("    lateral clearance %s; obstacle ahead at %.2f m" % [", ".join(widths), ahead])
	# Which street is the player on (distance from its axis vs its half width)?
	var plan: Dictionary = _cur_plan
	var best := 1e9
	var bs := {}
	for st: Dictionary in plan.get("streets", []):
		var cp := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), st["a"], st["b"])
		var dd := Vector2(p.x, p.z).distance_to(cp)
		if dd < best:
			best = dd
			bs = st
	if not bs.is_empty():
		var msg := "nearest street axis %.2f m away (street width %.1f, half %.2f)" % [best, bs["w"], float(bs["w"]) * 0.5]
		ev["street"] = msg
		log_line("    " + msg)
	events.append(ev)


func _ray_len(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, maxd: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * maxd, PLAYER_MASK, [player.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return maxd
	if absf((hit["normal"] as Vector3).y) > 0.6:
		return maxd
	return from.distance_to(hit["position"])


func _lot_at_door(plan: Dictionary, door: Vector2) -> Dictionary:
	for lot: Dictionary in plan["lots"]:
		if BuildingProfiles.door_point(lot).distance_to(door) < 0.05:
			return lot
	return {}


## Static gap audit: horizontal distance between the wall footprints of every pair of lots
## (the boxes BuildingProfiles actually collides with). Gaps the capsule (0.7 m wide) can
## enter but that are narrower than MIN_GAP are wedge traps and are logged.
func _footprint_poly(lot: Dictionary) -> PackedVector2Array:
	var asset := String(lot["asset"])
	var size: Vector3 = main.settlements._footprint(asset)   # what the builder really collides with
	var wall := BuildingProfiles.HOUSE_WALL if BuildingProfiles.is_house(asset) else BuildingProfiles.HERO_WALL
	var hw := size.x * wall
	var hd := size.z * wall
	var yaw: float = lot["yaw"]
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var c: Vector2 = lot["pos"]
	return PackedVector2Array([c - side * hw - fwd * hd, c + side * hw - fwd * hd, c + side * hw + fwd * hd, c - side * hw + fwd * hd])


func gap_audit(plan: Dictionary) -> void:
	var lots: Array = plan["lots"]
	var polys: Array = []
	for lot: Dictionary in lots:
		polys.append(_footprint_poly(lot))
	var narrow := 0
	var sealed := 0
	var seals: Array = []      # GapSeal filler bodies the builder added (world XZ centres)
	var root: Node = main.settlements.get_node_or_null(_town)
	if root:
		for ch in root.get_children():
			if "GapSeal" in String(ch.name):
				seals.append(Vector2((ch as Node3D).global_position.x, (ch as Node3D).global_position.z))
	for i in lots.size():
		for j in range(i + 1, lots.size()):
			if (lots[i]["pos"] as Vector2).distance_to(lots[j]["pos"]) > 30.0:
				continue
			var cl: Array = main.settlements.get_script()._poly_closest(polys[i], polys[j])
			var g: float = cl[0]
			if g > 0.0 and g < 1.4:
				var mid: Vector2 = ((cl[1] as Vector2) + (cl[2] as Vector2)) * 0.5
				var is_sealed := false
				for sc: Vector2 in seals:
					if sc.distance_to(mid) < 8.0:
						is_sealed = true
				if is_sealed:
					sealed += 1
					continue
				narrow += 1
				var nd := 1e9
				for sc2: Vector2 in seals:
					nd = minf(nd, sc2.distance_to(mid))
				log_line("  [%d seals, nearest %.1f m from gap]" % [seals.size(), nd])
				log_line("GAP %s: %.2f m between %s at %s and %s at %s" % [_town, g, lots[i]["asset"], lots[i]["pos"], lots[j]["asset"], lots[j]["pos"]])
			elif g == 0.0 and false:
				log_line("OVERLAP %s: %s at %s and %s at %s" % [_town, lots[i]["asset"], lots[i]["pos"], lots[j]["asset"], lots[j]["pos"]])
	log_line("gap audit %s: %d open narrow gaps (<1.4 m) between lot colliders, %d closed by GapSeal fillers" % [_town, narrow, sealed])


func _lane(a: Vector2, b: Vector2, off: float) -> Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * off
	return [a + n, b + n]


func _run(args: Dictionary) -> void:
	await _wait_ready()
	for _i in 120:
		await get_tree().process_frame
	Engine.time_scale = tscale
	Engine.max_physics_steps_per_frame = int(ceil(tscale)) * 2
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	player.set_view(Player.View.THIRD)
	var only: PackedStringArray = String(args.get("towns", "Ashford,Kingsreach")).split(",")
	var t0 := Time.get_ticks_msec()
	for s: Dictionary in WorldGen.settlements:
		if not (String(s["name"]) in only) and only[0] != "all":
			continue
		_town = String(s["name"])
		var plan: Dictionary = s["plan"]
		_cur_plan = plan
		var c: Vector2 = s["pos"]
		main._teleport(c, 0.0)
		for _i in 30:
			await get_tree().physics_frame
		log_line("=== %s (%s) at %s, %d lots, %d paths ===" % [_town, s["kind"], c, plan["lots"].size(), plan["paths"].size()])
		gap_audit(plan)
		if args.has("gaps-only"):
			continue
		var si := 0
		for st: Dictionary in plan["streets"]:
			si += 1
			if float(st["w"]) < 7.5:
				continue
			var a: Vector2 = st["a"]
			var b: Vector2 = st["b"]
			if plan["walls"]:   # stop inside the gate: the lanes outside are open country
				b = c + (b - c).normalized() * (float(plan["wall_radius"]) - 3.0)
			var half := float(st["w"]) * 0.5
			for off: float in [0.0, half - 1.2, -(half - 1.2)]:
				var ln := _lane(a, b, off)
				await walk_route("street%d lane %+.1f out" % [si, off], ln)
				await walk_route("street%d lane %+.1f back" % [si, off], [ln[1], ln[0]])
		var pi := 0
		for pth: Dictionary in plan["paths"]:
			pi += 1
			# Approach the way a player does: from the street to a point 3 m straight out
			# from the door, then in through the door threshold.
			var lot := _lot_at_door(plan, pth["a"])
			var nm := String(lot.get("asset", "?"))
			var pre: Vector2 = pth["a"]
			if not lot.is_empty():
				var yaw: float = lot["yaw"]
				pre = (pth["a"] as Vector2) + Vector2(sin(yaw), cos(yaw)) * 3.0
			await walk_route("door path %d (%s) in" % [pi, nm], [pth["b"], pre, pth["a"]])
			await walk_route("door path %d (%s) out" % [pi, nm], [pth["a"], pre, pth["b"]])
		log_line("=== %s done: %d routes, %d clean, %d stuck events so far ===" % [_town, routes_run, routes_ok, events.size()])
	var npc := 0
	for e in events:
		if e.get("npc", false):
			npc += 1
	log_line("SUMMARY routes=%d clean=%d stuck_events=%d (of which villager-blocked %d, real %d) wall_time=%.0fs" % [routes_run, routes_ok, events.size(), npc, events.size() - npc, (Time.get_ticks_msec() - t0) / 1000.0])
	var jf := FileAccess.open(out_dir.path_join("stuck.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify({"routes": routes_run, "clean": routes_ok, "events": events}, "  "))
	jf.close()
	get_tree().quit(0)
