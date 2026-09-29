extends Node
## Waits until the world in main.tscn is up (player exists, HUD loading veil gone),
## then loads the chosen save slot into it and removes itself.

var slot_id := ""
var _t := 0.0
var _poll := 0.0


func _process(delta: float) -> void:
	_t += delta
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	if _t > 180.0:
		queue_free()
		return
	var life := get_node_or_null("/root/Life")
	if life == null:
		return
	var p: Variant = life.get("player")
	if not is_instance_valid(p) or not (p is Node3D) or not (p as Node3D).is_inside_tree():
		return
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	if hud == null or not is_instance_valid(hud):
		return
	var veil: Variant = (hud as Object).get("_loading")
	if is_instance_valid(veil) and veil is CanvasItem and (veil as CanvasItem).visible:
		return
	# Let the first frames settle (birth cutscene / spawn) before restoring.
	if _t < 2.0:
		return
	if not life.saves.load_slot(slot_id):
		push_warning("[boot] could not load %s: %s" % [slot_id, life.saves.last_error])
	const Flow := preload("res://scripts/ui/frontend/flow.gd")
	Flow.pending_load = ""
	queue_free()
