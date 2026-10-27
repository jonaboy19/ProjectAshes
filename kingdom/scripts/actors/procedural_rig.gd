extends Node
## Procedural animation layered over the clips of any character model with a
## Skeleton3D, built from Godot 4.6's SkeletonModifier3D nodes:
##
##   foot IK     — one downward ray per foot, a TwoBoneIK3D per leg, the pelvis
##                 lowered to the lower foot and the planted feet tilted to the
##                 ground normal (UAL rig: thigh/calf/foot, pelvis).
##   secondary   — a damped spring on the torso (lags acceleration and turns)
##                 and on every BoneAttachment3D prop (weapon, shield), which
##                 trails the bone it rides on instead of being welded to it.
##   spring bones — SpringBoneSimulator3D chains for tails, ears, hair, capes,
##                 skirts, belts and pouches when a rig has such bones (the
##                 Quaternius-rigged wolf, bear and boar and the wyvern do; the
##                 65-bone UAL humanoids do not).
##
## Modifier order under the skeleton (each runs on the output of the previous):
##   animation -> LookAtModifier3D -> pre (pelvis, IK targets) -> TwoBoneIK3D
##             -> post (foot tilt, torso and prop springs) -> SpringBoneSimulator3D
##
## Everything switches off beyond ACTIVE_RANGE from the camera or while the
## model is hidden (impostor LOD, first-person view), checked by a timer.
##
## Usage (no class_name; preload it):
##   const ProceduralRig := preload("res://scripts/actors/procedural_rig.gd")
##   var rig := ProceduralRig.attach(model, self)     # humanoid: IK + secondary + springs
##   ProceduralRig.attach_springs(model)              # creatures: tail and ear springs only
## Owners that know their state call set_state() each tick; others are measured.
##
## Foot IK approach after SeaKrill's Godot-Foot-IK (MIT, (c) 2023 SeaKrill),
## reimplemented on the 4.6 IK modifiers. See CREDITS.md.

const ACTIVE_RANGE := 25.0
const CHECK_INTERVAL := 0.35
const WORLD_MASK := 1
const LEGS := [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]
const PELVIS := "pelvis"
## Arm chains for set_hand_brace (wall contact, balance): built lazily the first time a brace is requested.
const ARMS := [["upperarm_l", "lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r", "hand_r"]]
const TORSO := [["spine_02", 0.45], ["spine_03", 0.45], ["neck_01", -0.35]]
## IK weight by locomotion: full up to a walk, eased down into a run.
const RUN_WEIGHT := 0.35
const WALK_FULL := 2.8         # m/s (body-size corrected)
const RUN_REDUCED := 5.5
const WEIGHT_RATE := 4.0       # 1/s blend in and out
const MAX_TILT := 0.55         # rad the feet may tilt to the ground (~32°)
const GROUND_RATE := 20.0      # 1/s smoothing of the ground under each foot
const PELVIS_RATE := 12.0
## Torso spring: lean (rad) per m/s² of acceleration, and its limit.
const TORSO_GAIN := 0.010
const TORSO_MAX := 0.07
const TORSO_STIFF := 70.0
const TORSO_DAMP := 0.45       # damping ratio: a little overshoot reads as weight
## Prop spring: tip lag (m) per m/s² of grip acceleration, limited to a fraction of the prop length.
## Foot lock (docs/plans/AAA_FINISH_PLAN.md A5.1): while the animated sole is on the ground the IK target is pinned to where
## the stance began, so the planted foot cannot skate when the body speed and the clip's ground speed disagree. The pin
## fades out over LOCK_BLEND at lift-off and is dragged along once it lags more than LOCK_MAX (metres at leg height 0.98).
const LOCK_ON_LIFT := 0.045       # animated ball of the foot this high (m, at leg height 0.98) or lower: the stance starts
const LOCK_OFF_LIFT := 0.065     # ... and ends above this (hysteresis)
const LOCK_MAX := 0.25           # m of lag between the pinned and the animated foot before the pin is dragged along
const REACH_MAX := 0.97          # a pinned foot is kept within this fraction of the leg length (pelvis drop)
const REACH_DROP_MAX := 0.08     # ... dropping the pelvis at most this fraction of the leg (8 cm at 0.98 m)
const LOCK_BLEND := 0.05         # s: 3 frames at 60 Hz
const LOCK_MIN_SPEED := 0.35     # m/s: below this the clip is a standing idle, nothing to pin
const WEAPON_CARRY_DEG := 45.0
const WEAPON_CARRY_RATE := 14.0  # 1/s into a swing
const WEAPON_CARRY_IN := 4.5     # 1/s back to the carry: blends over the swing recovery with the arm, no snap
const HOLSTER_RATE := 7.0        # 1/s: arm <-> back in ~0.15 s
const BACK_GAP := 0.165          # m from the spine line (pelvis..neck) to the inner face of a prop on the back
const BACK_DIAG_DEG := 35.0      # long weapons on the back: tilt from vertical, grip over the right shoulder
const GUARD_MARGIN := 0.01       # m a hand prop is kept above the floor
const PROP_GAIN := 0.0045
const PROP_MAX := 0.12
const PROP_STIFF := 160.0
const PROP_DAMP := 0.3
## Spring chains: bone-name keyword -> [stiffness, drag, gravity, radius].
const SPRING_KEYS := {
	"tail": [1.6, 0.45, 0.15, 0.03], "ear": [4.0, 0.5, 0.0, 0.01], "hair": [2.0, 0.4, 0.4, 0.02],
	"ponytail": [1.8, 0.4, 0.5, 0.02], "braid": [1.8, 0.4, 0.5, 0.02], "cape": [1.2, 0.5, 0.6, 0.04],
	"cloak": [1.2, 0.5, 0.6, 0.04], "skirt": [2.5, 0.5, 0.4, 0.04], "belt": [3.0, 0.5, 0.5, 0.02],
	"pouch": [3.0, 0.5, 0.6, 0.02], "tassel": [2.0, 0.4, 0.6, 0.01],
}


## A SkeletonModifier3D stage that runs a callback in the modifier stack.
class Stage extends SkeletonModifier3D:
	var run: Callable

	func _process_modification_with_delta(delta: float) -> void:
		if run.is_valid():
			run.call(delta)


## Owner-driven state (see set_state). Without calls the rig measures speed itself.
var suppressed := false        # swimming, riding, rolling, dead: no IK at all
var airborne := false
var attacking := false         # whole-body actions that fight the clip: IK eased off
var external_off := false      # a second owner (GroundRealism: steep-slope slide) switches the foot IK off; set_state does not touch it
var always_near := false       # the local player: rays every tick
var paused := false            # set_paused(): ragdoll or cutscene owns the skeleton

var _model: Node3D
var _body: CollisionObject3D
var _skeleton: Skeleton3D
var _camera: Camera3D
var _timer: Timer
var _near := false
var _use_ik := false
var _use_secondary := false
var _pre: Stage
var _ik: TwoBoneIK3D
var _post: Stage
var _springs: SpringBoneSimulator3D
var _markers: Array[Node3D] = []   # [target_l, target_r, pole_l, pole_r]
var _query: PhysicsRayQueryParameters3D
var _tick := 0
var _owner_speed := -1.0

# Bones (-1 = missing).
var _leg: Array[PackedInt32Array] = []
var _pelvis := -1
var _torso: Array = []            # [[bone, share], ...]
var _leg_len := 0.9
var _ankle_rest := 0.08

