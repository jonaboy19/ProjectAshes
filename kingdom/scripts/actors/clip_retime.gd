class_name ClipRetime
extends RefCounted
## Per-foot stance retiming for locomotion clips (WP-02, AAA foot contact): data/anim/clip_retime.json holds, per clip, a time
## map baked by tools_qa/anim_states/clip_retime_bake.gd from the clip's own contact curves: while a foot is planted the clip
## time runs at the rate that makes the planted foot travel backwards at ONE constant speed (the body's ground speed), so a
## body moving at constant speed never sees the foot slip; swing phases keep their natural rate. The map is a list of source
## times sampled at FPS output frames; every track of the clip is resampled through it (loop seams stay closed: the map is
## monotonic from 0 to the source length). Applied once per library build (Assets._ual_for), before ClipLift.

const PATH := "res://data/anim/clip_retime.json"
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
		var src: Animation = lib.get_animation(StringName(clip))
		if src.has_meta(&"clip_retime"):
			continue
		var e: Dictionary = d[clip]
		var map: Array = e.get("map", [])
		var fps := float(e.get("fps", 30.0))
		if map.size() < 2:
			continue
		var out := retime(src, map, fps)
		out.set_meta(&"clip_retime", true)
		lib.remove_animation(StringName(clip))
		lib.add_animation(StringName(clip), out)
		n += 1
	return n


## A copy of `src` whose output frame k (time k / fps) shows the source pose at map[k].
static func retime(src: Animation, map: Array, fps: float) -> Animation:
	var a := Animation.new()
	a.length = float(map.size() - 1) / fps
	a.loop_mode = src.loop_mode
	a.step = 1.0 / fps
	for t in src.get_track_count():
		var ty := src.track_get_type(t)
		var nt := a.add_track(ty)
		a.track_set_path(nt, src.track_get_path(t))
		a.track_set_enabled(nt, src.track_is_enabled(t))
		a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		a.track_set_interpolation_loop_wrap(nt, src.track_get_interpolation_loop_wrap(t))
		if src.track_get_key_count(t) == 0:
			continue
		for k in map.size():
			var ts := clampf(float(map[k]), 0.0, src.length)
			var to := float(k) / fps
			match ty:
				Animation.TYPE_POSITION_3D:
					a.position_track_insert_key(nt, to, src.position_track_interpolate(t, ts))
				Animation.TYPE_ROTATION_3D:
					a.rotation_track_insert_key(nt, to, src.rotation_track_interpolate(t, ts))
				Animation.TYPE_SCALE_3D:
					a.scale_track_insert_key(nt, to, src.scale_track_interpolate(t, ts))
				Animation.TYPE_BLEND_SHAPE:
					a.blend_shape_track_insert_key(nt, to, src.blend_shape_track_interpolate(t, ts))
				Animation.TYPE_VALUE:
					a.track_insert_key(nt, to, src.value_track_interpolate(t, ts))
				_:
					pass
	return a
