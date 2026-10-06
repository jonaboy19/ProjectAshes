extends SceneTree
## Headless lint of the town kit's hand-placed props in all 30 towns (see kit_lint.gd).
##   $G --headless --path . -s res://tools_qa/lint_world/kit_lint_cli.gd -- [--seed=1066] [--towns=a,b] [--out=/path/kit.txt] [--draws]
## Exit code 1 on any SEVERE issue. kit_lint.gd is loaded at runtime (autoloads do not exist while a `-s` script compiles).


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	WorldGen.setup(int(args.get("seed", 1066)))
	var lint = load("res://tools_qa/lint_world/kit_lint.gd").new()
	var only: Array = Array(String(args.get("towns", "")).split(",", false))
	lint.run(root if args.has("draws") else null, only)
	var text: String = lint.text()
	print(text)
	if args.has("out"):
		var f := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
			f.close()
	quit(1 if lint.count("severe") > 0 else 0)
