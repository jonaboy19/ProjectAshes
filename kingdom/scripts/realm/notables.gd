extends "res://scripts/realm/realm_module.gd"
## Notables and NPC agency (docs/design/CIVILIZATION.md CIV-B): about 60 named adventurers, officers, merchants
## and scholars with ambitions who rise and fall and found companies, guilds, orders, mercenary bands,
## settlements (asked of civilization.gd when present) or states; families as institutions (inherited
## businesses, specialties, generational reputation that remembers help given to parents); guild and company
## competition; NPC research that can fail and spreads as knowledge; academy drift, rivalry and teachers leaving;
## expeditions the player can join, fund, sabotage or rescue (lost ones become mysteries that plant a relic lead
## in exploration.gd); and crises that NPC heroes solve (or fail) when nobody else does.
##
## Pure data, JSON-safe, deterministic. Weekly work runs as daily slices (index % 7 == day % 7) so every pump
## job is tiny; catch_up is closed form per entity. Dead notables are pruned into one-line history.
## Other modules read news_events() (cursor on "seq"); notables feed fame and nicknames to news.gd.

const Soc := preload("res://scripts/realm/society.gd")
const SAVE_VERSION := 1
const YEAR := 360
const TARGET := 60
const EVENT_CAP := 30
const HIST_CAP := 50
const ORG_CAP := 26
const ROLES := ["adventurer", "officer", "merchant", "scholar"]
const ROLE_SPLIT := [24, 10, 14, 12]
const TRAITS := ["competence", "ambition", "charm", "martial", "scholar", "greed"]
const FAMILY_SPEC := ["military", "healing", "trade", "crime", "scholarship", "craft"]
const SPEC_BIZ := {"military": "drill yard", "healing": "apothecary", "trade": "caravan house", "crime": "pawn shop",
	"scholarship": "scriptorium", "craft": "smithy"}
const ROLE_SPEC := {"adventurer": ["military", "crime", "healing"], "officer": ["military"], "merchant": ["trade", "craft", "crime"],
	"scholar": ["scholarship", "healing"]}
const ROLE_AMB := {"adventurer": ["band", "expedition", "order", "settlement", "band"], "officer": ["band", "govern", "state", "band"],
	"merchant": ["company", "guild", "settlement", "govern", "company"], "scholar": ["research", "order", "guild", "academy", "research"]}
## ambition -> {renown, wealth} needed to found it.
const AMB_COST := {"company": [10.0, 550.0], "guild": [18.0, 1200.0], "band": [12.0, 700.0], "order": [28.0, 2000.0],
	"academy": [20.0, 1500.0], "settlement": [40.0, 2600.0], "state": [70.0, 5000.0]}
const ORG_TITLE := {"company": "Company", "guild": "Guild", "band": "Free Company", "order": "Order", "academy": "School",
	"settlement": "Holding", "state": "Realm"}
const GOV_KIND := {"company": "company", "band": "company", "guild": "guild", "order": "order", "academy": "guild", "state": "state"}
const FIELDS := {"runestone_design": "a sturdier runestone design", "agriculture": "a hardier crop rotation",
	"medicine": "a cure for the marsh fever", "rift_gear": "gear that shrugs off Rift taint"}
const CRISIS := {"bandits": "A bandit gang is bleeding the roads near %s.", "monster_nest": "Something has nested in the hills by %s.",
	"plague": "Sickness is creeping through the lanes of %s.", "border_raid": "Raiders have crossed the border near %s.",
	"rift_spill": "The Rift leaks near %s."}
const CO_A := ["Trading", "Carters", "Mercantile", "Caravan", "Freight"]
const GU_A := ["Weavers", "Masons", "Drovers", "Brewers", "Tanners", "Coopers"]
const OR_A := ["Silver", "Grey", "Ember", "Hollow", "Dawn"]
const OR_B := ["Lantern", "Stag", "Thorn", "Bell", "Key"]
const BA_A := ["Iron", "Red", "Pale", "Black", "Stone"]
const BA_B := ["Wolves", "Ravens", "Spears", "Hounds", "Shields"]

var _nb: Dictionary = {}        # nid -> notable
var _ids: Array = []            # stable order
var _fam: Dictionary = {}       # fid -> family
var _orgs: Dictionary = {}      # oid -> organisation
var _exp: Array = []            # expeditions
var _myst: Array = []           # lost expeditions turned mysteries
var _res: Array = []            # research projects
var _tech: Dictionary = {}      # field -> {lvl, at: [sids]}
var _crises: Array = []
var _claims: Array = []         # settlement claims nobody has answered
var _hist: Array = []
var _events: Array = []
var _seq := 0
var _next_n := 1
var _next_o := 1
var _next_e := 1
var _next_c := 1
var _next_r := 1
var _day := 0
var _built := false
var _tgt: Array = []            # cached expedition targets (not saved)


# ------------------------------------------------------------------ helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[sid]["name"]))
	return "the road"


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _emit(kind: String, sid: int, text: String, mag := 1.0, detail := "", official := false) -> void:
	_seq += 1
	_events.append({"seq": _seq, "kind": kind, "sid": sid, "day": _day, "mag": mag, "text": text, "detail": detail, "official": official})
	if _events.size() > EVENT_CAP:
		_events.pop_front()


func news_events(since := 0) -> Array:
	if since <= 0:
		return _events.duplicate(true)
	var out: Array = []
	for e: Dictionary in _events:
		if int(e["seq"]) > since:
			out.append(e.duplicate())
	return out


func _hist_add(line: String) -> void:
	_hist.append(line)
	if _hist.size() > HIST_CAP:
		_hist.pop_front()


func chronicle() -> Array:
	return _hist.duplicate()


func _deed(nid: String, deed: String, sid: int, mag: float) -> void:
	var nw: Variant = _mod("news")
	if nw != null and nw.has_method("record_deed") and _nb.has(nid):
		nw.record_deed("n:" + nid, String(_nb[nid]["n"]), deed, sid, mag, _day)


func _age(n: Dictionary) -> int:
	return int(floor(float(_day - int(n["born"])) / float(YEAR)))


func _roads() -> Dictionary:
	var soc: Variant = _mod("society")
	if soc != null and soc.has_method("_road_nbrs"):
		return soc.call("_road_nbrs")
	return {}


# ------------------------------------------------------------------ seeding

