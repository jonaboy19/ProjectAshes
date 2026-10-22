extends Node
## Runs a SceneTree-style tool script (`extends SceneTree` + `_initialize`) as a Node inside a normal scene, so the
## autoloads (Life, WorldSim, ...) exist. Since the cloud layout (region_sites planners that use Life), WorldGen can no
## longer compile under `godot -s`. Usage (headless is fine for pure-data tools):
##   Godot --headless --path kingdom res://tools_qa/region1/run_tool.tscn -- --tool=res://tools_qa/region1/bake_biome.gd [tool args]


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tool="):
			path = a.substr(7)
	if path == "":
		push_error("run_tool: --tool=res://... missing")
		get_tree().quit(1)
		return
	var src := FileAccess.get_file_as_string(path)
	src = src.replace("extends SceneTree", "extends Node").replace("func _initialize()", "func _ready()")
	src = src.replace("\tquit(", "\tget_tree().quit(").replace(" quit(", " get_tree().quit(").replace("root.", "get_tree().root.")
	var gs := GDScript.new()
	gs.source_code = src
	var err := gs.reload()
	if err != OK:
		push_error("run_tool: %s does not compile as a Node (%d)" % [path, err])
		get_tree().quit(1)
		return
	var n := Node.new()
	n.set_script(gs)
	add_child(n)
