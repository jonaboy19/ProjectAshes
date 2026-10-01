extends SceneTree
## Light caves QA (no world boot, ~1 GB instead of 3 GB): builds dungeons straight from dungeon_build.gd and
## shoots them with a free camera, plus the hidden-entrance mouths on a flat stand-in hillside.
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan \
##       -s res://tools_qa/caves/caves_standalone.gd -- --out=/tmp/claude-0/shots/caves [--only=cave,ext]
var Gen: GDScript
var Build: GDScript
var Plan: GDScript
var View: GDScript
var out_dir := "/tmp/claude-0/shots/caves"
var only: PackedStringArray = []
var cam: Camera3D
var world: Node3D
var frame := 0
var started := false
var perf: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	Gen = load("res://scripts/interiors/dungeon_gen.gd")
	Build = load("res://scripts/interiors/dungeon_build.gd")
	Plan = load("res://scripts/world/region_caves.gd")
	View = load("res://scripts/world/region_caves_view.gd")
	world = Node3D.new()
	root.add_child.call_deferred(world)
	cam = Camera3D.new()
	cam.far = 400.0
	cam.fov = 70.0
	world.add_child.call_deferred(cam)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 30 and not started:
		started = true
		_run()
	return false


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, extra := "") -> void:
	await _wait(25)
	var vp := root.get_viewport()
	vp.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	var line := "%s draws=%d prims=%d %s" % [name, vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), extra]
	perf.append(line)
	print("[caves] ", line)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)


func _run() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	cam.current = true
	var seeds := {"cave": 11, "flooded": 12, "crystal": 13, "mine": 14, "hideout": 15, "warren": 16, "crypt": 17}
	for theme: String in Gen.THEMES:
		if not only.is_empty() and not (theme in only):
			continue
		var g: Dictionary = Gen.generate(int(seeds[theme]), theme, 2, {"id": "qa_" + theme, "rooms": 9})
		var interior: Node3D = Build.build(g, {}, {"creatures": true})
		interior.position = Vector3(0, 300, 0)
		world.add_child(interior)
		var env := interior.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
		cam.environment = env.environment
		var sp := interior.get_node("PlayerSpawn") as Node3D
		player.global_position = sp.global_position
		var c0: Vector3 = interior.global_position + Gen.cell_pos(g, g["rooms"][0]["center"])
		_look(sp.global_position + Vector3(0, 1.8, 0) - sp.global_transform.basis.z * -1.0 + Vector3(0, 0, 0), c0 + Vector3(0, 1.0, 0))
		await _wait(30)
		await _shot("%s_1_entrance" % theme, "tris=%d rooms=%d" % [int(interior.get_meta("tris")), g["rooms"].size()])
		var rid := 1
		for r: Dictionary in g["rooms"]:
			if r["role"] in ["lore", "resource", "vault", "den"]:
				rid = r["id"]
				break
		var rc: Vector3 = interior.global_position + Gen.cell_pos(g, g["rooms"][rid]["center"])
		player.global_position = rc
		_look(rc + Vector3(4, 2.4, 6), rc + Vector3(0, 1.0, 0))
		await _shot("%s_2_%s" % [theme, g["rooms"][rid]["role"]])
		var bc: Vector3 = interior.global_position + Gen.cell_pos(g, g["rooms"][g["boss_room"]]["center"])
		player.global_position = bc + Vector3(0, 0, 9)
		_look(bc + Vector3(0, 2.6, 9.5), bc + Vector3(0, 1.4, 0))
		await _wait(20)
		await _shot("%s_3_boss" % theme, "boss_lv=%d" % int(g["content"]["boss"]["level"]))
		interior.queue_free()
		await _wait(5)
	if only.is_empty() or "ext" in only:
		await _exteriors(player)
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(perf) + "\n")
	f.close()
	print("DONE")
	quit(0)


func _exteriors(player: Node3D) -> void:
	# a flat hillside stand-in: ground plane + a rock wall behind the mouth
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.2)
	ground.material_override = gm
	world.add_child(ground)
	var hill := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 14, 8)
	hill.mesh = bm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.45, 0.42, 0.38)
	hill.material_override = hm
	hill.position = Vector3(0, 7, -5.5)
	world.add_child(hill)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	cam.environment = env
	var view: Node3D = View.new()
	world.add_child(view)
	var names := [["Hollin Falls Grotto", "ext_waterfall"], ["Foxlantern Cave", "ext_vines"], ["Stonehollow Barrow", "ext_rockfall"],
		["Scarlight Grotto", "ext_night"], ["Bramblewick Burrow", "ext_visible"]]
	for e: Array in names:
		var s := {}
		for c: Dictionary in Plan.cave_sites():
			if String(c["name"]) == e[0]:
				s = c
		if s.is_empty():
			continue
		var node: Node3D = view._build(s)
		node.position = Vector3(0, 0, 0)
		node.rotation = Vector3.ZERO
		node.get_node("Door").position.y = 0.0
		if e[1] == "ext_night":
			env.background_color = Color(0.03, 0.04, 0.09)
			env.ambient_light_color = Color(0.12, 0.14, 0.25)
			sun.light_energy = 0.1
			var plug := node.get_node_or_null("NightPlug")
			if plug:
				(plug.get_node("Glow") as Node3D).visible = true
				(plug.get_node("Light") as OmniLight3D).light_energy = 1.4
		_look(Vector3(2.5, 2.2, 10.5), Vector3(0, 1.6, 0))
		await _shot(String(e[1]))
		node.queue_free()
		await _wait(3)
