extends "res://scripts/world/town_kit/town_threat.gd"
## The wolves of Thornfield: the town kit's threat (scripts/world/town_kit/town_threat.gd) configured from the `threat` of
## data/region1/towns/thornfield.json (a wolf den in the forest near the town, night probes of the fields, the grain-cart
## ambush). Kept as its own class so the Thornfield tests and QA tools keep their `WolfThreat.new()` / `DEN_RING` shapes.


func _init() -> void:
	configure("thornfield")
