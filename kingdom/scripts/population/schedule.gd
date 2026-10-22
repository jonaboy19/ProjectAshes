extends RefCounted
## One daily timetable for every simulation level (docs/design/SIM_HIERARCHY.md).
##
##   near player        UtilityBrain scores acts; this table is its baseline "sched_*" inputs (DailyRhythm.state)
##   same settlement    WorldSim rows: `phase()` picks the row's target, `spot()` the point it walks to
##   other settlements  no rows at all: `mix()` / `street_activity()` turn the same table into numbers
##
## Phases (the person's place for the hour): HOME, WORK, MARKET, INN, TEMPLE, TRAIN, SOCIAL. Waking up, the
## meal, the walk there (commute) and bed are not places: the near AI plays them around HOME/WORK
## transitions (utility_brain.gd, villager.gd), the rows simply move people between the places.
##
## What changes the table is a bit mask of the settlement's circumstances (`TownMood.flags_of`):
##   REST      every 7th day: lie in, temple, half-day market, socialise, no work except guards and animal chores
##   FESTIVAL  a day from scripts/sim/seasons.gd: late start, blessing, the plaza all day, revels until 23:30
##   WAR       the realm is at war: guards and militia drill, guards keep a night watch
##   MONSTER   a raid or beast about: fields and forest emptied by mid afternoon, no evening on the street
##   SCARCE    food shortage: bread queues at dawn, nobody can afford the inn, thin evenings
##   MOURN     a death in the town: half the town at the funeral service, quiet evenings
##   CURFEW    the law's curfew is in force at this hour: everyone but the watch is home
##
## Pure functions of (job, hour, flags, person): no node, no autoload, deterministic, safe to call per row.
## With no flags and no person (i < 0) the table is exactly the original WorldSim schedule.

enum Phase { HOME, WORK, MARKET, INN, TEMPLE, TRAIN, SOCIAL }
const NAMES := ["home", "work", "market", "inn", "temple", "train", "social"]

const F_REST := 1
const F_FESTIVAL := 2
const F_WAR := 4
const F_MONSTER := 8
const F_SCARCE := 16
const F_MOURN := 32
const F_CURFEW := 64
const FLAG_NAMES := {F_REST: "rest", F_FESTIVAL: "festival", F_WAR: "war", F_MONSTER: "monster", F_SCARCE: "scarce",
	F_MOURN: "mourn", F_CURFEW: "curfew"}

const INN_OPEN := 19.5
const INN_CLOSE := 22.5
## Percentage of (non-guard) residents who stop at the inn on an ordinary evening.
const INN_SHARE := 30

static var _places := {}      # settlement id -> {inn, inn_face, temple, temple_face, train, plaza_r}


## Does person `i` visit the inn today (a stable roll per person and day)?
static func goes_to_inn(i: int, day: int, flags := 0) -> bool:
	var share := INN_SHARE
	if flags & F_SCARCE:
		share = 10
	if flags & F_FESTIVAL:
		share = 60
	if flags & F_MOURN:
		share = 15
	return posmod(hash(i * 31 + day * 977), 100) < share


