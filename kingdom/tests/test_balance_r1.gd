extends GdUnitTestSuite
## Region 1 balance (packages L18 + C13): a short version of tools_qa/region1/balance_run.gd (30 game days, one seed per archetype, the
## nearest 14 markets) through the real game systems, asserted against the plan's targets (docs/regions/BALANCE_R1.md,
## data/region1/progression_spine.json): the first house within 25 days, no archetype near its top rank before day 60, no money loop
## (bounded daily gain, the exploit caps hold), nobody starves, progress on every ladder; plus the town-kit quest reward limits,
## the Soldier pay against the other careers, the soldier / Wardwright rank timing and the Rift gate rules. About 40 s.

const Sim := preload("res://tools_qa/region1/balance_sim.gd")
const Probe := preload("res://tools_qa/region1/balance_probe.gd")
const Spine := preload("res://scripts/region1/progression_spine.gd")
const SoldierCareer := preload("res://scripts/sim/soldier_career.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const CasualWork := preload("res://scripts/sim/casual_work.gd")
const Pickpocket := preload("res://scripts/sim/pickpocket.gd")
const Equipment := preload("res://scripts/sim/equipment.gd")
const Trades := preload("res://scripts/realm/career_trades.gd")

const DAYS := 30
const MARKETS := 14
static var _runs: Dictionary = {}            # arch -> [summary, sim]


func after() -> void:
	Life.reset()
	CasualWork.reset()
	Pickpocket.reset()


func _run(arch: String) -> Dictionary:
	if not _runs.has(arch):
		var sim: RefCounted = Sim.new(arch, 1, DAYS)
		sim.markets_limit = MARKETS
		_runs[arch] = [sim.run(), sim]
	return _runs[arch][0]


func _sim(arch: String) -> RefCounted:
	_run(arch)
	return _runs[arch][1]


# ---------------------------------------------------------------- the plan's targets, per archetype

func test_every_archetype_owns_a_house_within_25_days() -> void:
	var limit := int(Spine.targets()["first_house_day_max"])
	for a: String in Sim.ARCHETYPES:
		var fd: Dictionary = _run(a)["first_day"]
		assert_bool(fd.has("house")).override_failure_message("%s never bought a house in %d days" % [a, DAYS]).is_true()
		assert_int(int(fd["house"])).override_failure_message("%s: first house on day %d" % [a, int(fd.get("house", -1))]).is_less_equal(limit)


func test_nobody_is_near_a_top_rank_before_day_60() -> void:
	var limit := int(Spine.targets()["top_rank_day_min"])
	for a: String in Sim.ARCHETYPES:
		var fd: Dictionary = _run(a)["first_day"]
		assert_bool(not fd.has("rank_top") or int(fd["rank_top"]) >= limit).override_failure_message("%s reached its top rank on day %s" % [a, str(fd.get("rank_top"))]).is_true()
	# And the data cannot do it either: the soldier needs at least 60 days of service in the ranks below the top, the Wardwright too.
	var soldier_days := 0
	for i in range(1, SoldierCareer.rank_count()):
		soldier_days += int(SoldierCareer.rank_def(i)["min_days"])
	assert_int(soldier_days).is_greater_equal(limit)
	for career: String in ["wardwright", "farmer", "merchant"]:
		var days := 0
		var l := CareerLadders.ladder(career)
		for i in range(1, l.size() - 1 if career != "wardwright" else l.size()):
			days += int((l[i]["requires"] as Dictionary).get("days_in_rank", 0))
		assert_int(days).override_failure_message("%s ladder: %d days to the top" % [career, days]).is_greater_equal(limit if career == "wardwright" else 40)


func test_progress_on_every_ladder_and_nobody_starves() -> void:
	for a: String in Sim.ARCHETYPES:
		var sm := _run(a)
		assert_int(int(sm["career_rank"])).override_failure_message("%s rank %d" % [a, int(sm["career_rank"])]).is_greater_equal(1 if a == "merchant" else 2)
		assert_int(int(sm["soul_tier"])).override_failure_message("%s soul tier %d" % [a, int(sm["soul_tier"])]).is_greater_equal(1)
		assert_int(int(sm["level"])).override_failure_message("%s level %d" % [a, int(sm["level"])]).is_greater_equal(3)
		assert_float(float(sm["fed_share"])).override_failure_message("%s fed %.2f" % [a, float(sm["fed_share"])]).is_greater_equal(float(Spine.targets()["fed_share_min"]))
		assert_int(int(sm["gear_tier"])).override_failure_message("%s gear tier %d at day %d" % [a, int(sm["gear_tier"]), DAYS]).is_less_equal(2)


func test_wardwright_is_a_paid_career() -> void:
	var sm := _run("wardwright")
	assert_int(int(sm["income"].get("ledger_trades", 0))).override_failure_message("Wardwright earned nothing from the Legion").is_greater(200)
	assert_str(String(sm["career_rank_name"])).is_not_equal("none")


# ---------------------------------------------------------------- no money loop

func test_gold_growth_is_bounded_and_no_single_day_is_a_jackpot() -> void:
	var cap_day := float(Spine.targets()["money"]["gold_per_day_max"])
	for a: String in Sim.ARCHETYPES:
		var rows: Array = (_sim(a).rows)
		var last10 := float(int(rows[rows.size() - 1]["gold"]) - int(rows[rows.size() - 11]["gold"])) / 10.0
		assert_float(last10).override_failure_message("%s gains %.0f gold a day at the end" % [a, last10]).is_less(cap_day)
		var best := 0
		for i in range(1, rows.size()):
			best = maxi(best, int(rows[i]["gold"]) - int(rows[i - 1]["gold"]))
		assert_int(best).override_failure_message("%s: best day +%d gold" % [a, best]).is_less(400)
		assert_int(int(_run(a)["gold_peak"])).is_less(int(cap_day) * DAYS)


func test_the_farm_work_spot_has_a_daily_cap() -> void:
	CasualWork.reset()
	var total := 0
	for i in 40:
		total += CasualWork.pay_for("farm_work", 7, 6)
	assert_int(total).override_failure_message("40 shifts in a day paid %d" % total).is_less_equal(20)
	assert_int(CasualWork.pay_for("farm_work", 8, 6)).is_equal(6)          # the next day starts fresh


func test_pickpocketing_tops_out_far_below_the_old_hundred_and_eighty_a_day() -> void:
	Pickpocket.reset()
	var res := Probe.probe_pickpocket(6, 5.0, 1.0)
	assert_float(float(res["gold_per_day"])).override_failure_message("pickpocketing paid %.0f gold a day" % float(res["gold_per_day"])).is_less(60.0)
	Pickpocket.reset()
	var warm := Pickpocket.chance(5.0, 1.0, 0.6, true, 0, true, 0)
	assert_float(Pickpocket.chance(5.0, 1.0, 0.6, true, 0, true, 8)).is_less(warm * 0.4)


func test_same_market_buy_and_sell_never_pays_and_crafting_margins_stay_small() -> void:
	Life.reset()
	var loops := Probe.probe_loops()
	assert_int(int(loops["round_trip"]["profitable_items"])).is_equal(0)
	assert_float(float(loops["crafting"]["best_margin"])).override_failure_message("best crafting margin %s" % str(loops["crafting"]["best_margin"])).is_less_equal(15.0)


# ---------------------------------------------------------------- town-kit quests and pay

func test_town_kit_quest_rewards_have_no_outliers() -> void:
	var q := Probe.probe_quests()
	assert_int(int(q["town_count"])).is_equal(30)
	assert_int(int(q["quests"])).is_equal(90)
	assert_int(int(q["max_quest"])).is_less_equal(32)
	assert_float(float(q["worst_premium"])).is_less_equal(1.36)
	assert_array(q["outliers"]).override_failure_message("town reward outliers: %s" % str(q["outliers"])).is_empty()
	for t: String in q["towns"]:
		assert_int(int(q["towns"][t]["total"])).override_failure_message("%s pays %d gold over its three quests" % [t, int(q["towns"][t]["total"])]).is_less_equal(80)


func test_soldier_pay_is_in_line_with_the_other_careers() -> void:
	var w := Probe.probe_wages()
	var soldier: Array = w["soldier"]
	for i in range(1, soldier.size()):
		assert_float(float(soldier[i])).is_greater(float(soldier[i - 1]))
	# A recruit earns about half of what a tenant farmer or a Stone-Tender does and a lieutenant about what a master of those trades does.
	assert_float(float(soldier[0])).is_between(0.4 * float(w["farmer_by_mastery_1_10_20_30_40"][0]), 1.2 * float(w["farmer_by_mastery_1_10_20_30_40"][0]))
	assert_float(float(soldier[soldier.size() - 1])).is_between(0.7 * float(w["farmer_by_mastery_1_10_20_30_40"][3]), 1.6 * float(w["farmer_by_mastery_1_10_20_30_40"][3]))
	assert_float(float(w["wardwright"][0])).is_less(2.5 * float(soldier[0]))


# ---------------------------------------------------------------- the Wardwright trade (Runeward Legion)

func _ward() -> RefCounted:
	var hub: RefCounted = preload("res://scripts/realm/realm_hub.gd").new()
	var tr: RefCounted = hub.mod("trades")
	tr.mastery_ref = preload("res://scripts/sim/mastery.gd").new()
	tr.bio_ref = preload("res://scripts/sim/biography.gd").new()
	tr.gold_ref = 100
	tr.sync_life = false
	return tr


func test_only_legion_members_are_paid_for_stone_work() -> void:
	var tr := _ward()
	assert_bool(bool(tr.stone_work("mend", 0.4, 0.8, 5)["ok"])).is_false()
	assert_int(tr.pending_gold).is_equal(0)
	assert_bool(bool(tr.join("wardwright", 5)["ok"])).is_true()
	assert_str(tr.rank_of("wardwright")).is_equal("stone_tender")
	assert_bool(bool(tr.stone_work("mend", 0.4, 0.8, 5)["ok"])).is_true()
	assert_int(tr.pending_gold).is_greater(0)


func test_mending_a_sound_stone_again_and_again_pays_nothing_more() -> void:
	var tr := _ward()
	tr.join("wardwright", 1)
	tr.stone_work("mend", 0.95, 0.8, 3)                 # a sound stone: only the day's round pays
	var after_round: int = tr.pending_gold
	assert_int(after_round).is_between(3, 12)
	for i in 30:
		tr.stone_work("mend", 0.97, 1.0, 3)
	assert_int(tr.pending_gold).override_failure_message("repeat mending of sound stones paid %d" % (tr.pending_gold - after_round)).is_equal(after_round)
	# A stone that needs it pays more, in proportion.
	tr.stone_work("mend", 0.3, 0.8, 3)
	var needy: int = tr.pending_gold - after_round
	tr.stone_work("mend", 0.8, 0.8, 3)
	var slight: int = tr.pending_gold - after_round - needy
	assert_int(needy).is_greater(slight)


func test_glyph_fees_stop_after_three_a_day_and_the_stipend_is_docked() -> void:
	var tr := _ward()
	tr.join("wardwright", 1)
	var paid := 0
	for i in 8:
		var before: int = tr.pending_gold
		tr.stone_work("carve", 1.0, 0.8, 4)
		if tr.pending_gold > before:
			paid += 1
	assert_int(paid).is_equal(3)
	assert_int(int(tr.stats["wardwright"]["glyphs_carved"])).is_equal(8)        # the counter still counts every glyph for the ladder
	var full: int = tr.ward_stipend(4)
	assert_int(full).is_equal(int(Trades.ward_data()["stipend_week"][0]))
	assert_int(tr.ward_stipend(2)).is_equal(int(round(float(full) * 2.0 / 4.0)))
	assert_int(tr.ward_stipend(0)).is_equal(0)


func test_the_wardwright_ladder_has_five_ranks_and_cannot_be_rushed() -> void:
	var l := CareerLadders.ladder("wardwright")
	assert_int(l.size()).is_equal(5)
	var days := 0
	for i in range(1, l.size()):
		days += int((l[i]["requires"] as Dictionary).get("days_in_rank", 0))
		assert_bool((l[i]["requires"] as Dictionary).has("stats")).is_true()
	assert_int(days).is_greater_equal(int(Spine.targets()["top_rank_day_min"]))


# ---------------------------------------------------------------- the spine and the Rift gate

func test_spine_targets_and_rift_gate() -> void:
	var t := Spine.targets()
	assert_vector(Vector2(float(t["soul_tier"][0]), float(t["soul_tier"][1]))).is_equal(Vector2(3, 4))
	assert_vector(Vector2(float(t["career_rank"][0]), float(t["career_rank"][1]))).is_equal(Vector2(4, 5))
	assert_vector(Vector2(float(t["gear_tier"][0]), float(t["gear_tier"][1]))).is_equal(Vector2(2, 2))
	var closed := Spine.rift_gate({"story_done": true, "soul_tier": 2, "gear_tier": 2, "level": 20})
	assert_bool(bool(closed["open"])).is_false()
	assert_int((closed["missing"] as PackedStringArray).size()).is_equal(1)
	assert_bool(bool(Spine.rift_gate({"story_done": true, "soul_tier": 3, "gear_tier": 2, "level": 12})["open"])).is_true()
	assert_bool(bool(Spine.rift_gate({"story_done": false, "soul_tier": 4, "gear_tier": 3, "level": 30})["open"])).is_false()
	assert_bool(Spine.power_ready(3, 2, 12)).is_true()
	assert_bool(Spine.power_ready(3, 1, 12)).is_false()


func test_the_main_quest_opens_the_rift_only_to_a_ready_player() -> void:
	var DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/quests/r1_main.json"))
	var cond: Dictionary = {}
	for st: Dictionary in js["steps"]:
		if String(st["id"]) == "a5_rifts_edge":
			cond = (st["requires"] as Dictionary).get("if", {})
	assert_bool(cond.is_empty()).is_false()
	assert_bool(DialogueRunner.check(cond, {"soul_tier": 2, "gear_tier": 2, "level": 20})).is_false()
	assert_bool(DialogueRunner.check(cond, {"soul_tier": 3, "gear_tier": 1, "level": 20})).is_false()
	assert_bool(DialogueRunner.check(cond, {"soul_tier": 3, "gear_tier": 2, "level": 11})).is_false()
	assert_bool(DialogueRunner.check(cond, {"soul_tier": 3, "gear_tier": 2, "level": 12})).is_true()
	assert_bool(DialogueRunner.check(cond, {})).is_true()            # a context without the figures (tests, plain talk) is not gated


func test_gear_levels_are_a_rule() -> void:
	assert_bool(Equipment.ENFORCE_LEVEL).is_true()
	Life.reset()
	Life.give("steel_sword", 1)
	var msg: String = Life.equipment.equip_from(Life, "steel_sword")
	assert_str(msg).contains("You need level")
	assert_str(Life.equipment.item_in("main_hand")).is_not_equal("steel_sword")
	# Issued kit is exempt.
	assert_str(Life.equipment.equip_from(Life, "steel_sword", -1, true)).contains("equip")


# ---------------------------------------------------------------- determinism

func test_runs_are_deterministic_by_seed() -> void:
	var a: RefCounted = Sim.new("farmer", 2, 10)
	a.markets_limit = MARKETS
	a.run()
	var csv_a: String = a.csv()
	var b: RefCounted = Sim.new("farmer", 2, 10)
	b.markets_limit = MARKETS
	b.run()
	assert_str(b.csv()).is_equal(csv_a)
