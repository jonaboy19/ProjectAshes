extends GdUnitTestSuite
## City life: inns, leases and eviction, job interviews and employment, boards
## without markers, hidden careers found by clues, guild politics, districts at
## night, schedule opportunities, save round trips and the tick budget.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CityLife := preload("res://scripts/realm/city_life.gd")

const CTX := {"player_pos": Vector2(0, 0), "season": "spring", "at_war": false, "abs_hours": 100.0, "gold": 500}


func _new() -> RefCounted:
	WorldGen.setup(2024)
	var hub := Hub.new()
	return hub.mod("city_life")


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func _sid_of(kind: String) -> int:
	for s: Dictionary in WorldGen.settlements:
		if s["kind"] == kind:
			return int(s["id"])
	return -1


func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _canon(v[k])
		return o
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_canon(x))
		return a
	if v is int or v is float:
		return snappedf(float(v), 0.0001)
	return v


func _inject_job(cl: RefCounted, sid: int, tpl: String) -> String:
	cl.jobs(sid)
	var t: Dictionary = CityLife.JOB_TPL[tpl]
	var arr: Array = cl._cities[str(sid)]["jobs"]
	var id := "job:%d:%d" % [sid, 900 + arr.size()]
	arr.append({"id": id, "sid": sid, "district": t["district"], "tpl": tpl, "title": t["title"], "employer": "Master Test",
		"role": "smith", "wage": t["wage"], "via": "board", "posted": 0, "expires": 999})
	return id


func test_settlement_life_is_deterministic() -> void:
	var a := _new()
	var sid := _sid_of("town") if _sid_of("town") >= 0 else 0
	var ja: Array = a.jobs(sid)
	var ia: Array = a.inns(sid)
	var ba: Array = a.board(sid, "gate")
	var b := _new()
	assert_str(JSON.stringify(_canon(b.jobs(sid)))).is_equal(JSON.stringify(_canon(ja)))
	assert_str(JSON.stringify(_canon(b.inns(sid)))).is_equal(JSON.stringify(_canon(ia)))
	assert_str(JSON.stringify(_canon(b.board(sid, "gate")))).is_equal(JSON.stringify(_canon(ba)))
	assert_int(ia.size()).is_greater(0)


func test_inns_differ_by_tier_and_refuse_the_poor() -> void:
	var cl := _new()
	var sid := _sid_of("castle")
	assert_int(sid).is_greater_equal(0)
	var tiers := {}
	for inn: Dictionary in cl.inns(sid):
		tiers[inn["tier"]] = inn
	assert_bool(tiers.has("cheap") and tiers.has("merchant") and tiers.has("noble")).is_true()
	assert_bool(int(tiers["noble"]["price"]) > int(tiers["cheap"]["price"])).is_true()
	assert_str(String(tiers["noble"]["refusal"])).is_not_empty()
	var r: Dictionary = cl.rent_room(sid, 2, tiers["noble"]["id"])
	assert_bool(r["ok"]).is_false()


func test_rent_room_charges_and_improves_rest_and_expires() -> void:
	var cl := _new()
	cl.set_player({"gold": 100})
	var sid := _sid_of("town") if _sid_of("town") >= 0 else 0
	var before: float = cl.rest_quality()
	var r: Dictionary = cl.rent_room(sid, 3)
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["cost"])).is_greater(0)
	assert_float(cl.rest_quality()).is_greater(before)
	assert_int(cl.take_pending_gold()).is_equal(-int(r["cost"]))
	var ctx := CTX.duplicate()
	ctx["abs_hours"] = 100.0 + 24.0 * 4.0
	cl.tick_hour(9, ctx)
	assert_bool(cl.stay().is_empty()).is_true()
	var poor := _new()
	assert_bool(poor.rent_room(sid, 30)["ok"]).is_false()


func test_inn_rumours_come_from_society() -> void:
	var hub := _hub()
	var soc: RefCounted = hub.mod("society")
	var cl: RefCounted = hub.mod("city_life")
	soc.add_rumour("rescue", 0, 3.0)
	var lines: Array = cl.inn_rumours(0)
	assert_int(lines.size()).is_greater(0)
	var found := false
	for l: String in lines:
		if "pulled" in l:
			found = true
	assert_bool(found).is_true()


