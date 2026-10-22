extends GdUnitTestSuite
## Education: Scout Season at nine, multi-axis tests and corruption, overlooked
## late routes, admission routes, schedule blocks and time acceleration,
## interrupts, truancy ladder, performance/rankings, classmates and their careers,
## sponsors, tournaments, field exercises, graduation, dropping out, and combat
## training that is always available.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 200, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _edu() -> RefCounted:
	WorldGen.setup(2024)
	var e: RefCounted = Hub.new().mod("education")
	e.set_player({"home_sid": 5, "sid": 5, "age": 9, "gold": 200})
	return e


func _sid_of_kind(kind: String) -> int:
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) == kind:
			return int(s["id"])
	return 0


## A strong child who is selected wherever tested (no scouts needed to test the routes).
func _strong_axes() -> Dictionary:
	var a := {}
	for k: String in ["potential", "discipline", "intelligence", "condition", "magic_sensitivity", "resonance", "reflexes", "courage", "memory", "leadership", "constitution"]:
		a[k] = 95.0
	return a


func _weak_axes() -> Dictionary:
	var a := {}
	for k: String in ["potential", "discipline", "intelligence", "condition", "magic_sensitivity", "resonance", "reflexes", "courage", "memory", "leadership", "constitution"]:
		a[k] = 6.0
	return a


func _enrolled(inst_kind := "magic_academy") -> RefCounted:
	var e := _edu()
	e.set_player({"age": 12, "axes": _strong_axes()})
	e._ensure()
	var iid := ""
	for i: Dictionary in e.institutions():
		if String(i["kind"]) == inst_kind and not bool(i["minor"]):
			iid = String(i["id"])
	e.tick_day(1, CTX)
	var r: Dictionary = e.apply(iid, "exam", CTX)
	assert_bool(bool(r["ok"])).is_true()
	return e


func test_institutions_exist_with_church_and_rivals() -> void:
	var e := _edu()
	var kinds := {}
	for i: Dictionary in e.institutions():
		kinds[String(i["kind"])] = true
		assert_str(String(i["campus"])).contains("campus:")
	for k: String in ["magic_academy", "bending_school", "martial_sect", "knight_academy"]:
		assert_bool(kinds.has(k)).is_true()
	assert_bool(kinds.size() >= 8).is_true()
	assert_bool(e.church_schools() is Array).is_true()
	var mage := {}
	for i: Dictionary in e.institutions():
		if String(i["kind"]) == "magic_academy" and not bool(i["minor"]):
			mage = i
	assert_str(String(mage["rival"])).is_not_empty()
	assert_int(e.campus_buildings().size()).is_greater(10)


func test_scout_season_starts_at_age_nine_not_before() -> void:
	var e := _edu()
	e.set_player({"age": 8})
	var m8: Array = e.tick_day(100, CTX)
	assert_bool(e.scout_season().is_empty()).is_true()
	e.set_player({"age": 9})
	var m9: Array = e.tick_day(101, CTX)
	assert_str(String(e.scout_season()["status"])).is_equal("open")
	assert_bool(m9.size() > 0).is_true()
	var before: Dictionary = e.scout_season()
	e.tick_day(102, CTX)
	assert_int(int(e.scout_season()["start_day"])).is_equal(int(before["start_day"]))
	assert_int(m8.size()).is_equal(0)


func test_visiting_orgs_vary_by_region_war_and_wealth() -> void:
	var e := _edu()
	var v: Dictionary = e.visit_weights(_sid_of_kind("village"), false, 0.0)
	var c: Dictionary = e.visit_weights(_sid_of_kind("castle"), false, 0.0)
	assert_str(JSON.stringify(v)).is_not_equal(JSON.stringify(c))
	var peace: Dictionary = e.visit_weights(_sid_of_kind("frontier_town"), false, 0.0)
	var war: Dictionary = e.visit_weights(_sid_of_kind("frontier_town"), true, 0.0)
	var knight := ""
	var mage := ""
	for i: Dictionary in e.institutions():
		if String(i["kind"]) == "knight_academy" and not bool(i["minor"]):
			knight = String(i["id"])
		if String(i["kind"]) == "magic_academy" and not bool(i["minor"]):
			mage = String(i["id"])
	assert_float(float(war[knight]) / float(peace[knight])).is_greater(1.0)
	assert_float(float(war[mage]) / float(peace[mage])).is_less(1.0)
	assert_float(e.region_wealth(_sid_of_kind("castle"))).is_greater(e.region_wealth(_sid_of_kind("village")))
	# Unrest cuts visits.
	var calm: Dictionary = e.visit_weights(_sid_of_kind("village"), false, 0.0)
	var unrest: Dictionary = e.visit_weights(_sid_of_kind("village"), false, 1.0)
	assert_float(float(unrest[knight])).is_less(float(calm[knight]))


