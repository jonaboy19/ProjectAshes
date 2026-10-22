extends GdUnitTestSuite
## The Scribe career as real mechanics: copying accuracy, forgery clues, old-script glyph knowledge, tax
## ledgers, restricted records and secrets, exams and the six-rank ladder (patron, exam, clean record),
## dismissal and jail, estate and embassy, saves, determinism and cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const Data := preload("res://scripts/realm/scribe_data.gd")
const CareerLadders := preload("res://scripts/sim/career_ladders.gd")

static var _world_ready := false


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _setup_world() -> void:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true


## A hub, the scribe module wired to a private mastery and biography, hired at settlement 0.
func _scribe(hired := true, lvl_xp := 0.0) -> RefCounted:
	_setup_world()
	var hub: RefCounted = Hub.new()
	var sc: RefCounted = hub.mod("scribe")
	sc.mastery_ref = Mastery.new()
	sc.bio_ref = Biography.new()
	sc.gold_ref = 1000
	sc.sync_life = false
	if lvl_xp > 0.0:
		sc.mastery_ref.gain("scholarship", lvl_xp, 1)
	if hired:
		var r: Dictionary = sc.apply(0, 1, 0.9)
		assert_bool(r["ok"]).is_true()
	return sc


## Do the open copy task perfectly or with `bad` wrong lines.
func _do_copy(sc: RefCounted, day: int, bad := 0, steady := 1.0) -> Dictionary:
	var b: Dictionary = sc.begin("copy", day)
	assert_bool(b["ok"]).is_true()
	var lines: Array = sc.task["doc"]["lines"]
	var picks: Array = []
	for i in lines.size():
		var c := int(lines[i]["correct"])
		picks.append((c + 1) % 3 if i < bad else c)
	return sc.submit_copy(picks, steady)


# ---------------------------------------------------------------- copying

func test_copy_lines_have_one_faithful_option_and_two_slips() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var doc: Dictionary = Data.gen_copy(r, 10)
	assert_int((doc["lines"] as Array).size()).is_between(3, 6)
	for l: Dictionary in doc["lines"]:
		var opts: Array = l["options"]
		assert_int(opts.size()).is_equal(3)
		assert_str(String(opts[int(l["correct"])])).is_equal(String(l["src"]))
		var distinct := {}
		for o in opts:
			distinct[o] = true
		assert_int(distinct.size()).is_equal(3)


func test_copy_quality_tracks_accuracy_and_a_shaky_pen_blots() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var doc: Dictionary = Data.gen_copy(r, 10, "contract")
	var good: Array = []
	for l: Dictionary in doc["lines"]:
		good.append(int(l["correct"]))
	var perfect: Dictionary = Data.score_copy(doc, good, 1.0)
	assert_float(perfect["quality"]).is_equal_approx(1.0, 0.001)
	var shaky: Dictionary = Data.score_copy(doc, good, 0.2, 0)
	assert_bool(shaky["blot"]).is_true()
	assert_float(shaky["quality"]).is_less(perfect["quality"])
	var wrong := good.duplicate()
	wrong[0] = (int(wrong[0]) + 1) % 3
	var crit: Dictionary = Data.score_copy(doc, wrong, 1.0)
	assert_int(crit["crit_errors"]).is_equal(1)       # line 0 of a contract carries a name and a date
	assert_float(crit["quality"]).is_less(0.8)


func test_copy_pays_by_quality_and_builds_letters_reputation() -> void:
	var sc := _scribe()
	var good: Dictionary = _do_copy(sc, 2)
	var pay_good := int(good["pay"])
	var rep_good := float(sc.letters_rep())
	var sc2 := _scribe()
	var bad: Dictionary = _do_copy(sc2, 2, 3)
	assert_int(pay_good).is_greater(int(bad["pay"]))
	assert_float(rep_good).is_greater(float(sc2.letters_rep()))
	assert_int(sc.pending_gold).is_equal(pay_good)


