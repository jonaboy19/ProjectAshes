extends RefCounted
## Shared awareness for the near-NPC layer (docs/design/SIM_HIERARCHY.md: tier 0, at most 24 bodies).
##
## Everything the embodied villagers (villager.gd) and their utility brain (utility_brain.gd) need to
## know about the world beyond their own eyes lives here, as static data with fixed-size storage, so
## a decision costs a few array scans and no allocation:
##  - incidents: fires, fights, crimes, festivals, screams. Any system reports one
##    (NpcWorld.report(Kind.FIRE, pos, radius, seconds)); villagers within reach react by brain input.
##  - the player's drawn weapon (blocking or mid swing, latched for a moment) and how close it is.
##  - movers: carts/horses (group "vehicle") and the mounted player, with velocity, for stepping aside.
##  - fields: fenced crop rectangles per settlement (SettlementBuilder registers them) that only farmers enter.
##  - spots: one SmartObjects world (scripts/living_world/smart_objects.gd) filled per settlement on first
##    use from the city plan (building_spots), the plaza stalls, benches, chapel/well/inn and the job
##    workplaces of scripts/realm/work.gd, so work/shop/sit/pray/fetch-water have real places.
##  - lines: short barks (greetings, gossip, alarms) picked deterministically per person.
##  - crime: report_crime() finds the villagers who saw it, makes them shout and run for a guard, and feeds
##    the witness count to society.commit_crime (existing API).
## Distant tiers never touch this: WorldSim / sprites / VAT stay as they were.

