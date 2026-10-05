class_name Wolf
extends CharacterBody3D
## Forest beast: wolf (Meshy mesh on the CC0 Quaternius wolf rig), plus boar,
## bear and the CC0 blight rat / fungal brute when `species` is set before
## add_child. Small state machine: roam its territory -> stalk -> attack ->
## flee when badly hurt -> retreat home. Also retreats from strong runestone
## protection. A cheap capsule blocks the player and world nearby; distant
## animals keep terrain-based steering.
##
## Readable pressure (docs/concepts/COMBAT_PRESSURE_AND_READABILITY.md):
## - attack tokens: only slot holders close in and strike; the rest circle at a
##   ring around the target and take turns (creature_attack_tokens.gd);
## - every attack has a wind-up: the beast stops, growls and plays its attack
##   anticipation before a short authored-speed strike; damage only lands if the
##   target is still in reach, in front and not behind a wall at that moment;
## - a wounded beast flees below the player's run speed, then limps home and
##   recovers, so the chase always ends one way or the other.
## - deaths go physical (ragdoll.gd, capped world-wide; the death clip is the
##   fallback) and a heavy hit (knockback >= 6 or a parried bite) knocks a living
##   beast over for a second before it blends back into its idle.

signal died(wolf: Wolf)

const Models := preload("res://scripts/actors/creature_models.gd")
const Tokens := preload("res://scripts/actors/creature_attack_tokens.gd")
const Telegraph := preload("res://scripts/combat/telegraph.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const SoulbeastAura := preload("res://scripts/actors/soulbeast_aura.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")
const NodePool := preload("res://scripts/core/node_pool.gd")
const LEGACY_MODEL := "res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Wolf.gltf"
const LEGACY_CLIPS := {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack",
	"hit": "Idle_HitReact1", "death": "Death"}
const PLAYER_SOLID_RANGE := 16.0
## Hit knockback plays out as a short slide (time constant KNOCK_TAU, same 0.12 m per
## unit of knockback as before) instead of an instant teleport (FEEL_AUDIT F5).
const KNOCK_TAU := 0.1
const KNOCK_SHARE := 0.12
const STRIKE_TIME := 0.2
const WORLD_LAYER := 1
const ENEMY_LAYER := 4
const ESCAPE_DISTANCE := 30.0     # a fleeing beast this far from the player has got away
## The player walks at 2.4 m/s and runs at 6.5 m/s (player.gd WALK / RUN).
## Chase, charge and flee speeds all stay below the run, so the player can always
## either finish a wounded animal or break off a fight.
## windup: seconds from the start of the attack to contact; recover: seconds after
## contact before moving again; slots: most of this kind attacking one target at
## once; ring: circling distance while waiting for a turn; poise: not interrupted
## by hits; flee_below: health at which it runs (0 = fights to the death).
## ward_response (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, roads pillar): how this
## species treats runestone coverage. "shun": weak, avoids it outright.
## "brief": strong enough to push in for a while before it gives up and
## leaves. "ignore": corrupted/Rift-touched, barely notices it.
const SPECIES := {
	"wolf": {"health": 45, "damage": 9, "knock": 1.5, "walk": 0.8, "trot": 1.5, "run": 4.5,
		"flee": 5.2, "limp": 3.6, "aggro": 14.0, "stalk": 35.0, "stalk_speed": 1.0, "reach": 2.3,
		"strike": 1.9, "windup": 0.5, "recover": 0.45, "cooldown": [1.4, 2.0], "flee_below": 15,
		"slots": 2, "ring": 5.5, "radius": 0.34, "height": 1.1, "poise": false, "voice": "wolf_growl",
		"ward": "shun"},
	"boar": {"health": 60, "damage": 11, "knock": 3.5, "walk": 0.5, "trot": 1.2, "run": 4.8,
		"flee": 5.0, "limp": 3.4, "aggro": 7.0, "stalk": 0.0, "stalk_speed": 0.0, "reach": 2.2,
		"strike": 1.8, "windup": 0.55, "recover": 0.5, "cooldown": [1.6, 2.2], "flee_below": 18,
		"slots": 2, "ring": 5.0, "radius": 0.36, "height": 0.9, "poise": false, "voice": "boar_grunt",
		"ward": "shun"},
	"bear": {"health": 150, "damage": 18, "knock": 4.0, "walk": 1.2, "trot": 1.5, "run": 4.8,
		"flee": 4.6, "limp": 3.2, "aggro": 9.0, "stalk": 18.0, "stalk_speed": 0.0, "reach": 2.8,
		"strike": 2.2, "windup": 0.75, "recover": 0.6, "cooldown": [2.0, 2.8], "flee_below": 25,
		"slots": 1, "ring": 6.0, "radius": 0.55, "height": 1.4, "poise": true, "voice": "bear_growl",
		"ward": "brief"},
	"blight_rat": {"health": 18, "damage": 5, "knock": 0.0, "walk": 0.35, "trot": 1.1, "run": 3.4,
		"flee": 3.6, "limp": 3.0, "aggro": 10.0, "stalk": 16.0, "stalk_speed": 0.6, "reach": 1.6,
		"strike": 1.2, "windup": 0.45, "recover": 0.35, "cooldown": [1.2, 1.8], "flee_below": 0,
		"slots": 2, "ring": 3.5, "radius": 0.22, "height": 0.5, "poise": false, "voice": "",
		"ward": "shun"},
	"fungal_brute": {"health": 110, "damage": 16, "knock": 4.0, "walk": 1.0, "trot": 1.2, "run": 1.9,
		"flee": 1.9, "limp": 1.5, "aggro": 9.0, "stalk": 14.0, "stalk_speed": 0.0, "reach": 2.4,
		"strike": 1.9, "windup": 0.8, "recover": 0.6, "cooldown": [2.0, 2.8], "flee_below": 0,
		"slots": 1, "ring": 5.0, "radius": 0.42, "height": 1.6, "poise": true, "voice": "",
		"ward": "ignore"},
	# Region 1 creatures (package C11). Stats are first estimates; behaviour (herd graze / flee / antler charge, Warden phases)
	# is Codex's (X3, X4). Stagborn never start a fight (aggro 0) and run when hurt; the Antlered Warden is an OPTIONAL encounter.
	"ghoul": {"health": 70, "damage": 12, "knock": 2.0, "walk": 0.6, "trot": 1.2, "run": 2.4,
		"flee": 2.4, "limp": 1.6, "aggro": 12.0, "stalk": 18.0, "stalk_speed": 0.5, "reach": 2.0,
		"strike": 1.5, "windup": 0.9, "recover": 0.6, "cooldown": [1.8, 2.6], "flee_below": 0,
		"slots": 2, "ring": 4.0, "radius": 0.4, "height": 1.7, "poise": false, "voice": "", "ward": "ignore"},
	"giant_wasp": {"health": 24, "damage": 7, "knock": 0.5, "walk": 1.0, "trot": 2.4, "run": 4.2,
		"flee": 4.4, "limp": 2.5, "aggro": 13.0, "stalk": 20.0, "stalk_speed": 1.0, "reach": 1.8,
		"strike": 1.4, "windup": 0.5, "recover": 0.5, "cooldown": [1.2, 1.8], "flee_below": 6,
		"slots": 3, "ring": 3.5, "radius": 0.3, "height": 1.2, "poise": false, "voice": "", "ward": "shun"},
	"bog_toad": {"health": 40, "damage": 8, "knock": 1.5, "walk": 0.4, "trot": 1.0, "run": 2.2,
		"flee": 2.4, "limp": 1.6, "aggro": 6.0, "stalk": 0.0, "stalk_speed": 0.0, "reach": 2.4,
		"strike": 2.0, "windup": 0.6, "recover": 0.6, "cooldown": [1.8, 2.6], "flee_below": 8,
		"slots": 2, "ring": 3.5, "radius": 0.4, "height": 0.6, "poise": false, "voice": "", "ward": "shun"},
	"rift_slime": {"health": 26, "damage": 6, "knock": 0.5, "walk": 0.5, "trot": 0.9, "run": 1.4,
		"flee": 1.6, "limp": 1.0, "aggro": 9.0, "stalk": 12.0, "stalk_speed": 0.4, "reach": 1.4,
		"strike": 1.1, "windup": 0.5, "recover": 0.4, "cooldown": [1.4, 2.0], "flee_below": 0,
		"slots": 3, "ring": 3.0, "radius": 0.4, "height": 0.7, "poise": false, "voice": "", "ward": "ignore"},
	"rift_wraith": {"health": 90, "damage": 16, "knock": 2.5, "walk": 1.0, "trot": 2.0, "run": 3.6,
		"flee": 3.6, "limp": 2.0, "aggro": 15.0, "stalk": 28.0, "stalk_speed": 0.9, "reach": 2.6,
		"strike": 2.0, "windup": 0.8, "recover": 0.6, "cooldown": [2.0, 3.0], "flee_below": 0,
		"slots": 1, "ring": 5.0, "radius": 0.5, "height": 1.9, "poise": true, "voice": "", "ward": "ignore"},
	"stagborn_elk": {"health": 70, "damage": 12, "knock": 4.0, "walk": 1.2, "trot": 2.6, "run": 5.2,
		"flee": 5.2, "limp": 3.4, "aggro": 0.0, "stalk": 0.0, "stalk_speed": 0.0, "reach": 2.6,
		"strike": 2.0, "windup": 0.9, "recover": 0.7, "cooldown": [2.5, 3.5], "flee_below": 60,
		"slots": 1, "ring": 6.0, "radius": 0.5, "height": 1.6, "poise": false, "voice": "", "ward": "ignore"},
	"stagborn_warden": {"health": 420, "damage": 24, "knock": 6.0, "walk": 1.24, "trot": 2.8, "run": 6.9,
		"flee": 6.9, "limp": 3.0, "aggro": 0.0, "stalk": 0.0, "stalk_speed": 0.0, "reach": 3.4,
		"strike": 2.8, "windup": 1.1, "recover": 0.9, "cooldown": [2.4, 3.4], "flee_below": 0,
		"slots": 1, "ring": 7.0, "radius": 0.8, "height": 2.4, "poise": true, "voice": "", "ward": "ignore"},
}
## "brief" wards (bears...) may sit inside strong coverage this long before the
## usual retreat-at-strong-coverage rule catches up with them.
const WARD_BRIEF_LINGER := 22.0
enum State { ROAM, STALK, ATTACK, FLEE, RETREAT }

var species := "wolf"
var den_id := -1
var home := Vector2.ZERO
var territory := 200.0
var health := 45
var max_health := 45
var dead := false
var team := 1
var state := State.ROAM

var _sp: Dictionary
var _kind := ""                  # creature_models key ("" = legacy Quaternius wolf)
var _clips := {}
var _walk_clip_speed := 0.64
var _run_clip_speed := 2.63
var _impact_time := 0.25
var _anim: AnimationPlayer
var _target := Vector3.ZERO
var _think := 0.0
var _attack_cd := 0.0
var _busy := 0.0
var _speed := 0.0
var _knock := Vector3.ZERO        # sliding knockback velocity (m/s)
var _actor_shape: CollisionShape3D
var _winding := 0.0              # > 0 while an attack winds up
var _strike_snap_sent := false
var _strike_target: Node3D
var _turn_rest := 0.0            # waits this long before asking for another slot
var _turn_time := 0.0            # how long the current slot has been held
var _strikes_left := 1
var _orbit := 0.0
var _orbit_dir := 1.0
var _orbit_flip := 0.0
var _circling := false
var _flee_time := 0.0
var _provoked := 0.0
var _escape_told := false
var _regen := 0.0
var _ragdoll: Node
var _model: Node3D
var _fighter: RefCounted          # NpcFighter for species with a move table (wolf); others keep SPECIES only
var _cur_move: Resource
var _cur_windup := 0.5
var _stats := {}                  # CombatStats row (wolf only; other species use SPECIES numbers)
var _ward_timer := 0.0            # seconds spent inside strong coverage (ward "brief")
var _death_tween: Tween
var _model_scale0 := Vector3.ONE  # F12 pooling: scale the death squash starts from


func _ready() -> void:
	_sp = SPECIES.get(species, SPECIES["wolf"])
	if species == "wolf" and Fighter.has_archetype("wolf"):
		_fighter = Fighter.make("wolf", randi())
	max_health = int(_sp["health"])
	if _fighter != null:
		_stats = _fighter.apply_level(CombatStats.player_level())   # matching level: table value
		max_health = int(_stats["hp"])
	health = max_health
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_actor_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(_sp["radius"])
	capsule.height = maxf(float(_sp["height"]), capsule.radius * 2.0 + 0.05)
	_actor_shape.shape = capsule
	_actor_shape.position.y = capsule.height * 0.5
	_actor_shape.disabled = true
	add_child(_actor_shape)
	add_to_group("team1")
	add_to_group("combatant")
	var model: Node3D = Models.instance(species) if Models.has(species) else null
	if model:
		_kind = species
		_clips = Models.clips(species)
		var info := Models.info(species)
		_walk_clip_speed = float(info["walk"])
		_run_clip_speed = float(info["run"])
		_impact_time = float(info["impact"])
	elif species == "wolf" and ResourceLoader.exists(LEGACY_MODEL):
		model = Assets.scene(LEGACY_MODEL).instantiate()
		var box := Assets.visual_aabb(model)
		model.scale = Vector3.ONE * (0.85 / maxf(box.size.y, 0.01))   # ~85 cm at the shoulder
		_clips = LEGACY_CLIPS
	else:
		queue_free()        # model not imported yet
		return
	add_child(model)
	_model = model
	_model_scale0 = model.scale
	_anim = Assets.animation_player(model)
	_ragdoll = Ragdoll.attach(self, model, [_anim])
	if _kind == "" and _anim:
		for a in ["Idle", "Walk", "Gallop"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_strikes_left = randi_range(1, 2)
	_pick_roam_target()


func _exit_tree() -> void:
	Tokens.release(self)


# --- pooling (F12, scripts/core/node_pool.gd): a released body is as good as new --------------------------

func on_acquire() -> void:
	pass          # fields were put back by reset() on release; the spawner now sets species-agnostic ones (den, home)


func on_release() -> void:
	Tokens.release(self)
	Telegraph.end(self)


## Everything a fight or a death changed: health, state, AI timers, tokens, tween, groups, signals, ragdoll, model.
## A body that never entered the tree has nothing to reset (_ready sets it all).
func reset() -> void:
	if _model == null:
		return
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
	for c: Dictionary in died.get_connections():
		died.disconnect(c["callable"])
	for g in get_groups():
		if not String(g).begins_with("_") and g != &"team1" and g != &"combatant":
			remove_from_group(g)
	for m in get_meta_list():
		if m != &"_npool":
			remove_meta(m)
	add_to_group("team1")
	add_to_group("combatant")
	_sp = SPECIES.get(species, SPECIES["wolf"])
	if species == "wolf" and Fighter.has_archetype("wolf"):
		_fighter = Fighter.make("wolf", randi())
		_stats = _fighter.apply_level(CombatStats.player_level())
		max_health = int(_stats["hp"])
	else:
		max_health = int(_sp["health"])
	health = max_health
	dead = false
	state = State.ROAM
	den_id = -1
	home = Vector2.ZERO
	territory = 200.0
	velocity = Vector3.ZERO
	scale = Vector3.ONE            # spawners enlarge corrupted wolves and apex beasts
	_cur_move = null
	_target = global_position
	_think = 0.0
	_attack_cd = 0.0
	_busy = 0.0
	_speed = 0.0
	_knock = Vector3.ZERO
	_winding = 0.0
	_strike_snap_sent = false
	_strike_target = null
	_turn_rest = 0.0
	_turn_time = 0.0
	_strikes_left = randi_range(1, 2)
	_orbit = 0.0
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_orbit_flip = 0.0
	_circling = false
	_flee_time = 0.0
	_provoked = 0.0
	_escape_told = false
	_regen = 0.0
	_ward_timer = 0.0
	_actor_shape.disabled = true
	_model.scale = _model_scale0
	if _ragdoll != null:
		_ragdoll.call("revive")
		var sk: Variant = _ragdoll.get("skeleton")
		if sk is Skeleton3D:
			(sk as Skeleton3D).reset_bone_poses()
	_play("idle", true)


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _knock.length_squared() > 0.0004:
		move_and_collide(_knock * delta)
		global_position.y = WorldGen.height(global_position.x, global_position.z)
		_knock *= exp(-delta / KNOCK_TAU)
	_think -= delta
	_attack_cd -= delta
	_busy -= delta
	_turn_rest -= delta
	_provoked -= delta
	_orbit_flip -= delta
	var player := _quarry()
	if _winding > 0.0:
		_winding -= delta
		if is_instance_valid(_strike_target) and _winding > _cur_windup * 0.4:
			_face(_strike_target.global_position, delta)   # tracks early, then commits
		if _winding <= STRIKE_TIME and not _strike_snap_sent:
			_strike_snap_sent = true
			if _anim:
				_anim.speed_scale = 1.0
			VFX.flash(get_parent(), global_position + Vector3.UP * float(_sp["height"]) * 0.8,
				Color(1.0, 0.55, 0.2), 1.5, 0.08, 3.0)
		if _winding <= 0.0:
			_impact()
	var here := Vector2(global_position.x, global_position.z)
	var cov := Frontier.runestones.coverage(here)
	# Behaviour by class, not walls (roads pillar): shun avoids coverage as
	# below; brief can push in for a while before it gives up; ignore (Rift/
	# corrupted) never reads coverage as a reason to leave at all.
	var ward := String(_sp.get("ward", "shun"))
	if ward == "ignore":
		cov = 0.0
	elif ward == "brief":
		if cov > 0.25:
			_ward_timer += delta
		else:
			_ward_timer = maxf(0.0, _ward_timer - delta * 2.0)
		if _ward_timer < WARD_BRIEF_LINGER:
			cov = minf(cov, 0.5)      # not yet worn out its welcome: stays below the retreat threshold
	if _think <= 0.0:
		_think = 0.3
		_decide(player, cov)
	var want := 0.0
	var face_player := false
	match state:
		State.ROAM:
			want = float(_sp["walk"])
			if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 2.0:
				_pick_roam_target()
		State.STALK:
			want = float(_sp["stalk_speed"])
			_target = player.global_position
			face_player = true
		State.ATTACK:
			want = _attack_move(player, delta)
			face_player = _circling
		State.FLEE:
			_flee_time += delta
			want = lerpf(float(_sp["flee"]), float(_sp["limp"]), clampf(_flee_time / 6.0, 0.0, 1.0))
			_target = global_position + _flee_dir(player) * 6.0
		State.RETREAT:
			want = float(_sp["trot"])
			_target = Vector3(home.x, 0.0, home.y)
			_regen += delta * 1.5           # slow recovery on the way home
			if _regen >= 1.0:
				_regen -= 1.0
				health = mini(max_health, health + 1)
	if _busy > 0.0 or _winding > 0.0:
		want = 0.0
	_speed = lerpf(_speed, want, 6.0 * delta)
	_update_player_collision(player)
	var to := _target - global_position
	to.y = 0.0
	if face_player and player and _winding <= 0.0:
		_face(player.global_position, delta)
	if to.length() > 0.3 and _speed > 0.05:
		var dir := to.normalized()
		var turn_pace := 1.0     # local: never feeds back into _speed
		if not face_player and _winding <= 0.0:
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * delta))
			# Quadrupeds turn into a new heading instead of strafing sideways.
			var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
			turn_pace = clampf(0.55 + 0.45 * fwd.dot(dir), 0.35, 1.0)
			dir = (fwd * 0.65 + dir * 0.35).normalized()
		var step_velocity := dir * _speed * turn_pace
		if _near_player(player):
			velocity = step_velocity
			move_and_slide()
			global_position.y = WorldGen.height(global_position.x, global_position.z)
		else:
			var p := global_position + step_velocity * delta
			p.y = WorldGen.height(p.x, p.z)
			global_position = p
	if _busy <= 0.0 and _winding <= 0.0:
		var running := _speed > _walk_clip_speed * 1.8 and _run_clip_speed > _walk_clip_speed * 1.2
		var locomotion := "run" if running else ("walk" if _speed > 0.2 else "idle")
		var authored := _run_clip_speed if running else _walk_clip_speed
		var rate := 1.0 if locomotion == "idle" else clampf(_speed / authored, 0.6, 1.9)
		_play(locomotion, false, rate)


