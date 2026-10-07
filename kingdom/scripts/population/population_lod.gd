class_name PopulationLOD
extends Node3D
## Gives simulated people a body near the player:
##   within FULL_RANGE (nearest MAX_FULL)  -> animated character with a name tag
##   within SPRITE_RANGE, outside SPRITE_MIN_DIST -> directional sprite in a MultiMesh
##   beyond, or inside SPRITE_MIN_DIST without a full-model slot -> data only (WorldSim)
##
## Embodied villagers own their movement; each refresh writes their resolved
## positions back into WorldSim (the one hand-off point), and a time skip
## hands movement back the other way. Villagers inside CONTACT_KEEP are never
## demoted, and ones already embodied rank slightly closer so residents near
## the budget edge don't swap every refresh. Distant residents whose own clock
## (DailyRhythm) hasn't reached WorldSim's latest phase are held where they
## are, so the crowd sets off gradually.

const StreetGraph := preload("res://scripts/population/street_graph.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")
const MicroEvents := preload("res://scripts/population/micro_events.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const AlertGlyphs := preload("res://scripts/ui/alert_glyphs.gd")
const Takedown := preload("res://scripts/combat/takedown.gd")
const Probe := preload("res://scripts/core/perf_probe.gd")

const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const FULL_RANGE := 45.0       # defaults; the live values come from CellStreamer profile "population"
const SPRITE_RANGE := 220.0
const NEAR_ALWAYS := 9.0     # metres: never a sprite this close to the player
const NEAR_HARD_CAP := 12    # but never more than this many full models in total
## Below this, a flat sprite impostor reads as a blocky pixel person right next
## to the camera. NEAR_ALWAYS/NEAR_HARD_CAP above are meant to keep everyone this
## close in a full model, but when the full-model budget (Quality.npc_full) is
## smaller than NEAR_HARD_CAP a nearby resident can still lose out on the full-model
## race; rather than fall back to a sprite this close, they simply aren't drawn
## this refresh (WorldSim still tracks them; they reappear once a slot frees up
## or they step further out). SPRITE_MIN_DIST_RELEASE adds hysteresis so someone
## hovering right at the boundary doesn't pop in and out every refresh.
const SPRITE_MIN_DIST := 20.0
const SPRITE_MIN_DIST_RELEASE := 26.0
const MAX_FULL := 24
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
## Ceiling on total sprites drawn (all job looks combined; see `refresh()`), not
## per look. Quality.npc_sprites narrows this further per tier.
const MAX_SPRITES := 140
const MAX_SPAWNS_PER_TICK := 3
## Contact-range villagers that use the multi-slide controller each physics
## frame, nearest-to-player first. A crowd event can put more into contact at
## once; overflow uses one swept collision query (see Villager.physics_active)
## with the same steering/speed/animation and no NPC-on-NPC collision. Profile
## both paths before changing this cap.
const MAX_PHYSICS_CONTACT := 8
## Retain an active contact slot slightly across ranking refreshes to avoid
## repeatedly enabling/disabling collision for bodies at the budget edge.
const PHYSICS_KEEP_BIAS := 0.78
## Embodied villagers rank at this fraction of their squared distance (about
## 13% closer), so promotion and demotion don't chatter at the budget edge.
const KEEP_BIAS := 0.75
## Never demote a villager this close to the player (it may be touching them).
const CONTACT_KEEP := 3.0
## A world clock jump beyond this (hours) is a skip: sleep, wait, load.
const SKIP_HOURS := 0.5
## Job index -> look id (see Main._bake_looks).
const JOB_LOOK := ["peasant", "worker", "merchant", "guard", "worker", "peasant"]
const LOOK_MODEL := {
	"peasant": ["Rogue_Hooded", []],
	"worker": ["Barbarian", []],
	"merchant": ["Mage", []],
	"guard": ["Knight", ["Knight_Helmet", "1H_Sword"]],
}

var focus := Vector3.ZERO
var _full_range := FULL_RANGE
var _sprite_range := SPRITE_RANGE
var full_count := 0
var sprite_count := 0

var _full: Dictionary = {}        # person id -> Villager
var _multimeshes: Dictionary = {} # look -> MultiMesh
var _timer := 0.0
var _villagers: Array = []        # the Villager nodes in _full, shared with each of them
var _held: Dictionary = {}        # person id -> true while its departure is held back
var _last_time := -1.0
var _sprite_cache: Dictionary = {}   # person id -> [raw pos, pushed-out ground point]
var _sprite_hidden: Dictionary = {}  # person id -> true while suppressed inside SPRITE_MIN_DIST
## Street scenes (cart passing, funeral, gates closing ...) of the settlement the player is in.
var micro: Node
var _sprite_routes: Dictionary = {}  # visible sprite id -> bounded StreetGraph route state
var _refresh_elapsed := 0.0
var _query_r := 0.0             # adaptive people_near radius (see refresh)
## Living world (docs/anim/patches/P13_population_lod_vat.md). CrowdAnimLOD gives embodied villagers an animation LOD
## (NEAR full rate / MID stepped / FAR VAT twin). VatResidents draws residents WITHOUT a body inside VAT_RANGE as
## vertex-animated instances (no nodes); it replaces the sprite there and also fills the 20 m hole around the
## player. LOW tier keeps sprites only (VAT looks and far twins would add MultiMesh draw calls) and keeps the
## animation LOD, which only removes work.
const VAT_RANGE := 120.0
var _vat: VatResidents
var _anim_lod: CrowdAnimLOD


func setup(baker: ImpostorBaker) -> void:
	for look: String in LOOK_MODEL:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ImpostorBaker.quad()
		mm.instance_count = MAX_SPRITES
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		# Updated from _process at 4 Hz: physics interpolation only warned
		# ("triggered from outside physics process") and could jitter the sprites.
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.multimesh = mm
		mmi.material_override = baker.materials.get(look)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1500, 10000))
		add_child(mmi)
		_multimeshes[look] = mm
	_anim_lod = CrowdAnimLOD.new()
	if int(Quality.tier) >= 1:
		_vat = VatResidents.new()
		_vat.name = "VatResidents"
		_vat.height_fn = WorldGen.height
		add_child(_vat)
		_anim_lod.vat = _vat.crowd
	add_child(_anim_lod)
	micro = MicroEvents.new()
	add_child(micro)
	add_child(AlertGlyphs.new())        # ?/! above the heads of the few who are watching the player


