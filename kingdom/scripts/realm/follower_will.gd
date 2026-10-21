extends "res://scripts/realm/realm_module.gd"
## Follower will (Living World MW-12, MW-13, MW-14): what a recruit WANTS, not only what they are paid.
##
## MOTIVES. Every tracked follower carries seven drives 0..1: affection (for the lord as a person), respect, fear, ideals,
## greed, protection (of kin and the weak) and a hidden-agenda strength. They start from traits and loyalty (followers.gd)
## and drift with events (on_event) and the day tick (pay, hunger, tenure, memory). A hidden agenda (profit, power,
## enemy_agent, revenge) is rolled once per person; honourable loyal servants never get one.
## ROLES. personal, military, economic, settlement, political, social. assign_role checks skill, authority and motivation.
## ORDERS. respond(fid, order, situation) weighs the order against the motives, the opportunity (lord absent, garrison
## held, an enemy to talk to), the capability, the allies and the risk, and picks ONE of: comply, stay_behind,
## refuse_moral, consider_leaving, leak_to_enemy, organise_resistance, attempt_takeover, conceal_resentment. A little
## deterministic noise means betrayal is possible and never inevitable; a lifelong loyal follower will not betray.
## REQUESTS. Each day a few followers ask for something (assignment, leave, better conditions, partnership, a reward).
## DELEGATION. delegate_quality(fid) and settlement_modifier(sid) are the HOOKS other modules read: a governor's
## competence and honesty scale output and leakage. Nothing here touches gold; reward() returns the cost for the caller.
## PLAYER ACTIONS. investigate, audit, reward, promote, dismiss, forgive, imprison (imprison obeys courts.gd per region).

const Codec := preload("res://scripts/realm/save_codec.gd")

const MOT := ["aff", "res", "fear", "ide", "gre", "pro", "hid"]
const ROLES := ["personal", "military", "economic", "settlement", "political", "social"]
const AGENDAS := ["", "profit", "power", "enemy_agent", "revenge"]
const ACTIONS := ["comply", "stay_behind", "refuse_moral", "consider_leaving", "leak_to_enemy", "organise_resistance",
	"attempt_takeover", "conceal_resentment"]
const REQUESTS := ["", "assignment", "leave", "better_conditions", "partnership", "reward"]
const KINDS := ["paid_full", "unpaid", "praised", "rewarded", "promoted", "insulted", "punished_just", "punished_unjust",
	"ordered_atrocity", "saved_by_player", "victory", "defeat", "family_threatened", "family_helped", "lord_absent",
	"shared_loot", "betrayed_trust", "audited_clean", "accused_falsely", "imprisoned_unjust", "dismissed_ally", "forgiven"]
## event kind -> deltas [aff, res, fear, ide, gre, pro, hid, grudge]
const EVENTS := {
	"paid_full": [0.02, 0.01, 0, 0, -0.03, 0, 0, -0.01], "unpaid": [-0.04, 0, 0, 0, 0.04, 0, 0, 0.05],
	"praised": [0.04, 0.03, 0, 0, 0, 0, 0, -0.02], "rewarded": [0.05, 0.02, 0, 0, 0.02, 0, 0, -0.05],
	"promoted": [0.06, 0.05, 0, 0, 0.02, 0, 0, -0.08], "insulted": [-0.06, -0.04, 0, 0, 0, 0, 0, 0.08],
	"punished_just": [0, 0.01, 0.08, 0, 0, 0, 0, 0.02], "punished_unjust": [-0.10, -0.08, 0.08, 0, 0, 0, 0, 0.18],
	"ordered_atrocity": [-0.04, -0.06, 0.02, 0, 0, 0, 0, 0.08], "saved_by_player": [0.12, 0.08, 0, 0, 0, 0, 0, -0.10],
	"victory": [0.02, 0.04, 0, 0, 0.03, 0, 0, 0], "defeat": [-0.02, -0.04, 0.03, 0, 0, 0, 0, 0],
	"family_threatened": [-0.05, 0, 0, 0, 0, 0.10, 0, 0.10], "family_helped": [0.12, 0.02, 0, 0, 0, -0.02, 0, -0.10],
	"lord_absent": [0, -0.02, -0.01, 0, 0, 0, 0.01, 0], "shared_loot": [0.04, 0.01, 0, 0, -0.04, 0, 0, 0],
	"betrayed_trust": [-0.10, -0.10, 0, 0, 0, 0, 0, 0.15], "audited_clean": [-0.02, 0.02, 0, 0, 0, 0, 0, 0],
	"accused_falsely": [-0.12, -0.10, 0.03, 0, 0, 0, 0, 0.20], "imprisoned_unjust": [-0.20, -0.15, 0.20, 0, 0, 0, 0, 0.30],
	"dismissed_ally": [-0.04, 0, 0.03, 0, 0, 0, 0, 0.04], "forgiven": [0.10, 0.06, -0.10, 0, 0, 0, 0, -0.30],
}
## Kinds that count as an injustice done to the follower (lifelong loyalty breaks after enough of them).
const UNJUST := ["punished_unjust", "accused_falsely", "imprisoned_unjust", "betrayed_trust"]
## role -> skills that matter, and the motives that make a person want it.
const ROLE_SKILLS := {
	"personal": ["combat", "riding", "speech"], "military": ["command", "tactics", "combat"],
	"economic": ["building", "smithing", "speech", "repair"], "settlement": ["command", "speech", "building", "repair"],
	"political": ["speech", "command", "faith"], "social": ["medicine", "faith", "speech", "herbs"]}
const ROLE_DRIVES := {
	"personal": ["aff", "pro"], "military": ["res", "ide"], "economic": ["gre", "aff"],
	"settlement": ["pro", "ide"], "political": ["gre", "res"], "social": ["aff", "ide"]}
