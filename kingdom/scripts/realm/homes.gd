extends "res://scripts/realm/realm_module.gd"
## Personal life (LW-8.3, docs/design/LIVING_WORLD_SANDBOX.md section 12): homes, households, education ages, relocation between towns and
## between kingdoms, and travel parties (`tp:n`). The player and the NPCs use the same calls.
##
## HOMES. A home (`pr:n` from the registry) is rented or bought in a town, can be one of several, is the primary residence of one household
## at a time and is paid for every week: a tenant pays rent, an owner pays upkeep (a share of the value) and the property levy of the town
## (stewardship.tax_rate). Unpaid rent or upkeep builds arrears; four weeks behind and a tenant is evicted, eight and an owner loses the
## house to the creditor. An empty or neglected house falls into disrepair (condition 0..100) and below 25 it is condemned. Offers are not
## stored: `listings(sid)` is a deterministic function of (seed, town, month) so a town has no per-house records until someone signs.
##
## HOUSEHOLDS (`hh:n`). Head, spouse, children (bounded) and dependants live on one record with a home. Children are rows
## `[born, sex, ed, stage]`, not Characters: they enter school at SCHOOL_AGE, an apprenticeship at APPRENTICE_AGE and become adult Characters
## (minds.spawn_adult) at ADULT_AGE. A noble house sends its children to an academy at ACADEMY_AGE. Births are a monthly roll per couple.
##
## RELOCATION. Within a kingdom the household moves, its job ends unless the employer has a branch in the new town, its owned homes are let
## and its farms and businesses are run from afar (their own remote-management rules). Between kingdoms the move is slower: titles are NOT
## recognised abroad (only an alliance pact or the crown's letter lifts them), trade/arms/build/practice need a local licence, the church
## kingdoms keep their borders closed to anyone without a writ of passage, and the history of every residence is kept.
##
## TRAVEL PARTIES. `form_party` makes a `tp:n` with provisions (person-days), hired escorts and a purse. Roads are protected (patrolled,
## low danger), ordinary or dangerous (emergence.gd and the household danger model raise it); each day of the journey rolls an encounter
## whose chance falls with the escort and the patrols. Hunger slows a party, a robbery takes gold and food, an attack can kill.
##
## Money: through organizations.pay / earn (player = pending_gold), never directly. No per-frame work: weekly upkeep, a daily party step,
## a monthly household sweep.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")

const YEAR := 360
const SCHOOL_AGE := 7
const ACADEMY_AGE := 9
const APPRENTICE_AGE := 12
const ADULT_AGE := 16
const HOME_MAX := 420
const HH_MAX := 700
const KIDS_MAX := 7
const PARTY_MAX := 64
const PARTY_LOG := 24
const PLAYER_HOMES_MAX := 6
const TUITION := 4
const EVICT_WEEKS := 4
const SEIZE_WEEKS := 8
const CONDEMNED := 25
const SPEED_FOOT := 30.0
const SPEED_CART := 38.0
const NO_ROAD := 1.0e8
const NO_DAY := -(1 << 40)
const HIST_MAX := 12

## kind -> {rent a week, price, upkeep a week, rooms}
const HOME_KINDS := {
	"hovel": {"rent": 5, "price": 220, "up": 1, "rooms": 1},
	"cottage": {"rent": 14, "price": 800, "up": 3, "rooms": 2},
	"house": {"rent": 34, "price": 2100, "up": 8, "rooms": 4},
	"manor": {"rent": 110, "price": 7600, "up": 30, "rooms": 9},
}
const KIND_ORDER := ["hovel", "cottage", "house", "manor"]
## Settlement kind -> price multiplier.
const TOWN_MULT := {"village": 1.0, "town": 1.3, "frontier_town": 1.1, "castle": 1.4, "city": 1.7, "capital": 2.1}
## kingdom -> border rule for incoming settlers.
const BORDER := {"solmarch": "closed", "varska_marches": "closed", "serathi_lowlands": "closed"}
const LICENCES := {"trade": {"fee": 40, "days": 20}, "arms": {"fee": 90, "days": 30}, "build": {"fee": 60, "days": 25}, "practice": {"fee": 50, "days": 20}}
const PASSAGE_FEE := 120
const ENTRY_FEE := {"closed": 60, "open": 10}

var _home: Dictionary = {}       # pr:n -> home
var _hh: Dictionary = {}         # hh:n -> household
var _of: Dictionary = {}         # who -> household id (a quick index, rebuilt on load)
var _prim: Dictionary = {}       # who -> primary home id
var _res: Dictionary = {}        # who -> residency {k, since, hist, lic, passage}
var _tp: Dictionary = {}         # tp:n -> party
var _road: Dictionary = {}       # "a|b" -> [delta, until_day]
var _seats: Dictionary = {}      # sid -> seats used in school
var _tplog: Array = []           # finished parties, one line each
var _day := 0
var _hb: Array = []
var _hb_n := -1
var stats := {"rented": 0, "bought": 0, "sold": 0, "evictions": 0, "seized": 0, "condemned": 0, "marriages": 0, "births": 0, "enrolled": 0,
	"graduated": 0, "relocations": 0, "emigrations": 0, "turned_back": 0, "parties": 0, "arrived": 0, "robbed": 0, "attacked": 0, "deaths_on_road": 0,
	"licences": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _om() -> Variant:
	return _mod("organizations")


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 2) -> void:
	Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, w)


func _mint(prefix: String) -> String:
	var reg: Variant = _mod("registry")
	return String(reg.mint(prefix)) if reg != null else "%s:t%d" % [prefix, _home.size() + _hh.size() + _tp.size() + 1]


func _pay(who: String, amt: int) -> bool:
	var om: Variant = _om()
	return om.pay(who, amt) if om != null else true


func _earn(who: String, amt: int) -> void:
	var om: Variant = _om()
	if om != null:
		om.earn(who, amt)


func _purse(who: String) -> int:
	var om: Variant = _om()
	return int(om.purse(who)) if om != null else 1 << 20


func _kind_mult(sid: int) -> float:
	return float(TOWN_MULT.get(PD.kind_of(sid), 1.0))


# ------------------------------------------------------------------ homes

## Offers in a town this month: [{id, kind, rent, price, sid}]. A function of the seed, the town and the month only.
func listings(sid: int, day := -1) -> Array:
	var out: Array = []
	var month := (_now() if day < 0 else day) / 30
	var m := _kind_mult(sid)
	var pop := int(PD.settlement(sid).get("population", 200))
	var n := clampi(2 + pop / 200, 2, 6)
	for i in n:
		var h := absi(hash([WorldSim.SEED, "hl", sid, month, i]))
		var kind: String = KIND_ORDER[(h % 100) * 3 / 100 + (1 if i == n - 1 and pop > 600 else 0)]
		var def: Dictionary = HOME_KINDS[kind]
		var swing := 0.85 + float((h / 100) % 30) / 100.0
		out.append({"id": "L%d.%d.%d" % [sid, month, i], "kind": kind, "rent": maxi(1, int(round(float(def["rent"]) * m * swing))),
			"price": int(round(float(def["price"]) * m * swing)), "sid": sid})
	return out


