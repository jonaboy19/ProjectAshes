extends "res://scripts/realm/realm_module.gd"
## Organizations (LW-4.2, docs/design/LIVING_WORLD_SANDBOX.md §1.3, §5, Part C and E).
## ONE generic entity for every guild, company, band, order, academy, co-operative and syndicate. A record is `org:n` (registry.gd) and
## holds: type (organizations_data.gd), name, home settlement, stage (idea > members > charter > premises > standing), leader, succession
## mode, headquarters (a rented `pr:` property), charter + policies, treasury, a rank ladder with rights (recruit, dismiss, promote, judge,
## treasury, ...), members {ch: row}, applicants, disputes, parent / branches, and the assets it owns (versus the assets its members own).
##
## Four axes on every character, never mixed (spec §1.3): profession (what they do), employment (who pays them), membership (which
## organizations they belong to; several allowed unless a contract or an exclusive type conflicts) and ownership (assets, shares,
## businesses). axes(ch) returns the four side by side. Loyalty stays a separate per-person number (members' "t" trust here, "tr"/"ol"
## in recruitment.gd).
##
## The player and NPCs use the same calls: start_founding, add_founder, draft_charter, petition_recognition, rent_hq, apply, decide,
## promote, leave, challenge, open_branch, merge, split, dissolve. NPCs reach them from a bounded, hash-staggered goal pass (_npc_day).
##
## Money: members' dues and salaries move between purses and the treasury. The player's purse never changes here: pending_gold is drained
## by Life through take_pending_gold(). Activity income (what an organization earns from real work) and rent are the only exchanges with
## the world. Cost: day tick O(due orgs) in chunks of ORG_CHUNK; every org settles its week on its own staggered day, never all at once.
## Saves: ~150 B per org + ~24 B per member (cap ORG_CAP 400, MEMBER_CAP 4000).

const D := preload("res://scripts/realm/organizations_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const Reg := preload("res://scripts/realm/registry.gd")

const ORG_CAP := 400
const MEMBER_CAP := 4000
const ORG_CHUNK := 20
const FAR_DAYS := 28
const NPC_PER_DAY := 10
const NPC_CADENCE := 3          # one decision per NPC per 3 days
const ACTOR_SEED := 96
const ACTORS_MAX := 400
const PETITION_DAYS := 7
const PETITION_RETRY := 14
const APP_DAYS := 14
const SCHISM_AT := 8.0
const DISPUTE_RULE_DAYS := 10
const BRANCH_COST := 150
const BRANCH_TRIBUTE := 0.1
const REP_DECAY := 0.97
const LEAVE_BREACH_REP := 4.0
const FOUNDED_KEEP := 30        # a dissolved org's stub is kept this many days
const HIST_MAX := 6

var _o: Dictionary = {}          # org id -> org
var _c: Dictionary = {}          # ch -> character axes record
var _a: Dictionary = {}          # asset id -> asset {id, kind, name, value, owner}
var _pt: Dictionary = {}         # petition id -> petition
var _mem: Dictionary = {}        # ch -> [org ids] (derived, rebuilt on load)
var _ord: Array = []             # sorted org ids (cache)
var _npc: Array = []             # sorted NPC actor ids (cache)
var _npc_ok := false
var _next_d := 1
var _adapt_todo: Array = []
var _adapt_next := 0
var _sched: Dictionary = {}      # day -> [org ids to look at that day] (due queue; nothing is polled)
var _npc_b: Array = [[], [], []]
var _npc_ptr: Array = [0, 0, 0]
var _types_cache: Dictionary = {}
var _mcount := 0
var _reg: RefCounted = null
var _pl := ""
var _sidx: Dictionary = {}
var _sidx_ok := false
var _next_a := 1
var _next_p := 1
var _own_n := 0
var _day := 0
var _seeded := false
var auto_seed := true            # false in tests that bring their own actors
var pending_gold := 0
var gold_ref: Variant = null     # Dictionary {"gold": n} for tests; null = Game.gold
var stats := {"founded": 0, "dissolved": 0, "merged": 0, "splits": 0, "elections": 0, "challenges": 0, "disputes": 0, "contested": 0,
	"promotions": 0, "npc_founded": 0, "npc_joined": 0, "fees": 0, "rent": 0}
var log_lines: Array = []


# ------------------------------------------------------------------ plumbing

func _rng(tag: String, d: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, d, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _mint(prefix: String) -> String:
	var reg := _mod("registry")
	if reg != null:
		var pid: String = reg.mint(prefix)
		if pid != "":
			return pid
	_own_n += 1
	return "%s:%d" % [prefix, 90000 + _own_n]


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 20:
		log_lines.pop_front()


func _ev(kind: String, where: Variant, actors: Array, cause: String, outcome: String, weight := 2) -> void:
	if hub != null:
		Events.log_to(hub, kind, where, actors, cause, outcome, weight)


func today() -> int:
	return _day


func set_day(d: int) -> void:
	_day = d


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func player_id() -> String:
	var reg := _mod("registry")
	_pl = reg.ref("pl:player") if reg != null else "player"
	return _pl


func _is_player(ch: String) -> bool:
	if ch == "player":
		return true
	if _pl == "":
		var reg := _mod("registry")
		if reg != null:
			_pl = reg.lookup("pl:player")
	return ch != "" and ch == _pl


# ------------------------------------------------------------------ characters: the four axes

## A character record, created on first use. `init` may carry cash, sid, prof, sk{}, rep, npc.
func ensure_char(ch: String, init := {}) -> Dictionary:
	if not _c.has(ch):
		_c[ch] = {"prof": String(init.get("prof", "")), "emp": {}, "cash": int(init.get("cash", 0)), "sid": int(init.get("sid", -1)),
			"sk": (init.get("sk", {}) as Dictionary).duplicate(), "rep": float(init.get("rep", 0.0)), "npc": bool(init.get("npc", false)),
			"amb": String(init.get("amb", "")), "own": [], "fol": ""}
		if bool(init.get("npc", false)):
			_npc_ok = false
	elif not init.is_empty():
		var r: Dictionary = _c[ch]
		for k: String in init:
			if k == "sk":
				r["sk"] = (init["sk"] as Dictionary).duplicate()
			elif r.has(k):
				r[k] = init[k]
	return _c[ch]


func has_char(ch: String) -> bool:
	return _c.has(ch)


func char_rec(ch: String) -> Dictionary:
	return _c.get(ch, {})


## A new NPC (a characters id from the registry) that the goal pass will move. Returns its ch id.
func spawn_actor(sid: int, prof: String, cash: int, sk := {}, rep := 0.0, amb := "") -> String:
	var ch := _mint("ch")
	ensure_char(ch, {"prof": prof, "cash": cash, "sid": sid, "sk": sk, "rep": rep, "npc": true, "amb": amb})
	return ch


func profession(ch: String) -> String:
	return String(_c.get(ch, {}).get("prof", ""))


func set_profession(ch: String, prof: String) -> void:
	ensure_char(ch)["prof"] = prof


## Employment is "who pays you": {} (none) or {by, wage, ct}. It never implies membership.
func employment(ch: String) -> Dictionary:
	return (_c.get(ch, {}).get("emp", {}) as Dictionary).duplicate()


func employ(ch: String, by: String, wage: int, ct := "") -> void:
	ensure_char(ch)["emp"] = {"by": by, "wage": wage, "ct": ct}


func unemploy(ch: String) -> void:
	if _c.has(ch):
		_c[ch]["emp"] = {}


func skill_of(ch: String, stat: String) -> float:
	var sk: Dictionary = _c.get(ch, {}).get("sk", {})
	if sk.has(stat):
		return float(sk[stat])
	return 0.15 + float(absi(hash([WorldSim.SEED, "osk", ch, stat])) % 70) / 100.0


func reputation_of(ch: String) -> float:
	return float(_c.get(ch, {}).get("rep", 0.0))


func add_reputation(ch: String, d: float) -> void:
	var r := ensure_char(ch)
	r["rep"] = clampf(float(r["rep"]) + d, -100.0, 100.0)


func gold_available() -> int:
	var g := 0
	if gold_ref is Dictionary:
		g = int((gold_ref as Dictionary).get("gold", 0))
	else:
		g = Game.gold
	return g + pending_gold


func purse(ch: String) -> int:
	if _is_player(ch):
		return gold_available()
	return int(_c.get(ch, {}).get("cash", 0))


func pay(ch: String, amt: int) -> bool:
	if amt <= 0:
		return true
	if purse(ch) < amt:
		return false
	if _is_player(ch):
		pending_gold -= amt
	else:
		_c[ch]["cash"] = int(_c[ch]["cash"]) - amt
	return true


func earn(ch: String, amt: int) -> void:
	if amt <= 0:
		return
	if _is_player(ch):
		pending_gold += amt
	else:
		ensure_char(ch)["cash"] = int(_c[ch]["cash"]) + amt


## A payer or payee that is a character (purse) or an organization (treasury).
func can_afford(who: String, amt: int) -> bool:
	if Reg.prefix_of(who) == "org":
		return int(_o.get(who, {}).get("treasury", 0)) >= amt
	return purse(who) >= amt


func pay_from(who: String, amt: int) -> bool:
	if Reg.prefix_of(who) == "org":
		if not _o.has(who) or int(_o[who]["treasury"]) < amt:
			return false
		_o[who]["treasury"] = int(_o[who]["treasury"]) - amt
		return true
	return pay(who, amt)


func pay_to(who: String, amt: int) -> void:
	if Reg.prefix_of(who) == "org":
		if _o.has(who):
			_o[who]["treasury"] = int(_o[who]["treasury"]) + amt
		return
	earn(who, amt)


## The four axes of one character, side by side.
func axes(ch: String) -> Dictionary:
	var ms: Array = []
	for oid: String in memberships(ch):
		var o: Dictionary = _o[oid]
		var rk := int(o["m"][ch]["r"])
		ms.append({"org": oid, "name": o["name"], "rank": rk, "rank_name": rank_name(oid, rk)})
	var biz: Array = []
	var bm := _mod("businesses")
	if bm != null:
		biz = bm.owned_by(ch)
	return {"profession": profession(ch), "employment": employment(ch), "membership": ms,
		"ownership": {"assets": assets_owned_by(ch), "businesses": biz}}


# ------------------------------------------------------------------ queries

func org(oid: String) -> Dictionary:
	return _o.get(oid, {})


func exists(oid: String) -> bool:
	return _o.has(oid)


func org_ids() -> Array:
	if _ord.size() != _o.size():
		_ord = _o.keys()
		_ord.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(4)) < int(b.substr(4)))
	return _ord


## Asks to be looked at no later than day `d` (only one live chain of wake-ups per body).
func _wake(oid: String, d: int) -> void:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty():
		return
	var pl := int(o["pl"])
	if pl > _day and pl <= d:
		return
	o["pl"] = d
	_plan(oid, d)


func _plan(oid: String, d: int) -> void:
	if _sched.has(d):
		(_sched[d] as Array).append(oid)
	else:
		_sched[d] = [oid]


## Rank counts and the skill sum are kept with every change of a seat so a far body settles without walking its members.
func _rebuild_rc(o: Dictionary) -> void:
	var rc := [0, 0, 0, 0, 0, 0]
	var ks := 0.0
	var m: Dictionary = o["m"]
	for ch: String in m:
		rc[clampi(int(m[ch]["r"]), 0, 5)] += 1
		ks += float(m[ch].get("k", 0.5))
	o["rcv"] = rc
	o["ks"] = ks


func _set_rank(o: Dictionary, ch: String, rank: int) -> void:
	var row: Dictionary = o["m"][ch]
	var rc: Array = o["rcv"]
	rc[clampi(int(row["r"]), 0, 5)] -= 1
	row["r"] = rank
	rc[clampi(rank, 0, 5)] += 1


func active_ids() -> Array:
	var out: Array = []
	for oid: String in org_ids():
		if String(_o[oid]["st"]) == "active":
			out.append(oid)
	return out


func memberships(ch: String) -> Array:
	return (_mem.get(ch, []) as Array).duplicate()


func is_member(oid: String, ch: String) -> bool:
	return _o.get(oid, {}).get("m", {}).has(ch)


func rank_of(oid: String, ch: String) -> int:
	var m: Dictionary = _o.get(oid, {}).get("m", {})
	return int(m[ch]["r"]) if m.has(ch) else -1