const FIT_MIN := {"skill": 0.35, "authority": 0.3, "drive": 0.3}
const RANK_MAX := 3
const MEM_MAX := 6
const CHUNK := 16
const REQ_COOLDOWN := 14
const LEAVE_GRACE := 7
const HOLD_DAYS := 3
const DAILY_REQUESTS := 3        # new requests announced per day at most

var _s: Dictionary = {}            # fid -> state (see ensure)
var _gov: Dictionary = {}          # sid -> fid (delegated governors / stewards)
var _leak: Dictionary = {}         # fid -> estimated gold skimmed since the last audit
var _day := 0
var _msgs_today := 0
var stats := {"requests": 0, "leaks": 0, "coups": 0, "refusals": 0, "departures": 0}


func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _fol() -> Variant:
	return hub.mod("followers") if hub != null else null


func _rec() -> Variant:
	return hub.mod("recruitment") if hub != null else null


func _courts() -> Variant:
	return hub.mod("courts") if hub != null else null


func _follower(fid: String) -> Dictionary:
	var fol: Variant = _fol()
	return fol.get_follower(fid) if fol != null else {}


# ------------------------------------------------------------------ state

## Creates (once) the state of `fid` from the follower record: traits, loyalty and a per-person roll for the agenda.
func ensure(fid: String) -> Dictionary:
	if _s.has(fid):
		return _s[fid]
	var f := _follower(fid)
	var tr: Array = f.get("traits", [])
	var r := _rng("will", 0, fid)
	var loy := float(f.get("loyalty", 50.0)) / 100.0
	var m := {
		"aff": clampf(loy * 0.9 + r.randf_range(-0.08, 0.08), 0.0, 1.0),
		"res": clampf(0.35 + loy * 0.35 + (0.15 if "honorable" in tr else 0.0) + r.randf_range(-0.08, 0.08), 0.0, 1.0),
		"fear": clampf(0.12 + (0.1 if "cautious" in tr else 0.0) - (0.08 if "brave" in tr else 0.0) + r.randf_range(0.0, 0.1), 0.0, 1.0),
		"ide": clampf(0.3 + (0.35 if "honorable" in tr else 0.0) + (0.2 if "devout" in tr else 0.0) + (0.15 if "merciful" in tr else 0.0)
			- (0.2 if "ruthless" in tr else 0.0) + r.randf_range(-0.06, 0.06), 0.0, 1.0),
		"gre": clampf(0.25 + (0.45 if "greedy" in tr else 0.0) + r.randf_range(-0.08, 0.08), 0.0, 1.0),
		"pro": clampf(0.3 + (0.25 if "merciful" in tr else 0.0) + (0.15 if "loyal" in tr else 0.0) + r.randf_range(-0.06, 0.1), 0.0, 1.0),
		"hid": 0.0}
	var p := 0.12 + (0.14 if "greedy" in tr else 0.0) + (0.1 if "ruthless" in tr else 0.0) - (0.12 if "honorable" in tr else 0.0) \
		- (0.1 if "loyal" in tr else 0.0)
	if "honorable" in tr and "loyal" in tr:
		p = 0.0
	var agenda := ""
	if r.randf() < p:
		agenda = ["profit", "power", "enemy_agent", "revenge"][r.randi() % 4]
		if "greedy" in tr and r.randf() < 0.5:
			agenda = "profit"
		m["hid"] = 0.35 + r.randf() * 0.3
	_s[fid] = {"m": m, "role": _default_role(fid), "agenda": agenda, "g": 0.0, "rank": 0, "life": false, "mem": [], "al": [],
		"req": "", "req_day": -99, "cool": -99, "plot": "", "plot_day": 0, "leave_day": -1, "held": -1, "wins": 0, "unjust": 0,
		"known": false, "ov": 0.0, "since": _day, "last": "", "last_day": -99}
	return _s[fid]


func state_of(fid: String) -> Dictionary:
	return (ensure(fid) as Dictionary).duplicate(true)


func motives(fid: String) -> Dictionary:
	return ((ensure(fid) as Dictionary)["m"] as Dictionary).duplicate()


## Test and tool hook: overwrite parts of a follower's state (motives merge key by key).
func set_state(fid: String, patch: Dictionary) -> void:
	var s: Dictionary = ensure(fid)
	for k: String in patch:
		if k == "m":
			for mk: String in patch["m"]:
				(s["m"] as Dictionary)[mk] = clampf(float(patch["m"][mk]), 0.0, 1.0)
		else:
			s[k] = patch[k]


func add_ally(a: String, b: String) -> void:
	var pairs: Array = [[a, b], [b, a]]
	for pair: Array in pairs:
		var al: Array = (ensure(pair[0]) as Dictionary)["al"]
		if not (pair[1] in al) and al.size() < 6:
			al.append(pair[1])


func _active_ids() -> Array:
	var rc: Variant = _rec()
	if rc != null:
		var ids: Array = rc.active_ids()
		if not ids.is_empty():
			return ids
	var out: Array = []
	var fol: Variant = _fol()
	if fol != null:
		for f: Dictionary in fol.party():
			out.append(String(f["id"]))
	for k: String in _s:
		if not (k in out):
			out.append(k)
	out.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	return out


func _default_role(fid: String) -> String:
	var rc: Variant = _rec()
	var e: Dictionary = rc.get_entry(fid) if rc != null else {}
	if e.is_empty():
		return "personal"
	var duty := String(((rc.contract_of(fid) as Dictionary).get("t", {}) as Dictionary).get("d", "labor"))
	match String(e.get("mgr", "")):
		"captain":
			return "military"
		"steward":
			return "settlement"
	match duty:
		"campaign":
			return "military"
		"guard":
			return "military" if String(e["chain"]) != "personal" else "personal"
		"steward":
			return "settlement"
		"labor":
			return "economic"
	return "personal"