func home(hid: String) -> Dictionary:
	return (_home.get(hid, {}) as Dictionary).duplicate(true)


func home_count() -> int:
	return _home.size()


func homes_of(who: String) -> Array:
	var out: Array = []
	for hid: Variant in _home:
		var h: Dictionary = _home[hid]
		if String(h["owner"]) == who or String(h["tenant"]) == who:
			out.append(String(hid))
	out.sort()
	return out


func primary_home(who: String) -> String:
	return String(_prim.get(who, ""))


## Where `who` lives (a town id), -1 when nowhere.
func residence_sid(who: String) -> int:
	var hh: Dictionary = _hh.get(String(_of.get(who, "")), {})
	if not hh.is_empty() and int(hh["sid"]) >= 0:
		return int(hh["sid"])
	var h: Dictionary = _home.get(String(_prim.get(who, "")), {})
	return int(h["sid"]) if not h.is_empty() else -1


func _sync_household(who: String, hid: String) -> void:
	var hh: Dictionary = _hh.get(String(_of.get(who, "")), {})
	var h: Dictionary = _home.get(hid, {})
	if not hh.is_empty() and not h.is_empty():
		hh["sid"] = int(h["sid"])
		hh["home"] = hid


func _new_home(who: String, sid: int, kind: String, own: bool, rent: int, price: int) -> Dictionary:
	var hid := _mint("pr")
	var def: Dictionary = HOME_KINDS[kind]
	_home[hid] = {"sid": sid, "k": PD.kingdom_of(sid), "kind": kind, "owner": who if own else "", "tenant": who if not own else "",
		"rent": rent, "price": price, "cond": 90.0, "arr": 0, "weeks": 0, "let": 0, "rooms": int(def["rooms"]), "since": _now(), "lord": "" if own else "lord"}
	return {"id": hid}


## Rent a house from a listing (`listing_id`, or the cheapest of `kind` in the town when empty). Pays two weeks as a deposit.
func rent_home(who: String, sid: int, kind := "cottage", listing_id := "") -> Dictionary:
	if _home.size() >= HOME_MAX:
		return {"ok": false, "reason": "The town has no more houses on offer."}
	if who == "player" or who.begins_with("ch:"):
		if homes_of(who).size() >= PLAYER_HOMES_MAX and _is_player(who):
			return {"ok": false, "reason": "You cannot keep so many houses."}
	var pick: Dictionary = {}
	for l: Dictionary in listings(sid):
		if (listing_id != "" and String(l["id"]) == listing_id) or (listing_id == "" and String(l["kind"]) == kind and (pick.is_empty() or int(l["rent"]) < int(pick["rent"]))):
			pick = l
			if listing_id != "":
				break
	if pick.is_empty():
		return {"ok": false, "reason": "Nothing like that is for let here."}
	var deposit := int(pick["rent"]) * 2
	if not _pay(who, deposit):
		return {"ok": false, "reason": "A deposit of %d gold is asked." % deposit}
	var r := _new_home(who, sid, String(pick["kind"]), false, int(pick["rent"]), int(pick["price"]))
	var h: Dictionary = _home[r["id"]]
	h["dep"] = deposit
	stats["rented"] = int(stats["rented"]) + 1
	if not _prim.has(who):
		_prim[who] = r["id"]
		_sync_household(who, String(r["id"]))
	_ev("trade", sid, [who], "rent_home", "A %s is let" % pick["kind"], 1)
	return {"ok": true, "home": r["id"], "rent": int(pick["rent"]), "kind": pick["kind"], "deposit": deposit}


func buy_home(who: String, sid: int, kind := "house", listing_id := "") -> Dictionary:
	if _home.size() >= HOME_MAX:
		return {"ok": false, "reason": "The town has no more houses on offer."}
	if _is_player(who) and homes_of(who).size() >= PLAYER_HOMES_MAX:
		return {"ok": false, "reason": "You cannot keep so many houses."}
	var pick: Dictionary = {}
	for l: Dictionary in listings(sid):
		if (listing_id != "" and String(l["id"]) == listing_id) or (listing_id == "" and String(l["kind"]) == kind):
			pick = l
			break
	if pick.is_empty():
		return {"ok": false, "reason": "Nothing like that is for sale here."}
	if not _pay(who, int(pick["price"])):
		return {"ok": false, "reason": "The price is %d gold." % int(pick["price"])}
	var r := _new_home(who, sid, String(pick["kind"]), true, 0, int(pick["price"]))
	stats["bought"] = int(stats["bought"]) + 1
	if not _prim.has(who):
		_prim[who] = r["id"]
		_sync_household(who, String(r["id"]))
	_ev("trade", sid, [who], "buy_home", "A %s is bought" % pick["kind"], 2)
	return {"ok": true, "home": r["id"], "price": int(pick["price"]), "kind": pick["kind"]}


func _is_player(who: String) -> bool:
	if who == "player":
		return true
	var reg: Variant = _mod("registry")
	return reg != null and who != "" and who == String(reg.lookup("pl:player"))


func sell_home(hid: String, who: String) -> Dictionary:
	var h: Dictionary = _home.get(hid, {})
	if h.is_empty() or String(h["owner"]) != who:
		return {"ok": false, "reason": "It is not yours to sell."}
	var got := int(float(h["price"]) * (0.5 + 0.4 * float(h["cond"]) / 100.0)) - int(h["arr"])
	_earn(who, maxi(0, got))
	_drop_home(hid)
	stats["sold"] = int(stats["sold"]) + 1
	return {"ok": true, "gold": maxi(0, got)}


func end_tenancy(hid: String, who: String) -> Dictionary:
	var h: Dictionary = _home.get(hid, {})
	if h.is_empty() or String(h["tenant"]) != who:
		return {"ok": false, "reason": "You do not rent that."}
	var back := maxi(0, int(h.get("dep", 0)) - int(h["arr"]))
	_earn(who, back)
	_drop_home(hid)
	return {"ok": true, "gold": back}


func _drop_home(hid: String) -> void:
	_home.erase(hid)
	for who: Variant in _prim.keys():
		if String(_prim[who]) == hid:
			_prim.erase(who)
			for cand: String in homes_of(String(who)):
				if int((_home[cand] as Dictionary)["let"]) == 0:
					_prim[who] = cand
					break


## The owner lets a house out to the town's families: it earns 80% of the rent on weeks it is occupied (a hash of the week), and is not primary.
func let_out(hid: String, who: String, rent := -1) -> bool:
	var h: Dictionary = _home.get(hid, {})
	if h.is_empty() or String(h["owner"]) != who:
		return false
	h["let"] = 1
	h["rent"] = rent if rent > 0 else int(float((HOME_KINDS[h["kind"]] as Dictionary)["rent"]) * _kind_mult(int(h["sid"])))
	if String(_prim.get(who, "")) == hid:
		_prim.erase(who)
	return true


