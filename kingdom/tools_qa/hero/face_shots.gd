extends SceneTree
## Hero face QA (docs/art/FACES.md): 6 moods at face (0.85 m) and dialogue (2.2 m) range, blink_mid, talk_0..5, debug_face (brows + card magenta).
## godot --path kingdom --rendering-method mobile -s tools_qa/hero/face_shots.gd -- --out=C:/tmp/x/hero [--off=0,0.08,0.06 --size=0.11,0.1]
const StyleG := preload("res://scripts/style_g.gd")
const FaceState := preload("res://scripts/living_world/face_state.gd")
const CC := "res://scripts/ui/character_creation.gd"
var out := "user://faces"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var off_s := ""
	var size_s := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--off="):
			off_s = a.trim_prefix("--off=")
		elif a.begins_with("--size="):
			size_s = a.trim_prefix("--size=")
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	get_root().size = Vector2i(900, 900)
	var we := WorldEnvironment.new()
	we.environment = StyleG.make_environment("high")
	root.add_child(we)
	var sun := StyleG.make_sun("high")
	root.add_child(sun)
	StyleG.apply_sun(sun, "high")
	root.add_child(StyleG.make_fill())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	ground.material_override = StyleG.material_for("ground")
	root.add_child(ground)
	var cam := Camera3D.new()
	root.add_child(cam)
	var hero: Node3D = (load(CC) as GDScript).call("build_model", {"sex": "male", "v2": true, "skin": 1, "hair_color": 1, "hood": false}, 1.78, ["1H_Sword"] as Array[String])
	root.add_child(hero)
	var ap := Assets.animation_player(hero)
	if ap and ap.has_animation("Idle"):
		ap.play("Idle")
		ap.seek(0.4, true)
		ap.speed_scale = 0.0
	var sk := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var drv := sk.get_node_or_null("HeroFaceDriver")
	if drv == null:
		print("NO_DRIVER")
		quit()
		return
	for i in 40:
		await process_frame
	var card = drv.get("_card")
	print("CARD ", card != null and card.is_valid())
	if card != null and card.is_valid():
		if off_s != "":
			var o := off_s.split_floats(",")
			card.mesh.position = Vector3(o[0], o[1], o[2])
		if size_s != "":
			var z := size_s.split_floats(",")
			(card.mesh.mesh as QuadMesh).size = Vector2(z[0], z[1])
			(card.mesh.material_override as ShaderMaterial).set_shader_parameter("card_size", Vector2(z[0], z[1]))
	var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin + Vector3(0, 0.08, 0)
	var st = drv.get("_state")
	for m in FaceState.MOODS:
		drv.call("set_mood", m)
		for i in 20:
			await process_frame
		cam.fov = 22
		cam.position = hp + Vector3(0.0, 0.02, 0.85)
		cam.look_at(hp + Vector3(0, -0.05, 0))
		await _shot("face_%s" % m)
		cam.fov = 30
		cam.position = hp + Vector3(0.7, 0.0, 2.1)
		cam.look_at(hp + Vector3(0, -0.12, 0))
		await _shot("dialogue_%s" % m)
	drv.call("set_mood", "neutral")
	for i in 20:
		await process_frame
	cam.fov = 22
	cam.position = hp + Vector3(0.0, 0.02, 0.85)
	cam.look_at(hp + Vector3(0, -0.05, 0))
	st.force_blink(0.5)
	await _shot("blink_mid")
	drv.call("say", "Well met, traveller, what brings you to Kingsreach?")
	for i in 6:
		for j in 6:
			await process_frame
		await _shot("talk_%d" % i)
	# debug: brow rects + the card magenta
	var bm = drv.get("_body_mat")
	if bm != null:
		bm.set_shader_parameter("debug_face", 1.0)
	if card != null and card.is_valid():
		card.set_debug(true)
	await _shot("debug_face")
	cam.fov = 30
	cam.position = hp + Vector3(0.7, 0.0, 2.1)
	cam.look_at(hp + Vector3(0, -0.12, 0))
	await _shot("debug_dialogue")
	quit()


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)