func _ensure() -> void:
	if _built:
		return
	_built = true
	var r := _rng("nseed", 0, 0)
	for i in FAMILY_SPEC.size() * 2 + 2:
		var spec: String = FAMILY_SPEC[i % FAMILY_SPEC.size()]
		var fid := "f%d" % i
		var sur: String = Soc.SURN[(i * 5 + 3) % Soc.SURN.size()]
		var sid := r.randi() % maxi(1, WorldGen.settlements.size())
		_fam[fid] = {"id": fid, "n": sur, "spec": spec, "rep": snappedf(r.randf() * 10.0, 0.1), "good": 0.0, "head": "",
			"biz": {"kind": SPEC_BIZ[spec], "sid": sid, "name": "%s %s of %s" % [sur, String(SPEC_BIZ[spec]).capitalize(), _sname(sid)]}}
	var k := 0
	for ri in ROLES.size():
		for j in int(ROLE_SPLIT[ri]):
			_spawn(ROLES[ri], "", r.randi_range(22, 55), k)
			k += 1
	# Established organisations at the start of the era, so there is competition from day one.
	var seeds := [["company", "merchant", 0], ["company", "merchant", 4], ["band", "officer", 1], ["guild", "merchant", 9]]
	for sd: Array in seeds:
		var pool: Array = []
		for nid: String in _ids:
			if String(_nb[nid]["role"]) == String(sd[1]) and String(_nb[nid]["org"]) == "":
				pool.append(nid)
		if not pool.is_empty():
			_found(String(pool[int(sd[2]) % pool.size()]), String(sd[0]), true)


func _spawn(role: String, fid: String, age: int, salt: Variant, parent: Dictionary = {}) -> String:
	var nid := "n%d" % _next_n
	_next_n += 1
	var r := _rng("nspawn", _day, [nid, salt])
	var tr := {}
	for t: String in TRAITS:
		tr[t] = snappedf(r.randf(), 0.01)
	tr["competence"] = snappedf(0.3 + r.randf() * 0.65, 0.01)
	if not parent.is_empty():
		for t: String in TRAITS:
			tr[t] = snappedf(clampf(0.5 * float(tr[t]) + 0.5 * float((parent["tr"] as Dictionary)[t]), 0.0, 1.0), 0.01)
	if fid == "":
		var cands: Array = []
		var fkeys: Array = _fam.keys()
		fkeys.sort()
		for f: String in fkeys:
			if (ROLE_SPEC[role] as Array).has(String(_fam[f]["spec"])):
				cands.append(f)
		fid = String(cands[r.randi() % cands.size()])
	var fam: Dictionary = _fam[fid]
	var sid: int = int((fam["biz"] as Dictionary)["sid"]) if r.randf() < 0.5 else r.randi() % maxi(1, WorldGen.settlements.size())
	var ambs: Array = ROLE_AMB[role]
	var given := "%s%s" % [Soc.SYL_A[r.randi() % Soc.SYL_A.size()], Soc.SYL_B[r.randi() % Soc.SYL_B.size()]]
	var n := {"id": nid, "n": "%s %s" % [given, fam["n"]], "born": _day - age * YEAR - r.randi() % YEAR, "role": role, "sid": sid, "tr": tr,
		"amb": String(ambs[r.randi() % ambs.size()]), "prog": snappedf(r.randf() * 0.5, 0.01), "renown": snappedf(2.0 + r.randf() * 26.0, 0.1),
		"wealth": snappedf(r.randf() * 250.0, 1.0), "status": "active", "org": "", "fam": fid, "until": 0, "feats": [], "title": ""}
	if not parent.is_empty():
		n["renown"] = snappedf(float(parent["renown"]) * 0.3 + float(fam["rep"]) * 0.25 + 2.0, 0.1)
		n["wealth"] = snappedf(float(parent["wealth"]) * 0.5, 1.0)
		n["role"] = String(parent["role"]) if r.randf() < 0.6 else role
	_nb[nid] = n
	_ids.append(nid)
	if String(fam["head"]) == "" or not _nb.has(String(fam["head"])):
		fam["head"] = nid
	return nid


# ------------------------------------------------------------------ public reads

func notables(status := "") -> Array:
	_ensure()
	var out: Array = []
	for nid: String in _ids:
		if status == "" or String(_nb[nid]["status"]) == status:
			out.append(notable(nid))
	return out


func notable(nid: String) -> Dictionary:
	var n: Dictionary = _nb.get(nid, {})
	if n.is_empty():
		return {}
	var o := n.duplicate(true)
	o["age"] = _age(n)
	return o


func families() -> Array:
	_ensure()
	var out: Array = []
	for f: String in _fam:
		out.append((_fam[f] as Dictionary).duplicate(true))
	return out


func orgs(kind := "") -> Array:
	_ensure()
	var out: Array = []
	var ids: Array = _orgs.keys()
	ids.sort()
	for o: String in ids:
		if kind == "" or String(_orgs[o]["kind"]) == kind:
			out.append((_orgs[o] as Dictionary).duplicate(true))
	return out


func research() -> Array:
	return _res.duplicate(true)


func tech(field: String) -> int:
	return int((_tech.get(field, {}) as Dictionary).get("lvl", 0))


func tech_known_at(field: String, sid: int) -> bool:
	return ((_tech.get(field, {}) as Dictionary).get("at", []) as Array).has(sid)


func crises() -> Array:
	return _crises.duplicate(true)


func mysteries() -> Array:
	return _myst.duplicate(true)


func claims() -> Array:
	return _claims.duplicate(true)


func active_count() -> int:
	return _ids.size()


# ------------------------------------------------------------------ families

## Help given to someone is remembered by the family and its heirs (generational reputation).
func record_help(who: String, weight: float) -> void:
	_ensure()
	var fid := who
	if _nb.has(who):
		fid = String(_nb[who]["fam"])
	if _fam.has(fid):
		var f: Dictionary = _fam[fid]
		f["good"] = snappedf(clampf(float(f["good"]) + weight, -100.0, 100.0), 0.01)
		f["rep"] = snappedf(float(f["rep"]) + maxf(0.0, weight) * 0.1, 0.01)


func family_goodwill(fid: String) -> float:
	return float((_fam.get(fid, {}) as Dictionary).get("good", 0.0))


## How a notable regards the player: their family's memory of past help plus their own standing.
func attitude(nid: String) -> float:
	var n: Dictionary = _nb.get(nid, {})
	if n.is_empty():
		return 0.0
	return family_goodwill(String(n["fam"]))


# ------------------------------------------------------------------ governance hook

## Governance asks for a notable to take a chair; returns a person dict or {}.
func recruit_leader(iid: String, sid: int) -> Dictionary:
	_ensure()
	var best := ""
	var bs := -1.0
	for nid: String in _ids:
		var n: Dictionary = _nb[nid]
		if String(n["status"]) != "active" or String(n["org"]) != "" or float(n["renown"]) < 10.0:
			continue
		var tr: Dictionary = n["tr"]
		var sc := float(tr["competence"]) + (0.3 if String(n["amb"]) == "govern" else 0.0) + (0.2 if int(n["sid"]) == sid else 0.0) \
			+ float(n["renown"]) * 0.004
		if sc > bs and float(tr["competence"]) >= 0.5:
			bs = sc
			best = nid
	if best == "":
		return {}
	var n2: Dictionary = _nb[best]
	n2["status"] = "governing"
	n2["until"] = _day + 1440
	n2["renown"] = float(n2["renown"]) + 5.0
	_feat(n2, "governed %s" % _sname(sid))
	var tr2: Dictionary = n2["tr"]
	return {"n": n2["n"], "born": n2["born"], "nid": best, "tr": {"competence": tr2["competence"], "greed": tr2["greed"],
		"piety": snappedf(1.0 - float(tr2["scholar"]) * 0.5, 0.01), "martial": tr2["martial"], "openness": tr2["charm"]}}


