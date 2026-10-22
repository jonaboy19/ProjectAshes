extends SceneTree
## Meshy batch 3 placements in context, no main-scene boot: each m3_* yard (data/region1/world/meshy3_sites.json) is built by the
## real RegionDressing._build at its real world position over a stand-in heightfield (WorldGen.height) with the Style G daylight,
## plus the Watch Post, the Ash Hand camp and the Rift mouth (thornfield_wilds.json "extras"). Writes <out>/NN_name.png + perf.txt.
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan -s res://tools_qa/meshy3/placement_shots.gd \
##       -- --out=<abs dir> [--only=thornfield_lane,outpost]
## Gate on `free -m` (>= 6000 MB available) first. Never --headless.
var Wilds: GDScript
var Props: GDScript
var BanditCamp: GDScript
var Outpost: GDScript
var RiftEntrance: GDScript
var RD: GDScript
var out_dir := "/tmp/claude-0/shots/meshy3"
var only: PackedStringArray = []
var cam: Camera3D
var world: Node3D
var env: Environment
var frame := 0
var started := false
var perf: Array[String] = []

const YARDS := {
	"thornfield_lane": ["m3_thornfield_lane", Vector2(-20, 26), 7.0, Vector2(0, -4)],
	"thornfield_carters": ["m3_thornfield_carters", Vector2(-22, 24), 7.0, Vector2(0, 0)],
	"thornfield_wayhouse": ["m3_thornfield_wayhouse", Vector2(22, 30), 15.0, Vector2(0, -2)],
	"highcliff_stable": ["m3_highcliff_stable", Vector2(-20, 22), 6.0, Vector2(0, 0)],
	"greywatch_spearhall": ["m3_greywatch_spearhall", Vector2(-26, 34), 11.0, Vector2(0, -2)],
	"blackwater_gate": ["m3_blackwater_gate", Vector2(-22, 26), 8.0, Vector2(0, 0)],
	"redwater_dyers": ["m3_redwater_dyers", Vector2(-18, 22), 6.0, Vector2(0, 0)],
	"longmeadow_fair": ["m3_longmeadow_fair", Vector2(-24, 26), 9.0, Vector2(0, -3)],
}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = Node3D.new()
	root.add_child.call_deferred(world)
	cam = Camera3D.new()
	cam.far = 600.0
	cam.fov = 62.0
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


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _shot(name: String) -> void:
	await _wait(25)
	var vp := root.get_viewport()
	vp.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	var line := "%s draws=%d prims=%d" % [name, vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)]
	perf.append(line)
	print("[meshy3] ", line)


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)


func _ground(c: Vector2, half := 62.0, step := 2.5) -> MeshInstance3D:
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
				var col := Color(0.36, 0.45, 0.22).lerp(Color(0.22, 0.32, 0.15), clampf(f, 0.0, 1.0))
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


func _stage(c: Vector2) -> Node3D:
	var st := Node3D.new()
	world.add_child(st)
	st.add_child(_ground(c))
	return st


## `from` itself when the sight line to `at` stays above the ground, else the first of 16 rings around `at` (same distance) that does.
func _clear_from(at: Vector2, from: Vector2, lift: float) -> Vector2:
	var r := from.distance_to(at)
	var a0 := (from - at).angle()
	for k in 16:
		var a := a0 + (0.0 if k == 0 else (k + 1) / 2 * (0.4 if k % 2 == 1 else -0.4))
		var q := at + Vector2(cos(a), sin(a)) * r
		var hq := WorldGen.height(q.x, q.y) + lift
		var ok := true
		for t in 12:
			var f := (t + 1) / 13.0
			var m := q.lerp(at, f)
			if WorldGen.height(m.x, m.y) + 1.5 > lerpf(hq, WorldGen.height(at.x, at.y) + 2.0, f):
				ok = false
				break
		if ok:
			return q
	return from


static func _to_world(site: Dictionary, local: Vector2) -> Vector2:
	var yaw: float = site["yaw"]
	return (site["pos"] as Vector2) + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


