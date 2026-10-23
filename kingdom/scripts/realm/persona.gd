extends "res://scripts/realm/realm_module.gd"
## Person record (NI-2, docs/design/NPC_INTELLIGENCE_MAP.md section 5): who a registry Character is, as 24 packed bytes.
## The single source of truth for traits: minds.gd reads its goal weights from it, utility_brain's personality floats are a view of it
## (`personality`), and `registry.traits_of` reads the hidden trait words from it.
##
##   byte  0-1  birth settlement + 1 (0 = unknown)        16-19  skills: craft, trade, arms, lore
##   byte  2    culture id (cultures.json order)          20-21  hidden trait words (registry.TRAITS indexes)
##   byte  3    language mask (bit 0 = common tongue)     22     drift year (game year mod 256)
##   byte  4    education                                 23     drift points spent that year
##   byte  5    intelligence
##   byte  6-9  temperament: boldness, warmth, discipline, volatility
##   byte 10-15 values: honesty, loyalty, piety, ambition, mercy, pride
##
## Seeded once from hash([SEED, "pe", id, k]), the culture of the birth town (faith.culture_tags), the parent's record (heritable with
## variance) and education. CULTURE BIASES, NEVER DETERMINES: a culture adds a few byte points to a draw that spans the whole range, so
## two cultures differ in their means and their ranges overlap. Values then DRIFT with experience (`experience`, `nudge`), capped at
## DRIFT_CAP byte points per game year per person.
## Cost: creation is O(1), nothing runs per tick. Storage is one PackedByteArray plus a slot map (no Dictionary per person);
## the save is two base64 strings (about 32 bytes per character with its id). An old save without this block is fine: a record is
## created on first use from the same seed, so the numbers are identical, only earlier drift is lost.

const Registry := preload("res://scripts/realm/registry.gd")
const NeedRules := preload("res://scripts/sim/npc_need_rules.gd")

const STRIDE := 24
const MAX_SLOTS := 1024
const YEAR := 360
const DRIFT_CAP := 8
const O_BIRTH := 0
const O_CULT := 2
const O_LANG := 3
const O_EDU := 4
const O_INT := 5
const O_BOLD := 6
const O_WARM := 7
const O_DISC := 8
const O_VOL := 9
const O_HON := 10
const O_LOY := 11
const O_PIE := 12
const O_AMB := 13
const O_MER := 14
const O_PRI := 15
const O_SKILL := 16
const O_TRAIT := 20
const O_DYEAR := 22
const O_DSPENT := 23
## Named fields that culture bias and experience may move, by name (cultures.json / traits.json spell these).
const FIELD := {"intelligence": O_INT, "boldness": O_BOLD, "warmth": O_WARM, "discipline": O_DISC, "volatility": O_VOL, "honesty": O_HON,
	"loyalty": O_LOY, "piety": O_PIE, "ambition": O_AMB, "mercy": O_MER, "pride": O_PRI}
const NEUTRAL := [0, 0, 0, 1, 1, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 60, 60, 60, 60, 0, 1, 0, 0]

static var _data: Dictionary = {}
static var _neutral := PackedByteArray()

var _buf := PackedByteArray()
var _ids := PackedInt32Array()          # slot -> character number n of "ch:n" (0 = free slot)
var _slot: Dictionary = {}              # ch -> slot
var _free: Array = []
var stats := {"made": 0, "dropped": 0, "nudged": 0, "refused": 0}


static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var out := {"cultures": [], "languages": [], "experience": {}, "bias": []}
	var c: Variant = _read("res://data/npc/cultures.json")
	var t: Variant = _read("res://data/npc/traits.json")
	if c is Dictionary:
		out["cultures"] = c.get("list", [])
		out["languages"] = c.get("languages", [])
	if t is Dictionary:
		out["experience"] = t.get("experience", {})
	for cu: Dictionary in out["cultures"]:
		var b := PackedInt32Array()
		b.resize(STRIDE)
		var src: Dictionary = cu.get("bias", {})
		for k: String in src:
			if FIELD.has(k):
				b[int(FIELD[k])] = int(src[k])
		(out["bias"] as Array).append(b)
	if (out["cultures"] as Array).is_empty():
		out["cultures"] = [{"id": "caldric", "language": 1}]
		(out["bias"] as Array).append(PackedInt32Array())
		((out["bias"] as Array)[0] as PackedInt32Array).resize(STRIDE)
	_data = out
	return _data


