extends "res://scripts/realm/enterprise_people.gd"
## Enterprise (docs: Bannerlord-style sandbox on the living world, the Rising Ashes way).
## Registered in realm_hub.gd as "enterprise"; the three files are one module:
##   enterprise_core.gd    ledger, roles, prices from supply chains, price intel, trading, routes
##   enterprise_people.gd  clan, troops, recruit pools, mercenaries, vassalage, duties, fiefs, roads
##   enterprise.gd         player caravans (people, not tokens), workshops, ticks, save, map data
##
## Twists on the genre:
##  * Caravans are led by a named follower; traits decide shortcut-or-road, haggling, skimming,
##    and they come back with rumours (society) and sightings of armies (campaign).
##  * You only see prices you or your caravans/informants observed; the knowledge ages.
##  * Workshops burn the town's real stock, so they can cause shortages and price spikes; city
##    guilds (city_life) favour members and squeeze outsiders.
##  * Fief projects are built over days by a crew drawn from the town's labourers; how you rule
##    is remembered by land.gd for generations.
##  * Roads you build or mend (camps.gd) lift trade volume and cut raid risk.
##  * Rifts breed crystal: rare, valuable, and dangerous to haul.

const STOP_HOURS := 10.0
const CARAVAN_SKIM_LOYALTY := 35.0
const REPORT_MAX := 12
const NEAR_RANGE := 1300.0
const MID_RANGE := 3600.0
const SWEEP_MIN := 40

var caravans: Dictionary = {}              # id -> caravan
var _next_car := 1
var workshops: Array = []
var _next_ws := 1


func _owns_enterprise() -> bool:
	return not caravans.is_empty() or not workshops.is_empty()


func _ensure() -> void:
	if _inited:
		return
	var st := _st()
	if st == null or WorldGen.settlements.is_empty():
		return
	st.call("settlement_ids")
	_inited = true
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var r := _rng("seed", 0, sid)
		for g: String in D.LOCAL_GOODS:
			var t := target(sid, g)
			if g == "rift_crystal":
				var f := rift_factor(sid)
				st.call("add_stock", sid, g, t * r.randf_range(1.0, 3.0) if f > 0.05 else 0.0)
			else:
				st.call("add_stock", sid, g, t * r.randf_range(0.3, 1.8))
	observe(0, "home")
	for n: Dictionary in neighbours(0, 6.0):
		observe(int(n["sid"]), "rumour", 0.1, 2)


# ---------------------------------------------------------------- caravans: people, not tokens

func caravan_limit() -> int:
	return 2 + clan_tier() + fief_ids().size() / 2


func list_caravans() -> Array:
	var out: Array = []
	var ids := caravans.keys()
	ids.sort()
	for id: Variant in ids:
		out.append(caravans[id])
	return out


func get_caravan(id: int) -> Dictionary:
	return caravans.get(id, {})


func free_leaders() -> Array:
	var out: Array = []
	var fo := _fo()
	if fo == null:
		return out
	for f: Dictionary in fo.call("party"):
		if String(f["post"]) == "":
			out.append(f)
	return out


## Traits turn into behaviour: how hard they haggle, how much risk they accept, whether they steal.
func leader_profile(fid: String) -> Dictionary:
	var fo := _fo()
	var f: Dictionary = fo.call("get_follower", fid) if fo != null and fid != "" else {}
	var traits: Array = f.get("traits", [])
	var loyalty := float(f.get("loyalty", 50.0))
	var gr := _tf(traits, "greedy")
	var cu := _tf(traits, "curious")
	var ho := _tf(traits, "honorable")
	var br := _tf(traits, "brave")
	var haggle: float = clampf(0.35 + 0.15 * gr + 0.10 * cu + 0.05 * ho + loyalty / 400.0, 0.2, 0.85)
	var appetite: float = 0.45 * br + 0.25 * _tf(traits, "ruthless") + 0.2 * gr + 0.1 * cu - 0.5 * _tf(traits, "cautious") - 0.1 * _tf(traits, "merciful") - 0.1 * ho
	var skills: Dictionary = f.get("skills", {})
	var power: float = 1.0 + 0.3 * br + float(skills.get("combat", 0.2))
	return {"name": String(f.get("name", "a hired hand")), "traits": traits, "loyalty": loyalty, "haggle": haggle, "appetite": appetite,
		"power": power, "curious": traits.has("curious"), "honest": traits.has("honorable")}


static func _tf(traits: Array, t: String) -> float:
	return 1.0 if traits.has(t) else 0.0


func _car_spread(c: Dictionary) -> float:
	var p := leader_profile(String(c["leader"]))
	return maxf(0.03, D.SPREAD - 0.05 * float(p["haggle"]))


func caravan_cost(guards: int, capital: int) -> int:
	return D.CART_COST + guards * D.GUARD_COST + capital


func can_fund_caravan(sid: int, guards: int, capital: int, leader: String) -> String:
	var why := can("caravan")
	if why != "":
		return why
	if caravans.size() >= caravan_limit():
		return "You can run %d caravans at your standing." % caravan_limit()
	if not at_settlement(sid):
		return "You must be in %s to set a caravan going." % _sname(sid)
	var fo := _fo()
	var f: Dictionary = fo.call("get_follower", leader) if fo != null and leader != "" else {}
	if f.is_empty() or String(f["status"]) not in ["present", "traveling"]:
		return "Choose a companion to lead it."
	if String(f["post"]) != "":
		return "%s is already posted (%s)." % [f["name"], f["post"]]
	if guards < 0 or guards > 8:
		return "Between 0 and 8 guards."
	if capital < 50:
		return "A caravan needs at least 50 gold of trading capital."
	if gold() < caravan_cost(guards, capital):
		return "You need %d gold." % caravan_cost(guards, capital)
	return ""


