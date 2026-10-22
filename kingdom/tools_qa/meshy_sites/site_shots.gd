extends Node
## QA driver (Medieval pass, local): one 3/4 shot of each named Region 1 site, to check placed meshy_free models (floating, buried, overlapping).
##   godot --path kingdom --resolution 1280x720 --rendering-driver vulkan -- --adult --quality=high \
##       --qa=res://tools_qa/meshy_sites/site_shots.gd --sites=kingsreach_ward,oakvale_farm --out=C:/tmp/sites [--dist=34] [--angle=0.6]
## `--sites=all` shoots every site whose r1id is in data/region1/world/meshy_extra.json (+ add_parts hosts). Saves <out>/<r1id>.png.
const R1W := preload("res://scripts/world/region1_world.gd")
var main: Node
var cam: Camera3D


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var out_dir := String(args.get("out", "user://sites"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ids: Array = String(args.get("sites", "")).split(",", false)
	if ids == ["all"]:
		ids = []
		var extra: Dictionary = R1W.data("meshy_extra.json")
		for es: Dictionary in extra.get("extra_sites", []):
			if es.has("name"):
				ids.append(String(es["id"]))
		ids.append_array((extra.get("add_parts", {}) as Dictionary).keys())
	main.hud.visible = false
	main.player.visible = false
	WorldSim.time_of_day = 14.0
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 1200.0
	main.world.add_child(cam)
	var placed := 0
	var missing: Array = []
	for id: String in ids:
		var site: Dictionary = R1W.site(id)
		if site.is_empty():
			missing.append(id)
			continue
		placed += 1
		await _shoot(site, id, out_dir, float(args.get("dist", "30")), float(args.get("angle", "0.5")))
	print("SITES shot=%d missing=%s" % [placed, str(missing)])
	get_tree().quit(0)


func _shoot(site: Dictionary, id: String, out_dir: String, dist: float, ang: float) -> void:
	var p: Vector2 = site["pos"]
	var yaw: float = site["yaw"]
	var fwd := Vector2(sin(yaw), cos(yaw)).rotated(ang)
	var from := p + fwd * (dist + float(site["clear"]) * 0.5)
	# The player is parked well behind the site (a work station next to him opens a dialog); the streamers are pointed at the site.
	var park := p - fwd * (float(site["clear"]) + 60.0)
	main.call("_teleport", park, atan2(fwd.x, fwd.y))
	# main._process copies the player position into every streamer; the terrain alone can be redirected (stream_focus).
	Engine.set_meta("stream_focus", Vector3(p.x, WorldGen.height(p.x, p.y), p.y))
	main.terrain.focus = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	main.terrain.build_all_now()
	for i in 240:
		await get_tree().process_frame
	var n := 0
	while not main.region._queue.is_empty() and n < 900:
		await get_tree().process_frame
		n += 1
	for i in 40:
		await get_tree().process_frame
	cam.global_position = Vector3(from.x, maxf(WorldGen.height(from.x, from.y), WorldGen.height(p.x, p.y)) + 11.0, from.y)
	cam.look_at(Vector3(p.x, WorldGen.height(p.x, p.y) + 2.5, p.y))
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, id]
	img.save_png(path)
	Engine.remove_meta("stream_focus")
	var vp: Viewport = main.viewport
	print("SHOT %s parts=%d calls=%d prims=%d" % [path, (site["parts"] as Array).size(), vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)])
