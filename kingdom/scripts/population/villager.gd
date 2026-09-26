class_name Villager
extends Node3D
## The embodied form of one WorldSim person. Walks toward wherever the
## simulation says they are; the simulation, not this node, owns the truth.

var person := -1
## Set by PopulationLOD for the single nearest villager.
var show_tag := false
var _file := ""
var _keep: Array[String] = []
var _anim: AnimationPlayer
var _tag: Label3D
var _tag_timer := 0.0


static func create(id: int, file: String, keep: Array[String]) -> Villager:
	var v := Villager.new()
	v.person = id
	v._file = file
	v._keep = keep
	return v


func _ready() -> void:
	add_to_group("villager")
	var model := Assets.character(_file, 1.7, _keep)
	add_child(model)
	_anim = Assets.animation_player(model)
	var p: Vector2 = WorldSim.pos[person]
	position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.pixel_size = 0.004
	_tag.font_size = 32
	_tag.outline_size = 8
	_tag.position.y = 1.95
	_tag.modulate = Color(1, 0.95, 0.85)
	add_child(_tag)
	_tag.text = WorldSim.describe(person)


func _process(delta: float) -> void:
	var p: Vector2 = WorldSim.pos[person]
	var goal := Vector3(p.x, 0, p.y)
	var to := goal - Vector3(position.x, 0, position.z)
	var dist := to.length()
	if dist > 0.15:
		var step := to / dist * minf(dist, 1.6 * delta * (3.0 if dist > 4.0 else 1.0))
		position += step
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.15)
		_play("Walking_A")
	else:
		_play("Idle")
	position.y = WorldGen.height(position.x, position.z)
	_tag_timer -= delta
	if _tag_timer <= 0.0:
		_tag_timer = 1.0
		_tag.text = WorldSim.describe(person)
	_tag.visible = show_tag


func _play(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)
