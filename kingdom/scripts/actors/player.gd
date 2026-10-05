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
## Weapon <-> character bus: VFX/audio/HUD subscribe (CombatFeedback), combat code only emits.
## swing_started: action (CombatAction), info {hit_t, yaw, weak, riposte, combo, anim_speed, first_person}.
signal swing_started(action: Resource, info: Dictionary)
## hit_confirmed: contact points of the targets hit this swing, whether it was the finisher.
signal hit_confirmed(points: Array, finisher: bool, mixers: Array)
## parried: attacker, world point, grade ("perfect" / "knockaway" / "broken").
signal parried(attacker: Node, point: Vector3, grade: String)
signal blocked(attacker: Node, guard_broken: bool)
signal clashed(attacker: Node, won: bool)
## The fall animation has played; whoever owns the game decides what happens next
## (main.gd shows the death screen). With no listener the player just gets up at spawn_point.
signal died

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
const ACCEL_START := 17.0        # m/s² at rest (FEEL_AUDIT F2: 34 reached walk speed in 2 frames, before the first step)
const ACCEL_TOP := 11.0          # m/s² near RUN
const MOVE_BRAKE := 30.0         # m/s² when the target speed drops while still moving (sprint -> walk)
## Releasing the stick: braking eases with speed so a run takes 2-3 decelerating
## steps instead of stopping dead in 0.2 s (FEEL_AUDIT F1). Walk stops stay short.
const STOP_BRAKE_WALK := 16.0     # m/s² from walking pace (2.4 m/s -> 0.15 s)
const STOP_BRAKE_RUN := 15.0      # m/s² from a run (6.5 m/s -> 0.43 s, ~1.4 m)
const PIVOT_BRAKE := 42.0        # m/s² when reversing out of a run: plant, then go
const PIVOT_ANGLE := 2.3         # rad (~130°) between travel and stick that triggers a pivot
const PIVOT_EXIT_SPEED := 1.2    # a pivot sets off in the new direction below this speed
## Travel direction swings toward the stick at a bounded rate; facing turns
## faster than travel, so the body leads a turn instead of sliding sideways.
const TRAVEL_TURN_WALK := 16.0   # rad/s
const TRAVEL_TURN_RUN := 9.0
const FACE_TURN_IDLE := 14.0     # rad/s: 180° on the spot in ~0.25 s (was 20: a 0.13 s 90° spin, FEEL_AUDIT F7)
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
## Plain dodge-roll (default action / HUD dodge button): a short defensive
## step with i-frames, no VFX. Distinct from the Shadow Dash ability below.
const DODGE_SPEED_MIN := 3.2
const DODGE_SPEED_MAX := 7.0
const DODGE_LANE_STEP_DEG := 10.0
const DODGE_LANE_MAX_DEG := 50.0
const DODGE_STAMINA := 15.0
## Jump is intentionally separate from the dodge action. Timing and clip names:
## docs/anim/patches/P7_jump.md (the clip library is loaded before UAL1).
const JUMP_BUFFER := 0.12
const JUMP_START_STAND := 0.15
const JUMP_START_RUN := 0.13
const JUMP_STAND_HEIGHT := 1.10
const JUMP_RUN_HEIGHT := 1.25
const JUMP_FALL_GRAVITY := 32.0
## Variable height: releasing Jump only trims the rise after this much air time, so a tap
## (released during the take-off wind-up, the usual mobile press) still gives a readable hop.
const JUMP_CUT_MIN_AGE := 0.1
const JUMP_CUT_SCALE := 0.6
const JUMP_TERMINAL := 24.0
## Shadow Dash (explicit ability, own input + HUD button, cooldown-gated):
## the fast burst with the afterimage VFX that used to fire on every dodge.
const DASH_SPEED_MIN := 4.0
const DASH_SPEED_MAX := 12.0
const DASH_STAMINA := 30.0
const DASH_COOLDOWN := 4.0
const DASH_INVULNERABLE := 0.4
const GRAVITY := 24.0
const MAX_STAMINA := 100.0
## Camera-only occlusion layer: cheap full-AABB box proxies over props whose
## walk-collision box is intentionally smaller than their visual mesh (market
## stall awnings/cloth canopies), so the chase camera still gets pulled out of
## them without shrinking or growing what the player can walk through. Not in
## the player's own collision_mask, so it never affects movement.
const CAMERA_BLOCKER_LAYER := 1 << 9
## Only static world geometry (terrain, buildings, props: layer 1) plus the
## camera-only blocker layer above may pull the chase camera in. Villagers
## (2), soldiers and enemies (4) never do.
const CAMERA_MASK := 1 | CAMERA_BLOCKER_LAYER
const BODY_RADIUS := 0.35
## Riding.
const MountController := preload("res://scripts/actors/mount_controller.gd")
const TravelRules := preload("res://scripts/world/travel_rules.gd")
## Foot IK on slopes and steps, torso and weapon/shield secondary motion.
const ProceduralRig := preload("res://scripts/actors/procedural_rig.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const EquipmentVisuals := preload("res://scripts/actors/equipment_visuals.gd")
const ImpactPause := preload("res://scripts/actors/impact_pause.gd")
const VFXSpells := preload("res://scripts/vfx/vfx_spells.gd")
const FlipbookFX := preload("res://scripts/vfx/flipbook_fx.gd")
const SettingsStore := preload("res://scripts/ui/frontend/settings_store.gd")
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
## The sword chain is data now: CombatMoves.combo("sword") (scripts/combat/combat_moves.gd) holds the
## exact timings that used to live here (anim, damage, lock = whole swing, hit = contact time, cost,
## knockback). hit_time() = old "hit", total() = old "lock", cancel window = last SWING_CANCEL of it.
const CombatMoves := preload("res://scripts/combat/combat_moves.gd")
const HitResolver := preload("res://scripts/combat/hit_resolver.gd")
const CombatFeedback := preload("res://scripts/combat/combat_feedback.gd")
const CombatFeel := preload("res://scripts/combat/combat_feel.gd")
const EnemyHighlight := preload("res://scripts/combat/enemy_highlight.gd")
const ChaseCamera := preload("res://scripts/actors/chase_camera.gd")
## The slash arc needs ~0.07 s to read, so it spawns this long before the hit.
const SLASH_LEAD := 0.07
## Attack lunge stops short of the target: never push the body into the enemy (FEEL_AUDIT F4).
const LUNGE_STANDOFF := 1.3
const COMBO_WINDOW := 0.45

var max_health := 120
var health := 120
var stamina := MAX_STAMINA
var dead := false
## Seconds of the fall before the death screen appears.
const DEATH_SCREEN_DELAY := 2.4
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
var _trail: WeaponTrail          # blade ribbon on the fast frames (COMBAT_AUDIT C4)
var _equip_vis: RefCounted       # worn / wielded item models on the skeleton bones (Life.equipment.changed)
var _ragdoll: Node
var _viewmodel: Node3D
var _shake := CameraShake.new()
var _look_target: Node3D
var _body_node: Node3D
var _appearance_key := ""
var combat_style := "sword"     # key into CombatMoves; another weapon = another table, not another branch
var _combo := -1
var _action: Resource           # the CombatAction being swung
var _feedback: RefCounted
var _combat_rng := RandomNumberGenerator.new()
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
var _dodging_ability := false   # true while the current roll is the Shadow Dash (fast + VFX)
## Seconds left before Shadow Dash can be used again. Public: the HUD reads
## this (and DASH_COOLDOWN below) to draw the ability button's cooldown.
var dash_cooldown := 0.0
var _invulnerable := 0.0
var _stunned := 0.0
var _hurt_cooldown := 0.0
var _stamina_delay := 0.0
var _impulse := Vector3.ZERO
var _step_distance := 0.0
var _move_dir := Vector3.FORWARD
var _move_speed := 0.0
var _pivoting := false
var _pivot_clip := ""
var _pivot_elapsed := 0.0
var _pivot_length := 0.0
var _pivot_rate := 1.0
var _pivot_start_yaw := 0.0
var _pivot_yaw_scale := 1.0
var _air_time := 0.0
var _jump_buffer := 0.0
var _jump_starting := false
var _jump_delay := 0.0
var _jump_active := false
var _jump_left_floor := false
var _jump_cut := false
var _jump_running := false
var _jump_age := 0.0
var _jump_falling := false
var _air_visual := false
var _fall_apex_y := 0.0
var _land_time := 0.0
var _land_lock := 0.0
var _land_roll := false
var _land_roll_speed := 0.0
var _landing_dip := 0.0
var _land_fov := 0.0
var _impact_fov := 0.0
var _impact_roll := 0.0       # radians; short camera roll on heavy hits (combat_feel.gd limits it)
var _loco_transition_time := 0.0
var _impact_pause: Node
var _camera_fade_visual: GeometryInstance3D
## Responsive framing model (scripts/actors/chase_camera.gd): sprint/dash/gallop FOV + distance, open-ground and
## combat framing, the cast camera. Its offsets sit ON TOP of the rig; collision and foliage fade still win.
var _chase := ChaseCamera.new()
var _chase_scan := 0.0
var _chase_combat := false
var _chase_open := false
var _chase_roof := false
var _caster_hooked := false
var _caster_scan := 0.0
var _camera_fade_original := 0.0
var _flinch := 0.0
var _yaw_rate := 0.0
var _lean := Vector2.ZERO
var _lean_speed := 0.0
var _hit_stop_token := 0
var _hit_stopping := false
var _capsule: CapsuleShape3D
var _mount: MountController
## Travel rules (travel_rules.gd): seconds spent running, winded (out of stamina: walk), seconds of gallop.
var _run_time := 0.0
var _winded := false
var _gallop_time := 0.0
var _drown := 0.0
var _drown_warned := false
var _lock: Node3D
var _lock_marker: MeshInstance3D
var _lock_height := 2.0
var _block_threat: Node3D
var _block_threat_refresh := 0.0
var _flick := 0.0
var _flick_cooldown := 0.0
var _stick_flicked := false
var _strafing := false
var _block_age := 99.0
var _block_down := 99.0
var _was_blocking := false
var _parry_bonus := 0.0
var _riposte_mult := PARRY_DAMAGE


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
	_impact_pause = ImpactPause.new()
	add_child(_impact_pause)
	_build_body()
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
	_feedback = CombatFeedback.new()
	_feedback.bind(self)
	_combat_rng.randomize()


## Actions this controller adds when the project has not defined them.
## (Tab is already the journal, so lock-on uses Q and the middle mouse button.)
func _ensure_actions() -> void:
	var wanted := {
		"lock_on": [KEY_Q, MOUSE_BUTTON_MIDDLE, JOY_BUTTON_RIGHT_STICK],
		"crouch": [KEY_C, JOY_BUTTON_LEFT_STICK],
		# Shadow Dash: an explicit ability, not the default dodge (K).
		"ability_dash": [KEY_R, JOY_BUTTON_LEFT_SHOULDER],
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
## The character model with its animation, ragdoll, head look, foot IK and weapon trail.
## `Life.appearance` (character creation) picks the modular G6 look; no appearance = the default hero.
func _build_body() -> void:
	var props: Array[String] = ["1H_Sword", "Round_Shield"]
	var look: Variant = Life.get("appearance")
	var body: Node3D = null
	if look is Dictionary and not (look as Dictionary).is_empty():
		body = (load("res://scripts/ui/character_creation.gd") as GDScript).call("build_model", look, 1.8, props)
	_appearance_key = var_to_str(look) if body != null else ""
	if body == null:
		# Style G default hero (target 03 hooded traveller): G6 villager tunic tinted green + skinned HeroOutfit
		var hero_look: Dictionary = (load("res://scripts/style_lab/lab_chars.gd") as GDScript).get("HERO_LOOK")
		body = (load("res://scripts/ui/character_creation.gd") as GDScript).call("build_model", hero_look, 1.8, props)
		if body == null:
			body = Assets.character("Player", 1.8, props)
		else:
			var outfit: GDScript = load("res://scripts/actors/hero_outfit.gd")
			outfit.call("tint_tunic", body)
			outfit.call("dress", body)
	_body_node = body
	_model.add_child(body)
	_animator = CharacterAnimator.new(body, RUN, WALK, "Walking_A", "Running_A", "Idle", true, true)
	# Root-driven actions need a new graph sample for every capsule physics tick.
	# Idle processing at 30 rendered fps otherwise alternates travel and zero
	# velocity across the two 60 Hz physics ticks in each rendered frame.
	_animator.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_ragdoll = Ragdoll.attach(self, body, [_animator.tree, _animator.player])
	_add_head_look(body)
	# After the look-at: the rig orders the skeleton's modifiers as
	# animation -> look-at -> foot IK -> secondary motion.
	_rig = ProceduralRig.attach(body, self, true)
	_animator.rig = _rig
	_trail = WeaponTrail.attach(body)
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_equip_vis = EquipmentVisuals.new(sks[0], Life.equipment)


## Applies `Life.appearance` (skin, hair, head, outfit, sex) to the world model: after New Game the
## first build already uses it; a loaded save calls this once its appearance has been restored.
## Beard, scars and voice have no mesh in the asset set and stay cosmetic.
func apply_appearance() -> void:
	var look: Variant = Life.get("appearance")
	var key := var_to_str(look) if look is Dictionary and not (look as Dictionary).is_empty() else ""
	if key == _appearance_key or _model == null:
		return
	if _ragdoll and is_instance_valid(_ragdoll):
		remove_child(_ragdoll)
		_ragdoll.queue_free()
		_ragdoll = null
	if _look_target and is_instance_valid(_look_target):
		remove_child(_look_target)
		_look_target.queue_free()
		_look_target = null
	if _body_node and is_instance_valid(_body_node):
		_model.remove_child(_body_node)
		_body_node.queue_free()    # also frees the rig, trail, look-at modifier and animator nodes
	_rig = null
	_trail = null
	if _equip_vis != null:
		(_equip_vis as EquipmentVisuals).detach()
		_equip_vis = null
	_build_body()
	apply_age()
	if dead:
		_animator.set_active(true)


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
	dash_cooldown = maxf(dash_cooldown - delta, 0.0)
	_invulnerable -= delta
	_stunned -= delta
	_hurt_cooldown -= delta
	_stamina_delay -= delta
	_flinch -= delta
	_attack_buffer -= delta
	_dodge_buffer -= delta
	_jump_buffer -= delta
	_land_lock = maxf(_land_lock - delta, 0.0)
	if _loco_transition_time > 0.0:
		_loco_transition_time -= delta
		if _loco_transition_time <= 0.0:
			_loco_transition_time = 0.0
			_animator.finish_locomotion_transition()
	if _land_time > 0.0:
		_land_time -= delta
		if _land_time <= 0.0:
			_land_roll = false
			_animator.finish_air()
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
			and _stunned <= 0.0 and not swimming and not _jump_starting and not _jump_active \
			and _land_time <= 0.0
	if blocking:
		_cancel_locomotion_transition()
	_track_block(delta)
	_animator.set_blocking(blocking)
	_consume_buffers()

	var sprint := Input.is_action_pressed("sprint")
	if sprint and crouching and dir.length() > 0.1:
		_set_crouch(false)            # sprinting stands up
	var locked := is_instance_valid(_lock)
	var running := (sprint or (touch_move.length() > 0.92 and not crouching) or view >= View.TOWN) \
			and not blocking and not crouching and (not locked or sprint) and not _winded
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
	if _land_lock > 0.0:
		speed *= 0.3
	var target := dir * speed
	var floor_before := is_on_floor()
	_air_time = 0.0 if floor_before or swimming else _air_time + delta
	var grounded := _air_time <= COYOTE_TIME
	if _jump_buffer > 0.0 and grounded and not _jump_starting and not _jump_active \
			and _land_time <= 0.0 and not dead and not swimming and not blocking \
			and _swing <= 0.0 and _dodge <= 0.0 and _stunned <= 0.0:
		if crouching:
			_set_crouch(false) # next physics frame can spend the buffered jump
		else:
			_begin_jump(running, floor_before)
	if _jump_starting:
		_jump_delay -= delta
		if _jump_delay <= 0.0:
			_launch_jump()
	if _jump_active:
		_jump_age += delta
	var speed_before_steer := _move_speed
	if _dodge > 0.0:
		# The roll owns movement: its own speed curve, no input smoothing.
		var speed_lo := DASH_SPEED_MIN if _dodging_ability else DODGE_SPEED_MIN
		var speed_hi := DASH_SPEED_MAX if _dodging_ability else DODGE_SPEED_MAX
		var roll_speed := lerpf(speed_lo, speed_hi, clampf(_dodge / DODGE_TIME, 0.0, 1.0))
		_move_dir = _dodge_dir
		_move_speed = roll_speed
	elif _land_roll:
		_move_speed = _land_roll_speed
	else:
		_steer(target, delta, (0.2 if _jump_running else AIR_CONTROL) if _jump_active else (1.0 if grounded else AIR_CONTROL))
	var planar := _move_dir * _move_speed + _impulse
	velocity.x = planar.x
	velocity.z = planar.z
	_impulse = _impulse.move_toward(Vector3.ZERO, IMPULSE_DECEL * delta)
	if swimming:
		velocity.y = _swim_vertical(target.length() > 0.1)
	else:
		if floor_before and not _jump_active:
			velocity.y = -1.0
		else:
			if _jump_active and not _jump_cut and velocity.y > 0.0 and _jump_age >= JUMP_CUT_MIN_AGE and not Input.is_action_pressed("jump"):
				velocity.y *= JUMP_CUT_SCALE
				_jump_cut = true
			var gravity := GRAVITY if velocity.y > 0.0 else JUMP_FALL_GRAVITY
			if _jump_active and absf(velocity.y) < 1.5:
				gravity *= 0.5
			velocity.y = maxf(velocity.y - gravity * delta, -JUMP_TERMINAL)
	var impact_speed := -velocity.y
	move_and_slide()
	_update_jump_after_move(floor_before, impact_speed, dir)
	_resolve_contacts()
	_keep_above_ground()

	_update_facing(dir, delta)
	var real := get_real_velocity()
	var travel := Vector3(real.x, 0.0, real.z)
	_update_locomotion_transition(dir, floor_before, speed_before_steer)
	_animator.update(delta, travel.length() if _dodge <= 0.0 else 0.0, travel)
	if _rig:
		# Feet off the ground: airborne, swimming, rolling, dead. Big hits ease the IK off.
		_rig.call("set_state", travel.length(), is_on_floor(), swimming or dead or _dodge > 0.0,
				_animator.is_full_busy())
	_update_lean(delta)
	_update_footsteps(delta, dir, grounded and not swimming and not _jump_starting and not _jump_active \
			and _land_time <= 0.0)

	_travel_stamina(delta, running and travel.length() > RUN * 0.6)
	if swimming:
		_swim_stamina(delta, travel.length() > 0.3)
	elif _stamina_delay <= 0.0 and not blocking:
		stamina = minf(stamina + 28.0 * delta * Life.needs.stamina_regen() * (TravelRules.WINDED_REGEN if _winded else 1.0), MAX_STAMINA * Life.needs.stamina_cap())
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_look_target()
	_update_camera(delta)


## Long runs cost stamina (docs/design/REALM_PLAN.md "Travel and world size"): a run is free for TravelRules.RUN_FREE_S
## seconds, then drains until you are winded and must walk. Town view and swimming are exempt (swimming has its own drain).
func _travel_stamina(delta: float, running_fast: bool) -> void:
	if running_fast and view < View.TOWN and not swimming:
		_run_time += delta
		var drain := TravelRules.run_drain(_run_time)
		if drain > 0.0:
			stamina = maxf(stamina - drain * delta, 0.0)
			_stamina_delay = 0.6
	else:
		_run_time = maxf(0.0, _run_time - delta * 2.0)
	var was := _winded
	_winded = TravelRules.is_winded(stamina, _winded, MAX_STAMINA * Life.needs.stamina_cap())
	if _winded and not was and not dead:
		Game.say("You are winded. Walk for a while.")


## Never fall through unloaded/streaming ground.
func _keep_above_ground() -> void:
	var ground := WorldGen.height(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = 0.0
		reset_physics_interpolation()   # a snap-up, not a smooth fall: don't smear the camera


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
	_reset_jump()
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
	reset_physics_interpolation()
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
	reset_physics_interpolation()
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
	var gal := TravelRules.gallop_step(_gallop_time, _mount.speed > MountController.CANTER_SPEED + 0.6, delta, _mount.gallop_allowed)
	_gallop_time = float(gal[0])
	if bool(gal[1]) != _mount.gallop_allowed:
		_mount.gallop_allowed = bool(gal[1])
		if not _mount.gallop_allowed:
			Game.say("The horse is blowing hard. Let it canter.")
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
		var surface := WorldGen.water_level_at(global_position.x, global_position.z)
		if not is_nan(surface):
			FlipbookFX.play(&"water_splash", Vector3(global_position.x, surface, global_position.z), 0.7, Color.WHITE, get_parent())
		_reset_jump()
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
	if get_parent() != null:
		EnemyHighlight.at(get_parent()).lock(target)


## The locked-on enemy, or null (HUD threat plates read it).
func locked_target() -> Node3D:
	return _lock if is_instance_valid(_lock) else null


func _release_lock() -> void:
	if _lock != null and get_parent() != null:
		EnemyHighlight.at(get_parent()).unlock()
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


func _parry(from: Node, grade := "knockaway", refund := 8.0, riposte := 1.5) -> void:
	_parry_bonus = PARRY_BONUS_TIME
	_riposte_mult = riposte
	stamina = minf(stamina + refund, MAX_STAMINA)
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
	parried.emit(from, at, grade)


## Body response: speed and travel direction are tuned separately. `control`
## scales every rate (reduced in the air).
func _steer(target: Vector3, delta: float, control: float) -> void:
	if _pivot_clip != "":
		if target.length() < 0.05 or not is_on_floor() or swimming or dead or _stunned > 0.0 \
				or crouching or blocking or _strafing or view == View.FIRST:
			_cancel_pivot()
		else:
			_advance_pivot(delta)
			return
	var want_speed := target.length()
	if want_speed < 0.05:
		_pivoting = false
		var stop_brake := lerpf(STOP_BRAKE_WALK, STOP_BRAKE_RUN, clampf((_move_speed - WALK) / (RUN - WALK), 0.0, 1.0))
		_move_speed = move_toward(_move_speed, 0.0, stop_brake * control * delta)
		return
	var want_dir := target / want_speed
	var run_t := clampf(_move_speed / RUN, 0.0, 1.0)
	if _move_speed < 0.3:
		_move_dir = want_dir   # from rest, go where the stick points; the body turns to follow
	else:
		var angle := _move_dir.signed_angle_to(want_dir, Vector3.UP)
		if absf(angle) > PIVOT_ANGLE:
			if _move_speed >= 4.0 and is_on_floor() and not _strafing and not blocking \
					and view != View.FIRST and not crouching and _swing <= 0.0 and _stunned <= 0.0 and not _jump_active and not _jump_starting:
				if _begin_pivot(want_dir):
					_advance_pivot(delta)
					return
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
	if _pivot_clip != "" and Vector2(real.x, real.z).length() < _move_speed * 0.5:
		_cancel_pivot()
	_move_speed = minf(_move_speed, Vector2(real.x, real.z).length() + 0.5)


func _update_facing(dir: Vector3, delta: float) -> void:
	var before := _model.rotation.y
	if _pivot_clip != "":
		_model.rotation.y = _pivot_start_yaw + _animator.pivot_yaw(_pivot_clip, _pivot_elapsed) * _pivot_yaw_scale
		_yaw_rate = angle_difference(before, _model.rotation.y) / maxf(delta, 0.0001)
		return
	var want := before
	var rate := 0.0
	if _strafing and is_instance_valid(_lock) and _dodge <= 0.0 and _stunned <= 0.0:
		var to := _lock.global_position - global_position
		want = atan2(to.x, to.z)
		rate = FACE_TURN_IDLE
	elif view == View.FIRST or blocking:
		want = _yaw + PI
		if blocking and view != View.FIRST:
			# Refresh at 12.5 Hz while guarding; camera heading is the fallback.
			_block_threat_refresh -= delta
			if _block_threat_refresh <= 0.0 or not is_instance_valid(_block_threat):
				_block_threat = _nearest_enemy(6.0, -1.0)
				_block_threat_refresh = 0.08
			if is_instance_valid(_block_threat):
				var threat_dir := _block_threat.global_position - global_position
				want = atan2(threat_dir.x, threat_dir.z)
		rate = FACE_TURN_IDLE
	elif dir.length() > 0.05 and _swing <= 0.0 and _dodge <= 0.0 and _stunned <= 0.0:
		want = atan2(dir.x, dir.z)
		rate = lerpf(FACE_TURN_IDLE, FACE_TURN_RUN, clampf(_move_speed / RUN, 0.0, 1.0))
	if rate > 0.0:
		var diff := angle_difference(before, want)
		var step := clampf(diff * (1.0 - exp(-FACE_SHARPNESS * delta)), -rate * delta, rate * delta)
		_model.rotation.y = before + step
	_yaw_rate = angle_difference(before, _model.rotation.y) / maxf(delta, 0.0001)
	if not blocking:
		_block_threat = null
		_block_threat_refresh = 0.0


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
	pivot_goal.y += _landing_dip
	_landing_dip = move_toward(_landing_dip, 0.0, 1.2 * delta)
	_land_fov = move_toward(_land_fov, 0.0, 14.0 * delta)
	_impact_fov = move_toward(_impact_fov, 0.0, maxf(_impact_fov, 1.0) * 7.0 * delta)
	_impact_roll = move_toward(_impact_roll, 0.0, maxf(absf(_impact_roll), 0.01) * 9.0 * delta)
	_step_chase(delta)
	camera.fov = lerpf(camera.fov, _chase.fov_base() + _chase.impulse() + _land_fov + _impact_fov, 1.0 - exp(-14.0 * delta))
	camera.set_meta("fov_base", _chase.fov_base())
	if view == View.THIRD:
		want_distance += _chase.dist_offset()
		pivot_goal.y += _chase.lift()
	if _mount:
		pivot_goal.y += _mount.rider_offset(k).y
		if view == View.THIRD:
			want_distance = MOUNTED_CAMERA
	if is_instance_valid(_lock):
		# Frame both: pull back with the gap and shift the pivot a little toward the target.
		var to := _lock.global_position - global_position
		to.y = 0.0
		var frame := ChaseCamera.lock_frame(to.length())
		if view == View.THIRD:
			want_distance += float(frame["dist"])
		pivot_goal += to.limit_length(8.0).normalized() * float(frame["shift"])
	_pivot.position = _pivot.position.lerp(pivot_goal, 1.0 - exp(-6.0 * delta))
	_distance = lerpf(_distance, want_distance, 1.0 - exp(-5.0 * delta))
	var pitch: float = _pitch if view <= View.THIRD else rig[1]
	if view == View.THIRD and absf(_pitch - rig[1]) > 0.9:
		_pitch = rig[1]
	if view == View.THIRD:
		pitch += _chase.pitch_offset()
	_pivot.rotation = Vector3(lerp_angle(_pivot.rotation.x, pitch, 1.0 - exp(-6.0 * delta)), _yaw, 0)
	_camera_arm.spring_length = _distance
	camera.rotation = _shake.step(delta) + Vector3(0.0, 0.0, _impact_roll)
	var cp := camera.global_position
	var floor_h := WorldGen.height(cp.x, cp.z) + 0.6
	var water_h := WorldGen.water_level_at(cp.x, cp.z)
	if not is_nan(water_h):
		floor_h = maxf(floor_h, water_h + 0.4)   # keep the camera above the surface
	if cp.y < floor_h:
		camera.global_position.y = floor_h
	# Keep the chase camera out of walls, stalls and roofs: pull it in front of whatever
	# lies between the head and the camera (playtest: camera inside the guild hall / stalls).
	# This runs on top of the spring arm's own collision, which alone missed thin
	# awnings/roofs; snapping straight to the corrected point every tick made the
	# camera visibly jerk whenever the ray flickered in and out (corners, foliage) —
	# so solid walls still pull in immediately, while camera-only canopy proxies ease
	# in and may fade their linked mesh. Releasing any occluder eases back out.
	var camera_fade_target: GeometryInstance3D = null
	if view == View.THIRD and InteriorDoor.active == null:
		var from := _pivot.global_position
		var q := PhysicsRayQueryParameters3D.create(from, camera.global_position, CAMERA_MASK)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var camera_target := camera.global_position
		var soft_occluder := false
		if not hit.is_empty():
			camera_target = (hit["position"] as Vector3) + (from - camera.global_position).normalized() * 0.3
			var collider := hit.get("collider") as CollisionObject3D
			soft_occluder = collider != null and (int(collider.collision_layer) & CAMERA_BLOCKER_LAYER) != 0
			if soft_occluder and collider.has_meta("camera_fade_target"):
				camera_fade_target = collider.get_meta("camera_fade_target") as GeometryInstance3D
		if camera_target.distance_to(from) < camera.global_position.distance_to(from):
			if soft_occluder:
				camera.global_position = camera.global_position.lerp(camera_target, 1.0 - exp(-30.0 * delta))
			else:
				camera.global_position = camera_target
		else:
			camera.global_position = camera.global_position.lerp(camera_target, 1.0 - exp(-14.0 * delta))
	_update_camera_fade(camera_fade_target)
	# Pinned against a wall so tight the lens would sit inside the head: hide the body.
	if view != View.FIRST:
		_model.visible = camera.global_position.distance_to(_pivot.global_position) > 0.45 * Life.body_scale()


## Feeds ChaseCamera. The expensive questions (hostiles near, open ground) are asked at 4 Hz; the rest is read live.
func _step_chase(delta: float) -> void:
	_chase_scan -= delta
	if _chase_scan <= 0.0:
		_chase_scan = 0.25
		_chase_combat = _swing > 0.0 or blocking or is_instance_valid(_lock) or _nearest_enemy(14.0, -1.0) != null
		var arm_clear: bool = _camera_arm != null and _camera_arm.get_hit_length() >= _camera_arm.spring_length - 0.15
		_chase_open = arm_clear and not swimming and InteriorDoor.active == null
		_chase_roof = global_position.y - WorldGen.height(global_position.x, global_position.z) > 2.2 and is_on_floor()
	_hook_caster(delta)
	var speed := Vector2(velocity.x, velocity.z).length() if _mount == null else _move_speed
	var gallop := _mount != null and _gallop_time > 0.0
	var ctx := {
		"speed_k": speed / RUN, "sprinting": Input.is_action_pressed("sprint") and speed > WALK * 1.4 and not blocking,
		"dashing": _dodge > 0.0 or _dodging_ability, "gallop": gallop, "combat": _chase_combat,
		"locked": is_instance_valid(_lock), "open": _chase_open, "rooftop": _chase_roof,
		"strength": 1.0 if view == View.THIRD else 0.0,
	}
	if int(SettingsStore.get_value("screen_shake")) == 0:
		ctx["strength"] = 0.0     # Screen Shake Off also turns off the lens motion
	_chase.cast_enabled = bool(SettingsStore.get_value("cast_camera"))
	if _chase.casting() and (Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("dodge")
			or Input.is_action_just_pressed("jump") or touch_move.length() > 0.5):
		_chase.cancel_cast()       # skippable: any action takes the camera back
	_chase.step(delta, ctx)


## FOV impulse from combat feel code: positive = outward punch. Decays on its own and rides above the base FOV.
func add_fov_impulse(degrees: float) -> void:
	_chase.add_fov_impulse(degrees * _screen_feedback_strength())


func _hook_caster(delta: float) -> void:
	if _caster_hooked:
		return
	_caster_scan -= delta
	if _caster_scan > 0.0:
		return
	_caster_scan = 1.0
	var caster := get_node_or_null("TechniqueCaster")
	if caster != null and caster.has_signal("cast"):
		caster.connect("cast", _on_technique_cast)
		_caster_hooked = true


func _on_technique_cast(_id: String, def: Dictionary) -> void:
	if view == View.THIRD and _mount == null and ChaseCamera.is_big_technique(def):
		_chase.begin_cast()


func _update_camera_fade(target: GeometryInstance3D) -> void:
	if _camera_fade_visual != target:
		if is_instance_valid(_camera_fade_visual):
			_camera_fade_visual.transparency = _camera_fade_original
		_camera_fade_visual = target if is_instance_valid(target) else null
		if _camera_fade_visual:
			_camera_fade_original = _camera_fade_visual.transparency
	if is_instance_valid(_camera_fade_visual):
		_camera_fade_visual.transparency = maxf(_camera_fade_original, 0.6)


func _fov_punch(degrees: float) -> void:
	# Keep the small contact cue inside the existing accessibility setting. This
	# is an outward lens pulse, independent of positional camera shake.
	_impact_fov = CombatFeel.merge_fov(_impact_fov, degrees * _screen_feedback_strength())


## Short camera roll (radians, signed) for heavy hits; merged by max and capped (combat_feel.gd).
func _camera_roll(radians: float) -> void:
	_impact_roll = CombatFeel.merge_roll(_impact_roll, radians * _screen_feedback_strength())


func _add_camera_shake(amount: float) -> void:
	_shake.add(amount * _screen_feedback_strength())


func _screen_feedback_strength() -> float:
	# Settings: Off = none, Reduced = half, Full = full. Read on impacts only.
	return float(clampi(int(SettingsStore.get_value("screen_shake")), 0, 2)) * 0.5


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
	if dead or swimming or _mount != null or _jump_starting or _jump_active or _land_time > 0.0:
		return
	if _can_attack():
		_start_swing()
	else:
		_attack_buffer = ATTACK_BUFFER   # early press: fire at the next opening


## Space / the mobile button buffers a jump briefly through an attack lockout or
## the last few frames before landing. A second press in the air never relaunches.
func jump() -> void:
	if dead or swimming or _mount != null or _menu_open():
		return
	_jump_buffer = JUMP_BUFFER


func _begin_jump(running: bool, grounded_at_press: bool) -> void:
	_cancel_locomotion_transition()
	_jump_running = running and _move_speed >= 4.5
	var cost := 10.0 if _jump_running else 6.0
	if stamina < cost:
		_jump_buffer = 0.0
		return
	_spend(cost)
	_jump_buffer = 0.0
	_jump_starting = true
	# On a ledge, honor coyote input immediately instead of letting the start
	# anticipation spend the grace window falling below the take-off point.
	_jump_delay = (JUMP_START_RUN if _jump_running else JUMP_START_STAND) if grounded_at_press else 0.0
	_jump_cut = false
	_jump_falling = false
	_fall_apex_y = global_position.y
	# The run clip's take-off is frame 12; at 3x it reaches contact in 0.13 s.
	_animator.play_air("Jump_Running_Start" if _jump_running else "Jump_Start", 3.0 if _jump_running else 2.0)


func _launch_jump() -> void:
	_jump_starting = false
	_jump_active = true
	_jump_left_floor = false
	_jump_age = 0.0
	_air_visual = true
	_air_time = COYOTE_TIME + 0.01
	velocity.y = sqrt(2.0 * GRAVITY * (JUMP_RUN_HEIGHT if _jump_running else JUMP_STAND_HEIGHT))
	_fall_apex_y = global_position.y
	_animator.play_air("Jump_Rise")
	VFXSpells._dust(get_parent(), Vector3(global_position.x, WorldGen.height(global_position.x, global_position.z), global_position.z), 0.55 if _jump_running else 0.4)
	App.vibrate(10)


func _update_jump_after_move(floor_before: bool, impact_speed: float, dir: Vector3) -> void:
	if not is_on_floor() and not swimming:
		if floor_before and not _jump_active:
			_fall_apex_y = global_position.y
		_fall_apex_y = maxf(_fall_apex_y, global_position.y)
		if _jump_active:
			_jump_left_floor = true
			if not _jump_falling and velocity.y <= 0.5:
				_jump_falling = true
				_animator.play_air("Jump_Fall")
		elif not _jump_starting and not _air_visual and _air_time >= 0.15 \
				and _dodge <= 0.0 and _land_time <= 0.0:
			_air_visual = true
			_animator.play_air("Jump_Fall")
		return
	if is_on_floor() and ((_jump_active and (_jump_left_floor or _jump_age > 0.18)) \
			or (not floor_before and _air_visual)):
		_land_jump(maxf(impact_speed, 0.0), dir)


## A measured run-stop clip replaces the abrupt idle pose at high speed. Its
## root translation is disabled, and the capsule keeps the audited 15 m/s² brake.
func _update_locomotion_transition(dir: Vector3, grounded: bool, entry_speed: float) -> void:
	if _loco_transition_time > 0.0:
		return
	if not grounded or dead or swimming or blocking or _jump_starting or _jump_active \
			or _land_time > 0.0 or _dodge > 0.0 or _swing > 0.0 or _stunned > 0.0:
		return
	if dir.length() >= 0.05 or entry_speed < 4.0:
		return
	var clip := "Loco_RunStop_L" if _animator.gait_phase() < 0.5 else "Loco_RunStop_R"
	var natural_entry := 3.1 if clip.ends_with("_L") else 3.6
	var rate := clampf(entry_speed / natural_entry, 0.8, 2.5)
	var length := _animator.clip_length(clip)
	if length <= 0.0:
		return
	_animator.play_locomotion_transition(clip, rate)
	_loco_transition_time = length / rate


func _cancel_locomotion_transition() -> void:
	_cancel_pivot()
	if _loco_transition_time <= 0.0:
		return
	_loco_transition_time = 0.0
	_animator.finish_locomotion_transition()


func _begin_pivot(want_dir: Vector3) -> bool:
	var turn := angle_difference(_model.rotation.y, atan2(want_dir.x, want_dir.z))
	var clip := "Loco_Pivot180_Run_L"
	var length := _animator.clip_length(clip)
	var end_yaw := _animator.pivot_yaw(clip, length)
	if signf(end_yaw) != signf(turn):
		clip = "Loco_Pivot180_Run_R"
		length = _animator.clip_length(clip)
		end_yaw = _animator.pivot_yaw(clip, length)
	if length <= 0.0 or absf(end_yaw) < 2.3 or (absf(turn / end_yaw) < 0.8 or absf(turn / end_yaw) > 1.2):
		return false
	_cancel_locomotion_transition()
	_pivot_clip = clip
	_pivot_length = length
	_pivot_elapsed = 0.0
	_pivot_rate = clampf(_move_speed / 4.0, 0.8, 1.5)
	_pivot_start_yaw = _model.rotation.y
	_pivot_yaw_scale = turn / end_yaw
	_pivoting = false
	_animator.play_air(clip, _pivot_rate, true)
	return true


func _advance_pivot(delta: float) -> void:
	var clip_time := _animator.air_clip_time(_pivot_clip)
	if clip_time < 0.0:
		# State-machine travel enters on its next animation evaluation.
		_move_speed = 0.0
		return
	var previous := _animator.pivot_position(_pivot_clip, _pivot_elapsed)
	_pivot_elapsed = clampf(clip_time, _pivot_elapsed, _pivot_length)
	var next := _animator.pivot_position(_pivot_clip, _pivot_elapsed)
	var travel := (next - previous).rotated(Vector3.UP, _pivot_start_yaw) * Life.body_scale()
	travel.y = 0.0
	_move_speed = travel.length() / maxf(delta, 0.0001)
	if travel.length_squared() > 0.000001:
		_move_dir = travel.normalized()
	if _pivot_elapsed >= _pivot_length:
		_model.rotation.y = _pivot_start_yaw + _animator.pivot_yaw(_pivot_clip, _pivot_length) * _pivot_yaw_scale
		_cancel_pivot()


func _cancel_pivot() -> void:
	if _pivot_clip == "":
		return
	_pivot_clip = ""
	_pivoting = false
	_animator.finish_air()


func _land_jump(impact_speed: float, dir: Vector3) -> void:
	var fall_height := maxf(_fall_apex_y - global_position.y, 0.0)
	var forward_input := dir.length() > 0.1 and facing().dot(dir.normalized()) > 0.25
	var running_land := (_jump_running or _move_speed > 4.5) and fall_height <= 3.0
	var roll := (fall_height >= 3.0 and fall_height <= 6.0) or (fall_height > 1.2 and forward_input)
	var hard := fall_height >= 1.2 or impact_speed > 11.0
	_jump_active = false
	_jump_starting = false
	_jump_left_floor = false
	_jump_falling = false
	_jump_running = false
	_jump_cut = false
	_jump_age = 0.0
	_air_visual = false
	_air_time = 0.0
	if fall_height > 6.0 and not roll:
		take_damage(roundi((fall_height - 6.0) * 8.0), null, Vector3.ZERO, true)
		if dead:
			return
	var ground := Vector3(global_position.x, WorldGen.height(global_position.x, global_position.z), global_position.z)
	var water_surface := WorldGen.water_level_at(global_position.x, global_position.z)
	if is_nan(water_surface):
		VFXSpells._dust(get_parent(), ground, clampf(0.35 + impact_speed * 0.05, 0.4, 1.2))
	elif WorldGen.water_depth(global_position.x, global_position.z) > 0.05:
		FlipbookFX.play(&"water_splash", Vector3(global_position.x, water_surface, global_position.z),
			clampf(0.5 + impact_speed * 0.035, 0.6, 1.0), Color.WHITE, get_parent())
	if roll:
		_land_roll = true
		_land_roll_speed = maxf(_move_speed * 0.6, 2.2)
		_move_dir = dir.normalized() if dir.length() > 0.1 else facing()
		_land_time = 0.9
		_landing_dip = -0.30
		_animator.play_air("Jump_Land_Roll", 1.8)
		App.vibrate(35)
	elif running_land:
		_land_time = 0.35
		_landing_dip = -0.10
		_animator.play_air("Jump_Land_Running", 2.0)
		App.vibrate(10)
	elif hard:
		_land_time = 0.45
		_land_lock = 0.35
		_landing_dip = -0.22
		_land_fov = 2.0
		_animator.play_air("Jump_Land_Hard", 2.5)
		App.vibrate(20)
	else:
		_land_time = 0.25
		_landing_dip = -0.10
		_animator.play_air("Jump_Land_Soft", 2.5)
		App.vibrate(10)
	# A jump pressed just before landing should leave the recovery pose on the
	# first grounded frame; retain the buffer until the next physics step.
	if _jump_buffer > 0.0:
		_land_time = 0.0
		_land_lock = 0.0
		_land_roll = false
		_land_roll_speed = 0.0


func _reset_jump() -> void:
	if _animator:
		_cancel_locomotion_transition()
	_jump_buffer = 0.0
	_jump_starting = false
	_jump_active = false
	_jump_left_floor = false
	_jump_falling = false
	_jump_running = false
	_jump_cut = false
	_jump_age = 0.0
	_air_visual = false
	_land_time = 0.0
	_land_lock = 0.0
	_land_roll = false
	_land_roll_speed = 0.0
	_landing_dip = 0.0
	_land_fov = 0.0
	_loco_transition_time = 0.0
	if _animator:
		_animator.finish_air()


## Plain dodge-roll: short i-frame step, no VFX, no cooldown beyond stamina.
## Bound to the "dodge" action (K) and the HUD dodge button.
func dodge() -> void:
	if dead or swimming or _mount != null or _jump_starting or _jump_active or _land_time > 0.0:
		return
	if _can_dodge():
		_start_dodge(false)
	elif stamina >= DODGE_STAMINA:
		_dodge_buffer = DODGE_BUFFER


## Shadow Dash: the fast burst with afterimages, gated by its own cooldown
## and a higher stamina cost. Bound to "ability_dash" (KEY_R) and the HUD
## ability button. Never fires from ordinary movement or the plain dodge.
func ability_dash() -> void:
	if dead or swimming or _mount != null or _jump_starting or _jump_active or _land_time > 0.0:
		return
	if dash_cooldown > 0.0 or stamina < DASH_STAMINA:
		return
	if not _can_dodge():
		return
	_start_dodge(true)


## An attack may start when idle, in the cancel tail of the previous swing, or
## as a roll finishes.
func _can_attack() -> bool:
	return not dead and not swimming and _mount == null and not _jump_starting and not _jump_active \
		and _land_time <= 0.0 and _stunned <= 0.0 and _dodge <= DODGE_ATTACK_CANCEL and _swing <= _swing_cancel


## A roll may cut a swing's startup or recovery, but not its hit frames (it
## waits for them), and may chain from the very end of another roll.
func _can_dodge() -> bool:
	if dead or swimming or _mount != null or _jump_starting or _jump_active or _land_time > 0.0 \
			or _stunned > 0.0 or stamina < DODGE_STAMINA or _dodge > DODGE_CHAIN:
		return false
	return not _in_active_frames()


func _in_active_frames() -> bool:
	return _swing > 0.0 and _swing_elapsed >= _swing_hit - ACTIVE_BEFORE and _swing_elapsed <= _swing_hit + ACTIVE_AFTER


func _consume_buffers() -> void:
	if _dodge_buffer > 0.0 and _can_dodge():
		_dodge_buffer = 0.0
		_attack_buffer = 0.0
		_start_dodge(false)
	elif _attack_buffer > 0.0 and _can_attack():
		_attack_buffer = 0.0
		_start_swing()


func _start_swing() -> void:
	_cancel_locomotion_transition()
	if _dodge > 0.0:
		_dodge = 0.0                 # roll attack: the swing takes over the roll's tail
		_animator.stop_full()
	var steps := CombatMoves.combo(combat_style)
	_combo = (_combo + 1) % steps.size() if _combo_window > 0.0 else 0
	var action: Resource = steps[_combo]
	_action = action
	var weak: bool = stamina < action.cost
	# A tired swing plays at 0.7x, so its blade (and hit) arrives later too.
	var hit_t: float = action.hit_time() / (0.7 if weak else 1.0)
	_spend(action.cost)
	# Target assist: face the locked target, else snap toward an enemy roughly in front.
	var target: Node3D = _magnet_target()
	if target:
		var to := target.global_position - global_position
		_model.rotation.y = atan2(to.x, to.z)
	var lunge := ATTACK_LUNGE
	if target:
		# Magnetism: a small capped step toward the target (combat_feel.gd), ending at the standoff.
		var flat := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
		lunge = CombatFeel.lunge_speed(flat, IMPULSE_DECEL, action.finisher, ATTACK_LUNGE * 1.6)
	if action.root_motion:
		_kick(facing() * lunge)
	_swing_id += 1
	_swing = action.total()
	_swing_elapsed = 0.0
	_swing_hit = hit_t
	_swing_cancel = action.cancel_remaining("attack")   # finisher has no window: commits to its recovery
	_combo_window = action.total() + COMBO_WINDOW
	if action.finisher:
		_combo_window = 0.0     # finisher ends the chain
	var rate: float = action.anim_speed * (0.7 if weak else 1.0)
	_animator.play_upper(action.anim, rate)
	var riposte := _parry_bonus > 0.0
	_parry_bonus = 0.0
	var damage: int = int(action.damage * (0.5 if weak else 1.0) * (_riposte_mult if riposte else 1.0))
	_riposte_mult = PARRY_DAMAGE
	swing_started.emit(action, {"hit_t": hit_t, "yaw": _model.rotation.y, "weak": weak, "riposte": riposte,
		"combo": _combo, "anim_speed": rate, "first_person": _viewmodel.visible, "id": _swing_id})
	get_tree().create_timer(hit_t).timeout.connect(_resolve_hit.bind(damage, action.knockback, action.finisher, _swing_id))


## The locked target, else the best living enemy in the magnetism cone (combat_feel.gd pick_target).
func _magnet_target() -> Node3D:
	if is_instance_valid(_lock):
		return _lock
	var enemies: Array = []
	var pos: Array = []
	for enemy in get_tree().get_nodes_in_group("team1"):
		var e := enemy as Node3D
		if e == null or e.get("dead"):
			continue
		enemies.append(e)
		pos.append(e.global_position)
	var pick := CombatFeel.pick_target(global_position, facing(), pos)
	return null if pick["pos"] == null else enemies[int(pick["index"])]


## Damage and knockback of the swing in progress (breakable.gd and tools read this instead of the table).
func swing_stats() -> Dictionary:
	if _action == null:
		return {"damage": 14, "knockback": 1.5}
	return {"damage": _action.damage, "knockback": _action.knockback}


func swing_id() -> int:
	return _swing_id


func _resolve_hit(damage: int, knockback: float, finisher: bool, id := -1) -> void:
	if id >= 0 and id != _swing_id:
		return    # the swing was cancelled (dodge) before its hit frame
	if dead or not is_inside_tree():
		return
	var fwd := forward() if view == View.FIRST else facing()
	var points: Array = []
	var impacted_mixers: Array = []
	var blade_tip := _trail.tip_position() if _trail else Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("team1"):
		var to: Vector3 = (enemy as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() < 2.6 and fwd.dot(to.normalized()) > 0.2:
			enemy.take_damage(damage, self, to.normalized() * knockback)
			impacted_mixers.append_array(enemy.find_children("*", "AnimationMixer", true, false))
			var point: Vector3 = (enemy as Node3D).global_position + Vector3(0, 0.8, 0) - to.normalized() * 0.3
			if blade_tip != Vector3.ZERO and blade_tip.distance_to(point) <= 0.6:
				point = blade_tip
			points.append(point)
	# People in front of a drawn blade: a silent takedown from behind knocks them out, any other blow hurts and can kill
	# (villager.gd take_damage; Takedown leaves the body as Evidence and silences a witness).
	for v in get_tree().get_nodes_in_group("villager"):
		if not (v as Node).has_method("take_damage"):
			continue
		var tv: Vector3 = (v as Node3D).global_position - global_position
		tv.y = 0.0
		if tv.length() < 2.2 and fwd.dot(tv.normalized()) > 0.2:
			(v as Node).call("take_damage", damage, self, tv.normalized() * knockback)
			points.append((v as Node3D).global_position + Vector3(0, 0.9, 0))
	hit_confirmed.emit(points, finisher, impacted_mixers)


func _start_dodge(is_ability: bool) -> void:
	_cancel_locomotion_transition()
	_dodging_ability = is_ability
	if is_ability:
		_spend(DASH_STAMINA)
		dash_cooldown = DASH_COOLDOWN
	else:
		_spend(DODGE_STAMINA)
	var dir := _input_dir()
	var backward := dir.length() < 0.1
	_dodge_dir = -facing() if backward else dir.normalized()
	_dodge_dir = _clear_dodge_lane(_dodge_dir)
	if not backward:
		_model.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	_set_crouch(false)
	_dodge = DODGE_TIME
	_invulnerable = DASH_INVULNERABLE if is_ability else 0.35
	if _swing > 0.0:
		_swing_id += 1          # a pending hit frame no longer lands
		_animator.stop_upper()
		if _trail:
			_trail.stop()
	_swing = 0.0
	_attack_buffer = 0.0
	_impulse = Vector3.ZERO
	_animator.play_full("Dodge_Backward" if backward else "Dodge_Forward", DODGE_ANIM_RATE)
	if is_ability:
		# Shadow Dash only: the afterimage trail that used to play on every dodge.
		VFX.afterimage(get_parent(), _model, Color(0.6, 0.85, 1.0), 3)
	get_tree().create_timer(DODGE_TIME).timeout.connect(_end_dodge_anim)


## If the swept roll path hits a hostile capsule, choose the nearest clear lane
## around it. The probe runs only once per dodge input; regular movement and NPC
## collision budgets are unchanged. Walls still block the roll normally.
func _clear_dodge_lane(direction: Vector3) -> Vector3:
	var speed_min := DASH_SPEED_MIN if _dodging_ability else DODGE_SPEED_MIN
	var speed_max := DASH_SPEED_MAX if _dodging_ability else DODGE_SPEED_MAX
	var distance := (speed_min + speed_max) * 0.5 * DODGE_TIME
	var obstruction := _dodge_obstruction(direction, distance)
	if obstruction == null or not obstruction.is_in_group("team1"):
		return direction
	var right := direction.rotated(Vector3.UP, PI * 0.5)
	var to_obstruction := obstruction.global_position - global_position
	var preferred_side := -1.0 if to_obstruction.dot(right) >= 0.0 else 1.0
	for step in range(1, int(DODGE_LANE_MAX_DEG / DODGE_LANE_STEP_DEG) + 1):
		var angle := deg_to_rad(float(step) * DODGE_LANE_STEP_DEG)
		for side in [preferred_side, -preferred_side]:
			var candidate := direction.rotated(Vector3.UP, angle * side).normalized()
			if _dodge_obstruction(candidate, distance) == null:
				return candidate
	return direction


func _dodge_obstruction(direction: Vector3, distance: float) -> Node3D:
	var result := KinematicCollision3D.new()
	if test_move(global_transform, direction * distance, result):
		return result.get_collider() as Node3D
	return null


## When the roll's movement ends and the player is already steering, hand the
## legs straight back to locomotion instead of finishing the get-up on the spot.
func _end_dodge_anim() -> void:
	if _dodge <= 0.0 and _input_dir().length() > 0.1 and not dead:
		_animator.stop_full()


## One-off horizontal velocity kick. It replaces any kick still decaying.
func _kick(v: Vector3) -> void:
	_impulse = Vector3(v.x, 0.0, v.z)


const PLAYER_POISE := 40.0

func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO, force := false) -> void:
	if dead or (not force and (_invulnerable > 0.0 or _hurt_cooldown > 0.0)):
		return
	_cancel_locomotion_transition()
	var from_front := true
	if from is Node3D:
		var to := (from as Node3D).global_position - global_position
		to.y = 0.0
		from_front = facing().dot(to.normalized()) > 0.3
	# One resolver call per incoming blow. Attackers with a move table describe the blow
	# (attack_info: lane, poise, parryable...); anything else is a plain parryable mid blow.
	var atk := {"damage": amount, "poise_damage": float(amount), "lane": 1, "parryable": true, "unblockable": false}
	var from_action := false
	if from and is_instance_valid(from) and from.has_method("attack_info"):
		var info: Dictionary = from.call("attack_info")
		if not info.is_empty():
			atk.merge(info, true)
			atk["damage"] = amount
			from_action = true
	var def := {"guarding": blocking and not force, "from_front": from_front, "guard_age": _block_age, "guard_pool": stamina,
		"guard_cost": 1.6, "poise": PLAYER_POISE, "guard_lane": -1}
	if from_action and _swing > 0.0 and amount > 0 and _action != null:
		def["swing"] = {"active_age": _swing_elapsed - _swing_hit, "parryable": true,
			"poise_damage": _action.poise_damage}
	var res := HitResolver.resolve(atk, def, _combat_rng)
	match int(res["result"]):
		HitResolver.Outcome.CLASHED:
			var lost: bool = res["winner"] == "attacker" or res["winner"] == "none"
			if res["winner"] != "attacker" and from and is_instance_valid(from) and from.has_method("take_damage"):
				var away := Vector3.ZERO
				if from is Node3D:
					away = ((from as Node3D).global_position - global_position) * Vector3(1, 0, 1)
				from.call_deferred("take_damage", 0, self, away.normalized() * float(res["push"]) * 2.0)
			if lost:
				_interrupt_technique("clash")
				_stunned = maxf(_stunned, float(res["defender_stun"]))
				_swing = 0.0
				_swing_id += 1
				_kick(-facing() * float(res["push"]) * 2.0)
				_animator.play_upper("Block_Hit", 1.5)
			clashed.emit(from, not lost)
			return
		HitResolver.Outcome.PARRIED:
			_parry(from, String(res["grade"]), float(res["refund"]), float(res["riposte"]))
			if int(res["damage"]) <= 0:
				return
			amount = int(res["damage"])           # a broken parry still lets a part through
		HitResolver.Outcome.BLOCKED:
			_spend(float(res["guard_cost"]))
			_kick(-facing() * BLOCK_PUSH)
			blocked.emit(from, false)
			amount = int(res["damage"])
			if amount == 0:
				return
		HitResolver.Outcome.GUARD_BROKEN:
			_interrupt_technique("guard broken")
			_spend(float(res["guard_cost"]))
			_kick(-facing() * BLOCK_PUSH)
			_stunned = float(res["defender_stun"])
			_swing = 0.0
			_swing_id += 1
			blocked.emit(from, true)
	_hurt_cooldown = 0.35
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if knockback.length_squared() > 0.0001:
		_kick(knockback)
	_add_camera_shake(0.3)
	if health == 0:
		_die()
	elif not blocking:
		_interrupt_technique("hit reaction")
		_flinch = FLINCH_TIME
		var heavy := amount >= max_health * 0.12 or knockback.length() >= 4.0
		var clip := "Hit_%s_%s" % ["Heavy" if heavy else "Light", _hit_side(from)]
		if heavy and not _mount and not swimming:
			_animator.play_full(clip, 1.0)
		else:
			_animator.play_upper(clip, 1.0)
	if health > 0 and amount > 0 and _impact_pause:
		var attacker_mixers: Array = []
		if from is Node3D:
			attacker_mixers.append_array((from as Node3D).find_children("*", "AnimationMixer", true, false))
		_hit_stop(0.045, attacker_mixers)


func _hit_side(from: Node) -> String:
	if not (from is Node3D):
		return "Front"
	var to := (from as Node3D).global_position - global_position
	to.y = 0.0
	var forward := facing()
	var front := forward.dot(to)
	var right := Vector3.UP.cross(forward).dot(to)
	if absf(front) >= absf(right):
		return "Front" if front > 0.0 else "Back"
	return "Right" if right > 0.0 else "Left"


func _interrupt_technique(reason: String) -> void:
	var caster := get_node_or_null("TechniqueCaster")
	if caster != null and caster.has_method("interrupt_cast"):
		caster.call("interrupt_cast", reason)


func _die() -> void:
	_interrupt_technique("death")
	if _mount:
		_dismount()
	_release_lock()
	_reset_jump()
	_set_crouch(false)
	dead = true
	# Death_A resolves to the long Mesh2Motion stagger/fall clip and can outlast
	# the respawn timer. Use the short terminal fall for the playable character.
	if _rig:
		_rig.call("set_paused", true)   # no foot IK or springs under the ragdoll or death clip
	if not (_ragdoll and _ragdoll.call("die")):
		_animator.play_terminal("Death01")
	if get_signal_connection_list("died").is_empty():
		Game.say("You fall... and wake in the village, bruised.")
		await get_tree().create_timer(3.0).timeout
		revive()
		return
	await get_tree().create_timer(DEATH_SCREEN_DELAY).timeout
	if dead:
		died.emit()


## Gets the fallen player back on their feet: at `spawn_point` (a bed, or the village), or
## where they lie when `teleport` is false (a save was loaded over the death).
func revive(teleport := true) -> void:
	if teleport:
		global_position = spawn_point
	reset_physics_interpolation()
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
func _hit_stop(duration: float, impacted_mixers: Array = []) -> void:
	if duration <= 0.06 and _impact_pause:
		impacted_mixers.append(_animator.tree)
		impacted_mixers.append(_animator.player)
		_impact_pause.call("pause", impacted_mixers, duration)
		return
	_hit_stop_token += 1
	var token := _hit_stop_token
	_hit_stopping = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hit_stop_token:   # an overlapping, later hit-stop restores time itself
		_hit_stopping = false
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	_update_camera_fade(null)
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
		# Doors, services and pickups beat a passer-by's "Talk" when both are in reach.
		if node.has_meta("low_priority") and d < 3.2:
			d = minf(d + 1.6, 3.19)
		if d < best_d:
			best_d = d
			best = node
	return best
