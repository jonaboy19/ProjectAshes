extends Node
## Builds a pack, gear and shelves, then saves the inventory, character, shop and crafting screens.
const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
const ShopScreen := preload("res://scripts/ui/shop_screen.gd")
const CraftingScreen := preload("res://scripts/ui/crafting_screen.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const RAMarket := preload("res://scripts/sim/market.gd")

var out_dir := "/tmp/claude-0/shots/items"
var hud: CanvasLayer
var frame := 0
var started := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	hud = CanvasLayer.new()
	hud.layer = 10
	get_tree().root.add_child.call_deferred(hud)


func _process(_dt: float) -> void:
	frame += 1
	if frame == 90 and not started:
		started = true
		_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await _wait(8)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [out_dir, name]
	img.save_png(p)
	print("SAVED ", p, " ", img.get_size())


func _run() -> void:
	ItemsDB.register(Life)
	Game.gold = 640
	# A pack with a bit of everything.
	for id in ["steel_sword", "finesteel_greatsword", "yew_longbow", "spiritwood_staff", "iron_axe", "bronze_mace", "rift_dagger", "iron_spear", "oak_placeholder",
			"hardened_cuirass", "knight_helm", "sage_robe", "enchanter_hat", "steelmail_hauberk", "bearhide_cloak" if false else "bearhide_mantle", "ring_might_2", "amulet_focus_3", "talisman_spirit_jade",
			"greater_healing_potion", "qi_draught", "pill_foundation", "elixir_might", "roast_chicken", "meat_pie", "red_wine", "green_tea", "steamed_buns", "hardtack",
			"steel_ingot", "spirit_iron_ore", "troll_hide", "wyvern_scale", "beast_core", "rift_crystal", "moonpetal", "spirit_ginseng", "ruby",
			"manual_swordsmanship_t3", "scroll_chain_lightning", "steel_pickaxe", "iron_felling_axe" if false else "steel_felling_axe", "fine_bait", "oathblade_of_caldrenn", "mantle_of_ash",
			"key_crypt", "sealed_letter", "chair_carved", "seed_pumpkin"]:
		if Crafting.item_exists(id):
			Life.give(id, 3 if ItemsDB.info(id).get("max_stack_size", 1) > 1 else 1)
	Life.give("bread", 4)
	Life.give("stew", 2)
	for id in ["iron_helm", "leather_jerkin", "steelmail_chausses", "riftplate_sabatons", "mantle_of_ash", "ring_might_2", "amulet_focus_3", "iron_sword"]:
		Life.equipment.equip(id, 1)
	Life.equipment.equip("wooden_shield", 1)
	await _wait(10)
	var menu: Control = GameMenu.open(hud, "inventory")
	await _wait(10)
	var page: Control = menu.get("_pages")["inventory"]
	page.set("_sel", {"id": "steel_sword", "quality": 1})
	page.call("refresh")
	await _save("inventory_weapon")
	page.set("_sel", {"id": "greater_healing_potion", "quality": 1})
	page.set("_cat", "consumables")
	page.call("refresh")
	await _save("inventory_consumable")
	menu.call("open_tab", "character")
	await _wait(10)
	await _save("character_doll")
	menu.call("close")
	await _wait(5)
	# Shops: Ashford-tier and capital-tier shelves.
	var town := RAMarket.new()
	town.purse = 900
	ItemsDB.stock_settlement(town, "castle", 1500, [], 3)
	ShopScreen.open_for(hud, "blacksmith", town, 3, "Kingsreach Smithy")
	await _wait(10)
	await _save("shop_blacksmith")
	var shop: Control = hud.get_node("ShopScreen")
	shop.set("_cat", "armor")
	shop.call("open", "armourer", town, 3, "Kingsreach Armourer")
	shop.set("_sel", "knight_cuirass")
	shop.call("refresh")
	await _save("shop_armourer")
	shop.call("open", "alchemist", town, 3, "Kingsreach Alchemist")
	await _wait(5)
	await _save("shop_alchemist")
	shop.call("close_screen")
	await _wait(5)
	# Crafting menus.
	for sk in ["smithing", "cooking", "alchemy", "tailoring", "baking", "leatherwork", "jewelry", "carpentry", "brewing", "fletching"]:
		Life.crafting.add_xp(sk, 400)
	for id in ["iron_ingot", "bronze_ingot", "steel_ingot", "leather", "hardened_leather", "coal", "plank", "oak_plank", "iron_ore", "rivets", "flux", "tin_ore", "silver_ingot", "garnet",
			"healing_herb", "yarrow", "bloodmoss", "sunroot", "empty_vial", "flour", "butter", "egg", "salt", "onion", "mutton", "carrot", "thyme", "linen_cloth", "silk_thread", "wool_thread"]:
		Life.give(id, 12)
	CraftingScreen.open_for(hud, ["anvil"], "Kingsreach Smithy")
	await _wait(10)
	var cs: Control = hud.get_node("CraftingScreen")
	cs.set("_recipe", "steel_sword")
	cs.call("refresh")
	await _save("crafting_smithing")
	cs.call("open", ["hearth"], "Inn Hearth")
	await _wait(5)
	await _save("crafting_cooking")
	cs.call("open", ["alchemy_table"], "Healer's Table")
	await _wait(5)
	await _save("crafting_alchemy")
	get_tree().quit()
