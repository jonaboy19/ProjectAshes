extends Node
## The player's life in the world: employment (RACareers), hunger and sleep
## (RANeeds), possessions (a GLoot Inventory), the village market (RAMarket),
## merit, and save/load of the whole simulation.
##
## Villages' organisations are seeded here from the world plan and staffed
## with real WorldSim people, leaving genuine vacancies.

signal inventory_changed
signal employment_changed

const PROTOSET := "res://data/items.json"
const SAVE_PATH := "user://save_%d.json"
const SAVE_VERSION := 1
## Radius around the home village the guard counts as "at post" (walls, ring, gate).
const GUARD_POST_MARGIN := 45.0

var careers := RACareers.new()
var needs := RANeeds.new()
var market := RAMarket.new()
var inventory: Inventory
var player: Node3D        # set by main once the player exists

var _last_abs := -1.0     # absolute in-game hours at the last tick


func _ready() -> void:
	inventory = Inventory.new()
	inventory.name = "PlayerInventory"
	inventory.protoset = load(PROTOSET)
	add_child(inventory)
	inventory.item_added.connect(func(_i: InventoryItem) -> void: inventory_changed.emit())
	inventory.item_removed.connect(func(_i: InventoryItem) -> void: inventory_changed.emit())
	_setup_orgs()
	_setup_market()
	careers.player_changed.connect(func(text: String) -> void:
		Game.say(text)
		employment_changed.emit())
	careers.vacancy_opened.connect(_on_vacancy)
	WorldSim.hour_changed.connect(_on_hour)
	_last_abs = _abs_hours()
	give("bread", 2)


# --- world setup -------------------------------------------------------------

func _setup_orgs() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var r: float = home["radius"]
	var town := String(home["name"])
	careers.add_org("guard", "the %s Guard" % town, 0, "Captain of the Guard", Vector3(c.x, c.y, r + GUARD_POST_MARGIN),
		Vector2(7, 19), 3, [
			{"title": "Captain", "wage": 30, "count": 1, "command": 48, "merit": 400},
			{"title": "Sergeant", "wage": 18, "count": 2, "command": 24, "merit": 120},
			{"title": "Guard", "wage": 9, "count": 10, "command": 0, "merit": 0},
		])
	careers.add_org("smithy", "the %s Smithy" % town, 0, "Master Smith", Vector3(c.x, c.y, r),
		Vector2(7, 17), 1, [
			{"title": "Master Smith", "wage": 20, "count": 1, "merit": 9999},
			{"title": "Journeyman", "wage": 11, "count": 1, "merit": 60},
			{"title": "Apprentice", "wage": 5, "count": 2, "merit": 0},
		])
	careers.add_org("inn", "the %s Inn" % town, 0, "Innkeeper", Vector3(c.x, c.y, r),
		Vector2(11, 23), 2, [
			{"title": "Innkeeper", "wage": 16, "count": 1, "merit": 9999},
			{"title": "Server", "wage": 5, "count": 2, "merit": 0},
		])
	careers.add_org("woodcutters", "the %s Woodcutters" % town, 0, "Foreman", Vector3(c.x, c.y, r * 3.0),
		Vector2(6, 16), 5, [
			{"title": "Foreman", "wage": 12, "count": 1, "merit": 9999},
			{"title": "Woodcutter", "wage": 7, "count": 5, "merit": 0},
		])
	careers.staff(_candidates, {"guard": 0.6, "smithy": 0.5, "inn": 0.5, "woodcutters": 0.6})
	for o in careers.orgs:
		for s: Dictionary in o["seats"]:
			for who: int in s["holders"]:
				if who >= 0:
					WorldSim.job[who] = o["job"]


func _setup_market() -> void:
	market.add_good("bread", 2, 30, 6)
	market.add_good("apple", 1, 40, 8)
	market.add_good("cheese", 4, 12, 2)
	market.add_good("stew", 5, 8, 3)
	market.add_good("bandage", 4, 10, 2)
	market.add_good("wolf_pelt", 8, 6, 0)
	market.add_good("wolf_meat", 2, 10, 0)
	market.add_good("firewood", 1, 30, 6)


