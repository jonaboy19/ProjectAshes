extends GdUnitTestSuite
## Adventurer Guild, magicules, naming, injuries/healers and talent scouts.

const GUARD_WAGE := 9


# --- helpers -------------------------------------------------------------------

func _careers() -> RACareers:
	var c := RACareers.new(1)
	c.add_org("guard", "the Guard", 0, "Captain", Vector3(0, 0, 50), Vector2(7, 19), 3, [
		{"title": "Captain", "wage": 30, "count": 1, "merit": 400},
		{"title": "Guard", "wage": 9, "count": 3, "merit": 0},
	])
	c.add_org("inn", "the Inn", 0, "Innkeeper", Vector3(0, 0, 20), Vector2(11, 23), 2, [
		{"title": "Innkeeper", "wage": 16, "count": 1, "merit": 9999},
		{"title": "Server", "wage": 5, "count": 2, "merit": 0},
	])
	c.seat("guard", "Captain")["holders"].append(1)
	c.seat("guard", "Guard")["holders"].append_array([2, 3])
	return c


## A world with dens across the whole threat range, caravans, shortages and rumours.
func _world(careers: RACareers) -> Callable:
	return func(settlement: int, _day: int) -> Dictionary:
		var dens := []
		for i in 8:
			dens.append({"id": i, "species": "wolf", "population": 3 + i, "threat": 4.0 + i * 13.0, "distance": 400.0})
		return {
			"dens": dens,
			"caravans": [{"id": "c1", "from": "Ashford", "to": "Millbrook", "danger": 20.0, "days": 2},
				{"id": "c2", "from": "Ashford", "to": "Greywater", "danger": 50.0, "days": 3}],
			"gathering": [{"item": "moonleaf", "amount": 6}, {"item": "firewood", "amount": 20}],
			"deliveries": [{"item": "letter", "to": "Millbrook", "days": 2}],
			"rumours": [{"id": "r1", "label": "howling at the old mill", "threat": 35.0}],
			"vacancies": RAAdventurerGuild.vacancies_from(careers, settlement),
		}


func _guild() -> RAAdventurerGuild:
	var g := RAAdventurerGuild.new(7)
	g.add_branch(0, "Ashford Guild Hall")
	g.context = _world(_careers())
	g.join(RAAdventurerGuild.PLAYER, 0, 100, 0)
	return g


func _full_board(g: RAAdventurerGuild) -> Array:
	for d in 4:
		g.tick_day(d)
	return g.board(0)


func _find(g: RAAdventurerGuild, type: String, rank := -1) -> Dictionary:
	for c: Dictionary in g.board(0):
		if c["type"] == type and c["state"] == "open" and (rank < 0 or int(c["rank"]) == rank):
			return c
	return {}


# --- guild ---------------------------------------------------------------------

func test_membership_fee() -> void:
	var g := RAAdventurerGuild.new()
	g.add_branch(0, "Hall")
	var poor := g.join(5, 0, 3, 0)
	assert_bool(poor["ok"]).is_false()
	var r := g.join(5, 0, 50, 0)
	assert_bool(r["ok"]).is_true()
	assert_int(r["fee"]).is_equal(RAAdventurerGuild.MEMBERSHIP_FEE)
	assert_str(RAAdventurerGuild.rank_name(g.member(5)["rank"])).is_equal("F")
	assert_bool(g.join(5, 0, 50, 0)["ok"]).is_false()


func test_rank_up_by_points() -> void:
	var g := _guild()
	var me := RAAdventurerGuild.PLAYER
	# C13 balance change: the thresholds are [0, 150, 450, 1100, 2400, 5200, 11000] (were [0, 60, 180, 450, 1000, 2200, 5000]):
	# S came on day 55 of the balance run, B on day 18.
	assert_int(g.add_points(me, 149)).is_equal(-1)
	assert_int(g.member(me)["rank"]).is_equal(0)
	assert_int(g.add_points(me, 1)).is_equal(1)    # 150 points -> E
	assert_int(g.add_points(me, 300)).is_equal(2)  # 450 -> D
	assert_int(g.add_points(me, 2000)).is_equal(4) # 2450 -> B (skips C)
	# Losing points never demotes.
	g.add_points(me, -2400)
	assert_int(g.member(me)["rank"]).is_equal(4)
	assert_int(g.member(me)["points"]).is_equal(50)
	assert_int(RAAdventurerGuild.rank_for_points(11000)).is_equal(6)


