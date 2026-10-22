extends RefCounted
## Where Thornfield's places are in the live world: the Brewery landmark (brewhouse, kegs, tithe granary, wheat rows,
## Hesta's stool), the farm with its windmill, barn and pens, and the town. Everything is derived from WorldGen.sites
## and WorldGen.settlements, so it follows the layout if a site moves. No class_name; preload and call statics.
##
## The generic part (anchors, places, doors) is the town kit's: data/region1/towns/thornfield.json lists the places
## (thornfield, thornfield_barn, thornfield_fields, thornfield_mill, the ids data/quests/thornfield/*.json use) and the work
## doors, and scripts/world/town_kit/town_places.gd resolves them. This file keeps the site-local offsets the Thornfield
## special scripts (clues, barn figure, Hesta's stool) are built around, and the call shapes the tests were written against.
## Offsets are site-local (x right, y front, metres) in the part format of RegionSites.

const BREWERY_ID := "landmark_thornfield"
const FARM_NAME := "Thornfield Farm"
## Site-local offsets inside the Brewery landmark (data/region1/world/settlements.json Thornfield parts).
const BARN_AT := Vector2(-3.0, -10.0)         # the tithe granary (farm/granary)
const BARN_DOOR := Vector2(-3.0, -5.2)        # the yard in front of it
const BREWHOUSE_AT := Vector2(10.0, -4.0)
const TABLE_AT := Vector2(-1.0, 5.5)          # the long table beside Hesta's stool
const FIELD_AT := Vector2(-8.0, -20.0)        # the wheat rows behind the granary
const HESTA_AT := Vector2(-6.5, 9.0)         # clear ground left of the name board and lamp posts, facing the street
## Site-local offsets inside the farm (RegionSites._farmstead).
const WINDMILL_AT := Vector2(-14.0, -14.0)
const PIG_STY_AT := Vector2(-4.0, -2.0)
const COOP_AT := Vector2(16.0, 3.0)
const FARM_BARN_AT := Vector2(9.0, -8.0)

const TID := "thornfield"
const KitPlaces := preload("res://scripts/world/town_kit/town_places.gd")


static func settlement() -> Dictionary:
	return KitPlaces.settlement(TID)


static func brewery() -> Dictionary:
	return KitPlaces.site_of({"r1id": BREWERY_ID})


static func farm() -> Dictionary:
	return KitPlaces.site_of({"name": FARM_NAME})


## Site-local offset -> world XZ (the same transform RegionDressing places site parts with).
static func to_world(site: Dictionary, local: Vector2) -> Vector2:
	return KitPlaces.to_world(site, local)


## Unit vector the site's +Y (front) points to in the world.
static func front(site: Dictionary) -> Vector2:
	return KitPlaces.front(site)


## {id: {pos: Vector2, radius: float}} for the four quest places, empty entries left out.
static func places() -> Dictionary:
	return KitPlaces.places(TID)


static func place_pos(id: String) -> Vector2:
	return KitPlaces.place_pos(TID, id)


## Door-side position of a site building id (thornfield_brewery, thornfield_barn, thornfield_farm, thornfield_mill),
## Vector2.INF for anything else.
static func door_of_site(bid: String) -> Vector2:
	return KitPlaces.door_of_site(TID, bid)


## The night the barn is watched: a spot at the barn where the stranger stands.
static func figure_spot() -> Vector2:
	var b := brewery()
	return to_world(b, BARN_DOOR + Vector2(1.6, 0.4)) if not b.is_empty() else Vector2.INF