## Local people of a settlement who aren't already in an organisation, laborers first.
func _candidates(settlement: int, _job: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var later := PackedInt32Array()
	var rng: Vector2i = WorldSim.ranges[settlement]
	for i in range(rng.x, rng.y):
		if not careers.holder_of(i).is_empty():
			continue
		if WorldSim.job[i] == 4:
			out.append(i)
		elif WorldSim.job[i] == 0:
			later.append(i)
	out.append_array(later)
	return out


func _hire(o: Dictionary) -> int:
	var pool := _candidates(o["settlement"], o["job"])
	if pool.is_empty():
		return -2
	var who := pool[randi() % mini(pool.size(), 12)]
	WorldSim.job[who] = o["job"]
	return who


func _on_vacancy(o: Dictionary, s: Dictionary) -> void:
	if o["settlement"] == 0 and s["title"] != "Master Smith" and s["title"] != "Innkeeper":
		Game.say("Word in the square: %s is short a %s." % [o["name"], s["title"]])


# --- time ----------------------------------------------------------------------

func _abs_hours() -> float:
	return WorldSim.day * 24.0 + WorldSim.time_of_day


func _process(_delta: float) -> void:
	var now := _abs_hours()
	var dh := now - _last_abs
	_last_abs = now
	if dh <= 0.0 or dh > 2.0:
		return
	needs.tick(dh)
	if player and is_instance_valid(player):
		var p := Vector2(player.global_position.x, player.global_position.z)
		if careers.is_on_shift(WorldSim.time_of_day) and careers.at_post(p):
			careers.log_attendance(dh)
		var starve := needs.starvation() * dh
		if starve > 0.0 and player.has_method("take_damage") and randf() < starve:
			player.take_damage(1, null)


func _on_hour(hour: int) -> void:
	if careers.is_employed():
		var sh: Vector2 = careers.player_org()["shift"]
		if hour == int(sh.y):
			var r := careers.pay_day()
			if r["paid"] > 0:
				Game.add_gold(r["paid"])
			if r["text"] != "":
				Game.say(r["text"])
			if not careers.is_employed():
				employment_changed.emit()
	if hour == 5:
		careers.tick_day(_hire)
		market.tick_day(WorldSim.ranges[0].y - WorldSim.ranges[0].x)


## Sleep until rested (or at most until the next morning), then wake.
func sleep(quality := 1.0) -> String:
	var hours := clampf(needs.hours_to_rest(quality), 1.0, 10.0)
	needs.sleep(hours, quality)
	WorldSim.advance_hours(hours)
	_last_abs = _abs_hours()
	if player and player.get("health") != null:
		player.heal(int(20 * hours * quality))
	return "You sleep %d hours and wake %s." % [int(hours), needs.rest_label().to_lower()]


# --- merit & rank ----------------------------------------------------------------

func add_merit(amount: int, reason: String) -> void:
	Game.merit += amount
	Game.say("+%d merit: %s" % [amount, reason])
	var up := careers.promotion_for_player(Game.merit)
	if not up.is_empty():
		Game.say("A %s's seat is open in %s. Report to the %s." % [up["title"], careers.player_org()["name"],
			careers.player_org()["recruiter"]])


func on_wolf_killed(_where: Vector3) -> void:
	add_merit(5, "wolf slain")
	give("wolf_pelt", 1)
	if randf() < 0.6:
		give("wolf_meat", 1)


# --- inventory -----------------------------------------------------------------

func count(item: String) -> int:
	var n := 0
	for it in inventory.get_items_with_prototype_id(item):
		n += it.get_stack_size()
	return n


func give(item: String, amount := 1) -> void:
	for k in amount:
		var it := inventory.create_item(item)
		inventory.add_item_automerge(it)
	inventory_changed.emit()


func take(item: String, amount := 1) -> bool:
	if count(item) < amount:
		return false
	var left := amount
	for it in inventory.get_items_with_prototype_id(item):
		var n := it.get_stack_size()
		if n > left:
			it.set_stack_size(n - left)
			left = 0
		else:
			left -= n
			inventory.remove_item(it)
		if left == 0:
			break
	inventory_changed.emit()
	return true


func item_prop(item: String, prop: String, default: Variant = null) -> Variant:
	return inventory.get_prototree().get_prototype_property(item, prop, default)


func item_name(item: String) -> String:
	return String(item_prop(item, "name", item))


## Eat or apply an item. Returns the message.
func use_item(item: String) -> String:
	if count(item) <= 0:
		return "You have no %s." % item_name(item)
	var nutrition := float(item_prop(item, "nutrition", 0.0))
	var heal := int(item_prop(item, "heal", 0))
	if nutrition <= 0.0 and heal <= 0:
		return "You can't use %s." % item_name(item)
	take(item)
	if nutrition > 0.0:
		needs.eat(nutrition)
	if heal > 0 and player and player.has_method("heal"):
		player.heal(heal)
	return "%s. You feel %s." % [item_name(item), needs.hunger_label().to_lower()]


## The best food carried (most nutrition), or "".
func best_food() -> String:
	var best := ""
	var best_n := 0.0
	for it in inventory.get_items():
		var n := float(it.get_property("nutrition", 0.0))
		if n > best_n:
			best_n = n
			best = it.get_prototype().get_prototype_id()
	return best


func buy(item: String) -> String:
	var paid := market.buy(item, Game.gold)
	if paid < 0:
		return market.can_buy(item, Game.gold)
	Game.add_gold(-paid)
	give(item)
	return "Bought %s for %d gold." % [item_name(item), paid]


func sell(item: String) -> String:
	if count(item) <= 0:
		return "You have no %s." % item_name(item)
	var got := market.sell(item)
	if got < 0:
		return "The merchant can't afford it today."
	take(item)
	Game.add_gold(got)
	return "Sold %s for %d gold." % [item_name(item), got]


# --- save / load -----------------------------------------------------------------

func snapshot() -> Dictionary:
	var d := {
		"version": SAVE_VERSION,
		"world": WorldSim.serialize(),
		"game": Game.serialize(),
		"careers": careers.serialize(),
		"needs": needs.serialize(),
		"market": market.serialize(),
		"inventory": inventory.serialize(),
		"frontier": Frontier.serialize(),
	}
	if player and is_instance_valid(player):
		d["player"] = {"x": player.global_position.x, "y": player.global_position.y,
			"z": player.global_position.z, "health": player.get("health")}
	return d


func restore(d: Dictionary) -> void:
	WorldSim.deserialize(d.get("world", {}))
	Game.deserialize(d.get("game", {}))
	careers.deserialize(d.get("careers", {}))
	for o in careers.orgs:
		for s: Dictionary in o["seats"]:
			for who: int in s["holders"]:
				if who >= 0:
					WorldSim.job[who] = o["job"]
	needs.deserialize(d.get("needs", {}))
	market.deserialize(d.get("market", {}))
	inventory.deserialize(d.get("inventory", {}))
	Frontier.deserialize(d.get("frontier", {}))
	_last_abs = _abs_hours()
	if d.has("player") and player and is_instance_valid(player):
		var p: Dictionary = d["player"]
		player.global_position = Vector3(p["x"], p["y"], p["z"])
		if player.has_method("set_health"):
			player.set_health(int(p.get("health", 100)))
	inventory_changed.emit()
	employment_changed.emit()
	Game.stats_changed.emit()


func save_game(slot := 1) -> bool:
	var f := FileAccess.open(SAVE_PATH % slot, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(snapshot()))
	return true


func load_game(slot := 1) -> bool:
	if not FileAccess.file_exists(SAVE_PATH % slot):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH % slot))
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	restore(data)
	return true


func has_save(slot := 1) -> bool:
	return FileAccess.file_exists(SAVE_PATH % slot)
