extends Node
## Head / neck look-at on Godot 4.6's LookAtModifier3D. Two chained modifiers (neck_01 then Head)
## so the total turn is natural (neck takes a share, head the rest) and each has its own angle
## limit with a soft damp threshold near the edge; when the target leaves the cone the modifier
## eases back to the animated pose over `duration` seconds (its built-in time-based interpolation).
## Bone axes are detected from the rest pose (which local axis faces model-forward / up), so it
## works on any humanoid whose model faces +Z (all UAL characters), not just UAL.
##
##   const LookAtRig := preload("res://tools_qa/anim_tech/lib/look_at.gd")
##   var look := LookAtRig.attach(model, some_node3d)   # returns the rig node (child of the skeleton)
##   look.set_target(node)      # or null to look ahead (blends out)
##   look.set_weight(0.0..1.0)  # e.g. lower while the clip does its own head turn (attacks, talking)
##   look.active = false        # LOD: switches the modifiers off (they cost nothing then)
## No eye bones on the UAL rig; on rigs that have them add a third LookAtModifier3D on each eye
## bone with a 20 degree limit (see `_add`).
## Modifier order: AnimationMixer output -> LookAt -> anything after it; keep it before
## ProceduralRig's stages (ProceduralRig._order_modifiers already moves LookAtModifier3D first).

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
## [bone, max angle (deg), damp threshold (0-1 of the limit), blend seconds]
const STAGES := [["neck_01", 28.0, 0.6, 0.25], ["Head", 55.0, 0.5, 0.2]]

var active := true:
	set(v):
		active = v
		for m in _mods:
			m.active = v
var _sk: Skeleton3D
var _mods: Array[LookAtModifier3D] = []
var _target: Node3D


static func attach(model: Node3D, target: Node3D = null) -> Node:
	var sk := U.skeleton_of(model)
	if sk == null or sk.find_bone("Head") < 0:
		return null
	var rig: Node = (load("res://tools_qa/anim_tech/lib/look_at.gd") as GDScript).new()
	rig.name = "LookAtRig"
	sk.add_child(rig)   # lives under the skeleton so it goes with the model
	rig._build(sk, model)
	rig.set_target(target)
	return rig


func _build(sk: Skeleton3D, model: Node3D) -> void:
	_sk = sk
	_model = model
	for st: Array in STAGES:
		var b := sk.find_bone(st[0])
		if b >= 0:
			_add(b, st, model)


func _add(bone: int, st: Array, model: Node3D) -> void:
	var m := LookAtModifier3D.new()
	m.name = "Look_" + String(st[0])
	m.bone_name = st[0]
	# which bone-local axis faces the model's forward direction / up (rest pose), so no per-rig constants
	var fwd := model.global_basis.z.normalized()
	m.forward_axis = U.local_axis_towards(_sk, bone, fwd) as SkeletonModifier3D.BoneAxis
	m.primary_rotation_axis = (U.local_axis_towards(_sk, bone, Vector3.UP) / 2) as Vector3.Axis
	m.use_secondary_rotation = true
	m.relative = false
	m.use_angle_limitation = true
	m.symmetry_limitation = true
	m.primary_limit_angle = deg_to_rad(st[1])
	m.primary_damp_threshold = st[2]
	m.secondary_limit_angle = deg_to_rad(st[1] * 0.6)
	m.secondary_damp_threshold = st[2]
	m.duration = st[3]
	m.transition_type = Tween.TRANS_SINE
	m.ease_type = Tween.EASE_IN_OUT
	_sk.add_child(m)
	_mods.append(m)


func set_target(t: Node3D) -> void:
	_target = t
	for m in _mods:
		m.target_node = m.get_path_to(t) if t else NodePath()


func set_weight(w: float) -> void:
	_user_weight = w


func _exit_tree() -> void:
	for m in _mods:
		if is_instance_valid(m):
			m.queue_free()


# --- interest cone: fade the look out when the target is beside / behind the character ---------
@export var max_yaw_deg := 105.0          # beyond this the character stops looking (fully released)
@export var response := 7.0               # 1/s smoothing of the fade
var _model: Node3D
var _fade := 0.0
var _user_weight := 1.0


func _process(delta: float) -> void:
	if _target == null or not active:
		return
	var to := _target.global_position - _model.global_position
	to.y = 0.0
	var goal := 0.0
	if to.length() > 0.05:
		var yaw := absf(rad_to_deg(_model.global_basis.z.normalized().signed_angle_to(to.normalized(), Vector3.UP)))
		goal = 1.0 - smoothstep(max_yaw_deg * 0.75, max_yaw_deg, yaw)
	_fade = lerpf(_fade, goal, 1.0 - exp(-response * delta))
	for m in _mods:
		m.influence = _fade * _user_weight
