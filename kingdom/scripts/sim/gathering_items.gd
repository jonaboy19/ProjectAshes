extends RefCounted
## Hunting, fishing and foraging data: the new items (GLoot prototypes), their
## market prices, the hunting drop table, the fishing rarity table and the
## forage table. Pure data plus a few static helpers so it tests without autoloads.
##
## register(Life) adds the prototypes to the live protoset (data/items.json) and
## the goods to the village market. It is idempotent, and it must run before a
## save that carries these items is loaded. AmbientLife and Lakeside call it
## from _ready; Life can also call it from _setup_market().

const ItemsDB := preload("res://scripts/sim/items_db.gd")

## Protoset entries, in the same shape as data/items.json.
const ITEMS := {
	"venison": {"inherits": "food", "name": "Venison", "price": 5, "nutrition": 30},
	"rabbit_meat": {"inherits": "food", "name": "Rabbit Meat", "price": 3, "nutrition": 14},
	"pork": {"inherits": "food", "name": "Wild Pork", "price": 4, "nutrition": 24},
	"perch": {"inherits": "food", "name": "Perch", "price": 2, "nutrition": 12},
	"trout": {"inherits": "food", "name": "Brook Trout", "price": 4, "nutrition": 18},
	"pike": {"inherits": "food", "name": "Pike", "price": 7, "nutrition": 26},
	"emberfin": {"inherits": "food", "name": "Emberfin", "price": 30, "nutrition": 40, "heal": 20, "max_stack_size": 5},
	"mushroom": {"inherits": "food", "name": "Wood Mushroom", "price": 2, "nutrition": 8},
	"wild_berries": {"inherits": "food", "name": "Wild Berries", "price": 1, "nutrition": 6},
	"healing_herb": {"name": "Healing Herb", "category": "healing", "price": 3, "heal": 12, "max_stack_size": 20},
	"deer_hide": {"name": "Deer Hide", "category": "material", "price": 9, "max_stack_size": 20},
	"fox_pelt": {"name": "Fox Pelt", "category": "material", "price": 10, "max_stack_size": 20},
	"boar_tusk": {"name": "Boar Tusk", "category": "material", "price": 7, "max_stack_size": 20},
}

## item -> [base price, normal stock, made locally per day]. Fish and forage have
## a little local supply (villagers fish and pick too); game and hides do not.
const MARKET := {
	"venison": [5, 8, 0],
	"rabbit_meat": [3, 10, 0],
	"pork": [4, 8, 0],
	"perch": [2, 16, 3],
	"trout": [4, 10, 1],
	"pike": [7, 6, 0],
	"emberfin": [30, 2, 0],
	"mushroom": [2, 12, 2],
	"wild_berries": [1, 20, 4],
	"healing_herb": [3, 12, 1],
	"deer_hide": [9, 6, 0],
	"fox_pelt": [10, 4, 0],
	"boar_tusk": [7, 4, 0],
}

# --- hunting --------------------------------------------------------------------

## Wild game a player may hunt: kind -> health. Everything else (livestock, pets,
## horses, waterfowl in the village) is protected.
const GAME_HEALTH := {"rabbit": 10, "fox": 20, "deer": 28, "stag": 40}

## kind -> [[item, count], ...]. Boar is a beast (Wolf controller), dropped by AmbientLife.
const HUNT_DROPS := {
	"deer": [["venison", 1], ["deer_hide", 1]],
	"stag": [["venison", 2], ["deer_hide", 1]],
	"rabbit": [["rabbit_meat", 1]],
	"fox": [["fox_pelt", 1]],
	"boar": [["pork", 1], ["boar_tusk", 1]],
}


static func is_game(kind: String) -> bool:
	return GAME_HEALTH.has(kind)


static func drops_for(kind: String) -> Array:
	return HUNT_DROPS.get(kind, [])


# --- fishing --------------------------------------------------------------------

## Emberfin only rise to the surface while the sun sets over the Mere.
const SUNSET := Vector2(17.5, 20.0)

## fish -> {lake weight, river weight, sunset-only, reel zone width (0..1),
## fish pull speed, progress lost per second out of the zone}.
const FISH := {
	"perch": {"lake": 60.0, "river": 30.0, "sunset": false, "zone": 0.32, "pull": 0.35, "drain": 0.18},
	"trout": {"lake": 26.0, "river": 50.0, "sunset": false, "zone": 0.26, "pull": 0.55, "drain": 0.22},
	"pike": {"lake": 14.0, "river": 8.0, "sunset": false, "zone": 0.2, "pull": 0.7, "drain": 0.26},
	"emberfin": {"lake": 7.0, "river": 2.0, "sunset": true, "zone": 0.15, "pull": 0.9, "drain": 0.3},
}
const FISH_ORDER := ["perch", "trout", "pike", "emberfin"]
## Named pools with their own stock (FishingSpot.pool). The Hollin Falls plunge pool (Region 1 look pass) is a rare-fish
## spot: no perch, and the emberfin rise there at any hour, not only at sunset.
const POOLS := {
	"plunge": {"perch": 0.0, "trout": 40.0, "pike": 25.0, "emberfin": 35.0},
}


