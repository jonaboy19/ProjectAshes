extends Node
## Physical deaths and knockdowns on Godot's built-in PhysicalBoneSimulator3D.
##
## Attach one per actor (Ragdoll.attach); nothing physical exists until it is
## needed. On a death (die) or a heavy hit (knock_down) it builds PhysicalBone3D
## capsules for the main bones from the pose the animation is showing right
## then, starts the simulation, blends the simulator's influence in over
## BLEND_IN and throws the body with the hit at the bone nearest the attacker.
##
## - Deaths simulate for DEATH_SIM_TIME, then the pose is baked into the
##   skeleton (bone poses written from the bodies), the simulator and every
##   body are freed and the actor root is moved under the hips, so a dead actor
##   costs nothing afterwards and its fade-out squashes where it lies.
## - Knockdowns simulate for KNOCK_TIME, then the actor root is moved under the
##   hips, animation resumes (the caller's get-up callback picks the clip) and
##   the influence blends back out over BLEND_OUT before the bodies are freed.
## - At most MAX_LIVE ragdolls simulate at once across the world; past that,
##   or far from the player, or with no world collider under the body (terrain
##   collision only streams around the player), die()/knock_down() return
##   false and the caller plays its canned clip instead.
## - Bodies sit on no layer and only see the world (layer 1). The player also
##   lives on layer 1, so it is added as a collision exception: ragdolls never
##   push the player or block the camera (the camera arm only sweeps layer 1
##   and nothing sees a layer-0 body).
##
## Works on the Meshy 24-bone humanoids (goblin, orc, troll), the Quaternius
## quadrupeds (wolf, boar, bear), the Quaternius fungal brute and the UAL/Mixamo
## style rigs (soldiers, player): ROLES lists candidate bone names per body
## part and the first match wins; rigs with fewer than MIN_BODIES matches
## (e.g. the blight rat) just keep their death clip.
##
## The simulator/influence approach follows godot-demo-projects
## 3d/ragdoll_physics (MIT, see CREDITS.md); bodies here are built at runtime.
##
## Usage (preload, no class_name):
##   const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
##   _ragdoll = Ragdoll.attach(self, model, [_anim])
##   if not (_ragdoll and _ragdoll.die(knockback, attacker_pos)): _play("death")

const MAX_LIVE := 3
const WORLD_MASK := 1
const DEATH_SIM_TIME := 3.0
const KNOCK_TIME := 1.0
const BLEND_IN := 0.12
const BLEND_OUT := 0.35
const RANGE := 45.0               # metres from the player; terrain collision streams ~64 m
const HEAVY_KNOCK := 6.0          # knockback at or above this knocks a living actor down
const MIN_BODIES := 5
const FLOOR_PROBE := 4.0          # metres below the hips a world collider must exist
## [role, bone candidates, tip candidates, radius (x torso length), mass (kg),
##  joint ("" = root, "cone", "hinge"), swing or hinge-bend (deg), twist (deg)]
const ROLES := [
	["hips", ["Hips", "pelvis", "Back"], ["Spine01", "spine_02", "Abdomen", "Torso2"], 0.30, 10.0, "", 0, 0],
	["chest", ["Spine01", "spine_03", "Torso2", "Torso"], ["neck", "neck_01", "Neck", "Neck1"], 0.30, 10.0, "cone", 20, 15],
	["head", ["Head"], ["head_end"], 0.22, 4.0, "cone", 40, 30],
	["arm_l", ["LeftArm", "upperarm_l", "UpperArm.L"], ["LeftForeArm", "lowerarm_l", "LowerArm.L"], 0.11, 2.5, "cone", 70, 30],
	["arm_r", ["RightArm", "upperarm_r", "UpperArm.R"], ["RightForeArm", "lowerarm_r", "LowerArm.R"], 0.11, 2.5, "cone", 70, 30],
	["fore_l", ["LeftForeArm", "lowerarm_l", "LowerArm.L"], ["LeftHand", "hand_l", "Index1.L"], 0.09, 1.5, "cone", 60, 20],
	["fore_r", ["RightForeArm", "lowerarm_r", "LowerArm.R"], ["RightHand", "hand_r", "Index1.R"], 0.09, 1.5, "cone", 60, 20],
	["thigh_l", ["LeftUpLeg", "thigh_l", "UpperLeg.L", "BackLeg.L"], ["LeftLeg", "calf_l", "LowerLeg.L", "BackUpperLeg.L"], 0.15, 5.0, "cone", 45, 15],
	["thigh_r", ["RightUpLeg", "thigh_r", "UpperLeg.R", "BackLeg.R"], ["RightLeg", "calf_r", "LowerLeg.R", "BackUpperLeg.R"], 0.15, 5.0, "cone", 45, 15],
	["shin_l", ["LeftLeg", "calf_l", "LowerLeg.L", "BackUpperLeg.L"], ["LeftFoot", "foot_l", "Foot.L", "BackLowerLeg.L"], 0.12, 3.0, "hinge", 110, 0],
	["shin_r", ["RightLeg", "calf_r", "LowerLeg.R", "BackUpperLeg.R"], ["RightFoot", "foot_r", "Foot.R", "BackLowerLeg.R"], 0.12, 3.0, "hinge", 110, 0],
	["fleg_l", ["FrontUpperLeg.L"], ["FrontLowerLeg.L"], 0.13, 3.0, "cone", 45, 15],
	["fleg_r", ["FrontUpperLeg.R"], ["FrontLowerLeg.R"], 0.13, 3.0, "cone", 45, 15],
	["fshin_l", ["FrontLowerLeg.L"], [], 0.10, 2.0, "hinge", 110, 0],
	["fshin_r", ["FrontLowerLeg.R"], [], 0.10, 2.0, "hinge", 110, 0],
]

