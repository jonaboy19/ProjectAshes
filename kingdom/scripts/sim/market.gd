class_name RAMarket
extends RefCounted
## A settlement market. Each good has a stock and a target stock; price rises
## when stock runs short and falls when the market is glutted. Merchants pay
## from a purse (the settlement treasury share), so they can run out of coin.
## Daily, local producers restock and townsfolk consume.

## Buying from the market costs price(); selling to it pays SELL_SHARE of that.
const SELL_SHARE := 0.6

var base_price: Dictionary = {}    # item id -> gold
var stock: Dictionary = {}         # item id -> units on hand
var target: Dictionary = {}        # item id -> stock the market considers normal
var produce: Dictionary = {}       # item id -> units made locally per day
var purse := 200
## Fractional hourly market income, preserved until it forms whole purse units.
var _purse_carry := 0.0
## Event multipliers on top of the stock/target curve (economy.gd: road danger,
## season, festivals, war, a new mine). item id -> multiplier, missing = 1.0.
## Doesn't change base_price/stock, so old saves and RAMarket call sites are unaffected.
var modifiers: Dictionary = {}
## economy.gd skips recomputing `modifiers` while its inputs are unchanged (CPU pass 2026-10-06): the inputs it saw last time
## (`mods_sig`) and a counter of goods changes (`_goods_rev`, bumped by add_good). deserialize() clears the signature.
var mods_sig: Array = []
var _goods_rev := 0


func goods_rev() -> int:
	return _goods_rev


var _producers: Array = []
var _producers_rev := -1


## Goods this market makes (produce > 0), cached until the goods change. The daily surplus trade only needs these as donors.
func producers() -> Array:
	if _producers_rev != _goods_rev:
		_producers = []
		for item: String in base_price:
			if int(produce.get(item, 0)) > 0:
				_producers.append(item)
		_producers_rev = _goods_rev
	return _producers


func add_good(item: String, price: int, normal_stock: int, made_per_day := 0) -> void:
	_goods_rev += 1
	base_price[item] = price
	target[item] = normal_stock
	stock[item] = normal_stock
	produce[item] = made_per_day


func modifier(item: String) -> float:
	return float(modifiers.get(item, 1.0))