func set_primary(who: String, hid: String) -> bool:
	var h: Dictionary = _home.get(hid, {})
	if h.is_empty() or (String(h["owner"]) != who and String(h["tenant"]) != who):
		return false
	h["let"] = 0
	_prim[who] = hid
	var hh: Dictionary = _hh.get(String(_of.get(who, "")), {})
	if not hh.is_empty():
		hh["sid"] = int(h["sid"])
		hh["home"] = hid
	return true


## What `who` pays a week for all houses (rent + upkeep + levy), the income from let ones is not counted.
func upkeep_due(who: String) -> int:
	var t := 0
	for hid: String in homes_of(who):
		t += _weekly_cost(_home[hid], who)
	return t


func _weekly_cost(h: Dictionary, who: String) -> int:
	if String(h["tenant"]) == who and String(h["owner"]) != who:
		return int(h["rent"])
	var def: Dictionary = HOME_KINDS[h["kind"]]
	var st: Variant = _mod("stewardship")
	var levy := float(st.tax_rate(int(h["sid"]))) if st != null else 0.1
	return maxi(1, int(round(float(def["up"]) * _kind_mult(int(h["sid"])) + float(h["price"]) * levy * 0.002)))


func _week_homes(week: int) -> void:
	var ids: Array = _home.keys()
	ids.sort()
	for hid: String in ids:
		var h: Dictionary = _home[hid]
		var lived := _occupied(hid, h)
		# A house nobody lives in or lets falls into disrepair faster.
		h["cond"] = clampf(float(h["cond"]) - (0.4 if lived else 1.6), 0.0, 100.0)
		var owner := String(h["owner"])
		var tenant := String(h["tenant"])
		if int(h["let"]) == 1 and owner != "":
			# Let to the town's families: income when the hash says the house is taken this week.
			if absi(hash([WorldSim.SEED, "let", hid, week])) % 100 < 85:
				_earn(owner, int(float(h["rent"]) * 0.8))
			h["cond"] = clampf(float(h["cond"]) - 0.5, 0.0, 100.0)
			var up_l := _weekly_cost(h, owner)
			_settle(hid, h, owner, up_l, true)
			continue
		var payer := tenant if tenant != "" else owner
		if payer == "":
			continue
		var amt := _weekly_cost(h, payer)
		if tenant != "" and owner != "" and owner != tenant:
			_settle(hid, h, tenant, amt, false)
			if int(h["arr"]) == 0:
				_earn(owner, amt)
		else:
			_settle(hid, h, payer, amt, tenant == "")
		if _home.has(hid) and float(h["cond"]) < CONDEMNED and not bool(h.get("cd", false)):
			h["cd"] = true
			stats["condemned"] = int(stats["condemned"]) + 1
			_ev("emergency", int(h["sid"]), [payer], "condemned", "A house is condemned", 2)


## Rent / upkeep paid this week: the ledger's weekly summary and the quarter's payment driver (the payment itself stays here).
func _note_cost(h: Dictionary, who: String, amt: int, owner_side: bool) -> void:
	var rent := not owner_side and String(h["tenant"]) == who and String(h["owner"]) != who
	var lg: Variant = _mod("ledger")
	if lg != null:
		lg.note(who, String(h["owner"]) if rent else "tr:%d" % int(h["sid"]), "rent" if rent else "upkeep", amt)
	var dv: Variant = _mod("districts")
	if dv != null:
		dv.on_payment(int(h["sid"]), {"hovel": "poor", "cottage": "poor", "house": "other", "manor": "noble"}.get(String(h["kind"]), "other"), "rent" if rent else "tax", amt)


func _occupied(hid: String, h: Dictionary) -> bool:
	var who := String(h["tenant"]) if String(h["tenant"]) != "" else String(h["owner"])
	return String(_prim.get(who, "")) == hid


func _settle(hid: String, h: Dictionary, who: String, amt: int, owner_side: bool) -> void:
	if _pay(who, amt):
		_note_cost(h, who, amt, owner_side)
		if int(h["arr"]) > 0 and _pay(who, mini(int(h["arr"]), maxi(0, _purse(who) / 2))):
			h["arr"] = 0
		h["weeks"] = 0
		if not owner_side:
			return
		# Upkeep paid on a house somebody lives in (or that is let) keeps it in repair; an empty one only pays its levy.
		if _occupied(hid, h) or int(h["let"]) == 1:
			h["cond"] = clampf(float(h["cond"]) + 1.0, 0.0, 100.0)
		return
	h["arr"] = int(h["arr"]) + amt
	h["weeks"] = int(h["weeks"]) + 1
	if not owner_side and int(h["weeks"]) >= EVICT_WEEKS:
		stats["evictions"] = int(stats["evictions"]) + 1
		_ev("crime", int(h["sid"]), [who], "evicted", "A family is evicted", 3)
		var rep: Variant = _mod("reputation")
		if rep != null:
			rep.record("i:" + who, "reliability", -4.0, int(h["sid"]), "trader")
		_drop_home(hid)
	elif owner_side and int(h["weeks"]) >= SEIZE_WEEKS:
		stats["seized"] = int(stats["seized"]) + 1
		_ev("crime", int(h["sid"]), [who], "seized", "A house is taken for debt", 3)
		_drop_home(hid)


# ------------------------------------------------------------------ households

func household(hid: String) -> Dictionary:
	return (_hh.get(hid, {}) as Dictionary).duplicate(true)


func household_of(who: String) -> String:
	return String(_of.get(who, ""))


func household_count() -> int:
	return _hh.size()


func ensure_household(who: String, sid := -1) -> String:
	var cur := String(_of.get(who, ""))
	if cur != "":
		return cur
	if _hh.size() >= HH_MAX:
		return ""
	var hid := _mint("hh")
	_hh[hid] = {"sid": sid if sid >= 0 else residence_sid(who), "head": who, "sp": "", "kids": [], "mem": [], "home": String(_prim.get(who, "")), "house": "", "since": _now(), "mv": -1, "tp": ""}
	_of[who] = hid
	return hid


## People who depend on `who`: children and dependants of the household they head (a spouse counts as one).
func dependents(who: String) -> int:
	var hid := String(_of.get(who, ""))
	if hid == "":
		return 0
	var hh: Dictionary = _hh[hid]
	if String(hh["head"]) != who and String(hh["sp"]) != who:
		return 0
	return (hh["kids"] as Array).size() + (hh["mem"] as Array).size() + (1 if String(hh["sp"]) != "" else 0)


func add_member(hid: String, ch: String, role := "dependant") -> bool:
	var hh: Dictionary = _hh.get(hid, {})
	if hh.is_empty() or (hh["mem"] as Array).size() >= 6 or String(_of.get(ch, "")) not in ["", hid]:
		return false
	(hh["mem"] as Array).append([ch, role])
	_of[ch] = hid
	return true


func members(hid: String) -> Array:
	var hh: Dictionary = _hh.get(hid, {})
	if hh.is_empty():
		return []
	var out: Array = [String(hh["head"])]
	if String(hh["sp"]) != "":
		out.append(String(hh["sp"]))
	for m: Array in hh["mem"]:
		out.append(String(m[0]))
	return out


func food_cost_week(hid: String) -> int:
	var hh: Dictionary = _hh.get(hid, {})
	if hh.is_empty():
		return 0
	return 4 * (members(hid).size() + (hh["kids"] as Array).size())


