extends RefCounted
## NPC perception for the near-NPC layer (tier 0, at most 24 bodies): one alert scalar per body, a cheap
## vision factor (cone x distance x light x stance), analytic light for the player, and hearing events.
## Own numbers, tuned in the lab; the shape (cheap gates first, one budgeted ray last, scalar with thresholds
## and grace) follows docs/research/MINING_PERCEPTION_INTERACTION.md sections 2.1-2.4 and 4.1.
##
## Everything is static data with fixed arrays (like NpcWorld): a think tick costs arithmetic and no allocation.
## No randf(): chances come from hash([...]).  The distant tiers never touch this.
##
## Flow per think tick of an embodied villager (villager.gd):
##   var vis := Perception.vis(npc_pos, facing, player_pos, Perception.light_at(player_pos), stance, still, acuity)
##   if vis > Perception.VIS_MIN: ray = UtilityBrain.try_ray(...)   # the shared budget, one ray
##   Perception.update(slot, seen_vis, suspicion_factor, ..., now_ms, dt)
##   inputs for the brain: Perception.inputs(slot, into)

## NpcWorld preloads this script, so it is loaded lazily here (no preload cycle).
const NPC_WORLD := "res://scripts/population/npc_world.gd"

enum Cls { CALM, NOTICE, SUSPICIOUS, SEARCHING, ALARMED }
const CLASS_NAMES := ["calm", "notice", "suspicious", "searching", "alarmed"]

const SLOTS := 24
const T_NOTICE := 1.5
const T_SUSPICIOUS := 6.0
const T_SEARCHING := 10.0
const T_ALARMED := 18.0
const MAX_ALERT := 30.0
const DECAY_CALM := 0.8
const DECAY_SEARCHING := 0.3
## A class may fall only one step per this many ms.
const DROP_GAP_MS := 4000
## A repeat of the same source within this window is ignored (grace).
const GRACE_MS := 2500
const KNOWN := 4
const VIS_MIN := 0.05
## Sight cap: ordinary people watching an ordinary passer-by never get past "notice"; the watch can go all the way.
const SIGHT_CAP_CIVILIAN := 9.5
const SIGHT_CAP_GUARD := MAX_ALERT
## How suspicious the player looks (scales the alert gain AND caps what sight alone can reach, x MAX_ALERT).
const SUSP_PLAIN := 0.04
const SUSP_NIGHT := 0.07
const SUSP_ARMED := 0.55
const SUSP_CROUCH := 0.8
const SUSP_WANTED := 1.0

# stance multipliers (stance_term)
const STANCE_CROUCH := 0.5
const STANCE_WALK := 1.0
const STANCE_RUN := 1.25
const STANCE_MOUNTED := 1.4

# vision
const CONE_FULL := 1.2217305    # 70 degrees
const CONE_NONE := 1.9198622    # 110 degrees
const NEAR_M := 6.0
const FAR_M := 24.0
const FAR_STILL_DARK := 8.0
const GUARD_RANGE := 1.3

# light
const LIGHT_HZ_MS := 250
const LIGHT_RADIUS := 25.0
const MAX_LIGHTS := 32
const LANTERN_LIGHT := 0.4

# hearing
enum Sound { FOOTSTEP_WALK, FOOTSTEP_RUN, FOOTSTEP_CROUCH, DOOR_SLAM, LOCKPICK, BREAK_WOOD, BREAK_POTTERY, COIN_DROP, CLASH, SCREAM, DISTRACTION }
const SOUND_LOUDNESS := [8.0, 16.0, 3.0, 14.0, 4.0, 18.0, 20.0, 9.0, 28.0, 40.0, 22.0]
const SOUND_CAP := [2.0, 3.0, 1.5, 4.0, 3.0, 6.0, 7.0, 3.0, 9.0, 20.0, 5.0]
## Occlusion class multipliers on loudness.
enum Occ { SAME_CELL, OPEN_DOOR, CLOSED_DOOR, OTHER_BUILDING }
const OCC_MULT := [1.0, 0.7, 0.35, 0.2]

