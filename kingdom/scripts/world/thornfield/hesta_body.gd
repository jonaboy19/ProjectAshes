extends Node3D
## Hesta Thorne's body at the brewery: a villager-style resident the in-world talk (TalkSession) can bind to.
## She is not a WorldSim row, so she has no Villager node; this is the small stand-in that gives her what the talk needs:
## `talk_begin(player)` stops her idle sway and turns her to face you, `talk_end()` returns her to her stool's heading,
## and a LookAtModifier3D on her head follows the player while you talk (and when you stand within 5 m).
## She sits in group "talk_body" with meta npc_id so VillageServices._npc_node can find her; her menus stay on the
## Station parent (hub.gd), so quest options still come from QuestTalk.

const ID := "hesta_thorne"
const NOTICE_SQ := 25.0

var npc_id := ID
var talking := false
var player: Node3D
var model: Node3D
var look_target: Node3D
var head_look: LookAtModifier3D
var _home_yaw := 0.0
var _anim: AnimationPlayer
var _timer := 0.0


func _ready() -> void:
	name = "HestaBody"
	add_to_group("talk_body")
	set_meta("npc_id", ID)
	_home_yaw = global_rotation.y
	model = Assets.character("Trader", 1.7, [])
	if model != null:
		add_child(model)
		_anim = Assets.animation_player(model)
		if _anim != null:
			_anim.play("Idle" if _anim.has_animation("Idle") else _anim.get_animation_list()[0])
		_add_head_look()
	set_process(false)


func _add_head_look() -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var sk := skeletons[0] as Skeleton3D
	var bone := ""
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower() == "head":       # the rigs name it "Head" (Skeleton3D.find_bone is case-sensitive)
			bone = sk.get_bone_name(i)
			break
	if bone == "":
		return
	look_target = Node3D.new()
	add_child(look_target)
	head_look = LookAtModifier3D.new()
	head_look.bone_name = bone
	head_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	head_look.use_angle_limitation = true
	head_look.symmetry_limitation = true
	head_look.primary_limit_angle = deg_to_rad(120)
	head_look.secondary_limit_angle = deg_to_rad(55)
	head_look.duration = 0.3
	head_look.influence = 0.75
	sk.add_child(head_look)
	head_look.target_node = head_look.get_path_to(look_target)
	set_process(true)


func talk_begin(p: Node3D = null) -> void:
	if p != null:
		player = p
	talking = true
	_face_player()
	_timer = 0.0
	set_process(true)


func talk_end() -> void:
	talking = false
	global_rotation.y = _home_yaw


func is_talking() -> bool:
	return talking


func _face_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	global_rotation.y = atan2(to.x, to.z)


func _process(delta: float) -> void:
	if look_target == null:
		set_process(false)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	var p := player
	if p == null or not is_instance_valid(p):
		p = get_tree().get_first_node_in_group("player") as Node3D
	var fwd := Vector3(sin(global_rotation.y), 0.0, cos(global_rotation.y))
	var target := global_position + Vector3(0, 1.45, 0) + fwd * 3.0
	if p != null and (talking or global_position.distance_squared_to(p.global_position) < NOTICE_SQ):
		target = p.global_position + Vector3(0, 1.45, 0)
	look_target.global_position = look_target.global_position.lerp(target, 1.0 - exp(-0.7))