## A record of average people (for a character that has none and cannot get one).
static func neutral() -> PackedByteArray:
	if _neutral.is_empty():
		_neutral.resize(STRIDE)
		for i in STRIDE:
			_neutral[i] = int(NEUTRAL[i])
	return _neutral


static func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## One hash per person, then an integer mix per field (so making a person costs one Array allocation, not thirty).
var _hb := 0

func _h(_ch: String, k: int) -> int:
	var x: int = (_hb ^ (k * 0x9E3779B1)) * 0x85EBCA6B
	x ^= (x >> 29) & 0x7FFFFFFF
	x *= 0xC2B2AE35
	x ^= (x >> 31) & 0x7FFFFFFFF
	return absi(x)


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ queries

## Byte offset of `ch`'s record in `buf()`, -1 when it has none (never creates).
func off(ch: String) -> int:
	var s: Variant = _slot.get(ch)
	return int(s) * STRIDE if s != null else -1


## The packed records (copy on write: reading it never copies, so hold it only for the length of a read).
func buf() -> PackedByteArray:
	return _buf


func count() -> int:
	return _slot.size()


func has(ch: String) -> bool:
	return _slot.has(ch)


func culture_id(ch: String) -> String:
	var o := off(ch)
	if o < 0:
		return ""
	return String(((data()["cultures"] as Array)[mini(int(_buf[o + O_CULT]), (data()["cultures"] as Array).size() - 1)] as Dictionary)["id"])


func birth_sid(ch: String) -> int:
	var o := off(ch)
	return int(_buf[o + O_BIRTH]) + 256 * int(_buf[o + O_BIRTH + 1]) - 1 if o >= 0 else -1


func intelligence(ch: String) -> float:
	var o := off(ch)
	return float(_buf[o + O_INT]) / 255.0 if o >= 0 else 0.5


## A field (a FIELD name) as 0..1; 0.5 for a character without a record.
func trait_f(ch: String, field: String) -> float:
	var o := off(ch)
	return float(_buf[o + int(FIELD[field])]) / 255.0 if o >= 0 and FIELD.has(field) else 0.5


## The two hidden trait words of registry.TRAITS.
func traits(ch: String) -> Array:
	var o := off(ch)
	if o < 0:
		return []
	var out: Array = []
	for k in 2:
		out.append(Registry.TRAITS[int(_buf[o + O_TRAIT + k]) % Registry.TRAITS.size()])
	return out


## utility_brain's five 0..1 floats (sociable, lazy, pious, greedy, courage) as a view of the record. {} without one.
func personality(ch: String) -> Dictionary:
	var o := off(ch)
	if o < 0:
		return {}
	return personality_at(_buf, o)


static func personality_at(b: PackedByteArray, o: int) -> Dictionary:
	return {"sociable": float(b[o + O_WARM]) / 255.0, "lazy": 1.0 - float(b[o + O_DISC]) / 255.0, "pious": float(b[o + O_PIE]) / 255.0,
		"greedy": 0.5 * float(b[o + O_AMB]) / 255.0 + 0.5 * (1.0 - float(b[o + O_HON]) / 255.0), "courage": float(b[o + O_BOLD]) / 255.0}


