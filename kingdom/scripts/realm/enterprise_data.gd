extends RefCounted
## Static tables for the enterprise module (scripts/realm/enterprise.gd): trade goods, workshops,
## fief projects, troops, clan tiers. Pure constants, no state.

## id -> {name, base price, dem (demand per resident per day, sets the normal stock), src "chain"
## (settlements.gd supply chains make and eat it) or "local" (enterprise tops it up), prod (per
## resident per day by settlement kind), cons (per resident per day), cat}.
const GOODS := {
	"grain": {"name": "Grain", "base": 4, "dem": 0.030, "src": "chain", "cat": "food"},
	"flour": {"name": "Flour", "base": 6, "dem": 0.020, "src": "chain", "cat": "food"},
	"bread": {"name": "Bread", "base": 9, "dem": 0.040, "src": "chain", "cat": "food"},
	"fish": {"name": "Fish", "base": 7, "dem": 0.010, "src": "chain", "cat": "food"},
	"wood": {"name": "Timber", "base": 3, "dem": 0.030, "src": "chain", "cat": "raw"},
	"ore": {"name": "Iron ore", "base": 8, "dem": 0.004, "src": "chain", "cat": "raw"},
	"iron": {"name": "Iron", "base": 22, "dem": 0.010, "src": "chain", "cat": "metal"},
	"tools": {"name": "Tools", "base": 40, "dem": 0.004, "src": "chain", "cat": "craft"},
	"ale": {"name": "Ale", "base": 12, "dem": 0.020, "src": "local", "cat": "food", "cons": 0.020,
		"prod": {"village": 0.012, "town": 0.030, "castle": 0.022, "frontier_town": 0.020}},
	"wool": {"name": "Wool", "base": 7, "dem": 0.004, "src": "local", "cat": "raw", "cons": 0.004,
		"prod": {"village": 0.020, "town": 0.003, "castle": 0.000, "frontier_town": 0.005}},
	"hides": {"name": "Hides", "base": 6, "dem": 0.004, "src": "local", "cat": "raw", "cons": 0.004,
		"prod": {"village": 0.012, "town": 0.002, "castle": 0.001, "frontier_town": 0.012}},
	"clay": {"name": "Clay", "base": 3, "dem": 0.003, "src": "local", "cat": "raw", "cons": 0.003,
		"prod": {"village": 0.008, "town": 0.002, "castle": 0.001, "frontier_town": 0.003}},
	"cloth": {"name": "Cloth", "base": 18, "dem": 0.008, "src": "local", "cat": "craft", "cons": 0.008,
		"prod": {"village": 0.003, "town": 0.012, "castle": 0.010, "frontier_town": 0.004}},
	"leather": {"name": "Leather", "base": 20, "dem": 0.005, "src": "local", "cat": "craft", "cons": 0.005,
		"prod": {"village": 0.001, "town": 0.007, "castle": 0.004, "frontier_town": 0.003}},
	"pottery": {"name": "Pottery", "base": 10, "dem": 0.006, "src": "local", "cat": "craft", "cons": 0.006,
		"prod": {"village": 0.004, "town": 0.009, "castle": 0.006, "frontier_town": 0.004}},
	"rift_crystal": {"name": "Rift crystal", "base": 110, "dem": 0.0008, "src": "local", "cat": "rare", "cons": 0.0008,
		"prod": {"village": 0.0, "town": 0.0, "castle": 0.0, "frontier_town": 0.0}},
}
const GOOD_ORDER := ["grain", "flour", "bread", "fish", "wood", "ore", "iron", "tools", "ale", "wool", "hides", "clay", "cloth", "leather", "pottery", "rift_crystal"]
## Goods the local simulation tops up (everything whose src is "local").
const LOCAL_GOODS := ["ale", "wool", "hides", "clay", "cloth", "leather", "pottery", "rift_crystal"]
const SPREAD := 0.10                       # buy/sell gap of an ordinary trader
const RIFT_REACH := 1500.0                 # metres: settlements this close to a rift dig crystal
const RIFT_DANGER_REACH := 800.0