## The place of a person with `job` at clock `h` (0..24). `i` is the person (>= 0 enables the per-person
## shares), `day` the world day (the inn roll). Without flags and i < 0 this is the original three-phase table.
static func phase(job: int, h: float, flags := 0, i := -1, day := 1) -> int:
	var pers := i >= 0
	var guard := job == 3
	var rest := (flags & F_REST) != 0
	var fest := (flags & F_FESTIVAL) != 0
	# The watch: curfew, war and monsters keep a third of the guards out all night.
	if (h < 6.0 or h >= 21.0) and guard and pers and (flags & (F_CURFEW | F_WAR | F_MONSTER)) != 0 and i % 3 == 0:
		return Phase.WORK
	# The law sends everyone else home while the curfew is in force.
	if (flags & F_CURFEW) != 0 and (h >= 20.0 or h < 6.0):
		return Phase.WORK if (guard and pers and i % 3 == 0) else Phase.HOME
	# Inn evenings (also past nine at the inn door, which the original table sent home).
	if pers and not guard and h >= INN_OPEN and h < INN_CLOSE and (flags & F_MONSTER) == 0 and goes_to_inn(i, day, flags):
		return Phase.INN
	# Festival revels run late.
	if fest and pers and not guard and h >= 21.0 and h < 23.5 and i % 4 != 0:
		return Phase.SOCIAL if i % 2 == 0 else Phase.INN
	if h < 6.0 or h >= 21.0:
		return Phase.HOME
	if guard:
		if pers:
			if (flags & F_WAR) != 0 and h >= 14.0 and h < 16.0 and i % 2 == 0:
				return Phase.TRAIN
			if (flags & F_WAR) == 0 and h >= 14.0 and h < 15.5 and i % 4 == 0:
				return Phase.TRAIN
			if fest and h >= 12.0 and h < 20.0 and i % 3 == 0:
				return Phase.SOCIAL      # off-duty guards in the crowd
		return Phase.WORK
	if not pers and flags == 0:
		return _legacy(job, h)
	# Funeral service for half the town.
	if (flags & F_MOURN) != 0 and h >= 10.0 and h < 11.5 and i % 2 == 0 and (flags & (F_MONSTER | F_WAR)) == 0:
		return Phase.TEMPLE
	if fest:
		if h < 9.0:
			return Phase.HOME if i % 3 != 0 else Phase.MARKET
		if h < 10.5:
			return Phase.TEMPLE if i % 3 == 0 else Phase.SOCIAL
		return Phase.MARKET if i % 3 == 2 else Phase.SOCIAL
	if rest:
		if h < 8.5:
			return Phase.WORK if (job == 0 and h >= 6.5 and i % 2 == 0) else Phase.HOME
		if h < 10.0:
			return Phase.TEMPLE if i % 4 != 0 else Phase.HOME
		if h < 14.0:
			return Phase.MARKET if i % 3 != 0 else Phase.SOCIAL
		if h < 17.0:
			return Phase.TRAIN if ((flags & F_WAR) != 0 and i % 5 == 0) else Phase.SOCIAL
		return Phase.SOCIAL if h < 19.5 else Phase.HOME
	# An ordinary working day, bent by what is going on.
	var p := _legacy(job, h)
	if (flags & F_MONSTER) != 0:
		if (job == 0 or job == 5) and h >= 15.0:
			return Phase.HOME
		if h >= 17.0:
			return Phase.HOME
	if (flags & F_WAR) != 0 and (job == 4 or job == 5) and i % 5 == 0 and h >= 15.0 and h < 17.0:
		return Phase.TRAIN
	if (flags & F_SCARCE) != 0:
		if h >= 6.5 and h < 9.0 and i % 3 == 0:
			return Phase.MARKET          # the bread queue
		if p == Phase.MARKET and h >= 17.0 and i % 2 == 0:
			return Phase.HOME            # nothing to buy, nothing to spend
	if p == Phase.WORK and pers:
		# Temple services for a devout slice of the town (the near AI's service bell at 8:45 and 18:15).
		if h >= 8.5 and h < 9.25 and i % 11 == 0:
			return Phase.TEMPLE
	if p == Phase.MARKET and pers and h >= 17.0 and i % 7 == 0:
		return Phase.TEMPLE if (h >= 18.0 and h < 18.75 and i % 13 == 0) else Phase.SOCIAL
	return p


## The original WorldSim schedule: 0 home, 1 work, 2 market.
static func _legacy(job: int, h: float) -> int:
	if h < 6.0 or h >= 21.0:
		return Phase.HOME
	if job == 3:
		return Phase.WORK
	if h < 17.0:
		return Phase.MARKET if (h >= 12.0 and h < 13.0 and job == 4) else Phase.WORK
	return Phase.MARKET if h < 19.5 else Phase.HOME


## Phases that keep a person outdoors (the street fills with them).
static func outdoors(p: int) -> bool:
	return p != Phase.HOME


## Fraction of a typical settlement's people in each phase at `h` (a dict phase -> 0..1).
## "Other settlements = realm numbers": no per-person rows, a closed form over a fixed sample whose job mix
## matches WorldSim's `_pick_job` for the settlement kind.
static func mix(kind: String, h: float, flags := 0, day := 1) -> Dictionary:
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var n := 80
	for k in n:
		var job := _sample_job(kind, k)
		counts[phase(job, h, flags, k, day)] += 1
	var out := {}
	for p in counts.size():
		out[p] = float(counts[p]) / float(n)
	return out


static func _sample_job(kind: String, k: int) -> int:
	# Stratified draw from WorldSim._pick_job's cumulative table (k in 0..79).
	var roll := (float(k) + 0.5) / 80.0
	if kind == "village" or kind == "hamlet":
		return 0 if roll < 0.55 else (5 if roll < 0.7 else (4 if roll < 0.85 else (1 if roll < 0.92 else 2)))
	return 2 if roll < 0.25 else (1 if roll < 0.4 else (3 if roll < 0.55 else (4 if roll < 0.8 else 0)))


