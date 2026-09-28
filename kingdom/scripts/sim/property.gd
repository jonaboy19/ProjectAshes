extends RefCounted
## Real house lots the player can rent or buy in any settlement, from
## WorldGen.settlements[i]["plan"]["lots"] (see scripts/world/city_planner.gd).
## Registered lazily per settlement, the same way scripts/sim/homestead.gd
## finds its plots: a pure, deterministic function of the settlement's plan
## and the world seed, recomputed (never serialised) each run.
##
## Vacancy: about VACANCY_FRACTION of a settlement's house lots (house_*,
## mhouse_peasant_a/b/family/trader/manor) are flagged vacant and offered for
## rent or sale, chosen once per settlement with a seeded shuffle so it is the
## same lots every run and the town isn't emptied out.
##
## Kind (from the lot's asset): cottage (house_*, mhouse_peasant_a/b), family
## house (mhouse_family), trader's house (mhouse_trader: a shop front with a
## workshop), manor (mhouse_manor: workshop + servants). A weekly inn room
## ("s<idx>:inn", where that settlement has an inn lot) is always offered too:
## a bed only, no storage, no workshop, never for sale.
##
## Landlord: for now "the Crown" in towns and castles, "Lord of <settlement>"
## in villages (a later phase adds noble houses the player can deal with
## directly; `landlord_id` is kept as a plain string for that).
##
## Tenure: rent (weekly, a bed and, for a house, storage & family space), buy
## (sell back at SELL_FRACTION), or the bare inn room. Missed weekly rent
## builds debt; MISSED_RENT_LIMIT misses evicts the tenant (their chest is
## kept EVICTION_GRACE_DAYS days, then cleared and the lot goes back to
## vacant). Unpaid seasonal land tax on an *owned* property (owed even though
## you own the building — see docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Property,
## nobility, lordship") accrues as debt and dents trade reputation.
##
## Pure data (RefCounted, serialisable: only per-lot player state is saved,
## the registry itself is rebuilt from WorldGen + the seed). Driven by
## scripts/world/village_services.gd's notice board / inn / Pack menus;
## scripts/interiors/interior_door.gd reads is_yours() for its door prompt;
## scripts/world/home_chest.gd is the in-world storage chest.

const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")

const VACANCY_FRACTION := 0.2
const DAYS_PER_WEEK := 7
const SEASON_DAYS := 28              # scripts/sim/seasons.gd's DAYS_PER_SEASON
const MISSED_RENT_LIMIT := 2
const EVICTION_GRACE_DAYS := 7
const SELL_FRACTION := 0.8
const TAX_REP_HIT := 1.5             # trade reputation lost per missed season of land tax

## asset -> kind; anything else house-shaped (house_1..16, mhouse_peasant_a/b) is a cottage.
const ASSET_KIND := {
	"mhouse_manor": "manor",
	"mhouse_trader": "trader",
	"mhouse_family": "family",
}
const DEFAULT_KIND := "cottage"

## kind -> {name, tier (1 small .. 3 largest), base price at a village, storage
## slots (distinct item stacks), status points, workshop flag, servants (manor flavour)}.
const KIND_INFO := {
	"cottage": {"name": "Cottage", "tier": 1, "base": 220, "storage": 10, "status": 1,
		"workshop": false, "servants": []},
	"family": {"name": "Family house", "tier": 2, "base": 420, "storage": 16, "status": 2,
		"workshop": false, "servants": []},
	"trader": {"name": "Trader's house", "tier": 2, "base": 650, "storage": 18, "status": 3,
		"workshop": true, "servants": []},
	"manor": {"name": "Manor", "tier": 3, "base": 1700, "storage": 28, "status": 6,
		"workshop": true, "servants": ["a cook", "a groundskeeper", "a stable hand", "a maid"]},
}
## A settlement's size multiplies price, rent and tax.
const SETTLEMENT_MULT := {"village": 1.0, "town": 1.7, "castle": 2.6}
const RENT_FRACTION := 0.015     # of price, per week
const TAX_FRACTION := 0.012      # of price, per season
const INN_ROOM_BASE_RENT := 10   # gold per week at a village-sized inn

