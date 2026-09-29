extends RefCounted
## Transient, bounded action leases. This owns reservations and commit tokens,
## not domain effects; callers provide the final validation and apply callbacks.

const MAX_ACTIVE := 32
const TERMINAL_CACHE_SIZE := 64
const MAX_PAYLOAD_BYTES := 4096
const MAX_PAYLOAD_NODES := 256
const MAX_PAYLOAD_DEPTH := 6

static var _generation_serial := 0
var _generation := 0
var _serial := 0
var _active: Dictionary = {}
var _reservations: Dictionary = {}
var _terminal: Dictionary = {}
var _terminal_order: Array[String] = []


func _init() -> void:
	_rotate_generation()


func begin(actor_ref: String, action_type: String, resource_key: String, now_s: float,
		lease_s: float, payload: Dictionary = {}) -> Dictionary:
	if not is_finite(now_s) or not is_finite(lease_s) or lease_s <= 0.0:
		return {"ok": false, "token": "", "error": "invalid_lease"}
	if actor_ref.is_empty() or actor_ref.length() > 128 or action_type.is_empty() or action_type.length() > 64:
		return {"ok": false, "token": "", "error": "invalid_metadata"}
	if resource_key.is_empty() or resource_key.length() > 128:
		return {"ok": false, "token": "", "error": "resource_reserved"}
	if _reservations.has(resource_key):
		var reserved_token := String(_reservations[resource_key])
		if _active.has(reserved_token):
			var reserved_action: Dictionary = _active[reserved_token]
			if now_s >= float(reserved_action["expires_at"]) and String(reserved_action["phase"]) != "committing":
				cancel(reserved_token, "expired")
		if _reservations.has(resource_key):
			return {"ok": false, "token": "", "error": "resource_reserved"}
	if _active.size() >= MAX_ACTIVE:
		return {"ok": false, "token": "", "error": "capacity"}
	if not _serializable(payload, 0, [0]) or JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return {"ok": false, "token": "", "error": "invalid_payload"}
	_serial += 1
	var token := "%d:%d" % [_generation, _serial]
	_active[token] = {"actor_ref": actor_ref, "action_type": action_type,
		"resource_key": resource_key, "phase": "begun", "started_at": now_s,
		"expires_at": now_s + minf(lease_s, 300.0), "payload": payload.duplicate(true)}
	_reservations[resource_key] = token
	return {"ok": true, "token": token, "error": ""}


func transition(token: String, expected_phase: String, next_phase: String, now_s: float) -> bool:
	if not _active.has(token) or not is_finite(now_s):
		return false
	var action: Dictionary = _active[token]
	if now_s >= float(action["expires_at"]) or String(action["phase"]) != expected_phase:
		return false
	if expected_phase != "begun" or next_phase != "working":
		return false
	action["phase"] = next_phase
	return true


