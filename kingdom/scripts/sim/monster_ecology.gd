class_name RAMonsterEcology
extends RefCounted
## Lightweight monster ecology. Dens have a species, territory, population,
## food, aggression and migration pressure. Populations grow with food, split
## and migrate when crowded, recover when hunted, and avoid protected land
## unless pressure overwhelms it. Pure data: packs only get bodies near the
## player (see FrontierSpawner).

signal den_changed(den: Dictionary)
signal migration(den: Dictionary, from_pos: Vector2, to_pos: Vector2)

const SPECIES := {
	"wolf": {"threat": 1.0, "growth": 0.05, "max_pop": 14, "territory": 220.0, "pack": 4},
}

## Den: {id, species, pos, territory, population, food 0..1, aggression 0..1, pressure 0..1, alive}
var dens: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 4242) -> void:
	_rng.seed = seed_value


func add_den(species: String, pos: Vector2, population: int) -> Dictionary:
	var sp: Dictionary = SPECIES[species]
	var den := {"id": dens.size(), "species": species, "pos": pos, "territory": sp["territory"],
		"population": population, "food": 0.7, "aggression": 0.4, "pressure": 0.0, "alive": true}
	dens.append(den)
	return den


## Threat contributed by dens at p (0..~100), with the dens responsible.
func pressure_at(p: Vector2) -> Dictionary:
	var total := 0.0
	var sources: Array = []
	for den in dens:
		if not den["alive"] or den["population"] <= 0:
			continue
		var d := p.distance_to(den["pos"])
		var r: float = den["territory"]
		if d > r * 1.6:
			continue
		var sp: Dictionary = SPECIES[den["species"]]
		var falloff := 1.0 - smoothstep(r * 0.3, r * 1.6, d)
		var v: float = den["population"] * sp["threat"] * (0.6 + den["aggression"]) * falloff * 3.0
		if v > 0.5:
			sources.append({"den": den, "value": v})
			total += v
	return {"total": total, "sources": sources}


## Daily step. `coverage` is a Callable(Vector2) -> float from the runestone network.
func tick_day(coverage: Callable, rift_instability: float, winter: bool) -> void:
	for den in dens:
		if not den["alive"]:
			continue
		var sp: Dictionary = SPECIES[den["species"]]
		# Food: winter and crowding reduce it; small random swings.
		var crowd: float = den["population"] / float(sp["max_pop"])
		den["food"] = clampf(den["food"] + _rng.randf_range(-0.05, 0.06) - (0.08 if winter else 0.0) - crowd * 0.03, 0.0, 1.0)
		# Growth or starvation.
		if den["food"] > 0.5 and den["population"] < sp["max_pop"]:
			if _rng.randf() < sp["growth"] * den["food"] * 2.0:
				den["population"] += 1
		elif den["food"] < 0.2 and den["population"] > 0 and _rng.randf() < 0.3:
			den["population"] -= 1
		# Hunger, Rift instability and crowding raise aggression and pressure to move.
		den["aggression"] = clampf(0.3 + (1.0 - den["food"]) * 0.5 + rift_instability * 0.4, 0.0, 1.0)
		den["pressure"] = clampf(crowd * 0.6 + (1.0 - den["food"]) * 0.5 + rift_instability * 0.3, 0.0, 1.0)
		if den["pressure"] > 0.75 and den["population"] >= sp["pack"] * 2:
			_migrate(den, coverage)
		den_changed.emit(den)


## Part of the den splits off and settles somewhere new, avoiding protected land
## unless it's desperate enough to push into weak coverage.
func _migrate(den: Dictionary, coverage: Callable) -> void:
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 12:
		var ang := _rng.randf() * TAU
		var cand: Vector2 = den["pos"] + Vector2(cos(ang), sin(ang)) * _rng.randf_range(250.0, 600.0)
		var cov: float = coverage.call(cand)
		var score: float = -cov * 3.0 + WorldGen.forest_density(cand.x, cand.y) + (float(den["pressure"]) - 0.75) * cov
		if score > best_score:
			best_score = score
			best = cand
	var sp: Dictionary = SPECIES[den["species"]]
	var moved: int = den["population"] / 2
	den["population"] -= moved
	var child := add_den(den["species"], best, moved)
	child["aggression"] = den["aggression"]
	migration.emit(child, den["pos"], best)


## The player (or a patrol) killed members of a den.
func cull(den_id: int, count: int) -> void:
	var den := dens[den_id]
	den["population"] = maxi(0, den["population"] - count)
	den["aggression"] = minf(1.0, den["aggression"] + 0.1)
	if den["population"] == 0:
		den["alive"] = false
	den_changed.emit(den)


func serialize() -> Array:
	var out := []
	for den in dens:
		out.append({"id": den["id"], "species": den["species"], "x": den["pos"].x, "y": den["pos"].y,
			"territory": den["territory"], "population": den["population"], "food": den["food"],
			"aggression": den["aggression"], "pressure": den["pressure"], "alive": den["alive"]})
	return out


func deserialize(data: Array) -> void:
	dens.clear()
	for d: Dictionary in data:
		dens.append({"id": int(d["id"]), "species": String(d["species"]), "pos": Vector2(d["x"], d["y"]),
			"territory": float(d["territory"]), "population": int(d["population"]), "food": float(d["food"]),
			"aggression": float(d["aggression"]), "pressure": float(d["pressure"]), "alive": bool(d["alive"])})