## lot_id -> {settlement, lot_index, asset, kind, tier, name, landlord_id,
##            price, rent, tax, pos: Vector2, yaw, is_inn_room, settlement_name}
var _registry: Dictionary = {}
## "x.xx,z.zz" -> lot_id, for interior_door.gd's is_yours(world_pos) lookup.
var _pos_index: Dictionary = {}
var _registered: Dictionary = {}     # settlement idx -> true

## lot_id -> {status: "" / "owned" / "rented" / "rented_room" / "evicted",
##   rent_due_day, missed_rent, debt (unpaid rent, gold), tax_due_day,
##   tax_debt (unpaid land tax, gold), rented_since, evict_day,
##   storage: [{item, qty}]}
var state: Dictionary = {}
var _last_day := -1


# --- registration --------------------------------------------------------------------

func _ensure_registered(settlement_idx: int) -> void:
	if _registered.has(settlement_idx):
		return
	_registered[settlement_idx] = true
	if settlement_idx < 0 or settlement_idx >= WorldGen.settlements.size():
		return
	var s: Dictionary = WorldGen.settlements[settlement_idx]
	var lots: Array = s["plan"].get("lots", [])
	var mult := float(SETTLEMENT_MULT.get(String(s["kind"]), 1.0))
	var landlord := _landlord_for(s)
	var house_idx: Array[int] = []
	var inn_idx := -1
	for i in lots.size():
		var asset := String(lots[i]["asset"])
		if BuildingProfiles.is_house(asset):
			house_idx.append(i)
		elif asset == "inn" and inn_idx < 0:
			inn_idx = i
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSim.SEED + settlement_idx * 92821 + 4051
	_seeded_shuffle(house_idx, rng)
	var vacant_n := 0 if house_idx.is_empty() else maxi(1, int(floor(house_idx.size() * VACANCY_FRACTION)))
	for k in vacant_n:
		var i: int = house_idx[k]
		var lot: Dictionary = lots[i]
		var asset := String(lot["asset"])
		var kind: String = ASSET_KIND.get(asset, DEFAULT_KIND)
		var info: Dictionary = KIND_INFO[kind]
		var price := int(round(float(info["base"]) * mult))
		var lot_id := "s%d:l%d" % [settlement_idx, i]
		_registry[lot_id] = {
			"lot_id": lot_id, "settlement": settlement_idx, "settlement_name": String(s["name"]),
			"lot_index": i, "asset": asset, "kind": kind, "tier": int(info["tier"]), "name": String(info["name"]),
			"landlord_id": landlord, "price": price, "rent": maxi(2, int(round(price * RENT_FRACTION))),
			"tax": maxi(1, int(round(price * TAX_FRACTION))), "pos": lot["pos"], "yaw": float(lot["yaw"]),
			"is_inn_room": false,
		}
		_pos_index[_pos_key(lot["pos"])] = lot_id
	if inn_idx >= 0:
		var inn_lot: Dictionary = lots[inn_idx]
		var inn_id := "s%d:inn" % settlement_idx
		_registry[inn_id] = {
			"lot_id": inn_id, "settlement": settlement_idx, "settlement_name": String(s["name"]),
			"lot_index": inn_idx, "asset": "inn", "kind": "inn_room", "tier": 0, "name": "Inn room",
			"landlord_id": "the innkeeper", "price": -1, "rent": maxi(2, int(round(INN_ROOM_BASE_RENT * mult))),
			"tax": 0, "pos": inn_lot["pos"], "yaw": float(inn_lot["yaw"]), "is_inn_room": true,
		}


static func _seeded_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _landlord_for(s: Dictionary) -> String:
	return ("Lord of %s" % String(s["name"])) if String(s["kind"]) == "village" else "the Crown"


static func _pos_key(p: Vector2) -> String:
	return "%.2f,%.2f" % [p.x, p.y]


func _ensure_all_registered() -> void:
	for i in WorldGen.settlements.size():
		_ensure_registered(i)


# --- lookup ----------------------------------------------------------------------------

