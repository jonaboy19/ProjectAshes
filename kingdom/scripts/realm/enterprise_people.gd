extends "res://scripts/realm/enterprise_core.gd"
## Enterprise, part 2: clan renown/influence and party size, troops and recruit pools (relation gated,
## refilled daily), mercenary contracts, vassalage, army duties, fiefs (taxes, projects built over days
## by a real crew, garrison, governor, prosperity/security, territory memory) and road works.
## Fiefs sit on lordship.gd (treasury, tax rate, infra, militia) and land.gd (deeds, loyalty, memory);
## this adds the decisions around them. Nothing here ticks lordship.gd: Life already does that.

const LordshipScript := preload("res://scripts/sim/lordship.gd")
const CampsScript := preload("res://scripts/realm/camps.gd")

var clan: Dictionary = {"name": "Ashen Company", "renown": 0.0, "influence": 0.0}
var troops: Dictionary = {}                # type -> count following the player
var recruit_state: Dictionary = {}         # "sid" -> {pool: {type: n}, day}
var merc: Dictionary = {}                  # the active mercenary contract ({} = none)
var liege := ""                            # faction the player swore to ("" = free)
var vassal_day := -1
var duty: Dictionary = {}                  # the active army duty
var duties_done := 0
var fiefx: Dictionary = {}                 # "sid" -> {governor, built, prosperity, garrison, share}
var works: Array = []                      # building projects and road works in progress
var _next_work := 1
var _msgs: Array = []


func _say(text: String) -> void:
	_msgs.append(text)
	_note(text)


func _flush() -> Array:
	var out := _msgs
	_msgs = []
	return out


func _land() -> RefCounted:
	return _m("land")


func _fo() -> RefCounted:
	return _m("followers")


func _lord() -> RefCounted:
	if lordship_ref != null:
		return lordship_ref
	var l: Variant = _au_get("Life", "lordship")
	return l if l is RefCounted else null


# ---------------------------------------------------------------- clan

func clan_tier() -> int:
	var t := 0
	for i in D.CLAN_TIERS.size():
		if float(clan["renown"]) >= float((D.CLAN_TIERS[i] as Dictionary)["renown"]):
			t = i
	return t


func add_renown(amount: float, why := "") -> void:
	var before := clan_tier()
	clan["renown"] = maxf(0.0, float(clan["renown"]) + amount)
	if clan_tier() > before:
		_say("Your name carries further: %s (%s)." % [String((D.CLAN_TIERS[clan_tier()] as Dictionary)["name"]), why if why != "" else "renown"])


func add_influence(amount: float) -> void:
	clan["influence"] = maxf(0.0, float(clan["influence"]) + amount)


func spend_influence(amount: float) -> bool:
	if float(clan["influence"]) < amount:
		return false
	clan["influence"] = float(clan["influence"]) - amount
	return true


func party_limit() -> int:
	return D.PARTY_BASE + D.PARTY_PER_TIER * clan_tier() + D.PARTY_PER_FIEF * fief_ids().size()


func companions() -> int:
	var fo := _fo()
	return (fo.call("party") as Array).size() if fo != null else 0


func party_size() -> int:
	return troop_count() + companions()


func clan_info() -> Dictionary:
	var t := clan_tier()
	var nxt: Dictionary = D.CLAN_TIERS[t + 1] if t + 1 < D.CLAN_TIERS.size() else {}
	return {"name": clan["name"], "tier": t, "tier_name": (D.CLAN_TIERS[t] as Dictionary)["name"], "text": (D.CLAN_TIERS[t] as Dictionary)["text"],
		"renown": float(clan["renown"]), "influence": float(clan["influence"]), "next_name": nxt.get("name", ""), "next_renown": float(nxt.get("renown", 0.0)),
		"party_limit": party_limit(), "party_size": party_size(), "liege": liege}


# ---------------------------------------------------------------- troops and recruit pools

func troop_count() -> int:
	var n := 0
	for t: String in troops:
		n += int(troops[t])
	return n


static func troop_power(d: Dictionary) -> float:
	var p := 0.0
	for t: String in d:
		p += float(int(d[t])) * float((D.TROOPS.get(t, {}) as Dictionary).get("power", 1.0))
	return p


func troop_wages() -> int:
	var w := 0
	for t: String in troops:
		w += int(troops[t]) * int((D.TROOPS.get(t, {}) as Dictionary).get("wage", 1))
	return w


## Standing of the player in a settlement: land.gd's loyalty of the place, your fief's own loyalty,
## plus what you earned there by trading, helping and serving.
func standing(sid: int) -> float:
	var base := 40.0
	if is_fief(sid):
		var v := _village(sid)
		base = float(v.get("loyalty", 50.0))
	else:
		var la := _land()
		if la != null:
			base = float(la.call("loyalty", sid)) * 0.6 + 20.0
	return clampf(base + float(rep_delta.get(str(sid), 0.0)), 0.0, 100.0)


func add_standing(sid: int, delta: float) -> void:
	rep_delta[str(sid)] = clampf(float(rep_delta.get(str(sid), 0.0)) + delta, -40.0, 40.0)


func _has_barracks(sid: int) -> bool:
	var st := _st()
	if st == null:
		return false
	var d: Dictionary = st.get("_s").get(sid, {})
	return int((d.get("structures", {}) as Dictionary).get("barracks", 0)) > 0 or int(_fx(sid)["built"].get("barracks", 0)) > 0


