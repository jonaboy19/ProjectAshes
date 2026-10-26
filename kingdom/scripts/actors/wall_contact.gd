class_name WallContact
extends RefCounted
## Wall contact for the player (PC): what the body does when the stick pushes into a wall.
##
## Before this, pushing into a wall left `_idle_time` growing while the stick was held, so the locomotion-transition
## logic re-fired `Loco_RunStart_F` / `Loco_WalkStart_F` every time the previous one ended: the legs ran in place.
## Now a wall in the way is a state:
##   NONE      nothing in reach, or the stick is not pushing into it
##   APPROACH  head-on, wall inside the lead distance: the speed is capped so the body stops 0.25 m short
##   BRACE     blocked (speed < 0.3) and pushing: legs idle (no start clip), the hand(s) go to the wall at shoulder height,
##             a small forward lean
##   GLANCE    sliding along the wall at an angle: the torso turns away from it, a little roll, speed is kept
##   IMPACT    a sprint straight into the wall (>= impact_speed): a heavy full-body flinch, a small camera shake, -stamina
## `classify()` is pure (tests). `tick()` reads the slide collisions of the last move_and_slide() plus one chest ray.
## Config: data/movement/traversal.json "wall_contact" (mirrored in Traversal.DEFAULTS).
## Hand placement uses ProceduralRig.set_hand_brace (arm IK) and set_torso_yaw_offset.

const NONE := &"none"
const APPROACH := &"approach"
const BRACE := &"brace"
const GLANCE := &"glance"
const IMPACT := &"impact"

const DEFAULTS := {"ray_h": 1.2, "lead": 0.35, "lead_per_speed": 0.12, "brace_push": 0.75, "glance_push": 0.2, "impact_push": 0.85,
	"impact_speed": 6.0, "touch": 0.12, "stop_gap": 0.12, "reach_min": 0.3, "reach_max": 0.7, "shoulder_h": 1.35,
	"blend_in": 0.15, "blend_out": 0.2, "lean": 0.04, "glance_roll": 0.05, "torso_yaw_max_deg": 25.0,
	"impact_cooldown": 1.0, "impact_stamina": 5.0, "impact_clip": "Hit_Heavy_Front", "impact_rate": 1.2, "hold": 0.12}

var state: StringName = NONE
var normal := Vector3.ZERO           ## horizontal wall normal (points out of the wall), ZERO when no wall
var gap := 0.0                       ## metres between the capsule surface and the wall
var push := 0.0                      ## stick direction . into-the-wall, 0..1
var _hold := 0.0
var _peak := 0.0
var _cool := 0.0
var _w: Array[float] = [0.0, 0.0]    ## hand brace weights, [left, right]
var _yaw := 0.0
var _roll := 0.0
var _lean := 0.0
var _cap := -1.0
var _ray := PhysicsRayQueryParameters3D.new()
var _hand_pt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_n := Vector3.ZERO


static func config() -> Dictionary:
	var c: Variant = (load("res://scripts/actors/traversal.gd") as GDScript).call("config").get("wall_contact")
	if c is Dictionary:
		var d: Dictionary = DEFAULTS.duplicate()
		d.merge(c, true)
		return d
	return DEFAULTS


## Pure: the contact state for a stick direction (`input_dir`, horizontal, length 0..1), the wall's horizontal normal,
## the body's current ground speed, `dist` = gap between the capsule surface and the wall, and the speed the body had
## on the way in (`approach_speed`, negative = use `speed`). Returns one of the state names above.
static func classify(input_dir: Vector3, wall_normal: Vector3, speed: float, dist: float, approach_speed := -1.0, cfg := {}) -> StringName:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var n := Vector3(wall_normal.x, 0.0, wall_normal.z)
	var d := Vector3(input_dir.x, 0.0, input_dir.z)
	if n.length_squared() < 0.0001 or d.length() < 0.1:
		return NONE
	var p := d.normalized().dot(-n.normalized())
	if p <= float(c["glance_push"]):
		return NONE
	var touching := dist <= float(c["touch"])
	var came := approach_speed if approach_speed >= 0.0 else speed
	if p > float(c["impact_push"]) and came >= float(c["impact_speed"]) and touching:
		return IMPACT
	if p > float(c["brace_push"]):
		# blocked: pressed to the wall without moving, or stopped at the stop gap. Still moving while touching (up a ramp,
		# slowly along the wall) is not blocked: the legs keep their gait.
		if touching and speed < 0.35:
			return BRACE
		if touching:
			return GLANCE
		if speed < 0.3 and dist <= float(c["stop_gap"]) + 0.06:
			return BRACE
		# a walk eases down to the stop gap; a sprint (>= impact_speed) does not, it hits the wall
		if came < float(c["impact_speed"]) and dist <= float(c["lead"]) + came * float(c["lead_per_speed"]):
			return APPROACH
		return NONE
	return GLANCE if touching else NONE