func member(oid: String, ch: String) -> Dictionary:
	var m: Dictionary = _o.get(oid, {}).get("m", {})
	return (m[ch] as Dictionary).duplicate() if m.has(ch) else {}


func members_of(oid: String, min_rank := 0) -> Array:
	var out: Array = []
	var m: Dictionary = _o.get(oid, {}).get("m", {})
	for ch: String in m:
		if int(m[ch]["r"]) >= min_rank:
			out.append(ch)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(m[a]["r"])
		var rb := int(m[b]["r"])
		return ra > rb or (ra == rb and a < b))
	return out


func member_count(oid: String) -> int:
	return (_o.get(oid, {}).get("m", {}) as Dictionary).size()


func type_of(oid: String) -> Dictionary:
	return D.type_def(String(_o.get(oid, {}).get("type", "")))


func rank_name(oid: String, rank: int) -> String:
	var o: Dictionary = _o.get(oid, {})
	var ranks: Array = type_of(oid).get("ranks", [])
	if rank < 0:
		return "Applicant"
	return String(ranks[clampi(rank, 0, ranks.size() - 1)]) if not ranks.is_empty() else "member"


func rights_at(oid: String, rank: int) -> Array:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or rank < 0:
		return []
	var ov: Dictionary = o.get("rk", {})
	if ov.has(str(rank)):
		return ov[str(rank)]
	return D.rank_rights(String(o["type"]), rank)


func can(oid: String, ch: String, right: String) -> bool:
	var rk := rank_of(oid, ch)
	return rk >= 0 and right in rights_at(oid, rk)


func scale_of(oid: String) -> String:
	return D.scale_name(member_count(oid))


func stage_name(oid: String) -> String:
	return String(D.STAGES[clampi(int(_o.get(oid, {}).get("stage", 0)), 0, D.STAGES.size() - 1)])


## Seats at a rank (9999 = unlimited).
func slots(oid: String, rank: int) -> int:
	var v := float(D.BASE_SLOTS[clampi(rank, 0, D.RANK_COUNT - 1)])
	if v == -1.0:
		return 9999
	if v < 0.0:
		return maxi(1, ceili(float(member_count(oid)) * -v))
	return int(v)


func count_at(oid: String, rank: int) -> int:
	var n := 0
	var m: Dictionary = _o.get(oid, {}).get("m", {})
	for ch: String in m:
		if int(m[ch]["r"]) == rank:
			n += 1
	return n


func capacity(oid: String) -> int:
	var o: Dictionary = _o.get(oid, {})
	return 8 + (24 if not (o.get("hq", {}) as Dictionary).is_empty() else 0) + 10 * int(o.get("stage", 0))


func orgs_in(sid: int, type := "") -> Array:
	if not _sidx_ok:
		_sidx = {}
		for oid: String in org_ids():
			var s: int = int(_o[oid]["sid"])
			if not _sidx.has(s):
				_sidx[s] = []
			(_sidx[s] as Array).append(oid)
		_sidx_ok = true
	var out: Array = []
	for oid2: String in _sidx.get(sid, []):
		var o: Dictionary = _o.get(oid2, {})
		if not o.is_empty() and String(o["st"]) == "active" and (type == "" or String(o["type"]) == type):
			out.append(oid2)
	return out


## Settle this body member by member (its members' purses move). On for any body the player belongs to.
func watch(oid: String, on := true) -> void:
	if _o.has(oid):
		_o[oid]["dt"] = on


func _new_org(type: String, nm: String, sid: int, mode: String, forced_id := "") -> String:
	var oid := forced_id if forced_id != "" else _mint("org")
	var td := D.type_def(type)
	var born := _day
	_o[oid] = {"id": oid, "type": type, "name": nm, "sid": sid, "st": "active", "stage": 0, "leader": "", "founders": [], "mode": mode,
		"succ": {"mode": String(td.get("succ", "election")), "heir": ""}, "hq": {}, "charter": {}, "legal": "none", "treasury": 0,
		"pol": {"dues": 1.0, "wage": 1.0, "open": true}, "m": {}, "app": {}, "dis": [], "parent": "", "br": [], "assets": [], "rep": 0.0, "act": 0.0,
		"born": born, "lw": born - (int(Reg.parse(oid).get("n", 0)) % FAR_DAYS), "nd": born, "strife": 0.0, "sw": 0, "nw": 0, "late": 0, "hist": [],
		"pet": "", "cd": -100, "split_from": "", "merged": "", "dt": mode == "manual", "owed": 0, "n": int(Reg.parse(oid).get("n", 0)), "off": 0.0, "pl": born + 1 + int(Reg.parse(oid).get("n", 0)) % 7, "rcv": [0, 0, 0, 0, 0, 0], "ks": 0.0}
	if _ord.size() == _o.size() - 1:
		_ord.append(oid)
	else:
		_ord = []
	if _sidx_ok:
		if not _sidx.has(sid):
			_sidx[sid] = []
		(_sidx[sid] as Array).append(oid)
	_plan(oid, int(_o[oid]["pl"]))
	return oid


func _hist(o: Dictionary, text: String) -> void:
	var h: Array = o["hist"]
	h.append("d%d %s" % [_day, text])
	while h.size() > HIST_MAX:
		h.pop_front()


func _index(ch: String, oid: String, on: bool) -> void:
	var l: Array = _mem.get(ch, [])
	if on:
		if not l.has(oid):
			l.append(oid)
		_mem[ch] = l
	else:
		l.erase(oid)
		if l.is_empty():
			_mem.erase(ch)
		else:
			_mem[ch] = l


func _total_members() -> int:
	return _mcount


func _recount() -> void:
	var n := 0
	for oid: String in _o:
		n += (_o[oid]["m"] as Dictionary).size()
	_mcount = n


# ------------------------------------------------------------------ conflicts (membership axis)

## "" when `ch` may hold a seat in `oid`, else the plain-words reason (an exclusive oath, a rival type, a contract).
func join_conflict(oid: String, ch: String) -> String:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or String(o["st"]) != "active":
		return "That organization does not exist."
	if is_member(oid, ch):
		return "Already a member."
	var td := D.type_def(String(o["type"]))
	for other: String in memberships(ch):
		var ot := String(_o[other]["type"])
		var otd := D.type_def(ot)
		if bool(td.get("excl", false)) and bool(otd.get("excl", false)):
			return "Sworn to %s; an oath of service excludes another." % _o[other]["name"]
		if ot in (td.get("conflicts", []) as Array) or String(o["type"]) in (otd.get("conflicts", []) as Array):
			return "%s and %s will never share a member." % [td.get("label", ""), otd.get("label", "")]
		if bool(_o[other]["m"][ch].get("b", 0)) and bool(otd.get("excl", false)) and bool(td.get("excl", false)):
			return "Bound by contract to %s." % _o[other]["name"]
	return ""


# ------------------------------------------------------------------ founding

func start_founding(founder: String, type: String, nm: String, sid: int, mode := "manual") -> Dictionary:
	if not D.TYPES.has(type):
		return {"ok": false, "reason": "No such kind of organization."}
	if _o.size() >= ORG_CAP:
		return {"ok": false, "reason": "The realm has all the organizations it can hold."}
	for oid: String in _o:
		if String(_o[oid]["name"]) == nm and String(_o[oid]["st"]) == "active":
			return {"ok": false, "reason": "That name is taken."}
	ensure_char(founder)
	var oid2 := _new_org(type, nm, sid, mode)
	var why := join_conflict(oid2, founder)
	if why != "":
		_o.erase(oid2)
		_ord = []
		return {"ok": false, "reason": why}
	_o[oid2]["founders"] = [founder]
	_o[oid2]["leader"] = founder
	_add_member(oid2, founder, D.LEADER, "")
	_restage(oid2)
	stats["founded"] = int(stats["founded"]) + 1
	_ev("founding", "ss:%d" % sid if sid >= 0 else "", [founder, oid2], "org_idea", "%s is thought of" % nm, 2)
	return {"ok": true, "org": oid2}


func add_founder(oid: String, founder: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or founder != o["leader"]:
		return {"ok": false, "reason": "Only the founder can ask others to found."}
	if int(o["stage"]) >= 2:
		return {"ok": false, "reason": "The founding is over; people join now."}
	var why := join_conflict(oid, ch)
	if why != "":
		return {"ok": false, "reason": why}
	ensure_char(ch)
	(o["founders"] as Array).append(ch)
	_add_member(oid, ch, D.OFFICER, founder)
	_restage(oid)
	return {"ok": true}


## Writes the charter: text, rules (succession mode, dues, open recruiting). Costs the type's founding fee: half becomes the first
## treasury, half is the clerk's and the magistrate's.
func draft_charter(oid: String, by: String, text: String, rules := {}) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "charter"):
		return {"ok": false, "reason": "You have no right to write the charter."}
	if not (o["charter"] as Dictionary).is_empty():
		return {"ok": false, "reason": "There is a charter already."}
	if member_count(oid) < int(type_of(oid).get("min_founders", 2)):
		return {"ok": false, "reason": "A charter needs %d founders." % int(type_of(oid).get("min_founders", 2))}
	var cost := int(type_of(oid).get("found", 0))
	if not pay(by, cost):
		return {"ok": false, "reason": "The charter costs %d gold." % cost}
	o["treasury"] = int(o["treasury"]) + cost / 2
	stats["fees"] = int(stats["fees"]) + cost - cost / 2
	o["charter"] = {"text": text.substr(0, 160), "day": _day}
	if rules.has("succ") and String(rules["succ"]) in D.SUCCESSION:
		(o["succ"] as Dictionary)["mode"] = String(rules["succ"])
	if rules.has("dues"):
		o["pol"]["dues"] = clampf(float(rules["dues"]), 0.0, 3.0)
	if rules.has("open"):
		o["pol"]["open"] = bool(rules["open"])
	if float(type_of(oid).get("recog_rep", 0)) >= 9999.0:
		o["legal"] = "outlaw"
	_restage(oid)
	_ev("founding", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [by, oid], "charter", "%s writes its charter" % o["name"], 2)
	return {"ok": true}


## Legal recognition (Stage 6 hooks resolve_petition; until then a stub rule decides after PETITION_DAYS).
func petition_recognition(oid: String, by: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "charter"):
		return {"ok": false, "reason": "You cannot petition for it."}
	if (o["charter"] as Dictionary).is_empty():
		return {"ok": false, "reason": "A petition needs a charter."}
	if String(o["legal"]) in ["recognised", "outlaw"]:
		return {"ok": false, "reason": "Already settled."}
	if String(o["pet"]) != "" and String(_pt.get(o["pet"], {}).get("st", "")) == "pending":
		return {"ok": false, "reason": "The petition is waiting."}
	if _day < int(o.get("pd", -100)) + PETITION_RETRY:
		return {"ok": false, "reason": "They asked you to wait before petitioning again."}
	var pid := "pt%d" % _next_p
	_next_p += 1
	_pt[pid] = {"id": pid, "org": oid, "day": _day, "st": "pending", "why": ""}
	o["pet"] = pid
	o["legal"] = "petitioned"
	return {"ok": true, "petition": pid}


func petitions(status := "") -> Array:
	var out: Array = []
	for pid: String in _pt:
		if status == "" or String(_pt[pid]["st"]) == status:
			out.append((_pt[pid] as Dictionary).duplicate())
	return out


## The Stage 6 entry point: a court or magistrate answers a petition.
func resolve_petition(pid: String, granted: bool, why := "") -> bool:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["st"]) != "pending":
		return false
	p["st"] = "granted" if granted else "refused"
	p["why"] = why
	var o: Dictionary = _o.get(p["org"], {})
	if not o.is_empty():
		o["legal"] = "recognised" if granted else "none"
		o["pd"] = _day
		o["pet"] = ""
		_restage(String(p["org"]))
		_ev("founding", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [String(p["org"])],
			"recognised" if granted else "refused", "%s is %s" % [o["name"], "recognised" if granted else "refused recognition"], 2)
	return true


func _stub_petition(p: Dictionary) -> void:
	var o: Dictionary = _o.get(p["org"], {})
	if o.is_empty():
		p["st"] = "refused"
		return
	var ok := float(o["rep"]) >= float(type_of(String(p["org"])).get("recog_rep", 0.0)) and member_count(String(p["org"])) >= int(type_of(String(p["org"])).get("min_founders", 2))
	resolve_petition(String(p["id"]), ok, "" if ok else "unknown to the magistrate")


