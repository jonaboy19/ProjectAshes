class_name CharacterAnimator
extends RefCounted
## Builds an AnimationTree in code for a KayKit character so animations layer
## instead of replacing each other:
##
##   locomotion (idle <-> phase-synced walk/run gait, rate-matched to ground speed)
##     -> strafe  (guard stance: forward/back/side steps chosen by travel direction)
##     -> stance  (optional: crouch / swim / ride sets replace the whole locomotion)
##     -> block   (Blend2, upper body only: shield raised while walking)
##     -> upper   (OneShot, upper body only: swing a sword while running)
##     -> full    (OneShot, whole body: dodge rolls, big hits)
##
## Upper-body filtering uses the rig's bone names, so legs keep running while
## the arms attack. Pattern follows the Godot TPS demo / GDQuest controllers.
##
## Foot slide: every gait clip is stretched onto a common one-second timeline so
## walk and run share one step phase (both clips plant the left foot forward at
## t = 0). A TimeScale then plays that shared cycle at `speed / stride`, where
## the stride is blended from each clip's measured ground travel per cycle. The
## feet therefore cover the same distance as the capsule at any blend weight,
## instead of a mixed walk/run pose cycling at an unrelated rate.

## Bones that stay with the legs (everything else counts as upper body). Covers
## the KayKit rig and the UE-style Quaternius/UAL rig.
const LOWER_KEYS := ["root", "hips", "pelvis", "upperleg", "lowerleg", "thigh", "calf", "foot", "toes",
	"ball", "heel", "knee", "ik_", "IK", "control-"]
## Measured on the 1.7–1.8 m UAL rigs by tools/qa/anim_qa (planted-foot travel,
## docs/qa/anim_qa_report.md). Blend-space coordinates represent the speed
## covered by the clip, not a gameplay stat. These are the values for a rig whose
## thigh joint rests REF_LEG_HEIGHT above the soles; other rigs scale them by leg
## length (the armored guard measures 0.85 m/s walk, 0.87× the player).
const WALK_CLIP_SPEED := 1.0
const RUN_CLIP_SPEED := 6.0
const BACK_CLIP_SPEED := 1.0
## Measured body travel of the UAL strafe clips in rig space: Strafe_left moves
## the body toward the rig's -X, Strafe_right toward +X.
const STRAFE_LEFT_CLIP := Vector2(-0.8, 0.0)
const STRAFE_RIGHT_CLIP := Vector2(0.7, 0.0)
const REF_LEG_HEIGHT := 0.98
const LEG_BONES := ["thigh_l", "upperleg.l", "UpperLeg.L", "thigh.L", "upperleg_l"]
## Gameplay clip choices that must beat the asset library. `Assets._ual_for`
## only adds its KayKit-name aliases when the name is missing, so the extra
## Mesh2Motion library's own 4.46 s `Death_A` shadows `Death_A -> Death01` and
## keeps a dying actor upright for over a second. `Hit_B` (UAL
## `Hit_Knockback`) throws the body to the ground and sinks up to 34 cm under
## the floor on retargeted rigs (HIT_KNOCKBACK_FLOOR_CONTACT_REVIEW.md); the
## shield-recoil clip keeps both soles planted while the hips drop into a
## heavy stagger, and the capsule impulse still supplies the push.
const PREFERRED_CLIPS := {"Death_A": "Death01", "Hit_B": "Block_Hit", "Hit_Knockback": "Block_Hit"}
## Speed filter response (1/s). Movement is already shaped by the controllers;
## this only removes tick-to-tick noise, so keep it short.
const SPEED_RESPONSE := 18.0
## Turning on the spot: yaw rate (rad/s) times this radius (m) drives a short
## stepping gait so the feet reposition instead of the body spinning on planted soles.
const TURN_STEP_RADIUS := 0.2
## Cadence limits relative to the clips' natural rate: slower than this reads as
## slow motion, faster as frantic. Outside the band the feet slide a little instead.
const MIN_CADENCE := 0.55
const MAX_CADENCE := 1.4
## Guard-stance shuffles read fine quicker than a gait, which keeps the soles
## planted at the controllers' block speeds (1.2 m/s player).
const MAX_STRAFE_CADENCE := 1.7
## Alternate locomotion sets (built only with `with_stances`): name ->
## [idle clips, moving clips, ground speed of the moving clip at rate 1 (0 =
## static pose)]. The first clip the library has wins. Crouch_Fwd and Swim_Fwd
## speeds are estimates from their stride (not in the anim QA report yet).
const STANCES := {
	"crouch": [["Crouch_Idle"], ["Crouch_Fwd", "Walk_Stealth"], 1.1],
	"swim": [["Swim_Idle"], ["Swim_Fwd"], 2.2],
	"ride": [["Driving", "Sitting_Idle", "Sit_Floor_Idle"], ["Driving", "Sitting_Idle", "Sit_Floor_Idle"], 0.0],
}
const STANCE_BLEND := 5.0        # 1/s cross-fade into and out of a stance