## kind -> {name, price, in, out (per batch), guild (city_life guild kind), kinds (settlement kinds allowed)}.
const WORKSHOPS := {
	"brewery": {"name": "Brewery", "price": 520, "in": {"grain": 3.0, "wood": 1.0}, "out": {"ale": 4.0}, "guild": "merchant",
		"kinds": ["village", "town", "castle", "frontier_town"], "wage": 3},
	"mill": {"name": "Mill", "price": 360, "in": {"grain": 4.0}, "out": {"flour": 3.6}, "guild": "merchant",
		"kinds": ["village", "town", "castle", "frontier_town"], "wage": 3},
	"bakery": {"name": "Bakery", "price": 420, "in": {"flour": 3.0, "wood": 0.5}, "out": {"bread": 4.0}, "guild": "merchant",
		"kinds": ["village", "town", "castle", "frontier_town"], "wage": 3},
	"smithy": {"name": "Smithy", "price": 720, "in": {"iron": 2.0, "wood": 1.0}, "out": {"tools": 2.0}, "guild": "smiths",
		"kinds": ["town", "castle", "frontier_town"], "wage": 4},
	"tannery": {"name": "Tannery", "price": 460, "in": {"hides": 3.0}, "out": {"leather": 2.0}, "guild": "merchant",
		"kinds": ["village", "town", "frontier_town"], "wage": 3},
	"weaver": {"name": "Weaver's hall", "price": 500, "in": {"wool": 3.0}, "out": {"cloth": 2.5}, "guild": "merchant",
		"kinds": ["village", "town", "castle"], "wage": 3},
	"pottery": {"name": "Pottery", "price": 320, "in": {"clay": 4.0, "wood": 1.0}, "out": {"pottery": 4.0}, "guild": "merchant",
		"kinds": ["village", "town", "frontier_town"], "wage": 3},
}
const WORKSHOP_ORDER := ["brewery", "mill", "bakery", "smithy", "tannery", "weaver", "pottery"]
const SETTLEMENT_MULT := {"village": 1.0, "town": 1.6, "castle": 2.4, "frontier_town": 1.2}
const BATCHES_PER_LEVEL := 1.2
const WORKERS_PER_LEVEL := 2
const MAX_LEVEL := 3
const HIRE_COST := 12
const UPKEEP_FRACTION := 0.004             # of the purchase price per day (rent and town levy)
const GUILD_MEMBER_BONUS := 0.06
const GUILD_OUTSIDER_LEVY := 0.10

## Fief projects: built over days by a crew of real workers (man-days), paid from the fief treasury.
const PROJECTS := {
	"market": {"label": "Market square", "gold": 180, "work": 40, "text": "More stalls: trade tax and trade volume rise."},
	"granary": {"label": "Granary", "gold": 120, "work": 30, "text": "Stores keep through winter and bad harvests."},
	"walls": {"label": "Town walls", "gold": 260, "work": 70, "text": "Raids break on stone: security rises."},
	"roads": {"label": "Road works", "gold": 140, "work": 35, "text": "Mends every road out of town."},
	"mill": {"label": "Mill", "gold": 150, "work": 30, "text": "A mill turns grain to flour for the whole fief."},
	"barracks": {"label": "Barracks", "gold": 220, "work": 50, "text": "A bigger garrison and a larger recruit pool."},
	"warehouse": {"label": "Warehouse", "gold": 160, "work": 35, "text": "Merchants stop here; prosperity rises."},
}
const PROJECT_ORDER := ["market", "granary", "walls", "roads", "mill", "barracks", "warehouse"]
const CREW_WAGE := 3
const CREW_MAX := 14

## Troop types: tier gates by settlement standing, wage per day, upfront price, battle power.
const TROOPS := {
	"levy": {"name": "Levy spearman", "tier": 1, "cost": 12, "wage": 1, "power": 1.0, "standing": 20.0},
	"footman": {"name": "Footman", "tier": 2, "cost": 30, "wage": 2, "power": 2.2, "standing": 40.0},
	"archer": {"name": "Archer", "tier": 2, "cost": 34, "wage": 2, "power": 2.0, "standing": 45.0},
	"man_at_arms": {"name": "Man-at-arms", "tier": 3, "cost": 80, "wage": 4, "power": 5.0, "standing": 65.0},
}
const TROOP_ORDER := ["levy", "footman", "archer", "man_at_arms"]

## Clan tiers by renown.
const CLAN_TIERS := [
	{"id": "wanderer", "name": "Wanderer", "renown": 0.0, "text": "Nobody follows a stranger."},
	{"id": "household", "name": "Household", "renown": 40.0, "text": "A small retinue: you can raise troops."},
	{"id": "clan", "name": "Clan", "renown": 140.0, "text": "Lords hear you out: you may swear as a vassal."},
	{"id": "minor_house", "name": "Minor House", "renown": 320.0, "text": "A banner of your own."},
	{"id": "house", "name": "House", "renown": 650.0, "text": "A seat at the council."},
	{"id": "great_house", "name": "Great House", "renown": 1100.0, "text": "Kings write to you."},
]
const PARTY_BASE := 10
const PARTY_PER_TIER := 6
const PARTY_PER_FIEF := 5

const LICENSE_COST := 80
const CART_COST := 120
const GUARD_COST := 20
const GUARD_WAGE := 6
const INFORMANT_COST := 30
const RUMOUR_COST := 12
const CARAVAN_CAP := 60
const GUARD_RISK_REDUCTION := 0.16
const OFFROAD_SPEED := 0.72                # a shortcut takes this much of the road time
const SHORTCUT_RISK := 2.2

## Road levels and gold per metre to reach them from the level below.
const ROAD_COST_PER_M := {"dirt": 0.0, "road": 0.12, "stone": 0.30, "military": 0.45}
const MAINTAIN_COST_PER_M := 0.05

const DUTIES := {
	"patrol": {"name": "Patrol the road", "days": 2, "pay": 14, "renown": 1.0, "text": "Ride the road and keep raiders off it."},
	"escort": {"name": "Escort a convoy", "days": 3, "pay": 12, "renown": 1.4, "text": "Guard an army supply convoy."},
	"drill": {"name": "Drill recruits", "days": 1, "pay": 10, "renown": 0.6, "text": "Train the local levy: the recruit pool grows."},
}
