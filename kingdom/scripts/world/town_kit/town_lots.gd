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
		if bool(fits.call(asset, lot["pos"], lot["yaw"], c, r, walled, inner, lms)) and not _clips_neighbour(lots, int(cd[1]), asset):
			lot["asset"] = asset
			return int(cd[1])
	# Nothing bigger fits: the role keeps a house (still tagged, so the services and the interior pass find it).
	for cd: Array in cands:
		return int(cd[1])
	return -1


## Would `asset` standing on lot `idx` (its profile footprint, turned by the lot's yaw) overlap the footprint of any other lot?
## (`fits` only knows the walls and the landmarks: a converted inn once ate a quarter of the adventurer guild next to it.)
static func _clips_neighbour(lots: Array, idx: int, asset: String) -> bool:
	var mine := _footprint(lots[idx]["pos"], float(lots[idx]["yaw"]), asset)
	var reach := maxf(BuildingProfiles.size_of(asset).x, BuildingProfiles.size_of(asset).z) + 20.0
	for j in lots.size():
		if j == idx or (lots[j]["pos"] as Vector2).distance_to(lots[idx]["pos"]) > reach:
			continue
		var other := _footprint(lots[j]["pos"], float(lots[j]["yaw"]), String(lots[j]["asset"]))
		var inter := Geometry2D.intersect_polygons(mine, other)
		for poly: PackedVector2Array in inter:
			if absf(_area(poly)) > 2.0:
				return true
	return false


static func _footprint(pos: Vector2, yaw: float, asset: String) -> PackedVector2Array:
	var size := BuildingProfiles.size_of(asset)
	var wall := BuildingProfiles.HERO_WALL if BuildingProfiles.HERO.has(asset) else BuildingProfiles.HOUSE_WALL
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var hx := size.x * wall
	var hz := size.z * wall
	return PackedVector2Array([pos + side * hx + fwd * hz, pos - side * hx + fwd * hz, pos - side * hx - fwd * hz, pos + side * hx - fwd * hz])


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


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


## An offset `at` (x = beside the door, y = out in front of it) from a lot's door, turned into world axes by the lot's yaw, so a clue or stash
## "1.4 m left and 0.8 m out" stands in the street whichever way the house faces (in world axes it ended inside the walls of 11 towns).
## A work site (no lot) keeps `at` as world axes.
static func door_offset(bid: String, at: Vector2) -> Vector2:
	var tid := tid_of_bid(bid)
	var b := building_in(tid, bid) if tid != "" else {}
	if b.is_empty():
		return at
	var plan_lots: Array = (town(tid)["plan"] as Dictionary)["lots"]
	var idx := int(b["lot"])
	if idx < 0 or idx >= plan_lots.size():
		return at
	var yaw: float = plan_lots[idx]["yaw"]
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	return side * at.x + fwd * at.y


## The door-side spot of a building id (lot door, or the site door for a work site), nudged a little per person so a
## household does not stack on one pixel. A work site or the capital's keep gate is a yard, not a doorstep: ten workers share it, so
## their spots are spread over a 3.4 m disc (towns whose file says `outdoor_work`; Thornfield keeps its one-person doorsteps).
## Vector2.INF for an unknown id.
static func door_of(bid: String, row := 0, slot := -1, slots := 0) -> Vector2:
	var p := door_pos(bid)
	if p == Vector2.INF:
		return p
	var h := absi(hash(row * 31 + 7))
	var yard := building(bid).is_empty() and bool(TownData.town(tid_of_bid(bid)).get("outdoor_work", false))
	if slot >= 0 and slots > 1:
		# Everyone who stands at this door gets their own place on a sunflower spiral (golden angle, equal area per person): the hashed
		# disc piled up to six people shoulder to shoulder at a yard (QA sweep of the 30 towns). Within 1.2 m of a doorstep, 3.5 m of a yard.
		var reach := minf(3.5, 1.2 + 0.8 * sqrt(float(slots))) if yard else minf(1.15, 0.7 + 0.2 * float(slots))
		var ang := float(slot) * 2.399963 + float(h % 100) * 0.0063
		var rad := reach * sqrt((float(slot) + 1.0) / float(slots))
		return p + Vector2(cos(ang), sin(ang)) * rad
	var a := float(h % 628) / 100.0
	var r := 0.9
	if yard:
		r = 0.8 + 2.6 * sqrt(float((h / 628) % 100) / 100.0)
	return p + Vector2(cos(a), sin(a)) * r
