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


func add_good(item: String, price: int, normal_stock: int, made_per_day := 0) -> void:
	base_price[item] = price
	target[item] = normal_stock
	stock[item] = normal_stock
	produce[item] = made_per_day


## Current buy price: base * (target / stock) clamped to 0.5x .. 3x.
func price(item: String) -> int:
	var s := maxf(float(stock.get(item, 0)), 0.5)
	var f := clampf(float(target.get(item, 1)) / s, 0.5, 3.0)
	return maxi(1, int(round(float(base_price.get(item, 1)) * f)))


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


func serialize() -> Dictionary:
	return {"stock": stock.duplicate(), "purse": purse}


func deserialize(d: Dictionary) -> void:
	var s: Dictionary = d.get("stock", {})
	for item: String in s:
		if stock.has(item):
			stock[item] = int(s[item])
	purse = int(d.get("purse", purse))
