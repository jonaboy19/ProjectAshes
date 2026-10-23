extends "res://scripts/realm/realm_module.gd"
## Memory with emotional weight and per-person mood (NI-4 + MW-2, docs/design/NPC_INTELLIGENCE_MAP.md section 5).
##
## What a person lived through, as packed bytes, and how it left them. Two things per character, in one record of STRIDE bytes:
##   MOOD   stress, fear, anger, grief, confidence (0..255 each) plus the day they were last written. They are never ticked: every read
##          decays them in closed form toward a baseline set by the person's temperament, at a rate set by their resilience, so a
##          resilient farmer is steady again within weeks and a fragile one carries the fear for months.
##   MEMORY up to MEM_N tuples of 5 bytes: day (u16), kind (7 bits) + bad flag + processed flag, emotional weight, reliability (high
##          nibble, 0..15) and witnesses (low nibble). Weight is the APPRAISED weight, so it differs per person for the same event.
##          Insignificant memories of the same kind merge into one; when full, the least salient one (weight x reliability, fading with
##          age) is forgotten.
## APPRAISAL (`appraise`): the same event moves different people differently through persona.gd bytes: resilience (boldness, discipline,
## low volatility) scales fear, stress and the confidence hit; volatility, pride and mercy scale anger; warmth and loyalty scale grief.
## Heard-about events (reliability under 1) move the mood less. A heavy memory also DRIFTS values (data/npc/psyche.json "drift", one
## nudge per memory, through persona.nudge so the yearly cap holds); which way depends on which side of 128 the trait sits.
## FEEDS: rumours.gd calls `on_memory` for each memory it makes (witness, hearsay, player acts); minds.gd reads `devs` (deviation from
## baseline, so a person with no record scores exactly as before) as bounded considerations in goals.json.
## COST: nothing runs per tick. tick_week only visits a quarter of the slots (housekeeping). Save: zlib of ids + records, about 20-30
## bytes per character with a history, MAX_SLOTS characters at most. Near-tier characters (minds.tier_of == 1) keep full memory tuples;
## everyone else keeps mood only.