# Per-foot state (index 0 = left, 1 = right).
var _foot_anim: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_rot: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]   # animated, skeleton space
var _has_anim := false
var _hit: Array[bool] = [false, false]
var _hit_y: Array[float] = [0.0, 0.0]
var _hit_n: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _ground: Array[float] = [0.0, 0.0]      # smoothed offset from the base plane
var _normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _plant: Array[float] = [0.0, 0.0]
## The starter sword is authored for the swing poses (blade perpendicular to the fist); between swings it is carried lowered: the owner
## sets weapon_carry, the hand prop eases WEAPON_CARRY_DEG around its grip axis and back (docs/plans/AAA_PROGRESS.md, idle sword).
var weapon_carry := false
var _carry_w := 0.0
## Back sockets (docs/plans/AAA_PROGRESS.md, shield sling / roll holster): the owner sets shield_slung (the shield rides on the upper
## back instead of the forearm: out of combat, rolling, airborne) and long_holster (two-handed weapons go diagonally across the back
## while rolling). The prop travels between arm and back on an arc outside the body (HOLSTER_RATE), it is never hidden. Every hand
## prop is also kept above ground_guard_y (the floor under the body, set by the owner while grounded): no blade through the floor.
var shield_slung := false
var long_holster := false
## Sheathed (unarmed stance): one-handed weapons ride the left hip, blade down and back, grip forward; shields and long weapons go on
## the back (owner also sets shield_slung / long_holster).
var sheathed := false
var seated := 0.0             ## 0..1 sitting down: the hip blade lays back toward level, over the seat instead of through it
var ground_guard_y := NAN
var foot_lock := true
## 0..1 strength of the foot lock, set by the owner from how far the clip falls short of the body speed (player.gd).
var lock_gain := 1.0                         # QA switch (tools_qa/anim_states/loco_slide.gd --no-lock)
var _ball: Array[int] = []
var _leaf: Array[int] = []
var _sole_rest: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # rest heights (ankle, ball, toe tip) above the soles plane, left foot
var _ball_rest := 0.03                                          # rest-pose ball height above the soles plane (m)
var _ball_lift: Array[float] = [1.0, 1.0]                       # animated ball height above its rest height (m)
var _ball_off: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # animated ankle minus ball, world XZ
var _lock_on: Array[bool] = [false, false]
var _lock_xz: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _lock_w: Array[float] = [0.0, 0.0]
## Heel-toe lock: a stance that starts on the heel pins the ANKLE until the ball comes down, then hands the pin to the ball (where the
## pinned ankle puts it), so neither the heel at strike nor the ball at toe-off slides.
var _lock_heel: Array[bool] = [false, false]
var _lock_yaw: Array[float] = [NAN, NAN]
var _ball_h: Array[float] = [1.0, 1.0]
const HEEL_BALL_UP := 0.02      # m: ball this high above its rest at plant -> heel strike
const HEEL_BALL_DOWN := 0.012   # m: ball down -> pin moves to the ball
const HEEL_LOCK_MAX_SPEED := 1.8   # m/s: above this the heel phase is too short to pin (measured: it doubled jog slip)
var _pelvis_off := 0.0
var _reach_drop := 0.0
var _weight := 0.0

# Secondary motion state.
var _last_pos := Vector3.INF
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _props: Array = []            # [{att, node, rest, r, bone, last, vel, off, off_v}]

# Hand brace (arm IK, lazy) and torso yaw offset, both set by the owner (WallContact).
var _arm: Array[PackedInt32Array] = []
var _arm_ik: Array[TwoBoneIK3D] = []
var _arm_markers: Array[Node3D] = []      # [target_l, target_r, pole_l, pole_r]
var _arms_state := 0                      # 0 = not built, 1 = built, -1 = rig has no arms
var _brace_pt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _brace_w: Array[float] = [0.0, 0.0]
var _assist_pt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]     # two-handed weapon: the off hand rides on the weapon (own channel, wall braces win)
var _assist_w: Array[float] = [0.0, 0.0]
var _brace_rot: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _torso_yaw := 0.0
var _axis_anim := Vector3.ZERO
var _yaw_ch := {}                         # channel -> rad (0 = wall contact, 1 = balance sway)


## Foot IK, secondary motion and any spring chains on `model`. `body` is the
## physics body carrying it (its rays skip it). Returns the rig node, or null.
static func attach(model: Node3D, body: Node3D = null, player := false) -> Node:
	var rig: Node = (load("res://scripts/actors/procedural_rig.gd") as GDScript).new()
	if not rig.call("_setup", model, body, true, true):
		rig.free()
		return null
	rig.set("always_near", player)
	return rig


## Spring chains only (tails, ears, hair...) with the same camera-distance
## gating. Returns the rig node, or null when the rig has no such bones.
static func attach_springs(model: Node3D) -> Node:
	var rig: Node = (load("res://scripts/actors/procedural_rig.gd") as GDScript).new()
	if not rig.call("_setup", model, null, false, false) or rig.get("_springs") == null:
		rig.free()
		return null
	return rig


## Switches every modifier off (ragdoll, death, cutscene) until unpaused.
func set_paused(on: bool) -> void:
	paused = on
	if on and _near:
		_set_near(false)
	elif not on and is_inside_tree():
		_check_range()


## Call from the owner's tick. `speed` is horizontal ground speed in m/s.
func set_state(speed: float, grounded: bool, off := false, heavy_action := false) -> void:
	_owner_speed = speed
	airborne = not grounded
	suppressed = off
	attacking = heavy_action


## Owner request: put hand `side` (0 = left, 1 = right) on `point` (world) with weight 0..1. Only the player's rig
## (always_near) builds the arm IK; others ignore it. `normal` is unused for now (the hand keeps its animated rotation).
func set_hand_brace(side: int, point: Vector3, _normal: Vector3, weight: float) -> void:
	if side < 0 or side > 1:
		return
	_brace_pt[side] = point
	_brace_w[side] = clampf(weight, 0.0, 1.0)
	if _brace_w[side] > 0.001 and _arms_state == 0 and always_near and _use_ik:
		_build_arms()


## Off-hand assist for two-handed weapons (own channel next to set_hand_brace). side 0 = left.
func set_hand_assist(side: int, point: Vector3, weight: float) -> void:
	if side < 0 or side > 1:
		return
	_assist_pt[side] = point
	_assist_w[side] = clampf(weight, 0.0, 1.0)
	if _assist_w[side] > 0.001 and _arms_state == 0 and always_near and _use_ik:
		_build_arms()


## Carrying a load in both arms (player.gd _update_carry): its own channel, above wall braces and weapon assists.
var _load_pt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _load_w: Array[float] = [0.0, 0.0]


func set_hand_carry(side: int, point: Vector3, weight: float) -> void:
	if side < 0 or side > 1:
		return
	_load_pt[side] = point
	_load_w[side] = clampf(weight, 0.0, 1.0)
	if _load_w[side] > 0.001 and _arms_state == 0 and always_near and _use_ik:
		_build_arms()


## Shoulder-to-wrist length in metres (rest pose, at the current body scale); 0.37 when the rig has no arms.
func arm_length() -> float:
	var up := _skeleton.find_bone(ARMS[0][0])
	var lo := _skeleton.find_bone(ARMS[0][1])
	var hd := _skeleton.find_bone(ARMS[0][2])
	if up < 0 or lo < 0 or hd < 0:
		return 0.37
	var xf := _skeleton.global_transform
	var a := xf * _skeleton.get_bone_global_rest(up).origin
	var b := xf * _skeleton.get_bone_global_rest(lo).origin
	var c := xf * _skeleton.get_bone_global_rest(hd).origin
	return a.distance_to(b) + b.distance_to(c)


## World vector from the left upper-arm joint to the right one in the ANIMATED pose (measured at the start of the pre stage,
## before any chest yaw of ours), or ZERO when the rig has no arms.
func shoulder_axis() -> Vector3:
	return _axis_anim


## Chest yaw (rad, about world up) added to the torso bones; + turns toward the model's left. 0 = none. Channels add up.
func set_torso_yaw_offset(rad: float, channel := 0) -> void:
	_yaw_ch[channel] = rad
	var total := 0.0
	for v: float in _yaw_ch.values():
		total += v
	_torso_yaw = total


func _build_arms() -> void:
	_arms_state = -1
	for names: Array in ARMS:
		var ids := PackedInt32Array()
		for n: String in names:
			ids.append(_skeleton.find_bone(n))
		if ids.has(-1):
			_arm.clear()
			return
		_arm.append(ids)
	for i in 4:
		var m := Node3D.new()
		m.top_level = true
		add_child(m)
		_arm_markers.append(m)
	for s in 2:
		var ik := TwoBoneIK3D.new()
		ik.name = "ArmIK_" + ("L" if s == 0 else "R")
		ik.setting_count = 1
		ik.set_root_bone(0, _arm[s][0])
		ik.set_middle_bone(0, _arm[s][1])
		ik.set_end_bone(0, _arm[s][2])
		_skeleton.add_child(ik)
		ik.set_target_node(0, ik.get_path_to(_arm_markers[s]))
		ik.set_pole_node(0, ik.get_path_to(_arm_markers[s + 2]))
		ik.influence = 0.0
		ik.active = _near
		_arm_ik.append(ik)
	_arms_state = 1
	if _near:
		_order_modifiers()


func _setup(model: Node3D, body: Node3D, ik: bool, secondary: bool) -> bool:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	_model = model
	_skeleton = found[0]
	_body = body as CollisionObject3D
	name = "ProceduralRig"
	if ik:
		_use_ik = _find_legs()
	if secondary:
		_find_secondary()
	_build_springs()
	if not _use_ik and not _use_secondary and _springs == null:
		return false
	model.add_child(self)
	return true


