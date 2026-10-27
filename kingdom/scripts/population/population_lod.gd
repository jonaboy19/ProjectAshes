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
const PopVisibilityLog := preload("res://scripts/population/pop_visibility_log.gd")

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

## Bands are measured from here. main.gd sets it to the player every frame; when the active camera is far from that
## (a scripted / cutscene / fly-through camera while the player stays parked) the camera wins, so the people in shot
## get bodies and VAT instead of far sprites (towns slice footage 2026-10-28: sprites at 3-10 m from the lens).
var focus := Vector3.ZERO:
	set(v):
		focus = _camera_focus(v)
const SCRIPTED_CAM_GAP := 20.0
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
var _sprite_cache: Dictionary = {}   # person id -> [raw pos, pushed-out ground point]
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
var _query_r := 0.0             # adaptive people_near radius (see refresh)
## No pops on screen (spawn QA): residents drawn (sprite / VAT) after the last pass, and the camera of this pass.
## A resident that would appear or vanish INSIDE the view and nearer than VIS_GATE x its band edge waits for the
## view to turn away (appear) or keeps being drawn (vanish, up to VIS_HOLD_MAX extra) instead.
const VIS_GATE := 0.85
const VIS_HOLD_MAX := 64
## --no-vis-gate: old behaviour (A/B for the spawn QA logs).
static var vis_gate := not OS.get_cmdline_user_args().has("--no-vis-gate")
var _drawn_prev: Dictionary = {}       # id -> 1 sprite / 2 vat
var _changed_off_view: Dictionary = {}   # --pop-log: ids whose representation changed while out of the (wide) view
var _drawn_prev_before: Dictionary = {}   # --pop-log diagnostics: _drawn_prev of the pass before
var _vis_cam: Camera3D
var _sprite_mats: Array = []          # impostor materials: their fade_far follows the sprite band (no edge pops)
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
		_sprite_mats.append(mmi.material_override)
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
	FollowerManager.attach(self)        # recruits that follow, wait and work get their own bodies, inside a budget


func _process(delta: float) -> void:
	PopVisibilityLog.tick(delta)
	_drain_spawns()
	if _anim_lod.camera == null or not is_instance_valid(_anim_lod.camera):
		_anim_lod.camera = get_viewport().get_camera_3d()
	_tick_presence(delta)
	_timer -= delta
	_refresh_elapsed += delta
	if not _sj.is_empty():
		_sprite_job_step(SPRITE_SLICE_US)
	if _timer <= 0.0 and _sj.is_empty():
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
	var tries := _spawn_queue.size()
	while not _spawn_queue.is_empty() and built < MAX_SPAWNS_PER_FRAME and tries > 0:
		tries -= 1
		var id: int = _spawn_queue.pop_front()
		_spawn_queued.erase(id)
		if _full.has(id) or not _want_full.has(id) or WorldSim.is_indoors(id):
			continue
		# A body that would appear from nothing in view (stepping out of a door, entering the band): wait until the view
		# turns, unless it is right next to the player. Residents shown as VAT / sprite hand over in place instead.
		# also a resident still drawn as a sprite in view (no in-place hand-off from an impostor): wait for the view to turn
		var as_sprite_in_view: bool = vis_gate and int(_drawn_prev.get(id, 0)) == 1 and (WorldSim.pos[id] as Vector2).distance_squared_to(Vector2(focus.x, focus.z)) > 25.0 and _vis_cam_sees(Vector3((WorldSim.pos[id] as Vector2).x, focus.y, (WorldSim.pos[id] as Vector2).y))
		if as_sprite_in_view or (vis_gate and not _drawn_prev.has(id) and _spawn_hidden_from_view(id)):
			_spawn_queue.append(id)
			_spawn_queued[id] = true
			continue
		if vis_gate and not _vis_cam_sees(Vector3((WorldSim.pos[id] as Vector2).x, focus.y, (WorldSim.pos[id] as Vector2).y)):
			_changed_off_view[id] = true
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


