class_name Player
extends CharacterBody3D
## The player character plus the four-scale camera:
##   FIRST   — through the eyes, sword in hand
##   THIRD   — close over-the-shoulder exploration
##   TOWN    — pulled back to see a whole village
##   COMMAND — high above the army, still controlling the same character
##
## Melee: 4-hit combo with input buffering and a finisher, target assist,
## shield block (stamina), dodge roll with invulnerability frames, hit-stop
## and camera shake. Animations layer through CharacterAnimator so attacks
## play on the upper body while the legs keep moving.

signal health_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal view_changed(view: int)

enum View { FIRST, THIRD, TOWN, COMMAND }
const VIEW_NAMES := ["First person", "Third person", "Town view", "Command view"]
## [distance, pitch] per view.
const VIEW_RIG := [[0.0, -0.1], [5.5, -0.32], [26.0, -0.72], [85.0, -1.2]]
const VIEWMODEL_REST := Vector3(-0.5, 0.15, -0.35)

const WALK := 4.2
const RUN := 7.0
const GRAVITY := 24.0
const WADE_LIMIT := 1.4          # metres of water the player will walk into
const MAX_STAMINA := 100.0
const COMBO := [
	{"anim": "1H_Melee_Attack_Chop", "damage": 14, "lock": 0.42, "hit": 0.2, "speed": 1.7, "cost": 10.0},
	{"anim": "1H_Melee_Attack_Slice_Diagonal", "damage": 14, "lock": 0.42, "hit": 0.18, "speed": 1.7, "cost": 10.0},
	{"anim": "1H_Melee_Attack_Slice_Horizontal", "damage": 18, "lock": 0.45, "hit": 0.2, "speed": 1.6, "cost": 12.0},
	{"anim": "1H_Melee_Attack_Stab", "damage": 30, "lock": 0.6, "hit": 0.26, "speed": 1.4, "cost": 16.0, "knockback": 7.0},
]
const COMBO_WINDOW := 0.45

var max_health := 120
var health := 120
var stamina := MAX_STAMINA
var dead := false
var team := 0
var touch_move := Vector2.ZERO
var view := View.THIRD
var camera: Camera3D
var spawn_point := Vector3.ZERO
var blocking := false

var _yaw := 0.0
var _pitch := -0.32
var _distance := 5.5
var _pivot: Node3D
var _model: Node3D
var _animator: CharacterAnimator
var _viewmodel: Node3D
var _shake := CameraShake.new()
var _look_target: Node3D
var _combo := -1
var _swing := 0.0
var _combo_window := 0.0
var _buffered := false
var _dodge := 0.0
var _dodge_dir := Vector3.ZERO
var _invulnerable := 0.0
var _stunned := 0.0
var _hurt_cooldown := 0.0
var _stamina_delay := 0.0
var _impulse := Vector3.ZERO


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
	# Nearby embodied residents use layer 2. Keep the player on the default
	# world layer and include both layers in the movement mask.
	collision_layer = 1
	collision_mask = 1 | 2
	_model = Node3D.new()
	add_child(_model)
	var body := Assets.character("Knight", 1.8, ["1H_Sword", "Round_Shield"])
	_model.add_child(body)
	_animator = CharacterAnimator.new(body, RUN)
	_add_head_look(body)
	_pivot = Node3D.new()
	_pivot.position.y = 1.55
	add_child(_pivot)
	apply_age()
	Life.grown.connect(func(_age: int) -> void: apply_age())
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


## Procedural head tracking: the head turns toward the nearest enemy or person.
func _add_head_look(body: Node3D) -> void:
	var skeleton: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	if skeleton.find_bone("head") < 0:
		return   # UE-style rig: head axes differ; head tracking to be tuned for it later
	_look_target = Node3D.new()
	add_child(_look_target)
	var look := LookAtModifier3D.new()
	look.bone_name = "head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.use_angle_limitation = true
	look.symmetry_limitation = true
	look.primary_limit_angle = deg_to_rad(140)
	look.secondary_limit_angle = deg_to_rad(70)
	look.duration = 0.25
	look.influence = 0.85
	skeleton.add_child(look)
	look.target_node = look.get_path_to(_look_target)


## Horizontal direction the camera looks: "forward" for movement and formations.
func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


func facing() -> Vector3:
	return _model.global_transform.basis.z


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


func _input_dir() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	input = input.limit_length(1.0)
	return Vector3(input.x, 0, input.y).rotated(Vector3.UP, _yaw)


