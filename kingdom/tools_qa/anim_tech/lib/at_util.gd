extends RefCounted
## Small shared helpers for the anim_tech libs (no class_name; preload it).
##   const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")


## First clip in `candidates` that `ap` has (exact name first, then case-insensitive
## substring), or "" -- lets demos ask for "a hit flinch" and pick up new libraries by name.
static func find_clip(ap: AnimationPlayer, candidates: Array) -> String:
	var list := ap.get_animation_list()
	for c: String in candidates:
		if ap.has_animation(c):
			return c
	for c: String in candidates:
		var low := c.to_lower()
		for n in list:
			if String(n).to_lower().contains(low):
				return String(n)
	return ""


static func skeleton_of(model: Node) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


## Which bone-local axis (0..5 = +X,-X,+Y,-Y,+Z,-Z) of `bone` points closest to the
## world direction `dir` in the rest pose.
static func local_axis_towards(sk: Skeleton3D, bone: int, dir: Vector3) -> int:
	var basis := (sk.global_transform.basis * sk.get_bone_global_rest(bone).basis).orthonormalized()
	var d := basis.inverse() * dir.normalized()
	var best := 0
	var best_dot := -2.0
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for i in 6:
		var dt: float = (axes[i] as Vector3).dot(d)
		if dt > best_dot:
			best_dot = dt
			best = i
	return best


## Ground height under `pos` on collision layer 1 (or `fallback`).
static func ground_y(world: World3D, pos: Vector3, fallback := 0.0, from_above := 3.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * from_above, pos + Vector3.DOWN * 6.0, 1)
	var hit := world.direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else fallback


## Additive copy of `src` for AnimationTree Add2 / OneShot(ADD). Wanted local delta per key:
## rotation `ref^-1 * key` (right-multiplied), position `key - ref`; `ref_time` picks the reference pose (0 = first
## frame); `bones` keeps only those bone names (empty = all); `identity` writes the zero delta (every key the identity);
## `invert` flips the delta (a recoil the opposite way).
##
## AnimationTree stores every skeleton track as a delta from the bone's REST pose (rest^-1 * value, value - rest.origin)
## and Add2 accumulates that, so the values written here are `rest * delta` / `rest.origin + delta`. Pass the
## skeleton (`sk`) whose rest poses apply; without it the deltas are written raw (only right for a rest-identity rig).
static func make_additive(src: Animation, ref_time := 0.0, bones: PackedStringArray = [], sk: Skeleton3D = null, identity := false, invert := false) -> Animation:
	var out := src.duplicate(true) as Animation
	out.loop_mode = Animation.LOOP_NONE
	for t in range(out.get_track_count() - 1, -1, -1):
		var ty := out.track_get_type(t)
		var path := String(out.track_get_path(t))
		var bone := path.substr(path.find(":") + 1) if path.contains(":") else ""
		if not bones.is_empty() and not bones.has(bone):
			out.remove_track(t)
			continue
		var rest := Transform3D.IDENTITY
		if sk != null and sk.find_bone(bone) >= 0:
			rest = sk.get_bone_rest(sk.find_bone(bone))
		var rest_q := rest.basis.get_rotation_quaternion()
		if ty == Animation.TYPE_ROTATION_3D:
			var ref: Quaternion = out.rotation_track_interpolate(t, ref_time)
			for k in out.track_get_key_count(t):
				var q: Quaternion = out.track_get_key_value(t, k)
				var delta := Quaternion.IDENTITY if identity else (ref.inverse() * q).normalized()
				if invert:
					delta = delta.inverse()
				out.track_set_key_value(t, k, (rest_q * delta).normalized())
		elif ty == Animation.TYPE_POSITION_3D:
			var refp: Vector3 = out.position_track_interpolate(t, ref_time)
			for k in out.track_get_key_count(t):
				var delta_p := Vector3.ZERO if identity else (out.track_get_key_value(t, k) as Vector3) - refp
				if invert:
					delta_p = -delta_p
				out.track_set_key_value(t, k, rest.origin + delta_p)
		elif ty == Animation.TYPE_SCALE_3D:
			out.remove_track(t)
	return out

## All bones under `bone` (inclusive), by index.
static func subtree(sk: Skeleton3D, bone: int) -> PackedInt32Array:
	var out := PackedInt32Array([bone])
	var i := 0
	while i < out.size():
		out.append_array(sk.get_bone_children(out[i]))
		i += 1
	return out


