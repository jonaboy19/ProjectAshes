extends "res://scripts/realm/realm_module.gd"
## Government (docs/design/CIVILIZATION.md CIV-B): named leaders for settlements, guilds, companies and
## orders (traits, ageing, death, retirement, succession by election / appointment / heredity), councils
## that vote on taxes, projects, laws and diplomacy, regional laws other systems enforce through
## `law(sid, key)`, public opinion per bloc with reactions (petition, strike, emigration pressure, revolt),
## and the player-led settlement API (priorities + appointments).
##
## Pure data, JSON-safe, deterministic (hash([WorldSim.SEED, tag, day, id])). Weekly work runs as daily
## slices (institution index % 7 == day % 7) inside tick_day_chunks, so every pump job stays tiny;
## catch_up is closed form (survival odds, exponential opinion drift, a couple of council sittings).
## Other modules read news_events() (cursor by "seq") -- see news.gd.

const Soc := preload("res://scripts/realm/society.gd")
const SAVE_VERSION := 1
const YEAR := 360
const TERM_DAYS := 1440
const LAW_ANGER := -0.25       # a bloc must be this unhappy before a council votes a law change
const PETITION_EASE_GAP := 600  # a petition is only heard if no law changed in this many days
const LAW_COOLDOWN := 2000     # days between agenda law changes in one settlement (laws are stable for years)
const BLOCS := ["merchants", "farmers", "soldiers", "scholars", "clergy", "poor", "outsiders"]
const SEATS := ["merchants", "military", "landowners", "guilds", "temple", "commons"]
const SEAT_BLOC := {"merchants": "merchants", "military": "soldiers", "landowners": "farmers", "guilds": "scholars",
	"temple": "clergy", "commons": "poor"}
const IDENT_SEAT := {"merchant": "merchants", "fortress": "military", "farming": "landowners", "religious": "temple",
	"mining": "guilds", "scholarly": "guilds", "criminal": "commons"}
const TRAITS := ["competence", "greed", "piety", "martial", "openness"]
const PRIORITIES := ["growth", "defence", "trade", "welfare", "faith", "outsiders"]
const ROLES := ["steward", "marshal", "treasurer", "priest"]
const TAX_MIN := 0.05
const TAX_MAX := 0.35
const EVENT_CAP := 30
const HIST_CAP := 40
const PROJECT_CAP := 24

## law key -> level names (index = level; higher is harsher / more closed).
const LAWS := {
	"weapons": ["free", "licensed", "restricted"],
	"hunting_rights": ["free", "licensed", "noble_only"],
	"monster_part_trade": ["free", "licensed", "banned"],
	"curfew": ["none", "night", "strict"],
	"land_ownership": ["free", "noble_only", "crown_only"],
	"guild_licensing": ["open", "licensed", "closed"],
	"magic_use": ["free", "licensed", "banned"],
	"conscription": ["none", "levy", "universal"],
}
## opinion change per law level, per bloc.
const LAW_SWAY := {
	"weapons": {"farmers": -0.10, "poor": -0.08, "outsiders": -0.12, "soldiers": 0.05, "merchants": 0.05},
	"hunting_rights": {"farmers": -0.12, "poor": -0.14, "outsiders": -0.05},
	"monster_part_trade": {"merchants": -0.14, "scholars": -0.08, "poor": -0.08, "clergy": 0.06},
	"curfew": {"poor": -0.08, "merchants": -0.10, "outsiders": -0.08, "soldiers": 0.06, "clergy": 0.06},
	"land_ownership": {"farmers": -0.12, "poor": -0.10, "merchants": -0.05, "soldiers": 0.04},
	"guild_licensing": {"merchants": -0.04, "poor": -0.10, "outsiders": -0.12, "scholars": 0.05},
	"magic_use": {"scholars": -0.16, "outsiders": -0.06, "clergy": 0.12},
	"conscription": {"farmers": -0.14, "poor": -0.12, "merchants": -0.06, "soldiers": 0.10},
}
## leader trait that pushes a law up (+) or down (-): law -> [trait, sign]
const LAW_TRAIT := {"weapons": ["martial", 1.0], "hunting_rights": ["greed", 1.0], "monster_part_trade": ["piety", 1.0],
	"curfew": ["martial", 1.0], "land_ownership": ["greed", 1.0], "guild_licensing": ["greed", 1.0],
	"magic_use": ["piety", 1.0], "conscription": ["martial", 1.0]}
const TAX_SWAY := {"merchants": 1.6, "farmers": 2.2, "soldiers": 0.4, "scholars": 0.8, "clergy": 0.6, "poor": 2.6, "outsiders": 1.2}
const TAX_SEAT := {"merchants": -1.0, "military": 0.8, "landowners": -1.0, "guilds": -0.6, "temple": 0.3, "commons": -1.0}
const PRIO_SWAY := {
	"growth": {"farmers": 0.05, "merchants": 0.05, "outsiders": 0.03},
	"defence": {"soldiers": 0.08, "poor": -0.03, "farmers": 0.02},
	"trade": {"merchants": 0.08, "outsiders": 0.04, "clergy": -0.02},
	"welfare": {"poor": 0.09, "farmers": 0.04, "merchants": -0.03},
	"faith": {"clergy": 0.09, "scholars": -0.04, "outsiders": -0.03},
	"outsiders": {"outsiders": 0.10, "poor": -0.04, "soldiers": -0.03},
}
const PROJECTS := {"market": "merchants", "walls": "soldiers", "school": "scholars", "temple": "clergy", "granary": "farmers",
	"hospital": "poor", "hostel": "outsiders"}
const DIPLO := ["open trade talks", "sign a border pact", "send envoys", "stiffen the border"]
const TITLE_OF := {"village": "headman", "town": "mayor", "frontier_town": "warden", "castle": "lord", "guild": "guildmaster",
	"company": "master", "order": "grand master", "state": "ruler"}
const KIND_SUCC := {"town": "election", "frontier_town": "appointment", "castle": "heredity"}
const SEED_COMPANIES := ["Greywater Trading Company", "Redwater Mercantile", "Ironmarch Carters"]
const SEED_ORDERS := ["Order of the Pale Lamp", "Ashen Fist", "Circle of Tallow"]