func marry(a: String, b: String, opts: Dictionary = {}) -> Dictionary:
	if a == b or a == "" or b == "":
		return {"ok": false, "reason": "Two people are needed."}
	for w: String in [a, b]:
		var hid0 := String(_of.get(w, ""))
		if hid0 != "" and String((_hh[hid0] as Dictionary)["sp"]) != "":
			return {"ok": false, "reason": "Already married."}
	var sid := int(opts.get("sid", residence_sid(a) if residence_sid(a) >= 0 else residence_sid(b)))
	var ha := String(_of.get(a, ""))
	var hb := String(_of.get(b, ""))
	var hid := ha if ha != "" else (hb if hb != "" else ensure_household(a, sid))
	if hid == "":
		return {"ok": false, "reason": "No room for another household."}
	var hh: Dictionary = _hh[hid]
	var head := String(hh["head"])
	var other := b if head == a else a
	if head != a and head != b:
		other = b
	hh["sp"] = other
	_of[other] = hid
	if hb != "" and hb != hid:
		# The other household is folded in: children come along.
		var o: Dictionary = _hh[hb]
		for k: Array in o["kids"]:
			if (hh["kids"] as Array).size() < KIDS_MAX:
				(hh["kids"] as Array).append(k)
		_hh.erase(hb)
	if sid >= 0:
		hh["sid"] = sid
	if String(opts.get("house", "")) != "":
		hh["house"] = String(opts["house"])
	stats["marriages"] = int(stats["marriages"]) + 1
	var rep: Variant = _mod("reputation")
	if rep != null and bool(opts.get("well", false)):
		rep.on_deed("i:" + head, "married_well", sid, 0.5)
	_ev("marriage", sid, [a, b], "wedding", "A wedding", 3)
	var mn: Variant = _mod("minds")
	if mn != null:
		mn.on_married(a, b, hid)
	return {"ok": true, "hh": hid, "head": head}


func widow(who: String) -> void:
	var hid := String(_of.get(who, ""))
	if hid == "":
		return
	var hh: Dictionary = _hh.get(hid, {})
	_of.erase(who)
	if hh.is_empty():
		return
	if String(hh["head"]) == who:
		if String(hh["sp"]) != "":
			hh["head"] = hh["sp"]
			hh["sp"] = ""
		else:
			var left := (hh["mem"] as Array)
			if left.is_empty() and (hh["kids"] as Array).is_empty():
				_hh.erase(hid)
			elif not left.is_empty():
				hh["head"] = (left[0] as Array)[0]
				left.remove_at(0)
			else:
				hh["head"] = ""        # orphans: they are taken in by kin (see _sweep)
	elif String(hh["sp"]) == who:
		hh["sp"] = ""
	else:
		hh["mem"] = (hh["mem"] as Array).filter(func(m: Array) -> bool: return String(m[0]) != who)
	if _hh.has(hid) and members(hid).is_empty() or (_hh.has(hid) and String(hh["head"]) == "" and (hh["kids"] as Array).is_empty()):
		_hh.erase(hid)


## Children as rows with computed age/stage: [{i, age, sex, stage, ed}]
func children(hid: String) -> Array:
	var out: Array = []
	var hh: Dictionary = _hh.get(hid, {})
	var i := 0
	for k: Array in hh.get("kids", []):
		var age := (_now() - int(k[0])) / YEAR
		out.append({"i": i, "age": age, "sex": String(k[1]), "ed": int(k[2]), "stage": stage_of(age, bool(hh.get("noble", false)), int(k[3])), "born": int(k[0])})
		i += 1
	return out


static func stage_of(age: int, noble := false, state := 0) -> String:
	if age < SCHOOL_AGE:
		return "child"
	if noble and age >= ACADEMY_AGE and age < ADULT_AGE:
		return "academy"
	if age < APPRENTICE_AGE:
		return "school" if state != 9 else "working"
	if age < ADULT_AGE:
		return "apprentice"
	return "adult"


func add_child(hid: String, born := NO_DAY, sex := "") -> bool:
	var hh: Dictionary = _hh.get(hid, {})
	if hh.is_empty() or (hh["kids"] as Array).size() >= KIDS_MAX:
		return false
	var b := born if born != NO_DAY else _now()
	var sx := sex if sex != "" else ("m" if absi(hash([WorldSim.SEED, "csx", hid, b, (hh["kids"] as Array).size()])) % 2 == 0 else "f")
	(hh["kids"] as Array).append([b, sx, 0, 0])
	return true


func _sweep(day: int) -> void:
	# Monthly: every household is looked at on its own day of the month (id hash), so the work is spread.
	if _hb_n != _hh.size() or _hb.is_empty() or day % 30 == 0:
		_hb = []
		for i in 30:
			_hb.append([])
		for k: Variant in _hh:
			(_hb[String(k).hash() % 30] as Array).append(String(k))
		_hb_n = _hh.size()
	for hid: String in (_hb[day % 30] as Array).duplicate():
		var hh: Dictionary = _hh.get(hid, {})
		if hh.is_empty():
			continue
		_births(hid, hh, day)
		_schooling(hid, hh, day)
		_orphans(hid, hh)


func _births(hid: String, hh: Dictionary, day: int) -> void:
	var sp := String(hh["sp"])
	if sp == "" or (hh["kids"] as Array).size() >= KIDS_MAX - 1:
		return
	var mn: Variant = _mod("minds")
	if mn == null:
		return
	var wa: int = mn.age_of(sp)
	var ha: int = mn.age_of(String(hh["head"]))
	var wife_age := mini(wa, ha) if wa >= 0 and ha >= 0 else maxi(wa, ha)
	if wife_age < 18 or wife_age > 41:
		return
	var rich := clampf(float(_purse(String(hh["head"]))) / 300.0, 0.0, 1.0)
	var p := 0.045 * (1.0 - 0.012 * float((hh["kids"] as Array).size() * 5)) * (0.7 + 0.5 * rich)
	var em: Variant = _mod("emergence")
	if em != null:
		p *= float(em.fertility_mult(int(hh["sid"])))
	if float(absi(hash([WorldSim.SEED, "birth", hid, day])) % 10000) / 10000.0 < p:
		if add_child(hid):
			stats["births"] = int(stats["births"]) + 1
			_ev("birth", int(hh["sid"]), [String(hh["head"]), sp], "birth", "A child is born", 2)