## Who this beast hunts: the player, unless it was given prey (meta "prey": a node with `global_position`,
## `take_damage` and `dead`, e.g. the Thornfield grain cart) and the player is not within PREY_PLAYER_RANGE.
const PREY_PLAYER_RANGE := 9.0


func _quarry() -> Node3D:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if has_meta("prey"):
		var prey := get_meta("prey") as Node3D
		if is_instance_valid(prey) and not bool(prey.get("dead")):
			if player == null or global_position.distance_to(player.global_position) > PREY_PLAYER_RANGE:
				return prey
	return player


## Movement in ATTACK: slot holders close in and strike; others circle.
func _attack_move(player: Node3D, delta: float) -> float:
	if player == null:
		return 0.0
	var d := global_position.distance_to(player.global_position)
	var has_slot := Tokens.holds(self, player)
	if has_slot:
		_circling = false
		_turn_time += delta
		_target = player.global_position
		if _turn_time > Tokens.HOLD_TIME - 0.5 and _winding <= 0.0 and _busy <= 0.0:
			_end_turn(1.0)            # couldn't land it in time: let another try
		if d <= float(_sp["strike"]) and _attack_cd <= 0.0 and _busy <= 0.0 and _winding <= 0.0 \
				and Tokens.try_strike(player):
			_begin_attack(player)
		return float(_sp["run"]) if d > float(_sp["strike"]) * 0.9 else 0.0
	# Waiting for a turn: hold a spot on a ring around the target, drifting round.
	if not _circling:
		_circling = true
		var from := global_position - player.global_position
		_orbit = atan2(from.z, from.x)
	if _orbit_flip <= 0.0:
		_orbit_flip = randf_range(2.5, 5.0)
		if randf() < 0.35:
			_orbit_dir = -_orbit_dir
	var ring := float(_sp["ring"])
	_orbit += _orbit_dir * (float(_sp["trot"]) * 0.45 / ring) * delta
	_target = player.global_position + Vector3(cos(_orbit), 0.0, sin(_orbit)) * ring
	var gap := Vector2(_target.x - global_position.x, _target.z - global_position.z).length()
	if gap < 0.6:
		return 0.0
	return float(_sp["run"]) * 0.7 if gap > 1.5 else float(_sp["trot"])


