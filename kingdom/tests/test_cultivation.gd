extends GdUnitTestSuite
## Cultivation: universal ladder, path flavours, meditation, breakthrough risk (deterministic), manuals, saves.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Cult := preload("res://scripts/realm/cultivation.gd")
const Prog := preload("res://scripts/sim/progression.gd")


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk(paths: Array = ["sect"], level := 1) -> RefCounted:
	var c: RefCounted = Hub.new().mod("cultivation")
	for p: String in paths:
		c.begin(p, "academy")
	if level > 1:
		c.prog.grant_raw(Prog.total_xp(level))
	return c


func _ready_to_break(c: RefCounted, path: String) -> void:
	c._tracks[path]["qi"] = 1.0


func test_ladder_shape() -> void:
	var d := Cult.data()
	assert_int((d["realms"] as Array).size()).is_equal(10)
	assert_int(Cult.STAGES).is_equal(9)
	assert_int((d["paths"] as Dictionary).size()).is_equal(5)
	var prev := -1
	for r in range(1, 11):
		for s in range(1, 10):
			var need := Cult.level_needed(r, s)
			assert_int(need).is_greater_equal(prev)
			prev = need
			if s > 1:
				assert_float(Cult.stage_need_eff(r, s)).is_greater(Cult.stage_need_eff(r, s - 1))
	assert_int(Cult.level_needed(10, 9)).is_less_equal(500)
	for r in range(2, 11):
		assert_float(Cult.stage_need_eff(r, 1)).is_greater(Cult.stage_need_eff(r - 1, 9) * 0.9)
	# Region 1 (hard cap level 60) reaches realms 1-3 only
	assert_int(Cult.level_needed(3, 9)).is_less(60)
	assert_int(Cult.level_needed(4, 1)).is_greater(60)


func test_registered_in_hub_and_saves_with_it() -> void:
	var h: RefCounted = Hub.new()
	assert_bool(Hub.MODULES.has("cultivation")).is_true()
	assert_bool(Hub.ORDER.has("cultivation")).is_true()
	var c: RefCounted = h.mod("cultivation")
	c.begin("magic", "academy")
	var d: Dictionary = h.serialize()
	assert_bool(d.has("cultivation")).is_true()
	var h2: RefCounted = Hub.new()
	h2.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_bool(h2.mod("cultivation").has_path("magic")).is_true()


func test_path_flavours_share_one_ladder() -> void:
	var names := {}
	var diagrams := {}
	for p: String in Cult.paths():
		var pd: Dictionary = Cult.path_def(p)
		assert_int((pd["realm_names"] as Array).size()).is_equal(10)
		names[Cult.realm_name(p, 2)] = true
		diagrams[pd["diagram"]] = true
		assert_str(Cult.stage_label(p, 3, 4)).contains("4")
		assert_bool(Cult.techniques_of(p).size() >= 6).is_true()
		assert_bool(Cult.manuals_of(p).size() >= 4).is_true()
	assert_int(names.size()).is_equal(5)
	assert_int(diagrams.size()).is_equal(5)
	assert_str(Cult.realm_name("sect", 4)).is_equal("Golden Core")
	assert_str(Cult.realm_name("magic", 4)).is_equal("Mana Core")
	assert_str(Cult.path_def("sect")["structure"]).contains("meridian")
	assert_str(Cult.path_def("knight")["structure"]).contains("Aura")
	assert_str(Cult.path_def("beast")["structure"]).contains("bond")


func test_begin_learns_power_path_and_first_is_primary() -> void:
	var h: RefCounted = Hub.new()
	var c: RefCounted = h.mod("cultivation")
	assert_bool(c.begin("magic", "academy")).is_true()
	assert_bool(c.begin("magic", "academy")).is_false()
	assert_bool(c.begin("wizardry", "self")).is_false()
	assert_str(c.primary).is_equal("magic")
	assert_bool(h.mod("power_paths").knows("magic")).is_true()
	assert_bool(c.begin("knight", "academy")).is_true()
	assert_str(c.primary).is_equal("magic")


