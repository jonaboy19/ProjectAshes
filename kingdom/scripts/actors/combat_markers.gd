class_name CombatMarkers
extends RefCounted
## Static loader for the per-clip combat markers sidecar (frames at 30 fps, playback rate 1.0):
##   res://assets/incoming/animations/combat/combat_markers.json
##   {"version":1,"fps":30,"clips":{"Sword_Regular_A":{"hit_start":10,"hit_end":13,"hits":[11],
##     "trail_start":8,"trail_end":15,"combo_window":[14,30],"cancel_window":[22,39],...}},
##    "aliases":{"1H_Melee_Attack_Chop":"Sword_Regular_A"}}
## Loaded once and cached. A missing / broken file yields an empty table (callers fall back).
## Seconds at playback rate r = frame / fps / r.

const PATH := "res://assets/incoming/animations/combat/combat_markers.json"

static var _loaded := false
static var _fps := 30.0
static var _clips := {}
static var _aliases := {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	# Gameplay aliases (old KayKit names) first; the JSON may add or override.
	var sc: Variant = load("res://scripts/world/assets.gd")
	if sc is GDScript:
		var cm: Dictionary = (sc as GDScript).get_script_constant_map()
		if cm.has("UAL_ALIASES") and cm["UAL_ALIASES"] is Dictionary:
			_aliases = (cm["UAL_ALIASES"] as Dictionary).duplicate()
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_warning("CombatMarkers: bad JSON in " + PATH)
		return
	var d := parsed as Dictionary
	_fps = float(d.get("fps", 30.0))
	if d.get("clips") is Dictionary:
		_clips = d["clips"]
	if d.get("aliases") is Dictionary:
		_aliases.merge(d["aliases"], true)


## Force a reload (tools / tests).
static func reload() -> void:
	_loaded = false
	_clips = {}
	_aliases = {}
	_ensure()


static func set_aliases(map: Dictionary) -> void:
	_ensure()
	_aliases.merge(map, true)


static func has_clip(clip: String) -> bool:
	return not get_clip(clip).is_empty()


## Marker dictionary for a clip (alias-resolved); empty if unknown.
static func get_clip(clip: String) -> Dictionary:
	_ensure()
	var n := clip
	if not _clips.has(n) and _aliases.has(n):
		n = String(_aliases[n])
	return _clips.get(n, {})


## Start,end seconds of a window key ("hit", "trail", "combo_window", "cancel_window") at rate.
## Returns Vector2(-1, -1) when the clip or key is missing.
static func window_s(clip: String, key: String, rate := 1.0) -> Vector2:
	var c := get_clip(clip)
	if c.is_empty():
		return Vector2(-1, -1)
	var a: Variant = null
	var b: Variant = null
	if c.has(key) and c[key] is Array and (c[key] as Array).size() >= 2:
		a = c[key][0]
		b = c[key][1]
	elif c.has(key + "_start") and c.has(key + "_end"):
		a = c[key + "_start"]
		b = c[key + "_end"]
	if a == null:
		return Vector2(-1, -1)
	var s := 1.0 / (_fps * maxf(rate, 0.01))
	return Vector2(float(a) * s, float(b) * s)


## Single marker in seconds (e.g. "windup_end", "hit_start", "step_in_m" is not a time: raw value).
static func time_s(clip: String, key: String, rate := 1.0) -> float:
	var c := get_clip(clip)
	if c.is_empty() or not c.has(key):
		return -1.0
	return float(c[key]) / (_fps * maxf(rate, 0.01))


static func hits_s(clip: String, rate := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var c := get_clip(clip)
	if c.is_empty() or not (c.get("hits") is Array):
		return out
	var s := 1.0 / (_fps * maxf(rate, 0.01))
	for h in c["hits"]:
		out.append(float(h) * s)
	return out
