extends RefCounted
## Survival-style construction: constants only (no state). The catalogue runs from tier 0 (a fire and a
## lean-to) to tier 4 (keep, temple, guild hall). Nothing above tier 0 can be placed until the tier below
## stands, the named prerequisite buildings are finished, the know-how is learned (from a workbench, a
## mason's bench or a master builder) and the materials are on hand; tall buildings also need a worker of
## real building skill on the crew. See scripts/realm/construction.gd for the logic.

const REGION := "res://assets/generated/region/"

## Labour-hours are worked only in daylight.
const WORK_FROM := 6
const WORK_TO := 20
const WORK_HOURS_PER_DAY := 14
## Closed-form catch-up never simulates more than this many working hours per site in one call.
const CATCH_UP_CAP_DAYS := 40

## Share of every material you must hold (inventory + holding store) to lay a blueprint.
const START_SHARE := 0.25
## Upgrades reuse the old foundations and timbers.
const UPGRADE_COST := 0.7
const UPGRADE_HOURS := 0.6

const HOLDING_RADIUS := 110.0
const PLACE_REACH := 45.0
const MAX_SLOPE := 2.4
## Metres walked per game hour when hauling (the world is time-compressed like camps.TRAVEL_M_PER_HOUR).
const HAUL_M_PER_HOUR := 420.0
const LOAD_HOURS := 0.3
const CARRY_BASE := 8.0

const STAGES := ["foundation", "frame", "walls", "roof", "complete"]
## Progress (0..1) at which each stage begins.
const STAGE_AT := [0.0, 0.15, 0.4, 0.75, 1.0]

## Builder skill is 0..1 (mastery level / 100 for the player, follower "building" skill, hired skill).
const MASTER_SKILL := 0.65
const HIRE_WAGE := 4
const MASTER_WAGE := 14
const MAX_WORKERS := 12
const TOOL_BONUS := 1.25
const MASTER_BONUS := 0.15
const MASTER_BONUS_CAP := 0.3
const CROWD_FACTOR := 0.35
const PLAYER_NEAR := 70.0

## Trails: uses needed for a footpath and a worn road between two buildings; speed multipliers.
const FOOTPATH_USES := 8.0
const ROAD_USES := 60.0
const PATH_SPEED := {"": 1.0, "footpath": 1.25, "road": 1.5}

## Settlement levels: what is built plus who lives there.
const LEVELS := [
	{"id": "camp", "name": "Camp", "buildings": 1, "pop": 0, "tiers": 0, "roles": {}},
	{"id": "hamlet", "name": "Hamlet", "buildings": 5, "pop": 6, "tiers": 1, "roles": {"shelter": 2, "storage": 1}},
	{"id": "village", "name": "Village", "buildings": 12, "pop": 20, "tiers": 2, "roles": {"shelter": 4, "storage": 1, "water": 1, "food": 1}},
	{"id": "town", "name": "Town", "buildings": 26, "pop": 60, "tiers": 3, "roles": {"shelter": 8, "trade": 1, "defence": 2, "craft": 1}},
]

## Gatherable wild nodes: tool bonus, strikes to fell, bonus when felled, regrowth.
const NODES := {
	"tree": {"item": "log", "hp": 3, "per": 1, "tool": "wood_axe", "bonus": 1, "finish": 2, "regrow": 6, "verb": "Chop tree", "skill": "carpentry"},
	"rock": {"item": "stone", "hp": 5, "per": 1, "tool": "pickaxe", "bonus": 1, "finish": 3, "regrow": 8, "verb": "Quarry rock", "skill": "mining"},
	"clay": {"item": "clay", "hp": 4, "per": 2, "tool": "", "bonus": 0, "finish": 2, "regrow": 4, "verb": "Dig clay", "skill": ""},
	"reeds": {"item": "thatch", "hp": 3, "per": 2, "tool": "", "bonus": 0, "finish": 2, "regrow": 2, "verb": "Cut thatch", "skill": ""},
}
const NODE_CELL := 18.0

