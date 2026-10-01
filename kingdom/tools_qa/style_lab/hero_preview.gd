extends SceneTree
## Style G hero turnaround: renders the hooded-traveller hero (lab_chars.hero_g + HeroOutfit) in Style G light,
## walking (several phases) from behind, 3/4 front and side. Prints the skeleton bone names once.
## godot --path kingdom -s tools_qa/style_lab/hero_preview.gd -- --out=C:/tmp/hero   (never --headless)

const StyleG := preload("res://scripts/style_g.gd")
const Chars := preload("res://scripts/style_lab/lab_chars.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://hero"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var root := Node3D.new()
	get_root().add_child(root)
	get_root().size = Vector2i(1200, 1200)
	var we := WorldEnvironment.new()
	we.environment = StyleG.make_environment("high")
	root.add_child(we)
	var sun := StyleG.make_sun("high")
	root.add_child(sun)
	StyleG.apply_sun(sun, "high")
	root.add_child(StyleG.make_fill())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	ground.material_override = StyleG.material_for("ground")
	root.add_child(ground)
	if "--lineup" in OS.get_cmdline_user_args():
		await _lineup(root, out)
		return
	var hero := Chars.hero_g()
	root.add_child(hero)
	for mi in hero.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var kind := 1
		var n := String(m.name).to_lower()
		if n.contains("hair") or n.contains("brow"):
			kind = 2
		elif n.contains("head") or n.contains("hand") or n.contains("skin"):
			kind = 0
		elif n.contains("boot") or n.contains("glove") or n.contains("belt"):
			kind = 3
		for si in m.mesh.get_surface_count():
			var mm := StyleG.material_for("hero_new", m.get_active_material(si), kind, "high")
			if mm:
				m.set_surface_override_material(si, mm)
		if m.name == "HeroOutfit":
			m.material_override = null
	var sk := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("BONES ", names)
	var ap := Assets.animation_player(hero)
	ap.speed_scale = 1.0
	var cam := Camera3D.new()
	cam.fov = 32
	root.add_child(cam)
	var views := {"back": Vector3(0.6, 1.5, -3.4), "front34": Vector3(-2.0, 1.4, 2.6), "side": Vector3(3.4, 1.3, 0.2)}
	for v in views:
		for ph in [0.0, 0.33]:
			ap.play("Walk")
			ap.seek(ph, true)
			ap.speed_scale = 0.0
			cam.position = views[v]
			cam.look_at(Vector3(0, 0.95, 0))
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var p := "%s_%s_%d.png" % [out, v, int(ph * 100)]
			get_root().get_texture().get_image().save_png(p)
			print("HERO -> ", p)
	quit()


## Every G6 male outfit (rows) x hair style (columns), front 3/4, to pick the hero base.
func _lineup(root: Node3D, out: String) -> void:
	var CC: GDScript = load("res://scripts/ui/character_creation.gd")
	for b in 5:
		for h in 6:
			var m: Node3D = CC.call("build_model", {"sex": "male", "head": 2, "hair": h, "hair_color": 3, "body": b, "skin": 1}, 1.78, [] as Array[String])
			m.position = Vector3(h * 0.9 - 2.25, 0, -b * 1.2)
			root.add_child(m)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.position = Vector3(0, 3.2, 6.5)
	cam.look_at(Vector3(0, 0.9, -2.4))
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "_lineup.png")
	quit()