func queued_spawns() -> int:
	return _spawn_queue.size()


func _camera_focus(v: Vector3) -> Vector3:
	if not is_inside_tree():
		return v
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return v
	var c := cam.global_position
	if Vector2(c.x - v.x, c.z - v.z).length_squared() < SCRIPTED_CAM_GAP * SCRIPTED_CAM_GAP:
		return v
	return Vector3(c.x, WorldGen.height(c.x, c.z), c.z)


func refresh(step_delta := 0.25, spread := false) -> void:
	spread = spread and not Probe.legacy
	if not _sj.is_empty():
		_sprite_job_step(0)        # a sync caller (teleport, tool): finish the pass in flight first
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
	_vat_range = VAT_RANGE
	if Quality.is_pc():      # PC rows own the bands (docs/qa/perf: NPC density pass); phones keep the CellStreamer profile
		_full_range = float(Quality.value("pop_full_range"))
		_sprite_range = float(Quality.value("pop_sprite_range"))
		_vat_range = float(Quality.value("vat_range"))
	# Band-edge fades instead of pops (camera sits ~5 m behind the focus): sprites fade out at the far edge; the VAT tier
	# fades out over its last 18 m and the sprite that replaces a resident there fades in over the next 18 m.
	for m in _sprite_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("fade_far", _sprite_range + 6.0)
			(m as ShaderMaterial).set_shader_parameter("fade_near", (_vat_range + 23.0) if _vat else 0.0)
	if _vat:
		_vat.crowd.set_fade(_vat_range + 5.0)
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
		if FollowerManager.owns(i):
			continue            # a recruit: the follower manager owns this row and gives it its own body
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
	var _kept_in_view := 0
	for id in _full.keys():
		if want_full.has(id):
			continue
		var v: Villager = _full[id]
		# A body on the ground stays where it fell while the player is anywhere near.
		if v.is_down() and v.global_position.distance_squared_to(focus) < 90.0 * 90.0:
			continue
		# In view and not going indoors: keep the body until the view turns (spawn QA: no body vanishing on screen).
		if vis_gate and _kept_in_view < 12 and not WorldSim.is_indoors(id) and v.global_position.distance_squared_to(focus) < _full_range * _full_range * 2.25 and _vis_cam_sees(v.global_position):
			want_full[id] = true
			_kept_in_view += 1
			continue
		# Someone standing against the player keeps their body until they step away.
		if not FollowerManager.owns(id) and not WorldSim.is_indoors(id) and v.global_position.distance_squared_to(focus) < CONTACT_KEEP * CONTACT_KEEP:
			want_full[id] = true
			continue
		_anim_lod.unregister(id)
		_villagers.erase(v)
		v.queue_free()
		_full.erase(id)
		_drawn_prev[id] = 2          # the crowd tier may take this resident over at once (it was visible a moment ago)
		if vis_gate and not _vis_cam_sees(v.global_position):
			_changed_off_view[id] = true
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
	for entry in dists:
		if _full.has(entry[1]) and entry[0] < nearest_d:
			nearest_d = entry[0]
			nearest_id = entry[1]
	for id in _full:
		(_full[id] as Villager).show_tag = id == nearest_id
	# Reactive presence (observers, glances, greetings) only for the nearest full-AI bodies on PC (NPC density research: think-count small).
	_presence_bodies = []
	for entry in dists:
		if _full.has(entry[1]):
			_presence_bodies.append(_full[entry[1]])
			if _presence_bodies.size() >= PRESENCE_MAX:
				break
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
	_sprite_job_begin(dists, step_delta)
	if spread:
		_sprite_job_step(SPRITE_SLICE_US)      # the rest runs from _process, a slice per frame
	else:
		_sprite_job_step(0)
	Probe.add("pop.sprites", _pt)