func recruit_max(sid: int, type: String) -> int:
	var pop := pop_of(sid)
	var kind := _skind(sid)
	var n := 0
	match type:
		"levy":
			n = clampi(pop / 25, 2, 45)
		"footman":
			n = pop / (200 if kind == "village" else (60 if kind in ["castle", "frontier_town"] else 70))
		"archer":
			n = pop / (120 if kind == "village" else (50 if kind == "frontier_town" else (150 if kind == "castle" else 110)))
		"man_at_arms":
			if kind == "castle":
				n = pop / 110
			elif _has_barracks(sid) and kind in ["town", "frontier_town"]:
				n = pop / 200
	if _has_barracks(sid):
		n = int(ceil(float(n) * 1.5))
	var f := 0.4 + 0.6 * standing(sid) / 100.0
	return int(floor(float(n) * f + 0.5))


## The daily-refilled pool of a settlement. Refill is lazy: elapsed days since the last look
## are applied on access, so nothing has to tick every pool every day.
func recruit_pool(sid: int) -> Dictionary:
	var key := str(sid)
	var e: Dictionary = recruit_state.get(key, {})
	if e.is_empty():
		var pool := {}
		for t: String in D.TROOP_ORDER:
			pool[t] = int(ceil(float(recruit_max(sid, t)) * 0.7))
		e = {"pool": pool, "day": _day}
		recruit_state[key] = e
		return pool
	var dd := _day - int(e["day"])
	if dd > 0:
		var pool2: Dictionary = e["pool"]
		for t: String in D.TROOP_ORDER:
			var mx := recruit_max(sid, t)
			var cur := int(pool2.get(t, 0))
			if cur < mx:
				pool2[t] = mini(mx, cur + int(ceil(float(mx) * 0.15)) * dd)
			elif cur > mx:
				pool2[t] = mx
		e["day"] = _day
	return e["pool"]


func recruit_cost(sid: int, type: String) -> int:
	var base := float((D.TROOPS[type] as Dictionary)["cost"])
	var f := 1.3 - standing(sid) / 200.0
	if is_fief(sid):
		f *= 0.8
	return maxi(1, int(round(base * f)))


func can_recruit(sid: int, type: String, n := 1) -> String:
	var why := can("recruit")
	if why != "":
		return why
	if not D.TROOPS.has(type):
		return "No such troop."
	if not at_settlement(sid):
		return "You must be in %s to raise men." % _sname(sid)
	var need := float((D.TROOPS[type] as Dictionary)["standing"])
	if has_role("soldier"):
		need -= 10.0
	if is_fief(sid):
		need -= 8.0
	if standing(sid) < need:
		return "%s does not trust you enough (standing %d, needs %d)." % [_sname(sid), int(standing(sid)), int(ceil(need))]
	if int(recruit_pool(sid).get(type, 0)) < n:
		return "Not enough %s volunteers left (%d)." % [String((D.TROOPS[type] as Dictionary)["name"]).to_lower(), int(recruit_pool(sid).get(type, 0))]
	if party_size() + n > party_limit():
		return "Your party is at its limit (%d). Earn renown or hold more land." % party_limit()
	if gold() < recruit_cost(sid, type) * n:
		return "You need %d gold." % (recruit_cost(sid, type) * n)
	return ""


func recruit(sid: int, type: String, n := 1) -> Dictionary:
	var why := can_recruit(sid, type, n)
	if why != "":
		return {"ok": false, "reason": why, "n": 0, "paid": 0}
	var cost := recruit_cost(sid, type) * n
	_pay(cost)
	var pool := recruit_pool(sid)
	pool[type] = int(pool[type]) - n
	troops[type] = int(troops.get(type, 0)) + n
	var st := _st()
	if st != null and pop_of(sid) > 150:
		st.call("add_residents", sid, "farmer", -n)
	if is_fief(sid):
		var v := _village(sid)
		v["loyalty"] = clampf(float(v["loyalty"]) - 0.25 * float(n), 0.0, 100.0)
	return {"ok": true, "reason": "", "n": n, "paid": cost}


func dismiss(type: String, n: int) -> int:
	var k := mini(n, int(troops.get(type, 0)))
	if k <= 0:
		return 0
	troops[type] = int(troops[type]) - k
	if int(troops[type]) <= 0:
		troops.erase(type)
	return k


# ---------------------------------------------------------------- mercenaries, vassalage, duties

func has_merc_contract() -> bool:
	return not merc.is_empty()


func _nation_ids() -> Array:
	var fa := _m("factions")
	var out: Array = []
	if fa == null:
		return out
	for f: Dictionary in fa.call("factions"):
		if String(f["kind"]) in ["nation", "house"]:
			out.append(f)
	return out


func merc_offers() -> Array:
	var out: Array = []
	var fl := _nation_ids()
	if fl.is_empty():
		return out
	var week := _day / 7
	var r := _rng("merc", week, 0)
	for i in 3:
		var f: Dictionary = fl[r.randi() % fl.size()]
		var mn := 6 + r.randi() % 10
		var rate := snappedf(r.randf_range(1.6, 3.2), 0.1)
		var days: int = [7, 10, 14][i]
		out.append({"id": "m%d_%d" % [week, i], "faction": String(f["id"]), "name": String(f["name"]), "min_troops": mn, "rate": rate,
			"days": days, "bonus": int(rate * mn * days * 0.15)})
	return out