func test_lease_rent_due_and_eviction() -> void:
	var cl := _new()
	cl.set_player({"gold": 400, "class": 1})
	var sid := _sid_of("town") if _sid_of("town") >= 0 else 0
	var pick := ""
	for h: Dictionary in cl.homes(sid):
		if h["refusal"] == "" and h["kind"] == "room":
			pick = h["id"]
	assert_str(pick).is_not_empty()
	var res: Dictionary = cl.lease(pick, 1)
	assert_bool(res["ok"]).is_true()
	# Broke: no auto-pay possible, arrears grow, then eviction.
	cl.set_player({"gold": 0})
	cl.take_pending_gold()
	cl.pending_gold = 0
	var evicted := false
	var ctx := CTX.duplicate()
	ctx["gold"] = 0
	for d in range(1, 30):
		var msgs: Array = cl.tick_day(d, ctx)
		for m: String in msgs:
			if "changed the locks" in m:
				evicted = true
	assert_bool(evicted).is_true()
	assert_str(String(cl.leases()[0]["status"])).is_equal("evicted")
	assert_bool(cl.lease(pick, 1)["ok"]).is_false()


func test_interview_rejects_unqualified_guard_with_reason() -> void:
	var cl := _new()
	cl.set_player({"combat": 0, "age": 25})
	var id := _inject_job(cl, 0, "city_guard")
	var r: Dictionary = cl.apply(id, [0, 0, 0])
	assert_bool(r["hired"]).is_false()
	assert_str(String(r["reason"])).is_not_empty()
	assert_bool((r["missing"] as Array).has("combat")).is_true()


func test_interview_offers_apprenticeship_when_untrained() -> void:
	var cl := _new()
	cl.set_player({"craft": 0, "age": 25})
	var id := _inject_job(cl, 0, "smith")
	var r: Dictionary = cl.apply(id, [1, 1, 1])
	assert_bool(r["hired"]).is_false()
	assert_str(String(r["alternative"])).is_equal("smith_apprentice")


func test_interview_criminal_record_blocks_guard_job() -> void:
	var cl := _new()
	cl.set_player({"combat": 60, "age": 25, "record": true})
	var id := _inject_job(cl, 0, "city_guard")
	var r: Dictionary = cl.apply(id, [0, 2, 1])
	assert_bool(r["hired"]).is_false()
	assert_bool("record" in String(r["reason"])).is_true()


func test_good_answers_hire_and_lies_are_caught() -> void:
	var good := _new()
	good.set_player({"craft": 40, "charm": 40, "age": 25})
	var id := _inject_job(good, 0, "smith")
	var r: Dictionary = good.apply(id, [0, 2, 1])
	assert_bool(r["hired"]).is_true()
	assert_bool(good.is_employed()).is_true()
	var liar := _new()
	liar.set_player({"craft": 18, "charm": 5, "age": 25})   # passes the floor, not the boast
	var id2 := _inject_job(liar, 0, "smith")
	var r2: Dictionary = liar.apply(id2, [0, 0, 2])
	assert_float(float(r2["score"])).is_less(float(r["score"]))
	assert_bool(r2["hired"]).is_false()


func test_employment_pay_promotion_and_firing_for_absence() -> void:
	var cl := _new()
	cl.set_player({"craft": 40, "charm": 40, "age": 25})
	var id := _inject_job(cl, 0, "smith")
	assert_bool(cl.apply(id, [0, 2, 1])["hired"]).is_true()
	var ctx := CTX.duplicate()
	cl.tick_hour(9, ctx)
	assert_bool(cl.work_shift(1.0)["ok"]).is_true()
	cl.tick_day(1, ctx)
	assert_int(cl.take_pending_gold()).is_greater(0)
	# Never turn up again: fired after enough absences, blacklisted by that employer.
	var fired := false
	for d in range(2, 20):
		for m: String in cl.tick_day(d, ctx):
			if "dismissed" in m:
				fired = true
	assert_bool(fired).is_true()
	assert_bool(cl.is_employed()).is_false()
	assert_float(cl.employment_reputation()).is_less(50.0)
	var again := _inject_job(cl, 0, "smith")
	cl._cities["0"]["jobs"][-1]["employer"] = "Master Test"
	assert_str(String(cl.apply(again, [0, 2, 1])["reason"])).contains("remembers")


