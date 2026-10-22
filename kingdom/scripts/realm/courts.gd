extends "res://scripts/realm/realm_module.gd"
## Justice (Living World section 13, LW-6.4): laws per kingdom, case records, investigation by officers, courts, appeals, corruption, inequality.
##
## LAWS PER KINGDOM. Each of the thirteen kingdoms has a legal profile (harshness, noble privilege, standard of proof, witnesses needed, how far an
## appeal may climb, how much of the people are bonded, how corrupt the bench is). A crime's sentence is derived from the profile and the crime's
## severity in society.gd CRIMES, so the same theft earns a fine in one realm and the stocks or the rope in another; set_law() changes one rule
## and every verdict after it changes.
## CASES. A case has a complainant, an accused (maybe not yet known), witnesses, evidence (from society.gd's crime and evidence items or given),
## an investigating officer, a court level, a verdict and a sentence, and a history. Officers work it daily; the judge weighs evidence and witnesses
## (a witness's weight depends on how reliable the town thinks them), the proof standard, the accused's influence, bribes and the bench's honesty.
## APPEALS climb to the next court (the crown court only for those the chamberlain would admit). A bonded person is easier to convict and cannot appeal.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const Soc := preload("res://scripts/realm/society.gd")
const Faith := preload("res://scripts/realm/faith.gd")
const SP := preload("res://scripts/realm/social_perception.gd")

## harsh 0..1, priv (noble privilege) 0..1, std (proof needed), wit (witnesses to convict), appeal (highest court level), bond (share bonded), corrupt (bench base)
const PROFILES := {
	"caldrenn": {"harsh": 0.45, "priv": 0.6, "std": 0.55, "wit": 1, "appeal": 3, "bond": 0.08, "corrupt": 0.25},
	"seirune_isles": {"harsh": 0.30, "priv": 0.2, "std": 0.62, "wit": 2, "appeal": 2, "bond": 0.00, "corrupt": 0.18},
	"ongur_khanate": {"harsh": 0.80, "priv": 0.7, "std": 0.45, "wit": 1, "appeal": 1, "bond": 0.22, "corrupt": 0.30},
	"solmarch": {"harsh": 0.40, "priv": 0.35, "std": 0.58, "wit": 2, "appeal": 3, "bond": 0.03, "corrupt": 0.20},
	"urrokai_clanlands": {"harsh": 0.65, "priv": 0.3, "std": 0.48, "wit": 1, "appeal": 1, "bond": 0.12, "corrupt": 0.15},
	"shenlu_peaks": {"harsh": 0.35, "priv": 0.5, "std": 0.60, "wit": 2, "appeal": 2, "bond": 0.02, "corrupt": 0.22},
	"veylwood": {"harsh": 0.25, "priv": 0.15, "std": 0.64, "wit": 2, "appeal": 2, "bond": 0.00, "corrupt": 0.12},
	"hollowdeep": {"harsh": 0.85, "priv": 0.8, "std": 0.42, "wit": 1, "appeal": 1, "bond": 0.35, "corrupt": 0.40},
	"varska_marches": {"harsh": 0.70, "priv": 0.55, "std": 0.50, "wit": 1, "appeal": 2, "bond": 0.18, "corrupt": 0.28},
	"serathi_lowlands": {"harsh": 0.30, "priv": 0.25, "std": 0.60, "wit": 2, "appeal": 3, "bond": 0.01, "corrupt": 0.38},
	"solkar_dominion": {"harsh": 0.90, "priv": 0.85, "std": 0.40, "wit": 1, "appeal": 3, "bond": 0.30, "corrupt": 0.35},
	"frostcrown_holds": {"harsh": 0.55, "priv": 0.4, "std": 0.52, "wit": 1, "appeal": 1, "bond": 0.10, "corrupt": 0.16},
	"umbrafen_marsh": {"harsh": 0.50, "priv": 0.1, "std": 0.50, "wit": 1, "appeal": 1, "bond": 0.15, "corrupt": 0.33},
}
const LADDER := ["fine", "jail", "exile", "execution"]
const CASE_MAX := 160
const OPEN_PER_DAY := 6
const TRIALS_PER_DAY := 2
const COLD_DAYS := 60
const APPEAL_FEE := 40
const FIELDS := ["penalty", "std", "fine_mult", "witnesses"]
## MW-22: sins a church court punishes harder; evidence kinds (physical, testimony, document, magical) come from society.gd EVIDENCE_KIND.
const MORAL := ["fraud", "extortion", "black_market", "smuggling", "assault"]
const OBL_MAX := 2000
const OBL_KINDS := {"promise": 1.0, "oath": 1.6, "favour": 0.7, "debt": 1.0}
const GRACE_DAYS := 14
const SECRET_MAX := 300
const VERBS := ["persuade", "intimidate", "blackmail", "patronage"]

var _cases: Dictionary = {}     # cid -> case
var _ovr: Dictionary = {}       # kingdom -> {crime: {field: v}}
var _prof: Dictionary = {}      # kingdom -> {field: v} changes to the profile
var _fines: Dictionary = {}     # person -> gold owed
var _jail: Dictionary = {}      # person -> release day
var _exile: Dictionary = {}     # person -> kingdom
var _pardon: Dictionary = {}    # "person|sid" -> doc
var _bond: Dictionary = {}      # kingdom -> bonded share (changes only)
var _obl: Dictionary = {}       # oid -> obligation (MW-24)
var _secrets: Array = []        # [{holder, about, text, sev, day, used, src}] (blackmail needs one)
var _next := 1
var _day := 0
var _onext := 1
var _inext := 0
var _sp: RefCounted = null
var stats := {"opened": 0, "solved": 0, "tried": 0, "guilty": 0, "acquitted": 0, "appealed": 0, "overturned": 0, "corrupt": 0, "executed": 0,
	"cleared": 0, "suborned": 0, "perjury": 0, "planted": 0, "oaths_kept": 0, "oaths_broken": 0, "influence": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


# ------------------------------------------------------------------ laws

func profile(kingdom: String) -> Dictionary:
	var p: Dictionary = (PROFILES.get(kingdom, PROFILES["caldrenn"]) as Dictionary).duplicate()
	for k: String in _prof.get(kingdom, {}):
		p[k] = _prof[kingdom][k]
	if _bond.has(kingdom):
		p["bond"] = float(_bond[kingdom])
	return p


func set_profile(kingdom: String, field: String, value: float) -> bool:
	if not PROFILES.has(kingdom) or not (field in ["harsh", "priv", "std", "wit", "appeal", "corrupt"]):
		return false
	if not _prof.has(kingdom):
		_prof[kingdom] = {}
	_prof[kingdom][field] = value
	return true


func set_law(kingdom: String, crime: String, field: String, value: Variant) -> bool:
	if not PROFILES.has(kingdom) or not Soc.CRIMES.has(crime) or not (field in FIELDS):
		return false
	if not _ovr.has(kingdom):
		_ovr[kingdom] = {}
	if not (_ovr[kingdom] as Dictionary).has(crime):
		_ovr[kingdom][crime] = {}
	_ovr[kingdom][crime][field] = value
	return true


## The law for a crime in a kingdom: {penalty, fine, jail_days, std, witnesses}.
func law(kingdom: String, crime: String) -> Dictionary:
	var def: Dictionary = Soc.CRIMES.get(crime, {})
	if def.is_empty():
		return {}
	var p := profile(kingdom)
	var o: Dictionary = (_ovr.get(kingdom, {}) as Dictionary).get(crime, {})
	var sev := float(def["sev"])
	var s := sev * (0.5 + float(p["harsh"]))
	var idx := clampi(int(floor((s - 0.5) / 1.6)), 0, 3)
	var pen := String(o.get("penalty", LADDER[idx]))
	var fm := float(o.get("fine_mult", 1.0))
	return {"penalty": pen, "fine": int(round(float(def["fine"]) * (0.6 + float(p["harsh"])) * fm)), "jail_days": int(round(sev * (4.0 + float(p["harsh"]) * 10.0))),
		"std": float(o.get("std", p["std"])), "witnesses": int(o.get("witnesses", p["wit"])), "sev": int(sev)}


func laws(kingdom: String) -> Dictionary:
	var out := {}
	for c: String in Soc.CRIMES:
		out[c] = law(kingdom, c)
	return out


# ------------------------------------------------------------------ inequality and liberation

func bonded_share(kingdom: String) -> float:
	return float(profile(kingdom)["bond"])


## "free" or "bonded" (serf or slave). Stable per person: the lowest class is bonded in proportion to the kingdom's share.
func status_of(nid: String, kingdom: String) -> String:
	var soc: Variant = _mod("society")
	if soc == null or not soc.npcs.has(nid) or int((soc.npcs[nid] as Dictionary)["class"]) > 0:
		return "free"
	return "bonded" if float(absi(hash([WorldSim.SEED, "bond", nid])) % 1000) / 1000.0 < bonded_share(kingdom) * 2.0 else "free"


func set_bond_share(kingdom: String, share: float) -> void:
	if PROFILES.has(kingdom):
		_bond[kingdom] = clampf(share, 0.0, 1.0)


## Liberation: method decree (a ruler's word), purchase (freedom bought), revolt (taken). Returns the new share.
func liberate(kingdom: String, by: String, method: String, amount := 0.05) -> float:
	var cur := bonded_share(kingdom)
	var cut := amount * (1.0 if method == "decree" else (0.6 if method == "purchase" else 1.5))
	var now := maxf(0.0, cur - cut)
	_bond[kingdom] = now
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.on_deed(by, "charity" if method != "revolt" else "seized", -1, 1.0, {"groups": ["k:" + kingdom]})
	Events.log_to(hub, "crime", "", [], "liberation", "%s frees the bonded of %s by %s" % [by, PD.kingdom_name(kingdom), method], 4)
	return now


# ------------------------------------------------------------------ cases

func case_of(cid: String) -> Dictionary:
	return (_cases.get(cid, {}) as Dictionary).duplicate(true)


func cases(state := "") -> Array:
	var out: Array = []
	var ids := _cases.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(2)) < int(b.substr(2)))
	for k: String in ids:
		if state == "" or String((_cases[k] as Dictionary)["state"]) == state:
			out.append((_cases[k] as Dictionary).duplicate(true))
	return out


