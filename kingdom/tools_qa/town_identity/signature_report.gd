extends SceneTree
## Headless "town signature" report: every settlement's visual identity profile and a pairwise distinctness score.
##   $G --headless --path . -s res://tools_qa/town_identity/signature_report.gd -- [--seed=1066] [--out=/tmp/x/town_signatures] [--threshold=0.2] [--legacy]
## Writes <out>.txt (table) and <out>.json, prints the table. Exit code 1 when any pair is closer than the threshold.
## Logic loads at runtime (autoloads and class names do not exist while a -s script compiles).

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var code: int = load("res://tools_qa/town_identity/signature_core.gd").new().run(int(args.get("seed", "1066")), String(args.get("out", "/tmp/claude-0/townid/town_signatures")), float(args.get("threshold", "0.2")), args.has("legacy"))
	quit(code)