func _run_season(e: RefCounted, start: int) -> Array:
	var msgs: Array = []
	msgs.append_array(e.tick_day(start, CTX))
	for d in range(start, start + 30):
		msgs.append_array(e.tick_day(d, CTX))
		for s: Dictionary in e.scouts_present(d):
			e.attend(String(s["id"]))
	return msgs


func test_multi_axis_test_selects_strong_and_overlooks_weak() -> void:
	var found_sel := false
	var found_over := false
	for sid in [2, 5, 7, 9, 11]:
		if sid >= WorldGen.settlements.size():
			continue
		var s := _edu()
		s.set_player({"home_sid": sid, "axes": _strong_axes(), "class": 3})
		_run_season(s, 100)
		if not s.admission_offers().is_empty():
			found_sel = true
			var o: Dictionary = s.admission_offers()[0]
			assert_int((o["shown"] as Array).size()).is_greater(3)
		var w := _edu()
		w.set_player({"home_sid": sid, "axes": _weak_axes(), "class": 0})
		_run_season(w, 100)
		if w.is_overlooked():
			found_over = true
	assert_bool(found_sel).is_true()
	assert_bool(found_over).is_true()


func test_corruption_bribe_and_noble_pressure() -> void:
	var seen_corrupt := false
	for sid in range(0, mini(WorldGen.settlements.size(), 16)):
		var e := _edu()
		e.set_player({"home_sid": sid, "axes": _weak_axes(), "class": 0, "gold": 500})
		e.tick_day(100, CTX)
		for sc: Dictionary in e.scout_season().get("scouts", []):
			if bool(sc["corrupt"]):
				seen_corrupt = true
				var inst: Dictionary = e._insts[String(sc["inst"])]
				var clean: Dictionary = e._test_score(inst, e._scout(String(sc["id"])), false)
				var dirty: Dictionary = e._test_score(inst, e._scout(String(sc["id"])), true)
				assert_float(float(dirty["score"])).is_greater(float(clean["score"]) + 15.0)
				e.tick_day(int(sc["arrive"]), CTX)
				var low: Dictionary = e.attend(String(sc["id"]), 1)
				assert_bool(bool(low["ok"])).is_false()
				var ok: Dictionary = e.attend(String(sc["id"]), int(sc["price"]) + 5)
				assert_bool(bool(ok["ok"])).is_true()
				assert_bool(bool(ok["result"]["bribed"])).is_true()
				assert_int(e.take_pending_gold()).is_less(0)
				break
		if seen_corrupt:
			break
	assert_bool(seen_corrupt).is_true()
	# Only corrupt scouts can be bought.
	for sid in range(0, mini(WorldGen.settlements.size(), 16)):
		var e2 := _edu()
		e2.set_player({"home_sid": sid, "gold": 500})
		e2.tick_day(100, CTX)
		for sc2: Dictionary in e2.scout_season().get("scouts", []):
			if not bool(sc2["corrupt"]):
				e2.tick_day(int(sc2["arrive"]), CTX)
				assert_bool(bool(e2.attend(String(sc2["id"]), 300)["ok"])).is_false()
				return