# ------------------------------------------------------------------ events and memory

## Something happened to / around `fid`. mag scales the table row (1.0 normal). Remembered (ring of MEM_MAX).
func on_event(fid: String, kind: String, mag := 1.0, day := -1) -> void:
	var d: Array = EVENTS.get(kind, [])
	if d.is_empty():
		return
	var s: Dictionary = ensure(fid)
	var m: Dictionary = s["m"]
	var k := clampf(mag, 0.0, 3.0)
	if kind == "ordered_atrocity":
		k *= 0.6 + float(m["ide"])
	elif kind == "family_threatened":
		k *= 0.6 + float(m["pro"])
	for i in MOT.size():
		m[MOT[i]] = clampf(float(m[MOT[i]]) + float(d[i]) * k, 0.0, 1.0)
	s["g"] = clampf(float(s["g"]) + float(d[7]) * k, 0.0, 1.0)
	if kind == "victory":
		s["wins"] = int(s["wins"]) + 1
	if kind in UNJUST:
		s["unjust"] = int(s["unjust"]) + 1
		if int(s["unjust"]) >= 3:
			s["life"] = false
	var mem: Array = s["mem"]
	mem.append([KINDS.find(kind), day if day >= 0 else _day, int(round(k * 10.0))])
	if mem.size() > MEM_MAX:
		mem.pop_front()


## Broadcast to every active follower except `skip` (a witnessed injustice, a victory, a shared hardship).
func on_event_all(kind: String, mag := 1.0, skip := "") -> void:
	for fid: String in _active_ids():
		if fid != skip:
			on_event(fid, kind, mag)


## How the last MEM_MAX memories lean, newest weighted most. -1..1.
func memory_bias(fid: String) -> float:
	var s: Dictionary = ensure(fid)
	var tot := 0.0
	var w := 1.0
	var mem: Array = s["mem"]
	for i in range(mem.size() - 1, -1, -1):
		var e: Array = mem[i]
		var d: Array = EVENTS.get(KINDS[int(e[0])], [])
		if not d.is_empty():
			tot += (float(d[0]) + float(d[1]) - float(d[7])) * float(e[2]) * 0.1 * w
		w *= 0.7
	return clampf(tot * 4.0, -1.0, 1.0)


# ------------------------------------------------------------------ roles

func role_of(fid: String) -> String:
	return String((ensure(fid) as Dictionary)["role"])


func rank_of(fid: String) -> int:
	return int((ensure(fid) as Dictionary)["rank"])


func _skill(fid: String, role: String) -> float:
	var sk: Dictionary = _follower(fid).get("skills", {})
	var vals: Array = []
	for k: String in ROLE_SKILLS[role]:
		vals.append(float(sk.get(k, 0.0)))
	vals.sort()
	vals.reverse()
	var n := mini(2, vals.size())
	var tot := 0.0
	for i in n:
		tot += float(vals[i])
	return tot / maxf(1.0, n)


## {skill, authority, drive, ok, why}: can `fid` fill `role`? Authority is rank, respect and tenure; drive is how much they want it.
func role_fit(fid: String, role: String) -> Dictionary:
	if not ROLE_SKILLS.has(role):
		return {"skill": 0.0, "authority": 0.0, "drive": 0.0, "ok": false, "why": "unknown role"}
	var s: Dictionary = ensure(fid)
	var m: Dictionary = s["m"]
	var f := _follower(fid)
	var tenure := minf(0.3, float(maxi(0, _day - int(f.get("joined_day", _day)))) / 300.0)
	var skill := _skill(fid, role)
	var authority := clampf(float(s["rank"]) / float(RANK_MAX) * 0.4 + float(m["res"]) * 0.4 + tenure, 0.0, 1.0)
	var drives: Array = ROLE_DRIVES[role]
	var drive := (float(m[drives[0]]) + float(m[drives[1]])) * 0.5
	var why := ""
	if skill < float(FIT_MIN["skill"]):
		why = "lacks the skill"
	elif authority < float(FIT_MIN["authority"]):
		why = "lacks the standing"
	elif drive < float(FIT_MIN["drive"]):
		why = "does not want it"
	return {"skill": skill, "authority": authority, "drive": drive, "ok": why == "", "why": why}


func assign_role(fid: String, role: String) -> Dictionary:
	var fit := role_fit(fid, role)
	if bool(fit["ok"]):
		(ensure(fid) as Dictionary)["role"] = role
		fit["line"] = "Taken up as %s." % role
	else:
		fit["line"] = "They %s." % String(fit["why"])
	return fit


# ------------------------------------------------------------------ order response (MW-12)

func _capability(fid: String) -> float:
	var s: Dictionary = ensure(fid)
	return clampf(_skill(fid, "military") * 0.7 + float(s["rank"]) / float(RANK_MAX) * 0.3, 0.0, 1.0)


