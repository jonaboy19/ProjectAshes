extends "res://scripts/realm/realm_module.gd"
## War intelligence, envoys and the weekly digest (MW-15, MW-16, MW-26, MW-33; docs/design/LIVING_WORLD_MASTER_PLAN.md).
## This module sits on top of armies.gd (couriers, `leg`, fog of war, battle snapshots), news.gd (road delay, tavern/board channels), audiences.gd
## (audience window), factions.gd (relations, kin ties), ledger.gd (steward weekly summary) and events.gd. It owns only what they lacked:
##
## SCOUT REPORTS. A scout has skill, integrity, fear and loyalty. The report they bring is the truth seen through those traits: a skilled, calm scout
## counts well; a frightened one undercounts, is late and mixes up banners; a bribed one lies. Reports travel by messenger (armies.leg: distance,
## weather, enemy patrols) so they arrive late, may be lost on the road, and are old when read. Two scouts can disagree (conflicts()). The player sees a
## reliability tag built only from what can be observed (skill, demeanour, track record), so a bribed liar can still look reliable.
##
## ENVOY AUDIENCES. An envoy asks for something (neutrality, passage, aid, alliance, tribute) with a personal agenda (sincere, arrogant, desperate,
## deceptive, rogue = acting against orders). The ruler answers with accept, refuse, negotiate, delay, ask_intel, mediate, demand_compensation,
## secretly_aid or delegate_council. The outcome is computed from hidden state (trade, kin, trust, fear, grievance, power, secret aid), never a bare dice
## roll: the same words give "respected", "pressured", "strained" or "violated" neutrality depending on what is underneath.
##
## WEEKLY DIGEST. One letter a week at most: the steward's report (only if a steward exists), rumours as the tavern or the board would have them (news.gd
## delay applies) and scout reports that have actually arrived. A ruler gets numbers and reliability tags; an adventurer gets vague words and fewer lines.
## Urgent word is only for a hostile army the viewer already knows is near their own ground, at most one a day.
## Everything is deterministic (hash of WorldSim.SEED, tag, ids) and JSON-safe.

const Events := preload("res://scripts/realm/events.gd")

const REPORT_CAP := 60
const ENVOY_CAP := 24
const INBOX_CAP := 12
const POWER_CAP := 12
const AUDIENCE_DAYS := 10
const DIGEST_RULER := 6
const DIGEST_ADV := 3
const THREAT_RADIUS := 420.0
const URGENT_GAP_DAYS := 3
const AGENDAS := ["sincere", "arrogant", "desperate", "deceptive", "rogue"]
const ASKS := ["neutrality", "passage", "aid", "alliance", "tribute"]
const RESPONSES := ["accept", "refuse", "negotiate", "delay", "ask_intel", "mediate", "demand_compensation", "secretly_aid", "delegate_council"]
const BANNERS := ["the Crown", "a mercenary band", "the northern lords", "an unknown company", "the border wardens"]

var _scouts: Dictionary = {}     # id -> {skill, integ, fear, loy, bribe, n, right}
var _power: Array = []           # power reports (AR-9): [id, owner, scout, sid, level 0..100, flags, as_of_h, ready_h, fate]
var _next_p := 1
var _reports: Array = []         # delivered or in transit, see scout_report()
var _next_r := 1
var _envoys: Array = []
var _next_e := 1
var _viewer: Dictionary = {}     # {acct, sid, role, owner, holdings:[sid]}
var _inbox: Array = []
var _next_d := 1
var _last_week := -1
var _urgent_day: Dictionary = {}  # army id -> day last warned
var _urgent_last := -100
var _gold := 0
var stats := {"reports": 0, "lost": 0, "forged": 0, "envoys": 0, "digests": 0, "urgent": 0}


# ------------------------------------------------------------------ helpers

func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


static func _h(tag: String, a: Variant, b: Variant = 0) -> float:
	return float(absi(hash([WorldSim.SEED, "wi_" + tag, a, b])) % 10000) / 10000.0


func _now_h() -> int:
	var ar: Variant = _mod("armies")
	return int(ar.hours()) if ar != null else 0


func _day_now() -> int:
	return _now_h() / 24


func _frel(a: String, b: String) -> Dictionary:
	var f: Variant = _mod("factions")
	if f == null:
		return {"trust": 40.0, "fear": 0.0, "grievance": 0.0, "trade": 0.0, "stance": "neutral"}
	return f.relation(a, b)


func _fpower(id: String) -> float:
	var f: Variant = _mod("factions")
	if f == null:
		return 5.0
	var d: Dictionary = f.faction(id)
	return float(d.get("power", 5.0)) if not d.is_empty() else 5.0


func _kin(a: String, b: String) -> float:
	var f: Variant = _mod("factions")
	if f == null:
		return 0.0
	var best := 0.0
	for t: Dictionary in f.ties(true):
		if String(t["kind"]) in ["kin", "alliance"] and ((String(t["a"]) == a and String(t["b"]) == b) or (String(t["a"]) == b and String(t["b"]) == a)):
			best = maxf(best, float(t["strength"]))
	return best


func _vague(n: int) -> String:
	if n <= 5:
		return "a handful"
	if n <= 20:
		return "a score or so"
	if n <= 60:
		return "a few dozen"
	if n <= 200:
		return "a few hundred"
	return "a great host"


# ------------------------------------------------------------------ scouts and reports (MW-15, MW-26)

