extends RefCounted
## Static data for the labyrinths (Aincrad-style multi-floor dungeons, docs/plans/DUNGEONS_LABYRINTH.md): floor themes,
## hand-designed room templates, boss tables, trap kinds, per-floor difficulty scaling and the three world labyrinths
## (Deepdark under Dunhallow, the Ironmarch deeps, the Rift ruins). Pure data, no scene access, deterministic.
## Creature kinds are the ones scripts/interiors/dungeon_creature.gd already knows (test_labyrinth.gd checks that).

const CELL := 3.0

# ---------------------------------------------------------------------------------------------
# themes

## name, surface (SurfaceQuery material of the floor), wall_surface, tint colours, fog/ambient, lit (0 dark .. 1 bright),
## pool by danger tier -> creature kinds, traps (kinds from TRAPS), bosses [[name, title, kind, scale, [patterns]], ...],
## lore title. Boss lists are indexed by floor number so a labyrinth never repeats a boss on consecutive floors.
const THEMES := {
	"caverns": {"name": "Hollow Caverns", "surface": &"dirt", "wall_surface": &"stone",
		"wall": Color(0.36, 0.33, 0.30), "floor": Color(0.24, 0.21, 0.18), "accent": Color(0.55, 0.85, 0.50),
		"fog": Color(0.05, 0.06, 0.08), "ambient": Color(0.10, 0.11, 0.14), "lit": 0.1,
		"pool": {1: ["bat", "giant_rat", "spider"], 2: ["spider", "wolf", "goblin"], 3: ["wolf", "bear", "spider"], 4: ["bear", "mushroom_king", "troll"]},
		"traps": ["spikes", "pit", "rockfall"],
		"bosses": [["Hollowback", "the Den Bear", "bear", 1.6, ["charge", "stomp"]],
			["Gloamfang", "Alpha of the Dark", "wolf", 2.6, ["charge", "summon"]],
			["Mother Silkveil", "Weaver of the Deep", "spider", 3.2, ["lunge", "summon"]]]},
	"flooded": {"name": "Drowned Galleries", "surface": &"stone", "wall_surface": &"stone",
		"wall": Color(0.30, 0.36, 0.40), "floor": Color(0.17, 0.23, 0.27), "accent": Color(0.35, 0.85, 1.0),
		"fog": Color(0.03, 0.07, 0.10), "ambient": Color(0.07, 0.11, 0.15), "lit": 0.1,
		"pool": {1: ["giant_rat", "bog_toad", "bat"], 2: ["bog_toad", "spider", "giant_rat"], 3: ["bog_toad", "ghoul", "spider"], 4: ["ghoul", "rift_slime", "troll"]},
		"traps": ["dart", "pit", "gas"],
		"bosses": [["Gulpmaw", "the Mere King", "bog_toad", 2.8, ["charge", "stomp"]],
			["Skrit", "Lord of the Drains", "giant_rat", 4.0, ["charge", "summon", "stomp"]],
			["The Drowned Archivist", "Keeper of Lost Pages", "ghoul", 1.7, ["sweep", "nova"]]]},
	"crystal": {"name": "Glimmer Vaults", "surface": &"stone", "wall_surface": &"stone",
		"wall": Color(0.26, 0.22, 0.38), "floor": Color(0.14, 0.12, 0.25), "accent": Color(0.85, 0.5, 1.0),
		"fog": Color(0.06, 0.03, 0.10), "ambient": Color(0.10, 0.07, 0.16), "lit": 0.3,
		"pool": {1: ["blight_rat", "bat", "rift_slime"], 2: ["rift_slime", "spider", "ghost_skull"], 3: ["rift_slime", "rift_wraith", "ghost_skull"], 4: ["rift_wraith", "ghost_skull", "ghoul"]},
		"traps": ["rune", "dart", "rockfall"],
		"bosses": [["Shardweaver", "Spinner of Light", "spider", 3.4, ["lunge", "summon", "nova"]],
			["The Shardbound Horror", "Heart of the Geode", "rift_wraith", 2.4, ["nova", "summon"]],
			["Prism Queen", "Mother of Facets", "ghost_skull", 3.8, ["nova", "charge", "summon"]]]},
	"mine": {"name": "Old Workings", "surface": &"wood", "wall_surface": &"stone",
		"wall": Color(0.42, 0.35, 0.28), "floor": Color(0.30, 0.24, 0.18), "accent": Color(1.0, 0.72, 0.30),
		"fog": Color(0.05, 0.04, 0.04), "ambient": Color(0.09, 0.08, 0.08), "lit": 0.6,
		"pool": {1: ["giant_rat", "goblin", "spider"], 2: ["goblin", "spider", "bandit"], 3: ["goblin", "ghoul", "orc"], 4: ["orc", "blackcap_brute", "ghoul"]},
		"traps": ["spikes", "rockfall", "flame"],
		"bosses": [["Old Gorm", "the Blackcap Brute", "blackcap_brute", 1.5, ["slam", "sweep"]],
			["Cogwright Brute", "Hammer of the Engine", "orc", 1.9, ["sweep", "slam"]],
			["Brass Colossus", "Heart of the Foundry", "troll", 1.5, ["slam", "sweep", "charge"]]]},
	"crypt": {"name": "Ancient Crypt", "surface": &"stone", "wall_surface": &"stone",
		"wall": Color(0.50, 0.50, 0.52), "floor": Color(0.30, 0.30, 0.32), "accent": Color(0.70, 0.85, 1.0),
		"fog": Color(0.04, 0.05, 0.08), "ambient": Color(0.08, 0.09, 0.12), "lit": 0.5,
		"pool": {1: ["skeleton_minion", "giant_rat", "bat"], 2: ["skeleton_warrior", "skeleton_minion", "ghoul"], 3: ["skeleton_rogue", "skeleton_mage", "rift_wraith"], 4: ["skeleton_warrior", "skeleton_mage", "rift_wraith"]},
		"traps": ["dart", "spikes", "rune"],
		"bosses": [["The Barrow Warden", "Keeper of the Seal", "troll", 1.2, ["slam", "sweep"]],
			["Ashen Lich-King", "Sovereign of Cinders", "skeleton_mage", 2.2, ["nova", "summon", "slam"]],
			["Bone Regent", "Last of the Old Guard", "skeleton_warrior", 2.4, ["sweep", "summon", "charge"]]]},
	"warren": {"name": "Goblin Warren", "surface": &"dirt", "wall_surface": &"stone",
		"wall": Color(0.42, 0.38, 0.28), "floor": Color(0.28, 0.24, 0.16), "accent": Color(1.0, 0.55, 0.25),
		"fog": Color(0.05, 0.05, 0.03), "ambient": Color(0.10, 0.10, 0.07), "lit": 0.4,
		"pool": {1: ["goblin", "giant_rat"], 2: ["goblin", "spider", "bandit"], 3: ["goblin", "orc", "bandit"], 4: ["orc", "goblin", "blackcap_brute"]},
		"traps": ["spikes", "pit", "flame"],
		"bosses": [["Snarl", "the Tunnel King", "goblin", 2.0, ["charge", "summon"]],
			["Captain Verrick", "of the Ash Hand", "orc", 1.2, ["sweep", "charge"]],
			["Grizzle", "the Ruinlord", "goblin", 3.4, ["sweep", "summon", "slam"]]]},
	"rift": {"name": "Rift Hollows", "surface": &"stone", "wall_surface": &"stone",
		"wall": Color(0.28, 0.20, 0.36), "floor": Color(0.16, 0.10, 0.22), "accent": Color(0.80, 0.45, 1.0),
		"fog": Color(0.07, 0.03, 0.11), "ambient": Color(0.12, 0.07, 0.18), "lit": 0.3,
		"pool": {1: ["blight_rat", "rift_slime", "bat"], 2: ["rift_slime", "ghost_skull", "ghoul"], 3: ["rift_wraith", "ghost_skull", "rift_slime"], 4: ["rift_wraith", "troll", "ghost_skull"]},
		"traps": ["rune", "gas", "rockfall"],
		"bosses": [["Voidmaw", "Eater of Echoes", "rift_wraith", 2.6, ["nova", "lunge", "summon"]],
			["The Scarbound Troll", "Warden of the Mouth", "troll", 1.6, ["slam", "sweep", "nova"]],
			["Riftlord Vael", "Hollow Sovereign", "ghost_skull", 4.0, ["nova", "summon", "charge"]]]},
	"frost": {"name": "Rimebound Halls", "surface": &"snow", "wall_surface": &"stone",
		"wall": Color(0.50, 0.56, 0.63), "floor": Color(0.62, 0.68, 0.74), "accent": Color(0.60, 0.90, 1.0),
		"fog": Color(0.30, 0.36, 0.44), "ambient": Color(0.35, 0.42, 0.52), "lit": 0.7,
		"pool": {1: ["wolf", "bat", "giant_rat"], 2: ["wolf", "bandit", "ghoul"], 3: ["wolf", "bear", "ghoul"], 4: ["bear", "troll", "orc"]},
		"traps": ["pit", "dart", "rockfall"],
		"bosses": [["Rimefang", "Alpha of the White", "wolf", 3.3, ["charge", "sweep", "summon"]],
			["Whitemaw", "Storm-Bear of the Steppe", "bear", 2.3, ["charge", "sweep", "slam"]],
			["Hrimthurs", "Frost Giant", "troll", 1.8, ["slam", "sweep", "nova"]]]},
	"ruins": {"name": "Sundered Ruins", "surface": &"cobble", "wall_surface": &"stone",
		"wall": Color(0.42, 0.39, 0.34), "floor": Color(0.27, 0.25, 0.22), "accent": Color(1.0, 0.55, 0.30),
		"fog": Color(0.10, 0.08, 0.07), "ambient": Color(0.20, 0.18, 0.16), "lit": 0.6,
		"pool": {1: ["bandit", "skeleton_minion", "goblin"], 2: ["bandit", "skeleton_warrior", "orc"], 3: ["orc", "skeleton_rogue", "ghoul"], 4: ["orc", "troll", "skeleton_mage"]},
		"traps": ["spikes", "flame", "rockfall"],
		"bosses": [["Bastion Warden", "Stone Sentinel", "orc", 2.3, ["slam", "sweep", "charge"]],
			["Grimhold the Usurper", "Lord of the Cinders", "troll", 1.6, ["slam", "nova", "sweep"]],
			["The Crown Warden", "Last Voice of the Spire", "troll", 2.0, ["slam", "sweep", "nova", "summon"]]]},
}

