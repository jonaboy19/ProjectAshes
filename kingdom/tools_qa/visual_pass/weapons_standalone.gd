extends SceneTree
## Standalone render of the held weapons: the real Player on a floor, each weapon idle and mid-swing.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/weapons_standalone.gd -- --out=/path.png
## Columns: bronze sword, bronze spear, ash staff, ash shortbow. Rows: idle, mid-swing.

const ITEMS := ["bronze_sword", "bronze_spear", "ash_staff", "ash_shortbow"]
const TILE := Vector2i(480, 405)
var _out := "/tmp/weapons.png"
var _w3: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	_w3 = Node3D.new()
	root.add_child(_w3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	_w3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	_w3.add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(40, 1, 40)
	cs.shape = sh
	floor_body.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	fm.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.45, 0.3)
	fm.material_override = m
	floor_body.add_child(fm)
	_w3.add_child(floor_body)
	floor_body.position = Vector3(0, 599.5, 0)
	var p: CharacterBody3D = (load("res://scripts/actors/player.gd") as GDScript).new()
	_w3.add_child(p)
	p.global_position = Vector3(0, 600.0, 0)
	var cam := Camera3D.new()
	_w3.add_child(cam)
	cam.fov = 40.0
	cam.global_position = Vector3(-2.2, 601.3, 2.6)
	cam.look_at(Vector3(0, 600.95, 0))
	p.camera.current = false
	cam.make_current()
	for i in 40:
		await physics_frame
	print("MODEL ", p._model.visible, " ", p._model.global_position, " children ", p._model.get_child_count(), " body ", p._body_node)
	var sheet := Image.create(TILE.x * ITEMS.size(), TILE.y * 2, false, Image.FORMAT_RGB8)
	for c in ITEMS.size():
		root.get_node("Life").equipment.equip(ITEMS[c])
		for i in 20:
			await physics_frame
		await process_frame
		await process_frame
		_blit(sheet, root.get_texture().get_image(), c, 0)
		_report(p)
		p.attack()
		for i in 14:
			await physics_frame
		await process_frame
		await process_frame
		_blit(sheet, root.get_texture().get_image(), c, 1)
		for i in 70:
			await physics_frame
		print("shot ", ITEMS[c], " cam=", root.get_camera_3d().get_path(), " is_mine=", root.get_camera_3d() == cam, " playercam=", p.camera.global_position, " cur=", p.camera.current, " mine=", cam.global_position, " player=", p.global_position, " vis=", p.visible)
	sheet.save_png(_out)
	print("saved ", _out)
	quit()


func _blit(sheet: Image, im: Image, c: int, r: int) -> void:
	im.convert(Image.FORMAT_RGB8)
	im.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	sheet.blit_rect(im, Rect2i(Vector2i.ZERO, TILE), Vector2i(c * TILE.x, r * TILE.y))


## Prints each hand-attached prop's blade axis (model +Y) in the player's local frame: x right, y up, z forward.
func _report(p: Node3D) -> void:
	var inv := p.global_transform.basis.inverse()
	for sk in p.find_children("*", "Skeleton3D", true, false):
		for a in sk.get_children():
			if a is BoneAttachment3D and (a as BoneAttachment3D).bone_name == "hand_r":
				for ch in a.get_children():
					if ch is Node3D:
						var axis: Vector3 = inv * (ch as Node3D).global_transform.basis.y.normalized()
						var bb: Basis = inv * (a as Node3D).global_transform.basis
						print("  bone basis cols x=", bb.x.normalized().snapped(Vector3.ONE * 0.01), " y=", bb.y.normalized().snapped(Vector3.ONE * 0.01), " z=", bb.z.normalized().snapped(Vector3.ONE * 0.01))
						print("  prop ", a.name, " vis=", (a as Node3D).visible, " axisY(local)=", axis.snapped(Vector3.ONE * 0.01))
