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
	n += _apply_yaw(lib)
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


## Turn-in-place clips (Mixamo guard turns) rotate the PELVIS, not the root: playing them while the game also turns the model
## would turn twice. For TURN_CLIPS the pelvis yaw about the pelvis-parent up axis (+Y) relative to frame 0 is moved out of the
## pelvis rotation and position tracks and stored as meta "root_yaw" ([[t, radians], ...]); the owner turns the model by it
## (player.gd lock-on pivot), so feet, hips and facing end where the clip ends with no double turn.
const TURN_CLIPS := {"Mx_SnS_Turn": true, "Mx_SnS_Turn_2": true, "Mx_SnS_180_Turn": true, "Mx_SnS_180_Turn_2": true}


static func _twist(q: Quaternion, u: Vector3) -> float:
	# swing-twist: the twist of q about the unit axis u
	var d := Vector3(q.x, q.y, q.z).dot(u)
	if absf(d) < 1e-9 and absf(q.w) < 1e-9:
		return 0.0
	return 2.0 * atan2(d, q.w)


## The pelvis-parent "up" axis in track space: UAL rigs keep the root rotated (Z-up under a -90 deg X root on some exports), so
## +Y cannot be assumed. A standing clip's pelvis sits ~1 m above the root: the dominant axis of its frame-0 position is up.
static func _up_axis(a: Animation, pt: int) -> Vector3:
	if pt < 0:
		return Vector3.UP
	var p0: Vector3 = a.position_track_interpolate(pt, 0.0)
	var i := p0.abs().max_axis_index()
	var u := Vector3.ZERO
	u[i] = signf(p0[i])
	return u


static func _apply_yaw(lib: AnimationLibrary) -> int:
	var n := 0
	for clip: String in TURN_CLIPS:
		if not lib.has_animation(StringName(clip)):
			continue
		var a: Animation = lib.get_animation(StringName(clip))
		if a.has_meta(&"root_yaw"):
			continue
		var rt := -1
		var pt := -1
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			if path.ends_with(":pelvis"):
				if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					rt = t
				elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
					pt = t
		if rt < 0 or a.track_get_key_count(rt) < 2:
			continue
		var u := _up_axis(a, pt)
		var q0: Quaternion = a.rotation_track_interpolate(rt, 0.0)
		var y0 := _twist(q0, u)
		var yaw: Array = []
		var tt := 0.0
		var prev := 0.0
		while tt <= a.length + 0.0001:
			var y := wrapf(_twist(a.rotation_track_interpolate(rt, minf(tt, a.length)), u) - y0, -PI, PI)
			# unwrap: keep the curve continuous through +-180 (the 180 turns)
			while y - prev > PI:
				y -= TAU
			while y - prev < -PI:
				y += TAU
			prev = y
			yaw.append([tt, y])
			tt += STEP
		for k in a.track_get_key_count(rt):
			var kt := a.track_get_key_time(rt, k)
			var r := Quaternion(u, -yaw_at(yaw, kt))
			a.track_set_key_value(rt, k, r * (a.track_get_key_value(rt, k) as Quaternion))
		if pt >= 0:
			var p0: Vector3 = a.position_track_interpolate(pt, 0.0)
			for k in a.track_get_key_count(pt):
				var kt := a.track_get_key_time(pt, k)
				var v: Vector3 = a.track_get_key_value(pt, k)
				var rel := v - p0
				var hor := rel - u * rel.dot(u)
				a.track_set_key_value(pt, k, p0 + u * rel.dot(u) + Basis(u, -yaw_at(yaw, kt)) * hor)
		if u.dot(Vector3.UP) < 0.0 or u.dot(Vector3.UP) == 0.0 and u.dot(Vector3.BACK) < 0.0:
			yaw = yaw.map(func(e: Array) -> Array: return [e[0], -float(e[1])])    # model yaw is about world +Y
		a.set_meta(&"root_yaw", yaw)
		n += 1
	return n


## Root yaw (radians, relative to frame 0) at time t.
static func yaw_at(curve: Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	var i := clampi(int(t / STEP), 0, curve.size() - 1)
	var j := mini(i + 1, curve.size() - 1)
	var a: Array = curve[i]
	var b: Array = curve[j]
	var w := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
	return lerpf(float(a[1]), float(b[1]), w)