## The score of every response (before noise). order: {kind, moral 0..1, danger 0..1, tie 0..1}. sit: {lord_present,
## garrison, family_risk, owed_days, allies, enemy_contact, lord_strength}.
func scores(fid: String, order: Dictionary, sit: Dictionary) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var m: Dictionary = s["m"]
	var aff := float(m["aff"])
	var res := float(m["res"])
	var fear := float(m["fear"])
	var ide := float(m["ide"])
	var gre := float(m["gre"])
	var pro := float(m["pro"])
	var g := float(s["g"])
	var moral := clampf(float(order.get("moral", 0.0)), 0.0, 1.0)
	var danger := clampf(float(order.get("danger", 0.3)), 0.0, 1.0)
	var tie := clampf(float(order.get("tie", 0.0)), 0.0, 1.0)
	var fam := clampf(float(sit.get("family_risk", 0.0)), 0.0, 1.0)
	var owed := float(sit.get("owed_days", 0.0))
	var allies := float(sit.get("allies", (s["al"] as Array).size()))
	var contact := clampf(float(sit.get("enemy_contact", 0.0)), 0.0, 1.0)
	var lord_str := clampf(float(sit.get("lord_strength", 0.5)), 0.0, 1.0)
	var present: bool = bool(sit.get("lord_present", true))
	var garrison: bool = bool(sit.get("garrison", false))
	var agenda := String(s["agenda"])
	var lock := 2.0 if bool(s["life"]) else 0.0
	var bond := clampf(0.45 * aff + 0.30 * res + 0.25 * (1.0 - g), 0.0, 1.0)
	var risk := lord_str * (0.55 + 0.45 * fear) * (1.0 if present else 0.45)
	var cap := _capability(fid)
	var authority := clampf(float(s["rank"]) / float(RANK_MAX) * 0.5 + res * 0.5, 0.0, 1.0)
	var conflict := moral * ide * 1.1 + tie * pro * 0.9 + fam * pro * 0.7
	var sc := {}
	sc["comply"] = 0.55 + bond + fear * 0.35 - conflict - g * 0.5 - 0.15 * danger * (1.0 - bond)
	sc["stay_behind"] = (pro * (fam * 0.9 + tie * 0.4) + 0.15 * danger * (1.0 - res)) * (0.5 + 0.5 * bond) * (1.0 - fear * 0.5) - 0.12
	if moral < 0.3 and tie < 0.5:
		sc["refuse_moral"] = -1.0
	else:
		sc["refuse_moral"] = (moral * ide * 1.25 + tie * pro * 0.5) * (0.6 + 0.4 * res) - fear * 0.55 - 0.1
	sc["consider_leaving"] = g * 0.7 + (1.0 - aff) * 0.25 + minf(1.0, owed / 6.0) * 0.5 * (0.4 + gre) + conflict * 0.35 \
		- bond * 0.55 - fear * 0.2 - 0.1 - lock
	if contact > 0.0:
		sc["leak_to_enemy"] = (0.6 if agenda == "enemy_agent" else 0.0) + (g * 0.5 + tie * pro * 0.5) * contact - ide * 0.5 \
			- aff * 0.4 - risk * 0.4 - 0.2 - lock
	else:
		sc["leak_to_enemy"] = -1.0
	if allies < 1.0:
		sc["organise_resistance"] = -1.0
	else:
		sc["organise_resistance"] = minf(1.0, allies * 0.3) * (g * 0.6 + conflict * 0.5) * (0.5 + authority) - risk * 0.7 - 0.05 - lock
	if not garrison:
		sc["attempt_takeover"] = -1.0
	else:
		sc["attempt_takeover"] = (gre * 0.45 + (0.55 if agenda == "power" else 0.0) + g * 0.3) * (0.4 + cap * 0.6) \
			* (0.5 + minf(1.0, allies * 0.25)) * (0.35 if present else 1.0) - (aff * 0.45 + ide * 0.3 + res * 0.15) - risk * 0.5 - 0.15 - lock
	sc["conceal_resentment"] = (g * 0.6 + conflict * 0.3) * (0.3 + risk * 0.9 + fear * 0.5) - 0.1
	return sc


func _line(name: String, action: String) -> String:
	match action:
		"comply":
			return "%s salutes. \"It will be done.\"" % name
		"stay_behind":
			return "%s asks quietly to be left behind: \"There are people I cannot leave unguarded.\"" % name
		"refuse_moral":
			return "%s will not do it: \"I swore to defend, not to burn. Find another hand.\"" % name
		"consider_leaving":
			return "%s says nothing, but is weighing whether to stay in your service at all." % name
		"leak_to_enemy":
			return "%s slips away at dusk with word of your plans." % name
		"organise_resistance":
			return "%s has been talking to the others. Nobody moves." % name
		"attempt_takeover":
			return "%s holds the gate and the garrison answers to him now." % name
	return "%s complies, but the jaw is set." % name


## How `fid` answers an order. Returns {action, scores, line, outward} (outward is what the player sees: conceal_resentment
## looks like compliance). With apply, the choice changes the follower's state (grudge, plot, a pending departure).
func respond(fid: String, order: Dictionary, sit: Dictionary = {}, apply := true) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var sc := scores(fid, order, sit)
	var day := int(sit.get("day", _day))
	var r := _rng("resp", day, "%s|%s" % [fid, String(order.get("kind", ""))])
	var best := "comply"
	var bv := -1.0e9
	for a: String in ACTIONS:
		var v := float(sc[a]) + r.randf_range(-0.07, 0.07)
		if v > bv:
			bv = v
			best = a
	var name := String(_follower(fid).get("name", fid))
	var out := {"action": best, "scores": sc, "line": _line(name, best),
		"outward": "comply" if best in ["comply", "conceal_resentment"] else best}
	if apply:
		_apply_choice(s, best, day)
	return out


## What a follower is doing about the last order they were given, for the body: "stay_behind", "refuse_moral", "consider_leaving",
## "organise_resistance" make a following recruit hold position (follower_brain WILL_HOLD). Fades after HOLD_DAYS, "" when nothing.
func will_of(fid: String) -> String:
	if not _s.has(fid):
		return ""
	var s: Dictionary = _s[fid]
	if int(s["leave_day"]) >= 0:
		return "consider_leaving"
	if _day - int(s.get("last_day", -99)) <= HOLD_DAYS:
		return String(s.get("last", ""))
	return ""


