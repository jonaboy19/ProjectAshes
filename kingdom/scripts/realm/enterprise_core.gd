extends "res://scripts/realm/realm_module.gd"
## Enterprise, part 1: the money ledger, roles and gating, per-settlement prices from the real
## supply chains (settlements.gd stock), price intelligence that ages like war intel, bulk trading,
## and route maths (travel time from camps.gd, risk/tolls from strongholds.gd, rifts).
## Parts 2 and 3 (enterprise_people.gd, enterprise.gd) extend this file; the hub registers the last.
##
## Money rule: never touches the purse. Every gold change lands in `pending_gold` (signed) and Life
## drains it with take_pending_gold() (autoload/life.gd _on_hour ledger list; the UI also settles
## after a player action so the purse is current).

## Metres per hour on a road: the same as camps.TRAVEL_M_PER_HOUR (700 on the 8 km map, 1050 on the 12 km map).
const ROAD_M_PER_HOUR := 1050.0
const D := preload("res://scripts/realm/enterprise_data.gd")
const SettlementsScript := preload("res://scripts/realm/settlements.gd")

## Price curve: factor = (normal stock / (stock + 1)) ^ EXPONENT, kept inside [PRICE_MIN, PRICE_MAX].
const PRICE_EXPONENT := 0.55
const PRICE_MIN := 0.7
const PRICE_MAX := 1.8
const TRADE_CAP := 400
const CARAVAN_SLOW := 3.0             # carts are slower than a walker over the same road graph
const SEEN_FRESH_DAYS := 3
const LOG_MAX := 40

var hub_override: RefCounted = null
var pending_gold: int = 0
## Tests inject these; in the game they stay at their defaults and the autoloads answer.
var purse_override: int = -1
var career_override: String = ""
var lordship_ref: RefCounted = null
var presence_override: bool = false       # true = the player may trade anywhere (tests, screenshots)
var cart_override: bool = false

var license_owned := false
var pack: Dictionary = {}                 # good -> [qty, avg cost] the player carries
var seen: Dictionary = {}                 # "sid" -> {good: {p, n, d, src}}  what the player knows
var informants: Dictionary = {}           # "sid" -> day the informant's service ends
var rep_delta: Dictionary = {}            # "sid" -> standing earned by trading / helping (+/-)
var stats: Dictionary = {"traded": 0, "profit": 0, "trips": 0}
var log_lines: Array = []

var _inited := false
var _day := 0
var _now := 0.0
var _ppos := Vector2.ZERO
var _route_cache: Dictionary = {}
var _tc: Dictionary = {}                  # sid -> {good: normal stock}   (cleared daily)
var _ec: Dictionary = {}                  # sid -> {category: event multiplier}   (cleared daily)
var _rift_cache: Array = []
var _rift_built := false


# ---------------------------------------------------------------- plumbing

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, "ent", tag, day, str(id)])
	return r


## Autoloads are looked up at run time (not named in code) so this module never forms a compile
## cycle with Life, which owns the realm hub that owns this module.
func _au(autoload_name: String) -> Object:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(autoload_name)
	return null


func _au_get(autoload_name: String, prop: String) -> Variant:
	var n := _au(autoload_name)
	return n.get(prop) if n != null else null


