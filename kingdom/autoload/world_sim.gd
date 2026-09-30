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

const SEED := 1066
const JOBS := ["Farmer", "Blacksmith", "Merchant", "Guard", "Laborer", "Woodcutter"]
const WAGES := [6, 12, 15, 9, 5, 7]
const WALK_SPEED := 1.3
## CPU budget for the whole-world sim per frame, and the radius around the player that is kept fresh.
const BUDGET_US := 500
const NEAR_RADIUS := 320.0
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


func _ready() -> void:
	SeasonsScript.ensure_globals()   # shader globals must exist before shaders compile
	WorldGen.setup(SEED)
	_populate()
	seasons = SeasonsScript.new()
	add_child(seasons)


## Back to the first morning of a new game: the whole population re-rolled from SEED, the clock and
## the calendar reset. (Life.reset calls this; the world scene is rebuilt afterwards.)
func reset() -> void:
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
	external_position_owner = PackedInt64Array()
	ranges.clear()
	treasury = PackedInt32Array()
	_cursor = 0
	_clock = 0.0
	_last_hour = -1
	_near_ids = PackedInt32Array()
	_near_cursor = 0
	_near_next = 0.0
	_populate()
	if seasons:
		seasons.deserialize({"offset": 0})


func population() -> int:
	return pos.size()


func person_name(i: int) -> String:
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
func set_external_position_owner(i: int, owner_id: int, owned: bool, resolved_position := Vector2.INF) -> void:
	if i < 0 or i >= pos.size():
		return
	# A reset can rebuild WorldSim's deterministic rows before the old world
	# scene exits. Its stale Villager must not write into the new run. Likewise,
	# a delayed exit from an old LOD owner cannot release a newer owner's claim.
	if not owned and external_position_owner[i] != owner_id:
		return
	if resolved_position != Vector2.INF:
		pos[i] = resolved_position
	external_position_owner[i] = owner_id if owned else 0


## Indices of people within `radius` of p. Only settlements in range are scanned.
func people_near(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) > radius + s["radius"] * 2.0:
			continue
		var range_i: Vector2i = ranges[s["id"]]
		for i in range(range_i.x, range_i.y):
			if pos[i].distance_squared_to(p) < r2:
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
			job.append(_pick_job(rng, s["kind"]))
			var spot := _spot(s, 0, i)
			pos.append(spot)
			target.append(spot)
			money.append(rng.randi_range(5, 120))
			health.append(100)
			phase.append(255)
			last_update.append(0.0)
			external_position_owner.append(0)
		ranges.append(Vector2i(start, pos.size()))
		treasury.append(500)


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
		hour_changed.emit(hour)
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
	for i in pos.size():
		var want := _current_phase(job[i])
		if want != phase[i]:
			_on_phase_change(i, phase[i], want)
		pos[i] = target[i]
		last_update[i] = _clock


func serialize() -> Dictionary:
	return {"day": day, "time": time_of_day, "treasury": Array(treasury), "money": Marshalls.raw_to_base64(money.to_byte_array()),
		"season": seasons.serialize() if seasons else {}}


func deserialize(d: Dictionary) -> void:
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
	if seasons and d.has("season"):
		seasons.deserialize(d["season"])
	_last_hour = -1
	for i in pos.size():
		phase[i] = 255


## Schedule phase for the current hour: 0 home, 1 work, 2 market.
func _current_phase(person_job: int) -> int:
	var h := time_of_day
	if h < 6.0 or h >= 21.0:
		return 0
	if person_job == 3:          # guards keep watch all day
		return 1
	if h < 17.0:
		return 2 if (h >= 12.0 and h < 13.0 and person_job == 4) else 1
	return 2 if h < 19.5 else 0


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
	var dt := _clock - last_update[i]
	last_update[i] = _clock
	var want := _current_phase(job[i])
	if want != phase[i]:
		_on_phase_change(i, phase[i], want)
	# A promoted Villager is the sole position integrator until it is demoted.
	# WorldSim still updates this row's schedule/economy above, then waits for the
	# body's resolved position to be written back at the LOD boundary.
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
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) > NEAR_RADIUS + float(s["radius"]) * 2.0:
			continue
		var r: Vector2i = ranges[s["id"]]
		for i in range(r.x, r.y):
			_near_ids.append(i)


func _on_phase_change(i: int, old: int, new_phase: int) -> void:
	var s: Dictionary = WorldGen.settlements[home[i]]
	if old == 1:
		money[i] += WAGES[job[i]]
	if new_phase == 2 and money[i] > 3:
		var spend := mini(money[i], 3 + (i % 6))
		money[i] -= spend
		treasury[home[i]] += spend
	phase[i] = new_phase
	target[i] = _spot(s, new_phase, i)


## Deterministic point of interest for a person and phase.
func _spot(s: Dictionary, which: int, i: int) -> Vector2:
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
