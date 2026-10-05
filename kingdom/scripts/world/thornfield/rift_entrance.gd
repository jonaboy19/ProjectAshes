extends Node3D
## The mouth of the Thornfield Rift in the forest south of Thornfield (F9): a cleft in the ground between two
## leaning boulders, violet crystal light, and the RiftDoor that leads into the fixed layout (rift_door.gd). Position is
## data ("rift.entrance_offset" in thornfield_wilds.json); built within build_range of the player.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const RiftDoor := preload("res://scripts/world/thornfield/rift_door.gd")

var door: Node
var center := Vector2.INF
var built := false
var _root: Node3D


func _ready() -> void:
	name = "RiftEntrance"
	center = Wilds.at(Wilds.data()["rift"]["entrance_offset"])


func build() -> void:
	if built or center == Vector2.INF:
		return
	built = true
	_root = Node3D.new()
	_root.name = "Mouth"
	add_child(_root)
	Props.prop(_root, "boulder", center + Vector2(-2.6, -0.4), 0.4, 1.7)
	Props.prop(_root, "boulder", center + Vector2(2.7, 0.2), 2.6, 1.8)
	Props.prop(_root, "boulder", center + Vector2(0.2, -2.4), 1.3, 2.2)
	var gap := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 2.8, 0.2)
	gap.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.1, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.25, 0.95)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gap.material_override = mat
	gap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(gap)
	gap.global_position = Wilds.ground(center) + Vector3(0, 1.4, -0.9)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.4, 1.0)
	l.light_energy = 1.4
	l.omni_range = 9.0
	l.shadow_enabled = false
	_root.add_child(l)
	l.global_position = Wilds.ground(center) + Vector3(0, 1.8, 0.6)
	Props.prop(_root, "signpost", center + Vector2(5.0, 4.5), 2.4, 1.0)
	var d: Node = RiftDoor.new()
	add_child(d)
	d.call("configure_rift")
	(d as Node3D).global_position = Wilds.ground(center) + Vector3(0, 0, 1.3)
	(d as Node3D).global_position.y = WorldGen.height((d as Node3D).global_position.x, (d as Node3D).global_position.z)
	door = d


func free_built() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	if door != null and is_instance_valid(door):
		door.queue_free()
	_root = null
	door = null
	built = false


func refresh(pp: Vector2) -> void:
	if center == Vector2.INF:
		return
	var d := pp.distance_to(center)
	var rng := float(Wilds.data()["rift"]["build_range"])
	if not built and d < rng:
		build()
	elif built and d > rng + 120.0 and InteriorDoor.active == null:
		free_built()
