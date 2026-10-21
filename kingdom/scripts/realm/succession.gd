extends "res://scripts/realm/realm_module.gd"
## Marriage and inheritance into politics (Living World section 7, LW-6.2).
##
## Titles ("crown:<kingdom>", "lord:<sid>", "house:<id>") are held by people. A succession follows the LOCAL RULE of the kingdom or the place
## (primogeniture, ultimogeniture, tanistry, elective, designation) over the real family tree kept here. CLAIMS are separate from holding:
## blood claims come from the rule's order, designation and conquest claims are added, and a MARRIAGE NEVER GRANTS A THRONE: a spouse becomes consort,
## the couple's children carry both lines' claims, and at most a consort may be REGENT for a child under 16 until that child comes of age.
## When the two best claimants are within DISPUTE_MARGIN the title falls vacant and a DISPUTE opens; it ends by council vote, by a petition to the
## crown, or by war. A new holder triggers stewardship.assume (and so a review of everything the old holder granted).

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const Factions := preload("res://scripts/realm/factions.gd")

const YEAR := 360
const ADULT := 16
const DISPUTE_MARGIN := 0.15
const PEOPLE_MAX := 320
const RULES := ["primogeniture", "ultimogeniture", "tanistry", "elective", "designation"]
const FIRST_M := ["Aldric", "Bram", "Cedric", "Doran", "Edmund", "Fenn", "Gareth", "Hale", "Ivor", "Jorren", "Kael", "Lucan"]
const FIRST_F := ["Adela", "Brenna", "Cora", "Dessa", "Elin", "Freya", "Gwen", "Hilde", "Isolde", "Jessa", "Kira", "Mara"]

