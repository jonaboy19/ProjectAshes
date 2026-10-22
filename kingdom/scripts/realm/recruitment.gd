extends "res://scripts/realm/realm_module.gd"
## Recruitment core (Living World §2, docs/design/LIVING_WORLD.md; RETINUE_SETTLEMENT_ASCENSION §2).
## You recruit people, not units. A recruit is a real WorldSim row turned into a persistent follower in
## followers.gd (the character: traits, skills, needs, wage owed), and this module adds what recruitment needs
## on top of it, without duplicating it:
##   Contract   persistent id "k<n>": parties, terms {w wage, d duty, n days (0 = open), h housing, x danger},
##              status (active / expired / ended / broken) and a short history.
##   Evaluation willingness of one person for one offer: needs, goals, traits, current work, trust in the
##              player, reputation, the pay and the danger; plain-words reasons; accept / counter / reject.
##   Notices    a vacancy posted at an inn / market / guild hall; applicants arrive over days, drawn from the
##              real people of that settlement (WorldSim rows), never invented.
##   Chains     "personal" followers (yours; kept when you resign), "org" members (army, guild: lost when you
##              resign from that org) and "property" employees (belong to the property, stay when you leave).
##   Agency     chunked day tick: wages, morale, raise demands, desertion, expiry and renewal, recommendations,
##              independence, and refusal of illegal or suicidal orders.
##   Managers   a follower appointed steward / captain of a group with a delegated budget. Competence scales
##              output; honesty and oversight scale skimming; audit() reveals it. Modes: manual, delegated,
##              autonomous.
## Trust in the player ("tr") and loyalty to an organization ("ol") are separate numbers.
## Followers are data only; nothing here touches a node. Money never touches the purse: Life drains
## take_pending_gold() (autoload/life.gd ledger list). Wages are the "owed" followers.gd accrues each day.

const Fol := preload("res://scripts/realm/followers.gd")
const Events := preload("res://scripts/realm/events.gd")

const WAGE_DAYS_DESERT := 3
const THRESHOLD := 50.0
const NOTICE_FEE := 3
const NOTICE_DRAWS := 3
const HISTORY_MAX := 4
const INDEP_MAX := 20
const REF_MAX := 8
## WorldSim.JOBS index -> followers.gd occupation.
const JOB_OCC := ["builder", "smith", "scout", "mercenary", "builder", "hunter"]
## duty -> {x danger 0..1, skills it uses}
const DUTIES := {
	"labor": {"x": 0.05, "skills": ["building", "repair", "smithing"], "label": "labour"},
	"guard": {"x": 0.35, "skills": ["combat", "tactics"], "label": "guard duty"},
	"escort": {"x": 0.5, "skills": ["combat", "riding", "tracking"], "label": "escort work"},
	"scout": {"x": 0.45, "skills": ["tracking", "stealth"], "label": "scouting"},
	"campaign": {"x": 0.8, "skills": ["combat", "tactics", "command"], "label": "campaigning"},
	"steward": {"x": 0.05, "skills": ["command", "speech", "building"], "label": "stewarding"},
}
const INDEP_AMBITIONS := ["earn a captaincy", "win renown", "save for a farm"]
const MODES := ["manual", "delegated", "autonomous"]
## Orders a recruit takes (stage 3 bodies: scripts/actors/follower_manager.gd). Stored on the follower
## (followers.gd "order" / "order_arg"; "" = the default for their duty, see effective_order).
const ORDERS := ["follow", "wait", "home", "work"]

var _c: Dictionary = {}          # contract id -> contract
var _r: Dictionary = {}          # fid -> roster entry
var _by_row: Dictionary = {}     # row -> fid (recruited and still bound)
var _n: Dictionary = {}          # notice id -> notice
var _g: Dictionary = {}          # group id -> group (property / squad)
var _refs: Array = []            # [{by fid, row, day}] recommendations waiting for an answer
var _indep: Array = []           # people who went independent [{name, occ, day}]
var _next_c := 1
var _next_n := 1
var _next_g := 1
var _pending := 0
var _pend_f := 0.0
var _day := 0
var _prof: Dictionary = {}       # row -> profile (derived, never saved)
var _ids: Array = []             # cached sorted roster ids
var _avail := 0                  # purse gold left for wages during one day tick


func _fol() -> RefCounted:
	return hub.mod("followers") if hub != null else null


func _rng(tag: String, d: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, d, str(id)])
	return r


# --------------------------------------------------------------- people

## What one WorldSim person is like, derived deterministically from their row.
func profile(row: int) -> Dictionary:
	if _prof.has(row):
		return _prof[row]
	var r := _rng("rc_prof", 0, row)
	var traits: Array = []
	while traits.size() < 3:
		var t: String = Fol.TRAITS[r.randi() % Fol.TRAITS.size()]
		if not traits.has(t):
			traits.append(t)
	var jb := int(WorldSim.job[row])
	var occ: String = JOB_OCC[jb % JOB_OCC.size()]
	var od: Dictionary = Fol.OCCUPATIONS[occ]
	var skills := {}
	for s in od["skills"]:
		skills[s] = snappedf(clampf(float(od["skills"][s]) + r.randf_range(-0.2, 0.2), 0.05, 1.0), 0.01)
	var cur: int = int(WorldSim.WAGES[jb % WorldSim.WAGES.size()])
	var money := int(WorldSim.money[row])
	var employed := jb != 4 and money >= 20     # Laborer or broke = looking
	var ask := float(od["salary"])
	ask = maxf(ask, round(cur * 0.45))
	if "greedy" in traits:
		ask *= 1.3
	if "loyal" in traits or "lazy" in traits:
		ask *= 0.9
	if employed:
		ask *= 1.2
	var p := {"row": row, "name": WorldSim.person_name(row), "occ": occ, "traits": traits, "skills": skills,
		"ambition": Fol.AMBITIONS[r.randi() % Fol.AMBITIONS.size()], "ask": maxi(1, int(ceil(ask))),
		"employed": employed, "needy": money < 20, "home": int(WorldSim.home[row])}
	_prof[row] = p
	return p


func is_recruited(row: int) -> bool:
	return _by_row.has(row)


func fid_of(row: int) -> String:
	return String(_by_row.get(row, ""))


func _alive(row: int) -> bool:
	return row >= 0 and row < WorldSim.health.size() and WorldSim.health[row] != 0


# --------------------------------------------------------------- terms and evaluation

static func make_terms(wage: int, duty := "labor", days := 0, housing := false) -> Dictionary:
	var dd: Dictionary = DUTIES.get(duty, DUTIES["labor"])
	return {"w": wage, "d": duty, "n": days, "h": 1 if housing else 0, "x": float(dd["x"])}


func _push(reasons: Array, code: String, text: String, delta: float) -> void:
	reasons.append({"code": code, "text": text, "delta": snappedf(delta, 0.1)})


