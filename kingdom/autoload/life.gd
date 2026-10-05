extends Node
## The player's life in the world: employment (RACareers), hunger and sleep
## (RANeeds), possessions (a GLoot Inventory), the village market (RAMarket),
## merit, and save/load of the whole simulation.
##
## Villages' organisations are seeded here from the world plan and staffed
## with real WorldSim people, leaving genuine vacancies.

signal inventory_changed
## Region1 hook (docs/regions/REGION_1_PLAN.md) C7: a creature the player killed (story kill objectives). species is a registry target id.
signal region1_kill(species: String, where: Vector3)
signal employment_changed
signal grown(age: int)

const PROTOSET := "res://data/items.json"
const SAVE_PATH := "user://save_%d.json"
const SAVE_VERSION := 1
## Radius around the home village the guard counts as "at post" (walls, ring, gate).
const GUARD_POST_MARGIN := 45.0

## You are born in the first village and play from childhood, a person, not a
## class: the age-12 Blessing (awakening.gd) is a cultural event, not a class
## pick, and the world opens up at ADULT_AGE.
const START_AGE := 4
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
## Persistent state of interactive world objects (doors, chests, locks, broken props) and the evidence
## left on the ground; saved under "interactives" (scripts/world/world_state.gd).
var world_state: RefCounted = preload("res://scripts/world/world_state.gd").shared()
var relationships := preload("res://scripts/sim/relationships.gd").new()
## Sparse NPC-to-NPC ties from completed embodied conversations; separate from player opinion.
var npc_social_graph := preload("res://scripts/sim/npc_social_graph.gd").new()
var radiant := preload("res://scripts/sim/radiant_quests.gd").new()
var crafting := preload("res://scripts/sim/crafting.gd").new()
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const SaveContainers := preload("res://scripts/sim/save_containers.gd")
const WorldEventLog := preload("res://scripts/systems/world_event_log.gd")
const ActionRuntime := preload("res://scripts/systems/action_runtime.gd")
const NpcActivityRuntime := preload("res://scripts/systems/npc_activity_runtime.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const NpcSocialGraph := preload("res://scripts/sim/npc_social_graph.gd")
## Bounded facts from player actions, available to future dialogue/simulation consumers.
var world_events = WorldEventLog.new()
## Short-lived actor/action leases; deliberately excluded from saves.
var action_runtime = ActionRuntime.new()
## NPC activity names/leases adapt onto the same transient ActionRuntime authority.
var npc_activity_runtime = NpcActivityRuntime.new(action_runtime)
## Active craft token -> generation-qualified station resource key.
var _craft_station_actions: Dictionary = {}
var equipment := preload("res://scripts/sim/equipment.gd").new()
var skills := preload("res://scripts/sim/skills.gd").new()
## Careers as biography (docs/RISING_ASHES_LIFE_SIM_DESIGN.md): mastery only grows by doing,
## the biography keeps every chapter and reputation across career changes.
var mastery := preload("res://scripts/sim/mastery.gd").new()
var biography := preload("res://scripts/sim/biography.gd").new()
var property := preload("res://scripts/sim/property.gd").new()
var nobility := preload("res://scripts/sim/nobility.gd").new()
var lordship := preload("res://scripts/sim/lordship.gd").new()
var family := preload("res://scripts/sim/family.gd").new()
## Notable NPCs who age, marry, work, die (Phase 4) and the war with a neighbour.
## Phase 5 soul system: tiers and Paths, usage-driven evolution, Echoes (naming.gd holds Soul Names).
var soul := preload("res://scripts/sim/soul.gd").new()
var skill_evolution := preload("res://scripts/sim/skill_evolution.gd").new()
var echoes := preload("res://scripts/sim/echoes.gd").new()
const RECORD_TO_SOUL := {
	"helped_farmer": "farm", "farmed": "farm", "hunted": "hunt", "fished": "hunt",
	"trained_sword": "combat", "trained_bow": "combat", "adventured": "combat", "studied": "technique",
	"meditated": "meditate",
}
## Look chosen at character creation (scripts/ui/character_creation.gd); empty = default hero.
var appearance: Dictionary = {}
var life_courses := preload("res://scripts/sim/life_courses.gd").new()
var war := preload("res://scripts/sim/war_sim.gd").new()
## Realm / war / settlement / city-life simulation (scripts/realm/, docs/design/SIM_HIERARCHY.md).
var realm := preload("res://scripts/realm/realm_hub.gd").new()
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
var career_id := ""            # career_ladders.gd key, "" = none yet
var career_rank := ""          # rank id within that career
var career_since_day := 0      # WorldSim.day the current rank began
var career_sponsor_tier := 0   # best sponsor's Relationships tier rank (>= 4 = friend)
const RECORD_TO_MASTERY := {
	"helped_farmer": "farming", "farmed": "farming", "hunted": "hunting", "fished": "fishing",
	"trained_sword": "swordsmanship", "trained_bow": "archery", "traded": "trading",
	"adventured": "soldiering", "studied": "scholarship", "meditated": "faith", "worked": "farming",
}
const ORG_TO_CAREER := {"guard": "soldier", "smithy": "blacksmith", "inn": "innkeeper"}
var homestead := preload("res://scripts/sim/homestead.gd").new()
## Hidden childhood leanings, the Blessing/Awakening and the childhood event
## pool (see docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Life stages").
var tendencies := preload("res://scripts/sim/tendencies.gd").new()
var childhood_events := preload("res://scripts/sim/childhood_events.gd").new()
var awakening := preload("res://scripts/sim/awakening.gd").new()
const LifeEventPopup := preload("res://scripts/ui/life_event_popup.gd")
## Blessing tier -> magicule pool growth granted at the ceremony.
const _AWAKENING_MAGICULES := {"faint": 5.0, "common": 10.0, "strong": 18.0, "exceptional": 25.0}
var _hud: Node = null
## Scout offers waiting for an answer: [event]
var pending_offers: Array = []
const GUILD_MIN_AGE := 12
var needs := RANeeds.new()
var market := RAMarket.new()
## Regional markets, caravans, contracts; Ashford keeps using `market` (docs/RISING_ASHES_LIFE_SIM_DESIGN.md).
var economy := preload("res://scripts/sim/economy.gd").new()
var inventory: Inventory
## Dirty-flagged save containers (scripts/sim/save_containers.gd); the SaveManager sees them via `saves.containers`.
var save_containers := SaveContainers.new()
var player: Node3D        # set by main once the player exists

var _last_abs := -1.0     # absolute in-game hours at the last tick
const NO_CLOCK := -1.0e9  # `_spoil_abs` before the first day tick
var _spoil_abs := NO_CLOCK   # absolute in-game hours the pack's food was last aged to


func _ready() -> void:
	WorldSim.hour_changed.connect(_on_hour)
	_new_life()


## Every state object of a run (recreated by reset()).
const STATE := ["life_path", "titles", "triggers", "careers", "guild", "magicules", "naming", "injuries", "scouts",
	"discovery", "relationships", "npc_social_graph", "radiant", "crafting", "equipment", "skills", "mastery", "biography", "property",
	"nobility", "lordship", "family", "soul", "skill_evolution", "echoes", "life_courses", "war", "realm",
	"homestead", "tendencies", "childhood_events", "awakening", "needs", "market", "economy"]


## A brand-new run: Game, WorldSim, Frontier, Region 1 and every object Life owns go back to their
## initial state and the first life begins again (New Game after "Exit to Main Menu"). The saved
## Flow.creation is applied by _begin_life, so call this after it is set (or {}) and apply_creation
## again afterwards if the choices arrive later. Settings and save slots are untouched.
func reset() -> void:
	player = null
	_hud = null
	Game.reset()
	WorldSim.reset()
	UtilityBrain.clear_sound_events()
	UtilityBrain.clear_transient_social()
	Frontier.reset()
	Region1State.reset()
	world_state.call("clear")
	preload("res://scripts/population/evidence.gd").reset()
	var qw := get_node_or_null("/root/QuestWeaverGameState")
	if qw and qw.has_method("load_from_data"):
		qw.call("load_from_data", {})
	const MenuData := preload("res://scripts/ui/gamemenu/menu_data.gd")
	MenuData.quest_log.clear()
	if inventory and is_instance_valid(inventory):
		inventory.name = "OldInventory"
		remove_child(inventory)
		inventory.queue_free()
	for n: String in STATE:
		set(n, get(n).get_script().new())
	world_events = WorldEventLog.new()
	action_runtime = ActionRuntime.new()
	npc_activity_runtime = NpcActivityRuntime.new(action_runtime)
	_craft_station_actions.clear()
	pending_offers.clear()
	appearance = {}
	career_id = ""
	career_rank = ""
	career_since_day = 0
	career_sponsor_tier = 0
	saves.reset_autosave_clock()
	_new_life()
	inventory_changed.emit()
	employment_changed.emit()


## Wires the state objects together and begins the first life (boot, and again after reset()).
func _new_life() -> void:
	_spoil_abs = _abs_hours()
	equipment.clock = _abs_hours
	if not crafting.station_invalidated.is_connected(_on_craft_station_invalidated):
		crafting.station_invalidated.connect(_on_craft_station_invalidated)
	skills.breakthrough.connect(func(r: Dictionary) -> void:
		Game.say(String(r["text"]))
		if r["success"]:
			magicules.grow(float(r["magicule_growth"]), float(r["magicule_growth"]) * 0.05)
		elif int(r["damage"]) > 0 and player and player.has_method("set_health"):
			player.set_health(int(player.get("health")) - int(r["damage"])))
	inventory = Inventory.new()
	inventory.name = "PlayerInventory"
	inventory.protoset = load(PROTOSET)
	add_child(inventory)
	inventory.item_added.connect(func(_i: InventoryItem) -> void: inventory_changed.emit())
	inventory.item_removed.connect(func(_i: InventoryItem) -> void: inventory_changed.emit())
	# Dirty-flagged save container: the inventory is only re-serialized after one of its signals fired.
	save_containers.register("inventory", func() -> Dictionary: return inventory.serialize())
	var dirty_inv := func(_a: Variant = null, _b: Variant = null) -> void: save_containers.mark_dirty("inventory")
	inventory.item_added.connect(dirty_inv)
	inventory.item_removed.connect(dirty_inv)
	inventory.item_moved.connect(dirty_inv)
	inventory.item_property_changed.connect(dirty_inv)
	_setup_orgs()
	_setup_market()
	careers.player_changed.connect(func(text: String) -> void:
		Game.say(text)
		_on_career_post_changed()
		employment_changed.emit())
	crafting.crafted.connect(func(res: Dictionary) -> void:
		var sk := String(res.get("skill", ""))
		var item_id := String(res.get("item", ""))
		award_progress("craft", {"subject": item_id})
		world_events.publish("item_crafted", "player", "item:" + item_id if not item_id.is_empty() else "", _abs_hours(), {
			"skill": sk, "count": int(res.get("count", 0)), "quality": int(res.get("quality", 0)),
			"xp": int(res.get("xp", 0)), "tag": String(res.get("tag", "crafted")),
		})
		if mastery.DISCIPLINES.has(sk):
			mastery.gain(sk, float(res.get("xp", 0)) * 0.1, WorldSim.day)
		if sk in ["smithing", "forging", "blacksmithing"]:
			soul.gain("forge", float(res.get("xp", 0)) * 0.05, WorldSim.day)
			skill_evolution.record_use(_soul_element(), "forge", WorldSim.day)
		elif sk in ["alchemy", "herbalism"]:
			soul.gain("heal", float(res.get("xp", 0)) * 0.05, WorldSim.day)
			skill_evolution.record_use(_soul_element(), "heal", WorldSim.day)
		elif sk == "cooking":
			skill_evolution.record_use(_soul_element(), "hearth", WorldSim.day))
	soul.tier_up.connect(func(_idx: int, _id: String) -> void:
		var info: Dictionary = soul.tier_info()
		magicules.grow(float(info.get("pool", 0.0)), float(info.get("regen", 0.0)))
		if soul.tier() <= 3:
			Game.say("Your soul settles into a new tier: %s." % String(info.get("name", "?"))))
	soul.breakthrough_result.connect(func(r: Dictionary) -> void:
		Game.say(String(r.get("text", "")))
		if bool(r.get("success", false)):   # tier_up already grew the pool
			biography.add_highlight("Broke through to %s" % String(soul.tier_info().get("name", "")), WorldSim.day))
	soul.path_chosen.connect(func(_id: String) -> void:
		biography.add_highlight("Took up %s" % String(soul.path_info().get("name", "a Path")), WorldSim.day))
	skill_evolution.evolved.connect(func(evo: Dictionary) -> void:
		Game.say("Your %s has changed with use: %s." % [String(evo.get("element", "power")), String(evo.get("name", "?"))])
		biography.add_highlight("Awakened %s" % String(evo.get("name", "")), WorldSim.day))
	careers.vacancy_opened.connect(_on_vacancy)
	careers.vacancy_opened.connect(func(o: Dictionary, st: Dictionary) -> void: life_courses.on_vacancy(o, st, careers))
	childhood_events.life_courses = life_courses
	lordship.village_changed.connect(func(idx: int) -> void:
		var v: Dictionary = lordship.villages.get(idx, {})
		if not v.is_empty() and int(v.get("granted_day", -1)) == WorldSim.day and not bool(v.get("_noted", false)):
			v["_noted"] = true
			var place: String = lordship.settlement_name(idx)
			biography.start_chapter("lord", "", "lord", place, WorldSim.day)
			biography.add_highlight("Granted the village of %s" % place, WorldSim.day)
			Game.say("You are now lord of %s." % place))
	_last_abs = _abs_hours()
	give("bread", 2)
	_begin_life()
	life_path.birthday.connect(func(age: int) -> void:
		Game.say("Happy birthday! You are %d." % age)
		grown.emit(age)
		if age == ADULT_AGE:
			_coming_of_age())
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


# --- death ------------------------------------------------------------------------

## Share of the purse lost when the player is carried home after dying.
const DEATH_GOLD_LOSS := 0.10
const DEATH_INJURIES := ["bruised_ribs", "deep_cut"]


## The cost of dying and waking up at home: a tenth of the gold (thieves, the healer, a
## day's lost work) and a minor injury that heals by itself (Life.injuries, shown at the
## healer and in the character sheet). Returns {gold_lost, injury, text}.
func apply_death_penalty() -> Dictionary:
	var lost := clampi(int(round(Game.gold * DEATH_GOLD_LOSS)), 0, Game.gold)
	if lost > 0:
		Game.add_gold(-lost)
	var picked := ""
	for t: String in DEATH_INJURIES:
		if not injuries.has(t):
			picked = t
			break
	if picked != "":
		injuries.add(picked, WorldSim.day)
		magicules.apply_effects(injuries.effects())
	var inj_name := String(RAInjuries.info(picked).get("name", "")) if picked != "" else ""
	var text := "You wake at home, bruised."
	if lost > 0:
		text += " %d gold is gone from your purse." % lost
	if inj_name != "":
		text += " Injury: %s." % inj_name
	return {"gold_lost": lost, "injury": picked, "text": text}


# --- life from birth ------------------------------------------------------------

## A child of two real villagers, living in one of the village's houses.
func _begin_life() -> void:
	realm.warm_up()
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
	childhood_events.seed_from(WorldSim.SEED, life_path.full_name())
	apply_creation(preload("res://scripts/ui/frontend/flow.gd").creation)
	life_courses.seed_from(WorldSim.SEED)
	life_courses.populate_region(150, WorldSim.day)


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


## 0.58 of adult height at START_AGE (a small child), full height at ADULT_AGE.
## Clamped so a very young start (age 4) never scales the body unreasonably small.
func body_scale() -> float:
	return clampf(lerpf(0.58, 1.0, (age() - START_AGE) / float(ADULT_AGE - START_AGE)), 0.55, 1.0)


func record(tag: String, weight := 1.0) -> void:
	life_path.record(tag, weight, WorldSim.day)
	tendencies.record(tag, weight)
	if RECORD_TO_MASTERY.has(tag):
		mastery.gain(RECORD_TO_MASTERY[tag], weight, WorldSim.day)
	if RECORD_TO_SOUL.has(tag):
		soul.gain(RECORD_TO_SOUL[tag], weight, WorldSim.day)
		if tag in ["farmed", "helped_farmer"]:
			skill_evolution.record_use(_soul_element(), "farm", WorldSim.day)
		elif tag == "meditated":
			skill_evolution.record_use(_soul_element(), "meditate", WorldSim.day)
	world_events.publish("life_action_recorded", "player", "", _abs_hours(), {
		"tag": tag, "weight": weight, "day": WorldSim.day,
	})


## Applies the New Game character-creation choices (name, family, look, leanings, parents' trades).
func apply_creation(c: Dictionary) -> void:
	if c == null or c.is_empty():
		return
	var lp := life_path
	lp.given_name = String(c.get("given_name", lp.given_name))
	var fam := String(c.get("family_name", ""))
	if fam != "":
		lp.family_name = fam
		for p in lp.parents:
			p["name"] = "%s %s" % [String(p["name"]).get_slice(" ", 0), fam]
	appearance = c.get("appearance", {})
	tendencies.nudge_many(c.get("tendencies", {}))
	if String(c.get("birthplace", "")) != "":
		lp.set_flag("birthplace:" + String(c["birthplace"]))
	if String(c.get("culture", "")) != "":
		lp.set_flag("culture:" + String(c["culture"]))
	var trades := {"father": String(c.get("father_trade", "")), "mother": String(c.get("mother_trade", ""))}
	for p in lp.parents:
		var idx: int = WorldSim.JOBS.find(trades.get(String(p["role"]), ""))
		if idx >= 0 and int(p["id"]) >= 0:
			WorldSim.job[int(p["id"])] = idx


## The element the player's Blessing gave ("qi" when none): what their power grows from.
func _soul_element() -> String:
	return awakening.element if awakening.element != "" else "qi"


## Query recent persistent facts without exposing the mutable journal itself.
func recent_world_events(after_id: int = 0, limit: int = 32, type_filter: String = "") -> Array[Dictionary]:
	return world_events.since(after_id, limit, type_filter)


func world_event_window(after_id: int = -1) -> Dictionary:
	return world_events.window_info(after_id)


func begin_craft_action(recipe_id: String, lease_s: float, requested_kinds: Array = []) -> Dictionary:
	var now_s := Time.get_ticks_msec() / 1000.0
	action_runtime.expire(now_s, 8)
	_prune_craft_station_actions(now_s)
	var recipe: Dictionary = crafting.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "token": "", "error": "unknown_recipe"}
	var required: Array = recipe.get("stations", [])
	var station: Dictionary = {}
	var resources: Array = ["actor:player"]
	var station_ref := ""
	var station_generation := 0
	var station_kind := ""
	if not required.is_empty():
		if player == null or not is_instance_valid(player):
			return {"ok": false, "token": "", "error": "station_required"}
		station = crafting.nearest_station_for_recipe(player.global_position, recipe_id, requested_kinds)
		if station.is_empty():
			return {"ok": false, "token": "", "error": "station_required"}
		station_ref = String(station.get("ref", ""))
		station_generation = int(station.get("generation", 0))
		station_kind = String(station.get("kind", ""))
		resources.append(crafting.station_resource_key(station_ref, station_generation))
	var payload := {"recipe_id": recipe_id, "station_ref": station_ref,
		"station_generation": station_generation, "station_kind": station_kind}
	var started: Dictionary = action_runtime.begin_resources("player", "craft", resources,
		now_s, lease_s, payload)
	if not bool(started.get("ok", false)):
		return started
	if not action_runtime.transition(String(started["token"]), "begun", "working", now_s):
		action_runtime.cancel(String(started["token"]), "transition_failed")
		return {"ok": false, "token": "", "error": "transition_failed"}
	if not station_ref.is_empty():
		_craft_station_actions[String(started["token"])] = crafting.station_resource_key(station_ref, station_generation)
	return started