func test_freelance_copying_needs_no_post_but_pays_less() -> void:
	var sc := _scribe(false)
	var r := _do_copy(sc, 2)
	assert_bool(r["ok"]).is_true()
	assert_int(int(r["pay"])).is_greater(0)
	var hired := _scribe()
	var h := _do_copy(hired, 2)
	assert_int(int(r["pay"])).is_less(int(h["pay"]))
	# Forgery work is for the employed only.
	var f: Dictionary = sc.begin("forgery", 2)
	assert_bool(f["ok"]).is_false()


# ---------------------------------------------------------------- forgery

func _forged_doc(level: int) -> Dictionary:
	var day := 100
	for s in 400:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var d: Dictionary = Data.gen_forgery(r, level, day, 1.0)
		if (d["flaws"] as Dictionary).size() == 1:
			return d
	return {}


func test_flaws_are_seen_by_skill_and_a_lens_not_by_magic() -> void:
	var d := _forged_doc(1)
	var chan: String = (d["flaws"] as Dictionary).keys()[0]
	var sub := float(d["flaws"][chan])
	# Perception rises with mastery and a lens.
	assert_float(Data.perception(60, false)).is_greater(Data.perception(1, false))
	assert_float(Data.perception(1, true)).is_greater(Data.perception(1, false))
	# A master sees what a novice with no lens can miss.
	var master: Dictionary = Data.examine(d, chan, 100, true)
	assert_bool(master["seen_flaw"]).is_true()
	assert_str(String(master["text"])).contains("specimen")
	var sharp := Data.perception(1, false) >= sub
	var novice: Dictionary = Data.examine(d, chan, 1, false)
	assert_bool(novice["seen_flaw"]).is_equal(sharp)
	# Clean channels never accuse.
	for c: String in Data.CHANNELS:
		if not (d["flaws"] as Dictionary).has(c):
			assert_bool(Data.examine(d, c, 100, true)["seen_flaw"]).is_false()


func test_judging_catches_forgeries_and_punishes_false_alarms() -> void:
	var d := _forged_doc(10)
	var chan: String = (d["flaws"] as Dictionary).keys()[0]
	var caught: Dictionary = Data.judge_forgery(d, "forged", [chan])
	assert_str(caught["outcome"]).is_equal("caught")
	assert_float(caught["quality"]).is_greater(0.9)
	assert_str(Data.judge_forgery(d, "genuine", [])["outcome"]).is_equal("missed")
	var real := d.duplicate(true)
	real["flaws"] = {}
	assert_str(Data.judge_forgery(real, "genuine", [])["outcome"]).is_equal("cleared")
	var wrong: Dictionary = Data.judge_forgery(real, "forged", ["seal"])
	assert_str(wrong["outcome"]).is_equal("false_alarm")
	assert_float(wrong["quality"]).is_less(0.3)


func test_a_forgery_you_pass_is_traced_back_and_costs_you() -> void:
	var sc := _scribe(true, 6.0)     # clerk-level skills: level 12
	sc.rank = 1
	var guard := 0
	var res: Dictionary = {}
	while guard < 40:
		guard += 1
		var b: Dictionary = sc.begin("forgery", 3 + guard)
		assert_bool(b["ok"]).is_true()
		if not (sc.task["doc"]["flaws"] as Dictionary).is_empty():
			res = sc.submit_forgery("genuine", [])
			break
		sc.submit_forgery("genuine", [])
		sc.hours_used.clear()
	assert_str(res["outcome"]).is_equal("missed")
	assert_int(sc.traced.size()).is_greater(0)
	var before: float = sc.standing
	var patron_before: float = sc.patron_regard()
	# Weeks pass; the trace is chance-driven, so give it time.
	var hit := false
	for w in range(2, 60):
		var msgs: Array = sc.tick_week(w, {})
		if not msgs.is_empty() and String(msgs[0]).contains("traced"):
			hit = true
			break
	assert_bool(hit).is_true()
	assert_float(sc.standing).is_less(before)
	assert_float(sc.patron_regard()).is_less(patron_before)


