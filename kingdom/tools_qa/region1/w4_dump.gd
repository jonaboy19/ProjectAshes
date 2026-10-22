extends SceneTree
## W4 QA: prints every WorldGen site (name, kind, pos, yaw, clear, ground height, slope) as JSON lines "SITE {...}".
##   Godot --headless --path kingdom -s res://tools_qa/region1/w4_dump.gd -- [--out=<abs file>] [--world_macro=valencious]
func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	WorldGen.setup(1066)
	var lines: PackedStringArray = []
	for s: Dictionary in WorldGen.sites:
		var p: Vector2 = s["pos"]
		lines.append(JSON.stringify({"id": s["id"], "r1id": s.get("r1id", ""), "name": s["name"], "kind": s["kind"], "x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1),
			"yaw": snappedf(float(s["yaw"]), 0.001), "clear": s["clear"], "h": snappedf(WorldGen.height(p.x, p.y), 0.01), "parts": s["parts"].size()}))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("SITES ", lines.size())
	quit(0)