var _inst: Dictionary = {}      # id -> {id, kind, ref, name, sid, succ, leader, next_term, council, tax, prio, appoints, player}
var _order: Array = []          # stable institution order
var _ppl: Dictionary = {}       # pid -> {id, n, born, tr, inst, since, nid, heir}
var _op: Dictionary = {}        # str(sid) -> {bloc: opinion -1..1}
var _laws: Dictionary = {}      # str(sid) -> {law: level}
var _react: Dictionary = {}     # str(sid) -> {neg: {bloc: days}, pet: {bloc: day}, strike: day, revolt: day}
var _boost: Dictionary = {}     # str(sid) -> {bloc: bonus}
var _emig: Dictionary = {}      # str(sid) -> pressure 0..1
var _projects: Array = []       # {id, sid, kind, day, status}
var _hist: Array = []           # one-line history of dead / retired leaders
var _events: Array = []
var _seq := 0
var _next_p := 1
var _next_proj := 1
var _day := 0
var _at_war := false
var _built := false
var _mp_cache: Dictionary = {}
var _static: Dictionary = {}    # str(sid) -> {bloc: laws + tax + priorities + leadership term}; rebuilt when any of them changes


# ------------------------------------------------------------------ helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _skind(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["kind"])
	return "village"


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _emit(kind: String, sid: int, text: String, mag := 1.0, detail := "", official := true) -> void:
	_seq += 1
	_events.append({"seq": _seq, "kind": kind, "sid": sid, "day": _day, "mag": mag, "text": text, "detail": detail, "official": official})
	if _events.size() > EVENT_CAP:
		_events.pop_front()


## Other modules (news.gd) read this with a cursor on "seq".
func news_events(since := 0) -> Array:
	if since <= 0:
		return _events.duplicate(true)
	var out: Array = []
	for e: Dictionary in _events:
		if int(e["seq"]) > since:
			out.append(e.duplicate())
	return out


func chronicle() -> Array:
	return _hist.duplicate()


func _sync(ctx: Dictionary) -> void:
	_at_war = bool(ctx.get("at_war", _at_war))


# ------------------------------------------------------------------ people

func _pname(r: RandomNumberGenerator) -> String:
	return "%s%s %s" % [Soc.SYL_A[r.randi() % Soc.SYL_A.size()], Soc.SYL_B[r.randi() % Soc.SYL_B.size()], Soc.SURN[r.randi() % Soc.SURN.size()]]


func _roll_traits(r: RandomNumberGenerator) -> Dictionary:
	var t := {}
	for k: String in TRAITS:
		t[k] = snappedf(r.randf(), 0.01)
	t["competence"] = snappedf(0.25 + r.randf() * 0.7, 0.01)
	return t


func _new_person(tag: String, key: Variant, age_years: int, iid: String, base: Dictionary = {}) -> String:
	var pid := "p%d" % _next_p
	_next_p += 1
	var r := _rng("gperson", _day, [tag, key, pid])
	var p := {"id": pid, "n": String(base.get("n", _pname(r))), "born": int(base.get("born", _day - age_years * YEAR - r.randi() % YEAR)),
		"tr": (base.get("tr", _roll_traits(r)) as Dictionary).duplicate(), "inst": iid, "since": _day, "nid": String(base.get("nid", "")), "heir": {}}
	_ppl[pid] = p
	return pid


func _make_heir(pid: String) -> void:
	var p: Dictionary = _ppl[pid]
	var age := _age(p)
	if age < 30:
		p["heir"] = {}
		return
	var r := _rng("gheir", _day, pid)
	var tr := _roll_traits(r)
	# Children echo the parent.
	for k: String in TRAITS:
		tr[k] = snappedf(clampf(0.5 * float(tr[k]) + 0.5 * float((p["tr"] as Dictionary)[k]), 0.0, 1.0), 0.01)
	var sur := String(p["n"]).split(" ")[-1]
	p["heir"] = {"n": "%s%s %s" % [Soc.SYL_A[r.randi() % Soc.SYL_A.size()], Soc.SYL_B[r.randi() % Soc.SYL_B.size()], sur],
		"born": _day - maxi(16, age - 24 - r.randi() % 8) * YEAR, "tr": tr}


func _age(p: Dictionary) -> int:
	return int(floor(float(_day - int(p["born"])) / float(YEAR)))


func person(pid: String) -> Dictionary:
	var p: Dictionary = _ppl.get(pid, {})
	if p.is_empty():
		return {}
	var out := p.duplicate(true)
	out["age"] = _age(p)
	return out


# ------------------------------------------------------------------ build

func _ensure() -> void:
	if _built:
		return
	_built = true
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var kind := String(s["kind"])
		var r := _rng("gsett", 0, sid)
		var succ: String = String(KIND_SUCC.get(kind, ""))
		if succ == "":
			succ = "heredity" if r.randf() < 0.35 else "election"
		var iid := "s:%d" % sid
		_add_inst({"id": iid, "kind": "settlement", "ref": str(sid), "name": String(s["name"]), "sid": sid, "succ": succ,
			"council": kind != "village", "tax": snappedf(0.1 + r.randi() % 4 * 0.05, 0.01), "prio": {}, "appoints": {}, "player": false,
			"skind": kind}, r.randi_range(34, 64))
		_seed_laws(sid, kind, r)
		_op[str(sid)] = {}
		for b: String in BLOCS:
			(_op[str(sid)] as Dictionary)[b] = 0.0
		_react[str(sid)] = {"neg": {}, "pet": {}, "strike": -999, "revolt": -9999}
		_boost[str(sid)] = {}
		_emig[str(sid)] = 0.0
	var cl: Variant = _mod("city_life")
	if cl != null and cl.has_method("guilds"):
		for g: Dictionary in cl.guilds():
			var ld: Dictionary = g.get("leader", {})
			_add_inst({"id": String(g["id"]), "kind": "guild", "ref": String(g["id"]), "name": String(g["name"]), "sid": int(g["sid"]),
				"succ": "election", "council": false, "tax": 0.0, "prio": {}, "appoints": {}, "player": false},
				int(ld.get("age", 55)), {"n": String(ld.get("name", ""))})
	# People start at their settled mood, not at zero (no false wave of petitions on day one).
	for sid in WorldGen.settlements.size():
		var t := _target(sid)
		for b: String in BLOCS:
			(_op[str(sid)] as Dictionary)[b] = snappedf(float(t[b]), 0.001)
		_update_emigration(sid)
	for i in SEED_COMPANIES.size():
		var sid2 := (i * 7 + 1) % maxi(1, WorldGen.settlements.size())
		_add_inst({"id": "c:seed%d" % i, "kind": "company", "ref": "seed%d" % i, "name": SEED_COMPANIES[i], "sid": sid2, "succ": "heredity",
			"council": false, "tax": 0.0, "prio": {}, "appoints": {}, "player": false}, 40 + i * 6)
	for i in SEED_ORDERS.size():
		var sid3 := (i * 5 + 2) % maxi(1, WorldGen.settlements.size())
		_add_inst({"id": "o:seed%d" % i, "kind": "order", "ref": "seed%d" % i, "name": SEED_ORDERS[i], "sid": sid3, "succ": "appointment",
			"council": false, "tax": 0.0, "prio": {}, "appoints": {}, "player": false}, 50 + i * 4)


