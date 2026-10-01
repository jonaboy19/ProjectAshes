extends Node3D
## The micro-event director: short reusable street scenes (a cart passing, a drunk thrown out of the tavern, a
## funeral procession, the gates closing at night ...) that make a settlement look lived in
## (docs/design/VERTICAL_SLICE.md P1). The pool lives in micro_catalog.gd (60+ entries), the staging in
## micro_scene.gd, the bodies in micro_actor.gd.
##
## What it decides, every second at most:
##  - whether something may start: at most MAX_ACTIVE scenes near the player (two), a minimum gap between starts
##    that shrinks when the street is busy, an actor budget tied to Quality.npc_full, nothing while the player is
##    indoors, dead, or has a weapon drawn;
##  - which scene: every entry has a weight that depends on the hour, the district of the player's spot
##    (scripts/world/districts.gd), the weather and the circumstances of the town (TownMood: war, festival, rest
##    day, shortages, mourning, monsters, curfew, crime, plague, fire), and a per-entry cooldown;
##  - determinism: the draw is seeded from (world seed, day, half hour, serial), so the same situation and the
##    same serial always give the same scene.
## Pure parts (make_context, weight_of, weights, pick, in_hours, district_of) are static and need no scene tree.
##
## Persistent leftovers of scenes are kept here and cleaned by the clock: market stall shutters (lowered at
## dusk, raised in the morning), town gate leaves (closed to a wicket at night), lit lamps.
##
## Created by PopulationLOD.setup(); QA: `spawn_now("street_performer")` forces a scene.