## news.gd: a nickname became a formal title.
func set_nick(nid: String, nick: String) -> void:
	if _nb.has(nid):
		_nb[nid]["nick"] = nick


func _feat(n: Dictionary, text: String) -> void:
	var f: Array = n["feats"]
	f.append(text)
	if f.size() > 3:
		f.pop_front()


# ------------------------------------------------------------------ founding

func _org_name(kind: String, n: Dictionary, r: RandomNumberGenerator) -> String:
	var sur := String(n["n"]).split(" ")[-1]
	match kind:
		"company":
			return "%s %s %s" % [sur, CO_A[r.randi() % CO_A.size()], "Company"]
		"guild":
			return "%s Guild of %s" % [_sname(int(n["sid"])), GU_A[r.randi() % GU_A.size()]]
		"order":
			return "Order of the %s %s" % [OR_A[r.randi() % OR_A.size()], OR_B[r.randi() % OR_B.size()]]
		"band":
			return "%s %s" % [BA_A[r.randi() % BA_A.size()], BA_B[r.randi() % BA_B.size()]]
		"academy":
			return "%s School of %s" % [sur, ["Letters", "Runes", "Herbs", "Arms"][r.randi() % 4]]
		"settlement":
			return "%sford" % sur
		_:
			return "The Free Barony of %s" % sur


func _found(nid: String, kind: String, seeded := false) -> bool:
	var n: Dictionary = _nb[nid]
	var r := _rng("nfound", _day, [nid, kind])
	var nm := _org_name(kind, n, r)
	for tries in 8:   # names are unique
		var clash := false
		for x: String in _orgs:
			if String(_orgs[x]["n"]) == nm:
				clash = true
		if not clash:
			break
		nm = _org_name(kind, n, r)
	var oid := "o%d" % _next_o
	_next_o += 1
	var o := {"id": oid, "kind": kind, "n": nm, "founder": String(n["n"]), "leader": nid, "sid": int(n["sid"]), "day": _day - (r.randi() % 1500 if seeded else 0),
		"power": snappedf(6.0 + float(n["renown"]) * 0.3 + r.randf() * 6.0, 0.1), "branches": 0, "rival": "", "status": "active", "fam": String(n["fam"])}
	if kind == "settlement":
		o["status"] = "claimed"
		if not _civ_request(nid, o):
			_claims.append({"by": nid, "name": nm, "sid": int(n["sid"]), "day": _day})
			if _claims.size() > 6:
				_claims.pop_front()
	_orgs[oid] = o
	var cost: Array = AMB_COST.get(kind, [0.0, 0.0])
	if not seeded:
		n["wealth"] = maxf(0.0, float(n["wealth"]) - float(cost[1]) * 0.8)
		n["renown"] = float(n["renown"]) + 6.0
	n["org"] = oid
	n["amb"] = "expand"
	n["prog"] = 0.0
	n["title"] = "founder of %s" % nm
	_feat(n, "founded %s" % nm)
	var fam: Dictionary = _fam[String(n["fam"])]
	fam["rep"] = float(fam["rep"]) + 1.5
	_register(o, n)
	if not seeded:
		var sname := _sname(int(n["sid"]))
		var verb: String = {"company": "opens the %s", "guild": "founds the %s", "band": "raises the %s company", "order": "founds the %s",
			"academy": "opens the %s", "settlement": "stakes a claim and founds %s", "state": "proclaims %s"}[kind]
		_emit("founded_org", int(n["sid"]), ("%s " % n["n"]) + verb % nm + " at %s." % sname, 2.0 if kind in ["settlement", "state"] else 1.5,
			"A %s of %s." % [String(ORG_TITLE[kind]).to_lower(), sname], true)
		_hist_add("Year %d: %s founded %s (%s)." % [_day / YEAR + 1, n["n"], nm, kind])
		_deed(nid, "founded", int(n["sid"]), 2.0)
	_prune_orgs()
	return true


func _civ_request(nid: String, o: Dictionary) -> bool:
	var civ: Variant = _mod("civilization")
	if civ != null and civ.has_method("request_founding"):
		var res: Variant = civ.request_founding({"founder": String(_nb[nid]["n"]), "nid": nid, "near": int(o["sid"]), "name": String(o["n"]), "kind": "camp"})
		if res is Dictionary:
			return bool((res as Dictionary).get("ok", true))
		return bool(res)
	return false


func _register(o: Dictionary, n: Dictionary) -> void:
	var gov: Variant = _mod("governance")
	if gov == null or not GOV_KIND.has(String(o["kind"])) or not gov.has_method("register_institution"):
		return
	var tr: Dictionary = n["tr"]
	var succ := "heredity" if o["kind"] in ["company", "band"] else ("election" if o["kind"] == "guild" else "appointment")
	gov.register_institution(String(GOV_KIND[String(o["kind"])]), String(o["id"]), String(o["n"]), int(o["sid"]), succ,
		{"n": n["n"], "born": n["born"], "nid": String(n["id"]), "tr": {"competence": tr["competence"], "greed": tr["greed"],
		"piety": snappedf(1.0 - float(tr["scholar"]) * 0.5, 0.01), "martial": tr["martial"], "openness": tr["charm"]}})


func _prune_orgs() -> void:
	if _orgs.size() <= ORG_CAP:
		return
	var worst := ""
	var wp := 1.0e9
	var okeys: Array = _orgs.keys()
	okeys.sort()
	for oid: String in okeys:
		if float(_orgs[oid]["power"]) < wp and String(_orgs[oid]["kind"]) != "settlement":
			wp = float(_orgs[oid]["power"])
			worst = oid
	if worst != "":
		_dissolve(worst, "failed")


func _dissolve(oid: String, why: String) -> void:
	var o: Dictionary = _orgs.get(oid, {})
	if o.is_empty():
		return
	for nid: String in _ids:
		if String(_nb[nid]["org"]) == oid:
			_nb[nid]["org"] = ""
			_nb[nid]["title"] = ""
			_nb[nid]["amb"] = "none"
	_hist_add("Year %d: %s %s." % [_day / YEAR + 1, o["n"], why])
	_emit("org_failed", int(o["sid"]), "%s has closed its doors." % o["n"], 1.0, "", true)
	_orgs.erase(oid)


# ------------------------------------------------------------------ notable weekly step

func _death_hazard(n: Dictionary) -> float:
	var a := _age(n)
	var base := 0.004 if a < 45 else (0.012 if a < 55 else (0.04 if a < 65 else (0.1 if a < 75 else 0.25)))
	if String(n["role"]) in ["adventurer", "officer"]:
		base *= 1.8
	return minf(0.9, base)


