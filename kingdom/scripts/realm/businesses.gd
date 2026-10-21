extends "res://scripts/realm/realm_module.gd"
## Businesses (LW-4.3, docs/design/LIVING_WORLD_SANDBOX.md §10 and Part C): shop, workshop, inn, caravan company.
## One record `bz:n` with an account book (cash, in / out, 8 weeks of ledgers), debt, staff (the employment axis), ownership shares (the
## ownership axis: a character or an organization), a mode (manual / delegated / autonomous), a manager, and a ring of 8 reports.
##
## Real revenue and real expenses: customers come from the settlement's population and are shared among rivals by price and name; a shop
## sells stock it bought, a workshop turns inputs into products (never more value than its recipe yields), an inn sells beds and meals made
## of bread and ale from its stock, a caravan carries cargo bought at one town to another. Stock comes from three places only: a per-town
## wholesale pool that refills weekly and is shared by everyone, a farm parcel linked for vertical integration (farming.transfer_goods
## removes the units from the farm's store: nothing is created), or the business's own production. Goods spoil; nothing is conjured.
##
## Weekly accounts: wages, rent, upkeep, interest and purchases against sales. A balance below zero draws on credit (limit from recent
## earnings and stock); past the limit for two weeks the business is insolvent: restructure (owner injects cash, creditors take a haircut,
## half the staff go) or liquidate (stock and fixtures sold, debt repaid, staff released). Autonomous businesses decide this themselves, a
## manual (player) one is liquidated by its creditors after a grace period.
##
## Remote management: the owner of a delegated or autonomous business who is not in town sees only the DELIVERED reports (courier delay by
## distance); live() is for a present owner. A dishonest manager skims and under-reports; audit() finds it.
##
## Cost: no per-frame work. Every business settles its own week on a staggered day (7 days in one closed-form step), chunked BIZ_CHUNK per job.
## Saves ~200 B each (cap BIZ_CAP 500).

const FD := preload("res://scripts/realm/farming_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const Reg := preload("res://scripts/realm/registry.gd")

const BIZ_CAP := 500
const BIZ_CHUNK := 10
const REPORT_MAX := 8
const LEDGER_MAX := 8
const RESERVE := 60.0
const INTEREST := 0.015
const HAIRCUT := 0.3
const GRACE_DAYS := 21
const FAR_DAYS := 28
const RESTRUCTURE_DAYS := 28
const SPOIL := {"bread": 0.25, "ale": 0.04, "meat": 0.2, "wheat": 0.03, "barley": 0.03, "flax": 0.01, "flour": 0.06}
const WHOLESALE := 0.62
const MODES := ["manual", "delegated", "autonomous"]
## kind -> {cost: capital needed, fix: fixtures bought at once, rent: a week, max: staff, wage: a staff member's week, up: upkeep a week}
const KINDS := {
	"shop": {"cost": 300, "fix": 60, "rent": 14, "max": 3, "wage": 18, "up": 6},
	"workshop": {"cost": 450, "fix": 110, "rent": 16, "max": 4, "wage": 20, "up": 9},
	"inn": {"cost": 600, "fix": 150, "rent": 22, "max": 4, "wage": 16, "up": 12},
	"caravan": {"cost": 700, "fix": 250, "rent": 10, "max": 5, "wage": 22, "up": 14},
}
## Retail prices of what the businesses trade in.
const GOODS := {"bread": 4.0, "ale": 3.0, "cloth": 9.0, "tools": 16.0, "meat": 7.0, "iron": 6.0, "flour": 3.0, "wheat": 2.0, "barley": 2.0, "flax": 6.0}
const SHOP_GOODS := ["bread", "ale", "cloth", "tools", "meat"]
## recipe -> {in: input good, out: product, y: units made per input unit}
const RECIPES := {
	"bakery": {"in": "wheat", "out": "bread", "y": 1.5},
	"brewery": {"in": "barley", "out": "ale", "y": 2.0},
	"smithy": {"in": "iron", "out": "tools", "y": 0.7},
	"weaver": {"in": "flax", "out": "cloth", "y": 1.2},
}
const PROF_KIND := {"smith": ["workshop", "smithy"], "baker": ["workshop", "bakery"], "brewer": ["workshop", "brewery"], "weaver": ["workshop", "weaver"],
	"merchant": ["caravan", ""], "trader": ["caravan", ""], "farmer": ["workshop", "bakery"], "innkeeper": ["inn", ""]}

var _b: Dictionary = {}          # bz id -> business
var _ord: Array = []             # sorted ids (cache)
var _sup: Dictionary = {}        # sid -> {"w": week, good: units}
var _grp: Dictionary = {}        # "sid|kind|recipe" -> [ids] (derived)
var _grp_ok := false
var _own: Dictionary = {}        # owner -> [ids] (derived)
var _own_ok := false
var _war: Dictionary = {}        # group key -> day the war was first seen
var _pop: Dictionary = {}        # sid -> population override (tests)
var _own_n := 0
var _day := 0
var _sched: Dictionary = {}      # day -> [business ids to look at] (due queue)
var stats := {"founded": 0, "bankrupt": 0, "restructured": 0, "price_wars": 0, "sold_gold": 0, "wholesale_units": 0, "farm_units": 0, "made_units": 0,
	"input_units": 0, "wasted_units": 0, "sold_units": 0, "reports": 0, "npc_founded": 0}
var log_lines: Array = []


# ------------------------------------------------------------------ plumbing

func _rng(tag: String, d: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, d, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _orgm() -> RefCounted:
	return _mod("organizations")


func _mint() -> String:
	var reg := _mod("registry")
	if reg != null:
		var pid: String = reg.mint("bz")
		if pid != "":
			return pid
	_own_n += 1
	return "bz:%d" % (90000 + _own_n)


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, weight := 2) -> void:
	if hub != null:
		Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, weight)


func set_day(d: int) -> void:
	_day = d


func today() -> int:
	return _day


func set_population(sid: int, n: int) -> void:
	_pop[sid] = n


func population(sid: int) -> int:
	if _pop.has(sid):
		return int(_pop[sid])
	if sid >= 0 and sid < WorldSim.ranges.size():
		var rg: Vector2i = WorldSim.ranges[sid]
		return maxi(40, rg.y - rg.x)
	return 300


## Distance index between two settlements, 1 (next door) .. 8.
func distance_idx(a: int, b: int) -> int:
	if a == b:
		return 0
	if a >= 0 and b >= 0 and a < WorldGen.settlements.size() and b < WorldGen.settlements.size():
		var pa: Vector2 = WorldGen.settlements[a]["pos"]
		var pb: Vector2 = WorldGen.settlements[b]["pos"]
		return clampi(int(pa.distance_to(pb) / 600.0) + 1, 1, 8)
	return clampi(absi(a - b), 1, 8)


