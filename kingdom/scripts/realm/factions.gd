extends "res://scripts/realm/realm_module.gd"
## Factions (docs/design/REALM_WAR_SETTLEMENT.md R§22-28).
## Pure data. Nations come from data/world/nations.json, noble houses from
## ctx.life.nobility.houses when reachable (otherwise an own deterministic seed),
## plus the Church and a few sects / independent powers.
##
## R§23 relation matrix (trust, fear, grievance, trade) per unordered pair.
## R§24 ties: kin, debt, rivalry, alliance, guarantee, marriage (some hidden).
## R§25 political marriages: proposals accepted on interest, create alliances,
##      inheritance claims and rivalries.
## R§26 paths to kingship, tracked per path (nothing is announced as a quest).
## R§27 church influence per region.  R§28 sects rise, grow, may become factions.
## R§22 war reputation per actor.
##
## Hooks other systems may call: change_relation(), record_war_act(),
## add_kingship_progress(), propose_marriage(), discover_tie().

const NATIONS_PATH := "res://data/world/nations.json"
const PLAYER := "player"
const CHURCH := "church"
const HOUSE_MAX := 8
const STANCE_TRUST := {"allied": 85.0, "friendly": 62.0, "neutral": 42.0, "wary": 26.0, "hostile": 10.0, "war": 0.0}
const FIELDS := ["trust", "fear", "grievance", "trade"]
const KINGSHIP_PATHS := ["inheritance", "election", "conquest", "coronation", "uprising"]
const SECT_KINDS := ["martial_sect", "religious_order", "merchant_league", "mage_academy", "beast_clan",
	"mercenary_company", "rift_expedition", "criminal_org", "tribal_confederation"]
const SECT_NAMES := ["Ashen Fist", "Order of the Pale Lamp", "Greywater League", "Circle of Tallow", "Thornwolf Clan",
	"Free Company of Varn", "Deepdelvers", "Velvet Knives", "Nine Hearth Moot"]
const TIE_MAX := 80
const NEWS_MAX := 24

static var _nations_cache: Dictionary = {}

var _factions: Dictionary = {}      # id -> {id, name, kind, power, wealth, region}
var _order: Array = []              # stable id order
var _rel: Dictionary = {}           # "a|b" -> {trust, fear, grievance, trade}
var _ties: Array = []               # {id, a, b, kind, strength, hidden, day}
var _marriages: Array = []          # {id, a, b, day, claim}
var _kingship: Dictionary = {}      # path -> {progress, bonus, notes:[String]}
var _church: Dictionary = {}        # region -> {influence, known}
var _sects: Array = []              # {id, name, kind, power, region, members, faction}
var _war_rep: Dictionary = {}       # actor -> {honour, ruthless, cowardly, acts}
var _log: Array = []
var _next_id := 1
var _bound := false                 # houses taken from life.nobility
var _day := 0


func _init() -> void:
	_seed_world([])


# --- seeding -------------------------------------------------------------------

static func nations_data() -> Array:
	if _nations_cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(NATIONS_PATH))
		_nations_cache = d if d is Dictionary else {"nations": []}
	return _nations_cache.get("nations", [])


