extends GdUnitTestSuite
## Governance (CIV-B): named leaders with traits, succession, councils, regional laws other systems enforce,
## public opinion with reactions, the player-led settlement API, determinism, catch_up, save round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0, "player_pos": Vector2.ZERO}
const NEEDED := ["settlements", "city_life", "governance"]


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	hub.warm_up()
	return hub


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _run(hub: RefCounted, from_day: int, to_day: int, names: Array = NEEDED) -> void:
	for day in range(from_day, to_day + 1):
		for k: String in names:
			var m: RefCounted = hub.mod(k)
			var ch: Array = m.tick_day_chunks(day, CTX)
			if ch.is_empty():
				m.tick_day(day, CTX)
			else:
				for c: Callable in ch:
					c.call()


func test_every_institution_has_a_named_leader_with_traits() -> void:
	var g: RefCounted = _mk().mod("governance")
	var insts: Array = g.institutions()
	assert_int(insts.size()).is_greater(WorldGen.settlements.size())
	var kinds := {}
	for i: Dictionary in insts:
		kinds[i["kind"]] = true
		var ld: Dictionary = i["leader_info"]
		assert_str(String(ld["n"])).is_not_empty()
		for t: String in ["competence", "greed", "piety", "martial", "openness"]:
			assert_bool(ld["tr"].has(t)).is_true()
		assert_int(int(ld["age"])).is_greater(20)
	for k in ["settlement", "guild", "company", "order"]:
		assert_bool(kinds.has(k)).override_failure_message("no %s institution" % k).is_true()
	var L: Dictionary = g.leader_of_settlement(0)
	assert_str(String(L["n"])).is_not_empty()
	assert_float(g.leader_quality(0)).is_between(0.0, 1.0)


func test_laws_are_exposed_and_hooks_enforce_them() -> void:
	var g: RefCounted = _mk().mod("governance")
	for key: String in g.LAWS:
		assert_bool((g.LAWS[key] as Array).has(g.law(0, key))).is_true()
	assert_str(g.law(0, "no_such_law")).is_empty()
	g.set_law(0, "weapons", 2)
	assert_str(g.law(0, "weapons")).is_equal("restricted")
	assert_bool(g.weapons_violation(0, true)).is_true()
	assert_bool(g.weapons_violation(0, false)).is_false()
	g.set_law(0, "weapons", 0)
	assert_bool(g.weapons_violation(0, true)).is_false()
	# Monster parts: a real drop from loot.json, refused only where banned.
	assert_bool(g.is_monster_part("wolf_fang")).is_true()
	assert_bool(g.is_monster_part("wolf_meat")).is_false()
	assert_bool(g.is_monster_part("iron_sword")).is_false()
	g.set_law(1, "monster_part_trade", 2)
	assert_str(g.refuses_item(1, "wolf_fang")).is_not_empty()
	assert_str(g.refuses_item(1, "iron_sword")).is_empty()
	g.set_law(1, "monster_part_trade", 0)
	assert_str(g.refuses_item(1, "wolf_fang")).is_empty()
	g.set_law(2, "curfew", 1)
	assert_bool(g.curfew_active(2, 23)).is_true()
	assert_bool(g.curfew_active(2, 12)).is_false()
	g.set_law(2, "curfew", 0)
	assert_bool(g.curfew_active(2, 23)).is_false()
	g.set_law(3, "hunting_rights", 2)
	assert_bool(g.hunting_allowed(3)).is_false()
	assert_float(g.law_harshness(3)).is_between(0.0, 1.0)


func test_society_knows_the_illegal_arms_crime() -> void:
	var hub := _mk()
	var soc: RefCounted = hub.mod("society")
	assert_bool(soc.CRIMES.has("illegal_arms")).is_true()
	var res: Dictionary = soc.commit_crime("illegal_arms", 0, 1)
	assert_bool(bool(res["ok"])).is_true()


func test_leaders_age_die_and_are_succeeded() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var before := {}
	for i: Dictionary in g.institutions("settlement"):
		before[i["id"]] = i["leader_info"]["n"]
	_run(hub, 1, 360 * 8, ["governance"])
	var changed := 0
	for i: Dictionary in g.institutions("settlement"):
		if before[i["id"]] != i["leader_info"]["n"]:
			changed += 1
	assert_int(changed).is_greater(0)
	assert_bool(g.chronicle().size() > 0).is_true()
	var seen := false
	for e: Dictionary in g.news_events():
		if String(e["kind"]) == "succession":
			seen = true
	assert_bool(seen).is_true()
	# Every seat still has a living leader.
	for i: Dictionary in g.institutions():
		assert_str(String(i["leader_info"].get("n", ""))).is_not_empty()