func _add_inst(def: Dictionary, leader_age: int, base: Dictionary = {}) -> String:
	var iid := String(def["id"])
	if _inst.has(iid):
		return iid
	def["next_term"] = _day + TERM_DAYS / 2 + int(_rng("gterm", 0, iid).randi() % TERM_DAYS)
	var pid := _new_person("lead", iid, leader_age, iid, base)
	def["leader"] = pid
	_inst[iid] = def
	_order.append(iid)
	if String(def["succ"]) == "heredity":
		_make_heir(pid)
	if String(def["kind"]) == "settlement":
		_inst[iid]["prio"] = _derive_prio(_ppl[pid])
	return iid


func _derive_prio(p: Dictionary) -> Dictionary:
	var tr: Dictionary = p["tr"]
	var w := {"growth": 0.5 + float(tr["competence"]) * 0.6, "defence": 0.3 + float(tr["martial"]), "trade": 0.3 + float(tr["greed"]),
		"welfare": 0.3 + (1.0 - float(tr["greed"])) * 0.7, "faith": 0.2 + float(tr["piety"]) * 0.9, "outsiders": 0.2 + float(tr["openness"])}
	return _norm(w)


static func _norm(w: Dictionary) -> Dictionary:
	var tot := 0.0
	for k: String in w:
		tot += maxf(0.0, float(w[k]))
	var out := {}
	for k: String in w:
		out[k] = snappedf(maxf(0.0, float(w[k])) / maxf(0.0001, tot), 0.001)
	return out


func _seed_laws(sid: int, kind: String, r: RandomNumberGenerator) -> void:
	var laws := {}
	for key: String in LAWS:
		var roll := r.randf()
		var lv := 0 if roll < 0.5 else (1 if roll < 0.85 else 2)
		if kind == "castle" and key in ["weapons", "conscription", "curfew", "land_ownership"]:
			lv += 1
		elif kind == "frontier_town" and key in ["weapons", "hunting_rights", "monster_part_trade"]:
			lv -= 1
		elif kind == "town" and key == "guild_licensing":
			lv += 1
		laws[key] = clampi(lv, 0, 2)
	_laws[str(sid)] = laws


# ------------------------------------------------------------------ laws API

func law_level(sid: int, key: String) -> int:
	_ensure()
	var l: Dictionary = _laws.get(str(sid), {})
	return int(l.get(key, 0))


## The law in force at a settlement as a level name, e.g. law(3, "weapons") == "restricted".
func law(sid: int, key: String) -> String:
	if not LAWS.has(key):
		return ""
	return String((LAWS[key] as Array)[law_level(sid, key)])


func laws_of(sid: int) -> Dictionary:
	_ensure()
	var out := {}
	for key: String in LAWS:
		out[key] = law(sid, key)
	return out


func set_law(sid: int, key: String, level: int, reason := "decree") -> bool:
	_ensure()
	if not LAWS.has(key) or not _laws.has(str(sid)):
		return false
	level = clampi(level, 0, 2)
	if law_level(sid, key) == level:
		return false
	(_laws[str(sid)] as Dictionary)[key] = level
	if _react.has(str(sid)):
		(_react[str(sid)] as Dictionary)["law"] = _day
	_static.erase(str(sid))
	_emit("law", sid, "%s now sets %s to \"%s\" (%s)." % [_sname(sid), key.replace("_", " "), law(sid, key), reason], 1.0, "", true)
	return true


## Enforcement hooks (each used in one place by gameplay).
func weapons_violation(sid: int, armed: bool) -> bool:
	return armed and sid >= 0 and law_level(sid, "weapons") >= 2


func curfew_active(sid: int, hour: int) -> bool:
	var lv := law_level(sid, "curfew")
	if lv <= 0:
		return false
	var start := 22 if lv == 1 else 20
	var end := 5 if lv == 1 else 6
	return hour >= start or hour < end


func hunting_allowed(sid: int) -> bool:
	return law_level(sid, "hunting_rights") < 2


## True when `item` is a monster part (drops in data/items/loot.json, excluding meat).
func is_monster_part(item: String) -> bool:
	if _mp_cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/loot.json"))
		_mp_cache["_"] = true
		if d is Dictionary:
			for m: Variant in (d.get("monsters", {}) as Dictionary).values():
				for drop: Variant in (m as Dictionary).get("drops", []):
					var id := String((drop as Array)[0])
					if not id.ends_with("_meat"):
						_mp_cache[id] = true
	return _mp_cache.has(item) and item != "_"


## Shop refusal text for selling/buying a monster part where the trade is banned, else "".
func refuses_item(sid: int, item: String) -> String:
	if sid >= 0 and law_level(sid, "monster_part_trade") >= 2 and is_monster_part(item):
		return "%s bans the monster-part trade. The shopkeeper will not touch it." % _sname(sid)
	return ""


func law_harshness(sid: int) -> float:
	_ensure()
	var tot := 0.0
	for key: String in LAWS:
		tot += float(law_level(sid, key))
	return tot / float(LAWS.size() * 2)


## Push factor for migration (CIV-A): bad laws + unhappy blocs + a strike.
func emigration_pressure(sid: int) -> float:
	_ensure()
	return float(_emig.get(str(sid), 0.0))


# ------------------------------------------------------------------ leaders API

func institutions(kind := "") -> Array:
	_ensure()
	var out: Array = []
	for iid: String in _order:
		if kind == "" or String(_inst[iid]["kind"]) == kind:
			out.append(institution(iid))
	return out


func institution(iid: String) -> Dictionary:
	_ensure()
	var d: Dictionary = (_inst.get(iid, {}) as Dictionary).duplicate(true)
	if d.is_empty():
		return d
	d["leader_info"] = person(String(d["leader"]))
	return d


func leader(iid: String) -> Dictionary:
	_ensure()
	var d: Dictionary = _inst.get(iid, {})
	return person(String(d.get("leader", ""))) if not d.is_empty() else {}


func leader_of_settlement(sid: int) -> Dictionary:
	return leader("s:%d" % sid)


func _quality(ins: Dictionary) -> float:
	var p: Dictionary = _ppl.get(String(ins["leader"]), {})
	if p.is_empty():
		return 0.5
	var tr: Dictionary = p["tr"]
	var q := 0.6 * float(tr["competence"]) + 0.25 * (1.0 - float(tr["greed"])) + 0.15 * float(tr["openness"])
	var ap: Dictionary = ins.get("appoints", {})
	if not ap.is_empty():
		var s := 0.0
		for role: String in ap:
			s += float((ap[role] as Dictionary).get("competence", 0.5))
		q += 0.12 * (s / float(ap.size()) - 0.5)
	return clampf(q, 0.0, 1.0)


