extends Node
## Inn night-glare probe: the town_sheet "street" view of a town at night, one frame per Viewport debug draw mode
## (normal, unshaded, lighting, overdraw, normal buffer) so the blown-out patch can be pinned to albedo, lighting or emission.
##   godot --path kingdom --resolution 1280x720 -- --adult --quality=high --qa=res://tools_qa/towns_medieval/glare_probe.gd
##       --town=Ashford --hour=21.5 --out=<dir>

var main: Node
var vp_save_only_normal := false


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var town_name := String(args.get("town", "Ashford"))
	var hour := float(args.get("hour", "21.5"))
	var out := String(args.get("out", "user://glare"))
	DirAccess.make_dir_recursive_absolute(out)
	main.hud.visible = false
	main.player.visible = false
	var town: Dictionary = {}
	for s in WorldGen.settlements:
		if s["name"] == town_name:
			town = s
	var plan: Dictionary = town["plan"]
	var c: Vector2 = town["pos"]
	var g0 := float(plan["gates"][0])
	var dir := Vector2(cos(g0), sin(g0))
	var eye := c + dir * (float(plan["plaza_r"]) + 30.0)
	main.call("_teleport", c + dir * (float(plan["wall_radius"]) + 90.0), 0.0)
	await get_tree().create_timer(0.4).timeout
	for i in 5:
		main.settlements.update_now()
	main.settlements.finish_prop_jobs()
	main.terrain.focus = Vector3(eye.x, 0, eye.y)
	main.terrain.build_all_now()
	var cam := Camera3D.new()
	cam.fov = 62.0
	main.world.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(eye.x, WorldGen.height(eye.x, eye.y) + 2.6, eye.y)
	cam.look_at(Vector3(c.x, WorldGen.height(c.x, c.y) + 3.2, c.y))
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for i in 120:
		WorldSim.time_of_day = hour
		await get_tree().process_frame
	# every light near the inn door (the patch sits on the inn porch)
	var inn_door := Vector2.INF
	for lot: Dictionary in plan["lots"]:
		if String(lot["asset"]) == "inn":
			inn_door = CityPlanner.door_point(lot)
	for l in get_tree().root.find_children("*", "Light3D", true, false):
		var lp: Vector3 = (l as Light3D).global_position
		if inn_door != Vector2.INF and Vector2(lp.x, lp.z).distance_to(inn_door) < 15.0:
			var rng := (l as OmniLight3D).omni_range if l is OmniLight3D else ((l as SpotLight3D).spot_range if l is SpotLight3D else -1.0)
			print("GLARE_LIGHT %s %s at %s energy=%.2f range=%.1f visible=%s parent=%s" % [l.get_class(), l.name, lp, (l as Light3D).light_energy, rng, (l as Node3D).is_visible_in_tree(), l.get_parent().name])
	# elimination: --envoff=ssr|glow|ssil|ssao switches that Environment effect off on every WorldEnvironment
	var envoff := String(args.get("envoff", ""))
	if envoff != "":
		for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (we as WorldEnvironment).environment
			if env == null:
				continue
			match envoff:
				"ssr": env.ssr_enabled = false
				"glow": env.glow_enabled = false
				"ssil": env.ssil_enabled = false
				"ssao": env.ssao_enabled = false
		print("GLARE envoff ", envoff)
		vp_save_only_normal = true
		# elimination: --hide=<node name> (LampGlowBatch, LightPools, ...) hides every node of that name before the frames
	var hide := String(args.get("hide", ""))
	if hide != "":
		var n_hidden := 0
		for nd in get_tree().root.find_children(hide if hide != "Decal" else "*", "Decal" if hide == "Decal" else "", true, false):
			if nd is Node3D:
				(nd as Node3D).visible = false
				n_hidden += 1
		print("GLARE hid ", n_hidden, " ", hide)
		for i in 6:
			await get_tree().process_frame
		vp_save_only_normal = true
	var vp: Viewport = main.viewport
	var modes := {"normal": Viewport.DEBUG_DRAW_DISABLED, "unshaded": Viewport.DEBUG_DRAW_UNSHADED, "lighting": Viewport.DEBUG_DRAW_LIGHTING,
		"overdraw": Viewport.DEBUG_DRAW_OVERDRAW, "normals": Viewport.DEBUG_DRAW_NORMAL_BUFFER}
	for k: String in modes:
		if vp_save_only_normal and k != "normal":
			continue
		vp.debug_draw = modes[k]
		for i in 4:
			WorldSim.time_of_day = hour
			if hide != "":      # the night switch re-shows lamps every frame: hide again
				for nd in get_tree().root.find_children(hide if hide != "Decal" else "*", "Decal" if hide == "Decal" else "", true, false):
					if nd is Node3D:
						(nd as Node3D).visible = false
			await get_tree().process_frame
		vp.get_texture().get_image().save_png("%s/%s_%s%s%s.png" % [out, town_name, k, ("_no_" + hide) if hide != "" else "", ("_env_no_" + envoff) if envoff != "" else ""])
		print("GLARE ", k)
	vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	get_tree().quit(0)
