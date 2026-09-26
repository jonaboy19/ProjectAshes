class_name NPC
extends Node3D
## Villager with a name tag. Talking routes through the Dialogue autoload by npc_id.

var npc_id := ""
var display_name := ""
var model_file := "Mage"
var keep_parts: Array[String] = []
var idle_anim := "Idle"
var height_scale := 1.0
var _model: Node3D


static func create(id: String, name_text: String, file: String, keep: Array[String], idle: String, scale_factor := 1.0) -> NPC:
	var npc := NPC.new()
	npc.npc_id = id
	npc.display_name = name_text
	npc.model_file = file
	npc.keep_parts = keep
	npc.idle_anim = idle
	npc.height_scale = scale_factor
	return npc


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	var character := Assets.character(model_file, 1.75 * height_scale, keep_parts)
	_model.add_child(character)
	var anim := Assets.animation_player(character)
	if anim and anim.has_animation(idle_anim):
		anim.play(idle_anim)
		anim.seek(randf() * anim.current_animation_length, true)
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
	tag.position.y = 2.15 * height_scale
	tag.no_depth_test = false
	add_child(tag)
	var talk := Interactable.make("Talk", 1.4)
	add_child(talk)
	talk.interacted.connect(_on_talk)


func _on_talk(by: Node) -> void:
	var to: Vector3 = (by as Node3D).global_position - global_position
	_model.rotation.y = atan2(to.x, to.z)
	Dialogue.start_for_npc(npc_id)