func _physics_process(delta: float) -> void:
	_swing -= delta
	_combo_window -= delta
	_dodge -= delta
	_invulnerable -= delta
	_stunned -= delta
	_hurt_cooldown -= delta
	_stamina_delay -= delta

	var dir := Vector3.ZERO if dead or _stunned > 0.0 else _input_dir()
	blocking = Input.is_action_pressed("block") and stamina > 0.0 and _dodge <= 0.0 and not dead and _stunned <= 0.0
	_animator.set_blocking(blocking)
	if _swing <= 0.0 and _buffered:
		_buffered = false
		_start_swing()

	var running := (Input.is_action_pressed("sprint") or touch_move.length() > 0.92 or view >= View.TOWN) and not blocking
	var speed := (RUN if running else WALK) * Life.needs.speed()
	if blocking:
		speed = WALK * 0.5
	if _swing > 0.0:
		speed *= 0.4
	# Water: wade slowly past knee depth, and never walk into water deeper than chest height.
	var wade := WorldGen.water_depth(global_position.x, global_position.z)
	if wade > 0.5:
		speed *= lerpf(0.65, 0.35, clampf((wade - 0.5) / 0.9, 0.0, 1.0))
	var target := dir * speed
	if _dodge > 0.0:
		target = _dodge_dir * lerpf(4.0, 12.0, clampf(_dodge / 0.45, 0.0, 1.0))
	if target.length() > 0.05:
		var ahead := global_position + target.normalized() * 0.8
		var deep := WorldGen.water_depth(ahead.x, ahead.z)
		if deep > WADE_LIMIT and deep >= wade:
			target = Vector3.ZERO
	velocity.x = lerpf(velocity.x, target.x, 12.0 * delta) + _impulse.x
	velocity.z = lerpf(velocity.z, target.z, 12.0 * delta) + _impulse.z
	_impulse = _impulse.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	# Never fall through unloaded/streaming ground.
	var ground := WorldGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0

	if view == View.FIRST or blocking:
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw + PI, 15.0 * delta)
	elif dir.length() > 0.05 and _swing <= 0.0 and _dodge <= 0.0:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), 12.0 * delta)
	_animator.update(delta, Vector2(velocity.x, velocity.z).length() if _dodge <= 0.0 else 0.0)

	if _stamina_delay <= 0.0 and not blocking:
		stamina = minf(stamina + 28.0 * delta * Life.needs.stamina_regen(), MAX_STAMINA * Life.needs.stamina_cap())
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_look_target()
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var rig: Array = VIEW_RIG[view]
	_distance = lerpf(_distance, rig[0], clampf(delta * 5.0, 0.0, 1.0))
	var pitch: float = _pitch if view <= View.THIRD else rig[1]
	if view == View.THIRD and absf(_pitch - rig[1]) > 0.9:
		_pitch = rig[1]
	_pivot.rotation = Vector3(lerp_angle(_pivot.rotation.x, pitch, clampf(delta * 6.0, 0.0, 1.0)), _yaw, 0)
	camera.position = Vector3(0, 0, _distance)
	camera.rotation = _shake.step(delta)
	var cp := camera.global_position
	var floor_h := WorldGen.height(cp.x, cp.z) + 0.6
	var water_h := WorldGen.water_level_at(cp.x, cp.z)
	if not is_nan(water_h):
		floor_h = maxf(floor_h, water_h + 0.4)   # keep the camera above the surface
	if cp.y < floor_h:
		camera.global_position.y = floor_h


func _update_look_target() -> void:
	if _look_target == null:
		return
	var best: Node3D = _nearest_enemy(12.0, -1.0)
	if best == null:
		for v in get_tree().get_nodes_in_group("villager"):
			if (v as Node3D).global_position.distance_to(global_position) < 5.0:
				best = v
				break
	var p := best.global_position + Vector3(0, 1.5, 0) if best else global_position + facing() * 5.0 + Vector3(0, 1.6, 0)
	_look_target.global_position = _look_target.global_position.lerp(p, 0.2)


# --- Combat -----------------------------------------------------------------------

func attack() -> void:
	if dead or _stunned > 0.0 or _dodge > 0.0:
		return
	if _swing > 0.0:
		_buffered = true          # queue the next hit of the combo
		return
	_start_swing()