func test_second_path_is_very_slow_and_cannot_outrank_primary() -> void:
	var c := _mk(["sect", "magic", "beast"])
	var p1: float = c.speed_mult("sect")
	var p2: float = c.speed_mult("magic")
	var p3: float = c.speed_mult("beast")
	assert_float(p2).is_less(p1 * 0.4)
	assert_float(p3).is_less(p2)
	assert_float(p3).is_greater(0.0)
	# at the same time invested the secondary gains far less
	var a: Dictionary = c.meditate("sect", 4.0, "wilds", {"day": 1})
	var b: Dictionary = c.meditate("magic", 4.0, "wilds", {"day": 2})
	assert_float(b["frac"]).is_less(a["frac"] * 0.5)
	# primary behind: a secondary path may not step into a realm above the primary's
	c.prog.grant_raw(Prog.total_xp(30))
	c._tracks["magic"]["stage"] = 9
	c._tracks["magic"]["qi"] = 1.0
	c.insight = 100.0
	c.add_resource("herb", 1, 5)
	var info: Dictionary = c.breakthrough_info("magic", {"day": 3})
	assert_str(info["reason"]).is_equal("primary_behind")


func test_location_quality_and_access() -> void:
	var c := _mk(["sect"])
	assert_float(c.density("hidden_vale", "sect")).is_greater(c.density("wilds", "sect"))
	assert_float(c.density("sect_hall", "sect")).is_greater(c.density("sect_hall", "magic"))
	assert_float(c.density("town", "sect")).is_less(c.density("wilds", "sect"))
	assert_bool(c.location_open("hidden_vale")).is_false()
	assert_str(c.meditate("sect", 2.0, "hidden_vale", {"day": 1})["reason"]).is_equal("location_closed")
	c.set_flag("vale_found")
	assert_bool(c.meditate("sect", 2.0, "hidden_vale", {"day": 1})["ok"]).is_true()
	var w := _mk(["sect"])
	var g_wild: float = w.meditate("sect", 4.0, "wilds", {"day": 1})["frac"]
	var v := _mk(["sect"])
	v.set_flag("vale_found")
	var g_vale: float = v.meditate("sect", 4.0, "hidden_vale", {"day": 1})["frac"]
	assert_float(g_vale).is_greater(g_wild * 2.0)


func test_daily_absorption_curve_limits_marathon_sessions() -> void:
	var c := _mk(["sect"])
	var first: float = c.meditate("sect", 4.0, "wilds", {"day": 1})["eff_hours"]
	var second: float = c.meditate("sect", 4.0, "wilds", {"day": 1})["eff_hours"]
	var third: float = c.meditate("sect", 4.0, "wilds", {"day": 1})["eff_hours"]
	assert_float(first).is_equal_approx(4.0, 0.001)
	assert_float(second).is_less(first * 0.5)
	assert_float(third).is_less(second)
	# the next day resets
	assert_float(c.meditate("sect", 4.0, "wilds", {"day": 2})["eff_hours"]).is_equal_approx(4.0, 0.001)


func test_qi_bar_overflow_is_capped() -> void:
	var c := _mk(["sect"])
	for d in range(1, 400):
		c.meditate("sect", 4.0, "wilds", {"day": d})
	assert_float(c.qi_ratio("sect")).is_less_equal(float(Cult.data()["overflow_cap"]) + 0.0001)


