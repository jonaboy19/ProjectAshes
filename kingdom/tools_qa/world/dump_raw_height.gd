extends SceneTree
## Dumps WorldGen._raw_height (the noise height BEFORE settlement/road/river shaping) around the two cores the
## macro heightmap must keep (Ashford, Kingsreach). Output feeds tools/world/gen_valencious.py (hold zones).
##   Godot --headless --path kingdom -s res://tools_qa/world/dump_raw_height.gd -- --out=<file.json>
## Run with --world_macro=noise (default) so the numbers are the legacy noise terrain.

const WINDOWS := [["ashford", 0.0, 0.0], ["kingsreach", 560.0, -420.0]]
const HALF := 1700.0
const STEP := 16.0


func _initialize() -> void:
	var out := "user://raw_core.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	WorldGen.setup(1066)
	var wins := []
	var n := int(2.0 * HALF / STEP) + 1
	for w in WINDOWS:
		var cx: float = w[1]
		var cz: float = w[2]
		var vals := []
		for j in n:
			for i in n:
				vals.append(int(round(WorldGen._raw_height(cx - HALF + i * STEP, cz - HALF + j * STEP) * 10.0)))
		wins.append({"name": w[0], "cx": cx, "cz": cz, "half": HALF, "step": STEP, "n": n, "h_x10": vals})
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": 1066, "note": "WorldGen._raw_height * 10, row-major, x east, z south, origin = (cx-half, cz-half)", "windows": wins}))
	f.close()
	print("DUMPED raw core ", wins.size(), " windows of ", n, "x", n)
	quit(0)
