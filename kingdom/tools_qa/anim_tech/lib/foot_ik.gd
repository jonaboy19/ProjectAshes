extends "res://scripts/actors/procedural_rig.gd"
## Stair-safe foot IK: ProceduralRig (TwoBoneIK3D per leg, pelvis drop, foot tilt) plus a second
## ground probe under the BALL of each foot. ProceduralRig probes only under the ankle, so on a
## step edge the toes poke through the riser (measured 12-17 cm on 17 cm stairs); taking the higher
## of the ankle and ball surfaces lifts the foot over the edge. Everything else is inherited.
##
##   const FootIK := preload("res://tools_qa/anim_tech/lib/foot_ik.gd")
##   var rig := FootIK.attach_toe(model, body)      # same contract as ProceduralRig.attach
##   rig.set_state(speed, grounded)                 # optional, same as ProceduralRig
##   rig.set_paused(true)                           # ragdoll / cutscene
## LOD: the parent already switches itself off beyond ACTIVE_RANGE and ranks by camera distance
## (Quality "rig_budget"); rays cost 4 per active rig per physics tick.
## If it proves itself, the two probe lines below can be folded into ProceduralRig._physics_process.

var _ball: Array[int] = [-1, -1]
var _ball_rest: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # ball origin in foot-bone space


static func attach_toe(model: Node3D, body: Node3D = null, player := false) -> Node:
	var rig: Node = (load("res://tools_qa/anim_tech/lib/foot_ik.gd") as GDScript).new()
	if not rig.call("_setup", model, body, true, true):
		rig.free()
		return null
	rig.set("always_near", player)
	return rig


func _ready() -> void:
	super()
	if _use_ik:
		for i in 2:
			var name_ := "ball_l" if i == 0 else "ball_r"
			_ball[i] = _skeleton.find_bone(name_)
			if _ball[i] >= 0:
				_ball_rest[i] = _skeleton.get_bone_rest(_ball[i]).origin


func _physics_process(delta: float) -> void:
	super(delta)
	if not _has_anim or suppressed:
		return
	var space := _model.get_world_3d().direct_space_state
	var base_y := _model.global_position.y
	var xf := _skeleton.global_transform
	for i in 2:
		if _ball[i] < 0 or not _hit[i]:
			continue
		# animated ball position: ankle + (rest offset rotated by the animated foot orientation)
		var ball_pos: Vector3 = _foot_anim[i] + xf.basis * (Basis(_foot_rot[i]) * _ball_rest[i])
		_query.from = Vector3(ball_pos.x, base_y + _leg_len * 0.55, ball_pos.z)
		_query.to = Vector3(ball_pos.x, base_y - _leg_len * 0.6, ball_pos.z)
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_hit_y[i] = maxf(_hit_y[i], (hit["position"] as Vector3).y)


## Rising ground is followed instantly, falling ground is smoothed by the parent (GROUND_RATE).
## The parent smooths both ways, so the foot lags a fresh stair riser for ~50 ms and the toes end
## up inside the step. Pre-loading `_ground` with the new height makes its lerp land on the target
## for a rise and leaves it untouched for a drop.
func _pre_modify(delta: float) -> void:
	if _use_ik and _has_anim:
		var base_y := _model.global_position.y
		var max_drop := _leg_len * 0.38
		for i in 2:
			if _hit[i]:
				var d := clampf(_hit_y[i] - base_y, -max_drop, _leg_len * 0.5)
				if d > _ground[i]:
					_ground[i] = d
	super(delta)
