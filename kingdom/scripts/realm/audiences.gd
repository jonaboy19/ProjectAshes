extends "res://scripts/realm/realm_module.gd"
## Petitions and audiences (Living World section 7, LW-6.2). One pipeline for the player, NPCs, organisations and settlements.
##
##  1 identify   which office can answer this petition (stewardship.chain), what it wants and how long it takes
##  2 access     the clerk, steward or chamberlain lets you in only if your fame, rank or sponsors are enough; the king is rare and earned
##  3 present    you lay the evidence on the table: deeds, witnesses, recommendations, surveys, charters
##  4 wait       the queue at that office; longer at the top
##  5 audience   attend(): the holder hears you (a talk sheet: lines and choices) and states a verdict with reasons
##  6 negotiate  taxes, levies, building limits, loyalty, term; offers and counters, three rounds at most
##  7 document   a charter, licence, grant or commission, with terms, an issuer and an expiry
##  8 enforce    others may dispute it; breaches and arrears suspend or revoke it; a new ruler reviews what the old one granted
## Types: settlement and organisation recognition (resolving the founding.gd and organizations.gd stubs), land, title, mining rights,
## trade rights, military aid, tax relief, disputes, amnesty, office. NPCs file the same petitions (one new one a day at most).

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const OrgScript := preload("res://scripts/realm/organizations.gd")

const AUDIENCE_WINDOW := 10
const COOLDOWN := 10
const QUEUE_STEP := 2
const MAX_ROUNDS := 3
const PET_MAX := 120
const DOC_MAX := 300
const DIS_MAX := 60
const NPC_ACTIVE_MAX := 24
const PROXY_PER_DAY := 4
const REVIEW_DAYS := 30
const ARREARS_WARN := 4
const ARREARS_REVOKE := 8
const STEPS := ["identify", "access", "present", "wait", "audience", "negotiate", "document", "enforce"]

var _pt: Dictionary = {}        # pid -> petition
var _doc: Dictionary = {}       # did -> document
var _dis: Dictionary = {}       # xid -> dispute
var _rank: Dictionary = {}      # person id -> {r, title, day}
var _spons: Dictionary = {}     # person id -> [[sponsor id, name, rank], ...]
var _cool: Dictionary = {}      # "by|type|sid" -> day
var _next_p := 1
var _next_d := 1
var _next_x := 1
var _day := 0
var _npc_ids: Array = []        # sorted society npc ids, cached (not saved)
var _cost: Array = []           # fees the player owes, drained by take_pending_cost
var stats := {"filed": 0, "turned_away": 0, "granted": 0, "rejected": 0, "lapsed": 0, "disputed": 0, "revoked": 0, "reviewed": 0, "npc": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 2) -> void:
	Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, w)


# ------------------------------------------------------------------ petitioners

func rank_of(who: String) -> int:
	var st: Variant = _mod("stewardship")
	return int(st.rank_of(who)) if st != null else title_rank(who)


func title_rank(who: String) -> int:
	return int((_rank.get(who, {}) as Dictionary).get("r", 0))


func sponsor(who: String, sponsor_id: String, sponsor_name: String, rank: int) -> void:
	var l: Array = _spons.get(who, [])
	for s: Array in l:
		if String(s[0]) == sponsor_id:
			s[2] = rank
			return
	if l.size() >= 6:
		l.pop_front()
	l.append([sponsor_id, sponsor_name, rank])
	_spons[who] = l


func sponsors_of(who: String) -> Array:
	var out: Array = []
	for s: Array in _spons.get(who, []):
		out.append({"id": String(s[0]), "name": String(s[1]), "rank": int(s[2])})
	return out


## The player as a petitioner at `sid`.
func petitioner_player(sid: int, pname := "You") -> Dictionary:
	var soc: Variant = _mod("society")
	var fame := float(soc.fame_at(sid)) if soc != null else 0.0
	return {"id": "player", "name": pname, "kind": "player", "fame": fame, "rank": rank_of("player"), "sponsors": sponsors_of("player")}


func petitioner_npc(nid: String) -> Dictionary:
	var soc: Variant = _mod("society")
	if soc == null or not soc.npcs.has(nid):
		return {}
	var n: Dictionary = soc.npcs[nid]
	return {"id": nid, "name": String(n["name"]), "kind": "npc", "fame": float(int(n["tier"])) * 4.0 + float(int(n["class"])) * 3.0,
		"rank": maxi(rank_of(nid), mini(int(n["class"]), 3)), "sponsors": sponsors_of(nid)}


func _rkey(by: Dictionary) -> String:
	return ("i:" if String(by.get("kind", "npc")) in ["player", "npc"] else "f:") + String(by["id"])


# ------------------------------------------------------------------ 1. identify

func level_for(ptype: String, sid: int, subject: Dictionary = {}) -> int:
	var spec: Dictionary = PD.PETITIONS.get(ptype, {})
	if spec.is_empty():
		return -1
	var lv := int(spec["level"])
	match ptype:
		"settlement_recognition":
			var sc := String(subject.get("scale", "village"))
			lv = 1 if sc in ["camp", "hamlet"] else (3 if sc == "city" else 2)
		"title":
			lv = 2 if int(subject.get("rank", 1)) <= 2 else 3
		"land":
			lv = 3 if bool(subject.get("kingdom", false)) else lv
	return lv


