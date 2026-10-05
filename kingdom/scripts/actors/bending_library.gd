extends RefCounted
## BendingLibrary: the 36 CMU bending / martial clips (UAL_CMU_Bending.glb) as an AnimationLibrary named "bending",
## plus the one-shot playback path for technique casts. Same idea as LifeLibrary (living_world/life_library.gd) and
## Assets._ual_for: clips are retargeted to the UAL skeleton, their track paths are rewritten for the rig in use, one
## library instance is cached per skeleton path and shared by every character with that rig.
##
##   BendingLibrary.install(anim_player)            # idempotent; adds library "bending" (clips are addressed "bending/<name>")
##   BendingLibrary.pick(anim_player, ["Fire_Punch_Kick", "Spell_Simple_Shoot"])  # first clip the rig has (bending names resolve)
##   BendingLibrary.play_cast(animator, anim_player, def, windup)  # {clip, mode, speed, hit}; uses animator.play_upper/play_full
##
## Playback reuses CharacterAnimator's existing OneShot slots (upper = arms and spine over locomotion, full = whole
## body), so no blend, speed or state-machine value is changed. Data: data/powers/bending_clips.json (per clip:
## trim window, hit frame, lift, blend_out, mode), generated from tools/anim/measure_events.gd.
##
## Clip fixes applied once per skeleton path at install (the GLB is untouched):
##   - root travel: the `root` position track is removed (clips play in place; Air_Evade_L/R carried 3.4-4 m),
##     the movement of dashes belongs to the caster (_resolve dash), not to the clip;
##   - sink: `lift` metres are added to the pelvis Y track (Fire_Box_Combo_A, Fire_Stride_Strike_F, Water_Whirl
##     dipped 5-7 cm under the floor);
##   - blend_out: the last N seconds ease back to the clip's first pose (Earth_Punch_Hold_Deep ended crouched);
##   - trim: long takes are cut to a window around the strike so the windup of the technique and the fist land together.

const GLB := "res://assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb"
const DATA := "res://data/powers/bending_clips.json"
const LIB := "bending"

static var _meta: Dictionary = {}
static var _meta_loaded := false
static var _libs: Dictionary = {}        # skeleton path -> AnimationLibrary
static var _installed: Dictionary = {}   # AnimationPlayer instance id -> true


## Sidecar of every bending clip: {name: {mode, hit, trim, lift, blend_out, element}}.
static func meta() -> Dictionary:
	if _meta_loaded:
		return _meta
	_meta_loaded = true
	if FileAccess.file_exists(DATA):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary:
			_meta = (d as Dictionary).get("clips", {})
	return _meta


static func info(clip: String) -> Dictionary:
	return meta().get(clip, {})


static func has_clip(clip: String) -> bool:
	return meta().has(clip)


static func clip_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in meta():
		out.append(n)
	out.sort()
	return out


## Adds library "bending" to `anim` (once per player). Returns the number of clips on the rig, 0 if nothing was added.
static func install(anim: AnimationPlayer) -> int:
	if anim == null or not is_instance_valid(anim):
		return 0
	var key := anim.get_instance_id()
	if _installed.has(key) or anim.has_animation_library(LIB):
		return 0
	var sk := _skeleton_path(anim)
	if sk == "":
		return 0
	var lib := _library_for(sk)
	if lib == null:
		return 0
	anim.add_animation_library(LIB, lib)
	_installed[key] = true
	return lib.get_animation_list().size()


## Name the player can play for a clip: "bending/<name>" for bending clips the rig has, else the name itself.
static func resolve(anim: AnimationPlayer, clip: String) -> String:
	if anim == null:
		return clip
	if has_clip(clip):
		install(anim)
		if anim.has_animation(LIB + "/" + clip):
			return LIB + "/" + clip
	return clip


## First clip of the preference list the rig can play (bending clips are installed on demand), "" if none.
static func pick(anim: AnimationPlayer, names: Array) -> String:
	for c: Variant in names:
		var r := resolve(anim, String(c))
		if anim != null and anim.has_animation(r):
			return r
	return ""