func _officer(sid: int) -> Dictionary:
	var st: Variant = _mod("stewardship")
	if st == null:
		return {"id": "", "name": "the watch", "comp": 0.4, "honest": 0.5, "level": 1}
	var o: Dictionary = st.office(st.office_key(sid, 1))
	return {"id": String(o["holder"]), "name": String(o["name"]), "comp": float(o["comp"]), "honest": float(o["honest"]), "level": 1}


func _judge(sid: int, level: int) -> Dictionary:
	var st: Variant = _mod("stewardship")
	if st == null:
		return {"id": "", "name": "the bench", "comp": 0.5, "honest": 0.5}
	var o: Dictionary = st.office(st.office_key(sid, clampi(level, 1, 3)))
	return {"id": String(o["holder"]), "name": String(o["name"]), "comp": float(o["comp"]), "honest": float(o["honest"])}


## Opens a case. complainant/accused are {id, name, rank?}; accused may be {} (unknown). opts: evidence [{type,s}], witnesses [{id,name,saw,conf}], culprit id.
func file_case(crime: String, sid: int, complainant: Dictionary, accused: Dictionary, opts: Dictionary = {}) -> String:
	if not Soc.CRIMES.has(crime):
		return ""
	if _cases.size() >= CASE_MAX:
		_prune()
		if _cases.size() >= CASE_MAX:
			return ""
	var cid := "cs%d" % _next
	_next += 1
	var kingdom := String(opts.get("kingdom", PD.kingdom_of(sid)))      # opts.kingdom: the seat of law when the town's own kingdom is not the one judging
	var off := _officer(sid)
	_cases[cid] = {"id": cid, "crime": crime, "sid": sid, "kingdom": kingdom, "day": _now(), "complainant": {"id": String(complainant.get("id", "")), "name": String(complainant.get("name", "the town"))},
		"accused": {} if accused.is_empty() else {"id": String(accused["id"]), "name": String(accused.get("name", accused["id"])), "rank": int(accused.get("rank", 0))},
		"culprit": String(opts.get("culprit", "")), "witnesses": (opts.get("witnesses", []) as Array).duplicate(true), "evidence": (opts.get("evidence", []) as Array).duplicate(true),
		"state": "open", "level": 1, "officer": {"id": String(off["id"]), "name": String(off["name"])}, "progress": 0.0, "verdict": "", "sentence": {}, "hist": ["opened day %d" % _now()],
		"appeals": 0, "bribes": [], "judge": {}, "soc": String(opts.get("soc", "")), "flaw": false, "confessed": bool(opts.get("confessed", false)),
		"official": (opts.get("official", {}) as Dictionary).duplicate(), "malicious": bool(opts.get("malicious", false)), "exposed": 0, "cleared": ""}
	# A malicious accusation (the accuser knows the accused is innocent) comes with the accuser's own lying testimony.
	if bool(opts.get("malicious", false)) and not accused.is_empty() and String(complainant.get("id", "")) != "":
		(_cases[cid]["witnesses"] as Array).append({"id": String(complainant["id"]), "name": String(complainant.get("name", "")), "saw": true, "conf": 0.75,
			"state": "lying", "slant": 1, "true": false})
	stats["opened"] = int(stats["opened"]) + 1
	Events.log_to(hub, "crime", "ss:%d" % sid, [String(complainant.get("id", ""))], crime, "case opened: %s" % crime, 2)
	return cid


## Builds a case from a crime society.gd recorded: its evidence items, its witnesses' reports, and whether the culprit was recognised.
func from_society(crime_id: String) -> String:
	var soc: Variant = _mod("society")
	if soc == null:
		return ""
	var crime: Dictionary = {}
	for c: Dictionary in soc.crimes:
		if String(c["id"]) == crime_id:
			crime = c
	if crime.is_empty():
		return ""
	var ev: Array = []
	for e: Dictionary in soc.evidence(int(crime["sid"])):
		if String(e["crime"]) == crime_id:
			ev.append({"type": String(e["type"]), "s": float(e["strength"]), "day": int(e["day"])})
	var wit: Array = []
	var ids: Array = soc.npcs_in(int(crime["sid"]))
	for i in mini(int(crime["reported"]), 4):
		if i < ids.size():
			var n: Dictionary = soc.npcs[String(ids[i])]
			wit.append({"id": String(ids[i]), "name": String(n["name"]), "saw": i < int(crime["identified"]), "conf": 0.6 + float((n["pers"] as Dictionary)["honor"]) * 0.3})
	var accused: Dictionary = {"id": "player", "name": "You", "rank": 0} if int(crime["identified"]) > 0 else {}
	var comp: Dictionary = {"id": String(ids[0]) if not ids.is_empty() else "", "name": String(soc.npcs[String(ids[0])]["name"]) if not ids.is_empty() else "the town"}
	return file_case(String(crime["kind"]), int(crime["sid"]), comp, accused, {"evidence": ev, "witnesses": wit, "culprit": "player", "soc": crime_id})


