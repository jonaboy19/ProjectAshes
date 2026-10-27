extends Node
## Movie Maker QA tour (owner rule: check visual changes with a recording). Deterministic: fixed timestep, scripted
## player walks and a free camera, HUD hidden. One run covers the places the NPC / crowd / life-clip lanes show up:
##   start (Ashford gate road, morning) -> Ashford plaza ring -> Ashford back lanes -> Ashford at night ->
##   Kingsreach gate -> market crowd -> a farm work spot (orbit) -> the tavern (sit / drink / bard spots, orbit) ->
##   combat (a bandit vs a guard, watched) -> fly-over of Kingsreach.
## Record (windowed, never headless):
##   godot --path kingdom --resolution 1280x720 --write-movie C:/tmp/tour.avi --fixed-fps 30 -- --adult \
##         --qa=res://tools_qa/video/qa_tour.gd [--only=market,tavern] [--pop-log]
## Prints TOUR <t> <segment> lines (segment starts) so frames map back to places; quits at the end.
## Analyse with tools/qa/video/analyse_tour.sh (contact sheets 1 frame / 0.5 s + scene-diff spikes).

const NpcWorld := preload("res://scripts/population/npc_world.gd")
const WALK := 2.4            # m/s, an unhurried walk: crowd LOD bands are crossed slowly
var main: Node
var segs: Array = []          # [{name, dur, setup: Callable, tick: Callable}]
var si := -1
var st := 0.0                 # time in the current segment
var t := 0.0
var cam: Camera3D             # free camera (orbit / fly-over segments)
var only := PackedStringArray()
var _spawned: Array = []
var _a := Vector2.ZERO        # walk leg from
var _b := Vector2.ZERO        # walk leg to
var _c := Vector3.ZERO        # orbit centre


func run(m: Node) -> void:
	main = m
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--only="):
			only = PackedStringArray(a.substr(7).split(","))
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 1500.0
	main.world.add_child(cam)
	_build()
	_next()
	set_process(true)
	# safety: never record forever (Movie Maker keeps writing frames until quit)
	var total := 0.0
	for sg: Dictionary in segs:
		total += float(sg["dur"])
	get_tree().create_timer(total + 60.0, true, false, true).timeout.connect(func() -> void: get_tree().quit())


func _ash() -> Dictionary:
	return WorldGen.settlements[0]


func _cap() -> Dictionary:
	return WorldGen.settlements[1]


func _build() -> void:
	var ash := _ash()
	var c0: Vector2 = ash["pos"]
	var pr: float = float(ash["plan"]["plaza_r"])
	var g0: float = ash["plan"]["gates"][0] if not (ash["plan"]["gates"] as Array).is_empty() else 0.0
	var gd := Vector2(cos(g0), sin(g0))
	var cap := _cap()
	var cp: Vector2 = cap["pos"]
	var g1: float = cap["plan"]["gates"][0] if not (cap["plan"]["gates"] as Array).is_empty() else 0.0
	var gd1 := Vector2(cos(g1), sin(g1))
	var cpr: float = float(cap["plan"]["plaza_r"])
	_seg("start", 8.0, 9.0, func() -> void: _walk(c0 + gd * (float(ash["radius"]) + 10.0), c0 + gd * (pr + 6.0)))
	_seg("ashford_streets", 18.0, 10.0, func() -> void: _walk(c0 + gd.rotated(0.5) * (pr + 10.0), c0 + gd.rotated(2.6) * (pr + 10.0)))
	_seg("ashford_lanes", 12.0, 11.0, func() -> void: _walk(c0 + gd.rotated(-1.2) * (pr + 30.0), c0 + gd.rotated(-2.6) * (pr + 30.0)))
	_seg("ashford_night", 10.0, 22.5, func() -> void: _walk(c0 + gd.rotated(2.0) * (pr + 8.0), c0 + gd.rotated(3.4) * (pr + 8.0)))
	_seg("kingsreach_gate", 12.0, 12.0, func() -> void: _walk(cp + gd1 * (float(cap["radius"]) + 20.0), cp + gd1 * (cpr + 4.0)))
	_seg("kingsreach_market", 16.0, 12.5, func() -> void: _walk(cp + gd1.rotated(0.9) * (cpr + 5.0), cp + gd1.rotated(-0.9) * (cpr + 5.0)))
	_seg("farm_spot", 12.0, 9.0, func() -> void: _orbit_spot(["field_sow", "field_row", "field_harvest"], c0, 6.0, 2.2))
	_seg("tavern", 14.0, 20.0, func() -> void: _orbit_spot(["tavern_table", "bar_counter", "musician_spot", "bench"], c0, 5.0, 1.8))
	_seg("combat", 14.0, 15.0, func() -> void: _combat(c0 + gd * (float(ash["radius"]) + 40.0)))
	_seg("flyover", 12.0, 16.0, func() -> void: _fly(cp, float(cap["radius"])))