## The sprite pass of refresh() as a resumable job: 100+ residents were placed in one go (27 ms avg, 60-125 ms worst, 4x a second in a
## capital), now a slice of SPRITE_SLICE_US per frame. Same loop, same results; only the frame the last sprite lands in moves.
const SPRITE_SLICE_US := 4000
var _sj: Dictionary = {}


func _sprite_job_begin(dists: Array, step_delta: float) -> void:
	var used := {}
	for look in _multimeshes:
		used[look] = 0
	if _vat:
		_vat.begin()
	if _sprite_hidden.size() > 4000:
		_sprite_hidden.clear()
	_sj = {"dists": dists, "i": 0, "used": used, "total": 0, "active": {}, "step": step_delta, "vat": {}}


func sprite_job_busy() -> bool:
	return not _sj.is_empty()


## Runs the pending sprite pass for at most slice_us (0 = to the end). Returns true when it finished.
func _sprite_job_step(slice_us: int) -> bool:
	if _sj.is_empty():
		return true
	var _pt := Probe.t()
	var t_start := Time.get_ticks_usec()
	var dists: Array = _sj["dists"]
	var dn := dists.size()
	var i: int = _sj["i"]
	var used: Dictionary = _sj["used"]
	var sprite_total: int = _sj["total"]
	var active_sprite_ids: Dictionary = _sj["active"]
	var step_delta: float = _sj["step"]
	var sprite_budget: int = mini(MAX_SPRITES, Quality.npc_sprites)
	var vat_r2 := _vat_range * _vat_range
	var enter_r2 := SPRITE_MIN_DIST * SPRITE_MIN_DIST
	var release_r2 := SPRITE_MIN_DIST_RELEASE * SPRITE_MIN_DIST_RELEASE
	var break_early := false
	while i < dn:
		var entry: Array = dists[i]
		i += 1
		if slice_us > 0 and (i & 7) == 0 and Time.get_ticks_usec() - t_start > slice_us:
			break_early = true
			break
		# dists is sorted nearest-first, so once the budget is spent everyone
		# further away is skipped: the crowd is capped in total, not per look.
		var id: int = entry[1]
		var vat_ok: bool = _vat != null and entry[0] < vat_r2
		if sprite_total >= sprite_budget and not vat_ok:
			i = dn
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
		# appear-deny: someone not drawn last pass does not pop into view mid-screen (they are drawn once off-view)
		if vis_gate and not _drawn_prev.has(id):
			if _on_view(id, entry[0], vat_ok):
				continue
			_changed_off_view[id] = true
		active_sprite_ids[id] = true
		var raw := WorldSim.pos[id]
		var _ps1 := Probe.t()
		var graph := _sprite_route_graph(id, raw, WorldSim.target[id])
		Probe.add("sprj.graph", _ps1)
		_ps1 = Probe.t()
		var pp := _advance_sprite_route(id, raw, graph, step_delta)
		Probe.add("sprj.advance", _ps1)
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
		_ps1 = Probe.t()
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
		Probe.add("sprj.ground", _ps1)
		_ps1 = Probe.t()
		if vat_ok and vis_gate and int(_drawn_prev.get(id, 0)) == 1 and _on_view(id, entry[0], false):
			vat_ok = false        # keep the sprite while in view; the VAT twin takes over once the view turns
		if vat_ok and vis_gate and int(_drawn_prev.get(id, 0)) == 1:
			_changed_off_view[id] = true     # sprite -> VAT happens only out of view (the hold above)
		if vat_ok:
			if _vat.want(id, pp, WorldSim.target[id], WorldSim.job[id], WorldSim.phase[id], ground.y):
				_sprite_hidden.erase(id)
				(_sj["vat"] as Dictionary)[id] = true
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
		Probe.add("sprj.vat", _ps1)
		var t := Transform3D(Basis(Vector3.UP, yaw), ground)
		(_multimeshes[look] as MultiMesh).set_instance_transform(n, t)
		used[look] = n + 1
		sprite_total += 1
	_sj["i"] = i
	_sj["total"] = sprite_total
	if break_early:
		Probe.add("pop.sprites_slice", _pt)
		return false
	# vanish-hold: drawn last pass, still in view and near: keep drawing the last representation this pass
	var held := 0
	for id: int in (_drawn_prev if vis_gate else {}):
		if held >= VIS_HOLD_MAX:
			break
		if active_sprite_ids.has(id) or _full.has(id) or WorldSim.is_indoors(id) or Takedown.is_down(id) or FollowerManager.owns(id):
			continue
		var p2h: Vector2 = WorldSim.pos[id]
		var d2h := p2h.distance_squared_to(Vector2(focus.x, focus.z))
		var was_vat: bool = int(_drawn_prev[id]) == 2
		if not _on_view(id, d2h, was_vat):
			continue
		var gy := WorldGen.height(p2h.x, p2h.y)
		if was_vat and _vat:
			if _vat.want(id, p2h, WorldSim.target[id], WorldSim.job[id], WorldSim.phase[id], gy):
				active_sprite_ids[id] = true
				(_sj["vat"] as Dictionary)[id] = true
				held += 1
			continue
		var lk: String = JOB_LOOK[WorldSim.job[id]]
		var nn: int = used[lk]
		if nn >= MAX_SPRITES:
			continue
		var hd := _sprite_heading(id, WorldSim.target[id]) - p2h
		var yw := atan2(hd.x, hd.y) if hd.length() > 0.1 else float(id % 628) / 100.0
		(_multimeshes[lk] as MultiMesh).set_instance_transform(nn, Transform3D(Basis(Vector3.UP, yw), Vector3(p2h.x, gy, p2h.y)))
		used[lk] = nn + 1
		active_sprite_ids[id] = true
		held += 1
	_drawn_prev_before = _drawn_prev
	_drawn_prev = {}
	for id in active_sprite_ids:
		_drawn_prev[id] = 2 if (_sj["vat"] as Dictionary).has(id) else 1
	if PopVisibilityLog.enabled:
		_pop_log_report(active_sprite_ids, _sj["vat"])
	_sj = {}
	if _vat:
		_vat.end()
	for id in _sprite_routes.keys():
		if not active_sprite_ids.has(id) and not _full.has(id):
			_release_sprite_route(int(id))
	sprite_count = 0
	for look in _multimeshes:
		(_multimeshes[look] as MultiMesh).visible_instance_count = used[look]
		sprite_count += used[look]
	Probe.add("pop.sprites_slice", _pt)
	return true


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


