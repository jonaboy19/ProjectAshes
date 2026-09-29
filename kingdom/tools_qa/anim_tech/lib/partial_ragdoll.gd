extends "res://scripts/actors/ragdoll.gd"
## Ragdoll (scripts/actors/ragdoll.gd, unchanged) + a PARTIAL upper-body hit reaction.
##
## hit_react() builds the same capsule bodies from the pose on screen, but simulates only the
## chest, head and both arms (hips + legs stay kinematic, so the feet never leave the animation)
## while the AnimationTree / Player keeps running. The simulator's `influence` is tweened
## 0 -> peak -> 0, so the upper body is knocked by physics and blends back into the clip; the
## bodies are freed afterwards, so an idle actor pays nothing.
##
##   const PartialRagdoll := preload("res://tools_qa/anim_tech/lib/partial_ragdoll.gd")
##   var rd := PartialRagdoll.attach(actor_node3d, model, [anim_player_or_tree])   # same as Ragdoll.attach
##   rd.hit_react(push_world_dir, 3.0)          # light-medium hit; `die()` / `knock_down()` still work
## Note: attach() is inherited and creates a Ragdoll instance, so use PartialRagdoll.attach_partial.
## Unlike die() the mixers are NOT paused here. Costs ~12 body creations per hit (a few ms once) and
## a live simulation for ~0.7 s; count it against Ragdoll.MAX_LIVE like a knockdown.

const UPPER_ROLES := ["chest", "head", "arm_l", "arm_r", "fore_l", "fore_r"]
const PEAK_INFLUENCE := 0.7
const RISE := 0.05
const HOLD := 0.10
const RELEASE := 0.5


static func attach_partial(who: Node3D, model: Node, anim_mixers: Array = []) -> Node:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var r: Node = (load("res://tools_qa/anim_tech/lib/partial_ragdoll.gd") as GDScript).new()
	r.name = "PartialRagdoll"
	r.actor = who
	r.skeleton = skels[0]
	for m: Variant in anim_mixers:
		if m is AnimationMixer:
			r.mixers.append(m)
	who.add_child(r)
	return r


## `push` is the world-space direction the hit pushes the upper body (any length; strength in m/s).
func hit_react(push: Vector3, strength := 3.0, peak := PEAK_INFLUENCE) -> bool:
	if mode != Mode.IDLE or not is_inside_tree():
		return false
	if not acquire(self):
		why = "cap"
		return false
	if not _build():
		release(self)
		why = "rig"
		return false
	_gen += 1
	var gen := _gen
	# bodies are placed on the skeleton pose by the next skeleton update; joints are created when the
	# simulation starts, so let one frame pass first (otherwise the kinematic hips sit at the rest pose)
	await get_tree().process_frame
	await get_tree().physics_frame
	if gen != _gen or _sim == null:
		return false
	var names: Array[StringName] = []
	for b in _bodies:
		if UPPER_ROLES.has(String(b.name).trim_prefix("PB_")):
			names.append(StringName(b.bone_name))
	_sim.influence = 0.0
	_sim.physical_bones_start_simulation(names)
	var dir := push
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -actor.global_basis.z
	for b in _bodies:
		if names.has(StringName(b.bone_name)):
			var role := String(b.name).trim_prefix("PB_")
			var share := 1.0 if role == "chest" else (1.3 if role == "head" else 0.6)
			b.linear_velocity = dir * strength * share + Vector3.UP * 0.3
	var t := create_tween()
	t.tween_property(_sim, "influence", peak, RISE)
	t.tween_interval(HOLD)
	t.tween_property(_sim, "influence", 0.0, RELEASE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		if gen == _gen:
			_free_bodies()
			release(self))
	_blend = t
	return true
