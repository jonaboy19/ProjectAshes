extends RefCounted
## The Soul: Soul Power, the 12 soul tiers, and the Path that emerges from how
## that power was earned. See docs/RISING_ASHES_LIFE_SIM_DESIGN.md, pillar 4
## ("Rising Ashes' own power system") and Phase 5 of the build plan.
##
## Soul Power is earned only by doing (gain(source, amount, day)); there is no
## way to buy or grant it directly. Diminishing returns per source per day mean
## grinding one activity is slow — a rounded life earns faster than a narrow one.
##
## The first four tiers (Ember -> Kindled -> Warmed -> Tempered) are reached
## automatically once enough Soul Power has been earned. Past Tempered, each
## further tier needs a deliberate, riskier attempt_breakthrough(): success
## chance depends on how much power has been banked past the threshold and on
## injuries/readiness passed in `ctx`; failure is a setback (lost power), never
## death.
##
## A Path (the Forge, the Blade, the Harvest, ...) is never picked from a menu:
## it emerges from the mix of sources used, the character's mastery disciplines
## and their Blessing element. From tier 4 (Tempered) the dominant candidate is
## surfaced by path_candidates() and can be locked in with choose_path(id).
##
## Pure data/rules (RefCounted, no nodes), deterministic (own seeded RNG),
## serialisable.
##
## INTEGRATION (Life; not wired yet — see the soul_hooks report):
##   var soul := preload("res://scripts/sim/soul.gd").new()
##   soul.gain("combat", 1.0, WorldSim.day)   # from RECORD_TO_MASTERY-style events
##   if soul.attempt_breakthrough(...)['success']: magicules.grow(pool_growth, regen_growth)
##   Save: snapshot["soul"] = soul.serialize()

signal tier_up(tier_index: int, tier_id: String)
## {ok, success, tier, id, name, pool_growth, regen_growth, power_lost, text}
signal breakthrough_result(result: Dictionary)
signal path_chosen(path_id: String)

const TIERS_PATH := "res://data/soul/tiers.json"
const PATHS_PATH := "res://data/soul/paths.json"

## Sources gain() accepts; anything else is ignored (defensive against typos).
const SOURCES := ["combat", "technique", "forge", "farm", "heal", "meditate", "hunt", "rift"]

## Diminishing returns: the more raw power already earned from a source today,
## the less the next unit of that same source is worth.
const DIMINISH_K := 0.35
## Tier index up to and including which advancement is automatic (0-based;
## index 3 is "Tempered", the design's "tier 3"). Beyond it, a breakthrough is
## required. Paths are also offered starting at this same tier ("from tier 4").
const AUTO_MAX_INDEX := 3
## Breakthrough chance shaping.
const BASE_CHANCE := 0.35
const OVERFLOW_BONUS := 0.4
const INJURY_PENALTY := 0.35
## Failed breakthroughs cost this share of current Soul Power (a setback, not death).
const SETBACK_LOSS := 0.15
## Path scoring weights.
const SOURCE_WEIGHT := 1.0
const DISCIPLINE_WEIGHT := 2.0
const ELEMENT_BONUS := 15.0

var _tiers: Array = []
var _paths: Array = []
var _paths_by_id: Dictionary = {}

var power := 0.0
var tier_index := 0
## source -> lifetime effective power earned (drives Path emergence).
var source_totals: Dictionary = {}
## source -> raw amount already banked today (drives diminishing returns).
var _today_raw: Dictionary = {}
## source -> last day a gain was recorded (resets _today_raw on change).
var _last_day: Dictionary = {}
var blessing_element := ""
var blessing_dual := ""
var chosen_path := ""

var _rng := RandomNumberGenerator.new()


func _init(load_data := true, seed_value := 90210) -> void:
	_rng.seed = seed_value
	if load_data:
		_load()
	if _tiers.is_empty():
		_tiers = [{"id": "ember", "name": "Ember", "threshold": 0, "pool": 0.0, "regen": 0.0, "flavour": ""}]


func _load() -> void:
	var t: Variant = _read_json(TIERS_PATH)
	if t is Dictionary and t.get("tiers", []) is Array and not (t["tiers"] as Array).is_empty():
		_tiers = (t["tiers"] as Array).duplicate(true)
	var p: Variant = _read_json(PATHS_PATH)
	if p is Dictionary and p.get("paths", []) is Array:
		_paths = (p["paths"] as Array).duplicate(true)
		for def: Dictionary in _paths:
			_paths_by_id[String(def["id"])] = def


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# --- tiers ---------------------------------------------------------------------

func tier() -> int:
	return tier_index


