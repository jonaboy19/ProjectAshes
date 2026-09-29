extends RefCounted
## Small, saveable journal of meaningful world actions. This stores facts for
## later systems to query; it does not own or replace the systems that produce
## those facts.

const SCHEMA_VERSION := 2
const MAX_EVENTS := 256
const MAX_PAYLOAD_BYTES := 8192
const MAX_VALUE_DEPTH := 8
const MAX_PAYLOAD_NODES := 512
const MAX_SAFE_INTEGER := 9007199254740991

var _events: Array[Dictionary] = []
var _next_id := 1
var _evicted_count := 0


func publish(event_type: String, actor_ref: String, target_ref: String, game_hour: float,
		payload: Dictionary, cause_id: int = 0) -> Dictionary:
	var kind := event_type.strip_edges()
	if kind.is_empty() or kind.length() > 64:
		return {"ok": false, "id": 0, "error": "invalid_type"}
	if actor_ref.length() > 128 or target_ref.length() > 128 or not is_finite(game_hour) or cause_id < 0 or cause_id >= _next_id:
		return {"ok": false, "id": 0, "error": "invalid_metadata"}
	if _next_id >= MAX_SAFE_INTEGER:
		return {"ok": false, "id": 0, "error": "id_exhausted"}
	if not _value_is_serializable(payload, 0, [0]) or JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return {"ok": false, "id": 0, "error": "invalid_payload"}
	var event := {
		"id": _next_id, "type": kind, "actor_ref": actor_ref, "target_ref": target_ref,
		"game_hour": game_hour, "cause_id": cause_id, "payload": payload.duplicate(true),
	}
	_events.append(event)
	var published_id := _next_id
	_next_id += 1
	if _events.size() > MAX_EVENTS:
		_events.pop_front()
		_evicted_count += 1
	return {"ok": true, "id": published_id, "error": ""}


func since(after_id: int, limit: int = 32, type_filter: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0:
		return result
	var max_results := mini(limit, MAX_EVENTS)
	for event: Dictionary in _events:
		if int(event["id"]) <= after_id:
			continue
		if not type_filter.is_empty() and String(event["type"]) != type_filter:
			continue
		result.append(event.duplicate(true))
		if result.size() >= max_results:
			break
	return result


func serialize() -> Dictionary:
	return {"version": SCHEMA_VERSION, "next_id": _next_id, "evicted_count": _evicted_count,
		"events": _events.duplicate(true)}


## The retention window lets cursor consumers notice that older facts expired.
func window_info(after_id: int = -1) -> Dictionary:
	var oldest_id := int(_events[0]["id"]) if not _events.is_empty() else _next_id
	return {"oldest_id": oldest_id, "next_id": _next_id, "evicted_count": _evicted_count,
		"cursor_expired": _evicted_count > 0 and after_id < oldest_id - 1}


## Validate into temporary state first so a bad save never partially replaces the journal.
func deserialize(data: Dictionary) -> bool:
	var version_value: Variant = data.get("version", -1)
	var version_number := _exact_integer(version_value)
	if version_number < 0 or version_number != SCHEMA_VERSION:
		return false
	var raw_events: Variant = data.get("events")
	var raw_next_id: Variant = data.get("next_id")
	var next_id_number := _exact_integer(raw_next_id)
	var raw_evicted: Variant = data.get("evicted_count", 0)
	var evicted_number := _exact_integer(raw_evicted)
	if not raw_events is Array or next_id_number < 1 or next_id_number > MAX_SAFE_INTEGER or evicted_number < 0:
		return false
	if raw_events.size() > MAX_EVENTS:
		return false
	var parsed: Array[Dictionary] = []
	var previous_id := 0
	for raw: Variant in raw_events:
		if not raw is Dictionary:
			return false
		var event: Dictionary = raw
		var id: Variant = event.get("id")
		var kind: Variant = event.get("type")
		var actor: Variant = event.get("actor_ref")
		var target: Variant = event.get("target_ref")
		var hour: Variant = event.get("game_hour")
		var cause: Variant = event.get("cause_id")
		var payload: Variant = event.get("payload")
		var id_number := _exact_integer(id)
		var cause_number := _exact_integer(cause)
		if id_number <= previous_id or (previous_id > 0 and id_number != previous_id + 1) or id_number > MAX_SAFE_INTEGER or not kind is String or String(kind).strip_edges().is_empty() or String(kind).length() > 64:
			return false
		if not actor is String or not target is String or String(actor).length() > 128 or String(target).length() > 128:
			return false
		if not (hour is float or hour is int) or not is_finite(float(hour)) or cause_number < 0 or cause_number >= id_number:
			return false
		if not payload is Dictionary or not _value_is_serializable(payload, 0, [0]):
			return false
		if JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
			return false
		previous_id = id_number
		parsed.append({"id": id_number, "type": String(kind), "actor_ref": String(actor),
			"target_ref": String(target), "game_hour": float(hour), "cause_id": cause_number,
			"payload": payload.duplicate(true)})
	if (not parsed.is_empty() and next_id_number != previous_id + 1) or next_id_number <= previous_id or evicted_number != next_id_number - 1 - parsed.size():
		return false
	_events = parsed
	_next_id = next_id_number
	_evicted_count = evicted_number
	return true


func _exact_integer(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > float(MAX_SAFE_INTEGER) or floor(number) != number:
		return -1
	return int(number)


func _value_is_serializable(value: Variant, depth: int, node_count: Array) -> bool:
	node_count[0] += 1
	if depth > MAX_VALUE_DEPTH or node_count[0] > MAX_PAYLOAD_NODES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_INT:
			return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
		TYPE_STRING:
			return value.length() <= MAX_PAYLOAD_BYTES
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for child: Variant in value:
				if not _value_is_serializable(child, depth + 1, node_count):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _value_is_serializable(value[key], depth + 1, node_count):
					return false
			return true
		_:
			return false
