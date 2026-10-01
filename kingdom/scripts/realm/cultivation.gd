extends "res://scripts/realm/realm_module.gd"
## CULTIVATION: the universal ladder every path climbs (docs/design/ACADEMY_PLAN.md power systems).
##
## 10 realms x 9 stages for the whole game (Body Tempering -> Qi Gathering -> Foundation -> Core Formation ->
## Nascent Soul -> Spirit Severing -> Void Sovereign -> Ascendant -> Immortal Ascension -> Origin Dao).
## Region 1 reaches realms 1-3 only: realm 4 needs character level 62 (Region 1 hard-caps at 60).
## Every power path (power_paths.gd: magic, bending, sect, knight, beast) has its own track on the SAME ladder
## with its own names and diagram (mana circles / elemental resonance / meridians / aura layers / soul bond).
## The first path learned is the primary. Every extra path cultivates at cross_step^rank speed and may never
## out-realm the primary (the second path is very slow).
##
## Loop: MEDITATE (time spent, location density, path affinity, a daily absorption curve, toxicity from
## resources) fills the stage's qi bar; RESOURCES (spirit herbs, monster cores, pills) add chunks of it;
## INSIGHT (exploration, lore, teachers) is spent at bottlenecks; a BREAKTHROUGH attempt then has a risk
## (strain, qi deviation, backlash - never death). Realm boundaries also offer an optional TRIBULATION trial
## (an encounter the player may clear for a better chance and a lasting "tempered" bonus; skipping it is fine).
## MANUALS teach techniques; a technique needs its realm+stage, so cultivation gates power, not level alone.
## Level only gates how far up the ladder you may climb at a given time (level_needed).
##
## Also owns the character level (prog = scripts/sim/progression.gd) so both save together:
## hub.mod("cultivation").prog.award("kill", {...}).
##
## Deterministic: one seeded RNG (saved), exactly one draw per breakthrough roll (+1 on failure).

const Prog := preload("res://scripts/sim/progression.gd")
const DATA_PATH := "res://data/progression/cultivation.json"
const STAGES := 9
const SOURCE_MULT := {"academy": 1.0, "teacher": 0.9, "manual": 0.7, "self": 0.5, "sect_hall": 1.0}
const INSIGHT_SOURCES := {"discovery": 0.8, "lore": 2.0, "quest": 1.5, "teacher": 3.0, "trial": 2.0, "spar": 0.4, "rift": 1.2}

static var _data: Dictionary = {}

var prog: RefCounted = Prog.new()
var primary := ""
## Breakthrough chance banked by a swallowed pill (items' breakthrough_bonus); spent by the next attempt.
var pill_bonus := 0.0
var insight := 0.0
var insight_total := 0.0
var toxicity := 0.0
var strain_until := -1          # day; meditation and breakthrough are worse
var deviation_until := -1       # day; cannot meditate at all (qi deviation)
var injury_note := ""
var _tracks: Dictionary = {}    # path -> {realm, stage, qi, fails, tempered, src, order, stages_done}
var _manuals: Array = []        # learned manual ids
var _flags: Dictionary = {}
var _stock: Dictionary = {}     # "kind:grade" -> count
var _day := 0
var _med_day := -1
var _med_hours := 0.0
var _insight_seen: Dictionary = {}
var _insight_day: Dictionary = {}   # "source|day" -> count
var _rng := RandomNumberGenerator.new()
var _seed := 424242
var log_lines: Array = []


func _init() -> void:
	reseed(_seed)


func reseed(s: int) -> void:
	_seed = s
	_rng.seed = s


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f != null else {}
	return _data


# ----------------------------------------------------------------- static ladder info ----

static func realm_def(realm: int) -> Dictionary:
	return (data()["realms"] as Array)[clampi(realm, 1, 10) - 1]


static func path_def(path: String) -> Dictionary:
	return data()["paths"].get(path, {})


static func paths() -> Array:
	return (data()["paths"] as Dictionary).keys()


static func realm_name(path: String, realm: int) -> String:
	var pd := path_def(path)
	if pd.is_empty():
		return String(realm_def(realm)["name"])
	return String((pd["realm_names"] as Array)[clampi(realm, 1, 10) - 1])


