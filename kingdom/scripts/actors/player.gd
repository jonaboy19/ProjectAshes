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
##
## Movement: separate acceleration / braking / turn rates, a committed brake
## on reversals, turn-in-place before setting off, a slight lean, coyote
## grounding, one-off impulses that stop at walls, and buffered attack/dodge
## presses with cancel windows (swing recovery -> swing, swing -> roll outside
## the hit frames, roll tail -> attack).

signal health_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal view_changed(view: int)

enum View { FIRST, THIRD, TOWN, COMMAND }
const VIEW_NAMES := ["First person", "Third person", "Town view", "Command view"]
## [distance, pitch] per view.
const VIEW_RIG := [[0.0, -0.1], [5.5, -0.32], [26.0, -0.72], [85.0, -1.2]]
const VIEWMODEL_REST := Vector3(-0.5, 0.15, -0.35)

const WALK := 2.4
const RUN := 6.5
## Movement response (LOCOMOTION_START_STOP_TURN_CONTRACT.md): acceleration,
## braking and turning are separate rules instead of one smoothing constant.
## Acceleration is strongest from a standstill (the first step answers the
## stick at once) and eases off toward top speed, so a run still builds.
const ACCEL_START := 34.0        # m/s² at rest
const ACCEL_TOP := 11.0          # m/s² near RUN
const MOVE_BRAKE := 30.0         # m/s² when the stick is released or the target speed drops
const PIVOT_BRAKE := 42.0        # m/s² when reversing out of a run: plant, then go
const PIVOT_ANGLE := 2.3         # rad (~130°) between travel and stick that triggers a pivot
const PIVOT_EXIT_SPEED := 1.2    # a pivot sets off in the new direction below this speed
## Travel direction swings toward the stick at a bounded rate; facing turns
## faster than travel, so the body leads a turn instead of sliding sideways.
const TRAVEL_TURN_WALK := 16.0   # rad/s
const TRAVEL_TURN_RUN := 9.0
const FACE_TURN_IDLE := 20.0     # rad/s: 180° turn on the spot in ~0.17 s
const FACE_TURN_RUN := 11.0
const FACE_SHARPNESS := 16.0
## Air control after the coyote window, as a fraction of ground response.
const AIR_CONTROL := 0.3
const COYOTE_TIME := 0.12
## Lean into turns (roll) and against acceleration (pitch). Cosmetic only.
const LEAN_ROLL_MAX := 0.13
const LEAN_PITCH_MAX := 0.06
## Impulses are one-off velocity kicks (m/s) that then decay; they are never
## re-added each tick (PLAYER_MECHANICS_RESPONSE_REVIEW.md).
const IMPULSE_DECEL := 12.0
const ATTACK_LUNGE := 3.0
const BLOCK_PUSH := 3.0
const FLINCH_TIME := 0.18        # brief slowdown when hit, legs stay on the ground
## Input buffering and cancel windows.
const ATTACK_BUFFER := 0.35      # s an early attack press is remembered
const DODGE_BUFFER := 0.25
const SWING_CANCEL := 0.22       # last fraction of a swing's recovery that the next swing may cut
const DODGE_ATTACK_CANCEL := 0.12  # s left in a roll when an attack may cut it
const DODGE_CHAIN := 0.06        # s left in a roll when another roll may start
const ACTIVE_BEFORE := 0.03      # s around the hit frame when a dodge waits instead of cancelling
const ACTIVE_AFTER := 0.05
const DODGE_TIME := 0.45
const DODGE_ANIM_RATE := 1.8
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
var _camera_arm: SpringArm3D
var _model: Node3D
var _animator: CharacterAnimator
var _viewmodel: Node3D
var _shake := CameraShake.new()
var _look_target: Node3D
var _combo := -1
var _swing := 0.0
var _swing_cancel := 0.0
var _swing_elapsed := 0.0
var _swing_hit := 0.0
var _swing_id := 0
var _combo_window := 0.0
var _attack_buffer := 0.0
var _dodge_buffer := 0.0
var _dodge := 0.0
var _dodge_dir := Vector3.ZERO
var _invulnerable := 0.0
var _stunned := 0.0
var _hurt_cooldown := 0.0
var _stamina_delay := 0.0
var _impulse := Vector3.ZERO
var _step_distance := 0.0
var _move_dir := Vector3.FORWARD
var _move_speed := 0.0
var _pivoting := false
var _air_time := 0.0
var _flinch := 0.0
var _yaw_rate := 0.0
var _lean := Vector2.ZERO
var _lean_speed := 0.0
var _hit_stop_token := 0
var _hit_stopping := false


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
	# Layer 2 is near villagers; layer 4 is near soldiers and hostile actors.
	collision_mask = 1 | 2 | 4
	# Hold the ground over small drops and slope changes instead of hopping off them.
	floor_snap_length = 0.35
	_model = Node3D.new()
	add_child(_model)
	var body := Assets.character("Player", 1.8, ["1H_Sword", "Round_Shield"])
	_model.add_child(body)
	_animator = CharacterAnimator.new(body, RUN, WALK)
	_add_head_look(body)
	_pivot = Node3D.new()
	_pivot.position.y = 1.55
	add_child(_pivot)
	_camera_arm = SpringArm3D.new()
	_camera_arm.spring_length = _distance
	_camera_arm.margin = 0.18
	_camera_arm.collision_mask = 1
	var camera_sweep := SphereShape3D.new()
	camera_sweep.radius = 0.22
	_camera_arm.shape = camera_sweep
	_camera_arm.add_excluded_object(get_rid())
	_pivot.add_child(_camera_arm)
	apply_age()
	Life.grown.connect(func(_age: int) -> void: apply_age())
	camera = Camera3D.new()
	camera.far = 900.0
	camera.fov = 65.0
	_camera_arm.add_child(camera)
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
	# From the yaw alone: the lean and a child's body scale must not tilt or shrink it.
	var r := _model.global_rotation.y
	return Vector3(sin(r), 0.0, cos(r))


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
	_swing_elapsed += delta
	_combo_window -= delta
	_dodge -= delta
	_invulnerable -= delta
	_stunned -= delta
	_hurt_cooldown -= delta
	_stamina_delay -= delta
	_flinch -= delta
	_attack_buffer -= delta
	_dodge_buffer -= delta

	var dir := Vector3.ZERO if dead or _stunned > 0.0 else _input_dir()
	blocking = Input.is_action_pressed("block") and stamina > 0.0 and _dodge <= 0.0 and not dead and _stunned <= 0.0
	_animator.set_blocking(blocking)
	_consume_buffers()

	var running := (Input.is_action_pressed("sprint") or touch_move.length() > 0.92 or view >= View.TOWN) and not blocking
	var speed := (RUN if running else WALK) * Life.needs.speed()
	if blocking:
		speed = WALK * 0.5
	if _swing > 0.0:
		speed *= 0.4
	if _flinch > 0.0:
		speed *= 0.5
	# Water: wade slowly past knee depth, and never walk into water deeper than chest height.
	var wade := WorldGen.water_depth(global_position.x, global_position.z)
	if wade > 0.5:
		speed *= lerpf(0.65, 0.35, clampf((wade - 0.5) / 0.9, 0.0, 1.0))
	var target := dir * speed
	if target.length() > 0.05:
		var ahead := global_position + target.normalized() * 0.8
		var deep := WorldGen.water_depth(ahead.x, ahead.z)
		if deep > WADE_LIMIT and deep >= wade:
			target = Vector3.ZERO
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	var grounded := _air_time <= COYOTE_TIME
	if _dodge > 0.0:
		# The roll owns movement: its own speed curve, no input smoothing.
		var roll_speed := lerpf(4.0, 12.0, clampf(_dodge / DODGE_TIME, 0.0, 1.0))
		_move_dir = _dodge_dir
		_move_speed = roll_speed
	else:
		_steer(target, delta, 1.0 if grounded else AIR_CONTROL)
	var planar := _move_dir * _move_speed + _impulse
	velocity.x = planar.x
	velocity.z = planar.z
	_impulse = _impulse.move_toward(Vector3.ZERO, IMPULSE_DECEL * delta)
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_resolve_contacts()
	# Never fall through unloaded/streaming ground.
	var ground := WorldGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0

	_update_facing(dir, delta)
	var real := get_real_velocity()
	var travel := Vector3(real.x, 0.0, real.z)
	_animator.update(delta, travel.length() if _dodge <= 0.0 else 0.0, travel)
	_update_lean(delta)
	_update_footsteps(delta, dir, grounded)

	if _stamina_delay <= 0.0 and not blocking:
		stamina = minf(stamina + 28.0 * delta * Life.needs.stamina_regen(), MAX_STAMINA * Life.needs.stamina_cap())
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_look_target()
	_update_camera(delta)


