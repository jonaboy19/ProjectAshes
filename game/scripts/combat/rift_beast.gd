class_name RiftBeast
extends CharacterBody3D
## Placeholder Rift-touched wolf. Wanders its den, chases and bites the player.

signal died(beast: RiftBeast)

const GRAVITY := 24.0

var max_health := 30
var health := 30
var home := Vector3.ZERO
var _attack_cooldown := 0.0
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _model: Node3D
var _dead := false


func _ready() -> void:
	add_to_group("enemy")
	home = global_position
	_wander_target = home
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 1.6)
	shape.shape = box
	shape.position.y = 0.55
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	var fur := Color("2b2433")
	Props.part(_model, Props.box(Vector3(0.8, 0.7, 1.4)), fur, Vector3(0, 0.75, 0))
	Props.part(_model, Props.box(Vector3(0.6, 0.55, 0.6)), fur, Vector3(0, 0.95, 0.85))
	Props.part(_model, Props.box(Vector3(0.35, 0.3, 0.4)), Color("1c1722"), Vector3(0, 0.85, 1.25))
	for sx in [-1, 1]:
		Props.part(_model, Props.cylinder(0.0, 0.12, 0.35, 4), fur, Vector3(sx * 0.2, 1.35, 0.8))
		var eye := Props.part(_model, Props.box(Vector3(0.1, 0.07, 0.05)), Color("c86bff"), Vector3(sx * 0.16, 1.02, 1.16))
		eye.material_override = Props.mat(Color("c86bff"), 4.0)
		for sz in [-1, 1]:
			Props.part(_model, Props.box(Vector3(0.18, 0.5, 0.18)), fur, Vector3(sx * 0.28, 0.25, sz * 0.5))
	# Crystal growths along the spine: the Rift's mark.
	for i in 3:
		var spike := Props.part(_model, Props.cylinder(0.0, 0.12, 0.45, 5), Color("9b4dff"), Vector3(0, 1.25, 0.3 - i * 0.4))
		spike.material_override = Props.mat(Color("9b4dff"), 1.5)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_cooldown -= delta
	var player := get_tree().get_first_node_in_group("player") as Player
	var move := Vector3.ZERO
	var speed := 2.0
	if player and not player.input_locked and player.global_position.distance_to(home) < 26.0 \
			and player.global_position.distance_to(global_position) < 14.0:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 1.6:
			move = to_player.normalized()
			speed = 5.2
		elif _attack_cooldown <= 0.0:
			_attack_cooldown = 1.3
			player.take_damage(12, self)
			_lunge()
		_face(to_player)
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(2.0, 4.0)
			_wander_target = home + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		var to_target := _wander_target - global_position
		to_target.y = 0.0
		if to_target.length() > 0.5:
			move = to_target.normalized()
			_face(to_target)
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), 0.2)


func _lunge() -> void:
	var tween := create_tween()
	tween.tween_property(_model, "position:z", 0.4, 0.08)
	tween.tween_property(_model, "position:z", 0.0, 0.15)


func take_damage(amount: int, _from: Node = null) -> void:
	if _dead:
		return
	health -= amount
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.1)
	if health <= 0:
		_dead = true
		remove_from_group("enemy")
		died.emit(self)
		var fade := create_tween()
		fade.tween_property(_model, "scale", Vector3(1.4, 0.05, 1.4), 0.4)
		fade.tween_callback(queue_free)