func test_diligent_worker_is_promoted() -> void:
	var cl := _new()
	cl.set_player({"craft": 40, "charm": 40, "age": 25})
	var id := _inject_job(cl, 0, "smith")
	cl.apply(id, [0, 2, 1])
	var ctx := CTX.duplicate()
	var start_rank: int = cl.job()["rank"]
	for d in range(1, 60):
		cl.tick_hour(9, ctx)
		cl.tick_day(d, ctx)
		cl.tick_hour(9, ctx)
		cl.work_shift(1.2)
		cl.accomplish("order_filled", 1.0)
		if d % 7 == 0:
			cl._job["worked_today"] = true
	assert_bool(cl.is_employed()).is_true()
	assert_int(int(cl.job()["rank"])).is_greater(start_rank)


func test_boards_have_named_posters_and_no_markers() -> void:
	var cl := _new()
	var sid := _sid_of("castle")
	var total := 0
	for d: String in cl.board_districts(sid):
		for p: Dictionary in cl.board(sid, d):
			total += 1
			assert_bool(p.has("pos") or p.has("marker") or p.has("position")).is_false()
			assert_str(String(p["poster"]["name"])).is_not_empty()
			assert_str(String(p["text"])).is_not_empty()
	assert_int(total).is_greater(5)
	assert_bool(cl.board_districts(sid).has("gate")).is_true()


func test_taking_a_posting_teaches_a_place() -> void:
	var hub := _hub()
	var cl: RefCounted = hub.mod("city_life")
	var soc: RefCounted = hub.mod("society")
	var p: Dictionary = (cl.board(0, "gate") as Array)[0]
	assert_bool(soc.knows(p["teaches"])).is_false()
	var r: Dictionary = cl.take_posting(p["id"])
	assert_bool(r["ok"]).is_true()
	assert_bool(soc.knows(p["teaches"])).is_true()
	assert_bool(cl.take_posting(p["id"])["ok"]).is_false()


func test_hidden_careers_are_never_offered() -> void:
	var cl := _new()
	var sid := _sid_of("castle")
	var words := ["assassin", "thief", "smuggler", "informant"]
	for j: Dictionary in cl.jobs(sid):
		for w in words:
			assert_bool(w in String(j["title"]).to_lower() or String(j["tpl"]) == w).is_false()
	for d: String in cl.board_districts(sid):
		for p: Dictionary in cl.board(sid, d):
			for w in words:
				assert_bool(w in String(p["text"]).to_lower()).is_false()
	assert_int(cl.hidden_leads().size()).is_equal(0)


func test_hidden_career_discovered_through_clues_then_trial() -> void:
	var cl := _new()
	cl.set_player({"stealth": 60, "charm": 40})
	assert_bool(cl.hidden_trial("smuggler")["ok"]).is_false()
	cl.note_activity("explore_sewer", 0, 1.0)
	assert_int(cl.hidden_leads().size()).is_equal(1)   # one hint after a first clue
	var lead: Dictionary = cl.hidden_leads()[0]
	assert_bool(lead.has("pos")).is_false()
	assert_str(String(lead["text"])).is_not_empty()
	cl.note_activity("explore_sewer", 0, 2.0)
	cl.note_activity("crime_smuggling", 0, 1.0)
	cl.note_activity("night_docks", 0, 2.0)
	var stage := 0
	for l: Dictionary in cl.hidden_leads():
		if l["id"] == "smuggler":
			stage = int(l["stage"])
	assert_int(stage).is_equal(3)
	var passed := false
	for day in range(0, 60, 8):
		cl._last_day = day
		var t: Dictionary = cl.hidden_trial("smuggler")
		if t.get("passed", false):
			passed = true
			break
	assert_bool(passed).is_true()
	assert_bool(cl.hidden_member("smuggler")).is_true()
	assert_str(cl.hidden_rank("smuggler")).is_equal("Runner")


