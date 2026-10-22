extends SceneTree
## Standalone render of the F2 traversal (docs: ashes-cloud-testing). Boxes at the threshold heights, the real
## Player driven by its Traversal driver; 3 frames of a vault and 3 of a low mantle go into one PNG.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/traversal/traversal_standalone.gd -- --out=/path.png

var PlayerScript: GDScript
const Y0 := 600.0
var _root3: Node3D
var _out := "/tmp/traversal.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	root.size = Vector2i(640, 400)
	_run.call_deferred()


func _box(c: Vector3, s: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	b.add_child(mi)
	_root3.add_child(b)
	b.position = c


func _run() -> void:
	_root3 = Node3D.new()
	root.add_child(_root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	_root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	_root3.add_child(sun)
	_box(Vector3(0, Y0 - 0.5, 0), Vector3(40, 1, 40), Color(0.35, 0.45, 0.3))
	# Player faces +Z. Vault wall (0.9 m, thin) at z=+1.0; low mantle block (1.0 m, deep) at z=+9.
	_box(Vector3(0, Y0 + 0.45, 1.15), Vector3(4, 0.9, 0.3), Color(0.6, 0.45, 0.3))
	_box(Vector3(0, Y0 + 0.5, 9.7), Vector3(4, 1.0, 1.4), Color(0.55, 0.5, 0.5))
	PlayerScript = load("res://scripts/actors/player.gd")
	var p: CharacterBody3D = PlayerScript.new()
	_root3.add_child(p)
	p.global_position = Vector3(0, Y0, 0)
	p.view = 1
	var cam := Camera3D.new()
	_root3.add_child(cam)
	cam.global_position = Vector3(6.0, Y0 + 1.2, 1.0)
	cam.look_at(Vector3(0, Y0 + 0.9, 1.0))
	cam.current = true
	for i in 30:
		await physics_frame
	var shots: Array[Image] = []
	# Vault, running.
	var sp: Dictionary = Traversal_().probe(p.get_world_3d().direct_space_state, p.global_position, Vector3(0, 0, 1), [p.get_rid()], false)
	print("vault probe: ", sp["kind"])
	p.set("_move_speed", 5.0)
	p._trav.begin(sp, 5.0)
	shots.append_array(await _grab(p, [0.2, 0.5, 0.85]))
	for i in 90:
		await physics_frame
	# Mantle low.
	p.global_position = Vector3(0, Y0, 8.0)
	p.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	var mp: Dictionary = Traversal_().probe(p.get_world_3d().direct_space_state, p.global_position, Vector3(0, 0, 1), [p.get_rid()], true)
	print("mantle probe: ", mp["kind"])
	p._trav.begin(mp, 0.0)
	cam.global_position = Vector3(6.0, Y0 + 1.2, 9.2)
	cam.look_at(Vector3(0, Y0 + 0.9, 9.2))
	shots.append_array(await _grab(p, [0.3, 0.8, 1.3]))
	var sheet := Image.create(640 * 3, 400 * 2, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var im := shots[i]
		im.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(im, Rect2i(0, 0, 640, 400), Vector2i((i % 3) * 640, (i / 3) * 400))
	sheet.save_png(_out)
	print("saved ", _out, " ", shots.size())
	quit()


func Traversal_() -> GDScript:
	return load("res://scripts/actors/traversal.gd")


func _grab(p: Node, times: Array) -> Array[Image]:
	var out: Array[Image] = []
	var t0 := Time.get_ticks_msec()
	var k := 0
	var ticks := 0
	while k < times.size() and ticks < 600:
		await physics_frame
		ticks += 1
		if float(ticks) / 60.0 >= float(times[k]):
			await process_frame
			out.append(root.get_texture().get_image())
			k += 1
	return out