func _run() -> void:
	Wilds = load("res://scripts/world/thornfield/wilds.gd")
	Props = load("res://scripts/world/thornfield/wilds_props.gd")
	BanditCamp = load("res://scripts/world/thornfield/bandit_camp.gd")
	Outpost = load("res://scripts/world/thornfield/outpost.gd")
	RiftEntrance = load("res://scripts/world/thornfield/rift_entrance.gd")
	RD = load("res://scripts/world/region_dressing.gd")
	WorldGen.setup(WorldSim.SEED)
	var SG: GDScript = load("res://scripts/style_g.gd")
	env = SG.make_environment("low")
	var sun: DirectionalLight3D = SG.make_sun("low")
	var fill: DirectionalLight3D = SG.make_fill()
	world.add_child(sun)
	world.add_child(fill)
	SG.apply_daylight(env, sun, fill, 15.0)
	cam.environment = env
	cam.current = true
	var player := Node3D.new()
	player.add_to_group("player")
	world.add_child(player)
	var i := 0
	var names: Array = YARDS.keys()
	for key: String in names:
		i += 1
		if not _want(key):
			continue
		var spec: Array = YARDS[key]
		var site := {}
		for s in WorldGen.sites:
			if String(s.get("fill_id", "")) == String(spec[0]):
				site = s
		if site.is_empty():
			print("[meshy3] site not planned: ", spec[0])
			continue
		var stage := _stage(site["pos"])
		var rd = RD.new()           # not in the tree (its _ready preloads every site asset); only its part builders are used
		var built := Node3D.new()   # mirrors RegionDressing._build: site root at the site position, yawed
		built.name = String(site["name"]).replace(" ", "")
		stage.add_child(built)
		var sp: Vector2 = site["pos"]
		built.global_position = Vector3(sp.x, WorldGen.height(sp.x, sp.y), sp.y)
		built.rotation.y = float(site["yaw"])
		rd.call("_scatter_ground", built, site)
		if (site["parts"] as Array).size() >= 12:          # RegionDressing.BAKE_MIN_PARTS
			built.set_meta("pending", (site["parts"] as Array).size())
			built.set_meta("site_id", site["id"])
		for part: Array in site["parts"]:
			rd.call("_build_part", built, site, part)
		for l: Array in site["lights"]:
			rd.call("_build_light", built, l)
		var from2: Vector2 = _to_world(site, spec[1])
		var at2: Vector2 = _to_world(site, spec[3])
		from2 = _clear_from(at2, from2, float(spec[2]))
		_look(Vector3(from2.x, WorldGen.height(from2.x, from2.y) + float(spec[2]), from2.y), Vector3(at2.x, WorldGen.height(at2.x, at2.y) + 2.0, at2.y))
		player.global_position = Vector3(from2.x, 0, from2.y)
		await _shot("%02d_%s" % [i, key])
		stage.queue_free()
		rd.free()
		await _wait(3)
	if _want("outpost"):
		var fort: Node3D = Outpost.new()
		var post: Dictionary = Wilds.post()
		var st6 := _stage(post["pos"])
		st6.add_child(fort)
		fort.build()
		var perp := Vector2(fort.heading.y, -fort.heading.x)
		player.global_position = Wilds.ground(fort.center + perp * 30.0)
		_look(Wilds.ground(fort.center - fort.heading * 22.0 + perp * 20.0, 13.0), Wilds.ground(fort.center + perp * -3.0 + fort.heading * 2.0, 1.5))
		await _wait(30)
		await _shot("20_watch_post")
		# second angle: the east side (wagon, horse) from inside the fort
		_look(Wilds.ground(fort.center - perp * 8.0 - fort.heading * 6.0, 4.5), Wilds.ground(fort.center + perp * 13.0 + fort.heading * 2.0, 1.2))
		await _shot("21_watch_post_east")
		_look(Wilds.ground(fort.center + perp * 8.0 + fort.heading * 6.0, 4.5), Wilds.ground(fort.center - perp * 13.0 - fort.heading * 3.0, 1.2))
		await _shot("22_watch_post_west")
		# the horse and the quartermaster stall up close (road frame (13.4, 0.9) and (-6.5, -9.4))
		var hp := fort.call("local", 13.4, 0.9) as Vector2
		_look(Wilds.ground(hp - perp * 7.0 + fort.heading * -5.0, 2.6), Wilds.ground(hp, 1.3))
		await _shot("25_watch_post_horse")
		var qp := fort.call("local", -6.5, -9.4) as Vector2
		_look(Wilds.ground(qp + perp * 3.0 + fort.heading * 8.0, 2.6), Wilds.ground(qp, 1.3))
		await _shot("26_watch_post_stall")
		st6.queue_free()
		await _wait(3)
	if _want("camp"):
		var def: Dictionary = Wilds.data()["bandit_camp"]
		var cp: Vector2 = Wilds.at(def["offset"])
		var st2 := _stage(cp)
		var camp: Node3D = BanditCamp.create(st2, def)
		camp.build()
		player.global_position = Wilds.ground(cp + Vector2(40, 40))
		_look(Wilds.ground(cp + Vector2(-9, 20), 6.5), Wilds.ground(cp + Vector2(5, 0), 1.5))
		await _shot("23_bandit_camp")
		st2.queue_free()
		await _wait(3)
	if _want("rift"):
		var c: Vector2 = Wilds.at(Wilds.data()["rift"]["entrance_offset"])
		var st3 := _stage(c)
		var ent: Node3D = RiftEntrance.new()
		st3.add_child(ent)
		ent.build()
		player.global_position = Wilds.ground(c + Vector2(0, -12))
		_look(Wilds.ground(c + Vector2(-5.0, -11.0), 3.0), Wilds.ground(c + Vector2(-2.0, 0.5), 1.4))
		await _shot("24_rift_mouth")
		st3.queue_free()
		await _wait(3)
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(perf) + "\n")
	f.close()
	print("DONE")
	quit(0)
