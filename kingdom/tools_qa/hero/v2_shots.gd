extends SceneTree
## Hero v2 via the character creator: godot --path kingdom --rendering-method mobile -s tools_qa/hero/v2_shots.gd -- --out=C:/tmp/x/v
## Renders look variants through CharacterCreation.build_model (skin, hair colour, hood) as front / 3/4 / back + face, and the LOD distances (6, 20, 45 m).
const StyleG := preload("res://scripts/style_g.gd")
const CC := "res://scripts/ui/character_creation.gd"
var out := "user://v2"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
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
	var looks := {
		"default": {"sex": "male", "v2": true, "skin": 1, "hair_color": 1, "hood": false},
		"darkhood": {"sex": "male", "v2": true, "skin": 4, "hair_color": 0, "hood": true},
		"fairblond": {"sex": "male", "v2": true, "skin": 0, "hair_color": 3, "hood": false},
		"ginger_tan": {"sex": "male", "v2": true, "skin": 2, "hair_color": 4, "hood": true},
	}
	for k in looks:
		var hero: Node3D = (load(CC) as GDScript).call("build_model", looks[k], 1.78, ["1H_Sword"] as Array[String])
		root.add_child(hero)
		var ap := Assets.animation_player(hero)
		if ap and ap.has_animation("Idle"):
			ap.play("Idle")
			ap.seek(0.4, true)
			ap.speed_scale = 0.0
		var sk := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for i in 4:
			await process_frame
		var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin + Vector3(0, 0.08, 0)
		cam.fov = 30
		for v in {"front": Vector3(0, 1.2, 4.2), "back": Vector3(0.3, 1.3, -4.2)}:
			cam.position = {"front": Vector3(0, 1.2, 4.2), "back": Vector3(0.3, 1.3, -4.2)}[v]
			cam.look_at(Vector3(0, 0.92, 0))
			await _shot("%s_%s" % [k, v])
		cam.fov = 22
		cam.position = hp + Vector3(-0.5, 0.0, 0.8)
		cam.look_at(hp + Vector3(0, -0.05, 0))
		await _shot("%s_face34" % k)
		cam.position = hp + Vector3(0.0, 0.02, 0.85)
		cam.look_at(hp + Vector3(0, -0.05, 0))
		await _shot("%s_face" % k)
		if k == "default":
			cam.fov = 30
			for d in [6.0, 20.0, 45.0]:
				cam.position = Vector3(0, 1.2 + d * 0.05, d)
				cam.look_at(Vector3(0, 0.92, 0))
				await _shot("lod_%d" % int(d))
		hero.queue_free()
	quit()


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("SHOT ", name)