## Rents a building (a `pr:` property, leased). The rent comes out of the treasury weekly; three unpaid weeks and the landlord takes it back.
func rent_hq(oid: String, by: String, sid: int, rent := -1) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "treasury"):
		return {"ok": false, "reason": "You cannot sign a lease for it."}
	if not (o["hq"] as Dictionary).is_empty():
		return {"ok": false, "reason": "There is a headquarters already."}
	var r := rent if rent >= 0 else int(type_of(oid).get("hq_rent", 8))
	if int(o["treasury"]) < r * 2:
		return {"ok": false, "reason": "A lease needs two weeks' rent in the treasury (%d gold)." % (r * 2)}
	o["treasury"] = int(o["treasury"]) - r * 2
	stats["rent"] = int(stats["rent"]) + r * 2
	o["hq"] = {"pr": _mint("pr"), "sid": sid, "rent": r, "since": _day, "legal": "leased"}
	o["late"] = 0
	_restage(oid)
	_ev("founding", "ss:%d" % sid if sid >= 0 else "", [by, oid], "hq", "%s takes a house" % o["name"], 1)
	return {"ok": true, "property": o["hq"]["pr"]}


func _restage(oid: String) -> void:
	var o: Dictionary = _o[oid]
	var td := D.type_def(String(o["type"]))
	var st := 0
	if member_count(oid) >= int(td.get("min_founders", 2)):
		st = 1
		if not (o["charter"] as Dictionary).is_empty() and String(o["legal"]) in ["recognised", "outlaw"]:
			st = 2
			if not (o["hq"] as Dictionary).is_empty():
				st = 3
				if float(o["rep"]) >= float(td.get("stand_rep", 25.0)) and int(o["sw"]) >= 4:
					st = 4
	if st != int(o["stage"]):
		o["stage"] = st
		_hist(o, "stage: " + String(D.STAGES[st]))


# ------------------------------------------------------------------ members: joining

func _add_member(oid: String, ch: String, rank: int, sponsor: String, bound := 0, ct := "") -> void:
	var o: Dictionary = _o[oid]
	var td := D.type_def(String(o["type"]))
	o["m"][ch] = {"r": rank, "s": _day, "c": 0.0, "t": 60.0, "sp": sponsor, "b": bound, "ar": 0, "ct": ct,
		"pd": (_day + int(td.get("prob", 7))) if rank == D.PROBATION else -1, "k": snappedf(skill_of(ch, String(td.get("skill", ""))), 0.01)}
	_index(ch, oid, true)
	_mcount += 1
	(o["rcv"] as Array)[clampi(rank, 0, 5)] += 1
	o["ks"] = float(o["ks"]) + float(o["m"][ch]["k"])
	if _is_player(ch):
		o["dt"] = true
	_wake(oid, _day + 1)
	ensure_char(ch)
	o["app"].erase(ch)


## An applicant asks to join. `sponsor` is a member who vouches for them (open for types that require it).
func apply(oid: String, ch: String, sponsor := "") -> Dictionary:
	var why := join_conflict(oid, ch)
	if why != "":
		return {"ok": false, "reason": why}
	var o: Dictionary = _o[oid]
	if not bool(o["pol"]["open"]) and sponsor == "":
		return {"ok": false, "reason": "They are not taking people."}
	if member_count(oid) >= capacity(oid):
		return {"ok": false, "reason": "There is no room: %d of %d seats." % [member_count(oid), capacity(oid)]}
	if (o["app"] as Dictionary).has(ch):
		return {"ok": false, "reason": "You have applied already."}
	if sponsor != "" and not is_member(oid, sponsor):
		sponsor = ""
	ensure_char(ch)
	o["app"][ch] = {"d": _day, "sp": sponsor}
	_wake(oid, _day + 1)
	return {"ok": true}


## What the examiners think of an applicant: {ok, score, reasons[]}. Skill, name, fee and (when the type asks) a sponsor.
func evaluate_application(oid: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	var a: Dictionary = o.get("app", {}).get(ch, {})
	var td := type_of(oid)
	var ent: Dictionary = td.get("entry", {})
	var reasons: Array = []
	var ok := true
	var sk := skill_of(ch, String(td.get("skill", "")))
	if sk < float(ent.get("skill", 0.0)):
		ok = false
		reasons.append("Not skilled enough (%.2f of %.2f)." % [sk, float(ent.get("skill", 0.0))])
	if reputation_of(ch) < float(ent.get("rep", 0)):
		ok = false
		reasons.append("Not known well enough.")
	if bool(ent.get("sponsor", false)) and String(a.get("sp", "")) == "":
		ok = false
		reasons.append("Needs a sponsor from among the members.")
	if purse(ch) < int(ent.get("fee", 0)):
		ok = false
		reasons.append("Cannot pay the %d gold entry fee." % int(ent.get("fee", 0)))
	var sp := String(a.get("sp", ""))
	var score := sk * 50.0 + reputation_of(ch) * 0.4 + (12.0 if sp != "" else 0.0) + (6.0 if profession(ch) in (td.get("prof", []) as Array) else 0.0)
	return {"ok": ok, "score": snappedf(score, 0.1), "reasons": reasons}


func applicants(oid: String) -> Array:
	return (_o.get(oid, {}).get("app", {}) as Dictionary).keys()


## A member with the recruit right accepts or refuses an applicant. Accepting seats them on probation.
func decide(oid: String, by: String, ch: String, accept: bool) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "recruit"):
		return {"ok": false, "reason": "You have no right to admit people."}
	if not (o["app"] as Dictionary).has(ch):
		return {"ok": false, "reason": "They have not applied."}
	if not accept:
		o["app"].erase(ch)
		return {"ok": true, "joined": false}
	var ev := evaluate_application(oid, ch)
	if not bool(ev["ok"]):
		o["app"].erase(ch)
		return {"ok": true, "joined": false, "reasons": ev["reasons"]}
	var why := join_conflict(oid, ch)
	if why != "":
		o["app"].erase(ch)
		return {"ok": true, "joined": false, "reasons": [why]}
	if _total_members() >= MEMBER_CAP or member_count(oid) >= capacity(oid):
		return {"ok": false, "reason": "There is no room."}
	var fee := int(type_of(oid).get("entry", {}).get("fee", 0))
	if not pay(ch, fee):
		return {"ok": true, "joined": false, "reasons": ["Cannot pay the entry fee."]}
	o["treasury"] = int(o["treasury"]) + fee
	var sp := String(o["app"][ch].get("sp", ""))
	_add_member(oid, ch, D.PROBATION, sp if sp != "" else by)
	_ev("contract", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [ch, oid], "join_probation", "%s takes a probationer" % o["name"], 1)
	return {"ok": true, "joined": true}


## Seats a person who is already tied by a recruitment.gd contract (first recruits of a new organization).
func admit_contracted(oid: String, by: String, ch: String, ct: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "recruit"):
		return {"ok": false, "reason": "You have no right to admit people."}
	var why := join_conflict(oid, ch)
	if why != "":
		return {"ok": false, "reason": why}
	if _total_members() >= MEMBER_CAP or member_count(oid) >= capacity(oid):
		return {"ok": false, "reason": "There is no room."}
	_add_member(oid, ch, D.PROBATION, by, 1, ct)
	return {"ok": true}


## First recruits through recruitment.gd (spec §2): posts a notice at the organization's headquarters town, and later seats applicants.
func post_recruitment(oid: String, by: String, wage: int, occ := "") -> Dictionary:
	var rc := _mod("recruitment")
	var o: Dictionary = _o.get(oid, {})
	if rc == null or o.is_empty() or not can(oid, by, "recruit"):
		return {"ok": false, "reason": "You cannot post a notice for them."}
	if not pay_from(oid, 3):
		return {"ok": false, "reason": "The treasury cannot pay the notice."}
	var sid := int((o["hq"] as Dictionary).get("sid", o["sid"]))
	var res: Dictionary = rc.post_notice(sid, "guild", rc.make_terms(wage, "labor", 0, false), occ, 10, "", maxf(10.0, float(o["rep"])))
	if res.get("ok", false):
		rc.set("_pending", int(rc.get("_pending")) + 3)     # the organization paid the fee, not the player's ledger
		o["nid"] = res["nid"]
	return res


## Seats one applicant of the organization's notice on a recruitment.gd contract in the org chain.
func hire_from_notice(oid: String, by: String, row: int, wage: int) -> Dictionary:
	var rc := _mod("recruitment")
	var reg := _mod("registry")
	var o: Dictionary = _o.get(oid, {})
	if rc == null or reg == null or o.is_empty() or not can(oid, by, "recruit"):
		return {"ok": false, "reason": "You cannot hire for them."}
	var nid := String(o.get("nid", ""))
	var ch: String = reg.ref("ws:%d" % row)
	var why := join_conflict(oid, ch)
	if why != "":
		return {"ok": false, "reason": why}
	var res: Dictionary = rc.engage(row, rc.make_terms(wage, "labor", 0, false), "org", oid, {"trust": 40.0, "reputation": maxf(20.0, float(o["rep"]))})
	if not bool(res.get("ok", false)):
		return res
	if nid != "":
		for n: Dictionary in rc.notices():
			if String(n["id"]) == nid:
				(n["app"] as Array).erase(row)
	var cid := String(res["cid"])
	var ctid: String = reg.ref("rc:" + cid)
	ensure_char(ch, {"sid": int(o["sid"])})
	var ad := admit_contracted(oid, by, ch, ctid)
	if bool(ad.get("ok", false)):
		employ(ch, oid, wage, ctid)
	return {"ok": bool(ad.get("ok", false)), "ch": ch, "ct": ctid, "fid": res.get("fid", ""), "reason": ad.get("reason", "")}


# ------------------------------------------------------------------ members: promotion and dismissal

func _next_rank(oid: String, ch: String) -> int:
	return rank_of(oid, ch) + 1