## Plays a technique's clip through the animator's OneShot slots. `def` is a normalised ability (anims, anim_mode,
## anim_speed, windup). The clip speed is raised or lowered (0.75 to 1.8 x the data speed) so the strike frame of the
## clip lands near the technique's windup. Returns {} when nothing played, else {clip, mode, speed, hit}.
static func play_cast(animator: Object, def: Dictionary, fallback := "") -> Dictionary:
	if animator == null:
		return {}
	var ap: Variant = animator.get("player")
	if not (ap is AnimationPlayer):
		return {}
	var names: Array = (def.get("anims", [def.get("anim", "")]) as Array).duplicate()
	if fallback != "":
		names.append(fallback)
	var clip := pick(ap, names)
	if clip == "":
		return {}
	var plain := clip.trim_prefix(LIB + "/")
	var meta_row := info(plain) if clip.begins_with(LIB + "/") else {}
	var mode := String(def.get("anim_mode", "upper"))
	var speed := float(def.get("anim_speed", 1.0))
	var hit := 0.0
	if not meta_row.is_empty():
		hit = float(meta_row.get("hit", 0.0))
		var windup := float(def.get("windup", def.get("hit_time", 0.25)))
		if hit > 0.0 and windup > 0.05:
			# hit / windup is the absolute rate, not a multiplier of data speed.
			# Retain the authored speed's permitted range without applying it twice.
			var base_speed := maxf(speed, 0.01)
			speed = clampf(hit / windup, base_speed * 0.75, base_speed * 1.8)
	if mode == "full":
		animator.call("play_full", clip, speed)
	else:
		animator.call("play_upper", clip, speed)
	return {"clip": clip, "mode": mode, "speed": speed, "hit": hit}


## True when the first usable clip of the ability's preference list is a bending clip.
static func is_bending(def: Dictionary) -> bool:
	for c: Variant in def.get("anims", [def.get("anim", "")]):
		if has_clip(String(c)):
			return true
	return false


# --- building ---------------------------------------------------------------------------

static func _skeleton_path(anim: AnimationPlayer) -> String:
	if anim.has_animation_library(""):
		var lib := anim.get_animation_library("")
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					return tp.substr(0, colon)
	return ""


static func _library_for(sk: String) -> AnimationLibrary:
	if _libs.has(sk):
		return _libs[sk]
	if not ResourceLoader.exists(GLB):
		push_warning("Missing bending clip library (not imported?): " + GLB)
		return null
	var lib := AnimationLibrary.new()
	var inst: Node = (load(GLB) as PackedScene).instantiate()
	var found := inst.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		var ap := found[0] as AnimationPlayer
		for anim_name in ap.get_animation_list():
			var nm := String(anim_name)
			if nm == "RESET" or not has_clip(nm):
				continue
			lib.add_animation(nm, prepare(ap.get_animation(nm), sk, info(nm)))
	inst.free()
	_libs[sk] = lib
	return lib


## A copy of `src` for skeleton path `sk` with the clip fixes of `row` applied (see the file header).
static func prepare(src: Animation, sk: String, row: Dictionary) -> Animation:
	var a: Animation = src.duplicate(true)
	# 1. root travel out, paths onto this rig.
	for t in range(a.get_track_count() - 1, -1, -1):
		var tp := String(a.track_get_path(t))
		var colon := tp.find(":")
		if colon <= 0:
			continue
		if tp.substr(colon) == ":root" and a.track_get_type(t) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			a.remove_track(t)
			continue
		a.track_set_path(t, NodePath(sk + tp.substr(colon)))
	# 2. lift the pelvis out of the floor where a bone sinks (curve is in source time, so before the trim).
	var lift: Array = row.get("lift", [])
	if not lift.is_empty():
		_lift_pelvis(a, lift)
	# 3. trim to the window around the strike.
	var trim: Array = row.get("trim", [])
	if trim.size() == 2:
		a = _trim(a, float(trim[0]), float(trim[1]))
	# 4. ease the tail back to the first pose.
	var bo := float(row.get("blend_out", 0.0))
	if bo > 0.0:
		_blend_out(a, bo)
	a.loop_mode = Animation.LOOP_NONE
	return a


static func _trim(src: Animation, t0: float, t1: float) -> Animation:
	t1 = minf(t1, src.length)
	t0 = clampf(t0, 0.0, maxf(t1 - 0.1, 0.0))
	var out := Animation.new()
	out.length = t1 - t0
	for t in src.get_track_count():
		var typ := src.track_get_type(t)
		if not (typ in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]):
			continue
		var i := out.add_track(typ)
		out.track_set_path(i, src.track_get_path(t))
		out.track_set_interpolation_type(i, src.track_get_interpolation_type(t))
		out.track_insert_key(i, 0.0, _sample(src, t, typ, t0))
		for k in src.track_get_key_count(t):
			var kt := src.track_get_key_time(t, k)
			if kt > t0 + 0.0005 and kt < t1 - 0.0005:
				out.track_insert_key(i, kt - t0, src.track_get_key_value(t, k))
		out.track_insert_key(i, out.length, _sample(src, t, typ, t1))
	return out