## Body response: speed and travel direction are tuned separately. `control`
## scales every rate (reduced in the air).
func _steer(target: Vector3, delta: float, control: float) -> void:
	var want_speed := target.length()
	if want_speed < 0.05:
		_pivoting = false
		_move_speed = move_toward(_move_speed, 0.0, MOVE_BRAKE * control * delta)
		return
	var want_dir := target / want_speed
	var run_t := clampf(_move_speed / RUN, 0.0, 1.0)
	if _move_speed < 0.3:
		_move_dir = want_dir   # from rest, go where the stick points; the body turns to follow
	else:
		var angle := _move_dir.signed_angle_to(want_dir, Vector3.UP)
		if absf(angle) > PIVOT_ANGLE:
			_pivoting = true
		if _pivoting:
			# Reversal: brake hard along the old line (no wide arc), then set off.
			_move_speed = move_toward(_move_speed, 0.0, PIVOT_BRAKE * control * delta)
			if _move_speed < PIVOT_EXIT_SPEED or absf(angle) < PIVOT_ANGLE * 0.5:
				_pivoting = false
				_move_dir = want_dir
			return
		var turn_rate := lerpf(TRAVEL_TURN_WALK, TRAVEL_TURN_RUN, run_t) * control
		_move_dir = _move_dir.rotated(Vector3.UP, clampf(angle, -turn_rate * delta, turn_rate * delta)).normalized()
	if want_speed > _move_speed:
		var accel := lerpf(ACCEL_START, ACCEL_TOP, run_t) * control
		# Starting against the facing: turn on the spot first, then drive.
		if _move_speed < WALK and view != View.FIRST and not blocking:
			var align := facing().dot(want_dir)
			accel *= clampf(0.5 + 0.5 * align, 0.3, 1.0)
		_move_speed = move_toward(_move_speed, want_speed, accel * delta)
	else:
		_move_speed = move_toward(_move_speed, want_speed, MOVE_BRAKE * control * delta)


