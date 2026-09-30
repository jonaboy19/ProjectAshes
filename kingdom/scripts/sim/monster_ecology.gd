class_name RAMonsterEcology
extends RefCounted
## Lightweight monster ecology. Dens have a species, territory, population,
## food, aggression and migration pressure. Populations grow with food, split
## and migrate when crowded, recover when hunted, and avoid protected land
## unless pressure overwhelms it. Pure data: packs only get bodies near the
## player (see FrontierSpawner).
##
## Migration chains (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Living world
## simulation": "a strong beast moves in -> wolves displaced -> livestock
## lost -> hunters find the real cause"): an apex creature (SPECIES entry with
## "apex": true) claims a wide territory. Ordinary dens caught inside it feel
## extra pressure and, when they migrate, are biased toward the nearest
## settlement instead of away from runestone coverage -- they are fleeing the
## apex, not just looking for open land. A wolf den that ends up near a
## settlement may take livestock. Winter pushes wolves the same way, at a
## lower pressure threshold. Rift instability can seed a corrupted den near
## the Rift outpost. Every notable happening is logged to `_events` and
## readable via `events_since(day)`, so lordship/homestead/radiant_quests can
## react without this file depending on any of them.

signal den_changed(den: Dictionary)
signal migration(den: Dictionary, from_pos: Vector2, to_pos: Vector2)
signal ecology_event(event: Dictionary)

const SPECIES := {
	"wolf": {"threat": 1.0, "growth": 0.05, "max_pop": 14, "territory": 220.0, "pack": 4},
	"corrupted_wolf": {"threat": 1.6, "growth": 0.04, "max_pop": 10, "territory": 260.0, "pack": 4},
	"troll": {"threat": 4.0, "growth": 0.0, "max_pop": 1, "territory": 700.0, "pack": 1, "apex": true},
	"wyvern": {"threat": 5.0, "growth": 0.0, "max_pop": 1, "territory": 900.0, "pack": 1, "apex": true},
	"bear": {"threat": 2.5, "growth": 0.0, "max_pop": 1, "territory": 500.0, "pack": 1, "apex": true},
	# Region 1 (package C11, scripts/world/region1_creatures.gd). max_pop stays under 2 x pack so these dens never split.
	"stagborn_elk": {"threat": 0.0, "growth": 0.02, "max_pop": 11, "territory": 170.0, "pack": 6},
	"stagborn_warden": {"threat": 3.0, "growth": 0.0, "max_pop": 1, "territory": 70.0, "pack": 1},
	"ghoul": {"threat": 1.4, "growth": 0.02, "max_pop": 5, "territory": 110.0, "pack": 3},
	"giant_wasp": {"threat": 1.1, "growth": 0.04, "max_pop": 5, "territory": 90.0, "pack": 3},
	"bog_toad": {"threat": 0.9, "growth": 0.03, "max_pop": 5, "territory": 80.0, "pack": 3},
	"rift_slime": {"threat": 0.8, "growth": 0.05, "max_pop": 7, "territory": 100.0, "pack": 4},
	"rift_wraith": {"threat": 2.2, "growth": 0.0, "max_pop": 2, "territory": 140.0, "pack": 2},
}
## Migration is easier to trigger when it's fleeing an apex or winter cold.
const MIGRATE_PRESSURE := 0.75
const DISPLACED_MIGRATE_PRESSURE := 0.55
const WINTER_PRESSURE_ADD := 0.35
const APEX_PRESSURE_ADD := 0.6
## A wolf den within this distance of a settlement may raid livestock.
const LIVESTOCK_RANGE := 260.0
const LIVESTOCK_CHANCE := 0.12
const RIFT_DEN_CHANCE := 0.06
const RIFT_DEN_MIN_INSTABILITY := 0.45
const MAX_EVENTS := 200
## Hard ceiling on living dens. Migration only ever added dens (25 -> 118 alive in two simulated years, and
## pop doubling), so past this a crowded den simply stays put and stops growing at its species' max_pop.
const MAX_ALIVE_DENS := 72      # was 48: Region 1 adds about 25 fixed dens (herds, ghouls, wasps, toads, rift) that never migrate