func test_taking_a_bribe_to_pass_a_forgery_ends_in_jail() -> void:
	var sc := _scribe(true, 6.0)
	sc.rank = 2
	var guard := 0
	while guard < 60:
		guard += 1
		sc.hours_used.clear()
		sc.begin("forgery", 3)
		if not (sc.task["doc"]["flaws"] as Dictionary).is_empty():
			break
		sc.abandon_task()
	assert_int(int(sc.task["bribe"])).is_greater(0)
	var gold_before: int = sc.pending_gold
	var r: Dictionary = sc.submit_forgery("genuine", [], true)
	assert_str(r["outcome"]).is_equal("bribed")
	assert_int(sc.pending_gold).is_greater(gold_before - 1)
	var jailed := false
	for w in range(2, 80):
		sc.tick_week(w, {})
		if sc.is_jailed(w * 7):
			jailed = true
			break
	assert_bool(jailed).is_true()
	assert_bool(sc.active).is_false()
	assert_bool(sc.clean_record(sc.jail_until)).is_false()    # the record outlasts the cell
	assert_int(sc.rank).is_less(2)


# ---------------------------------------------------------------- old script

func test_known_glyphs_read_themselves_and_guesses_teach_new_ones() -> void:
	var sc := _scribe(true, 4.0)
	var hub: RefCounted = sc.hub
	var soc: RefCounted = hub.mod("society")
	assert_bool(soc.knows("glyph:orr")).is_false()
	sc.learn_glyph("orr")
	assert_bool(soc.knows("glyph:orr")).is_true()          # knowledge is shared with society
	assert_array(sc.glyphs_known_list()).contains(["orr"])
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var t: Dictionary = Data.gen_translation(r, 0)
	var all_right: Array = []
	for c: Dictionary in t["choices"]:
		all_right.append(int(c["correct"]))
	var sc_known: Dictionary = Data.score_translation(t, t["glyphs"], [])
	assert_float(sc_known["quality"]).is_equal_approx(1.0, 0.001)    # everything known: no guessing
	var blind: Dictionary = Data.score_translation(t, [], [])
	assert_float(blind["quality"]).is_less(0.2)
	var guessed: Dictionary = Data.score_translation(t, [], all_right)
	assert_float(guessed["quality"]).is_greater(0.8)
	assert_int((guessed["learned"] as Array).size()).is_equal((t["glyphs"] as Array).size())


func test_translating_adds_society_knowledge_and_counts_for_promotion() -> void:
	var sc := _scribe(true, 6.0)
	sc.rank = 1
	var b: Dictionary = sc.begin("translate", 3)
	assert_bool(b["ok"]).is_true()
	assert_bool(not (sc.task_view()["text"] as Dictionary).has("fact")).is_true()     # the view never leaks answers
	var guesses: Array = []
	for c: Dictionary in sc.task["text"]["choices"]:
		guesses.append(int(c["correct"]))
	var fact := String(sc.task["text"]["fact"])
	var res: Dictionary = sc.submit_translation(guesses)
	assert_float(res["quality"]).is_greater(0.8)
	assert_bool(sc.hub.mod("society").knows(fact)).is_true()
	assert_int(int(sc.stats["translations"])).is_equal(1)
	# Studying the tables teaches glyphs without a task.
	var st: Dictionary = sc.study_glyphs(4)
	assert_bool(st["ok"]).is_true()


# ---------------------------------------------------------------- tax

func test_tax_ledger_uses_the_settlements_rate_and_notices_errors() -> void:
	var sc := _scribe(true, 6.0)
	sc.rank = 1
	var gov: RefCounted = sc.hub.mod("governance")
	gov.set_player_ruler(0, true)
	assert_bool(gov.set_tax(0, 0.25)).is_true()
	var b: Dictionary = sc.begin("tax", 3)
	assert_bool(b["ok"]).is_true()
	var led: Dictionary = sc.task["ledger"]
	assert_float(led["rate"]).is_equal_approx(0.25, 0.001)
	for row: Dictionary in led["rows"]:
		if row["err"] == "":
			assert_int(int(row["ledger"])).is_equal(int(row["receipt"]))
			assert_int(int(row["due"])).is_equal(int(round(float(row["income"]) * 0.25)))
	var view: Dictionary = sc.task_view()
	for row: Dictionary in view["ledger"]["rows"]:
		assert_bool(row.has("err")).is_false()
	var marked: Array = []
	for i in (led["rows"] as Array).size():
		if led["rows"][i]["err"] != "":
			marked.append(i)
	var res: Dictionary = sc.submit_tax(marked)
	assert_float(res["quality"]).is_equal_approx(1.0, 0.001)
	assert_int(int(res["found"])).is_equal(int(led["errors"]))