func accept_merc(offer_id: String) -> Dictionary:
	var why := can("mercenary")
	if why != "":
		return {"ok": false, "reason": why}
	if has_merc_contract():
		return {"ok": false, "reason": "You are already under contract."}
	for o: Dictionary in merc_offers():
		if String(o["id"]) == offer_id:
			if troop_count() < int(o["min_troops"]):
				return {"ok": false, "reason": "%s wants at least %d troops under your banner." % [o["name"], o["min_troops"]]}
			if liege != "" and liege != String(o["faction"]):
				return {"ok": false, "reason": "You are sworn to another lord."}
			merc = {"faction": o["faction"], "name": o["name"], "min": o["min_troops"], "rate": o["rate"], "days_left": o["days"], "days": o["days"],
				"bonus": o["bonus"], "earned": 0, "breach": 0}
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "That offer has lapsed."}


func break_merc() -> void:
	if merc.is_empty():
		return
	var fa := _m("factions")
	if fa != null:
		fa.call("change_relation", "player", String(merc["faction"]), "trust", -5.0)
	add_renown(-2.0, "broken contract")
	_say("You broke your contract with %s; word travels." % String(merc["name"]))
	merc = {}


func swear_vassal(faction_id: String) -> Dictionary:
	var why := can("vassal")
	if why != "":
		return {"ok": false, "reason": why}
	var fa := _m("factions")
	if liege != "":
		return {"ok": false, "reason": "You already serve %s." % liege}
	if fa == null or (fa.call("faction", faction_id) as Dictionary).is_empty():
		return {"ok": false, "reason": "No such lord."}
	if not spend_influence(10.0) and float(clan["influence"]) > 0.0:
		return {"ok": false, "reason": "You lack the influence (10) to be heard."}
	liege = faction_id
	vassal_day = _day
	fa.call("change_relation", "player", faction_id, "trust", 8.0)
	_say("You swear your oath to %s." % String((fa.call("faction", faction_id) as Dictionary)["name"]))
	return {"ok": true, "reason": ""}


func renounce_vassal() -> void:
	if liege == "":
		return
	var fa := _m("factions")
	if fa != null:
		fa.call("change_relation", "player", liege, "trust", -15.0)
	for sid: int in fief_ids():
		var v := _village(sid)
		v["loyalty"] = clampf(float(v["loyalty"]) - 4.0, 0.0, 100.0)
	add_renown(-3.0, "oathbreaking")
	_say("You broke your oath to %s." % liege)
	liege = ""
	vassal_day = -1


func duty_board(sid: int) -> Array:
	var out: Array = []
	var r := _rng("duty", _day, sid)
	for k: String in D.DUTIES:
		var def: Dictionary = D.DUTIES[k]
		out.append({"kind": k, "name": def["name"], "days": def["days"], "pay": int(def["pay"]) + r.randi() % 4, "text": def["text"], "sid": sid})
	return out


func take_duty(kind: String, sid: int) -> Dictionary:
	var why := can("duty")
	if why != "":
		return {"ok": false, "reason": why}
	if not duty.is_empty():
		return {"ok": false, "reason": "You are already on duty."}
	for o: Dictionary in duty_board(sid):
		if String(o["kind"]) == kind:
			var edge: Array = []
			if kind == "patrol":
				var nb := neighbours(sid, 99.0)
				if not nb.is_empty():
					var t := int((nb[0] as Dictionary)["sid"])
					var cm := _camps()
					var path: Array = cm.call("route", sid, t)
					if path.size() >= 2:
						edge = [path[0], path[1]]
						cm.call("set_guarded", path[0], path[1], true)
			duty = {"kind": kind, "sid": sid, "days_left": int(o["days"]), "pay": int(o["pay"]), "edge": edge, "renown": float(D.DUTIES[kind]["renown"])}
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "No such duty."}


func is_soldier() -> bool:
	return has_role("soldier") or has_role("mercenary")


func _duty_day() -> void:
	if duty.is_empty():
		return
	_earn(int(duty["pay"]))
	add_renown(float(duty["renown"]), "duty")
	duty["days_left"] = int(duty["days_left"]) - 1
	if int(duty["days_left"]) <= 0:
		var sid := int(duty["sid"])
		match String(duty["kind"]):
			"drill":
				var pool := recruit_pool(sid)
				pool["levy"] = int(pool.get("levy", 0)) + 6
			"patrol":
				var e: Array = duty["edge"]
				if e.size() == 2 and _camps() != null:
					_camps().call("set_guarded", e[0], e[1], false)
		add_standing(sid, 6.0)
		duties_done += 1
		_say("Duty done: %s." % String(D.DUTIES[String(duty["kind"])]["name"]))
		duty = {}