## Can `ch` be promoted now, and why not: skill, contribution, trust, an open seat, and politics (an open dispute against an officer).
func promotion_status(oid: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	var m: Dictionary = o.get("m", {}).get(ch, {})
	if m.is_empty():
		return {"can": false, "reasons": ["Not a member."]}
	var rk := int(m["r"])
	var nxt := rk + 1
	if nxt > D.LEADER:
		return {"can": false, "reasons": ["Already at the top."], "next": rk}
	if nxt == D.LEADER:
		return {"can": false, "reasons": ["The leader's seat is won by succession, not promotion."], "next": nxt}
	var reasons: Array = []
	var td := type_of(oid)
	if float(m["c"]) < float(D.BASE_NEED[nxt]):
		reasons.append("Contribution %.0f of %.0f." % [float(m["c"]), float(D.BASE_NEED[nxt])])
	if float(m["t"]) < 40.0 + 6.0 * float(nxt):
		reasons.append("Not trusted enough yet.")
	if skill_of(ch, String(td.get("skill", ""))) < 0.12 + 0.1 * float(nxt):
		reasons.append("Not skilled enough for the post.")
	if count_at(oid, nxt) >= slots(oid, nxt):
		reasons.append("No open seat for a %s." % rank_name(oid, nxt))
	if nxt == D.PROBATION + 1 and int(m["pd"]) >= 0 and _day < int(m["pd"]):
		reasons.append("Still on probation until day %d." % int(m["pd"]))
	for d: Dictionary in o["dis"]:
		if String(d["st"]) == "open" and String(d["b"]) == ch and rank_of(oid, String(d["a"])) >= D.OFFICER:
			reasons.append("An officer has a complaint against them.")
			break
	return {"can": reasons.is_empty(), "reasons": reasons, "next": nxt}


func promote(oid: String, by: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "promote"):
		return {"ok": false, "reason": "You have no right to promote."}
	var st := promotion_status(oid, ch)
	if not bool(st["can"]):
		return {"ok": false, "reason": " ".join(st["reasons"]), "reasons": st["reasons"]}
	var nxt := int(st["next"])
	if nxt >= rank_of(oid, by) and by != String(o["leader"]):
		return {"ok": false, "reason": "You cannot raise anyone to your own rank or above."}
	_set_rank(o, ch, nxt)
	o["m"][ch]["s"] = _day
	o["m"][ch]["pd"] = -1
	stats["promotions"] = int(stats["promotions"]) + 1
	_ev("contract", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [ch, oid], "promoted", "%s made %s" % [ch, rank_name(oid, nxt)], 1)
	return {"ok": true, "rank": nxt}


func demote(oid: String, by: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "dismiss") or rank_of(oid, ch) >= rank_of(oid, by) or rank_of(oid, ch) <= 0:
		return {"ok": false, "reason": "You cannot."}
	_set_rank(o, ch, int(o["m"][ch]["r"]) - 1)
	o["m"][ch]["t"] = maxf(0.0, float(o["m"][ch]["t"]) - 15.0)
	return {"ok": true}


func dismiss(oid: String, by: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "dismiss") or rank_of(oid, ch) < 0 or rank_of(oid, ch) >= rank_of(oid, by):
		return {"ok": false, "reason": "You cannot dismiss them."}
	_remove(oid, ch, "dismissed")
	return {"ok": true}


## Credit for real work done for the organization (a contract delivered, a commission filled): contribution, activity, reputation.
func record_activity(oid: String, ch: String, amount: float, kind := "work") -> void:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty():
		return
	o["act"] = float(o["act"]) + amount
	if (o["m"] as Dictionary).has(ch):
		o["m"][ch]["c"] = float(o["m"][ch]["c"]) + amount
		o["m"][ch]["t"] = minf(100.0, float(o["m"][ch]["t"]) + amount * 0.3)
	add_reputation(ch, amount * 0.05)


func _remove(oid: String, ch: String, why: String) -> void:
	var o: Dictionary = _o[oid]
	var row: Dictionary = o["m"].get(ch, {})
	if row.is_empty():
		return
	var was_leader := String(o["leader"]) == ch
	(o["rcv"] as Array)[clampi(int(row["r"]), 0, 5)] -= 1
	o["ks"] = float(o["ks"]) - float(row.get("k", 0.5))
	o["m"].erase(ch)
	_mcount -= 1
	_index(ch, oid, false)
	if String(_c.get(ch, {}).get("emp", {}).get("by", "")) == oid:
		unemploy(ch)
	var rc := _mod("recruitment")
	if rc != null and String(row.get("ct", "")) != "":
		var reg := _mod("registry")
		var legacy: String = reg.legacy_of(String(row["ct"])) if reg != null else ""
		if legacy.begins_with("rc:"):
			_end_contract(rc, legacy.substr(3))
	if was_leader:
		o["leader"] = ""
		_succeed(oid, why)


func _end_contract(rc: RefCounted, cid: String) -> void:
	var c: Dictionary = rc.contract(cid)
	if not c.is_empty() and String(c.get("st", "")) == "active":
		rc.dismiss(String(c["fid"]), 0)


# ------------------------------------------------------------------ leaving (only the free follow)

## `ch` leaves. `take` are members who would follow them (empty = everyone they sponsored). Only the legally free go: not bound by a
## contract or oath, not an officer holding a post. Bound ones stay. A bound leaver is in breach (reputation and trust cost).
## `to_org` seats the followers there as probationers. For the player, org-chain recruits stay with the organization
## (recruitment.gd resign) and personal followers stay with the player.
func leave(oid: String, ch: String, take := [], to_org := "") -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not is_member(oid, ch):
		return {"ok": false, "reason": "Not a member."}
	var row: Dictionary = o["m"][ch]
	var breach := int(row["b"]) != 0
	var want: Array = take.duplicate()
	if want.is_empty():
		for f: String in o["m"]:
			if f != ch and String(o["m"][f]["sp"]) == ch:
				want.append(f)
	var went: Array = []
	var stayed: Array = []
	for f: String in want:
		if not is_member(oid, f) or f == ch:
			continue
		var fr: Dictionary = o["m"][f]
		var free := int(fr["b"]) == 0 and int(fr["r"]) < D.OFFICER and String(o["leader"]) != f
		if free:
			went.append(f)
		else:
			stayed.append(f)
	for f2: String in went:
		_remove(oid, f2, "followed " + ch)
		_c[f2]["fol"] = ch
		if to_org != "" and _o.has(to_org) and join_conflict(to_org, f2) == "" and member_count(to_org) < capacity(to_org):
			_add_member(to_org, f2, D.PROBATION, ch)
	if breach:
		add_reputation(ch, -LEAVE_BREACH_REP)
		stats["fees"] = int(stats["fees"]) + 0
	var rc := _mod("recruitment")
	if _is_player(ch) and rc != null:
		rc.resign(oid)
	_remove(oid, ch, "left")
	if to_org != "" and _o.has(to_org) and join_conflict(to_org, ch) == "":
		_add_member(to_org, ch, D.MEMBER, "")
	_hist(o, "%s left with %d followers" % [ch, went.size()])
	_ev("contract", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [ch, oid], "left_org", "%s leaves %s" % [ch, o["name"]], 2)
	if member_count(oid) == 0 and String(o["st"]) == "active":
		_close(oid, "empty")
	return {"ok": true, "followed": went, "stayed": stayed, "breach": breach}


# ------------------------------------------------------------------ succession

func set_succession(oid: String, by: String, mode: String, heir := "") -> bool:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or mode not in D.SUCCESSION or not can(oid, by, "charter"):
		return false
	o["succ"]["mode"] = mode
	o["succ"]["heir"] = heir
	return true


func name_successor(oid: String, by: String, ch: String) -> bool:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "appoint") or not is_member(oid, ch) or ch == by:
		return false
	o["succ"]["heir"] = ch
	return true


func _score(oid: String, ch: String) -> float:
	var m: Dictionary = _o[oid]["m"][ch]
	return float(m["c"]) + float(m["t"]) * 0.5 + skill_of(ch, String(type_of(oid).get("skill", ""))) * 30.0 + float(m["r"]) * 12.0


## A seat falls empty. Election: voters (vote right) back who they trust and respect; appointment: the named heir, else the best officer;
## heredity: the heir if they are a member, else an election; challenge: the strongest officer takes it.
func _succeed(oid: String, why: String) -> void:
	var o: Dictionary = _o[oid]
	var pool: Array = []
	for ch: String in o["m"]:
		if int(o["m"][ch]["r"]) >= D.PROBATION + 1:
			pool.append(ch)
	if pool.is_empty():
		_close(oid, "no one left")
		return
	pool.sort()
	var mode := String(o["succ"]["mode"])
	var heir := String(o["succ"]["heir"])
	var winner := ""
	if (mode == "appointment" or mode == "heredity") and heir != "" and is_member(oid, heir):
		winner = heir
	elif mode == "challenge":
		var best := -1.0
		for ch2: String in pool:
			var s := _score(oid, ch2) + _rng("succ", _day, [oid, ch2]).randf() * 10.0
			if s > best:
				best = s
				winner = ch2
	else:
		var cands: Array = []
		for ch3: String in pool:
			if int(o["m"][ch3]["r"]) >= D.OFFICER:
				cands.append(ch3)
		if cands.is_empty():
			cands = pool
		var votes := {}
		for v: String in pool:
			if not can(oid, v, "vote"):
				continue
			var pick := ""
			var pb := -1e9
			for cd: String in cands:
				var s2 := _score(oid, cd) + (8.0 if String(o["m"][cd]["sp"]) == v else 0.0) + _rng("vote", _day, [oid, v, cd]).randf() * 14.0
				if s2 > pb:
					pb = s2
					pick = cd
			votes[pick] = int(votes.get(pick, 0)) + 1
		var top := -1
		var ks := votes.keys()
		ks.sort()
		for k: String in ks:
			if int(votes[k]) > top:
				top = int(votes[k])
				winner = k
		stats["elections"] = int(stats["elections"]) + 1
	if winner == "":
		winner = String(pool[0])
	_install_leader(oid, winner)
	o["succ"]["heir"] = ""
	_ev("succession", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [winner, oid], "by_" + mode, "%s leads %s (%s)" % [winner, o["name"], why], 3)


func _install_leader(oid: String, ch: String) -> void:
	var o: Dictionary = _o[oid]
	for other: String in o["m"]:
		if int(o["m"][other]["r"]) == D.LEADER and other != ch:
			_set_rank(o, other, D.OFFICER)
	_set_rank(o, ch, D.LEADER)
	o["m"][ch]["pd"] = -1
	o["leader"] = ch
	_hist(o, "%s takes the lead" % ch)


## A member with rank >= officer challenges the leader (spec §5 succession by challenge). Returns {ok, won}.
func challenge(oid: String, ch: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not is_member(oid, ch) or rank_of(oid, ch) < D.OFFICER or String(o["leader"]) == ch or String(o["leader"]) == "":
		return {"ok": false, "reason": "You cannot challenge."}
	if _day - int(o["cd"]) < 14:
		return {"ok": false, "reason": "The last challenge was too recent."}
	o["cd"] = _day
	var lead: String = o["leader"]
	var a := _score(oid, ch) + _rng("chal", _day, [oid, ch]).randf() * 20.0
	var b := _score(oid, lead) + _rng("chal", _day, [oid, lead]).randf() * 20.0 + 6.0
	stats["challenges"] = int(stats["challenges"]) + 1
	if a > b:
		_set_rank(o, lead, D.OFFICER)
		o["m"][lead]["t"] = maxf(0.0, float(o["m"][lead]["t"]) - 20.0)
		_install_leader(oid, ch)
		_ev("succession", "", [ch, oid], "challenge", "%s unseats the leader" % ch, 4)
		return {"ok": true, "won": true}
	_set_rank(o, ch, D.VETERAN)
	o["m"][ch]["t"] = maxf(0.0, float(o["m"][ch]["t"]) - 25.0)
	o["strife"] = float(o["strife"]) + 2.0
	return {"ok": true, "won": false}


# ------------------------------------------------------------------ assets: the org's versus the members'

func add_asset(owner: String, kind: String, nm: String, value: int) -> String:
	var aid := "a%d" % _next_a
	_next_a += 1
	_a[aid] = {"id": aid, "kind": kind, "name": nm, "value": value, "owner": owner}
	if Reg.prefix_of(owner) == "org" and _o.has(owner):
		(_o[owner]["assets"] as Array).append(aid)
	else:
		ensure_char(owner)
		(_c[owner]["own"] as Array).append(aid)
	return aid


func asset(aid: String) -> Dictionary:
	return _a.get(aid, {})


func assets_of(oid: String) -> Array:
	return (_o.get(oid, {}).get("assets", []) as Array).duplicate()


func assets_owned_by(ch: String) -> Array:
	return (_c.get(ch, {}).get("own", []) as Array).duplicate()


## A member lends an asset to the organization: ownership does not move (the axes stay separate). A gift (`donate`) moves it.
func donate_asset(aid: String, ch: String, oid: String) -> bool:
	var a: Dictionary = _a.get(aid, {})
	if a.is_empty() or String(a["owner"]) != ch or not is_member(oid, ch):
		return false
	(_c[ch]["own"] as Array).erase(aid)
	a["owner"] = oid
	(_o[oid]["assets"] as Array).append(aid)
	record_activity(oid, ch, float(a["value"]) * 0.05, "gift")
	return true


func _release_assets(oid: String, to: String) -> int:
	var v := 0
	var l: Array = _o[oid]["assets"]
	for aid: String in l:
		v += int(_a[aid]["value"])
		if to != "" and _o.has(to):
			_a[aid]["owner"] = to
			(_o[to]["assets"] as Array).append(aid)
		else:
			_a.erase(aid)
	_o[oid]["assets"] = []
	return v


# ------------------------------------------------------------------ disputes

func open_dispute(oid: String, a: String, b: String, kind: String, text := "") -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not is_member(oid, a):
		return {"ok": false, "reason": "Only a member can bring a dispute."}
	if (o["dis"] as Array).size() >= 6:
		return {"ok": false, "reason": "The hall is full of grievances already."}
	var d := {"id": "d%d" % _next_d, "a": a, "b": b, "k": kind, "t": text.substr(0, 60), "day": _day, "st": "open"}
	_next_d += 1
	o["dis"].append(d)
	o["strife"] = float(o["strife"]) + 1.0
	_wake(oid, _day + 1)
	stats["disputes"] = int(stats["disputes"]) + 1
	return {"ok": true, "id": d["id"]}


func disputes(oid: String, only_open := true) -> Array:
	var out: Array = []
	for d: Dictionary in _o.get(oid, {}).get("dis", []):
		if not only_open or String(d["st"]) == "open":
			out.append(d.duplicate())
	return out


## A member with the judge right rules: "a" for the complainant, "b" for the accused, "both" (a warning to both), or "dismiss".
func resolve_dispute(oid: String, by: String, did: String, ruling: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "judge"):
		return {"ok": false, "reason": "You are not the judge here."}
	for d: Dictionary in o["dis"]:
		if String(d["id"]) == did and String(d["st"]) == "open":
			return _rule(oid, d, ruling)
	return {"ok": false, "reason": "No such open dispute."}


func _rule(oid: String, d: Dictionary, ruling: String) -> Dictionary:
	var o: Dictionary = _o[oid]
	d["st"] = "ruled"
	d["ruling"] = ruling
	var a: String = d["a"]
	var b: String = d["b"]
	var ma: Dictionary = o["m"].get(a, {})
	var mb: Dictionary = o["m"].get(b, {})
	match ruling:
		"a":
			if not mb.is_empty():
				mb["t"] = maxf(0.0, float(mb["t"]) - 12.0)
			if not ma.is_empty():
				ma["t"] = minf(100.0, float(ma["t"]) + 6.0)
			o["strife"] = maxf(0.0, float(o["strife"]) - 1.0)
		"b":
			if not ma.is_empty():
				ma["t"] = maxf(0.0, float(ma["t"]) - 12.0)
			if not mb.is_empty():
				mb["t"] = minf(100.0, float(mb["t"]) + 6.0)
			o["strife"] = maxf(0.0, float(o["strife"]) - 1.0)
		"both":
			for m: Dictionary in [ma, mb]:
				if not m.is_empty():
					m["t"] = maxf(0.0, float(m["t"]) - 4.0)
			o["strife"] = maxf(0.0, float(o["strife"]) - 0.5)
		_:
			o["strife"] = maxf(0.0, float(o["strife"]) - 0.5)
	return {"ok": true}


func _rule_auto(oid: String, d: Dictionary) -> void:
	var o: Dictionary = _o[oid]
	var ra := rank_of(oid, String(d["a"]))
	var rb := rank_of(oid, String(d["b"]))
	if ra < 0 or rb < 0:
		_rule(oid, d, "dismiss")
		return
	var sa := _score(oid, String(d["a"])) + float(o["m"][d["a"]]["t"]) * 0.2
	var sb := _score(oid, String(d["b"])) + float(o["m"][d["b"]]["t"]) * 0.2
	_rule(oid, d, "a" if sa > sb + 10.0 else ("b" if sb > sa + 10.0 else "both"))


# ------------------------------------------------------------------ branches, mergers, splits, dissolution

func open_branch(oid: String, by: String, sid: int, leader: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not can(oid, by, "found_branch"):
		return {"ok": false, "reason": "You have no right to open a branch."}
	if not is_member(oid, leader) or leader == String(o["leader"]):
		return {"ok": false, "reason": "A branch is led by one of your own members."}
	if int(o["stage"]) < 3:
		return {"ok": false, "reason": "Only an established organization can spread."}
	if _o.size() >= ORG_CAP:
		return {"ok": false, "reason": "No more room in the realm."}
	if int(o["treasury"]) < BRANCH_COST:
		return {"ok": false, "reason": "A branch costs %d gold." % BRANCH_COST}
	o["treasury"] = int(o["treasury"]) - BRANCH_COST
	var bid := _new_org(String(o["type"]), "%s of %s" % [o["name"], _sname(sid)], sid, "autonomous" if not _is_player(leader) else "manual")
	var b: Dictionary = _o[bid]
	b["parent"] = oid
	b["treasury"] = BRANCH_COST / 2
	b["legal"] = "recognised"
	b["charter"] = {"text": "A branch of " + String(o["name"]), "day": _day}
	b["founders"] = [leader]
	b["leader"] = leader
	b["succ"]["mode"] = "appointment"
	_add_member(bid, leader, D.LEADER, by)
	_set_rank(o, leader, D.BRANCH_LEADER)
	(o["br"] as Array).append(bid)
	_restage(bid)
	_ev("founding", "ss:%d" % sid if sid >= 0 else "", [leader, bid], "branch", "%s opens a branch" % o["name"], 2)
	return {"ok": true, "org": bid}


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid].get("name", "town %d" % sid))
	return "town %d" % sid


