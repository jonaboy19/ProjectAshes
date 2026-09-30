extends "res://scripts/realm/realm_module.gd"
## R§1 followers as individuals, R§2 summons with travel delay, L§18/19
## temporary vs permanent companions, L§43 party disagreements, R§31/32
## creature taming per species and settlement creature roles.
## Followers have agency: they can refuse a summon, disapprove of decisions,
## demand pay, quarrel with each other and leave. Pure data, JSON-safe save.

const TRAITS := ["brave", "cautious", "greedy", "honorable", "merciful", "ruthless", "devout", "curious",
	"stubborn", "loyal", "lazy", "hot_headed"]
## trait -> value axes in -1..1 (what they approve of in the player's choices).
const TRAIT_VALUES := {
	"brave": {"risk": 0.7}, "cautious": {"risk": -0.7}, "greedy": {"greed": 0.8}, "honorable": {"honor": 0.8},
	"merciful": {"mercy": 0.8}, "ruthless": {"mercy": -0.8}, "devout": {"faith": 0.8},
	"curious": {"risk": 0.3}, "hot_headed": {"mercy": -0.3, "risk": 0.3}, "lazy": {"risk": -0.3},
}
const AXES := ["mercy", "greed", "honor", "faith", "risk"]
const OCCUPATIONS := {
	"hunter": {"skills": {"tracking": 0.8, "archery": 0.7, "combat": 0.3, "forest_lore": 0.8}, "salary": 2},
	"knight": {"skills": {"combat": 0.9, "riding": 0.8, "tactics": 0.6, "command": 0.5}, "salary": 9},
	"scout": {"skills": {"tracking": 0.6, "stealth": 0.8, "riding": 0.5, "combat": 0.3}, "salary": 3},
	"cavalry": {"skills": {"combat": 0.7, "riding": 0.9, "tactics": 0.4}, "salary": 6},
	"healer": {"skills": {"medicine": 0.8, "herbs": 0.7, "combat": 0.1}, "salary": 3},
	"smith": {"skills": {"smithing": 0.8, "combat": 0.3, "repair": 0.7}, "salary": 4},
	"priest": {"skills": {"faith": 0.8, "medicine": 0.3, "speech": 0.6}, "salary": 2},
	"mercenary": {"skills": {"combat": 0.7, "tactics": 0.4, "intimidation": 0.6}, "salary": 5},
	"builder": {"skills": {"building": 0.65, "repair": 0.5, "combat": 0.1}, "salary": 3},
}
const FIRST := ["Alda", "Bertram", "Cael", "Dagna", "Eirik", "Fenna", "Garrick", "Hilde", "Ivor", "Jessa", "Korrin", "Lyra",
	"Merrick", "Nessa", "Osric", "Petra", "Quill", "Rhodri", "Sigrun", "Toben", "Ulla", "Voss", "Wren", "Yorick"]
const LAST := ["Ashdown", "Brack", "Coldwater", "Dunmere", "Eastwick", "Fell", "Greyle", "Hale", "Ironside", "Marsh", "Oakley", "Thorne"]
const ORIGINS := ["Ashford farmstead", "Kingsreach barracks", "the Millbrook mill", "a mountain hold", "the river folk", "a wandering caravan", "the frontier"]
const AMBITIONS := ["earn a captaincy", "save for a farm", "avenge a burned home", "see the Rift", "find a wife", "win renown", "repay a debt"]
const MEMBER_STATES := ["present", "traveling"]
const DISPUTE_MAX := 6
const DECISION_MAX := 40

