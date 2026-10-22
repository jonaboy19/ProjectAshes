extends RefCounted
## Demo placement of every interaction kind inside the Golden Stag-style inn (scenes/interiors/inn_interior.tscn),
## so each can be seen and used in a normal playthrough. Coordinates are the room's local frame, chosen from the
## scene's collider boxes (free floor: the fire hearth corner, the west wall, and the east end of table 2).
## Called from village_services._on_interior_entered; the props are children of the room, so they vanish with it.

const Seat_ := preload("res://scripts/interaction/kinds/seat.gd")
const Container_ := preload("res://scripts/interaction/kinds/container.gd")

const ROOT := "InteractionProps"


static func is_inn(room: Node3D) -> bool:
	return room != null and String(room.scene_file_path).contains("inn_interior")


## Adds the demo props once. Returns the node holding them (null when this is not the inn).
static func populate(room: Node3D) -> Node3D:
	if not is_inn(room):
		return null
	var existing := room.get_node_or_null(ROOT) as Node3D
	if existing != null:
		return existing
	var root := Node3D.new()
	root.name = ROOT
	room.add_child(root)
	root.position = Vector3.ZERO
	var at := func(p: Vector3) -> Vector3: return room.to_global(p)
	# Sit: a bench in front of the hearth, facing the fire (-Z).
	Seat_.spawn(root, at.call(Vector3(-3.2, 0.0, -3.5)), room.global_rotation.y + PI, "bench")
	# Open: a crate in the north-west corner.
	Container_.spawn(root, at.call(Vector3(-5.3, 0.0, -4.4)), "inn/crate/1", "Cellar crate")
	# Take: a loaf left on the nearest table.
	GroundItem.spawn(root, at.call(Vector3(0.2, 0.66, 1.21)), "bread", 1)
	# Search: a fallen traveller by the west wall.
	var body := Node3D.new()
	body.name = "FallenTraveller"
	root.add_child(body)
	body.global_position = at.call(Vector3(-5.3, 0.12, -0.2))
	body.rotation.z = PI * 0.5
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.7
	mi.mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.3, 0.28)
	mi.material_override = m
	body.add_child(mi)
	CorpseLoot.attach(body, "inn/fallen_traveller")
	# Climb: a ladder to the upstairs floor along the west wall.
	Ladder.spawn(root, at.call(Vector3(-5.55, 0.0, 0.9)), at.call(Vector3(-5.2, 4.1, 0.9)))
	# Pull: a lever on the west wall that rattles the shutters (just a message for now).
	var lv := Lever.spawn(root, at.call(Vector3(-5.85, 1.3, -2.6)), "inn/cellar", room.global_rotation.y + PI * 0.5)
	lv.on_pull = func(on: bool) -> void:
		Game.say("Somewhere below, a latch %s." % ("lifts" if on else "drops"))
	return root
