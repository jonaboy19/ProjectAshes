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
const PresenceLive := preload("res://scripts/population/presence_live.gd")
const AlertGlyphs := preload("res://scripts/ui/alert_glyphs.gd")
const Takedown := preload("res://scripts/combat/takedown.gd")
const Probe := preload("res://scripts/core/perf_probe.gd")

const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const FULL_RANGE := 45.0       # defaults; the live values come from CellStreamer profile "population"
const SPRITE_RANGE := 220.0
const NEAR_ALWAYS := 9.0     # metres: never a sprite this close to the player
const NEAR_HARD_CAP := 8    # but never more than this many full models in total
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
const MAX_FULL := 18
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
## Recruits with a body of their own (stage 3, scripts/actors/follower_manager.gd): their rows are never drawn here.
const FollowerManager := preload("res://scripts/actors/follower_manager.gd")
## Ceiling on total sprites drawn (all job looks combined; see `refresh()`), not
## per look. Quality.npc_sprites narrows this further per tier.
const MAX_SPRITES := 120
## Full bodies built per rendered frame (see `_drain_spawns`). The refresh only queues; this is the whole spawn budget.
const MAX_SPAWNS_PER_FRAME := 1
## Contact-range villagers that use the multi-slide controller each physics
## frame, nearest-to-player first. A crowd event can put more into contact at
## once; overflow uses one swept collision query (see Villager.physics_active)
## with the same steering/speed/animation and no NPC-on-NPC collision. Profile
## both paths before changing this cap.
const MAX_PHYSICS_CONTACT := 4
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
var _vat_range := VAT_RANGE
var full_count := 0
var sprite_count := 0

var _full: Dictionary = {}        # person id -> Villager
var _multimeshes: Dictionary = {} # look -> MultiMesh
var _timer := 0.0
var _villagers: Array = []        # the Villager nodes in _full, shared with each of them
var _held: Dictionary = {}        # person id -> true while its departure is held back
var _last_time := -1.0
var _sprite_hidden: Dictionary = {}  # person id -> true while suppressed inside SPRITE_MIN_DIST
## Street scenes (cart passing, funeral, gates closing ...) of the settlement the player is in.
var micro: Node
var _sprite_routes: Dictionary = {}  # visible sprite id -> bounded StreetGraph route state
var _refresh_elapsed := 0.0
## Spawn queue (person ids, nearest first) and the want_full set of the last refresh it is drained against.
var _spawn_queue: Array[int] = []
var _spawn_queued: Dictionary = {}
var _want_full: Dictionary = {}
## False: refresh() builds its bodies at once (tests, screenshot tools) instead of one per frame.
var queue_spawns := true
## Sprite / VAT pass (perf60): refresh() decides WHO is drawn (rank, at most 1 Hz or after the focus moved RERANK_MOVE);
## the sweep keeps WHAT is drawn current. Per-row state lives in packed arrays indexed by WorldSim row.
const SPRITE_SLICE_US := 1000          # per frame
const SPRITE_FRAME_CAP := 48           # instances touched per frame
const RERANK_MOVE := 4.0
const RERANK_SECS := 1.0
const ROUTE_NEAREST := 40              # only the nearest drawn residents plan street routes
const MOVE_EPS2 := 0.0025              # 0.05 m: a drawn row that moved less is left alone
const NO_POS := Vector2(1.0e9, 1.0e9)
## 0 full body, 1 VAT, 2 sprite, 3 record (data only). No gameplay code reads it.
var tier := PackedByteArray()
var _want := PackedByteArray()         # tier the last rank asked for
var _stamp := PackedInt32Array()       # rank generation that last listed the row
var _slot := PackedInt32Array()        # MultiMesh slot of a sprite row
var _rli := PackedByteArray()          # look index of a sprite row
var _raw := PackedVector2Array()       # WorldSim.pos at the last placement
var _gpos := PackedVector2Array()      # where the ground sample was taken
var _rt := PackedByteArray()          # 1: one of the nearest ROUTE_NEAREST sprites (plans street routes)
var _hold_cursor := 0
var _cl_goal := PackedVector2Array()    # goal for which the straight line from the row was last found clear
var _gdraw := PackedVector2Array()     # drawn x/z (after push_out)
var _gy := PackedFloat32Array()
var _t_adv := PackedFloat64Array()     # seconds clock of the last placement (route integration step)
var _vis_rows := PackedInt32Array()    # rows wanted as VAT or sprite, nearest first
var _vis_cursor := 0
var _sweeping := false
var _looks: Array = []                 # look ids, index = look index
var _mm_list: Array = []               # MultiMesh per look index
var _job_li := PackedInt32Array()      # job -> look index
var _slot_rows := PackedInt32Array()   # look index * MAX_SPRITES + slot -> row
var _slot_n := PackedInt32Array()      # used slots per look index
var _rank_gen := 0
var _rank_age := 0.0
var _rank_focus := NO_POS
var _rank_head := 0                    # entries of the last rank that were ordered by full-body weight
## Living world (docs/anim/patches/P13_population_lod_vat.md). CrowdAnimLOD gives embodied villagers an animation LOD
## (NEAR full rate / MID stepped / FAR VAT twin). VatResidents draws residents WITHOUT a body inside VAT_RANGE as
## vertex-animated instances (no nodes); it replaces the sprite there and also fills the 20 m hole around the
## player. LOW tier keeps sprites only (VAT looks and far twins would add MultiMesh draw calls) and keeps the
## animation LOD, which only removes work.
const VAT_RANGE := 120.0
var _vat: VatResidents
var _anim_lod: CrowdAnimLOD
const PRESENCE_MAX := 6
var _presence_bodies: Array = []
var _presence := PresenceLive.new()      # Reactive Presence for the FULL tier (~10 Hz, observers staggered)
var _player_node: Node3D


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
		_looks.append(look)
		_mm_list.append(mm)
	_job_li.resize(JOB_LOOK.size())
	for j in JOB_LOOK.size():
		_job_li[j] = _looks.find(JOB_LOOK[j])
	_slot_rows.resize(_looks.size() * MAX_SPRITES)
	_slot_n.resize(_looks.size())
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
	FollowerManager.attach(self)        # recruits that follow, wait and work get their own bodies, inside a budget