## Species -> taming method. accept: action -> trust gain (negative hurts).
const SPECIES := {
	"wolf": {"method": "trust", "accept": {"feed": 0.2, "wait": 0.1, "dominate": -0.3},
		"roles": {"guarding": 1.0, "scouting": 0.8, "hauling": 0.2}},
	"stag": {"method": "resonance", "accept": {"attune": 0.25, "wait": 0.05, "feed": 0.05, "dominate": -0.4},
		"roles": {"scouting": 1.0, "hauling": 0.6}},
	"wyvern": {"method": "raise", "accept": {"raise": 0.12, "feed": 0.05, "dominate": -0.2}, "needs_young": true,
		"roles": {"scouting": 1.0, "guarding": 0.8}},
	"boar": {"method": "dominance", "accept": {"dominate": 0.3, "feed": 0.05, "wait": -0.05},
		"roles": {"farming": 1.0, "hauling": 0.7, "guarding": 0.4}},
	"draft_horse": {"method": "trust", "accept": {"feed": 0.25, "wait": 0.1, "dominate": -0.1},
		"roles": {"hauling": 1.0, "farming": 0.9}},
	"rift_wraith": {"method": "none", "accept": {}, "roles": {}},
}
const ROLE_YIELD := {"farming": ["grain", 3.0], "hauling": ["wood", 2.0]}

## fid -> follower dict.
var _f: Dictionary = {}
var _next_f := 1
var _summons: Array = []       # [{fid, dest, hours_left, eta, lost}]
var _arrived: Array = []       # last arrivals [{fid, dest, day}]
var _decisions: Array = []     # [{kind, stance, day}]
var _disputes: Array = []      # [{a, b, kind, day}]
var _creatures: Dictionary = {}
var _temps: Array = []         # ids of temporary companions
var _day := 0


func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


# --------------------------------------------------------------- creation R§1 / L§19

## A person met on the road; not in the party until recruited.
func candidate(occupation: String, key: String, loc := "s0") -> String:
	var occ: Dictionary = OCCUPATIONS.get(occupation, OCCUPATIONS["mercenary"])
	var r := _rng("cand", 0, key)
	var traits: Array = []
	while traits.size() < 3:
		var t: String = TRAITS[r.randi() % TRAITS.size()]
		if not traits.has(t):
			traits.append(t)
	var skills := {}
	for s in occ["skills"]:
		skills[s] = snappedf(clampf(float(occ["skills"][s]) + r.randf_range(-0.2, 0.2), 0.05, 1.0), 0.01)
	var values := {}
	for a in AXES:
		values[a] = 0.0
	for t in traits:
		for a in TRAIT_VALUES.get(t, {}):
			values[a] = clampf(values[a] + TRAIT_VALUES[t][a], -1.0, 1.0)
	var fid := "f%d" % _next_f
	_next_f += 1
	_f[fid] = {"id": fid, "name": "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]],
		"age": 19 + r.randi() % 27, "origin": ORIGINS[r.randi() % ORIGINS.size()], "occupation": occupation,
		"traits": traits, "values": values, "skills": skills, "ambition": AMBITIONS[r.randi() % AMBITIONS.size()],
		"loyalty": 45.0 + (10.0 if "loyal" in traits else 0.0), "morale": 0.7,
		"needs": {"rest": 0.8, "food": 0.8, "pay": 1.0, "purpose": 0.6},
		"opinions": {}, "relations": {}, "salary": int(occ["salary"]) + r.randi() % 2, "owed": 0,
		"status": "candidate", "loc": loc, "post": "", "permanent": false, "until_hours": 0,
		"unhappy_days": 0, "flags": {}, "joined_day": -1}
	return fid


## Recruitment (L§19): they weigh reputation, pay and their own character.
## Returns {ok, line}. `terms`: {reputation 0..100, pay per day, permanent}.
func recruit(fid: String, terms: Dictionary) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or f["status"] != "candidate":
		return {"ok": false, "line": ""}
	var rep: float = float(terms.get("reputation", 0.0))
	var pay: float = float(terms.get("pay", f["salary"]))
	var permanent: bool = bool(terms.get("permanent", true))
	var need := 25.0 + (25.0 if permanent else 0.0) + (10.0 if OCCUPATIONS[f["occupation"]]["salary"] >= 9 else 0.0)
	var score := rep + (pay - float(f["salary"])) * 8.0 + (8.0 if "loyal" in f["traits"] else 0.0) - (12.0 if "stubborn" in f["traits"] else 0.0)
	if "greedy" in f["traits"]:
		score += (pay - float(f["salary"])) * 6.0
	if score < need:
		var line := "\"You can't even protect yourself. Why would I follow you?\"" if rep < 20.0 else "\"Not for that pay, and not yet.\""
		return {"ok": false, "line": "%s: %s" % [f["name"], line]}
	f["status"] = "present"
	f["permanent"] = permanent
	f["salary"] = int(maxf(1.0, pay))
	f["joined_day"] = _day
	f["loyalty"] = clampf(f["loyalty"] + rep * 0.15, 0.0, 100.0)
	if not permanent:
		f["until_hours"] = int(terms.get("hours", 72))
		_temps.append(fid)
	return {"ok": true, "line": "%s agrees to travel with you." % f["name"]}


