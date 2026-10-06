extends RefCounted
## Region 1 balance simulator engine (package L18). One simulated life of one archetype, driven through the REAL
## game systems (no separate maths model): the Life autoload (hour/day ticks, economy and markets, property,
## careers and ladders, soul, mastery, progression, equipment, crafting), the realm modules (soldier career,
## career_trades for the farmer / merchant / Wardwright trades), the Adventurer Guild, the town-kit quest library
## (data/quests/*, played through QuestRunner and paid by QuestRewards), the Region 1 story rewards and the combat
## stat tables (data/combat/archetypes.json through CombatStats, with the duel-arena win rates as the calibration).
##
## The only modelled parts are the PLAYER (a policy per archetype: what it does with a day's play time, with a skill
## value for the mini-games) and the fights (a win-probability model calibrated on the arena, see win_chance).
## Deterministic: the world seed is fixed (WorldSim.SEED), the policy's dice come from `seed`.
##
## Used by tools_qa/region1/balance_run.gd (100 days, CSV) and tests/test_balance_r1.gd (short, CI).
## Needs the autoloads, so run it as a Node (balance_run.tscn) or inside gdUnit.

const CombatStats := preload("res://scripts/combat/combat_stats.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const SoldierCareer := preload("res://scripts/sim/soldier_career.gd")
const Guild := preload("res://scripts/sim/adventurer_guild.gd")
const Pickpocket := preload("res://scripts/sim/pickpocket.gd")
const Theft := preload("res://scripts/sim/theft.gd")
const QuestRewards := preload("res://scripts/quests/quest_rewards.gd")
const CorpseLoot := preload("res://scripts/interaction/kinds/corpse_loot.gd")

const ARCHETYPES: Array[String] = ["farmer", "soldier", "wardwright", "merchant", "adventurer"]
const CSV_HEADER := "day,gold,career,career_rank,career_rank_name,soul_tier,soul_power,gear_tier,house_owned,food_security,bounty,deaths,level"

## --- the player model (assumptions, all in one place) -------------------------------------------------------------
## A game day is 12 real minutes (docs/balance/PROGRESSION_R1.md); a focused player spends this share on the
## activities below, the rest is walking, menus, sleeping through the night.
const DAY_SECONDS := 540.0
const START_AGE := 16
const LEDGER_MODULES := ["city_life", "society", "education", "household", "callups", "enterprise", "construction", "scribe", "soldier", "trades"]
const SKILL := 0.7                       # 0..1: mini-game quality and arena skill of the simulated player
const GOLD_RESERVE := 30                 # never spend below this on gear / assets
const TRADE_RESERVE := 160               # the merchant keeps this much out of the stock it carries (house, gear, shop)
const WALK_SPEED := 5.5                  # m/s on roads
const SECS := {"task": 45.0, "market": 20.0, "fight": 45.0, "craft": 15.0, "gather": 30.0, "plot": 5.0, "duty_patrol": 120.0,
	"duty_guard_gate": 60.0, "duty_escort": 150.0, "duty_clear": 150.0, "duty_deliver_orders": 90.0, "duty_investigate": 100.0,
	"quest_objective": 55.0, "commission": 160.0, "meditate": 60.0}
## Arena win rates of the unskilled bot at matching level (data/combat/archetypes.json _doc; the rest are estimates).
const ARENA_WIN := {"goblin": 0.92, "wolf": 0.90, "boar": 0.85, "orc": 0.70, "bandit": 0.75, "bandit_chief": 0.50, "guard": 0.53,
	"captain": 0.40, "troll": 0.30}
const ENEMY_LEVEL := {"goblin": 2, "wolf": 3, "boar": 3, "orc": 7, "bandit": 6, "bandit_chief": 9, "guard": 8, "captain": 10, "troll": 11}
const BASE_DMG := 6.0                    # the arena player's weapon and armour (unskilled bot with the starting kit)
const BASE_ARM := 4.0
const DEATH_ON_LOSS := 0.4               # share of lost fights where the player is carried home (the rest flee)

var arch := "farmer"
var seed_value := 1
var rng := RandomNumberGenerator.new()
var days_total := 100
var markets_limit := 0                   # > 0: keep only this many of the 30 markets (CI speed)
var rows: Array[Dictionary] = []
var income: Dictionary = {}              # source -> gold earned
var spend: Dictionary = {}               # sink -> gold spent
var events: Array[String] = []
var first_day: Dictionary = {}           # milestone -> day first reached ("house", "rank_3", "soul_3", "gear_2", ...)
var deaths := 0
var fights := 0
var wins := 0
var counters: Dictionary = {}            # policy counters for the report (mends, carves, duties...)
var quests_done: Dictionary = {}         # quest id -> day
var story_done := 0
var story_gold := 0
var day := 1
var _secs_left := 0.0
var _pos_sid := 0                        # settlement the player is standing in
var _bus: QuestBus
var _runner: QuestRunner
var _quests_loaded := false
var _food_min_today := 100.0
var _fed_days := 0
var _hours_hungry := 0
var _sold_today: Dictionary = {}
var _gold_day0 := 0
var _booked_today := 0
var _wl: RefCounted = null               # Wardlines sim (Wardwright)
var _guild_joined := false
var _plot := -1
var _cargo_cap := 20
var _story_steps: Array = []
var _story_i := 0
const STORY_PER_DAY := 0.36              # the Region 1 main quest (38 steps) is finished around day 105 by a steady player
const STORY_STEP_SECS := 120.0


func _init(p_arch := "farmer", p_seed := 1, p_days := 100) -> void:
	arch = p_arch
	seed_value = p_seed
	days_total = p_days


# =============================================================================================== public

## Plays `days_total` days and returns the summary dictionary (rows are in `rows`).
func run() -> Dictionary:
	setup()
	for d in days_total:
		play_day(1 + d)
	return summary()


func setup() -> void:
	rng.seed = hash([seed_value, arch, "balance_r1"])
	seed(hash([seed_value, arch, "global"]))
	var old_soldier: Variant = Life.realm.mod("soldier") if Life.realm != null else null
	if old_soldier != null:
		old_soldier.release()
	QuestBus.reset_shared()
	QuestHub.reset()
	Pickpocket.reset()
	var cw: GDScript = load("res://scripts/sim/casual_work.gd") if ResourceLoader.exists("res://scripts/sim/casual_work.gd") else null
	if cw != null:
		cw.call("reset")
	Life.reset()
	Theft.last = {}
	Life.life_path.set_age(START_AGE, WorldSim.day, WorldSim.time_of_day)
	Life.life_path.update(WorldSim.day, int(WorldSim.time_of_day))
	if markets_limit > 0:
		_trim_markets(markets_limit)
	rows.clear()
	income.clear()
	spend.clear()
	events.clear()
	first_day.clear()
	deaths = 0
	fights = 0
	wins = 0
	quests_done.clear()
	counters.clear()
	story_done = 0
	story_gold = 0
	_story_i = 0
	_pos_sid = 0
	_fed_days = 0
	_hours_hungry = 0
	_guild_joined = false
	_plot = -1
	_wl = null
	_bus = QuestBus.new()
	_runner = QuestRunner.new(_bus)
	_quests_loaded = false
	Life.needs.food = 80.0


func summary() -> Dictionary:
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	var prog: Variant = Life.realm.mod("cultivation").prog if Life.realm.mod("cultivation") != null else null
	var xp_by: Dictionary = {}
	if prog != null:
		for k: String in prog.earned_by:
			xp_by[k] = int(round(float(prog.earned_by[k])))
	return {"xp_by": xp_by, "arch": arch, "seed": seed_value, "days": rows.size(), "gold": int(last.get("gold", 0)), "career_rank": int(last.get("career_rank", 0)),
		"career_rank_name": String(last.get("career_rank_name", "")), "soul_tier": int(last.get("soul_tier", 0)), "gear_tier": int(last.get("gear_tier", 0)),
		"house_owned": int(last.get("house_owned", 0)), "deaths": deaths, "level": int(last.get("level", 1)), "first_day": first_day.duplicate(),
		"income": income.duplicate(), "spend": spend.duplicate(), "fights": fights, "wins": wins, "bounty": int(last.get("bounty", 0)),
		"food_security": float(last.get("food_security", 0.0)), "fed_share": float(_fed_days) / maxf(1.0, float(rows.size())),
		"counters": counters.duplicate(), "gold_peak": _peak("gold"), "story_gold": story_gold, "quests_done": quests_done.size(), "rank_count": int(last.get("rank_count", 0))}


func csv() -> String:
	var out := PackedStringArray([CSV_HEADER])
	for r: Dictionary in rows:
		out.append("%d,%d,%s,%d,%s,%d,%.1f,%d,%d,%.2f,%d,%d,%d" % [r["day"], r["gold"], r["career"], r["career_rank"], r["career_rank_name"],
			r["soul_tier"], r["soul_power"], r["gear_tier"], r["house_owned"], r["food_security"], r["bounty"], r["deaths"], r["level"]])
	return "\n".join(out) + "\n"


func _peak(key: String) -> int:
	var m := 0
	for r: Dictionary in rows:
		m = maxi(m, int(r[key]))
	return m


# =============================================================================================== the day

func play_day(d: int) -> void:
	day = d
	_gold_day0 = Game.gold
	_booked_today = 0
	_secs_left = DAY_SECONDS
	_food_min_today = 100.0
	_sold_today.clear()
	# Night and the early morning: the realm's day ticks (hour 6) run before the player acts.
	for h in range(0, 7):
		_hour(d, h)
	WorldSim.time_of_day = 7.0
	_morning(d)
	_discover(d)
	_story(d)
	match arch:
		"farmer":
			_farmer(d)
		"soldier":
			_soldier(d)
		"wardwright":
			_wardwright(d)
		"merchant":
			_merchant(d)
		"adventurer":
			_adventurer(d)
	_evening(d)
	for h in range(7, 24):
		_hour(d, h)
	_record_row(d)


func _hour(d: int, h: int) -> void:
	WorldSim.day = d
	WorldSim.time_of_day = float(h)
	var g0 := Game.gold
	var pend := {}
	for k: String in LEDGER_MODULES:
		var m: RefCounted = Life.realm.mod(k)
		if m != null and m.get("pending_gold") != null:
			pend[k] = int(m.get("pending_gold"))
	WorldSim.hour_changed.emit(h)
	Life.realm.drain()
	var dg := Game.gold - g0
	var booked := 0
	for k: String in pend:
		if int(pend[k]) != 0:
			_credit("ledger_" + k, int(pend[k]))
			booked += int(pend[k])
	if dg - booked != 0:
		_credit("other_hourly" if dg - booked > 0 else "rent_tax_other", dg - booked)
	Life.needs.tick(1.0)
	_food_min_today = minf(_food_min_today, Life.needs.food)
	if Life.needs.food < 25.0:
		_hours_hungry += 1
		_eat()


func _count(key: String, n := 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n


func _credit(source: String, amount: int) -> void:
	_booked_today += amount
	if amount > 0:
		income[source] = int(income.get(source, 0)) + amount
	elif amount < 0:
		spend[source] = int(spend.get(source, 0)) - amount


func _use_time(key: String, mult := 1.0) -> bool:
	var c := float(SECS.get(key, 30.0)) * mult
	if _secs_left < c:
		return false
	_secs_left -= c
	return true


func _walk_to(sid: int) -> bool:
	if sid == _pos_sid:
		return true
	var secs := _travel_secs(sid)
	if _secs_left < secs:
		return false
	_secs_left -= secs
	_pos_sid = sid
	return true


func _travel_secs(sid: int) -> float:
	var a: Vector2 = WorldGen.settlements[_pos_sid]["pos"]
	var b: Vector2 = WorldGen.settlements[sid]["pos"]
	return a.distance_to(b) * 1.25 / WALK_SPEED


# =============================================================================================== needs, house, gear

func _morning(_d: int) -> void:
	if Life.needs.food < 55.0:
		_eat()
	_buy_house()
	_upgrade_gear()


## New places found (hud.gd awards "discovery" once per place): explorers find more than people with a trade to mind.
func _discover(d: int) -> void:
	var rate := 0.4
	var before := int(floor(rate * float(d - 1)))
	var after := int(floor(rate * float(d)))
	for i in range(before, after):
		_award("discovery", {"id": "place_%d" % i})
		_use_time("gather")


func _evening(_d: int) -> void:
	if Life.needs.food < 60.0:
		_eat()
	_stock_food()


func _eat() -> void:
	var guard := 0
	while Life.needs.food < 70.0 and guard < 4:
		guard += 1
		var f: String = Life.best_food()
		if f == "":
			if not _buy_food_one():
				return
			continue
		Life.use_item(f)


func _buy_food_one() -> bool:
	var m: RefCounted = Life.economy.markets[_pos_sid]
	for item: String in ["bread", "apple", "cabbage"]:
		if m.base_price.has(item) and int(m.stock.get(item, 0)) > 0 and Game.gold >= m.price(item):
			var paid: int = Life.economy.buy(_pos_sid, item, Game.gold)
			if paid >= 0:
				Game.add_gold(-paid)
				_credit("food", -paid)
				Life.give(item, 1)
				return true
	return false


func _food_nutrition() -> float:
	var have := 0.0
	for it in Life.inventory.get_items():
		var n := float(it.get_property("nutrition", 0.0))
		if n > 0.0:
			have += n * float(it.get_stack_size())
	return have


func _stock_food() -> void:
	var guard := 0
	while _food_nutrition() < 150.0 and guard < 8:
		guard += 1
		if not _buy_food_one():
			break


func _food_days() -> float:
	return _food_nutrition() / (24.0 * 2.8)


func _buy_house() -> void:
	if not Life.property.owned().is_empty():
		return
	# The cheapest vacant home in Ashford (village lots); a trader's house or manor is never the first.
	var best := ""
	var best_price := 1 << 30
	for lot: String in Life.property.available(0):
		var inf: Dictionary = Life.property.info(lot)
		if bool(inf.get("is_inn_room", false)) or int(inf.get("price", -1)) < 0:
			continue
		if int(inf["price"]) < best_price:
			best_price = int(inf["price"])
			best = lot
	if best == "" or Game.gold < best_price + GOLD_RESERVE:
		return
	var g := Game.gold
	Life.property.buy(best)
	_credit("house", Game.gold - g)
	if Life.property.is_owned(best):
		events.append("day %d: bought %s (%d gold)" % [day, best, best_price])
		first_day["house"] = day


func gear_tier() -> int:
	# Mean tier of the six core slots worn (an empty slot counts as tier 0), rounded to nearest with .5 going down: the "kit tier"
	# of the plan (tier 2 is a kit that is mostly iron, tier 3 needs the average piece to be steel).
	var slots := ["main_hand", "body", "head", "legs", "feet", "off_hand"]
	var sum := 0.0
	for s: String in slots:
		var id: String = Life.equipment.item_in(s)
		if id != "":
			sum += float(Crafting.item_info(id).get("tier", 0))
	return int(ceil(sum / float(slots.size()) - 0.5))


## Gear policy of a sensible player: fill an empty slot with the cheapest piece it may wear, and replace a piece only with the
## cheapest piece of the best tier it may wear (the level a tier asks for, Equipment.ENFORCE_LEVEL, or, before that rule existed,
## whatever it can pay for), never buying a tier it will outgrow within days. At most half the spare gold a day. When the market the
## player stands in has nothing for a slot it makes a trip to the nearest settlement that has (walking time is charged).
func _upgrade_gear() -> void:
	# The first house comes before the first piece of kit that is not free (the cheapest vacant home is 220 gold).
	var keep := GOLD_RESERVE if not Life.property.owned().is_empty() else 260
	var budget := int(float(maxi(0, Game.gold - keep)) * 0.5)
	if budget <= 0:
		return
	var lvl: int = Life.player_level()
	var eq_script: GDScript = Equipment
	var enforce_level: bool = eq_script.get_script_constant_map().has("ENFORCE_LEVEL")
	# The best tier the level opens (tier 1 from level 6, tier 2 from 12, tier 3 from 22); without the rule, any tier goes.
	var cap_tier := 9
	if enforce_level:
		cap_tier = 3 if lvl >= 22 else (2 if lvl >= 12 else (1 if lvl >= 6 else 0))
	var trip_done := false
	for slot: String in ["main_hand", "body", "head", "legs", "feet", "off_hand"]:
		var cur_id: String = Life.equipment.item_in(slot)
		var cur_tier := int(Crafting.item_info(cur_id).get("tier", -1)) if cur_id != "" else -1
		var pick := _gear_pick(_pos_sid, slot, cur_id, cur_tier, cap_tier, enforce_level, lvl, budget)
		var at_sid := _pos_sid
		if pick.is_empty() and not trip_done and cur_tier < cap_tier and budget >= 60 and day % 4 == 0:
			for sid: int in _markets_by_distance():
				if sid == _pos_sid or _travel_secs(sid) * 2.0 + 60.0 > _secs_left or _travel_secs(sid) > 700.0:
					continue
				pick = _gear_pick(sid, slot, cur_id, cur_tier, cap_tier, enforce_level, lvl, budget)
				if not pick.is_empty():
					at_sid = sid
					_secs_left -= _travel_secs(sid) * 2.0
					trip_done = true
					_count("gear_trips")
					break
		if pick.is_empty():
			continue
		var paid: int = Life.economy.buy(at_sid, String(pick["item"]), Game.gold)
		if paid >= 0:
			Game.add_gold(-paid)
			_credit("gear", -paid)
			budget -= paid
			Life.give(String(pick["item"]), 1)
			var eqmsg: String = Life.equipment.equip_from(Life, String(pick["item"]))
			events.append("day %d: gear %s %s (tier %d, %d gold) -> %s" % [day, slot, pick["item"], int(pick["tier"]), paid, eqmsg])


func _markets_by_distance() -> Array:
	var order: Array = []
	for sid in Life.economy.markets:
		order.append([(WorldGen.settlements[int(sid)]["pos"] as Vector2).distance_to(WorldGen.settlements[_pos_sid]["pos"]), int(sid)])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for o: Array in order:
		out.append(o[1])
	return out


func _gear_pick(sid: int, slot: String, cur_id: String, cur_tier: int, cap_tier: int, enforce_level: bool, lvl: int, budget: int) -> Dictionary:
	var m: RefCounted = Life.economy.markets[sid]
	var best := ""
	var best_tier := -1
	var best_price := 1 << 30
	for item: String in m.base_price:
		var inf: Dictionary = Crafting.item_info(item)
		if String(inf.get("slot", "")) != slot or not inf.has("tier"):
			continue
		var t := int(inf["tier"])
		var p: int = m.price(item)
		if t > cap_tier or t <= cur_tier or p > budget or int(m.stock.get(item, 0)) <= 0:
			continue
		if enforce_level and not ItemsDB.meets_requirements(item, lvl):
			continue
		if slot == "main_hand" and float(inf.get("damage", 0)) <= 0.0:
			continue
		# An empty slot takes the cheapest wearable piece; a worn one is replaced only by the best tier that is open.
		if cur_id != "" and t < cap_tier and cap_tier < 9:
			continue
		if t > best_tier or (t == best_tier and p < best_price):
			best = item
			best_tier = t
			best_price = p
	return {} if best == "" else {"item": best, "tier": best_tier}


# =============================================================================================== progression hooks

func _award(activity: String, ctx: Dictionary = {}) -> void:
	Life.award_progress(activity, ctx)


## {career, index (0-based), count, name}: the rank on whichever career ladder the player is on.
func career_rank_info() -> Dictionary:
	var soldier: RefCounted = Life.realm.mod("soldier")
	if bool(soldier.get("active")):
		return {"career": "soldier", "index": int(soldier.get("rank")), "count": SoldierCareer.rank_count(), "name": SoldierCareer.rank_title(int(soldier.get("rank")))}
	if arch == "adventurer" and Life.guild.is_member(Guild.PLAYER):
		var gr := int(Life.guild.member(Guild.PLAYER)["rank"])
		return {"career": "guild", "index": gr, "count": Guild.RANKS.size(), "name": Guild.rank_name(gr) + "-rank"}
	if Life.career_id != "":
		var idx := CareerLadders.rank_index(Life.career_id, Life.career_rank)
		return {"career": Life.career_id, "index": maxi(idx, 0), "count": CareerLadders.ladder(Life.career_id).size(),
			"name": CareerLadders.title_for(Life.career_id, Life.career_rank)}
	return {"career": "", "index": -1, "count": 0, "name": "none"}


func _record_row(d: int) -> void:
	var leak := Game.gold - _gold_day0 - _booked_today          # gold the policy did not book (kept visible, should stay near zero)
	if leak != 0:
		_credit("unbooked_gain" if leak > 0 else "unbooked_spend", leak)
	var ri := career_rank_info()
	var gt := gear_tier()
	var soc: RefCounted = Life.realm.mod("society")
	var bounty := int(soc.call("bounty")) if soc != null else 0
	var fed := _food_min_today >= 15.0
	if fed:
		_fed_days += 1
	# Food security 0..1: three days of food in the pack and never hungry is 1.0.
	var fs := clampf(minf(_food_days() / 3.0, 1.0) * (1.0 if fed else 0.4), 0.0, 1.0)
	var row := {"day": d, "gold": Game.gold, "career": String(ri["career"]), "career_rank": int(ri["index"]) + 1, "career_rank_name": String(ri["name"]).replace(",", ""),
		"soul_tier": Life.soul.tier(), "soul_power": Life.soul.power, "gear_tier": gt, "house_owned": 1 if not Life.property.owned().is_empty() else 0,
		"food_security": fs, "bounty": bounty, "deaths": deaths, "level": Life.player_level(), "rank_count": int(ri["count"])}
	rows.append(row)
	for t in range(1, 7):
		if gt >= t and not first_day.has("gear_%d" % t):
			first_day["gear_%d" % t] = d
	for t in range(1, 6):
		if Life.soul.tier() >= t and not first_day.has("soul_%d" % t):
			first_day["soul_%d" % t] = d
	for r in range(1, 9):
		if int(row["career_rank"]) >= r and not first_day.has("rank_%d" % r):
			first_day["rank_%d" % r] = d
	if int(ri["count"]) > 0 and int(row["career_rank"]) >= int(ri["count"]) and not first_day.has("rank_top"):
		first_day["rank_top"] = d
	if Life.soul.can_attempt_breakthrough() and Life.soul.tier() < 4:
		var r2: Dictionary = Life.soul.attempt_breakthrough(rng)
		if bool(r2.get("success", false)):
			events.append("day %d: soul breakthrough to tier %d" % [d, Life.soul.tier()])


# =============================================================================================== combat

## Win probability of the player against `species` (calibrated on the duel arena at matching level).
func win_chance(species: String, enemy_level := -1) -> float:
	var base: float = float(ARENA_WIN.get(species, 0.7))
	var el := enemy_level if enemy_level > 0 else int(ENEMY_LEVEL.get(species, 5))
	var lvl: int = Life.player_level()
	var st: Dictionary = CombatStats.stats(species, el, lvl) if CombatStats.has(species) else {"hp": 100, "dmg": 1.0}
	var ref: Dictionary = CombatStats.stats(species, lvl, lvl) if CombatStats.has(species) else {"hp": 100, "dmg": 1.0}
	var eq: Dictionary = Life.equipment.stats()
	var dmg := maxf(float(eq.get("damage", 0.0)), 2.0)
	var arm := float(eq.get("armour", 0.0))
	var power := (1.0 + 0.006 * float(lvl - 1)) * (1.0 + 0.045 * (dmg - BASE_DMG)) * (1.0 + 0.03 * (arm - BASE_ARM))
	var enemy := (float(st["hp"]) / maxf(1.0, float(ref["hp"]))) * pow(float(st["dmg"]) / maxf(0.001, float(ref["dmg"])), 0.5)
	var logit := log(base / (1.0 - base)) + 1.6 * log(maxf(0.05, power / maxf(0.05, enemy))) + 1.2 * (SKILL - 0.5)
	return clampf(1.0 / (1.0 + exp(-logit)), 0.02, 0.985)


## One fight. Returns {win, dead, p}. A loss may carry the player home (Life.apply_death_penalty).
func fight(species: String, enemy_level := -1) -> Dictionary:
	fights += 1
	var p := win_chance(species, enemy_level)
	var win := rng.randf() < p
	var dead := false
	if win:
		wins += 1
	elif rng.randf() < DEATH_ON_LOSS:
		dead = true
		deaths += 1
		var g := Game.gold
		Life.apply_death_penalty()
		_credit("death_penalty", Game.gold - g)
	return {"win": win, "dead": dead, "p": p}


## The kill rewards the game gives TODAY: progression, soul (hunt), merit and guild kill credit through Life, a wolf's pelt and meat
## (Life.on_wolf_killed) and, from a fallen humanoid, the corpse search (CorpseLoot GUARD table). ItemsDB.monster_drops and
## roll_loot are not wired to kills in the game yet (docs/design/ITEMS_R1.md "hooks still missing"), so they are not simulated.
func _kill_rewards(species: String, den_id := -1) -> void:
	_count("kills")
	if species == "wolf":
		Life.on_wolf_killed(Vector3.ZERO, den_id)
		return
	Life.on_monster_killed(species)
	Life.guild.on_kill(Guild.PLAYER, species, den_id)
	if species in ["bandit", "bandit_chief", "goblin", "orc", "guard", "captain"]:
		var loot: Dictionary = CorpseLoot.roll("sim/%d/%d" % [day, fights], CorpseLoot.GUARD)
		if int(loot["gold"]) > 0:
			Game.add_gold(int(loot["gold"]))
			_credit("corpse_gold", int(loot["gold"]))
		for e: Array in loot["items"]:
			Life.give(String(e[0]), int(e[1]))


## Sells what the pack holds that is not food, gear worn, tools or quest goods, at the market the player stands in
## (real prices, real purse).
func _sell_loot(keep: Array = []) -> void:
	if not _use_time("market"):
		return
	for it in Life.inventory.get_items().duplicate():
		var id: String = it.get_prototype().get_prototype_id()
		if id in keep:
			continue
		var slot := String(Life.item_prop(id, "slot", ""))
		if slot != "" and Life.equipment.item_in(slot) == id and int(it.get_stack_size()) <= 1:
			continue
		if float(it.get_property("nutrition", 0.0)) > 0.0:
			continue
		if int(Life.item_prop(id, "price", 0)) <= 0 or String(Life.item_prop(id, "category", "")) in ["quest", "key", "manual", "lore"]:
			continue
		if String(Life.item_prop(id, "type", "")) == "tool":
			continue
		var n := int(it.get_stack_size())
		for k in n:
			var got: int = Life.economy.sell(_pos_sid, id)
			if got < 0:
				break
			Game.add_gold(got)
			_credit("sales", got)
			Life.take(id, 1)
			_sold_today[id] = int(_sold_today.get(id, 0)) + 1


# =============================================================================================== task helper (career_trades)

## Plays one career_trades task with the player's skill. Returns the result dictionary ({} when none could start).
func _trade_task(career: String, kind: String) -> Dictionary:
	var tr: RefCounted = Life.realm.mod("trades")
	var b: Dictionary = tr.begin(career, kind, day)
	if not bool(b.get("ok", false)):
		return {}
	if not _use_time("task"):
		tr.abandon_task()
		return {}
	var guard := 0
	while guard < 8:
		guard += 1
		var task: Dictionary = tr.get("task")
		var st: Dictionary = (task["steps"] as Array)[int(task["i"])]
		var value := 0.0
		if String(st["widget"]) == "choice":
			var opts: Array = st["options"]
			var best := 0
			for i in opts.size():
				if float(opts[i]["q"]) > float(opts[best]["q"]):
					best = i
			value = float(best) if rng.randf() < 0.45 + 0.5 * SKILL else float(rng.randi() % opts.size())
		else:
			value = clampf(0.35 + 0.5 * SKILL + rng.randfn(0.0, 0.15), 0.0, 1.0)
		var r: Dictionary = tr.submit(value)
		if bool(r.get("done", false)):
			return r
	return {}


# =============================================================================================== FARMER

func _farmer(d: int) -> void:
	var tr: RefCounted = Life.realm.mod("trades")
	if not tr.is_member("farmer"):
		tr.join("farmer", d)
	if _plot < 0:
		_plot = 0
		var why: String = tr.take_tenancy(_plot, d)
		if why != "":
			events.append("farmer: no lease (%s)" % why)
	var guard := 0
	while guard < 6:
		guard += 1
		var r := _trade_task("farmer", "sow")
		if r.is_empty():
			break
	_farm_work_spot(d)
	_tend_plot(d)
	_farmer_assets(d)
	_sell_loot()


## The field hand's wage at the farm site (the real work spot: 6 gold per 4 s hold). With scripts/sim/casual_work.gd
## present the same daily rule the game uses applies; without it nothing stops the player but their own patience.
func _farm_work_spot(d: int) -> void:
	var cw: Variant = load("res://scripts/sim/casual_work.gd") if ResourceLoader.exists("res://scripts/sim/casual_work.gd") else null
	var n := 0
	while n < 60 and _secs_left > 40.0:
		var pay := 6
		if cw != null:
			pay = int(cw.pay_for("farm_work", d, 6))
			if pay <= 0:
				break
		if not _use_time("task", 0.5):
			break
		n += 1
		Game.add_gold(pay)
		_credit("farm_work_spot", pay)
		Life.record("farmed", 1.0)
		if cw == null and n >= 12:
			break          # no cap in the game: a human gets bored after a dozen holds, the exploit probe shows the rest


func _tend_plot(_d: int) -> void:
	var hs: RefCounted = Life.homestead
	if not hs.owns_or_leases(_plot):
		return
	var want := 24
	var cur := 0
	for cr: Dictionary in hs.crops:
		if int(cr["plot"]) == _plot:
			cur += 1
	var x := cur
	while cur < want and Game.gold >= 8 + GOLD_RESERVE and _secs_left > 20.0:
		var cell := Vector2i(x % 6, x / 6)
		x += 1
		if hs.crop_at(_plot, cell).is_empty():
			var g := Game.gold
			hs.place(_plot, "crop_plot", cell, 0)
			_credit("plot_tilling", Game.gold - g)
			cur += 1
			_use_time("plot", 0.5)
	for cr: Dictionary in hs.crops:
		if int(cr["plot"]) != _plot:
			continue
		var cell: Vector2i = cr["cell"]
		if String(cr.get("crop", "")) == "":
			if _use_time("plot", 0.6):
				hs.plant(_plot, cell, "wheat")
				hs.water(_plot, cell)
		elif hs.is_ready(cr):
			if _use_time("plot", 0.6):
				hs.harvest(_plot, cell)
	var n := Life.count("wheat")
	if n > 0 and _use_time("market"):
		for i in n:
			var got: int = Life.economy.sell(_pos_sid, "wheat")
			if got < 0:
				break
			Game.add_gold(got)
			_credit("crop_sales", got)
			Life.take("wheat", 1)


## Land and tenants: the farmer ladder wants an owned plot (smallholder) and tenants (estate owner); a farmer with the
## gold buys the plot and settles a family now and then (career_trades: 80 gold a family, 4 gold rent a week).
func _farmer_assets(d: int) -> void:
	var tr: RefCounted = Life.realm.mod("trades")
	var hs: RefCounted = Life.homestead
	if not hs.is_owned(_plot):
		var price := int(hs.plots()[_plot]["price"])
		if Game.gold >= price + 120 and tr.rank_of("farmer") != "field_hand":
			var g := Game.gold
			hs.end_lease(_plot)          # a plot is leased or owned, never both
			tr.buy_land(_plot)
			_credit("land", Game.gold - g)
			if hs.is_owned(_plot):
				events.append("day %d: bought the plot (%d gold)" % [d, price])
				first_day["land"] = d
		return
	if Game.gold >= 300 and int(tr.estate.get("tenants", 0)) < 8 and _secs_left > 60.0:
		var r := _trade_task("farmer", "tenant")
		if not r.is_empty():
			_credit("tenant_family", int(r.get("gold", 0)))


# =============================================================================================== SOLDIER

func _soldier(d: int) -> void:
	var s: RefCounted = Life.realm.mod("soldier")
	if not bool(s.get("active")):
		var r: Dictionary = s.enlist(d, "captain")
		if not bool(r.get("ok", false)):
			events.append("soldier: cannot enlist (%s)" % String(r.get("reason", "")))
			return
	# Muster at 06:30 at the post (the realm's day tick at hour 6 has already settled yesterday's).
	s.muster_attend(d, 6.5, s.post_pos() + Vector2(2, 1))
	if not _use_time("market", 0.5):
		return
	var duty: Dictionary = s.todays_duty(d)
	if duty.is_empty():
		return
	var ac: Dictionary = s.accept_duty(d)
	if not bool(ac.get("ok", false)):
		return
	_do_duty(s, duty)
	_soldier_extras(s)


func _do_duty(s: RefCounted, duty: Dictionary) -> void:
	var kind := String(duty["kind"])
	if not _use_time("duty_" + kind):
		s.abandon_duty(day)
		return
	var bus := QuestBus.shared()
	var stage: Dictionary = (duty["def"]["stages"] as Array)[0]
	var failed := false
	for o: Dictionary in stage["objectives"]:
		match String(o["type"]):
			"goto":
				var p: Array = o["pos"]
				bus.emit_event(&"position", {"x": float(p[0]), "y": float(p[1])})
			"wait", "protect":
				for h in int(ceil(float(o["hours"]))):
					bus.emit_event(&"hours", {"amount": 1.0, "hour": float((22 + h) % 24)})
			"escort":
				if rng.randf() < 0.25:
					var f := fight("bandit")
					if bool(f["win"]):
						_kill_rewards("bandit")
					else:
						failed = true
				if not failed:
					bus.emit_event(&"arrive", {"actor": o["actor"], "place": o["place"]})
			"kill":
				var target := String(o["target"])
				for k in int(o["count"]):
					var f2 := fight(target)
					if bool(f2["win"]):
						_kill_rewards(target)
						bus.emit_event(&"kill", {"target": target, "place": o["place"], "amount": 1})
					else:
						failed = true
						break
			"deliver":
				bus.emit_event(&"deliver", {"item": o["item"], "to": o["to"], "amount": 1})
			"investigate":
				for c: String in o["clues"]:
					bus.emit_event(&"interact", {"id": c})
	if failed:
		s.abandon_duty(day)
		return


func _soldier_extras(s: RefCounted) -> void:
	# Drill with the squad (combat training is open to every career); the soldier fights on duty only.
	if _use_time("task"):
		Life.record("trained_sword", 1.0)
		_award("train", {"subject": "drill_yard"})
	_sell_loot()


# =============================================================================================== WARDWRIGHT

func _ensure_wardlines() -> void:
	if _wl != null:
		return
	var W: GDScript = load("res://scripts/region1/wardlines.gd")
	_wl = W.new()
	_wl.setup(WorldSim.SEED + seed_value)
	_wl.tick(0.5)


func _wardwright(d: int) -> void:
	_ensure_wardlines()
	_wl.tick(1.0)
	var tr: RefCounted = Life.realm.mod("trades")
	var has_career: bool = tr.has_method("stone_work") and ("wardwright" in tr.CAREERS)
	if has_career and not tr.is_member("wardwright"):
		tr.join("wardwright", d)
	# Walk the road and mend the worst stones (the real hook in region1_glue._mend: refused when mended less than 0.4 day ago
	# and still above 0.6; each mend adds `repair_amount`), carve a glyph on a dim stone now and then.
	var mends := 0
	var worn: Array = []
	for i in _wl.n:
		if _wl.elder_of[i] < 0:
			worn.append([float(_wl.condition[i]), i])
	worn.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var gi := 0
	while gi < worn.size() and mends < 5 and _secs_left > 50.0:
		var i: int = int(worn[gi][1])
		gi += 1
		if _wl.day_f - _wl.last_repair[i] < 0.4 and _wl.condition[i] > 0.6:
			continue
		if mends >= 1 and _wl.condition[i] > 0.9:
			break          # one round a day always, more only where a stone needs it
		if not _use_time("task", 0.8):
			break
		var cond_before: float = _wl.condition[i]
		_wl.repair(i)
		mends += 1
		_count("mends")
		Life.record("mended_stone", 1.0)
		if has_career:
			tr.stone_work("mend", cond_before, clampf(0.35 + 0.5 * SKILL + rng.randfn(0.0, 0.15), 0.0, 1.0), d)
	var carved := 0
	for i in _wl.n:
		if carved >= 2 or _secs_left < 60.0:
			break
		if _wl.elder_of[i] >= 0 or int(_wl.glyph[i]) != 0:
			continue
		if _use_time("task"):
			var res: Dictionary = _wl.carve(i, ["ward", "lure", "alarm", "bless"][rng.randi() % 4])
			if not bool(res.get("ok", false)):
				_count("carve_fail_" + String(res.get("reason", "?")))
			if bool(res.get("ok", false)):
				carved += 1
				_count("carves")
				if has_career:
					tr.stone_work("carve", 0.4, clampf(0.35 + 0.5 * SKILL + rng.randfn(0.0, 0.15), 0.0, 1.0), d)
	# Wardwrights also fight what wanders in from the wild edge (the stone ring is theirs to keep).
	var guard := 0
	while _secs_left > 100.0 and guard < 4:
		guard += 1
		if not _use_time("fight"):
			break
		var f := fight("wolf")
		if bool(f["win"]):
			_kill_rewards("wolf")
	_sell_loot()


# =============================================================================================== MERCHANT

func _merchant(d: int) -> void:
	var tr: RefCounted = Life.realm.mod("trades")
	if not tr.is_member("merchant"):
		tr.join("merchant", d)
	# Every third day is a road day (contracts, a trade run, the cart, the shop); the other days are the stall and haggling.
	var trip_day := d % 3 == 0
	var guard := 0
	while guard < (2 if trip_day else 5):
		guard += 1
		var r := _trade_task("merchant", "stall" if guard % 2 == 1 else "haggle")
		if r.is_empty():
			break
	if trip_day:
		_buy_cart_when_able()
		_contracts(d)
		_arbitrage(d)
		_buy_shop_when_able(d)


func _buy_cart_when_able() -> void:
	if Life.economy.owns_cart or Game.gold < Life.economy.CART_COST + 80 or Life.property.owned().is_empty():
		return
	if String(WorldGen.settlements[_pos_sid]["kind"]) == "village":
		# The cart-wright is in a town: go to the nearest one if the day allows.
		var town := -1
		for sid: int in _markets_by_distance():
			if String(WorldGen.settlements[sid]["kind"]) != "village":
				town = sid
				break
		if town < 0 or _travel_secs(town) * 2.0 + 60.0 > _secs_left:
			return
		_walk_to(town)
	var why: String = Life.economy.buy_cart(_pos_sid, Game.gold)
	if why == "":
		Game.add_gold(-Life.economy.CART_COST)
		_credit("cart", -Life.economy.CART_COST)
		events.append("day %d: bought a cart" % day)


## A trader's house (a shop front with a workshop) is what the shopkeeper rank asks for: the merchant buys the cheapest
## one on offer once the purse allows, walking there first.
func _buy_shop_when_able(d: int) -> void:
	if bool(Life.economy.has_shop) or Life.realm.mod("trades").rank_of("merchant") == "peddler":
		return
	var best_lot := ""
	var best_price := 1 << 30
	var best_sid := -1
	for sid in WorldGen.settlements.size():
		for lot: String in Life.property.available(sid):
			var inf: Dictionary = Life.property.info(lot)
			if String(inf.get("kind", "")) == "trader" and int(inf["price"]) < best_price:
				best_price = int(inf["price"])
				best_lot = lot
				best_sid = sid
	if best_lot == "" or Game.gold < best_price + 120 or _travel_secs(best_sid) + 60.0 > _secs_left:
		return
	_walk_to(best_sid)
	var g := Game.gold
	Life.property.buy(best_lot)
	_credit("shop_house", Game.gold - g)
	if Life.property.is_owned(best_lot):
		events.append("day %d: bought a trader's house %s (%d gold)" % [d, best_lot, best_price])
		first_day["shop"] = d


func _contracts(d: int) -> void:
	var eco: RefCounted = Life.economy
	_count("contract_days_open", eco.contracts.size())
	for c: Dictionary in eco.contracts.duplicate():
		if int(c["filled"]) >= int(c["amount"]) or d > int(c["due_day"]) or _secs_left < 120.0:
			continue
		var item := String(c["item"])
		var need := int(c["amount"])
		var best_sid := -1
		var best_cost := 1 << 30
		for sid in eco.markets:
			var m: RefCounted = eco.markets[sid]
			if not m.base_price.has(item) or int(m.stock.get(item, 0)) < need or int(sid) == int(c["to"]):
				continue
			var cost: int = m.price(item) * need
			if cost < best_cost:
				best_cost = cost
				best_sid = int(sid)
		if best_sid < 0 or Game.gold < best_cost:
			_count("contract_no_source")
			continue
		var a: Vector2 = WorldGen.settlements[best_sid]["pos"]
		var b: Vector2 = WorldGen.settlements[int(c["to"])]["pos"]
		var trip := _travel_secs(best_sid) + a.distance_to(b) * 1.25 / WALK_SPEED
		if trip + 60.0 > _secs_left:
			_count("contract_no_time")
			continue
		_walk_to(best_sid)
		_secs_left -= 20.0
		for k in need:
			var paid: int = eco.buy(best_sid, item, Game.gold)
			if paid < 0:
				break
			Game.add_gold(-paid)
			_credit("trade_goods_bought", -paid)
			Life.give(item, 1)
		_walk_to(int(c["to"]))
		if Life.count(item) >= need:
			Life.take(item, need)
			eco.contract_progress(int(c["id"]), need)
			var r: Dictionary = eco.complete_contract(int(c["id"]), d)
			if int(r["reward"]) > 0:
				_count("contracts_done")
				Game.add_gold(int(r["reward"]))
				_credit("contracts", int(r["reward"]))
				Life.biography.change_rep("trade", 2.0)
				Life.mastery.gain("trading", 3.0, d)


## Marginal-profit trade planner: buying from one market pushes its price up unit by unit and selling into another pushes that one
## down (RAMarket.price follows the stock), so only the first units of a good pay. This walks the same price curve the markets use
## and returns the best {to, item, units, cost, revenue} over the routes out of the player's market.
func _plan_trade(capital: int, cap_units: int) -> Dictionary:
	var eco: RefCounted = Life.economy
	var from_m: RefCounted = eco.markets[_pos_sid]
	var best := {}
	var best_rate := 0.0
	for r: Dictionary in eco.best_trade_routes(_pos_sid, 24):
		var trip := _travel_secs(int(r["to"]))
		if trip + 80.0 > _secs_left:
			continue
		var to_m: RefCounted = eco.markets[int(r["to"])]
		var item := String(r["item"])
		var s_from := float(from_m.stock.get(item, 0))
		var s_to := float(to_m.stock.get(item, 0))
		var cost := 0
		var rev := 0
		var units := 0
		var best_profit := 0
		var best_units := 0
		var best_cost := 0
		var best_rev := 0
		while units < mini(cap_units, int(s_from)):
			var bp := _price_at(from_m, item, s_from - float(units))
			if cost + bp > capital:
				break
			var sp := maxi(1, int(floor(float(_price_at(to_m, item, s_to + float(units))) * RAMarketShare)))
			if rev + sp > int(to_m.purse):
				break           # the buyer's purse is empty: a merchant only pays what it has
			cost += bp
			rev += sp
			units += 1
			if rev - cost > best_profit:
				best_profit = rev - cost
				best_units = units
				best_cost = cost
				best_rev = rev
		if best_profit < 12:
			continue
		var rate := float(best_profit) / (trip * 2.0 + 60.0)
		if rate > best_rate:
			best_rate = rate
			best = {"to": int(r["to"]), "item": item, "units": best_units, "cost": best_cost, "revenue": best_rev, "profit": best_profit}
	return best


const RAMarketShare := 0.6


func _price_at(m: RefCounted, item: String, stock: float) -> int:
	var f := clampf(float(m.target.get(item, 1)) / maxf(stock, 0.5), 0.5, 3.0)
	return maxi(1, int(round(float(m.base_price.get(item, 1)) * f * m.modifier(item))))


func _arbitrage(_d: int) -> void:
	if _secs_left < 120.0:
		return
	# Saving for the first house comes before stock.
	var reserve := TRADE_RESERVE if not Life.property.owned().is_empty() else 260
	var capital := maxi(0, Game.gold - reserve)
	if capital < 40:
		return
	var eco: RefCounted = Life.economy
	var cap: int = eco.cargo_slots(_cargo_cap, true)
	var plan := _plan_trade(capital, cap)
	if plan.is_empty():
		return
	var item := String(plan["item"])
	var bought := 0
	var spent_total := 0
	while bought < int(plan["units"]):
		var paid: int = eco.buy(_pos_sid, item, mini(Game.gold, capital - spent_total))
		if paid < 0:
			break
		Game.add_gold(-paid)
		spent_total += paid
		Life.give(item, 1)
		bought += 1
	_credit("trade_goods_bought", -spent_total)
	if bought == 0:
		return
	_walk_to(int(plan["to"]))
	_secs_left -= 20.0
	var got_total := 0
	for k in bought:
		var got: int = eco.sell(_pos_sid, item)
		if got < 0:
			break
		Game.add_gold(got)
		got_total += got
		Life.take(item, 1)
		Life.record("traded", 0.3)
	_credit("trade_goods_sold", got_total)
	_count("trades")


# =============================================================================================== ADVENTURER

func _adventurer(d: int) -> void:
	if not _guild_joined:
		_guild_joined = true
		Life.join_guild()
		if Life.guild.is_member(Guild.PLAYER):
			_credit("guild_fee", -Guild.MEMBERSHIP_FEE)
	_commissions(d)
	_town_quests(d)
	_hunt(d)
	_craft_basics()
	_sell_loot()


## Region 1 main quest pace: the adventurer follows the story at a steady clip; its rewards are applied exactly as
## r1_story_director does (gold, items).
func _story(_d: int) -> void:
	if _story_steps.is_empty():
		var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/quests/r1_main.json"))
		_story_steps = js["steps"]
	var target := int(floor(STORY_PER_DAY * float(day)))
	while _story_i < mini(target, _story_steps.size()):
		var st: Dictionary = _story_steps[_story_i]
		_story_i += 1
		story_done += 1
		_secs_left = maxf(0.0, _secs_left - STORY_STEP_SECS)
		if String(st["id"]) == "a4_five_hearts":
			first_day["story_five_hearts"] = day
		if String(st["id"]) == "a5_homecoming":
			first_day["story_complete"] = day
		for a: Array in st.get("on_complete", []):
			match String(a[0]):
				"gold":
					Game.add_gold(int(a[1]))
					story_gold += int(a[1])
					_credit("story", int(a[1]))
				"give":
					Life.give(String(a[1]), int(a[2]))
		_award("quest", {"id": "r1_" + String(st["id"])})      # r1_story_director.gd: no content_level, so the player's own level


func _commissions(d: int) -> void:
	if not Life.guild.is_member(Guild.PLAYER):
		return
	_turn_in_ready()
	var open: Array = Life.guild.available_for(Guild.PLAYER, 0)
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["reward"]) / maxf(1.0, float(a["required"])) > float(b["reward"]) / maxf(1.0, float(b["required"])))
	for c: Dictionary in open:
		if Life.guild.active_for(Guild.PLAYER).size() >= 2:
			break
		if String(c["type"]) == "cull":
			Life.guild.accept(Guild.PLAYER, int(c["id"]), d)
	for c: Dictionary in Life.guild.active_for(Guild.PLAYER).duplicate():
		if String(c["type"]) != "cull":
			continue
		var species := String(c["target"].get("species", "wolf"))
		if not CombatStats.has(species):
			species = "wolf"
		var den := int(c["target"].get("den", -1))
		var left := int(c["required"]) - int(c["progress"])
		if _secs_left < 60.0 + float(SECS["fight"]):
			break
		_secs_left -= 60.0
		for k in left:
			if not _use_time("fight"):
				break
			var f := fight(species)
			if bool(f["win"]):
				_kill_rewards(species, den)
			else:
				break
	_turn_in_ready()