## Sets (or clears, at 1.0) an event multiplier for `item`. economy.gd recomputes
## these fresh every hourly tick from current conditions, so they never drift or stack.
func set_modifier(item: String, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		modifiers.erase(item)
	else:
		modifiers[item] = mult


## Current buy price: base * (target / stock) clamped to 0.5x .. 3x, times any
## active event modifier (road danger, season, war...).
func price(item: String) -> int:
	var s := maxf(float(stock.get(item, 0)), 0.5)
	var f := clampf(float(target.get(item, 1)) / s, 0.5, 3.0)
	return maxi(1, int(round(float(base_price.get(item, 1)) * f * modifier(item))))


func sell_price(item: String) -> int:
	return maxi(1, int(floor(price(item) * SELL_SHARE)))


func can_buy(item: String, gold: int) -> String:
	if not base_price.has(item):
		return "Nobody sells that here."
	if int(stock[item]) <= 0:
		return "Sold out."
	if gold < price(item):
		return "You need %d gold." % price(item)
	return ""


## Player buys one unit. Returns the gold paid, or -1.
func buy(item: String, gold: int) -> int:
	if can_buy(item, gold) != "":
		return -1
	var p := price(item)
	stock[item] = int(stock[item]) - 1
	purse += p
	return p


## Player sells one unit. Returns the gold received, or -1 if the merchant can't pay.
func sell(item: String) -> int:
	if not base_price.has(item):
		add_good(item, 1, 4)
		stock[item] = 0
	var p := sell_price(item)
	if purse < p:
		return -1
	stock[item] = int(stock[item]) + 1
	purse -= p
	return p


## Share of the on-hand stock townsfolk use up per day at population 60 (scaled by clamp(pop / 60, .3, 2)).
## Demand follows the stock (not the target) so a market settles where production meets demand instead of
## sliding to empty (Ashford's bread, 6 made vs 8 eaten a day) or piling up to the 3x cap (a village's wheat).
const DEMAND_RATE := 0.15
## Durable goods (armour, weapons, tools) are not used up by townsfolk the way bread is. C13 (docs/regions/BALANCE_R1.md): a shelf of
## gear drained at the food rate, so the smith's stock sat at zero and the few pieces that arrived sold at the 3x ceiling (an iron
## spear for 104 against a list price of 20). `demand_scale` (item -> factor, set by ItemsDB.stock_market) lowers their demand.
var demand_scale: Dictionary = {}
## Stock changes smaller than one unit per tick carry over here instead of being rounded away (an hourly
## tick moves a typical good by 0.05 units, so the old int(round()) made regional markets completely static).
var _carry: Dictionary = {}
## Goods this market buys in from outside rather than makes: item id -> units per day that arrive at full
## road safety (economy.gd restocks them once a day, scaled down by road danger).
var imports: Dictionary = {}


## Producers restock, townsfolk buy, the purse earns from ordinary trade.
func tick_day(population: int) -> void:
	tick_hours(24.0, population)


## Fractional version of tick_day for a market ticked hourly (economy.gd's
## regional markets): the same production/consumption curve, scaled to `dh`
## in-game hours instead of a full day. No per-frame work; callers tick at
## most once per in-game hour.
func tick_hours(dh: float, population: int) -> void:
	var frac := clampf(dh, 0.0, 24.0) / 24.0
	var k := clampf(population / 60.0, 0.3, 2.0)
	for item: String in stock:
		var cur := int(stock[item])
		if cur == 0 and int(produce[item]) == 0:
			# Nothing on the shelf and nothing made: the step below is the identity (acc = carry < 1, whole = 0, the carry
			# stays as it is), so only make sure the carry entry exists, as the full step would.
			if not _carry.has(item):
				_carry[item] = 0.0
			continue
		var acc := float(_carry.get(item, 0.0)) + (float(produce[item]) - DEMAND_RATE * float(demand_scale.get(item, 1.0)) * k * float(cur)) * frac
		var whole := floori(acc)
		var cap := int(target[item]) * 3
		var nxt := clampi(cur + whole, 0, cap)
		_carry[item] = acc - float(whole) if nxt == cur + whole else 0.0
		stock[item] = nxt
	if purse >= 600:
		purse = 600
		_purse_carry = 0.0
	else:
		var income := 15.0 * frac + _purse_carry
		var whole_income := floori(income)
		purse = mini(purse + whole_income, 600)
		_purse_carry = income - float(whole_income) if purse < 600 else 0.0


## Lets `units` of `item` arrive (fractions carry over); never past 3x the target.
func add_stock(item: String, units: float) -> void:
	if not stock.has(item):
		return
	var acc := float(_carry.get(item, 0.0)) + units
	var whole := floori(acc)
	var cap := int(target[item]) * 3
	var nxt := clampi(int(stock[item]) + whole, 0, cap)
	_carry[item] = acc - float(whole) if nxt == int(stock[item]) + whole else 0.0
	stock[item] = nxt


func serialize() -> Dictionary:
	# A zero carry is the same as no entry (deserialize reads a missing one as 0): leaving them out is lossless and was
	# most of the entries in a saved market (save pass 2026-10-06).
	var carry := {}
	for item: String in _carry:
		var c := float(_carry[item])
		if c != 0.0:
			carry[item] = c
	return {"stock": stock.duplicate(), "purse": purse, "modifiers": modifiers.duplicate(),
		"carry": carry, "purse_carry": _purse_carry}


func deserialize(d: Dictionary) -> void:
	var s: Dictionary = d.get("stock", {})
	for item: String in s:
		if stock.has(item):
			stock[item] = int(s[item])
	purse = int(d.get("purse", purse))
	_purse_carry = 0.0
	var saved_purse_carry: Variant = d.get("purse_carry", 0.0)
	if typeof(saved_purse_carry) in [TYPE_INT, TYPE_FLOAT]:
		var purse_amount := float(saved_purse_carry)
		if is_finite(purse_amount) and purse_amount >= 0.0 and purse_amount < 1.0:
			_purse_carry = purse_amount
	modifiers = (d.get("modifiers", {}) as Dictionary).duplicate()
	mods_sig = []
	_carry.clear()
	var saved_carry: Variant = d.get("carry", {})
	if not (saved_carry is Dictionary):
		return
	for item: Variant in saved_carry:
		var good := String(item)
		var value: Variant = saved_carry[item]
		if stock.has(good) and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			var amount := float(value)
			if is_finite(amount) and amount >= 0.0 and amount < 1.0:
				_carry[good] = amount
