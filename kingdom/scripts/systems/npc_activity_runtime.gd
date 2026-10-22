extends RefCounted
## Domain adapter for brief embodied NPC activities. ActionRuntime remains the
## single lease authority; this class only names well slots and validates phases.

const SLOT_COUNT := 2
const MAX_LEASE_SECONDS := 180.0

var _actions: Variant


func _init(action_runtime: Variant) -> void:
	_actions = action_runtime


func reserve_water_source(person: int, settlement_id: int, source_ref: String, slot: int, now_s: float) -> Dictionary:
	if (_actions == null or person < 0 or person >= WorldSim.population()
			or settlement_id < 0 or settlement_id >= WorldGen.settlements.size()
			or slot < 0 or slot >= SLOT_COUNT
			or not ["well", "plaza_break"].has(source_ref)):
		return {"ok": false, "token": "", "error": "invalid_water_slot"}
	var world_ref := str(WorldSim.SEED)
	var actor_ref := "npc:%s:row:%d" % [world_ref, person]
	var actor_key := "actor:%s" % actor_ref
	var slot_key := "water:%s:settlement:%d:%s:slot:%d" % [world_ref, settlement_id, source_ref, slot]
	var payload := {"settlement_id": settlement_id, "source_ref": source_ref, "slot": slot}
	return _actions.begin_resources(actor_ref, "water_fetch", [actor_key, slot_key],
		now_s, MAX_LEASE_SECONDS, payload)


func phase(token: String, now_s: float) -> String:
	if _actions == null or token.is_empty() or not is_finite(now_s):
		return ""
	var state: Dictionary = _actions.inspect(token)
	if not state.has("phase"):
		return ""
	if now_s >= float(state.get("expires_at", 0.0)):
		_actions.cancel(token, "expired")
		return ""
	return String(state.get("phase", ""))


func start_work(token: String, now_s: float) -> bool:
	return _actions != null and _actions.transition(token, "begun", "working", now_s)


func release(token: String, reason := "activity_interrupted") -> void:
	if _actions != null and not token.is_empty():
		_actions.cancel(token, reason)
