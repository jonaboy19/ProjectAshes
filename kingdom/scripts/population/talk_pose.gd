extends RefCounted
## TalkPose: the villager side of an in-world conversation (docs/design/FOUNDATION_PLAN.md F4).
## While `active` the villager stops walking / working, turns its body toward the player and looks at them
## with its existing head look; its schedule (route, activity, smart-object session) is left untouched so it
## picks up exactly where it was when the talk ends. Pure state + maths so it is unit tested without a scene.
##
## villager.gd owns one instance (`_talk`) and consults it in _steer, the activity pick and the head look.

## Body turn rate while facing the player (rad/s): a touch quicker than a walking turn so the NPC is
## facing you within a second or so from any angle.
const TURN_RATE := 5.0
## Below this angle error (rad) the body counts as facing the player.
const FACING_EPS := 0.08

var active := false
var started_ms := 0
var turns := 0           # how many times this villager has been talked to (diagnostics / tests)


func begin(now_ms: int) -> void:
	active = true
	started_ms = now_ms
	turns += 1


func end() -> void:
	active = false


## New body heading after turning toward `target` (planar x/z) from `here`. Same convention as villager.gd:
## heading = atan2(dx, dz). Never overshoots.
static func turn_heading(heading: float, here: Vector2, target: Vector2, delta: float, rate := TURN_RATE) -> float:
	var to := target - here
	if to.length_squared() < 0.0001:
		return heading
	var diff := wrapf(atan2(to.x, to.y) - heading, -PI, PI)
	return wrapf(heading + clampf(diff, -rate * delta, rate * delta), -PI, PI)


static func facing_error(heading: float, here: Vector2, target: Vector2) -> float:
	var to := target - here
	if to.length_squared() < 0.0001:
		return 0.0
	return absf(wrapf(atan2(to.x, to.y) - heading, -PI, PI))