## Willingness of person `row` for `terms`. env: {trust -100..100 (their opinion of you), reputation 0..100,
## referral bool}. Returns {score, willing, verdict accept|counter|reject, counter terms, reasons, line}.
func evaluate(row: int, terms: Dictionary, env := {}) -> Dictionary:
	var p := profile(row)
	var tr: Array = p["traits"]
	var reasons: Array = []
	var score := 30.0
	var wage := float(terms.get("w", 0))
	var ask := float(p["ask"])
	var ratio := wage / maxf(1.0, ask)
	var pay_d := clampf((ratio - 1.0) * 60.0, -40.0, 30.0)
	if "greedy" in tr:
		pay_d += clampf((ratio - 1.0) * 25.0, -20.0, 12.0)
	score += 20.0 + pay_d
	_push(reasons, "pay_low" if pay_d < -2.0 else "pay_ok", "The pay is too low for what I need." if pay_d < -2.0 else "The pay is fair.", pay_d)
	if bool(p["needy"]):
		score += 12.0
		_push(reasons, "needy", "I need the work.", 12.0)
	elif bool(p["employed"]):
		score -= 12.0
		_push(reasons, "employed", "I have steady work already.", -12.0)
	var trust := float(env.get("trust", 0.0))
	var trd := clampf(trust * 0.25, -20.0, 20.0)
	if absf(trd) >= 1.0:
		score += trd
		_push(reasons, "trust_hi" if trd > 0.0 else "trust_low",
			"I think well of you." if trd > 0.0 else "I do not trust you with my living.", trd)
	var rep_d := clampf((float(env.get("reputation", 30.0)) - 30.0) * 0.2, -8.0, 10.0)
	if absf(rep_d) >= 1.0:
		score += rep_d
		_push(reasons, "rep_hi" if rep_d > 0.0 else "rep_low",
			"Folk speak well of you." if rep_d > 0.0 else "Folk say little good of you.", rep_d)
	var danger := float(terms.get("x", 0.0))
	var dmul := 1.0
	if "cautious" in tr:
		dmul = 1.5
	elif "brave" in tr:
		dmul = 0.5
	var dan_d := -danger * 32.0 * dmul
	if dan_d < -3.0:
		_push(reasons, "danger", "That sounds like a way to get killed.", dan_d)
	if int(terms.get("h", 0)) == 1:
		score += 7.0
		_push(reasons, "housing", "A roof is worth something.", 7.0)
	var days := int(terms.get("n", 0))
	if days >= 60 and ("stubborn" in tr or p["ambition"] in INDEP_AMBITIONS):
		score -= 5.0
		_push(reasons, "bound", "I do not want to be bound that long.", -5.0)
	elif days >= 30 and ("cautious" in tr or "loyal" in tr):
		score += 5.0
		_push(reasons, "secure", "A fixed term is security.", 5.0)
	var duty: String = String(terms.get("d", "labor"))
	var dd: Dictionary = DUTIES.get(duty, DUTIES["labor"])
	var fit := 0.0
	for s in dd["skills"]:
		fit = maxf(fit, float(p["skills"].get(s, 0.0)))
	if fit >= 0.6:
		score += 6.0
		_push(reasons, "fit", "It is work I know.", 6.0)
	elif fit < 0.2:
		score -= 5.0
		_push(reasons, "unfit", "I know nothing of that work.", -5.0)
	var amb: String = p["ambition"]
	if (amb == "earn a captaincy" and duty in ["guard", "campaign"]) or (amb == "avenge a burned home" and duty == "campaign") \
			or (amb == "win renown" and duty in ["escort", "campaign"]):
		score += 8.0
		_push(reasons, "goal", "It could get me what I want in life.", 8.0)
	if (amb == "save for a farm" or amb == "repay a debt") and ratio >= 1.1:
		score += 5.0
		_push(reasons, "goal_pay", "The coin would help my plans.", 5.0)
	if "lazy" in tr and duty == "labor":
		score -= 6.0
		_push(reasons, "lazy", "Honest labour is not for me.", -6.0)
	if bool(env.get("referral", false)):
		score += 10.0
		_push(reasons, "referral", "A friend vouched for you.", 10.0)
	score += dan_d
	reasons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["delta"]) > absf(b["delta"]))
	var res := {"score": snappedf(score, 0.1), "reasons": reasons, "willing": score >= THRESHOLD, "name": p["name"]}
	if score >= THRESHOLD:
		res["verdict"] = "accept"
		res["counter"] = terms.duplicate()
		res["line"] = "\"Aye, I'll take it.\""
	else:
		var gap := THRESHOLD - score + 1.0
		var per_gold := 60.0 / maxf(1.0, ask) * (1.4 if "greedy" in tr else 1.0)
		var extra := int(ceil(gap / per_gold))
		if score >= 32.0 and wage + extra <= ask * 2.0:
			var ct := terms.duplicate()
			ct["w"] = int(wage) + extra
			res["verdict"] = "counter"
			res["counter"] = ct
			res["line"] = "\"Make it %d gold a day and we have a bargain.\"" % ct["w"]
		else:
			res["verdict"] = "reject"
			res["counter"] = {}
			var why := "Not for me."
			for rs: Dictionary in reasons:
				if float(rs["delta"]) < 0.0:
					why = String(rs["text"])
					break
			res["line"] = "\"%s\"" % why
	return res


## Reasons in plain words, strongest first (for the talk sheet).
func reason_lines(ev: Dictionary, limit := 3) -> Array:
	var out: Array = []
	for r: Dictionary in ev.get("reasons", []):
		out.append("%s %s" % ["+" if float(r["delta"]) >= 0.0 else "-", r["text"]])
		if out.size() >= limit:
			break
	return out


# --------------------------------------------------------------- contracts and signing

func contract(cid: String) -> Dictionary:
	return _c.get(cid, {})


func contract_of(fid: String) -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	return _c.get(e.get("c", ""), {}) if not e.is_empty() else {}


func _hist(c: Dictionary, ev: String) -> void:
	var h: Array = c["h"]
	h.append([_day, ev])
	while h.size() > HISTORY_MAX:
		h.pop_front()