## Convenience for tests and scripted arrivals: create and enlist directly.
func hire(occupation: String, loc := "s0", permanent := true, key := "", hours := 72) -> String:
	var fid := candidate(occupation, key if key != "" else "hire%d" % _next_f, loc)
	var f: Dictionary = _f[fid]
	f["status"] = "present"
	f["permanent"] = permanent
	f["joined_day"] = _day
	if not permanent:
		f["until_hours"] = hours
		_temps.append(fid)
	return fid


func hire_temp(occupation: String, loc: String, hours: int, key := "") -> String:
	return hire(occupation, loc, false, key, hours)


func make_permanent(fid: String) -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or f["status"] not in MEMBER_STATES or f["permanent"]:
		return false
	if f["loyalty"] < 55.0:
		return false
	f["permanent"] = true
	f["until_hours"] = 0
	_temps.erase(fid)
	return true


func list(status := "") -> Array:
	var out: Array = []
	var ids := _f.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	for id in ids:
		var f: Dictionary = _f[id]
		if status == "" and f["status"] in ["candidate", "left"]:
			continue
		if status == "" or f["status"] == status:
			out.append(f)
	return out


func get_follower(fid: String) -> Dictionary:
	return _f.get(fid, {})


func party() -> Array:
	return _party_ids().map(func(i: String) -> Dictionary: return _f[i])


func _party_ids() -> Array:
	var out: Array = []
	for id in _f:
		if _f[id]["status"] in MEMBER_STATES:
			out.append(id)
	return out


func assign_post(fid: String, post: String) -> void:
	if _f.has(fid):
		_f[fid]["post"] = post


func wages_due() -> int:
	var t := 0
	for id in _f:
		if _f[id]["status"] in MEMBER_STATES:
			t += int(_f[id]["owed"])
	return t


func pay(fid: String, amount: int) -> int:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty():
		return 0
	var used := mini(amount, int(f["owed"]))
	f["owed"] -= used
	if used > 0:
		f["needs"]["pay"] = clampf(1.0 - float(f["owed"]) / maxf(1.0, f["salary"] * 7.0), 0.0, 1.0)
	return used


func care(fid: String, need: String, amount: float) -> void:
	var f: Dictionary = _f.get(fid, {})
	if not f.is_empty() and f["needs"].has(need):
		f["needs"][need] = clampf(f["needs"][need] + amount, 0.0, 1.0)


# --------------------------------------------------------------- summons R§2

func _hours_between(a: String, b: String) -> float:
	var cm := _mod("camps")
	if cm == null:
		return 4.0
	return cm.travel_hours(a, b)


func _resolve_node(dest: Variant) -> String:
	if dest is Vector2 or dest is Vector3:
		var p := Vector2(dest.x, dest.y if dest is Vector2 else dest.z)
		var cm := _mod("camps")
		return cm.nearest_node(p) if cm != null else "s0"
	if dest is int:
		return "s%d" % dest
	return String(dest)


