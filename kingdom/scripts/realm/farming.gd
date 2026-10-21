extends "res://scripts/realm/realm_module.gd"
## Farming as a career (Living World Stage 3, LW-3.1 / 3.2 / 3.3; docs/design/LIVING_WORLD_SANDBOX.md section 3).
##
## One connected loop, all plain data (no nodes). A *parcel* is a farm: a deed with an owner, a tenant with rights, a lien, fields,
## a herd, buildings, a store and a ledger. The player and the NPC farmers of WorldSim hold parcels through the same calls.
##
##   Ladder    farmhand (wage work for an NPC farmer) -> sharecropper (works a landlord's fields for a share) -> tenant (rents) ->
##             owner (holds a deed) -> estate (several farms, a steward). rung(who) is derived from what you hold; take_tenancy / buy
##             enforce the requirements (experience, deposit, a season as tenant).
##   Land      list_for_sale + bid (escrowed) + close_sale, buy_direct from the Crown, sell_to, list_for_let + bid_tenancy, rent_out,
##             mortgage / repay, transfer, evict. A sale keeps the lien, the tenant's lease and the wages owed with the land.
##   Fields    farming_fields.gd: fertility drawn down by cropping, rotation, season and climate, moisture and irrigation, pests and blight
##             spreading to neighbouring fields, weeds, seed stock, spoilage in the store.
##   Work      sow / harvest / treat / weed / water / manure. do_task() is the ONE code path: the player calls it, hired workers
##             (recruitment property chain: group + manager + mode) call it from the day tick. Yield is a pure function of the field, so manual,
##             delegated and autonomous farms earn the same; the mode only changes who decides (plan, seed, sales) and who can skim.
##   Herd      farming_herd.gd: individual animals near the player, one cohort per species when far; feed, water, shelter, breeding, ageing,
##             sickness, theft; dairy / wool / horse specialisations.
##   Build     build(pid, kind): field, barn, granary, pen, cottage, well, irrigation, fence, mill as construction staged sites
##             (place_kit_plan for the player, npc_place for NPC farms); the effect starts when the site is done.
##   Economy   sell_goods() feeds the settlement market's stock and so its price; garrison supply contracts (strongholds) at a premium.
##   NPCs      every WorldSim settlement seeds farms held by farmer rows; they rent, bid on land (and can outbid the player), expand, borrow
##             and go bust. Far farms step weekly on expected values; the player's own farms and near ones step daily.
## Money rule: the purse is never touched; Life drains take_pending_gold() (like construction / recruitment).
## Ids: a parcel is the registry's "pr:<n>" (hub.mod("registry").mint("pr")); who is "player", "npc:<row>", "lord:<sid>" or "bank:<sid>".

const D := preload("res://scripts/realm/farming_data.gd")
const FF := preload("res://scripts/realm/farming_fields.gd")
const FH := preload("res://scripts/realm/farming_herd.gd")
const Events := preload("res://scripts/realm/events.gd")

const NEAR_RADIUS := 150.0
const FAR_STEP := 7
const CHUNK_FARMS := 5
const NPC_FARMS_MAX := 24
const WAGE_HAND := 5               # a farmhand's day, paid by the farmer
const HAND_LABOUR := 2.0           # task units one worker does in a day
const NPC_LABOUR := 2.6
const LIVING_COST := 1.8           # an NPC farmer's household, per day
const HAND_COST := 3
const EXP_TENANT := 6              # workdays before a landlord lets you rent
const EXP_SHARE := 3
const EXP_OWNER := 30
const TASK_COST := {"harvest": 1.0, "sow": 1.0, "treat": 0.5, "weed": 0.4, "water": 0.3, "manure": 0.5}
const MODES := ["manual", "delegated", "autonomous"]
const EVICT_GRACE := 7
const SHARE_NOTICE := 14
const CONTRACT_DAYS := 10
const BUST_DAYS := 21
const REL_FLOOR := 0.5             # a farm will not sell below this share of the base price unless the goods would spoil

var _p: Dictionary = {}            # pid -> parcel
var _f: Dictionary = {}            # who -> NPC farmer {row, sid, name, cash, amb, neg, bust, busts}
var _ct: Array = []                # garrison supply contracts
var _pl := {"exp": 0, "fh": "", "fh_days": 0, "last": -1, "rung": "", "rep": 0, "season_tenant": 0}
var _next_c := 1
var _own_n := 0
var _day := 0
var _inited := false
var _order: Array = []             # sorted parcel ids (cache)
var _idx_owner: Dictionary = {}    # who -> parcel ids held (cache, rebuilt after any change of hands)
var _idx_tenant: Dictionary = {}   # who -> parcel ids rented
var _idx_ok := false
var _fids: Array = []              # sorted NPC farmer ids (cache)
var _damp: Dictionary = {}         # settlement id -> true once its abstract crop supply was handed to the real farms
var stats := {"busts": 0, "sales": 0, "npc_buys": 0, "outbid": 0, "harvests": 0, "thefts": 0, "contracts": 0, "evictions": 0, "seized": 0, "built": 0}
var pending_gold := 0
var gold_ref: Variant = null       # Dictionary {"gold": n} for tests; null = Game.gold
var market_ref: Variant = null     # Dictionary sid -> RAMarket for tests; null = Life.economy.markets
var player_pos := Vector2(1e9, 1e9)
var log_lines: Array = []


# ------------------------------------------------------------------ plumbing

func _rng(tag: String, d: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, d, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _rec() -> RefCounted:
	return _mod("recruitment")


func _cons() -> RefCounted:
	return _mod("construction")


func set_day(d: int) -> void:
	_day = d


func today() -> int:
	return _day


func gold_available() -> int:
	var g := 0
	if gold_ref is Dictionary:
		g = int((gold_ref as Dictionary).get("gold", 0))
	else:
		g = Game.gold
	return g + pending_gold


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 20:
		log_lines.pop_front()


## Can `who` pay `amt` now? Lords and banks always can.
func can_pay(who: String, amt: int) -> bool:
	if amt <= 0:
		return true
	if who == "player":
		return gold_available() >= amt
	if _f.has(who):
		return int(_f[who]["cash"]) >= amt
	return who.begins_with("lord:") or who.begins_with("bank:")


func _pay(who: String, amt: int) -> bool:
	if amt <= 0:
		return true
	if not can_pay(who, amt):
		return false
	if who == "player":
		pending_gold -= amt
	elif _f.has(who):
		_f[who]["cash"] = int(_f[who]["cash"]) - amt
	return true


func _earn(who: String, amt: int) -> void:
	if amt <= 0:
		return
	if who == "player":
		pending_gold += amt
	elif _f.has(who):
		_f[who]["cash"] = int(_f[who]["cash"]) + amt


func _mint() -> String:
	var reg := _mod("registry")
	if reg != null and reg.has_method("mint"):
		var pid: String = reg.mint("pr")
		if pid != "":
			return pid
	_own_n += 1
	return "pr:f%d" % _own_n


func who_name(who: String) -> String:
	if who == "player":
		return "you"
	if _f.has(who):
		return String(_f[who]["name"])
	if who.begins_with("lord:"):
		return "the Crown's steward"
	if who.begins_with("bank:"):
		return "the money-lender"
	return who


func _ev(kind: String, pid: String, actors: Array, cause: String, outcome: String, weight := 2) -> void:
	if hub == null:
		return
	var acts: Array = []
	for a: Variant in actors:
		var s := String(a)
		if s.begins_with("npc:") and s.substr(4).is_valid_int():
			acts.append("ws:" + s.substr(4))
		else:
			acts.append(s)
	Events.log_to(hub, kind, pid, acts, cause, outcome, weight)


# ------------------------------------------------------------------ parcels

func parcel(pid: String) -> Dictionary:
	return _p.get(pid, {})


func parcels() -> Array:
	if _order.size() != _p.size():
		_order = _p.keys()
		_order.sort_custom(func(a: String, b: String) -> bool: return _num(a) < _num(b))
	return _order


static func _num(pid: String) -> int:
	var i := pid.find(":")
	var s := pid.substr(i + 1)
	if s.begins_with("f"):
		s = s.substr(1)
	return int(s)


func _reindex() -> void:
	_idx_owner.clear()
	_idx_tenant.clear()
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		var o := String(P["owner"])
		if not _idx_owner.has(o):
			_idx_owner[o] = []
		(_idx_owner[o] as Array).append(pid)
		var t: Dictionary = P["ten"]
		if not t.is_empty():
			var w := String(t["who"])
			if not _idx_tenant.has(w):
				_idx_tenant[w] = []
			(_idx_tenant[w] as Array).append(pid)
	_idx_ok = true


func parcels_of(who: String) -> Array:
	if not _idx_ok:
		_reindex()
	return (_idx_owner.get(who, []) as Array).duplicate()


func rented_by(who: String) -> Array:
	if not _idx_ok:
		_reindex()
	return (_idx_tenant.get(who, []) as Array).duplicate()


func operator(P: Dictionary) -> String:
	var t: Dictionary = P["ten"]
	return String(t["who"]) if not t.is_empty() else String(P["owner"])


func is_vacant(pid: String) -> bool:
	var P: Dictionary = _p.get(pid, {})
	return not P.is_empty() and (P["ten"] as Dictionary).is_empty() and (String(P["owner"]).begins_with("lord:") or String(P["owner"]).begins_with("bank:"))


## Create a farm. `owner` is a who string. Returns the parcel id.
const DEFAULT_PLAN := ["wheat", "peas", "barley", "turnip"]


func _kind_of(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid].get("kind", "village"))
	return "village"


func found_parcel(sid: int, pos: Vector2, fields_n: int, owner: String, nm := "", fertility := -1.0) -> String:
	var pid := _mint()
	var kind := _kind_of(sid)
	var P := {"id": pid, "name": nm if nm != "" else "Farm %s" % pid.substr(3), "sid": sid, "kind": kind, "pos": [pos.x, pos.y],
		"clim": D.climate_of(sid), "owner": owner, "ten": {}, "mort": {}, "wo": 0, "sale": {}, "let": {},
		"fields": [], "bld": [], "herd": [], "co": {}, "lod": 0, "spec": "", "store": {}, "ls": {}, "plan": DEFAULT_PLAN.duplicate(),
		"mode": "manual", "gid": "", "stw": "", "hands": 0, "inc": 0.0, "out": 0.0, "wt": _rng("wt", 0, pid).randf() < 0.7,
		"last": _day, "tx": -1, "stolen": 0, "num": _num(pid), "hist": []}
	var r := _rng("farm", 0, pid)
	for i in fields_n:
		P["fields"].append(FF.new_field(fertility if fertility >= 0.0 else r.randf_range(0.65, 0.85)))
	var st: Dictionary = P["store"]
	for c in ["wheat", "peas", "barley", "turnip"]:
		st["seed_" + c] = float(D.CROPS[c]["seed"]) * maxf(2.0, float(fields_n))
	st["hay"] = 10.0
	_p[pid] = P
	_order = []
	_idx_ok = false
	return pid


func value(pid: String) -> int:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return 0
	var fields: Array = P["fields"]
	var fert := 0.0
	for F: Dictionary in fields:
		fert += float(F["f"])
	fert = fert / maxf(1.0, float(fields.size()))
	var v := float(D.LAND_BASE.get(String(P["kind"]), 90)) + float(fields.size()) * float(D.FIELD_VALUE) * (0.6 + 0.5 * fert)
	for b: Dictionary in P["bld"]:
		if String(b["st"]) == "done":
			v += float(D.BUILDINGS[String(b["k"])]["value"]) * 0.7
	return int(round(v / 5.0)) * 5


func rent_of(pid: String) -> int:
	return maxi(4, int(round(float(value(pid)) * D.RENT_FRACTION)))


