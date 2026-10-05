extends Node
## Before/after harness for the AAA camera + HUD pass (skill ashes-aaa-camera-hud). Boots the real game and renders the three
## phone views the owner flagged (S22 screens 08 hero village, 09 town street, 12 combat aftermath) from FIXED spots, with the
## real HUD on, so a code change can be judged on identical frames. Each view uses the rig's own default pitch.
## PC (Mobile renderer, never --headless):
##   Godot_console.exe --path kingdom --rendering-method mobile --resolution 2340x1080 res://tools_qa/aaa_camera/feel_views.tscn \
##       -- --adult --skipintro --out=C:/tmp/shots --tag=after
## Walk-through for Movie Maker (frames, then sheet with tools_qa/aaa_camera/frame_sheet.gd):
##   ... --write-movie C:/tmp/walk/f.png --fixed-fps 30 --resolution 1170x540 res://tools_qa/aaa_camera/feel_views.tscn -- --adult --skipintro --walk

const MAIN := "res://scenes/main.tscn"

var main: Node
var player: Player
var out := "user://feel_views"
var tag := "shot"
var walk := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--tag="):
			tag = arg.substr(6)
		elif arg == "--walk":
			walk = true
	DirAccess.make_dir_recursive_absolute(out)
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	main.hud.close_menu()
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out.path_join("%s_%s.png" % [tag, name])
	img.save_png(path)
	print("FEELVIEW saved ", path, " ", img.get_size(), " fps=", Engine.get_frames_per_second())