func test_flagging_honest_rows_costs_quality_and_a_skim_becomes_a_secret() -> void:
	var r := RandomNumberGenerator.new()
	var led: Dictionary = {}
	for s in 200:
		r.seed = s
		led = Data.gen_tax(r, 0.2, 1.0, 10)
		if int(led["skims"]) > 0:
			break
	assert_int(int(led["skims"])).is_greater(0)
	var honest: Array = []
	var bad: Array = []
	for i in (led["rows"] as Array).size():
		(bad if led["rows"][i]["err"] != "" else honest).append(i)
	var careless: Dictionary = Data.score_tax(led, bad + honest)
	var careful: Dictionary = Data.score_tax(led, bad)
	assert_float(careless["quality"]).is_less(careful["quality"])
	assert_int(careless["false_flags"]).is_equal(honest.size())
	# Through the module: finding a skim records a restricted secret and tells society.
	var sc := _scribe(true, 6.0)
	sc.rank = 1
	var guard := 0
	while guard < 60:
		guard += 1
		sc.hours_used.clear()
		sc.begin("tax", 3 + guard)
		if int(sc.task["ledger"]["skims"]) > 0:
			break
		sc.abandon_task()
	var marks: Array = []
	for i in (sc.task["ledger"]["rows"] as Array).size():
		if sc.task["ledger"]["rows"][i]["err"] != "":
			marks.append(i)
	var res: Dictionary = sc.submit_tax(marks)
	assert_bool(res.has("secret")).is_true()
	assert_bool(sc.hub.mod("society").knows("secret:" + String(res["secret"]))).is_true()


# ---------------------------------------------------------------- consequences

func test_repeated_botched_work_gets_you_dismissed_and_then_barred() -> void:
	var sc := _scribe()
	var day := 2
	var fired := false
	for i in 12:
		sc.hours_used.clear()
		var r := _do_copy(sc, day, 6, 0.1)
		if bool(r["fired"]):
			fired = true
			break
	assert_bool(fired).is_true()
	assert_bool(sc.active).is_false()
	assert_bool(sc.is_banned(day)).is_true()
	assert_str(String(sc.apply_refusal(0, day))).is_not_empty()
	assert_int(sc.dismissals).is_equal(1)
	# After the ban the desk is open again, one rank down at most.
	assert_str(sc.apply_refusal(0, sc.banned_until + 1)).is_empty()


func test_restricted_records_need_rank_and_reveal_a_secret_you_can_use() -> void:
	var sc := _scribe(true, 12.0)
	var no: Dictionary = sc.read_restricted(3)
	assert_bool(no["ok"]).is_false()                      # a copyist may not
	sc.rank = 2
	var r: Dictionary = sc.read_restricted(3)
	assert_bool(r["ok"]).is_true()
	var s: Dictionary = r["secret"]
	assert_str(String(s["text"])).is_not_empty()
	assert_bool(sc.hub.mod("society").knows("secret:" + String(s["id"]))).is_true()
	assert_int(int(sc.stats["restricted_reads"])).is_equal(1)
	# Reporting pays an honest wage and the patron approves.
	var reg_before: float = sc.patron_regard()
	var use: Dictionary = sc.use_secret(String(s["id"]), "report", 3)
	assert_bool(use["ok"]).is_true()
	assert_int(int(use["gold"])).is_greater(0)
	if not bool(s["about_patron"]):
		assert_float(sc.patron_regard()).is_greater(reg_before)
	assert_bool(sc.use_secret(String(s["id"]), "report", 3)["ok"]).is_false()     # spent