# ------------------------------------------------------------------ queries

func biz(bid: String) -> Dictionary:
	return _b.get(bid, {})


func exists(bid: String) -> bool:
	return _b.has(bid)


func ids() -> Array:
	if _ord.size() != _b.size():
		_ord = _b.keys()
		_ord.sort_custom(func(a: String, c: String) -> bool: return int(a.substr(3)) < int(c.substr(3)))
	return _ord


func count(active_only := true) -> int:
	if not active_only:
		return _b.size()
	var n := 0
	for k: String in _b:
		if String(_b[k]["st"]) in ["active", "restructuring", "insolvent"]:
			n += 1
	return n


func _live(b: Dictionary) -> bool:
	return String(b["st"]) in ["active", "restructuring", "insolvent"]


func owned_by(who: String) -> Array:
	if not _own_ok:
		_own = {}
		for k: String in ids():
			var b: Dictionary = _b[k]
			if not _live(b):
				continue
			for o: String in b["sh"]:
				if not _own.has(o):
					_own[o] = []
				(_own[o] as Array).append(k)
		_own_ok = true
	return (_own.get(who, []) as Array).duplicate()


func _dirty() -> void:
	_grp_ok = false
	_own_ok = false


func _gkey(b: Dictionary) -> String:
	return "%d|%s|%s" % [int(b["sid"]), b["kind"], b["rec"]]


func _group(b: Dictionary) -> Array:
	if not _grp_ok:
		_grp = {}
		for k: String in ids():
			var x: Dictionary = _b[k]
			if _live(x):
				var gk := String(x["gk"])
				if not _grp.has(gk):
					_grp[gk] = []
				(_grp[gk] as Array).append(k)
		_grp_ok = true
	return _grp.get(String(b["gk"]), [])


func rivals(bid: String) -> Array:
	var out: Array = []
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty():
		return out
	for k: String in _group(b):
		if k != bid:
			out.append(k)
	return out


func price_war_active(sid: int, kind: String) -> bool:
	for gk: String in _war:
		if gk.begins_with("%d|%s|" % [sid, kind]) and _day - int(_war[gk]) < 28:
			return true
	return false


func staff_count(bid: String) -> int:
	return (_b.get(bid, {}).get("staff", []) as Array).size()


func inventory_value(b: Dictionary) -> float:
	var v := 0.0
	for g: String in b["inv"]:
		v += float(b["inv"][g]) * float(GOODS.get(g, 2.0)) * WHOLESALE
	return v


# ------------------------------------------------------------------ founding

## Starts a business. `owner` is a character or an organization id; the capital leaves their purse or treasury. NPCs and the player call the
## same function.
func found(owner: String, kind: String, sid: int, nm := "", recipe := "", capital := -1, mode := "manual") -> Dictionary:
	if not KINDS.has(kind):
		return {"ok": false, "reason": "No such business."}
	if kind == "workshop" and not RECIPES.has(recipe):
		return {"ok": false, "reason": "A workshop needs a trade."}
	if _b.size() >= BIZ_CAP * 2 or count() >= BIZ_CAP:
		return {"ok": false, "reason": "The market has no room for another."}
	var kd: Dictionary = KINDS[kind]
	var cap := capital if capital >= 0 else int(kd["cost"])
	if cap < int(kd["cost"]):
		return {"ok": false, "reason": "It takes %d gold to start." % int(kd["cost"])}
	var om := _orgm()
	if om == null or not om.pay_from(owner, cap):
		return {"ok": false, "reason": "You cannot find %d gold." % cap}
	var bid := _mint()
	var pr: String = _mod("registry").mint("pr") if _mod("registry") != null else "pr:%d" % (90000 + _own_n)
	var n := int(Reg.parse(bid).get("n", 0))
	var label := recipe.capitalize() if recipe != "" else kind.capitalize()
	_b[bid] = {"id": bid, "owner": owner, "kind": kind, "rec": recipe, "name": nm if nm != "" else "%s of %s" % [label, bid], "sid": sid, "pr": pr,
		"st": "active", "mode": mode if mode in MODES else "manual", "mgr": {}, "bal": float(cap - int(kd["fix"])), "in": 0.0, "out": float(kd["fix"]),
		"wi": 0.0, "wo": 0.0, "debt": 0.0, "neg": 0, "staff": [], "inv": {}, "pm": 1.0, "rep": 10.0, "sh": {owner: 100}, "lk": [], "route": [sid, sid],
		"led": [], "rq": [], "rl": [], "born": _day, "lw": _day - (n % FAR_DAYS), "pl": _day + 1 + (n % 7), "att": _day, "cost": int(kd["cost"]), "skim": 0.0, "rs": 0, "rc": 0, "ins": -1,
		"avg": 0.0, "li": 0.0, "lo": 0.0, "end": -1, "wsk": 0.0, "dt": mode != "autonomous", "n": n, "gk": "%d|%s|%s" % [sid, kind, recipe], "at": 0.48, "ef": 1.0}
	_b[bid]["ef"] = _calc_eff(_b[bid])
	if _ord.size() == _b.size() - 1:
		_ord.append(bid)
	_plan(bid, int(_b[bid]["pl"]))
	_dirty()
	stats["founded"] = int(stats["founded"]) + 1
	_ev("founding", sid, [owner, bid], "business", "%s opens" % _b[bid]["name"], 2)
	return {"ok": true, "bz": bid}


func set_route(bid: String, from_sid: int, to_sid: int) -> bool:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or String(b["kind"]) != "caravan":
		return false
	b["route"] = [from_sid, to_sid]
	return true


func set_price(bid: String, pm: float) -> bool:
	if not _b.has(bid):
		return false
	_b[bid]["pm"] = clampf(pm, 0.5, 1.6)
	return true


func attend(bid: String) -> void:
	if _b.has(bid):
		_b[bid]["att"] = _day


func set_mode(bid: String, mode: String) -> bool:
	if not _b.has(bid) or mode not in MODES:
		return false
	_b[bid]["mode"] = mode
	_b[bid]["ef"] = _calc_eff(_b[bid])
	if mode != "autonomous":
		_b[bid]["dt"] = true
	return true


## Trade this business in detail (stock, spoilage, farm links) even though it runs itself.
func watch(bid: String, on := true) -> void:
	if _b.has(bid):
		_b[bid]["dt"] = on or String(_b[bid]["mode"]) != "autonomous" or not (_b[bid]["lk"] as Array).is_empty()


