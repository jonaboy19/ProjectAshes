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

var _cases: Dictionary = {}     # cid -> case
var _ovr: Dictionary = {}       # kingdom -> {crime: {field: v}}
var _prof: Dictionary = {}      # kingdom -> {field: v} changes to the profile
var _fines: Dictionary = {}     # person -> gold owed
var _jail: Dictionary = {}      # person -> release day
var _exile: Dictionary = {}     # person -> kingdom
var _pardon: Dictionary = {}    # "person|sid" -> doc
var _bond: Dictionary = {}      # kingdom -> bonded share (changes only)
var _next := 1
var _day := 0
var stats := {"opened": 0, "solved": 0, "tried": 0, "guilty": 0, "acquitted": 0, "appealed": 0, "overturned": 0, "corrupt": 0, "executed": 0}


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
	var kingdom := PD.kingdom_of(sid)
	var off := _officer(sid)
	_cases[cid] = {"id": cid, "crime": crime, "sid": sid, "kingdom": kingdom, "day": _now(), "complainant": {"id": String(complainant.get("id", "")), "name": String(complainant.get("name", "the town"))},
		"accused": {} if accused.is_empty() else {"id": String(accused["id"]), "name": String(accused.get("name", accused["id"])), "rank": int(accused.get("rank", 0))},
		"culprit": String(opts.get("culprit", "")), "witnesses": (opts.get("witnesses", []) as Array).duplicate(true), "evidence": (opts.get("evidence", []) as Array).duplicate(true),
		"state": "open", "level": 1, "officer": {"id": String(off["id"]), "name": String(off["name"])}, "progress": 0.0, "verdict": "", "sentence": {}, "hist": ["opened day %d" % _now()],
		"appeals": 0, "bribes": [], "judge": {}, "soc": String(opts.get("soc", "")), "flaw": false, "confessed": bool(opts.get("confessed", false))}
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


func add_witness(cid: String, nid: String, nname: String, saw: bool, conf := 0.7) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["witnesses"] as Array).size() >= 8 or String(c["state"]) in ["closed"]:
		return false
	(c["witnesses"] as Array).append({"id": nid, "name": nname, "saw": saw, "conf": clampf(conf, 0.0, 1.0)})
	return true


func add_evidence(cid: String, type: String, strength: float) -> bool:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or (c["evidence"] as Array).size() >= 10 or String(c["state"]) == "closed":
		return false
	(c["evidence"] as Array).append({"type": type, "s": clampf(strength, 0.0, 1.0), "day": _now()})
	return true


func _evidence_score(c: Dictionary) -> float:
	var s := 0.0
	for e: Dictionary in c["evidence"]:
		var rate := float(Soc.EVIDENCE_DECAY.get(String(e["type"]), 0.02))
		var age := float(maxi(0, _now() - int(e.get("day", c["day"]))))
		s += float(e["s"]) * exp(-rate * age * 0.5)
	return clampf(s / 1.2, 0.0, 1.0)


func _witness_score(c: Dictionary) -> float:
	var rep: Variant = _mod("reputation")
	var tot := 0.0
	var n := 0
	for w: Dictionary in c["witnesses"]:
		if not bool(w["saw"]):
			continue
		var rf := 0.8
		if rep != null:
			var rv := float(rep.axis_of("i:" + String(w["id"]), "reliability", "t:%d" % int(c["sid"])))
			rf = clampf(0.6 + rv / 250.0, 0.2, 1.0)
		tot += float(w["conf"]) * rf
		n += 1
	return clampf(tot, 0.0, 1.0) if n > 0 else 0.0


func _saw_count(c: Dictionary) -> int:
	var n := 0
	for w: Dictionary in c["witnesses"]:
		if bool(w["saw"]):
			n += 1
	return n


## One working day by the officer. Returns the progress. A solved case with an unknown accused names the culprit.
func investigate(cid: String) -> float:
	var c: Dictionary = _cases.get(cid, {})
	if c.is_empty() or not (String(c["state"]) in ["open", "investigating"]):
		return 0.0
	var off := _officer(int(c["sid"]))
	var gain := 0.02 + 0.06 * float(off["comp"]) + 0.07 * _evidence_score(c) + 0.06 * _witness_score(c) + (0.04 if not (c["accused"] as Dictionary).is_empty() else 0.0)
	c["progress"] = snappedf(minf(1.0, float(c["progress"]) + gain), 0.001)
	c["state"] = "investigating"
	if float(c["progress"]) >= 1.0:
		if (c["accused"] as Dictionary).is_empty():
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
	var taken := PD.rng("cbribe", _now(), [cid, party, gold]).randf() < corrupt
	(c["bribes"] as Array).append({"by": party, "gold": gold, "taken": taken})
	if not taken:
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.on_deed("i:" + String((c["accused"] as Dictionary).get("id", party)) if party == "accused" else "i:" + party, "bribed", int(c["sid"]), 1.0)
		(c["hist"] as Array).append("%s tried to bribe the bench and was refused" % party)
	else:
		stats["corrupt"] = int(stats["corrupt"]) + 1
	return {"ok": true, "taken": taken}


func _judgement(c: Dictionary, level: int) -> Dictionary:
	var kingdom := String(c["kingdom"])
	var lw := law(kingdom, String(c["crime"]))
	var prof := profile(kingdom)
	var judge := _judge(int(c["sid"]), level)
	var acc: Dictionary = c["accused"]
	var rep: Variant = _mod("reputation")
	var total := 0.6 * _evidence_score(c) + 0.5 * _witness_score(c) + (0.45 if bool(c["confessed"]) else 0.0)
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
			add_evidence(cid, String(e.get("type", "witness_statement")), float(e.get("s", 0.5)))
	# A tainted first trial is grounds in itself.
	c["flaw"] = bool(c.get("tainted", false)) or bool(grounds.get("flaw", false))
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
	_prune()
	return []


func serialize() -> Dictionary:
	return {"cases": _cases.duplicate(true), "ovr": _ovr.duplicate(true), "prof": _prof.duplicate(true), "fines": _fines.duplicate(), "jail": _jail.duplicate(), "exile": _exile.duplicate(),
		"pardon": _pardon.duplicate(), "bond": _bond.duplicate(), "next": _next, "day": _day, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_cases = (d.get("cases", {}) as Dictionary).duplicate(true)
	for c: Dictionary in _cases.values():
		PD.fix_ints(c, ["sid", "day", "level", "appeals"])
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
	var st: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
