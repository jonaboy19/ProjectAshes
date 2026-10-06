extends RefCounted
## Guarantees a kit town has the lots the village life needs (a tavern, a smithy, a general shop, and in a town a bakery,
## a guard post and a healer, as its file's `lots.required` lists them), plus a numbered row of named homes. The playtest found
## a town once had no blacksmith lot, so these are forced, not hoped for. CityPlanner.plan calls `enforce` once, after the
## districts are zoned and before the door paths are made, and nothing else in the plan moves. A settlement without a town
## file is untouched.
##
## Each chosen lot keeps its drawn building (`asset`) unless a role needs a different one, and gains
##   lot["bid"]    stable building id ("thornfield_smithy", "millbrook_house_3", ...)
##   lot["btype"]  what it is: smithy | general_shop | tavern | bakery | guard_post | healer | house
## (building_profiles.gd / the interior pass key off `asset`; `btype` is the extra hook for shop vs house).
## plan["slice"] = {town, tid, buildings: {bid: {type, asset, lot, pos, door}}, sites: {bid: what}} is the registry.
##
## No class_name; preload it. `enforce` is a pure function of the plan; the lookups read WorldGen.settlements.

const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")

## Wanted drawn building and the quarter it belongs in, by lot type.
const ASSETS := {"tavern": "inn", "smithy": "blacksmith", "general_shop": "mhouse_trader", "bakery": "house_town_b",
	"guard_post": "house_13", "healer": "healer_house"}
const DISTRICTS := {"blacksmith": "craft", "mhouse_trader": "market", "house_town_b": "market", "house_13": "military", "inn": "inn"}
## The lot types of a village / a town (a town adds the bakery, the guard post and the healer).
const VILLAGE_TYPES := ["tavern", "smithy", "general_shop"]
const TOWN_TYPES := ["tavern", "smithy", "general_shop", "bakery", "guard_post", "healer"]

static var _plans: Dictionary = {}     # settlement id -> plan["slice"]
static var _bid_town: Dictionary = {}  # bid -> tid (filled as registries are built or looked up)


static func is_kit_town(s: Dictionary) -> bool:
	return TownData.has_town(String(s.get("name", "")))


## The lot types town `tid` must have in its plan (its file's required list).
static func required_types(tid: String) -> Array:
	var out: Array = []
	for r: Dictionary in (TownData.town(tid).get("lots", {}) as Dictionary).get("required", []):
		out.append(String(r["btype"]))
	return out


## Adds the forced lots and the building registry to `plan` (settlement `s`). `fits` = CityPlanner.fits.
static func enforce(plan: Dictionary, s: Dictionary, fits: Callable) -> void:
	var tid := TownData.id_of_settlement(String(s.get("name", "")))
	if tid == "":
		return
	var doc := TownData.town(tid)
	var lots_def: Dictionary = doc.get("lots", {})
	var lots: Array = plan["lots"]
	var c: Vector2 = plan["centre"]
	var used := {}
	var buildings := {}
	for role: Dictionary in lots_def.get("required", []):
		var asset := String(role["asset"])
		var btype := String(role["btype"])
		var idx := _find_lot(lots, btype, asset, c, used)
		if idx < 0:
			idx = _convert(plan, lots, asset, c, used, fits)
		if idx < 0:
			continue
		used[idx] = true
		_tag(lots[idx], btype, String(role["bid"]), buildings, idx)
	# Named homes: the houses nearest the plaza, numbered in a stable order.
	var homes: Array = []
	for i in lots.size():
		if not used.has(i) and BuildingProfiles.is_house(String(lots[i]["asset"])) and _free(lots[i]):
			homes.append(i)
	homes.sort_custom(func(a: int, b: int) -> bool:
		var da := (lots[a]["pos"] as Vector2).distance_to(c)
		var db := (lots[b]["pos"] as Vector2).distance_to(c)
		return da < db or (da == db and (lots[a]["pos"] as Vector2).x < (lots[b]["pos"] as Vector2).x))
	for k in mini(int(lots_def.get("homes", 0)), homes.size()):
		_tag(lots[homes[k]], "house", "%s_house_%d" % [tid, k + 1], buildings, homes[k])
	plan["slice"] = {"town": String(doc["settlement"]), "tid": tid, "buildings": buildings, "sites": (lots_def.get("sites", {}) as Dictionary).duplicate()}
	_plans[int(s["id"])] = plan["slice"]


## A lot the kit may take: not already a kit building, and not one the planner gave a civic role (the courthouse, a workshop).
static func _free(lot: Dictionary) -> bool:
	return String(lot.get("btype", "")) == "" and String(lot.get("role", "")) == ""


static func _tag(lot: Dictionary, btype: String, bid: String, buildings: Dictionary, idx: int) -> void:
	lot["bid"] = bid
	lot["btype"] = btype
	if String(lot.get("role", "")) == "":
		lot["role"] = btype
	buildings[bid] = {"type": btype, "asset": String(lot["asset"]), "lot": idx, "pos": lot["pos"], "door": BuildingProfiles.door_point(lot)}


