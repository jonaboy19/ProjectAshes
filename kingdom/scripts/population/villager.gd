class_name Villager
extends CharacterBody3D
## The embodied form of one WorldSim person near the player.
##
## While embodied, this body owns the resident's movement; WorldSim keeps the
## intent (job, home, schedule) and PopulationLOD writes the resolved position
## back into the simulation (NPC_CONTACT_LOD_CONTRACT: one movement owner).
##
##  - Route: along the settlement's streets and door paths (StreetGraph), never
##    the straight line through a house; light steering keeps clear of walls,
##    other villagers and the player.
##  - Contact tier: only villagers within CONTACT_ENTER of the player enable
##    their capsule and move with move_and_slide(); farther ones move along
##    their route without a physics body.
##  - Gait: accelerates, brakes into arrival, turns at a bounded rate and slows
##    for sharp corners; the walk clip plays at the body's resolved speed over
##    its measured ground speed, so feet don't slide.
##  - Choices: a UtilityBrain scores what to do next (sleep, eat, work, shop,
##    chat, inn, pray, fetch water, shelter from rain, flee, watch the player)
##    every DECIDE_INTERVAL on a per-person phase; DailyRhythm's staggered
##    schedule is one of its considerations, so the street still fills and
##    empties gradually. This body executes the chosen act: walk the route,
##    perform at the spot (clip, facing, going indoors), idle otherwise.
##  - Thinking (contact tier, spacing, stuck checks, facing) runs every
##    THINK_INTERVAL on a per-person phase, not every frame.

