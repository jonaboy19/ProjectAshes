class_name RootExtract
extends RefCounted
## Root-motion extraction for traversal clips whose travel lives in the pelvis (Mixamo "_root" takes with the root track off):
## the pelvis position track keeps only the motion around a moving root, and the root's path (pelvis travel relative to frame 0,
## in pelvis-parent track space) is stored on the animation as meta "root_path" ([[t, Vector3], ...]). The owner (traversal.gd)
## moves the capsule along that path, so the clip's last pose ends standing over the capsule and blends into idle with no pop.
## Applied once per library build (Assets._ual_for) to CLIPS.

const CLIPS := {"Mx_Trav_Ladder_Top_Exit": true}
const STEP := 1.0 / 30.0


static func apply(lib: AnimationLibrary) -> int:
	var n := 0
	for clip: String in CLIPS:
		if not lib.has_animation(StringName(clip)):
			continue
		var a: Animation = lib.get_animation(StringName(clip))
		if a.has_meta(&"root_path"):
			continue
		var tr := -1
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":pelvis"):
				tr = t
				break
		if tr < 0 or a.track_get_key_count(tr) < 2:
			continue
		var p0: Vector3 = a.position_track_interpolate(tr, 0.0)
		# root = pelvis travel: horizontal in full, vertical as a running maximum (the climb up, never the crouch dips), so the
		# pelvis keeps its bob relative to the root
		var path: Array = []
		var tt := 0.0
		var up := 0.0
		while tt <= a.length + 0.0001:
			var d: Vector3 = a.position_track_interpolate(tr, minf(tt, a.length)) - p0
			up = maxf(up, d.y)
			path.append([tt, Vector3(d.x, up, d.z)])
			tt += STEP
		for k in a.track_get_key_count(tr):
			var kt := a.track_get_key_time(tr, k)
			var v: Vector3 = a.track_get_key_value(tr, k)
			a.track_set_key_value(tr, k, v - at(path, kt))
		a.set_meta(&"root_path", path)
		_calm_arms(lib, a)
		n += 1
	return n


## The root offset at time t (pelvis-parent track space), linearly interpolated.
static func at(path: Array, t: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var i := clampi(int(t / STEP), 0, path.size() - 1)
	var j := mini(i + 1, path.size() - 1)
	var a: Array = path[i]
	var b: Array = path[j]
	var w := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
	return (a[1] as Vector3).lerp(b[1] as Vector3, w)


## The top-out's arms fly wide as the body stands up (reads as a flail): from ARMS_FROM the arm tracks ease into the Idle arm pose
## (ARMS_TO fully), the climb part keeps its grips.
const ARMS_FROM := 1.6
const ARMS_TO := 2.5
const ARM_BONES := ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]


static func _calm_arms(lib: AnimationLibrary, a: Animation) -> void:
	if not lib.has_animation(&"Idle"):
		return
	var idle: Animation = lib.get_animation(&"Idle")
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(a.track_get_path(t))
		var bone := path.get_slice(":", 1) if path.contains(":") else ""
		if not ARM_BONES.has(bone):
			continue
		var it := idle.find_track(a.track_get_path(t), Animation.TYPE_ROTATION_3D)
		if it < 0 or idle.track_get_key_count(it) == 0:
			continue
		var q0: Quaternion = idle.track_get_key_value(it, 0)
		for k in a.track_get_key_count(t):
			var kt := a.track_get_key_time(t, k)
			var w := smoothstep(ARMS_FROM, ARMS_TO, kt)
			if w > 0.0:
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, q.slerp(q0, w).normalized())