func _decide(player: Node3D, cov: float) -> void:
	var flee_below := int(_sp["flee_below"])
	if flee_below > 0 and health < flee_below and state != State.RETREAT:
		if state != State.FLEE:
			state = State.FLEE
			_flee_time = 0.0
			_stop_fighting()
		if player == null or player.get("dead") or global_position.distance_to(player.global_position) > ESCAPE_DISTANCE:
			_escape(player)
		return
	if state == State.RETREAT:
		var at_home := Vector2(global_position.x, global_position.z).distance_to(home) < 8.0
		var player_close: bool = player != null and not player.get("dead") and global_position.distance_to(player.global_position) < 10.0
		if player_close and health < flee_below:
			state = State.FLEE          # cornered on the way home: bolt again
			_flee_time = 2.0
			return
		if at_home or (cov < 0.3 and health >= flee_below):
			if at_home:
				health = maxi(health, int(max_health * 0.6))
			state = State.ROAM
			_escape_told = false
			_pick_roam_target()
		return
	if cov > 0.55:
		state = State.RETREAT           # strong runestone protection: head home
		_stop_fighting()
		return
	if player == null or player.get("dead"):
		_set_state(State.ROAM)
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var d := global_position.distance_to(player.global_position)
	var ward := String(_sp.get("ward", "shun"))
	var player_cov := 0.0 if ward == "ignore" else Frontier.runestones.coverage(pp)
	var in_territory := pp.distance_to(home) < territory * 1.3
	var aggro := (float(_sp["aggro"]) if _provoked <= 0.0 else maxf(float(_sp["aggro"]), 22.0)) * Frontier.danger_mult(WorldSim.time_of_day)
	# Stealth: a sneaking player (player.noise_radius(), 10 m at a walk) is noticed
	# closer, a running one farther. Once fighting, the range stays as it is.
	if _provoked <= 0.0 and state != State.ATTACK and player.has_method("noise_radius"):
		aggro *= clampf(float(player.call("noise_radius")) / 10.0, 0.4, 1.6)
	var wary := 1.0     # F10: a bonded Soulbeast beside the player makes wild wolves wary (soulbeast_aura.gd)
	if species == "wolf" and _provoked <= 0.0:
		wary = SoulbeastAura.wary_factor(global_position)
		aggro *= wary
	if player_cov > 0.5:
		_set_state(State.ROAM)            # won't follow prey into protected land
	elif d < aggro and (in_territory or _provoked > 0.0):
		_set_state(State.ATTACK)
		Tokens.engage(self, player)
		if _turn_rest <= 0.0 and not Tokens.holds(self, player):
			if Tokens.request(self, player, int(_sp["slots"])):
				_turn_time = 0.0
	elif d < float(_sp["stalk"]) * wary and in_territory:
		_set_state(State.STALK)
	else:
		_set_state(State.ROAM)