func test_breakthrough_requirements_block() -> void:
	var c := _mk(["sect"])
	assert_str(c.breakthrough_info("sect", {"day": 1})["reason"]).is_equal("qi_low")
	_ready_to_break(c, "sect")
	# stage 1 -> 2 needs level 2
	assert_str(c.breakthrough_info("sect", {"day": 1})["reason"]).is_equal("level")
	c.prog.grant_raw(Prog.total_xp(5))
	assert_bool(c.breakthrough_info("sect", {"day": 1})["ok"]).is_true()
	# stage 3 is a minor bottleneck that costs insight
	c._tracks["sect"]["stage"] = 3
	c._tracks["sect"]["qi"] = 1.0
	c.prog.grant_raw(Prog.total_xp(10))
	assert_int(c.insight_needed("sect")).is_greater(0)
	assert_str(c.breakthrough_info("sect", {"day": 1})["reason"]).is_equal("insight")
	c.add_insight(5.0, "quest", "q1")
	assert_bool(c.breakthrough_info("sect", {"day": 1})["ok"]).is_true()
	# a realm boundary needs its catalyst
	c._tracks["sect"]["realm"] = 2
	c._tracks["sect"]["stage"] = 9
	c._tracks["sect"]["qi"] = 1.0
	c.prog.grant_raw(Prog.total_xp(30))
	c.insight = 50.0
	assert_str(c.breakthrough_info("sect", {"day": 1})["reason"]).is_equal("catalyst")
	c.add_resource("herb", 1, 3)
	assert_bool(c.breakthrough_info("sect", {"day": 1})["ok"]).is_true()
	assert_bool(c.breakthrough_info("sect", {"day": 1})["major"]).is_true()


func _run_attempts(seed_: int, n: int) -> Array:
	var c := _mk(["sect"], 40)
	c.reseed(seed_)
	var out: Array = []
	for i in n:
		c._tracks["sect"]["realm"] = 2
		c._tracks["sect"]["stage"] = 1
		c._tracks["sect"]["qi"] = 1.0
		c.insight = 0.0
		c.deviation_until = -1
		c.strain_until = -1
		var r: Dictionary = c.attempt_breakthrough("sect", {"day": 1})
		out.append([r["success"], r["severity"], snappedf(float(r["roll"]), 0.000001)])
	return out


func test_breakthrough_is_deterministic_by_seed() -> void:
	var a := _run_attempts(777, 25)
	var b := _run_attempts(777, 25)
	var other := _run_attempts(778, 25)
	assert_str(_norm(a)).is_equal(_norm(b))
	assert_str(_norm(a)).is_not_equal(_norm(other))


func test_failure_hurts_but_never_loses_the_stage() -> void:
	# find a seed whose first attempt fails
	var c: RefCounted = null
	for sd in range(1, 400):
		c = _mk(["sect"], 40)
		c.reseed(sd)
		c._tracks["sect"]["stage"] = 5
		c._tracks["sect"]["qi"] = 1.0
		c._tracks["sect"]["realm"] = 2
		var chance: float = c.breakthrough_info("sect", {"day": 1})["chance"]
		var r: Dictionary = c.attempt_breakthrough("sect", {"day": 1})
		if not bool(r["success"]):
			assert_int(c.realm_of("sect")).is_equal(2)
			assert_int(c.stage_of("sect")).is_equal(5)
			assert_float(c.qi_ratio("sect")).is_less(0.85)
			assert_int(int(c._tracks["sect"]["fails"])).is_equal(1)
			assert_str(r["severity"]).is_not_empty()
			assert_float(chance).is_less(0.97)
			return
	fail("no failing seed found in 400 tries")