func commit_craft_action(token: String, recipe_id: String, requested_kinds: Array, ctx: Dictionary) -> Dictionary:
	var inspection: Dictionary = action_runtime.inspect(token)
	var action_info: Dictionary = inspection.get("action", inspection)
	var action_payload: Dictionary = action_info.get("payload", {})
	if (String(action_info.get("actor_ref", "")) != "player"
			or String(action_info.get("action_type", "")) != "craft"
			or String(action_payload.get("recipe_id", "")) != recipe_id):
		return {"ok": false, "newly_committed": false, "result": {}, "error": "action_mismatch"}
	if inspection.has("newly_committed"):
		var prior := inspection.duplicate(true)
		prior["newly_committed"] = false
		return prior
	var now_s := Time.get_ticks_msec() / 1000.0
	var station_ref := String(action_payload.get("station_ref", ""))
	var station_generation := int(action_payload.get("station_generation", 0))
	var station_kind := String(action_payload.get("station_kind", ""))
	var recipe: Dictionary = crafting.recipe(recipe_id)
	var required: Array = recipe.get("stations", [])
	var allowed_kinds: Variant = [station_kind] if not station_ref.is_empty() else null
	var check := func() -> String:
		if not station_ref.is_empty():
			if player == null or not is_instance_valid(player):
				return "station_changed"
			var current: Dictionary = crafting.station_at(station_ref, station_generation, player.global_position)
			if current.is_empty() or String(current.get("kind", "")) != station_kind:
				return "station_changed"
			if not required.has(station_kind) or (not requested_kinds.is_empty() and not requested_kinds.has(station_kind)):
				return "station_changed"
		elif not required.is_empty():
			return "station_changed"
		return String(crafting.call("can_craft", recipe_id, self, allowed_kinds, ctx))
	var apply := func() -> Dictionary:
		return crafting.call("craft", recipe_id, self, allowed_kinds, ctx)
	var result: Dictionary = action_runtime.commit(token, now_s, check, apply)
	_craft_station_actions.erase(token)
	return result


