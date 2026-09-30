class_name RAThreatMap
extends RefCounted
## Explainable danger. Threat at a point = wilderness + monster pressure +
## active event modifiers - runestone protection - patrol presence, clamped to
## 0..100. Every term is reported, so the UI (and rumours) can say *why* a road
## has become dangerous instead of showing a level number.

## Active modifiers: {id, label, pos: Vector2, radius, value, expires_day}
var modifiers: Array[Dictionary] = []
var runestones: RARunestoneNetwork
var ecology: RAMonsterEcology
## Callable(Vector2) -> float in 0..1: how patrolled a point is.
var patrols: Callable = func(_p: Vector2) -> float: return 0.0
## CIV-C hook (realm/ecology.gd bind_frontier): Callable(Vector2) -> Array of [label, value] for hunting bands the dens
## do not cover (goblin / orc clans). Unset by default.
var territory_source: Callable = Callable()

var _next_id := 0


func _init(stones: RARunestoneNetwork, eco: RAMonsterEcology) -> void:
	runestones = stones
	ecology = eco


func add_modifier(label: String, pos: Vector2, radius: float, value: float, expires_day: int) -> void:
	modifiers.append({"id": _next_id, "label": label, "pos": pos, "radius": radius, "value": value, "expires_day": expires_day})
	_next_id += 1


func expire(day: int) -> void:
	modifiers = modifiers.filter(func(m: Dictionary) -> bool: return m["expires_day"] > day)


## {total, lines: [[label, value]]}: the breakdown shown to the player.
func evaluate(p: Vector2) -> Dictionary:
	var lines: Array = []
	var wild := WorldGen.forest_density(p.x, p.y) * 30.0 + 8.0
	var near := WorldGen.nearest_settlement(p)
	if not near.is_empty() and p.distance_to(near["pos"]) < near["radius"]:
		wild = 2.0
	lines.append(["Wilderness", wild])
	var mp := ecology.pressure_at(p)
	for src in mp["sources"]:
		var den: Dictionary = src["den"]
		lines.append(["%s den (%d)" % [String(den["species"]).capitalize(), den["population"]], src["value"]])
	for m in modifiers:
		var d := p.distance_to(m["pos"])
		if d < m["radius"]:
			lines.append([m["label"], m["value"] * (1.0 - smoothstep(m["radius"] * 0.5, m["radius"], d))])
	if territory_source.is_valid():
		for tl: Array in territory_source.call(p):
			lines.append([String(tl[0]), float(tl[1])])
	var cov := runestones.coverage(p)
	if cov > 0.01:
		lines.append(["Runestone protection", -cov * 80.0])
	var patrol: float = patrols.call(p)
	if patrol > 0.01:
		lines.append(["Patrols", -patrol * 20.0])
	var total := 0.0
	for l in lines:
		total += l[1]
	return {"total": clampf(total, 0.0, 100.0), "lines": lines, "coverage": cov}


static func describe(t: float) -> String:
	if t < 10.0: return "Safe"
	if t < 30.0: return "Watchful"
	if t < 55.0: return "Dangerous"
	if t < 80.0: return "Perilous"
	return "Deadly"
