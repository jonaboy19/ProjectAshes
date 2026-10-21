extends "res://scripts/realm/realm_module.gd"
## Diplomacy and the kingdoms' reactions (Living World section 8, LW-6.3).
##
## AGREEMENTS between any two parties (the player's faction, houses, sects, the thirteen kingdoms): non-aggression, passage, trade, alliance,
## vassalage, tribute, marriage. Each has terms, a duration and enforcement: allowed() answers whether an act is lawful under the pacts in
## force; report_act() turns a forbidden act into a BREACH. A breach breaks the agreement, drops trust in factions.gd, costs reliability in
## reputation.gd and stays in the victim's memory, so the next proposal from that party is weighed against it (and fades after a year).
## Tribute accrues weekly; three weeks in arrears is a default.
##
## REACTIONS TO INDEPENDENT FACTIONS. A kingdom notices a faction by its VISIBILITY (settlement exposure, claimed cells, fame) and judges it by
## its CONDUCT (reputation, treaties kept, tribute, raids). assess() returns one of ignore, tax, recognize, suppress, and react() applies it once
## per change: tax demands a tribute, recognize offers vassalage and a charter, suppress cuts trust and logs a punitive force.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const TYPES := {
	"non_aggression": {"dur": 180, "forbids": ["attack", "raid"], "grants": [], "min": 28.0},
	"passage": {"dur": 90, "forbids": [], "grants": ["enter"], "min": 22.0},
	"trade": {"dur": 365, "forbids": [], "grants": ["trade", "enter"], "min": 32.0},
	"alliance": {"dur": 720, "forbids": ["attack", "raid"], "grants": ["enter", "trade"], "min": 62.0},
	"vassalage": {"dur": -1, "forbids": ["attack", "raid"], "grants": ["enter", "trade"], "min": 30.0},
	"tribute": {"dur": 180, "forbids": ["attack", "raid"], "grants": [], "min": 18.0},
	"marriage": {"dur": -1, "forbids": ["attack"], "grants": ["enter"], "min": 40.0},
}
const REACTIONS := ["ignore", "tax", "recognize", "suppress"]
const VIS_NOTICE := 0.12
const VIS_RECOGNIZE := 0.30
const VIS_ALARM := 0.70
const CONDUCT_GOOD := 0.35
const CONDUCT_BAD := -0.20
const BREACH_FADE := 360
const MEM_MAX := 60
const AG_MAX := 120

