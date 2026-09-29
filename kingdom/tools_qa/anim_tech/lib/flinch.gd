extends RefCounted
## Additive directional hit flinch on top of ANY base animation, so a character keeps walking / attacking /
## idling while its upper body recoils. AnimationTree layout (the node names are the parameter names):
##
##   base (Animation, whatever the character is doing) ---------------------------.
##   zero (identity additive) -> shot (OneShot, blend, fade in/out) <- dir (BlendSpace2D of additive clips)
##                                   |
##                                   v
##                                 add (Add2, filtered to spine / neck / head / clavicles / arms) -> output
##
##   const Flinch := preload("res://tools_qa/anim_tech/lib/flinch.gd")
##   var f := Flinch.attach(model, "Walk")      # the tree replaces the AnimationPlayer as the driver of the pose
##   f.set_base("Sword_Idle")                   # any clip name of the player
##   f.hit(Vector2(0.0, 1.0), 1.0)              # dir: x = from the character's right (+) / left (-), y = from the front (+) / back (-)
##   f.is_flinching()
##
## The additive clips are built once per player with U.make_additive (right-multiplied delta against frame 0, the
## convention AnimationTree uses for Add2 / OneShot ADD) from the stock Hit_* clips.
## Cost: one extra 2-3 clip filtered blend while flinching; the shot input is skipped when idle.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
## direction point -> stock clip (checked by eye in docs/anim/advanced/tech/flinch.png).
const POINTS := [
	[Vector2(0, 1), "Hit_Chest"],
	[Vector2(0, -1), "Hit_Chest", true],   # from behind: the chest recoil inverted (Hit_B is a full fall)
	[Vector2(-1, 0), "Hit_A"],
	[Vector2(1, 0), "Hit_Head"],
]
const BONES := ["spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]
const FADE_IN := 0.03
const FADE_OUT := 0.16

var tree: AnimationTree
var ap: AnimationPlayer
var _base: AnimationNodeAnimation


static func attach(model: Node3D, base_clip: String, bones: Array = BONES) -> RefCounted:
	var f: RefCounted = (load("res://tools_qa/anim_tech/lib/flinch.gd") as GDScript).new()
	f.call("_setup", model, base_clip, bones)
	return f


func _setup(model: Node3D, base_clip: String, bones: Array) -> void:
	ap = Assets.animation_player(model)
	var sk := U.skeleton_of(model)
	var sk_p := U.sk_path(ap, sk)
	var lib := AnimationLibrary.new()
	var zero_src := ""
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1, -1)
	space.max_space = Vector2(1, 1)
	space.sync = true
	for p: Array in POINTS:
		var clip: String = U.find_clip(ap, [p[1]])
		if clip == "":
			continue
		var inv: bool = p.size() > 2
		var add_anim := U.make_additive(ap.get_animation(clip), 0.0, PackedStringArray(bones), sk, false, inv)
		var key := "add_" + clip + ("_inv" if inv else "")
		lib.add_animation(key, add_anim)
		if zero_src == "":
			zero_src = key
		var n := AnimationNodeAnimation.new()
		n.animation = "atadd/" + key
		space.add_blend_point(n, p[0])
	# identity additive: same tracks, every key the identity, so the OneShot fades the delta in from nothing
	var zero := U.make_additive(ap.get_animation(U.find_clip(ap, [POINTS[0][1]])), 0.0, PackedStringArray(bones), sk, true)
	zero.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("zero", zero)
	ap.add_animation_library("atadd", lib)

	var root := AnimationNodeBlendTree.new()
	_base = AnimationNodeAnimation.new()
	_base.animation = base_clip
	root.add_node("base", _base, Vector2(-500, -100))
	var z := AnimationNodeAnimation.new()
	z.animation = "atadd/zero"
	root.add_node("zero", z, Vector2(-500, 100))
	root.add_node("dir", space, Vector2(-500, 250))
	var shot := AnimationNodeOneShot.new()
	shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	shot.fadein_time = FADE_IN
	shot.fadeout_time = FADE_OUT
	root.add_node("shot", shot, Vector2(-250, 150))
	var add := AnimationNodeAdd2.new()
	add.filter_enabled = true
	for b: String in bones:
		add.set_filter_path(NodePath("%s:%s" % [sk_p, b]), true)
	root.add_node("add", add, Vector2(0, 0))
	root.connect_node("shot", 0, "zero")
	root.connect_node("shot", 1, "dir")
	root.connect_node("add", 0, "base")
	root.connect_node("add", 1, "shot")
	root.connect_node("output", 0, "add")
	tree = AnimationTree.new()
	tree.tree_root = root
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.root_node = tree.get_path_to(ap.get_node(ap.root_node))
	tree.set("parameters/add/add_amount", 1.0)
	tree.active = true


func set_base(clip: String) -> void:
	_base.animation = clip


## `dir`: x = the hit comes from the character's right (+) / left (-), y = from the front (+) / back (-).
## `amount` scales the recoil (1 = the clip as authored, up to ~1.5).
func hit(dir: Vector2, amount := 1.0) -> void:
	tree.set("parameters/dir/blend_position", dir.limit_length(1.0))
	tree.set("parameters/add/add_amount", amount)
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_flinching() -> bool:
	return bool(tree.get("parameters/shot/active"))
