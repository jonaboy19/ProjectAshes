extends Node
## The player's life in the world: employment (RACareers), hunger and sleep
## (RANeeds), possessions (a GLoot Inventory), the village market (RAMarket),
## merit, and save/load of the whole simulation.
##
## Villages' organisations are seeded here from the world plan and staffed
## with real WorldSim people, leaving genuine vacancies.

signal inventory_changed
signal employment_changed
signal grown(age: int)

const PROTOSET := "res://data/items.json"
const SAVE_PATH := "user://save_%d.json"
const SAVE_VERSION := 1
## Radius around the home village the guard counts as "at post" (walls, ring, gate).
const GUARD_POST_MARGIN := 45.0

## You are born in the first village and play from childhood.
const START_AGE := 6
const ADULT_AGE := 16

var life_path := RALifePath.new()
var titles := RATitles.new()
var archetypes := RAArchetypes.new()
var triggers := RAHiddenTriggers.new()
var careers := RACareers.new()
var lore := RAWorldLore.new()
var guild := RAAdventurerGuild.new()
var magicules := RAMagicules.new()
var naming := RANaming.new()
var injuries := RAInjuries.new()
var scouts := RAScouts.new()
var discovery := preload("res://scripts/sim/discovery.gd").new()
## Scout offers waiting for an answer: [event]
var pending_offers: Array = []
const GUILD_MIN_AGE := 12
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
	_begin_life()
	life_path.birthday.connect(func(age: int) -> void:
		Game.say("Happy birthday! You are %d." % age)
		grown.emit(age))
	life_path.stage_changed.connect(func(stage: int) -> void:
		Game.say("You are now %s." % ("a " + RALifePath.STAGE_NAMES[stage].to_lower())))
	titles.earned.connect(func(t: Dictionary) -> void:
		Game.say("Title earned: %s" % t.get("name", t.get("id", "?"))))
	triggers.triggered.connect(_on_trigger)
	guild.add_branch(0, "%s Guild Hall" % WorldGen.settlements[0]["name"])
	guild.context = _guild_context
	guild.tick_day(WorldSim.day)
	guild.rank_changed.connect(func(who: int, rank: int) -> void:
		if who == RAAdventurerGuild.PLAYER:
			Game.say("Guild rank up: %s-rank adventurer!" % RAAdventurerGuild.rank_name(rank))
			if rank == 2:
				_offer(scouts.on_scenario(scout_profile(), "guild_rank_d", WorldSim.day)))
	careers.seat_filled.connect(func(o: Dictionary, s: Dictionary, who: int) -> void:
		if who == RACareers.PLAYER and guild.is_member(RAAdventurerGuild.PLAYER):
			var r := guild.on_hired(RAAdventurerGuild.PLAYER, o["id"], s["title"], WorldSim.day)
			if r.get("ok", false):
				Game.say(String(r.get("text", ""))))


# --- life from birth ------------------------------------------------------------

## A child of two real villagers, living in one of the village's houses.
func _begin_life() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var r: Vector2i = WorldSim.ranges[0]
	var mother := r.x + 3
	var father := r.x + 8
	# Parents are named from the Caldric (home kingdom) culture, by gender.
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSim.SEED + 7
	var father_name := lore.random_name("caldric", rng, "male")
	var mother_given := lore.random_name("caldric", rng, "female").get_slice(" ", 0)
	var family := father_name.get_slice(" ", 1)
	var mname := "%s %s" % [mother_given, family]
	var house := Vector2(14, 9)
	var lots: Array = home["plan"].get("lots", [])
	for lot: Dictionary in lots:
		if String(lot["asset"]).begins_with("house") and (lot["pos"] as Vector2).length() < 25.0:
			house = lot["pos"]
			break
	life_path.begin(WorldSim.day, WorldSim.time_of_day, "Ren", family,
		[{"id": mother, "name": mname, "role": "mother"},
		 {"id": father, "name": father_name, "role": "father"}], 0, house)
	life_path.set_age(START_AGE, WorldSim.day, WorldSim.time_of_day)
	triggers.seed_first_region(home["pos"], home["radius"])


## The smallest named place (from data/world/first_region.json) containing p, or {}.
func place_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_r := INF
	for pl: Dictionary in lore.places_in_region():
		if not pl.has("radius") or pl.get("kind", "") in ["village", "capital", "hidden_place"]:
			continue
		var r := float(pl["radius"])
		if p.distance_to(pl["pos"]) <= r and r < best_r:
			best = pl
			best_r = r
	return best


func age() -> int:
	return life_path.age_years(WorldSim.day, WorldSim.time_of_day)


func is_adult() -> bool:
	return age() >= ADULT_AGE