func _vis_cam_sees(p: Vector3) -> bool:
	if _vis_cam == null or not is_instance_valid(_vis_cam) or not _vis_cam.current:
		_vis_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	return _vis_cam != null and _in_wide_view(p + Vector3(0, 1.0, 0))


func _spawn_hidden_from_view(id: int) -> bool:
	var d2 := (WorldSim.pos[id] as Vector2).distance_squared_to(Vector2(focus.x, focus.z))
	if d2 <= NEAR_ALWAYS * NEAR_ALWAYS:
		return false
	return _on_view(id, d2, false)


## True when resident `id` (squared distance d2 to the focus) is inside the camera view and nearer than VIS_GATE of its
## draw band (VAT or sprite range): a change there would be a visible pop.
func _on_view(id: int, d2: float, vat_band: bool) -> bool:
	if _vis_cam == null or not is_instance_valid(_vis_cam) or not _vis_cam.current:
		_vis_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
		if _vis_cam == null:
			return false
	var band := (_vat_range if vat_band else _sprite_range) * VIS_GATE
	if d2 > band * band:
		return false
	var p: Vector2 = WorldSim.pos[id]
	return _in_wide_view(Vector3(p.x, WorldGen.height(p.x, p.y) + 1.0, p.y))


## In view with a margin: the gates run on a time-sliced pass while the camera keeps turning, so "in view" means
## within the horizontal FOV + VIEW_MARGIN_DEG either side (anything about to enter the view counts as seen).
const VIEW_MARGIN_DEG := 30.0
func _in_wide_view(w: Vector3) -> bool:
	var cxf := _vis_cam.global_transform
	var to := w - cxf.origin
	var fwd := -cxf.basis.z
	to.y = 0.0
	fwd.y = 0.0
	if to.length() < 0.5:
		return true
	var aspect := 16.0 / 9.0
	var vp := get_viewport()
	if vp:
		var sz := vp.get_visible_rect().size
		aspect = sz.x / maxf(sz.y, 1.0)
	var half_h := rad_to_deg(atan(tan(deg_to_rad(_vis_cam.fov) * 0.5) * aspect))
	return rad_to_deg(fwd.normalized().angle_to(to.normalized())) < half_h + VIEW_MARGIN_DEG


