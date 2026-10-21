extends "res://scripts/realm/realm_module.gd"
## Army entity, command, logistics and settlement defence (Living World section 9, LW-7.1 to 7.3).
## docs/design/LIVING_WORLD_SANDBOX.md Part C ("ar:n": links an organisation, a commander, stacks of men and a few named officers).
##
## FORCE TYPES carry a legal status (lawful, licensed, tolerated, illegal) and a size limit per owner rank (stewardship.gd levy limits, audiences.gd
## licences, diplomacy.gd recognition). Going over the limit raises suspicion, which feeds diplomacy.gd (visibility and conduct) and territory.gd.
## UNITS are stacks (kind, men, training level, equipment, morale, discipline, specialisation). Real recruits join through recruitment.gd contracts
## (enlist), the rest are mustered for gold. Training takes days and money; specialisation takes days.
## OFFICERS have competence and a personality, standing orders, and sub-commanders who own units. A unit obeys an order by morale, discipline,
## the officer over it and communications; one that does not follows its standing orders or deserts.
## COMMAND is data only: orders travel by courier (distance / COURIER_SPEED), may be lost, and the sender learns the outcome only when the reply
## would have come back. Scouting gives last-known positions; known_map() marks them confirmed or stale and lets stale ones fade.
## LOGISTICS: rations and wages every day, wagons and supply trains, unpaid men lose morale and then desert. Levies drawn from a village cut the
## harvest through farming.gd.
## SETTLEMENT DEFENCE: patrols, watch rotations, garrison, muster point, stockpile, evacuation, fallback. Attackers (bandits, armies) evaluate a
## settlement, then pick assault, blockade, bribing an insider, a raid on the outskirts, or another target. NPCs use the same calls.
## Positions are [x, y] arrays (no Vector2 in saved state). Everything runs on hub ticks; day work is chunked.

const D := preload("res://scripts/realm/armies_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const COURIERS_MAX := 40
const ORDERS_KEEP := 60
const SIGHT_KEEP := 48
const TRAINS_MAX := 24
const NPC_RAID_CHANCE := 0.3

var _ar: Dictionary = {}          # "ar:n" -> army
var _next_u := 1
var _couriers: Array = []         # {c, aid, order, sent, eta, ack, seq, lost}
var _orders: Array = []           # order log, see order_view()
var _trains: Array = []           # supply trains in transit
var _sight: Dictionary = {}       # viewer owner -> {target pid -> intel}
var _hostile: Dictionary = {}     # "a|b" -> true
var _def: Dictionary = {}         # sid -> defence plan
var _blk: Dictionary = {}         # sid -> blockade
var _levied: Dictionary = {}      # sid -> {n, until, aid}
var _susp: Dictionary = {}        # owner -> suspicion 0..1
var _ssid: Dictionary = {}        # owner -> settlements whose ground was told about it
var _recog: Dictionary = {}       # owner -> true when a kingdom recognised them
var _hq: Dictionary = {}          # owner -> [x, y]
var _camp: Dictionary = {}        # campaign army id -> "ar:n"
var _seq := 1
var _next_c := 1
var _own_n := 0
var _day := 0
var _hours := 0
var _npc_seeded := false
var _perf := {}
var _stance_cache: Dictionary = {}   # "a|b" -> hostile by faction stance; cleared every day (derived, never saved)
var stats := {"founded": 0, "deserted": 0, "orders": 0, "lost_orders": 0, "raids": 0, "repelled": 0, "fallen": 0, "betrayals": 0, "blockades": 0}


# ------------------------------------------------------------------ helpers

func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _now() -> int:
	return _day


## Tests and tools: the army clock.
func set_day(d: int) -> void:
	_day = d
	_hours = maxi(_hours, d * 24)


static func _h(tag: String, a: int, b: int = 0) -> float:
	return float(absi(hash([WorldSim.SEED, "ar_" + tag, a, b])) % 10000) / 10000.0


func _num(pid: String) -> int:
	return int(pid.get_slice(":", 1))


func _mint() -> String:
	var reg: Variant = _mod("registry")
	if reg != null:
		return reg.mint("ar")
	_own_n += 1
	return "ar:%d" % _own_n


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 3) -> void:
	Events.log_to(hub, kind, ("ss:%d" % sid) if sid >= 0 else "", actors, cause, outcome, w)


static func _pos_of_sid(sid: int) -> Array:
	if sid >= 0 and sid < WorldGen.settlements.size():
		var p: Vector2 = WorldGen.settlements[sid]["pos"]
		return [p.x, p.y]
	return [0.0, 0.0]


static func _dist(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2.0) + pow(float(a[1]) - float(b[1]), 2.0))


func army(aid: String) -> Dictionary:
	return _ar.get(aid, {})


## Keys of a dictionary of "ar:n" ids in number order, so ties never depend on dictionary order (which changes across a save).
func _sorted_ids(d: Dictionary) -> Array:
	var out := d.keys()
	out.sort_custom(func(a: String, b: String) -> bool: return _num(a) < _num(b))
	return out


func ids(owner := "") -> Array:
	var out: Array = []
	for k: String in _ar:
		if owner == "" or String((_ar[k] as Dictionary)["owner"]) == owner:
			out.append(k)
	out.sort_custom(func(a: String, b: String) -> bool: return _num(a) < _num(b))
	return out


func count() -> int:
	return _ar.size()


func men(aid: String) -> int:
	var n := 0
	for u: Dictionary in (_ar.get(aid, {}) as Dictionary).get("units", []):
		n += int(u["n"])
	return n


func men_of(owner: String, kind := "") -> int:
	var n := 0
	for k: String in _ar:
		var a: Dictionary = _ar[k]
		if String(a["owner"]) == owner and (kind == "" or String(a["kind"]) == kind):
			n += men(k)
	return n


# ------------------------------------------------------------------ legal status and size limits

func owner_rank(owner: String) -> int:
	var st: Variant = _mod("stewardship")
	return clampi(int(st.rank_of(owner)), 0, 4) if st != null else 0


func recognised(owner: String) -> bool:
	if bool(_recog.get(owner, false)):
		return true
	var dp: Variant = _mod("diplomacy")
	var f: Variant = _mod("factions")
	if dp != null and f != null:
		for k: Variant in f.factions():
			if String((k as Dictionary).get("kind", "")) == "nation" and dp.reaction(String(k["id"]), owner) == "recognize":
				return true
	return false


func recognise(owner: String, by := "") -> void:
	_recog[owner] = true
	_ev("military", -1, [owner], "recognised", "%s recognised by %s" % [owner, by if by != "" else "a kingdom"], 3)


func licensed(owner: String) -> bool:
	if owner_rank(owner) >= 1:
		return true
	var au: Variant = _mod("audiences")
	return au != null and (au.has_right(owner, "military_aid", -1) or au.has_right(owner, "org_recognition", -1))


## lawful, licensed, tolerated or illegal for this owner (a licensed kind without a licence is only tolerated; an illegal one that is recognised is licensed).
func legal_status(owner: String, kind: String) -> String:
	var f: Dictionary = D.FORCES.get(kind, {})
	if f.is_empty():
		return "illegal"
	var st := String(f["legal"])
	if st == "licensed" and not licensed(owner):
		return "tolerated"
	if st == "illegal" and recognised(owner):
		return "licensed"
	return st


## Most men this owner may keep under arms of this kind.
func legal_limit(owner: String, kind: String) -> int:
	var f: Dictionary = D.FORCES.get(kind, {})
	if f.is_empty():
		return 0
	var rank := owner_rank(owner)
	var st := legal_status(owner, kind)
	if kind == "levy":
		var s: Variant = _mod("stewardship")
		return int(s.limit(clampi(rank, 0, 3), "levy") * D.LEVY_PER_POINT) if s != null else 20
	if String(f["legal"]) == "illegal":
		return D.RECOGNISED_LIMIT if st == "licensed" else 0
	var lim := float(f["lim"]) * (1.0 + float(f["scale"]) * float(rank))
	if st == "tolerated" and String(f["legal"]) == "licensed":
		lim *= 0.25
	var au: Variant = _mod("audiences")
	if au != null and au.has_right(owner, "military_aid", -1):
		lim *= 1.5
	return int(lim)


func compliance(owner: String) -> Dictionary:
	var out := {}
	for k: String in D.FORCES:
		var n := men_of(owner, k)
		if n > 0:
			var lim := legal_limit(owner, k)
			out[k] = {"men": n, "limit": lim, "over": maxi(0, n - lim), "status": legal_status(owner, k)}
	return out


func pressure(owner: String) -> float:
	var p := 0.0
	for k: String in compliance(owner):
		var c: Dictionary = compliance_row(owner, k)
		if int(c["over"]) > 0:
			p += float(c["over"]) / float(maxi(int(c["limit"]), 20)) * D.SUSPICION_OVER
		if String(D.FORCES[k]["legal"]) == "illegal" and String(c["status"]) == "illegal":
			p += float(c["men"]) * D.SUSPICION_ILLEGAL
	return clampf(p, 0.0, 1.0)


func compliance_row(owner: String, kind: String) -> Dictionary:
	var n := men_of(owner, kind)
	var lim := legal_limit(owner, kind)
	return {"men": n, "limit": lim, "over": maxi(0, n - lim), "status": legal_status(owner, kind)}


func suspicion(owner: String) -> float:
	return float(_susp.get(owner, 0.0))


## Recomputes suspicion for an owner and passes it on to diplomacy (visibility, conduct) and territory (the home ground).
func _review(owner: String) -> void:
	var p := pressure(owner)
	var old := suspicion(owner)
	if p > old:
		_susp[owner] = p
		if old < 0.2 and p >= 0.2:
			_ev("military", -1, [owner], "over_limit", "%s keeps more armed men than the law allows" % owner, 4)
	_push_suspicion(owner)


func _push_suspicion(owner: String) -> void:
	var s := suspicion(owner)
	var dp: Variant = _mod("diplomacy")
	if dp != null and dp.has_method("note_force_suspicion"):
		dp.note_force_suspicion(owner, s)
	var tr: Variant = _mod("territory")
	if tr != null and tr.has_method("note_suspicion"):
		var sids: Array = _ssid.get(owner, [])
		for k: String in _ar:
			var a: Dictionary = _ar[k]
			if String(a["owner"]) == owner and int(a["sid"]) >= 0 and not sids.has(int(a["sid"])):
				sids.append(int(a["sid"]))
		for sid: int in sids:
			tr.note_suspicion(sid, s)
		if s <= 0.0:
			_ssid.erase(owner)
		else:
			_ssid[owner] = sids


# ------------------------------------------------------------------ founding, units, officers