func _people_day() -> void:
	# wages: a company that goes unpaid melts away
	var w := troop_wages()
	if w > 0:
		if gold() < w:
			var lost := 0
			for t: String in troops.keys():
				var k := maxi(1, int(ceil(float(int(troops[t])) * 0.1)))
				lost += dismiss(t, k)
			_say("Unpaid wages: %d of your troops have deserted." % lost)
		else:
			_pay(w)
	# mercenary contract
	if not merc.is_empty():
		var have := troop_count()
		if have >= int(merc["min"]):
			var pay := int(round(float(merc["rate"]) * float(mini(have, int(merc["min"]) * 2))))
			_earn(pay)
			merc["earned"] = int(merc["earned"]) + pay
			merc["breach"] = 0
		else:
			merc["breach"] = int(merc["breach"]) + 1
		merc["days_left"] = int(merc["days_left"]) - 1
		if int(merc["breach"]) >= 3:
			_say("%s voids your contract: too few men." % String(merc["name"]))
			break_merc()
		elif int(merc["days_left"]) <= 0:
			_earn(int(merc["bonus"]))
			var fa := _m("factions")
			if fa != null:
				fa.call("change_relation", "player", String(merc["faction"]), "trust", 6.0)
			add_renown(4.0, "contract")
			add_influence(2.0)
			_say("Contract with %s ends: %d gold earned and a bonus of %d." % [String(merc["name"]), int(merc["earned"]), int(merc["bonus"])])
			merc = {}
	# vassal tithe and benefits, weekly
	if liege != "" and _day % 7 == 0:
		var tithe := 10 + 6 * fief_ids().size() + int(float(troop_count()) * 0.3)
		_pay(tithe)
		add_influence(1.0)
		add_renown(1.0, "service")
	_duty_day()
	# influence trickles in from land and standing
	add_influence(0.05 * float(fief_ids().size()) + 0.02 * float(clan_tier()))


# ---------------------------------------------------------------- fiefs

func _fx(sid: int) -> Dictionary:
	var k := str(sid)
	if not fiefx.has(k):
		fiefx[k] = {"governor": "", "built": {}, "prosperity": 50.0, "garrison": {}, "share": 0, "last_tax": 0}
	return fiefx[k]


func _village(sid: int) -> Dictionary:
	var l := _lord()
	return l.call("village", sid) if l != null else {}


## Settlements the player holds: lordship.gd villages plus land.gd deeds in the player's name.
func fief_ids() -> Array:
	var ids := {}
	var l := _lord()
	if l != null:
		for s: Variant in l.call("held_settlements"):
			ids[int(s)] = true
	var la := _land()
	if la != null:
		for s: Dictionary in WorldGen.settlements:
			var sid := int(s["id"])
			if String((la.call("deed", sid) as Dictionary).get("holder", "")) == "player":
				ids[sid] = true
	var out := ids.keys()
	out.sort()
	return out


func is_fief(sid: int) -> bool:
	return fief_ids().has(sid)


func is_lord() -> bool:
	return not fief_ids().is_empty()


## A deed in the player's name gets a village record (treasury, tax, militia) if it has none.
func ensure_fief(sid: int) -> bool:
	var l := _lord()
	if l == null:
		return false
	if not (l.call("village", sid) as Dictionary).is_empty():
		return true
	var la := _land()
	if la != null and String((la.call("deed", sid) as Dictionary).get("holder", "")) == "player":
		l.call("grant", sid, "purchase")
		return true
	return false


func fief_price(sid: int) -> int:
	var mult: float = float(D.SETTLEMENT_MULT.get(_skind(sid), 1.0))
	return int(round(float(pop_of(sid)) * 6.0 * mult / 10.0) * 10.0) + 400


func can_buy_fief(sid: int) -> String:
	var la := _land()
	if la == null:
		return "No land records."
	var d: Dictionary = la.call("deed", sid)
	if d.is_empty():
		return "No such estate."
	if String(d["holder"]) == "player":
		return "You already hold it."
	if String(d["holder"]) in ["crown", "church"]:
		return "The %s does not sell its towns." % String(d["holder"])
	if clan_tier() < 2:
		return "Only a recognised Clan may hold an estate (renown 140)."
	if gold() < fief_price(sid):
		return "You need %d gold." % fief_price(sid)
	return ""


func buy_fief(sid: int) -> Dictionary:
	var why := can_buy_fief(sid)
	if why != "":
		return {"ok": false, "reason": why}
	var la := _land()
	_pay(fief_price(sid))
	la.call("purchase", sid, "player", fief_price(sid), _day)
	ensure_fief(sid)
	add_renown(6.0, "a landed name")
	return {"ok": true, "reason": ""}


func governor_of(sid: int) -> Dictionary:
	var fid := String(_fx(sid)["governor"])
	var fo := _fo()
	if fid == "" or fo == null:
		return {}
	var f: Dictionary = fo.call("get_follower", fid)
	if f.is_empty() or String(f["status"]) not in ["present", "traveling"]:
		return {}
	return f


func set_governor(sid: int, fid: String) -> Dictionary:
	var why := can("fief")
	if why != "" or not is_fief(sid):
		return {"ok": false, "reason": why if why != "" else "That is not your fief."}
	var fo := _fo()
	var f: Dictionary = fo.call("get_follower", fid) if fo != null else {}
	if f.is_empty() or String(f["status"]) not in ["present", "traveling"]:
		return {"ok": false, "reason": "They are not in your party."}
	if String(f["post"]) != "" and not String(f["post"]).begins_with("governor:"):
		return {"ok": false, "reason": "%s is already posted (%s)." % [f["name"], f["post"]]}
	var old := String(_fx(sid)["governor"])
	if old != "" and fo != null:
		fo.call("assign_post", old, "")
	_fx(sid)["governor"] = fid
	fo.call("assign_post", fid, "governor:%d" % sid)
	f["loc"] = "s%d" % sid
	return {"ok": true, "reason": ""}


