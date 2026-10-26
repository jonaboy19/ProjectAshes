class_name TamedPet
extends Node
## READY_V1 C8: the behaviour of a tamed wolf / Stagborn elk, driven from outside so wolf.gd stays untouched. The host's
## own AI and groups are switched off, and this child walks it: "follow" trails the player, "guard" holds a post (and
## comes running when the player is far away). The mode lives in the followers.gd creature entry, so it is in the save.
## Animation: the host plays nothing here (no clip API is called); the local animation pass adds follow/guard clips.

const FOLLOW_DIST := 3.2
const CATCH_UP := 40.0
const WALK := 2.4
const RUN := 5.0
const MODES := ["follow", "guard"]

var host: Node3D
var cid := ""
var mode := "follow"
var post := Vector3.ZERO


## Takes `body` off the wild AI and gives it a TamedPet. Role: follow = scouting, guard = guarding (wolf only).
static func adopt(body: Node3D, fm: RefCounted, creature: String, start_mode := "follow") -> TamedPet:
	body.set_meta("tamed", creature)
	body.set_physics_process(false)
	body.set_process(false)
	for g in ["team1", "combatant", "hostile", "enemy"]:
		if body.is_in_group(g):
			body.remove_from_group(g)
	body.add_to_group("tamed_pet")
	if body.get("health") != null:
		body.set("health", body.get("max_health"))
	var comp := Interactable.component_of(body)
	if comp != null:
		comp.free()
	var pet := TamedPet.new()
	pet.name = "TamedPet"
	pet.host = body
	pet.cid = creature
	body.add_child(pet)
	var c: Dictionary = fm.creature(creature)
	c["pet"] = true
	c["species_world"] = String(body.get("species"))
	pet.set_mode(start_mode, fm)
	Interactable.attach(body, {"id": "pet/" + creature, "verb": "Command", "target": String(c.get("name", "beast")), "range": 2.8,
		"label": func() -> Dictionary: return {"verb": "Guard here" if pet.mode == "follow" and String(c.get("species", "")) == "wolf" else "Follow me", "target": String(c.get("name", "beast"))},
		"do": func(_p: Node) -> void: pet.set_mode("guard" if pet.mode == "follow" and String(c.get("species", "")) == "wolf" else "follow", fm)})
	return pet


func set_mode(m: String, fm: RefCounted) -> void:
	mode = m if MODES.has(m) else "follow"
	var c: Dictionary = fm.creature(cid)
	if c.is_empty():
		return
	c["mode"] = mode
	if mode == "guard":
		post = host.global_position
		c["post"] = [post.x, post.z]
		fm.assign_role(cid, "guarding", String(c.get("loc", "s0")))
	else:
		fm.assign_role(cid, "scouting", String(c.get("loc", "s0")))


func _physics_process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var goal := player.global_position
	var stop := FOLLOW_DIST
	if mode == "guard" and goal.distance_to(host.global_position) < CATCH_UP:
		goal = post
		stop = 1.5
	var d := goal - host.global_position
	d.y = 0.0
	var dist := d.length()
	if dist <= stop:
		return
	var speed := RUN if dist > stop + 8.0 else WALK
	var step := d / dist * minf(speed * delta, dist - stop)
	var p := host.global_position + step
	p.y = WorldGen.height(p.x, p.z)
	host.global_position = p
	host.rotation.y = lerp_angle(host.rotation.y, atan2(-d.x, -d.z), minf(1.0, 8.0 * delta))