func _find_legs() -> bool:
	for names: Array in LEGS:
		var ids := PackedInt32Array()
		for n: String in names:
			ids.append(_skeleton.find_bone(n))
		if ids.has(-1):
			return false
		_leg.append(ids)
	_pelvis = _skeleton.find_bone(PELVIS)
	for ball_name: String in ["ball_l", "ball_r"]:        # foot lock pins the ball of the foot (the ankle rolls over it)
		_ball.append(_skeleton.find_bone(ball_name))
	for leaf_name: String in ["ball_leaf_l", "ball_leaf_r"]:
		_leaf.append(_skeleton.find_bone(leaf_name))
	return _pelvis >= 0


func _find_secondary() -> void:
	for entry: Array in TORSO:
		var b := _skeleton.find_bone(entry[0])
		if b >= 0:
			_torso.append([b, entry[1]])
	_use_secondary = not _torso.is_empty()
	for att in _skeleton.find_children("*", "BoneAttachment3D", false, false):
		var a := att as BoneAttachment3D
		for child in a.get_children():
			if not child is Node3D:
				continue
			var prop := child as Node3D
			var box := prop.transform * Assets.visual_aabb(prop)
			var r := box.get_center()
			if r.length() < 0.0001:
				continue
			_props.append({"node": prop, "rest": prop.transform, "r": r, "bone": _skeleton.find_bone(a.bone_name),
				"last": Vector3.INF, "vel": Vector3.ZERO, "off": Vector3.ZERO, "off_v": Vector3.ZERO})
	_use_secondary = _use_secondary or not _props.is_empty()


## Chains of bones named after SPRING_KEYS: a chain starts at a matching bone
## whose parent does not match and follows matching children to the tip.
func _build_springs() -> void:
	var chains: Array = []   # [root, end, params]
	for i in _skeleton.get_bone_count():
		var key := _spring_key(_skeleton.get_bone_name(i))
		if key == "":
			continue
		var parent := _skeleton.get_bone_parent(i)
		if parent >= 0 and _spring_key(_skeleton.get_bone_name(parent)) == key:
			continue
		var end := i
		while true:
			var next := -1
			for c in _skeleton.get_bone_children(end):
				if _spring_key(_skeleton.get_bone_name(c)) == key:
					next = c
					break
			if next < 0:
				break
			end = next
		if end != i:
			chains.append([i, end, SPRING_KEYS[key]])
	if chains.is_empty():
		return
	_springs = SpringBoneSimulator3D.new()
	_springs.name = "SpringBones"
	_springs.setting_count = chains.size()
	for s in chains.size():
		var c: Array = chains[s]
		var p: Array = c[2]
		_springs.set_root_bone(s, c[0])
		_springs.set_end_bone(s, c[1])
		_springs.set_stiffness(s, p[0])
		_springs.set_drag(s, p[1])
		_springs.set_gravity(s, p[2])
		_springs.set_radius(s, p[3])
	_springs.active = false


static func _spring_key(bone: String) -> String:
	var low := bone.to_lower()
	for key: String in SPRING_KEYS:
		if low.begins_with(key) or low.contains("_" + key) or low.contains("." + key):
			# "ear" must not catch "forearm", "shear"... (begins_with or a separator only)
			return key
	return ""


func _ready() -> void:
	if _use_ik:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collision_mask = WORLD_MASK
		if _body:
			_query.exclude = [_body.get_rid()]
		for i in 4:
			var m := Node3D.new()
			m.top_level = true
			add_child(m)
			_markers.append(m)
		_pre = Stage.new()
		_pre.name = "RigPre"
		_pre.run = _pre_modify
		_skeleton.add_child(_pre)
		_ik = TwoBoneIK3D.new()
		_ik.name = "FootIK"
		_ik.setting_count = 2
		for s in 2:
			_ik.set_root_bone(s, _leg[s][0])
			_ik.set_middle_bone(s, _leg[s][1])
			_ik.set_end_bone(s, _leg[s][2])
		_skeleton.add_child(_ik)
		for s in 2:
			_ik.set_target_node(s, _ik.get_path_to(_markers[s]))
			_ik.set_pole_node(s, _ik.get_path_to(_markers[s + 2]))
	if _use_ik or _use_secondary:
		_post = Stage.new()
		_post.name = "RigPost"
		_post.run = _post_modify
		_skeleton.add_child(_post)
	if _springs:
		_skeleton.add_child(_springs)
	_timer = Timer.new()
	_timer.wait_time = CHECK_INTERVAL
	_timer.timeout.connect(_check_range)
	add_child(_timer)
	_timer.start(randf_range(0.02, CHECK_INTERVAL))
	_set_near(false)


func _notification(what: int) -> void:
	# The stages live under the skeleton. A rig freed on its own (the model stays)
	# takes them along; when the model goes, the skeleton frees them itself.
	if what == NOTIFICATION_PREDELETE:
		_candidates.erase(get_instance_id())
		for mod: Node in [_pre, _ik, _post, _springs] + _arm_ik:
			if is_instance_valid(mod) and not mod.is_queued_for_deletion():
				mod.queue_free()


## Performance budget: only the nearest few NPC rigs run their modifiers (the
## player's rig is exempt via always_near). Every active rig runs GDScript stages
## inside the skeleton update each frame; with ~30 villagers, soldiers and animals
## within ACTIVE_RANGE in the village this cost 50-100 ms frames (perf_visual
## ablation 2026-09-28: 260 -> 23 hitches with rigs off). Distance-ranked, refreshed
## on each rig's CHECK_INTERVAL timer; per-tier count from Quality ("rig_budget").
static var _candidates: Dictionary = {}   # rig instance id -> squared camera distance


static func _budget() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var q: Node = tree.root.get_node_or_null("/root/Quality") if tree else null
	if q and q.has_method("value"):
		var v: Variant = q.call("value", "rig_budget")
		if v != null:
			return int(v)
	return 6


func _check_range() -> void:
	# A duplicated model (e.g. the dialogue portrait copies an NPC's model) carries a
	# copy of this node without its setup: nothing to drive, so remove the copy.
	if _model == null or not is_instance_valid(_model):
		_candidates.erase(get_instance_id())
		queue_free()
		return
	if _camera == null or not is_instance_valid(_camera) or not _camera.current:
		_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := false
	var id := get_instance_id()
	if _camera and not paused and _model.is_visible_in_tree():
		var d2 := _camera.global_position.distance_squared_to(_model.global_position)
		near = d2 < ACTIVE_RANGE * ACTIVE_RANGE
		if near and not always_near:
			_candidates[id] = d2
			var closer := 0
			for other: float in _candidates.values():
				if other < d2:
					closer += 1
			near = closer < _budget()
		else:
			_candidates.erase(id)
	else:
		_candidates.erase(id)
	if near != _near:
		_set_near(near)


func _set_near(on: bool) -> void:
	_near = on
	if on:
		_order_modifiers()
		_measure_rig()
		_weight = 0.0
		_pelvis_off = 0.0
		_has_anim = false
		_hit = [false, false]
		_last_pos = Vector3.INF
		_lean = Vector2.ZERO
		_lean_v = Vector2.ZERO
		for p: Dictionary in _props:
			p["last"] = Vector3.INF
			p["off"] = Vector3.ZERO
			p["off_v"] = Vector3.ZERO
		if _springs:
			_springs.reset()
	else:
		for p: Dictionary in _props:
			if is_instance_valid(p["node"]):
				(p["node"] as Node3D).transform = p["rest"]
	for mod: SkeletonModifier3D in [_pre, _ik, _post, _springs]:
		if mod:
			mod.active = on
	for aik in _arm_ik:
		aik.active = on
		aik.influence = 0.0
	if _ik:
		_ik.influence = 0.0
	set_physics_process(on and _use_ik)


## Look-at first (it aims the head from the animated pose), then this rig's
## stages in order, then the springs. Other modifiers keep their place after.
func _order_modifiers() -> void:
	var index := 0
	for child in _skeleton.get_children():
		if child is LookAtModifier3D:
			_skeleton.move_child(child, index)
			index += 1
	for mod: Node in [_pre, _ik, _arm_ik[0] if _arm_ik.size() == 2 else null, _arm_ik[1] if _arm_ik.size() == 2 else null, _post, _springs]:
		if mod:
			_skeleton.move_child(mod, index)
			index += 1


