class_name MotionIntent
extends RefCounted
## The output contract of MotionRules.evaluate (docs/plans/NPC_MOTION_RULES.md section 2). Pure data, no nodes.
## An intent is a flat Dictionary with a FIXED key set, so a body can keep one and have it refilled in place every think
## (MotionRules.evaluate_into) with no allocation. Read it with plain keys:
##
##   steer_x, steer_z   desired velocity offset (m/s, world XZ); speed_mul: multiplier on the route speed; stop: true = hold still
##   gait_clip, gait_rate   base locomotion clip and playback rate (never empty at NEAR/MID/FAR; "" only at OUT)
##   upper_clip         composite clip on the upper body ("" = none)
##   oneshot_clip, oneshot_channel   one-off clip and the channel that owns it (Channel.BODY or Channel.UPPER; -1 = none)
##   lean               model-root roll in radians (no skeleton update)
##   ik                 Array of {limb, target, weight}, only filled at NEAR (the caller still checks the ContactIK budget)
##   look_prio, look_x/y/z, look_hold, look_limit   head look request (look_prio 0 = none), world target, hold seconds, head-turn limit in degrees
##   reaction           ReactionRequest.Kind (0 = none)
##   tier, body_rule, loco_rule, upper_rule, head_rule   diagnostics: input tier and the rule id that won each channel ("" = none/suppressed)
##
## Keys prefixed b_ / u_ are channel-internal (a BODY rule's own steer, an UPPER rule's oneshot); MotionRules folds them into the
## public keys, adapters ignore them.

## Same numeric values as ReactionRequest.Layer, so a higher number is a higher precedence: BODY > LOCO > UPPER > HEAD.
enum Channel { HEAD, UPPER, LOCO, BODY }
const CHANNEL_NAMES := ["HEAD", "UPPER", "LOCO", "BODY"]
const NO_IK: Array = []
const NO_CHANNEL := -1


static func make() -> Dictionary:
	var d := {}
	d["steer_x"] = 0.0
	d["steer_z"] = 0.0
	d["speed_mul"] = 1.0
	d["stop"] = false
	d["gait_clip"] = ""
	d["gait_rate"] = 1.0
	d["upper_clip"] = ""
	d["oneshot_clip"] = ""
	d["oneshot_channel"] = NO_CHANNEL
	d["lean"] = 0.0
	d["ik"] = []
	d["look_prio"] = 0
	d["look_x"] = 0.0
	d["look_y"] = 0.0
	d["look_z"] = 0.0
	d["look_hold"] = 0.0
	d["look_limit"] = 0.0
	d["reaction"] = 0
	d["tier"] = 0
	d["body_rule"] = ""
	d["loco_rule"] = ""
	d["upper_rule"] = ""
	d["head_rule"] = ""
	d["b_steer_x"] = 0.0
	d["b_steer_z"] = 0.0
	d["b_speed_mul"] = 1.0
	d["b_stop"] = false
	d["u_oneshot"] = ""
	return d


## Refills every key with its default, in place (the `ik` array is cleared, keeping its capacity). One flat run of stores:
## this is on the per-body per-think path.
static func reset(d: Dictionary) -> void:
	d["steer_x"] = 0.0
	d["steer_z"] = 0.0
	d["speed_mul"] = 1.0
	d["stop"] = false
	d["gait_clip"] = ""
	d["gait_rate"] = 1.0
	d["upper_clip"] = ""
	d["oneshot_clip"] = ""
	d["oneshot_channel"] = NO_CHANNEL
	d["lean"] = 0.0
	(d["ik"] as Array).clear()
	d["look_prio"] = 0
	d["look_x"] = 0.0
	d["look_y"] = 0.0
	d["look_z"] = 0.0
	d["look_hold"] = 0.0
	d["look_limit"] = 0.0
	d["reaction"] = 0
	d["tier"] = 0
	d["body_rule"] = ""
	d["loco_rule"] = ""
	d["upper_rule"] = ""
	d["head_rule"] = ""
	d["b_steer_x"] = 0.0
	d["b_steer_z"] = 0.0
	d["b_speed_mul"] = 1.0
	d["b_stop"] = false
	d["u_oneshot"] = ""