## `into` swallows `gone`. Both leaders must agree (`gone`'s leader is `consent` unless it is in debt). Ranks are kept where seats allow.
func merge(into: String, gone: String, by: String, consent := true) -> Dictionary:
	var a: Dictionary = _o.get(into, {})
	var b: Dictionary = _o.get(gone, {})
	if a.is_empty() or b.is_empty() or into == gone or not can(into, by, "merge"):
		return {"ok": false, "reason": "You cannot merge them."}
	if not consent and int(b["treasury"]) >= 0:
		return {"ok": false, "reason": "The other side refuses."}
	if not (String(b["type"]) in (D.COMPAT_MERGE.get(String(a["type"]), []) as Array)):
		return {"ok": false, "reason": "They are not the same kind of body."}
	a["treasury"] = int(a["treasury"]) + int(b["treasury"])
	var moved := 0
	var bm: Dictionary = b["m"]
	for ch: String in bm.keys():
		_index(ch, gone, false)
		if (a["m"] as Dictionary).has(ch):
			a["m"][ch]["c"] = float(a["m"][ch]["c"]) + float(bm[ch]["c"])
			continue
		var rk := int(bm[ch]["r"])
		if rk >= D.LEADER:
			rk = D.OFFICER
		if rk >= D.OFFICER and count_at(into, rk) >= slots(into, rk):
			rk = D.VETERAN
		var row: Dictionary = (bm[ch] as Dictionary).duplicate()
		row["r"] = rk
		a["m"][ch] = row
		_index(ch, into, true)
		moved += 1
	b["m"] = {}
	_rebuild_rc(a)
	_rebuild_rc(b)
	_recount()
	_release_assets(gone, into)
	for br: String in b["br"]:
		if _o.has(br):
			_o[br]["parent"] = into
			(a["br"] as Array).append(br)
	a["rep"] = maxf(float(a["rep"]), float(b["rep"])) + minf(float(a["rep"]), float(b["rep"])) * 0.25
	b["br"] = []
	b["st"] = "merged"
	_plan(gone, _day + FOUNDED_KEEP + 1)
	b["merged"] = into
	b["end"] = _day
	b["treasury"] = 0
	var pa := String(b["parent"])
	if _o.has(pa):
		(_o[pa]["br"] as Array).erase(gone)
	stats["merged"] = int(stats["merged"]) + 1
	_hist(a, "merged with " + String(b["name"]))
	_restage(into)
	_ev("founding", "", [into, gone], "merger", "%s absorbs %s" % [a["name"], b["name"]], 3)
	return {"ok": true, "moved": moved}


## A faction under `leader` walks out and founds a new body. Only free members follow (the bound stay), and the new body takes a share of
## the treasury in proportion to the people it took.
func split(oid: String, leader: String, followers: Array, nm: String) -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or not is_member(oid, leader) or leader == String(o["leader"]) or _o.size() >= ORG_CAP:
		return {"ok": false, "reason": "There can be no schism."}
	for oid2: String in _o:
		if String(_o[oid2]["name"]) == nm and String(_o[oid2]["st"]) == "active":
			return {"ok": false, "reason": "That name is taken."}
	var total := member_count(oid)
	var go: Array = [leader]
	var stay: Array = []
	for f: String in followers:
		if f == leader or not is_member(oid, f) or f == String(o["leader"]):
			continue
		var fr: Dictionary = o["m"][f]
		if int(fr["b"]) == 0:
			go.append(f)
		else:
			stay.append(f)
	var nid := _new_org(String(o["type"]), nm, int(o["sid"]), "autonomous" if _c.get(leader, {}).get("npc", false) else "manual")
	var n: Dictionary = _o[nid]
	var share := int(float(maxi(0, int(o["treasury"]))) * float(go.size()) / float(maxi(1, total)) * 0.5)
	o["treasury"] = int(o["treasury"]) - share
	n["treasury"] = share
	n["split_from"] = oid
	n["founders"] = go.duplicate()
	n["leader"] = leader
	n["charter"] = {"text": "Broke from " + String(o["name"]), "day": _day}
	n["legal"] = "petitioned" if String(o["legal"]) == "recognised" else String(o["legal"])
	n["rep"] = float(o["rep"]) * 0.3
	for ch: String in go:
		var old: Dictionary = o["m"][ch]
		_remove_row_only(oid, ch)
		n["m"][ch] = {"r": D.LEADER if ch == leader else maxi(D.VETERAN, mini(int(old["r"]), D.OFFICER)), "s": _day, "c": float(old["c"]) * 0.5,
			"t": 70.0, "sp": leader, "b": 0, "ar": 0, "ct": "", "pd": -1, "k": float(old.get("k", 0.5))}
		_index(ch, nid, true)
	_rebuild_rc(n)
	_mcount += go.size()
	o["strife"] = 0.0
	if not (o["m"] as Dictionary).has(String(o["leader"])) and String(o["leader"]) != "":
		o["leader"] = ""
	stats["splits"] = int(stats["splits"]) + 1
	_restage(nid)
	_hist(o, "schism: %s left" % nm)
	_ev("founding", "", [leader, nid], "schism", "%s breaks from %s" % [nm, o["name"]], 3)
	return {"ok": true, "org": nid, "followed": go, "stayed": stay}


func _remove_row_only(oid: String, ch: String) -> void:
	var o: Dictionary = _o[oid]
	var row: Dictionary = o["m"][ch]
	(o["rcv"] as Array)[clampi(int(row["r"]), 0, 5)] -= 1
	o["ks"] = float(o["ks"]) - float(row.get("k", 0.5))
	o["m"].erase(ch)
	_mcount -= 1
	_index(ch, oid, false)


func dissolve(oid: String, by: String, reason := "dissolved") -> Dictionary:
	var o: Dictionary = _o.get(oid, {})
	if o.is_empty() or (by != "" and not can(oid, by, "dissolve")):
		return {"ok": false, "reason": "You cannot close it."}
	return {"ok": true, "paid": _close(oid, reason)}


## Closes an organization: arrears first, the rest split by contribution; assets pass to the parent or are sold into the pot; branches
## go free (or to the parent); members are released and their org contracts ended.
func _close(oid: String, reason: String) -> int:
	var o: Dictionary = _o[oid]
	if String(o["st"]) != "active":
		return 0
	var pot := maxi(0, int(o["treasury"]))
	pot += _release_assets(oid, String(o["parent"]) if _o.has(String(o["parent"])) and String(_o[o["parent"]]["st"]) == "active" else "")
	var rows: Dictionary = o["m"]
	var owed_total := 0
	for ch: String in rows:
		owed_total += int(rows[ch]["ar"])
	var paid := 0
	for ch2: String in rows:
		var due := int(rows[ch2]["ar"])
		var take := mini(due, pot)
		if take > 0:
			pot -= take
			paid += take
			earn(ch2, take)
	if pot > 0 and not rows.is_empty():
		var tc := 0.0
		for ch3: String in rows:
			tc += float(rows[ch3]["c"]) + 1.0
		var share_total := pot
		for ch4: String in rows:
			var part := int(float(share_total) * (float(rows[ch4]["c"]) + 1.0) / tc)
			if part > 0:
				earn(ch4, part)
				pot -= part
	var rc := _mod("recruitment")
	if rc != null:
		rc.resign(oid)
	var members_list: Array = rows.keys()
	for ch5: String in members_list:
		_index(ch5, oid, false)
		if String(_c.get(ch5, {}).get("emp", {}).get("by", "")) == oid:
			unemploy(ch5)
	var parent := String(o["parent"])
	for br: String in o["br"]:
		if _o.has(br):
			_o[br]["parent"] = parent if _o.has(parent) and String(_o[parent]["st"]) == "active" else ""
			if _o.has(parent) and String(_o[parent]["st"]) == "active":
				(_o[parent]["br"] as Array).append(br)
	if _o.has(parent):
		(_o[parent]["br"] as Array).erase(oid)
	_mcount -= (o["m"] as Dictionary).size()
	o["m"] = {}
	_rebuild_rc(o)
	o["app"] = {}
	o["br"] = []
	o["treasury"] = 0
	o["st"] = "dissolved"
	o["end"] = _day
	_hist(o, "closed: " + reason)
	stats["dissolved"] = int(stats["dissolved"]) + 1
	_plan(oid, _day + FOUNDED_KEEP + 1)
	_ev("founding", "ss:%d" % int(o["sid"]) if int(o["sid"]) >= 0 else "", [oid], "dissolved", "%s closes (%s)" % [o["name"], reason], 3)
	return paid


# ------------------------------------------------------------------ economy (one org, one week)

