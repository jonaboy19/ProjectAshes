class_name Carryable
extends Node3D
## A crate, sack or log the player can pick up and carry in both arms (blueprint §3, WP-01): "Pick up" lifts it to the chest
## (Chore_Pick_Up_Box), the weapons go to their sheathe sockets (hands free), walking is slower and sprint / jump / dodge /
## attack are off; "Put down" (or attacking) sets it on the ground in front. The arms hold it through the rig's arm IK
## (ProceduralRig.set_hand_brace on both sides), so it works over any locomotion clip.

signal picked_up(player: Node)
signal put_down(player: Node)

## kind -> [size m, mass kg, colour]; logs are carried across the chest (long axis sideways).
const KINDS := {
	"crate": [Vector3(0.5, 0.4, 0.4), 14.0, Color(0.48, 0.34, 0.2)],
	"sack": [Vector3(0.45, 0.5, 0.3), 20.0, Color(0.62, 0.55, 0.4)],
	"log": [Vector3(1.1, 0.24, 0.24), 22.0, Color(0.36, 0.25, 0.15)],
}
const SPEED_MULT := 0.6

var kind := "crate"
var carrier: Node3D = null
var _body: StaticBody3D


static func spawn(parent: Node, pos: Vector3, carry_kind := "crate", yaw := 0.0) -> Node3D:
	var c: Node3D = (load("res://scripts/interaction/kinds/carryable.gd") as GDScript).new()
	c.set("kind", carry_kind)
	c.name = "Carry_%s" % carry_kind
	parent.add_child(c)
	c.global_position = pos
	c.rotation.y = yaw
	return c


func _ready() -> void:
	_build()
	Interactable.attach(self, {"id_fn": func() -> String: return "carry/%s/%d_%d" % [kind, roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)],
		"verb": "Pick up", "range": 2.2,
		"can": func(p: Node) -> bool: return carrier == p or (carrier == null and p.has_method("carry_pick") and p.get("_carry") == null),
		"do": func(p: Node) -> void:
			if carrier == p:
				p.call("carry_drop")
			else:
				p.call("carry_pick", self),
		"label": func() -> Dictionary: return {"verb": "Put down" if carrier != null else "Pick up", "target": kind.capitalize()}})


func size() -> Vector3:
	return (KINDS.get(kind, KINDS["crate"]) as Array)[0]


func mass() -> float:
	return float((KINDS.get(kind, KINDS["crate"]) as Array)[1])


## Carried: no collision (the body walks with it), lifted by the player each frame.
func set_carried(by: Node3D) -> void:
	carrier = by
	if _body:
		_body.collision_layer = 0 if by != null else 1
	if by != null:
		picked_up.emit(by)


## Pure: where the carried object sits relative to the body (model space: +Z forward, +Y up), from the chest height.
static func hold_offset(chest_y: float, obj_size: Vector3) -> Vector3:
	return Vector3(0.0, chest_y - 0.12 - obj_size.y * 0.25, 0.2 + obj_size.z * 0.5)


func _build() -> void:
	var k: Array = KINDS.get(kind, KINDS["crate"])
	var sz: Vector3 = k[0]
	var mi := MeshInstance3D.new()
	if kind == "log":
		var cm := CylinderMesh.new()
		cm.top_radius = sz.y * 0.5
		cm.bottom_radius = sz.y * 0.52
		cm.height = sz.x
		mi.mesh = cm
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif kind == "sack":
		var sm := SphereMesh.new()
		sm.radius = sz.x * 0.5
		sm.height = sz.y
		mi.mesh = sm
		mi.scale = Vector3(1.0, 1.0, sz.z / sz.x)
	else:
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = k[2]
	m.roughness = 0.95
	mi.material_override = m
	mi.position.y = sz.y * 0.5
	add_child(mi)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = sz
	cs.shape = sh
	cs.position.y = sz.y * 0.5
	_body.add_child(cs)
	add_child(_body)
