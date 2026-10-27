class_name ClipPicker
extends RefCounted
## Variety clip picker over the normalised tag index data/anim/motion_tags.json (rules C2 and C3 of
## docs/plans/NPC_MOTION_RULES.md; the index is built by tools/anim/life/tag_clips.py).
##
##   ClipPicker.pick({"verb": "talk", "posture": "stand", "mood": "happy", "day": 3, "cycle": 12},
##                   {"id": 42, "gesture": 1.1, "mood": 0.7}, history, neighbours) -> "Life_Talk_Emphatic"
##
## query    verb (required), posture, prop ("none" = no prop), mood, layer, phase (default: loops and
##          one-shots, never an enter/exit transition), tag, vat (true = baked clips only, the FAR tier),
##          day, cycle (the decision counter; with the person id they are the seed).
## persona  id, gesture (0.8..1.2, LifeAmbience.gesture), mood (0..1, LifeAmbience.mood). All optional.
## history  this NPC's recent clips, oldest first. The last HISTORY_WINDOW are excluded.
## neighbours  clips the visible neighbours play or just played, oldest first. The last NEIGHBOUR_WINDOW are
##          excluded so two bodies side by side do not run the same clip (crowd de-sync).
## Returns "" when no clip matches the verb (the caller falls back to Walk / Idle, as the FAR tier does).
##
## Pure and static. The choice is a function of (person, day, cycle, verb) only: no RNG state, no randf.
## No allocation per call: the candidate list and weights live in static scratch arrays.
##
## Exclusions are soft so a small pool never dead-ends. Tiers, first with any weight left wins:
## history 3 + neighbours 2 -> history 3 -> the newest history entry only -> nothing.
## Filters relax in this order when they leave nothing: prop, then posture. The verb never relaxes.
##
## Weights = clip weight x mood factor x persona factor.
##   mood factor     query mood given: exact x4, calm x1, any other mood x0.1 (not given: 1).
##   persona factor  gesture g biases by intensity: 1 + 2 (g - 1)(2 i - 1), clamped 0.5..1.6;
##                   cheerful people (persona mood) favour happy clips, gloomy ones sad clips (x0.7..1.3).

const INDEX_PATH := "res://data/anim/motion_tags.json"
const HISTORY_WINDOW := 3
const NEIGHBOUR_WINDOW := 2
const MAX_CANDIDATES := 192
const MOOD_EXACT := 4.0
const MOOD_OTHER := 0.1

static var _loaded := false
static var _names := PackedStringArray()
static var _posture := PackedInt32Array()
static var _prop := PackedInt32Array()
static var _mood := PackedInt32Array()
static var _layer := PackedInt32Array()
static var _phase := PackedInt32Array()
static var _intensity := PackedFloat32Array()
static var _weight := PackedFloat32Array()
static var _vat := PackedByteArray()
static var _tags: Array[PackedStringArray] = []
static var _by_verb: Dictionary = {}     # verb -> PackedInt32Array of clip indexes (wired clips only)
static var _by_name: Dictionary = {}     # clip name -> index
static var _vocab: Dictionary = {}       # axis -> {value -> int}

static var _cand := PackedInt32Array()   # scratch
static var _w := PackedFloat32Array()    # scratch

const _ENTER := "enter"
const _EXIT := "exit"


## Loads the index from disk once. Returns the number of pickable clips.
static func ensure_loaded() -> int:
	if _loaded:
		return _names.size()
	_loaded = true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if typeof(d) == TYPE_DICTIONARY:
		_build(d as Dictionary)
	return _names.size()


## Replaces the index with `doc` (same shape as motion_tags.json). For tests and tools; reset() undoes it.
static func load_index(doc: Dictionary) -> int:
	_loaded = true
	_build(doc)
	return _names.size()


static func reset() -> void:
	_loaded = false
	_clear()


static func _clear() -> void:
	_names = PackedStringArray()
	_posture = PackedInt32Array()
	_prop = PackedInt32Array()
	_mood = PackedInt32Array()
	_layer = PackedInt32Array()
	_phase = PackedInt32Array()
	_intensity = PackedFloat32Array()
	_weight = PackedFloat32Array()
	_vat = PackedByteArray()
	_tags = []
	_by_verb = {}
	_by_name = {}
	_vocab = {}
	_cand.resize(MAX_CANDIDATES)
	_w.resize(MAX_CANDIDATES)


