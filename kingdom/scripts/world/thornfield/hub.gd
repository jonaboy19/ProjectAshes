extends "res://scripts/world/town_kit/town_hub.gd"
## Thornfield's hub, as the town kit sees it: the generic TownHub (scripts/world/town_kit/town_hub.gd) for the town
## "thornfield", with Thornfield's set pieces in special.gd. The town file names this script as its `hub` so the QA tools
## and tests that call the Thornfield-specific methods below (and `get("cart")`, `get("figure")`, ... which the kit forwards to
## the special) keep working. `Hub.new()` is a Thornfield hub; the kit's `TownHub.attach(parent, "thornfield")` adds one.


func _init() -> void:
	tid = "thornfield"


func store_available() -> bool:
	return special.call("store_available")


func take_barley() -> String:
	return special.call("take_barley")


func cart_route() -> PackedVector2Array:
	return special.call("cart_route")
