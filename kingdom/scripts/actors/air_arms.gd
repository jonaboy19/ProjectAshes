class_name AirArms
extends RefCounted
## The CMU-derived jump clips throw both arms overhead at the apex (the left-arm shield then flies above the head). This pulls the
## shoulder / arm tracks of the air clips part of the way back to the standing Idle arm pose, once per library build.
const CLIPS := ["Jump_Start", "Jump_Rise", "Jump_Fall", "Jump_Running_Start", "Jump_Land_Soft", "Jump_Land_Running"]
const BONES := ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]
const KEEP := 0.4          # fraction of the clip's own arm rotation that remains


static func soften(lib: AnimationLibrary) -> void:
	if not lib.has_animation(&"Idle"):
		return
	var idle: Animation = lib.get_animation(&"Idle")
	for clip: String in CLIPS:
		if not lib.has_animation(StringName(clip)):
			continue
		var a: Animation = lib.get_animation(StringName(clip))
		if a.has_meta(&"air_arms"):
			continue
		a.set_meta(&"air_arms", true)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var path := String(a.track_get_path(t))
			var bone := path.get_slice(":", 1) if path.contains(":") else ""
			if not BONES.has(bone):
				continue
			var it := idle.find_track(a.track_get_path(t), Animation.TYPE_ROTATION_3D)
			if it < 0 or idle.track_get_key_count(it) == 0:
				continue
			var q0: Quaternion = idle.track_get_key_value(it, 0)
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, q0.slerp(q, KEEP).normalized())