## Signs `row` on `terms` into a chain. Returns {ok, cid, fid, line}. The person is evaluated again here, so a
## stale offer cannot buy anyone.
func engage(row: int, terms: Dictionary, chain := "personal", org := "", env := {}) -> Dictionary:
	if chain not in ["personal", "org", "property"]:
		return {"ok": false, "line": "No such post."}
	if not _alive(row) or _by_row.has(row):
		return {"ok": false, "line": "They are not available."}
	var ev := evaluate(row, terms, env)
	if ev["verdict"] != "accept":
		return {"ok": false, "line": ev["line"], "eval": ev}
	var fol := _fol()
	var p := profile(row)
	var fid: String = fol.candidate(p["occ"], "rc%d" % row, "s%d" % int(p["home"]))
	var f: Dictionary = fol.get_follower(fid)
	f["name"] = p["name"]
	f["traits"] = p["traits"].duplicate()
	f["skills"] = p["skills"].duplicate()
	f["ambition"] = p["ambition"]
	f.erase("values")
	fol._expand(f)                        # value axes follow the person's own traits
	f["status"] = "present"
	f["permanent"] = true
	f["salary"] = int(terms["w"])
	f["joined_day"] = _day
	f["person"] = row
	var cid := "k%d" % _next_c
	_next_c += 1
	var t := {"w": int(terms["w"]), "d": String(terms.get("d", "labor")), "n": int(terms.get("n", 0)),
		"h": int(terms.get("h", 0)), "x": snappedf(float(terms.get("x", 0.0)), 0.01)}
	var c := {"id": cid, "fid": fid, "chain": chain, "org": org, "t": t, "st": "active", "s": _day,
		"e": (_day + int(t["n"])) if int(t["n"]) > 0 else 0, "h": [[_day, "signed"]]}
	_c[cid] = c
	_r[fid] = {"c": cid, "chain": chain, "org": org, "tr": clampf(50.0 + float(env.get("trust", 0.0)) * 0.3, 0.0, 100.0),
		"ol": 55.0 if chain == "org" else 0.0, "m": 0.7, "unp": 0, "low": 0, "dm": 0, "rn": 0, "g": "", "rf": 0, "hb": 0.0, "mgr": ""}
	_by_row[row] = fid
	Events.log_to(hub, "contract", "ss:%d" % int(p["home"]), ["ws:%d" % row, "rc:" + cid], "engage_" + chain, "%s signed on (%dg, %s)" % [p["name"], int(t["w"]), t["d"]], 2)
	return {"ok": true, "cid": cid, "fid": fid, "line": "%s joins you." % p["name"]}


func get_entry(fid: String) -> Dictionary:
	return _r.get(fid, {})


func _active(fid: String) -> bool:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty():
		return false
	var f: Dictionary = _fol().get_follower(fid)
	return not f.is_empty() and f["status"] in Fol.MEMBER_STATES and _c.get(e["c"], {}).get("st", "") == "active"


func active_ids() -> Array:
	var out: Array = []
	for fid: String in _sorted_ids():
		if _active(fid):
			out.append(fid)
	return out


## Roster ids in numeric order; rebuilt only when someone was added (entries are never removed).
func _sorted_ids() -> Array:
	if _ids.size() != _r.size():
		_ids = _r.keys()
		_ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	return _ids


func _end(fid: String, st: String, ev: String) -> void:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty():
		return
	var c: Dictionary = _c[e["c"]]
	c["st"] = st
	_hist(c, ev)
	Events.log_to(hub, "contract", "", ["fo:" + fid, "rc:" + String(c["id"])], st, "contract " + st, 2)
	var f: Dictionary = _fol().get_follower(fid)
	if not f.is_empty():
		f["status"] = "left"
	e["g"] = ""
	e["mgr"] = ""
	for gid in _g:
		if _g[gid]["mgr"] == fid:
			_g[gid]["mgr"] = ""
	# The person is free again (they may reapply later); the character stays in followers.gd as "left".
	var row := int(f.get("person", -1))
	if row >= 0 and _by_row.get(row, "") == fid:
		_by_row.erase(row)


# --------------------------------------------------------------- chains and resigning

func members(chain := "", org := "") -> Array:
	var out: Array = []
	for fid in active_ids():
		var e: Dictionary = _r[fid]
		if (chain == "" or e["chain"] == chain) and (org == "" or e["org"] == org):
			out.append(fid)
	return out


## You resign from organization `org` (army, guild). Org members stop being yours; personal followers stay;
## property employees stay with their property. Returns counts.
func resign(org: String) -> Dictionary:
	var lost := 0
	var kept := members("personal").size()
	for fid in members("org", org):
		_end(fid, "ended", "resigned")
		lost += 1
	return {"lost_org": lost, "kept_personal": kept, "property_stay": members("property").size()}


## Sell or lose a property: its employees stay with the property (they leave your books).
func release_property(ref: String) -> int:
	var n := 0
	for gid in _g:
		if _g[gid]["ref"] == ref:
			for fid in members("property"):
				if _r[fid]["g"] == gid:
					_end(fid, "ended", "property sold")
					n += 1
	return n


func roster(chain := "") -> Array:
	var out: Array = []
	var fol := _fol()
	for fid in members(chain):
		var e: Dictionary = _r[fid]
		var c: Dictionary = _c[e["c"]]
		var f: Dictionary = fol.get_follower(fid)
		out.append({"fid": fid, "name": f["name"], "chain": e["chain"], "org": e["org"], "wage": int(c["t"]["w"]), "duty": c["t"]["d"],
			"morale": e["m"], "trust": e["tr"], "org_loyalty": e["ol"], "days_left": (int(c["e"]) - _day) if int(c["e"]) > 0 else -1,
			"demand": int(e["dm"]), "group": e["g"]})
	return out


# --------------------------------------------------------------- orders

## Will `fid` carry out an order? kind: normal | dangerous | illegal | suicidal.
func give_order(fid: String, kind: String) -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	var f: Dictionary = _fol().get_follower(fid) if not e.is_empty() else {}
	if e.is_empty() or f.is_empty() or not _active(fid):
		return {"obeys": false, "line": ""}
	var tr: Array = f["traits"]
	var trust: float = e["tr"]
	var ok := true
	var line := ""
	match kind:
		"illegal":
			var bent: bool = "greedy" in tr or "ruthless" in tr
			var sworn: bool = e["chain"] == "personal" and trust >= 85.0 and not ("honorable" in tr)
			ok = (bent and trust >= 40.0) or sworn
			if e["chain"] == "org" and not ("ruthless" in tr and trust >= 70.0):
				ok = false
			line = "\"That is against the law, and I will not hang for you.\""
			if "honorable" in tr:
				line = "\"I gave my word to serve, not to break the law.\""
		"suicidal":
			ok = ("brave" in tr and trust >= 75.0) or float(e["ol"]) >= 90.0 or trust >= 95.0
			line = "\"That is a death sentence. Find someone else to throw away.\""
		"dangerous":
			ok = float(e["m"]) >= 0.35 and not ("cautious" in tr and trust < 40.0)
			line = "\"Not like this. The people are not ready for it.\""
	if ok:
		return {"obeys": true, "line": "%s: \"As you say.\"" % f["name"]}
	e["rf"] = int(e["rf"]) + 1
	e["tr"] = maxf(0.0, trust - 1.0)
	return {"obeys": false, "line": "%s: %s" % [f["name"], line]}


# --------------------------------------------------------------- orders (follow / wait / home / work)

