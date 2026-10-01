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
##  - Contact tier: villagers within CONTACT_ENTER of the player enable their
##    capsule. The closest physics budget uses move_and_slide(); overflow uses a
##    single swept move_and_collide() query, so contact actors still respect the
##    player and world without enabling NPC-on-NPC physics.
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
##  - Purpose and reactions (docs: NpcWorld / UtilityBrain): work, shop, sit, pray, fetch water, chores and
##    play at real smart-object spots (SmartObjects sessions with life clips and props), guards patrol,
##    everyone steps back from a drawn weapon, flees and hides from danger and peeks out later, runs to a
##    guard when they witness a crime, throws water at fires, keeps off crop fields and out of the way of
##    carts and riders, greets the player by how the town regards them and remembers where danger was seen.
##    Evaluation is sliced (NpcWorld.take_decide_budget) and only ever runs for these near bodies.

const Nameplates := preload("res://scripts/core/nameplates.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const NpcSocialGraph := preload("res://scripts/sim/npc_social_graph.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const TownIdentity := preload("res://scripts/world/town_identity.gd")
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
const ALARM_PACE := 2.1
const FIRE_PACE := 1.7
## Armed-player personal space (metres) replaces PERSONAL_SPACE while a weapon is drawn this close.
const ARMED_SPACE := 2.8
## Seconds each speaker holds the floor in a chat.
const TURN_SECONDS := 4.0
## Clip candidates per act, first one the rig has wins (life clips first, UAL / UAL extras as fallback).
const ACT_CLIPS := {
	Act.SHOP: ["Life_Market_Browse", "Idle_Talking", "Interact"],
	Act.INN: ["Life_Tavern_Lean_Bar", "Idle_Talking", "Cheering_Two_Hands"],
	Act.PRAY: ["Life_Pray_Kneel", "Life_Pray_Stand", "G6_pray", "Taichi_Idle", "Meditate", "Fixing_Kneeling"],
	Act.WATER: ["Life_Chore_Well_Crank", "G6_gathering", "Chore_Pick_Up_Box", "Interact", "PickUp_Table"],
	Act.SHELTER: ["Life_Mocap_Cold", "Life_Ambient_Rub_Arms", "Shivering", "Idle_Subtle"],
	Act.FLEE: ["Shivering", "Idle_Hurt"],
	Act.WATCH: ["Life_Ambient_Shade_Eyes", "Idle_Listening", "Idle_Subtle"],
	Act.SLEEP: ["Life_Rest_Sleep_Ground", "Lie_Down_Idle", "Sitting_Idle"],
	Act.HOME: ["Life_Chore_Sweep", "Chore_Sweep", "Sitting_Idle"],
	Act.EAT: ["Life_Eat_Bread_Stand", "Consume_Item", "Sitting_Idle"],
	Act.SIT: ["Sitting_Idle", "Idle_Subtle"],
	Act.PLAY: ["Life_Kid_Run_Play", "Idle_Subtle"],
	Act.HIDE: ["Life_Mocap_Cold", "Shivering", "Idle_Subtle"],
	Act.PROTEST: ["Life_Social_Argue_A", "Life_Social_Shake_Head", "Idle_Hurt", "Idle_Talking"],
	Act.ALARM: ["Life_Social_Point_Directions", "Life_Mocap_Directions", "Idle_Talking"],
	Act.FIREFIGHT: ["Life_Carry_Put_Down", "Life_Carry_Pick_Up", "Chore_Pick_Up_Box", "Interact"],
	Act.CHORE: ["Life_Chore_Sweep", "Chore_Sweep", "Interact"],
	Act.PATROL: ["Life_Guard_Look_Out", "Idle_Shield", "Idle_Subtle"],
	Act.TRAIN: ["Life_Guard_Attention", "Idle_Shield", "Idle_Subtle"],
	Act.MOURN: ["Life_Social_Mourn_Stand", "Life_Mocap_Sad", "Life_Pray_Stand", "Idle_Subtle"],
	Act.FESTIVE: ["Dance", "Life_Tavern_Cheer", "Life_Social_Laugh", "Cheering_Two_Hands"],
	Act.QUEUE: ["Life_Ambient_Shift_Weight", "Life_Ambient_Look_Around", "Life_Ambient_Wipe_Brow", "Idle_Subtle"],
}
## Clips of the same act varied per person: the devout kneel at a funeral, some dance and some cheer.
const MOURN_KNEEL := ["Life_Social_Mourn_Kneel", "Life_Pray_Kneel"]
const FESTIVE_DANCE := ["Dance", "Life_Tavern_Cheer", "Life_Social_Laugh", "Life_Mocap_Happy"]
const POOR_MEAL := ["Life_Mocap_Eat_Soup", "Life_Eat_Bread_Stand", "Consume_Item"]
const WAKE_CLIPS := ["Life_Ambient_Stretch_Morning", "Life_Ambient_Yawn", "Life_Mocap_Stretch_Yawn", "Idle_Subtle"]
const TALK_CLIPS := ["Life_Talk_Casual", "Life_Talk_Explain", "Life_Talk_Gossip", "Life_Talk_Emphatic", "Idle_Talking"]
const LISTEN_CLIPS := ["Life_Talk_Listen_Nod", "Life_Talk_Listen_Hips", "Idle_Listening", "Head_Nod", "Idle_Talking"]
const ALONE_CLIPS := ["Life_Ambient_Shift_Weight", "Idle_Subtle"]
const JOB_CLIPS := [["Life_Farm_Hoe", "Farm_Harvest"], ["Life_Smith_Hammer", "Fixing_Kneeling"], ["Life_Market_Call_Out", "Idle_Talking"],
	["Life_Guard_Lean_Spear", "Idle_Shield"], ["Life_Carp_Saw", "Interact"], ["Life_Wood_Chop", "TreeChopping"]]
## One-shot greeting clips by how the town regards the player.
const GREET_CLIPS := {"warm": ["Life_Social_Wave_Greet", "Life_Social_Nod"], "neutral": ["Life_Social_Nod", "Head_Nod"],
	"cold": ["Life_Social_Shake_Head", "Idle_Subtle"]}
## Stuck check window and the progress expected in it.
const STUCK_WINDOW := 1.2
const STUCK_PROGRESS := 0.3
## Smart object sessions advance at this rate (their state machine allocates a result per update).
const SESSION_HZ := 10.0
## Real seconds an act is held after arriving when it is not the default MIN_PERFORM.
const PERFORM_FOR := {Act.PROTEST: 3.0, Act.PATROL: 3.5, Act.FIREFIGHT: 5.0, Act.ALARM: 7.0, Act.WATCH: 6.0,
	Act.MOURN: 18.0, Act.FESTIVE: 20.0, Act.QUEUE: 14.0, Act.TRAIN: 16.0}
## Real-time gaps between a villager's grumbles about the state of the town, and the wake-up routine's cooldown.
const GRUMBLE_GAP_MS := 75000
const PROTEST_COOLDOWN_MS := 25000
const GREET_RANGE := 3.4
const BUBBLE_SECONDS := 3.2
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
var _skeleton: Skeleton3D
var _child := false
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

# Smart object use (SmartObjects.Session driven at SESSION_HZ; see _so_*).
var _props: LifeProps.Holder
var _so: SmartObjects.Session
var _so_acc := 0.0
var _so_clip := ""
var _so_clip_done := false
var _so_last_pos := 0.0
var _so_phase := -1
var _so_face := NAN
var _so_move := Vector3.INF
var _so_snap := false
var _so_snap_to := Vector3.ZERO
var _so_ended := false
var _so_leaving := false

# Awareness and reactions (times are Time.get_ticks_msec()).
var _hide_until := 0
var _scared_at := Vector2.INF
var _protest_cd := 0
var _greet_cd := 0
var _crime_until := 0
var _crime_pos := Vector2.INF
var _crime_heard := false
var _peek_until := 0
var _oneshot := ""
var _oneshot_until := 0
var _oneshot_started := false
var _oneshot_face_player := false
var _bubble: Label3D
var _bubble_until := 0
var _fire_slot := -1
var _throw_t := 0.0
var _gossip_turn := -1
var _prev_act := -1
var _regard := 0.0
var _regard_ms := 0
var _avoid_extra := Vector2.ZERO
var _grumble_cd := 0
var _mood: Dictionary = {}
var _monster_hide_cd := 0

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
var physics_active := false
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
var _water_token := ""
var _water_slot := -1
var _water_working := false
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
	_child = NpcWorld.is_child(person)
	var model := Assets.character(_file, 1.7 * (0.78 if _child else 1.0), _keep)
	# Colour language: this town's guard uniform / clothing palette (culture + archetype) as a tint of the shared materials.
	var tt: Array = TownIdentity.person_tint(WorldSim.home[person], person, WorldSim.job[person] == 3)
	TownIdentity.tint_model(model, tt[0], float(tt[1]))
	add_child(model)
	_anim = Assets.animation_player(model)
	LifeLibrary.install(_anim)      # idempotent: the life clips are added to the shared rig library once
	for n in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n as GeometryInstance3D)
	_add_head_look(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_props = LifeProps.Holder.new(_skeleton)
	_attach_components(model)
	_graph = StreetGraph.for_person(person) as StreetGraph
	NpcWorld.ensure_spots(WorldSim.home[person], get_parent())
	# Promotion: start where the simulation had this person, moved out of any
	# footprint it cut through, facing the way they were heading.
	var p: Vector2 = WorldSim.pos[person]
	if _graph:
		p = _graph.push_out(p, BODY_RADIUS + 0.12)
	position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	WorldSim.set_external_position_owner(person, get_instance_id(), true, sim_position(), true)
	var heading: Vector2 = WorldSim.target[person] - p
	_heading = atan2(heading.x, heading.y) if heading.length() > 0.1 else float(person % 628) / 100.0
	rotation.y = _heading
	# Stable per-person variation: pace, think phase, gait phase.
	var h := hash(person * 2654435761 + 7)
	_walk_speed = WALK_SPEED * (0.9 + float(h % 200) / 1000.0) * (1.12 if _child else 1.0)
	_think = float((h / 200) % 1000) / 1000.0 * THINK_INTERVAL
	_stuck_from = p
	_tag = Label3D.new()
	Nameplates.style(_tag, Color(1, 0.95, 0.85), 26, 14.0)
	_tag.remove_from_group("nameplate")      # driven by show_tag / Nameplates.suppressed below
	_tag.position.y = 1.95
	add_child(_tag)
	_tag.text = WorldSim.describe(person)
	_brain = _make_brain()
	UtilityBrain.register_body(person, self)
	# First decision now, later ones on this person's own phase.
	_decide = 0.0
	_think_tick()
	_decide = float((h / 7) % 1000) / 1000.0 * DECIDE_INTERVAL


func _exit_tree() -> void:
	NpcWorld.queue_leave(WorldSim.home[person], person)
	_interrupt_activity()
	_so_release()
	if _bubble != null and _bubble.visible:
		NpcWorld.bubbles_shown = maxi(NpcWorld.bubbles_shown - 1, 0)
	_save_needs()
	WorldSim.set_external_position_owner(person, get_instance_id(), false, sim_position())
	UtilityBrain.clear_sight_for(self)
	UtilityBrain.unregister_body(person, get_instance_id())


## Components other systems attach to an embodied villager's model go here
## (e.g. a procedural rig: `model.add_child(ProceduralRig.new())`). Called once,
## right after the model, AnimationPlayer and head look exist.
func _attach_components(_model: Node3D) -> void:
	# NPC foot IK via ProceduralRig was tried here and measured at -14..-22 fps on HIGH in
	# the village bench (rig modifiers keep every resident's skeleton updating each frame);
	# see docs/anim/patches/P6_npc_foot_ik_cost.md before re-enabling.
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
	var stored := WorldSim.person_needs(person)
	if stored.is_empty() or not b.import_needs(stored.get("values", PackedFloat32Array()), float(stored.get("hours", -1.0))):
		b.seed_needs(DailyRhythm.local_time(person), WorldSim.day)
	else:
		# Reconcile on promotion with the brain's constant-time catch-up (Codex).
		b.catch_up(WorldSim.day * 24.0 + WorldSim.time_of_day)
	return b


## Resolved position for WorldSim (PopulationLOD writes it back).
func sim_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## SaveManager can restore while this resident body is still alive. Re-import the
## loaded row immediately so a following time-skip resync cannot write old needs
## over the save that was just selected.
func restore_needs_from_world() -> void:
	if _brain == null:
		return
	WorldSim.set_external_position_owner(person, get_instance_id(), true, Vector2.INF, true)
	_interrupt_activity()
	var stored := WorldSim.person_needs(person)
	if stored.is_empty() or not _brain.import_needs(stored.get("values", PackedFloat32Array()), float(stored.get("hours", -1.0))):
		_brain.seed_needs(DailyRhythm.local_time(person), WorldSim.day)
	else:
		_brain.catch_up(WorldSim.day * 24.0 + WorldSim.time_of_day)
	_act = -1
	_brain.act = -1
	_decide = 0.0
	_save_needs()


## WorldSim moved everyone (time skip / load): take its position as the new
## truth, settle outside footprints and plan again.
func resync() -> void:
	# A time skip changes this resident's schedule target, not its live resolved
	# transform. WorldSim.pos is only the last 4 Hz LOD write-back while owned.
	UtilityBrain.clear_sound_events()
	var p: Vector2 = sim_position() if WorldSim.owns_external_position(person, get_instance_id()) else WorldSim.pos[person]
	_interrupt_activity()
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
	# A time skip invalidates transient activity/perception, but not this resident's
	# durable needs. Advance through the existing bounded brain tick, then resume.
	UtilityBrain.chat_leave(person)
	_so_release()
	_hide_until = 0
	_crime_until = 0
	_peek_until = 0
	_oneshot_until = 0
	_set_indoors(false)
	_act = -1
	_brain.act = -1
	_brain.catch_up(WorldSim.day * 24.0 + WorldSim.time_of_day)
	_save_needs()
	_brain.clear_threat_memory()
	UtilityBrain.clear_sight_for(self)
	_decide = 0.0


func _physics_process(delta: float) -> void:
	if NpcWorld.profile:
		var t0 := Time.get_ticks_usec()
		_tick_body(delta)
		NpcWorld.prof_usec += Time.get_ticks_usec() - t0
		NpcWorld.prof_calls += 1
	else:
		_tick_body(delta)


func _tick_body(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think += THINK_INTERVAL
		_think_tick()
	if _indoors:
		# Inside a building: nothing to move, draw or animate until the next choice.
		_perform_time += delta
		return
	if _arrived and _yield_time <= 0.0:
		if _act != Act.WATER or _water_working:
			_perform_time += delta
		if _plan_indoors:
			_set_indoors(true)
			return
	var here := Vector2(global_position.x, global_position.z)
	if _contact:
		_check_yield(here, delta)
	var driving := _so != null and _so_frame(delta)
	var planar := Vector2.ZERO if driving else _steer(here, delta)
	if driving:
		velocity = Vector3.ZERO
		global_position = _so_step(delta)
	elif _contact and physics_active:
		velocity = Vector3(planar.x, 0.0, planar.y)
		move_and_slide()
	elif _contact:
		# Keep the expensive multi-slide path capped by PopulationLOD, but never
		# let an embodied overflow actor cross the player or a solid world shape.
		# The mask is world/player only (NPCs are on layer 2), so this remains one
		# bounded sweep without adding pairwise crowd collision.
		if planar != Vector2.ZERO:
			move_and_collide(Vector3(planar.x, 0.0, planar.y) * delta)
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
	_tag.visible = show_tag and not Nameplates.suppressed


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
	# Sliced: a limited number of utility decisions per physics frame across all villagers; a refused
	# one stays due and is taken on the next think tick.
	if _decide <= 0.0 and NpcWorld.take_decide_budget():
		_decide = maxf(_decide, -DECIDE_INTERVAL) + DECIDE_INTERVAL
		_decide_act(here)
	var now_ms := Time.get_ticks_msec()
	_bubble_tick(now_ms)
	if _indoors:
		return
	_update_facing(here)
	_activity_want = _activity_for_person()
	if _needs_route and _yield_time <= 0.0 and _wait <= 0.0 and StreetGraph.take_route_budget():
		_plan_route(here)
	var travelling := _path_i < _path.size()
	_avoid = _graph.repulse(here, 1.0) if _graph and travelling else Vector2.ZERO
	if travelling:
		_avoid += _extra_steering(here)
	_separation = _neighbour_push(here)
	_maybe_greet(here, player_distance, now_ms)
	_reaction_tick(here, now_ms)
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
func _save_needs() -> void:
	if _brain == null or person < 0 or not WorldSim.owns_external_position(person, get_instance_id()):
		return
	WorldSim.set_person_needs(person, get_instance_id(), _brain.export_needs(), WorldSim.day * 24.0 + WorldSim.time_of_day)


## One utility decision (every DECIDE_INTERVAL): sense, update needs, score,
## and turn a new act into a goal. Same act: only dynamic goals are refreshed.
func _decide_act(here: Vector2) -> void:
	var tree := get_tree()
	NpcWorld.refresh(tree)
	var now := Time.get_ticks_msec()
	var sensed := {"visible": PackedVector2Array()}
	if not _indoors:
		sensed = _brain.sense_threats(self, tree, WORLD_LAYER)
	var visible_threats: PackedVector2Array = sensed["visible"]
	var remembered_threats: PackedVector2Array = sensed.get("remembered", visible_threats)
	var danger := _brain.remembered_danger(here, remembered_threats, int(sensed.get("observed_ms", -1)))
	var danger_v: float = danger[0]
	var danger_p: Vector2 = danger[1]
	var own_sight := danger_v
	var guard := WorldSim.job[person] == 3
	# Fires and screams are dangers too (heard, not seen): they carry the position to run from.
	var fd := NpcWorld.fire_danger(here)
	if fd > danger_v:
		danger_v = fd
		danger_p = NpcWorld.incident_pos(NpcWorld.nearest(NpcWorld.Kind.FIRE, here, NpcWorld.FIRE_DANGER_FAR))
	var scream := NpcWorld.alarm_at(here, NpcWorld.Kind.SCREAM) * 0.9
	if scream > danger_v and not guard:
		danger_v = scream
		danger_p = NpcWorld.incident_pos(NpcWorld.nearest(NpcWorld.Kind.SCREAM, here, 40.0))
	if danger_v > 0.4 and danger_p != Vector2.INF:
		_scared_at = danger_p
		_brain.remember_danger(danger_p)
	var player_p := Vector2.INF
	if _player:
		player_p = Vector2(_player.global_position.x, _player.global_position.z)
	# Sight-based fight interest still uses only hostile samples this villager
	# actually saw. Movement noise adds a separate, anonymous look cue outdoors.
	var sight := UtilityBrain.spectacle_at(here, player_p, visible_threats)
	var heard := UtilityBrain.heard_player_at(here, _player, tree, _graph) if not _indoors else [0.0, Vector2.INF]
	if not _indoors:
		var sound_event := UtilityBrain.audible_event_at(here, tree, _graph)
		if float(sound_event[0]) > float(heard[0]):
			heard = sound_event
	if float(heard[0]) > 0.0:
		_brain.remember_heard_sound(heard[1], float(heard[0]))
	var heard_memory := _brain.heard_memory()
	var interest: Array = sight if float(sight[0]) >= float(heard_memory[0]) else heard_memory
	var performing := _indoors or (_arrived and _yield_time <= 0.0
		and (_act != Act.WATER or _water_is_performing(here)))
	_brain.tick(WorldSim.day * 24.0 + WorldSim.time_of_day, _act if performing else -1)
	_save_needs()
	_state = DailyRhythm.state(person)
	var sid: int = WorldSim.home[person]
	var company := UtilityBrain.chat_waiting(sid, person) or UtilityBrain.chat_partner(person) >= 0
	_gather_inputs(here, now, guard)
	var ctx := _brain.context(DailyRhythm.local_time(person), _state, UtilityBrain.is_raining(tree),
		danger_v, sight[0], company, float(WorldSim.money[person]) / 60.0, WorldSim.day)
	var committed := not performing or _perform_time < float(PERFORM_FOR.get(_act, MIN_PERFORM))
	var act := _brain.decide(ctx, committed)
	if act != _act:
		# UtilityBrain can override the coarse work/market schedule. Release its
		# reservation before planning the new act; WORK/SHOP will reacquire as needed.
		WorldSim.release_activity_target(person)
		if _act == Act.SOCIAL:
			UtilityBrain.chat_leave(person)
		if _act == Act.QUEUE:
			NpcWorld.queue_leave(sid, person)
		_prev_act = _act
		_act = act
		# Someone who bolts from what they saw themselves shouts it to the street.
		if act == Act.FLEE and own_sight > 0.5 and danger_p != Vector2.INF:
			NpcWorld.report(NpcWorld.Kind.SCREAM, danger_p, 28.0, 8.0, 0.9)
		_apply_plan(here, danger_p, _look_for(act, danger_p, sight[1], player_p, here))
		return
	if _so_ended:
		# The smart object use ran its course: pick the next spot for the same purpose.
		_so_ended = false
		_apply_plan(here, danger_p, _look_for(act, danger_p, sight[1], player_p, here))
		return
	_record_completed_social()
	match act:
		Act.FLEE:
			# Still in danger at the end of the run: keep going from here.
			if _arrived and not _plan_indoors:
				_apply_plan(here, danger_p, sight[1])
		Act.WATCH:
			if interest[1] != Vector2.INF and (interest[1] as Vector2).distance_to(_look_point) > 3.0:
				_apply_plan(here, danger_p, interest[1])
		Act.SOCIAL:
			if _partner < 0:
				# Waiting residents retry at the existing staggered decision cadence,
				# allowing a bounded candidate group to form before pairing by familiarity.
				var social_plan := _brain.plan_goal(Act.SOCIAL, here, _graph, danger_p, interest[1])
				_partner = int(social_plan["partner"])
				var social_goal: Vector2 = social_plan["goal"]
				if _partner >= 0 and social_goal.distance_to(_goal) > 0.1:
					_goal = social_goal
					_needs_route = true
					_arrived = false
		Act.WATER:
			# Capacity conflicts leave the resident where they are. Retry only on
			# this already staggered decision tick, never every physics frame.
			if _water_token.is_empty():
				_apply_plan(here, danger_p, interest[1])
		Act.PATROL:
			if _arrived and _perform_time > float(PERFORM_FOR[Act.PATROL]):
				_apply_plan(here, danger_p, Vector2.INF)
		Act.ALARM:
			if _arrived and _perform_time > float(PERFORM_FOR[Act.ALARM]):
				# Reported (or arrived at the scene): the excitement is over.
				if not guard:
					_say(NpcWorld.line("alarm_guard", person, now / 1000))
				_crime_until = 0
		Act.FIREFIGHT:
			var slot := NpcWorld.nearest(NpcWorld.Kind.FIRE, here, NpcWorld.FIRE_REACH)
			if slot >= 0 and slot != _fire_slot:
				_fire_slot = slot
				_apply_plan(here, danger_p, NpcWorld.incident_pos(slot))


## Persist one NPC-to-NPC tie only after the current pair has spent time together
## at its shared social activity. Lower person ID owns the single write.
func _record_completed_social() -> void:
	if _act != Act.SOCIAL or not _arrived or _yield_time > 0.0 or _perform_time < MIN_PERFORM:
		return
	if _partner < 0 or person > _partner or UtilityBrain.chat_partner(person) != _partner:
		return
	var partner_body := UtilityBrain.body_of(_partner)
	if partner_body == null or not is_instance_valid(partner_body):
		return
	var here := Vector2(global_position.x, global_position.z)
	var other := Vector2(partner_body.global_position.x, partner_body.global_position.z)
	if here.distance_squared_to(other) > 9.0:
		return
	var life := get_node_or_null("/root/Life")
	var graph: Variant = life.get("npc_social_graph") if life else null
	if graph == null or not graph.has_method("record_conversation"):
		return
	var a := NpcSocialGraph.worldsim_person(WorldSim.SEED, person)
	var b := NpcSocialGraph.worldsim_person(WorldSim.SEED, _partner)
	var day := float(WorldSim.day) + WorldSim.time_of_day / 24.0
	graph.call("record_conversation", a, b, day)


## Everything the body knows that the brain scores: fire, a drawn weapon, a crime it saw or heard, being
## in hiding, guard duty turns and whether a seat / play patch / chore is at hand.
func _gather_inputs(here: Vector2, now: int, guard: bool) -> void:
	var inp := _brain.inp
	inp["child"] = 1.0 if _child else 0.0
	inp["fire"] = NpcWorld.fire_interest(here)
	inp["armed"] = NpcWorld.armed_pressure(here) if now >= _protest_cd else 0.0
	inp["crime"] = _crime_input(here, now)
	inp["hide"] = 1.0 if (now < _hide_until and not guard) else 0.0
	var hour := DailyRhythm.local_time(person)
	var sid: int = WorldSim.home[person]
	_mood = TownMood.mood_of(sid)
	var festival: bool = String(_mood.get("festival", "")) != ""
	var edgy: bool = float(_mood.get("war", 0.0)) >= 0.5 or bool(_mood.get("curfew", false)) or float(_mood.get("monster", 0.0)) >= 0.5
	inp["patrol_turn"] = 1.0 if guard and ((((now / 45000 + person) % 3) != 0) if edgy else (((now / 45000 + person) & 1) == 0)) else 0.0
	_gather_town_inputs(here, now, guard, hour, festival)
	inp["seat"] = 1.0 if (_brain.breath < 0.72 and not _indoors and hour >= 7.0 and hour < 21.0 and _brain.has_spot(Act.SIT, here)) else 0.0
	inp["play_spot"] = 1.0 if (_child and _brain.has_spot(Act.PLAY, here)) else 0.0
	var chore := 0.0
	if not _child and ((hour >= 6.5 and hour < 9.0) or (hour >= 16.0 and hour < 20.5)):
		var s: Dictionary = WorldGen.settlements[WorldSim.home[person]]
		if _brain.has_spot(Act.CHORE, WorldSim._spot(s, 0, person), 30.0):
			chore = 1.0
	inp["chore_spot"] = chore


## The town's circumstances as inputs (town_mood.gd): rest days and festivals, curfew, mourning, shortages, war
## and monsters, plus whether a drill, a bread line or a funeral is at hand for this person.
func _gather_town_inputs(here: Vector2, now: int, guard: bool, hour: float, festival: bool) -> void:
	var inp := _brain.inp
	var sid: int = WorldSim.home[person]
	var rest_day: bool = bool(_mood.get("rest_day", false))
	var scarcity := float(_mood.get("scarcity", 0.0))
	var war := float(_mood.get("war", 0.0))
	var monster := float(_mood.get("monster", 0.0))
	inp["holiday"] = 1.0 if (rest_day or festival) else 0.0
	inp["festive"] = 1.0 if (festival and hour >= 9.5 and hour < 23.5 and not guard) else 0.0
	inp["curfew"] = 1.0 if bool(_mood.get("curfew", false)) else 0.0
	inp["mourning_town"] = float(_mood.get("mourning", 0.0))
	inp["scarce"] = scarcity
	_brain.meal_q = TownMood.meal_quality(scarcity)
	# Drill: scheduled, or the militia in wartime (a spot must exist, so nobody drills at an empty yard).
	var train := 0.0
	if not _child and (_state == DailyRhythm.State.TRAIN or (war >= 0.5 and (guard or WorldSim.job[person] == 4 or WorldSim.job[person] == 5) and hour >= 14.0 and hour < 17.0)):
		train = 1.0 if _brain.has_spot(Act.TRAIN, here, 140.0) else 0.0
	inp["train"] = train
	# Bread line: scarcity at the busy hours, for anyone who is not on duty.
	var queue := 0.0
	var q_level := TownMood.queue_level(scarcity, hour)
	if q_level > 0.3 and not guard and not _child and _brain.food < 0.85 and not NpcWorld.bread_stall(sid).is_empty():
		if _act == Act.QUEUE or NpcWorld.queue_length(sid) < NpcWorld.QUEUE_MAX:
			queue = 1.0
	inp["queue"] = queue
	# A funeral nearby (reported by NpcWorld.report(Kind.FUNERAL, ...)): the town goes to it, the watch does not.
	var mourn := 0.0
	var fslot := NpcWorld.nearest(NpcWorld.Kind.FUNERAL, here, NpcWorld.FUNERAL_REACH)
	if fslot >= 0 and not guard:
		mourn = 0.2 + 0.8 * (1.0 - clampf(here.distance_to(NpcWorld.incident_pos(fslot)) / NpcWorld.FUNERAL_REACH, 0.0, 1.0))
	inp["mourn"] = mourn
	# A raid at the gates: those who are not the watch go indoors and keep away from the walls for a while.
	if monster >= 0.8 and not guard and now >= _monster_hide_cd and not _indoors:
		_monster_hide_cd = now + 60000
		_hide_until = now + 22000 + (person % 5) * 1000
		_scared_at = WorldGen.settlements[sid]["pos"] + Vector2(cos(float(person)), sin(float(person))) * float(WorldGen.settlements[sid]["radius"]) * 0.9


func _crime_input(here: Vector2, now: int) -> float:
	if now < _crime_until:
		return 0.55 if _crime_heard else 1.0
	return NpcWorld.alarm_at(here, NpcWorld.Kind.CRIME) * 0.6


## The point an act is about (what to watch, who drew a weapon, the crime, the fire, what scared us).
func _look_for(act: int, danger_p: Vector2, sight_p: Vector2, player_p: Vector2, here: Vector2) -> Vector2:
	match act:
		Act.WATCH:
			return sight_p
		Act.PROTEST:
			return player_p
		Act.HIDE:
			return _scared_at
		Act.ALARM:
			if _crime_pos != Vector2.INF and Time.get_ticks_msec() < _crime_until:
				return _crime_pos
			var slot := NpcWorld.nearest(NpcWorld.Kind.CRIME, here, NpcWorld.CRIME_HEARING)
			return NpcWorld.incident_pos(slot) if slot >= 0 else Vector2.INF
		Act.FIREFIGHT:
			_fire_slot = NpcWorld.nearest(NpcWorld.Kind.FIRE, here, NpcWorld.FIRE_REACH)
			return NpcWorld.incident_pos(_fire_slot) if _fire_slot >= 0 else Vector2.INF
	return sight_p


func _apply_plan(here: Vector2, hazard: Vector2, look: Vector2) -> void:
	var plan := _brain.plan_goal(_act, here, _graph, hazard, look)
	var goal: Vector2 = plan["goal"]
	var now := Time.get_ticks_msec()
	_plan_indoors = plan["indoors"]
	_face_pref = plan["face"]
	_look_point = plan["look"]
	_partner = plan["partner"]
	_pace = _pace_for(_act)
	_perform_time = 0.0
	_interrupt_activity()
	if _act == Act.WATER:
		var water_lease := _reserve_water_slot(plan)
		if water_lease.is_empty():
			goal = here
			_plan_indoors = false
			_face_pref = Vector2.INF
		else:
			goal = water_lease["goal"]
			_face_pref = (WorldGen.settlements[WorldSim.home[person]]["pos"] as Vector2) - goal
	# Leave the previous smart object (gracefully, with its exit clip, unless running for it).
	var spot: Array = plan["spot"]
	var spot_claim_failed := false
	_so_leave(not spot.is_empty() or _act == Act.FLEE or _act == Act.ALARM or _act == Act.HIDE or _act == Act.SHELTER or _act == Act.PROTEST)
	if not spot.is_empty():
		if not _so_begin(spot):
			# Another resident may claim a candidate after planning but before this
			# session starts. Do not walk to an unowned workstation; retry next think tick.
			spot = []
			spot_claim_failed = true
			goal = here
			_plan_indoors = false
			_face_pref = Vector2.INF
			_so_ended = true
	if WorldSim.job[person] != 0 and spot.is_empty() and not spot_claim_failed and not _plan_indoors and _act != Act.FLEE:
		goal = NpcWorld.out_of_fields(WorldSim.home[person], goal)
	_act_started(here, hazard, look, now)
	var was_inside := _indoors
	_set_indoors(false)
	if was_inside and _prev_act == Act.HIDE and _act != Act.HIDE:
		# Out of hiding: stop at the door and look where the scare was before carrying on.
		_peek_until = now + 3400
		_wait = 3.4
		_begin_oneshot(["Life_Ambient_Look_Around", "Idle_Subtle"], 3.2)
		if _scared_at != Vector2.INF:
			_say(NpcWorld.line("hide", person, now / 1000), 2.6)
	elif was_inside and (_prev_act == Act.SLEEP or _prev_act == Act.HOME or _prev_act == Act.EAT) and _act != _prev_act \
			and not _plan_indoors and DailyRhythm.local_time(person) >= 5.0 and DailyRhythm.local_time(person) < 10.0:
		# Wake: the morning stretch at the door before the day begins.
		_begin_oneshot(WAKE_CLIPS, 2.2)
		_wait = maxf(_wait, 2.2)
		if person % 4 == 0:
			_say(NpcWorld.line("wake", person, now / 60000), 2.2)
	if was_inside and _plan_indoors and goal.distance_to(sim_position()) < 1.0:
		_set_indoors(true)    # e.g. eat -> sleep: stay in
		return
	var water_slot_needs_route := (_act == Act.WATER and not _water_token.is_empty()
		and sim_position().distance_to(goal) > 0.55)
	if _goal == Vector2.INF or goal.distance_to(_goal) > 1.0 or not _arrived or water_slot_needs_route:
		_goal = goal
		_needs_route = true
		_arrived = false


func _pace_for(act: int) -> float:
	match act:
		Act.FLEE: return FLEE_PACE
		Act.SHELTER: return SHELTER_PACE
		Act.ALARM: return ALARM_PACE
		Act.FIREFIGHT: return FIRE_PACE
		Act.HIDE: return 1.9
		Act.PROTEST: return 0.85
		Act.QUEUE: return 1.1
		Act.MOURN: return 0.85
	return 1.0


## Bookkeeping and barks when a new act starts.
func _act_started(here: Vector2, hazard: Vector2, look: Vector2, now: int) -> void:
	var sec := now / 1000
	var guard := WorldSim.job[person] == 3
	match _act:
		Act.FLEE:
			_hide_until = now + 16000 + (person % 6) * 1000
			_say(NpcWorld.line("flee", person, sec), 2.4)
			if hazard != Vector2.INF:
				_brain.remember_danger(hazard)
		Act.PROTEST:
			_protest_cd = now + PROTEST_COOLDOWN_MS
			_say(NpcWorld.line("armed_guard" if guard else "armed", person, sec))
		Act.ALARM:
			_say(NpcWorld.line("guard_respond" if guard else "crime", person, sec))
		Act.FIREFIGHT:
			_say(NpcWorld.line("fire", person, sec))
			if _props != null:
				_props.show_props([{"id": "bucket", "hand": "r"}])
		Act.SHELTER:
			if person % 4 == 0:
				_say(NpcWorld.line("rain", person, sec), 2.6)
		Act.QUEUE:
			if person % 2 == 0:
				_say(NpcWorld.line("queue" if person % 4 == 0 else "shortage", person, sec), 3.0)
		Act.FESTIVE:
			if person % 3 == 0:
				_say(NpcWorld.line("festival_talk", person, sec), 2.8)
		Act.MOURN:
			if person % 3 == 0:
				_say(NpcWorld.line("mourning", person, sec), 3.0)
		Act.EAT:
			if float(_mood.get("scarcity", 0.0)) >= 0.4 and person % 3 == 0:
				_say(NpcWorld.line("meal_poor", person, sec), 2.8)
		Act.WATCH:
			if person % 3 == 0 and look != Vector2.INF:
				_say(NpcWorld.line("festival" if NpcWorld.nearest(NpcWorld.Kind.FESTIVAL, here, 60.0) >= 0 else "fight", person, sec), 2.6)
	if _act != Act.FIREFIGHT and _so == null and _props != null:
		_props.clear()


## Inside a building: hidden, no capsule, not a talk target.
func _set_indoors(on: bool) -> void:
	if on == _indoors:
		return
	if on:
		UtilityBrain.clear_sight_for(self)
	_indoors = on
	if on:
		_so_release()
	if on and _brain != null:
		_brain.clear_threat_memory()
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
	var now := Time.get_ticks_msec()
	if now < _peek_until and _scared_at != Vector2.INF:
		_face_now = _scared_at - here
		return
	if now < _oneshot_until and _player != null and _oneshot_face_player:
		_face_now = Vector2(_player.global_position.x, _player.global_position.z) - here
		return
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
	var yield_radius := YIELD_RADIUS * (2.2 if NpcWorld.player_mounted() else 1.0)
	var space := ARMED_SPACE if NpcWorld.armed_pressure(here) > 0.2 else PERSONAL_SPACE
	if d > maxf(yield_radius, space) or d < 0.001:
		return
	# Personal space: ease away from the player while close (wider while a weapon is drawn).
	if d < space:
		_player_push = rel / d * (space - d) / space
	if d > yield_radius:
		return
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
	if not _water_token.is_empty():
		var life := get_node_or_null("/root/Life")
		var activities: Variant = life.get("npc_activity_runtime") if life else null
		if activities != null and activities.has_method("release"):
			activities.call("release", _water_token)
	_water_token = ""
	_water_slot = -1
	_water_working = false
	_interrupt_animation()


## Clear only presentation state. Walking toward a reserved activity must not
## release its capacity lease; real interruptions use _interrupt_activity().
func _interrupt_animation() -> void:
	_activity_name = ""
	_activity_needs_start = true
	_activity_pause = 0.0


## Reserve one generated well approach plus this resident's actor channel.
## The exact row/settlement identifiers are scoped to this deterministic world.
func _reserve_water_slot(plan: Dictionary) -> Dictionary:
	var slots: PackedVector2Array = plan.get("well_slots", PackedVector2Array())
	if slots.is_empty():
		return {}
	var source_ref := String(plan.get("water_source", ""))
	var life := get_node_or_null("/root/Life")
	var activities: Variant = life.get("npc_activity_runtime") if life else null
	if activities == null or not activities.has_method("reserve_water_source"):
		return {}
	var sid: int = WorldSim.home[person]
	var now_s := Time.get_ticks_msec() / 1000.0
	for offset in mini(slots.size(), 2):
		var slot := (person + offset) % mini(slots.size(), 2)
		var started: Dictionary = activities.call("reserve_water_source", person, sid, source_ref, slot, now_s)
		if bool(started.get("ok", false)):
			_water_token = String(started.get("token", ""))
			_water_slot = slot
			return {"goal": slots[slot]}
	return {}


## Water is restored only at a cleared approach while this token still owns a
## working lease. The existing animation is a presentation cue, never authority.
func _water_is_performing(here: Vector2) -> bool:
	if _water_token.is_empty():
		_water_working = false
		return false
	var life := get_node_or_null("/root/Life")
	var activities: Variant = life.get("npc_activity_runtime") if life else null
	if activities == null or not activities.has_method("phase"):
		_water_working = false
		return false
	var now_s := Time.get_ticks_msec() / 1000.0
	var phase := String(activities.call("phase", _water_token, now_s))
	if phase.is_empty():
		_water_token = ""
		_water_slot = -1
		_water_working = false
		return false
	var facing := Vector2(sin(_heading), cos(_heading))
	var face_dir := _face_pref.normalized() if _face_pref != Vector2.INF else Vector2.ZERO
	var aligned := face_dir == Vector2.ZERO or facing.dot(face_dir) >= 0.9
	var at_slot := (_arrived and _yield_time <= 0.0 and here.distance_to(_goal) <= 0.65
		and _resolved_speed <= 0.18 and aligned)
	if phase == "begun" and at_slot:
		_water_working = bool(activities.call("start_work", _water_token, now_s))
		phase = "working" if _water_working else ""
	else:
		_water_working = phase == "working" and at_slot
	return _water_working


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
	if _so != null and _so_phase >= SmartObjects.Session.ENTER and _so_phase <= SmartObjects.Session.EXIT:
		_walking = false      # a smart object session owns the clip (enter / loop / between / exit)
		return
	if not _walking and _resolved_speed > 0.14:
		_walking = true
	elif _walking and _resolved_speed < 0.07 and _move_speed < 0.1:
		_walking = false
	if not _walking:
		_update_activity(delta)
		return
	_interrupt_activity()
	_oneshot_started = false
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
	if _oneshot != "" and Time.get_ticks_msec() < _oneshot_until:
		if not _oneshot_started:
			_oneshot_started = true
			_anim.play(_oneshot, 0.25)
		return
	if _oneshot_started:
		_oneshot_started = false
		_oneshot = ""
		_activity_needs_start = true
	_anim.speed_scale = _idle_rate() if _anim.current_animation == "Idle" else 1.0
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
	# Idle breathes at a per-person rate so a crowd never sways in unison (FEEL_AUDIT F9).
	_anim.speed_scale = _idle_rate() if _anim.current_animation == "Idle" else 1.0
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
	if Audio.has_method("has_sound") and not Audio.has_sound(cue[0]):
		return
	var sound_level := 0.38 if activity == "TreeChopping" else 0.28
	var sound_radius := 13.0 if activity == "TreeChopping" else 8.0
	UtilityBrain.sound_notice(Vector2(global_position.x, global_position.z), sound_level, sound_radius, 1.0)
	if _player == null or global_position.distance_squared_to(_player.global_position) > WORK_SOUND_RANGE * WORK_SOUND_RANGE:
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
				return _pick_clip(ALONE_CLIPS, 0)
			# Take turns: one talks while the other listens, swapping every few seconds.
			var t := int(Time.get_ticks_msec() / int(TURN_SECONDS * 1000.0))
			return _pick_clip(TALK_CLIPS if (t % 2 == 0) == (person < _partner) else LISTEN_CLIPS, t / 2 + person)
		Act.SHOP, Act.INN:
			if job == 3:
				return _first_clip(JOB_CLIPS[3])
		Act.EAT:
			if float(_mood.get("scarcity", 0.0)) >= 0.4:
				return _first_clip(POOR_MEAL)
		Act.MOURN:
			if float(_brain.traits["pious"]) > 0.6:
				var kneel := _first_clip(MOURN_KNEEL)
				if kneel != "":
					return kneel
		Act.FESTIVE:
			return _pick_clip(FESTIVE_DANCE, int(Time.get_ticks_msec() / 14000))
		Act.TRAIN:
			if _so == null:
				return _first_clip(ACT_CLIPS[Act.TRAIN])
		Act.WATER:
			if _water_is_performing(sim_position()):
				return _first_clip(ACT_CLIPS.get(Act.WATER, []))
			return ""
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
		if anim_name == "Idle":
			# Enter the idle at this person's own point in the loop, not frame 0 (FEEL_AUDIT F9).
			var length := _anim.current_animation_length
			if length > 0.0:
				_anim.seek(fmod(float(person) * 0.381966 + randf() * 0.2, 1.0) * length)


## Per-person idle playback rate, 0.9-1.1 (stable for a person).
func _idle_rate() -> float:
	return 0.9 + 0.2 * fmod(float(person) * 0.618034, 1.0)


# ---------------------------------------------------------------- smart objects
## Claim `pick` ([spot, slot]) and start its session; the route leads to the approach point.
func _so_begin(pick: Array) -> bool:
	var so := NpcWorld.spots()
	_so_release()
	if not so.claim(pick[0], pick[1], person):
		return false
	_so = so.session(person, pick[0], pick[1])
	_so_phase = SmartObjects.Session.APPROACH
	_so_acc = 0.0
	_so_ended = false
	return true


## Stop using the current object. Graceful (play its exit clip) unless `urgent`.
func _so_leave(urgent: bool) -> void:
	if _so == null:
		return
	var exit := String(_so.act.get("exit", ""))
	if not urgent and _so_phase >= SmartObjects.Session.ENTER and _so_phase <= SmartObjects.Session.BETWEEN \
			and exit != "" and _anim != null and _anim.has_animation(exit):
		_so.interrupt()        # exit clip, then DONE releases the slot
		_so_leaving = true
		_wait = float(LifeLibrary.info(exit).get("seconds", 0.8))
	else:
		_so_release()


func _so_release() -> void:
	if NpcWorld.smart != null:
		NpcWorld.smart.release(person)
	_so = null
	_so_phase = -1
	_so_move = Vector3.INF
	_so_snap = false
	_so_leaving = false
	_so_clip = ""
	if _props != null and _act != Act.FIREFIGHT:
		_props.clear()


## Advance the session (at SESSION_HZ) and turn toward what it wants. True while it owns the body.
func _so_frame(delta: float) -> bool:
	var leaving := _so_phase >= SmartObjects.Session.ALIGN
	if not _arrived and not leaving:
		return false          # still walking to the approach point
	_so_acc += delta
	_so_track_clip()
	if _so_acc >= 1.0 / SESSION_HZ:
		var out := _so.update(_so_acc, global_position, _so_clip_done)
		_so_acc = 0.0
		_so_clip_done = false
		_so_apply(out)
		if _so == null:
			return false
	if _so_phase < SmartObjects.Session.ALIGN:
		return false
	var want := _so_face
	if is_nan(want) and _so_move != Vector3.INF:
		var to := _so_move - global_position
		if to.length_squared() > 0.0004:
			want = atan2(to.x, to.z)
	if not is_nan(want):
		_heading = rotate_toward(_heading, want, TURN_RATE * 1.3 * delta)
	_move_speed = 0.0
	return true


func _so_step(delta: float) -> Vector3:
	var pos := global_position
	if _so_move != Vector3.INF:
		var to := _so_move - pos
		to.y = 0.0
		var d := to.length()
		if d > 0.02:
			pos += to / d * minf(0.9 * delta, d)
	elif _so_snap:
		pos = pos.lerp(_so_snap_to, 1.0 - exp(-8.0 * delta))
	return pos


func _so_apply(out: Dictionary) -> void:
	_so_phase = int(out["phase"])
	var clip: String = out["clip"]
	if clip != "" and _anim != null and _anim.has_animation(clip):
		if out["restart"] or _so_clip != clip:
			_so_play(clip, float(LifeLibrary.info(clip).get("blend_in", 0.25)), bool(out["restart"]))
		_anim.speed_scale = _idle_rate() if bool(LifeLibrary.info(clip).get("loop", false)) else 1.0
	if _props != null and _so_phase >= SmartObjects.Session.ENTER and _so_phase <= SmartObjects.Session.EXIT:
		_props.show_props(out["props"])
	_so_face = float(out["face"])
	_so_move = out["move_to"] if out["move_to"] != null else Vector3.INF
	var snap: Variant = out.get("snap")
	_so_snap = snap != null
	if _so_snap:
		_so_snap_to = (snap as Transform3D).origin
		_so_snap_to.y = global_position.y
	var ev: Variant = out["event"]
	if ev != null:
		LivingEvents.emit(String((ev as Dictionary).get("kind", "work")), global_position, float((ev as Dictionary).get("radius", 10.0)), 2.0)
	if _so_phase == SmartObjects.Session.DONE:
		var was_leaving := _so_leaving
		_so_release()
		_so_ended = not was_leaving


func _so_play(clip: String, blend: float, restart: bool) -> void:
	_anim.play(clip, blend)
	if restart and clip == _so_clip:
		_anim.seek(0.0, true)
	_so_clip = clip
	_so_last_pos = 0.0
	_so_clip_done = false


## Loop wrap / one-shot end detection (the session needs to know a cycle finished).
func _so_track_clip() -> void:
	if _anim == null or _so_clip == "" or _anim.current_animation != _so_clip:
		return
	var pos := _anim.current_animation_position
	var a := _anim.get_animation(_so_clip)
	if a == null:
		return
	if a.loop_mode != Animation.LOOP_NONE:
		if pos + 0.0001 < _so_last_pos:
			_so_clip_done = true
	elif not _anim.is_playing() or pos >= a.length - 0.02:
		_so_clip_done = true
	_so_last_pos = pos


# ---------------------------------------------------------------- reactions and barks
## Steering on top of the street graph's wall push: keep away from where danger was seen, out of the
## crop fields (unless a farmer) and out of the way of a cart or rider bearing down on this spot.
func _extra_steering(here: Vector2) -> Vector2:
	var push := _brain.avoid_push(here) * 0.8
	if WorldSim.job[person] != 0:
		push += NpcWorld.field_push(WorldSim.home[person], here) * 1.2
	var mv := NpcWorld.mover_push(here)
	if mv != Vector2.ZERO:
		push += mv * 2.0
		if mv.length() > 0.7 and _yield_time <= 0.0 and _yield_cooldown <= 0.0:
			_begin_sidestep(here, mv, 1.1)
			_yield_cooldown = 1.6
	return push


## Greet (or coldly ignore) the player who walks up: what they say and do depends on how the settlement
## regards them (society reputation, read only). Stops for a moment, turns, one-shot clip + bark.
func _maybe_greet(here: Vector2, player_distance: float, now: int) -> void:
	if player_distance > GREET_RANGE or now < _greet_cd or _player == null or _indoors:
		return
	if _act == Act.FLEE or _act == Act.HIDE or _act == Act.PROTEST or _act == Act.ALARM or _act == Act.FIREFIGHT \
			or _act == Act.SLEEP or _yield_time > 0.0 or _so_phase >= SmartObjects.Session.ALIGN and _act == Act.WORK:
		return
	if NpcWorld.player_armed():
		return
	var to := Vector2(_player.global_position.x, _player.global_position.z) - here
	if to.length() > 1.4 and Vector2(sin(_heading), cos(_heading)).dot(to.normalized()) < -0.25:
		return       # behind their back
	_greet_cd = now + 70000 + (person % 25) * 1000
	if now - _regard_ms > 5000:
		_regard_ms = now
		_regard = NpcWorld.regard_of_player(WorldSim.home[person])
	var cat := "greet_warm" if _regard > 0.25 else ("greet_cold" if _regard < -0.25 else "greet_neutral")
	if cat == "greet_neutral" and DailyRhythm.local_time(person) >= 19.0 and person % 2 == 0:
		cat = "greet_evening"
	var clips: Array = GREET_CLIPS["warm" if _regard > 0.25 else ("cold" if _regard < -0.25 else "neutral")]
	if _so_phase < SmartObjects.Session.ENTER:
		_begin_oneshot(clips, 1.9)
		_oneshot_face_player = true
		if _path_i < _path.size() or not _arrived:
			_wait = maxf(_wait, 1.5)
	_say(NpcWorld.line(cat, person, now / 60000))

## Townsfolk gossip about hidden caves: speaks a rumour from the exploration module and learns the lead.
func _gossip_cave_lead(here: Vector2) -> bool:
	var ex: Variant = Life.realm.mod("exploration") if Life.realm != null else null
	if ex == null:
		return false
	var r: Dictionary = ex.rumour_for(here, person)
	if r.is_empty():
		return false
	_say(String(r["text"]), 4.6)
	ex.learn_lead(String(r["site_id"]), WorldSim.day)
	return true


## Grumble (or cheer) about the state of the town when the player is near: shortages, war, monsters, a death,
## the law, a holiday. Rare per person (GRUMBLE_GAP_MS) and only when a bubble is free (_say's budget).
func _maybe_grumble(here: Vector2, now: int) -> void:
	if now < _grumble_cd or _player == null or _act == Act.SLEEP or _act == Act.FLEE or _act == Act.HIDE:
		return
	if global_position.distance_squared_to(_player.global_position) > 100.0:
		return
	var cat := TownMood.grumble_category(_mood)
	_grumble_cd = now + GRUMBLE_GAP_MS + (person % 17) * 1000
	if cat == "" or (person + now / 90000) % 3 != 0:
		return
	_say(NpcWorld.line(cat, person, now / 60000), 3.4)


func _reaction_tick(here: Vector2, now: int) -> void:
	_maybe_grumble(here, now)
	# Gossip: in a chat pair the speaker says something now and then, when the player is near enough to hear.
	if _act == Act.SOCIAL and _arrived and _partner_node != null and _player != null:
		var turn := int(now / int(TURN_SECONDS * 1000.0))
		if turn != _gossip_turn:
			_gossip_turn = turn
			if (turn % 2 == 0) == (person < _partner) and global_position.distance_squared_to(_player.global_position) < 196.0 \
					and (turn + person) % 3 == 0:
				var sid: int = WorldSim.home[person]
				var rumours := NpcWorld.rumour_lines(sid)
				if not rumours.is_empty() and (turn / 3 + person) % 2 == 0:
					_say(String(rumours[(turn + person) % rumours.size()]), 4.6)
				elif turn % 4 == 0 and _gossip_cave_lead(here):
					pass   # a cave / hidden-entrance rumour was spoken (and learned)
				else:
					_say(NpcWorld.line("gossip_generic", person, turn), 3.6)
	# Fire: water thrown at the flames shrinks them (and dies out sooner with more helpers).
	if _act == Act.FIREFIGHT and _arrived and _fire_slot >= 0:
		_throw_t -= THINK_INTERVAL
		if _throw_t <= 0.0:
			_throw_t = 2.4
			NpcWorld.douse(_fire_slot, 0.08)
			if _contact:
				var fp := NpcWorld.incident_pos(_fire_slot)
				VFX.sparks(get_parent(), Vector3(fp.x, WorldGen.height(fp.x, fp.y) + 0.9, fp.y), Color(0.55, 0.78, 1.0), 8)


## A crime happened at `pos` (NpcWorld.report_crime): did this villager see it (or only hear it)?
## Witnesses shout and, like everyone who heard, run for a guard; guards go to look.
func witness(pos: Vector2, _kind: String, saw: bool, _by_player: bool) -> bool:
	var now := Time.get_ticks_msec()
	_crime_until = now + 25000
	_crime_pos = pos
	_crime_heard = not saw
	_decide = 0.0          # think about it on the next tick
	return true


## Short line above the head (at most NpcWorld.MAX_BUBBLES on screen, only near the player).
func _say(text: String, seconds := BUBBLE_SECONDS) -> void:
	if text == "" or _indoors or _player == null:
		return
	if global_position.distance_squared_to(_player.global_position) > 26.0 * 26.0:
		return
	var showing := _bubble != null and _bubble.visible
	if not showing and NpcWorld.bubbles_shown >= NpcWorld.MAX_BUBBLES:
		return
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.double_sided = true
		_bubble.no_depth_test = false
		_bubble.pixel_size = 0.0042
		_bubble.font_size = 34
		_bubble.outline_size = 10
		_bubble.modulate = Color(1.0, 0.96, 0.82)
		_bubble.outline_modulate = Color(0.08, 0.06, 0.05, 0.95)
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.width = 360.0
		_bubble.position.y = 2.25 if not _child else 1.85
		_bubble.visible = false
		add_child(_bubble)
	_bubble.text = text
	if not showing:
		NpcWorld.bubbles_shown += 1
		_bubble.visible = true
	_bubble_until = Time.get_ticks_msec() + int(seconds * 1000.0)


func _bubble_tick(now: int) -> void:
	if _bubble != null and _bubble.visible and (now >= _bubble_until or _indoors):
		_bubble.visible = false
		NpcWorld.bubbles_shown = maxi(NpcWorld.bubbles_shown - 1, 0)


func _begin_oneshot(names: Array, seconds: float) -> void:
	var clip := _first_clip(names)
	if clip == "":
		return
	_oneshot = clip
	_oneshot_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_oneshot_started = false
	_oneshot_face_player = false


## Stable per-person pick among the clips the rig has (`salt` varies it over time).
func _pick_clip(names: Array, salt: int) -> String:
	if names.is_empty() or _anim == null:
		return ""
	var key := names.hash()
	var avail: Array = _clip_cache.get(key, [])
	if avail.is_empty():
		for n: String in names:
			if _anim.has_animation(n):
				avail.append(n)
		_clip_cache[key] = avail
	if avail.is_empty():
		return ""
	return avail[absi(person * 31 + salt) % avail.size()]
