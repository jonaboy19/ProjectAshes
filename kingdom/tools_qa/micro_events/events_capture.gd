extends Node
## Thornfield over a day cycle: forces one street scene per time of day (with the town's circumstances faked
## where the scene needs them), stands the player where it can be seen and writes frames.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan \
##       res://tools_qa/micro_events/events_capture.tscn -- --out=/tmp/claude-0/shots/events [--only=a,b] [--town=Thornfield]
## Then tools_qa/micro_events/sheet.py tiles the frames. One run at a time (a full boot is about 4.5 GB).

const MAIN := "res://scenes/main.tscn"
const MicroEvents := preload("res://scripts/population/micro_events.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")

## name, hour, where to stand, scene id ("" = let the director run), mood override, seconds of the frames
const SHOTS := [
	["gates_opening", 5.9, "gate", "gates_opening", {}, [6.0, 16.0]],
	["delivery", 8.0, "plaza", "delivery_to_shops", {}, [8.0, 22.0]],
	["bread_queue", 7.6, "stall", "", {"scarcity": 0.9}, [10.0, 26.0]],
	["town_crier", 11.0, "plaza", "town_crier", {}, [8.0, 18.0]],
	["drills", 10.0, "drill", "training_drills", {"war": 1.0}, [8.0, 20.0]],
	["recruiters", 15.0, "plaza", "recruiters_calling", {"war": 1.0}, [8.0, 20.0]],
	["noble_carriage", 12.5, "plaza", "noble_carriage", {}, [8.0, 24.0]],
	["funeral", 10.5, "temple", "funeral_procession", {"mourning": 1.0}, [10.0, 30.0]],
	["festival", 15.0, "plaza", "festival_dancers", {"festival": "midsummer"}, [8.0, 20.0]],
	["performer", 14.0, "plaza", "street_performer", {}, [8.0, 20.0]],
	["thief", 16.0, "plaza", "thief_running", {}, [6.0, 12.0]],
	["broken_cart", 13.0, "plaza", "broken_cart", {}, [14.0, 28.0]],
	["children", 9.5, "plaza", "children_chasing", {}, [8.0, 18.0]],
	["market_closing", 18.7, "stall", "market_closing", {}, [8.0, 24.0]],
	["lamp_lighter", 18.9, "plaza", "lamp_lighter", {}, [10.0, 26.0]],
	["gates_closing", 21.2, "gate", "gates_closing", {}, [8.0, 30.0]],
	["drunk", 22.0, "inn", "drunk_ejected", {}, [6.0, 14.0]],
	["night_watch", 23.5, "plaza", "night_watch_rounds", {"curfew": true}, [10.0, 24.0]],
	["shift_change", 6.1, "gate", "guard_shift_change", {}, [8.0, 22.0]],
	["sermon", 9.0, "temple", "street_sermon", {}, [8.0, 20.0]],
]

var main: Node
var player: Player
var out_dir := "/tmp/claude-0/shots/events"
var town := "Thornfield"
var only: PackedStringArray = PackedStringArray()
var _pin := -1.0


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	out_dir = String(args.get("out", out_dir))
	town = String(args.get("town", town))
	if args.has("only"):
		only = String(args["only"]).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _process(_delta: float) -> void:
	# A software-rendered frame can take seconds (and the first teleport minutes): pin the clock so every shot
	# is taken at the hour it is labelled with.
	if _pin >= 0.0:
		WorldSim.time_of_day = _pin


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("SHOT ", path, " hour=", snapped(WorldSim.time_of_day, 0.01))


## Where to stand and what to face for a kind of place in settlement `s`: [position, look-at point].
func _stand(kind: String, s: Dictionary) -> Array:
	var c: Vector2 = s["pos"]
	var plan: Dictionary = s["plan"]
	var sid := int(s["id"])
	var graph := StreetGraph.for_settlement(sid) as StreetGraph
	var pr := float(plan.get("plaza_r", 14.0))
	match kind:
		"gate":
			var g := float(plan["gates"][0])
			var dir := Vector2(cos(g), sin(g))
			var gp := c + dir * (float(plan.get("wall_radius", 100.0)) - 3.5)
			return [gp - dir * 24.0, gp]
		"inn":
			if graph.inn_door != Vector2.INF:
				return [graph.inn_door + graph.inn_facing * 15.0, graph.inn_door]
		"temple":
			var pl := UtilityBrain.places(sid, graph)
			if pl["shrine"] != Vector2.INF:
				var face: Vector2 = -(pl["shrine_face"] as Vector2)
				return [(pl["shrine"] as Vector2) + face * 17.0, pl["shrine"]]
		"drill":
			var yard := Schedule.spot(s, Schedule.Phase.TRAIN, 0, 1)
			var to_c := (c - yard).normalized()
			return [yard + to_c * 17.0, yard]
		"stall":
			var places := NpcWorld.places_of(sid)
			var stalls: PackedVector2Array = places.get("stalls", PackedVector2Array())
			if not stalls.is_empty():
				var yaw: float = (places["stall_yaw"] as PackedFloat32Array)[0]
				var front := Vector2(sin(yaw), cos(yaw))
				return [stalls[0] + front * 17.0, stalls[0]]
	return [c + Vector2(0.0, pr + 12.0), c]


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null \
			and (not is_instance_valid(main.hud._loading) or not main.hud._loading.visible)):
		await get_tree().process_frame
	player = main.player
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	var s: Dictionary = {}
	for t: Dictionary in WorldGen.settlements:
		if t["name"] == town:
			s = t
	if s.is_empty():
		print("EVENTS no such town ", town)
		get_tree().quit(1)
		return
	Quality.npc_full = 16
	main.hud.visible = false
	MicroEvents.verbose = true
	await _wait(2.0)
	var first := true
	for shot: Array in SHOTS:
		var name: String = shot[0]
		if not only.is_empty() and not only.has(name):
			continue
		var hour: float = shot[1]
		TownMood.reset()
		var ov: Dictionary = shot[4]
		if not ov.is_empty():
			TownMood.override = {int(s["id"]): ov}
		_pin = hour
		WorldSim.time_of_day = hour
		WorldSim._refresh_moods_now()
		var st := _stand(String(shot[2]), s)
		var from: Vector2 = st[0]
		var at: Vector2 = st[1]
		var d := at - from
		main._teleport(from, atan2(-d.x, -d.y))
		player.set_camera(atan2(-d.x, -d.y), -0.32)
		player.set_view(Player.View.TOWN)
		await _wait(4.0 if first else 3.0)
		first = false
		var micro: Node = main.population.micro
		var ok := true
		if String(shot[3]) != "":
			ok = bool(micro.call("spawn_now", String(shot[3])))
		print("EVENTS ", name, " hour=", hour, " scene=", shot[3], " started=", ok, " villagers=", main.population.full_count)
		var t0 := Time.get_ticks_msec()
		var k := 0
		for secs: float in shot[5]:
			while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
				await get_tree().process_frame
			await _shot("%s_%d" % [name, k])
			k += 1
		micro.call("_tick")
		for sc in (micro.get("active") as Array):
			if is_instance_valid(sc):
				sc.call("finish")
	print("EVENTS log: ", MicroEvents.log)
	print("EVENTS done")
	get_tree().quit()
