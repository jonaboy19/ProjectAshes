class_name CampMonster
extends CharacterBody3D
## Humanoid monster (goblins, orcs, the odd troll) living in a camp. Wanders its
## camp, turns on intruders who come close, and yields (kneels) when beaten
## instead of dying, unless finished off. A yielded monster can be named
## (Tensura-style) through Life.name_monster: it evolves into its greater form,
## takes a class and follows the player as a subordinate that fights the
## player's enemies.
## Uses close-range collision with the player and world; distant monsters keep
## low-cost terrain steering rather than participating in full crowd physics.
##
## A whole warren turns on an intruder together, but only a few hold an attack
## token at once (creature_attack_tokens.gd): the rest circle or hold at a ring
## and take turns. Each swing has a wind-up (stop, a "!" over the head, the
## attack clip slowed so contact lands at `windup`) and only hurts if the target
## is still in reach, in front and not behind a wall at the contact frame.
## Models: Meshy goblin / orc / troll (creature_models.gd); the yield kneel and
## stand-up are cut from the orc's charged-chop clip.
## Deaths go physical (ragdoll.gd, capped world-wide) and fall back to the death
## clip; a heavy hit (knockback >= 6 or a parried swing) knocks a living monster
## down for a second, then it gets up through the stand-up clip.

signal died(monster: CampMonster)

