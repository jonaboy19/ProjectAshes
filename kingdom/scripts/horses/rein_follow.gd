class_name ReinFollow
extends SkeletonModifier3D
## Horse-skeleton modifier: moves the rein grip bones (the hand ends of the skinned reins) to the rider's fists when a
## hand has let go of the reins (weights 1 = follow the rider's hand, 0 = keep the animated grip, which is where the
## hands normally are). Uses the rider pose of the previous frame (one frame of lag, invisible at 60 fps).

var rider_skeleton: Skeleton3D
var weights := Vector2.ZERO
const PAIRS := [["rein_grip_L", "hand_l"], ["rein_grip_R", "hand_r"]]


func _process_modification_with_delta(_delta: float) -> void:
	_modify()


func _process_modification() -> void:
	_modify()


func _modify() -> void:
	var sk := get_skeleton()
	if sk == null or rider_skeleton == null or not is_instance_valid(rider_skeleton) or weights == Vector2.ZERO:
		return
	var inv := sk.global_transform.affine_inverse()
	for i in 2:
		var w := weights[i]
		if w <= 0.001:
			continue
		var b := sk.find_bone(PAIRS[i][0])
		var h := rider_skeleton.find_bone(PAIRS[i][1])
		if b < 0 or h < 0:
			continue
		var want := inv * rider_skeleton.global_transform * rider_skeleton.get_bone_global_pose(h)
		var cur := sk.get_bone_global_pose(b)
		cur.origin = cur.origin.lerp(want.origin, w)
		sk.set_bone_global_pose(b, cur)