func identify(ptype: String, sid: int, subject: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = PD.PETITIONS.get(ptype, {})
	var st: Variant = _mod("stewardship")
	if spec.is_empty() or st == null:
		return {"ok": false, "reason": "Nobody handles that."}
	var lv := level_for(ptype, sid, subject)
	var c: Array = st.chain(sid)
	var o: Dictionary = c[lv]
	return {"ok": true, "type": ptype, "level": lv, "office": o, "doc": String(spec["doc"]), "wait": int(spec["wait"]), "fee": int(spec["fee"]),
		"need": (spec["need"] as Array).duplicate(), "help": (spec["help"] as Array).duplicate(), "words": String(spec["words"]),
		"gate": gate_words(lv), "chain": c}


# ------------------------------------------------------------------ 2. access

func gate_words(level: int) -> String:
	var g: Dictionary = PD.OFFICES[level]
	if level == 3:
		return "The chamberlain admits only those of rank %d or more, known across the realm (fame %d), with a sponsor of rank %d." % [int(g["must_rank"]), int(g["fame"]), int(g["sponsor_rank"])]
	return "The %s wants fame %d and rank %d, or a sponsor of rank %d." % [String(g["gatekeeper"]), int(g["fame"]), int(g["rank"]), int(g["sponsor_rank"])]


func access(by: Dictionary, level: int, sid: int, ptype := "") -> Dictionary:
	var g: Dictionary = PD.OFFICES[clampi(level, 0, 3)]
	var missing: Array = []
	var rank := int(by.get("rank", 0))
	var fame := float(by.get("fame", 0.0))
	var good_sponsors := 0
	for s: Dictionary in by.get("sponsors", []):
		if int(s["rank"]) >= int(g["sponsor_rank"]):
			good_sponsors += 1
	if bool(by.get("outlaw", false)):
		missing.append("outlaw")
	var rep: Variant = _mod("reputation")
	if rep != null:
		var stn: Dictionary = rep.standing(_rkey(by), sid)
		if bool(stn["known"]) and float(stn["legitimacy"]) < -40.0:
			missing.append("outlaw")
	if level == 0:
		pass
	elif level == 3:
		if rank < int(g["must_rank"]):
			missing.append("rank")
		if fame < float(g["fame"]):
			missing.append("fame")
		if good_sponsors < int(g["sponsors"]):
			missing.append("sponsor")
	else:
		if fame < float(g["fame"]) and rank < int(g["rank"]) and good_sponsors < int(g["sponsors"]):
			missing.append("fame")
		elif level >= 2 and rank < int(g["rank"]) and good_sponsors < int(g["sponsors"]) and fame < float(g["fame"]) * 2.0:
			missing.append("rank")
	var ck := "%s|%s|%d" % [String(by["id"]), ptype, sid]
	if ptype != "" and int(_cool.get(ck, -999)) > _now():
		missing.append("cooldown")
	var words: Array = []
	for m: String in missing:
		match m:
			"fame": words.append("you are not known enough (fame %d needed, you have %d)" % [int(g["fame"]), int(fame)])
			"rank": words.append("your rank is too low (rank %d needed, or a sponsor of rank %d)" % [int(g["rank"]), int(g["sponsor_rank"])])
			"sponsor": words.append("no one of rank %d will speak for you" % int(g["sponsor_rank"]))
			"outlaw": words.append(String(PD.REJECT_WORDS["outlaw"]))
			"cooldown": words.append("you were refused lately; come back after day %d" % int(_cool.get(ck, 0)))
	return {"ok": missing.is_empty(), "missing": missing, "words": words, "gatekeeper": String(g["gatekeeper"]), "sponsors": good_sponsors}


## Steps 1 and 2: identify the authority and pass the gate. Returns {ok, pid} or {ok:false, reason, missing}.
func file(ptype: String, sid: int, by: Dictionary, subject: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var idf := identify(ptype, sid, subject)
	if not bool(idf["ok"]):
		return {"ok": false, "reason": String(idf.get("reason", "")), "missing": []}
	var lv := int(idf["level"])
	var acc := access(by, lv, sid, ptype)
	if not bool(acc["ok"]):
		stats["turned_away"] = int(stats["turned_away"]) + 1
		return {"ok": false, "reason": "The %s turns you away: %s." % [String(acc["gatekeeper"]), "; ".join(PackedStringArray(acc["words"]))],
			"missing": acc["missing"], "level": lv}
	if _pt.size() >= PET_MAX:
		_prune()
		if _pt.size() >= PET_MAX:
			return {"ok": false, "reason": "The clerks have no room for another petition.", "missing": []}
	var pid := "pn%d" % _next_p
	_next_p += 1
	var off: Dictionary = idf["office"]
	_pt[pid] = {"id": pid, "type": ptype, "sid": sid, "level": lv, "key": String(off["key"]), "by": {"id": String(by["id"]), "name": String(by["name"]), "kind": String(by.get("kind", "npc"))},
		"subject": subject.duplicate(true), "state": "admitted", "step": 2, "steps": [[1, _now(), "office: " + String(off["role"])], [2, _now(), "admitted by the " + String(acc["gatekeeper"])]],
		"filed": _now(), "evidence": [], "due": -1, "expire": -1, "assess": {}, "terms": {}, "round": 0, "doc": "", "proxy": bool(opts.get("proxy", false)),
		"ext": (opts.get("ext", {}) as Dictionary).duplicate(), "fee": int(idf["fee"]), "gift": 0, "sponsors": (by.get("sponsors", []) as Array).size(), "reasons": [],
		"rank": int(by.get("rank", 0)), "fame": float(by.get("fame", 0.0)), "wait_cap": int(opts.get("wait_cap", 999))}
	stats["filed"] = int(stats["filed"]) + 1
	if bool(opts.get("npc", false)):
		stats["npc"] = int(stats["npc"]) + 1
	return {"ok": true, "pid": pid, "level": lv, "office": off, "reason": ""}


# ------------------------------------------------------------------ 3, 4. present and wait

func _log_step(p: Dictionary, step: int, note: String) -> void:
	p["step"] = step
	(p["steps"] as Array).append([step, _now(), note])


func add_evidence(pid: String, kind: String, strength := 0.7, by := "") -> bool:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or not (kind in PD.EVIDENCE_KINDS) or String(p["state"]) in ["granted", "rejected", "withdrawn", "lapsed"]:
		return false
	if (p["evidence"] as Array).size() >= 10:
		return false
	(p["evidence"] as Array).append({"kind": kind, "s": snappedf(clampf(strength, 0.0, 1.0), 0.01), "by": by})
	return true


## Step 3: put the evidence on the table; the petition joins the queue. Returns the missing required evidence (the clerk warns you).
func present(pid: String, evidence: Array = [], gift := 0) -> Dictionary:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["state"]) != "admitted":
		return {"ok": false, "reason": "Nothing to present."}
	for e: Variant in evidence:
		if e is Dictionary:
			add_evidence(pid, String(e.get("kind", "")), float(e.get("s", 0.7)), String(e.get("by", "")))
	p["gift"] = maxi(0, gift)
	var spec: Dictionary = PD.PETITIONS[p["type"]]
	var have := {}
	for e: Dictionary in p["evidence"]:
		have[String(e["kind"])] = true
	var missing: Array = []
	for k: String in spec["need"]:
		if not have.has(k):
			missing.append(k)
	var queue := 0
	for q: Dictionary in _pt.values():
		if q != p and String(q["key"]) == String(p["key"]) and String(q["state"]) in ["waiting", "audience"]:
			queue += 1
	var wait := int(spec["wait"]) + mini(queue * QUEUE_STEP, 12) + (int(p["level"]) - int(spec["level"])) * 3
	wait = mini(wait, int(p["wait_cap"]))
	p["due"] = _now() + maxi(1, wait)
	p["state"] = "waiting"
	_log_step(p, 3, "%d pieces of evidence presented" % (p["evidence"] as Array).size())
	_log_step(p, 4, "queued; the hearing is on day %d" % int(p["due"]))
	if int(p["fee"]) > 0 and String(p["by"]["kind"]) == "player":
		_cost.append(int(p["fee"]) + int(p["gift"]))
	return {"ok": true, "missing": missing, "due": int(p["due"]), "wait": wait}


func take_pending_cost() -> int:
	var t := 0
	for c: int in _cost:
		t += c
	_cost.clear()
	return t


# ------------------------------------------------------------------ 5. audience

func _holder(p: Dictionary) -> Dictionary:
	var st: Variant = _mod("stewardship")
	return st.office(String(p["key"])) if st != null else {}


func _assess(p: Dictionary) -> Dictionary:
	var spec: Dictionary = PD.PETITIONS[p["type"]]
	var off := _holder(p)
	var lv := int(p["level"])
	var codes: Array = []
	var parts := {}
	var have := {}
	for e: Dictionary in p["evidence"]:
		have[String(e["kind"])] = maxf(float(have.get(String(e["kind"]), 0.0)), float(e["s"]))
	var need: Array = spec["need"]
	var ev_sum := 0.0
	for k: String in need:
		if not have.has(k):
			codes.append("no_evidence:" + k)
		else:
			ev_sum += float(have[k])
	var ev_avg := ev_sum / float(maxi(need.size(), 1))
	var help := 0.0
	for k: String in spec["help"]:
		if have.has(k):
			help += 0.04 * float(have[k])
	parts["evidence"] = 0.28 * ev_avg
	parts["help"] = minf(help, 0.12)
	var good := 0
	for s: Array in _spons.get(String(p["by"]["id"]), []):
		if int(s[2]) >= lv:
			good += 1
	parts["sponsors"] = minf(0.06 * float(good), 0.18)
	var rep: Variant = _mod("reputation")
	var rv := 0.0
	var unreliable := false
	if rep != null:
		var stn: Dictionary = rep.standing(_rkey(p["by"]), int(p["sid"]))
		rv = clampf(float(stn["favour"]) / 100.0 * 0.5 + float(stn["influence"]) / 100.0 * 0.1, -0.28, 0.28)
		unreliable = bool(stn["known"]) and float(stn["reliability"]) < -35.0
		if bool(stn["known"]) and float(stn["trust"]) < -35.0:
			codes.append("low_standing")
	if unreliable:
		codes.append("unreliable")
	parts["reputation"] = rv
	var rank_gap := float(int(p["rank"])) * 0.025
	parts["rank"] = rank_gap
	# Law: the local law may close the door.
	var gv: Variant = _mod("governance")
	var seat := int(off.get("seat", int(p["sid"])))
	if gv != null:
		var ptype := String(p["type"])
		if ptype == "land":
			var ll: int = gv.law_level(seat, "land_ownership")
			if (ll == 1 and int(p["rank"]) < 1) or (ll == 2 and lv < 3):
				codes.append("law_forbids")
		elif ptype in ["trade_rights", "org_recognition", "mining_rights"]:
			if gv.law_level(seat, "guild_licensing") == 2 and int(p["rank"]) < 1 and int(p["sponsors"]) < 1:
				codes.append("law_forbids")
	if String(p["type"]) == "title" and int((p["subject"] as Dictionary).get("rank", 1)) > [1, 2, 3, 4][clampi(lv, 0, 3)]:
		codes.append("wrong_office")
	# A rival with the same business before the same office, or a standing grant to someone else.
	for q: Dictionary in _pt.values():
		if q != p and String(q["type"]) == String(p["type"]) and int(q["sid"]) == int(p["sid"]) and String(q["state"]) in ["waiting", "audience", "heard", "negotiated"] \
				and String(q["by"]["id"]) != String(p["by"]["id"]) and p["type"] in ["land", "mining_rights", "office"] and int(q["filed"]) < int(p["filed"]):
			parts["rival"] = -0.1
			break
	if String(p["type"]) in ["land", "mining_rights"]:
		for d: Dictionary in _doc.values():
			if String(d["state"]) == "valid" and String(d["type"]) == String(p["type"]) and int(d["sid"]) == int(p["sid"]) and String(d["holder"]) != String(p["by"]["id"]):
				parts["rival"] = -0.35
				codes.append("rival_claim")
				break
	# Coin: a corrupt holder takes it; an honest one is insulted.
	var gift := int(p["gift"])
	var corrupt := 0.0
	if not off.is_empty():
		corrupt = clampf((1.0 - float(off["honest"])) * 0.8, 0.0, 1.0)
		var fnd: Variant = _mod("founding")
		if fnd != null:
			corrupt = clampf(corrupt + float(fnd.corruption_at(seat)) * 0.3 - 0.1, 0.0, 1.0)
	if gift > 0:
		var take := PD.rng("bribe", int(p["filed"]), p["id"]).randf() < corrupt
		if take:
			parts["gift"] = minf(0.25, float(gift) / float(int(p["fee"]) + 20) * 0.1)
			p["tainted"] = true
		else:
			parts["gift"] = -0.25
			codes.append("bribe_refused")
	var noise := (PD.rng("aud", int(p["filed"]), p["id"]).randf() - 0.5) * 0.08
	parts["noise"] = noise
	var score := 0.30
	for k: String in parts:
		score += float(parts[k])
	var thr := 0.55 + 0.03 * float(lv)
	var verdict := "grant" if score >= thr else ("conditional" if score >= thr - 0.1 else "refuse")
	var hard := false
	for c: String in codes:
		if c.begins_with("no_evidence") or c in ["law_forbids", "rival_claim", "wrong_office", "unreliable", "bribe_refused", "low_standing"]:
			hard = true
	if hard:
		verdict = "refuse"
	elif verdict == "refuse":
		codes.append("score")
	return {"score": snappedf(score, 0.001), "thr": thr, "verdict": verdict, "reasons": codes, "parts": parts}


func reason_words(codes: Array) -> Array:
	var out: Array = []
	for c: String in codes:
		if c.begins_with("no_evidence:"):
			out.append("You brought no %s." % c.substr(12).replace("_", " "))
		elif PD.REJECT_WORDS.has(c):
			out.append(String(PD.REJECT_WORDS[c]))
	return out


func _terms_for(p: Dictionary, conditional: bool) -> Dictionary:
	var lv := int(p["level"])
	var st: Variant = _mod("stewardship")
	var f := 0.75 if conditional else 0.45
	var t := {"tax": snappedf(float(st.limit(lv, "tax")) * f, 0.001), "levy": int(ceil(float(st.limit(lv, "levy")) * f * 0.5)), "build": int(float(st.limit(lv, "build")) * (0.35 if conditional else 0.6)),
		"loyalty": lv >= 2 or conditional, "years": int(st.limit(lv, "years")), "relief": 0.0, "troops": 0, "fine": 0}
	match String(p["type"]):
		"tax_relief":
			t["relief"] = 0.3 if conditional else 0.5
			t["years"] = 1
		"military_aid":
			t["troops"] = maxi(2, int(st.limit(lv, "levy") * (0.3 if conditional else 0.5)))
			t["years"] = 1
		"amnesty":
			t["fine"] = 60 if conditional else 25
		"dispute":
			t["tax"] = 0.0
			t["levy"] = 0
	return t


## Step 5. The holder hears you. Returns a talk sheet {speaker, title, lines[], choices[], assessment, terms}; a refusal ends the petition with reasons.
func attend(pid: String) -> Dictionary:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["state"]) != "audience":
		return {"ok": false, "reason": "There is no hearing to attend."}
	var off := _holder(p)
	if bool(off.get("vacant", true)):
		p["due"] = _now() + 7
		p["state"] = "waiting"
		return {"ok": false, "reason": "The seat is empty; the hearing is put off a week."}
	var a := _assess(p)
	p["assess"] = a
	_log_step(p, 5, "heard by %s: %s (%.2f against %.2f)" % [String(off["name"]), String(a["verdict"]), float(a["score"]), float(a["thr"])])
	var spec: Dictionary = PD.PETITIONS[p["type"]]
	var lines: Array = ["%s receives you in the name of %s." % [String(off["name"]), String(off["role"])],
		"You ask for %s. %d pieces of evidence lie before the court." % [String(spec["words"]), (p["evidence"] as Array).size()]]
	if String(a["verdict"]) == "refuse":
		_reject(p, a["reasons"])
		lines.append_array(reason_words(a["reasons"]))
		return {"ok": true, "speaker": String(off["name"]), "title": String(off["role"]), "lines": lines, "choices": [], "assessment": a, "terms": {}, "refused": true}
	p["state"] = "heard"
	p["terms"] = _terms_for(p, String(a["verdict"]) == "conditional")
	var tm: Dictionary = p["terms"]
	lines.append("The terms: tax %d%%, %d men to the levy, no more than %d structures, term of %d years%s." % [int(float(tm["tax"]) * 100.0), int(tm["levy"]), int(tm["build"]), int(tm["years"]),
		", and an oath of loyalty" if bool(tm["loyalty"]) else ""])
	var choices: Array = [{"id": "accept", "text": "Accept the terms."}, {"id": "haggle", "text": "Ask for lighter tax and levy."}, {"id": "withdraw", "text": "Withdraw the petition."}]
	if bool(tm["loyalty"]):
		choices.insert(1, {"id": "swear", "text": "Swear loyalty to win a better price."})
	return {"ok": true, "speaker": String(off["name"]), "title": String(off["role"]), "lines": lines, "choices": choices, "assessment": a, "terms": tm.duplicate(), "refused": false}