func test_blackmail_pays_when_it_works_and_jails_when_it_does_not() -> void:
	var paid := 0
	var jailed := 0
	for trial in 30:
		var sc := _scribe(true, 12.0)
		sc.rank = 3
		var s: Dictionary = sc._new_secret("skim", 10 + trial, 0, false)
		var r: Dictionary = sc.use_secret(String(s["id"]), "blackmail", 10 + trial)
		assert_str(String(r["crime"])).is_equal("extortion")
		if bool(r["jailed"]):
			jailed += 1
			assert_bool(sc.is_jailed(10 + trial)).is_true()
			assert_bool(sc.active).is_false()
		else:
			paid += 1
			assert_int(int(r["gold"])).is_greater(0)
	assert_int(paid).is_greater(0)
	assert_int(jailed).is_greater(0)


func test_sneaking_into_the_archive_as_a_junior_is_dangerous() -> void:
	var caught := 0
	var got := 0
	for trial in 24:
		var sc := _scribe(true, 6.0)
		var r: Dictionary = sc.read_restricted(5 + trial, true)
		if bool(r.get("caught", false)):
			caught += 1
			assert_bool(sc.active).is_false()     # dismissed or jailed
		elif bool(r["ok"]):
			got += 1
	assert_int(caught).is_greater(0)
	assert_int(got).is_greater(0)


func test_reporting_the_patrons_own_secret_costs_the_patron() -> void:
	var sc := _scribe(true, 12.0)
	sc.rank = 2
	sc.patron["regard"] = 70.0
	var s: Dictionary = sc._new_secret("bastard", 8, 0, true)
	assert_str(String(s["house"])).is_equal(String(sc.patron["house"]))
	sc.use_secret(String(s["id"]), "report", 8)
	assert_float(sc.patron_regard()).is_less(40.0)
	assert_int(sc.sponsor_tier()).is_less(CareerLadders.SPONSOR_TIER_NEEDED)


# ---------------------------------------------------------------- ladder

func test_scribe_ladder_is_the_six_ranks_in_order() -> void:
	var l := CareerLadders.ladder("scribe")
	var ids: Array = l.map(func(x: Dictionary) -> String: return String(x["id"]))
	assert_array(ids).is_equal(["copyist", "clerk", "registrar", "stewards_secretary", "steward", "envoy"])
	assert_str(CareerLadders.title_for("scribe", "stewards_secretary")).is_equal("Steward's Secretary")
	assert_bool(((l[2] as Dictionary)["requires"] as Dictionary).has("exam")).is_true()
	assert_bool(((l[3] as Dictionary)["requires"] as Dictionary).get("sponsor", false)).is_true()


func test_promotion_lists_what_is_missing_and_needs_patron_exam_and_clean_record() -> void:
	var sc := _scribe()
	sc.rank = 1
	sc.since_day = 0
	var st: Dictionary = sc.promotion_status(60)
	assert_bool(st["eligible"]).is_false()
	var miss: Array = Array(st["missing"] as PackedStringArray)
	assert_bool(miss.any(func(m: String) -> bool: return m.contains("Registrar's Examination"))).is_true()
	# Give it everything except the exam.
	for d in 40:
		sc.mastery_ref.gain("scholarship", 2.0, d)
	sc.bio_ref.change_rep("letters", 30.0)
	sc.stats["forgeries_caught"] = 3
	sc.stats["tax_audits"] = 3
	assert_bool(sc.promotion_status(60)["eligible"]).is_false()
	# The exam: wrong answers fail, right ones pass.
	var b: Dictionary = sc.begin("exam", 61)
	assert_bool(b["ok"]).is_true()
	assert_bool(not (sc.task_view()["questions"][0] as Dictionary).has("a")).is_true()
	var qs: Array = sc.task["questions"]
	var wrong: Array = qs.map(func(q: Dictionary) -> int: return (int(q["a"]) + 1) % 4)
	var fail: Dictionary = sc.submit_exam(wrong)
	assert_bool(fail["passed"]).is_false()
	sc.hours_used.clear()
	sc.begin("exam", 62)
	var right: Array = (sc.task["questions"] as Array).map(func(q: Dictionary) -> int: return int(q["a"]))
	assert_bool(sc.submit_exam(right)["passed"]).is_true()
	assert_bool(sc.exams.has("registrar_exam")).is_true()
	assert_bool(sc.promotion_status(63)["eligible"]).is_true()
	var p: Dictionary = sc.petition(63)
	assert_bool(p["ok"]).is_true()
	assert_str(sc.rank_id()).is_equal("registrar")
	assert_str(String(sc.bio_ref.current_chapter().get("rank", ""))).is_equal("registrar")


