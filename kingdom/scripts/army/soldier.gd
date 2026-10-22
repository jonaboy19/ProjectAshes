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
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const Telegraph := preload("res://scripts/combat/telegraph.gd")
const CombatStats := preload("res://scripts/combat/combat_stats.gd")
const NpcCaster := preload("res://scripts/combat/npc_caster.gd")
const BendingLibrary := preload("res://scripts/actors/bending_library.gd")
const EffectSet := preload("res://scripts/abilities/effect_set.gd")
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

## Set before add_child (squad.add_soldiers does): an NpcCaster id from data/powers/npc_casters.json makes this soldier
## a bandit mage, sect disciple or knight captain. The same AbilityRunner as the player's casts, costs off. Active
## casters are capped world-wide (NpcCaster.MAX_ACTIVE); over the cap the soldier stays a plain fighter.
var caster_id := ""
var _caster: RefCounted
var _caster_think_t := 0.0
var _kite_t := 0.0
var _foe_fx: EffectSet
var _foe_fx_for: Node


static func create(team_id: int, look: String, file: String, keep: Array[String]) -> Soldier:
	var s := Soldier.new()
	s.team = team_id
	s._look = look
	s._file = file
	s._keep = keep
	return s


func _ready() -> void:
	# Distant troops remain cheap; only nearby troops participate in physics.
	if caster_id != "" and NpcCaster.has(caster_id) and NpcCaster.try_acquire():
		_caster = NpcCaster.make(caster_id, randi())
		_fighter = _caster.fighter
		_caster.runner.executed.connect(_on_cast_executed)
		_caster.runner.chant_started.connect(_on_chant_started)
		_caster.runner.started.connect(_on_cast_started)
		_caster.runner.interrupted.connect(_on_cast_interrupted)
		add_to_group("caster")
	else:
		caster_id = ""
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
	if _caster != null:
		_caster_tick(delta)

	var goal := slot_target
	var engaging: bool = combat_target != null and is_instance_valid(combat_target) and not combat_target.get("dead")
	if engaging:
		goal = combat_target.global_position
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var desired := Vector3.ZERO
	var casting: bool = _caster != null and _caster.is_casting()
	if casting:
		_face(to_goal)                       # planted: chanting or winding up
	elif engaging and dist <= ATTACK_RANGE:
		_face(to_goal)
		if _attack_cooldown <= 0.0 and _busy <= 0.0:
			_attack()
	elif engaging and _kite_t > 0.0 and dist > 0.4:
		desired = -to_goal / dist * WALK * 1.2        # a mage backs off to keep her range
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
			"blocking" if _is_blocking(victim) else "idle")
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
	# P9: rate = clip contact time / hit_delay lands the blade on the damage frame; a soldier standing still gets the full-body clip.
	var swing_clip := "Sword_Light_%d" % (1 + randi() % 3)
	var clip_hit := CombatMarkers.time_s(swing_clip, "hit", 1.0)
	_animator.play_attack(swing_clip, clampf((clip_hit if clip_hit > 0.0 else 0.3) / maxf(hit_delay, 0.1), 0.6, 1.6), _velocity.length() < 0.3)
	var move := _cur_move
	Telegraph.begin(self, move, move.reach if move != null else ATTACK_RANGE, hit_delay)
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
	if _caster != null and amount > 0:
		amount = int(_caster.deal(float(amount))["amount"])      # wards and absorbs soak a blow before it lands (raw blow units, then army scaling)
		if amount <= 0:
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
	if _caster != null and health > 0:
		var poise := float(amount)
		if from != null and from.has_method("attack_info"):
			poise = float((from.call("attack_info") as Dictionary).get("poise_damage", poise))
		if _caster.on_blow(poise, float(amount), Time.get_ticks_msec() * 0.001):
			_busy = maxf(_busy, 0.5)                                # a stagger breaks the chant
	if health <= 0:
		_die()
	elif Ragdoll.reaction(amount, from, knockback) != "stagger" and _ragdoll \
			and _ragdoll.knock_down(knockback, _hit_from, _get_up,
				Ragdoll.LAUNCH_LIFT if Ragdoll.reaction(amount, from, knockback) == "launch" else 1.0):
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
	_release_caster()
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


func _exit_tree() -> void:
	_release_caster()


func _release_caster() -> void:
	if _caster != null:
		_caster = null
		NpcCaster.release()
		remove_from_group("caster")


# --- casting (NpcCaster through the shared AbilityRunner) ------------------------------------

func _is_blocking(victim: Node) -> bool:
	var b: Variant = victim.get("blocking")        # soldiers have no such property: only the player blocks
	return b is bool and b


func _caster_tick(delta: float) -> void:
	_caster.update(delta)
	_kite_t = maxf(0.0, _kite_t - delta)
	if _foe_fx != null:
		_tick_foe_fx(delta)
	_caster_think_t -= delta
	var victim := combat_target
	if _caster_think_t > 0.0 or victim == null or not is_instance_valid(victim) or bool(victim.get("dead")) or _busy > 0.0 or _caster.is_casting():
		return
	_caster_think_t = NpcCaster.THINK
	var dist := global_position.distance_to(victim.global_position)
	var d: Dictionary = _caster.think(NpcCaster.THINK, {"dist": dist, "target_state": "blocking" if _is_blocking(victim) else "idle",
		"has_token": true, "own_hp_frac": float(health) / maxf(float(max_health), 1.0), "sees_target": true,
		"strike_range": ATTACK_RANGE})
	if String(d["ability"]) != "":
		var r: Dictionary = _caster.cast(String(d["ability"]), victim)
		if bool(r.get("ok", false)):
			_attack_cooldown = maxf(_attack_cooldown, 0.8)
			_face(victim.global_position - global_position)
			# A bending clip plays from the runner's `started` signal (_on_cast_started, windup start).
			var chant := String(r.get("phase", "")) == "chant"
			if chant or not BendingLibrary.is_bending(AbilityLib.get_def(String(d["ability"]))):
				_animator.play_upper("Spellcast_Raise" if chant else "Spellcast_Shoot", 1.0)
	elif String(d["intent"]) == "kite":
		_kite_t = 0.6


