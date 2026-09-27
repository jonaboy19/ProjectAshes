class_name Villager
extends CharacterBody3D
## The embodied form of one WorldSim person. Walks toward wherever the
## simulation says they are. Only the nearby LOD is a physics body, so the
## player can stand behind a resident without turning the whole crowd physical.

const WORLD_LAYER := 1
const LOCAL_ACTOR_LAYER := 2
const WALK_SPEED := 1.6

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
	# Villagers block the player and solid world geometry, but don't shove one
	# another into jams. The player includes LOCAL_ACTOR_LAYER in its mask.
	collision_layer = LOCAL_ACTOR_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.25
	body_shape.shape = capsule
	body_shape.position.y = capsule.height * 0.5
	add_child(body_shape)
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


func _physics_process(delta: float) -> void:
	var p: Vector2 = WorldSim.pos[person]
	var goal := Vector3(p.x, 0, p.y)
	var to := goal - Vector3(global_position.x, 0, global_position.z)
	var dist := to.length()
	if dist > 0.15:
		var catch_up := 3.0 if dist > 4.0 else 1.0
		var speed := WALK_SPEED * catch_up
		velocity.x = to.x / dist * minf(speed, dist / maxf(delta, 0.001))
		velocity.z = to.z / dist * minf(speed, dist / maxf(delta, 0.001))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y = 0.0
	move_and_slide()
	global_position.y = WorldGen.height(global_position.x, global_position.z)
	# Physics may stop the resident at the player or a building. Feed the
	# resolved position back so the data simulation doesn't pull it through.
	WorldSim.pos[person] = Vector2(global_position.x, global_position.z)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed > 0.08:
		var facing := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-8.0 * delta))
		_play("Walking_A")
		if _anim:
			_anim.speed_scale = clampf(planar_speed / WALK_SPEED, 0.65, 2.0)
	else:
		_play("Idle")
		if _anim:
			_anim.speed_scale = 1.0
	_tag_timer -= delta
	if _tag_timer <= 0.0:
		_tag_timer = 1.0
		_tag.text = WorldSim.describe(person)
	_tag.visible = show_tag


func _play(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)
