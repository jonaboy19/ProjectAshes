extends Node3D
## The Ash Hand camp off the Thornfield road (F9): tents, a palisade stub, a campfire, a lookout platform, a strongbox,
## and five bandits. The bandits are the army Soldier fighters (team 1, an NpcFighter "bandit" each, scripts/army/
## soldier.gd): four hold the camp as one Squad and the lookout is a Squad of one on his platform with a wider eye.
## The strongbox is a Container owned by "bandit:<camp id>" (scripts/sim/ownership.gd): taking from it is not a crime.
## All positions are data (data/region1/world/thornfield_wilds.json "bandit_camp", offsets from the camp centre, which is
## an offset from Thornfield). Props are built within build_range of the player and freed beyond free_range; the bandits
## come with spawn_range and go with free_range, and a camp whose bandits were all killed stays empty respawn_days.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const Squad := preload("res://scripts/army/squad.gd")
const Ownership := preload("res://scripts/sim/ownership.gd")
const KEEP: Array[String] = ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"]

var def: Dictionary = {}
var center := Vector2.INF
var chest: Node3D
var camp_squad: Node
var lookout_squad: Node
var fire_light: OmniLight3D
var built := false
var dead_day := -999
var _root: Node3D


static func create(parent: Node, camp_def: Dictionary) -> Node3D:
	var c: Node3D = (load("res://scripts/world/thornfield/bandit_camp.gd") as GDScript).new()
	c.set("def", camp_def)
	parent.add_child(c)
	return c


func _ready() -> void:
	name = "BanditCamp_" + String(def.get("id", "camp"))
	center = Wilds.at(def["offset"])


func owner_id() -> String:
	return Ownership.bandit(String(def["id"]))


## World XZ of a camp-local offset.
func at(local: Array) -> Vector2:
	return center + Vector2(float(local[0]), float(local[1]))


# --- props -----------------------------------------------------------------------------------------

func build() -> void:
	if built or center == Vector2.INF:
		return
	built = true
	_root = Node3D.new()
	_root.name = "Props"
	add_child(_root)
	for t: Array in def["tents"]:
		Props.prop(_root, "tent", at(t), deg_to_rad(float(t[2])), 1.0, 0.0, true)
	for p: Array in def["palisade"]:
		Props.prop(_root, "palisade", at(p), deg_to_rad(float(p[2])), 1.0)
	var fire := Props.prop(_root, "campfire", at(def["campfire"]["offset"]), 0.0, 1.0, 0.0, false)
	fire.add_to_group("bandit_campfire")
	fire_light = Props.fire_light(_root, Wilds.ground(at(def["campfire"]["offset"]), 1.4), 1.5, 12.0)
	for c: Array in def["crates"]:
		Props.prop(_root, "crate_stack", at(c), float(c[0]) * 0.7)
	_build_lookout()
	var cd: Dictionary = def["chest"]
	var stacks: Array = []
	for s: Array in cd["stacks"]:
		stacks.append({"item": String(s[0]), "qty": int(s[1])})
	var ContainerKind := load("res://scripts/interaction/kinds/container.gd") as GDScript
	chest = ContainerKind.call("spawn", self, Wilds.ground(at(cd["offset"])), String(cd["id"]), String(cd["label"]), stacks, "", owner_id(), true)
	chest.add_to_group("bandit_chest")