func test_assassin_path_is_gated_behind_smuggler_contacts() -> void:
	var cl := _new()
	cl.note_activity("crime_murder", 0, 5.0)
	var st := 0
	for l: Dictionary in cl.hidden_leads():
		if l["id"] == "assassin":
			st = int(l["stage"])
	assert_int(st).is_less_equal(1)
	cl.note_activity("explore_sewer", 0, 3.0)
	cl.note_activity("crime_smuggling", 0, 1.0)
	cl.note_activity("crime_murder", 0, 1.0)
	for l: Dictionary in cl.hidden_leads():
		if l["id"] == "assassin":
			st = int(l["stage"])
	assert_int(st).is_greater(1)


func test_crime_in_society_feeds_hidden_leads() -> void:
	var hub := _hub()
	var soc: RefCounted = hub.mod("society")
	var cl: RefCounted = hub.mod("city_life")
	for i in 3:
		soc.commit_crime("pickpocket", 0, 0)
	var found := false
	for l: Dictionary in cl.hidden_leads():
		if l["id"] == "thief":
			found = true
	assert_bool(found).is_true()


func test_guilds_entry_requirements_and_ranks() -> void:
	var cl := _new()
	cl.set_player({"combat": 40, "gold": 200})
	var gs: Array = cl.guilds()
	assert_int(gs.size()).is_greater(2)
	var hunters := ""
	for g: Dictionary in gs:
		if g["kind"] == "hunters":
			hunters = g["id"]
	assert_str(hunters).is_not_empty()
	assert_str(String(cl.guild_requirements(hunters)["entry"])).is_equal("demonstration")
	var mages := ""
	for g: Dictionary in gs:
		if g["kind"] == "mages":
			mages = g["id"]
	if mages != "":
		assert_bool(cl.join_guild(mages)["ok"]).is_false()   # famous guild rejects a beginner
	var ok := false
	for d in range(0, 60, 11):
		cl._last_day = d
		var r: Dictionary = cl.join_guild(hunters)
		if r.get("joined", false):
			ok = true
			break
	assert_bool(ok).is_true()
	var ctx := CTX.duplicate()
	var got_member := false
	for d in range(70, 90):
		cl.tick_day(d, ctx)
		if int(cl.guild(hunters)["player"]["rank"]) >= 1:
			got_member = true
	assert_bool(got_member).is_true()


func test_guild_leaders_change_over_time() -> void:
	var cl := _new()
	var g0: Array = cl.guilds()
	var leaders := {}
	for g: Dictionary in g0:
		leaders[g["id"]] = g["leader"]["name"]
	var ctx := CTX.duplicate()
	for d in range(1, 4000, 1):
		cl.tick_day(d, ctx)
		if d % 400 == 0:
			cl.set_player({"gold": 100000})
	var changed := 0
	for g: Dictionary in cl.guilds():
		if g["leader"]["name"] != leaders[g["id"]]:
			changed += 1
	assert_int(changed).is_greater(0)


func test_district_state_changes_at_night() -> void:
	var cl := _new()
	var sid := _sid_of("castle")
	var day: Dictionary = cl.district_state(sid, "market", 12)
	var night: Dictionary = cl.district_state(sid, "market", 23)
	assert_bool(day["shops_open"]).is_true()
	assert_bool(night["shops_open"]).is_false()
	assert_float(float(night["crime_risk"])).is_greater(float(day["crime_risk"]))
	var slums: Dictionary = cl.district_state(sid, "slums", 2)
	assert_bool((slums["night_npcs"] as Array).size() > 0).is_true()
	var noble: Dictionary = cl.district_state(sid, "noble", 23)
	assert_bool(noble["entry_ok"]).is_false()   # default class 1, gate wants 3 at night
	assert_bool(cl.district_state(sid, "slums", 2)["taverns_open"]).is_true()


