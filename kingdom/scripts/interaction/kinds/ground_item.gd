class_name GroundItem
extends Node3D
## An item lying in the world: "Take" puts it in Life.inventory and removes the node.
## Optional owner (meta "owner", also in the `taken` signal) so a later theft rule can treat taking someone's
## belongings as a crime; nothing here enforces it yet.

signal taken(item_id: String, qty: int, owner_id: String)

var item_id := ""
var qty := 1
var owner_id := "":
	set(v):
		owner_id = v
		set_meta("owner", v)
var _gone := false


## Drops `qty` of `item` at `pos` (global) under `parent`.
static func spawn(parent: Node, pos: Vector3, item: String, count := 1, owner := "") -> GroundItem:
	var g := GroundItem.new()
	g.item_id = item
	g.qty = maxi(count, 1)
	g.owner_id = owner
	g.name = "Ground_%s" % item
	parent.add_child(g)
	g.global_position = pos
	return g


func _ready() -> void:
	_build_visual()
	Interactable.attach(self, {"id_fn": func() -> String: return "ground/%s/%d_%d" % [item_id, roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)],
		"verb": "Take", "range": 2.6, "can": func(_p: Node) -> bool: return not _gone,
		"do": func(p: Node) -> void: take(p),
		"label": func() -> Dictionary: return {"verb": "Take", "target": _display()}})


func _display() -> String:
	var n := Life.item_name(item_id)
	return "%s ×%d" % [n, qty] if qty > 1 else n


## Gives the stack to the player. False when it is already gone.
func take(_player: Node = null) -> bool:
	if _gone or item_id == "":
		return false
	_gone = true
	Life.give(item_id, qty)
	taken.emit(item_id, qty, owner_id)
	Game.say("You take %s." % _display())
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