func clear_governor(sid: int) -> void:
	var fid := String(_fx(sid)["governor"])
	if fid != "" and _fo() != null:
		_fo().call("assign_post", fid, "")
	_fx(sid)["governor"] = ""


func governor_efficiency(sid: int) -> float:
	var g := governor_of(sid)
	if g.is_empty():
		return 0.0
	var e := 0.06 + 0.14 * clampf(float(g["loyalty"]) / 100.0, 0.0, 1.0)
	if "honorable" in g["traits"] or "greedy" in g["traits"]:
		e += 0.04
	return e


func garrison_of(sid: int) -> Dictionary:
	return _fx(sid)["garrison"]


func garrison_assign(sid: int, type: String, n: int) -> int:
	if not is_fief(sid):
		return 0
	var k := mini(n, int(troops.get(type, 0)))
	if k <= 0:
		return 0
	troops[type] = int(troops[type]) - k
	if int(troops[type]) <= 0:
		troops.erase(type)
	var g := garrison_of(sid)
	g[type] = int(g.get(type, 0)) + k
	return k


func garrison_recall(sid: int, type: String, n: int) -> int:
	var g := garrison_of(sid)
	var k := mini(n, int(g.get(type, 0)))
	if k <= 0 or party_size() + k > party_limit():
		return 0
	g[type] = int(g[type]) - k
	if int(g[type]) <= 0:
		g.erase(type)
	troops[type] = int(troops.get(type, 0)) + k
	return k


func security_of(sid: int) -> float:
	var v := _village(sid)
	if v.is_empty():
		return 0.0
	var pop := float(pop_of(sid))
	var fx := _fx(sid)
	var garr := float(v["militia"]) + troop_power(fx["garrison"])
	var s := 20.0 + clampf(garr * 3.0 / (pop / 100.0 + 1.0), 0.0, 40.0)
	s += float((v["infra"] as Dictionary).get("walls", 0.0)) * 14.0
	s += 5.0 * float(fx["built"].get("walls", 0)) + 4.0 * float(fx["built"].get("barracks", 0))
	if not governor_of(sid).is_empty():
		s += 8.0
	if liege != "":
		s += 6.0
	var sh := _sh()
	if sh != null:
		var hit := 0
		for rs: Dictionary in sh.call("recent_raid_results"):
			if bool(rs["success"]) and (rs["pos"] as Vector2).distance_to(_spos(sid)) < 600.0:
				hit += 1
		s -= float(mini(hit, 4)) * 4.0
	return clampf(s, 0.0, 100.0)


func _trade_level(sid: int) -> float:
	var st := _st()
	if st == null:
		return 0.5
	return float((st.get("_s").get(sid, {}) as Dictionary).get("trade", 0.5))


func prosperity_target(sid: int) -> float:
	var v := _village(sid)
	if v.is_empty():
		return 50.0
	var fx := _fx(sid)
	var infra: Dictionary = v["infra"]
	var avg := 0.0
	for k: String in infra:
		avg += float(infra[k])
	avg /= maxf(float(infra.size()), 1.0)
	var pop := float(maxi(pop_of(sid), 1))
	var food := clampf(float(v["food"]) / (pop * 0.2), 0.0, 1.0)
	var t := 22.0 + 18.0 * food + 14.0 * avg
	t += 7.0 * float(mini(1, int(fx["built"].get("market", 0)))) + 5.0 * float(mini(1, int(fx["built"].get("warehouse", 0)))) + 4.0 * float(mini(1, int(fx["built"].get("granary", 0))))
	t += 0.12 * (float(v["loyalty"]) - 50.0) + 0.10 * (security_of(sid) - 50.0) + 6.0 * _trade_level(sid)
	return clampf(t, 0.0, 100.0)


func fief_income(sid: int) -> Dictionary:
	var v := _village(sid)
	if v.is_empty():
		return {"tax": 0, "share": 0, "wages": 0, "crew": 0, "net": 0}
	var rate: Dictionary = LordshipScript.TAX_RATES[String(v["tax_rate"])]
	var tax := int(round(float(v["population"]) * LordshipScript.BASE_TAX_PER_POP * float(rate["mult"])))
	var share := _production_share(sid)
	var wages := int(v["militia"]) * LordshipScript.MILITIA_WAGE
	for t: String in garrison_of(sid):
		wages += int(garrison_of(sid)[t]) * int((D.TROOPS[t] as Dictionary)["wage"])
	var crew := 0
	for w: Dictionary in works:
		if int(w["sid"]) == sid and String(w["kind"]) == "project":
			crew += int(w["crew"]) * D.CREW_WAGE
	return {"tax": tax, "share": share, "wages": wages, "crew": crew, "net": tax + share - wages - crew}


## The lord's cut of what the fief's farms, mills and workshops make in a day.
func _production_share(sid: int) -> int:
	var prod := production_of(sid)
	var value := 0.0
	for g: String in prod:
		value += float(prod[g]) * float((D.GOODS[g] as Dictionary)["base"])
	var fx := _fx(sid)
	var cut := 0.06 * (1.0 + governor_efficiency(sid)) * (1.0 + 0.4 * float(mini(1, int(fx["built"].get("market", 0)))))
	return int(round(value * cut))