static func stage_label(path: String, realm: int, stage: int) -> String:
	var pd := path_def(path)
	var word := String(pd.get("stage_word", "Stage"))
	return "%s, %s %d" % [realm_name(path, realm), word, clampi(stage, 1, STAGES)]


static func stage_index(realm: int, stage: int) -> int:
	return (realm - 1) * STAGES + stage


## Effective meditation hours (at density 1.0) a stage takes.
static func stage_need_eff(realm: int, stage: int) -> float:
	return float(realm_def(realm)["eff_hours"]) * (1.0 + float(data()["stage_growth"]) * float(stage - 1))


## The qi number shown in the UI for a stage.
static func stage_need_qi(realm: int, stage: int) -> int:
	return int(round(stage_need_eff(realm, stage) * float(data()["qi_per_eff_hour"])))


static func level_needed(realm: int, stage: int) -> int:
	var r := realm_def(realm)
	return int(r["level_gate"]) + int(floor(float(r["level_span"]) * float(stage - 1) / float(STAGES - 1)))


static func location(id: String) -> Dictionary:
	return data()["locations"].get(id, {})


static func locations() -> Array:
	return (data()["locations"] as Dictionary).keys()


static func technique(id: String) -> Dictionary:
	for t: Dictionary in data()["techniques"]:
		if t["id"] == id:
			return t
	return {}


static func techniques_of(path: String) -> Array:
	return (data()["techniques"] as Array).filter(func(t: Dictionary) -> bool: return t["path"] == path)


static func manual(id: String) -> Dictionary:
	for m: Dictionary in data()["manuals"]:
		if m["id"] == id:
			return m
	return {}


static func manuals_of(path: String) -> Array:
	return (data()["manuals"] as Array).filter(func(m: Dictionary) -> bool: return m["path"] == path)


## Universal power multiplier of a ladder position (cultivation matters far more than level).
static func position_power(realm: int, stage: int) -> float:
	return 1.0 + 0.055 * float(stage_index(realm, stage))


# ----------------------------------------------------------------- tracks ----

func _pp() -> Variant:
	if hub != null and hub.mods.has("power_paths"):
		return hub.mod("power_paths")
	return null


func has_path(path: String) -> bool:
	return _tracks.has(path)


func cultivating() -> Array:
	var out: Array = []
	for p: String in paths():
		if _tracks.has(p):
			out.append(p)
	return out


## Start cultivating a path (also learns it in power_paths). The first becomes primary.
func begin(path: String, source := "self") -> bool:
	if not (data()["paths"] as Dictionary).has(path) or _tracks.has(path) or not SOURCE_MULT.has(source):
		return false
	var pp: Variant = _pp()
	if pp != null and not pp.knows(path):
		pp.learn(path, source if ["academy", "teacher", "manual", "self"].has(source) else "academy")
	_tracks[path] = {"realm": 1, "stage": 1, "qi": 0.0, "fails": 0, "tempered": 0, "src": source, "order": _tracks.size(), "done": 0}
	if primary == "":
		primary = path
	return true


func set_flag(flag: String, on := true) -> void:
	_flags[flag] = on


func flag(flag_id: String) -> bool:
	return bool(_flags.get(flag_id, false))


func track(path: String) -> Dictionary:
	return (_tracks[path] as Dictionary).duplicate() if _tracks.has(path) else {}


func realm_of(path: String) -> int:
	return int(_tracks[path]["realm"]) if _tracks.has(path) else 0


func stage_of(path: String) -> int:
	return int(_tracks[path]["stage"]) if _tracks.has(path) else 0


func qi_ratio(path: String) -> float:
	return float(_tracks[path]["qi"]) if _tracks.has(path) else 0.0


func position(path: String) -> int:
	if not _tracks.has(path):
		return 0
	return stage_index(int(_tracks[path]["realm"]), int(_tracks[path]["stage"]))


func _level(ctx: Dictionary = {}) -> int:
	return int(ctx.get("level", prog.level))