## One week of an organization's money. A body that is watched (the player belongs to it or leads it, or `watch()` was called) settles member
## by member through their purses. Every other body settles in closed form from rank counts (O(members) integer work), so 400 of them cost
## well under a millisecond a day; their members' personal purses are not simulated, only the body's own flows.
func _settle(oid: String, day: int) -> void:
	var o: Dictionary = _o[oid]
	var td := D.type_def(String(o["type"]))
	var rows: Dictionary = o["m"]
	var dues_mult := float(o["pol"]["dues"])
	var wage_mult := float(o["pol"]["wage"])
	var npc_run := String(o["mode"]) != "manual"
	var detail := bool(o["dt"])
	var w := 1.0 if detail else maxf(1.0, float(day - maxi(int(o["lw"]), int(o["born"]))) / 7.0)      # a far body settles several weeks in one closed-form step
	var pay_tab: Array = td.get("pay", [0, 0, 0, 0, 0, 0])
	var dues_base := float(td.get("dues", 0))
	var counts: Array = o["rcv"]
	var income := 0.0
	var n_all := rows.size()
	var skill_sum := float(o["ks"]) * float(n_all - int(counts[0])) / maxf(1.0, float(n_all))
	if detail:
		for ch: String in rows:
			var m: Dictionary = rows[ch]
			var rk := int(m["r"])
			var due := int(round(dues_base * dues_mult * float(D.BASE_DUES[rk])))
			if due > 0:
				if pay(ch, due):
					income += due
				else:
					m["t"] = maxf(0.0, float(m["t"]) - 3.0)
			m["t"] = minf(100.0, float(m["t"]) + 0.5)
	else:
		income += dues_base * dues_mult * (float(counts[1]) + float(counts[2]) + 0.5 * float(counts[3])) * w
	# Activity: real (record_activity) always; a delegated or autonomous body also works on its own, closed form.
	var act := float(o["act"])
	if npc_run:
		act += skill_sum * float(td.get("rate", 1.0)) * 0.8 * w
	income += act * float(td.get("yield", 1.0))
	o["rep"] = clampf(float(o["rep"]) * (REP_DECAY if w == 1.0 else pow(REP_DECAY, w)) + act * 0.6, 0.0, 100.0)
	o["act"] = 0.0
	var tre := float(o["treasury"]) + income
	# Rent, then salaries from the top rank down.
	var hq: Dictionary = o["hq"]
	var rent := int(round(float(hq.get("rent", 0)) * w))
	if rent > 0:
		if tre >= rent:
			tre -= rent
			o["late"] = 0
			stats["rent"] = int(stats["rent"]) + rent
		else:
			o["late"] = int(o["late"]) + 1
			if int(o["late"]) >= 3:
				o["hq"] = {}
				_hist(o, "lost the headquarters")
				_ev("founding", "", [oid], "evicted", "%s is evicted" % o["name"], 2)
	var unpaid := false
	var total_sal := 0.0
	if detail:
		for rk3 in D.RANK_COUNT:
			total_sal += float(counts[rk3]) * round(float(pay_tab[rk3]) * wage_mult)
	else:
		total_sal = w * wage_mult * (float(counts[0]) * float(pay_tab[0]) + float(counts[1]) * float(pay_tab[1]) + float(counts[2]) * float(pay_tab[2]) \
			+ float(counts[3]) * float(pay_tab[3]) + float(counts[4]) * float(pay_tab[4]) + float(counts[5]) * float(pay_tab[5]))
	if detail:
		for ch2: String in rows:
			total_sal += float(rows[ch2]["ar"])
	if tre >= total_sal:
		tre -= total_sal
		if detail:
			for ch3: String in rows:
				var m3: Dictionary = rows[ch3]
				var sal := int(round(float(pay_tab[int(m3["r"])]) * wage_mult)) + int(m3["ar"])
				if sal > 0:
					earn(ch3, sal)
				m3["ar"] = 0
		o["owed"] = 0
	else:
		unpaid = true
		if detail:
			var order: Array = rows.keys()
			order.sort_custom(func(a: String, b: String) -> bool:
				var ra := int(rows[a]["r"])
				var rb := int(rows[b]["r"])
				return ra > rb or (ra == rb and a < b))
			for ch4: String in order:
				var m4: Dictionary = rows[ch4]
				var sal2 := int(round(float(pay_tab[int(m4["r"])]) * wage_mult)) + int(m4["ar"])
				if sal2 <= 0:
					continue
				if tre >= sal2:
					tre -= sal2
					earn(ch4, sal2)
					m4["ar"] = 0
				else:
					m4["ar"] = sal2
					m4["t"] = maxf(0.0, float(m4["t"]) - 4.0)
		else:
			var left := tre
			for rk4 in range(D.RANK_COUNT - 1, -1, -1):
				var need: float = w * float(counts[rk4]) * round(float(pay_tab[rk4]) * wage_mult)
				left -= minf(left, need)
			tre = left
		o["owed"] = int(o.get("owed", 0)) + 1
	tre -= 0.4 * float(rows.size()) * w
	# A branch sends a tenth of its week up.
	var parent: String = o["parent"]
	if parent != "" and _o.has(parent) and income > 0.0 and tre > 0.0:
		var tribute := income * BRANCH_TRIBUTE
		tre -= tribute
		_o[parent]["treasury"] = int(_o[parent]["treasury"]) + int(tribute)
	o["treasury"] = int(floor(tre))
	if unpaid or tre < 0.0:
		o["nw"] = int(o["nw"]) + int(w)
		o["sw"] = 0
		o["strife"] = float(o["strife"]) + w
	else:
		o["nw"] = 0
		o["sw"] = int(o["sw"]) + int(w)
		o["strife"] = maxf(0.0, float(o["strife"]) - 0.5 * w)
	o["lw"] = day
	o["off"] = _offer_base(o)
	if int(o["nw"]) >= 8 or (rows.is_empty() and String(o["st"]) == "active"):
		_close(oid, "bankrupt" if int(o["nw"]) >= 8 else "empty")
		return
	if npc_run and (day / 7 + int(o["n"])) % 3 == 0 or w > 1.0:
		_week_politics(oid, day, counts)
	if int(o["stage"]) < 4:
		_restage(oid)


## Days between two settlements: a watched, young or troubled body every week; a quiet far one every four.
func _gap(o: Dictionary) -> int:
	if bool(o["dt"]) or int(o["stage"]) < 3 or int(o["nw"]) > 0 or float(o["strife"]) >= 3.0 or int(o["late"]) > 0 or not (o["app"] as Dictionary).is_empty():
		return 7
	return FAR_DAYS


func _offer_base(o: Dictionary) -> float:
	var td := D.type_def(String(o["type"]))
	return float((td.get("pay", [0, 0]) as Array)[1]) * float(o["pol"]["wage"]) * 2.0 + float(o["rep"]) * 0.3 \
		- float(td.get("dues", 0)) * float(o["pol"]["dues"]) + (4.0 if int(o["treasury"]) > 0 else -8.0) + float(int(o["stage"]))


## Weekly politics of a body that runs itself: one promotion, a leaderless seat, grievances and, when strife runs high, a schism.
func _week_politics(oid: String, day: int, counts: Array) -> void:
	var o: Dictionary = _o[oid]
	var rows: Dictionary = o["m"]
	if String(o["leader"]) == "" and not rows.is_empty():
		_succeed(oid, "vacant")
	# The best candidate who clears the bar for the next rank, seats permitting; the highest-ranked member with the right promotes.
	var n := rows.size()
	var by := ""
	var by_r := -1
	var best := ""
	var best_c := -1.0
	for ch: String in rows:
		var m: Dictionary = rows[ch]
		var rk := int(m["r"])
		if rk > by_r or (rk == by_r and ch < by):
			if rk >= D.OFFICER:
				by = ch
				by_r = rk
		if rk < D.BRANCH_LEADER and float(m["c"]) > best_c and int(m["pd"]) < 0:
			var nxt := rk + 1
			if float(m["c"]) >= float(D.BASE_NEED[nxt]) and float(m["t"]) >= 40.0 + 6.0 * float(nxt):
				var sl := 9999 if D.BASE_SLOTS[nxt] == -1 else (maxi(1, ceili(float(n) * -float(D.BASE_SLOTS[nxt]))) if float(D.BASE_SLOTS[nxt]) < 0.0 else int(D.BASE_SLOTS[nxt]))
				if int(counts[nxt]) < sl:
					best = ch
					best_c = float(m["c"])
	if by != "" and best != "" and best != by:
		promote(oid, by, best)
	# Grievances: a body in need of pay breeds them; a rank gap and a slight make one.
	var roll := float(absi(hash([WorldSim.SEED, "odis", day, oid])) % 1000) / 1000.0
	if n >= 4 and (o["dis"] as Array).size() < 4 and roll < 0.04 + float(o["strife"]) * 0.02:
		var r := _rng("odis", day, oid)
		var ks: Array = rows.keys()
		var a: String = ks[r.randi() % ks.size()]
		var b: String = ks[r.randi() % ks.size()]
		if a != b:
			open_dispute(oid, a, b, ["pay", "rank", "honour", "policy"][r.randi() % 4], "a grievance")
	if float(o["strife"]) >= SCHISM_AT and n >= 6:
		_auto_schism(oid)


func _auto_schism(oid: String) -> void:
	var o: Dictionary = _o[oid]
	var best := ""
	var bs := -1e9
	for ch: String in members_of(oid, D.OFFICER):
		if ch == String(o["leader"]):
			continue
		var s := _score(oid, ch) - float(o["m"][ch]["t"]) * 0.3
		if s > bs:
			bs = s
			best = ch
	if best == "":
		o["strife"] = 0.0
		return
	var fol: Array = []
	for ch2: String in o["m"]:
		if ch2 != best and float(o["m"][ch2]["t"]) < 45.0:
			fol.append(ch2)
	split(oid, best, fol, "%s Reformed" % String(o["name"]).substr(0, 24))


# ------------------------------------------------------------------ day tick

func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_day = day
	if auto_seed and not _seeded:
		_seed_actors()
	# The due queue: every body asked to be looked at on or before today (a skipped day is never lost).
	var due: Array = []
	var seen := {}
	for d: int in _sched.keys():
		if d <= day:
			for oid: String in _sched[d]:
				if not seen.has(oid):
					seen[oid] = true
					due.append(oid)
			_sched.erase(d)
	var out: Array = []
	var i := 0
	while i < due.size():
		var part := due.slice(i, i + ORG_CHUNK)
		out.append(func() -> Array: return _org_chunk(part, day))
		i += ORG_CHUNK
	out.append(func() -> Array: return _npc_day(day))
	out.append(func() -> Array: return _adapt_step(day))
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _org_chunk(ids: Array, day: int) -> Array:
	var msgs: Array = []
	for oid: String in ids:
		if not _o.has(oid):
			continue
		var o: Dictionary = _o[oid]
		if String(o["st"]) != "active":
			if day - int(o.get("end", day)) > FOUNDED_KEEP:
				_o.erase(oid)
				_ord = []
				_sidx_ok = false
			else:
				_plan(oid, day + FOUNDED_KEEP / 2)
			continue
		if int(o["pl"]) > day:
			continue                                   # an older wake-up; the live one is later
		if o.has("legacy"):
			_sync_legacy(oid)                          # a mirror of an old guild or career: it follows its source, nothing else
			o["pl"] = day + 7
			_plan(oid, day + 7)
			continue
		_org_day(oid, day, msgs)
		if day - int(o["lw"]) >= _gap(o) and String(o["st"]) == "active":
			_settle(oid, day)
	return msgs


