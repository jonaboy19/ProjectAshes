class_name Interactable
extends Area3D
## Something the player can use: talk to an NPC, ring a bell, open a door.
## Add as a child of the object, give it a shape via make(), connect `interacted`.

signal interacted(by: Node)

const LAYER := 8

@export var prompt := "Talk"
var enabled := true


static func make(prompt_text: String, radius := 1.2) -> Interactable:
	var area := Interactable.new()
	area.prompt = prompt_text
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position.y = 1.0
	area.add_child(shape)
	return area


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func interact(by: Node) -> void:
	if enabled:
		interacted.emit(by)
