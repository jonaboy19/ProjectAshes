class_name ClipLift
extends RefCounted
## Ground-penetration repair for UAL clips (WP-02, golden gate "ground penetration"): data/anim/clip_lift.json holds, per clip, a
## per-frame pelvis offset (pelvis track-local space, rig units) measured by tools_qa/anim_states/clip_lift_bake.gd so the lowest
## skinned vertex of the body never goes below the ground plane (jumps, landings, turns, rolls whose knees, toes or hands sank
## 2-11 cm). Applied once per library build (Assets._ual_for), like AirArms; anim_qa measures the repaired clips the same way.

const PATH := "res://data/anim/clip_lift.json"
static var _data: Dictionary = {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if p is Dictionary:
				_data = (p as Dictionary).get("clips", {})
	return _data


static func apply(lib: AnimationLibrary) -> int:
	var n := 0
	var d := data()
	for clip: String in d:
		if not lib.has_animation(StringName(clip)):
			continue
		var a: Animation = lib.get_animation(StringName(clip))
		if a.has_meta(&"clip_lift"):
			continue
		var e: Dictionary = d[clip]
		var track := -1
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":" + String(e.get("bone", "pelvis"))):
				track = t
				break
		if track < 0:
			continue
		var fps := float(e.get("fps", 30.0))
		var deltas: Array = e.get("d", [])
		if deltas.is_empty():
			continue
		a.set_meta(&"clip_lift", true)
		for k in a.track_get_key_count(track):
			var t := a.track_get_key_time(track, k)
			var f := clampf(t * fps, 0.0, float(deltas.size() - 1))
			var i := int(floor(f))
			var j := mini(i + 1, deltas.size() - 1)
			var w := f - float(i)
			var di: Array = deltas[i]
			var dj: Array = deltas[j]
			var dv := Vector3(float(di[0]), float(di[1]), float(di[2])).lerp(Vector3(float(dj[0]), float(dj[1]), float(dj[2])), w)
			a.track_set_key_value(track, k, (a.track_get_key_value(track, k) as Vector3) + dv)
		n += 1
	return n