func _m(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _st() -> RefCounted:
	return _m("settlements")


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _skind(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["kind"])
	return "village"


func _spos(sid: int) -> Vector2:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.settlements[sid]["pos"]
	return Vector2.ZERO


func _note(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > LOG_MAX:
		log_lines.pop_front()


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


## Spendable gold: the purse plus what is already on the ledger.
func gold() -> int:
	if purse_override >= 0:
		return purse_override + pending_gold
	return int(_au_get("Game", "gold")) + pending_gold


func _pay(amount: int) -> void:
	pending_gold -= amount


func _earn(amount: int) -> void:
	pending_gold += amount


func day() -> int:
	return _day


func set_clock(d: int) -> void:
	_day = d
	_now = float(d) * 24.0


func set_player_pos(p: Vector2) -> void:
	_ppos = p


func player_pos() -> Vector2:
	var pl: Variant = _au_get("Life", "player")
	if pl is Node3D and is_instance_valid(pl):
		return Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	return _ppos


## True when the player is close enough to a settlement's market to deal in it.
func at_settlement(sid: int) -> bool:
	if presence_override:
		return true
	if sid < 0 or sid >= WorldGen.settlements.size():
		return false
	var s: Dictionary = WorldGen.settlements[sid]
	return player_pos().distance_to(s["pos"]) <= float(s["radius"]) + 90.0


func nearest_settlement(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = p.distance_squared_to(s["pos"])
		if d < bd:
			bd = d
			best = int(s["id"])
	return best


# ---------------------------------------------------------------- roles and gating

func career() -> String:
	if career_override != "":
		return career_override
	return String(_au_get("Life", "career_id"))


## Number of player-owned things; subclasses override the pieces they own.
func _owns_enterprise() -> bool:
	return false


func is_lord() -> bool:
	return false


func has_merc_contract() -> bool:
	return false


func roles() -> Array:
	var out: Array = []
	if career() == "merchant" or license_owned or _owns_enterprise():
		out.append("merchant")
	if is_lord():
		out.append("lord")
	if career() == "soldier":
		out.append("soldier")
	if has_merc_contract():
		out.append("mercenary")
	if out.is_empty():
		out.append("commoner")
	return out


func has_role(r: String) -> bool:
	return roles().has(r)


func clan_tier() -> int:
	return 0


## "" when `action` is open to the player, else the reason it is not.
func can(action: String) -> String:
	var r := roles()
	match action:
		"trade":
			return ""
		"rumour":
			return ""
		"caravan", "workshop", "informant":
			if r.has("merchant") or r.has("lord"):
				return ""
			return "You need a trader's licence (%d gold) or a merchant career." % D.LICENSE_COST
		"road_works":
			if r.has("merchant") or r.has("lord"):
				return ""
			return "Only merchants and lords pay for road works."
		"fief":
			return "" if r.has("lord") else "You hold no land. Earn a fief through service, purchase or marriage."
		"recruit":
			if r.has("lord") or r.has("soldier") or r.has("mercenary") or clan_tier() >= 1:
				return ""
			return "Nobody follows a stranger. Earn renown (40) or serve a lord."
		"mercenary":
			if r.has("lord") or r.has("soldier") or clan_tier() >= 1:
				return ""
			return "Sellswords answer to a captain with a name. Earn renown first."
		"vassal":
			if r.has("lord") or clan_tier() >= 2:
				return ""
			return "A lord takes oaths only from landholders or a recognised clan."
		"duty":
			if r.has("soldier") or r.has("mercenary"):
				return ""
			return "Army duties are for soldiers and sworn mercenaries."
	return "Unknown action."


func buy_license() -> Dictionary:
	if license_owned:
		return {"ok": false, "reason": "You already hold a licence."}
	if gold() < D.LICENSE_COST:
		return {"ok": false, "reason": "You need %d gold." % D.LICENSE_COST}
	_pay(D.LICENSE_COST)
	license_owned = true
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------- supply, demand, price

func pop_of(sid: int) -> int:
	var st := _st()
	return int(st.call("population", sid)) if st != null else 100


func stock_of(sid: int, good: String) -> float:
	var st := _st()
	return float(st.call("supply_of", sid, good)) if st != null else 0.0


## The stock a settlement of that size considers normal.
func target(sid: int, good: String) -> float:
	var row: Dictionary = _tc.get(sid, {})
	if row.has(good):
		return float(row[good])
	var def: Dictionary = D.GOODS.get(good, {})
	var v := 10.0
	if not def.is_empty():
		var floor_v := 6.0 if good == "rift_crystal" else 12.0
		v = maxf(floor_v, float(pop_of(sid)) * float(def["dem"]) * 10.0)
	row[good] = v
	_tc[sid] = row
	return v


func reserve(sid: int, good: String) -> float:
	var frac := 0.2 if String(D.GOODS.get(good, {}).get("cat", "")) == "food" else 0.1
	return target(sid, good) * frac


## Units a trader could still carry away without emptying the town.
func available(sid: int, good: String) -> float:
	return maxf(0.0, stock_of(sid, good) - reserve(sid, good))


func _event_mod(sid: int, good: String) -> float:
	var cat := String(D.GOODS.get(good, {}).get("cat", ""))
	var row: Dictionary = _ec.get(sid, {})
	if row.has(cat):
		return float(row[cat])
	var m := 1.0
	var st := _st()
	if st != null:
		for e: Dictionary in st.call("emergencies", sid):
			match String(e["kind"]):
				"famine":
					m *= 1.35 if cat == "food" else 1.0
				"strike":
					m *= 1.15 if cat == "craft" else 1.0
				"raid_aftermath":
					m *= 1.12 if cat in ["food", "craft"] else 1.0
	row[cat] = m
	_ec[sid] = row
	return m


func clear_market_cache() -> void:
	_tc.clear()
	_ec.clear()


## Market price of one unit at the given stock level (-1 = the town's real stock).
func price_at(sid: int, good: String, stock_override := -1.0) -> float:
	var def: Dictionary = D.GOODS.get(good, {})
	if def.is_empty():
		return 1.0
	var s := stock_of(sid, good) if stock_override < 0.0 else stock_override
	var f := clampf(pow(target(sid, good) / (maxf(s, 0.0) + 1.0), PRICE_EXPONENT), PRICE_MIN, PRICE_MAX)
	return float(def["base"]) * f * _event_mod(sid, good)


func price(sid: int, good: String) -> int:
	return maxi(1, int(round(price_at(sid, good))))


## Trader's margin: a merchant haggles better, a good standing in town helps a little.
func spread_for_player(sid := -1) -> float:
	var s := D.SPREAD
	if career() == "merchant" or license_owned:
		s -= 0.025
	if sid >= 0:
		s -= 0.02 * clampf(standing(sid) / 100.0, 0.0, 1.0)
	return maxf(0.04, s)


func standing(_sid: int) -> float:
	return 40.0


func buy_price(sid: int, good: String) -> int:
	return maxi(1, int(round(price_at(sid, good) * (1.0 + spread_for_player(sid) * 0.5))))


func sell_price(sid: int, good: String) -> int:
	return maxi(1, int(round(price_at(sid, good) * (1.0 - spread_for_player(sid) * 0.5))))


## Bulk quote that walks the price along the stock as units move (prices react to you).
## side "buy" (the trader buys from the town) or "sell". opts: spread, stock (start level).
## Big lots are priced in up to 24 chunks at their mid-point stock: same curve, far fewer steps.
func quote(sid: int, good: String, qty: int, side: String, opts: Dictionary = {}) -> Dictionary:
	var spread: float = float(opts["spread"]) if opts.has("spread") else spread_for_player(sid)
	var s: float = float(opts["stock"]) if opts.has("stock") else stock_of(sid, good)
	var res := reserve(sid, good)
	var t := target(sid, good)
	var base := float((D.GOODS.get(good, {"base": 1}) as Dictionary)["base"]) * _event_mod(sid, good)
	var want := mini(qty, TRADE_CAP)
	var chunk := maxi(1, int(ceil(float(want) / 24.0)))
	var buy := side == "buy"
	var mult := 1.0 + spread * 0.5 if buy else 1.0 - spread * 0.5
	var total := 0.0
	var n := 0
	var first := 0.0
	var last := 0.0
	while n < want:
		var m := mini(chunk, want - n)
		if buy:
			var avail := s - res
			if avail < 1.0:
				break
			m = mini(m, int(floor(avail)))
		var mid := s - float(m - 1) * 0.5 if buy else s + float(m - 1) * 0.5
		var p := base * clampf(pow(t / (maxf(mid, 0.0) + 1.0), PRICE_EXPONENT), PRICE_MIN, PRICE_MAX) * mult
		if n == 0:
			first = p
		last = p
		total += p * float(m)
		n += m
		s += float(-m if buy else m)
	return {"qty": n, "total": int(round(total)), "avg": total / maxf(float(n), 1.0), "first": first, "last": last, "stock_after": s}


# ---------------------------------------------------------------- price intelligence

## Records what the player can see at `sid` right now. src: visit, caravan, informant, rumour, home.
func observe(sid: int, src := "visit", noise := 0.0, age := 0) -> void:
	if sid < 0 or sid >= WorldGen.settlements.size():
		return
	var d := {}
	var r := _rng("obs", _day, sid * 7 + age)
	for g: String in D.GOOD_ORDER:
		var p := price_at(sid, g)
		var n := stock_of(sid, g)
		if noise > 0.0:
			p *= r.randf_range(1.0 - noise, 1.0 + noise)
			n *= r.randf_range(1.0 - noise, 1.0 + noise)
		d[g] = {"p": int(round(p)), "n": int(round(n)), "d": _day - age, "src": src}
	seen[str(sid)] = d


func known_price(sid: int, good: String) -> Dictionary:
	var e: Dictionary = (seen.get(str(sid), {}) as Dictionary).get(good, {})
	if e.is_empty():
		return {}
	var out := e.duplicate()
	out["age"] = maxi(0, _day - int(e["d"]))
	return out


func is_known(sid: int) -> bool:
	return seen.has(str(sid))


func known_age(sid: int) -> int:
	var e: Dictionary = seen.get(str(sid), {})
	if e.is_empty():
		return -1
	var best := 99999
	for g: String in e:
		best = mini(best, _day - int((e[g] as Dictionary)["d"]))
	return maxi(0, best)


static func age_text(age: int) -> String:
	if age < 0:
		return "never seen"
	if age == 0:
		return "seen today"
	if age == 1:
		return "seen yesterday"
	return "seen %d days ago" % age


## Buy a round of gossip at an inn: three other towns' prices, blurred and a few days old.
func buy_rumour(sid: int) -> Dictionary:
	if gold() < D.RUMOUR_COST:
		return {"ok": false, "reason": "You need %d gold." % D.RUMOUR_COST, "towns": []}
	_pay(D.RUMOUR_COST)
	var ids: Array = []
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) != sid:
			ids.append(int(s["id"]))
	var r := _rng("rumour", _day, sid)
	var towns: Array = []
	while towns.size() < 3 and not ids.is_empty():
		var i := r.randi() % ids.size()
		towns.append(ids[i])
		ids.remove_at(i)
	for t: int in towns:
		observe(t, "rumour", 0.12, 1 + r.randi() % 3)
	return {"ok": true, "reason": "", "towns": towns}


func hire_informant(sid: int, days := 14) -> Dictionary:
	var why := can("informant")
	if why != "":
		return {"ok": false, "reason": why}
	if gold() < D.INFORMANT_COST:
		return {"ok": false, "reason": "You need %d gold." % D.INFORMANT_COST}
	_pay(D.INFORMANT_COST)
	informants[str(sid)] = _day + days
	observe(sid, "informant")
	return {"ok": true, "reason": ""}


func has_informant(sid: int) -> bool:
	return int(informants.get(str(sid), -1)) >= _day


# ---------------------------------------------------------------- the trader's pack

func capacity() -> int:
	return 40 + 10 * clan_tier() + (60 if _owns_cart() else 0)


func _owns_cart() -> bool:
	if cart_override:
		return true
	var ec: Variant = _au_get("Life", "economy")
	return ec != null and bool(ec.get("owns_cart"))


func pack_total() -> int:
	var t := 0
	for g: String in pack:
		t += int((pack[g] as Array)[0])
	return t


func pack_qty(good: String) -> int:
	return int((pack.get(good, [0, 0.0]) as Array)[0])


func pack_cost(good: String) -> float:
	return float((pack.get(good, [0, 0.0]) as Array)[1])


func _pack_add(good: String, n: int, unit_cost: float) -> void:
	var cur: Array = pack.get(good, [0, 0.0])
	var q := int(cur[0])
	var c := float(cur[1])
	pack[good] = [q + n, (c * q + unit_cost * n) / float(maxi(q + n, 1))]


func _pack_take(good: String, n: int) -> void:
	var cur: Array = pack.get(good, [0, 0.0])
	var left := int(cur[0]) - n
	if left <= 0:
		pack.erase(good)
	else:
		pack[good] = [left, float(cur[1])]


## Player buys `qty` of `good` at a settlement. Returns {ok, qty, paid, reason}.
func buy(sid: int, good: String, qty: int) -> Dictionary:
	if not D.GOODS.has(good) or qty <= 0:
		return {"ok": false, "qty": 0, "paid": 0, "reason": "Nothing to buy."}
	if not at_settlement(sid):
		return {"ok": false, "qty": 0, "paid": 0, "reason": "You are not in %s." % _sname(sid)}
	var room := capacity() - pack_total()
	if room <= 0:
		return {"ok": false, "qty": 0, "paid": 0, "reason": "Your pack is full (%d/%d)." % [pack_total(), capacity()]}
	var q := quote(sid, good, mini(qty, room), "buy")
	if int(q["qty"]) <= 0:
		return {"ok": false, "qty": 0, "paid": 0, "reason": "The market will not part with any more."}
	# Fewer units if the purse is short.
	var n: int = int(q["qty"])
	while n > 0 and int(q["total"]) > gold():
		n -= 1
		q = quote(sid, good, n, "buy")
	if n <= 0:
		return {"ok": false, "qty": 0, "paid": 0, "reason": "You cannot afford it."}
	var st := _st()
	st.call("add_stock", sid, good, -float(n))
	var paid: int = int(q["total"])
	_pay(paid)
	_pack_add(good, n, float(paid) / float(n))
	stats["traded"] = int(stats["traded"]) + paid
	rep_delta[str(sid)] = minf(30.0, float(rep_delta.get(str(sid), 0.0)) + float(paid) / 4000.0)
	observe(sid, "visit")
	return {"ok": true, "qty": n, "paid": paid, "reason": ""}


func sell(sid: int, good: String, qty: int) -> Dictionary:
	var have := pack_qty(good)
	if have <= 0 or qty <= 0:
		return {"ok": false, "qty": 0, "got": 0, "profit": 0, "reason": "You carry none."}
	if not at_settlement(sid):
		return {"ok": false, "qty": 0, "got": 0, "profit": 0, "reason": "You are not in %s." % _sname(sid)}
	var n := mini(qty, have)
	var q := quote(sid, good, n, "sell")
	var got: int = int(q["total"])
	var cost := int(round(pack_cost(good) * n))
	_st().call("add_stock", sid, good, float(n))
	_pack_take(good, n)
	_earn(got)
	var profit := got - cost
	stats["traded"] = int(stats["traded"]) + got
	stats["profit"] = int(stats["profit"]) + profit
	rep_delta[str(sid)] = minf(30.0, float(rep_delta.get(str(sid), 0.0)) + float(got) / 4000.0)
	if profit > 0:
		add_renown(float(profit) / 220.0, "trade")
	observe(sid, "visit")
	return {"ok": true, "qty": n, "got": got, "profit": profit, "reason": ""}


func add_renown(_amount: float, _why := "") -> void:
	pass


# ---------------------------------------------------------------- resources

func rift_positions() -> Array:
	if not _rift_built:
		_rift_built = true
		_rift_cache = []
		for s: Dictionary in WorldGen.sites:
			if String(s.get("kind", "")) in ["rift", "rift_outpost"]:
				_rift_cache.append(s["pos"])
	return _rift_cache


## 0..1 how close a settlement sits to a rift (they dig crystal there).
func rift_factor(sid: int) -> float:
	var best := INF
	var p := _spos(sid)
	for rp: Vector2 in rift_positions():
		best = minf(best, p.distance_to(rp))
	if best == INF:
		return 0.0
	return clampf(1.0 - best / D.RIFT_REACH, 0.0, 1.0)


## Per-day output of a settlement's supply chains: {good: units/day} (what it could make at full inputs).
func production_of(sid: int) -> Dictionary:
	var out := {}
	var st := _st()
	if st == null:
		return out
	var d: Dictionary = st.get("_s").get(sid, {})
	if d.is_empty():
		return out
	var chains: Dictionary = d["chains"]
	var defs: Dictionary = SettlementsScript.CHAINS
	for cid: String in chains:
		var n := int(chains[cid])
		if n <= 0 or not defs.has(cid):
			continue
		var def: Dictionary = defs[cid]
		for g: String in (def["outputs"] as Dictionary):
			out[g] = float(out.get(g, 0.0)) + float(n) * 4.0 * float((def["outputs"] as Dictionary)[g])
	var kind := _skind(sid)
	for g: String in D.LOCAL_GOODS:
		var gd: Dictionary = D.GOODS[g]
		var rate := float((gd["prod"] as Dictionary).get(kind, 0.0)) * float(pop_of(sid))
		if g == "rift_crystal":
			rate = rift_factor(sid) * float(pop_of(sid)) * 0.004
		if rate > 0.0:
			out[g] = rate
	return out


## What a settlement sells cheaply and what it is short of: {sells: [good], needs: [good]}.
func resources_of(sid: int) -> Dictionary:
	var sells: Array = []
	var needs: Array = []
	for g: String in D.GOOD_ORDER:
		var t := target(sid, g)
		var s := stock_of(sid, g)
		if s > t * 1.25:
			sells.append(g)
		elif s < t * 0.45 and String(D.GOODS[g]["cat"]) != "rare":
			needs.append(g)
		elif s < t * 0.45 and g == "rift_crystal":
			pass
	return {"sells": sells, "needs": needs, "makes": production_of(sid)}


# ---------------------------------------------------------------- routes, risk, tolls

func _camps() -> RefCounted:
	return _m("camps")


func _sh() -> RefCounted:
	return _m("strongholds")


func invalidate_routes() -> void:
	_route_cache.clear()
	clear_market_cache()


## Cached road-graph route between two settlements:
## {nodes, legs: [{a, b, hours, len}], hours (walker), length, risk (before guards), toll, rift, hostile}.
func route_info(a: int, b: int) -> Dictionary:
	var key := "%d|%d" % [a, b]
	if _route_cache.has(key):
		return _route_cache[key]
	var cm := _camps()
	var info := {"nodes": [], "legs": [], "hours": 0.0, "length": 0.0, "risk": 0.0, "toll": 0, "rift": false, "hostile": false, "owners": []}
	if cm == null or a == b:
		_route_cache[key] = info
		return info
	var path: Array = cm.call("route", a, b)
	if path.is_empty():
		var d := _spos(a).distance_to(_spos(b))
		info["hours"] = d * 2.2 / ROAD_M_PER_HOUR
		info["length"] = d
		info["risk"] = 0.14
		info["nodes"] = ["s%d" % a, "s%d" % b]
		info["legs"] = [{"a": "s%d" % a, "b": "s%d" % b, "hours": d * 2.2 / ROAD_M_PER_HOUR, "len": d}]
		_route_cache[key] = info
		return info
	var legs: Array = []
	var safe := 1.0
	var sh := _sh()
	var toll := 0
	var recent: Array = sh.call("recent_raid_results") if sh != null else []
	var rift_hit := false
	var hostile := false
	var owners: Array = []
	for i in range(path.size() - 1):
		var na: String = path[i]
		var nb: String = path[i + 1]
		var e: Dictionary = cm.call("road", na, nb)
		var ln := float(e.get("len", cm.call("node_pos", na).distance_to(cm.call("node_pos", nb))))
		var hrs := ln * float(cm.call("road_factor", na, nb)) / ROAD_M_PER_HOUR
		var r := float(cm.call("raid_risk", na, nb))
		var mid: Vector2 = (cm.call("node_pos", na) as Vector2).lerp(cm.call("node_pos", nb), 0.5)
		if sh != null and na.begins_with("s") and nb.begins_with("s"):
			var ctl: Dictionary = sh.call("controls_route", int(na.substr(1)), int(nb.substr(1)))
			if not ctl.is_empty():
				var own := String(ctl["owner"])
				if own != "player":
					toll += int(ctl["toll"])
				if own == "caldrenn":
					r *= 0.85
				elif own != "player":
					r += 0.06
					hostile = true
				owners.append(own)
		for rs: Dictionary in recent:
			if bool(rs["success"]) and (rs["pos"] as Vector2).distance_to(mid) < 500.0:
				r += 0.03
		for rp: Vector2 in rift_positions():
			if rp.distance_to(mid) < D.RIFT_DANGER_REACH:
				r += 0.10
				rift_hit = true
				break
		safe *= 1.0 - clampf(r, 0.0, 0.8)
		legs.append({"a": na, "b": nb, "hours": hrs, "len": ln, "risk": clampf(r, 0.0, 0.8)})
		info["hours"] = float(info["hours"]) + hrs
		info["length"] = float(info["length"]) + ln
	info["nodes"] = path
	info["legs"] = legs
	info["risk"] = 1.0 - safe
	info["toll"] = toll
	info["rift"] = rift_hit
	info["hostile"] = hostile
	info["owners"] = owners
	_route_cache[key] = info
	return info


func guard_factor(guards: int) -> float:
	return pow(1.0 - D.GUARD_RISK_REDUCTION, mini(guards, 6))


## Chance that something on the road takes a bite out of a trip.
func trip_risk(a: int, b: int, guards := 0, shortcut := false) -> float:
	var r := float(route_info(a, b)["risk"]) * guard_factor(guards)
	if shortcut:
		r *= D.SHORTCUT_RISK
	return clampf(r, 0.0, 0.9)


func trip_hours(a: int, b: int, cart := true, shortcut := false) -> float:
	var h := float(route_info(a, b)["hours"])
	if cart:
		h *= CARAVAN_SLOW
	if shortcut:
		h *= D.OFFROAD_SPEED
	return h


func trip_toll(a: int, b: int) -> int:
	return int(route_info(a, b)["toll"])


## Settlements reachable by the road graph, nearest first: [{sid, hours}].
func neighbours(sid: int, limit_hours := 30.0) -> Array:
	var out: Array = []
	for s: Dictionary in WorldGen.settlements:
		var o := int(s["id"])
		if o == sid:
			continue
		var h := trip_hours(sid, o)
		if h <= limit_hours:
			out.append({"sid": o, "hours": h})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["hours"]) < float(y["hours"]))
	return out