var _ag: Dictionary = {}        # id -> agreement
var _mem: Array = []            # [victim, actor, type, day]  broken agreements remembered
var _owed: Dictionary = {}      # agreement id -> weeks of unpaid tribute
var _react: Dictionary = {}     # "kingdom|faction" -> {r, since}
var _hostile: Dictionary = {}   # "faction|kingdom" -> [count, last_day]
var _next := 1
var _day := 0
var stats := {"signed": 0, "refused": 0, "breaches": 0, "defaults": 0, "reactions": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _rel(a: String, b: String) -> Dictionary:
	var f: Variant = _mod("factions")
	return f.relation(a, b) if f != null else {"trust": 40.0, "fear": 0.0, "grievance": 0.0, "trade": 0.0, "stance": "neutral"}


func _power(id: String) -> float:
	var f: Variant = _mod("factions")
	if f != null:
		var d: Dictionary = f.faction(id)
		if not d.is_empty():
			return float(d.get("power", 40.0))
	return 40.0


# ------------------------------------------------------------------ memory of broken agreements

func breaches_by(actor: String, victim := "") -> int:
	var n := 0
	for m: Array in _mem:
		if String(m[1]) == actor and (victim == "" or String(m[0]) == victim) and _now() - int(m[3]) < BREACH_FADE * 2:
			n += 1
	return n


func _breach_penalty(actor: String, victim: String) -> float:
	var p := 0.0
	for m: Array in _mem:
		if String(m[1]) == actor:
			var age := float(_now() - int(m[3]))
			var w := clampf(1.0 - age / float(BREACH_FADE), 0.0, 1.0)
			p += (16.0 if String(m[0]) == victim else 7.0) * w
	return p


# ------------------------------------------------------------------ proposals

## `proposer` asks `other`. terms: {days, amount (gold a week), payer, lord, dowry, gift}. Returns {ok, accepted, id, score, need, reasons}.
func propose(proposer: String, other: String, type: String, terms: Dictionary = {}) -> Dictionary:
	if not TYPES.has(type) or proposer == other or proposer == "" or other == "":
		return {"ok": false, "accepted": false, "reasons": ["Not a pact either side can sign."]}
	for a: Dictionary in _ag.values():
		if String(a["type"]) == type and String(a["state"]) == "active" and ((a["a"] == proposer and a["b"] == other) or (a["a"] == other and a["b"] == proposer)):
			return {"ok": false, "accepted": false, "reasons": ["A %s pact is already in force." % type.replace("_", " ")]}
	var spec: Dictionary = TYPES[type]
	var rel := _rel(other, proposer)
	var score := float(rel["trust"]) - float(rel["grievance"]) * 0.5
	var reasons: Array = []
	var pen := _breach_penalty(proposer, other)
	if pen > 0.0:
		score -= pen
		reasons.append("%s remembers broken agreements." % PD.kingdom_name(other) if PD.is_kingdom(other) else "They remember the agreements you broke.")
	var rep: Variant = _mod("reputation")
	if rep != null:
		var rel_axis := float(rep.axis_of("f:" + proposer, "reliability", "f:" + other))
		score += rel_axis * 0.15
		var leg := float(rep.axis_of("f:" + proposer, "legitimacy", "k:" + other))
		score += leg * 0.05
	score += float(terms.get("gift", 0)) / 10.0 + float(terms.get("dowry", 0)) / 15.0
	var pp := _power(proposer)
	var po := _power(other)
	match type:
		"vassalage":
			if po < pp:
				score -= 25.0
				reasons.append("They will not take a lord weaker than themselves.")
			else:
				score += float(rel["fear"]) * 0.0 + (po - pp) * 0.2
		"alliance":
			score += float(rel["trade"]) * 0.1
		"trade":
			score += float(rel["trade"]) * 0.3
		"tribute":
			score += float(terms.get("amount", 0)) / 4.0
		"marriage":
			if not terms.has("dowry"):
				score -= 5.0
	var need := float(spec["min"])
	var accepted := score >= need
	if not accepted:
		stats["refused"] = int(stats["refused"]) + 1
		reasons.append("They refuse: %d against the %d they need." % [int(score), int(need)])
		return {"ok": true, "accepted": false, "score": snappedf(score, 0.1), "need": need, "reasons": reasons, "id": ""}
	var id := _sign(proposer, other, type, terms)
	return {"ok": true, "accepted": true, "score": snappedf(score, 0.1), "need": need, "reasons": reasons, "id": id}


func _sign(a: String, b: String, type: String, terms: Dictionary, state := "active") -> String:
	if _ag.size() >= AG_MAX:
		_prune()
	var spec: Dictionary = TYPES[type]
	var days := int(terms.get("days", spec["dur"]))
	var id := "ag%d" % _next
	_next += 1
	var t := terms.duplicate()
	if type in ["vassalage", "tribute"]:
		t["amount"] = int(terms.get("amount", 10))
		t["payer"] = String(terms.get("payer", a))
	if type == "vassalage":
		t["lord"] = String(terms.get("lord", b))
		t["payer"] = a if String(t["lord"]) == b else b
	_ag[id] = {"id": id, "type": type, "a": a, "b": b, "terms": t, "start": _now(), "end": -1 if days < 0 else _now() + days, "state": state, "arrears": 0, "paid": 0}
	stats["signed"] = int(stats["signed"]) + 1
	var f: Variant = _mod("factions")
	if f != null and state == "active":
		f.change_relation(a, b, "trust", 6.0)
	Events.log_to(hub, "contract", "", [], "pact", "%s and %s sign %s" % [a, b, type.replace("_", " ")], 3)
	return id


func agreement(id: String) -> Dictionary:
	return (_ag.get(id, {}) as Dictionary).duplicate(true)


func agreements(party := "", state := "active") -> Array:
	var out: Array = []
	var ids := _ag.keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return int(x.substr(2)) < int(y.substr(2)))
	for k: String in ids:
		var a: Dictionary = _ag[k]
		if (party == "" or a["a"] == party or a["b"] == party) and (state == "" or String(a["state"]) == state):
			out.append(a.duplicate(true))
	return out


func end_agreement(id: String, why := "ended") -> bool:
	var a: Dictionary = _ag.get(id, {})
	if a.is_empty() or String(a["state"]) != "active":
		return false
	a["state"] = why
	return true