## Existing lot for a role: the asset the role wants (inn, blacksmith, healer_house) nearest the plaza, else -1.
static func _find_lot(lots: Array, btype: String, asset: String, c: Vector2, used: Dictionary) -> int:
	if btype != "tavern" and btype != "smithy" and btype != "healer":
		return -1
	var best := -1
	var bd := INF
	for i in lots.size():
		if used.has(i) or String(lots[i]["asset"]) != asset:
			continue
		var d := (lots[i]["pos"] as Vector2).distance_to(c)
		if d < bd:
			bd = d
			best = i
	return best


## Turns the best remaining house lot into `asset` (the nearest to the plaza that the building fits on; role-specific
## preferences: shop and bakery in the market quarter, the guard post by a gate, the smithy in the craft quarter).
static func _convert(plan: Dictionary, lots: Array, asset: String, c: Vector2, used: Dictionary, fits: Callable) -> int:
	var walled: bool = plan["walls"]
	var r: float = plan["wall_radius"]
	var inner: float = plan["inner_wall"]
	var lms: Array = plan["landmarks"]
	var want_district: String = DISTRICTS.get(asset, "")
	var gates: Array = plan["gates"]
	var gate_pos := c + Vector2(cos(float(gates[0])), sin(float(gates[0]))) * r * 0.85 if not gates.is_empty() else c
	var cands: Array = []
	for i in lots.size():
		if used.has(i) or not _free(lots[i]):
			continue
		var a := String(lots[i]["asset"])
		if not BuildingProfiles.is_house(a):
			continue
		var p: Vector2 = lots[i]["pos"]
		var score := p.distance_to(gate_pos) if asset == "house_13" else p.distance_to(c)
		if want_district != "" and String(lots[i].get("district", "")) != want_district:
			score += 1000.0
		cands.append([score, i])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for cd: Array in cands:
		var lot: Dictionary = lots[cd[1]]
		if asset == String(lot["asset"]):
			return int(cd[1])
		var big := BuildingProfiles.size_of(asset)
		if asset != "blacksmith" and asset != "inn" and maxf(big.x, big.z) > 10.6:
			continue
		if bool(fits.call(asset, lot["pos"], lot["yaw"], c, r, walled, inner, lms)):
			lot["asset"] = asset
			return int(cd[1])
	# Nothing bigger fits: the role keeps a house (still tagged, so the services and the interior pass find it).
	for cd: Array in cands:
		return int(cd[1])
	return -1


# --- lookups ------------------------------------------------------------------------------------

static func slice_of(plan: Dictionary) -> Dictionary:
	return plan.get("slice", {})


## The planned town `tid` (a WorldGen.settlements entry), {} before the world exists.
static func town(tid: String) -> Dictionary:
	return TownPlaces.settlement(tid)


## The town id a building id belongs to ("millbrook_smithy" -> "millbrook"): ids start with the town id. "" if none.
static func tid_of_bid(bid: String) -> String:
	if _bid_town.has(bid):
		return String(_bid_town[bid])
	var best := ""
	for tid: String in TownData.ids():
		if bid.begins_with(tid + "_") and tid.length() > best.length():
			best = tid
	if best != "":
		_bid_town[bid] = best
	return best


static func building(bid: String) -> Dictionary:
	var tid := tid_of_bid(bid)
	if tid == "":
		return {}
	return building_in(tid, bid)


static func building_in(tid: String, bid: String) -> Dictionary:
	var s := town(tid)
	if s.is_empty() or not (s["plan"] as Dictionary).has("slice"):
		return {}
	return (slice_of(s["plan"]).get("buildings", {}) as Dictionary).get(bid, {})


static func lots_of_type(tid: String, btype: String) -> Array:
	var out: Array = []
	var s := town(tid)
	if s.is_empty():
		return out
	for bid: String in slice_of(s["plan"]).get("buildings", {}):
		var b: Dictionary = slice_of(s["plan"])["buildings"][bid]
		if String(b["type"]) == btype:
			out.append(bid)
	out.sort()
	return out


## The plain door of a building id (lot door or work-site door), Vector2.INF for an unknown id.
static func door_pos(bid: String) -> Vector2:
	var b := building(bid)
	if not b.is_empty():
		return b["door"]
	return TownPlaces.door_of_any(bid)


## The door-side spot of a building id (lot door, or the site door for a work site), nudged a little per person so a
## household does not stack on one pixel. A work site or the capital's keep gate is a yard, not a doorstep: ten workers share it, so
## their spots are spread over a 3.4 m disc (towns whose file says `outdoor_work`; Thornfield keeps its one-person doorsteps).
## Vector2.INF for an unknown id.
static func door_of(bid: String, row := 0) -> Vector2:
	var p := door_pos(bid)
	if p == Vector2.INF:
		return p
	var h := absi(hash(row * 31 + 7))
	var a := float(h % 628) / 100.0
	var r := 0.9
	if building(bid).is_empty() and bool(TownData.town(tid_of_bid(bid)).get("outdoor_work", false)):
		r = 0.8 + 2.6 * sqrt(float((h / 628) % 100) / 100.0)
	return p + Vector2(cos(a), sin(a)) * r
