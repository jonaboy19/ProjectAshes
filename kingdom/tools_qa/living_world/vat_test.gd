extends Node3D
## Quick check: a skeletal villager and its VAT twin side by side on the same clip + a 12x12 VAT field.
func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.7, 0.8, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.45, 0.6, 0.3); ground.material_override = gm; add_child(ground)
	var model := Assets.mh_character("villager_man_a", 1.75, [], true)
	add_child(model); model.position = Vector3(-0.6, 0, 0)
	var anim := Assets.animation_player(model); anim.play("Walk")
	var crowd := VatCrowd.new(); add_child(crowd); crowd.load_looks(["villager_man_a"])
	var a: VatAsset = crowd.assets["villager_man_a"]
	var s := 1.75 / a.height
	crowd.put(0, "villager_man_a", Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(0.6, 0, 0)), "Walk", 0.0)
	var clips := a.clips.keys()
	var k := 1
	for x in 12:
		for z in 12:
			var tint := Color(randf_range(0.35, 0.65), randf_range(0.35, 0.65), randf_range(0.35, 0.65))
			crowd.put(k, "villager_man_a", Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * s), Vector3(-11 + x * 2.0, 0, -4 - z * 2.0)), clips[k % clips.size()], -1.0, randf_range(0.9, 1.1), tint)
			k += 1
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 2.2, 4.5); cam.look_at(Vector3(0, 1.0, -3))
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://vat_test.png")
	print("VATTEST skel pos=%.3f vat=%.3f" % [anim.current_animation_position, crowd.clip_time(0)])
	get_tree().quit()