const Registry := preload("res://scripts/realm/registry.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const PD := preload("res://scripts/realm/politics_data.gd")

const MEM_N := 5
const MEM_W := 5
const O_DAY := 5
const O_N := 7
const O_MEM := 8
const STRIDE := O_MEM + MEM_N * MEM_W
const MAX_SLOTS := 1024
const DIMS := ["stress", "fear", "anger", "grief", "confidence"]
const S_STRESS := 0
const S_FEAR := 1
const S_ANGER := 2
const S_GRIEF := 3
const S_CONF := 4
const POINTS := 140.0
const INSIG := 40                    # weights below this merge with a like memory
const DRIFT_WEIGHT := 150
const HALF := 180.0                  # days for a memory's salience to halve
const BAD_FLAG := 128
const DONE_FLAG := 64

static var _data: Dictionary = {}

var _buf := PackedByteArray()
var _ids := PackedInt32Array()
var _slot: Dictionary = {}
var _free: Array = []
var _day := 0
var _out := PackedFloat32Array()      # reused result of devs()
var _tmp := PackedFloat32Array()
var stats := {"events": 0, "heard": 0, "merged": 0, "forgotten": 0, "drifted": 0, "refused": 0}


static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var f := FileAccess.open("res://data/npc/psyche.json", FileAccess.READ)
	var doc: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var d := {"kinds": [], "index": {}, "tau": [25.0, 40.0, 15.0, 100.0, 70.0], "drift": {}}
	if doc is Dictionary:
		d["kinds"] = (doc as Dictionary).get("kinds", [])
		d["drift"] = (doc as Dictionary).get("drift", {})
		var tau: Array = (doc as Dictionary).get("tau_days", d["tau"])
		d["tau"] = tau
	for i in (d["kinds"] as Array).size():
		(d["index"] as Dictionary)[String(((d["kinds"] as Array)[i] as Dictionary)["id"])] = i
	# flat per-kind rows for the hot path: m0..m4, tempered, 1 when the four negative-mood terms sum above 0.3 (the "bad" flag)
	var kf: Array = []
	for kd2: Dictionary in (d["kinds"] as Array):
		var m: Array = kd2["m"]
		kf.append(PackedFloat64Array([float(m[0]), float(m[1]), float(m[2]), float(m[3]), float(m[4]), float(kd2.get("tempered", 0.0)),
			1.0 if float(m[0]) + float(m[1]) + float(m[2]) + float(m[3]) > 0.3 else 0.0]))
	d["kf"] = kf
	var tf := PackedFloat64Array()
	for t: Variant in (d["tau"] as Array):
		tf.append(float(t))
	d["tauf"] = tf
	_data = d
	return _data


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _now() -> int:
	return maxi(_day, PD.today())


func has(ch: String) -> bool:
	return _slot.has(ch)


func count() -> int:
	return _slot.size()


func _off(ch: String) -> int:
	var s: Variant = _slot.get(ch)
	return int(s) * STRIDE if s != null else -1


func _make(ch: String) -> int:
	var o := _off(ch)
	if o >= 0:
		return o
	var pr: Dictionary = Registry.parse(ch)
	if pr.is_empty() or String(pr["p"]) != "ch":
		return -1
	var slot := -1
	if not _free.is_empty():
		slot = int(_free.pop_back())
	elif _ids.size() < MAX_SLOTS:
		slot = _ids.size()
		_ids.append(0)
		_buf.resize(_buf.size() + STRIDE)
	if slot < 0:
		stats["refused"] = int(stats["refused"]) + 1
		return -1
	_ids[slot] = int(pr["n"])
	_slot[ch] = slot
	o = slot * STRIDE
	for i in STRIDE:
		_buf[o + i] = 0
	var pb := _pbuf(ch)
	for k in 5:
		_buf[o + k] = int(_base(pb[0], pb[1], k))
	return o


# ------------------------------------------------------------------ persona terms

## [persona bytes, offset] for `ch` (a record is made for a character that has none; the neutral person when it cannot).
func _pbuf(ch: String) -> Array:
	var pe: Variant = _mod("persona")
	if pe == null:
		return [Persona.neutral(), 0]
	var po: int = pe.off(ch)
	if po < 0:
		po = pe.ensure(ch, -1)
	if po < 0:
		return [Persona.neutral(), 0]
	return [pe.buf(), po]


static func resilience(pb: PackedByteArray, po: int) -> float:
	return clampf(0.45 * float(pb[po + Persona.O_BOLD]) / 255.0 + 0.35 * float(pb[po + Persona.O_DISC]) / 255.0 + 0.2 * (1.0 - float(pb[po + Persona.O_VOL]) / 255.0), 0.0, 1.0)


## The mood a person returns to (byte points): the volatile are tenser and angrier, the bold more confident.
static func _base(pb: PackedByteArray, po: int, k: int) -> float:
	var vol := float(pb[po + Persona.O_VOL]) / 255.0
	var bold := float(pb[po + Persona.O_BOLD]) / 255.0
	match k:
		S_STRESS: return 30.0 + 50.0 * vol
		S_FEAR: return 8.0 + 20.0 * (1.0 - bold)
		S_ANGER: return 8.0 + 30.0 * vol
		S_GRIEF: return 0.0
	return 90.0 + 80.0 * bold


# ------------------------------------------------------------------ mood (closed-form decay)

## Writes the five decayed mood values (byte points) of the record at `o` for `day` into `out`.
func _decayed(o: int, pb: PackedByteArray, po: int, day: int, out: PackedFloat32Array) -> void:
	var dt := float(maxi(0, (day - (int(_buf[o + O_DAY]) | (int(_buf[o + O_DAY + 1]) << 8))) & 0xFFFF))
	if dt <= 0.0:
		for i in 5:
			out[i] = float(_buf[o + i])
		return
	var vol := float(pb[po + Persona.O_VOL]) / 255.0
	var bold := float(pb[po + Persona.O_BOLD]) / 255.0
	var k := 2.0 - 1.5 * clampf(0.45 * bold + 0.35 * float(pb[po + Persona.O_DISC]) / 255.0 + 0.2 * (1.0 - vol), 0.0, 1.0)   # == resilience(pb, po)
	var tau: PackedFloat64Array = (_data if not _data.is_empty() else data())["tauf"]
	# the five baselines of _base(), computed once (same formulas)
	var b0 := 30.0 + 50.0 * vol
	var b1 := 8.0 + 20.0 * (1.0 - bold)
	var b2 := 8.0 + 30.0 * vol
	var b3 := 0.0
	var b4 := 90.0 + 80.0 * bold
	out[0] = b0 + (float(_buf[o]) - b0) * exp(-dt / (tau[0] * k))
	out[1] = b1 + (float(_buf[o + 1]) - b1) * exp(-dt / (tau[1] * k))
	out[2] = b2 + (float(_buf[o + 2]) - b2) * exp(-dt / (tau[2] * k))
	out[3] = b3 + (float(_buf[o + 3]) - b3) * exp(-dt / (tau[3] * k))
	out[4] = b4 + (float(_buf[o + 4]) - b4) * exp(-dt / (tau[4] * k))


## Mood as 0..1 floats {stress, fear, anger, grief, confidence}; the baseline of a person with no record.
func mood(ch: String, day := -1) -> Dictionary:
	var pb := _pbuf(ch)
	var o := _off(ch)
	var out := {}
	if o < 0:
		for i in 5:
			out[DIMS[i]] = _base(pb[0], pb[1], i) / 255.0
		return out
	if _tmp.size() != 5:
		_tmp.resize(5)
	_decayed(o, pb[0], pb[1], _now() if day < 0 else day, _tmp)
	for i in 5:
		out[DIMS[i]] = _tmp[i] / 255.0
	return out


## What the decision layers read, allocation free: stress, fear, anger, grief, confidence as deviations from the person's own baseline
## (positive = more than usual, -1..1) and `scar` 0..1 = how much heavy, believed, still-fresh bad memory they hold. All zero for a
## person with no record. The returned array is reused by the next call.
func devs(ch: String, day: int) -> PackedFloat32Array:
	if _out.size() != 6:
		_out.resize(6)
		_tmp.resize(5)
	var s: Variant = _slot.get(ch)
	if s == null:
		_out.fill(0.0)
		return _out
	var o: int = int(s) * STRIDE
	var pe: Variant = _mod("persona")
	var po: int = pe.off(ch) if pe != null else -1
	var pb: PackedByteArray = pe.buf() if po >= 0 else Persona.neutral()
	if po < 0:
		po = 0
	_decayed(o, pb, po, day, _tmp)
	for i in 5:
		_out[i] = clampf((_tmp[i] - _base(pb, po, i)) / 255.0, -1.0, 1.0)
	var scar := 0.0
	for j in int(_buf[o + O_N]):
		var m := o + O_MEM + j * MEM_W
		if (int(_buf[m + 2]) & BAD_FLAG) == 0:
			continue
		scar += _salience(m, day) * float(_buf[m + 3]) / 255.0
	_out[5] = minf(1.0, scar)
	return _out


# ------------------------------------------------------------------ memory

func _salience(m: int, day: int) -> float:
	var d0 := int(_buf[m]) | (int(_buf[m + 1]) << 8)
	var age := float(maxi(0, (day - d0) & 0xFFFF))
	return float(_buf[m + 3]) / 255.0 * (0.3 + 0.7 * float(int(_buf[m + 4]) >> 4) / 15.0) / (1.0 + age / HALF)


## The memories of `ch`, strongest first: [{day, kind, bad, weight (0..255), reliability (0..1), witnesses, salience}].
func memories(ch: String, day := -1) -> Array:
	var out: Array = []
	var o := _off(ch)
	if o < 0:
		return out
	var now := _now() if day < 0 else day
	var kinds: Array = data()["kinds"]
	for j in int(_buf[o + O_N]):
		var m := o + O_MEM + j * MEM_W
		out.append({"day": int(_buf[m]) | (int(_buf[m + 1]) << 8), "kind": String((kinds[int(_buf[m + 2]) & 63] as Dictionary)["id"]), "bad": (int(_buf[m + 2]) & BAD_FLAG) != 0,
			"weight": int(_buf[m + 3]), "reliability": float(int(_buf[m + 4]) >> 4) / 15.0, "witnesses": int(_buf[m + 4]) & 15, "salience": _salience(m, now)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["salience"]) > float(b["salience"]))
	return out


## Dread of a person: 0..1, the same number devs()[5] gives.
func scar(ch: String, day := -1) -> float:
	return devs(ch, _now() if day < 0 else day)[5]


# ------------------------------------------------------------------ appraisal

## What an event of `kind` at severity `sev` (0..1) and reliability `rel` (1 = saw it) means to THIS person:
## {mood: five byte-point deltas, weight: emotional weight 0..255, bad: bool, drift: [[persona field, delta], ...]}. Pure: no state.
func appraise(ch: String, kind: String, sev: float, rel := 1.0) -> Dictionary:
	var pb := _pbuf(ch)
	return appraise_at(pb[0], pb[1], kind, sev, rel)


static func appraise_at(pb: PackedByteArray, po: int, kind: String, sev: float, rel: float) -> Dictionary:
	var r := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var drift: Array = []
	var ki := _appraise_core(pb, po, kind, sev, rel, r, drift)
	if ki < 0:
		return {}
	var pts: Array = [r[0], r[1], r[2], r[3], r[4]]
	return {"mood": pts, "weight": int(r[5]), "bad": r[6] != 0.0, "drift": drift, "k": ki}


## The appraisal without allocating a result: mood deltas (byte points) into r[0..4], weight into r[5], bad into r[6] (1/0), drift pairs appended
## to `drift`. Returns the kind's index or -1 for an unknown kind.
static func _appraise_core(pb: PackedByteArray, po: int, kind: String, sev: float, rel: float, r: PackedFloat64Array, drift: Array) -> int:
	var d := _data if not _data.is_empty() else data()
	var ki: Variant = (d["index"] as Dictionary).get(kind)
	if ki == null:
		return -1
	var kf: PackedFloat64Array = (d["kf"] as Array)[int(ki)]
	var m0 := kf[0]
	var m1 := kf[1]
	var m2 := kf[2]
	var m3 := kf[3]
	var m4 := kf[4]
	var vol := float(pb[po + Persona.O_VOL]) / 255.0
	var bold := float(pb[po + Persona.O_BOLD]) / 255.0
	var res := clampf(0.45 * bold + 0.35 * float(pb[po + Persona.O_DISC]) / 255.0 + 0.2 * (1.0 - vol), 0.0, 1.0)   # == resilience(pb, po)
	var warm := float(pb[po + Persona.O_WARM]) / 255.0
	var w := 0.2 + 0.8 * clampf(rel, 0.0, 1.0)
	var csev := clampf(sev, 0.0, 1.0)
	var s := csev * w
	var fear_k := 1.5 - 1.2 * res
	r[0] = m0 * (1.4 - 0.9 * res) * s * POINTS
	r[1] = m1 * fear_k * s * POINTS
	r[2] = m2 * (0.5 + 0.6 * vol + 0.4 * (float(pb[po + Persona.O_PRI]) / 255.0) - 0.3 * (float(pb[po + Persona.O_MER]) / 255.0)) * s * POINTS
	r[3] = m3 * (0.6 + 0.5 * warm + 0.4 * (float(pb[po + Persona.O_LOY]) / 255.0)) * s * POINTS
	r[4] = (m4 * (fear_k if m4 < 0.0 else 0.6 + 0.8 * res) + kf[5] * (res - 0.5) * 2.0) * s * POINTS
	var bad: bool = kf[6] != 0.0
	var weight := clampi(int(csev * 255.0 * (1.2 - 0.5 * res if bad else 0.9 + 0.2 * warm)), 0, 255)
	r[5] = float(weight)
	r[6] = 1.0 if bad else 0.0
	if weight >= DRIFT_WEIGHT and rel >= 0.5:
		var step := 2 if weight >= 220 else 1
		var kd: Dictionary = (d["kinds"] as Array)[int(ki)]
		for dr: Array in (d["drift"] as Dictionary).get(String(kd.get("theme", "")), []):
			var field: int = int(Persona.FIELD.get(String(dr[0]), -1))
			if field < 0:
				continue
			var hi := int(pb[po + field]) >= 128
			if (String(dr[2]) == "hi") == hi:
				drift.append([field, int(dr[1]) * step])
	return int(ki)


## `ch` lived through (rel 1) or heard of (rel < 1) an event: mood moves, the memory is kept, values may drift. `witnesses` is how many
## people saw it. Returns false for an unknown kind, a non-character or a full table.
func experience(ch: String, kind: String, sev: float, rel := 1.0, witnesses := 1, day := -1) -> bool:
	if hub != _mh:
		_mn_m = _mod("minds")
		_pe_m = _mod("persona")
		_mh = hub
	var pe: Variant = _pe_m if _pe_m != null else _mod("persona")
	var pbuf: PackedByteArray
	var po := 0
	if pe == null:
		pbuf = Persona.neutral()
	else:
		po = pe.off(ch)
		if po < 0:
			po = pe.ensure(ch, -1)
		if po < 0:
			pbuf = Persona.neutral()
			po = 0
		else:
			pbuf = pe.buf()
	var drift := _ad   # reused: nothing below re-enters experience()
	drift.clear()
	var ar := _ar
	var kidx := _appraise_core(pbuf, po, kind, sev, rel, ar, drift)
	if kidx < 0:
		return false
	var o := _off(ch)
	if o < 0:
		o = _make(ch)
		if o < 0:
			return false
	var now := _now() if day < 0 else day
	if _tmp.size() != 5:
		_tmp.resize(5)
	_decayed(o, pbuf, po, now, _tmp)
	for i in 5:
		_buf[o + i] = clampi(int(roundf(_tmp[i] + ar[i])), 0, 255)
	_buf[o + O_DAY] = now & 255
	_buf[o + O_DAY + 1] = (now >> 8) & 255
	stats["events" if rel >= 0.9 else "heard"] += 1
	# values drift once per heavy memory (a merged or re-told one does not drift twice); far characters keep no tuple, so each hearing counts
	var drifted: bool = _store(o, now, kidx, int(ar[5]), ar[6] != 0.0, drift, rel, witnesses) if _near(ch) else not drift.is_empty()
	if drifted:
		if pe != null:
			for dr: Array in drift:
				if int(pe.nudge(ch, int(dr[0]), int(dr[1]), now)) != 0:
					stats["drifted"] = int(stats["drifted"]) + 1
	return true


## Near-tier extra detail only: tuples for characters in the focus town (or when there is no minds layer to tell).
func _near(ch: String) -> bool:
	var mn: Variant = _mn_m
	if mn == null:
		mn = _mod("minds")
		_mn_m = mn
	if mn == null or not mn.is_mind(ch):
		return true
	var f: int = mn.focus_sid()
	return f < 0 or int(mn.tier_of(ch)) == 1


var _mn_m: Variant = null
var _ad: Array = []
var _ar := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _mh: Variant = null
var _pe_m: Variant = null


## Adds the memory tuple (merging insignificant likes, forgetting the least salient). True when it should drive a value drift.
func _store(o: int, now: int, kidx: int, weight: int, bad: bool, drift: Array, rel: float, witnesses: int) -> bool:
	var flag: int = kidx | (BAD_FLAG if bad else 0)
	var rel_n := clampi(int(roundf(rel * 15.0)), 0, 15)
	var wit := clampi(witnesses, 0, 15)
	var n := int(_buf[o + O_N])
	if weight < INSIG:
		for j in n:
			var m := o + O_MEM + j * MEM_W
			if (int(_buf[m + 2]) & (63 | BAD_FLAG)) == flag and int(_buf[m + 3]) < INSIG + 20:
				_buf[m] = now & 255
				_buf[m + 1] = (now >> 8) & 255
				_buf[m + 3] = mini(INSIG + 19, int(_buf[m + 3]) + weight / 2 + 1)
				_buf[m + 4] = (maxi(rel_n, int(_buf[m + 4]) >> 4) << 4) | mini(15, (int(_buf[m + 4]) & 15) + wit)
				stats["merged"] = int(stats["merged"]) + 1
				return false
	var at := n
	if n >= MEM_N:
		var worst := 0
		var ws := 1.0e9
		for j in n:
			var mm := o + O_MEM + j * MEM_W   # _salience(mm, now), inlined
			var sc := float(_buf[mm + 3]) / 255.0 * (0.3 + 0.7 * float(int(_buf[mm + 4]) >> 4) / 15.0) / (1.0 + float(maxi(0, (now - (int(_buf[mm]) | (int(_buf[mm + 1]) << 8))) & 0xFFFF)) / HALF)
			if sc < ws:
				ws = sc
				worst = j
		var mine := float(weight) / 255.0 * (0.3 + 0.7 * rel)
		if mine < ws:
			stats["forgotten"] = int(stats["forgotten"]) + 1
			return false
		at = worst
		stats["forgotten"] = int(stats["forgotten"]) + 1
	else:
		_buf[o + O_N] = n + 1
	var m2 := o + O_MEM + at * MEM_W
	_buf[m2] = now & 255
	_buf[m2 + 1] = (now >> 8) & 255
	_buf[m2 + 2] = flag | (DONE_FLAG if not drift.is_empty() else 0)
	_buf[m2 + 3] = weight
	_buf[m2 + 4] = (rel_n << 4) | wit
	return not drift.is_empty()


## The hook rumours.gd calls for every new memory: `conf` is its 0..100 confidence (100 = saw it), `mag` the -100..100 story size.
func on_memory(ch: String, kind: String, mag: float, conf: int, witnesses: int) -> void:
	experience(ch, kind, absf(mag) / 100.0, float(conf) / 100.0, witnesses)


# ------------------------------------------------------------------ the week, catch-up

## A quarter of the slots a week: forgets memories whose salience has faded to nothing and frees records that are back to baseline.
func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	var now := _now()
	var n := _ids.size()
	var q := week & 3
	var i := q
	while i < n:
		if _ids[i] > 0:
			_sweep(i, now)
		i += 4
	return []


func _sweep(slot: int, now: int) -> void:
	var o := slot * STRIDE
	var n := int(_buf[o + O_N])
	var j := 0
	while j < n:
		var m := o + O_MEM + j * MEM_W
		if _salience(m, now) < 0.01:
			for t in range(j, n - 1):
				for b in MEM_W:
					_buf[o + O_MEM + t * MEM_W + b] = _buf[o + O_MEM + (t + 1) * MEM_W + b]
			n -= 1
			stats["forgotten"] = int(stats["forgotten"]) + 1
			continue
		j += 1
	_buf[o + O_N] = n
	if n == 0 and now - (int(_buf[o + O_DAY]) | (int(_buf[o + O_DAY + 1]) << 8)) > 720:
		var ch := "ch:%d" % _ids[slot]
		drop(ch)


func drop(ch: String) -> void:
	var s: Variant = _slot.get(ch)
	if s == null:
		return
	_slot.erase(ch)
	_ids[int(s)] = 0
	_free.append(int(s))


func drop_character(ch: String) -> void:
	drop(ch)


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Mood decays on read and memories fade on read: nothing to do per day. Housekeeping once.
	_day += days
	for i in _ids.size():
		if _ids[i] > 0:
			_sweep(i, _now())
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var last := _ids.size()
	while last > 0 and _ids[last - 1] == 0:
		last -= 1
	var raw := _ids.slice(0, last).to_byte_array()
	raw.append_array(_buf.slice(0, last * STRIDE))
	return {"v": 1, "k": last, "z": raw.size(), "d": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) if not raw.is_empty() else "", "day": _day, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_buf = PackedByteArray()
	_ids = PackedInt32Array()
	_slot = {}
	_free = []
	_day = int(d.get("day", 0))
	var k := mini(int(d.get("k", 0)), MAX_SLOTS)
	var z := int(d.get("z", 0))
	if k > 0 and z > 0:
		var raw := Marshalls.base64_to_raw(String(d.get("d", ""))).decompress(z, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == z and z == k * 4 + k * STRIDE:
			_ids = raw.slice(0, k * 4).to_int32_array()
			_buf = raw.slice(k * 4)
			for i in k:
				if _ids[i] > 0:
					_slot["ch:%d" % _ids[i]] = i
				else:
					_free.append(i)
	var st: Dictionary = d.get("st", {})
	for key: String in stats:
		stats[key] = int(st.get(key, stats[key]))
