extends SceneTree
## Walk-in camera for Movie Maker: boots the real game, then walks a camera (and the player, so the world
## streams) along a path at a steady pace, looking at a target. Pre-roll frames (boot) are numbered below
## --start; delete them before making sheets.
##   Godot --path kingdom --resolution 1280x720 --write-movie <dir>/f.png --fixed-fps 30 \
##       -s res://tools_qa/region1/walkin.gd -- --adult --skipintro --quality=high [--path=hollins_gate]
## Quits by itself after the walk (and on a wall-clock watchdog).

const PATHS := {
	# From the Ashrun Bridge road up through Hollin's Gate into the valley; the falls at the end.
	"hollins_gate": {"pts": [[-296, -214], [-285, -262], [-273, -310], [-260, -372], [-250, -420], [-240, -466], [-228, -510]],
		"look": [-148, -910], "look_up": 45.0, "speed": 7.5, "hour": 15.4, "up": 2.2},
}
const START := 600

var main: Node
var cam: Camera3D
var frame := 0
var t0 := 0
var spec: Dictionary
var pts: Array[Vector2] = []
var dist := 0.0
var total := 0.0


func _initialize() -> void:
	var which := "hollins_gate"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--path="): which = a.substr(7)
	spec = PATHS[which]
	for p: Array in spec["pts"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	t0 = Time.get_ticks_msec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _at(d: float) -> Vector2:
	var acc := 0.0
	for i in range(1, pts.size()):
		var l := pts[i].distance_to(pts[i - 1])
		if acc + l >= d:
			return pts[i - 1].lerp(pts[i], (d - acc) / l)
		acc += l
	return pts[pts.size() - 1]


func _process(dt: float) -> bool:
	frame += 1
	if Time.get_ticks_msec() - t0 > 900000:
		print("WATCHDOG")
		quit(1)
		return true
	if frame < START - 60:
		return false
	var player: Node3D = main.get("player")
	if frame == START - 60:
		var hud: Node = main.get("hud")
		if hud:
			hud.visible = false
		root.get_node("WorldSim").set("time_of_day", float(spec["hour"]))
		cam = Camera3D.new()
		cam.far = 4000.0
		cam.fov = 62.0
		(main.get("world") as Node3D).add_child(cam)
		cam.current = true
		player.visible = false
		main.call("_teleport", pts[0], 0.0)
	if frame >= START:
		dist += float(spec["speed"]) / 30.0
	var p := _at(dist)
	root.get_node("WorldSim").set("time_of_day", float(spec["hour"]))
	player.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 0.3, p.y)
	var region: Node = main.get("region")
	if region:
		region.set("focus", player.global_position)
	var ahead := _at(dist + 30.0)
	var lk: Vector2 = spec["look"]  if spec["look"] is Vector2 else Vector2(float(spec["look"][0]), float(spec["look"][1]))
	var k := clampf(dist / total, 0.0, 1.0)
	var target2 := ahead.lerp(lk, 0.35 + 0.65 * k)
	var ty := lerpf(WorldGen.height(ahead.x, ahead.y) + 2.0, WorldGen.height(lk.x, lk.y) + float(spec["look_up"]), 0.35 + 0.65 * k)
	var eye := Vector3(p.x, WorldGen.height(p.x, p.y) + float(spec["up"]) + 0.08 * sin(dist * 1.9), p.y)
	cam.global_position = eye
	cam.look_at(Vector3(target2.x, ty, target2.y))
	if dist >= total:
		print("WALK DONE frames ", frame)
		quit(0)
		return true
	return false
