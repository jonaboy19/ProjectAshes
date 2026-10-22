extends Node
## QA driver for the "last 4" Thornfield visual fixes (Hesta placement/nameplate, discovery banner).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom scenes/main.tscn --rendering-driver vulkan -- --adult --quality=low \
##       --qa=res://tools_qa/last4/last4_shots.gd [--tag=after] [--only=hesta,banner] [--old]
## --old puts Hesta back at her old spot (table-facing) and draws the banner with the previous script saved at
## OLD_BANNER (git show HEAD~:kingdom/scripts/ui/discovery_banner.gd), for the "before" half of the contact sheet.
## Shots land in /tmp/claude-0/shots/last4/<tag>_<name>.png. Software GL runs ~2 fps, so the banner is pinned at its shown moment.
const Sites := preload("res://scripts/world/thornfield/sites.gd")
const HudLane := preload("res://scripts/ui/hud_lane.gd")
const OLD_BANNER := "/tmp/claude-0/-home-user-ProjectAshes/bd406f54-1c34-5ffe-a895-ca805e65a050/scratchpad/old_banner.gd"
var main: Node
var tag := "after"


func run(m: Node) -> void:
	main = m
	var only := "hesta,banner"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		if a.begins_with("--only="):
			only = a.substr(7)
	WorldSim.time_of_day = 14.0
	var old := OS.get_cmdline_user_args().has("--old")
	var b := Sites.brewery()
	var hub: Node = main.world.get_node_or_null("ThornfieldHub")
	var hesta: Node3D = hub.get("hesta")
	var from := Sites.to_world(b, Vector2(2.0, 14.0))
	main.call("_teleport", from, 0.0)
	main.region.focus = main.player.global_position
	for i in 10:
		await get_tree().process_frame
	_build_near(from)
	await get_tree().create_timer(4.0).timeout
	if old:
		var ow := Sites.to_world(b, Vector2(0.0, 8.5))
		hesta.global_position = Vector3(ow.x, WorldGen.height(ow.x, ow.y), ow.y)
		var tw := Sites.to_world(b, Sites.TABLE_AT) - ow
		hesta.rotation.y = atan2(tw.x, tw.y)
	print("HESTA at ", hesta.global_position)
	# approach from the street (the brewery's front), looking at her, like a player walking up
	var fr := Sites.front(b)
	var pw := Vector2(hesta.global_position.x, hesta.global_position.z) + fr * 3.2
	var look := Vector2(hesta.global_position.x, hesta.global_position.z) - pw
	main.call("_teleport", pw, atan2(-look.x, -look.y))
	await get_tree().create_timer(3.0).timeout
	main.player.set_camera(atan2(-look.x, -look.y), -0.22)
	main.player.reset_physics_interpolation()
	await get_tree().create_timer(3.0).timeout
	if only.contains("hesta"):
		await _shot("hesta_idle")
		hesta.call("use")
		await get_tree().create_timer(3.0).timeout
		await _shot("hesta_talk")
		if main.hud.has_method("close_menu"):
			main.hud.call("close_menu")
		await get_tree().create_timer(1.0).timeout
	if only.contains("banner"):
		HudLane.reset()
		var bnr: Control = main.hud.banner
		if old:
			var ob := Control.new()
			ob.set_script(load(OLD_BANNER))
			main.hud.add_child(ob)
			bnr = ob
		bnr.call("show_place", "Thornfield Brewery", "Brewery")
		await get_tree().create_timer(0.5).timeout
		bnr.set("_t", 1.4)
		await _shot("banner", 2)
	get_tree().quit(0)


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


func _shot(name: String, frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "/tmp/claude-0/shots/last4/%s_%s.png" % [tag, name]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("SHOT ", path)