## Charged casts get a ground ring in the ability's element until the cast lands or breaks.
func _on_chant_started(id: String, info: Dictionary) -> void:
	_telegraph_cast(id, float(info.get("time", 1.0)))


func _on_cast_started(id: String, ab: Dictionary) -> void:
	if not dead and BendingLibrary.is_bending(ab):
		BendingLibrary.play_cast(_animator, ab)       # CMU bending clip through the upper / full OneShot slot
	if float(ab.get("windup", 0.0)) >= 0.4:
		_telegraph_cast(id, float(ab["windup"]))


func _on_cast_interrupted(_id: String, _reason: String) -> void:
	Telegraph.end(self)


func _telegraph_cast(id: String, seconds: float) -> void:
	if dead or _caster == null:
		return
	var def: Dictionary = AbilityLib.get_def(id)
	var tg: Dictionary = def.get("targeting", {})
	var radius := maxf(float(tg.get("radius", 0.0)), 1.6)
	Telegraph.begin_cast(self, String(def.get("element", "qi")), radius, seconds)


func _on_cast_executed(_id: String, ab: Dictionary, cast: Dictionary) -> void:
	if dead or _caster == null:
		return
	var own: Dictionary = _caster.apply(ab, 0, _caster.effects(), "self")
	health = mini(max_health, health + int(own["heal"]))
	var victim: Node3D = cast.get("target") as Node3D
	var tg: Dictionary = ab["targeting"]
	var kind := String(tg["kind"])
	if victim == null or not is_instance_valid(victim) or bool(victim.get("dead")) or kind in ["self", "buff", "utility", "command"]:
		return
	# Damage scale like the melee blows: row dmg_mult and the squad unit scaling (damage / BASE_DAMAGE).
	var dmg := maxi(int(round(float(cast["damage"]) * float(_caster.row.get("dmg_mult", 1.0)) * float(damage) / BASE_DAMAGE)), 1) if int(cast["damage"]) > 0 else 0
	if not BendingLibrary.is_bending(ab):       # a bending clip already plays from the cast start
		_animator.play_upper("Spellcast_Shoot" if kind in ["projectile", "target_aoe", "aoe", "chain"] else "1H_Melee_Attack_Chop", 1.2)
	var dist := global_position.distance_to(victim.global_position)
	match kind:
		"projectile":
			var t := dist / maxf(float(tg["speed"]), 1.0)
			get_tree().create_timer(t).timeout.connect(func() -> void:
				if not dead and is_instance_valid(victim) and not bool(victim.get("dead")) \
						and global_position.distance_to(victim.global_position) <= float(tg["range"]) + 2.0:
					_spell_hit(victim, dmg, ab))
		"dash":
			var dir := victim.global_position - global_position
			dir.y = 0.0
			if dist <= float(tg["range"]) + 1.0 and dir.length() > 0.1:
				_impulse = dir.normalized() * sqrt(2.0 * 12.0 * minf(dist, float(tg["range"])))
			get_tree().create_timer(0.25).timeout.connect(func() -> void:
				if not dead and is_instance_valid(victim) and not bool(victim.get("dead")) \
						and global_position.distance_to(victim.global_position) <= 3.4:
					_spell_hit(victim, dmg, ab))
		_:
			var reach := float(tg["radius"]) if kind == "aoe" else float(tg["range"])
			if dist <= maxf(reach, 1.0) + 0.6:
				_spell_hit(victim, dmg, ab)


func _spell_hit(victim: Node3D, dmg: int, ab: Dictionary) -> void:
	var push := victim.global_position - global_position
	push.y = 0.0
	push = push.normalized() * float((ab["targeting"] as Dictionary)["knockback"]) if push.length() > 0.05 else Vector3.ZERO
	if dmg > 0:
		victim.take_damage(dmg, self, push)
	var el := String(ab["element"])
	if is_inside_tree():
		VFX.burst(get_parent(), victim.global_position, el if VFX.ELEMENTS.has(el) else "qi", 0.6)
	if (ab["effects"] as Array).is_empty():
		return
	if _foe_fx == null or _foe_fx_for != victim:
		_foe_fx = EffectSet.new()
		_foe_fx_for = victim
	var res: Dictionary = _caster.apply(ab, dmg, _foe_fx, "enemy")
	if victim.has_method("apply_status"):
		for st: Dictionary in res["statuses"]:
			victim.call("apply_status", String(st["status"]), float(st["duration"]))


func _tick_foe_fx(delta: float) -> void:
	for ev: Dictionary in _foe_fx.tick(delta):
		if String(ev["kind"]) == "dot" and is_instance_valid(_foe_fx_for) and not bool(_foe_fx_for.get("dead")):
			_foe_fx_for.take_damage(int(ev["amount"]), self)
	if _foe_fx.active.is_empty():
		_foe_fx = null
		_foe_fx_for = null


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
