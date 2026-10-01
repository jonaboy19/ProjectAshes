extends Node3D
## One interactable spot of the tower world (door, gate, bonfire, chest, vendor...). Joins the "interactable" group so the
## HUD shows its prompt() on the interact button; tower_site.gd dispatches the press via `action` and `data`.
## Plain data + a prompt: no per-frame work at all.

var action := ""
var label := ""
var data: Dictionary = {}
var enabled := true:
	set(v):
		enabled = v
		_sync()


func _ready() -> void:
	add_to_group("tower_point")
	set_meta("tower_point", true)
	_sync()


func _sync() -> void:
	if not is_inside_tree():
		return
	if enabled and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not enabled and is_in_group("interactable"):
		remove_from_group("interactable")


func prompt() -> String:
	return label
