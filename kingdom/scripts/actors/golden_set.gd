class_name GoldenSet
extends RefCounted
## The animation "golden set" (docs/plans/AAA_FINISH_PLAN.md A3/B): the only clips gameplay may play.
## Source of truth: data/anim/golden_set.json (clips with measured metrics + status gold|probation|banned,
## gameplay slots with a primary clip and fallbacks). Built by tools/qa/anim_qa/golden_gate.py.
##
## Resolution (resolve): a banned clip is replaced by the slot's primary/variants, else its own "fallback",
## else the category fallback (Idle for humanoids). Each substitution or gap is logged once per key to
## user://golden_missing.log. Enforcement is OFF until the JSON says "enforce": true or the game runs with
## --golden-enforce (no gold clips exist for most slots yet, so enforcing early would strip the library);
## --golden-strict turns every gap into push_error so QA finds them all.
const PATH := "res://data/anim/golden_set.json"
const LOG := "user://golden_missing.log"

static var _data: Dictionary = {}
static var _loaded := false
static var _logged := {}
static var force_enforce := false    # tests


static func reload() -> void:
	_loaded = false
	_logged.clear()
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed


static func data() -> Dictionary:
	_load()
	return _data


static func strict() -> bool:
	return OS.get_cmdline_user_args().has("--golden-strict")


static func enforce() -> bool:
	_load()
	return force_enforce or bool(_data.get("enforce", false)) or OS.get_cmdline_user_args().has("--golden-enforce")


## "gold" | "probation" | "banned" | "" (not in the set: unmeasured, treated as allowed).
static func status(clip: StringName) -> String:
	_load()
	var c: Variant = (_data.get("clips", {}) as Dictionary).get(String(clip), null)
	return String((c as Dictionary).get("status", "")) if c is Dictionary else ""


static func is_banned(clip: StringName) -> bool:
	return status(clip) == "banned"


## Banned clips the library builders must skip. Empty while enforcement is off.
static func skip_in_library(clip: StringName) -> bool:
	return enforce() and is_banned(clip)


static func slot(slot_id: String) -> Dictionary:
	_load()
	var s: Variant = (_data.get("slots", {}) as Dictionary).get(slot_id, null)
	return s if s is Dictionary else {}


## A measured metric of a clip from the golden set (e.g. "speed": ground speed in m/s on the 1.8 m reference rig), or `default`.
static func metric(clip: StringName, key: String, default := 0.0) -> float:
	_load()
	var c: Variant = (_data.get("clips", {}) as Dictionary).get(String(clip), null)
	if c is Dictionary and (c as Dictionary).get("metrics", null) is Dictionary:
		var v: Variant = ((c as Dictionary)["metrics"] as Dictionary).get(key, null)
		if v != null:
			return float(v)
	return default


## Planted-foot contact windows of a clip: {"foot_l": [[first, last], ...], ...} in frames at contacts_fps.
static func contacts(clip: StringName) -> Dictionary:
	_load()
	var c: Variant = (_data.get("clips", {}) as Dictionary).get(String(clip), null)
	if c is Dictionary and (c as Dictionary).get("foot_contacts", null) is Dictionary:
		return (c as Dictionary)["foot_contacts"]
	return {}


## The clip gameplay should play for `name` (and optionally a slot id). Returns `name` unchanged when it is
## fine or when enforcement is off (the would-be substitution is still logged).
static func resolve(name: StringName, slot_id := "") -> StringName:
	_load()
	if _data.is_empty():
		return name
	var enforcing := enforce()
	if slot_id != "":
		var s := slot(slot_id)
		if s.is_empty():
			_note("unknown slot " + slot_id, slot_id)
			return name
		var pick := _slot_pick(s, name)
		if pick != &"":
			return pick if enforcing or pick == name else name
		_note("slot %s: no usable clip (primary %s)" % [slot_id, s.get("primary", "")], slot_id)
		var fb := StringName(String(s.get("fallback", "")))
		return fb if enforcing and fb != &"" else name
	if not is_banned(name):
		return name
	var c: Dictionary = (_data["clips"] as Dictionary)[String(name)]
	var fb2 := StringName(String(c.get("fallback", "")))
	if fb2 == &"":
		var cat_fb: Dictionary = _data.get("category_fallback", {})
		fb2 = StringName(String(cat_fb.get(String(c.get("category", "")), "")))
	_note("banned clip %s -> %s" % [name, fb2], String(name))
	return fb2 if enforcing and fb2 != &"" else name


## Per-rig clip names (creatures): keys in golden_set.json are "<rig>/<clip>". Returns the bare clip name.
static func resolve_for(rig: String, clip: String) -> String:
	if clip == "" or not enforce():
		return clip
	var r := String(resolve(StringName(rig + "/" + clip)))
	return r.trim_prefix(rig + "/")


static func _slot_pick(s: Dictionary, requested: StringName) -> StringName:
	var cands: Array = [s.get("primary", "")]
	cands.append_array(s.get("variants", []))
	for n: Variant in cands:
		var nm := StringName(String(n))
		if nm != &"" and not is_banned(nm):
			return nm
	return &""


static func _note(msg: String, key: String) -> void:
	if _logged.has(key):
		return
	_logged[key] = true
	if strict():
		push_error("golden: " + msg)
	else:
		push_warning("golden: " + msg)
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(msg)
		f.close()