## Yaw that makes the camera look along world direction d (XZ).
static func yaw_for(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func _home() -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var dd := (s["pos"] as Vector2).distance_to(main.HOME_SPAWN)
		if dd < bd and s.has("plan"):
			bd = dd
			best = s
	return best


func _place(p: Vector2, look: Vector2) -> void:
	main._teleport(p, 0.0)
	var pitch := float(Player.VIEW_RIG[Player.View.THIRD][1])
	player.set_camera(yaw_for(look.normalized()), pitch)
	await frames(150)
	main.hud.close_menu()
	await frames(20)


func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	player = main.player
	WorldSim.time_of_day = 15.5
	player.set_view(Player.View.THIRD)
	await frames(30)
	var s := _home()
	var c: Vector2 = s["pos"]
	var plan: Dictionary = s["plan"]
	print("FEELVIEW home ", s.get("name", "?"), " at ", c, " spawn ", main.HOME_SPAWN, " lots ", (plan["lots"] as Array).size())
	if walk:
		await _walk(c, plan)
		get_tree().quit()
		return
	# 1. hero_village: the spawn, looking across the plaza (the phone's first frame).
	var sp: Vector2 = main.HOME_SPAWN
	await _place(sp, c - sp if c.distance_to(sp) > 3.0 else Vector2(1, -1))
	await shot("1_village")
	# 2. town_street: the first gate's cobble apron, looking out along the road.
	var ga := float(plan["gates"][0])
	var dir := Vector2(cos(ga), sin(ga))
	var wr: float = float(plan["wall_radius"]) if plan["walls"] else float(s["radius"]) * 1.1
	var side := Vector2(-dir.y, dir.x)
	await _place(c + dir * (wr - 7.0) + side * 4.0, dir.rotated(0.35))
	if OS.get_cmdline_user_args().has("--probe"):
		var pp := Vector2(player.global_position.x, player.global_position.z)
		for l: Dictionary in plan["lots"]:
			if (l["pos"] as Vector2).distance_to(pp) < 16.0:
				print("FEELPROBE lot ", l["asset"], " d=", (l["pos"] as Vector2).distance_to(pp))
		for l: Dictionary in plan["landmarks"]:
			if (l["pos"] as Vector2).distance_to(pp) < 25.0:
				print("FEELPROBE landmark ", l["asset"], " d=", (l["pos"] as Vector2).distance_to(pp))
	await shot("2_street")
	# 3. aftermath: back to a house front, the camera pushed toward its roof (the thatch that filled the phone screen).
	var lot := _near_lot(plan, sp)
	var f := Vector2(sin(float(lot["yaw"])), cos(float(lot["yaw"])))
	var lp: Vector2 = lot["pos"]
	await _place(lp + f * 7.5 + f.orthogonal() * 2.0, f.rotated(0.5))


	await shot("3_aftermath")
	# 5. the benchmark street (streets[0]) from a third of the way down, looking toward the gate, slightly to the houses
	var bst: Dictionary = plan["streets"][0]
	var bd := ((bst["b"] as Vector2) - (bst["a"] as Vector2)).normalized()
	await _place((bst["a"] as Vector2) + bd * 22.0 - bd.orthogonal() * 1.5, bd.rotated(0.3))
	for n in get_tree().root.find_children("*", "Node", true, false):
		if n.has_method("spawn_now") and n.has_method("actors_alive"):
			for id in ["laundry_day", "street_sweeper", "water_carriers"]:
				print("FEELVIEW chore ", id, " ", n.call("spawn_now", id))
			break
	await frames(240)
	var tgt: Node = main.hud.get("target")
	print("FEELVIEW focus ", tgt, " tag_visible=", (tgt.get("_tag") as Label3D).visible if tgt and tgt.get("_tag") else "n/a")
	await shot("5_benchmark")
	for hr in [18.6, 22.0]:
		WorldSim.time_of_day = hr
		await frames(90)
		await shot("6_benchmark_%d" % int(hr))
	WorldSim.time_of_day = 15.5
	# 4. a town horse up close (textured HorseRig vs the old flat Quaternius one).
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node3D and String(n.get("kind") if n.get("kind") != null else "").begins_with("horse"):
			if best == null or (n as Node3D).global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = n
	if best:
		var hp := Vector2(best.global_position.x, best.global_position.z)
		print("FEELVIEW horse ", best.get("kind"), " rig=", best.get("_rig") != null, " at ", hp)
		await _place(hp + Vector2(4.5, 1.5), Vector2(-4.5, -1.5))
		await shot("4_horse")
	print("FEELVIEW DONE")
	get_tree().quit()


## Debug: what the renderer reports between the lens and the shoulder (occluder fade input).
func _probe() -> void:
	var cam := player.camera.global_position
	var pv: Vector3 = player._pivot.global_position
	var scen := get_viewport().find_world_3d().scenario
	var fwd := -player.camera.global_transform.basis.z
	for oid in RenderingServer.instances_cull_aabb(AABB(cam + fwd * 3.0 - Vector3.ONE * 3.0, Vector3.ONE * 6.0), scen):
		var gi := instance_from_id(oid) as GeometryInstance3D
		if gi:
			var box := gi.global_transform * gi.get_aabb()
			print("FEELPROBE ", gi.get_class(), " ", gi.name, " size=", box.size, " has_pivot=", box.has_point(pv), " tr=", gi.transparency, " path=", str(gi.get_path()).right(80), " mat=", _matinfo(gi))


func _matinfo(gi: GeometryInstance3D) -> String:
	var m: Material = gi.material_override
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if m == null and mesh and mesh.get_surface_count() > 0:
		m = mesh.surface_get_material(0)
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		return (m as ShaderMaterial).shader.resource_path + " mesh=" + (mesh.resource_name if mesh else "")
	return (m.get_class() if m else "none") + " mesh=" + (mesh.resource_name if mesh else "")


func _near_lot(plan: Dictionary, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for l: Dictionary in plan["lots"]:
		var d := (l["pos"] as Vector2).distance_to(to)
		if d > 8.0 and d < bd:
			bd = d
			best = l
	return best


## Walk the benchmark street (plan streets[0], plaza -> gate): Movie Maker records every frame. The old route crossed the
## market and snagged on a stall.
func _walk(c: Vector2, plan: Dictionary) -> void:
	var st: Dictionary = plan["streets"][0]
	var a: Vector2 = st["a"]
	var e: Vector2 = st["b"]
	var dir := (e - a).normalized()
	await _place(a + dir * 2.0, dir)
	player.touch_move = Vector2(0, -1)
	var t := 0
	while t < 420:
		var here := Vector2(player.global_position.x, player.global_position.z)
		var ahead := a + dir * ((here - a).dot(dir) + 8.0)
		var want := yaw_for((ahead - here).normalized())
		player.set_camera(lerp_angle(player._yaw, want, 0.08), player._pitch)
		if t == 240:
			Input.action_press("sprint")
		await get_tree().process_frame
		t += 1
	Input.action_release("sprint")
	player.touch_move = Vector2.ZERO
	await frames(30)
	print("FEELVIEW WALK DONE")