func _process(delta: float) -> void:
	if _anim_lod.camera == null or not is_instance_valid(_anim_lod.camera):
		_anim_lod.camera = get_viewport().get_camera_3d()
	_timer -= delta
	_refresh_elapsed += delta
	if _timer <= 0.0:
		_timer = 0.25
		var step := _refresh_elapsed
		_refresh_elapsed = 0.0
		if NpcWorld.profile:
			var t0 := Time.get_ticks_usec()
			refresh(step)
			NpcWorld.prof_lod_usec += Time.get_ticks_usec() - t0
			NpcWorld.prof_lod_calls += 1
		else:
			refresh(step)


func refresh(step_delta := 0.25) -> void:
	var _pt := Probe.t()
	var skipped := _clock_skipped()
	if skipped:
		# WorldSim just placed everyone (advance_hours / load): it is the truth now.
		# Drop temporary sprite routes without writing their old positions over
		# destinations chosen by this explicit time skip.
		for id in _sprite_routes:
			WorldSim.set_external_position_owner(int(id), get_instance_id(), false)
		_sprite_routes.clear()
		_sprite_cache.clear()
		for id in _full:
			(_full[id] as Villager).resync()
	else:
		_write_back()
	Probe.add("pop.write_back", _pt)
	_pt = Probe.t()
	var p2 := Vector2(focus.x, focus.z)
	_full_range = CellStreamer.shared().distance("population", "full")      # F12: the cell manager owns the bands
	_sprite_range = CellStreamer.shared().distance("population", "load")
	# Perf (release QA 2026-10-06): in the capital people_near returned ~1-2k residents and every refresh filtered, weighted and
	# lambda-sorted all of them (~20 ms on the PC, ~100 ms on the S22, 4x a second) to keep ~22 (LOW). The query radius now
	# adapts so about 4x what the tier can show come back; it never drops below the full-model band, so bodies are unchanged.
	var want_n := (NEAR_HARD_CAP + mini(MAX_FULL, Quality.npc_full) + mini(MAX_SPRITES, Quality.npc_sprites)) * 4
	if _query_r <= 0.0 or _query_r > _sprite_range:
		_query_r = _sprite_range
	var ids := WorldSim.people_near(p2, _query_r)
	if ids.size() > want_n:
		_query_r = maxf(_full_range + 6.0, _query_r * 0.8)
	elif ids.size() < want_n / 2:
		_query_r = minf(_sprite_range, _query_r * 1.15)
	_update_holds(ids)
	Probe.add("pop.query", _pt)
	_pt = Probe.t()
	var morning := WorldSim.time_of_day >= 6.0 and WorldSim.time_of_day < 6.0 + DailyRhythm.MAX_DELAY
	var dists := []
	for i in ids:
		if WorldSim.is_indoors(i) or (morning and DailyRhythm.still_home(i)):
			continue
		if Takedown.is_down(i):
			continue            # a body on the ground (KO'd / dead): no sprite, no respawn; the node keeps lying below
		var d2: float = WorldSim.pos[i].distance_squared_to(p2)
		# Named residents (the town kit's rosters) rank as if closer, so they are the ones who get bodies first.
		dists.append([d2, i, (d2 * KEEP_BIAS if _full.has(i) else d2) * TownRoster.embody_weight(i)])
	Probe.add("pop.dists", _pt)
	_pt = Probe.t()
	dists.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	Probe.add("pop.sort", _pt)
	_pt = Probe.t()

	var want_full := {}
	# The near cap follows the tier (LOW 8, MEDIUM 11, HIGH+ 12): each full villager is ~0.5 ms of script on the S22.
	var near_cap := mini(NEAR_HARD_CAP, Quality.npc_full + 3)
	# Anyone this close must be a real model: a flat sprite at arm's length looks broken,
	# so the tier budget may be exceeded up to NEAR_HARD_CAP inside NEAR_ALWAYS.
	for entry in dists:
		if entry[2] > _full_range * _full_range and entry[0] > NEAR_ALWAYS * NEAR_ALWAYS:
			break
		var within_budget: bool = want_full.size() < mini(MAX_FULL, Quality.npc_full) and entry[0] <= _full_range * _full_range
		var too_close_for_sprite: bool = entry[0] <= NEAR_ALWAYS * NEAR_ALWAYS and want_full.size() < near_cap
		if not (within_budget or too_close_for_sprite):
			continue
		want_full[entry[1]] = true
	for id in _full.keys():
		if want_full.has(id):
			continue
		var v: Villager = _full[id]
		# A body on the ground stays where it fell while the player is anywhere near.
		if v.is_down() and v.global_position.distance_squared_to(focus) < 90.0 * 90.0:
			continue
		# Someone standing against the player keeps their body until they step away.
		if not WorldSim.is_indoors(id) and v.global_position.distance_squared_to(focus) < CONTACT_KEEP * CONTACT_KEEP:
			want_full[id] = true
			continue
		_anim_lod.unregister(id)
		_villagers.erase(v)
		v.queue_free()
		_full.erase(id)
	# Bodies on the ground (killed / knocked out, also after a load) near the player get a lying body.
	if Takedown.down_count() > 0:
		for did: int in Takedown.persons():
			if _full.has(did) or did < 0 or did >= WorldSim.population():
				continue
			var bp := Takedown.body_pos(did)
			if bp != Vector2.INF and bp.distance_squared_to(p2) < _full_range * _full_range:
				var body := _spawn(did)
				_full[did] = body
				body.lie_restored(Takedown.kind_of(did))
	Probe.add("pop.demote", _pt)
	_pt = Probe.t()
	var spawned := 0
	for id in want_full:
		if not _full.has(id) and spawned < MAX_SPAWNS_PER_TICK:
			_full[id] = _spawn(id)
			spawned += 1
	Probe.add("pop.spawn", _pt)
	_pt = Probe.t()
	# Promotion transfers the same position-owner flag to the body. Discard any
	# old visual route so demotion can plan again from the body's resolved point.
	for id in _full:
		_sprite_routes.erase(id)
	full_count = _full.size()
	var nearest_id: int = -1
	var nearest_d := 20.0     # squared: the one name plate shows within ~4.5 m (was 6 m)
	for entry in dists:
		if _full.has(entry[1]) and entry[0] < nearest_d:
			nearest_d = entry[0]
			nearest_id = entry[1]
	for id in _full:
		(_full[id] as Villager).show_tag = id == nearest_id
	var physics_candidates: Array = []
	for entry in dists:
		var candidate_id: int = entry[1]
		if not _full.has(candidate_id):
			continue
		var v := _full[candidate_id] as Villager
		var keep_factor := PHYSICS_KEEP_BIAS if v.physics_active else 1.0
		physics_candidates.append([float(entry[0]) * keep_factor, candidate_id])
	physics_candidates.sort_custom(func(a: Array, b: Array) -> bool:
		if float(a[0]) == float(b[0]):
			return int(a[1]) < int(b[1])
		return float(a[0]) < float(b[0]))
	for resident_id in _full:
		(_full[resident_id] as Villager).physics_active = false
	for i in mini(MAX_PHYSICS_CONTACT, physics_candidates.size()):
		var selected_id: int = physics_candidates[i][1]
		(_full[selected_id] as Villager).physics_active = true

	Probe.add("pop.physics_pick", _pt)
	_pt = Probe.t()
	var used := {}
	for look in _multimeshes:
		used[look] = 0
	var sprite_budget: int = mini(MAX_SPRITES, Quality.npc_sprites)
	var sprite_total := 0
	var active_sprite_ids := {}
	var vat_r2 := VAT_RANGE * VAT_RANGE
	if _vat:
		_vat.begin()
	if _sprite_hidden.size() > 4000:
		_sprite_hidden.clear()
	var enter_r2 := SPRITE_MIN_DIST * SPRITE_MIN_DIST
	var release_r2 := SPRITE_MIN_DIST_RELEASE * SPRITE_MIN_DIST_RELEASE
	for entry in dists:
		# dists is sorted nearest-first, so once the budget is spent everyone
		# further away is skipped: the crowd is capped in total, not per look.
		var id: int = entry[1]
		var vat_ok: bool = _vat != null and entry[0] < vat_r2
		if sprite_total >= sprite_budget and not vat_ok:
			break
		if _full.has(id):
			_sprite_hidden.erase(id)
			_sprite_routes.erase(id)
			continue
		# Nobody without a full model is drawn as a sprite this close (see
		# SPRITE_MIN_DIST above); hysteresis keeps the on/off edge from chattering.
		# VAT residents are drawn instead (below), so they skip this test unless the VAT cap is reached.
		if not vat_ok:
			if _sprite_hidden.get(id, false):
				if entry[0] < release_r2:
					continue
				_sprite_hidden.erase(id)
			elif entry[0] < enter_r2:
				_sprite_hidden[id] = true
				continue
		active_sprite_ids[id] = true
		var raw := WorldSim.pos[id]
		var graph := _sprite_route_graph(id, raw, WorldSim.target[id])
		var pp := _advance_sprite_route(id, raw, graph, step_delta)
		var look: String = JOB_LOOK[WorldSim.job[id]]
		var n: int = used[look]
		var heading := _sprite_heading(id, WorldSim.target[id]) - pp
		var yaw := atan2(heading.x, heading.y) if heading.length() > 0.1 else float(id % 628) / 100.0
		# WorldSim moves distant residents in straight lines; never draw one
		# standing inside a house it is cutting through.
		# push_out + terrain height for every sprite each refresh was a spike in
		# the capital; reuse the result while the person hasn't moved.
		if _sprite_cache.size() > 4000:
			_sprite_cache.clear()
		var cached: Array = _sprite_cache.get(id, [])
		var ground: Vector3
		if not cached.is_empty() and (cached[0] as Vector2).distance_squared_to(pp) < 0.0025:
			ground = cached[1]
		else:
			var ground_raw := pp
			var ground_graph := StreetGraph.for_person(id) as StreetGraph
			if ground_graph and entry[0] < 90.0 * 90.0:
				pp = ground_graph.push_out(pp, 0.3)
			ground = Vector3(pp.x, WorldGen.height(pp.x, pp.y), pp.y)
			_sprite_cache[id] = [ground_raw, ground]
		if vat_ok:
			if _vat.want(id, pp, WorldSim.target[id], WorldSim.job[id], WorldSim.phase[id], ground.y):
				_sprite_hidden.erase(id)
				continue
			# VAT cap reached: the old sprite rules apply
			if sprite_total >= sprite_budget:
				continue
			if _sprite_hidden.get(id, false):
				if entry[0] < release_r2:
					continue
				_sprite_hidden.erase(id)
			elif entry[0] < enter_r2:
				_sprite_hidden[id] = true
				continue
		var t := Transform3D(Basis(Vector3.UP, yaw), ground)
		(_multimeshes[look] as MultiMesh).set_instance_transform(n, t)
		used[look] = n + 1
		sprite_total += 1
	if _vat:
		_vat.end()
	for id in _sprite_routes.keys():
		if not active_sprite_ids.has(id) and not _full.has(id):
			_release_sprite_route(int(id))
	sprite_count = 0
	for look in _multimeshes:
		(_multimeshes[look] as MultiMesh).visible_instance_count = used[look]
		sprite_count += used[look]
	Probe.add("pop.sprites", _pt)