func test_rewards_are_balanced_against_wages() -> void:
	# F: one to two days of a Guard's wage. C: about a week.
	for t in [0.0, 0.5, 1.0]:
		var f: int = RAAdventurerGuild.reward_for(0, t)["gold"]
		assert_int(f).is_between(GUARD_WAGE, GUARD_WAGE * 2)
		var c: int = RAAdventurerGuild.reward_for(3, t)["gold"]
		assert_int(c).is_between(GUARD_WAGE * 6, GUARD_WAGE * 10)
	# Bands grow strictly with rank.
	for r in range(1, 7):
		assert_int(RAAdventurerGuild.reward_for(r, 0.0)["gold"]).is_greater(RAAdventurerGuild.reward_for(r - 1, 0.0)["gold"])


func test_commission_generation_from_world() -> void:
	var g := _guild()
	var board := _full_board(g)
	assert_int(board.size()).is_between(6, RAAdventurerGuild.BOARD_SIZE)
	var types := {}
	for c: Dictionary in board:
		types[c["type"]] = true
		assert_int(c["deadline"]).is_greater(int(c["posted_day"]))
		if c["type"] == "vacancy":
			assert_int(c["reward"]).is_equal(0)
			continue
		var band: Array = RAAdventurerGuild.RANK_GOLD[int(c["rank"])]
		assert_int(c["reward"]).is_between(int(band[0]), int(band[1]))
		assert_int(c["penalty"]["gold"]).is_greater(0)
		assert_int(c["penalty"]["gold"]).is_less(int(c["reward"]))
		if int(c["rank"]) == 0:
			assert_int(c["reward"]).is_between(GUARD_WAGE, GUARD_WAGE * 2)
		if int(c["rank"]) == 3:
			assert_int(c["reward"]).is_between(GUARD_WAGE * 6, GUARD_WAGE * 10)
	assert_bool(types.has("vacancy")).is_true()
	assert_bool(types.has("cull")).is_true()
	# Vacancies mirror the real open seats (Captain is taken, Innkeeper is never advertised).
	var seats := []
	for c: Dictionary in board:
		if c["type"] == "vacancy":
			seats.append("%s/%s" % [c["target"]["org"], c["target"]["seat"]])
	assert_array(seats).contains_exactly_in_any_order(["guard/Guard", "inn/Server"])
	# Den threat maps to rank: the quietest den is F, the worst is S.
	var ranks := []
	for c: Dictionary in board:
		if c["type"] == "cull":
			ranks.append(int(c["rank"]))
	for r: int in ranks:
		assert_int(r).is_between(0, 6)
	# No duplicate postings for the same source.
	var sources := {}
	for c: Dictionary in board:
		assert_bool(sources.has(c["source"])).is_false()
		sources[c["source"]] = true


func test_accept_progress_complete() -> void:
	var g := _guild()
	var me := RAAdventurerGuild.PLAYER
	_full_board(g)
	var c := _find(g, "cull", 0)
	assert_bool(c.is_empty()).is_false()
	var cid := int(c["id"])
	assert_str(g.accept(me, cid, 4)).is_empty()
	assert_str(g.accept(me, cid, 4)).contains("already taken")
	var need := int(c["required"])
	assert_bool(g.complete(me, cid, 4)["ok"]).is_false()
	for k in need - 1:
		g.on_kill(me, "wolf", int(c["target"]["den"]))
	g.on_kill(me, "wolf", 99)   # wrong den: doesn't count
	assert_bool(g.is_ready(cid)).is_false()
	assert_array(g.on_kill(me, "wolf", int(c["target"]["den"]))).contains([cid])
	var r := g.complete(me, cid, 5)
	assert_bool(r["ok"]).is_true()
	assert_int(r["gold"]).is_equal(int(c["reward"]))
	assert_int(g.member(me)["points"]).is_equal(int(c["points"]))
	assert_int(g.member(me)["completed"]).is_equal(1)
	assert_bool(g.commission(cid).is_empty()).is_true()