func test_a_secretary_needs_the_patrons_friendship_and_a_clean_record() -> void:
	var sc := _scribe()
	sc.rank = 2
	sc.since_day = 0
	for d in 60:
		sc.mastery_ref.gain("scholarship", 2.0, d)
	sc.bio_ref.change_rep("letters", 40.0)
	sc.stats["translations"] = 4
	sc.stats["restricted_reads"] = 2
	sc.patron["regard"] = 20.0
	var st: Dictionary = sc.promotion_status(80)
	assert_bool(Array(st["missing"] as PackedStringArray).any(func(m: String) -> bool: return m.contains("sponsor"))).is_true()
	sc.patron["regard"] = 75.0
	assert_bool(sc.promotion_status(80)["eligible"]).is_true()
	sc.record_until = 200      # a conviction on file
	var st2: Dictionary = sc.promotion_status(80)
	assert_bool(Array(st2["missing"] as PackedStringArray).any(func(m: String) -> bool: return m.contains("clean record"))).is_true()


func test_patron_is_the_settlements_governance_leader() -> void:
	var sc := _scribe()
	var gov: RefCounted = sc.hub.mod("governance")
	var leader: Dictionary = gov.leader_of_settlement(0)
	assert_str(String(sc.patron["name"])).is_equal(String(leader["n"]))
	assert_str(String(sc.patron["pid"])).is_equal(String(leader["id"]))
	assert_int(sc.sponsor_tier()).is_less(CareerLadders.SPONSOR_TIER_NEEDED)
	sc.patron["regard"] = 61.0
	assert_int(sc.sponsor_tier()).is_equal(CareerLadders.SPONSOR_TIER_NEEDED)


# ---------------------------------------------------------------- estate, embassy

func test_a_steward_runs_an_estate_whose_loyalty_answers_the_policy() -> void:
	var sc := _scribe(true, 30.0)
	sc.rank = 4
	sc.assign_estate(10)
	assert_bool(sc.estate.is_empty()).is_false()
	var land: RefCounted = sc.hub.mod("land")
	var region: String = sc.estate["region"]
	var l0 := float(land.loyalty(region))
	sc.set_estate_policy(0, 2)         # low rent, full repairs
	for w in 6:
		sc.estate_week(14 + w * 7)
	var kind: float = land.loyalty(region)
	assert_float(kind).is_greater(l0)
	var sc2 := _scribe(true, 30.0)
	sc2.rank = 4
	sc2.assign_estate(10)
	var land2: RefCounted = sc2.hub.mod("land")
	var m0 := float(land2.loyalty(sc2.estate["region"]))
	sc2.set_estate_policy(2, 0)        # high rent, no repairs
	for w in 6:
		sc2.estate_week(14 + w * 7)
	assert_float(land2.loyalty(sc2.estate["region"])).is_less(m0)
	assert_int(int(sc.stats["estate_weeks"])).is_equal(6)


func test_skimming_the_estate_is_eventually_audited_into_jail() -> void:
	var arrested := 0
	for trial in 6:
		var sc := _scribe(true, 30.0)
		sc.rank = 4
		sc.assign_estate(10 + trial)
		sc.estate["treasury"] = 2000
		sc.estate_skim(400)
		for w in 80:
			var rep: Dictionary = sc.estate_week(20 + trial + w * 7)
			if bool(rep.get("arrested", false)):
				arrested += 1
				assert_bool(sc.is_jailed(20 + trial + w * 7)).is_true()
				break
	assert_int(arrested).is_greater(3)


