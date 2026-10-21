extends RefCounted
## MN-0: player-facing vocabulary for the soul reserve, and aliases that keep old saves and data keys working.
## Internal identifiers (class RAMagicules, the "magicules" resource key, "magicule_regen" effect keys) stay as they are so saves load;
## everything a player reads says "soul reserve" (the pool) and "ember" (one unit). New code may use the alias on the left.

const ALIASES := {"soul_reserve": "magicules", "embers": "magicules", "ember": "magicule", "ember_regen": "magicule_regen",
	"ember_max": "magicule_max", "ember_burn": "magicule_burn", "ember_growth": "magicule_growth", "reserve_cost": "magicules_cost"}
const DISPLAY := {"magicules": "soul reserve", "magicule": "ember", "magicule_regen": "reserve regeneration", "magicule_max": "reserve size",
	"magicule_burn": "Ember Burn", "magicule_growth": "reserve growth"}


## The key stored in saves and data for an alias (unknown keys pass through).
static func canonical(key: String) -> String:
	return String(ALIASES.get(key, key))


## What the player reads for an internal key.
static func display(key: String) -> String:
	return String(DISPLAY.get(canonical(key), key.replace("_", " ")))
