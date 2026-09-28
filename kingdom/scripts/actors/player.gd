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
##
## Traversal and combat extras:
##   Riding   — interact beside a horse mounts it (mount_controller.gd drives
##              it; this body still does the physics), interact again dismounts.
##   Swimming — past chest depth the body floats at the surface, drains
##              stamina, and hurts slowly once stamina is gone.
##   Lock-on  — `lock_on` targets the enemy in front; the camera frames both,
##              movement strafes around the target, swings face it. A look
##              flick (drag or right stick) switches target, a second press
##              releases. Releases on death or past LOCK_BREAK.
##   Parry    — a block raised within PARRY_WINDOW before a hit lands cancels
##              it, staggers the attacker and empowers the next swing.
##   Crouch   — `crouch` toggles a slow, quiet stance; noise_radius() is what
##              wolves, monsters and wary game hear.

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
const MAX_STAMINA := 100.0
## Only static world geometry (terrain, buildings, props: layer 1) may pull the
## chase camera in. Villagers (2), soldiers and enemies (4) never do.
const CAMERA_MASK := 1
const BODY_RADIUS := 0.35
## Riding.
const MountController := preload("res://scripts/actors/mount_controller.gd")
## Foot IK on slopes and steps, torso and weapon/shield secondary motion.
const ProceduralRig := preload("res://scripts/actors/procedural_rig.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const MOUNTED_RADIUS := 0.6      # wider body while mounted so the horse's chest meets walls
const MOUNTED_CAMERA := 7.5      # third-person distance on horseback
## Swimming. Depths are for a full-size body and scale with Life.body_scale().
const SWIM_ENTER := 1.3          # water deeper than this (chest) floats the body
const SWIM_EXIT := 1.05          # shallower than this puts the feet back down
const SWIM_FLOAT := 1.25         # body origin sits this far under the surface
const SWIM_SPEED := 2.2
const SWIM_DRAIN := 3.0          # stamina/s treading water
const SWIM_DRAIN_MOVING := 4.5   # extra stamina/s while stroking
const DROWN_DPS := 4.0           # health/s once stamina is gone
## Crouch / stealth.
const CROUCH_SPEED := 1.5
const NOISE_CROUCH := 4.0
const NOISE_WALK := 10.0
const NOISE_RUN := 18.0
## Lock-on.
const LOCK_RANGE := 18.0
const LOCK_BREAK := 25.0
const LOCK_STRAFE_SPEED := 1.9   # strafing pace; sprint breaks into a normal run
const LOCK_FLICK := 70.0         # px of quick horizontal drag that switches target
const LOCK_STICK := 0.7          # right-stick deflection that switches target
const LOCK_PITCH := -0.26
## Parry.
const PARRY_WINDOW := 0.18       # s after raising the block during which a hit is parried
const PARRY_REARM := 0.3         # s the block must be down before a new raise can parry (no mashing)
const PARRY_BONUS_TIME := 1.0
const PARRY_DAMAGE := 1.5
const PARRY_HIT_STOP := 0.12
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
var swimming := false
var crouching := false

var _yaw := 0.0
var _pitch := -0.32
var _distance := 5.5
var _pivot: Node3D
var _camera_arm: SpringArm3D
var _model: Node3D
var _animator: CharacterAnimator
var _rig: Node
var _ragdoll: Node
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
var _capsule: CapsuleShape3D
var _mount: MountController
var _drown := 0.0
var _drown_warned := false
var _lock: Node3D
var _lock_marker: MeshInstance3D
var _lock_height := 2.0
var _flick := 0.0
var _flick_cooldown := 0.0
var _stick_flicked := false
var _strafing := false
var _block_age := 99.0
var _block_down := 99.0
var _was_blocking := false
var _parry_bonus := 0.0


func _ready() -> void:
	add_to_group("team0")
	add_to_group("player")
	var shape := CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = BODY_RADIUS
	_capsule.height = 1.7
	shape.shape = _capsule
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
	_animator = CharacterAnimator.new(body, RUN, WALK, "Walking_A", "Running_A", "Idle", true)
	_ragdoll = Ragdoll.attach(self, body, [_animator.tree, _animator.player])
	_add_head_look(body)
	# After the look-at: the rig orders the skeleton's modifiers as
	# animation -> look-at -> foot IK -> secondary motion.
	_rig = ProceduralRig.attach(body, self, true)
	_animator.rig = _rig
	_pivot = Node3D.new()
	_pivot.position.y = 1.55
	add_child(_pivot)
	_camera_arm = SpringArm3D.new()
	_camera_arm.spring_length = _distance
	_camera_arm.margin = 0.18
	_camera_arm.collision_mask = CAMERA_MASK
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
	_ensure_actions()
	_build_lock_marker()


## Actions this controller adds when the project has not defined them.
## (Tab is already the journal, so lock-on uses Q and the middle mouse button.)
func _ensure_actions() -> void:
	var wanted := {
		"lock_on": [KEY_Q, MOUSE_BUTTON_MIDDLE, JOY_BUTTON_RIGHT_STICK],
		"crouch": [KEY_C, JOY_BUTTON_LEFT_STICK],
	}
	for action: String in wanted:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var codes: Array = wanted[action]
		var ev_key := InputEventKey.new()
		ev_key.physical_keycode = codes[0]
		InputMap.action_add_event(action, ev_key)
		if action == "lock_on":
			var mb := InputEventMouseButton.new()
			mb.button_index = codes[1]
			InputMap.action_add_event(action, mb)
		var jb := InputEventJoypadButton.new()
		jb.button_index = codes[codes.size() - 1]
		InputMap.action_add_event(action, jb)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on"):
		toggle_lock()
	elif event.is_action_pressed("crouch"):
		toggle_crouch()
	elif event.is_action_pressed("interact"):
		# Runs before main.gd's handler (deeper in the tree), which ignores horses.
		if _menu_open():
			return
		if _mount:
			toggle_mount()
		else:
			var target := nearest_interactable()
			if target and target.has_method("rideable") and target.call("rideable"):
				toggle_mount(target)


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and (hud as Object).has_method("is_menu_open") and (hud as Object).call("is_menu_open")


## Procedural head tracking: the head turns toward the nearest enemy or person.
func _add_head_look(body: Node3D) -> void:
	var skeleton: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	# The UAL rig names it "Head" (its +Z faces forward, like the KayKit "head").
	var head := "Head" if skeleton.find_bone("Head") >= 0 else "head"
	if skeleton.find_bone(head) < 0:
		return
	_look_target = Node3D.new()
	add_child(_look_target)
	var look := LookAtModifier3D.new()
	look.bone_name = head
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
	if is_instance_valid(_lock):
		# Locked: the camera frames the target by itself; a quick sideways drag switches.
		_flick += relative.x
		if absf(_flick) > LOCK_FLICK and _flick_cooldown <= 0.0:
			_switch_lock(signf(_flick))
			_flick = 0.0
			_flick_cooldown = 0.35
		return
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
	_parry_bonus -= delta
	_flick_cooldown -= delta
	_flick *= exp(-8.0 * delta)
	_update_lock(delta)
	if _mount != null:
		_physics_mounted(delta)
		return

	var dir := Vector3.ZERO if dead or _stunned > 0.0 else _input_dir()
	var wade := WorldGen.water_depth(global_position.x, global_position.z)
	_update_swim_state(wade)
	blocking = Input.is_action_pressed("block") and stamina > 0.0 and _dodge <= 0.0 and not dead \
			and _stunned <= 0.0 and not swimming
	_track_block(delta)
	_animator.set_blocking(blocking)
	_consume_buffers()

	var sprint := Input.is_action_pressed("sprint")
	if sprint and crouching and dir.length() > 0.1:
		_set_crouch(false)            # sprinting stands up
	var locked := is_instance_valid(_lock)
	var running := (sprint or (touch_move.length() > 0.92 and not crouching) or view >= View.TOWN) \
			and not blocking and not crouching and (not locked or sprint)
	_strafing = (blocking or (locked and not running)) and not swimming
	_animator.set_strafing(_strafing and not blocking)
	var speed := (RUN if running else WALK) * Life.needs.speed()
	if crouching:
		speed = CROUCH_SPEED * Life.needs.speed()
	if locked and not running:
		speed = minf(speed, LOCK_STRAFE_SPEED)
	if blocking:
		speed = WALK * 0.5
	if _swing > 0.0:
		speed *= 0.4
	if _flinch > 0.0:
		speed *= 0.5
	if swimming:
		speed = SWIM_SPEED
	elif wade > 0.5:
		# Wade slowly past knee depth; past chest depth the body swims instead.
		speed *= lerpf(0.65, 0.35, clampf((wade - 0.5) / 0.8, 0.0, 1.0))
	var target := dir * speed
	_air_time = 0.0 if is_on_floor() or swimming else _air_time + delta
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
	if swimming:
		velocity.y = _swim_vertical(target.length() > 0.1)
	else:
		velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_resolve_contacts()
	_keep_above_ground()

	_update_facing(dir, delta)
	var real := get_real_velocity()
	var travel := Vector3(real.x, 0.0, real.z)
	_animator.update(delta, travel.length() if _dodge <= 0.0 else 0.0, travel)
	if _rig:
		# Feet off the ground: airborne, swimming, rolling, dead. Big hits ease the IK off.
		_rig.call("set_state", travel.length(), is_on_floor(), swimming or dead or _dodge > 0.0,
				_animator.is_full_busy())
	_update_lean(delta)
	_update_footsteps(delta, dir, grounded and not swimming)

	if swimming:
		_swim_stamina(delta, travel.length() > 0.3)
	elif _stamina_delay <= 0.0 and not blocking:
		stamina = minf(stamina + 28.0 * delta * Life.needs.stamina_regen(), MAX_STAMINA * Life.needs.stamina_cap())
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_look_target()
	_update_camera(delta)


## Never fall through unloaded/streaming ground.
func _keep_above_ground() -> void:
	var ground := WorldGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0


# --- Riding -----------------------------------------------------------------------

## Mounts `target` (or the nearest rideable interactable), or dismounts.
func toggle_mount(target: Node3D = null) -> void:
	if _mount:
		_dismount()
		return
	if target == null:
		target = nearest_interactable()
	if target == null or not target.has_method("rideable") or not target.call("rideable"):
		return
	if dead or swimming or _dodge > 0.0 or _stunned > 0.0:
		return
	_release_lock()
	_set_crouch(false)
	if _swing > 0.0:
		_swing_id += 1
	_swing = 0.0
	_attack_buffer = 0.0
	_dodge_buffer = 0.0
	blocking = false
	_animator.set_blocking(false)
	_animator.set_strafing(false)
	_animator.stop_upper()
	_animator.stop_full()
	var horse := MountController.take(target, get_parent())
	_mount = MountController.new(horse)
	global_position = horse.global_position + Vector3.UP * 0.05
	velocity = Vector3.ZERO
	_move_speed = 0.0
	_impulse = Vector3.ZERO
	_capsule.radius = MOUNTED_RADIUS
	_lean = Vector2.ZERO
	_model.rotation = Vector3(0.0, _mount.yaw, 0.0)
	_animator.set_stance("ride")
	Audio.sfx("step_grass", global_position, -4.0)


func _dismount() -> void:
	if _mount == null:
		return
	var exclude: Array[RID] = [get_rid()]
	var spot := _mount.dismount_point(get_world_3d().direct_space_state, global_position, exclude)
	var yaw := _mount.yaw
	_mount.release()
	_mount = null
	_capsule.radius = BODY_RADIUS
	_model.position = Vector3.ZERO
	_model.rotation = Vector3(0.0, yaw, 0.0)
	_animator.set_stance("")
	global_position = spot
	velocity = Vector3.ZERO
	_move_speed = 0.0
	_move_dir = facing()


func is_mounted() -> bool:
	return _mount != null


func _physics_mounted(delta: float) -> void:
	if not is_instance_valid(_mount.horse):
		_dismount()
		return
	var dir := Vector3.ZERO if dead else _input_dir()
	var planar := _mount.drive(delta, dir, Input.is_action_pressed("sprint"), global_position)
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if is_on_wall():
		var real := get_real_velocity()
		_mount.blocked(Vector2(real.x, real.z).length())
	_keep_above_ground()
	if _mount.sync(global_position, delta):
		Audio.sfx("step_" + WorldGen.footstep_surface(global_position.x, global_position.z), global_position, -3.0)
	var k := Life.body_scale()
	_model.rotation = Vector3(0.0, _mount.yaw, 0.0)
	_model.position = _mount.rider_offset(k)
	_move_speed = _mount.speed
	_move_dir = _mount.facing()
	_animator.update(delta, 0.0)
	if _rig:
		_rig.call("set_state", 0.0, true, true)   # seated: legs follow the saddle clip
	if _stamina_delay <= 0.0:
		stamina = minf(stamina + 28.0 * delta * Life.needs.stamina_regen(), MAX_STAMINA * Life.needs.stamina_cap())
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_look_target()
	_update_camera(delta)


# --- Swimming ---------------------------------------------------------------------

func _update_swim_state(depth: float) -> void:
	var k := Life.body_scale()
	if not swimming and depth > SWIM_ENTER * k and not dead:
		swimming = true
		_set_crouch(false)
		_drown = 0.0
		_drown_warned = false
		if _swing > 0.0:
			_swing_id += 1
		_swing = 0.0
		_animator.stop_upper()
		_animator.set_stance("swim")
		VFX.sparks(get_parent(), global_position + Vector3.UP * SWIM_FLOAT * k, Color(0.85, 0.93, 1.0), 16)
	elif swimming and (depth < SWIM_EXIT * k or dead):
		swimming = false
		_animator.set_stance("crouch" if crouching else "")


## Vertical speed that holds the chest at the surface; pressing into a bank
## lifts the body so it can climb out.
func _swim_vertical(stroking: bool) -> float:
	var k := Life.body_scale()
	var surface := WorldGen.water_level_at(global_position.x, global_position.z)
	if is_nan(surface):
		return velocity.y - GRAVITY * get_physics_process_delta_time()
	var vy := clampf((surface - SWIM_FLOAT * k - global_position.y) * 4.0, -3.0, 3.0)
	if stroking and is_on_wall():
		vy = maxf(vy, 2.2)
	return vy


func _swim_stamina(delta: float, stroking: bool) -> void:
	stamina = maxf(stamina - (SWIM_DRAIN + (SWIM_DRAIN_MOVING if stroking else 0.0)) * delta, 0.0)
	_stamina_delay = 0.6
	if stamina > 0.0 or dead:
		_drown = 0.0
		return
	if not _drown_warned:
		_drown_warned = true
		Game.say("You're exhausted. Get to the shore!")
	_drown += DROWN_DPS * delta
	if _drown >= 1.0:
		var hurt := int(_drown)
		_drown -= hurt
		health = maxi(health - hurt, 0)
		health_changed.emit(health, max_health)
		if health == 0:
			_die()


# --- Crouch / stealth -------------------------------------------------------------

func toggle_crouch() -> void:
	_set_crouch(not crouching)


func _set_crouch(on: bool) -> void:
	if on and (dead or swimming or _mount != null):
		return
	crouching = on
	if not swimming and _mount == null:
		_animator.set_stance("crouch" if on else "")


## How far away enemies and game can hear the player (m): quiet crouched,
## loud at a run or a canter.
func noise_radius() -> float:
	if dead:
		return 0.0
	if _mount:
		return NOISE_RUN if _mount.speed > 4.0 else NOISE_WALK
	if crouching:
		return NOISE_CROUCH
	return NOISE_RUN if Vector2(velocity.x, velocity.z).length() > WALK + 0.8 else NOISE_WALK


# --- Lock-on ----------------------------------------------------------------------

func toggle_lock() -> void:
	if is_instance_valid(_lock):
		_release_lock()
		return
	if dead or _mount != null:
		return
	var best: Node3D = null
	var best_score := INF
	var fwd := forward()
	for enemy in _lock_candidates():
		var to := enemy.global_position - global_position
		to.y = 0.0
		var d := to.length()
		var dot := fwd.dot(to / maxf(d, 0.01))
		if dot < 0.25:
			continue    # in front of the camera only
		var score := d * (1.6 - dot)
		if score < best_score:
			best_score = score
			best = enemy
	if best:
		_set_lock(best)


func _lock_candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("team1"):
		var e := node as Node3D
		if e == null or e.get("dead"):
			continue
		if e.global_position.distance_to(global_position) <= LOCK_RANGE:
			out.append(e)
	return out


func _set_lock(target: Node3D) -> void:
	_lock = target
	_lock_height = _body_top(target) + 0.45
	_lock_marker.visible = true
	_flick = 0.0


func _release_lock() -> void:
	_lock = null
	if _lock_marker:
		_lock_marker.visible = false
	_animator.set_strafing(false)


## Next target to the left (-1) or right (+1) of the current one on screen.
func _switch_lock(side: float) -> void:
	if not is_instance_valid(_lock):
		return
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var here := right.dot(_lock.global_position - global_position)
	var best: Node3D = null
	var best_gap := INF
	for enemy in _lock_candidates():
		if enemy == _lock:
			continue
		var gap := (right.dot(enemy.global_position - global_position) - here) * side
		if gap > 0.2 and gap < best_gap:
			best_gap = gap
			best = enemy
	if best:
		_set_lock(best)


func _update_lock(delta: float) -> void:
	if _lock == null:
		return
	if not is_instance_valid(_lock) or _lock.get("dead") or dead or _mount != null \
			or not _lock.is_in_group("team1") \
			or _lock.global_position.distance_to(global_position) > LOCK_BREAK:
		_release_lock()
		return
	# Right stick flick switches target.
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(rx) > LOCK_STICK and not _stick_flicked:
		_stick_flicked = true
		_switch_lock(signf(rx))
	elif absf(rx) < 0.3:
		_stick_flicked = false
	# Frame the target: the camera looks from the player toward it.
	var to := _lock.global_position - global_position
	to.y = 0.0
	if to.length() > 0.3:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))
	if view == View.THIRD:
		_pitch = lerpf(_pitch, LOCK_PITCH, 1.0 - exp(-3.0 * delta))
	var t := Time.get_ticks_msec() * 0.001
	_lock_marker.global_position = _lock.global_position + Vector3.UP * (_lock_height + sin(t * 4.0) * 0.06)
	_lock_marker.rotation.y = t * 2.5