## 0..1 quality of the settlement's leadership (traits + appointees).
func leader_quality(sid: int) -> float:
	_ensure()
	var d: Dictionary = _inst.get("s:%d" % sid, {})
	return _quality(d) if not d.is_empty() else 0.5


func register_institution(kind: String, ref: String, inst_name: String, sid: int, succ: String, lead: Dictionary) -> String:
	## An NPC-founded guild / company / order / state. `lead` = {n, born, tr, nid} (a notable).
	_ensure()
	var iid := "%s:%s" % [kind.substr(0, 1), ref]
	if _inst.has(iid):
		return iid
	_add_inst({"id": iid, "kind": kind, "ref": ref, "name": inst_name, "sid": sid, "succ": succ, "council": false, "tax": 0.0,
		"prio": {}, "appoints": {}, "player": false}, 40, lead)
	return iid


func notable_died(nid: String) -> bool:
	## A notable who led an institution has died: run that institution's succession.
	for iid: String in _order:
		var p: Dictionary = _ppl.get(String(_inst[iid]["leader"]), {})
		if not p.is_empty() and String(p.get("nid", "")) == nid:
			_succeed(iid, "death", [])
			return true
	return false


# ------------------------------------------------------------------ succession

func _title(ins: Dictionary) -> String:
	if String(ins["kind"]) == "settlement":
		return String(TITLE_OF.get(String(ins.get("skind", "village")), "headman"))
	return String(TITLE_OF.get(String(ins["kind"]), "leader"))


func _succeed(iid: String, reason: String, msgs: Array) -> void:
	var ins: Dictionary = _inst[iid]
	var old_id := String(ins["leader"])
	var old: Dictionary = _ppl.get(old_id, {})
	var title := _title(ins)
	var sid := int(ins["sid"])
	var r := _rng("gsucc", _day, iid)
	var new_id := ""
	var how := String(ins["succ"])
	if reason == "deposed":
		how = "election" if how != "heredity" else "appointment"
	# Notables can take a chair ("the boy you met at 10 now governs Emberford").
	var nm: Variant = _mod("notables")
	var cand: Dictionary = {}
	if nm != null and nm.has_method("recruit_leader") and not bool(ins["player"]) and r.randf() < 0.3 \
			and (String(ins["kind"]) == "settlement" or String(ins["kind"]) == "guild"):
		cand = nm.recruit_leader(iid, sid)
	if not cand.is_empty():
		new_id = _new_person("notable", iid, 40, iid, cand)
		how = "notable"
	elif how == "heredity" and not old.is_empty() and not (old["heir"] as Dictionary).is_empty():
		new_id = _new_person("heir", iid, 25, iid, old["heir"])
	else:
		var best := -1.0
		for i in 3:
			var c := _new_person("cand", [iid, i], r.randi_range(32, 62), iid)
			var cp: Dictionary = _ppl[c]
			var tr: Dictionary = cp["tr"]
			var sc := float(tr["competence"]) * (0.6 if how == "appointment" else 0.4) + r.randf() * 0.4
			if how == "election":
				var ops: Dictionary = _op.get(str(sid), {})
				# Discontent favours change: a martial candidate when soldiers shout, a generous one when the poor do.
				sc += 0.3 * float(tr["martial"]) * (1.0 + float(ops.get("soldiers", 0.0))) * 0.5
				sc += 0.3 * (1.0 - float(tr["greed"])) * (1.0 - float(ops.get("poor", 0.0))) * 0.5
			if sc > best:
				if new_id != "":
					_ppl.erase(new_id)
				best = sc
				new_id = c
			else:
				_ppl.erase(c)
		how = how if how != "" else "election"
	var np: Dictionary = _ppl[new_id]
	np["inst"] = iid
	np["since"] = _day
	ins["leader"] = new_id
	_static.erase(str(sid))
	ins["next_term"] = _day + TERM_DAYS
	if String(ins["succ"]) == "heredity" or how == "heredity":
		_make_heir(new_id)
	if String(ins["kind"]) == "settlement":
		if not bool(ins["player"]):
			ins["prio"] = _derive_prio(np)
		_boost[str(sid)] = _boost.get(str(sid), {})
		for b: String in BLOCS:
			(_boost[str(sid)] as Dictionary)[b] = float((_boost[str(sid)] as Dictionary).get(b, 0.0)) + 0.12   # honeymoon
	var cl: Variant = _mod("city_life")
	if String(ins["kind"]) == "guild" and cl != null and cl.has_method("set_guild_leader"):
		cl.set_guild_leader(iid, String(np["n"]), _age(np))
	var line := ""
	if not old.is_empty():
		var verb: String = {"death": "died", "retire": "retired", "term": "lost office", "deposed": "was deposed"}.get(reason, "left office")
		line = "%s, %s of %s, %s in year %d (age %d)." % [old["n"], title, ins["name"], verb, _day / YEAR + 1, _age(old)]
		_hist.append(line)
		if _hist.size() > HIST_CAP:
			_hist.pop_front()
		_ppl.erase(old_id)
	var how_txt: String = {"election": "elected", "appointment": "appointed", "heredity": "inherited the seat as", "notable": "chosen as"}.get(how, "named")
	var text := "%s %s %s of %s%s." % [np["n"], how_txt, title, ins["name"], (" after the " + title + " " + ("died" if reason == "death" else "stepped down")) if reason in ["death", "retire"] else ""]
	var is_sett := String(ins["kind"]) == "settlement"
	_emit("succession", sid, text, 2.0 if is_sett else 0.6, line, is_sett or String(ins["kind"]) in ["order", "state"])
	if String(ins["kind"]) == "settlement":
		msgs.append(text)


func _death_hazard(age: int) -> float:
	if age < 50:
		return 0.004
	if age < 60:
		return 0.012
	if age < 70:
		return 0.035
	if age < 80:
		return 0.09
	return 0.22


func _retire_hazard(age: int) -> float:
	return 0.0 if age < 58 else minf(0.6, 0.10 + float(age - 58) * 0.03)


func _reelect_prob(ins: Dictionary) -> float:
	if String(ins["kind"]) == "settlement":
		var ops: Dictionary = _op.get(str(int(ins["sid"])), {})
		var m := 0.0
		for b: String in BLOCS:
			m += float(ops.get(b, 0.0))
		m /= float(BLOCS.size())
		return clampf(0.76 + 0.6 * m + 0.25 * (_quality(ins) - 0.5), 0.05, 0.95)
	return 0.85


