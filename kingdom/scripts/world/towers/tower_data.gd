extends RefCounted
## Static data for the dungeon towers (docs/design/DUNGEON_TOWERS.md): towers, floor themes, floor bosses, boss pattern
## catalogue, relics and level scaling. Pure data, no scene access, deterministic. Preloaded (no class_name).

## Tower rows. `pos` is filled at planning time (tower_planner.gd) and read from WorldGen.sites (kind "dungeon_tower").
const TOWERS := {
	"ashfall_spire": {"name": "The Ashfall Spire", "floors": 20, "lvl_min": 5, "lvl_max": 60, "region": 1,
		"blurb": "A colossal spire of ancient stone and glowing runes. No one has seen its crown."},
}
const DEFAULT_TOWER := "ashfall_spire"

## Theme kits: palette and look. wall/floor/accent are albedo colours, `fog` the room's fog/background, `ceiling` whether
## the labyrinth is roofed, `water` a flooded floor, `props` the dressing families, `mobs` the floor's creature kinds.
const THEMES := {
	"forest": {"name": "Forest", "wall": Color(0.26, 0.34, 0.2), "floor": Color(0.2, 0.28, 0.13), "accent": Color(0.55, 1.0, 0.45),
		"fog": Color(0.1, 0.17, 0.11), "ambient": Color(0.5, 0.65, 0.5), "ceiling": false, "water": false,
		"props": ["tree", "rock", "root"], "mobs": ["wolf", "boar", "spider"], "trim": Color(0.36, 0.28, 0.16)},
	"flooded": {"name": "Flooded Halls", "wall": Color(0.3, 0.36, 0.4), "floor": Color(0.17, 0.23, 0.27), "accent": Color(0.35, 0.85, 1.0),
		"fog": Color(0.05, 0.13, 0.18), "ambient": Color(0.4, 0.6, 0.7), "ceiling": true, "water": true,
		"props": ["column", "rubble", "weed"], "mobs": ["giant_rat", "goblin", "blight_rat"], "trim": Color(0.22, 0.3, 0.3)},
	"crystal": {"name": "Crystal Caverns", "wall": Color(0.22, 0.2, 0.36), "floor": Color(0.14, 0.12, 0.25), "accent": Color(0.85, 0.5, 1.0),
		"fog": Color(0.07, 0.04, 0.14), "ambient": Color(0.55, 0.45, 0.8), "ceiling": true, "water": false,
		"props": ["crystal", "crystal", "rock"], "mobs": ["spider", "fungal_brute", "goblin"], "trim": Color(0.3, 0.22, 0.5)},
	"clockwork": {"name": "Clockwork Halls", "wall": Color(0.38, 0.3, 0.2), "floor": Color(0.22, 0.18, 0.13), "accent": Color(1.0, 0.72, 0.25),
		"fog": Color(0.12, 0.08, 0.04), "ambient": Color(0.75, 0.6, 0.4), "ceiling": true, "water": false,
		"props": ["gear", "pipe", "column"], "mobs": ["orc", "goblin", "blackcap_brute"], "trim": Color(0.5, 0.36, 0.14)},
	"snow": {"name": "Snowfield", "wall": Color(0.5, 0.56, 0.63), "floor": Color(0.68, 0.72, 0.78), "accent": Color(0.6, 0.9, 1.0),
		"fog": Color(0.45, 0.52, 0.6), "ambient": Color(0.85, 0.9, 1.0), "ceiling": false, "water": false,
		"props": ["drift", "pine", "rock"], "mobs": ["wolf", "bear", "troll"], "trim": Color(0.5, 0.58, 0.66)},
	"ruins": {"name": "Ancient Ruins", "wall": Color(0.42, 0.39, 0.34), "floor": Color(0.27, 0.25, 0.22), "accent": Color(1.0, 0.55, 0.3),
		"fog": Color(0.1, 0.08, 0.07), "ambient": Color(0.65, 0.58, 0.5), "ceiling": true, "water": false,
		"props": ["column", "rubble", "brazier"], "mobs": ["goblin", "orc", "troll"], "trim": Color(0.34, 0.3, 0.26)},
}