func hire_leader(sid: int) -> String:
	var fo := _fo()
	if fo == null:
		return ""
	return String(fo.call("hire", "scout", "s%d" % sid, true, "caravan%d_%d" % [_next_car, _day]))


func fund_caravan(sid: int, guards: int, capital: int, leader: String, route: Array = []) -> Dictionary:
	var why := can_fund_caravan(sid, guards, capital, leader)
	if why != "":
		return {"ok": false, "reason": why, "id": -1}
	_pay(caravan_cost(guards, capital))
	var id := _next_car
	_next_car += 1
	var prof := leader_profile(leader)
	var c := {"id": id, "name": "%s's wagons" % String(prof["name"]).get_slice(" ", 0), "home": sid, "at": sid, "state": "market", "leader": leader,
		"guards": guards, "cash": capital, "capital": capital, "cap": D.CARAVAN_CAP, "route": route.duplicate(), "route_i": 0, "dest": -1,
		"legs": [], "leg": 0, "leg_left": 0.0, "stop_left": 0.0, "shortcut": false, "cargo": {}, "trips": 0, "profit": 0, "raids": 0,
		"stops": [sid], "reports": [], "seed": hash([WorldSim.SEED, id, sid]) & 0xffff, "born": _day, "hits": [], "sweep": true,
		"leave_on_arrival": false}
	caravans[id] = c
	var fo := _fo()
	if fo != null:
		fo.call("assign_post", leader, "caravan:%d" % id)
		(fo.call("get_follower", leader) as Dictionary)["loc"] = "s%d" % sid
	observe(sid, "caravan")
	_plan_next(c)
	return {"ok": true, "reason": "", "id": id}


func set_caravan_route(id: int, route: Array) -> void:
	if caravans.has(id):
		var c: Dictionary = caravans[id]
		c["route"] = route.duplicate()
		c["route_i"] = 0


func recall_caravan(id: int) -> void:
	if caravans.has(id):
		var c: Dictionary = caravans[id]
		c["route"] = [int(c["home"])]
		c["route_i"] = 0
		c["leave_on_arrival"] = false


func disband_caravan(id: int) -> Dictionary:
	if not caravans.has(id):
		return {"ok": false, "reason": "No such caravan."}
	var c: Dictionary = caravans[id]
	if String(c["state"]) == "travel":
		c["leave_on_arrival"] = true
		c["route"] = [int(c["at"])]
		return {"ok": true, "reason": "It will disband when it reaches its next stop."}
	_disband_now(c)
	return {"ok": true, "reason": ""}


func _disband_now(c: Dictionary) -> void:
	var st := _st()
	var sid := int(c["at"])
	var got := 0
	for g: String in (c["cargo"] as Dictionary):
		var n := int((c["cargo"][g] as Array)[0])
		var q := quote(sid, g, n, "sell", {"spread": _car_spread(c)})
		got += int(q["total"])
		st.call("add_stock", sid, g, float(int(q["qty"])))
	c["cargo"] = {}
	_earn(int(c["cash"]) + got + D.CART_COST / 2)
	_free_leader(c)
	_creport(c, "Disbanded at %s; %d gold came home." % [_sname(sid), int(c["cash"]) + got + D.CART_COST / 2])
	c["cash"] = 0
	c["state"] = "disbanded"
	caravans.erase(int(c["id"]))


func _free_leader(c: Dictionary) -> void:
	var fo := _fo()
	if fo != null and String(c["leader"]) != "":
		fo.call("assign_post", String(c["leader"]), "")


func _creport(c: Dictionary, text: String) -> void:
	var rp: Array = c["reports"]
	rp.append({"day": _day, "text": text})
	if rp.size() > REPORT_MAX:
		rp.pop_front()
	_say("%s: %s" % [String(c["name"]), text])


## Where a caravan is right now (for the map).
func caravan_pos(c: Dictionary) -> Vector2:
	var cm := _camps()
	if String(c["state"]) != "travel" or (c["legs"] as Array).is_empty() or cm == null:
		return _spos(int(c["at"]))
	var legs: Array = c["legs"]
	var i := clampi(int(c["leg"]), 0, legs.size() - 1)
	var leg: Dictionary = legs[i]
	var mult := CARAVAN_SLOW * (D.OFFROAD_SPEED if bool(c["shortcut"]) else 1.0)
	var total := maxf(float(leg["hours"]) * mult, 0.01)
	var f := clampf(1.0 - float(c["leg_left"]) / total, 0.0, 1.0)
	return (cm.call("node_pos", String(leg["a"])) as Vector2).lerp(cm.call("node_pos", String(leg["b"])), f)


## How far from the player a caravan is: near plays out live, far is bookkeeping (SIM_HIERARCHY).
func tier_of(c: Dictionary) -> String:
	var d := caravan_pos(c).distance_to(player_pos())
	if d < NEAR_RANGE:
		return "near"
	return "mid" if d < MID_RANGE else "far"


func caravan_eta(c: Dictionary) -> float:
	if String(c["state"]) == "travel":
		var h := float(c["leg_left"])
		var legs: Array = c["legs"]
		var mult := CARAVAN_SLOW * (D.OFFROAD_SPEED if bool(c["shortcut"]) else 1.0)
		for i in range(int(c["leg"]) + 1, legs.size()):
			h += float((legs[i] as Dictionary)["hours"]) * mult
		return h
	return float(c["stop_left"])