## One institution's weekly step (dt = 7 days when sliced, `days` in catch-up).
func _leader_step(iid: String, dt: float, msgs: Array) -> void:
	var ins: Dictionary = _inst[iid]
	var p: Dictionary = _ppl.get(String(ins["leader"]), {})
	if p.is_empty() or bool(ins["player"]):
		return
	var r := _rng("gstep", _day, iid)
	var age := _age(p)
	if String(p.get("nid", "")) == "":   # notables die in notables.gd and call notable_died()
		var pd := 1.0 - pow(1.0 - _death_hazard(age), dt / float(YEAR))
		if r.randf() < pd:
			_succeed(iid, "death", msgs)
			return
	var pr := 1.0 - pow(1.0 - _retire_hazard(age), dt / float(YEAR))
	if r.randf() < pr:
		_succeed(iid, "retire", msgs)
		return
	if String(ins["succ"]) != "heredity" and _day >= int(ins["next_term"]):
		if r.randf() < _reelect_prob(ins):
			ins["next_term"] = _day + TERM_DAYS
			_emit("reelected", int(ins["sid"]), "%s keeps the seat of %s." % [p["n"], ins["name"]], 0.5, "", false)
		else:
			_succeed(iid, "term", msgs)


# ------------------------------------------------------------------ opinion

func opinion(sid: int, bloc: String) -> float:
	_ensure()
	return float((_op.get(str(sid), {}) as Dictionary).get(bloc, 0.0))


func opinions(sid: int) -> Dictionary:
	_ensure()
	return (_op.get(str(sid), {}) as Dictionary).duplicate()


## Mean approval of the ruler, 0..100 (player-led settlements are judged per bloc via approval()).
func approval(sid: int) -> Dictionary:
	var out := {}
	for b: String in BLOCS:
		out[b] = int(round(50.0 + 50.0 * opinion(sid, b)))
	return out


static var _law_vec: Dictionary = {}     # law -> [per-bloc sway]   (built once)
static var _prio_vec: Dictionary = {}    # priority -> [per-bloc sway]
static var _tax_vec: Array = []


static func _build_vecs() -> void:
	if not _tax_vec.is_empty():
		return
	for key: String in LAWS:
		var v: Array = []
		for b: String in BLOCS:
			v.append(float((LAW_SWAY[key] as Dictionary).get(b, 0.0)))
		_law_vec[key] = v
	for pk: String in PRIORITIES:
		var v2: Array = []
		for b: String in BLOCS:
			v2.append(float((PRIO_SWAY[pk] as Dictionary).get(b, 0.0)))
		_prio_vec[pk] = v2
	for b: String in BLOCS:
		_tax_vec.append(float(TAX_SWAY[b]))


func _static_terms(sid: int) -> Dictionary:
	var k := str(sid)
	if _static.has(k):
		return _static[k]
	_build_vecs()
	var ins: Dictionary = _inst["s:%d" % sid]
	var laws: Dictionary = _laws[k]
	var prio: Dictionary = ins.get("prio", {})
	var tax := float(ins["tax"])
	var nb := BLOCS.size()
	var acc: Array = []
	var lead := 0.12 + (_quality(ins) - 0.5) * 0.8
	for i in nb:
		acc.append(lead - (tax - 0.15) * float(_tax_vec[i]))
	for key: String in LAWS:
		var lv := float(laws[key])
		if lv > 0.0:
			var vec: Array = _law_vec[key]
			for i in nb:
				acc[i] = float(acc[i]) + float(vec[i]) * lv
	for pk: String in PRIORITIES:
		var w := float(prio.get(pk, 1.0 / 6.0)) * 6.0 - 1.0
		if absf(w) > 0.001:
			var vec2: Array = _prio_vec[pk]
			for i in nb:
				acc[i] = float(acc[i]) + float(vec2[i]) * w
	var t := {}
	for i in nb:
		t[BLOCS[i]] = acc[i]
	_static[k] = t
	return t


func _target(sid: int) -> Dictionary:
	var k := str(sid)
	var base: Dictionary = _static_terms(sid)
	var bo: Dictionary = _boost.get(k, {})
	var short := 0.0
	var emerg := 0.0
	var st: Variant = _mod("settlements")
	if st != null:
		short = float((st.shortages(sid) as Dictionary).size())
		emerg = float((st.emergencies(sid) as Array).size())
	var need := minf(0.5, short * 0.12)
	var t := {}
	for b: String in BLOCS:
		var v := float(base[b]) - emerg * 0.06 + float(bo.get(b, 0.0))
		if b == "farmers" or b == "poor":
			v -= need
		if _at_war:
			v += 0.08 if b == "soldiers" else (-0.06 if b == "poor" else 0.0)
		t[b] = clampf(v, -1.0, 1.0)
	return t


func _opinion_step(sid: int, days: float) -> void:
	var t := _target(sid)
	var k := str(sid)
	var f := 1.0 - exp(-days / 20.0)
	var o: Dictionary = _op[k]
	for b: String in BLOCS:
		o[b] = snappedf(float(o[b]) + (float(t[b]) - float(o[b])) * f, 0.001)
	var bo: Dictionary = _boost[k]
	var keep := pow(0.97, days)
	for b: String in bo.keys():
		bo[b] = snappedf(float(bo[b]) * keep, 0.001)
		if absf(float(bo[b])) < 0.004:
			bo.erase(b)
	_update_emigration(sid)


func _update_emigration(sid: int) -> void:
	var k := str(sid)
	var o: Dictionary = _op[k]
	var neg := 0.0
	for b: String in BLOCS:
		neg += maxf(0.0, -float(o[b]))
	var strike := 0.15 if int((_react[k] as Dictionary)["strike"]) + 10 > _day else 0.0
	_emig[k] = snappedf(clampf(neg / float(BLOCS.size()) * 1.5 + law_harshness(sid) * 0.35 + strike, 0.0, 1.0), 0.001)