## Vacant, purchasable/rentable house lots in a settlement (not the inn room; see rent_room()).
func available(settlement_idx: int) -> Array[String]:
	_ensure_registered(settlement_idx)
	var out: Array[String] = []
	for lot_id: String in _registry:
		var r: Dictionary = _registry[lot_id]
		if int(r["settlement"]) == settlement_idx and not bool(r["is_inn_room"]) and _is_vacant(lot_id):
			out.append(lot_id)
	return out


func _is_vacant(lot_id: String) -> bool:
	if not state.has(lot_id):
		return true
	return String(state[lot_id].get("status", "")) == ""


func has_inn_room(settlement_idx: int) -> bool:
	_ensure_registered(settlement_idx)
	return _registry.has("s%d:inn" % settlement_idx)


func inn_room_id(settlement_idx: int) -> String:
	return "s%d:inn" % settlement_idx


func registered(lot_id: String) -> bool:
	return _registry.has(lot_id)


## The lot_id whose registered world position matches `pos` (interior doors'
## "lot_pos" meta), or "" if none (not a house lot, or not yet registered).
func find_by_pos(pos: Vector2) -> String:
	_ensure_all_registered()
	return String(_pos_index.get(_pos_key(pos), ""))


func is_held(lot_id: String) -> bool:
	return String(state.get(lot_id, {}).get("status", "")) in ["owned", "rented", "rented_room"]


func is_owned(lot_id: String) -> bool:
	return String(state.get(lot_id, {}).get("status", "")) == "owned"


## True if the door at this world position belongs to a property the player
## owns or rents (interior_door.gd's "Enter your home" hook).
func is_yours(pos: Vector2) -> bool:
	var lot_id := find_by_pos(pos)
	return lot_id != "" and is_held(lot_id)


## Registry + player-state fields for one lot_id, or {} if unknown.
func info(lot_id: String) -> Dictionary:
	if not _registry.has(lot_id):
		return {}
	var out: Dictionary = (_registry[lot_id] as Dictionary).duplicate()
	var st: Dictionary = state.get(lot_id, {})
	out["status"] = String(st.get("status", ""))
	out["missed_rent"] = int(st.get("missed_rent", 0))
	out["debt"] = int(st.get("debt", 0))
	out["tax_debt"] = int(st.get("tax_debt", 0))
	out["storage"] = (st.get("storage", []) as Array).duplicate(true)
	out["has_bed"] = true
	out["workshop"] = bool(KIND_INFO.get(String(out.get("kind", "")), {}).get("workshop", false))
	out["servants"] = (KIND_INFO.get(String(out.get("kind", "")), {}).get("servants", []) as Array).duplicate()
	out["status_points"] = int(KIND_INFO.get(String(out.get("kind", "")), {}).get("status", 0))
	return out


func owned() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lot_id: String in state:
		if is_owned(lot_id):
			out.append(info(lot_id))
	return out


func rented() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lot_id: String in state:
		var status := String(state[lot_id].get("status", ""))
		if status == "rented" or status == "rented_room":
			out.append(info(lot_id))
	return out


## The best held property with a bed (owned beats rented, bigger tier beats
## smaller), or {} if the player holds none. The inn room always has a bed too.
func home() -> Dictionary:
	var best := {}
	var best_score := -1
	for lot_id: String in state:
		if not is_held(lot_id):
			continue
		var i := info(lot_id)
		var score := int(i["tier"]) + (10 if i["status"] == "owned" else 0)
		if score > best_score:
			best_score = score
			best = i
	return best


# --- tenure: rent / buy / sell ---------------------------------------------------------

func can_rent(lot_id: String) -> String:
	if not _registry.has(lot_id) or bool(_registry[lot_id]["is_inn_room"]):
		return "No such house."
	if not _is_vacant(lot_id):
		return "Already taken."
	return ""


