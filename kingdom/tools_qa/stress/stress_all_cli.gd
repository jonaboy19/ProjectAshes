extends Node
## godot --headless --path kingdom res://tools_qa/stress/stress_all_cli.tscn [-- --hours=48]
## Prints one STRESS_JSON line (the stress_all.gd report) and a per-module table, then quits. A scene, not `-s`: the autoloads
## (WorldSim, Life) only compile in order when the project boots normally.

func _ready() -> void:
	var hours := 48
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hours="):
			hours = int(a.get_slice("=", 1))
	var rep: Dictionary = preload("res://tools_qa/stress/stress_all.gd").run(hours)
	print("STRESS_JSON ", JSON.stringify(rep))
	for r: Dictionary in rep.get("per_module", []):
		print("  %-16s %8.2f ms" % [r["module"], r["ms"]])
	print("STRESS avg %.3f ms/busy frame worst %.3f ms (budget %.1f)" % [float(rep.get("avg_ms", -1.0)), float(rep.get("worst_ms", -1.0)), 4.0])
	get_tree().quit(0)