func _process(delta: float) -> void:
	_drain_spawns()
	if _anim_lod.camera == null or not is_instance_valid(_anim_lod.camera):
		_anim_lod.camera = get_viewport().get_camera_3d()
	_tick_presence(delta)
	_timer -= delta
	_refresh_elapsed += delta
	if _sweeping:
		_sweep(SPRITE_SLICE_US)
	if _timer <= 0.0 and not _sweeping:
		_timer = 0.25
		var step := _refresh_elapsed
		_refresh_elapsed = 0.0
		if NpcWorld.profile:
			var t0 := Time.get_ticks_usec()
			refresh(step, true)
			NpcWorld.prof_lod_usec += Time.get_ticks_usec() - t0
			NpcWorld.prof_lod_calls += 1
		else:
			refresh(step, true)


func _tick_presence(delta: float) -> void:
	if _villagers.is_empty() and _presence.registered_count() == 0:
		return
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node3D
	var _pp := Probe.t()
	_presence.tick(delta, Time.get_ticks_msec(), _presence_bodies if Quality.is_pc() else _villagers, _player_node)
	Probe.add("pop.presence", _pp)


## Builds the next queued body (at most MAX_SPAWNS_PER_FRAME per call). A queued person who is no longer wanted by the last
## refresh (walked out of range, went indoors, got a body some other way) is dropped without a body.
func _drain_spawns() -> void:
	if _spawn_queue.is_empty():
		return
	var _pt := Probe.t()
	var built := 0
	while not _spawn_queue.is_empty() and built < MAX_SPAWNS_PER_FRAME:
		var id: int = _spawn_queue.pop_front()
		_spawn_queued.erase(id)
		if _full.has(id) or not _want_full.has(id) or WorldSim.is_indoors(id):
			continue
		_full[id] = _spawn(id)
		full_count = _full.size()
		built += 1
	Probe.add("pop.spawn", _pt)


## Builds every queued body now.
func flush_spawns() -> void:
	while not _spawn_queue.is_empty():
		var id: int = _spawn_queue.pop_front()
		_spawn_queued.erase(id)
		if _full.has(id) or not _want_full.has(id) or WorldSim.is_indoors(id):
			continue
		_full[id] = _spawn(id)
	full_count = _full.size()


## A recruit just got a body of their own: drop the villager body (or queued one) they had here.
func evict_person(id: int) -> void:
	_spawn_queued.erase(id)
	_spawn_queue.erase(id)
	if not _full.has(id):
		return
	var v := _full[id] as Villager
	_anim_lod.unregister(id)
	_villagers.erase(v)
	v.queue_free()
	_full.erase(id)
	_ensure_arrays()
	tier[id] = 3


