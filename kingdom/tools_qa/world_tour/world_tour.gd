extends Node
## Photographs the real streamed game world: every settlement from the air and from
## street level, every region site, plus a few very high overviews. Needs a real renderer:
##   <godot> --path . res://tools_qa/world_tour/world_tour.tscn -- --out=before
## Output: docs/qa/world_tour/<out>/*.jpg and an index.txt with what each shot shows.

const MAIN := "res://scenes/main.tscn"
var main: Node
var cam: Camera3D
var out_dir := ""
var index: PackedStringArray = []
var only := ""


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	only = String(args.get("only", ""))
	var base := ProjectSettings.globalize_path("res://").path_join("../docs/qa/world_tour")
	out_dir = base.path_join(String(args.get("out", "shots"))).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1600, 900)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _ready_to_shoot() -> bool:
	return main and main.get("player") != null and main.player.is_inside_tree() \
		and main.get("hud") != null and not main.hud._loading.visible


func _focus(p: Vector2) -> void:
	main._teleport(p, 0.0)
	if main.region:
		main.region.focus = main.player.global_position
		main.region.build_all_now()


func _shoot(name: String, what: String, frames := 90) -> void:
	for i in frames:
		await get_tree().process_frame
	var img: Image = main.viewport.get_texture().get_image()
	var path := out_dir.path_join(name + ".jpg")
	img.save_jpg(path, 0.92)
	index.append("%s\t%s" % [name, what])
	print("SHOT ", path)


## Free camera at `from` (x, height above ground, z) looking at ground point `at`.
func _aim(from: Vector2, height: float, at: Vector2, fov := 55.0) -> void:
	var gy_from := WorldGen.height(from.x, from.y)
	var gy_at := WorldGen.height(at.x, at.y)
	cam.global_position = Vector3(from.x, gy_from + height, from.y)
	cam.look_at(Vector3(at.x, gy_at, at.y))
	cam.fov = fov
	cam.current = true


func _run() -> void:
	while not _ready_to_shoot():
		await get_tree().process_frame
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	main.player.apply_age()
	WorldSim.time_of_day = 15.5
	main.hud.visible = false
	cam = Camera3D.new()
	cam.far = 6000.0
	main.world.add_child(cam)

	# Settlements: aerial 3/4, top-down-ish, and a street-level look at the centre.
	for s: Dictionary in WorldGen.settlements:
		var nm: String = s["name"]
		if only != "" and not nm.to_lower().contains(only):
			continue
		var c: Vector2 = s["pos"]
		var r: float = s["radius"]
		var kind: String = s["kind"]
		_focus(c)
		main.terrain.view_radius = 6
		main.terrain.build_all_now()
		var slug := nm.to_lower()
		_aim(c + Vector2(r * 1.25, r * 1.25), r * 1.1 + 25.0, c)
		await _shoot("%s_aerial" % slug, "%s (%s, r=%d m) aerial 3/4" % [nm, kind, int(r)], 120)
		_aim(c + Vector2(r * 0.15, r * 0.35), r * 2.4 + 40.0, c, 50.0)
		await _shoot("%s_overhead" % slug, "%s overhead layout" % nm)
		# street level: from a third of the way out, looking at the centre
		var sp := c + Vector2(r * 0.35, -r * 0.2)
		_aim(sp, 2.2, c, 65.0)
		await _shoot("%s_street" % slug, "%s street level toward the centre" % nm)

	if only == "":
		# Region sites between towns (farms, mines, forts, ruins, arena, secrets...)
		var seen := {}
		for site: Dictionary in WorldGen.sites:
			var k: String = site["kind"]
			if seen.has(k):
				continue
			seen[k] = true
			var c: Vector2 = site["pos"]
			var clear := maxf(float(site["clear"]), 14.0)
			_focus(c)
			var yaw: float = site["yaw"]
			var front := Vector2(sin(yaw), cos(yaw)).rotated(0.5)
			_aim(c + front * (clear * 1.4 + 10.0), clear * 0.7 + 8.0, c, 60.0)
			await _shoot("site_%s" % k, "%s (%s)" % [site["name"], k])
		# Very high overviews of the whole 4 km map around the capital and home vale.
		_focus(Vector2(280, -210))
		main.terrain.view_radius = 8
		main.terrain.build_all_now()
		_aim(Vector2(900, 500), 520.0, Vector2(250, -200), 60.0)
		await _shoot("world_overview_vale", "Ashford -> Kingsreach vale from 520 m", 150)

	FileAccess.open(out_dir.path_join("index.txt"), FileAccess.WRITE).store_string("\n".join(index))
	get_tree().quit(0)
