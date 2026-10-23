extends SceneTree
## Prints ground + water level on a grid around --at=x,z (default the Rift) for the current --world_macro mode.
func _initialize() -> void:
	WorldGen.setup(1066)
	var c := Vector2(1100, 960)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			c = Vector2(float(p[0]), float(p[1]))
	print("MODE ", WorldMacro.mode(), " lake ", WorldGen.lake_center, " lvl ", WorldGen.lake_level)
	for j in range(-6, 7):
		var row := ""
		for i in range(-6, 7):
			var x := c.x + i * 25.0
			var z := c.y + j * 25.0
			var lv := WorldGen.water_level_at(x, z)
			row += "%4.0f%s " % [WorldGen.height(x, z), "~" if not is_nan(lv) else " "]
		print("z=%5.0f %s" % [c.y + j * 25.0, row])
	quit(0)
