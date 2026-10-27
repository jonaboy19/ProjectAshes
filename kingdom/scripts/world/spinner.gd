extends Node3D
## Towns medieval pass: something that turns (windmill sails, waterwheels). Rotates about its local `axis` at `speed` rad/s while it is
## visible and within `reach` metres of the camera (beyond that the turning cannot be seen). No class_name; preload it.

@export var axis := Vector3.FORWARD
@export var speed := 0.6
@export var reach := 180.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) > reach * reach:
		return
	rotate_object_local(axis, speed * delta)
