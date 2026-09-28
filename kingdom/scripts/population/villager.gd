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
##  - Daily rhythm: DailyRhythm staggers departures per person and adds an
##    evening at the inn.
##  - Thinking (schedule, contact tier, spacing, stuck checks) runs every
##    THINK_INTERVAL on a per-person phase, not every frame.

const StreetGraph := preload("res://scripts/population/street_graph.gd")
const DailyRhythm := preload("res://scripts/population/daily_rhythm.gd")

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
## Step aside when the player comes this close.
const YIELD_RADIUS := 1.7
const SEPARATION_RADIUS := 0.9
const PERSONAL_SPACE := 1.2
const THINK_INTERVAL := 0.3
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

# Motion.
var _walk_speed := WALK_SPEED
var _move_speed := 0.0
var _heading := 0.0
var _resolved_speed := 0.0
var _separation := Vector2.ZERO
var _player_push := Vector2.ZERO
var _avoid := Vector2.ZERO
var _contact := false
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
	_add_head_look(model)
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
	_think_tick()


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


func _physics_process(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think += THINK_INTERVAL
		_think_tick()
	var here := Vector2(global_position.x, global_position.z)
	if _contact:
		_check_yield(here, delta)
	var planar := _steer(here, delta)
	if _contact:
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
	_set_contact(player_distance < CONTACT_ENTER or (_contact and player_distance < CONTACT_EXIT))
	# Schedule: a new state means a new goal; small moves of the same goal don't re-plan.
	var st := DailyRhythm.state(person)
	if st != _state:
		_state = st
		var goal := DailyRhythm.goal(person, st, _graph)
		if _goal == Vector2.INF or goal.distance_to(_goal) > 1.0:
			_goal = goal
			_needs_route = true
			_arrived = false
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
		_tag.text = "%s\n%s" % [WorldSim.describe(person), DailyRhythm.label(person, _state, travelling)]


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
			target_speed = _walk_speed
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
	if face != Vector2.INF and face.length_squared() > 0.0001:
		var diff := wrapf(atan2(face.x, face.y) - _heading, -PI, PI)
		_heading = wrapf(_heading + clampf(diff, -TURN_RATE * delta, TURN_RATE * delta), -PI, PI)
		# Turn on the spot rather than moonwalk: slow while facing away.
		target_speed *= clampf(cos(diff) * 0.6 + 0.4, 0.15, 1.0)
	var response := ACCELERATION if target_speed > _move_speed else BRAKING
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
	_look_target.global_position = _look_target.global_position.lerp(target, 1.0 - exp(-7.0 * delta))


func _update_activity(delta: float) -> void:
	_step_distance = 0.0
	if _anim == null:
		return
	_anim.speed_scale = 1.0
	# Work only once actually at the spot; waiting, yielding or stopped mid-route idles.
	var activity := _activity_for_person() if _arrived and _yield_time <= 0.0 else ""
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


func _activity_for_person() -> String:
	var job: int = WorldSim.job[person]
	match _state:
		DailyRhythm.State.MARKET, DailyRhythm.State.INN:
			return "Idle_Talking" if job != 3 else "Idle_Shield"
		DailyRhythm.State.WORK:
			match job:
				0: return "Farm_Harvest"
				1: return "Fixing_Kneeling"
				2: return "Idle_Talking"
				3: return "Idle_Shield"
				4: return "Interact"
				5: return "TreeChopping"
	return ""


func _play(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.2)
