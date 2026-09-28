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

const FULL_RANGE := 45.0
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
## Ceiling on total sprites drawn (all job looks combined; see `refresh()`), not
## per look. Quality.npc_sprites narrows this further per tier.
const MAX_SPRITES := 140
const MAX_SPAWNS_PER_TICK := 3
## Contact-range villagers that actually run move_and_slide() each physics frame,
## nearest-to-player first. A crowd event (flee hazard) can put many more than
## this into contact range at once; move_and_slide()'s narrow-phase collision
## cost against a dense cluster of capsules is the expensive part, so the rest
## fall back to plain kinematic movement (see Villager.physics_active) -- same
## steering, speed and animation, just no per-pair collision resolution.
const MAX_PHYSICS_CONTACT := 8
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


func setup(baker: ImpostorBaker) -> void:
	for look: String in LOOK_MODEL:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ImpostorBaker.quad()
		mm.instance_count = MAX_SPRITES
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = baker.materials.get(look)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1500, 10000))
		add_child(mmi)
		_multimeshes[look] = mm


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		refresh()


func refresh() -> void:
	var skipped := _clock_skipped()
	if skipped:
		# WorldSim just placed everyone (advance_hours / load): it is the truth now.
		for id in _full:
			(_full[id] as Villager).resync()
	else:
		_write_back()
	var p2 := Vector2(focus.x, focus.z)
	var ids := WorldSim.people_near(p2, SPRITE_RANGE)
	_update_holds(ids)
	var morning := WorldSim.time_of_day >= 6.0 and WorldSim.time_of_day < 6.0 + DailyRhythm.MAX_DELAY
	var dists := []
	for i in ids:
		if WorldSim.is_indoors(i) or (morning and DailyRhythm.still_home(i)):
			continue
		var d2: float = WorldSim.pos[i].distance_squared_to(p2)
		dists.append([d2, i, d2 * KEEP_BIAS if _full.has(i) else d2])
	dists.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])

	var want_full := {}
	# Anyone this close must be a real model: a flat sprite at arm's length looks broken,
	# so the tier budget may be exceeded up to NEAR_HARD_CAP inside NEAR_ALWAYS.
	for entry in dists:
		if entry[2] > FULL_RANGE * FULL_RANGE and entry[0] > NEAR_ALWAYS * NEAR_ALWAYS:
			break
		var within_budget: bool = want_full.size() < mini(MAX_FULL, Quality.npc_full) and entry[0] <= FULL_RANGE * FULL_RANGE
		var too_close_for_sprite: bool = entry[0] <= NEAR_ALWAYS * NEAR_ALWAYS and want_full.size() < NEAR_HARD_CAP
		if not (within_budget or too_close_for_sprite):
			continue
		want_full[entry[1]] = true
	for id in _full.keys():
		if want_full.has(id):
			continue
		var v: Villager = _full[id]
		# Someone standing against the player keeps their body until they step away.
		if not WorldSim.is_indoors(id) and v.global_position.distance_squared_to(focus) < CONTACT_KEEP * CONTACT_KEEP:
			want_full[id] = true
			continue
		_villagers.erase(v)
		v.queue_free()
		_full.erase(id)
	var spawned := 0
	for id in want_full:
		if not _full.has(id) and spawned < MAX_SPAWNS_PER_TICK:
			_full[id] = _spawn(id)
			spawned += 1
	full_count = _full.size()
	var nearest_id: int = -1
	var nearest_d := 36.0
	for entry in dists:
		if _full.has(entry[1]) and entry[0] < nearest_d:
			nearest_d = entry[0]
			nearest_id = entry[1]
	for id in _full:
		(_full[id] as Villager).show_tag = id == nearest_id
	var physics_slots := 0
	for entry in dists:
		if not _full.has(entry[1]):
			continue
		var v: Villager = _full[entry[1]]
		v.physics_active = physics_slots < MAX_PHYSICS_CONTACT
		physics_slots += 1

	var used := {}
	for look in _multimeshes:
		used[look] = 0
	var sprite_budget: int = mini(MAX_SPRITES, Quality.npc_sprites)
	var sprite_total := 0
	if _sprite_hidden.size() > 4000:
		_sprite_hidden.clear()
	var enter_r2 := SPRITE_MIN_DIST * SPRITE_MIN_DIST
	var release_r2 := SPRITE_MIN_DIST_RELEASE * SPRITE_MIN_DIST_RELEASE
	for entry in dists:
		# dists is sorted nearest-first, so once the budget is spent everyone
		# further away is skipped: the crowd is capped in total, not per look.
		if sprite_total >= sprite_budget:
			break
		var id: int = entry[1]
		if _full.has(id):
			_sprite_hidden.erase(id)
			continue
		# Nobody without a full model is drawn as a sprite this close (see
		# SPRITE_MIN_DIST above); hysteresis keeps the on/off edge from chattering.
		if _sprite_hidden.get(id, false):
			if entry[0] < release_r2:
				continue
			_sprite_hidden.erase(id)
		elif entry[0] < enter_r2:
			_sprite_hidden[id] = true
			continue
		var look: String = JOB_LOOK[WorldSim.job[id]]
		var n: int = used[look]
		var pp: Vector2 = WorldSim.pos[id]
		var heading: Vector2 = WorldSim.target[id] - pp
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
			var raw := pp
			var graph := StreetGraph.for_person(id) as StreetGraph
			if graph and entry[0] < 90.0 * 90.0:
				pp = graph.push_out(pp, 0.3)
			ground = Vector3(pp.x, WorldGen.height(pp.x, pp.y), pp.y)
			_sprite_cache[id] = [raw, ground]
		var t := Transform3D(Basis(Vector3.UP, yaw), ground)
		(_multimeshes[look] as MultiMesh).set_instance_transform(n, t)
		used[look] = n + 1
		sprite_total += 1
	sprite_count = 0
	for look in _multimeshes:
		(_multimeshes[look] as MultiMesh).visible_instance_count = used[look]
		sprite_count += used[look]


## Embodied villagers' resolved positions -> WorldSim, so ranking, sprites,
## indoors checks and the villager's own demotion all start from where the
## body actually is.
func _write_back() -> void:
	for id in _full:
		WorldSim.pos[id] = (_full[id] as Villager).sim_position()


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
			if _full.has(id) or not DailyRhythm.lagging(id) or WorldSim.pos[id].distance_to(Vector2(focus.x, focus.z)) > SPRITE_RANGE + 40.0:
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
	return v