func fief_info(sid: int) -> Dictionary:
	ensure_fief(sid)
	var v := _village(sid)
	if v.is_empty():
		return {}
	var fx := _fx(sid)
	var g := governor_of(sid)
	var la := _land()
	return {"sid": sid, "name": _sname(sid), "pop": pop_of(sid), "treasury": int(v["treasury"]), "tax_rate": String(v["tax_rate"]),
		"loyalty": float(v["loyalty"]), "prosperity": float(fx["prosperity"]), "security": security_of(sid), "food": float(v["food"]),
		"infra": (v["infra"] as Dictionary).duplicate(), "militia": int(v["militia"]), "garrison": garrison_of(sid).duplicate(),
		"governor": {"fid": String(fx["governor"]), "name": String(g.get("name", ""))} if not g.is_empty() else {},
		"income": fief_income(sid), "built": (fx["built"] as Dictionary).duplicate(), "projects": works.filter(func(w: Dictionary) -> bool: return int(w["sid"]) == sid),
		"memory": la.call("memories", sid) if la != null else [], "issues": (v["issues"] as Array).size(), "liege": liege}


func set_tax(sid: int, rate: String) -> String:
	var why := can("fief")
	if why != "":
		return why
	ensure_fief(sid)
	var l := _lord()
	return String(l.call("set_tax_rate", sid, rate)) if l != null else "No lordship."


func treasury_withdraw(sid: int, amount: int) -> int:
	var v := _village(sid)
	if v.is_empty():
		return 0
	var a := clampi(amount, 0, int(v["treasury"]))
	v["treasury"] = int(v["treasury"]) - a
	_earn(a)
	return a


func treasury_deposit(sid: int, amount: int) -> int:
	var v := _village(sid)
	if v.is_empty():
		return 0
	var a := clampi(amount, 0, maxi(0, gold()))
	_pay(a)
	v["treasury"] = int(v["treasury"]) + a
	return a


# ---------------------------------------------------------------- works: projects and roads

func _construction() -> RefCounted:
	return hub.mod("construction") if hub != null else null


## Builders hired for the player's own sites come out of the same labour pool as fief crews.
func _labour_other(sid: int) -> int:
	var c := _construction()
	return int(c.call("labour_taken", sid)) if c != null else 0


func labour_pool(sid: int) -> int:
	return maxi(2, pop_of(sid) / 30)


func labour_used(sid: int) -> int:
	var n := 0
	for w: Dictionary in works:
		if int(w["sid"]) == sid:
			n += int(w["crew"])
	return n + _labour_other(sid)


func labour_free(sid: int) -> int:
	return maxi(0, labour_pool(sid) - labour_used(sid))


func can_start_project(sid: int, kind: String) -> String:
	var why := can("fief")
	if why != "":
		return why
	if not is_fief(sid):
		return "That is not your fief."
	if not D.PROJECTS.has(kind):
		return "No such project."
	ensure_fief(sid)
	var fx := _fx(sid)
	var have := int(fx["built"].get(kind, 0))
	var limit := 2 if kind == "walls" else (99 if kind == "roads" else 1)
	if have >= limit:
		return "Already built."
	for w: Dictionary in works:
		if int(w["sid"]) == sid and String(w["key"]) == kind:
			return "Already under construction."
	var v := _village(sid)
	var cost := int((D.PROJECTS[kind] as Dictionary)["gold"])
	if int(v["treasury"]) < cost:
		return "The treasury holds %d; it needs %d." % [int(v["treasury"]), cost]
	if labour_free(sid) < 1:
		return "No free hands: every labourer is already at work."
	return ""


func start_project(sid: int, kind: String, crew := 6) -> Dictionary:
	var why := can_start_project(sid, kind)
	if why != "":
		return {"ok": false, "reason": why}
	var v := _village(sid)
	var def: Dictionary = D.PROJECTS[kind]
	v["treasury"] = int(v["treasury"]) - int(def["gold"])
	var c := clampi(crew, 1, mini(D.CREW_MAX, labour_free(sid)))
	var w := {"id": _next_work, "kind": "project", "key": kind, "sid": sid, "label": String(def["label"]), "left": float(def["work"]), "total": float(def["work"]),
		"crew": c, "start": _day}
	_next_work += 1
	works.append(w)
	return {"ok": true, "reason": "", "id": int(w["id"]), "crew": c}


func set_crew(work_id: int, crew: int) -> void:
	for w: Dictionary in works:
		if int(w["id"]) == work_id:
			var others := labour_used(int(w["sid"])) - int(w["crew"])
			w["crew"] = clampi(crew, 1, maxi(1, mini(D.CREW_MAX, labour_pool(int(w["sid"])) - others)))


## The player lends a hand for a shift (quality 0..1): real labour on a real site.
func help_build(work_id: int, quality := 0.7) -> Dictionary:
	for w: Dictionary in works:
		if int(w["id"]) == work_id:
			w["left"] = maxf(0.0, float(w["left"]) - 5.0 * clampf(quality, 0.0, 1.0))
			add_standing(int(w["sid"]), 0.8)
			if is_fief(int(w["sid"])):
				var la := _land()
				if la != null:
					la.call("adjust_loyalty", int(w["sid"]), 0.4)
			return {"ok": true, "left": float(w["left"])}
	return {"ok": false, "left": 0.0}


