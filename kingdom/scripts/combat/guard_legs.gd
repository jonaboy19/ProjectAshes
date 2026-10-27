extends SkeletonModifier3D
## Guard legs during a swing's recovery (combat-motion worker; coordinator FAIL 3 "player stands tall between swings").
## The Mixamo slashes finish upright; ref 03 wants a wide, bent-knee base. This blends ONLY the legs and the pelvis
## height toward the weapon's measured guard pose (Mx_SnS_Block_Idle: feet 1.05 m apart, pelvis -22 cm; see
## tools_qa/combat/stance_measure.gd) while the upper body keeps the clip's follow-through: an additive crouch, built
## on Godot's SkeletonModifier3D stack (runs after the AnimationTree, before nothing of ours).
##
##   var g := GuardLegs.attach(skeleton, animation_player, "Mx_SnS_Block_Idle")
##   g.target = 1.0 during recovery, 0.0 otherwise (smoothed at RATE per second)
## Cost: 9 bone slerps per frame while weight > 0; idle (weight 0) it returns at once.

const BONES := ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
const RATE := 9.0             ## 1/s toward the target weight (in ~0.25 s, out ~0.25 s)
const MAX_WEIGHT := 0.75      ## never a full pose swap: the clip's own foot placement still shows through

var target := 0.0
var weight := 0.0
## Pelvis-only crouch (guard while strafing / lock-on idle): lowers the hips toward the guard height without touching the
## leg rotations, so moving feet keep their stepping clip; the rig's foot IK (it runs after this stage) bends the knees.
var crouch_target := 0.0
var crouch := 0.0
var _ids: Array[int] = []
var _rots: Array[Quaternion] = []
var _pelvis := -1
var _pelvis_y := NAN
var _rest_pelvis_y := 0.0


static func attach(sk: Skeleton3D, ap: AnimationPlayer, guard_clip: String) -> SkeletonModifier3D:
	if sk == null or ap == null or not ap.has_animation(guard_clip):
		return null
	var g: SkeletonModifier3D = (load("res://scripts/combat/guard_legs.gd") as GDScript).new()
	g.name = "GuardLegs"
	sk.add_child(g)
	sk.move_child(g, 0)      # first in the stack: the rig's foot IK runs after it and keeps the soles on the ground
	g.call("bind", sk, ap.get_animation(guard_clip))
	return g


## Sample the guard pose (frame 0) for the leg bones and the pelvis height, as bone-local poses.
func bind(sk: Skeleton3D, anim: Animation) -> void:
	_ids.clear()
	_rots.clear()
	for bn: String in BONES:
		var b := sk.find_bone(bn)
		var tr := _track(anim, bn, Animation.TYPE_ROTATION_3D)
		if b < 0 or tr < 0:
			continue
		_ids.append(b)
		_rots.append(anim.rotation_track_interpolate(tr, 0.0))
	_pelvis = sk.find_bone("pelvis")
	var pt := _track(anim, "pelvis", Animation.TYPE_POSITION_3D)
	if _pelvis >= 0 and pt >= 0:
		_pelvis_y = anim.position_track_interpolate(pt, 0.0).y
		_rest_pelvis_y = sk.get_bone_rest(_pelvis).origin.y


static func _track(anim: Animation, bone: String, type: int) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type and String(anim.track_get_path(i)).ends_with(":" + bone):
			return i
	return -1


## Pure: the blended weight after `dt` (tests).
static func step_weight(w: float, tgt: float, dt: float) -> float:
	return move_toward(w, clampf(tgt, 0.0, 1.0) * MAX_WEIGHT, RATE * MAX_WEIGHT * dt)


func _process_modification_with_delta(delta: float) -> void:
	weight = step_weight(weight, target, delta)
	crouch = step_weight(crouch, crouch_target, delta)
	if weight <= 0.001 and crouch <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	for i in (_ids.size() if weight > 0.001 else 0):
		var b := _ids[i]
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(_rots[i], weight))
	if _pelvis >= 0 and not is_nan(_pelvis_y):
		var p := sk.get_bone_pose_position(_pelvis)
		# lower toward the guard height only (never raise a deeper pose), x/z stay the clip's
		if _pelvis_y < p.y:
			p.y = lerpf(p.y, _pelvis_y, maxf(weight, crouch))
			sk.set_bone_pose_position(_pelvis, p)
