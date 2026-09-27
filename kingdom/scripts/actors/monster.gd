class_name CampMonster
extends CharacterBody3D
## Humanoid monster (goblins, orcs) living in a camp. Wanders its camp, turns on
## intruders who come close, and yields (kneels) when beaten instead of dying,
## unless finished off. A yielded monster can be named (Tensura-style) through
## Life.name_monster: it evolves into its greater form, takes a class and
## follows the player as a subordinate that fights the player's enemies.
## Uses close-range collision with the player and world; distant monsters keep
## low-cost terrain steering rather than participating in full crowd physics.

signal died(monster: CampMonster)

const MODELS := "res://assets/incoming/quaternius/ultimate-animated-character/glTF/"
const PLAYER_SOLID_RANGE := 16.0
const WORLD_LAYER := 1
const ENEMY_LAYER := 4
const SPECIES := {
	"goblin": {"models": ["Goblin_Male", "Goblin_Female"], "height": 1.1, "health": 32, "damage": 6,
		"walk": 1.4, "run": 5.2, "level": [1, 4], "tint": Color(1, 1, 1)},
	"orc": {"models": ["Goblin_Male"], "height": 2.05, "health": 95, "damage": 15,
		"walk": 1.3, "run": 4.6, "level": [5, 9], "tint": Color(0.62, 0.72, 0.5)},
}
const NAMES := ["Gobta", "Rigur", "Kurra", "Snag", "Brek", "Mossa", "Tuk", "Hesk", "Grom", "Varka",
	"Orrin", "Dazh", "Ruuk", "Pell", "Zagra", "Hollo", "Krith", "Ushna", "Bram", "Tessik"]
enum State { WANDER, ALERT, ATTACK, YIELD, FOLLOW }

var species := "goblin"
var home := Vector2.ZERO
var home_radius := 18.0
var level := 1
var health := 30
var max_health := 30
var dead := false
var hostile := true
var named := ""
var klass := ""
var state := State.WANDER
var team := 1

var _anim: AnimationPlayer
var _label: Label3D
var _target := Vector3.ZERO
var _think := 0.0
var _attack_cd := 0.0
var _busy := 0.0
var _speed := 0.0
var _foe: Node3D
var _actor_shape: CollisionShape3D


func _ready() -> void:
	var sp: Dictionary = SPECIES[species]
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_actor_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = maxf(0.8, float(sp["height"]) * 0.9)
	capsule.radius = clampf(float(sp["height"]) * 0.22, 0.22, 0.42)
	_actor_shape.shape = capsule
	_actor_shape.position.y = capsule.height * 0.5
	_actor_shape.disabled = true
	add_child(_actor_shape)
	var models: Array = sp["models"]
	var model: Node3D = (load(MODELS + String(models[randi() % models.size()]) + ".gltf") as PackedScene).instantiate()
	var box := Assets.visual_aabb(model)
	model.scale = Vector3.ONE * (float(sp["height"]) / maxf(box.size.y, 0.01))
	add_child(model)
	var tint: Color = sp["tint"]
	if tint != Color(1, 1, 1):
		_tint(model, tint)
	_anim = Assets.animation_player(model)
	for a in ["Idle", "Walk", "Run"]:
		if _anim and _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var lv: Array = sp["level"]
	level = randi_range(int(lv[0]), int(lv[1]))
	max_health = int(sp["health"]) + level * 4
	health = max_health
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.007
	_label.font_size = 26
	_label.outline_size = 8
	_label.position.y = float(sp["height"]) + 0.35
	add_child(_label)
	_refresh_label()
	_set_team(hostile)
	_pick_wander()


func _tint(model: Node, tint: Color) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = d.albedo_color * tint
				mi.set_surface_override_material(s, d)


func _set_team(is_hostile: bool) -> void:
	for g in ["team0", "team1", "combatant", "interactable"]:
		if is_in_group(g):
			remove_from_group(g)
	if dead:
		return
	if state == State.YIELD:
		add_to_group("interactable")
		return
	add_to_group("combatant")
	add_to_group("team1" if is_hostile else "team0")
	team = 1 if is_hostile else 0


func _refresh_label() -> void:
	var sp_name := String(species).capitalize()
	if named != "":
		_label.text = "%s · %s %s" % [named, RANaming.species_info(species).get("evolves_to", sp_name), klass.capitalize()]
		_label.modulate = Color("f5b841")
	elif state == State.YIELD:
		_label.text = "%s (Lv %d) · yielded" % [sp_name, level]
		_label.modulate = Color("9fe39f")
	else:
		_label.text = "%s  Lv %d" % [sp_name, level]
		_label.modulate = Color("ff8a7a") if hostile else Color("e0e0e0")


func prompt() -> String:
	return "Name"