## 0.62 of adult height at 6, full height at 16.
func body_scale() -> float:
	return clampf(lerpf(0.62, 1.0, (age() - START_AGE) / float(ADULT_AGE - START_AGE)), 0.55, 1.0)


func record(tag: String, weight := 1.0) -> void:
	life_path.record(tag, weight, WorldSim.day)


func build_summary() -> String:
	var lead := archetypes.leading(life_path.actions, _title_bonus(), 3)
	var parts := PackedStringArray()
	for a: Dictionary in lead:
		parts.append("%s %d%%" % [a["name"], int(float(a["affinity"]) * 100)])
	return ", ".join(parts)


func _title_bonus() -> Dictionary:
	return titles.earned_ids


func _life_tick(hour: int) -> void:
	life_path.update(WorldSim.day, hour)
	titles.evaluate({"actions": life_path.actions, "stats": {"gold": Game.gold, "merit": Game.merit},
		"age": age(), "flags": life_path.flags, "day": WorldSim.day})
	if player and is_instance_valid(player):
		triggers.check(Vector2(player.global_position.x, player.global_position.z), age(), float(hour), life_path.flags)


func _on_trigger(t: Dictionary) -> void:
	var g: Dictionary = t.get("grants", {})
	for f in g.get("flags", []):
		life_path.set_flag(String(f))
	if g.get("title", "") != "":
		titles.grant(g["title"], WorldSim.day)
	if g.get("class", "") != "":
		life_path.set_flag("class:" + String(g["class"]))
		Game.say("Something awakens in you. Class gained: %s" % g["class"])
	if g.get("ability", "") != "":
		life_path.set_flag("ability:" + String(g["ability"]))
	if g.get("quest", "") != "":
		life_path.set_flag("quest:" + String(g["quest"]))


# --- guild, magic, injuries, scouts ------------------------------------------------

func _guild_context(settlement: int, _day: int) -> Dictionary:
	var home: Vector2 = WorldGen.settlements[settlement]["pos"]
	var dens := []
	for den in Frontier.ecology.dens:
		if not den["alive"]:
			continue
		var p: Vector2 = den["pos"]
		var threat := float(Frontier.ecology.pressure_at(p).get("total", 10.0))
		dens.append({"id": den["id"], "species": den["species"], "population": den["population"],
			"threat": threat, "distance": p.distance_to(home), "compass": Frontier._compass(p - home).trim_prefix("toward the ")})
	var gathering := []
	for item: String in market.stock:
		if int(market.stock[item]) < int(market.target[item]) / 2 and item in ["wolf_pelt", "firewood", "wolf_meat"]:
			gathering.append({"item": item, "amount": int(market.target[item]) - int(market.stock[item])})
	var rumours := []
	for m: Dictionary in Frontier.threat.modifiers:
		rumours.append({"id": hash(m.get("label", "")), "label": m.get("label", "Strange signs"), "threat": m.get("value", 10.0)})
	return {"dens": dens, "caravans": [], "gathering": gathering, "deliveries": [], "rumours": rumours,
		"vacancies": RAAdventurerGuild.vacancies_from(careers, settlement)}


func scout_profile() -> Dictionary:
	return {"id": -1, "name": life_path.full_name(), "age": age(), "titles": titles.earned_ids.keys(),
		"feats": life_path.flags.keys().filter(func(f: String) -> bool: return f.begins_with("class:")),
		"reputation": clampf(Game.merit / 10.0, 0.0, 100.0),
		"guild_rank": int(guild.member(RAAdventurerGuild.PLAYER).get("rank", -1))}


func _offer(e: Dictionary) -> void:
	if e.is_empty():
		return
	pending_offers.append(e)
	var sc: Dictionary = e.get("scout", {})
	var org: Dictionary = e.get("org", {})
	Game.say("%s of %s has been watching you. (See your Pack to answer.)" % [sc.get("name", "A stranger"), org.get("name", "somewhere")])


func answer_offer(event_id: int, yes: bool) -> String:
	for e: Dictionary in pending_offers.duplicate():
		if int(e["id"]) == event_id:
			pending_offers.erase(e)
			if not yes:
				scouts.decline(event_id)
				return "You decline, politely."
			var r := scouts.accept(event_id, WorldSim.day)
			life_path.set_flag("recruited:" + String(e["org"].get("id", "?")))
			if bool(e["offer"].get("soulbeast_path", false)):
				life_path.set_flag("permit:xiava_lake")
			return String(r.get("text", "You accept the offer."))
	return ""


## Effective level for naming: grows with merit, reduced while levels are lost to naming.
func player_level() -> int:
	return maxi(1, 1 + int(sqrt(float(Game.merit))) + age() / 4 - naming.level_penalty(WorldSim.day))


