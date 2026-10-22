class_name GroundItem
extends Node3D
## An item lying in the world: "Take" puts it in Life.inventory and removes the node.
## Optional owner (meta "owner", also in the `taken` signal). Taking something owned by somebody else is theft
## (scripts/sim/ownership.gd, theft.gd): the verb reads "Steal", the item is flagged stolen and a witness check runs.
## Taken items stay taken across saves (WorldState delta "taken" under the stable id).

signal taken(item_id: String, qty: int, owner_id: String)

var item_id := ""
var qty := 1
var owner_id := "":
	set(v):
		owner_id = v
		set_meta("owner", v)
var _gone := false

const Ownership := preload("res://scripts/sim/ownership.gd")
const Theft := preload("res://scripts/sim/theft.gd")


## Drops `qty` of `item` at `pos` (global) under `parent`.
static func spawn(parent: Node, pos: Vector3, item: String, count := 1, owner := "") -> GroundItem:
	var g := GroundItem.new()
	g.item_id = item
	g.qty = maxi(count, 1)
	g.owner_id = owner
	g.name = "Ground_%s" % item
	parent.add_child(g)
	g.global_position = pos
	g._apply_saved()
	return g


func _ready() -> void:
	_build_visual()
	Interactable.attach(self, {"id_fn": _id,
		"verb": "Take", "range": 2.6, "can": func(_p: Node) -> bool: return not _gone,
		"do": func(p: Node) -> void: take(p),
		"label": func() -> Dictionary: return {"verb": Theft.verb_for(_owner()), "target": _display()}})


## Explicit owner, else the building the item lies in (meta "building_owner" on the room), else public.
func _owner() -> String:
	return owner_id if owner_id != "" else Ownership.owner_of(self)


func _id() -> String:
	return "ground/%s/%d_%d" % [item_id, roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)]


## A saved "taken" removes the node silently (no message, no signal).
func _apply_saved() -> void:
	if Ownership.state_taken(_id()):
		_gone = true
		queue_free()


func _display() -> String:
	var n := Life.item_name(item_id)
	return "%s ×%d" % [n, qty] if qty > 1 else n


## Gives the stack to the player. False when it is already gone.
func take(_player: Node = null) -> bool:
	if _gone or item_id == "":
		return false
	_gone = true
	var verb := "take"
	var who := _owner()
	if Ownership.is_theft(who):
		verb = "steal"
		var at := Vector2(global_position.x, global_position.z)
		Theft.steal(get_tree(), who, item_id, qty, "ground", at, Theft.sid_at(at))
	else:
		Life.give(item_id, qty)
	Ownership.mark_taken(_id())
	taken.emit(item_id, qty, who)
	Game.say("You %s %s." % [verb, _display()])
	queue_free()
	return true


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.12, 0.16)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.55, 0.32)
	m.roughness = 0.9
	mi.material_override = m
	mi.position.y = 0.06
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