func appoint_manager(bid: String, ch: String, skill: float, honesty: float, wage := 25) -> bool:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or not _live(b):
		return false
	b["mgr"] = {"ch": ch, "sk": clampf(skill, 0.0, 1.0), "hon": clampf(honesty, 0.0, 1.0), "w": wage}
	b["ef"] = _calc_eff(b)
	var om := _orgm()
	if om != null:
		om.employ(ch, bid, wage)
	return true


func hire(bid: String, ch: String, wage := -1) -> Dictionary:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or not _live(b):
		return {"ok": false, "reason": "Closed."}
	var kd: Dictionary = KINDS[b["kind"]]
	if (b["staff"] as Array).size() >= int(kd["max"]):
		return {"ok": false, "reason": "No room for more hands."}
	for s: Dictionary in b["staff"]:
		if String(s["ch"]) == ch:
			return {"ok": false, "reason": "Already on the staff."}
	var om := _orgm()
	if om != null and not (om.employment(ch) as Dictionary).is_empty():
		return {"ok": false, "reason": "They already work for someone."}
	var w := wage if wage >= 0 else int(kd["wage"])
	(b["staff"] as Array).append({"ch": ch, "w": w})
	if om != null:
		om.employ(ch, bid, w)
	return {"ok": true}


func fire(bid: String, ch: String) -> bool:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty():
		return false
	var st: Array = b["staff"]
	for i in st.size():
		if String(st[i]["ch"]) == ch:
			st.remove_at(i)
			var om := _orgm()
			if om != null:
				om.unemploy(ch)
			return true
	return false


func transfer_shares(bid: String, from: String, to: String, pct: int, price: int) -> bool:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or int(b["sh"].get(from, 0)) < pct or pct <= 0:
		return false
	var om := _orgm()
	if om == null or not om.pay_from(to, price):
		return false
	om.pay_to(from, price)
	b["sh"][from] = int(b["sh"][from]) - pct
	if int(b["sh"][from]) == 0:
		b["sh"].erase(from)
	b["sh"][to] = int(b["sh"].get(to, 0)) + pct
	var top := ""
	var tp := -1
	for o: String in b["sh"]:
		if int(b["sh"][o]) > tp:
			tp = int(b["sh"][o])
			top = o
	b["owner"] = top
	_dirty()
	return true


## Vertical integration: a farm parcel feeds this business `per_week` units of `item`. Goods leave the farm's store, never appear from nothing.
func link_farm(bid: String, parcel: String, item: String, per_week: int) -> bool:
	var b: Dictionary = _b.get(bid, {})
	var fm := _mod("farming")
	if b.is_empty() or fm == null or fm.parcel(parcel).is_empty():
		return false
	(b["lk"] as Array).append({"p": parcel, "i": item, "q": per_week})
	b["dt"] = true                                    # goods really move: this one is traded in detail
	return true


# ------------------------------------------------------------------ money in and out

func _in(b: Dictionary, amt: float) -> void:
	b["bal"] = float(b["bal"]) + amt
	b["in"] = float(b["in"]) + amt
	b["wi"] = float(b["wi"]) + amt
	stats["sold_gold"] = int(stats["sold_gold"]) + int(amt)


func _out(b: Dictionary, amt: float) -> void:
	b["bal"] = float(b["bal"]) - amt
	b["out"] = float(b["out"]) + amt
	b["wo"] = float(b["wo"]) + amt


func _supply(sid: int, good: String, week: int) -> float:
	var s: Dictionary = _sup.get(sid, {})
	if s.is_empty() or int(s.get("w", -1)) != week:
		s = {"w": week}
		_sup[sid] = s
	if not s.has(good):
		s[good] = float(population(sid)) * 0.05 + 30.0
	return float(s[good])


func _take_supply(sid: int, good: String, qty: float, week: int) -> float:
	var have := _supply(sid, good, week)
	var n := minf(have, qty)
	_sup[sid][good] = have - n
	return n


## Buys up to `qty` of a good wholesale (from the town pool), as far as the cash allows. Returns the units bought.
func _buy(b: Dictionary, good: String, qty: float, week: int) -> float:
	if qty <= 0.0:
		return 0.0
	var unit := float(GOODS.get(good, 2.0)) * WHOLESALE
	var afford := maxf(0.0, float(b["bal"]) - 15.0) / unit
	var n := minf(qty, afford)
	n = _take_supply(int(b["sid"]), good, n, week)
	if n <= 0.0:
		return 0.0
	_out(b, n * unit)
	b["inv"][good] = float(b["inv"].get(good, 0.0)) + n
	stats["wholesale_units"] = int(stats["wholesale_units"]) + int(n)
	return n


func _pull_farms(b: Dictionary, days: int, need: Dictionary) -> void:
	var fm := _mod("farming")
	if fm == null:
		return
	for lk: Dictionary in b["lk"]:
		var item := String(lk["i"])
		var want := mini(int(ceil(float(lk["q"]) * float(days) / 7.0)), int(ceil(float(need.get(item, 0.0)))))
		if want <= 0:
			continue
		var P: Dictionary = fm.parcel(String(lk["p"]))
		if P.is_empty():
			continue
		var farm_who := "player" if _orgm() != null and _orgm()._is_player(String(b["owner"])) else String(b["owner"])
		var internal := String(P["owner"]) == farm_who
		var price := 0 if internal else int(ceil(float(FD.base_price(item)) * 0.9))
		if price > 0:
			want = mini(want, int(maxf(0.0, float(b["bal"]) - 15.0) / float(price)))
		var got: int = fm.transfer_goods(String(lk["p"]), item, want, price)
		if got > 0:
			if price > 0:
				_out(b, float(got * price))
			b["inv"][item] = float(b["inv"].get(item, 0.0)) + got
			stats["farm_units"] = int(stats["farm_units"]) + got


# ------------------------------------------------------------------ efficiency and share

func _eff(b: Dictionary) -> float:
	return float(b["ef"])


## Efficiency of whoever runs the business (cached: it changes only when the mode, the manager or the owner changes).
func _calc_eff(b: Dictionary) -> float:
	var m: Dictionary = b["mgr"]
	var om := _orgm()
	match String(b["mode"]):
		"delegated":
			return 0.9 + 0.1 * float(m.get("sk", 0.5)) if not m.is_empty() else 0.6
		"autonomous":
			var sk := 0.5
			var ow := String(b["owner"])
			if om != null and Reg.prefix_of(ow) == "ch":
				sk = om.skill_of(ow, "trading")
			elif not m.is_empty():
				sk = float(m.get("sk", 0.5))
			return 0.78 + 0.22 * sk
	return 1.0