func _physics_process(delta: float) -> void:
	if dead:
		return
	_think -= delta
	_attack_cd -= delta
	_busy -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _think <= 0.0:
		_think = 0.35
		_decide(player)
	var want := 0.0
	var sp: Dictionary = SPECIES[species]
	match state:
		State.WANDER:
			want = float(sp["walk"])
			if Vector2(_target.x - global_position.x, _target.z - global_position.z).length() < 1.5:
				_pick_wander()
		State.ALERT:
			want = 0.0
			if player:
				_target = player.global_position
		State.ATTACK:
			if is_instance_valid(_foe):
				_target = _foe.global_position
				var d := global_position.distance_to(_target)
				want = float(sp["run"]) if d > 1.6 else 0.0
				if d <= 1.8 and _attack_cd <= 0.0:
					_strike(_foe)
		State.FOLLOW:
			if player:
				var d2 := global_position.distance_to(player.global_position)
				_target = player.global_position + Vector3(1.6, 0, 1.6)
				want = 0.0 if d2 < 3.0 else (float(sp["run"]) if d2 > 7.0 else float(sp["walk"]) * 1.6)
		State.YIELD:
			want = 0.0
	if _busy > 0.0:
		want = 0.0
	_speed = lerpf(_speed, want, 6.0 * delta)
	_update_player_collision(player)
	var to := _target - global_position
	to.y = 0.0
	if to.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 6.0 * delta)
	if to.length() > 0.3 and _speed > 0.05:
		var step_velocity := to.normalized() * _speed
		if _near_player(player):
			velocity = step_velocity
			move_and_slide()
			global_position.y = WorldGen.height(global_position.x, global_position.z)
		else:
			var p := global_position + step_velocity * delta
			p.y = WorldGen.height(p.x, p.z)
			global_position = p
	if _busy <= 0.0 and state != State.YIELD:
		_play("Run" if _speed > 3.0 else ("Walk" if _speed > 0.3 else "Idle"))


func _decide(player: Node3D) -> void:
	if state == State.YIELD:
		return
	if state == State.FOLLOW or not hostile:
		# Subordinates defend the player: fight the nearest hostile nearby.
		_foe = _nearest("team1", 14.0)
		if _foe:
			state = State.ATTACK
		elif named != "":
			state = State.FOLLOW
		else:
			state = State.WANDER
		return
	if player == null or player.get("dead"):
		state = State.WANDER
		return
	var d := global_position.distance_to(player.global_position)
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var near_home := pp.distance_to(home) < home_radius + 22.0
	if d < 9.0 or (near_home and d < 16.0):
		state = State.ATTACK
		_foe = player
	elif d < 24.0:
		state = State.ALERT
	else:
		state = State.WANDER


func _nearest(group: String, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for n in get_tree().get_nodes_in_group(group):
		if n == self or not n is Node3D or n.get("dead"):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n
	return best


func _near_player(player: Node3D) -> bool:
	return player != null and player.global_position.distance_squared_to(global_position) < PLAYER_SOLID_RANGE * PLAYER_SOLID_RANGE


func _update_player_collision(player: Node3D) -> void:
	_actor_shape.set_deferred("disabled", not _near_player(player))


func _pick_wander() -> void:
	var ang := randf() * TAU
	var p := home + Vector2(cos(ang), sin(ang)) * randf_range(2.0, home_radius)
	_target = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _strike(foe: Node3D) -> void:
	_attack_cd = randf_range(1.1, 1.7)
	_busy = 0.55
	_play("SwordSlash" if species == "orc" or randf() < 0.5 else "Punch", true)
	var dmg := int(SPECIES[species]["damage"]) + level
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if not dead and is_instance_valid(foe) and global_position.distance_to(foe.global_position) < 2.4 and foe.has_method("take_damage"):
			foe.take_damage(dmg, self, (foe.global_position - global_position).normalized() * 2.0)
			VFX.sparks(get_parent(), foe.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.6, 0.4), 12))


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	if state == State.YIELD:
		# Striking a creature that has yielded kills it.
		_die()
		return
	health -= amount
	global_position += knockback * 0.12
	if health <= 0:
		if named == "" and hostile and randf() < 0.75:
			_yield()
		else:
			_die()
		return
	_busy = 0.3
	_play("RecieveHit", true)
	if from is Node3D:
		_foe = from
		state = State.ATTACK


func _yield() -> void:
	health = maxi(1, max_health / 5)
	state = State.YIELD
	hostile = false
	_set_team(false)
	_play("SitDown", true)
	_refresh_label()
	Game.say("The %s drops its weapon and kneels." % species)


func _die() -> void:
	dead = true
	_set_team(false)
	_play("Death", true)
	died.emit(self)
	var t := create_tween()
	t.tween_interval(6.0)
	t.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.5)
	t.tween_callback(queue_free)


## Called by Life after a successful naming.
func become_named(given: String, chosen_class: String) -> void:
	named = given
	klass = chosen_class
	state = State.FOLLOW
	hostile = false
	health = max_health
	scale *= 1.12
	_set_team(false)
	_play("StandUp", true)
	_refresh_label()
	VFX.burst(get_parent(), global_position, "qi", 1.2)
	VFX.aura(self, Color(1.0, 0.85, 0.4), 1.4)


func random_name() -> String:
	return NAMES[randi() % NAMES.size()]


func _play(anim_name: String, restart := false) -> void:
	if _anim and _anim.has_animation(anim_name) and (restart or _anim.current_animation != anim_name):
		_anim.play(anim_name, 0.15)
