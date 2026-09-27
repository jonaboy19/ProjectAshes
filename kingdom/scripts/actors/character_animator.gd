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

## Bones that stay with the legs (everything else counts as upper body). Covers
## the KayKit rig and the UE-style Quaternius/UAL rig.
const LOWER_KEYS := ["root", "hips", "pelvis", "upperleg", "lowerleg", "thigh", "calf", "foot", "toes",
	"ball", "heel", "knee", "ik_", "IK", "control-"]
## Measured on the 1.7–1.8 m UAL rigs by tools/qa/anim_qa. Blend-space
## coordinates represent the speed covered by the clip, not a gameplay stat.
const WALK_CLIP_SPEED := 1.0
const RUN_CLIP_SPEED := 6.0

var tree: AnimationTree
var player: AnimationPlayer
var _root: AnimationNodeBlendTree
var _upper_anim: AnimationNodeAnimation
var _full_anim: AnimationNodeAnimation
var _block_target := 0.0
var _block := 0.0
var _speed := 0.0


var _anim_root: Node
var _skeleton: Skeleton3D


func _init(model: Node3D, run_speed: float, _walk_speed := -1.0, walk_anim := "Walking_A", run_anim := "Running_A", idle_anim := "Idle") -> void:
	player = Assets.animation_player(model)
	_anim_root = player.get_node(player.root_node)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_root = AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = maxf(run_speed, 7.5)
	loco.add_blend_point(_anim(idle_anim), 0.0)
	loco.add_blend_point(_anim(walk_anim), WALK_CLIP_SPEED)
	loco.add_blend_point(_anim(run_anim), RUN_CLIP_SPEED)
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
	tree.root_node = tree.get_path_to(_anim_root)
	tree.active = true


func _anim(anim_name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


func _filter_upper(node: AnimationNode) -> void:
	node.filter_enabled = true
	var sk_path := String(_anim_root.get_path_to(_skeleton))
	for i in _skeleton.get_bone_count():
		var bone := _skeleton.get_bone_name(i)
		var lower := false
		for key: String in LOWER_KEYS:
			if bone.begins_with(key) or bone.contains(key):
				lower = true
				break
		if not lower:
			node.set_filter_path(NodePath("%s:%s" % [sk_path, bone]), true)


## Call every frame with the character's horizontal speed.
func update(delta: float, speed: float) -> void:
	_speed = lerpf(_speed, maxf(speed, 0.0), 1.0 - exp(-10.0 * delta))
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
