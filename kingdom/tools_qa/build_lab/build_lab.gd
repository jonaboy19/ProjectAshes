extends Node3D
## Build-kit lab: a sunny Style G meadow, the real build_kit module + construction crews, renderer and touch build mode.
##   <godot> --path kingdom res://tools_qa/build_lab/build_lab.tscn -- --shots=<dir>    (windowed; quits after the frame sheet)
## Without --shots it stays open: drag to aim, R rotate, PgUp/PgDn storey, Enter place, Esc cancel.
## Shots: a settlement built from the kit (blueprints, free pieces, a road, a half-built crew site), ghost states
## (green / amber plan / red), the remove highlight and a stats line with draw calls.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Renderer := preload("res://scripts/build/build_renderer.gd")
const BuildMode := preload("res://scripts/build/build_mode.gd")
const StyleG := preload("res://scripts/style_g.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")

var hub: RefCounted
var kit: RefCounted
var cam: Camera3D
var renderer: Node3D
var ui: Control
var gid := 0
var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
	var env := WorldEnvironment.new()
	env.environment = StyleG.make_environment("high")
	add_child(env)
	var sun := StyleG.make_sun("high")
	add_child(sun)
	var fill := StyleG.make_fill()
	add_child(fill)
	StyleG.apply_environment(env.environment, "high", true)
	StyleG.apply_daylight(env.environment, sun, fill, 14.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = StyleG.ph("leafy_grass", "diff", "2k")
	gm.uv1_scale = Vector3(60, 60, 1)
	gm.albedo_color = Color(0.72, 0.86, 0.5)
	ground.material_override = gm
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true

	hub = Hub.new()
	var c: RefCounted = hub.mod("construction")
	c.bag = {"log": 900, "plank": 900, "stone": 900, "cut_stone": 900, "clay": 400, "thatch": 400, "iron_ingot": 120, "tools": 40, "cloth": 40}
	c.gold_ref = {"gold": 5000}
	c.mastery_ref = Mastery.new()
	for f: String in ["build:carpentry", "build:masonry", "build:architecture"]:
		c.known[f] = true
	kit = hub.mod("build_kit")
	kit.height_fn = func(_x: float, _z: float) -> float: return 0.0
	gid = int(kit.ensure_grid(Vector3.ZERO, "Lab Hold")["gid"])
	_build_town()

	renderer = Renderer.new()
	renderer.kit = kit
	renderer.use_world_height = false
	add_child(renderer)
	renderer.rebuild_all()

	ui = BuildMode.new()
	ui.kit = kit
	ui.camera = cam
	ui.world = self
	ui.renderer = renderer
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.open()
	_look(Vector3(-26, 22, 34), Vector3(4, 2, 2))
	if out_dir != "":
		_shots.call_deferred()


func _put(kind: String, x: float, z: float, rot := 0, lv := 0) -> void:
	kit.place(gid, kit.snap_local(gid, kind, Vector3(x, 0, z), rot, lv), false)


func _build_town() -> void:
	# built with materials in hand (done) ...
	kit.hub.mod("construction")
	for bp: Array in [["townhouse", 0, 0, 0], ["townhouse", 3, 0, 0], ["cottage", -4, 0, 0], ["smithy", 7, 1, 0], ["townhouse", 0, -5, 2], ["cottage", 4, -5, 2]]:
		kit.place_blueprint(gid, String(bp[0]), int(bp[1]), int(bp[2]), int(bp[3]))
	# blueprints are laid as plans: these are "built" straight away for the lab town, except the last group handed to a crew
	for pid: int in kit.grids[gid]["pieces"]:
		kit.grids[gid]["pieces"][pid]["state"] = "done"
	kit.place_blueprint(gid, "townhouse", -4, -5, 2)
	var h: Dictionary = kit.hand_to_workers(gid, "Lab crew")
	if bool(h["ok"]):
		var site: Dictionary = kit.hub.mod("construction").sites[int(h["site"])]
		site["progress"] = float(site["total"]) * 0.55
	kit.place_blueprint(gid, "palisade_corner", -9, -9, 0)
	for x in range(-8, 16, 1):
		if x % 3 != 0:
			_put("fence_rail", x * 2.0, 13.0)
	for p: Array in [["meshy_well_stone_roofed", 2, 6.5, 0], ["meshy_stall_potatoes", -3, 7, 6], ["meshy_stall_open_roof", 8, 7.5, 18],
			["meshy_lamp_post_timber_cross", 5, 6, 0], ["hay_cart", 12, 9, 4], ["barrel_cluster", 6, 3.2, 0], ["laundry_line", -6, 10, 0],
			["meshy_hay_bale_round", 14, 4, 0], ["meshy_banner_stand_iron_frame", -1, 6, 0], ["mud_puddle", 3.5, 9, 3],
			["anvil", 16, 3.5, 2], ["workbench", 17, 6, 6], ["meshy_chest_metal_wood", 18, 3, 0], ["oven", -9, 5, 0], ["loom", -10, 2.5, 6]]:
		kit.place(gid, kit.snap_local(gid, String(p[0]), Vector3(float(p[1]), 0, float(p[2])), int(p[3]), 0), false)
	var stroke: Array = []
	for i in 30:
		stroke.append(Vector3(-14 + i * 1.3, 0, 5 + sin(i * 0.25) * 2.0))
	kit.add_road(gid, "cobble", preload("res://scripts/build/road_tool.gd").process(stroke))


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


func _frame() -> void:
	for i in 6:
		await get_tree().process_frame


func _save(name: String) -> void:
	await _frame()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(out_dir.path_join(name + ".jpg"), 0.86)


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frame()
	ui.visible = false
	_look(Vector3(-18, 15, 26), Vector3(4, 2, 0))
	await _save("01_settlement_overview")
	_look(Vector3(-6, 5, 18), Vector3(4, 4, 0))
	await _save("02_street_eye_level")
	_look(Vector3(-22, 12, -24), Vector3(-6, 2, -9))
	await _save("03_crew_site_half_built")
	ui.visible = true
	# ghost states, aimed through the camera like a finger
	_look(Vector3(14, 14, 26), Vector3(14, 0, 14))
	ui.pick("foundation_stone")
	ui.aim_screen = cam.unproject_position(Vector3(22, 0, 16))
	await _save("04_ghost_green_foundation")
	ui.pick("wall_plaster_window")
	ui.aim_screen = cam.unproject_position(Vector3(30, 0.5, 21))
	await _save("05_ghost_red_no_support")
	kit.hub.mod("construction").bag["cut_stone"] = 0
	ui.pick("wall_stone")
	ui.plan_mode = false
	ui.aim_screen = cam.unproject_position(Vector3(22, 0.5, 17))
	await _save("06_ghost_amber_plan")
	_look(Vector3(-8, 12, 18), Vector3(2, 3, 2))
	ui.set_mode("remove")
	ui.set_level(1)
	ui.aim_screen = cam.unproject_position(Vector3(0, 3.5, 3))
	await _save("07_remove_highlight")
	ui.visible = false
	_look(Vector3(-18, 15, 26), Vector3(4, 2, 0))
	await _frame()
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var line := "BUILDLAB pieces=%d multimeshes=%d roads=%d draw_calls=%d primitives=%d" % [kit.piece_count(gid), renderer.stats["multimeshes"], renderer.stats["roads"], dc, prim]
	print(line)
	var f := FileAccess.open(out_dir.path_join("stats.txt"), FileAccess.WRITE)
	f.store_line(line)
	f.close()
	get_tree().quit()