## World-space leg length and ankle height, from the rest pose at the current
## body scale (children grow; soldiers and villagers differ in height).
func _measure_rig() -> void:
	if not _use_ik:
		return
	var xf := _skeleton.global_transform
	var hip := xf * _skeleton.get_bone_global_rest(_leg[0][0]).origin
	var knee := xf * _skeleton.get_bone_global_rest(_leg[0][1]).origin
	var ankle := xf * _skeleton.get_bone_global_rest(_leg[0][2]).origin
	_leg_len = maxf(hip.distance_to(knee) + knee.distance_to(ankle), 0.1)
	_ankle_rest = clampf(ankle.y - _model.global_position.y, 0.0, _leg_len * 0.2)
	if _ball.size() == 2 and _ball[0] >= 0:
		_ball_rest = maxf((xf * _skeleton.get_bone_global_rest(_ball[0]).origin).y - _model.global_position.y, 0.0)
		var by := _model.global_position.y
		_sole_rest[0] = Vector3(ankle.y - by, _ball_rest, (xf * _skeleton.get_bone_global_rest(_leaf[0]).origin).y - by if _leaf.size() == 2 and _leaf[0] >= 0 else _ball_rest)


# --- Ground probes (physics tick) ---------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _has_anim or suppressed:
		return
	_tick += 1
	if not always_near and (_tick + get_instance_id()) % 2 != 0:
		return   # other characters probe every other tick; the smoothing hides it
	var space := _model.get_world_3d().direct_space_state
	var base_y := _model.global_position.y
	for i in 2:
		var f := _foot_anim[i]
		_query.from = Vector3(f.x, base_y + _leg_len * 0.55, f.z)
		_query.to = Vector3(f.x, base_y - _leg_len * 0.6, f.z)
		var hit := space.intersect_ray(_query)
		_hit[i] = not hit.is_empty()
		if _hit[i]:
			_hit_y[i] = (hit["position"] as Vector3).y
			# A ray that starts inside a collider (foot clipped into geometry for a frame)
			# comes back with normal = Vector3.ZERO -- Godot's own documented behaviour for
			# intersect_ray. That zero vector reached Vector3.slerp() in _pre_modify() below
			# and threw "axis must be normalized" every physics tick (1215x in one soak run,
			# docs/qa/stability.md): keep the last good normal instead of a degenerate one.
			var n: Vector3 = hit["normal"]
			if n.length_squared() > 0.0001:
				_hit_n[i] = n


# --- Modifier stages -----------------------------------------------------------------

func _target_weight() -> float:
	if suppressed or airborne or external_off or not (_hit[0] or _hit[1]):
		return 0.0
	var speed := _owner_speed
	if speed < 0.0:
		speed = Vector2(_vel.x, _vel.z).length()
	var k := maxf(_model.global_basis.get_scale().y, 0.05)
	var w := lerpf(1.0, RUN_WEIGHT, smoothstep(WALK_FULL * k, RUN_REDUCED * k, speed))
	return w * (0.3 if attacking else 1.0)


## After the clip and the look-at: record the animated feet, drop the pelvis to
## the lower foot and place the IK targets and knee poles.
func _pre_modify(delta: float) -> void:
	_track_body(delta)
	if _arms_state != -1 and _torso_yaw_wanted():
		var l := _skeleton.find_bone(ARMS[0][0])
		var r := _skeleton.find_bone(ARMS[1][0])
		if l >= 0 and r >= 0:
			var xa := _skeleton.global_transform
			_axis_anim = (xa * _skeleton.get_bone_global_pose(r).origin) - (xa * _skeleton.get_bone_global_pose(l).origin)
	if absf(_torso_yaw) >= 0.0005:
		_apply_torso_yaw()          # before the arm IK: the hands must reach their targets with the chest already turned
	var xf := _skeleton.global_transform
	var base := _model.global_position
	var fwd := _model.global_basis.z.normalized()
	var hips: Array[Vector3] = []
	var knees: Array[Vector3] = []
	for i in 2:
		hips.append(xf * _skeleton.get_bone_global_pose(_leg[i][0]).origin)
		knees.append(xf * _skeleton.get_bone_global_pose(_leg[i][1]).origin)
		var foot_pose := _skeleton.get_bone_global_pose(_leg[i][2])
		_foot_anim[i] = xf * foot_pose.origin
		_foot_rot[i] = foot_pose.basis.get_rotation_quaternion()
		if i < _ball.size() and _ball[i] >= 0:
			var bp: Vector3 = xf * _skeleton.get_bone_global_pose(_ball[i]).origin
			_ball_off[i] = Vector2(_foot_anim[i].x - bp.x, _foot_anim[i].z - bp.z)
			# sole height proxy: the lowest of ankle, ball and toe tip, each against its own rest height (heel strike and toe-off count)
			var by := _model.global_position.y
			var lo := minf(_foot_anim[i].y - by - _sole_rest[0].x, bp.y - by - _sole_rest[0].y)
			if i < _leaf.size() and _leaf[i] >= 0:
				lo = minf(lo, (xf * _skeleton.get_bone_global_pose(_leaf[i]).origin).y - by - _sole_rest[0].z)
			_ball_lift[i] = lo
			_ball_h[i] = bp.y - by - _sole_rest[0].y
		else:
			_ball_off[i] = Vector2.ZERO
			_ball_lift[i] = _foot_anim[i].y - _model.global_position.y - _ankle_rest
	_has_anim = true
	if _arms_state == 1:
		_arms_pre(xf, fwd)
	_weight = move_toward(_weight, _target_weight(), WEIGHT_RATE * delta)
	var a := 1.0 - exp(-GROUND_RATE * delta)
	var max_drop := _leg_len * 0.38
	var lowest := 0.0
	for i in 2:
		var d := 0.0
		var n := Vector3.UP
		if _hit[i]:
			d = clampf(_hit_y[i] - base.y, -max_drop, _leg_len * 0.5)
			n = _hit_n[i]
		_ground[i] = lerpf(_ground[i], d, a)
		# Vector3.slerp() requires BOTH operands exactly unit-length (it derives a rotation
		# axis internally and asserts on it). A raycast normal off a non-uniformly-scaled
		# collision shape, or one _normal[i] already nudged off unit length by a previous
		# .normalized() float rounding, was enough to trip "axis must be normalized" every
		# physics tick this foot was grounded (still 417x in one soak run after only
		# guarding against a zero vector -- see docs/qa/stability.md). Re-normalize both
		# operands right at the call site instead of trusting upstream state.
		if _normal[i].length_squared() > 0.0001 and n.length_squared() > 0.0001:
			# lerp + normalize, NOT slerp: for two nearly equal normals (flat ground, the
			# common case) Vector3.slerp builds its rotation axis from a tiny cross product
			# that float rounding leaves just off unit length, so the engine printed
			# "axis must be normalized" ~2000x per minute (each print costs ms: 50-100 ms
			# frames in the village, perf_visual 2026-09-28). Same look for small angles.
			_normal[i] = _normal[i].lerp(n, a).normalized()
		elif n.length_squared() > 0.0001:
			_normal[i] = n.normalized()
		var lift := _foot_anim[i].y - base.y - _ankle_rest
		_plant[i] = 1.0 - smoothstep(0.03 * _leg_len, 0.2 * _leg_len, lift)
		_update_lock(i, delta)
		lowest = minf(lowest, _ground[i])
	_pelvis_off = lerpf(_pelvis_off, lowest * _weight, 1.0 - exp(-PELVIS_RATE * delta))
	# Reach: a pinned foot the stretched mocap leg cannot reach any more (half the walk frames were at > 98 % of the leg, the foot
	# then slid 4-5 cm per stance) pulls the pelvis down just enough, capped, eased: the planted foot stays planted.
	var want_drop := 0.0
	for i in 2:
		if _lock_w[i] > 0.001:
			var tgt := _foot_anim[i] + Vector3(0.0, _ground[i], 0.0)
			var lk := Vector2(tgt.x, tgt.z).lerp(_lock_xz[i] + (Vector2.ZERO if _lock_heel[i] else _yawed_off(i)), _lock_w[i])
			var r := Vector2(hips[i].x - lk.x, hips[i].z - lk.y).length()
			var h := hips[i].y + _pelvis_off - tgt.y
			var reach := _leg_len * REACH_MAX
			if r < reach and h > 0.0:
				var h_ok := sqrt(reach * reach - r * r)
				want_drop = maxf(want_drop, (h - h_ok) * _lock_w[i])
	want_drop = minf(want_drop, _leg_len * REACH_DROP_MAX)
	_reach_drop = want_drop if want_drop > _reach_drop else lerpf(_reach_drop, want_drop, 1.0 - exp(-12.0 * delta))
	var pinned := maxf(_lock_w[0], _lock_w[1])
	_ik.influence = maxf(_weight, pinned)       # a pinned foot needs the IK even where the ground blend is off (sprint)
	if _weight <= 0.001 and absf(_pelvis_off) < 0.001 and pinned <= 0.001 and _reach_drop < 0.0005:
		return
	# Pelvis: a world-space drop, converted into its parent bone's space.
	var drop := _skeleton.global_basis.inverse() * Vector3(0.0, _pelvis_off - _reach_drop, 0.0)
	var parent := _skeleton.get_bone_parent(_pelvis)
	if parent >= 0:
		drop = _skeleton.get_bone_global_pose(parent).basis.inverse() * drop
	_skeleton.set_bone_pose_position(_pelvis, _skeleton.get_bone_pose_position(_pelvis) + drop)
	for i in 2:
		var target := _foot_anim[i] + Vector3(0.0, _ground[i], 0.0)
		if _lock_w[i] > 0.001:
			var lk := Vector2(target.x, target.z).lerp(_lock_xz[i] + (Vector2.ZERO if _lock_heel[i] else _yawed_off(i)), _lock_w[i])
			target.x = lk.x
			target.z = lk.y
		_markers[i].global_position = target
		var mid := (hips[i] + _foot_anim[i]) * 0.5
		var bend := knees[i] - mid
		bend = bend.normalized() if bend.length() > 0.02 * _leg_len else fwd
		_markers[i + 2].global_position = knees[i] + Vector3(0.0, _pelvis_off - _reach_drop, 0.0) + (bend + fwd * 0.3).normalized() * _leg_len * 0.6