## Plain-words legal status, the strongest claim first: seized > mortgaged > let > for sale > freehold > crown land.
func legal_status(pid: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return ""
	if not (P["mort"] as Dictionary).is_empty():
		return "mortgaged"
	if not (P["ten"] as Dictionary).is_empty():
		return "let"
	if not (P["sale"] as Dictionary).is_empty():
		return "for_sale"
	var o := String(P["owner"])
	if o.begins_with("lord:") or o.begins_with("bank:"):
		return "crown"
	return "freehold"


## Everything that binds the land to somebody: [{kind, who, ...}]. These pass to a buyer with the deed.
func rights(pid: String) -> Array:
	var P: Dictionary = _p.get(pid, {})
	var out: Array = []
	if P.is_empty():
		return out
	var t: Dictionary = P["ten"]
	if not t.is_empty():
		out.append({"kind": "tenancy", "who": t["who"], "lease": t["kind"], "until": t["until"], "arrears": t["arrears"]})
	var m: Dictionary = P["mort"]
	if not m.is_empty():
		out.append({"kind": "lien", "who": m["lender"], "principal": m["principal"]})
	if int(P["wo"]) > 0:
		out.append({"kind": "wages_owed", "amount": int(P["wo"])})
	return out


func fields_count(pid: String) -> int:
	return (_p[pid]["fields"] as Array).size()


func field(pid: String, i: int) -> Dictionary:
	var fs: Array = _p[pid]["fields"]
	return fs[i] if i >= 0 and i < fs.size() else {}


func building_count(P: Dictionary, kind: String) -> int:
	var n := 0
	for b: Dictionary in P["bld"]:
		if b["k"] == kind and b["st"] == "done":
			n += 1
	return n


func _bsum(P: Dictionary, key: String) -> float:
	var s := 0.0
	for b: Dictionary in P["bld"]:
		if b["st"] == "done":
			s += float(D.BUILDINGS[String(b["k"])].get(key, 0))
	return s


func store_cap(P: Dictionary) -> int:
	return D.STORE_BASE + int(_bsum(P, "store"))


func store_used(P: Dictionary) -> int:
	var n := 0.0
	for k: String in P["store"]:
		n += float(P["store"][k])
	return int(n)


func shelter_of(P: Dictionary) -> float:
	return D.SHELTER_BASE + _bsum(P, "shelter")


func has_water(P: Dictionary) -> bool:
	return bool(P["wt"]) or building_count(P, "well") > 0


func housing_cap(P: Dictionary) -> int:
	return 2 + int(_bsum(P, "housing"))


# ------------------------------------------------------------------ ladder

## The player's (or an NPC's) rung on the land ladder, derived from what they hold.
func rung(who := "player") -> String:
	var owned := parcels_of(who)
	if not owned.is_empty():
		var nf := 0
		var stew := false
		for pid: String in owned:
			nf += fields_count(pid)
			stew = stew or String(_p[pid]["stw"]) != ""
		if owned.size() >= 2 and nf >= 6 and stew:
			return "estate"
		return "owner"
	for pid2: String in rented_by(who):
		if String(_p[pid2]["ten"]["kind"]) == "rent":
			return "tenant"
	for pid3: String in rented_by(who):
		if String(_p[pid3]["ten"]["kind"]) == "share":
			return "sharecropper"
	if who == "player" and String(_pl["fh"]) != "":
		return "farmhand"
	if _f.has(who) and int(_f[who].get("hand", 0)) == 1:
		return "farmhand"
	return ""


## The farm the player works as a hand ("" when not employed).
func job_parcel() -> String:
	return String(_pl["fh"])


func experience() -> int:
	return int(_pl["exp"])


func _note_rung(who: String) -> void:
	if who != "player":
		return
	var r := rung(who)
	if r != String(_pl["rung"]):
		var up := D.rung_index(r) > D.rung_index(String(_pl["rung"]))
		_pl["rung"] = r
		if r != "":
			_say(("You are now a %s." if up else "You are no longer above %s.") % r)
			_ev("trade", "", [who], "ladder", "became a " + r, 3)


## What blocks the player from `step` ("tenant", "share", "owner") right now ("" = nothing).
func requirement(step: String, who := "player") -> String:
	if who != "player":
		return ""
	var e := int(_pl["exp"])
	match step:
		"share":
			return "" if e >= EXP_SHARE else "The landlords want proof you can work a field: %d more workdays." % (EXP_SHARE - e)
		"rent":
			return "" if e >= EXP_TENANT else "No landlord will rent to a stranger: %d more workdays as a hand." % (EXP_TENANT - e)
		"buy":
			if int(_pl["season_tenant"]) >= 1 or e >= EXP_OWNER:
				return ""
			return "A deed is for those who have farmed: rent a farm first, or work %d more days." % (EXP_OWNER - e)
	return ""


## Wage work on an NPC farmer's farm.
func hire_on(pid: String, who := "player") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	var op := operator(P)
	if not _f.has(op):
		return "Nobody there is hiring."
	if who == "player" and String(_pl["fh"]) != "":
		return "You already work for a farmer."
	if int(P["hands"]) >= maxi(1, fields_count(pid) / 2 + 1):
		return "The farmer has all the hands he needs."
	P["hands"] = int(P["hands"]) + 1
	if who == "player":
		_pl["fh"] = pid
		_pl["fh_days"] = 0
		_note_rung(who)
	return ""


func quit_job(who := "player") -> void:
	if who == "player" and String(_pl["fh"]) != "":
		var P: Dictionary = _p.get(String(_pl["fh"]), {})
		if not P.is_empty():
			P["hands"] = maxi(0, int(P["hands"]) - 1)
		_pl["fh"] = ""
		_note_rung(who)


## One day's work as a farmhand: up to three tasks on the farm (the same do_task the owner uses), a wage from the farmer.
func farmhand_work(pid: String, day := -1) -> Dictionary:
	if day < 0:
		day = _day
	if String(_pl["fh"]) != pid:
		return {"ok": false, "line": "You do not work there."}
	if int(_pl["last"]) == day:
		return {"ok": false, "line": "You have worked today."}
	var P: Dictionary = _p[pid]
	var season := season_of(day)
	var done := _labour(P, day, season, 3.0, "player")
	_pl["last"] = day
	_pl["exp"] = int(_pl["exp"]) + 1
	_pl["fh_days"] = int(_pl["fh_days"]) + 1
	var op := operator(P)
	var paid := WAGE_HAND
	if _pay(op, paid):
		_earn("player", paid)
	else:
		P["wo"] = int(P["wo"]) + paid
		paid = 0
		_say("%s cannot pay you today." % who_name(op))
	return {"ok": true, "tasks": done, "wage": paid, "line": "You worked the day: %d tasks." % done}


## Pay a hand the farm owes (the farmer can pay again).
func collect_owed(pid: String) -> int:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or String(_pl["fh"]) != pid:
		return 0
	var owed := int(P["wo"])
	if owed <= 0 or not _pay(operator(P), owed):
		return 0
	P["wo"] = 0
	_earn("player", owed)
	return owed


# ------------------------------------------------------------------ land market

func _check_listable(P: Dictionary, who: String) -> String:
	if String(P["owner"]) != who:
		return "It is not yours to sell."
	if not (P["sale"] as Dictionary).is_empty():
		return "It is already for sale."
	return ""


func list_for_sale(pid: String, ask: int, who := "") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	if who == "":
		who = String(P["owner"])
	var why := _check_listable(P, who)
	if why != "":
		return why
	P["sale"] = {"ask": maxi(1, ask), "close": _day + D.AUCTION_DAYS, "bids": []}
	return ""


func highest_bid(pid: String) -> Dictionary:
	var best := {}
	for b: Dictionary in _p[pid]["sale"].get("bids", []):
		if best.is_empty() or int(b["amt"]) > int(best["amt"]):
			best = b
	return best


## Offer `amt` for a listed farm. The offer is escrowed (the player's gold leaves the purse until the sale closes or they are outbid).
func bid(pid: String, who: String, amt: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["sale"] as Dictionary).is_empty():
		return "That farm is not for sale."
	var sale: Dictionary = P["sale"]
	if who == String(P["owner"]):
		return "You cannot bid on your own land."
	var why := requirement("buy", who)
	if why != "":
		return why
	var hi := highest_bid(pid)
	var floor_amt := int(sale["ask"]) if hi.is_empty() else int(ceil(float(hi["amt"]) * 1.05))
	if amt < floor_amt:
		return "The bidding stands at %d: offer at least %d." % [int(hi.get("amt", sale["ask"])), floor_amt]
	if not can_pay(who, amt):
		return "You need %d gold." % amt
	_pay(who, amt)
	if not hi.is_empty():
		_earn(String(hi["who"]), int(hi["amt"]))
		if String(hi["who"]) == "player" and who != "player":
			stats["outbid"] += 1
			_say("%s outbids you for %s." % [who_name(who), String(P["name"])])
	var bids: Array = sale["bids"]
	bids.erase(hi)
	bids.append({"who": who, "amt": amt})
	return ""


## Close the auction: the highest bid wins (no bids: the listing lapses). Returns the buyer or "".
func close_sale(pid: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["sale"] as Dictionary).is_empty():
		return ""
	var hi := highest_bid(pid)
	P["sale"] = {}
	if hi.is_empty():
		return ""
	var buyer := String(hi["who"])
	var amt := int(hi["amt"])
	var res := _convey(P, buyer, amt, true)
	if not bool(res["ok"]):
		_earn(buyer, amt)          # the escrow comes back
		return ""
	return buyer


## Sell straight to `buyer` at `price` (the buyer pays; no auction).
func sell_to(pid: String, buyer: String, price: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	if buyer == String(P["owner"]):
		return "Already yours."
	var why := requirement("buy", buyer)
	if why != "":
		return why
	if not can_pay(buyer, price):
		return "The buyer cannot find %d gold." % price
	_pay(buyer, price)
	var res := _convey(P, buyer, price, true)
	if not bool(res["ok"]):
		_earn(buyer, price)
		return String(res["line"])
	return ""


## The Crown sells vacant land at its value, no auction.
func buy_direct(pid: String, who: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	if not is_vacant(pid) or not String(P["owner"]).begins_with("lord:"):
		return "That land is not for the Crown to sell."
	if not (P["sale"] as Dictionary).is_empty():
		return "It is up for auction; place a bid."
	var price := value(pid)
	var why := requirement("buy", who)
	if why != "":
		return why
	if not can_pay(who, price):
		return "The deed costs %d gold." % price
	_pay(who, price)
	var res := _convey(P, who, price, true)
	if not bool(res["ok"]):
		_earn(who, price)
		return String(res["line"])
	return ""


## The deed changes hands. `paid` has already left the buyer. The seller gets price minus the lien; the lien, the lease, the arrears and
## the wages owed stay with the land (the buyer takes them on).
func _convey(P: Dictionary, buyer: String, price: int, log_it: bool) -> Dictionary:
	var seller := String(P["owner"])
	var m: Dictionary = P["mort"]
	var lien := int(m.get("principal", 0))
	if lien > price:
		return {"ok": false, "line": "The debt on the land (%d) is more than the price." % lien}
	_earn(seller, price - lien)
	var pid := String(P["id"])
	P["owner"] = buyer
	P["sale"] = {}
	P["let"] = {}
	_idx_ok = false
	var t: Dictionary = P["ten"]
	if not t.is_empty() and String(t["who"]) == buyer:
		P["ten"] = {}                                  # the tenant bought his own farm: the lease ends
		_idx_ok = false
		_earn(buyer, int(t.get("dep", 0)))
		if buyer == "player" and String(t["kind"]) == "rent":
			_pl["season_tenant"] = maxi(1, int(_pl["season_tenant"]))
	if seller == "player":
		var rec := _rec()
		if rec != null:
			rec.release_property(pid)
		P["gid"] = ""
		P["stw"] = ""
		P["mode"] = "manual"
	stats["sales"] += 1
	if buyer.begins_with("npc:") and seller == "player":
		stats["npc_buys"] += 1
	if log_it:
		_ev("trade", pid, [seller, buyer], "land_sale", "%s sold %s for %d" % [who_name(seller), String(P["name"]), price], 4)
		if seller == "player" or buyer == "player":
			_say("%s changes hands for %d gold." % [String(P["name"]), price])
	_note_rung("player")
	return {"ok": true, "line": "Sold."}


func transfer(pid: String, to: String, why := "gift") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	var from := String(P["owner"])
	P["owner"] = to
	P["sale"] = {}
	_idx_ok = false
	_ev("trade", pid, [from, to], why, "%s passed to %s (%s)" % [String(P["name"]), who_name(to), why], 3)
	_note_rung("player")
	return ""


## Borrow against the deed from the money-lender. Returns "" or the refusal.
func mortgage(pid: String, amount: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	var who := String(P["owner"])
	if who.begins_with("lord:") or who.begins_with("bank:"):
		return "That is not yours to pledge."
	var m: Dictionary = P["mort"]
	var room := int(float(value(pid)) * D.MORTGAGE_MAX) - int(m.get("principal", 0))
	if amount <= 0 or amount > room:
		return "The lender will advance at most %d more." % maxi(0, room)
	if m.is_empty():
		P["mort"] = {"lender": "bank:%d" % int(P["sid"]), "principal": amount, "next": _day + D.Seasons.DAYS_PER_SEASON, "missed": 0}
	else:
		m["principal"] = int(m["principal"]) + amount
	_earn(who, amount)
	_ev("trade", pid, [who], "mortgage", "%s borrowed %d on %s" % [who_name(who), amount, String(P["name"])], 2)
	return ""


func repay(pid: String, amount: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["mort"] as Dictionary).is_empty():
		return "There is no debt on it."
	var m: Dictionary = P["mort"]
	var pay := mini(amount, int(m["principal"]))
	if not _pay(String(P["owner"]), pay):
		return "You need %d gold." % pay
	m["principal"] = int(m["principal"]) - pay
	if int(m["principal"]) <= 0:
		P["mort"] = {}
	return ""


func debt_of(pid: String) -> int:
	return int(_p[pid]["mort"].get("principal", 0))


# --- letting ---------------------------------------------------------------------

## Offer the farm to rent: kind "rent" (rent a season) or "share" (a share of every harvest).
func list_for_let(pid: String, kind := "rent", rent := -1, share := -1.0, term := 112) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	if not (P["ten"] as Dictionary).is_empty():
		return "It is let already."
	if not (P["let"] as Dictionary).is_empty():
		return "It is already offered."
	P["let"] = {"kind": kind, "rent": rent if rent >= 0 else rent_of(pid), "share": share if share >= 0.0 else D.SHARE_DEFAULT,
		"term": term, "close": _day + D.LET_DAYS, "bids": []}
	return ""


## Bid for the tenancy. For "rent" `offer` is gold a season (at least the asking rent); for "share" it is gold-equivalent of the share:
## offered share fraction * 100 (at least the asking share).
func bid_tenancy(pid: String, who: String, offer: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["let"] as Dictionary).is_empty():
		return "That farm is not offered."
	var l: Dictionary = P["let"]
	var why := requirement(String(l["kind"]), who)
	if why != "":
		return why
	if String(P["owner"]) == who:
		return "It is your own land."
	var floor_o := int(l["rent"]) if l["kind"] == "rent" else int(round(float(l["share"]) * 100.0))
	if offer < floor_o:
		return "The landlord asks at least %d." % floor_o
	var dep := int(l["rent"]) if l["kind"] == "rent" else 0
	if not can_pay(who, dep):
		return "The deposit is %d gold." % dep
	if rung(who) == "owner" or rung(who) == "estate":
		return "You hold land of your own."
	for b: Dictionary in l["bids"]:
		if String(b["who"]) == who:
			b["offer"] = maxi(int(b["offer"]), offer)
			return ""
	(l["bids"] as Array).append({"who": who, "offer": offer})
	return ""


func close_let(pid: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["let"] as Dictionary).is_empty():
		return ""
	var l: Dictionary = P["let"]
	var best := {}
	for b: Dictionary in l["bids"]:
		var bw := String(b["who"])
		if not can_pay(bw, int(l["rent"]) if l["kind"] == "rent" else 0) or rung(bw) in ["owner", "estate"] \
				or (not rented_by(bw).is_empty() and bw != "player"):
			continue
		if best.is_empty() or int(b["offer"]) > int(best["offer"]):
			best = b
	P["let"] = {}
	if best.is_empty():
		return ""
	var rent := int(best["offer"]) if l["kind"] == "rent" else int(l["rent"])
	var share: float = float(best["offer"]) / 100.0 if l["kind"] == "share" else 0.0
	if rent_out(pid, String(best["who"]), String(l["kind"]), rent, share, int(l["term"])) != "":
		return ""
	return String(best["who"])


## Let the farm to `who` now. Takes the deposit (rent leases), starts the term.
func rent_out(pid: String, who: String, kind: String, rent: int, share: float, term: int) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	if not (P["ten"] as Dictionary).is_empty():
		return "It is let already."
	var dep := rent if kind == "rent" else 0
	if not _pay(who, dep):
		return "The deposit is %d gold." % dep
	P["ten"] = {"who": who, "kind": kind, "rent": rent, "share": snappedf(share, 0.01), "since": _day, "until": _day + term,
		"next": _day + D.Seasons.DAYS_PER_SEASON, "arrears": 0, "missed": 0, "dep": dep, "notice": -1}
	P["let"] = {}
	_idx_ok = false
	_ev("trade", String(P["id"]), [String(P["owner"]), who], "tenancy", "%s took %s (%s)" % [who_name(who), String(P["name"]), kind], 2)
	_note_rung("player")
	return ""


func take_tenancy(pid: String, kind := "rent", who := "player") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return "There is no such farm."
	var why := requirement(kind, who)
	if why != "":
		return why
	if not (P["ten"] as Dictionary).is_empty():
		return "It is let already."
	if not (P["sale"] as Dictionary).is_empty():
		return "It is up for sale."
	if not is_vacant(pid):
		return "Nobody is letting that farm."
	var rent := rent_of(pid)
	if kind == "share":
		return rent_out(pid, who, "share", 0, D.SHARE_DEFAULT, 112)
	return rent_out(pid, who, "rent", rent, 0.0, 112)


func end_tenancy(pid: String, who := "player") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["ten"] as Dictionary).is_empty() or String(P["ten"]["who"]) != who:
		return "You are not the tenant."
	_evict_now(P, "left")
	return ""


## The landlord moves a tenant out. A rent tenant with a term and no missed payments cannot be moved before the term ends; a sharecropper
## gets SHARE_NOTICE days.
func evict(pid: String, by: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["ten"] as Dictionary).is_empty():
		return "Nobody lives there."
	if String(P["owner"]) != by:
		return "It is not your land."
	var t: Dictionary = P["ten"]
	if t["kind"] == "rent":
		if _day < int(t["until"]) and int(t["missed"]) < 2:
			return "The tenant has the farm until day %d." % int(t["until"])
		t["notice"] = _day + EVICT_GRACE
	else:
		t["notice"] = _day + SHARE_NOTICE
	return ""


func _evict_now(P: Dictionary, why: String) -> void:
	var t: Dictionary = P["ten"]
	if t.is_empty():
		return
	var who := String(t["who"])
	var refund := maxi(0, int(t.get("dep", 0)) - int(t.get("arrears", 0)))
	if why != "default":
		_earn(who, refund)
	P["ten"] = {}
	_idx_ok = false
	stats["evictions"] += 1
	if who == "player":
		var rec := _rec()
		if rec != null:
			rec.release_property(String(P["id"]))
		P["gid"] = ""
		P["stw"] = ""
		P["mode"] = "manual"
		_say("You leave %s (%s)." % [String(P["name"]), why])
		if t["kind"] == "rent" and _day - int(t["since"]) >= D.Seasons.DAYS_PER_SEASON and why in ["left", "notice"]:
			_pl["season_tenant"] = int(_pl["season_tenant"]) + 1
	_ev("trade", String(P["id"]), [who], "tenancy_end", "%s left %s (%s)" % [who_name(who), String(P["name"]), why], 2)
	_note_rung(who)


# ------------------------------------------------------------------ field work

static func season_of(day: int) -> int:
	return D.Seasons.season_of(day)


## One task on one field: the single code path for the player and for every worker. Returns {ok, line, qty}.
func do_task(pid: String, i: int, task: String, arg := "", who := "player") -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return {"ok": false, "line": "There is no such farm.", "qty": 0}
	var fs: Array = P["fields"]
	if i < 0 or i >= fs.size():
		return {"ok": false, "line": "There is no such field.", "qty": 0}
	if who == "player" and operator(P) != "player" and String(_pl["fh"]) != pid:
		return {"ok": false, "line": "It is not your farm.", "qty": 0}
	return _task(P, fs[i], task, arg, who, _day)


func _task(P: Dictionary, F: Dictionary, task: String, arg: String, who: String, day: int) -> Dictionary:
	var season := season_of(day)
	var st: Dictionary = P["store"]
	match task:
		"harvest":
			if not FF.is_ready(F):
				return {"ok": false, "line": "Not ready yet.", "qty": 0}
			var res := FF.reap(F, int(P["clim"]))
			var crop := String(res["crop"])
			var qty := int(res["qty"])
			var cut := 0
			var t: Dictionary = P["ten"]
			if not t.is_empty() and t["kind"] == "share":
				cut = int(round(float(qty) * float(t["share"])))
				P["ls"][crop] = float(P["ls"].get(crop, 0.0)) + cut
			st[crop] = float(st.get(crop, 0.0)) + (qty - cut)
			st["seed_" + crop] = float(st.get("seed_" + crop, 0.0)) + float(res["seed"])
			stats["harvests"] += 1
			if who == "player":
				_pl["exp"] = int(_pl["exp"]) + 1
			return {"ok": true, "line": "Harvested %d %s." % [qty - cut, crop], "qty": qty - cut, "crop": crop, "cut": cut}
		"sow":
			if String(F["c"]) != "":
				return {"ok": false, "line": "Already sown.", "qty": 0}
			var crop2 := arg if arg != "" else FF.rotation_pick(F, season, P["plan"])
			if crop2 == "" or not D.CROPS.has(crop2):
				return {"ok": false, "line": "Nothing can be sown now.", "qty": 0}
			if not D.can_sow(crop2, season):
				return {"ok": false, "line": "%s cannot be sown this season." % crop2.capitalize(), "qty": 0}
			var need := float(D.CROPS[crop2]["seed"])
			if float(st.get("seed_" + crop2, 0.0)) < need:
				return {"ok": false, "line": "No seed for %s." % crop2, "qty": 0}
			st["seed_" + crop2] = float(st["seed_" + crop2]) - need
			FF.sow(F, crop2, day)
			return {"ok": true, "line": "Sowed %s." % crop2, "qty": 0, "crop": crop2}
		"treat":
			if float(F["p"]) < 0.02 and float(F["d"]) < 0.02:
				return {"ok": false, "line": "Nothing to treat.", "qty": 0}
			FF.treat(F)
			return {"ok": true, "line": "Treated the field.", "qty": 0}
		"weed":
			FF.weed(F)
			return {"ok": true, "line": "Weeded.", "qty": 0}
		"water":
			FF.water(F)
			return {"ok": true, "line": "Watered.", "qty": 0}
		"manure":
			if float(st.get("manure", 0.0)) < 2.0:
				return {"ok": false, "line": "No manure.", "qty": 0}
			st["manure"] = float(st["manure"]) - 2.0
			FF.manure(F)
			return {"ok": true, "line": "Manured.", "qty": 0}
	return {"ok": false, "line": "Unknown work.", "qty": 0}


func forecast(pid: String, i: int) -> int:
	var F := field(pid, i)
	return FF.harvest_yield(F, int(_p[pid]["clim"])) if not F.is_empty() else 0


func buy_seed(pid: String, crop: String, units: int, who := "player") -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or not D.CROPS.has(crop) or units <= 0:
		return "Cannot buy that."
	var cost := maxi(1, int(ceil(float(D.base_price(crop)) * 0.5 * float(units))))
	if not _pay(who, cost):
		return "Seed costs %d gold." % cost
	P["store"]["seed_" + crop] = float(P["store"].get("seed_" + crop, 0.0)) + units
	P["out"] = float(P["out"]) + cost
	return ""


func set_plan(pid: String, plan: Array) -> void:
	var P: Dictionary = _p.get(pid, {})
	if not P.is_empty():
		var ok: Array = []
		for c in plan:
			if D.CROPS.has(String(c)):
				ok.append(String(c))
		if not ok.is_empty():
			P["plan"] = ok


## What to sow here. The player's plan (rotation_pick); an autonomous farm and every NPC farm also keep the herd in fodder.
func _pick_crop(P: Dictionary, F: Dictionary, season: int) -> String:
	if _f.has(operator(P)) or String(P["mode"]) == "autonomous":
		var herd_n := herd_total(String(P["id"]))
		if herd_n > 0:
			var st: Dictionary = P["store"]
			var feed := float(st.get("hay", 0.0)) + float(st.get("turnip", 0.0))
			var growing := 0
			for G: Dictionary in P["fields"]:
				if String(G["c"]) == "hay" or String(G["c"]) == "turnip":
					growing += 1
			if feed < float(herd_n) * 14.0 and growing < maxi(1, herd_n / 4):
				for c: String in ["hay", "turnip"]:
					if D.can_sow(c, season):
						return c
		return _best_crop(P, F, season)
	return FF.rotation_pick(F, season, P["plan"])


## The sowable crop of a sound rotation that pays best at this settlement's market (yield x price), a legume when the soil is tired.
func _best_crop(P: Dictionary, F: Dictionary, season: int) -> String:
	if float(F["f"]) < 0.62:
		return FF.rotation_pick(F, season, P["plan"])
	var m := _market(int(P["sid"]))
	var l1 := String(F["l1"])
	var best := ""
	var best_v := 0.0
	for c: String in D.CROP_IDS:
		var cd: Dictionary = D.CROPS[c]
		if c == "hay" or not D.can_sow(c, season) or (String(cd["fam"]) == l1 and l1 != "legume"):
			continue
		var price := float(cd["p"])
		if m != null and m.base_price.has(c):
			price = float(m.base_price[c]) * clampf(float(m.target.get(c, 1)) / maxf(float(m.stock.get(c, 0)), 0.5), 0.5, 3.0)
		var v: float = float(cd["y"]) * float((cd["clim"] as Array)[int(P["clim"])]) * price * (1.0 + 0.2 * (1.0 if String(cd["fam"]) == "legume" else 0.0))
		if v > best_v:
			best_v = v
			best = c
	return best if best != "" else FF.rotation_pick(F, season, P["plan"])


## Worker (or steward) days: task units spent in priority order -- harvest, treat, sow, weed, water, manure. Used by every non-manual
## worker and by farmhand_work. Returns the number of tasks done.
func _labour(P: Dictionary, day: int, season: int, units: float, who: String) -> int:
	var fs: Array = P["fields"]
	var done := 0
	var left := units
	var buy_ok := not (operator(P) == "player" and String(P["mode"]) == "manual")
	var passes := ["harvest", "treat", "sow", "weed", "water", "manure"]
	for task: String in passes:
		for F: Dictionary in fs:
			if left < float(TASK_COST[task]) - 0.0001:
				break
			var go := false
			match task:
				"harvest":
					go = FF.is_ready(F)
				"treat":
					go = String(F["c"]) != "" and (float(F["p"]) > 0.15 or float(F["d"]) > 0.15)
				"sow":
					go = String(F["c"]) == ""
				"weed":
					go = String(F["c"]) != "" and float(F["w"]) > 0.5
				"water":
					go = String(F["c"]) != "" and int(F["irr"]) == 0 and float(F["m"]) < float(D.CROPS[String(F["c"])]["w"]) * 0.7
				"manure":
					go = float(F["f"]) < 0.5 and float(P["store"].get("manure", 0.0)) >= 2.0
			if not go:
				continue
			var arg := ""
			if task == "sow":
				arg = _pick_crop(P, F, season)
				if arg == "":
					continue
				if buy_ok and float(P["store"].get("seed_" + arg, 0.0)) < float(D.CROPS[arg]["seed"]):
					buy_seed(String(P["id"]), arg, int(D.CROPS[arg]["seed"]) * 2, operator(P))
			var r := _task(P, F, task, arg, who, day)
			if bool(r["ok"]):
				left -= float(TASK_COST[task])
				done += 1
	return done


# ------------------------------------------------------------------ workers (the recruitment property chain)

func _group(P: Dictionary) -> String:
	var rec := _rec()
	if rec == null:
		return ""
	if String(P["gid"]) == "" or rec.group(String(P["gid"])).is_empty():
		P["gid"] = rec.create_group("property", String(P["id"]), String(P["name"]), 0.0)
		rec.set_mode(String(P["gid"]), String(P["mode"]))
	return String(P["gid"])


func workers_of(pid: String) -> Array:
	var P: Dictionary = _p.get(pid, {})
	var rec := _rec()
	var out: Array = []
	if P.is_empty() or rec == null or String(P["gid"]) == "":
		return out
	for e: Dictionary in rec.roster("property"):
		if String(e["group"]) == String(P["gid"]):
			out.append(String(e["fid"]))
	return out


## Hire a person of the settlement as a farm worker (a recruitment contract on the property chain, assigned to the farm's group).
func hire_worker(pid: String, row: int, wage := -1) -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	var rec := _rec()
	if P.is_empty() or rec == null:
		return {"ok": false, "line": "No one to hire."}
	if operator(P) != "player":
		return {"ok": false, "line": "It is not your farm."}
	if workers_of(pid).size() >= housing_cap(P):
		return {"ok": false, "line": "No bed for another hand: build a worker cottage."}
	var gid := _group(P)
	var terms: Dictionary = rec.make_terms(wage if wage > 0 else maxi(WAGE_HAND, int(rec.profile(row)["ask"])), "labor", 0, true)
	var res: Dictionary = rec.engage(row, terms, "property", "", {"trust": 30.0, "reputation": 50.0})
	if bool(res["ok"]):
		rec.assign_to_group(String(res["fid"]), gid)
	return res


func set_mode(pid: String, mode: String) -> bool:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or mode not in MODES or operator(P) != "player":
		return false
	P["mode"] = mode
	var rec := _rec()
	if rec != null and String(P["gid"]) != "":
		rec.set_mode(String(P["gid"]), mode)
	return true


func appoint_steward(pid: String, fid: String) -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	var rec := _rec()
	if P.is_empty() or rec == null:
		return {"ok": false, "line": "No farm."}
	if String(P["owner"]) != "player":
		return {"ok": false, "line": "Only an owner appoints a steward."}
	var gid := _group(P)
	var res: Dictionary = rec.appoint_manager(fid, gid, "steward", 0.0)
	if bool(res["ok"]):
		P["stw"] = fid
		if P["mode"] == "manual":
			P["mode"] = "delegated"
		rec.set_mode(gid, String(P["mode"]))
		_note_rung("player")
	return res


func _labour_units(P: Dictionary) -> float:
	var op := operator(P)
	if _f.has(op):
		return NPC_LABOUR + float(P["hands"]) * HAND_LABOUR
	var n := workers_of(String(P["id"])).size()
	return float(n) * HAND_LABOUR


# ------------------------------------------------------------------ livestock

func herd(pid: String) -> Array:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return []
	_unfold(P)
	return P["herd"]


func herd_counts(pid: String) -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return {}
	if int(P["lod"]) == 1:
		var out := {}
		for sp: String in P["co"]:
			var c: Dictionary = P["co"][sp]
			out[sp] = int(round(float(c["n"]) + float(c["m"]) + float(c["y"])))
		return out
	return FH.counts(P["herd"])


func herd_total(pid: String) -> int:
	var t := 0
	var c := herd_counts(pid)
	for sp: String in c:
		t += int(c[sp])
	return t


func _unfold(P: Dictionary) -> void:
	if int(P["lod"]) == 0:
		return
	P["herd"] = FH.expand(P["co"], _day, _rng("unfold", _day, P["id"]))
	P["co"] = {}
	P["lod"] = 0


func _fold(P: Dictionary) -> void:
	if int(P["lod"]) == 1:
		return
	P["co"] = FH.collapse(P["herd"], _day)
	P["herd"] = []
	P["lod"] = 1


func buy_animals(pid: String, sp: String, n: int, who := "", female_share := 0.8) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or not D.ANIMALS.has(sp) or n <= 0:
		return "Cannot buy that."
	if who == "":
		who = operator(P)
	var sd: Dictionary = D.ANIMALS[sp]
	var cost := int(sd["price"]) * n
	if not _pay(who, cost):
		return "That costs %d gold." % cost
	_unfold(P)
	var r := _rng("buy", _day, P["id"])
	var nf := maxi(0, int(round(float(n) * female_share)))
	var have_male := false
	for a: Array in P["herd"]:
		if FH.species_of(a) == sp and int(a[FH.A_SEX]) == 0 and FH.is_adult(a):
			have_male = true
	if not have_male and n >= 2:
		nf = mini(nf, n - 1)
	for i in n:
		P["herd"].append(FH.new_animal(sp, int(sd["mat"]) + r.randi_range(5, 40), i < nf, _day, r))
	P["out"] = float(P["out"]) + cost
	return ""


func sell_animals(pid: String, sp: String, n: int, adults_only := true) -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return {"sold": 0, "gold": 0}
	_unfold(P)
	var h: Array = P["herd"]
	var idx: Array = []
	for i in h.size():
		var a: Array = h[i]
		if FH.species_of(a) == sp and (FH.is_adult(a) or not adults_only):
			idx.append(i)
	idx.sort_custom(func(x: int, y: int) -> bool: return FH.value(h[x]) < FH.value(h[y]))
	var bonus := float(D.SPECS.get(String(P["spec"]), D.SPECS[""])["price"]) if D.SPECS.get(String(P["spec"]), {}).get("species", "") == sp else 1.0
	var gold := 0
	var sold := 0
	var take: Array = idx.slice(0, n)
	take.sort()
	for k in range(take.size() - 1, -1, -1):
		gold += int(round(float(FH.value(h[take[k]])) * bonus))
		h.remove_at(take[k])
		sold += 1
	_earn(operator(P), gold)
	P["inc"] = float(P["inc"]) + gold
	return {"sold": sold, "gold": gold}


func set_specialisation(pid: String, spec: String) -> String:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or not D.SPECS.has(spec):
		return "No such specialisation."
	var need := String(D.SPECS[spec]["needs"])
	if need != "" and building_count(P, need) == 0:
		return "A %s needs a %s." % [String(D.SPECS[spec]["name"]).to_lower(), need]
	P["spec"] = spec
	return ""


## The player (or a hand) tends the sick animals for a few days.
func tend_herd(pid: String) -> void:
	var P: Dictionary = _p.get(pid, {})
	if not P.is_empty():
		P["tx"] = _day + 3


func _herd_env(P: Dictionary, day: int, season: int) -> Dictionary:
	var graze := 4.0
	for F: Dictionary in P["fields"]:
		if String(F["c"]) == "":
			graze += 3.0
	return {"day": day, "season": season, "graze": graze, "water": has_water(P), "shelter": shelter_of(P), "spec": String(P["spec"]),
		"treat": day <= int(P["tx"]) or int(P["hands"]) > 0 or workers_of(String(P["id"])).size() > 0 or String(P["stw"]) != ""}


func _guard(P: Dictionary) -> float:
	var g := _bsum(P, "guard")
	if int(P["hands"]) > 1 or workers_of(String(P["id"])).size() > 1:
		g += 0.3
	return clampf(g, 0.0, 0.85)


## Thieves in the night: one animal at a time, the most valuable first. `force` for tests.
func _theft(P: Dictionary, r: RandomNumberGenerator, dt: int, force := false) -> int:
	var lost := 0
	var total := herd_total(String(P["id"]))
	if total == 0:
		return 0
	var p := 0.006 * (1.0 - _guard(P))
	for _d in dt:
		if not force and r.randf() >= p:
			continue
		if int(P["lod"]) == 0:
			var h: Array = P["herd"]
			if h.is_empty():
				break
			var best := 0
			for i in h.size():
				if FH.value(h[i]) > FH.value(h[best]):
					best = i
			h.remove_at(best)
		else:
			if FH.steal_far(P["co"], r) == "":
				break
		lost += 1
		force = false
	if lost > 0:
		P["stolen"] = int(P["stolen"]) + lost
		stats["thefts"] += lost
		_ev("crime", String(P["id"]), [operator(P)], "livestock_theft", "%d animal(s) stolen from %s" % [lost, String(P["name"])], 3)
		if operator(P) == "player":
			_say("Thieves took %d animal%s from %s." % [lost, "" if lost == 1 else "s", String(P["name"])])
	return lost


func _herd_day(P: Dictionary, day: int, dt: int, season: int, near: bool) -> void:
	if near and int(P["lod"]) == 1:
		_unfold(P)
	elif not near and int(P["lod"]) == 0 and not (P["herd"] as Array).is_empty():
		_fold(P)
	var env := _herd_env(P, day, season)
	var st: Dictionary = P["store"]
	var r := _rng("herd", day, P["id"])
	if int(P["lod"]) == 0:
		for _d in dt:
			env["day"] = day - dt + 1 + _d
			FH.step_near(P["herd"], env, st, r)
	else:
		FH.step_far(P["co"], env, st, float(dt))
	_theft(P, r, dt)
	st["manure"] = float(st.get("manure", 0.0)) + 0.1 * float(herd_total(String(P["id"]))) * float(dt)


# ------------------------------------------------------------------ expansion (construction staged sites)

## Add a field, barn, granary, pen, cottage, well, irrigation ditch, fence or mill. The player's go through
## construction.place_kit_plan (a staged site raised by crews, materials from the store or pack); NPC farms use npc_place. The gold is
## paid now; the building works when its site is done.
func build(pid: String, kind: String, who := "") -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or not D.BUILDINGS.has(kind):
		return {"ok": false, "line": "Cannot build that."}
	if who == "":
		who = operator(P)
	if who != operator(P) and who != String(P["owner"]):
		return {"ok": false, "line": "It is not your farm."}
	var bd: Dictionary = D.BUILDINGS[kind]
	if kind == "field" and fields_count(pid) + _pending_of(P, "field") >= D.FIELD_MAX:
		return {"ok": false, "line": "No room for more fields."}
	for b: Dictionary in P["bld"]:
		if b["k"] == kind and kind in ["well", "irrigation", "mill", "fence"] and b["st"] != "failed":
			return {"ok": false, "line": "You already have one."}
	if not _pay(who, int(bd["gold"])):
		return {"ok": false, "line": "It costs %d gold." % int(bd["gold"])}
	var pos := Vector2(float(P["pos"][0]), float(P["pos"][1]))
	var n := (P["bld"] as Array).size()
	var spot := pos + Vector2(14.0 + 7.0 * float(n % 5), -10.0 - 7.0 * float(n / 5))
	var site := 0
	var cons := _cons()
	var b2 := {"k": kind, "st": "site", "site": 0, "due": _day + int(ceil(float(bd["hours"]) / 12.0))}
	if cons != null:
		if _f.has(who) or who.begins_with("lord:"):
			site = int(cons.npc_place(String(bd["npc"]), spot, 0.0, float(bd["hours"]), "%s: %s" % [String(P["name"]), String(bd["name"])], String(P["id"])))
		else:
			var res: Dictionary = cons.place_kit_plan(spot, 0.0, bd["mats"], float(bd["hours"]), "%s: %s" % [String(P["name"]), String(bd["name"])])
			site = int(res.get("id", 0))
	b2["site"] = site
	b2["npc"] = _f.has(who) or cons == null
	(P["bld"] as Array).append(b2)
	P["out"] = float(P["out"]) + int(bd["gold"])
	return {"ok": true, "line": "%s begun." % bd["name"], "site": site}


func _pending_of(P: Dictionary, kind: String) -> int:
	var n := 0
	for b: Dictionary in P["bld"]:
		if b["k"] == kind and b["st"] == "site":
			n += 1
	return n


## Finished sites switch their buildings on; NPC sites progress by the calendar.
func _poll_sites(P: Dictionary, day: int) -> void:
	var cons := _cons()
	for b: Dictionary in P["bld"]:
		if b["st"] != "site":
			continue
		var done := false
		var site := int(b["site"])
		if cons != null and site > 0 and cons.sites.has(site):
			var s: Dictionary = cons.sites[site]
			if bool(b.get("npc", false)):
				var span := float(maxi(1, int(D.BUILDINGS[String(b["k"])]["hours"] / 12.0)))
				cons.npc_set_progress(site, 1.0 - float(maxi(0, int(b["due"]) - day)) / span)
				if day >= int(b["due"]):
					cons.npc_finish(site)
					done = true
			else:
				done = String(s["state"]) == "done"
		elif cons == null or site == 0:
			done = day >= int(b["due"])
		elif bool(b.get("npc", false)):
			done = day >= int(b["due"])                       # a pruned NPC site is simply part of the farm
		else:
			b["st"] = "failed"                                # the player's plan was cancelled
		if done:
			b["st"] = "done"
			stats["built"] += 1
			_activate(P, String(b["k"]))
			if operator(P) == "player":
				_say("%s: the %s is finished." % [String(P["name"]), String(D.BUILDINGS[String(b["k"])]["name"]).to_lower()])
			_ev("build", String(P["id"]), [operator(P)], "farm_build", "%s finished at %s" % [D.BUILDINGS[String(b["k"])]["name"], String(P["name"])], 2)


func _activate(P: Dictionary, kind: String) -> void:
	if kind == "field":
		P["fields"].append(FF.new_field(0.75))
	elif kind == "irrigation":
		for F: Dictionary in P["fields"]:
			F["irr"] = 1


func buildings(pid: String) -> Array:
	return (_p[pid]["bld"] as Array).duplicate(true)


# ------------------------------------------------------------------ economy

func _market(sid: int) -> RefCounted:
	if market_ref is Dictionary:
		return (market_ref as Dictionary).get(sid)
	if Life != null and Life.get("economy") != null:
		return Life.economy.markets.get(sid)
	return null


func _ensure_good(m: RefCounted, item: String) -> void:
	if not m.base_price.has(item):
		var bp := D.base_price(item)
		m.add_good(item, bp, 40, 0)


## Sell from the farm's store to the settlement market, one unit at a time, until `qty` is sold, the price falls under `floor_ratio` of the
## base price, or the merchant's purse is empty. The units join the market's stock, so they weigh on its price. Returns gold.
func sell_goods(pid: String, item: String, qty := -1, floor_ratio := 0.0, from_share := false) -> int:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return 0
	var m := _market(int(P["sid"]))
	if m == null:
		return 0
	var src: Dictionary = P["ls"] if from_share else P["store"]
	var have := int(floor(float(src.get(item, 0.0))))
	if qty < 0 or qty > have:
		qty = have
	if qty <= 0:
		return 0
	_ensure_good(m, item)
	var gold_f := 0.0
	var sold := 0
	var base := float(m.base_price[item])
	var mod: float = m.modifier(item)
	var target := float(m.target.get(item, 1))
	var stock := float(m.stock.get(item, 0))
	var purse := float(m.purse)
	while sold < qty:
		var pf := base * clampf(target / maxf(stock, 0.5), 0.5, 3.0) * mod          # the market's own curve, unrounded
		if floor_ratio > 0.0 and pf < base * floor_ratio:
			break
		var unit := maxf(0.5, pf * float(m.SELL_SHARE))
		if purse < unit:
			break
		purse -= unit
		gold_f += unit
		stock += 1.0
		sold += 1
	var gold := int(round(gold_f))
	m.stock[item] = int(m.stock.get(item, 0)) + sold
	m.purse = maxi(0, int(m.purse) - gold)
	src[item] = float(src.get(item, 0.0)) - sold
	var owner := String(P["owner"]) if from_share else operator(P)
	_income(P, owner, gold)
	return gold


## Proceeds go to the one who sells; a delegated or autonomous player farm sends them through the farm group's budget first (wages), and a
## dishonest steward skims some (recruitment audit() finds it).
func _income(P: Dictionary, who: String, gold: int) -> void:
	if gold <= 0:
		return
	P["inc"] = float(P["inc"]) + gold
	if who == "player" and String(P["mode"]) != "manual" and String(P["gid"]) != "":
		var rec := _rec()
		if rec != null:
			var g: Dictionary = rec.group(String(P["gid"]))
			var stw := String(P["stw"])
			if stw != "" and not g.is_empty():
				var hon: float = rec.honesty(stw)
				var skim := int(round(float(gold) * clampf(0.5 - hon, 0.0, 0.5) * 0.4 * (1.0 - float(g["ov"]))))
				if skim > 0:
					g["sk"] = float(g["sk"]) + skim
					gold -= skim
			var float_cap := float(workers_of(String(P["id"])).size() * WAGE_HAND * 14)
			var top := maxi(0, int(minf(float(gold), float_cap - float(g.get("bud", 0.0)))))
			if not g.is_empty() and top > 0:
				g["bud"] = float(g["bud"]) + top
				gold -= top
	_earn(who, gold)


func process(P: Dictionary, dt: int) -> void:
	var st: Dictionary = P["store"]
	if building_count(P, "mill") > 0:
		var w := minf(float(st.get("wheat", 0.0)), 4.0 * dt)
		if w >= 1.0:
			st["wheat"] = float(st["wheat"]) - w
			st["flour"] = float(st.get("flour", 0.0)) + w
	if building_count(P, "barn") > 0 and float(st.get("milk", 0.0)) >= 4.0:
		var cheese := floorf(float(st["milk"]) / 4.0)
		st["milk"] = float(st["milk"]) - cheese * 4.0
		st["cheese"] = float(st.get("cheese", 0.0)) + cheese * 1.0


func _spoil(P: Dictionary, dt: int) -> void:
	var st: Dictionary = P["store"]
	var granary := building_count(P, "granary") > 0
	var keys := st.keys()
	for k: String in keys:
		var q := float(st[k])
		if q <= 0.0:
			st.erase(k)
			continue
		var rate := D.spoil_rate(k)
		var fam := D.goods_family(k)
		if granary and (fam == "grain" or fam == "legume"):
			rate *= 0.4
		q *= pow(1.0 - rate, float(dt))
		st[k] = q if q >= 0.05 else 0.0
	# Goods beyond the barn rot in the open.
	var over := store_used(P) - store_cap(P)
	if over > 0:
		var loss := minf(0.1 * float(dt), 0.6)
		for k2: String in st.keys():
			if not k2.begins_with("seed_"):
				st[k2] = float(st[k2]) * (1.0 - loss * float(over) / maxf(1.0, float(store_used(P))))
	var ls: Dictionary = P["ls"]
	for k3: String in ls.keys():
		ls[k3] = float(ls[k3]) * pow(1.0 - D.spoil_rate(k3), float(dt))
		if float(ls[k3]) < 0.05:
			ls.erase(k3)


## A manager's or a farmer's selling round: contracts first, spoilables at once, the rest while the price holds. Feed for the herd stays.
func _auto_sell(P: Dictionary, day: int) -> void:
	var pid := String(P["id"])
	var st: Dictionary = P["store"]
	_fill_contracts(P, day)
	var herd_n := herd_total(pid)
	for k: String in st.keys():
		if k.begins_with("seed_") or k == "manure":
			continue
		var have := int(floor(float(st[k])))
		if have <= 0:
			continue
		var spoil := D.spoil_rate(k)
		var reserve := 0
		if herd_n > 0 and k in ["hay", "turnip", "barley", "wheat"]:
			reserve = herd_n * 4
		var fast := spoil >= 0.02 or _distress(P)
		var sell_n := have - (0 if fast else reserve)
		if sell_n > 0:
			sell_goods(pid, k, sell_n, 0.0 if fast else REL_FLOOR)
	var ls: Dictionary = P["ls"]
	for k2: String in ls.keys():
		if int(float(ls[k2])) > 0:
			sell_goods(pid, k2, int(float(ls[k2])), 0.0, true)


## An autonomous player farm puts spare gold back into the land: a field up to six, then a barn once it has stock to shelter.
func _auto_expand(P: Dictionary) -> void:
	var pid := String(P["id"])
	if fields_count(pid) + _pending_of(P, "field") < 6 and gold_available() >= 300:
		build(pid, "field", "player")
	elif herd_total(pid) > 0 and building_count(P, "barn") + _pending_of(P, "barn") == 0 and gold_available() >= 350:
		build(pid, "barn", "player")


## A farm that manages itself buys fodder when the barn runs low (a gold a bundle) so the herd does not starve in winter.
func _auto_feed(P: Dictionary) -> void:
	var herd_n := herd_total(String(P["id"]))
	if herd_n == 0:
		return
	var st: Dictionary = P["store"]
	var have := float(st.get("hay", 0.0)) + float(st.get("turnip", 0.0))
	var want := float(herd_n) * 8.0
	if have >= want:
		return
	var units := int(ceil(want - have))
	var op := operator(P)
	while units > 0 and not _pay(op, units):
		units /= 2
	if units > 0:
		st["hay"] = float(st.get("hay", 0.0)) + units
		P["out"] = float(P["out"]) + units


## A farmer short of cash sells at any price.
func _distress(P: Dictionary) -> bool:
	var op := operator(P)
	return _f.has(op) and int(_f[op]["cash"]) < 60


# --- garrison supply contracts ------------------------------------------------------

func contracts() -> Array:
	return _ct


func _gen_contracts(day: int) -> void:
	_ct = _ct.filter(func(c: Dictionary) -> bool: return day <= int(c["due"]) + 3 and not (bool(c.get("done", false)) and day > int(c["due"])))
	var sh := _mod("strongholds")
	var buyers: Array = sh.supply_buyers() if sh != null else []
	if buyers.is_empty():
		return
	var items := ["wheat", "barley", "turnip", "hay", "beef", "peas"]
	var open := 0
	for c: Dictionary in _ct:
		if not bool(c.get("done", false)):
			open += 1
	var r := _rng("ctgen", day, 0)
	var want := mini(6, buyers.size()) - open
	for _k in maxi(0, want):
		var s2: Dictionary = buyers[r.randi() % buyers.size()]
		var item: String = items[r.randi() % items.size()]
		var qty := clampi(int(s2.get("garrison", 10)) / 3, 6, 40)
		var price := maxi(1, int(round(float(D.base_price(item)) * 1.35)))
		_ct.append({"id": _next_c, "buyer": int(s2["id"]), "item": item, "qty": qty, "price": price, "due": day + CONTRACT_DAYS,
			"got": 0, "taker": "", "pid": "", "done": false})
		_next_c += 1


func accept_contract(cid: int, pid: String, who := "player") -> String:
	for c: Dictionary in _ct:
		if int(c["id"]) == cid:
			if String(c["taker"]) != "":
				return "Taken already."
			if not _p.has(pid) or operator(_p[pid]) != who:
				return "It is not your farm."
			c["taker"] = who
			c["pid"] = pid
			return ""
	return "No such contract."


func _fill_contracts(P: Dictionary, day: int) -> void:
	var pid := String(P["id"])
	var op := operator(P)
	for c: Dictionary in _ct:
		if bool(c.get("done", false)):
			continue
		if String(c["taker"]) == "" and _f.has(op) and float(P["store"].get(String(c["item"]), 0.0)) >= float(c["qty"]) * 0.6 and int(c["due"]) > day:
			c["taker"] = op
			c["pid"] = pid
		if String(c["pid"]) == pid:
			deliver_contract(int(c["id"]), pid, day)


## Hand over what the store has of the contract's goods; completed contracts pay the fixed price and top up the stronghold's supply.
func deliver_contract(cid: int, pid: String, day := -1) -> Dictionary:
	if day < 0:
		day = _day
	var P: Dictionary = _p.get(pid, {})
	for c: Dictionary in _ct:
		if int(c["id"]) != cid or bool(c.get("done", false)):
			continue
		if String(c["pid"]) != pid:
			return {"ok": false, "line": "It is not your contract."}
		if day > int(c["due"]):
			c["done"] = true
			if String(c["taker"]) == "player":
				_pl["rep"] = int(_pl["rep"]) - 1
				_say("The supply contract for %s lapsed." % String(c["item"]))
			return {"ok": false, "line": "Too late."}
		var item := String(c["item"])
		var give := mini(int(c["qty"]) - int(c["got"]), int(floor(float(P["store"].get(item, 0.0)))))
		if give <= 0:
			return {"ok": false, "line": "You have none to deliver."}
		P["store"][item] = float(P["store"][item]) - give
		c["got"] = int(c["got"]) + give
		if int(c["got"]) >= int(c["qty"]):
			c["done"] = true
			var pay := int(c["qty"]) * int(c["price"])
			_income(P, operator(P), pay)
			stats["contracts"] += 1
			var sh := _mod("strongholds")
			if sh != null:
				sh.add_supply(int(c["buyer"]), int(c["qty"]))
			_ev("contract", pid, [operator(P)], "garrison_supply", "%s supplied %d %s" % [who_name(operator(P)), int(c["qty"]), item], 2)
			return {"ok": true, "line": "Contract filled: %d gold." % pay, "gold": pay}
		return {"ok": true, "line": "Delivered %d; %d to go." % [give, int(c["qty"]) - int(c["got"])], "gold": 0}
	return {"ok": false, "line": "No such contract."}


# ------------------------------------------------------------------ the farm's day

func _tracked(P: Dictionary) -> bool:
	return String(P["owner"]) == "player" or operator(P) == "player"


func _is_near(P: Dictionary) -> bool:
	return Vector2(float(P["pos"][0]), float(P["pos"][1])).distance_to(player_pos) <= NEAR_RADIUS


## Advance one farm to `day`. Near / player farms step daily with real weather; far NPC farms step every FAR_STEP days on expected values.
func _farm_step(P: Dictionary, day: int, ctx: Dictionary) -> void:
	var dt := day - int(P["last"])
	if dt <= 0:
		return
	var near := _is_near(P)
	if not near and not _tracked(P) and dt < FAR_STEP:
		return
	dt = mini(dt, 28)
	P["last"] = day
	var season := season_of(day)
	var op := operator(P)
	var vacant := is_vacant(String(P["id"]))
	var env := {"season": season, "clim": int(P["clim"]), "irr_ok": building_count(P, "irrigation") > 0}
	var rng: RandomNumberGenerator = _rng("fd", day, P["id"]) if dt == 1 else null
	for F: Dictionary in P["fields"]:
		FF.step(F, env, float(dt), rng)
	FF.spread(P["fields"], D.COLS, float(dt))
	_cross_spread(P, float(dt))
	if not vacant:
		var units := _labour_units(P)
		if units > 0.0:
			_labour(P, day, season, units * float(dt), "worker")
		if _f.has(op) or (op == "player" and String(P["mode"]) != "manual"):
			_auto_feed(P)
		_herd_day(P, day, dt, season, near)
		process(P, dt)
		_spoil(P, dt)
		_finance(P, day, dt, ctx)
		if _f.has(op) or (op == "player" and String(P["mode"]) != "manual" and (String(P["stw"]) != "" or not workers_of(String(P["id"])).is_empty())):
			_auto_sell(P, day)
		if op == "player" and String(P["mode"]) == "autonomous" and day % 14 == 0:
			_auto_expand(P)
	else:
		_spoil(P, dt)
	_poll_sites(P, day)


func _cross_spread(P: Dictionary, dt: float) -> void:
	var fs: Array = P["fields"]
	if fs.is_empty():
		return
	var worst := 0.0
	for F: Dictionary in fs:
		worst = maxf(worst, maxf(float(F["p"]), float(F["d"])))
	if worst < 0.45:
		return
	var here := Vector2(float(P["pos"][0]), float(P["pos"][1]))
	for pid2: String in parcels():
		var Q: Dictionary = _p[pid2]
		if Q == P or Q["fields"].is_empty():
			continue
		if here.distance_to(Vector2(float(Q["pos"][0]), float(Q["pos"][1]))) < 90.0:
			var G: Dictionary = (Q["fields"] as Array)[0]
			G["p"] = clampf(float(G["p"]) + 0.03 * worst * dt, 0.0, 1.0)


## Wages, rent, mortgage payments, living costs, eviction notices. `dt` days of each.
func _finance(P: Dictionary, day: int, dt: int, _ctx: Dictionary) -> void:
	var op := operator(P)
	var owner := String(P["owner"])
	# NPC household and hands.
	if _f.has(op):
		var w: Dictionary = _f[op]
		w["cash"] = int(w["cash"]) - int(round(LIVING_COST * float(dt))) - int(P["hands"]) * HAND_COST * dt
		if int(w["cash"]) < 0:
			w["neg"] = int(w["neg"]) + dt
		else:
			w["neg"] = 0
	# Tenancy.
	var t: Dictionary = P["ten"]
	if not t.is_empty():
		if t["kind"] == "rent" and day >= int(t["next"]):
			var due := int(t["rent"])
			t["next"] = int(t["next"]) + D.Seasons.DAYS_PER_SEASON
			if _pay(String(t["who"]), due):
				_earn(owner, due)
				if String(t["who"]) == "player":
					_pl["season_tenant"] = maxi(int(_pl["season_tenant"]), 1) if int(t["missed"]) == 0 else int(_pl["season_tenant"])
				t["missed"] = 0
			else:
				t["arrears"] = int(t["arrears"]) + due
				t["missed"] = int(t["missed"]) + 1
				if String(t["who"]) == "player":
					_say("You could not pay the rent on %s." % String(P["name"]))
				if int(t["missed"]) >= 2 and int(t["notice"]) < 0:
					t["notice"] = day + EVICT_GRACE
		if int(t["arrears"]) > 0 and can_pay(String(t["who"]), int(t["arrears"])) and t["kind"] == "rent":
			var ar := int(t["arrears"])
			_pay(String(t["who"]), ar)
			_earn(owner, ar)
			t["arrears"] = 0
			t["missed"] = 0
			t["notice"] = -1
		if int(t["notice"]) >= 0 and day >= int(t["notice"]):
			_evict_now(P, "evicted" if int(t["arrears"]) > 0 else "notice")
	# Mortgage.
	var m: Dictionary = P["mort"]
	if not m.is_empty() and day >= int(m["next"]):
		var interest := maxi(1, int(ceil(float(m["principal"]) * D.MORTGAGE_RATE)))
		m["next"] = int(m["next"]) + D.Seasons.DAYS_PER_SEASON
		if _pay(owner, interest):
			m["missed"] = 0
		else:
			m["missed"] = int(m["missed"]) + 1
			m["principal"] = int(m["principal"]) + interest
			if owner == "player":
				_say("You missed the lender's payment on %s." % String(P["name"]))
			if int(m["missed"]) >= 3:
				_seize(P)
	# NPC bust.
	if _f.has(op) and int(_f[op]["neg"]) >= BUST_DAYS and int(_f[op]["cash"]) < -30:
		_bust(op, day)


func _seize(P: Dictionary) -> void:
	var owner := String(P["owner"])
	stats["seized"] += 1
	_ev("trade", String(P["id"]), [owner], "foreclosure", "%s lost %s to the lender" % [who_name(owner), String(P["name"])], 4)
	if owner == "player":
		_say("The lender seizes %s." % String(P["name"]))
		var rec := _rec()
		if rec != null:
			rec.release_property(String(P["id"]))
		P["gid"] = ""
		P["stw"] = ""
		P["mode"] = "manual"
	P["owner"] = "lord:%d" % int(P["sid"])
	_idx_ok = false
	P["mort"] = {}
	P["sale"] = {}
	list_for_sale(String(P["id"]), int(round(float(value(String(P["id"]))) * 0.8 / 5.0)) * 5, String(P["owner"]))
	_note_rung("player")
	if _f.has(owner):
		_f[owner]["bust"] = _day + 60


func _bust(who: String, day: int) -> void:
	var w: Dictionary = _f[who]
	w["busts"] = int(w["busts"]) + 1
	w["bust"] = day + 60
	w["cash"] = 12
	w["neg"] = 0
	stats["busts"] += 1
	for pid: String in rented_by(who):
		var P: Dictionary = _p[pid]
		P["hands"] = 0
		_evict_now(P, "default")
	for pid2: String in parcels_of(who):
		var Q: Dictionary = _p[pid2]
		Q["hands"] = 0
		_seize(Q)
	_ev("emergency", "", [who], "farm_bust", "%s went bust" % String(w["name"]), 4)


# ------------------------------------------------------------------ NPC farmers

func ensure() -> void:
	_ensure()


func _ensure() -> void:
	if _inited:
		return
	_inited = true
	if not _p.is_empty() or WorldGen.settlements.is_empty():
		return
	_seed_world()


func _seed_world() -> void:
	var total := 0
	for s: Dictionary in WorldGen.settlements:
		if total >= NPC_FARMS_MAX:
			break
		var sid := int(s["id"])
		if sid >= WorldSim.ranges.size():
			continue
		var rg: Vector2i = WorldSim.ranges[sid]
		var rows: Array = []
		for i in range(rg.x, rg.y):
			if WorldSim.job[i] == 0 and WorldSim.health[i] != 0:
				rows.append(i)
		var kind := String(s["kind"])
		var nfarm := 0
		if kind == "village":
			nfarm = clampi(rows.size() / 8, 1, 3)
		elif rows.size() >= 3:
			nfarm = clampi(rows.size() / 6, 1, 2)
		nfarm = mini(nfarm, rows.size())
		var r := _rng("seedfarm", 0, sid)
		var spos: Vector2 = s["pos"]
		var used := 0
		for k in nfarm:
			if total >= NPC_FARMS_MAX or used >= rows.size():
				break
			var row: int = rows[used]
			used += 1
			var who := "npc:%d" % row
			_make_farmer(who, row, sid, r.randi_range(60, 160), r.randf_range(0.2, 0.9))
			var ang := r.randf() * TAU
			var pos := spos + Vector2(cos(ang), sin(ang)) * (75.0 + 30.0 * float(k))
			var landlord := "lord:%d" % sid
			var owned_by_farmer := r.randf() < 0.3
			var pid := found_parcel(sid, pos, 3 + (1 if r.randf() < 0.3 else 0), who if owned_by_farmer else landlord)
			var P: Dictionary = _p[pid]
			P["last"] = _day - (int(P["num"]) % FAR_STEP)
			_seed_fields_and_stock(P, r)
			if not owned_by_farmer:
				rent_out(pid, who, "rent", rent_of(pid), 0.0, 112 + r.randi_range(0, 56))
				P["ten"]["since"] = _day - r.randi_range(10, 60)
				P["ten"]["dep"] = int(P["ten"]["rent"])
			else:
				_f[who]["cash"] = int(_f[who]["cash"]) + 120
			total += 1
		_dampen_abstract_supply(sid, nfarm)
		# Landless farmers look for land (and hire out meanwhile).
		var extra := 0
		while used < rows.size() and extra < 2:
			var row2: int = rows[used]
			used += 1
			extra += 1
			var f2 := _make_farmer("npc:%d" % row2, row2, sid, r.randi_range(25, 90), r.randf_range(0.2, 0.9))
			f2["hand"] = 1


## A seeded farm starts mid-year: crops part grown, a cow or sheep in the yard.
func _seed_fields_and_stock(P: Dictionary, r: RandomNumberGenerator) -> void:
	var season := season_of(_day)
	var plan: Array = P["plan"]
	var i := 0
	for F: Dictionary in P["fields"]:
		var c: String = plan[i % plan.size()]
		i += 1
		if D.can_sow(c, season):
			FF.sow(F, c, _day)
			F["g"] = r.randf() * 0.85 * float(D.CROPS[c]["d"])
	P["store"]["hay"] = 40.0
	P["store"]["turnip"] = 20.0
	var roll := r.randf()
	if roll < 0.7:
		P["herd"].append(FH.new_animal("cow", 90, true, _day, r))
		P["herd"].append(FH.new_animal("cow", 100, true, _day, r))
		P["herd"].append(FH.new_animal("cow", 120, false, _day, r))
	if roll < 0.9:
		for k in 4:
			P["herd"].append(FH.new_animal("sheep", 70, k < 3, _day, r))


## The abstract village crops of the economy (wheat, cabbage a day) are what these farms really grow: the real farms of a settlement take
## most of that supply over so the market is not flooded twice. Only for the live economy, once, at seeding.
func _dampen_abstract_supply(sid: int, nfarm: int) -> void:
	if market_ref is Dictionary or nfarm <= 0 or Life == null or Life.get("economy") == null:
		return
	var m: RefCounted = Life.economy.markets.get(sid)
	if m == null:
		return
	var cut := minf(0.8, 0.28 * float(nfarm))
	for item: String in ["wheat", "cabbage"]:
		var made := int(m.produce.get(item, 0))
		if made > 0:
			m.produce[item] = maxi(1, int(round(float(made) * (1.0 - cut))))
	_damp[sid] = true


func _make_farmer(who: String, row: int, sid: int, cash: int, amb: float) -> Dictionary:
	var f := {"row": row, "sid": sid, "name": WorldSim.person_name(row), "cash": cash, "amb": snappedf(amb, 0.01), "neg": 0, "bust": -1, "busts": 0, "hand": 0}
	_f[who] = f
	return f


func farmers() -> Dictionary:
	return _f


func farmer(who: String) -> Dictionary:
	return _f.get(who, {})


## Test / scenario helper: register an NPC farmer record.
func add_farmer(who: String, sid: int, cash: int, amb := 0.7, row := -1, nm := "Farmer") -> Dictionary:
	var f := {"row": row, "sid": sid, "name": nm, "cash": cash, "amb": amb, "neg": 0, "bust": -1, "busts": 0, "hand": 0}
	_f[who] = f
	return f


## Farms of an NPC farmer with room and the means to take on a hand (the farmhand's rung).
func jobs(sid := -1) -> Array:
	var out: Array = []
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		var op := operator(P)
		if _f.has(op) and (sid < 0 or int(P["sid"]) == sid) and int(P["hands"]) < maxi(1, fields_count(pid) / 2 + 1) \
				and int(_f[op]["cash"]) >= WAGE_HAND * 7:
			out.append(pid)
	return out


## Farms on offer to rent: the Crown's vacant land and lets listed by owners.
func for_rent() -> Array:
	var out: Array = []
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		if not (P["let"] as Dictionary).is_empty() or is_vacant(pid):
			out.append(pid)
	return out


func for_sale() -> Array:
	var out: Array = []
	for pid: String in parcels():
		if not (_p[pid]["sale"] as Dictionary).is_empty():
			out.append(pid)
	return out


func listings() -> Array:
	var out: Array = []
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		if not (P["sale"] as Dictionary).is_empty() or not (P["let"] as Dictionary).is_empty():
			out.append(pid)
	return out


## What an NPC farmer would pay for `pid` at most: their cash, less a working reserve, and only if ambitious.
func npc_cap(who: String) -> int:
	var w: Dictionary = _f.get(who, {})
	if w.is_empty() or int(w["bust"]) > _day or float(w["amb"]) < 0.3:
		return 0
	return maxi(0, int(float(w["cash"]) * (0.7 + 0.3 * float(w["amb"])) - 20.0))


func _farmer_ids() -> Array:
	if _fids.size() != _f.size():
		_fids = _f.keys()
		_fids.sort()
	return _fids


func _holds_land(who: String) -> bool:
	if not _idx_ok:
		_reindex()
	return _idx_owner.has(who) or _idx_tenant.has(who)


## Every NPC who can afford it bids on a farm that is for sale (one round). Bids rise a little over the standing bid.
func npc_bid_round(pid: String) -> int:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty() or (P["sale"] as Dictionary).is_empty():
		return 0
	var n := 0
	var ask := int(P["sale"]["ask"])
	for who: String in _farmer_ids():
		var w: Dictionary = _f[who]
		if who == String(P["owner"]) or int(w["bust"]) > _day or float(w["cash"]) < float(ask) * 0.8:
			continue
		var cap := npc_cap(who)
		var hi := highest_bid(pid)
		var want := ask if hi.is_empty() else int(ceil(float(hi["amt"]) * 1.05))
		if String(hi.get("who", "")) == who:
			continue
		if int(w["sid"]) != int(P["sid"]) and float(w["amb"]) < 0.6:
			continue
		var offer := mini(cap, int(round(float(want) * (1.0 + 0.06 * float(w["amb"])))))
		if offer < want:
			continue
		if bid(pid, who, offer) == "":
			n += 1
	return n


func _npc_let_bids(pid: String) -> void:
	var P: Dictionary = _p[pid]
	var l: Dictionary = P["let"]
	var floor_o := int(l["rent"]) if l["kind"] == "rent" else int(round(float(l["share"]) * 100.0))
	for who: String in _farmer_ids():
		var w: Dictionary = _f[who]
		if int(w["bust"]) > _day or _holds_land(who) or float(w["cash"]) < float(floor_o if l["kind"] == "rent" else 0):
			continue
		if int(w["sid"]) != int(P["sid"]) and float(w["amb"]) < 0.7:
			continue
		var jitter := float(hash([_day, who, pid]) % 1000) / 1000.0
		bid_tenancy(pid, who, int(round(float(floor_o) * (1.0 + 0.25 * float(w["amb"]) * jitter))))


func _npc_day(day: int) -> void:
	var k := 0
	for who: String in _farmer_ids():
		var w: Dictionary = _f[who]
		k += 1
		# Landless: wage work at home keeps them alive and saving.
		if not _holds_land(who):
			w["cash"] = int(w["cash"]) + 2
			if (day + k) % 7 == 0 and int(w["bust"]) <= day:
				_npc_seek(who)
			continue
		if (day + k) % 7 != 0:
			continue
		_npc_grow(who, day)


func _npc_seek(who: String) -> void:
	# Landless: bid on an offered tenancy in the home settlement (the closing round picks the best bid).
	for pid: String in listings():
		var P: Dictionary = _p[pid]
		if not (P["let"] as Dictionary).is_empty() and int(P["sid"]) == int(_f[who]["sid"]):
			var l: Dictionary = P["let"]
			if can_pay(who, int(l["rent"])) and rung(who) == "":
				bid_tenancy(pid, who, int(l["rent"]) if l["kind"] == "rent" else int(round(float(l["share"]) * 100.0)))
				return


func _npc_grow(who: String, _day_n: int) -> void:
	var w: Dictionary = _f[who]
	var held := rented_by(who)
	var owned := parcels_of(who)
	var amb := float(w["amb"])
	if not owned.is_empty():
		var pid: String = owned[0]
		var P: Dictionary = _p[pid]
		var cash := int(w["cash"])
		if (P["sale"] as Dictionary).is_empty() and cash > 140 + 20 * fields_count(pid) and fields_count(pid) + _pending_of(P, "field") < 8 and amb > 0.35:
			build(pid, "field", who)
		elif cash > 220 and building_count(P, "barn") + _pending_of(P, "barn") == 0 and amb > 0.45:
			build(pid, "barn", who)
		elif cash > 160 and herd_total(pid) < 3 + int(5.0 * amb) and building_count(P, "barn") > 0:
			buy_animals(pid, "cow" if amb > 0.5 else "sheep", 2, who)
		elif cash > 300 and building_count(P, "irrigation") + _pending_of(P, "irrigation") == 0 and amb > 0.6:
			build(pid, "irrigation", who)
		# Let spare land: a second farm for a tenant.
		if owned.size() < 3 and cash > 450 and amb > 0.6:
			var spare := _spare_listing_for(who)
			if spare != "":
				bid(spare, who, maxi(int(_p[spare]["sale"]["ask"]), 1))
	elif not held.is_empty():
		var pid2: String = held[0]
		var P2: Dictionary = _p[pid2]
		var price := value(pid2)
		if int(w["cash"]) >= int(float(price) * 1.2) and amb > 0.45 and (P2["sale"] as Dictionary).is_empty() and String(P2["owner"]).begins_with("lord:"):
			list_for_sale(pid2, price, String(P2["owner"]))


func _spare_listing_for(who: String) -> String:
	for pid: String in listings():
		var P: Dictionary = _p[pid]
		if not (P["sale"] as Dictionary).is_empty() and int(P["sid"]) == int(_f[who]["sid"]) and String(P["owner"]) != who:
			return pid
	return ""


## The Crown re-lets vacant land.
func _lord_relist() -> void:
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		if is_vacant(pid) and (P["let"] as Dictionary).is_empty() and (P["sale"] as Dictionary).is_empty():
			list_for_let(pid, "rent", -1, -1.0, 112)
		elif not (P["let"] as Dictionary).is_empty() and not (P["ten"] as Dictionary).is_empty():
			P["let"] = {}


func _market_round(day: int) -> Array:
	var out: Array = _deals(day)
	out.append_array(_npcs(day))
	return out


## The Crown re-lets, auctions close, lets close.
func _deals(day: int) -> Array:
	var out: Array = _sales(day)
	out.append_array(_lets(day))
	return out


func _sales(day: int) -> Array:
	var out: Array = []
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		if not (P["sale"] as Dictionary).is_empty():
			npc_bid_round(pid)
			if day >= int(P["sale"]["close"]):
				var buyer := close_sale(pid)
				if buyer != "" and (String(P["owner"]) == "player" or buyer == "player"):
					out.append("%s sells %s." % [who_name(buyer), String(P["name"])])
	return out


func _lets(day: int) -> Array:
	var out: Array = []
	_lord_relist()
	for pid: String in parcels():
		var P: Dictionary = _p[pid]
		if not (P["let"] as Dictionary).is_empty():
			_npc_let_bids(pid)
			if day >= int(P["let"]["close"]):
				var t := close_let(pid)
				if t == "player":
					out.append("You take the tenancy of %s." % String(P["name"]))
	return out


func _npcs(day: int) -> Array:
	_npc_day(day)
	if day % 7 == 0:
		_gen_contracts(day)
	var out: Array = log_lines.duplicate()
	log_lines.clear()
	return out


# ------------------------------------------------------------------ ticks

func _ppos(ctx: Dictionary) -> void:
	var pp: Variant = ctx.get("player_pos", null)
	if pp is Vector2:
		player_pos = pp
	elif pp is Vector3:
		player_pos = Vector2((pp as Vector3).x, (pp as Vector3).z)


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	_ppos(ctx)
	var ids := parcels()
	var chunks: Array = []
	var i := 0
	while i < ids.size():
		var slice: Array = ids.slice(i, i + CHUNK_FARMS)
		chunks.append(func() -> Array: return _chunk_farms(day, ctx, slice))
		i += CHUNK_FARMS
	chunks.append(func() -> Array: return _sales(day))
	chunks.append(func() -> Array: return _lets(day))
	chunks.append(func() -> Array: return _npcs(day))
	return chunks


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _chunk_farms(day: int, ctx: Dictionary, ids: Array) -> Array:
	_day = day
	for pid: String in ids:
		if _p.has(pid):
			_farm_step(_p[pid], day, ctx)
	_note_rung("player")
	return []


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


## Sleep / travel: farms advance in FAR_STEP blocks (at most a year of them), O(farms * weeks), never per day.
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	var blocks := mini(int(ceil(float(days) / 28.0)), 13)
	var start := _day
	for b in blocks:
		var d := start + mini(days, (b + 1) * 28)
		_day = d
		for pid: String in parcels():
			_farm_step_far(_p[pid], d, ctx)
		_market_round(d)
	_day = start + days
	return []


func _farm_step_far(P: Dictionary, day: int, ctx: Dictionary) -> void:
	var saved := player_pos
	player_pos = Vector2(1e9, 1e9)
	_farm_step(P, day, ctx)
	player_pos = saved


# ------------------------------------------------------------------ report

func summary(pid: String) -> Dictionary:
	var P: Dictionary = _p.get(pid, {})
	if P.is_empty():
		return {}
	var ready := 0
	for F: Dictionary in P["fields"]:
		if FF.is_ready(F):
			ready += 1
	return {"id": pid, "name": P["name"], "owner": P["owner"], "operator": operator(P), "legal": legal_status(pid), "value": value(pid),
		"fields": fields_count(pid), "ready": ready, "herd": herd_total(pid), "debt": debt_of(pid), "mode": P["mode"],
		"workers": workers_of(pid).size() + int(P["hands"]), "store": store_used(P), "cap": store_cap(P), "rent": rent_of(pid),
		"income": int(P["inc"]), "spend": int(P["out"])}


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var ps := {}
	for pid: String in _p:
		var P: Dictionary = _p[pid]
		var fs: Array = []
		for F: Dictionary in P["fields"]:
			fs.append(FF.pack(F))
		var d := {"s": P["sid"], "x": [snappedf(float(P["pos"][0]), 0.1), snappedf(float(P["pos"][1]), 0.1)],
			"o": P["owner"], "f": fs, "l": P["last"]}
		if P["name"] != "Farm %s" % String(pid).substr(3):
			d["n"] = P["name"]
		if not P["wt"]:
			d["wt"] = 0
		if P["plan"] != DEFAULT_PLAN:
			d["pl"] = P["plan"]
		if not (P["ten"] as Dictionary).is_empty():
			var t0: Dictionary = P["ten"]
			d["t"] = [t0["who"], 0 if t0["kind"] == "rent" else 1, int(t0["rent"]), snappedf(float(t0["share"]), 0.01), int(t0["since"]), int(t0["until"]),
				int(t0["next"]), int(t0["arrears"]), int(t0["missed"]), int(t0["dep"]), int(t0["notice"])]
		if not (P["mort"] as Dictionary).is_empty():
			d["m"] = P["mort"].duplicate()
		if int(P["wo"]) != 0:
			d["wo"] = P["wo"]
		if not (P["sale"] as Dictionary).is_empty():
			d["sa"] = P["sale"].duplicate(true)
		if not (P["let"] as Dictionary).is_empty():
			d["le"] = P["let"].duplicate(true)
		if not (P["bld"] as Array).is_empty():
			var bs: Array = []
			for b: Dictionary in P["bld"]:
				bs.append([b["k"], b["st"], int(b["site"]), int(b["due"]), 1 if b.get("npc", false) else 0])
			d["b"] = bs
		if int(P["lod"]) == 0 and not (P["herd"] as Array).is_empty():
			var hs: Array = []
			for a: Array in P["herd"]:
				hs.append([int(a[0]), int(a[1]), int(a[2]), snappedf(float(a[3]), 0.01), snappedf(float(a[4]), 0.01), int(a[5]), int(a[6]), int(a[7]), int(a[8])])
			d["h"] = hs
		elif int(P["lod"]) == 1 and not (P["co"] as Dictionary).is_empty():
			var co := {}
			for sp: String in P["co"]:
				co[sp] = FH.pack_cohort(P["co"][sp])
			d["c"] = co
		if not (P["store"] as Dictionary).is_empty():
			var st := {}
			for k: String in P["store"]:
				if float(P["store"][k]) >= 0.5:
					st[k] = int(round(float(P["store"][k]))) if float(P["store"][k]) >= 10.0 else snappedf(float(P["store"][k]), 0.1)
			d["st"] = st
		if not (P["ls"] as Dictionary).is_empty():
			d["ls"] = P["ls"].duplicate()
		if String(P["spec"]) != "":
			d["sp"] = P["spec"]
		if String(P["mode"]) != "manual":
			d["md"] = P["mode"]
		if String(P["gid"]) != "":
			d["g"] = P["gid"]
		if String(P["stw"]) != "":
			d["sw"] = P["stw"]
		if int(P["hands"]) != 0:
			d["hd"] = P["hands"]
		if float(P["inc"]) >= 1.0 or float(P["out"]) >= 1.0:
			d["lg"] = [int(P["inc"]), int(P["out"])]
		if int(P["stolen"]) != 0:
			d["sl"] = P["stolen"]
		ps[pid] = d
	var fm := {}
	for who: String in _f:
		var w: Dictionary = _f[who]
		fm[who] = [int(w["row"]), int(w["sid"]), w["name"], int(w["cash"]), w["amb"], int(w["neg"]), int(w["bust"]), int(w["busts"]), int(w.get("hand", 0))]
	return {"v": 1, "p": ps, "f": fm, "ct": _ct.duplicate(true), "pl": _pl.duplicate(), "nc": _next_c, "on": _own_n, "day": _day, "st": stats.duplicate(),
		"pg": pending_gold}


func deserialize(d: Dictionary) -> void:
	_p.clear()
	_f.clear()
	_order = []
	_idx_ok = false
	_inited = true
	_next_c = int(d.get("nc", 1))
	_own_n = int(d.get("on", 0))
	_day = int(d.get("day", 0))
	pending_gold = int(d.get("pg", 0))
	var pl: Dictionary = d.get("pl", {})
	for k: String in pl:
		_pl[k] = pl[k]
	for k2: String in ["exp", "fh_days", "last", "rep", "season_tenant"]:
		_pl[k2] = int(_pl[k2])
	for k3: String in (d.get("st", {}) as Dictionary):
		stats[k3] = int(d["st"][k3])
	for who: String in (d.get("f", {}) as Dictionary):
		var a: Array = d["f"][who]
		_f[who] = {"row": int(a[0]), "sid": int(a[1]), "name": a[2], "cash": int(a[3]), "amb": float(a[4]), "neg": int(a[5]), "bust": int(a[6]),
			"busts": int(a[7]), "hand": int(a[8]) if a.size() > 8 else 0}
	for pid: String in (d.get("p", {}) as Dictionary):
		var s: Dictionary = d["p"][pid]
		var fs: Array = []
		for a2: Array in s["f"]:
			fs.append(FF.unpack(a2))
		var sid := int(s["s"])
		var P := {"id": pid, "name": s.get("n", "Farm %s" % String(pid).substr(3)), "sid": sid, "kind": _kind_of(sid), "pos": [float(s["x"][0]), float(s["x"][1])],
			"clim": D.climate_of(sid), "owner": s["o"], "ten": {}, "mort": {}, "wo": int(s.get("wo", 0)), "sale": {}, "let": {},
			"fields": fs, "bld": [], "herd": [], "co": {}, "lod": 0, "spec": s.get("sp", ""), "store": {}, "ls": {},
			"plan": (s["pl"] as Array).duplicate() if s.has("pl") else DEFAULT_PLAN.duplicate(),
			"mode": s.get("md", "manual"), "gid": s.get("g", ""), "stw": s.get("sw", ""), "hands": int(s.get("hd", 0)), "inc": 0.0, "out": 0.0,
			"wt": int(s.get("wt", 1)) == 1, "last": int(s["l"]), "tx": -1, "stolen": int(s.get("sl", 0)), "num": _num(pid), "hist": []}
		if s.has("t"):
			var ta: Array = s["t"]
			P["ten"] = {"who": ta[0], "kind": "rent" if int(ta[1]) == 0 else "share", "rent": int(ta[2]), "share": float(ta[3]), "since": int(ta[4]),
				"until": int(ta[5]), "next": int(ta[6]), "arrears": int(ta[7]), "missed": int(ta[8]), "dep": int(ta[9]), "notice": int(ta[10])}
		if s.has("m"):
			var m: Dictionary = s["m"]
			for k5: String in ["principal", "next", "missed"]:
				m[k5] = int(m[k5])
			P["mort"] = m
		if s.has("sa"):
			var sa: Dictionary = s["sa"]
			sa["ask"] = int(sa["ask"])
			sa["close"] = int(sa["close"])
			for b: Dictionary in sa["bids"]:
				b["amt"] = int(b["amt"])
			P["sale"] = sa
		if s.has("le"):
			var le: Dictionary = s["le"]
			for k6: String in ["rent", "term", "close"]:
				le[k6] = int(le[k6])
			le["share"] = float(le["share"])
			for b2: Dictionary in le["bids"]:
				b2["offer"] = int(b2["offer"])
			P["let"] = le
		for b3: Array in s.get("b", []):
			P["bld"].append({"k": b3[0], "st": b3[1], "site": int(b3[2]), "due": int(b3[3]), "npc": int(b3[4]) == 1})
		for a3: Array in s.get("h", []):
			P["herd"].append([int(a3[0]), int(a3[1]), int(a3[2]), float(a3[3]), float(a3[4]), int(a3[5]), int(a3[6]), int(a3[7]), int(a3[8])])
		if s.has("c"):
			P["lod"] = 1
			for sp: String in s["c"]:
				P["co"][sp] = FH.unpack_cohort(s["c"][sp])
		for k7: String in s.get("st", {}):
			P["store"][k7] = float(s["st"][k7])
		for k8: String in s.get("ls", {}):
			P["ls"][k8] = float(s["ls"][k8])
		if s.has("lg"):
			P["inc"] = float(s["lg"][0])
			P["out"] = float(s["lg"][1])
		_p[pid] = P
	_ct = []
	for c: Dictionary in d.get("ct", []):
		for k9: String in ["id", "buyer", "qty", "price", "due", "got"]:
			c[k9] = int(c[k9])
		_ct.append(c)