func _org_day(oid: String, day: int, msgs: Array) -> void:
	var o: Dictionary = _o[oid]
	var gap := _gap(o)
	var nd := day + gap + (int(o["n"]) % 2 if gap == 7 else 0)      # a quiet far body is looked at once a month
	# Probation ends.
	if int((o["rcv"] as Array)[0]) > 0:
		for ch: String in o["m"].keys():
			var m: Dictionary = o["m"][ch]
			var pd := int(m["pd"])
			if pd >= 0:
				if day >= pd:
					if float(m["t"]) >= 40.0:
						_set_rank(o, ch, D.MEMBER)
						m["pd"] = -1
						m["s"] = day
						_ev("contract", "", [ch, oid], "member", "%s becomes a full member" % ch, 1)
					else:
						_remove(oid, ch, "failed probation")
						continue
				else:
					nd = mini(nd, pd)
	# Applications: a body that runs itself decides; a manual one waits for its player (applicants lose patience).
	var app: Dictionary = o["app"]
	for ch2: String in app.keys():
		if day - int(app[ch2]["d"]) >= APP_DAYS:
			app.erase(ch2)
			continue
		if String(o["mode"]) != "manual":
			var by := _recruiter(oid)
			if by != "":
				var ev := evaluate_application(oid, ch2)
				decide(oid, by, ch2, bool(ev["ok"]) and float(ev["score"]) >= 12.0)
				continue
		nd = mini(nd, day + 1)
	# Disputes the hall has left open too long are ruled by whoever sits highest.
	for d: Dictionary in o["dis"]:
		if String(d["st"]) == "open":
			if day - int(d["day"]) >= DISPUTE_RULE_DAYS:
				_rule_auto(oid, d)
			else:
				nd = mini(nd, int(d["day"]) + DISPUTE_RULE_DAYS)
	var keep: Array = []
	for d2: Dictionary in o["dis"]:
		if String(d2["st"]) == "open" or day - int(d2["day"]) < 20:
			keep.append(d2)
	if keep.size() != (o["dis"] as Array).size():
		o["dis"] = keep
	# Petition stub.
	var pid := String(o["pet"])
	if pid != "" and _pt.has(pid) and String(_pt[pid]["st"]) == "pending":
		if day - int(_pt[pid]["day"]) >= PETITION_DAYS:
			_stub_petition(_pt[pid])
		else:
			nd = mini(nd, int(_pt[pid]["day"]) + PETITION_DAYS)
	if String(o["mode"]) != "manual" and int(o["stage"]) < 3 and String(o["leader"]) != "":
		_npc_found_step(oid, day)
		nd = mini(nd, day + 3)
	o["nd"] = nd
	o["pl"] = nd
	_plan(oid, nd)
	if _pt.size() > 40:
		_prune_petitions()


func _prune_petitions() -> void:
	for pid: String in _pt.keys():
		if String(_pt[pid]["st"]) != "pending" and _day - int(_pt[pid]["day"]) > 60:
			_pt.erase(pid)


## Highest-ranked member with the recruit right (the one who runs admissions in a body that runs itself).
func _recruiter(oid: String) -> String:
	var rows: Dictionary = _o[oid]["m"]
	var best := ""
	var br := -1
	for ch: String in rows:
		var r := int(rows[ch]["r"])
		if r >= D.VETERAN and (r > br or (r == br and ch < best)) and can(oid, ch, "recruit"):
			best = ch
			br = r
	return best


# ------------------------------------------------------------------ NPCs (same calls as the player)

func _npc_list() -> Array:
	if not _npc_ok:
		_npc = []
		for ch: String in _c:
			if bool(_c[ch].get("npc", false)):
				_npc.append(ch)
		_npc.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(3)) < int(b.substr(3)))
		_npc_b = [[], [], []]
		for i in _npc.size():
			(_npc_b[i % NPC_CADENCE] as Array).append(_npc[i])
		_npc_ok = true
	return _npc


## NPC actors in a town with no employer (the labour pool for businesses).
func unemployed_npcs(sid: int, limit: int) -> Array:
	var out: Array = []
	for ch: String in _npc_list():
		var c: Dictionary = _c[ch]
		if int(c["sid"]) == sid and (c["emp"] as Dictionary).is_empty() and (_mem.get(ch, []) as Array).is_empty():
			out.append(ch)
			if out.size() >= limit:
				break
	return out


func npc_count() -> int:
	return _npc_list().size()


func _seed_actors() -> void:
	_seeded = true
	if WorldSim.ranges.is_empty() or ACTOR_SEED <= 0:
		return
	var reg := _mod("registry")
	if reg == null:
		return
	var per := maxi(1, ACTOR_SEED / WorldSim.ranges.size())
	for sid in WorldSim.ranges.size():
		var rg: Vector2i = WorldSim.ranges[sid]
		var count := rg.y - rg.x
		if count <= 0:
			continue
		for k in per:
			var row := rg.x + int(posmod(hash([WorldSim.SEED, "oact", sid, k]), count))
			if WorldSim.health[row] == 0:
				continue
			var ch: String = reg.ref("ws:%d" % row)
			if ch == "" or _c.has(ch):
				continue
			var jb := int(WorldSim.job[row])
			var profs := ["builder", "smith", "scout", "mercenary", "laborer", "hunter"]
			var prof: String = ["carpenter", "smith", "hunter", "mercenary", "farmer", "hunter"][jb % profs.size()]
			ensure_char(ch, {"prof": prof, "cash": int(WorldSim.money[row]) * 2, "sid": sid, "npc": true,
				"amb": ["found", "join", "join", "join"][absi(hash([WorldSim.SEED, "oamb", row])) % 4]})
	_npc_ok = false


func _types_for(prof: String) -> Array:
	if _types_cache.has(prof):
		return _types_cache[prof]
	var out: Array = []
	for t: String in D.TYPE_IDS:
		if prof in (D.TYPES[t]["prof"] as Array):
			out.append(t)
	_types_cache[prof] = out
	return out


## How attractive an organization is to a possible recruit: pay, name, fit and prospects.
func offer_score(oid: String, ch: String) -> float:
	var o: Dictionary = _o[oid]
	var td := D.type_def(String(o["type"]))
	return _offer_base(o) + (6.0 if profession(ch) in (td.get("prof", []) as Array) else -4.0)


func _npc_day(day: int) -> Array:
	var msgs: Array = []
	if _npc_list().is_empty():
		return msgs
	var bi := day % NPC_CADENCE
	var bucket: Array = _npc_b[bi]
	if bucket.is_empty():
		return msgs
	var ptr := int(_npc_ptr[bi])
	var todo := mini(NPC_PER_DAY, bucket.size())
	for k in todo:
		_decide(String(bucket[(ptr + k) % bucket.size()]), day)
	_npc_ptr[bi] = (ptr + todo) % bucket.size()
	return msgs


func _decide(ch: String, day: int) -> void:
	var c: Dictionary = _c[ch]
	var sid := int(c["sid"])
	var mine: Array = _mem.get(ch, [])
	var roll := float(absi(hash([WorldSim.SEED, "odc", day, ch])) % 1000) / 1000.0
	var amb_found := String(c["amb"]) == "found"
	# A business, when there is money and a taste for it (businesses.gd uses the same founding call as the player).
	if amb_found and roll < 0.12 and (c["own"] as Array).is_empty():
		var bm := _mod("businesses")
		if bm != null:
			bm.npc_try_found(ch, day)
	var types := _types_for(String(c["prof"]))
	if types.is_empty():
		return
	# Already seated in one fitting body: nothing more to decide.
	for oid: String in mine:
		if String(_o[oid]["type"]) in types:
			return
	if amb_found and roll > 0.5 and roll < 0.68:
		var t: String = types[int(roll * 1000.0) % types.size()]
		var td := D.type_def(t)
		if int(c["cash"]) >= int(td.get("found", 0)) + 30 and _o.size() < ORG_CAP and orgs_in(sid, t).size() < 2:
			var nm := _npc_org_name(t, sid, ch, _rng("onm", day, ch))
			var res := start_founding(ch, t, nm, sid, "autonomous")
			if bool(res.get("ok", false)):
				stats["npc_founded"] = int(stats["npc_founded"]) + 1
				return
	# Look for the best body that is hiring and fits.
	var cands: Array = []
	orgs_in(-9)                                                               # builds the town index
	for oid2: String in _sidx.get(sid, []):
		var o: Dictionary = _o.get(oid2, {})
		if o.is_empty() or int(o["stage"]) < 1 or String(o["st"]) != "active" or not (String(o["type"]) in types) or o.has("legacy"):
			continue
		if not bool(o["pol"]["open"]) or (o["m"] as Dictionary).size() >= capacity(oid2):
			continue
		cands.append([_offer_base(o) + 6.0, oid2])
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for cd: Array in cands:
		if join_conflict(String(cd[1]), ch) != "":
			continue
		if cands.size() >= 2:
			stats["contested"] = int(stats["contested"]) + 1
		var res2 := apply(String(cd[1]), ch, _recruiter(String(cd[1])))
		if bool(res2.get("ok", false)):
			stats["npc_joined"] = int(stats["npc_joined"]) + 1
		return


func _npc_org_name(t: String, sid: int, ch: String, r: RandomNumberGenerator) -> String:
	var label := String(D.TYPES[t]["label"])
	var nm := "%s of %s" % [label, _sname(sid)]
	var tries := 0
	while tries < 6:
		var clash := false
		for oid: String in _o:
			if String(_o[oid]["name"]) == nm and String(_o[oid]["st"]) == "active":
				clash = true
				break
		if not clash:
			return nm
		tries += 1
		nm = "%s %s of %s" % [["Free", "Old", "Grey", "United", "Honest", "Northern", "River"][r.randi() % 7], label, _sname(sid)]
	return "%s %d" % [nm, int(Reg.parse(ch).get("n", 0))]


## The next step of an NPC-led founding, using the player's own calls.
func _npc_found_step(oid: String, day: int) -> void:
	var o: Dictionary = _o[oid]
	var lead: String = o["leader"]
	if not bool(_c.get(lead, {}).get("npc", false)):
		return
	var td := type_of(oid)
	var sid := int(o["sid"])
	if member_count(oid) < int(td.get("min_founders", 2)):
		# Ask a friend: an unaffiliated NPC of a fitting profession in the same town.
		var r := _rng("ofound", day, oid)
		var lst := _npc_list()
		for k in 8:
			var ch: String = lst[r.randi() % lst.size()]
			if ch == lead or int(_c[ch]["sid"]) != sid or not (_mem.get(ch, []) as Array).is_empty():
				continue
			if _types_for(profession(ch)).is_empty() or r.randf() > 0.5:
				continue
			if add_founder(oid, lead, ch).get("ok", false):
				break
		return
	if (o["charter"] as Dictionary).is_empty():
		draft_charter(oid, lead, "We, the founders of %s, bind ourselves." % o["name"])
		return
	if String(o["legal"]) == "none":
		petition_recognition(oid, lead)
		return
	if (o["hq"] as Dictionary).is_empty() and String(o["legal"]) in ["recognised", "outlaw"]:
		rent_hq(oid, lead, sid)
		return


# ------------------------------------------------------------------ catch-up

func catch_up(days: int, _ctx: Dictionary) -> Array:
	var weeks := days / 7
	if weeks <= 0:
		_day += days
		return []
	for oid: String in org_ids():
		var o: Dictionary = _o[oid]
		if String(o["st"]) != "active":
			continue
		var before := int(o["treasury"])
		var d0 := _day
		_settle(oid, d0 + 7)
		if not _o.has(oid) or String(o["st"]) != "active":
			continue
		var net := int(o["treasury"]) - before
		var rest := weeks - 1
		if rest > 0:
			o["treasury"] = int(o["treasury"]) + net * rest
			o["rep"] = clampf(float(o["rep"]) * pow(REP_DECAY, float(rest)), 0.0, 100.0)
			if int(o["treasury"]) < -50 * maxi(1, member_count(oid)):
				_close(oid, "bankrupt")
		o["lw"] = d0 + days
	_day += days
	return []


# ------------------------------------------------------------------ adapters (existing guilds and careers)

## Mirrors an existing system's body as an organization record without touching the legacy state (legacy key "og:<kind>:<key>").
## kind: "city_guild" (city_life), "notable" (notables), "career" (soldier / scribe / trades). Returns the org id or "".
func adapt(kind: String, key: String) -> String:
	var reg := _mod("registry")
	if reg == null:
		return ""
	var lk := "og:%s:%s" % [kind, key]
	var existing: String = reg.lookup(lk)
	if existing != "" and _o.has(existing):
		_sync_legacy(existing)
		return existing
	if _o.size() >= ORG_CAP:
		return ""
	var oid: String = reg.ref(lk)
	if oid == "":
		return ""
	var type := ""
	var nm := key
	var sid := -1
	match kind:
		"city_guild":
			var cl := _mod("city_life")
			var g: Dictionary = cl.guild(key) if cl != null else {}
			if g.is_empty():
				return ""
			type = String(D.LEGACY_GUILD_KIND.get(String(g["kind"]), "craft_guild"))
			nm = String(g["name"])
			sid = int(g["sid"])
		"notable":
			var nt := _mod("notables")
			var found: Dictionary = {}
			if nt != null:
				for x: Dictionary in nt.orgs():
					if String(x["id"]) == key:
						found = x
			if found.is_empty():
				return ""
			type = String(D.LEGACY_NOTABLE_KIND.get(String(found["kind"]), ""))
			if type == "":
				return ""
			nm = String(found["n"])
			sid = int(found["sid"])
		"career":
			type = String(D.LEGACY_CAREER.get(key, ""))
			if type == "":
				return ""
			nm = "The %s career" % key.capitalize()
		_:
			return ""
	_new_org(type, nm, sid, "autonomous", oid)
	var rec: Dictionary = _o[oid]
	rec["legacy"] = {"kind": kind, "key": key}
	rec["stage"] = 4
	rec["legal"] = "recognised"
	rec["pol"]["open"] = true
	_sync_legacy(oid)
	return oid


