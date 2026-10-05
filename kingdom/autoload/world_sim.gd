extends Node
## The living world as pure data. Every person exists here as a row in packed
## arrays: no node, no mesh, no physics. The population LOD system gives a
## person a body only while the player is near them.
##
## Scale tiers (see docs/KINGDOM_DESIGN.md):
##   world database  ~20,000 people  (this script, sliced updates)
##   local region    people of settlements near the player
##   visible         ~250 sprite impostors
##   near player     ~24 animated characters

signal hour_changed(hour: int)

const SeasonsScript := preload("res://scripts/sim/seasons.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const TownIdentity := preload("res://scripts/world/town_identity.gd")   # guard density per town
const NeedRules := preload("res://scripts/sim/npc_need_rules.gd")
const ThornfieldRoster := preload("res://scripts/world/thornfield/roster.gd")   # F8: named residents of the slice town

const SEED := 1066
const JOBS := ["Farmer", "Blacksmith", "Merchant", "Guard", "Laborer", "Woodcutter"]
const WAGES := [6, 12, 15, 9, 5, 7]
const WALK_SPEED := 1.3
const NEED_SCHEDULE_BOUNDARIES := [6.0, 21.0, 24.0]
## CPU budget for the whole-world sim per frame, and the radius around the player that is kept fresh.
const BUDGET_US := 500
const NEAR_RADIUS := 320.0
## Keep schedule destinations local to the settlement; SmartObjects uses a
## per-settlement candidate list, so this range can include the outer farm rows.
const SMART_TARGET_MAX_RADIUS := 256.0
## Real seconds per in-game day.
const DAY_LENGTH := 720.0
const FIRST := ["Marcus", "Aldric", "Edda", "Hild", "Osric", "Wynn", "Bertram", "Maud", "Cedric", "Agnes",
	"Godric", "Elena", "Hugh", "Isolde", "Roland", "Sybil", "Tobias", "Mira", "Walter", "Rowan"]
const LAST := ["Smith", "Cooper", "Fletcher", "Thatcher", "Miller", "Ward", "Brook", "Hale", "Carter", "Mason"]

var time_of_day := 8.0      # hours, 0..24
var day := 1

## Four-season calendar (scripts/sim/seasons.gd), advanced off our own
## hour_changed signal. "spring" / "summer" / "autumn" / "winter".
var seasons: Node = null
var season: String:
	get: return seasons.season_name() if seasons else "spring"

# Per-person columns.
var home := PackedInt32Array()
var job := PackedByteArray()
var pos := PackedVector2Array()
var target := PackedVector2Array()
var money := PackedInt32Array()
var health := PackedByteArray()
var phase := PackedByteArray()      # schedule phase the current target belongs to
var last_update := PackedFloat32Array()
## Five normalized UtilityBrain needs per person, kept flat to avoid per-person objects.
var npc_need_values := PackedFloat32Array()
var npc_need_hours := PackedFloat64Array()
var npc_need_valid := PackedByteArray()
## 1 only when an embodied UtilityBrain, rather than an impostor, advances needs.
var npc_need_brain_owner := PackedByteArray()
## Owner instance ID while a higher-detail LOD representation owns position.
## Schedule, wages and other world-data updates continue, but _step does not
## integrate a competing movement path behind that representation. The token
## makes delayed exits from replaced bodies unable to release a newer owner's claim.
var external_position_owner := PackedInt64Array()
## Per settlement: [first_person, end_person), treasury.
var ranges: Array[Vector2i] = []
var treasury := PackedInt32Array()

var _cursor := 0
var _clock := 0.0
var _last_hour := -1
var dbg_slice_usec := 0   # QA: total _simulate_slice time, read by tools/qa/water_shots/water_prof.gd
var dbg_frames := 0
var _near_ids := PackedInt32Array()
var _near_cursor := 0
var _near_next := 0.0
## Schedule.F_* mask per settlement (TownMood), refreshed one settlement per frame after each hour change.
var _mood_flags := PackedInt32Array()
var _mood_cursor := 0
var _mood_pending := 0
## Semantic work targets are resolved only for settlements in the existing near-simulation ring.
## Distant rows keep their deterministic cheap schedule targets.
var smart: SmartObjects
var _smart_done: Dictionary = {}             # settlement id -> external activity spot count indexed
var _near_settlement_ids: Dictionary = {}    # settlement id -> true, rebuilt with _near_ids


func _ready() -> void:
	SeasonsScript.ensure_globals()   # shader globals must exist before shaders compile
	WorldGen.setup(SEED)
	_populate()
	smart = SmartObjects.new()
	seasons = SeasonsScript.new()
	add_child(seasons)


## Back to the first morning of a new game: the whole population re-rolled from SEED, the clock and
## the calendar reset. (Life.reset calls this; the world scene is rebuilt afterwards.)
func reset() -> void:
	ThornfieldRoster.clear()      # F8: the named residents are bound to rows again after the new population exists
	time_of_day = 8.0
	day = 1
	home = PackedInt32Array()
	job = PackedByteArray()
	pos = PackedVector2Array()
	target = PackedVector2Array()
	money = PackedInt32Array()
	health = PackedByteArray()
	phase = PackedByteArray()
	last_update = PackedFloat32Array()
	npc_need_values = PackedFloat32Array()
	npc_need_hours = PackedFloat64Array()
	npc_need_valid = PackedByteArray()
	npc_need_brain_owner = PackedByteArray()
	external_position_owner = PackedInt64Array()
	ranges.clear()
	treasury = PackedInt32Array()
	_cursor = 0
	_clock = 0.0
	_last_hour = -1
	_near_ids = PackedInt32Array()
	_near_cursor = 0
	_near_next = 0.0
	smart = SmartObjects.new()
	_smart_done.clear()
	_near_settlement_ids.clear()
	_populate()
	if seasons:
		seasons.deserialize({"offset": 0})


func population() -> int:
	return pos.size()


func is_dead(i: int) -> bool:
	return i >= 0 and i < health.size() and health[i] == 0


func dead_list() -> Array:
	var out: Array = []
	for i in health.size():
		if health[i] == 0:
			out.append(i)
	return out


## Next living person of the same settlement after `i` (the heir of a dead person's purse); -1 when none.
func heir_of(i: int) -> int:
	if i < 0 or i >= pos.size():
		return -1
	var r: Vector2i = ranges[home[i]]
	var n := r.y - r.x
	for k in range(1, n):
		var j := r.x + (i - r.x + k) % n
		if health[j] != 0:
			return j
	return -1


## A person dies (killed): their row leaves the schedules and the walk, their purse goes to the heir, claims are
## released and social ties forgotten. Returns the heir (-1 none). Idempotent.
func kill_person(i: int, at := Vector2.INF) -> int:
	if i < 0 or i >= pos.size() or health[i] == 0:
		return -1
	var heir := heir_of(i)
	if heir >= 0:
		money[heir] += money[i]
		money[i] = 0
	_mark_dead(i)
	ThornfieldRoster.on_died(i)       # F8: the quest bus hears `died {actor}`
	if at != Vector2.INF:
		pos[i] = at
		target[i] = at
	var life := get_node_or_null("/root/Life")
	var graph: Variant = life.get("npc_social_graph") if life else null
	if graph != null and graph.has_method("forget"):
		graph.call("forget", "worldsim:%d:%d" % [SEED, i])
	return heir


func _mark_dead(i: int) -> void:
	health[i] = 0
	phase[i] = 255
	if smart != null:
		smart.release(i)


func person_name(i: int) -> String:
	var named := ThornfieldRoster.name_of(i)     # F8: a bound resident of Thornfield has a real name
	if named != "":
		return named
	var h := hash(i * 7919 + SEED)
	return "%s %s" % [FIRST[h % FIRST.size()], LAST[(h / 31) % LAST.size()]]


## Indoors people exist but aren't drawn: at home once they've arrived, and
## craftsmen working inside their shops.
func is_indoors(i: int) -> bool:
	if phase[i] == 0:
		return pos[i].distance_squared_to(target[i]) < 1.0
	# Craftsmen work inside their shop most of the time: 3 in 4 stay indoors once
	# they've arrived (was 2 in 3), so fewer bodies are idling on the street at
	# a given moment without changing where anyone actually is.
	if phase[i] == 1 and (job[i] == 1 or job[i] == 2):
		return i % 4 != 0 and pos[i].distance_squared_to(target[i]) < 1.0
	return false


func describe(i: int) -> String:
	return "%s · %s · %dg" % [person_name(i), JOBS[job[i]], money[i]]


## Transfer position ownership at an LOD boundary. WorldSim remains authoritative
## for schedule and goal; a Villager or routed sprite may own resolved movement.
func set_external_position_owner(i: int, owner_id: int, owned: bool, resolved_position := Vector2.INF,
		brain_owns_needs := false) -> void:
	if i < 0 or i >= pos.size() or owner_id <= 0:
		return
	# A reset can rebuild WorldSim's deterministic rows before the old world
	# scene exits. Its stale Villager must not write into the new run. Likewise,
	# a delayed exit from an old LOD owner cannot release a newer owner's claim.
	if not owned and external_position_owner[i] != owner_id:
		return
	if resolved_position != Vector2.INF:
		pos[i] = resolved_position
	external_position_owner[i] = owner_id if owned else 0
	npc_need_brain_owner[i] = 1 if owned and brain_owns_needs else 0


func owns_external_position(i: int, owner_id: int) -> bool:
	return i >= 0 and i < external_position_owner.size() and external_position_owner[i] == owner_id


## Read/write the durable five-value UtilityBrain state. Invalid or absent rows
## return empty so old saves retain the existing deterministic seed fallback.
func person_needs(i: int) -> Dictionary:
	if i < 0 or i >= npc_need_valid.size() or npc_need_valid[i] == 0:
		return {}
	var offset := i * 5
	return {"values": PackedFloat32Array([npc_need_values[offset], npc_need_values[offset + 1],
		npc_need_values[offset + 2], npc_need_values[offset + 3], npc_need_values[offset + 4]]),
		"hours": npc_need_hours[i]}


func set_person_needs(i: int, owner_id: int, values: PackedFloat32Array, hours: float) -> void:
	if not owns_external_position(i, owner_id) or i >= npc_need_valid.size() or values.size() != 5 or not is_finite(hours):
		return
	var offset := i * 5
	for n in 5:
		if not is_finite(values[n]):
			return
	for n in 5:
		var value := values[n]
		npc_need_values[offset + n] = clampf(value, 0.0, 1.0)
	npc_need_hours[i] = hours
	npc_need_valid[i] = 1


## Indices of people within `radius` of p. Only settlements in range are scanned.
func people_near(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) > radius + s["radius"] * 2.0:
			continue
		var range_i: Vector2i = ranges[s["id"]]
		for i in range(range_i.x, range_i.y):
			if health[i] != 0 and pos[i].distance_squared_to(p) < r2:
				out.append(i)
	return out


func _populate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for s in WorldGen.settlements:
		var start := pos.size()
		for n in int(s["population"]):
			var i := pos.size()
			home.append(s["id"])
			job.append(TownIdentity.adjust_job(_pick_job(rng, s["kind"]), s, n))    # fortress towns post more guards, criminal ones fewer
			var spot := _spot(s, 0, i)
			pos.append(spot)
			target.append(spot)
			money.append(rng.randi_range(5, 120))
			health.append(100)
			phase.append(255)
			last_update.append(0.0)
			for _need in 5:
				npc_need_values.append(0.0)
			npc_need_hours.append(0.0)
			npc_need_valid.append(0)
			npc_need_brain_owner.append(0)
			external_position_owner.append(0)
		ranges.append(Vector2i(start, pos.size()))
		treasury.append(500)
	_mood_flags = PackedInt32Array()
	_mood_flags.resize(WorldGen.settlements.size())
	_mood_flags.fill(0)
	ThornfieldRoster.bind(true)      # F8: Thornfield's named residents take their rows (names, jobs, doors, schedules)


func _pick_job(rng: RandomNumberGenerator, kind: String) -> int:
	var roll := rng.randf()
	if kind == "village":
		return 0 if roll < 0.55 else (5 if roll < 0.7 else (4 if roll < 0.85 else (1 if roll < 0.92 else 2)))
	return 2 if roll < 0.25 else (1 if roll < 0.4 else (3 if roll < 0.55 else (4 if roll < 0.8 else 0)))


func _process(delta: float) -> void:
	_clock += delta
	time_of_day += delta * 24.0 / DAY_LENGTH
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
	var hour := int(time_of_day)
	if hour != _last_hour:
		_last_hour = hour
		_mood_pending = _mood_flags.size()
		_mood_cursor = 0
		hour_changed.emit(hour)
	_refresh_mood_step()
	var _t0 := Time.get_ticks_usec()
	_simulate_slice()
	dbg_slice_usec += Time.get_ticks_usec() - _t0
	dbg_frames += 1


## Skip time (sleeping, waiting): steps hour by hour so every hourly listener
## runs, then settles everyone where their schedule says they should be.
func advance_hours(hours: float) -> void:
	var left := hours
	while left > 0.0:
		var step := minf(1.0, left)
		left -= step
		time_of_day += step
		if time_of_day >= 24.0:
			time_of_day -= 24.0
			day += 1
		var hour := int(time_of_day)
		if hour != _last_hour:
			_last_hour = hour
			hour_changed.emit(hour)
	_refresh_moods_now()
	for i in pos.size():
		var want := _current_phase(job[i], i)
		if want != phase[i]:
			_on_phase_change(i, phase[i], want)
		if npc_need_valid[i] != 0 and npc_need_brain_owner[i] == 0:
			_advance_offline_needs(i, day * 24.0 + time_of_day)
		# Time skips settle data-only residents immediately. An embodied body
		# keeps its resolved position and follows the newly selected target.
		if external_position_owner[i] == 0:
			pos[i] = target[i]
		last_update[i] = _clock


func serialize() -> Dictionary:
	return {"day": day, "time": time_of_day, "treasury": Array(treasury), "money": Marshalls.raw_to_base64(money.to_byte_array()),
		"npc_needs_v": 2, "npc_needs": Marshalls.raw_to_base64(npc_need_values.to_byte_array()),
		"npc_needs_hours": Marshalls.raw_to_base64(npc_need_hours.to_byte_array()),
		"npc_needs_valid": Marshalls.raw_to_base64(npc_need_valid),
		"dead": dead_list(),
		"season": seasons.serialize() if seasons else {}}


func deserialize(d: Dictionary) -> void:
	# Claims are transient schedule reservations. Rebuild them from the loaded rows
	# instead of letting a previous session's people keep slots occupied.
	smart = SmartObjects.new()
	_smart_done.clear()
	_near_settlement_ids.clear()
	# Loading an older save into a running session must not inherit needs from the
	# session being replaced. Missing/invalid fields naturally use seeded fallback.
	npc_need_values = PackedFloat32Array()
	npc_need_hours = PackedFloat64Array()
	npc_need_valid = PackedByteArray()
	npc_need_brain_owner = PackedByteArray()
	for _person in pos.size():
		for _need in 5:
			npc_need_values.append(0.0)
		npc_need_hours.append(0.0)
		npc_need_valid.append(0)
		npc_need_brain_owner.append(0)
	if d.is_empty():
		return
	day = int(d.get("day", day))
	time_of_day = float(d.get("time", time_of_day))
	var t: Array = d.get("treasury", [])
	for k in mini(t.size(), treasury.size()):
		treasury[k] = int(t[k])
	if d.has("money"):
		var m := Marshalls.base64_to_raw(d["money"]).to_int32_array()
		if m.size() == money.size():
			money = m
	var need_version := int(d.get("npc_needs_v", 0))
	if need_version in [1, 2] and d.has("npc_needs") and d.has("npc_needs_hours") and d.has("npc_needs_valid"):
		var raw_values := Marshalls.base64_to_raw(String(d["npc_needs"]))
		var raw_hours := Marshalls.base64_to_raw(String(d["npc_needs_hours"]))
		var stored_valid := Marshalls.base64_to_raw(String(d["npc_needs_valid"]))
		var expected_hours_bytes := pos.size() * (8 if need_version == 2 else 4)
		if raw_values.size() == pos.size() * 5 * 4 and raw_hours.size() == expected_hours_bytes and stored_valid.size() == pos.size():
			var stored_values := raw_values.to_float32_array()
			var stored_hours := PackedFloat64Array(raw_hours.to_float64_array()) if need_version == 2 else PackedFloat64Array(raw_hours.to_float32_array())
			for i in pos.size():
				if stored_valid[i] == 0:
					continue
				if not is_finite(stored_hours[i]):
					stored_valid[i] = 0
					continue
				var offset := i * 5
				for n in 5:
					if not is_finite(stored_values[offset + n]) or stored_values[offset + n] < 0.0 or stored_values[offset + n] > 1.0:
						stored_valid[i] = 0
						break
			npc_need_values = stored_values
			npc_need_hours = stored_hours
			npc_need_valid = stored_valid
	if seasons and d.has("season"):
		seasons.deserialize(d["season"])
	# The dead stay dead (killed by the player, Takedown); everyone else is alive again.
	health.fill(100)
	var dead_rows: Variant = d.get("dead", [])
	if dead_rows is Array:
		for row: Variant in dead_rows:
			if (row is int or row is float) and int(row) >= 0 and int(row) < pos.size():
				_mark_dead(int(row))
	_last_hour = -1
	for i in pos.size():
		phase[i] = 255


## Schedule phase for the current hour (scripts/population/schedule.gd): 0 home, 1 work, 2 market, 3 inn,
## 4 temple, 5 training yard, 6 plaza. Without a person it is the original three-phase table.
func _current_phase(person_job: int, i := -1) -> int:
	var flags := 0
	if i >= 0 and i < home.size() and home[i] < _mood_flags.size():
		flags = _mood_flags[home[i]]
	return ThornfieldRoster.override_phase(i, time_of_day, Schedule.phase(person_job, time_of_day, flags, i, day))


## One settlement's circumstance mask per call (rest day, festival, war, shortages, mourning, curfew ...).
func _refresh_mood_step() -> void:
	if _mood_pending <= 0 or _mood_flags.is_empty():
		return
	_mood_pending -= 1
	var sid := _mood_cursor
	_mood_cursor = (_mood_cursor + 1) % _mood_flags.size()
	_mood_flags[sid] = TownMood.flags_of(sid)


func _refresh_moods_now() -> void:
	TownMood.clear_cache()
	for sid in _mood_flags.size():
		_mood_flags[sid] = TownMood.flags_of(sid)
	_mood_pending = 0


## The circumstance mask of settlement `sid` as the rows currently use it.
func mood_flags(sid: int) -> int:
	return _mood_flags[sid] if sid >= 0 and sid < _mood_flags.size() else 0


## Schedule phase of row `i` at hour `h` (same table as _current_phase; used by Codex's offline need catch-up).
func _phase_at(person_job: int, h: float, i := -1) -> int:
	var flags := 0
	if i >= 0 and i < home.size() and home[i] < _mood_flags.size():
		flags = _mood_flags[home[i]]
	return ThornfieldRoster.override_phase(i, h, Schedule.phase(person_job, h, flags, i, day))


## Distant need state advances only when the resident's existing WorldSim row is
## already being visited by the time-sliced simulation (or by advance_hours()).
## Schedule boundaries and meal times split the arithmetic so sleeping and meals
## are consistent regardless of how many rendered frames elapsed between visits.
func _advance_offline_needs(i: int, now_hours: float) -> void:
	var stored_hours := float(npc_need_hours[i])
	var elapsed := clampf(now_hours - stored_hours, 0.0, NeedRules.OFFLINE_CATCHUP_HOURS)
	if elapsed <= 0.0:
		npc_need_hours[i] = now_hours
		return
	var offset := i * 5
	var cursor := now_hours - elapsed
	var social_rate := NeedRules.social_drain_per_hour(i)
	var faith_rate := NeedRules.faith_drain_per_hour(i)
	while cursor < now_hours:
		var day_start := floorf(cursor / 24.0) * 24.0
		var local_hour := cursor - day_start
		var next := now_hours
		for boundary: float in NEED_SCHEDULE_BOUNDARIES:
			var event_hour := day_start + boundary
			if event_hour > cursor + 0.0000001:
				next = minf(next, event_hour)
		for meal: float in NeedRules.MEALS:
			var meal_hour := day_start + meal
			if meal_hour > cursor + 0.0000001:
				next = minf(next, meal_hour)
		if next <= cursor:
			break
		var midpoint := fposmod((cursor + next) * 0.5, 24.0)
		var sleeping := _phase_at(job[i], midpoint, i) == 0 and (midpoint < 6.0 or midpoint >= 21.0)
		var dt := next - cursor
		npc_need_values[offset] -= NeedRules.HUNGER_PER_HOUR * dt * (0.5 if sleeping else 1.0)
		if sleeping:
			npc_need_values[offset + 1] += NeedRules.SLEEP_PER_HOUR * dt
		else:
			npc_need_values[offset + 1] -= NeedRules.FATIGUE_PER_HOUR * dt
		npc_need_values[offset + 2] -= social_rate * dt
		npc_need_values[offset + 3] -= faith_rate * dt
		npc_need_values[offset + 4] -= NeedRules.WATER_PER_HOUR * dt
		# Recover food exactly when this interval reaches a scheduled meal.
		for meal: float in NeedRules.MEALS:
			if absf(next - (day_start + meal)) < 0.000001:
				npc_need_values[offset] = minf(1.0, npc_need_values[offset] + NeedRules.EAT_RESTORE_PER_HOUR * 0.5)
		for n in 5:
			npc_need_values[offset + n] = clampf(npc_need_values[offset + n], 0.0, 1.0)
		cursor = next
	npc_need_hours[i] = now_hours


## Time-sliced: the whole database used to be walked at 1500 people per frame
## (about 4 ms per frame in GDScript, the biggest single CPU cost measured at the
## lake on LOW, 2026-09-29). Now a fixed time budget per frame is spent, and the
## people near the player (the ones with sprites or bodies) are updated first and
## often; distant settlements get the leftover budget. Movement uses each
## person's own elapsed time (dt), so a slower cycle gives the same result.
func _simulate_slice() -> void:
	var n := pos.size()
	if n == 0:
		return
	_refresh_near()
	var t0 := Time.get_ticks_usec()
	var near_end := t0 + BUDGET_US * 7 / 10
	var end := t0 + BUDGET_US
	var m := _near_ids.size()
	if m > 0:
		# Every near person about every 4 frames (15 Hz at 60 fps).
		var todo := maxi((m + 3) / 4, 32)
		var k := 0
		while k < todo:
			_step(_near_ids[_near_cursor])
			_near_cursor += 1
			if _near_cursor >= m:
				_near_cursor = 0
			k += 1
			if (k & 31) == 0 and Time.get_ticks_usec() > near_end:
				break
	var c := 0
	while true:
		_step(_cursor)
		_cursor += 1
		if _cursor >= n:
			_cursor = 0
		c += 1
		if (c & 31) == 0 and Time.get_ticks_usec() > end:
			break


func _step(i: int) -> void:
	if health[i] == 0:
		return                  # dead: off every schedule, job and walk
	var dt := _clock - last_update[i]
	last_update[i] = _clock
	var want := _current_phase(job[i], i)
	if want != phase[i]:
		_on_phase_change(i, phase[i], want)
	if npc_need_valid[i] != 0 and npc_need_brain_owner[i] == 0:
		_advance_offline_needs(i, day * 24.0 + time_of_day)
	# A higher-detail body or routed sprite is the sole position integrator until
	# it releases this row. WorldSim still updates schedule/economy and eligible
	# unembodied needs above, then waits for resolved position writeback.
	if external_position_owner[i] != 0:
		return
	var to := target[i] - pos[i]
	var dist := to.length()
	if dist > 0.05:
		pos[i] += to / dist * minf(dist, WALK_SPEED * dt)


## People of the settlements within NEAR_RADIUS of the player, rebuilt every 1.5 s.
func _refresh_near() -> void:
	if _clock < _near_next:
		return
	_near_next = _clock + 1.5
	_near_ids.clear()
	_near_cursor = 0
	_near_settlement_ids.clear()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) > NEAR_RADIUS + float(s["radius"]) * 2.0:
			continue
		_near_settlement_ids[int(s["id"])] = true
		var r: Vector2i = ranges[s["id"]]
		for i in range(r.x, r.y):
			_near_ids.append(i)