# ------------------------------------------------------------------ per-body store
static var alert := PackedFloat32Array()
static var cls := PackedInt32Array()
static var point := PackedVector2Array()
static var src := PackedInt32Array()
static var grace_until := PackedInt32Array()
static var drop_ok_ms := PackedInt32Array()
static var known := PackedInt32Array()           # SLOTS * KNOWN ring of event ids
static var acuity := PackedFloat32Array()
static var guard := PackedByteArray()
static var heard_ms := PackedInt32Array()
static var used := PackedByteArray()
static var last_ray_ms := PackedInt32Array()
static var _slot_of := {}                        # person -> slot
static var _ready_store := false
static var _event_serial := 0

# ------------------------------------------------------------------ light
static var _lights := PackedFloat32Array()       # stride 4: x, z, radius, energy
static var _light_n := 0
static var _hour := 12.0
static var _overcast := 0.0
static var _indoor := false
static var _lantern := false
static var _lc_ms := -100000
static var _lc_pos := Vector2.INF
static var _lc_val := 0.0
static var light_evals := 0                      # QA: how often the analytic light really ran

# ------------------------------------------------------------------ QA
static var profile := false
static var prof_usec := 0
static var prof_calls := 0


static func _ensure() -> void:
	if _ready_store:
		return
	_ready_store = true
	alert.resize(SLOTS)
	cls.resize(SLOTS)
	point.resize(SLOTS)
	src.resize(SLOTS)
	grace_until.resize(SLOTS)
	drop_ok_ms.resize(SLOTS)
	known.resize(SLOTS * KNOWN)
	acuity.resize(SLOTS)
	guard.resize(SLOTS)
	heard_ms.resize(SLOTS)
	used.resize(SLOTS)
	last_ray_ms.resize(SLOTS)
	_lights.resize(MAX_LIGHTS * 4)
	_clear_slots()


static func _clear_slots() -> void:
	alert.fill(0.0)
	cls.fill(0)
	point.fill(Vector2.INF)
	src.fill(0)
	grace_until.fill(0)
	drop_ok_ms.fill(0)
	known.fill(0)
	acuity.fill(1.0)
	guard.fill(0)
	heard_ms.fill(-100000)
	used.fill(0)
	last_ray_ms.fill(-100000)


## Forget everything (tests, new game).
static func reset() -> void:
	_ready_store = false
	_slot_of.clear()
	_light_n = 0
	_hour = 12.0
	_overcast = 0.0
	_indoor = false
	_lantern = false
	_lc_ms = -100000
	_lc_pos = Vector2.INF
	_event_serial = 0
	light_evals = 0
	profile = false
	prof_usec = 0
	prof_calls = 0
	_ensure()


# ================================================================ slots
## Give `person` a perception slot (-1 when all SLOTS are taken). `role_acuity`: guard 1.2, villager 1.0,
## drunk 0.5, child 0.8.
static func bind(person: int, role_acuity := 1.0, is_guard := false) -> int:
	_ensure()
	if _slot_of.has(person):
		return _slot_of[person]
	for i in SLOTS:
		if used[i] == 0:
			used[i] = 1
			_slot_of[person] = i
			alert[i] = 0.0
			cls[i] = 0
			point[i] = Vector2.INF
			src[i] = 0
			grace_until[i] = 0
			drop_ok_ms[i] = 0
			heard_ms[i] = -100000
			last_ray_ms[i] = -100000
			acuity[i] = role_acuity
			guard[i] = 1 if is_guard else 0
			for k in KNOWN:
				known[i * KNOWN + k] = 0
			return i
	return -1


static func unbind(person: int) -> void:
	if not _slot_of.has(person):
		return
	used[_slot_of[person]] = 0
	_slot_of.erase(person)


static func slot_of(person: int) -> int:
	return _slot_of.get(person, -1)


static func bound_count() -> int:
	return _slot_of.size()


# ================================================================ light
## Hour, how overcast (0..1, rain counts as 1) and whether the player is indoors; the light cache drops.
static func set_environment(hour: float, overcast := 0.0, indoor := false, lantern := false) -> void:
	_ensure()
	_hour = hour
	_overcast = clampf(overcast, 0.0, 1.0)
	_indoor = indoor
	_lantern = lantern
	_lc_ms = -100000


## Ambient light 0..1 by hour (moonlit night 0.15, noon 1.0), overcast and indoors.
static func ambient(hour: float, overcast := 0.0, indoor := false) -> float:
	var day := smoothstep(5.0, 7.5, hour) * (1.0 - smoothstep(18.0, 20.5, hour))
	var a := lerpf(0.15, 1.0, day) * (1.0 - 0.35 * overcast)
	if indoor:
		a = maxf(0.3, a * 0.55)
	return a


