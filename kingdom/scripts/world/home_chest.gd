extends Node3D
## A property's storage chest: self-contained like scripts/world/fishing_spot.gd,
## an Interactable (scripts/interaction/interactable.gd) with prompt() and use(). Spawned by
## scripts/world/village_services.gd inside a property's interior (on the
## interior's "StorageMarker" if the scene has one, else a fixed offset from
## "PlayerSpawn"), it opens a simple deposit/withdraw menu on Life.property's
## chest for that lot via hud.show_menu.
##
## The interact key reaches use() through the player's InteractionController,
## like every other interactable.

const RAProperty := preload("res://scripts/sim/property.gd")
const Locks := preload("res://scripts/world/locks.gd")

## The lot_id this chest belongs to (scripts/sim/property.gd).
var lot_id := ""
## Optional shared lock (scripts/world/locks.gd): doors, chests and gates naming the same lock_id share one key.
var lock_id := ""

var _last_use_frame := -100
var _ic: Interactable


func _ready() -> void:
	_ic = Interactable.attach(self, {"id_fn": _interact_id, "verb": "Open", "target": "Storage chest",
		"range": 3.3, "do": func(_p: Node) -> void: use(),
		"label": func() -> Dictionary:
			return {"verb": "Open", "target": prompt()}})


## Stable interactable id (overridden by scripts/interaction/kinds/container.gd).
func _interact_id() -> String:
	return "home_chest/%s" % lot_id


func prompt() -> String:
	return "Storage chest (locked)" if lock_id != "" and Locks.is_locked(lock_id) else "Storage chest"


func use() -> void:
	var f := Engine.get_process_frames()
	if f - _last_use_frame < 2:
		return
	_last_use_frame = f
	if lock_id != "" and Locks.is_locked(lock_id):
		var h := Locks.player_holder()
		if not Locks.unlock(lock_id, h) and not bool(Locks.try_pick(lock_id, h).get("ok", false)):
			var g := get_node_or_null("/root/Game")
			if g != null and g.has_method("say"):
				g.call("say", "It is locked.")
			return
	var hud := _hud()
	if hud != null:
		hud.call("show_menu", _menu)


## The storage UI (hud.show_menu dictionary). The stack list, capacity, title and the withdraw / deposit
## actions are small virtuals so other containers (kinds/container.gd) reuse this same menu.
func _menu() -> Dictionary:
	var lines := PackedStringArray()
	var opts: Array = []
	var stacks: Array = _stacks()
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
	lines.append("\n%d / %d chest slots used." % [stacks.size(), _capacity()])
	return {"title": _title(), "body": "\n".join(lines), "options": opts}


func _stacks() -> Array:
	return Life.property.storage_of(lot_id)


func _capacity() -> int:
	return Life.property.storage_capacity(lot_id)


func _title() -> String:
	return "Storage — %s" % String(Life.property.info(lot_id).get("name", "Home"))


func _withdraw(item: String, qty: int) -> String:
	return Life.property.withdraw(lot_id, item, qty)


func _deposit(item: String, qty: int) -> String:
	return Life.property.deposit(lot_id, item, qty)


func _hud() -> Node:
	var scene := get_tree().current_scene
	var h: Variant = scene.get("hud") if scene else null
	return h if h is Object and is_instance_valid(h) else null