func _start_swing() -> void:
	_combo = (_combo + 1) % COMBO.size() if _combo_window > 0.0 else 0
	var step: Dictionary = COMBO[_combo]
	var weak: bool = stamina < step["cost"]
	_spend(step["cost"])
	# Target assist: snap toward an enemy roughly in front.
	var target := _nearest_enemy(3.8, 0.1)
	if target:
		var to := target.global_position - global_position
		_model.rotation.y = atan2(to.x, to.z)
	_impulse = facing() * 2.5
	_swing = step["lock"]
	_combo_window = step["lock"] + COMBO_WINDOW
	if _combo == COMBO.size() - 1:
		_combo_window = 0.0     # finisher ends the chain
	_animator.play_upper(step["anim"], step["speed"] * (0.7 if weak else 1.0))
	Audio.sfx("swing", null, -4.0)
	if _viewmodel.visible:
		var t := create_tween()
		t.tween_property(_viewmodel, "rotation", Vector3(-0.35, 1.2 * (1 if _combo % 2 == 0 else -1), 0.5), 0.1)
		t.tween_property(_viewmodel, "rotation", VIEWMODEL_REST, 0.25)
	var damage: int = int(step["damage"] * (0.5 if weak else 1.0))
	var knock: float = step.get("knockback", 1.5)
	# Sword arc: tilt alternates with the combo so chops, slices and stabs read differently.
	var tilts := [0.9, -0.9, 0.05, 0.0]
	var yaw := _model.rotation.y
	var arc_col := Color(1.0, 0.9, 0.7) if not weak else Color(0.7, 0.7, 0.75)
	get_tree().create_timer(step["hit"] * 0.55).timeout.connect(func() -> void:
		if is_inside_tree():
			VFX.slash(get_parent(), global_position + Vector3(0, 1.15 * Life.body_scale(), 0), yaw,
				tilts[_combo % tilts.size()], arc_col, 1.6))
	get_tree().create_timer(step["hit"]).timeout.connect(_resolve_hit.bind(damage, knock, _combo == COMBO.size() - 1))


func _resolve_hit(damage: int, knockback: float, finisher: bool) -> void:
	var fwd := forward() if view == View.FIRST else facing()
	var hits := 0
	for enemy in get_tree().get_nodes_in_group("team1"):
		var to: Vector3 = (enemy as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() < 2.6 and fwd.dot(to.normalized()) > 0.2:
			enemy.take_damage(damage, self, to.normalized() * knockback)
			VFX.sparks(get_parent(), (enemy as Node3D).global_position + Vector3(0, 0.8, 0) - to.normalized() * 0.3,
				Color(1.0, 0.72, 0.35), 30 if finisher else 18)
			hits += 1
	if finisher:
		VFX.shockwave(get_parent(), global_position + fwd * 1.2, Color(1.0, 0.85, 0.45), 3.2)
	if hits > 0:
		Audio.sfx("hit")
		_hit_stop(0.09 if finisher else 0.05)
		_shake.add(0.45 if finisher else 0.22)


func dodge() -> void:
	if dead or _dodge > 0.0 or _stunned > 0.0 or stamina < 15.0:
		return
	_spend(22.0)
	var dir := _input_dir()
	var backward := dir.length() < 0.1
	_dodge_dir = -facing() if backward else dir.normalized()
	if not backward:
		_model.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	_dodge = 0.45
	_invulnerable = 0.35
	_swing = 0.0
	_buffered = false
	_animator.play_full("Dodge_Backward" if backward else "Dodge_Forward", 1.5)


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead or _invulnerable > 0.0 or _hurt_cooldown > 0.0:
		return
	var from_front := true
	if from is Node3D:
		var to := (from as Node3D).global_position - global_position
		to.y = 0.0
		from_front = facing().dot(to.normalized()) > 0.3
	if blocking and from_front:
		_spend(amount * 1.6)
		_impulse = -facing() * 3.0
		_shake.add(0.15)
		if stamina <= 0.0:
			_stunned = 0.9          # guard broken
			_animator.play_full("Hit_B", 1.2)
			Game.say("Guard broken!")
		else:
			_animator.play_upper("Block_Hit", 1.5)
			Audio.sfx("clash")
			amount = int(amount * 0.15)
			if amount == 0:
				return
	_hurt_cooldown = 0.35
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	_impulse = knockback
	_shake.add(0.3)
	if health == 0:
		_die()
	elif not blocking:
		_animator.play_upper("Hit_A", 1.5)


func _die() -> void:
	dead = true
	_animator.play_terminal("Death_A")
	Game.say("You fall... and wake in the village, bruised.")
	await get_tree().create_timer(3.0).timeout
	global_position = spawn_point
	health = max_health
	stamina = MAX_STAMINA
	dead = false
	_animator.set_active(true)
	health_changed.emit(health, max_health)


## Children are smaller; the body and camera height follow Life.body_scale().
func apply_age() -> void:
	var k := Life.body_scale()
	_model.scale = Vector3.ONE * k
	_pivot.position.y = 1.55 * k


func heal(amount: int) -> void:
	if dead:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


func set_health(value: int) -> void:
	health = clampi(value, 1, max_health)
	health_changed.emit(health, max_health)


func _spend(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_delay = 0.8


## Brief freeze on impact: sells the weight of a hit.
func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _nearest_enemy(max_dist: float, min_dot: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for enemy in get_tree().get_nodes_in_group("team1"):
		var to: Vector3 = (enemy as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and (min_dot < -0.99 or facing().dot(to / maxf(d, 0.01)) > min_dot):
			best_d = d
			best = enemy
	return best


func nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_d := 3.2
	for node in get_tree().get_nodes_in_group("interactable"):
		var d := global_position.distance_to((node as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best
