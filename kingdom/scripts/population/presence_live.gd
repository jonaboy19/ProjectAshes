extends RefCounted
## Live wiring of Reactive Presence (presence.gd) for the near tier. PopulationLOD owns ONE of these and calls tick() every
## frame; it runs the Presence at ~10 Hz (the Presence itself staggers observers, 1/STAGGER per call). Only FULL-tier bodies
## are registered: a body that left the LOD's list is unregistered on the next sync (far tiers cost nothing).
## Bodies are duck-typed so tests can use stubs:
##   presence_sample() -> {id, pos: Vector2, facing: Vector2, vel: Vector2, flags: int, busy: float, guard: bool, opts: {}}
##   presence_react(kind: int, target_id: int, info: Dictionary)   (info = ReactionAdapter.describe)
## The player is a subject only (never an observer). Output goes through ReactionAdapter.consume().

const Presence := preload("res://scripts/population/presence.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const Adapter := preload("res://scripts/population/reaction_adapter.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")

const PLAYER_ID := 60000          # Presence packs targets into 16 bits; person ids are far below this
const STEP_MS := 100              # ~10 Hz
const GUARD_NEAR_M := 15.0
const BUMP_M := 0.75

static var current: RefCounted    # the live instance (player-side hooks report through it)
static var debug := false         # print each reaction + the stage/reason of watching NPCs

var presence: Presence = Presence.new()
var adapter: RefCounted = Adapter.new()
var step_ms := STEP_MS
var _acc_ms := 0
var _bodies: Dictionary = {}      # id -> body (registered FULL-tier observers)
var _player_prev := Vector2.INF
var _player_vel := Vector2.ZERO
var _bump_cd := 0
var _log_seen := 0
var ticks := 0
var last_tick_usec := 0
var sync_usec := 0
var _guards: Array[Vector2] = []


func _init() -> void:
	presence.record = true
	presence.stagger = 5          # each observer is evaluated at 2 Hz: 1/5 of the near tier per 10 Hz call
	current = self


# ------------------------------------------------------------------ driving
## Advance by `delta` seconds. `bodies` = the FULL-tier bodies right now; `player` = the player node (may be null).
func tick(delta: float, now_ms: int, bodies: Array, player: Node3D = null) -> bool:
	_acc_ms += int(delta * 1000.0)
	if _acc_ms < step_ms:
		return false
	_acc_ms = 0
	var t0 := Time.get_ticks_usec()
	sync(bodies, player, now_ms)
	sync_usec = Time.get_ticks_usec() - t0
	presence.tick(now_ms)
	_deliver(now_ms)
	ticks += 1
	last_tick_usec = Time.get_ticks_usec() - t0
	if debug:
		_print_debug()
	return true


## Registers/updates the FULL bodies, unregisters those that left, feeds the player.
func sync(bodies: Array, player: Node3D, now_ms: int) -> void:
	var live := {}
	_guards.clear()
	var samples: Array = []
	for b in bodies:
		if b == null or not is_instance_valid(b) or not b.has_method("presence_sample"):
			continue
		var s: Dictionary = b.presence_sample()
		if s.is_empty():
			continue
		var id: int = s["id"]
		if id < 0 or id >= PLAYER_ID:
			continue
		live[id] = true
		_bodies[id] = b
		samples.append(s)
		if bool(s.get("guard", false)):
			_guards.append(s["pos"])
	for id in _bodies.keys():
		if not live.has(id):
			unregister(id)
	for s in samples:
		var id: int = s["id"]
		var fl: int = int(s.get("flags", 0))
		if bool(s.get("guard", false)):
			fl |= Presence.F_GUARD
		var slot := presence.set_body(id, s["pos"], s["facing"], s.get("vel", Vector2.ZERO), s.get("head", Vector2.ZERO), fl)
		if slot < 0:
			continue
		if presence.observer[slot] == 0:
			presence.make_observer(id, s.get("opts", {}))      # traits are set once, on registration
		presence.set_busy(id, float(s.get("busy", 0.2)))
		(presence.data[slot] as Dictionary)["guard_near"] = _guard_near(s["pos"])
	if player != null and is_instance_valid(player):
		_feed_player(player, now_ms)


func _guard_near(p: Vector2) -> bool:
	for g in _guards:
		var d: Vector2 = g - p
		if d.length_squared() < GUARD_NEAR_M * GUARD_NEAR_M and d.length_squared() > 0.01:
			return true
	return false


func unregister(id: int) -> void:
	_bodies.erase(id)
	presence.remove_body(id)


func registered_count() -> int:
	return _bodies.size()


func _feed_player(pl: Node3D, now_ms: int) -> void:
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	if _player_prev != Vector2.INF:
		_player_vel = (p - _player_prev) / maxf(float(step_ms) / 1000.0, 0.001)
	_player_prev = p
	var face := Vector2.ZERO
	if pl.has_method("facing"):
		var f: Vector3 = pl.facing()
		face = Vector2(f.x, f.z)
	var head := face
	if pl.has_method("forward"):
		var f2: Vector3 = pl.forward()
		head = Vector2(f2.x, f2.z)          # the camera direction is where the player is looking
	var fl := 0
	if _player_vel.length() > 4.5:
		fl |= Presence.F_RUNNING
	if bool(pl.get("crouching")):
		fl |= Presence.F_CROUCH
	if bool(pl.get_meta("weapon_drawn", false)) or _npc_world_armed():
		fl |= Presence.F_DRAWN
	if _player_indoors():
		fl |= Presence.F_PUBLIC            # weapons are taboo in a building
	presence.set_body(PLAYER_ID, p, face, _player_vel, head, fl)
	if pl.has_meta("insignia"):
		presence.describe_subject(PLAYER_ID, {"insignia": float(pl.get_meta("insignia"))})
	if pl.has_meta("aura_view"):
		presence.describe_subject(PLAYER_ID, pl.get_meta("aura_view"))   # AR-3: aura_emit / reach_m / signature -> Stim.AURA
	elif not pl.has_node("AuraDriver") and pl.is_inside_tree():
		(load("res://scripts/actors/aura_driver.gd") as GDScript).call("attach", pl)
	# Walking into someone is a bump (rate limited).
	if now_ms >= _bump_cd and _player_vel.length() > 1.5:
		for id: int in _bodies:
			var s := presence.slot_of(id)
			if s >= 0 and presence.pos[s].distance_squared_to(p) < BUMP_M * BUMP_M:
				_bump_cd = now_ms + 2500
				presence.report(Presence.Stim.BUMP, PLAYER_ID, 1.0, now_ms, id, 2.0)
				break


static func _npc_world_armed() -> bool:
	return NpcWorld.player_armed()


static func _player_indoors() -> bool:
	return InteriorDoor.active != null and is_instance_valid(InteriorDoor.active)


func _deliver(now_ms: int) -> void:
	for id: int in _bodies.keys():
		var b: Object = _bodies[id]
		var slot := presence.slot_of(id)
		if slot < 0 or presence.requests.pending_count(slot) == 0:
			continue
		if b == null or not is_instance_valid(b):
			continue
		adapter.consume(presence.requests, slot, func(_sl: int, kind: int, target: int, info: Dictionary) -> void:
			if debug:
				print("[presence] %d -> %s (target %d)" % [id, RR.name_of(kind), target])
			if b.has_method("presence_react"):
				b.presence_react(kind, target, info))


# ------------------------------------------------------------------ player-side hooks (static: callers need no reference)
## Player did something others can notice: Presence.Stim.* (bump, take object, kindness, trespass ...).
static func report_player(stim: int, strength := 1.0, radius := 12.0) -> int:
	if current == null:
		return 0
	var cur: RefCounted = current
	return cur.presence.report(stim, PLAYER_ID, strength, Time.get_ticks_msec(), -1, radius)


# ------------------------------------------------------------------ debug
## "stage: reason" of what `observer_id` is currently watching, or "idle".
func describe(observer_id: int) -> String:
	var o := presence.slot_of(observer_id)
	if o < 0:
		return "unregistered"
	var out := PackedStringArray()
	for k in Presence.ATT:
		var a := o * Presence.ATT + k
		if presence.a_subj[a] >= 0:
			out.append("%s: %s on %d (%.2f)" % [Presence.Stage.keys()[presence.a_stage[a]].to_lower(),
				Presence.STIM_NAMES[presence.a_kind[a]], presence.id_of[presence.a_subj[a]], presence.a_level[a]])
	return ", ".join(out) if not out.is_empty() else "idle"


func _print_debug() -> void:
	_log_seen = mini(_log_seen, presence.log.size())
	while _log_seen < presence.log.size():
		print("[presence] ", presence.log[_log_seen])
		_log_seen += 1
	if ticks % 10 == 0:
		for id: int in _bodies:
			var d := describe(id)
			if d != "idle":
				print("[presence] npc ", id, " ", d)
