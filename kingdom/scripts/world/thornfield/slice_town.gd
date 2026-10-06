extends RefCounted
## Thornfield's lots, as the town kit sees them: a thin facade over scripts/world/town_kit/town_lots.gd bound to the town
## "thornfield" (its required lots are in data/region1/towns/thornfield.json). The lot rules (forced tavern, smithy, shop,
## bakery, guard post, healer and a numbered row of homes) are the kit's and run for every town file; this keeps the call
## shapes the Thornfield tests and QA tools were written against. Preload, no class_name; every function is static.

const TID := "thornfield"
const TOWN := "Thornfield"
const KitLots := preload("res://scripts/world/town_kit/town_lots.gd")
## Types a town of the slice must have in its plan (tests/test_thornfield.gd).
const REQUIRED_TYPES := ["tavern", "smithy", "general_shop", "bakery", "guard_post", "healer"]
## Site ids the region plan must also hold near Thornfield.
const REQUIRED_SITES := {"thornfield_brewery": "landmark", "thornfield_farm": "farm"}


static func is_slice_town(s: Dictionary) -> bool:
	return String(s.get("name", "")) == TOWN


static func enforce(plan: Dictionary, s: Dictionary, fits: Callable) -> void:
	KitLots.enforce(plan, s, fits)


static func slice_of(plan: Dictionary) -> Dictionary:
	return KitLots.slice_of(plan)


static func town() -> Dictionary:
	return KitLots.town(TID)


static func building(bid: String) -> Dictionary:
	return KitLots.building(bid)


static func lots_of_type(btype: String) -> Array:
	return KitLots.lots_of_type(TID, btype)


static func door_of(bid: String, row := 0) -> Vector2:
	return KitLots.door_of(bid, row)