func _reject(p: Dictionary, codes: Array) -> void:
	p["state"] = "rejected"
	p["reasons"] = codes.duplicate()
	stats["rejected"] = int(stats["rejected"]) + 1
	_cool["%s|%s|%d" % [String(p["by"]["id"]), String(p["type"]), int(p["sid"])]] = _now() + COOLDOWN
	_log_step(p, int(p["step"]), "rejected: " + "; ".join(PackedStringArray(reason_words(codes))))
	if p["type"] == "settlement_recognition" and (p["ext"] as Dictionary).has("fid"):
		var fd: Variant = _mod("founding")
		if fd != null:
			fd.resolve_petition(int(p["ext"]["fid"]), false)
	if p["type"] == "org_recognition" and (p["ext"] as Dictionary).has("opid"):
		var og: Variant = _mod("organizations")
		if og != null:
			og.resolve_petition(String(p["ext"]["opid"]), false, " ".join(PackedStringArray(reason_words(codes))))
	if "bribe_refused" in codes:
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.on_deed(_rkey(p["by"]), "bribed", int(p["sid"]), 1.0)
		_ev("crime", int(p["sid"]), [String(p["by"]["id"])], "bribery", "bribe refused", 3)
	_ev("contract", int(p["sid"]), [String(p["by"]["id"])], "refused", "%s refused" % PD.PETITIONS[p["type"]]["words"], 2)


