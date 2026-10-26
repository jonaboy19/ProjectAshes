class_name AaaClips
extends RefCounted
## Wires the reviewed subset of the staged AAA mocap packs (assets/incoming/animations/aaa/UAL_AAA_*.glb, CMU mocap on the
## Quaternius UAL rig) into the shared per-skeleton clip library that Assets._ual_for builds.
##
## data/anim/aaa_clips.json lists every pack clip with a decision ("add", "cmp", "skip") and, for add / promoted cmp,
## the game name (`as`). Only those clips are copied (the packs are not in Assets.UAL_FILES: a whole pack in the library
## costs memory for clips nothing plays). Existing clip names always win; a collision is an error, never an overwrite.
## Root position is disabled like every incoming/animations library (clips are in place; the capsule owns travel).

const MANIFEST := "res://data/anim/aaa_clips.json"

## Perf tools flip this off to measure the library without the AAA clips.
static var enabled := true
static var _manifest: Dictionary = {}
static var _loaded := false


static func manifest() -> Dictionary:
	if _loaded:
		return _manifest
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		push_warning("AaaClips: missing " + MANIFEST)
		return _manifest
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		_manifest = parsed
	return _manifest


## True when an entry is wired into the shared clip library. Entries with a "life" category are LivingWorld clips: they live
## in animations/life/UAL_Life_AAA.glb (installed by LifeLibrary, not here).
static func is_wired(e: Dictionary) -> bool:
	if e.has("life"):
		return false
	var st := String(e.get("status", "skip"))
	return st == "add" or (st == "cmp" and bool(e.get("promote", false)))


## Entries that go to the LivingWorld library (UAL_Life_AAA.glb).
static func is_life(e: Dictionary) -> bool:
	var st := String(e.get("status", "skip"))
	return e.has("life") and (st == "add" or (st == "cmp" and bool(e.get("promote", false))))


## Game names this module installs (tests, tools).
static func wired_names() -> PackedStringArray:
	var out := PackedStringArray()
	for pack: String in (manifest().get("packs", {}) as Dictionary):
		var clips: Dictionary = manifest()["packs"][pack]
		for clip: String in clips:
			var e: Dictionary = clips[clip]
			if is_wired(e):
				out.append(String(e["as"]))
	return out


## Adds the wired clips to `lib` with track paths rewritten for skeleton path `sk`. Returns the number added.
static func merge_into(lib: AnimationLibrary, sk: String) -> int:
	if not enabled:
		return 0
	var packs: Dictionary = manifest().get("packs", {})
	var added := 0
	for pack: String in packs:
		var clips: Dictionary = packs[pack]
		var wanted: Array = []
		for clip: String in clips:
			if is_wired(clips[clip]):
				wanted.append(clip)
		if wanted.is_empty():
			continue
		if not ResourceLoader.exists(pack):
			push_warning("AaaClips: pack not imported: " + pack)
			continue
		var inst: Node = (load(pack) as PackedScene).instantiate()
		var found := inst.find_children("*", "AnimationPlayer", true, false)
		if found.is_empty():
			inst.free()
			continue
		var ap := found[0] as AnimationPlayer
		for clip: String in wanted:
			var e: Dictionary = clips[clip]
			var game_name := String(e["as"])
			if lib.has_animation(game_name):
				push_error("AaaClips: '%s' (from %s) collides with an existing clip; not added" % [game_name, clip])
				continue
			if not ap.has_animation(clip):
				push_error("AaaClips: %s has no clip '%s'" % [pack, clip])
				continue
			var a: Animation = ap.get_animation(clip).duplicate(true)
			for t in a.get_track_count():
				var tp := String(a.track_get_path(t))
				var colon := tp.find(":")
				if colon > 0:
					a.track_set_path(t, NodePath(sk + tp.substr(colon)))
					if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						a.track_set_enabled(t, false)
			if e.get("trim") is Array:
				_trim(a, float(e["trim"][0]), float(e["trim"][1]))
			a.loop_mode = Animation.LOOP_LINEAR if bool(e.get("loop", false)) else Animation.LOOP_NONE
			a.set_meta("aaa_source", pack.get_file() + ":" + clip)      # tests tell AAA clips from same-named existing ones
			lib.add_animation(game_name, a)
			added += 1
		inst.free()
	return added


## Keeps [t0, t1] of a clip, re-based to 0; the cut edges get interpolated keys so the pose at t0 / t1 is exact.
static func _trim(a: Animation, t0: float, t1: float) -> void:
	t1 = minf(t1, a.length)
	for t in a.get_track_count():
		var ty := a.track_get_type(t)
		var kt: PackedFloat32Array = PackedFloat32Array()
		var vals: Array = []
		var n := a.track_get_key_count(t)
		if n == 0:
			continue
		var first_v: Variant = _sample(a, t, t0)
		var last_v: Variant = _sample(a, t, t1)
		kt.append(0.0)
		vals.append(first_v)
		for i in n:
			var ti := a.track_get_key_time(t, i)
			if ti > t0 + 0.0001 and ti < t1 - 0.0001:
				kt.append(ti - t0)
				vals.append(a.track_get_key_value(t, i))
		kt.append(t1 - t0)
		vals.append(last_v)
		for i in range(n - 1, -1, -1):
			a.track_remove_key(t, i)
		for i in kt.size():
			match ty:
				Animation.TYPE_POSITION_3D:
					a.position_track_insert_key(t, kt[i], vals[i])
				Animation.TYPE_ROTATION_3D:
					a.rotation_track_insert_key(t, kt[i], vals[i])
				Animation.TYPE_SCALE_3D:
					a.scale_track_insert_key(t, kt[i], vals[i])
				_:
					a.track_insert_key(t, kt[i], vals[i])
	a.length = t1 - t0


static func _sample(a: Animation, t: int, at: float) -> Variant:
	match a.track_get_type(t):
		Animation.TYPE_POSITION_3D:
			return a.position_track_interpolate(t, at)
		Animation.TYPE_ROTATION_3D:
			return a.rotation_track_interpolate(t, at)
		Animation.TYPE_SCALE_3D:
			return a.scale_track_interpolate(t, at)
		Animation.TYPE_VALUE:
			return a.value_track_interpolate(t, at)
	return a.track_get_key_value(t, a.track_find_key(t, at, Animation.FIND_MODE_NEAREST))
