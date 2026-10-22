extends SceneTree
## Headless timing of DistrictProps (town build hitch): see district_build_prof_core.gd (runtime loaded: autoloads/class
## names do not exist while a -s script compiles).
##   $G --headless --path . -s res://tools_qa/districts/district_build_prof.gd -- [--towns=Thornfield,Kingsreach]

func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var towns := ["Thornfield", "Kingsreach"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--towns="):
			towns = a.substr(8).split(",")
	load("res://tools_qa/districts/district_build_prof_core.gd").new().run(self, towns)
	quit(0)