## Bones whose own origin is off the body: the capsule starts at the average of
## these instead. The Quaternius quadrupeds hang both hind legs and the torso off
## "Back", whose origin floats well above the animal, so it has to be the hips
## body (or the hind legs would come loose) but its capsule sits at the pelvis.
const SHAPE_START := {"Back": ["BackLeg.L", "BackLeg.R"]}

enum Mode { IDLE, DYING, DOWN, BAKED }

static var _live: Array = []      # owners currently holding a simulation slot

var mode := Mode.IDLE
var actor: Node3D
var skeleton: Skeleton3D
var mixers: Array = []            # AnimationMixers paused while the body is physical
var _mixer_was: Array = []
var _sim: PhysicalBoneSimulator3D
var _bodies: Array[PhysicalBone3D] = []
var _hips: PhysicalBone3D
var _gen := 0                     # invalidates timers of an older run
var _on_get_up := Callable()
var _blend: Tween
var why := ""                     # last reason a ragdoll was refused (debug/tests)


# --- simulation slots (the cap) ---------------------------------------------------

static func acquire(owner: Object) -> bool:
	prune()
	if _live.has(owner):
		return true
	if _live.size() >= MAX_LIVE:
		return false
	_live.append(owner)
	return true


static func release(owner: Object) -> void:
	_live.erase(owner)


static func live_count() -> int:
	prune()
	return _live.size()


static func prune() -> void:
	_live = _live.filter(func(o: Variant) -> bool: return is_instance_valid(o))


static func reset_slots() -> void:
	_live.clear()


## A hit heavy enough to knock a living actor off its feet: a big knockback, or
## the player's parry (player.gd sends the attacker take_damage(0, player, push)).
static func is_heavy(amount: int, from: Node, knockback: Vector3) -> bool:
	if knockback.length() >= HEAVY_KNOCK:
		return true
	return amount == 0 and from != null and is_instance_valid(from) and from.is_in_group("player") \
		and knockback.length_squared() > 0.0


# --- setup ------------------------------------------------------------------------

## Adds a ragdoll controller under `who` for the skeleton inside `model`.
## `anim_mixers` (AnimationPlayer / AnimationTree) are paused while physical.
static func attach(who: Node3D, model: Node, anim_mixers: Array = []) -> Node:
	if model == null:
		return null
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var r: Node = (load("res://scripts/actors/ragdoll.gd") as GDScript).new()
	r.name = "Ragdoll"
	r.actor = who
	r.skeleton = skels[0]
	for m: Variant in anim_mixers:
		if m is AnimationMixer:
			r.mixers.append(m)
	who.add_child(r)
	return r


func _exit_tree() -> void:
	release(self)