func test_rank_requirement_and_active_limit() -> void:
	var g := _guild()
	var me := RAAdventurerGuild.PLAYER
	_full_board(g)
	var high := {}
	for c: Dictionary in g.board(0):
		if int(c["rank"]) >= 2:
			high = c
			break
	assert_bool(high.is_empty()).is_false()
	assert_str(g.accept(me, int(high["id"]), 4)).contains("needs rank")
	# One rank above is allowed.
	var e := {}
	for c: Dictionary in g.board(0):
		if int(c["rank"]) == 1 and c["type"] != "vacancy":
			e = c
			break
	if not e.is_empty():
		assert_str(g.accept(me, int(e["id"]), 4)).is_empty()
	assert_str(g.accept(77, int(high["id"]), 4)).contains("Only guild members")


func test_fail_fines_and_deadline() -> void:
	var g := _guild()
	var me := RAAdventurerGuild.PLAYER
	_full_board(g)
	g.add_points(me, 100)
	var a := _find(g, "gather")
	var aid := int(a["id"])
	g.accept(me, aid, 4)
	var f := g.fail(me, aid, 4)
	assert_bool(f["ok"]).is_true()
	assert_int(g.member(me)["debt"]).is_equal(int(a["penalty"]["gold"]))
	assert_int(g.member(me)["points"]).is_equal(100 - int(a["penalty"]["points"]))
	assert_int(g.member(me)["failed"]).is_equal(1)
	# Debt blocks new work until settled.
	var b := _find(g, "cull", 0)
	assert_str(g.accept(me, int(b["id"]), 4)).contains("Settle your fine")
	assert_int(g.settle_debt(me, 1000)).is_equal(int(a["penalty"]["gold"]))
	assert_str(g.accept(me, int(b["id"]), 4)).is_empty()
	# Letting the deadline pass fails it automatically on the daily tick.
	var events := g.tick_day(int(b["deadline"]) + 1)
	var failed := events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "failed")
	assert_int(failed.size()).is_equal(1)
	assert_int(g.member(me)["failed"]).is_equal(2)
	assert_int(g.member(me)["debt"]).is_equal(int(b["penalty"]["gold"]))
	# Untaken postings just expire.
	var expired := events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "expired")
	assert_int(expired.size()).is_greater(0)


func test_vacancy_through_guild_links_careers() -> void:
	var careers := _careers()
	var g := RAAdventurerGuild.new(3)
	g.add_branch(0, "Hall")
	g.context = _world(careers)
	g.join(RAAdventurerGuild.PLAYER, 0, 20, 0)
	g.tick_day(0)
	var v := {}
	for c: Dictionary in g.board(0):
		if c["type"] == "vacancy" and c["target"]["org"] == "guard":
			v = c
	assert_bool(v.is_empty()).is_false()
	assert_str(careers.apply(v["target"]["org"], v["target"]["seat"], 0, 1)).is_empty()
	var r := g.on_hired(RAAdventurerGuild.PLAYER, "guard", "Guard", 1)
	assert_bool(r["ok"]).is_true()
	assert_int(r["points"]).is_equal(RAAdventurerGuild.VACANCY_POINTS)


func test_guild_roundtrip() -> void:
	var g := _guild()
	_full_board(g)
	var c := _find(g, "cull", 0)
	g.accept(RAAdventurerGuild.PLAYER, int(c["id"]), 4)
	g.on_kill(RAAdventurerGuild.PLAYER, "wolf", int(c["target"]["den"]))
	g.add_points(RAAdventurerGuild.PLAYER, 160)         # C13: E needs 150 points now (was 60)
	var data: Variant = JSON.parse_string(JSON.stringify(g.serialize()))
	var h := RAAdventurerGuild.new()
	h.add_branch(0, "Ashford Guild Hall")
	h.context = g.context
	h.deserialize(data)
	assert_int(h.board(0).size()).is_equal(g.board(0).size())
	assert_int(h.member(RAAdventurerGuild.PLAYER)["rank"]).is_equal(1)
	var hc := h.commission(int(c["id"]))
	assert_str(hc["state"]).is_equal("accepted")
	assert_int(hc["progress"]).is_equal(1)
	assert_int(typeof(hc["reward"])).is_equal(TYPE_INT)
	# Both generate the same next day.
	var a1 := g.tick_day(10)
	var a2 := h.tick_day(10)
	assert_int(a2.size()).is_equal(a1.size())


# --- magicules -------------------------------------------------------------------