## 0..1 how busy the streets are, from the realm numbers alone: everyone in a public place (market, inn, temple,
## square, drill yard) counts, a third of those at work (the outdoor trades, the watch) do.
static func street_activity(kind: String, h: float, flags := 0, day := 1) -> float:
	var m := mix(kind, h, flags, day)
	return float(m[Phase.MARKET]) + float(m[Phase.INN]) + float(m[Phase.TEMPLE]) + float(m[Phase.SOCIAL]) + float(m[Phase.TRAIN]) + 0.35 * float(m[Phase.WORK])


## Share of people at the inn / temple / drilling, for the realm's own bookkeeping (tavern takings, etc.).
static func share(kind: String, h: float, p: int, flags := 0, day := 1) -> float:
	return float(mix(kind, h, flags, day)[p])


# ================================================================ places for WorldSim rows
## Where phase `which` of settlement `s` sends person `i` (a point; cached plan data, no graph, no nodes).
static func spot(s: Dictionary, which: int, i: int, day: int) -> Vector2:
	var pl := _places_of(s)
	var h := hash(i * 613 + which * 29 + 5)
	var ang := (float(posmod(h, 1000)) / 1000.0 - 0.5) * 2.2
	var dist := 1.8 + float(posmod(h / 1000, 100)) / 100.0 * 3.2
	match which:
		Phase.INN:
			var face: Vector2 = pl["inn_face"]
			return (pl["inn"] as Vector2) + face.rotated(ang) * dist
		Phase.TEMPLE:
			var f2: Vector2 = pl["temple_face"]
			return (pl["temple"] as Vector2) + f2.rotated(ang) * (1.2 + dist * 0.5)
		Phase.TRAIN:
			var row := posmod(h, 4)
			var col := posmod(h / 7, 5)
			var ax: Vector2 = (pl["train_axis"] as Vector2)
			return (pl["train"] as Vector2) + ax * (float(col) * 1.6 - 3.2) + Vector2(-ax.y, ax.x) * (float(row) * 1.5 - 2.2)
		_:
			# SOCIAL: a loose ring on the plaza.
			var a := float(posmod(h, 3600)) / 3600.0 * TAU
			var pr: float = pl["plaza_r"]
			return (s["pos"] as Vector2) + Vector2(cos(a), sin(a)) * lerpf(pr * 0.25, pr * 0.8, float(posmod(h / 3600, 1000)) / 1000.0)


static func forget_places() -> void:
	_places.clear()


static func _places_of(s: Dictionary) -> Dictionary:
	var sid := int(s["id"])
	if _places.has(sid):
		return _places[sid]
	var c: Vector2 = s["pos"]
	var plan: Dictionary = s.get("plan", {})
	var pr := float(plan.get("plaza_r", float(s.get("radius", 40.0)) * 0.2))
	var out := {"inn": c + Vector2(pr * 0.7, 0.0), "inn_face": Vector2.RIGHT, "temple": c + Vector2(0.0, pr * 0.7),
		"temple_face": Vector2.DOWN, "train": c + Vector2(-pr * 1.1, pr * 0.4), "train_axis": Vector2.RIGHT, "plaza_r": pr}
	var found_inn := false
	var found_temple := false
	for lot: Dictionary in plan.get("lots", []):
		var asset := String(lot.get("asset", ""))
		var yaw: float = lot["yaw"]
		var face := Vector2(sin(yaw), cos(yaw))
		if asset == "inn" and not found_inn:
			found_inn = true
			out["inn"] = (lot["pos"] as Vector2) + face * 4.6
			out["inn_face"] = face
		elif (asset == "temple" or asset == "chapel") and not found_temple:
			found_temple = true
			out["temple"] = (lot["pos"] as Vector2) + face * 5.0
			out["temple_face"] = face
	if not found_temple:
		for lm: Dictionary in plan.get("landmarks", []):
			var a2 := String(lm.get("asset", ""))
			if a2 == "temple" or a2 == "bell_tower" or a2 == "chapel":
				var yaw2: float = lm["yaw"]
				var f2 := Vector2(sin(yaw2), cos(yaw2))
				out["temple"] = (lm["pos"] as Vector2) + f2 * 6.0
				out["temple_face"] = f2
				break
	var gates: Array = plan.get("gates", [])
	if not gates.is_empty():
		var wall_r := float(plan.get("wall_radius", float(s.get("radius", 40.0)) * 0.95))
		var dir := Vector2(cos(float(gates[0])), sin(float(gates[0])))
		out["train"] = c + dir * (wall_r - 16.0) + Vector2(-dir.y, dir.x) * 8.0
		out["train_axis"] = Vector2(-dir.y, dir.x)
	_places[sid] = out
	return out