func groups() -> Array:
	var out: Array = []
	var ids := _g.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	for gid: String in ids:
		out.append({"id": gid, "name": _g[gid]["name"], "kind": _g[gid]["kind"], "ref": _g[gid]["ref"]})
	return out


## What `fid` is doing now: their standing order, or the default for their post. Property employees and
## labourers go to work (at their group) or home; guards, escorts, scouts and campaigners follow the player.
func effective_order(fid: String) -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	var f: Dictionary = _fol().get_follower(fid) if not e.is_empty() else {}
	if e.is_empty() or f.is_empty():
		return {"order": "home", "arg": ""}
	var o := String(f.get("order", ""))
	if o != "":
		var arg := String(f.get("order_arg", ""))
		if o == "work" and arg == "":
			arg = String(e["g"])
		return {"order": o, "arg": arg}
	var duty := String(_c[e["c"]]["t"]["d"])
	if e["chain"] == "personal" and duty in ["guard", "escort", "scout", "campaign"]:
		return {"order": "follow", "arg": ""}
	if String(e["g"]) != "":
		return {"order": "work", "arg": String(e["g"])}
	return {"order": "home", "arg": ""}


## Give a standing order. "work" needs a group (property or squad) to work at: `arg` is its id, or the group they
## are assigned to. Returns {ok, line}; a worker may refuse a second post, and an unhappy one a long march.
func set_order(fid: String, order: String, arg := "") -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	var f: Dictionary = _fol().get_follower(fid) if not e.is_empty() else {}
	if e.is_empty() or f.is_empty() or not _active(fid):
		return {"ok": false, "line": ""}
	if order not in ORDERS:
		return {"ok": false, "line": ""}
	var nm: String = f["name"]
	if order == "follow" and e["chain"] == "property":
		return {"ok": false, "line": "%s: \"I work for the %s, not for you on the road.\"" % [nm, "estate"]}
	if order == "work":
		var gid := arg if arg != "" else String(e["g"])
		if gid == "" or not _g.has(gid):
			return {"ok": false, "line": "%s: \"Work where? Give me a post first.\"" % nm}
		arg = gid
		_r[fid]["g"] = gid
	else:
		arg = ""
	var ob := give_order(fid, "dangerous" if order == "follow" and String(_c[e["c"]]["t"]["d"]) == "campaign" else "normal")
	if not bool(ob["obeys"]):
		return {"ok": false, "line": String(ob["line"])}
	f["order"] = order
	f["order_arg"] = arg
	var says := {"follow": "I am right behind you.", "wait": "I will hold here.", "home": "I will see to things at home.",
		"work": "I will get to work at %s." % String(_g.get(arg, {}).get("name", "the post"))}
	return {"ok": true, "line": "%s: \"%s\"" % [nm, says[order]]}


## Drops the contracts, roster entries and links of followers that followers.gd pruned (old "left" records).
func _forget_gone() -> void:
	var fol := _fol()
	if fol == null or _r.is_empty():
		return
	var dead: Array = []
	for fid: String in _r:
		if fol.get_follower(fid).is_empty():
			dead.append(fid)
	for fid: String in dead:
		var cid: String = _r[fid]["c"]
		_c.erase(cid)
		_r.erase(fid)
		for row: int in _by_row.keys():
			if _by_row[row] == fid:
				_by_row.erase(row)
		for gid: String in _g:
			if _g[gid]["mgr"] == fid:
				_g[gid]["mgr"] = ""
	_ids = []


# --------------------------------------------------------------- raises, renewals

func grant_raise(fid: String) -> bool:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty() or int(e["dm"]) <= 0 or not _active(fid):
		return false
	var c: Dictionary = _c[e["c"]]
	c["t"]["w"] = int(e["dm"])
	_fol().get_follower(fid)["salary"] = int(e["dm"])
	_hist(c, "raise")
	e["dm"] = 0
	e["tr"] = minf(100.0, float(e["tr"]) + 4.0)
	e["m"] = minf(1.0, float(e["m"]) + 0.15)
	return true


## A raise you offer unasked (or the one they demanded when `dm` is set). Returns {ok, wage, line}.
func offer_raise(fid: String, by := 1) -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty() or not _active(fid):
		return {"ok": false, "wage": 0, "line": ""}
	if int(e["dm"]) > 0 and grant_raise(fid):
		return {"ok": true, "wage": int(_c[e["c"]]["t"]["w"]), "line": "%s accepts the raise." % _fol().get_follower(fid)["name"]}
	var c: Dictionary = _c[e["c"]]
	c["t"]["w"] = int(c["t"]["w"]) + maxi(1, by)
	_fol().get_follower(fid)["salary"] = int(c["t"]["w"])
	_hist(c, "raise")
	e["tr"] = minf(100.0, float(e["tr"]) + 2.0)
	e["m"] = minf(1.0, float(e["m"]) + 0.08)
	return {"ok": true, "wage": int(c["t"]["w"]), "line": "%s: \"That is generous.\" (%dg a day now)" % [_fol().get_follower(fid)["name"], int(c["t"]["w"])]}


## Let someone go. Their unpaid wages are settled from `gold` first (through the ledger); a dismissal with wages
## owed and not paid costs trust with the rest. Returns {ok, paid, line}.
func dismiss(fid: String, gold := 0) -> Dictionary:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty() or not _active(fid):
		return {"ok": false, "paid": 0, "line": ""}
	var fol := _fol()
	var f: Dictionary = fol.get_follower(fid)
	var owed := int(f["owed"])
	var paid := mini(owed, maxi(0, gold))
	if paid > 0:
		_pending -= paid
		fol.pay(fid, paid)
	var short := owed - paid
	_end(fid, "ended", "dismissed")
	_set_lost_order(f)
	var line := "%s takes the news with a nod and goes." % f["name"]
	if paid > 0:
		line += " (%dg of back pay settled)" % paid
	if short > 0:
		line += " They are owed %dg." % short
	return {"ok": true, "paid": paid, "line": line}


func _set_lost_order(f: Dictionary) -> void:
	f["order"] = ""
	f["order_arg"] = ""


func refuse_raise(fid: String) -> void:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty():
		return
	e["dm"] = 0
	e["tr"] = maxf(0.0, float(e["tr"]) - 5.0)
	e["m"] = maxf(0.0, float(e["m"]) - 0.1)
	e["rf"] = int(e["rf"]) + 1


## Accept the renewal their contract offered (wage `rn`), for `days` more days.
func renew(fid: String, days := 30) -> bool:
	var e: Dictionary = _r.get(fid, {})
	if e.is_empty() or not _active(fid):
		return false
	var c: Dictionary = _c[e["c"]]
	var w: int = int(e["rn"]) if int(e["rn"]) > 0 else int(c["t"]["w"])
	c["t"]["w"] = w
	c["t"]["n"] = days
	c["e"] = _day + days
	_fol().get_follower(fid)["salary"] = w
	_hist(c, "renewed")
	e["rn"] = 0
	e["tr"] = minf(100.0, float(e["tr"]) + 2.0)
	return true