## How far a person's word can be trusted in a courtroom, 0.1..1: honest and sharp and calm is high; greedy, dull or terrified is low.
## A person with no persona record is average (0.7).
func witness_reliability(nid: String) -> float:
	var pm: Variant = _mod("persona")
	if pm == null or nid == "":
		return 0.7
	var pe: Dictionary = pm.personality(nid)
	if pe.is_empty():
		return 0.7
	var r := 0.4 + 0.3 * (1.0 - float(pe["greedy"])) + 0.2 * float(pm.view(nid).get("intelligence", 128)) / 255.0
	var ps: Variant = _mod("psyche")
	if ps != null:
		var m: Dictionary = ps.mood(nid)
		r -= 0.15 * float(m.get("stress", 0.0)) + 0.1 * float(m.get("fear", 0.0))
	return clampf(r, 0.1, 1.0)


func add_witness(cid: String, nid: String, nname: String, saw: bool, conf := 0.7) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["witnesses"] as Array).size() >= 8 or String(c["state"]) in ["closed"]:
		return false
	var w := {"id": nid, "name": nname, "saw": saw, "conf": clampf(conf, 0.0, 1.0), "state": "honest", "slant": 1, "true": true}
	# A shaky witness may honestly misremember the face; the court cannot tell.
	if saw and PD.rng("wmist", _now(), [cid, nid]).randf() < (1.0 - witness_reliability(nid)) * 0.45 and witness_reliability(nid) != 0.7:
		w["state"] = "mistaken"
		w["true"] = false
	(c["witnesses"] as Array).append(w)
	return true


## Corrupt a witness. party "accuser" makes them swear to the accused's guilt, "accused" makes them recant. mode "bribe" (gold) or "threaten".
## A witness who refuses may talk: the case is marked and the court leans away from whoever tried it. Returns {ok, taken, state}.
func suborn_witness(cid: String, nid: String, party: String, mode: String, gold := 0) -> Dictionary:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["state"]) == "closed" or not (party in ["accuser", "accused"]) or not (mode in ["bribe", "threaten"]):
		return {"ok": false}
	var w := {}
	for x: Dictionary in c["witnesses"]:
		if String(x["id"]) == nid:
			w = x
	if w.is_empty():
		if (c["witnesses"] as Array).size() >= 8:
			return {"ok": false}
		w = {"id": nid, "name": nid, "saw": party == "accuser", "conf": 0.7, "state": "honest", "slant": 1, "true": party != "accuser"}
		(c["witnesses"] as Array).append(w)
	var pm: Variant = _mod("persona")
	var pe: Dictionary = pm.personality(nid) if pm != null else {}
	var greedy := float(pe.get("greedy", 0.4))
	var courage := float(pe.get("courage", 0.5))
	var p := 0.0
	if mode == "bribe":
		p = clampf(float(gold) / 120.0 * (0.4 + greedy) - (1.0 - greedy) * 0.25, 0.0, 0.92)
	else:
		p = clampf(0.75 - courage * 0.8, 0.05, 0.9)
	var taken := PD.rng("suborn", _now(), [cid, nid, party, mode, gold]).randf() < p
	if taken:
		w["state"] = "bribed" if mode == "bribe" else "afraid"
		w["true"] = party != "accuser"          # swearing against the accused is false unless the accused is the culprit (checked at clearing)
		w["slant"] = 1 if party == "accuser" else -1
		w["saw"] = true
		w["by"] = party
		stats["suborned"] = int(stats["suborned"]) + 1
	else:
		c["exposed"] = int(c["exposed"]) + (1 if party == "accuser" else -1)
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.on_deed("i:" + (String(c["complainant"]["id"]) if party == "accuser" else String((c["accused"] as Dictionary).get("id", "accused"))), "bribed", int(c["sid"]), 0.6)
		(c["hist"] as Array).append("%s tried to %s a witness and was refused" % [party, mode])
	return {"ok": true, "taken": taken, "state": String(w["state"]), "chance": snappedf(p, 0.001)}


## type: any of society.gd EVIDENCE_DECAY. opts: against (id the item points at, when not the accused: it then clears the accused), fake (planted or forged).
func add_evidence(cid: String, type: String, strength: float, opts: Dictionary = {}) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["evidence"] as Array).size() >= 10 or String(c["state"]) == "closed":
		return false
	var e := {"type": type, "s": clampf(strength, 0.0, 1.0), "day": _now()}
	if String(opts.get("against", "")) != "":
		e["against"] = String(opts["against"])
	if bool(opts.get("fake", false)):
		e["fake"] = true
	(c["evidence"] as Array).append(e)
	return true


## Church courts trust sworn testimony and distrust magic; a secular court (Valencios and the rest) weighs the thing itself.
func culture(kingdom: String) -> Dictionary:
	if not (kingdom in Faith.CHURCH_KINGDOMS):
		return {"church": false, "wit": 1.0, "phys": 1.0, "doc": 1.0, "magic": 1.0, "moral": 0.0, "power": 0.0}
	var pw := float((Faith.KINGDOM_FAITH[kingdom] as Dictionary)["power"])
	return {"church": true, "wit": 1.0 + 0.45 * pw, "phys": 1.0 - 0.2 * pw, "doc": 1.0, "magic": 1.0 - 0.5 * pw, "moral": -0.12 * pw, "power": pw}


func _ev_parts(c: Dictionary) -> Dictionary:
	var out := {"physical": 0.0, "testimony": 0.0, "document": 0.0, "magical": 0.0, "excul": 0.0}
	var who := String((c["accused"] as Dictionary).get("id", ""))
	for e: Dictionary in c["evidence"]:
		var rate := float(Soc.EVIDENCE_DECAY.get(String(e["type"]), 0.02))
		var age := float(maxi(0, _now() - int(e.get("day", c["day"]))))
		var v := float(e["s"]) * exp(-rate * age * 0.5)
		var ag := String(e.get("against", ""))
		if ag != "" and ag != who:
			out["excul"] = float(out["excul"]) + v
			continue
		var kind := String(Soc.EVIDENCE_KIND.get(String(e["type"]), "physical"))
		out[kind] = float(out[kind]) + v
	return out


func _evidence_score(c: Dictionary) -> float:
	var p := _ev_parts(c)
	var cu := culture(String(c["kingdom"]))
	var s := float(p["physical"]) * float(cu["phys"]) + float(p["testimony"]) + float(p["document"]) * float(cu["doc"]) + float(p["magical"]) * float(cu["magic"])
	return clampf(s / 1.2, 0.0, 1.0)


## Weight of what the accused's alibi and evidence pointing at someone else is worth, 0..1.
func exculpatory_score(c: Dictionary) -> float:
	return clampf(float(_ev_parts(c)["excul"]) / 0.9, 0.0, 1.0)


func _witness_score(c: Dictionary) -> float:
	var rep: Variant = _mod("reputation")
	var cu := culture(String(c["kingdom"]))
	var tot := 0.0
	var n := 0
	for w: Dictionary in c["witnesses"]:
		if not bool(w["saw"]):
			continue
		var rf := 0.8
		if rep != null:
			var rv := float(rep.axis_of("i:" + String(w["id"]), "reliability", "t:%d" % int(c["sid"])))
			rf = clampf(0.6 + rv / 250.0, 0.2, 1.0)
		var pr := witness_reliability(String(w["id"]))
		if pr != 0.7:
			rf *= 0.6 + 0.4 * pr
		if String(w.get("state", "honest")) == "afraid":
			rf *= 0.8
		var sl := int(w.get("slant", 1))
		tot += float(sl) * float(w["conf"]) * rf * (float(cu["wit"]) if sl > 0 else 0.8)
		n += 1
	return clampf(tot, -0.5, 1.0) if n > 0 else 0.0


func _saw_count(c: Dictionary) -> int:
	var n := 0
	for w: Dictionary in c["witnesses"]:
		if bool(w["saw"]) and int(w.get("slant", 1)) > 0:
			n += 1
	return n