## Settlements that have a delegated governor.
func governed() -> Array:
	var out: Array = _gov.keys()
	out.sort()
	return out


func _apply_choice(s: Dictionary, a: String, day: int) -> void:
	s["last"] = a
	s["last_day"] = day
	match a:
		"conceal_resentment":
			s["g"] = clampf(float(s["g"]) + 0.03, 0.0, 1.0)
		"refuse_moral", "stay_behind":
			stats["refusals"] = int(stats["refusals"]) + 1
		"consider_leaving":
			if int(s["leave_day"]) < 0:
				s["leave_day"] = day + LEAVE_GRACE
		"leak_to_enemy":
			stats["leaks"] = int(stats["leaks"]) + 1
			s["plot"] = "leak"
			s["plot_day"] = day
		"organise_resistance":
			s["plot"] = "resist"
			s["plot_day"] = day
		"attempt_takeover":
			s["plot"] = "takeover"
			s["plot_day"] = day


## Settle a takeover attempt (deterministic): {won, line}. A failed attempt exposes the plotter (grudge maxed).
func resolve_takeover(fid: String, sit: Dictionary = {}) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var r := _rng("coup", int(sit.get("day", _day)), fid)
	var power := _capability(fid) * 0.5 + minf(1.0, float(sit.get("allies", (s["al"] as Array).size())) * 0.2) * 0.35 \
		+ (0.2 if bool(sit.get("garrison", false)) else 0.0) + (0.15 if not bool(sit.get("lord_present", true)) else 0.0)
	var won := power + r.randf_range(-0.1, 0.1) > float(sit.get("lord_strength", 0.5)) * 0.9
	s["plot"] = ""
	stats["coups"] = int(stats["coups"]) + 1
	if not won:
		s["g"] = 1.0
		s["known"] = true
	return {"won": won, "line": "The garrison follows him." if won else "The attempt collapses before dawn."}


# ------------------------------------------------------------------ autonomous requests

## What `fid` would ask for today, or "". Pure (no state change).
func wanted_request(fid: String, day: int) -> String:
	var s: Dictionary = ensure(fid)
	if int(s["held"]) >= 0 or day - int(s["cool"]) < REQ_COOLDOWN or String(s["req"]) != "":
		return ""
	var m: Dictionary = s["m"]
	var f := _follower(fid)
	var needs: Dictionary = f.get("needs", {"pay": 1.0, "food": 1.0, "rest": 1.0, "purpose": 1.0})
	var tenure := day - int(f.get("joined_day", day))
	var fit_role := _best_role(fid)
	var best := _skill(fid, fit_role)
	if float(m["res"]) > 0.55 and float(m["aff"]) > 0.6 and tenure > 40 and best > 0.55 and int(s["rank"]) >= 1:
		return "partnership"
	if int(s["wins"]) >= 3 and float(m["gre"]) > 0.4:
		return "reward"
	if float(needs.get("purpose", 1.0)) < 0.4 or (fit_role != String(s["role"]) and best > 0.7 and float(m["res"]) > 0.4):
		return "assignment"
	if float(needs.get("pay", 1.0)) < 0.5 or float(needs.get("food", 1.0)) < 0.35 or float(needs.get("rest", 1.0)) < 0.25:
		return "better_conditions"
	if float(m["pro"]) > 0.65 and float(m["aff"]) < 0.8 and tenure > 20:
		return "leave"
	return ""


func pending_request(fid: String) -> String:
	return String((ensure(fid) as Dictionary)["req"])


## The player answers: "grant", "deny" or "promise" (a promise soothes now; betray_promise costs trust).
func answer(fid: String, how: String) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var req := String(s["req"])
	if req == "":
		return {"ok": false, "line": ""}
	s["req"] = ""
	s["cool"] = _day
	match how:
		"grant":
			on_event(fid, "rewarded", 0.8)
			match req:
				"assignment":
					s["role"] = _best_role(fid)
				"leave":
					s["leave_day"] = -1
				"reward":
					s["wins"] = 0
				"partnership":
					s["rank"] = mini(RANK_MAX, int(s["rank"]) + 1)
		"promise":
			on_event(fid, "praised", 0.6)
			s["promise"] = req
		_:
			on_event(fid, "insulted", 0.9 if req == "reward" else 0.5)
			if req in ["reward", "better_conditions"]:
				var m: Dictionary = s["m"]
				m["gre"] = clampf(float(m["gre"]) + 0.04, 0.0, 1.0)
	return {"ok": true, "request": req, "how": how}


func betray_promise(fid: String) -> void:
	var s: Dictionary = ensure(fid)
	if s.has("promise"):
		s.erase("promise")
		on_event(fid, "betrayed_trust", 1.0)


func _best_role(fid: String) -> String:
	var best := "personal"
	var bv := -1.0
	for role: String in ROLES:
		var v := _skill(fid, role)
		if v > bv:
			bv = v
			best = role
	return best


# ------------------------------------------------------------------ delegation (MW-13)

func appoint_governor(sid: int, fid: String, role := "settlement") -> Dictionary:
	var fit := assign_role(fid, role)
	if bool(fit["ok"]):
		_gov[sid] = fid
	return fit


func remove_governor(sid: int) -> bool:
	return _gov.erase(sid)


func governor_of(sid: int) -> String:
	return String(_gov.get(sid, ""))


