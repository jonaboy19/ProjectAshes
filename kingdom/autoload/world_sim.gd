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

const SEED := 1066
const JOBS := ["Farmer", "Blacksmith", "Merchant", "Guard", "Laborer", "Woodcutter"]
const WAGES := [6, 12, 15, 9, 5, 7]
const WALK_SPEED := 1.3
const UPDATES_PER_FRAME := 1500
## Real seconds per in-game day.
const DAY_LENGTH := 720.0
const FIRST := ["Marcus", "Aldric", "Edda", "Hild", "Osric", "Wynn", "Bertram", "Maud", "Cedric", "Agnes",
	"Godric", "Elena", "Hugh", "Isolde", "Roland", "Sybil", "Tobias", "Mira", "Walter", "Rowan"]
const LAST := ["Smith", "Cooper", "Fletcher", "Thatcher", "Miller", "Ward", "Brook", "Hale", "Carter", "Mason"]

var time_of_day := 8.0      # hours, 0..24
var day := 1

# Per-person columns.
var home := PackedInt32Array()
var job := PackedByteArray()
var pos := PackedVector2Array()
var target := PackedVector2Array()
var money := PackedInt32Array()
var health := PackedByteArray()
var phase := PackedByteArray()      # schedule phase the current target belongs to
var last_update := PackedFloat32Array()
## Per settlement: [first_person, end_person), treasury.
var ranges: Array[Vector2i] = []
var treasury := PackedInt32Array()

var _cursor := 0
var _clock := 0.0
var _last_hour := -1


func _ready() -> void:
	WorldGen.setup(SEED)
	_populate()


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
	if phase[i] == 1 and (job[i] == 1 or job[i] == 2):
		return i % 3 != 0 and pos[i].distance_squared_to(target[i]) < 1.0
	return false


func describe(i: int) -> String:
	return "%s · %s · %dg" % [person_name(i), JOBS[job[i]], money[i]]


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
	_simulate_slice()


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


func _simulate_slice() -> void:
	var n := pos.size()
	if n == 0:
		return
	for k in mini(UPDATES_PER_FRAME, n):
		var i := _cursor
		_cursor = (_cursor + 1) % n
		var dt := _clock - last_update[i]
		last_update[i] = _clock
		var want := _current_phase(job[i])
		if want != phase[i]:
			_on_phase_change(i, phase[i], want)
		var to := target[i] - pos[i]
		var dist := to.length()
		if dist > 0.05:
			pos[i] += to / dist * minf(dist, WALK_SPEED * dt)


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
