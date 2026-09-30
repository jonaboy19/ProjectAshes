extends RefCounted
## A regional, reactive economy (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Careers"
## -> Merchant, and "Living world simulation"): one RAMarket per settlement,
## each producing and consuming goods by its kind, drifting hourly toward
## supply and demand, and shifted by world events -- road danger, season, war,
## a new mine opening. Also owns the merchant's other assets: caravans sent
## along the roads, contracts settlements offer, and the flags the merchant
## career ladder (career_ladders.gd, data/careers/ladders.json) reads.
##
## Ashford's own market stays exactly what it always was: `Life.market`. This
## script never replaces it, only binds it in (bind_home_market) so it gets
## the same hourly drift and event modifiers as every other settlement, and
## existing code/tests that read `Life.market` directly keep working.
##
## Pure RefCounted data: no autoload is required to construct or tick it (only
## WorldGen, a static class already populated once, and Frontier's runestone
## network, read defensively). tests/test_economy.gd builds one directly, the
## same way tests/test_roads.gd exercises WorldGen.
##
## Performance: tick_hour() is meant to be called at most once per in-game
## hour (see autoload/life.gd's hourly tick); nothing here runs per frame.

const RAMarket := preload("res://scripts/sim/market.gd")
const RACaravans := preload("res://scripts/sim/caravans.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")

## Settlement kind -> {item: [base_price, normal_stock, made_per_day]}.
const GOODS_BY_KIND := {
	"village": {"wheat": [2, 40, 14], "cabbage": [2, 30, 10], "wool": [5, 20, 7], "firewood": [1, 30, 10], "hides": [6, 15, 5]},
	"town": {"tools": [15, 15, 5], "cloth": [8, 20, 7], "ale": [4, 25, 9]},
	"castle": {"luxury_goods": [40, 10, 4], "weapons": [35, 12, 5]},
}
## Goods a settlement of this kind doesn't make but still stocks a little of
## (bought in from elsewhere): produce is always 0, so road danger always
## counts as import risk for them. A village's smithy still needs tools; a
## town's bakery still needs grain; the capital needs everyone's staples.
const IMPORTS_BY_KIND := {
	"village": ["tools", "ale"],
	"town": ["wheat", "cabbage", "wool"],
	"castle": ["wheat", "cabbage", "wool", "tools", "cloth"],
}
## Region1 hook C4 (docs/regions/REGION_1_PLAN.md): Scar goods. Towns and the capital buy them, and their price follows
## `scar_price_mult` (set by Region 1 from the size of the Scar Tide: a big Scar floods the market, a burned-back one makes them dear).
const SCAR_GOODS := {"scar_crystal": [40, 4, 0], "scarbloom": [18, 6, 0]}
var scar_price_mult := 1.0
const MINE_GOOD := "iron_ore"
const MINE_PRODUCE := [3, 25, 9]           # [base_price, normal_stock, made_per_day]
const LAKE_GOOD := "perch"
const LAKE_PRODUCE := [2, 20, 7]
## Settlements within this many lake radii of Emberglass Mere fish it (covers
## the design's "lake and coastal places"; the region has one lake, no coast yet).
const LAKE_REACH_MULT := 3.0

const FOOD_ITEMS: Array[String] = ["wheat", "cabbage", "bread", "ale"]
const WAR_GOODS: Array[String] = ["weapons", "horses", "wheat"]
const FESTIVAL_GOODS: Array[String] = ["ale", "wheat", "cabbage"]

const WINTER_FOOD_MULT := 1.35
const HARVEST_GRAIN_MULT := 0.7
const WAR_MULT := 1.4
const FESTIVAL_MULT := 1.3
const MINE_OPENED_MULT := 0.6
## Up to +160% on an imported good at maximum recorded road danger (road_risk = 1.0).
const IMPORT_RISK_MULT := 1.6
## Share of the daily import wagons lost at maximum road danger.
const IMPORT_RISK_CUT := 0.8
## A market holding more than this multiple of its normal stock of something it makes can export the excess;
## one under TRADE_SHORT_RATIO of normal gets shipments.
const TRADE_SURPLUS_RATIO := 1.25
const TRADE_SHORT_RATIO := 0.75
## Kingsreach (the capital) eats its food stock faster than it makes it.
const CAPITAL_FOOD_EAT_MULT := 1.6