## Material items (added to data/items.json): id -> display name.
const MATERIALS := {"log": "Log", "stone": "Quarry Stone", "clay": "Clay", "thatch": "Thatch", "cut_stone": "Cut Stone",
	"plank": "Wooden Plank", "iron_ingot": "Iron Ingot", "tools": "Iron Tools"}
const MATERIAL_ORDER := ["log", "plank", "stone", "cut_stone", "clay", "thatch", "iron_ingot", "tools"]

## Processing stations: building kind -> {in, n_in, out, n_out, per_hour (units of input a crafter turns per hour)}.
const STATIONS := {
	"sawhorse": {"in": "log", "n_in": 1, "out": "plank", "n_out": 1, "per_hour": 2},
	"workshop": {"in": "log", "n_in": 1, "out": "plank", "n_out": 2, "per_hour": 3},
	"mason_bench": {"in": "stone", "n_in": 2, "out": "cut_stone", "n_out": 1, "per_hour": 4},
}

## kind -> definition.
##   tier, name, desc, cost {item: n}, hours (labour-hours), size (metres w x d), asset (Assets.BUILDINGS key or res path, or
##   "proc:<name>" for a built-in prop), role, beds, store (capacity added), ident (settlements.gd STRUCT_WEIGHT kind),
##   needs (finished buildings), know (facts), grants (facts), min_skill (best builder on the crew), upgrades_from, upkeep (gold/day).
const CATALOG := {
	# ---- tier 0: survival
	"campfire": {"tier": 0, "name": "Campfire", "desc": "Warmth and light. Every camp starts here.", "cost": {"log": 3}, "hours": 1.0,
		"size": Vector2(2, 2), "asset": REGION + "ruins/campfire.glb", "role": "shelter", "beds": 0, "grants": ["build:fire"]},
	"lean_to": {"tier": 0, "name": "Lean-to", "desc": "Branches and thatch against the wind. One bed.", "cost": {"log": 5, "thatch": 4}, "hours": 3.0,
		"size": Vector2(3, 2.5), "asset": REGION + "ruins/bandit_lean_to.glb", "role": "shelter", "beds": 1},
	"tent": {"tier": 0, "name": "Tent", "desc": "Quick to raise, quick to lose. Two beds.", "cost": {"thatch": 6, "log": 3}, "hours": 2.0,
		"size": Vector2(3.5, 3.5), "asset": REGION + "ruins/bandit_tent.glb", "role": "shelter", "beds": 2},
	"drying_rack": {"tier": 0, "name": "Drying rack", "desc": "Smoke and dry meat and fish so a camp can eat through winter.", "cost": {"log": 4}, "hours": 2.0,
		"size": Vector2(2.4, 1.2), "asset": "proc:rack", "role": "food"},
	"storage_pile": {"tier": 0, "name": "Storage pile", "desc": "A covered heap of goods. Haulers draw materials from here.", "cost": {"log": 2, "thatch": 2}, "hours": 2.0,
		"size": Vector2(2.6, 2.6), "asset": "sack_pile", "role": "storage", "store": 60},
	# ---- tier 1: a settled camp
	"hut": {"tier": 1, "name": "Wattle hut", "desc": "Clay-daubed walls and a thatch roof. Three beds.", "cost": {"log": 10, "thatch": 8, "clay": 4}, "hours": 10.0,
		"size": Vector2(4.2, 3.8), "asset": "house_1", "role": "shelter", "beds": 3, "needs": ["storage_pile"]},
	"fence": {"tier": 1, "name": "Fence", "desc": "Keeps animals in and strangers honest.", "cost": {"log": 2}, "hours": 1.0,
		"size": Vector2(3, 0.6), "asset": "fence", "role": "defence", "needs": ["storage_pile"]},
	"well": {"tier": 1, "name": "Well", "desc": "Clean water. Fewer fevers, more people.", "cost": {"stone": 10, "log": 4}, "hours": 8.0,
		"size": Vector2(2.2, 2.2), "asset": "well", "role": "water", "needs": ["storage_pile"]},
	"workbench": {"tier": 1, "name": "Workbench", "desc": "Proper joinery. Teaches carpentry and unlocks timber buildings.", "cost": {"log": 8, "tools": 1}, "hours": 6.0,
		"size": Vector2(2.6, 1.6), "asset": "produce_table", "role": "craft", "needs": ["hut"], "grants": ["build:carpentry"]},
	"sawhorse": {"tier": 1, "name": "Sawhorse", "desc": "Saw logs into planks, by hand or with a hired sawyer.", "cost": {"log": 6, "tools": 1}, "hours": 4.0,
		"size": Vector2(2.2, 1.2), "asset": "proc:sawhorse", "role": "craft", "needs": ["workbench"]},
	"field": {"tier": 1, "name": "Field", "desc": "Turned earth for a few rows of grain.", "cost": {"log": 2}, "hours": 6.0,
		"size": Vector2(8, 8), "asset": "garden_plot", "role": "food", "needs": ["hut"]},
	# ---- tier 2: a working village
	"timber_house": {"tier": 2, "name": "Timber house", "desc": "Sawn planks, a real roof, five beds. Upgrades a wattle hut.", "cost": {"plank": 24, "thatch": 10, "clay": 6, "tools": 2},
		"hours": 60.0, "size": Vector2(6.5, 6.0), "asset": "house_5", "role": "shelter", "beds": 5, "needs": ["workbench", "sawhorse"],
		"know": ["build:carpentry"], "min_skill": 0.15, "upgrades_from": "hut", "upkeep": 0.2},
	"workshop": {"tier": 2, "name": "Workshop", "desc": "A roofed sawpit: planks twice as fast.", "cost": {"plank": 20, "stone": 8, "tools": 3}, "hours": 45.0,
		"size": Vector2(7, 6), "asset": "house_3", "role": "craft", "needs": ["sawhorse"], "know": ["build:carpentry"], "min_skill": 0.15, "upkeep": 0.3},
	"mason_bench": {"tier": 2, "name": "Mason's bench", "desc": "Dress quarry stone into blocks. Teaches masonry.", "cost": {"stone": 12, "log": 6, "tools": 2}, "hours": 10.0,
		"size": Vector2(2.6, 1.6), "asset": "proc:mason", "role": "craft", "needs": ["workbench"], "grants": ["build:masonry"]},
	"palisade": {"tier": 2, "name": "Palisade", "desc": "A wall of sharpened trunks. Raiders think twice.", "cost": {"log": 20}, "hours": 16.0,
		"size": Vector2(8, 1.2), "asset": REGION + "ruins/bandit_palisade.glb", "role": "defence", "needs": ["fence"], "ident": "tower", "min_skill": 0.1},
	"watchtower": {"tier": 2, "name": "Watchtower", "desc": "See trouble coming.", "cost": {"plank": 16, "log": 10, "stone": 6}, "hours": 40.0,
		"size": Vector2(4, 4), "asset": "watchtower", "role": "defence", "needs": ["workbench", "palisade"], "ident": "tower", "min_skill": 0.25, "upkeep": 0.3},
	"barn": {"tier": 2, "name": "Barn", "desc": "Stores grain and shelters animals. Big storage.", "cost": {"plank": 22, "thatch": 14}, "hours": 40.0,
		"size": Vector2(8, 6), "asset": "stable", "role": "storage", "store": 150, "needs": ["field", "sawhorse"], "know": ["build:carpentry"], "min_skill": 0.15},
	# ---- tier 3: a proper town
	"stone_house": {"tier": 3, "name": "Stone house", "desc": "Cut stone walls that last generations. Eight beds. Upgrades a timber house.",
		"cost": {"cut_stone": 30, "plank": 16, "clay": 10, "tools": 4}, "hours": 120.0, "size": Vector2(7.5, 7.0), "asset": "mhouse_family", "role": "shelter", "beds": 8,
		"needs": ["mason_bench", "timber_house"], "know": ["build:masonry"], "min_skill": 0.4, "upgrades_from": "timber_house", "upkeep": 0.4},
	"smithy": {"tier": 3, "name": "Smithy", "desc": "Forge and anvil: iron tools from your own hearth.", "cost": {"cut_stone": 24, "iron_ingot": 6, "plank": 10, "tools": 4}, "hours": 100.0,
		"size": Vector2(9, 8), "asset": "blacksmith", "role": "craft", "needs": ["mason_bench", "workshop"], "know": ["build:masonry"], "min_skill": 0.4, "ident": "smithy", "upkeep": 0.6},
	"market": {"tier": 3, "name": "Market", "desc": "Stalls and a square: trade finds you.", "cost": {"plank": 30, "cut_stone": 10, "tools": 3}, "hours": 90.0,
		"size": Vector2(10, 8), "asset": "market_stall_red", "role": "trade", "needs": ["workshop", "barn"], "know": ["build:masonry"], "min_skill": 0.35, "ident": "market", "upkeep": 0.5},
	"stone_wall": {"tier": 3, "name": "Stone wall", "desc": "A wall section. Lay them end to end.", "cost": {"cut_stone": 16}, "hours": 40.0,
		"size": Vector2(8, 1.6), "asset": "wall", "role": "defence", "needs": ["palisade", "mason_bench"], "know": ["build:masonry"], "min_skill": 0.4, "ident": "wall"},
	"gate": {"tier": 3, "name": "Gatehouse", "desc": "A gap in the wall you can close.", "cost": {"cut_stone": 20, "plank": 10, "iron_ingot": 4}, "hours": 60.0,
		"size": Vector2(8, 3), "asset": "wall_gate", "role": "defence", "needs": ["stone_wall"], "know": ["build:masonry"], "min_skill": 0.45, "ident": "gate", "upkeep": 0.4},
	"granary": {"tier": 3, "name": "Granary", "desc": "Dry stores that carry a settlement through winter.", "cost": {"plank": 30, "cut_stone": 12, "thatch": 10}, "hours": 70.0,
		"size": Vector2(6, 6), "asset": REGION + "farm/granary.glb", "role": "storage", "store": 300, "needs": ["barn", "mason_bench"], "know": ["build:masonry"], "min_skill": 0.35},
	# ---- tier 4: seat of power
	"keep": {"tier": 4, "name": "Keep", "desc": "A fortified seat of power. Twenty beds.", "cost": {"cut_stone": 120, "plank": 60, "iron_ingot": 20, "tools": 10}, "hours": 400.0,
		"size": Vector2(16, 16), "asset": "castle", "role": "command", "beds": 20, "store": 200, "needs": ["smithy", "stone_wall", "stone_house"],
		"know": ["build:masonry", "build:architecture"], "min_skill": 0.65, "ident": "barracks", "upkeep": 2.0},
	"temple": {"tier": 4, "name": "Temple", "desc": "Faith gathers a people.", "cost": {"cut_stone": 80, "plank": 30, "iron_ingot": 6, "tools": 6}, "hours": 240.0,
		"size": Vector2(12, 14), "asset": "temple", "role": "faith", "needs": ["market", "stone_house"], "know": ["build:masonry", "build:architecture"], "min_skill": 0.6, "ident": "temple", "upkeep": 1.0},
	"guild_hall": {"tier": 4, "name": "Guild hall", "desc": "Crafts and trades bargain under one roof.", "cost": {"cut_stone": 60, "plank": 50, "iron_ingot": 10, "tools": 6}, "hours": 220.0,
		"size": Vector2(12, 10), "asset": "adventurer_guild", "role": "trade", "needs": ["market", "smithy"], "know": ["build:masonry", "build:architecture"], "min_skill": 0.6, "ident": "library", "upkeep": 1.0},
	"stone_tower": {"tier": 4, "name": "Stone tower", "desc": "A tall, hard tower for archers.", "cost": {"cut_stone": 60, "plank": 20, "iron_ingot": 4, "tools": 4}, "hours": 160.0,
		"size": Vector2(6, 6), "asset": "wall_tower", "role": "defence", "needs": ["stone_wall"], "know": ["build:masonry"], "min_skill": 0.55, "ident": "tower", "upkeep": 0.6},
	# Build-kit hook (scripts/realm/build_kit.gd, docs/regions/HOOKS_FOR_CLOUD.md): a blueprint of kit pieces that a crew raises. Its cost and
	# hours are set per site by place_kit_plan(); hidden from the building menus.
	"kit_plan": {"tier": 0, "name": "Kit blueprint", "desc": "Walls, roofs and floors you laid out piece by piece, raised by a crew.", "cost": {}, "hours": 1.0,
		"size": Vector2(2.4, 2.4), "asset": "res://assets/incoming/build_kit/storage_crates_lod0.glb", "role": "build", "hidden": true},
}
const TIER_NAMES := ["Survival", "Camp", "Village", "Town", "Seat of power"]
const KIND_ORDER := ["campfire", "lean_to", "tent", "drying_rack", "storage_pile", "hut", "fence", "well", "workbench", "sawhorse", "field",
	"timber_house", "workshop", "mason_bench", "palisade", "watchtower", "barn", "stone_house", "smithy", "market", "stone_wall", "gate", "granary",
	"keep", "temple", "guild_hall", "stone_tower", "kit_plan"]