## Pins foot `i` while its animated sole is planted (see LOCK_*). Player-only (always_near), never while airborne,
## attacking or standing still, so clips that move planted feet on purpose (skids, pivots out of locomotion) are left alone.
func _update_lock(i: int, delta: float) -> void:
	var speed := _owner_speed if _owner_speed >= 0.0 else Vector2(_vel.x, _vel.z).length()
	var k := maxf(_model.global_basis.get_scale().y, 0.05)
	var ok := foot_lock and always_near and not airborne and not suppressed and not external_off and not attacking 			and (_hit[0] or _hit[1]) and speed > LOCK_MIN_SPEED
	var lift := _ball_lift[i] / k
	var planted := ok and (lift < LOCK_ON_LIFT or (_lock_on[i] and lift < LOCK_OFF_LIFT))
	var anim_xz := Vector2(_foot_anim[i].x, _foot_anim[i].z) - _ball_off[i]      # the ball of the foot
	if planted:
		if not _lock_on[i]:
			_lock_on[i] = true
			_lock_heel[i] = _ball_h[i] / k > HEEL_BALL_UP and speed < HEEL_LOCK_MAX_SPEED * k   # walking heel strikes; jogs land on the forefoot
			_lock_xz[i] = Vector2(_foot_anim[i].x, _foot_anim[i].z) if _lock_heel[i] else anim_xz
			_lock_yaw[i] = _foot_yaw(i)
		elif _lock_heel[i] and _ball_h[i] / k < HEEL_BALL_DOWN:
			_lock_heel[i] = false
			_lock_xz[i] = _lock_xz[i] - _ball_off[i]       # the ball where the pinned ankle puts it
		else:
			var lag := _lock_xz[i] - (Vector2(_foot_anim[i].x, _foot_anim[i].z) if _lock_heel[i] else anim_xz)
			if lag.length() > LOCK_MAX * k:
				_lock_xz[i] = (Vector2(_foot_anim[i].x, _foot_anim[i].z) if _lock_heel[i] else anim_xz) + lag.normalized() * LOCK_MAX * k
	else:
		_lock_on[i] = false
	# a sprint stance lasts ~6 frames: the 3-frame blend would eat half of it, so the blend shortens with speed (1 frame at 7.5 m/s)
	var blend := LOCK_BLEND * clampf(2.5 / maxf(speed, 0.1), 0.33, 1.0)
	_lock_w[i] = move_toward(_lock_w[i], lock_gain if _lock_on[i] else 0.0, delta / blend)


## Two-handed weapons: between swings the weapon stands upright beside the body (shortest-arc rotation of its blade axis onto world
## up, weight = carry), during swings the off hand is pulled onto the weapon (spear: forward on the shaft, great weapons: on the pommel).
var _wprops: Array = []     # [{node, rest}] equipped two-handed weapons (EquipmentVisuals sets meta wclass on the prop)


func _update_two_handed(_delta: float) -> void:
	if Engine.get_process_frames() % 20 == 0:
		_wprops = _wprops.filter(func(e: Dictionary) -> bool:
			var nv: Variant = e["node"]
			return is_instance_valid(nv) and (nv as Node).is_inside_tree())
		for att in _skeleton.get_children():
			if att is BoneAttachment3D:
				for c in att.get_children():
					if c is Node3D and c.has_meta(&"wclass") and (c as Node3D).visible:
						var known := false
						for e: Dictionary in _wprops:
							var ev: Variant = e["node"]
							if is_instance_valid(ev) and ev == c:
								known = true
						if not known:
							_wprops.append({"node": c, "rest": (c as Node3D).transform})
	if _wprops.is_empty():
		if _assist_w[0] > 0.0:
			set_hand_assist(0, Vector3.ZERO, 0.0)
		return
	for e: Dictionary in _wprops:
		var nv: Variant = e["node"]
		if not is_instance_valid(nv):
			continue
		var node := nv as Node3D
		if node.visible:
			node.transform = _two_hand_rest(node, e["rest"])


func _two_hand_rest(node: Node3D, rest: Transform3D) -> Transform3D:
	var wc := String(node.get_meta(&"wclass"))
	if wc != "polearm" and wc != "great" and wc != "torch":
		return rest
	var parent := node.get_parent_node_3d()
	if parent == null:
		return rest
	var ax: Vector3 = node.get_meta(&"axis", Vector3.UP)
	# the attachment follows its bone only after the modifier stack: take the live bone pose (its global_basis is last frame's)
	var pxf := parent.global_transform
	if parent is BoneAttachment3D:
		var bi := _skeleton.find_bone((parent as BoneAttachment3D).bone_name)
		if bi >= 0:
			pxf = _skeleton.global_transform * _skeleton.get_bone_global_pose(bi)
	var pb := pxf.basis
	var cur := pb * rest.basis
	var axis_w := (cur * ax).normalized()
	if _carry_w > 0.001:
		# The carried pose is defined by the body, not by the shortest arc from the hand (that arc flipped about the blade axis by
		# ~90 deg in one frame when the jump arms turned the blade near straight down): blade axis up, its flat along the body's side.
		if not node.has_meta(&"thin_i"):
			var bx := _local_box(node)
			var ai := 0 if absf(ax.x) > 0.5 else (2 if absf(ax.z) > 0.5 else 1)
			var o1 := (ai + 1) % 3
			var o2 := (ai + 2) % 3
			node.set_meta(&"thin_i", o1 if bx.size[o1] <= bx.size[o2] else o2)
		var ti := int(node.get_meta(&"thin_i"))
		var right := _model.global_basis.x.normalized()
		var ai2 := 0 if absf(ax.x) > 0.5 else (2 if absf(ax.z) > 0.5 else 1)
		var sgn := signf(ax[ai2])
		var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		cols[ai2] = Vector3.UP * sgn
		# the thin axis keeps the side it currently points to (no half-turn), flat faces the body's side
		if not node.has_meta(&"thin_sign"):
			# decided once, in the pose the weapon is first carried in (idle): later flips of the hand must not flip the carry
			node.set_meta(&"thin_sign", 1.0 if (cur.orthonormalized() * _axis(ti)).dot(right) >= 0.0 else -1.0)
		cols[ti] = right * float(node.get_meta(&"thin_sign"))
		var oi := 3 - ai2 - ti
		cols[oi] = cols[(oi + 1) % 3].cross(cols[(oi + 2) % 3])
		var target := Basis(cols[0], cols[1], cols[2]).orthonormalized()
		var q := cur.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), _carry_w)
		rest.basis = pb.inverse() * Basis(q).scaled(cur.get_scale())
		axis_w = (pb * rest.basis * ax).normalized()
	if wc == "torch":
		return rest                  # upright only: the off hand holds it, nothing to assist
	var assist := 1.0 - _carry_w
	_set_assist_now((pxf * rest).origin + axis_w * float(node.get_meta(&"grip2", 0.4)), assist if assist > 0.01 else 0.0)
	return rest