## Use the home's street graph only while this resident is near that settlement.
## Field/forest travel outside the graph remains the cheap WorldSim direct mover.
func _sprite_route_graph(id: int, here: Vector2, goal: Vector2) -> StreetGraph:
	var sid: int = WorldSim.home[id]
	if sid < 0 or sid >= WorldGen.settlements.size():
		return null
	var settlement: Dictionary = WorldGen.settlements[sid]
	var reach := float(settlement["radius"]) + 32.0
	var center: Vector2 = settlement["pos"]
	if here.distance_to(center) > reach and goal.distance_to(center) > reach:
		return null
	return StreetGraph.for_settlement(sid) as StreetGraph


## Move only visible impostors whose direct segment is obstructed. Their path is
## bounded by the sprite budget, planned under StreetGraph's existing route cap,
## and written to WorldSim while this temporary LOD owns position.
func _advance_sprite_route(id: int, from: Vector2, graph: StreetGraph, delta: float) -> Vector2:
	var goal: Vector2 = WorldSim.target[id]
	var state: Dictionary = _sprite_routes.get(id, {})
	if graph == null:
		if not state.is_empty():
			_release_sprite_route(id)
		return from
	var route_goal := graph.push_out(goal, 0.4)
	var target_clamped := route_goal.distance_squared_to(goal) > 0.25
	if graph.clear_line(from, route_goal, 0.4) and not target_clamped:
		if not state.is_empty():
			_release_sprite_route(id)
		return from
	if state.is_empty() or (state["goal"] as Vector2).distance_squared_to(goal) > 1.0:
		state = {"goal": goal, "points": PackedVector2Array(), "cursor": 0,
			"partial": false, "retry_ms": 0}
		_sprite_routes[id] = state
	var current := from
	var just_planned := false
	var points: PackedVector2Array = state["points"]
	if points.is_empty() and Time.get_ticks_msec() >= int(state["retry_ms"]):
		WorldSim.set_external_position_owner(id, get_instance_id(), true, current)
		if StreetGraph.take_route_budget():
			var start := graph.push_out(current, 0.4)
			var planned := graph.route(start, route_goal)
			var partial := graph.last_route_partial or target_clamped
			if partial and not planned.is_empty():
				var end := planned[planned.size() - 1]
				if end.distance_to(route_goal) > 0.5 and graph.clear_line(end, route_goal, 0.4):
					planned.append(route_goal)
					partial = target_clamped
			var clear := not planned.is_empty()
			var previous := start
			for point in planned:
				if not graph.clear_line(previous, point, 0.4):
					clear = false
					break
				previous = point
			if clear:
				current = start
				state["points"] = planned
				state["cursor"] = 0
				state["partial"] = partial
				state["retry_ms"] = 0
				points = planned
				just_planned = true
			else:
				state["retry_ms"] = Time.get_ticks_msec() + 2500
		else:
			state["retry_ms"] = Time.get_ticks_msec() + 500
	if not points.is_empty() and not just_planned:
		var remaining := WorldSim.WALK_SPEED * maxf(delta, 0.0)
		var cursor := int(state["cursor"])
		while cursor < points.size():
			var to := points[cursor] - current
			var distance := to.length()
			if distance <= 0.05:
				current = points[cursor]
				cursor += 1
				continue
			if remaining <= 0.0:
				break
			if distance <= remaining:
				current = points[cursor]
				remaining -= distance
				cursor += 1
			else:
				current += to / distance * remaining
				remaining = 0.0
				break
		state["cursor"] = cursor
		if cursor >= points.size():
			if not bool(state["partial"]):
				_release_sprite_route(id, current)
				return current
			if target_clamped and current.distance_to(route_goal) < 0.5:
				state["points"] = PackedVector2Array()
				state["retry_ms"] = 2147483647
				WorldSim.set_external_position_owner(id, get_instance_id(), true, current)
				return current
			state["points"] = PackedVector2Array()
			state["retry_ms"] = Time.get_ticks_msec() + 1000
	WorldSim.set_external_position_owner(id, get_instance_id(), true, current)
	return current


