extends SceneTree
## Dungeon tower screenshots (bootstrap; the logic is tower_shots_run.gd, loaded at runtime so autoloads exist).
##   Godot --path kingdom --rendering-driver vulkan --resolution 1280x720 -s res://tools_qa/towers/tower_shots.gd -- \
##       --adult --out=/tmp/claude-0/shots/towers --only=spire_kingsreach,camp
## Views: spire_kingsreach spire_mid spire_far door camp floor_1..floor_6 safe boss banner teleport map


func _initialize() -> void:
	var n: Node = (load("res://tools_qa/towers/tower_shots_run.gd") as GDScript).new()
	root.add_child.call_deferred(n)