func cancel_action(token: String) -> Dictionary:
	var result: Dictionary = action_runtime.cancel(token)
	_craft_station_actions.erase(token)
	return result


func _on_craft_station_invalidated(ref: String, generation: int) -> void:
	var resource_key: String = crafting.station_resource_key(ref, generation)
	for token: String in _craft_station_actions.keys():
		if String(_craft_station_actions[token]) == resource_key:
			action_runtime.cancel(token, "station_unloaded")
			_craft_station_actions.erase(token)


func _prune_craft_station_actions(now_s: float) -> void:
	for token: String in _craft_station_actions.keys():
		var state: Dictionary = action_runtime.inspect(token)
		if not state.has("phase") or (String(state.get("phase", "")) != "committing"
				and now_s >= float(state.get("expires_at", 0.0))):
			_craft_station_actions.erase(token)


func _craft_station_kinds_near_player() -> Array:
	if player == null or not is_instance_valid(player):
		return []
	var result: Array = []
	for station: Dictionary in crafting.call("stations_near", player.global_position):
		var kind := String(station.get("kind", ""))
		if not kind.is_empty() and not result.has(kind):
			result.append(kind)
	return result


## TechniqueCaster reports every successful cast: Soul Power, and the element
## evolving toward how it is used (a fight vs. training alone).
func on_technique_cast(_id: String, def: Dictionary, in_combat: bool) -> void:
	soul.gain("combat" if in_combat else "technique", 0.5, WorldSim.day)
	var el := String(def.get("element", _soul_element()))
	skill_evolution.record_use(el if el != "" else "qi", "combat" if in_combat else "technique", WorldSim.day)


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
	if hour == 0:
		_career_daily()
		for msg: String in homestead.daily_tick(WorldSim.day):
			Game.say(msg)
	for msg: String in skills.sync_progress(skills.ctx_from_life(self)):
		Game.say(msg)
	if player and is_instance_valid(player):
		var p := Vector2(player.global_position.x, player.global_position.z)
		triggers.check(p, age(), float(hour), life_path.flags)
		_life_events_tick(p, hour)


