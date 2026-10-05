extends RefCounted
## Where Thornfield's places are in the live world: the Brewery landmark (brewhouse, kegs, tithe granary, wheat rows,
## Hesta's stool), the farm with its windmill, barn and pens, and the town. Everything is derived from WorldGen.sites
## and WorldGen.settlements, so it follows the layout if a site moves. No class_name; preload and call statics.
##
## Place ids (the ones data/quests/thornfield/*.json use): thornfield, thornfield_barn, thornfield_fields,
## thornfield_mill. Offsets are site-local (x right, y front, metres) in the part format of RegionSites.

const BREWERY_ID := "landmark_thornfield"
const FARM_NAME := "Thornfield Farm"
## Site-local offsets inside the Brewery landmark (data/region1/world/settlements.json Thornfield parts).
const BARN_AT := Vector2(-3.0, -10.0)         # the tithe granary (farm/granary)
const BARN_DOOR := Vector2(-3.0, -5.2)        # the yard in front of it
const BREWHOUSE_AT := Vector2(10.0, -4.0)
const TABLE_AT := Vector2(-1.0, 5.5)          # the long table beside Hesta's stool
const FIELD_AT := Vector2(-8.0, -20.0)        # the wheat rows behind the granary
const HESTA_AT := Vector2(0.0, 8.5)
## Site-local offsets inside the farm (RegionSites._farmstead).
const WINDMILL_AT := Vector2(-14.0, -14.0)
const PIG_STY_AT := Vector2(-4.0, -2.0)
const COOP_AT := Vector2(16.0, 3.0)
const FARM_BARN_AT := Vector2(9.0, -8.0)
const PLACE_RADIUS := {"thornfield": 130.0, "thornfield_barn": 16.0, "thornfield_fields": 36.0, "thornfield_mill": 18.0}


static func settlement() -> Dictionary:
	for s in WorldGen.settlements:
		if String(s["name"]) == "Thornfield":
			return s
	return {}


static func brewery() -> Dictionary:
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) == BREWERY_ID:
			return s
	return {}


static func farm() -> Dictionary:
	for s in WorldGen.sites:
		if String(s["name"]) == FARM_NAME:
			return s
	return {}


## Site-local offset -> world XZ (the same transform RegionDressing places site parts with).
static func to_world(site: Dictionary, local: Vector2) -> Vector2:
	var yaw: float = site["yaw"]
	return (site["pos"] as Vector2) + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


## Unit vector the site's +Y (front) points to in the world.
static func front(site: Dictionary) -> Vector2:
	return to_world(site, Vector2(0, 1)) - (site["pos"] as Vector2)


## {id: {pos: Vector2, radius: float}} for the four quest places, empty entries left out.
static func places() -> Dictionary:
	var out := {}
	var s := settlement()
	if not s.is_empty():
		out["thornfield"] = {"pos": s["pos"], "radius": PLACE_RADIUS["thornfield"]}
	var b := brewery()
	if not b.is_empty():
		out["thornfield_barn"] = {"pos": to_world(b, BARN_AT), "radius": PLACE_RADIUS["thornfield_barn"]}
		out["thornfield_fields"] = {"pos": to_world(b, FIELD_AT), "radius": PLACE_RADIUS["thornfield_fields"]}
	var f := farm()
	if not f.is_empty():
		out["thornfield_mill"] = {"pos": to_world(f, WINDMILL_AT), "radius": PLACE_RADIUS["thornfield_mill"]}
	return out


static func place_pos(id: String) -> Vector2:
	var p: Dictionary = places().get(id, {})
	return p["pos"] if not p.is_empty() else Vector2.INF


## Door-side position of a site building id (thornfield_brewery, thornfield_barn, thornfield_farm, thornfield_mill),
## Vector2.INF for anything else.
static func door_of_site(bid: String) -> Vector2:
	match bid:
		"thornfield_brewery":
			var b := brewery()
			return to_world(b, Vector2(8.0, 2.0)) if not b.is_empty() else Vector2.INF
		"thornfield_barn":
			var b2 := brewery()
			return to_world(b2, BARN_DOOR) if not b2.is_empty() else Vector2.INF
		"thornfield_farm":
			var f := farm()
			return to_world(f, Vector2(-6.0, 4.0)) if not f.is_empty() else Vector2.INF
		"thornfield_mill":
			var f2 := farm()
			return to_world(f2, WINDMILL_AT + Vector2(0.0, 5.0)) if not f2.is_empty() else Vector2.INF
	return Vector2.INF


## The night the barn is watched: a spot at the barn where the stranger stands.
static func figure_spot() -> Vector2:
	var b := brewery()
	return to_world(b, BARN_DOOR + Vector2(1.6, 0.4)) if not b.is_empty() else Vector2.INF