func test_heredity_uses_the_heir_and_death_runs_succession() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var castle := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "castle":
			castle = int(s["id"])
	assert_int(castle).is_greater(-1)
	var iid := "s:%d" % castle
	var old: Dictionary = g.leader(iid)
	assert_str(String(g.institution(iid)["succ"])).is_equal("heredity")
	var heir: Dictionary = g._ppl[old["id"]]["heir"]
	assert_bool(not heir.is_empty()).is_true()
	g._day = 100
	var msgs: Array = []
	g._succeed(iid, "death", msgs)
	var now: Dictionary = g.leader(iid)
	assert_str(String(now["n"])).is_equal(String(heir["n"]))
	assert_bool(msgs.size() > 0).is_true()


func test_council_votes_are_weighted_and_apply_law_changes() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var town := -1
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "town":
			town = int(s["id"])
			break
	var council: Dictionary = g.council(town)
	assert_int((council["seats"] as Dictionary).size()).is_equal(6)
	for seat: String in ["merchants", "military", "landowners", "guilds", "temple", "commons"]:
		assert_bool((council["seats"] as Dictionary).has(seat)).is_true()
	assert_bool(g.council(_village()).is_empty()).is_true()   # villages have a headman, not a council
	var res: Dictionary = g.vote(town, {"kind": "tax", "delta": 0.05})
	assert_bool(res.has("passed") and res.has("yes") and res.has("total")).is_true()
	assert_float(float(res["total"])).is_greater(0.0)
	# A proposal every seat likes passes and is applied.
	g.set_law(town, "conscription", 1)
	var lvl: int = g.law_level(town, "conscription")
	var applied := false
	for day in 40:
		g._day = day
		var r: Dictionary = g.vote(town, {"kind": "law", "key": "monster_part_trade", "delta": -1})
		if bool(r["passed"]):
			applied = true
			break
	assert_bool(applied or g.law_level(town, "monster_part_trade") == 0).is_true()
	assert_int(g.law_level(town, "conscription")).is_equal(lvl)
	var t0: float = g.tax(town)
	var out: Dictionary = g.propose(town, {"kind": "tax", "delta": 0.05})
	if bool(out["passed"]):
		assert_float(g.tax(town)).is_equal_approx(minf(0.35, t0 + 0.05), 0.001)


func _village() -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == "village":
			return int(s["id"])
	return 0


func test_opinion_reacts_to_laws_and_shocks_with_petitions_and_emigration() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var sid := _village()
	g.set_law(sid, "hunting_rights", 0)
	var calm: float = g.emigration_pressure(sid)
	for day in range(91, 160):   # after the season of grace
		g.shock(sid, {"poor": -0.35, "farmers": -0.3})
		_run(hub, day, day)
	assert_float(g.opinion(sid, "poor")).is_less(-0.3)
	assert_float(g.emigration_pressure(sid)).is_greater(calm)
	var kinds := {}
	for e: Dictionary in g.news_events():
		kinds[e["kind"]] = true
	assert_bool(kinds.has("petition") or kinds.has("strike") or kinds.has("revolt")).is_true()
	var ap: Dictionary = g.approval(sid)
	for b: String in g.BLOCS:
		assert_bool(ap.has(b)).is_true()


func test_revolt_deposes_a_hated_ruler() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var sid := _village()
	var ruler: String = g.leader_of_settlement(sid)["n"]
	var revolted := false
	for day in range(1, 400):
		g.shock(sid, {"poor": -0.6, "farmers": -0.6, "merchants": -0.5, "soldiers": -0.4, "clergy": -0.4, "scholars": -0.4, "outsiders": -0.4})
		_run(hub, day, day)
		for e: Dictionary in g.news_events():
			if String(e["kind"]) == "revolt" and int(e["sid"]) == sid:
				revolted = true
		if revolted:
			break
	assert_bool(revolted).is_true()
	assert_str(String(g.leader_of_settlement(sid)["n"])).is_not_equal(ruler)