func queued_spawns() -> int:
	return _spawn_queue.size()


func refresh(step_delta := 0.25, spread := false) -> void:
	spread = spread and not Probe.legacy
	if _sweeping:
		_sweep(0)        # a sync caller (teleport, tool): finish the pass in flight first
	_ensure_arrays()
	_rank_age += step_delta
	var _pt := Probe.t()
	var skipped := _clock_skipped()
	if skipped:
		# WorldSim just placed everyone (advance_hours / load): it is the truth now.
		# Drop temporary sprite routes without writing their old positions over
		# destinations chosen by this explicit time skip.
		for id in _sprite_routes:
			WorldSim.set_external_position_owner(int(id), get_instance_id(), false)
		_sprite_routes.clear()
		_raw.fill(NO_POS)
		_gpos.fill(NO_POS)
		_cl_goal.fill(NO_POS)
		for id in _full:
			(_full[id] as Villager).resync()
	else:
		_write_back()
	Probe.add("pop.write_back", _pt)
	_pt = Probe.t()
	var p2 := Vector2(focus.x, focus.z)
	# Transform-only refresh: the ranking (who is drawn, who gets a body) is redone at most once a second or after the
	# focus moved RERANK_MOVE; in between the sweep just follows the rows that moved. Sync callers always re-rank.
	if spread and not skipped and _rank_focus != NO_POS and _rank_age < RERANK_SECS \
			and p2.distance_squared_to(_rank_focus) < RERANK_MOVE * RERANK_MOVE:
		_sweep_begin()
		_sweep(SPRITE_SLICE_US)
		return
	_rank_age = 0.0
	_rank_focus = p2
	_full_range = CellStreamer.shared().distance("population", "full")      # F12: the cell manager owns the bands
	_sprite_range = CellStreamer.shared().distance("population", "load")
	_vat_range = VAT_RANGE
	if Quality.is_pc():      # PC rows own the bands (docs/qa/perf: NPC density pass); phones keep the CellStreamer profile
		_full_range = float(Quality.value("pop_full_range"))
		_sprite_range = float(Quality.value("pop_sprite_range"))
		_vat_range = float(Quality.value("vat_range"))
	# The nearest want_n residents come straight out of the cell grid (WorldSim.index), nearest first: no whole-settlement scan,
	# no full sort. want_n is what the tier can show (bodies + sprites) with headroom for the ones filtered out below.
	var want_n := (NEAR_HARD_CAP + mini(MAX_FULL, Quality.npc_full) + mini(MAX_SPRITES, Quality.npc_sprites)) * 5
	var ids := WorldSim.people_in_ring(p2, 0.0, _sprite_range, want_n)
	Probe.add("pop.q_ring", _pt)
	var _ph := Probe.t()
	_update_holds(ids)
	Probe.add("pop.q_holds", _ph)
	Probe.add("pop.query", _pt)
	_pt = Probe.t()
	var morning := WorldSim.time_of_day >= 6.0 and WorldSim.time_of_day < 6.0 + DailyRhythm.MAX_DELAY
	var dists := []
	for i in ids:
		if WorldSim.is_indoors(i) or (morning and DailyRhythm.still_home(i)):
			continue
		if FollowerManager.owns(i):
			continue            # a recruit: the follower manager owns this row and gives it its own body
		if Takedown.is_down(i):
			continue            # a body on the ground (KO'd / dead): no sprite, no respawn; the node keeps lying below
		var d2: float = WorldSim.pos[i].distance_squared_to(p2)
		# Named residents (the town kit's rosters) rank as if closer, so they are the ones who get bodies first.
		dists.append([d2, i, (d2 * KEEP_BIAS if _full.has(i) else d2) * TownRoster.embody_weight(i)])
	Probe.add("pop.dists", _pt)
	_pt = Probe.t()
	# `dists` is already nearest first. Only the head (everyone who could win a full body: weighted distance within the full
	# band, or inside NEAR_ALWAYS) is re-ordered by weighted distance; the tail keeps its order.
	var head_r2 := maxf(_full_range * _full_range, NEAR_ALWAYS * NEAR_ALWAYS) / (KEEP_BIAS * 0.55)
	var head_n := 0
	while head_n < dists.size() and (dists[head_n] as Array)[0] <= head_r2:
		head_n += 1
	if head_n > 1:
		var keys := PackedFloat64Array()
		keys.resize(head_n)
		for k in head_n:
			keys[k] = floorf(float((dists[k] as Array)[2]) * 256.0) * 1024.0 + float(k)       # native sort, ties by list order
		keys.sort()
		var ordered: Array = []
		ordered.resize(head_n)
		for k in head_n:
			ordered[k] = dists[int(fposmod(keys[k], 1024.0))]
		dists = ordered + dists.slice(head_n)
	_rank_head = head_n
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
		if not FollowerManager.owns(id) and not WorldSim.is_indoors(id) and v.global_position.distance_squared_to(focus) < CONTACT_KEEP * CONTACT_KEEP:
			want_full[id] = true
			continue
		_anim_lod.unregister(id)
		_villagers.erase(v)
		v.queue_free()
		_full.erase(id)
		tier[id] = 3
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
	# Bodies are queued (nearest first, the order of want_full) and built ONE per frame by _drain_spawns(): a Villager costs
	# 3.7-6 ms to build (about 20-30 ms on the S22), and three in one refresh was a visible hitch. They still appear, a frame apart,
	# at the edge of the full-model band or where a teleport put the player.
	_want_full = want_full
	for id in want_full:
		if not _full.has(id) and not _spawn_queued.has(id):
			_spawn_queue.append(id)
			_spawn_queued[id] = true
	if not queue_spawns:
		flush_spawns()
	Probe.add("pop.spawn_queue", _pt)
	_pt = Probe.t()
	# Promotion transfers the same position-owner flag to the body. Discard any
	# old visual route so demotion can plan again from the body's resolved point.
	for id in _full:
		_sprite_routes.erase(id)
	full_count = _full.size()
	var nearest_id: int = -1
	var nearest_d := 20.0     # squared: the one name plate shows within ~4.5 m (was 6 m)
	for k in head_n:
		var entry: Array = dists[k]
		if _full.has(entry[1]) and entry[0] < nearest_d:
			nearest_d = entry[0]
			nearest_id = entry[1]
	for id in _full:
		(_full[id] as Villager).show_tag = id == nearest_id
	# Reactive presence (observers, glances, greetings) only for the nearest full-AI bodies on PC (NPC density research: think-count small).
	_presence_bodies = []
	for k in head_n:
		var entry: Array = dists[k]
		if _full.has(entry[1]):
			_presence_bodies.append(_full[entry[1]])
			if _presence_bodies.size() >= PRESENCE_MAX:
				break
	var physics_candidates: Array = []
	for k in head_n:
		var entry: Array = dists[k]
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
	_rank_visible(dists)
	Probe.add("pop.rank", _pt)
	_pt = Probe.t()
	_sweep_begin()
	if spread:
		_sweep(SPRITE_SLICE_US)      # the rest runs from _process, a slice per frame
	else:
		_sweep(0)
	Probe.add("pop.sprites", _pt)