func _works_day() -> void:
	var l := _lord()
	var i := works.size() - 1
	while i >= 0:
		var w: Dictionary = works[i]
		var sid := int(w["sid"])
		var eff := 1.0
		var paid := true
		if String(w["kind"]) == "project":
			eff += governor_efficiency(sid) + 0.1 * (float(_fx(sid)["prosperity"]) - 50.0) / 50.0
			var wage := int(w["crew"]) * D.CREW_WAGE
			var v := _village(sid)
			if v.is_empty() or int(v["treasury"]) < wage:
				paid = false
			else:
				v["treasury"] = int(v["treasury"]) - wage
		else:
			var wage2 := int(w["crew"]) * D.CREW_WAGE
			if gold() < wage2:
				paid = false
			else:
				_pay(wage2)
		# One labour model for every crew (scripts/realm/construction.gd): skilled crews finish sooner.
		var cons := _construction()
		var man_days := float(w["crew"]) if cons == null else float(cons.call("crew_output", int(w["crew"])))
		w["left"] = float(w["left"]) - man_days * eff * (1.0 if paid else 0.4)
		if float(w["left"]) <= 0.0:
			works.remove_at(i)
			_complete_work(w, l)
		i -= 1


func _complete_work(w: Dictionary, _l: RefCounted) -> void:
	var sid := int(w["sid"])
	var st := _st()
	if String(w["kind"]) == "road":
		var cm := _camps()
		if cm != null:
			cm.call("build_road", String(w["a"]), String(w["b"]), String(w["level"]))
		invalidate_routes()
		add_standing(int(String(w["a"]).substr(1)), 3.0)
		add_standing(int(String(w["b"]).substr(1)), 3.0)
		add_renown(1.0, "road builder")
		_say("The %s between %s and %s is finished." % [String(w["level"]), _sname(int(String(w["a"]).substr(1))), _sname(int(String(w["b"]).substr(1)))])
		return
	var key := String(w["key"])
	var fx := _fx(sid)
	var v := _village(sid)
	fx["built"][key] = int(fx["built"].get(key, 0)) + 1
	var cons_done := _construction()
	if cons_done != null:
		cons_done.call("on_fief_complete", sid, key)
	match key:
		"market":
			if st != null:
				st.call("add_structure", sid, "market")
				st.call("set_trade", sid, _trade_level(sid) + 0.25)
		"granary":
			v["infra"]["granary"] = 1.0
			v["food"] = float(v["food"]) + 30.0
		"walls":
			v["infra"]["walls"] = 1.0
			if st != null:
				st.call("add_structure", sid, "wall")
		"roads":
			v["infra"]["roads"] = 1.0
			var cm2 := _camps()
			if cm2 != null:
				for e: Dictionary in cm2.call("edges"):
					if e["a"] == "s%d" % sid or e["b"] == "s%d" % sid:
						cm2.call("maintain_road", e["a"], e["b"], 2.0)
			invalidate_routes()
		"mill":
			if st != null:
				st.call("add_structure", sid, "mill")
		"barracks":
			if st != null:
				st.call("add_structure", sid, "barracks")
		"warehouse":
			if st != null:
				st.call("add_structure", sid, "warehouse")
				st.call("set_trade", sid, _trade_level(sid) + 0.15)
	v["loyalty"] = clampf(float(v["loyalty"]) + 3.0, 0.0, 100.0)
	var la := _land()
	if la != null:
		la.call("remember", sid, "relief", 0.3, _day)
	add_renown(2.0, "works")
	_say("%s: the %s is finished." % [_sname(sid), String(w["label"]).to_lower()])


# ---------------------------------------------------------------- roads

func road_cost(a: int, b: int, level: String) -> int:
	var len_m := _spos(a).distance_to(_spos(b))
	var cm := _camps()
	var e: Dictionary = cm.call("road", a, b) if cm != null else {}
	var c := len_m * float(D.ROAD_COST_PER_M.get(level, 0.3))
	if e.is_empty():
		c *= 1.3
	return int(round(c / 5.0) * 5.0)


func can_plan_road(a: int, b: int, level: String) -> String:
	var why := can("road_works")
	if why != "":
		return why
	var cm := _camps()
	if cm == null or a == b or not D.ROAD_COST_PER_M.has(level):
		return "No such road."
	var e: Dictionary = cm.call("road", a, b)
	if not e.is_empty():
		var order: Array = CampsScript.LEVEL_ORDER
		if order.find(level) <= order.find(String(e["level"])):
			return "That road is already at least %s." % level
	elif _spos(a).distance_to(_spos(b)) > 2600.0:
		return "Too far to link directly."
	for w: Dictionary in works:
		if String(w["kind"]) == "road" and String(w["a"]) == "s%d" % a and String(w["b"]) == "s%d" % b:
			return "Already being built."
	if gold() < road_cost(a, b, level):
		return "You need %d gold." % road_cost(a, b, level)
	return ""