func test_magicules_overdraw_exhausts_and_hurts() -> void:
	var m := RAMagicules.new(100.0, 2.0, 1)
	assert_bool(m.spend(60.0)["ok"]).is_true()
	assert_float(m.exhaustion).is_equal(0.0)
	assert_bool(m.spend(200.0)["ok"]).is_false()   # beyond the -50% margin
	assert_float(m.current).is_equal(40.0)
	var r := m.spend(85.0)                          # down to -45
	assert_bool(r["ok"]).is_true()
	assert_float(r["overdraw"]).is_equal(45.0)
	assert_bool(m.is_exhausted()).is_true()
	assert_float(m.exhaustion).is_equal_approx(0.9, 0.001)
	assert_float(m.stamina_factor()).is_less(1.0)
	# Deep overdraws hurt sometimes: over many seeds some do, some don't.
	var hurt := 0
	for s in 200:
		var p := RAMagicules.new(100.0, 2.0, s)
		if int(p.spend(145.0)["damage"]) > 0:
			hurt += 1
	assert_int(hurt).is_between(80, 190)   # chance = 0.45 * 1.4 = 63%
	# Regeneration is slowed by exhaustion but gets back to full.
	m.regenerate(10.0)
	assert_float(m.current).is_greater(-45.0)
	m.regenerate(200.0)
	assert_float(m.current).is_equal(100.0)
	assert_float(m.exhaustion).is_equal(0.0)


func test_magicules_roundtrip() -> void:
	var m := RAMagicules.new(80.0, 1.0, 9)
	m.spend(100.0)
	var n := RAMagicules.new()
	n.deserialize(JSON.parse_string(JSON.stringify(m.serialize())))
	assert_float(n.current).is_equal(m.current)
	assert_float(n.exhaustion).is_equal_approx(m.exhaustion, 0.0001)
	var a := n.spend(15.0)
	var b := m.spend(15.0)
	assert_bool(a["ok"]).is_true()
	assert_int(a["damage"]).is_equal(b["damage"])


# --- naming ----------------------------------------------------------------------

func test_naming_cost_scales_with_level_and_power() -> void:
	assert_int(RANaming.cost("goblin", 1)).is_equal(9)
	assert_int(RANaming.cost("wolf", 1)).is_greater(RANaming.cost("goblin", 1))
	assert_int(RANaming.cost("wolf", 5)).is_greater(RANaming.cost("wolf", 1) * 4)
	assert_int(RANaming.cost("ogre", 20)).is_greater(1000)
	assert_array(RANaming.class_options("goblin")).contains(["warrior", "artisan"])
	assert_str(RANaming.evolution_hint("wolf")).contains("Storm Wolf")
	assert_str(RANaming.evolution_hint("goblin")).contains("Hobgoblin")


func test_safe_naming_has_no_consequences() -> void:
	var n := RANaming.new(1)
	var m := RAMagicules.new(100.0, 2.0, 1)
	var inj := RAInjuries.new()
	var r := n.name_monster(m, inj, 10, "goblin", 2, "Rigo", "warrior", 1)
	assert_bool(r["ok"]).is_true()
	assert_float(r["risk"]).is_equal(0.0)
	assert_int(r["soul_fatigue_days"]).is_equal(0)
	assert_int(r["levels_lost"]).is_equal(0)
	assert_array(r["injuries"]).is_empty()
	assert_float(m.current).is_equal(100.0 - RANaming.cost("goblin", 2))
	var sub: Dictionary = r["subordinate"]
	assert_str(sub["form"]).is_equal("Hobgoblin")
	assert_str(sub["class"]).is_equal("warrior")
	assert_int(sub["loyalty"]).is_equal(RANaming.BASE_LOYALTY + RANaming.FAVOURED_LOYALTY)
	assert_int(n.roster.size()).is_equal(1)
	# Invalid class or empty name are refused without cost.
	assert_bool(n.name_monster(m, inj, 10, "goblin", 2, "Gob", "mage", 1)["ok"]).is_false()
	assert_bool(n.name_monster(m, inj, 10, "goblin", 2, "  ", "warrior", 1)["ok"]).is_false()


func test_naming_beyond_reach_is_refused() -> void:
	var n := RANaming.new(1)
	var m := RAMagicules.new(40.0, 1.0, 1)
	var r := n.name_monster(m, RAInjuries.new(), 3, "ogre", 12, "Kurogane", "warrior", 1)
	assert_bool(r["ok"]).is_false()
	assert_float(m.current).is_equal(40.0)
	assert_int(n.roster.size()).is_equal(0)