func _ask_now(f: Dictionary) -> int:
	var top := 0.0
	for s in f["skills"]:
		top = maxf(top, float(f["skills"][s]))
	var base: int = int(Fol.OCCUPATIONS[f["occupation"]]["salary"])
	return maxi(1, int(ceil(base * (0.7 + top))))


# --------------------------------------------------------------- notices

## Post a vacancy at a settlement's inn / market / guild hall. Returns {ok, nid, line}.
func post_notice(sid: int, kind: String, terms: Dictionary, occ := "", days := 10, gid := "", rep := 30.0) -> Dictionary:
	if kind not in ["inn", "market", "guild"] or sid < 0 or sid >= WorldSim.ranges.size():
		return {"ok": false, "line": "There is no place to post it."}
	var nid := "n%d" % _next_n
	_next_n += 1
	_n[nid] = {"id": nid, "sid": sid, "kind": kind, "t": terms.duplicate(), "occ": occ, "post": _day, "exp": _day + days,
		"app": [], "mx": 8, "g": gid, "rep": rep}
	_pending -= NOTICE_FEE
	return {"ok": true, "nid": nid, "line": "Your notice is up at the %s." % kind}


func notices() -> Array:
	var out: Array = []
	var ids := _n.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	for id in ids:
		out.append(_n[id])
	return out


func applicants(nid: String) -> Array:
	var out: Array = []
	var n: Dictionary = _n.get(nid, {})
	for row: int in n.get("app", []):
		var p := profile(row)
		out.append({"row": row, "name": p["name"], "occ": p["occ"], "ask": p["ask"], "traits": p["traits"]})
	return out


## Hire one applicant at the notice's terms (or `terms` you pass). If they counter, "eval" carries it.
func hire_applicant(nid: String, row: int, terms := {}, env := {}) -> Dictionary:
	var n: Dictionary = _n.get(nid, {})
	if n.is_empty() or not (n["app"] as Array).has(row):
		return {"ok": false, "line": "They have gone."}
	var t: Dictionary = terms if not terms.is_empty() else n["t"]
	var gid := String(n["g"])
	var res := engage(row, t, "personal" if gid == "" else "property", "", env)
	if res["ok"]:
		(n["app"] as Array).erase(row)
		if gid != "":
			_r[res["fid"]]["g"] = gid
	return res


func _draw_applicants(n: Dictionary, d: int) -> void:
	if d >= int(n["exp"]) or (n["app"] as Array).size() >= int(n["mx"]):
		return
	var rg: Vector2i = WorldSim.ranges[int(n["sid"])]
	var count := rg.y - rg.x
	if count <= 0:
		return
	for k in NOTICE_DRAWS:
		var row := rg.x + int(posmod(hash([WorldSim.SEED, "nb", n["id"], d, k]), count))
		if not _alive(row) or _by_row.has(row) or (n["app"] as Array).has(row):
			continue
		var p := profile(row)
		if String(n["occ"]) != "" and p["occ"] != n["occ"]:
			continue
		var ev := evaluate(row, n["t"], {"reputation": float(n.get("rep", 30.0))})
		if float(ev["score"]) >= THRESHOLD - 8.0:      # near-willing people apply and haggle
			(n["app"] as Array).append(row)
			if (n["app"] as Array).size() >= int(n["mx"]):
				break


# --------------------------------------------------------------- groups and managers

## A group the player runs: a property or a squad. `base` is gold produced per worker per day at full competence.
func create_group(kind: String, ref: String, gname: String, base := 6.0) -> String:
	var gid := "g%d" % _next_g
	_next_g += 1
	_g[gid] = {"id": gid, "kind": kind, "ref": ref, "name": gname, "mgr": "", "role": "", "mode": "manual", "bud": 0.0, "cap": 0.0,
		"base": base, "ov": 0.0, "sk": 0.0, "skf": 0.0, "out": 0.0}
	return gid


func group(gid: String) -> Dictionary:
	return _g.get(gid, {})


func assign_to_group(fid: String, gid: String) -> bool:
	if not _r.has(fid) or not _g.has(gid):
		return false
	_r[fid]["g"] = gid
	return true


func set_mode(gid: String, mode: String) -> bool:
	if not _g.has(gid) or mode not in MODES:
		return false
	_g[gid]["mode"] = mode
	return true


## Put gold into a group's budget (leaves the purse through the ledger).
func fund(gid: String, amount: int) -> bool:
	if not _g.has(gid) or amount <= 0:
		return false
	_g[gid]["bud"] = float(_g[gid]["bud"]) + amount
	_pending -= amount
	return true


func appoint_manager(fid: String, gid: String, role := "steward", daily_budget := 10.0) -> Dictionary:
	if not _g.has(gid) or not _active(fid):
		return {"ok": false, "line": "They cannot take the post."}
	var f: Dictionary = _fol().get_follower(fid)
	var g: Dictionary = _g[gid]
	g["mgr"] = fid
	g["role"] = role
	g["cap"] = daily_budget
	if g["mode"] == "manual":
		g["mode"] = "delegated"
	_r[fid]["g"] = gid
	_r[fid]["mgr"] = role
	_r[fid]["tr"] = minf(100.0, float(_r[fid]["tr"]) + 3.0)    # promotion pleases
	return {"ok": true, "line": "%s is now %s of %s." % [f["name"], role, g["name"]]}


func competence(fid: String) -> float:
	var f: Dictionary = _fol().get_follower(fid)
	var e: Dictionary = _r.get(fid, {})
	if f.is_empty() or e.is_empty():
		return 0.0
	var keys: Array = ["command", "tactics", "combat"] if e["mgr"] == "captain" else ["building", "speech", "repair", "command"]
	var best: Array = []
	for s in f["skills"]:
		best.append(float(f["skills"][s]) * (1.0 if s in keys else 0.6))
	best.sort()
	best.reverse()
	var tot := 0.0
	var n := mini(2, best.size())
	for i in n:
		tot += float(best[i])
	var tenure := minf(0.2, float(_day - int(f["joined_day"])) / 300.0)
	return clampf(tot / maxf(1.0, n) + tenure, 0.0, 1.0)


func honesty(fid: String) -> float:
	var f: Dictionary = _fol().get_follower(fid)
	var e: Dictionary = _r.get(fid, {})
	if f.is_empty() or e.is_empty():
		return 0.0
	var h := 0.55
	var tr: Array = f["traits"]
	if "honorable" in tr:
		h += 0.3
	if "loyal" in tr:
		h += 0.15
	if "merciful" in tr:
		h += 0.05
	if "greedy" in tr:
		h -= 0.4
	if "ruthless" in tr:
		h -= 0.15
	h += (float(e["tr"]) - 50.0) / 200.0 + float(e["hb"])
	return clampf(h, 0.0, 1.0)