func test_an_envoy_moves_nation_relations_by_reading_the_court() -> void:
	var sc := _scribe(true, 40.0)
	sc.rank = 5
	sc.patron["regard"] = 60.0
	var ms: Array = sc.missions(70)
	assert_int(ms.size()).is_greater(0)
	var m: Dictionary = ms[0]
	var fa: RefCounted = sc.hub.mod("factions")
	var t0 := float(fa.relation("caldrenn", String(m["target"]))["trust"])
	var want: Array = sc.wanted_tones(fa.relation("caldrenn", String(m["target"])), float(m["diff"]), hash([WorldSim.SEED, "env", String(m["id"])]))
	var res: Dictionary = sc.run_mission(m, want, 70)
	assert_bool(res["ok"]).is_true()
	assert_str(String(res["outcome"])).is_equal("success")
	assert_float(fa.relation("caldrenn", String(m["target"]))["trust"]).is_greater(t0)
	assert_int(int(res["pay"])).is_greater(0)
	# A tone-deaf envoy gets nothing.
	sc.hours_used.clear()
	var bad: Array = want.map(func(t: String) -> String: return "press" if t != "press" else "flatter")
	var res2: Dictionary = sc.run_mission(ms[1], bad, 70)
	assert_str(String(res2["outcome"])).is_not_equal("success")


# ---------------------------------------------------------------- saves, determinism, cost, shifts

func test_state_round_trips_through_json() -> void:
	var sc := _scribe(true, 12.0)
	sc.rank = 4
	_do_copy(sc, 2)
	sc.assign_estate(5)
	sc.read_restricted(6)
	sc.learn_glyph("sul")
	sc.exams["registrar_exam"] = 3
	sc.begin("forgery", 7)
	var a: Dictionary = JSON.parse_string(JSON.stringify(sc.serialize()))
	var sc2 := _scribe(false)
	sc2.deserialize(a)
	assert_str(_norm(sc2.serialize())).is_equal(_norm(sc.serialize()))
	assert_int(sc2.rank).is_equal(4)
	assert_bool(sc2.is_jailed(0)).is_false()


func test_generation_is_deterministic_for_a_seed() -> void:
	var a := _scribe()
	var b := _scribe()
	a.begin("tax", 4)
	b.begin("tax", 4)
	assert_str(_norm(a.task)).is_equal(_norm(b.task))
	a.abandon_task()
	b.abandon_task()
	a.hours_used.clear()
	b.hours_used.clear()
	a.begin("copy", 5)
	b.begin("copy", 5)
	assert_str(_norm(a.task["doc"])).is_equal(_norm(b.task["doc"]))


func test_a_day_has_a_limited_number_of_work_hours() -> void:
	var sc := _scribe()
	var n := 0
	for i in 8:
		var b: Dictionary = sc.begin("copy", 3)
		if not bool(b["ok"]):
			break
		sc.submit_copy([0, 0, 0], 1.0)
		n += 1
	assert_int(n).is_between(4, 6)
	assert_str(String(sc.begin("copy", 3)["reason"])).contains("enough")
	assert_bool(sc.begin("copy", 4)["ok"]).is_true()     # tomorrow is another day


func test_the_scribe_shift_opens_the_rich_tasks_and_pays_through_the_module() -> void:
	var sc := _scribe()
	var w: RefCounted = sc.hub.mod("work")
	w.mastery_ref = sc.mastery_ref
	var pw: Dictionary = w.player_work()
	assert_str(String(pw["job"])).is_equal("scribe")
	assert_str(String(pw["via"])).is_equal("scribe")
	var shift: Dictionary = w.begin("scribe", 0, 3, "spring", 10.0)
	assert_bool(shift["ok"]).is_true()
	var t: Dictionary = w.current_task()
	assert_str(String(t["rich"])).is_equal("copy")
	# A quality reported by the rich task is used even for the choice tasks.
	w.resolve_task(0.9)
	w.resolve_task(0.9)     # seal
	var file: Dictionary = w.current_task()
	assert_str(String(file["rich"])).is_equal("forgery")
	var r: Dictionary = w.resolve_task(0.85)
	assert_float(r["quality"]).is_equal_approx(0.85, 0.001)


func test_hub_ticks_and_catch_up_stay_cheap() -> void:
	var sc := _scribe()
	sc.rank = 4
	sc.assign_estate(5)
	var t0 := Time.get_ticks_usec()
	for d in 60:
		sc.tick_day(10 + d, {})
		if d % 7 == 0:
			sc.tick_week((10 + d) / 7, {})
	sc.catch_up(2000, {})
	var per := float(Time.get_ticks_usec() - t0) / 60.0
	assert_float(per).is_less(3000.0)