# ---------------------------------------------------------------- profit estimates

## Best single good to haul a -> b. Uses what the player KNOWS about b (or the base price if never
## seen), so the answer is only as good as the intel. opts: cap, budget, guards, spread, cash_only.
func estimate_leg(a: int, b: int, opts: Dictionary = {}) -> Dictionary:
	var cap: int = int(opts["cap"]) if opts.has("cap") else capacity()
	var budget: float = float(opts["budget"]) if opts.has("budget") else float(gold())
	var guards := int(opts.get("guards", 0))
	var spread: float = float(opts["spread"]) if opts.has("spread") else spread_for_player(a)
	var best := {"good": "", "qty": 0, "buy": 0, "sell": 0, "profit": 0, "known": false, "age": -1}
	var bestp := 0.0
	for g: String in D.GOOD_ORDER:
		var avail := int(floor(available(a, g)))
		if avail < 1:
			continue
		var unit := price_at(a, g) * (1.0 + spread * 0.5)
		var qmax := mini(mini(cap, avail), int(floor(budget / maxf(unit, 1.0))))
		if qmax < 1:
			continue
		var kp := known_price(b, g)
		var sell_stock: float
		if kp.is_empty():
			sell_stock = target(b, g)
		else:
			sell_stock = float(kp["n"])
		# quick prune: no unit margin, no haul
		var pb: float = float(kp["p"]) if not kp.is_empty() else price_at(b, g, sell_stock)
		if pb * (1.0 - spread * 0.5) <= unit:
			continue
		for frac: float in [1.0, 0.5]:
			var q := maxi(1, int(round(qmax * frac)))
			var cost := float(quote(a, g, q, "buy", {"spread": spread})["total"])
			var rev: float
			if kp.is_empty():
				rev = float(quote(b, g, q, "sell", {"spread": spread, "stock": sell_stock})["total"])
			else:
				# price the known quote: scale the projected revenue to the price that was seen
				var proj := quote(b, g, q, "sell", {"spread": spread, "stock": sell_stock})
				var at_seen := price_at(b, g, sell_stock) * (1.0 - spread * 0.5)
				var scale := float(kp["p"]) * (1.0 - spread * 0.5) / maxf(at_seen, 0.01) if float(kp["p"]) > 0.0 else 1.0
				rev = float(proj["total"]) * scale
			var profit := rev - cost
			if profit > bestp:
				bestp = profit
				best = {"good": g, "qty": q, "buy": int(round(cost)), "sell": int(round(rev)), "profit": int(round(profit)),
					"known": not kp.is_empty(), "age": int(kp.get("age", -1))}
	var risk := trip_risk(a, b, guards)
	var toll := trip_toll(a, b)
	best["hours"] = trip_hours(a, b) + 10.0
	best["risk"] = risk
	best["toll"] = toll
	best["expected"] = int(round(float(best["profit"]) * (1.0 - risk * 0.45) - float(toll)))
	return best


