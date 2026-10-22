extends SceneTree
## Standalone world-spot renders without booting the whole game (about 2 GB instead of 4.5 GB+): WorldGen.setup, a RegionDressing node that
## streams the sites around its `focus`, a Region1Look child for the hand-placed landmarks, a terrain patch under each view, Style G sun/environment.
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver vulkan --resolution 1280x720 -s res://tools_qa/asset_use/site_shots.gd \
##       -- --views=res://tools_qa/asset_use/asset_use_views.json --out=/tmp/claude-0/shots/asset_use [--only=01_x,02_y]
## Never --headless. The logic lives in site_shots_core.gd (loaded at runtime: WorldGen does not exist yet while a `-s` script compiles).


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var core: RefCounted = load("res://tools_qa/asset_use/site_shots_core.gd").new()
	await core.run(self, args)
	quit(0)