## Send a messenger. The follower answers in character; returns
## {ok, response, eta}. `arrivals()` lists those on the road.
func summon(fid: String, dest: Variant) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or f["status"] not in MEMBER_STATES:
		return {"ok": false, "response": "", "eta": 0.0}
	var node := _resolve_node(dest)
	for s in _summons:
		if s["fid"] == fid:
			return {"ok": false, "response": "%s is already on the way." % f["name"], "eta": s["hours_left"]}
	if f["loc"] == node:
		return {"ok": true, "response": "%s is already here." % f["name"], "eta": 0.0}
	var r := _rng("summon", _day, fid + node)
	var refuse := ""
	var loy: float = f["loyalty"]
	if f["post"] != "" and loy < 85.0 and r.randf() < 0.75:
		refuse = "\"I cannot leave my post.\""
	elif loy < 25.0:
		refuse = "\"Why should I come running?\""
	elif "stubborn" in f["traits"] and _avg_opinion(f) < -0.6 and r.randf() < 0.6:
		refuse = "\"After what you did? No.\""
	if refuse != "":
		return {"ok": false, "response": "%s: %s" % [f["name"], refuse], "eta": 0.0}
	var eta := _hours_between(f["loc"], node)
	var cm := _mod("camps")
	var risk: float = cm.route_risk(f["loc"], node) if cm != null else 0.0
	var lost: bool = r.randf() < risk * 0.5
	var resp := "%s: \"I will come.\"" % f["name"]
	if not lost and risk > 0.35 and r.randf() < 0.5:
		eta *= 1.5
		resp = "%s: \"The road is unsafe. I will come, but slowly.\"" % f["name"]
	if eta <= 0.0:
		f["loc"] = node
		return {"ok": true, "response": resp, "eta": 0.0}
	f["status"] = "traveling"
	_summons.append({"fid": fid, "dest": node, "hours_left": eta, "eta": eta, "lost": lost})
	return {"ok": true, "response": resp, "eta": eta}


func arrivals() -> Array:
	return _summons


func recent_arrivals() -> Array:
	return _arrived


func _avg_opinion(f: Dictionary) -> float:
	var ops: Dictionary = f["opinions"]
	if ops.is_empty():
		return 0.0
	var t := 0.0
	for k in ops:
		t += float(ops[k])
	return t / ops.size()


# --------------------------------------------------------------- decisions and disagreement L§43

## The player made a choice on an axis (mercy/greed/honor/faith/risk) with a
## stance -1..1. Members react by character. Returns their spoken reactions.
func decide(kind: String, stance: float, day := -1) -> Array:
	var out: Array = []
	if kind not in AXES:
		return out
	var dd := _day if day < 0 else day
	_decisions.append({"kind": kind, "stance": stance, "day": dd})
	if _decisions.size() > DECISION_MAX:
		_decisions.pop_front()
	var reacts := {}
	for id in _party_ids():
		var f: Dictionary = _f[id]
		var a: float = float(f["values"].get(kind, 0.0)) * stance
		reacts[id] = a
		f["opinions"][kind] = clampf(float(f["opinions"].get(kind, 0.0)) + a * 0.5, -3.0, 3.0)
		if absf(a) > 0.2:
			f["loyalty"] = clampf(f["loyalty"] + a * 4.0, 0.0, 100.0)
		if a < -0.5:
			out.append("%s disapproves." % f["name"])
		elif a > 0.6:
			out.append("%s nods approvingly." % f["name"])
	var ids := reacts.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if reacts[ids[i]] * reacts[ids[j]] <= -0.36:
				_add_dispute(ids[i], ids[j], kind, dd)
	return out


func _add_dispute(a: String, b: String, kind: String, day: int) -> void:
	for d in _disputes:
		if (d["a"] == a and d["b"] == b) or (d["a"] == b and d["b"] == a):
			d["day"] = day
			d["kind"] = kind
			return
	_disputes.append({"a": a, "b": b, "kind": kind, "day": day})
	if _disputes.size() > DISPUTE_MAX:
		_disputes.pop_front()


func disputes() -> Array:
	return _disputes


# --------------------------------------------------------------- taming R§31/32

func start_taming(creature_id: String, species: String, young := false, loc := "s0") -> bool:
	if not SPECIES.has(species) or _creatures.has(creature_id):
		return false
	_creatures[creature_id] = {"id": creature_id, "species": species, "name": species.replace("_", " "), "trust": 0.0,
		"status": "wild", "young": young, "role": "", "loc": loc, "attempts": 0}
	return true