func tier_info(index := -1) -> Dictionary:
	var i: int = index if index >= 0 else tier_index
	if i < 0 or i >= _tiers.size():
		return {}
	return _tiers[i]


func is_max_tier() -> bool:
	return tier_index >= _tiers.size() - 1


## {power, tier, tier_name, next_tier, into, needed, ratio} — ratio is 0..1
## progress toward the next threshold (1.0 with nothing left to gain at the cap).
func progress() -> Dictionary:
	var cur := tier_info()
	if is_max_tier():
		return {"power": power, "tier": tier_index, "tier_name": String(cur.get("name", "")),
			"next_tier": "", "into": 0.0, "needed": 0.0, "ratio": 1.0}
	var nxt := tier_info(tier_index + 1)
	var cur_th := float(cur.get("threshold", 0.0))
	var next_th := float(nxt.get("threshold", cur_th + 1.0))
	var span := maxf(1.0, next_th - cur_th)
	return {"power": power, "tier": tier_index, "tier_name": String(cur.get("name", "")),
		"next_tier": String(nxt.get("name", "")), "into": maxf(0.0, power - cur_th),
		"needed": span, "ratio": clampf((power - cur_th) / span, 0.0, 1.0)}


## Earn Soul Power by doing. Diminishing returns apply per source per day.
## Returns {source, gained, power, tier_up, tier, tier_name, text}.
func gain(source: String, amount: float, day: int) -> Dictionary:
	var res := {"source": source, "gained": 0.0, "power": power, "tier_up": false,
		"tier": tier_index, "tier_name": String(tier_info().get("name", "")), "text": ""}
	if amount <= 0.0 or not SOURCES.has(source):
		return res
	if int(_last_day.get(source, -999999)) != day:
		_last_day[source] = day
		_today_raw[source] = 0.0
	var today: float = float(_today_raw.get(source, 0.0))
	var effective := amount / (1.0 + DIMINISH_K * today)
	_today_raw[source] = today + amount
	source_totals[source] = float(source_totals.get(source, 0.0)) + effective
	power += effective
	res["gained"] = effective
	res["power"] = power
	var before := tier_index
	while tier_index < AUTO_MAX_INDEX and tier_index < _tiers.size() - 1 and power >= float(tier_info(tier_index + 1).get("threshold", INF)):
		_advance_tier()
	if tier_index > before:
		res["tier_up"] = true
		res["tier"] = tier_index
		res["tier_name"] = String(tier_info().get("name", ""))
		res["text"] = "Your soul settles into a new tier: %s." % res["tier_name"]
	return res


func _advance_tier() -> void:
	tier_index += 1
	var info := tier_info()
	tier_up.emit(tier_index, String(info.get("id", "")))


## True once Tempered (AUTO_MAX_INDEX) has been reached, there is a next tier,
## and enough Soul Power has been banked past its threshold to try.
func can_attempt_breakthrough() -> bool:
	if is_max_tier() or tier_index < AUTO_MAX_INDEX:
		return false
	var nxt := tier_info(tier_index + 1)
	return power >= float(nxt.get("threshold", INF))


## Attempt to break into the next soul tier. `rng_seed_or_rng` is either a
## RandomNumberGenerator (tests, scripted events) or an int reseeding the
## internal RNG; pass -1 (default) to keep using the internal RNG as-is.
## `ctx` may hold "injury" (0..1, from RAInjuries.effects() or similar),
## "bonus" (a flat chance bonus) and "roll" (0..1, overrides the dice for tests).
## -> {ok, success, tier, id, name, pool_growth, regen_growth, power_lost, text}
func attempt_breakthrough(rng_seed_or_rng: Variant = -1, ctx: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "success": false, "tier": tier_index, "id": String(tier_info().get("id", "")),
		"name": String(tier_info().get("name", "")), "pool_growth": 0.0, "regen_growth": 0.0,
		"power_lost": 0.0, "text": ""}
	if not can_attempt_breakthrough():
		res["text"] = "There is nothing left to break through to." if is_max_tier() else \
			"Your soul has not gathered enough power for this yet."
		return res
	var rng := _rng
	if rng_seed_or_rng is RandomNumberGenerator:
		rng = rng_seed_or_rng
	elif rng_seed_or_rng is int and int(rng_seed_or_rng) >= 0:
		_rng.seed = int(rng_seed_or_rng)
	var nxt := tier_info(tier_index + 1)
	var threshold := float(nxt.get("threshold", power))
	var overflow := clampf((power - threshold) / maxf(1.0, threshold), 0.0, 1.0)
	var injury := clampf(float(ctx.get("injury", 0.0)), 0.0, 1.0)
	var bonus := float(ctx.get("bonus", 0.0))
	var chance := clampf(BASE_CHANCE + overflow * OVERFLOW_BONUS - injury * INJURY_PENALTY + bonus, 0.05, 0.95)
	var roll: float = float(ctx["roll"]) if ctx.has("roll") else rng.randf()
	res["ok"] = true
	if roll < chance:
		_advance_tier()
		res["success"] = true
		res["tier"] = tier_index
		res["id"] = String(tier_info().get("id", ""))
		res["name"] = String(tier_info().get("name", ""))
		res["pool_growth"] = float(tier_info().get("pool", 0.0))
		res["regen_growth"] = float(tier_info().get("regen", 0.0))
		res["text"] = "Breakthrough! Your soul steps into %s." % res["name"]
	else:
		var loss := power * SETBACK_LOSS
		power = maxf(0.0, power - loss)
		res["power_lost"] = loss
		res["text"] = "The breakthrough slips away. Something in you has to be rebuilt first."
	breakthrough_result.emit(res)
	return res