func _on_phase_change(i: int, old: int, new_phase: int) -> void:
	# A phase switch can move to a different type of target or fall back when a
	# slot is unavailable. Drop the old reservation before looking for the new one.
	release_activity_target(i)
	var s: Dictionary = WorldGen.settlements[home[i]]
	if old == 1:
		money[i] += WAGES[job[i]]
	if new_phase == 2 and money[i] > 3:
		var spend := mini(money[i], 3 + (i % 6))
		money[i] -= spend
		treasury[home[i]] += spend
	elif new_phase == 3 and money[i] > 2:
		var tab := mini(money[i], 2 + (i % 4))      # a round at the inn
		money[i] -= tab
		treasury[home[i]] += tab
	phase[i] = new_phase
	target[i] = _spot(s, new_phase, i)


## Release a near-ring schedule reservation when an embodied UtilityBrain act
## overrides that schedule goal. A new work/shop goal may claim another slot.
func release_activity_target(i: int) -> void:
	if smart != null:
		smart.release(i)


## Deterministic point of interest for a person and phase.
func _spot(s: Dictionary, which: int, i: int) -> Vector2:
	var named_spot := ThornfieldRoster.spot(i, which)      # F8: a named resident's own door
	if named_spot != Vector2.INF:
		if which == 0 and smart != null:
			smart.release(i)
		return named_spot
	if which == 0 and smart != null:
		# DailyRhythm can return home before the coarse WorldSim phase changes.
		# Release the old work slot when that resident's own schedule goal does.
		smart.release(i)
	if (which == 1 or which == 2) and smart != null:
		var sid := int(s["id"])
		if _near_settlement_ids.has(sid):
			var act := "work" if which == 1 else "shop"
			var role := "vendor" if which == 1 and job[i] == 2 else ("customer" if which == 2 else "")
			var center: Vector2 = s["pos"]
			var center_3d := Vector3(center.x, WorldGen.height(center.x, center.y), center.y)
			var near_plan: Dictionary = s.get("plan", {})
			var activity_spots: Array = near_plan.get("activity_spots", [])
			if int(_smart_done.get(sid, -1)) != activity_spots.size():
				smart.populate_settlement(s, WorldGen.height)
				_smart_done[sid] = activity_spots.size()
			var semantic_target := smart.target_for(i, center_3d, act,
				job[i] if i < job.size() else 4, time_of_day,
				minf(float(s["radius"]) * 2.5, SMART_TARGET_MAX_RADIUS), role, sid)
			if semantic_target != Vector2.INF:
				return semantic_target
	if which >= Schedule.Phase.INN:
		return Schedule.spot(s, which, i, day)
	var r: float = s["radius"]
	var h := hash(i * 131 + which * 17 + day * (1 if which == 2 else 0))
	var ang := float(h % 3600) / 3600.0 * TAU
	var t := float((h / 3600) % 1000) / 1000.0
	var plan: Dictionary = s.get("plan", {})
	var lots: Array = plan.get("lots", [])
	# Homes and workshops are real buildings from the city plan: people stand at the door.
	if not lots.is_empty() and (which == 0 or (which == 1 and i < job.size() and (job[i] == 1 or job[i] == 2))):
		var lot: Dictionary = lots[h % lots.size()]
		var yaw: float = lot["yaw"]
		return lot["pos"] + Vector2(sin(yaw), cos(yaw)) * 4.6
	var dist: float
	match which:
		0: dist = lerpf(r * 0.35, r * 0.85, t)                   # homes
		2: dist = lerpf(2.0, plan.get("plaza_r", r * 0.2) + 2.0, t)    # market square
		_:
			match job[i] if i < job.size() else 4:
				0: dist = lerpf(r * 1.2, r * 1.9, t)             # fields
				5: dist = lerpf(r * 2.0, r * 2.8, t)             # forest edge
				3: dist = r * 0.95                               # walls / gate
				1, 2: dist = lerpf(r * 0.1, r * 0.35, t)          # workshops
				_: dist = lerpf(r * 0.2, r * 1.2, t)
	return s["pos"] + Vector2(cos(ang), sin(ang)) * dist