func _reactions(sid: int, msgs: Array, dt := 1) -> void:
	var k := str(sid)
	var rc: Dictionary = _react[k]
	var o: Dictionary = _op[k]
	var neg: Dictionary = rc["neg"]
	var worst := ""
	var wv := 1.0
	var mean := 0.0
	for b: String in BLOCS:
		var v := float(o[b])
		mean += v / float(BLOCS.size())
		neg[b] = int(neg.get(b, 0)) + dt if v < -0.4 else maxi(0, int(neg.get(b, 0)) - 2 * dt)
		if v < wv:
			wv = v
			worst = b
	if worst == "":
		return
	var r := _rng("greact", _day, sid)
	var name := _sname(sid)
	if _day < 90:
		return   # a fresh world gets a season of grace before anyone takes to the streets
	if wv < -0.4 and int(neg[worst]) >= 10 and _day - int((rc["pet"] as Dictionary).get(worst, -999)) > 60 and _day - int(rc.get("law", -99999)) > PETITION_EASE_GAP:
		(rc["pet"] as Dictionary)[worst] = _day
		_emit("petition", sid, "The %s of %s petition their %s." % [worst, name, _title(_inst["s:%d" % sid])], 1.0,
			"They want the laws that hurt them eased.", true)
		# A petition is heard: the council or lord eases the harshest law that bloc dislikes.
		_ease_for(sid, worst)
	if wv < -0.62 and int(neg[worst]) >= 25 and _day - int(rc["strike"]) > 120:
		rc["strike"] = _day
		_emit("strike", sid, "The %s of %s have downed tools." % [worst, name], 2.0, "", true)
		var st: Variant = _mod("settlements")
		if st != null and st.has_method("_start"):
			st.call("_start", sid, "strike", 0.4)
		msgs.append("The %s of %s have downed tools in protest." % [worst, name])
	if wv < -0.8 and mean < -0.35 and int(neg[worst]) >= 45 and _day - int(rc["revolt"]) > 360 and r.randf() < 0.5:
		rc["revolt"] = _day
		_emit("revolt", sid, "Revolt in %s! The %s drive out their %s." % [name, worst, _title(_inst["s:%d" % sid])], 3.0, "", true)
		msgs.append("Revolt in %s! The ruler has been driven out." % name)
		_ease_for(sid, worst)
		_ease_for(sid, worst)
		_succeed("s:%d" % sid, "deposed", msgs)
		for b: String in BLOCS:
			neg[b] = 0


func _ease_for(sid: int, bloc: String) -> void:
	var ins: Dictionary = _inst["s:%d" % sid]
	if bloc in ["poor", "farmers", "merchants"] and float(ins["tax"]) > 0.1 and not bool(ins["player"]):
		ins["tax"] = snappedf(float(ins["tax"]) - 0.05, 0.01)
		_static.erase(str(sid))
	var best := ""
	var bv := 0.0
	for key: String in LAWS:
		var c := float((LAW_SWAY[key] as Dictionary).get(bloc, 0.0))
		if c < 0.0 and law_level(sid, key) > 0 and -c * float(law_level(sid, key)) > bv:
			bv = -c * float(law_level(sid, key))
			best = key
	if best != "":
		set_law(sid, best, law_level(sid, best) - 1, "after petition")


## External shock (war, plague, a hero's feat): nudges opinion directly. deltas {bloc: amount}.
func shock(sid: int, deltas: Dictionary, reason := "") -> void:
	_ensure()
	var bo: Dictionary = _boost.get(str(sid), {})
	for b: String in deltas:
		bo[b] = float(bo.get(b, 0.0)) + float(deltas[b])
	_boost[str(sid)] = bo
	if reason != "":
		_emit("mood", sid, "%s: %s" % [_sname(sid), reason], 0.5, "", false)


# ------------------------------------------------------------------ councils

func _seat_power(sid: int) -> Dictionary:
	var out := {}
	var dom := ""
	var st: Variant = _mod("settlements")
	if st != null:
		dom = String(st.dominant(sid))
	var r := _rng("gseat", 0, sid)
	for s: String in SEATS:
		out[s] = 1.0 + r.randf() * 0.5
	if IDENT_SEAT.has(dom):
		out[IDENT_SEAT[dom]] = float(out[IDENT_SEAT[dom]]) + 1.5
	return out


func council(sid: int) -> Dictionary:
	_ensure()
	var d: Dictionary = _inst.get("s:%d" % sid, {})
	if d.is_empty() or not bool(d["council"]):
		return {}
	return {"seats": _seat_power(sid), "leader": leader_of_settlement(sid), "tax": float(d["tax"])}


func _leader_push(sid: int, prop: Dictionary) -> float:
	## -1..1: which way the ruler leans on this proposal.
	var p: Dictionary = _ppl.get(String((_inst["s:%d" % sid] as Dictionary)["leader"]), {})
	if p.is_empty():
		return 0.0
	var tr: Dictionary = p["tr"]
	match String(prop["kind"]):
		"law":
			var lt: Array = LAW_TRAIT[String(prop["key"])]
			var dir := 1.0 if int(prop["delta"]) > 0 else -1.0
			return clampf((float(tr[lt[0]]) - 0.5) * 2.0 * dir, -1.0, 1.0)
		"tax":
			var dir2 := 1.0 if float(prop["delta"]) > 0.0 else -1.0
			return clampf((float(tr["greed"]) - 0.5) * 2.0 * dir2, -1.0, 1.0)
		"project":
			return clampf((float(tr["competence"]) - 0.4) * 1.6, -1.0, 1.0)
		"diplomacy":
			return clampf((float(tr["openness"]) - 0.5) * 2.0, -1.0, 1.0)
	return 0.0


func _seat_score(seat: String, sid: int, prop: Dictionary, r: RandomNumberGenerator) -> float:
	match String(prop["kind"]):
		"law":
			var c := float((LAW_SWAY[String(prop["key"])] as Dictionary).get(SEAT_BLOC[seat], 0.0))
			return c * (1.0 if int(prop["delta"]) > 0 else -1.0)
		"tax":
			return float(TAX_SEAT[seat]) * (1.0 if float(prop["delta"]) > 0.0 else -1.0)
		"project":
			if String(PROJECTS[String(prop["key"])]) == String(SEAT_BLOC[seat]):
				return 1.0
			return 0.3 if r.randf() < 0.6 else -0.3
		"diplomacy":
			var pk := int(prop["idx"])
			if seat == "military":
				return -0.6 if pk == 0 or pk == 2 else 0.5
			if seat == "merchants":
				return 0.8 if pk == 0 else (0.3 if pk == 1 else -0.4)
			return 0.3 if r.randf() < 0.55 else -0.3
	return 0.0


## Weighted vote of the council (or the ruler's decree when there is none). Returns {passed, yes, total}.
func vote(sid: int, prop: Dictionary) -> Dictionary:
	_ensure()
	var ins: Dictionary = _inst["s:%d" % sid]
	var r := _rng("gvote", _day, [sid, String(prop["kind"]), String(prop.get("key", ""))])
	var push := _leader_push(sid, prop)
	if not bool(ins["council"]):
		var p_ok := clampf(0.5 + 0.4 * push, 0.05, 0.95)
		var ok := r.randf() < p_ok
		return {"passed": ok, "yes": 1.0 if ok else 0.0, "total": 1.0}
	var pw := _seat_power(sid)
	var yes := 0.0
	var total := 0.0
	for seat: String in SEATS:
		var sc := _seat_score(seat, sid, prop, r)
		if absf(sc) < 0.001:
			continue
		total += float(pw[seat])
		if sc > 0.0:
			yes += float(pw[seat])
	# The ruler carries the weight of about one seat.
	total += 1.3
	if push > 0.0:
		yes += 1.3 * push
	elif push < 0.0:
		total += 0.0
	return {"passed": total > 0.0 and yes / total > 0.5, "yes": snappedf(yes, 0.01), "total": snappedf(total, 0.01)}


