extends RefCounted
## Items that only dungeons hand out (crystals, pearls, relics, torches, boss trophies), added to the live
## GLoot protoset at runtime so data/items.json stays untouched (same pattern as sim/gathering_items.gd).
## register(Life) is idempotent; dungeon_thing.gd calls it right before it gives anything.

const ITEMS := {
	"glowcap": {"name": "Glowcap Mushroom", "category": "material", "price": 6, "max_stack_size": 20, "description": "A faintly luminous cave mushroom. Alchemists pay well for it."},
	"cave_pearl": {"name": "Cave Pearl", "category": "material", "price": 18, "max_stack_size": 10, "description": "A pale pearl grown in still underground water."},
	"rift_crystal": {"name": "Rift Crystal", "category": "material", "price": 30, "max_stack_size": 10, "description": "Violet crystal that hums near the Rift. Warm to the touch."},
	"silver_ore": {"name": "Silver Ore", "category": "ore", "price": 14, "max_stack_size": 30, "description": "Bright veins in grey rock. Smelt it with coal."},
	"old_relic": {"name": "Old Relic", "category": "material", "price": 70, "max_stack_size": 5, "description": "A worn keepsake from before the stones were raised."},
	"ancient_coin": {"name": "Ancient Coin", "category": "material", "price": 25, "max_stack_size": 20, "description": "Stamped with a crown no chronicle remembers."},
	"torch": {"name": "Torch", "category": "tool", "price": 3, "max_stack_size": 5, "description": "Carry one into a dark cave and you can see ten paces."},
	"trophy_bear_claw": {"name": "Den Bear's Claw", "category": "trophy", "price": 90, "max_stack_size": 1, "description": "Proof you faced Hollowback in her den."},
	"trophy_toad_crown": {"name": "Mere King's Crown", "category": "trophy", "price": 90, "max_stack_size": 1, "description": "A ring of pearls still wet with cave water."},
	"trophy_shard_heart": {"name": "Shard Heart", "category": "trophy", "price": 130, "max_stack_size": 1, "description": "A violet crystal that beats slowly."},
	"trophy_brute_cap": {"name": "Gorm's Blackcap", "category": "trophy", "price": 100, "max_stack_size": 1, "description": "The foreman's hard hat, dented by a hundred falls."},
	"trophy_ash_hand_seal": {"name": "Ash Hand Seal", "category": "trophy", "price": 110, "max_stack_size": 1, "description": "Captain Verrick's signet. Bandits know it on sight."},
	"trophy_goblin_crown": {"name": "Tunnel King's Crown", "category": "trophy", "price": 80, "max_stack_size": 1, "description": "Hammered tin and bent spoons, worn with great pride."},
	"trophy_warden_seal": {"name": "Barrow Warden's Seal", "category": "trophy", "price": 140, "max_stack_size": 1, "description": "Stone stamped with the first wardens' mark."},
}
const MARKET := {
	"glowcap": [6, 6, 0], "cave_pearl": [18, 2, 0], "rift_crystal": [30, 2, 0], "silver_ore": [14, 4, 0],
	"torch": [3, 10, 2], "ancient_coin": [25, 2, 0], "old_relic": [70, 1, 0],
}

## Which item a resource node kind yields.
const NODE_ITEM := {
	"glowcap": "glowcap", "healing_herb": "healing_herb", "coal": "coal", "cave_pearl": "cave_pearl", "rift_crystal": "rift_crystal",
	"iron_ore": "iron_ore", "copper_ore": "copper_ore", "silver_ore": "silver_ore",
}


static func register(life: Node) -> void:
	if life == null:
		return
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
			var proto: Variant = tree.get_root().inherit(id)
			for key: String in entry:
				proto.set_property(key, entry[key])
	var market: Variant = life.get("market")
	if market != null:
		for id: String in MARKET:
			if not market.base_price.has(id):
				var m: Array = MARKET[id]
				market.add_good(id, int(m[0]), int(m[1]), int(m[2]))
