extends RefCounted
## Utility AI for embodied villagers: every few tenths of a second (never per
## frame) each action is scored as the product of its considerations, and the
## best one becomes the villager's next goal, which villager.gd carries out
## along the street graph.
##
## Design after two MIT utility-AI addons for Godot (see CREDITS.md):
##  - John Pennycook's godot-utility-ai: considerations map an input through a
##    response curve (binary, linear, exponential, logistic) and a behaviour
##    aggregates them (product by default); pick the best-scoring option.
##  - Vinicius Gerevini's godot-utility-ai: an agent owns actions, each with
##    considerations, multiplied together; the top action is handed to the
##    game to execute.
## Reimplemented lean: no nodes or resources, just a const table of actions and
## pure static scoring over a Dictionary of 0..1 inputs, so scores are
## deterministic and cheap (13 actions x ~5 considerations per decision).
## Product aggregation uses the compensation factor from Dave Mark / Rez Graham
## ("An Introduction to Utility Theory", Game AI Pro ch. 9) so actions with more
## considerations aren't punished for having them.
##
## Inputs come from: the time of day on the person's own staggered clock
## (DailyRhythm, kept as the baseline schedule consideration), their career
## shift, a seeded personality (sociable, lazy, pious, greedy), needs that
## decay with game time (food, rest, company, faith, household water), rain,
## nearby hostiles and anything noteworthy the player is doing.
##
## Unembodied residents never create a brain; they keep WorldSim's schedule.

const StreetGraph := preload("res://scripts/population/street_graph.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")
const RANeedsScript := preload("res://scripts/sim/needs.gd")

enum Act { SLEEP, HOME, EAT, WORK, SHOP, SOCIAL, INN, PRAY, WATER, SHELTER, FLEE, WATCH, IDLE }
const NAMES := ["sleep", "home", "eat", "work", "shop", "socialise", "inn", "pray", "water", "shelter", "flee", "watch", "idle"]

## Response curves (Pennycook's set plus a remap):
##  BINARY    x >= a ? 1 : b             (b is the floor below the threshold)
##  LINEAR    a * x + b
##  EXP       pow(x, a) + b
##  LOGISTIC  1 / (1 + exp(-a * (x - b)))
##  RANGE     lerp(a, b, x)              (a at x = 0, b at x = 1)
## Every curve is clamped to 0..1.
enum Resp { BINARY, LINEAR, EXP, LOGISTIC, RANGE }

## Action -> [weight, [[input, curve, a, b], ...]]. Score = weight x product.
const ACTIONS := {
	Act.SLEEP: [1.0, [["night", Resp.RANGE, 0.0, 1.0], ["tired", Resp.RANGE, 0.35, 1.0],
		["lazy", Resp.RANGE, 0.85, 1.0]]],
	# Evening at home (DailyRhythm's HOME baseline) when nothing else calls.
	Act.HOME: [0.36, [["sched_home", Resp.RANGE, 0.05, 1.0], ["night", Resp.RANGE, 1.0, 0.3]]],
	Act.EAT: [0.9, [["hungry", Resp.LOGISTIC, 10.0, 0.5], ["meal", Resp.RANGE, 0.35, 1.0]]],
	Act.WORK: [0.8, [["sched_work", Resp.RANGE, 0.03, 1.0], ["lazy", Resp.RANGE, 1.0, 0.6],
		["greedy", Resp.RANGE, 0.8, 1.0], ["rest", Resp.LOGISTIC, 12.0, 0.15],
		["rain_exposed", Resp.RANGE, 1.0, 0.35]]],
	Act.SHOP: [0.6, [["sched_market", Resp.RANGE, 0.12, 1.0], ["market_open", Resp.BINARY, 0.5, 0.0],
		["money", Resp.RANGE, 0.2, 1.0], ["greedy", Resp.RANGE, 1.0, 0.6]]],
	Act.SOCIAL: [0.55, [["lonely", Resp.LOGISTIC, 8.0, 0.45], ["sociable", Resp.RANGE, 0.2, 1.0],
		["daytime", Resp.BINARY, 0.5, 0.0], ["partner", Resp.RANGE, 0.6, 1.0],
		["sched_work", Resp.RANGE, 1.0, 0.35]]],
	Act.INN: [0.8, [["evening", Resp.RANGE, 0.0, 1.0], ["sociable", Resp.RANGE, 0.25, 1.0],
		["sched_inn", Resp.RANGE, 0.55, 1.0], ["money", Resp.RANGE, 0.3, 1.0],
		["lonely", Resp.RANGE, 0.6, 1.0], ["guard", Resp.RANGE, 1.0, 0.0]]],
	Act.PRAY: [0.6, [["pious", Resp.EXP, 1.5, 0.0], ["faithless", Resp.LOGISTIC, 8.0, 0.4],
		["daytime", Resp.BINARY, 0.5, 0.0], ["holy_day", Resp.RANGE, 0.75, 1.0],
		["sched_work", Resp.RANGE, 1.0, 0.5]]],
	Act.WATER: [0.5, [["thirst", Resp.LOGISTIC, 9.0, 0.5], ["chores", Resp.RANGE, 0.25, 1.0],
		["lazy", Resp.RANGE, 1.0, 0.6], ["daytime", Resp.BINARY, 0.5, 0.0]]],
	Act.SHELTER: [0.95, [["rain", Resp.BINARY, 0.5, 0.0], ["night", Resp.RANGE, 1.0, 0.0],
		["guard", Resp.RANGE, 1.0, 0.3]]],
	Act.FLEE: [1.6, [["danger", Resp.LOGISTIC, 12.0, 0.35], ["guard", Resp.RANGE, 1.0, 0.25]]],
	Act.WATCH: [0.9, [["spectacle", Resp.LOGISTIC, 10.0, 0.4], ["sociable", Resp.RANGE, 0.5, 1.0],
		["danger", Resp.RANGE, 1.0, 0.0]]],
	Act.IDLE: [0.05, []],
}

## Acts carried out indoors: the villager walks to the door and goes inside.
const INDOOR := [Act.SLEEP, Act.HOME, Act.EAT]
## Acts that may break a commitment at once (they get the current act's bonus too).
const URGENT := [Act.FLEE, Act.SHELTER]
## Score bonus for the current act: while still committed (just arrived) and after.
const COMMIT_BONUS := 1.45
const KEEP_BONUS := 1.15