func _sprite_heading(id: int, fallback: Vector2) -> Vector2:
	var state: Dictionary = _sprite_routes.get(id, {})
	if state.is_empty():
		return fallback
	var points: PackedVector2Array = state["points"]
	var cursor := int(state["cursor"])
	return points[cursor] if cursor < points.size() else fallback


func _release_sprite_route(id: int, final_position := Vector2.INF) -> void:
	_sprite_routes.erase(id)
	_sprite_cache.erase(id)
	if final_position == Vector2.INF:
		WorldSim.set_external_position_owner(id, get_instance_id(), false, WorldSim.pos[id])
	else:
		WorldSim.set_external_position_owner(id, get_instance_id(), false, final_position)


## Embodied villagers' resolved positions -> WorldSim, so ranking, sprites,
## indoors checks and the villager's own demotion all start from where the
## body actually is.
func _write_back() -> void:
	for id in _full:
		var v := _full[id] as Villager
		WorldSim.set_external_position_owner(id, v.get_instance_id(), true, v.sim_position())


func _clock_skipped() -> bool:
	var now := WorldSim.day * 24.0 + WorldSim.time_of_day
	var skipped := _last_time >= 0.0 and absf(now - _last_time) > SKIP_HOURS
	_last_time = now
	return skipped


## Staggered departures for residents without a body: while their own clock
## lags WorldSim's phase, their WorldSim target is pinned to where they stand;
## when it catches up, the target WorldSim chose is restored and they set off.
func _update_holds(ids: PackedInt32Array) -> void:
	if not _held.is_empty():
		for id: int in _held.keys():
			if _full.has(id) or not DailyRhythm.lagging(id) or WorldSim.pos[id].distance_to(Vector2(focus.x, focus.z)) > _sprite_range + 40.0:
				_release_hold(id)
	if not DailyRhythm.in_lag_window():
		return
	for i in ids:
		if not _held.has(i) and not _full.has(i) and DailyRhythm.lagging(i):
			_held[i] = true
			WorldSim.target[i] = WorldSim.pos[i]


func _release_hold(id: int) -> void:
	_held.erase(id)
	var phase: int = WorldSim.phase[id]
	if phase != 255:
		WorldSim.target[id] = WorldSim._spot(WorldGen.settlements[WorldSim.home[id]], phase, id)


func _spawn(id: int) -> Villager:
	var look: String = JOB_LOOK[WorldSim.job[id]]
	var model: Array = LOOK_MODEL[look]
	var keep: Array[String] = []
	keep.assign(model[1])
	var v := Villager.create(id, model[0], keep)
	v.neighbours = _villagers
	_villagers.append(v)
	add_child(v)
	v.register_anim_lod(_anim_lod)
	return v