func _build_lookout() -> void:
	var lo: Dictionary = def["lookout"]
	var p := at(lo["offset"])
	var wood := Color(0.36, 0.26, 0.16)
	var dark := Color(0.28, 0.2, 0.13)
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append([Vector3(sx * 1.0, 2.1, sz * 1.0), Vector3(0.22, 4.2, 0.22), 0.0, wood])
	parts.append([Vector3(0, 4.2, 0), Vector3(2.5, 0.16, 2.5), 0.0, dark])
	parts.append([Vector3(0, 4.85, 1.1), Vector3(2.4, 0.9, 0.08), 0.0, wood])
	parts.append([Vector3(0, 4.85, -1.1), Vector3(2.4, 0.9, 0.08), 0.0, wood])
	parts.append([Vector3(1.1, 4.85, 0), Vector3(0.08, 0.9, 2.2), 0.0, wood])
	parts.append([Vector3(-1.1, 4.85, 0), Vector3(0.08, 0.9, 2.2), 0.0, wood])
	parts.append([Vector3(0.0, 1.3, -1.3), Vector3(0.12, 2.8, 0.5), 0.5, dark])      # the ladder rail
	var mi := MeshInstance3D.new()
	mi.name = "LookoutPlatform"
	mi.mesh = Props.boxes_mesh(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(lo.get("yaw_deg", 0.0)))), Vector3(p.x, WorldGen.height(p.x, p.y) - 0.05, p.y))
	mi.set_meta("lookout", true)


# --- the bandits -------------------------------------------------------------------------------------

## Spawns the roster (idempotent while it is alive). Returns the soldiers.
func spawn_roster() -> Array:
	if center == Vector2.INF:
		return []
	if not bandits().is_empty():
		return bandits()
	var camp_n := 0
	var lookout_at := Vector2.INF
	for r: Dictionary in def["roster"]:
		if String(r["role"]) == "lookout":
			lookout_at = at(r["offset"])
		else:
			camp_n += 1
	var base := Wilds.ground(center)
	camp_squad = _squad(base, 28.0)
	camp_squad.call("add_soldiers", camp_n, base)
	if lookout_at != Vector2.INF:
		var lp := Wilds.ground(lookout_at, 4.2)
		lookout_squad = _squad(lp, 42.0)
		lookout_squad.call("add_soldiers", 1, lp)
		for s: Variant in (lookout_squad.get("soldiers") as Array):
			if is_instance_valid(s):
				(s as Node3D).global_position = lp
				(s as Node3D).set_meta("lookout", true)
	for s: Variant in bandits():
		(s as Node).set_meta("bandit_camp", String(def["id"]))
	return bandits()


func _squad(anchor: Vector3, aggro: float) -> Node:
	var sq := Squad.new().setup(1, "raider", "Barbarian", KEEP)
	sq.anchor = anchor
	sq.aggro_radius = aggro
	add_child(sq)
	return sq


## The living bandits across both squads.
func bandits() -> Array:
	var out: Array = []
	for sq: Variant in [camp_squad, lookout_squad]:
		if sq != null and is_instance_valid(sq):
			for s: Variant in (sq.get("soldiers") as Array):
				if is_instance_valid(s) and not bool((s as Node).get("dead")):
					out.append(s)
	return out


func despawn_roster() -> void:
	for sq: Variant in [camp_squad, lookout_squad]:
		if sq != null and is_instance_valid(sq):
			for s: Variant in (sq.get("soldiers") as Array).duplicate():
				if is_instance_valid(s):
					(s as Node).queue_free()
			(sq as Node).queue_free()
	camp_squad = null
	lookout_squad = null


func free_props() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	if chest != null and is_instance_valid(chest):
		chest.queue_free()
	_root = null
	chest = null
	built = false


## The hub's 2 s timer: build, spawn and free by distance.
func refresh(pp: Vector2) -> void:
	if center == Vector2.INF:
		return
	var d := pp.distance_to(center)
	if not built and d < float(def["build_range"]):
		build()
	elif built and d > float(def["free_range"]) + 120.0:
		free_props()
	var have := not bandits().is_empty()
	var camp_alive := camp_squad != null and is_instance_valid(camp_squad)
	if camp_alive and not have:
		# every bandit is dead: the camp stays quiet for a few days
		despawn_roster()
		dead_day = int(WorldSim.day)
	elif not camp_alive and d < float(def["spawn_range"]) and built and int(WorldSim.day) - dead_day >= int(def["respawn_days"]):
		spawn_roster()
	elif camp_alive and d > float(def["free_range"]):
		despawn_roster()
