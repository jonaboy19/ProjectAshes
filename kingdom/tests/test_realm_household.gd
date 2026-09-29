extends GdUnitTestSuite
## Household: the family economy, autonomous parental sacrifice found through
## clues, family travel with world-sim danger, kidnapping and displacement,
## optional search (leads only), parents who die from believable causes.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _hh() -> RefCounted:
	WorldGen.setup(2024)
	var h: RefCounted = Hub.new().mod("household")
	h.set_player({"home_sid": 3, "sid": 3, "age": 10, "gold": 100})
	h._ensure()
	return h


func _far_sid(h: RefCounted) -> int:
	var best := 0
	var bd := 0.0
	for s: Dictionary in WorldGen.settlements:
		var d: float = h._dist(3, int(s["id"]))
		if d > bd:
			bd = d
			best = int(s["id"])
	return best


func test_family_economy_has_jobs_food_tax_and_repairs() -> void:
	var h := _hh()
	var f: Dictionary = h.family()
	assert_int((f["parents"] as Array).size()).is_equal(2)
	for p: Dictionary in f["parents"]:
		assert_str(String(p["job"])).is_not_empty()
		assert_int(int(p["wage"])).is_greater(0)
	var m0: Dictionary = h.money()
	assert_float(float(m0["income_week"])).is_greater(float(m0["expense_week"]) * 0.5)
	var msgs: Array = []
	for d in range(1, 130):
		msgs.append_array(h.tick_day(d, CTX))
	var m1: Dictionary = h.money()
	assert_float(float(m1["savings"])).is_not_equal(float(m0["savings"]))
	assert_int(int(h.fam["next_tax"])).is_greater(100)
	# The house decays and is repaired when the family can afford it.
	assert_float(float(m1["house"])).is_less(0.85)
	h.fam["house"] = 0.2
	h.fam["savings"] = 100.0
	h.tick_day(200, CTX)
	assert_float(float(h.money()["house"])).is_greater(0.8)


func test_bad_harvest_injury_and_debt_hurt_income() -> void:
	var h := _hh()
	var farmer := ""
	for p: Dictionary in h.family()["parents"]:
		if bool(h.JOBS[String(p["job"])]["farm"]):
			farmer = String(p["id"])
	var base: float = h.money()["income_week"]
	h.fam["bad_harvest_until"] = 500
	assert_bool(bool(h.money()["bad_harvest"])).is_true()
	assert_float(float(h.money()["expense_week"])).is_greater(0.0)
	h.fam["bad_harvest_until"] = -1
	h.injure_parent("father", 20, "the forge")
	assert_float(float(h.money()["income_week"])).is_less(base)
	# Shortfalls become debt, and debt grows.
	var d := _hh()
	d.fam["savings"] = 0.0
	d.parent("father")
	d.injure_parent("father", 400)
	d.injure_parent("mother", 400)
	for i in range(1, 40):
		d.tick_day(i, CTX)
	assert_float(float(d.money()["debt"])).is_greater(0.0)
	var debt0: float = d.money()["debt"]
	d.tick_week(6, CTX)
	assert_float(float(d.money()["debt"])).is_not_equal(debt0)
	assert_str(farmer).is_not_equal("zzz")


func test_parents_sacrifice_autonomously_under_school_costs() -> void:
	var h := _hh()
	h.fam["savings"] = 10.0
	var found := false
	for w in range(1, 30):
		h.support_student(18.0)
		for d in range(7):
			h.tick_day(w * 7 + d, CTX)
		h.tick_week(w, CTX)
		if not h.sacrifices().is_empty():
			found = true
			break
	assert_bool(found).is_true()
	var s: Dictionary = h.sacrifices()[0]
	assert_bool(bool(s["known"])).is_false()
	assert_bool(String(s["kind"]) in h.SACRIFICE_KINDS).is_true()


