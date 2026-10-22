extends GdUnitTestSuite
## CIV-A people on the move (realm/migration.gd): waves along roads over days, refugee camps, districts and quarters, cultural exchange,
## specialist masters, determinism, catch_up, save round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const DAY_MODS := ["settlements", "camps", "civilization", "migration", "construction"]


func _ctx(at_war := false) -> Dictionary:
	return {"season": "summer", "at_war": at_war, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk() -> RefCounted:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = Hub.new()
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	rs.add_stone(WorldGen.settlements[0]["pos"], 140.0, 0, "Ashford Ring")   # as Frontier rings the home village
	hub.mod("civilization").runestones = rs
	hub.mod("civilization")._ensure()
	hub.mod("migration")._ensure()
	for n in hub.mod("civilization").place_ids():
		hub.mod("civilization").no_finds[n] = true
	return hub


func _run(hub: RefCounted, from_day: int, n: int, at_war := false) -> void:
	var ctx := _ctx(at_war)
	for d in range(from_day, from_day + n):
		hub.mod("civilization").runestones.tick_day(d)
		for k: String in DAY_MODS:
			hub.mod(k).tick_day(d, ctx)


# ------------------------------------------------------------------ waves

func _in_flight(mig: RefCounted, id: int) -> bool:
	return mig.active_waves().any(func(w: Dictionary) -> bool: return int(w["id"]) == id)


func test_a_wave_leaves_walks_for_days_and_arrives() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	var from_pop: int = civ.population("s1")
	var w: Dictionary = mig.send_wave("s1", "s6", 30, "settlers", "test", "native", 10)
	assert_bool(w.is_empty()).is_false()
	assert_int(civ.population("s1")).is_less(from_pop)
	assert_int(int(w["arrive"]) - int(w["depart"])).is_greater_equal(2)
	assert_bool(_in_flight(mig, int(w["id"]))).is_true()
	assert_bool(mig.waves_to("s6").any(func(x: Dictionary) -> bool: return int(x["id"]) == int(w["id"]))).is_true()
	assert_float(mig.wave_progress(w, 11)).is_between(0.0, 0.99)
	var to_pop: int = civ.population("s6")
	# nobody has arrived yet on day 11
	for c: Callable in mig.tick_day_chunks(11, _ctx()):
		c.call()
	assert_bool(_in_flight(mig, int(w["id"]))).is_true()
	for c: Callable in mig.tick_day_chunks(int(w["arrive"]), _ctx()):
		c.call()
	assert_bool(_in_flight(mig, int(w["id"]))).is_false()
	assert_bool(civ.population("s6") >= to_pop).is_true()
	assert_bool(mig.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "arrival")).is_true()


func test_waves_are_pooled_to_sixteen_and_need_a_road() -> void:
	var hub := _mk()
	var mig: RefCounted = hub.mod("migration")
	var sent := 0
	for i in 24:
		if not mig.send_wave("s1", "s6" if i % 2 == 0 else "s5", 5, "settlers", "", "native", 3).is_empty():
			sent += 1
	assert_int(sent).is_equal(mig.MAX_WAVES)
	assert_int(mig.active_waves().size()).is_equal(mig.MAX_WAVES)
	# a place the world forgot cannot be reached
	var hub2 := _mk()
	hub2.mod("civilization").isolate("s6", 999)
	assert_bool(hub2.mod("migration").send_wave("s1", "s6", 5).is_empty()).is_true()


func test_trouble_pushes_people_out_in_a_wave_with_a_cause() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	# monsters keep hitting Stonehollow (s3), a busy neighbour has room
	var pop0: int = civ.population("s3")
	var causes := {}
	for d in range(1, 150):
		civ.add_pressure("s3", "monster", 0.05)
		civ.add_pressure("s3", "law", 0.004)
		_run(hub, d, 1)
		for w: Dictionary in mig.active_waves():
			if w["from"] == "s3":
				causes[w["cause"]] = true
	assert_bool(causes.size() > 0).is_true()
	assert_int(civ.population("s3")).is_less(pop0)
	assert_bool(causes.has("monsters") or causes.has("hard times") or causes.has("war")).is_true()


func test_boom_draws_inflow_waves_from_outside() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	civ.no_finds.erase("s5")
	civ.discover("s5", "rift_crystal", 0.9, 1)
	var before: int = int(mig.stats()["waves"])
	_run(hub, 1, 120)
	assert_int(int(mig.stats()["waves"])).is_greater(before)
	assert_bool(mig.news_events().size() > 0).is_true()


