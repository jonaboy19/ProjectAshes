extends GdUnitTestSuite
## Job work layer: task sequences per job, quality -> pay / mastery, problems -> call-ups and
## story hooks, determinism, save round trip, perf.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const SMITH_JOB := {"job": "j1", "tpl": "smith", "sid": 0, "title": "Journeyman", "employer": "Harl the Smith", "wage": 10, "rank": 0, "ladder": ["Journeyman"],
	"hired": 0, "since_rank": 0, "shift": [7, 15], "performance": 60.0, "merit": 0.0, "missed": 0, "recent_missed_day": 0, "worked_today": false,
	"days_worked": 0, "owed": 0, "leave_until": -1}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


static var _world_ready := false


func _setup_world() -> void:
	if not _world_ready:
		WorldGen.setup(2024)
		_world_ready = true


func _w(employed := false) -> RefCounted:
	_setup_world()
	var hub: RefCounted = Hub.new()
	var w: RefCounted = hub.mod("work")
	w.mastery_ref = Mastery.new()
	if employed:
		var cl: RefCounted = hub.mod("city_life")
		cl._job = SMITH_JOB.duplicate(true)
		cl._hour = 9
		cl._last_day = 5
	return w


## Do the whole round at a fixed quality, taking option 0 in choices and problems.
func _run(w: RefCounted, q: float, opt := 0) -> Dictionary:
	var guard := 0
	while w.on_shift() and guard < 30:
		guard += 1
		if not w.pending_problem().is_empty():
			w.resolve_problem(opt)
			continue
		var t: Dictionary = w.current_task()
		if t.is_empty():
			break
		w.resolve_task(q, opt)
	return w.finish({})


func test_every_job_has_a_valid_shift() -> void:
	var w := _w()
	assert_int(w.job_ids().size()).is_equal(15)
	for job: String in w.job_ids():
		var jd: Dictionary = w.job_def(job)
		for season in ["spring", "summer", "autumn", "winter"]:
			var seq: Array = w.task_ids(job, season)
			assert_int(seq.size()).is_between(3, 4)
			for id: String in seq:
				var t: Dictionary = w.task_def(job, id)
				assert_bool(t.is_empty()).is_false()
				assert_bool(String(t["widget"]) in ["timing", "hold", "choice"]).is_true()
				var kinds := (jd["spots"] as Array).map(func(s: Dictionary) -> String: return String(s["kind"]))
				assert_bool(String(t["spot"]) in kinds).is_true()
				assert_float(float(t["hours"])).is_greater(0.0)
				if String(t["widget"]) == "choice":
					assert_int((t["options"] as Array).size()).is_greater(1)
		assert_int((jd["problems"] as Array).size()).is_greater(1)
		assert_str(String(jd["discipline"])).is_not_empty()
		assert_bool(String(jd["discipline"]) in Mastery.DISCIPLINES).is_true()
		for tier in ["great", "ok", "poor"]:
			assert_int((jd["say"][tier] as Array).size()).is_greater(0)


func test_forge_sequence_and_farm_by_season() -> void:
	var w := _w()
	assert_array(w.task_ids("blacksmith", "summer")).is_equal(["forge", "quench", "grind"])
	assert_array(w.task_ids("farmer", "spring")).is_equal(["till", "sow", "water"])
	assert_array(w.task_ids("farmer", "autumn")).is_equal(["harvest", "bundle", "store"])
	assert_bool(w.task_ids("farmer", "winter") != w.task_ids("farmer", "summer")).is_true()
	assert_str(String(w.task_def("merchant", "haggle_a")["widget"])).is_equal("choice")


func test_minigame_maths() -> void:
	var W := preload("res://scripts/realm/work.gd")
	assert_float(W.timing_quality(0.5, 0.5, 0.2)).is_equal_approx(1.0, 0.001)
	assert_float(W.timing_quality(0.55, 0.5, 0.2)).is_between(0.6, 1.0)
	assert_float(W.timing_quality(0.0, 0.9, 0.2)).is_equal_approx(0.0, 0.001)
	assert_float(W.zone_width(0.9, 1)).is_less(W.zone_width(0.2, 1))
	assert_float(W.zone_width(0.5, 60)).is_greater(W.zone_width(0.5, 1))