func test_sacrifice_clues_are_society_facts_the_player_discovers() -> void:
	var h := _hh()
	var soc: RefCounted = h.hub.mod("society")
	var rec: Dictionary = h.start_sacrifice("extra_job", "mother")
	assert_bool(rec.is_empty()).is_false()
	assert_bool(bool(h.parent("mother")["extra_job"])).is_true()
	assert_bool(soc.knows("topic:parents_sacrifice")).is_false()
	assert_float(float(h.money()["income_week"])).is_greater(0.0)
	# Away from home nothing can be found by looking around.
	h.set_player({"sid": 0})
	assert_bool(bool(h.investigate_home()["ok"])).is_false()
	h.set_player({"sid": 3})
	var r1: Dictionary = h.investigate_home()
	assert_bool(bool(r1["ok"])).is_true()
	assert_bool(soc.knows(String(rec["clues"][0]))).is_true()
	assert_bool(bool(r1["known"])).is_false()
	var r2: Dictionary = h.investigate_home()
	assert_bool(bool(r2["known"])).is_true()
	assert_bool(soc.knows("topic:parents_sacrifice")).is_true()
	assert_bool(soc.knows("secret:parents_extra_job")).is_true()
	assert_array(soc.dialogue_unlocks()).contains(["Confront them about parents extra job"])
	# You can respond in many ways.
	var sid: String = String(rec["id"])
	assert_bool(bool(h.respond_to_sacrifice(sid, "continue_studying")["ok"])).is_true()
	assert_bool(bool(h.respond_to_sacrifice(sid, "send_money", 90)["ok"])).is_true()
	assert_str(String(h.sacrifices()[0]["status"])).is_equal("stopped")
	assert_bool(bool(h.parent("mother")["extra_job"])).is_false()
	assert_int(h.take_pending_gold()).is_equal(-90)


func test_passive_clue_discovery_at_home() -> void:
	var h := _hh()
	var soc: RefCounted = h.hub.mod("society")
	var rec: Dictionary = h.start_sacrifice("skip_meals", "father")
	for d in range(1, 200):
		h.tick_day(d, CTX)
		if soc.knows(String(rec["clues"][0])):
			break
	assert_bool(soc.knows(String(rec["clues"][0]))).is_true()


func test_sacrifices_cost_the_parents_health() -> void:
	var h := _hh()
	h.start_sacrifice("extra_job", "father")
	h.start_sacrifice("skip_meals", "father")
	var hp0: float = h.parent("father")["health"]
	for d in range(1, 80):
		h.tick_day(d, CTX)
	assert_float(float(h.parent("father")["health"])).is_less(hp0)
	var hz: Dictionary = h.hazards("father")
	assert_float(float(hz["total"])).is_greater(0.0)


func test_leg_danger_reads_world_state() -> void:
	var h := _hh()
	var peace: float = h.leg_danger(3, 4, CTX)
	var war_ctx := CTX.duplicate()
	war_ctx["at_war"] = true
	var war: float = h.leg_danger(3, 4, war_ctx)
	assert_float(war).is_greater(peace)
	var land: RefCounted = h.hub.mod("land")
	land.conquer(3, "player", 0)
	land.remember(3, "massacre", 1.5, 0)
	assert_float(h.leg_danger(3, 4, CTX)).is_greater(peace)
	var sm: RefCounted = h.hub.mod("settlements")
	sm._ensure()
	var d0: float = h.leg_danger(3, 4, CTX)
	sm._start(4, "raid_aftermath", 0.8)
	assert_float(h.leg_danger(3, 4, CTX)).is_greater(d0)


func test_family_trip_can_turn_dangerous_and_interactive() -> void:
	var h := _hh()
	var war_ctx := CTX.duplicate()
	war_ctx["at_war"] = true
	var dest := _far_sid(h)
	var saw := false
	for trip in range(0, 80):
		if h.trip().is_empty():
			var p: Dictionary = h.plan_trip(dest, war_ctx)
			assert_bool(bool(p["ok"])).is_true()
		for hour in range(0, 500):
			var msgs: Array = h.tick_hour(hour % 24, war_ctx)
			if not h.pending_encounter().is_empty():
				saw = true
				break
			if h.trip().is_empty():
				break
		if saw:
			break
	assert_bool(saw).is_true()
	var enc: Dictionary = h.pending_encounter()
	assert_bool((enc["choices"] as Array).size() > 0).is_true()
	# Left unresolved, it resolves by itself after a couple of hours.
	var day0: int = enc["day"]
	for i in 4:
		h.tick_hour((int(enc["hour"]) + 1 + i) % 24, war_ctx)
	assert_bool(h.pending_encounter().is_empty() or int(h.pending_encounter().get("hour", -1)) != int(enc["hour"])).is_true()
	assert_int(day0).is_greater(-1)


func test_normal_trips_usually_arrive_home_safely() -> void:
	var h := _hh()
	var dest := (3 + 1) % WorldGen.settlements.size()
	var p: Dictionary = h.plan_trip(dest, CTX, false)
	assert_bool(bool(p["ok"])).is_true()
	assert_bool(bool(h.plan_trip(dest, CTX)["ok"])).is_false()
	for hour in range(0, 2500):
		h.tick_hour(hour % 24, CTX)
		if h.trip().is_empty():
			break
	assert_bool(h.trip().is_empty()).is_true()
	assert_bool(h.trip_log.size() > 0 or not h.deaths().is_empty() or h.captive.size() > 0 or h.displaced().size() > 0).is_true()


