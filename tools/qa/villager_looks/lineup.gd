extends SceneTree
## Every villager model the game can pick (Assets.MH_LOOKS, unique files), each shown
## front and back side by side under a plain sun. Catches untextured / faceless looks
## (a hood seen from behind, a cloak the colour of skin, a missing texture).
##   godot --path kingdom --resolution 2400x1840 -s <abs>/tools/qa/villager_looks/lineup.gd -- --png=<file> [--lod1]

const COLS := 7          # characters per row (each takes two slots: front, back)
const SPACING := 0.62
const ROW_H := 2.25
var png := "user://villager_looks.png"
var frames := 0


func _initialize() -> void:
	var lod1 := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
		elif a == "--lod1":
			lod1 = true
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.68)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 15, 0)
	world.add_child(sun)
	var files: Array[String] = []
	for look: String in Assets.MH_LOOKS:
		for f: String in Assets.MH_LOOKS[look]:
			if not files.has(f):
				files.append(f)
	var rows := ceili(files.size() / float(COLS))
	for i in files.size():
		var x := (i % COLS - (COLS - 1) / 2.0) * SPACING * 2.4
		var y := -(i / COLS) * ROW_H
		for side in 2:
			var c := Assets.mh_character(files[i], 1.75, [], lod1)
			world.add_child(c)
			c.position = Vector3(x + (side - 0.5) * SPACING, y, 0)
			c.rotation.y = PI * side
			var anim := Assets.animation_player(c)
			if anim and anim.has_animation("Idle"):
				anim.play("Idle")
		var l := Label3D.new()
		l.text = "%d %s" % [i, files[i].get_file()]
		l.font_size = 28
		l.outline_size = 6
		l.pixel_size = 0.0025
		l.position = Vector3(x, y + 1.9, 0.3)
		world.add_child(l)
		print("LOOK %d %s" % [i, files[i]])
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * ROW_H + 0.2
	cam.position = Vector3(0, 1.05 - (rows - 1) * ROW_H / 2.0, 12)
	world.add_child(cam)
	cam.current = true


func _process(_d: float) -> bool:
	frames += 1
	if frames == 40:
		root.get_texture().get_image().save_png(png)
		print("Saved ", png)
		return true
	return false