func _turn_in_ready() -> void:
	for c: Dictionary in Life.guild.active_for(Guild.PLAYER).duplicate():
		if Life.guild.is_ready(int(c["id"])):
			var g := Game.gold
			Life.turn_in(int(c["id"]))
			_credit("guild_commissions", Game.gold - g)


func _load_quests() -> void:
	if _quests_loaded:
		return
	_quests_loaded = true
	for sub in DirAccess.get_directories_at("res://data/quests"):
		_runner.load_dir("res://data/quests/" + sub)


## Town-kit quest lines: the adventurer works the quests of the towns near Ashford, nearest first, in chain order.
func _town_quests(_d: int) -> void:
	_load_quests()
	for tid: String in _town_order():
		if _secs_left < 200.0:
			return
		for qid: String in _chain_of(tid):
			if quests_done.has(qid):
				continue
			var def: QuestDef = _runner.def(qid)
			if def == null:
				continue
			if _runner.can_start(qid) != "":
				break
			var sid := _sid_of_town(tid)
			var cost := _quest_cost(def) + (_travel_secs(sid) if sid >= 0 else 0.0)
			if cost > _secs_left:
				return
			_secs_left -= cost
			if sid >= 0:
				_pos_sid = sid
			_play_quest(def)
			break


func _town_order() -> Array:
	var out: Array = []
	var names: Array = []
	for i in WorldGen.settlements.size():
		names.append([float((WorldGen.settlements[i]["pos"] as Vector2).distance_to(WorldGen.settlements[0]["pos"])), String(WorldGen.settlements[i]["name"]).to_lower()])
	names.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for n: Array in names:
		out.append(n[1])
	return out


