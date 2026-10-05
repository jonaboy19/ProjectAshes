extends Node
## Keeps the world's SquadSoldier bodies in step with the soldier module's squad (scripts/sim/soldier_squad.gd):
## one body per living member while the player serves as corporal or above, none otherwise. Add one to the
## scene with SquadManager.attach(parent) (Captain does, once). Checks twice a second; replacements and healed
## soldiers appear next to the leader.

const Body := preload("res://scripts/actors/squad_soldier.gd")
const CHECK := 0.5

var _acc := 0.0


static func attach(parent: Node) -> Node:
	var existing := parent.get_node_or_null("SquadManager")
	if existing != null:
		return existing
	var m: Node = (load("res://scripts/actors/squad_manager.gd") as GDScript).new()
	m.name = "SquadManager"
	parent.add_child(m)
	return m


func _module() -> RefCounted:
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod("soldier") if hub != null else null


func _process(delta: float) -> void:
	_acc += delta
	if _acc < CHECK:
		return
	_acc = 0.0
	var m := _module()
	var leader := get_tree().get_first_node_in_group("player") as Node3D
	var bodies := {}
	for n: Node in get_tree().get_nodes_in_group("squad_soldier"):
		bodies[String(n.get("member_id"))] = n
	var want := {}
	if m != null and leader != null and bool(m.call("has_squad")):
		for mem: Dictionary in m.squad.members:
			if String(mem["state"]) != "dead":
				want[String(mem["id"])] = mem
	for id: String in bodies:
		if not want.has(id):
			(bodies[id] as Node).queue_free()
	for id: String in want:
		if not bodies.has(id):
			var b: Node3D = Body.new()
			b.call("setup", m, id, leader)
			get_parent().add_child(b)
			var p := leader.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(2.0, 4.0))
			b.global_position = Vector3(p.x, WorldGen.height(p.x, p.z), p.z)