## The player checks the books. Reveals what the manager skimmed since the last audit, and raises oversight.
func audit(gid: String) -> Dictionary:
	var g: Dictionary = _g.get(gid, {})
	if g.is_empty() or String(g["mgr"]) == "":
		return {"ok": false, "found": 0, "line": "There is no manager to audit."}
	var f: Dictionary = _fol().get_follower(g["mgr"])
	var found := int(round(float(g["sk"])))
	g["skf"] = float(g["skf"]) + float(g["sk"])
	g["sk"] = 0.0
	g["ov"] = 0.7
	var e: Dictionary = _r[g["mgr"]]
	var line := ""
	if found > 0:
		e["tr"] = maxf(0.0, float(e["tr"]) - 8.0)
		line = "The books are short by %d gold. %s has been skimming." % [found, f["name"]]
	else:
		line = "The books balance. %s is honest, or careful." % f["name"]
	return {"ok": true, "found": found, "line": line, "honesty": honesty(g["mgr"]), "competence": competence(g["mgr"])}


## Warn a skimming manager: honesty improves for a while.
func warn_manager(gid: String) -> bool:
	var g: Dictionary = _g.get(gid, {})
	if g.is_empty() or String(g["mgr"]) == "":
		return false
	_r[g["mgr"]]["hb"] = 0.2
	return true


func dismiss_manager(gid: String) -> bool:
	var g: Dictionary = _g.get(gid, {})
	if g.is_empty() or String(g["mgr"]) == "":
		return false
	_r[g["mgr"]]["mgr"] = ""
	g["mgr"] = ""
	g["mode"] = "manual"
	return true


func _group_day(gid: String, days: float) -> void:
	var g: Dictionary = _g[gid]
	var n := 0
	for fid in _r:
		if _r[fid]["g"] == gid and _active(fid):
			n += 1
	g["out"] = 0.0
	if n == 0:
		return
	var base: float = float(g["base"]) * n * days
	var mgr := String(g["mgr"])
	if mgr == "" or not _active(mgr) or g["mode"] == "manual":
		var out_m := base * 0.6
		_pend_f += out_m
		g["out"] = out_m
		return
	var comp := competence(mgr)
	var hon := honesty(mgr)
	var mult := 0.5 + comp                    # below 1 when incompetent: output is lost
	var need := base * 0.4
	var spend := minf(float(g["cap"]) * days, maxf(0.0, float(g["bud"])))
	var rate := clampf(0.5 - hon, 0.0, 0.5) * (1.0 - float(g["ov"]))
	var skim := spend * rate
	g["bud"] = float(g["bud"]) - spend
	g["sk"] = float(g["sk"]) + skim
	var supplied := minf(1.0, (spend - skim) / maxf(0.01, need))
	var out := base * mult * (0.5 + 0.5 * supplied)
	g["out"] = out
	if g["mode"] == "autonomous":
		g["bud"] = float(g["bud"]) + out * 0.5      # reinvests half
		_pend_f += out * 0.5
	else:
		_pend_f += out
	g["ov"] = float(g["ov"]) * pow(0.95, days)
	var e: Dictionary = _r[mgr]
	e["hb"] = maxf(0.0, float(e["hb"]) - 0.005 * days)


# --------------------------------------------------------------- the day, in chunks

func take_pending_gold() -> int:
	var whole := int(_pend_f)
	_pend_f -= whole
	var t := _pending + whole
	_pending = 0
	return t


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	return [_chunk_pay.bind(day, ctx, 0), _chunk_pay.bind(day, ctx, 1), _chunk_agency.bind(day), _chunk_growth.bind(day), _chunk_groups.bind(day)]


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## Wages and morale. Followers.gd accrued the wage as "owed"; the purse pays it (or the group budget / the org).
func _chunk_pay(day: int, ctx: Dictionary, part: int) -> Array:
	_day = day
	var fol := _fol()
	if part == 0:
		_forget_gone()
		_avail = int(ctx.get("gold", 0)) + _pending
	var avail := _avail
	var ids := active_ids()
	for k in range(part, ids.size(), 2):         # two halves, two pump jobs
		var fid: String = ids[k]
		var e: Dictionary = _r[fid]
		var f: Dictionary = fol.get_follower(fid)
		var c: Dictionary = _c[e["c"]]
		var owed := int(f["owed"])
		var wage := maxi(1, int(c["t"]["w"]))
		if owed > 0:
			var paid := 0
			match String(e["chain"]):
				"personal":
					paid = mini(owed, maxi(0, avail))
					paid = (paid / wage) * wage if paid < owed else paid     # whole days only
					avail -= paid
					_pending -= paid
				"org":
					paid = owed                                            # the organization pays its own
				_:
					var g: Dictionary = _g.get(e["g"], {})
					var have := int(g.get("bud", 0.0)) if not g.is_empty() else 0
					paid = mini(owed, have)
					paid = (paid / wage) * wage if paid < owed else paid
					if not g.is_empty():
						g["bud"] = float(g["bud"]) - paid
			if paid > 0:
				fol.pay(fid, paid)
			_ledger_wage(fid, e, paid, owed)
			e["unp"] = int(e["unp"]) + 1 if int(f["owed"]) >= wage else 0
			_ledger_short(fid, e, owed - paid, wage)
		else:
			e["unp"] = 0
		# Morale: pay, conditions, danger, trust.
		var n: Dictionary = f["needs"]
		var bravery := 1.0
		if "brave" in f["traits"]:
			bravery = 0.6
		elif "cautious" in f["traits"]:
			bravery = 1.4
		var target := 0.35 * float(n["pay"]) + 0.2 * (1.0 if int(c["t"]["h"]) == 1 else 0.4) \
			+ 0.2 * (float(n["food"]) + float(n["rest"])) * 0.5 + 0.25 * (1.0 - clampf(float(c["t"]["x"]) * bravery, 0.0, 1.0)) \
			+ 0.1 * (float(e["tr"]) - 50.0) / 50.0
		e["m"] = clampf(float(e["m"]) + (target - float(e["m"])) * 0.3, 0.0, 1.0)
		if e["chain"] == "org":
			e["ol"] = clampf(float(e["ol"]) + (30.0 + 60.0 * float(n["pay"]) - float(e["ol"])) * 0.05, 0.0, 100.0)
		f["morale"] = e["m"]
		e["low"] = int(e["low"]) + 1 if float(e["m"]) < 0.25 else 0
	_avail = avail
	return []


## Wages stay on recruitment's own path (the purse / group budget pays); the ledger only records the flow in its weekly summary.
func _ledger_wage(fid: String, e: Dictionary, paid: int, _owed: int) -> void:
	var lg: Variant = hub.mod("ledger") if hub != null else null
	if lg == null or paid <= 0:
		return
	var payer := "player"
	match String(e["chain"]):
		"org":
			payer = "org:" + String(e.get("org", ""))
		"personal":
			payer = "player"
		_:
			payer = "gb:" + String(e["g"])
	lg.note(payer, "fo:" + fid, "wage", paid)