func _schooling(hid: String, hh: Dictionary, _day2: int) -> void:
	var sid := int(hh["sid"])
	var keep: Array = []
	for k: Array in hh["kids"]:
		var age := (_now() - int(k[0])) / YEAR
		var noble := bool(hh.get("noble", false))
		if age >= ADULT_AGE:
			var mn: Variant = _mod("minds")
			var ch := ""
			if mn != null:
				ch = String(mn.spawn_adult(hid, k))
			if ch != "":
				stats["graduated"] = int(stats["graduated"]) + 1
				continue
			continue                        # an aggregate adult now: the town absorbs them
		if age >= APPRENTICE_AGE and int(k[3]) != 2:
			# Twelve: school ends and the child is placed with a master (a seat is given back).
			if int(k[3]) == 1:
				_seats[sid] = maxi(0, int(_seats.get(sid, 0)) - 1)
			k[3] = 2
		elif age >= SCHOOL_AGE and int(k[3]) == 0:
			# Enrol if there is a seat and the family can pay; otherwise the child works.
			var used := int(_seats.get(sid, 0))
			if used < school_seats(sid) and _purse(String(hh["head"])) >= TUITION * 3:
				k[3] = 1
				_seats[sid] = used + 1
				stats["enrolled"] = int(stats["enrolled"]) + 1
			else:
				k[3] = 9
		if int(k[3]) == 1:
			if _pay(String(hh["head"]), TUITION):
				k[2] = mini(3, int(k[2]) + (1 if noble or age % 3 == 0 else 0))
				_earn_school(sid, TUITION)
			else:
				k[3] = 9
				_seats[sid] = maxi(0, int(_seats.get(sid, 0)) - 1)
		keep.append(k)
	hh["kids"] = keep
	if keep.is_empty() and String(hh["head"]) == "":
		_hh.erase(hid)


func _earn_school(_sid: int, _amt: int) -> void:
	pass


func _orphans(hid: String, hh: Dictionary) -> void:
	if String(hh["head"]) != "" or (hh["kids"] as Array).is_empty():
		return
	# Orphans go to the oldest household in the town with room (kin are not tracked for commoners).
	for other: String in _hh:
		var o: Dictionary = _hh[other]
		if other != hid and int(o["sid"]) == int(hh["sid"]) and String(o["head"]) != "" and (o["kids"] as Array).size() + (hh["kids"] as Array).size() <= KIDS_MAX:
			(o["kids"] as Array).append_array(hh["kids"])
			_hh.erase(hid)
			return


func school_seats(sid: int) -> int:
	var pop := int(PD.settlement(sid).get("population", 200))
	var seats := pop / 20
	var fa: Variant = _mod("faith")
	if fa != null:
		seats += int(fa.school_seats(sid))
	return seats


# ------------------------------------------------------------------ roads