func _set_state(s: State) -> void:
	if s != State.ATTACK and state == State.ATTACK:
		_stop_fighting()
	state = s


func _stop_fighting() -> void:
	Tokens.release(self)
	_circling = false
	if _winding > 0.0:
		_winding = 0.0
		_busy = 0.2


func _end_turn(rest: float) -> void:
	Tokens.yield_slot(self)
	_turn_rest = rest
	_turn_time = 0.0
	_strikes_left = randi_range(1, 2)
	_circling = false


## Away from the player, bending toward the den when that isn't back past them.
func _flee_dir(player: Node3D) -> Vector3:
	var away := Vector3.FORWARD
	if player:
		away = global_position - player.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var to_home := Vector3(home.x - global_position.x, 0.0, home.y - global_position.z)
	if to_home.length() > 4.0:
		to_home = to_home.normalized()
		if to_home.dot(away) > -0.2:
			away = (away + to_home * 0.6).normalized()
	return away


func _escape(player: Node3D) -> void:
	state = State.RETREAT
	if not _escape_told and player and global_position.distance_to(player.global_position) < 60.0:
		_escape_told = true
		Game.say("The wounded %s slinks away toward its den." % species.replace("_", " "))


func _near_player(player: Node3D) -> bool:
	return player != null and player.global_position.distance_squared_to(global_position) < PLAYER_SOLID_RANGE * PLAYER_SOLID_RANGE