const Models := preload("res://scripts/actors/creature_models.gd")
const Tokens := preload("res://scripts/actors/creature_attack_tokens.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const PLAYER_SOLID_RANGE := 16.0
const WORLD_LAYER := 1
const ENEMY_LAYER := 4
## Player walks at 2.4 m/s and runs at 6.5 m/s (player.gd), so "run" stays below it.
## windup: seconds from swing start to contact; recover: after contact; strike:
## distance at which a token holder starts its swing; reach: contact range at the
## contact frame; ring: circling distance while waiting for a turn; poise: hits
## don't interrupt its wind-up.
const SPECIES := {
	"goblin": {"model": "goblin", "fallback": "goblin_uac", "height": 1.1, "health": 32, "damage": 6,
		"walk": 0.7, "run": 2.6, "level": [1, 4], "tint": Color(1, 1, 1), "windup": 0.5, "recover": 0.45,
		"strike": 1.6, "reach": 2.2, "ring": 4.5, "cooldown": [1.4, 2.0], "knock": 2.0, "poise": false,
		"voice": ""},
	"orc": {"model": "orc", "fallback": "goblin_uac", "height": 2.05, "health": 95, "damage": 15,
		"walk": 1.3, "run": 3.8, "level": [5, 9], "tint": Color(0.62, 0.72, 0.5), "windup": 0.85,
		"recover": 0.6, "strike": 2.0, "reach": 2.6, "ring": 5.5, "cooldown": [2.0, 2.8], "knock": 3.0,
		"poise": false, "voice": "orc_roar"},
	"troll": {"model": "troll", "fallback": "", "height": 3.0, "health": 220, "damage": 22,
		"walk": 1.2, "run": 2.8, "level": [10, 12], "tint": Color(1, 1, 1), "windup": 1.1, "recover": 0.8,
		"strike": 2.6, "reach": 3.2, "ring": 7.0, "cooldown": [2.6, 3.4], "knock": 6.0, "poise": true,
		"voice": "bear_growl"},
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

var _kind := ""
var _clips := {}
var _anim: AnimationPlayer
var _label: Label3D
var _target := Vector3.ZERO
var _think := 0.0
var _attack_cd := 0.0
var _busy := 0.0
var _speed := 0.0
var _foe: Node3D
var _actor_shape: CollisionShape3D
var _walk_clip_speed := 0.65
var _run_clip_speed := 1.7
var _impact_time := 0.3
var _winding := 0.0
var _strike_target: Node3D
var _turn_rest := 0.0
var _turn_time := 0.0
var _strikes_left := 1
var _circling := false
var _orbit := 0.0
var _orbit_dir := 1.0
var _orbit_pace := 1.0
var _orbit_flip := 0.0
var _was_yielded := false
var _ragdoll: Node
var _model: Node3D
var _hit_push := Vector3.ZERO
var _hit_from := Vector3.INF


func _ready() -> void:
	var sp: Dictionary = SPECIES[species]
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER
	floor_snap_length = 0.25
	safe_margin = 0.03
	_actor_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = maxf(0.8, float(sp["height"]) * 0.9)
	capsule.radius = clampf(float(sp["height"]) * 0.22, 0.22, 0.6)
	_actor_shape.shape = capsule
	_actor_shape.position.y = capsule.height * 0.5
	_actor_shape.disabled = true
	add_child(_actor_shape)
	for k: String in [String(sp["model"]), String(sp["fallback"])]:
		if k != "" and Models.has(k):
			_kind = k
			break
	if _kind == "":
		queue_free()
		return
	var model := Models.instance(_kind)
	if Models.info(_kind).has("fit_height"):
		# Fallback model: scale the shared goblin body to this species.
		model.scale *= float(sp["height"]) / float(Models.info(_kind)["fit_height"])
	add_child(model)
	_model = model
	var tint: Color = sp["tint"]
	if tint != Color(1, 1, 1) and _kind != String(sp["model"]):
		_tint(model, tint)    # only the stand-in body needs recolouring
	_anim = Assets.animation_player(model)
	_ragdoll = Ragdoll.attach(self, model, [_anim])
	var info := Models.info(_kind)
	_clips = Models.clips(_kind)
	var size_ratio := float(sp["height"]) / float(info["fit_height"]) if info.has("fit_height") else 1.0
	_walk_clip_speed = float(info["walk"]) * size_ratio
	_run_clip_speed = float(info["run"]) * size_ratio
	_impact_time = float(info["impact"])
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
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_strikes_left = randi_range(1, 2)
	_refresh_label()
	_set_team(hostile)
	_pick_wander()


func _exit_tree() -> void:
	Tokens.release(self)


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
	_turn_rest -= delta
	_orbit_flip -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _winding > 0.0:
		_winding -= delta
		if is_instance_valid(_strike_target) and _winding > float(SPECIES[species]["windup"]) * 0.4:
			_face(_strike_target.global_position, delta)   # tracks early, then commits
		if _winding <= 0.0:
			_impact()
	if _was_yielded and state != State.YIELD:
		_was_yielded = false          # let go or named: get up before moving off
		if _play("stand_up", true, 1.0, 0.3):
			_busy = maxf(_busy, 1.0)
	if _think <= 0.0:
		_think = 0.35
		_decide(player)
	var want := 0.0
	var face_foe := false
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
				want = _attack_move(_foe, delta)
				face_foe = _circling
		State.FOLLOW:
			if player:
				var d2 := global_position.distance_to(player.global_position)
				_target = player.global_position + Vector3(1.6, 0, 1.6)
				want = 0.0 if d2 < 3.0 else (float(sp["run"]) if d2 > 7.0 else float(sp["walk"]) * 1.6)
		State.YIELD:
			want = 0.0
	if _busy > 0.0 or _winding > 0.0:
		want = 0.0
	_speed = lerpf(_speed, want, 6.0 * delta)
	_update_player_collision(player)
	var to := _target - global_position
	to.y = 0.0
	if _winding <= 0.0 and state != State.YIELD:
		if face_foe and is_instance_valid(_foe):
			_face(_foe.global_position, delta)
		elif to.length() > 0.3:
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
	if _busy <= 0.0 and _winding <= 0.0 and state != State.YIELD:
		var running := _speed > _walk_clip_speed * 1.8 and _run_clip_speed > _walk_clip_speed * 1.2
		var gait := "run" if running else ("walk" if _speed > 0.2 else "idle")
		var clip_speed := _run_clip_speed if running else _walk_clip_speed
		_play(gait, false, 1.0 if gait == "idle" else clampf(_speed / clip_speed, 0.6, 1.9))


## Movement while fighting: token holders close in and swing, the rest circle
## (or hold still for a moment) on a ring around the foe, facing it.
func _attack_move(foe: Node3D, delta: float) -> float:
	var sp: Dictionary = SPECIES[species]
	var d := global_position.distance_to(foe.global_position)
	if Tokens.holds(self, foe):
		_circling = false
		_turn_time += delta
		_target = foe.global_position
		if _turn_time > Tokens.HOLD_TIME - 0.5 and _winding <= 0.0 and _busy <= 0.0:
			_end_turn(1.0)
		if d <= float(sp["strike"]) and _attack_cd <= 0.0 and _busy <= 0.0 and _winding <= 0.0 \
				and Tokens.try_strike(foe):
			_strike(foe)
		return float(sp["run"]) if d > float(sp["strike"]) * 0.9 else 0.0
	if not _circling:
		_circling = true
		var from := global_position - foe.global_position
		_orbit = atan2(from.z, from.x)
	if _orbit_flip <= 0.0:
		_orbit_flip = randf_range(2.0, 4.5)
		_orbit_pace = 0.0 if randf() < 0.35 else 1.0          # sometimes just hold and watch
		if randf() < 0.35:
			_orbit_dir = -_orbit_dir
	var ring := float(sp["ring"])
	_orbit += _orbit_dir * _orbit_pace * (float(sp["walk"]) * 1.2 / ring) * delta
	_target = foe.global_position + Vector3(cos(_orbit), 0.0, sin(_orbit)) * ring
	var gap := Vector2(_target.x - global_position.x, _target.z - global_position.z).length()
	if gap < 0.6:
		return 0.0
	# Back off to the ring briskly; drift along it at a walk.
	return float(sp["run"]) * 0.8 if gap > 1.5 else float(sp["walk"]) * 1.3


func _decide(player: Node3D) -> void:
	if state == State.YIELD:
		return
	var prev_foe := _foe
	if state == State.FOLLOW or not hostile:
		# Subordinates defend the player: fight the nearest hostile nearby.
		_foe = _nearest("team1", 14.0)
		if _foe:
			state = State.ATTACK
		elif named != "":
			state = State.FOLLOW
		else:
			state = State.WANDER
	elif player == null or player.get("dead"):
		state = State.WANDER
		_foe = null
	else:
		var d := global_position.distance_to(player.global_position)
		var pp := Vector2(player.global_position.x, player.global_position.z)
		var near_home := pp.distance_to(home) < home_radius + 22.0
		# Stealth: player.noise_radius() (10 m at a walk) scales how close it must
		# come before the creature attacks; a fight already under way keeps going.
		var hear := 1.0
		if state != State.ATTACK and player.has_method("noise_radius"):
			hear = clampf(float(player.call("noise_radius")) / 10.0, 0.4, 1.6)
		if d < 9.0 * hear or (near_home and d < 16.0 * hear):
			state = State.ATTACK
			_foe = player
		elif d < 24.0:
			state = State.ALERT
			_foe = null
		else:
			state = State.WANDER
			_foe = null
	if _foe != prev_foe or state != State.ATTACK:
		_stop_fighting()
	if state == State.ATTACK and is_instance_valid(_foe):
		Tokens.engage(self, _foe)
		if _turn_rest <= 0.0 and not Tokens.holds(self, _foe) and Tokens.request(self, _foe):
			_turn_time = 0.0


func _stop_fighting() -> void:
	Tokens.release(self)
	_circling = false
	if _winding > 0.0:
		_winding = 0.0
		_strike_target = null
		_busy = 0.2
		_show_telegraph(false)


func _end_turn(rest: float) -> void:
	Tokens.yield_slot(self)
	_turn_rest = rest
	_turn_time = 0.0
	_strikes_left = randi_range(1, 2)
	_circling = false


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
	var should_disable := not _near_player(player)
	if _actor_shape.disabled != should_disable:
		_actor_shape.set_deferred("disabled", should_disable)


func _pick_wander() -> void:
	var ang := randf() * TAU
	var p := home + Vector2(cos(ang), sin(ang)) * randf_range(2.0, home_radius)
	_target = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _face(at: Vector3, delta: float) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 8.0 * delta)


## Wind-up: stop, flag "!" and play the swing slowed so contact lands at `windup`.
func _strike(foe: Node3D) -> void:
	var sp: Dictionary = SPECIES[species]
	var windup := float(sp["windup"])
	_attack_cd = randf_range(float(sp["cooldown"][0]), float(sp["cooldown"][1]))
	_winding = windup
	_busy = windup + float(sp["recover"])
	_strike_target = foe
	_play("attack", true, clampf(_impact_time / windup, 0.3, 1.6))
	_show_telegraph(true)
	var voice := String(sp["voice"])
	if voice != "" and Audio.has_sound(voice):
		Audio.play_sfx(voice, global_position + Vector3.UP * float(sp["height"]) * 0.8, -5.0, 0.1)


func _impact() -> void:
	if _anim:
		_anim.speed_scale = 1.0
	_show_telegraph(false)
	var foe := _strike_target
	_strike_target = null
	var sp: Dictionary = SPECIES[species]
	if Tokens.can_hit(self, foe, float(sp["reach"]), WORLD_LAYER) and foe.has_method("take_damage"):
		var dmg := int(sp["damage"]) + level
		var push := foe.global_position - global_position
		push.y = 0.0
		foe.take_damage(dmg, self, push.normalized() * float(sp["knock"]))
		VFX.sparks(get_parent(), foe.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.6, 0.4), 12)
	_strikes_left -= 1
	if _strikes_left <= 0:
		_end_turn(randf_range(1.2, 2.4))