const StreetGraph := preload("res://scripts/population/street_graph.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const Perception := preload("res://scripts/population/perception.gd")
const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const DoorModel := preload("res://scripts/world/door_model.gd")
const Search := preload("res://scripts/population/search.gd")
const AlertNet := preload("res://scripts/population/alert_net.gd")
const Takedown := preload("res://scripts/combat/takedown.gd")
const BRAIN := "res://scripts/population/utility_brain.gd"

enum Kind { FIRE, FIGHT, CRIME, FESTIVAL, SCREAM, FUNERAL, SOUND, CALL_FOR_HELP, BODY_FOUND, SUSPICIOUS }

const SLOTS := 16
const REFRESH_MS := 400
const ARMED_LATCH_MS := 3500
const ARMED_NEAR := 2.5
const ARMED_FAR := 7.0
const FIRE_DANGER_NEAR := 3.0
const FIRE_DANGER_FAR := 9.0
const FIRE_REACH := 45.0
const CRIME_SIGHT := 26.0
const CRIME_HEARING := 40.0
const MOVER_LOOKAHEAD := 3.0
const MOVER_CLEAR := 2.6
const DECIDE_PER_FRAME := 3
const MAX_BUBBLES := 4
const FUNERAL_REACH := 55.0
## Longest bread line (people) a settlement forms, and the gap between two people in it.
const QUEUE_MAX := 8
const QUEUE_GAP := 0.85
## A swing of the drawn weapon this close to a villager is an assault (once per ASSAULT_COOLDOWN_MS).
const ASSAULT_RANGE := 1.9
const ASSAULT_COOLDOWN_MS := 20000

# ------------------------------------------------------------------ incidents
static var _i_kind := PackedInt32Array()
static var _i_pos := PackedVector2Array()
static var _i_rad := PackedFloat32Array()
static var _i_str := PackedFloat32Array()
static var _i_until := PackedInt32Array()
static var _i_sid := PackedInt32Array()
static var _i_serial := PackedInt32Array()
static var _i_eid := PackedInt32Array()      # event id (sounds: Perception.emit_sound)
static var _i_cap := PackedFloat32Array()    # sounds: the most alert one event can give
static var _serial := 0
static var _ready_store := false

# ------------------------------------------------------------------ shared scan (every REFRESH_MS)
static var _scan_ms := -100000
static var _armed_until := -100000
static var _player_pos := Vector2.INF
static var _player_vel := Vector2.ZERO
static var _player_mounted := false
static var _player_crouch := false
static var _player_armed := false
static var _player_running := false
static var _player_hide_spot := -1       # search.gd spot the crouched player is hidden in (-1 none)
static var _wanted := {}                 # sid -> [expires_ms, bool] cached Society bounty > 0
static var _mover_pos := PackedVector2Array()
static var _mover_vel := PackedVector2Array()
static var _mover_n := 0
static var _prev_nodes := {}             # instance id -> Vector2 (previous position) for velocity
static var _decide_frame := -1
static var _decide_used := 0
static var bubbles_shown := 0
## QA: when true the near-NPC layer adds its script time here, in microseconds, by kind of callback so a cost can be
## expressed per 60 Hz frame whatever the real frame rate: villager physics ticks (prof_usec / prof_calls), micro actors
## and the director per rendered frame (prof_frame_usec), the PopulationLOD refresh (prof_lod_usec / prof_lod_calls,
## which runs every 0.25 s, about once per 15 frames).
static var profile := false
static var prof_usec := 0
static var prof_calls := 0
static var prof_frame_usec := 0
static var prof_lod_usec := 0
static var prof_lod_calls := 0

# ------------------------------------------------------------------ fields / spots
static var _fields := {}                 # sid -> Array of [centre, unit x axis, half extents]
static var smart: SmartObjects
static var _spots_done := {}             # sid -> true
static var _places := {}                 # sid -> Dictionary (stalls, benches, posts, patrol route)
static var _rumour_cache := {}           # sid -> [expires_ms, Array[String]]
static var _queues := {}                 # sid -> Array of person ids waiting at the bread stall (front first)
static var _assault_ms := -100000
static var _realm_sync_ms := -100000
static var _lamp_sync_ms := -100000
static var _fire_nodes := {}             # sid -> Node3D (the burning thing for a realm fire emergency)


static func _ensure_store() -> void:
	if _ready_store:
		return
	_ready_store = true
	_i_kind.resize(SLOTS)
	_i_pos.resize(SLOTS)
	_i_rad.resize(SLOTS)
	_i_str.resize(SLOTS)
	_i_until.resize(SLOTS)
	_i_sid.resize(SLOTS)
	_i_serial.resize(SLOTS)
	_i_eid.resize(SLOTS)
	_i_cap.resize(SLOTS)
	_i_eid.fill(0)
	_i_until.fill(0)
	_mover_pos.resize(8)
	_mover_vel.resize(8)


## Forget everything (tests, new game).
static func reset() -> void:
	_ready_store = false
	_serial = 0
	_decide_frame = -1
	_scan_ms = -100000
	_armed_until = -100000
	_player_pos = Vector2.INF
	_mover_n = 0
	_prev_nodes.clear()
	_fields.clear()
	_spots_done.clear()
	_places.clear()
	_rumour_cache.clear()
	_queues.clear()
	_assault_ms = -100000
	_realm_sync_ms = -100000
	_lamp_sync_ms = -100000
	_fire_nodes.clear()
	smart = null
	bubbles_shown = 0
	_wanted.clear()
	_player_crouch = false
	_player_armed = false
	_player_running = false
	Perception.reset()
	Witness.reset()
	Evidence.reset()
	Search.reset()
	AlertNet.reset()
	Takedown.reset()
	_player_hide_spot = -1
	_ensure_store()


# ================================================================ incidents
## Report something noteworthy at `pos`. A second report of the same kind within 6 m refreshes the first.
## Returns the incident's slot. Fights and festivals also become UtilityBrain notices (watch / gather).
static func report(kind: int, pos: Vector2, radius := 20.0, seconds := 20.0, strength := 1.0, sid := -1) -> int:
	_ensure_store()
	var now := Time.get_ticks_msec()
	var slot := -1
	var oldest := 0
	var oldest_until := 1 << 60
	for i in SLOTS:
		if _i_until[i] > now and _i_kind[i] == kind and _i_pos[i].distance_squared_to(pos) < 36.0:
			slot = i
			break
		var u := _i_until[i] if _i_until[i] > now else 0
		if u < oldest_until:
			oldest_until = u
			oldest = i
	if slot < 0:
		slot = oldest
	_serial += 1
	_i_kind[slot] = kind
	_i_pos[slot] = pos
	_i_rad[slot] = radius
	_i_str[slot] = clampf(strength, 0.0, 1.0)
	_i_until[slot] = now + int(seconds * 1000.0)
	_i_sid[slot] = sid
	_i_serial[slot] = _serial
	if kind == Kind.FIGHT or kind == Kind.FESTIVAL:
		(load(BRAIN) as GDScript).call("notice", pos, strength, seconds)
	elif kind == Kind.FUNERAL:
		pass       # mourners react through nearest(Kind.FUNERAL), not as a spectacle
	return slot


## A sound (Perception.emit_sound): the ring slot of its kind and place is refreshed, else the oldest is reused.
## `loudness` is the effective radius in metres; listeners read it with sound_at().
static func report_sound(sound_kind: int, pos: Vector2, loudness: float, event_id: int, cap: float, sid := -1) -> int:
	var slot := report(Kind.SOUND, pos, loudness, 3.0, clampf(loudness / 40.0, 0.05, 1.0), sid)
	_i_eid[slot] = event_id
	_i_cap[slot] = cap
	_i_aux_kind_set(slot, sound_kind)
	return slot


static var _i_sound_kind := PackedInt32Array()


static func _i_aux_kind_set(slot: int, k: int) -> void:
	if _i_sound_kind.size() != SLOTS:
		_i_sound_kind.resize(SLOTS)
	_i_sound_kind[slot] = k


## Number of live sounds in the ring.
static func sound_count() -> int:
	if not _ready_store:
		return 0
	var now := Time.get_ticks_msec()
	var n := 0
	for i in SLOTS:
		if _i_until[i] > now and _i_kind[i] == Kind.SOUND:
			n += 1
	return n


const HEAR_SLOPE := 0.15


## The sound that would alert a listener at `here` most: [gain, pos, event_id] ([0.0, INF, 0] when none reaches it).
## gain = clamp(1 + (loudness_eff - distance) * HEAR_SLOPE, 1, cap of its kind), only inside the effective loudness.
static func best_sound(here: Vector2) -> Array:
	var best := [0.0, Vector2.INF, 0]
	if not _ready_store:
		return best
	var now := Time.get_ticks_msec()
	for i in SLOTS:
		if _i_until[i] <= now or _i_kind[i] != Kind.SOUND:
			continue
		var d := here.distance_to(_i_pos[i])
		if d >= _i_rad[i]:
			continue
		var g := clampf(1.0 + (_i_rad[i] - d) * HEAR_SLOPE, 1.0, _i_cap[i])
		if g > float(best[0]):
			best = [g, _i_pos[i], _i_eid[i]]
	return best


static func incident_alive(slot: int) -> bool:
	return _ready_store and slot >= 0 and slot < SLOTS and _i_until[slot] > Time.get_ticks_msec()


static func incident_pos(slot: int) -> Vector2:
	return _i_pos[slot]


static func incident_kind(slot: int) -> int:
	return _i_kind[slot]


static func incident_serial(slot: int) -> int:
	return _i_serial[slot]


## Slot of the nearest live incident of `kind` within `reach` of `here` (-1 when none).
static func nearest(kind: int, here: Vector2, reach: float) -> int:
	if not _ready_store:
		return -1
	var now := Time.get_ticks_msec()
	var best := -1
	var best_d := reach * reach
	for i in SLOTS:
		if _i_until[i] <= now or _i_kind[i] != kind:
			continue
		var d := _i_pos[i].distance_squared_to(here)
		if d < best_d:
			best_d = d
			best = i
	return best


## 0..1 danger from fires (and screams) near `here`: a burning thing is worth running from close up.
static func fire_danger(here: Vector2) -> float:
	var slot := nearest(Kind.FIRE, here, FIRE_DANGER_FAR)
	if slot < 0:
		return 0.0
	var d := here.distance_to(_i_pos[slot])
	return (1.0 - smoothstep(FIRE_DANGER_NEAR, FIRE_DANGER_FAR, d)) * _i_str[slot]


## 0..1 interest of a fire further off than the run-away distance: worth fetching water for.
static func fire_interest(here: Vector2) -> float:
	var slot := nearest(Kind.FIRE, here, FIRE_REACH)
	if slot < 0:
		return 0.0
	var d := here.distance_to(_i_pos[slot])
	if d < FIRE_DANGER_NEAR:
		return 0.0
	return (1.0 - clampf(d / FIRE_REACH, 0.0, 1.0)) * _i_str[slot]


## Water thrown at fire `slot`: it shrinks and dies sooner the more people help.
static func douse(slot: int, amount := 0.12) -> void:
	if not incident_alive(slot) or _i_kind[slot] != Kind.FIRE:
		return
	_i_str[slot] = maxf(_i_str[slot] - amount, 0.0)
	if _i_str[slot] <= 0.02:
		_i_until[slot] = 0


## 0..1 alarm from screams / a nearby crime that `here` heard (not saw): strength fades with distance.
static func alarm_at(here: Vector2, kind := -1) -> float:
	if not _ready_store:
		return 0.0
	var now := Time.get_ticks_msec()
	var top := 0.0
	for i in SLOTS:
		if _i_until[i] <= now:
			continue
		var k := _i_kind[i]
		if kind >= 0 and k != kind:
			continue
		if kind < 0 and k != Kind.SCREAM and k != Kind.CRIME:
			continue
		var d := here.distance_to(_i_pos[i])
		if d > _i_rad[i]:
			continue
		top = maxf(top, (1.0 - d / maxf(_i_rad[i], 1.0)) * _i_str[i])
	return top


static func clear_incidents() -> void:
	_ensure_store()
	_i_until.fill(0)


# ================================================================ shared scan
## Refresh the cached player/vehicle view at most every REFRESH_MS for all villagers together.
static func refresh(tree: SceneTree) -> void:
	_ensure_store()
	var now := Time.get_ticks_msec()
	if tree == null or now - _scan_ms < REFRESH_MS:
		return
	var dt := clampf(float(now - _scan_ms) / 1000.0, 0.05, 2.0)
	_scan_ms = now
	var pl := tree.get_first_node_in_group("player") as Node3D
	if pl != null:
		var p := Vector2(pl.global_position.x, pl.global_position.z)
		_player_vel = (p - _player_pos) / dt if _player_pos != Vector2.INF and _player_pos.distance_to(p) < 6.0 else Vector2.ZERO
		_player_pos = p
		_player_mounted = pl.has_method("is_mounted") and bool(pl.call("is_mounted"))
		var armed := bool(pl.get("blocking")) or float(pl.get("_swing")) > 0.0 or bool(pl.get_meta("weapon_drawn", false))
		_player_crouch = pl.get("crouching") == true
		_player_armed = armed
		_player_running = _player_vel.length() > 3.2
		_player_hide_spot = Search.hidden_spot(p, _player_crouch and not _player_mounted)
		Perception.set_environment(WorldSim.time_of_day, 1.0 if _raining(tree) else 0.0,
			pl.get("_indoors") == true, bool(pl.get_meta("lantern_lit", false)))
		if armed:
			_armed_until = now + ARMED_LATCH_MS
	else:
		_player_pos = Vector2.INF
	_mover_n = 0
	if _player_mounted and _player_pos != Vector2.INF:
		_push_mover(_player_pos, _player_vel)
	for n in tree.get_nodes_in_group("vehicle"):
		var node := n as Node3D
		if node == null or _mover_n >= 8:
			continue
		var id := node.get_instance_id()
		var q := Vector2(node.global_position.x, node.global_position.z)
		var prev: Vector2 = _prev_nodes.get(id, q)
		_prev_nodes[id] = q
		_push_mover(q, (q - prev) / dt)
	if _prev_nodes.size() > 64:
		_prev_nodes.clear()
	# Nodes that joined the "fire_hazard" group burn for as long as they exist.
	for n in tree.get_nodes_in_group("fire_hazard"):
		var node := n as Node3D
		if node != null:
			report(Kind.FIRE, Vector2(node.global_position.x, node.global_position.z), 25.0, 1.5, float(node.get_meta("fire_strength", 1.0)))
	_watch_assault(tree, now)
	if not Search.searches.is_empty():
		Search.tick(now, smart)
	if Takedown.down_count() > 0:
		Takedown.tick(now)
	if Witness.pending_count() > 0:
		Witness.tick(now, _society())
	if now - _lamp_sync_ms > 5000:
		_lamp_sync_ms = now
		sync_lamps(tree)
	if now - _realm_sync_ms > 5000:
		_realm_sync_ms = now
		sync_realm_incidents(tree)


## Lit street lamps near the player become light sources for Perception.light_at (analytic, no render): the
## OmniLight3D nodes of group "street_lamp" (settlement_builder.gd) whose energy is on, nearest 32 within 60 m.
static func sync_lamps(tree: SceneTree) -> void:
	Perception.clear_lights()
	if _player_pos == Vector2.INF:
		return
	var near: Array = []
	for n in tree.get_nodes_in_group("street_lamp"):
		var l := n as OmniLight3D
		if l == null or l.light_energy < 0.05 or not l.is_visible_in_tree():
			continue
		var p := Vector2(l.global_position.x, l.global_position.z)
		var d2 := p.distance_squared_to(_player_pos)
		if d2 < 3600.0:
			near.append([d2, p, l.omni_range])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for e: Array in near.slice(0, Perception.MAX_LIGHTS):
		Perception.register_light(e[1], float(e[2]), 0.6)


static func _raining(tree: SceneTree) -> bool:
	return (load(BRAIN) as GDScript).call("is_raining", tree)


## Stance multiplier of the player for vision (crouch 0.5, walk 1, run 1.25, mounted 1.4).
static func player_stance() -> float:
	if _player_hide_spot >= 0:
		return Perception.STANCE_HIDDEN
	return Perception.stance_term(_player_crouch, _player_running, _player_mounted)


## The search spot the crouched player is hidden in (-1 none).
static func player_hide_spot() -> int:
	return _player_hide_spot


static func set_player_hide_spot(spot: int) -> void:
	_player_hide_spot = spot


static func player_still() -> bool:
	return _player_vel.length() < 0.3


## How suspicious the player looks to people of settlement `sid` right now (Perception.suspicion_factor).
static func player_suspicion(sid: int) -> float:
	var now := Time.get_ticks_msec()
	var w: Array = _wanted.get(sid, [])
	if w.is_empty() or int(w[0]) < now:
		var soc := _society()
		var wanted := soc != null and sid >= 0 and int(soc.call("bounty", sid)) > 0
		w = [now + 2000, wanted]
		_wanted[sid] = w
	return Perception.suspicion_factor(_player_crouch, _player_armed, bool(w[1]), WorldSim.time_of_day)


## A door that person `person` of settlement `sid` cannot pass: a locked (or jammed) door near `door_pos`
## whose household they do not belong to. False for no known door, broken doors and own-lot doors.
static func door_blocked(sid: int, door_pos: Vector2, person: int) -> bool:
	if DoorModel.count() == 0:
		return false
	var d: RefCounted = DoorModel.door_near(door_pos, 2.5)
	if d == null:
		return false
	var h := {"keys": [], "master": person >= 0 and person < WorldSim.job.size() and WorldSim.job[person] == 3}
	var owner: Vector2 = d.get("owner_home")
	if owner != Vector2.INF and sid >= 0 and sid < WorldGen.settlements.size() and person >= 0:
		var home: Vector2 = WorldSim._spot(WorldGen.settlements[sid], 0, person)
		if owner.distance_to(home) < 7.0:
			(h["keys"] as Array).append(DoorModel.lot_key(owner))
	return bool(d.call("blocked_for", h))


## A drawn weapon swung beside a villager is an assault: witnesses shout and run for the watch, the town's
## society module records it (the one place a swing at a person becomes a real crime).
static func _watch_assault(tree: SceneTree, now: int) -> void:
	if _player_pos == Vector2.INF or now - _assault_ms < ASSAULT_COOLDOWN_MS:
		return
	var pl := tree.get_first_node_in_group("player") as Node3D
	if pl == null or float(pl.get("_swing")) <= 0.0:
		return
	var victim := Vector2.INF
	for n in tree.get_nodes_in_group("villager"):
		var v := n as Node3D
		if v == null:
			continue
		var vp := Vector2(v.global_position.x, v.global_position.z)
		if vp.distance_to(_player_pos) <= ASSAULT_RANGE:
			# A silent takedown from behind is judged when it lands (Takedown / villager.go_down), not as a brawl.
			if v.has_method("perception_facing") and v.has_method("alert_class"):
				var pn := int(v.get("person"))
				var is_guard := pn >= 0 and pn < WorldSim.job.size() and WorldSim.job[pn] == 3
				if Takedown.can_takedown(_player_pos, vp, v.call("perception_facing"), int(v.call("alert_class")), is_guard):
					continue
			victim = vp
			break
	if victim == Vector2.INF:
		return
	_assault_ms = now
	report_crime(tree, "assault", victim, _sid_at(victim), true)
	report(Kind.FIGHT, victim, 24.0, 10.0, 0.9, _sid_at(victim))


## Settlement id whose area contains `p` (-1 outside every settlement).
static func _sid_at(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for s: Dictionary in WorldGen.settlements:
		var d := p.distance_to(s["pos"])
		if d < float(s["radius"]) * 1.4 and d < best_d:
			best_d = d
			best = int(s["id"])
	return best


## Realm facts that have a place in the street become incidents the near AI reacts to: a settlement fire
## emergency (realm/settlements.gd) burns at a house near the plaza while the player is within earshot, and
## a funeral is held for a recent death. Cheap: a few dictionary reads every 5 s, only for the nearest town.
static func sync_realm_incidents(tree: SceneTree) -> void:
	if _player_pos == Vector2.INF:
		return
	var sid := _sid_at(_player_pos)
	if sid < 0:
		return
	var mood := TownMood.mood_of(sid)
	# A festival day (scripts/sim/seasons.gd): the plaza is a spectacle people gather at all day.
	var hour: float = WorldSim.time_of_day
	if String(mood.get("festival", "")) != "" and hour >= 9.5 and hour < 23.5:
		var c: Vector2 = WorldGen.settlements[sid]["pos"]
		report(Kind.FESTIVAL, c, 55.0, 8.0, 0.7, sid)
	var node: Node3D = _fire_nodes.get(sid)
	if bool(mood.get("fire", false)):
		if node == null or not is_instance_valid(node):
			var at := _fire_site(sid)
			if at != Vector2.INF:
				node = Node3D.new()
				node.name = "RealmFire"
				node.set_meta("fire_strength", 0.8)
				node.add_to_group("fire_hazard")
				var host := tree.current_scene
				if host != null:
					host.add_child(node)
					node.global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
					_fire_nodes[sid] = node
					var vfx: Variant = load("res://scripts/vfx/vfx.gd")
					if vfx != null:
						(vfx as GDScript).call("fire_pillar", host, node.global_position, 1.1, 6.0)
	elif node != null:
		if is_instance_valid(node):
			node.remove_from_group("fire_hazard")
			node.queue_free()
		_fire_nodes.erase(sid)


## A house front near the plaza (deterministic per settlement and day) for a fire to break out at.
static func _fire_site(sid: int) -> Vector2:
	var s: Dictionary = WorldGen.settlements[sid]
	var lots: Array = (s.get("plan", {}) as Dictionary).get("lots", [])
	if lots.is_empty():
		return s["pos"] + Vector2(6.0, 4.0)
	var lot: Dictionary = lots[posmod(hash(sid * 7 + WorldSim.day), lots.size())]
	var yaw: float = lot["yaw"]
	return (lot["pos"] as Vector2) + Vector2(sin(yaw), cos(yaw)) * 3.6


static func _push_mover(p: Vector2, v: Vector2) -> void:
	if _mover_n >= 8:
		return
	_mover_pos[_mover_n] = p
	_mover_vel[_mover_n] = v
	_mover_n += 1


static func player_position() -> Vector2:
	return _player_pos


static func player_mounted() -> bool:
	return _player_mounted


## Set by tests / tools: pretend the player's weapon is (not) drawn for the next few seconds.
static func set_weapon_drawn(on: bool) -> void:
	_armed_until = Time.get_ticks_msec() + ARMED_LATCH_MS if on else -100000


static func player_armed() -> bool:
	return Time.get_ticks_msec() < _armed_until


## 0..1 how hard a drawn weapon presses on someone standing `here` (0 when sheathed or far).
static func armed_pressure(here: Vector2) -> float:
	if not player_armed() or _player_pos == Vector2.INF:
		return 0.0
	return 1.0 - smoothstep(ARMED_NEAR, ARMED_FAR, here.distance_to(_player_pos))


## Push (length 0..1) that sends `here` out of the way of an oncoming cart or rider; zero when clear.
static func mover_push(here: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for i in _mover_n:
		var v := _mover_vel[i]
		var speed2 := v.length_squared()
		if speed2 < 0.36:
			continue
		var rel := here - _mover_pos[i]
		if rel.length_squared() > 400.0:
			continue
		var t := clampf(rel.dot(v) / speed2, 0.0, MOVER_LOOKAHEAD)
		var closest := rel - v * t
		var d := closest.length()
		if d >= MOVER_CLEAR:
			continue
		var side := closest / d if d > 0.05 else Vector2(-v.y, v.x).normalized()
		push += side * (1.0 - d / MOVER_CLEAR) * (1.0 - 0.5 * t / MOVER_LOOKAHEAD)
	return push.limit_length(1.5)


## Shared per-physics-frame allowance for utility decisions (the slicing of the brain across frames).
static func take_decide_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _decide_frame:
		_decide_frame = frame
		_decide_used = 0
	if _decide_used >= DECIDE_PER_FRAME:
		return false
	_decide_used += 1
	return true


# ================================================================ fields
## Fenced crop field of settlement `sid` (centre, yaw, half extents in metres). Called while the town is built.
static func register_field(sid: int, c: Vector2, yaw: float, half: Vector2) -> void:
	if not _fields.has(sid):
		_fields[sid] = []
	(_fields[sid] as Array).append([c, Vector2(cos(yaw), -sin(yaw)), half])


static func field_count(sid: int) -> int:
	return (_fields.get(sid, []) as Array).size()


static func in_field(sid: int, p: Vector2, margin := 0.0) -> bool:
	for f: Array in _fields.get(sid, []):
		var d: Vector2 = p - (f[0] as Vector2)
		var ax: Vector2 = f[1]
		var h: Vector2 = f[2]
		if absf(d.dot(ax)) <= h.x + margin and absf(d.dot(Vector2(-ax.y, ax.x))) <= h.y + margin:
			return true
	return false


## Steering push (length 0..1) out of the fields near `p` for someone who has no business there.
static func field_push(sid: int, p: Vector2, reach := 2.5) -> Vector2:
	var out := Vector2.ZERO
	for f: Array in _fields.get(sid, []):
		var c: Vector2 = f[0]
		var h: Vector2 = f[2]
		if c.distance_squared_to(p) > (h.length() + reach) * (h.length() + reach):
			continue
		var d: Vector2 = p - c
		var ax: Vector2 = f[1]
		var az := Vector2(-ax.y, ax.x)
		var lx := d.dot(ax)
		var lz := d.dot(az)
		var ox := h.x + reach - absf(lx)
		var oz := h.y + reach - absf(lz)
		if ox <= 0.0 or oz <= 0.0:
			continue
		# leave across the nearer edge
		if ox < oz:
			out += ax * signf(lx if lx != 0.0 else 1.0) * clampf(ox / reach, 0.0, 1.0)
		else:
			out += az * signf(lz if lz != 0.0 else 1.0) * clampf(oz / reach, 0.0, 1.0)
	return out.limit_length(1.0)


## Nearest point outside every field (for goals that would put a non-farmer among the crops).
static func out_of_fields(sid: int, p: Vector2) -> Vector2:
	var q := p
	for _i in 4:
		if not in_field(sid, q, 0.4):
			return q
		var push := field_push(sid, q, 0.4)
		if push.length_squared() < 0.0001:
			return q
		q += push.normalized() * 2.0
	return q


# ================================================================ spots (smart objects)
const SPOT_TYPES := {
	# work.gd workplace spot kind -> smart object type (scripts/living_world data) or a local type
	"field": "field_row", "well": "well", "barn": "chicken_yard",
	"forge": "anvil", "quench": "bellows", "grinder": "bellows", "ore_pile": "npc_haul",
	"stall": "market_stall", "crate": "npc_haul", "counter": "shop_counter",
	"gate": "guard_post", "market_watch": "guard_post", "wall": "guard_post", "barracks": "guard_post",
	"cart": "npc_haul", "ditch": "field_row", "stack": "npc_haul",
	"tree": "chopping_block", "log_pile": "npc_haul", "sled": "npc_haul",
	"saw_pit": "sawhorse", "frame": "nail_plank", "bench": "sawhorse",
}
const WORK_IDS := ["farmer", "blacksmith", "merchant", "guard", "laborer", "woodcutter"]

## Types this module adds to the data-driven SmartObjects catalogue (same schema as the JSON).
const LOCAL_TYPES := {
	"npc_haul": {
		"slots": [{"stand": [0.0, 0.0, 0.7], "face": 180}], "approach": 0.8,
		"activity": {"loop": ["Life_Mocap_Move_Box", "Life_Mocap_Pick_Place", "Life_Carry_Pick_Up"], "duration": [40, 120], "cycles": [2, 3]},
		"jobs": ["Laborer", "Woodcutter", "Farmer", "Blacksmith"], "acts": ["work"], "hours": [6, 19], "tags": ["work", "haul"],
	},
	"training_dummy": {
		"slots": [{"stand": [0.0, 0.0, 1.1], "face": 180}], "approach": 1.0,
		"activity": {"loop": ["Punch_Jab", "Sword_Attack", "Punch_Cross", "Sword_Attack"], "between": ["Life_Guard_Attention", "Life_Ambient_Wipe_Brow"],
			"cycles": [3, 5], "duration": [30, 90]},
		"acts": ["train"], "hours": [6, 20], "tags": ["train", "loud"],
	},
	# A place to look for someone: doorway, alley, behind a stall, haystack, crate (search.gd claims and checks them).
	"search": {
		"slots": [{"stand": [0.0, 0.0, 0.9], "face": 180}], "approach": 0.9,
		"activity": {"loop": ["Life_Ambient_Look_Around"], "duration": [3, 4], "cycles": [1, 1]},
		"acts": ["search"], "tags": ["search"],
	},
	"wall_idle": {
		"slots": [{"stand": [0.0, 0.0, 0.0], "face": 0}], "approach": 0.6,
		"activity": {"loop": ["Life_Ambient_Shift_Weight", "Life_Ambient_Look_Around"], "between": ["Life_Ambient_Scratch_Head", "Life_Ambient_Check_Sky"],
			"cycles": [1, 2], "duration": [25, 90]},
		"acts": ["rest", "social"], "hours": [7, 21], "tags": ["lean", "rest"],
	},
}


static func spots() -> SmartObjects:
	if smart == null:
		smart = SmartObjects.new()
		for k: String in LOCAL_TYPES:
			if not smart.types.has(k):
				smart.types[k] = (LOCAL_TYPES[k] as Dictionary).duplicate(true)
	return smart


## Fill settlement `sid` with activity spots (idempotent, once per settlement; a town costs a few ms).
## `host` (optional) is where visible props (benches) are parented.
static func ensure_spots(sid: int, host: Node = null) -> void:
	if _spots_done.has(sid) or sid < 0 or sid >= WorldGen.settlements.size():
		return
	_spots_done[sid] = true
	var so := spots()
	var s: Dictionary = WorldGen.settlements[sid]
	so.populate_settlement(s, WorldGen.height)
	var plan: Dictionary = s.get("plan", {})
	var c: Vector2 = s["pos"]
	var graph := StreetGraph.for_settlement(sid) as StreetGraph
	var pr: float = plan.get("plaza_r", 12.0)
	# (Packed arrays are copy-on-write: appending to `places["stalls"] as PackedVector2Array` changed a temporary,
	# so the stall list stayed empty. Fill local arrays and store them.)
	var stall_pts := PackedVector2Array()
	var stall_yaws := PackedFloat32Array()
	var bench_pts := PackedVector2Array()
	var places := {"stalls": stall_pts, "stall_yaw": stall_yaws, "benches": bench_pts,
		"patrol": PackedVector2Array(), "plaza": c, "plaza_r": pr}
	# Market stalls ring the plaza exactly as SettlementBuilder / StreetGraph lay them out.
	var n_stalls := 6 if s["kind"] == "village" else 12
	for i in n_stalls:
		var ang := TAU * i / n_stalls + 0.2
		var sp := c + Vector2(cos(ang), sin(ang)) * (pr - 3.0)
		var yaw := atan2(-cos(ang), -sin(ang))
		stall_pts.append(sp)
		stall_yaws.append(yaw)
		# Keeper behind the counter, customers on the plaza side (market_stall slot frame: +Z is the front).
		so.add("market_stall", Transform3D(Basis(Vector3.UP, yaw), Vector3(sp.x, WorldGen.height(sp.x, sp.y), sp.y)), sid)
	# Benches between the stalls, facing the square.
	var bench_n := mini(4, n_stalls / 2)
	for i in bench_n:
		var ang2 := TAU * (2.0 * i + 1.0) / n_stalls + 0.2
		var bp := c + Vector2(cos(ang2), sin(ang2)) * (pr - 2.2)
		var byaw := atan2(-cos(ang2), -sin(ang2))
		bench_pts.append(bp)
		var h := WorldGen.height(bp.x, bp.y)
		so.add("bench", Transform3D(Basis(Vector3.UP, byaw), Vector3(bp.x, h, bp.y)), sid)
		_add_bench_prop(host, Vector3(bp.x, h, bp.y), byaw)
	# Chatting corners, a hopscotch square and a play patch on the plaza.
	for i in 2:
		var a3 := TAU * (float(i) / 2.0) + 1.0
		var cp := c + Vector2(cos(a3), sin(a3)) * pr * 0.45
		so.add("conversation", Transform3D(Basis(Vector3.UP, a3), Vector3(cp.x, WorldGen.height(cp.x, cp.y), cp.y)), sid)
	var hp := c + Vector2(cos(2.4), sin(2.4)) * pr * 0.35
	so.add("hopscotch", Transform3D(Basis(Vector3.UP, 0.4), Vector3(hp.x, WorldGen.height(hp.x, hp.y), hp.y)), sid)
	var pp := c + Vector2(cos(4.3), sin(4.3)) * pr * 0.3
	so.add("play_area", Transform3D(Basis(Vector3.UP, 1.0), Vector3(pp.x, WorldGen.height(pp.x, pp.y), pp.y)), sid)
	# Places a searcher looks into (doorways, alleys, behind stalls, haystacks, crates).
	Search.populate(so, sid, plan, c, pr, float(s.get("radius", 60.0)), stall_pts, graph, WorldGen.height)
	# People stand about by house fronts too.
	var lots: Array = plan.get("lots", [])
	var k := 0
	for lot: Dictionary in lots:
		k += 1
		if k % 4 != 0:
			continue
		var yaw2: float = lot["yaw"]
		var face := Vector2(sin(yaw2), cos(yaw2))
		var wp: Vector2 = (lot["pos"] as Vector2) + face * 3.4 + Vector2(-face.y, face.x) * 2.2
		if graph != null:
			wp = graph.push_out(wp, 0.6)
		so.add("wall_idle", Transform3D(Basis(Vector3.UP, yaw2 + PI), Vector3(wp.x, WorldGen.height(wp.x, wp.y), wp.y)), sid)
	# The training yard: four dummies in a row facing the plaza, a hay-bale target and a weapon rack beside each pair.
	var yard := Schedule.spot(s, Schedule.Phase.TRAIN, 0, 1)
	var to_plaza := (c - yard).normalized() if c.distance_to(yard) > 1.0 else Vector2.DOWN
	var row_axis := Vector2(-to_plaza.y, to_plaza.x)
	var yaw_t := atan2(to_plaza.x, to_plaza.y)
	for ti in 4:
		var dp := yard + row_axis * (float(ti) * 2.4 - 3.6)
		if graph != null:
			dp = graph.push_out(dp, 0.9)
		so.add("training_dummy", Transform3D(Basis(Vector3.UP, yaw_t + PI), Vector3(dp.x, WorldGen.height(dp.x, dp.y), dp.y)), sid)
		_add_prop(host, "hay", dp - to_plaza * 1.5, yaw_t)
	_add_prop(host, "weapon_rack", yard + row_axis * 6.4, yaw_t)
	# Job workplaces from work.gd: each spot becomes the matching smart object, so a farmer hoes at the
	# farm's field, the smith hammers at the smithy and guards hold the gate post the player's shifts use.
	var work := _work_module()
	if work != null:
		for place: Dictionary in work.call("workplaces", sid):
			var centre: Vector2 = place["center"]
			for sp: Dictionary in place["spots"]:
				var type: String = SPOT_TYPES.get(String(sp["kind"]), "")
				if type == "" or not so.types.has(type):
					continue
				var p2: Vector2 = sp["pos"]
				if graph != null:
					p2 = graph.push_out(p2, 1.6)
				var yaw3 := atan2(centre.x - p2.x, centre.y - p2.y) + PI
				so.add(type, Transform3D(Basis(Vector3.UP, yaw3), Vector3(p2.x, WorldGen.height(p2.x, p2.y), p2.y)), sid)
				if type == "field_row":
					# a field is several rows: lay a second beside the first
					var q := p2 + Vector2(cos(yaw3), -sin(yaw3)) * 2.4
					so.add(type, Transform3D(Basis(Vector3.UP, yaw3), Vector3(q.x, WorldGen.height(q.x, q.y), q.y)), sid)
	# Patrol loop for guards: plaza, inn front, each gate / a few wall points, back.
	var route: PackedVector2Array = places["patrol"]
	route.append(c + Vector2(pr * 0.6, 0.0))
	if graph != null and graph.inn_door != Vector2.INF:
		route.append(graph.inn_door)
	route.append(c + Vector2(0.0, pr * 0.7))
	var gates: Array = plan.get("gates", [])
	var wall_r := float(plan.get("wall_radius", float(s["radius"]) * 0.95))
	for g in gates:
		var gp := c + Vector2(cos(float(g)), sin(float(g))) * (wall_r - 4.0)
		route.append(graph.push_out(gp, 0.8) if graph != null else gp)
	if gates.is_empty():
		route.append(c + Vector2(-pr * 0.8, -pr * 0.4))
	route.append(c + Vector2(-pr * 0.5, pr * 0.2))
	places["patrol"] = route
	places["stalls"] = stall_pts
	places["stall_yaw"] = stall_yaws
	places["benches"] = bench_pts
	_places[sid] = places


static func _work_module() -> RefCounted:
	var life := _life()
	if life == null or life.get("realm") == null:
		return null
	return (life.get("realm") as RefCounted).call("mod", "work") as RefCounted


static func _add_bench_prop(host: Node, at: Vector3, yaw: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var node := Assets.building_node("bench", false)
	if node == null:
		return
	node.position = at
	node.rotation.y = yaw + PI
	node.add_to_group("npc_prop")
	host.add_child(node)


static func _add_prop(host: Node, key: String, p: Vector2, yaw: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	var node := Assets.building_node(key, false)
	if node == null:
		return
	node.position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	node.rotation.y = yaw
	node.add_to_group("npc_prop")
	host.add_child(node)


static func places_of(sid: int) -> Dictionary:
	return _places.get(sid, {})


## Waypoint `i` of the guard patrol loop of settlement `sid` (Vector2.INF without a route).
static func patrol_point(sid: int, i: int) -> Vector2:
	var route: PackedVector2Array = (_places.get(sid, {}) as Dictionary).get("patrol", PackedVector2Array())
	if route.is_empty():
		return Vector2.INF
	return route[posmod(i, route.size())]


static func patrol_size(sid: int) -> int:
	return ((_places.get(sid, {}) as Dictionary).get("patrol", PackedVector2Array()) as PackedVector2Array).size()


## Nearest shelter from rain outside a house door: the canopy side of a market stall.
static func nearest_stall_cover(sid: int, p: Vector2, reach := 25.0) -> Vector2:
	var pl: Dictionary = _places.get(sid, {})
	var stalls: PackedVector2Array = pl.get("stalls", PackedVector2Array())
	var yaws: PackedFloat32Array = pl.get("stall_yaw", PackedFloat32Array())
	var best := Vector2.INF
	var best_d := reach * reach
	for i in stalls.size():
		var d := p.distance_squared_to(stalls[i])
		if d < best_d:
			best_d = d
			best = stalls[i] + Vector2(sin(yaws[i]), cos(yaws[i])) * 1.3
	return best


## Best free smart object slot for `filter` near `here` (see SmartObjects.find). Returns [spot, slot] or [].
## `avoid`/`avoid_until` is the asking brain's short-term memory of danger spots.
static func find_spot(person: int, filter: Dictionary, here: Vector2, radius: float, avoid := PackedVector2Array(),
		avoid_r := 0.0) -> Array:
	if smart == null:
		return []
	return smart.find(Vector3(here.x, 0.0, here.y), filter, radius, person, avoid, avoid_r)


# ================================================================ search and alert sharing
## Where `person` should look next in the search for an alarm at `at`: the approach point of a claimed search spot.
## Returns [goal, look] ([] when the searcher cap is reached or no spot is left: they hold and watch instead).
static func search_goal(person: int, here: Vector2, at: Vector2, sid: int) -> Array:
	if at == Vector2.INF:
		return []
	var now := Time.get_ticks_msec()
	var slot := Perception.slot_of(person)
	var eid := int(Perception.src[slot]) if slot >= 0 else 0
	var id := Search.begin(at, sid, now, eid)
	var spot := Search.claim(id, person, here, spots())
	if spot < 0:
		return []
	return [Search.approach(spot, spots()), Search.spot_pos(spot)]


## Everyone embodied who could hear a shout: [{person, pos, guard, node}] from the "villager" group (tier 0 only).
static func alert_listeners(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("villager"):
		var v := n as Node3D
		if v == null or not v.has_method("hear_alarm"):
			continue
		var p := int(v.get("person"))
		out.append({"person": p, "pos": Vector2(v.global_position.x, v.global_position.z),
			"guard": p >= 0 and p < WorldSim.job.size() and WorldSim.job[p] == 3, "node": v})
	return out


# ================================================================ queue, funeral, festival
## The bread stall of settlement `sid`: the first plaza stall, the counter side outward. [position, yaw].
static func bread_stall(sid: int) -> Array:
	var pl: Dictionary = _places.get(sid, {})
	var stalls: PackedVector2Array = pl.get("stalls", PackedVector2Array())
	if stalls.is_empty():
		return []
	var yaws: PackedFloat32Array = pl["stall_yaw"]
	return [stalls[0], yaws[0]]


## How many people stand in the bread line of `sid` right now (people who left or went indoors drop out).
static func queue_length(sid: int) -> int:
	var q: Array = _queues.get(sid, [])
	var n := 0
	for p: int in q:
		if _body_of(p) != null:
			n += 1
	return n


static func _body_of(p: int) -> Node3D:
	return (load(BRAIN) as GDScript).call("body_of", p) as Node3D


## Join (or keep a place in) the bread line; returns [spot, facing] or [] when the line is full or there is no stall.
static func queue_spot(sid: int, person: int) -> Array:
	var st := bread_stall(sid)
	if st.is_empty():
		return []
	var q: Array = _queues.get(sid, [])
	var idx := q.find(person)
	if idx < 0:
		var live: Array = []
		for p: int in q:
			if _body_of(p) != null:
				live.append(p)
		q = live
		if q.size() >= QUEUE_MAX:
			_queues[sid] = q
			return []
		q.append(person)
		idx = q.size() - 1
		_queues[sid] = q
	var stall_p: Vector2 = st[0]
	var yaw: float = st[1]
	var front := Vector2(sin(yaw), cos(yaw))        # towards the customers' side
	var side := Vector2(-front.y, front.x)
	# A line that bends away from the counter: first person at the counter, the rest back and to one side.
	var spot := stall_p + front * (1.7 + float(idx) * QUEUE_GAP) + side * (float(idx) * 0.18)
	return [spot, -front]


static func queue_leave(sid: int, person: int) -> void:
	if _queues.has(sid):
		(_queues[sid] as Array).erase(person)


## A place among the mourners round a funeral at `at` (a loose half circle facing it).
static func mourn_spot(at: Vector2, person: int) -> Vector2:
	var h := absi(hash(person * 41 + 3))
	var a := float(h % 628) / 100.0
	return at + Vector2(cos(a), sin(a)) * (2.6 + float((h / 628) % 100) / 100.0 * 3.4)


# ================================================================ crime
## A crime happened at `pos`. Villagers within sight (not behind a house) who are not looking away
## become witnesses: they shout and run for a guard; guards within earshot come to look. The witness
## count goes to society.commit_crime (existing API). Returns that call's result plus {"seen_by": n}.
static func report_crime(tree: SceneTree, kind: String, pos: Vector2, sid := -1, culprit_is_player := true, leave_traces := true) -> Dictionary:
	_ensure_store()
	var now := Time.get_ticks_msec()
	var cands: Array = []
	var heard := 0
	if tree != null:
		refresh(tree)        # light / stance for this very moment (rate limited, cheap)
		var graph := StreetGraph.for_settlement(sid) as StreetGraph if sid >= 0 else null
		var stance := player_stance() if culprit_is_player else 1.0
		var light := Perception.light_at(pos)
		for n in tree.get_nodes_in_group("villager"):
			var v := n as Node3D
			if v == null or not v.has_method("witness"):
				continue
			var vp := Vector2(v.global_position.x, v.global_position.z)
			var d := vp.distance_to(pos)
			if d > CRIME_HEARING:
				continue
			# Seen = the culprit's visibility for THIS person (cone, light, distance, stance, line), not a flat roll.
			var vis := 0.0
			if d <= CRIME_SIGHT:
				var clear := graph == null or graph.clear_line(vp, pos, 0.05)
				var facing := Vector2.ZERO
				var acu := 1.0
				if v.has_method("perception_facing"):
					facing = v.call("perception_facing")
					acu = float(v.call("perception_acuity"))
				vis = Witness.sight(vp, facing, acu, pos, light, stance, clear)
			var saw := vis >= Witness.SEEN_VIS
			if v.call("witness", pos, kind, saw, culprit_is_player):
				if saw:
					var person := int(v.get("person"))
					cands.append({"id": Witness.witness_id(sid, person), "person": person, "vis": vis,
						"guard": person >= 0 and person < WorldSim.job.size() and WorldSim.job[person] == 3})
				else:
					heard += 1
	report(Kind.CRIME, pos, CRIME_HEARING, 30.0, 1.0, sid)
	if leave_traces:
		Evidence.leave_traces(kind, pos, sid, now)
	var out := {"ok": false, "seen_by": cands.size(), "heard_by": heard, "pending": false}
	var soc := _society()
	if soc != null and sid >= 0 and culprit_is_player:
		# Reporting is a task: the crime reaches Society when a witness reaches a guard or after the timeout.
		var cid := Witness.begin(kind, sid, pos, cands, now, soc, true)
		out["case"] = cid
		if cid > 0:
			var c := Witness.case_of(cid)
			if c["status"] == "committed":
				var res: Dictionary = (c["result"] as Dictionary).duplicate()
				res["seen_by"] = cands.size()
				res["case"] = cid
				return res
			out["pending"] = true
	return out


static func _society() -> RefCounted:
	var life := _life()
	if life == null or life.get("realm") == null:
		return null
	return (life.get("realm") as RefCounted).call("mod", "society") as RefCounted


static func _life() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null


## How the settlement regards the player: 1 adored .. -1 despised (society reputation, read only).
static func regard_of_player(sid: int) -> float:
	var soc := _society()
	if soc == null or sid < 0:
		return 0.0
	var group := "city:%d" % sid
	return clampf(float(soc.call("rep", group)) / 60.0 - float(soc.call("crim_rep", group)) / 80.0, -1.0, 1.0)


## Up to a few current rumour lines of settlement `sid` (society, read only; cached 20 s).
static func rumour_lines(sid: int) -> Array:
	var now := Time.get_ticks_msec()
	var e: Array = _rumour_cache.get(sid, [])
	if not e.is_empty() and int(e[0]) > now:
		return e[1]
	var lines: Array = []
	var soc := _society()
	if soc != null and sid >= 0:
		lines = soc.call("rumours", sid)
	_rumour_cache[sid] = [now + 20000, lines]
	return lines


# ================================================================ lines (barks)
const LINES := {
	"greet_warm": ["Good day to you!", "Well met, friend!", "Blessings on you.", "Ah, it's you! Welcome."],
	"greet_neutral": ["Morning.", "Good day.", "Mind the cart.", "Fine weather."],
	"greet_cold": ["Hmph.", "Keep your distance.", "We don't want trouble.", "...Stranger."],
	"greet_evening": ["Good evening.", "Late to be out.", "Mind the dark roads."],
	"armed": ["Put that away!", "Sheathe your blade!", "Easy now, easy!", "Watch where you point that!", "Not in the market!"],
	"armed_guard": ["Sheathe your weapon, citizen!", "Keep the peace here!"],
	"crime": ["Thief! Stop them!", "Guards! Guards!", "Murder!", "Help! Somebody help!"],
	"alarm_guard": ["There! Over there!", "He went that way!", "Fetch the watch!"],
	"guard_respond": ["Where? Show me!", "Stand aside!", "Hold there!"],
	"notice": ["Hm?", "Who's there?", "Did you see that?", "What was that?"],
	"suspicious": ["Hey, you there!", "What are you up to?", "I'm watching you.", "State your business."],
	"suspicious_guard": ["Halt! Who goes there?", "Show yourself!", "You, there. Stand still."],
	"search": ["Come out, whoever you are!", "I know someone's here.", "Search the area!", "Check the alleys."],
	"flee": ["Run!", "Get inside!", "Wolf!", "It's coming!", "Save yourselves!"],
	"hide": ["Is it gone?", "Shh...", "Stay quiet."],
	"fire": ["Fire!", "Water, bring water!", "The fire's spreading!", "Form a line!"],
	"rain": ["Wet again...", "Get under cover!", "Just my luck.", "Rain at last."],
	"gossip_generic": ["Did you hear about the new tax?", "The harvest looks fair this year.", "They say wolves took a sheep last night.",
		"My knee says rain.", "Smith's lad has taken up with the miller's girl.", "Prices at the stalls are a scandal."],
	"gossip_player": ["They say a stranger did that?", "Is that the one everybody talks about?"],
	"festival": ["What's all the noise?", "Come see!", "A fine show!"],
	"fight": ["Fight! Fight!", "Break it up!", "Someone fetch the guard!"],
	# the town's circumstances (town_mood.gd): grumbling about shortages, war, monsters, deaths, the law, holidays
	"shortage": ["Bread's gone up again.", "Nothing left on the shelves.", "How are we meant to feed the children?", "Half a loaf, and they call that a price.",
		"The granary is empty, mark my words.", "Third day on thin porridge..."],
	"queue": ["Is this the line for bread?", "Been standing here since dawn.", "They'll run out before I get to the front.", "No pushing at the back!"],
	"meal_poor": ["Thin soup again.", "Not much on the plate tonight.", "Bread and scrape, that is supper."],
	"war_talk": ["They say the levy is coming.", "My brother marched in spring. No word since.", "The crown wants more men.", "War taxes, war prices."],
	"monster_talk": ["Bar the doors tonight.", "Something was at the fence again.", "Stay off the road after dark.", "The wardstones aren't what they were."],
	"mourning": ["A sad day for the town.", "He will be missed.", "May the ash take him gently.", "We shall light a candle."],
	"curfew_talk": ["Home before the bell, they say.", "The watch is out in force.", "Keep your head down, keep your purse close.", "Curfew again. Who does it help?"],
	"festival_talk": ["Come and dance!", "The best festival in years!", "Have you tried the honey cakes?", "A fine day for it!"],
	"rest_talk": ["Day of rest at last.", "Not a hoe in sight today.", "Temple, then a pie.", "Sleep in, they said. The cockerel didn't hear."],
	"wake": ["Morning!", "Another day...", "Up with the sun.", "Where did I leave my boots?"],
	"drunk": ["I'm not drunk! The road is crooked!", "One more... for the road...", "You're my best friend, you are!", "Hic... excuse me."],
	"barkeep": ["Out! And stay out!", "You've had enough, friend.", "Come back when you can stand!"],
	"merchant_a": ["That's robbery!", "Three coins and not a copper less!", "Your scales are false!"],
	"merchant_b": ["Cheat! Thief!", "Quality has its price!", "Ask anyone, my cloth is the finest!"],
	"thief": ["Out of my way!", "Not me!", "Catch me if you can!"],
	"stop_thief": ["Stop, thief!", "My purse! My purse!", "Guards! After him!"],
	"recruiter": ["The crown needs good men!", "A silver a week and a meal a day!", "Join the levy, defend your homes!", "Who will stand for Valencious?"],
	"crier": ["Hear ye, hear ye!", "News from the road!", "By order of the council!"],
	"performer": ["Gather round, gather round!", "A song for a copper!", "Listen to the tale of the ash-bound king!"],
	"audience": ["Bravo!", "Another!", "Marvellous!", "Here, a copper for you."],
	"sermon": ["The ash remembers all.", "From ember, a new fire.", "Be generous in lean times.", "Mourn, but do not despair."],
	"gate_close": ["Gates closing!", "Last call, travellers!", "Lock it up for the night.", "All quiet?"],
	"gate_open": ["Gates open!", "Dawn's here, let them in.", "Another quiet night."],
	"shift": ["Your watch.", "All quiet.", "Nothing to report.", "Keep your eyes open."],
	"lamp": ["Light for the road.", "Mind the flame!", "Dusk already..."],
	"beggar": ["Spare a copper?", "Alms for the hungry...", "Bless you, kind soul."],
	"market_close": ["Closing up!", "Last chance, bargains!", "See you at dawn."],
	"broken_cart": ["Blast this wheel!", "I'll never make market now.", "Could someone lend a hand?"],
	"thanks": ["Bless you!", "You've saved my day.", "Take this, you've earned it."],
	"child_play": ["Tag! You're it!", "Can't catch me!", "Race you to the well!", "Wait for me!"],
	"dog": ["Come back here, you wretched dog!", "Not the hens!", "Bad dog!"],
	"traveller": ["Just passing through.", "My papers are in order.", "I come from the coast, officer."],
	"guard_ask": ["State your business.", "Papers, traveller.", "Where are you bound?"],
	"noble": ["Make way for his lordship!", "Clear the road!"],
	"adventurer": ["Where is the guild hall?", "Heard there's a nest to the north.", "I need a drink and a bed."],
	"delivery": ["Mind your backs!", "Fresh flour for the baker!", "Where does this crate go?"],
	"laundry": ["Plenty of sun for drying today.", "My arms ache from wringing.", "Hand me those pegs."],
	"gossip_well": ["Did you hear what happened last night?", "She said what?", "And with the miller's wife!"],
	"funeral": ["Rest now, old friend.", "Gently, gently...", "Lower your heads."],
	"wedding": ["Long life to the couple!", "A kiss! A kiss!", "Throw the barley!"],
	"fire_bucket": ["Pass the bucket!", "More water!", "Keep the line moving!"],
	"hunter": ["Wolves on the road!", "Fresh venison!", "Close the gates early!"],
	"courier": ["Message for the captain!", "Make way, urgent post!", "News from the front!"],
	"healer": ["Keep the water boiled.", "Rest and broth, that will mend him.", "Burn the bedding."],
	"tax": ["The crown's due, if you please.", "Your ledger, merchant.", "Quarter's tax. No excuses."],
	"farmer_home": ["Another long day.", "Fields are dry as bone.", "The ox is lame again."],
	"teacher": ["Again, from the top!", "Letters first, play after.", "Who can read this word?"],
	"peddler": ["Ribbons, pins, needles!", "Charms against the dark!", "Finest trinkets, cheap!"],
	"kneel": ["For those we lost.", "Light a candle for the dead."],
}


## Deterministic line of category `cat` for `person` (salt varies it over time).
static func line(cat: String, person: int, salt := 0) -> String:
	var list: Array = LINES.get(cat, [])
	if list.is_empty():
		return ""
	return list[absi(hash(person * 7919 + salt * 131 + cat.length())) % list.size()]


# ================================================================ helpers
## A child: a stable slice of the settlement's day labourers (shorter, plays about the plaza).
static func is_child(person: int) -> bool:
	return person >= 0 and person < WorldSim.job.size() and WorldSim.job[person] == 4 and absi(hash(person * 977 + 3)) % 10 == 0

