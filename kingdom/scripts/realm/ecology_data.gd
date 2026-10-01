extends RefCounted
## Constants for realm/ecology.gd (CIV-C living ecology, docs/design/CIVILIZATION.md). Pure data, no state.
## Species are indexed so a zone's populations fit one flat Array: [deer, boar, wolf, corrupted_wolf, bear, troll, wyvern].

const SPECIES := ["deer", "boar", "wolf", "corrupted_wolf", "bear", "troll", "wyvern"]
const DEER := 0
const BOAR := 1
const WOLF := 2
const CORR := 3
const BEAR := 4
const TROLL := 5
const WYVERN := 6
const PREY := [0, 1]
const APEX := [4, 5, 6]
## Species the live RAMonsterEcology knows as dens (prey are not spawned as bodies).
const DEN_SPECIES := [2, 3, 4, 5, 6]

const LABEL := {"deer": "deer", "boar": "boar", "wolf": "wolf", "corrupted_wolf": "corrupted wolf", "bear": "bear",
	"troll": "troll", "wyvern": "wyvern"}
## Apex individuals count as this much threat each; prey carry none.
const THREAT := [0.0, 0.0, 1.0, 1.6, 6.0, 10.0, 14.0]
const GROUP_NAME := {"wolf": "pack", "corrupted_wolf": "pack", "bear": "bear", "troll": "troll", "wyvern": "pair", "deer": "herd", "boar": "sounder"}
## The worse apex that moves into a niche once its holder is gone.
const WORSE := {"bear": "troll", "troll": "wyvern", "wyvern": "wyvern"}
## Apex tiers by distance from the capital: near the heartland only bears wander in.
const TIER_MAX_APEX := [[1500.0, 4], [2600.0, 5], [99999.0, 6]]

## Prey logistic growth per day and carrying capacity per zone at full wildness.
const PREY_R := [0.05, 0.04]
const PREY_K := [60.0, 30.0]
const PREY_CROSS := [0.6, 0.25]   # effect of the other prey on [deer, boar]
## Predation hazard on each prey species (per predator, per day), rows = species index.
const HAZARD := {2: [0.0006, 0.0003], 3: [0.0008, 0.0004], 4: [0.020, 0.024], 5: [0.022, 0.020], 6: [0.020, 0.010]}
## Territorial mesopredators: slow numerical response, capped by territory and food.
const WOLF_R := 0.02
const WOLF_K := 11.0
const CORR_R := 0.018
const CORR_K := 9.0
## Apex hazard on wolves (per apex per day).
const APEX_ON_WOLF := {4: 0.004, 5: 0.005, 6: 0.006}
const ADV_HUNT := 0.0006          # extra predator mortality per adventurer in the zone
const HUMAN_HUNT := 0.004         # guards and farmers thin predators in human land (scaled by 1 - wild)
const EXTINCT_BELOW := 0.25
const APEX_NEED := 12.0           # food units (half a deer + three wolves) one apex wants
const APEX_MAX := 3

## Continuous migration rate per day (fraction of the source population) while the trigger holds.
const WINTER_WOLF_PUSH := 0.012
const SPRING_RETURN := 0.02
const AUTUMN_HERD_PUSH := 0.006
const CROWD_PUSH := 0.02
const FLEE_PUSH := 0.012
const RIFT_PUSH := 0.012
const RIFT_LEAK := 0.02           # corrupted wolves seeping out of a Rift zone per day at full instability

## Adventurer economy.
const ADV_INFLOW := 0.5           # per day at full attraction in a zone of average size
const ADV_LEAVE_BASE := 0.03
const SERVICES := ["inn", "equipment", "healer", "guide", "bounty_office"]
## Adventurers needed per service level.
const SERVICE_PER := {"inn": 3.0, "equipment": 4.0, "healer": 5.0, "guide": 6.0, "bounty_office": 8.0}
const SERVICE_MAX := 4.0
const SERVICE_UP := 0.02
const SERVICE_DOWN := 0.05
const DUNGEON_KINDS := ["tower_ruin", "rift", "rift_outpost", "goblin_warren", "orc_village", "cave", "dungeon", "hollow"]

## Domestication (settlement tech): familiarity per day toward 1 while the species is present, decay while absent.
const DOMESTIC := {
	"boar": {"use": "farming", "rate": 0.00045, "ref": 4.0},
	"deer": {"use": "resources", "rate": 0.00035, "ref": 8.0},
	"wolf": {"use": "guarding", "rate": 0.00025, "ref": 4.0},
	"wyvern": {"use": "transport", "rate": 0.00009, "ref": 1.0},
}
## [name, species index, rate, ref] rows of DOMESTIC for the per-step loop.
const DOM_ROWS := [["boar", 1, 0.00045, 4.0], ["deer", 0, 0.00035, 8.0], ["wolf", 2, 0.00025, 4.0], ["wyvern", 6, 0.00009, 1.0]]
const DOMESTIC_DECAY := 0.0008
const DOM_LEVELS := [[0.2, "wild"], [0.45, "tolerated"], [0.7, "tamed"], [1.01, "domesticated"]]

## Intelligent monster factions.
const FACTION_INTENTS := ["hold", "trade", "raid", "negotiate", "migrate", "settle"]
const DECISION_DAYS := 10
const MARCH_M_PER_DAY := 450.0
const FACTION_SPECIES := {"goblin": {"strength": 14.0, "temper": 0.55, "cunning": 0.45}, "orc": {"strength": 11.0, "temper": 0.65, "cunning": 0.55}}