## A follower the purse could not pay climbs the ledger's shortage ladder (no gold moves).
func _ledger_short(fid: String, e: Dictionary, short: int, wage: int) -> void:
	var lg: Variant = hub.mod("ledger") if hub != null else null
	if lg == null or short <= 0 or String(e["chain"]) == "org":
		return
	lg.report_arrears("player" if String(e["chain"]) == "personal" else "gb:" + String(e["g"]), "fo:" + fid, "wage", short, maxi(1, int(e["unp"])), _day)


## Ledger departures whose payee is one of our followers (a posted wage obligation, or the arrears above): they resign here.
func _ledger_departures() -> Array:
	var out: Array = []
	var lg: Variant = hub.mod("ledger") if hub != null else null
	if lg == null:
		return out
	var mine := func(dep: Dictionary) -> bool:
		var py := String(dep["payee"])
		return py.begins_with("fo:") and _r.has(py.substr(3))
	for dep: Dictionary in lg.take_departures(mine):
		var fid := String(dep["payee"]).substr(3)
		var c: Dictionary = _c.get(String((_r[fid] as Dictionary).get("c", "")), {})
		if c.is_empty() or c["st"] != "active":
			continue
		var nm := String(_fol().get_follower(fid).get("name", fid))
		_end(fid, "broken", "%s unpaid" % dep["why"])
		var w: Variant = hub.mod("will")
		if w != null:
			w.on_event(fid, "unpaid", 1.0)
		out.append("%s %s: unpaid wages." % [nm, "resigns" if dep["why"] == "resign" else "walks out"])
	return out


func _chunk_agency(day: int) -> Array:
	var out: Array = _ledger_departures()
	var fol := _fol()
	for fid: String in _sorted_ids():
		var e: Dictionary = _r[fid]
		var c: Dictionary = _c[e["c"]]
		if c["st"] != "active":
			continue
		var f: Dictionary = fol.get_follower(fid)
		if f.is_empty() or f["status"] == "left":
			_end(fid, "broken", "left")
			continue
		if f["status"] not in Fol.MEMBER_STATES:
			continue
		var nm: String = f["name"]
		var pay_w := int(c["t"]["w"])
		# Desertion: unpaid or beaten down.
		if int(e["unp"]) >= WAGE_DAYS_DESERT:
			var days_unpaid := int(e["unp"])
			_end(fid, "broken", "deserted unpaid")
			out.append("%s has deserted: %d days without pay." % [nm, days_unpaid])
			continue
		if int(e["low"]) >= 2:
			var scared := float(c["t"]["x"]) > 0.4
			_end(fid, "broken", "deserted")
			out.append("%s has deserted, %s." % [nm, "afraid for their life" if scared else "worn out by it all"])
			continue
		# Contract end.
		var end_day := int(c["e"])
		if end_day > 0:
			if day >= end_day:
				var grp: Dictionary = _g.get(e["g"], {})
				if not grp.is_empty() and grp["mode"] == "autonomous" and float(e["m"]) >= 0.4:
					renew(fid, 30)
					out.append("%s's contract was renewed by the manager." % nm)
				else:
					_end(fid, "expired", "contract ended")
					out.append("%s leaves: the contract has ended." % nm)
					continue
			elif day >= end_day - 3 and int(e["rn"]) == 0:
				e["rn"] = maxi(pay_w, _ask_now(f))
				out.append("%s's contract ends in %d days; they would stay for %d gold a day." % [nm, end_day - day, int(e["rn"])])
		# Raise demand: skills grew past the pay, or pay is the grievance.
		if int(e["dm"]) == 0 and day > int(f["joined_day"]) + 5:
			var ask_now := _ask_now(f)
			if ask_now > pay_w * 1.25 or (float(f["needs"]["pay"]) < 0.5 and float(e["m"]) < 0.45 and int(e["unp"]) == 0):
				e["dm"] = maxi(pay_w + 1, ask_now)
				out.append("%s demands a raise to %d gold a day." % [nm, int(e["dm"])])
		elif int(e["dm"]) > 0 and day % 10 == 0:
			e["m"] = maxf(0.0, float(e["m"]) - 0.05)      # an unanswered demand festers
	return out


func _chunk_growth(day: int) -> Array:
	var out: Array = []
	var fol := _fol()
	for fid in active_ids():
		var e: Dictionary = _r[fid]
		var c: Dictionary = _c[e["c"]]
		var f: Dictionary = fol.get_follower(fid)
		# Skill grows with duty.
		var dd: Dictionary = DUTIES.get(c["t"]["d"], DUTIES["labor"])
		for s in dd["skills"]:
			if f["skills"].has(s):
				f["skills"][s] = minf(1.0, float(f["skills"][s]) + 0.004)
				break
		var top := 0.0
		for s in f["skills"]:
			top = maxf(top, float(f["skills"][s]))
		# Independence (the rng is only built when the cheap conditions hold).
		if top >= 0.85 and f["ambition"] in INDEP_AMBITIONS and day - int(f["joined_day"]) >= 20 and _rng("rc_ind", day, fid).randf() < 0.1:
			_indep.append({"name": f["name"], "occ": f["occupation"], "day": day})
			while _indep.size() > INDEP_MAX:
				_indep.pop_front()
			var happy := float(e["m"]) >= 0.5
			_end(fid, "ended", "went independent")
			out.append("%s has gone independent, %s." % [f["name"], "with your blessing" if happy else "bitterly"])
			continue
		# Recommendation of a relative or friend.
		if float(e["tr"]) >= 55.0 and float(e["m"]) >= 0.6 and _refs.size() < REF_MAX and day % 7 == int(fid.substr(1)) % 7 and _rng("rc_ref", day, fid).randf() < 0.5:
			var home := int(f.get("person", -1))
			if home >= 0:
				var sid := int(WorldSim.home[home])
				var rg: Vector2i = WorldSim.ranges[sid]
				var row := rg.x + int(posmod(hash([WorldSim.SEED, "rc_ref", fid, day]), maxi(1, rg.y - rg.x)))
				if _alive(row) and not _by_row.has(row) and row != home:
					var seen := false
					for rf: Dictionary in _refs:
						seen = seen or int(rf["row"]) == row
					if not seen:
						_refs.append({"by": fid, "row": row, "day": day})
						out.append("%s recommends %s." % [f["name"], WorldSim.person_name(row)])
	return out


func _chunk_groups(day: int) -> Array:
	for nid in _n.keys():
		var n: Dictionary = _n[nid]
		if day >= int(n["exp"]) + 3:
			_n.erase(nid)
			continue
		_draw_applicants(n, day)
	for gid in _g:
		_group_day(gid, 1.0)
	# Old unanswered recommendations lapse.
	for i in range(_refs.size() - 1, -1, -1):
		if day - int(_refs[i]["day"]) > 20:
			_refs.remove_at(i)
	return []


