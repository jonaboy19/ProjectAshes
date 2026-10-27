extends SceneTree
## W6 owner video: Movie Maker fly-over of the real-terrain world + a ground walk near Ashford. Scripted camera, HUD hidden.
## Godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie <abs>.avi -s res://tools_qa/world/flyover.gd -- --adult
##   --world_macro=real --terrain_backend=terrain3d --profile=pc --quality=high [--seconds=60] [--walk=15]
## Path (game metres): Ashford -> Emberglass Mere -> the northern snow fells -> Kingsreach -> the Rift; then a walk into Ashford.

const BOOT := 600
var main: Node
var cam: Camera3D
var frame := 0
var fly_s := 60.0
var walk_s := 15.0
var path: Array = []          # [x, z, alt]
var _walk_started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			fly_s = float(a.get_slice("=", 1))
		elif a.begins_with("--walk="):
			walk_s = float(a.get_slice("=", 1))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _waypoints() -> Array:
	var mere: Vector2 = WorldGen.lake_center
	var rift: Variant = RealWorld.place("site:The Rift:1130:1004")
	var kr: Vector2 = WorldGen.settlements[1]["pos"]
	return [[200.0, 900.0, 140.0], [0.0, 0.0, 120.0], [mere.x, mere.y, 90.0], [-300.0, -2600.0, 260.0], [400.0, -5200.0, 380.0],
		[1800.0, -3000.0, 320.0], [kr.x, kr.y, 160.0], [(rift as Vector2).x if rift != null else 2000.0, (rift as Vector2).y if rift != null else 3900.0, 150.0]]


## Catmull-Rom through the waypoints, t in 0..1 (by segment).
func _at(t: float) -> Vector3:
	var n := path.size() - 1
	var f := clampf(t, 0.0, 0.9999) * n
	var i := int(f)
	var u := f - i
	var p0: Array = path[maxi(i - 1, 0)]
	var p1: Array = path[i]
	var p2: Array = path[mini(i + 1, n)]
	var p3: Array = path[mini(i + 2, n)]
	var r := Vector3.ZERO
	for c in 3:
		var a := float(p0[c]); var b := float(p1[c]); var cc := float(p2[c]); var d := float(p3[c])
		r[c] = 0.5 * ((2.0 * b) + (-a + cc) * u + (2.0 * a - 5.0 * b + 4.0 * cc - d) * u * u + (-a + 3.0 * b - 3.0 * cc + d) * u * u * u)
	return r


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
		path = _waypoints()
		cam = Camera3D.new()
		cam.far = 6000.0
		cam.fov = 62.0
		(main.get("world") as Node3D).add_child(cam)
		cam.current = true
		player.visible = false
	root.get_node("WorldSim").set("time_of_day", 10.5)
	if frame % 15 == 0:
		_hide_overlays()
	cam.current = true          # intro / vista events grab the camera otherwise
	var t_s := (frame - BOOT) / 30.0
	if t_s < fly_s:
		var p := _at(t_s / fly_s)
		var ahead := _at(minf(t_s / fly_s + 0.012, 1.0))
		var gx := WorldGen.height(p.x, p.y)
		var cy := maxf(WorldGen.height(p.x, p.y), WorldGen.height(ahead.x, ahead.y)) + p.z
		cam.global_position = Vector3(p.x, cy, p.y)
		var ly := WorldGen.height(ahead.x, ahead.y) + ahead.z * 0.55
		cam.look_at(Vector3(ahead.x, ly, ahead.y))
		player.global_position = Vector3(p.x, gx + 1.0, p.y)     # the streamers follow the player
		return false
	var w_s := t_s - fly_s
	if w_s < walk_s:
		var a := Vector2(-70.0, -150.0)
		var b := Vector2(30.0, 40.0)
		if not _walk_started:
			_walk_started = true
			main.call("_teleport", a, 0.0)
		var q := a.lerp(b, w_s / walk_s)
		var nq := a.lerp(b, minf(w_s / walk_s + 0.05, 1.0))
		var h := WorldGen.height(q.x, q.y)
		cam.global_position = Vector3(q.x, h + 1.7 + 0.04 * sin(w_s * 9.0), q.y)
		cam.look_at(Vector3(nq.x, WorldGen.height(nq.x, nq.y) + 1.6, nq.y))
		player.global_position = Vector3(q.x, h + 1.0, q.y)
		return false
	quit()
	return true
