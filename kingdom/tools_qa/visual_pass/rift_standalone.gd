extends SceneTree
## Standalone render of the Thornfield Rift camp through the REAL entry path (RiftDoor -> dungeon_build -> player camera).
## Two tiles: the first frames after entering, and a few seconds later. Used for the camera-spawn / floor-horizon fix.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/rift_standalone.gd -- --out=/path.png

var _out := "/tmp/rift.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	var w3 := Node3D.new()
	root.add_child(w3)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(60, 1, 60)
	cs.shape = sh
	fb.add_child(cs)
	w3.add_child(fb)
	fb.position = Vector3(0, -0.5, 0)
	var p: CharacterBody3D = (load("res://scripts/actors/player.gd") as GDScript).new()
	w3.add_child(p)
	p.global_position = Vector3(0, 0, 2)
	for i in 30:
		await physics_frame
	root.get_node("WorldSim").time_of_day = 12.0
	var door: Area3D = (load("res://scripts/world/thornfield/rift_door.gd") as GDScript).new()
	var dcs := CollisionShape3D.new()
	dcs.shape = BoxShape3D.new()
	door.add_child(dcs)
	w3.add_child(door)
	door.call("configure_rift")
	door.global_position = Vector3(0, 0, 0)
	door.call("enter", p)
	var tiles: Array[Image] = []
	for step in [2, 40, 150]:
		for i in step:
			await physics_frame
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		tiles.append(img)
		print("tile after ", step, " frames cam ", p.camera.global_position, " player ", p.global_position)
	var sheet := Image.create(640 * tiles.size(), 360, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 640, 360), Vector2i(i * 640, 0))
	sheet.save_png(_out)
	print("saved ", _out)
	quit()