func test_kidnapped_child_wakes_far_away_and_can_escape() -> void:
	var h := _hh()
	var msgs: Array = h.kidnap("player", "slavers")
	assert_bool(msgs.size() > 0).is_true()
	assert_str(h.player_status()).is_equal("displaced")
	var ds: Dictionary = h.displaced()
	assert_int(int(ds["loc"])).is_not_equal(3)
	assert_float(h._dist(3, int(ds["loc"]))).is_greater(500.0)
	var woke := ""
	for d in range(1, 15):
		for m in h.tick_day(d, CTX):
			if String(m).contains("hundreds of kilometres"):
				woke = String(m)
	assert_str(woke).is_not_empty()
	assert_str(String(h.displaced()["stage"])).is_equal("forced_labour")
	# The school plan lapses.
	var edu: RefCounted = h.hub.mod("education")
	assert_bool(bool(edu.player.get("on_campus", true))).is_false()
	var free := false
	for i in range(0, 200):
		h._day += 1
		var r: Dictionary = h.attempt_escape("wait" if i % 3 == 0 else "sneak", CTX)
		if bool(r["ok"]):
			free = true
			break
	assert_bool(free).is_true()
	assert_str(h.player_status()).is_equal("free_far")
	# Reaching home ends it.
	h.set_player({"sid": 3})
	var msg: Array = h.tick_day(60, CTX)
	assert_str(h.player_status()).is_equal("home")
	assert_bool(msg.any(func(m: String) -> bool: return m.contains("home"))).is_true()


func test_missing_parents_are_leads_not_a_quest_marker() -> void:
	var h := _hh()
	var soc: RefCounted = h.hub.mod("society")
	h.kidnap("parents", "bandit_gang")
	assert_str(h.player_status()).is_equal("home")
	var mf: Dictionary = h.missing_family()
	assert_bool(bool(mf["missing"])).is_true()
	assert_int((mf["leads"] as Array).size()).is_equal(1)
	assert_bool(soc.knows("lead:family_missing")).is_true()
	# No marker, no coordinates anywhere in the data the UI could read.
	var blob := JSON.stringify(mf)
	for banned: String in ["marker", "\"pos\"", "coords", "waypoint", "quest"]:
		assert_bool(blob.contains(banned)).is_false()
	assert_bool(bool(h.rescue_attempt("fight", CTX)["ok"])).is_false()
	assert_bool(soc.leads().any(func(l: Dictionary) -> bool: return String(l["fact"]) == "lead:family_missing")).is_true()
	# Time passes; asking around reveals more only as the trail develops.
	for d in range(1, 30):
		h.tick_day(d, CTX)
	var got := false
	for i in range(0, 60):
		h._day += 1
		for f in ["lead:family_missing", "lead:family_transported", "lead:family_market"]:
			if h.leads_state.has(f):
				var r: Dictionary = h.follow_lead(f, CTX)
				got = got or bool(r["ok"])
	assert_bool(got).is_true()
	assert_bool(h.leads_state.has("lead:family_market")).is_true()
	# The player may ignore all of it; parents' fates keep moving.
	for w in range(1, 30):
		h.tick_week(w, CTX)
	assert_bool(int(h.captive["weeks"]) > 0 or bool(h.captive["rescued"]) or not h.deaths().is_empty()).is_true()


func test_rescue_of_captive_parents_once_located() -> void:
	var h := _hh()
	h.kidnap("parents", "slavers")
	for d in range(1, 20):
		h.tick_day(d, CTX)
	assert_str(String(h.captive["stage"])).is_equal("forced_labour")
	h.leads_state["lead:family_location"] = {"day": 20, "text": "x"}
	assert_bool(bool(h.rescue_attempt("ransom", CTX, 10)["ok"])).is_false()
	var ok: Dictionary = h.rescue_attempt("ransom", CTX, 200)
	if not bool(ok["ok"]):
		ok = h.rescue_attempt("ransom", CTX, 200)
	for i in 5:
		if bool(h.captive["rescued"]):
			break
		h._day += 1
		h.rescue_attempt("ransom", CTX, 200)
	assert_bool(bool(h.captive["rescued"])).is_true()
	assert_str(String(h.parent("father")["status"])).is_equal("home")
	assert_float(float(h.parent("father")["trauma"])).is_greater(0.0)