func caravan_status(c: Dictionary) -> String:
	match String(c["state"]):
		"travel":
			return "On the road to %s (%d h)" % [_sname(int(c["dest"])), int(ceil(caravan_eta(c)))]
		"market":
			return "Trading in %s" % _sname(int(c["at"]))
		"idle":
			return "Waiting in %s: nothing worth hauling" % _sname(int(c["at"]))
	return String(c["state"]).capitalize()


func _cargo_cost(c: Dictionary) -> float:
	var t := 0.0
	for g: String in (c["cargo"] as Dictionary):
		var e: Array = c["cargo"][g]
		t += float(e[0]) * float(e[1])
	return t


func cargo_units(c: Dictionary) -> int:
	var n := 0
	for g: String in (c["cargo"] as Dictionary):
		n += int((c["cargo"][g] as Array)[0])
	return n


func _choose_dest(c: Dictionary) -> int:
	var at := int(c["at"])
	var route: Array = c["route"]
	if not route.is_empty():
		for k in route.size():
			var i := (int(c["route_i"]) + 1 + k) % route.size()
			if int(route[i]) != at:
				c["route_i"] = i
				return int(route[i])
		return -1
	var prof := leader_profile(String(c["leader"]))
	var r := _rng("cdest", int(c["trips"]) * 31 + int(c["seed"]), int(c["id"]))
	var best := -1
	var bs := 0.0
	var opts := {"cap": int(c["cap"]), "budget": float(c["cash"]), "guards": int(c["guards"]), "spread": _car_spread(c)}
	var near: Array = neighbours(at, 40.0)
	if near.size() > 5:
		near = near.slice(0, 5)
	for n: Dictionary in near:
		var sid := int(n["sid"])
		var leg := estimate_leg(at, sid, opts)
		var score := float(leg["expected"]) / maxf(float(leg["hours"]), 6.0)
		if (c["stops"] as Array).has(sid):
			score *= 0.6
		if bool(prof["curious"]) and not is_known(sid):
			score += 1.5
		score *= 1.0 + r.randf_range(-0.12, 0.12) * (1.3 - float(prof["haggle"]))
		if score > bs:
			bs = score
			best = sid
	if best < 0 and at != int(c["home"]):
		return int(c["home"])
	return best


func _choose_shortcut(c: Dictionary, a: int, b: int) -> bool:
	var ri := route_info(a, b)
	if (ri["nodes"] as Array).size() <= 2 or float(ri["risk"]) > 0.3:
		return false
	var prof := leader_profile(String(c["leader"]))
	var r := _rng("cshort", int(c["trips"]) * 17 + int(c["seed"]), int(c["id"]))
	return float(prof["appetite"]) + r.randf_range(-0.35, 0.35) > 0.3


## Buys the cargo for the next run and sets the wagons rolling after the stop.
func _plan_next(c: Dictionary) -> bool:
	var at := int(c["at"])
	var dest := _choose_dest(c)
	if dest < 0:
		c["state"] = "idle"
		c["stop_left"] = 24.0
		c["dest"] = -1
		return false
	var opts := {"cap": int(c["cap"]), "budget": float(c["cash"]), "guards": int(c["guards"]), "spread": _car_spread(c)}
	var leg := estimate_leg(at, dest, opts)
	if String(leg["good"]) != "" and int(leg["qty"]) > 0 and int(leg["profit"]) > 0:
		var q := quote(at, String(leg["good"]), int(leg["qty"]), "buy", {"spread": _car_spread(c)})
		if int(q["qty"]) > 0 and int(q["total"]) <= int(c["cash"]):
			c["cash"] = int(c["cash"]) - int(q["total"])
			_st().call("add_stock", at, String(leg["good"]), -float(int(q["qty"])))
			c["cargo"][String(leg["good"])] = [int(q["qty"]), float(q["total"]) / float(int(q["qty"]))]
	var toll := trip_toll(at, dest)
	if toll > 0 and int(c["cash"]) >= toll:
		c["cash"] = int(c["cash"]) - toll
	var short := _choose_shortcut(c, at, dest)
	c["shortcut"] = short
	var ri := route_info(at, dest)
	c["legs"] = (ri["legs"] as Array).duplicate(true)
	c["leg"] = 0
	c["dest"] = dest
	var first := float((c["legs"][0] as Dictionary)["hours"]) if not (c["legs"] as Array).is_empty() else 1.0
	c["leg_left"] = first * CARAVAN_SLOW * (D.OFFROAD_SPEED if short else 1.0)
	c["state"] = "market"
	c["stop_left"] = STOP_HOURS
	return true