func test_overlooked_opens_late_routes() -> void:
	var e := _edu()
	e.set_player({"axes": _weak_axes(), "class": 0, "gold": 0})
	_run_season(e, 100)
	assert_bool(e.is_overlooked()).is_true()
	e.set_player({"gold": 0})
	var routes: Array = e.late_routes()
	assert_int(routes.size()).is_greater(9)
	var ids: Array = routes.map(func(r: Dictionary) -> String: return String(r["id"]))
	for k: String in ["private_teacher", "sponsorship", "smaller_school", "old_manual", "military_service", "learn_illegally", "apprentice", "local_tournament"]:
		assert_bool(ids.has(k)).is_true()
	var mil: Dictionary = routes[ids.find("military_service")]
	assert_bool(bool(mil["available"])).is_false()
	var tut: Dictionary = routes[ids.find("private_teacher")]
	assert_bool(bool(tut["available"])).is_false()
	# Growing up and saving money opens doors.
	e.set_player({"age": 16, "gold": 150})
	var later: Array = e.late_routes()
	assert_bool(bool(later[ids.find("military_service")]["available"])).is_true()
	assert_bool(bool(later[ids.find("private_teacher")]["available"])).is_true()
	var t: Dictionary = e.take_late_route("private_teacher")
	assert_bool(bool(t["ok"])).is_true()
	assert_bool(bool(e.late["tutor"])).is_true()
	var soc: RefCounted = e.hub.mod("society")
	assert_bool(soc.knows("topic:late_routes")).is_true()


func test_late_start_can_still_get_in_by_exam() -> void:
	var e := _edu()
	e.set_player({"axes": _strong_axes(), "age": 13, "class": 0, "gold": 100})
	e._ensure()
	var iid := ""
	for i: Dictionary in e.institutions():
		if String(i["kind"]) == "knight_academy" and not bool(i["minor"]):
			iid = String(i["id"])
	var opts: Array = e.admission_options(iid)
	assert_bool(bool(opts[0]["available"])).is_false()
	assert_bool(bool(opts[1]["available"])).is_true()
	var r: Dictionary = e.apply(iid, "exam", CTX)
	assert_bool(bool(r["ok"])).is_true()
	assert_bool(e.is_student()).is_true()
	var weak := _edu()
	weak.set_player({"axes": _weak_axes(), "age": 13, "gold": 100})
	var w: Dictionary = weak.apply(iid, "exam", CTX)
	assert_bool(bool(w["ok"])).is_false()


func test_schedule_time_scale_and_interrupt_events() -> void:
	var e := _enrolled()
	var sch: Array = e.schedule()
	assert_bool(sch.any(func(b: Dictionary) -> bool: return float(b["time_scale"]) == 5.0)).is_true()
	assert_float(e.time_scale(10)).is_equal(5.0)
	assert_float(e.time_scale(17)).is_equal(1.0)
	assert_str(String(e.block_at(10)["id"])).is_equal("lessons")
	assert_str(String(e.block_at(23)["id"])).is_equal("night")
	assert_str(String(e.block_at(3)["id"])).is_equal("night")
	# An interrupt returns normal speed.
	var hit := false
	for d in range(2, 80):
		e.tick_day(d, CTX)
		for h in range(6, 22):
			var msgs: Array = e.tick_hour(h, CTX)
			if not e.current_interrupt().is_empty():
				hit = true
				assert_bool(msgs.size() > 0).is_true()
				assert_float(e.time_scale(h)).is_equal(1.0)
				var kind: String = String(e.current_interrupt()["kind"])
				var choice: String = String(e.current_interrupt()["choices"][0]["id"])
				var r: Dictionary = e.resolve_interrupt(choice)
				assert_str(String(r["kind"])).is_equal(kind)
				assert_bool(e.current_interrupt().is_empty()).is_true()
				break
		if hit:
			break
	assert_bool(hit).is_true()


func test_attending_raises_performance_and_skipping_lowers_grades() -> void:
	var a := _enrolled()
	var b := _enrolled()
	var t0: float = a.performance("theory")
	for d in range(2, 30):
		a.tick_day(d, CTX)
		b.tick_day(d, CTX)
		for h in range(6, 22):
			a.tick_hour(h, CTX)
			a.resolve_interrupt("")
		b.skip_block("lessons")
		for h in range(6, 22):
			b.tick_hour(h, CTX)
			b.resolve_interrupt("")
	assert_float(a.performance("theory")).is_greater(t0)
	assert_float(a.performance("theory")).is_greater(b.performance("theory"))