func _ensure_arrays() -> void:
	var n := WorldSim.population()
	if tier.size() == n:
		return
	tier.resize(n)
	tier.fill(3)
	_want.resize(n)
	_want.fill(3)
	_stamp.resize(n)
	_stamp.fill(0)
	_slot.resize(n)
	_slot.fill(-1)
	_rli.resize(n)
	_raw.resize(n)
	_raw.fill(NO_POS)
	_gpos.resize(n)
	_gpos.fill(NO_POS)
	_cl_goal.resize(n)
	_cl_goal.fill(NO_POS)
	_rt.resize(n)
	_rt.fill(0)
	_gdraw.resize(n)
	_gy.resize(n)
	_t_adv.resize(n)
	_t_adv.fill(0.0)
	_vis_rows = PackedInt32Array()
	_slot_n.fill(0)
	sprite_count = 0
	for mm: MultiMesh in _mm_list:
		mm.visible_instance_count = 0


## Decide who is drawn: walk the ranked list nearest first and give every row its tier. Rows that dropped out of the list leave
## now (one swap-remove for a sprite); rows that entered or changed tier are placed by the sweep, a slice per frame.
func _rank_visible(dists: Array) -> void:
	_rank_gen += 1
	var gen := _rank_gen
	var sprite_budget := mini(MAX_SPRITES, Quality.npc_sprites)
	var vat_r2 := _vat_range * _vat_range
	var enter_r2 := SPRITE_MIN_DIST * SPRITE_MIN_DIST
	var release_r2 := SPRITE_MIN_DIST_RELEASE * SPRITE_MIN_DIST_RELEASE
	var vat_cap: int = _vat.cap if _vat != null else 0
	var vat_planned := 0
	var sprite_total := 0
	var vis := PackedInt32Array()
	if _sprite_hidden.size() > 4000:
		_sprite_hidden.clear()
	for entry: Array in dists:
		var id: int = entry[1]
		var d2: float = entry[0]
		var vat_ok: bool = _vat != null and d2 < vat_r2 and vat_planned < vat_cap
		# dists is nearest first, so once the budget is spent everyone further away is skipped: the crowd is capped in total.
		if sprite_total >= sprite_budget and not vat_ok:
			break
		if _full.has(id):
			_sprite_hidden.erase(id)
			_sprite_routes.erase(id)
			continue
		if not vat_ok:
			# Nobody without a full model is drawn as a sprite this close (SPRITE_MIN_DIST); hysteresis keeps the edge calm.
			if _sprite_hidden.get(id, false):
				if d2 < release_r2:
					continue
				_sprite_hidden.erase(id)
			elif d2 < enter_r2:
				_sprite_hidden[id] = true
				continue
		_stamp[id] = gen
		vis.append(id)
		if vat_ok:
			_want[id] = 1
			vat_planned += 1
		else:
			_want[id] = 2
			_rt[id] = 1 if sprite_total < ROUTE_NEAREST else 0
			sprite_total += 1
	# Leavers: drawn last time, not listed now.
	for id in _vis_rows:
		if _stamp[id] != gen:
			_want[id] = 3
			if tier[id] == 1 or tier[id] == 2:
				_leave(id)
	# Anything still drawn that this rank dropped before it was ever in the list (full-body takeovers happen in _spawn).
	_vis_rows = vis