## Everything about one person as plain data (for tests, tools, the future inspector).
func view(ch: String) -> Dictionary:
	var o := off(ch)
	if o < 0:
		return {}
	var langs: Array = []
	var names: Array = data()["languages"]
	for i in names.size():
		if (int(_buf[o + O_LANG]) >> i) & 1 == 1:
			langs.append(names[i])
	var v := {"birth_sid": birth_sid(ch), "culture": culture_id(ch), "languages": langs, "education": int(_buf[o + O_EDU]),
		"intelligence": int(_buf[o + O_INT]), "traits": traits(ch), "skills": [int(_buf[o + O_SKILL]), int(_buf[o + O_SKILL + 1]), int(_buf[o + O_SKILL + 2]), int(_buf[o + O_SKILL + 3])]}
	for k: String in FIELD:
		v[k] = int(_buf[o + int(FIELD[k])])
	return v


# ------------------------------------------------------------------ making

## The record of `ch`, created on first call. `sid` is the birth (or first known) settlement, `edu` the education step, `parent` an
## optional parent id whose record the values lean towards, `row` the WorldSim row (its old trait generator seeds the five
## personality fields so a person keeps the same temper they always had), `culture` a culture tag that overrides the birth town's
## (a foundling raised by another people; tests). Returns the byte offset, -1 for a non-character id or when full.
func ensure(ch: String, sid: int, edu := 1, parent := "", row := -1, culture := "") -> int:
	var have := off(ch)
	if have >= 0:
		return have
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
	_hb = hash([WorldSim.SEED, "pe", ch])
	var o := slot * STRIDE
	var d := data()
	var cults: Array = d["cultures"]
	# culture of the birth town
	var tags: Array = ["caldric"]
	var fa: Variant = _mod("faith")
	if fa != null and sid >= 0:
		tags = fa.culture_tags(sid)
	var tag := culture if culture != "" else String(tags[_h(ch, 90) % tags.size()])
	var ci := 0
	for i in cults.size():
		if String((cults[i] as Dictionary)["id"]) == tag:
			ci = i
	var bias: PackedInt32Array = (d["bias"] as Array)[ci]
	var po := -1
	if parent != "":
		po = off(parent)
	_buf[o + O_BIRTH] = (sid + 1) & 255
	_buf[o + O_BIRTH + 1] = ((sid + 1) >> 8) & 255
	_buf[o + O_CULT] = ci
	_buf[o + O_EDU] = clampi(edu, 0, 9)
	# values and temperament: a uniform draw, the parent's value pulled in, then the culture's nudge
	for off_f in range(O_BOLD, O_PRI + 1):
		var v := float(_h(ch, off_f) % 256)
		if row >= 0:
			match off_f:
				O_WARM: v = 255.0 * NeedRules.trait_value(row, 0)
				O_DISC: v = 255.0 * (1.0 - NeedRules.trait_value(row, 1))
				O_PIE: v = 255.0 * NeedRules.trait_value(row, 2)
				O_BOLD: v = 255.0 * NeedRules.trait_value(row, 4)
		if po >= 0:
			v = lerpf(v, float(_buf[po + off_f]), 0.35)
		_buf[o + off_f] = clampi(int(v) + bias[off_f], 0, 255)
	var iv := float((_h(ch, O_INT) % 256 + _h(ch, O_INT + 100) % 256) / 2) + 12.0 * float(clampi(edu, 0, 4) - 1)
	if po >= 0:
		iv = lerpf(iv, float(_buf[po + O_INT]), 0.35)
	_buf[o + O_INT] = clampi(int(iv) + bias[O_INT], 0, 255)
	for k in 4:
		_buf[o + O_SKILL + k] = clampi(20 + _h(ch, 40 + k) % 50 + 18 * edu, 0, 255)
	var lang := 1 | (1 << int((cults[ci] as Dictionary).get("language", 1)))
	if edu >= 2 and int(_buf[o + O_INT]) > 150:
		lang |= 1 << (_h(ch, 60) % maxi(1, (d["languages"] as Array).size()))
	_buf[o + O_LANG] = lang & 255
	var words: Array = Registry.traits_for(row) if row >= 0 else [Registry.TRAITS[_h(ch, 70) % Registry.TRAITS.size()], Registry.TRAITS[_h(ch, 71) % Registry.TRAITS.size()]]
	for k in 2:
		_buf[o + O_TRAIT + k] = maxi(0, Registry.TRAITS.find(words[k]))
	_buf[o + O_DYEAR] = 0
	_buf[o + O_DSPENT] = 0
	stats["made"] = int(stats["made"]) + 1
	return o