static func is_sunset(hour: float) -> bool:
	return hour >= SUNSET.x and hour < SUNSET.y


## fish -> weight for this water and hour.
static func fish_weights(hour: float, river := false, pool := "") -> Dictionary:
	var out := {}
	if POOLS.has(pool):
		for id: String in FISH_ORDER:
			out[id] = float((POOLS[pool] as Dictionary).get(id, 0.0))
		return out
	for id: String in FISH_ORDER:
		var f: Dictionary = FISH[id]
		var w := float(f["river" if river else "lake"])
		if bool(f["sunset"]) and not is_sunset(hour):
			w = 0.0
		out[id] = w
	return out


## Pick a fish from a uniform roll in [0, 1).
static func roll_fish(roll: float, hour: float, river := false, pool := "") -> String:
	var w := fish_weights(hour, river, pool)
	var total := 0.0
	for id: String in FISH_ORDER:
		total += float(w[id])
	var x := clampf(roll, 0.0, 0.999999) * total
	for id: String in FISH_ORDER:
		x -= float(w[id])
		if x < 0.0:
			return id
	return FISH_ORDER[0]


# --- foraging ---------------------------------------------------------------------

## kind -> {item, min, max, days to regrow, model hint}
const FORAGE := {
	"herb": {"item": "healing_herb", "min": 1, "max": 2, "respawn_days": 2, "verb": "Pick herbs"},
	"mushroom": {"item": "mushroom", "min": 1, "max": 3, "respawn_days": 3, "verb": "Pick mushrooms"},
	"berries": {"item": "wild_berries", "min": 2, "max": 4, "respawn_days": 3, "verb": "Pick berries"},
	"firewood": {"item": "firewood", "min": 1, "max": 2, "respawn_days": 1, "verb": "Gather firewood"},
}
## Archetype tags recorded per forage kind (scripts/sim/archetypes.gd).
const FORAGE_TAGS := {"herb": "gathered_herbs", "mushroom": "explored_forest", "berries": "gathered_herbs",
	"firewood": "chopped_wood"}


## What grows at a spot: forest floors give mushrooms, firewood and herbs;
## open meadows give berries and herbs. `roll` is uniform in [0, 1).
static func forage_kind(forest: float, roll: float) -> String:
	if forest >= 0.35:
		return "mushroom" if roll < 0.38 else ("firewood" if roll < 0.72 else "herb")
	return "berries" if roll < 0.55 else "herb"


# --- registration -----------------------------------------------------------------

## Adds the prototypes and market goods. Safe to call any number of times.
static func register(life: Node) -> void:
	if life == null:
		return
	ItemsDB.register(life)        # the Region 1 item set (data/items/*.json) rides along: Life already calls this at boot
	var inv: Variant = life.get("inventory")
	if inv != null and inv.protoset != null:
		var json: JSON = inv.protoset
		var tree: Variant = inv.get_prototree()
		var data: Variant = json.data
		for id: String in ITEMS:
			var entry: Dictionary = ITEMS[id]
			if data is Dictionary and not (data as Dictionary).has(id):
				(data as Dictionary)[id] = entry.duplicate()
			if tree.has_prototype(id):
				continue
			var base: String = entry.get("inherits", "")
			var parent: Variant = tree.get_prototype(base) if base != "" and tree.has_prototype(base) else tree.get_root()
			var proto: Variant = parent.inherit(id)
			for key: String in entry:
				if key != "inherits":
					proto.set_property(key, entry[key])
	var market: Variant = life.get("market")
	if market != null:
		for id: String in MARKET:
			if not market.base_price.has(id):
				var m: Array = MARKET[id]
				market.add_good(id, int(m[0]), int(m[1]), int(m[2]))


## Gives a kill's drops. Returns "+1 Venison, +1 Deer Hide" (empty if none).
static func give_drops(life: Node, kind: String) -> String:
	var parts := PackedStringArray()
	for pair: Array in drops_for(kind):
		life.give(String(pair[0]), int(pair[1]))
		parts.append("+%d %s" % [int(pair[1]), life.item_name(String(pair[0]))])
	return ", ".join(parts)