# ---------------------------------------------------------------------------------------------
# traps

## kind -> {dmg: base damage (x floor scale), detect: perception needed to spot it (0..1), disarm: can be disarmed,
## radius: m, rearm: seconds (0 = one shot), effect: runtime hint}.
const TRAPS := {
	"spikes": {"dmg": 8, "detect": 0.35, "disarm": true, "radius": 1.2, "rearm": 4.0, "effect": "damage"},
	"dart": {"dmg": 5, "detect": 0.5, "disarm": true, "radius": 0.8, "rearm": 0.0, "effect": "damage_poison"},
	"pit": {"dmg": 10, "detect": 0.45, "disarm": false, "radius": 1.4, "rearm": 0.0, "effect": "fall_damage"},
	"flame": {"dmg": 9, "detect": 0.3, "disarm": true, "radius": 1.6, "rearm": 5.0, "effect": "damage_burn"},
	"rockfall": {"dmg": 12, "detect": 0.55, "disarm": false, "radius": 2.0, "rearm": 0.0, "effect": "damage_stagger"},
	"gas": {"dmg": 3, "detect": 0.6, "disarm": true, "radius": 2.5, "rearm": 8.0, "effect": "poison_cloud"},
	"rune": {"dmg": 6, "detect": 0.7, "disarm": true, "radius": 2.2, "rearm": 0.0, "effect": "alarm_wake_room"},
}

