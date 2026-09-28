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
## Event multipliers on top of the stock/target curve (economy.gd: road danger,
## season, festivals, war, a new mine). item id -> multiplier, missing = 1.0.
## Doesn't change base_price/stock, so old saves and RAMarket call sites are unaffected.
var modifiers: Dictionary = {}


func add_good(item: String, price: int, normal_stock: int, made_per_day := 0) -> void:
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


## Producers restock, townsfolk buy, the purse earns from ordinary trade.
func tick_day(population: int) -> void:
	for item: String in stock:
		var s := int(stock[item]) + int(produce[item])
		var eaten := int(ceil(float(target[item]) * 0.15 * clampf(population / 60.0, 0.3, 2.0)))
		stock[item] = clampi(s - eaten, 0, int(target[item]) * 3)
	purse = mini(purse + 15, 600)


## Fractional version of tick_day for a market ticked hourly (economy.gd's
## regional markets): the same production/consumption curve, scaled to `dh`
## in-game hours instead of a full day. No per-frame work; callers tick at
## most once per in-game hour.
func tick_hours(dh: float, population: int) -> void:
	var frac := clampf(dh, 0.0, 24.0) / 24.0
	for item: String in stock:
		var s := float(stock[item]) + float(produce[item]) * frac
		var eaten := float(target[item]) * 0.15 * clampf(population / 60.0, 0.3, 2.0) * frac
		stock[item] = clampi(int(round(s - eaten)), 0, int(target[item]) * 3)
	purse = mini(purse + int(round(15.0 * frac)), 600)


func serialize() -> Dictionary:
	return {"stock": stock.duplicate(), "purse": purse, "modifiers": modifiers.duplicate()}


func deserialize(d: Dictionary) -> void:
	var s: Dictionary = d.get("stock", {})
	for item: String in s:
		if stock.has(item):
			stock[item] = int(s[item])
	purse = int(d.get("purse", purse))
	modifiers = (d.get("modifiers", {}) as Dictionary).duplicate()