## Cultivation speed multiplier of a track: primary 1.0 x source; each extra path cross_step^rank.
func speed_mult(path: String) -> float:
	if not _tracks.has(path):
		return 0.0
	var t: Dictionary = _tracks[path]
	var src := float(SOURCE_MULT.get(String(t["src"]), 0.5))
	var base := 0.6 + 0.4 * src
	if path == primary:
		return base
	var rank := 0
	for p: String in _tracks:
		if p != primary and int(_tracks[p]["order"]) < int(t["order"]):
			rank += 1
	var d := data()
	return maxf(float(d["cross_min"]), pow(float(d["cross_step"]), float(rank + 1))) * base


func density(loc: String, path: String) -> float:
	var l := location(loc)
	if l.is_empty():
		return 1.0
	return float(l["density"]) + float((l["affinity"] as Dictionary).get(path, 0.0))


func location_open(loc: String) -> bool:
	var l := location(loc)
	if l.is_empty():
		return false
	var req := String(l.get("requires", ""))
	return req == "" or flag(req)


func open_locations() -> Array:
	return locations().filter(func(l: String) -> bool: return location_open(l))


func is_deviated(day: int = -1) -> bool:
	return (_day if day < 0 else day) < deviation_until


func is_strained(day: int = -1) -> bool:
	return (_day if day < 0 else day) < strain_until


func _sync_day(day: int) -> void:
	if day >= 0:
		_day = maxi(_day, day)
		if day != _med_day:
			_med_day = day
			_med_hours = 0.0


# ----------------------------------------------------------------- meditation ----

## Efficiency of the next `hours` given today's meditation so far (sum of schedule tiers).
func _eff_hours(hours: float) -> float:
	var sched: Array = data()["med_schedule"]
	var eff := 0.0
	var used := _med_hours
	var left := hours
	var edge := 0.0
	for tier: Array in sched:
		var hi := edge + float(tier[0])
		if used < hi and left > 0.0:
			var take := minf(left, hi - used)
			eff += take * float(tier[1])
			used += take
			left -= take
		edge = hi
	return eff