func drop(ch: String) -> void:
	var s: Variant = _slot.get(ch)
	if s == null:
		return
	_slot.erase(ch)
	_ids[int(s)] = 0
	_free.append(int(s))
	stats["dropped"] = int(stats["dropped"]) + 1


# ------------------------------------------------------------------ drift

## Moves a field of `ch` by `delta` byte points, within the person's yearly drift budget. Returns the points actually moved (signed).
func nudge(ch: String, field: int, delta: int, day: int) -> int:
	var o := off(ch)
	if o < 0 or delta == 0 or field < O_INT or field > O_PRI:
		return 0
	var yr := (day / YEAR) & 255
	if int(_buf[o + O_DYEAR]) != yr:
		_buf[o + O_DYEAR] = yr
		_buf[o + O_DSPENT] = 0
	var left := DRIFT_CAP - int(_buf[o + O_DSPENT])
	var step := mini(absi(delta), left)
	if step <= 0:
		return 0
	var old := int(_buf[o + field])
	var nv := clampi(old + (step if delta > 0 else -step), 0, 255)
	var moved := absi(nv - old)
	_buf[o + field] = nv
	_buf[o + O_DSPENT] = int(_buf[o + O_DSPENT]) + moved
	if moved > 0:
		stats["nudged"] = int(stats["nudged"]) + 1
	return nv - old


## What doing `goal` (a goals.json id) and succeeding or failing teaches: the table is traits.json "experience".
func experience(ch: String, goal: String, ok: bool, day: int) -> void:
	var tbl: Dictionary = data()["experience"]
	var row: Variant = tbl.get(goal)
	if row == null:
		return
	for pair: Array in (row as Dictionary).get("ok" if ok else "fail", []):
		if FIELD.has(pair[0]):
			nudge(ch, int(FIELD[pair[0]]), int(pair[1]), day)


## Skill bytes (0 craft, 1 trade, 2 arms, 3 lore): learned from a master (realm/bonds.gd). -1 when the character has no record.
func skill_of(ch: String, idx: int) -> int:
	var o := off(ch)
	return int(_buf[o + O_SKILL + clampi(idx, 0, 3)]) if o >= 0 else -1


## Raises a skill by `delta` byte points (never above `cap`, never past 255). Returns the points gained.
func skill_gain(ch: String, idx: int, delta: int, cap := 255) -> int:
	var o := off(ch)
	if o < 0 or delta <= 0:
		return 0
	var k := o + O_SKILL + clampi(idx, 0, 3)
	var nv := mini(mini(255, cap), int(_buf[k]) + delta)
	var gained := maxi(0, nv - int(_buf[k]))
	_buf[k] = int(_buf[k]) + gained
	return gained


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var last := _ids.size()
	while last > 0 and _ids[last - 1] == 0:
		last -= 1
	return {"v": 1, "ids": _b64(_ids.slice(0, last).to_byte_array()), "b": _b64(_buf.slice(0, last * STRIDE))}


## raw_to_base64 logs an engine error on an empty array: an empty store saves as "".
static func _b64(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw) if not raw.is_empty() else ""


func deserialize(d: Dictionary) -> void:
	_buf = PackedByteArray()
	_ids = PackedInt32Array()
	_slot = {}
	_free = []
	var ids := Marshalls.base64_to_raw(String(d.get("ids", ""))).to_int32_array()
	var b := Marshalls.base64_to_raw(String(d.get("b", "")))
	var n := mini(ids.size(), b.size() / STRIDE)
	n = mini(n, MAX_SLOTS)
	_ids = ids.slice(0, n)
	_buf = b.slice(0, n * STRIDE)
	for i in n:
		if _ids[i] > 0:
			_slot["ch:%d" % _ids[i]] = i
		else:
			_free.append(i)