static func _sample(a: Animation, t: int, typ: int, at: float) -> Variant:
	match typ:
		Animation.TYPE_POSITION_3D:
			return a.position_track_interpolate(t, at)
		Animation.TYPE_ROTATION_3D:
			return a.rotation_track_interpolate(t, at)
		_:
			return a.scale_track_interpolate(t, at)


## Adds the lift curve ([[t, metres], ...], source time, skeleton units) to the pelvis Y track, resampled every 1/30 s
## so the body rises only while a bone would be under the floor (feet that already stand on it do not float).
static func _lift_pelvis(a: Animation, curve: Array) -> void:
	var idx := a.find_track(NodePath(_first_path(a) + ":pelvis"), Animation.TYPE_POSITION_3D)
	if idx < 0 or curve.size() < 2:
		return
	var n := int(ceil(a.length * 30.0))
	# The pelvis sits in the root's space, which is Z-up on the UAL rig (hip height 0.84 on Z): "up" is the axis the
	# first key is tallest on.
	var p0: Vector3 = a.track_get_key_value(idx, 0)
	var up := Vector3.ZERO
	var ax := 0
	for i in 3:
		if absf(p0[i]) > absf(p0[ax]):
			ax = i
	up[ax] = signf(p0[ax])
	var vals: Array[Vector3] = []
	for f in n + 1:
		var t := minf(float(f) / 30.0, a.length)
		vals.append(a.position_track_interpolate(idx, t) + up * _curve_at(curve, t))
	for k in range(a.track_get_key_count(idx) - 1, -1, -1):
		a.track_remove_key(idx, k)
	for f in n + 1:
		a.track_insert_key(idx, minf(float(f) / 30.0, a.length), vals[f])


static func _curve_at(curve: Array, t: float) -> float:
	if t <= float((curve[0] as Array)[0]):
		return float((curve[0] as Array)[1])
	for i in range(1, curve.size()):
		var t1 := float((curve[i] as Array)[0])
		if t <= t1:
			var t0 := float((curve[i - 1] as Array)[0])
			var w := (t - t0) / maxf(t1 - t0, 0.0001)
			return lerpf(float((curve[i - 1] as Array)[1]), float((curve[i] as Array)[1]), w)
	return float((curve[curve.size() - 1] as Array)[1])


static func _first_path(a: Animation) -> String:
	for t in a.get_track_count():
		var tp := String(a.track_get_path(t))
		var colon := tp.find(":")
		if colon > 0:
			return tp.substr(0, colon)
	return ""


static func _blend_out(a: Animation, secs: float) -> void:
	secs = minf(secs, a.length * 0.6)
	var from := a.length - secs
	var src: Animation = a.duplicate(true)
	for t in a.get_track_count():
		var typ := a.track_get_type(t)
		var n := a.track_get_key_count(t)
		if n < 2:
			continue
		var first: Variant = a.track_get_key_value(t, 0)
		# Resample the tail every 1/30 s so the ease is smooth whatever the source key spacing.
		var times: Array[float] = []
		for k in n:
			var kt := a.track_get_key_time(t, k)
			if kt > from:
				times.append(kt)
		for k in range(n - 1, -1, -1):
			if a.track_get_key_time(t, k) > from:
				a.track_remove_key(t, k)
		var s := from
		while s < a.length - 0.0001:
			s += 1.0 / 30.0
			times.append(minf(s, a.length))
		times.sort()
		var last := -1.0
		for kt: float in times:
			if absf(kt - last) < 0.001:
				continue
			last = kt
			var cur: Variant = _sample(src, t, typ, kt)
			var w := smoothstep(0.0, 1.0, (kt - from) / maxf(secs, 0.001))
			var v: Variant
			if typ == Animation.TYPE_ROTATION_3D:
				v = (cur as Quaternion).slerp(first as Quaternion, w)
			else:
				v = (cur as Vector3).lerp(first as Vector3, w)
			a.track_insert_key(t, kt, v)