## After the physics step: walls stop momentum and impulses instead of letting
## the body (and its run cycle) keep pressing into them.
func _resolve_contacts() -> void:
	if not is_on_wall():
		return
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var into := _impulse.dot(n)
		if into < 0.0:
			_impulse -= n * into
	var real := get_real_velocity()
	_move_speed = minf(_move_speed, Vector2(real.x, real.z).length() + 0.5)


func _update_facing(dir: Vector3, delta: float) -> void:
	var before := _model.rotation.y
	var want := before
	var rate := 0.0
	if view == View.FIRST or blocking:
		want = _yaw + PI
		rate = FACE_TURN_IDLE
	elif dir.length() > 0.05 and _swing <= 0.0 and _dodge <= 0.0 and _stunned <= 0.0:
		want = atan2(dir.x, dir.z)
		rate = lerpf(FACE_TURN_IDLE, FACE_TURN_RUN, clampf(_move_speed / RUN, 0.0, 1.0))
	if rate > 0.0:
		var diff := angle_difference(before, want)
		var step := clampf(diff * (1.0 - exp(-FACE_SHARPNESS * delta)), -rate * delta, rate * delta)
		_model.rotation.y = before + step
	_yaw_rate = angle_difference(before, _model.rotation.y) / maxf(delta, 0.0001)


## A small lean into turns and against speed changes. Pivots at the feet (the
## model origin), so the soles stay on the ground.
func _update_lean(delta: float) -> void:
	var roll := 0.0
	var pitch := 0.0
	if _dodge <= 0.0 and not dead and view != View.FIRST:
		var speed_t := clampf(_move_speed / RUN, 0.0, 1.0)
		# Lateral acceleration = speed × yaw rate; lean toward the inside of the turn.
		roll = clampf(-_yaw_rate * _move_speed * 0.012, -LEAN_ROLL_MAX, LEAN_ROLL_MAX) * speed_t
		var accel := (_move_speed - _lean_speed) / maxf(delta, 0.0001)
		pitch = clampf(accel * 0.002, -LEAN_PITCH_MAX, LEAN_PITCH_MAX)
	_lean_speed = _move_speed
	var a := 1.0 - exp(-10.0 * delta)
	_lean = _lean.lerp(Vector2(pitch, roll), a)
	_model.rotation.x = _lean.x
	_model.rotation.z = _lean.y