const CART_COST := 120
const CART_MIN_KIND := "town"        # buy at a town (or the capital)
## Extra cargo slots a cart gives, but only while it's on the road (Life/inventory
## reads this; the cart itself is a flag here, not an inventory system).
const CART_CARGO_BONUS := 12
const GUARD_DAILY_WAGE := 6
## A hired guard's cut of an ambush's would-be cargo loss (see caravans.gd).
const GUARD_LOSS_REDUCTION := 0.5

const CONTRACT_GOOD_POOL: Array[String] = ["wheat", "wool", "tools", "cloth", "ale", "hides", "iron_ore"]

## settlement id (WorldGen.settlements index) -> RAMarket.
var markets: Dictionary = {}
## settlement id -> 0..1 danger on the road(s) reaching it (dark runestones,
## bandit activity); refresh_road_risk() fills this from Frontier's network,
## or a test/caller can set it directly.
var road_risk: Dictionary = {}
## settlement id -> {item: {"price": int, "day": float}}: only what the player
## has actually learned, by visiting or by rumour (trade_screen's price list).
var known_prices: Dictionary = {}

var caravans := RACaravans.new()
## [{id, from, to, item, amount, reward, due_day, filled}]
var contracts: Array[Dictionary] = []
var _next_contract_id := 1

# --- merchant ladder flags (career_ladders.gd ctx; see life.gd's _career_daily) ---
var owns_cart := false
var owns_caravan := false
## Owning a trader's house; set from property.gd if present, else left as a
## plain flag callers can set directly (per the brief: "if it's missing, just
## check a has_shop flag passed in").
var has_shop := false
var has_guard := false
## Total gold moved buying + selling + caravan profit: career mastery/flavour.
var trade_volume := 0

var _mine_settlement_id := -2      # -2 = not looked up yet, -1 = none found


# --- setup -------------------------------------------------------------------------

## Builds a market for every settlement except `home_id` (Ashford), which the
## caller binds in separately with its own already-live RAMarket.
func setup(home_id := 0) -> void:
	for s: Dictionary in WorldGen.settlements:
		var id := int(s["id"])
		if id == home_id or markets.has(id):
			continue
		markets[id] = _build_market(s)


## Registers Ashford's existing market (Life.market) as settlement `home_id`'s
## regional market, so it drifts and gets event modifiers like every other one.
func bind_home_market(home_id: int, market: RAMarket) -> void:
	markets[home_id] = market


func _build_market(s: Dictionary) -> RAMarket:
	var m := RAMarket.new()
	var kind := String(s.get("kind", "village"))
	var goods: Dictionary = GOODS_BY_KIND.get(kind, GOODS_BY_KIND["village"])
	for item: String in goods:
		var g: Array = goods[item]
		m.add_good(item, int(g[0]), int(g[1]), int(g[2]))
	for item: String in IMPORTS_BY_KIND.get(kind, []):
		if m.base_price.has(item):
			continue
		var src := _recipe_for(item)
		m.add_good(item, int(src[0]), maxi(4, int(src[1]) / 4), 0)
		# Enough arrives, on a safe road, to hold the stock near normal against what people use.
		m.imports[item] = 0.15 * clampf(float(s.get("population", 100)) / 60.0, 0.3, 2.0) * float(m.target[item])
	if kind in ["town", "castle", "frontier_town"]:
		for item: String in SCAR_GOODS:
			m.add_good(item, int(SCAR_GOODS[item][0]), int(SCAR_GOODS[item][1]), int(SCAR_GOODS[item][2]))
	var id := int(s["id"])
	if _is_mine_settlement(id) and not m.base_price.has(MINE_GOOD):
		m.add_good(MINE_GOOD, int(MINE_PRODUCE[0]), int(MINE_PRODUCE[1]), int(MINE_PRODUCE[2]))
	if _near_lake(s) and not m.base_price.has(LAKE_GOOD):
		m.add_good(LAKE_GOOD, int(LAKE_PRODUCE[0]), int(LAKE_PRODUCE[1]), int(LAKE_PRODUCE[2]))
	# Region 1 item set: the shops this kind and size of settlement has stock their goods (data/items/shops.json).
	ItemsDB.stock_settlement(m, kind, int(s.get("population", 100)), s.get("idents", []), id)
	return m


