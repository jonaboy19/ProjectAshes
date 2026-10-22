extends SceneTree
## Prints WorldGen.height transects across Hollin's Reach (W1c fit) for the current --world_macro mode.
##   Godot --headless --path kingdom -s res://tools_qa/world/fit_probe.gd -- --world_macro=valencious
func _initialize() -> void:
	WorldGen.setup(1066)
	print("MODE ", WorldMacro.mode(), " active ", WorldMacro.active)
	for z in [-900.0, -780.0, -660.0, -540.0, -470.0]:
		var row := ""
		var lo := 1.0e9
		var hi := -1.0e9
		for i in 21:
			var x := -520.0 + i * 30.0
			var h := WorldGen.height(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			row += "%4.0f " % h
		print("z=%5.0f relief %5.1f  %s" % [z, hi - lo, row])
	var r: Dictionary = WorldGen.rivers[0]
	var pts: PackedVector2Array = r["points"]
	var lv: PackedFloat32Array = r["level"]
	print("river0 start level %.1f ground %.1f ; at 40 %.1f ground %.1f ; end(lake) %.1f" % [lv[0], WorldGen.height(pts[0].x, pts[0].y), lv[40], WorldGen.height(pts[40].x, pts[40].y), lv[lv.size() - 1]])
	print("lake level %.2f centre ground %.2f" % [WorldGen.lake_level, WorldGen.height(WorldGen.lake_center.x, WorldGen.lake_center.y)])
	quit(0)
