extends Node
## Perf helper (no class_name): hides a static/idle skinned character and pauses its
## AnimationPlayer once the camera is farther than `range_m` x the tier's visibility-range
## multiplier (LOW 0.55). Checked on a 0.5 s timer, so it costs nothing per frame.
## Usage: DistanceCull.attach(model, 90.0)  ->  const DistanceCull := preload("res://scripts/core/distance_cull.gd")

var target: Node3D
var anim: AnimationPlayer
var range_m := 90.0
var _t := randf() * 0.5
var _hidden := false


static func attach(model: Node3D, range_meters := 90.0, player: AnimationPlayer = null) -> void:
	if model == null:
		return
	var c := (load("res://scripts/core/distance_cull.gd") as GDScript).new() as Node
	c.set("target", model)
	c.set("anim", player)
	c.set("range_m", range_meters)
	model.add_child(c)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or target == null or not target.is_inside_tree():
		return
	_t = 0.5
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var limit := range_m * clampf(float(Quality.value("range")), 0.5, 1.0)
	var d := cam.global_position.distance_to(target.global_position)
	var want := d > limit * (0.9 if _hidden else 1.1)
	if want == _hidden:
		return
	_hidden = want
	target.visible = not want
	if anim:
		anim.active = not want