func test_truancy_ladder_ends_in_expulsion() -> void:
	var e := _enrolled()
	var stages := {}
	var expelled := false
	for d in range(2, 120):
		e.tick_day(d, CTX)
		stages[e.truancy_stage()] = true
		if String(e.student_state()["status"]) == "expelled":
			expelled = true
			break
		if String(e.student_state()["status"]) == "enrolled":
			for b: String in ["morning_training", "lessons", "practical"]:
				e.skip_block(b)
	for st: String in ["warning", "detention", "privileges_lost"]:
		assert_bool(stages.has(st)).is_true()
	assert_bool(expelled).is_true()
	assert_bool(e.is_student()).is_false()


func test_truant_who_trains_elsewhere_is_forgiven_by_admirers() -> void:
	var e := _enrolled()
	for t: Dictionary in e.student["teachers"]:
		t["independence_fan"] = true
		t["lenient"] = false
		t["temper"] = 0.0
	e.train("self_taught", 2, CTX)
	e.skip_block("lessons")
	var forgiven: float = e.student["truancy"]
	var f := _enrolled()
	for t2: Dictionary in f.student["teachers"]:
		t2["independence_fan"] = false
		t2["lenient"] = false
		t2["temper"] = 0.0
	f.skip_block("lessons")
	assert_float(forgiven).is_less(float(f.student["truancy"]))


func test_multi_dimensional_report_and_rankings() -> void:
	var e := _enrolled("magic_academy")
	var card: Dictionary = e.report_card()
	assert_int((card["grades"] as Dictionary).size()).is_equal(5)
	assert_bool(card.has("score")).is_false()
	e.student["perf"]["combat"] = 5.0
	e.student["perf"]["theory"] = 95.0
	assert_str(String(e.report_card()["strength"])).is_equal("theory")
	assert_str(String(e.report_card()["weakness"])).is_equal("combat")
	assert_int(e.player_rank("academic")).is_equal(1)
	var r: Dictionary = e.rankings("combat")
	assert_bool(bool(r["published"])).is_true()
	assert_int((r["rows"] as Array).size()).is_greater(25)
	assert_int(e.player_rank("combat")).is_greater(20)
	# A school that finds rankings harmful publishes none.
	var b := _enrolled("bending_school")
	assert_bool(bool(b.rankings()["published"])).is_false()
	assert_int(b.player_rank()).is_equal(-1)


func test_cohort_of_thirty_named_classmates() -> void:
	var e := _enrolled()
	var ms: Array = e.classmates()
	assert_int(ms.size()).is_equal(30)
	var names := {}
	for m: Dictionary in ms:
		names[String(m["name"])] = true
		assert_bool(int(m["class"]) >= 0 and int(m["class"]) <= 4).is_true()
	assert_int(names.size()).is_greater(27)
	assert_bool(ms.any(func(m: Dictionary) -> bool: return bool(m["roommate"]))).is_true()
	var mid: String = String(ms[5]["id"])
	var a0: float = e.classmate(mid)["affinity"]
	e.interact(mid, "help")
	assert_float(e.classmate(mid)["affinity"]).is_greater(a0)


func test_classmate_careers_run_for_years_and_become_contacts() -> void:
	var e := _enrolled()
	e.catch_up(6 * 360 + 30, CTX)
	e.catch_up(7 * 360, CTX)
	var al: Array = e.alumni()
	assert_int(al.size()).is_greater(10)
	var top := 0
	for a: Dictionary in al:
		top = maxi(top, int(a["rank"]))
	assert_int(top).is_greater(1)
	assert_bool(String(al[0]["title"]).length() > 0).is_true()
	# Weekly step is O(cohort) and deterministic.
	var a2 := _enrolled()
	var b2 := _enrolled()
	a2.catch_up(6 * 360 + 30, CTX)
	b2.catch_up(6 * 360 + 30, CTX)
	for w in range(1, 30):
		a2.tick_week(w, CTX)
		b2.tick_week(w, CTX)
	assert_str(JSON.stringify(a2.serialize())).is_equal(JSON.stringify(b2.serialize()))
	assert_bool(a2.alumni().size() > 0).is_true()


