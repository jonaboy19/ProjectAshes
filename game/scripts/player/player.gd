class_name Player
extends CharacterBody3D
## Sugo. Third-person movement relative to the camera, a wooden-sword combo,
## dodge, interaction, and a blessing cast that is locked until he has one.

signal health_changed(current: int, maximum: int)
signal interact_target_changed(target: Interactable)
signal blessing_denied

const WALK_SPEED := 4.5
const RUN_SPEED := 7.5
const DODGE_SPEED := 15.0
const GRAVITY := 24.0
const ATTACK_RANGE := 2.4
const ATTACK_DAMAGE := 10

var max_health := 100
var health := 100
## Written by the on-screen joystick each frame.
var touch_move := Vector2.ZERO
var input_locked := false
var spawn_point := Vector3.ZERO
var camera: Camera3D

var _yaw := 0.0
var _pitch := -0.32
var _pivot: Node3D
var _spring: SpringArm3D
var _model: Node3D
var _anim: AnimationPlayer
var _action_time := 0.0
var _attack_cooldown := 0.0
var _cast_cooldown := 0.0
var _dodge_time := 0.0
var _dodge_dir := Vector3.ZERO
var _hurt_cooldown := 0.0
var _nearby: Array[Interactable] = []
var _target: Interactable = null


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	_build_model()
	_build_camera()
	_build_interact_area()
	spawn_point = global_position


func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	# KayKit Rogue stands in for Sugo until a custom model exists; keeps only his knife.
	var body := Assets.character("Rogue", 1.75, ["Knife"])
	_model.add_child(body)
	_anim = Assets.animation_player(body)
	_play("Idle")


func _play(anim_name: String, speed := 1.0, blend := 0.15) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if _anim.current_animation == anim_name and _anim.is_playing():
		_anim.speed_scale = speed
		return
	_anim.play(anim_name, blend)
	_anim.speed_scale = speed


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.5, 0)
	add_child(_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = 6.5
	_spring.margin = 0.3
	_spring.add_excluded_object(get_rid())
	_pivot.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 600.0
	_spring.add_child(camera)
	camera.current = true


func _build_interact_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Interactable.LAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.4
	shape.shape = sphere
	shape.position.y = 1.0
	area.add_child(shape)
	add_child(area)
	area.area_entered.connect(func(a: Area3D) -> void:
		if a is Interactable: _nearby.append(a))
	area.area_exited.connect(func(a: Area3D) -> void: _nearby.erase(a))


## Called by the look area on the HUD (touch drag) — pixels of drag.
func add_camera_input(relative: Vector2) -> void:
	_yaw -= relative.x * 0.006
	_pitch = clampf(_pitch - relative.y * 0.004, -1.2, 0.35)


func set_camera_angles(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_apply_camera()


func face_direction(yaw: float) -> void:
	_model.rotation.y = yaw


func _apply_camera() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0)


func _physics_process(delta: float) -> void:
	_attack_cooldown -= delta
	_cast_cooldown -= delta
	_hurt_cooldown -= delta
	_apply_camera()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	input = input.limit_length(1.0)
	if input_locked or Dialogue.is_active():
		input = Vector2.ZERO
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, _yaw)
	var running := Input.is_action_pressed("sprint") or touch_move.length() > 0.92

	if _dodge_time > 0.0:
		_dodge_time -= delta
		velocity.x = _dodge_dir.x * DODGE_SPEED
		velocity.z = _dodge_dir.z * DODGE_SPEED
	else:
		var target := dir * (RUN_SPEED if running else WALK_SPEED)
		velocity.x = lerpf(velocity.x, target.x, 12.0 * delta)
		velocity.z = lerpf(velocity.z, target.z, 12.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	_action_time -= delta
	if dir.length() > 0.05:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), 14.0 * delta)
	if _action_time <= 0.0:
		if dir.length() > 0.05:
			_play("Running_A" if running else "Walking_A", 1.0 if running else 1.2)
		else:
			_play("Idle")

	if global_position.y < -20.0:
		global_position = spawn_point


func _process(_delta: float) -> void:
	if not input_locked and not Dialogue.is_active():
		if Input.is_action_just_pressed("attack"):
			attack()
		if Input.is_action_just_pressed("blessing"):
			cast_blessing()
		if Input.is_action_just_pressed("dodge"):
			dodge()
		if Input.is_action_just_pressed("interact"):
			interact()
	_update_target()


func _update_target() -> void:
	var best: Interactable = null
	var best_dist := INF
	for candidate in _nearby:
		if not is_instance_valid(candidate) or not candidate.enabled:
			continue
		var dist := global_position.distance_to(candidate.global_position)
		if dist < best_dist:
			best = candidate
			best_dist = dist
	if best != _target:
		_target = best
		interact_target_changed.emit(_target)


func facing() -> Vector3:
	return _model.global_transform.basis.z


func interact() -> void:
	if _target and not Dialogue.is_active():
		_target.interact(self)


func attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.5
	_action_time = 0.5
	_anim.stop()
	_play("1H_Melee_Attack_Slice_Horizontal", 1.8, 0.05)
	get_tree().create_timer(0.18).timeout.connect(_resolve_hit)


func _resolve_hit() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var to_enemy: Vector3 = enemy.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length() < ATTACK_RANGE and facing().dot(to_enemy.normalized()) > 0.2:
			enemy.take_damage(ATTACK_DAMAGE, self)


func cast_blessing() -> void:
	if _cast_cooldown > 0.0:
		return
	if GameState.player_blessing == "":
		blessing_denied.emit()
		_cast_cooldown = 1.0
		_action_time = 0.9
		_play("Spellcast_Raise", 1.0, 0.1)
		return
	var data: Dictionary = GameState.blessings[GameState.player_blessing]
	_action_time = 0.5
	_play("Spellcast_Shoot", 1.6, 0.05)
	var bolt := BlessingBolt.new()
	bolt.color = Color(data["color"])
	bolt.damage = int(data["damage"])
	bolt.speed = float(data["speed"])
	bolt.direction = facing()
	get_parent().add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.1, 0) + facing() * 0.8
	_cast_cooldown = 0.6


func dodge() -> void:
	if _dodge_time > 0.0:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	_dodge_dir = Vector3(input.x, 0, input.y).rotated(Vector3.UP, _yaw).normalized() if input.length() > 0.1 else facing()
	_dodge_time = 0.22
	_hurt_cooldown = 0.3
	_action_time = 0.4
	_model.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	_play("Dodge_Forward", 1.6, 0.05)


func take_damage(amount: int, _from: Node = null) -> void:
	if _hurt_cooldown > 0.0 or _dodge_time > 0.0:
		return
	_hurt_cooldown = 0.6
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	_action_time = 0.35
	_play("Hit_A", 1.5, 0.05)
	if health == 0:
		GameState.toast("Sugo collapses... and wakes back in Aramori.")
		global_position = spawn_point
		health = max_health
		health_changed.emit(health, max_health)