## Floor rows (index 0 = floor 1): [floor name, theme, boss]. Boss: [name, title, creature kind, scale, tint, [patterns]].
const FLOORS := [
	["Mossroot Hollow", "forest", ["Gorm the Mossback", "Warden of the Hollow", "boar", 2.7, Color(0.7, 0.85, 0.55), ["charge", "stomp"]]],
	["Sunken Cloisters", "flooded", ["Skrit, the Sewer King", "Lord of the Drains", "giant_rat", 4.2, Color(0.75, 0.8, 0.9), ["charge", "summon", "stomp"]]],
	["Glimmer Vaults", "crystal", ["Shardweaver", "Spinner of Light", "spider", 3.4, Color(0.8, 0.6, 1.0), ["lunge", "summon", "nova"]]],
	["Cogwork Halls", "clockwork", ["Cogwright Brute", "Hammer of the Engine", "h:Plate_Knight", 1.7, Color(1.0, 0.78, 0.45), ["sweep", "slam"]]],
	["Rimefield Terrace", "snow", ["Rimefang", "Alpha of the White", "wolf", 3.3, Color(0.85, 0.95, 1.0), ["charge", "sweep", "summon"]]],
	["Sundered Bastion", "ruins", ["Grizzle the Ruinlord", "Usurper of Stones", "goblin", 3.6, Color(0.9, 0.7, 0.55), ["sweep", "summon", "slam"]]],
	["Sporewood Gallery", "forest", ["The Sporemother", "Bloom of Rot", "fungal_brute", 1.9, Color(0.75, 0.95, 0.6), ["slam", "nova", "summon"]]],
	["Drowned Archive", "flooded", ["The Drowned Archivist", "Keeper of Lost Pages", "troll", 1.3, Color(0.6, 0.8, 0.9), ["sweep", "nova", "slam"]]],
	["Prism Deep", "crystal", ["Prism Queen", "Mother of Facets", "spider", 4.4, Color(1.0, 0.6, 0.95), ["lunge", "nova", "summon", "charge"]]],
	["Brasswork Foundry", "clockwork", ["Brass Colossus", "Heart of the Foundry", "blackcap_brute", 2.3, Color(1.0, 0.8, 0.45), ["slam", "sweep", "charge", "nova"]]],
	["Whitewind Steppe", "snow", ["Whitemaw", "Storm-Bear of the Steppe", "bear", 2.2, Color(0.9, 0.95, 1.0), ["charge", "sweep", "slam", "summon"]]],
	["Collapsed Keep", "ruins", ["Bastion Warden", "Stone Sentinel", "orc", 2.3, Color(0.7, 0.68, 0.62), ["slam", "sweep", "charge", "nova"]]],
	["Thornwood Maze", "forest", ["Thornmother Vael", "Hedge-Queen", "wolf", 4.0, Color(0.55, 0.8, 0.4), ["lunge", "summon", "charge", "nova"]]],
	["Tidal Crypts", "flooded", ["Brinewraith", "Drowned Admiral", "troll", 1.5, Color(0.45, 0.7, 0.85), ["sweep", "nova", "summon", "slam"]]],
	["Geode Halls", "crystal", ["Geodrake", "Wyrm of the Hollow Stone", "wyvern", 2.4, Color(0.85, 0.55, 1.0), ["lunge", "nova", "charge", "summon"]]],
	["Orrery Engine", "clockwork", ["The Orrery Regent", "Timekeeper Automaton", "troll", 1.65, Color(1.0, 0.85, 0.5), ["slam", "nova", "sweep", "summon"]]],
	["Glacier Keep", "snow", ["Hrimthurs", "Frost Giant", "troll", 1.8, Color(0.75, 0.9, 1.0), ["slam", "sweep", "nova", "charge"]]],
	["Ashen Necropolis", "ruins", ["Ashen Lich-King", "Sovereign of Cinders", "h:Orc_Warchief", 1.55, Color(0.6, 0.55, 0.6), ["nova", "summon", "slam", "sweep"]]],
	["Emberwild", "forest", ["Cinderstag", "Wildfire Avatar", "boar", 4.6, Color(1.0, 0.6, 0.35), ["charge", "nova", "summon", "stomp"]]],
	["Crown of Runes", "ruins", ["The Crown Warden", "Last Voice of the Spire", "troll", 2.3, Color(1.0, 0.85, 0.4), ["slam", "sweep", "nova", "charge", "summon"]]],
]