func _attended(b: Dictionary) -> bool:
	return String(b["mode"]) != "manual" or _day - int(b["att"]) <= 7


func _share(b: Dictionary) -> float:
	var tot := 0.0
	for k: String in _group(b):
		tot += float(_b[k]["at"])
	return float(b["at"]) / tot if tot > 0.0 else 1.0


func _attract(b: Dictionary) -> float:
	var staff_f := 0.8 + 0.1 * float((b["staff"] as Array).size())
	return (0.5 + float(b["rep"]) / 100.0) * pow(1.0 / maxf(0.5, float(b["pm"])), 1.6) * staff_f


# ------------------------------------------------------------------ the week

## Resolves `days` days of trading in one closed-form step and closes the books. Normally called by the staggered day tick.
func settle(bid: String, days := 7, day := -1) -> void:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or not _live(b):
		return
	var d := day if day >= 0 else _day
	_day = maxi(_day, d)
	var kd: Dictionary = KINDS[b["kind"]]
	var week := d / 7
	var share := _share(b)
	var eff := _eff(b)
	var staff: Array = b["staff"]
	var restruct := String(b["st"]) == "restructuring"
	var served := 0.0
	var wanted := 0.0
	var rev0 := float(b["wi"])
	if bool(b["dt"]):
		match String(b["kind"]):
			"shop":
				var cust := minf(float(population(int(b["sid"]))) * 0.006 * share * (0.7 + 0.3 * float(b["rep"]) / 100.0), float(1 + staff.size()) * 30.0)
				var want_items := cust * days * 1.5
				var per_good := want_items / float(SHOP_GOODS.size())
				if _attended(b):
					var need: Dictionary = {}
					for g: String in SHOP_GOODS:
						need[g] = maxf(0.0, per_good - float(b["inv"].get(g, 0.0)))
					_pull_farms(b, days, need)
					for g2: String in SHOP_GOODS:
						var short := maxf(0.0, per_good - float(b["inv"].get(g2, 0.0)))
						_buy(b, g2, short * eff, week)
				for g3: String in SHOP_GOODS:
					var have := float(b["inv"].get(g3, 0.0))
					var sell := minf(have, per_good)
					wanted += per_good
					served += sell
					if sell > 0.0:
						b["inv"][g3] = have - sell
						stats["sold_units"] = int(stats["sold_units"]) + int(round(sell))
						_in(b, sell * float(GOODS[g3]) * float(b["pm"]))
			"workshop":
				var rc: Dictionary = RECIPES[b["rec"]]
				var inp := String(rc["in"])
				var outp := String(rc["out"])
				var cap_units := float(1 + staff.size()) * 3.0 * days
				var dem := float(population(int(b["sid"]))) * 0.012 * share * days
				if _attended(b):
					var need2: Dictionary = {inp: cap_units}
					_pull_farms(b, days, need2)
					var short2 := maxf(0.0, cap_units - float(b["inv"].get(inp, 0.0)))
					_buy(b, inp, short2 * eff, week)
				var make := minf(float(b["inv"].get(inp, 0.0)), cap_units)
				if make > 0.0:
					b["inv"][inp] = float(b["inv"][inp]) - make
					var prod := make * float(rc["y"])
					b["inv"][outp] = float(b["inv"].get(outp, 0.0)) + prod
					stats["made_units"] = int(stats["made_units"]) + int(prod)
					stats["input_units"] = int(stats["input_units"]) + int(make)
				var have2 := float(b["inv"].get(outp, 0.0))
				var sold := minf(have2, dem)
				wanted = dem
				served = sold
				if sold > 0.0:
					b["inv"][outp] = have2 - sold
					stats["sold_units"] = int(stats["sold_units"]) + int(round(sold))
					_in(b, sold * float(GOODS[outp]) * 0.9 * float(b["pm"]))
			"inn":
				var rooms := 8.0
				var guests := minf(float(population(int(b["sid"]))) * 0.0035 * share + 1.0, rooms)
				var room_price := 6.0 * float(b["pm"])
				if _attended(b):
					var need3: Dictionary = {"bread": guests * days, "ale": guests * days}
					_pull_farms(b, days, need3)
					for g4: String in ["bread", "ale"]:
						var short3 := maxf(0.0, guests * days - float(b["inv"].get(g4, 0.0)))
						_buy(b, g4, short3 * eff, week)
				var nights := guests * days
				_in(b, nights * room_price)
				var meals := minf(nights, minf(float(b["inv"].get("bread", 0.0)), float(b["inv"].get("ale", 0.0))))
				if meals > 0.0:
					b["inv"]["bread"] = float(b["inv"]["bread"]) - meals
					b["inv"]["ale"] = float(b["inv"]["ale"]) - meals
					stats["sold_units"] = int(stats["sold_units"]) + int(round(meals * 2.0))
					_in(b, meals * (4.0 + 3.0) * 0.8 * float(b["pm"]))
				wanted = nights
				served = nights
			"caravan":
				var rt: Array = b["route"]
				var dist := distance_idx(int(rt[0]), int(rt[1]))
				if dist > 0:
					var cycle := float(4 + dist)
					var trips := float(days) / cycle
					var cargo_cap := float(1 + staff.size()) * 20.0
					var good := "cloth" if (int(Reg.parse(String(b["id"])).get("n", 0)) % 2 == 0) else "tools"
					var units := 0.0
					if _attended(b):
						units = minf(cargo_cap * trips, _supply(int(rt[0]), good, week)) * eff
						var afford := maxf(0.0, float(b["bal"]) - 15.0) / (float(GOODS[good]) * WHOLESALE)
						units = minf(units, afford)
						units = _take_supply(int(rt[0]), good, units, week)
					if units > 0.0:
						var cost := units * float(GOODS[good]) * WHOLESALE
						_out(b, cost)
						var lost := 0.03
						var sell_price := float(GOODS[good]) * WHOLESALE * (1.0 + 0.3 + 0.05 * float(dist)) * float(b["pm"])
						_in(b, units * (1.0 - lost) * sell_price)
						served = units
						wanted = cargo_cap * trips
	else:
		var sw := _agg(b, days, share, eff)
		served = sw[0]
		wanted = sw[1]
	# Goods spoil.
	for g5: String in b["inv"].keys():
		var rate := float(SPOIL.get(g5, 0.0)) * float(days) / 7.0
		if rate > 0.0:
			var lose := float(b["inv"][g5]) * minf(0.9, rate)
			b["inv"][g5] = float(b["inv"][g5]) - lose
			stats["wasted_units"] = int(stats["wasted_units"]) + int(lose)
		if float(b["inv"][g5]) < 0.05:
			b["inv"].erase(g5)
	# A dishonest manager takes a cut and writes a better number in the report.
	var gross := float(b["wi"]) - rev0
	var skim := 0.0
	if String(b["mode"]) == "delegated" and not (b["mgr"] as Dictionary).is_empty():
		skim = (1.0 - float(b["mgr"]["hon"])) * 0.05 * gross
		if skim > 0.0:
			b["bal"] = float(b["bal"]) - skim
			b["skim"] = float(b["skim"]) + skim
	b["wsk"] = skim
	# Expenses of the week: wages, a manager, rent, upkeep (halved while restructuring), interest.
	var wk := float(days) / 7.0
	var om := _orgm()
	var wages := 0.0
	var paid_wages := 0.0
	for s: Dictionary in staff:
		wages += float(s["w"]) * wk
	if not (b["mgr"] as Dictionary).is_empty():
		wages += float(b["mgr"]["w"]) * wk
	var rent := float(kd["rent"]) * wk
	var upkeep := float(kd["up"]) * wk * (0.5 if restruct else 1.0)
	var interest := 0.0 if restruct else float(b["debt"]) * INTEREST * wk
	if float(b["bal"]) >= wages:
		paid_wages = wages
	else:
		paid_wages = maxf(0.0, float(b["bal"]))
	_out(b, paid_wages + rent + upkeep + interest)
	if om != null and paid_wages > 0.0:
		var share_w := paid_wages / maxf(1.0, wages)
		for s2: Dictionary in staff:
			om.earn(String(s2["ch"]), int(round(float(s2["w"]) * wk * share_w)))
		if not (b["mgr"] as Dictionary).is_empty():
			om.earn(String(b["mgr"]["ch"]), int(round(float(b["mgr"]["w"]) * wk * share_w)))
	# Reputation follows how many wanted customers were served.
	var ratio := served / wanted if wanted > 0.0 else 1.0
	b["rep"] = clampf(float(b["rep"]) * 0.9 + clampf(ratio, 0.0, 1.0) * 10.0, 0.0, 100.0)
	_close_week(b, d, days)