func test_chance_responds_to_preparation_and_trial() -> void:
	var c := _mk(["sect"], 40)
	c._tracks["sect"]["qi"] = 1.0
	c._tracks["sect"]["realm"] = 2
	c._tracks["sect"]["stage"] = 9
	var base: float = c.breakthrough_info("sect", {"day": 1})["chance"]
	var pill: float = c.breakthrough_info("sect", {"day": 1, "pill": true})["chance"]
	var good: float = c.breakthrough_info("sect", {"day": 1, "score": 0.9})["chance"]
	var bad: float = c.breakthrough_info("sect", {"day": 1, "score": 0.1})["chance"]
	c.set_flag("vale_found")
	var vale: float = c.breakthrough_info("sect", {"day": 1, "loc": "hidden_vale"})["chance"]
	assert_float(pill).is_greater(base)
	assert_float(good).is_greater(base)
	assert_float(bad).is_less(base)
	assert_float(vale).is_greater(base)
	# major breakthroughs are riskier than minor ones of the same realm
	c._tracks["sect"]["stage"] = 8
	assert_float(c.breakthrough_info("sect", {"day": 1})["chance"]).is_greater(base)
	# the trial is optional: no score at all is fine
	assert_bool(c.tribulation_spec("sect").is_empty()).is_true()
	c._tracks["sect"]["stage"] = 9
	assert_bool(bool(c.tribulation_spec("sect")["optional"])).is_true()


func test_success_advances_awards_xp_once() -> void:
	var c: RefCounted = null
	for sd in range(1, 100):
		c = _mk(["sect"], 10)
		c.reseed(sd)
		c._tracks["sect"]["qi"] = 1.2
		var xp0: float = c.prog.xp
		var r: Dictionary = c.attempt_breakthrough("sect", {"day": 1})
		if bool(r["success"]):
			assert_int(c.stage_of("sect")).is_equal(2)
			assert_float(c.prog.xp).is_greater(xp0)
			assert_float(c.qi_ratio("sect")).is_less(0.2)
			return
	fail("no successful seed")


func test_resources_and_toxicity() -> void:
	var c := _mk(["beast"], 1)
	c.add_resource("core", 1, 5)
	c.add_resource("herb", 1, 5)
	var r: Dictionary = c.use_resource("beast", "core", 1, {"day": 1})
	assert_bool(r["ok"]).is_true()
	var s := _mk(["sect"], 1)
	s.add_resource("core", 1, 5)
	var r2: Dictionary = s.use_resource("sect", "core", 1, {"day": 1})
	assert_float(r["frac"]).is_greater(r2["frac"])
	# wolfing pills drives toxicity past 1 and cuts gains
	var t := _mk(["sect"], 1)
	t.add_resource("pill", 1, 10)
	var f0: float = t.use_resource("sect", "pill", 1, {"day": 1})["frac"]
	t.use_resource("sect", "pill", 1, {"day": 1})
	t.use_resource("sect", "pill", 1, {"day": 1})
	assert_float(t.toxicity).is_greater(1.0)
	t.deviation_until = -1
	var f3: float = t.use_resource("sect", "pill", 1, {"day": 1})["frac"] if not t.is_deviated(1) else 0.0
	assert_float(f3).is_less(f0)
	t.tick_day(3, {})
	assert_float(t.toxicity).is_less(1.2)
	assert_bool(t.use_resource("sect", "herb", 1, {"day": 3})["ok"] == false).is_true()


func test_deviation_stops_meditation_until_it_passes() -> void:
	var c := _mk(["sect"])
	c._day = 5
	c.deviation_until = 10
	assert_str(c.meditate("sect", 2.0, "wilds", {"day": 5})["reason"]).is_equal("deviated")
	c.tick_day(10, {})
	assert_bool(c.meditate("sect", 2.0, "wilds", {"day": 10})["ok"]).is_true()


func test_insight_sources_are_once_and_diminish() -> void:
	var c := _mk(["sect"])
	var a: float = c.add_insight(1.0, "discovery", "ruin")
	assert_float(a).is_greater(0.0)
	assert_float(c.add_insight(1.0, "discovery", "ruin")).is_equal(0.0)
	var x: float = c.add_insight(1.0, "spar")
	var y: float = c.add_insight(1.0, "spar")
	assert_float(y).is_less(x)