## Needs, per game hour. Rest uses the player's RANeeds rates (0..100 -> 0..1).
const FATIGUE_PER_HOUR := RANeedsScript.FATIGUE_PER_HOUR / 100.0
const SLEEP_PER_HOUR := RANeedsScript.SLEEP_PER_HOUR / 100.0
const HUNGER_PER_HOUR := 0.11
const WATER_PER_HOUR := 0.09
## Restored per game hour while performing an act at its spot: [need, amount].
const RESTORE := {
	Act.SLEEP: [["rest", SLEEP_PER_HOUR]], Act.HOME: [["rest", 0.03]],
	Act.EAT: [["food", 2.5]], Act.SOCIAL: [["social", 1.5]],
	Act.INN: [["social", 1.0], ["food", 0.6]], Act.PRAY: [["faith", 1.6]],
	Act.WATER: [["water", 2.2]],
}
const MEALS := [7.0, 12.5, 18.5]

## Sensing ranges, metres.
const DANGER_NEAR := 5.0
const DANGER_FAR := 22.0
const FIGHT_NOTICE := 10.0      # a hostile this close to the player is a fight worth watching
const WATCH_RANGE := 32.0
const SENSE_INTERVAL_MS := 500
const THREAT_RAY_BUDGET := 4
const THREAT_RAY_WINDOW_MS := 500
const LAST_SEEN_SECONDS := 3.0
const SIGHT_QUEUE_MAX := 64
const NOTICE_MAX := 64
const NOTICE_MERGE_RADIUS := 1.0
const NOTICE_MAX_SECONDS := 30.0
const CHAT_GAP := 1.3           # metres between two people chatting

# ---------------------------------------------------------------- shared state
static var _hazards := PackedVector2Array()
## The cached team1 scan keeps only [world position, instance id] samples.
static var _threat_samples: Array = []
static var _sense_ms := -100000
static var _ray_window_ms := -100000
static var _rays_used := 0
## FIFO requests and short lived per-viewer result mailboxes. Queue entries hold
## WeakRefs only; instance IDs are used solely to match/prune entries.
static var _sight_queue: Array[Dictionary] = []
static var _sight_mail: Dictionary = {}
static var _sight_stats := {"queued": 0, "dropped": 0, "unknown": 0,
	"max_wait_ms": 0, "expired": 0}
static var _sight_stats_by_observer: Dictionary = {}
static var _last_sight_target: Dictionary = {}
static var _ray_window_stats := {"requested": 0, "admitted": 0, "exhausted": 0,
	"occluded": 0, "visible": 0, "stale": 0, "unavailable": 0}
static var _ray_total_stats := {"requested": 0, "admitted": 0, "exhausted": 0,
	"occluded": 0, "visible": 0, "stale": 0, "unavailable": 0}
static var _notices: Array = []              # [pos: Vector2, strength, expires_ms]
static var _weather: Node
static var _poi := {}                        # settlement id -> Dictionary
static var _bodies := {}                     # person -> instance id of its Villager
static var _chat_wait := {}                  # settlement id -> [person, spot]
static var _chat_partner := {}               # person -> partner person

# ---------------------------------------------------------------- per person
var person := -1
var traits := {}
var food := 0.8
var rest := 0.9
var social := 0.6
var faith := 0.6
var water := 0.6
var act := -1
var job := 4
## Career shift hours (x..y) when the person holds a seat in a career org, else (-1, -1).
var shift := Vector2(-1, -1)
var org_id := ""
var _last_hours := -1.0
## One short-lived, anonymous last-seen point. This is not persistent identity.
var _last_seen := Vector2.INF
var _last_seen_ms := -100000
var _last_seen_strength := 0.0
var _sight_observer_ref: WeakRef


func _init(p: int = -1, p_job := 4, org_shift := Vector2(-1, -1), p_org := "") -> void:
	person = p
	job = p_job
	shift = org_shift
	org_id = p_org
	traits = personality(p)


# ================================================================ scoring (pure)
static func curve(kind: int, x: float, a: float, b: float) -> float:
	var y := 0.0
	match kind:
		Resp.BINARY: y = 1.0 if x >= a else b
		Resp.LINEAR: y = a * x + b
		Resp.EXP: y = pow(maxf(x, 0.0), a) + b
		Resp.LOGISTIC: y = 1.0 / (1.0 + exp(-a * (x - b)))
		Resp.RANGE: y = lerpf(a, b, clampf(x, 0.0, 1.0))
	return clampf(y, 0.0, 1.0)


## Utility of `action` for inputs `ctx` (missing inputs read 0).
static func score(action: int, ctx: Dictionary) -> float:
	var def: Array = ACTIONS[action]
	var cons: Array = def[1]
	var total: float = def[0]
	if cons.is_empty():
		return total
	var mod := 1.0 - 1.0 / float(cons.size())
	for c: Array in cons:
		var s := curve(c[1], float(ctx.get(c[0], 0.0)), c[2], c[3])
		if s <= 0.0:
			return 0.0
		total *= s + (1.0 - s) * mod * s
	return total