func _leave(r: int) -> void:
	var t := tier[r]
	if t == 2:
		_slot_remove(r)
	elif t == 1 and _vat != null:
		_vat.release(r)
	tier[r] = 3
	_raw[r] = NO_POS
	_cl_goal[r] = NO_POS
	if _sprite_routes.has(r):
		_release_sprite_route(r)


func _slot_add(r: int, li: int, xf: Transform3D) -> bool:
	var n := _slot_n[li]
	if n >= MAX_SPRITES:
		return false
	var mm := _mm_list[li] as MultiMesh
	mm.set_instance_transform(n, xf)
	_slot_rows[li * MAX_SPRITES + n] = r
	_slot[r] = n
	_rli[r] = li
	_slot_n[li] = n + 1
	mm.visible_instance_count = n + 1
	sprite_count += 1
	return true


func _slot_remove(r: int) -> void:
	var li := _rli[r]
	var at := _slot[r]
	var last := _slot_n[li] - 1
	var mm := _mm_list[li] as MultiMesh
	if at != last:
		var moved := _slot_rows[li * MAX_SPRITES + last]
		mm.set_instance_transform(at, mm.get_instance_transform(last))
		_slot_rows[li * MAX_SPRITES + at] = moved
		_slot[moved] = at
	_slot_n[li] = last
	mm.visible_instance_count = last
	_slot[r] = -1
	sprite_count -= 1


## A full body took this row over (see _spawn): it is no longer a sprite or VAT figure.
func _drop_visible(r: int) -> void:
	if tier.size() != WorldSim.population():
		return
	_want[r] = 0
	if tier[r] == 1 or tier[r] == 2:
		_leave(r)
	tier[r] = 0


func sprite_job_busy() -> bool:
	return _sweeping


func _sweep_begin() -> void:
	_vis_cursor = 0
	_sweeping = true