var _chain_cache: Dictionary = {}


func _chain_of(tid: String) -> Array:
	if _chain_cache.has(tid):
		return _chain_cache[tid]
	var out: Array = []
	var dir := "res://data/quests/" + tid
	if DirAccess.dir_exists_absolute(dir):
		var defs: Array = []
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				var q: QuestDef = QuestDef.load_json(dir + "/" + f)
				if q != null:
					defs.append(q)
		var done := {}
		var guard := 0
		while defs.size() > out.size() and guard < 8:
			guard += 1
			for q: QuestDef in defs:
				if done.has(q.id):
					continue
				var ok := true
				for r: Variant in q.requires():
					if not done.has(String(r)):
						ok = false
				if ok:
					done[q.id] = true
					out.append(q.id)
	_chain_cache[tid] = out
	return out


func _sid_of_town(tid: String) -> int:
	for i in WorldGen.settlements.size():
		if String(WorldGen.settlements[i]["name"]).to_lower() == tid:
			return i
	return -1


func _quest_cost(def: QuestDef) -> float:
	var n := 0
	for st: Dictionary in def.stages:
		n += (st.get("objectives", []) as Array).size()
	return float(SECS["quest_objective"]) * float(n)


## Plays a quest to its end through the runner (private bus), honest 70% of the time on the moral choice.
func _play_quest(def: QuestDef) -> void:
	var r := _runner
	if r.start(def.id) != "":
		return
	var g0 := Game.gold
	var guard := 0
	while r.is_active(def.id) and guard < 40:
		guard += 1
		var open: Array = r.objectives_of(def.id).filter(func(o: RefCounted) -> bool: return not o.is_done())
		if open.is_empty():
			break
		_fire_objective(open[0])
	_credit("town_quests", Game.gold - g0)          # stage and quest rewards are paid by the runner itself (QuestRewards)
	if r.is_done(def.id):
		quests_done[def.id] = day
		Life.record("helped_villager", 1.5)
	elif r.is_failed(def.id):
		events.append("quest failed: " + def.id)