## HOOK: {competence, honesty, drive, output (multiplier 0.5..1.5), leak (share of spending skimmed 0..0.5), loyal}.
## Competence is skill plus tenure, dulled by a low drive; honesty falls with greed, a hidden profit agenda and a grudge.
func delegate_quality(fid: String) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var m: Dictionary = s["m"]
	var f := _follower(fid)
	var role := String(s["role"])
	var drives: Array = ROLE_DRIVES[role]
	var drive := (float(m[drives[0]]) + float(m[drives[1]])) * 0.5
	var tenure := minf(0.2, float(maxi(0, _day - int(f.get("joined_day", _day)))) / 300.0)
	var comp := clampf((_skill(fid, role) + tenure) * (0.65 + 0.35 * drive), 0.0, 1.0)
	var tr: Array = f.get("traits", [])
	var hon := 0.55 + (0.3 if "honorable" in tr else 0.0) + (0.15 if "loyal" in tr else 0.0) - (0.4 if "greedy" in tr else 0.0) \
		- (0.15 if "ruthless" in tr else 0.0)
	hon += float(m["ide"]) * 0.2 + float(m["aff"]) * 0.1 - float(m["gre"]) * 0.3 - float(s["g"]) * 0.15
	if String(s["agenda"]) == "profit":
		hon -= 0.25
	hon = clampf(hon, 0.0, 1.0)
	return {"competence": comp, "honesty": hon, "drive": drive, "output": 0.5 + comp,
		"leak": clampf(0.5 - hon, 0.0, 0.5) * (1.0 - float(s["ov"])), "loyal": bool(s["life"])}


## HOOK for settlement code: the governor's effect on `sid`. Neutral {output 1, leak 0, unrest 0} without one.
## Other modules multiply taxes/output by `output`, treat `leak` as the share lost, and add `unrest`.
func settlement_modifier(sid: int) -> Dictionary:
	var fid := String(_gov.get(sid, ""))
	if fid == "" or not _s.has(fid):
		return {"output": 1.0, "leak": 0.0, "unrest": 0.0, "governor": ""}
	var q := delegate_quality(fid)
	var s: Dictionary = _s[fid]
	return {"output": float(q["output"]), "leak": float(q["leak"]),
		"unrest": clampf((1.0 - float(q["honesty"])) * 0.15 + float(s["g"]) * 0.1, 0.0, 0.3), "governor": fid}


## Estimated gold skimmed under `fid` since the last audit (information only; the ledger is not touched here).
func skimmed(fid: String) -> float:
	return snappedf(float(_leak.get(fid, 0.0)), 0.01)


# ------------------------------------------------------------------ player actions (MW-14)

## Look into a follower's affairs. `skill` 0..1 is the investigator's skill. Reveals agenda, plot and resentment when it
## beats their concealment; an innocent subject resents being suspected.
func investigate(fid: String, skill := 0.5, day := -1) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var d := day if day >= 0 else _day
	var r := _rng("inv", d, fid)
	var conceal := 0.25 + float(s["m"]["hid"]) * 0.5 + _skill(fid, "personal") * 0.1
	var found := skill + r.randf_range(-0.15, 0.15) > conceal
	var out := {"found": found, "agenda": "", "plot": "", "grudge": 0.0}
	if found:
		s["known"] = true
		out["agenda"] = String(s["agenda"])
		out["plot"] = String(s["plot"])
		out["grudge"] = snappedf(float(s["g"]), 0.01)
	if String(s["agenda"]) == "" and String(s["plot"]) == "":
		on_event(fid, "accused_falsely", 0.25)
	else:
		on_event(fid, "punished_just", 0.4)
	return out


## Check the books of a delegate. Reveals what was skimmed, and raises oversight for a while.
func audit(fid: String, _from_ledger := false) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var found := float(_leak.get(fid, 0.0))
	_leak[fid] = 0.0
	# One audit, one result: gold a follower steward really skimmed on a ledger account is found (and taken back) by the same call.
	var lg: Variant = hub.mod("ledger") if hub != null else null
	var led: Array = []
	if lg != null and not _from_ledger:
		for acct: String in lg.accounts_of("fo:" + fid):
			var lr: Dictionary = lg.audit(acct, "player", true)
			led.append(lr)
			found += float(lr["found"])
	s["ov"] = 0.7
	var q := delegate_quality(fid)
	var res := {"found": found, "honesty": q["honesty"], "competence": q["competence"]}
	if not led.is_empty():
		res["ledger"] = led
	if found >= 1.0:
		on_event(fid, "punished_just", 1.0)
		s["known"] = true
		res["line"] = "The books are short by %d gold." % int(found)
	else:
		on_event(fid, "audited_clean", 1.0)
		res["line"] = "The books balance."
	var rc: Variant = _rec()
	if rc != null and not (rc.get_entry(fid) as Dictionary).is_empty():
		var gid := String((rc.get_entry(fid) as Dictionary).get("g", ""))
		if gid != "":
			res["group"] = rc.audit(gid)
	return res


## Reward a follower. The CALLER takes `gold` from the purse (returned as cost); the effect scales with the gift.
func reward(fid: String, gold: int) -> Dictionary:
	var mag := clampf(float(gold) / maxf(10.0, float(_follower(fid).get("salary", 3)) * 10.0), 0.1, 2.0)
	on_event(fid, "rewarded", mag)
	return {"cost": maxi(0, gold), "mag": mag}


func promote(fid: String, role := "") -> Dictionary:
	var s: Dictionary = ensure(fid)
	var target := role if role != "" else String(s["role"])
	var fit := role_fit(fid, target)
	if not bool(fit["ok"]) or int(s["rank"]) >= RANK_MAX:
		return {"ok": false, "line": "Not ready: %s." % (String(fit["why"]) if not bool(fit["ok"]) else "already at the top")}
	s["role"] = target
	s["rank"] = int(s["rank"]) + 1
	on_event(fid, "promoted", 1.0)
	return {"ok": true, "rank": s["rank"], "line": "Promoted."}


