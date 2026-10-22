extends RefCounted
## Opening hours and real shop stock (package F5). Data: data/living_world/shop_hours.json, one [open, close] pair
## per service kind (an ItemsDB shop id such as "blacksmith" / "general_store", or "inn", "healer", "guild",
## "temple"). Merchants refuse trade when closed (`closed_line`), Stations show "Closed" (station.gd), and a shop
## interior outside its hours counts as private (scripts/population/trespass.gd).
## Pure static helpers; the clock is always a parameter (WorldSim.time_of_day when omitted). Preload; no class_name.

const PATH := "res://data/living_world/shop_hours.json"
const FALLBACK := {"default": [8, 20], "kinds": {"tavern": [0, 24], "inn": [0, 24]}, "closed_lines": {}}

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if not _data.is_empty():
		return _data
	var txt := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
	_data = parsed if parsed is Dictionary else FALLBACK.duplicate(true)
	return _data


## Forget the cached JSON (tests).
static func reset() -> void:
	_data = {}


static func _now() -> float:
	var loop := Engine.get_main_loop()
	var ws: Node = (loop as SceneTree).root.get_node_or_null("WorldSim") if loop is SceneTree else null
	return float(ws.get("time_of_day")) if ws != null and ws.get("time_of_day") != null else 12.0


## [open, close] hours of a service kind.
static func hours_of(kind: String) -> Array:
	var d := _load()
	var k: Dictionary = d.get("kinds", {})
	var h: Variant = k.get(kind, d.get("default", [8, 20]))
	if h is Array and (h as Array).size() >= 2:
		return [float(h[0]), float(h[1])]
	return [8.0, 20.0]


static func is_always(kind: String) -> bool:
	var h := hours_of(kind)
	return float(h[0]) <= 0.0 and float(h[1]) >= 24.0


## Open at `hour` (0..24, fractions fine; omitted = the game clock). A kind with no entry uses the default.
static func is_open(kind: String, hour := -1.0) -> bool:
	if kind == "":
		return true
	var h := hour if hour >= 0.0 else _now()
	var span := hours_of(kind)
	var o := float(span[0])
	var c := float(span[1])
	if o <= 0.0 and c >= 24.0:
		return true
	if o <= c:
		return h >= o and h < c
	return h >= o or h < c      # wraps past midnight (the back-alley fence)


## "7:00" style opening / closing label for a prompt or a sign: "Open 07:00 - 19:00".
static func hours_text(kind: String) -> String:
	if is_always(kind):
		return "Always open"
	var h := hours_of(kind)
	return "Open %02d:00 - %02d:00" % [int(h[0]), int(h[1]) % 24]


## The merchant's refusal line. Deterministic for a (kind, hour) so a menu does not flicker.
static func closed_line(kind: String, hour := -1.0) -> String:
	var t := hour if hour >= 0.0 else _now()
	var lines: Dictionary = _load().get("closed_lines", {})
	var open_h := float(hours_of(kind)[0])
	var key := "morning" if t < open_h or t >= 20.0 else "evening"
	var arr: Array = lines.get(key, lines.get("morning", []))
	if arr.is_empty():
		return "Come back in the morning."
	return String(arr[(int(t) + kind.length()) % arr.size()])


## The "Come back in the morning." line when `kind` is shut now, "" when open.
static func refusal(kind: String, hour := -1.0) -> String:
	return "" if is_open(kind, hour) else closed_line(kind, hour)


# ---------------------------------------------------------------- real stock
## What shop `shop_kind` really has on the shelf of `market` (RAMarket) at `tier`: the ItemsDB shop's goods that
## the market actually carries and has in stock, in the shop's own order. [{item, price, stock}].
static func stock_lines(market: Object, shop_kind: String, tier := 1, limit := 12) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if market == null:
		return out
	var ItemsDB := load("res://scripts/sim/items_db.gd")
	var base: Dictionary = market.get("base_price")
	var stock: Dictionary = market.get("stock")
	for g: Dictionary in ItemsDB.call("shop_goods", shop_kind, tier):
		var item := String(g["item"])
		if not base.has(item) or int(stock.get(item, 0)) <= 0:
			continue
		out.append({"item": item, "price": int(market.call("price", item)), "stock": int(stock[item])})
		if out.size() >= limit:
			break
	return out