## One taming step. Correct method per species; returns {ok, msg, trust, status}.
func attempt_taming(creature_id: String, action: String, day := -1) -> Dictionary:
	var c: Dictionary = _creatures.get(creature_id, {})
	if c.is_empty() or c["status"] not in ["wild", "taming"]:
		return {"ok": false, "msg": "", "trust": 0.0, "status": c.get("status", "none")}
	var sp: Dictionary = SPECIES[c["species"]]
	if sp["method"] == "none":
		return {"ok": false, "msg": "The %s can never be tamed." % c["name"], "trust": 0.0, "status": c["status"]}
	if sp.get("needs_young", false) and not c["young"]:
		return {"ok": false, "msg": "A grown %s will not be tamed; it must be raised from youth." % c["name"], "trust": c["trust"], "status": c["status"]}
	c["attempts"] += 1
	var gain: float = float(sp["accept"].get(action, -0.05))
	c["trust"] = clampf(c["trust"] + gain, 0.0, 1.0)
	c["status"] = "taming"
	var msg := ""
	if gain <= 0.0:
		var r := _rng("tame", _day if day < 0 else day, "%s%d" % [creature_id, c["attempts"]])
		if r.randf() < 0.15 + (0.3 if gain < -0.25 else 0.0):
			c["status"] = "fled"
			return {"ok": false, "msg": "The %s bolts and is gone." % c["name"], "trust": c["trust"], "status": "fled"}
		msg = "The %s bristles; that was the wrong approach." % c["name"]
	else:
		msg = "The %s grows a little more at ease." % c["name"]
	if c["trust"] >= 1.0:
		c["status"] = "tamed"
		msg = "The %s is yours." % c["name"]
	return {"ok": gain > 0.0, "msg": msg, "trust": c["trust"], "status": c["status"]}


func tamed() -> Array:
	var out: Array = []
	var ids := _creatures.keys()
	ids.sort()
	for id in ids:
		if _creatures[id]["status"] == "tamed":
			out.append(_creatures[id])
	return out


func creature(cid: String) -> Dictionary:
	return _creatures.get(cid, {})


func assign_role(cid: String, role: String, loc: String) -> bool:
	var c: Dictionary = _creatures.get(cid, {})
	if c.is_empty() or c["status"] != "tamed":
		return false
	if not SPECIES[c["species"]]["roles"].has(role):
		return false
	c["role"] = role
	c["loc"] = loc
	return true


func role_efficiency(cid: String) -> float:
	var c: Dictionary = _creatures.get(cid, {})
	if c.is_empty() or c["role"] == "":
		return 0.0
	return float(SPECIES[c["species"]]["roles"].get(c["role"], 0.0)) * (0.5 + 0.5 * float(c["trust"]))


## Guard strength at a node from tamed guards (feeds raid defence).
func guard_bonus(node: String) -> float:
	var b := 0.0
	for id in _creatures:
		var c: Dictionary = _creatures[id]
		if c["status"] == "tamed" and c["role"] == "guarding" and c["loc"] == node:
			b += 0.06 * role_efficiency(id)
	return minf(b, 0.3)


func _apply_roles(days: float) -> void:
	var sm := _mod("settlements")
	for id in _creatures:
		var c: Dictionary = _creatures[id]
		if c["status"] != "tamed" or not ROLE_YIELD.has(c["role"]):
			continue
		if sm != null and String(c["loc"]).begins_with("s"):
			var y: Array = ROLE_YIELD[c["role"]]
			sm.add_stock(int(String(c["loc"]).substr(1)), y[0], y[1] * role_efficiency(id) * days)


