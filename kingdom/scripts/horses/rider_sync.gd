class_name RiderSync
extends Node
## Keeps a UAL rider glued to a HorseRig and in step with it (standalone module; wiring: P14_rider_sync.md).
##
## Contract (docs/anim/horses/HANDOFF.md): every Horse_Ride_* clip was authored against the horse at REST with the rider
## root at the horse root. Each frame the rider model is moved rigidly by the saddle delta
##     rider.global = horse_skeleton.global * saddle_delta
## and its synced clip plays at the SAME normalized time as the horse clip (phase lock, no drift, blends included).
## Actions (sword, bow, rein turns ...) are "upper" layer clips: play_upper() blends their spine/arm tracks over the
## synced gait through an AnimationTree-free bone filter (a second AnimationPlayer would fight the first, so the
## upper clip is merged per frame with a Blend2 node in a tiny AnimationTree built here).
##
##   var sync := RiderSync.new(); add_child(sync); sync.attach(horse, rider_model)   # rider_model = UAL character root
##   sync.play_upper("Horse_Ride_Sword_Swing_R")   # returns the clip length; hit frame in the sidecar
##   sync.play_full("Horse_Ride_Dismount_L")       # full-body override (mount/dismount/fall), ends via full_finished
##   sync.detach()

signal full_finished(clip: String)

const RIDER_GLB := "res://assets/generated/horses/UAL_Horse_Rider.glb"
const RIDER_SIDECAR := RIDER_GLB + ".clips.json"
const LIB := "rider"
const UPPER_ROOT := "spine_01"

var horse: HorseRig
var rider: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var enabled := true
var full_clip := ""
var upper_clip := ""
var _anim: AnimationPlayer
var _blend_gait: AnimationNodeAnimation
var _upper_node: AnimationNodeAnimation
var _full_node: AnimationNodeAnimation
var _root: AnimationNodeBlendTree
var _upper_w := 0.0
var _full_w := 0.0
var _upper_t := 0.0
var _full_t := 0.0
var _scale := Vector3.ONE
var _full_done := false
## Keep the last frame of a full-body clip (dismount end pose) until stop_full() or the next play_full().
var hold_full := false

static var _lib_cache := {}
static var _meta := {}


static func clip_info(name: String) -> Dictionary:
	if _meta.is_empty() and FileAccess.file_exists(RIDER_SIDECAR):
		var arr = JSON.parse_string(FileAccess.get_file_as_string(RIDER_SIDECAR))
		if arr is Array:
			for e: Dictionary in arr:
				_meta[e["name"]] = e
	return _meta.get(name, {})


static func library(skel_path: String) -> AnimationLibrary:
	if _lib_cache.has(skel_path):
		return _lib_cache[skel_path]
	var lib := AnimationLibrary.new()
	if ResourceLoader.exists(RIDER_GLB):
		var inst: Node = (load(RIDER_GLB) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():
			var a: Animation = ap.get_animation(n).duplicate(true)
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(skel_path + tp.substr(colon)))
			lib.add_animation(n, a)
		inst.free()
	_lib_cache[skel_path] = lib
	return lib


## Rider clip that goes with a horse clip (synced, same frame count).
static func rider_clip_for(horse_clip: String) -> String:
	var c := "Horse_Ride_" + horse_clip
	if not clip_info(c).is_empty():
		return c
	for pre: String in ["Gallop", "Canter", "Trot", "Walk", "Cart_Pull_Walk", "Graze", "Drink"]:
		if horse_clip.begins_with(pre):
			var alt: String = "Horse_Ride_" + String({"Cart_Pull_Walk": "Walk"}.get(pre, pre))
			for suf: String in ["_L", ""]:
				if not clip_info(alt + suf).is_empty():
					return alt + suf
	return "Horse_Ride_Idle"


func attach(h: HorseRig, rider_model: Node3D) -> void:
	horse = h
	rider = rider_model
	_scale = rider.scale
	skeleton = rider.find_children("*", "Skeleton3D", true, false)[0]
	_anim = AnimationPlayer.new()
	_anim.name = "RiderSyncPlayer"
	rider.add_child(_anim)
	_anim.root_node = _anim.get_path_to(rider)
	var sp := String(rider.get_path_to(skeleton))
	_anim.add_animation_library(LIB, library(sp))
	# disable the rider's own player (locomotion) while mounted
	for ap: AnimationPlayer in rider.find_children("*", "AnimationPlayer", true, false):
		if ap != _anim:
			ap.active = false
	for at: AnimationTree in rider.find_children("*", "AnimationTree", true, false):
		at.active = false
	_build_tree(sp)
	process_priority = 200            # after the horse's AnimationPlayer
	process_physics_priority = 200


func detach() -> void:
	if tree:
		tree.queue_free()
	if _anim:
		_anim.queue_free()
	for ap: AnimationPlayer in rider.find_children("*", "AnimationPlayer", true, false):
		ap.active = true
	for at: AnimationTree in rider.find_children("*", "AnimationTree", true, false):
		at.active = true
	horse = null