## Facts a master builder will teach (gold, labour days). Needs a master builder within reach.
const LESSONS := {
	"build:carpentry": {"name": "Carpentry", "gold": 40},
	"build:masonry": {"name": "Masonry", "gold": 90},
	"build:architecture": {"name": "Architecture", "gold": 220},
}
const KNOW_NAMES := {"build:fire": "Fire-making", "build:carpentry": "Carpentry", "build:masonry": "Masonry", "build:architecture": "Architecture"}

## kind -> fiefs/enterprise project key it stands for (fief projects built by crews).
const FIEF_TO_KIND := {"market": "market", "granary": "granary", "walls": "stone_wall", "mill": "workshop", "barracks": "keep", "warehouse": "barn"}
## kind -> camps.gd STRUCTURES kind so finished buildings join a camp's supply chain.
const CAMP_KIND := {"well": "well", "smithy": "smithy", "barn": "stable", "granary": "warehouse", "storage_pile": "warehouse",
	"market": "market_stall", "field": "farm_plot", "palisade": "palisade", "watchtower": "watchtower"}

const NAMES := ["Osric", "Mabel", "Tomas", "Wren", "Hodge", "Ada", "Piers", "Nell", "Gunnar", "Edda", "Rowan", "Hale", "Corin", "Maud"]


static func def(kind: String) -> Dictionary:
	return CATALOG.get(kind, {})


static func kinds_of_tier(t: int) -> Array:
	var out: Array = []
	for k: String in KIND_ORDER:
		if int(CATALOG[k]["tier"]) == t and not bool(CATALOG[k].get("hidden", false)):
			out.append(k)
	return out


static func stage_index(p: float) -> int:
	var i := 0
	for s in STAGE_AT.size() - 1:
		if p >= STAGE_AT[s]:
			i = s
	if p >= 1.0:
		i = STAGE_AT.size() - 1
	return i


static func stage_name(p: float) -> String:
	return STAGES[stage_index(p)]


## Half extents (metres) of a building's footprint, for obstacles.
static func half_size(kind: String) -> Vector2:
	var s: Vector2 = CATALOG.get(kind, {}).get("size", Vector2(3, 3))
	return s * 0.5