func is_physical() -> bool:
	return mode == Mode.DYING or mode == Mode.DOWN


func is_down() -> bool:
	return mode == Mode.DOWN


# --- entry points -----------------------------------------------------------------

## Death: returns false (caller plays its death clip) when capped or unsafe.
func die(knockback := Vector3.ZERO, hit_from := Vector3.INF) -> bool:
	if mode == Mode.DOWN:
		_gen += 1                 # already physical: just stay down for good
		mode = Mode.DYING
		for m: AnimationMixer in mixers:
			m.active = false      # in case the get-up had started
		_blend_to(1.0, BLEND_IN)
		_throw(knockback, hit_from, 0.6)
		_after(DEATH_SIM_TIME, _bake)
		return true
	if mode != Mode.IDLE or not _start(knockback, hit_from):
		return false
	mode = Mode.DYING
	_after(DEATH_SIM_TIME, _bake)
	return true


## Knockdown of a living actor: physical for KNOCK_TIME, then `on_get_up` is
## called (play a get-up clip there) and the pose blends back to animation.
func knock_down(knockback: Vector3, hit_from := Vector3.INF, on_get_up := Callable()) -> bool:
	if mode != Mode.IDLE or not _start(knockback, hit_from):
		return false
	mode = Mode.DOWN
	_on_get_up = on_get_up
	_after(KNOCK_TIME, _recover)
	return true


# --- internals --------------------------------------------------------------------

func _start(knockback: Vector3, hit_from: Vector3) -> bool:
	if not is_inside_tree() or skeleton == null or not skeleton.is_visible_in_tree():
		why = "hidden"
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_squared_to(actor.global_position) > RANGE * RANGE:
		why = "far"
		return false
	if not _floor_below(actor.global_position + Vector3.UP * 0.5, player):
		why = "no floor"
		return false
	if not acquire(self):
		why = "cap"
		return false
	if not _build():
		why = "rig"
		release(self)
		return false
	why = ""
	_gen += 1
	_mixer_was.clear()
	for m: AnimationMixer in mixers:
		_mixer_was.append(m.active)
		m.active = false          # freeze the unsimulated bones (hands, feet, tail)
	if player is CollisionObject3D:
		_sim.physical_bones_add_collision_exception((player as CollisionObject3D).get_rid())
	_sim.influence = 0.0
	_sim.physical_bones_start_simulation()
	_blend_to(1.0, BLEND_IN)
	_throw(knockback, hit_from, 1.0)
	return true


## Velocities rather than impulses: fresh bodies don't have their mass on the
## server yet (same reason as breakable.gd's shards).
func _throw(knockback: Vector3, hit_from: Vector3, scale_by: float) -> void:
	var push := knockback
	push.y = 0.0
	if push.length() < 0.5:
		push = -actor.global_basis.z * 0.5 if hit_from == Vector3.INF else (actor.global_position - hit_from) * Vector3(1, 0, 1)
	var dir := push.normalized() if push.length() > 0.01 else Vector3.BACK
	var strength := clampf(2.0 + knockback.length() * 0.7, 2.0, 8.0) * scale_by
	var at := hit_from + Vector3.UP * 1.1 if hit_from != Vector3.INF else actor.global_position + Vector3.UP
	var hit: PhysicalBone3D = null
	var best := INF
	for b in _bodies:
		var d := _centre(b).distance_squared_to(at)
		if d < best:
			best = d
			hit = b
	for b in _bodies:
		var share := 1.0 if b == hit else 0.35
		b.linear_velocity = dir * strength * share + Vector3.UP * (1.2 * share * scale_by)


## Straight back to animation (e.g. the player respawning): drops any bodies,
## re-enables the mixers and frees the slot, whatever state it was in.
func revive() -> void:
	_gen += 1
	_free_bodies()
	for m: AnimationMixer in mixers:
		if is_instance_valid(m):
			m.active = true
	mode = Mode.IDLE
	release(self)


func _blend_to(influence: float, seconds: float) -> Tween:
	if _blend and _blend.is_valid():
		_blend.kill()
	_blend = create_tween()
	_blend.tween_property(_sim, "influence", influence, seconds)
	return _blend


