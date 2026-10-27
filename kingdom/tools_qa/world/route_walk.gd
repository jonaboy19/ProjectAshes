extends SceneTree
## Benchmark slice: the SAME countryside route every time (BENCHMARK_SLICE.md acceptance). Movie Maker, scripted camera at walking
## eye height (2.2 m, slight follow lag) along data/world/real/slice_route.json, a pause at the Waymark Stone looking north to the fells,
## then on to the bandit camp. Hour pinned, weather pinned clear, HUD hidden.
## Godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie <abs>.avi -s res://tools_qa/world/route_walk.gd -- --adult
##   --world_macro=real --terrain_backend=terrain3d --profile=pc --quality=high [--slice_off] [--hour=10.5]

const BOOT := 600
const SPEED := 4.2          # m/s, a brisk walk
const PAUSE_S := 5.0
var main: Node
var cam: Camera3D
var frame := 0
var hour := 10.5
var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var stone := Vector2(318, 58)
var stone_s := 0.0           # path distance at which the view turns to the stone/fells


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			hour = float(a.get_slice("=", 1))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/real/slice_route.json"))
	for p: Array in d["path"]["points"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	stone = Vector2(float(d["landmark"]["at"][0]), float(d["landmark"]["at"][1]))
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var best := INF
	for i in pts.size():
		if pts[i].distance_to(stone) < best:
			best = pts[i].distance_to(stone)
			stone_s = cum[i]
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _at(s: float) -> Vector2:
	s = clampf(s, 0.0, cum[cum.size() - 1])
	for i in range(1, pts.size()):
		if s <= cum[i]:
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001))
	return pts[pts.size() - 1]


func _hide_overlays() -> void:
	var hud: Node = main.get("hud")
	if hud:
		hud.visible = false
	for n in root.find_children("*", "CanvasLayer", true, false):
		if not n.find_children("*", "SubViewportContainer", true, false).is_empty():
			for ch in n.get_children():
				if ch is CanvasItem and not ch is SubViewportContainer and ch.find_children("*", "SubViewportContainer", true, false).is_empty():
					(ch as CanvasItem).visible = false
			continue
		(n as CanvasLayer).visible = false


func _process(_dt: float) -> bool:
	frame += 1
	if frame < BOOT:
		return false
	var player: Node3D = main.get("player")
	if frame == BOOT:
		cam = Camera3D.new()
		cam.far = 6000.0
		cam.fov = 64.0
		(main.get("world") as Node3D).add_child(cam)
		player.visible = false
		var w: Node = main.get("weather")
		if w:
			w.call("set_weather", "clear", 0.0)
			w.set("auto", false)
		main.call("_teleport", pts[0], 0.0)
		print("[route] config world_macro=", WorldMacro.mode(), " real=", RealWorld.active(), " t3d_region_m=", Terrain3DBridge.region_m(), " slice=", not OS.get_cmdline_user_args().has("--slice_off"))
	root.get_node("WorldSim").set("time_of_day", hour)
	if frame % 15 == 0:
		_hide_overlays()
	cam.current = true
	var t := (frame - BOOT) / 30.0
	var walk_to_stone := stone_s / SPEED
	var s := 0.0
	var look_stone := 0.0
	if t < walk_to_stone:
		s = t * SPEED
	elif t < walk_to_stone + PAUSE_S:
		s = stone_s
		look_stone = sin(PI * (t - walk_to_stone) / PAUSE_S)        # turn to the stone / fells and back
	else:
		s = (t - PAUSE_S) * SPEED
	if s >= cum[cum.size() - 1] - 16.0:   # stop short of the camp so the camera never looks straight down
		quit()
		return true
	var p := _at(s)
	var ahead := _at(s + 14.0)
	var h := WorldGen.height(p.x, p.y)
	cam.global_position = Vector3(p.x, h + 2.2 + 0.03 * sin(t * 7.5), p.y)
	var look := Vector3(ahead.x, WorldGen.height(ahead.x, ahead.y) + 1.6, ahead.y)
	if look_stone > 0.0:
		var north := Vector3(stone.x, WorldGen.height(stone.x, stone.y) + 3.0, stone.y - 60.0)
		look = look.lerp(north, look_stone)
	cam.look_at(look)
	player.global_position = Vector3(p.x, h + 1.0, p.y)
	return false