## --pop-log: every resident's representation after a finished refresh (see PopVisibilityLog).
func _pop_log_report(active: Dictionary, vat_ids: Dictionary) -> void:
	var st := {}
	for id in active:
		st[id] = PopVisibilityLog.Rep.VAT if vat_ids.has(id) else PopVisibilityLog.Rep.SPRITE
	for id in vat_ids:
		st[id] = PopVisibilityLog.Rep.VAT
	for id in _full:
		st[id] = PopVisibilityLog.Rep.FULL
	var full := _full
	var pos_of := func(id: int) -> Vector3:
		if full.has(id) and is_instance_valid(full[id]):
			return (full[id] as Node3D).global_position
		if id < 0 or id >= WorldSim.population():
			return Vector3.INF
		var p: Vector2 = WorldSim.pos[id]
		return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	# sprites crossing the far edge of the band are dither-faded by the impostor shader (fade_far): not a pop
	var faded := {}
	var edge := (_sprite_range - 24.0) * (_sprite_range - 24.0)
	for id in st:
		if int(st[id]) == PopVisibilityLog.Rep.SPRITE and (WorldSim.pos[id] as Vector2).distance_squared_to(Vector2(focus.x, focus.z)) > edge:
			faded[id] = true
	# bodies that took over a VAT instance in place (same look, pose, clip time): a hand-off, not a pop
	for id in _full:
		var fv = _full[id]
		if is_instance_valid(fv) and not (fv as Villager).handoff.is_empty():
			faded[id] = true
	var vr := _vat_range if _vat else -1000.0
	var sr := _sprite_range
	# changes inside the dither bands (VAT fade-out vr-18..vr, sprite fade-in vr..vr+23, sprite fade-out sr-24..sr+6)
	var in_band := func(d: float) -> bool: return (d > vr - 20.0 and d < vr + 25.0) or d > sr - 26.0
	var prev_seen := _drawn_prev_before
	var why := func(id: int) -> String:
		var d2 := (WorldSim.pos[id] as Vector2).distance_squared_to(Vector2(focus.x, focus.z)) if id >= 0 and id < WorldSim.population() else -1.0
		return "prev=%s view=%s hidden=%s queued=%s held=%s indoors=%s home_am=%s near=%s" % [prev_seen.get(id, 0), _on_view(id, d2, true) if d2 >= 0.0 else false, _sprite_hidden.get(id, false), _spawn_queued.has(id), _held.has(id), WorldSim.is_indoors(id), DailyRhythm.still_home(id), d2 <= _query_r * _query_r]
	for id in _changed_off_view:
		faded[id] = true      # decided while out of the (wide) view: invisible when it happened, not a pop
	_changed_off_view.clear()
	PopVisibilityLog.report(get_viewport().get_camera_3d(), focus, st, pos_of, faded, in_band, why)


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
	if _vat:
		v.handoff = _vat.handoff(id)       # same look, pose, place and clip time as the VAT instance it replaces
	v.neighbours = _villagers
	_villagers.append(v)
	add_child(v)
	v.register_anim_lod(_anim_lod)
	return v