func propose(sid: int, prop: Dictionary) -> Dictionary:
	## Public entry (player-led settlements, tests): vote and apply.
	var res := vote(sid, prop)
	if bool(res["passed"]):
		_apply(sid, prop)
	return res


func _apply(sid: int, prop: Dictionary) -> void:
	var ins: Dictionary = _inst["s:%d" % sid]
	var name := _sname(sid)
	match String(prop["kind"]):
		"law":
			set_law(sid, String(prop["key"]), law_level(sid, String(prop["key"])) + int(prop["delta"]), "council vote" if bool(ins["council"]) else "decree")
		"tax":
			ins["tax"] = snappedf(clampf(float(ins["tax"]) + float(prop["delta"]), TAX_MIN, TAX_MAX), 0.01)
			_static.erase(str(sid))
			_emit("tax", sid, "%s sets its tax at %d%%." % [name, int(round(float(ins["tax"]) * 100.0))], 1.0, "", true)
		"project":
			var kind := String(prop["key"])
			_projects.append({"id": _next_proj, "sid": sid, "kind": kind, "day": _day, "status": "approved"})
			_next_proj += 1
			if _projects.size() > PROJECT_CAP:
				_projects.pop_front()
			var bo: Dictionary = _boost[str(sid)]
			var bl := String(PROJECTS[kind])
			bo[bl] = float(bo.get(bl, 0.0)) + 0.10
			_emit("project", sid, "%s approves a new %s." % [name, kind.replace("_", " ")], 1.5, "", true)
			var civ: Variant = _mod("civilization")
			if civ != null and civ.has_method("request_project"):
				civ.request_project(sid, kind)
		"diplomacy":
			var idx := int(prop["idx"])
			_emit("diplomacy", sid, "%s resolves to %s." % [name, DIPLO[idx]], 1.0, "", true)
			var fa: Variant = _mod("factions")
			if fa != null and fa.has_method("change_relation"):
				var nations: Array = []
				for f: Dictionary in fa.factions():
					if String(f["kind"]) == "nation" and String(f["id"]) != "caldrenn":
						nations.append(String(f["id"]))
				if not nations.is_empty():
					var pick: String = nations[_rng("gdip", _day, sid).randi() % nations.size()]
					fa.change_relation("caldrenn", pick, "trade" if idx == 0 else "trust", 5.0 if idx < 3 else -5.0)


func _agenda(sid: int) -> void:
	var ins: Dictionary = _inst["s:%d" % sid]
	var r := _rng("gagenda", _day, sid)
	var roll := r.randf()
	var prop: Dictionary = {}
	var worst_v := 1.0
	for b2: String in BLOCS:
		worst_v = minf(worst_v, float((_op[str(sid)] as Dictionary)[b2]))
	var rc_l: Dictionary = _react[str(sid)]
	if roll < 0.5 and (worst_v > LAW_ANGER or _day - int(rc_l.get("law", -99999)) < LAW_COOLDOWN):
		roll = 0.75   # nobody is angry enough to change a law (or one was changed recently): build something instead
	if roll < 0.5:
		# Law: the most discontented bloc asks for the change that helps it most.
		var ops: Dictionary = _op[str(sid)]
		var worst := BLOCS[0] as String
		for b: String in BLOCS:
			if float(ops[b]) < float(ops[worst]):
				worst = b
		var bestv := -1.0
		for key: String in LAWS:
			for delta in [-1, 1]:
				var nl: int = law_level(sid, key) + int(delta)
				if nl < 0 or nl > 2:
					continue
				var gain := float((LAW_SWAY[key] as Dictionary).get(worst, 0.0)) * float(delta) + r.randf() * 0.12
				# Rulers also want their own way: a martial lord likes harsher security laws.
				gain += 0.05 * _leader_push(sid, {"kind": "law", "key": key, "delta": delta})
				if gain > bestv:
					bestv = gain
					prop = {"kind": "law", "key": key, "delta": delta}
		if bestv < 0.05:
			prop = {}
	elif roll < 0.68:
		var low := float((_op[str(sid)] as Dictionary)["poor"]) + float((_op[str(sid)] as Dictionary)["farmers"]) < -0.4
		var up := (not low) and r.randf() < 0.55
		var dlt := 0.05 if up else -0.05
		if float(ins["tax"]) + dlt >= TAX_MIN and float(ins["tax"]) + dlt <= TAX_MAX:
			prop = {"kind": "tax", "delta": dlt}
	elif roll < 0.92:
		var busy := false
		for pj: Dictionary in _projects:
			if int(pj["sid"]) == sid and _day - int(pj["day"]) < 150:
				busy = true
		if busy:
			return
		var keys: Array = PROJECTS.keys()
		# Build what the unhappiest bloc lacks.
		var worst2 := ""
		var wv := 2.0
		for k: String in keys:
			var v := float((_op[str(sid)] as Dictionary)[String(PROJECTS[k])])
			if v + r.randf() * 0.4 < wv:
				wv = v + r.randf() * 0.4
				worst2 = k
		prop = {"kind": "project", "key": worst2}
	else:
		prop = {"kind": "diplomacy", "idx": r.randi() % DIPLO.size()}
	if prop.is_empty():
		return
	var res := vote(sid, prop)
	if bool(res["passed"]):
		_apply(sid, prop)


# ------------------------------------------------------------------ player-led settlements

func set_player_ruler(sid: int, on: bool, player_name := "You", competence := 0.5) -> bool:
	_ensure()
	var ins: Dictionary = _inst.get("s:%d" % sid, {})
	if ins.is_empty():
		return false
	ins["player"] = on
	_static.erase(str(sid))
	if on:
		var old := String(ins["leader"])
		var pid := _new_person("player", sid, 30, "s:%d" % sid, {"n": player_name, "tr": {"competence": competence, "greed": 0.4, "piety": 0.5,
			"martial": 0.5, "openness": 0.5}})
		ins["leader"] = pid
		_ppl.erase(old)
		ins["prio"] = _norm({"growth": 1, "defence": 1, "trade": 1, "welfare": 1, "faith": 1, "outsiders": 1})
	return true