## Makes or updates a scout. Missing fields come from a hash of the id (and the character's persona through ledger.traits when it is a ch: id).
func register_scout(id: String, traits: Dictionary = {}) -> Dictionary:
	var s: Dictionary = _scouts.get(id, {})
	if s.is_empty():
		var integ := _h("integ", id)
		var loy := _h("loy", id)
		var lg: Variant = _mod("ledger")
		if lg != null and id.begins_with("ch:"):
			var t: Dictionary = lg.traits(id)
			integ = float(t["honesty"])
			loy = float(t["loyalty"])
		s = {"skill": _h("skill", id), "integ": integ, "fear": _h("fear", id) * 0.8, "loy": loy, "bribe": 0.0, "n": 0, "right": 0}
	for k: String in ["skill", "integ", "fear", "loy", "bribe"]:
		if traits.has(k):
			s[k] = clampf(float(traits[k]), 0.0, 1.0)
	_scouts[id] = s
	return s.duplicate()


## An enemy (or anyone) pays the scout: 0..1 how much. Only an unprincipled or disloyal scout turns on it (see scout_report).
func bribe_scout(id: String, amount: float) -> void:
	register_scout(id)
	(_scouts[id] as Dictionary)["bribe"] = clampf(amount, 0.0, 1.0)


func scout(id: String) -> Dictionary:
	return (_scouts.get(id, {}) as Dictionary).duplicate()


## What a ruler can tell about a scout by looking: skill and nerves show, a bribe does not. Track record counts once there are three reports.
func reliability_tag(id: String) -> String:
	var s: Dictionary = _scouts.get(id, {})
	if s.is_empty():
		return "unknown"
	var score := float(s["skill"]) - 0.4 * float(s["fear"])
	if int(s["n"]) >= 3:
		score = 0.5 * score + 0.5 * (float(s["right"]) / float(s["n"]))
	if score >= 0.6:
		return "reliable"
	if score >= 0.35:
		return "uncertain"
	return "doubtful"


## A scout of `owner` looks at army `target_aid` (armies.gd). The truth is read here; what is kept is the scout's account of it, sent by messenger to the
## owner's post (or `opts.to` = [x, y]). Returns {ok, id, ready_h, fate}. The report is invisible to the owner until ready_h and never arrives if it is lost.
func scout_report(owner: String, scout_id: String, target_aid: String, opts: Dictionary = {}) -> Dictionary:
	var ar: Variant = _mod("armies")
	if ar == null:
		return {"ok": false}
	var tg: Dictionary = ar.army(target_aid)
	if tg.is_empty():
		return {"ok": false, "reason": "no_target"}
	var s: Dictionary = _scouts.get(scout_id, {})
	if s.is_empty():
		s = register_scout(scout_id)
		s = _scouts[scout_id]
	var rid := _next_r
	_next_r += 1
	var skill := float(s["skill"])
	var fear := float(s["fear"])
	var true_n := int(ar.men(target_aid))
	var true_owner := String(tg["owner"])
	var flags: Array = []
	var n := float(true_n)
	var err := 0.06 + (1.0 - skill) * 0.45 + fear * 0.15
	n *= 1.0 + (_h("n", rid, scout_id) - 0.5) * 2.0 * err
	if fear > 0.55 or skill < 0.3:
		n *= 0.55 + 0.3 * _h("under", rid, scout_id)
		flags.append("partial")
	var banner := true_owner
	if _h("banner", rid, scout_id) < (1.0 - skill) * 0.4 * (1.0 + fear):
		banner = BANNERS[int(_h("bsel", rid, scout_id) * BANNERS.size())]
		if banner == true_owner:
			banner = "a rival banner"
		flags.append("wrong_banner")
	var lie_p := 0.0
	if float(s["bribe"]) > 0.0:
		lie_p = clampf(float(s["bribe"]) * ((1.0 - float(s["integ"])) * 0.9 + (1.0 - float(s["loy"])) * 0.5), 0.0, 1.0)
	if lie_p > 0.0 and _h("lie", rid, scout_id) < lie_p:
		n = float(true_n) * (0.35 if _h("lieway", rid, scout_id) < 0.6 else 2.2)
		flags.append("bribed")
	var jit := err * 160.0
	var pos := [float(tg["pos"][0]) + (_h("px", rid) - 0.5) * 2.0 * jit, float(tg["pos"][1]) + (_h("py", rid) - 0.5) * 2.0 * jit]
	var now := _now_h()
	var to: Array = opts.get("to", ar.hq(owner))
	var hrs := 1
	var risk := 0.0
	if not to.is_empty():
		var lg: Dictionary = ar.leg(owner, tg["pos"], to)
		hrs = int(lg["hours"])
		risk = float(lg["risk"])
	var late := int(round(fear * 18.0 + (1.0 - skill) * 10.0)) + int(opts.get("late_h", 0))
	var fate := "ok"
	if risk > 0.0 and _h("road", rid, scout_id) < risk:
		fate = "lost"
		stats["lost"] = int(stats["lost"]) + 1
	var r := {"id": rid, "owner": owner, "scout": scout_id, "tgt": target_aid, "banner": banner, "n": maxi(0, int(round(n))), "pos": [snappedf(pos[0], 0.1), snappedf(pos[1], 0.1)],
		"as_of": now, "ready": now + hrs + late, "fate": fate, "flags": flags, "true_n": true_n, "true_owner": true_owner}
	_reports.append(r)
	if _reports.size() > REPORT_CAP:
		_reports.pop_front()
	stats["reports"] = int(stats["reports"]) + 1
	return {"ok": true, "id": rid, "ready_h": int(r["ready"]), "fate": fate, "late_h": late}


