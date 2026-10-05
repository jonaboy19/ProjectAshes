extends "res://scripts/world/home_chest.gd"
## A crate, barrel or cupboard anyone can "Open": the home chest's storage menu (HomeChest._menu through
## hud.show_menu, including its lock handling via `lock_id`) over an in-world list of stacks instead of a
## property's storage. Contents are rolled once from the container id (`roll_contents`) so they are the same
## every visit; withdrawing and depositing go through Life like the home chest does.
## Ownership (scripts/sim/ownership.gd): the container's own meta "owner", else the building it stands in (meta
## "building_owner" on the room). Withdrawing from somebody else's container is a burglary: the rows read "Steal", the
## goods are flagged stolen and a witness check runs (scripts/sim/theft.gd). Contents and the opened flag persist as
## a WorldState delta under "container/<id>".

const Ownership_ := preload("res://scripts/sim/ownership.gd")
const Theft_ := preload("res://scripts/sim/theft.gd")

const KIND_NAMES := ["Crate", "Barrel", "Cupboard"]

var container_id := ""
var title := "Crate"
## [{item, qty}, ...]
var contents: Array = []
var capacity := 12


## Spawns a container at `pos` (global). Empty `stacks` rolls the contents from the id.
static func spawn(parent: Node, pos: Vector3, id: String, label := "Crate", stacks: Array = [], lock := "", owner := "") -> Node3D:
	var c: Node3D = (load("res://scripts/interaction/kinds/container.gd") as GDScript).new()
	c.set("container_id", id)
	c.set("title", label)
	c.set("contents", stacks.duplicate(true) if not stacks.is_empty() else roll_contents(id))
	c.set("lock_id", lock)
	c.name = "Container_" + id.replace("/", "_")
	if owner != "":
		c.set_meta("owner", owner)
	parent.add_child(c)
	c.global_position = pos
	return c


## Deterministic small stock for a container id.
static func roll_contents(id: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["container", id])
	var pool := [["bread", 1, 3], ["apple", 1, 4], ["torch", 1, 2], ["rope", 1, 1], ["candle", 1, 3]]
	var out: Array = []
	for e: Array in pool:
		if rng.randf() < 0.5:
			out.append({"item": String(e[0]), "qty": rng.randi_range(int(e[1]), int(e[2]))})
	if out.is_empty():
		out.append({"item": "bread", "qty": 1})
	return out


func _ready() -> void:
	super()
	_build_visual()
	var st := Ownership_.container_state(_interact_id())
	if st["contents"] is Array:
		contents = (st["contents"] as Array).duplicate(true)


## Who owns what is inside (explicit meta, else the building).
func owner_key() -> String:
	return Ownership_.owner_of(self)


func _menu() -> Dictionary:
	if not bool(Ownership_.container_state(_interact_id())["opened"]):
		Ownership_.save_container(_interact_id(), contents)
	var m := super()
	if Ownership_.is_theft(owner_key()):
		for o: Array in m["options"]:
			if String(o[0]).begins_with("Withdraw "):
				o[0] = "Steal " + String(o[0]).trim_prefix("Withdraw ")
	return m


func _interact_id() -> String:
	return "container/%s" % container_id


func prompt() -> String:
	return "%s (locked)" % title if lock_id != "" and Locks.is_locked(lock_id) else title


func _stacks() -> Array:
	return contents


func _capacity() -> int:
	return capacity


func _title() -> String:
	return title


## Takes up to `qty` of `item` out of the container into Life.inventory.
func _withdraw(item: String, qty: int) -> String:
	for i in contents.size():
		var st: Dictionary = contents[i]
		if String(st["item"]) != item:
			continue
		var n := mini(qty, int(st["qty"]))
		var who := owner_key()
		var theft := Ownership_.is_theft(who)
		if theft:
			var at := Vector2(global_position.x, global_position.z)
			Theft_.steal(get_tree(), who, item, n, "container", at, Theft_.sid_at(at))
		else:
			Life.give(item, n)
		if n >= int(st["qty"]):
			contents.remove_at(i)
		else:
			st["qty"] = int(st["qty"]) - n
		Ownership_.save_container(_interact_id(), contents)
		return "You %s %s ×%d." % ["steal" if theft else "take", Life.item_name(item), n]
	return "It is not there any more."


func _deposit(item: String, qty: int) -> String:
	if not Life.take(item, qty):
		return "You do not have that."
	for st: Dictionary in contents:
		if String(st["item"]) == item:
			st["qty"] = int(st["qty"]) + qty
			Ownership_.save_container(_interact_id(), contents)
			return "You put %s ×%d away." % [Life.item_name(item), qty]
	if contents.size() >= capacity:
		Life.give(item, qty)
		return "It is full."
	contents.append({"item": item, "qty": qty})
	Ownership_.save_container(_interact_id(), contents)
	return "You put %s ×%d away." % [Life.item_name(item), qty]


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.55, 0.5)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.3, 0.17)
	m.roughness = 0.95
	mi.material_override = m
	mi.position.y = 0.28
	add_child(mi)
