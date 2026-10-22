class_name LifeLibrary
extends RefCounted
## The LIFE clip libraries (villager work, town, social, ambient and mocap clips on the UAL skeleton)
## and their living-world sidecars.
##
##   LifeLibrary.install(anim)            # once per character (idempotent, cached per skeleton path):
##                                        # adds every life clip to the AnimationPlayer's default library
##   LifeLibrary.info("Life_Smith_Hammer")   -> sidecar entry (loop, layer, props, enter/exit, events, anchor ...)
##   LifeLibrary.clips_in("work/smith")      -> clip names whose category starts with the prefix
##   LifeLibrary.clips_tagged("rain")        -> clip names carrying a tag
##   LifeLibrary.composite(anim, "Walk", "Life_Carry_Bucket_Upper") -> name of a cached clip that plays the
##                                        walk's legs and the carry clip's spine/arms (one AnimationPlayer, no tree)
##
## Libraries live under res://assets/incoming/animations/ so their `root` position track is disabled the same way
## Assets._ual_for does it (clips are in place). Sidecars: <glb>.life.json (tools/anim/life/author_life.py,
## make_life_cmu_sidecar.py). Hot-file hook alternative: append LIBS to Assets.UAL_FILES (docs/anim/patches/P13_*).

const LIBS := [
	"res://assets/incoming/animations/life/UAL_Life_Work.glb",
	"res://assets/incoming/animations/life/UAL_Life_Town.glb",
	"res://assets/incoming/animations/life/UAL_Life_Social.glb",
	"res://assets/incoming/animations/life/UAL_Life_Mocap.glb",
]
## Bones that an "upper" layer clip owns (spine_01 and everything above it).
const LOWER_BONES := ["root", "pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l",
	"thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r"]

static var _meta: Dictionary = {}
static var _meta_loaded := false
static var _anims: Dictionary = {}       # skeleton path -> {clip name -> Animation}
static var _installed: Dictionary = {}   # AnimationLibrary instance id -> true
static var _composites: Dictionary = {}  # AnimationLibrary id -> {name -> true}


## Sidecar metadata of every life clip (loaded once).
static func meta() -> Dictionary:
	if _meta_loaded:
		return _meta
	_meta_loaded = true
	for lib: String in LIBS:
		var p := lib + ".life.json"
		if not FileAccess.file_exists(p):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var clips: Dictionary = d.get("clips", {})
		for n: String in clips:
			var e: Dictionary = clips[n]
			e["library"] = lib
			_meta[n] = e
	return _meta


static func info(clip: String) -> Dictionary:
	return meta().get(clip, {})


static func clips_in(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in meta():
		if String(_meta[n].get("category", "")).begins_with(prefix):
			out.append(n)
	out.sort()
	return out


static func clips_tagged(tag: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in meta():
		if (_meta[n].get("tags", []) as Array).has(tag):
			out.append(n)
	out.sort()
	return out


## Adds the life clips to the default library of `anim` (the shared UAL library Assets built for this
## skeleton path, so every villager with the same rig pays this once). Returns the number of clips added.
static func install(anim: AnimationPlayer) -> int:
	if anim == null or not anim.has_animation_library(""):
		return 0
	var lib := anim.get_animation_library("")
	var key := lib.get_instance_id()
	if _installed.has(key):
		return 0
	var sk := _skeleton_path(lib)
	if sk == "":
		return 0
	var added := 0
	var clips := _clips_for(sk)
	for n: String in clips:
		if not lib.has_animation(n):
			lib.add_animation(n, clips[n])
			added += 1
	if not clips.is_empty():
		_installed[key] = true
	return added


## Track-path prefix ("Armature/Skeleton3D") of the library's clips.
static func _skeleton_path(lib: AnimationLibrary) -> String:
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		for t in a.get_track_count():
			var tp := String(a.track_get_path(t))
			var colon := tp.find(":")
			if colon > 0:
				return tp.substr(0, colon)
	return ""


static func _clips_for(sk: String) -> Dictionary:
	if _anims.has(sk):
		return _anims[sk]
	var out := {}
	for file: String in LIBS:
		if not ResourceLoader.exists(file):
			continue
		var inst: Node = (load(file) as PackedScene).instantiate()
		var found := inst.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			var ap := found[0] as AnimationPlayer
			for anim_name in ap.get_animation_list():
				var a: Animation = ap.get_animation(anim_name).duplicate(true)
				for t in a.get_track_count():
					var tp := String(a.track_get_path(t))
					var colon := tp.find(":")
					if colon > 0:
						a.track_set_path(t, NodePath(sk + tp.substr(colon)))
						if tp.substr(colon) == ":root" and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
							a.track_set_enabled(t, false)
				var nm := String(anim_name)
				if not out.has(nm):
					out[nm] = a
		inst.free()
	_anims[sk] = out
	return out


## A clip that plays `lower`'s legs/pelvis and `upper`'s spine, arms and head, built once per library.
## Its length is the lower clip's; the upper clip's keys repeat every upper length (make carry loops calm).
static func composite(anim: AnimationPlayer, lower: String, upper: String) -> String:
	var name := lower + "+" + upper
	if anim == null or not anim.has_animation(lower) or not anim.has_animation(upper):
		return lower
	var lib := anim.get_animation_library("")
	if lib.has_animation(name):
		return name
	var lo := anim.get_animation(lower)
	var up := anim.get_animation(upper)
	var out := Animation.new()
	out.length = lo.length
	out.loop_mode = lo.loop_mode
	var lower_set := {}
	for b: String in LOWER_BONES:
		lower_set[b] = true
	for t in lo.get_track_count():
		if lower_set.has(_bone_of(lo, t)):
			lo.copy_track(t, out)
	for t in up.get_track_count():
		var b := _bone_of(up, t)
		if b == "" or lower_set.has(b):
			continue
		var i := out.add_track(up.track_get_type(t))
		out.track_set_path(i, up.track_get_path(t))
		out.track_set_interpolation_type(i, up.track_get_interpolation_type(t))
		var ul := maxf(up.length, 0.001)
		var rep := 0.0
		while rep < out.length + 0.001:
			for k in up.track_get_key_count(t):
				var kt := up.track_get_key_time(t, k) + rep
				if kt > out.length + 0.0001:
					break
				out.track_insert_key(i, minf(kt, out.length), up.track_get_key_value(t, k))
			rep += ul
	lib.add_animation(name, out)
	return name


static func _bone_of(a: Animation, t: int) -> String:
	var tp := String(a.track_get_path(t))
	var colon := tp.find(":")
	return tp.substr(colon + 1) if colon >= 0 else ""