## Den: {id, species, pos, territory, population, food 0..1, aggression 0..1,
## pressure 0..1, alive, apex: bool}
var dens: Array[Dictionary] = []
## {day, type, ...}: "apex_arrival", "displaced", "livestock_taken", "rift_den".
var _events: Array[Dictionary] = []
## Displacements not yet turned into a radiant quest: {apex_den_id, den_id,
## displaced_pos, apex_pos, species, notice_day}.
var _pending_hunts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _day := 0


func _init(seed_value := 4242) -> void:
	_rng.seed = seed_value


## Region1 hook H4 (docs/regions/REGION_1_PLAN.md): Scar Tide cells turn a species into its rift variant (Callable(species, pos) -> species).
var variant_override: Callable = Callable()


func variant_for(species: String, pos: Vector2) -> String:
	return String(variant_override.call(species, pos)) if variant_override.is_valid() else species


func add_den(species: String, pos: Vector2, population: int) -> Dictionary:
	var sp: Dictionary = SPECIES[species]
	var den := {"id": dens.size(), "species": species, "pos": pos, "territory": sp["territory"],
		"population": population, "food": 0.7, "aggression": 0.4, "pressure": 0.0, "alive": true,
		"apex": bool(sp.get("apex", false))}
	dens.append(den)
	return den


## An apex creature moves into the region. Logs an "apex_arrival" event; the
## next tick_day() will start pushing nearby weaker dens out.
func spawn_apex(species: String, pos: Vector2, day: int) -> Dictionary:
	var den := add_den(species, pos, 1)
	_log_event({"day": day, "type": "apex_arrival", "species": species, "pos": pos, "den_id": int(den["id"])})
	return den


func alive_count() -> int:
	var n := 0
	for den in dens:
		if den["alive"]:
			n += 1
	return n


func _apex_dens() -> Array:
	var out := []
	for den in dens:
		if den["alive"] and bool(den.get("apex", false)):
			out.append(den)
	return out


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
	_day += 1
	_maybe_spawn_rift_den(rift_instability, _day)
	var apexes := _apex_dens()
	for den in dens:
		if not den["alive"]:
			continue
		var sp: Dictionary = SPECIES[den["species"]]
		if bool(den.get("apex", false)):
			# Apex creatures are not part of the food/growth cycle; they just sit
			# in their territory pushing weaker dens out.
			den["food"] = 1.0
			den["aggression"] = clampf(0.5 + rift_instability * 0.3, 0.0, 1.0)
			den["pressure"] = 0.0
			den_changed.emit(den)
			continue
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
		# An apex nearby pushes weaker dens out of its territory; winter pushes
		# wolves down toward human land at a lower threshold too.
		var apex_source := {}
		var apex_push := 0.0
		for apex in apexes:
			var ap_sp: Dictionary = SPECIES[apex["species"]]
			var d: float = den["pos"].distance_to(apex["pos"])
			var r: float = float(ap_sp["territory"]) * 1.2
			if d < r:
				var push: float = 1.0 - smoothstep(0.0, r, d)
				if push > apex_push:
					apex_push = push
					apex_source = apex
		var winter_push := WINTER_PRESSURE_ADD if (winter and den["species"] == "wolf") else 0.0
		den["pressure"] = clampf(den["pressure"] + apex_push * APEX_PRESSURE_ADD + winter_push, 0.0, 1.0)
		var displaced := apex_push > 0.0 or winter_push > 0.0
		var threshold := DISPLACED_MIGRATE_PRESSURE if displaced else MIGRATE_PRESSURE
		if den["pressure"] > threshold and den["population"] >= sp["pack"] * 2 and alive_count() < MAX_ALIVE_DENS:
			_migrate(den, coverage, displaced, apex_source)
		_maybe_take_livestock(den)
		den_changed.emit(den)