func _arrive(c: Dictionary, near: bool) -> void:
	var sid := int(c["at"])
	var st := _st()
	var prof := leader_profile(String(c["leader"]))
	var r := _rng("carrive", int(c["trips"]), int(c["id"]) * 13 + int(c["seed"]))
	observe(sid, "caravan")
	var revenue := 0
	var basis := _cargo_cost(c)
	for g: String in (c["cargo"] as Dictionary).keys():
		var n := int((c["cargo"][g] as Array)[0])
		var q := quote(sid, g, n, "sell", {"spread": _car_spread(c)})
		revenue += int(q["total"])
		st.call("add_stock", sid, g, float(int(q["qty"])))
	c["cargo"] = {}
	var skim := 0
	if float(prof["loyalty"]) < CARAVAN_SKIM_LOYALTY and revenue > 0 and r.randf() < 0.45:
		skim = int(float(revenue) * r.randf_range(0.04, 0.12))
		revenue -= skim
		_leader_loyalty(c, -2.0)
	c["cash"] = int(c["cash"]) + revenue
	var profit := revenue - int(round(basis))
	c["profit"] = int(c["profit"]) + profit
	c["trips"] = int(c["trips"]) + 1
	stats["trips"] = int(stats["trips"]) + 1
	if profit > 0:
		add_renown(float(profit) / 300.0, "trade")
		_leader_loyalty(c, 0.4)
	if revenue > 0 or basis > 0.0:
		var line := "Reached %s: sold for %d gold (%s%d)." % [_sname(sid), revenue, "+" if profit >= 0 else "", profit]
		if skim > 0:
			line += " The books look short by about %d." % skim
		_creport(c, line)
	_leader_news(c, sid, near, r)
	var stops: Array = c["stops"]
	stops.append(sid)
	if stops.size() > 3:
		stops.pop_front()
	# report back: profits above the working capital ride home with a courier
	var surplus := int(c["cash"]) - int(c["capital"])
	if bool(c["sweep"]) and surplus >= SWEEP_MIN:
		c["cash"] = int(c["capital"])
		_earn(int(surplus * 0.98))
	if bool(c["leave_on_arrival"]):
		_disband_now(c)
		return
	_plan_next(c)


func _leader_loyalty(c: Dictionary, delta: float) -> void:
	var fo := _fo()
	if fo == null or String(c["leader"]) == "":
		return
	var f: Dictionary = fo.call("get_follower", String(c["leader"]))
	if not f.is_empty():
		f["loyalty"] = clampf(float(f["loyalty"]) + delta, 0.0, 100.0)


## Leaders bring news home: what the road ahead costs, and any army they saw.
func _leader_news(c: Dictionary, sid: int, near: bool, r: RandomNumberGenerator) -> void:
	# a rumour of the next town's market
	var nb := neighbours(sid, 12.0)
	if not nb.is_empty():
		var t := int((nb[r.randi() % mini(nb.size(), 3)] as Dictionary)["sid"])
		if known_age(t) < 0 or known_age(t) > 5:
			observe(t, "rumour", 0.1, 1 + r.randi() % 2)
	var cm := _m("campaign")
	if cm != null and (leader_profile(String(c["leader"]))["curious"] or r.randf() < 0.35):
		var here := _spos(sid)
		for a: Dictionary in cm.call("armies"):
			if String(a["faction"]) != "player" and (a["pos"] as Vector2).distance_to(here) < 1100.0:
				if bool(cm.call("report_sighting", int(a["id"]), "caravan", 0.35)):
					_creport(c, "The leader glimpsed soldiers on the road near %s and sent word." % _sname(sid))
				break


func _raid(c: Dictionary, rd: Dictionary, salt: int) -> void:
	var prof := leader_profile(String(c["leader"]))
	var r := _rng("craid", salt, int(c["id"]) * 7 + int(c["seed"]))
	var strength := float(rd.get("strength", r.randi_range(8, 30)))
	var defence := float(c["guards"]) * 4.0 + 6.0 * float(prof["power"])
	var where := _sname(int(c["at"]))
	c["raids"] = int(c["raids"]) + 1
	var soc := _m("society")
	if defence * r.randf_range(0.7, 1.3) >= strength * r.randf_range(0.7, 1.3) * 0.75:
		var lost_g := int(round(float(c["guards"]) * 0.15))
		c["guards"] = maxi(0, int(c["guards"]) - lost_g)
		_creport(c, "Beat off raiders near %s%s." % [where, (", losing %d guards" % lost_g) if lost_g > 0 else ""])
		_leader_loyalty(c, 2.0)
		add_renown(0.6, "caravan defence")
		if soc != null:
			soc.call("add_rumour", "rescue", int(c["at"]), float(maxi(2, int(c["guards"]))), "player", 1.0)
		return
	var frac := r.randf_range(0.2, 0.6) * guard_factor(int(c["guards"])) * (1.0 - 0.25 * float(prof["appetite"] > 0.4))
	var cargo: Dictionary = c["cargo"]
	for g: String in cargo.keys():
		var e: Array = cargo[g]
		e[0] = int(round(float(e[0]) * (1.0 - frac)))
		if int(e[0]) <= 0:
			cargo.erase(g)
	var stolen := int(float(c["cash"]) * r.randf_range(0.1, 0.25) * guard_factor(int(c["guards"])))
	c["cash"] = int(c["cash"]) - stolen
	var lost_guards := int(round(float(c["guards"]) * frac * 0.7))
	c["guards"] = maxi(0, int(c["guards"]) - lost_guards)
	_leader_loyalty(c, -2.0 if not (prof["traits"] as Array).has("brave") else -0.5)
	if int(c["guards"]) == 0 and frac > 0.45 and r.randf() < 0.35:
		_creport(c, "Lost to bandits near %s. The wagons did not come back." % where)
		_free_leader(c)
		c["state"] = "destroyed"
		caravans.erase(int(c["id"]))
		return
	_creport(c, "Raided near %s: %d%% of the cargo and %d gold gone%s." % [where, int(frac * 100.0), stolen, (", %d guards down" % lost_guards) if lost_guards > 0 else ""])


