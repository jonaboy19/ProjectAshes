extends CharacterBody3D
## A party member in the tower (a follower from followers.party() or a hired camp adventurer). Humanoid figure that trails
## the player, engages enemies in reach and can be knocked down by them ("downed" until the fight is won or ~12 s pass).
## Healers mend the player now and then. Group "team0" + "tower_ally" so bosses can pick them as targets.
## Purely a fighter abstraction: hits land on a timer, no per-weapon simulation.

signal downed_changed(ally: Node3D, downed: bool)

const LOOKS := {"knight": "Plate_Knight", "mercenary": "Mercenary", "hunter": "Hunter", "healer": "Herbalist", "scout": "Rogue",
	"smith": "Blacksmith", "priest": "Monk", "cavalry": "Knight", "builder": "Barbarian"}
const GRAVITY := 24.0

var ally_name := "Ally"
var job := "mercenary"
var max_health := 80
var health := 80
var damage := 10
var downed := false
var dead := false       # never truly dead in the tower; kept for the dead/downed duck-typing of enemies
var slot := 0

var _model: Node3D
var _anim: AnimationPlayer
var _atk := 0.0
var _down_t := 0.0
var _heal_t := 8.0
var _foe: Node3D
var _label: Label3D


func setup(p_name: String, p_job: String, floor_level: int, p_slot: int) -> void:
	ally_name = p_name
	job = p_job
	slot = p_slot
	max_health = 60 + floor_level * 5
	health = max_health
	damage = 6 + int(floor_level * 0.9)
	name = "Ally_" + p_name.replace(" ", "_")


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	_model = Assets.character(String(LOOKS.get(job, "Mercenary")), 1.78)
	add_child(_model)
	_anim = Assets.animation_player(_model)
	if _anim:
		for a in ["Idle", "Sword_Idle", "Walking_A", "Running_A"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	add_child(shape)
	_label = Label3D.new()
	var Nameplates := preload("res://scripts/core/nameplates.gd")
	Nameplates.style(_label, Color("8fe3a4"), 22, 22.0)
	_label.position.y = 2.15
	_label.text = ally_name
	add_child(_label)
	add_to_group("team0")
	add_to_group("tower_ally")
	_play("Idle")


func _play(clip: String, rate := 1.0) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.speed_scale = rate
		if _anim.current_animation != clip:
			_anim.play(clip, 0.2)


func take_damage(amount: int, _from: Node = null, knockback := Vector3.ZERO) -> void:
	if downed or amount <= 0:
		return
	health -= maxi(1, int(amount * 0.6))
	velocity += Vector3(knockback.x, 0, knockback.z) * 0.5
	if health <= 0:
		downed = true
		_down_t = 12.0
		_play("Death_A")
		_label.text = ally_name + " (down)"
		downed_changed.emit(self, true)
	else:
		_play("Hit_A")


func revive() -> void:
	if not downed:
		return
	downed = false
	health = max_health / 2
	_label.text = ally_name
	_play("Idle")
	downed_changed.emit(self, false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if downed:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_down_t -= delta
		if _down_t <= 0.0 or get_tree().get_nodes_in_group("tower_enemy").is_empty():
			revive()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_atk -= delta
	_heal_t -= delta
	if not is_instance_valid(_foe) or ("dead" in _foe and bool(_foe.get("dead"))) or global_position.distance_to(_foe.global_position) > 16.0:
		_foe = _nearest_enemy(14.0)
	var want := Vector3.ZERO
	var speed := 0.0
	var face := Vector3.ZERO
	if _foe != null:
		var to := _foe.global_position - global_position
		to.y = 0.0
		var d := to.length()
		face = to
		var reach := 1.8 + (0.8 if job in ["hunter", "scout"] else 0.0) + 0.4 * float(_foe.get("body_scale") if "body_scale" in _foe else 1.0)
		if job == "healer":
			reach = 5.5
		if d > reach:
			want = to.normalized()
			speed = 4.2
		elif _atk <= 0.0:
			_atk = 1.5 if job != "smith" else 2.0
			_play("Sword_Regular_A" if job != "healer" else "Magic_Attack_1", 1.4)
			if _foe.has_method("take_damage"):
				_foe.call("take_damage", damage, self, to.normalized() * 1.0)
	else:
		var anchor := player.global_position + Vector3(2.2 * cos(float(slot) * 2.1 + 0.8), 0, 2.2 * sin(float(slot) * 2.1 + 0.8))
		var to := anchor - global_position
		to.y = 0.0
		face = to
		if to.length() > 1.2:
			want = to.normalized()
			speed = 3.0 if to.length() < 6.0 else 5.5
	if job == "healer" and _heal_t <= 0.0 and "health" in player and "max_health" in player \
			and int(player.get("health")) < int(player.get("max_health")) * 0.7 and player.has_method("heal"):
		_heal_t = 9.0
		player.call("heal", 8 + damage)
	velocity.x = lerpf(velocity.x, want.x * speed, clampf(8.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, want.z * speed, clampf(8.0 * delta, 0.0, 1.0))
	if face.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), clampf(8.0 * delta, 0.0, 1.0))
	move_and_slide()
	if _atk < 1.0:
		if speed > 4.0:
			_play("Running_A")
		elif speed > 0.5:
			_play("Walking_A")
		else:
			_play("Sword_Idle" if _foe != null else "Idle")


func _nearest_enemy(radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for n in get_tree().get_nodes_in_group("tower_enemy"):
		if not (n is Node3D) or ("dead" in n and bool(n.get("dead"))):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best