func withdraw(pid: String) -> bool:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["state"]) in ["granted", "rejected", "withdrawn", "lapsed"]:
		return false
	p["state"] = "withdrawn"
	_log_step(p, int(p["step"]), "withdrawn")
	return true


# ------------------------------------------------------------------ 6. negotiate

## Offer {accept, tax, levy, build, loyalty, years, swear}. Returns {ok, state: agreed|counter|refused, terms, failed[]}.
func negotiate(pid: String, offer: Dictionary) -> Dictionary:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["state"]) != "heard":
		return {"ok": false, "state": "none", "reason": "No terms are on the table."}
	var tm: Dictionary = p["terms"]
	if bool(offer.get("withdraw", false)):
		withdraw(pid)
		return {"ok": true, "state": "withdrawn", "terms": tm.duplicate(), "failed": []}
	if bool(offer.get("accept", false)):
		return _agree(p, tm)
	p["round"] = int(p["round"]) + 1
	var a: Dictionary = p["assess"]
	var margin := float(a["score"]) - float(a["thr"])
	var rep: Variant = _mod("reputation")
	var infl := 0.0
	if rep != null:
		infl = float((rep.standing(_rkey(p["by"]), int(p["sid"])) as Dictionary)["influence"])
	var sworn := bool(offer.get("swear", false)) or bool(offer.get("loyalty", false))
	var concession := clampf(margin * 1.2 + infl * 0.002 + (0.15 if sworn else 0.0), 0.0, 0.5)
	var failed: Array = []
	var want := tm.duplicate()
	if offer.has("tax") and float(offer["tax"]) < float(tm["tax"]) * (1.0 - concession) - 0.0005:
		failed.append("tax")
	if offer.has("levy") and float(offer["levy"]) < float(tm["levy"]) * (1.0 - concession) - 0.4:
		failed.append("levy")
	if offer.has("build") and float(offer["build"]) > float(tm["build"]) * (1.0 + concession):
		failed.append("build")
	if bool(tm["loyalty"]) and not sworn:
		failed.append("loyalty")
	if offer.has("years") and int(offer["years"]) > int(tm["years"]):
		failed.append("years")
	if failed.is_empty():
		for k: String in ["tax", "levy", "build", "years"]:
			if offer.has(k):
				want[k] = offer[k]
		want["loyalty"] = sworn or bool(tm["loyalty"])
		return _agree(p, want)
	if int(p["round"]) >= MAX_ROUNDS:
		p["state"] = "rejected"
		p["reasons"] = ["talks_failed"]
		stats["rejected"] = int(stats["rejected"]) + 1
		_log_step(p, 6, "talks collapsed over " + ", ".join(PackedStringArray(failed)))
		_cool["%s|%s|%d" % [String(p["by"]["id"]), String(p["type"]), int(p["sid"])]] = _now() + COOLDOWN
		return {"ok": true, "state": "refused", "terms": tm.duplicate(), "failed": failed}
	# The holder moves a little toward you.
	var counter := tm.duplicate()
	counter["tax"] = snappedf(lerpf(float(tm["tax"]), float(offer.get("tax", tm["tax"])), 0.5 * concession + 0.25), 0.001)
	counter["levy"] = int(round(lerpf(float(tm["levy"]), float(offer.get("levy", tm["levy"])), 0.5)))
	p["terms"] = counter
	_log_step(p, 6, "round %d: counter on %s" % [int(p["round"]), ", ".join(PackedStringArray(failed))])
	return {"ok": true, "state": "counter", "terms": counter.duplicate(), "failed": failed}