func _case_officer(c: Dictionary) -> Dictionary:
	var o: Dictionary = c.get("official", {})
	if not o.is_empty():
		return {"id": String(o.get("id", "")), "name": String(o.get("name", "an official")), "comp": float(o.get("comp", 0.5)), "honest": float(o.get("honest", 0.5)), "level": 1}
	return _officer(int(c["sid"]))


## The player (or a ruler) hands a case to one of their own people. `official` {id, name, comp, honest}; from_follower() builds one from follower_will.
func assign_official(cid: String, official: Dictionary) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["state"]) in ["tried", "closed"]:
		return false
	c["official"] = {"id": String(official.get("id", "")), "name": String(official.get("name", "")), "comp": clampf(float(official.get("comp", 0.5)), 0.0, 1.0), "honest": clampf(float(official.get("honest", 0.5)), 0.0, 1.0)}
	c["officer"] = {"id": String(official.get("id", "")), "name": String(official.get("name", ""))}
	(c["hist"] as Array).append("handed to %s" % String(official.get("name", "")))
	return true


func from_follower(fid: String) -> Dictionary:
	var wm: Variant = _mod("will")
	if wm == null:
		return {}
	var q: Dictionary = wm.delegate_quality(fid)
	return {"id": fid, "name": fid, "comp": float(q["competence"]), "honest": float(q["honesty"])}


## One working day by the officer. Returns the progress. A solved case with an unknown accused names the culprit. A skilled officer turns up new
## proof (against the real culprit, or against a wrongly accused person's accuser); an honest one lets exculpatory proof clear the accused
## and turns the case on the true culprit; a bought one buries it.
func investigate(cid: String) -> float:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or not (String(c["state"]) in ["open", "investigating"]):
		return 0.0
	var off := _case_officer(c)
	var gain := 0.02 + 0.06 * float(off["comp"]) + 0.07 * _evidence_score(c) + 0.06 * maxf(0.0, _witness_score(c)) + (0.04 if not (c["accused"] as Dictionary).is_empty() else 0.0)
	c["progress"] = snappedf(minf(1.0, float(c["progress"]) + gain), 0.001)
	c["state"] = "investigating"
	_discover(c, off)
	if float(c["progress"]) >= 1.0:
		var acc: Dictionary = c["accused"]
		if not acc.is_empty() and String(c["culprit"]) != "" and String(c["culprit"]) != String(acc["id"]) and exculpatory_score(c) >= 0.35 and not bool(c.get("officer_bought", false)):
			_clear(c, off)
		elif acc.is_empty():
			if String(c["culprit"]) == "":
				c["state"] = "cold"
				(c["hist"] as Array).append("went cold day %d" % _now())
				return float(c["progress"])
			c["accused"] = {"id": String(c["culprit"]), "name": String(c["culprit"]), "rank": 0}
			(c["hist"] as Array).append("culprit identified day %d" % _now())
		c["state"] = "charged"
		(c["hist"] as Array).append("charged day %d" % _now())
		stats["solved"] = int(stats["solved"]) + 1
	return float(c["progress"])


func _discover(c: Dictionary, off: Dictionary) -> void:
	var cul := String(c["culprit"])
	if cul == "" or (c["evidence"] as Array).size() >= 9 or bool(c.get("officer_bought", false)):
		return
	if PD.rng("clue", _now(), [c["id"], c["progress"]]).randf() >= 0.05 + 0.25 * float(off["comp"]):
		return
	var kinds: Array = (Soc.CRIMES[String(c["crime"])] as Dictionary)["evidence"]
	var t := String(kinds[PD.rng("clue_t", _now(), c["id"]).randi() % kinds.size()])
	var acc: Dictionary = c["accused"]
	var strength := 0.3 + 0.4 * float(off["comp"])
	if acc.is_empty() or String(acc["id"]) == cul:
		add_evidence(String(c["id"]), t, strength)
	else:
		add_evidence(String(c["id"]), t, strength, {"against": cul})


## The accused is shown innocent. The case turns on the real culprit; whoever lied is marked.
func _clear(c: Dictionary, _off: Dictionary) -> void:
	var rep: Variant = _mod("reputation")
	var old: Dictionary = c["accused"]
	c["cleared"] = String(old["id"])
	(c["hist"] as Array).append("%s cleared by the evidence day %d" % [String(old.get("name", old["id"])), _now()])
	stats["cleared"] = int(stats["cleared"]) + 1
	if rep != null:
		rep.on_deed("i:" + String(old["id"]), "fair_ruling", int(c["sid"]), 0.4)
		for w: Dictionary in c["witnesses"]:
			if String(w.get("state", "honest")) in ["lying", "bribed", "afraid"] and int(w.get("slant", 1)) > 0:
				rep.on_deed("i:" + String(w["id"]), "false_witness", int(c["sid"]), 1.0)
				stats["perjury"] = int(stats["perjury"]) + 1
		if bool(c["malicious"]):
			rep.on_deed("i:" + String(c["complainant"]["id"]), "false_witness", int(c["sid"]), 1.5)
	# the false proof is struck out; the true culprit is charged
	var keep: Array = []
	for w: Dictionary in c["witnesses"]:
		if not (String(w.get("state", "honest")) in ["lying", "bribed", "afraid", "mistaken"] and int(w.get("slant", 1)) > 0):
			keep.append(w)
	c["witnesses"] = keep
	var ev: Array = []
	for e: Dictionary in c["evidence"]:
		if not bool(e.get("fake", false)):
			ev.append(e)
	c["evidence"] = ev
	c["accused"] = {"id": String(c["culprit"]), "name": String(c["culprit"]), "rank": 0}


func bring_to_court(cid: String) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["accused"] as Dictionary).is_empty() or String(c["state"]) in ["closed", "tried"]:
		return false
	c["state"] = "charged"
	return true


## Offer a bribe to the judge of this case on behalf of "accused" or "complainant". Returns {taken}; an honest bench is insulted and the briber is marked.
func bribe(cid: String, party: String, gold: int) -> Dictionary:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["state"]) == "closed" or gold <= 0:
		return {"ok": false}
	var judge := _judge(int(c["sid"]), int(c["level"]))
	var prof := profile(String(c["kingdom"]))
	var corrupt := clampf((1.0 - float(judge["honest"])) * 0.7 + float(prof["corrupt"]) * 0.5, 0.0, 0.95)
	var fnd: Variant = _mod("founding")
	if fnd != null:
		corrupt = clampf(corrupt + float(fnd.corruption_at(int(c["sid"]))) * 0.2, 0.0, 0.95)
	corrupt = clampf(corrupt + district_corruption(int(c["sid"])) * 0.2, 0.0, 0.95)
	var taken := PD.rng("cbribe", _now(), [cid, party, gold]).randf() < corrupt
	(c["bribes"] as Array).append({"by": party, "gold": gold, "taken": taken})
	if not taken:
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.on_deed("i:" + String((c["accused"] as Dictionary).get("id", party)) if party == "accused" else "i:" + party, "bribed", int(c["sid"]), 1.0)
		(c["hist"] as Array).append("%s tried to bribe the bench and was refused" % party)
	else:
		stats["corrupt"] = int(stats["corrupt"]) + 1
		_feed_corruption(int(c["sid"]), 0.03)
	return {"ok": true, "taken": taken}


## What the quarters of a town say about how bought its officials are (districts' hidden corruption value, 0..1; 0.5 when unknown).
func district_corruption(sid: int) -> float:
	var dv: Variant = _mod("districts")
	if dv == null:
		return 0.5
	var qs: Array = dv.quarters_of(sid)
	if qs.is_empty():
		return 0.5
	var t := 0.0
	for q: String in qs:
		t += float(dv.values(sid, q).get("corruption", 0.5))
	return t / float(qs.size())