## A lamp/torch/brazier at `pos` (metres in the XZ plane). Returns its id for unregister_light (-1 when full).
static func register_light(pos: Vector2, radius := 8.0, energy := 0.6) -> int:
	_ensure()
	if _light_n >= MAX_LIGHTS:
		return -1
	var i := _light_n
	_lights[i * 4] = pos.x
	_lights[i * 4 + 1] = pos.y
	_lights[i * 4 + 2] = radius
	_lights[i * 4 + 3] = energy
	_light_n += 1
	_lc_ms = -100000
	return i


## Remove light `id` (the last light moves into its place, so ids of others may change: register again on rebuild).
static func unregister_light(id: int) -> void:
	if id < 0 or id >= _light_n:
		return
	var last := _light_n - 1
	for k in 4:
		_lights[id * 4 + k] = _lights[last * 4 + k]
	_light_n -= 1
	_lc_ms = -100000


static func clear_lights() -> void:
	_light_n = 0
	_lc_ms = -100000


static func light_count() -> int:
	return _light_n


## Analytic light at `pos`: ambient + registered lights within LIGHT_RADIUS + the player's own lantern. Never a
## render pass. Cached LIGHT_HZ_MS (4 Hz) while the target stays within 1.5 m of the cached point.
static func light_at(pos: Vector2, now_ms := -1) -> float:
	_ensure()
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _lc_ms < LIGHT_HZ_MS and _lc_pos != Vector2.INF and pos.distance_squared_to(_lc_pos) < 2.25:
		return _lc_val
	_lc_ms = now
	_lc_pos = pos
	_lc_val = light_uncached(pos)
	return _lc_val


static func light_uncached(pos: Vector2) -> float:
	light_evals += 1
	var l := ambient(_hour, _overcast, _indoor)
	var r2 := LIGHT_RADIUS * LIGHT_RADIUS
	for i in _light_n:
		var dx := _lights[i * 4] - pos.x
		var dz := _lights[i * 4 + 1] - pos.y
		var d2 := dx * dx + dz * dz
		if d2 > r2:
			continue
		var rad := _lights[i * 4 + 2]
		if d2 >= rad * rad:
			continue
		var f := 1.0 - sqrt(d2) / rad
		l += _lights[i * 4 + 3] * f * f
	if _lantern:
		l += LANTERN_LIGHT
	return clampf(l, 0.0, 1.0)


# ================================================================ vision
static func stance_term(crouching: bool, running: bool, mounted: bool) -> float:
	if mounted:
		return STANCE_MOUNTED
	if crouching:
		return STANCE_CROUCH
	return STANCE_RUN if running else STANCE_WALK


## How suspicious the player looks right now (0..1): scales alert gain and caps what sight alone reaches.
static func suspicion_factor(crouching: bool, armed: bool, wanted: bool, hour: float) -> float:
	if wanted:
		return SUSP_WANTED
	if crouching:
		return SUSP_CROUCH
	if armed:
		return SUSP_ARMED
	return SUSP_NIGHT if (hour >= 21.0 or hour < 5.0) else SUSP_PLAIN


static func light_term(light: float) -> float:
	return clampf(0.15 + 0.85 * light, 0.0, 1.0)


## Cone factor: 1 inside 70 degrees of `facing`, linear to 0 at 110 (peripheral).
static func cone(facing: Vector2, to_target: Vector2) -> float:
	var l := to_target.length()
	if l < 0.001 or facing == Vector2.ZERO:
		return 1.0
	var d := clampf(facing.dot(to_target) / (facing.length() * l), -1.0, 1.0)
	# cheap early outs: inside cos(70) is full, behind cos(110) is none
	if d >= 0.342:
		return 1.0
	if d <= -0.342:
		return 0.0
	return inverse_lerp(CONE_NONE, CONE_FULL, acos(d))