## Multi-stop plan over a list of settlement ids: per-leg goods, profit, days, risk, tolls.
## opts: cap, budget, guards, loop (return to the first town), wage (per day running costs).
func estimate_route(sids: Array, opts: Dictionary = {}) -> Dictionary:
	var stops: Array = sids.duplicate()
	if bool(opts.get("loop", false)) and stops.size() >= 2:
		stops.append(stops[0])
	var cash: float = float(opts["budget"]) if opts.has("budget") else float(gold())
	var start_cash := cash
	var legs: Array = []
	var hours := 0.0
	var safe := 1.0
	var toll := 0
	var profit := 0.0
	var guards := int(opts.get("guards", 0))
	for i in range(stops.size() - 1):
		var a := int(stops[i])
		var b := int(stops[i + 1])
		var o := opts.duplicate()
		o["budget"] = cash
		var leg := estimate_leg(a, b, o)
		leg["from"] = a
		leg["to"] = b
		legs.append(leg)
		cash += float(leg["profit"])
		profit += float(leg["profit"])
		hours += float(leg["hours"])
		safe *= 1.0 - float(leg["risk"])
		toll += int(leg["toll"])
	var days := hours / 24.0
	var wage := float(opts.get("wage", 0.0)) * days
	var risk := 1.0 - safe
	var loss := risk * 0.3 * (start_cash * 0.5 + profit)
	var net := profit - float(toll) - wage - loss
	var rift := false
	var hostile := false
	for i in range(stops.size() - 1):
		var ri := route_info(int(stops[i]), int(stops[i + 1]))
		rift = rift or bool(ri["rift"])
		hostile = hostile or bool(ri["hostile"])
	return {"stops": stops, "legs": legs, "profit": int(round(profit)), "hours": hours, "days": days, "risk": risk, "toll": toll,
		"wage": int(round(wage)), "loss": int(round(loss)), "net": int(round(net)), "per_day": int(round(net / maxf(days, 0.25))),
		"rift": rift, "hostile": hostile, "guards": guards}