static func _code(axis: String, value: String) -> int:
	var m: Dictionary = _vocab.get(axis, {})
	if not m.has(value):
		m[value] = m.size()
		_vocab[axis] = m
	return m[value]


static func _build(doc: Dictionary) -> void:
	_clear()
	var clips: Dictionary = doc.get("clips", {})
	var keys: Array = clips.keys()
	keys.sort()
	for k: String in keys:
		var c: Dictionary = clips[k]
		if not bool(c.get("wired", true)):
			continue
		var i := _names.size()
		_names.append(k)
		_posture.append(_code("posture", String(c.get("posture", "stand"))))
		_prop.append(_code("prop", String(c.get("prop", "none"))))
		_mood.append(_code("mood", String(c.get("mood", "calm"))))
		_layer.append(_code("layer", String(c.get("layer", "full"))))
		_phase.append(_code("phase", String(c.get("phase", "loop"))))
		_intensity.append(float(c.get("intensity", 0.5)))
		_weight.append(maxf(0.0, float(c.get("weight", 1.0))))
		_vat.append(1 if bool(c.get("vat", false)) else 0)
		_tags.append(PackedStringArray(c.get("tags", [])))
		_by_name[k] = i
		var verb := String(c.get("verb", ""))
		var bucket: PackedInt32Array = _by_verb.get(verb, PackedInt32Array())
		bucket.append(i)
		_by_verb[verb] = bucket


## Clip names that match the verb (and the optional filters of `query`), no weighting or exclusion.
static func candidates(query: Dictionary) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	var n := _gather(query)
	for j in n:
		out.append(_names[_cand[j]])
	return out


## Weight of every candidate for this query and persona (what pick() samples from before exclusions).
## Allocates; for tests and debug overlays, not for per-tick use.
static func weights(query: Dictionary, persona: Dictionary) -> Dictionary:
	ensure_loaded()
	var out := {}
	var n := _gather(query)
	_weigh(n, query, persona)
	for j in n:
		out[_names[_cand[j]]] = _w[j]
	return out


static func is_known(clip: String) -> bool:
	ensure_loaded()
	return _by_name.has(clip)


static func pick(query: Dictionary, persona: Dictionary, history: PackedStringArray,
		neighbours: PackedStringArray = PackedStringArray()) -> String:
	ensure_loaded()
	var n := _gather(query)
	if n == 0:
		return ""
	_weigh(n, query, persona)
	var h0 := maxi(0, history.size() - HISTORY_WINDOW)
	var n0 := maxi(0, neighbours.size() - NEIGHBOUR_WINDOW)
	# tier 0: history + neighbours, 1: history, 2: newest history entry, 3: nothing excluded
	var total := 0.0
	var tier := 0
	while tier < 4:
		total = 0.0
		for j in n:
			if _excluded(_names[_cand[j]], history, h0, neighbours, n0, tier):
				continue
			total += _w[j]
		if total > 0.0:
			break
		tier += 1
	if tier == 4:  # every weight is zero: uniform over the pool
		return _names[_cand[int(_unit(query, persona) * n) % n]]
	var r := _unit(query, persona) * total
	var last := -1
	for j in n:
		if _excluded(_names[_cand[j]], history, h0, neighbours, n0, tier):
			continue
		last = j
		r -= _w[j]
		if r < 0.0:
			break
	return _names[_cand[last]]


## True when `name` sits in the exclusion window of `tier` (see pick()).
static func _excluded(name: String, history: PackedStringArray, h0: int, neighbours: PackedStringArray,
		n0: int, tier: int) -> bool:
	if tier >= 3:
		return false
	if tier == 2:
		return history.size() > 0 and history[history.size() - 1] == name
	for k in range(h0, history.size()):
		if history[k] == name:
			return true
	if tier == 0:
		for k in range(n0, neighbours.size()):
			if neighbours[k] == name:
				return true
	return false


