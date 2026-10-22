extends SceneTree
## Light QA for the F9 wilds (no main-scene boot): builds the road, the bandit camp, the hidden shrine, the Rift's camp and
## boss arena and the Watch Post at their real world positions over a small stand-in heightfield (WorldGen.height),
## and shoots each with a free camera. Writes <out>/NN_name.png plus perf.txt (draw calls per shot).
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan \
##       -s res://tools_qa/thornfield_wilds/wilds_standalone.gd -- --out=/tmp/claude-0/shots/wilds [--only=road,camp]
## then: python3 tools_qa/caves/make_sheet.py <out> <sheet.png>   (3 columns reads best: edit `cols`)
var Wilds: GDScript
var Props: GDScript
var BanditCamp: GDScript
var HiddenPlaces: GDScript
var Outpost: GDScript
var RiftLayout: GDScript
var RiftExtras: GDScript
var Build: GDScript
var Gen: GDScript

var out_dir := "/tmp/claude-0/shots/wilds"
var only: PackedStringArray = []
var cam: Camera3D
var world: Node3D
var frame := 0
var started := false
var perf: Array[String] = []
var env: Environment
var sun: DirectionalLight3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = Node3D.new()
	root.add_child.call_deferred(world)
	cam = Camera3D.new()
	cam.far = 500.0
	cam.fov = 65.0
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
	await _wait(30)
	var vp := root.get_viewport()
	vp.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	var line := "%s draws=%d prims=%d %s" % [name, vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), extra]
	perf.append(line)
	print("[wilds] ", line)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)


func _want(k: String) -> bool:
	return only.is_empty() or k in only