func _feed_corruption(sid: int, amt: float) -> void:
	var dv: Variant = _mod("districts")
	if dv == null:
		return
	for q: String in dv.quarters_of(sid):
		dv.on_corruption(sid, q, amt)


## Bribe the investigating officer or watch. party "complainant": the officer plants proof against the accused; party "accused": proof against them goes missing.
## An honest officer refuses and the briber is marked. Returns {ok, taken}.
func bribe_officer(cid: String, party: String, gold: int) -> Dictionary:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["state"]) in ["closed", "tried"] or gold <= 0 or not (party in ["complainant", "accused"]):
		return {"ok": false}
	var off := _case_officer(c)
	var prof := profile(String(c["kingdom"]))
	var corrupt := clampf((1.0 - float(off["honest"])) * 0.75 + float(prof["corrupt"]) * 0.4 + district_corruption(int(c["sid"])) * 0.15, 0.0, 0.95)
	var taken := PD.rng("obribe", _now(), [cid, party, gold]).randf() < corrupt
	if taken:
		stats["corrupt"] = int(stats["corrupt"]) + 1
		c["officer_bought"] = true
		_feed_corruption(int(c["sid"]), 0.03)
		if party == "complainant":
			add_evidence(cid, "stolen_goods", minf(0.7, float(gold) / 120.0), {"fake": true})
			stats["planted"] = int(stats["planted"]) + 1
		else:
			for e: Dictionary in c["evidence"]:
				if String(e.get("against", "")) == "" :
					e["s"] = snappedf(float(e["s"]) * 0.4, 0.01)
		(c["hist"] as Array).append("the officer was bought")
	else:
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.on_deed("i:" + (String(c["complainant"]["id"]) if party == "complainant" else String((c["accused"] as Dictionary).get("id", "accused"))), "bribed", int(c["sid"]), 0.8)
		(c["hist"] as Array).append("%s offered the officer a bribe and was refused" % party)
	return {"ok": true, "taken": taken}


func _judgement(c: Dictionary, level: int) -> Dictionary:
	var kingdom := String(c["kingdom"])
	var lw := law(kingdom, String(c["crime"]))
	var prof := profile(kingdom)
	var judge := _judge(int(c["sid"]), level)
	var acc: Dictionary = c["accused"]
	var rep: Variant = _mod("reputation")
	var cu := culture(String(c["kingdom"]))
	var total := 0.6 * _evidence_score(c) + 0.5 * _witness_score(c) + (0.45 if bool(c["confessed"]) else 0.0)
	total -= 0.9 * exculpatory_score(c) * (1.0 if not bool(c.get("officer_bought", false)) else 0.5)
	total += 0.12 * float(clampi(int(c.get("exposed", 0)), -2, 2))
	var saw := _saw_count(c)
	var capped := false
	if saw < int(lw["witnesses"]) and not bool(c["confessed"]) and _evidence_score(c) < 0.9:
		capped = true
	var defense := 0.0
	var bonded := String(status_of(String(acc.get("id", "")), kingdom)) == "bonded"
	if rep != null and not acc.is_empty():
		var tr: Dictionary = rep.truth("i:" + String(acc["id"]))
		defense = float(tr["influence"]) / 100.0 * 0.15 + float(tr["wealth"]) / 100.0 * 0.1
	var std := float(lw["std"])
	if String(c["crime"]) in MORAL:
		std += float(cu["moral"])
	if bonded:
		std -= 0.1
	elif int(acc.get("rank", 0)) >= 2:
		std += 0.1 * float(prof["priv"])
	total -= defense
	var tainted := false
	for b: Dictionary in c["bribes"]:
		if bool(b["taken"]):
			var amt := minf(0.5, float(b["gold"]) / 200.0)
			total += -amt if String(b["by"]) == "accused" else amt
			tainted = true
	if not tainted and PD.rng("bench", _now(), [c["id"], level]).randf() < float(prof["corrupt"]) * (1.0 - float(judge["honest"])) * 0.5:
		total += (PD.rng("benchd", _now(), c["id"]).randf() - 0.4) * 0.3
		tainted = true
	if bool(c["flaw"]):
		total -= 0.2
	var guilty := total >= std and not capped
	var verdict := "guilty" if guilty else ("not_proven" if (total >= std - 0.2 or capped) else "acquitted")
	return {"verdict": verdict, "total": snappedf(total, 0.001), "std": std, "tainted": tainted, "capped": capped, "judge": judge, "bonded": bonded, "law": lw}


func _sentence(c: Dictionary, j: Dictionary) -> Dictionary:
	var lw: Dictionary = j["law"]
	var pen := String(lw["penalty"])
	var acc: Dictionary = c["accused"]
	var prof := profile(String(c["kingdom"]))
	var idx := LADDER.find(pen)
	if int(acc.get("rank", 0)) >= 2 and float(prof["priv"]) >= 0.5 and idx > 0:
		idx -= 1
	pen = String(LADDER[idx])
	var s := {"penalty": pen, "fine": int(lw["fine"]), "jail_days": 0, "waived": false}
	var cu := culture(String(c["kingdom"]))
	if bool(cu["church"]) and String(c["crime"]) in MORAL and pen != "execution":
		s["penance"] = int(round(float(cu["power"]) * 10.0))         # a church court adds penance days (works for the parish) to the sentence
	if pen == "jail":
		s["jail_days"] = int(lw["jail_days"])
	if _pardon.has("%s|%d" % [String(acc.get("id", "")), int(c["sid"])]):
		s["waived"] = true
	return s


func _apply(c: Dictionary, s: Dictionary) -> void:
	var who := String((c["accused"] as Dictionary).get("id", ""))
	if bool(s["waived"]) or who == "":
		return
	match String(s["penalty"]):
		"fine":
			_fines[who] = int(_fines.get(who, 0)) + int(s["fine"])
		"jail":
			_jail[who] = _now() + int(s["jail_days"])
			_fines[who] = int(_fines.get(who, 0)) + int(s["fine"]) / 3
		"exile":
			_exile[who] = String(c["kingdom"])
		"execution":
			stats["executed"] = int(stats["executed"]) + 1
			Events.log_to(hub, "death", "ss:%d" % int(c["sid"]), [who], "executed", "%s is executed for %s" % [String((c["accused"] as Dictionary).get("name", who)), String(c["crime"])], 5)


## Holds the trial at the case's court level. Returns the case with verdict and sentence.
func trial(cid: String) -> Dictionary:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["accused"] as Dictionary).is_empty() or not (String(c["state"]) in ["charged", "appeal"]):
		return {}
	var j := _judgement(c, int(c["level"]))
	c["judge"] = {"id": String(j["judge"]["id"]), "name": String(j["judge"]["name"]), "level": int(c["level"])}
	c["verdict"] = String(j["verdict"])
	c["tainted"] = bool(j["tainted"])
	c["total"] = float(j["total"])
	stats["tried"] = int(stats["tried"]) + 1
	if String(j["verdict"]) == "guilty":
		c["sentence"] = _sentence(c, j)
		_apply(c, c["sentence"])
		stats["guilty"] = int(stats["guilty"]) + 1
	else:
		c["sentence"] = {}
		stats["acquitted"] = int(stats["acquitted"]) + 1
	c["state"] = "tried"
	(c["hist"] as Array).append("tried by %s at level %d: %s" % [String(c["judge"]["name"]), int(c["level"]), String(c["verdict"])])
	if (c["hist"] as Array).size() > 10:
		(c["hist"] as Array).pop_front()
	var rep: Variant = _mod("reputation")
	if rep != null and String(j["verdict"]) == "guilty":
		rep.on_deed("i:" + String(c["accused"]["id"]), "stole" if String(c["crime"]) in ["robbery", "burglary", "pickpocket"] else "kept_order", int(c["sid"]), 0.5)
	var soc: Variant = _mod("society")
	if soc != null and String(c["soc"]) != "":
		for sc: Dictionary in soc.crimes:
			if String(sc["id"]) == String(c["soc"]):
				sc["solved"] = true
	Events.log_to(hub, "crime", "ss:%d" % int(c["sid"]), [String(c["accused"]["id"])], String(c["crime"]), "%s: %s" % [String(c["verdict"]), String(c["crime"])], 3)
	return c.duplicate(true)