func _agree(p: Dictionary, tm: Dictionary) -> Dictionary:
	p["terms"] = tm.duplicate()
	p["state"] = "negotiated"
	_log_step(p, 6, "terms agreed: tax %d%%, levy %d, build %d" % [int(float(tm["tax"]) * 100.0), int(tm["levy"]), int(tm["build"])])
	return {"ok": true, "state": "agreed", "terms": tm.duplicate(), "failed": []}


# ------------------------------------------------------------------ 7. document

func issue(pid: String) -> Dictionary:
	var p: Dictionary = _pt.get(pid, {})
	if p.is_empty() or String(p["state"]) != "negotiated":
		return {}
	if _doc.size() >= DOC_MAX:
		_prune()
	var spec: Dictionary = PD.PETITIONS[p["type"]]
	var off := _holder(p)
	var did := "dc%d" % _next_d
	_next_d += 1
	var tm: Dictionary = p["terms"]
	var yrs := int(tm["years"])
	var d := {"id": did, "kind": String(spec["doc"]), "type": String(p["type"]), "holder": String(p["by"]["id"]), "hname": String(p["by"]["name"]), "hkind": String(p["by"]["kind"]),
		"sid": int(p["sid"]), "level": int(p["level"]), "key": String(p["key"]), "issuer": String(off.get("holder", "")), "iname": String(off.get("name", "")), "terms": tm.duplicate(),
		"day": _now(), "expires": -1 if yrs >= 99 else _now() + yrs * 360, "state": "valid", "warn": 0, "arrears": 0, "paid": 0, "pid": pid, "subject": (p["subject"] as Dictionary).duplicate(true),
		"tainted": bool(p.get("tainted", false)), "rev": -1, "hist": ["issued day %d" % _now()]}
	_doc[did] = d
	p["doc"] = did
	p["state"] = "granted"
	stats["granted"] = int(stats["granted"]) + 1
	_log_step(p, 7, "%s %s issued by %s" % [String(d["kind"]), did, String(d["iname"])])
	_log_step(p, 8, "in force; others may dispute it")
	_on_issue(d, p)
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed("i:" + String(d["issuer"]), "fair_ruling", int(d["sid"]), 0.5)
		if String(d["kind"]) in ["charter", "commission"]:
			rep.on_deed(("i:" if String(d["hkind"]) in ["player", "npc"] else "f:") + String(d["holder"]), "recognised", int(d["sid"]), 0.6 + 0.2 * float(int(d["level"])))
	_ev("contract", int(d["sid"]), [String(d["holder"]), String(d["issuer"])], String(d["kind"]), "%s granted: %s" % [String(d["kind"]), String(spec["words"])], 3)
	return d.duplicate(true)


func _on_issue(d: Dictionary, p: Dictionary) -> void:
	var sub: Dictionary = p["subject"]
	var ext: Dictionary = p["ext"]
	var who := String(d["holder"])
	match String(d["type"]):
		"settlement_recognition":
			if ext.has("fid"):
				var fd: Variant = _mod("founding")
				if fd != null:
					fd.resolve_petition(int(ext["fid"]), true)
			var tr: Variant = _mod("territory")
			if tr != null and sub.has("pos"):
				tr.confirm_pos(Vector2(float(sub["pos"][0]), float(sub["pos"][1])), who, String(d["id"]), 1 + int(sub.get("cells", 1)))
		"org_recognition":
			if ext.has("opid"):
				var og: Variant = _mod("organizations")
				if og != null:
					og.resolve_petition(String(ext["opid"]), true, "")
		"land":
			var ld: Variant = _mod("land")
			if ld != null:
				ld.grant(int(d["sid"]), who, "*", _now())
		"title":
			var cur := title_rank(who)
			var nr := int(sub.get("rank", cur + 1))
			_rank[who] = {"r": maxi(cur, nr), "title": String(sub.get("title", "knight" if nr <= 2 else "baron")), "day": _now()}
		"tax_relief":
			var st: Variant = _mod("stewardship")
			if st != null:
				st.set_relief(int(d["sid"]), float((d["terms"] as Dictionary)["relief"]), _now() + 90)
		"amnesty":
			var ct: Variant = _mod("courts")
			if ct != null:
				ct.pardon(who, int(d["sid"]), String(d["id"]))
		"office":
			var st2: Variant = _mod("stewardship")
			if st2 != null:
				var target := String(sub.get("office", st2.office_key(int(d["sid"]), 0)))
				st2.assume(target, who, String(d["hname"]), String(d["hkind"]) == "player")
		"dispute":
			var tgt := String(sub.get("against", ""))
			if _doc.has(tgt):
				_set_state(_doc[tgt], "revoked", "overturned by ruling " + String(d["id"]))


# ------------------------------------------------------------------ 8. enforcement

func doc(did: String) -> Dictionary:
	return (_doc.get(did, {}) as Dictionary).duplicate(true)


func documents(holder := "", state := "") -> Array:
	var out: Array = []
	var ids := _doc.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(2)) < int(b.substr(2)))
	for k: String in ids:
		var d: Dictionary = _doc[k]
		if (holder == "" or String(d["holder"]) == holder) and (state == "" or String(d["state"]) == state):
			out.append(d.duplicate(true))
	return out


