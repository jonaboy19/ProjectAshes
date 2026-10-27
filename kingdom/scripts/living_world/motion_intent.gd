class_name MotionIntent
extends RefCounted
## The one result every body adapter reads (docs/plans/NPC_MOTION_RULES.md section 2). Plain Dictionary so it costs
## nothing to pass around; this file only owns the SHAPE: key names, enums, reset-in-place, and the per-body hysteresis
## state. No node access, no allocation after the first reset().
##
##   steer    {offset: Vector3, speed_mul: float, stop: bool}   desired-velocity offset + speed multiplier, or stop
##   look     {target: Vector3|null, priority: int, hold_s: float}
##   gait     {clip: String, rate: float}                       base locomotion clip (FAR resolves it to a VAT clip)
##   upper    String                                            composite upper-layer clip ("" = none)
##   oneshot  {clip: String, channel: int}                      channel = Channel value, -1 when none
##   lean     float                                             model-root roll, radians
##   ik       Array of {limb, target, weight}                   NEAR only, honoured within the IK budget
##   reaction int                                               ReactionRequest.Kind (0 = none)
##   winners  Array[String] (size 4)                            rule id that owns each Channel ("" = nobody)
##   tier     int

## Same order as ReactionRequest.Layer, so reaction layers map straight onto channels.
enum Channel { HEAD, UPPER, LOCO, BODY }
## Lowest tier a rule may run at is stored as one of these. OUT produces an empty intent.
enum Tier { NEAR, MID, FAR, OUT }

const CHANNEL_NAMES := ["head", "upper", "loco", "body"]
const TIER_NAMES := ["near", "mid", "far", "out"]
const KEYS := ["steer", "look", "gait", "upper", "oneshot", "lean", "ik", "reaction"]


static func make() -> Dictionary:
	var d := {
		"steer": {"offset": Vector3.ZERO, "speed_mul": 1.0, "stop": false},
		"look": {"target": null, "priority": 0, "hold_s": 0.0},
		"gait": {"clip": "", "rate": 1.0},
		"upper": "",
		"oneshot": {"clip": "", "channel": -1},
		"lean": 0.0,
		"ik": [],
		"reaction": 0,
		"winners": ["", "", "", ""],
		"tier": 0,
	}
	return d


## Back to the no-op intent without allocating (nested dictionaries are reused).
static func reset(d: Dictionary) -> void:
	if d.is_empty():
		d.merge(make())
		return
	var s: Dictionary = d["steer"]
	s["offset"] = Vector3.ZERO
	s["speed_mul"] = 1.0
	s["stop"] = false
	var l: Dictionary = d["look"]
	l["target"] = null
	l["priority"] = 0
	l["hold_s"] = 0.0
	var g: Dictionary = d["gait"]
	g["clip"] = ""
	g["rate"] = 1.0
	d["upper"] = ""
	var o: Dictionary = d["oneshot"]
	o["clip"] = ""
	o["channel"] = -1
	d["lean"] = 0.0
	(d["ik"] as Array).clear()
	d["reaction"] = 0
	var w: Array = d["winners"]
	for i in 4:
		w[i] = ""
	d["tier"] = 0


## Copy a rule payload (any subset of KEYS; nested dictionaries may be partial) onto an intent.
static func apply(d: Dictionary, payload: Dictionary) -> void:
	for k: String in payload:
		match k:
			"steer", "look", "gait", "oneshot":
				var dst: Dictionary = d[k]
				var src: Dictionary = payload[k]
				for f: String in src:
					dst[f] = src[f]
			"ik":
				var a: Array = d["ik"]
				a.clear()
				a.append_array(payload[k])
			"upper", "lean", "reaction":
				d[k] = payload[k]


## Per-body hysteresis memory. Own one per body, put it in ctx["state"]; evaluate() mutates it in place.
static func new_state() -> Dictionary:
	return {
		"rule": PackedInt32Array([-1, -1, -1, -1]),
		"prio": PackedInt32Array([0, 0, 0, 0]),
		"until": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		"payload": [null, null, null, null],
	}