static func scores(ctx: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(NAMES.size())
	for a: int in ACTIONS:
		out[a] = score(a, ctx)
	return out


## Best act for `ctx`. The current act gets `bonus` (commitment); urgent acts
## compete without it. Ties go to the lower act index (deterministic).
static func best(ctx: Dictionary, current := -1, bonus := 1.0) -> int:
	var s := scores(ctx)
	var pick := Act.IDLE
	var top := -1.0
	for a in s.size():
		var v := s[a]
		# Urgent acts share the bonus, so a commitment never blocks them.
		if a == current or a in URGENT:
			v *= bonus
		if v > top:
			top = v
			pick = a
	return pick


## Seeded personality, stable for life: four traits in 0..1.
static func personality(p: int) -> Dictionary:
	var out := {}
	var k := 0
	for t: String in ["sociable", "lazy", "pious", "greedy"]:
		# Sum of two draws: traits cluster around the middle, extremes are rarer.
		var h1 := hash(p * 2246822519 + k * 3266489917 + 1066)
		var h2 := hash(p * 668265263 + k * 374761393 + 7)
		out[t] = (float(h1 % 1000) + float(h2 % 1000)) / 1998.0
		k += 1
	return out


static func _bell(h: float, centre: float, width: float) -> float:
	var d := absf(wrapf(h - centre, -12.0, 12.0))
	return 1.0 - smoothstep(0.0, width, d)


## Time-of-day inputs for hour `h` (the person's own clock).
static func time_inputs(h: float, lazy := 0.5) -> Dictionary:
	var wake := 5.5 + lazy * 1.2
	var night := maxf(smoothstep(20.5, 22.5, h), 1.0 - smoothstep(wake - 0.5, wake + 1.0, h))
	var meal := 0.0
	for m: float in MEALS:
		meal = maxf(meal, _bell(h, m, 1.1))
	return {
		"hour": h, "night": night, "meal": meal,
		"evening": smoothstep(18.0, 19.5, h) * (1.0 - smoothstep(22.5, 23.5, h)),
		"market_open": 1.0 if h >= 8.0 and h < 19.0 else 0.0,
		"daytime": 1.0 if h >= 7.0 and h < 20.5 else 0.0,
		"chores": maxf(_bell(h, 7.5, 1.8), _bell(h, 17.0, 1.5)),
	}


## A complete input set with neutral defaults, overridden by `over`. Tests and
## tools build contexts with this; villagers use context().
static func make_context(hour: float, over: Dictionary = {}, p_traits: Dictionary = {}) -> Dictionary:
	var tr := {"sociable": 0.5, "lazy": 0.5, "pious": 0.5, "greedy": 0.5}
	tr.merge(p_traits, true)
	var ctx := time_inputs(hour, tr["lazy"])
	ctx.merge(tr, true)
	var st := DailyRhythm.phase_at(4, hour)
	ctx.merge({"sched_home": 1.0 if st == 0 else 0.0, "sched_work": 1.0 if st == 1 else 0.0,
		"sched_market": 1.0 if st == 2 else 0.0, "sched_inn": 0.0,
		"tired": 0.3, "rest": 0.7, "hungry": 0.3, "lonely": 0.4, "faithless": 0.3, "thirst": 0.2,
		"money": 0.5, "rain": 0.0, "rain_exposed": 0.0, "danger": 0.0, "spectacle": 0.0,
		"partner": 0.0, "guard": 0.0, "holy_day": 0.0}, true)
	ctx.merge(over, true)
	return ctx


# ================================================================ per-person needs
## Plausible needs for someone met at hour `h`: rest from hours awake, food
## from the last mealtime, the rest seeded per person and day.
func seed_needs(h: float, day := 1) -> void:
	var wake := 5.5 + float(traits["lazy"]) * 1.2
	var awake := h - wake if h >= wake else 0.0
	rest = clampf(1.0 - awake * FATIGUE_PER_HOUR, 0.05, 1.0)
	var since := 24.0
	for m: float in MEALS:
		if h >= m + 0.5:
			since = h - m - 0.5
	if since >= 24.0:
		# Before breakfast: supper was at 19:00 and hunger runs at half rate asleep.
		since = (h + 5.0) * 0.5
	food = clampf(1.0 - since * HUNGER_PER_HOUR, 0.1, 1.0)
	var r := hash(person * 40503 + day * 9973)
	social = 0.35 + float(r % 100) / 160.0
	faith = 0.3 + float((r / 100) % 100) / 150.0
	water = 0.3 + float((r / 10000) % 100) / 140.0
	_last_hours = -1.0


## Compact LOD/save boundary in stable order: food, rest, social, faith, water.
func export_needs() -> PackedFloat32Array:
	return PackedFloat32Array([food, rest, social, faith, water])


func import_needs(values: PackedFloat32Array, last_hours: float) -> bool:
	if values.size() != 5 or not is_finite(last_hours):
		return false
	for value: float in values:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	food = values[0]
	rest = values[1]
	social = values[2]
	faith = values[3]
	water = values[4]
	_last_hours = last_hours
	return true


## Advance needs to absolute game time `now_hours` (day * 24 + time). While
## `performing` an act at its spot, that act restores its need.
func tick(now_hours: float, performing := -1, elapsed_cap := 2.0) -> void:
	if _last_hours < 0.0:
		_last_hours = now_hours
		return
	var dt := clampf(now_hours - _last_hours, 0.0, maxf(0.0, elapsed_cap))
	_last_hours = now_hours
	if dt <= 0.0:
		return
	var asleep := performing == Act.SLEEP
	food -= HUNGER_PER_HOUR * dt * (0.5 if asleep else 1.0)
	if not asleep:
		rest -= FATIGUE_PER_HOUR * dt
	social -= (0.05 + 0.08 * float(traits["sociable"])) * dt
	faith -= (0.02 + 0.05 * float(traits["pious"])) * dt
	water -= WATER_PER_HOUR * dt
	if RESTORE.has(performing):
		for r: Array in RESTORE[performing]:
			set(r[0], float(get(r[0])) + float(r[1]) * dt)
	food = clampf(food, 0.0, 1.0)
	rest = clampf(rest, 0.0, 1.0)
	social = clampf(social, 0.0, 1.0)
	faith = clampf(faith, 0.0, 1.0)
	water = clampf(water, 0.0, 1.0)


## Bring data-tier needs current in one constant-cost step after an NPC spent time
## unembodied. The need model is linear between decisions, so no per-hour loop is
## needed; it intentionally assumes no unobserved activity restored a need.
func catch_up(now_hours: float) -> void:
	var elapsed := maxf(0.0, now_hours - _last_hours) if _last_hours >= 0.0 else 0.0
	tick(now_hours, -1, elapsed)


## Inputs for this person now. `hour` is their own clock, `sched` DailyRhythm's
## state for them (the baseline), the rest sensed by the villager.
func context(hour: float, sched: int, raining: bool, danger: float, spectacle: float,
		partner: bool, money_frac: float, day := 1) -> Dictionary:
	var ctx := time_inputs(hour, traits["lazy"])
	ctx.merge(traits, true)
	var on_shift := sched == DailyRhythm.State.WORK
	if shift.x >= 0.0:
		on_shift = hour >= shift.x and hour < shift.y
	var outdoor := job == 0 or job == 3 or job == 4 or job == 5
	var guard := 1.0 if job == 3 else 0.0
	var rain := 1.0 if raining else 0.0
	ctx.merge({
		"sched_home": 1.0 if sched == DailyRhythm.State.HOME else 0.0,
		"sched_work": 1.0 if on_shift else 0.0,
		"sched_market": 1.0 if sched == DailyRhythm.State.MARKET else 0.0,
		"sched_inn": 1.0 if sched == DailyRhythm.State.INN else 0.0,
		"tired": 1.0 - rest, "rest": rest, "hungry": 1.0 - food, "lonely": 1.0 - social,
		"faithless": 1.0 - faith, "thirst": 1.0 - water, "money": clampf(money_frac, 0.0, 1.0),
		"rain": rain, "rain_exposed": rain * (1.0 if outdoor else 0.0) * (1.0 - guard),
		"danger": danger, "spectacle": spectacle, "partner": 1.0 if partner else 0.0,
		"guard": guard, "holy_day": 1.0 if day % 7 == 0 else 0.0,
	}, true)
	return ctx


## Choose the next act; `committed` while the current act has only just begun.
func decide(ctx: Dictionary, committed: bool) -> int:
	act = best(ctx, act, COMMIT_BONUS if committed else KEEP_BONUS)
	return act


# ================================================================ sensing (shared, cached)
## Hostile combatants' positions, refreshed at most every SENSE_INTERVAL_MS
## for all villagers together.
static func hazards(tree: SceneTree) -> PackedVector2Array:
	var now := Time.get_ticks_msec()
	if now - _sense_ms < SENSE_INTERVAL_MS or tree == null:
		return _hazards
	_sense_ms = now
	_hazards = PackedVector2Array()
	_threat_samples.clear()
	for n in tree.get_nodes_in_group("team1"):
		var body := n as Node3D
		if body == null or not body.is_in_group("combatant") or body.get("dead") == true:
			continue
		var pos := body.global_position
		_hazards.append(Vector2(pos.x, pos.z))
		_threat_samples.append([pos, body.get_instance_id()])
	return _hazards


## Ambient 360-degree line-of-sight sensing; no facing cone is modeled.
## Selects up to two candidates within WATCH_RANGE in one O(n) pass, without
## copying or sorting the shared cache. Ray results can be unknown when budget
## is exhausted; unknown candidates never count as visible.
func sense_threats(viewer: Node3D, tree: SceneTree, world_layer: int) -> Dictionary:
	var out := {"visible": PackedVector2Array(), "observed_ms": -1}
	if viewer == null or tree == null:
		return out
	_sight_observer_ref = weakref(viewer)
	hazards(tree)
	var now := Time.get_ticks_msec()
	if now - _ray_window_ms >= THREAT_RAY_WINDOW_MS:
		_ray_window_ms = now
		_rays_used = 0
		_reset_ray_window_stats()
	_prune_sight_queue(now)
	var eye := viewer.global_position + Vector3.UP * 1.4
	var nearest: Array = [] # [distance_squared, target instance id]
	var range_squared := WATCH_RANGE * WATCH_RANGE
	for sample: Array in _threat_samples:
		var target_id := int(sample[1])
		if not is_instance_id_valid(target_id):
			continue
		var target_node := instance_from_id(target_id) as Node3D
		if target_node == null:
			continue
		var target: Vector3 = target_node.global_position
		var dx := target.x - eye.x
		var dz := target.z - eye.z
		var distance_squared := dx * dx + dz * dz
		if distance_squared > range_squared:
			continue
		var entry := [distance_squared, int(sample[1])]
		if nearest.is_empty() or distance_squared < float(nearest[0][0]):
			nearest.push_front(entry)
		elif nearest.size() < 2:
			nearest.append(entry)
		elif distance_squared < float(nearest[1][0]):
			nearest[1] = entry
		if nearest.size() > 2:
			nearest.resize(2)
	# New requests join the tail. Refreshing an existing pair does not change age.
	# Keep one pending request per observer. Alternate between the two nearest
	# candidates after each completed request so a nearer repeat cannot monopolize.
	if not nearest.is_empty():
		var last_target: int = int(_last_sight_target.get(viewer.get_instance_id(), -1))
		var selected: int = int(nearest[0][1])
		if nearest.size() > 1 and selected == last_target:
			selected = int(nearest[1][1])
		_enqueue_sight(viewer, selected, world_layer, now)
	# Any observer decision may service the oldest eligible work using that
	# request's own world and current positions. Each admitted request costs 1 ray.
	while _rays_used < THREAT_RAY_BUDGET and not _sight_queue.is_empty():
		_process_oldest_sight(now)
	for request: Dictionary in _sight_queue:
		var ref: WeakRef = request["viewer"]
		if ref.get_ref() == viewer:
			_sight_stats["unknown"] = int(_sight_stats["unknown"]) + 1
			var observer_stats: Dictionary = _observer_sight_stats(viewer.get_instance_id())
			observer_stats["unknown"] = int(observer_stats["unknown"]) + 1
			break
	# Consume only this observer's mailbox. Delayed packets retain ray-time.
	var viewer_id := viewer.get_instance_id()
	if _sight_mail.has(viewer_id):
		var mail: Dictionary = _sight_mail[viewer_id]
		var mail_viewer: WeakRef = mail["viewer"]
		if mail_viewer.get_ref() == viewer:
			var observed_ms: int = int(mail["observed_ms"])
			if now - observed_ms <= int(LAST_SEEN_SECONDS * 1000.0):
				out["remembered"] = mail["visible"]
				out["observed_ms"] = observed_ms
				if now - observed_ms <= THREAT_RAY_WINDOW_MS:
					out["visible"] = mail["visible"]
		_sight_mail.erase(viewer_id)
	return out


static func _enqueue_sight(viewer: Node3D, target_id: int, world_layer: int, now: int) -> void:
	for request: Dictionary in _sight_queue:
		var observer_ref: WeakRef = request["viewer"]
		if observer_ref.get_ref() == viewer:
			request["world_layer"] = world_layer
			if is_instance_id_valid(target_id):
				var refreshed_target := instance_from_id(target_id) as Node3D
				if refreshed_target != null:
					request["target"] = weakref(refreshed_target)
					request["target_id"] = target_id
					request["last_refresh_ms"] = now
			return # age is intentionally preserved
	if _sight_queue.size() >= SIGHT_QUEUE_MAX:
		_sight_stats["dropped"] = int(_sight_stats["dropped"]) + 1
		var observer_stats: Dictionary = _observer_sight_stats(viewer.get_instance_id())
		observer_stats["dropped"] = int(observer_stats["dropped"]) + 1
		_record_ray_stat("exhausted")
		return
	if not is_instance_id_valid(target_id):
		return
	var target := instance_from_id(target_id) as Node3D
	if target == null:
		return
	_sight_queue.append({"viewer": weakref(viewer), "viewer_id": viewer.get_instance_id(),
		"target": weakref(target), "target_id": target_id, "world_layer": world_layer,
		"enqueued_ms": now, "last_refresh_ms": now})
	_sight_stats["queued"] = int(_sight_stats["queued"]) + 1
	var observer_stats: Dictionary = _observer_sight_stats(viewer.get_instance_id())
	observer_stats["queued"] = int(observer_stats["queued"]) + 1
	_record_ray_stat("requested")


static func _prune_sight_queue(now: int) -> void:
	for i in range(_sight_queue.size() - 1, -1, -1):
		var request: Dictionary = _sight_queue[i]
		var viewer_ref: WeakRef = request["viewer"]
		var target_ref: WeakRef = request["target"]
		if viewer_ref.get_ref() == null or target_ref.get_ref() == null or now - int(request["last_refresh_ms"]) > 3000:
			if now - int(request["last_refresh_ms"]) > 3000:
				_sight_stats["expired"] = int(_sight_stats["expired"]) + 1
			_sight_queue.remove_at(i)
	for viewer_id in _sight_mail.keys():
		var mail: Dictionary = _sight_mail[viewer_id]
		var ref: WeakRef = mail["viewer"]
		if ref.get_ref() == null or now - int(mail["observed_ms"]) > 3000:
			_sight_mail.erase(viewer_id)
	for viewer_id in _sight_stats_by_observer.keys():
		if not is_instance_id_valid(int(viewer_id)):
			_sight_stats_by_observer.erase(viewer_id)
			_last_sight_target.erase(viewer_id)


static func _process_oldest_sight(now: int) -> void:
	if _sight_queue.is_empty():
		return
	var request: Dictionary = _sight_queue.pop_front()
	var wait_ms := now - int(request["enqueued_ms"])
	_sight_stats["max_wait_ms"] = maxi(int(_sight_stats["max_wait_ms"]), wait_ms)
	var observer_stats: Dictionary = _observer_sight_stats(int(request["viewer_id"]))
	_last_sight_target[int(request["viewer_id"])] = int(request["target_id"])
	observer_stats["max_wait_ms"] = maxi(int(observer_stats["max_wait_ms"]), wait_ms)
	var viewer_ref: WeakRef = request["viewer"]
	var target_ref: WeakRef = request["target"]
	var viewer := viewer_ref.get_ref() as Node3D
	var body := target_ref.get_ref() as Node3D
	if viewer == null or body == null or not body.is_in_group("combatant") or body.get("dead") == true:
		_record_ray_stat("stale")
		return
	if not viewer.is_inside_tree() or not body.is_inside_tree() or viewer.get_world_3d() == null or viewer.get_world_3d() != body.get_world_3d() or viewer.get("_indoors") == true:
		_record_ray_stat("unavailable")
		return
	var eye := viewer.global_position + Vector3.UP * 1.4
	var target := body.global_position
	var dx := target.x - eye.x
	var dz := target.z - eye.z
	if dx * dx + dz * dz > WATCH_RANGE * WATCH_RANGE:
		_record_ray_stat("stale")
		return
	var viewer_body := viewer as CollisionObject3D
	var viewer_rid := viewer_body.get_rid() if viewer_body != null else RID()
	var space := viewer.get_world_3d().direct_space_state
	if space == null or not viewer_rid.is_valid():
		_record_ray_stat("unavailable")
		return
	var query := PhysicsRayQueryParameters3D.create(eye, target + Vector3.UP * 0.9, int(request["world_layer"]))
	query.exclude = [viewer_rid]
	_rays_used += 1
	_record_ray_stat("admitted")
	var hit := space.intersect_ray(query)
	var observer_id: int = int(request["viewer_id"])
	if hit.is_empty():
		var mail: Dictionary = _sight_mail.get(observer_id, {"viewer": viewer_ref, "visible": PackedVector2Array(), "observed_ms": now})
		var mail_ref: WeakRef = mail["viewer"]
		if mail_ref.get_ref() != viewer or int(mail["observed_ms"]) != now:
			mail = {"viewer": viewer_ref, "visible": PackedVector2Array(), "observed_ms": now}
		(mail["visible"] as PackedVector2Array).append(Vector2(target.x, target.z))
		mail["observed_ms"] = now
		_sight_mail[observer_id] = mail
		while _sight_mail.size() > SIGHT_QUEUE_MAX:
			_sight_mail.erase(_sight_mail.keys()[0])
		observer_stats["visible"] = int(observer_stats.get("visible", 0)) + 1
		_record_ray_stat("visible")
	else:
		_record_ray_stat("occluded")


static func _reset_ray_window_stats() -> void:
	_ray_window_stats = {"requested": 0, "admitted": 0, "exhausted": 0,
		"occluded": 0, "visible": 0, "stale": 0, "unavailable": 0}


static func _record_ray_stat(key: String) -> void:
	_ray_window_stats[key] = int(_ray_window_stats.get(key, 0)) + 1
	_ray_total_stats[key] = int(_ray_total_stats.get(key, 0)) + 1


static func ray_budget_stats() -> Dictionary:
	return {"window": _ray_window_stats.duplicate(), "total": _ray_total_stats.duplicate(),
		"window_ms": THREAT_RAY_WINDOW_MS, "budget": THREAT_RAY_BUDGET,
		"sight": _sight_stats.duplicate(), "sight_by_observer": _sight_stats_by_observer.duplicate(true),
		"queue_depth": _sight_queue.size()}


static func _observer_sight_stats(viewer_id: int) -> Dictionary:
	if not _sight_stats_by_observer.has(viewer_id):
		while _sight_stats_by_observer.size() >= SIGHT_QUEUE_MAX:
			var retired_id: int = int(_sight_stats_by_observer.keys()[0])
			_sight_stats_by_observer.erase(retired_id)
			_last_sight_target.erase(retired_id)
		_sight_stats_by_observer[viewer_id] = {"queued": 0, "dropped": 0, "unknown": 0,
			"visible": 0, "max_wait_ms": 0}
	return _sight_stats_by_observer[viewer_id]


## Resolve immediate visible danger plus the decaying last-seen point. A hidden
## hostile always uses its remembered position, never its current live position.
func remembered_danger(here: Vector2, visible: PackedVector2Array, observed_ms := -1) -> Array:
	var now := Time.get_ticks_msec()
	var observation_ms := now if observed_ms < 0 else observed_ms
	var immediate := visible if now - observation_ms <= THREAT_RAY_WINDOW_MS else PackedVector2Array()
	if not visible.is_empty() and now - observation_ms < int(LAST_SEEN_SECONDS * 1000.0):
		var seen: Array = danger_at(here, visible)
		if observation_ms > _last_seen_ms:
			_last_seen = seen[1]
			_last_seen_ms = observation_ms
			_last_seen_strength = float(seen[0])
	var age := float(now - _last_seen_ms) / 1000.0
	if _last_seen != Vector2.INF and age < LAST_SEEN_SECONDS:
		var remembered := danger_at(here, PackedVector2Array([_last_seen]))
		var memory_strength := minf(float(remembered[0]), _last_seen_strength) * (1.0 - age / LAST_SEEN_SECONDS)
		if memory_strength > float(visible_danger(here, immediate)[0]):
			return [memory_strength, _last_seen]
	if _last_seen != Vector2.INF and age >= LAST_SEEN_SECONDS:
		clear_threat_memory()
	return visible_danger(here, immediate)


static func visible_danger(here: Vector2, visible: PackedVector2Array) -> Array:
	return danger_at(here, visible)


func clear_threat_memory() -> void:
	_last_seen = Vector2.INF
	_last_seen_ms = -100000
	_last_seen_strength = 0.0
	if _sight_observer_ref != null:
		var observer := _sight_observer_ref.get_ref() as Node3D
		if observer != null:
			clear_sight_for(observer)
		_sight_observer_ref = null


## Remove queued work and mailbox data when this observer is reset or indoors.
static func clear_sight_for(viewer: Node3D) -> void:
	if viewer == null:
		return
	var viewer_id := viewer.get_instance_id()
	_sight_mail.erase(viewer_id)
	_sight_stats_by_observer.erase(viewer_id)
	_last_sight_target.erase(viewer_id)
	for i in range(_sight_queue.size() - 1, -1, -1):
		var ref: WeakRef = _sight_queue[i]["viewer"]
		if ref.get_ref() == viewer:
			_sight_queue.remove_at(i)


## 0..1 danger at `here` and the nearest hazard (Vector2.INF when none).
static func danger_at(here: Vector2, list: PackedVector2Array) -> Array:
	var best_d := INF
	var at := Vector2.INF
	for h in list:
		var d := here.distance_squared_to(h)
		if d < best_d:
			best_d = d
			at = h
	if at == Vector2.INF:
		return [0.0, at]
	return [1.0 - smoothstep(DANGER_NEAR, DANGER_FAR, sqrt(best_d)), at]


## Add a short-lived, anonymous spectacle for nearby villagers. This is an
## explicit stimulus, not sight/hearing evidence; callers should only publish
## conspicuous events. Coalesce same-place bursts and hard-cap shared storage.
static func notice(pos: Vector2, strength: float = 1.0, seconds: float = 8.0) -> void:
	if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(strength) or not is_finite(seconds):
		return
	var now := Time.get_ticks_msec()
	for i in range(_notices.size() - 1, -1, -1):
		if int(_notices[i][2]) <= now:
			_notices.remove_at(i)
	var level := clampf(strength, 0.0, 1.0)
	var duration := clampf(seconds, 0.0, NOTICE_MAX_SECONDS)
	if level <= 0.0 or duration <= 0.0:
		return
	var expires := now + int(duration * 1000.0)
	for n: Array in _notices:
		var notice_pos: Vector2 = n[0]
		if notice_pos.distance_squared_to(pos) <= NOTICE_MERGE_RADIUS * NOTICE_MERGE_RADIUS:
			n[1] = maxf(float(n[1]), level)
			n[2] = maxi(int(n[2]), expires)
			return
	if _notices.size() >= NOTICE_MAX:
		_notices.pop_front()
	_notices.append([pos, level, expires])


## 0..1 interest at `here`, and where to look (Vector2.INF when nothing).
## A fight near the player counts on its own.
static func spectacle_at(here: Vector2, player_pos: Vector2, list: PackedVector2Array) -> Array:
	var now := Time.get_ticks_msec()
	var top := 0.0
	var at := Vector2.INF
	for i in range(_notices.size() - 1, -1, -1):
		var n: Array = _notices[i]
		if int(n[2]) < now:
			_notices.remove_at(i)
			continue
		var v: float = float(n[1]) * (1.0 - clampf(here.distance_to(n[0]) / WATCH_RANGE, 0.0, 1.0))
		if v > top:
			top = v
			at = n[0]
	if player_pos != Vector2.INF:
		for h in list:
			if h.distance_squared_to(player_pos) < FIGHT_NOTICE * FIGHT_NOTICE:
				var v := 1.0 - clampf(here.distance_to(player_pos) / WATCH_RANGE, 0.0, 1.0)
				if v > top:
					top = v
					at = player_pos
				break
	return [top, at]


## Weakly localize the player's current movement noise for nearby outdoor
## villagers. This is a cheap range cue, not identity, line of sight or combat
## evidence; uncertainty deliberately biases the investigation point inward.
static func heard_player_at(here: Vector2, player: Node3D, tree: SceneTree) -> Array:
	if player == null or not is_instance_valid(player) or player.get("dead") == true \
	or not player.has_method("noise_radius"):
		return [0.0, Vector2.INF]
	var velocity: Vector3 = player.get("velocity")
	if velocity.length_squared() < 0.1225:
		return [0.0, Vector2.INF]
	var radius := clampf(float(player.call("noise_radius")), 0.0, 18.0)
	if radius <= 0.0:
		return [0.0, Vector2.INF]
	if _weather == null or not is_instance_valid(_weather):
		_weather = tree.get_first_node_in_group("weather") if tree else null
	if _weather and is_instance_valid(_weather) and _weather.has_method("noise_mult"):
		radius *= clampf(float(_weather.call("noise_mult")), 0.4, 1.0)
	var source := Vector2(player.global_position.x, player.global_position.z)
	var offset := source - here
	var distance := offset.length()
	if distance >= radius:
		return [0.0, Vector2.INF]
	var strength := 1.0 - distance / radius
	var direction := offset / maxf(distance, 0.001)
	var guessed_distance := maxf(distance - lerpf(0.75, 3.0, distance / radius), 0.0)
	return [strength, here + direction * guessed_distance]


static func is_raining(tree: SceneTree) -> bool:
	if _weather == null or not is_instance_valid(_weather):
		_weather = tree.get_first_node_in_group("weather") if tree else null
		if _weather == null:
			return false
	return _weather.has_method("is_raining") and bool(_weather.call("is_raining"))


# ================================================================ bodies and chat pairs
static func register_body(p: int, node: Node) -> void:
	_bodies[p] = node.get_instance_id()


static func unregister_body(p: int, owner_id := 0) -> void:
	# A queued old body can exit after a replacement has registered this person.
	if owner_id != 0 and int(_bodies.get(p, 0)) != owner_id:
		return
	_bodies.erase(p)
	chat_leave(p)


## Save restoration can happen while population bodies remain alive. Restore each
## active brain from the newly loaded WorldSim rows before it can write them back.
static func restore_active_needs() -> void:
	for p in _bodies.keys():
		var body := body_of(int(p))
		if body and body.has_method("restore_needs_from_world"):
			body.call("restore_needs_from_world")


static func body_of(p: int) -> Node3D:
	if not _bodies.has(p):
		return null
	return instance_from_id(_bodies[p]) as Node3D


## Someone in settlement `sid` is standing in the plaza waiting for company.
static func chat_waiting(sid: int, p: int) -> bool:
	if not _chat_wait.has(sid):
		return false
	var w: Array = _chat_wait[sid]
	if w[0] == p:
		return false
	if body_of(w[0]) == null:
		_chat_wait.erase(sid)
		return false
	return true


## Join or start a chat. Returns [goal spot, partner person or -1].
static func chat_join(sid: int, p: int, own_spot: Vector2) -> Array:
	if _chat_partner.has(p):
		return [own_spot, _chat_partner[p]]
	if chat_waiting(sid, p):
		var w: Array = _chat_wait[sid]
		_chat_wait.erase(sid)
		var other: int = w[0]
		var spot: Vector2 = w[1]
		_chat_partner[p] = other
		_chat_partner[other] = p
		var side := own_spot - spot
		if side.length() < 0.1:
			side = Vector2.RIGHT.rotated(float(p) * 2.399)
		return [spot + side.normalized() * CHAT_GAP, other]
	_chat_wait[sid] = [p, own_spot]
	return [own_spot, -1]


static func chat_partner(p: int) -> int:
	var other: int = _chat_partner.get(p, -1)
	if other >= 0 and body_of(other) == null:
		chat_leave(p)
		return -1
	return other


static func chat_leave(p: int) -> void:
	for sid in _chat_wait.keys():
		if _chat_wait[sid][0] == p:
			_chat_wait.erase(sid)
	if _chat_partner.has(p):
		var other: int = _chat_partner[p]
		_chat_partner.erase(p)
		if _chat_partner.get(other, -1) == p:
			_chat_partner.erase(other)


# ================================================================ places (cached per settlement)
## Points of interest of a settlement: well, shrine/temple front, plaza,
## eaves (the front wall of each building) with their outward facing.
static func places(sid: int, graph: StreetGraph) -> Dictionary:
	if _poi.has(sid):
		return _poi[sid]
	var s: Dictionary = WorldGen.settlements[sid]
	var plan: Dictionary = s.get("plan", {})
	var c: Vector2 = s["pos"]
	var out := {"well": Vector2.INF, "shrine": Vector2.INF, "shrine_face": Vector2.ZERO,
		"well_slots": PackedVector2Array(), "water_source": "", "plaza": c,
		"plaza_r": float(plan.get("plaza_r", 12.0)),
		"eaves": PackedVector2Array(), "eaves_face": PackedVector2Array()}
	for lm: Dictionary in plan.get("landmarks", []):
		var asset := String(lm["asset"])
		var p: Vector2 = lm["pos"]
		var yaw: float = lm["yaw"]
		var face := Vector2(sin(yaw), cos(yaw))
		if asset == "well":
			out["water_source"] = "well"
			var outward := Vector2(1.0, 0.6).normalized()
			out["well"] = _clear(graph, p + outward * 1.6, 0.4)
			var tangent := Vector2(-outward.y, outward.x)
			var slots: PackedVector2Array = out["well_slots"]
			for side in [-1.0, 1.0]:
				var slot := _clear(graph, p + outward * 2.4 + tangent * 0.75 * side, 0.45)
				var separated := true
				for previous in slots:
					if slot.distance_to(previous) < 1.2:
						separated = false
						break
				if separated:
					slots.append(slot)
			out["well_slots"] = slots
		elif (asset == "temple" or asset == "bell_tower" or asset == "chapel") and out["shrine"] == Vector2.INF:
			var spot := p + face * 4.0
			for d: float in [4.0, 6.0, 8.0, 10.0, 12.0, 14.0]:
				spot = p + face * d
				if graph == null or not graph.inside(spot, 0.5):
					break
			out["shrine"] = _clear(graph, spot, 0.45)
			out["shrine_face"] = -face
	if String(out["water_source"]).is_empty():
		# Some fortified plans have no well landmark. Keep thirst behavior by
		# assigning two low-fidelity plaza water-break points instead of making
		# the need impossible to satisfy. This fallback is abstract: it creates no
		# visible vessel, item, gold, XP or other resource.
		out["water_source"] = "plaza_break"
		var fallback_outward := Vector2(1.0, 0.6).normalized()
		var fallback_tangent := Vector2(-fallback_outward.y, fallback_outward.x)
		var radius := maxf(2.5, float(out["plaza_r"]) * 0.45)
		var fallback_slots: PackedVector2Array = out["well_slots"]
		for side in [-1.0, 1.0]:
			var fallback_slot := _clear(graph, c + fallback_outward * radius + fallback_tangent * 0.75 * side, 0.45)
			var fallback_separated := true
			for previous in fallback_slots:
				if fallback_slot.distance_to(previous) < 1.2:
					fallback_separated = false
					break
			if fallback_separated:
				fallback_slots.append(fallback_slot)
		out["well_slots"] = fallback_slots
	for lot: Dictionary in plan.get("lots", []):
		var yaw: float = lot["yaw"]
		var face := Vector2(sin(yaw), cos(yaw))
		(out["eaves"] as PackedVector2Array).append(_clear(graph, (lot["pos"] as Vector2) + face * 3.0, 0.45))
		(out["eaves_face"] as PackedVector2Array).append(face)
	_poi[sid] = out
	return out


static func _clear(graph: StreetGraph, p: Vector2, r: float) -> Vector2:
	return graph.push_out(p, r) if graph else p


## Index of the eaves spot nearest `p` (-1 when none within `reach`).
static func nearest_eaves(pl: Dictionary, p: Vector2, reach := 30.0) -> int:
	var eaves: PackedVector2Array = pl["eaves"]
	var best_i := -1
	var best_d := reach * reach
	for i in eaves.size():
		var d := p.distance_squared_to(eaves[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


## Where person `p` goes to carry out `action`, and how to stand there.
## Returns {goal: Vector2, face: Vector2 (INF = no preference), indoors: bool,
##          partner: int, look: Vector2 (INF = none)}.
func plan_goal(action: int, here: Vector2, graph: StreetGraph, hazard: Vector2, look_at: Vector2) -> Dictionary:
	var sid: int = WorldSim.home[person]
	var s: Dictionary = WorldGen.settlements[sid]
	var pl := places(sid, graph)
	var out := {"goal": here, "face": Vector2.INF, "indoors": false, "partner": -1,
		"look": Vector2.INF, "well_slots": PackedVector2Array(), "water_source": ""}
	var home: Vector2 = WorldSim._spot(s, 0, person)
	var has_home: bool = not (s.get("plan", {}) as Dictionary).get("lots", []).is_empty()
	match action:
		Act.SLEEP, Act.HOME, Act.EAT:
			out["goal"] = home
			out["indoors"] = has_home
		Act.WORK:
			if org_id == "inn":
				out["goal"] = DailyRhythm.goal(person, DailyRhythm.State.INN, graph)
			else:
				out["goal"] = WorldSim._spot(s, 1, person)
				# Craftsmen mostly work inside their shops (WorldSim.is_indoors).
				out["indoors"] = (job == 1 or job == 2) and person % 3 != 0 and has_home
		Act.SHOP:
			out["goal"] = WorldSim._spot(s, 2, person)
			out["face"] = (pl["plaza"] as Vector2) - (out["goal"] as Vector2)
		Act.INN:
			out["goal"] = DailyRhythm.goal(person, DailyRhythm.State.INN, graph)
			if graph and graph.inn_door != Vector2.INF:
				out["face"] = graph.inn_door - (out["goal"] as Vector2)
		Act.SOCIAL:
			var h := hash(person * 9176 + WorldSim.day * 31)
			var ang := float(h % 628) / 100.0
			var own := _clear(graph, (pl["plaza"] as Vector2) + Vector2(cos(ang), sin(ang)) * float(pl["plaza_r"]) * 0.55, 0.45)
			var joined := chat_join(sid, person, own)
			out["goal"] = joined[0]
			out["partner"] = joined[1]
		Act.PRAY:
			if pl["shrine"] != Vector2.INF:
				var h := hash(person * 523 + 3)
				var off := Vector2(float(h % 100) / 100.0 - 0.5, float((h / 100) % 100) / 100.0 - 0.5) * 3.0
				out["goal"] = _clear(graph, (pl["shrine"] as Vector2) + off, 0.45)
				out["face"] = pl["shrine_face"]
			else:
				out["goal"] = (pl["plaza"] as Vector2)
		Act.WATER:
			var well: Vector2 = pl["well"] if pl["well"] != Vector2.INF else pl["plaza"]
			var ang := float(hash(person * 71 + 9) % 628) / 100.0
			out["goal"] = _clear(graph, well + Vector2(cos(ang), sin(ang)) * 0.6, 0.45)
			out["face"] = (s["pos"] as Vector2) - (out["goal"] as Vector2)
			out["well_slots"] = pl["well_slots"]
			out["water_source"] = pl["water_source"]
		Act.SHELTER:
			var e := nearest_eaves(pl, here)
			if has_home and (e < 0 or here.distance_to(home) < here.distance_to((pl["eaves"] as PackedVector2Array)[e]) + 8.0):
				out["goal"] = home
				out["indoors"] = true
			elif e >= 0:
				out["goal"] = (pl["eaves"] as PackedVector2Array)[e]
				out["face"] = (pl["eaves_face"] as PackedVector2Array)[e]
		Act.FLEE:
			var away := (here - hazard).normalized() if hazard != Vector2.INF else Vector2.RIGHT
			if has_home and (home - hazard).length() > (here - hazard).length() + 3.0 and (home - here).dot(away) > 0.0:
				out["goal"] = home
				out["indoors"] = true
			else:
				out["goal"] = _clear(graph, here + away * 20.0, 0.45)
		Act.WATCH:
			if look_at != Vector2.INF:
				var from := here - look_at
				var d := clampf(from.length(), 5.0, 8.0)
				out["goal"] = _clear(graph, look_at + (from.normalized() if from.length() > 0.1 else Vector2.RIGHT) * d, 0.45)
				out["look"] = look_at
	return out


static func label(action: int, travelling: bool) -> String:
	match action:
		Act.SLEEP: return "heading to bed" if travelling else "asleep"
		Act.HOME: return "heading home" if travelling else "at home"
		Act.EAT: return "going home to eat" if travelling else "eating"
		Act.WORK: return "off to work" if travelling else "working"
		Act.SHOP: return "off to market" if travelling else "shopping"
		Act.SOCIAL: return "looking for company" if travelling else "chatting"
		Act.INN: return "off to the inn" if travelling else "at the inn"
		Act.PRAY: return "off to pray" if travelling else "praying"
		Act.WATER: return "fetching water" if travelling else "at the water point"
		Act.SHELTER: return "running from the rain" if travelling else "sheltering"
		Act.FLEE: return "fleeing!" if travelling else "hiding"
		Act.WATCH: return "watching"
	return "idling"