## Where `item` is actually produced (its [price, stock, rate] entry), so an
## importing settlement's little local stock starts at a sane base price.
func _recipe_for(item: String) -> Array:
	for kind: String in GOODS_BY_KIND:
		var goods: Dictionary = GOODS_BY_KIND[kind]
		if goods.has(item):
			return goods[item]
	return [4, 10, 0]


## The settlement nearest the region's mine site (WorldGen.sites, kind "mine"),
## resolved once and cached. WorldGen.setup() places sites synchronously, so by
## the time anything can call this, WorldGen.sites is already final.
func _is_mine_settlement(id: int) -> bool:
	if _mine_settlement_id == -2:
		_mine_settlement_id = -1
		var best := INF
		for site: Dictionary in WorldGen.sites:
			if String(site.get("kind", "")) != "mine":
				continue
			var site_pos: Vector2 = site["pos"]
			for s: Dictionary in WorldGen.settlements:
				if int(s["id"]) == 0:
					continue   # Ashford keeps its own market untouched; pick another settlement
				var d: float = (s["pos"] as Vector2).distance_to(site_pos)
				if d < best:
					best = d
					_mine_settlement_id = int(s["id"])
	return _mine_settlement_id == id


func _near_lake(s: Dictionary) -> bool:
	if WorldGen.lake_radius <= 0.0:
		return false
	return (s["pos"] as Vector2).distance_to(WorldGen.lake_center) < WorldGen.lake_radius * LAKE_REACH_MULT


# --- prices & trading ----------------------------------------------------------------

func price(settlement: int, item: String) -> int:
	var m: RAMarket = markets.get(settlement)
	return m.price(item) if m else 0


func sell_price(settlement: int, item: String) -> int:
	var m: RAMarket = markets.get(settlement)
	return m.sell_price(item) if m else 0


## Player buys at `settlement`. Returns gold paid, or -1 (see RAMarket.can_buy
## for why). Tracks trade_volume for the merchant ladder.
func buy(settlement: int, item: String, gold: int) -> int:
	var m: RAMarket = markets.get(settlement)
	if m == null:
		return -1
	var paid := m.buy(item, gold)
	if paid > 0:
		trade_volume += paid
	return paid


## Player sells at `settlement`. Returns gold received, or -1.
func sell(settlement: int, item: String) -> int:
	var m: RAMarket = markets.get(settlement)
	if m == null:
		return -1
	var got := m.sell(item)
	if got > 0:
		trade_volume += got
	return got