func _risky(seed_value: int) -> Dictionary:
	var n := RANaming.new(seed_value)
	var m := RAMagicules.new(100.0, 2.0, seed_value)
	m.current = 30.0
	var inj := RAInjuries.new()
	var r := n.name_monster(m, inj, 3, "wolf", 5, "Ranga", "scout", 10)
	return {"r": r, "naming": n, "injuries": inj, "magicules": m}


func test_risky_naming_under_fixed_seed() -> void:
	var out := _risky(42)
	var r: Dictionary = out["r"]
	var n: RANaming = out["naming"]
	var inj: RAInjuries = out["injuries"]
	assert_bool(r["ok"]).is_true()
	assert_str(r["subordinate"]["form"]).is_equal("Storm Wolf")
	# cost 78 with 30 in the pool: 48 overdrawn of 100 -> risk .72 + level gap .12 + power .024
	assert_int(r["cost"]).is_equal(78)
	assert_float(r["risk"]).is_equal_approx(0.864, 0.001)
	# Overdrawing always brings Soul Fatigue.
	assert_int(r["soul_fatigue_days"]).is_equal(7)
	assert_bool(inj.has("soul_fatigue")).is_true()
	assert_bool(RAInjuries.is_healer_only("soul_fatigue")).is_false()
	# Same seed -> same outcome.
	var again: Dictionary = _risky(42)["r"]
	assert_int(again["levels_lost"]).is_equal(r["levels_lost"])
	assert_array(again["injuries"]).is_equal(r["injuries"])
	assert_int(again["damage"]).is_equal(r["damage"])
	# Level loss is temporary.
	if int(r["levels_lost"]) > 0:
		assert_int(n.level_penalty(10)).is_equal(r["levels_lost"])
		n.tick_day(10 + int(r["level_loss_days"]))
		assert_int(n.level_penalty(10 + int(r["level_loss_days"]))).is_equal(0)
	# Soul Fatigue wears off by itself.
	inj.tick_day(10 + int(r["soul_fatigue_days"]))
	assert_bool(inj.has("soul_fatigue")).is_false()


func test_risky_naming_outcome_rates() -> void:
	var lost := 0
	var cores := 0
	for s in 200:
		var r: Dictionary = _risky(s)["r"]
		if int(r["levels_lost"]) > 0:
			lost += 1
		if "fractured_core" in r["injuries"]:
			cores += 1
	# Level loss ~86%, Fractured Core ~49%.
	assert_int(lost).is_between(150, 195)
	assert_int(cores).is_between(70, 130)


func test_roster_loyalty_and_desertion() -> void:
	var n := RANaming.new(5)
	var m := RAMagicules.new(500.0, 5.0, 5)
	var r := n.name_monster(m, null, 20, "kobold", 2, "Pip", "scout", 1)
	var id := int(r["subordinate"]["id"])
	assert_int(n.adjust_loyalty(id, -70)).is_equal(RANaming.BASE_LOYALTY - 70)
	var left := false
	for d in 200:
		for e: Dictionary in n.tick_day(d):
			if e["type"] == "deserted":
				left = true
	assert_bool(left).is_true()
	assert_int(n.roster.size()).is_equal(0)


func test_naming_roundtrip() -> void:
	var out := _risky(42)
	var n: RANaming = out["naming"]
	var d := RANaming.new()
	d.deserialize(JSON.parse_string(JSON.stringify(n.serialize())))
	assert_int(d.roster.size()).is_equal(1)
	assert_str(d.roster[0]["name"]).is_equal("Ranga")
	assert_int(typeof(d.roster[0]["level"])).is_equal(TYPE_INT)
	assert_int(d.level_penalty(10)).is_equal(n.level_penalty(10))
	# RNG state carried over: both roll identically from here.
	var m1 := RAMagicules.new(100.0, 2.0, 1)
	var m2 := RAMagicules.new(100.0, 2.0, 1)
	m1.current = 20.0
	m2.current = 20.0
	var r1 := n.name_monster(m1, RAInjuries.new(), 1, "goblin", 5, "A", "scout", 11)
	var r2 := d.name_monster(m2, RAInjuries.new(), 1, "goblin", 5, "A", "scout", 11)
	assert_bool(r1["ok"]).is_true()
	assert_int(r2["levels_lost"]).is_equal(r1["levels_lost"])
	assert_array(r2["injuries"]).is_equal(r1["injuries"])