# --- childhood, tendencies and the Blessing -----------------------------------------

## The smallest place kind a childhood event cares about (see childhood_events.gd's
## "place" condition): "home" / "settlement" close to the family house or the
## village, "forest_edge" / "road" from place_at()'s named places, else "outskirts".
func _place_kind(pos: Vector2) -> String:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var r: float = home["radius"]
	var d := pos.distance_to(c)
	if d < r * 0.35:
		return "home"
	if d < r:
		return "settlement"
	match String(place_at(pos).get("kind", "")):
		"forest":
			return "forest_edge"
		"road":
			return "road"
		_:
			return "outskirts"


## While a child or adolescent: rolls the childhood event pool at a gentle rate
## and, once at 12 in the home settlement, runs the Blessing ceremony.
func _life_events_tick(pos: Vector2, hour: int) -> void:
	var a := age()
	if a >= ADULT_AGE:
		return
	var place := _place_kind(pos)
	if hour >= 6 and hour <= 21:
		var now_days := float(WorldSim.day) + float(hour) / 24.0
		var ev := childhood_events.roll(a, place, WorldSim.season, life_path.flags, now_days)
		if not ev.is_empty():
			childhood_events.mark_seen(String(ev["id"]), now_days, life_path.birth_day, life_path.home_settlement, "caldric")
			_present_childhood_event(ev)
	if a == 12 and not awakening.has_happened() and hour == 7 and place in ["home", "settlement"]:
		_run_awakening()


func _find_hud() -> Node:
	if _hud != null and is_instance_valid(_hud):
		return _hud
	if not is_inside_tree():
		return null
	_hud = _find_hud_in(get_tree().root)
	return _hud


static func _find_hud_in(n: Node) -> Node:
	if n is HUD:
		return n
	for c in n.get_children():
		var r := _find_hud_in(c)
		if r != null:
			return r
	return null


func _present_childhood_event(ev: Dictionary) -> void:
	var hud := _find_hud()
	if hud == null:
		return
	var opts: Array = []
	for c: Dictionary in ev.get("choices", []):
		opts.append([String(c.get("text", "…")), _childhood_choice.bind(c)])
	LifeEventPopup.present(hud, {"title": "Growing Up", "body": String(ev.get("text", "")), "choices": opts})


func _childhood_choice(c: Dictionary) -> void:
	tendencies.nudge_many(c.get("tendency", {}))
	for f: String in c.get("flags", []):
		life_path.set_flag(f)
	var bond: Dictionary = c.get("bond", {})
	for role: String in bond:
		life_path.adjust_bond(role, float(bond[role]))
	if c.has("item"):
		give(String(c["item"]), 1)
	if "befriended_rival" in c.get("flags", []):
		childhood_events.on_rival_befriended()


## The age-12 Blessing ceremony: a popup, a magic circle underfoot, the outcome
## stored as flags (dialogue and skills read "blessing:<element>" /
## "blessing_tier:<tier>" / "blessing_dual" / "blessing:none"), and starting
## Soul Power by tier.
func _run_awakening() -> void:
	var culture := "caldric"
	var r := awakening.roll(tendencies, culture, WorldSim.SEED, life_path.full_name(), WorldSim.day)
	for f: String in awakening.flags():
		life_path.set_flag(f)
	_grant_blessing(r)
	if player and is_instance_valid(player):
		VFX.magic_circle(player.get_parent(), player.global_position,
			awakening.element if awakening.element != "" else "qi", 2.4, 3.5)
	var hud := _find_hud()
	var body := _awakening_text(r)
	if hud:
		LifeEventPopup.present(hud, {"title": "The Blessing", "body": body, "choices": [["...", Callable()]]})
	else:
		Game.say(body)


func _awakening_text(r: Dictionary) -> String:
	if bool(r.get("none", false)):
		return "The bell tolls, the temple lights every candle it has, and... nothing answers. No element comes to you. Whatever you become, you will make yourself."
	var tier_words := {"faint": "the faintest whisper of", "common": "a clear, steady", "strong": "a strong",
		"exceptional": "an extraordinary"}
	var el: String = r["element"]
	var text := "The temple bell tolls, and %s leaning toward %s answers your call." % [
		tier_words.get(String(r["tier"]), "a"), el]
	if String(r.get("dual", "")) != "":
		text += " A second element, %s, answers too — rare enough that the whole village will talk about it." % String(r["dual"])
	return text


func _grant_blessing(r: Dictionary) -> void:
	soul.set_blessing(String(r.get("element", "")), String(r.get("dual", "")))
	if bool(r.get("none", false)):
		magicules.grow(3.0, 0.02)
		return
	var tier := String(r.get("tier", "common"))
	var bonus := float(_AWAKENING_MAGICULES.get(tier, 10.0))
	magicules.grow(bonus, bonus * 0.03)
	var tech := awakening.first_technique(String(r.get("element", "")))
	if tech != "":
		skills.grant(tech)
	var dual := String(r.get("dual", ""))
	if dual != "":
		var dual_tech := awakening.first_technique(dual)
		if dual_tech != "":
			skills.grant(dual_tech)
		magicules.grow(bonus * 0.5, 0.0)
	if tier in ["strong", "exceptional"]:
		skills.award_points(2 if tier == "exceptional" else 1, "blessing:" + tier)


## Age 16: "The world is yours now." Summarises the childhood from tendencies
## and flags. (No hard gate on child travel was found to lift; the flag and
## summary mark the transition for dialogue and other systems.)
func _coming_of_age() -> void:
	life_path.set_flag("came_of_age")
	var body := _childhood_summary()
	var hud := _find_hud()
	if hud:
		LifeEventPopup.present(hud, {"title": "The World Is Yours Now", "body": body, "choices": [["Step forward.", Callable()]]})
	else:
		Game.say(body)


func _childhood_summary() -> String:
	var lines := PackedStringArray()
	lines.append("You are sixteen. The world is yours now.")
	lines.append(tendencies.describe())
	if life_path.has_flag("blessing:none"):
		lines.append("No Blessing ever came for you. Whatever you become, you'll make yourself.")
	elif life_path.has_flag("blessing_dual"):
		lines.append("Two elements answered your Blessing, rare enough that people still whisper about it.")
	for f: String in life_path.flags:
		if f.begins_with("apprentice:"):
			lines.append("Years apprenticed in the %s shaped your hands." % f.trim_prefix("apprentice:"))
	return "\n".join(lines)


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
	Game.say("%s of %s has been watching you. Open Pack → Journal → Scouting Offers to answer." % [
		sc.get("name", "A stranger"), org.get("name", "somewhere")])


func answer_offer(event_id: int, yes: bool) -> String:
	var e := scouts.offer(event_id)
	if e.is_empty():
		return "That offer has expired."
	if WorldSim.day > int(e.get("offer", {}).get("expires_day", -1)):
		scouts.tick_day(WorldSim.day)
		for pending: Dictionary in pending_offers.duplicate():
			if int(pending.get("id", -1)) == event_id:
				pending_offers.erase(pending)
		return "That offer has expired."
	for pending: Dictionary in pending_offers.duplicate():
		if int(pending.get("id", -1)) == event_id:
			pending_offers.erase(pending)
	if not yes:
		scouts.decline(event_id)
		return "You decline, politely."
	var accepted := scouts.accept(event_id, WorldSim.day)
	if accepted.is_empty():
		return "That offer has expired."
	var org_id := String(accepted["org"].get("id", "?"))
	life_path.set_flag("recruited:" + org_id)
	if bool(accepted["offer"].get("soulbeast_path", false)):
		life_path.set_flag("permit:xiava_lake")
	var org_name := String(accepted["org"].get("name", "the organization"))
	biography.add_highlight("Accepted a recruitment offer from %s" % org_name, WorldSim.day)
	var bonus := int(accepted["offer"].get("signing_bonus", 0))
	if bonus > 0:
		Game.add_gold(bonus)
		return "You accept the offer from %s and receive %d gold to begin." % [org_name, bonus]
	return "You accept the offer from %s." % org_name