# ------------------------------------------------------------------ enforcement

## Is `act` ("attack", "raid", "enter", "trade") lawful for actor against victim under the pacts in force?
func allowed(actor: String, victim: String, act: String) -> Dictionary:
	var grant := ""
	for a: Dictionary in _ag.values():
		if String(a["state"]) != "active":
			continue
		if not ((a["a"] == actor and a["b"] == victim) or (a["a"] == victim and a["b"] == actor)):
			continue
		var spec: Dictionary = TYPES[a["type"]]
		if act in spec["forbids"]:
			return {"allowed": false, "by": String(a["id"]), "type": String(a["type"])}
		if act in spec["grants"]:
			grant = String(a["id"])
	return {"allowed": true, "by": grant, "type": ""}


## An act happened. If it breaks a pact the pact is broken, remembered, and the actor's name suffers.
func report_act(actor: String, victim: String, act: String, sid := -1) -> Dictionary:
	var al := allowed(actor, victim, act)
	if act in ["attack", "raid"]:
		var hk := "%s|%s" % [actor, victim]
		var h: Array = _hostile.get(hk, [0, 0])
		_hostile[hk] = [int(h[0]) + 1, _now()]
	if bool(al["allowed"]):
		return {"breach": false}
	var a: Dictionary = _ag[String(al["by"])]
	a["state"] = "broken"
	a["broken_by"] = actor
	a["broken_day"] = _now()
	_mem.append([victim, actor, String(a["type"]), _now()])
	if _mem.size() > MEM_MAX:
		_mem.pop_front()
	stats["breaches"] = int(stats["breaches"]) + 1
	var f: Variant = _mod("factions")
	if f != null:
		f.change_relation(victim, actor, "trust", -25.0)
		f.change_relation(victim, actor, "grievance", 20.0)
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("f:" + actor, "treaty_broken", sid, 1.0, {"groups": ["k:" + victim, "f:" + victim]})
	Events.log_to(hub, "contract", "", [], "breach", "%s breaks the %s with %s" % [actor, String(a["type"]).replace("_", " "), victim], 5)
	return {"breach": true, "agreement": String(a["id"]), "type": String(a["type"])}


func owed(id: String) -> int:
	var a: Dictionary = _ag.get(id, {})
	return int(_owed.get(id, 0)) * int(a.get("terms", {}).get("amount", 0)) if not a.is_empty() else 0


func pay(id: String, weeks := 1) -> bool:
	var a: Dictionary = _ag.get(id, {})
	if a.is_empty() or String(a["state"]) != "active" or not _owed.has(id):
		return false
	_owed[id] = maxi(0, int(_owed[id]) - weeks)
	a["paid"] = int(a["paid"]) + weeks
	if int(_owed[id]) == 0:
		_owed.erase(id)
	return true


func _week_agreements() -> void:
	for id: String in _ag.keys():
		var a: Dictionary = _ag[id]
		if String(a["state"]) != "active":
			continue
		if int(a["end"]) >= 0 and _now() >= int(a["end"]):
			a["state"] = "expired"
			continue
		if String(a["type"]) in ["tribute", "vassalage"]:
			var payer := String((a["terms"] as Dictionary)["payer"])
			var rep: Variant = _mod("reputation")
			if payer == "player":
				_owed[id] = int(_owed.get(id, 0)) + 1
				if int(_owed[id]) >= 3:
					stats["defaults"] = int(stats["defaults"]) + 1
					var payee := String(a["b"]) if String(a["a"]) == payer else String(a["a"])
					_owed.erase(id)
					report_act(payer, payee, "default")
					a["state"] = "broken"
					a["broken_by"] = payer
					_mem.append([payee, payer, String(a["type"]), _now()])
					if rep != null:
						rep.on_deed("f:" + payer, "treaty_broken", -1, 0.6, {"groups": ["k:" + payee]})
			else:
				a["paid"] = int(a["paid"]) + 1
				var f: Variant = _mod("factions")
				if f != null:
					f.add_wealth(payer, -float((a["terms"] as Dictionary)["amount"]) * 0.02)


# ------------------------------------------------------------------ reactions to independent factions

func set_profile(faction: String, vis: float, conduct: float) -> void:
	_react["profile|" + faction] = {"v": clampf(vis, 0.0, 1.0), "c": clampf(conduct, -1.0, 1.0)}