func test_player_led_settlement_priorities_and_appointments() -> void:
	var hub := _mk()
	var g: RefCounted = hub.mod("governance")
	var sid := _village()
	assert_bool(g.set_priorities(sid, {"defence": 1.0})).is_false()   # not the ruler yet
	assert_bool(g.set_player_ruler(sid, true, "Wanderer", 0.7)).is_true()
	assert_str(String(g.leader_of_settlement(sid)["n"])).is_equal("Wanderer")
	var base: Dictionary = g._target(sid)
	assert_bool(g.set_priorities(sid, {"defence": 10.0, "welfare": 0.0})).is_true()
	var tuned: Dictionary = g._target(sid)
	assert_float(float(tuned["soldiers"])).is_greater(float(base["soldiers"]))
	assert_float(float(tuned["poor"])).is_less(float(base["poor"]) + 0.0001)
	var q0: float = g.leader_quality(sid)
	assert_bool(g.appoint(sid, "steward", {"name": "Brenna Hale", "competence": 0.95})).is_true()
	assert_float(g.leader_quality(sid)).is_greater(q0)
	assert_bool(g.appointments(sid).has("steward")).is_true()
	assert_bool(g.set_tax(sid, 0.3)).is_true()
	assert_float(g.tax(sid)).is_equal_approx(0.3, 0.001)
	assert_bool(g.set_law_by_player(sid, "curfew", 2)).is_true()
	assert_str(g.law(sid, "curfew")).is_equal("strict")
	# The player ruler never dies of old age in the sim.
	_run(hub, 1, 360 * 3, ["governance"])
	assert_str(String(g.leader_of_settlement(sid)["n"])).is_equal("Wanderer")


func test_determinism_and_save_round_trip() -> void:
	var a := _mk()
	var b := _mk()
	_run(a, 1, 300)
	_run(b, 1, 300)
	assert_str(_norm(a.mod("governance").serialize())).is_equal(_norm(b.mod("governance").serialize()))
	var c := _mk()
	for k: String in NEEDED + ["notables"]:   # governance asks notables to fill chairs, so its state travels too
		c.mod(k).deserialize(JSON.parse_string(JSON.stringify(a.mod(k).serialize())))
	assert_str(_norm(c.mod("governance").serialize())).is_equal(_norm(a.mod("governance").serialize()))
	# The restored realm keeps ticking identically to the original.
	_run(a, 301, 380)
	_run(c, 301, 380)
	assert_str(_norm(c.mod("governance").serialize())).is_equal(_norm(a.mod("governance").serialize()))


func test_catch_up_matches_day_by_day_within_tolerance() -> void:
	var a := _mk()
	var b := _mk()
	_run(a, 1, 1)
	_run(b, 1, 1)
	_run(a, 2, 241)
	b.mod("governance").catch_up(240, CTX)
	var ga: RefCounted = a.mod("governance")
	var gb: RefCounted = b.mod("governance")
	assert_int(gb.institutions().size()).is_equal(ga.institutions().size())
	var worst := 0.0
	var total := 0.0
	var count := 0
	for sid in WorldGen.settlements.size():
		for bloc: String in ga.BLOCS:
			var d: float = absf(ga.opinion(sid, bloc) - gb.opinion(sid, bloc))
			worst = maxf(worst, d)
			total += d
			count += 1
	print("governance catch_up vs day-by-day: mean |d opinion| %.3f, worst %.3f" % [total / float(count), worst])
	assert_float(total / float(count)).is_less(0.2)    # the same mood on average
	assert_float(worst).is_less(0.9)                     # a settlement that took a different law path can differ
	for i: Dictionary in gb.institutions():
		assert_str(String(i["leader_info"].get("n", ""))).is_not_empty()
	# Leadership churn is the same order of magnitude.
	var ca := 0
	var cb := 0
	for e: Dictionary in ga.news_events():
		ca += 1 if String(e["kind"]) == "succession" else 0
	for e: Dictionary in gb.news_events():
		cb += 1 if String(e["kind"]) == "succession" else 0
	assert_int(absi(ca - cb)).is_less(12)


func test_day_chunks_cost_and_save_size() -> void:
	var hub := _mk()
	_run(hub, 1, 30)
	var g: RefCounted = hub.mod("governance")
	var times: Array = []
	for day in range(31, 61):
		for c: Callable in g.tick_day_chunks(day, CTX):
			var t0 := Time.get_ticks_usec()
			c.call()
			times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var median := float(times[times.size() / 2]) / 1000.0
	var p95 := float(times[int(times.size() * 0.95)]) / 1000.0
	print("governance chunk cost: median %.3f ms, p95 %.3f ms, worst %.3f ms" % [median, p95, float(times[times.size() - 1]) / 1000.0])
	assert_float(median).is_less(0.6)
	assert_float(p95).is_less(2.0)        # loose: CI runners are slow
	assert_int(JSON.stringify(g.serialize()).length()).is_less(150000)


func test_registered_in_hub_after_society_and_factions() -> void:
	for k in ["governance", "notables", "news"]:
		assert_bool(Hub.MODULES.has(k)).is_true()
		assert_int(Hub.ORDER.find(k)).is_greater(Hub.ORDER.find("society"))
		assert_int(Hub.ORDER.find(k)).is_greater(Hub.ORDER.find("factions"))
	assert_int(Hub.ORDER.find("governance")).is_less(Hub.ORDER.find("notables"))
	assert_int(Hub.ORDER.find("notables")).is_less(Hub.ORDER.find("news"))