func _seg(name: String, dur: float, hour: float, setup: Callable) -> void:
	if not only.is_empty() and not only.has(name):
		return
	segs.append({"name": name, "dur": dur, "hour": hour, "setup": setup})


func _next() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	si += 1
	st = 0.0
	if si >= segs.size():
		print("TOUR_END t=%.1f" % t)
		get_tree().quit()
		return
	var s: Dictionary = segs[si]
	WorldSim.time_of_day = float(s["hour"])
	main.player.visible = true
	cam.current = false
	_mode = ""
	(s["setup"] as Callable).call()
	print("TOUR %.1f %s" % [t, s["name"]])


var _mode := ""


func _walk(a: Vector2, b: Vector2) -> void:
	_mode = "walk"
	_a = a
	_b = b
	var d := b - a
	main.call("_teleport", a, atan2(-d.x, -d.y))


func _orbit_spot(types: Array, near: Vector2, r: float, h: float) -> void:
	_mode = "orbit"
	var best := Vector3.INF
	var so: SmartObjects = NpcWorld.smart
	if so != null:
		var bd := INF
		for sp: Dictionary in so.spots:
			if types.has(String(sp["type"])):
				var o: Vector3 = (sp["xform"] as Transform3D).origin
				var d := Vector2(o.x, o.z).distance_to(near)
				if d < bd:
					bd = d
					best = o
	if best == Vector3.INF:
		best = Vector3(near.x, WorldGen.height(near.x, near.y), near.y)
	_c = best
	main.call("_teleport", Vector2(best.x + r * 0.7, best.z + r * 0.7), 0.0)     # the player is near so bodies spawn
	main.player.visible = false
	_orbit_r = r
	_orbit_h = h
	cam.current = true


var _orbit_r := 6.0
var _orbit_h := 2.0


func _combat(at: Vector2) -> void:
	_mode = "orbit"
	main.call("_teleport", at + Vector2(6, 6), 0.0)
	main.player.visible = false
	var g := Soldier.create(0, "Guard", "Knight", ["1H_Sword", "Round_Shield"])
	main.world.add_child(g)
	g.global_position = Vector3(at.x - 2.0, WorldGen.height(at.x - 2.0, at.y) + 0.3, at.y)
	var b := Soldier.create(1, "Bandit", "Bandit", ["1H_Sword", "Round_Shield"])
	main.world.add_child(b)
	b.global_position = Vector3(at.x + 2.0, WorldGen.height(at.x + 2.0, at.y) + 0.3, at.y)
	_spawned = [g, b]
	_c = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	_orbit_r = 7.0
	_orbit_h = 2.4
	cam.current = true


func _fly(centre: Vector2, radius: float) -> void:
	_mode = "fly"
	main.call("_teleport", centre, 0.0)
	main.player.visible = false
	_c = Vector3(centre.x, WorldGen.height(centre.x, centre.y), centre.y)
	_orbit_r = radius + 40.0
	_orbit_h = 70.0
	cam.current = true


func _process(delta: float) -> void:
	if si < 0 or si >= segs.size():
		return
	t += delta
	st += delta
	if main.hud:
		main.hud.visible = false
	var s: Dictionary = segs[si]
	match _mode:
		"walk":
			var len := maxf(_a.distance_to(_b), 0.1)
			var p := _a.lerp(_b, minf(st * WALK / len, 1.0))
			main.player.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.1, p.y)
			var d := _b - _a
			main.player.set_camera(atan2(-d.x, -d.y) + sin(st * 0.35) * 0.35, -0.1)
		"orbit", "fly":
			var ang := st * (0.35 if _mode == "orbit" else 0.22)
			var o := _c + Vector3(cos(ang) * _orbit_r, _orbit_h, sin(ang) * _orbit_r)
			cam.global_position = o
			cam.look_at(_c + Vector3(0, 1.0 if _mode == "orbit" else 0.0, 0), Vector3.UP)
	if st >= float(s["dur"]):
		_next()