func plan_road(a: int, b: int, level: String) -> Dictionary:
	var why := can_plan_road(a, b, level)
	if why != "":
		return {"ok": false, "reason": why}
	_pay(road_cost(a, b, level))
	var len_m := _spos(a).distance_to(_spos(b))
	var mult: float = {"road": 1.0, "stone": 1.5, "military": 2.0}.get(level, 1.0)
	var left := maxf(6.0, len_m / 40.0 * mult)
	var home := a if pop_of(a) >= pop_of(b) else b
	var w := {"id": _next_work, "kind": "road", "key": level, "sid": home, "a": "s%d" % a, "b": "s%d" % b, "level": level,
		"label": "%s %s to %s" % [level.capitalize(), _sname(a), _sname(b)], "left": left, "total": left,
		"crew": clampi(mini(8, labour_free(home)), 1, 8), "start": _day}
	_next_work += 1
	works.append(w)
	return {"ok": true, "reason": "", "id": int(w["id"])}


func maintain_cost(a: int, b: int) -> int:
	var cm := _camps()
	var e: Dictionary = cm.call("road", a, b) if cm != null else {}
	if e.is_empty():
		return 0
	return int(round(10.0 + float(e["len"]) * D.MAINTAIN_COST_PER_M * (1.0 - float(e["cond"]))))


func maintain_road(a: int, b: int) -> Dictionary:
	var why := can("road_works")
	if why != "":
		return {"ok": false, "reason": why}
	var cost := maintain_cost(a, b)
	if cost <= 0:
		return {"ok": false, "reason": "No road there."}
	if gold() < cost:
		return {"ok": false, "reason": "You need %d gold." % cost}
	_pay(cost)
	_camps().call("maintain_road", "s%d" % a, "s%d" % b, 1.0)
	invalidate_routes()
	add_standing(a, 1.0)
	add_standing(b, 1.0)
	return {"ok": true, "reason": ""}


## Roads for the trade overlay: [{a, b, level, cond, len, trade, risk, guarded}].
func road_list() -> Array:
	var out: Array = []
	var cm := _camps()
	if cm == null:
		return out
	for e: Dictionary in cm.call("edges"):
		out.append({"a": e["a"], "b": e["b"], "level": e["level"], "cond": float(e["cond"]), "len": float(e["len"]),
			"trade": float(cm.call("trade_volume", e["a"], e["b"])), "risk": float(cm.call("raid_risk", e["a"], e["b"])), "guarded": bool(e["guarded"])})
	return out


# ---------------------------------------------------------------- the fief day

func _fiefs_day(d: int) -> void:
	var la := _land()
	var sids := fief_ids()
	for sid: int in sids:
		if not ensure_fief(sid):
			continue
		var v := _village(sid)
		var fx := _fx(sid)
		var ge := governor_efficiency(sid)
		# the lord's cut of the fief's production
		var share := _production_share(sid)
		v["treasury"] = int(v["treasury"]) + share
		fx["share"] = share
		# a garrison is paid from the treasury; unpaid men drift off
		var gw := 0
		for t: String in garrison_of(sid):
			gw += int(garrison_of(sid)[t]) * int((D.TROOPS[t] as Dictionary)["wage"])
		if gw > 0:
			if int(v["treasury"]) >= gw:
				v["treasury"] = int(v["treasury"]) - gw
			else:
				for t: String in garrison_of(sid).keys():
					garrison_of(sid)[t] = maxi(0, int(garrison_of(sid)[t]) - 1)
				v["loyalty"] = clampf(float(v["loyalty"]) - 1.0, 0.0, 100.0)
		# a governor with a grudge helps himself
		var g := governor_of(sid)
		if not g.is_empty() and float(g["loyalty"]) < 30.0:
			var skim := int(float(v["treasury"]) * 0.03)
			v["treasury"] = int(v["treasury"]) - skim
		# fiefs remember how they are ruled: land.gd memory drives loyalty for generations
		if la != null:
			var rate := String(v["tax_rate"])
			if rate == "harsh" and d % 4 == 0:
				la.call("remember", sid, "tax_burden", 0.3, d)
			elif rate == "low" and d % 6 == 0:
				la.call("remember", sid, "fair_rule", 0.15, d)
			elif rate == "fair" and security_of(sid) >= 55.0 and float(v["loyalty"]) >= 50.0 and d % 9 == 0:
				la.call("remember", sid, "fair_rule", 0.1, d)
			if security_of(sid) < 25.0 and g.is_empty() and float(v["loyalty"]) < 40.0 and d % 5 == 0:
				la.call("remember", sid, "neglect", 0.2, d)
			v["loyalty"] = clampf(float(v["loyalty"]) + (float(la.call("loyalty", sid)) - float(v["loyalty"])) * 0.05, 0.0, 100.0)
		fx["prosperity"] = float(fx["prosperity"]) + (prosperity_target(sid) - float(fx["prosperity"])) * 0.06
		# a steward remits the surplus once a week
		if not g.is_empty() and d % 7 == 0 and int(v["treasury"]) > 250:
			var sweep := int(float(int(v["treasury"]) - 200) * (0.9 - ge * 0.0))
			v["treasury"] = int(v["treasury"]) - sweep
			_earn(sweep)
			_say("%s sends %d gold from %s." % [String(g["name"]), sweep, _sname(sid)])
		add_renown(clampf((float(fx["prosperity"]) - 40.0) / 600.0, 0.0, 0.1), "rule")
	_works_day()