## AR-9: a scout reports a terrifying power (the player's aura, read from aura_fallout) in town `sid`. What is kept is the scout's account: the level is
## off by the scout's error, a frightened scout inflates it, a poor one under-reports, and the report is late and sometimes lost. Bounded ring (POWER_CAP).
## Returns {ok, id, ready_h, fate} or {ok:false, reason}.
func scout_power(owner: String, scout_id: String, sid: int, subject := "i:player", opts: Dictionary = {}) -> Dictionary:
	var af: Variant = _mod("aura_fallout")
	if af == null:
		return {"ok": false, "reason": "no_aura"}
	var truth: float = maxf(float(af.dread_felt(subject, sid)), float(af.awe(subject, sid)))
	if truth < 10.0:
		return {"ok": false, "reason": "nothing_to_report"}
	var s: Dictionary = _scouts.get(scout_id, {})
	if s.is_empty():
		register_scout(scout_id)
		s = _scouts[scout_id]
	var pid := _next_p
	_next_p += 1
	var skill := float(s["skill"])
	var fear := float(s["fear"])
	var err := 0.1 + (1.0 - skill) * 0.5 + fear * 0.2
	var lvl := truth * (1.0 + (_h("pw", pid, scout_id) - 0.5) * 2.0 * err)
	var flags: Array = []
	if fear > 0.55:
		lvl *= 1.0 + fear * 0.3
		flags.append("exaggerated")
	elif skill < 0.3:
		lvl *= 0.6
		flags.append("underplayed")
	var now := _now_h()
	var late := int(round(fear * 18.0 + (1.0 - skill) * 10.0)) + int(opts.get("hours", 24))
	var fate := "lost" if _h("plost", pid, scout_id) < float(opts.get("risk", 0.05)) else "ok"
	if fate == "lost":
		stats["lost"] = int(stats["lost"]) + 1
	_power.append([pid, owner, scout_id, sid, int(round(clampf(lvl, 0.0, 100.0))), flags, now, now + late, fate])
	while _power.size() > POWER_CAP:
		_power.pop_front()
	stats["reports"] = int(stats["reports"]) + 1
	return {"ok": true, "id": pid, "ready_h": now + late, "fate": fate}


## Arrived power reports of an owner, newest last: {id, scout, sid, level, word, age_h, tag}. `word` is deliberately vague.
func power_reports(owner: String) -> Array:
	var now := _now_h()
	var out: Array = []
	for r: Array in _power:
		if String(r[1]) != owner or String(r[8]) == "lost" or int(r[7]) > now:
			continue
		var lv := int(r[4])
		var word := "a rumour of something strange" if lv < 30 else ("a power that frightens grown men" if lv < 60 else "a terrifying power that empties streets")
		out.append({"id": int(r[0]), "scout": r[2], "sid": int(r[3]), "level": lv, "word": word, "age_h": now - int(r[6]), "tag": reliability_tag(String(r[2]))})
	return out


## The reports an owner can read now: delivered ones only (a lost one never shows), with age, the observable tag, and no hint of hidden flags.
func reports(owner: String, target_aid := "") -> Array:
	var now := _now_h()
	var out: Array = []
	for r: Dictionary in _reports:
		if String(r["owner"]) != owner or String(r["fate"]) == "lost" or int(r["ready"]) > now:
			continue
		if target_aid != "" and String(r["tgt"]) != target_aid:
			continue
		out.append({"id": int(r["id"]), "scout": r["scout"], "tgt": r["tgt"], "banner": r["banner"], "n": int(r["n"]), "pos": (r["pos"] as Array).duplicate(),
			"as_of": int(r["as_of"]), "age_h": now - int(r["as_of"]), "tag": reliability_tag(String(r["scout"])), "partial": "partial" in (r["flags"] as Array)})
	return out


## Pairs of arrived reports on the same army that cannot both be right (counts more than 40 % apart, different banners, or places far apart).
func conflicts(owner: String, target_aid: String) -> Array:
	var rs := reports(owner, target_aid)
	var out: Array = []
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			var a: Dictionary = rs[i]
			var b: Dictionary = rs[j]
			var hi := float(maxi(int(a["n"]), int(b["n"])))
			var count_gap := hi > 0.0 and absf(float(int(a["n"]) - int(b["n"]))) / hi > 0.4
			var banner_gap: bool = String(a["banner"]) != String(b["banner"])
			var dx := float(a["pos"][0]) - float(b["pos"][0])
			var dy := float(a["pos"][1]) - float(b["pos"][1])
			var place_gap: bool = dx * dx + dy * dy > 300.0 * 300.0
			if count_gap or banner_gap or place_gap:
				out.append({"a": int(a["id"]), "b": int(b["id"]), "count": count_gap, "banner": banner_gap, "place": place_gap})
	return out


## Later, once the truth is known, the scout's record is updated (so their tag moves). True when the report was within 30 % and had the right banner.
func verify(report_id: int) -> bool:
	for r: Dictionary in _reports:
		if int(r["id"]) == report_id and not bool(r.get("checked", false)):
			r["checked"] = true
			var s: Dictionary = _scouts.get(String(r["scout"]), {})
			var ok: bool = absf(float(int(r["n"]) - int(r["true_n"]))) <= 0.3 * float(maxi(1, int(r["true_n"]))) and String(r["banner"]) == String(r["true_owner"])
			if not s.is_empty():
				s["n"] = int(s["n"]) + 1
				s["right"] = int(s["right"]) + (1 if ok else 0)
			return ok
	return false