func test_overflow_waits_in_a_refugee_camp_and_is_taken_in_as_housing_grows() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	var w: Dictionary = mig.send_wave("s1", "s18", 120, "refugees", "war", "refugee", 5)   # Emberfall, a tiny village
	assert_bool(w.is_empty()).is_false()
	for c: Callable in mig.tick_day_chunks(int(w["arrive"]), _ctx()):
		c.call()
	assert_int(mig.refugees_at("s18")).is_greater(20)
	assert_bool(mig.refugee_camps().any(func(r: Dictionary) -> bool: return r["node"] == "s18")).is_true()
	assert_int(int(civ.place("s18")["refugees"])).is_greater(20)
	var camp0: int = mig.refugees_at("s18")
	civ.place("s18")["housing"] = float(civ.place("s18")["housing"]) + 400.0
	_run(hub, 6, 120)
	assert_int(mig.refugees_at("s18")).is_less(camp0)


# ------------------------------------------------------------------ districts, quarters, exchange

func test_culture_shares_per_district_and_a_quarter_forms_from_sustained_inflow() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	var ds: Array = mig.districts("s5")
	assert_int(ds.size()).is_greater_equal(2)
	var shares: Dictionary = mig.culture_shares("s5")
	assert_float(float(shares.get("native", 0.0))).is_greater(0.8)
	var total := 0.0
	for c: String in shares:
		total += float(shares[c])
	assert_float(total).is_equal_approx(1.0, 0.02)
	civ.place("s5")["housing"] = float(civ.place("s5")["housing"]) + 500.0
	for week in 10:
		mig._absorb("s5", "sunreach", 70)
		civ.add_people("s5", 70, "merchant", week)
		mig._eval_place("s5", 7 * week + 7, 1.0)
	var q: Array = mig.quarters("s5")
	assert_array(q).is_not_empty()
	assert_str(q[0]["quarter"]).is_equal("sunreach")
	assert_str(q[0]["name"]).contains("Sunreach")
	assert_bool(mig.is_mixed("s5")).is_true()
	assert_bool(mig.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "quarter")).is_true()


func test_cultural_exchange_adds_foods_clothes_and_festivals() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	civ.place("s5")["housing"] = 5000.0
	mig._absorb("s5", "frostmark", 600)
	civ.add_people("s5", 600, "", 1)
	for week in range(1, 90):
		mig._eval_place("s5", 7 * week, 1.0)
	var kinds := {}
	for t: Dictionary in mig.traditions("s5"):
		kinds[t["kind"]] = true
		assert_str(t["from"]).is_equal("frostmark")
	assert_bool(kinds.has("food")).is_true()
	assert_bool(kinds.has("clothes")).is_true()
	assert_bool(kinds.has("festival")).is_true()


# ------------------------------------------------------------------ specialists

func test_famous_place_attracts_a_named_master_and_the_cap_holds() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	# Stonehollow (s3) is a mining village: fame in smithing
	var cd: Dictionary = mig._cult["s3"]
	cd["fame"]["smith"] = 0.9
	var day := 1
	while mig.specialists("s3").is_empty() and day < 400:
		mig._eval_place("s3", day, 1.0)
		day += 7
	var ms: Array = mig.specialists("s3")
	assert_array(ms).is_not_empty()
	assert_str(ms[0]["field"]).is_equal("smith")
	assert_str(ms[0]["name"]).contains("Master Smith")
	assert_str(ms[0]["state"]).is_equal("travelling")
	for c: Callable in mig.tick_day_chunks(int(ms[0]["arrive"]), _ctx()):
		c.call()
	assert_str(mig.specialists("s3")[0]["state"]).is_equal("settled")
	assert_float(mig.master_bonus("s3", "smith")).is_greater(0.0)
	assert_int(mig.master_count("s3")).is_equal(1)
	# the region never holds more than the cap
	for n in civ.place_ids():
		for f: String in mig.FIELDS:
			mig._ensure_place(n)
			mig._cult[n]["fame"][f] = 0.95
	for w in range(1, 120):
		for n in civ.place_ids():
			mig._eval_place(n, 7 * w, 1.0)
	assert_int(mig.specialists().size()).is_less_equal(mig.MAX_SPECIALISTS)


func test_masters_leave_a_place_that_falls() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mig: RefCounted = hub.mod("migration")
	mig._spec.append({"id": 99, "name": "Master Smith Test", "field": "smith", "at": "s3", "from": "", "state": "settled", "arrive": 1, "left_day": 99999, "age0": 40})
	mig._mc_dirty = true
	assert_int(mig.master_count("s3")).is_equal(1)
	civ.place("s3")["ruin"] = true
	for c: Callable in mig.tick_day_chunks(10, _ctx()):
		c.call()
	assert_int(mig.master_count("s3")).is_equal(0)
	assert_bool(mig.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "master_left")).is_true()


