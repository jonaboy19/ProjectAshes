class_name InteractionController
extends Node
## Child of the Player: the ONE place the "interact" action is handled. A tap runs the chosen candidate
## (Interaction.activate); a candidate with hold_time > 0 is run once the button has been held that long
## while it stays the chosen one, and reports progress through its Interactable's hold_* signals.
## While a menu is open the key is left alone, so main.gd can close the menu.

var player: Node3D
var _hold: Interactable = null
var _held := 0.0


func _ready() -> void:
	player = get_parent() as Node3D
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not event.is_action_pressed("interact") or event.is_echo():
		return
	if _menu_open():
		return
	if bool(player.get("dead")):
		return
	var c := Interaction.best(player)
	if c.is_empty():
		return
	var ht := float(c.get("hold_time", 0.0))
	var src: Variant = c.get("source", null)
	if ht > 0.0 and src is Interactable:
		_begin_hold(src as Interactable)
	else:
		Interaction.run(c, player)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _hold == null or not is_instance_valid(_hold):
		_end_hold(false)
		return
	var still := Input.is_action_pressed("interact") and not _menu_open() and not bool(player.get("dead"))
	if still:
		var c := Interaction.best(player)
		still = c.get("source", null) == _hold
	if not still:
		_end_hold(false)
		return
	_held += delta
	_hold.hold_progress.emit(player, clampf(_held / _hold.hold_time, 0.0, 1.0))
	if _held >= _hold.hold_time:
		var h := _hold
		_end_hold(true)
		if h.can_interact(player):
			h.interact(player)


func holding() -> Interactable:
	return _hold


func _begin_hold(c: Interactable) -> void:
	_hold = c
	_held = 0.0
	set_process(true)
	c.hold_started.emit(player)


func _end_hold(finished: bool) -> void:
	var h := _hold
	_hold = null
	_held = 0.0
	set_process(false)
	if h != null and is_instance_valid(h) and not finished:
		h.hold_cancelled.emit(player)


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
		and bool((hud as Object).call("is_menu_open"))
