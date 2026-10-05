extends SceneTree
## Headless probe of the planned world (WorldGen.setup, no rendering): prints sites matching --kind= / --name=, and with --crossings
## the narrow water crossings found near every settlement (3-9 m of water between two dry banks), for footbridge placement.
##   Godot --headless --path kingdom -s res://tools_qa/asset_use/probe_world.gd -- [--seed=1066] [--kind=bridge] [--name=Row] [--crossings]
## The logic lives in probe_core.gd (loaded at runtime: WorldGen does not exist yet while a `-s` script compiles).


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	load("res://tools_qa/asset_use/probe_core.gd").new().run(args)
	quit(0)