func visibility_of(faction: String) -> float:
	var prof: Dictionary = _react.get("profile|" + faction, {})
	if not prof.is_empty():
		return float(prof["v"])
	var v := 0.0
	var fd: Variant = _mod("founding")
	if fd != null and faction == "player":
		for fid: int in fd.ids(true):
			var f: Dictionary = fd.get_founding(fid)
			if String(f.get("who", "")) == "player":
				v = maxf(v, float((f["esc"] as Dictionary).get("vis", 0.0)))
	var tr: Variant = _mod("territory")
	if tr != null:
		v = clampf(v * 0.7 + float(tr.claimed_cells(faction)) / 30.0, 0.0, 1.0)
	if faction == "player":
		var soc: Variant = _mod("society")
		if soc != null:
			v = clampf(v + float(soc.fame_at(0)) / 400.0, 0.0, 1.0)
	return v


func conduct_of(faction: String, kingdom: String) -> float:
	var prof: Dictionary = _react.get("profile|" + faction, {})
	if not prof.is_empty():
		return float(prof["c"])
	var c := 0.0
	var rep: Variant = _mod("reputation")
	if rep != null:
		var v: Dictionary = rep.view("f:" + faction, "k:" + kingdom)
		if not v.is_empty():
			c += (float(v["legitimacy"]) + float(v["trust"]) + float(v["reliability"])) / 300.0 * 0.9
	c -= float(breaches_by(faction, kingdom)) * 0.25
	var hk: Array = _hostile.get("%s|%s" % [faction, kingdom], [0, 0])
	if _now() - int(hk[1]) < 180:
		c -= 0.2 * float(mini(int(hk[0]), 3))
	for a: Dictionary in _ag.values():
		if String(a["state"]) == "active" and ((a["a"] == faction and a["b"] == kingdom) or (a["b"] == faction and a["a"] == kingdom)):
			c += 0.12
			if int(_owed.get(String(a["id"]), 0)) > 0:
				c -= 0.15
	var aud: Variant = _mod("audiences")
	if aud != null and aud.has_right(faction, "settlement_recognition", -1):
		c += 0.1
	return clampf(c, -1.0, 1.0)


func react_for(vis: float, conduct: float) -> String:
	if vis < VIS_NOTICE:
		return "ignore"
	if conduct < CONDUCT_BAD or (vis >= VIS_ALARM and conduct < CONDUCT_GOOD):
		return "suppress"
	if vis >= VIS_RECOGNIZE and conduct >= CONDUCT_GOOD:
		return "recognize"
	return "tax"


## {reaction, visibility, conduct, kingdom}. Far kingdoms see less of a faction than the home kingdom does.
func assess(kingdom: String, faction := "player") -> Dictionary:
	var vis := visibility_of(faction) * (1.0 if kingdom == PD.HOME else 0.45)
	var con := conduct_of(faction, kingdom)
	return {"kingdom": kingdom, "faction": faction, "visibility": snappedf(vis, 0.001), "conduct": snappedf(con, 0.001), "reaction": react_for(vis, con)}


func reaction(kingdom: String, faction := "player") -> String:
	return String((_react.get("%s|%s" % [kingdom, faction], {}) as Dictionary).get("r", "ignore"))


func react(kingdom: String, faction := "player") -> Dictionary:
	var a := assess(kingdom, faction)
	var key := "%s|%s" % [kingdom, faction]
	var cur: Dictionary = _react.get(key, {})
	var r := String(a["reaction"])
	if not cur.is_empty() and String(cur["r"]) == r:
		return a
	_react[key] = {"r": r, "since": _now()}
	a["changed"] = true
	stats["reactions"] = int(stats["reactions"]) + 1
	var f: Variant = _mod("factions")
	match r:
		"tax":
			var amt := maxi(3, int(round(float(a["visibility"]) * 60.0)))
			_sign(faction, kingdom, "tribute", {"amount": amt, "payer": faction, "days": 360}, "demanded")
			Events.log_to(hub, "contract", "", [], "tax", "%s demands tribute of %d a week from %s" % [PD.kingdom_name(kingdom), amt, faction], 3)
		"recognize":
			_sign(faction, kingdom, "vassalage", {"amount": 6, "lord": kingdom, "days": -1}, "offered")
			if f != null:
				f.change_relation(kingdom, faction, "trust", 10.0)
			var rep: Variant = _mod("reputation")
			if rep != null:
				rep.on_deed("f:" + faction, "recognised", -1, 0.8, {"groups": ["k:" + kingdom]})
			Events.log_to(hub, "contract", "", [], "recognize", "%s offers to recognise %s" % [PD.kingdom_name(kingdom), faction], 4)
		"suppress":
			if f != null:
				f.change_relation(kingdom, faction, "trust", -15.0)
				f.change_relation(kingdom, faction, "grievance", 15.0)
			_hostile["%s|%s" % [kingdom, faction]] = [1, _now()]
			Events.log_to(hub, "battle", "", [], "suppress", "%s moves to suppress %s" % [PD.kingdom_name(kingdom), faction], 5)
	return a