## Effective level for naming: grows with merit, reduced while levels are lost to naming.
func player_level() -> int:
	var prog: Variant = _progression()
	if prog != null:
		return int(prog.level)   # docs/balance/PROGRESSION_R1.md hook: the cultivation module owns the level curve
	return maxi(1, 1 + int(sqrt(float(Game.merit))) + age() / 4 - naming.level_penalty(WorldSim.day))


## Item effects only world systems can apply (equipment.consume calls this): pills, manuals/scrolls, coatings, recall,
## wards, reveals. Returns a short line for the toast, or "" when nothing happened (the item is still spent).
func apply_item_effect(id: String, info: Dictionary) -> String:
	var cult: Variant = realm.mod("cultivation") if realm != null else null
	if info.has("cultivation_xp"):
		if cult == null or (cult.cultivating() as Array).is_empty():
			return "The pill's warmth fades; you aren't cultivating yet."
		return "Qi +%d." % int(cult.add_pill_qi(float(info["cultivation_xp"])))
	if info.has("breakthrough_bonus"):
		if cult != null:
			cult.pill_bonus = maxf(float(cult.pill_bonus), float(info["breakthrough_bonus"]))
		return "Your next breakthrough is steadier (+%d%%)." % int(round(float(info["breakthrough_bonus"]) * 100.0))
	if info.has("permanent_stat"):
		var stat := String(info["permanent_stat"])
		equipment.add_buff("Tempered body", stat, float(info.get("value", 5.0)), 24.0 * 365.0 * 200.0)
		return "Your %s grows for good." % stat.replace("_", " ")
	if info.has("casts"):
		var r: Dictionary = skills.grant(String(info["casts"]))
		if not bool(r.get("ok", true)):
			return String(r.get("text", ""))
		return "You learn %s." % String(skills.get_def(String(info["casts"])).get("name", String(info["casts"]).replace("_", " ")))
	if info.has("coating"):
		equipment.add_buff("%s coating" % String(info["coating"]).capitalize(), String(info["coating"]) + "_damage", float(info.get("value", 6.0)), 1.0)
		return "Your blade is coated for an hour."
	match String(info.get("effect", "")):
		"ward":
			equipment.add_buff("Ward", "armor", float(info.get("value", 8.0)), 2.0)
			return "A ward settles around you."
		"recall":
			if player != null and not WorldGen.settlements.is_empty():
				var home: Vector2 = WorldGen.settlements[0]["pos"]
				var near: Dictionary = WorldGen.nearest_settlement(Vector2(player.global_position.x, player.global_position.z))
				if near.has("pos"):
					home = near["pos"]
				player.global_position = Vector3(home.x, WorldGen.height(home.x, home.y) + 1.0, home.y)
				return "The world folds; you stand at the edge of town."
			return ""
		"reveal":
			if player != null:
				var pp := Vector2(player.global_position.x, player.global_position.z)
				for s: Dictionary in WorldGen.sites:
					if bool(s.get("secret", false)) and (s["pos"] as Vector2).distance_to(pp) < 400.0 and discovery.reveal_site(s, WorldSim.day):
						return "Hidden ways show themselves: %s." % String(s["name"])
			return "Nothing hidden lies near."
	return ""


## The character-level module (cultivation.prog), or null before the realm exists.
func _progression() -> Variant:
	if realm == null:
		return null
	var cult: Variant = realm.mod("cultivation")
	return cult.prog if cult != null and cult.get("prog") != null else null


## Progression hook (docs/balance/PROGRESSION_R1.md section 5): award XP for an activity. Null-safe.
func award_progress(activity: String, ctx: Dictionary = {}) -> void:
	var prog: Variant = _progression()
	if prog != null:
		var c := ctx.duplicate()
		c["day"] = WorldSim.day
		c["region"] = "region1"
		prog.award(activity, c)


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
		Audio.play_ui("quest_complete")
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
	market.add_good("scar_crystal", 40, 4, 0)   # Region1 hook C4: the Scar's harvest sells here too
	market.add_good("scarbloom", 18, 6, 0)
	preload("res://scripts/sim/gathering_items.gd").register(self)
	economy.setup(0)
	economy.bind_home_market(0, market)
	for id: String in ["iron_ingot", "leather", "plank", "arrowheads", "horseshoe", "healing_salve", "antidote", "stamina_draught", "grilled_fish", "berry_pie", "saddle"]:
		market.add_good(id, int(item_prop(id, "price", 1)), 4, 0)
		market.imports[id] = 0.15 * 1.67 * 4.0     # wagons bring a trickle (economy.gd, once a day) so crafting goods aren't sold out forever


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
	for msg: String in realm.pump():
		Game.say(msg)
	needs.tick(dh)
	magicules.regenerate(dh)
	if player and is_instance_valid(player):
		var p := Vector2(player.global_position.x, player.global_position.z)
		if careers.is_on_shift(WorldSim.time_of_day) and careers.at_post(p):
			careers.log_attendance(dh)
		var starve := needs.starvation() * dh
		if starve > 0.0 and player.has_method("take_damage") and randf() < starve:
			player.take_damage(1, null)


## Merchant contracts appear when markets run short, army orders during war,
## and the crown requisitions part of the farm's stores once a week in wartime.
func _contracts_daily() -> void:
	economy.expire_contracts(WorldSim.day)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED, "contracts", WorldSim.day])
	if economy.contracts.size() < 3 and WorldSim.day % 3 == 0:
		economy.roll_contract(WorldSim.day, rng)
	if war.is_at_war() and WorldSim.day % 5 == 0:
		var c: Dictionary = economy.add_war_contract(WorldSim.day, war.contract_for_merchant(WorldSim.day))
		if not c.is_empty():
			Game.say("The army quartermaster wants %d %s. See the market trader." % [int(c["amount"]), item_name(String(c["item"]))])
	var frac: float = war.crop_requisition_fraction()
	if frac > 0.0 and WorldSim.day % 7 == 0:
		var taken := 0
		for crop: String in homestead.storage.keys():
			var n := int(floor(int(homestead.storage[crop]) * frac))
			if n > 0:
				homestead.storage[crop] = int(homestead.storage[crop]) - n
				taken += n
		if taken > 0:
			Game.say("Crown requisition officers took %d sacks from your farm stores for the war." % taken)


func _realm_ctx() -> Dictionary:
	var pp := Vector2.ZERO
	if player and is_instance_valid(player):
		pp = Vector2(player.global_position.x, player.global_position.z)
	return {"player_pos": pp, "season": WorldSim.season, "at_war": war.is_at_war(),
		"abs_hours": _abs_hours(), "gold": Game.gold, "life": self}


