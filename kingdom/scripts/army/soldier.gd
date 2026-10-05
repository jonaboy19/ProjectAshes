class_name Soldier
extends CharacterBody3D
## One soldier. At a distance it follows terrain with inexpensive steering;
## close to the player its capsule becomes solid and movement uses physics.
## Beyond LOD_DISTANCE from the camera it swaps its skinned model for a sprite.
## Deaths go physical (ragdoll.gd, capped world-wide, Death01 as the fallback);
## a heavy hit (knockback >= 6 or a parried swing) knocks it down for a second,
## then the locomotion tree blends back in (the UAL set has no get-up clip).

signal died(soldier: Soldier)

const LOD_DISTANCE := 45.0
const WALK := 2.4
const RUN := 5.8
const ATTACK_RANGE := 1.7
const ENGAGE_RANGE := 9.0
const PLAYER_SOLID_RANGE := 16.0
const WORLD_LAYER := 1
const SOLDIER_LAYER := 4
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const Fighter := preload("res://scripts/combat/npc_fighter.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")
## Pre-table soldier numbers. Army fights keep them: the table's HP/damage apply to duels with the player;
## blows between NPCs are multiplied by max_health / BASE_HP, so a 170-200 HP body loses the SAME FRACTION of its
## health per blow as the old 40 HP one (a battle lasts as long as before). The factor was inverted once
## (BASE_HP / max_health) which made army fights ~20x longer; tests/test_combat_stats.gd pins the direction.
const BASE_HP := 40.0
const BASE_DAMAGE := 8.0

var team := 0
var squad: Squad
var max_health := 40
var health := 40
var damage := 8
var slot_target := Vector3.ZERO
var combat_target: Node3D = null
var dead := false

var _look := ""
var _file := ""
var _keep: Array[String] = []
var _model: Node3D
var _anim: AnimationPlayer
var _animator: CharacterAnimator
var _impulse := Vector3.ZERO
var _guard := 0.0
## Chance to catch a hit on the shield.
var block_chance := 0.3
var _sprite: MeshInstance3D
var _actor_shape: CollisionShape3D
var _attack_cooldown := 0.0
var _busy := 0.0
var _retarget := 0.0
var _velocity := Vector3.ZERO
var _step_distance := 0.0
var _ragdoll: Node
var _hit_from := Vector3.INF
## Humanoid fighter model: bandits (team 1) and guards/militia (team 0) pick moves from CombatMoves and
## guard on a rank-based chance (npc_fighter.gd). Squad stances still scale block_chance.
var _fighter: RefCounted
var _cur_move: Resource
var _stats := {}
var _npc_scale := 1.0           # damage multiplier for non-player sources (max_health / BASE_HP, >= 1)


static func create(team_id: int, look: String, file: String, keep: Array[String]) -> Soldier:
	var s := Soldier.new()
	s.team = team_id
	s._look = look
	s._file = file
	s._keep = keep
	return s


func _ready() -> void:
	# Distant troops remain cheap; only nearby troops participate in physics.
	_fighter = Fighter.make("bandit" if team == 1 else "guard", randi())
	block_chance = _fighter.react_chance()
	var pl := CombatStats.player_level()
	_stats = _fighter.apply_level(pl, pl)          # soldiers are "matching level": the table value
	max_health = int(_stats["hp"])
	health = max_health
	_npc_scale = maxf(float(max_health) / BASE_HP, 1.0)
	collision_layer = SOLDIER_LAYER
	collision_mask = WORLD_LAYER
	_actor_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	_actor_shape.shape = capsule
	_actor_shape.position.y = 0.825
	_actor_shape.disabled = true
	add_child(_actor_shape)
	add_to_group("team%d" % team)
	add_to_group("combatant")
	_model = Assets.character(_file, 1.75, _keep)
	add_child(_model)
	_anim = Assets.animation_player(_model)
	_animator = CharacterAnimator.new(_model, RUN, WALK)
	_ragdoll = Ragdoll.attach(self, _model, [_animator.tree, _anim])
	_sprite = MeshInstance3D.new()
	_sprite.mesh = ImpostorBaker.quad()
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var baker: ImpostorBaker = get_tree().get_first_node_in_group("impostor_baker")
	if baker and baker.materials.has(_look):
		_sprite.material_override = baker.materials[_look]
	_sprite.visible = false
	add_child(_sprite)
	_retarget = randf() * 0.4


