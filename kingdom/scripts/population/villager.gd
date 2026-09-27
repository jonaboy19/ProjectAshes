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
var _step_distance := 0.0
var _activity_name := ""
var _activity_needs_start := true
var _activity_pause := 0.0
var _look_target: Node3D
var _look_timer := 0.0


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
	_add_head_look(model)
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
	var steering := to.normalized() if dist > 0.15 else Vector3.ZERO
	steering += _separation_force() * 1.8
	var desired_velocity := Vector3.ZERO
	if steering.length_squared() > 0.01:
		var catch_up := 3.0 if dist > 4.0 else 1.0
		var speed := WALK_SPEED * catch_up
		if dist > 0.15:
			speed = minf(speed, dist / maxf(delta, 0.001))
		else:
			speed *= 0.65
		desired_velocity = steering.normalized() * speed
	var response := 9.0 if desired_velocity.length_squared() > 0.01 else 12.0
	velocity = velocity.move_toward(desired_velocity, response * delta)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = WorldGen.height(global_position.x, global_position.z)
	# Physics may stop the resident at the player or a building. Feed the
	# resolved position back so the data simulation doesn't pull it through.
	WorldSim.pos[person] = Vector2(global_position.x, global_position.z)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_head_look(delta)
	if planar_speed > 0.08:
		_activity_name = ""
		_activity_needs_start = true
		var facing := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, facing, 1.0 - exp(-8.0 * delta))
		_play("Walking_A")
		var animation_rate := clampf(planar_speed / WALK_SPEED, 0.65, 2.0)
		if _anim:
			_anim.speed_scale = animation_rate
		_step_distance += planar_speed * delta
		var stride := planar_speed / (1.5 * animation_rate)
		if _step_distance >= stride:
			_step_distance = fmod(_step_distance, stride)
			Audio.sfx("step_" + WorldGen.footstep_surface(global_position.x, global_position.z), global_position, -15.0)
	else:
		_update_activity(delta)
	_tag_timer -= delta
	if _tag_timer <= 0.0:
		_tag_timer = 1.0
		_tag.text = WorldSim.describe(person)
	_tag.visible = show_tag


func _separation_force() -> Vector3:
	var push := Vector3.ZERO
	for other_node in get_tree().get_nodes_in_group("villager"):
		if other_node == self or not other_node is Node3D:
			continue
		var other := other_node as Node3D
		var away := global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance < 0.9:
			if distance < 0.01:
				away = Vector3.RIGHT.rotated(Vector3.UP, float(person) * 2.399)
				distance = 0.01
			push += away / distance * ((0.9 - distance) / 0.9)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var away_from_player := global_position - player.global_position
		away_from_player.y = 0.0
		var player_distance := away_from_player.length()
		if player_distance < 1.5:
			if player_distance < 0.01:
				away_from_player = Vector3.RIGHT.rotated(Vector3.UP, float(person) * 2.399)
				player_distance = 0.01
			push += away_from_player / player_distance * (1.5 - player_distance) / 1.5 * 2.0
	return push.limit_length(1.5)


func _add_head_look(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone("head") < 0:
		return
	_look_target = Node3D.new()
	add_child(_look_target)
	var look := LookAtModifier3D.new()
	look.bone_name = "head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.use_angle_limitation = true
	look.symmetry_limitation = true
	look.primary_limit_angle = deg_to_rad(120)
	look.secondary_limit_angle = deg_to_rad(55)
	look.duration = 0.3
	look.influence = 0.75
	skeleton.add_child(look)
	look.target_node = look.get_path_to(_look_target)


func _update_head_look(delta: float) -> void:
	if _look_target == null:
		return
	_look_timer -= delta
	if _look_timer > 0.0:
		return
	_look_timer = 0.12
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var target := global_position + Vector3(0, 1.45, 0) + forward * 3.0
	if player and global_position.distance_squared_to(player.global_position) < 25.0:
		target = player.global_position + Vector3(0, 1.45, 0)
	_look_target.global_position = _look_target.global_position.lerp(target, 1.0 - exp(-7.0 * delta))


func _update_activity(delta: float) -> void:
	_step_distance = 0.0
	if _anim == null:
		return
	var activity := _activity_for_person()
	if activity != _activity_name:
		_activity_name = activity
		_activity_needs_start = true
		_activity_pause = 0.0
	if activity == "" or not _anim.has_animation(activity):
		_play("Idle")
		return
	if _activity_pause > 0.0:
		_activity_pause = maxf(_activity_pause - delta, 0.0)
		_play("Idle")
		return
	if _activity_needs_start:
		_anim.play(activity, 0.2)
		_activity_needs_start = false
	elif not _anim.is_playing():
		_activity_pause = randf_range(0.8, 1.8)
		_activity_needs_start = true
		_play("Idle")
	_anim.speed_scale = 1.0


func _activity_for_person() -> String:
	var job: int = WorldSim.job[person]
	var phase: int = WorldSim.phase[person]
	if phase == 2:
		return "Idle_Talking" if job != 3 else "Idle_Shield"
	match job:
		0: return "Farm_Harvest"
		1: return "Fixing_Kneeling"
		2: return "Idle_Talking"
		3: return "Idle_Shield"
		4: return "Interact"
		5: return "TreeChopping"
	return ""


func _play(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)