func _income(n: Dictionary) -> float:
	var m := {"merchant": 2.2, "officer": 1.4, "adventurer": 1.2, "scholar": 0.9}[String(n["role"])] as float
	return float((n["tr"] as Dictionary)["competence"]) * 3.0 * m


func _nb_step(nid: String, weeks: float, msgs: Array) -> void:
	if not _nb.has(nid):
		return
	var n: Dictionary = _nb[nid]
	var r := _rng("nstep", _day, nid)
	var tr: Dictionary = n["tr"]
	if r.randf() < 1.0 - pow(1.0 - _death_hazard(n), weeks * 7.0 / float(YEAR)):
		_die(nid, "died", msgs)
		return
	var a := _age(n)
	if a >= 58 and r.randf() < 1.0 - pow(1.0 - minf(0.5, 0.08 + float(a - 58) * 0.03), weeks * 7.0 / float(YEAR)):
		_die(nid, "retired", msgs)
		return
	if String(n["status"]) in ["governing", "busy"] and _day >= int(n["until"]):
		n["status"] = "active"
	n["wealth"] = snappedf(maxf(0.0, float(n["wealth"]) + (_income(n) - 1.2) * weeks), 0.1)
	# Fame fades unless kept up; competence and charm keep it.
	n["renown"] = snappedf(clampf(float(n["renown"]) + (float(tr["charm"]) * 0.22 + float(tr["competence"]) * 0.2 - 0.18) * weeks, 0.0, 100.0), 0.1)
	var amb := String(n["amb"])
	if amb == "expand" or amb == "none" or String(n["status"]) != "active":
		return
	var rate := (float(tr["ambition"]) * 0.5 + float(tr["competence"]) * 0.3 + float(tr["charm"]) * 0.2) * 0.04 * weeks
	n["prog"] = snappedf(minf(1.5, float(n["prog"]) + rate * (0.6 + r.randf() * 0.8)), 0.001)
	if float(n["prog"]) < 1.0:
		return
	if amb == "expedition" or amb == "research" or amb == "govern":
		n["prog"] = 0.35
		return   # handled by those weekly systems (they draw a leader with this ambition)
	var cost: Array = AMB_COST.get(amb, [999.0, 99999.0])
	if float(n["renown"]) >= float(cost[0]) and float(n["wealth"]) >= float(cost[1]) and _orgs.size() < ORG_CAP:
		if amb == "settlement" and _count_kind("settlement") >= 4:
			n["amb"] = "company"
			n["prog"] = 0.3
			return
		if amb == "state" and _count_kind("state") >= 1:
			n["amb"] = "band"
			n["prog"] = 0.3
			return
		if _found(nid, amb):
			msgs.append(String((_events[-1] as Dictionary)["text"]))
	else:
		n["prog"] = 0.8   # keeps trying while it earns and gains renown


func _count_kind(kind: String) -> int:
	var c := 0
	for oid: String in _orgs:
		if String(_orgs[oid]["kind"]) == kind:
			c += 1
	return c


func _die(nid: String, why: String, msgs: Array) -> void:
	var n: Dictionary = _nb[nid]
	var fam: Dictionary = _fam[String(n["fam"])]
	var title := String(n["title"])
	var line := "%s, %s%s, %s in year %d (age %d)." % [n["n"], String(n["role"]), (" and " + title) if title != "" else "", why, _day / YEAR + 1, _age(n)]
	if (n["feats"] as Array).size() > 0:
		line += " " + "; ".join(n["feats"]) + "."
	_hist_add(line)
	var notable_leader := float(n["renown"]) >= 25.0 or String(n["org"]) != ""
	if notable_leader:
		_emit("notable_gone", int(n["sid"]), "%s has %s." % [n["n"], why], 1.0, line, false)
	# Fame of the dead passes to the family.
	fam["rep"] = snappedf(float(fam["rep"]) + float(n["renown"]) * 0.25, 0.01)
	var oid := String(n["org"])
	var gov: Variant = _mod("governance")
	if gov != null and gov.has_method("notable_died") and oid != "":
		gov.notable_died(nid)
	_nb.erase(nid)
	_ids.erase(nid)
	# Missions led by the dead go on without a leader or fail.
	for e: Dictionary in _exp:
		if String(e["leader"]) == nid and String(e["status"]) == "out":
			e["leader"] = ""
			e["mod"] = float(e.get("mod", 0.0)) - 0.25
	# Heir: the family keeps the business; the org passes to an heir or the best local notable.
	var heir := _spawn(String(n["role"]), String(n["fam"]), 19 + absi(int(hash([nid, _day]))) % 10, nid, n)
	var hn: Dictionary = _nb[heir]
	if String(fam["head"]) == nid or String(fam["head"]) == "" or not _nb.has(String(fam["head"])):
		fam["head"] = heir
		var biz: Dictionary = fam["biz"]
		_emit("inherit", int(biz["sid"]), "%s takes over the %s." % [hn["n"], biz["name"]], 0.8, "", false)
	if oid != "" and _orgs.has(oid):
		var o: Dictionary = _orgs[oid]
		if String(o["kind"]) in ["company", "band", "settlement"]:
			o["leader"] = heir
			hn["org"] = oid
			hn["title"] = "head of %s" % o["n"]
			hn["amb"] = "expand"
		else:
			var bestn := ""
			var bc := -1.0
			for x: String in _ids:
				var xn: Dictionary = _nb[x]
				if String(xn["org"]) == "" and String(xn["status"]) == "active" and String(xn["amb"]) != "expand":
					var sc := float((xn["tr"] as Dictionary)["competence"]) + (0.3 if int(xn["sid"]) == int(o["sid"]) else 0.0)
					if sc > bc:
						bc = sc
						bestn = x
			if bestn != "":
				o["leader"] = bestn
				_nb[bestn]["org"] = oid
				_nb[bestn]["title"] = "head of %s" % o["n"]
				_nb[bestn]["amb"] = "expand"
			else:
				o["leader"] = ""
				o["status"] = "leaderless"
	if notable_leader:
		msgs.append("%s has %s." % [n["n"], why])


# ------------------------------------------------------------------ organisations

