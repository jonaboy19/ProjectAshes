extends SceneTree
## Headless world linter: floating / sunken / clipping / overlapping / road-blocking props and per-site draw budgets,
## found without rendering anything.
##
##   G=/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64
##   $G --headless --path . -s res://tools_qa/lint_world/world_lint.gd -- [--seed=N] [--sites=all|kind,...] [--out=/path/report.json]
##
## --sites: "all" (default) or a comma list of site kinds (farm, waystone, bandit_camp, bridge, hidden_vale, ...) and of the
##          pseudo groups settlement (or one settlement name), r1look, vale, caves, tower.
## Writes <out> (JSON) and <out without .json>.txt (readable summary), prints the summary, exit code 1 on any non-allowlisted
## SEVERE issue (float > 1 m, building overlap, solid prop on a road).
## Logic lives in lint_core.gd (loaded at runtime: autoloads do not exist yet while a `-s` script compiles); tunables and the
## allowlist in lint_config.gd. See .claude/skills/ashes-world-lint/SKILL.md.

const CORE := "res://tools_qa/lint_world/lint_core.gd"


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame          # the root window is only "inside the tree" from the first frame on
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var seed_v := int(args.get("seed", 1066))
	var sites := String(args.get("sites", "all")).split(",", false)
	var out := String(args.get("out", ProjectSettings.globalize_path("user://world_lint_report.json")))
	var core = load(CORE).new()
	core.run(self, seed_v, Array(sites))
	var text: String = core.text_report(15)
	core.restore()
	print(text)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(core.to_dict(), "\t"))
		f.close()
	var tp := out.get_basename() + ".txt"
	var ft := FileAccess.open(tp, FileAccess.WRITE)
	if ft != null:
		ft.store_string(text + "\n")
		ft.close()
	print("world_lint: wrote %s and %s" % [out, tp])
	quit(1 if core.count_sev("severe") > 0 else 0)