# ---------------------------------------------------------------------------------------------
# room templates (hand-designed)

## Legend: '#' pillar / blocked, '.' floor, 'S' monster slot, 'C' chest slot, 'T' trap slot, 'B' boss spot,
## 'A' altar / warp stone (safe rooms), 'U' stairs up (arrival), 'X' stairs down (opens when the boss dies), 'L' brazier (blocked).
## Every passable cell of a template must be 4-connected and touch the border (test_labyrinth.gd checks both), so doors can sit anywhere.
## roles: which room roles may use it. Templates get a random mirror / rotation when placed.
const TEMPLATES := {
	"arrival": {"roles": ["start"], "rows": [
		"#.......#",
		"....U....",
		".........",
		".L.....L.",
		".........",
		"#.......#"]},
	"sanctuary": {"roles": ["safe"], "rows": [
		"#L.....L#",
		"....A....",
		".........",
		"....A....",
		"#L.....L#"]},
	"arena_small": {"roles": ["combat"], "rows": [
		".......",
		".S.#.S.",
		"...S...",
		".#.S.#.",
		"...S...",
		".S.#.S.",
		"......."]},
	"pillar_hall": {"roles": ["combat"], "rows": [
		"...........",
		".#.S.#.S.#.",
		"...........",
		".S.#...#.S.",
		"...........",
		".#.S.#.S.#.",
		"..........."]},
	"cross_hall": {"roles": ["combat", "trap"], "rows": [
		"##..S..##",
		"##.....##",
		"....S....",
		".S.....S.",
		"....S....",
		"##.....##",
		"##..S..##"]},
	"ring_room": {"roles": ["combat"], "rows": [
		".........",
		".S.....S.",
		"..#####..",
		".S#CCC.S.",
		"..#####..",
		".S.....S.",
		"........."]},
	"long_hall": {"roles": ["combat", "trap"], "rows": [
		".............",
		".S...S...S...",
		"....T...T....",
		".S...S...S...",
		"............."]},
	"collapsed_nave": {"roles": ["combat"], "rows": [
		"....#.....#....",
		".S..#..S..#..S.",
		"...............",
		".S.....S.....S.",
		"....#.....#....",
		"...............",
		".S..#..S..#..S."]},
	"treasure_vault": {"roles": ["treasure"], "rows": [
		"#.....#",
		"...C...",
		".C.S.C.",
		"...C...",
		"#.....#"]},
	"trap_gallery": {"roles": ["trap"], "rows": [
		"...........",
		".T.T.T.T.T.",
		"...........",
		".C.......C.",
		"..........."]},
	"spike_pit": {"roles": ["trap"], "rows": [
		".......",
		".TTTTT.",
		".T.C.T.",
		".TTTTT.",
		"......."]},
	"hidden_cache": {"roles": ["secret"], "rows": [
		".....",
		".CCC.",
		".C.C.",
		"....."]},
	"hidden_shrine": {"roles": ["secret"], "rows": [
		"#...#",
		"..C..",
		".LCL.",
		"..S.."]},
	"midboss_hall": {"roles": ["midboss"], "rows": [
		"#...........#",
		"....#...#....",
		".............",
		".#....B....#.",
		".............",
		"....#...#....",
		"#...........#"]},
	"boss_arena": {"roles": ["boss"], "rows": [
		"###.........###",
		"##...........##",
		"#....#...#....#",
		"......S.S......",
		"......S.S......",
		"...#...B...#...",
		"......S.S......",
		"......S.S......",
		"#....#...#....#",
		"##...........##",
		"###....X....###"]},
}

