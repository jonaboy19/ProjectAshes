extends SceneTree
## Item UI screenshots (bootstrap; logic in items_shots_run.gd so autoloads exist when it compiles). Run under xvfb, never --headless:
##   xvfb-run -a -s "-screen 0 1280x720x24" Godot --path kingdom --rendering-driver opengl3 --resolution 1280x720 \
##       -s res://tools_qa/items/items_shots.gd -- --out=/tmp/claude-0/shots/items


func _initialize() -> void:
	var n: Node = (load("res://tools_qa/items/items_shots_run.gd") as GDScript).new()
	root.add_child.call_deferred(n)
