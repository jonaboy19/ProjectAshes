extends RefCounted
## Hired caravans: cart + driver + guards, sent between two settlements. Travel
## takes real simulated time over the road distance at cart speed; risk of
## ambush per road segment depends on the road's tier, its runestones'
## condition and how many guards ride along; cargo that survives sells at the
## destination market on arrival. See economy.gd (which owns one of these) and
## docs/RISING_ASHES_LIFE_SIM_DESIGN.md's Merchant career.
##
## Pure RefCounted data, no autoloads required: distance comes from
## WorldGen.settlements (a static class, already populated once). Resolution
## is seeded per caravan so the same seed always gives the same ambush/loss
## outcome (tests/test_economy.gd checks this).

## World units a cart covers per in-game hour.
const CART_SPEED := 55.0
## Base ambush chance per road tier before guards or stone condition.
const BASE_RISK_BY_TIER := {"kingdom": 0.02, "rural": 0.07, "frontier": 0.16}
## Added risk for how dangerous the road's runestones are (0..1, from economy.road_risk).
const STONE_RISK_WEIGHT := 0.35
## Each guard multiplies remaining risk by (1 - this), diminishing returns.
const GUARD_RISK_REDUCTION := 0.16
const MAX_GUARDS_COUNTED := 6
## Fraction of cargo lost on a successful ambush, before guards soften it
## (economy.gd's GUARD_LOSS_REDUCTION halves this per guard again).
const LOSS_RANGE := Vector2(0.2, 0.6)

## id -> {id, from, to, cargo: {item: count}, guards, depart, arrive, risk,
##        seed, status: "in_transit"/"arrived", result: {} once resolved}
var caravans: Dictionary = {}
var _next_id := 1


## Sends a caravan from `from` to `to` (WorldGen.settlements ids) carrying
## `cargo` (item -> count), with `guards` hired guards. `road_tier` and
## `stone_risk` (0..1) describe the worst stretch of road it must cross --
## the caller (economy.gd, from WorldGen.road_tier/road_risk) supplies them so
## this stays decoupled from the world/runestone singletons for testing.
## `depart_abs_hours` is the current absolute in-game hour (day*24+time_of_day).
func send(from: int, to: int, cargo: Dictionary, guards: int, road_tier: String,
		stone_risk: float, depart_abs_hours: float, seed_value: int) -> Dictionary:
	var dist := _distance(from, to)
	var hours := maxf(dist / CART_SPEED, 1.0)
	var base := float(BASE_RISK_BY_TIER.get(road_tier, 0.12)) + clampf(stone_risk, 0.0, 1.0) * STONE_RISK_WEIGHT
	var guard_mult := pow(1.0 - GUARD_RISK_REDUCTION, mini(guards, MAX_GUARDS_COUNTED))
	var c := {
		"id": _next_id, "from": from, "to": to, "cargo": cargo.duplicate(), "guards": guards,
		"depart": depart_abs_hours, "arrive": depart_abs_hours + hours, "distance": dist,
		"risk": clampf(base * guard_mult, 0.0, 0.9), "seed": seed_value, "status": "in_transit", "result": {},
	}
	caravans[c["id"]] = c
	_next_id += 1
	return c


func _distance(from: int, to: int) -> float:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == from:
			a = s["pos"]
		elif int(s["id"]) == to:
			b = s["pos"]
	return a.distance_to(b)


func in_transit() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in caravans.values():
		if String(c["status"]) == "in_transit":
			out.append(c)
	return out


## Resolves every caravan due by `now_abs_hours`. `economy` (may be null, e.g.
## in a unit test that only checks the roll) sells surviving cargo into the
## destination market so the trip actually moves goods, and its
## GUARD_LOSS_REDUCTION softens a guarded caravan's loss further. Returns one
## report per caravan resolved this tick, for Game.say.
func tick(now_abs_hours: float, economy: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in caravans.keys():
		var c: Dictionary = caravans[id]
		if String(c["status"]) != "in_transit" or now_abs_hours < float(c["arrive"]):
			continue
		out.append(_resolve(c, economy))
	return out


func _resolve(c: Dictionary, economy: Object) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(c["id"]), int(c["seed"])))
	var ambushed := rng.randf() < float(c["risk"])
	var lost_frac := 0.0
	if ambushed:
		lost_frac = rng.randf_range(LOSS_RANGE.x, LOSS_RANGE.y)
		# The caravan's own guards (already priced into "risk" above) also
		# soften a loss that does happen, same diminishing-returns curve.
		lost_frac *= pow(1.0 - GUARD_RISK_REDUCTION, mini(int(c["guards"]), MAX_GUARDS_COUNTED))
	var revenue := 0
	var kept_cargo: Dictionary = {}
	var cargo: Dictionary = c["cargo"]
	for item: String in cargo:
		var n := int(cargo[item])
		var kept := int(round(n * (1.0 - lost_frac)))
		kept_cargo[item] = kept
		if economy != null and economy.get("markets") != null and (economy.get("markets") as Dictionary).has(int(c["to"])):
			var to_market: Object = (economy.get("markets") as Dictionary)[int(c["to"])]
			for _k in kept:
				revenue += int(to_market.call("sell", item))
	c["status"] = "arrived"
	c["result"] = {"ambushed": ambushed, "lost_frac": lost_frac, "kept_cargo": kept_cargo, "revenue": revenue}
	var text := ""
	if ambushed:
		text = "Your caravan was ambushed on the road to %s! It lost %d%% of its cargo but still turned %d gold." % [
			_name(int(c["to"])), int(round(lost_frac * 100.0)), revenue]
	else:
		text = "Your caravan reached %s safely and sold its cargo for %d gold." % [_name(int(c["to"])), revenue]
	return {"id": int(c["id"]), "ok": true, "ambushed": ambushed, "revenue": revenue, "text": text}


func _name(id: int) -> String:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == id:
			return String(s["name"])
	return "the market town"


func get_caravan(id: int) -> Dictionary:
	return caravans.get(id, {})


func serialize() -> Dictionary:
	var out: Dictionary = {}
	for id in caravans:
		out[str(id)] = (caravans[id] as Dictionary).duplicate(true)
	return {"caravans": out, "next_id": _next_id}


func deserialize(d: Dictionary) -> void:
	caravans.clear()
	var c: Dictionary = d.get("caravans", {})
	for key: String in c:
		caravans[int(key)] = (c[key] as Dictionary).duplicate(true)
	_next_id = int(d.get("next_id", 1))