func _on_hour(hour: int) -> void:
	realm.on_hour(hour, WorldSim.day, _realm_ctx())
	# War map authority follows the soldier career rank (none for civilians).
	var cam: RefCounted = realm.mod("campaign")
	if cam.has_method("set_player_rank"):
		cam.set_player_rank(CareerLadders.military_rank_for(career_rank) if career_id == "soldier" else "")
	# City life and society keep a signed ledger instead of touching the purse.
	for k: String in ["city_life", "society", "education", "household", "callups", "enterprise", "construction", "scribe", "trades"]:
		var m: RefCounted = realm.mod(k)
		if m != null and m.has_method("take_pending_gold"):
			var net := int(m.take_pending_gold())
			if net != 0:
				Game.add_gold(net)
	# Combat training is open to every career (education.training_options).
	var gains: Dictionary = realm.mod("education").take_pending_gains()
	if float(gains.get("combat", 0.0)) > 0.0:
		mastery.gain("swordsmanship", float(gains["combat"]), WorldSim.day)
	if hour == 6:
		# War first: economy, lordship levies and promotion speed read the at_war flag this hour.
		for msg: String in war.tick_day(WorldSim.day, {"feud_count": nobility.feuds().size(),
				"rift_instability": Frontier.rift_instability, "season": WorldSim.season}):
			Game.say(msg)
		life_path.set_flag("at_war", war.is_at_war())
	economy.refresh_road_risk(Frontier.runestones)
	for r: Dictionary in economy.tick_hour(1.0, {
			"season": WorldSim.season, "festival": not WorldSim.seasons.festival_today().is_empty(),
			"at_war": bool(life_path.flags.get("at_war", false)), "mine_opened": bool(life_path.flags.get("mine_opened", false)),
			"abs_hours": _abs_hours()}):
		Game.say(String(r["text"]))
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
	if hour == 6:
		for msg: String in property.daily(WorldSim.day):
			Game.say(msg)
		for msg: String in nobility.daily(WorldSim.day):
			Game.say(msg)
		for msg: String in lordship.daily_tick(WorldSim.day, {"season": WorldSim.season, "at_war": bool(life_path.flags.get("at_war", false))}):
			Game.say(msg)
		for msg: String in family.daily_tick(WorldSim.day):
			Game.say(msg)
		_contracts_daily()
		_spoilage_tick()
		var threat := 0.0
		if player and is_instance_valid(player):
			var t: Dictionary = Frontier.threat_at(Vector2(player.global_position.x, player.global_position.z))
			threat = float(t.get("total", t.get("threat", 0.0)))
		for msg: String in life_courses.tick_day(WorldSim.day, {"at_war": war.is_at_war(),
				"frontier_threat": clampf(threat, 0.0, 100.0), "careers": careers, "nobility": nobility}):
			Game.say(msg)
		if family.check_old_age_death(age(), WorldSim.day):
			_on_old_age_death()
	if hour == 5:
		for e: Dictionary in guild.tick_day(WorldSim.day):
			if e.get("type", "") == "failed":
				Game.say(String(e.get("text", "")))
		for h: Dictionary in injuries.tick_day(WorldSim.day):
			Game.say("Your %s has healed." % String(RAInjuries.info(String(h["type"])).get("name", "injury")).to_lower())
		magicules.apply_effects(injuries.effects())
		naming.tick_day(WorldSim.day)
		var expired_offers: Array = scouts.tick_day(WorldSim.day)
		for expired: Dictionary in expired_offers:
			for pending: Dictionary in pending_offers.duplicate():
				if int(pending.get("id", -1)) == int(expired.get("id", -2)):
					pending_offers.erase(pending)
			Game.say("The offer from %s has expired." % String(expired.get("scout", {}).get("name", "the recruiter")))
		_offer(scouts.daily_roll(scout_profile(), WorldSim.day))
		careers.tick_day(_hire)
		# Ashford's market (`market`) is bound into `economy` (see _setup_market) and ticks hourly there; ticking
		# it here too double-counted demand.


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


## Night camping on the road (scripts/world/travel_rules.gd): a Bedroll or Travel Tent used outdoors from dusk. Sleeps rough
## until morning (a tinderbox lights a fire), but the night can be interrupted: bandits or beasts (realm_encounters.on_camp),
## a thief, or a traveller at the fire with news. Returns the line for the toast; the kit is never used up.
func camp_here(_kit_id := "") -> String:
	var TR := preload("res://scripts/world/travel_rules.gd")
	if player == null or not is_instance_valid(player) or bool(player.get("dead")):
		return "You can't camp now."
	var pos := Vector2(player.global_position.x, player.global_position.z)
	var near: Dictionary = WorldGen.nearest_settlement(pos)
	var ratio := 99.0
	if not near.is_empty():
		ratio = pos.distance_to(near["pos"]) / maxf(float(near["radius"]), 1.0)
	var kit := TR.camp_kit({"bedroll": count("bedroll"), "tent_kit": count("tent_kit"), "tinderbox": count("tinderbox")})
	var enemies := false
	for e in get_tree().get_nodes_in_group("team1"):
		if e is Node3D and (e as Node3D).is_visible_in_tree() and (e as Node3D).global_position.distance_to(player.global_position) < 45.0:
			enemies = true
			break
	var why := TR.camp_block_reason(int(WorldSim.time_of_day), InteriorDoor.active != null, ratio, enemies, kit)
	if why != "":
		return why
	var eco: Variant = realm.mod("ecology") if realm != null else null
	var danger := {}
	if eco != null and eco.has_method("danger_at"):
		danger = eco.danger_at(pos)
	var sources: Array = danger.get("sources", [])
	var ri := WorldGen.road_info(pos.x, pos.y)
	var bandit_dist := 1.0e9
	for site: Dictionary in WorldGen.sites:
		if String(site.get("kind", "")) in ["bandit_camp", "hideout"]:
			bandit_dist = minf(bandit_dist, pos.distance_to(site["pos"]))
	var ctx := {"danger": float(danger.get("total", 0.0)), "road_dist": float(ri["dist"]), "bandit_dist": bandit_dist, "tier": String(ri["tier"]),
		"fire": bool(kit["fire"]), "tent": bool(kit["tent"]), "species": String((sources[0] as Dictionary).get("species", "")) if not sources.is_empty() else ""}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED, WorldSim.day, int(pos.x / 60.0), int(pos.y / 60.0)])
	var plan: Dictionary = TR.camp_outcome(ctx, rng.randf(), rng.randf())
	var quality := TR.camp_quality(kit)
	var night := TR.night_hours(WorldSim.time_of_day)
	var enc := get_tree().get_first_node_in_group("realm_encounters")
	var line := ""
	var slept := night
	match String(plan["outcome"]):
		"ambush":
			slept = clampf(float(plan["hours"]), 1.0, night)
			line = "You are woken by %s." % ("shouting outside the tent" if String(plan["foe"]) == "bandits" else "growls beyond the firelight")
		"thief":
			slept = clampf(float(plan["hours"]), 1.0, night)
			var lost := mini(Game.gold, maxi(5, int(Game.gold * 0.12)))
			Game.add_gold(-lost)
			line = "You wake to find a thief gone, and %d gold with him." % lost if lost > 0 else "You wake to a thief's footsteps, and he leaves empty-handed."
		"visitor":
			line = "A traveller shares your fire and the road's news."
	needs.sleep(slept, quality)
	WorldSim.advance_hours(slept)
	_last_abs = _abs_hours()
	player.heal(int(20 * slept * quality))
	if slept >= night - 0.01 and player.get("stamina") != null:
		player.set("stamina", 100.0)
	record("camped")
	if String(plan["outcome"]) == "ambush" and enc != null and enc.has_method("on_camp"):
		enc.on_camp(String(plan["foe"]), String(plan["species"]), ctx)
	elif String(plan["outcome"]) == "visitor" and enc != null and enc.has_method("camp_visitor"):
		enc.camp_visitor()
	if line == "":
		line = "You sleep %d hours under the stars and wake %s." % [int(slept), needs.rest_label().to_lower()]
	return line


# --- merit & rank ----------------------------------------------------------------

func add_merit(amount: int, reason: String) -> void:
	Game.merit += amount
	Game.say("+%d merit: %s" % [amount, reason])
	var up := careers.promotion_for_player(Game.merit)
	if not up.is_empty():
		Game.say("A %s's seat is open in %s. Report to the %s." % [up["title"], careers.player_org()["name"],
			careers.player_org()["recruiter"]])


func on_monster_killed(species: String) -> void:
	award_progress("kill", {"subject": species, "magnitude": 1})
	region1_kill.emit(species, player.global_position if player and is_instance_valid(player) else Vector3.ZERO)
	guild.on_kill(RAAdventurerGuild.PLAYER, species, -1)
	add_merit(12 if species == "orc" else 6, "%s slain" % species)
	record("hunted")