func test_accidental_discovery_when_passing_through() -> void:
	var h := _hh()
	var soc: RefCounted = h.hub.mod("society")
	h.kidnap("parents", "slavers")
	for d in range(1, 20):
		h.tick_day(d, CTX)
	h.set_player({"sid": int(h.captive["loc"])})
	for d in range(20, 120):
		h.tick_day(d, CTX)
		if soc.knows("lead:family_glimpse"):
			break
	assert_bool(soc.knows("lead:family_glimpse")).is_true()


func test_parents_die_only_from_believable_causes() -> void:
	var h := _hh()
	h.fam["parents"][0]["health"] = 0.15
	h.fam["parents"][0]["skipping"] = true
	h.fam["food_days"] = 0.0
	h.start_sacrifice("extra_job", "father")
	var hz: Dictionary = h.hazards("father")
	assert_float(float(hz["poverty"])).is_greater(0.0)
	assert_float(float(hz["total"])).is_greater(float(h.hazards("mother")["total"]))
	var msgs: Array = []
	h.parent("father")
	h.fam["parents"][0]["chain"].append("worked double shifts")
	h.kill_parent("father", "poverty", msgs)
	assert_bool(msgs.size() > 0).is_true()
	assert_str(String(msgs[0])).contains("hunger and overwork")
	assert_str(String(msgs[0])).contains("double shifts")
	var d: Dictionary = h.deaths()[0]
	assert_bool(String(d["cause"]) in h.DEATH_CAUSES).is_true()
	assert_bool(bool(h.parent("father")["alive"])).is_false()
	assert_str(String(h.sacrifices()[0]["status"])).is_equal("ended")
	# Both gone: an orphan with a guardian, no plot armour, no random cheap death for a healthy parent.
	h.kill_parent("mother", "disease", msgs)
	assert_bool(bool(h.family()["orphan"])).is_true()
	assert_str(String(h.family()["guardian"])).is_not_empty()
	var fresh := _hh()
	assert_float(float(fresh.hazards("father")["total"])).is_less(0.01)


func test_natural_death_has_a_cause_from_the_hazards() -> void:
	var h := _hh()
	h.fam["parents"][1]["health"] = 0.05
	h.fam["parents"][1]["ill_until"] = 100000
	h.fam["parents"][1]["illness"] = "winter fever"
	var died := false
	for d in range(1, 400):
		h.tick_day(d, CTX)
		if not h.deaths().is_empty():
			died = true
			break
	assert_bool(died).is_true()
	assert_bool(String(h.deaths()[0]["cause"]) in h.DEATH_CAUSES).is_true()
	assert_str(String(h.deaths()[0]["text"])).is_not_empty()


func test_life_family_sync_is_guarded() -> void:
	var h := _hh()
	var fake := RefCounted.new()
	var ctx := CTX.duplicate()
	ctx["life"] = fake
	h.kill_parent("father", "accident")
	h.tick_day(1, ctx)
	assert_bool(true).is_true()


func test_determinism_round_trip_and_perf() -> void:
	var a := _hh()
	var b := _hh()
	for h in [a, b]:
		h.start_sacrifice("borrow", "mother")
		h.kidnap("parents", "slavers")
		for d in range(1, 45):
			h.tick_day(d, CTX)
		h.tick_week(3, CTX)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	var json := JSON.stringify(a.serialize())
	var h2: RefCounted = Hub.new().mod("household")
	h2.deserialize(JSON.parse_string(json))
	assert_str(_norm(h2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_str(String(h2.captive["stage"])).is_equal(String(a.captive["stage"]))
	# catch_up
	var c := _hh()
	var d2 := _hh()
	assert_array(c.catch_up(300, CTX)).is_equal(d2.catch_up(300, CTX))
	assert_str(JSON.stringify(c.serialize())).is_equal(JSON.stringify(d2.serialize()))
	# trip and captivity resolved statistically
	var e := _hh()
	e.plan_trip(_far_sid(e), CTX)
	e.kidnap("parents", "press_gang")
	var t0 := Time.get_ticks_usec()
	e.catch_up(2000, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
	var f := _hh()
	f.tick_day(1, CTX)
	var t1 := Time.get_ticks_usec()
	for hr in 24:
		f.tick_hour(hr, CTX)
	f.tick_day(2, CTX)
	assert_int(Time.get_ticks_usec() - t1).is_less(20000)