func has_right(holder: String, ptype: String, sid: int) -> bool:
	for d: Dictionary in _doc.values():
		if String(d["holder"]) == holder and String(d["type"]) == ptype and (sid < 0 or int(d["sid"]) == sid) and String(d["state"]) in ["valid", "review"]:
			if int(d["expires"]) < 0 or int(d["expires"]) >= _now():
				return true
	return false


func _set_state(d: Dictionary, state: String, why: String) -> void:
	d["state"] = state
	(d["hist"] as Array).append("%s day %d: %s" % [state, _now(), why])
	if (d["hist"] as Array).size() > 8:
		(d["hist"] as Array).pop_front()
	if state == "revoked":
		stats["revoked"] = int(stats["revoked"]) + 1
		_ev("contract", int(d["sid"]), [String(d["holder"])], "revoked", "%s revoked: %s" % [String(d["kind"]), why], 3)


## Anyone with a stake can dispute a document (a rival, a neighbour, the heirs). It goes to the issuing office.
func dispute(did: String, by: Dictionary, reason: String, evidence: Array = []) -> Dictionary:
	var d: Dictionary = _doc.get(did, {})
	if d.is_empty() or String(d["state"]) not in ["valid", "review"]:
		return {"ok": false, "reason": "No such valid document."}
	if _dis.size() >= DIS_MAX:
		_prune()
	if String(by["id"]) == String(d["holder"]):
		return {"ok": false, "reason": "You hold it yourself."}
	var xid := "dx%d" % _next_x
	_next_x += 1
	_dis[xid] = {"id": xid, "doc": did, "by": {"id": String(by["id"]), "name": String(by["name"]), "kind": String(by.get("kind", "npc"))}, "reason": reason, "day": _now(),
		"evidence": evidence.duplicate(true), "state": "open", "due": _now() + 6, "rank": int(by.get("rank", 0))}
	stats["disputed"] = int(stats["disputed"]) + 1
	return {"ok": true, "xid": xid}


func rule_dispute(xid: String, force := "") -> Dictionary:
	var x: Dictionary = _dis.get(xid, {})
	if x.is_empty() or String(x["state"]) != "open":
		return {}
	var d: Dictionary = _doc.get(String(x["doc"]), {})
	var upheld := false
	if force != "":
		upheld = force == "upheld"
	elif not d.is_empty():
		var s := 0.25
		for e: Variant in x["evidence"]:
			s += 0.2 * float((e as Dictionary).get("s", 0.5)) if e is Dictionary else 0.0
		s += float(int(x["rank"])) * 0.03
		if bool(d["tainted"]):
			s += 0.25
		if String(d["state"]) == "review":
			s += 0.1
		var rep: Variant = _mod("reputation")
		if rep != null:
			s += clampf(float(rep.standing("i:" + String(d["holder"]), int(d["sid"]))["favour"]) / -200.0, -0.2, 0.2)
		s += (PD.rng("disp", int(x["day"]), xid).randf() - 0.5) * 0.1
		upheld = s >= 0.55
	x["state"] = "upheld" if upheld else "dismissed"
	if not d.is_empty():
		(d["hist"] as Array).append("dispute %s %s" % [xid, x["state"]])
		if upheld:
			_set_state(d, "revoked", "dispute by %s upheld: %s" % [String(x["by"]["name"]), String(x["reason"])])
		else:
			d["warn"] = int(d["warn"])
	return {"xid": xid, "upheld": upheld, "doc": String(x["doc"])}


func breach(did: String, what: String) -> int:
	var d: Dictionary = _doc.get(did, {})
	if d.is_empty() or String(d["state"]) != "valid":
		return -1
	d["warn"] = int(d["warn"]) + 1
	(d["hist"] as Array).append("breach: " + what)
	if int(d["warn"]) >= 3:
		_set_state(d, "revoked", "three breaches (last: %s)" % what)
	elif int(d["warn"]) == 2:
		_set_state(d, "suspended", "second breach: " + what)
		d["state"] = "valid"   # a written warning; the third breach revokes
	return int(d["warn"])


func dues_owed(did: String) -> int:
	var d: Dictionary = _doc.get(did, {})
	return int(d.get("arrears", 0)) * int(round(float((d.get("terms", {}) as Dictionary).get("tax", 0.0)) * 100.0)) if not d.is_empty() else 0


func pay_dues(did: String, weeks := 1) -> bool:
	var d: Dictionary = _doc.get(did, {})
	if d.is_empty() or String(d["state"]) != "valid":
		return false
	d["arrears"] = maxi(0, int(d["arrears"]) - weeks)
	d["paid"] = int(d["paid"]) + weeks
	return true


## A holder of an office changed (death, dismissal, succession): what the old one granted is reviewed by the new one.
func on_ruler_change(key: String, old: String, new_holder: String) -> int:
	var n := 0
	for d: Dictionary in _doc.values():
		if String(d["key"]) == key and String(d["issuer"]) == old and String(d["state"]) == "valid" and old != new_holder:
			d["state"] = "review"
			d["rev"] = _now() + REVIEW_DAYS
			(d["hist"] as Array).append("review ordered day %d" % _now())
			n += 1
	return n


func _review(d: Dictionary) -> void:
	var st: Variant = _mod("stewardship")
	var off: Dictionary = st.office(String(d["key"])) if st != null else {}
	if off.is_empty() or bool(off.get("vacant", true)):
		d["rev"] = _now() + 14
		return
	stats["reviewed"] = int(stats["reviewed"]) + 1
	d["issuer"] = String(off["holder"])
	d["iname"] = String(off["name"])
	var rep: Variant = _mod("reputation")
	var fav := 0.0
	if rep != null:
		fav = float(rep.standing(("i:" if String(d["hkind"]) in ["player", "npc"] else "f:") + String(d["holder"]), int(d["sid"]))["favour"])
	var s := 0.55 + fav / 200.0 + float(int(d["level"])) * 0.0 - (0.2 if bool(d["tainted"]) else 0.0) + (PD.rng("review", _now(), d["id"]).randf() - 0.5) * 0.3
	var tm: Dictionary = d["terms"]
	if s >= 0.5:
		d["state"] = "valid"
		(d["hist"] as Array).append("confirmed by %s" % String(off["name"]))
	elif s >= 0.3:
		d["state"] = "valid"
		tm["tax"] = snappedf(float(tm["tax"]) * 1.25, 0.001)
		(d["hist"] as Array).append("renegotiated by %s: tax raised" % String(off["name"]))
	else:
		_set_state(d, "revoked", "the new holder %s does not honour it" % String(off["name"]))
	d["rev"] = -1
	_ev("contract", int(d["sid"]), [String(d["holder"]), String(d["issuer"])], "review", "%s reviewed: %s" % [String(d["kind"]), String(d["state"])], 2)