func on_wolf_killed(_where: Vector3, den_id := -1, variant := "") -> void:
	award_progress("kill", {"subject": "rift_wolf" if variant != "" else "wolf", "magnitude": 1})
	var r1_species := variant if variant != "" else "wolf"
	if den_id >= 0 and den_id < Frontier.ecology.dens.size() and String(Frontier.ecology.dens[den_id].get("species", "wolf")) == "corrupted_wolf":
		r1_species = "rift_wolf"
	elif den_id >= 0 and den_id < Frontier.ecology.dens.size() and String(Frontier.ecology.dens[den_id].get("species", "")) == "stagborn_warden":
		r1_species = "stagborn_warden"      # Region 1 story: the Antlered Warden's defeat (r1_story_director.gd)
	region1_kill.emit(r1_species, _where)
	for c: Dictionary in guild.on_kill(RAAdventurerGuild.PLAYER, "wolf", den_id):
		if guild.is_ready(int(c["id"])):
			Game.say("Commission ready to turn in: %s" % c.get("title", ""))
	add_merit(5, "wolf slain")
	record("hunted")
	if den_id >= 0 and den_id < Frontier.ecology.dens.size():
		var species := String(Frontier.ecology.dens[den_id].get("species", "wolf"))
		if species in ["troll", "bear", "wyvern", "corrupted_wolf"]:
			soul.gain("hunt", 4.0, WorldSim.day)
			if species != "corrupted_wolf" or randf() < 0.25:
				echoes.add_echo(species + "_echo", "the " + species.replace("_", " "), WorldSim.day, 1.0)
				Game.say("Something of the %s lingers with you: an Echo." % species.replace("_", " "))
	give("wolf_pelt", 1)
	if randf() < 0.6:
		give("wolf_meat", 1)


# --- inventory -----------------------------------------------------------------

func count(item: String) -> int:
	var n := 0
	for it in inventory.get_items_with_prototype_id(item):
		n += it.get_stack_size()
	return n


## Mean quality tier (0 rough, 1 fine, 2 masterwork) of the carried stacks of `item`, -1 when none carried.
## Feeds Crafting.input_grade so better materials give better products.
func quality_of(item: String) -> int:
	var sum := 0.0
	var n := 0
	for it in inventory.get_items_with_prototype_id(item):
		var q := int(it.get_property("quality", 1))
		sum += float(q) * float(it.get_stack_size())
		n += it.get_stack_size()
	return int(round(sum / float(n))) if n > 0 else -1


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


# --- food spoilage ---------------------------------------------------------------------------------------------------
# Food with spoil data (ItemsDB.spoil_hours) ages in the pack: each stack carries an `age_hours` property (absent = fresh) that
# grows on the realm day tick (hour 6, see _on_hour) by the game time elapsed since the last time, in ONE step however long
# that was (sleep, fast travel, waiting). Past its shelf life a stack turns into its `spoils_into` item (Spoiled Food);
# before that, stale food gives less nutrition (use_item). Cured / smoked / salted / dried food has a long shelf life in the data.

## Called once a day (hour 6) and after skipping time: ages the pack by the game time since the last call.
func _spoilage_tick() -> void:
	var now := _abs_hours()
	if _spoil_abs <= NO_CLOCK or now < _spoil_abs:
		_spoil_abs = now
		return
	var elapsed := now - _spoil_abs
	if elapsed < 1.0:
		return
	_spoil_abs = now
	age_pack(elapsed)


## Ages every food stack in the pack by `hours` game hours (closed form). Returns {aged, spoiled}: stacks aged and items turned bad.
func age_pack(hours: float) -> Dictionary:
	var out := {"aged": 0, "spoiled": 0}
	if hours <= 0.0 or inventory == null:
		return out
	var spoiled: Array = []         # [spoiled id, count, name of the good item]
	for it: InventoryItem in inventory.get_items().duplicate():
		var id := it.get_prototype().get_prototype_id()
		if ItemsDB.spoil_hours(id) <= 0.0:
			continue
		var r := ItemsDB.age_by(id, float(it.get_property(ItemsDB.AGE_PROP, 0.0)), hours)
		out["aged"] += 1
		if String(r["into"]) != "":
			spoiled.append([String(r["into"]), it.get_stack_size(), item_name(id)])
			inventory.remove_item(it)
		else:
			it.set_property(ItemsDB.AGE_PROP, float(r["age"]))
	for s: Array in spoiled:
		give(String(s[0]), int(s[1]))
		out["spoiled"] += int(s[1])
		Game.say("%d %s spoiled in your pack." % [int(s[1]), String(s[2]).to_lower()])
	# Stacks of one kind that now share an age merge back into one.
	for it: InventoryItem in inventory.get_items().duplicate():
		if is_instance_valid(it) and it.has_property(ItemsDB.AGE_PROP) and it.get_inventory() == inventory:
			inventory.pack_item(it)
	inventory_changed.emit()
	return out


## Age in game hours of the stack `take(item)` consumes first (the first stack of that id); 0 = fresh.
func food_age(item: String) -> float:
	for it in inventory.get_items_with_prototype_id(item):
		return float(it.get_property(ItemsDB.AGE_PROP, 0.0))
	return 0.0


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
	nutrition *= ItemsDB.freshness(item, food_age(item))     # stale food feeds less (spoilage)
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
	var gov: Variant = realm.mod("governance")   # CIV-B law hook: banned monster-part trade
	if gov != null:
		var refusal: String = gov.refuses_item(int(realm.mod("city_life").near_settlement()), item)
		if refusal != "":
			return refusal
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
		"economy": economy.serialize(),
		"inventory": save_containers.snapshot()["inventory"],
		"spoil_abs": _spoil_abs,
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
		"relationships": relationships.serialize(),
		"npc_social_graph": npc_social_graph.serialize(),
		"mastery": mastery.serialize(),
		"biography": biography.serialize(),
		"property": property.serialize(),
		"nobility": nobility.serialize(),
		"lordship": lordship.serialize(),
		"family": family.serialize(),
		"life_courses": life_courses.serialize(),
		"war": war.serialize(),
		"realm": realm.serialize(),
		"soul": soul.serialize(),
		"skill_evolution": skill_evolution.serialize(),
		"echoes": echoes.serialize(),
		"appearance": appearance,
		"career": {"id": career_id, "rank": career_rank, "since_day": career_since_day, "sponsor_tier": career_sponsor_tier},
		"radiant": radiant.serialize(),
		"crafting": crafting.serialize(),
		"world_events": world_events.serialize(),
		"equipment": equipment.serialize(),
		"skills": skills.serialize(),
		"homestead": homestead.serialize(),
		"tendencies": tendencies.serialize(),
		"childhood_events": childhood_events.serialize(),
		"awakening": awakening.serialize(),
	}
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	d["region1"] = Region1State.snapshot()
	var interactives: Dictionary = world_state.call("snapshot")
	interactives["evidence"] = preload("res://scripts/population/evidence.gd").serialize()
	# Search, knocked-out / killed people and the town's guard alert (all clock-relative).
	var now_ms := Time.get_ticks_msec()
	interactives["search"] = preload("res://scripts/population/search.gd").serialize(now_ms)
	interactives["takedown"] = preload("res://scripts/combat/takedown.gd").serialize(now_ms)
	interactives["guard_alert"] = preload("res://scripts/population/alert_net.gd").serialize(now_ms)
	d["interactives"] = interactives
	if player and is_instance_valid(player):
		d["player"] = {"x": player.global_position.x, "y": player.global_position.y,
			"z": player.global_position.z, "health": player.get("health")}
	return d