## Part of the den splits off and settles somewhere new. Ordinarily it avoids
## protected land unless it's desperate enough to push into weak coverage;
## when `toward_settlement` is true (fleeing an apex, or winter cold) it is
## instead biased toward the nearest settlement -- it's fleeing into human
## land, not just looking for open ground.
func _migrate(den: Dictionary, coverage: Callable, toward_settlement := false, apex: Dictionary = {}) -> void:
	var near := WorldGen.nearest_settlement(den["pos"]) if toward_settlement else {}
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 12:
		var ang := _rng.randf() * TAU
		var cand: Vector2 = den["pos"] + Vector2(cos(ang), sin(ang)) * _rng.randf_range(250.0, 600.0)
		var cov: float = coverage.call(cand)
		var score: float
		if toward_settlement and not near.is_empty():
			var to_settlement: float = 1.0 - clampf(cand.distance_to(near["pos"]) / 1200.0, 0.0, 1.0)
			score = to_settlement * 4.0 + WorldGen.forest_density(cand.x, cand.y) - cov * 0.5
		else:
			score = -cov * 3.0 + WorldGen.forest_density(cand.x, cand.y) + (float(den["pressure"]) - 0.75) * cov
		if score > best_score:
			best_score = score
			best = cand
	var sp: Dictionary = SPECIES[den["species"]]
	var moved: int = maxi(1, den["population"] / 2)
	den["population"] -= moved
	var child := add_den(den["species"], best, moved)
	child["aggression"] = den["aggression"]
	migration.emit(child, den["pos"], best)
	if toward_settlement:
		_log_event({"day": _day, "type": "displaced", "den_id": int(child["id"]), "from": den["pos"],
			"to": best, "species": den["species"], "reason": "apex" if not apex.is_empty() else "winter"})
		if not apex.is_empty():
			var hunt := {"apex_den_id": int(apex["id"]), "den_id": int(child["id"]), "displaced_pos": best,
				"apex_pos": apex["pos"], "species": String(apex["species"]), "notice_day": _day}
			_pending_hunts.append(hunt)
			_log_event({"day": _day, "type": "apex_hunt_available", "apex_den_id": int(apex["id"]),
				"pos": apex["pos"], "species": String(apex["species"])})


## Wolves that ended up near a settlement (chased there by an apex, or by
## winter) sometimes take livestock. Lordship/homestead can read the event
## (see events_since()) and dock loyalty or stock without this file knowing
## about either of them.
func _maybe_take_livestock(den: Dictionary) -> void:
	if den["species"] != "wolf" or den["population"] <= 0:
		return
	var near := WorldGen.nearest_settlement(den["pos"])
	if near.is_empty() or den["pos"].distance_to(near["pos"]) > LIVESTOCK_RANGE:
		return
	if _rng.randf() < LIVESTOCK_CHANCE * (0.5 + den["aggression"]):
		_log_event({"day": _day, "type": "livestock_taken", "den_id": int(den["id"]), "pos": den["pos"],
			"settlement": int(near.get("id", -1)), "settlement_name": String(near.get("name", ""))})


## Rift instability can seed a corrupted den near the Rift outpost
## (WorldGen.sites kind "rift_outpost"), independent of the ordinary
## population cycle.
func _maybe_spawn_rift_den(rift_instability: float, day: int) -> void:
	if rift_instability < RIFT_DEN_MIN_INSTABILITY or alive_count() >= MAX_ALIVE_DENS + 8:
		return
	if _rng.randf() > RIFT_DEN_CHANCE * rift_instability:
		return
	var outpost := Vector2.ZERO
	var found := false
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "rift_outpost":
			outpost = s["pos"]
			found = true
			break
	if not found:
		return
	var ang := _rng.randf() * TAU
	var pos := outpost + Vector2(cos(ang), sin(ang)) * _rng.randf_range(80.0, 260.0)
	var den := add_den("corrupted_wolf", pos, _rng.randi_range(4, 7))
	_log_event({"day": day, "type": "rift_den", "den_id": int(den["id"]), "pos": pos})