func test_schedules_create_opportunities_once_learned() -> void:
	var hub := _hub()
	var cl: RefCounted = hub.mod("city_life")
	var soc: RefCounted = hub.mod("society")
	var sid := _sid_of("town") if _sid_of("town") >= 0 else 0
	var entry: Dictionary = {}
	for e: Dictionary in cl._ensure(sid)["sched"]:
		if e["role"] == "gate_guard":
			entry = e
	assert_bool(entry.is_empty()).is_false()
	var hour: int = entry["from"]
	var opps: Array = cl.opportunities(sid, hour)
	var mine: Dictionary = {}
	for o: Dictionary in opps:
		if o["id"] == entry["id"]:
			mine = o
	assert_bool(mine.is_empty()).is_false()
	assert_bool(mine["known"]).is_false()
	assert_int((mine["actions"] as Array).size()).is_equal(0)
	cl.observe(sid, entry["id"])
	cl._last_day = 1
	cl.observe(sid, entry["id"])
	assert_bool(soc.knows("schedule:" + String(entry["id"]))).is_true()
	for o: Dictionary in cl.opportunities(sid, hour):
		if o["id"] == entry["id"]:
			mine = o
	assert_bool(mine["known"]).is_true()
	assert_bool((mine["actions"] as Array).has("sneak past")).is_true()
	assert_bool(cl.opportunities(sid, entry["to"] + 5).size() < opps.size() + 5).is_true()


func test_failure_is_logged_as_a_story() -> void:
	var hub := _hub()
	var cl: RefCounted = hub.mod("city_life")
	var soc: RefCounted = hub.mod("society")
	cl.set_player({"craft": 40, "charm": 40, "age": 25})
	var id := _inject_job(cl, 0, "smith")
	cl.apply(id, [0, 2, 1])
	cl.caught_stealing()
	var hooks: Array = soc.story_hooks()
	assert_int(hooks.size()).is_greater(0)
	assert_str(String(hooks[0]["hook"])).is_not_empty()
	assert_float(soc.rep("city:0")).is_less(0.0)


func test_serialize_round_trip_including_json() -> void:
	var cl := _new()
	cl.set_player({"craft": 40, "charm": 40, "age": 25, "gold": 300})
	var id := _inject_job(cl, 0, "smith")
	cl.apply(id, [0, 2, 1])
	cl.rent_room(0, 2)
	cl.note_activity("explore_sewer", 0, 3.0)
	cl.guilds()
	cl.tick_day(3, CTX)
	var a: Dictionary = cl.serialize()
	var b := CityLife.new()
	b.deserialize(a)
	assert_str(JSON.stringify(_canon(b.serialize()))).is_equal(JSON.stringify(_canon(a)))
	var c := CityLife.new()
	c.deserialize(JSON.parse_string(JSON.stringify(a)))
	assert_str(JSON.stringify(_canon(c.serialize()))).is_equal(JSON.stringify(_canon(a)))
	assert_str(JSON.stringify(_canon(c.jobs(0)))).is_equal(JSON.stringify(_canon(cl.jobs(0))))
	# Both keep evolving identically after a JSON load (order-independent RNG).
	for d in range(4, 30):
		cl.tick_day(d, CTX)
		c.tick_day(d, CTX)
		if d % 7 == 0:
			cl.tick_week(d / 7, CTX)
			c.tick_week(d / 7, CTX)
	assert_str(JSON.stringify(_canon(c.serialize()))).is_equal(JSON.stringify(_canon(cl.serialize())))


func test_catch_up_is_bounded_and_fires_absent_workers() -> void:
	var cl := _new()
	cl.set_player({"craft": 40, "charm": 40, "age": 25})
	cl.jobs(0)
	cl.jobs(1)
	var id := _inject_job(cl, 0, "smith")
	cl.apply(id, [0, 2, 1])
	var t0 := Time.get_ticks_usec()
	var msgs: Array = cl.catch_up(60, CTX)
	assert_bool(cl.is_employed()).is_false()
	assert_int(msgs.size()).is_greater(0)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)


func test_perf_day_of_ticks_under_budget() -> void:
	var cl := _new()
	cl.set_player({"gold": 200})
	for s: Dictionary in WorldGen.settlements:
		cl.jobs(int(s["id"]))
	cl.guilds()
	var ctx := CTX.duplicate()
	var t0 := Time.get_ticks_usec()
	for h in 24:
		ctx["abs_hours"] = 100.0 + h
		cl.tick_hour(h, ctx)
	cl.tick_day(5, ctx)
	var us := Time.get_ticks_usec() - t0
	assert_int(us).is_less(20000)