func test_manuals_gate_techniques_by_realm_not_level() -> void:
	var c := _mk(["magic"], 200)
	assert_bool(c.technique_unlocked("mg_spark")).is_false()     # no manual yet, despite level 200
	assert_bool(c.learn_manual("m_mg1")["ok"]).is_true()
	assert_bool(c.learn_manual("m_mg1")["ok"]).is_false()
	assert_bool(c.technique_unlocked("mg_spark")).is_false()     # needs stage 4
	c._tracks["magic"]["stage"] = 4
	assert_bool(c.technique_unlocked("mg_spark")).is_true()
	assert_bool(c.learn_manual("m_bn1")["ok"]).is_false()        # not cultivating bending
	# chantless casting is an advanced art
	assert_bool(c.learn_manual("m_mg4")["ok"]).is_false()        # too advanced at realm 1
	c._tracks["magic"]["realm"] = 4
	c._tracks["magic"]["stage"] = 1
	assert_bool(c.learn_manual("m_mg4")["ok"]).is_true()
	assert_bool(c.technique_unlocked("mg_chantless")).is_true()
	var states: Array = c.technique_states("magic")
	assert_bool(states.any(func(t: Dictionary) -> bool: return t["state"] == "ready")).is_true()
	assert_bool(states.any(func(t: Dictionary) -> bool: return t["state"] == "locked")).is_true()


func test_cultivation_outweighs_level() -> void:
	var low_level_realm3 := _mk(["sect"], 1)
	low_level_realm3._tracks["sect"]["realm"] = 3
	var high_level_none := _mk(["sect"], 55)
	assert_float(low_level_realm3.combined_power()).is_greater(high_level_none.combined_power())
	var dual := _mk(["sect", "magic"], 1)
	dual._tracks["sect"]["realm"] = 3
	dual._tracks["magic"]["realm"] = 3
	assert_float(dual.power_multiplier()).is_less(low_level_realm3.power_multiplier() * 1.3)


func test_second_path_progress_is_tiny_compared_to_primary_over_a_season() -> void:
	var c := _mk(["knight", "beast"], 30)
	for d in range(1, 91):
		c.tick_day(d, {})
		c.meditate("knight", 4.0, "wilds", {"day": d})
		c.meditate("beast", 4.0, "wilds", {"day": d})
		for p: String in ["knight", "beast"]:
			if c.breakthrough_info(p, {"day": d})["ok"]:
				c.attempt_breakthrough(p, {"day": d})
	assert_int(c.position("knight")).is_greater(c.position("beast"))
	assert_int(c.position("beast") - 1).is_less_equal((c.position("knight") - 1) * 2 / 3)


func test_save_round_trip_keeps_the_rng_stream() -> void:
	var c := _mk(["sect", "knight"], 25)
	c.set_flag("vale_found")
	c.add_resource("herb", 2, 3)
	c.add_insight(4.0, "lore", "l1")
	c.learn_manual("m_st1")
	c.meditate("sect", 4.0, "hidden_vale", {"day": 4})
	c.deviation_until = 9
	var d: Dictionary = c.serialize()
	var c2: RefCounted = Hub.new().mod("cultivation")
	c2.deserialize(JSON.parse_string(JSON.stringify(d)))
	assert_str(_norm(c2.serialize())).is_equal(_norm(d))
	# both continue identically
	for x: RefCounted in [c, c2]:
		x.deviation_until = -1
		x._tracks["sect"]["qi"] = 1.0
		x._tracks["sect"]["realm"] = 2
		x._tracks["sect"]["stage"] = 2
	var ra: Dictionary = c.attempt_breakthrough("sect", {"day": 5})
	var rb: Dictionary = c2.attempt_breakthrough("sect", {"day": 5})
	assert_str(_norm(ra)).is_equal(_norm(rb))
	assert_int(c2.prog.level).is_equal(c.prog.level)
	assert_bool(c2.knows_manual("m_st1")).is_true()


func test_progression_lives_in_the_module() -> void:
	var c := _mk(["sect"])
	c.prog.award("quest", {"id": "a", "content_level": 1})
	var d: Dictionary = c.serialize()
	assert_float(float(d["prog"]["xp"])).is_greater(0.0)