func _after(seconds: float, what: Callable) -> void:
	var gen := _gen
	get_tree().create_timer(seconds, false, true).timeout.connect(func() -> void:
		if gen == _gen and is_inside_tree():
			what.call())


func _floor_below(from: Vector3, player: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_PROBE, WORLD_MASK)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return not actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _bone(names: Array) -> int:
	for n: String in names:
		var i := skeleton.find_bone(n)
		if i >= 0:
			return i
	return -1


## Builds the bodies from the pose on screen now (not the rest pose: several
## imported rigs have rests far from their animated shape).
func _build() -> bool:
	_free_bodies()
	var picks := []                    # [role row, bone, tip position]
	var used := {}
	for row: Array in ROLES:
		var b := _bone(row[1])
		if b < 0 or used.has(b):
			continue
		used[b] = true
		picks.append([row, b])
	if picks.size() < MIN_BODIES:
		return false
	var poses := {}
	for p: Array in picks:
		poses[p[1]] = skeleton.get_bone_global_pose(p[1])
	# Body size scale: hips (capsule start) to head.
	var hip_b := _bone(ROLES[0][1])
	var head_b := _bone(["Head", "head"])
	if hip_b < 0 or head_b < 0:
		return false
	var ref := _shape_start(hip_b).distance_to(skeleton.get_bone_global_pose(head_b).origin)
	if ref < 1e-4:
		return false
	var side := (skeleton.global_basis.inverse() * actor.global_basis.x).normalized()
	# Physics bodies are never scaled (the server keeps them orthonormal), but
	# Meshy/Quaternius skeletons sit under 0.01-0.6 scaled nodes. So each body's
	# origin is its bone's origin (body_offset has no translation) and shapes /
	# joints are sized in world metres inside the body.
	var s := skeleton.global_basis.get_scale().x
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "RagdollSim"
	skeleton.add_child(_sim)
	for p: Array in picks:
		var row: Array = p[0]
		var b: int = p[1]
		var pose: Transform3D = poses[b]
		var start := _shape_start(b)
		var tip := _tip(b, row[2], pose, ref)
		var seg := tip - start
		var length := seg.length()
		if length < ref * 0.02:
			continue
		var z := -seg / length                     # -Z runs from the joint to the tip
		var x := side - z * side.dot(z)
		if x.length() < 0.1:
			x = Vector3.UP - z * z.y
		x = x.normalized()
		var body_basis := Basis(x, z.cross(x), z)
		var centre := body_basis.inverse() * (start + seg * 0.5 - pose.origin) * s
		var radius := minf(float(row[3]) * ref, length * 0.6) * s
		var len_m := length * s
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + String(row[0])
		pb.bone_name = skeleton.get_bone_name(b)
		# The 1/s cancels the skeleton's scale both ways: bone -> body comes out
		# orthonormal, and body -> bone (what the simulator writes) comes back
		# at the skeleton's scale instead of blowing the mesh up by 1/s.
		pb.body_offset = Transform3D(Basis.from_scale(Vector3.ONE / s) * pose.basis.orthonormalized().inverse() * body_basis, Vector3.ZERO)
		pb.collision_layer = 0
		pb.collision_mask = WORLD_MASK
		pb.mass = float(row[4])
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = 0.15
		pb.angular_damp = 1.5
		pb.can_sleep = true
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = maxf(len_m, radius * 2.05)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), centre)
		pb.add_child(cs)
		_setup_joint(pb, row)
		_sim.add_child(pb)
		_bodies.append(pb)
		if row[0] == "hips":
			_hips = pb
	if _bodies.size() < MIN_BODIES or _hips == null:
		_free_bodies()
		return false
	return true


func _shape_start(b: int) -> Vector3:
	var names: Array = SHAPE_START.get(skeleton.get_bone_name(b), [])
	if names.is_empty():
		return skeleton.get_bone_global_pose(b).origin
	var sum := Vector3.ZERO
	for n: String in names:
		var i := skeleton.find_bone(n)
		if i < 0:
			return skeleton.get_bone_global_pose(b).origin
		sum += skeleton.get_bone_global_pose(i).origin
	return sum / names.size()