func _rng(tag: String, day: int, id: Variant = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _seed_world(houses: Array) -> void:
	_factions.clear()
	_order.clear()
	_rel.clear()
	_ties.clear()
	_marriages.clear()
	_sects.clear()
	_church.clear()
	var r := _rng("factions_seed", 0)
	var nations := nations_data()
	for n: Dictionary in nations:
		var id := String(n.get("id", ""))
		_add_faction(id, String(n.get("short_name", n.get("name", id))), "nation", r.randf_range(35.0, 80.0), r.randf_range(30.0, 80.0), id)
	if houses.is_empty():
		var fam := ["Aldren", "Voss", "Harrow", "Cray", "Marlow", "Thane", "Wyke", "Dunmere"]
		for i in HOUSE_MAX:
			houses.append({"id": "house_%s" % fam[i].to_lower(), "name": "House %s" % fam[i]})
	for i in mini(houses.size(), HOUSE_MAX):
		var h: Dictionary = houses[i]
		_add_faction(String(h["id"]), String(h.get("name", h["id"])), "house", r.randf_range(8.0, 30.0), r.randf_range(10.0, 50.0), "caldrenn")
	_add_faction(CHURCH, "The Church", "church", 55.0, 60.0, "all")
	_add_faction(PLAYER, "You", "player", 4.0, 5.0, "caldrenn")
	for i in 2:
		_spawn_sect(r, 0)
	# relation matrix
	for i in _order.size():
		for j in range(i + 1, _order.size()):
			_init_relation(String(_order[i]), String(_order[j]), r)
	# ties: kin/rivalry between houses, debts to nations, alliances from stances
	var hs := _ids_of("house")
	for i in hs.size():
		for j in range(i + 1, hs.size()):
			var roll := r.randf()
			if roll < 0.22:
				_add_tie(String(hs[i]), String(hs[j]), "kin", r.randf_range(0.4, 0.9), r.randf() < 0.15)
			elif roll < 0.42:
				_add_tie(String(hs[i]), String(hs[j]), "rivalry", r.randf_range(0.3, 0.9), r.randf() < 0.2)
				change_relation(String(hs[i]), String(hs[j]), "grievance", 25.0)
			elif roll < 0.55:
				_add_tie(String(hs[i]), String(hs[j]), "debt", r.randf_range(0.2, 0.7), r.randf() < 0.5)
	for i in _order.size():
		for j in range(i + 1, _order.size()):
			var a := String(_order[i])
			var b := String(_order[j])
			if _kind(a) == "nation" and _kind(b) == "nation" and relation(a, b)["trust"] >= 80.0:
				_add_tie(a, b, "alliance", 0.7, false)
	for h: String in hs:
		_add_tie(h, "caldrenn", "vassalage", 0.6, false)
	# church influence per nation region (depth hidden until discovered)
	for n: Dictionary in nations:
		var id := String(n.get("id", ""))
		_church[id] = {"influence": r.randf_range(0.05, 0.35) if id == "caldrenn" else r.randf_range(0.1, 0.8), "known": id == "caldrenn"}
	for p: String in KINGSHIP_PATHS:
		_kingship[p] = {"progress": 0.0, "bonus": 0.0, "notes": []}
	_kingship["inheritance"]["bonus"] = 0.0
	_war_rep.clear()
	_add_rep(PLAYER)


func _add_faction(id: String, nm: String, kind: String, power: float, wealth: float, region: String) -> void:
	_factions[id] = {"id": id, "name": nm, "kind": kind, "power": power, "wealth": wealth, "region": region}
	_order.append(id)


func _ids_of(kind: String) -> Array:
	var out: Array = []
	for id: String in _order:
		if _factions[id]["kind"] == kind:
			out.append(id)
	return out


func _kind(id: String) -> String:
	return String((_factions.get(id, {}) as Dictionary).get("kind", ""))


static func _key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _nation_stance(a: String, b: String) -> String:
	for n: Dictionary in nations_data():
		if String(n.get("id", "")) == a:
			var rel: Dictionary = n.get("relations", {})
			if rel.has(b):
				return String(rel[b])
	return ""


func _init_relation(a: String, b: String, r: RandomNumberGenerator) -> void:
	var ka := _kind(a)
	var kb := _kind(b)
	var trust := 40.0
	var trade := 20.0
	var grievance := r.randf_range(0.0, 15.0)
	if ka == "nation" and kb == "nation":
		var s1 := _nation_stance(a, b)
		var s2 := _nation_stance(b, a)
		var t1: float = STANCE_TRUST.get(s1, 42.0)
		var t2: float = STANCE_TRUST.get(s2, 42.0)
		trust = (t1 + t2) * 0.5
		trade = trust * 0.6 + r.randf_range(-8.0, 8.0)
		grievance = clampf(60.0 - trust, 0.0, 60.0) * 0.6 + r.randf_range(0.0, 10.0)
	elif ka == "house" and kb == "house":
		trust = r.randf_range(25.0, 65.0)
	elif ka == "player" or kb == "player":
		trust = 30.0
		trade = 10.0
		grievance = 0.0
	elif ka == "church" or kb == "church":
		trust = r.randf_range(35.0, 70.0)
	else:
		trust = r.randf_range(25.0, 55.0)
	var pa: float = _factions[a]["power"]
	var pb: float = _factions[b]["power"]
	var fear := clampf(absf(pa - pb) * 0.8, 0.0, 80.0)
	_rel[_key(a, b)] = {"trust": clampf(trust, 0.0, 100.0), "fear": fear, "grievance": clampf(grievance, 0.0, 100.0),
		"trade": clampf(trade, 0.0, 100.0)}


func _add_tie(a: String, b: String, kind: String, strength: float, hidden: bool) -> Dictionary:
	if _ties.size() >= TIE_MAX:
		_ties.pop_front()
	var t := {"id": _next_id, "a": a, "b": b, "kind": kind, "strength": snappedf(strength, 0.01), "hidden": hidden, "day": _day}
	_next_id += 1
	_ties.append(t)
	return t


func _spawn_sect(r: RandomNumberGenerator, day: int) -> void:
	var kind: String = SECT_KINDS[r.randi() % SECT_KINDS.size()]
	var nm: String = SECT_NAMES[r.randi() % SECT_NAMES.size()]
	for s: Dictionary in _sects:
		if s["name"] == nm:
			nm = "%s of %s" % [nm, WorldGen.NAMES[r.randi() % WorldGen.NAMES.size()]] if not WorldGen.NAMES.is_empty() else nm + " II"
	var regions := nations_data()
	var region := "caldrenn"
	if not regions.is_empty():
		region = String((regions[r.randi() % regions.size()] as Dictionary).get("id", "caldrenn"))
	_sects.append({"id": "sect_%d" % _next_id, "name": nm, "kind": kind, "power": r.randf_range(2.0, 8.0),
		"region": region, "members": r.randi_range(20, 120), "faction": false, "founded": day})
	_next_id += 1


func _add_rep(actor: String) -> Dictionary:
	if not _war_rep.has(actor):
		_war_rep[actor] = {"honour": 0.0, "ruthless": 0.0, "cowardly": 0.0, "acts": 0}
	return _war_rep[actor]


func _bind_houses(ctx: Dictionary) -> void:
	if _bound:
		return
	var life: Variant = ctx.get("life")
	if life == null or not ("nobility" in life) or life.nobility == null or not ("houses" in life.nobility):
		return
	var hs: Array = life.nobility.houses
	if hs.is_empty():
		return
	# Re-seed with the real houses, keeping the player's accumulated state (none yet on first bind).
	_seed_world(hs.duplicate())
	_bound = true


# --- ticks ---------------------------------------------------------------------

func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_bind_houses(ctx)
	if ctx.get("at_war", false):
		# fear rises a hair while the realm is at war
		var k := _key(PLAYER, "caldrenn")
		if _rel.has(k):
			_rel[k]["fear"] = minf(100.0, float(_rel[k]["fear"]) + 0.02)
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## Relation drift / power + marriages + rivalries / church + sects + kingship + war: one job each
## (they share one seeded RNG in that order, so results equal the old single tick).
func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_bind_houses(ctx)
	_day = day
	var r := _rng("factions_day", day)
	return [
		func() -> Array:
			_day_relations()
			return [],
		func() -> Array:
			return _day_houses(r),
		func() -> Array:
			var out: Array = []
			_tick_church(r)
			_tick_sects(r, day, out)
			_tick_kingship(ctx)
			_day_war(ctx)
			return out,
	]


func _day_relations() -> void:
	# relation drift toward stance baseline, grievance decay, trade growth
	for k: String in _rel:
		var v: Dictionary = _rel[k]
		v["grievance"] = maxf(0.0, float(v["grievance"]) - 0.15)
		v["fear"] = maxf(0.0, float(v["fear"]) - 0.1)
		v["trade"] = clampf(float(v["trade"]) + (float(v["trust"]) - 45.0) * 0.004, 0.0, 100.0)
		v["trust"] = clampf(float(v["trust"]) + (50.0 - float(v["grievance"]) - float(v["trust"])) * 0.01, 0.0, 100.0)


func _day_houses(r: RandomNumberGenerator) -> Array:
	var out: Array = []
	# power drifts
	for id: String in _order:
		var f: Dictionary = _factions[id]
		f["power"] = clampf(float(f["power"]) + r.randf_range(-0.3, 0.32), 1.0, 100.0)
	# ties decay (debts are settled, rivalries cool) and marriages may bear heirs
	for t: Dictionary in _ties:
		if t["kind"] == "rivalry":
			t["strength"] = maxf(0.05, float(t["strength"]) - 0.002)
	# a marriage proposal now and then
	if r.randf() < 0.35:
		var m := _auto_marriage(r)
		if m != "":
			out.append(m)
	# random rivalry flare-ups between houses
	if r.randf() < 0.1:
		var hs := _ids_of("house")
		if hs.size() >= 2:
			var a: String = hs[r.randi() % hs.size()]
			var b: String = hs[r.randi() % hs.size()]
			if a != b:
				change_relation(a, b, "grievance", 18.0)
				_add_tie(a, b, "rivalry", 0.4, r.randf() < 0.4)
				_note("%s and %s quarrel." % [_factions[a]["name"], _factions[b]["name"]])
	return out


func _day_war(ctx: Dictionary) -> void:
	# a war in progress hurts the enemy's trust in the crown
	var life: Variant = ctx.get("life")
	if life != null and "war" in life and life.war != null and life.war.is_at_war():
		var e := String(life.war.enemy_id())
		if _factions.has(e):
			change_relation("caldrenn", e, "grievance", 2.0)
			change_relation("caldrenn", e, "trust", -1.0)


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	var r := _rng("factions_week", week)
	# power rebalancing: strong grow slower (rubber band), new sect sometimes
	var total := 0.0
	for id: String in _order:
		total += float(_factions[id]["power"])
	var mean := total / maxf(1.0, float(_order.size()))
	for id: String in _order:
		var f: Dictionary = _factions[id]
		f["power"] = clampf(float(f["power"]) + (mean - float(f["power"])) * 0.02, 1.0, 100.0)
	if _sects.size() < 12 and r.randf() < 0.25:
		_spawn_sect(r, week * 7)
		out.append("Rumour: a new order calls itself the %s." % _sects[-1]["name"])
	return out


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# closed form: drift every relation toward baseline, decay grievances, grow sects
	var out: Array = []
	if days <= 0:
		return out
	var d := float(mini(days, 400))
	var fac := 1.0 - pow(0.99, d)
	for k: String in _rel:
		var v: Dictionary = _rel[k]
		v["grievance"] = maxf(0.0, float(v["grievance"]) - 0.15 * d)
		v["fear"] = maxf(0.0, float(v["fear"]) - 0.1 * d)
		v["trust"] = clampf(float(v["trust"]) + (50.0 - float(v["grievance"]) - float(v["trust"])) * fac, 0.0, 100.0)
	for s: Dictionary in _sects:
		s["power"] = clampf(float(s["power"]) * (1.0 + 0.002 * d), 1.0, 60.0)
	var r := _rng("factions_catch", _day + days)
	var cn := 0
	for i in mini(days / 20, 3):
		var m := _auto_marriage(r)
		if m != "":
			out.append(m)
			cn += 1
	_day += days
	if days >= 7:
		out.append("News from the great houses reaches you after %d days away." % days)
	return out


# --- marriages -----------------------------------------------------------------

func _married(a: String, b: String) -> bool:
	for m: Dictionary in _marriages:
		if (m["a"] == a and m["b"] == b) or (m["a"] == b and m["b"] == a):
			return true
	return false


## Interest: how much `b` gains by marrying into `a` (0..1).
func marriage_interest(a: String, b: String) -> float:
	if not _factions.has(a) or not _factions.has(b) or a == b:
		return 0.0
	var v: Dictionary = relation(a, b)
	var power_gap := clampf((float(_factions[a]["power"]) - float(_factions[b]["power"])) / 100.0, -0.5, 0.5)
	var s := float(v["trust"]) * 0.006 + float(v["fear"]) * 0.002 - float(v["grievance"]) * 0.008 + float(v["trade"]) * 0.002 + power_gap * 0.4
	for t: Dictionary in _ties:
		if (t["a"] == a and t["b"] == b) or (t["a"] == b and t["b"] == a):
			if t["kind"] == "rivalry":
				s -= 0.25 * float(t["strength"])
			elif t["kind"] in ["kin", "alliance"]:
				s += 0.1
	return clampf(s, 0.0, 1.0)


func _auto_marriage(r: RandomNumberGenerator) -> String:
	var pool: Array = []
	for id: String in _order:
		if _kind(id) in ["house", "nation"]:
			pool.append(id)
	if pool.size() < 2:
		return ""
	var a: String = pool[r.randi() % pool.size()]
	var b: String = pool[r.randi() % pool.size()]
	if a == b or _married(a, b) or _kind(a) == "nation" and _kind(b) == "nation" and r.randf() < 0.5:
		return ""
	var res := propose_marriage(a, b, false)
	if res.get("accepted", false):
		return "%s and %s are joined in marriage." % [_factions[a]["name"], _factions[b]["name"]]
	return ""


## Propose a marriage between two factions. `a` proposes to `b`. The player
## (id "player") may propose too; acceptance is by the other side's interest
## plus a deterministic roll, never guaranteed.
func propose_marriage(a: String, b: String, log_it := true) -> Dictionary:
	if not _factions.has(a) or not _factions.has(b) or a == b:
		return {"accepted": false, "reason": "unknown"}
	if _married(a, b):
		return {"accepted": false, "reason": "already_bound"}
	var interest := marriage_interest(b, a) if a != PLAYER else marriage_interest(b, PLAYER)
	var roll := _rng("marriage", _day, "%s>%s" % [a, b]).randf()
	var ok := roll < interest * 0.85
	if not ok:
		change_relation(a, b, "grievance", 3.0)
		if log_it:
			_note("%s's proposal to %s is refused." % [_factions[a]["name"], _factions[b]["name"]])
		return {"accepted": false, "reason": "refused", "interest": interest}
	var claim := a == PLAYER or b == PLAYER
	var m := {"id": _next_id, "a": a, "b": b, "day": _day, "claim": claim}
	_next_id += 1
	_marriages.append(m)
	_add_tie(a, b, "marriage", 0.6 + interest * 0.3, false)
	change_relation(a, b, "trust", 12.0)
	change_relation(a, b, "grievance", -10.0)
	if float(relation(a, b)["trust"]) >= 55.0:
		_add_tie(a, b, "alliance", 0.5 + interest * 0.3, false)
	# jealous third parties: a rivalry with any suitor's rival
	for t: Dictionary in _ties.duplicate():
		if t["kind"] == "rivalry" and (t["a"] == a or t["b"] == a) and t["a"] != b and t["b"] != b:
			var other: String = t["b"] if t["a"] == a else t["a"]
			change_relation(other, b, "grievance", 8.0)
	if claim:
		var other := b if a == PLAYER else a
		if _kind(other) == "house" or other == "caldrenn":
			(_kingship["inheritance"] as Dictionary)["bonus"] = float(_kingship["inheritance"]["bonus"]) + 12.0
			_kingship["inheritance"]["notes"].append("Married into %s." % _factions[other]["name"])
	return {"accepted": true, "interest": interest, "marriage_id": m["id"]}


# --- church, sects, kingship ---------------------------------------------------

func _tick_church(r: RandomNumberGenerator) -> void:
	for reg: String in _church:
		var c: Dictionary = _church[reg]
		c["influence"] = clampf(float(c["influence"]) + r.randf_range(-0.004, 0.005), 0.0, 1.0)


func _tick_sects(r: RandomNumberGenerator, day: int, out: Array) -> void:
	for s: Dictionary in _sects:
		if s["faction"]:
			continue
		s["power"] = clampf(float(s["power"]) * (1.0 + r.randf_range(-0.006, 0.012)), 1.0, 60.0)
		s["members"] = int(float(s["members"]) * (1.0 + r.randf_range(-0.004, 0.01)))
		if float(s["power"]) >= 25.0 and int(s["members"]) >= 200:
			s["faction"] = true
			_add_faction(String(s["id"]), String(s["name"]), "independent", float(s["power"]), 30.0, String(s["region"]))
			for id: String in _order:
				if id != s["id"]:
					_init_relation(String(s["id"]), id, _rng("sect_rel", day, id))
			out.append("The %s has grown into a power in its own right." % s["name"])


func _tick_kingship(_ctx: Dictionary) -> void:
	var houses := _ids_of("house")
	var trust_sum := 0.0
	for h: String in houses:
		trust_sum += float(relation(PLAYER, h)["trust"])
	var election := (trust_sum / maxf(1.0, float(houses.size())) - 30.0) * 1.2
	var church_trust: float = float(relation(PLAYER, CHURCH)["trust"])
	var coronation := (church_trust - 30.0) * 1.0 * (0.5 + float((_church.get("caldrenn", {}) as Dictionary).get("influence", 0.3)))
	var rep := war_rep(PLAYER)
	var uprising := float(rep["honour"]) * 0.4 - float(rep["ruthless"]) * 0.2
	var derived := {"election": election, "coronation": coronation, "uprising": uprising, "inheritance": 0.0, "conquest": 0.0}
	for p: String in KINGSHIP_PATHS:
		var k: Dictionary = _kingship[p]
		k["progress"] = snappedf(clampf(float(derived[p]) + float(k["bonus"]), 0.0, 100.0), 0.1)


## Player advancement hook: `path` in KINGSHIP_PATHS, `amount` in progress points.
func add_kingship_progress(path: String, amount: float, note := "") -> void:
	if not _kingship.has(path):
		return
	var k: Dictionary = _kingship[path]
	k["bonus"] = clampf(float(k["bonus"]) + amount, -50.0, 100.0)
	k["progress"] = clampf(float(k["progress"]) + amount, 0.0, 100.0)
	if note != "":
		(k["notes"] as Array).append(note)
		if k["notes"].size() > 8:
			k["notes"].pop_front()


# --- war reputation (R§22) ------------------------------------------------------

const ACT_EFFECTS := {
	"spare_civilians": {"honour": 3.0}, "honour_surrender": {"honour": 4.0}, "pay_soldiers": {"honour": 2.0},
	"keep_treaty": {"honour": 4.0}, "massacre": {"ruthless": 10.0, "honour": -8.0}, "kill_prisoners": {"ruthless": 6.0, "honour": -5.0},
	"burn_villages": {"ruthless": 5.0, "honour": -3.0}, "break_treaty": {"honour": -10.0, "ruthless": 2.0},
	"abandon_allies": {"cowardly": 8.0, "honour": -4.0}, "flee_battle": {"cowardly": 6.0}, "rout": {"cowardly": 4.0},
	"victory": {"honour": 1.0}, "covert_exposed": {"ruthless": 3.0, "honour": -3.0},
}


func record_war_act(actor: String, act: String, weight := 1.0) -> void:
	var rep := _add_rep(actor)
	var e: Dictionary = ACT_EFFECTS.get(act, {})
	for k: String in e:
		rep[k] = clampf(float(rep[k]) + float(e[k]) * weight, -100.0, 100.0)
	rep["acts"] = int(rep["acts"]) + 1


func war_rep(actor: String) -> Dictionary:
	var rep := _add_rep(actor).duplicate()
	var label := "unknown"
	if rep["acts"] > 0:
		var h := float(rep["honour"])
		var ru := float(rep["ruthless"])
		var co := float(rep["cowardly"])
		if co > maxf(h, ru) and co >= 8.0:
			label = "cowardly"
		elif ru > h and ru >= 8.0:
			label = "ruthless"
		elif h >= 8.0:
			label = "honourable"
		else:
			label = "untested"
	rep["label"] = label
	return rep


# --- relations ------------------------------------------------------------------

func change_relation(a: String, b: String, field: String, delta: float) -> void:
	var k := _key(a, b)
	if not _rel.has(k) or not (field in FIELDS):
		return
	_rel[k][field] = clampf(float(_rel[k][field]) + delta, 0.0, 100.0)


func relation(a: String, b: String) -> Dictionary:
	var v: Dictionary = (_rel.get(_key(a, b), {"trust": 40.0, "fear": 0.0, "grievance": 0.0, "trade": 0.0}) as Dictionary).duplicate()
	var t := float(v["trust"]) - float(v["grievance"]) * 0.5
	var stance := "neutral"
	if t >= 75.0:
		stance = "allied"
	elif t >= 55.0:
		stance = "friendly"
	elif t >= 35.0:
		stance = "neutral"
	elif t >= 20.0:
		stance = "wary"
	elif t >= 8.0:
		stance = "hostile"
	else:
		stance = "war"
	v["stance"] = stance
	return v


func factions() -> Array:
	var out: Array = []
	for id: String in _order:
		out.append((_factions[id] as Dictionary).duplicate())
	return out


func faction(id: String) -> Dictionary:
	return (_factions.get(id, {}) as Dictionary).duplicate()


## Ties the player knows about (hidden ones need discover_tie()).
func ties(include_hidden := false) -> Array:
	var out: Array = []
	for t: Dictionary in _ties:
		if include_hidden or not t["hidden"]:
			out.append(t.duplicate())
	return out


func discover_tie(tie_id: int) -> bool:
	for t: Dictionary in _ties:
		if int(t["id"]) == tie_id and t["hidden"]:
			t["hidden"] = false
			return true
	return false


func marriages() -> Array:
	return _marriages.duplicate(true)


func kingship_paths() -> Dictionary:
	return _kingship.duplicate(true)


## Influence 0..1 for a region id; `known` only true once discovered.
func church_influence(region: String) -> Dictionary:
	var c: Dictionary = _church.get(region, {"influence": 0.0, "known": false})
	return {"influence": float(c["influence"]), "known": bool(c["known"])}


func discover_church(region: String) -> void:
	if _church.has(region):
		_church[region]["known"] = true


func sects() -> Array:
	return _sects.duplicate(true)


func news(limit := 6) -> Array:
	return _log.slice(maxi(0, _log.size() - limit))


func _note(line: String) -> void:
	_log.append(line)
	if _log.size() > NEWS_MAX:
		_log.pop_front()


# --- persistence ---------------------------------------------------------------

func serialize() -> Dictionary:
	return {"factions": _factions.duplicate(true), "order": _order.duplicate(), "rel": _rel.duplicate(true),
		"ties": _ties.duplicate(true), "marriages": _marriages.duplicate(true), "kingship": _kingship.duplicate(true),
		"church": _church.duplicate(true), "sects": _sects.duplicate(true), "war_rep": _war_rep.duplicate(true),
		"log": _log.duplicate(), "next_id": _next_id, "bound": _bound, "day": _day}


func deserialize(d: Dictionary) -> void:
	if not d.has("factions"):
		return
	_factions = (d["factions"] as Dictionary).duplicate(true)
	_order = (d.get("order", []) as Array).duplicate()
	_rel = (d.get("rel", {}) as Dictionary).duplicate(true)
	_ties = _ints_fix((d.get("ties", []) as Array).duplicate(true), ["id", "day"])
	_marriages = _ints_fix((d.get("marriages", []) as Array).duplicate(true), ["id", "day"])
	_kingship = (d.get("kingship", {}) as Dictionary).duplicate(true)
	_church = (d.get("church", {}) as Dictionary).duplicate(true)
	_sects = _ints_fix((d.get("sects", []) as Array).duplicate(true), ["members", "founded"])
	_war_rep = (d.get("war_rep", {}) as Dictionary).duplicate(true)
	for k: String in _war_rep:
		_war_rep[k]["acts"] = int(_war_rep[k].get("acts", 0))
	_log = (d.get("log", []) as Array).duplicate()
	_next_id = int(d.get("next_id", 1))
	_bound = bool(d.get("bound", false))
	_day = int(d.get("day", 0))


static func _ints_fix(arr: Array, keys: Array) -> Array:
	for e: Dictionary in arr:
		for k: String in keys:
			if e.has(k):
				e[k] = int(e[k])
	return arr
