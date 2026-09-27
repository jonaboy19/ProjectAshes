class_name Wolf
extends CharacterBody3D
## Forest wolf (Quaternius Ultimate Animated Animals, CC0). Small state machine:
## roam its den's territory -> stalk -> attack -> flee when hurt or when it
## wanders into strong runestone protection. A cheap capsule blocks the player
## and world nearby; distant animals keep terrain-based steering.

signal died(wolf: Wolf)

const MODEL := "res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Wolf.gltf"
const PLAYER_SOLID_RANGE := 16.0
const WORLD_LAYER := 1
const ENEMY_LAYER := 4
enum State { ROAM, STALK, ATTACK, FLEE }

var den_id := -1
var home := Vector2.ZERO
var territory := 200.0
var health := 45
var dead := false
var team := 1
var state := State.ROAM

var _anim: AnimationPlayer
var _target := Vector3.ZERO
var _think := 0.0
var _attack_cd := 0.0
var _busy := 0.0
var _speed := 0.0
var _actor_shape: CollisionShape3D


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_actor_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.1
	_actor_shape.shape = capsule
	_actor_shape.position.y = capsule.height * 0.5
	_actor_shape.disabled = true
	add_child(_actor_shape)
	add_to_group("team1")
	add_to_group("combatant")
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	var box := Assets.visual_aabb(model)
	model.scale = Vector3.ONE * (0.85 / maxf(box.size.y, 0.01))   # ~85 cm at the shoulder
	add_child(model)
	_anim = Assets.animation_player(model)
	for a in ["Idle", "Walk", "Gallop", "Idle_2"]:
		if _anim and _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_pick_roam_target()


func _physics_process(delta: float) -> void:
	if dead:
		return
	_think -= delta
	_attack_cd -= delta
	_busy -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var here := Vector2(global_position.x, global_position.z)
	var cov := Frontier.runestones.coverage(here)
	if _think <= 0.0:
		_think = 0.3
		_decide(player, cov)
	var want := 0.0
	match state:
		State.ROAM:
			want = 1.6
			if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 2.0:
				_pick_roam_target()
		State.STALK:
			want = 3.5
			_target = player.global_position
		State.ATTACK:
			_target = player.global_position
			var d := global_position.distance_to(_target)
			want = 7.5 if d > 1.8 else 0.0
			if d <= 1.9 and _attack_cd <= 0.0:
				_bite(player)
		State.FLEE:
			want = 8.0
	if _busy > 0.0:
		want = 0.0
	_speed = lerpf(_speed, want, 6.0 * delta)
	_update_player_collision(player)
	var to := _target - global_position
	to.y = 0.0
	if state == State.FLEE:
		to = -to
	if to.length() > 0.3 and _speed > 0.05:
		var dir := to.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 6.0 * delta)
		var step_velocity := dir * _speed
		if _near_player(player):
			velocity = step_velocity
			move_and_slide()
			global_position.y = WorldGen.height(global_position.x, global_position.z)
		else:
			var p := global_position + step_velocity * delta
			p.y = WorldGen.height(p.x, p.z)
			global_position = p
	if _busy <= 0.0:
		_play("Gallop" if _speed > 4.5 else ("Walk" if _speed > 0.4 else "Idle"))


func _decide(player: Node3D, cov: float) -> void:
	if health < 15 or cov > 0.55:
		state = State.FLEE
		_target = Vector3(home.x, 0, home.y) if cov > 0.55 else (player.global_position if player else global_position)
		if health >= 15 and cov < 0.3:
			state = State.ROAM
		return
	if player == null or player.get("dead"):
		state = State.ROAM
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var d := global_position.distance_to(player.global_position)
	var player_cov := Frontier.runestones.coverage(pp)
	var in_territory := pp.distance_to(home) < territory * 1.3
	if player_cov > 0.5:
		state = State.ROAM            # won't follow prey into protected land
	elif d < 14.0 and in_territory:
		state = State.ATTACK
	elif d < 35.0 and in_territory:
		state = State.STALK
	else:
		state = State.ROAM


func _near_player(player: Node3D) -> bool:
	return player != null and player.global_position.distance_squared_to(global_position) < PLAYER_SOLID_RANGE * PLAYER_SOLID_RANGE


func _update_player_collision(player: Node3D) -> void:
	var should_disable := not _near_player(player)
	if _actor_shape.disabled != should_disable:
		_actor_shape.set_deferred("disabled", should_disable)


func _pick_roam_target() -> void:
	var ang := randf() * TAU
	var p := home + Vector2(cos(ang), sin(ang)) * randf_range(10.0, territory * 0.8)
	_target = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _bite(player: Node3D) -> void:
	_attack_cd = randf_range(1.2, 1.8)
	_busy = 0.5
	_play("Attack", true)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if not dead and is_instance_valid(player) and global_position.distance_to(player.global_position) < 2.4:
			player.take_damage(9, self)
			Audio.sfx("hit", global_position, -8.0))


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	global_position += knockback * 0.12
	if health <= 0:
		dead = true
		remove_from_group("team1")
		remove_from_group("combatant")
		_play("Death", true)
		died.emit(self)
		var t := create_tween()
		t.tween_interval(6.0)
		t.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.5)
		t.tween_callback(queue_free)
	else:
		_busy = 0.3
		_play("Idle_HitReact1", true)
		if from is Node3D:
			state = State.ATTACK


func _play(anim_name: String, restart := false) -> void:
	if _anim and _anim.has_animation(anim_name) and (restart or _anim.current_animation != anim_name):
		_anim.play(anim_name, 0.15)