# ------------------------------------------------------------------ queries

func petition(pid: String) -> Dictionary:
	return (_pt.get(pid, {}) as Dictionary).duplicate(true)


func petitions(state := "", by := "") -> Array:
	var out: Array = []
	var ids := _pt.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(2)) < int(b.substr(2)))
	for k: String in ids:
		var p: Dictionary = _pt[k]
		if (state == "" or String(p["state"]) == state) and (by == "" or String(p["by"]["id"]) == by):
			out.append(p.duplicate(true))
	return out


## Petitions waiting at each office for more than `days`, as {"seat:level": n} (stewardship counts these as a neglected duty).
func backlog_map(days: int) -> Dictionary:
	var m := {}
	for p: Dictionary in _pt.values():
		if String(p["state"]) == "audience" and int(p["due"]) <= _now() - days:
			m[String(p["key"])] = int(m.get(String(p["key"]), 0)) + 1
	return m


func backlog(seat: int, level: int, days: int) -> int:
	return int(backlog_map(days).get("%d:%d" % [seat, level], 0))


func disputes(state := "") -> Array:
	var out: Array = []
	for x: Dictionary in _dis.values():
		if state == "" or String(x["state"]) == state:
			out.append(x.duplicate(true))
	return out


# ------------------------------------------------------------------ stubs: founding and organizations

func _adopt_founding() -> void:
	var fd: Variant = _mod("founding")
	if fd == null:
		return
	for fid: int in fd.ids(true):
		var f: Dictionary = fd.get_founding(fid)
		var pet: Dictionary = f.get("pet", {})
		if pet.is_empty() or String(pet.get("state", "")) != "filed" or String(pet.get("stage6", "")) != "pending":
			continue
		var land: Dictionary = f.get("land", {})
		var sid := int(land.get("sid", PD.nearest_of(0, ["village", "town", "castle", "capital", "frontier_town"])))
		var pos := Vector2(float(f["pos"][0]), float(f["pos"][1]))
		var who := String(f.get("who", "player"))
		var by := {"id": "fo:%d" % fid, "name": String(f["name"]), "kind": "settlement", "fame": float(pet.get("pop", 10)) * 0.5 + 10.0,
			"rank": rank_of("player") if who == "player" else 1, "sponsors": sponsors_of("player") if who == "player" else [{"id": "x", "name": "a patron", "rank": 3}]}
		pet["stage6"] = "audiences"
		var sub := {"scale": String(pet.get("scale", "village")), "pos": [pos.x, pos.y], "cells": 1 + int(pet.get("pop", 0)) / 40}
		var fr := file("settlement_recognition", sid, _force_access(by, sub), sub, {"proxy": true, "ext": {"fid": fid}})
		if not bool(fr["ok"]):
			fd.resolve_petition(fid, false)
			pet["stage6"] = "refused: " + String(fr["reason"])
			continue
		var pid := String(fr["pid"])
		add_evidence(pid, "survey", clampf(float(f.get("site", {}).get("overall", 0.6)) if f.get("site") is Dictionary else 0.65, 0.3, 1.0))
		add_evidence(pid, "witness", clampf(float(pet.get("pop", 5)) / 40.0 + 0.3, 0.3, 1.0))
		if int(pet.get("officials", 0)) > 0:
			add_evidence(pid, "recommendation", 0.7)
		present(pid, [], 0)
		pet["pid"] = pid


## A settlement petition is represented by its steward: it gets in at the level its scale needs (the gate checks the founder's rank).
func _force_access(by: Dictionary, sub: Dictionary) -> Dictionary:
	var out := by.duplicate(true)
	var lv := 1 if String(sub.get("scale", "village")) in ["camp", "hamlet"] else (3 if String(sub.get("scale", "village")) == "city" else 2)
	var g: Dictionary = PD.OFFICES[lv]
	out["fame"] = maxf(float(out["fame"]), float(g["fame"]) if lv < 3 else 0.0)
	return out


func _adopt_orgs() -> void:
	var og: Variant = _mod("organizations")
	if og == null:
		return
	for row: Dictionary in og.petitions("pending"):
		var opid := String(row["id"])
		var known := false
		for p: Dictionary in _pt.values():
			if (p["ext"] as Dictionary).get("opid", "") == opid:
				known = true
				break
		if known:
			continue
		var org: Dictionary = og.org(String(row["org"]))
		if org.is_empty():
			continue
		var sid := maxi(int(org.get("sid", -1)), 0)
		var orep := float(org.get("rep", 0.0))
		var by := {"id": String(row["org"]), "name": String(org.get("name", "an organisation")), "kind": "org", "fame": orep * 2.0, "rank": 1, "sponsors": []}
		var fr := file("org_recognition", sid, by, {}, {"proxy": true, "ext": {"opid": opid}, "wait_cap": OrgScript.PETITION_DAYS - 1})
		if not bool(fr["ok"]):
			og.resolve_petition(opid, false, String(fr["reason"]))
			continue
		var pid := String(fr["pid"])
		if not (org.get("charter", {}) as Dictionary).is_empty():
			add_evidence(pid, "charter", 0.8)
		if int(og.member_count(String(row["org"]))) >= 2:
			add_evidence(pid, "witness", clampf(0.15 + orep / 16.0, 0.1, 1.0))
		if orep >= 12.0:
			add_evidence(pid, "recommendation", 0.7)
		present(pid, [], 0)


# ------------------------------------------------------------------ NPCs use the same door

const NPC_TYPES := ["tax_relief", "trade_rights", "dispute", "land", "mining_rights", "office", "amnesty"]


func _npc_petition(day: int) -> void:
	var active := 0
	for p: Dictionary in _pt.values():
		if bool(p["proxy"]) and String((p["by"] as Dictionary)["kind"]) == "npc" and String(p["state"]) in ["admitted", "waiting", "audience", "heard", "negotiated"]:
			active += 1
	if active >= NPC_ACTIVE_MAX:
		return
	var soc: Variant = _mod("society")
	if soc == null:
		return
	var r := PD.rng("npcpet", day, 0)
	if r.randf() > 0.55:
		return
	soc._ensure_npcs()
	if _npc_ids.size() != soc.npcs.size():
		_npc_ids = soc.npcs.keys()
		_npc_ids.sort()
	var ids: Array = _npc_ids
	if ids.is_empty():
		return
	var nid := String(ids[r.randi() % ids.size()])
	var by := petitioner_npc(nid)
	if by.is_empty() or not bool((soc.npcs[nid] as Dictionary)["alive"]):
		return
	var ptype := String(NPC_TYPES[r.randi() % NPC_TYPES.size()])
	var sid := int((soc.npcs[nid] as Dictionary)["sid"])
	var fr := file(ptype, sid, by, {}, {"proxy": true, "npc": true})
	if not bool(fr["ok"]):
		return
	var pid := String(fr["pid"])
	var spec: Dictionary = PD.PETITIONS[ptype]
	var pers: Dictionary = (soc.npcs[nid] as Dictionary)["pers"]
	for k: String in spec["need"]:
		add_evidence(pid, k, clampf(0.35 + float(pers["honor"]) * 0.3 + r.randf() * 0.35, 0.2, 1.0))
	for k: String in spec["help"]:
		if r.randf() < 0.4:
			add_evidence(pid, k, 0.5 + r.randf() * 0.4)
	present(pid, [], 0)