## Height of a body's collision capsule top above its origin (1.8 m when unknown).
func _body_top(node: Node3D) -> float:
	for child in node.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is CapsuleShape3D:
			return cs.position.y + (cs.shape as CapsuleShape3D).height * 0.5
		if cs.shape is CylinderShape3D:
			return cs.position.y + (cs.shape as CylinderShape3D).height * 0.5
		if cs.shape is BoxShape3D:
			return cs.position.y + (cs.shape as BoxShape3D).size.y * 0.5
	return 1.8


## A small downward cone that floats over the locked target, drawn over everything.
func _build_lock_marker() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.0
	cone.height = 0.3
	cone.radial_segments = 8
	cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.2)
	mat.no_depth_test = true
	mat.render_priority = 10
	cone.material = mat
	_lock_marker = MeshInstance3D.new()
	_lock_marker.mesh = cone
	_lock_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lock_marker.top_level = true
	_lock_marker.visible = false
	add_child(_lock_marker)


# --- Parry ------------------------------------------------------------------------

## Tracks how long the block has been up; a raise only opens a parry window
## after the block has been down for PARRY_REARM.
func _track_block(delta: float) -> void:
	if blocking and not _was_blocking:
		_block_age = 0.0 if _block_down >= PARRY_REARM else 99.0
	elif blocking:
		_block_age += delta
	_block_down = 0.0 if blocking else _block_down + delta
	_was_blocking = blocking