func _physics_process(delta: float) -> void:
	if dead:
		return
	_attack_cooldown -= delta
	_busy -= delta
	_guard -= delta
	_retarget -= delta
	_update_lod()
	_update_player_collision()
	if _retarget <= 0.0:
		_retarget = 0.4
		_pick_target()

	var goal := slot_target
	var engaging: bool = combat_target != null and is_instance_valid(combat_target) and not combat_target.get("dead")
	if engaging:
		goal = combat_target.global_position
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var desired := Vector3.ZERO
	if engaging and dist <= ATTACK_RANGE:
		_face(to_goal)
		if _attack_cooldown <= 0.0 and _busy <= 0.0:
			_attack()
	elif dist > 0.4:
		var speed := (RUN if dist > 6.0 or engaging else WALK) * (squad.speed_mult() if squad else 1.0)
		desired = to_goal / dist * minf(speed, dist * 3.0)
	desired += _separation() * 2.5
	_velocity = _velocity.lerp(desired, 8.0 * delta)
	if _busy > 0.0:
		_velocity *= 0.4
	var step_velocity := _velocity + _impulse
	var p := global_position + step_velocity * delta
	_impulse = _impulse.move_toward(Vector3.ZERO, 25.0 * delta)
	p.y = WorldGen.height(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var physics_close := player != null and player.global_position.distance_squared_to(global_position) < PLAYER_SOLID_RANGE * PLAYER_SOLID_RANGE
	if physics_close:
		global_position.y = p.y
		velocity = step_velocity
		move_and_slide()
		# Ground height is generated by WorldGen; retain its exact surface after
		# resolving horizontal contacts with buildings and the player.
		global_position.y = WorldGen.height(global_position.x, global_position.z)
		_velocity.x = velocity.x
		_velocity.z = velocity.z
	else:
		global_position = p

	var planar := Vector2(_velocity.x, _velocity.z).length()
	if _busy <= 0.0:
		if planar > 0.5:
			_face(_velocity)
		elif not engaging:
			_face(squad.facing_for(self) if squad else Vector3.FORWARD)
	if _model.visible:
		_animator.update(delta, planar)
		_animator.set_blocking(_guard > 0.0)
		if planar > 0.5:
			_step_distance += planar * delta
			var gait := clampf((planar - WALK) / (RUN - WALK), 0.0, 1.0)
			var authored_stride := lerpf(WALK / 1.5, RUN / (2.0 * 24.0 / 22.0), gait)
			var gait_speed := lerpf(WALK, RUN, gait)
			var stride := authored_stride * planar / gait_speed
			if _step_distance >= stride:
				_step_distance = fmod(_step_distance, stride)
				var listener_near := Audio.listener == null or Audio.listener.global_position.distance_to(global_position) < 35.0
				if listener_near:
					Audio.sfx("step_" + WorldGen.footstep_surface(global_position.x, global_position.z), global_position, -13.0)
		else:
			_step_distance = 0.0


func _pick_target() -> void:
	if squad and not squad.soldiers.is_empty():
		combat_target = null if squad.is_routed() else squad.target_for(self)
		return
	var order := squad.order if squad else Squad.Order.HOLD
	var reach := INF if order == Squad.Order.CHARGE else ENGAGE_RANGE
	var best: Node3D = null
	var best_d := reach
	for enemy in get_tree().get_nodes_in_group("team%d" % (1 - team)):
		if enemy.get("dead"):
			continue
		var d := global_position.distance_to((enemy as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = enemy
	combat_target = best


func _separation() -> Vector3:
	var push := Vector3.ZERO
	if squad == null:
		return push
	for other in squad.soldiers:
		if other == self:
			continue
		var d := global_position - other.global_position
		d.y = 0.0
		var len := d.length()
		if len < 1.2 and len > 0.001:
			push += d / len * (1.2 - len)
	return push


func _update_player_collision() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var should_disable := player == null or player.global_position.distance_squared_to(global_position) > PLAYER_SOLID_RANGE * PLAYER_SOLID_RANGE
	if _actor_shape.disabled != should_disable:
		_actor_shape.set_deferred("disabled", should_disable)


func _attack() -> void:
	var victim := combat_target
	var vs_player := victim != null and victim.is_in_group("player")
	_attack_cooldown = randf_range(1.1, 1.5) * (float(_stats.get("cdm", 1.0)) if vs_player else 1.0)
	# Defaults are the old fixed swing: contact 0.3 s in, busy 0.5 s, `damage` per hit.
	var hit_delay := 0.3
	var busy := 0.5
	var dmg := damage
	_cur_move = null
	if _fighter != null and victim != null:
		_cur_move = _fighter.choose_move(global_position.distance_to(victim.global_position),
			"blocking" if bool(victim.get("blocking")) else "idle")
		if _cur_move != null:
			var ref: Resource = _fighter.default_move()
			var k: float = _cur_move.windup / ref.windup
			hit_delay = 0.3 * k
			busy = 0.5 * k
			dmg = maxi(int(round(float(damage) * _cur_move.damage / ref.damage)), 1)
			if vs_player:
				# Duel numbers: table damage multiplier, with squad unit scaling kept (damage / 8).
				dmg = maxi(int(round(float(_cur_move.damage) * float(_stats.get("dmg", 1.0)) * float(damage) / BASE_DAMAGE)), 1)
	_busy = busy
	_animator.play_upper(["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal"][randi() % 3], 1.4 / maxf(hit_delay / 0.3, 0.5))
	var move := _cur_move
	get_tree().create_timer(hit_delay).timeout.connect(func() -> void:
		if not dead and is_instance_valid(victim) and not victim.get("dead") \
				and global_position.distance_to(victim.global_position) < ATTACK_RANGE + 0.5:
			victim.take_damage(dmg, self)
			Audio.sfx("clash" if randf() < 0.5 else "hit", global_position, -6.0)
		if _cur_move == move:
			_cur_move = null)


## Describes the blow in flight for the defender's HitResolver call.
func attack_info() -> Dictionary:
	if _cur_move == null:
		return {}
	return {"poise_damage": _cur_move.poise_damage, "lane": _cur_move.lane, "parryable": _cur_move.parryable,
		"unblockable": _cur_move.unblockable}


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	if _npc_scale > 1.0 and amount > 0 and not (from != null and from.is_in_group("player")):
		amount = maxi(int(round(float(amount) * _npc_scale)), 1)     # army fights stay as long as before
	var from_front := true
	_hit_from = (from as Node3D).global_position if from is Node3D else Vector3.INF
	if _ragdoll and _ragdoll.is_down():
		if squad:
			amount = roundi(amount * squad.incoming_mult(self, from))
		health -= amount              # on the ground: no block, no flinch
		if health <= 0:
			_die()
		return
	if from is Node3D:
		var to := (from as Node3D).global_position - global_position
		from_front = global_transform.basis.z.dot(Vector3(to.x, 0, to.z).normalized()) > 0.3
	if from_front and _busy <= 0.0 and not _fighter.consider_reaction(Time.get_ticks_msec() * 0.001, block_chance).is_empty():
		_guard = 0.6
		_impulse = knockback * 0.4
		_animator.play_upper("Block_Hit", 1.5)
		return
	if squad:
		amount = roundi(amount * squad.incoming_mult(self, from))
	health -= amount
	_impulse = knockback
	if health <= 0:
		_die()
	elif Ragdoll.is_heavy(amount, from, knockback) and _ragdoll \
			and _ragdoll.knock_down(knockback, _hit_from, _get_up):
		_impulse = Vector3.ZERO
		_velocity = Vector3.ZERO
		_busy = Ragdoll.KNOCK_TIME + 0.4
	else:
		_busy = 0.35
		if knockback.length() > 4.0:
			_animator.play_full("Hit_Heavy_" + _hit_side(from), 1.0)
		else:
			_animator.play_upper("Hit_Light_" + _hit_side(from), 1.0)


func _hit_side(from: Node) -> String:
	if not (from is Node3D):
		return "Front"
	var to := (from as Node3D).global_position - global_position
	to.y = 0.0
	var forward := global_transform.basis.z.normalized()
	var front := forward.dot(to)
	var right := Vector3.UP.cross(forward).dot(to)
	if absf(front) >= absf(right):
		return "Front" if front > 0.0 else "Back"
	return "Right" if right > 0.0 else "Left"


func _die() -> void:
	dead = true
	remove_from_group("team%d" % team)
	remove_from_group("combatant")
	_actor_shape.set_deferred("disabled", true)
	if not (_ragdoll and _ragdoll.die(_impulse, _hit_from)):
		_animator.play_terminal("Death01")
	died.emit(self)
	var tween := create_tween()
	tween.tween_interval(5.0)
	# Squash the model, not the body: Jolt rejects non-uniform body scale.
	tween.tween_property(_model, "scale", _model.scale * Vector3(1, 0.01, 1), 0.6)
	tween.tween_callback(queue_free)


## Knockdown over (ragdoll.gd moved us under the hips and re-enabled the tree).
func _get_up() -> void:
	_animator.stop_full()
	_animator.stop_upper()


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.25)




func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var far := cam.global_position.distance_to(global_position) > LOD_DISTANCE
	if far == _sprite.visible:
		return
	_sprite.visible = far
	_model.visible = not far
	_animator.set_active(not far)