func restore(d: Dictionary) -> void:
	action_runtime.reset()
	_craft_station_actions.clear()
	UtilityBrain.clear_sound_events()
	UtilityBrain.clear_transient_social()
	# Optional social data must not leak across loading an older/empty save.
	npc_social_graph = NpcSocialGraph.new()
	# Older saves simply start a fresh journal. Invalid new journal data is isolated
	# from the rest of the save so existing player state still restores normally.
	world_events = WorldEventLog.new()
	if d.has("world_events"):
		var event_data: Variant = d["world_events"]
		if not event_data is Dictionary or not world_events.deserialize(event_data):
			world_events = WorldEventLog.new()
			push_warning("Ignoring invalid saved world event journal.")
	var cd: Dictionary = d.get("career", {})
	career_id = String(cd.get("id", ""))
	career_rank = String(cd.get("rank", ""))
	career_since_day = int(cd.get("since_day", 0))
	career_sponsor_tier = int(cd.get("sponsor_tier", 0))
	WorldSim.deserialize(d.get("world", {}))
	UtilityBrain.restore_active_needs()
	Game.deserialize(d.get("game", {}))
	careers.deserialize(d.get("careers", {}))
	for o in careers.orgs:
		for s: Dictionary in o["seats"]:
			for who: int in s["holders"]:
				if who >= 0:
					WorldSim.job[who] = o["job"]
	needs.deserialize(d.get("needs", {}))
	market.deserialize(d.get("market", {}))
	economy.deserialize(d.get("economy", {}), 0, market)
	inventory.deserialize(d.get("inventory", {}))
	save_containers.mark_all()
	_spoil_abs = float(d.get("spoil_abs", NO_CLOCK))
	Frontier.deserialize(d.get("frontier", {}))
	if d.has("life_path"):
		life_path.deserialize(d["life_path"])
		titles.deserialize(d.get("titles", {}))
		triggers.deserialize(d.get("triggers", {}))
	for key: String in ["guild", "magicules", "naming", "injuries", "scouts", "discovery", "relationships", "npc_social_graph", "radiant", "crafting", "equipment", "skills", "homestead", "tendencies", "childhood_events", "awakening", "mastery", "biography", "property", "nobility", "lordship", "family", "life_courses", "war", "soul", "skill_evolution", "echoes", "realm"]:
		if d.has(key):
			get(key).deserialize(d[key])
	appearance = d.get("appearance", {})
	if player and is_instance_valid(player) and player.has_method("apply_appearance"):
		player.apply_appearance()
	realm.warm_up()
	_last_abs = _abs_hours()
	if d.has("player") and player and is_instance_valid(player):
		var p: Dictionary = d["player"]
		player.global_position = Vector3(p["x"], p["y"], p["z"])
		if bool(player.get("dead")) and player.has_method("revive"):
			player.revive(false)     # a save loaded from the death screen
		if player.has_method("set_health"):
			player.set_health(int(p.get("health", 100)))
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	Region1State.restore(d.get("region1", {}))
	# Two-phase: only the dictionaries load here; each door / chest pulls its own state by id when it is built.
	world_state.call("restore", d.get("interactives", {}))
	var inter: Variant = d.get("interactives", {})
	preload("res://scripts/population/evidence.gd").deserialize(inter.get("evidence", []) if inter is Dictionary else [])
	var inter_d: Dictionary = inter if inter is Dictionary else {}
	var now_ms2 := Time.get_ticks_msec()
	preload("res://scripts/combat/takedown.gd").deserialize(inter_d.get("takedown", []), now_ms2)       # after Evidence: re-links bodies
	preload("res://scripts/population/search.gd").deserialize(inter_d.get("search", []), now_ms2)
	preload("res://scripts/population/alert_net.gd").deserialize(inter_d.get("guard_alert", []), now_ms2)
	inventory_changed.emit()
	employment_changed.emit()
	Game.stats_changed.emit()


## Slots, autosaves, backups and migration live in scripts/sim/save_manager.gd
## (JSON in user://saves/). The old single file user://save_N.json (SAVE_PATH)
## is moved into manual slot N on first run. `saves.last_error` explains failures.
const SaveManager := preload("res://scripts/sim/save_manager.gd")
var saves: Node = _make_save_manager()


func _make_save_manager() -> Node:
	var m: Node = SaveManager.new()
	m.name = "SaveManager"
	add_child(m)
	# Focus-loss autosaves skip a clean game (scripts/sim/save_manager.gd is_dirty).
	inventory_changed.connect(m.mark_dirty)
	m.watch = save_containers
	return m


## Slot 1-3: manual slots (the old API); 0: the quicksave.
func _slot_id(slot: int) -> String:
	return SaveManager.QUICK if slot == 0 else SaveManager.manual_id(clampi(slot, 1, SaveManager.MANUAL_SLOTS))


func save_game(slot := 1) -> bool:
	return saves.save_slot(_slot_id(slot))


func load_game(slot := 1) -> bool:
	return saves.load_slot(_slot_id(slot))


func has_save(slot := 1) -> bool:
	return saves.has_slot(_slot_id(slot))


func quick_save() -> bool:
	return saves.quick_save()


func quick_load() -> bool:
	return saves.quick_load()


## Loads the newest save of any kind (manual, quick or auto).
func load_latest() -> bool:
	var id: String = saves.latest_id()
	return id != "" and saves.load_slot(id)


## Autosave hook for other systems (sleep, fast travel, quest steps). Returns the
## slot used, or "" when skipped (combat, cutscene, just saved).
func autosave(reason := "auto") -> String:
	return saves.autosave(reason)


## A new post at an org starts (or continues) a biography chapter on the matching ladder.
func _on_career_post_changed() -> void:
	if not careers.is_employed():
		return
	var org_id := String(careers.player["org"])
	if not ORG_TO_CAREER.has(org_id):
		return
	var cid: String = ORG_TO_CAREER[org_id]
	if cid != career_id:
		career_id = cid
		career_rank = CareerLadders.first_rank(cid)
		career_since_day = WorldSim.day
		var place := String(WorldGen.settlements[0]["name"]) if not WorldGen.settlements.is_empty() else ""
		biography.start_chapter(cid, org_id, career_rank, place, WorldSim.day)


## Once a day: promotion on the current ladder when every requirement is met.
func _career_daily() -> void:
	if career_id == "":
		return
	# The scribe career promotes itself (patron, exams, counters): scripts/realm/scribe.gd.
	if career_id == "scribe":
		return
	var ctx := {
		"career": career_id, "rank": career_rank, "since_day": career_since_day, "day": WorldSim.day,
		"mastery": mastery, "biography": biography, "careers": careers, "gold": Game.gold,
		"at_war": bool(life_path.flags.get("at_war", false)), "sponsor_tier": career_sponsor_tier,
		"owns_plot": not homestead.owned.is_empty(),
		"leased_plot": not homestead.leased.is_empty(),
	}
	economy.has_shop = property.owned().any(func(p: Variant) -> bool: return p is Dictionary and String(p.get("kind", "")) == "trader")
	ctx.merge(economy.ladder_ctx())
	# Counters and property the lighter ladders read (harvests, drills, pieces, workshops): career_trades.gd.
	var trades: Variant = realm.mod("trades") if realm != null else null
	if trades != null:
		ctx["career_stats"] = trades.career_stats(career_id)
		ctx["owns_workshop"] = bool(trades.ladder_ctx(career_id, WorldSim.day).get("owns_workshop", false))
	if bool(CareerLadders.check_promotion(ctx)["eligible"]):
		var r: Dictionary = CareerLadders.promote(ctx)
		career_rank = String(r["rank"])
		career_since_day = WorldSim.day
		Game.say(String(r["text"]))


## Dying of old age: the family carries on through the eldest heir (docs: "Families and
## generations"); with no heir the story ends here, told by the biography.
func _on_old_age_death() -> void:
	var heirs: Array = family.heir_candidates()
	var story := "\n".join(biography.summary(WorldSim.day))
	if heirs.is_empty():
		Game.say("%s dies in old age, with no heir to carry the name.\n%s" % [life_path.full_name(), story])
		# Region1 hook (docs/regions/REGION_1_PLAN.md) H7: the story ends, the ember remains
		preload("res://scripts/region1/ember_legacy.gd").emit_life_ended(biography, echoes, life_path.full_name(), age(),
			life_path.family_name, WorldSim.day, {"place": String(WorldGen.settlements[life_path.home_settlement]["name"]) if life_path.home_settlement >= 0 and life_path.home_settlement < WorldGen.settlements.size() else "", "mastery": mastery.xp, "tendencies": tendencies.values})
		return
	var heir: Dictionary = heirs[0]
	Game.say("%s dies in old age. %s carries on the family.\n%s" % [life_path.full_name(), String(heir.get("name", "Your heir")), story])
	family.succeed_to(heir["id"])