# ---------------------------------------------------------------------------------------------
# difficulty scaling

## Danger tier (1-4, the same tiers DungeonGen.roll_loot and the creature pools use) for floor index `f` (0-based) of `floors`.
static func tier_for(f: int, floors: int) -> int:
	return clampi(1 + int(floor(4.0 * float(f) / float(maxi(floors, 1)))), 1, 4)


## Character level a floor expects: def.level_base + f * level_step.
static func level_for(def: Dictionary, f: int) -> int:
	return int(def["level_base"]) + f * int(def["level_step"])


## Multiplier on enemy counts, trap damage and loot budgets: 1.0 on floor 1, +9% per floor.
static func scale_for(f: int) -> float:
	return 1.0 + 0.09 * float(f)


## Mid-boss and boss strength multipliers over the base creature (hp, dmg) for floor `f`.
static func boss_mult(f: int, is_boss: bool) -> Vector2:
	var s := scale_for(f)
	if is_boss:
		return Vector2(5.0 * s, 1.5 + 0.06 * float(f))
	return Vector2(2.5 * s, 1.2 + 0.04 * float(f))


# ---------------------------------------------------------------------------------------------
# labyrinths

## id -> definition. `theme_cycle` is walked by floor index; `sites` are name fragments (lower case) the entrance hook matches
## against world site names (labyrinth_sites.gd); `kinds` the world-site kinds that also qualify.
const DEFS := {
	"deepdark": {"name": "The Deepdark", "blurb": "A lightless labyrinth under the Dunhallow uplands. Goblin tunnels give way to older, wetter halls.",
		"floors": 10, "level_base": 6, "level_step": 4, "seed_salt": 7101,
		"theme_cycle": ["warren", "caverns", "flooded", "caverns", "crystal", "crypt", "flooded", "crystal", "crypt", "rift"],
		"sites": ["deepdark"], "kinds": [], "region": "dunhallow_uplands"},
	"ironmarch_deeps": {"name": "The Ironmarch Deeps", "blurb": "The deep levels of the Ironmarch mines, where the seams ran out and the digging did not.",
		"floors": 8, "level_base": 14, "level_step": 5, "seed_salt": 7202,
		"theme_cycle": ["mine", "mine", "warren", "flooded", "mine", "crypt", "crystal", "mine"],
		"sites": ["deepvein", "ironroot", "coldseam", "silverthread", "skullpick", "redtusk"], "kinds": [], "region": "ironmarch_highlands"},
	"rift_ruins": {"name": "The Riftbound Ruins", "blurb": "Ruined halls swallowed by the Rift. The stone remembers a different sky.",
		"floors": 8, "level_base": 20, "level_step": 6, "seed_salt": 7303,
		"theme_cycle": ["ruins", "rift", "crystal", "ruins", "rift", "frost", "rift", "ruins"],
		"sites": ["riftglass", "scarlight", "rift ruins", "the rift"], "kinds": ["rift_ruins"], "region": "rift_marches"},
}
const DEFAULT_ID := "deepdark"


static func def_of(id: String) -> Dictionary:
	return DEFS.get(id, {})


## Theme id of floor index `f` of labyrinth `id`.
static func theme_of(id: String, f: int) -> String:
	var cycle: Array = DEFS[id]["theme_cycle"]
	return cycle[f % cycle.size()]
