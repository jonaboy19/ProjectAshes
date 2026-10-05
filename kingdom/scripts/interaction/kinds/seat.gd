class_name Seat
extends Node3D
## A chair or bench: "Sit" puts the player on the seat (facing the seat's +Z), plays the sit pose and stands
## them up the moment they try to move (or press the button again). The pose is the animator's "sit_chair" /
## "sit_bench" stance, which resolves to the UAL life clips (Life_Rest_Sit_Chair / _Bench) and falls back to
## Sitting_Idle, the clip the ride stance already uses.

signal sat(player: Node)
signal stood(player: Node)

const MOVE_DEADZONE := 0.25

var kind := "chair"            ## "chair" or "bench"
var seat_height := 0.0         ## metres above this node's origin the hips rest at
var occupant: Node3D = null


## A seat at `pos` (global) facing the direction of `yaw`.
static func spawn(parent: Node, pos: Vector3, yaw: float, seat_kind := "chair") -> Seat:
	var s := Seat.new()
	s.kind = seat_kind
	s.name = "Seat_%s" % seat_kind
	parent.add_child(s)
	s.global_position = pos
	s.rotation.y = yaw
	return s


func _ready() -> void:
	set_physics_process(false)
	_build_visual()
	Interactable.attach(self, {"id_fn": func() -> String: return "seat/%s/%d_%d" % [kind, roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)],
		"verb": "Sit", "range": 2.6,
		"can": func(p: Node) -> bool: return occupant == null or occupant == p,
		"do": func(p: Node) -> void: toggle(p as Node3D),
		"label": func() -> Dictionary: return {"verb": "Stand" if occupant != null else "Sit", "target": kind.capitalize()}})


func stance_name() -> String:
	return "sit_bench" if kind == "bench" else "sit_chair"


## Pure: does this movement input get the sitter up?
static func should_stand(move: Vector2, jumped := false) -> bool:
	return jumped or move.length() > MOVE_DEADZONE


func toggle(player: Node3D) -> void:
	if occupant == player:
		stand(player)
	else:
		sit(player)


## Seats `player`. False when someone is already sitting here or the player is dead.
func sit(player: Node3D) -> bool:
	if player == null or occupant != null or bool(player.get("dead")):
		return false
	occupant = player
	player.global_position = global_position + Vector3(0.0, seat_height, 0.0)
	if player.has_method("reset_physics_interpolation"):
		player.call("reset_physics_interpolation")
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	var model: Variant = player.get("_model")
	if model is Node3D:
		(model as Node3D).global_rotation.y = global_rotation.y
	var an: Variant = player.get("_animator")
	if an is Object and (an as Object).has_method("set_stance"):
		(an as Object).call("set_stance", stance_name())
	player.set_meta("seated_on", self)
	set_physics_process(true)
	sat.emit(player)
	return true


## Gets the occupant up (animation back to normal locomotion).
func stand(player: Node3D = null) -> void:
	var who := occupant
	if who == null:
		return
	occupant = null
	set_physics_process(false)
	if is_instance_valid(who):
		var an: Variant = who.get("_animator")
		if an is Object and (an as Object).has_method("set_stance"):
			(an as Object).call("set_stance", "")
		if who.has_meta("seated_on"):
			who.remove_meta("seated_on")
	stood.emit(who)


func _physics_process(_delta: float) -> void:
	if occupant == null or not is_instance_valid(occupant):
		stand()
		return
	var move := Vector2.ZERO
	if InputMap.has_action("move_left") and InputMap.has_action("move_forward"):
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var tm: Variant = occupant.get("touch_move")
	if tm is Vector2:
		move += tm as Vector2
	if should_stand(move, InputMap.has_action("jump") and Input.is_action_just_pressed("jump")) or bool(occupant.get("dead")):
		stand()


func _build_visual() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.16)
	wood.roughness = 0.95
	var size := Vector3(1.6, 0.06, 0.4) if kind == "bench" else Vector3(0.45, 0.06, 0.45)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = size
	top.mesh = tm
	top.material_override = wood
	top.position.y = 0.45
	add_child(top)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.06, 0.45, 0.06)
			leg.mesh = lm
			leg.material_override = wood
			leg.position = Vector3(sx * (size.x * 0.5 - 0.05), 0.225, sz * (size.z * 0.5 - 0.05))
			add_child(leg)