func _fire_objective(o: RefCounted) -> void:
	var data: Dictionary = o.data
	var b := _bus
	match String(o.type):
		"goto":
			b.emit_event(&"enter_area", {"place": data["place"]} if data.has("place") else {})
		"talk_to":
			b.emit_event(&"talk", {"npc": data.get("npc", ""), "node": data.get("node", "")})
		"kill":
			var target := String(data.get("target", "wolf"))
			var sp := target if CombatStats.has(target) else "wolf"
			for k in int(data.get("count", 1)):
				var f := fight(sp)
				if not bool(f["win"]):
					f = fight(sp)        # back up the road, heal, try again
				if bool(f["win"]):
					_kill_rewards(sp)
				b.emit_event(&"kill", {"target": target, "place": data.get("place", ""), "amount": 1})
		"collect":
			b.emit_event(&"item", {"item": data.get("item", ""), "amount": int(data.get("count", 1))})
		"deliver":
			b.emit_event(&"deliver", {"item": data.get("item", ""), "to": data.get("to", ""), "amount": int(data.get("count", 1))})
		"investigate":
			for c: String in data.get("clues", []):
				b.emit_event(&"interact", {"id": c})
		"choose":
			var opts: Array = data.get("options", [])
			var pick := 0 if rng.randf() < 0.7 else (opts.size() - 1)
			b.emit_event(&"choose", {"choice": o.id, "option": (opts[pick] as Dictionary)["id"]})
		"wait", "protect":
			for h in int(ceil(float(data.get("hours", 1.0)))):
				b.emit_event(&"hours", {"amount": 1.0, "hour": 23.0})
		"escort":
			b.emit_event(&"arrive", {"actor": data.get("actor", ""), "place": data.get("place", "")})
		"observe":
			b.emit_event(&"observe", {"target": data.get("target", ""), "hour": 12.0, "dist": 5.0, "unseen": true, "dt": 60.0})
		_:
			b.emit_event(&"talk", {})


