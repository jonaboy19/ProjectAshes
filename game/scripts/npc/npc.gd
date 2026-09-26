class_name NPC
extends Node3D
## Villager with a name tag. Talking routes through the Dialogue autoload by npc_id.

var npc_id := ""
var display_name := ""
var outfit := Color("7a6a55")
var hair := Color("3b2a20")
var height_scale := 1.0
var _model: Node3D
var _bob := randf() * TAU


static func create(id: String, name_text: String, outfit_color: Color, hair_color: Color, scale_factor := 1.0) -> NPC:
	var npc := NPC.new()
	npc.npc_id = id
	npc.display_name = name_text
	npc.outfit = outfit_color
	npc.hair = hair_color
	npc.height_scale = scale_factor
	return npc


func _ready() -> void:
	_model = Node3D.new()
	_model.scale = Vector3.ONE * height_scale
	add_child(_model)
	Props.part(_model, Props.cylinder(0.26, 0.4, 1.1, 8), outfit, Vector3(0, 0.55, 0))
	Props.part(_model, Props.sphere(0.26, 10, 6), Color("e8bf98"), Vector3(0, 1.38, 0))
	Props.part(_model, Props.sphere(0.28, 8, 4), hair, Vector3(0, 1.47, -0.05))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6 * height_scale
	shape.shape = capsule
	shape.position.y = 0.8 * height_scale
	body.add_child(shape)
	add_child(body)
	var tag := Label3D.new()
	tag.text = display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.006
	tag.position.y = 2.0 * height_scale
	tag.no_depth_test = false
	add_child(tag)
	var talk := Interactable.make("Talk", 1.4)
	add_child(talk)
	talk.interacted.connect(_on_talk)


func _process(delta: float) -> void:
	_bob += delta * 2.0
	_model.position.y = sin(_bob) * 0.02


func _on_talk(by: Node) -> void:
	var to: Vector3 = (by as Node3D).global_position - global_position
	_model.rotation.y = atan2(to.x, to.z)
	Dialogue.start_for_npc(npc_id)