func _leg_done(c: Dictionary) -> void:
	var legs: Array = c["legs"]
	var i := int(c["leg"])
	var leg: Dictionary = legs[i]
	var risk := float(leg["risk"]) * guard_factor(int(c["guards"])) * (D.SHORTCUT_RISK if bool(c["shortcut"]) else 1.0)
	var salt := int(c["trips"]) * 37 + i
	var r := _rng("clegroll", salt, int(c["id"]) + int(c["seed"]))
	c["leg"] = i + 1
	if r.randf() < clampf(risk, 0.0, 0.9):
		_raid(c, {}, salt)
		if not caravans.has(int(c["id"])):
			return
	if int(c["leg"]) >= legs.size():
		c["at"] = int(c["dest"])
		_arrive(c, false)
	else:
		var nxt: Dictionary = legs[int(c["leg"])]
		c["leg_left"] = float(nxt["hours"]) * CARAVAN_SLOW * (D.OFFROAD_SPEED if bool(c["shortcut"]) else 1.0)


## Runs a caravan forward `hours` game hours by events (leg ends, stops), so a long absence costs
## O(legs) rather than O(hours).
func _advance(c: Dictionary, hours: float) -> void:
	var left := hours
	var guard := 0
	while left > 0.0001 and guard < 500 and caravans.has(int(c["id"])):
		guard += 1
		match String(c["state"]):
			"market", "idle":
				var step := minf(left, float(c["stop_left"]))
				c["stop_left"] = float(c["stop_left"]) - step
				left -= step
				if float(c["stop_left"]) <= 0.0001:
					if String(c["state"]) == "idle":
						_plan_next(c)
					else:
						c["state"] = "travel"
			"travel":
				var step2 := minf(left, float(c["leg_left"]))
				c["leg_left"] = float(c["leg_left"]) - step2
				left -= step2
				if float(c["leg_left"]) <= 0.0001:
					_leg_done(c)
			_:
				return


## Live raid bands near a travelling caravan fight it: only for caravans near the player.
func _intercept_check(c: Dictionary) -> void:
	var sh := _sh()
	if sh == null or String(c["state"]) != "travel":
		return
	var pos := caravan_pos(c)
	for rd: Dictionary in sh.call("raids"):
		if String(rd["phase"]) not in ["travel", "strike"] or (c["hits"] as Array).has(int(rd["id"])):
			continue
		if (rd["pos"] as Vector2).distance_to(pos) < 350.0:
			(c["hits"] as Array).append(int(rd["id"]))
			if (c["hits"] as Array).size() > 6:
				(c["hits"] as Array).pop_front()
			_raid(c, rd, 900 + int(rd["id"]))
			return


func _caravans_day() -> void:
	var fo := _fo()
	for id: Variant in caravans.keys():
		var c: Dictionary = caravans[id]
		var wage := int(c["guards"]) * D.GUARD_WAGE + 4
		if String(c["leader"]) != "" and fo != null:
			var f: Dictionary = fo.call("get_follower", String(c["leader"]))
			if not f.is_empty() and int(f["owed"]) > 0:
				var used := int(fo.call("pay", String(c["leader"]), mini(int(f["owed"]), int(c["cash"]))))
				c["cash"] = int(c["cash"]) - used
		if int(c["cash"]) >= wage:
			c["cash"] = int(c["cash"]) - wage
		else:
			c["cash"] = 0
			if int(c["guards"]) > 0:
				c["guards"] = int(c["guards"]) - 1
				_creport(c, "Unpaid guards are drifting away.")
			_leader_loyalty(c, -1.0)
		if String(c["state"]) in ["market", "idle"]:
			observe(int(c["at"]), "caravan")


# ---------------------------------------------------------------- workshops

func workshop_price(sid: int, kind: String) -> int:
	var def: Dictionary = D.WORKSHOPS.get(kind, {})
	if def.is_empty():
		return 0
	return int(round(float(def["price"]) * float(D.SETTLEMENT_MULT.get(_skind(sid), 1.0)) / 10.0) * 10.0)


func workshops_at(sid: int) -> Array:
	return workshops.filter(func(w: Dictionary) -> bool: return int(w["sid"]) == sid)


func get_workshop(id: int) -> Dictionary:
	for w: Dictionary in workshops:
		if int(w["id"]) == id:
			return w
	return {}


func _labour_other(sid: int) -> int:
	var n := 0
	for w: Dictionary in workshops:
		if int(w["sid"]) == sid:
			n += int(w["workers"])
	return n


## City guilds: members get a better market, outsiders pay a levy, a closed guild blocks you.
func guild_stance(sid: int, kind: String) -> Dictionary:
	var cl := _m("city_life")
	var def: Dictionary = D.WORKSHOPS.get(kind, {})
	if cl == null or def.is_empty():
		return {"present": false, "member": false, "blocked": false, "name": ""}
	var gid := "g:%s:%d" % [String(def["guild"]), sid]
	var g: Dictionary = cl.call("guild", gid)
	if g.is_empty():
		return {"present": false, "member": false, "blocked": false, "name": ""}
	var member := int((g["player"] as Dictionary)["rank"]) >= 0
	var top_id := ""
	var top_p := -1.0
	for f: Dictionary in g["factions"]:
		if float(f["power"]) > top_p:
			top_p = float(f["power"])
			top_id = String(f["id"])
	var blocked := (not member) and top_id == "old_guard" and top_p > 38.0
	return {"present": true, "member": member, "blocked": blocked, "name": String(g["name"]), "gid": gid, "fee": int(g["fee"]), "ruling": top_id}


func join_workshop_guild(sid: int, kind: String) -> Dictionary:
	var gs := guild_stance(sid, kind)
	var cl := _m("city_life")
	if not bool(gs["present"]) or cl == null:
		return {"ok": false, "reason": "No guild there."}
	return cl.call("join_guild", String(gs["gid"]))


