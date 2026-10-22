extends Node
## Ticks GuardLantern.update at 4 Hz around the player (or the camera). Created once by GuardLantern.attach.

const GuardLantern := preload("res://scripts/population/guard_lantern.gd")

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	var focus := Vector3.ZERO
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		focus = p.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			focus = cam.global_position
	GuardLantern.update(get_tree(), focus, WorldSim.time_of_day)