func _update_player_collision(player: Node3D) -> void:
	var should_disable := not _near_player(player)
	if _actor_shape.disabled != should_disable:
		_actor_shape.set_deferred("disabled", should_disable)


func _pick_roam_target() -> void:
	var ang := randf() * TAU
	var p := home + Vector2(cos(ang), sin(ang)) * randf_range(minf(10.0, territory * 0.3), territory * 0.8)
	_target = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _face(at: Vector3, delta: float) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))


## Wind-up: stretch anticipation to its fairness timer, then play the last
## STRIKE_TIME at the clip's authored rate. The timer and hit frame stay fixed.
func _begin_attack(target: Node3D) -> void:
	var windup := float(_sp["windup"])
	var total := windup + float(_sp["recover"])
	_cur_move = null
	if _fighter != null:
		_cur_move = _fighter.choose_move(global_position.distance_to(target.global_position),
			"blocking" if bool(target.get("blocking")) else "idle")
		if _cur_move != null:
			windup = _cur_move.windup
			total = _cur_move.total()
	_cur_windup = windup
	_attack_cd = randf_range(float(_sp["cooldown"][0]), float(_sp["cooldown"][1])) * float(_stats.get("cdm", 1.0))
	_winding = windup
	_strike_snap_sent = false
	_busy = total
	_strike_target = target
	var pre := maxf(_impact_time - STRIKE_TIME, 0.05)
	var hold := maxf(windup - STRIKE_TIME, 0.05)
	_play("attack", true, clampf(pre / hold, 0.25, 2.0))
	Telegraph.begin(self, _cur_move, _cur_move.reach if _cur_move != null else float(_sp["strike"]), windup, bool(_sp["poise"]))
	var voice := String(_sp["voice"])
	if voice != "" and Audio.has_sound(voice):
		Audio.play_sfx(voice, global_position + Vector3.UP * 0.6, -4.0, 0.1)