## Step sounds land on the gait's footfalls (the animator's shared walk/run phase).
func _update_footsteps(delta: float, input_dir: Vector3, grounded: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var footfall := _animator.consume_footstep()
	if input_dir.length_squared() < 0.01 or speed < 0.6 or _dodge > 0.0 or dead or not grounded:
		_step_distance = 0.0
		return
	_step_distance += speed * delta
	# Fallback spacing in case the animator is inactive: never go silent over ~1.6 m.
	if footfall or _step_distance > 1.6:
		_step_distance = 0.0
		Audio.sfx("step_" + WorldGen.footstep_surface(global_position.x, global_position.z), global_position, -6.0)


func _update_camera(delta: float) -> void:
	var rig: Array = VIEW_RIG[view]
	_distance = lerpf(_distance, rig[0], 1.0 - exp(-5.0 * delta))
	var pitch: float = _pitch if view <= View.THIRD else rig[1]
	if view == View.THIRD and absf(_pitch - rig[1]) > 0.9:
		_pitch = rig[1]
	_pivot.rotation = Vector3(lerp_angle(_pivot.rotation.x, pitch, 1.0 - exp(-6.0 * delta)), _yaw, 0)
	_camera_arm.spring_length = _distance
	camera.rotation = _shake.step(delta)
	var cp := camera.global_position
	var floor_h := WorldGen.height(cp.x, cp.z) + 0.6
	var water_h := WorldGen.water_level_at(cp.x, cp.z)
	if not is_nan(water_h):
		floor_h = maxf(floor_h, water_h + 0.4)   # keep the camera above the surface
	if cp.y < floor_h:
		camera.global_position.y = floor_h
	# Keep the chase camera out of walls, stalls and roofs: pull it in front of whatever
	# lies between the head and the camera (playtest: camera inside the guild hall / stalls).
	if view == View.THIRD and InteriorDoor.active == null:
		var from := _pivot.global_position
		var q := PhysicsRayQueryParameters3D.create(from, camera.global_position)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			camera.global_position = (hit["position"] as Vector3) + (from - camera.global_position).normalized() * 0.3


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
	if dead:
		return
	if _can_attack():
		_start_swing()
	else:
		_attack_buffer = ATTACK_BUFFER   # early press: fire at the next opening


func dodge() -> void:
	if dead:
		return
	if _can_dodge():
		_start_dodge()
	elif stamina >= 15.0:
		_dodge_buffer = DODGE_BUFFER


## An attack may start when idle, in the cancel tail of the previous swing, or
## as a roll finishes.
func _can_attack() -> bool:
	return not dead and _stunned <= 0.0 and _dodge <= DODGE_ATTACK_CANCEL and _swing <= _swing_cancel


## A roll may cut a swing's startup or recovery, but not its hit frames (it
## waits for them), and may chain from the very end of another roll.
func _can_dodge() -> bool:
	if dead or _stunned > 0.0 or stamina < 15.0 or _dodge > DODGE_CHAIN:
		return false
	return not _in_active_frames()


func _in_active_frames() -> bool:
	return _swing > 0.0 and _swing_elapsed >= _swing_hit - ACTIVE_BEFORE and _swing_elapsed <= _swing_hit + ACTIVE_AFTER


func _consume_buffers() -> void:
	if _dodge_buffer > 0.0 and _can_dodge():
		_dodge_buffer = 0.0
		_attack_buffer = 0.0
		_start_dodge()
	elif _attack_buffer > 0.0 and _can_attack():
		_attack_buffer = 0.0
		_start_swing()


func _start_swing() -> void:
	if _dodge > 0.0:
		_dodge = 0.0                 # roll attack: the swing takes over the roll's tail
		_animator.stop_full()
	_combo = (_combo + 1) % COMBO.size() if _combo_window > 0.0 else 0
	var step: Dictionary = COMBO[_combo]
	var weak: bool = stamina < step["cost"]
	_spend(step["cost"])
	# Target assist: snap toward an enemy roughly in front.
	var target := _nearest_enemy(3.8, 0.1)
	if target:
		var to := target.global_position - global_position
		_model.rotation.y = atan2(to.x, to.z)
	_kick(facing() * ATTACK_LUNGE)
	_swing_id += 1
	_swing = step["lock"]
	_swing_elapsed = 0.0
	_swing_hit = step["hit"]
	_swing_cancel = step["lock"] * SWING_CANCEL
	_combo_window = step["lock"] + COMBO_WINDOW
	if _combo == COMBO.size() - 1:
		_combo_window = 0.0     # finisher ends the chain
		_swing_cancel = 0.0     # and commits to its full recovery
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
	var id := _swing_id
	var combo := _combo
	get_tree().create_timer(step["hit"] * 0.55).timeout.connect(func() -> void:
		if is_inside_tree() and id == _swing_id:
			VFX.slash(get_parent(), global_position + Vector3(0, 1.15 * Life.body_scale(), 0), yaw,
				tilts[combo % tilts.size()], arc_col, 1.6))
	get_tree().create_timer(step["hit"]).timeout.connect(_resolve_hit.bind(damage, knock, _combo == COMBO.size() - 1, id))


func _resolve_hit(damage: int, knockback: float, finisher: bool, id := -1) -> void:
	if id >= 0 and id != _swing_id:
		return    # the swing was cancelled (dodge) before its hit frame
	if dead or not is_inside_tree():
		return
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


func _start_dodge() -> void:
	_spend(22.0)
	var dir := _input_dir()
	var backward := dir.length() < 0.1
	_dodge_dir = -facing() if backward else dir.normalized()
	if not backward:
		_model.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	_dodge = DODGE_TIME
	_invulnerable = 0.35
	if _swing > 0.0:
		_swing_id += 1          # a pending hit frame no longer lands
		_animator.stop_upper()
	_swing = 0.0
	_attack_buffer = 0.0
	_impulse = Vector3.ZERO
	_animator.play_full("Dodge_Backward" if backward else "Dodge_Forward", DODGE_ANIM_RATE)
	get_tree().create_timer(DODGE_TIME).timeout.connect(_end_dodge_anim)


## When the roll's movement ends and the player is already steering, hand the
## legs straight back to locomotion instead of finishing the get-up on the spot.
func _end_dodge_anim() -> void:
	if _dodge <= 0.0 and _input_dir().length() > 0.1 and not dead:
		_animator.stop_full()


## One-off horizontal velocity kick. It replaces any kick still decaying.
func _kick(v: Vector3) -> void:
	_impulse = Vector3(v.x, 0.0, v.z)


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
		_kick(-facing() * BLOCK_PUSH)
		_shake.add(0.15)
		if stamina <= 0.0:
			_stunned = 0.9          # guard broken
			_swing = 0.0
			_swing_id += 1
			# Heavy stagger with both feet planted (CharacterAnimator.PREFERRED_CLIPS).
			_animator.play_full("Hit_B", 1.3)
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
	if knockback.length_squared() > 0.0001:
		_kick(knockback)
	_shake.add(0.3)
	if health == 0:
		_die()
	elif not blocking:
		_flinch = FLINCH_TIME
		_animator.play_upper("Hit_A", 1.5)


func _die() -> void:
	dead = true
	# Death_A resolves to the long Mesh2Motion stagger/fall clip and can outlast
	# the respawn timer. Use the short terminal fall for the playable character.
	_animator.play_terminal("Death01")
	Game.say("You fall... and wake in the village, bruised.")
	await get_tree().create_timer(3.0).timeout
	global_position = spawn_point
	_move_speed = 0.0
	_impulse = Vector3.ZERO
	_attack_buffer = 0.0
	_dodge_buffer = 0.0
	health = max_health
	stamina = MAX_STAMINA
	dead = false
	_animator.set_active(true)
	health_changed.emit(health, max_health)


## Children are smaller; the body and camera height follow Life.body_scale().
func apply_age() -> void:
	var k := Life.body_scale()
	_model.scale = Vector3.ONE * k
	if _animator:
		_animator.stride_scale = k   # a child's shorter legs cover less ground per step
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
	_hit_stop_token += 1
	var token := _hit_stop_token
	_hit_stopping = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hit_stop_token:   # an overlapping, later hit-stop restores time itself
		_hit_stopping = false
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	if _hit_stopping:
		_hit_stopping = false
		Engine.time_scale = 1.0   # never leave the world frozen if removed mid hit-stop


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