## Acting on old news: how far an arrived report has drifted from the army it was about (distance in metres), for debriefs and tests.
func drift(report_id: int) -> float:
	var ar: Variant = _mod("armies")
	for r: Dictionary in _reports:
		if int(r["id"]) == report_id and ar != null:
			var tg: Dictionary = ar.army(String(r["tgt"]))
			if tg.is_empty():
				return -1.0
			return sqrt(pow(float(tg["pos"][0]) - float(r["pos"][0]), 2.0) + pow(float(tg["pos"][1]) - float(r["pos"][1]), 2.0))
	return -1.0


# ------------------------------------------------------------------ envoys (MW-16)

## The agenda is read off the two sides: a weak or poor envoy side is desperate, a much stronger one arrogant, old grievance breeds deceit; one envoy in
## twelve acts against orders. `opts.agenda` forces it (scenarios, tests).
func _agenda_for(from: String, to: String, eid: int) -> String:
	var rel := _frel(from, to)
	var pf := _fpower(from)
	var pt := _fpower(to)
	if _h("rogue", eid, from) < 0.08:
		return "rogue"
	if float(rel["grievance"]) > 30.0 and float(rel["trust"]) < 45.0:
		return "deceptive"
	if pf < pt * 0.6:
		return "desperate"
	if pf > pt * 1.5:
		return "arrogant"
	return "sincere"


## An envoy of faction `from` arrives at the court of `to` (the ruler's realm). ask: one of ASKS; `against` the other side the ask concerns.
func envoy_arrive(from: String, to: String, ask: String, against := "", opts: Dictionary = {}) -> Dictionary:
	if not (ask in ASKS):
		return {"ok": false, "reason": "unknown_ask"}
	var eid := _next_e
	_next_e += 1
	var agenda := String(opts.get("agenda", _agenda_for(from, to, eid)))
	var day := _day_now()
	var e := {"id": eid, "from": from, "to": to, "ask": ask, "against": against, "agenda": agenda, "state": "waiting", "day": day, "until": day + AUDIENCE_DAYS,
		"delayed": 0, "informed": false, "secret_aid": false, "gift": int(opts.get("gift", 0)), "sid": int(opts.get("sid", -1)), "outcome": ""}
	_envoys.append(e)
	if _envoys.size() > ENVOY_CAP:
		_envoys.pop_front()
	stats["envoys"] = int(stats["envoys"]) + 1
	Events.log_to(hub, "audience", ("ss:%d" % int(e["sid"])) if int(e["sid"]) >= 0 else "", [], "envoy", "An envoy of %s asks for %s" % [from, ask], 3)
	return {"ok": true, "id": eid, "agenda": "unknown", "bearing": _bearing(e)}


## What the court can see of the envoy without asking: manner only (a deceiver and a sincere envoy can look alike, but not always).
func _bearing(e: Dictionary) -> String:
	var tell := _h("tell", int(e["id"]), String(e["agenda"]))
	match String(e["agenda"]):
		"arrogant":
			return "carries himself like a conqueror"
		"desperate":
			return "looks worn and anxious"
		"deceptive":
			return "smiles a little too easily" if tell < 0.6 else "is warm and entirely composed"
		"rogue":
			return "keeps glancing at his own seal" if tell < 0.5 else "speaks of terms nobody sent him to offer"
	return "speaks plainly"


func envoy(eid: int) -> Dictionary:
	for e: Dictionary in _envoys:
		if int(e["id"]) == eid:
			return e
	return {}


## Envoys waiting for an audience; expired ones leave offended.
func envoys(state := "waiting") -> Array:
	var out: Array = []
	for e: Dictionary in _envoys:
		if state == "" or String(e["state"]) == state:
			var v := (e as Dictionary).duplicate()
			v["agenda"] = "unknown" if not bool(e["informed"]) else e["agenda"]
			out.append(v)
	return out


## The hidden state behind a neutrality (or any) ask. Public for tests and for a "what do my advisors say" screen that the player pays for.
func hidden_state(eid: int) -> Dictionary:
	var e := envoy(eid)
	if e.is_empty():
		return {}
	var to := String(e["to"])
	var from := String(e["from"])
	var other := String(e["against"])
	var rel_o := _frel(to, other) if other != "" else {"trust": 40.0, "fear": 0.0, "grievance": 0.0, "trade": 0.0}
	var rel_e := _frel(to, from)
	var bond_other := 0.6 * float(rel_o["trade"]) + 40.0 * _kin(to, other) + 0.3 * float(rel_o["trust"]) if other != "" else 0.0
	var bond_env := 0.6 * float(rel_e["trade"]) + 40.0 * _kin(to, from) + 0.3 * float(rel_e["trust"])
	var pressure := float(rel_e["fear"]) + 0.3 * float(rel_e["grievance"]) + 12.0 * _fpower(from) / maxf(1.0, _fpower(to))
	if String(e["agenda"]) in ["arrogant", "rogue"]:
		pressure += 8.0
	return {"bond_other": snappedf(bond_other, 0.1), "bond_env": snappedf(bond_env, 0.1), "pressure": snappedf(pressure, 0.1), "grievance_env": float(rel_e["grievance"]),
		"trust_env": float(rel_e["trust"]), "secret_aid": bool(e["secret_aid"])}


