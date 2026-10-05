extends RefCounted
## Sparse, bounded ties between persistent non-player people.
##
## This is distinct from Relationships, which owns how NPCs regard the player.
## Endpoints are namespaced strings so future identity domains can coexist;
## current embodied villagers use `worldsim:<seed>:<person-index>`.

const VERSION := 1
const MAX_EDGES := 2048
const MAX_ID_LENGTH := 96
const MIN_REPEAT_DAYS := 0.25
## Familiarity loses at most half its value after 200 days without a valid chat.
const DORMANCY_FADE_PER_DAY := 0.0025
const DORMANCY_FADE_CAP := 0.5

## Canonical pair key -> {a, b, first_day, last_day, conversations, affinity}.
var edges: Dictionary = {}


static func worldsim_person(seed: int, person: int) -> String:
	if person < 0:
		return ""
	return "worldsim:%d:%d" % [seed, person]


static func _valid_id(value: String) -> bool:
	return not value.strip_edges().is_empty() and value.length() <= MAX_ID_LENGTH and not value.contains("|")


static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## A successful, face-to-face conversation adds familiarity. Repeated callbacks
## are coalesced; a pair can gain at most one conversation per six game hours.
func record_conversation(a: String, b: String, day: float) -> bool:
	if not _valid_id(a) or not _valid_id(b) or a == b or not is_finite(day) or day < 0.0:
		return false
	var key := _pair_key(a, b)
	if edges.has(key):
		var edge: Dictionary = edges[key]
		if day < float(edge["last_day"]):
			return false
		if day - float(edge["last_day"]) < MIN_REPEAT_DAYS:
			return true
		var elapsed_days := day - float(edge["last_day"])
		var fade := minf(DORMANCY_FADE_CAP, elapsed_days * DORMANCY_FADE_PER_DAY)
		edge["affinity"] = float(edge["affinity"]) * (1.0 - fade)
		edge["last_day"] = day
		edge["conversations"] = mini(int(edge["conversations"]) + 1, 999)
		edge["affinity"] = minf(60.0, float(edge["affinity"]) + 2.0)
		edges[key] = edge
		return true
	if edges.size() >= MAX_EDGES:
		_evict_oldest()
	var left := a if a < b else b
	var right := b if a < b else a
	edges[key] = {"a": left, "b": right, "first_day": day, "last_day": day,
		"conversations": 1, "affinity": 2.0}
	return true


## Neutral/default ties are absent. Returned values are copies.
func link(a: String, b: String) -> Dictionary:
	if not _valid_id(a) or not _valid_id(b) or a == b:
		return {}
	return (edges.get(_pair_key(a, b), {}) as Dictionary).duplicate(true)


func affinity(a: String, b: String, now_day := -1.0) -> float:
	var edge := link(a, b)
	var value := float(edge.get("affinity", 0.0))
	# Existing callers without a clock keep receiving the saved raw score.
	if edge.is_empty() or now_day < 0.0 or not is_finite(now_day):
		return value
	var age := maxf(0.0, now_day - float(edge["last_day"]))
	var fade := minf(DORMANCY_FADE_CAP, age * DORMANCY_FADE_PER_DAY)
	return value * (1.0 - fade)


## A person died: every tie they had goes. Returns how many edges were dropped.
func forget(id: String) -> int:
	var drop: Array = []
	for key: String in edges:
		var e: Dictionary = edges[key]
		if String(e["a"]) == id or String(e["b"]) == id:
			drop.append(key)
	for key: String in drop:
		edges.erase(key)
	return drop.size()


func _evict_oldest() -> void:
	var oldest_key := ""
	var oldest_day := INF
	for key: String in edges:
		var edge: Dictionary = edges[key]
		# Prefer dropping weak, stale incidental ties over repeatedly renewed ones.
		var score := float(edge["last_day"]) + float(edge["affinity"]) * 0.02
		if score < oldest_day:
			oldest_day = score
			oldest_key = key
	if oldest_key != "":
		edges.erase(oldest_key)


func serialize() -> Dictionary:
	var records: Array = []
	var keys: Array = edges.keys()
	keys.sort()
	for key: String in keys:
		records.append((edges[key] as Dictionary).duplicate(true))
	return {"version": VERSION, "edges": records}


## Invalid optional social data is rejected as a whole; older saves remain empty.
func deserialize(data: Variant) -> bool:
	var restored: Dictionary = {}
	if not data is Dictionary or int(data.get("version", -1)) != VERSION:
		edges = restored
		return false
	var raw_edges: Variant = data.get("edges", [])
	if not raw_edges is Array or raw_edges.size() > MAX_EDGES:
		edges = restored
		return false
	for raw: Variant in raw_edges:
		if not raw is Dictionary:
			edges = {}
			return false
		var row: Dictionary = raw
		var a: Variant = row.get("a", null)
		var b: Variant = row.get("b", null)
		var first: Variant = row.get("first_day", null)
		var last: Variant = row.get("last_day", null)
		var conversations: Variant = row.get("conversations", null)
		var affinity_value: Variant = row.get("affinity", null)
		if not a is String or not b is String or not _valid_id(String(a)) or not _valid_id(String(b)) \
		or String(a) == String(b) or not (first is float or first is int) or not (last is float or last is int) \
		or not is_finite(float(first)) or not is_finite(float(last)) or float(first) < 0.0 \
		or float(last) < float(first) or not (conversations is int or conversations is float) \
		or not is_finite(float(conversations)) or float(conversations) != floorf(float(conversations)) \
		or float(conversations) < 1.0 or float(conversations) > 999.0 \
		or not (affinity_value is int or affinity_value is float) or not is_finite(float(affinity_value)) \
		or float(affinity_value) < 0.0 or float(affinity_value) > 60.0:
			edges = {}
			return false
		var left := String(a) if String(a) < String(b) else String(b)
		var right := String(b) if String(a) < String(b) else String(a)
		var key := _pair_key(left, right)
		if restored.has(key):
			edges = {}
			return false
		restored[key] = {"a": left, "b": right, "first_day": float(first), "last_day": float(last),
			"conversations": int(conversations), "affinity": float(affinity_value)}
	edges = restored
	return true