func referrals() -> Array:
	var out: Array = []
	for rf: Dictionary in _refs:
		out.append({"by": rf["by"], "row": int(rf["row"]), "name": WorldSim.person_name(int(rf["row"]))})
	return out


func hire_referral(row: int, terms: Dictionary) -> Dictionary:
	for i in _refs.size():
		if int(_refs[i]["row"]) == row:
			var res := engage(row, terms, "personal", "", {"referral": true, "trust": 20.0})
			if res["ok"]:
				_refs.remove_at(i)
			return res
	return {"ok": false, "line": "No one recommended them."}


func independents() -> Array:
	return _indep


# --------------------------------------------------------------- catch up (closed form, O(entities))

func catch_up(days: int, ctx: Dictionary) -> Array:
	var out: Array = []
	if days < 1:
		return out
	_day += days
	_forget_gone()
	var fol := _fol()
	var avail: int = int(ctx.get("gold", 0)) + _pending
	var deserted := 0
	var expired := 0
	for fid in active_ids():
		var e: Dictionary = _r[fid]
		var f: Dictionary = fol.get_follower(fid)
		var c: Dictionary = _c[e["c"]]
		var wage := maxi(1, int(c["t"]["w"]))
		var owed := int(f["owed"])
		var paid := 0
		match String(e["chain"]):
			"personal":
				paid = mini(owed, maxi(0, avail))
				paid = (paid / wage) * wage if paid < owed else paid
				avail -= paid
				_pending -= paid
			"org":
				paid = owed
			_:
				var g: Dictionary = _g.get(e["g"], {})
				if not g.is_empty():
					paid = mini(owed, int(g["bud"]))
					paid = (paid / wage) * wage if paid < owed else paid
					g["bud"] = float(g["bud"]) - paid
		if paid > 0:
			fol.pay(fid, paid)
		_ledger_wage(fid, e, paid, owed)
		e["unp"] = int(f["owed"]) / wage
		var end_day := int(c["e"])
		if int(e["unp"]) >= WAGE_DAYS_DESERT:
			_end(fid, "broken", "deserted unpaid")
			deserted += 1
		elif end_day > 0 and _day >= end_day:
			_end(fid, "expired", "contract ended")
			expired += 1
		else:
			e["m"] = clampf(float(e["m"]) + (0.7 - float(e["m"])) * (1.0 - pow(0.7, days)), 0.0, 1.0)
	for gid in _g:
		_group_day(gid, float(days))
	for nid in _n.keys():
		if _day >= int(_n[nid]["exp"]) + 3:
			_n.erase(nid)
	if deserted > 0:
		out.append("%d of your people deserted while you were away, unpaid." % deserted)
	if expired > 0:
		out.append("%d contracts ran out while you were away." % expired)
	return out


# --------------------------------------------------------------- save

## Compact save: contracts and roster entries are arrays (keys would triple the size), ~140 B per recruit.
const CHAIN_IDS := ["personal", "org", "property"]
const ST_IDS := ["active", "expired", "ended", "broken"]


func serialize() -> Dictionary:
	var cc := {}
	for cid in _c:
		var c: Dictionary = _c[cid]
		var t: Dictionary = c["t"]
		cc[cid] = [c["fid"], CHAIN_IDS.find(c["chain"]), c["org"], int(t["w"]), t["d"], int(t["n"]), int(t["h"]), t["x"],
			ST_IDS.find(c["st"]), int(c["s"]), int(c["e"]), c["h"]]
	var rr := {}
	for fid in _r:
		var e: Dictionary = _r[fid]
		rr[fid] = [e["c"], snappedf(e["tr"], 0.1), snappedf(e["ol"], 0.1), snappedf(e["m"], 0.01), int(e["unp"]), int(e["low"]),
			int(e["dm"]), int(e["rn"]), e["g"], int(e["rf"]), snappedf(e["hb"], 0.01), e["mgr"]]
	return {"c": cc, "r": rr, "n": _n.duplicate(true), "g": _g.duplicate(true), "refs": _refs.duplicate(true),
		"indep": _indep.duplicate(true), "nc": _next_c, "nn": _next_n, "ng": _next_g, "pend": _pending, "pf": snappedf(_pend_f, 0.01), "day": _day}


func deserialize(d: Dictionary) -> void:
	_c.clear()
	var cc: Dictionary = d.get("c", {})
	for cid in cc:
		var a: Array = cc[cid]
		var fid_s: String = a[0]
		_c[cid] = {"id": cid, "fid": fid_s, "chain": CHAIN_IDS[int(a[1])], "org": a[2],
			"t": {"w": int(a[3]), "d": a[4], "n": int(a[5]), "h": int(a[6]), "x": float(a[7])},
			"st": ST_IDS[int(a[8])], "s": int(a[9]), "e": int(a[10]), "h": (a[11] as Array).duplicate(true)}
	_r.clear()
	var rr: Dictionary = d.get("r", {})
	for fid in rr:
		var a: Array = rr[fid]
		var cd: Dictionary = _c.get(a[0], {})
		_r[fid] = {"c": a[0], "chain": cd.get("chain", "personal"), "org": cd.get("org", ""), "tr": float(a[1]), "ol": float(a[2]),
			"m": float(a[3]), "unp": int(a[4]), "low": int(a[5]), "dm": int(a[6]), "rn": int(a[7]), "g": a[8], "rf": int(a[9]),
			"hb": float(a[10]), "mgr": a[11]}
	_n = (d.get("n", {}) as Dictionary).duplicate(true)
	_g = (d.get("g", {}) as Dictionary).duplicate(true)
	_refs = (d.get("refs", []) as Array).duplicate(true)
	_indep = (d.get("indep", []) as Array).duplicate(true)
	_next_c = int(d.get("nc", 1))
	_next_n = int(d.get("nn", 1))
	_next_g = int(d.get("ng", 1))
	_pending = int(d.get("pend", 0))
	_pend_f = float(d.get("pf", 0.0))
	_day = int(d.get("day", 0))
	_prof.clear()
	_by_row.clear()
	_ids = []
	# JSON turns ints into floats: normalise the row ids that are compared with ints.
	for nid in _n:
		var apps: Array = []
		for v in _n[nid]["app"]:
			apps.append(int(v))
		_n[nid]["app"] = apps
	for rf: Dictionary in _refs:
		rf["row"] = int(rf["row"])
	var fol := _fol()
	if fol == null:
		return
	for fid in _r:
		var f: Dictionary = fol.get_follower(fid)
		var c: Dictionary = _c.get(_r[fid]["c"], {})
		if not f.is_empty() and c.get("st", "") == "active" and f.has("person"):
			_by_row[int(f["person"])] = fid