func _org_step(oid: String, weeks: float, msgs: Array) -> void:
	var o: Dictionary = _orgs.get(oid, {})
	if o.is_empty():
		return
	var r := _rng("ostep", _day, oid)
	var lead: Dictionary = _nb.get(String(o["leader"]), {})
	var comp := float((lead.get("tr", {"competence": 0.3}) as Dictionary)["competence"])
	# Power drifts toward what the leader can sustain; leaderless outfits decay.
	var p := float(o["power"]) + (8.0 + 30.0 * comp - float(o["power"])) * 0.02 * weeks - (0.5 * weeks if lead.is_empty() else 0.0)
	var kind := String(o["kind"])
	if kind in ["company", "guild", "band", "academy"]:
		# Competition over contracts, territory and recruits against a rival of the same kind.
		var rival := String(o["rival"])
		if rival == "" or not _orgs.has(rival):
			rival = _pick_rival(oid, kind, r)
			o["rival"] = rival
		if rival != "" and _orgs.has(rival):
			var rv: Dictionary = _orgs[rival]
			var ratio := float(o["power"]) / maxf(1.0, float(o["power"]) + float(rv["power"]))
			var bouts := maxi(1, int(round(weeks / 2.0)))
			for b in bouts:
				if r.randf() < ratio:
					p += 0.45
					rv["power"] = maxf(1.0, float(rv["power"]) - 0.3)
				else:
					p -= 0.45
					rv["power"] = float(rv["power"]) + 0.3
	p = clampf(p, 0.0, 100.0)
	o["power"] = snappedf(p, 0.1)
	if kind == "company":
		var br := int(p / 22.0)
		if br > int(o["branches"]):
			o["branches"] = br
			var nb := _neighbor_sid(int(o["sid"]), r)
			_emit("branch", nb, "%s opens a warehouse in %s." % [o["n"], _sname(nb)], 1.0, "", true)
	if p < 2.0 and String(o["status"]) in ["leaderless", "active"] and r.randf() < 0.03 * weeks:
		_dissolve(oid, "collapsed")


func _pick_rival(oid: String, kind: String, r: RandomNumberGenerator) -> String:
	var c: Array = []
	for x: String in _orgs:
		if x != oid and String(_orgs[x]["kind"]) == kind:
			c.append(x)
	c.sort()
	return String(c[r.randi() % c.size()]) if not c.is_empty() else ""


func _neighbor_sid(sid: int, r: RandomNumberGenerator) -> int:
	var nb: Array = _roads().get(sid, [])
	if nb.is_empty():
		return sid
	return int((nb[r.randi() % nb.size()] as Array)[0])


# ------------------------------------------------------------------ expeditions

func _targets() -> Array:
	if _tgt.is_empty():
		for s: Dictionary in WorldGen.sites:
			if s.has("cave"):
				var best := 0
				var bd := INF
				for st: Dictionary in WorldGen.settlements:
					var d: float = (st["pos"] as Vector2).distance_squared_to(s["pos"])
					if d < bd:
						bd = d
						best = int(st["id"])
				_tgt.append({"id": String(s["cave"]["dungeon_id"]), "name": String(s["name"]).trim_prefix("The "), "sid": best})
	return _tgt


func expeditions(status := "") -> Array:
	var out: Array = []
	for e: Dictionary in _exp:
		if status == "" or String(e["status"]) == status:
			out.append(e.duplicate(true))
	return out


func _exp_by_id(eid: int) -> Dictionary:
	for e: Dictionary in _exp:
		if int(e["id"]) == eid:
			return e
	return {}


func _start_expedition(r: RandomNumberGenerator) -> void:
	var tg := _targets()
	if tg.is_empty():
		return
	var lead := ""
	var bs := -1.0
	for nid: String in _ids:
		var n: Dictionary = _nb[nid]
		if String(n["status"]) != "active":
			continue
		var tr: Dictionary = n["tr"]
		var sc := float(tr["martial"]) * 0.5 + float(tr["competence"]) * 0.4 + (0.4 if String(n["amb"]) == "expedition" else 0.0) + r.randf() * 0.3
		if sc > bs and float(n["renown"]) >= 6.0:
			bs = sc
			lead = nid
	if lead == "":
		return
	var t: Dictionary = tg[r.randi() % tg.size()]
	var n2: Dictionary = _nb[lead]
	var sponsor := String(n2["org"]) if String(n2["org"]) != "" else "crown"
	var eid := _next_e
	_next_e += 1
	var e := {"id": eid, "n": "The %s Expedition" % t["name"], "sponsor": sponsor, "leader": lead, "lname": String(n2["n"]), "target": t["id"],
		"tname": t["name"], "sid": int(t["sid"]), "size": r.randi_range(6, 18), "depart": _day, "eta": _day + r.randi_range(25, 70),
		"status": "out", "funding": 0, "sab": 0.0, "mod": 0.0, "player": false, "until": 0}
	_exp.append(e)
	n2["status"] = "expedition"
	_emit("expedition_out", int(t["sid"]), "%s sets out under %s to the %s." % [e["n"], n2["n"], t["name"]], 1.5,
		"%d people, sponsored by %s." % [int(e["size"]), "the Crown" if sponsor == "crown" else String((_orgs.get(sponsor, {"n": sponsor}) as Dictionary)["n"])], true)


func expedition_join(eid: int) -> Dictionary:
	var e := _exp_by_id(eid)
	if e.is_empty() or String(e["status"]) != "out" or bool(e["player"]):
		return {"ok": false, "reason": "You cannot join that expedition."}
	e["player"] = true
	e["mod"] = float(e["mod"]) + 0.12
	return {"ok": true, "eta": int(e["eta"]), "target": e["target"]}


## Caller deducts the gold; this records the money and improves the odds.
func expedition_fund(eid: int, gold: int) -> Dictionary:
	var e := _exp_by_id(eid)
	if e.is_empty() or String(e["status"]) != "out" or gold <= 0:
		return {"ok": false}
	e["funding"] = int(e["funding"]) + gold
	var lead: String = String(e["leader"])
	if _nb.has(lead):
		record_help(lead, minf(10.0, float(gold) * 0.02))
	return {"ok": true, "funding": int(e["funding"])}


func expedition_sabotage(eid: int) -> Dictionary:
	var e := _exp_by_id(eid)
	if e.is_empty() or String(e["status"]) != "out":
		return {"ok": false}
	var r := _rng("nsab", _day, eid)
	e["sab"] = float(e["sab"]) + 0.22
	var caught := r.randf() < 0.3
	if caught:
		_emit("sabotage", int(e["sid"]), "Someone tampered with the stores of %s." % e["n"], 1.0, "", false)
	return {"ok": true, "caught": caught}


## A missing expedition can be rescued inside its window. `power` 0..1 is how strong the rescuers are.
func expedition_rescue(eid: int, power := 0.5) -> Dictionary:
	var e := _exp_by_id(eid)
	if e.is_empty() or String(e["status"]) != "missing":
		return {"ok": false, "reason": "Nobody is waiting to be rescued."}
	var r := _rng("nresc", _day, eid)
	var ok := r.randf() < clampf(0.35 + 0.5 * power, 0.1, 0.95)
	if ok:
		e["status"] = "rescued"
		_emit("expedition_rescued", int(e["sid"]), "%s is found alive and brought home." % e["n"], 2.0, "", true)
		if _nb.has(String(e["leader"])):
			_nb[String(e["leader"])]["status"] = "active"
			record_help(String(e["leader"]), 25.0)
			_deed(String(e["leader"]), "rescued", int(e["sid"]), 2.0)
	else:
		e["until"] = int(e["until"]) - 7
	return {"ok": ok}