## Refreshes an adapter record from its legacy source (treasury, leader, the player's seat).
func _sync_legacy(oid: String) -> void:
	var o: Dictionary = _o.get(oid, {})
	var lg: Dictionary = o.get("legacy", {})
	if lg.is_empty():
		return
	var pl := player_id()
	var key := String(lg["key"])
	var rank := -1
	match String(lg["kind"]):
		"city_guild":
			var cl := _mod("city_life")
			var g: Dictionary = cl.guild(key) if cl != null else {}
			if not g.is_empty():
				o["treasury"] = int(g["treasury"])
				rank = int(g["player"]["rank"])
		"notable":
			var nt := _mod("notables")
			if nt != null:
				for x: Dictionary in nt.orgs():
					if String(x["id"]) == key:
						var lead := String(x.get("leader", ""))
						var reg := _mod("registry")
						var lch: String = reg.ref("nt:" + lead) if reg != null and lead != "" else ""
						if lch != "" and not (o["m"] as Dictionary).has(lch):
							ensure_char(lch)
							o["m"][lch] = {"r": D.LEADER, "s": _day, "c": 0.0, "t": 70.0, "sp": "", "b": 0, "ar": 0, "ct": "", "pd": -1, "k": 0.5}
							_index(lch, oid, true)
							o["leader"] = lch
						o["rep"] = float(x.get("power", 0.0))
		"career":
			rank = _career_rank(key)
	var m: Dictionary = o["m"]
	if rank >= 0:
		rank = clampi(rank, 0, D.LEADER)
		if m.has(pl):
			m[pl]["r"] = rank
		else:
			m[pl] = {"r": rank, "s": _day, "c": 0.0, "t": 60.0, "sp": "", "b": 0, "ar": 0, "ct": "", "pd": -1, "k": 0.5}
			_index(pl, oid, true)
			ensure_char(pl)
		if rank == D.LEADER:
			o["leader"] = pl
	elif m.has(pl):
		m.erase(pl)
		_index(pl, oid, false)
	_rebuild_rc(o)
	_recount()


func _career_rank(career: String) -> int:
	match career:
		"soldier":
			var s := _mod("soldier")
			return int(s.get("rank")) if s != null and bool(s.get("active")) else -1
		"scribe":
			var sc := _mod("scribe")
			return clampi(sc.level() / 10, 0, 5) if sc != null and sc.has_method("level") and sc.level() > 0 else -1
		_:
			var tr := _mod("trades")
			if tr != null and tr.has_method("is_member") and tr.is_member(career):
				return 1
	return -1


## Mirrors the existing guilds, notable organizations and careers a few at a time (a month later it looks for new ones), so the
## adapters never cost a frame.
func _adapt_step(day: int) -> Array:
	if not auto_seed:
		return []
	if _adapt_todo.is_empty():
		if day < _adapt_next:
			return []
		_adapt_next = day + 28
		var cl := _mod("city_life")
		if cl != null:
			for g: Dictionary in cl.guilds():
				_adapt_todo.append(["city_guild", String(g["id"])])
		var nt := _mod("notables")
		if nt != null:
			for x: Dictionary in nt.orgs():
				_adapt_todo.append(["notable", String(x["id"])])
		for career: String in D.LEGACY_CAREER:
			_adapt_todo.append(["career", career])
	var n := 0
	while not _adapt_todo.is_empty() and n < 6:
		var it: Array = _adapt_todo.pop_back()
		adapt(String(it[0]), String(it[1]))
		n += 1
	return []


## Mirrors every guild of city_life, every notable organization and every career once. Bounded by ORG_CAP. Returns how many exist.
func adapt_all() -> int:
	var cl := _mod("city_life")
	if cl != null:
		for g: Dictionary in cl.guilds():
			adapt("city_guild", String(g["id"]))
	var nt := _mod("notables")
	if nt != null:
		for x: Dictionary in nt.orgs():
			adapt("notable", String(x["id"]))
	for career: String in D.LEGACY_CAREER:
		adapt("career", career)
	var n := 0
	for oid: String in _o:
		if (_o[oid] as Dictionary).has("legacy"):
			n += 1
	return n


# ------------------------------------------------------------------ save

func _blank_org() -> Dictionary:
	return {"st": "active", "stage": 0, "leader": "", "founders": [], "hq": {}, "charter": {}, "legal": "none", "treasury": 0,
		"pol": {"dues": 1.0, "wage": 1.0, "open": true}, "app": {}, "dis": [], "parent": "", "br": [], "assets": [], "rep": 0.0, "act": 0.0,
		"strife": 0.0, "sw": 0, "nw": 0, "late": 0, "hist": [], "pet": "", "cd": -100, "split_from": "", "merged": "", "owed": 0}


## Member rows are stored as arrays and an org only writes the fields that differ from a blank one (the doc's save budget).
func _pack_org(o: Dictionary) -> Dictionary:
	var blank := _blank_org()
	var out := {}
	for k: String in o:
		if k == "id" or k == "m" or k == "rcv" or k == "ks" or k == "pl" or k == "nd":
			continue
		if blank.has(k) and o[k] == blank[k]:
			continue
		out[k] = o[k]
	var rows := {}
	var m: Dictionary = o["m"]
	for ch: String in m:
		var r: Dictionary = m[ch]
		rows[ch] = [r["r"], r["s"], r["c"], r["t"], r["sp"], r["b"], r["ar"], r["ct"], r["pd"], r["k"]]
	out["m"] = rows
	return out


func _unpack_org(oid: String, v: Dictionary) -> Dictionary:
	var o := _blank_org()
	o["id"] = oid
	for k: String in v:
		if k != "m":
			o[k] = v[k]
	var m := {}
	var rows: Dictionary = v.get("m", {})
	for ch: String in rows:
		var a: Array = rows[ch]
		m[ch] = {"r": a[0], "s": a[1], "c": a[2], "t": a[3], "sp": a[4], "b": a[5], "ar": a[6], "ct": a[7], "pd": a[8], "k": a[9] if a.size() > 9 else 0.5}
	o["m"] = m
	o["rcv"] = [0, 0, 0, 0, 0, 0]
	o["ks"] = 0.0
	o["pl"] = 0
	o["nd"] = 0
	return o


func _pack_char(c: Dictionary) -> Dictionary:
	var out := {}
	if String(c["prof"]) != "":
		out["prof"] = c["prof"]
	if not (c["emp"] as Dictionary).is_empty():
		out["emp"] = c["emp"]
	if int(c["cash"]) != 0:
		out["cash"] = c["cash"]
	if int(c["sid"]) != -1:
		out["sid"] = c["sid"]
	if not (c["sk"] as Dictionary).is_empty():
		out["sk"] = c["sk"]
	if float(c["rep"]) != 0.0:
		out["rep"] = c["rep"]
	if bool(c["npc"]):
		out["npc"] = true
	if String(c["amb"]) != "":
		out["amb"] = c["amb"]
	if not (c["own"] as Array).is_empty():
		out["own"] = c["own"]
	if String(c["fol"]) != "":
		out["fol"] = c["fol"]
	return out


func serialize() -> Dictionary:
	var packed := {}
	for oid: String in _o:
		packed[oid] = _pack_org(_o[oid])
	var chars := {}
	for ch: String in _c:
		var pc := _pack_char(_c[ch])
		if not pc.is_empty():
			chars[ch] = pc
	return {"o": packed, "c": chars, "a": _a.duplicate(true), "pt": _pt.duplicate(true), "nd": _next_d, "na": _next_a,
		"np": _next_p, "day": _day, "seeded": _seeded, "st": stats.duplicate(), "pg": pending_gold}


func deserialize(d: Dictionary) -> void:
	_o = {}
	_c = {}
	_a = {}
	_pt = {}
	_mem = {}
	_ord = []
	_sidx_ok = false
	_npc_ok = false
	var o: Variant = d.get("o", {})
	if o is Dictionary:
		for k: String in o:
			var v: Variant = o[k]
			if v is Dictionary:
				_o[k] = _fix_org(_unpack_org(k, v))
	var c: Variant = d.get("c", {})
	if c is Dictionary:
		for k: String in c:
			if c[k] is Dictionary:
				var cd: Dictionary = c[k]
				_c[k] = {"prof": String(cd.get("prof", "")), "emp": cd.get("emp", {}), "cash": int(cd.get("cash", 0)), "sid": int(cd.get("sid", -1)),
					"sk": cd.get("sk", {}), "rep": float(cd.get("rep", 0.0)), "npc": bool(cd.get("npc", false)), "amb": String(cd.get("amb", "")),
					"own": cd.get("own", []), "fol": String(cd.get("fol", ""))}
	var a: Variant = d.get("a", {})
	if a is Dictionary:
		for k: String in a:
			_a[k] = a[k]
	var pt: Variant = d.get("pt", {})
	if pt is Dictionary:
		for k: String in pt:
			_pt[k] = pt[k]
	_sched = {}
	for oid: String in _o:
		for ch: String in _o[oid]["m"]:
			_index(ch, oid, true)
			if not _c.has(ch):
				ensure_char(ch)
		_rebuild_rc(_o[oid])
		_o[oid]["pl"] = int(d.get("day", 0)) + 1 + (int(Reg.parse(oid).get("n", 0)) % 7)
		_plan(oid, int(_o[oid]["pl"]))
	_recount()
	_pl = ""
	_next_d = int(d.get("nd", 1))
	_next_a = int(d.get("na", 1))
	_next_p = int(d.get("np", 1))
	_day = int(d.get("day", 0))
	_seeded = bool(d.get("seeded", false))
	pending_gold = int(d.get("pg", 0))
	var st: Variant = d.get("st", {})
	if st is Dictionary:
		for k: String in st:
			stats[k] = int(st[k])


## JSON turns ints into floats; put the integer fields back so comparisons and match keys behave.
func _fix_org(v: Dictionary) -> Dictionary:
	var o: Dictionary = v.duplicate(true)
	for k: String in ["sid", "stage", "treasury", "born", "lw", "nd", "sw", "nw", "late", "cd", "owed", "n", "pl"]:
		o[k] = int(o.get(k, 0))
	o["strife"] = float(o.get("strife", 0.0))
	o["rep"] = float(o.get("rep", 0.0))
	o["act"] = float(o.get("act", 0.0))
	o["off"] = float(o.get("off", 0.0))
	var m: Dictionary = o.get("m", {})
	for ch: String in m:
		var r: Dictionary = m[ch]
		r["r"] = int(r["r"])
		r["s"] = int(r["s"])
		r["b"] = int(r["b"])
		r["ar"] = int(r["ar"])
		r["pd"] = int(r["pd"])
		r["k"] = float(r.get("k", 0.5))
		r["c"] = float(r["c"])
		r["t"] = float(r["t"])
	var rk: Dictionary = o.get("rk", {})
	if not rk.is_empty():
		o["rk"] = rk
	for k2: String in ["app", "dis", "br", "assets", "hist", "founders"]:
		if not o.has(k2):
			o[k2] = {} if k2 == "app" else []
	for d2: Dictionary in o["dis"]:
		d2["day"] = int(d2["day"])
	for ch2: String in (o["app"] as Dictionary):
		o["app"][ch2]["d"] = int(o["app"][ch2]["d"])
	if (o["hq"] as Dictionary).has("rent"):
		o["hq"]["rent"] = int(o["hq"]["rent"])
		o["hq"]["sid"] = int(o["hq"]["sid"])
		o["hq"]["since"] = int(o["hq"]["since"])
	if o.has("end"):
		o["end"] = int(o["end"])
	if o.has("pd"):
		o["pd"] = int(o["pd"])
	return o