## Priorities {growth, defence, trade, welfare, faith, outsiders} -> weights (normalised). Player-led only;
## NPC rulers keep priorities drawn from their traits.
func set_priorities(sid: int, weights: Dictionary) -> bool:
	_ensure()
	var ins: Dictionary = _inst.get("s:%d" % sid, {})
	if ins.is_empty() or not bool(ins["player"]):
		return false
	var w := {}
	for k: String in PRIORITIES:
		w[k] = float(weights.get(k, 0.0)) + 0.02
	ins["prio"] = _norm(w)
	_static.erase(str(sid))
	return true


func priorities(sid: int) -> Dictionary:
	_ensure()
	return ((_inst.get("s:%d" % sid, {}) as Dictionary).get("prio", {}) as Dictionary).duplicate()


## Appoints a steward / marshal / treasurer / priest. `who` = {name, competence}; works for NPC rulers too.
func appoint(sid: int, role: String, who: Dictionary) -> bool:
	_ensure()
	var ins: Dictionary = _inst.get("s:%d" % sid, {})
	if ins.is_empty() or not ROLES.has(role):
		return false
	_static.erase(str(sid))
	(ins["appoints"] as Dictionary)[role] = {"name": String(who.get("name", "An appointee")), "competence": clampf(float(who.get("competence", 0.5)), 0.0, 1.0)}
	_emit("appointment", sid, "%s appoints %s as %s of %s." % [leader_of_settlement(sid).get("n", "The ruler"), who.get("name", "someone"), role, _sname(sid)], 0.5, "", true)
	return true


func appointments(sid: int) -> Dictionary:
	return ((_inst.get("s:%d" % sid, {}) as Dictionary).get("appoints", {}) as Dictionary).duplicate(true)


func tax(sid: int) -> float:
	_ensure()
	return float((_inst.get("s:%d" % sid, {}) as Dictionary).get("tax", 0.15))


func set_tax(sid: int, value: float) -> bool:
	var ins: Dictionary = _inst.get("s:%d" % sid, {})
	if ins.is_empty() or not bool(ins["player"]):
		return false
	ins["tax"] = snappedf(clampf(value, TAX_MIN, TAX_MAX), 0.01)
	_static.erase(str(sid))
	return true


func projects(sid := -1) -> Array:
	var out: Array = []
	for p: Dictionary in _projects:
		if sid < 0 or int(p["sid"]) == sid:
			out.append(p.duplicate())
	return out


func set_law_by_player(sid: int, key: String, level: int) -> bool:
	var ins: Dictionary = _inst.get("s:%d" % sid, {})
	if ins.is_empty() or not bool(ins["player"]):
		return false
	return set_law(sid, key, level, "your decree")


# ------------------------------------------------------------------ ticks

## A settlement's mood is updated every third day (closed form over the 3 days), then its blocs may react.
func _mood(sid: int, msgs: Array) -> void:
	_opinion_step(sid, 3.0)
	_reactions(sid, msgs, 3)


func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	return [
		func() -> Array:
			_sync(ctx)
			_day = day
			_ensure()
			return [],
		func() -> Array:
			var msgs: Array = []
			var slice := day % 7
			for i in _order.size():
				if i % 7 == slice:
					_leader_step(String(_order[i]), 7.0, msgs)
			return msgs,
		func() -> Array:
			var msgs: Array = []
			var n := WorldGen.settlements.size()
			for sid in range(0, (n + 1) / 2):
				if sid % 3 == day % 3:
					_mood(sid, msgs)
			return msgs,
		func() -> Array:
			var msgs: Array = []
			var n := WorldGen.settlements.size()
			for sid in range((n + 1) / 2, n):
				if sid % 3 == day % 3:
					_mood(sid, msgs)
			return msgs,
		func() -> Array:
			for sid in WorldGen.settlements.size():
				if day % 30 == sid % 30:
					_agenda(sid)
			return [],
	]


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	if days <= 0:
		return msgs
	_sync(ctx)
	_ensure()
	var start := _day
	_day += days
	var end_day := _day
	for iid: String in _order.duplicate():
		if _inst.has(iid):
			_leader_step(iid, float(days), msgs)
	# A few evenly spaced sittings stand in for the span: opinion moves in closed form between them, and the
	# councils and petitions respond to it (bounded work, O(settlements)).
	var n := WorldGen.settlements.size()
	var sittings := mini(6, days / 30)
	var step := float(days) / float(sittings + 1)
	for i in sittings:
		_day = start + int(step * float(i + 1))
		for sid in n:
			_opinion_step(sid, step)
			_reactions(sid, msgs, int(step))
			_agenda(sid)
	_day = end_day
	for sid in n:
		_opinion_step(sid, step)
	return msgs


# ------------------------------------------------------------------ info

func stats() -> Dictionary:
	_ensure()
	return {"institutions": _order.size(), "people": _ppl.size(), "projects": _projects.size(), "history": _hist.size(), "events": _events.size()}


func serialize() -> Dictionary:
	var ops := {}
	for k: String in _op:
		ops[k] = (_op[k] as Dictionary).duplicate()
	return {"v": SAVE_VERSION, "inst": _inst.duplicate(true), "order": _order.duplicate(), "ppl": _ppl.duplicate(true), "op": ops,
		"laws": _laws.duplicate(true), "react": _react.duplicate(true), "boost": _boost.duplicate(true), "emig": _emig.duplicate(),
		"projects": _projects.duplicate(true), "hist": _hist.duplicate(), "events": _events.duplicate(true), "seq": _seq, "next_p": _next_p,
		"next_proj": _next_proj, "day": _day, "war": _at_war, "built": _built}


func deserialize(d: Dictionary) -> void:
	_inst = (d.get("inst", {}) as Dictionary).duplicate(true)
	_order = (d.get("order", []) as Array).duplicate()
	_ppl = (d.get("ppl", {}) as Dictionary).duplicate(true)
	_op = (d.get("op", {}) as Dictionary).duplicate(true)
	_laws = (d.get("laws", {}) as Dictionary).duplicate(true)
	_react = (d.get("react", {}) as Dictionary).duplicate(true)
	_boost = (d.get("boost", {}) as Dictionary).duplicate(true)
	_emig = (d.get("emig", {}) as Dictionary).duplicate()
	_projects = (d.get("projects", []) as Array).duplicate(true)
	_hist = (d.get("hist", []) as Array).duplicate()
	_events = (d.get("events", []) as Array).duplicate(true)
	_seq = int(d.get("seq", 0))
	_next_p = int(d.get("next_p", 1))
	_next_proj = int(d.get("next_proj", 1))
	_day = int(d.get("day", 0))
	_at_war = bool(d.get("war", false))
	_built = bool(d.get("built", false))
	_mp_cache.clear()
	_static.clear()