## Boss pattern catalogue. kind: circle (around the boss), cone (in front), line (charge), ring (expanding wave), summon.
## windup seconds, radius/length metres, dmg multiplier of the boss base hit, cd = rest after it.
const PATTERNS := {
	"stomp": {"name": "Stomp", "kind": "circle", "windup": 0.9, "radius": 3.6, "dmg": 0.8, "cd": 1.2, "hint": "Stay out of the red ring"},
	"slam": {"name": "Earthshatter", "kind": "circle", "windup": 1.4, "radius": 6.5, "dmg": 1.3, "cd": 2.0, "hint": "Run from the boss when it rears up"},
	"sweep": {"name": "Reaping Sweep", "kind": "cone", "windup": 1.1, "radius": 6.0, "dmg": 1.1, "cd": 1.6, "hint": "Roll behind it or keep away from its front"},
	"charge": {"name": "Rampage", "kind": "line", "windup": 1.3, "radius": 16.0, "dmg": 1.5, "cd": 2.2, "hint": "Sidestep the line it paws at"},
	"lunge": {"name": "Shadow Lunge", "kind": "line", "windup": 0.75, "radius": 9.0, "dmg": 1.0, "cd": 1.4, "hint": "Quick; dodge as the line flashes"},
	"nova": {"name": "Runic Nova", "kind": "ring", "windup": 1.7, "radius": 13.0, "dmg": 1.4, "cd": 2.4, "hint": "Dodge through the wave as it reaches you"},
	"summon": {"name": "Call of the Hall", "kind": "summon", "windup": 1.4, "radius": 0.0, "dmg": 0.0, "cd": 3.0, "hint": "It calls minions; kill them or keep moving"},
}

const RELIC_SLOTS := ["Blade", "Mantle", "Crown", "Band", "Sigil", "Gauntlet"]


static func tower(id: String) -> Dictionary:
	return TOWERS.get(id, {})


static func tower_ids() -> Array:
	return TOWERS.keys()


static func floor_count(id: String) -> int:
	return int(tower(id).get("floors", 0))


## Recommended character level of a floor (linear 5 .. 60 across the tower).
static func floor_level(id: String, floor_n: int) -> int:
	var t := tower(id)
	var n := maxi(1, int(t.get("floors", 20)))
	var k := clampf(float(floor_n - 1) / maxf(1.0, float(n - 1)), 0.0, 1.0)
	return int(round(lerpf(float(t.get("lvl_min", 5)), float(t.get("lvl_max", 60)), k)))


## Floor row as a dictionary: {floor, name, theme, boss:{name,title,kind,scale,tint,patterns}, level, tier}.
## Towers with fewer rows than floors reuse rows cyclically (a future second tower).
static func floor_info(id: String, floor_n: int) -> Dictionary:
	var row: Array = FLOORS[(floor_n - 1) % FLOORS.size()]
	var b: Array = row[2]
	return {"floor": floor_n, "name": row[0], "theme": row[1], "level": floor_level(id, floor_n), "tier": tier_of(floor_n),
		"boss": {"name": b[0], "title": b[1], "kind": b[2], "scale": b[3], "tint": b[4], "patterns": (b[5] as Array).duplicate(),
			"hp": boss_hp(floor_n), "damage": boss_damage(floor_n)}}


## Loot tier 1..6 (Region 1 covers the low tiers of a game that goes to level 500).
static func tier_of(floor_n: int) -> int:
	return clampi(1 + (floor_n - 1) / 4, 1, 6)


static func boss_hp(floor_n: int) -> int:
	return 380 + 210 * (floor_n - 1)


static func boss_damage(floor_n: int) -> int:
	return int(round(9.0 + 2.4 * float(floor_n)))


static func mob_hp(floor_n: int) -> int:
	return 36 + 12 * floor_n


static func mob_damage(floor_n: int) -> int:
	return int(round(5.0 + 1.5 * float(floor_n)))


## Unique first-clear drop (Last-Attack style): a relic with a passive bonus.
static func relic(id: String, floor_n: int) -> Dictionary:
	var info := floor_info(id, floor_n)
	var slot: String = RELIC_SLOTS[(floor_n - 1) % RELIC_SLOTS.size()]
	var bname := String(info["boss"]["name"]).split(",")[0]
	var stats := ["max_health", "damage", "armour", "stamina_regen"]
	var stat: String = stats[(floor_n - 1) % stats.size()]
	var val: float = {"max_health": 6.0 + 2.0 * floor_n, "damage": 1.0 + 0.6 * floor_n, "armour": 1.0 + 0.5 * floor_n, "stamina_regen": 0.04 + 0.01 * floor_n}[stat]
	return {"id": "tower_relic_%s_%d" % [id, floor_n], "name": "%s's %s" % [bname.replace("The ", "").replace("the ", ""), slot],
		"floor": floor_n, "stat": stat, "value": snappedf(float(val), 0.01), "tier": info["tier"]}


static func theme(key: String) -> Dictionary:
	return THEMES.get(key, THEMES["ruins"])