func _build_tree(skel_path: String) -> void:
	tree = AnimationTree.new()
	tree.name = "RiderSyncTree"
	rider.add_child(tree)
	tree.anim_player = tree.get_path_to(_anim)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_root = AnimationNodeBlendTree.new()
	_blend_gait = AnimationNodeAnimation.new()
	_blend_gait.use_custom_timeline = false
	_upper_node = AnimationNodeAnimation.new()
	_full_node = AnimationNodeAnimation.new()
	var upper_blend := AnimationNodeBlend2.new()
	upper_blend.filter_enabled = true
	var i := skeleton.find_bone(UPPER_ROOT)
	for b in skeleton.get_bone_count():
		var p := b
		var under := false
		while p >= 0:
			if p == i:
				under = true
				break
			p = skeleton.get_bone_parent(p)
		if under:
			upper_blend.set_filter_path(NodePath(skel_path + ":" + skeleton.get_bone_name(b)), true)
	var full_blend := AnimationNodeBlend2.new()
	_root.add_node("gait", _blend_gait, Vector2(0, 0))
	_root.add_node("upper", _upper_node, Vector2(0, 200))
	_root.add_node("full", _full_node, Vector2(0, 400))
	for n: String in ["gait", "upper", "full"]:
		_root.add_node(n + "_seek", AnimationNodeTimeSeek.new(), Vector2(150, 0))
		_root.connect_node(n + "_seek", 0, n)
	_root.add_node("ub", upper_blend, Vector2(300, 100))
	_root.add_node("fb", full_blend, Vector2(600, 200))
	_root.connect_node("ub", 0, "gait_seek")
	_root.connect_node("ub", 1, "upper_seek")
	_root.connect_node("fb", 0, "ub")
	_root.connect_node("fb", 1, "full_seek")
	_root.connect_node("output", 0, "fb")
	tree.tree_root = _root
	tree.active = true


func play_upper(c: String, blend_in := 0.12) -> float:
	var full := LIB + "/" + c
	if not _anim.has_animation(full):
		return 0.0
	upper_clip = c
	_upper_node.animation = full
	_upper_t = 0.0
	_upper_w = 0.0
	_seek_node("upper", 0.0)
	return _anim.get_animation(full).length


func stop_upper() -> void:
	upper_clip = ""


func play_full(c: String) -> float:
	var full := LIB + "/" + c
	if not _anim.has_animation(full):
		return 0.0
	full_clip = c
	_full_node.animation = full
	_full_t = 0.0
	_full_done = false
	return _anim.get_animation(full).length


func stop_full() -> void:
	full_clip = ""


func _process(delta: float) -> void:
	if not enabled or horse == null or not is_instance_valid(horse) or rider == null:
		return
	# 1. place the rider rigidly with the saddle (the horse's pose for this frame is already applied)
	var skel_g := horse.skeleton.global_transform
	rider.global_transform = (skel_g * horse.saddle_delta() * _rest_offset()).scaled_local(_scale)
	# 2. phase-locked gait clip
	var gc := LIB + "/" + rider_clip_for(horse.clip)
	if _anim.has_animation(gc):
		if _blend_gait.animation != gc:
			_blend_gait.animation = gc
			if _upper_node.animation == &"":
				_upper_node.animation = gc
			if _full_node.animation == &"":
				_full_node.animation = gc
		var a := _anim.get_animation(gc)
		_seek_node("gait", horse.phase() * a.length)
	# 3. upper and full layers
	var up_len := _anim.get_animation(LIB + "/" + upper_clip).length if upper_clip != "" and _anim.has_animation(LIB + "/" + upper_clip) else 0.0
	if upper_clip != "":
		_upper_t += delta
		_upper_w = move_toward(_upper_w, 1.0 if _upper_t < up_len - 0.12 else 0.0, delta / 0.12)
		_seek_node("upper", minf(_upper_t, up_len))
		if _upper_t >= up_len and _upper_w <= 0.0:
			upper_clip = ""
	else:
		_upper_w = move_toward(_upper_w, 0.0, delta / 0.12)
	var full_len := _anim.get_animation(LIB + "/" + full_clip).length if full_clip != "" and _anim.has_animation(LIB + "/" + full_clip) else 0.0
	if full_clip != "":
		_full_t += delta
		_full_w = move_toward(_full_w, 1.0, delta / 0.15)
		_seek_node("full", minf(_full_t, full_len))
		if _full_t >= full_len and not _full_done:
			_full_done = true
			full_finished.emit(full_clip)
			if not hold_full:
				full_clip = ""
	else:
		_full_w = move_toward(_full_w, 0.0, delta / 0.2)
	tree.set("parameters/ub/blend_amount", _upper_w)
	tree.set("parameters/fb/blend_amount", _full_w)
	tree.advance(maxf(delta, 0.0001))


## The Horse_Ride clips put the rider root at the HORSE root (rest): no extra offset. Kept as a hook for rigs whose
## model root is offset from their skeleton (returns identity for the UAL characters).
func _rest_offset() -> Transform3D:
	return Transform3D.IDENTITY


func _seek_node(node: String, t: float) -> void:
	# every layer is driven by an explicit time through its TimeSeek node, then tree.advance(0) applies the pose
	tree.set("parameters/%s_seek/seek_request" % node, t)