## Candidate scratch of one rule: same keys, but `ik` points at a shared empty constant (rules assign their own constant array).
static func reset_cand(d: Dictionary) -> void:
	for ch in 4:
		clear_channel(d, ch)
	d["ik"] = NO_IK


## clear_channel for an intent or latch that owns its `ik` array (cleared in place, capacity kept).
static func clear_channel_out(d: Dictionary, ch: int) -> void:
	clear_channel(d, ch)
	if ch == Channel.UPPER:
		(d["ik"] as Array).clear()


## Defaults for the keys one channel owns (except `ik`, which is owned differently by intents and rule candidates).
static func clear_channel(d: Dictionary, ch: int) -> void:
	match ch:
		Channel.BODY:
			d["reaction"] = 0
			d["oneshot_clip"] = ""
			d["b_steer_x"] = 0.0
			d["b_steer_z"] = 0.0
			d["b_speed_mul"] = 1.0
			d["b_stop"] = false
		Channel.LOCO:
			d["steer_x"] = 0.0
			d["steer_z"] = 0.0
			d["speed_mul"] = 1.0
			d["stop"] = false
			d["gait_clip"] = ""
			d["gait_rate"] = 1.0
			d["lean"] = 0.0
		Channel.UPPER:
			d["upper_clip"] = ""
			d["u_oneshot"] = ""
		Channel.HEAD:
			d["look_prio"] = 0
			d["look_x"] = 0.0
			d["look_y"] = 0.0
			d["look_z"] = 0.0
			d["look_hold"] = 0.0


## Copies the keys one channel owns from `src` (a rule candidate, a latch, ...) into `dst`.
static func copy_channel(dst: Dictionary, src: Dictionary, ch: int) -> void:
	match ch:
		Channel.BODY:
			dst["reaction"] = src["reaction"]
			dst["oneshot_clip"] = src["oneshot_clip"]
			dst["b_steer_x"] = src["b_steer_x"]
			dst["b_steer_z"] = src["b_steer_z"]
			dst["b_speed_mul"] = src["b_speed_mul"]
			dst["b_stop"] = src["b_stop"]
		Channel.LOCO:
			dst["steer_x"] = src["steer_x"]
			dst["steer_z"] = src["steer_z"]
			dst["speed_mul"] = src["speed_mul"]
			dst["stop"] = src["stop"]
			dst["gait_clip"] = src["gait_clip"]
			dst["gait_rate"] = src["gait_rate"]
			dst["lean"] = src["lean"]
		Channel.UPPER:
			dst["upper_clip"] = src["upper_clip"]
			dst["u_oneshot"] = src["u_oneshot"]
			# Rule candidates hold a reference to the rule's own constant list; the destination owns a mutable copy.
			var d_ik: Array = dst["ik"]
			d_ik.clear()
			var s_ik: Array = src["ik"]
			for e in s_ik:
				d_ik.append(e)
		Channel.HEAD:
			dst["look_prio"] = src["look_prio"]
			dst["look_x"] = src["look_x"]
			dst["look_y"] = src["look_y"]
			dst["look_z"] = src["look_z"]
			dst["look_hold"] = src["look_hold"]


## True when the intent asks for nothing beyond the base gait: no steer change, no overlay, no look, no reaction.
static func is_noop(d: Dictionary) -> bool:
	return (d["steer_x"] == 0.0 and d["steer_z"] == 0.0 and d["speed_mul"] == 1.0 and not d["stop"]
		and d["upper_clip"] == "" and d["oneshot_clip"] == "" and d["lean"] == 0.0 and (d["ik"] as Array).is_empty()
		and d["look_prio"] == 0 and d["reaction"] == 0)