## Dismiss through recruitment.gd; friends notice, and a hostile one with a hidden agenda becomes an ex-agent.
func dismiss(fid: String, gold := 0) -> Dictionary:
	var rc: Variant = _rec()
	var res: Dictionary = rc.dismiss(fid, gold) if rc != null else {"ok": true, "paid": 0, "line": ""}
	if not bool(res.get("ok", false)):
		return res
	var s: Dictionary = ensure(fid)
	for ally: String in s["al"]:
		on_event(ally, "dismissed_ally", 1.0)
	for sid: Variant in _gov.keys():
		if _gov[sid] == fid:
			_gov.erase(sid)
	if float(s["g"]) > 0.6 and String(s["agenda"]) != "":
		s["plot"] = "ex_hostile"
	return res


## Forgive: the grudge falls and respect returns. A pardoned betrayer can become the most loyal of all.
func forgive(fid: String) -> Dictionary:
	var s: Dictionary = ensure(fid)
	on_event(fid, "forgiven", 1.0 + float(s["g"]))
	if String(s["plot"]) in ["leak", "resist", "takeover", "ex_hostile"]:
		s["plot"] = ""
	s["leave_day"] = -1
	s["unjust"] = maxi(0, int(s["unjust"]) - 1)
	return {"ok": true, "grudge": float(s["g"]), "line": "The matter is closed."}


## Imprison a follower. Lawful when the realm's court convicts them of `crime` (courts.gd: file, investigate, try; the
## sentence follows that kingdom's law), or, with no crime, only where the profile is harsh enough to allow detention
## without trial (harsh >= 0.7). Otherwise refused. Unlawful detention is an injustice every ally notices.
func imprison(fid: String, kingdom: String, crime := "", sid := 0, evidence := 0.0, day := -1) -> Dictionary:
	var s: Dictionary = ensure(fid)
	var d := day if day >= 0 else _day
	var cs: Variant = _courts()
	if cs == null:
		return {"ok": false, "lawful": false, "line": "There is no court to hold them."}
	if crime != "":
		var acc := {"id": "f:" + fid, "name": fid}
		var opts := {"evidence": [{"type": "witness_statement", "s": clampf(evidence, 0.0, 1.0), "day": d}], "culprit": "f:" + fid,
			"confessed": evidence >= 0.9}
		var cid: String = cs.file_case(crime, sid, {"id": "player", "name": "the lord"}, acc, opts)
		if cid == "":
			return {"ok": false, "lawful": false, "line": "The case cannot be opened."}
		for i in 40:
			if String(cs.case_of(cid)["state"]) in ["charged", "cold"]:
				break
			cs.investigate(cid)
		var c: Dictionary = cs.trial(cid)
		if c.is_empty():
			return {"ok": false, "lawful": true, "case": cid, "line": "The case goes cold; nothing can be proven."}
		var until: int = cs.jailed_until("f:" + fid)
		if String(c["verdict"]) == "guilty" and until >= 0:
			s["held"] = until
			on_event(fid, "punished_just", 1.0)
			return {"ok": true, "lawful": true, "case": cid, "until": until, "line": "Convicted and jailed."}
		return {"ok": false, "lawful": true, "case": cid, "verdict": c["verdict"], "line": "The court did not jail them (%s)." % c["verdict"]}
	var prof: Dictionary = cs.profile(kingdom)
	if float(prof["harsh"]) < 0.7:
		return {"ok": false, "lawful": false, "line": "The law of %s does not allow holding a man without a charge." % kingdom}
	s["held"] = d + 7
	on_event(fid, "imprisoned_unjust", 1.0)
	for ally: String in s["al"]:
		on_event(ally, "dismissed_ally", 1.5)
	return {"ok": true, "lawful": false, "until": d + 7, "line": "Held without trial. They will remember it."}


func is_held(fid: String) -> bool:
	return int((ensure(fid) as Dictionary)["held"]) >= 0


# ------------------------------------------------------------------ the day, in chunks

func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	var ids := _active_ids()
	var out: Array = []
	_day = day
	_msgs_today = 0
	var i := 0
	while i < ids.size():
		var part: Array = ids.slice(i, i + CHUNK)
		out.append(func() -> Array: return _chunk(day, part))
		i += CHUNK
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _chunk(day: int, ids: Array) -> Array:
	var msgs: Array = []
	for fid: String in ids:
		var f := _follower(fid)
		if f.is_empty() or f["status"] not in ["present", "traveling"]:
			continue
		msgs.append_array(_drift(fid, f, day, 1.0))
	return msgs