var tree: AnimationTree
var player: AnimationPlayer
## Extra stride multiplier for a body scaled after construction (the player's
## child years). Leg length at construction is measured automatically.
var stride_scale := 1.0
## Optional procedural rig (scripts/actors/procedural_rig.gd) fed from update():
## foot IK eases off for whole-body actions and turns off for swim/ride stances
## and terminal poses. Owners with more state (airborne) call its set_state after.
var rig: Node
var _root: AnimationNodeBlendTree
var _upper_anim: AnimationNodeAnimation
var _full_anim: AnimationNodeAnimation
var _block_target := 0.0
var _block := 0.0
var _speed := 0.0
var _turn := 0.0
var _last_yaw := NAN
var _last_pos := Vector3.INF
var _move_dir := Vector3.ZERO

var _model: Node3D
var _anim_root: Node
var _skeleton: Skeleton3D
var _walk_pt := WALK_CLIP_SPEED
var _run_pt := RUN_CLIP_SPEED
var _walk_len := 1.0
var _run_len := 1.0
var _has_strafe := false
var _strafe_fw := WALK_CLIP_SPEED
var _strafe_bw := BACK_CLIP_SPEED
var _strafe_l := STRAFE_LEFT_CLIP
var _strafe_r := STRAFE_RIGHT_CLIP
var _strafe_cadence := Vector2.ONE   # (side, back) natural cycles per second
var _phase := 0.0
var _step_ready := false
var _strafe_target := 0.0
var _strafe := 0.0
var _has_stances := false
var _stance := ""
var _stance_w := 0.0
var _stance_clip_speed := 0.0
var _stance_lens := Vector2.ONE   # (idle, move) clip lengths
var _has_air := false
var _air_state: AnimationNodeStateMachinePlayback
var _air_weight := 0.0
var _air_target := 0.0


