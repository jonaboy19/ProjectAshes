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
var _pelvis_off := 0.0
var _weight := 0.0

# Secondary motion state.
var _last_pos := Vector3.INF
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _props: Array = []            # [{att, node, rest, r, bone, last, vel, off, off_v}]


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
		for mod: Node in [_pre, _ik, _post, _springs]:
			if is_instance_valid(mod) and not mod.is_queued_for_deletion():
				mod.queue_free()


func _check_range() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _camera.current:
		_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := false
	if _camera and not paused and _model.is_visible_in_tree():
		near = _camera.global_position.distance_squared_to(_model.global_position) < ACTIVE_RANGE * ACTIVE_RANGE
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
	for mod: Node in [_pre, _ik, _post, _springs]:
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
			_hit_n[i] = hit["normal"]


# --- Modifier stages -----------------------------------------------------------------

func _target_weight() -> float:
	if suppressed or airborne or not (_hit[0] or _hit[1]):
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
	_has_anim = true
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
		_normal[i] = _normal[i].slerp(n, a).normalized()
		var lift := _foot_anim[i].y - base.y - _ankle_rest
		_plant[i] = 1.0 - smoothstep(0.03 * _leg_len, 0.2 * _leg_len, lift)
		lowest = minf(lowest, _ground[i])
	_pelvis_off = lerpf(_pelvis_off, lowest * _weight, 1.0 - exp(-PELVIS_RATE * delta))
	_ik.influence = _weight
	if _weight <= 0.001 and absf(_pelvis_off) < 0.001:
		return
	# Pelvis: a world-space drop, converted into its parent bone's space.
	var drop := _skeleton.global_basis.inverse() * Vector3(0.0, _pelvis_off, 0.0)
	var parent := _skeleton.get_bone_parent(_pelvis)
	if parent >= 0:
		drop = _skeleton.get_bone_global_pose(parent).basis.inverse() * drop
	_skeleton.set_bone_pose_position(_pelvis, _skeleton.get_bone_pose_position(_pelvis) + drop)
	for i in 2:
		var target := _foot_anim[i] + Vector3(0.0, _ground[i], 0.0)
		_markers[i].global_position = target
		var mid := (hips[i] + _foot_anim[i]) * 0.5
		var bend := knees[i] - mid
		bend = bend.normalized() if bend.length() > 0.02 * _leg_len else fwd
		_markers[i + 2].global_position = knees[i] + Vector3(0.0, _pelvis_off, 0.0) + (bend + fwd * 0.3).normalized() * _leg_len * 0.6


## After the IK: tilt the planted feet to the ground, then the torso and prop springs.
func _post_modify(delta: float) -> void:
	if _use_ik and _weight > 0.001:
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
			var foot := _leg[i][2]
			var parent_q := _skeleton.get_bone_global_pose(_leg[i][1]).basis.get_rotation_quaternion()
			var foot_q := _skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(foot, (parent_q.inverse() * foot_q.slerp(desired, _weight)).normalized())
	if _use_secondary:
		_torso_spring(delta)
		_prop_springs(delta)


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
	if _lean.length() < 0.0005:
		return
	var skel_q := _skeleton.global_basis.get_rotation_quaternion()
	var right := basis.x
	var fwd := basis.z
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
	for p: Dictionary in _props:
		var node: Node3D = p["node"]
		if not is_instance_valid(node) or p["bone"] < 0:
			continue
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
			node.transform = p["rest"]
			continue
		var axis_local := att_basis.inverse() * (axis_world / angle)
		node.transform = Transform3D(Basis(axis_local.normalized(), angle), Vector3.ZERO) * (p["rest"] as Transform3D)