func can_buy_workshop(sid: int, kind: String) -> String:
	var why := can("workshop")
	if why != "":
		return why
	var def: Dictionary = D.WORKSHOPS.get(kind, {})
	if def.is_empty():
		return "No such workshop."
	if not (def["kinds"] as Array).has(_skind(sid)):
		return "%s has no room for a %s." % [_sname(sid), String(def["name"]).to_lower()]
	if not at_settlement(sid):
		return "You must be in %s to buy." % _sname(sid)
	for w: Dictionary in workshops_at(sid):
		if String(w["kind"]) == kind:
			return "You already run one here."
	if workshops_at(sid).size() >= 3:
		return "Three workshops is all the town will tolerate from one owner."
	var gs := guild_stance(sid, kind)
	if bool(gs["blocked"]):
		return "%s keeps the trade closed to outsiders. Join them first." % String(gs["name"])
	if labour_free(sid) < D.WORKERS_PER_LEVEL:
		return "No free hands in %s to staff it." % _sname(sid)
	if gold() < workshop_price(sid, kind):
		return "You need %d gold." % workshop_price(sid, kind)
	return ""


func buy_workshop(sid: int, kind: String) -> Dictionary:
	var why := can_buy_workshop(sid, kind)
	if why != "":
		return {"ok": false, "reason": why, "id": -1}
	var price := workshop_price(sid, kind)
	_pay(price)
	var w := {"id": _next_ws, "sid": sid, "kind": kind, "level": 1, "workers": D.WORKERS_PER_LEVEL, "manager": "", "bought": _day, "spent": price,
		"history": [], "last": {}}
	_next_ws += 1
	workshops.append(w)
	observe(sid, "visit")
	return {"ok": true, "reason": "", "id": int(w["id"])}


func upgrade_cost(w: Dictionary) -> int:
	return int(round(0.8 * float(workshop_price(int(w["sid"]), String(w["kind"]))) * float(w["level"]) / 10.0) * 10.0)


func upgrade_workshop(id: int) -> Dictionary:
	var w := get_workshop(id)
	if w.is_empty() or int(w["level"]) >= D.MAX_LEVEL:
		return {"ok": false, "reason": "It cannot grow further."}
	var c := upgrade_cost(w)
	if gold() < c:
		return {"ok": false, "reason": "You need %d gold." % c}
	_pay(c)
	w["level"] = int(w["level"]) + 1
	w["spent"] = int(w["spent"]) + c
	return {"ok": true, "reason": ""}


func set_workers(id: int, n: int) -> Dictionary:
	var w := get_workshop(id)
	if w.is_empty():
		return {"ok": false, "reason": "No such workshop."}
	var mx := int(w["level"]) * 4
	var target_n := clampi(n, 0, mx)
	if target_n > int(w["workers"]):
		var add := target_n - int(w["workers"])
		if add > labour_free(int(w["sid"])):
			return {"ok": false, "reason": "No more free hands in town."}
		if gold() < add * D.HIRE_COST:
			return {"ok": false, "reason": "Hiring costs %d gold." % (add * D.HIRE_COST)}
		_pay(add * D.HIRE_COST)
	w["workers"] = target_n
	return {"ok": true, "reason": ""}


func set_manager(id: int, fid: String) -> Dictionary:
	var w := get_workshop(id)
	var fo := _fo()
	if w.is_empty() or fo == null:
		return {"ok": false, "reason": "No such workshop."}
	if String(w["manager"]) != "":
		fo.call("assign_post", String(w["manager"]), "")
	w["manager"] = ""
	if fid != "":
		var f: Dictionary = fo.call("get_follower", fid)
		if f.is_empty() or String(f["post"]) != "":
			return {"ok": false, "reason": "They are not free to manage it."}
		fo.call("assign_post", fid, "workshop:%d" % int(w["id"]))
		w["manager"] = fid
	return {"ok": true, "reason": ""}


func sell_workshop(id: int) -> Dictionary:
	var w := get_workshop(id)
	if w.is_empty():
		return {"ok": false, "reason": "No such workshop."}
	var refund := int(float(w["spent"]) * 0.6)
	_earn(refund)
	if String(w["manager"]) != "":
		set_manager(id, "")
	workshops.erase(w)
	return {"ok": true, "reason": "", "refund": refund}