func _expedition_day() -> void:
	for e: Dictionary in _exp:
		var st := String(e["status"])
		if st == "out" and _day >= int(e["eta"]):
			_resolve_expedition(e)
		elif st == "missing" and _day >= int(e["until"]):
			_lose_expedition(e)
	# History stays short: finished ones fall off.
	while _exp.size() > 12:
		var done := -1
		for i in _exp.size():
			if String(_exp[i]["status"]) in ["returned", "rescued", "lost"]:
				done = i
				break
		if done < 0:
			break
		_exp.remove_at(done)


func _resolve_expedition(e: Dictionary) -> void:
	var r := _rng("nexp", _day, int(e["id"]))
	var lead: Dictionary = _nb.get(String(e["leader"]), {})
	var tr: Dictionary = lead.get("tr", {"martial": 0.3, "competence": 0.3})
	var p := 0.3 + 0.3 * float(tr["martial"]) + 0.25 * float(tr["competence"]) + minf(0.15, float(e["funding"]) * 0.0004) \
		+ float(e["mod"]) - float(e["sab"]) + (0.06 if int(e["size"]) > 12 else 0.0)
	if r.randf() < clampf(p, 0.05, 0.92):
		e["status"] = "returned"
		var loot := int(120 + r.randi() % 500)
		if not lead.is_empty():
			lead["status"] = "active"
			lead["renown"] = float(lead["renown"]) + 7.0
			lead["wealth"] = float(lead["wealth"]) + float(loot) * 0.4
			_feat(lead, "returned from %s" % e["tname"])
			_deed(String(e["leader"]), "expedition", int(e["sid"]), 2.5)
		var so: Dictionary = _orgs.get(String(e["sponsor"]), {})
		if not so.is_empty():
			so["power"] = float(so["power"]) + 3.0
		_emit("expedition_return", int(e["sid"]), "%s returns from the %s with %d crates of salvage." % [e["n"], e["tname"], 2 + loot / 120], 2.0, "", true)
	else:
		e["status"] = "missing"
		e["until"] = _day + 30   # rescue window
		_emit("expedition_missing", int(e["sid"]), "%s is overdue. Nobody has heard from it." % e["n"], 2.0,
			"It went into the %s." % e["tname"], true)


func _lose_expedition(e: Dictionary) -> void:
	e["status"] = "lost"
	var lead: Dictionary = _nb.get(String(e["leader"]), {})
	var lname := String(e["lname"])
	if not lead.is_empty():
		lead["status"] = "lost"
		lead["renown"] = float(lead["renown"]) + 3.0   # the legend grows
		var oid := String(lead["org"])
		if oid != "" and _orgs.has(oid):
			_orgs[oid]["power"] = maxf(0.0, float(_orgs[oid]["power"]) - 5.0)
		_die(String(e["leader"]), "vanished in the %s" % e["tname"], [])
	var r := _rng("nmyst", _day, int(e["id"]))
	_myst.append({"id": int(e["id"]), "n": String(e["n"]), "lname": lname, "target": String(e["target"]), "tname": String(e["tname"]), "day": _day,
		"relic_day": _day + r.randi_range(60, 240), "planted": false})
	if _myst.size() > 10:
		_myst.pop_front()
	_emit("expedition_lost", int(e["sid"]), "%s was never seen again. The %s keeps its secret." % [e["n"], e["tname"]], 3.0,
		"%s and %d others vanished." % [lname, int(e["size"]) - 1], true)
	_hist_add("Year %d: %s was lost in the %s." % [_day / YEAR + 1, e["n"], e["tname"]])


func _mystery_day() -> void:
	for m: Dictionary in _myst:
		if bool(m["planted"]) or _day < int(m["relic_day"]):
			continue
		m["planted"] = true
		var ex: Variant = _mod("exploration")
		var gear: String = ["a signal horn", "a rune-etched shield", "a captain's journal", "a sealed map case"][absi(int(hash([int(m["id"]), "gear"]))) % 4]
		if ex != null and ex.has_method("plant_relic"):
			ex.plant_relic(String(m["target"]), "%s's party carried %s; their remains lie deep in the %s." % [m["lname"], gear, m["tname"]], _day)
		_emit("relic_lead", 0, "Travellers talk of %s from the lost %s turning up in the %s." % [gear, String(m["n"]).trim_prefix("The "), m["tname"]], 1.5,
			"A lead toward %s." % m["tname"], false)


# ------------------------------------------------------------------ research

func _start_research(r: RandomNumberGenerator) -> void:
	var lead := ""
	var bs := -1.0
	for nid: String in _ids:
		var n: Dictionary = _nb[nid]
		if String(n["status"]) != "active":
			continue
		var sc := float((n["tr"] as Dictionary)["scholar"]) + (0.5 if String(n["role"]) == "scholar" else 0.0) + (0.3 if String(n["amb"]) == "research" else 0.0) + r.randf() * 0.4
		if sc > bs:
			bs = sc
			lead = nid
	if lead == "":
		return
	var fields: Array = FIELDS.keys()
	var field: String = fields[r.randi() % fields.size()]
	for p: Dictionary in _res:
		if String(p["field"]) == field and String(p["status"]) == "active":
			return
	var n2: Dictionary = _nb[lead]
	n2["status"] = "research"
	_res.append({"id": _next_r, "field": field, "lead": lead, "lname": String(n2["n"]), "sid": int(n2["sid"]), "done": 0.0,
		"need": float(r.randi_range(500, 1400)), "status": "active", "day": _day})
	_next_r += 1
	_emit("research_start", int(n2["sid"]), "%s begins work on %s." % [n2["n"], FIELDS[field]], 1.0, "", false)


func _academy_factor(sid: int) -> float:
	var ed: Variant = _mod("education")
	var f := 1.0
	if ed != null and ed.has_method("institutions"):
		for i: Dictionary in ed.institutions():
			if int(i["sid"]) == sid:
				f = maxf(f, 0.8 + float(i.get("prestige", 0.3)) * 0.8 + float(i.get("staff", 1.0)) * 0.1)
	return f


