extends RefCounted
## Motion warping: a root-motion attack / lunge that lands on a moving or off-axis target.
##
## While the player runs a clip with its root motion enabled (U.enable_root_motion), every frame inside the warp
## window [t0, t1] this
##   - turns the actor towards the target (exponential, `turn_rate`),
##   - scales the horizontal root motion so the remaining clip travel equals the remaining distance to the stop
##     point (target minus `stop_dist` along the approach line). Closed loop, so a moving target is tracked and the
##     end error is ~0 whatever the ratio (clamped to [min_scale, max_scale] so it never looks like a teleport).
## Outside the window the clip's own root motion plays 1:1. Vertical travel is never scaled.
##
##   const MotionWarp := preload("res://tools_qa/anim_tech/lib/motion_warp.gd")
##   var w := MotionWarp.new()
##   w.begin(ap, skeleton, actor, "at/MA_Kick_Jump_R", target_node_or_pos, 0.9)   # window auto-detected from the clip
##   # every frame after the player advanced (_process):
##   w.step(delta)
##   w.done   # true after the clip's end
## Tuning: `stop_dist` = where the attacker should stand (weapon reach), `turn_rate` 10-14 /s, scale clamp 0.4-2.2.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")

var turn_rate := 12.0
var min_scale := 0.35
var max_scale := 2.4
var done := false
var scale_used := 1.0          # last applied travel scale (debug / HUD)

var _ap: AnimationPlayer
var _sk: Skeleton3D
var _actor: Node3D
var _anim: Animation
var _target: Variant           # Node3D or Vector3
var _stop := 0.9
var _t0 := 0.0
var _t1 := 0.0


## Window = the part of the clip where the root moves (10 % .. 95 % of the total horizontal travel).
func begin(ap: AnimationPlayer, sk: Skeleton3D, actor: Node3D, clip: String, target: Variant, stop_dist: float) -> void:
	_ap = ap
	_sk = sk
	_actor = actor
	_anim = ap.get_animation(clip)
	_target = target
	_stop = stop_dist
	done = false
	var total := _horiz(U.root_at(_anim, _anim.length))
	_t0 = 0.0
	_t1 = _anim.length
	var found0 := false
	var t := 0.0
	while t <= _anim.length:
		var d := _horiz(U.root_at(_anim, t))
		if not found0 and d >= total * 0.10:
			_t0 = t
			found0 = true
		if d >= total * 0.95:
			_t1 = t
			break
		t += 1.0 / 30.0
	_ap.play(clip)


func window() -> Vector2:
	return Vector2(_t0, _t1)


func _horiz(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _target_pos() -> Vector3:
	return (_target as Node3D).global_position if _target is Node3D else (_target as Vector3)


func step(delta: float) -> void:
	if _ap == null or done:
		return
	var t := _ap.current_animation_position
	if not _ap.is_playing() or t >= _anim.length - 0.001:
		done = true
	var s := 1.0
	if t >= _t0 - 0.001 and t <= _t1:
		var to := _target_pos() - _actor.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.01:
			var want_yaw := atan2(to.x, to.z)
			_actor.rotation.y = lerp_angle(_actor.rotation.y, want_yaw, 1.0 - exp(-turn_rate * delta))
		var dir := to / maxf(dist, 0.001)
		var need := maxf(dist - _stop, 0.0)
		var sc := _sk.global_basis.get_scale().x
		var rem := _horiz(U.root_at(_anim, _t1) - U.root_at(_anim, t)) * sc
		# the frame's own travel is already part of `rem` -> leave a little (this frame) out
		s = clampf(need / maxf(rem, 0.02), min_scale, max_scale) if rem > 0.02 else 1.0
		if need < 0.02:
			s = 0.0
		dir = dir     # (kept for clarity: travel follows the actor's yaw, which now faces the target)
	scale_used = s
	U.apply_root_motion(_ap, _sk, _actor, s)