## Walk the drawn set: enter / change-tier rows are placed, the others only when they moved more than 5 cm (or follow a route).
## At most SPRITE_FRAME_CAP rows are touched and SPRITE_SLICE_US spent per call (0 = to the end). Returns true when the pass is done.
func _sweep(slice_us: int) -> bool:
	if not _sweeping:
		return true
	var _pt := Probe.t()
	var t_start := Time.get_ticks_usec()
	var p2 := Vector2(focus.x, focus.z)
	var n := _vis_rows.size()
	var work := 0
	var checked := 0
	var now := Time.get_ticks_msec() * 0.001
	while _vis_cursor < n:
		if slice_us > 0:
			checked += 1
			if work >= SPRITE_FRAME_CAP or (((checked & 15) == 0 or (work & 3) == 3) and Time.get_ticks_usec() - t_start > slice_us):
				break
		var idx := _vis_cursor
		_vis_cursor += 1
		var r := _vis_rows[idx]
		var wt := _want[r]
		if wt == 0 or wt == 3:
			continue
		if tier[r] == wt:
			# Cadence: nearest sprites (street routes) 4 Hz; VAT figures walk on their own between updates and everyone else
			# follows at 1 Hz.
			if now - _t_adv[r] < (0.2 if _rt[r] != 0 and wt == 2 else 1.0):
				continue
		elif _full.has(r):
			continue
		if tier[r] != wt:
			if tier[r] != 3:
				_leave(r)
			_place(r, idx, p2)
			work += 1
			continue
		if (WorldSim.pos[r] - _raw[r]).length_squared() <= MOVE_EPS2 and not _sprite_routes.has(r) \
				and not (wt == 1 and _vat.walking(r)):
			continue
		_place(r, idx, p2)
		work += 1
	Probe.add("pop.sprites_slice", _pt)
	if _vis_cursor < n:
		return false
	_sweeping = false
	return true


## Put one resident on screen (enter) or bring it up to date (moved): route step for the nearest ROUTE_NEAREST, ground sample,
## then the VAT figure or the sprite slot.
func _place(r: int, rank_i: int, p2: Vector2) -> void:
	var raw := WorldSim.pos[r]
	var tgt := WorldSim.target[r]
	var now := Time.get_ticks_msec() * 0.001
	var dt := clampf(now - _t_adv[r], 0.0, 1.0) if _t_adv[r] > 0.0 else 0.25
	_t_adv[r] = now
	var pp := raw
	var _ps := Probe.t()
	if _rt[r] != 0 and _want[r] == 2:
		# WorldSim walks straight toward the goal: a line that was clear stays clear until the goal changes.
		if _cl_goal[r] != tgt or _sprite_routes.has(r):
			pp = _advance_sprite_route(r, raw, _sprite_route_graph(r, raw, tgt), dt)
			_cl_goal[r] = NO_POS if _sprite_routes.has(r) else tgt
	elif _sprite_routes.has(r):
		_release_sprite_route(r)
	Probe.add("sprj.advance", _ps)
	_raw[r] = raw
	_ps = Probe.t()
	var near_ground := pp.distance_squared_to(p2) < 8100.0       # push_out and terrain height only matter within 90 m
	if _gpos[r] == NO_POS or pp.distance_squared_to(_gpos[r]) > (MOVE_EPS2 if near_ground else 9.0):
		var q := pp
		if near_ground:
			var g := StreetGraph.for_person(r) as StreetGraph
			if g:
				q = g.push_out(pp, 0.3)
		_gdraw[r] = q
		_gy[r] = WorldGen.height(q.x, q.y)
		_gpos[r] = pp
	Probe.add("sprj.ground", _ps)
	var q2 := _gdraw[r]
	var gy := _gy[r]
	var wt := _want[r]
	if wt == 1:
		_ps = Probe.t()
		var ok := _vat != null and _vat.want(r, q2, tgt, WorldSim.job[r], WorldSim.phase[r], gy)
		Probe.add("sprj.vat", _ps)
		if ok:
			tier[r] = 1
			_sprite_hidden.erase(r)
			return
		# VAT cap reached or no bake fits: the sprite rules apply
		if sprite_count >= mini(MAX_SPRITES, Quality.npc_sprites) or pp.distance_squared_to(p2) < SPRITE_MIN_DIST * SPRITE_MIN_DIST:
			_want[r] = 3
			return
		_want[r] = 2
	var li := _job_li[WorldSim.job[r]]
	var heading := _sprite_heading(r, tgt) - pp
	var yaw := atan2(heading.x, heading.y) if heading.length() > 0.1 else float(r % 628) / 100.0
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q2.x, gy, q2.y))
	if tier[r] == 2:
		(_mm_list[li] as MultiMesh).set_instance_transform(_slot[r], xf)
	elif _slot_add(r, li, xf):
		tier[r] = 2
	else:
		_want[r] = 3


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
	# lagging() is ~16 us a row: the 40 nearest are checked every rank, the rest of the list in rotating slices of 48.
	var n := ids.size()
	var near_n := mini(n, 40)
	var rest := n - near_n
	var todo := near_n + mini(rest, 48)
	var start := _hold_cursor % maxi(rest, 1)
	_hold_cursor += 48
	for k in todo:
		var i := ids[k] if k < near_n else ids[near_n + (start + k - near_n) % rest]
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
	_drop_visible(id)
	return v