# --------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	var i := _summons.size() - 1
	while i >= 0:
		var s: Dictionary = _summons[i]
		s["hours_left"] = float(s["hours_left"]) - 1.0
		if s["hours_left"] <= 0.0:
			var f: Dictionary = _f.get(s["fid"], {})
			if not f.is_empty():
				if s["lost"]:
					f["status"] = "present"
					out.append("No sign of %s; the messenger never arrived." % f["name"])
				else:
					f["status"] = "present"
					f["loc"] = s["dest"]
					_arrived.append({"fid": s["fid"], "dest": s["dest"], "day": _day})
					if _arrived.size() > 20:
						_arrived.pop_front()
					out.append("%s arrives." % f["name"])
			_summons.remove_at(i)
		i -= 1
	var j := _temps.size() - 1
	while j >= 0:
		var f: Dictionary = _f.get(_temps[j], {})
		if f.is_empty() or f["permanent"] or f["status"] not in MEMBER_STATES:
			_temps.remove_at(j)
		else:
			f["until_hours"] -= 1
			if f["until_hours"] <= 0:
				f["status"] = "left"
				out.append("%s parts ways with you, the job done." % f["name"])
				_temps.remove_at(j)
		j -= 1
	return out


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var out: Array = []
	var sm := _mod("settlements")
	for id in _f.keys():
		var f: Dictionary = _f[id]
		if f["status"] not in MEMBER_STATES:
			continue
		out.append_array(_follower_day(f, 1.0, sm, day))
	# Disputes cool or fester.
	var k := _disputes.size() - 1
	while k >= 0:
		var d: Dictionary = _disputes[k]
		var a: Dictionary = _f.get(d["a"], {})
		var b: Dictionary = _f.get(d["b"], {})
		if a.is_empty() or b.is_empty() or a["status"] not in MEMBER_STATES or b["status"] not in MEMBER_STATES or day - int(d["day"]) > 14:
			_disputes.remove_at(k)
		else:
			var rel: float = float(a["relations"].get(d["b"], 0.0)) - 0.06
			a["relations"][d["b"]] = clampf(rel, -1.0, 1.0)
			b["relations"][d["a"]] = clampf(rel, -1.0, 1.0)
			a["loyalty"] = maxf(0.0, a["loyalty"] - 0.5)
			b["loyalty"] = maxf(0.0, b["loyalty"] - 0.5)
			if rel < -0.5 and not a["flags"].get("feud_" + d["b"], false):
				a["flags"]["feud_" + d["b"]] = true
				out.append("%s and %s are at each other's throats over %s." % [a["name"], b["name"], d["kind"]])
		k -= 1
	_apply_roles(1.0)
	for cid in _creatures:
		var c: Dictionary = _creatures[cid]
		if c["status"] == "tamed" and c["role"] != "":
			c["trust"] = minf(1.0, c["trust"] + 0.001)
	# Companions in the same place grow close, or not.
	var by_loc := {}
	for id in _party_ids():
		var loc: String = _f[id]["loc"]
		if not by_loc.has(loc):
			by_loc[loc] = []
		by_loc[loc].append(id)
	for loc in by_loc:
		var grp: Array = by_loc[loc]
		if grp.size() < 2:
			continue
		var r := _rng("bond", day, loc)
		var a: Dictionary = _f[grp[r.randi() % grp.size()]]
		var b: Dictionary = _f[grp[r.randi() % grp.size()]]
		if a["id"] == b["id"]:
			continue
		var rel: float = a["relations"].get(b["id"], 0.0) + 0.03
		a["relations"][b["id"]] = clampf(rel, -1.0, 1.0)
		b["relations"][a["id"]] = clampf(rel, -1.0, 1.0)
		if rel > 0.6 and not a["flags"].get("love_" + b["id"], false):
			a["flags"]["love_" + b["id"]] = true
			out.append("%s and %s have grown close." % [a["name"], b["name"]])
	return out


