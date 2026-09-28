extends Node3D
## A property's storage chest: self-contained like scripts/world/fishing_spot.gd,
## always in the "interactable" group with prompt() and use(). Spawned by
## scripts/world/village_services.gd inside a property's interior (on the
## interior's "StorageMarker" if the scene has one, else a fixed offset from
## "PlayerSpawn"), it opens a simple deposit/withdraw menu on Life.property's
## chest for that lot via hud.show_menu.
##
## Self-dispatches the interact key while it is the player's nearest
## interactable, the same way fishing_spot.gd does (main.gd's own interact
## dispatch only knows about a fixed set of node types).

const RAProperty := preload("res://scripts/sim/property.gd")

## The lot_id this chest belongs to (scripts/sim/property.gd).
var lot_id := ""

var _last_use_frame := -100
var _menu_was_open := false


func _ready() -> void:
	add_to_group("interactable")


func prompt() -> String:
	return "Storage chest"


func use() -> void:
	var f := Engine.get_process_frames()
	if f - _last_use_frame < 2:
		return
	_last_use_frame = f
	var hud := _hud()
	if hud != null:
		hud.call("show_menu", _menu)


func _process(_delta: float) -> void:
	_poll_interact()


func _menu() -> Dictionary:
	var prop: RAProperty = Life.property
	var i: Dictionary = prop.info(lot_id)
	var lines := PackedStringArray()
	var opts: Array = []
	var stacks: Array = prop.storage_of(lot_id)
	for st: Dictionary in stacks:
		var item := String(st["item"])
		var qty := int(st["qty"])
		lines.append("%s ×%d" % [Life.item_name(item), qty])
		opts.append(["Withdraw %s ×%d" % [Life.item_name(item), qty], _withdraw.bind(item, qty)])
	if lines.is_empty():
		lines.append("Empty.")
	var seen := {}
	for it in Life.inventory.get_items():
		var id := it.get_prototype().get_prototype_id()
		if seen.has(id):
			continue
		seen[id] = true
		var n := Life.count(id)
		if n > 0:
			opts.append(["Deposit %s ×%d" % [Life.item_name(id), n], _deposit.bind(id, n)])
	lines.append("\n%d / %d chest slots used." % [stacks.size(), prop.storage_capacity(lot_id)])
	return {"title": "Storage — %s" % String(i.get("name", "Home")), "body": "\n".join(lines), "options": opts}


func _withdraw(item: String, qty: int) -> String:
	return Life.property.withdraw(lot_id, item, qty)


func _deposit(item: String, qty: int) -> String:
	return Life.property.deposit(lot_id, item, qty)


func _hud() -> Node:
	var scene := get_tree().current_scene
	var h: Variant = scene.get("hud") if scene else null
	return h if h is Object and is_instance_valid(h) else null


func _menu_open() -> bool:
	var hud := _hud()
	return hud != null and hud.has_method("is_menu_open") and bool(hud.call("is_menu_open"))


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _poll_interact() -> void:
	var p := _player()
	if p == null or p.global_position.distance_squared_to(global_position) > 3.3 * 3.3:
		_menu_was_open = false
		return
	var menu_open := _menu_open()
	var was := _menu_was_open
	_menu_was_open = menu_open
	if menu_open or was or not Input.is_action_just_pressed("interact"):
		return
	if p.has_method("nearest_interactable") and p.call("nearest_interactable") == self:
		use()