## The neutrality label that a stance would earn from the hidden state: respected, pressured (the envoy side's weight bends it), strained (ties to the other side
## pull), violated (secret help, found out).
func neutrality_label(eid: int, discovered := false) -> String:
	var hs := hidden_state(eid)
	if hs.is_empty():
		return ""
	if bool(hs["secret_aid"]) and discovered:
		return "violated"
	if float(hs["pressure"]) > float(hs["bond_other"]) + 12.0 and float(hs["pressure"]) >= 30.0:
		return "pressured"
	if float(hs["bond_other"]) >= 45.0:
		return "strained"
	return "respected"


func _shift_rel(a: String, b: String, field: String, d: float) -> void:
	var f: Variant = _mod("factions")
	if f != null:
		f.change_relation(a, b, field, d)


## Answers an envoy. opts: gift (gold given), insight 0..1 (how well the court reads people, default 0.5), council 0..1 (skill of the council, default 0.5).
## Returns {ok, response, outcome, text, effects}. `outcome` is a short code the UI maps to words; the hidden state is not returned.
func respond(eid: int, response: String, opts: Dictionary = {}) -> Dictionary:
	var e := envoy(eid)
	if e.is_empty() or String(e["state"]) in ["closed"]:
		return {"ok": false, "reason": "no_envoy"}
	if not (response in RESPONSES):
		return {"ok": false, "reason": "unknown_response"}
	var from := String(e["from"])
	var to := String(e["to"])
	var other := String(e["against"])
	var agenda := String(e["agenda"])
	var hs := hidden_state(eid)
	var insight := float(opts.get("insight", 0.5))
	var res := {"ok": true, "response": response, "outcome": "", "text": "", "effects": {}}
	var fx: Dictionary = res["effects"]
	match response:
		"accept":
			res = _accept(e, hs, res)
		"refuse":
			var grievance := 6.0 if agenda == "arrogant" else (1.0 if agenda == "desperate" else 3.0)
			_shift_rel(to, from, "grievance", grievance)
			_shift_rel(to, from, "trust", -2.0 if agenda != "desperate" else -0.5)
			fx["grievance"] = grievance
			res["outcome"] = "refused"
			res["text"] = "The envoy of %s leaves %s." % [from, "in cold anger" if agenda == "arrogant" else "without a word of thanks"]
			if agenda == "desperate":
				res["text"] = "The envoy of %s bows and goes, and may seek another door." % from
			if agenda == "rogue":
				res["text"] = "The envoy keeps his own counsel; his masters learn nothing of it."
				res["outcome"] = "refused_unreported"
				fx["grievance"] = 0.0
				_shift_rel(to, from, "grievance", -grievance)
			e["state"] = "closed"
		"negotiate":
			var odds := 0.35 + (float(hs["bond_env"]) - float(hs["bond_other"])) / 120.0 + float(opts.get("gift", 0)) / 400.0 + (0.12 if bool(e["informed"]) else 0.0)
			if agenda == "desperate":
				odds += 0.18
			if agenda == "arrogant":
				odds -= 0.15
			if agenda == "deceptive":
				odds -= 0.05
			odds = clampf(odds, 0.05, 0.92)
			if _h("neg", eid, "n") < odds:
				res["outcome"] = "terms"
				res["text"] = "Terms are struck with the envoy of %s." % from
				fx["trust"] = 3.0
				_shift_rel(to, from, "trust", 3.0)
				res["neutrality"] = neutrality_label(eid) if String(e["ask"]) == "neutrality" else ""
				e["state"] = "closed"
			else:
				res["outcome"] = "talks_stall"
				res["text"] = "The talks stall; neither side will give ground."
				e["until"] = int(e["until"]) + 2
			res["odds"] = snappedf(odds, 0.01)
		"delay":
			e["delayed"] = int(e["delayed"]) + 1
			var offence: float = {"arrogant": 5.0, "desperate": 0.0, "sincere": 1.0, "deceptive": 1.0, "rogue": 0.0}[agenda] * float(e["delayed"])
			_shift_rel(to, from, "grievance", offence)
			e["until"] = int(e["until"]) + 4
			res["outcome"] = "delayed"
			res["text"] = "The envoy is lodged and told to wait."
			fx["grievance"] = offence
			if agenda == "desperate" and int(e["delayed"]) >= 2:
				res["outcome"] = "envoy_defects"
				res["text"] = "The envoy, out of patience and out of hope, seeks the other side."
				e["state"] = "closed"
		"ask_intel":
			var chance := clampf(insight * (0.55 if agenda == "deceptive" else 0.9) + (0.15 if agenda == "desperate" else 0.0), 0.05, 0.95)
			if _h("intel", eid, "i") < chance:
				e["informed"] = true
				res["outcome"] = "learned"
				res["agenda"] = agenda
				res["aim"] = _aim_text(e)
				res["text"] = "You learn what the envoy truly wants: %s." % res["aim"]
			else:
				res["outcome"] = "told_nothing"
				res["text"] = "The envoy answers every question smoothly and says very little."
				if agenda == "deceptive":
					res["false_aim"] = "friendship" if String(e["ask"]) != "alliance" else "trade"
		"mediate":
			if other == "":
				return {"ok": false, "reason": "nobody_to_mediate"}
			var odds2 := 0.25 + (float(_frel(to, other)["trust"]) + float(hs["trust_env"])) / 400.0 + 0.1 * insight
			if agenda in ["arrogant", "rogue"]:
				odds2 -= 0.2
			if agenda == "desperate":
				odds2 += 0.2
			odds2 = clampf(odds2, 0.05, 0.9)
			if _h("med", eid, "m") < odds2:
				_shift_rel(from, other, "grievance", -8.0)
				_shift_rel(from, other, "trust", 4.0)
				res["outcome"] = "mediated"
				res["text"] = "You broker a pause between %s and %s." % [from, other]
				fx["grievance_between"] = -8.0
			else:
				_shift_rel(to, from, "trust", -2.0)
				res["outcome"] = "mediation_failed"
				res["text"] = "Neither side will sit at your table."
			res["odds"] = snappedf(odds2, 0.01)
			e["state"] = "closed"
		"demand_compensation":
			var amt := 60 + int(10.0 * float(hs["pressure"]) * 0.1)
			match agenda:
				"sincere":
					res["outcome"] = "paid"
					_gold += amt
					fx["gold"] = amt
					res["text"] = "The envoy pays %d gold without argument." % amt
					_shift_rel(to, from, "trust", 1.0)
				"desperate":
					res["outcome"] = "cannot_pay"
					res["text"] = "The envoy has nothing to give, and says so honestly."
				"arrogant":
					res["outcome"] = "insulted"
					res["text"] = "The envoy laughs. The audience ends."
					_shift_rel(to, from, "grievance", 7.0)
					e["state"] = "closed"
				"deceptive":
					res["outcome"] = "false_promise"
					res["text"] = "The envoy promises payment 'within the month'."
					e["owed"] = amt
				_:
					res["outcome"] = "no_authority"
					res["text"] = "The envoy has no authority to promise gold."
		"secretly_aid":
			if other == "":
				return {"ok": false, "reason": "nobody_to_aid"}
			e["secret_aid"] = true
			var found_p := 0.18 + (0.3 if agenda in ["deceptive", "rogue"] else 0.0) + (0.1 if agenda == "arrogant" else 0.0)
			var found := _h("secret", eid, "s") < found_p
			_shift_rel(to, other, "trust", 6.0)
			fx["trust_other"] = 6.0
			if found:
				_shift_rel(to, from, "trust", -14.0)
				_shift_rel(to, from, "grievance", 10.0)
				res["outcome"] = "discovered"
				res["neutrality"] = "violated"
				res["text"] = "The envoy's people learn that %s sent help to %s in the night." % [to, other]
				Events.log_to(hub, "crime", "", [], "secret_aid", "Secret aid to %s was exposed" % other, 4)
			else:
				res["outcome"] = "unseen"
				res["neutrality"] = "violated_unseen"
				res["text"] = "The help goes through, for now."
			res["found_p"] = snappedf(found_p, 0.01)
			e["state"] = "closed"
		"delegate_council":
			var comp := float(opts.get("council", 0.5))
			var natural := "refuse" if float(hs["bond_other"]) > float(hs["pressure"]) else "accept"
			if _h("council", eid, "c") > comp:
				natural = "accept" if natural == "refuse" else "refuse"
			e["until"] = int(e["until"]) + 3
			var sub := respond(eid, natural, opts)
			sub["response"] = "delegate_council"
			sub["via"] = natural
			sub["delay_days"] = 3
			return sub
	if String(e["state"]) == "closed":
		e["outcome"] = String(res["outcome"])
	res["response"] = response
	Events.log_to(hub, "audience", ("ss:%d" % int(e["sid"])) if int(e["sid"]) >= 0 else "", [], "envoy_" + response, String(res["text"]), 3)
	return res


