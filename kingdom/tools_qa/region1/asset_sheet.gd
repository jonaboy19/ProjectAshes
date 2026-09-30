extends SceneTree
## Contact sheet of GLB/scene assets (3/4 view, each fitted to a cell, name + size + tris underneath).
##   Godot --path kingdom --resolution 1920x1080 -s res://tools_qa/region1/asset_sheet.gd -- --out=<abs png> --cols=6 \
##       --assets=res://a.glb,res://b.glb,...   (or --dir=res://assets/incoming/meshy_free/nature --filter=_lod0)
## Never --headless.

var paths: PackedStringArray = []
var out := ""
var cols := 6
var frame := 0


func _initialize() -> void:
	var dir := ""
	var filt := ".glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--cols="): cols = int(a.substr(7))
		elif a.begins_with("--assets="): paths = a.substr(9).split(",", false)
		elif a.begins_with("--dir="): dir = a.substr(6)
		elif a.begins_with("--filter="): filt = a.substr(9)
	if dir != "":
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".glb") and f.contains(filt):
				paths.append(dir.path_join(f))
	pass

func _build() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fc4e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d6f0")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.7, 0)
	sun.light_color = Color("ffe0b0")
	sun.light_energy = 1.4
	world.add_child(sun)
	var rows := int(ceil(paths.size() / float(cols)))
	var cell := 10.0
	for i in paths.size():
		var ps := load(paths[i])
		if ps == null:
			continue
		var n: Node3D = (ps as PackedScene).instantiate()
		world.add_child(n)
		var box := _aabb(n)
		var k := 7.0 / maxf(maxf(box.size.x, box.size.z), box.size.y)
		n.scale = Vector3.ONE * k
		var c := Vector3((i % cols) * cell, 0, (i / cols) * cell * 1.1)
		n.position = c - Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
		var tris := 0
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m:
				tris += m.get_faces().size() / 3
		var l := Label3D.new()
		l.text = "%s\n%.1fx%.1fx%.1f m  %dk tris" % [paths[i].get_file().get_basename(), box.size.x, box.size.y, box.size.z, tris / 1000]
		l.font_size = 40
		l.pixel_size = 0.01
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = c + Vector3(0, -0.6, 3.2)
		world.add_child(l)
	var cam := Camera3D.new()
	world.add_child(cam)
	var w := cols * cell
	var h := rows * cell * 1.1
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(h * 0.95, w * 0.56) + 4.0
	var mid := Vector3((cols - 1) * cell * 0.5, 2.0, (rows - 1) * cell * 0.55)
	cam.position = mid + Vector3(0, 60, 60)
	cam.look_at(mid)
	cam.current = true


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var b: AABB = g.global_transform * g.get_aabb() if g.is_inside_tree() else g.transform * g.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		_build()
	if frame == 40:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out, " ", paths.size())
		quit(0)
	return false
