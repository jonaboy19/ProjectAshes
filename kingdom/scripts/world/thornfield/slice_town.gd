extends RefCounted
## Guarantees Thornfield (the vertical-slice town) has the lots the village life needs: a blacksmith, a general shop,
## a tavern, a bakery, a guard post and a healer, plus a numbered row of named homes. The playtest found a town once
## had no blacksmith lot, so these are forced, not hoped for. CityPlanner.plan calls `enforce` once, after the
## districts are zoned and before the door paths are made, and nothing else in the plan moves.
##
## Each chosen lot keeps its drawn building (`asset`) unless a role needs a different one, and gains
##   lot["bid"]    stable building id ("thornfield_smithy", "thornfield_house_3", ...)
##   lot["btype"]  what it is: smithy | general_shop | tavern | bakery | guard_post | healer | house
## (building_profiles.gd / the interior pass key off `asset`; `btype` is the extra hook for shop vs house).
## plan["slice"] = {town, buildings: {bid: {type, asset, lot, pos, door}}, sites: {bid: what}} is the registry; the
## farm, brewery, mill and livestock are sites of the region plan (sites.gd), listed under plan["slice"]["sites"].
##
## No class_name; preload it. Pure functions of the plan: no autoloads.

const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const TOWN := "Thornfield"
const HOME_COUNT := 18
## role -> [btype, wanted asset, bid]
const ROLES := [
	["tavern", "inn", "thornfield_inn"],
	["smithy", "blacksmith", "thornfield_smithy"],
	["general_shop", "mhouse_trader", "thornfield_shop"],
	["bakery", "house_town_b", "thornfield_bakery"],
	["guard_post", "house_13", "thornfield_guard_post"],
	["healer", "healer_house", "thornfield_healer"],
]
## Types a town of the slice must have in its plan (tests/test_thornfield.gd).
const REQUIRED_TYPES := ["tavern", "smithy", "general_shop", "bakery", "guard_post", "healer"]
## Site ids the region plan must also hold near Thornfield.
const REQUIRED_SITES := {"thornfield_brewery": "landmark", "thornfield_farm": "farm"}

static var _plans: Dictionary = {}     # settlement id -> plan["slice"] (for door_of without the settlement scan)


static func is_slice_town(s: Dictionary) -> bool:
	return String(s.get("name", "")) == TOWN


## Adds the forced lots and the building registry to `plan` (settlement `s`). `fits` = CityPlanner.fits.
static func enforce(plan: Dictionary, s: Dictionary, fits: Callable) -> void:
	if not is_slice_town(s):
		return
	var lots: Array = plan["lots"]
	var c: Vector2 = plan["centre"]
	var used := {}
	var buildings := {}
	for role: Array in ROLES:
		var idx := _find_lot(lots, String(role[0]), String(role[1]), c, used)
		if idx < 0:
			idx = _convert(plan, lots, String(role[1]), c, used, fits)
		if idx < 0:
			continue
		used[idx] = true
		_tag(lots[idx], String(role[0]), String(role[2]), buildings, idx)
	# Named homes: the houses nearest the plaza, numbered in a stable order.
	var homes: Array = []
	for i in lots.size():
		if not used.has(i) and BuildingProfiles.is_house(String(lots[i]["asset"])) and String((lots[i] as Dictionary).get("btype", "")) == "":
			homes.append(i)
	homes.sort_custom(func(a: int, b: int) -> bool:
		var da := (lots[a]["pos"] as Vector2).distance_to(c)
		var db := (lots[b]["pos"] as Vector2).distance_to(c)
		return da < db or (da == db and (lots[a]["pos"] as Vector2).x < (lots[b]["pos"] as Vector2).x))
	for k in mini(HOME_COUNT, homes.size()):
		_tag(lots[homes[k]], "house", "thornfield_house_%d" % (k + 1), buildings, homes[k])
	plan["slice"] = {"town": TOWN, "buildings": buildings,
		"sites": {"thornfield_brewery": "Thornfield Brewery", "thornfield_farm": "Thornfield Farm", "thornfield_mill": "Thornfield Farm windmill"}}
	_plans[int(s["id"])] = plan["slice"]


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
	var districts := {"blacksmith": "craft", "mhouse_trader": "market", "house_town_b": "market", "house_13": "military", "inn": "inn"}
	var want_district: String = districts.get(asset, "")
	var gates: Array = plan["gates"]
	var gate_pos := c + Vector2(cos(float(gates[0])), sin(float(gates[0]))) * r * 0.85 if not gates.is_empty() else c
	var cands: Array = []
	for i in lots.size():
		if used.has(i) or String((lots[i] as Dictionary).get("btype", "")) != "":
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


## The planned Thornfield (WorldGen.settlements entry), {} before the world exists.
static func town() -> Dictionary:
	for s in WorldGen.settlements:
		if is_slice_town(s):
			return s
	return {}


static func building(bid: String) -> Dictionary:
	var s := town()
	if s.is_empty():
		return {}
	return (slice_of(s["plan"]).get("buildings", {}) as Dictionary).get(bid, {})


static func lots_of_type(btype: String) -> Array:
	var out: Array = []
	var s := town()
	if s.is_empty():
		return out
	for bid: String in slice_of(s["plan"]).get("buildings", {}):
		var b: Dictionary = slice_of(s["plan"])["buildings"][bid]
		if String(b["type"]) == btype:
			out.append(bid)
	out.sort()
	return out


## The door-side spot of a building id (lot door, or the site door for the brewery/farm/mill/barn), nudged a little
## per person so a household does not stack on one pixel. Vector2.INF for an unknown id.
static func door_of(bid: String, row := 0) -> Vector2:
	var p := Vector2.INF
	var b := building(bid)
	if not b.is_empty():
		p = b["door"]
	else:
		p = preload("res://scripts/world/thornfield/sites.gd").door_of_site(bid)
	if p == Vector2.INF:
		return p
	var a := float(absi(hash(row * 31 + 7)) % 628) / 100.0
	return p + Vector2(cos(a), sin(a)) * 0.9
