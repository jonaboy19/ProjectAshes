extends GdUnitTestSuite
## MW-15 / MW-16 / MW-17 / MW-26 / MW-33: messenger delay, interception and forgery; scout reports shaped by traits; envoy audiences with agendas and
## neutrality computed from hidden state; weather/line/intel factors and the battlefield snapshot; the throttled weekly digest; determinism and save/load.

const Hub := preload("res://scripts/realm/realm_hub.gd")

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	return h


func _arm(h: RefCounted) -> RefCounted:
	return h.mod("armies")


func _wi(h: RefCounted) -> RefCounted:
	return h.mod("war_intel")


func _mk(h: RefCounted, owner: String, kind: String, sid: int, men: int, pos := []) -> String:
	var r: Dictionary = _arm(h).found(owner, kind, "", sid, {"purse": 800, "food": 300.0})
	assert_bool(r["ok"]).is_true()
	var id: String = r["id"]
	_arm(h).add_unit(id, "spear", men, {"mo": 1.0, "di": 1.0, "lvl": 1})
	if not pos.is_empty():
		_arm(h).army(id)["pos"] = [float(pos[0]), float(pos[1])]
	return id


func _hours(h: RefCounted, n: int) -> void:
	for i in n:
		_arm(h).tick_hour(i % 24, {})


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _fids(h: RefCounted) -> Array:
	var out: Array = []
	for f: Dictionary in h.mod("factions").factions():
		out.append(String(f["id"]))
	return out


# --- 1. messenger delay, interception, forgery, magic ----------------------------------------

func test_distance_delays_the_order_and_the_army_acts_on_old_information() -> void:
	var h := _hub()
	var a := _arm(h)
	a.set_hq("player", [0.0, 0.0])
	var near := _mk(h, "player", "garrison", 0, 20, [300.0, 0.0])
	var far := _mk(h, "player", "garrison", 0, 20, [5000.0, 0.0])
	var rn: Dictionary = a.send_order(near, {"kind": "move", "x": 300.0, "y": 500.0})
	var rf: Dictionary = a.send_order(far, {"kind": "move", "x": 5000.0, "y": 500.0})
	assert_int(int(rf["eta_hours"])).is_greater(int(rn["eta_hours"]))
	_hours(h, int(rn["eta_hours"]))
	assert_str(String(a.army(near)["order"]["kind"])).is_equal("move")
	assert_str(String(a.army(far)["order"]["kind"])).is_equal("hold")
	assert_int(int(a.order_view(int(rf["seq"]))["stale_h"])).is_greater(0)


func test_weather_slows_the_rider() -> void:
	var h := _hub()
	var a := _arm(h)
	a.set_hq("player", [0.0, 0.0])
	var id := _mk(h, "player", "garrison", 0, 10, [4000.0, 0.0])
	var clear: Dictionary = a.send_order(id, {"kind": "hold"})
	a.weather = "storm"
	var storm: Dictionary = a.send_order(id, {"kind": "hold"})
	assert_int(int(storm["eta_hours"])).is_greater(int(clear["eta_hours"]))


