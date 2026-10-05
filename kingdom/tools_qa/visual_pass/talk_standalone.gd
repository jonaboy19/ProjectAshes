extends SceneTree
## Standalone render of the conversation camera framing: the real Player and a talker on a floor, talk framing on, with the
## bottom third (where the talk sheet sits) tinted red. Faces and upper bodies belong in the clear top 60%.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/talk_standalone.gd -- --out=/path.png

const Y0 := 600.0
var _out := "/tmp/talk.png"


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
	var props: Array[String] = []
	var npc: Node3D = (load("res://scripts/world/assets.gd") as GDScript).call("character", "Rogue_Hooded", 1.74, props)
	w3.add_child(npc)
	npc.global_position = Vector3(0.0, Y0, -2.2)
	npc.rotation.y = 0.0
	for i in 40:
		await physics_frame
	p.set_talk_framing(true)
	for i in 90:
		await physics_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var h := img.get_height()
	var w := img.get_width()
	for y in range(int(h * 0.62), h):          # the talk sheet: the lower third
		for x in w:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, c.lerp(Color(0.8, 0.1, 0.1), 0.45))
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	img.save_png(_out)
	print("saved ", _out, " cam fov ", p.camera.fov)
	quit()
