class_name VillageServices
extends Node3D
## The starting village's places to live a life: the market stall, the inn,
## the notice board (jobs with real vacancies) and the Captain's office.
## Each is a Station whose menu reads and drives the Life autoload.
## Keepers stand beside their building's entrance (never on the door line), and
## the same menus are offered inside: wire_settlement() hooks every InteriorDoor
## so the innkeeper, smith, receptionist and healer in a room get a Station.

const FarmLedger := preload("res://scripts/ui/farm_ledger.gd")
const TradeScreen := preload("res://scripts/ui/trade_screen.gd")
const CraftingScreen := preload("res://scripts/ui/crafting_screen.gd")
const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const BuildMenu := preload("res://scripts/ui/build_menu.gd")
const CareerScreen := preload("res://scripts/ui/career_screen.gd")
const SaveScreen := preload("res://scripts/ui/save_screen.gd")
const NobilityScreen := preload("res://scripts/ui/nobility_screen.gd")
const ChronicleScreen := preload("res://scripts/ui/chronicle_screen.gd")
const FamilyScreen := preload("res://scripts/ui/family_screen.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const RAProperty := preload("res://scripts/sim/property.gd")
const MEGAKIT := "res://assets/incoming/quaternius/fantasy-props-megakit/Exports/glTF/"
const BOARD := "res://assets/generated/notice_board.glb"
const BED_PRICE := 3
const Relationships := preload("res://scripts/sim/relationships.gd")
const RadiantQuests := preload("res://scripts/sim/radiant_quests.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const TalkTarget := preload("res://scripts/world/talk_target.gd")
const QUEST_SEED := 1066 * 31
const SOCIAL_TICK := 0.5
## Service keepers you can talk to: id -> [role, dialogue file, radiant giver role].
const KEEPERS := {
	"innkeeper": ["innkeeper", "innkeeper", "villager"],
	"receptionist": ["receptionist", "guild", "guild"],
	"herbalist": ["healer", "villager", "healer"],
	"trader": ["trader", "villager", "villager"],
	"smith": ["blacksmith", "villager", ""],
}

var hud: HUD
var guild_station: Station
var captain: Captain
var soldiers: Callable      # () -> int, current company size
var recruit: Callable       # (count) -> void
var talk_target: Node3D
## Used until Life owns `relationships` / `radiant` (see relationships()).
var _rel_local: Relationships = Relationships.new()
var _radiant_local: RadiantQuests = RadiantQuests.new()
## The conversation on screen: {id, info, file, node, line, hint_id}.
var _talk: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _social_timer := 0.0
var _last_day := -999
var _last_quest_day := -999
var _weather: Node
var _weather_search := 0.0
var _gossip: Dictionary = {}
var _keeper_pos: Dictionary = {}     # keeper id -> Vector2 (where to report back)


func setup(p_hud: HUD, p_captain: Captain, p_soldiers: Callable, p_recruit: Callable) -> void:
	hud = p_hud
	captain = p_captain
	soldiers = p_soldiers
	recruit = p_recruit


func _ready() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var plan: Dictionary = home["plan"]
	var pr: float = plan["plaza_r"]
	# Merchant in front of the first plaza stall (see SettlementBuilder).
	var ang := 0.2
	var stall := c + Vector2(cos(ang), sin(ang)) * (pr - 4.6)
	_person("Market Trader", "Trade", merchant_menu, stall, c, "Trader")
	_prop("Barrel_Apples", stall + Vector2(-sin(ang), cos(ang)) * 1.6, 1.0)
	_prop("FarmCrate_Apple", stall + Vector2(sin(ang), -cos(ang)) * 1.5, 1.0)
	# Innkeeper beside the inn's entrance, clear of the InteriorDoor (he is also
	# behind the bar inside). The door threshold is BuildingProfiles.door_point.
	for lot: Dictionary in plan["lots"]:
		if lot["asset"] == "inn":
			var yaw: float = lot["yaw"]
			var at := BuildingProfiles.keeper_point(lot, 1.0)
			_person("%s Inn" % home["name"], "Food & bed", inn_menu, at, at + Vector2(sin(yaw), cos(yaw)), "Innkeeper")
			_keeper_pos["innkeeper"] = at
			break
	# Adventurer Guild receptionist and the herbalist beside their buildings'
	# entrances (CityPlanner puts both on the lots nearest the plaza).
	var guild_at := c + Vector2(-4.0, -9.0)
	var herb_at := c + Vector2(9.0, -7.5)
	var guild_face := c
	var herb_face := c
	for lot: Dictionary in plan["lots"]:
		var yaw: float = lot["yaw"]
		var out := Vector2(sin(yaw), cos(yaw))
		if lot["asset"] == "adventurer_guild":
			guild_at = BuildingProfiles.keeper_point(lot, -1.0)    # the board takes the other side
			guild_face = guild_at + out
			_prop_gen("guild_board", lot["pos"] + out * 6.2 + Vector2(out.y, -out.x) * 3.2, yaw)
		elif lot["asset"] == "healer_house":
			herb_at = BuildingProfiles.keeper_point(lot, 1.0)
			herb_face = herb_at + out
	guild_station = _person("Adventurer Guild", "Guild", guild_menu, guild_at, guild_face, "Rogue_Hooded")
	_person("Herbalist", "Healer", healer_menu, herb_at, herb_face, "Herbalist")
	# Notice board beside the well, facing the spawn road.
	var board_pos := c + Vector2(3.5, -3.0)
	var board := Station.new("Notice Board", "Read", notice_menu)
	add_child(board)
	board.global_position = _ground(board_pos)
	var model: Node3D = Assets.scene(BOARD).instantiate()
	board.add_child(model)
	board.look_at(_ground(board_pos + Vector2(-1.0, 3.0)), Vector3.UP, true)
	board.rotate_y(PI)
	# People: one "Talk" interactable that follows the nearest villager.
	_rng.seed = WorldSim.SEED + 99
	relationships().add_sects(Life.lore.sects)
	talk_target = TalkTarget.new(hud, talk_menu)
	add_child(talk_target)
	# Compass / map marker for the tracked radiant quest (HUD asks active_objective_position()).
	if hud and "quest_source" in hud and hud.get("quest_source") == null:
		hud.set("quest_source", self)
	_keeper_pos["receptionist"] = guild_at
	_keeper_pos["herbalist"] = herb_at
	_keeper_pos["trader"] = stall


# --- interiors -------------------------------------------------------------------

## Hooks the InteriorDoors a SettlementBuilder made under `root` (a settlement
## root with a "Doors" child, or the builder itself) so their rooms' keepers get
## menus. Safe to call again for the same doors.
func wire_settlement(root: Node) -> void:
	var holder := root.get_node_or_null("Doors")
	if holder == null:
		for child in root.get_children():
			if child.get_node_or_null("Doors") != null:
				wire_settlement(child)
		return
	for d in holder.get_children():
		var door := d as InteriorDoor
		if door and not door.is_exit and not door.interior_entered.is_connected(_on_interior_entered):
			door.interior_entered.connect(_on_interior_entered.bind(door))


## Role (NPC marker metadata) -> [title, verb, menu].
func _role_service(role: String) -> Array:
	match role:
		"innkeeper":
			return ["Innkeeper", "Food & bed", inn_menu]
		"blacksmith":
			return ["Blacksmith", "Talk", smith_menu]
		"receptionist":
			return ["Guild Receptionist", "Guild", guild_menu]
		"healer":
			return ["Healer", "Healer", healer_menu]
	return []


## A room was loaded: put a Station on each service NPC's marker. The markers
## exist right away (the NPC models spawn a frame later), and the Stations are
## children of the room, so they are freed with it. `door` (the InteriorDoor
## that loaded this room) is used to spot the player's own home: a house lot
## they own or rent gets a storage chest and, on a bed marker, a place to sleep.
func _on_interior_entered(room: Node3D, door: InteriorDoor = null) -> void:
	Life.crafting.scan_interior(room)
	for m in room.find_children("NPC_*", "Marker3D", true, false):
		var svc := _role_service(String(m.get_meta("role", "")))
		if svc.is_empty():
			continue
		var st := Station.new(svc[0], svc[1], svc[2])
		st.name = "Service_" + String(m.name).trim_prefix("NPC_")
		room.add_child(st)
		st.global_position = (m as Marker3D).global_position
	if door and door.has_meta("lot_pos"):
		var lot_id: String = Life.property.find_by_pos(door.get_meta("lot_pos"))
		if lot_id != "" and Life.property.is_held(lot_id):
			_furnish_home(room, lot_id)


const HomeChest := preload("res://scripts/world/home_chest.gd")

## Puts a storage chest (if the property has one, i.e. it isn't a bare inn
## room) and, on a "BedSpawn" marker, a free "Sleep" station and sets the
## respawn point there.
func _furnish_home(room: Node3D, lot_id: String) -> void:
	var spawn := room.find_child("PlayerSpawn", true, false) as Node3D
	var origin := spawn.global_position if spawn else room.global_position
	if Life.property.can_store(lot_id):
		var chest := HomeChest.new()
		chest.lot_id = lot_id
		room.add_child(chest)
		var marker := room.find_child("StorageMarker", true, false) as Node3D
		chest.global_position = marker.global_position if marker else origin + Vector3(1.4, 0, 1.4)
	var bed := room.find_child("BedSpawn", true, false) as Node3D
	if bed:
		var st := Station.new("Bed", "Sleep", func() -> Dictionary:
			return {"title": "Your bed", "body": "It's yours; sleeping here costs nothing.",
				"options": [["Sleep", _sleep_at_home.bind(bed.global_position)]]})
		room.add_child(st)
		st.global_position = bed.global_position


## Sleeping in your own bed is free and sets it as your respawn point
## (player.gd's `spawn_point`, read back on death — main.gd sets it once at
## world start, then whatever last set it holds).
func _sleep_at_home(spawn_pos: Vector3) -> String:
	hud.close_menu()
	if Life.player and is_instance_valid(Life.player) and "spawn_point" in Life.player:
		Life.player.spawn_point = spawn_pos
	return Life.sleep(1.0)


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _person(title: String, verb: String, menu: Callable, at: Vector2, face: Vector2, look: String) -> Station:
	var st := Station.new(title, verb, menu)
	add_child(st)
	st.global_position = _ground(at)
	var body := Assets.character(look, 1.74, [])
	st.add_child(body)
	var anim := Assets.animation_player(body)
	if anim:
		anim.play("Idle" if anim.has_animation("Idle") else anim.get_animation_list()[0])
	var to := face - at
	st.rotation.y = atan2(to.x, to.y)
	return st


func _prop_gen(asset: String, at: Vector2, yaw: float) -> void:
	var path := "res://assets/generated/%s.glb" % asset
	if not ResourceLoader.exists(path):
		return
	var n: Node3D = Assets.scene(path).instantiate()
	add_child(n)
	n.global_position = _ground(at)
	n.rotation.y = yaw


func _prop(item: String, at: Vector2, scale_by: float) -> void:
	var path := MEGAKIT + item + ".gltf"
	if not ResourceLoader.exists(path):
		return
	var scene := Assets.scene(path)
	if scene == null:   # exists but failed to load (e.g. not imported): skip instead of erroring every boot
		return
	var n: Node3D = scene.instantiate()
	n.scale = Vector3.ONE * scale_by
	add_child(n)
	n.global_position = _ground(at)
	n.rotation.y = randf() * TAU


# --- menus ---------------------------------------------------------------------

func merchant_menu() -> Dictionary:
	var m := Life.market
	var opts: Array = []
	for item: String in ["bread", "apple", "cheese", "bandage", "firewood"]:
		opts.append(["Buy %s  —  %dg  (%d in stock)" % [Life.item_name(item), m.price(item), m.stock[item]],
			Life.buy.bind(item), m.can_buy(item, Game.gold) == ""])
	for item: String in ["wolf_pelt", "wolf_meat", "firewood"]:
		var n := Life.count(item)
		if n > 0:
			opts.append(["Sell %s ×%d  —  %dg each" % [Life.item_name(item), n, m.sell_price(item)],
				Life.sell.bind(item), m.purse >= m.sell_price(item)])
	opts.append(["Trade routes & caravans", TradeScreen.open_for.bind(hud), true])
	opts.append(_talk_option("trader"))
	return {"title": "Market Trader",
		"body": "\"Fresh from the farms. Pelts wanted: the tanner's short.\"\nYou carry %d gold. Trader's purse: %d gold." % [Game.gold, m.purse],
		"options": opts}


func inn_menu() -> Dictionary:
	var n := Life.needs
	var opts: Array = [
		["Hot stew  —  %dg" % Life.market.price("stew"), _buy_stew, Life.market.can_buy("stew", Game.gold) == ""],
		["Rent a bed and sleep  —  %dg" % BED_PRICE, _rent_bed, Game.gold >= BED_PRICE and n.rest < 90.0],
	]
	if Life.property.has_inn_room(0):
		var room_rent := int(Life.property.info(Life.property.inn_room_id(0))["rent"])
		opts.append(["Rent a room for a week  —  %dg" % room_rent, _rent_room, Game.gold >= room_rent])
	var server := Life.careers.seat("inn", "Server")
	if not Life.careers.is_employed() and Life.careers.open_count(server) > 0:
		opts.append(["Ask for work as a Server (%dg/day)" % server["wage"], _apply.bind("inn", "Server")])
	opts.append(CraftingScreen.menu_option(hud, ["hearth"], "Cook at the hearth", "Inn Hearth"))
	opts.append(_talk_option("innkeeper"))
	return {"title": "%s Inn" % WorldGen.settlements[0]["name"],
		"body": "The common room smells of smoke and onions.\nYou are %s and %s. It is %02d:00." % [
			n.hunger_label().to_lower(), n.rest_label().to_lower(), int(WorldSim.time_of_day)],
		"options": opts}


## The smithy: no smith goods in the market yet, so the smith takes firewood for
## the forge and hires apprentices (the "smithy" org in Life).
func smith_menu() -> Dictionary:
	var m := Life.market
	var opts: Array = []
	var wood := Life.count("firewood")
	if wood > 0:
		opts.append(["Sell firewood for the forge ×%d  —  %dg each" % [wood, m.sell_price("firewood")],
			Life.sell.bind("firewood"), m.purse >= m.sell_price("firewood")])
	if not Life.careers.is_employed():
		for title: String in ["Apprentice", "Journeyman"]:
			var s := Life.careers.seat("smithy", title)
			if not s.is_empty() and Life.careers.open_count(s) > 0:
				var why := Life.careers.check_application("smithy", title, Game.merit)
				opts.append(["Ask for work as a %s (%dg/day)" % [title, s["wage"]], _apply.bind("smithy", title), why == ""])
	var body := "The forge roars; the smith doesn't look up from the anvil.\n\"Wood for the fire, or a strong back. Nothing else I need today.\""
	if opts.is_empty():
		body += "\nYou have nothing the smith wants."
	opts.append(CraftingScreen.menu_option(hud, ["anvil", "workbench"], "Work the anvil & bench", "Smithy"))
	opts.append(_talk_option("smith"))
	return {"title": "Blacksmith", "body": body, "options": opts}


func _buy_stew() -> String:
	var msg := Life.buy("stew")
	return Life.use_item("stew") if msg.begins_with("Bought") else msg


func _rent_bed() -> String:
	Game.add_gold(-BED_PRICE)
	hud.close_menu()
	return Life.sleep(1.0)


func _rent_room() -> String:
	return Life.property.rent_room(0, 1)


func notice_menu() -> Dictionary:
	var lines := PackedStringArray()
	var opts: Array = []
	for o in Life.careers.orgs:
		var sh: Vector2 = o["shift"]
		var parts := PackedStringArray()
		for s: Dictionary in o["seats"]:
			parts.append("%s %d/%d" % [s["title"], s["holders"].size(), s["count"]])
		lines.append("%s  (%02d:00–%02d:00):  %s" % [String(o["name"]).capitalize(), int(sh.x), int(sh.y), ", ".join(parts)])
		for v: Dictionary in Life.careers.vacancies(o["id"]):
			var s: Dictionary = v["seat"]
			if o["id"] == "guard":
				continue
			var why := Life.careers.check_application(o["id"], s["title"], Game.merit)
			opts.append(["Apply: %s, %s  —  %dg/day  (%d open)" % [s["title"], o["name"], s["wage"], v["open"]],
				_apply.bind(o["id"], s["title"]), why == ""])
	var guard := Life.careers.seat("guard", "Guard")
	if Life.careers.open_count(guard) > 0:
		lines.append("\nThe Guard is hiring: %d posts open. See the Captain of the Guard." % Life.careers.open_count(guard))
	for i in Life.homestead.plots().size():
		if Life.homestead.is_owned(i):
			continue
		var price := int(Life.homestead.plots()[i]["price"])
		opts.append(["Buy homestead plot %d (%dg)" % [i + 1, price], Life.homestead.buy.bind(i), Game.gold >= price])
	lines.append_array(_notice_houses(opts))
	return {"title": "Notice Board", "body": "\n".join(lines), "options": opts}


## Houses for sale / rent in the home town: every currently-vacant house lot,
## with price, weekly rent and seasonal land tax. Returns the lines to show
## (PackedStringArray is a value type in GDScript, so this can't mutate a
## caller's array directly); `opts` (a reference type) is appended to in place.
func _notice_houses(opts: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	var town := String(WorldGen.settlements[0]["name"])
	var ids: Array[String] = Life.property.available(0)
	if ids.is_empty():
		return lines
	lines.append("\nHouses for sale / rent in %s:" % town)
	for lot_id: String in ids:
		var i: Dictionary = Life.property.info(lot_id)
		lines.append("  %s  —  buy %dg, rent %dg/week, land tax %dg/season (owed to %s)" %
			[String(i["name"]), int(i["price"]), int(i["rent"]), int(i["tax"]), String(i["landlord_id"])])
		opts.append(["Buy %s (%dg)" % [String(i["name"]).to_lower(), int(i["price"])],
			Life.property.buy.bind(lot_id), Game.gold >= int(i["price"])])
		opts.append(["Rent %s for a week (%dg)" % [String(i["name"]).to_lower(), int(i["rent"])],
			Life.property.rent.bind(lot_id, 1), Game.gold >= int(i["rent"])])
	return lines


func _apply(org_id: String, title: String) -> String:
	if not Life.is_adult() and org_id != "inn":
		return "\"Come back when you're grown, little one.\" (age %d of %d)" % [Life.age(), Life.ADULT_AGE]
	var why := Life.careers.apply(org_id, title, Game.merit, WorldSim.day)
	return why


func captain_menu() -> Dictionary:
	var c := Life.careers
	var o := c.org("guard")
	var parts := PackedStringArray()
	for s: Dictionary in o["seats"]:
		parts.append("%s %d/%d (%dg)" % [s["title"], s["holders"].size(), s["count"], s["wage"]])
	var in_guard: bool = c.is_employed() and c.player["org"] == "guard"
	var opts: Array = []
	if not in_guard:
		var why := c.check_application("guard", "Guard", Game.merit)
		opts.append(["Enlist as a Guard" if why == "" else "Enlist (no post open)", _enlist, why == ""])
	else:
		var up := c.promotion_for_player(Game.merit)
		if not up.is_empty():
			opts.append(["Take the open %s's seat" % up["title"], _apply.bind("guard", up["title"])])
		var room := Game.max_soldiers() - int(soldiers.call())
		opts.append(["Hire soldiers (%dg each)" % Game.RECRUIT_COST, _hire.bind(room), room > 0])
		opts.append(["Resign from the Guard", _resign])
	var body := "%s: %s.\nWatch from %02d:00 to %02d:00 on the walls and ring stones. Miss %d shifts and you're out." % [
		String(o["name"]).capitalize(), ", ".join(parts), int(o["shift"].x), int(o["shift"].y), RACareers.STRIKES_TO_DISMISS]
	if in_guard:
		body += "\nYou: %s, %d merit, %d strike(s)." % [c.player["seat"], Game.merit, c.player["strikes"]]
	return {"title": "Captain of the Guard", "body": body, "options": opts}


func _hire(room: int) -> String:
	var k := mini(room, mini(6, Game.gold / Game.RECRUIT_COST))
	if k <= 0:
		return "No room in your company or no coin."
	Game.add_gold(-k * Game.RECRUIT_COST)
	recruit.call(k)
	return "%d recruits join your company." % k


func _resign() -> String:
	Life.careers.resign()
	return ""


func _enlist() -> String:
	if not Life.is_adult():
		return "\"The Guard takes no children. Grow strong, and come back at %d.\"" % Life.ADULT_AGE
	var why := Life.careers.apply("guard", "Guard", Game.merit, WorldSim.day)
	if why != "":
		return why
	if Game.rank == 0:
		Game.promote()
		recruit.call(Game.max_soldiers())
	hud.close_menu()
	return "\"Welcome to the Guard. Take a patrol of twelve. Raiders camp in the eastern woods, wolves in the pines.\""


func pack_menu() -> Dictionary:
	var c := Life.careers
	var n := Life.needs
	var lines := PackedStringArray()
	if c.is_employed():
		var sh: Vector2 = c.player_org()["shift"]
		lines.append("%s, %s. Shift %02d–%02d. Today %.1f h on duty. Strikes %d/%d." % [c.player["seat"], c.player_org()["name"],
			int(sh.x), int(sh.y), c.player["attended"], c.player["strikes"], RACareers.STRIKES_TO_DISMISS])
	else:
		lines.append("No employment. The notice board lists open posts.")
	lines.append("%s, age %d (%s).  Build: %s" % [Life.life_path.full_name(), Life.age(),
		Life.life_path.stage_name(WorldSim.day, WorldSim.time_of_day), Life.build_summary()])
	var shown := PackedStringArray()
	for t: Dictionary in Life.titles.earned_list():
		shown.append(String(t.get("name", t.get("id", ""))))
	if not shown.is_empty():
		lines.append("Titles: " + ", ".join(shown))
	lines.append("Food %d  ·  Rest %d  ·  Gold %d  ·  Merit %d" % [int(n.food), int(n.rest), Game.gold, Game.merit])
	var items := PackedStringArray()
	var opts: Array = []
	opts.append(["Inventory & equipment", func() -> String:
		hud.close_menu()
		InventoryScreen.open_for(hud)
		return ""])
	opts.append(["Crafting", func() -> String:
		hud.close_menu()
		CraftingScreen.open_for(hud)
		return ""])
	opts.append(["Arts & cultivation", func() -> String:
		hud.close_menu()
		hud.skills_screen.open()
		return ""])
	opts.append(["Photo mode", func() -> String:
		hud.close_menu()
		hud.open_photo_mode()
		return ""])
	opts.append(["Career & life", func() -> String:
		hud.close_menu()
		CareerScreen.open_for(hud)
		return ""])
	opts.append(["Nobility", func() -> String:
		hud.close_menu()
		NobilityScreen.open_for(hud)
		return ""])
	opts.append(["Chronicle", func() -> String:
		hud.close_menu()
		ChronicleScreen.open_for(hud)
		return ""])
	if Life.get("family") != null:
		opts.append(["Family", func() -> String:
			hud.close_menu()
			FamilyScreen.open_for(hud)
			return ""])
	var homestead_plot := Life.homestead.plot_at(_player_pos())
	if homestead_plot >= 0:
		opts.append([("Build on your homestead" if Life.homestead.owns_or_leases(homestead_plot) else "Buy or lease this plot"), func() -> String:
			hud.close_menu()
			BuildMenu.open_for(hud)
			return ""])
	if not Life.homestead.owned.is_empty() or not Life.homestead.leased.is_empty():
		opts.append(["Farm ledger", func() -> String:
			hud.close_menu()
			FarmLedger.open_for(hud)
			return ""])
	opts.append(["Save / Load", func() -> String:
		hud.close_menu()
		SaveScreen.open_for(hud)
		return ""])
	var seen := {}
	for it in Life.inventory.get_items():
		var id := it.get_prototype().get_prototype_id()
		if seen.has(id):
			continue
		seen[id] = true
		items.append("%s ×%d" % [Life.item_name(id), Life.count(id)])
		if float(it.get_property("nutrition", 0.0)) > 0.0 or int(it.get_property("heal", 0)) > 0:
			opts.append(["Use %s" % Life.item_name(id), Life.use_item.bind(id)])
	lines.append("Pack: " + (", ".join(items) if not items.is_empty() else "empty"))
	for e: Dictionary in Life.pending_offers:
		var eid := int(e["id"])
		var offer: Dictionary = e.get("offer", {})
		lines.append("Offer: %s (%s) wants you as %s." % [e["scout"].get("name", "?"), e["org"].get("name", "?"), offer.get("role", "recruit")])
		opts.append(["Accept offer from %s" % e["org"].get("name", "?"), Life.answer_offer.bind(eid, true)])
		opts.append(["Decline offer from %s" % e["org"].get("name", "?"), Life.answer_offer.bind(eid, false)])
	var inj := PackedStringArray()
	for i: Dictionary in Life.injuries.active:
		inj.append(Life.injuries.label(i))
	if not inj.is_empty():
		lines.append("Injuries: " + ", ".join(inj))
	lines.append("Magicules %d / %d" % [int(Life.magicules.current), int(Life.magicules.effective_max())])
	var jl: PackedStringArray = radiant().journal_lines()
	if not jl.is_empty():
		lines.append("Quests:\n  " + "\n  ".join(jl))
	opts.append(["People & reputation", func() -> String:
		hud.show_menu(people_menu)
		return ""])
	if not Life.property.owned().is_empty() or not Life.property.rented().is_empty():
		opts.append(["Your properties", func() -> String:
			hud.show_menu(properties_menu)
			return ""])
	if radiant().active.size() > 1:
		opts.append(["Track next quest", func() -> String:
			return _track_next()])
	opts.append(["Sleep rough here", _sleep_rough, n.rest < 80.0])
	opts.append(["Save game", _save])
	opts.append(["Load game", _load, Life.has_save()])
	opts.append(["Settings & Credits", func() -> String:
		hud.show_menu(SettingsMenu.menu.bind(hud))
		return ""])
	return {"title": "Pack & Journal", "body": "\n".join(lines), "options": opts}


func _sleep_rough() -> String:
	hud.close_menu()
	return Life.sleep(0.55)


func _save() -> String:
	return "Game saved." if Life.save_game() else "Could not save."


func _load() -> String:
	hud.close_menu()
	return "Game loaded." if Life.load_game() else "No save found."


# --- guild & healer ---------------------------------------------------------------

func guild_menu() -> Dictionary:
	var g := Life.guild
	var me := RAAdventurerGuild.PLAYER
	var opts: Array = []
	var body := ""
	if not g.is_member(me):
		body = "\"Welcome to the %s. Membership is %d gold; every adventurer starts at F rank. Commissions pay by rank.\"" % [
			g.branch(0).get("name", "Guild Hall"), RAAdventurerGuild.MEMBERSHIP_FEE]
		opts.append(["Register as an adventurer (%dg)" % RAAdventurerGuild.MEMBERSHIP_FEE, Life.join_guild,
			Game.gold >= RAAdventurerGuild.MEMBERSHIP_FEE])
	else:
		var m := g.member(me)
		var rank := int(m.get("rank", 0))
		var next_pts: int = RAAdventurerGuild.RANK_POINTS[mini(rank + 1, 6)]
		body = "%s-rank adventurer · %d / %d points" % [RAAdventurerGuild.rank_name(rank), int(m.get("points", 0)), next_pts]
		if int(m.get("debt", 0)) > 0:
			body += " · debt %dg" % int(m["debt"])
			opts.append(["Pay guild debt", func() -> String:
				var paid := g.settle_debt(me, Game.gold)
				Game.add_gold(-paid)
				return "Paid %d gold." % paid, Game.gold > 0])
		for c: Dictionary in g.active_for(me):
			var cid := int(c["id"])
			if g.is_ready(cid):
				opts.append(["✔ Turn in: %s  (+%dg)" % [c["title"], c["reward"]], Life.turn_in.bind(cid)])
			else:
				opts.append(["Abandon: %s  (%d/%d)" % [c["title"], c["progress"], c["required"]], func() -> String:
					return String(g.fail(me, cid, WorldSim.day).get("text", ""))])
		for c: Dictionary in g.available_for(me, 0):
			var cid2 := int(c["id"])
			var label := "[%s] %s  —  %dg · %d pts · %d days" % [RAAdventurerGuild.rank_name(int(c["rank"])), c["title"],
				c["reward"], c["points"], int(c["deadline"]) - WorldSim.day]
			if c["type"] == "vacancy":
				var tg: Dictionary = c.get("target", {})
				label = "Job · %s, %s  —  %dg/day · +%d pts when hired" % [tg.get("seat", "?"),
					String(Life.careers.org(String(tg.get("org", ""))).get("name", "")).trim_prefix("the "), int(tg.get("wage", 0)), c["points"]]
			opts.append([label, func() -> String:
				var why := g.accept(me, cid2, WorldSim.day)
				return why if why != "" else "Commission accepted."])
	var open_board := 0
	for c: Dictionary in g.board(0):
		if c["state"] == "open":
			open_board += 1
	body += "\n%d commissions on the board." % open_board
	var rq := radiant()
	var contracts := rq.offers_for("guild", 5).size()
	var reports := rq.ready_for("receptionist", "guild").size()
	if contracts + reports > 0 and g.is_member(me):
		body += "  %d local contract%s posted." % [contracts, "" if contracts == 1 else "s"]
		opts.append(["Local contracts%s" % (("  (%d to report)" % reports) if reports > 0 else ""), func() -> String:
			hud.show_menu(_quest_menu.bind(_keeper_info("receptionist")))
			return ""])
	opts.append(_talk_option("receptionist"))
	return {"title": "Adventurer Guild", "body": body, "options": opts}


func healer_menu() -> Dictionary:
	var opts: Array = []
	var menu := Life.injuries.healer_menu("herbalist")
	for q: Dictionary in menu:
		opts.append(["Treat %s  —  %s" % [q["name"], ("%dg, %dh" % [q["cost"], int(ceil(float(q["hours"])))]) if q["ok"] else "beyond my skill"],
			Life.treat.bind(int(q["uid"]), "herbalist"), bool(q["ok"]) and Game.gold >= int(q["cost"])])
	opts.append(["Buy a linen bandage (%dg)" % Life.market.price("bandage"), Life.buy.bind("bandage"),
		Life.market.can_buy("bandage", Game.gold) == ""])
	var body := "\"Cuts, bites, fevers, I can mend. A cracked soul-core needs a temple, child.\""
	if menu.is_empty():
		body += "\nYou are unhurt."
	var hinfo := _keeper_info("herbalist")
	for q: Dictionary in radiant().ready_for("herbalist", "healer"):
		opts.append(["✔ Hand in: %s" % q["title"], _turn_in.bind(String(q["id"]), hinfo)])
	var herb_jobs := radiant().offers_for("healer", 5)
	if not herb_jobs.is_empty():
		opts.append(["Ask about work (%d)" % herb_jobs.size(), func() -> String:
			hud.show_menu(_quest_menu.bind(hinfo))
			return ""])
	opts.append(CraftingScreen.menu_option(hud, ["alchemy_table"], "Mix remedies at the table", "Healer's Table"))
	opts.append(_talk_option("herbalist"))
	return {"title": "Herbalist", "body": body, "options": opts}


# --- naming ---------------------------------------------------------------------

func naming_menu(m: CampMonster) -> Dictionary:
	if not is_instance_valid(m) or m.dead:
		return {"title": "Gone", "body": "", "options": []}
	var pv := Life.naming.preview(Life.magicules, Life.player_level(), m.species, m.level, Life.injuries)
	if m.get_meta("given", "") == "":
		m.set_meta("given", m.random_name())
	var given: String = m.get_meta("given")
	var risk := float(pv["risk"])
	var body := "A %s (level %d) kneels before you. Name it, and it becomes a %s bound to you.\n" % [m.species, m.level, pv["form"]]
	body += "Cost %d magicules (you have %d / %d)  ·  risk %d%%" % [pv["cost"], int(Life.magicules.current),
		int(Life.magicules.effective_max()), int(risk * 100)]
	if risk > 0.3:
		body += "\nNaming beyond your strength can cost levels or crack your soul-core; only a healer mends that."
	var opts: Array = []
	for k: String in pv["classes"]:
		opts.append(["Name it \"%s\" the %s" % [given, k.capitalize()], _do_name.bind(m, given, k), bool(pv["possible"])])
	opts.append(["Think of another name", func() -> String:
		m.set_meta("given", m.random_name())
		return ""])
	opts.append(["Let it go", func() -> String:
		hud.close_menu()
		m.state = CampMonster.State.WANDER
		m.hostile = false
		m._set_team(false)
		m._refresh_label()
		return "It scrambles back toward its camp."])
	return {"title": "Naming", "body": body, "options": opts}


func _do_name(m: CampMonster, given: String, k: String) -> String:
	hud.close_menu()
	return Life.name_monster(m, given, k)


# --- people: talk, gifts, reputation, radiant quests --------------------------------
# Relationships and radiant quests live on Life once its hooks are in (Life.relationships,
# Life.radiant: saved with the game); until then these fall back to local copies.

func relationships() -> Relationships:
	var r: Variant = Life.get("relationships")
	return r if r != null else _rel_local


func radiant() -> RadiantQuests:
	var r: Variant = Life.get("radiant")
	return r if r != null else _radiant_local


## Where the compass should point for the tracked radiant quest (Vector2 or null).
func active_objective_position() -> Variant:
	return radiant().active_objective_position()


func _now() -> float:
	return WorldSim.day + WorldSim.time_of_day / 24.0


func _home_pos() -> Vector2:
	return WorldGen.settlements[0]["pos"]


func _player_pos() -> Vector2:
	var p: Node3D = Life.player
	if p == null or not is_instance_valid(p):
		return Vector2.INF
	return Vector2(p.global_position.x, p.global_position.z)


func _process(delta: float) -> void:
	_social_timer -= delta
	if _social_timer > 0.0:
		return
	_social_timer = SOCIAL_TICK
	var rq := radiant()
	if WorldSim.day != _last_day:
		_last_day = WorldSim.day
		relationships().prune(_now())
		for e: Dictionary in rq.tick_day(WorldSim.day, world_from_game(), QUEST_SEED):
			Game.say(String(e["text"]))
			_qw_event(&"radiant_failed", e["quest"])
	if rq.active.is_empty():
		return
	for e: Dictionary in rq.update(_quest_ctx()):
		var q: Dictionary = e["quest"]
		match String(e["type"]):
			"complete":
				Game.say("%s  %s" % [e["text"], _pay(q)])
				_qw_event(&"radiant_completed", q)
			"ready":
				Game.say("%s: %s" % [q["title"], e["text"]])
			_:
				Game.say("%s: %s" % [q["title"], e["text"]])


## The live world for radiant quest generation (see RadiantQuests.generate).
func world_from_game() -> Dictionary:
	var dens: Array = []
	for d: Dictionary in Frontier.ecology.dens:
		dens.append({"id": d["id"], "species": d["species"], "pos": d["pos"], "population": d["population"], "alive": d["alive"]})
	var sites: Array = []
	for st: Dictionary in WorldGen.sites:
		sites.append({"name": st["name"], "kind": st["kind"], "pos": st["pos"]})
	var world := {"home": _home_pos(), "dens": dens, "sites": sites, "places": Life.lore.places}
	if Life.career_id != "":
		world["career_rank"] = {"career": Life.career_id, "rank": Life.career_rank}
	world["at_war"] = bool(Life.life_path.flags.get("at_war", false))
	return world


func _quest_ctx() -> Dictionary:
	return {"pos": _player_pos(), "day": _now(), "count_item": Life.count, "den_population": _den_population}


func _den_population(id: int) -> int:
	var dens: Array = Frontier.ecology.dens
	if id < 0 or id >= dens.size() or not dens[id]["alive"]:
		return -1
	return int(dens[id]["population"])


## Pays a finished quest's reward; returns the summary text.
func _pay(q: Dictionary) -> String:
	var r: Dictionary = q.get("reward", {})
	var parts := PackedStringArray()
	var gold := int(r.get("gold", 0))
	if gold > 0:
		Game.add_gold(gold)
		parts.append("+%dg" % gold)
	var rel := relationships()
	var reps: Dictionary = r.get("rep", {})
	for f: String in reps:
		rel.change_rep(f, float(reps[f]))
		parts.append("%s %+d" % [rel.faction_name(f), int(reps[f])])
	var giver := String(q.get("giver", ""))
	if giver != "" and int(r.get("opinion", 0)) != 0:
		rel.add_modifier(giver, "quest", "Did me a good turn", float(r["opinion"]), _now(), 60.0, 3)
	_last_quest_day = WorldSim.day
	Life.record("adventured" if q.get("giver_role", "") == "guild" else "helped_villager", 1.5)
	return "(" + ", ".join(parts) + ")"


func _turn_in(id: String, info: Dictionary) -> String:
	var r: Dictionary = radiant().turn_in(id, Life.count)
	if not r.get("ok", false):
		return String(r.get("text", ""))
	var take: Dictionary = r.get("take", {})
	for item: String in take:
		Life.take(item, int(take[item]))
	var q: Dictionary = r["quest"]
	Audio.play_ui("quest_complete")
	if String(q.get("giver", "")) == "":
		q["giver"] = info.get("id", "")
	_qw_event(&"radiant_completed", q)
	return "%s  %s" % [r["text"], _pay(q)]


func _track_next() -> String:
	var rq := radiant()
	if rq.active.is_empty():
		return ""
	var i := 0
	for k in rq.active.size():
		if rq.active[k]["id"] == rq.tracked:
			i = k
	var q: Dictionary = rq.active[(i + 1) % rq.active.size()]
	rq.tracked = q["id"]
	return "Tracking: %s" % q["title"]


## Mirrors radiant quest events onto Quest Weaver's event bus, so graph quests
## authored in the editor can react (listen for radiant_accepted / _completed / _failed).
func _qw_event(event: StringName, q: Dictionary) -> void:
	var qw := get_node_or_null("/root/QuestWeaverGlobal")
	if qw and qw.has_signal("quest_event_fired"):
		qw.emit_signal("quest_event_fired", event, {"id": q.get("id", ""), "kind": q.get("kind", ""),
			"title": q.get("title", ""), "giver": q.get("giver", "")})


# --- who is this ----------------------------------------------------------------

func _keeper_info(id: String) -> Dictionary:
	var k: Array = KEEPERS.get(id, ["villager", "villager", "villager"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED, id])
	var nm := Life.lore.random_name("caldric", rng)
	return {"id": id, "person": -1, "name": nm if nm != "" else id.capitalize(), "role": k[0], "file": k[1],
		"quest_role": k[2], "culture": "caldric", "faction": "ashford", "bond": "",
		"pos": _keeper_pos.get(id, _home_pos())}


## Fills in who a villager (TalkTarget.npc_of) or keeper is: name, role, culture,
## faction, dialogue file, family bond.
func _npc_info(npc: Dictionary) -> Dictionary:
	var id := String(npc.get("id", ""))
	if KEEPERS.has(id):
		return _keeper_info(id)
	var person := int(npc.get("person", -1))
	var info := {"id": id, "person": person, "name": String(npc.get("name", "Villager")), "role": "villager",
		"file": "villager", "quest_role": "villager", "culture": "caldric", "faction": "ashford", "bond": "",
		"pos": _home_pos()}
	if person < 0:
		return info
	info["name"] = WorldSim.person_name(person)
	info["role"] = String(WorldSim.JOBS[WorldSim.job[person]]).to_lower()
	if WorldSim.home[person] != 0:
		info["faction"] = "crown_caldrenn"
	for p: Dictionary in Life.life_path.parents:
		if int(p["id"]) == person:
			info["name"] = p["name"]
			info["bond"] = p["role"]
			info["file"] = "parents"
			info["quest_role"] = ""
	return info


func _sync(info: Dictionary) -> void:
	var rel := relationships()
	var fresh: bool = not rel.has_npc(info["id"])
	rel.ensure(info["id"], info)
	if info["bond"] != "":
		rel.set_bond(info["id"], info["bond"], Life.life_path.bond(info["bond"]))
	elif fresh:
		# First impressions: a little warmth for a local child, a little wariness for strangers' kids.
		var h := hash(info["id"]) % 21 - 6
		rel.ensure(info["id"], {"base": float(h)})


# --- conversation context ---------------------------------------------------------

func _weather_name() -> String:
	if _weather == null or not is_instance_valid(_weather):
		_weather = get_tree().get_first_node_in_group("weather")
		if _weather == null and Time.get_ticks_msec() / 1000.0 > _weather_search:
			_weather_search = Time.get_ticks_msec() / 1000.0 + 10.0
			var scan: Array = []
			if get_parent():
				scan.append_array(get_parent().get_children())
			if get_tree().current_scene:
				scan.append_array(get_tree().current_scene.get_children())
			for n: Node in scan:
				if n.has_method("current_name") and n.has_signal("weather_changed"):
					_weather = n
					break
	return String(_weather.current_name()) if _weather else "clear"


func _gossip_data() -> Dictionary:
	if _gossip.is_empty():
		_gossip = DialogueRunner.load_file("gossip")
	return _gossip


static func _culture_greeting(c: Dictionary) -> Array:
	var g := String(c.get("greeting", ""))
	var parts := g.split("\"")
	var hello := parts[1] if parts.size() > 1 else "Good day."
	var reply := parts[3] if parts.size() > 3 else "And to you."
	return [hello, reply]


func _recent_events(id: String, now: float) -> Array:
	var rel := relationships()
	var ev: Array = []
	if rel.has_modifier(id, "insult", now) and now - rel.modifier_day(id, "insult") < 20.0:
		ev.append("insulted")
	if now - rel.modifier_day(id, "chores") < 2.0:
		ev.append("helped_recently")
	if now - rel.modifier_day(id, "gift") < 1.0:
		ev.append("gifted_recently")
	if now - rel.modifier_day(id, "quest") < 3.0 or WorldSim.day - _last_quest_day <= 1:
		ev.append("quest_done")
	if not Life.injuries.active.is_empty():
		ev.append("injured")
	if Life.needs.food < 25.0:
		ev.append("hungry")
	if Life.guild.is_member(RAAdventurerGuild.PLAYER):
		ev.append("guild_member")
	for t: String in Life.titles.earned_ids:
		if WorldSim.day - int(Life.titles.earned_ids[t]) <= 3:
			ev.append("new_title")
			break
	return ev


## A hidden-trigger hint this child could still act on: [trigger id, text] or [].
func _pick_hint() -> Array:
	var hints: Dictionary = _gossip_data().get("hints", {})
	var age := Life.age()
	var fresh: Array = []
	var told: Array = []
	for t: Dictionary in Life.triggers.triggers:
		var id := String(t["id"])
		if Life.triggers.has_fired(id) or not hints.has(id):
			continue
		if age > int(t["age_max"]) or age < int(t["age_min"]) - 2:
			continue
		(told if Life.life_path.has_flag("hint_told:" + id) else fresh).append(id)
	var pool := fresh if not fresh.is_empty() else told
	if pool.is_empty():
		return []
	var pick: String = pool[_rng.randi() % pool.size()]
	var texts: Array = hints[pick]
	return [pick, String(texts[_rng.randi() % texts.size()])]


## One rumour from the state of the world (dens, threats, places, the guild).
func _pick_rumour() -> String:
	# Failing runestones are the talk of every road (docs/RISING_ASHES_LIFE_SIM_DESIGN.md).
	var stones: Array = Frontier.runestones.rumours()
	if not stones.is_empty() and randf() < 0.45:
		return String(stones[randi() % stones.size()])
	var prices: Array = Life.economy.rumour_prices()
	if not prices.is_empty() and randf() < 0.35:
		return String(prices[randi() % prices.size()])
	var lc: Object = Life.get("life_courses")
	if lc != null:
		var chronicle: Array = lc.rumours()
		if not chronicle.is_empty() and randf() < 0.2:
			return String(chronicle[randi() % chronicle.size()])
	var r: Dictionary = _gossip_data().get("rumours", {})
	var home := _home_pos()
	var cands: Array = []   # [category, vars]
	var near_den: Dictionary = {}
	for d: Dictionary in Frontier.ecology.dens:
		if d["alive"] and (near_den.is_empty() or home.distance_to(d["pos"]) < home.distance_to(near_den["pos"])):
			near_den = d
	if not near_den.is_empty():
		var v: Vector2 = near_den["pos"] - home
		cands.append(["den", {"dir": RadiantQuests._compass(v), "dist": int(v.length()), "count": int(near_den["population"])}])
	for m: Dictionary in Frontier.threat.modifiers:
		cands.append(["threat", {"label": String(m.get("label", "Strange signs"))}])
	var open := 0
	for c: Dictionary in Life.guild.board(0):
		if c["state"] == "open":
			open += 1
	if open > 0:
		cands.append(["guild", {"count": open}])
	for cat: String in ["waystation", "hollow", "orcs", "goblins", "crown"]:
		cands.append([cat, {}])
	var pick: Array = cands[_rng.randi() % cands.size()]
	var texts: Array = r.get(pick[0], [])
	if texts.is_empty():
		return ""
	return String(texts[_rng.randi() % texts.size()]).format(pick[1])


func _talk_ctx(info: Dictionary) -> Dictionary:
	var rel := relationships()
	var now := _now()
	var id: String = info["id"]
	var greet := _culture_greeting(Life.lore.culture(String(info.get("culture", "caldric"))))
	var tier_s: String = rel.tier(id, now)
	var qrole := String(info.get("quest_role", ""))
	var gift_items := false
	for it in Life.inventory.get_items():
		gift_items = true
		break
	var chores_day: float = rel.modifier_day(id, "chores")
	return {
		"id": id, "tier": tier_s, "bond": String(info.get("bond", "")), "opinion": rel.opinion(id, now),
		"time": DialogueRunner.time_bucket(WorldSim.time_of_day), "weather": _weather_name(),
		"child": not Life.is_adult(), "age": Life.age(), "role": String(info.get("role", "")),
		"flags": Life.life_path.flags, "events": _recent_events(id, now),
		"name": info["name"], "first": String(info["name"]).get_slice(" ", 0),
		"player": Life.life_path.given_name, "town": WorldGen.settlements[0]["name"],
		"greeting": greet[0], "reply": greet[1],
		"mother": Life.life_path.parent("mother").get("name", "your mother"),
		"father": Life.life_path.parent("father").get("name", "your father"),
		"kid": "little one" if not Life.is_adult() else "friend",
		"rumour": String(_talk.get("rumour", "")), "hint": String(_talk.get("hint", "")),
		"quest_offer": qrole != "" and not radiant().offers_for(qrole, Relationships.tier_rank(tier_s)).is_empty(),
		"quest_ready": not _ready_quests(info).is_empty(),
		"has_gift_items": gift_items,
		"chores_today": floorf(chores_day) == floorf(now),
		"guild_member": Life.guild.is_member(RAAdventurerGuild.PLAYER),
		"vars": {"family": Life.life_path.family_name},
	}


func _ready_quests(info: Dictionary) -> Array:
	var qrole := String(info.get("quest_role", ""))
	return radiant().ready_for(info["id"], qrole if KEEPERS.has(info["id"]) else "")


# --- conversation menu --------------------------------------------------------------

## A keeper menu's "Talk" button.
func _talk_option(keeper: String) -> Array:
	var info := _keeper_info(keeper)
	return ["Talk with %s" % String(info["name"]).get_slice(" ", 0), func() -> String:
		_begin_talk(info)
		hud.show_menu(talk_menu.bind({"id": keeper}))
		return ""]


## Menu source for talking to someone ({id, person} from TalkTarget, or a keeper id).
## A fresh open (menu closed) starts the conversation from its greeting.
func talk_menu(npc: Dictionary) -> Dictionary:
	var info := _npc_info(npc)
	if _talk.get("id", "") != info["id"] or not hud.is_menu_open():
		_begin_talk(info)
	return _talk_page()


func _begin_talk(info: Dictionary) -> void:
	_sync(info)
	_talk = {"id": info["id"], "info": info, "file": info["file"], "node": "", "line": ""}
	var d := DialogueRunner.load_file(info["file"])
	_enter(DialogueRunner.start_node(d))
	var rel := relationships()
	if rel.note_talk(info["id"], _now()):
		rel.add_modifier(info["id"], "talked", "Chatted recently", 3.0, _now(), 4.0)


## Moves to a dialogue node: fresh rumour/hint, picks and applies the line.
func _enter(node: String) -> void:
	var info: Dictionary = _talk["info"]
	var h := _pick_hint()
	_talk["node"] = node
	_talk["rumour"] = _pick_rumour()
	_talk["hint_id"] = h[0] if not h.is_empty() else ""
	_talk["hint"] = h[1] if not h.is_empty() else ""
	var d := DialogueRunner.load_file(_talk["file"])
	var line := DialogueRunner.pick_line(d, node, _talk_ctx(info), _rng)
	_talk["line"] = String(line.get("text", "…"))
	var msg := _do_actions(line.get("do", []))
	if msg != "":
		_talk["line"] += "\n\n" + msg


func _talk_page() -> Dictionary:
	var info: Dictionary = _talk["info"]
	var rel := relationships()
	var now := _now()
	var ctx := _talk_ctx(info)
	var d := DialogueRunner.load_file(_talk["file"])
	var opts: Array = []
	for c: Dictionary in DialogueRunner.choices(d, _talk["node"], ctx):
		opts.append([c["text"], _choose.bind(c)])
	_add_courtship_options(opts, info)
	var why := PackedStringArray()
	for b: Array in rel.breakdown(info["id"], now).slice(0, 3):
		why.append("%s %+d" % [b[0], b[1]])
	var status := "%s · opinion %+d" % [rel.tier_label(info["id"], now), rel.opinion(info["id"], now)]
	if not why.is_empty():
		status += "\n" + ", ".join(why)
	var role := String(info.get("bond", "")) if info.get("bond", "") != "" else String(info.get("role", ""))
	return {"title": "%s  ·  %s" % [info["name"], role.capitalize()],
		"body": "%s\n\n%s" % [_talk["line"], status], "options": opts}


## Family/courtship actions layered on top of the dialogue file's own choices
## (Life.get("family") is guarded: nothing shows until autoload/life.gd owns
## one — see the hook lines in the PR notes).
func _add_courtship_options(opts: Array, info: Dictionary) -> void:
	var fam: Object = Life.get("family")
	if fam == null or String(info.get("bond", "")) != "" or String(info.get("id", "")) == "":
		return
	var npc_id: String = info["id"]
	var first: String = String(info.get("name", "them")).get_slice(" ", 0)
	if bool(fam.is_married()):
		return
	var st: String = String(fam.stage(npc_id))
	if st == "":
		if String(fam.can_court(npc_id)) == "":
			opts.append(["Court %s" % first, func() -> String: return fam.court(npc_id)])
		return
	opts.append(["Take %s on a date" % first, func() -> String: return fam.date(npc_id)])
	if String(fam.can_propose(npc_id)) == "":
		opts.append(["Propose to %s" % first, func() -> String: return fam.propose(npc_id)])
	if st == "betrothed" and String(fam.can_marry(npc_id)) == "":
		opts.append(["Marry %s" % first, func() -> String: return fam.marry(npc_id)])


func _choose(c: Dictionary) -> String:
	var msg := _do_actions(c.get("do", []))
	if not hud.is_menu_open() or _talk.is_empty():
		return msg
	var g := String(c.get("goto", ""))
	if g == "@end":
		hud.close_menu()
	elif g != "":
		_enter(g)
	return msg


## Applies dialogue actions (see DialogueRunner). Returns a message to show, or "".
func _do_actions(actions: Array) -> String:
	if actions.is_empty() or _talk.is_empty():
		return ""
	var info: Dictionary = _talk["info"]
	var id: String = info["id"]
	var rel := relationships()
	var now := _now()
	var out := PackedStringArray()
	for a: Variant in actions:
		var act: Array = a if a is Array else [a]
		match String(act[0]):
			"opinion":
				rel.add_modifier(id, String(act[1]), String(act[2]), float(act[3]), now, float(act[4]) if act.size() > 4 else 0.0)
			"rep":
				rel.change_rep(String(act[1]), float(act[2]))
			"bond":
				if info["bond"] != "":
					Life.life_path.adjust_bond(info["bond"], float(act[1]))
					rel.set_bond(id, info["bond"], Life.life_path.bond(info["bond"]))
			"flag":
				Life.life_path.set_flag(String(act[1]))
			"record":
				Life.record(String(act[1]), float(act[2]) if act.size() > 2 else 1.0)
			"give":
				Life.give(String(act[1]), int(act[2]) if act.size() > 2 else 1)
			"chores":
				WorldSim.advance_hours(1.0)
			"tell_hint":
				if String(_talk.get("hint_id", "")) != "":
					Life.life_path.set_flag("hint_told:" + String(_talk["hint_id"]))
			"close":
				hud.close_menu()
			"gift":
				hud.show_menu(_gift_menu.bind(info))
			"quests":
				hud.show_menu(_quest_menu.bind(info))
			"turn_in":
				for q: Dictionary in _ready_quests(info):
					out.append(_turn_in(String(q["id"]), info))
	return "\n".join(out)


func _back_to_talk(info: Dictionary) -> String:
	hud.show_menu(talk_menu.bind({"id": info["id"], "person": info["person"]}))
	return ""


func _gift_menu(info: Dictionary) -> Dictionary:
	var rel := relationships()
	var id: String = info["id"]
	var opts: Array = []
	var seen := {}
	var today := rel.gifted_today(id, _now())
	for it in Life.inventory.get_items():
		var item := it.get_prototype().get_prototype_id()
		if seen.has(item):
			continue
		seen[item] = true
		var known: String = rel.known_reaction(id, item)
		var note := ("  (%s it)" % {"loves": "loves", "likes": "likes", "neutral": "doesn't mind", "dislikes": "dislikes"}[known]) if known != "" else ""
		opts.append(["%s ×%d%s" % [Life.item_name(item), Life.count(item), note], _give.bind(info, item), not today])
	opts.append(["Back", _back_to_talk.bind(info)])
	var body := "What might %s like?" % String(info["name"]).get_slice(" ", 0)
	if today:
		body += "\nYou've already given a gift today."
	return {"title": "A gift for %s" % info["name"], "body": body, "options": opts}


func _give(info: Dictionary, item: String) -> String:
	var r: Dictionary = relationships().give_gift(info["id"], item, _now())
	if r.get("ok", false):
		Life.take(item)
		Life.record("gave_gift", 0.5)
	_back_to_talk(info)
	_talk["line"] = "%s\n(%s)" % [r["text"], ("opinion %+d" % int(r["delta"])) if r.get("ok", false) else "no gift given"]
	return ""


func _quest_menu(info: Dictionary) -> Dictionary:
	var rel := relationships()
	var rq := radiant()
	var id: String = info["id"]
	var tr: int = Relationships.tier_rank(rel.tier(id, _now())) if not KEEPERS.has(id) else 5
	var qrole := String(info.get("quest_role", "villager"))
	var opts: Array = []
	var lines := PackedStringArray()
	for q: Dictionary in _ready_quests(info):
		opts.append(["✔ Report: %s" % q["title"], _turn_in.bind(String(q["id"]), info)])
	var offers := rq.offers_for(qrole, tr)
	if qrole == "guild" and not Life.guild.is_member(RAAdventurerGuild.PLAYER):
		offers.clear()
		lines.append("\"Contracts are for registered adventurers. Sign the book first.\"")
	for q: Dictionary in offers:
		var rw: Dictionary = q["reward"]
		lines.append("• %s: %s" % [q["title"], q["desc"]])
		var why: String = rq.can_accept(q["id"])
		opts.append(["Accept: %s  —  %dg · %d days" % [q["title"], int(rw["gold"]), int(q.get("days", 5))],
			_accept.bind(String(q["id"]), info), why == ""])
	opts.append(["Back", _back_to_talk.bind(info)])
	var body := "\n".join(lines) if not lines.is_empty() else "\"Nothing I need right now.\""
	body += "\nActive jobs: %d / %d" % [rq.active.size(), RadiantQuests.MAX_ACTIVE]
	return {"title": "Work from %s" % info["name"], "body": body, "options": opts}


func _accept(qid: String, info: Dictionary) -> String:
	var rel := relationships()
	var id: String = info["id"]
	var bonus := 5 if Relationships.tier_rank(rel.tier(id, _now())) >= 4 else 0
	var q: Dictionary = radiant().find(qid)
	var why: String = radiant().accept(qid, WorldSim.day, id, String(info["name"]), info.get("pos", _home_pos()), _quest_ctx(), bonus)
	if why != "":
		return why
	_qw_event(&"radiant_accepted", q)
	Audio.play_ui("quest_accepted")
	return "Accepted: %s. %s" % [q["title"], RadiantQuests.current_stage(q).get("text", "")]


## Everyone the player knows, and where they stand with each faction.
func people_menu() -> Dictionary:
	var rel := relationships()
	var now := _now()
	var lines := PackedStringArray()
	var fl := PackedStringArray()
	for f: String in rel.reputation:
		if float(rel.reputation[f]) != 0.0 or Relationships.FACTIONS.has(f):
			fl.append("%s: %s (%+d)" % [rel.faction_name(f), rel.standing(f), int(rel.rep(f))])
	lines.append("Factions\n  " + "\n  ".join(fl))
	var people: Array = []
	for id: String in rel.npcs:
		if int(rel.npcs[id]["talks"]) > 0:
			people.append([id, rel.opinion(id, now)])
	people.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var pl := PackedStringArray()
	for p: Array in people.slice(0, 14):
		var e: Dictionary = rel.npcs[p[0]]
		pl.append("%s — %s (%+d)" % [e["name"], rel.tier_label(p[0], now), p[1]])
	lines.append("People\n  " + ("\n  ".join(pl) if not pl.is_empty() else "You haven't really talked to anyone yet."))
	return {"title": "People & Reputation", "body": "\n\n".join(lines),
		"options": [["Back to pack", func() -> String:
			hud.show_menu(pack_menu)
			return ""]]}


# --- property: houses, rooms, dues, storage -----------------------------------------

## Every property the player owns or rents: dues owed, storage, and the
## option to pay up or sell.
func properties_menu() -> Dictionary:
	var prop: RAProperty = Life.property
	var lines := PackedStringArray()
	var opts: Array = []
	for i: Dictionary in prop.owned():
		lines.append("%s in %s (owned)  ·  tax %dg/season%s" % [String(i["name"]), String(i["settlement_name"]),
			int(i["tax"]), ("  ·  %dg tax owed" % int(i["tax_debt"])) if int(i["tax_debt"]) > 0 else ""])
		var stacks: int = (i["storage"] as Array).size()
		lines.append("  Chest: %d / %d slots used." % [stacks, prop.storage_capacity(String(i["lot_id"]))])
		if bool(i["workshop"]):
			lines.append("  Has a workshop: you can craft at home here.")
		if not (i["servants"] as Array).is_empty():
			lines.append("  Servants: %s." % ", ".join(PackedStringArray(i["servants"])))
		opts.append(["Sell %s (80%% back)" % String(i["name"]).to_lower(), prop.sell.bind(String(i["lot_id"]))])
	for i: Dictionary in prop.rented():
		var is_room := String(i["kind"]) == "inn_room"
		lines.append("%s in %s (rented)  ·  rent %dg/week%s" % [String(i["name"]), String(i["settlement_name"]),
			int(i["rent"]), ("  ·  %dg rent owed" % int(i["debt"])) if int(i["debt"]) > 0 else ""])
		if not is_room:
			var stacks: int = (i["storage"] as Array).size()
			lines.append("  Chest: %d / %d slots used." % [stacks, prop.storage_capacity(String(i["lot_id"]))])
	var owed := prop.total_debt()
	if owed > 0:
		lines.append("\nTotal dues owed: %dg." % owed)
		opts.append(["Pay all dues (%dg)" % mini(owed, Game.gold), func() -> String:
			return prop.pay_due()])
	if lines.is_empty():
		lines.append("You hold no property.")
	opts.append(["Back to pack", func() -> String:
		hud.show_menu(pack_menu)
		return ""])
	return {"title": "Your Properties", "body": "\n".join(lines), "options": opts}
