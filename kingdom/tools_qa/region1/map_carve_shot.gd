extends SceneTree
## Item 3 QA: boot the real game, carve a ward glyph on a dim-free stone near the player, open the world
## map zoomed on it, save before/after PNGs (the teal rim from r1_map_layer.gd must show up).
##   Godot --path kingdom --resolution 1600x900 -s res://tools_qa/region1/map_carve_shot.gd -- --adult --out=<abs dir>
var out_dir := ""
var main: Node
var frame := 0
var sf := 0
var t0 := 0
var step := 0
var stone := -1
var wl: Object


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	t0 = Time.get_ticks_msec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(main)


func _shot(name: String) -> void:
	var p := "%s/%s.png" % [out_dir, name]
	root.get_viewport().get_texture().get_image().save_png(p)
	print("SAVED ", p)


func _process(_dt: float) -> bool:
	frame += 1
	sf += 1
	if Time.get_ticks_msec() - t0 > 800000:
		print("WATCHDOG")
		quit(1)
		return true
	if frame < 500:
		return false
	var hud: Node = main.get("hud")
	var wm: Control = hud.get("world_map")
	if step == 0:
		wl = Region1State.sim(&"wardlines")
		print("wardlines sim: ", wl != null)
		if wl == null:
			quit(2)
			return true
		var pp: Vector3 = (main.get("player") as Node3D).global_position
		var me := Vector2(pp.x, pp.z)
		# nearest stone that is carvable right now
		var best := -1
		var bd := 1e18
		for i in wl.n:
			if wl.elder_of[i] >= 0 or wl.supplier[i] < 0 or wl.glyph[i] != 0:
				continue
			var d: float = me.distance_to(wl.st_pos[i])
			if d < bd:
				bd = d
				best = i
		stone = best
		print("stone ", stone, " at ", wl.st_pos[stone] if stone >= 0 else "none", " charge ", wl.charge[stone])
		if stone < 0:
			quit(3)
			return true
		main.call("_teleport", wl.st_pos[stone] + Vector2(6, 6), 0.0)
		step = 1
		sf = 0
		return false
	if sf % 60 == 0:
		print("[mc] step ", step, " sf ", sf, " t=", (Time.get_ticks_msec() - t0) / 1000)
	if step == 1 and sf == 120:
		wm.open()
		wm.focus_on(wl.st_pos[stone], 0.9)
		step = 2
		sf = 0
	elif step == 2 and sf == 60:
		_shot("map_before_carve")
		wm.close()
		var res: Dictionary = wl.carve(stone, "ward")
		print("carve -> ", res)
		step = 3
		sf = 0
	elif step == 3 and sf == 30:
		wm.open()
		wm.focus_on(wl.st_pos[stone], 0.9)
		step = 4
		sf = 0
	elif step == 4 and sf == 60:
		_shot("map_after_carve")
		wm.focus_on(wl.st_pos[stone], 0.3)
		step = 5
		sf = 0
	elif step == 5 and sf == 40:
		_shot("map_after_carve_wide")
		quit(0)
		return true
	return false