## Rents a house lot for `weeks` (bed, storage, family space); "" on success.
func rent(lot_id: String, weeks := 1) -> String:
	var why := can_rent(lot_id)
	if why != "":
		return why
	weeks = maxi(1, weeks)
	var r: Dictionary = _registry[lot_id]
	var cost := int(r["rent"]) * weeks
	if Game.gold < cost:
		return "Needs %d gold (have %d)." % [cost, Game.gold]
	Game.add_gold(-cost)
	var day := WorldSim.day
	state[lot_id] = {"status": "rented", "rent_due_day": day + weeks * DAYS_PER_WEEK, "missed_rent": 0,
		"debt": 0, "tax_due_day": 0, "tax_debt": 0, "rented_since": day, "evict_day": -1, "storage": []}
	return "You rent %s in %s for %d week%s (%d gold)." % [String(r["name"]).to_lower(), r["settlement_name"],
		weeks, "" if weeks == 1 else "s", cost]


## Rents the settlement's inn room by the week: a bed only, no storage.
func rent_room(settlement_idx: int, weeks := 1) -> String:
	if not has_inn_room(settlement_idx):
		return "No inn here."
	var lot_id := inn_room_id(settlement_idx)
	weeks = maxi(1, weeks)
	var r: Dictionary = _registry[lot_id]
	var cost := int(r["rent"]) * weeks
	if Game.gold < cost:
		return "Needs %d gold (have %d)." % [cost, Game.gold]
	Game.add_gold(-cost)
	var day := WorldSim.day
	var cur: Dictionary = state.get(lot_id, {})
	var due := day + weeks * DAYS_PER_WEEK
	if String(cur.get("status", "")) == "rented_room":
		due = int(cur.get("rent_due_day", day)) + weeks * DAYS_PER_WEEK
	state[lot_id] = {"status": "rented_room", "rent_due_day": due, "missed_rent": 0, "debt": 0,
		"tax_due_day": 0, "tax_debt": 0, "rented_since": day, "evict_day": -1, "storage": []}
	return "You take a room at the %s Inn for %d week%s (%d gold)." % [r["settlement_name"], weeks,
		"" if weeks == 1 else "s", cost]


func can_buy(lot_id: String) -> String:
	if not _registry.has(lot_id) or bool(_registry[lot_id]["is_inn_room"]):
		return "Not for sale."
	if not _is_vacant(lot_id):
		return "Already taken."
	return ""


## Buys a house lot outright; "" on success. Adds a biography highlight.
func buy(lot_id: String) -> String:
	var why := can_buy(lot_id)
	if why != "":
		return why
	var r: Dictionary = _registry[lot_id]
	var price := int(r["price"])
	if Game.gold < price:
		return "Needs %d gold (have %d)." % [price, Game.gold]
	Game.add_gold(-price)
	var day := WorldSim.day
	state[lot_id] = {"status": "owned", "rent_due_day": 0, "missed_rent": 0, "debt": 0,
		"tax_due_day": day + SEASON_DAYS, "tax_debt": 0, "rented_since": day, "evict_day": -1, "storage": []}
	var kind_name: String = String(r["name"]).to_lower()
	var article := "an" if "aeiou".contains(kind_name.substr(0, 1)) else "a"
	Life.biography.add_highlight("Bought %s %s in %s" % [article, kind_name, r["settlement_name"]], day)
	return "You now own %s in %s (%d gold). Land tax is owed to %s every season." % [kind_name,
		r["settlement_name"], price, r["landlord_id"]]


## Sells an owned lot back at SELL_FRACTION of its price; "" on success.
## Refuses while the chest still holds anything (empty it first).
func sell(lot_id: String) -> String:
	if not is_owned(lot_id):
		return "You don't own this."
	var st: Dictionary = state[lot_id]
	if not (st.get("storage", []) as Array).is_empty():
		return "Empty your storage chest first."
	var r: Dictionary = _registry[lot_id]
	var refund := int(round(int(r["price"]) * SELL_FRACTION))
	Game.add_gold(refund)
	state.erase(lot_id)
	return "You sell %s in %s for %d gold." % [String(r["name"]).to_lower(), r["settlement_name"], refund]


# --- dues --------------------------------------------------------------------------------