# --- injuries & healers -------------------------------------------------------------

func test_fractured_core_needs_a_healer() -> void:
	var inj := RAInjuries.new()
	var core := inj.add("fractured_core", 1)
	inj.add("deep_cut", 1)
	assert_float(inj.effects()["magicule_max"]).is_less(0.0)
	var m := RAMagicules.new(100.0, 2.0, 1)
	m.apply_effects(inj.effects())
	assert_float(m.effective_max()).is_equal_approx(65.0, 0.01)
	# Time heals the cut but never the core.
	var healed := inj.tick_day(1000)
	assert_int(healed.size()).is_equal(1)
	assert_bool(inj.has("fractured_core")).is_true()
	assert_bool(inj.has("deep_cut")).is_false()
	# A village herbalist can't mend it; a temple can, for gold and time.
	var uid := int(core["uid"])
	assert_bool(inj.treat(uid, "herbalist", 9999)["ok"]).is_false()
	var q := inj.quote(uid, "temple")
	assert_int(q["cost"]).is_equal(171)   # ceil(140 * 1.2) + 3
	assert_bool(inj.treat(uid, "temple", 50)["ok"]).is_false()
	assert_bool(inj.has("fractured_core")).is_true()
	var t := inj.treat(uid, "temple", 500)
	assert_bool(t["ok"]).is_true()
	assert_float(t["hours"]).is_equal(48.0)
	assert_bool(inj.has("fractured_core")).is_false()
	m.apply_effects(inj.effects())
	assert_float(m.effective_max()).is_equal(100.0)


func test_healer_prices_match_economy() -> void:
	var herb := RAInjuries.healer_service("herbalist")
	var temple := RAInjuries.healer_service("temple")
	var by_type := {}
	for s: Dictionary in herb["services"]:
		by_type[s["type"]] = s
	assert_bool(by_type.has("fractured_core")).is_false()
	assert_int(by_type["deep_cut"]["cost"]).is_less_equal(GUARD_WAGE)          # under a day's pay
	assert_int(by_type["broken_arm"]["cost"]).is_between(GUARD_WAGE * 2, GUARD_WAGE * 4)
	var core := {}
	for s: Dictionary in temple["services"]:
		if s["type"] == "fractured_core":
			core = s
	assert_int(core["cost"]).is_between(GUARD_WAGE * 14, GUARD_WAGE * 21)    # two to three weeks


func test_injuries_roundtrip() -> void:
	var inj := RAInjuries.new()
	inj.add("fractured_core", 3)
	inj.add("soul_fatigue", 3, 5)
	var d := RAInjuries.new()
	d.deserialize(JSON.parse_string(JSON.stringify(inj.serialize())))
	assert_int(d.active.size()).is_equal(2)
	assert_int(d.find("soul_fatigue")["heals_on"]).is_equal(8)
	assert_int(d.find("fractured_core")["heals_on"]).is_equal(RAInjuries.HEALER_ONLY)
	assert_int(d.add("deep_cut", 4)["uid"]).is_equal(3)


# --- scouts --------------------------------------------------------------------

func _nobody(id: int) -> Dictionary:
	return {"id": id, "name": "Villager %d" % id, "age": 30, "titles": [], "feats": [], "reputation": 0.0}


func _prodigy(id: int) -> Dictionary:
	return {"id": id, "name": "Prodigy", "age": 16, "titles": ["Wolfbane", "Dawn Blade", "Ashford's Hope", "Iron Will", "Keen Eye"],
		"feats": ["a", "b", "c", "d", "e"], "reputation": 100.0}


func test_scouting_is_rare() -> void:
	var s := RAScouts.new(11)
	var n := 0
	for day in 10000:
		if not s.daily_roll(_nobody(day), day).is_empty():
			n += 1
	# 0.15% per day -> ~15 in 10,000 days.
	assert_int(n).is_between(4, 32)


func test_boosts_raise_but_stay_under_one_percent() -> void:
	var s := RAScouts.new(12)
	assert_float(s.daily_chance(_prodigy(1), 0)).is_less(0.01)
	assert_float(s.daily_chance(_prodigy(1), 0)).is_greater(s.daily_chance(_nobody(2), 0))
	var n := 0
	for day in 10000:
		if not s.daily_roll(_prodigy(day), day).is_empty():
			n += 1
	# Capped at 0.9% -> ~90 in 10,000 days.
	assert_int(n).is_between(55, 125)