func _rk(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


## Emergence raises (or lowers) the danger of one road until `until` (a day).
func set_road_mod(a: int, b: int, delta: float, until: int) -> void:
	_road[_rk(a, b)] = [clampf(delta, -0.5, 0.9), until]


func road_mod(a: int, b: int) -> float:
	var r: Array = _road.get(_rk(a, b), [])
	if r.is_empty() or _now() > int(r[1]):
		return 0.0
	return float(r[0])


func road_protection(a: int, b: int) -> float:
	var ar: Variant = _mod("armies")
	if ar == null:
		return 0.0
	var dr := float(ar.defence_rating(a)) + float(ar.defence_rating(b))
	return clampf(dr * 0.02, 0.0, 0.5)


func road_danger(a: int, b: int) -> float:
	var hh: Variant = _mod("household")
	var base := float(hh.leg_danger(a, b, {})) if hh != null else 0.12
	return clampf(base + road_mod(a, b) - road_protection(a, b), 0.0, 0.95)


## "protected" (patrolled and calm), "ordinary" or "dangerous".
func road_status(a: int, b: int) -> String:
	var d := road_danger(a, b)
	if d >= 0.4:
		return "dangerous"
	if road_protection(a, b) >= 0.1 and d < 0.2:
		return "protected"
	return "ordinary"


# ------------------------------------------------------------------ travel parties

func party(tp: String) -> Dictionary:
	return (_tp.get(tp, {}) as Dictionary).duplicate(true)


func active_parties() -> Array:
	var out: Array = []
	for k: Variant in _tp:
		if String((_tp[k] as Dictionary)["st"]) == "travelling":
			out.append(String(k))
	out.sort()
	return out


func party_count() -> int:
	return _tp.size()


## Provisions a trip needs (person-days) for `people` over `from`->`to`.
func provisions_needed(from_sid: int, to_sid: int, people: int, cart := false) -> int:
	var nw: Variant = _mod("news")
	var dist := float(nw.road_distance(from_sid, to_sid)) if nw != null else 300.0
	if dist >= NO_ROAD:
		return 0
	return int(ceil(dist / (SPEED_CART if cart else SPEED_FOOT))) * people


func form_party(leader: String, members_: Array, from_sid: int, to_sid: int, opts: Dictionary = {}) -> Dictionary:
	if active_parties().size() >= PARTY_MAX:
		return {"ok": false, "reason": "The roads are crowded with travellers."}
	var nw: Variant = _mod("news")
	var dist := float(nw.road_distance(from_sid, to_sid)) if nw != null else 300.0
	if from_sid == to_sid or dist >= NO_ROAD:
		return {"ok": false, "reason": "There is no road."}
	var cart := bool(opts.get("cart", false))
	var speed := SPEED_CART if cart else SPEED_FOOT
	var eta_days := maxi(1, int(ceil(dist / speed)))
	var people := 1 + members_.size()
	var esc := clampi(int(opts.get("escorts", 0)), 0, 12)
	var food := int(opts.get("provisions", 0))
	var wage := int(opts.get("escort_wage", 3))
	var fee := esc * wage * eta_days
	if fee > 0 and not _pay(leader, fee):
		return {"ok": false, "reason": "The escort wants %d gold." % fee}
	var buy := int(opts.get("buy_provisions", 0))
	if buy > 0:
		if not _pay(leader, buy * 2):
			if fee > 0:
				_earn(leader, fee)
			return {"ok": false, "reason": "Provisions cost 2 gold a ration."}
		food += buy
	var carry := mini(int(opts.get("gold", 0)), _purse(leader))
	if carry > 0:
		_pay(leader, carry)
	var tp := _mint("tp")
	_tp[tp] = {"lead": leader, "mem": members_.duplicate(), "from": from_sid, "to": to_sid, "pos": 0.0, "dist": dist, "speed": speed, "food": food, "esc": esc,
		"gold": carry, "st": "travelling", "d0": _now(), "eta": _now() + eta_days, "hurt": 0, "lost": [], "rel": String(opts.get("rel", "")), "tk": String(opts.get("tk", "")),
		"log": ["day %d: leaves %s" % [_now(), PD.sname(from_sid)]]}
	stats["parties"] = int(stats["parties"]) + 1
	var mn: Variant = _mod("minds")
	if mn != null:
		for w: Variant in [leader] + members_:
			mn.set_travelling(String(w), tp)
	_ev("trade", from_sid, [leader], "party_leaves", "A party sets out for %s" % PD.sname(to_sid), 1)
	return {"ok": true, "tp": tp, "eta": _now() + eta_days, "people": people, "paid": fee + buy * 2}


## Buy rations on the road (at a town the party passes). Only while travelling.
func buy_rations(tp: String, qty: int) -> bool:
	var p: Dictionary = _tp.get(tp, {})
	if p.is_empty() or String(p["st"]) != "travelling" or qty <= 0:
		return false
	if int(p["gold"]) < qty * 3:
		return false
	p["gold"] = int(p["gold"]) - qty * 3
	p["food"] = int(p["food"]) + qty
	return true


func _plog(p: Dictionary, line: String) -> void:
	var l: Array = p["log"]
	l.append("day %d: %s" % [_now(), line])
	if l.size() > 6:
		l.pop_front()


func _step_party(tp: String, p: Dictionary, day: int) -> void:
	var people := 1 + (p["mem"] as Array).size() - (p["lost"] as Array).size()
	var rations := people + int(p["esc"])
	var speed := float(p["speed"])
	if int(p["food"]) >= rations:
		p["food"] = int(p["food"]) - rations
	else:
		p["food"] = 0
		speed *= 0.5
		p["hurt"] = int(p["hurt"]) + 1
		_plog(p, "goes hungry")
	if int(p["hurt"]) >= 5 and absi(hash([WorldSim.SEED, "starve", tp, day])) % 100 < 20:
		_lose_member(tp, p, "hunger")
	var a := int(p["from"])
	var b := int(p["to"])
	var danger := road_danger(a, b)
	var protect := clampf(float(p["esc"]) * 0.12, 0.0, 0.7)
	var chance := danger * (1.0 - protect) * 0.35
	var roll := float(absi(hash([WorldSim.SEED, "enc", tp, day])) % 10000) / 10000.0
	if roll < chance:
		var kind := absi(hash([WorldSim.SEED, "enck", tp, day])) % 100
		if protect > 0.3 and kind < 40:
			_plog(p, "the escort drives off raiders")
		elif kind < 55:
			var loss := int(float(p["gold"]) * 0.3)
			p["gold"] = int(p["gold"]) - loss
			p["food"] = int(float(p["food"]) * 0.6)
			stats["robbed"] = int(stats["robbed"]) + 1
			_plog(p, "is robbed of %d gold" % loss)
		elif kind < 80:
			speed *= 0.4
			_plog(p, "is delayed on a bad road")
		elif danger > 0.4 and protect < 0.4 and (p["mem"] as Array).size() > (p["lost"] as Array).size():
			_lose_member(tp, p, "attack")
		else:
			p["hurt"] = int(p["hurt"]) + 1
			_plog(p, "is hurt in an ambush")
	p["pos"] = float(p["pos"]) + speed
	if float(p["pos"]) >= float(p["dist"]):
		_arrive(tp, p)


func _lose_member(tp: String, p: Dictionary, why: String) -> void:
	for m: Variant in p["mem"]:
		if not (p["lost"] as Array).has(m):
			(p["lost"] as Array).append(m)
			stats["deaths_on_road"] = int(stats["deaths_on_road"]) + 1
			stats["attacked"] = int(stats["attacked"]) + 1
			_plog(p, "loses %s to %s" % [m, why])
			var mn: Variant = _mod("minds")
			if mn != null:
				mn.die(String(m), "road")
			_ev("death", int(p["from"]), [String(m)], "road_" + why, "A traveller dies on the road", 3)
			return


func _arrive(tp: String, p: Dictionary) -> void:
	p["st"] = "arrived"
	var to := int(p["to"])
	stats["arrived"] = int(stats["arrived"]) + 1
	_plog(p, "reaches %s" % PD.sname(to))
	var who: Array = [String(p["lead"])]
	for m: Variant in p["mem"]:
		if not (p["lost"] as Array).has(m):
			who.append(String(m))
	_earn(String(p["lead"]), int(p["gold"]))
	p["gold"] = 0
	var mn: Variant = _mod("minds")
	for w: Variant in who:
		if mn != null:
			mn.set_travelling(String(w), "")
		_move_char(String(w), to)
	var hid := String(_of.get(String(p["lead"]), ""))
	if hid != "" and String(p["rel"]) == "relocate":
		var hh: Dictionary = _hh.get(hid, {})
		if not hh.is_empty():
			hh["sid"] = to
			hh["mv"] = _now()
			hh["tp"] = ""
	_finish_party(tp, p)


func _finish_party(tp: String, p: Dictionary) -> void:
	_tplog.append("%s %s->%s %s d%d" % [tp, PD.sname(int(p["from"])), PD.sname(int(p["to"])), p["st"], _now()])
	if _tplog.size() > PARTY_LOG:
		_tplog.pop_front()


func _drop_old_parties(day: int) -> void:
	for tp: String in _tp.keys():
		var p: Dictionary = _tp[tp]
		if String(p["st"]) != "travelling" and day - int(p["eta"]) > 20:
			_tp.erase(tp)


func party_history() -> Array:
	return _tplog.duplicate()


## Turn a party back (the leader decides the road is too dangerous).
func turn_back(tp: String) -> bool:
	var p: Dictionary = _tp.get(tp, {})
	if p.is_empty() or String(p["st"]) != "travelling":
		return false
	p["st"] = "turned_back"
	stats["turned_back"] = int(stats["turned_back"]) + 1
	var mn: Variant = _mod("minds")
	if mn != null:
		for w: Variant in [p["lead"]] + (p["mem"] as Array):
			mn.set_travelling(String(w), "")
	_plog(p, "turns back")
	_finish_party(tp, p)
	return true


func _party_day(day: int) -> void:
	var ids := active_parties()
	for tp: String in ids:
		_step_party(tp, _tp[tp], day)


# ------------------------------------------------------------------ relocation

## Move a household to another town of the same kingdom. Job ends (unless a branch of the employer is there), owned homes are let, the
## primary home is given up, farms and businesses stay and are run from afar. Travel is by party when `travel` is true.
func relocate(who: String, to_sid: int, opts: Dictionary = {}) -> Dictionary:
	var from := residence_sid(who)
	if from < 0 and _om() != null and _om().has_char(who):
		from = int((_om().char_rec(who) as Dictionary).get("sid", -1))      # no household yet: they live where their record says
	if to_sid < 0 or PD.settlement(to_sid).is_empty():
		return {"ok": false, "reason": "There is no such place."}
	if from == to_sid:
		return {"ok": false, "reason": "You live there already."}
	var hid := ensure_household(who, from)
	var moved: Array = ["household"]
	var om: Variant = _om()
	var emp: Dictionary = om.employment(who) if om != null else {}
	if not emp.is_empty():
		var kept := false
		var by := String(emp.get("by", ""))
		if by.begins_with("org:") and om != null:
			for oid: String in om.orgs_in(to_sid, String(om.org(by).get("type", ""))):
				if oid != by and om.apply(oid, who, "").get("ok", false):
					kept = true
					break
		if not kept:
			if by.begins_with("bz:") and _mod("businesses") != null:
				_mod("businesses").fire(by, who)
			if om != null:
				om.unemploy(who)
		moved.append("job kept" if kept else "job ended")
	var let_n := 0
	var gave := ""
	for h: String in homes_of(who):
		var hm: Dictionary = _home[h]
		if String(hm["owner"]) == who:
			if let_out(h, who):
				let_n += 1
		elif String(hm["tenant"]) == who and int(hm["sid"]) != to_sid:
			end_tenancy(h, who)
			gave = h
	if let_n > 0:
		moved.append("%d homes let" % let_n)
	var hh: Dictionary = _hh[hid]
	var all: Array = members(hid)
	all.erase(who)
	hh["tp"] = ""
	var travel := bool(opts.get("travel", false))
	var res := {"ok": true, "moved": moved, "from": from, "to": to_sid, "hh": hid, "property": _property_kept(who)}
	if travel:
		var need := provisions_needed(from, to_sid, 1 + all.size(), true) + 1 + all.size()
		var fp := form_party(who, all, from, to_sid, {"rel": "relocate", "provisions": int(opts.get("provisions", 0)), "buy_provisions": int(opts.get("buy_provisions", need)),
			"escorts": int(opts.get("escorts", 0)), "cart": true, "gold": int(opts.get("gold", 0))})
		if not bool(fp["ok"]):
			return fp
		hh["tp"] = fp["tp"]
		res["tp"] = fp["tp"]
	else:
		hh["sid"] = to_sid
		hh["mv"] = _now()
		for w: String in members(hid):
			_move_char(w, to_sid)
	if _mod("farming") != null:
		for pid: String in _mod("farming").rented_by(who):
			_mod("farming").end_tenancy(pid, who)
			(res["moved"] as Array).append("tenancy ended")
	stats["relocations"] = int(stats["relocations"]) + 1
	_ev("trade", to_sid, [who], "relocated", "A household moves to %s" % PD.sname(to_sid), 2)
	var rep: Variant = _mod("rumours")
	if rep != null and _is_player(who):
		rep.note_player("moved", to_sid, 8.0)
	if gave != "":
		(res["moved"] as Array).append("home given up")
	return res


## What stays behind and is run remotely: [{kind, id}]
## A character lives in another town now: the minds index and the organizations record move together.
func _move_char(w: String, to_sid: int) -> void:
	var mn: Variant = _mod("minds")
	var om: Variant = _om()
	if mn != null and mn.is_mind(w):
		mn.set_town(w, to_sid)
	elif om != null and om.has_char(w):
		(om.char_rec(w) as Dictionary)["sid"] = to_sid


func _property_kept(who: String) -> Array:
	var out: Array = []
	var bz: Variant = _mod("businesses")
	if bz != null:
		for b: Variant in bz.owned_by(who):
			out.append({"kind": "business", "id": String(b)})
	var fm: Variant = _mod("farming")
	if fm != null:
		for p: Variant in fm.parcels_of(who):
			out.append({"kind": "farm", "id": String(p)})
	for h: String in homes_of(who):
		if String(_home[h]["owner"]) == who:
			out.append({"kind": "home", "id": h})
	return out


# ------------------------------------------------------------------ kingdoms

func residency(who: String) -> Dictionary:
	var r: Dictionary = _res.get(who, {})
	if r.is_empty():
		return {"k": PD.HOME, "since": 0, "hist": [], "lic": {}, "passage": 0}
	return r.duplicate(true)


func kingdom_of(who: String) -> String:
	return String((_res.get(who, {}) as Dictionary).get("k", PD.HOME))


func history(who: String) -> Array:
	return (residency(who)["hist"] as Array).duplicate()


## Is a title of `who` (earned in `origin`) honoured in `kingdom`? Only at home, or under an alliance pact between the two.
func title_recognised(origin: String, kingdom: String) -> bool:
	if origin == kingdom:
		return true
	var dp: Variant = _mod("diplomacy")
	if dp == null:
		return false
	for a: Dictionary in dp.agreements(origin, "active"):
		if String(a.get("type", "")) == "alliance" and (String(a["a"]) == kingdom or String(a["b"]) == kingdom):
			return true
	return false


## The rank `who` may use in the kingdom they live in (0 when their title comes from elsewhere and is not recognised).
func rank_in(who: String, kingdom := "") -> int:
	var k := kingdom if kingdom != "" else kingdom_of(who)
	var au: Variant = _mod("audiences")
	var rank := int(au.rank_of(who)) if au != null else 0
	var origin := String((_res.get(who, {}) as Dictionary).get("origin", PD.HOME))
	return rank if title_recognised(origin, k) else 0


func has_licence(who: String, kind: String, kingdom := "") -> bool:
	var k := kingdom if kingdom != "" else kingdom_of(who)
	if k == String((_res.get(who, {}) as Dictionary).get("origin", PD.HOME)) and not _res.has(who):
		return true                              # never left home: the home licences apply
	var lic: Dictionary = (_res.get(who, {}) as Dictionary).get("lic", {})
	return int(lic.get("%s|%s" % [k, kind], -1)) > _now()


func apply_licence(who: String, kind: String) -> Dictionary:
	if not LICENCES.has(kind):
		return {"ok": false, "reason": "Unknown licence."}
	var r: Dictionary = _res.get(who, {})
	if r.is_empty():
		return {"ok": true, "reason": "You need no licence at home.", "fee": 0}
	var def: Dictionary = LICENCES[kind]
	if _now() - int(r["since"]) < int(def["days"]):
		return {"ok": false, "reason": "The clerks want you resident for %d days first." % int(def["days"])}
	if kind == "practice" and String(BORDER.get(r["k"], "")) == "closed":
		var fa: Variant = _mod("faith")
		if fa != null and float(fa.belief_of(who)) < 30.0:
			return {"ok": false, "reason": "The church will not license the unbelieving."}
	if not _pay(who, int(def["fee"])):
		return {"ok": false, "reason": "The licence costs %d gold." % int(def["fee"])}
	(r["lic"] as Dictionary)["%s|%s" % [r["k"], kind]] = _now() + 360
	stats["licences"] = int(stats["licences"]) + 1
	return {"ok": true, "fee": int(def["fee"])}


## A writ of passage lets a stranger through a closed border (a pilgrim's, a merchant's or one bought).
func buy_passage(who: String, kingdom: String) -> Dictionary:
	if String(BORDER.get(kingdom, "open")) != "closed":
		return {"ok": true, "fee": 0}
	var fa: Variant = _mod("faith")
	var fee := PASSAGE_FEE
	if fa != null and float(fa.belief_of(who)) >= 40.0 and String(fa.faith_of(who)) == "dawn":
		fee = PASSAGE_FEE / 3
	if not _pay(who, fee):
		return {"ok": false, "reason": "A writ of passage costs %d gold." % fee}
	var r: Dictionary = _res.get(who, {})
	if r.is_empty():
		r = {"k": PD.HOME, "origin": PD.HOME, "since": 0, "hist": [], "lic": {}, "passage": 0}
		_res[who] = r
	r["passage"] = _now() + 90
	return {"ok": true, "fee": fee}


## Move the household to another kingdom. Titles stop counting (rank_in), licences are asked for again, the history of residences is kept.
func emigrate(who: String, kingdom: String, reason := "") -> Dictionary:
	if not PD.is_kingdom(kingdom):
		return {"ok": false, "reason": "No such kingdom."}
	var r: Dictionary = _res.get(who, {})
	if r.is_empty():
		r = {"k": PD.HOME, "origin": PD.HOME, "since": 0, "hist": [], "lic": {}, "passage": 0}
	if String(r["k"]) == kingdom:
		return {"ok": false, "reason": "You live there already."}
	var rule := String(BORDER.get(kingdom, "open"))
	if rule == "closed" and int(r["passage"]) < _now():
		stats["turned_back"] = int(stats["turned_back"]) + 1
		return {"ok": false, "reason": "The border is closed: a writ of passage is needed."}
	var fee := int(ENTRY_FEE[rule])
	if not _pay(who, fee):
		return {"ok": false, "reason": "The border post asks %d gold." % fee}
	var hist: Array = r["hist"]
	hist.append([String(r["k"]), int(r["since"]), _now(), reason])
	if hist.size() > HIST_MAX:
		hist.pop_front()
	r["k"] = kingdom
	r["since"] = _now()
	r["lic"] = {}
	_res[who] = r
	var hid := String(_of.get(who, ""))
	if hid != "":
		(_hh[hid] as Dictionary)["k"] = kingdom
	stats["emigrations"] = int(stats["emigrations"]) + 1
	_ev("founding", -1, [who], "emigrated", "A household leaves for %s" % PD.kingdom_name(kingdom), 3)
	var fa: Variant = _mod("faith")
	if fa != null:
		fa.on_emigrated(who, kingdom)
	var rep: Variant = _mod("reputation")
	if rep != null:
		rep.record("i:" + who, "legitimacy", -3.0, -1, "none")
	return {"ok": true, "fee": fee, "rank_here": rank_in(who, kingdom), "needs": ["trade", "arms", "build", "practice"]}


# ------------------------------------------------------------------ days

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_party_day(day)
	_sweep(day)
	if day % 30 == 0:
		_seats = {}
		_drop_old_parties(day)
		for hid: Variant in _hh:
			var k: Array = (_hh[hid] as Dictionary)["kids"]
			var sid := int((_hh[hid] as Dictionary)["sid"])
			for row: Array in k:
				if int(row[3]) == 1:
					_seats[sid] = int(_seats.get(sid, 0)) + 1
		for k2: Variant in _road.keys():
			if day > int((_road[k2] as Array)[1]):
				_road.erase(k2)
	return []


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_week_homes(week)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Parties finish, a few weeks of rent are settled in closed form, the sweep is a month's worth at most.
	_day += days
	for tp: String in active_parties():
		var p: Dictionary = _tp[tp]
		_arrive(tp, p)
	for i in mini(days / 7, 4):
		_week_homes(_day / 7 - i)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var homes: Dictionary = {}
	for hid: Variant in _home:
		var h: Dictionary = _home[hid]
		homes[hid] = [int(h["sid"]), String(h["kind"]), String(h["owner"]), String(h["tenant"]), int(h["rent"]), int(h["price"]), snappedf(float(h["cond"]), 0.1),
			int(h["arr"]), int(h["weeks"]), int(h["let"]), int(h["since"]), int(h.get("dep", 0)), 1 if bool(h.get("cd", false)) else 0]
	var hhs: Dictionary = {}
	for hid: Variant in _hh:
		var hh: Dictionary = _hh[hid]
		hhs[hid] = [int(hh["sid"]), String(hh["head"]), String(hh["sp"]), (hh["kids"] as Array).duplicate(true), (hh["mem"] as Array).duplicate(true),
			String(hh["home"]), String(hh["house"]), int(hh["since"]), int(hh["mv"]), String(hh["tp"]), 1 if bool(hh.get("noble", false)) else 0, String(hh.get("k", ""))]
	var road: Dictionary = {}
	for k: Variant in _road:
		road[k] = _road[k]
	return {"home": homes, "hh": hhs, "prim": _prim.duplicate(), "res": _res.duplicate(true), "tp": _tp.duplicate(true), "road": road, "log": _tplog.duplicate(),
		"day": _day, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_home = {}
	_hh = {}
	_of = {}
	_prim = {}
	_res = {}
	_tp = {}
	_road = {}
	_seats = {}
	_tplog = []
	var homes: Dictionary = d.get("home", {})
	for hid: Variant in homes:
		var a: Array = homes[hid]
		var sid := int(a[0])
		var own := String(a[2])
		_home[String(hid)] = {"sid": sid, "k": PD.kingdom_of(sid), "kind": String(a[1]), "owner": own, "tenant": String(a[3]), "rent": int(a[4]), "price": int(a[5]),
			"cond": float(a[6]), "arr": int(a[7]), "weeks": int(a[8]), "let": int(a[9]), "rooms": int((HOME_KINDS[String(a[1])] as Dictionary)["rooms"]), "since": int(a[10]),
			"lord": "" if own != "" else "lord", "dep": int(a[11]), "cd": int(a[12]) == 1}
	var hhs: Dictionary = d.get("hh", {})
	for hid: Variant in hhs:
		var a: Array = hhs[hid]
		var kids: Array = []
		for k: Variant in a[3]:
			var kk: Array = k
			kids.append([int(kk[0]), String(kk[1]), int(kk[2]), int(kk[3])])
		var mem: Array = []
		for m: Variant in a[4]:
			mem.append([String((m as Array)[0]), String((m as Array)[1])])
		_hh[String(hid)] = {"sid": int(a[0]), "head": String(a[1]), "sp": String(a[2]), "kids": kids, "mem": mem, "home": String(a[5]), "house": String(a[6]),
			"since": int(a[7]), "mv": int(a[8]), "tp": String(a[9]), "noble": int(a[10]) == 1, "k": String(a[11])}
		for w: String in members(String(hid)):
			_of[w] = String(hid)
	var pr: Dictionary = d.get("prim", {})
	for k: Variant in pr:
		_prim[String(k)] = String(pr[k])
	var rs: Dictionary = d.get("res", {})
	for k: Variant in rs:
		var r: Dictionary = (rs[k] as Dictionary).duplicate(true)
		var hist: Array = []
		for h: Variant in r.get("hist", []):
			hist.append([String((h as Array)[0]), int((h as Array)[1]), int((h as Array)[2]), String((h as Array)[3])])
		r["hist"] = hist
		r["since"] = int(r.get("since", 0))
		r["passage"] = int(r.get("passage", 0))
		var lic: Dictionary = {}
		for l: Variant in r.get("lic", {}):
			lic[String(l)] = int((r["lic"] as Dictionary)[l])
		r["lic"] = lic
		_res[String(k)] = r
	var tps: Dictionary = d.get("tp", {})
	for k: Variant in tps:
		var p: Dictionary = (tps[k] as Dictionary).duplicate(true)
		for f: String in ["from", "to", "food", "esc", "gold", "d0", "eta", "hurt"]:
			p[f] = int(p.get(f, 0))
		p["pos"] = float(p.get("pos", 0.0))
		p["dist"] = float(p.get("dist", 0.0))
		p["speed"] = float(p.get("speed", SPEED_FOOT))
		_tp[String(k)] = p
	var rd: Dictionary = d.get("road", {})
	for k: Variant in rd:
		_road[String(k)] = [float((rd[k] as Array)[0]), int((rd[k] as Array)[1])]
	for l: Variant in d.get("log", []):
		_tplog.append(String(l))
	_day = int(d.get("day", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
