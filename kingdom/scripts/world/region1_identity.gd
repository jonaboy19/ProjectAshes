extends RefCounted
## Settlement identity lookups (package C2): the trade, landmark, named NPC and rumour set of each of the 20 settlements
## (data/region1/world/settlements.json). Pure reads, no per-frame cost.
##   Region1Identity.of("Millbrook")           -> {name, alias, trade, tagline, landmark, npc, rumours[]}
##   Region1Identity.nearest(pos)              -> the settlement dict whose centre is nearest (within `reach`), else {}
##   Region1Identity.rumour_near(pos, rng)     -> one of the nearest town's own rumours, or "" away from every town
##   Region1Identity.display_name("Oakvale")   -> "Greenhollow"

const FILE := "res://data/region1/world/settlements.json"
const REACH := 420.0

static var _by_name: Dictionary = {}


static func _load() -> void:
	if not _by_name.is_empty():
		return
	_by_name = {"_": {}}
	if not FileAccess.file_exists(FILE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if d is Dictionary:
		for st: Dictionary in d.get("settlements", []):
			_by_name[String(st["name"])] = st


static func of(town: String) -> Dictionary:
	_load()
	return _by_name.get(town, {})


static func display_name(town: String) -> String:
	var st := of(town)
	return String(st.get("alias", "")) if String(st.get("alias", "")) != "" else town


static func all() -> Array:
	_load()
	var out: Array = []
	for k: String in _by_name:
		if k != "_":
			out.append(_by_name[k])
	return out


static func nearest(pos: Vector2, reach := REACH) -> Dictionary:
	var best := {}
	var best_d := reach
	for s in WorldGen.settlements:
		var d: float = pos.distance_to(s["pos"]) - float(s["radius"])
		if d < best_d:
			best_d = d
			best = of(String(s["name"]))
	return best


static func rumour_near(pos: Vector2, rng: RandomNumberGenerator = null) -> String:
	if pos == Vector2.INF:
		return ""
	var st := nearest(pos)
	var list: Array = st.get("rumours", [])
	if list.is_empty():
		return ""
	var i := rng.randi() % list.size() if rng != null else randi() % list.size()
	return String(list[i])
