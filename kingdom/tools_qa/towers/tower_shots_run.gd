extends Node
## Logic of tower_shots.gd (a Node so autoloads exist when it compiles). Boots the real game, adds TowerSite to the world (the
## hook main.gd will carry) and flies a free camera through the views. Never pass --headless.
##   Godot --path kingdom --rendering-driver vulkan --resolution 1280x720 -s res://tools_qa/towers/tower_shots.gd -- \
##       --out=/tmp/claude-0/shots/towers --only=spire_kingsreach,camp [--budget=900]
## Views: spire_kingsreach spire_mid spire_far door camp floor_1..floor_6 safe boss banner teleport map

var out_dir := "/tmp/claude-0/shots/towers"
var only: PackedStringArray = []
var budget_s := 1100
var main: Node
var world: Node3D
var cam: Camera3D
var site: Node
var t0 := 0
var frame := 0
var started := false
const TID := "ashfall_spire"

const ALL := ["spire_kingsreach", "spire_mid", "spire_far", "door", "camp", "floor_1", "floor_2", "floor_3", "floor_4", "floor_5", "floor_6",
	"safe", "boss", "banner", "teleport", "map"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--only="): only = a.substr(7).split(",", false)
		elif a.begins_with("--budget="): budget_s = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out_dir)
	t0 = Time.get_ticks_msec()
	var ps := load("res://scenes/main.tscn") as PackedScene
	main = ps.instantiate()
	get_tree().root.add_child.call_deferred(main)


func _process(_dt: float) -> void:
	frame += 1
	if Time.get_ticks_msec() - t0 > budget_s * 1000:
		print("WATCHDOG quit")
		get_tree().quit(1)
		return
	if frame == 500 and not started:
		started = true
		_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _want(name: String) -> bool:
	return only.is_empty() or name in only


func _save(name: String) -> void:
	await _wait(3)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [out_dir, name]
	img.save_png(p)
	var vp: Viewport = get_tree().root.get_viewport()
	var sub: SubViewport = main.get("viewport")
	var rv: Viewport = sub if sub else vp
	print("SAVED ", p, " draws=", rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		" prims=", rv.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))


func _kingsreach() -> Vector2:
	for s in WorldGen.settlements:
		if String(s["name"]) == "Kingsreach":
			return s["pos"]
	return Vector2.ZERO


func _tower_pos() -> Vector2:
	for s in WorldGen.sites:
		if String(s.get("kind", "")) == "dungeon_tower":
			return s["pos"]
	return Vector2.ZERO


func _view(name: String, at: Vector2, up: float, look: Vector3, hour := 15.0, fov := 60.0, warm := 50) -> void:
	get_tree().root.get_node("WorldSim").set("time_of_day", hour)
	var player: Node3D = main.get("player")
	main.call("_teleport", at, 0.0)
	var region: Node = main.get("region")
	if region:
		region.set("focus", player.global_position)
	await _wait(10)
	var gy := WorldGen.height(at.x, at.y)
	player.visible = false
	cam.global_position = Vector3(at.x, gy + up, at.y)
	cam.look_at(look)
	cam.fov = fov
	cam.current = true
	await _wait(warm)
	await _save(name)


