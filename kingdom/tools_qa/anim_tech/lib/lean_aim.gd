extends SkeletonModifier3D
## Procedural lean + aim twist, one SkeletonModifier3D under the Skeleton3D (runs after the clip, before nothing else).
##
##  - LEAN: the body tips into a turn (roll = -speed * yaw_rate * roll_gain) and forward with speed
##    (pitch = speed * pitch_gain), both smoothed by a critically damped spring so it lags like weight.
##    Spread over pelvis / spine_01..03 (shares below).
##  - AIM TWIST: yaw of the upper body toward `aim_target` while the legs keep following the clip, spread over
##    spine_01..03 / neck / head, limited to +-aim_limit degrees (beyond it the twist fades out, no snapping).
##
##   const LeanAim := preload("res://tools_qa/anim_tech/lib/lean_aim.gd")
##   var m := LeanAim.attach(model, actor_node3d)     # actor: the node that moves / turns (velocity + yaw are measured)
##   m.aim_target = some_node3d                       # or null; m.aim_weight 0..1 fades it
##   m.lean_weight = 1.0
## Model faces +Z (UAL). Cost: ~10 quaternion ops per frame, no allocations. LOD: `m.active = false` (or free it).

const LEAN_BONES := [["pelvis", 0.15], ["spine_01", 0.25], ["spine_02", 0.3], ["spine_03", 0.3]]
const AIM_BONES := [["spine_01", 0.2], ["spine_02", 0.25], ["spine_03", 0.3], ["neck_01", 0.1], ["Head", 0.15]]

@export var roll_gain := 0.11         # rad per (m/s * rad/s)
@export var pitch_gain := 0.03        # rad per m/s
@export var max_roll := 0.30
@export var max_pitch := 0.22
@export var stiffness := 60.0
@export var aim_limit := 75.0         # degrees
@export var lean_weight := 1.0
@export var aim_weight := 1.0

var actor: Node3D
var aim_target: Node3D
var _lean_ids: Array[int] = []
var _aim_ids: Array[int] = []
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _speed := 0.0
var _yaw_rate := 0.0
var _lean := Vector2.ZERO       # x = pitch, y = roll
var _lean_v := Vector2.ZERO
var _aim := 0.0
var _aim_v := 0.0


static func attach(model: Node3D, body: Node3D) -> SkeletonModifier3D:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var m: SkeletonModifier3D = (load("res://tools_qa/anim_tech/lib/lean_aim.gd") as GDScript).new()
	m.name = "LeanAim"
	m.set("actor", body)
	sk.add_child(m)
	m.call("_bind", sk)
	return m


func _bind(sk: Skeleton3D) -> void:
	for e: Array in LEAN_BONES:
		_lean_ids.append(sk.find_bone(e[0]))
	for e: Array in AIM_BONES:
		_aim_ids.append(sk.find_bone(e[0]))


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or actor == null or delta <= 0.0:
		return
	var dt := minf(delta, 0.05)
	# measure the actor
	var pos := actor.global_position
	var yaw := actor.global_rotation.y
	if _last_pos != Vector3.INF:
		_speed = lerpf(_speed, Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / dt, 1.0 - exp(-10.0 * dt))
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / dt, 1.0 - exp(-10.0 * dt))
	_last_pos = pos
	_last_yaw = yaw
	# lean spring (critically damped)
	var goal := Vector2(clampf(_speed * pitch_gain, 0.0, max_pitch), clampf(-_speed * _yaw_rate * roll_gain, -max_roll, max_roll)) * lean_weight
	var damp := 2.0 * sqrt(stiffness)
	_lean_v += ((goal - _lean) * stiffness - _lean_v * damp) * dt
	_lean += _lean_v * dt
	var skq := sk.global_basis.get_rotation_quaternion()
	if _lean.length() > 0.002:
		var q_lean := Quaternion(Vector3.RIGHT, _lean.x) * Quaternion(Vector3.BACK, _lean.y)
		for i in _lean_ids.size():
			if _lean_ids[i] >= 0:
				_apply(sk, _lean_ids[i], Quaternion.IDENTITY.slerp(q_lean, LEAN_BONES[i][1]))
	# aim twist
	var aim_goal := 0.0
	if aim_target != null and aim_weight > 0.0:
		var local := sk.global_transform.affine_inverse() * aim_target.global_position
		var a := atan2(local.x, local.z)
		var lim := deg_to_rad(aim_limit)
		# fade out beyond the limit instead of clamping hard (no snap when the target passes behind)
		aim_goal = clampf(a, -lim, lim) * (1.0 - smoothstep(lim, lim + 0.8, absf(a))) * aim_weight
	var adamp := 2.0 * sqrt(stiffness * 1.5)
	_aim_v += ((aim_goal - _aim) * stiffness * 1.5 - _aim_v * adamp) * dt
	_aim += _aim_v * dt
	if absf(_aim) > 0.002:
		for i in _aim_ids.size():
			if _aim_ids[i] >= 0:
				_apply(sk, _aim_ids[i], Quaternion(Vector3.UP, _aim * AIM_BONES[i][1]))
	skq = skq  # (skeleton space is used directly: model faces +Z, up = +Y)


## Rotates `bone` by `q` given in skeleton space.
func _apply(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var parent := sk.get_bone_parent(bone)
	var pq := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var cq := sk.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, (pq.inverse() * q * cq).normalized())
