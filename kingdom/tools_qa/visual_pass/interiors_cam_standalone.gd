extends SceneTree
## Standalone render of the REAL entry path: a real Player walks through an InteriorDoor into a modular interior, so the
## chase camera, spawn framing, wall collision and night light are what the game shows. One tile per layout and hour.
## xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan -s res://tools_qa/visual_pass/interiors_cam_standalone.gd -- --out=/path.png
## Rows: cottage, general_store, tavern_inn; columns: 12:00 and 23:00.

var IDS: Array = ["cottage", "general_store", "tavern_inn"]
var HOURS: Array = [12.0, 23.0]
var _loft := false     # --loft: stand the player at the top of the ladder
var _yaw := NAN        # --yaw=<radians>: camera yaw after the loft teleport
var _npcs := false     # --npcs: let the household walk in (bodies in view)
const TILE := Vector2i(560, 315)
var _out := "/tmp/interiors_cam.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--ids="):
			IDS = Array(a.substr(6).split(","))
		if a.begins_with("--hours="):
			HOURS = []
			for h in a.substr(8).split(","):
				HOURS.append(float(h))
		if a == "--loft":
			_loft = true
		if a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		if a == "--npcs":
			_npcs = true
	_run.call_deferred()


func _run() -> void:
	var Layouts: GDScript = load("res://scripts/interiors/interior_layouts.gd")
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
	var sheet := Image.create(TILE.x * HOURS.size(), TILE.y * IDS.size(), false, Image.FORMAT_RGB8)
	for r in IDS.size():
		for c in HOURS.size():
			root.get_node("WorldSim").time_of_day = HOURS[c]
			var door: Area3D = (load("res://scripts/interiors/interior_door.gd") as GDScript).new()
			door.set("interior_scene", Layouts.scene_path(IDS[r]))
			var dcs := CollisionShape3D.new()
			dcs.shape = BoxShape3D.new()
			door.add_child(dcs)
			w3.add_child(door)
			door.global_position = Vector3(0, 0, 0)
			door.call("enter", p)
			var room: Node3D = door.get("interior")
			if room != null:
				room.set("spawn_npcs", _npcs)
			for i in 90:
				await physics_frame
			if _loft and room != null and not (room.get("layout") as Dictionary).get("loft", {}).is_empty():
				var lf: Dictionary = room.get("layout")["loft"]
				p.global_position = room.to_global((lf["ladder_top"] as Vector3) + Vector3(0, 0.15, -0.6))
				p.velocity = Vector3.ZERO
				if not is_nan(_yaw):
					p.set_camera(_yaw, -0.2)
				for i in 90:
					await physics_frame
			await process_frame
			await process_frame
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(c * TILE.x, r * TILE.y))
			print("shot ", IDS[r], " ", HOURS[c], " draws ", room.call("draw_estimate") if room != null else "none", " cam ", p.camera.global_position)
			door.call("leave")
			door.queue_free()
			for i in 5:
				await physics_frame
	sheet.save_png(_out)
	print("saved ", _out)
	quit()