## Every other town ranked by the expected profit of one run from `a` (for the planner).
func rank_destinations(a: int, opts: Dictionary = {}) -> Array:
	var out: Array = []
	for s: Dictionary in WorldGen.settlements:
		var b := int(s["id"])
		if b == a:
			continue
		var leg := estimate_leg(a, b, opts)
		leg["to"] = b
		out.append(leg)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["expected"]) > int(y["expected"]))
	return out


# ---------------------------------------------------------------- the local market day

func _local_day(d: int) -> void:
	var st := _st()
	if st == null:
		return
	var cm := _camps()
	# NPC traders along the roads pull stock toward normal faster where the roads are better.
	var tvs: Dictionary = {}
	var cnts: Dictionary = {}
	if cm != null:
		for e: Dictionary in cm.call("edges"):
			var tv := float(cm.call("trade_volume", e["a"], e["b"]))
			for end: String in [e["a"], e["b"]]:
				tvs[end] = float(tvs.get(end, 0.0)) + tv
				cnts[end] = int(cnts.get(end, 0)) + 1
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var pop := float(pop_of(sid))
		var kind := String(s["kind"])
		var mix := 0.02
		var key := "s%d" % sid
		if cnts.has(key):
			mix = clampf(0.012 + 0.018 * float(tvs[key]) / float(cnts[key]), 0.008, 0.06)
		for g: String in D.LOCAL_GOODS:
			var gd: Dictionary = D.GOODS[g]
			var t := target(sid, g)
			var cur := stock_of(sid, g)
			var prod := float((gd["prod"] as Dictionary).get(kind, 0.0)) * pop
			if g == "rift_crystal":
				prod = rift_factor(sid) * pop * 0.004
			var cons := float(gd["cons"]) * pop
			var delta := prod - cons
			if g != "rift_crystal":
				delta += (t - cur) * mix
			var nxt := clampf(cur + delta, 0.0, t * 6.0)
			st.call("add_stock", sid, g, nxt - cur)