func _set_assist_now(point: Vector3, weight: float) -> void:
	set_hand_assist(0, point, weight)


func _torso_yaw_wanted() -> bool:
	return always_near          # only the player's rig measures its shoulder line (WallContact squares the chest to a wall)


## Chest yaw from set_torso_yaw_offset: the spine bones turn about world up (the neck is left alone).
func _apply_torso_yaw() -> void:
	var skel_q := _skeleton.global_basis.get_rotation_quaternion()
	for entry: Array in _torso:
		var share: float = entry[1]
		if share <= 0.0:
			continue
		var bone: int = entry[0]
		var q_skel := skel_q.inverse() * Quaternion(Vector3.UP, _torso_yaw * share / 0.9) * skel_q
		var parent := _skeleton.get_bone_parent(bone)
		var parent_q := _skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var bone_q := _skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * q_skel * bone_q).normalized())


## Arm IK targets: the animated hand pulled toward the brace point by its weight; the elbow keeps the bend it had.
func _arms_pre(xf: Transform3D, fwd: Vector3) -> void:
	for s in 2:
		var w := _brace_w[s]
		var bp := _brace_pt[s]
		if _assist_w[s] > w:
			w = _assist_w[s]
			bp = _assist_pt[s]
		if _load_w[s] > 0.001:
			w = _load_w[s]
			bp = _load_pt[s]
		var ik := _arm_ik[s]
		var shoulder := xf * _skeleton.get_bone_global_pose(_arm[s][0]).origin
		var hand_pose := _skeleton.get_bone_global_pose(_arm[s][2])
		var hand := xf * hand_pose.origin
		_brace_rot[s] = hand_pose.basis.get_rotation_quaternion()
		if w <= 0.001:
			ik.influence = 0.0
			continue
		ik.influence = 1.0
		_arm_markers[s].global_position = hand.lerp(bp, w)
		var side := -1.0 if s == 0 else 1.0
		var out := fwd.cross(Vector3.UP).normalized() * side      # away from the body on this side
		# elbows point out, back and down (a push against a wall, arms out to the sides): the pole sits there, relative to the shoulder
		_arm_markers[s + 2].global_position = shoulder + out * 0.45 - fwd * 0.3 - Vector3.UP * 0.4


## After the IK: tilt the planted feet to the ground, then the torso and prop springs.
func _post_modify(delta: float) -> void:
	var ik_w := maxf(_weight, maxf(_lock_w[0], _lock_w[1]))
	if _use_ik and ik_w > 0.001:
		var skel_q := _skeleton.global_basis.get_rotation_quaternion()
		for i in 2:
			# The solved shin would carry the foot's pitch with it: restore the
			# animated foot orientation, tilted to the ground while planted.
			var tilt := Quaternion(Vector3.UP, _normal[i])
			var angle := tilt.get_angle()
			if angle > MAX_TILT:
				tilt = Quaternion.IDENTITY.slerp(tilt, MAX_TILT / angle)
			tilt = Quaternion.IDENTITY.slerp(tilt, _plant[i])
			var desired := (skel_q.inverse() * tilt * skel_q) * _foot_rot[i]
			if _lock_w[i] > 0.001 and not is_nan(_lock_yaw[i]):
				# a planted foot keeps the heading it landed with: the clip's stance yaw swings the toe sideways (adult walk:
				# 0.28 m/s of the 0.39 m/s slip was lateral, at the toe tip)
				var dy := wrapf(_lock_yaw[i] - _foot_yaw(i), -PI, PI) * _lock_w[i]
				desired = (skel_q.inverse() * Quaternion(Vector3.UP, dy) * skel_q) * desired
			var foot := _leg[i][2]
			var parent_q := _skeleton.get_bone_global_pose(_leg[i][1]).basis.get_rotation_quaternion()
			var foot_q := _skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(foot, (parent_q.inverse() * foot_q.slerp(desired, ik_w)).normalized())
	if _arms_state == 1:
		for s in 2:
			if maxf(maxf(_brace_w[s], _assist_w[s]), _load_w[s]) > 0.001:
				# keep the animated hand orientation (the solved forearm would twist it)
				var hand := _arm[s][2]
				var fa_q := _skeleton.get_bone_global_pose(_arm[s][1]).basis.get_rotation_quaternion()
				var cur_q := _skeleton.get_bone_global_pose(hand).basis.get_rotation_quaternion()
				_skeleton.set_bone_pose_rotation(hand, (fa_q.inverse() * cur_q.slerp(_brace_rot[s], 0.8)).normalized())
	if _use_secondary:
		_torso_spring(delta)
		_prop_springs(delta)
		_holster_pass(delta)     # also on zero-delta re-evaluations of the stack, or the guard would be lost for that pass


## Smoothed world velocity and acceleration of the model (drives the springs and,
## for owners that do not report it, the IK's speed band).
func _track_body(delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := _model.global_position
	if _last_pos != Vector3.INF and pos.distance_to(_last_pos) < 3.0:
		var v := (pos - _last_pos) / delta
		var nv := _vel.lerp(v, 1.0 - exp(-12.0 * delta))
		_acc = _acc.lerp((nv - _vel) / delta, 1.0 - exp(-10.0 * delta))
		_vel = nv
	_last_pos = pos


func _torso_spring(delta: float) -> void:
	if _torso.is_empty() or delta <= 0.0:
		return
	if not _use_ik:
		_track_body(delta)
	var basis := _model.global_basis.orthonormalized()
	var local := basis.inverse() * _acc
	# Speeding up tips the chest back, braking throws it forward, turns roll it outward.
	var goal := Vector2(clampf(-local.z * TORSO_GAIN, -TORSO_MAX, TORSO_MAX), clampf(local.x * TORSO_GAIN, -TORSO_MAX, TORSO_MAX))
	var damp := 2.0 * sqrt(TORSO_STIFF) * TORSO_DAMP
	_lean_v += ((goal - _lean) * TORSO_STIFF - _lean_v * damp) * minf(delta, 0.05)
	_lean += _lean_v * minf(delta, 0.05)
	_lean = _lean.limit_length(TORSO_MAX * 4.0)        # jolts may throw the chest further than acceleration lean does
	if _lean.length() < 0.0005:
		return
	var skel_q := _skeleton.global_basis.get_rotation_quaternion()
	var right := basis.x.normalized()   # must be exactly unit: a scaled model left it at ~0.996 and Quaternion(axis, a) printed "axis must be normalized" twice per call (~16 ms each)
	var fwd := basis.z.normalized()
	for entry: Array in _torso:
		var bone: int = entry[0]
		var share: float = entry[1]
		var q := Quaternion(right, _lean.x * share) * Quaternion(fwd, _lean.y * share)

		var q_skel := skel_q.inverse() * q * skel_q
		var parent := _skeleton.get_bone_parent(bone)
		var parent_q := _skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var bone_q := _skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * q_skel * bone_q).normalized())


## Props on bone attachments trail their grip: the prop centre lags the grip's
## acceleration on a damped spring and the prop turns about the grip to follow.
func _prop_springs(delta: float) -> void:
	if delta <= 0.0:
		return
	var xf := _skeleton.global_transform
	var dt := minf(delta, 0.05)
	_carry_w = move_toward(_carry_w, 1.0 if weapon_carry else 0.0, (WEAPON_CARRY_IN if weapon_carry else WEAPON_CARRY_RATE) * delta)
	_update_two_handed(delta)
	_spring_props(delta, xf, dt)