func test_cooldown_blocks_repeat_scouting() -> void:
	var s := RAScouts.new(13)
	var n := 0
	for day in 10000:
		var e := s.daily_roll(_prodigy(1), day)
		if not e.is_empty():
			n += 1
			s.decline(int(e["id"]))
	assert_int(n).is_less_equal(10000 / RAScouts.COOLDOWN_DAYS + 1)
	assert_int(n).is_greater(10)


func test_scenarios_bring_plausible_scouts() -> void:
	var s := RAScouts.new(14)
	var total := 0
	var soulbeast := 0
	var malformed := 0
	var wrong_org := 0
	var wrong_soulbeast := 0
	for i in 20000:
		var e := s.on_scenario(_prodigy(i), "tournament", 5)
		if e.is_empty():
			continue
		total += 1
		if not (e.has("scout") and e.has("org") and e.has("scenario") and e.has("offer")) \
				or e["scenario"]["id"] != "tournament":
			malformed += 1
		if not e["org"]["id"] in ["army", "academy", "sect"]:
			wrong_org += 1
		if e["offer"]["soulbeast_path"]:
			soulbeast += 1
			if not e["org"]["kind"] in ["academy", "sect"] or e["offer"]["travel_permit"] != "Xiava's Lake":
				wrong_soulbeast += 1
	assert_int(malformed).is_equal(0)
	assert_int(wrong_org).is_equal(0)
	assert_int(wrong_soulbeast).is_equal(0)
	# Capped at 35% per tournament for a prodigy.
	assert_int(total).is_between(6400, 7600)
	# Soulbeast path: ~4% of academy/sect offers only (~2.7% of all).
	assert_float(float(soulbeast) / total).is_between(0.01, 0.05)
	# A patrol only ever brings the army, never a soulbeast.
	var patrol := 0
	var bad_patrol := 0
	for i in 3000:
		var e := s.on_scenario(_nobody(100000 + i), "wolf_pack_patrol", 5)
		if not e.is_empty():
			patrol += 1
			if e["org"]["kind"] != "military" or e["offer"]["soulbeast_path"]:
				bad_patrol += 1
	assert_int(patrol).is_between(100, 270)   # 6% of 3000
	assert_int(bad_patrol).is_equal(0)


func test_scout_recruits_npcs_and_offers_expire() -> void:
	var s := RAScouts.new(15)
	var pop := []
	for i in 400:
		pop.append(_prodigy(i))
	var events := []
	var day := 0
	while events.is_empty() and day < 100:
		events = s.roll_population(pop, day)
		day += 1
	assert_bool(events.is_empty()).is_false()
	var e: Dictionary = events[0]
	var got := s.accept(int(e["id"]), int(e["day"]) + 1)
	assert_bool(got.is_empty()).is_false()
	assert_str(s.recruited[int(e["candidate"])]).is_equal(e["org"]["id"])
	assert_float(s.daily_chance(_prodigy(int(e["candidate"])), 5000)).is_equal(0.0)
	# The other offers lapse if nobody answers.
	var lapsed := s.tick_day(day + RAScouts.OFFER_DAYS + 1)
	assert_int(lapsed.size() + 1).is_equal(events.size())
	assert_int(s.offers.size()).is_equal(0)


func test_scouts_roundtrip() -> void:
	var s := RAScouts.new(16)
	var e := {}
	var i := 0
	while e.is_empty():
		e = s.on_scenario(_prodigy(i), "guild_rank_d", 3)
		i += 1
	var d := RAScouts.new()
	d.deserialize(JSON.parse_string(JSON.stringify(s.serialize())))
	assert_int(d.offers.size()).is_equal(1)
	assert_int(d.offer(int(e["id"]))["offer"]["expires_day"]).is_equal(3 + RAScouts.OFFER_DAYS)
	assert_bool(d.eligible(_prodigy(int(e["candidate"])), 10)).is_false()
	var a := s.on_scenario(_prodigy(9999), "tournament", 4)
	var b := d.on_scenario(_prodigy(9999), "tournament", 4)
	assert_bool(a.is_empty()).is_equal(b.is_empty())