# ------------------------------------------------------------------ determinism, catch_up, save, cost

func test_same_seed_same_migration() -> void:
	var a := _mk()
	var b := _mk()
	for h: RefCounted in [a, b]:
		h.mod("civilization").discover("s5", "iron", 0.9, 1)
		_run(h, 1, 200)
	assert_str(_norm(a.mod("migration").serialize())).is_equal(_norm(b.mod("migration").serialize()))
	assert_str(_norm(a.mod("civilization").serialize())).is_equal(_norm(b.mod("civilization").serialize()))


func test_catch_up_lands_waves_and_is_close_to_day_by_day() -> void:
	var a := _mk()
	var b := _mk()
	for h: RefCounted in [a, b]:
		h.mod("civilization").discover("s5", "iron", 0.9, 1)
		h.mod("migration").send_wave("s1", "s6", 40, "settlers", "", "native", 1)
	_run(a, 1, 120)
	for k: String in DAY_MODS:
		b.mod(k).catch_up(120, _ctx())
	assert_int(b.mod("migration").active_waves().size()).is_less_equal(a.mod("migration").active_waves().size() + 2)
	var wa: int = a.mod("migration").stats()["waves"]
	var wb: int = b.mod("migration").stats()["waves"]
	assert_bool(wb >= 1).is_true()
	assert_float(float(wb + 1) / float(wa + 1)).is_between(0.3, 3.0)
	var pa := 0
	var pb := 0
	for n in a.mod("civilization").place_ids():
		pa += a.mod("civilization").population(n)
		pb += b.mod("civilization").population(n)
	assert_float(float(pb) / float(pa)).is_between(0.85, 1.15)
	# and a digest in plain words
	for l in b.mod("migration").digest():
		assert_str(String(l)).is_not_empty()


func test_save_round_trip_with_waves_in_flight() -> void:
	var a := _mk()
	a.mod("civilization").discover("s5", "iron", 0.9, 1)
	_run(a, 1, 90)
	a.mod("migration").send_wave("s1", "s6", 20, "settlers", "", "native", 90)
	assert_bool(a.mod("migration").active_waves().size() > 0).is_true()
	var saved: Variant = JSON.parse_string(JSON.stringify(a.serialize()))
	var b := _mk()
	b.deserialize(saved)
	assert_str(_norm(b.mod("migration").serialize())).is_equal(_norm(a.mod("migration").serialize()))
	# both continue from the same JSON-rounded state (a float survives a save to its 15th digit only)
	var net: Variant = JSON.parse_string(JSON.stringify(a.mod("civilization").runestones.serialize()))
	a.deserialize(saved)
	for h: RefCounted in [a, b]:
		var rs2 := RARunestoneNetwork.new()
		rs2.deserialize(net)
		h.mod("civilization").runestones = rs2
	_run(a, 91, 20)
	_run(b, 91, 20)
	assert_str(_norm(b.mod("migration").serialize())).is_equal(_norm(a.mod("migration").serialize()))


func test_migration_save_is_small_after_two_years() -> void:
	var hub := _mk()
	hub.mod("civilization").discover("s5", "iron", 0.9, 1)
	_run(hub, 1, 730)
	assert_int(JSON.stringify(hub.mod("migration").serialize()).length()).is_less(80000)
	assert_int(hub.mod("migration").active_waves().size()).is_less_equal(hub.mod("migration").MAX_WAVES)
	assert_int(hub.mod("migration").news_events().size()).is_less_equal(hub.mod("migration").MAX_NEWS)


func test_migration_jobs_are_cheap() -> void:
	var hub := _mk()
	hub.mod("civilization").discover("s5", "iron", 0.9, 1)
	_run(hub, 1, 60)
	var times: Array = []
	for d in range(61, 181):
		var ctx := _ctx()
		hub.mod("civilization").runestones.tick_day(d)
		for k: String in ["settlements", "camps", "civilization"]:
			hub.mod(k).tick_day(d, ctx)
		for c: Callable in hub.mod("migration").tick_day_chunks(d, ctx):
			var t0 := Time.get_ticks_usec()
			c.call()
			times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var median: int = times[times.size() / 2]
	var p95: int = times[int(times.size() * 0.95)]
	prints("migration pump job us: median", median, "p95", p95, "max", times[-1], "jobs", times.size())
	assert_int(median).is_less(600)
	assert_int(p95).is_less(3000)