## Which hands the brace uses: [left, right] in 0..1. A wall dead ahead gets both; an oblique one only the near hand.
## `lateral` = wall direction . character-left (+ = the wall is on the left). `reach` = shoulder-to-wall distance in metres of an
## adult body (divide by the model scale first; the UAL adult arm is 0.63 m shoulder to wrist).
static func hands_for(lateral: float, reach: float, cfg := {}) -> Array[float]:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	if reach < float(c["reach_min"]) or reach > float(c["reach_max"]):
		return [0.0, 0.0]
	if lateral > 0.35:
		return [1.0, 0.0]
	if lateral < -0.35:
		return [0.0, 1.0]
	return [1.0, 1.0]


## Share of the slide along the wall that survives while braced: 1 at the brace threshold, 0 head-on. Used by GroundRealism.
func slide_scale() -> float:
	var bp := float(config()["brace_push"])
	return clampf((1.0 - push) / maxf(1.0 - bp, 0.01), 0.0, 1.0)


func blocked() -> bool:
	return state == BRACE or (state == IMPACT)


## Speed cap for the next move: ease down to a stop `stop_gap` short of a wall dead ahead.
func limit_speed(speed: float) -> float:
	if state == BRACE and gap > float(config()["stop_gap"]) + 0.01:
		return minf(speed, 0.4)          # creep the last centimetres to the stop gap
	if state == BRACE and gap > float(config()["touch"]):
		return 0.0                       # at the stop gap: hold there
	if state != APPROACH or _cap < 0.0:
		return speed
	return minf(speed, _cap)


## Extra lean for the model: x = pitch (+ forward), y = roll.
func lean() -> Vector2:
	return Vector2(_lean, _roll)


## Call after move_and_slide(). `dir` is the stick direction in world space.
func tick(body: CharacterBody3D, dir: Vector3, delta: float) -> void:
	_dt = delta
	var c := config()
	_cool = maxf(_cool - delta, 0.0)
	var real := body.get_real_velocity()
	var speed := Vector2(real.x, real.z).length()
	_peak = maxf(speed, _peak - 20.0 * delta)
	if not _enabled(body) or dir.length() < 0.1:
		_release(delta, c, 0.0 if dir.length() < 0.1 else _hold)
		return
	# 1. a wall: the strongest push among the slide collisions, else a chest ray along the stick direction
	var best_n := Vector3.ZERO
	var best_push := 0.0
	var best_gap := 99.0
	var dn := dir.normalized()
	for i in body.get_slide_collision_count():
		var col := body.get_slide_collision(i)
		var n := col.get_normal()
		if not _is_wall(n):
			continue
		var nh := Vector3(n.x, 0.0, n.z).normalized()
		var p := dn.dot(-nh)
		if p > best_push:
			best_push = p
			best_n = nh
			best_gap = 0.0
	var radius := _radius(body)
	var scale_k := _body_k(body)
	if best_n == Vector3.ZERO:
		var space := body.get_world_3d().direct_space_state
		var from := body.global_position + Vector3.UP * float(c["ray_h"]) * scale_k
		var reach := radius + float(c["lead"]) + _peak * float(c["lead_per_speed"])
		_ray.from = from
		_ray.to = from + dn * reach
		_ray.collision_mask = 1
		_ray.exclude = [body.get_rid()]
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			var hn: Vector3 = hit["normal"]
			if _is_wall(hn):
				var nh2 := Vector3(hn.x, 0.0, hn.z).normalized()
				best_push = dn.dot(-nh2)
				best_n = nh2
				best_gap = maxf((hit["position"] as Vector3 - from).length() - radius, 0.0)
	if best_n != Vector3.ZERO and _steppable(body, dn):
		best_n = Vector3.ZERO            # a stair riser or kerb the step-up (Traversal.step_assist) takes: not a wall
	if best_n == Vector3.ZERO:
		_release(delta, c, 0.0)
		return
	normal = best_n
	gap = best_gap
	push = best_push
	var st := classify(dir, best_n, speed, best_gap, _peak, c)
	if st == IMPACT and _cool > 0.0:
		st = BRACE if speed < 0.3 else GLANCE
	if st == NONE and state == BRACE and push > 0.5 and speed < 0.5:
		st = BRACE                       # no flicker while the body is still pressed to the wall
	if st != NONE:
		_hold = float(c["hold"])
	elif _hold > 0.0 and state != NONE:
		_hold -= delta
		st = state
	var was := state
	state = st
	_cap = -1.0
	if st == APPROACH:
		var room := maxf(gap - float(c["stop_gap"]), 0.0)
		_cap = clampf(room / maxf(float(c["lead"]) + _peak * float(c["lead_per_speed"]), 0.1), 0.0, 1.0) * maxf(speed, 1.5)
	if st == IMPACT and was != IMPACT:
		_impact(body, c)
	_pose(body, dir, speed, c, delta)