## Pays off outstanding rent/tax debt on one lot (or every held lot if lot_id
## is ""), as far as Game.gold allows. Returns a summary line.
func pay_due(lot_id := "") -> String:
	var ids: Array = [lot_id] if lot_id != "" else state.keys().duplicate()
	var paid := 0
	for id: String in ids:
		if not state.has(id):
			continue
		var st: Dictionary = state[id]
		var owed := int(st.get("debt", 0)) + int(st.get("tax_debt", 0))
		if owed <= 0:
			continue
		var pay := mini(owed, Game.gold - paid)
		if pay <= 0:
			continue
		var tax_debt := int(st.get("tax_debt", 0))
		var tax_pay := mini(pay, tax_debt)
		st["tax_debt"] = tax_debt - tax_pay
		st["debt"] = int(st.get("debt", 0)) - (pay - tax_pay)
		paid += pay
	if paid > 0:
		Game.add_gold(-paid)
		return "Paid %d gold in dues." % paid
	return "Nothing to pay." if _total_debt() == 0 else "Not enough gold to pay any of it."


func _total_debt() -> int:
	var t := 0
	for id: String in state:
		t += int(state[id].get("debt", 0)) + int(state[id].get("tax_debt", 0))
	return t


func total_debt() -> int:
	return _total_debt()


## Rent (weekly) and land tax (seasonal) due, missed payments, eviction and
## the eviction grace period. Call once per in-game day (life.gd's daily
## tick, e.g. `Life.property.daily(WorldSim.day)`); a repeat call the same
## day is a no-op. Returns messages worth telling the player.
func daily(day: int) -> Array[String]:
	if day == _last_day:
		return []
	_last_day = day
	var out: Array[String] = []
	for lot_id: String in state.keys().duplicate():
		var st: Dictionary = state[lot_id]
		var status := String(st.get("status", ""))
		match status:
			"rented", "rented_room":
				out.append_array(_tick_rent(lot_id, st, day))
			"owned":
				out.append_array(_tick_tax(lot_id, st, day))
			"evicted":
				if day - int(st.get("evict_day", day)) >= EVICTION_GRACE_DAYS:
					state.erase(lot_id)
	return out


func _tick_rent(lot_id: String, st: Dictionary, day: int) -> Array[String]:
	if day < int(st.get("rent_due_day", day)):
		return []
	var r: Dictionary = _registry.get(lot_id, {})
	var rent_amt := int(r.get("rent", 0))
	var name: String = String(r.get("name", "your room"))
	var out: Array[String] = []
	if Game.gold >= rent_amt:
		Game.add_gold(-rent_amt)
		st["missed_rent"] = 0
	else:
		st["missed_rent"] = int(st.get("missed_rent", 0)) + 1
		st["debt"] = int(st.get("debt", 0)) + rent_amt
		if int(st["missed_rent"]) >= MISSED_RENT_LIMIT:
			st["status"] = "evicted"
			st["evict_day"] = day
			out.append("Evicted from %s for missing %d rent payments. Your things are kept %d days." %
				[name.to_lower(), MISSED_RENT_LIMIT, EVICTION_GRACE_DAYS])
			return out
		out.append("Rent unpaid on %s (%d gold owed)." % [name.to_lower(), int(st["debt"])])
	st["rent_due_day"] = int(st.get("rent_due_day", day)) + DAYS_PER_WEEK
	return out


func _tick_tax(lot_id: String, st: Dictionary, day: int) -> Array[String]:
	if day < int(st.get("tax_due_day", day)):
		return []
	var r: Dictionary = _registry.get(lot_id, {})
	var tax_amt := int(r.get("tax", 0))
	var name: String = String(r.get("name", "your property"))
	var out: Array[String] = []
	if Game.gold >= tax_amt:
		Game.add_gold(-tax_amt)
	else:
		st["tax_debt"] = int(st.get("tax_debt", 0)) + tax_amt
		if Life.get("biography") != null:
			Life.biography.change_rep("trade", -TAX_REP_HIT)
		out.append("Land tax unpaid on %s, owed to %s (%d gold owed)." % [name.to_lower(), r.get("landlord_id", "the Crown"), int(st["tax_debt"])])
	st["tax_due_day"] = int(st.get("tax_due_day", day)) + SEASON_DAYS
	return out


# --- storage ---------------------------------------------------------------------------