## One follower's day: drives pull toward their baselines, grudges fade, the lifelong flag is re-judged, a request or a
## departure may come, delegated posts leak. `days` scales the drift (catch_up uses it).
func _drift(fid: String, f: Dictionary, day: int, days: float) -> Array:
	var msgs: Array = []
	var s: Dictionary = ensure(fid)
	var m: Dictionary = s["m"]
	var needs: Dictionary = f["needs"]
	var k := 1.0 - pow(0.95, days)
	var tr: Array = f["traits"]
	m["aff"] = clampf(float(m["aff"]) + (float(f["loyalty"]) / 100.0 * 0.9 - float(m["aff"])) * k, 0.0, 1.0)
	m["fear"] = float(m["fear"]) * pow(0.97, days)
	m["gre"] = clampf(float(m["gre"]) + ((0.7 if "greedy" in tr else 0.25) + (1.0 - float(needs["pay"])) * 0.3 - float(m["gre"])) * k * 0.4, 0.0, 1.0)
	m["res"] = clampf(float(m["res"]) + 0.002 * days * (1.0 if float(s["g"]) < 0.4 else -0.5), 0.0, 1.0)
	m["hid"] = clampf(float(m["hid"]) + (0.002 if String(s["agenda"]) != "" else -0.01) * days, 0.0, 1.0)
	var unpaid := float(needs["pay"]) < 0.4
	s["g"] = clampf(float(s["g"]) + (0.004 if unpaid else -0.012) * days, 0.0, 1.0)
	var tenure := day - int(f.get("joined_day", day))
	if not bool(s["life"]):
		s["life"] = ("loyal" in tr or "honorable" in tr) and tenure >= 60 and float(m["aff"]) >= 0.75 and float(m["res"]) >= 0.65 \
			and int(s["unjust"]) < 2 and String(s["agenda"]) == ""
	elif int(s["unjust"]) >= 3 or float(m["aff"]) < 0.4:
		s["life"] = false
	if int(s["held"]) >= 0 and day >= int(s["held"]):
		s["held"] = -1
	if String(s["plot"]) == "leak" and day - int(s["plot_day"]) > 10:
		s["plot"] = ""
	# a departure that nobody talked out of
	if int(s["leave_day"]) >= 0 and day >= int(s["leave_day"]):
		if float(s["g"]) > 0.35 or float(m["aff"]) < 0.3:
			f["status"] = "left"
			stats["departures"] = int(stats["departures"]) + 1
			msgs.append("%s has left your service." % f["name"])
			return msgs
		s["leave_day"] = -1
	# a delegate's skim accrues as an estimate for audit(); never touches gold
	for sid: Variant in _gov:
		if _gov[sid] == fid:
			var q := delegate_quality(fid)
			_leak[fid] = float(_leak.get(fid, 0.0)) + float(q["leak"]) * 10.0 * days
			s["ov"] = float(s["ov"]) * pow(0.95, days)
	# requests
	if _msgs_today < DAILY_REQUESTS and String(s["req"]) == "":
		var want := wanted_request(fid, day)
		if want != "":
			s["req"] = want
			s["req_day"] = day
			_msgs_today += 1
			stats["requests"] = int(stats["requests"]) + 1
			msgs.append("%s asks for %s." % [f["name"], want.replace("_", " ")])
	return msgs


func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	_day += days
	for fid: String in _active_ids():
		var f := _follower(fid)
		if f.is_empty() or f["status"] not in ["present", "traveling"]:
			continue
		_drift(fid, f, _day, float(mini(days, 60)))
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var rows := {}
	for fid: String in _s:
		var s: Dictionary = _s[fid]
		var m: Dictionary = s["m"]
		var mm: Array = []
		for k: String in MOT:
			mm.append(int(round(float(m[k]) * 100.0)))
		rows[fid] = [mm, ROLES.find(s["role"]), AGENDAS.find(s["agenda"]), Codec.num(float(s["g"]) * 100.0, 1.0), int(s["rank"]),
			1 if s["life"] else 0, (s["mem"] as Array).duplicate(true), (s["al"] as Array).duplicate(), REQUESTS.find(s["req"]),
			int(s["cool"]), String(s["plot"]), int(s["plot_day"]), int(s["leave_day"]), int(s["held"]), int(s["wins"]), int(s["unjust"]),
			1 if s["known"] else 0, Codec.num(float(s["ov"]), 0.01), int(s["since"]), String(s.get("promise", "")), String(s.get("last", "")), int(s.get("last_day", -99))]
	var lk := {}
	for fid: String in _leak:
		if float(_leak[fid]) > 0.0:
			lk[fid] = Codec.num(float(_leak[fid]), 0.01)
	return {"s": rows, "gov": _gov.duplicate(), "leak": lk, "day": _day, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_s.clear()
	var rows: Dictionary = d.get("s", {})
	for fid: String in rows:
		var a: Array = rows[fid]
		var m := {}
		for i in MOT.size():
			m[MOT[i]] = float(a[0][i]) / 100.0
		var st := {"m": m, "role": ROLES[clampi(int(a[1]), 0, ROLES.size() - 1)], "agenda": AGENDAS[clampi(int(a[2]), 0, AGENDAS.size() - 1)],
			"g": float(a[3]) / 100.0, "rank": int(a[4]), "life": int(a[5]) == 1, "mem": (a[6] as Array).duplicate(true), "al": (a[7] as Array).duplicate(),
			"req": REQUESTS[clampi(int(a[8]), 0, REQUESTS.size() - 1)], "req_day": -99, "cool": int(a[9]), "plot": String(a[10]), "plot_day": int(a[11]),
			"leave_day": int(a[12]), "held": int(a[13]), "wins": int(a[14]), "unjust": int(a[15]), "known": int(a[16]) == 1, "ov": float(a[17]), "since": int(a[18])}
		if String(a[19]) != "":
			st["promise"] = String(a[19])
		st["last"] = String(a[20]) if a.size() > 21 else ""
		st["last_day"] = int(a[21]) if a.size() > 21 else -99
		for e: Array in st["mem"]:
			e[0] = int(e[0])
			e[1] = int(e[1])
			e[2] = int(e[2])
		_s[fid] = st
	_gov.clear()
	var gv: Dictionary = d.get("gov", {})
	for sid: Variant in gv:
		_gov[int(sid)] = String(gv[sid])
	_leak = (d.get("leak", {}) as Dictionary).duplicate()
	_day = int(d.get("day", 0))
	var st2: Dictionary = d.get("st", {})
	for k: String in st2:
		stats[k] = int(st2[k])