## Hunting around the home vale: the fights that fill the rest of the day, easy to hard by level.
func _hunt(_d: int) -> void:
	var guard := 0
	while _secs_left > 120.0 and guard < 6:
		guard += 1
		var species := "wolf"
		var roll := rng.randf()
		var level: int = Life.player_level()
		if level >= 14 and roll < 0.15:
			species = "orc"
		elif level >= 8 and roll < 0.40:
			species = "bandit"
		elif roll < 0.55:
			species = "goblin"
		elif roll < 0.75:
			species = "boar"
		if not _use_time("fight"):
			break
		var f := fight(species)
		if bool(f["win"]):
			_kill_rewards(species)
		_use_time("gather", 0.3)


## Bandages and salves from what the hunt gives: real recipes, real quality rolls, sold at the market.
func _craft_basics() -> void:
	for id: String in ["bandage", "healing_salve"]:
		var guard := 0
		while guard < 4 and _secs_left > 40.0 and Life.crafting.can_craft(id, Life, null) == "":
			guard += 1
			if not _use_time("craft"):
				break
			Life.crafting.craft(id, Life, null, {"tension": true})


# =============================================================================================== market scaling for CI

func _trim_markets(keep: int) -> void:
	var eco: RefCounted = Life.economy
	var order: Array = []
	for sid in eco.markets:
		var p: Vector2 = WorldGen.settlements[int(sid)]["pos"]
		order.append([p.distance_to(WorldGen.settlements[0]["pos"]), int(sid)])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var kept := {}
	for i in mini(keep, order.size()):
		kept[int(order[i][1])] = true
	for sid in eco.markets.keys():
		if not kept.has(int(sid)):
			eco.markets.erase(sid)
