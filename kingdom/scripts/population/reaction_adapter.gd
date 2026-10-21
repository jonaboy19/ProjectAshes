extends RefCounted
## MW-41 stub adapter: the only place that turns an abstract reaction into "what the body should do".
## Codex replaces `describe()` clip hints with real AnimationTree layers; AI code never changes. The stub just forwards
## to a Callable sink (villager.gd / CharacterAnimator / LookAt) so nothing breaks while no clips exist.

const RR := preload("res://scripts/population/reaction_request.gd")

## clip_hint: free-text key for the animation layer; look: head/eyes follow the request target; additive: overlay on the
## current activity; displace: short root displacement then the activity resumes; speak: bark expected.
const INFO := {
	RR.Kind.GLANCE: {"clip_hint": "react_glance", "look": true, "additive": true},
	RR.Kind.LOOK_AWAY: {"clip_hint": "react_look_away", "look": false, "additive": true},
	RR.Kind.STEP_BACK: {"clip_hint": "react_step_back", "look": true, "displace": true},
	RR.Kind.STEP_ASIDE: {"clip_hint": "react_step_aside", "look": true, "displace": true},
	RR.Kind.BOW: {"clip_hint": "react_bow", "look": true, "additive": true},
	RR.Kind.FLINCH: {"clip_hint": "react_flinch", "look": false, "additive": true},
	RR.Kind.CONFRONT: {"clip_hint": "react_confront", "look": true, "speak": true},
	RR.Kind.WAVE: {"clip_hint": "react_wave", "look": true, "additive": true},
	RR.Kind.WARN: {"clip_hint": "react_warn", "look": true, "speak": true},
	RR.Kind.CALL_GUARD: {"clip_hint": "react_call_guard", "look": true, "speak": true},
	RR.Kind.FLEE: {"clip_hint": "react_flee", "look": false},
	RR.Kind.RETURN_TO_WORK: {"clip_hint": "react_resume", "look": false},
	# AR-5 aura kinds: no clips yet (Antigravity). `fallback` is the pre-aura kind a body plays until a real mapping exists.
	RR.Kind.KNEEL: {"clip_hint": "react_kneel", "look": false, "fallback": RR.Kind.BOW},
	RR.Kind.FAINT: {"clip_hint": "react_faint", "look": false, "fallback": RR.Kind.FLINCH},
	RR.Kind.HIDE: {"clip_hint": "react_hide", "look": false, "fallback": RR.Kind.STEP_BACK},
	RR.Kind.FLEE_WITH_CHILD: {"clip_hint": "react_flee_with_child", "look": false, "carry": true, "fallback": RR.Kind.FLEE},
}
var delivered := 0


## Dictionary a clip mapper reads: layer, priority, keeps_activity and the hints above.
static func describe(kind: int) -> Dictionary:
	var d: Dictionary = (INFO.get(kind, {}) as Dictionary).duplicate()
	d["kind"] = kind
	d["name"] = RR.name_of(kind)
	d["fallback_kind"] = RR.fallback_of(kind)
	d["layer"] = RR.LAYER_OF[kind] if kind > 0 and kind < RR.NAMES.size() else 0
	d["priority"] = RR.PRIORITY[kind] if kind > 0 and kind < RR.NAMES.size() else 0
	d["keeps_activity"] = RR.KEEPS_ACTIVITY[kind] if kind > 0 and kind < RR.NAMES.size() else true
	return d


## Drains the slot's pending requests into `sink(slot, kind, target_id, describe_dict)`. Returns how many were delivered.
func consume(queue: RefCounted, slot: int, sink: Callable) -> int:
	var n := 0
	while true:
		var r: Array = queue.pop(slot)
		if r.is_empty():
			break
		n += 1
		if sink.is_valid():
			sink.call(slot, r[0], r[1], describe(r[0]))
	delivered += n
	return n


## Target id the head/eyes should follow right now, or -1 (feeds LookAtModifier3D / villager head look).
static func look_target(queue: RefCounted, slot: int, now: int) -> int:
	for layer in [RR.Layer.BODY, RR.Layer.LOCO, RR.Layer.UPPER, RR.Layer.HEAD]:
		var k: int = queue.current(slot, layer, now)
		if k != 0 and INFO.get(k, {}).get("look", false):
			return queue.current_target(slot, layer, now)
	return -1