func _run() -> void:
	var hud: Node = main.get("hud")
	if hud:
		hud.visible = false
	world = main.get("world")
	cam = Camera3D.new()
	cam.far = 6000.0
	world.add_child(cam)
	site = load("res://scripts/world/towers/tower_site.gd").new()
	world.add_child(site)
	await _wait(5)
	var tp := _tower_pos()
	var th := WorldGen.height(tp.x, tp.y)
	print("[towers] tower at ", tp, " ground ", th, " kingsreach ", _kingsreach(), " dist ", tp.distance_to(_kingsreach()))
	var yaw: float = site.sites[TID]["yaw"]
	var front := Vector2(sin(yaw), cos(yaw))
	if _want("spire_kingsreach"):
		var k := _kingsreach()
		await _view("spire_kingsreach", k + Vector2(0, 0), 14.0, Vector3(tp.x, th + 230.0, tp.y), 16.0, 55.0, 70)
	if _want("spire_mid"):
		var at := tp + front * 950.0
		await _view("spire_mid", at, 6.0, Vector3(tp.x, th + 200.0, tp.y), 16.0, 60.0, 70)
	if _want("spire_far"):
		var dir := (Vector2.ZERO - tp).normalized()
		var at2 := tp + dir * 3400.0
		at2.x = clampf(at2.x, -3900.0, 3900.0)
		at2.y = clampf(at2.y, -3900.0, 3900.0)
		await _view("spire_far", at2, 10.0, Vector3(tp.x, th + 250.0, tp.y), 17.0, 50.0, 70)
	if _want("door"):
		var at3 := tp + front * 150.0
		await _view("door", at3, 4.0, Vector3(tp.x + front.x * 55.0, th + 18.0, tp.y + front.y * 55.0), 15.0, 65.0, 90)
	if _want("camp"):
		var at4 := tp + front * 150.0 + Vector2(-front.y, front.x) * 16.0
		await _view("camp", at4, 5.0, Vector3(tp.x + front.x * 96.0, th + 2.0, tp.y + front.y * 96.0), 15.5, 62.0, 110)
	# ---- interior views
	var realm: RefCounted = get_tree().root.get_node("Life").realm.mod("towers")
	var player: Node3D = main.get("player")
	for f in [1, 2, 3, 4, 5, 6]:
		if not _want("floor_%d" % f):
			continue
		await _floor_view(f)
	if _want("safe") or _want("banner") or _want("teleport") or _want("map") or _want("boss"):
		await _misc_views(realm, player)
	print("TOWER SHOTS DONE")
	get_tree().quit(0)


func _enter(f: int) -> void:
	site.debug_enter(TID, f)
	await _wait(20)


func _floor_view(f: int) -> void:
	await _enter(f)
	var run: Node = site.run
	var FG := preload("res://scripts/world/towers/floor_gen.gd")
	var L: Dictionary = run.L
	var o: Vector3 = run.origin
	var player: Node3D = main.get("player")
	player.visible = false
	# a corridor-level view from the arrival room down the first open way
	var sc := FG.cell_center(L["start"])
	var dist: Dictionary = L["dist"]
	# look along the longest straight run from the start region: pick the far cell with the greatest distance on row/col of start
	var m := FG.open_mask(L, L["start"])
	var dir := Vector3(1, 0, 0) if (m & FG.E) else Vector3(0, 0, 1)
	cam.global_position = o + sc + Vector3(-2.5, 2.3, -2.5) - dir * 1.0
	cam.look_at(o + sc + dir * 18.0 + Vector3(0, 1.5, 0))
	cam.fov = 70.0
	cam.current = true
	await _wait(40)
	await _save("floor_%d_%s" % [f, L["theme"]])
	run.end()
	site.run = null
	site.leave_tower()
	await _wait(5)


func _misc_views(realm: RefCounted, player: Node3D) -> void:
	var FG := preload("res://scripts/world/towers/floor_gen.gd")
	await _enter(6)
	for k in range(1, 6):
		realm.activate_gate(TID, k)
	var run: Node = site.run
	var L: Dictionary = run.L
	var o: Vector3 = run.origin
	player.visible = true
	cam.current = false
	if _want("safe"):
		var sp := FG.cell_center(L["safe_cell"])
		player.global_position = o + sp + Vector3(-2.2, 0.3, 0.8)
		player.call("set_camera", 0.8, -0.25)
		await _wait(40)
		await _save("safe")
	if _want("map"):
		# reveal most of the floor and show the big map
		for c in (L["dist"] as Dictionary):
			run.explored[c] = true
		site.ui.call("_toggle_big_map")
		run._update_map()
		site.ui.visible = true
		await _wait(10)
		var hud: Node = main.get("hud")
		await _save("map")
		site.ui.call("_toggle_big_map")
	if _want("boss"):
		# to the arena; open the door; the boss winds up a telegraph
		var bp := FG.cell_center(L["boss_cell"])
		player.global_position = o + bp + Vector3(0, 0.3, 9.0)
		player.call("set_camera", PI, -0.3)
		run.begin_boss(false)
		await _wait(30)
		var boss: Node3D = run.boss
		if boss:
			boss.call("engage", player)
			for i in 400:
				await _wait(1)
				if int(boss.get("state")) == 2:
					await _wait(int(float(boss.get("_timer")) * 30.0 * 0.0) + 14)
					break
			await _save("boss")
			# kill it for the banner
			boss.call("take_damage", 999999, player, Vector3.ZERO)
			await _wait(60)
			if _want("banner"):
				await _save("banner")
	if _want("teleport"):
		run.teleport_menu()
		await _wait(10)
		await _save("teleport")
		site.ui.close_menu()
	run.end()
	site.run = null
	site.leave_tower()
