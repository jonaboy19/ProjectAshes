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


## Additive copy of `src` for AnimationTree Add / OneShot(ADD): every rotation key becomes
## `ref^-1 * key` (right-multiplied delta), position keys `key - ref`. `ref_time` picks the
## reference pose (0 = first frame). `bones` keeps only those bone names (empty = all).
static func make_additive(src: Animation, ref_time := 0.0, bones: PackedStringArray = []) -> Animation:
	var out := src.duplicate(true) as Animation
	out.loop_mode = Animation.LOOP_NONE
	for t in range(out.get_track_count() - 1, -1, -1):
		var ty := out.track_get_type(t)
		var path := String(out.track_get_path(t))
		var bone := path.substr(path.find(":") + 1) if path.contains(":") else ""
		if not bones.is_empty() and not bones.has(bone):
			out.remove_track(t)
			continue
		if ty == Animation.TYPE_ROTATION_3D:
			var ref: Quaternion = out.rotation_track_interpolate(t, ref_time)
			for k in out.track_get_key_count(t):
				var q: Quaternion = out.track_get_key_value(t, k)
				out.track_set_key_value(t, k, (ref.inverse() * q).normalized())
		elif ty == Animation.TYPE_POSITION_3D:
			var refp: Vector3 = out.position_track_interpolate(t, ref_time)
			for k in out.track_get_key_count(t):
				out.track_set_key_value(t, k, (out.track_get_key_value(t, k) as Vector3) - refp)
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