# --- paths -----------------------------------------------------------------------

## Records the character's Blessing so Path scoring can weigh it.
func set_blessing(element: String, dual := "") -> void:
	blessing_element = element
	blessing_dual = dual


## Ranked Path candidates (highest score first), empty before tier
## AUTO_MAX_INDEX or once a Path is already chosen. `disciplines` is an
## optional {discipline: level} map (e.g. from RAMastery) to weigh in.
func path_candidates(disciplines: Dictionary = {}) -> Array:
	if chosen_path != "" or tier_index < AUTO_MAX_INDEX or _paths.is_empty():
		return []
	var rows := []
	for def: Dictionary in _paths:
		var score := 0.0
		for src: String in (def.get("sources", []) as Array):
			score += float(source_totals.get(String(src), 0.0)) * SOURCE_WEIGHT
		for disc: String in (def.get("disciplines", []) as Array):
			if disciplines.has(disc):
				score += float(disciplines[disc]) * DISCIPLINE_WEIGHT
		var els: Array = def.get("elements", [])
		if els.has(blessing_element) or (blessing_dual != "" and els.has(blessing_dual)):
			score += ELEMENT_BONUS
		rows.append({"id": def["id"], "name": def["name"], "score": score,
			"flavour": def.get("flavour", ""), "modifiers": (def.get("modifiers", {}) as Dictionary).duplicate()})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return rows


## The single most likely Path right now (the one usually offered), or {} if
## none is available yet.
func dominant_path(disciplines: Dictionary = {}) -> Dictionary:
	var rows := path_candidates(disciplines)
	return rows[0] if not rows.is_empty() else {}


func choose_path(id: String) -> Dictionary:
	if chosen_path != "":
		return {"ok": false, "text": "Your Path is already set."}
	if tier_index < AUTO_MAX_INDEX:
		return {"ok": false, "text": "Your soul has not settled enough yet."}
	if not _paths_by_id.has(id):
		return {"ok": false, "text": "That Path is unknown."}
	chosen_path = id
	path_chosen.emit(id)
	return {"ok": true, "text": "You have taken up %s." % String(_paths_by_id[id]["name"])}


func path_info() -> Dictionary:
	return _paths_by_id.get(chosen_path, {})


## Passive bonuses other systems can read, e.g. modifiers().get("forge_quality", 0.0).
func path_modifiers() -> Dictionary:
	var info := path_info()
	return (info.get("modifiers", {}) as Dictionary).duplicate() if not info.is_empty() else {}


# --- save --------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"version": 1, "power": power, "tier_index": tier_index,
		"source_totals": source_totals.duplicate(), "today_raw": _today_raw.duplicate(),
		"last_day": _last_day.duplicate(), "blessing_element": blessing_element,
		"blessing_dual": blessing_dual, "chosen_path": chosen_path, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	power = float(d.get("power", 0.0))
	tier_index = clampi(int(d.get("tier_index", 0)), 0, maxi(0, _tiers.size() - 1))
	source_totals.clear()
	for k: String in (d.get("source_totals", {}) as Dictionary):
		source_totals[k] = float(d["source_totals"][k])
	_today_raw.clear()
	for k: String in (d.get("today_raw", {}) as Dictionary):
		_today_raw[k] = float(d["today_raw"][k])
	_last_day.clear()
	for k: String in (d.get("last_day", {}) as Dictionary):
		_last_day[k] = int(d["last_day"][k])
	blessing_element = String(d.get("blessing_element", ""))
	blessing_dual = String(d.get("blessing_dual", ""))
	chosen_path = String(d.get("chosen_path", ""))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