## What a day of work would cost and earn at today's prices and stock. apply=true also moves the stock.
func workshop_run(w: Dictionary, apply: bool) -> Dictionary:
	var def: Dictionary = D.WORKSHOPS[String(w["kind"])]
	var sid := int(w["sid"])
	var st := _st()
	var level := int(w["level"])
	var staffing := clampf(float(w["workers"]) / float(D.WORKERS_PER_LEVEL * level), 0.0, 1.25)
	var mgr := 0.0
	if String(w["manager"]) != "" and _fo() != null and not (_fo().call("get_follower", String(w["manager"])) as Dictionary).is_empty():
		mgr = 0.08
	var batches := D.BATCHES_PER_LEVEL * float(level) * staffing * (1.0 + mgr)
	var supplied := 1.0
	var short_good := ""
	var ins: Dictionary = def["in"]
	for g: String in ins:
		var need := batches * float(ins[g])
		if need <= 0.0:
			continue
		var frac := available(sid, g) / need
		if frac < supplied:
			supplied = frac
			short_good = g
	supplied = clampf(supplied, 0.0, 1.0)
	var eff := batches * supplied
	var spread := D.SPREAD * 0.8
	var in_cost := 0.0
	for g: String in ins:
		var q := eff * float(ins[g])
		var s0 := stock_of(sid, g)
		in_cost += q * 0.5 * (price_at(sid, g, s0) + price_at(sid, g, maxf(0.0, s0 - q))) * (1.0 + spread * 0.5)
	var revenue := 0.0
	var outs: Dictionary = def["out"]
	for g: String in outs:
		var q2 := eff * float(outs[g])
		var s1 := stock_of(sid, g)
		revenue += q2 * 0.5 * (price_at(sid, g, s1) + price_at(sid, g, s1 + q2)) * (1.0 - spread * 0.5)
	var gs := guild_stance(sid, String(w["kind"]))
	var guild_adj := 0.0
	if bool(gs["present"]):
		guild_adj = D.GUILD_MEMBER_BONUS if bool(gs["member"]) else -D.GUILD_OUTSIDER_LEVY
	revenue *= 1.0 + guild_adj
	var wages := int(w["workers"]) * int(def["wage"])
	var upkeep := int(round(float(w["spent"]) * D.UPKEEP_FRACTION))
	var net := int(round(revenue - in_cost)) - wages - upkeep
	var res := {"batches": batches, "eff": eff, "supplied": supplied, "short": short_good, "in_cost": int(round(in_cost)), "revenue": int(round(revenue)),
		"wages": wages, "upkeep": upkeep, "net": net, "guild": guild_adj, "day": _day}
	if apply:
		for g: String in ins:
			st.call("add_stock", sid, g, -eff * float(ins[g]))
		for g: String in outs:
			st.call("add_stock", sid, g, eff * float(outs[g]))
		if supplied < 0.6 and short_good != "":
			var sh: Dictionary = st.call("shortages", sid)
			sh[short_good] = int(sh.get(short_good, 0)) + 1
		_earn(net)
		if net > 0:
			add_renown(float(net) / 400.0, "craft")
	return res


func _workshops_day() -> void:
	for w: Dictionary in workshops:
		var res := workshop_run(w, true)
		w["last"] = res
		var h: Array = w["history"]
		h.append(int(res["net"]))
		if h.size() > 7:
			h.pop_front()
		if float(res["supplied"]) < 0.6 and String(res["short"]) != "":
			_say("Your %s in %s is short of %s." % [String((D.WORKSHOPS[String(w["kind"])] as Dictionary)["name"]).to_lower(), _sname(int(w["sid"])), String((D.GOODS[String(res["short"])] as Dictionary)["name"]).to_lower()])
		observe(int(w["sid"]), "visit")


# ---------------------------------------------------------------- ticks

func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_ensure()
	if ctx.has("abs_hours"):
		_now = float(ctx["abs_hours"])
		_day = int(_now / 24.0)
	if ctx.get("player_pos") is Vector2:
		_ppos = ctx["player_pos"]
	for id: Variant in caravans.keys():
		if not caravans.has(id):
			continue
		var c: Dictionary = caravans[id]
		_advance(c, 1.0)
		if caravans.has(id) and tier_of(c) == "near":
			_intercept_check(c)
	return _flush()


func tick_day(day_n: int, ctx: Dictionary) -> Array:
	return _run_chunks(day_n, ctx)


func tick_day_chunks(day_n: int, _ctx: Dictionary) -> Array:
	_ensure()
	return [
		func() -> Array:
			_day = day_n
			invalidate_routes()
			_local_day(day_n)
			for k: String in informants.keys():
				if int(informants[k]) >= day_n:
					observe(int(k), "informant")
			return _flush(),
		func() -> Array:
			_workshops_day()
			return _flush(),
		func() -> Array:
			_caravans_day()
			return _flush(),
		func() -> Array:
			_fiefs_day(day_n)
			return _flush(),
		func() -> Array:
			_people_day()
			return _flush(),
	]


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	if days < 1:
		return []
	var n := mini(days, 30)
	var d1 := int(float(ctx.get("abs_hours", float(_day) * 24.0)) / 24.0)
	var d0 := d1 - n
	for i in n:
		var dd := d0 + i + 1
		for ch: Callable in tick_day_chunks(dd, ctx):
			ch.call()
	_day = d1
	_now = float(d1) * 24.0
	for id: Variant in caravans.keys():
		if caravans.has(id):
			_advance(caravans[id], float(n) * 24.0)
	var out := _flush()
	if out.size() > 6:
		out = out.slice(out.size() - 6)
	return out


# ---------------------------------------------------------------- map data (strategic map, cards)

## Who holds a settlement on the political map: deed holder plus the war owner.
func political_of(sid: int) -> Dictionary:
	var la := _land()
	var d: Dictionary = la.call("deed", sid) if la != null else {}
	var fac := "caldrenn"
	var cm := _m("campaign")
	if cm != null:
		var cap: Dictionary = cm.call("captured")
		if cap.has(str(sid)):
			fac = String(cap[str(sid)])
	return {"holder": String(d.get("holder", "crown")), "kind": String(d.get("kind", "royal")), "faction": fac,
		"loyalty": float(la.call("loyalty", sid)) if la != null else 50.0}


func holder_label(holder: String) -> String:
	match holder:
		"crown":
			return "The Crown"
		"church":
			return "The Church"
		"commons":
			return "Free commons"
		"player":
			return "You"
		"rebels":
			return "Rebels"
	return holder.capitalize().replace("_", " ")