func found(owner: String, kind: String, nm := "", sid := -1, opts: Dictionary = {}) -> Dictionary:
	if not D.FORCES.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	if _ar.size() >= D.CAMP_ARMY_MAX:
		return {"ok": false, "reason": "too_many_armies"}
	var pid := _mint()
	var f: Dictionary = D.FORCES[kind]
	var pos: Array = opts.get("pos", _pos_of_sid(sid))
	_ar[pid] = {"id": pid, "name": nm if nm != "" else "%s of %s" % [String(f["label"]).capitalize(), owner], "owner": owner, "kind": kind,
		"org": String(opts.get("org", "")), "sid": sid, "pos": [float(pos[0]), float(pos[1])], "dest": [], "cmd": "", "offs": {}, "units": [],
		"purse": int(opts.get("purse", 0)), "food": float(opts.get("food", 0.0)), "wagons": int(opts.get("wagons", 0)), "unpaid": 0, "hungry": 0,
		"state": "camped", "order": {"kind": "hold"}, "order_day": _now(), "standing": {}, "mode": String(opts.get("mode", "manual")), "camp": -1,
		"npc": bool(opts.get("npc", false)), "day": _now(), "ledger": {"wages": 0, "food": 0, "train": 0, "days": 0}, "contracted": 0, "deserted": 0}
	stats["founded"] = int(stats["founded"]) + 1
	_ev("military", sid, [pid], "raised", "%s raised (%s, %s)" % [_ar[pid]["name"], String(f["label"]), legal_status(owner, kind)], 3)
	_review(owner)
	return {"ok": true, "id": pid, "status": legal_status(owner, kind)}


func disband(aid: String, why := "disbanded") -> bool:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty():
		return false
	var owner := String(a["owner"])
	if int(a["camp"]) >= 0:
		_camp.erase(int(a["camp"]))
	_ar.erase(aid)
	for sid: int in _levied.keys():
		if String((_levied[sid] as Dictionary)["aid"]) == aid:
			_levied.erase(sid)
			_push_levy(sid)
	for sid2: int in _def:
		if String((_def[sid2] as Dictionary)["garrison"]) == aid:
			(_def[sid2] as Dictionary)["garrison"] = ""
	_ev("military", int(a["sid"]), [aid], "disbanded", "%s %s" % [a["name"], why], 2)
	_review(owner)
	return true


func add_unit(aid: String, ukind: String, n: int, opts: Dictionary = {}) -> int:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty() or not D.UNITS.has(ukind) or n <= 0:
		return -1
	var f: Dictionary = D.FORCES[String(a["kind"])]
	var cost := int(float(n) * float(opts.get("gold", 0.0)))
	if cost > int(a["purse"]):
		return -1
	a["purse"] = int(a["purse"]) - cost
	var u := {"u": _next_u, "k": ukind, "n": n, "lvl": clampi(int(opts.get("lvl", 0)), 0, D.MAX_LEVEL), "eq": clampf(float(opts.get("eq", 0.5)), 0.0, 1.0),
		"mo": float(opts.get("mo", f["mo"])), "di": float(opts.get("di", f["di"])), "spec": "", "tr_left": 0, "tr_to": 0, "sp_left": 0, "sp_to": "",
		"off": "", "cts": [], "real": 0, "mode": "obey"}
	_next_u += 1
	(a["units"] as Array).append(u)
	_review(String(a["owner"]))
	return int(u["u"])


func unit(aid: String, uid: int) -> Dictionary:
	for u: Dictionary in (_ar.get(aid, {}) as Dictionary).get("units", []):
		if int(u["u"]) == uid:
			return u
	return {}