func _parry(from: Node) -> void:
	_parry_bonus = PARRY_BONUS_TIME
	stamina = minf(stamina + 8.0, MAX_STAMINA)
	var at := global_position + Vector3.UP * 1.2
	var push := facing() * 3.5
	if from is Node3D:
		var to := (from as Node3D).global_position - global_position
		to.y = 0.0
		at = global_position + to * 0.5 + Vector3.UP * 1.2
		push = to.normalized() * 3.5
	# The attacker's own hit-reaction path (0 damage), after its strike resolves.
	if from and is_instance_valid(from) and from.has_method("take_damage"):
		from.call_deferred("take_damage", 0, self, push)
	_animator.play_upper("Block_Hit", 1.8)
	VFX.impact_frame(get_parent(), global_position + Vector3.UP * 1.2, 0.5)
	Audio.sfx("clash")
	VFX.sparks(get_parent(), at, Color(1.0, 0.97, 0.75), 42)
	VFX.flash(get_parent(), at, Color(1.0, 0.9, 0.6), 3.0, 0.15, 5.0)
	_shake.add(0.3)
	_hit_stop(PARRY_HIT_STOP)


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
		if _move_speed < WALK and view != View.FIRST and not _strafing:
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
	if _strafing and is_instance_valid(_lock) and _dodge <= 0.0 and _stunned <= 0.0:
		var to := _lock.global_position - global_position
		want = atan2(to.x, to.z)
		rate = FACE_TURN_IDLE
	elif view == View.FIRST or blocking:
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
	var want_distance: float = rig[0]
	var k := Life.body_scale()
	var pivot_goal := Vector3(0.0, 1.55 * k, 0.0)
	if _mount:
		pivot_goal.y += _mount.rider_offset(k).y
		if view == View.THIRD:
			want_distance = MOUNTED_CAMERA
	if is_instance_valid(_lock):
		# Frame both: pull back with the gap and shift the pivot a little toward the target.
		var to := _lock.global_position - global_position
		to.y = 0.0
		if view == View.THIRD:
			want_distance += clampf(to.length() * 0.12, 0.0, 2.0)
		pivot_goal += to.limit_length(4.8) * 0.25   # at most 1.2 m
	_pivot.position = _pivot.position.lerp(pivot_goal, 1.0 - exp(-6.0 * delta))
	_distance = lerpf(_distance, want_distance, 1.0 - exp(-5.0 * delta))
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
		var q := PhysicsRayQueryParameters3D.create(from, camera.global_position, CAMERA_MASK)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			camera.global_position = (hit["position"] as Vector3) + (from - camera.global_position).normalized() * 0.3
	# Pinned against a wall so tight the lens would sit inside the head: hide the body.
	if view != View.FIRST:
		_model.visible = camera.global_position.distance_to(_pivot.global_position) > 0.45 * Life.body_scale()


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
	if dead or swimming or _mount != null:
		return
	if _can_attack():
		_start_swing()
	else:
		_attack_buffer = ATTACK_BUFFER   # early press: fire at the next opening