const StreetGraph := preload("res://scripts/population/street_graph.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const Act := UtilityBrain.Act

const WORLD_LAYER := 1
const LOCAL_ACTOR_LAYER := 2
const BODY_RADIUS := 0.28
## Measured ground speed and cycle of the walk/run clips (docs/qa/anim_qa_report.md).
const WALK_CLIP_SPEED := 0.98
const WALK_CYCLE_SECONDS := 1.33
const RUN_CLIP_SPEED := 5.82
const RUN_CYCLE_SECONDS := 0.93
## Normal pace. Plays the walk clip at about 1.2x: close enough to its measured
## 0.98 m/s that the cadence reads as walking, not scurrying.
const WALK_SPEED := 1.18
const ACCELERATION := 1.6
const BRAKING := 2.8
## Heading change limit, radians per second.
const TURN_RATE := 4.2
const ARRIVE_RADIUS := 0.45
const WAYPOINT_RADIUS := 0.8
## Capsule on inside this distance from the player, off again past CONTACT_EXIT.
## At the player's 6.5 m/s run, 14 m is two seconds of warning.
const CONTACT_ENTER := 14.0
const CONTACT_EXIT := 17.0
## Beyond this (and out of contact range), the AnimationPlayer stops advancing
## every physics frame and is stepped manually at LOD_ANIM_HZ instead: a distant
## villager's gait reads the same at 12 Hz, and skinned-mesh update is most of a
## full NPC's per-frame cost. Beyond LOD_SHADOW_DIST it also stops casting a sun
## shadow: at that range the shadow map contribution isn't visible under the body.
const LOD_ANIM_DIST := 12.0
const LOD_ANIM_HZ := 12.0
const LOD_SHADOW_DIST := 15.0
## Step aside when the player comes this close.
const YIELD_RADIUS := 1.7
const SEPARATION_RADIUS := 0.9
const PERSONAL_SPACE := 1.2
const THINK_INTERVAL := 0.3
## Utility decisions: slow, staggered per person (a multiple of THINK_INTERVAL).
const DECIDE_INTERVAL := 0.9
## Real seconds an act is held (commitment bonus) after arriving at its spot.
const MIN_PERFORM := 8.0
## Pace multipliers: running from danger, hurrying out of the rain.
const FLEE_PACE := 2.7
const SHELTER_PACE := 1.35
## Seconds each speaker holds the floor in a chat.
const TURN_SECONDS := 4.0
## Clip candidates per act, first one the rig has wins (UAL / UAL extras).
const ACT_CLIPS := {
	Act.SHOP: ["Idle_Talking", "Interact"],
	Act.INN: ["Idle_Talking", "Cheering_Two_Hands"],
	Act.PRAY: ["G6_pray", "Taichi_Idle", "Meditate", "Fixing_Kneeling"],
	Act.WATER: ["G6_gathering", "Chore_Pick_Up_Box", "Interact", "PickUp_Table"],
	Act.SHELTER: ["Shivering", "Idle_Subtle"],
	Act.FLEE: ["Shivering", "Idle_Hurt"],
	Act.WATCH: ["Idle_Listening", "Idle_Subtle"],
	Act.SLEEP: ["Lie_Down_Idle", "Sitting_Idle"], Act.HOME: ["Chore_Sweep", "Sitting_Idle"], Act.EAT: ["Consume_Item", "Sitting_Idle"],
}
const TALK_CLIPS := ["Idle_Talking"]
const LISTEN_CLIPS := ["Idle_Listening", "Head_Nod", "Idle_Talking"]
const ALONE_CLIPS := ["Idle_Subtle"]
const JOB_CLIPS := [["Farm_Harvest"], ["Fixing_Kneeling"], ["Idle_Talking"], ["Idle_Shield"], ["Interact"], ["TreeChopping"]]
## Stuck check window and the progress expected in it.
const STUCK_WINDOW := 1.2
const STUCK_PROGRESS := 0.3
const STEP_RANGE := 11.0
const WORK_SOUND_RANGE := 16.0
## Activity clip -> [sound, fraction of the clip where the tool lands]. Approximate
## impact points until the clips carry contact markers.
const WORK_SOUNDS := {"TreeChopping": ["chop_wood", 0.5], "Fixing_Kneeling": ["hammer_nail", 0.45]}

## Last time any villager played a footstep: shares the positional voice pool
## with combat, so the crowd gets at most one step per 70 ms.
static var _last_step_ms := 0

var person := -1
## Set by PopulationLOD for the single nearest villager.
var show_tag := false
## Villagers PopulationLOD currently embodies (for spacing). Shared array.
var neighbours: Array = []
var _file := ""
var _keep: Array[String] = []
var _anim: AnimationPlayer
var _meshes: Array[GeometryInstance3D] = []
var _anim_lod := false
var _anim_accum := 0.0
var _shadow_lod := false
var _tag: Label3D
var _tag_timer := 0.0
var _shape: CollisionShape3D
var _graph: StreetGraph
var _look_target: Node3D
var _look_timer := 0.0
var _player: Node3D

# Schedule and route.
var _state := -1
var _goal := Vector2.INF
var _path := PackedVector2Array()
var _path_i := 0
var _needs_route := false
var _arrived := false
var _think := 0.0

# Choice (UtilityBrain) and its execution.
var _brain: UtilityBrain
var _act := -1
var _decide := 0.0
var _perform_time := 0.0
var _plan_indoors := false
var _indoors := false
var _face_pref := Vector2.INF     # direction to stand facing at the spot
var _look_point := Vector2.INF    # WATCH: what to look at
var _partner := -1                # SOCIAL: chat partner person
var _partner_node: Node3D
var _face_now := Vector2.INF      # resolved each think tick
var _pace := 1.0
var _activity_want := ""
var _clip_cache := {}

# Motion.
var _walk_speed := WALK_SPEED
var _move_speed := 0.0
var _heading := 0.0
var _resolved_speed := 0.0
var _separation := Vector2.ZERO
var _player_push := Vector2.ZERO
var _avoid := Vector2.ZERO
var _contact := false
## Set by PopulationLOD (once per refresh, ~4 Hz): true for only the nearest
## MAX_PHYSICS_CONTACT contact-range villagers to the player. During a crowd
## event (e.g. a flee hazard) many villagers can be in contact range at once;
## running move_and_slide() for all of them is the expensive part (narrow-phase
## collision against each other), so the rest fall back to the same direct
## kinematic move non-contact villagers already use. Steering, speed, animation
## and footsteps are unaffected -- only which capsules resolve collisions.
var physics_active := true
var _yield_time := 0.0
var _yield_cooldown := 0.0
var _yield_to := Vector2.ZERO
var _yield_face := false
var _stuck_timer := 0.0
var _stuck_from := Vector2.ZERO
var _stuck_count := 0
var _wait := 0.0

# Presentation.
var _walking := false
var _step_distance := 0.0
var _surface := "grass"
var _surface_timer := 0.0
var _activity_name := ""
var _activity_needs_start := true
var _activity_pause := 0.0
var _cue_done := false
var _cue_last := 0.0


static func create(id: int, file: String, keep: Array[String]) -> Villager:
	var v := Villager.new()
	v.person = id
	v._file = file
	v._keep = keep
	return v


func _ready() -> void:
	add_to_group("villager")
	# Villagers block the player and solid world geometry, but don't shove one
	# another into jams. The player includes LOCAL_ACTOR_LAYER in its mask.
	collision_layer = LOCAL_ACTOR_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = 1.25
	_shape.shape = capsule
	_shape.position.y = capsule.height * 0.5
	_shape.disabled = true
	add_child(_shape)
	var model := Assets.character(_file, 1.7, _keep)
	add_child(model)
	_anim = Assets.animation_player(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n as GeometryInstance3D)
	_add_head_look(model)
	_attach_components(model)
	_graph = StreetGraph.for_person(person) as StreetGraph
	# Promotion: start where the simulation had this person, moved out of any
	# footprint it cut through, facing the way they were heading.
	var p: Vector2 = WorldSim.pos[person]
	if _graph:
		p = _graph.push_out(p, BODY_RADIUS + 0.12)
	position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	var heading: Vector2 = WorldSim.target[person] - p
	_heading = atan2(heading.x, heading.y) if heading.length() > 0.1 else float(person % 628) / 100.0
	rotation.y = _heading
	# Stable per-person variation: pace, think phase, gait phase.
	var h := hash(person * 2654435761 + 7)
	_walk_speed = WALK_SPEED * (0.9 + float(h % 200) / 1000.0)
	_think = float((h / 200) % 1000) / 1000.0 * THINK_INTERVAL
	_stuck_from = p
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.pixel_size = 0.004
	_tag.font_size = 32
	_tag.outline_size = 8
	_tag.position.y = 1.95
	_tag.modulate = Color(1, 0.95, 0.85)
	add_child(_tag)
	_tag.text = WorldSim.describe(person)
	_brain = _make_brain()
	UtilityBrain.register_body(person, self)
	# First decision now, later ones on this person's own phase.
	_decide = 0.0
	_think_tick()
	_decide = float((h / 7) % 1000) / 1000.0 * DECIDE_INTERVAL


func _exit_tree() -> void:
	UtilityBrain.unregister_body(person)


## Components other systems attach to an embodied villager's model go here
## (e.g. a procedural rig: `model.add_child(ProceduralRig.new())`). Called once,
## right after the model, AnimationPlayer and head look exist.
func _attach_components(_model: Node3D) -> void:
	pass


## Brain for this person: seeded personality, career shift if they hold a seat,
## needs seeded from the hour they were met.
func _make_brain() -> UtilityBrain:
	var shift := Vector2(-1, -1)
	var org_id := ""
	var life := get_node_or_null("/root/Life")
	if life and life.get("careers") != null:
		var held: Dictionary = life.careers.holder_of(person)
		if not held.is_empty():
			var org: Dictionary = held["org"]
			shift = org.get("shift", shift)
			org_id = String(org.get("id", ""))
	var b := UtilityBrain.new(person, WorldSim.job[person], shift, org_id)
	b.seed_needs(DailyRhythm.local_time(person), WorldSim.day)
	return b


## Resolved position for WorldSim (PopulationLOD writes it back).
func sim_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## WorldSim moved everyone (time skip / load): take its position as the new
## truth, settle outside footprints and plan again.
func resync() -> void:
	var p: Vector2 = WorldSim.pos[person]
	if _graph:
		p = _graph.push_out(p, BODY_RADIUS + 0.12)
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	velocity = Vector3.ZERO
	_move_speed = 0.0
	_resolved_speed = 0.0
	_path = PackedVector2Array()
	_path_i = 0
	_state = -1
	_goal = Vector2.INF
	_arrived = false
	_yield_time = 0.0
	_stuck_from = p
	_stuck_count = 0
	_step_distance = 0.0
	# Hours may have passed: fresh needs, fresh choice.
	UtilityBrain.chat_leave(person)
	_set_indoors(false)
	_act = -1
	_brain.act = -1
	_brain.seed_needs(DailyRhythm.local_time(person), WorldSim.day)
	_decide = 0.0


func _physics_process(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think += THINK_INTERVAL
		_think_tick()
	if _indoors:
		# Inside a building: nothing to move, draw or animate until the next choice.
		_perform_time += delta
		return
	if _arrived and _yield_time <= 0.0:
		_perform_time += delta
		if _plan_indoors:
			_set_indoors(true)
			return
	var here := Vector2(global_position.x, global_position.z)
	if _contact:
		_check_yield(here, delta)
	var planar := _steer(here, delta)
	if _contact and physics_active:
		velocity = Vector3(planar.x, 0.0, planar.y)
		move_and_slide()
	elif planar != Vector2.ZERO:
		global_position += Vector3(planar.x, 0.0, planar.y) * delta
	var moved := Vector2(global_position.x, global_position.z) - here
	global_position.y = WorldGen.height(global_position.x, global_position.z)
	rotation.y = _heading
	# Animation follows the resolved body speed (a blocked villager stops its feet).
	var measured := moved.length() / maxf(delta, 0.001)
	_resolved_speed = lerpf(_resolved_speed, measured, 1.0 - exp(-14.0 * delta))
	if _anim_lod:
		# Throttled: accumulate real time and refresh the clip/pose at LOD_ANIM_HZ
		# instead of every physics tick, stepping the manual player by what elapsed.
		_anim_accum += delta
		if _anim_accum >= 1.0 / LOD_ANIM_HZ:
			var step := _anim_accum
			_anim_accum = 0.0
			_update_animation(step)
			if _anim:
				_anim.advance(step)
	else:
		_update_animation(delta)
	_update_head_look(delta)
	_tag.visible = show_tag


# ---------------------------------------------------------------- thinking
func _think_tick() -> void:
	var here := Vector2(global_position.x, global_position.z)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var player_distance := INF
	if _player:
		player_distance = here.distance_to(Vector2(_player.global_position.x, _player.global_position.z))
	_set_contact(not _indoors and (player_distance < CONTACT_ENTER or (_contact and player_distance < CONTACT_EXIT)))
	_apply_distance_lod(player_distance)
	_decide -= THINK_INTERVAL
	if _decide <= 0.0:
		_decide += DECIDE_INTERVAL
		_decide_act(here)
	if _indoors:
		return
	_update_facing(here)
	_activity_want = _activity_for_person()
	if _needs_route and _yield_time <= 0.0 and _wait <= 0.0 and StreetGraph.take_route_budget():
		_plan_route(here)
	var travelling := _path_i < _path.size()
	_avoid = _graph.repulse(here, 1.0) if _graph and travelling else Vector2.ZERO
	_separation = _neighbour_push(here)
	if travelling and _yield_time <= 0.0:
		_check_stuck(here)
	else:
		_stuck_timer = 0.0
		_stuck_from = here
	if _contact and _walking:
		_surface_timer -= THINK_INTERVAL
		if _surface_timer <= 0.0:
			_surface_timer = 1.5
			_surface = Audio.surface_at(global_position) if Audio.has_method("surface_at") \
				else WorldGen.footstep_surface(global_position.x, global_position.z)
	_tag_timer -= THINK_INTERVAL
	if show_tag and _tag_timer <= 0.0:
		_tag_timer = 1.0
		_tag.text = "%s\n%s" % [WorldSim.describe(person), UtilityBrain.label(_act, travelling)]


# ---------------------------------------------------------------- choosing
## One utility decision (every DECIDE_INTERVAL): sense, update needs, score,
## and turn a new act into a goal. Same act: only dynamic goals are refreshed.
func _decide_act(here: Vector2) -> void:
	var tree := get_tree()
	var hazards := UtilityBrain.hazards(tree)
	var danger := UtilityBrain.danger_at(here, hazards)
	var player_p := Vector2.INF
	if _player:
		player_p = Vector2(_player.global_position.x, _player.global_position.z)
	var sight := UtilityBrain.spectacle_at(here, player_p, hazards)
	var performing := _indoors or (_arrived and _yield_time <= 0.0)
	_brain.tick(WorldSim.day * 24.0 + WorldSim.time_of_day, _act if performing else -1)
	_state = DailyRhythm.state(person)
	var sid: int = WorldSim.home[person]
	var company := UtilityBrain.chat_waiting(sid, person) or UtilityBrain.chat_partner(person) >= 0
	var ctx := _brain.context(DailyRhythm.local_time(person), _state, UtilityBrain.is_raining(tree),
		danger[0], sight[0], company, float(WorldSim.money[person]) / 60.0, WorldSim.day)
	var committed := not performing or _perform_time < MIN_PERFORM
	var act := _brain.decide(ctx, committed)
	if act != _act:
		if _act == Act.SOCIAL:
			UtilityBrain.chat_leave(person)
		_act = act
		_apply_plan(here, danger[1], sight[1])
		return
	match act:
		Act.FLEE:
			# Still in danger at the end of the run: keep going from here.
			if _arrived and not _plan_indoors:
				_apply_plan(here, danger[1], sight[1])
		Act.WATCH:
			if sight[1] != Vector2.INF and (sight[1] as Vector2).distance_to(_look_point) > 3.0:
				_apply_plan(here, danger[1], sight[1])
		Act.SOCIAL:
			if _partner < 0:
				_partner = UtilityBrain.chat_partner(person)


func _apply_plan(here: Vector2, hazard: Vector2, look: Vector2) -> void:
	var plan := _brain.plan_goal(_act, here, _graph, hazard, look)
	var goal: Vector2 = plan["goal"]
	_plan_indoors = plan["indoors"]
	_face_pref = plan["face"]
	_look_point = plan["look"]
	_partner = plan["partner"]
	_pace = FLEE_PACE if _act == Act.FLEE else (SHELTER_PACE if _act == Act.SHELTER else 1.0)
	_perform_time = 0.0
	_interrupt_activity()
	var was_inside := _indoors
	_set_indoors(false)
	if was_inside and _plan_indoors and goal.distance_to(sim_position()) < 1.0:
		_set_indoors(true)    # e.g. eat -> sleep: stay in
		return
	if _goal == Vector2.INF or goal.distance_to(_goal) > 1.0 or not _arrived:
		_goal = goal
		_needs_route = true
		_arrived = false


## Inside a building: hidden, no capsule, not a talk target.
func _set_indoors(on: bool) -> void:
	if on == _indoors:
		return
	_indoors = on
	visible = not on
	if on:
		remove_from_group("villager")
		_set_contact(false)
		_move_speed = 0.0
		_resolved_speed = 0.0
		_walking = false
		_path = PackedVector2Array()
		_path_i = 0
	else:
		add_to_group("villager")


## Which way to stand while performing: the chat partner, what is being
## watched, or the spot's own facing. Resolved on think ticks only.
func _update_facing(here: Vector2) -> void:
	_face_now = Vector2.INF
	if _partner >= 0 and UtilityBrain.chat_partner(person) != _partner:
		_partner = -1    # they walked off: carry on alone
	_partner_node = UtilityBrain.body_of(_partner) if _partner >= 0 else null
	if not _arrived:
		return
	if _partner_node:
		_face_now = Vector2(_partner_node.global_position.x, _partner_node.global_position.z) - here
	elif _look_point != Vector2.INF:
		_face_now = _look_point - here
	elif _face_pref != Vector2.INF:
		_face_now = _face_pref


func _plan_route(here: Vector2) -> void:
	_needs_route = false
	if here.distance_to(_goal) < ARRIVE_RADIUS:
		_path = PackedVector2Array()
		_path_i = 0
		_arrived = true
		return
	_path = _graph.route(here, _goal) if _graph else PackedVector2Array([_goal])
	_path_i = 0
	_arrived = false
	_stuck_count = 0
	_stuck_timer = 0.0
	_stuck_from = here


## Capsule on near the player, off (and plain route following) farther out.
func _set_contact(on: bool) -> void:
	if on == _contact:
		return
	_contact = on
	_shape.set_deferred("disabled", not on)
	if not on:
		velocity = Vector3.ZERO
		_player_push = Vector2.ZERO


## Distance-only throttling: never changes what plays, only how often it's
## refreshed. Contact-range villagers (about to be touched or stepped around)
## are excluded from both, so nothing changes for anyone the player can reach.
func _apply_distance_lod(player_distance: float) -> void:
	var want_anim := player_distance > LOD_ANIM_DIST and not _contact
	if want_anim != _anim_lod:
		_anim_lod = want_anim
		if _anim:
			_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if want_anim \
				else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
			_anim_accum = 0.0
	var want_shadow := player_distance > LOD_SHADOW_DIST
	if want_shadow != _shadow_lod:
		_shadow_lod = want_shadow
		var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if want_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for m in _meshes:
			if is_instance_valid(m):
				m.cast_shadow = mode


func _neighbour_push(here: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for other_node in neighbours:
		if other_node == self or not is_instance_valid(other_node):
			continue
		var other := other_node as Node3D
		var away := here - Vector2(other.global_position.x, other.global_position.z)
		var distance := away.length()
		if distance < SEPARATION_RADIUS:
			if distance < 0.01:
				away = Vector2.RIGHT.rotated(float(person) * 2.399)
				distance = 0.01
			push += away / distance * (SEPARATION_RADIUS - distance) / SEPARATION_RADIUS
	return push.limit_length(1.2)


## Desired progress vs actual: slow down, sidestep, re-plan, then skip a
## blocked waypoint. Never teleports through the blocker.
func _check_stuck(here: Vector2) -> void:
	_stuck_timer += THINK_INTERVAL
	if _stuck_timer < STUCK_WINDOW:
		return
	var progress := here.distance_to(_stuck_from)
	_stuck_timer = 0.0
	_stuck_from = here
	if progress >= STUCK_PROGRESS or _move_speed < 0.05:
		_stuck_count = 0
		return
	_stuck_count += 1
	match _stuck_count:
		1:
			var side := Vector2(cos(_heading), -sin(_heading)) * (1.0 if person % 2 == 0 else -1.0)
			_begin_sidestep(here, side, 0.9)
		2, 4:
			_needs_route = true
		3:
			if _path_i < _path.size() - 1:
				_path_i += 1
		_:
			# Wait a moment for the way to clear, then try a fresh route.
			_wait = 2.0 + float(person % 7) * 0.2
			_needs_route = true
			_stuck_count = 0


# ---------------------------------------------------------------- yielding
func _check_yield(here: Vector2, delta: float) -> void:
	_yield_cooldown = maxf(_yield_cooldown - delta, 0.0)
	_player_push = Vector2.ZERO
	if _player == null:
		return
	var rel := here - Vector2(_player.global_position.x, _player.global_position.z)
	var d := rel.length()
	if d > YIELD_RADIUS or d < 0.001:
		return
	# Personal space: ease away from the player while close.
	if d < PERSONAL_SPACE:
		_player_push = rel / d * (PERSONAL_SPACE - d) / PERSONAL_SPACE
	if _yield_cooldown > 0.0 or _yield_time > 0.0:
		return
	var player_velocity := Vector2.ZERO
	if _player is CharacterBody3D:
		var pv := (_player as CharacterBody3D).velocity
		player_velocity = Vector2(pv.x, pv.z)
	var away := rel / d
	var approaching := player_velocity.length() > 0.5 and player_velocity.normalized().dot(away) > 0.3
	var walking_into := _move_speed > 0.2 and Vector2(sin(_heading), cos(_heading)).dot(-away) > 0.5
	if not (d < 1.0 or approaching or walking_into):
		return
	# Step off the player's line, to the side this villager is already on.
	var line := player_velocity.normalized() if player_velocity.length() > 0.5 else -away
	var side := Vector2(-line.y, line.x)
	if side.dot(away) < 0.0:
		side = -side
	_begin_sidestep(here, side + away * 0.3, 1.0 + float(person % 5) * 0.1, true)
	_yield_cooldown = _yield_time + 1.5
	_interrupt_activity()


## Brief step to a clear spot beside the current position, then resume.
func _begin_sidestep(here: Vector2, direction: Vector2, duration: float, face_player := false) -> void:
	var dir := direction.normalized()
	var target := here + dir * 1.1
	if _graph:
		target = _graph.push_out(target, BODY_RADIUS + 0.1)
		if not _graph.clear_line(here, target, BODY_RADIUS):
			target = _graph.push_out(here - dir * 1.1, BODY_RADIUS + 0.1)
			if not _graph.clear_line(here, target, BODY_RADIUS):
				target = here
	_yield_to = target
	_yield_time = duration
	_yield_face = face_player
	# Afterwards, head on (re-planned from the new spot) or back to the activity spot.
	if _path_i < _path.size() or _arrived:
		_needs_route = true


func _interrupt_activity() -> void:
	_activity_name = ""
	_activity_needs_start = true
	_activity_pause = 0.0


# ---------------------------------------------------------------- steering
## Planar velocity for this tick: route following with braking and bounded
## turns, plus wall/crowd spacing.
func _steer(here: Vector2, delta: float) -> Vector2:
	var target_speed := 0.0
	var dir := Vector2.ZERO
	var face := Vector2.INF
	if _wait > 0.0:
		_wait = maxf(_wait - delta, 0.0)
	if _yield_time > 0.0:
		_yield_time = maxf(_yield_time - delta, 0.0)
		var to := _yield_to - here
		var d := to.length()
		if d > 0.12:
			dir = to / d
			target_speed = _walk_speed * clampf(d / 0.6, 0.35, 0.9)
		elif _yield_face and _player:
			face = Vector2(_player.global_position.x, _player.global_position.z) - here
	elif _wait <= 0.0 and _path_i < _path.size():
		var wp := _path[_path_i]
		var to := wp - here
		var d := to.length()
		var last := _path_i == _path.size() - 1
		if last and d < ARRIVE_RADIUS:
			_path_i += 1
			_arrived = true
		elif not last and d < WAYPOINT_RADIUS:
			_path_i += 1
		else:
			dir = to / maxf(d, 0.001)
			target_speed = _walk_speed * _pace
			if last:
				# Brake into the arrival spot instead of overshooting it.
				target_speed = minf(target_speed, sqrt(2.0 * BRAKING * maxf(d - ARRIVE_RADIUS * 0.5, 0.0)))
			elif d < 2.0:
				# Ease off for a sharp corner at the next waypoint.
				var next := _path[_path_i + 1] - wp
				if next.length() > 0.01:
					var sharp := 1.0 - clampf(dir.dot(next.normalized()), 0.0, 1.0)
					target_speed *= 1.0 - 0.45 * sharp * (1.0 - d / 2.0)
	var crowd := _separation + _player_push * 1.5
	var steer := dir + _avoid * 0.8 + crowd * 1.4
	if target_speed <= 0.0 and crowd.length() > 0.35:
		# Standing still but crowded: shuffle over to make room.
		steer = crowd
		target_speed = 0.35
	if target_speed > 0.0 and steer.length_squared() > 0.0001:
		face = steer
	elif face == Vector2.INF and _face_now != Vector2.INF:
		# At the spot: turn to the partner, the spectacle or the spot's facing.
		face = _face_now
	if face != Vector2.INF and face.length_squared() > 0.0001:
		var diff := wrapf(atan2(face.x, face.y) - _heading, -PI, PI)
		_heading = wrapf(_heading + clampf(diff, -TURN_RATE * delta, TURN_RATE * delta), -PI, PI)
		# Turn on the spot rather than moonwalk: slow while facing away.
		target_speed *= clampf(cos(diff) * 0.6 + 0.4, 0.15, 1.0)
	var response := ACCELERATION * (2.0 if _pace > 2.0 else 1.0) if target_speed > _move_speed else BRAKING
	_move_speed = move_toward(_move_speed, target_speed, response * delta)
	if _move_speed < 0.005:
		return Vector2.ZERO
	return Vector2(sin(_heading), cos(_heading)) * _move_speed


# ---------------------------------------------------------------- animation
func _update_animation(delta: float) -> void:
	if not _walking and _resolved_speed > 0.14:
		_walking = true
	elif _walking and _resolved_speed < 0.07 and _move_speed < 0.1:
		_walking = false
	if not _walking:
		_update_activity(delta)
		return
	_interrupt_activity()
	var running := _resolved_speed > 2.2
	var clip := "Running_A" if running else "Walking_A"
	var clip_speed := RUN_CLIP_SPEED if running else WALK_CLIP_SPEED
	var cycle_seconds := RUN_CYCLE_SECONDS if running else WALK_CYCLE_SECONDS
	if _anim:
		if _anim.current_animation != clip:
			_anim.play(clip, 0.25)
			# Start each person at their own point in the cycle so a group
			# leaving together doesn't march in step.
			var length := _anim.current_animation_length
			if length > 0.0:
				_anim.seek(fmod(float(person) * 0.618, 1.0) * length)
		_anim.speed_scale = clampf(_resolved_speed / clip_speed, 0.3, 1.8)
	# One step per half cycle of ground covered by the clip; keep the remainder.
	var stride := clip_speed * cycle_seconds * 0.5
	_step_distance += _resolved_speed * delta
	if _step_distance >= stride:
		_step_distance = minf(_step_distance - stride, stride)
		_footstep()


func _footstep() -> void:
	if not _contact or _player == null:
		return
	if global_position.distance_squared_to(_player.global_position) > STEP_RANGE * STEP_RANGE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_step_ms < 70:
		return
	var sound := "step_" + _surface
	if Audio.has_method("has_sound") and not Audio.has_sound(sound):
		return
	_last_step_ms = now
	Audio.play_sfx(sound, global_position, -17.0, 0.08)


func _add_head_look(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone("head") < 0:
		return
	_look_target = Node3D.new()
	add_child(_look_target)
	var look := LookAtModifier3D.new()
	look.bone_name = "head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.use_angle_limitation = true
	look.symmetry_limitation = true
	look.primary_limit_angle = deg_to_rad(120)
	look.secondary_limit_angle = deg_to_rad(55)
	look.duration = 0.3
	look.influence = 0.75
	skeleton.add_child(look)
	look.target_node = look.get_path_to(_look_target)


func _update_head_look(delta: float) -> void:
	if _look_target == null:
		return
	_look_timer -= delta
	if _look_timer > 0.0:
		return
	_look_timer = 0.12
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var target := global_position + Vector3(0, 1.45, 0) + forward * 3.0
	if _player and is_instance_valid(_player) and global_position.distance_squared_to(_player.global_position) < 25.0:
		target = _player.global_position + Vector3(0, 1.45, 0)
	elif _arrived and _partner_node and is_instance_valid(_partner_node):
		target = _partner_node.global_position + Vector3(0, 1.45, 0)
	elif _look_point != Vector2.INF:
		target = Vector3(_look_point.x, WorldGen.height(_look_point.x, _look_point.y) + 1.3, _look_point.y)
	_look_target.global_position = _look_target.global_position.lerp(target, 1.0 - exp(-7.0 * delta))


func _update_activity(delta: float) -> void:
	_step_distance = 0.0
	if _anim == null:
		return
	_anim.speed_scale = 1.0
	# Work only once actually at the spot; waiting, yielding or stopped mid-route idles.
	var activity := _activity_want if _arrived and _yield_time <= 0.0 else ""
	if activity != _activity_name:
		_activity_name = activity
		_activity_needs_start = true
		_activity_pause = 0.0
	if activity == "" or not _anim.has_animation(activity):
		_play("Idle")
		return
	if _activity_pause > 0.0:
		_activity_pause = maxf(_activity_pause - delta, 0.0)
		_play("Idle")
		return
	if _activity_needs_start:
		_anim.play(activity, 0.2)
		_activity_needs_start = false
		_cue_done = false
		_cue_last = 0.0
	elif not _anim.is_playing():
		_activity_pause = randf_range(0.8, 1.8)
		_activity_needs_start = true
		_play("Idle")
	_anim.speed_scale = 1.0
	_work_cue(activity)


## Tool sound when the work clip reaches its impact point, only near the player.
func _work_cue(activity: String) -> void:
	if not WORK_SOUNDS.has(activity) or _anim.current_animation != activity:
		return
	var length := _anim.current_animation_length
	if length <= 0.0:
		return
	var f := _anim.current_animation_position / length
	if f < _cue_last:
		_cue_done = false
	_cue_last = f
	var cue: Array = WORK_SOUNDS[activity]
	if _cue_done or f < float(cue[1]):
		return
	_cue_done = true
	if _player == null or global_position.distance_squared_to(_player.global_position) > WORK_SOUND_RANGE * WORK_SOUND_RANGE:
		return
	if Audio.has_method("has_sound") and not Audio.has_sound(cue[0]):
		return
	Audio.play_sfx(cue[0], global_position + Vector3(0, 0.6, 0), -9.0, 0.1)


## Clip for the current act at its spot (resolved on think ticks, not per frame).
func _activity_for_person() -> String:
	var job: int = WorldSim.job[person]
	match _act:
		Act.WORK:
			return _first_clip(JOB_CLIPS[job])
		Act.SOCIAL:
			if _partner_node == null:
				return _first_clip(ALONE_CLIPS)
			# Take turns: one talks while the other listens, swapping every few seconds.
			var turn := int(Time.get_ticks_msec() / int(TURN_SECONDS * 1000.0)) % 2 == 0
			return _first_clip(TALK_CLIPS if turn == (person < _partner) else LISTEN_CLIPS)
		Act.SHOP, Act.INN:
			if job == 3:
				return _first_clip(JOB_CLIPS[3])
	return _first_clip(ACT_CLIPS.get(_act, []))


## First clip in `names` the rig has ("" when none), cached per list.
func _first_clip(names: Array) -> String:
	if names.is_empty() or _anim == null:
		return ""
	var key := "|".join(PackedStringArray(names))
	if _clip_cache.has(key):
		return _clip_cache[key]
	var found := ""
	for n: String in names:
		if _anim.has_animation(n):
			found = n
			break
	_clip_cache[key] = found
	return found


func _play(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)