## Profitable runs out of `from`, best first: [{to, item, buy, sell, profit,
## distance, risk, score}]. `score` is profit per unit after distance and road
## risk, which is what "best" is sorted by.
func best_trade_routes(from: int, n := 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from_market: RAMarket = markets.get(from)
	if from_market == null:
		return out
	var from_pos: Vector2 = _settlement_pos(from)
	for to in markets:
		if to == from:
			continue
		var to_market: RAMarket = markets[to]
		var dist := from_pos.distance_to(_settlement_pos(to))
		var risk := float(road_risk.get(from, 0.0)) + float(road_risk.get(to, 0.0))
		for item: String in from_market.base_price:
			if not to_market.base_price.has(item):
				continue
			var buy_p := from_market.price(item)
			var sell_p := to_market.sell_price(item)
			var profit := sell_p - buy_p
			if profit <= 0:
				continue
			var score := float(profit) - dist * 0.01 - risk * 8.0
			out.append({"to": to, "item": item, "buy": buy_p, "sell": sell_p, "profit": profit,
				"distance": dist, "risk": risk, "score": score})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return out.slice(0, n) if out.size() > n else out


func _settlement_pos(id: int) -> Vector2:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return s["pos"]
	return Vector2.ZERO


func _settlement_name(id: int) -> String:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return String(s["name"])
	return "somewhere"


## Rumour lines for gossip, e.g. "Iron Ore fetches double in Kingsreach since
## the road there went dark." Only reports a real, large gap (>= 1.8x).
func rumour_prices() -> Array[String]:
	var items: Dictionary = {}
	for id in markets:
		for item: String in (markets[id] as RAMarket).base_price:
			items[item] = true
	var out: Array[String] = []
	for item: String in items:
		var hi_id := -1
		var hi_p := -1
		var lo_p := 999999
		for id in markets:
			var m: RAMarket = markets[id]
			if not m.base_price.has(item):
				continue
			var p := m.price(item)
			if p > hi_p:
				hi_p = p
				hi_id = id
			if p < lo_p:
				lo_p = p
		if hi_id < 0 or lo_p >= hi_p:
			continue
		var ratio := float(hi_p) / maxf(float(lo_p), 1.0)
		if ratio < 1.8:
			continue
		var word := "double" if ratio < 2.6 else ("triple" if ratio < 3.6 else "many times over")
		var reason := ""
		if float(road_risk.get(hi_id, 0.0)) > 0.4:
			reason = " since the road there went dark"
		out.append("%s fetches %s in %s%s." % [_item_label(item), word, _settlement_name(hi_id), reason])
	return out


func _item_label(item: String) -> String:
	return item.replace("_", " ").capitalize()


# --- price knowledge (trade_screen.gd) -----------------------------------------------

## Snapshots every current price at `settlement` as known, dated `day` (call on
## arrival/visit).
func learn_prices(settlement: int, day: float) -> void:
	var m: RAMarket = markets.get(settlement)
	if m == null:
		return
	var snap: Dictionary = {}
	for item: String in m.base_price:
		snap[item] = {"price": m.price(item), "day": day}
	known_prices[settlement] = snap


## A single learned price, from a rumour (rumour_prices() reports the fact;
## this is how a gossip system that heard one records it).
func learn_price(settlement: int, item: String, day: float) -> void:
	var known: Dictionary = known_prices.get(settlement, {})
	known[item] = {"price": price(settlement, item), "day": day}
	known_prices[settlement] = known


# --- hourly tick: production/consumption drift + events -------------------------------

## ctx: {season: String ("spring"/"summer"/"autumn"/"winter"), festival: bool,
## at_war: bool, mine_opened: bool, abs_hours: float}. Call at most once per
## in-game hour (life.gd's hourly tick); does no per-frame work. Returns any
## caravan-arrival reports due this tick ({id, ok, ambushed, revenue, text}),
## for the caller to Game.say.
func tick_hour(dh: float, ctx: Dictionary) -> Array[Dictionary]:
	var season := String(ctx.get("season", "spring"))
	var festival := bool(ctx.get("festival", false))
	var at_war := bool(ctx.get("at_war", false))
	var mine_opened := bool(ctx.get("mine_opened", false))
	for id in markets:
		var m: RAMarket = markets[id]
		var pop := _population(id)
		m.tick_hours(dh, pop)
		if _is_capital(id):
			_extra_capital_food_drain(m, dh)
		_apply_modifiers(id, m, season, festival, at_war, mine_opened)
	# Once a day (06:00) the merchants' wagons bring in what each place doesn't make; dangerous roads thin them out.
	if ctx.has("abs_hours") and int(float(ctx["abs_hours"])) % 24 == 6:
		for id in markets:
			var m2: RAMarket = markets[id]
			var risk := clampf(float(road_risk.get(id, 0.0)), 0.0, 1.0)
			for item: String in m2.imports:
				m2.add_stock(item, float(m2.imports[item]) * (1.0 - IMPORT_RISK_CUT * risk))
		_trade_surplus()
	return caravans.tick(_abs_hours_placeholder(ctx), self)


## Daily surplus trade between markets: places that make a good and hold well over their normal stock ship
## part of the excess to places that are running short, less what dangerous roads cost. Without it the
## producers sat at the 0.5x price floor and the importing towns at the 3x cap indefinitely.
func _trade_surplus() -> void:
	var items := {}
	for id in markets:
		for item: String in (markets[id] as RAMarket).base_price:
			items[item] = true
	for item: String in items:
		var donors: Array = []
		var needy: Array = []
		for id in markets:
			var m: RAMarket = markets[id]
			var t := float(m.target.get(item, 0))
			if t <= 0.0:
				continue
			var ratio := float(m.stock.get(item, 0)) / t
			if ratio > TRADE_SURPLUS_RATIO and int(m.produce.get(item, 0)) > 0:
				donors.append([id, ratio])
			elif ratio < TRADE_SHORT_RATIO:
				needy.append([id, ratio])
		if donors.is_empty() or needy.is_empty():
			continue
		donors.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		needy.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
		var di := 0
		for n: Array in needy:
			var nm: RAMarket = markets[n[0]]
			var want := (TRADE_SURPLUS_RATIO - 0.25 - float(n[1])) * float(nm.target[item]) * 0.5
			var keep := 1.0 - IMPORT_RISK_CUT * clampf(float(road_risk.get(n[0], 0.0)), 0.0, 1.0)
			while want >= 0.5 and di < donors.size():
				var dm: RAMarket = markets[donors[di][0]]
				var surplus := float(dm.stock[item]) - TRADE_SURPLUS_RATIO * float(dm.target[item]) * 0.9
				var give := minf(want, surplus * 0.5)
				if give < 0.5:
					di += 1
					continue
				dm.add_stock(item, -give)
				nm.add_stock(item, give * keep)
				want -= give
				donors[di][1] = float(dm.stock[item]) / float(dm.target[item])


## caravans.tick needs "now" in absolute in-game hours; callers pass it via
## ctx["abs_hours"] (life.gd already tracks this as _abs_hours()). Falls back
## to 0.0 so a caller that only cares about price drift needn't supply it.
func _abs_hours_placeholder(ctx: Dictionary) -> float:
	return float(ctx.get("abs_hours", 0.0))


func _population(id: int) -> int:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return int(s.get("population", 100))
	return 100


func _is_capital(id: int) -> bool:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return String(s.get("kind", "")) == "castle"
	return false


func _extra_capital_food_drain(m: RAMarket, dh: float) -> void:
	var frac := clampf(dh, 0.0, 24.0) / 24.0
	for item: String in ["wheat", "cabbage"]:
		if not m.stock.has(item):
			continue
		var extra := int(round(float(m.target.get(item, 0)) * 0.1 * (CAPITAL_FOOD_EAT_MULT - 1.0) * frac))
		if extra > 0:
			m.stock[item] = maxi(0, int(m.stock[item]) - extra)


func _apply_modifiers(id: int, m: RAMarket, season: String, festival: bool, at_war: bool, mine_opened: bool) -> void:
	var risk := clampf(float(road_risk.get(id, 0.0)), 0.0, 1.0)
	for item: String in m.base_price:
		var mult := 1.0
		if int(m.produce.get(item, 0)) <= 0:
			mult *= 1.0 + risk * IMPORT_RISK_MULT
		if season == "winter" and item in FOOD_ITEMS:
			mult *= WINTER_FOOD_MULT
		if season == "autumn" and item == "wheat":
			mult *= HARVEST_GRAIN_MULT
		if festival and item in FESTIVAL_GOODS:
			mult *= FESTIVAL_MULT
		if at_war and item in WAR_GOODS:
			mult *= WAR_MULT
		if mine_opened and item == MINE_GOOD:
			mult *= MINE_OPENED_MULT
		if SCAR_GOODS.has(item):
			mult *= scar_price_mult   # Region1 hook C4
		m.set_modifier(item, mult)


## Refreshes road_risk for every settlement from a runestone network (Frontier.
## runestones in the live game): the worse the road stones between a settlement
## and the rest of the map, the higher its import risk. Optional -- tests and
## callers that don't have a network can just set road_risk directly.
func refresh_road_risk(network: RARunestoneNetwork) -> void:
	if network == null:
		return
	# Rebuilt from scratch: the old version only ever raised a settlement's risk, so one dark night on a road
	# left it "dangerous" forever even after the stones were repaired.
	road_risk.clear()
	for r in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		var mid := a.lerp(b, 0.5)
		var danger := 1.0 - network.coverage(mid)
		road_risk[r.x] = maxf(float(road_risk.get(r.x, 0.0)), danger)
		road_risk[r.y] = maxf(float(road_risk.get(r.y, 0.0)), danger)


## Toll a noble house charges to cross the road between `a` and `b` (0 if the
## road is a crown road, unowned, or scripts/sim/nobility.gd isn't wired in as
## Life.nobility yet). Callers that tax a caravan's revenue (caravans.gd,
## trade_screen.gd) can subtract this per leg.
func toll_for_road(a: int, b: int) -> int:
	var nobility: Object = Life.get("nobility")
	if nobility != null and nobility.has_method("toll_for_road"):
		return int(nobility.toll_for_road(a, b))
	return 0


# --- merchant assets -----------------------------------------------------------------

## Buys a cart at `settlement` (must be a town or the capital). "" on success,
## else why not.
func buy_cart(settlement: int, gold: int) -> String:
	if owns_cart:
		return "You already have a cart."
	var kind := ""
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == settlement:
			kind = String(s["kind"])
	if kind == "village":
		return "No cart-wright here; try a town."
	if gold < CART_COST:
		return "You need %d gold for a cart." % CART_COST
	owns_cart = true
	return ""


## Cargo capacity: the ordinary carry limit, plus the cart's bonus only while
## the cart is actually on the road (per the brief -- off the road it's just
## parked, and the player's own carry limit applies).
func cargo_slots(base_carry: int, cart_on_road: bool) -> int:
	return base_carry + (CART_CARGO_BONUS if owns_cart and cart_on_road else 0)


func hire_guard() -> String:
	if has_guard:
		return "Already have a guard on the payroll."
	has_guard = true
	return "A hired guard falls in beside you."


func dismiss_guard() -> void:
	has_guard = false


## The guard's daily wage (life.gd's daily tick can charge this the same way
## it pays careers.pay_day()). 0 if no guard is hired.
func guard_wage() -> int:
	return GUARD_DAILY_WAGE if has_guard else 0


## A hired guard halves whatever cargo/goods loss a road ambush would otherwise
## deal the player (road_events.gd, not edited here, can read this multiplier).
func player_ambush_loss_mult() -> float:
	return (1.0 - GUARD_LOSS_REDUCTION) if has_guard else 1.0


# --- contracts -------------------------------------------------------------------------

## Rolls up to one delivery contract from a settlement short of a good: "" (no
## offer) or the new contract. A settlement is "short" when its stock is below
## a third of its target for something it doesn't produce, or below a fifth
## for something it does (a bad run of luck).
func roll_contract(day: int, rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for id in markets:
		var m: RAMarket = markets[id]
		for item: String in CONTRACT_GOOD_POOL:
			if not m.base_price.has(item):
				continue
			var t := int(m.target.get(item, 0))
			if t <= 0:
				continue
			var floor_frac := 0.2 if int(m.produce.get(item, 0)) > 0 else 0.34
			if float(m.stock.get(item, 0)) < t * floor_frac:
				candidates.append({"to": id, "item": item, "short_by": t - int(m.stock[item])})
	if candidates.is_empty():
		return {}
	var c: Dictionary = candidates[rng.randi() % candidates.size()]
	var amount := clampi(int(c["short_by"]), 3, 20)
	var m: RAMarket = markets[c["to"]]
	var reward := int(round(m.price(String(c["item"])) * amount * 1.4))
	var contract := {"id": _next_contract_id, "to": c["to"], "item": c["item"], "amount": amount,
		"reward": reward, "due_day": day + rng.randi_range(4, 10), "filled": 0}
	_next_contract_id += 1
	contracts.append(contract)
	return contract


## An army quartermaster's order during war (war_sim.gd contract_for_merchant()).
func add_war_contract(day: int, spec: Dictionary) -> Dictionary:
	if spec.is_empty():
		return {}
	var item := String(spec["good"])
	var m: RAMarket = markets.get(0)
	var unit := m.price(item) if m != null and m.base_price.has(item) else 40
	var contract := {"id": _next_contract_id, "to": 0, "item": item, "amount": int(spec["quantity"]),
		"reward": int(round(unit * int(spec["quantity"]) * float(spec.get("pay_mult", 1.5)))),
		"due_day": day + 8, "filled": 0, "war": true}
	_next_contract_id += 1
	contracts.append(contract)
	return contract


func contract_progress(id: int, item_count: int) -> void:
	for c: Dictionary in contracts:
		if int(c["id"]) == id:
			c["filled"] = mini(int(c["amount"]), int(c["filled"]) + item_count)


## Completes a contract if fully delivered and not overdue: {ok, text, reward}.
func complete_contract(id: int, day: int) -> Dictionary:
	for c: Dictionary in contracts.duplicate():
		if int(c["id"]) != id:
			continue
		if int(c["filled"]) < int(c["amount"]):
			return {"ok": false, "text": "Not delivered yet.", "reward": 0}
		if day > int(c["due_day"]):
			contracts.erase(c)
			return {"ok": false, "text": "Too late -- the contract has lapsed.", "reward": 0}
		contracts.erase(c)
		trade_volume += int(c["reward"])
		return {"ok": true, "text": "Delivered %d %s to %s for %d gold." % [int(c["amount"]),
			_item_label(String(c["item"])), _settlement_name(int(c["to"])), int(c["reward"])], "reward": int(c["reward"])}
	return {"ok": false, "text": "No such contract.", "reward": 0}


func expire_contracts(day: int) -> void:
	for c: Dictionary in contracts.duplicate():
		if day > int(c["due_day"]):
			contracts.erase(c)


# --- career ladder hooks (career_ladders.gd ctx; see docstring at top) ---------------

## Merges the merchant flags career_ladders.gd's `promote()`/`check_promotion()`
## read into an existing ctx dictionary (life.gd's `_career_daily`). See the
## exact hook line in the file docstring above.
func ladder_ctx() -> Dictionary:
	return {"owns_cart": owns_cart, "owns_caravan": owns_caravan, "owns_shop": has_shop,
		"trade_volume": trade_volume}


# --- save / load ------------------------------------------------------------------------

func serialize() -> Dictionary:
	var m: Dictionary = {}
	for id in markets:
		m[str(id)] = (markets[id] as RAMarket).serialize()
	var risk: Dictionary = {}
	for id in road_risk:
		risk[str(id)] = float(road_risk[id])
	var known: Dictionary = {}
	for id in known_prices:
		known[str(id)] = (known_prices[id] as Dictionary).duplicate(true)
	return {
		"markets": m, "road_risk": risk, "known_prices": known,
		"owns_cart": owns_cart, "owns_caravan": owns_caravan, "has_shop": has_shop, "has_guard": has_guard,
		"trade_volume": trade_volume, "contracts": contracts.duplicate(true), "next_contract_id": _next_contract_id,
		"caravans": caravans.serialize(),
	}


## `home_id`/`home_market` re-binds Ashford's live market the same way setup()
## does, since a fresh RAEconomy is built before restore on load.
func deserialize(d: Dictionary, home_id := 0, home_market: RAMarket = null) -> void:
	setup(home_id)
	if home_market != null:
		bind_home_market(home_id, home_market)
	var m: Dictionary = d.get("markets", {})
	for key: String in m:
		var id := int(key)
		if markets.has(id):
			(markets[id] as RAMarket).deserialize(m[key])
	road_risk.clear()
	for key: String in (d.get("road_risk", {}) as Dictionary):
		road_risk[int(key)] = float(d["road_risk"][key])
	known_prices.clear()
	for key: String in (d.get("known_prices", {}) as Dictionary):
		known_prices[int(key)] = (d["known_prices"][key] as Dictionary).duplicate(true)
	owns_cart = bool(d.get("owns_cart", false))
	owns_caravan = bool(d.get("owns_caravan", false))
	has_shop = bool(d.get("has_shop", false))
	has_guard = bool(d.get("has_guard", false))
	trade_volume = int(d.get("trade_volume", 0))
	contracts.clear()
	for c: Dictionary in (d.get("contracts", []) as Array):
		contracts.append(c.duplicate())
	_next_contract_id = int(d.get("next_contract_id", 1))
	caravans.deserialize(d.get("caravans", {}))