func test_intercepted_riders_are_lost_or_forged_and_the_outcome_changes() -> void:
	var h := _hub()
	var a := _arm(h)
	a.set_hq("player", [0.0, 0.0])
	var id := _mk(h, "player", "garrison", 0, 30, [3000.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 20, [1500.0, 40.0])
	a.set_hostile("player", "raiders")
	var forged := -1
	var lost := -1
	for i in 40:
		var f: Dictionary = a.send_order(id, {"kind": "attack", "x": 3500.0, "y": 0.0}, {"forge": 1.0})
		if a.order_truth(int(f["seq"])) == "forged" and forged < 0:
			forged = int(f["seq"])
		var l: Dictionary = a.send_order(id, {"kind": "attack", "x": 3500.0, "y": 0.0}, {"forge": 0.0})
		if a.order_truth(int(l["seq"])) == "lost" and lost < 0:
			lost = int(l["seq"])
		if forged >= 0 and lost >= 0:
			break
		_hours(h, 12)
	assert_int(forged).is_greater(-1)
	assert_int(lost).is_greater(-1)
	_hours(h, 60)
	# the sender is told the order was "obeyed"/"sent" for a forged one, and nothing at all for a lost one
	assert_str(String(a.order_view(lost)["state"])).is_equal("no_reply")
	assert_str(String(a.order_view(forged)["state"])).is_not_equal("no_reply")
	assert_str(a.order_truth(forged)).is_equal("forged")
	assert_int(int(a.stats["lost_orders"])).is_greater(0)
	# a clean ride from a safe post differs from both
	var h2 := _hub()
	var a2 := _arm(h2)
	a2.set_hq("player", [0.0, 0.0])
	var id2 := _mk(h2, "player", "garrison", 0, 30, [3000.0, 0.0])
	var ok: Dictionary = a2.send_order(id2, {"kind": "attack", "x": 3500.0, "y": 0.0})
	assert_str(a2.order_truth(int(ok["seq"]))).is_equal("ok")


func test_magic_messaging_needs_a_mage_and_arrives_within_the_hour() -> void:
	var h := _hub()
	var a := _arm(h)
	a.set_hq("player", [0.0, 0.0])
	var plain := _mk(h, "player", "garrison", 0, 10, [6000.0, 0.0])
	var r0: Dictionary = a.send_order(plain, {"kind": "hold"}, {"magic": true})
	assert_bool(bool(r0["magic"])).is_false()
	assert_int(int(r0["eta_hours"])).is_greater(5)
	var mage := _mk(h, "player", "garrison", 0, 10, [6000.0, 0.0])
	a.add_unit(mage, "mage", 2, {"mo": 1.0, "di": 1.0})
	var r1: Dictionary = a.send_order(mage, {"kind": "move", "x": 6000.0, "y": 300.0}, {"magic": true})
	assert_bool(bool(r1["magic"])).is_true()
	assert_int(int(r1["eta_hours"])).is_equal(1)


# --- 2. scouts ----------------------------------------------------------------------------

func _stats_for(h: RefCounted, scout: String, target: String, n: int) -> Dictionary:
	var wi := _wi(h)
	var err := 0.0
	var wrong := 0
	var partial := 0
	var late := 0
	for i in n:
		var r: Dictionary = wi.scout_report("player", scout, target)
		late += int(r["late_h"])
	_hours(h, 400)
	for rp: Dictionary in wi.reports("player", target):
		err += absf(float(int(rp["n"]) - 100)) / 100.0
		if String(rp["banner"]) != "raiders":
			wrong += 1
		if bool(rp["partial"]):
			partial += 1
	var got := (wi.reports("player", target) as Array).size()
	return {"err": err / float(maxi(got, 1)), "wrong": wrong, "partial": partial, "late": late / n, "got": got}


func test_scout_accuracy_follows_skill_fear_and_integrity() -> void:
	var h := _hub()
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hq("player", [0.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 100, [300.0, 0.0])
	_arm(h).add_unit(foe, "spear", 0)
	wi.register_scout("ace", {"skill": 0.97, "fear": 0.0, "integ": 0.95, "loy": 0.95})
	wi.register_scout("coward", {"skill": 0.12, "fear": 0.85, "integ": 0.8, "loy": 0.7})
	var good := _stats_for(h, "ace", foe, 24)
	var bad := _stats_for(h, "coward", foe, 24)
	assert_float(float(bad["err"])).is_greater(float(good["err"]))
	assert_int(int(bad["wrong"])).is_greater(int(good["wrong"]))
	assert_int(int(bad["partial"])).is_greater(int(good["partial"]))
	assert_int(int(bad["late"])).is_greater(int(good["late"]))
	assert_str(wi.reliability_tag("ace")).is_equal("reliable")
	assert_str(wi.reliability_tag("coward")).is_equal("doubtful")


func test_a_bribed_scout_lies_but_may_still_look_reliable() -> void:
	var h := _hub()
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hq("player", [0.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 100, [300.0, 0.0])
	wi.register_scout("snake", {"skill": 0.9, "fear": 0.0, "integ": 0.05, "loy": 0.1})
	wi.register_scout("honest", {"skill": 0.9, "fear": 0.0, "integ": 0.95, "loy": 0.95})
	wi.bribe_scout("snake", 1.0)
	wi.bribe_scout("honest", 1.0)
	for i in 20:
		wi.scout_report("player", "snake", foe)
		wi.scout_report("player", "honest", foe)
	var lies := {"snake": 0, "honest": 0}
	for r: Dictionary in wi.serialize()["rep"]:
		if "bribed" in r["flags"]:
			lies[String(r["scout"])] = int(lies[String(r["scout"])]) + 1
	assert_int(int(lies["snake"])).is_greater(10)
	assert_int(int(lies["honest"])).is_less(int(lies["snake"]))
	assert_str(wi.reliability_tag("snake")).is_equal("reliable")      # nothing visible gives the bribe away
	_hours(h, 300)
	var shown: Array = wi.reports("player", foe)
	for rp: Dictionary in shown:
		assert_bool(rp.has("flags")).is_false()                      # hidden flags are never shown


func test_two_scouts_can_disagree_and_reports_arrive_late_or_never() -> void:
	var h := _hub()
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hq("player", [0.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 100, [3000.0, 0.0])
	wi.register_scout("ace", {"skill": 0.97, "fear": 0.0, "integ": 0.95, "loy": 0.95})
	wi.register_scout("liar", {"skill": 0.3, "fear": 0.7, "integ": 0.1, "loy": 0.1})
	wi.bribe_scout("liar", 1.0)
	for i in 12:
		wi.scout_report("player", "ace", foe)
		wi.scout_report("player", "liar", foe)
	assert_int((wi.reports("player", foe) as Array).size()).is_equal(0)   # nothing has had time to arrive
	_hours(h, 200)
	assert_int((wi.conflicts("player", foe) as Array).size()).is_greater(0)
	# a report is old when read, and the army has since moved
	var first: Dictionary = (wi.reports("player", foe) as Array)[0]
	assert_int(int(first["age_h"])).is_greater(0)
	a.army(foe)["pos"] = [3000.0, 2000.0]
	assert_float(wi.drift(int(first["id"]))).is_greater(1500.0)
	# the road is dangerous: with a hostile patrol on it some reports never arrive
	var h2 := _hub()
	var a2 := _arm(h2)
	a2.set_hq("player", [0.0, 0.0])
	var foe2 := _mk(h2, "raiders", "rebels", 2, 100, [3000.0, 0.0])
	var watch := _mk(h2, "raiders", "rebels", 2, 40, [1500.0, 0.0])
	a2.set_hostile("player", "raiders")
	for i in 30:
		_wi(h2).scout_report("player", "ace", foe2)
	_hours(h2, 400)
	assert_int(int(_wi(h2).stats["lost"])).is_greater(0)
	assert_int((_wi(h2).reports("player", foe2) as Array).size()).is_less(30)
	assert_int(watch.length()).is_greater(0)


# --- 3. envoys ----------------------------------------------------------------------------

func test_agenda_changes_the_outcome_of_the_same_answer() -> void:
	var h := _hub()
	var wi := _wi(h)
	var ids := _fids(h)
	var from: String = ids[0]
	var to: String = ids[1]
	var other: String = ids[2]
	var grievance := {}
	for ag: String in ["arrogant", "desperate", "sincere"]:
		var e: Dictionary = wi.envoy_arrive(from, to, "aid", other, {"agenda": ag})
		var g0 := float(h.mod("factions").relation(to, from)["grievance"])
		var r: Dictionary = wi.respond(int(e["id"]), "refuse")
		assert_bool(bool(r["ok"])).is_true()
		grievance[ag] = float(h.mod("factions").relation(to, from)["grievance"]) - g0
	assert_float(float(grievance["arrogant"])).is_greater(float(grievance["desperate"]))
	assert_float(float(grievance["arrogant"])).is_greater(float(grievance["sincere"]))
	var outs := {}
	for ag2: String in ["sincere", "desperate", "arrogant", "deceptive", "rogue"]:
		var e2: Dictionary = wi.envoy_arrive(from, to, "tribute", other, {"agenda": ag2})
		outs[ag2] = String(wi.respond(int(e2["id"]), "demand_compensation")["outcome"])
	assert_str(outs["sincere"]).is_equal("paid")
	assert_str(outs["desperate"]).is_equal("cannot_pay")
	assert_str(outs["arrogant"]).is_equal("insulted")
	assert_str(outs["deceptive"]).is_equal("false_promise")
	assert_int(wi.take_pending_gold()).is_greater(0)
	assert_int(wi.take_pending_gold()).is_equal(0)


func test_every_response_is_available_and_ask_intel_reveals_the_agenda() -> void:
	var h := _hub()
	var wi := _wi(h)
	var ids := _fids(h)
	for resp: String in wi.RESPONSES:
		var e: Dictionary = wi.envoy_arrive(ids[0], ids[1], "neutrality", ids[2], {"agenda": "deceptive"})
		var r: Dictionary = wi.respond(int(e["id"]), resp, {"insight": 1.0})
		assert_bool(bool(r["ok"])).is_true()
		assert_str(String(r["text"])).is_not_empty()
	var shown: Array = wi.envoys("waiting")
	for s: Dictionary in shown:
		if not bool(s["informed"]):
			assert_str(String(s["agenda"])).is_equal("unknown")
	var found := false
	for i in 12:
		var e2: Dictionary = wi.envoy_arrive(ids[0], ids[1], "neutrality", ids[2], {"agenda": "sincere"})
		var r2: Dictionary = wi.respond(int(e2["id"]), "ask_intel", {"insight": 1.0})
		if String(r2["outcome"]) == "learned":
			found = true
			assert_str(String(r2["agenda"])).is_equal("sincere")
			break
	assert_bool(found).is_true()


func test_envoys_who_wait_too_long_leave_offended() -> void:
	var h := _hub()
	var wi := _wi(h)
	var ids := _fids(h)
	var e: Dictionary = wi.envoy_arrive(ids[0], ids[1], "passage", "", {"agenda": "sincere"})
	for d in range(1, 14):
		wi.tick_day(d, {})
	assert_str(String(wi.envoy(int(e["id"]))["state"])).is_equal("closed")
	assert_str(String(wi.envoy(int(e["id"]))["outcome"])).is_equal("left_offended")


# --- 4. neutrality from hidden state ------------------------------------------------------------

func _set_rel(h: RefCounted, a: String, b: String, field: String, v: float) -> void:
	var f: RefCounted = h.mod("factions")
	f.change_relation(a, b, field, v - float(f.relation(a, b)[field]))


func test_neutrality_outcome_depends_on_trade_fear_and_secret_aid() -> void:
	var h := _hub()
	var wi := _wi(h)
	var ids := _fids(h)
	var from: String = ids[0]
	var to: String = ids[1]
	var other: String = ids[2]
	for pair in [[to, other], [to, from]]:
		_set_rel(h, pair[0], pair[1], "trade", 0.0)
		_set_rel(h, pair[0], pair[1], "fear", 0.0)
		_set_rel(h, pair[0], pair[1], "grievance", 0.0)
	var labels := {}
	var e0: Dictionary = wi.envoy_arrive(from, to, "neutrality", other, {"agenda": "sincere"})
	labels["calm"] = wi.neutrality_label(int(e0["id"]))
	var r0: Dictionary = wi.respond(int(e0["id"]), "accept")
	_set_rel(h, to, from, "fear", 80.0)
	var e1: Dictionary = wi.envoy_arrive(from, to, "neutrality", other, {"agenda": "sincere"})
	labels["feared"] = wi.neutrality_label(int(e1["id"]))
	_set_rel(h, to, from, "fear", 0.0)
	_set_rel(h, to, other, "trade", 90.0)
	var e2: Dictionary = wi.envoy_arrive(from, to, "neutrality", other, {"agenda": "sincere"})
	labels["trade_ties"] = wi.neutrality_label(int(e2["id"]))
	assert_str(labels["calm"]).is_equal("respected")
	assert_str(labels["feared"]).is_equal("pressured")
	assert_str(labels["trade_ties"]).is_equal("strained")
	# the same "accept" gives different results and different relation changes
	var r2: Dictionary = wi.respond(int(e2["id"]), "accept")
	assert_str(String(r0["outcome"])).is_equal("neutral_respected")
	assert_str(String(r2["outcome"])).is_equal("neutral_strained")
	# secret aid to the other side: violated if found out
	var seen := {"discovered": 0, "unseen": 0}
	for i in 30:
		var e3: Dictionary = wi.envoy_arrive(from, to, "neutrality", other, {"agenda": "deceptive"})
		var r3: Dictionary = wi.respond(int(e3["id"]), "secretly_aid")
		seen[String(r3["outcome"])] = int(seen[String(r3["outcome"])]) + 1
		if String(r3["outcome"]) == "discovered":
			assert_str(String(r3["neutrality"])).is_equal("violated")
	assert_int(int(seen["discovered"])).is_greater(0)
	assert_int(int(seen["unseen"])).is_greater(0)


func test_council_delegation_follows_the_state_with_a_delay() -> void:
	var h := _hub()
	var wi := _wi(h)
	var ids := _fids(h)
	_set_rel(h, ids[1], ids[2], "trade", 95.0)
	var e: Dictionary = wi.envoy_arrive(ids[0], ids[1], "neutrality", ids[2], {"agenda": "sincere"})
	var r: Dictionary = wi.respond(int(e["id"]), "delegate_council", {"council": 1.0})
	assert_str(String(r["via"])).is_equal("refuse")
	assert_int(int(r["delay_days"])).is_equal(3)


# --- 5. war factors and battlefield snapshot ---------------------------------------------

func _fort(h: RefCounted, sid := 0) -> String:
	var a := _arm(h)
	var g: String = a.found("player", "garrison", "", sid, {"purse": 2000, "food": 200.0})["id"]
	a.add_unit(g, "spear", 40, {"lvl": 2, "eq": 0.7, "mo": 0.8, "di": 0.8})
	a.appoint(g, {"name": "Warden", "comp": 0.7, "pers": "loyal", "loy": 0.9})
	a.set_defence(sid, {"garrison": g, "patrols": 4, "shifts": 3, "per_shift": 2, "walls": 2})
	a.stock_up(sid, "food", 400.0)
	return g


func test_weather_supply_line_and_intel_change_the_attackers_power() -> void:
	var h := _hub()
	var a := _arm(h)
	_fort(h)
	var att := _mk(h, "raiders", "rebels", 3, 60, [4000.0, 0.0])
	a.set_hq("raiders", [0.0, 0.0])
	a.army(att)["food"] = 5.0
	var base: Dictionary = a.war_factors({"aid": att, "owner": "raiders"}, 0)
	a.weather = "storm"
	var storm: Dictionary = a.war_factors({"aid": att, "owner": "raiders"}, 0)
	assert_float(float(storm["mult"])).is_less(float(base["mult"]))
	assert_float(float(base["line"])).is_less(1.0)       # far from home with empty wagons
	a.weather = "clear"
	var scouted: Dictionary = a.war_factors({"aid": att, "owner": "raiders", "scouts": true}, 0)
	assert_float(float(scouted["mult"])).is_greater(float(base["mult"]))
	for u: Dictionary in a.army(att)["units"]:
		u["mo"] = 0.1
	assert_float(float(a.war_factors({"aid": att, "owner": "raiders"}, 0)["rout"])).is_less(1.0)


func test_battlefield_snapshot_is_consistent_through_the_fight() -> void:
	var h := _hub()
	var a := _arm(h)
	_fort(h)
	_hours(h, 10)
	var att := _mk(h, "raiders", "rebels", 3, 90)
	var before: int = a.men(att)
	var res: Dictionary = a.resolve_attack({"owner": "raiders", "aid": att, "power": a.power(att)}, 0, "assault", {"player_present": true})
	var start: int = a.hours()
	var snap0: Dictionary = a.battlefield_snapshot(0, start)
	assert_str(String(snap0["phase"])).is_equal("opening")
	var dur := 0
	for hr in range(start, start + 40):
		if String(a.battlefield_snapshot(0, hr)["phase"]) == "ended":
			dur = hr - start
			break
	assert_int(dur).is_greater(2)
	var last_a := 0
	var last_d := 0
	var last_w := 0
	var phases: Array = []
	for hr2 in range(start, start + dur + 1):
		var s: Dictionary = a.battlefield_snapshot(0, hr2)
		var at: Dictionary = s["attacker"]
		var df: Dictionary = s["defender"]
		assert_int(int(at["lost"]) + int(at["alive"])).is_equal(int(at["start"]))
		assert_int(int(at["engaged"]) + int(at["waiting"])).is_equal(int(at["alive"]))
		assert_int(int(df["lost"]) + int(df["alive"])).is_equal(int(df["start"]))
		assert_int(int(at["lost"])).is_greater_equal(last_a)
		assert_int(int(df["lost"])).is_greater_equal(last_d)
		assert_int(int(s["destroyed"]["walls"])).is_greater_equal(last_w)
		assert_int(int(s["destroyed"]["walls"])).is_less_equal(int(s["destroyed"]["walls_total"]))
		assert_int(int(s["destroyed"]["gates"])).is_less_equal(int(s["destroyed"]["gates_total"]))
		last_a = int(at["lost"])
		last_d = int(df["lost"])
		last_w = int(s["destroyed"]["walls"])
		if phases.is_empty() or phases[-1] != String(s["phase"]):
			phases.append(String(s["phase"]))
	var fin: Dictionary = a.battlefield_snapshot(0, start + dur + 5)
	assert_int(int(fin["attacker"]["alive"])).is_equal(a.men(att))
	assert_int(int(fin["attacker"]["start"])).is_equal(before)
	assert_str(String(fin["outcome"])).is_equal("attacker_won" if bool(res["won"]) else "repelled")
	assert_str(String(a.battlefield_snapshot(0, start + 1)["outcome"])).is_equal("undecided")
	assert_str(phases[0]).is_equal("opening")
	assert_str(phases[-1]).is_equal("ended")
	assert_dict(a.battlefield_snapshot(99, start)).is_empty()
	assert_str(String(a.battlefield_snapshot(0, start - 3)["phase"])).is_equal("not_started")


# --- 6. digest ----------------------------------------------------------------------------

func test_digest_is_once_a_week_capped_and_differs_by_role() -> void:
	var h := _hub()
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hq("player", [0.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 100, [300.0, 0.0])
	wi.register_scout("ace", {"skill": 0.97, "fear": 0.0, "integ": 0.95, "loy": 0.95})
	for i in 10:
		wi.scout_report("player", "ace", foe)
	_hours(h, 100)
	h.mod("news").post("boom", 0, "Silver was struck at the old mine.", 3.0, "", true, 0)
	wi.set_viewer("player", 0, "ruler", "player", [0])
	var d1: Dictionary = wi.digest(1)
	assert_bool(d1.is_empty()).is_false()
	assert_int((d1["items"] as Array).size()).is_less_equal(wi.DIGEST_RULER)
	assert_bool(wi.digest(1).is_empty()).is_true()                    # same week: nothing more
	assert_bool(wi.digest(0).is_empty()).is_true()
	var joined := ""
	for it: Dictionary in d1["items"]:
		joined += String(it["text"]) + "|"
	assert_bool(joined.contains("men under")).is_true()
	assert_bool(joined.contains("reliable")).is_true()
	assert_bool(joined.contains("steward")).is_false()               # no steward, no report
	# an adventurer gets fewer lines and no numbers
	wi.set_viewer("player", 0, "adventurer", "player", [])
	var d2: Dictionary = wi.digest(2)
	assert_bool(d2.is_empty()).is_false()
	assert_int((d2["items"] as Array).size()).is_less_equal(wi.DIGEST_ADV)
	for it2: Dictionary in d2["items"]:
		assert_bool(String(it2["text"]).contains("reliable")).is_false()
	# a flood of weeks gives one digest per week at most, and the inbox is bounded
	for w in range(3, 60):
		wi.digest(w)
	assert_int((wi.inbox() as Array).size()).is_less_equal(wi.INBOX_CAP)
	assert_int(int(wi.stats["digests"])).is_less_equal(60)


func test_steward_report_only_with_a_steward() -> void:
	var h := _hub()
	var wi := _wi(h)
	wi.set_viewer("acct_test", 0, "ruler", "player", [0])
	wi.digest(1)
	for d: Dictionary in wi.inbox():
		for it: Dictionary in d["items"]:
			assert_str(String(it["kind"])).is_not_equal("steward")
	h.mod("ledger").delegate("acct_test", "ch:1", 100, 50)
	var d2: Dictionary = wi.digest(2)
	assert_bool(d2.is_empty()).is_false()
	assert_str(String((d2["items"] as Array)[0]["kind"])).is_equal("steward")


func test_urgent_word_only_for_a_known_direct_threat_and_once_a_day() -> void:
	var h := _hub()
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hostile("player", "raiders")
	var mine := _mk(h, "player", "garrison", 0, 20)
	var home: Array = a._pos_of_sid(0)
	var foe := _mk(h, "raiders", "rebels", 2, 60, [float(home[0]) + 100.0, float(home[1])])
	wi.set_viewer("player", 0, "ruler", "player", [0])
	a.army(foe)["pos"] = [float(home[0]) + 100.0, float(home[1]) + 5000.0]
	assert_bool(wi.urgent_check(5).is_empty()).is_true()               # nothing seen: no word, even though an army exists
	a.army(foe)["pos"] = [float(home[0]) + 100.0, float(home[1])]
	a.scout_pass()
	var u: Dictionary = wi.urgent_check(6)
	assert_bool(u.is_empty()).is_false()
	assert_bool(bool(u["urgent"])).is_true()
	assert_bool(wi.urgent_check(6).is_empty()).is_true()               # one a day
	assert_bool(wi.urgent_check(7).is_empty()).is_true()               # same army, inside the gap
	assert_bool(wi.urgent_check(6 + wi.URGENT_GAP_DAYS).is_empty()).is_false()
	assert_str(mine).is_not_empty()


# --- 7. determinism, save/load, catch-up ------------------------------------------------------

func _scenario(h: RefCounted) -> void:
	var a := _arm(h)
	var wi := _wi(h)
	a.set_hq("player", [0.0, 0.0])
	var foe := _mk(h, "raiders", "rebels", 2, 100, [2000.0, 0.0])
	wi.register_scout("s1", {"skill": 0.5, "fear": 0.3, "integ": 0.4, "loy": 0.5})
	for i in 6:
		wi.scout_report("player", "s1", foe)
	var ids := _fids(h)
	var e: Dictionary = wi.envoy_arrive(ids[0], ids[1], "neutrality", ids[2])
	wi.respond(int(e["id"]), "negotiate", {"gift": 50})
	wi.set_viewer("player", 0, "ruler", "player", [0])
	_hours(h, 120)
	wi.digest(1)


func test_determinism_and_save_round_trip() -> void:
	var h1 := _hub()
	var h2 := _hub()
	_scenario(h1)
	_scenario(h2)
	assert_str(_norm(_wi(h1).serialize())).is_equal(_norm(_wi(h2).serialize()))
	assert_str(_norm(_arm(h1).serialize())).is_equal(_norm(_arm(h2).serialize()))
	var snap := _norm(_wi(h1).serialize())
	var h3 := _hub()
	_wi(h3).deserialize(JSON.parse_string(JSON.stringify(_wi(h1).serialize())))
	assert_str(_norm(_wi(h3).serialize())).is_equal(snap)
	# battles and weather survive an armies save
	var h4 := _hub()
	_fort(h4)
	var att := _mk(h4, "raiders", "rebels", 3, 60)
	_arm(h4).weather = "rain"
	_arm(h4).resolve_attack({"owner": "raiders", "aid": att, "power": _arm(h4).power(att)}, 0, "assault", {})
	var d4: Dictionary = JSON.parse_string(JSON.stringify(_arm(h4).serialize()))
	var h5 := _hub()
	_arm(h5).deserialize(d4)
	assert_str(_norm(_arm(h5).serialize())).is_equal(_norm(_arm(h4).serialize()))
	assert_str(_norm(_arm(h5).battlefield_snapshot(0, _arm(h4).hours() + 2))).is_equal(_norm(_arm(h4).battlefield_snapshot(0, _arm(h4).hours() + 2)))
	assert_str(_arm(h5).weather).is_equal("rain")


func test_catch_up_and_ticks_are_cheap_and_never_flood() -> void:
	var h := _hub()
	var wi := _wi(h)
	wi.set_viewer("player", 0, "ruler", "player", [0])
	var t0 := Time.get_ticks_usec()
	for w in 52:
		wi.tick_week(w + 1, {})
		wi.tick_day(w * 7, {})
	wi.catch_up(400, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(200000)
	assert_int((wi.inbox() as Array).size()).is_less_equal(wi.INBOX_CAP)