## Appeal a verdict to the next court. `by` is a petitioner dict (id, name, fame, rank, sponsors) so the crown court can gate it like an audience.
func appeal(cid: String, by: Dictionary, grounds: Dictionary = {}) -> Dictionary:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["state"]) != "tried" or String(c["verdict"]) != "guilty":
		return {"ok": false, "reason": "There is no verdict to appeal."}
	var prof := profile(String(c["kingdom"]))
	if int(c["level"]) >= int(prof["appeal"]) or int(c["appeals"]) >= 2:
		return {"ok": false, "reason": "No higher court in %s will hear it." % PD.kingdom_name(String(c["kingdom"]))}
	if String(status_of(String((c["accused"] as Dictionary)["id"]), String(c["kingdom"]))) == "bonded":
		return {"ok": false, "reason": "The bonded have no right of appeal."}
	var nl := int(c["level"]) + 1
	if nl >= 3:
		var aud: Variant = _mod("audiences")
		if aud != null:
			var acc: Dictionary = aud.access(by, 3, int(c["sid"]))
			if not bool(acc["ok"]):
				return {"ok": false, "reason": "The chamberlain will not admit you: " + "; ".join(PackedStringArray(acc["words"]))}
	for e: Variant in grounds.get("evidence", []):
		if e is Dictionary:
			add_evidence(cid, String(e.get("type", "witness_statement")), float(e.get("s", 0.5)), {"against": String(e.get("against", ""))})
	# A tainted first trial is grounds in itself; a higher bench also looks hard at proof that looks planted.
	c["flaw"] = bool(c.get("tainted", false)) or bool(grounds.get("flaw", false))
	var hj := _judge(int(c["sid"]), nl)
	var clean: Array = []
	for e: Dictionary in c["evidence"]:
		if bool(e.get("fake", false)) and PD.rng("faked", _now(), [cid, e["type"]]).randf() < 0.35 + 0.5 * float(hj["comp"]):
			c["flaw"] = true
			(c["hist"] as Array).append("planted %s struck out on appeal" % String(e["type"]))
		else:
			clean.append(e)
	c["evidence"] = clean
	# bribed or terrified witnesses can be examined again by a better bench and recant
	for w: Dictionary in c["witnesses"]:
		if String(w.get("state", "honest")) in ["bribed", "afraid", "lying"] and int(w.get("slant", 1)) > 0 \
				and PD.rng("recant", _now(), [cid, w["id"]]).randf() < 0.3 + 0.5 * float(hj["comp"]):
			w["slant"] = 0
			w["saw"] = false
			(c["hist"] as Array).append("%s recanted before the higher court" % String(w["id"]))
	c["level"] = nl
	c["appeals"] = int(c["appeals"]) + 1
	c["state"] = "appeal"
	stats["appealed"] = int(stats["appealed"]) + 1
	var prev := String(c["verdict"])
	# Undo the first sentence before the new court decides.
	var who := String((c["accused"] as Dictionary)["id"])
	_fines.erase(who)
	_jail.erase(who)
	_exile.erase(who)
	var res := trial(cid)
	if String(res.get("verdict", "")) != "guilty" and prev == "guilty":
		stats["overturned"] = int(stats["overturned"]) + 1
	return {"ok": true, "case": res, "overturned": String(res.get("verdict", "")) != "guilty", "fee": APPEAL_FEE * nl}


func close_case(cid: String) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty():
		return false
	c["state"] = "closed"
	return true


# ------------------------------------------------------------------ sentences in force

func pardon(who: String, sid: int, doc: String) -> void:
	_pardon["%s|%d" % [who, sid]] = doc
	_fines.erase(who)
	_jail.erase(who)


func fines_due(who: String) -> int:
	return int(_fines.get(who, 0))


func pay_fine(who: String, gold: int) -> int:
	var owed := int(_fines.get(who, 0))
	var pay := mini(owed, gold)
	if owed - pay <= 0:
		_fines.erase(who)
	else:
		_fines[who] = owed - pay
	return pay


func jailed_until(who: String) -> int:
	return int(_jail.get(who, -1))


func is_exiled(who: String, kingdom: String) -> bool:
	return String(_exile.get(who, "")) == kingdom


# ------------------------------------------------------------------ MW-24 obligations

func _ledgerable(id: String) -> bool:
	return id == "player" or id.begins_with("ch:") or id.begins_with("org:") or id.begins_with("bz:")


func _church_mult(k: String, sworn: bool) -> float:
	if not sworn or k == "":
		return 1.0
	return 1.0 + float((Faith.KINGDOM_FAITH[k] as Dictionary)["power"]) if k in Faith.CHURCH_KINGDOMS else 1.15


## A promise, oath, favour or debt of honour between two people, with a due day. opts: gold (a money debt), sid, text, sworn (before a priest or on a
## relic: breaking it costs more, most in church kingdoms), public (the town heard). Returns the id, "" when full.
func make_obligation(kind: String, from: String, to: String, due: int, opts: Dictionary = {}) -> String:
	if not OBL_KINDS.has(kind) or from == "" or to == "" or from == to:
		return ""
	if _obl.size() >= OBL_MAX:
		_prune_obl()
		if _obl.size() >= OBL_MAX:
			return ""
	var oid := "ob%d" % _onext
	_onext += 1
	_obl[oid] = {"id": oid, "kind": kind, "from": from, "to": to, "due": due, "day": _now(), "gold": int(opts.get("gold", 0)), "sid": int(opts.get("sid", -1)),
		"kingdom": String(opts.get("kingdom", PD.kingdom_of(int(opts.get("sid", -1))) if int(opts.get("sid", -1)) >= 0 else "")),
		"text": String(opts.get("text", kind)), "sworn": bool(opts.get("sworn", kind == "oath")), "public": bool(opts.get("public", false)), "state": "open"}
	return oid


func obligation(oid: String) -> Dictionary:
	return (_obl.get(oid, {}) as Dictionary).duplicate()


func obligations_of(who: String, state := "open") -> Array:
	var out: Array = []
	for k: String in _obl:
		var o: Dictionary = _obl[k]
		if (String(o["from"]) == who or String(o["to"]) == who) and (state == "" or String(o["state"]) == state):
			out.append(o.duplicate())
	return out


## The obligor keeps their word. A money debt moves through the ledger when both sides have accounts, otherwise `cost` tells the caller what to deduct.
func fulfil(oid: String) -> Dictionary:
	var o: Dictionary = _obl.get(oid, {})
	if o.is_empty() or String(o["state"]) != "open":
		return {"ok": false, "reason": "Nothing owed."}
	var gold := int(o["gold"])
	var cost := 0
	if gold > 0:
		var lg: Variant = _mod("ledger")
		if lg != null and _ledgerable(String(o["from"])) and _ledgerable(String(o["to"])):
			if not bool(lg.transfer(String(o["from"]), String(o["to"]), gold, "debt")["ok"]):
				return {"ok": false, "reason": "They cannot pay.", "cost": gold}
		else:
			cost = gold
	o["state"] = "kept"
	stats["oaths_kept"] = int(stats["oaths_kept"]) + 1
	var rep: Variant = _mod("reputation")
	if rep != null:
		var deed := "oath_kept" if String(o["kind"]) == "oath" else ("paid_debt" if String(o["kind"]) == "debt" else "treaty_kept")
		rep.on_deed("i:" + String(o["from"]), deed, int(o["sid"]), 1.0, {"groups": ["i:" + String(o["to"])]} if String(o["to"]) != "" else {})
	return {"ok": true, "cost": cost}