## Visibility 0..1 of `target` for an observer at `pos` looking along `facing`.
## Gates in order: distance^2, cone, light/stance. The caller then asks for ONE ray when this exceeds VIS_MIN.
static func vis(pos: Vector2, facing: Vector2, target: Vector2, light: float, stance := 1.0, still := false, observer_acuity := 1.0) -> float:
	var lt := light_term(light)
	var far := FAR_M * lt * clampf(stance, 0.6, 1.2)
	far *= clampf(observer_acuity, 0.3, GUARD_RANGE)
	if still and light < 0.3:
		far = minf(far, FAR_STILL_DARK)
	var off := target - pos
	var d2 := off.length_squared()
	if d2 >= far * far:
		return 0.0
	var c := cone(facing, off)
	if c <= 0.0:
		return 0.0
	var near := NEAR_M * lt
	var d := sqrt(d2)
	var df := 1.0 if d <= near else 1.0 - (d - near) / maxf(far - near, 0.01)
	return clampf(c * df * lt * stance, 0.0, 1.0)


# ================================================================ alert scalar
static func class_for(a: float) -> int:
	if a >= T_ALARMED:
		return Cls.ALARMED
	if a >= T_SEARCHING:
		return Cls.SEARCHING
	if a >= T_SUSPICIOUS:
		return Cls.SUSPICIOUS
	if a >= T_NOTICE:
		return Cls.NOTICE
	return Cls.CALM


static func threshold_of(c: int) -> float:
	match c:
		Cls.NOTICE: return T_NOTICE
		Cls.SUSPICIOUS: return T_SUSPICIOUS
		Cls.SEARCHING: return T_SEARCHING
		Cls.ALARMED: return T_ALARMED
	return 0.0


## Fresh event id (never 0).
static func new_event_id() -> int:
	_event_serial += 1
	return _event_serial


static func knows(slot: int, event_id: int) -> bool:
	if slot < 0 or event_id == 0:
		return false
	for k in KNOWN:
		if known[slot * KNOWN + k] == event_id:
			return true
	return false


static func _remember(slot: int, event_id: int) -> void:
	# shift the tiny ring
	for k in range(KNOWN - 1, 0, -1):
		known[slot * KNOWN + k] = known[slot * KNOWN + k - 1]
	known[slot * KNOWN] = event_id


## One think tick of sight. `seen_vis` is the visibility that passed the ray (0 when not seen this tick).
## Gains alert by (3 + 7 vis) x factor x dt, capped by what sight alone may reach; otherwise decays.
## Returns the class after the update.
static func update(slot: int, seen_vis: float, factor: float, target_pos: Vector2, now_ms: int, dt: float) -> int:
	if slot < 0:
		return 0
	var a := alert[slot]
	if seen_vis > VIS_MIN:
		var cap := (SIGHT_CAP_GUARD if guard[slot] == 1 else SIGHT_CAP_CIVILIAN) * 1.0
		cap = minf(cap, factor * MAX_ALERT)
		var gain := (3.0 + 7.0 * seen_vis) * factor * dt
		if a < cap:
			a = minf(cap, a + gain)
		point[slot] = target_pos
		last_ray_ms[slot] = now_ms
	else:
		var rate := DECAY_SEARCHING if cls[slot] >= Cls.SEARCHING else DECAY_CALM
		a = maxf(0.0, a - rate * dt)
	alert[slot] = a
	_settle(slot, now_ms)
	return cls[slot]


## Raise the class at once and never drop it before DROP_GAP_MS has passed (one step at a time).
static func _settle(slot: int, now_ms: int) -> void:
	var want := class_for(alert[slot])
	var cur := cls[slot]
	if want >= cur:
		if want > cur:
			drop_ok_ms[slot] = now_ms + DROP_GAP_MS
		cls[slot] = want
	elif now_ms >= drop_ok_ms[slot]:
		cls[slot] = cur - 1
		drop_ok_ms[slot] = now_ms + DROP_GAP_MS


## Something told or showed this body about an event: add alert unless it is the same recent source (grace).
## Returns true when it counted.
static func stimulate(slot: int, gain: float, at: Vector2, event_id: int, now_ms: int) -> bool:
	if slot < 0:
		return false
	if event_id != 0:
		if knows(slot, event_id) and now_ms < grace_until[slot]:
			return false
		if not knows(slot, event_id):
			_remember(slot, event_id)
		src[slot] = event_id
		grace_until[slot] = now_ms + GRACE_MS
	alert[slot] = minf(MAX_ALERT, alert[slot] + gain)
	point[slot] = at
	_settle(slot, now_ms)
	return true


## Jump straight to a class (a body found, a witnessed crime): alert is raised to at least its threshold + 0.5.
static func set_class_at_least(slot: int, c: int, at: Vector2, now_ms: int) -> void:
	if slot < 0:
		return
	alert[slot] = maxf(alert[slot], threshold_of(c) + 0.5)
	point[slot] = at
	_settle(slot, now_ms)