func _spring_props(delta: float, xf: Transform3D, dt: float) -> void:
	for p: Dictionary in _props:
		var node: Node3D = p["node"]
		if not is_instance_valid(node) or p["bone"] < 0:
			continue
		var rest: Transform3D = p["rest"]
		if _carry_w > 0.001 and String(node.name).begins_with("Sword") and String(_skeleton.get_bone_name(p["bone"])) == "hand_r":
			rest.basis = rest.basis * Basis(Vector3(0, 0, 1), deg_to_rad(WEAPON_CARRY_DEG * _carry_w))

		var bone_xf: Transform3D = xf * _skeleton.get_bone_global_pose(p["bone"])
		var grip := bone_xf.origin
		var last: Vector3 = p["last"]
		p["last"] = grip
		if last == Vector3.INF or grip.distance_to(last) > 2.0:
			continue
		var v: Vector3 = (grip - last) / delta
		var prev_v: Vector3 = p["vel"]
		var nv := prev_v.lerp(v, 1.0 - exp(-20.0 * delta))
		p["vel"] = nv
		var acc := (nv - prev_v) / delta
		# The attachment sits exactly on the bone, so its space is the bone's.
		var att_basis := bone_xf.basis.orthonormalized()
		var r_world: Vector3 = bone_xf.basis * (p["r"] as Vector3)
		var r_len := maxf(r_world.length(), 0.01)
		var goal := (-acc * PROP_GAIN).limit_length(PROP_MAX * r_len)
		var off: Vector3 = p["off"]
		var off_v: Vector3 = p["off_v"]
		var damp := 2.0 * sqrt(PROP_STIFF) * PROP_DAMP
		off_v += ((goal - off) * PROP_STIFF - off_v * damp) * dt
		off = (off + off_v * dt).limit_length(PROP_MAX * r_len * 1.3)
		p["off"] = off
		p["off_v"] = off_v
		# Small rotation that moves the prop centre by `off`: axis r × off, angle |off| / |r|.
		var axis_world := r_world.cross(off) / (r_len * r_len)
		var angle := axis_world.length()
		if angle < 0.0005:
			node.transform = rest
			continue
		var axis_local := att_basis.inverse() * (axis_world / angle)
		node.transform = Transform3D(Basis(axis_local.normalized(), angle), Vector3.ZERO) * rest


# ---------------------------------------------------------------------------------------------------------------------------------
# Back sockets and ground guard (run after every other prop pass, so they see the final hand transform of the frame).

var _hprops: Array = []      # [{node, att, kind, h, rest, managed, corners, box, thin, long, out_sign}]
var _back_frame := {}        # cached: spine_03 / pelvis / neck bones and the body's forward and up in spine_03 bone space


func _holster_refresh() -> void:
	_hprops = _hprops.filter(func(e: Dictionary) -> bool:
		var nv: Variant = e["node"]
		return is_instance_valid(nv) and (nv as Node).is_inside_tree())
	for att in _skeleton.get_children():
		if not att is BoneAttachment3D:
			continue
		var bn := String((att as BoneAttachment3D).bone_name).to_lower()
		if bn != "hand_r" and bn != "hand_l" and bn != "lowerarm_l":
			continue
		for c in att.get_children():
			if not c is Node3D:
				continue
			var known := false
			for e: Dictionary in _hprops:
				if e["node"] == c:
					known = true
					break
			if known:
				continue
			var node := c as Node3D
			var kind := "hand"
			if bn == "lowerarm_l":
				kind = "shield"
			elif node.has_meta(&"wclass") and ["polearm", "great", "bow"].has(String(node.get_meta(&"wclass"))):
				kind = "long"
			var managed := node.has_meta(&"wclass")
			for p: Dictionary in _props:
				if p["node"] == node:
					managed = true
			var box := _local_box(node)
			if box.size.length() < 0.0001:
				continue
			var corners: Array[Vector3] = []
			for k in 8:
				corners.append(box.get_endpoint(k))
			var sz := box.size
			var thin := 0 if sz.x <= sz.y and sz.x <= sz.z else (1 if sz.y <= sz.z else 2)
			var lng := 0 if sz.x >= sz.y and sz.x >= sz.z else (1 if sz.y >= sz.z else 2)
			if node.has_meta(&"axis"):
				var ax: Vector3 = node.get_meta(&"axis")
				lng = 0 if absf(ax.x) > 0.5 else (2 if absf(ax.z) > 0.5 else 1)
				if thin == lng:
					thin = (lng + 1) % 3
			# the grip (the hand bone) in the prop's own space, and which end of the long axis it is on
			var grip_l := node.transform.affine_inverse() * Vector3.ZERO
			var gsign := 1.0 if grip_l[lng] >= box.get_center()[lng] else -1.0
			_hprops.append({"node": node, "att": att, "kind": kind, "h": 0.0, "rest": node.transform, "managed": managed,
					"corners": corners, "box": box, "thin": thin, "long": lng, "out_sign": 0.0, "grip": grip_l, "gsign": gsign})