## Closed-form trading of a business nobody is watching: what the detailed week would earn with stock always on the shelf, scaled by the
## manager's efficiency. Returns [served, wanted] (units). Revenue and the wholesale cost go through the same books.
func _agg(b: Dictionary, days: int, share: float, eff: float) -> Array:
	var pop := float(population(int(b["sid"])))
	var staff_n := (b["staff"] as Array).size()
	var pm := float(b["pm"])
	var rep_f := 0.7 + 0.3 * float(b["rep"]) / 100.0
	match String(b["kind"]):
		"shop":
			var cust := minf(pop * 0.006 * share * rep_f, float(1 + staff_n) * 30.0)
			var items := cust * float(days) * 1.5 * eff
			_in(b, items * 7.8 * pm)
			_out(b, items * 7.8 * WHOLESALE)
			stats["sold_units"] = int(stats["sold_units"]) + int(items)
			return [items, cust * float(days) * 1.5]
		"workshop":
			var rc: Dictionary = RECIPES[b["rec"]]
			var cap_units := float(1 + staff_n) * 3.0 * days
			var dem := pop * 0.012 * share * days
			var make := minf(cap_units, dem / float(rc["y"])) * eff
			var prod := make * float(rc["y"])
			_out(b, make * float(GOODS[rc["in"]]) * WHOLESALE)
			_in(b, prod * float(GOODS[rc["out"]]) * 0.9 * pm)
			stats["made_units"] = int(stats["made_units"]) + int(prod)
			stats["input_units"] = int(stats["input_units"]) + int(make)
			stats["sold_units"] = int(stats["sold_units"]) + int(prod)
			return [prod, dem]
		"inn":
			var guests := minf(pop * 0.0035 * share + 1.0, 8.0)
			var nights := guests * days
			_in(b, nights * 6.0 * pm)
			_in(b, nights * eff * 7.0 * 0.8 * pm)
			_out(b, nights * eff * 7.0 * WHOLESALE)
			return [nights * eff, nights]
		"caravan":
			var rt: Array = b["route"]
			var dist := distance_idx(int(rt[0]), int(rt[1]))
			if dist > 0:
				var trips := float(days) / float(4 + dist)
				var units := float(1 + staff_n) * 20.0 * trips * eff
				var base := 12.5 * WHOLESALE                     # an average of cloth (9) and tools (16)
				_out(b, units * base)
				_in(b, units * 0.97 * base * (1.3 + 0.05 * float(dist)) * pm)
				return [units, float(1 + staff_n) * 20.0 * trips]
	return [0.0, 0.0]


func _close_week(b: Dictionary, d: int, days: int) -> void:
	var net := float(b["wi"]) - float(b["wo"])
	var led: Array = b["led"]
	# One row per settlement: [closing day, in, out, cash, debt, what the manager took]. Reports are views of these rows.
	b["avg"] = float(b["avg"]) * 0.7 + net * (0.3 * 7.0 / float(days) if days > 7 else 0.3)
	b["li"] = float(b["wi"])
	b["lo"] = float(b["wo"])
	var restruct := String(b["st"]) == "restructuring"
	# Credit.
	var limit := credit_limit(b)
	if float(b["bal"]) < 0.0:
		var need := -float(b["bal"]) + 20.0
		if float(b["debt"]) + need <= limit:
			b["debt"] = float(b["debt"]) + need
			b["bal"] = float(b["bal"]) + need
			b["neg"] = 0
		else:
			b["neg"] = int(b["neg"]) + 1
	else:
		b["neg"] = 0
		if float(b["debt"]) > 0.0 and float(b["bal"]) > RESERVE:
			var rep_pay := minf(float(b["debt"]), float(b["bal"]) - RESERVE)
			b["debt"] = float(b["debt"]) - rep_pay
			b["bal"] = float(b["bal"]) - rep_pay
	# Dividends for a business that earns beyond its needs (delegated and autonomous ones pay out; a manual owner withdraws).
	if String(b["mode"]) != "manual" and float(b["debt"]) <= 0.0 and float(b["bal"]) > RESERVE * 3.0 and not restruct:
		_pay_out(b, (float(b["bal"]) - RESERVE * 2.0) * 0.5)
	led.append([d, int(round(float(b["li"]))), int(round(float(b["lo"]))), int(round(float(b["bal"]))), int(round(float(b["debt"]))), int(round(float(b.get("wsk", 0.0))))])
	while led.size() > LEDGER_MAX:
		led.pop_front()
	# Reports reach an absent owner late (a body that runs itself needs none).
	if String(b["mode"]) != "autonomous":
		_report(b, d)
	# Insolvency.
	var st := String(b["st"])
	if st == "restructuring":
		if d >= int(b["rs"]):
			if float(b["avg"]) >= 0.0 and float(b["bal"]) >= 0.0:
				b["st"] = "active"
				b["ins"] = -1
				_ev("trade", int(b["sid"]), [String(b["id"])], "recovered", "%s is back on its feet" % b["name"], 2)
			else:
				b["st"] = "insolvent"
				b["ins"] = d
				b["rc"] = int(b["rc"]) + 1
	elif st == "active" and (int(b["neg"]) >= 2 or (float(b["debt"]) > limit * 1.4 and float(b["bal"]) < 0.0)):
		b["st"] = "insolvent"
		b["ins"] = d
		_ev("trade", int(b["sid"]), [String(b["id"])], "insolvent", "%s cannot pay its debts" % b["name"], 3)
	if String(b["st"]) == "insolvent":
		_resolve_insolvency(b, d)
	if _live(b) and String(b["mode"]) == "autonomous":
		_manage(b, d)
	b["wi"] = 0.0
	b["wo"] = 0.0
	b["lw"] = d
	b["at"] = _attract(b)