func _tip(b: int, names: Array, pose: Transform3D, ref: float) -> Vector3:
	var t := _bone(names)
	if t >= 0 and t != b:
		return skeleton.get_bone_global_pose(t).origin
	var kids := skeleton.get_bone_children(b)
	if kids.size() > 0:
		var o := skeleton.get_bone_global_pose(kids[0]).origin
		if o.distance_to(pose.origin) > ref * 0.05:
			return o
	return pose.origin + pose.basis.y.normalized() * ref * 0.35


## Joint frame sits at the bone's own origin, which is the body origin. A
## quarter turn about Y puts the cone's twist axis (joint X) along the bone and
## the hinge axis (joint Z) on the character's side axis (body X).
func _setup_joint(pb: PhysicalBone3D, row: Array) -> void:
	var kind := String(row[5])
	if kind == "":
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		return
	pb.joint_rotation = Vector3(0, PI * 0.5, 0)
	if kind == "hinge":
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		pb.set("joint_constraints/angular_limit_enabled", true)
		pb.set("joint_constraints/angular_limit_upper", 3.0)
		pb.set("joint_constraints/angular_limit_lower", -float(row[6]))
	else:
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.set("joint_constraints/swing_span", float(row[6]))
		pb.set("joint_constraints/twist_span", float(row[7]))


## Death, after DEATH_SIM_TIME: write the simulated pose into the skeleton and
## drop every body. The actor root moves under the hips first so later effects
## (fade-out squash, loot) happen where the body lies.
func _bake() -> void:
	if _sim == null:
		return
	var world := {}
	for pb in _bodies:
		world[skeleton.find_bone(pb.bone_name)] = pb.global_transform * pb.body_offset.affine_inverse()
	_move_root_under_hips()
	var inv := skeleton.global_transform.affine_inverse()
	var globals := {}
	var stack: Array = Array(skeleton.get_parentless_bones())
	while not stack.is_empty():
		var b: int = stack.pop_back()
		var parent := skeleton.get_bone_parent(b)
		var parent_g: Transform3D = globals.get(parent, Transform3D.IDENTITY)
		var g: Transform3D
		if world.has(b):
			g = inv * (world[b] as Transform3D)
		else:
			g = parent_g * skeleton.get_bone_pose(b)
		globals[b] = g
		var local := parent_g.affine_inverse() * g if parent >= 0 else g
		skeleton.set_bone_pose_position(b, local.origin)
		skeleton.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
		stack.append_array(Array(skeleton.get_bone_children(b)))
	_gen += 1
	mode = Mode.BAKED
	_free_bodies()
	release(self)


## Knockdown, after KNOCK_TIME: stand the actor where the body landed, resume
## animation, blend the physics out, then free it.
func _recover() -> void:
	if _sim == null:
		return
	_move_root_under_hips()
	for i in mixers.size():
		var m: AnimationMixer = mixers[i]
		if is_instance_valid(m):
			m.active = _mixer_was[i] if i < _mixer_was.size() else true
	if _on_get_up.is_valid():
		_on_get_up.call()
	var gen := _gen
	var t := _blend_to(0.0, BLEND_OUT)
	t.tween_callback(func() -> void:
		if gen != _gen:
			return
		_free_bodies()
		mode = Mode.IDLE
		release(self))


func _move_root_under_hips() -> void:
	if _hips == null or not is_instance_valid(actor):
		return
	var h := _centre(_hips)
	var p := actor.global_position
	var player := get_tree().get_first_node_in_group("player")
	var q := PhysicsRayQueryParameters3D.create(Vector3(h.x, maxf(h.y, p.y) + 1.5, h.z), Vector3(h.x, minf(h.y, p.y) - FLOOR_PROBE, h.z), WORLD_MASK)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(q)
	actor.global_position = Vector3(h.x, float(hit["position"].y) if hit else p.y, h.z)


## Middle of a body's capsule (its origin is the bone's, which may be off the body).
func _centre(b: PhysicalBone3D) -> Vector3:
	return (b.get_child(0) as Node3D).global_position if b.get_child_count() > 0 else b.global_position


func _free_bodies() -> void:
	if _blend and _blend.is_valid():
		_blend.kill()
	if _sim and is_instance_valid(_sim):
		if _sim.is_simulating_physics():
			_sim.physical_bones_stop_simulation()
		_sim.queue_free()
	_sim = null
	_bodies.clear()
	_hips = null
