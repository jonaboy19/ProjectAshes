class_name Soldier
extends Node3D
## One soldier. Deliberately not a physics body: it follows the terrain height
## function and steers with simple separation, so a hundred of them cost little.
## Beyond LOD_DISTANCE from the camera it swaps its skinned model for a sprite.

signal died(soldier: Soldier)

const LOD_DISTANCE := 45.0
const WALK := 3.6
const RUN := 5.8
const ATTACK_RANGE := 1.7
const ENGAGE_RANGE := 9.0

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
var _attack_cooldown := 0.0
var _busy := 0.0
var _retarget := 0.0
var _velocity := Vector3.ZERO


static func create(team_id: int, look: String, file: String, keep: Array[String]) -> Soldier:
	var s := Soldier.new()
	s.team = team_id
	s._look = look
	s._file = file
	s._keep = keep
	return s


func _ready() -> void:
	add_to_group("team%d" % team)
	add_to_group("combatant")
	_model = Assets.character(_file, 1.75, _keep)
	add_child(_model)
	_anim = Assets.animation_player(_model)
	_animator = CharacterAnimator.new(_model, RUN)
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
		var speed := RUN if dist > 6.0 or engaging else WALK
		desired = to_goal / dist * minf(speed, dist * 3.0)
	desired += _separation() * 2.5
	_velocity = _velocity.lerp(desired, 8.0 * delta)
	if _busy > 0.0:
		_velocity *= 0.4
	var p := global_position + (_velocity + _impulse) * delta
	_impulse = _impulse.move_toward(Vector3.ZERO, 25.0 * delta)
	p.y = WorldGen.height(p.x, p.z)
	global_position = p

	var planar := Vector2(_velocity.x, _velocity.z).length()
	if _busy <= 0.0:
		if planar > 0.5:
			_face(_velocity)
		elif not engaging:
			_face(squad.facing if squad else Vector3.FORWARD)
	if _model.visible:
		_animator.update(delta, planar)
		_animator.set_blocking(_guard > 0.0)


func _pick_target() -> void:
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


func _attack() -> void:
	_attack_cooldown = randf_range(1.1, 1.5)
	_busy = 0.5
	_animator.play_upper(["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal"][randi() % 3], 1.4)
	var victim := combat_target
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if not dead and is_instance_valid(victim) and not victim.get("dead") \
				and global_position.distance_to(victim.global_position) < ATTACK_RANGE + 0.5:
			victim.take_damage(damage, self))


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	var from_front := true
	if from is Node3D:
		var to := (from as Node3D).global_position - global_position
		from_front = global_transform.basis.z.dot(Vector3(to.x, 0, to.z).normalized()) > 0.3
	if from_front and randf() < block_chance and _busy <= 0.0:
		_guard = 0.6
		_impulse = knockback * 0.4
		_animator.play_upper("Block_Hit", 1.5)
		return
	health -= amount
	_impulse = knockback
	if health <= 0:
		_die()
	else:
		_busy = 0.35
		if knockback.length() > 4.0:
			_animator.play_full("Hit_B", 1.3)
		else:
			_animator.play_upper("Hit_A", 1.5)


func _die() -> void:
	dead = true
	remove_from_group("team%d" % team)
	remove_from_group("combatant")
	_animator.play_terminal("Death_A" if randf() < 0.5 else "Death_B")
	died.emit(self)
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.6)
	tween.tween_callback(queue_free)


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