func _aim_text(e: Dictionary) -> String:
	match String(e["agenda"]):
		"arrogant":
			return "to make you kneel to %s's terms" % e["from"]
		"desperate":
			return "to save a failing cause; %s cannot stand alone" % e["from"]
		"deceptive":
			return "to keep your hands tied while %s moves against %s" % [e["from"], e["against"] if e["against"] != "" else "a rival"]
		"rogue":
			return "to win a private bargain that his masters never approved"
	return "to get what he asked, and nothing hidden"


func _accept(e: Dictionary, hs: Dictionary, res: Dictionary) -> Dictionary:
	var from := String(e["from"])
	var to := String(e["to"])
	var ask := String(e["ask"])
	var agenda := String(e["agenda"])
	var fx: Dictionary = res["effects"]
	e["state"] = "closed"
	_shift_rel(to, from, "trust", 4.0)
	fx["trust"] = 4.0
	if ask == "neutrality":
		var label := neutrality_label(int(e["id"]))
		res["neutrality"] = label
		match label:
			"respected":
				res["outcome"] = "neutral_respected"
				res["text"] = "%s is satisfied: %s will stand aside." % [from, to]
			"pressured":
				res["outcome"] = "neutral_pressured"
				res["text"] = "You declare neutrality, but %s's weight is felt in every council." % from
				_shift_rel(to, String(e["against"]), "trust", -3.0)
				fx["trust_other"] = -3.0
			"strained":
				res["outcome"] = "neutral_strained"
				res["text"] = "You declare neutrality, though your ties to %s will not stay quiet." % e["against"]
				_shift_rel(to, from, "trust", -2.0)
			_:
				res["outcome"] = "neutral_violated"
		if agenda == "deceptive":
			res["text"] += " Behind it, the envoy was buying time."
			_shift_rel(from, String(e["against"]), "grievance", 2.0)
	else:
		res["outcome"] = "accepted_" + ask
		res["text"] = "You grant the request of %s's envoy (%s)." % [from, ask]
		if ask == "aid" or ask == "passage":
			if String(e["against"]) != "":
				_shift_rel(to, String(e["against"]), "trust", -4.0)
	if agenda == "rogue":
		res["text"] += " His masters will not honour what he promised."
		res["outcome"] += "_unbacked"
	return res