## The word is broken. Reputation falls (reliability and trust, more for an oath and for a public one, most when sworn in a church realm), the wronged
## party remembers it, and a debt or sworn oath goes to court as fraud. Returns {ok, cost_rep}.
func break_obligation(oid: String, why := "") -> Dictionary:
	var o: Dictionary = _obl.get(oid, {})
	if o.is_empty() or String(o["state"]) != "open":
		return {"ok": false}
	o["state"] = "broken"
	o["why"] = why
	stats["oaths_broken"] = int(stats["oaths_broken"]) + 1
	var mag := float(OBL_KINDS[String(o["kind"])]) * _church_mult(String(o.get("kingdom", "")), bool(o["sworn"])) * (1.3 if bool(o["public"]) else 1.0)
	var rep: Variant = _mod("reputation")
	if rep != null:
		var groups: Array = ["i:" + String(o["to"])]
		if int(o["sid"]) >= 0:
			groups.append("t:%d" % int(o["sid"]))
		rep.on_deed("i:" + String(o["from"]), "broke_promise", int(o["sid"]), mag, {"groups": groups})
	var ps: Variant = _mod("psyche")
	if ps != null:
		ps.experience(String(o["to"]), "crime", clampf(0.25 * mag, 0.0, 1.0))
	if (String(o["kind"]) == "debt" or bool(o["sworn"])) and int(o["sid"]) >= 0:
		file_case("fraud", int(o["sid"]), {"id": String(o["to"]), "name": String(o["to"])}, {"id": String(o["from"]), "name": String(o["from"])},
			{"evidence": [{"type": "ledger_entry" if String(o["kind"]) == "debt" else "letter", "s": 0.7, "day": _now()}], "culprit": String(o["from"])})
	return {"ok": true, "weight": snappedf(mag, 0.01)}


func _prune_obl() -> void:
	for k: String in _obl.keys():
		if String(_obl[k]["state"]) != "open" and _now() - int(_obl[k]["due"]) > 120:
			_obl.erase(k)


func _tick_obligations(day: int) -> void:
	var n := 0
	for k: String in _obl.keys():
		var o: Dictionary = _obl[k]
		if String(o["state"]) != "open" or int(o["due"]) >= day or n >= 40:
			continue
		n += 1
		if String(o["from"]) == "player":
			if day - int(o["due"]) > GRACE_DAYS:
				break_obligation(k, "lapsed")
			continue
		var pm: Variant = _mod("persona")
		var pe: Dictionary = pm.personality(String(o["from"])) if pm != null else {}
		var hon := 1.0 - float(pe.get("greedy", 0.4))
		if PD.rng("oblk", day, k).randf() < 0.35 + 0.55 * hon + (0.1 if bool(o["sworn"]) else 0.0):
			if not bool(fulfil(k)["ok"]):
				break_obligation(k, "could not pay")
		else:
			break_obligation(k, "forgot or refused")


# ------------------------------------------------------------------ MW-25 social influence

## A thing `holder` knows about `about` that could ruin them. sev 0..1. Needed to blackmail.
func learn_secret(holder: String, about: String, text: String, sev: float, src := "") -> bool:
	if holder == "" or about == "" or holder == about:
		return false
	if _secrets.size() >= SECRET_MAX:
		_secrets.pop_front()
	_secrets.append({"holder": holder, "about": about, "text": text, "sev": clampf(sev, 0.0, 1.0), "day": _now(), "used": 0, "src": src})
	return true


## `holder` learns the guilt of a case's real culprit (an officer, clerk or witness who saw it).
func secret_from_case(holder: String, cid: String) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or String(c["culprit"]) == "":
		return false
	return learn_secret(holder, String(c["culprit"]), "guilty of %s" % String(c["crime"]), float((Soc.CRIMES[String(c["crime"])] as Dictionary)["sev"]) / 6.0, cid)


## The one ledger of who knows what about whom. secrets.gd (NI-8) owns what people hide and writes what is found here (src "slot:N" names the secret).
func secrets_ledger() -> Array:
	return _secrets


func secrets_known(holder: String, about := "") -> Array:
	var out: Array = []
	for sc: Dictionary in _secrets:
		if String(sc["holder"]) == holder and (about == "" or String(sc["about"]) == about):
			out.append(sc.duplicate())
	return out


func _best_secret(holder: String, about: String) -> int:
	var best := -1
	var bv := -1.0
	for i in _secrets.size():
		var sc: Dictionary = _secrets[i]
		if String(sc["holder"]) == holder and String(sc["about"]) == about:
			var v := float(sc["sev"]) * pow(0.5, float(sc["used"]))
			if v > bv:
				bv = v
				best = i
	return best


## What the target makes of the actor (social_perception.gd) mixed with the target's persona.
func _read_actor(actor: String, target: String, sid: int, opts: Dictionary) -> Dictionary:
	if _sp == null:
		_sp = SP.new()
		_sp.seed_value = int(WorldSim.SEED)
	var kingdom := PD.kingdom_of(sid) if sid >= 0 else "caldrenn"
	var subj: Dictionary = (opts.get("actor_state", {}) as Dictionary).duplicate()
	subj["id"] = actor
	var o := {"id": target, "kingdom": kingdom}
	var rep: Variant = _mod("reputation")
	if rep != null and sid >= 0:
		var v: Dictionary = rep.view("i:" + actor, "t:%d" % sid)
		if not v.is_empty():
			o["rep"] = v
	var r: Dictionary = _sp.read(o, subj, {"hub": hub, "day": _now(), "hour": _now() * 24})
	var pm: Variant = _mod("persona")
	var pe: Dictionary = pm.personality(target) if pm != null else {}
	if pe.is_empty():
		pe = {"courage": 0.5, "pious": 0.3, "greedy": 0.4, "sociable": 0.5, "lazy": 0.4}
	return {"r": r, "pe": pe}