func _init(model: Node3D, run_speed: float, _walk_speed := -1.0, walk_anim := "Walking_A", run_anim := "Running_A", idle_anim := "Idle", with_stances := false, with_air := false) -> void:
	_model = model
	player = Assets.animation_player(model)
	_anim_root = player.get_node(player.root_node)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_root = AnimationNodeBlendTree.new()

	var leg := _leg_factor(model)
	_walk_pt = WALK_CLIP_SPEED * leg
	_run_pt = RUN_CLIP_SPEED * leg
	_walk_len = _clip_length(walk_anim)
	_run_len = _clip_length(run_anim)

	_root.add_node("idle_anim", _anim(idle_anim), Vector2(-400, -200))
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = maxf(maxf(run_speed, 7.5), _run_pt + 0.5)
	gait.sync = true   # both cycles keep advancing, so their shared phase never drifts
	gait.add_blend_point(_cycle(walk_anim), _walk_pt)
	gait.add_blend_point(_cycle(run_anim), _run_pt)
	_root.add_node("gait", gait, Vector2(-400, 0))
	_root.add_node("gait_rate", AnimationNodeTimeScale.new(), Vector2(-250, 0))
	var move := AnimationNodeBlend2.new()
	move.sync = true
	_root.add_node("loco", move, Vector2(-100, 0))
	_root.connect_node("gait_rate", 0, "gait")
	_root.connect_node("loco", 0, "idle_anim")
	_root.connect_node("loco", 1, "gait_rate")
	var loco_out := "loco"

	_has_strafe = player.has_animation("Walk_Backwards") and player.has_animation("Strafe_left") \
			and player.has_animation("Strafe_right") and player.has_animation(walk_anim)
	if _has_strafe:
		_strafe_fw = WALK_CLIP_SPEED * leg
		_strafe_bw = BACK_CLIP_SPEED * leg
		_strafe_l = STRAFE_LEFT_CLIP * leg
		_strafe_r = STRAFE_RIGHT_CLIP * leg
		_strafe_cadence = Vector2(1.0 / _clip_length("Strafe_left"), 1.0 / _clip_length("Walk_Backwards"))
		var strafe := AnimationNodeBlendSpace2D.new()
		strafe.min_space = Vector2(-2.0, -2.0) * maxf(leg, 1.0)
		strafe.max_space = Vector2(2.0, 2.0) * maxf(leg, 1.0)
		strafe.sync = true
		strafe.add_blend_point(_anim(idle_anim), Vector2.ZERO)
		strafe.add_blend_point(_cycle(walk_anim), Vector2(0.0, _strafe_fw))
		strafe.add_blend_point(_cycle("Walk_Backwards"), Vector2(0.0, -_strafe_bw))
		strafe.add_blend_point(_cycle("Strafe_left"), _strafe_l)
		strafe.add_blend_point(_cycle("Strafe_right"), _strafe_r)
		_root.add_node("strafe", strafe, Vector2(-400, 400))
		_root.add_node("strafe_rate", AnimationNodeTimeScale.new(), Vector2(-250, 400))
		_root.add_node("guard_feet", AnimationNodeBlend2.new(), Vector2(50, 200))
		_root.connect_node("strafe_rate", 0, "strafe")
		_root.connect_node("guard_feet", 0, "loco")
		_root.connect_node("guard_feet", 1, "strafe_rate")
		loco_out = "guard_feet"

	if with_stances:
		# Stance set: its own idle and moving loops, each on a stretched one-second
		# timeline with its own rate, mixed by speed and faded over the gait.
		_has_stances = true
		_root.add_node("st_idle", _cycle(idle_anim), Vector2(-400, 600))
		_root.add_node("st_idle_rate", AnimationNodeTimeScale.new(), Vector2(-250, 600))
		_root.add_node("st_move", _cycle(walk_anim), Vector2(-400, 750))
		_root.add_node("st_move_rate", AnimationNodeTimeScale.new(), Vector2(-250, 750))
		_root.add_node("st_mix", AnimationNodeBlend2.new(), Vector2(-100, 650))
		_root.add_node("stance", AnimationNodeBlend2.new(), Vector2(100, 400))
		_root.connect_node("st_idle_rate", 0, "st_idle")
		_root.connect_node("st_move_rate", 0, "st_move")
		_root.connect_node("st_mix", 0, "st_idle_rate")
		_root.connect_node("st_mix", 1, "st_move_rate")
		_root.connect_node("stance", 0, loco_out)
		_root.connect_node("stance", 1, "st_mix")
		loco_out = "stance"

	_root.add_node("block_anim", _anim("Blocking"), Vector2(0, 200))
	var block := AnimationNodeBlend2.new()
	_filter_upper(block)
	_root.add_node("block", block, Vector2(250, 0))

	_upper_anim = _anim("1H_Melee_Attack_Chop")
	_root.add_node("upper_anim", _upper_anim, Vector2(250, 200))
	var upper_speed := AnimationNodeTimeScale.new()
	_root.add_node("upper_speed", upper_speed, Vector2(400, 200))
	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.08
	upper.fadeout_time = 0.18
	_filter_upper(upper)
	_root.add_node("upper", upper, Vector2(550, 0))

	_full_anim = _anim("Dodge_Forward")
	_root.add_node("full_anim", _full_anim, Vector2(550, 200))
	var full_speed := AnimationNodeTimeScale.new()
	_root.add_node("full_speed", full_speed, Vector2(700, 200))
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.06
	full.fadeout_time = 0.15
	_root.add_node("full", full, Vector2(850, 0))

	_root.connect_node("block", 0, loco_out)
	_root.connect_node("block", 1, "block_anim")
	_root.connect_node("upper_speed", 0, "upper_anim")
	_root.connect_node("upper", 0, "block")
	_root.connect_node("upper", 1, "upper_speed")
	_root.connect_node("full_speed", 0, "full_anim")
	_root.connect_node("full", 0, "upper")
	_root.connect_node("full", 1, "full_speed")
	var output := "full"
	var air_output := ""
	if with_air:
		_has_air = true
		# Every air clip can transition directly to every other air clip so an
		# interrupted launch or a hard landing never queues an unwanted state.
		var air_states := ["Normal", "Jump_Start", "Jump_Running_Start", "Jump_Rise", "Jump_Fall",
			"Jump_Land_Soft", "Jump_Land_Hard", "Jump_Land_Roll", "Jump_Land_Running",
			"Loco_RunStart_F", "Loco_RunStop_L", "Loco_RunStop_R"]
		var air_machine := AnimationNodeStateMachine.new()
		for state: String in air_states:
			air_machine.add_node(state, _anim("Idle" if state == "Normal" else state))
		var entry := AnimationNodeStateMachineTransition.new()
		entry.xfade_time = 0.0
		air_machine.add_transition("Start", "Normal", entry)
		for from: String in air_states:
			for to: String in air_states:
				if from == to:
					continue
				var transition := AnimationNodeStateMachineTransition.new()
				transition.xfade_time = 0.08
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				air_machine.add_transition(from, to, transition)
		_root.add_node("air_state", air_machine, Vector2(1100, 250))
		_root.add_node("air_rate", AnimationNodeTimeScale.new(), Vector2(1250, 250))
		_root.add_node("air_blend", AnimationNodeBlend2.new(), Vector2(1450, 0))
		_root.connect_node("air_rate", 0, "air_state")
		_root.connect_node("air_blend", 0, output)
		_root.connect_node("air_blend", 1, "air_rate")
		air_output = "air_blend"
	_root.connect_node("output", 0, air_output if with_air else output)

	tree = AnimationTree.new()
	tree.tree_root = _root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.root_node = tree.get_path_to(_anim_root)
	tree["parameters/gait_rate/scale"] = 1.0 / _walk_len
	if _has_air:
		tree["parameters/air_blend/blend_amount"] = 0.0
		_air_state = tree["parameters/air_state/playback"]
	if _has_stances:
		tree["parameters/stance/blend_amount"] = 0.0
	tree.active = true