var _ppl: Dictionary = {}       # pid -> person
var _titles: Dictionary = {}    # key -> title
var _claims: Dictionary = {}    # key -> [[pid, basis, strength], ...]
var _dis: Dictionary = {}       # id -> dispute
var _local: Dictionary = {}     # str(sid) -> rule
var _next_p := 1
var _next_d := 1
var _day := 0
var stats := {"successions": 0, "disputes": 0, "regencies": 0, "marriages": 0, "births": 0, "deaths": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ people

func _name(r: RandomNumberGenerator, sex: String, house: String) -> String:
	var first: String = (FIRST_M if sex == "m" else FIRST_F)[r.randi() % 12]
	return "%s %s" % [first, house.capitalize()]


func new_person(pname: String, age: int, sex: String, house: String, father := "", mother := "", pid := "") -> String:
	if _ppl.size() >= PEOPLE_MAX:
		_trim()
	var id := pid if pid != "" else "sp%d" % _next_p
	if pid == "":
		_next_p += 1
	_ppl[id] = {"id": id, "name": pname, "born": _now() - age * YEAR, "sex": sex, "house": house, "father": father, "mother": mother, "spouse": "", "kids": [], "alive": true, "died": -1}
	for par: String in [father, mother]:
		if par != "" and _ppl.has(par):
			(_ppl[par]["kids"] as Array).append(id)
	return id


func person(pid: String) -> Dictionary:
	var p: Dictionary = _ppl.get(pid, {})
	if p.is_empty():
		return {}
	var out := p.duplicate(true)
	out["age"] = age_of(pid)
	return out


func age_of(pid: String) -> int:
	var p: Dictionary = _ppl.get(pid, {})
	if p.is_empty():
		return 0
	var end := int(p["died"]) if not bool(p["alive"]) else _now()
	return int(floor(float(end - int(p["born"])) / float(YEAR)))


func _trim() -> void:
	for k: String in _ppl.keys():
		var p: Dictionary = _ppl[k]
		if not bool(p["alive"]) and _now() - int(p["died"]) > 600 and not _is_holder(k):
			_ppl.erase(k)
			if _ppl.size() < PEOPLE_MAX - 20:
				return


func _is_holder(pid: String) -> bool:
	for t: Dictionary in _titles.values():
		if String(t["holder"]) == pid or String(t["regent"]) == pid:
			return true
	return false


# ------------------------------------------------------------------ titles

func rule_of(key: String) -> String:
	var t := title(key)
	return String(t.get("rule", "primogeniture"))


func set_local_rule(sid: int, rule: String) -> bool:
	if not (rule in RULES):
		return false
	_local[str(sid)] = rule
	var t: Dictionary = _titles.get("lord:%d" % sid, {})
	if not t.is_empty():
		t["rule"] = rule
	return true


func _seed_title(key: String) -> Dictionary:
	var bits := key.split(":")
	if bits.size() != 2:
		return {}
	var kind := bits[0]
	var r := PD.rng("stitle", 0, key)
	var kingdom := PD.HOME
	var house := bits[1]
	var rule := "primogeniture"
	var hold_age := 38 + r.randi() % 24
	var hname := ""
	var heir_name := ""
	var heir_age := 0
	var heir_sex := ""
	match kind:
		"crown":
			kingdom = bits[1]
			if not PD.is_kingdom(kingdom):
				return {}
			house = kingdom
			rule = String(PD.SUCCESSION_RULE.get(kingdom, "primogeniture"))
			for n: Dictionary in Factions.nations_data():
				if String(n["id"]) == kingdom:
					hname = String((n.get("ruler", {}) as Dictionary).get("name", ""))
					hold_age = int((n.get("ruler", {}) as Dictionary).get("age", hold_age))
					heir_name = String((n.get("heir", {}) as Dictionary).get("name", ""))
					heir_age = int((n.get("heir", {}) as Dictionary).get("age", 0))
					heir_sex = "f" if String((n.get("heir", {}) as Dictionary).get("title", "")).contains("Princess") else "m"
		"lord":
			var sid := int(bits[1])
			if PD.settlement(sid).is_empty():
				return {}
			house = PD.sname(sid)
			rule = String(_local.get(str(sid), PD.SUCCESSION_RULE[PD.kingdom_of(sid)]))
			var gv: Variant = _mod("governance")
			if gv != null:
				var lp: Dictionary = gv.leader_of_settlement(sid)
				if not lp.is_empty():
					hname = String(lp["n"])
					hold_age = int(lp.get("age", hold_age))
					var hr: Dictionary = lp.get("heir", {})
					if not hr.is_empty():
						heir_name = String(hr["n"])
						heir_age = int(floor(float(_now() - int(hr["born"])) / float(YEAR)))
		"house":
			rule = String(PD.SUCCESSION_RULE[PD.HOME])
		_:
			return {}
	if hname == "":
		hname = _name(r, "m" if r.randf() < 0.6 else "f", house)
	var sex := "m" if r.randf() < 0.6 else "f"
	var hid := new_person(hname, hold_age, sex, house)
	var spouse := new_person(_name(r, "f" if sex == "m" else "m", house), maxi(18, hold_age - 2 - r.randi() % 6), "f" if sex == "m" else "m", "other")
	_ppl[hid]["spouse"] = spouse
	_ppl[spouse]["spouse"] = hid
	var father := hid if sex == "m" else spouse
	var mother := spouse if sex == "m" else hid
	var kids := 2 + r.randi() % 2
	for i in kids:
		var base := heir_age if heir_age > 0 else hold_age - 24
		var age := base if i == 0 else maxi(1, base - i * (2 + r.randi() % 3))
		var ksex := heir_sex if (i == 0 and heir_sex != "") else ("m" if r.randf() < 0.5 else "f")
		var kname := heir_name if (i == 0 and heir_name != "") else _name(r, ksex, house)
		new_person(kname, age, ksex, house, father, mother)
	_titles[key] = {"key": key, "kind": kind, "kingdom": kingdom, "rule": rule, "holder": hid, "regent": "", "designated": "", "council": [], "dispute": "", "hist": ["seeded day %d" % _now()], "since": _now()}
	return _titles[key]


func title(key: String) -> Dictionary:
	var t: Dictionary = _titles.get(key, {})
	if t.is_empty():
		t = _seed_title(key)
	return t.duplicate(true) if not t.is_empty() else {}


func _t(key: String) -> Dictionary:
	if not _titles.has(key):
		_seed_title(key)
	return _titles.get(key, {})


func holder(key: String) -> String:
	return String(_t(key).get("holder", ""))


func regent_of(key: String) -> String:
	return String(_t(key).get("regent", ""))


func designate(key: String, pid: String) -> bool:
	var t := _t(key)
	if t.is_empty() or not _ppl.has(pid) or not bool(_ppl[pid]["alive"]):
		return false
	t["designated"] = pid
	return true


func add_claim(key: String, pid: String, basis: String, strength: float) -> bool:
	if not _ppl.has(pid) or _t(key).is_empty():
		return false
	var l: Array = _claims.get(key, [])
	for c: Array in l:
		if String(c[0]) == pid and String(c[1]) == basis:
			c[2] = strength
			return true
	l.append([pid, basis, strength])
	_claims[key] = l
	return true


func set_council(key: String, pids: Array) -> void:
	var t := _t(key)
	if not t.is_empty():
		t["council"] = pids.duplicate()


# ------------------------------------------------------------------ order of succession and claims

func _kin_pool(t: Dictionary) -> Array:
	var h: Dictionary = _ppl.get(String(t["holder"]), {})
	var pool: Array = []
	if h.is_empty():
		return pool
	var seen := {}
	var add := func(pid: String) -> void:
		if pid != "" and not seen.has(pid) and _ppl.has(pid) and bool(_ppl[pid]["alive"]) and pid != String(t["holder"]):
			seen[pid] = true
			pool.append(pid)
	for k: String in h["kids"]:
		add.call(k)
	for par: String in [String(h["father"]), String(h["mother"])]:
		if par != "" and _ppl.has(par):
			for s: String in _ppl[par]["kids"]:
				add.call(s)
	# grandchildren and nephews/nieces
	for pid2: String in pool.duplicate():
		for k2: String in _ppl[pid2]["kids"]:
			add.call(k2)
	return pool


func _is_child_line(pid: String, holder_pid: String) -> bool:
	var p: Dictionary = _ppl.get(pid, {})
	return not p.is_empty() and (String(p["father"]) == holder_pid or String(p["mother"]) == holder_pid)


## Heirs by the title's rule, best first: [{pid, basis, strength}]. The consort never appears here.
func heirs(key: String) -> Array:
	var t := _t(key)
	if t.is_empty():
		return []
	var rule := String(t["rule"])
	var hp := String(t["holder"])
	var pool := _kin_pool(t)
	var out: Array = []
	var kids: Array = []
	var others: Array = []
	for pid: String in pool:
		(kids if _is_child_line(pid, hp) else others).append(pid)
	var by_age := func(a: String, b: String) -> bool: return int(_ppl[a]["born"]) < int(_ppl[b]["born"])
	kids.sort_custom(by_age)
	others.sort_custom(by_age)
	var ordered: Array = []
	match rule:
		"ultimogeniture":
			kids.reverse()
			ordered = kids + others
		"tanistry":
			var all := kids + others
			all.sort_custom(func(a: String, b: String) -> bool:
				var aa := 1 if age_of(a) >= ADULT else 0
				var ab := 1 if age_of(b) >= ADULT else 0
				return aa > ab or (aa == ab and int(_ppl[a]["born"]) < int(_ppl[b]["born"])))
			ordered = all
		"elective":
			var all2 := kids + others
			var council: Array = t["council"]
			all2.sort_custom(func(a: String, b: String) -> bool: return _elect_score(a, council) > _elect_score(b, council))
			ordered = all2
		"designation":
			var d := String(t["designated"])
			ordered = kids + others
			if d != "" and d in ordered:
				ordered.erase(d)
				ordered.push_front(d)
		_:
			ordered = kids + others
	var i := 0
	for pid3: String in ordered:
		var s := maxf(0.15, 1.0 - 0.28 * float(i))
		if rule == "elective":
			s = clampf(0.4 + _elect_score(pid3, t["council"]) * 0.6 - 0.1 * float(i), 0.1, 1.0)
		if age_of(pid3) < ADULT:
			s *= 0.9
		out.append({"pid": pid3, "basis": "blood" if _is_child_line(pid3, hp) else "kin", "strength": snappedf(s, 0.001)})
		i += 1
	for c: Array in _claims.get(key, []):
		if bool(_ppl.get(String(c[0]), {}).get("alive", false)) and String(c[0]) != hp:
			var found := false
			for e: Dictionary in out:
				if String(e["pid"]) == String(c[0]):
					e["strength"] = maxf(float(e["strength"]), float(c[2]))
					found = true
			if not found:
				out.append({"pid": String(c[0]), "basis": String(c[1]), "strength": float(c[2])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["strength"]) > float(b["strength"]))
	return out


func _elect_score(pid: String, council: Array) -> float:
	var rep: Variant = _mod("reputation")
	var s := float(absi(hash([WorldSim.SEED, "elect", pid])) % 100) / 400.0
	if rep != null:
		var tr: Dictionary = rep.truth("i:" + pid)
		s += (float(tr["competence"]) + float(tr["influence"]) + float(tr["trust"])) / 600.0
	s += 0.08 if age_of(pid) >= ADULT else -0.1
	for m: String in council:
		if m == pid:
			s += 0.1
	return clampf(s, 0.0, 1.0)


## What a person may claim and on what basis. A consort claims nothing by marriage.
func claims_of(pid: String) -> Array:
	var out: Array = []
	for key: String in _titles:
		for e: Dictionary in heirs(key):
			if String(e["pid"]) == pid:
				out.append({"title": key, "basis": String(e["basis"]), "strength": float(e["strength"])})
	var p: Dictionary = _ppl.get(pid, {})
	if not p.is_empty() and String(p["spouse"]) != "":
		for key2: String in _titles:
			if String(_titles[key2]["holder"]) == String(p["spouse"]):
				out.append({"title": key2, "basis": "consort", "strength": 0.0})
	return out


# ------------------------------------------------------------------ marriage and children

func marry(a: String, b: String, terms: Dictionary = {}) -> Dictionary:
	var pa: Dictionary = _ppl.get(a, {})
	var pb: Dictionary = _ppl.get(b, {})
	if pa.is_empty() or pb.is_empty() or not bool(pa["alive"]) or not bool(pb["alive"]):
		return {"ok": false, "reason": "Both must be alive."}
	if String(pa["spouse"]) != "" or String(pb["spouse"]) != "":
		return {"ok": false, "reason": "One of them is already married."}
	if age_of(a) < ADULT or age_of(b) < ADULT:
		return {"ok": false, "reason": "Too young to marry."}
	if String(pa["father"]) != "" and String(pa["father"]) == String(pb["father"]):
		return {"ok": false, "reason": "Siblings cannot marry."}
	pa["spouse"] = b
	pb["spouse"] = a
	stats["marriages"] = int(stats["marriages"]) + 1
	var out := {"ok": true, "consort_of": "", "throne": false}
	for key: String in _titles:
		var hp := String(_titles[key]["holder"])
		if hp == a or hp == b:
			out["consort_of"] = key
	var dip: Variant = _mod("diplomacy")
	if dip != null and String(pa["house"]) != String(pb["house"]) and String(pa["house"]) != "" and String(pb["house"]) != "":
		var pr: Dictionary = dip.propose(String(pa["house"]), String(pb["house"]), "marriage", {"dowry": int(terms.get("dowry", 20)), "gift": int(terms.get("gift", 0))})
		out["pact"] = String(pr.get("id", ""))
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("i:" + a, "married_well", -1, 0.6)
		rep.on_deed("i:" + b, "married_well", -1, 0.6)
	Events.log_to(hub, "marriage", "", [a, b], "marriage", "%s weds %s" % [String(pa["name"]), String(pb["name"])], 3)
	return out


func beget(a: String, b: String, cname := "", sex := "") -> String:
	var pa: Dictionary = _ppl.get(a, {})
	var pb: Dictionary = _ppl.get(b, {})
	if pa.is_empty() or pb.is_empty() or String(pa["spouse"]) != b:
		return ""
	var r := PD.rng("birth", _now(), [a, b, (pa["kids"] as Array).size()])
	var s := sex if sex != "" else ("m" if r.randf() < 0.5 else "f")
	var father := a if String(pa["sex"]) == "m" else b
	var mother := b if father == a else a
	var house := String(_ppl[father]["house"])
	var kid := new_person(cname if cname != "" else _name(r, s, house), 0, s, house, father, mother)
	stats["births"] = int(stats["births"]) + 1
	return kid


# ------------------------------------------------------------------ death and succession

func die(pid: String, cause := "age") -> Dictionary:
	var p: Dictionary = _ppl.get(pid, {})
	if p.is_empty() or not bool(p["alive"]):
		return {}
	p["alive"] = false
	p["died"] = _now()
	stats["deaths"] = int(stats["deaths"]) + 1
	var res := {"pid": pid, "titles": []}
	for key: String in _titles.keys():
		var t: Dictionary = _titles[key]
		if String(t["holder"]) == pid:
			(res["titles"] as Array).append(succeed(key, cause))
		elif String(t["regent"]) == pid:
			t["regent"] = _pick_regent(key, String(t["holder"]))
	return res


func _pick_regent(key: String, ward: String) -> String:
	var w: Dictionary = _ppl.get(ward, {})
	if w.is_empty():
		return ""
	# The surviving parent first (the consort), then the best adult kin by the council's reckoning.
	for par: String in [String(w["mother"]), String(w["father"])]:
		if par != "" and _ppl.has(par) and bool(_ppl[par]["alive"]) and age_of(par) >= ADULT:
			return par
	var best := ""
	var bs := -1.0
	for e: Dictionary in heirs(key):
		var pid := String(e["pid"])
		if pid != ward and age_of(pid) >= ADULT and _elect_score(pid, _t(key)["council"]) > bs:
			bs = _elect_score(pid, _t(key)["council"])
			best = pid
	return best


func succeed(key: String, cause := "death") -> Dictionary:
	var t := _t(key)
	if t.is_empty():
		return {}
	var old := String(t["holder"])
	var hs := heirs(key)
	var out := {"title": key, "old": old, "new": "", "regent": "", "dispute": "", "rule": String(t["rule"])}
	if hs.is_empty():
		t["holder"] = ""
		(t["hist"] as Array).append("vacant day %d" % _now())
		return out
	if hs.size() > 1 and float(hs[0]["strength"]) - float(hs[1]["strength"]) < DISPUTE_MARGIN:
		var did := "sd%d" % _next_d
		_next_d += 1
		_dis[did] = {"id": did, "title": key, "parties": [{"pid": String(hs[0]["pid"]), "s": float(hs[0]["strength"])}, {"pid": String(hs[1]["pid"]), "s": float(hs[1]["strength"])}],
			"day": _now(), "state": "open", "deadline": _now() + 28, "by": ""}
		t["holder"] = ""
		t["dispute"] = did
		(t["hist"] as Array).append("disputed day %d" % _now())
		stats["disputes"] = int(stats["disputes"]) + 1
		out["dispute"] = did
		Events.log_to(hub, "succession", "", [String(hs[0]["pid"]), String(hs[1]["pid"])], "dispute", "%s is disputed after %s" % [key, cause], 6)
		return out
	_install(key, String(hs[0]["pid"]), old)
	out["new"] = String(t["holder"])
	out["regent"] = String(t["regent"])
	return out


func _install(key: String, pid: String, old: String) -> void:
	var t := _t(key)
	t["holder"] = pid
	t["dispute"] = ""
	t["since"] = _now()
	t["regent"] = ""
	if age_of(pid) < ADULT:
		t["regent"] = _pick_regent(key, pid)
		if String(t["regent"]) != "":
			stats["regencies"] = int(stats["regencies"]) + 1
	stats["successions"] = int(stats["successions"]) + 1
	(t["hist"] as Array).append("%s holds from day %d" % [String(_ppl[pid]["name"]), _now()])
	if (t["hist"] as Array).size() > 8:
		(t["hist"] as Array).pop_front()
	Events.log_to(hub, "succession", "", [pid, old], "succession", "%s succeeds to %s" % [String(_ppl[pid]["name"]), key], 6)
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("i:" + pid, "recognised", -1, 0.5)
	_seat(key, pid)


func _seat(key: String, pid: String) -> void:
	var st: Variant = _mod("stewardship")
	if st == null:
		return
	var t := _t(key)
	var rule_holder := String(t["regent"]) if String(t["regent"]) != "" else pid
	var nm := String(_ppl[rule_holder]["name"])
	var bits := key.split(":")
	if bits[0] == "crown":
		if bits[1] == PD.HOME:
			st.assume("%d:3" % PD.capital_sid(), rule_holder, nm, false, 0.55, 0.6)
	elif bits[0] == "lord":
		st.assume("%d:0" % int(bits[1]), rule_holder, nm, false, 0.5, 0.6)
		if PD.is_seat(PD.kind_of(int(bits[1]))):
			st.assume("%d:2" % int(bits[1]), rule_holder, nm, false, 0.5, 0.6)


## Support for each party in an open dispute (council weight, reputation, strength).
func support(did: String) -> Dictionary:
	var d: Dictionary = _dis.get(did, {})
	var out := {}
	if d.is_empty():
		return out
	var t := _t(String(d["title"]))
	for party: Dictionary in d["parties"]:
		out[String(party["pid"])] = snappedf(float(party["s"]) * 0.6 + _elect_score(String(party["pid"]), t["council"]) * 0.5, 0.001)
	return out


## method: council (vote), petition (the crown rules, with audiences-style weighing), war (strength and chance). Returns the winner pid.
func resolve_dispute(did: String, method := "council") -> String:
	var d: Dictionary = _dis.get(did, {})
	if d.is_empty() or String(d["state"]) != "open":
		return ""
	var sup := support(did)
	var best := ""
	var bv := -1.0
	var ids: Array = sup.keys()
	ids.sort()
	var r := PD.rng("dres", _now(), did)
	for pid: String in ids:
		var v := float(sup[pid])
		if method == "war":
			v = v * 0.5 + r.randf() * 0.7
		if v > bv:
			bv = v
			best = pid
	d["state"] = "resolved"
	d["by"] = method
	d["winner"] = best
	var key := String(d["title"])
	_install(key, best, "")
	for party: Dictionary in d["parties"]:
		if String(party["pid"]) != best:
			add_claim(key, String(party["pid"]), "grievance", 0.4)
	if method == "war":
		Events.log_to(hub, "battle", "", [best], "succession war", "war over %s" % key, 6)
	return best


func disputes(open_only := true) -> Array:
	var out: Array = []
	for d: Dictionary in _dis.values():
		if not open_only or String(d["state"]) == "open":
			out.append(d.duplicate(true))
	return out


# ------------------------------------------------------------------ ticks

func tick_week(_week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	var keys := _titles.keys()
	keys.sort()
	for key: String in keys:
		var t: Dictionary = _titles[key]
		var hp := String(t["holder"])
		if hp != "":
			var a := age_of(hp)
			var haz := 0.0002 + maxf(0.0, float(a - 55)) * 0.0004
			if PD.rng("mort", _now(), [key, hp]).randf() < haz:
				die(hp)
				continue
			# Regency ends when the ward comes of age.
			if String(t["regent"]) != "" and age_of(hp) >= ADULT:
				(t["hist"] as Array).append("regency ends day %d" % _now())
				t["regent"] = ""
				_seat(key, hp)
			# A couple may have children.
			var sp := String(_ppl[hp]["spouse"])
			if sp != "" and bool(_ppl.get(sp, {}).get("alive", false)) and (_ppl[hp]["kids"] as Array).size() < 5 and age_of(sp) < 42 and age_of(sp) >= 18:
				if PD.rng("kid", _now(), [key, hp]).randf() < 0.01:
					beget(hp, sp)
	for did: String in _dis.keys():
		var d: Dictionary = _dis[did]
		if String(d["state"]) == "open" and _now() >= int(d["deadline"]):
			resolve_dispute(did, "council")
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	_day += days
	for i in mini(days / 7, 4):
		tick_week(0, ctx)
	return []


func warm() -> void:
	for k: String in PD.kingdoms():
		_t("crown:" + k)


func serialize() -> Dictionary:
	return {"ppl": _ppl.duplicate(true), "titles": _titles.duplicate(true), "claims": _claims.duplicate(true), "dis": _dis.duplicate(true), "local": _local.duplicate(),
		"np": _next_p, "nd": _next_d, "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ppl = (d.get("ppl", {}) as Dictionary).duplicate(true)
	for p: Dictionary in _ppl.values():
		PD.fix_ints(p, ["born", "died"])
	_titles = (d.get("titles", {}) as Dictionary).duplicate(true)
	for t: Dictionary in _titles.values():
		PD.fix_ints(t, ["since"])
	_claims = (d.get("claims", {}) as Dictionary).duplicate(true)
	_dis = (d.get("dis", {}) as Dictionary).duplicate(true)
	for x: Dictionary in _dis.values():
		PD.fix_ints(x, ["day", "deadline"])
	_local = (d.get("local", {}) as Dictionary).duplicate()
	_next_p = int(d.get("np", 1))
	_next_d = int(d.get("nd", 1))
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