## One resolver for persuade / intimidate / blackmail / patronage. opts: sid, ask (how much is asked 0..1), gold (patronage), actor_state (title_rank,
## weapons, gear_value ... as social_perception.gd takes them), binding (the target swears to it). Blackmail without a known secret fails at once.
## Returns {ok, success, p, verb, cost, obligation, reason}; p is the chance used (tests and UI read it, the roll is deterministic).
func influence(verb: String, actor: String, target: String, opts: Dictionary = {}) -> Dictionary:
	if not (verb in VERBS) or actor == "" or target == "" or actor == target:
		return {"ok": false, "success": false, "reason": "Not a thing you can do."}
	var sid := int(opts.get("sid", -1))
	var ask := clampf(float(opts.get("ask", 0.4)), 0.0, 1.0)
	var si := -1
	if verb == "blackmail":
		si = _best_secret(actor, target)
		if si < 0:
			return {"ok": false, "success": false, "verb": verb, "reason": "You know nothing to hold over them."}
	var rd := _read_actor(actor, target, sid, opts)
	var r: Dictionary = rd["r"]
	var pe: Dictionary = rd["pe"]
	var gold := int(opts.get("gold", 0))
	var p := 0.0
	match verb:
		"persuade":
			p = 0.30 + 0.30 * float(r["reputation"]) + 0.25 * float(r["authority"]) + 0.20 * (float(pe["sociable"]) - 0.5) - 0.40 * ask
		"intimidate":
			p = 0.15 + 0.55 * float(r["threat"]) + 0.30 * float(r["authority"]) + 0.2 * float(r["magic_pressure"]) - 0.55 * float(pe["courage"]) - 0.30 * ask + 0.15 * float(r["local_influence"]) * 0.0
		"blackmail":
			var sc: Dictionary = _secrets[si]
			p = 0.25 + 0.55 * float(sc["sev"]) * pow(0.5, float(sc["used"])) + 0.25 * (1.0 - float(pe["courage"])) + 0.1 * float(r["authority"]) - 0.25 * ask
		"patronage":
			if gold <= 0:
				return {"ok": false, "success": false, "verb": verb, "reason": "Patronage needs a gift or a post."}
			p = 0.35 + 0.35 * clampf(float(gold) / 150.0, 0.0, 1.0) + 0.3 * float(pe["greedy"]) - 0.15 * float(pe["pious"]) - 0.25 * ask
	p = snappedf(clampf(p, 0.03, 0.95), 0.001)
	_inext += 1
	var roll := PD.rng("infl", _now(), [verb, actor, target, _inext]).randf()
	var ok := roll < p
	stats["influence"] = int(stats["influence"]) + 1
	var res := {"ok": true, "success": ok, "p": p, "verb": verb, "cost": 0, "obligation": "", "reason": ""}
	var rep: Variant = _mod("reputation")
	var ps: Variant = _mod("psyche")
	match verb:
		"persuade":
			if ok and bool(opts.get("binding", false)):
				res["obligation"] = make_obligation("promise", target, actor, _now() + int(opts.get("days", 30)), {"sid": sid, "text": "agreed to " + String(opts.get("text", "a request"))})
		"intimidate":
			if ps != null:
				ps.experience(target, "crime", 0.3 if ok else 0.15)
			if rep != null and sid >= 0:
				rep.record("i:" + actor, "cruelty", 3.0 if ok else 1.5, sid)
			if ok and bool(opts.get("binding", false)):
				res["obligation"] = make_obligation("favour", target, actor, _now() + int(opts.get("days", 30)), {"sid": sid, "text": "yielded to threats"})
			elif not ok and sid >= 0 and float(pe["courage"]) > 0.6:
				file_case("assault", sid, {"id": target, "name": target}, {"id": actor, "name": actor}, {"culprit": actor, "witnesses": [{"id": target, "name": target, "saw": true, "conf": 0.7}]})
		"blackmail":
			var sc2: Dictionary = _secrets[si]
			sc2["used"] = int(sc2["used"]) + 1
			if ok:
				res["obligation"] = make_obligation("favour", target, actor, _now() + int(opts.get("days", 30)), {"sid": sid, "text": "silence about: " + String(sc2["text"])})
				if rep != null and sid >= 0:
					rep.record("i:" + actor, "legitimacy", -2.0, sid, "rumour")
			else:
				if rep != null and sid >= 0:
					rep.on_deed("i:" + actor, "extorted", sid, 0.6)
				if sid >= 0 and float(pe["courage"]) > 0.5:
					file_case("extortion", sid, {"id": target, "name": target}, {"id": actor, "name": actor}, {"culprit": actor, "witnesses": [{"id": target, "name": target, "saw": true, "conf": 0.8}]})
		"patronage":
			res["cost"] = gold
			if rep != null and sid >= 0:
				rep.on_deed("i:" + actor, "gift", sid, clampf(float(gold) / 50.0, 0.2, 3.0))
			if ok:
				res["obligation"] = make_obligation("favour", target, actor, _now() + int(opts.get("days", 60)), {"sid": sid, "text": "owes their patron", "public": bool(opts.get("public", false))})
	if not ok and verb != "patronage":
		res["reason"] = "They are not moved."
	return res


# ------------------------------------------------------------------ ticks

func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	return [func() -> Array:
			_day = day
			var worked := 0
			for k: String in _cases.keys():
				var c: Dictionary = _cases[k]
				if worked < OPEN_PER_DAY and String(c["state"]) in ["open", "investigating"]:
					worked += 1
					investigate(k)
					if _now() - int(c["day"]) > COLD_DAYS and String(c["state"]) in ["open", "investigating"]:
						c["state"] = "cold"
			return [],
		func() -> Array:
			var tried := 0
			for k: String in _cases.keys():
				var c: Dictionary = _cases[k]
				if tried < TRIALS_PER_DAY and String(c["state"]) == "charged" and String((c["accused"] as Dictionary).get("id", "")) != "player" and _now() - int(c["day"]) >= 3:
					tried += 1
					trial(k)
			for w: String in _jail.keys():
				if int(_jail[w]) <= day:
					_jail.erase(w)
			_tick_obligations(day)
			return []]


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _prune() -> void:
	for k: String in _cases.keys():
		var c: Dictionary = _cases[k]
		if String(c["state"]) in ["closed", "cold"] or (String(c["state"]) == "tried" and _now() - int(c["day"]) > 90):
			_cases.erase(k)


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	for w: String in _jail.keys():
		if int(_jail[w]) <= _day:
			_jail.erase(w)
	_tick_obligations(_day)
	_prune()
	return []


func serialize() -> Dictionary:
	return {"cases": _cases.duplicate(true), "ovr": _ovr.duplicate(true), "prof": _prof.duplicate(true), "fines": _fines.duplicate(), "jail": _jail.duplicate(), "exile": _exile.duplicate(),
		"pardon": _pardon.duplicate(), "bond": _bond.duplicate(), "next": _next, "day": _day, "stats": stats.duplicate(),
		"obl": _obl.duplicate(true), "secrets": _secrets.duplicate(true), "onext": _onext, "inext": _inext}


func deserialize(d: Dictionary) -> void:
	_cases = (d.get("cases", {}) as Dictionary).duplicate(true)
	for c: Dictionary in _cases.values():
		PD.fix_ints(c, ["sid", "day", "level", "appeals", "exposed"])
		for w: Dictionary in c["witnesses"]:
			if w.has("slant"):
				w["slant"] = int(w["slant"])
		for e: Dictionary in c["evidence"]:
			if e.has("day"):
				e["day"] = int(e["day"])
	_ovr = (d.get("ovr", {}) as Dictionary).duplicate(true)
	for k: String in _ovr:
		for cr: String in _ovr[k]:
			if (_ovr[k][cr] as Dictionary).has("witnesses"):
				_ovr[k][cr]["witnesses"] = int(_ovr[k][cr]["witnesses"])
	_prof = (d.get("prof", {}) as Dictionary).duplicate(true)
	for k: String in _prof:
		for f: String in ["wit", "appeal"]:
			if (_prof[k] as Dictionary).has(f):
				_prof[k][f] = int(_prof[k][f])
	_fines = (d.get("fines", {}) as Dictionary).duplicate()
	for k: String in _fines:
		_fines[k] = int(_fines[k])
	_jail = (d.get("jail", {}) as Dictionary).duplicate()
	for k: String in _jail:
		_jail[k] = int(_jail[k])
	_exile = (d.get("exile", {}) as Dictionary).duplicate()
	_pardon = (d.get("pardon", {}) as Dictionary).duplicate()
	_bond = (d.get("bond", {}) as Dictionary).duplicate()
	_next = int(d.get("next", 1))
	_day = int(d.get("day", 0))
	_onext = int(d.get("onext", 1))
	_inext = int(d.get("inext", 0))
	_obl = (d.get("obl", {}) as Dictionary).duplicate(true)
	for o: Dictionary in _obl.values():
		PD.fix_ints(o, ["due", "day", "gold", "sid"])
	_secrets = (d.get("secrets", []) as Array).duplicate(true)
	for sc: Dictionary in _secrets:
		PD.fix_ints(sc, ["day", "used"])
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
