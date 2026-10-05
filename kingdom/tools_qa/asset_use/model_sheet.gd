extends SceneTree
## Contact sheet of meshy_free models AS THE GAME SHOWS THEM (Assets.static_model: merged and Style G restyled), front-3/4 view,
## name + size under each. For checking orientation, scale and colour of pieces placed by docs/qa/ASSET_AUDIT.md work.
##   xvfb-run -a -s "-screen 0 1600x900x24" Godot --path kingdom --rendering-driver vulkan --resolution 1600x900 \
##       -s res://tools_qa/asset_use/model_sheet.gd -- --out=/tmp/x.png --cols=6 --items=banners/banner_spear_top,lighting/sconce_wall_bowl_a
## Items are "<cat>/<name>" under assets/incoming/meshy_free (lod0), or a res:// path. Never --headless.

var items: PackedStringArray = []
var out := "/tmp/model_sheet.png"
var cols := 6
var frame := 0
var cell := 6.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--cols="): cols = int(a.substr(7))
		elif a.begins_with("--items="): items = a.substr(8).split(",", false)
		elif a.begins_with("--cell="): cell = float(a.substr(7))


func _build() -> void:
	var assets: GDScript = load("res://scripts/world/assets.gd")
	var sg: GDScript = load("res://scripts/style_g.gd")
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env: Environment = sg.call("make_environment", "medium")
	env.fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a9c4dd")
	we.environment = env
	world.add_child(we)
	var sun: DirectionalLight3D = sg.call("make_sun", "medium")
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(cols * cell + 4.0, (ceili(items.size() / float(cols)) + 1) * cell * 1.5 + 4.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("7d8a55")
	ground.material_override = gm
	ground.position = Vector3(cols * cell * 0.5 - cell * 0.5, -0.01, ceili(items.size() / float(cols)) * cell * 0.75 - cell * 0.5)
	world.add_child(ground)
	for i in items.size():
		var path := items[i]
		if not path.begins_with("res://"):
			path = "res://assets/incoming/meshy_free/" + path + "_lod0.glb"
		if not ResourceLoader.exists(path):
			print("MISSING ", path)
			continue
		var n: Node3D = assets.call("static_model", path)
		if n == null:
			continue
		var holder := Node3D.new()
		world.add_child(holder)
		holder.add_child(n)
		var box: AABB = assets.call("visual_aabb", holder)
		var k := (cell * 0.8) / maxf(maxf(box.size.x, box.size.z), box.size.y)       # every model fills its cell; the label has the real size
		holder.scale = Vector3.ONE * k
		var c := Vector3((i % cols) * cell, 0.0, (i / cols) * cell * 1.5)
		holder.position = c - Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
		var l := Label3D.new()
		l.text = "%s\n%.1f x %.1f x %.1f" % [items[i].get_file(), box.size.x, box.size.y, box.size.z]
		l.font_size = 28
		l.pixel_size = 0.008
		l.outline_size = 8
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = c + Vector3(0, 0.1, cell * 0.42)
		world.add_child(l)
	var cam := Camera3D.new()
	world.add_child(cam)
	var rows := ceili(items.size() / float(cols))
	var mid := Vector3((cols - 1) * cell * 0.5, 1.0, (rows - 1) * cell * 0.75)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(cols * cell * 0.5625, rows * cell * 1.6) + 1.0
	cam.position = mid + Vector3(0, cell * 2.0, cell * 8.0)
	cam.look_at(mid)
	cam.current = true


func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		_build()
	if frame == 60:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out, " ", items.size())
		quit(0)
	return false