## Fills _cand with the clip indexes matching the query. Returns the count.
static func _gather(query: Dictionary) -> int:
	var bucket: PackedInt32Array = _by_verb.get(String(query.get("verb", "")), PackedInt32Array())
	if bucket.is_empty():
		return 0
	var qpost := String(query.get("posture", ""))
	var qprop := String(query.get("prop", ""))
	var qlayer := String(query.get("layer", ""))
	var qphase := String(query.get("phase", ""))
	var qtag := String(query.get("tag", ""))
	var need_vat := bool(query.get("vat", false))
	var post_code := _lookup("posture", qpost) if qpost != "" else -1
	var prop_code := _lookup("prop", qprop) if qprop != "" else -1
	var layer_code := _lookup("layer", qlayer) if qlayer != "" else -1
	var phase_code := _lookup("phase", qphase) if qphase != "" else -1
	var enter_code := _lookup("phase", _ENTER)
	var exit_code := _lookup("phase", _EXIT)
	for relax in 3:  # 0 strict, 1 drop prop, 2 drop prop and posture
		var n := 0
		for i in bucket:
			if n >= MAX_CANDIDATES:
				break
			if layer_code != -1 and _layer[i] != layer_code:
				continue
			if need_vat and _vat[i] == 0:
				continue
			if phase_code != -1:
				if _phase[i] != phase_code:
					continue
			elif _phase[i] == enter_code or _phase[i] == exit_code:
				continue
			if qtag != "" and not _tags[i].has(qtag):
				continue
			if relax < 2 and post_code != -1 and _posture[i] != post_code:
				continue
			if relax < 1 and prop_code != -1 and _prop[i] != prop_code:
				continue
			_cand[n] = i
			n += 1
		if n > 0:
			return n
	return 0


static func _lookup(axis: String, value: String) -> int:
	var m: Dictionary = _vocab.get(axis, {})
	return int(m.get(value, -2))  # -2 matches nothing


static func _weigh(n: int, query: Dictionary, persona: Dictionary) -> void:
	var qmood := String(query.get("mood", ""))
	var mood_code := _lookup("mood", qmood) if qmood != "" else -1
	var calm_code := _lookup("mood", "calm")
	var happy_code := _lookup("mood", "happy")
	var sad_code := _lookup("mood", "sad")
	var g := float(persona.get("gesture", 1.0))
	var pm := clampf(float(persona.get("mood", 0.5)), 0.0, 1.0)
	for j in n:
		var i := _cand[j]
		var w := _weight[i]
		var m := _mood[i]
		if mood_code != -1:
			if m == mood_code:
				w *= MOOD_EXACT
			elif m != calm_code:
				w *= MOOD_OTHER
		if m == happy_code:
			w *= lerpf(0.7, 1.3, pm)
		elif m == sad_code:
			w *= lerpf(1.3, 0.7, pm)
		w *= clampf(1.0 + 2.0 * (g - 1.0) * (2.0 * _intensity[i] - 1.0), 0.5, 1.6)
		_w[j] = w


## Uniform 0..1 from (person, day, cycle, verb). Same inputs, same number, every run.
static func _unit(query: Dictionary, persona: Dictionary) -> float:
	var seed_v := int(persona.get("id", 0)) * 92821 + int(query.get("day", 0)) * 68917 \
		+ int(query.get("cycle", 0)) * 104729 + String(query.get("verb", "")).hash()
	return float(absi(hash(seed_v)) % 1000003) / 1000003.0


# --- C3: personality offsets (stable per person id, same hash recipe as LifeAmbience._h) -------------

static func _h(person: int, k: int) -> float:
	return float(absi(hash(person * 92821 + k * 68917)) % 10000) / 10000.0


## Loop playback rate 0.93..1.07 (LifeAmbience.anim_rate).
static func loop_rate(person: int) -> float:
	return 0.93 + 0.14 * _h(person, 2)


## Walk speed multiplier 0.88..1.12 (LifeAmbience.walk_speed).
static func walk_speed_scale(person: int) -> float:
	return 0.88 + 0.24 * _h(person, 1)


## Extra model-root pitch while idling, degrees, -3..+4 (posture: slouched to upright).
static func idle_pitch_deg(person: int) -> float:
	return -3.0 + 7.0 * _h(person, 11)


## Talk-loop playback rate 1.0..1.15 for a gesture amplitude 0.8..1.2.
static func talk_rate(gesture: float) -> float:
	return 1.0 + 0.15 * clampf((gesture - 0.8) / 0.4, 0.0, 1.0)


## Seek offset into a looping idle so nobody stands in sync: 0..seconds, stable per person and slot.
static func idle_start_offset(person: int, slot: int, seconds: float) -> float:
	return seconds * _h(person + slot * 7919, 13)