func test_layout_is_deterministic_and_near_settlement() -> void:
	var a: RefCounted = _w()
	var b: RefCounted = _w()
	var pa: Array = a.workplaces(0)
	assert_int(pa.size()).is_equal(15)
	assert_str(_norm(pa.map(func(p: Dictionary) -> Array: return [p["job"], snappedf((p["center"] as Vector2).x, 0.01)]))).is_equal(
		_norm(b.workplaces(0).map(func(p: Dictionary) -> Array: return [p["job"], snappedf((p["center"] as Vector2).x, 0.01)])))
	var st: Dictionary = WorldGen.settlements[0]
	for p: Dictionary in pa:
		assert_float((p["center"] as Vector2).distance_to(st["pos"])).is_less(float(st["radius"]) * 1.4)
		for s: Dictionary in p["spots"]:
			assert_float((s["pos"] as Vector2).distance_to(p["center"])).is_less(float(p["radius"]))
	var at: Dictionary = a.workplace_at((pa[0]["center"] as Vector2) + Vector2(1, 0), 0)
	assert_str(String(at["job"])).is_equal(String(pa[0]["job"]))


func test_start_rules() -> void:
	var w := _w()
	assert_str(w.start_refusal("blacksmith", 3.0, 5)).contains("runs")
	assert_str(w.start_refusal("blacksmith", 9.0, 5)).is_equal("")
	var r: Dictionary = w.begin("blacksmith", 0, 5, "summer", 9.0)
	assert_bool(bool(r["ok"])).is_true()
	assert_bool(bool(w.begin("blacksmith", 0, 5, "summer", 9.0)["ok"])).is_false()
	_run(w, 0.8)
	assert_str(w.start_refusal("blacksmith", 9.0, 5)).contains("today")
	assert_str(w.start_refusal("blacksmith", 9.0, 6)).is_equal("")


func test_quality_drives_pay_and_mastery_for_employed_smith() -> void:
	var good := _w(true)
	good.begin("blacksmith", 0, 5, "summer", 9.0)
	var rg := _run(good, 1.0, 0)
	var bad := _w(true)
	bad.begin("blacksmith", 0, 5, "summer", 9.0)
	var rb := _run(bad, 0.1, 2)
	assert_str(String(rg["wage_via"])).is_equal("city_life")
	assert_float(float(rg["quality"])).is_greater(float(rb["quality"]))
	var cg: RefCounted = good.hub.mod("city_life")
	var cb: RefCounted = bad.hub.mod("city_life")
	assert_int(int(cg._job["owed"])).is_greater(int(cb._job["owed"]))
	assert_float(float(cg._job["performance"])).is_greater(float(cb._job["performance"]))
	assert_bool(bool(cg._job["worked_today"])).is_true()
	assert_float(float(good.mastery_ref.xp.get("smithing", 0.0))).is_greater(float(bad.mastery_ref.xp.get("smithing", 0.0)))
	assert_str(String(rg["comment"])).contains("Harl the Smith")
	assert_float(good.standing_with("Harl the Smith")).is_greater(50.0)
	assert_float(bad.standing_with("Harl the Smith")).is_less(50.0)


func test_freelance_pays_tips_and_orders() -> void:
	var w := _w()
	w.begin("baker", 0, 12, "summer", 5.0)
	var r := _run(w, 0.9)
	assert_str(String(r["wage_via"])).is_equal("freelance")
	assert_int(int(r["gold"])).is_greater(0)
	assert_int(w.take_pending_gold()).is_greater(0)
	assert_int(w.pending_gold).is_equal(0)
	assert_float(float(w.mastery_ref.xp.get("cooking", 0.0))).is_greater(0.0)


func test_merchant_haggle_trades_price_for_regard() -> void:
	var w := _w()
	var t: Dictionary = w.task_def("merchant", "haggle_a")
	var opts: Array = t["options"]
	assert_int(int(opts[0]["tip"])).is_greater(int(opts[2]["tip"]))
	assert_float(float(opts[0]["regard"])).is_less(float(opts[2]["regard"]))
	w.begin("merchant", 0, 3, "spring", 9.0)
	w.resolve_task(1.0)   # open stall
	var gold0: int = w.pending_gold
	var r: Dictionary = w.resolve_task(0.0, 0)
	assert_str(String(r["task"])).is_equal("haggle_a")
	assert_int(w.pending_gold).is_equal(gold0 + int(opts[0]["tip"]))