func _auto_hear(p: Dictionary) -> void:
	var sheet := attend(String(p["id"]))
	if not bool(sheet.get("ok", false)) or bool(sheet.get("refused", false)):
		return
	var res := negotiate(String(p["id"]), {"accept": true})
	if String(res.get("state", "")) == "agreed":
		issue(String(p["id"]))


# ------------------------------------------------------------------ ticks

## The day's work in four jobs (each far below the realm pump budget): taking in stubs and NPC petitions, moving the queue, proxy hearings, documents.
func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	return [func() -> Array:
			_day = day
			_adopt_founding()
			_adopt_orgs()
			_npc_petition(day)
			return [],
		func() -> Array:
			for k: String in _pt.keys():
				var p: Dictionary = _pt[k]
				var s := String(p["state"])
				if s == "waiting" and int(p["due"]) <= day:
					p["state"] = "audience"
					p["expire"] = day + AUDIENCE_WINDOW
				elif s == "audience" and not bool(p["proxy"]) and int(p["expire"]) < day:
					p["state"] = "lapsed"
					p["reasons"] = ["lapsed"]
					stats["lapsed"] = int(stats["lapsed"]) + 1
					_log_step(p, 5, "lapsed: no one came to the hearing")
			return [],
		func() -> Array:
			var heard := 0
			for k: String in _pt.keys():
				var p: Dictionary = _pt[k]
				if heard < PROXY_PER_DAY and String(p["state"]) == "audience" and bool(p["proxy"]):
					heard += 1
					_auto_hear(p)
			return [],
		func() -> Array:
			for xid: String in _dis.keys():
				var x: Dictionary = _dis[xid]
				if String(x["state"]) == "open" and int(x["due"]) <= day:
					rule_dispute(xid)
			for did: String in _doc.keys():
				var d: Dictionary = _doc[did]
				if String(d["state"]) == "valid" and int(d["expires"]) >= 0 and int(d["expires"]) < day:
					_set_state(d, "expired", "term ended")
				elif String(d["state"]) == "review" and int(d["rev"]) >= 0 and int(d["rev"]) <= day:
					_review(d)
			return []]


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	# Dues: a document with a tax term accrues arrears; NPC holders pay on their own, the player must pay_dues().
	for d: Dictionary in _doc.values():
		if String(d["state"]) != "valid" or float((d["terms"] as Dictionary).get("tax", 0.0)) <= 0.0 or String(d["type"]) in ["tax_relief", "dispute", "amnesty"]:
			continue
		if String(d["hkind"]) == "player":
			d["arrears"] = int(d["arrears"]) + 1
			if int(d["arrears"]) >= ARREARS_REVOKE:
				_set_state(d, "revoked", "dues unpaid for %d weeks" % int(d["arrears"]))
			elif int(d["arrears"]) == ARREARS_WARN:
				breach(String(d["id"]), "dues unpaid")
		elif PD.rng("dues", _now(), d["id"]).randf() < 0.97:
			d["paid"] = int(d["paid"]) + 1
		else:
			d["arrears"] = int(d["arrears"]) + 1
	return []


func _prune() -> void:
	for k: String in _pt.keys():
		var p: Dictionary = _pt[k]
		if String(p["state"]) in ["granted", "rejected", "withdrawn", "lapsed"] and _now() - int(p["filed"]) > 40:
			_pt.erase(k)
	for k: String in _doc.keys():
		var d: Dictionary = _doc[k]
		if String(d["state"]) in ["revoked", "expired"] and _now() - int(d["day"]) > 120:
			_doc.erase(k)
	for k: String in _dis.keys():
		if String(_dis[k]["state"]) != "open" and _now() - int(_dis[k]["day"]) > 60:
			_dis.erase(k)
	for k: String in _cool.keys():
		if int(_cool[k]) < _now():
			_cool.erase(k)


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	for p: Dictionary in _pt.values():
		if String(p["state"]) == "waiting":
			p["due"] = mini(int(p["due"]), _day)
	_prune()
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	return {"pt": _pt.duplicate(true), "doc": _doc.duplicate(true), "dis": _dis.duplicate(true), "rank": _rank.duplicate(true), "spons": _spons.duplicate(true), "cool": _cool.duplicate(),
		"np": _next_p, "nd": _next_d, "nx": _next_x, "day": _day, "cost": _cost.duplicate(), "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_pt = (d.get("pt", {}) as Dictionary).duplicate(true)
	for p: Dictionary in _pt.values():
		PD.fix_ints(p, ["sid", "level", "step", "filed", "due", "expire", "round", "fee", "gift", "sponsors", "rank", "wait_cap"])
		for s: Array in p["steps"]:
			s[0] = int(s[0])
			s[1] = int(s[1])
		if p["ext"].has("fid"):
			p["ext"]["fid"] = int(p["ext"]["fid"])
	_doc = (d.get("doc", {}) as Dictionary).duplicate(true)
	for x: Dictionary in _doc.values():
		PD.fix_ints(x, ["sid", "level", "day", "expires", "warn", "arrears", "paid", "rev"])
	_dis = (d.get("dis", {}) as Dictionary).duplicate(true)
	for x: Dictionary in _dis.values():
		PD.fix_ints(x, ["day", "due", "rank"])
	_rank = (d.get("rank", {}) as Dictionary).duplicate(true)
	for k: String in _rank:
		PD.fix_ints(_rank[k], ["r", "day"])
	_spons = (d.get("spons", {}) as Dictionary).duplicate(true)
	_cool = (d.get("cool", {}) as Dictionary).duplicate()
	for k: String in _cool:
		_cool[k] = int(_cool[k])
	_next_p = int(d.get("np", 1))
	_next_d = int(d.get("nd", 1))
	_next_x = int(d.get("nx", 1))
	_day = int(d.get("day", 0))
	_cost = (d.get("cost", []) as Array).duplicate()
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
