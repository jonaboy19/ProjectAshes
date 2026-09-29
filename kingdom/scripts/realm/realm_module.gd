extends RefCounted
## Base for every realm-simulation module (docs/design/SIM_HIERARCHY.md).
## Pure data: no nodes, no scene access. The hub (realm_hub.gd) calls these at
## the tier the module declares and hands in `ctx` (see realm_hub.gd `_ctx`).
## Every tick returns Array[String] of Game.say-able lines.

## Set by the hub so modules can reach siblings: hub.mod("factions").
var hub: RefCounted = null


## Tier 2: once per game hour (one module per frame, never all at once).
func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


## Tier 3: once per game day (queued, one module per frame from 06:00).
func tick_day(_day: int, _ctx: Dictionary) -> Array:
	return []


## Tier 4: once per game week, statistical far-away resolution.
func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


## Catch-up after sleep, travel or a load: `days` elapsed while unobserved.
## Must be O(entities), never O(days * entities) -- resolve statistically.
func catch_up(_days: int, _ctx: Dictionary) -> Array:
	return []


func serialize() -> Dictionary:
	return {}


func deserialize(_d: Dictionary) -> void:
	pass
