extends SceneTree
## Close-up comparison of thatch house candidates under the game sun + StyleG restyle (AAA pass 4).
## Godot_console.exe --path kingdom --rendering-method mobile --resolution 1800x600 -s res://tools_qa/aaa_camera/thatch_compare.gd -- --out=C:/tmp/thatch.png
const CANDS := ["res://assets/incoming/ai3d/meshy/buildings/house_peasant_a_lod0.glb",
	"res://assets/incoming/meshy_dl3/buildings/cottage_thatch_timber_lod0.glb",
	"res://assets/incoming/meshy_dl3/buildings/house_straw_thatch_lod0.glb",
	"res://assets/incoming/meshy_dl3/buildings/cottage_straw_roof_a_lod0.glb"]
var out := "C:/tmp/thatch.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	var StyleG := load("res://scripts/style_g.gd")
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	we.environment = StyleG.make_environment("high")
	w.add_child(we)
	w.add_child(StyleG.make_sun("high"))
	var tiles: Array[Image] = []
	for path: String in CANDS:
		if not ResourceLoader.exists(path):
			print("THATCH missing ", path)
			continue
		var n: Node3D = (load(path) as PackedScene).instantiate()
		w.add_child(n)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			if m.mesh is ArrayMesh:
				m.mesh = StyleG.restyle_mesh((m.mesh as ArrayMesh).duplicate(), path.get_file(), "", "house")
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var s := 9.0 / maxf(box.size.x, box.size.z)
		n.scale = Vector3.ONE * s
		var cam := Camera3D.new()
		w.add_child(cam)
		cam.fov = 54.0
		var h := box.size.y * s
		cam.look_at_from_position(Vector3(6.5, h * 0.7, 7.0), Vector3(0, h * 0.62, 0))
		cam.current = true
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(600, 600 * img.get_height() / img.get_width())
		tiles.append(img)
		n.queue_free()
		cam.queue_free()
		await process_frame
	var sheet := Image.create(600 * tiles.size(), tiles[0].get_height(), false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(600 * i, 0))
	sheet.save_png(out)
	print("THATCH saved ", out)
	quit()
