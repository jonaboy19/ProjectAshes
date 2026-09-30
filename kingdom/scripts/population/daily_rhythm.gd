extends RefCounted
## Per-resident daily rhythm layered on WorldSim's job schedule
## (docs/concepts/WORLD_DAILY_RHYTHM_DESIGN.md).
##
## WorldSim switches every resident of a job at the same clock boundary. Here
## each person runs a little behind that clock by a stable, deterministic
## delay (per person and day, so a reload reproduces it), so the street fills
## and empties gradually instead of in one wave. Evenings add a visit to the
## inn for some residents before they head home to sleep.
##
## Pure functions of WorldSim state: no per-frame randomness, no saved data,
## and WorldSim's own phase, wages and targets are left untouched.

const StreetGraph := preload("res://scripts/population/street_graph.gd")

enum State { HOME, WORK, MARKET, INN }

## Largest departure delay, in game hours (2.0 h = 60 real seconds). Wider than
## the original 0.9 h so a schedule boundary (e.g. the 17:00 market call) empties
## and fills the street gradually over a couple of minutes instead of every
## resident of a job stepping outside in the same few seconds.
const MAX_DELAY := 2.0
## Evening at the inn runs from the end of the market until this hour.
const INN_OPEN := 19.5
const INN_CLOSE := 22.5
## Percentage of (non-guard) residents who stop at the inn on a given evening.
const INN_SHARE := 30
## WorldSim's schedule boundaries (see WorldSim._current_phase).
const BOUNDARIES := [6.0, 12.0, 13.0, 17.0, 19.5, 21.0]
## Settlement plans are immutable for the fixed world seed; cache inn presence once.
static var _inn_lot_by_settlement := {}


## Stable delay behind the shared clock for person i today, in game hours.
static func delay(i: int) -> float:
	var h := hash(i * 7919 + WorldSim.day * 104729 + 17)
	return float(h % 1000) / 1000.0 * MAX_DELAY


## The clock person i is living by.
static func local_time(i: int) -> float:
	return wrapf(WorldSim.time_of_day - delay(i), 0.0, 24.0)


## WorldSim._current_phase() evaluated at hour h: 0 home, 1 work, 2 market.
## (Mirrors that function, which only reads the current world time.)
static func phase_at(job: int, h: float) -> int:
	if h < 6.0 or h >= 21.0:
		return 0
	if job == 3:
		return 1
	if h < 17.0:
		return 2 if (h >= 12.0 and h < 13.0 and job == 4) else 1
	return 2 if h < 19.5 else 0


static func goes_to_inn(i: int) -> bool:
	return WorldSim.job[i] != 3 and hash(i * 31 + WorldSim.day * 977) % 100 < INN_SHARE


## Whether resident i's settlement plan has an inn, using the cached lookup.
static func has_inn_lot(i: int) -> bool:
	return _has_inn_lot(i)


static func _has_inn_lot(i: int) -> bool:
	if i < 0 or i >= WorldSim.home.size():
		return false
	var settlement_id := int(WorldSim.home[i])
	if settlement_id < 0 or settlement_id >= WorldGen.settlements.size():
		return false
	if _inn_lot_by_settlement.has(settlement_id):
		return bool(_inn_lot_by_settlement[settlement_id])
	var settlement: Dictionary = WorldGen.settlements[settlement_id]
	var plan: Dictionary = settlement.get("plan", {})
	for lot: Dictionary in plan.get("lots", []):
		if String(lot.get("asset", "")) == "inn":
			_inn_lot_by_settlement[settlement_id] = true
			return true
	_inn_lot_by_settlement[settlement_id] = false
	return false


## Where person i wants to be right now.
static func state(i: int) -> int:
	var t := local_time(i)
	var p := phase_at(WorldSim.job[i], t)
	if p == 0 and t >= INN_OPEN and t < INN_CLOSE and goes_to_inn(i) and _has_inn_lot(i):
		return State.INN
	return p


## True while WorldSim has already moved person i to a new phase but their own
## clock hasn't reached it yet.
static func lagging(i: int) -> bool:
	var sim_phase: int = WorldSim.phase[i]
	return sim_phase != 255 and phase_at(WorldSim.job[i], local_time(i)) != sim_phase


## True for a short window after any shared schedule boundary: outside it no
## resident can be lagging, so callers can skip the per-person check.
static func in_lag_window() -> bool:
	var h := WorldSim.time_of_day
	for b: float in BOUNDARIES:
		var since := h - b
		if since >= 0.0 and since < MAX_DELAY:
			return true
	return false


## Destination for person i in `st`. Home, work and market reuse WorldSim's
## deterministic spots (the same point WorldSim targets for that phase); the
## inn gets a spread of standing spots in front of its door.
static func goal(i: int, st: int, graph: StreetGraph) -> Vector2:
	var s: Dictionary = WorldGen.settlements[WorldSim.home[i]]
	if st == State.INN:
		if graph != null and graph.inn_door != Vector2.INF:
			var h := hash(i * 613 + 5)
			var ang := (float(h % 1000) / 1000.0 - 0.5) * 2.2
			var dist := 1.8 + float((h / 1000) % 100) / 100.0 * 3.2
			return graph.inn_door + graph.inn_facing.rotated(ang) * dist
		return WorldSim._spot(s, State.HOME, i)
	return WorldSim._spot(s, st, i)


## Person i should still be indoors at home: their clock is before the morning
## departure and they're standing at their door.
static func still_home(i: int) -> bool:
	if WorldSim.time_of_day < 6.0 or WorldSim.time_of_day >= 6.0 + MAX_DELAY:
		return false
	if phase_at(WorldSim.job[i], local_time(i)) != 0:
		return false
	var s: Dictionary = WorldGen.settlements[WorldSim.home[i]]
	return WorldSim.pos[i].distance_squared_to(WorldSim._spot(s, 0, i)) < 2.25


## Short line for the name tag.
static func label(i: int, st: int, travelling: bool) -> String:
	match st:
		State.WORK:
			if WorldSim.job[i] == 3:
				return "heading to post" if travelling else "on watch"
			return "off to work" if travelling else "working"
		State.MARKET:
			return "off to market" if travelling else "at the market"
		State.INN:
			return "off to the inn" if travelling else "at the inn"
	var t := local_time(i)
	if t >= INN_CLOSE or t < 6.0:
		return "turning in"
	return "heading home"
