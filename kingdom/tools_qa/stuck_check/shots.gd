extends Node
## Screenshots of the spots stuck_check flagged (needs a real renderer, never --headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver vulkan \
##       res://tools_qa/stuck_check/shots.tscn -- --out=after --skipintro
## Spots are looked up from the plan, so they follow the generator: a townhouse door path in
## Kingsreach's gate street, the inner-wall gates on the market streets, and a gap between lots.

const MAIN := "res://scenes/main.tscn"
var main: Node
var player: Player
var out_dir := ""


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var base := ProjectSettings.globalize_path("res://").path_join("../docs/qa/stuck_check")
	out_dir = base.path_join(String(args.get("out", "shots"))).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _look(from: Vector2, at: Vector2, name: String, pitch := -0.18, extra := 1.4) -> void:
	main._teleport(from, 0.0)
	var d := at - from
	player.set_camera(atan2(-d.x, -d.y), pitch)
	player.set_view(Player.View.THIRD)
	for i in 120:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".jpg")
	img.save_jpg(path, 0.9)
	print("SHOT ", path)


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._loading.visible):
		await get_tree().process_frame
	player = main.player
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	WorldSim.time_of_day = 12.0
	var kr: Dictionary = {}
	for s: Dictionary in WorldGen.settlements:
		if s["name"] == "Kingsreach":
			kr = s
	var plan: Dictionary = kr["plan"]
	var c: Vector2 = kr["pos"]
	main._teleport(c, 0.0)
	await get_tree().create_timer(1.0).timeout
	# 1. townhouse door paths that used to run into a stall or barrels (gate street)
	var paths: Array = plan["paths"]
	for idx in [6, 10]:
		var pth: Dictionary = paths[idx]
		var to_street: Vector2 = ((pth["b"] as Vector2) - (pth["a"] as Vector2)).normalized()
		await _look((pth["b"] as Vector2) + to_street * 3.0, pth["a"], "door_path_%d" % idx)
	# 2. inner wall gates on the market streets (were solid wall across the street axis)
	var g: Array = plan["gates"]
	var ir: float = plan["inner_wall"]
	for k in g.size():
		var dir := Vector2(cos(float(g[k])), sin(float(g[k])))
		await _look(c + dir * (ir - 9.0), c + dir * (ir + 4.0), "inner_gate_%d" % k, -0.15)
	# 3. a gap between lots that is now closed
	var seals: Array = []
	var root: Node = main.settlements.get_node_or_null("Kingsreach")
	for ch in root.get_children():
		if "GapSeal" in String(ch.name):
			seals.append(Vector2((ch as Node3D).global_position.x, (ch as Node3D).global_position.z))
	if not seals.is_empty():
		var sp: Vector2 = seals[0]
		var away := (c - sp).normalized()
		await _look(sp + away * 9.0, sp, "gap_sealed", -0.25)
	# 4. the gate itself: opening centred on the street
	var g0 := Vector2(cos(float(g[0])), sin(float(g[0])))
	var wr: float = plan["wall_radius"]
	await _look(c + g0 * (wr - 12.0), c + g0 * wr, "outer_gate", -0.12)
	get_tree().quit(0)