## Meditate `hours` game hours at `loc`. ctx: day, level. -> {ok, reason, eff_hours, frac, events, ...}
func meditate(path: String, hours: float, loc := "wilds", ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": "", "eff_hours": 0.0, "frac": 0.0, "events": [], "qi": 0}
	if not _tracks.has(path):
		out["reason"] = "not_cultivating"
		return out
	_sync_day(int(ctx.get("day", -1)))
	if is_deviated():
		out["reason"] = "deviated"
		return out
	if not location_open(loc):
		out["reason"] = "location_closed"
		return out
	hours = clampf(hours, 0.0, 12.0)
	if hours <= 0.0:
		out["reason"] = "no_time"
		return out
	var t: Dictionary = _tracks[path]
	var eff := _eff_hours(hours)
	_med_hours += hours
	var tox_f := 1.0 if toxicity <= 1.0 else 0.4
	var strain_f := 0.5 if is_strained() else 1.0
	var d := density(loc, path)
	var gain_eff := eff * d * speed_mult(path) * tox_f * strain_f
	var need := stage_need_eff(int(t["realm"]), int(t["stage"]))
	var before := float(t["qi"])
	var cap := float(data()["overflow_cap"])
	t["qi"] = minf(cap, before + gain_eff / need)
	out["ok"] = true
	out["eff_hours"] = eff
	out["frac"] = float(t["qi"]) - before
	out["qi"] = int(round(float(out["frac"]) * float(stage_need_qi(int(t["realm"]), int(t["stage"])))))
	out["density"] = d
	out["full"] = float(t["qi"]) >= 1.0
	var risk := float(location(loc).get("risk", 0.0)) * (hours / 4.0)
	if risk > 0.0 and _rng.randf() < risk:
		t["qi"] = maxf(0.0, float(t["qi"]) - 0.1)
		strain_until = _day + 5
		injury_note = "Backlash at %s" % String(location(loc)["name"])
		(out["events"] as Array).append("backlash")
	prog.award("meditate", {"subject": loc, "magnitude": eff, "day": _day, "content_level": maxi(1, int(level_needed(int(t["realm"]), int(t["stage"])))), "region": String(ctx.get("region", "region1"))})
	var pp: Variant = _pp()
	if pp != null and pp.knows(path):
		pp.gain_xp(path, eff * 0.6)
	return out


# ----------------------------------------------------------------- resources & insight ----

func add_resource(kind: String, grade: int, n := 1) -> void:
	if not (data()["resources"] as Dictionary).has(kind):
		return
	var k := "%s:%d" % [kind, clampi(grade, 1, 6)]
	_stock[k] = int(_stock.get(k, 0)) + n


func stock(kind: String, grade: int) -> int:
	return int(_stock.get("%s:%d" % [kind, grade], 0))


## Count of kind at grade >= min_grade.
func stock_at_least(kind: String, min_grade: int) -> int:
	var n := 0
	for g in range(min_grade, 7):
		n += stock(kind, g)
	return n


func stock_list() -> Array:
	var out: Array = []
	for k: String in _stock:
		if int(_stock[k]) > 0:
			var p := k.split(":")
			out.append({"kind": p[0], "grade": int(p[1]), "n": int(_stock[k])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["kind"] < b["kind"] or (a["kind"] == b["kind"] and a["grade"] < b["grade"]))
	return out


func _take(kind: String, min_grade: int) -> int:
	for g in range(min_grade, 7):
		if stock(kind, g) > 0:
			_stock["%s:%d" % [kind, g]] = stock(kind, g) - 1
			return g
	return 0


## Eat a herb / absorb a core / take a pill of exactly `grade`. Adds a chunk of the current stage's qi bar;
## toxicity builds (decays daily); past 1.0 gains fall and qi deviation becomes a risk.
func use_resource(path: String, kind: String, grade: int, ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": "", "frac": 0.0}
	if not _tracks.has(path):
		out["reason"] = "not_cultivating"
		return out
	if stock(kind, grade) <= 0:
		out["reason"] = "none"
		return out
	_sync_day(int(ctx.get("day", -1)))
	if is_deviated():
		out["reason"] = "deviated"
		return out
	var res: Dictionary = data()["resources"][kind]
	var t: Dictionary = _tracks[path]
	_stock["%s:%d" % [kind, grade]] = stock(kind, grade) - 1
	# a grade-g resource is worth eff * step^(g-1) meditation hours (realm-independent), so a high grade is
	# a big chunk of an early stage but only a sliver of a late one.
	var frac := float(res["eff"]) * pow(float(data()["resource_grade_step"]), float(grade - 1)) / stage_need_eff(int(t["realm"]), int(t["stage"]))
	frac = clampf(frac, 0.002, 1.2)
	if kind == "core" and path == "beast":
		frac *= 1.5
	if toxicity > 1.0:
		frac *= 0.3
	frac *= speed_mult(path) if path != primary else 1.0
	toxicity += float(res["tox"])
	t["qi"] = minf(float(data()["overflow_cap"]), float(t["qi"]) + frac)
	out["ok"] = true
	out["frac"] = frac
	if toxicity > 1.2 and _rng.randf() < 0.15:
		deviation_until = _day + 6
		injury_note = "Qi deviation from overdosing"
		out["deviation"] = true
	return out


func add_insight(amount: float, source := "discovery", id := "") -> float:
	if id != "":
		var key := source + "#" + id
		if _insight_seen.has(key):
			return 0.0
		_insight_seen[key] = true
	var n := int(_insight_day.get("%s|%d" % [source, _day], 0))
	_insight_day["%s|%d" % [source, _day]] = n + 1
	var got := amount * float(INSIGHT_SOURCES.get(source, 1.0)) / (1.0 + 0.25 * float(n))
	insight += got
	insight_total += got
	return got


# ----------------------------------------------------------------- breakthrough ----

func is_major(path: String) -> bool:
	return _tracks.has(path) and int(_tracks[path]["stage"]) >= STAGES


## The (realm, stage) an attempt would reach; {} at the top of the ladder.
func next_position(path: String) -> Dictionary:
	if not _tracks.has(path):
		return {}
	var r := int(_tracks[path]["realm"])
	var s := int(_tracks[path]["stage"])
	if s >= STAGES:
		return {} if r >= 10 else {"realm": r + 1, "stage": 1}
	return {"realm": r, "stage": s + 1}


func insight_needed(path: String) -> int:
	if not _tracks.has(path):
		return 0
	var r := int(_tracks[path]["realm"])
	var s := int(_tracks[path]["stage"])
	var cost := int(realm_def(r)["insight_cost"])
	if s >= STAGES:
		return cost
	if _is_minor_stage(s):
		return int(round(float(cost) * float(data()["minor_insight_share"])))
	return 0


func _is_minor_stage(s: int) -> bool:
	for m in data()["minor_insight_stages"]:
		if int(m) == s:
			return true
	return false


func catalyst_needed(path: String) -> Array:
	if not is_major(path):
		return []
	return realm_def(int(_tracks[path]["realm"]))["catalyst"]


func tribulation_spec(path: String) -> Dictionary:
	if not is_major(path):
		return {}
	var r := int(_tracks[path]["realm"])
	var t: Dictionary = realm_def(r)["tribulation"]
	return {"waves": int(t["waves"]), "difficulty": float(t["difficulty"]), "optional": true,
		"reward": "Better odds now, and a lasting tempered bonus when cleared well.", "name": "%s Trial" % realm_name(path, r)}


## Stand-in trial result (0..1) until the tribulation encounter reports a real one: level over the stage's
## requirement, tempering so far and the path's strain all matter.
func trial_score_estimate(path: String, ctx: Dictionary = {}) -> float:
	var nxt := next_position(path)
	if nxt.is_empty():
		return 0.0
	var over := float(_level(ctx) - level_needed(int(nxt["realm"]), int(nxt["stage"])))
	return clampf(0.5 + over * 0.02 + 0.03 * float(tempered(path)) - (0.15 if is_strained() else 0.0), 0.1, 0.95)


## Everything the UI shows before pressing Break through. opts: score (tribulation 0..1, -1 none), pill, master,
## loc, extra_insight, level, day. No RNG here. -> {ok, reason, chance, major, factors, ...}
func breakthrough_info(path: String, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": "", "chance": 0.0, "major": false, "factors": {}, "needs": {}}
	if not _tracks.has(path):
		out["reason"] = "not_cultivating"
		return out
	_sync_day(int(opts.get("day", -1)))
	var t: Dictionary = _tracks[path]
	var r := int(t["realm"])
	var s := int(t["stage"])
	var nxt := next_position(path)
	if nxt.is_empty():
		out["reason"] = "top"
		return out
	var major := s >= STAGES
	out["major"] = major
	var f := {}
	var base := float(realm_def(r)["base_success"]) - 0.01 * float(s - 1) - (0.10 if major else 0.0)
	f["base"] = base
	var qi := float(t["qi"])
	f["overflow"] = 0.15 * clampf((qi - 1.0) / (float(data()["overflow_cap"]) - 1.0), 0.0, 1.0)
	f["insight"] = 0.02 * float(clampi(int(opts.get("extra_insight", 0)), 0, 5))
	f["pill"] = 0.12 if bool(opts.get("pill", false)) else 0.0
	f["pill"] += pill_bonus
	var dens := density(String(opts.get("loc", "wilds")), path)
	f["place"] = 0.08 if dens >= 2.4 else (0.05 if dens >= 1.8 else 0.0)
	f["master"] = 0.05 if bool(opts.get("master", false)) else 0.0
	f["persistence"] = 0.04 * float(mini(int(t["fails"]), 4))
	f["strain"] = -0.15 if is_strained() else 0.0
	f["toxicity"] = -0.10 if toxicity > 0.7 else 0.0
	f["second_path"] = -0.10 if path != primary else 0.0
	var score := float(opts.get("score", -1.0))
	f["trial"] = (score - 0.5) * 0.3 if score >= 0.0 else 0.0
	var ch := 0.0
	for k: String in f:
		ch += float(f[k])
	out["chance"] = clampf(ch, 0.05, 0.97)
	out["factors"] = f
	out["level_needed"] = level_needed(int(nxt["realm"]), int(nxt["stage"]))
	out["insight_needed"] = insight_needed(path)
	out["catalyst"] = catalyst_needed(path)
	var why := ""
	if is_deviated():
		why = "deviated"
	elif qi < 1.0:
		why = "qi_low"
	elif _level(opts) < int(out["level_needed"]):
		why = "level"
	elif insight + 0.0001 < float(out["insight_needed"]) + float(clampi(int(opts.get("extra_insight", 0)), 0, 5)):
		why = "insight"
	elif path != primary and int(nxt["realm"]) > realm_of(primary):
		why = "primary_behind"
	else:
		for c: Dictionary in out["catalyst"]:
			if stock_at_least(String(c["kind"]), int(c["grade"])) < int(c["n"]):
				why = "catalyst"
		if why == "" and bool(opts.get("pill", false)) and stock_at_least("pill", r) < 1 + _pill_need_overlap(path):
			why = "pill"
	out["reason"] = why
	out["ok"] = why == ""
	return out


func _pill_need_overlap(path: String) -> int:
	var n := 0
	for c: Dictionary in catalyst_needed(path):
		if c["kind"] == "pill":
			n += int(c["n"])
	return n


## Attempt the breakthrough. Consumes insight/catalysts (insight half-refunded on failure).
## -> {ok, success, reason, chance, roll, severity, realm, stage, msg}
func attempt_breakthrough(path: String, opts: Dictionary = {}) -> Dictionary:
	var info := breakthrough_info(path, opts)
	if bool(info.get("ok", false)):
		pill_bonus = 0.0
	var res := {"ok": false, "success": false, "reason": info["reason"], "chance": info["chance"], "roll": -1.0, "severity": "", "msg": ""}
	if not bool(info["ok"]):
		res["msg"] = "Cannot break through yet (%s)." % String(info["reason"])
		return res
	res["ok"] = true
	var t: Dictionary = _tracks[path]
	var extra := float(clampi(int(opts.get("extra_insight", 0)), 0, 5))
	var spent := float(info["insight_needed"]) + extra
	insight -= spent
	for c: Dictionary in info["catalyst"]:
		for i in int(c["n"]):
			_take(String(c["kind"]), int(c["grade"]))
	if bool(opts.get("pill", false)):
		_take("pill", int(t["realm"]))
	var roll := _rng.randf()
	res["roll"] = roll
	var nxt := next_position(path)
	var major := bool(info["major"])
	if roll < float(info["chance"]):
		var leftover := maxf(0.0, float(t["qi"]) - 1.0) * 0.5
		t["realm"] = int(nxt["realm"])
		t["stage"] = int(nxt["stage"])
		t["qi"] = leftover
		t["fails"] = 0
		t["done"] = int(t["done"]) + 1
		var score := float(opts.get("score", -1.0))
		if major and score >= 0.6:
			t["tempered"] = int(t["tempered"]) + 1
			res["tempered"] = true
		res["success"] = true
		res["realm"] = int(t["realm"])
		res["stage"] = int(t["stage"])
		res["msg"] = "Breakthrough! %s." % stage_label(path, int(t["realm"]), int(t["stage"]))
		prog.award("breakthrough", {"id": "bt_%s_%d_%d" % [path, int(t["realm"]), int(t["stage"])],
			"magnitude": 1.0 + float(int(t["realm"]) - 1) * 0.5 + (0.5 if major else 0.0),
			"content_level": level_needed(int(t["realm"]), int(t["stage"])), "day": _day, "region": String(opts.get("region", "region1"))})
		var pp: Variant = _pp()
		if pp != null and pp.knows(path):
			pp.gain_xp(path, 20.0)
		return res
	# failure: never death; the stage holds, qi and body pay.
	insight += spent * 0.5
	t["fails"] = int(t["fails"]) + 1
	var sev := _rng.randf()
	var cuts := [0.5, 0.8, 0.95] if major else [0.6, 0.9, 0.99]
	var loss := 0.3
	if sev < float(cuts[0]):
		res["severity"] = "setback"
	elif sev < float(cuts[1]):
		res["severity"] = "strain"
		loss = 0.4
		strain_until = _day + 6
		injury_note = "Meridian strain"
	elif sev < float(cuts[2]):
		res["severity"] = "deviation"
		loss = 0.6
		deviation_until = _day + 12
		injury_note = "Qi deviation"
	else:
		res["severity"] = "backlash"
		loss = 0.8
		deviation_until = _day + 20
		injury_note = "Backlash"
		insight -= minf(insight, spent * 0.25)
	t["qi"] = float(t["qi"]) * (1.0 - loss)
	res["msg"] = "The breakthrough fails (%s)." % String(res["severity"])
	return res


# ----------------------------------------------------------------- manuals & techniques ----

func knows_manual(id: String) -> bool:
	return _manuals.has(id)


func learned_manuals(path := "") -> Array:
	return _manuals.filter(func(id: String) -> bool: return path == "" or String(manual(id).get("path", "")) == path)


## Study a manual (from a school, master, dungeon, tower or loot). Needs the path and to be within one realm of it.
func learn_manual(id: String) -> Dictionary:
	var m := manual(id)
	if m.is_empty():
		return {"ok": false, "reason": "unknown"}
	if _manuals.has(id):
		return {"ok": false, "reason": "known"}
	var path := String(m["path"])
	if not _tracks.has(path):
		return {"ok": false, "reason": "not_cultivating"}
	if realm_of(path) < int(m["realm"]) - 1:
		return {"ok": false, "reason": "too_advanced"}
	_manuals.append(id)
	var got := add_insight(1.0, "lore", "manual_" + id)
	return {"ok": true, "reason": "", "insight": got}


func technique_unlocked(id: String) -> bool:
	var t := technique(id)
	if t.is_empty() or not _tracks.has(String(t["path"])):
		return false
	var has_manual := false
	for mid: String in _manuals:
		if (manual(mid).get("techniques", []) as Array).has(id):
			has_manual = true
	if not has_manual:
		return false
	var p := String(t["path"])
	return stage_index(realm_of(p), stage_of(p)) >= stage_index(int(t["realm"]), int(t["stage"]))


## All techniques of a path with state: "locked" (no manual), "sealed" (manual, realm too low), "ready".
func technique_states(path: String) -> Array:
	var out: Array = []
	for t: Dictionary in techniques_of(path):
		var st := "locked"
		var has_manual := false
		for mid: String in _manuals:
			if (manual(mid).get("techniques", []) as Array).has(t["id"]):
				has_manual = true
		if has_manual:
			st = "ready" if technique_unlocked(String(t["id"])) else "sealed"
		out.append({"id": t["id"], "name": t["name"], "realm": t["realm"], "stage": t["stage"], "kind": t["kind"], "desc": t["desc"], "state": st})
	return out


# ----------------------------------------------------------------- power ----

func tempered(path := "") -> int:
	var n := 0
	for p: String in _tracks:
		if path == "" or p == path:
			n += int(_tracks[p]["tempered"])
	return n


## Power multiplier from cultivation: best track in full, other tracks at a fraction, plus tempering.
func power_multiplier() -> float:
	var best := 1.0
	var extra := 0.0
	for p: String in _tracks:
		var pm := position_power(int(_tracks[p]["realm"]), int(_tracks[p]["stage"]))
		if pm > best:
			extra += (best - 1.0) * 0.15
			best = pm
		else:
			extra += (pm - 1.0) * 0.15
	return best + extra + 0.03 * float(tempered())


## Level + cultivation + gear in one number (gear_mult from the items system, default 1).
func combined_power(gear_mult := 1.0) -> float:
	return Prog.power_share(prog.level) * power_multiplier() * gear_mult


func summary(path: String, opts: Dictionary = {}) -> Dictionary:
	if not _tracks.has(path):
		return {}
	var t: Dictionary = _tracks[path]
	var r := int(t["realm"])
	var s := int(t["stage"])
	var need_qi := stage_need_qi(r, s)
	return {"path": path, "realm": r, "stage": s, "label": stage_label(path, r, s), "realm_name": realm_name(path, r),
		"generic_realm": String(realm_def(r)["name"]), "qi_ratio": float(t["qi"]), "qi": int(round(float(t["qi"]) * need_qi)),
		"qi_need": need_qi, "primary": path == primary, "speed": speed_mult(path), "tempered": int(t["tempered"]),
		"fails": int(t["fails"]), "position": stage_index(r, s), "breakthrough": breakthrough_info(path, opts)}


# ----------------------------------------------------------------- realm hooks ----

func tick_day(day: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	_day = maxi(_day, day)
	toxicity = maxf(0.0, toxicity - 0.3)
	if _med_day != day:
		_med_day = day
		_med_hours = 0.0
	if deviation_until > 0 and _day >= deviation_until and injury_note != "":
		out.append("Your qi settles. You can cultivate again.")
		injury_note = ""
	elif strain_until > 0 and _day >= strain_until and deviation_until <= _day:
		injury_note = ""
	# "daily breath": a half hour of ambient cultivation on the primary path, never past a full bar.
	if primary != "" and not is_deviated():
		var t: Dictionary = _tracks[primary]
		var need := stage_need_eff(int(t["realm"]), int(t["stage"]))
		if float(t["qi"]) < 1.0:
			t["qi"] = minf(1.0, float(t["qi"]) + 0.5 * 0.6 * speed_mult(primary) / need)
	prog.prune(day)
	return out


func catch_up(days: int, ctx: Dictionary) -> Array:
	for i in mini(days, 30):
		tick_day(_day + 1, ctx)
	return []


func serialize() -> Dictionary:
	return {"prog": prog.serialize(), "primary": primary, "insight": insight, "insight_total": insight_total,
		"toxicity": toxicity, "strain": strain_until, "dev": deviation_until, "note": injury_note,
		"tracks": _tracks.duplicate(true), "manuals": _manuals.duplicate(), "flags": _flags.duplicate(),
		"stock": _stock.duplicate(), "day": _day, "med_day": _med_day, "med_h": _med_hours,
		"iseen": _insight_seen.duplicate(), "iday": _insight_day.duplicate(), "rng": str(_rng.state), "seed": _seed}


func deserialize(d: Dictionary) -> void:
	prog = Prog.new()
	if d.get("prog") is Dictionary:
		prog.deserialize(d["prog"])
	primary = String(d.get("primary", ""))
	insight = float(d.get("insight", 0.0))
	insight_total = float(d.get("insight_total", 0.0))
	toxicity = float(d.get("toxicity", 0.0))
	strain_until = int(d.get("strain", -1))
	deviation_until = int(d.get("dev", -1))
	injury_note = String(d.get("note", ""))
	_tracks = {}
	var ts: Dictionary = d.get("tracks", {})
	for p: String in ts:
		if not (data()["paths"] as Dictionary).has(p):
			continue
		var s: Dictionary = ts[p]
		_tracks[p] = {"realm": clampi(int(s.get("realm", 1)), 1, 10), "stage": clampi(int(s.get("stage", 1)), 1, STAGES),
			"qi": float(s.get("qi", 0.0)), "fails": int(s.get("fails", 0)), "tempered": int(s.get("tempered", 0)),
			"src": String(s.get("src", "self")), "order": int(s.get("order", 0)), "done": int(s.get("done", 0))}
	if primary != "" and not _tracks.has(primary):
		primary = ""
	_manuals = []
	for m in d.get("manuals", []):
		if not manual(String(m)).is_empty():
			_manuals.append(String(m))
	_flags = (d.get("flags", {}) as Dictionary).duplicate()
	_stock = {}
	for k in (d.get("stock", {}) as Dictionary):
		_stock[String(k)] = int(d["stock"][k])
	_day = int(d.get("day", 0))
	_med_day = int(d.get("med_day", -1))
	_med_hours = float(d.get("med_h", 0.0))
	_insight_seen = (d.get("iseen", {}) as Dictionary).duplicate()
	_insight_day = {}
	for k in (d.get("iday", {}) as Dictionary):
		_insight_day[String(k)] = int(d["iday"][k])
	_seed = int(d.get("seed", 424242))
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed
	if d.has("rng"):
		_rng.state = int(String(d["rng"]))


## Item hook (pills): adds `amount` qi to the main path's current stage. Returns the qi actually added.
func add_pill_qi(amount: float) -> int:
	var path := primary if _tracks.has(primary) else (String(cultivating()[0]) if not cultivating().is_empty() else "")
	if path == "":
		return 0
	var t: Dictionary = _tracks[path]
	var need := float(stage_need_qi(int(t["realm"]), int(t["stage"])))
	var before := float(t["qi"])
	t["qi"] = minf(float(data()["overflow_cap"]), before + amount / maxf(need, 1.0))
	return int(round((float(t["qi"]) - before) * need))