## The "about to swing" cue: the name tag turns hot orange with a "!".
func _show_telegraph(on: bool) -> void:
	if _label == null:
		return
	if on:
		_label.text = "!  " + _label.text
		_label.modulate = Color(1.0, 0.45, 0.15)
		_label.outline_modulate = Color(0.25, 0.0, 0.0)
	else:
		_label.outline_modulate = Color(0, 0, 0)
		_refresh_label()


func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	_hit_push = knockback
	_hit_from = (from as Node3D).global_position if from is Node3D else Vector3.INF
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
	if from is Node3D and state != State.ATTACK:
		_foe = from
		state = State.ATTACK
	if bool(SPECIES[species]["poise"]) and _winding > 0.0:
		return                       # a troll doesn't flinch mid-swing
	if _winding > 0.0:
		_winding = 0.0
		_strike_target = null
		_show_telegraph(false)
	if _ragdoll and _ragdoll.is_down():
		_busy = maxf(_busy, 0.3)     # already on the ground
		return
	if Ragdoll.is_heavy(amount, from, knockback) and _ragdoll \
			and _ragdoll.knock_down(knockback, _hit_from, _get_up):
		_speed = 0.0
		_busy = Ragdoll.KNOCK_TIME + 1.2
		if state == State.ATTACK:
			_end_turn(2.0)
		return
	_busy = 0.3
	_play("hit", true)
	if state == State.ATTACK and not _circling:
		_end_turn(0.9)               # a hit reaction gives up the attack token


