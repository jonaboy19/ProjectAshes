class_name RiderIK
extends Node
## Hands on the reins, feet in the stirrups (standalone; wiring: P14_rider_ik.md). Godot 4.6 SkeletonModifier3D stack:
## four TwoBoneIK3D modifiers on the rider's skeleton (arm L/R: upperarm -> lowerarm -> hand, leg L/R: thigh -> calf ->
## foot) with target and pole markers, plus a ReinFollow modifier on the HORSE skeleton so the reins end in the rider's
## fists even when a hand leaves them (sword, bow).
##
## The Horse_Ride clips already put hands and feet on the sockets; the IK only removes what blending, phase changes,
## LOD stepping and rider proportions add (typically 1-4 cm). calibrate() stores each end effector's offset from its
## socket in the seated idle pose, so the IK keeps the authored grip instead of forcing the wrist onto the socket.
##
##   var ik := RiderIK.new(); add_child(ik); ik.setup(horse, rider_skeleton)   # after RiderSync.attach
##   ik.hands = Vector2(1, 1)      # per hand weight on the reins (0 = free: sword hand, bow hands)
##   ik.feet = 1.0                 # feet in the stirrups (0 while mounting / dismounting)
## Cost: 4 two-bone solves per rider per frame (~0.02 ms on the PC, see HANDOFF "Performance"). LOW tier: feet only.

var horse: HorseRig
var skeleton: Skeleton3D
var hands := Vector2(1, 1):
	set(v):
		hands = v
		_apply_weights()
var feet := 1.0:
	set(v):
		feet = v
		_apply_weights()
var mods := {}              # "hand_l" -> TwoBoneIK3D ...
var targets := {}           # "hand_l" -> Marker3D
var poles := {}
var offsets := {}           # "hand_l" -> Transform3D (socket -> end bone) from calibrate()
var rein_follow: ReinFollow
const LIMBS := {
	"hand_l": ["upperarm_l", "lowerarm_l", "hand_l", "rein_grip_L", Vector3(0.45, 0.35, -0.9)],
	"hand_r": ["upperarm_r", "lowerarm_r", "hand_r", "rein_grip_R", Vector3(-0.45, 0.35, -0.9)],
	"foot_l": ["thigh_l", "calf_l", "foot_l", "stirrup_L", Vector3(0.25, 0.3, 1.0)],
	"foot_r": ["thigh_r", "calf_r", "foot_r", "stirrup_R", Vector3(-0.25, 0.3, 1.0)],
}


func setup(h: HorseRig, rider_skeleton: Skeleton3D, tier := 2) -> void:
	horse = h
	skeleton = rider_skeleton
	process_priority = 210     # after RiderSync placed the rider
	for k: String in LIMBS:
		if tier <= 0 and k.begins_with("hand"):
			continue
		var d: Array = LIMBS[k]
		var t := Marker3D.new()
		t.name = "IK_" + k
		var p := Marker3D.new()
		p.name = "Pole_" + k
		add_child(t)
		add_child(p)
		targets[k] = t
		poles[k] = p
		var m := TwoBoneIK3D.new()
		m.name = "TwoBoneIK_" + k
		skeleton.add_child(m)
		m.setting_count = 1
		m.set_root_bone_name(0, d[0])
		m.set_middle_bone_name(0, d[1])
		m.set_end_bone_name(0, d[2])
		m.set_target_node(0, m.get_path_to(t))
		m.set_pole_node(0, m.get_path_to(p))
		mods[k] = m
		offsets[k] = Transform3D.IDENTITY
	rein_follow = ReinFollow.new()
	rein_follow.name = "ReinFollow"
	rein_follow.rider_skeleton = skeleton
	horse.skeleton.add_child(rein_follow)
	_apply_weights()


## Store the authored hand/foot offsets from their sockets (call once while the synced idle plays, ~0.1 s after mounting).
func calibrate() -> void:
	for k: String in mods:
		var d: Array = LIMBS[k]
		var sock := horse.socket(d[3])
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(d[2]))
		offsets[k] = sock.affine_inverse() * end


func _process(_delta: float) -> void:
	if horse == null or not is_instance_valid(horse):
		return
	var pelvis := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))
	for k: String in mods:
		var d: Array = LIMBS[k]
		(targets[k] as Marker3D).global_transform = horse.socket(d[3]) * offsets[k]
		(poles[k] as Marker3D).global_position = pelvis.origin + skeleton.global_basis * (d[4] as Vector3)
	if rein_follow:
		rein_follow.weights = Vector2(1.0 - hands.x, 1.0 - hands.y)


func _apply_weights() -> void:
	for k: String in mods:
		(mods[k] as SkeletonModifier3D).influence = (hands.x if k == "hand_l" else hands.y) if k.begins_with("hand") else feet