func test_problems_appear_scale_with_poor_work_and_raise_callups() -> void:
	var raised := {}
	var problems := 0
	var shifts := 0
	for day in range(2, 200):
		var w := _w()
		w.begin("blacksmith", 0, day, "summer", 9.0)
		var guard := 0
		while w.on_shift() and guard < 20:
			guard += 1
			var p: Dictionary = w.pending_problem()
			if not p.is_empty():
				problems += 1
				# Take the worst (last) option: trouble grows.
				var r: Dictionary = w.resolve_problem((p["options"] as Array).size() - 1)
				var cu: Dictionary = r["callup"]
				if not cu.is_empty():
					raised[String(cu["template"])] = cu
				continue
			if w.current_task().is_empty():
				break
			w.resolve_task(0.3, 2)
		w.finish({})
		shifts += 1
	assert_int(problems).is_greater(20)
	assert_bool(raised.is_empty()).is_false()
	var any: Dictionary = raised.values()[0]
	assert_str(String(any["status"])).is_equal("open")
	assert_bool(bool(any.get("job_trigger", false))).is_true()
	assert_str(String(any["template"])).is_equal(String(any["template"]))


func test_good_work_has_fewer_problems_than_bad() -> void:
	var hi := 0
	var lo := 0
	for day in range(2, 150):
		var w := _w()
		w.begin("carpenter", 0, day, "summer", 9.0)
		while w.on_shift() and not w.current_task().is_empty() or (w.on_shift() and not w.pending_problem().is_empty()):
			if not w.pending_problem().is_empty():
				w.resolve_problem(0)
				continue
			var r: Dictionary = w.resolve_task(1.0, 0)
			if not (r["problem"] as Dictionary).is_empty():
				hi += 1
		w.finish({})
		var w2 := _w()
		w2.begin("carpenter", 0, day, "summer", 9.0)
		while w2.on_shift() and not w2.current_task().is_empty() or (w2.on_shift() and not w2.pending_problem().is_empty()):
			if not w2.pending_problem().is_empty():
				w2.resolve_problem(0)
				continue
			var r2: Dictionary = w2.resolve_task(0.0, 2)
			if not (r2["problem"] as Dictionary).is_empty():
				lo += 1
		w2.finish({})
	assert_int(lo).is_greater(hi)


func test_problem_story_hook_and_injury() -> void:
	var w := _w(true)
	var soc: RefCounted = w.hub.mod("society")
	var hooks0: int = soc.story_hooks().size()
	# Force a known problem: the smith hides a flaw.
	w.begin("blacksmith", 0, 5, "summer", 9.0)
	w.shift["pending"] = (w.job_def("blacksmith")["problems"] as Array)[0].duplicate(true)
	var r: Dictionary = w.resolve_problem(1)   # use it and hide the flaw
	assert_str(String(r["story"])).is_equal("shoddy_work")
	assert_int(soc.story_hooks().size()).is_equal(hooks0 + 1)
	# A woodcutter's ignored widowmaker injures: city_life leave.
	w.shift = {}
	w.begin("blacksmith", 0, 5, "summer", 9.0)
	w.shift["pending"] = {"id": "x", "text": "t", "weight": 1.0, "callup": "", "story": "", "options": [{"text": "hurt", "q": 0.1, "injure": 3}]}
	var r2: Dictionary = w.resolve_problem(0)
	assert_int(int(r2["injured"])).is_equal(3)
	assert_int(int(w.hub.mod("city_life")._job["leave_until"])).is_equal(5 + 3)


func test_normal_speed_during_problems() -> void:
	# A task that triggers a problem reports 0 hours; routine tasks report their hours.
	for day in range(2, 120):
		var w := _w()
		w.begin("miner", 0, day, "summer", 9.0)
		var r: Dictionary = w.resolve_task(0.0, 2)
		if not (r["problem"] as Dictionary).is_empty():
			assert_float(float(r["hours"])).is_equal(0.0)
			assert_bool(w.current_task().is_empty()).is_true()   # decision first
			return
		else:
			assert_float(float(r["hours"])).is_greater(0.0)
	fail("no problem in 120 shifts")