## True when the obstacle in front is a small edge the body steps onto (stairs, kerbs): bracing there would stop the step-up.
func _steppable(body: CharacterBody3D, dir: Vector3) -> bool:
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var trav := load("res://scripts/actors/traversal.gd") as GDScript
	_excl = [body.get_rid()]
	return float(trav.call("step_height", space, feet, dir, _radius(body) + 0.4, _excl)) > 0.0


var _excl: Array = []


func _enabled(body: CharacterBody3D) -> bool:
	if bool(body.get("dead")) or bool(body.get("blocking")) or bool(body.get("swimming")) or bool(body.get("crouching")):
		return false
	if int(body.get("view")) == 0:                      # View.FIRST
		return false
	if body.get("_mount") != null:
		return false
	var trav: Variant = body.get("_trav")
	if trav != null and trav.has_method("busy") and bool(trav.call("busy")):
		return false
	if not body.is_on_floor() and not body.is_on_wall():
		return false                                  # (a ramp steeper than the floor limit reports on_wall)
	return float(body.get("_swing")) <= 0.0 and float(body.get("_dodge")) <= 0.0


func _radius(body: CharacterBody3D) -> float:
	for ch in body.get_children():
		if ch is CollisionShape3D:
			var sh := (ch as CollisionShape3D).shape
			if sh is CapsuleShape3D:
				return (sh as CapsuleShape3D).radius * body.global_basis.get_scale().x
	return 0.35


## Not touching anything that matters: ease the hands, yaw and lean back to nothing.
func _release(delta: float, c: Dictionary, hold: float) -> void:
	_brace_yaw = lerpf(_brace_yaw, 0.0, 1.0 - exp(-6.0 * delta))
	if hold > 0.0 and state != NONE:
		_hold = hold - delta
		if _hold > 0.0:
			return
	state = NONE
	normal = Vector3.ZERO
	push = 0.0
	_cap = -1.0
	_apply_weights(delta, c, [0.0, 0.0], 0.0, 0.0, 0.0)


func _pose(body: CharacterBody3D, dir: Vector3, speed: float, c: Dictionary, delta: float) -> void:
	var want_w: Array[float] = [0.0, 0.0]
	var yaw := 0.0
	var roll := 0.0
	var lean := 0.0
	var fwd := body.global_basis.z.normalized() if body.get("_model") == null else (body.get("_model") as Node3D).global_basis.z.normalized()
	var left := Vector3.UP.cross(fwd)
	var lateral := (-normal).dot(left)
	match state:
		BRACE, IMPACT:
			lean = float(c["lean"])
			yaw = _square_shoulders()
			var k := _body_k(body)
			var sh := body.global_position + Vector3.UP * float(c["shoulder_h"]) * k
			var space := body.get_world_3d().direct_space_state
			_ray.from = sh
			_ray.to = sh - normal * (float(c["reach_max"]) + 0.3) * k
			_ray.collision_mask = 1
			_ray.exclude = [body.get_rid()]
			var hit := space.intersect_ray(_ray)
			if not hit.is_empty() and _is_wall(hit["normal"]):
				var reach := (hit["position"] as Vector3 - sh).length() / k
				want_w = hands_for(lateral, reach, c)
				var p: Vector3 = hit["position"]
				_hand_n = Vector3(hit["normal"].x, 0.0, hit["normal"].z).normalized()
				var tangent := Vector3.UP.cross(_hand_n)
				var both: bool = want_w[0] > 0.0 and want_w[1] > 0.0
				var off := 0.18 if both else 0.0
				var base := p + _hand_n * 0.02 + Vector3.UP * 0.05
				_hand_pt = [base + tangent * off, base - tangent * off]
				if _model_left_is_plus_x_tangent(left, tangent):
					_hand_pt = [base - tangent * off, base + tangent * off]
		GLANCE:
			# turn the chest away from the wall: positive yaw about +Y turns the facing toward the character's left
			var away := -signf(lateral) if absf(lateral) > 0.05 else 0.0
			yaw = deg_to_rad(float(c["torso_yaw_max_deg"])) * (1.0 - clampf(push, 0.0, 1.0)) * away
			roll = float(c["glance_roll"]) * away * 1.0
	_apply_weights(delta, c, want_w, yaw, roll, lean)