const FREE_DIR := "res://assets/incoming/animations_free/"
const FREE2_DIR := "res://assets/incoming/animations_free2/"
## Player-local library that import_clips() fills, so the shared Assets cache is never touched.
const LIB := "at"


## Skeleton path relative to the animation root (what the clip tracks must start with).
static func sk_path(ap: AnimationPlayer, sk: Skeleton3D) -> String:
	return String(ap.get_node(ap.root_node).get_path_to(sk))


## Copies clips out of a GLB AnimationLibrary (animations_free*/...) into the player's own "at" library and
## returns the names as they must be played ("at/<name>"). Track paths are rewritten to this character's
## skeleton. `root_motion` re-enables the (normally disabled) root position track on the copy.
static func import_clips(ap: AnimationPlayer, sk: Skeleton3D, glb: String, names: Array, root_motion := false) -> Array[String]:
	var out: Array[String] = []
	if not ResourceLoader.exists(glb):
		push_warning("anim_tech: missing " + glb)
		return out
	var inst: Node = (load(glb) as PackedScene).instantiate()
	var src_found := inst.find_children("*", "AnimationPlayer", true, false)
	if src_found.is_empty():
		inst.free()
		return out
	var src: AnimationPlayer = src_found[0]
	var lib: AnimationLibrary
	if ap.has_animation_library(LIB):
		lib = ap.get_animation_library(LIB)
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library(LIB, lib)
	var sk_p := sk_path(ap, sk)
	for n: String in names:
		if lib.has_animation(n):
			out.append(LIB + "/" + n)
			continue
		if not src.has_animation(n):
			push_warning("anim_tech: %s has no clip %s" % [glb, n])
			continue
		var a: Animation = src.get_animation(n).duplicate(true)
		for t in a.get_track_count():
			var tp := String(a.track_get_path(t))
			var colon := tp.find(":")
			if colon > 0:
				a.track_set_path(t, NodePath(sk_p + tp.substr(colon)))
				if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
					a.track_set_enabled(t, root_motion)
		lib.add_animation(n, a)
		out.append(LIB + "/" + n)
	inst.free()
	return out


## Index of the `:root` position track of `a` (-1 if none).
static func root_track(a: Animation) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":root"):
			return t
	return -1


## Root position at time `t` (skeleton space, metres; UAL faces +Z), Vector3.ZERO without a root track.
static func root_at(a: Animation, t: float) -> Vector3:
	var i := root_track(a)
	return a.position_track_interpolate(i, clampf(t, 0.0, a.length)) if i >= 0 else Vector3.ZERO


## Enables the root track of `a` and points the player's root-motion at it (AnimationMixer.root_motion_track):
## after this get_root_motion_position() returns the per-frame travel and the root bone itself stays put.
static func enable_root_motion(ap: AnimationPlayer, sk: Skeleton3D, a: Animation) -> void:
	var i := root_track(a)
	if i >= 0:
		a.track_set_enabled(i, true)
	ap.root_motion_track = NodePath(sk_path(ap, sk) + ":root")


## Samples where `bone` is (skeleton space) every `step` seconds while `clip` plays on `ap`; used to find
## hit / release frames (speed peaks). Pauses and restores the player. Must be awaited.
static func sample_bone(ap: AnimationPlayer, sk: Skeleton3D, clip: String, bone: String, step := 1.0 / 30.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var b := sk.find_bone(bone)
	var a := ap.get_animation(clip)
	ap.play(clip)
	ap.pause()
	var t := 0.0
	while t <= a.length + 0.0001:
		ap.seek(t, true)
		out.append(sk.get_bone_global_pose(b).origin)
		t += step
	ap.stop()
	return out


## {time, speed} of the fastest point of a sampled bone path (m/s), searching t in [t0, t1].
static func peak_speed(path: PackedVector3Array, step := 1.0 / 30.0, t0 := 0.0, t1 := 1e9) -> Dictionary:
	var best := 0.0
	var best_t := 0.0
	for i in range(1, path.size()):
		var t := i * step
		if t < t0 or t > t1:
			continue
		var s := path[i].distance_to(path[i - 1]) / step
		if s > best:
			best = s
			best_t = t
	return {"time": best_t, "speed": best}