func _follower_day(f: Dictionary, days: float, sm: RefCounted, day: int) -> Array:
	var out: Array = []
	var n: Dictionary = f["needs"]
	f["owed"] += int(round(f["salary"] * days))
	n["pay"] = clampf(1.0 - float(f["owed"]) / maxf(1.0, f["salary"] * 7.0), 0.0, 1.0)
	var loc: String = f["loc"]
	var fed := true
	if sm != null and loc.begins_with("s") and f["status"] == "present":
		fed = int(sm.shortages(int(loc.substr(1))).get("food", 0)) == 0
	var at_home: bool = f["status"] == "present" and loc.begins_with("s")
	n["food"] = clampf(n["food"] + (0.06 if fed and at_home else -0.05) * days, 0.0, 1.0)
	n["rest"] = clampf(n["rest"] + (0.04 if at_home else -0.03) * days, 0.0, 1.0)
	n["purpose"] = clampf(n["purpose"] + (-0.015 if f["post"] == "" else 0.005) * days, 0.0, 1.0)
	var avg: float = (n["rest"] + n["food"] + n["pay"] + n["purpose"]) * 0.25
	var target: float = 10.0 + 60.0 * avg + 8.0 * clampf(_avg_opinion(f), -3.0, 3.0) + (10.0 if "loyal" in f["traits"] else 0.0)
	var k := 1.0 - pow(0.95, days)
	f["loyalty"] = clampf(f["loyalty"] + (target - f["loyalty"]) * k, 0.0, 100.0)
	f["morale"] = clampf(avg, 0.0, 1.0)
	if f["loyalty"] < 14.0:
		f["unhappy_days"] += int(ceil(days))
	else:
		f["unhappy_days"] = 0
	if n["pay"] < 0.4 and "greedy" in f["traits"] and not f["flags"].get("raise_asked", false):
		f["flags"]["raise_asked"] = true
		out.append("%s demands better pay." % f["name"])
	elif n["pay"] >= 0.8:
		f["flags"].erase("raise_asked")
	if f["unhappy_days"] >= 3:
		f["status"] = "left"
		var weakest := "pay"
		for nd in n:
			if n[nd] < n[weakest]:
				weakest = nd
		var why: String = {"pay": "unpaid wages", "food": "hunger", "rest": "exhaustion", "purpose": "having nothing to do"}[weakest]
		out.append("%s has left your service over %s." % [f["name"], why])
		_temps.erase(f["id"])
		for i in range(_summons.size() - 1, -1, -1):
			if _summons[i]["fid"] == f["id"]:
				_summons.remove_at(i)
	return out


func catch_up(days: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	if days < 1:
		return out
	_day += days
	var sm := _mod("settlements")
	var gone := 0
	var arrived := 0
	var wages := 0
	# Roads and messengers resolve through the elapsed hours.
	for i in range(_summons.size() - 1, -1, -1):
		var s: Dictionary = _summons[i]
		var f: Dictionary = _f.get(s["fid"], {})
		s["hours_left"] = float(s["hours_left"]) - days * 24.0
		if s["hours_left"] <= 0.0:
			if not f.is_empty():
				f["status"] = "present"
				if not s["lost"]:
					f["loc"] = s["dest"]
					arrived += 1
			_summons.remove_at(i)
	for j in range(_temps.size() - 1, -1, -1):
		var f2: Dictionary = _f.get(_temps[j], {})
		if f2.is_empty() or f2["permanent"]:
			_temps.remove_at(j)
			continue
		f2["until_hours"] -= days * 24
		if f2["until_hours"] <= 0:
			f2["status"] = "left"
			_temps.remove_at(j)
			gone += 1
	for id in _f:
		var f3: Dictionary = _f[id]
		if f3["status"] not in MEMBER_STATES:
			continue
		var msgs := _follower_day(f3, float(days), sm, _day)
		if f3["status"] == "left":
			gone += 1
		wages += int(f3["owed"])
	_apply_roles(float(days))
	_disputes.clear()
	if arrived > 0:
		out.append("%d summoned follower%s reached you while you were away." % [arrived, "" if arrived == 1 else "s"])
	if gone > 0:
		out.append("%d of your followers left while you were away." % gone)
	if wages > 0 and days >= 3:
		out.append("Wages are owed to your followers (%d gold)." % wages)
	return out


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"f": _f.duplicate(true), "next": _next_f, "summons": _summons.duplicate(true),
		"arrived": _arrived.duplicate(true), "decisions": _decisions.duplicate(true),
		"disputes": _disputes.duplicate(true), "creatures": _creatures.duplicate(true), "day": _day}


func deserialize(d: Dictionary) -> void:
	_f = (d.get("f", {}) as Dictionary).duplicate(true)
	_next_f = int(d.get("next", 1))
	_summons = (d.get("summons", []) as Array).duplicate(true)
	_arrived = (d.get("arrived", []) as Array).duplicate(true)
	_decisions = (d.get("decisions", []) as Array).duplicate(true)
	_disputes = (d.get("disputes", []) as Array).duplicate(true)
	_creatures = (d.get("creatures", {}) as Dictionary).duplicate(true)
	_day = int(d.get("day", 0))
	_temps = []
	for id in _f:
		var f: Dictionary = _f[id]
		if not f["permanent"] and f["status"] in MEMBER_STATES:
			_temps.append(id)