## Describes the blow in flight for the defender's HitResolver call (player.take_damage reads it).
func attack_info() -> Dictionary:
	if _cur_move == null:
		return {}
	return {"poise_damage": _cur_move.poise_damage, "lane": _cur_move.lane, "parryable": _cur_move.parryable,
		"unblockable": _cur_move.unblockable}


func _impact() -> void:
	if _anim:
		_anim.speed_scale = 1.0
	var target := _strike_target
	_strike_target = null
	var reach := float(_sp["reach"])
	var dmg := int(_sp["damage"])
	var knock := float(_sp["knock"])
	if _cur_move != null:
		reach = _cur_move.reach
		dmg = _cur_move.damage
		knock = _cur_move.knockback
	if Tokens.can_hit(self, target, reach, WORLD_LAYER) and target.has_method("take_damage"):
		var push := (target.global_position - global_position)
		push.y = 0.0
		dmg = int(round(float(dmg) * float(_stats.get("dmg", 1.0))))
		if has_meta("r1_safe") and target.get("health") != null:
			dmg = mini(dmg, maxi(int(target.get("health")) - 1, 0))   # Region1 C8: the first fight knocks down, it never kills
		target.take_damage(dmg, self, push.normalized() * knock)
		Audio.sfx("hit", global_position, -8.0)
	_cur_move = null
	_strikes_left -= 1
	if _strikes_left <= 0:
		_end_turn(randf_range(1.4, 2.6))


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	health -= amount
	_knock += Vector3(knockback.x, 0.0, knockback.z) * (KNOCK_SHARE / KNOCK_TAU)
	var hit_from := (from as Node3D).global_position if from is Node3D else Vector3.INF
	if health <= 0:
		dead = true
		Tokens.release(self)
		_winding = 0.0
		remove_from_group("team1")
		remove_from_group("combatant")
		_actor_shape.set_deferred("disabled", true)
		if not (_ragdoll and _ragdoll.die(knockback, hit_from)):
			_play("death", true)
		died.emit(self)
		var t := create_tween()
		_death_tween = t
		t.tween_interval(6.0)
		# Squash the model, not the body: Jolt rejects non-uniform body scale.
		t.tween_property(_model, "scale", _model.scale * Vector3(1, 0.01, 1), 0.5)
		t.tween_callback(NodePool.recycle.bind(self))     # pooled bodies go back to their pool, others queue_free
		return
	if from is Node3D:
		_provoked = 15.0
	# Hyper-armour: a blow below the poise break (parries and clashes send amount 0 and always stagger)
	# does not interrupt the swing; a break staggers and grants 1.6 s of immunity (npc_fighter.absorb).
	if _fighter != null and _winding > 0.0 and amount > 0 and not _fighter.absorb(float(amount), Time.get_ticks_msec() * 0.001):
		return
	if bool(_sp["poise"]) and _winding > 0.0:
		return                        # heavy beasts shrug off hits mid-swing
	if _winding > 0.0:
		Telegraph.end(self)
	_winding = 0.0
	_strike_target = null
	if _ragdoll and _ragdoll.is_down():
		_busy = maxf(_busy, 0.3)      # already on the ground
		return
	var reaction := Ragdoll.reaction(amount, from, knockback)   # stagger (hit clip) / launch / knockdown
	if reaction != "stagger" and _ragdoll \
			and _ragdoll.knock_down(knockback, hit_from, _get_up, Ragdoll.LAUNCH_LIFT if reaction == "launch" else 1.0):
		_speed = 0.0
		_busy = Ragdoll.KNOCK_TIME + 0.5
		if state == State.ATTACK:
			_end_turn(1.6)
		return
	_busy = 0.3
	_play("hit", true)
	if state == State.ATTACK and not _circling:
		_end_turn(0.8)                # hit reaction gives up the slot


## Knockdown over (ragdoll.gd moved us under the hips): no get-up clip on these
## rigs, so the physics pose blends straight back into the idle.
func _get_up() -> void:
	if not dead:
		_play("idle", true)


func _play(role: String, restart := false, rate := 1.0) -> void:
	var anim_name := String(_clips.get(role, role))
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.speed_scale = rate
	if restart or _anim.current_animation != anim_name:
		var loco := [_clips.get("walk", ""), _clips.get("run", "")]
		var blend := 0.28 if _anim.current_animation in loco and anim_name in loco else 0.15
		_anim.play(anim_name, blend)
