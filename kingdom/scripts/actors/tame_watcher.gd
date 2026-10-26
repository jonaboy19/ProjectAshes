class_name TameWatcher
extends Node
## READY_V1 C8: finds beaten wolves and Stagborn near the player and gives them the Calm prompt (TameTarget), keeps the
## hold length in step, and brings tamed beasts that are in the save back into the world when the player is around.
## Child of the follower manager; ticks twice a second. No creature script is edited: creatures are read from the
## "combatant" group.

const SCAN := 0.5
const RANGE := 30.0

var _acc := 0.0


func _physics_process(delta: float) -> void:
	_acc += delta
	if _acc < SCAN:
		return
	_acc = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for n in get_tree().get_nodes_in_group("combatant"):
		var b := n as Node3D
		if b == null or not b.is_inside_tree() or b.global_position.distance_to(player.global_position) > RANGE:
			continue
		if TameTarget.calmable(b):
			TameTarget.attach(b)
			TameTarget.refresh(b)
		else:
			var c := Interactable.component_of(b)
			if c != null and c.id.begins_with("calm/") and c.enabled:
				c.enabled = false
	_respawn(player)


## A tamed beast from the save with no body yet stands up next to the player (follow) or at its post (guard).
func _respawn(player: Node3D) -> void:
	var hub = Life.get("realm") if Life != null else null
	var fm: RefCounted = hub.mod("followers") if hub != null else null
	if fm == null:
		return
	var live := {}
	for n in get_tree().get_nodes_in_group("tamed_pet"):
		live[String(n.get_meta("tamed", ""))] = true
	for c: Dictionary in fm.tamed():
		if not bool(c.get("pet", false)) or live.has(String(c["id"])) or not bool(c.get("pet_world", true)):
			continue
		var w := Wolf.new()
		w.species = String(c.get("species_world", "wolf"))
		var at := player.global_position + Vector3(2.5, 0.0, 2.5)
		if String(c.get("mode", "follow")) == "guard" and c.has("post"):
			at = Vector3(float(c["post"][0]), 0.0, float(c["post"][1]))
		w.home = Vector2(at.x, at.z)
		player.get_parent().add_child(w)
		w.global_position = Vector3(at.x, WorldGen.height(at.x, at.z) + 0.3, at.z)
		TamedPet.adopt(w, fm, String(c["id"]), String(c.get("mode", "follow")))