## Gold due to the player from envoys (compensation). Queued, never written to the purse directly; life.gd collects it.
func take_pending_gold() -> int:
	var g := _gold
	_gold = 0
	return g


# ------------------------------------------------------------------ digest (MW-33)

## Tells the digest who it is for. role "ruler" or "adventurer"; acct is the ledger account of the realm; holdings are settlement ids whose safety is theirs.
func set_viewer(acct: String, sid: int, role: String, owner: String, holdings: Array = []) -> void:
	_viewer = {"acct": acct, "sid": sid, "role": role, "owner": owner, "holdings": holdings.duplicate()}


func inbox() -> Array:
	return _inbox.duplicate(true)


func _push_inbox(d: Dictionary) -> void:
	_inbox.append(d)
	if _inbox.size() > INBOX_CAP:
		_inbox.pop_front()


func _steward_lines() -> Array:
	var out: Array = []
	var lg: Variant = _mod("ledger")
	var acct := String(_viewer.get("acct", ""))
	if lg == null or acct == "" or String(lg.steward_of(acct)) == "":
		return out
	var s: Dictionary = lg.summary(acct)
	out.append({"ch": "letter", "kind": "steward", "text": "Your steward writes: the strongbox holds %d gold; last week came to %+d; the next looks like %+d." % [int(s["balance"]), int(s["net"]), int(s["projected_week"])]})
	var late := 0
	for l: Variant in s.get("scheduled", []):
		late += 1
	if late > 0:
		out.append({"ch": "letter", "kind": "steward", "text": "He lists %d standing payments that fall due." % late})
	return out


func _intel_lines(since_h: int, ruler: bool) -> Array:
	var out: Array = []
	var owner := String(_viewer.get("owner", ""))
	var now := _now_h()
	for pr: Array in _power:
		if String(pr[1]) == owner and String(pr[8]) != "lost" and int(pr[7]) <= now and int(pr[7]) > since_h:
			var w: String = "a rumour of something strange" if int(pr[4]) < 30 else ("a power that frightens grown men" if int(pr[4]) < 60 else "a terrifying power that empties streets")
			out.append({"ch": "messenger", "kind": "intel", "text": "A rider speaks of %s, said to walk near the town." % w if ruler else "A rider mutters of %s." % w})
	for r: Dictionary in _reports:
		if String(r["owner"]) != owner or String(r["fate"]) == "lost" or int(r["ready"]) > now or int(r["ready"]) <= since_h:
			continue
		var age := now - int(r["as_of"])
		if ruler:
			out.append({"ch": "messenger", "kind": "intel", "text": "A rider brings a scout's word (%s): about %d men under %s, seen %d hours ago." % [reliability_tag(String(r["scout"])), int(r["n"]), r["banner"], age]})
		else:
			out.append({"ch": "messenger", "kind": "intel", "text": "A rider mutters that %s men under %s were seen on the road." % [_vague(int(r["n"])), r["banner"]]})
	return out


func _rumour_lines(ruler: bool, limit: int) -> Array:
	var out: Array = []
	var nw: Variant = _mod("news")
	var sid := int(_viewer.get("sid", -1))
	if nw == null or sid < 0:
		return out
	for it: Dictionary in nw.news_for(sid, "tavern" if not ruler else "traveller", limit):
		out.append({"ch": "tavern" if not ruler else "letter", "kind": "rumour", "text": ("It is said in the inn: " if not ruler else "Travellers carry word: ") + String(it["text"])})
	return out


## Builds this week's digest (one per week at most). Ruler: steward, intel with tags and numbers, rumours; adventurer: rumours first, vague intel, fewer lines.
func digest(week: int) -> Dictionary:
	if _viewer.is_empty() or week <= _last_week:
		return {}
	var ruler := String(_viewer["role"]) == "ruler"
	var cap := DIGEST_RULER if ruler else DIGEST_ADV
	var since := (week - 1) * 7 * 24
	var items: Array = []
	if ruler:
		items.append_array(_steward_lines())
		items.append_array(_intel_lines(since, true))
		items.append_array(_rumour_lines(true, 3))
	else:
		items.append_array(_rumour_lines(false, 2))
		items.append_array(_intel_lines(since, false))
	if items.size() > cap:
		items = items.slice(0, cap)
	_last_week = week
	if items.is_empty():
		return {}
	var d := {"id": _next_d, "week": week, "day": _day_now(), "role": _viewer["role"], "items": items, "urgent": false}
	_next_d += 1
	stats["digests"] = int(stats["digests"]) + 1
	_push_inbox(d)
	return d