func _research_step(weeks: float, msgs: Array) -> void:
	for p: Dictionary in _res:
		if String(p["status"]) != "active":
			continue
		var r := _rng("nres", _day, int(p["id"]))
		var lead: Dictionary = _nb.get(String(p["lead"]), {})
		if lead.is_empty():
			p["status"] = "failed"
			_emit("research_fail", int(p["sid"]), "The work on %s died with %s." % [FIELDS[p["field"]], p["lname"]], 1.0, "", false)
			continue
		var tr: Dictionary = lead["tr"]
		var speed := (0.4 + float(tr["scholar"])) * _academy_factor(int(p["sid"]))
		p["done"] = float(p["done"]) + 7.0 * weeks * speed
		# Accidents, dead ends, lost funding.
		if r.randf() < 1.0 - pow(1.0 - (0.0003 + (1.0 - float(tr["competence"])) * 0.0004), 7.0 * weeks):
			p["status"] = "failed"
			lead["status"] = "active"
			lead["renown"] = maxf(0.0, float(lead["renown"]) - 5.0)
			_emit("research_fail", int(p["sid"]), "%s's work on %s ends in failure." % [p["lname"], FIELDS[p["field"]]], 1.0, "", false)
			continue
		if float(p["done"]) >= float(p["need"]):
			p["status"] = "done"
			lead["status"] = "active"
			var t: Dictionary = _tech.get(String(p["field"]), {"lvl": 0, "at": []})
			t["lvl"] = int(t["lvl"]) + 1
			var at: Array = t["at"]
			if not at.has(int(p["sid"])):
				at.append(int(p["sid"]))
			_tech[String(p["field"])] = t
			lead["renown"] = float(lead["renown"]) + 9.0
			_feat(lead, "discovered %s" % FIELDS[p["field"]])
			_emit("research_done", int(p["sid"]), "%s has perfected %s." % [p["lname"], FIELDS[p["field"]]], 2.0, "", true)
			_deed(String(p["lead"]), "discovery", int(p["sid"]), 2.5)
			var soc: Variant = _mod("society")
			if soc != null and soc.has_method("learn"):
				soc.learn("tech:%s:%d" % [p["field"], int(t["lvl"])], "Scholars in %s have %s." % [_sname(int(p["sid"])), FIELDS[p["field"]]])
	while _res.size() > 8:
		var gone := -1
		for i in _res.size():
			if String(_res[i]["status"]) != "active":
				gone = i
				break
		if gone < 0:
			break
		_res.remove_at(gone)


func _spread_tech(weeks: float, r: RandomNumberGenerator) -> void:
	var nbrs := _roads()
	var fields: Array = _tech.keys()
	fields.sort()
	for field: String in fields:
		var at: Array = (_tech[field] as Dictionary)["at"]
		for step in maxi(1, int(weeks / 2.0)):
			if at.size() >= WorldGen.settlements.size():
				break
			var from := int(at[r.randi() % at.size()])
			var nb: Array = nbrs.get(from, [])
			if nb.is_empty():
				continue
			var to := int((nb[r.randi() % nb.size()] as Array)[0])
			if not at.has(to):
				at.append(to)


# ------------------------------------------------------------------ crises

func _spawn_crisis(r: RandomNumberGenerator) -> void:
	var kinds: Array = CRISIS.keys()
	var k: String = kinds[r.randi() % kinds.size()]
	var sid := r.randi() % maxi(1, WorldGen.settlements.size())
	var c := {"id": _next_c, "kind": k, "sid": sid, "day": _day, "sev": r.randi_range(1, 3), "deadline": _day + r.randi_range(25, 55), "status": "open"}
	_next_c += 1
	_crises.append(c)
	_emit("crisis", sid, String(CRISIS[k]) % _sname(sid), 1.0 + float(c["sev"]) * 0.3, "", false)


func crisis_resolve(cid: int) -> bool:
	## The player deals with it.
	for c: Dictionary in _crises:
		if int(c["id"]) == cid and String(c["status"]) == "open":
			c["status"] = "resolved_player"
			_emit("crisis_resolved", int(c["sid"]), "The trouble at %s has been dealt with." % _sname(int(c["sid"])), 1.0, "", false)
			return true
	return false


func _crisis_day() -> void:
	for c: Dictionary in _crises:
		if String(c["status"]) == "open" and _day >= int(c["deadline"]):
			_ignored_crisis(c)
	while _crises.size() > 10:
		var gone := -1
		for i in _crises.size():
			if String(_crises[i]["status"]) != "open":
				gone = i
				break
		if gone < 0:
			break
		_crises.remove_at(gone)


func _ignored_crisis(c: Dictionary) -> void:
	var r := _rng("ncrisis", _day, int(c["id"]))
	var hero := ""
	var bs := 0.0
	for nid: String in _ids:
		var n: Dictionary = _nb[nid]
		if String(n["status"]) != "active":
			continue
		var sc := float((n["tr"] as Dictionary)["martial"]) + float(n["renown"]) * 0.004 + r.randf() * 0.25
		if sc > bs:
			bs = sc
			hero = nid
	var sid := int(c["sid"])
	var sname := _sname(sid)
	var gov: Variant = _mod("governance")
	var pw := 0.0
	if hero != "":
		pw = float((_nb[hero]["tr"] as Dictionary)["martial"])
	if hero != "" and r.randf() < clampf(0.25 + 0.6 * pw - 0.1 * float(c["sev"]), 0.05, 0.9):
		c["status"] = "resolved_npc"
		var hn: Dictionary = _nb[hero]
		hn["status"] = "busy"   # recovering and travelling for a month
		hn["until"] = _day + 30
		hn["renown"] = float(hn["renown"]) + 6.0 + float(c["sev"]) * 2.0
		_feat(hn, "saved %s" % sname)
		_emit("crisis_resolved", sid, "%s has put down the trouble at %s." % [hn["n"], sname], 2.0, "", true)
		_deed(hero, {"bandits": "bandits_broken", "monster_nest": "beast_slain", "plague": "healed", "border_raid": "defended", "rift_spill": "rift_sealed"}[String(c["kind"])], sid, 2.0 + float(c["sev"]))
		if gov != null and gov.has_method("shock"):
			gov.shock(sid, {"poor": 0.15, "farmers": 0.12, "soldiers": 0.1})
	else:
		c["status"] = "failed"
		_emit("crisis_failed", sid, "Nobody stopped the trouble at %s. The damage is done." % sname, 2.5, "", true)
		if gov != null and gov.has_method("shock"):
			gov.shock(sid, {"poor": -0.25, "farmers": -0.2, "merchants": -0.1})
		var st: Variant = _mod("settlements")
		if st != null and st.has_method("raid_aftermath"):
			st.raid_aftermath(sid, 0.15 * float(c["sev"]))


# ------------------------------------------------------------------ academies (extends education.gd)