## AABB of the prop's meshes in the prop node's own space.
static func _local_box(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := node.global_transform.affine_inverse()
	for mi in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := (inv * m.global_transform) * m.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## spine_03 world origin and the body's back / up / right directions in world space (they follow the live spine through a roll).
func _back_basis() -> Dictionary:
	if _back_frame.is_empty():
		var sp := _skeleton.find_bone("spine_03")
		var pel := _skeleton.find_bone("pelvis")
		var nk := _skeleton.find_bone("neck_01")
		var fl := _skeleton.find_bone("foot_l")
		var bl := _skeleton.find_bone("ball_l")
		if sp < 0 or pel < 0 or nk < 0 or fl < 0 or bl < 0:
			_back_frame = {"ok": false}
			return _back_frame
		var r_sp := _skeleton.get_bone_global_rest(sp)
		var up_s := (_skeleton.get_bone_global_rest(nk).origin - r_sp.origin).normalized()     # along the upper back
		var fwd_s := _skeleton.get_bone_global_rest(bl).origin - _skeleton.get_bone_global_rest(fl).origin
		fwd_s = (fwd_s - up_s * fwd_s.dot(up_s)).normalized()
		var inv := r_sp.basis.inverse()
		# the point of the spine line (pelvis..neck) level with spine_03 in the rest pose, kept in spine_03 bone space: the socket rides
		# that bone rigidly (no drift when the spine curls in a roll)
		var pel_r := _skeleton.get_bone_global_rest(pel).origin
		var ab_r := _skeleton.get_bone_global_rest(nk).origin - pel_r
		var line_r := pel_r + ab_r * clampf((r_sp.origin - pel_r).dot(ab_r) / maxf(ab_r.length_squared(), 1e-9), 0.0, 1.0)
		_back_frame = {"ok": true, "sp": sp, "fwd": (inv * fwd_s).normalized(), "up": (inv * up_s).normalized(),
				"line": r_sp.affine_inverse() * line_r}
	if not bool(_back_frame["ok"]):
		return _back_frame
	var xf := _skeleton.global_transform
	var spx := xf * _skeleton.get_bone_global_pose(_back_frame["sp"])
	var b := spx.basis
	var up := (b * (_back_frame["up"] as Vector3)).normalized()
	var fwd := (b * (_back_frame["fwd"] as Vector3)).normalized()
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var pel_w := xf * _skeleton.get_bone_global_pose(_skeleton.find_bone("pelvis")).origin
	return {"ok": true, "o": spx.origin, "up": up, "back": -fwd, "right": up.cross(fwd).normalized(), "line": spx * (_back_frame["line"] as Vector3), "pel": pel_w}


func _holster_pass(delta: float) -> void:
	if Engine.get_process_frames() % 20 == 0 or _hprops.is_empty():
		_holster_refresh()
	if _hprops.is_empty():
		return
	var bb := _back_basis()
	for e: Dictionary in _hprops:
		var nv: Variant = e["node"]
		if not is_instance_valid(nv):
			continue
		var node := nv as Node3D
		if not node.is_visible_in_tree():
			continue
		if delta <= 0.0 and e.has("pre"):
			node.transform = e["pre"]          # a re-evaluation of the stack: start from this frame's hand transform again
		elif not bool(e["managed"]):
			node.transform = e["rest"]
		e["pre"] = node.transform
		var kind := String(e["kind"])
		var want := 0.0
		if kind == "shield" and shield_slung:
			want = 1.0
		elif kind == "long" and (long_holster or sheathed):
			want = 1.0
		elif kind == "hand" and sheathed and String((e["att"] as BoneAttachment3D).bone_name).to_lower() == "hand_r":
			want = 1.0
		var h: float = move_toward(float(e["h"]), want, HOLSTER_RATE * delta)
		_roll_gap = move_toward(_roll_gap, ROLL_GAP if long_holster else 0.0, 0.4 * delta)
		e["h"] = h
		var att := e["att"] as BoneAttachment3D
		# the attachment follows the bone only after the modifier stack (skeleton_updated): use the live bone pose, not att's transform
		var bi := _skeleton.find_bone(att.bone_name)
		if bi < 0:
			continue
		var att_g := _skeleton.global_transform * _skeleton.get_bone_global_pose(bi)
		e["att_g"] = att_g
		if h > 0.0005 and bool(bb.get("ok", false)):
			var hand_g := att_g * node.transform
			var box: AABB = e["box"]
			if float(e["out_sign"]) == 0.0:
				# which side of the thin axis faces away from the bone it is worn on (the shield's boss)
				var tw := hand_g.basis.orthonormalized() * _axis(int(e["thin"]))
				e["out_sign"] = 1.0 if tw.dot(hand_g * box.get_center() - att_g.origin) >= 0.0 else -1.0
			var sock := _socket(e, bb, hand_g)
			var k := h * h * (3.0 - 2.0 * h)
			var q := hand_g.basis.get_rotation_quaternion().slerp(sock.basis.get_rotation_quaternion(), k)
			var c_hand := hand_g * box.get_center()
			var c_sock := sock * box.get_center()
			var side: Vector3 = -(bb["right"] as Vector3) if kind == "shield" else (bb["right"] as Vector3)
			# the path swings out past the shoulder and behind, never through the chest (to the hip: in front of the body)
			var arc := (side * 0.28 + (bb["back"] as Vector3) * 0.12 + (bb["up"] as Vector3) * 0.08) * sin(PI * k)
			if kind == "hand":
				arc = (-(bb["back"] as Vector3) * 0.22 + (bb["up"] as Vector3) * 0.05) * sin(PI * k)
			var basis := Basis(q).scaled(hand_g.basis.get_scale())
			node.transform = att_g.affine_inverse() * Transform3D(basis, c_hand.lerp(c_sock, k) + arc - basis * box.get_center())
		_ground_guard(e, node)


## While rolling (long_holster) the back curls: slung props stand a little further off it so the curled shoulders do not swallow them.
const ROLL_GAP := 0.05
var _roll_gap := 0.0


static func _axis(i: int) -> Vector3:
	return Vector3.RIGHT if i == 0 else (Vector3.UP if i == 1 else Vector3.BACK)


## World transform of a prop on the back: thin axis (outside out) along the body's back direction, long axis up (shield) or
## diagonal with the grip over the right shoulder (long weapons), inner face BACK_GAP behind the spine line at spine_03.
func _socket(e: Dictionary, bb: Dictionary, hand_g: Transform3D) -> Transform3D:
	var up: Vector3 = bb["up"]
	var back: Vector3 = bb["back"]
	var right: Vector3 = bb["right"]
	var box: AABB = e["box"]
	var scl := hand_g.basis.get_scale()
	var ti := int(e["thin"])
	var li := int(e["long"])
	var oi := 3 - ti - li
	if String(e["kind"]) == "hand":
		return _hip_socket(e, bb, hand_g)
	var is_long := String(e["kind"]) == "long"
	var long_dir := up
	var lsign := 1.0
	if is_long:
		long_dir = (up * cos(deg_to_rad(BACK_DIAG_DEG)) - right * sin(deg_to_rad(BACK_DIAG_DEG))).normalized()
		# the grip end goes up (over the shoulder)
		lsign = float(e["gsign"])
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[ti] = back * float(e["out_sign"])
	cols[li] = long_dir * lsign
	cols[oi] = cols[(oi + 1) % 3].cross(cols[(oi + 2) % 3])
	var basis := Basis(cols[0], cols[1], cols[2]).orthonormalized()
	var half_thin := box.size[ti] * 0.5 * scl[ti]
	var centre := (bb["line"] as Vector3) + back * (BACK_GAP + half_thin + _roll_gap) + up * (0.04 if not is_long else 0.0)
	var b_scaled := basis.scaled(scl)
	return Transform3D(b_scaled, centre - b_scaled * box.get_center())


const HIP_OUT := 0.2       # m from the pelvis to the scabbard, sideways
const HIP_TILT_DEG := 25.0
const HIP_TILT_SEATED_DEG := 78.0


func _hip_socket(e: Dictionary, bb: Dictionary, hand_g: Transform3D) -> Transform3D:
	var up: Vector3 = bb["up"]
	var back: Vector3 = bb["back"]
	var side: Vector3 = bb["right"]      # the left hip ("right" = up x forward points to the character's left; verified in sheet_unarmed)
	var box: AABB = e["box"]
	var scl := hand_g.basis.get_scale()
	var ti := int(e["thin"])
	var li := int(e["long"])
	var oi := 3 - ti - li
	var tilt := deg_to_rad(lerpf(HIP_TILT_DEG, HIP_TILT_SEATED_DEG, seated))
	var grip_dir := (up * cos(tilt) - back * sin(tilt)).normalized()   # grip up and forward
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[li] = grip_dir * float(e["gsign"])      # the grip end up and forward: the blade points down and back
	cols[ti] = side
	cols[oi] = cols[(oi + 1) % 3].cross(cols[(oi + 2) % 3])
	var basis := Basis(cols[0], cols[1], cols[2]).orthonormalized().scaled(scl)
	var grip := (bb["pel"] as Vector3) + side * HIP_OUT + up * lerpf(0.04, 0.12, seated) - back * 0.04
	return Transform3D(basis, grip - basis * (e["grip"] as Vector3))


## A hand prop whose lowest corner goes below the floor is turned about its grip (the bone) just enough to clear it.
func _ground_guard(e: Dictionary, node: Node3D) -> void:
	if is_nan(ground_guard_y):
		return
	var floor_y := ground_guard_y + GUARD_MARGIN
	var att_g: Transform3D = e["att_g"]
	var g := att_g * node.transform
	var lp := _lowest(e, g)
	if lp.y >= floor_y:
		return
	if float(e["h"]) > 0.5:
		# on the back: the body rolls over it, so it is lifted off the back (straight up = away from a back that faces the floor)
		g.origin.y += floor_y - lp.y
		node.transform = att_g.affine_inverse() * g
		return
	var pivot := att_g.origin
	for _iter in 4:
		var r := lp - pivot
		var need := floor_y - lp.y
		if need <= 0.0:
			break
		var horiz := Vector3(r.x, 0.0, r.z)
		var axis := horiz.cross(Vector3.UP)
		if axis.length() < 1e-4 or horiz.length() < 0.05:
			break
		var rot := Basis(axis.normalized(), clampf(need / horiz.length(), 0.0, 1.0))
		g = Transform3D(rot * g.basis, pivot + rot * (g.origin - pivot))
		lp = _lowest(e, g)
	if lp.y < floor_y:
		g.origin.y += floor_y - lp.y      # what the turn could not clear (prop hanging straight down from a low hand)
	node.transform = att_g.affine_inverse() * g


static func _lowest(e: Dictionary, g: Transform3D) -> Vector3:
	var low := Vector3(0, INF, 0)
	for p: Vector3 in e["corners"]:
		var w := g * p
		if w.y < low.y:
			low = w
	return low


## While the rig is paused (death: the ragdoll drives the bones) the owner calls this each frame after physics: every hand prop is
## kept above floor_y the same way (turned about its grip), from the attachment's live transform.
func guard_props_now(floor_y: float) -> void:
	if _skeleton == null:
		return
	if _hprops.is_empty() or Engine.get_process_frames() % 20 == 0:
		_holster_refresh()
	var keep := ground_guard_y
	ground_guard_y = floor_y
	for e: Dictionary in _hprops:
		var nv: Variant = e["node"]
		if not is_instance_valid(nv) or not (nv as Node3D).is_visible_in_tree():
			continue
		e["att_g"] = (e["att"] as Node3D).global_transform
		e["h"] = 0.0 if float(e["h"]) < 0.5 else e["h"]
		_ground_guard(e, nv as Node3D)
	ground_guard_y = keep


## Impact on the torso spring (hit reactions, a blow on the shield): the chest is thrown along `world_dir` (away from the attacker)
## by a velocity kick and springs back. Reads on top of any clip; strength ~ rad/s (3 = a light hit, 6 = a heavy one).
func jolt(world_dir: Vector3, strength: float) -> void:
	if _model == null:
		return
	var local := _model.global_basis.orthonormalized().inverse() * world_dir
	_lean_v += Vector2(local.z, local.x).limit_length(1.0) * strength


## World yaw of the animated foot (heel to ball direction), radians.
func _foot_yaw(i: int) -> float:
	var fw := Vector2(-_ball_off[i].x, -_ball_off[i].y)     # ball minus ankle, world xz
	return atan2(fw.x, fw.y) if fw.length_squared() > 1e-6 else 0.0


## The ankle's offset from the ball (world xz) with the foot turned back to the heading it was planted with.
func _yawed_off(i: int) -> Vector2:
	if is_nan(_lock_yaw[i]) or _lock_w[i] <= 0.001:
		return _ball_off[i]
	var dy := wrapf(_lock_yaw[i] - _foot_yaw(i), -PI, PI) * _lock_w[i]
	var o := _ball_off[i]
	return Vector2(o.x * cos(dy) + o.y * sin(dy), -o.x * sin(dy) + o.y * cos(dy))