## A direct threat only: an enemy army the viewer's own fog-of-war map shows (not the truth) near their own settlement. One warning a day, and the
## same army not again for URGENT_GAP_DAYS.
func urgent_check(day: int) -> Dictionary:
	var ar: Variant = _mod("armies")
	if _viewer.is_empty() or ar == null or day - _urgent_last < 1:
		return {}
	var owner := String(_viewer["owner"])
	for e: Dictionary in ar.known_map(owner):
		if bool(e["own"]):
			continue
		var aid := String(e["id"])
		if day - int(_urgent_day.get(aid, -100)) < URGENT_GAP_DAYS:
			continue
		for hs: Variant in _viewer.get("holdings", []):
			var p: Array = ar._pos_of_sid(int(hs))
			var dx := float(e["pos"][0]) - float(p[0])
			var dy := float(e["pos"][1]) - float(p[1])
			if dx * dx + dy * dy <= THREAT_RADIUS * THREAT_RADIUS:
				_urgent_day[aid] = day
				_urgent_last = day
				stats["urgent"] = int(stats["urgent"]) + 1
				var d := {"id": _next_d, "week": day / 7, "day": day, "role": _viewer["role"], "urgent": true,
					"items": [{"ch": "messenger", "kind": "threat", "text": "A rider gasps that armed men (%s) were last seen near your land, %d hours ago." % [_vague(int(e["n"])) if String(_viewer["role"]) != "ruler" else "about %d" % int(e["n"]), int(e["age_h"])]}]}
				_next_d += 1
				_push_inbox(d)
				return d
	return {}


# ------------------------------------------------------------------ ticks and save

func tick_day(day: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in _envoys:
		if String(e["state"]) == "waiting" and day > int(e["until"]):
			e["state"] = "closed"
			e["outcome"] = "left_offended"
			_shift_rel(String(e["to"]), String(e["from"]), "grievance", 2.0)
	for e2: Dictionary in _envoys:
		if e2.has("owed") and not bool(e2.get("settled", false)) and day > int(e2["day"]) + 30:
			e2["settled"] = true
			_shift_rel(String(e2["to"]), String(e2["from"]), "grievance", 5.0)   # the promised gold never came
	var u := urgent_check(day)
	if not u.is_empty():
		out.append(String((u["items"] as Array)[0]["text"]))
	return out


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var d := digest(week)
	return [] if d.is_empty() else ["A letter arrives with the week's news."]


## Closed form: any number of weeks yields at most one digest (the latest), so a long sleep never floods the inbox.
func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	var day := _day_now()
	for e: Dictionary in _envoys:
		if String(e["state"]) == "waiting" and day > int(e["until"]):
			e["state"] = "closed"
			e["outcome"] = "left_offended"
	return []


func serialize() -> Dictionary:
	return {"sc": _scouts.duplicate(true), "rep": _reports.duplicate(true), "nr": _next_r, "env": _envoys.duplicate(true), "ne": _next_e, "view": _viewer.duplicate(true),
		"pw": _power.duplicate(true), "np": _next_p, "in": _inbox.duplicate(true), "nd": _next_d, "lw": _last_week, "ud": _urgent_day.duplicate(), "ul": _urgent_last, "gold": _gold, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_scouts = {}
	var sc: Dictionary = d.get("sc", {})
	for k: String in sc:
		var s: Dictionary = (sc[k] as Dictionary).duplicate(true)
		for f: String in ["skill", "integ", "fear", "loy", "bribe"]:
			s[f] = float(s[f])
		for f2: String in ["n", "right"]:
			s[f2] = int(s[f2])
		_scouts[k] = s
	_reports = []
	for r: Dictionary in d.get("rep", []):
		var rr := r.duplicate(true)
		for f3: String in ["id", "n", "as_of", "ready", "true_n"]:
			rr[f3] = int(rr[f3])
		_reports.append(rr)
	_next_r = int(d.get("nr", 1))
	_power = []
	for pr2: Array in d.get("pw", []):
		_power.append([int(pr2[0]), String(pr2[1]), String(pr2[2]), int(pr2[3]), int(pr2[4]), (pr2[5] as Array).duplicate(), int(pr2[6]), int(pr2[7]), String(pr2[8])])
	_next_p = int(d.get("np", 1))
	_envoys = []
	for e: Dictionary in d.get("env", []):
		var ee := e.duplicate(true)
		for f4: String in ["id", "day", "until", "delayed", "gift", "sid"]:
			ee[f4] = int(ee[f4])
		if ee.has("owed"):
			ee["owed"] = int(ee["owed"])
		_envoys.append(ee)
	_next_e = int(d.get("ne", 1))
	_viewer = (d.get("view", {}) as Dictionary).duplicate(true)
	if _viewer.has("sid"):
		_viewer["sid"] = int(_viewer["sid"])
		var hl: Array = []
		for x: Variant in _viewer.get("holdings", []):
			hl.append(int(x))
		_viewer["holdings"] = hl
	_inbox = []
	for i: Dictionary in d.get("in", []):
		var ii := i.duplicate(true)
		for f5: String in ["id", "week", "day"]:
			ii[f5] = int(ii[f5])
		_inbox.append(ii)
	_next_d = int(d.get("nd", 1))
	_last_week = int(d.get("lw", -1))
	_urgent_day = {}
	var ud: Dictionary = d.get("ud", {})
	for k2: String in ud:
		_urgent_day[k2] = int(ud[k2])
	_urgent_last = int(d.get("ul", -100))
	_gold = int(d.get("gold", 0))
	var st: Dictionary = d.get("stats", {})
	for k3: String in stats:
		stats[k3] = int(st.get(k3, stats[k3]))
