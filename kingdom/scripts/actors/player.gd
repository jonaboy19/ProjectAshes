class_name Player
extends CharacterBody3D
## The player character plus the four-scale camera:
##   FIRST   — through the eyes, sword in hand
##   THIRD   — close over-the-shoulder exploration
##   TOWN    — pulled back to see a whole village
##   COMMAND — high above the army, still controlling the same character

signal health_changed(current: int, maximum: int)
signal view_changed(view: int)

enum View { FIRST, THIRD, TOWN, COMMAND }
const VIEW_NAMES := ["First person", "Third person", "Town view", "Command view"]
## [distance, pitch] per view.
const VIEW_RIG := [[0.0, -0.1], [5.5, -0.32], [26.0, -0.72], [85.0, -1.2]]

const VIEWMODEL_REST := Vector3(-0.5, 0.15, -0.35)
const WALK := 4.2
const RUN := 7.0
const GRAVITY := 24.0

var max_health := 120
var health := 120
var dead := false
var team := 0
var touch_move := Vector2.ZERO
var view := View.THIRD
var camera: Camera3D
var spawn_point := Vector3.ZERO

var _yaw := 0.0
var _pitch := -0.32
var _distance := 5.5
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _viewmodel: Node3D
var _action := 0.0
var _attack_cooldown := 0.0
var _hurt_cooldown := 0.0


func _ready() -> void:
	add_to_group("team0")
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	_model = Node3D.new()
	add_child(_model)
	var body := Assets.character("Knight", 1.8, ["1H_Sword", "Round_Shield"])
	_model.add_child(body)
	_anim = Assets.animation_player(body)
	_pivot = Node3D.new()
	_pivot.position.y = 1.55
	add_child(_pivot)
	camera = Camera3D.new()
	camera.far = 900.0
	camera.fov = 65.0
	_pivot.add_child(camera)
	camera.current = true
	_viewmodel = Assets.weapon("sword_1handed")
	_viewmodel.scale = Vector3.ONE * 0.3
	_viewmodel.position = Vector3(0.3, -0.32, -0.55)
	_viewmodel.rotation = VIEWMODEL_REST
	camera.add_child(_viewmodel)
	_viewmodel.visible = false
	spawn_point = global_position
	_play("Idle")


## Horizontal direction the camera looks: "forward" for movement and formations.
func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


func set_view(v: int) -> void:
	view = v as View
	_model.visible = view != View.FIRST
	_viewmodel.visible = view == View.FIRST
	view_changed.emit(view)


func cycle_first_third() -> void:
	set_view(View.THIRD if view == View.FIRST else View.FIRST)


func zoom(step: int) -> void:
	set_view(clampi(view + step, View.THIRD if step > 0 else View.FIRST, View.COMMAND))


func add_look(relative: Vector2) -> void:
	_yaw -= relative.x * 0.006
	if view == View.FIRST or view == View.THIRD:
		_pitch = clampf(_pitch - relative.y * 0.004, -1.3, 0.6)


func set_camera(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_model.rotation.y = yaw + PI


func _physics_process(delta: float) -> void:
	_action -= delta
	_attack_cooldown -= delta
	_hurt_cooldown -= delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	input = input.limit_length(1.0)
	if dead:
		input = Vector2.ZERO
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, _yaw)
	var running := Input.is_action_pressed("sprint") or touch_move.length() > 0.92 or view >= View.TOWN
	var target := dir * (RUN if running else WALK)
	velocity.x = lerpf(velocity.x, target.x, 10.0 * delta)
	velocity.z = lerpf(velocity.z, target.z, 10.0 * delta)
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	# Never fall through unloaded/streaming ground.
	var ground := WorldGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0
	if view == View.FIRST:
		_model.rotation.y = _yaw + PI
	elif dir.length() > 0.05:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
	if _action <= 0.0:
		if dir.length() > 0.05:
			_play("Running_A" if running else "Walking_A")
		else:
			_play("Idle")
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var rig: Array = VIEW_RIG[view]
	_distance = lerpf(_distance, rig[0], clampf(delta * 5.0, 0.0, 1.0))
	var pitch: float = _pitch if view <= View.THIRD else rig[1]
	if view == View.THIRD and absf(_pitch - rig[1]) > 0.9:
		_pitch = rig[1]
	_pivot.rotation = Vector3(lerp_angle(_pivot.rotation.x, pitch, clampf(delta * 6.0, 0.0, 1.0)), _yaw, 0)
	camera.position = Vector3(0, 0, _distance)
	# Keep the camera above the terrain.
	var cp := camera.global_position
	var floor_h := WorldGen.height(cp.x, cp.z) + 0.6
	if cp.y < floor_h:
		camera.global_position.y = floor_h


func attack() -> void:
	if _attack_cooldown > 0.0 or dead:
		return
	_attack_cooldown = 0.55
	_action = 0.5
	_anim.stop()
	_play("1H_Melee_Attack_Slice_Horizontal", 1.7)
	if _viewmodel.visible:
		var t := create_tween()
		t.tween_property(_viewmodel, "rotation", Vector3(deg_to_rad(-20), deg_to_rad(70), deg_to_rad(30)), 0.1)
		t.tween_property(_viewmodel, "rotation", VIEWMODEL_REST, 0.25)
	get_tree().create_timer(0.18).timeout.connect(_resolve_hit)


func _resolve_hit() -> void:
	var fwd := forward() if view == View.FIRST else _model.global_transform.basis.z
	for enemy in get_tree().get_nodes_in_group("team1"):
		var to: Vector3 = (enemy as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() < 2.4 and fwd.dot(to.normalized()) > 0.25:
			enemy.take_damage(18, self)


func take_damage(amount: int, _from: Node = null) -> void:
	if dead or _hurt_cooldown > 0.0:
		return
	_hurt_cooldown = 0.4
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health == 0:
		dead = true
		_action = 3.0
		_play("Death_A")
		Game.say("You fall... and wake in the village, bruised.")
		await get_tree().create_timer(3.0).timeout
		global_position = spawn_point
		health = max_health
		dead = false
		health_changed.emit(health, max_health)
	else:
		_action = 0.3
		_play("Hit_A", 1.5)


func nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_d := 3.2
	for node in get_tree().get_nodes_in_group("interactable"):
		var d := global_position.distance_to((node as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _play(anim_name: String, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if _anim.current_animation != anim_name or not _anim.is_playing():
		_anim.play(anim_name, 0.12)
	_anim.speed_scale = speed