func credit_limit(b: Dictionary) -> float:
	return maxf(50.0, 3.0 * maxf(0.0, float(b["avg"])) + 0.4 * inventory_value(b) + 0.25 * float(b["cost"]))


func _pay_out(b: Dictionary, amt: float) -> void:
	var om := _orgm()
	if om == null or amt < 1.0:
		return
	var total := int(amt)
	var given := 0
	for o: String in b["sh"]:
		var part := total * int(b["sh"][o]) / 100
		if part > 0:
			om.pay_to(o, part)
			given += part
	b["bal"] = float(b["bal"]) - given
	b["out"] = float(b["out"]) + given


func _report(b: Dictionary, d: int) -> void:
	var delay := report_delay(b)
	b["rq"].append([d + delay, d])
	stats["reports"] = int(stats["reports"]) + 1
	if delay == 0:
		_deliver(b, d)


## Days a report takes to reach the owner: 0 when the owner is in town.
func report_delay(b: Dictionary) -> int:
	var om := _orgm()
	if om == null:
		return 0
	var ow := String(b["owner"])
	var osid := -1
	if Reg.prefix_of(ow) == "org":
		osid = int(om.org(ow).get("sid", -1))
	else:
		osid = int(om.char_rec(ow).get("sid", -1))
	if osid < 0 or osid == int(b["sid"]):
		return 0
	return 1 + distance_idx(osid, int(b["sid"]))


func _deliver(b: Dictionary, d: int) -> void:
	var rq: Array = b["rq"]
	var rl: Array = b["rl"]
	while not rq.is_empty() and int(rq[0][0]) <= d:
		var item: Array = rq.pop_front()
		rl.append([int(item[1]), d])
		while rl.size() > REPORT_MAX:
			rl.pop_front()


func _row(b: Dictionary, closing_day: int) -> Array:
	for r: Array in b["led"]:
		if int(r[0]) == closing_day:
			return r
	return []


## Reports that have reached the owner (what the manager wrote: the number hides whatever he took).
func reports(bid: String) -> Array:
	var out: Array = []
	var b: Dictionary = _b.get(bid, {})
	for rl: Array in b.get("rl", []):
		var r := _row(b, int(rl[0]))
		if r.is_empty():
			continue
		out.append({"wk": int(r[0]) / 7, "d": int(r[0]), "in": r[1], "out": r[2], "net": int(r[1]) - int(r[2]) + int(r[5]), "bal": r[3], "debt": r[4], "got": int(rl[1])})
	return out


## What an absent owner sees: the latest delivered report and how stale it is.
func owner_view(bid: String) -> Dictionary:
	var rs := reports(bid)
	if rs.is_empty():
		return {}
	var r: Dictionary = rs[-1]
	r["age"] = _day - int(r["d"])
	return r


## Live books, for an owner who is present only.
func live(bid: String) -> Dictionary:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty():
		return {}
	return {"bal": b["bal"], "debt": b["debt"], "in": b["wi"], "out": b["wo"], "st": b["st"], "staff": (b["staff"] as Array).size(), "stock": inventory_value(b)}


func accounts(bid: String) -> Array:
	return (_b.get(bid, {}).get("led", []) as Array).duplicate(true)


## The owner pays for an audit: how much a delegated manager took.
func audit(bid: String) -> Dictionary:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty():
		return {}
	var skim := float(b["skim"])
	return {"skimmed": snappedf(skim, 0.1), "honest": skim < 1.0}


func withdraw(bid: String, by: String, amt: int) -> bool:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or int(b["sh"].get(by, 0)) < 50 or float(b["bal"]) - float(amt) < RESERVE or amt <= 0:
		return false
	var om := _orgm()
	if om == null:
		return false
	b["bal"] = float(b["bal"]) - amt
	b["out"] = float(b["out"]) + amt
	om.pay_to(by, amt)
	return true


func inject(bid: String, by: String, amt: int) -> bool:
	var b: Dictionary = _b.get(bid, {})
	var om := _orgm()
	if b.is_empty() or om == null or not om.pay_from(by, amt):
		return false
	b["bal"] = float(b["bal"]) + amt
	return true


# ------------------------------------------------------------------ insolvency

func _resolve_insolvency(b: Dictionary, d: int) -> void:
	var om := _orgm()
	if String(b["mode"]) == "manual":
		# The player decides; the creditors do not wait forever.
		if d - int(b["ins"]) >= GRACE_DAYS:
			liquidate(String(b["id"]), "", "creditors")
		return
	var owner := String(b["owner"])
	var cash: int = om.purse(owner) if om != null and Reg.prefix_of(owner) == "ch" else (int(om.org(owner).get("treasury", 0)) if om != null else 0)
	var hopeful := float(b["li"]) >= float(b["lo"]) * 0.7 and int(b["rc"]) < 1
	if hopeful and float(cash) >= float(b["debt"]) * 0.3:
		restructure(String(b["id"]), owner)
	else:
		liquidate(String(b["id"]), "", "bankrupt")


