class_name CharacterAnimator
extends RefCounted
## Builds an AnimationTree in code for a KayKit character so animations layer
## instead of replacing each other:
##
##   locomotion (BlendSpace1D idle -> walk -> run, driven by speed)
##     -> block   (Blend2, upper body only: shield raised while walking)
##     -> upper   (OneShot, upper body only: swing a sword while running)
##     -> full    (OneShot, whole body: dodge rolls, big hits)
##
## Upper-body filtering uses the rig's bone names, so legs keep running while
## the arms attack. Pattern follows the Godot TPS demo / GDQuest controllers.

const UPPER_BONES := ["spine", "chest", "upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r", "head", "elbowIK.l", "handIK.l",
	"elbowIK.r", "handIK.r", "1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Round_Shield", "Badge_Shield",
	"Rectangle_Shield", "Spike_Shield", "1H_Axe", "1H_Axe_Offhand", "2H_Axe", "Barbarian_Round_Shield",
	"Knight_Helmet", "Barbarian_Hat", "Knife", "Knife_Offhand"]
const SKELETON_PATH := "Rig/Skeleton3D"

var tree: AnimationTree
var player: AnimationPlayer
var _root: AnimationNodeBlendTree
var _upper_anim: AnimationNodeAnimation
var _full_anim: AnimationNodeAnimation
var _block_target := 0.0
var _block := 0.0
var _speed := 0.0


func _init(model: Node3D, run_speed: float, walk_anim := "Walking_A", run_anim := "Running_A", idle_anim := "Idle") -> void:
	player = Assets.animation_player(model)
	_root = AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = run_speed
	loco.add_blend_point(_anim(idle_anim), 0.0)
	loco.add_blend_point(_anim(walk_anim), run_speed * 0.5)
	loco.add_blend_point(_anim(run_anim), run_speed)
	_root.add_node("loco", loco, Vector2(0, 0))

	_root.add_node("block_anim", _anim("Blocking"), Vector2(0, 200))
	var block := AnimationNodeBlend2.new()
	_filter_upper(block)
	_root.add_node("block", block, Vector2(250, 0))

	_upper_anim = _anim("1H_Melee_Attack_Chop")
	_root.add_node("upper_anim", _upper_anim, Vector2(250, 200))
	var upper_speed := AnimationNodeTimeScale.new()
	_root.add_node("upper_speed", upper_speed, Vector2(400, 200))
	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.08
	upper.fadeout_time = 0.18
	_filter_upper(upper)
	_root.add_node("upper", upper, Vector2(550, 0))

	_full_anim = _anim("Dodge_Forward")
	_root.add_node("full_anim", _full_anim, Vector2(550, 200))
	var full_speed := AnimationNodeTimeScale.new()
	_root.add_node("full_speed", full_speed, Vector2(700, 200))
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.06
	full.fadeout_time = 0.15
	_root.add_node("full", full, Vector2(850, 0))

	_root.connect_node("block", 0, "loco")
	_root.connect_node("block", 1, "block_anim")
	_root.connect_node("upper_speed", 0, "upper_anim")
	_root.connect_node("upper", 0, "block")
	_root.connect_node("upper", 1, "upper_speed")
	_root.connect_node("full_speed", 0, "full_anim")
	_root.connect_node("full", 0, "upper")
	_root.connect_node("full", 1, "full_speed")
	_root.connect_node("output", 0, "full")

	tree = AnimationTree.new()
	tree.tree_root = _root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.active = true


func _anim(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


func _filter_upper(node: AnimationNode) -> void:
	node.filter_enabled = true
	for bone: String in UPPER_BONES:
		node.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)


## Call every frame with the character's horizontal speed.
func update(delta: float, speed: float) -> void:
	_speed = lerpf(_speed, speed, clampf(delta * 10.0, 0.0, 1.0))
	tree["parameters/loco/blend_position"] = _speed
	_block = move_toward(_block, _block_target, delta * 6.0)
	tree["parameters/block/blend_amount"] = _block


## Arms-only action (attack, cast, block hit) layered over locomotion.
func play_upper(anim_name: String, time_scale := 1.0) -> void:
	_upper_anim.animation = anim_name
	tree["parameters/upper_speed/scale"] = time_scale
	tree["parameters/upper/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


## Whole-body action (dodge roll, stagger) that overrides locomotion.
func play_full(anim_name: String, time_scale := 1.0) -> void:
	_full_anim.animation = anim_name
	tree["parameters/full_speed/scale"] = time_scale
	tree["parameters/full/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func set_blocking(on: bool) -> void:
	_block_target = 1.0 if on else 0.0


func is_upper_busy() -> bool:
	return tree["parameters/upper/active"]


## Death and other terminal poses bypass the tree.
func play_terminal(anim_name: String) -> void:
	tree.active = false
	player.play(anim_name, 0.1)


func set_active(on: bool) -> void:
	tree.active = on