func _anim(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


## A looping gait clip stretched onto a one-second timeline, so clips of
## different lengths share one normalized step phase.
func _cycle(anim_name: String) -> AnimationNodeAnimation:
	var a := _anim(anim_name)
	a.use_custom_timeline = true
	a.timeline_length = 1.0
	a.stretch_time_scale = true
	a.start_offset = 0.0
	a.loop_mode = Animation.LOOP_LINEAR
	return a


func _clip_length(anim_name: String) -> float:
	if player.has_animation(anim_name):
		return maxf(player.get_animation(anim_name).length, 0.1)
	return 1.0


## Leg length relative to the rig the clip speeds were measured on. Stride
## scales with the hip-to-sole distance, not the head height.
func _leg_factor(model: Node3D) -> float:
	for bone_name: String in LEG_BONES:
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		var xform := Transform3D.IDENTITY
		var current: Node = _skeleton
		while current != null:
			if current is Node3D:
				xform = (current as Node3D).transform * xform
			if current == model:
				break
			current = current.get_parent()
		var h := (xform * _skeleton.get_bone_global_rest(i)).origin.y
		if h > 0.05:
			return clampf(h / REF_LEG_HEIGHT, 0.35, 1.8)
	return 1.0


func _filter_upper(node: AnimationNode) -> void:
	node.filter_enabled = true
	var sk_path := String(_anim_root.get_path_to(_skeleton))
	for i in _skeleton.get_bone_count():
		var bone := _skeleton.get_bone_name(i)
		var lower := false
		for key: String in LOWER_KEYS:
			if bone.begins_with(key) or bone.contains(key):
				lower = true
				break
		if not lower:
			node.set_filter_path(NodePath("%s:%s" % [sk_path, bone]), true)


## Call every frame with the character's horizontal speed (resolved travel, not
## requested input). `move_dir` is the world travel direction for guard-stance
## strafing; when omitted it is taken from the model's own motion.
func update(delta: float, speed: float, move_dir := Vector3.ZERO) -> void:
	if delta <= 0.0:
		return
	if _has_air:
		_air_weight = move_toward(_air_weight, _air_target, 12.0 * delta)
		tree["parameters/air_blend/blend_amount"] = _air_weight
	var k := maxf(stride_scale, 0.05)
	var v := maxf(speed, 0.0) / k
	_track_motion(delta, move_dir)
	# Turning on the spot: step the feet around instead of pivoting on planted soles.
	var step_speed := minf(_turn * TURN_STEP_RADIUS / k, _walk_pt * 1.2)
	var drive := maxf(v, step_speed)
	_speed = lerpf(_speed, drive, 1.0 - exp(-SPEED_RESPONSE * delta))

	# Idle <-> gait: continuous weight, so near-zero speeds cannot chatter between states.
	var moving := smoothstep(0.06, _walk_pt * 0.6, _speed)
	tree["parameters/loco/blend_amount"] = moving
	var pos := clampf(_speed, _walk_pt, _run_pt)
	tree["parameters/gait/blend_position"] = pos
	var t := inverse_lerp(_walk_pt, _run_pt, pos)
	var stride := lerpf(_walk_pt * _walk_len, _run_pt * _run_len, t)
	var natural := lerpf(1.0 / _walk_len, 1.0 / _run_len, t)
	var rate := clampf(_speed / maxf(stride, 0.01), natural * MIN_CADENCE, natural * MAX_CADENCE)
	tree["parameters/gait_rate/scale"] = rate
	_advance_phase(delta, rate, moving)

	_block = move_toward(_block, _block_target, delta * 6.0)
	tree["parameters/block/blend_amount"] = _block
	_strafe = move_toward(_strafe, _strafe_target, delta * 6.0)
	if _has_strafe:
		_update_strafe()
	if _has_stances:
		_update_stance(delta)
	if rig:
		var off := not tree.active or _stance == "swim" or _stance == "ride"
		rig.call("set_state", maxf(speed, 0.0), true, off, is_full_busy())


func _update_stance(delta: float) -> void:
	_stance_w = move_toward(_stance_w, 1.0 if _stance != "" else 0.0, delta * STANCE_BLEND)
	tree["parameters/stance/blend_amount"] = _stance_w
	if _stance_w <= 0.0:
		return
	var v := _speed
	tree["parameters/st_mix/blend_amount"] = smoothstep(0.05, 0.5, v) if _stance_clip_speed > 0.0 else 0.0
	tree["parameters/st_idle_rate/scale"] = 1.0 / _stance_lens.x
	var cadence := clampf(v / _stance_clip_speed, 0.5, 1.6) if _stance_clip_speed > 0.0 else 1.0
	tree["parameters/st_move_rate/scale"] = cadence / _stance_lens.y


func _track_motion(delta: float, move_dir: Vector3) -> void:
	if not _model.is_inside_tree():
		return
	var basis := _model.global_basis.orthonormalized()
	var yaw := atan2(basis.z.x, basis.z.z)
	var turn := 0.0
	if not is_nan(_last_yaw):
		var dyaw := angle_difference(_last_yaw, yaw)
		# A snap (LOD return, scripted facing) is not a turn the feet should follow.
		turn = absf(dyaw) / delta if absf(dyaw) < 0.8 else 0.0
	_last_yaw = yaw
	_turn = lerpf(_turn, turn, 1.0 - exp(-14.0 * delta))
	var pos := _model.global_position
	if move_dir.length_squared() > 0.0001:
		_move_dir = Vector3(move_dir.x, 0.0, move_dir.z).normalized()
	elif _last_pos != Vector3.INF:
		var d := pos - _last_pos
		d.y = 0.0
		if d.length() > 0.0005 and d.length() < 2.0:
			_move_dir = d.normalized()
	_last_pos = pos


## Guard stance: pick forward, backward and side steps by the travel direction
## relative to the facing, at a rate that matches that direction's ground speed.
func _update_strafe() -> void:
	var guard := maxf(_block, _strafe)
	tree["parameters/guard_feet/blend_amount"] = guard
	if guard <= 0.001:
		return
	var local := Vector2.ZERO
	if _model.is_inside_tree() and _move_dir != Vector3.ZERO:
		var l := _model.global_basis.orthonormalized().inverse() * _move_dir
		local = Vector2(l.x, l.z).normalized()
	if local == Vector2.ZERO:
		local = Vector2(0.0, 1.0)
	# Ground speed of the directional blend along `local`: an ellipse through the clips.
	var side := absf(_strafe_l.x if local.x < 0.0 else _strafe_r.x)
	var fwd := _strafe_fw if local.y >= 0.0 else _strafe_bw
	var clip_speed := 1.0 / sqrt(pow(local.x / side, 2.0) + pow(local.y / fwd, 2.0))
	var s := _speed
	tree["parameters/strafe/blend_position"] = local * minf(s, clip_speed)
	var along := local.y * local.y
	var natural := lerpf(_strafe_cadence.x, 1.0 / _walk_len if local.y >= 0.0 else _strafe_cadence.y, along)
	tree["parameters/strafe_rate/scale"] = natural * clampf(s / clip_speed, 1.0, MAX_STRAFE_CADENCE)


## Follows the shared gait phase (two footfalls per cycle, left at 0.0). Both
## gait clips report the same normalized position, so the blend's position is
## the phase; while the tree is paused it is integrated from the rate instead.
func _advance_phase(delta: float, rate: float, moving: float) -> void:
	var before := _phase
	if tree.active:
		_phase = fposmod(float(tree["parameters/gait/current_position"]), 1.0)
	else:
		_phase = fmod(_phase + rate * delta, 1.0)
	var crossed := (before < 0.5 and _phase >= 0.5) or _phase < before
	if crossed and moving > 0.5:
		_step_ready = true


## True once per footfall of the locomotion cycle; use it to time step sounds
## and dust to the gait instead of to a distance guess.
func consume_footstep() -> bool:
	var due := _step_ready
	_step_ready = false
	return due


## Locomotion speed the animation is currently showing (m/s at this body size).
func shown_speed() -> float:
	return _speed * maxf(stride_scale, 0.05)


## Arms-only action (attack, cast, block hit) layered over locomotion.
func play_upper(anim_name: String, time_scale := 1.0) -> void:
	_upper_anim.animation = _clip(anim_name)
	tree["parameters/upper_speed/scale"] = time_scale
	tree["parameters/upper/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


## Whole-body action (dodge roll, stagger) that overrides locomotion.
func play_full(anim_name: String, time_scale := 1.0) -> void:
	_full_anim.animation = _clip(anim_name)
	tree["parameters/full_speed/scale"] = time_scale
	tree["parameters/full/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


## Optional whole-body air state machine, enabled on the playable character only.
func play_air(anim_name: String, time_scale := 1.0) -> void:
	if not _has_air or _air_state == null:
		return
	tree["parameters/air_rate/scale"] = time_scale
	_air_state.travel(anim_name)
	_air_target = 1.0


func finish_air() -> void:
	if not _has_air or _air_state == null:
		return
	_air_state.travel("Normal")
	_air_target = 0.0


func play_locomotion_transition(anim_name: String, time_scale: float) -> void:
	play_air(anim_name, time_scale)


func gait_phase() -> float:
	return _phase


## Hand the body back to locomotion early (dodge recovery cancelled by input).
func stop_full() -> void:
	if tree["parameters/full/active"]:
		tree["parameters/full/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT


## Cut an arms-only action short (e.g. a dodge cancelling a swing's recovery).
func stop_upper() -> void:
	if tree["parameters/upper/active"]:
		tree["parameters/upper/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT


func set_blocking(on: bool) -> void:
	_block_target = 1.0 if on else 0.0


## Lock-on footwork: directional strafe steps without raising the shield.
func set_strafing(on: bool) -> void:
	_strafe_target = 1.0 if on else 0.0


## Swaps the whole locomotion for a STANCES set ("" = normal gait). Needs
## `with_stances`; unknown or unavailable sets fall back to the normal gait.
func set_stance(stance_name: String) -> void:
	if not _has_stances or stance_name == _stance:
		return
	if stance_name == "" or not STANCES.has(stance_name):
		_stance = ""
		return
	var cfg: Array = STANCES[stance_name]
	var idle := _first_clip(cfg[0])
	var move := _first_clip(cfg[1])
	if idle == "" and move == "":
		_stance = ""
		return
	if idle == "":
		idle = move
	if move == "":
		move = idle
	(_root.get_node("st_idle") as AnimationNodeAnimation).animation = idle
	(_root.get_node("st_move") as AnimationNodeAnimation).animation = move
	_stance_lens = Vector2(_clip_length(idle), _clip_length(move))
	_stance_clip_speed = float(cfg[2])
	_stance = stance_name


func stance() -> String:
	return _stance


func _first_clip(names: Array) -> String:
	for n: String in names:
		if player.has_animation(n):
			return n
	return ""


func is_upper_busy() -> bool:
	return tree["parameters/upper/active"]


func is_full_busy() -> bool:
	return tree["parameters/full/active"]


## Death and other terminal poses bypass the tree.
func play_terminal(anim_name: String) -> void:
	tree.active = false
	player.play(_clip(anim_name), 0.1)


func set_active(on: bool) -> void:
	tree.active = on
	if on:
		_last_yaw = NAN
		_last_pos = Vector3.INF


## Resolves gameplay clip names to the clip that should actually play (see PREFERRED_CLIPS).
func _clip(anim_name: String) -> String:
	var preferred: String = PREFERRED_CLIPS.get(anim_name, "")
	if preferred != "" and player.has_animation(preferred):
		return preferred
	return anim_name