## Brain inputs for the slot into `into` (0 when the slot is not bound).
static func inputs(slot: int, into: Dictionary, now_ms := -1) -> void:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if slot < 0:
		into["suspicion"] = 0.0
		into["a_notice"] = 0.0
		into["a_susp"] = 0.0
		into["a_search"] = 0.0
		into["a_alarm"] = 0.0
		into["heard"] = 0.0
		return
	var c := cls[slot]
	into["suspicion"] = clampf(alert[slot] / T_ALARMED, 0.0, 1.0)
	into["a_notice"] = 1.0 if c == Cls.NOTICE else 0.0
	into["a_susp"] = 1.0 if c == Cls.SUSPICIOUS else 0.0
	into["a_search"] = 1.0 if c == Cls.SEARCHING else 0.0
	into["a_alarm"] = 1.0 if c == Cls.ALARMED else 0.0
	into["heard"] = 1.0 if now - heard_ms[slot] < 2500 else 0.0


static func class_of(slot: int) -> int:
	return cls[slot] if slot >= 0 else 0


static func point_of(slot: int) -> Vector2:
	return point[slot] if slot >= 0 else Vector2.INF


# ================================================================ hearing
## Occlusion class between a source and a listener. `graph` (StreetGraph, optional) tells who is inside a
## building; `door_state` is the DoorState of the door between them (-1 none, 0 open, 1 closed/locked).
static func occlusion_class(graph: RefCounted, source: Vector2, listener: Vector2, door_state := -1) -> int:
	if graph == null:
		return Occ.SAME_CELL
	var a_in: bool = graph.call("inside", source, 0.0)
	var b_in: bool = graph.call("inside", listener, 0.0)
	if not a_in and not b_in:
		return Occ.SAME_CELL
	if a_in and b_in and source.distance_squared_to(listener) < 16.0:
		return Occ.SAME_CELL
	if door_state == 0:
		return Occ.OPEN_DOOR
	if door_state == 1:
		return Occ.CLOSED_DOOR
	return Occ.OTHER_BUILDING


## A sound at `pos`. Stored in the NpcWorld incident ring (one scan per NPC think tick). `occ` is the class
## measured by the maker (inside a closed building ...), applied to the loudness for every listener.
## Returns the event id.
static func emit_sound(kind: int, pos: Vector2, loudness_m := -1.0, maker := "", occ := Occ.SAME_CELL, sid := -1) -> int:
	_ensure()
	var loud := loudness_m if loudness_m > 0.0 else float(SOUND_LOUDNESS[kind])
	var eid := new_event_id()
	(load(NPC_WORLD) as GDScript).call("report_sound", kind, pos, loud * float(OCC_MULT[occ]), eid, float(SOUND_CAP[kind]), sid)
	return eid


## Alert gain a listener at `here` would get from the loudest live sound (0 when none reaches it) and where
## it seems to come from (fuzzed deterministically by slot and event, scaled by distance over loudness).
## Returns [gain, apparent_pos, event_id].
static func hear(here: Vector2, slot: int) -> Array:
	var b: Array = (load(NPC_WORLD) as GDScript).call("best_sound", here)
	if float(b[0]) <= 0.0:
		return b
	var d := here.distance_to(b[1])
	var h := hash([slot, int(b[2])])
	var ang := float(absi(h) % 628) / 100.0
	var fuzz := 1.5 * clampf(d / 16.0, 0.2, 1.0)
	return [b[0], (b[1] as Vector2) + Vector2(cos(ang), sin(ang)) * fuzz, b[2]]


## Apply hearing for `slot` at `here`: stimulate once per event id, mark `heard`. Returns the gain applied.
static func listen(slot: int, here: Vector2, now_ms: int) -> float:
	if slot < 0:
		return 0.0
	var h := hear(here, slot)
	var g: float = h[0]
	if g <= 0.0:
		return 0.0
	if stimulate(slot, g, h[1], int(h[2]), now_ms):
		heard_ms[slot] = now_ms
		return g
	return 0.0


# ================================================================ persistence (event ids only)
static func serialize() -> Dictionary:
	return {"v": 1, "event_serial": _event_serial}


static func deserialize(d: Dictionary) -> void:
	_event_serial = maxi(_event_serial, int(d.get("event_serial", 0)))