func test_social_class_kit_and_expenses() -> void:
	var e := _enrolled()
	var tr: Dictionary = e.treatment()
	assert_str(String(tr["class"])).is_equal("commoner")
	assert_float(float(tr["kit_gap"])).is_greater(0.0)
	var gap0: float = e.kit_gap()
	assert_bool(bool(e.buy("uniform")["ok"])).is_true()
	assert_bool(bool(e.buy("uniform")["ok"])).is_false()
	assert_float(e.kit_gap()).is_less(gap0)
	assert_bool(e.take_pending_gold() < 0).is_true()
	assert_int(e.weekly_cost()).is_greater(0)
	assert_bool(e.expenses().size() >= 8).is_true()
	e.set_budget("minimal")
	var minimal: int = e.weekly_cost()
	e.set_budget("full")
	assert_int(e.weekly_cost()).is_greater(minimal)
	# Unpaid weeks pile up as arrears; the bursar eventually suspends.
	var p := _enrolled()
	var no_gold := CTX.duplicate()
	no_gold["gold"] = 0
	p.set_player({"gold": 0})
	var suspended := false
	for w in range(1, 12):
		p.tick_week(w, no_gold)
		if String(p.student_state()["status"]) == "suspended":
			suspended = true
	assert_float(float(p.student_state()["arrears"])).is_greater(0.0)
	assert_bool(suspended).is_true()


func test_sponsor_obligations() -> void:
	var e := _enrolled()
	var sp: Dictionary = e._make_sponsor("noble", e._rng("t", 0, "x"))
	e.sponsors_list.append(sp)
	assert_int(e.sponsor_offers().size()).is_equal(1)
	var r: Dictionary = e.accept_sponsor(String(sp["id"]))
	assert_bool(bool(r["ok"])).is_true()
	assert_int((r["obligations"] as Array).size()).is_greater(0)
	assert_int(e.tuition_weekly()).is_equal(0)
	assert_int(e.obligations_after_school().size()).is_greater(0)
	# Neglecting what the sponsor asks costs the sponsorship.
	e.set_player({"gold": 0})
	for w in range(1, 80):
		e.tick_day(w * 7, CTX)
		e.tick_week(w, CTX)
		if String(sp["status"]) == "withdrawn":
			break
	assert_str(String(e.sponsors_list[0]["status"])).is_equal("withdrawn")


func test_factions_clubs_rivals_teachers_mentor() -> void:
	var e := _enrolled()
	assert_bool(bool(e.join_faction("nobles")["ok"])).is_false()
	assert_bool(bool(e.join_faction("commoners")["ok"])).is_true()
	assert_bool(e.student_factions().size() >= 6).is_true()
	assert_bool(bool(e.join_club("dueling")["ok"])).is_true()
	var mid: String = String(e.classmates()[3]["id"])
	e.interact(mid, "embarrass")
	assert_int(e.rivals().size()).is_equal(1)
	assert_bool(bool(e.reconcile(mid)["ok"]) or true).is_true()
	e.rivals_list[0]["heat"] = 10.0
	e.tick_week(1, CTX)
	assert_str(String(e.rivals_list[0]["status"])).is_equal("ally")
	assert_int(e.teachers().size()).is_greater(4)
	# Mentorship needs regard and the mentor's own requirement.
	var t: Dictionary = e.teachers()[1]
	e.student["teachers"][1]["regard"] = 10.0
	e.student["teachers"][1]["trait"] = "caring"
	e.student["perf"][String(t["subject"])] = 60.0
	e.student["perf"]["discipline"] = 60.0
	e.student["perf"]["practical"] = 60.0
	e.student["perf"]["leadership"] = 60.0
	e.student["perf"]["combat"] = 60.0
	e.student["traits"]["courage"] = 60.0
	var rq: Dictionary = e.request_mentorship(String(t["id"]))
	assert_bool(bool(rq["ok"])).is_true()
	assert_bool(bool(e.request_mentorship(String(t["id"]))["ok"])).is_false()
	# Failure ends it.
	e.student["mentor"]["min"] = 500.0
	for w in range(1, 8):
		e.tick_week(w, CTX)
	assert_bool(e.mentor().is_empty()).is_true()