func danger_of(sid: int) -> Dictionary:
	var sh := _sh()
	if sh == null:
		return {"danger": 0.0, "text": "", "lines": []}
	return sh.call("recommended_preparation", sid, {"season": "spring"})


func days_away(sid: int) -> float:
	var from := nearest_settlement(player_pos())
	if from == sid:
		return 0.0
	return trip_hours(from, sid, false) / 24.0


## The info card behind a tap on a settlement, with the actions this player can take there.
func settlement_card(sid: int) -> Dictionary:
	var st := _st()
	var pol := political_of(sid)
	var dom := String(st.call("dominant", sid)) if st != null else ""
	var res := resources_of(sid)
	var acts: Array = []
	var here := at_settlement(sid)
	acts.append({"id": "trade", "label": "Trade here", "ok": here, "reason": "" if here else "You are %.1f days away." % days_away(sid)})
	var why_w := can("workshop")
	acts.append({"id": "workshop", "label": "Workshops", "ok": why_w == "", "reason": why_w})
	var why_c := can("caravan")
	acts.append({"id": "caravan", "label": "Send a caravan", "ok": why_c == "", "reason": why_c})
	var why_r := can("recruit")
	acts.append({"id": "recruit", "label": "Recruit troops", "ok": why_r == "", "reason": why_r})
	if is_fief(sid):
		acts.append({"id": "fief", "label": "Manage fief", "ok": true, "reason": ""})
	else:
		var why_f := can_buy_fief(sid)
		acts.append({"id": "buy_fief", "label": "Buy the estate", "ok": why_f == "", "reason": why_f})
	if is_soldier():
		acts.append({"id": "duty", "label": "Army duties", "ok": true, "reason": ""})
	if roles() == ["commoner"]:
		acts.append({"id": "license", "label": "Buy trader's licence (%dg)" % D.LICENSE_COST, "ok": gold() >= D.LICENSE_COST, "reason": "You need %d gold." % D.LICENSE_COST})
	return {"sid": sid, "name": _sname(sid), "kind": _skind(sid), "pop": pop_of(sid), "holder": pol["holder"], "holder_label": holder_label(String(pol["holder"])),
		"faction": pol["faction"], "loyalty": pol["loyalty"], "identity": dom, "sells": res["sells"], "needs": res["needs"], "makes": res["makes"],
		"age": known_age(sid), "danger": danger_of(sid), "standing": standing(sid), "fief": is_fief(sid),
		"workshops": workshops_at(sid).size(), "caravans": caravans.values().filter(func(c: Dictionary) -> bool: return int(c["at"]) == sid).size(),
		"rift": rift_factor(sid) > 0.05, "actions": acts}


# ---------------------------------------------------------------- save

func serialize() -> Dictionary:
	var cs := {}
	for id: Variant in caravans:
		cs[str(id)] = (caravans[id] as Dictionary).duplicate(true)
	return {"inited": _inited, "pending_gold": pending_gold, "license": license_owned, "pack": pack.duplicate(true), "seen": seen.duplicate(true),
		"informants": informants.duplicate(), "rep": rep_delta.duplicate(), "stats": stats.duplicate(), "log": log_lines.duplicate(),
		"clan": clan.duplicate(), "troops": troops.duplicate(), "recruit": recruit_state.duplicate(true), "merc": merc.duplicate(true), "liege": liege,
		"vassal_day": vassal_day, "duty": duty.duplicate(true), "duties_done": duties_done, "fiefx": fiefx.duplicate(true), "works": works.duplicate(true),
		"next_work": _next_work, "caravans": cs, "next_car": _next_car, "workshops": workshops.duplicate(true), "next_ws": _next_ws, "day": _day}


func deserialize(d: Dictionary) -> void:
	_inited = bool(d.get("inited", false))
	pending_gold = int(d.get("pending_gold", 0))
	license_owned = bool(d.get("license", false))
	pack = (d.get("pack", {}) as Dictionary).duplicate(true)
	seen = (d.get("seen", {}) as Dictionary).duplicate(true)
	informants = (d.get("informants", {}) as Dictionary).duplicate()
	rep_delta = (d.get("rep", {}) as Dictionary).duplicate()
	stats = (d.get("stats", {"traded": 0, "profit": 0, "trips": 0}) as Dictionary).duplicate()
	log_lines = (d.get("log", []) as Array).duplicate()
	clan = (d.get("clan", {"name": "Ashen Company", "renown": 0.0, "influence": 0.0}) as Dictionary).duplicate()
	troops = (d.get("troops", {}) as Dictionary).duplicate()
	recruit_state = (d.get("recruit", {}) as Dictionary).duplicate(true)
	merc = (d.get("merc", {}) as Dictionary).duplicate(true)
	liege = String(d.get("liege", ""))
	vassal_day = int(d.get("vassal_day", -1))
	duty = (d.get("duty", {}) as Dictionary).duplicate(true)
	duties_done = int(d.get("duties_done", 0))
	fiefx = (d.get("fiefx", {}) as Dictionary).duplicate(true)
	works = (d.get("works", []) as Array).duplicate(true)
	_next_work = int(d.get("next_work", 1))
	caravans = {}
	var cs: Dictionary = d.get("caravans", {})
	for k: Variant in cs:
		caravans[int(k)] = (cs[k] as Dictionary).duplicate(true)
	_next_car = int(d.get("next_car", 1))
	workshops = (d.get("workshops", []) as Array).duplicate(true)
	_next_ws = int(d.get("next_ws", 1))
	_day = int(d.get("day", 0))
	_route_cache.clear()