func dodge() -> void:
	if dead or swimming or _mount != null:
		return
	if _can_dodge():
		_start_dodge()
	elif stamina >= 15.0:
		_dodge_buffer = DODGE_BUFFER


## An attack may start when idle, in the cancel tail of the previous swing, or
## as a roll finishes.
func _can_attack() -> bool:
	return not dead and not swimming and _mount == null and _stunned <= 0.0 and _dodge <= DODGE_ATTACK_CANCEL and _swing <= _swing_cancel


## A roll may cut a swing's startup or recovery, but not its hit frames (it
## waits for them), and may chain from the very end of another roll.
func _can_dodge() -> bool:
	if dead or swimming or _mount != null or _stunned > 0.0 or stamina < 15.0 or _dodge > DODGE_CHAIN:
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
	# Target assist: face the locked target, else snap toward an enemy roughly in front.
	var target: Node3D = _lock if is_instance_valid(_lock) else _nearest_enemy(3.8, 0.1)
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
	var riposte := _parry_bonus > 0.0
	_parry_bonus = 0.0
	var damage: int = int(step["damage"] * (0.5 if weak else 1.0) * (PARRY_DAMAGE if riposte else 1.0))
	var knock: float = step.get("knockback", 1.5)
	# Sword arc: tilt alternates with the combo so chops, slices and stabs read differently.
	var tilts := [0.9, -0.9, 0.05, 0.0]
	var yaw := _model.rotation.y
	var arc_col := Color(1.0, 0.9, 0.7) if not weak else Color(0.7, 0.7, 0.75)
	if riposte:
		arc_col = Color(1.0, 0.97, 0.55)
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
	var first_hit := Vector3.INF
	for enemy in get_tree().get_nodes_in_group("team1"):
		var to: Vector3 = (enemy as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() < 2.6 and fwd.dot(to.normalized()) > 0.2:
			enemy.take_damage(damage, self, to.normalized() * knockback)
			var point: Vector3 = (enemy as Node3D).global_position + Vector3(0, 0.8, 0) - to.normalized() * 0.3
			VFX.sparks(get_parent(), point, Color(1.0, 0.72, 0.35), 30 if finisher else 18)
			if hits == 0:
				first_hit = point
			hits += 1
	if finisher:
		VFX.shockwave(get_parent(), global_position + fwd * 1.2, Color(1.0, 0.85, 0.45), 3.2)
		if hits > 0:
			VFX.impact_frame(get_parent(), first_hit, 0.7)
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
	_set_crouch(false)
	_dodge = DODGE_TIME
	_invulnerable = 0.35
	if _swing > 0.0:
		_swing_id += 1          # a pending hit frame no longer lands
		_animator.stop_upper()
	_swing = 0.0
	_attack_buffer = 0.0
	_impulse = Vector3.ZERO
	_animator.play_full("Dodge_Backward" if backward else "Dodge_Forward", DODGE_ANIM_RATE)
	VFX.afterimage(get_parent(), _model, Color(0.6, 0.85, 1.0), 3)
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
	if blocking and from_front and _block_age <= PARRY_WINDOW:
		_parry(from)
		return
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
	if _mount:
		_dismount()
	_release_lock()
	_set_crouch(false)
	dead = true
	# Death_A resolves to the long Mesh2Motion stagger/fall clip and can outlast
	# the respawn timer. Use the short terminal fall for the playable character.
	if _rig:
		_rig.call("set_paused", true)   # no foot IK or springs under the ragdoll or death clip
	if not (_ragdoll and _ragdoll.call("die")):
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
	if _ragdoll:
		_ragdoll.call("revive")
	_animator.set_active(true)
	if _rig:
		_rig.call("set_paused", false)
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
	VFX.heal(get_parent(), global_position)
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
	if _mount and is_instance_valid(_mount.horse):
		return _mount.horse     # "Dismount"; main.gd ignores horses, player.gd handles them
	var best: Node3D = null
	var best_d := 3.2
	for node in get_tree().get_nodes_in_group("interactable"):
		var d := global_position.distance_to((node as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best