## Turn the chest so the shoulder line runs parallel to the wall (an idle pose with the sword hand back leaves one shoulder
## 15 cm behind the other, out of the arm's reach). The animated shoulder line comes from the rig (pre-yaw), so there is no feedback loop; returns the yaw offset.
func _square_shoulders() -> float:
	var rig = _rig_ref.get_ref() if _rig_ref != null else null
	if rig == null or not is_instance_valid(rig) or not rig.has_method("shoulder_axis"):
		return 0.0
	var axis: Vector3 = rig.call("shoulder_axis")
	axis.y = 0.0
	var tangent := Vector3.UP.cross(normal)
	if axis.length() < 0.05 or tangent.length() < 0.05:
		return _brace_yaw
	axis = axis.normalized()
	tangent = tangent.normalized()
	if axis.dot(tangent) < 0.0:
		tangent = -tangent
	var goal := clampf(axis.signed_angle_to(tangent, Vector3.UP), -0.6, 0.6)
	_brace_yaw = lerpf(_brace_yaw, goal, 1.0 - exp(-10.0 * get_delta()))
	return _brace_yaw


var _dt := 0.016


func get_delta() -> float:
	return _dt


func _model_left_is_plus_x_tangent(left: Vector3, tangent: Vector3) -> bool:
	return left.dot(tangent) < 0.0


func _apply_weights(delta: float, c: Dictionary, want: Array[float], yaw: float, roll: float, lean: float) -> void:
	for i in 2:
		var rate := 1.0 / maxf(float(c["blend_in"]) if want[i] > _w[i] else float(c["blend_out"]), 0.01)
		_w[i] = move_toward(_w[i], want[i], rate * delta)
	_yaw = lerpf(_yaw, yaw, 1.0 - exp(-8.0 * delta))
	_roll = lerpf(_roll, roll, 1.0 - exp(-8.0 * delta))
	_lean = lerpf(_lean, lean, 1.0 - exp(-8.0 * delta))
	var rig = _rig_ref.get_ref() if _rig_ref != null else null
	if rig == null or not is_instance_valid(rig):
		return
	var active := absf(_yaw) > 0.0005 or _w[0] > 0.0005 or _w[1] > 0.0005
	if active or _was_active:                  # stay silent when idle so balance (GroundRealism) can use the same rig
		rig.call("set_torso_yaw_offset", _yaw, 0)
		for i in 2:
			rig.call("set_hand_brace", i, _hand_pt[i], _hand_n, _w[i])
	_was_active = active


var _rig_ref: WeakRef
var _was_active := false
var _brace_yaw := 0.0


## The player's ProceduralRig (arm IK + torso yaw); optional.
func bind_rig(rig: Node) -> void:
	_rig_ref = weakref(rig) if rig != null else null


func _impact(body: CharacterBody3D, c: Dictionary) -> void:
	_cool = float(c["impact_cooldown"])
	var animator: Variant = body.get("_animator")
	if animator != null:
		var clip := String(c["impact_clip"])
		if animator.has_method("has_clip") and animator.call("has_clip", clip):
			animator.call("play_full", clip, float(c["impact_rate"]))
	body.set("stamina", maxf(float(body.get("stamina")) - float(c["impact_stamina"]), 0.0))
	if body.has_method("_add_camera_shake"):
		body.call("_add_camera_shake", 0.12)
	body.set("_move_speed", 0.0)


## A surface the body cannot stand on: a wall, or a slope steeper than the floor limit (45 degrees, n.y 0.707). Pushing
## up such a ramp used to leave the legs jogging at its foot.
static func _is_wall(n: Vector3) -> bool:
	return n.y < 0.72 and n.y > -0.3


## Visual body scale of the player (a child is 0.58 of an adult; the capsule itself is not scaled).
static func _body_k(body: Node) -> float:
	var m: Variant = body.get("_model")
	return maxf((m as Node3D).scale.y, 0.1) if m is Node3D else 1.0