## A heightfield patch of the real terrain (grass, darker under forest, brown on the road) around `c`.
func _ground(c: Vector2, half := 70.0, step := 3.0) -> MeshInstance3D:
	var n := int(half * 2.0 / step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var quad: Array[Vector3] = []
			var cols: Array[Color] = []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
				var x := c.x - half + (ix + k.x) * step
				var z := c.y - half + (iz + k.y) * step
				quad.append(Vector3(x, WorldGen.height(x, z), z))
				var f := WorldGen.forest_density(x, z)
				var col := Color(0.33, 0.43, 0.2).lerp(Color(0.2, 0.3, 0.14), clampf(f, 0.0, 1.0))
				if WorldGen.road_distance(x, z) < 3.2:
					col = Color(0.45, 0.37, 0.27)
				cols.append(col)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(cols[idx])
				st.add_vertex(quad[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _stage(title_center: Vector2, hour := 15.0) -> Node3D:
	var stage := Node3D.new()
	stage.name = "Stage"
	world.add_child(stage)
	stage.add_child(_ground(title_center))
	cam.environment = env
	return stage


func _run() -> void:
	Wilds = load("res://scripts/world/thornfield/wilds.gd")
	Props = load("res://scripts/world/thornfield/wilds_props.gd")
	BanditCamp = load("res://scripts/world/thornfield/bandit_camp.gd")
	HiddenPlaces = load("res://scripts/world/thornfield/hidden_places.gd")
	Outpost = load("res://scripts/world/thornfield/outpost.gd")
	RiftLayout = load("res://scripts/world/thornfield/rift_layout.gd")
	RiftExtras = load("res://scripts/world/thornfield/rift_extras.gd")
	Build = load("res://scripts/interiors/dungeon_build.gd")
	Gen = load("res://scripts/interiors/dungeon_gen.gd")
	WorldGen.setup(WorldSim.SEED)
	var StyleGScript: GDScript = load("res://scripts/style_g.gd")
	env = StyleGScript.make_environment("low")
	sun = StyleGScript.make_sun("low")
	var fill: DirectionalLight3D = StyleGScript.make_fill()
	world.add_child(sun)
	world.add_child(fill)
	StyleGScript.apply_daylight(env, sun, fill, 15.0)
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	cam.current = true
	cam.environment = env
	var th: Vector2 = Wilds.anchor()
	# 1. the road with a runestone pair
	if _want("road"):
		var rp := _road_point(th)
		var h: Vector2 = Wilds.road_heading(rp)
		var perp := Vector2(h.y, -h.x)
		var stage := _stage(rp)
		for side: float in [-1.0, 1.0]:
			var q: Vector2 = rp + perp * 4.6 * side + h * 6.0
			var mi: MeshInstance3D = Props.prop(stage, "res://assets/generated/region/road/milestone.glb", q, Outpost.along_yaw(perp), 1.0, 1.6)
			mi.name = "Runestone"
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.45, 0.78, 1.0)
		glow.omni_range = 6.0
		glow.light_energy = 1.2
		stage.add_child(glow)
		glow.global_position = Wilds.ground(rp + h * 6.0, 1.4)
		Props.prop(stage, "signpost", rp + perp * 8.0 + h * 6.0, 0.4, 1.0)
		player.global_position = Wilds.ground(rp)
		_look(Wilds.ground(rp - h * 13.0, 2.4), Wilds.ground(rp + h * 8.0, 1.2))
		await _shot("01_road_runestone", "danger_day=%.2f night=%.2f" % [Wilds.danger(rp, 12.0), Wilds.danger(rp, 3.0)])
		stage.queue_free()
		await _wait(3)
	# 2. the bandit camp
	if _want("camp"):
		var def: Dictionary = Wilds.data()["bandit_camp"]
		var cp: Vector2 = Wilds.at(def["offset"])
		var stage2 := _stage(cp)
		var camp: Node3D = BanditCamp.create(stage2, def)
		camp.build()
		camp.spawn_roster()
		player.global_position = Wilds.ground(cp + Vector2(30, 30))
		_look(Wilds.ground(cp + Vector2(-17, 22), 6.0), Wilds.ground(cp, 1.8))
		await _wait(40)
		await _shot("02_bandit_camp", "bandits=%d danger_day=%.2f night=%.2f" % [camp.bandits().size(), Wilds.danger(cp, 12.0), Wilds.danger(cp, 3.0)])
		stage2.queue_free()
		await _wait(3)
	# 3. the hidden shrine
	if _want("shrine"):
		var sp: Vector2 = HiddenPlaces.pos_of("ruined_shrine")
		var stage3 := _stage(sp)
		var hp: Node3D = HiddenPlaces.new()
		stage3.add_child(hp)
		hp.build("ruined_shrine")
		player.global_position = Wilds.ground(sp + Vector2(8, 9))
		_look(Wilds.ground(sp + Vector2(8, 11), 3.6), Wilds.ground(sp, 2.0))
		await _shot("03_hidden_shrine")
		stage3.queue_free()
		await _wait(3)
	# 4/5. the Rift: safe camp and boss arena
	if _want("rift"):
		var g: Dictionary = RiftLayout.layout()
		var interior: Node3D = Build.build(g, {}, {"creatures": true})
		interior.position = Vector3(0, 300, 0)
		world.add_child(interior)
		RiftExtras.attach(interior, g)
		var e := interior.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
		cam.environment = e.environment
		var camp_c: Vector3 = interior.global_position + g["content"]["camp"]["fire"]
		player.global_position = camp_c + Vector3(3, 0, 5)
		_look(camp_c + Vector3(-6.5, 3.2, 6.0), camp_c + Vector3(1.5, 1.0, -1.0))
		await _wait(30)
		await _shot("04_rift_safe_camp", "tris=%d" % int(interior.get_meta("tris")))
		var bc: Vector3 = interior.global_position + Gen.cell_pos(g, g["rooms"][4]["center"])
		player.global_position = bc + Vector3(0, 0, -9)
		_look(bc + Vector3(0, 3.0, -12.5), bc + Vector3(0, 1.4, 1.0))
		await _wait(20)
		await _shot("05_rift_boss_arena")
		interior.queue_free()
		await _wait(5)
		cam.environment = env
	# 6. the Watch Post
	if _want("outpost"):
		var fort: Node3D = Outpost.new()
		var post: Dictionary = Wilds.post()
		var stage6 := _stage(post["pos"])
		stage6.add_child(fort)
		fort.build()
		fort.spawn_garrison()
		var perp6 := Vector2(fort.heading.y, -fort.heading.x)
		player.global_position = Wilds.ground(fort.center + perp6 * 30.0)
		_look(Wilds.ground(fort.center - fort.heading * 36.0 + perp6 * 24.0, 15.0), Wilds.ground(fort.center, 2.0))
		await _wait(40)
		await _shot("06_watch_post", "soldiers=%d pos=%s" % [fort.soldiers().size(), str(fort.center)])
		stage6.queue_free()
		await _wait(3)
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(perf) + "\n")
	f.close()
	print("DONE")
	quit(0)


func _road_point(th: Vector2) -> Vector2:
	var r := float(Wilds.data().get("anchor_ring", 175.0))
	var best := Vector2.INF
	var best_d := 1.0e9
	var a := 0.0
	while a < 360.0:
		var p := th + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
		var d := WorldGen.road_distance(p.x, p.y)
		if d < best_d:
			best_d = d
			best = p
		a += 2.0
	return best