## The player (or a patrol) killed members of a den.
func cull(den_id: int, count: int) -> void:
	var den := dens[den_id]
	den["population"] = maxi(0, den["population"] - count)
	den["aggression"] = minf(1.0, den["aggression"] + 0.1)
	if den["population"] == 0:
		den["alive"] = false
	den_changed.emit(den)


# --- events & apex hunts -------------------------------------------------------------

func _log_event(event: Dictionary) -> void:
	if event.get("pos") is Vector2 and String(event.get("type", "")) in ["livestock_taken", "apex_arrival"]:
		AshMemory.report(&"raid", event["pos"], AshMemory.clock())   # Region1 hook C6: the ashes remember it (no-op when the module is off)
	_events.append(event)
	if _events.size() > MAX_EVENTS:
		_events = _events.slice(_events.size() - MAX_EVENTS)
	ecology_event.emit(event)


## Events logged on or after `day` (apex arrivals, displacements, livestock
## losses, rift dens, new apex hunts). Read-only: callers never mutate these.
## tick_day()'s own day counter (starts at 0, +1 per call) -- not
## WorldSim.day. A caller polling events_since() daily should keep the value
## this returned last time and pass it back next time, e.g.:
##   var last := ecology.current_day()
##   ... later ...
##   for e in ecology.events_since(last): ...
##   last = ecology.current_day()
func current_day() -> int:
	return _day


func events_since(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _events:
		if int(e.get("day", 0)) >= day:
			out.append(e)
	return out


## Displacements noticed but not yet offered as an "apex_hunt" radiant quest.
## radiant_quests.gd's world dict can pass these straight through as
## "apex_hunts"; call consume_apex_hunt() once a quest for one is generated so
## it isn't offered twice.
func pending_apex_hunts() -> Array[Dictionary]:
	return _pending_hunts.duplicate(true)


func consume_apex_hunt(apex_den_id: int) -> void:
	_pending_hunts = _pending_hunts.filter(func(h: Dictionary) -> bool: return int(h["apex_den_id"]) != apex_den_id)


func serialize() -> Array:
	var out := []
	for den in dens:
		out.append({"id": den["id"], "species": den["species"], "x": den["pos"].x, "y": den["pos"].y,
			"territory": den["territory"], "population": den["population"], "food": den["food"],
			"aggression": den["aggression"], "pressure": den["pressure"], "alive": den["alive"],
			"apex": bool(den.get("apex", false))})
	return out


## Full state round trip (dens plus events, pending hunts and the day
## counter), for tests and any caller that wants migration history to
## survive a save; frontier.gd's own save only calls serialize()/deserialize()
## today (dens only) -- see the war/migration hooks in the task report to
## wire this in.
func serialize_state() -> Dictionary:
	return {"dens": serialize(), "events": _events.duplicate(true), "pending_hunts": _pending_hunts.duplicate(true), "day": _day}


func deserialize_state(d: Dictionary) -> void:
	deserialize(d.get("dens", []))
	_events.assign(d.get("events", []))
	_pending_hunts.assign(d.get("pending_hunts", []))
	_day = int(d.get("day", 0))


func deserialize(data: Array) -> void:
	dens.clear()
	for d: Dictionary in data:
		var species := String(d["species"])
		var default_apex := bool((SPECIES.get(species, {}) as Dictionary).get("apex", false))
		dens.append({"id": int(d["id"]), "species": species, "pos": Vector2(d["x"], d["y"]),
			"territory": float(d["territory"]), "population": int(d["population"]), "food": float(d["food"]),
			"aggression": float(d["aggression"]), "pressure": float(d["pressure"]), "alive": bool(d["alive"]),
			"apex": bool(d.get("apex", default_apex))})
