extends RefCounted
## The wilds around Thornfield (F9): data access, world placement and the safety/danger field. Everything positional
## lives in data/region1/world/thornfield_wilds.json as [x, z] offsets from the Thornfield settlement centre. The
## Soldier career's post position is read from data/careers/soldier_career.json (SoldierCareer.resolve_post), so the
## outpost always matches it. No class_name; preload and call statics.
##
## The gradient, in play: Thornfield (safe) -> the road and its runestones (safe by day) -> the verge -> forest and
## off-road (danger climbs, more wolves at night, bandit ambushes). `danger(pos, hour)` is the one number; `zone(pos)`
## and `level_name(danger)` are its words (the hub says them as you cross a line).

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const Career := preload("res://scripts/sim/soldier_career.gd")
const PATH := "res://data/region1/world/thornfield_wilds.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data


static func quartermaster() -> Dictionary:
	return data()["quartermaster"]


## The Thornfield settlement centre (Vector2.INF while the world has no Thornfield).
static func anchor() -> Vector2:
	var s := Sites.settlement()
	return s["pos"] if not s.is_empty() else Vector2.INF


## World XZ of a data offset.
static func at(offset: Array) -> Vector2:
	var a := anchor()
	return a + Vector2(float(offset[0]), float(offset[1])) if a != Vector2.INF else Vector2.INF


static func ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y) + lift, p.y)


## A hidden place's definition by id ({} when unknown).
static func hidden_def(id: String) -> Dictionary:
	for d: Dictionary in data()["hidden"]:
		if String(d["id"]) == id:
			return d
	return {}


# --- the Soldier career's post -----------------------------------------------------------------------

## {id, name, kind, pos, radius, ...} from soldier_career.json: the outpost's place and radius.
static func post() -> Dictionary:
	return Career.resolve_post(WorldGen.settlements)


## The road's direction at `p` (unit Vector2), found by walking the road distance field: the heading along which the
## distance to the road stays smallest. Falls back to east.
static func road_heading(p: Vector2) -> Vector2:
	var best := Vector2.RIGHT
	var best_d := 1.0e9
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector2(cos(a), sin(a))
		var d := WorldGen.road_distance(p.x + dir.x * 14.0, p.y + dir.y * 14.0) + WorldGen.road_distance(p.x - dir.x * 14.0, p.y - dir.y * 14.0)
		if d < best_d - 0.001:
			best_d = d
			best = dir
	return best


# --- the safety / danger field -----------------------------------------------------------------------

## 0 (nothing protects this spot) .. 1 (inside the town, on the maintained road, under a runestone's ward).
static func safety(p: Vector2) -> float:
	var s: Dictionary = data()["safety"]
	var town := Sites.settlement()
	if not town.is_empty() and p.distance_to(town["pos"]) <= float(town["radius"]):
		return 1.0
	var rd := WorldGen.road_distance(p.x, p.y)
	var road_safe := 1.0 - smoothstep(float(s["road_safe"]), float(s["road_wild"]), rd)
	var ward := 0.0
	if Frontier != null and Frontier.runestones != null:
		ward = clampf(float(Frontier.runestones.coverage(p)), 0.0, 1.0)
	var safe := maxf(road_safe, ward)
	safe -= float(s["forest_penalty"]) * WorldGen.forest_density(p.x, p.y)
	return clampf(safe, 0.0, 1.0)


## Danger at a point and hour (0..24; -1 = the game clock). Road by day ~0.15; off-road by day ~1; off-road at night up to 3.
static func danger(p: Vector2, hour := -1.0) -> float:
	var s: Dictionary = data()["safety"]
	var h := hour if hour >= 0.0 else float(WorldSim.time_of_day)
	var base := float(s["base"])
	var wild := 1.0 - safety(p)
	return (base + (1.0 - base) * wild) * Frontier.danger_mult(h)


static func level_name(d: float) -> String:
	for row: Array in data()["safety"]["levels"]:
		if d <= float(row[0]):
			return String(row[1])
	return "deadly"


## "town" | "road" | "verge" | "wilds": where the player stands on the gradient.
static func zone(p: Vector2) -> String:
	var town := Sites.settlement()
	if not town.is_empty() and p.distance_to(town["pos"]) <= float(town["radius"]):
		return "town"
	var sf := safety(p)
	if sf >= 0.8:
		return "road"
	if sf >= 0.35:
		return "verge"
	return "wilds"


## The line said when the zone changes (empty when there is nothing to say).
static func crossing_line(from_zone: String, to_zone: String) -> String:
	if from_zone == to_zone or from_zone == "":
		return ""
	match to_zone:
		"town":
			return "Thornfield's lamps and hedges: you are safe here."
		"road":
			return "The road's runestones hum faintly. This stretch is protected." if from_zone != "town" else "You walk the stoned road beyond the gate."
		"verge":
			return "You drift off the road. The stones' protection thins."
		"wilds":
			return "Beyond the stones now. Wolves and cutthroats hunt where the road cannot reach."
	return ""


# --- what the danger brings ---------------------------------------------------------------------------

## Wolves in a night/off-road pack at this danger: 0 below the threshold, 2 above it, 3 when it is deep.
static func wolf_pack_size(d: float) -> int:
	var w: Dictionary = data()["safety"]["wolves"]
	if d < float(w["min_danger"]):
		return 0
	var span: Array = w["count"]
	return int(span[1]) if d >= float(w["min_danger"]) + 1.0 else int(span[0])


## Bandits in an ambush at this danger (0 below the threshold).
static func ambush_size(d: float) -> int:
	var a: Dictionary = data()["safety"]["ambush"]
	if d < float(a["min_danger"]):
		return 0
	var span: Array = a["count"]
	return int(span[1]) if d >= float(a["min_danger"]) + 0.9 else int(span[0])