func can_store(lot_id: String) -> bool:
	var r: Dictionary = _registry.get(lot_id, {})
	return is_held(lot_id) and not bool(r.get("is_inn_room", false))


func storage_of(lot_id: String) -> Array:
	return (state.get(lot_id, {}).get("storage", []) as Array).duplicate(true)


func storage_capacity(lot_id: String) -> int:
	var kind := String(_registry.get(lot_id, {}).get("kind", ""))
	return int(KIND_INFO.get(kind, {}).get("storage", 0))


## Moves `qty` of `item` from the player's pack into the lot's chest.
func deposit(lot_id: String, item: String, qty: int) -> String:
	if not can_store(lot_id):
		return "No storage here."
	if qty <= 0 or Life.count(item) < qty:
		return "You don't have %d %s." % [qty, Life.item_name(item)]
	var st: Dictionary = state[lot_id]
	var stacks: Array = st["storage"]
	var stack := _find_stack(stacks, item)
	if stack.is_empty() and stacks.size() >= storage_capacity(lot_id):
		return "The chest is full."
	if not Life.take(item, qty):
		return "You don't have %d %s." % [qty, Life.item_name(item)]
	if stack.is_empty():
		stacks.append({"item": item, "qty": qty})
	else:
		stack["qty"] = int(stack["qty"]) + qty
	return "Stored %d %s." % [qty, Life.item_name(item)]


## Moves `qty` of `item` from the lot's chest back into the player's pack.
func withdraw(lot_id: String, item: String, qty: int) -> String:
	if not can_store(lot_id):
		return "No storage here."
	var st: Dictionary = state.get(lot_id, {})
	var stacks: Array = st.get("storage", [])
	var stack := _find_stack(stacks, item)
	if stack.is_empty() or int(stack["qty"]) < qty or qty <= 0:
		return "The chest doesn't have %d %s." % [qty, Life.item_name(item)]
	stack["qty"] = int(stack["qty"]) - qty
	if int(stack["qty"]) <= 0:
		stacks.erase(stack)
	Life.give(item, qty)
	return "Took %d %s." % [qty, Life.item_name(item)]


static func _find_stack(stacks: Array, item: String) -> Dictionary:
	for st: Dictionary in stacks:
		if String(st["item"]) == item:
			return st
	return {}


# --- save / load -------------------------------------------------------------------------

func serialize() -> Dictionary:
	var st_out := {}
	for lot_id: String in state:
		var s: Dictionary = state[lot_id]
		var storage_out: Array = []
		for it: Dictionary in (s.get("storage", []) as Array):
			storage_out.append({"item": String(it["item"]), "qty": int(it["qty"])})
		st_out[lot_id] = {"status": String(s.get("status", "")), "rent_due_day": int(s.get("rent_due_day", 0)),
			"missed_rent": int(s.get("missed_rent", 0)), "debt": int(s.get("debt", 0)),
			"tax_due_day": int(s.get("tax_due_day", 0)), "tax_debt": int(s.get("tax_debt", 0)),
			"rented_since": int(s.get("rented_since", 0)), "evict_day": int(s.get("evict_day", -1)),
			"storage": storage_out}
	return {"state": st_out, "last_day": _last_day}


func deserialize(d: Dictionary) -> void:
	state.clear()
	var st_in: Dictionary = d.get("state", {})
	for lot_id: String in st_in:
		var s: Dictionary = st_in[lot_id]
		var storage_in: Array = []
		for it: Variant in (s.get("storage", []) as Array):
			var itd: Dictionary = it
			storage_in.append({"item": String(itd["item"]), "qty": int(itd["qty"])})
		state[lot_id] = {"status": String(s.get("status", "")), "rent_due_day": int(s.get("rent_due_day", 0)),
			"missed_rent": int(s.get("missed_rent", 0)), "debt": int(s.get("debt", 0)),
			"tax_due_day": int(s.get("tax_due_day", 0)), "tax_debt": int(s.get("tax_debt", 0)),
			"rented_since": int(s.get("rented_since", 0)), "evict_day": int(s.get("evict_day", -1)),
			"storage": storage_in}
	_last_day = int(d.get("last_day", -1))