## The owner puts money in, the creditors forgive a third of the debt, half the staff go, and the business has four weeks to turn around.
func restructure(bid: String, by: String) -> Dictionary:
	var b: Dictionary = _b.get(bid, {})
	var om := _orgm()
	if b.is_empty() or String(b["st"]) != "insolvent" or om == null or int(b["sh"].get(by, 0)) < 50:
		return {"ok": false, "reason": "Nothing to restructure."}
	var put := maxi(50, int(float(b["debt"]) * 0.25))
	if not om.pay_from(by, put):
		return {"ok": false, "reason": "You cannot find %d gold." % put}
	b["bal"] = float(b["bal"]) + put
	var cut := float(b["debt"]) * HAIRCUT
	b["debt"] = float(b["debt"]) - cut
	var st: Array = b["staff"]
	while st.size() > (st.size() + 1) / 2 and st.size() > 1:
		var gone: Dictionary = st.pop_back()
		om.unemploy(String(gone["ch"]))
	b["st"] = "restructuring"
	b["rs"] = _day + RESTRUCTURE_DAYS
	b["neg"] = 0
	b["pm"] = 1.0
	stats["restructured"] = int(stats["restructured"]) + 1
	_ev("trade", int(b["sid"]), [bid, by], "restructure", "%s is restructured" % b["name"], 3)
	return {"ok": true, "forgiven": int(cut)}


## Sells stock and fixtures, repays the debt, releases the staff. What is left goes to the owners by share.
func liquidate(bid: String, by: String, why := "closed") -> Dictionary:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty() or not _live(b):
		return {"ok": false}
	if by != "" and int(b["sh"].get(by, 0)) < 50:
		return {"ok": false, "reason": "It is not yours to close."}
	var om := _orgm()
	var proceeds := float(b["bal"]) + inventory_value(b) * 0.5 + float(KINDS[b["kind"]]["fix"]) * 0.3
	var left := proceeds - float(b["debt"])
	if left > 0.0 and om != null:
		var total := int(left)
		for o: String in b["sh"]:
			var part := total * int(b["sh"][o]) / 100
			if part > 0:
				om.pay_to(o, part)
	for s: Dictionary in b["staff"]:
		if om != null:
			om.unemploy(String(s["ch"]))
	if not (b["mgr"] as Dictionary).is_empty() and om != null:
		om.unemploy(String(b["mgr"]["ch"]))
	b["staff"] = []
	b["mgr"] = {}
	b["inv"] = {}
	b["bal"] = 0.0
	b["debt"] = 0.0
	b["st"] = "closed"
	b["end"] = _day
	stats["bankrupt"] = int(stats["bankrupt"]) + 1
	for o2: String in b["sh"]:
		if om != null and Reg.prefix_of(o2) == "ch":
			om.add_reputation(o2, -2.0 if why in ["bankrupt", "creditors"] else 0.0)
	_dirty()
	_ev("trade", int(b["sid"]), [bid, String(b["owner"])], why, "%s closes (%s)" % [b["name"], why], 3)
	return {"ok": true, "returned": int(maxf(0.0, left))}


# ------------------------------------------------------------------ autonomous owners

func _manage(b: Dictionary, d: int) -> void:
	var roll := float(absi(hash([WorldSim.SEED, "bm", d, b["n"]])) % 1000) / 1000.0
	var roll2 := float(absi(hash([WorldSim.SEED, "bm2", d, b["n"]])) % 1000) / 1000.0
	var bid := String(b["id"])
	# Price war: follow a cheaper rival down, creep back up when alone.
	var min_pm := 9.0
	var n_low := 0
	for k: String in _group(b):
		if k == bid:
			continue
		var rp := float(_b[k]["pm"])
		min_pm = minf(min_pm, rp)
		if rp <= 0.88:
			n_low += 1
	var pm := float(b["pm"])
	if min_pm < pm - 0.04 and float(b["bal"]) > RESERVE:
		b["pm"] = maxf(0.7, pm - 0.06)
	elif min_pm >= pm - 0.01 and pm < 1.0 and roll < 0.5:
		b["pm"] = minf(1.0, pm + 0.03)
	# A hungry business with a rival in town sometimes tries to win customers by undercutting.
	if min_pm < 9.0 and float(b["avg"]) < 0.06 * float(b["cost"]) and float(b["pm"]) >= 0.99 and roll2 < 0.5 and float(b["bal"]) > RESERVE:
		b["pm"] = 0.88
	if float(b["pm"]) <= 0.88 and n_low >= 1:
		var gk := String(b["gk"])
		if not _war.has(gk) or d - int(_war[gk]) >= 28:
			stats["price_wars"] = int(stats["price_wars"]) + 1
			_war[gk] = d
			_ev("trade", int(b["sid"]), [bid], "price_war", "A price war breaks out", 3)
	# Take on a hand when business is good; let one go when it is bad.
	var staff: Array = b["staff"]
	if float(b["avg"]) > 25.0 and staff.size() < int((KINDS[b["kind"]] as Dictionary)["max"]) and float(b["bal"]) > RESERVE * 2.0:
		var om := _orgm()
		if om != null:
			var pool: Array = om.unemployed_npcs(int(b["sid"]), 3)
			if not pool.is_empty():
				hire(bid, String(pool[0]))
	elif float(b["avg"]) < -8.0 and staff.size() > 1:
		fire(bid, String(staff[-1]["ch"]))


# ------------------------------------------------------------------ NPC founding

func npc_try_found(ch: String, day: int) -> bool:
	var om := _orgm()
	if om == null or count() >= BIZ_CAP:
		return false
	var rec: Dictionary = om.char_rec(ch)
	if rec.is_empty() or not owned_by(ch).is_empty():
		return false
	var prof := String(rec["prof"])
	var pk: Array = PROF_KIND.get(prof, ["shop", ""])
	var kind := String(pk[0])
	var recipe := String(pk[1])
	var sid := int(rec["sid"])
	if sid < 0:
		return false
	# One more of a kind only where the town can feed it.
	var same := 0
	for k: String in ids():
		var x: Dictionary = _b[k]
		if _live(x) and int(x["sid"]) == sid and String(x["kind"]) == kind:
			same += 1
	if same >= maxi(1, population(sid) / 140):
		return false
	if kind == "workshop" and recipe == "":
		recipe = RECIPES.keys()[absi(hash([ch, "rec"])) % RECIPES.size()]
	var cost := int(KINDS[kind]["cost"])
	if int(rec["cash"]) < cost + 40:
		return false
	var res := found(ch, kind, sid, "", recipe, cost, "autonomous")
	if bool(res.get("ok", false)):
		stats["npc_founded"] = int(stats["npc_founded"]) + 1
		if kind == "caravan":
			var other := (sid + 1 + absi(hash([ch, "rt"])) % 3) % maxi(1, WorldSim.ranges.size())
			set_route(String(res["bz"]), sid, other if other != sid else sid + 1)
		return true
	return false


# ------------------------------------------------------------------ day tick

func _plan(bid: String, d: int) -> void:
	if _sched.has(d):
		(_sched[d] as Array).append(bid)
	else:
		_sched[d] = [bid]


