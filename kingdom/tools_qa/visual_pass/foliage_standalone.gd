extends SceneTree
## Standalone render of the camera see-through (shaders/foliage_fade.gdshaderinc): the real Player with a boulder and a tree
## a few metres in front of the chase camera. Before the pass they filled the frame; now they dither away near the lens.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/foliage_standalone.gd -- --out=/path.png

const Y0 := 600.0
var _out := "/tmp/foliage.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	var w3 := Node3D.new()
	root.add_child(w3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	w3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	w3.add_child(sun)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(60, 1, 60)
	cs.shape = sh
	fb.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	fm.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.45, 0.3)
	fm.material_override = m
	fb.add_child(fm)
	w3.add_child(fb)
	fb.position = Vector3(0, Y0 - 0.5, 0)
	var p: CharacterBody3D = (load("res://scripts/actors/player.gd") as GDScript).new()
	w3.add_child(p)
	p.global_position = Vector3(0, Y0, 0)
	for i in 60:
		await physics_frame
	var cam: Camera3D = p.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var base := Vector3(cam.global_position.x, Y0, cam.global_position.z)
	var rock := (load("res://assets/generated/region/nature/boulder_large.glb") as PackedScene).instantiate() as Node3D
	w3.add_child(rock)
	rock.global_position = base + fwd * 3.4 + right * 2.1
	rock.scale = Vector3.ONE * 1.6
	var tree := (load("res://assets/generated/region/nature/beech_a.glb") as PackedScene).instantiate() as Node3D
	w3.add_child(tree)
	tree.global_position = base + fwd * 2.8 - right * 2.2
	for n: Node3D in [rock, tree]:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh is ArrayMesh:
				(load("res://scripts/world/assets.gd") as GDScript).call("_region_materials", (mi as MeshInstance3D).mesh, n.name.to_lower())
	for i in 30:
		await physics_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	img.save_png(_out)
	print("saved ", _out, " cam ", cam.global_position)
	quit()