func _academy_week(weeks: float, r: RandomNumberGenerator, msgs: Array) -> void:
	var ed: Variant = _mod("education")
	if ed == null or not ed.has_method("adjust_school"):
		return
	var insts: Array = ed.institutions()
	insts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return String(x["id"]) < String(y["id"]))
	var by_id := {}
	for i: Dictionary in insts:
		by_id[String(i["id"])] = i
	for i: Dictionary in insts:
		var id := String(i["id"])
		# Reputation drifts with results (noise) and recovers staff slowly.
		var drift := (r.randf() - 0.5) * 3.0 * weeks
		var staff_d := 0.008 * weeks if float(i.get("staff", 1.0)) < 1.0 else 0.0
		var rival := String(i.get("rival", ""))
		if rival != "" and by_id.has(rival):
			var a := float(i["prestige"]) + float(ed.school_reputation(id)) / 100.0 + float(i.get("staff", 1.0)) * 0.3
			var b := float((by_id[rival] as Dictionary)["prestige"]) + float(ed.school_reputation(rival)) / 100.0 + float((by_id[rival] as Dictionary).get("staff", 1.0)) * 0.3
			if r.randf() < a / maxf(0.1, a + b):
				drift += 1.0 * weeks
				ed.adjust_school(rival, -0.7 * weeks, 0.0)   # the loser's students drift to the winner
			else:
				drift -= 1.0 * weeks
		# A teacher leaves (poached by a rival, or off to found a school).
		if not bool(i.get("hidden", false)) and r.randf() < 0.012 * weeks:
			staff_d -= 0.1
			var poach := rival != "" and by_id.has(rival) and r.randf() < 0.5
			if poach:
				ed.adjust_school(rival, 1.0, 0.06)
				_emit("teacher_poached", int(i["sid"]), "%s loses a master teacher to %s." % [i["name"], (by_id[rival] as Dictionary)["name"]], 1.0, "", false)
			else:
				_emit("teacher_left", int(i["sid"]), "A master teacher has left %s." % i["name"], 0.8, "", false)
				if r.randf() < 0.3 and _count_kind("academy") < 3:
					for nid: String in _ids:
						var n: Dictionary = _nb[nid]
						if String(n["role"]) == "scholar" and String(n["org"]) == "" and String(n["status"]) == "active" and float(n["wealth"]) > 200.0:
							_found(nid, "academy")
							break
		ed.adjust_school(id, drift, staff_d)


# ------------------------------------------------------------------ ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	return [
		func() -> Array:
			_day = day
			_ensure()
			return [],
		func() -> Array:
			var msgs: Array = []
			var slice := day % 7
			var snap: Array = _ids.duplicate()
			for i in snap.size():
				if i % 7 == slice:
					_nb_step(String(snap[i]), 1.0, msgs)
			return msgs,
		func() -> Array:
			var msgs: Array = []
			var slice := day % 7
			var ids: Array = _orgs.keys()
			ids.sort()
			for i in ids.size():
				if i % 7 == slice:
					_org_step(String(ids[i]), 1.0, msgs)
			return msgs,
		func() -> Array:
			var msgs: Array = []
			_expedition_day()
			_crisis_day()
			_mystery_day()
			if day % 7 == 2:
				var r := _rng("nweek", day, 0)
				if _exp_active() < 2 and r.randf() < 0.075:
					_start_expedition(r)
				if _res_active() < 3 and r.randf() < 0.1:
					_start_research(r)
				if _open_crises() < 3 and r.randf() < 0.10:
					_spawn_crisis(r)
				_research_step(1.0, msgs)
				_spread_tech(1.0, r)
			if day % 7 == 4:
				_academy_week(1.0, _rng("nacad", day, 0), msgs)
			return msgs,
	]


func _exp_active() -> int:
	var c := 0
	for e: Dictionary in _exp:
		if String(e["status"]) in ["out", "missing"]:
			c += 1
	return c


func _res_active() -> int:
	var c := 0
	for p: Dictionary in _res:
		if String(p["status"]) == "active":
			c += 1
	return c


func _open_crises() -> int:
	var c := 0
	for x: Dictionary in _crises:
		if String(x["status"]) == "open":
			c += 1
	return c


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	if days <= 0:
		return msgs
	_ensure()
	_day += days
	var weeks := float(days) / 7.0
	for nid: String in _ids.duplicate():
		_nb_step(nid, weeks, msgs)
	var oids: Array = _orgs.keys()
	oids.sort()
	for oid: String in oids:
		_org_step(String(oid), weeks, msgs)
	# Missions, crises and mysteries due inside the span resolve now (at most twice over a very long span).
	for k in 2:
		_expedition_day()
		_crisis_day()
		_mystery_day()
	var r := _rng("ncatch", _day, days)
	var fresh := mini(2, int(weeks * 0.12))
	for i in fresh:
		if _exp_active() < 2:
			_start_expedition(r)
		if _res_active() < 3:
			_start_research(r)
		if _open_crises() < 3:
			_spawn_crisis(r)
	_research_step(weeks, msgs)
	_spread_tech(weeks, r)
	_academy_week(minf(weeks, 8.0), _rng("nacad", _day, days), msgs)
	return msgs


# ------------------------------------------------------------------ persistence

func stats() -> Dictionary:
	_ensure()
	return {"notables": _ids.size(), "families": _fam.size(), "orgs": _orgs.size(), "expeditions": _exp.size(), "mysteries": _myst.size(),
		"research": _res.size(), "crises": _crises.size(), "history": _hist.size()}


func serialize() -> Dictionary:
	return {"v": SAVE_VERSION, "nb": _nb.duplicate(true), "ids": _ids.duplicate(), "fam": _fam.duplicate(true), "orgs": _orgs.duplicate(true),
		"exp": _exp.duplicate(true), "myst": _myst.duplicate(true), "res": _res.duplicate(true), "tech": _tech.duplicate(true),
		"crises": _crises.duplicate(true), "claims": _claims.duplicate(true), "hist": _hist.duplicate(), "events": _events.duplicate(true),
		"seq": _seq, "next": [_next_n, _next_o, _next_e, _next_c, _next_r], "day": _day, "built": _built}


func deserialize(d: Dictionary) -> void:
	_nb = (d.get("nb", {}) as Dictionary).duplicate(true)
	_ids = (d.get("ids", []) as Array).duplicate()
	_fam = (d.get("fam", {}) as Dictionary).duplicate(true)
	_orgs = (d.get("orgs", {}) as Dictionary).duplicate(true)
	_exp = (d.get("exp", []) as Array).duplicate(true)
	_myst = (d.get("myst", []) as Array).duplicate(true)
	_res = (d.get("res", []) as Array).duplicate(true)
	_tech = (d.get("tech", {}) as Dictionary).duplicate(true)
	for f: String in _tech:   # JSON turns ints into floats; Array.has(int) would then miss them
		var ints: Array = []
		for sid: Variant in (_tech[f]["at"] as Array):
			ints.append(int(sid))
		_tech[f]["at"] = ints
		_tech[f]["lvl"] = int(_tech[f]["lvl"])
	_crises = (d.get("crises", []) as Array).duplicate(true)
	_claims = (d.get("claims", []) as Array).duplicate(true)
	_hist = (d.get("hist", []) as Array).duplicate()
	_events = (d.get("events", []) as Array).duplicate(true)
	_seq = int(d.get("seq", 0))
	var nx: Array = d.get("next", [1, 1, 1, 1, 1])
	_next_n = int(nx[0])
	_next_o = int(nx[1])
	_next_e = int(nx[2])
	_next_c = int(nx[3])
	_next_r = int(nx[4])
	_day = int(d.get("day", 0))
	_built = bool(d.get("built", false))
	_tgt.clear()