func _wake(bid: String, d: int) -> void:
	var b: Dictionary = _b.get(bid, {})
	if b.is_empty():
		return
	var pl := int(b["pl"])
	if pl > _day and pl <= d:
		return
	b["pl"] = d
	_plan(bid, d)


## Days between two settlements: a business traded in detail, or in trouble, every week; a quiet one that runs itself once a month.
func _gap(b: Dictionary) -> int:
	if bool(b["dt"]) or String(b["st"]) != "active" or int(b["neg"]) > 0 or float(b["bal"]) < RESERVE:
		return 7
	return FAR_DAYS


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var due: Array = []
	var seen := {}
	for d: int in _sched.keys():
		if d <= day:
			for k: String in _sched[d]:
				if not seen.has(k):
					seen[k] = true
					due.append(k)
			_sched.erase(d)
	var out: Array = []
	var i := 0
	while i < due.size():
		var part := due.slice(i, i + BIZ_CHUNK)
		out.append(func() -> Array: return _chunk(part, day))
		i += BIZ_CHUNK
	return out


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _chunk(part: Array, day: int) -> Array:
	for k: String in part:
		var b: Dictionary = _b.get(k, {})
		if b.is_empty():
			continue
		if not _live(b):
			if String(b["st"]) == "closed" and day - int(b["end"]) > 60:
				_b.erase(k)
				_ord = []
				_dirty()
			else:
				_plan(k, day + 30)
			continue
		if int(b["pl"]) > day:
			continue                                   # an older wake-up; the live one is later
		if not (b["rq"] as Array).is_empty():
			_deliver(b, day)
		if day - int(b["lw"]) >= _gap(b):
			settle(k, day - int(b["lw"]), day)
			if not _live(b):
				_dirty()
				_plan(k, day + 61)
				b["pl"] = day + 61
				continue
		var nxt: int = int(b["lw"]) + _gap(b)
		if not (b["rq"] as Array).is_empty():
			nxt = mini(nxt, int(b["rq"][0][0]))
		nxt = maxi(nxt, day + 1)
		b["pl"] = nxt
		_plan(k, nxt)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	var weeks := days / 7
	if weeks <= 0:
		_day += days
		return []
	for k: String in ids():
		var b: Dictionary = _b[k]
		if not _live(b):
			continue
		var d := _day + 7
		settle(k, 7, d)
		if _live(b) and weeks > 1:
			var net := float(b["li"]) - float(b["lo"])
			b["bal"] = float(b["bal"]) + net * float(weeks - 1)
			if float(b["bal"]) < -credit_limit(b):
				liquidate(k, "", "bankrupt")
		b["lw"] = _day + days
		if _live(b):
			_deliver(b, _day + days)
			_wake(k, _day + days + 1)
	_day += days
	return []


# ------------------------------------------------------------------ save

func _blank() -> Dictionary:
	return {"rec": "", "mgr": {}, "in": 0.0, "out": 0.0, "wi": 0.0, "wo": 0.0, "debt": 0.0, "neg": 0, "staff": [], "inv": {}, "pm": 1.0, "lk": [], "led": [], "rq": [],
		"rl": [], "skim": 0.0, "rs": 0, "rc": 0, "ins": -1, "avg": 0.0, "li": 0.0, "lo": 0.0, "end": -1, "wsk": 0.0, "st": "active", "att": 0, "ef": 1.0, "at": 0.48}


## Only the fields that differ from a blank business are written, floats rounded to a tenth.
func _pack(b: Dictionary) -> Dictionary:
	var blank := _blank()
	var out := {}
	for k: String in b:
		if k == "id" or k == "pl":
			continue
		var v: Variant = b[k]
		if blank.has(k) and v == blank[k]:
			continue
		if v is float:
			v = snappedf(float(v), 0.01 if k == "ef" or k == "at" else 0.1)
		elif k == "inv":
			var inv := {}
			for g: String in v:
				inv[g] = snappedf(float(v[g]), 0.1)
			v = inv
		out[k] = v
	return out


func serialize() -> Dictionary:
	var packed := {}
	for k: String in _b:
		packed[k] = _pack(_b[k])
	return {"b": packed, "sup": _sup.duplicate(true), "war": _war.duplicate(), "day": _day, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_b = {}
	_sup = {}
	_war = {}
	_sched = {}
	_ord = []
	_dirty()
	var b: Variant = d.get("b", {})
	if b is Dictionary:
		for k: String in b:
			if b[k] is Dictionary:
				var full := _blank()
				full["id"] = k
				for f: String in b[k]:
					full[f] = b[k][f]
				_b[k] = _fix(full)
	for k2: String in _b:
		var bb: Dictionary = _b[k2]
		bb["pl"] = int(d.get("day", 0)) + 1 + (int(bb["n"]) % 7)
		_plan(k2, int(bb["pl"]))
	var s: Variant = d.get("sup", {})
	if s is Dictionary:
		for k: String in s:
			var sd: Dictionary = s[k]
			_sup[int(k)] = sd
			sd["w"] = int(sd["w"])
	var w: Variant = d.get("war", {})
	if w is Dictionary:
		for k: String in w:
			_war[k] = int(w[k])
	_day = int(d.get("day", 0))
	var st: Variant = d.get("st", {})
	if st is Dictionary:
		for k: String in st:
			stats[k] = int(st[k])


func _fix(v: Dictionary) -> Dictionary:
	var b: Dictionary = v.duplicate(true)
	for k: String in ["sid", "neg", "born", "lw", "att", "cost", "rs", "rc", "ins", "end", "n"]:
		b[k] = int(b.get(k, 0))
	for k2: String in ["bal", "in", "out", "wi", "wo", "debt", "pm", "rep", "skim", "avg", "li", "lo", "wsk", "ef", "at"]:
		b[k2] = float(b.get(k2, 0.0))
	for o: String in (b["sh"] as Dictionary):
		b["sh"][o] = int(b["sh"][o])
	for i in (b["route"] as Array).size():
		b["route"][i] = int(b["route"][i])
	for s: Dictionary in b["staff"]:
		s["w"] = int(s["w"])
	for lk: Dictionary in b["lk"]:
		lk["q"] = int(lk["q"])
	for row: Array in b["led"]:
		for i in row.size():
			row[i] = int(row[i])
	for rq: Array in b["rq"]:
		rq[0] = int(rq[0])
		rq[1] = int(rq[1])
	for rl: Array in b["rl"]:
		rl[0] = int(rl[0])
		rl[1] = int(rl[1])
	for g: String in (b["inv"] as Dictionary):
		b["inv"][g] = float(b["inv"][g])
	if not b.has("gk"):
		b["gk"] = _gkey(b)
	return b