func _yield() -> void:
	health = maxi(1, max_health / 5)
	_stop_fighting()
	_show_telegraph(false)
	state = State.YIELD
	_was_yielded = true
	hostile = false
	_set_team(false)
	_play("kneel", true, 1.0, 0.35)
	_refresh_label()
	Game.say("The %s drops its weapon and kneels." % species)


func _die() -> void:
	dead = true
	Tokens.release(self)
	_winding = 0.0
	_set_team(false)
	_actor_shape.set_deferred("disabled", true)
	if not (_ragdoll and _ragdoll.die(_hit_push, _hit_from)):
		_play("death", true)
	died.emit(self)
	var t := create_tween()
	t.tween_interval(6.0)
	# Squash the model, not the body: Jolt rejects non-uniform body scale.
	t.tween_property(_model, "scale", _model.scale * Vector3(1, 0.01, 1), 0.5)
	t.tween_callback(queue_free)


## Knockdown over (ragdoll.gd moved us under the hips): back on our feet.
func _get_up() -> void:
	if dead:
		return
	if state == State.YIELD:
		_play("kneel", true, 1.0, 0.2)
	elif not _play("stand_up", true, 1.0, 0.2):
		_play("idle", true, 1.0, 0.2)
		_busy = minf(_busy, 0.4)


## Called by Life after a successful naming.
func become_named(given: String, chosen_class: String) -> void:
	named = given
	klass = chosen_class
	state = State.FOLLOW
	hostile = false
	health = max_health
	scale *= 1.12
	_set_team(false)
	_was_yielded = false
	if _play("stand_up", true, 1.0, 0.3):
		_busy = 1.0
	_refresh_label()
	VFX.burst(get_parent(), global_position, "qi", 1.2)
	VFX.aura(self, Color(1.0, 0.85, 0.4), 1.4)


func random_name() -> String:
	return NAMES[randi() % NAMES.size()]


func _play(role: String, restart := false, rate := 1.0, blend := -1.0) -> bool:
	var anim_name := String(_clips.get(role, ""))
	if _anim == null or not _anim.has_animation(anim_name):
		return false
	_anim.speed_scale = rate
	if restart or _anim.current_animation != anim_name:
		if blend < 0.0:
			var loco := [_clips["walk"], _clips["run"]]
			blend = 0.28 if _anim.current_animation in loco and anim_name in loco else 0.15
		_anim.play(anim_name, blend)
	return true