## Name a yielded monster: pays magicules, may cost levels or cause injuries.
func name_monster(m: CampMonster, given: String, klass: String) -> String:
	var r := naming.name_monster(magicules, injuries, player_level(), m.species, m.level, given, klass, WorldSim.day)
	if not r.get("ok", false):
		return String(r.get("text", "The name does not take."))
	m.become_named(given, klass)
	record("named", 3.0)
	var dmg := int(r.get("damage", 0))
	if dmg > 0 and player and player.has_method("set_health"):
		player.set_health(int(player.get("health")) - dmg)
	magicules.apply_effects(injuries.effects())
	return String(r.get("text", ""))


func join_guild() -> String:
	if age() < GUILD_MIN_AGE:
		return "\"Adventurers start at %d. Come back then, and bring your parents' blessing.\"" % GUILD_MIN_AGE
	var r := guild.join(RAAdventurerGuild.PLAYER, 0, Game.gold, WorldSim.day)
	if r.get("ok", false):
		Game.add_gold(-int(r.get("fee", 0)))
		record("adventured", 1.0)
	return String(r.get("text", ""))


func turn_in(cid: int) -> String:
	var r := guild.complete(RAAdventurerGuild.PLAYER, cid, WorldSim.day)
	if r.get("ok", false):
		Game.add_gold(int(r.get("gold", 0)))
		record("adventured", 2.0)
	return String(r.get("text", ""))


func treat(uid: int, healer: String) -> String:
	var r := injuries.treat(uid, healer, Game.gold, WorldSim.day)
	if r.get("ok", false):
		Game.add_gold(-int(r["cost"]))
		WorldSim.advance_hours(float(r["hours"]))
		_last_abs = _abs_hours()
		magicules.apply_effects(injuries.effects())
	return String(r.get("text", ""))


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
	preload("res://scripts/sim/gathering_items.gd").register(self)


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
	magicules.regenerate(dh)
	if player and is_instance_valid(player):
		var p := Vector2(player.global_position.x, player.global_position.z)
		if careers.is_on_shift(WorldSim.time_of_day) and careers.at_post(p):
			careers.log_attendance(dh)
		var starve := needs.starvation() * dh
		if starve > 0.0 and player.has_method("take_damage") and randf() < starve:
			player.take_damage(1, null)


func _on_hour(hour: int) -> void:
	_life_tick(hour)
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
		for e: Dictionary in guild.tick_day(WorldSim.day):
			if e.get("type", "") == "failed":
				Game.say(String(e.get("text", "")))
		for h: Dictionary in injuries.tick_day(WorldSim.day):
			Game.say("Your %s has healed." % String(RAInjuries.info(String(h["type"])).get("name", "injury")).to_lower())
		magicules.apply_effects(injuries.effects())
		naming.tick_day(WorldSim.day)
		scouts.tick_day(WorldSim.day)
		_offer(scouts.daily_roll(scout_profile(), WorldSim.day))
		careers.tick_day(_hire)
		market.tick_day(WorldSim.ranges[0].y - WorldSim.ranges[0].x)


## Sleep until rested (or at most until the next morning), then wake.
func sleep(quality := 1.0) -> String:
	# Sleep through to the next morning (about 06:30); a nap if it's already morning.
	var t := WorldSim.time_of_day
	var until_morning := fposmod(6.5 - t, 24.0)
	var hours := clampf(maxf(needs.hours_to_rest(quality), until_morning if until_morning <= 12.0 else 0.0), 1.0, 12.0)
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


func on_monster_killed(species: String) -> void:
	guild.on_kill(RAAdventurerGuild.PLAYER, species, -1)
	add_merit(12 if species == "orc" else 6, "%s slain" % species)
	record("hunted")


func on_wolf_killed(_where: Vector3, den_id := -1) -> void:
	for c: Dictionary in guild.on_kill(RAAdventurerGuild.PLAYER, "wolf", den_id):
		if guild.is_ready(int(c["id"])):
			Game.say("Commission ready to turn in: %s" % c.get("title", ""))
	add_merit(5, "wolf slain")
	record("hunted")
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
	if paid >= 0:
		record("traded", 0.3)
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
	record("traded", 0.5)
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
		"life_path": life_path.serialize(),
		"titles": titles.serialize(),
		"triggers": triggers.serialize(),
		"guild": guild.serialize(),
		"magicules": magicules.serialize(),
		"naming": naming.serialize(),
		"injuries": injuries.serialize(),
		"scouts": scouts.serialize(),
		"discovery": discovery.serialize(),
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
	if d.has("life_path"):
		life_path.deserialize(d["life_path"])
		titles.deserialize(d.get("titles", {}))
		triggers.deserialize(d.get("triggers", {}))
	for key: String in ["guild", "magicules", "naming", "injuries", "scouts", "discovery"]:
		if d.has(key):
			get(key).deserialize(d[key])
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
