extends "res://scripts/interiors/dungeon_door.gd"
## The door into the hand-tuned Rift near Thornfield (F9). A DungeonDoor whose room is the fixed layout of rift_layout.gd
## instead of a generated one: everything the generated dungeons do (the exit door, the lever gate, chests that stay looted,
## creatures that stay dead, the boss and its chest, the carried light) works unchanged, and the persistence is the same
## exploration-module state under the dungeon id "thornfield_rift". After the room is built the camp's quartermaster,
## bedroll (rest + save) and the Rift vents are added (rift_extras.gd).

const RiftLayout := preload("res://scripts/world/thornfield/rift_layout.gd")
const RiftExtras := preload("res://scripts/world/thornfield/rift_extras.gd")

var extras: Dictionary = {}
var data_path := RiftLayout.PATH


func configure_rift() -> void:
	configure_hand(RiftLayout.PATH)


## Configures the door for any hand-tuned layout file (the Rift, the Miner's Nook).
func configure_hand(path: String) -> void:
	data_path = path
	var g := RiftLayout.layout(path)
	configure({"dungeon_id": String(g["id"]), "seed": int(g["seed"]), "theme": String(g["theme"]), "tier": int(g["tier"]),
		"name": String(g["name"]), "rooms": (g["rooms"] as Array).size()})
	prompt_text = "Enter %s  (Lv %d-%d)" % [dname, lvl_min, lvl_max]
	name = "RiftDoor_%s" % dungeon_id


func layout() -> Dictionary:
	return RiftLayout.layout(data_path)


func _make_interior() -> Node3D:
	var root := super()
	if root != null and (layout()["content"] as Dictionary).has("camp"):
		extras = RiftExtras.attach(root, layout())
	return root
