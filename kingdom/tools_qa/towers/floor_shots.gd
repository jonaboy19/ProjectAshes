extends SceneTree
## Standalone floor shots (no main scene): builds floors with FloorGen into a bare world and photographs them.
##   Godot --path kingdom --rendering-driver vulkan --resolution 1280x720 -s res://tools_qa/towers/floor_shots.gd -- --out=DIR [--floors=1,2,3,4,5,6]
## Bootstrap; the logic is floor_shots_run.gd (a Node loaded at runtime so autoloads exist).

func _initialize() -> void:
	var n: Node = (load("res://tools_qa/towers/floor_shots_run.gd") as GDScript).new()
	root.add_child.call_deferred(n)
