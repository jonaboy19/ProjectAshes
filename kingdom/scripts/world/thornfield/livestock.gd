extends RefCounted
## Thornfield's livestock, as the town kit sees it: a thin facade over scripts/world/town_kit/town_livestock.gd for the town
## "thornfield" (the groups and pens are in data/region1/towns/thornfield.json). AmbientLife calls the kit for every town.
## Preload, no class_name; every function is static.

const TID := "thornfield"
const KitLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")


static func groups() -> Array:
	return KitLivestock.groups(TID)


static func add_groups(ambient: Node) -> int:
	return KitLivestock.add_groups(ambient, TID)


static func build_pens(parent: Node) -> Node3D:
	return KitLivestock.build_pens(TID, parent)