func test_board_text_and_determinism() -> void:
	var w := _w()
	var b1: Array = w.board(0, "farmer", 10)
	var b2: Array = w.board(0, "farmer", 10)
	assert_str(_norm(b1)).is_equal(_norm(b2))
	assert_int(b1.size()).is_between(2, 3)
	for o: Dictionary in b1:
		assert_str(String(o["text"])).contains("pays")
		assert_int(int(o["reward"])).is_greater(0)
	assert_str(_norm(w.board(0, "farmer", 11))).is_not_equal(_norm(b1))
	# A good finished shift fills the first order and pays its reward.
	w.begin("farmer", 0, 10, "spring", 8.0)
	var r := _run(w, 1.0)
	assert_bool((r["order"] as Dictionary).is_empty()).is_false()


func test_comment_reflects_quality_and_uses_employer() -> void:
	var w := _w()
	var great: String = w.comment("guard", 0.95, 0, 4, "Captain Vale")
	var poor: String = w.comment("guard", 0.1, 0, 4, "Captain Vale")
	assert_str(great).contains("Captain Vale")
	assert_str(great).is_not_equal(poor)
	assert_str(w.coworker(0, "guard", 4)).is_not_empty()


func test_determinism_same_choices_same_outcome() -> void:
	var a: RefCounted = _w()
	var b: RefCounted = _w()
	a.begin("hunter", 0, 33, "autumn", 8.0)
	b.begin("hunter", 0, 33, "autumn", 8.0)
	var ra := _run(a, 0.7)
	var rb := _run(b, 0.7)
	assert_str(_norm(ra)).is_equal(_norm(rb))


func test_walking_off_counts_as_failed() -> void:
	var w := _w()
	w.begin("fisher", 0, 5, "summer", 6.0)
	w.resolve_task(1.0)
	var r: Dictionary = w.abandon()
	assert_float(float(r["quality"])).is_less(0.4)
	assert_bool(w.on_shift()).is_false()


func test_round_trip_mid_shift() -> void:
	var a: RefCounted = _w()
	a.begin("guard", 0, 8, "winter", 9.0)
	a.resolve_task(0.8, 0)
	a.standing["Sergeant Hale"] = 61.0
	a.last_done["baker"] = 7
	var blob: Variant = JSON.parse_string(JSON.stringify(a.serialize()))
	var b: RefCounted = _w()
	b.deserialize(blob)
	assert_str(_norm(b.serialize())).is_equal(_norm(a.serialize()))
	assert_int(int(b.shift["step"])).is_equal(1)
	# Either the next task or an open problem is waiting, exactly as before saving.
	assert_bool(b.current_task().is_empty()).is_equal(a.current_task().is_empty())
	assert_str(_norm(b.pending_problem())).is_equal(_norm(a.pending_problem()))
	var ra := _run(a, 0.8)
	var rb := _run(b, 0.8)
	assert_str(_norm(ra)).is_equal(_norm(rb))


func test_hub_registers_module_and_day_tick_closes_stale_shift() -> void:
	var hub: RefCounted = Hub.new()
	assert_bool(hub.mod("work") != null).is_true()
	assert_bool("work" in hub.ORDER).is_true()
	var w: RefCounted = hub.mod("work")
	w.mastery_ref = Mastery.new()
	w.begin("laborer", 0, 4, "spring", 8.0)
	w.tick_day(5, {})
	assert_bool(w.on_shift()).is_false()
	assert_int(int(w.last_done["laborer"])).is_equal(4)
	hub.serialize()


func test_perf_layout_and_task_resolution() -> void:
	var w := _w()
	var t0 := Time.get_ticks_usec()
	for sid in mini(WorldGen.settlements.size(), 12):
		w.workplaces(sid)
	var layout_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_float(layout_ms).is_less(60.0)
	var pa: Array = w.workplaces(0)
	t0 = Time.get_ticks_usec()
	for i in 2000:
		w.workplace_at(Vector2(float(i), 5.0), 0)
	assert_float(float(Time.get_ticks_usec() - t0) / 1000.0).is_less(80.0)
	t0 = Time.get_ticks_usec()
	for day in 100:
		w.begin("baker", 0, 100 + day, "summer", 6.0)
		_run(w, 0.7)
	assert_float(float(Time.get_ticks_usec() - t0) / 1000.0).is_less(300.0)
	assert_int(pa.size()).is_equal(15)