func muster(aid: String, ukind: String, n: int, gold_each := 3.0, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	o["gold"] = gold_each
	var uid := add_unit(aid, ukind, n, o)
	return {"ok": uid >= 0, "uid": uid, "reason": "" if uid >= 0 else "cannot_pay_or_invalid"}


## A real recruit joins through a recruitment.gd contract (chain "org", org = the army id). The man is added to a unit of that kind.
func enlist(aid: String, ukind: String, row: int, terms: Dictionary = {}) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	var rc: Variant = _mod("recruitment")
	if a.is_empty() or rc == null or not D.UNITS.has(ukind):
		return {"ok": false, "line": "No such army."}
	var t := {"w": int(terms.get("w", 4)), "d": String(terms.get("d", "guard")), "n": int(terms.get("n", 0)), "h": int(terms.get("h", 0)), "x": float(terms.get("x", 0.3))}
	var r: Dictionary = rc.engage(row, t, "org", aid, terms.get("env", {}))
	if not bool(r.get("ok", false)):
		return r
	var u: Dictionary = {}
	for x: Dictionary in a["units"]:
		if String(x["k"]) == ukind and int(x["tr_left"]) == 0 and int(x["n"]) < 40:
			u = x
			break
	if u.is_empty():
		var uid := add_unit(aid, ukind, 1)
		u = unit(aid, uid)
	else:
		u["n"] = int(u["n"]) + 1
	u["real"] = int(u["real"]) + 1
	if (u["cts"] as Array).size() < 8:
		(u["cts"] as Array).append(String(r["cid"]))
	a["contracted"] = int(a["contracted"]) + 1
	var reg: Variant = _mod("registry")
	if reg != null:
		reg.upgrade_row(row)
	_review(String(a["owner"]))
	return r


func _contract_men(a: Dictionary) -> int:
	return int(a["contracted"])


## Training: costs gold now, takes days (fewer with a competent officer). The unit does not fight while it drills.
func train(aid: String, uid: int, level: int) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	var u := unit(aid, uid)
	if u.is_empty():
		return {"ok": false, "reason": "no_unit"}
	level = clampi(level, 0, D.MAX_LEVEL)
	if level <= int(u["lvl"]) or int(u["tr_left"]) > 0:
		return {"ok": false, "reason": "no_gain_or_busy"}
	var ud: Dictionary = D.UNITS[String(u["k"])]
	var steps := level - int(u["lvl"])
	var cost := int(ceil(float(int(u["n"]) * steps) * float(ud["cost"])))
	if cost > int(a["purse"]):
		return {"ok": false, "reason": "cannot_pay", "cost": cost}
	var days := maxi(int(ud["train"]) * steps, int(ceil(float(ud["train"]) * float(steps) * float(u["n"]) / 10.0 / (0.6 + comp_of(aid, u)))))
	a["purse"] = int(a["purse"]) - cost
	(a["ledger"] as Dictionary)["train"] = int((a["ledger"] as Dictionary)["train"]) + cost
	u["tr_left"] = days
	u["tr_to"] = level
	return {"ok": true, "days": days, "cost": cost}


func specialise(aid: String, uid: int, spec: String) -> Dictionary:
	var u := unit(aid, uid)
	if u.is_empty() or not D.SPECS.has(spec) or not (String(u["k"]) in (D.SPECS[spec]["units"] as Array)):
		return {"ok": false, "reason": "not_allowed"}
	if int(u["sp_left"]) > 0 or int(u["tr_left"]) > 0:
		return {"ok": false, "reason": "busy"}
	u["sp_left"] = int(D.SPECS[spec]["days"])
	u["sp_to"] = spec
	return {"ok": true, "days": u["sp_left"]}


func equip(aid: String, uid: int, quality: float, gold_each: float) -> bool:
	var a: Dictionary = _ar.get(aid, {})
	var u := unit(aid, uid)
	if u.is_empty():
		return false
	var cost := int(ceil(float(u["n"]) * gold_each))
	if cost > int(a["purse"]):
		return false
	a["purse"] = int(a["purse"]) - cost
	u["eq"] = clampf(maxf(float(u["eq"]), quality), 0.0, 1.0)
	return true


## An officer: from a WorldSim row (a real person, upgraded to a Character) or invented. Role "commander" or "sub".
func appoint(aid: String, who: Dictionary, role := "commander") -> String:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty():
		return ""
	var reg: Variant = _mod("registry")
	var row := int(who.get("row", -1))
	var oid := ""
	if row >= 0 and reg != null:
		oid = reg.upgrade_row(row)
	if oid == "" and reg != null:
		oid = reg.mint("ch")
		reg.upgrade(oid)
	if oid == "":
		oid = "ch:o%d" % (a["offs"] as Dictionary).size()
	var seed_n := row if row >= 0 else _num(aid) * 31 + (a["offs"] as Dictionary).size()
	var off := {"name": String(who.get("name", WorldSim.person_name(row) if row >= 0 else "Officer %d" % seed_n)),
		"comp": clampf(float(who.get("comp", 0.25 + 0.7 * _h("comp", seed_n))), 0.0, 1.0),
		"pers": String(who.get("pers", D.OFFICER_PERS[int(_h("pers", seed_n) * D.OFFICER_PERS.size()) % D.OFFICER_PERS.size()])),
		"loy": clampf(float(who.get("loy", 0.5 + 0.4 * _h("loy", seed_n))), 0.0, 1.0), "role": role, "standing": {}, "units": []}
	(a["offs"] as Dictionary)[oid] = off
	if role == "commander":
		a["cmd"] = oid
	return oid


func officer(aid: String, oid: String) -> Dictionary:
	return ((_ar.get(aid, {}) as Dictionary).get("offs", {}) as Dictionary).get(oid, {})


func comp_of(aid: String, u: Dictionary) -> float:
	var a: Dictionary = _ar.get(aid, {})
	var o: Dictionary = officer(aid, String(u.get("off", "")))
	if o.is_empty():
		o = officer(aid, String(a.get("cmd", "")))
	return float(o.get("comp", 0.3))


## Hands units to a sub-commander (who obeys the commander but acts on his own standing orders when orders do not reach him).
func delegate(aid: String, oid: String, uids: Array) -> bool:
	var a: Dictionary = _ar.get(aid, {})
	var o: Dictionary = officer(aid, oid)
	if a.is_empty() or o.is_empty() or oid == String(a["cmd"]):
		return false
	for uid: Variant in uids:
		var u := unit(aid, int(uid))
		if not u.is_empty():
			u["off"] = oid
			if not (o["units"] as Array).has(int(uid)):
				(o["units"] as Array).append(int(uid))
	return true


## Standing orders: {kind, retreat_morale, avoid_ratio, radius}. Without an oid they belong to the army.
func set_standing(aid: String, orders: Dictionary, oid := "") -> bool:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty():
		return false
	var o := {"kind": String(orders.get("kind", "hold")), "retreat_morale": float(orders.get("retreat_morale", 0.25)),
		"avoid_ratio": float(orders.get("avoid_ratio", 0.8)), "radius": float(orders.get("radius", 220.0))}
	if oid == "":
		a["standing"] = o
	else:
		var off: Dictionary = officer(aid, oid)
		if off.is_empty():
			return false
		off["standing"] = o
	return true


func set_mode(aid: String, mode: String) -> bool:
	if not _ar.has(aid) or mode not in ["manual", "delegated", "autonomous"]:
		return false
	(_ar[aid] as Dictionary)["mode"] = mode
	return true


# ------------------------------------------------------------------ strength

func unit_power(u: Dictionary, defending := false) -> float:
	var ud: Dictionary = D.UNITS[String(u["k"])]
	var p := float(u["n"]) * float(ud["pw"]) * (0.5 + float(u["lvl"]) * 0.16) * (0.6 + 0.5 * float(u["eq"])) * (0.45 + float(u["mo"])) * (0.6 + 0.4 * float(u["di"]))
	if int(u["tr_left"]) > 0:
		p *= 0.25
	var sp := String(u["spec"])
	if sp != "":
		p *= float(D.SPECS[sp]["def" if defending else "atk"])
	return p


func power(aid: String, defending := false) -> float:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty():
		return 0.0
	var tot := 0.0
	for u: Dictionary in a["units"]:
		tot += unit_power(u, defending) * (0.9 + 0.3 * comp_of(aid, u))
	var n := men(aid)
	var fed := 1.0 if (float(a["food"]) >= float(n) * D.RATION or int(a["hungry"]) == 0) else 0.75
	return tot * fed * maxf(0.6, 1.0 - 0.08 * float(a["unpaid"]))


func morale(aid: String) -> float:
	var a: Dictionary = _ar.get(aid, {})
	var n := 0
	var s := 0.0
	for u: Dictionary in a.get("units", []):
		n += int(u["n"])
		s += float(u["n"]) * float(u["mo"])
	return s / float(n) if n > 0 else 0.0


func discipline(aid: String) -> float:
	var a: Dictionary = _ar.get(aid, {})
	var n := 0
	var s := 0.0
	for u: Dictionary in a.get("units", []):
		n += int(u["n"])
		s += float(u["n"]) * float(u["di"])
	return s / float(n) if n > 0 else 0.0


## Damage in battle: `frac` of every unit dies (officers' units a little less), morale drops.
func hurt(aid: String, frac: float, morale_hit := 0.1) -> int:
	var a: Dictionary = _ar.get(aid, {})
	var lost := 0
	for u: Dictionary in a.get("units", []):
		var l := mini(int(u["n"]), int(round(float(u["n"]) * frac)))
		u["n"] = int(u["n"]) - l
		u["mo"] = clampf(float(u["mo"]) - morale_hit, 0.0, 1.0)
		lost += l
	if not a.is_empty():
		a["units"] = (a["units"] as Array).filter(func(x: Dictionary) -> bool: return int(x["n"]) > 0)
	return lost


func upkeep(aid: String) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	var wages := 0.0
	var paid_men := 0
	for u: Dictionary in a.get("units", []):
		var ud: Dictionary = D.UNITS[String(u["k"])]
		var wm := float(D.FORCES[String(a["kind"])]["wage"])
		var paying := maxi(0, int(u["n"]) - int(u["real"]))
		wages += float(paying) * float(ud["wage"]) * wm * (1.0 + D.LEVEL_WAGE * float(u["lvl"])) * 0.5
		paid_men += paying
	return {"wages": int(ceil(wages)), "food": men(aid) * D.RATION, "paid_men": paid_men, "contracted": int(a.get("contracted", 0))}


func upkeep_total(owner: String) -> Dictionary:
	var w := 0
	var f := 0.0
	for k: String in _ar:
		if String((_ar[k] as Dictionary)["owner"]) == owner:
			var u := upkeep(k)
			w += int(u["wages"])
			f += float(u["food"])
	return {"wages": w, "food": f}


# ------------------------------------------------------------------ logistics

func fund(aid: String, gold: int) -> bool:
	if not _ar.has(aid) or gold <= 0:
		return false
	(_ar[aid] as Dictionary)["purse"] = int((_ar[aid] as Dictionary)["purse"]) + gold
	return true


func carry_cap(aid: String) -> float:
	var a: Dictionary = _ar.get(aid, {})
	return float(int(a.get("wagons", 0))) * D.WAGON_CAP + float(men(aid)) * D.CARRY_PER_MAN


func buy_supply(aid: String, qty: float) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty():
		return {"ok": false}
	qty = minf(qty, carry_cap(aid) - float(a["food"]))
	var cost := int(ceil(qty * D.FOOD_PRICE))
	if qty <= 0.0 or cost > int(a["purse"]):
		return {"ok": false, "reason": "capacity_or_gold"}
	a["purse"] = int(a["purse"]) - cost
	a["food"] = float(a["food"]) + qty
	(a["ledger"] as Dictionary)["food"] = int((a["ledger"] as Dictionary)["food"]) + cost
	return {"ok": true, "qty": qty, "cost": cost}


func add_wagons(aid: String, n: int) -> void:
	if _ar.has(aid):
		(_ar[aid] as Dictionary)["wagons"] = int((_ar[aid] as Dictionary)["wagons"]) + n


## A wagon train carries food and gold from a place to an army; it moves at TRAIN_SPEED and can be intercepted.
func send_train(aid: String, from_pos: Array, food: float, gold := 0, wagons := 1) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty() or _trains.size() >= TRAINS_MAX:
		return {"ok": false}
	var food_c := minf(food, float(wagons) * D.WAGON_CAP)
	var t := {"t": _next_c, "aid": aid, "food": food_c, "gold": gold, "pos": [float(from_pos[0]), float(from_pos[1])], "owner": a["owner"], "lost": false}
	_next_c += 1
	_trains.append(t)
	return {"ok": true, "t": t["t"], "eta_h": ceil(_dist(from_pos, a["pos"]) / D.TRAIN_SPEED)}


func trains() -> Array:
	return _trains.duplicate(true)


func intercept_train(tid: int, by_aid: String) -> bool:
	for t: Dictionary in _trains:
		if int(t["t"]) == tid and not bool(t["lost"]):
			var b: Dictionary = _ar.get(by_aid, {})
			if b.is_empty() or _dist(b["pos"], t["pos"]) > 150.0:
				return false
			t["lost"] = true
			b["food"] = minf(carry_cap(by_aid), float(b["food"]) + float(t["food"]) * 0.5)
			b["purse"] = int(b["purse"]) + int(int(t["gold"]) / 2)
			_ev("military", -1, [String(t["aid"]), by_aid], "convoy_taken", "A supply train for %s was taken" % [(_ar.get(String(t["aid"]), {}) as Dictionary).get("name", "an army")], 4)
			return true
	return false


func _trains_hour() -> void:
	for t: Dictionary in _trains:
		if bool(t["lost"]):
			continue
		var a: Dictionary = _ar.get(String(t["aid"]), {})
		if a.is_empty():
			t["lost"] = true
			continue
		var d := _dist(t["pos"], a["pos"])
		if d <= D.TRAIN_SPEED:
			a["food"] = minf(carry_cap(String(t["aid"])), float(a["food"]) + float(t["food"]))
			a["purse"] = int(a["purse"]) + int(t["gold"])
			t["lost"] = true
			t["done"] = true
		else:
			var k := D.TRAIN_SPEED / d
			t["pos"] = [float(t["pos"][0]) + (float(a["pos"][0]) - float(t["pos"][0])) * k, float(t["pos"][1]) + (float(a["pos"][1]) - float(t["pos"][1])) * k]
	_trains = _trains.filter(func(t: Dictionary) -> bool: return not bool(t["lost"]))


func _stock_ration(a: Dictionary, need: float) -> float:
	## Garrisons eat the settlement stockpile first.
	var sid := int(a["sid"])
	if sid >= 0 and _def.has(sid) and String((_def[sid] as Dictionary)["garrison"]) == String(a["id"]):
		var st: Dictionary = (_def[sid] as Dictionary)["stock"]
		var take := minf(need, float(st["food"]))
		st["food"] = float(st["food"]) - take
		return take
	return 0.0


func _army_day(aid: String) -> void:
	var a: Dictionary = _ar[aid]
	var led: Dictionary = a["ledger"]
	led["days"] = int(led["days"]) + 1
	var n := men(aid)
	if n <= 0:
		return
	# training and specialisation
	for u: Dictionary in a["units"]:
		if int(u["tr_left"]) > 0:
			u["tr_left"] = int(u["tr_left"]) - 1
			if int(u["tr_left"]) == 0:
				u["lvl"] = int(u["tr_to"])
				u["mo"] = clampf(float(u["mo"]) + 0.05, 0.0, 1.0)
				u["di"] = clampf(float(u["di"]) + 0.04, 0.0, 1.0)
		if int(u["sp_left"]) > 0:
			u["sp_left"] = int(u["sp_left"]) - 1
			if int(u["sp_left"]) == 0:
				u["spec"] = String(u["sp_to"])
	# rations
	var need := float(n) * D.RATION
	var got := _stock_ration(a, need)
	var from_pack := minf(float(a["food"]), need - got)
	a["food"] = float(a["food"]) - from_pack
	got += from_pack
	if got + 0.001 < need:
		a["hungry"] = int(a["hungry"]) + 1
		_shift(a, -0.05, -0.02)
		_desert(aid, 0.03 * float(mini(int(a["hungry"]), 4)), "hunger")
	else:
		a["hungry"] = 0
	# wages
	var up := upkeep(aid)
	var due := int(up["wages"])
	if due <= int(a["purse"]):
		a["purse"] = int(a["purse"]) - due
		led["wages"] = int(led["wages"]) + due
		_note_upkeep(aid, a, due)
		if int(a["unpaid"]) > 0:
			a["unpaid"] = 0
		else:
			_shift(a, 0.008, 0.004)
	else:
		a["unpaid"] = int(a["unpaid"]) + 1
		_shift(a, -0.04, -0.03)
		if int(a["unpaid"]) > D.DESERT_GRACE:
			_desert(aid, minf(0.3, 0.04 * float(int(a["unpaid"]) - D.DESERT_GRACE)), "unpaid")
	if String(a["state"]) == "marching":
		for u2: Dictionary in a["units"]:
			u2["eq"] = clampf(float(u2["eq"]) - 0.003, 0.0, 1.0)


## The army pays from its own purse (no gold moves here); the ledger records it in the weekly summary of the owner.
func _note_upkeep(aid: String, a: Dictionary, amt: int) -> void:
	var lg: Variant = _mod("ledger")
	if lg != null and amt > 0:
		lg.note("ar:" + aid, "", "upkeep", amt)


func _shift(a: Dictionary, dm: float, dd: float) -> void:
	for u: Dictionary in a["units"]:
		u["mo"] = clampf(float(u["mo"]) + dm, 0.0, 1.0)
		u["di"] = clampf(float(u["di"]) + dd, 0.0, 1.0)


func _desert(aid: String, rate: float, why: String) -> void:
	var a: Dictionary = _ar[aid]
	var lost := 0
	var day_n := _now()
	for u: Dictionary in a["units"]:
		var base := float(u["n"]) * rate * (1.2 - float(u["di"]))
		var l := int(floor(base + _h("desert", int(u["u"]), day_n)))
		l = mini(l, int(u["n"]) - int(u["real"]))
		if l > 0:
			u["n"] = int(u["n"]) - l
			lost += l
	if lost > 0:
		a["deserted"] = int(a["deserted"]) + lost
		stats["deserted"] = int(stats["deserted"]) + lost
		a["units"] = (a["units"] as Array).filter(func(x: Dictionary) -> bool: return int(x["n"]) > 0)
		_ev("military", int(a["sid"]), [aid], "desertion_" + why, "%d men desert %s (%s)" % [lost, a["name"], why], 3 if lost < 10 else 4)


# ------------------------------------------------------------------ levies (farming.gd)

func levy(owner: String, sid: int, n: int, days := 20, opts: Dictionary = {}) -> Dictionary:
	var st: Variant = _mod("settlements")
	var pop := int(st.population(sid)) if st != null else 100
	var farm_hands := maxi(10, int(pop * 0.5))
	n = mini(n, int(farm_hands * 0.6))
	if n <= 0 or _levied.has(sid):
		return {"ok": false, "reason": "none_to_draw_or_already_levied"}
	var lim := legal_limit(owner, "levy")
	var over := men_of(owner, "levy") + n > lim
	if over and not bool(opts.get("force", false)):
		return {"ok": false, "reason": "over_legal_limit", "limit": lim}
	var r := found(owner, "levy", "Levy of %s" % (st.sname(sid) if st != null else str(sid)), sid, {"npc": bool(opts.get("npc", false))})
	if not bool(r["ok"]):
		return r
	var aid := String(r["id"])
	add_unit(aid, "spear", n, {"eq": 0.25, "mo": 0.5, "di": 0.35})
	(_ar[aid] as Dictionary)["purse"] = int(opts.get("purse", n * 3))
	_levied[sid] = {"n": n, "until": _now() + days, "aid": aid, "hands": farm_hands}
	_push_levy(sid)
	_ev("military", sid, [aid], "levy", "%d farmers are called up from %s" % [n, st.sname(sid) if st != null else str(sid)], 3)
	return {"ok": true, "id": aid, "n": n, "over": over}


func release_levy(sid: int) -> int:
	var l: Dictionary = _levied.get(sid, {})
	if l.is_empty():
		return 0
	var back := men(String(l["aid"]))
	if _ar.has(String(l["aid"])):
		var owner := String((_ar[String(l["aid"])] as Dictionary)["owner"])
		_ar.erase(String(l["aid"]))
		_review(owner)
	_levied.erase(sid)
	_push_levy(sid)
	_ev("military", sid, [], "levy_released", "%d levied men return to the fields" % back, 2)
	return back


func levied_at(sid: int) -> int:
	var l: Dictionary = _levied.get(sid, {})
	return men(String(l["aid"])) if not l.is_empty() else 0


func _push_levy(sid: int) -> void:
	var fm: Variant = _mod("farming")
	if fm == null or not fm.has_method("set_levy"):
		return
	var l: Dictionary = _levied.get(sid, {})
	fm.set_levy(sid, clampf(float(levied_at(sid)) / float(maxi(10, int(l.get("hands", 40)))), 0.0, 0.8) if not l.is_empty() else 0.0)


# ------------------------------------------------------------------ command: couriers, obedience, standing orders

func set_hq(owner: String, pos: Array) -> void:
	_hq[owner] = [float(pos[0]), float(pos[1])]


func hq(owner: String) -> Array:
	return _hq.get(owner, [])


func courier_hours(aid: String) -> float:
	var a: Dictionary = _ar.get(aid, {})
	var h: Array = _hq.get(String(a.get("owner", "")), [])
	if a.is_empty() or h.is_empty():
		return 1.0
	return maxf(1.0, ceil(_dist(h, a["pos"]) / D.COURIER_SPEED))


## 1.0 when the commander is within a day's ride, falling to 0.2 for a week away.
func comms(aid: String) -> float:
	return clampf(1.0 - courier_hours(aid) / 24.0 * 0.15, 0.2, 1.0)


func obedience(aid: String, uid: int, order: Dictionary, seq := 0) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	var u := unit(aid, uid)
	if a.is_empty() or u.is_empty():
		return {"p": 0.0, "obeys": false, "why": "none"}
	var o: Dictionary = officer(aid, String(u.get("off", "")))
	if o.is_empty():
		o = officer(aid, String(a["cmd"]))
	var p := 0.34 * float(u["mo"]) + 0.34 * float(u["di"]) + 0.14 * float(o.get("comp", 0.3)) + 0.18 * comms(aid)
	p += 0.06 * (float(o.get("loy", 0.5)) - 0.5) * 2.0
	if String(o.get("pers", "")) == "loyal":
		p += 0.05
	p -= minf(0.4, 0.1 * float(a["unpaid"]))
	var kind := String(order.get("kind", "hold"))
	p -= float(D.RISKY.get(kind, 0.0)) * (1.0 + (1.0 - float(u["mo"])))
	if String(o.get("pers", "")) == "bold" and kind == "attack":
		p += 0.08
	if String(o.get("pers", "")) == "careful" and kind == "attack":
		p -= 0.08
	p = clampf(p, 0.0, 1.0)
	var roll := _h("obey", _num(aid) * 1000 + uid, seq)
	var why := "obeys"
	var ok := roll < p
	if not ok:
		why = "deserts" if (p < 0.15 and int(a["unpaid"]) > D.DESERT_GRACE) else "defies"
	return {"p": snappedf(p, 0.001), "obeys": ok, "why": why}


func _route_danger(aid: String) -> float:
	## Chance an enemy patrol takes the courier: enemy armies near the straight line from the hq.
	var a: Dictionary = _ar[aid]
	var h: Array = _hq.get(String(a["owner"]), [])
	if h.is_empty():
		return 0.0
	var mid := [(float(h[0]) + float(a["pos"][0])) * 0.5, (float(h[1]) + float(a["pos"][1])) * 0.5]
	var p := 0.0
	for k: String in _ar:
		var b: Dictionary = _ar[k]
		if is_hostile(String(a["owner"]), String(b["owner"])):
			if _dist(b["pos"], mid) < 260.0 or _dist(b["pos"], a["pos"]) < 200.0:
				p += 0.3
	return minf(p, 0.8)


## Sends an order by courier. It arrives after the ride and is checked unit by unit; the sender hears back one ride later.
func send_order(aid: String, order: Dictionary) -> Dictionary:
	var a: Dictionary = _ar.get(aid, {})
	if a.is_empty() or _couriers.size() >= COURIERS_MAX:
		return {"ok": false}
	var o := {"kind": String(order.get("kind", "hold"))}
	for k: String in ["target", "x", "y", "sid"]:
		if order.has(k):
			o[k] = order[k]
	var hrs := int(courier_hours(aid))
	var seq := _seq
	_seq += 1
	var lost := _h("courier", seq, _num(aid)) < _route_danger(aid)
	_couriers.append({"c": seq, "aid": aid, "order": o, "sent": _hours, "eta": _hours + hrs, "ack": _hours + hrs * 2, "seq": seq, "lost": lost})
	_orders.append({"seq": seq, "aid": aid, "kind": o["kind"], "sent": _hours, "arrives": _hours + hrs, "ack": _hours + hrs * 2, "truth": "sent", "obeyed": 0, "men": 0})
	if _orders.size() > ORDERS_KEEP:
		_orders.pop_front()
	stats["orders"] = int(stats["orders"]) + 1
	return {"ok": true, "seq": seq, "eta_hours": hrs}


func couriers() -> Array:
	return _couriers.duplicate(true)


func _order_row(seq: int) -> Dictionary:
	for r: Dictionary in _orders:
		if int(r["seq"]) == seq:
			return r
	return {}


## What the sender knows: "sent" until the reply could have come back, then the truth ("obeyed", "partial", "defied") or "no_reply" for a lost courier.
func order_view(seq: int) -> Dictionary:
	var r := _order_row(seq)
	if r.is_empty():
		return {}
	var known := _hours >= int(r["ack"])
	var st := "sent"
	if known:
		st = "no_reply" if String(r["truth"]) == "lost" else String(r["truth"])
	return {"seq": seq, "aid": r["aid"], "kind": r["kind"], "state": st, "known": known, "eta_h": maxi(0, int(r["arrives"]) - _hours)}


func _deliver(c: Dictionary) -> void:
	var aid := String(c["aid"])
	var row := _order_row(int(c["seq"]))
	if bool(c["lost"]) or not _ar.has(aid):
		if not row.is_empty():
			row["truth"] = "lost"
		stats["lost_orders"] = int(stats["lost_orders"]) + 1
		return
	var a: Dictionary = _ar[aid]
	var tot := 0
	var ok_men := 0
	for u: Dictionary in a["units"]:
		var r := obedience(aid, int(u["u"]), c["order"], int(c["seq"]))
		tot += int(u["n"])
		if bool(r["obeys"]):
			ok_men += int(u["n"])
			u["mode"] = "obey"
		else:
			u["mode"] = "defiant"
			if String(r["why"]) == "deserts":
				u["mo"] = clampf(float(u["mo"]) - 0.1, 0.0, 1.0)
	var share := float(ok_men) / float(maxi(tot, 1))
	var truth := "obeyed" if share >= 0.9 else ("partial" if share >= 0.3 else "defied")
	if share >= 0.3:
		_apply_order(a, c["order"])
	if not row.is_empty():
		row["truth"] = truth
		row["obeyed"] = ok_men
		row["men"] = tot
	if truth == "defied":
		_ev("military", int(a["sid"]), [aid], "order_defied", "%s would not carry out the order to %s" % [a["name"], c["order"]["kind"]], 4)


func _apply_order(a: Dictionary, order: Dictionary) -> void:
	a["order"] = order.duplicate()
	a["order_day"] = _now()
	var k := String(order["kind"])
	if order.has("x") and order.has("y"):
		a["dest"] = [float(order["x"]), float(order["y"])]
	elif order.has("sid"):
		a["dest"] = _pos_of_sid(int(order["sid"]))
	elif k in ["hold", "defend"]:
		a["dest"] = []
	a["state"] = "marching" if not (a["dest"] as Array).is_empty() else "camped"
	var cm: Variant = _mod("campaign")
	if int(a["camp"]) >= 0 and cm != null and cm.has_method("apply_order_now") and order.has("target"):
		cm.apply_order_now(int(a["camp"]), {"kind": k, "target": int(order["target"])})


func _standing_for(aid: String, a: Dictionary) -> Dictionary:
	var s: Dictionary = a["standing"]
	if s.is_empty():
		s = officer(aid, String(a["cmd"])).get("standing", {})
	return s


## Delegated and cut-off armies act on their standing orders. Returns a line when something was decided.
func _standing_step(aid: String) -> void:
	var a: Dictionary = _ar[aid]
	var stale := _now() - int(a["order_day"]) >= 5
	if String(a["mode"]) == "manual" and not (stale and comms(aid) < 0.45):
		return
	var s := _standing_for(aid, a)
	if s.is_empty():
		return
	var home: Array = _pos_of_sid(int(a["sid"])) if int(a["sid"]) >= 0 else (_hq.get(String(a["owner"]), a["pos"]))
	if morale(aid) < float(s["retreat_morale"]):
		a["order"] = {"kind": "retreat"}
		a["dest"] = home
		a["state"] = "marching"
		_ev("military", int(a["sid"]), [aid], "fell_back", "%s falls back on standing orders (morale)" % a["name"], 3)
		return
	var foe := _nearest_known_foe(a)
	if not foe.is_empty() and _dist(a["pos"], foe["pos"]) < float(s["radius"]):
		var ratio := power(aid) / maxf(1.0, float(foe["n"]) * 0.8)
		if ratio < float(s["avoid_ratio"]):
			a["order"] = {"kind": "retreat"}
			a["dest"] = home
			a["state"] = "marching"
			_ev("military", int(a["sid"]), [aid], "avoids_foe", "%s avoids a stronger foe" % a["name"], 3)
			return
	match String(s["kind"]):
		"patrol":
			if (a["dest"] as Array).is_empty():
				var ang := _h("patrol", _num(aid), _now()) * TAU
				a["dest"] = [float(home[0]) + cos(ang) * float(s["radius"]), float(home[1]) + sin(ang) * float(s["radius"])]
				a["order"] = {"kind": "patrol"}
				a["state"] = "marching"
		"defend", "hold":
			if _dist(a["pos"], home) > 40.0 and (a["dest"] as Array).is_empty():
				a["dest"] = home
				a["state"] = "marching"


func _nearest_known_foe(a: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1e18
	var book: Dictionary = _sight.get(String(a["owner"]), {})
	for k: String in _sorted_ids(book):
		var e: Dictionary = book[k]
		var d := _dist(a["pos"], e["pos"])
		if d < bd and _hours - int(e["seen"]) < 72:
			bd = d
			best = e
	return best


func _move_hour(a: Dictionary) -> void:
	if int(a["camp"]) >= 0:
		return
	var dest: Array = a["dest"]
	if dest.is_empty():
		return
	var spd := D.ARMY_SPEED * (0.7 if int(a["hungry"]) > 0 else 1.0)
	var d := _dist(a["pos"], dest)
	if d <= spd:
		a["pos"] = [float(dest[0]), float(dest[1])]
		a["dest"] = []
		a["state"] = "camped"
	else:
		var k := spd / d
		a["pos"] = [float(a["pos"][0]) + (float(dest[0]) - float(a["pos"][0])) * k, float(a["pos"][1]) + (float(dest[1]) - float(a["pos"][1])) * k]


# ------------------------------------------------------------------ hostility, scouting, fog of war

func set_hostile(a: String, b: String, on := true) -> void:
	_hostile[a + "|" + b] = on
	_hostile[b + "|" + a] = on
	if not on:
		_hostile.erase(a + "|" + b)
		_hostile.erase(b + "|" + a)


func is_hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	if _hostile.has(a + "|" + b):
		return true
	var ck := a + "|" + b
	if _stance_cache.has(ck):
		return bool(_stance_cache[ck])
	var r := _stance_hostile(a, b)
	_stance_cache[ck] = r
	return r


func _stance_hostile(a: String, b: String) -> bool:
	var f: Variant = _mod("factions")
	if f != null and f.faction(a).size() > 0 and f.faction(b).size() > 0:
		return String(f.relation(a, b)["stance"]) in ["hostile", "war"]
	return false


func sight_radius(a: Dictionary) -> float:
	var r := D.SIGHT_BASE
	for u: Dictionary in a["units"]:
		if String(u["k"]) == "scout" and int(u["n"]) > 0:
			r = maxf(r, D.SIGHT_SCOUT)
		if String(u["spec"]) == "scouting":
			r += 120.0
	return r


## Every army looks for hostile armies inside its sight radius and writes what it sees (position, estimated men, hour).
func scout_pass() -> int:
	var seen := 0
	var keys := ids()
	var n := keys.size()
	var own: Array = []
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var rads := PackedFloat32Array()
	xs.resize(n)
	ys.resize(n)
	rads.resize(n)
	for i in n:
		var a: Dictionary = _ar[keys[i]]
		own.append(String(a["owner"]))
		xs[i] = float(a["pos"][0])
		ys[i] = float(a["pos"][1])
		rads[i] = sight_radius(a)
	for i in n:
		var rad := rads[i]
		for j in n:
			if own[j] == own[i] or absf(xs[i] - xs[j]) > rad or absf(ys[i] - ys[j]) > rad:
				continue
			var dx := xs[i] - xs[j]
			var dy := ys[i] - ys[j]
			if dx * dx + dy * dy > rad * rad or not is_hostile(own[i], own[j]):
				continue
			var kb: String = keys[j]
			var b: Dictionary = _ar[kb]
			var has_scouts: bool = rad > D.SIGHT_BASE
			var err := 0.08 if has_scouts else 0.3
			var est := int(round(float(men(kb)) * (1.0 + (_h("est", _num(kb), _hours) - 0.5) * 2.0 * err)))
			var book: Dictionary = _sight.get(own[i], {})
			book[kb] = {"id": kb, "pos": [float(b["pos"][0]), float(b["pos"][1])], "n": est, "seen": _hours, "src": "scout" if has_scouts else "sight",
				"of": own[j], "dest": [] if not has_scouts else (b["dest"] as Array).duplicate()}
			_sight[own[i]] = book
			seen += 1
	for owner2: String in _sight.keys():
		var bk: Dictionary = _sight[owner2]
		if bk.size() > SIGHT_KEEP:
			var old := ""
			var oh := 1 << 60
			for k: String in _sorted_ids(bk):
				if int((bk[k] as Dictionary)["seen"]) < oh:
					oh = int((bk[k] as Dictionary)["seen"])
					old = k
			bk.erase(old)
	return seen


## The map a player (viewer owner) sees: own armies exactly, others only as last seen. status: confirmed (seen in the last CONFIRM_HOURS) or stale
## (conf halves every STALE_HALF_DAYS, gone below INTEL_MIN). Never reads the enemy's true position.
func known_map(viewer: String) -> Array:
	var out: Array = []
	for k: String in ids(viewer):
		var a: Dictionary = _ar[k]
		out.append({"id": k, "own": true, "pos": a["pos"].duplicate(), "n": men(k), "status": "confirmed", "conf": 1.0, "age_h": 0, "name": a["name"]})
	var book: Dictionary = _sight.get(viewer, {})
	for k: String in _sorted_ids(book):
		var e: Dictionary = book[k]
		var age := _hours - int(e["seen"])
		var conf := 1.0 if age <= D.CONFIRM_HOURS else pow(0.5, float(age) / 24.0 / D.STALE_HALF_DAYS)
		if conf < D.INTEL_MIN:
			continue
		out.append({"id": k, "own": false, "pos": e["pos"].duplicate(), "n": int(e["n"]), "status": "confirmed" if age <= D.CONFIRM_HOURS else "stale",
			"conf": snappedf(conf, 0.01), "age_h": age, "src": e["src"]})
	return out


# ------------------------------------------------------------------ settlement defence

func _plan(sid: int) -> Dictionary:
	return {"sid": sid, "garrison": "", "patrols": 0, "shifts": 3, "per_shift": 0, "muster": _pos_of_sid(sid), "stock": {"food": 0.0, "arms": 0.0},
		"evac": {"state": "none", "frac": 0.0, "to": -1, "day": 0}, "fallback": {"kind": "keep", "pos": _pos_of_sid(sid)}, "alert": 0, "walls": 0, "gates": 2, "fell_back": false}


func set_defence(sid: int, opts: Dictionary) -> Dictionary:
	var p: Dictionary = _def.get(sid, _plan(sid))
	for k: String in ["patrols", "shifts", "per_shift", "walls", "gates"]:
		if opts.has(k):
			p[k] = maxi(0, int(opts[k]))
	if opts.has("garrison"):
		p["garrison"] = String(opts["garrison"])
		if _ar.has(String(opts["garrison"])):
			var g: Dictionary = _ar[String(opts["garrison"])]
			g["sid"] = sid
			g["pos"] = _pos_of_sid(sid)
			var dv: Variant = _mod("districts")
			if dv != null:
				dv.act("garrison_posted", sid, "military" if dv.has_quarter(sid, "military") else "merchant", String(g["owner"]), clampf(float(men(String(opts["garrison"]))) / 40.0, 0.3, 2.0))
	if opts.has("muster"):
		p["muster"] = [float(opts["muster"][0]), float(opts["muster"][1])]
	if opts.has("fallback"):
		p["fallback"] = {"kind": String(opts["fallback"].get("kind", "keep")), "pos": opts["fallback"].get("pos", p["fallback"]["pos"])}
	p["walls"] = clampi(int(p["walls"]), 0, D.WALL_BONUS.size() - 1)
	_def[sid] = p
	return p.duplicate(true)


func defence(sid: int) -> Dictionary:
	return (_def.get(sid, {}) as Dictionary).duplicate(true)


func defended_sids() -> Array:
	var out := _def.keys()
	out.sort()
	return out


func stock_up(sid: int, item: String, qty: float) -> bool:
	if not _def.has(sid) or item not in ["food", "arms"]:
		return false
	var st: Dictionary = (_def[sid] as Dictionary)["stock"]
	st[item] = float(st[item]) + qty
	return true


func watch_cover(sid: int) -> float:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return 0.0
	return clampf(float(mini(int(p["shifts"]), 3) * int(p["per_shift"])) / float(D.WATCH_FULL), 0.0, 1.0)


func _pop_left(sid: int) -> float:
	var st: Variant = _mod("settlements")
	var pop := float(st.population(sid)) if st != null else 100.0
	var p: Dictionary = _def.get(sid, {})
	return pop * (1.0 - float((p.get("evac", {}) as Dictionary).get("frac", 0.0)) * (1.0 if String((p.get("evac", {}) as Dictionary).get("state", "")) == "done" else 0.5))


func food_days(sid: int) -> float:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return 0.0
	var g := men(String(p["garrison"])) + int(p["patrols"]) + int(p["per_shift"])
	var eaters := float(g) + _pop_left(sid) * 0.2
	return float((p["stock"] as Dictionary)["food"]) / maxf(1.0, eaters * D.RATION)


func defence_rating(sid: int) -> float:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return 0.0
	var r := power(String(p["garrison"]), true) + float(p["patrols"]) * 0.8 + float(p["per_shift"]) * 0.4
	r *= float(D.WALL_BONUS[int(p["walls"])]) * (0.7 + 0.3 * watch_cover(sid)) * (1.0 + 0.1 * float(p["alert"]))
	if men(String(p["garrison"])) > 0 and _dist(p["muster"], _pos_of_sid(sid)) < 120.0:
		r *= 1.05
	if food_days(sid) < 3.0:
		r *= 0.8
	if bool(p["fell_back"]):
		r *= 0.2
	return r


func weak_points(sid: int) -> Array:
	var p: Dictionary = _def.get(sid, {})
	var out: Array = []
	if p.is_empty():
		return ["undefended"]
	if watch_cover(sid) < 0.5:
		out.append("gate_unwatched")
	if men(String(p["garrison"])) < 8:
		out.append("thin_garrison")
	if food_days(sid) < 5.0:
		out.append("low_stock")
	if int(p["walls"]) == 0:
		out.append("no_walls")
	if String((p["evac"] as Dictionary)["state"]) == "none" and int(p["alert"]) >= 2:
		out.append("no_evacuation_plan")
	return out


## Patrols and the watch notice an approaching enemy: raises the alert, musters the garrison and (alert 3) starts an evacuation.
func raise_alert(sid: int, level: int) -> bool:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return false
	level = clampi(level, 0, 3)
	if level <= int(p["alert"]) and level != 0:
		return false
	p["alert"] = level
	if level >= 1 and _ar.has(String(p["garrison"])):
		var g: Dictionary = _ar[String(p["garrison"])]
		g["order"] = {"kind": "defend"}
		g["dest"] = [float(p["muster"][0]), float(p["muster"][1])]
		g["state"] = "marching"
	if level >= 3 and String((p["evac"] as Dictionary)["state"]) == "none":
		evacuate(sid, 0.5)
	_ev("emergency", sid, [String(p["garrison"])], "alert_%d" % level, "Alert %d raised" % level, 3)
	return true


func evacuate(sid: int, frac := 0.6, to := -1) -> Dictionary:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return {"ok": false}
	var ev: Dictionary = p["evac"]
	if String(ev["state"]) in ["evacuating", "done"]:
		return {"ok": false, "reason": "already"}
	if to < 0:
		var best := 1 << 30
		var bd := 1e18
		for s: Dictionary in WorldGen.settlements:
			var d := _dist(_pos_of_sid(sid), _pos_of_sid(int(s["id"])))
			if int(s["id"]) != sid and d < bd and d > 0.0:
				bd = d
				best = int(s["id"])
		to = best if best != (1 << 30) else -1
	ev["state"] = "evacuating"
	ev["frac"] = clampf(frac, 0.0, 0.9)
	ev["to"] = to
	ev["day"] = _now()
	_ev("emergency", sid, [], "evacuation", "Evacuation of %d%% of the people begins" % int(frac * 100.0), 4)
	return {"ok": true, "to": to}


func return_evacuees(sid: int) -> bool:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty() or String((p["evac"] as Dictionary)["state"]) == "none":
		return false
	p["evac"] = {"state": "none", "frac": 0.0, "to": -1, "day": _now()}
	p["fell_back"] = false
	p["alert"] = 0
	return true


## The garrison leaves the walls for the fallback position (keep, hill fort, or a point) and the settlement is left to the people.
func fall_back(sid: int) -> bool:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return false
	p["fell_back"] = true
	if _ar.has(String(p["garrison"])):
		var g: Dictionary = _ar[String(p["garrison"])]
		g["pos"] = [float(p["fallback"]["pos"][0]), float(p["fallback"]["pos"][1])]
		g["order"] = {"kind": "hold"}
		g["state"] = "camped"
	_ev("emergency", sid, [String(p["garrison"])], "fallback", "The garrison falls back to the %s" % String(p["fallback"]["kind"]), 4)
	return true


# ------------------------------------------------------------------ attackers

func insider_chance(sid: int) -> float:
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		return 0.0
	var aid := String(p["garrison"])
	var a: Dictionary = _ar.get(aid, {})
	var c := 0.05
	if not a.is_empty():
		c += 0.5 * minf(1.0, float(a["unpaid"]) / 5.0) + 0.3 * (1.0 - morale(aid)) + 0.15 * (1.0 - discipline(aid))
		var o: Dictionary = officer(aid, String(a["cmd"]))
		if String(o.get("pers", "")) == "greedy":
			c += 0.15
		c -= 0.2 * float(o.get("loy", 0.5))
	else:
		c += 0.2
	return clampf(c, 0.0, 0.85)


## What an attacker learns about a defended settlement. Precision depends on scouts: a guess otherwise (a wide error, fixed per attacker and day).
func evaluate_defence(att: Dictionary, sid: int) -> Dictionary:
	var err := 0.12 if bool(att.get("scouts", false)) else 0.4
	var n := int(hash(String(att.get("owner", "x")))) % 997
	var est := defence_rating(sid) * (1.0 + (_h("evalnoise", sid * 31 + n, _now()) - 0.5) * 2.0 * err)
	var p: Dictionary = _def.get(sid, {})
	return {"sid": sid, "est_rating": est, "ratio": float(att.get("power", 0.0)) / maxf(est, 1.0), "watch_gap": 1.0 - watch_cover(sid),
		"insider": insider_chance(sid), "food_days": food_days(sid), "walls": int(p.get("walls", 0)), "evac": String((p.get("evac", {}) as Dictionary).get("state", "none")),
		"garrison": men(String(p.get("garrison", ""))), "loot": _loot(sid)}


func _loot(sid: int) -> float:
	var st: Variant = _mod("settlements")
	var pop := float(st.population(sid)) if st != null else 100.0
	var p: Dictionary = _def.get(sid, {})
	var left := 1.0 - float((p.get("evac", {}) as Dictionary).get("frac", 0.0)) * 0.6
	return (pop * 0.3 + float((p.get("stock", {"food": 0.0}) as Dictionary)["food"]) * 0.2) * left


## Picks a target and a method among `cands` (settlement ids): attacks that look winnable, siege if the stores are short, a bribe if the garrison is
## unpaid, a raid on the outskirts if they are poorly watched, otherwise skip. att: {owner, power, men, gold, patience, scouts}
func choose_attack(att: Dictionary, cands: Array) -> Dictionary:
	var best := {"sid": -1, "method": "skip", "score": 0.0}
	var evals := {}
	var men_a := float(att.get("men", 20))
	for sid: Variant in cands:
		var s := int(sid)
		var ev := evaluate_defence(att, s)
		evals[s] = ev
		var loot := float(ev["loot"])
		var win_p := clampf((float(ev["ratio"]) - 0.6) / 1.2, 0.0, 1.0)
		var price := 40.0 + float(ev["garrison"]) * 3.0
		var est := float(ev["est_rating"])
		var loss_frac := clampf(0.1 + 0.4 * est / maxf(float(att.get("power", 0.0)) + est, 1.0), 0.1, 0.6)
		var caught := _catch_chance(s)
		var sc := {"assault": win_p * loot - men_a * (loss_frac + (1.0 - win_p) * 0.4) * 1.2,
			"blockade": (loot * 0.8 - float(ev["food_days"]) * men_a * 0.05) if (float(att.get("patience", 0.0)) >= float(ev["food_days"]) and float(ev["ratio"]) > 0.3) else -1e9,
			"bribe_insider": (float(ev["insider"]) * loot * 1.1 - price * 0.3) if float(att.get("gold", 0.0)) >= price else -1e9,
			"raid_outskirts": loot * 0.22 * (1.0 - caught) - caught * men_a * 1.5}
		for m: String in sc:
			if float(sc[m]) > float(best["score"]) + 1e-6 or (is_equal_approx(float(sc[m]), float(best["score"])) and float(sc[m]) > 0.0 and s < int(best["sid"])):
				best = {"sid": s, "method": m, "score": float(sc[m]), "price": price}
	best["evals"] = evals
	return best


## Chance that patrols and the watch catch raiders working the outskirts.
func _catch_chance(sid: int) -> float:
	var p: Dictionary = _def.get(sid, {})
	return clampf(0.15 + 0.5 * watch_cover(sid) + float(p.get("patrols", 0)) * 0.05, 0.0, 0.95)


func blockades() -> Dictionary:
	return _blk.duplicate(true)


func resolve_attack(att: Dictionary, sid: int, method: String, opts: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _def.get(sid, {})
	var away := not bool(opts.get("player_present", false))
	var owner := String(att.get("owner", "raiders"))
	var res := {"sid": sid, "method": method, "owner": owner, "won": false, "player_away": away, "text": ""}
	if p.is_empty() or method == "skip":
		res["text"] = "No attack."
		return res
	stats["raids"] = int(stats["raids"]) + 1
	var gid := String(p["garrison"])
	var aid := String(att.get("aid", ""))
	var ap := float(att.get("power", 0.0)) if aid == "" else power(aid)
	match method:
		"bribe_insider":
			var price := 40.0 + float(men(gid)) * 3.0
			if _h("bribe", sid, _now()) < insider_chance(sid) and float(att.get("gold", 0.0)) >= price:
				stats["betrayals"] = int(stats["betrayals"]) + 1
				ap *= 1.8
				res["betrayed"] = true
				_ev("crime", sid, [gid], "betrayal", "A gate was opened from inside at %s" % _sname(sid), 6)
				method = "assault"
			else:
				res["text"] = "The bribe was refused and the insider was exposed."
				if _ar.has(gid):
					for u: Dictionary in (_ar[gid] as Dictionary)["units"]:
						u["di"] = clampf(float(u["di"]) + 0.05, 0.0, 1.0)
				_ev("crime", sid, [gid], "bribe_failed", "An attempt to buy a gate at %s failed" % _sname(sid), 4)
				return _finish(res, away)
	match method:
		"assault":
			var dr := defence_rating(sid)
			var sc := ap / maxf(ap + dr, 1.0) + (_h("assault", sid, _now()) - 0.5) * 0.24
			var att_wins := sc > 0.5
			var margin := absf(sc - 0.5)
			var a_loss := clampf(0.12 + (0.35 - margin) * dr / maxf(ap, 1.0) * 0.6, 0.05, 0.6) if att_wins else clampf(0.28 + margin * 0.9, 0.2, 0.75)
			var d_loss := clampf(0.28 + margin * 0.9, 0.2, 0.75) if att_wins else clampf(0.12 + (0.35 - margin) * ap / maxf(dr, 1.0) * 0.6, 0.05, 0.6)
			if aid != "":
				hurt(aid, a_loss, 0.2 if not att_wins else -0.05)
			if gid != "":
				res["defender_lost"] = hurt(gid, d_loss, 0.1 if not att_wins else 0.3)
			res["won"] = att_wins
			if att_wins:
				var sev := clampf(0.4 + margin, 0.2, 1.0) * (1.0 - float((p["evac"] as Dictionary)["frac"]) * 0.6)
				var stt: Variant = _mod("settlements")
				if stt != null:
					stt.raid_aftermath(sid, sev)
				(p["stock"] as Dictionary)["food"] = float((p["stock"] as Dictionary)["food"]) * 0.4
				fall_back(sid)
				stats["fallen"] = int(stats["fallen"]) + 1
				res["text"] = "%s took %s%s." % [owner, _sname(sid), " (betrayed from inside)" if res.get("betrayed", false) else ""]
			else:
				stats["repelled"] = int(stats["repelled"]) + 1
				res["text"] = "%s was beaten off at %s." % [owner, _sname(sid)]
			_ev("battle", sid, [gid] if gid != "" else [], "assault", res["text"], 6 if not away else 5)
		"blockade":
			if not _blk.has(sid):
				_blk[sid] = {"owner": owner, "aid": aid, "since": _now(), "power": ap, "patience": int(att.get("patience", 20)), "men": int(att.get("men", 20))}
				stats["blockades"] = int(stats["blockades"]) + 1
				res["text"] = "%s closes the roads to %s." % [owner, _sname(sid)]
				_ev("emergency", sid, [gid] if gid != "" else [], "blockade", res["text"], 5)
			res["won"] = true
		"raid_outskirts":
			var caught := _h("outskirts", sid, _now()) < _catch_chance(sid)
			if caught:
				stats["repelled"] = int(stats["repelled"]) + 1
				res["text"] = "Patrols caught %s's raiders at the outskirts." % owner
				if aid != "":
					hurt(aid, 0.1, 0.1)
			else:
				var stt2: Variant = _mod("settlements")
				if stt2 != null:
					stt2.raid_aftermath(sid, 0.2 * (1.0 - float((p["evac"] as Dictionary)["frac"]) * 0.5))
				(p["stock"] as Dictionary)["food"] = float((p["stock"] as Dictionary)["food"]) * 0.85
				res["won"] = true
				res["text"] = "%s plundered farms outside %s." % [owner, _sname(sid)]
			_ev("crime", sid, [gid] if gid != "" else [], "raid", res["text"], 4)
	return _finish(res, away)


func _finish(res: Dictionary, away: bool) -> Dictionary:
	if away:
		res["text"] = "While you were away: " + String(res["text"])
	return res


func _sname(sid: int) -> String:
	var st: Variant = _mod("settlements")
	return String(st.sname(sid)) if st != null else "settlement %d" % sid


func _blockade_day(sid: int) -> void:
	var b: Dictionary = _blk[sid]
	var p: Dictionary = _def.get(sid, {})
	if p.is_empty():
		_blk.erase(sid)
		return
	var eaters := float(men(String(p["garrison"])) + int(p["patrols"])) + _pop_left(sid) * 0.2
	var st: Dictionary = p["stock"]
	st["food"] = maxf(0.0, float(st["food"]) - eaters * D.RATION)
	var days := _now() - int(b["since"])
	var fell := ""
	if float(st["food"]) <= 0.0:
		var g := String(p["garrison"])
		if _ar.has(g):
			_shift(_ar[g], -0.05, -0.01)
		if _h("starve", sid, _now()) < 0.35 or morale(g) < 0.2:
			fell = "starved into surrender"
	elif days >= int(b["patience"]):
		_blk.erase(sid)
		_ev("emergency", sid, [], "blockade_lifted", "%s gives up the blockade of %s" % [b["owner"], _sname(sid)], 4)
		return
	if fell != "":
		var stt: Variant = _mod("settlements")
		if stt != null:
			stt.raid_aftermath(sid, 0.3)
		_blk.erase(sid)
		fall_back(sid)
		stats["fallen"] = int(stats["fallen"]) + 1
		_ev("battle", sid, [], "blockade", "%s fell, %s" % [_sname(sid), fell], 6)


## Weekly: bandit bands test the defended settlements, using exactly the player's rules (choose_attack, resolve_attack).
func _npc_raids(day: int) -> Array:
	var out: Array = []
	var sids := defended_sids()
	if sids.is_empty():
		return out
	for i in mini(sids.size(), 6):
		var sid := int(sids[(i + day) % sids.size()])
		if _h("npc_raid", sid, day) > NPC_RAID_CHANCE or _blk.has(sid):
			continue
		var pw := 30.0 + 220.0 * _h("npc_pw", sid, day)
		var att := {"owner": "bandits:%d" % (day % 97), "power": pw, "men": int(pw / 3.0), "gold": 120.0 * _h("npc_gold", sid, day), "patience": 8 + int(10.0 * _h("npc_pat", sid, day)),
			"scouts": _h("npc_sc", sid, day) < 0.4}
		var cands := [sid]
		var other := int(sids[(i + day + 1) % sids.size()])
		if other != sid:
			cands.append(other)
		var pick := choose_attack(att, cands)
		if int(pick["sid"]) >= 0 and String(pick["method"]) != "skip":
			var r := resolve_attack(att, int(pick["sid"]), String(pick["method"]), {"player_present": false})
			out.append(String(r["text"]))
	return out


# ------------------------------------------------------------------ campaign and siege integration

func bind_campaign(aid: String, camp_id: int) -> bool:
	if not _ar.has(aid):
		return false
	(_ar[aid] as Dictionary)["camp"] = camp_id
	_camp[camp_id] = aid
	return true


func pid_of_campaign(camp_id: int) -> String:
	return String(_camp.get(camp_id, ""))


## Puts the army on the campaign map (strength = its men) and binds the two.
func spawn_campaign(aid: String, node: int) -> int:
	var cm: Variant = _mod("campaign")
	var a: Dictionary = _ar.get(aid, {})
	if cm == null or a.is_empty() or men(aid) <= 0:
		return -1
	var o: Dictionary = officer(aid, String(a["cmd"]))
	var pers: String = {"bold": "aggressive", "careful": "cautious", "loyal": "loyal", "ambitious": "ambitious"}.get(String(o.get("pers", "")), "loyal")
	var cid: int = cm.spawn_army("player" if String(a["owner"]) == "player" else String(a["owner"]), node, men(aid), pers, String(a["name"]))
	bind_campaign(aid, cid)
	return cid


## campaign.gd _side_power multiplier: training, equipment, morale, discipline, officers, wages and rations, relative to an average stack.
func power_mult(camp_id: int) -> float:
	var aid := pid_of_campaign(camp_id)
	if aid == "":
		return 1.0
	var n := men(aid)
	if n <= 0:
		return 1.0
	return clampf(power(aid) / float(n) / 0.63, 0.4, 2.0)


## campaign.gd tells us who fought: entity men follow the campaign's strength, and the fight is written to the event log with ar: ids.
func on_battle(att_ids: Array, def_ids: Array, outcome: String, where: String, weight := 4) -> void:
	var actors: Array = []
	for cid: Variant in att_ids + def_ids:
		var aid := pid_of_campaign(int(cid))
		if aid != "":
			sync_from_campaign(int(cid))
			actors.append(aid)
	if not actors.is_empty():
		Events.log_to(hub, "battle", "", actors, "campaign", "%s: %s" % [where, outcome], weight)


func sync_from_campaign(camp_id: int) -> void:
	var aid := pid_of_campaign(camp_id)
	var cm: Variant = _mod("campaign")
	if aid == "" or cm == null or not cm.has_method("army_info"):
		return
	var info: Dictionary = cm.army_info(camp_id)
	if info.is_empty() or int(info["strength"]) <= 0:
		disband(aid, "destroyed in battle")
		return
	var a: Dictionary = _ar[aid]
	var have := men(aid)
	var strength := int(info["strength"])
	if strength < have and have > 0:
		hurt(aid, 1.0 - float(strength) / float(have), 0.0)
	a["pos"] = [float(info["pos"][0]), float(info["pos"][1])]
	var cm_morale := float(info["morale"])
	for u: Dictionary in a["units"]:
		u["mo"] = clampf((float(u["mo"]) + cm_morale) * 0.5, 0.0, 1.0)


## A siege spec (siege.gd create) built from real armies: the attacker's stacks and the settlement's garrison and stockpile.
func siege_spec(att_aid: String, def_sid: int, base: Dictionary = {}) -> Dictionary:
	var spec := base.duplicate(true)
	var a: Dictionary = _ar.get(att_aid, {})
	var p: Dictionary = _def.get(def_sid, {})
	var units: Array = []
	var eng := 0
	var med := 0
	var guards := 0
	for u: Dictionary in a.get("units", []):
		if int(u["tr_left"]) > 0:
			continue
		units.append({"cid": 0, "name": "%s (%s)" % [String(u["k"]).capitalize(), a["name"]], "kind": String(D.UNITS[String(u["k"])]["siege"]), "men": int(u["n"]),
			"quality": clampf(0.3 + float(u["lvl"]) * 0.1 + float(u["eq"]) * 0.2, 0.2, 0.95), "morale": float(u["mo"]), "fatigue": 0.0})
		if String(u["k"]) == "engineer":
			eng += int(u["n"])
		elif String(u["k"]) == "medic":
			med += int(u["n"])
		else:
			guards += int(u["n"]) / 5
	spec["att_units"] = units
	spec["camp"] = {"men": men(att_aid), "engineers": eng, "medical": med, "guards": guards, "morale": morale(att_aid), "food_days": float(a.get("food", 0.0)) / maxf(1.0, float(men(att_aid)))}
	spec["attacker"] = String(a.get("owner", "player"))
	if not p.is_empty():
		spec["garrison"] = men(String(p["garrison"])) + int(p["patrols"])
		spec["food_days"] = food_days(def_sid)
		spec["morale"] = morale(String(p["garrison"]))
		spec["gates"] = [0.0, PI] if int(p["gates"]) >= 2 else [0.0]
		spec["wall_age"] = 0.7 - 0.2 * float(p["walls"])
	return spec


## After a siege: losses go back onto the armies.
func apply_siege_result(att_aid: String, def_sid: int, siege_state: Dictionary) -> Dictionary:
	var p: Dictionary = _def.get(def_sid, {})
	var g_left := int(siege_state.get("garrison", 0))
	var g_have := men(String(p.get("garrison", ""))) + int(p.get("patrols", 0))
	var d_lost := 0
	if g_have > 0 and g_left < g_have:
		d_lost = hurt(String(p.get("garrison", "")), 1.0 - float(g_left) / float(g_have), 0.1)
	var c_left := int((siege_state.get("camp", {}) as Dictionary).get("men", 0))
	var c_have := men(att_aid)
	var a_lost := 0
	if c_have > 0 and c_left < c_have:
		a_lost = hurt(att_aid, 1.0 - float(c_left) / float(c_have), 0.1)
	var fell := String(siege_state.get("status", "")) in ["fallen", "taken", "surrendered"]
	if fell and not p.is_empty():
		fall_back(def_sid)
	_ev("battle", def_sid, [att_aid, String(p.get("garrison", ""))], "siege", "Siege of %s ends (%s): %d defenders and %d attackers lost" % [_sname(def_sid), String(siege_state.get("status", "?")), d_lost, a_lost], 6)
	return {"defender_lost": d_lost, "attacker_lost": a_lost, "fell": fell}


# ------------------------------------------------------------------ NPC parity

## NPC kingdoms keep a royal army and garrison their towns under the same limits, wages and rations as a player's. Their gold comes from faction wealth.
func npc_seed() -> void:
	if _npc_seeded:
		return
	var f: Variant = _mod("factions")
	if f == null:
		return
	_npc_seeded = true
	for fd: Dictionary in f.factions():
		if String(fd["kind"]) != "nation" or _ar.size() >= 20:
			continue
		var r := found(String(fd["id"]), "royal", "Royal army of %s" % String(fd["name"]), -1, {"npc": true, "purse": 400, "food": 300.0, "mode": "autonomous"})
		if bool(r["ok"]):
			var aid := String(r["id"])
			var n := clampi(int(float(fd["power"]) * 2.0), 30, legal_limit(String(fd["id"]), "royal"))
			add_unit(aid, "spear", int(n * 0.5), {"lvl": 1, "eq": 0.5})
			add_unit(aid, "archer", int(n * 0.3), {"lvl": 1, "eq": 0.5})
			add_unit(aid, "cavalry", int(n * 0.2), {"lvl": 2, "eq": 0.6})
			appoint(aid, {"name": "Marshal of %s" % String(fd["name"])})
			set_standing(aid, {"kind": "defend", "retreat_morale": 0.3})


## An NPC army is paid and fed from its kingdom's wealth with the same wage bill as anyone's; when the kingdom is broke it goes unpaid and deserts.
func _npc_fund(k: String) -> void:
	var a: Dictionary = _ar[k]
	if not bool(a["npc"]):
		return
	var f: Variant = _mod("factions")
	var up := upkeep(k)
	var need := int(up["wages"]) * 7
	if int(a["purse"]) < int(up["wages"]) * 3:
		var fd: Dictionary = f.faction(String(a["owner"])) if f != null else {}
		var cost := float(need - int(a["purse"])) * 0.02
		if not fd.is_empty() and float(fd["wealth"]) > cost:
			f.add_wealth(String(a["owner"]), -cost)
			a["purse"] = need
	if float(a["food"]) < float(men(k)) * 3.0:
		var qty := minf(carry_cap(k) - float(a["food"]), float(men(k)) * 7.0)
		var fd2: Dictionary = f.faction(String(a["owner"])) if f != null else {}
		var cost2 := qty * D.FOOD_PRICE * 0.02
		if not fd2.is_empty() and float(fd2["wealth"]) > cost2:
			f.add_wealth(String(a["owner"]), -cost2)
			a["food"] = float(a["food"]) + qty


# ------------------------------------------------------------------ hub hooks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	var t0 := Time.get_ticks_usec()
	_hours += 1
	for c: Dictionary in _couriers:
		if _hours >= int(c["eta"]) and not bool(c.get("done", false)):
			c["done"] = true
			_deliver(c)
	_couriers = _couriers.filter(func(c: Dictionary) -> bool: return not bool(c.get("done", false)))
	for k: String in _ar:
		_move_hour(_ar[k])
	if not _trains.is_empty():
		_trains_hour()
	if _hours % 3 == 0 and _ar.size() > 1:
		scout_pass()
	_perf["hour"] = Time.get_ticks_usec() - t0
	return []


const CHUNK := 8    # armies per day-tick job: about 0.6 ms (hub PUMP budget), so 64 armies run as eight small jobs


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	if not _npc_seeded:
		npc_seed()
	var parts := maxi(1, int(ceil(float(_ar.size()) / float(CHUNK))))
	var out: Array = []
	for i in parts:
		out.append(func() -> Array: return _chunk_armies(day, i, parts))
	out.append(func() -> Array: return _chunk_defence(day))
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _chunk_armies(day: int, part := 0, parts := 1) -> Array:
	var t0 := Time.get_ticks_usec()
	if part == 0:
		_day = maxi(_day, day)
		_hours = maxi(_hours, day * 24)
		_stance_cache.clear()
		if not _npc_seeded:
			npc_seed()
	var all := ids()
	var lo := part * CHUNK
	var hi := all.size() if part == parts - 1 else mini(all.size(), lo + CHUNK)
	for i in range(lo, hi):
		var k: String = all[i]
		if _ar.has(k):
			_npc_fund(k)
			_army_day(k)
			_standing_step(k)
	if part == parts - 1:
		for sid: int in _levied.keys():
			if _now() >= int((_levied[sid] as Dictionary)["until"]) or not _ar.has(String((_levied[sid] as Dictionary)["aid"])):
				release_levy(sid)
			else:
				_push_levy(sid)      # deserters and the fallen go home to the fields' count
	_perf["day_armies"] = Time.get_ticks_usec() - t0
	return []


func _chunk_defence(day: int) -> Array:
	var t0 := Time.get_ticks_usec()
	_day = maxi(_day, day)
	for sid: int in _def.keys():
		var p: Dictionary = _def[sid]
		var ev: Dictionary = p["evac"]
		if String(ev["state"]) == "evacuating" and _now() - int(ev["day"]) >= 2:
			ev["state"] = "done"
		if int(p["alert"]) > 0 and _h("calm", sid, _now()) < 0.2 and not _blk.has(sid):
			p["alert"] = int(p["alert"]) - 1
	for sid2: int in _blk.keys():
		_blockade_day(sid2)
	_perf["day_defence"] = Time.get_ticks_usec() - t0
	return []


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	for o: String in _susp.keys():
		var p := pressure(o)
		_susp[o] = maxf(p, suspicion(o) - D.SUSPICION_DECAY)
		if suspicion(o) <= 0.0:
			_susp.erase(o)
		_push_suspicion(o)
	return _npc_raids(_now())


## Long absences are resolved with counts, not day by day: wages, rations and desertion in closed form per army.
func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	_day += days
	_hours += days * 24
	for k: String in ids():
		var a: Dictionary = _ar[k]
		var up := upkeep(k)
		var paid_days := mini(days, int(a["purse"]) / maxi(1, int(up["wages"])))
		a["purse"] = int(a["purse"]) - int(up["wages"]) * paid_days
		(a["ledger"] as Dictionary)["wages"] = int((a["ledger"] as Dictionary)["wages"]) + int(up["wages"]) * paid_days
		_note_upkeep(k, a, int(up["wages"]) * paid_days)
		if paid_days < days:
			a["unpaid"] = int(a["unpaid"]) + (days - paid_days)
			_desert(k, minf(0.9, 0.04 * float(maxi(0, int(a["unpaid"]) - D.DESERT_GRACE)) * 0.5 * float(days - paid_days)), "unpaid")
			_shift(a, -0.04 * float(mini(days - paid_days, 8)), -0.02)
		var fed := mini(days, int(float(a["food"]) / maxf(1.0, float(men(k)) * D.RATION)))
		a["food"] = maxf(0.0, float(a["food"]) - float(men(k)) * D.RATION * float(fed))
		if fed < days:
			a["hungry"] = int(a["hungry"]) + days - fed
			_desert(k, minf(0.5, 0.02 * float(days - fed)), "hunger")
		for u: Dictionary in a["units"]:
			u["tr_left"] = maxi(0, int(u["tr_left"]) - days) if int(u["tr_left"]) > 0 else 0
			if int(u["tr_left"]) == 0 and int(u["tr_to"]) > int(u["lvl"]):
				u["lvl"] = int(u["tr_to"])
			if int(u["sp_left"]) > 0:
				u["sp_left"] = maxi(0, int(u["sp_left"]) - days)
				if int(u["sp_left"]) == 0:
					u["spec"] = String(u["sp_to"])
		a["dest"] = []
		if String(a["state"]) == "marching":
			a["state"] = "camped"
	for sid: int in _levied.keys():
		if _now() >= int((_levied[sid] as Dictionary)["until"]):
			release_levy(sid)
	for sid2: int in _blk.keys():
		for i in mini(days, 30):
			if _blk.has(sid2):
				_blockade_day(sid2)
	_couriers.clear()
	_trains.clear()
	return []


func perf() -> Dictionary:
	return _perf.duplicate()


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	return {"ar": _ar.duplicate(true), "u": _next_u, "cou": _couriers.duplicate(true), "ord": _orders.duplicate(true), "tr": _trains.duplicate(true),
		"sight": _sight.duplicate(true), "host": _hostile.keys(), "def": _def.duplicate(true), "blk": _blk.duplicate(true), "lev": _levied.duplicate(true),
		"susp": _susp.duplicate(), "ssid": _ssid.duplicate(true), "recog": _recog.keys(), "hq": _hq.duplicate(true), "camp": _camp.duplicate(), "seq": _seq, "nc": _next_c, "on": _own_n,
		"day": _day, "hours": _hours, "npc": _npc_seeded, "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ar = {}
	_couriers = []
	_orders = []
	_trains = []
	_sight = {}
	_hostile = {}
	_def = {}
	_blk = {}
	_levied = {}
	_susp = {}
	_ssid = {}
	_recog = {}
	_hq = {}
	_camp = {}
	_next_u = int(d.get("u", 1))
	_seq = int(d.get("seq", 1))
	_next_c = int(d.get("nc", 1))
	_own_n = int(d.get("on", 0))
	_day = int(d.get("day", 0))
	_hours = int(d.get("hours", 0))
	_npc_seeded = bool(d.get("npc", false))
	var ar: Dictionary = d.get("ar", {})
	for k: String in ar:
		_ar[k] = _fix_army((ar[k] as Dictionary).duplicate(true))
	for c: Dictionary in d.get("cou", []):
		var cc := c.duplicate(true)
		for f: String in ["c", "sent", "eta", "ack", "seq"]:
			cc[f] = int(cc[f])
		_couriers.append(cc)
	for o: Dictionary in d.get("ord", []):
		var oo := o.duplicate(true)
		for f2: String in ["seq", "sent", "arrives", "ack", "obeyed", "men"]:
			oo[f2] = int(oo[f2])
		_orders.append(oo)
	for t: Dictionary in d.get("tr", []):
		var tt := t.duplicate(true)
		tt["t"] = int(tt["t"])
		tt["gold"] = int(tt["gold"])
		_trains.append(tt)
	var sg: Dictionary = d.get("sight", {})
	for ow: String in sg:
		_sight[ow] = {}
		for k2: String in sg[ow]:
			var e: Dictionary = (sg[ow][k2] as Dictionary).duplicate(true)
			e["n"] = int(e["n"])
			e["seen"] = int(e["seen"])
			_sight[ow][k2] = e
	for h: Variant in d.get("host", []):
		_hostile[String(h)] = true
	var df: Dictionary = d.get("def", {})
	for k3: String in df:
		var p: Dictionary = (df[k3] as Dictionary).duplicate(true)
		for f3: String in ["sid", "patrols", "shifts", "per_shift", "alert", "walls", "gates"]:
			p[f3] = int(p[f3])
		(p["evac"] as Dictionary)["to"] = int((p["evac"] as Dictionary)["to"])
		(p["evac"] as Dictionary)["day"] = int((p["evac"] as Dictionary)["day"])
		_def[int(k3)] = p
	var bl: Dictionary = d.get("blk", {})
	for k4: String in bl:
		var b: Dictionary = (bl[k4] as Dictionary).duplicate(true)
		for f4: String in ["since", "patience", "men"]:
			b[f4] = int(b[f4])
		_blk[int(k4)] = b
	var lv: Dictionary = d.get("lev", {})
	for k5: String in lv:
		var l: Dictionary = (lv[k5] as Dictionary).duplicate(true)
		for f5: String in ["n", "until", "hands"]:
			l[f5] = int(l[f5])
		_levied[int(k5)] = l
	var su: Dictionary = d.get("susp", {})
	for k6: String in su:
		_susp[k6] = float(su[k6])
	var ss: Dictionary = d.get("ssid", {})
	for k9: String in ss:
		var l9: Array = []
		for x9: Variant in ss[k9]:
			l9.append(int(x9))
		_ssid[k9] = l9
	for r: Variant in d.get("recog", []):
		_recog[String(r)] = true
	_hq = (d.get("hq", {}) as Dictionary).duplicate(true)
	var cp: Dictionary = d.get("camp", {})
	for k7: String in cp:
		_camp[int(k7)] = String(cp[k7])
	var st: Dictionary = d.get("stats", {})
	for k8: String in stats:
		stats[k8] = int(st.get(k8, stats[k8]))
	# the farm labour factor is derived state: re-push it after a load
	for ow: String in _susp:
		_push_suspicion(ow)
	var fm: Variant = _mod("farming")
	if fm != null and fm.has_method("clear_levy"):
		fm.clear_levy()
	for sid: int in _levied:
		_push_levy(sid)


func _fix_army(a: Dictionary) -> Dictionary:
	for f: String in ["sid", "purse", "wagons", "unpaid", "hungry", "order_day", "camp", "day", "contracted", "deserted"]:
		a[f] = int(a[f])
	for f2: String in ["food"]:
		a[f2] = float(a[f2])
	for k: String in ["wages", "food", "train", "days"]:
		(a["ledger"] as Dictionary)[k] = int((a["ledger"] as Dictionary)[k])
	for u: Dictionary in a["units"]:
		for f3: String in ["u", "n", "lvl", "tr_left", "tr_to", "sp_left", "real"]:
			u[f3] = int(u[f3])
		var cts: Array = []
		for c: Variant in u["cts"]:
			cts.append(String(c))
		u["cts"] = cts
	for oid: String in a["offs"]:
		var o: Dictionary = a["offs"][oid]
		var us: Array = []
		for x: Variant in o["units"]:
			us.append(int(x))
		o["units"] = us
	return a