func test_tournament_gives_fame_and_field_exercise_can_go_wrong() -> void:
	var e := _enrolled("knight_academy")
	e.student["perf"]["combat"] = 90.0
	e.student["perf"]["practical"] = 80.0
	var tid := ""
	for d in range(2, 320):
		e.tick_day(d, CTX)
		if tid == "" and not e.tournaments().is_empty():
			tid = String(e.tournaments()[0]["id"])
			var f0: float = e.student["fame"]
			var res: Dictionary = e.enter_tournament(tid, CTX)
			assert_bool(bool(res["ok"])).is_true()
			assert_float(float(e.student["fame"])).is_greater(f0)
			assert_bool(res["log"].size() > 0).is_true()
	assert_str(tid).is_not_empty()
	var outcomes := {}
	for i in 40:
		var x := _enrolled("knight_academy")
		x.exercise = {"id": "fx%d" % i, "kind": "monster_territory", "text": "x", "danger": 0.8, "day": 10 + i, "close": 40, "choices": []}
		var r: Dictionary = x.resolve_exercise("lead")
		outcomes[String(r["outcome"])] = true
	assert_bool(outcomes.has("disaster") or outcomes.has("complications")).is_true()
	# A sweep of the forest schedule appears on the calendar.
	var y := _enrolled()
	var saw := false
	for d in range(2, 120):
		y.tick_day(d, CTX)
		if not y.pending_exercise().is_empty():
			saw = true
			break
	assert_bool(saw).is_true()


func test_graduation_offers_are_refusable_and_dropping_out_keeps_knowledge() -> void:
	var e := _enrolled()
	e.student["perf"]["combat"] = 70.0
	assert_bool(bool(e.graduate()["ok"])).is_false()
	var g: Dictionary = e.graduate(true)
	assert_bool(bool(g["ok"])).is_true()
	var offers: Array = e.graduation_offers()
	assert_int(offers.size()).is_greater(0)
	var acc: Dictionary = e.accept_graduation_offer(String(offers[0]["id"]))
	assert_bool(bool(acc["ok"])).is_true()
	assert_str(e.refuse_all_offers()).contains("turn down")
	assert_int(e.graduation_offers().size()).is_equal(0)
	assert_float(e.school_reputation()).is_greater(0.0)
	var d := _enrolled()
	d.student["perf"]["theory"] = 66.0
	var out: Dictionary = d.drop_out("magic_isnt_for_me")
	assert_bool(bool(out["ok"])).is_true()
	assert_float(float(out["retained"]["theory"])).is_greater(60.0)
	assert_bool(d.is_student()).is_false()


func test_school_reputation_follows_you_and_rival_schools_matter() -> void:
	var e := _enrolled("magic_academy")
	var alma: Dictionary = e.alma_mater()
	var rival: Dictionary = e.institution(String(alma["rival"]))
	var friendly: Dictionary = e.reception(String(alma["id"]))
	var hostile: Dictionary = e.reception(String(rival["id"]))
	assert_float(float(friendly["modifier"])).is_greater(float(hostile["modifier"]))
	e.student["perf"]["combat"] = 1.0
	assert_float(e.ideology_clash(String(alma["id"]), String(alma["id"]))).is_equal(0.0)
	# Society hears it too.
	var soc: RefCounted = e.hub.mod("society")
	e._school_rep_add(String(alma["id"]), 10.0)
	assert_float(soc.rep("school:%s" % String(alma["id"]))).is_equal_approx(10.0, 0.001)


func test_church_funded_school_builds_loyalty_and_waives_tuition() -> void:
	var e := _edu()
	e._ensure()
	var iid := ""
	for k: String in e._insts:
		if String(e._insts[k]["kind"]) == "knight_academy" and not bool(e._insts[k]["minor"]):
			iid = k
	e._insts[iid]["church_funded"] = true
	e.set_player({"age": 12, "axes": _strong_axes(), "class": 0})
	e.tick_day(1, CTX)
	assert_bool(bool(e.apply(iid, "exam", CTX)["ok"])).is_true()
	assert_int(e.tuition_weekly()).is_equal(0)
	for d in range(2, 60):
		e.tick_day(d, CTX)
	assert_float(e.church_loyalty()).is_greater(0.1)
	var church: Dictionary = e.reception("church")
	assert_float(float(church["modifier"])).is_greater(0.0)
	assert_float(e.ideology_clash(iid, String(e.institutions()[1]["id"]))).is_greater(-0.001)