const Catalog := preload("res://scripts/population/micro_catalog.gd")
const MicroScene := preload("res://scripts/population/micro_scene.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const Schedule := preload("res://scripts/population/schedule.gd")

const POOL: Array = Catalog.POOL
const MAX_ACTIVE := 2
const MIN_GAP := 14.0            # real seconds between two starts when the street is quiet
const MAX_GAP := 34.0
const TICK := 1.0
const NEAR_TOWN := 1.35          # x radius around a settlement in which scenes run
## Fewer scenes in a busy frame: nothing starts while this many micro actors exist.
const ACTOR_CAP_MAX := 12

## Debug: log what starts (tests and QA read it).
static var log: Array = []
static var verbose := false

var focus := Vector3.ZERO
var active: Array = []
var cooldown: Dictionary = {}        # id -> Time.get_ticks_msec() it is available again
var serial := 0
var scenes_started := 0
var sid := -1

var _acc := 0.0
var _next_ms := 0
var _shutters := {}                  # sid -> {stall index: Node3D}
var _gates := {}                     # sid -> {gate index: [leaf nodes]}
var _lamps := {}                     # sid -> Array of Node3D
var _hour_seen := -1.0
var _district_cache := {}


# ================================================================ pure logic (static, testable)
## Hours window test; `win` = [a, b], wrapping midnight when b < a.
static func in_hours(h: float, win: Array) -> bool:
	var a := float(win[0])
	var b := float(win[1])
	if a <= b:
		return h >= a and h < b
	return h >= a or h < b


## The situation a scene is chosen in. `mood` is a TownMood dictionary; `extra` adds/overrides flags (tests).
static func make_context(hour: float, day: int, district: String, raining: bool, mood: Dictionary, kind := "town", extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"hour": hour, "day": day, "district": district, "kind": kind, "rain": raining,
		"night": hour >= 22.0 or hour < 5.0, "dusk": hour >= 17.5 and hour < 20.5, "dawn": hour >= 5.0 and hour < 8.0,
		"day_time": hour >= 8.0 and hour < 17.5, "market_open": hour >= 8.0 and hour < 19.0,
		"war": float(mood.get("war", 0.0)) >= 0.5, "festival": String(mood.get("festival", "")) != "",
		"rest": bool(mood.get("rest_day", false)), "scarce": float(mood.get("scarcity", 0.0)) >= 0.4,
		"mourn": float(mood.get("mourning", 0.0)) >= 0.5, "monster": float(mood.get("monster", 0.0)) >= 0.5,
		"curfew": bool(mood.get("curfew", false)), "crime": float(mood.get("crime", 0.0)) >= 0.5,
		"plague": bool(mood.get("plague", false)), "fire": bool(mood.get("fire", false)), "shutters_down": false,
	}
	ctx.merge(extra, true)
	return ctx


## Weight of catalogue entry `e` in situation `ctx` (0 = not eligible).
static func weight_of(e: Dictionary, ctx: Dictionary) -> float:
	var w := float(e["w"])
	var when: Dictionary = e.get("when", {})
	var h := float(ctx["hour"])
	if when.has("h") and not in_hours(h, when["h"]):
		return 0.0
	if when.has("rain"):
		var r := int(when["rain"])
		if (r < 0 and bool(ctx["rain"])) or (r > 0 and not bool(ctx["rain"])):
			return 0.0
	for f: String in when.get("need", []):
		if not bool(ctx.get(f, false)):
			return 0.0
	for f: String in when.get("not", []):
		if bool(ctx.get(f, false)):
			return 0.0
	if when.has("kinds") and not (when["kinds"] as Array).has(String(ctx["kind"])):
		return 0.0
	if when.has("dom"):
		var dom: Array = when["dom"]
		if posmod(int(ctx["day"]), int(dom[0])) != int(dom[1]):
			return 0.0
	var mods: Dictionary = e.get("mods", {})
	for flag: String in mods:
		if bool(ctx.get(flag, false)):
			w *= float(mods[flag])
	var dw: Dictionary = e.get("dw", {})
	var d := String(ctx.get("district", ""))
	w *= float(dw.get(d, dw.get("*", 1.0))) if d != "" else float(dw.get("*", 1.0))
	if e.has("bell"):
		var best := 0.0
		for b: Array in e["bell"]:
			var dist := absf(wrapf(h - float(b[0]), -12.0, 12.0))
			best = maxf(best, 1.0 - smoothstep(0.0, float(b[1]) * 2.0, dist))
		w *= 0.25 + 0.75 * best
	return maxf(w, 0.0)


## Weights of every eligible entry, skipping `excluded` ids (cooling down or already running).
static func weights(ctx: Dictionary, excluded: Array = []) -> Dictionary:
	var out := {}
	for e: Dictionary in POOL:
		var id := String(e["id"])
		if excluded.has(id):
			continue
		var w := weight_of(e, ctx)
		if w > 0.0:
			out[id] = w
	return out


## The scene to run: a weighted draw (deterministic for `seed_i`) among eligible entries not in cooldown (`cooldowns`
## maps id -> ms it is free again; `now_ms` the clock) and not in `active_ids`. "" when nothing qualifies.
static func pick(ctx: Dictionary, seed_i: int, cooldowns: Dictionary, now_ms: int, active_ids: Array = []) -> String:
	var excluded: Array = active_ids.duplicate()
	for id: String in cooldowns:
		if int(cooldowns[id]) > now_ms:
			excluded.append(id)
	var total := 0.0
	var order: Array = []
	var ws := weights(ctx, excluded)
	for e: Dictionary in POOL:          # catalogue order: the draw never depends on dictionary ordering
		var id := String(e["id"])
		if ws.has(id):
			order.append([id, float(ws[id])])
			total += float(ws[id])
	if order.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var r := rng.randf() * total
	for o: Array in order:
		r -= float(o[1])
		if r <= 0.0:
			return String(o[0])
	return String((order[order.size() - 1] as Array)[0])


static func entry_of(id: String) -> Dictionary:
	for e: Dictionary in POOL:
		if String(e["id"]) == id:
			return e
	return {}


## May a new scene start? Pure budget rule: scenes running, actors alive and the tier's NPC allowance.
static func budget_allows(active_scenes: int, actors_alive: int, villagers: int, npc_full: int) -> bool:
	if active_scenes >= MAX_ACTIVE:
		return false
	var cap := clampi(npc_full * 2 / 3, 5, ACTOR_CAP_MAX)
	if actors_alive + 5 > cap:
		return false
	return villagers + actors_alive <= npc_full + 6


## Seconds to wait after a start: busier streets (0..1) shorten the gap.
static func gap_seconds(street_activity: float, rnd: float) -> float:
	return lerpf(MAX_GAP, MIN_GAP, clampf(street_activity, 0.0, 1.0)) * (0.75 + 0.5 * rnd)


## District ("market" "craft" "poor" "admin" "inn" "military") of world point `p` in settlement `s`: the town
## planner's own districts when the plan has them, else a geometric guess (near the plaza: market, near a gate:
## military, near the inn door: inn, outer ring: poor, near the temple: admin, the rest: craft).
static func district_of(s: Dictionary, p: Vector2) -> String:
	var plan: Dictionary = s.get("plan", {})
	if not (plan.get("district_anchors", []) as Array).is_empty():
		# CityPlanner.district_at(plan, pos) (another agent's, null-guarded: it may not exist yet)
		var planner: GDScript = load("res://scripts/world/city_planner.gd")
		if planner != null and planner.has_method("district_at"):
			var d := String(planner.call("district_at", plan, p))
			if d != "":
				return d
	var c: Vector2 = s["pos"]
	var r := float(s.get("radius", 60.0))
	var pr := float(plan.get("plaza_r", 12.0))
	var dist := p.distance_to(c)
	if dist > r * 1.05:
		return ""
	if dist < pr * 1.6:
		return "market"
	for g in plan.get("gates", []):
		if p.distance_to(c + Vector2(cos(float(g)), sin(float(g))) * r * 0.95) < r * 0.28:
			return "military"
	for lot: Dictionary in plan.get("lots", []):
		var asset := String(lot.get("asset", ""))
		if (asset == "inn" or asset == "stable") and p.distance_to(lot["pos"]) < 16.0:
			return "inn"
	for lm: Dictionary in plan.get("landmarks", []):
		var a := String(lm.get("asset", ""))
		if (a == "temple" or a == "chapel" or a == "bell_tower") and p.distance_to(lm["pos"]) < 20.0:
			return "admin"
	return "poor" if dist > r * 0.7 else "craft"


# ================================================================ director
func _ready() -> void:
	name = "MicroEvents"
	set_process(true)
	_next_ms = Time.get_ticks_msec() + 8000


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	if NpcWorld.profile:
		var t0 := Time.get_ticks_usec()
		_tick()
		NpcWorld.prof_frame_usec += Time.get_ticks_usec() - t0
	else:
		_tick()


func _tick() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var here := _town_at(pp)
	if here != sid:
		sid = here
	_sync_world_state(here, pp)
	if here < 0:
		return
	var now := Time.get_ticks_msec()
	if now < _next_ms or not _may_start(player):
		return
	var s: Dictionary = WorldGen.settlements[here]
	NpcWorld.ensure_spots(here, get_parent())
	var hour := WorldSim.time_of_day
	var mood := TownMood.mood_of(here)
	var raining := _raining()
	var extra := {"shutters_down": _any_shutter_down(here)}
	var ctx := make_context(hour, WorldSim.day, district_of(s, pp), raining, mood, String(s["kind"]), extra)
	var ids: Array = []
	for sc in active:
		if is_instance_valid(sc):
			ids.append(String((sc as MicroScene).entry["id"]))
	serial += 1
	var seed_i := hash([WorldSim.SEED, WorldSim.day, int(hour * 2.0), serial])
	var id := pick(ctx, seed_i, cooldown, now, ids)
	if id == "":
		_next_ms = now + 4000
		return
	var ok := _start(id, here, pp, player, seed_i)
	if ok:
		var act := Schedule.street_activity(String(s["kind"]), hour, int(mood["flags"]), WorldSim.day)
		var rnd := float(hash([serial, 77]) % 1000) / 1000.0
		_next_ms = now + int(gap_seconds(act, rnd) * 1000.0)
	else:
		cooldown[id] = now + 9000
		_next_ms = now + 1500


## Start scene `id` now, ignoring weights, cooldowns and the budget (QA and tests).
func spawn_now(id: String) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var here := _town_at(pp)
	if here < 0:
		return false
	NpcWorld.ensure_spots(here, get_parent())
	serial += 1
	return _start(id, here, pp, player, hash([WorldSim.SEED, serial, id]))


func _start(id: String, town: int, pp: Vector2, player: Node3D, seed_i: int) -> bool:
	var e := entry_of(id)
	if e.is_empty():
		return false
	var fwd := Vector2(-sin(player.global_rotation.y), -cos(player.global_rotation.y))
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var f := -cam.global_transform.basis.z
		fwd = Vector2(f.x, f.z)
	var scene := MicroScene.new()
	add_child(scene)
	if not scene.setup(e, town, seed_i, pp, fwd, self):
		scene.queue_free()
		return false
	active.append(scene)
	scenes_started += 1
	cooldown[id] = Time.get_ticks_msec() + int(float(e["cd"]) * 1000.0)
	log.append("%s %s" % [id, scene.announce])
	if log.size() > 200:
		log.pop_front()
	if verbose:
		print("[micro] ", log[log.size() - 1])
	return true


func on_scene_finished(scene: Node) -> void:
	active.erase(scene)


func actors_alive() -> int:
	var n := 0
	for sc in active:
		if is_instance_valid(sc):
			n += (sc as MicroScene).actor_count()
	return n


func _may_start(player: Node3D) -> bool:
	if InteriorDoor.active != null or bool(player.get("dead")) or NpcWorld.player_armed():
		return false
	var pop := get_parent()
	var villagers := int(pop.get("full_count")) if pop != null and pop.get("full_count") != null else 0
	return budget_allows(active.size(), actors_alive(), villagers, Quality.npc_full)


func _town_at(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for s: Dictionary in WorldGen.settlements:
		var d := p.distance_to(s["pos"])
		if d < float(s["radius"]) * NEAR_TOWN and d < best_d:
			best_d = d
			best = int(s["id"])
	return best


func _raining() -> bool:
	var w := get_tree().get_first_node_in_group("weather")
	return w != null and w.has_method("is_raining") and bool(w.call("is_raining"))


# ================================================================ persistent leftovers
func shutter_nodes(town: int) -> Dictionary:
	if not _shutters.has(town):
		_shutters[town] = {}
	return _shutters[town]


func add_shutter(town: int, idx: int, node: Node3D) -> void:
	shutter_nodes(town)[idx] = node
	add_child(node)


func _any_shutter_down(town: int) -> bool:
	for n in shutter_nodes(town).values():
		if is_instance_valid(n) and bool((n as Node3D).get_meta("down", false)):
			return true
	return false


func add_lamp(town: int, node: Node3D) -> void:
	if not _lamps.has(town):
		_lamps[town] = []
	(_lamps[town] as Array).append(node)
	add_child(node)


## Close or open town gate `gi` of `town`: two leaves swung on their hinges (closed leaves leave a wicket).
func set_gate(town: int, gi: int, closed: bool, base: Vector2, ang: float) -> void:
	if not _gates.has(town):
		_gates[town] = {}
	var g: Dictionary = _gates[town]
	if not g.has(gi):
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		var leaves: Array = []
		for k in 2:
			var sgn := 1.0 if k == 0 else -1.0
			var pivot := Node3D.new()
			var hinge := base + side * 4.05 * sgn
			pivot.position = Vector3(hinge.x, WorldGen.height(base.x, base.y), hinge.y)
			pivot.set_meta("closed_v", -side * sgn)
			pivot.set_meta("open_v", -dir)
			var leaf := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.2, 3.7, 0.18)
			leaf.mesh = bm
			leaf.position = Vector3(1.6, 1.85, 0.0)
			leaf.material_override = Assets.flat_material(Color(0.27, 0.19, 0.12))
			pivot.add_child(leaf)
			for j in 3:
				var band := MeshInstance3D.new()
				var bb := BoxMesh.new()
				bb.size = Vector3(3.24, 0.12, 0.22)
				band.mesh = bb
				band.position = Vector3(1.6, 0.6 + float(j) * 1.35, 0.0)
				band.material_override = Assets.flat_material(Color(0.1, 0.09, 0.09))
				pivot.add_child(band)
			add_child(pivot)
			pivot.rotation.y = _yaw_for(pivot.get_meta("open_v"))
			leaves.append(pivot)
		g[gi] = leaves
	for pivot: Node3D in g[gi]:
		var want := _yaw_for(pivot.get_meta("closed_v" if closed else "open_v"))
		var tw := pivot.create_tween()
		tw.tween_property(pivot, "rotation:y", pivot.rotation.y + wrapf(want - pivot.rotation.y, -PI, PI), 5.0).set_trans(Tween.TRANS_SINE)
		pivot.set_meta("is_closed", closed)


static func _yaw_for(v: Vector2) -> float:
	return atan2(-v.y, v.x)


## Clock-driven cleanup of scene leftovers (cheap, once per tick): shutters up and lamps out by day, gates open
## by day, and everything of a town the player has left far behind.
func _sync_world_state(here: int, pp: Vector2) -> void:
	var h := WorldSim.time_of_day
	var day_open := h >= 8.5 and h < 17.0
	if day_open:
		for town: int in _shutters:
			for idx: int in _shutters[town]:
				var n: Node3D = _shutters[town][idx]
				if is_instance_valid(n) and bool(n.get_meta("down", false)):
					n.set_meta("down", false)
					var sp: Vector2 = n.get_meta("stall_pos")
					n.position.y = WorldGen.height(sp.x, sp.y) + 2.7
	if h >= 6.2 and h < 17.0:
		for town: int in _lamps:
			for n: Node3D in _lamps[town]:
				if is_instance_valid(n):
					n.queue_free()
			(_lamps[town] as Array).clear()
	if h >= 6.8 and h < 20.0:
		for town: int in _gates:
			for gi: int in _gates[town]:
				for pivot: Node3D in _gates[town][gi]:
					if is_instance_valid(pivot) and bool(pivot.get_meta("is_closed", false)):
						pivot.set_meta("is_closed", false)
						pivot.rotation.y = _yaw_for(pivot.get_meta("open_v"))
	_hour_seen = h
	# Far from a settlement its leftovers are freed (rebuilt by the next scene there).
	for town: int in _shutters.keys():
		if town != here and WorldGen.settlements[town]["pos"].distance_to(pp) > 400.0:
			for n in (_shutters[town] as Dictionary).values():
				if is_instance_valid(n):
					(n as Node).queue_free()
			_shutters.erase(town)
	for town: int in _gates.keys():
		if town != here and WorldGen.settlements[town]["pos"].distance_to(pp) > 400.0:
			for gi: int in _gates[town]:
				for pivot: Node3D in _gates[town][gi]:
					if is_instance_valid(pivot):
						pivot.queue_free()
			_gates.erase(town)
