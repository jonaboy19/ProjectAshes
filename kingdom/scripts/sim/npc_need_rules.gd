extends RefCounted
## Shared low-cost need rates used by embodied UtilityBrains and the packed,
## unembodied WorldSim rows. Keep both LODs on the same depletion/personality rules.

const RANeedsScript := preload("res://scripts/sim/needs.gd")

const FATIGUE_PER_HOUR := RANeedsScript.FATIGUE_PER_HOUR / 100.0
const SLEEP_PER_HOUR := RANeedsScript.SLEEP_PER_HOUR / 100.0
const HUNGER_PER_HOUR := 0.11
const WATER_PER_HOUR := 0.09
const EAT_RESTORE_PER_HOUR := 2.5
const MEALS := [7.0, 12.5, 18.5]
const OFFLINE_CATCHUP_HOURS := 24.0


## Matches UtilityBrain's stable per-person trait generator without allocating
## a Dictionary for distant residents.
static func trait_value(person: int, trait_index: int) -> float:
	var h1 := hash(person * 2246822519 + trait_index * 3266489917 + 1066)
	var h2 := hash(person * 668265263 + trait_index * 374761393 + 7)
	return (float(h1 % 1000) + float(h2 % 1000)) / 1998.0


static func social_drain_per_hour(person: int) -> float:
	return 0.05 + 0.08 * trait_value(person, 0)


static func faith_drain_per_hour(person: int) -> float:
	return 0.02 + 0.05 * trait_value(person, 2)