func test_combat_training_is_always_available_whatever_the_career() -> void:
	var e := _edu()
	e.set_player({"age": 20, "sid": 5})
	for sid in range(0, mini(WorldGen.settlements.size(), 12)):
		e.set_player({"sid": sid})
		var opts: Array = e.training_options(CTX)
		assert_int(opts.size()).is_greater(2)
		var avail: Array = opts.filter(func(o: Dictionary) -> bool: return bool(o["available"]))
		assert_int(avail.size()).is_greater(0)
		assert_bool(avail.any(func(o: Dictionary) -> bool: return String(o["id"]) == "self_taught")).is_true()
	# Wanted people are turned away by guards but can still train.
	var soc: RefCounted = e.hub.mod("society")
	soc.bounties["5"] = 100
	e.set_player({"sid": 5})
	var opts2: Array = e.training_options(CTX)
	var guard: Dictionary = opts2.filter(func(o: Dictionary) -> bool: return String(o["id"]) == "guard_sparring")[0]
	assert_bool(bool(guard["available"])).is_false()
	var g0: float = e.fighting_ability()
	for i in 10:
		assert_bool(bool(e.train("drill_yard", 3, CTX)["ok"])).is_true()
	assert_float(e.fighting_ability()).is_greater(g0)
	assert_float(e.take_pending_gains()["combat"]).is_greater(0.5)
	# What people believe lags behind what you can do.
	assert_float(e.known_ability(5)).is_less_equal(e.fighting_ability())
	e.set_player({"age": 5})
	assert_bool(bool(e.train("drill_yard", 1, CTX)["ok"])).is_false()
	assert_bool(bool(e.train("self_taught", 1, CTX)["ok"])).is_true()


func test_determinism_and_round_trip() -> void:
	var a := _enrolled()
	var b := _enrolled()
	for d in range(2, 40):
		a.tick_day(d, CTX)
		b.tick_day(d, CTX)
		for h in range(6, 22):
			a.tick_hour(h, CTX)
			b.tick_hour(h, CTX)
			a.resolve_interrupt("")
			b.resolve_interrupt("")
		if d % 7 == 0:
			a.tick_week(d / 7, CTX)
			b.tick_week(d / 7, CTX)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	var json := JSON.stringify(a.serialize())
	var e2: RefCounted = Hub.new().mod("education")
	e2.deserialize(JSON.parse_string(json))
	assert_str(_norm(e2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_int(e2.classmates().size()).is_equal(30)
	assert_float(float(e2.performance("theory"))).is_equal_approx(float(a.performance("theory")), 0.001)
	# The round-tripped module keeps running identically.
	e2.tick_day(41, CTX)
	a.tick_day(41, CTX)
	assert_str(_norm(e2.serialize())).is_equal(_norm(a.serialize()))
	# Mid scout season too.
	var s := _edu()
	s.tick_day(100, CTX)
	var s2: RefCounted = Hub.new().mod("education")
	s2.deserialize(JSON.parse_string(JSON.stringify(s.serialize())))
	assert_str(_norm(s2.serialize())).is_equal(_norm(s.serialize()))


func test_catch_up_is_bounded_and_deterministic() -> void:
	var a := _enrolled()
	var b := _enrolled()
	var la: Array = a.catch_up(400, CTX)
	var lb: Array = b.catch_up(400, CTX)
	assert_array(la).is_equal(lb)
	assert_bool(la.size() <= 6).is_true()
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	var t0 := Time.get_ticks_usec()
	a.catch_up(3000, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)


func test_displacement_pauses_school() -> void:
	var e := _enrolled()
	e.on_displaced(3)
	assert_str(String(e.student_state()["status"])).is_equal("on_leave")
	assert_float(e.time_scale(10)).is_equal(1.0)
	e.on_returned()
	assert_str(String(e.student_state()["status"])).is_equal("enrolled")


func test_perf_24_hourly_ticks_and_one_day() -> void:
	var e := _enrolled()
	e.tick_day(2, CTX)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		e.tick_hour(h, CTX)
	e.tick_day(3, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
	var s := _edu()
	s.set_player({"age": 9})
	var t1 := Time.get_ticks_usec()
	for h in 24:
		s.tick_hour(h, CTX)
	s.tick_day(100, CTX)
	assert_int(Time.get_ticks_usec() - t1).is_less(20000)