## The player (or any party) answers a demand or an offer: "demanded" tribute and "offered" vassalage become active, or are refused.
func answer(id: String, accept: bool) -> bool:
	var a: Dictionary = _ag.get(id, {})
	if a.is_empty() or not (String(a["state"]) in ["demanded", "offered"]):
		return false
	if accept:
		a["state"] = "active"
		a["start"] = _now()
		if int(a["end"]) >= 0:
			a["end"] = _now() + 360
		stats["signed"] = int(stats["signed"]) + 1
	else:
		a["state"] = "refused"
		var kingdom := String(a["b"]) if PD.is_kingdom(String(a["b"])) else String(a["a"])
		var faction := String(a["a"]) if kingdom == String(a["b"]) else String(a["b"])
		_hostile["%s|%s" % [faction, kingdom]] = [int((_hostile.get("%s|%s" % [faction, kingdom], [0, 0]) as Array)[0]) + 1 if String(a["type"]) == "tribute" else 0, _now()]
		var f: Variant = _mod("factions")
		if f != null and String(a["type"]) == "tribute":
			f.change_relation(kingdom, faction, "grievance", 8.0)
	return true


# ------------------------------------------------------------------ ticks

func tick_week(_week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_week_agreements()
	# The home kingdom always looks; the rest only when the faction is famous. Independent sects are judged by the same table.
	var vis := visibility_of("player")
	if vis > 0.0 or _react.has("%s|player" % PD.HOME):
		for k: String in PD.kingdoms():
			if k == PD.HOME or vis >= 0.35:
				react(k, "player")
	var f: Variant = _mod("factions")
	if f != null:
		var n := 0
		for s: Dictionary in f.sects():
			if n >= 6:
				break
			n += 1
			var sid := String(s.get("id", ""))
			if sid != "":
				set_profile(sid, clampf(float(s.get("power", 10.0)) / 60.0, 0.0, 1.0), 0.45 - float(absi(hash([WorldSim.SEED, "sect", sid])) % 100) / 100.0)
				react(PD.HOME, sid)
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	for id: String in _ag.keys():
		var a: Dictionary = _ag[id]
		if String(a["state"]) == "active" and int(a["end"]) >= 0 and _day >= int(a["end"]):
			a["state"] = "expired"
	return []


func _prune() -> void:
	for id: String in _ag.keys():
		if String(_ag[id]["state"]) in ["expired", "refused", "broken", "ended"] and _now() - int(_ag[id]["start"]) > 120:
			_ag.erase(id)


func serialize() -> Dictionary:
	return {"ag": _ag.duplicate(true), "mem": _mem.duplicate(true), "owed": _owed.duplicate(), "react": _react.duplicate(true), "hostile": _hostile.duplicate(true),
		"next": _next, "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ag = (d.get("ag", {}) as Dictionary).duplicate(true)
	for a: Dictionary in _ag.values():
		PD.fix_ints(a, ["start", "end", "arrears", "paid"])
	_mem = (d.get("mem", []) as Array).duplicate(true)
	for m: Array in _mem:
		m[3] = int(m[3])
	_owed = (d.get("owed", {}) as Dictionary).duplicate()
	for k: String in _owed:
		_owed[k] = int(_owed[k])
	_react = (d.get("react", {}) as Dictionary).duplicate(true)
	for k: String in _react:
		if (_react[k] as Dictionary).has("since"):
			_react[k]["since"] = int(_react[k]["since"])
	_hostile = (d.get("hostile", {}) as Dictionary).duplicate(true)
	for k: String in _hostile:
		_hostile[k] = [int(_hostile[k][0]), int(_hostile[k][1])]
	_next = int(d.get("next", 1))
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