func commit(token: String, now_s: float, validate_fn: Callable, apply_fn: Callable) -> Dictionary:
	if _terminal.has(token):
		var prior: Dictionary = _terminal[token]
		var repeated := prior.duplicate(true)
		repeated["newly_committed"] = false
		return repeated
	if not _active.has(token):
		return {"ok": false, "newly_committed": false, "result": {}, "error": "unknown_token"}
	var action: Dictionary = _active[token]
	if String(action["phase"]) == "committing":
		return {"ok": false, "newly_committed": false, "result": {}, "error": "commit_in_progress"}
	if String(action["phase"]) != "working":
		return {"ok": false, "newly_committed": false, "result": {}, "error": "invalid_phase"}
	if not is_finite(now_s) or now_s >= float(action["expires_at"]):
		cancel(token, "expired")
		return {"ok": false, "newly_committed": false, "result": {}, "error": "expired"}
	if not validate_fn.is_valid() or not apply_fn.is_valid():
		return {"ok": false, "newly_committed": false, "result": {}, "error": "invalid_callbacks"}
	# Lock before either user callback to make reentrant commits/cancels harmless.
	action["phase"] = "committing"
	var validation: Variant = validate_fn.call()
	if not _active.has(token) or String(_active[token].get("phase", "")) != "committing":
		return {"ok": false, "newly_committed": false, "result": {}, "error": "invalidated"}
	if validation is bool and not validation:
		var invalid := {"ok": false, "newly_committed": false, "result": {}, "error": "validation_failed"}
		_finish(token, invalid)
		return invalid.duplicate(true)
	if not ((validation is bool and validation) or (validation is String and String(validation).is_empty())):
		var rejected := {"ok": false, "newly_committed": false, "result": {}, "error": String(validation) if validation is String else "invalid_validation_result"}
		_finish(token, rejected)
		return rejected.duplicate(true)
	var applied: Variant = apply_fn.call()
	if not _active.has(token) or String(_active[token].get("phase", "")) != "committing":
		# The apply callback may already have changed domain state; the runtime cannot roll it back.
		return {"ok": false, "newly_committed": false, "result": {}, "error": "invalidated_after_apply"}
	if (not applied is Dictionary or not _serializable(applied, 0, [0])
			or JSON.stringify(applied).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES):
		var malformed := {"ok": false, "newly_committed": false, "result": {}, "error": "invalid_apply_result"}
		_finish(token, malformed)
		return malformed.duplicate(true)
	var committed := {"ok": bool(applied.get("ok", false)), "newly_committed": bool(applied.get("ok", false)),
		"result": applied.duplicate(true), "error": "" if bool(applied.get("ok", false)) else String(applied.get("text", "apply_failed"))}
	_finish(token, committed)
	return committed.duplicate(true)


func cancel(token: String, reason: String = "cancelled") -> Dictionary:
	if _terminal.has(token):
		var prior: Dictionary = _terminal[token].duplicate(true)
		prior["newly_committed"] = false
		return prior
	if not _active.has(token):
		return {"ok": false, "newly_committed": false, "result": {}, "error": "unknown_token"}
	if String(_active[token]["phase"]) == "committing":
		return {"ok": false, "newly_committed": false, "result": {}, "error": "commit_in_progress"}
	var result := {"ok": false, "newly_committed": false, "result": {}, "error": reason}
	_finish(token, result)
	return result.duplicate(true)


func expire(now_s: float, budget: int = 8) -> int:
	if not is_finite(now_s) or budget <= 0:
		return 0
	var expired := 0
	for token: String in _active.keys():
		if expired >= mini(budget, MAX_ACTIVE):
			break
		if now_s >= float(_active[token]["expires_at"]) and String(_active[token]["phase"]) != "committing":
			var outcome := cancel(token, "expired")
			if String(outcome.get("error", "")) == "expired":
				expired += 1
	return expired


func inspect(token: String) -> Dictionary:
	if _active.has(token):
		return _active[token].duplicate(true)
	if _terminal.has(token):
		return _terminal[token].duplicate(true)
	return {}


## Called during restore; active tokens are session-local and never serialized.
func reset() -> void:
	_active.clear()
	_reservations.clear()
	_terminal.clear()
	_terminal_order.clear()
	_serial = 0
	_rotate_generation()


func _finish(token: String, result: Dictionary) -> void:
	if not _active.has(token):
		return
	var action: Dictionary = _active[token]
	var resource_key := String(action["resource_key"])
	if String(_reservations.get(resource_key, "")) == token:
		_reservations.erase(resource_key)
	_active.erase(token)
	var completed := result.duplicate(true)
	completed["action"] = {"actor_ref": String(action.get("actor_ref", "")),
		"action_type": String(action.get("action_type", "")),
		"resource_key": resource_key, "payload": action.get("payload", {}).duplicate(true)}
	_terminal[token] = completed
	_terminal_order.append(token)
	while _terminal_order.size() > TERMINAL_CACHE_SIZE:
		_terminal.erase(_terminal_order.pop_front())


func _rotate_generation() -> void:
	_generation_serial += 1
	_generation = _generation_serial


func _serializable(value: Variant, depth: int, nodes: Array) -> bool:
	nodes[0] += 1
	if depth > MAX_PAYLOAD_DEPTH or nodes[0] > MAX_PAYLOAD_NODES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for child: Variant in value:
				if not _serializable(child, depth + 1, nodes):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _serializable(value[key], depth + 1, nodes):
					return false
			return true
		_:
			return false
