extends GdUnitTestSuite
## CIV-A settlement lifecycle (realm/civilization.gd): tiers with hysteresis, housing/food/jobs pressure, boom and decline, NPC development
## projects as staged construction sites, dynamic founding, determinism, catch_up, save round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const DAY_MODS := ["settlements", "camps", "civilization", "migration", "construction"]


class FakeEco:
	extends RefCounted
	var civ_price_mult := {}


class FakeLife:
	extends RefCounted
	var economy := FakeEco.new()


func _ctx(at_war := false, life: Variant = null) -> Dictionary:
	return {"season": "summer", "at_war": at_war, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": life}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


## A hub with the modules civilization reads, its own runestone network (set before seeding so static places calibrate against it).
func _mk() -> RefCounted:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = Hub.new()
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	rs.add_stone(WorldGen.settlements[0]["pos"], 140.0, 0, "Ashford Ring")   # as Frontier rings the home village
	hub.mod("civilization").runestones = rs
	hub.mod("civilization")._ensure()
	hub.mod("migration")._ensure()
	return hub


func _tick(hub: RefCounted, day: int, at_war := false) -> void:
	var ctx := _ctx(at_war)
	hub.mod("civilization").runestones.tick_day(day)
	for k: String in DAY_MODS:
		hub.mod(k).tick_day(day, ctx)


func _run(hub: RefCounted, from_day: int, n: int, at_war := false) -> void:
	for d in range(from_day, from_day + n):
		_tick(hub, d, at_war)


## A frontier camp between Ashford and Oakvale (a dirt road), like docs/balance/data/civ_sim.gd.
func _camp(hub: RefCounted, day := 0) -> String:
	var civ: RefCounted = hub.mod("civilization")
	var a: Vector2 = WorldGen.settlements[0]["pos"]
	var b: Vector2 = WorldGen.settlements[8]["pos"]
	for t in [0.5, 0.45, 0.55, 0.4, 0.6, 0.35]:
		for lat in [70.0, -70.0, 120.0, -120.0]:
			var node: String = civ.found_place(a.lerp(b, t) + (b - a).normalized().orthogonal() * lat, "Ironwatch", "a prospector and her crew", day, 12)
			if node != "":
				return node
	return ""


func _pop_sum(civ: RefCounted) -> int:
	var t := 0
	for n in civ.place_ids():
		t += civ.population(n)
	return t


# ------------------------------------------------------------------ seeding and getters

func test_static_settlements_are_places_with_tiers_and_pressures() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	assert_int(civ.place_ids().size()).is_equal(WorldGen.settlements.size())
	assert_str(civ.tier_name("s1")).is_equal("city")              # the castle
	assert_str(civ.tier_name("s0")).is_equal("village")
	for n in ["s0", "s1", "s5"]:
		var pr: Dictionary = civ.pressures(n)
		for k in ["housing", "food", "jobs", "safety", "roads", "attraction", "unrest", "crime"]:
			assert_bool(pr.has(k)).is_true()
		assert_float(pr["housing"]).is_between(0.5, 2.0)
	var info: Dictionary = civ.info("s5")
	assert_str(info["name"]).is_equal(WorldGen.settlements[5]["name"])
	assert_int(info["pop"]).is_equal(civ.population("s5"))


func test_hub_registration_orders_civilization_after_camps_and_before_construction() -> void:
	var order: Array = Hub.ORDER
	assert_bool(order.has("civilization") and order.has("migration")).is_true()
	assert_bool(order.find("civilization") > order.find("settlements") and order.find("civilization") > order.find("camps")).is_true()
	assert_bool(order.find("migration") > order.find("civilization")).is_true()
	assert_bool(order.find("civilization") < order.find("construction")).is_true()


func test_static_places_are_stable_without_events() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	for n in civ.place_ids():
		civ.no_finds[n] = true
	var before := _pop_sum(civ)
	_run(hub, 1, 60)
	var after := _pop_sum(civ)
	assert_float(float(after) / float(before)).is_between(0.85, 1.25)


# ------------------------------------------------------------------ dynamic founding, boom, growth

func test_found_place_makes_a_camp_that_is_on_the_road_graph() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var node := _camp(hub)
	assert_str(node).starts_with("c")
	assert_str(civ.tier_name(node)).is_equal("camp")
	assert_int(civ.dynamic_count()).is_equal(1)
	assert_int(hub.mod("camps").camps().size()).is_equal(1)
	assert_bool(hub.mod("camps").has_node_id(node)).is_true()
	assert_array(civ.chronicle(node)).is_not_empty()


func test_dynamic_founding_is_capped() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var made := 0
	for i in 40:
		var pos := Vector2(-3000 + 160 * (i % 12), -2500 + 420 * (i / 12))
		if civ.found_place(pos, "", "", 0, 10) != "":
			made += 1
	assert_int(civ.dynamic_count()).is_less_equal(civ.DYNAMIC_CAP)
	assert_int(made).is_less_equal(civ.DYNAMIC_CAP)


func test_discovery_makes_a_boom_and_a_camp_grows_into_a_town() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	civ.no_finds["s8"] = true
	var node := _camp(hub)
	var pop0: int = civ.population(node)
	_run(hub, 1, 29)
	civ.discover(node, "iron", 0.85, 30)
	assert_float(civ.boom_of(node, 30)["power"]).is_greater(0.4)
	assert_array(civ.deposits(node)).has_size(1)
	_run(hub, 30, 700)
	assert_int(civ.population(node)).is_greater(pop0 * 4)
	assert_int(civ.tier(node)).is_greater_equal(1)
	# the mine got built (an NPC project) and opened the deposit
	assert_bool(bool(civ.deposits(node)[0]["dev"])).is_true()
	assert_bool(civ.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "boom")).is_true()
	assert_bool(hub.mod("migration").stats()["waves"] > 0).is_true()


func test_safety_comes_from_the_runestone_network() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var node := _camp(hub)
	_run(hub, 1, 4)
	var s0: float = civ.pressures(node)["safety"]
	var rs: RARunestoneNetwork = civ.runestones
	rs.add_stone(civ.pos_of(node), 140.0, -1, "Test Stone")
	_run(hub, 5, 8)
	assert_float(civ.pressures(node)["safety"]).is_greater(s0 + 0.25)


# ------------------------------------------------------------------ tiers: hysteresis, decline, ruin

func test_tier_promotion_needs_time_and_demotion_has_hysteresis() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var node := _camp(hub)
	var p: Dictionary = civ.place(node)
	civ.runestones.add_stone(civ.pos_of(node), 140.0, -1, "Test Stone")
	p["popf"] = 130.0
	p["housing"] = 400.0
	p["jobs"] = 400.0
	p["farms"] = 6
	assert_int(civ.tier(node)).is_equal(0)
	_run(hub, 1, 12)
	assert_int(civ.tier(node)).is_less_equal(1)        # not yet: 20 days of it first (and outpost before village)
	_run(hub, 13, 80)
	assert_int(civ.tier(node)).is_greater_equal(2)
	# just under the threshold of the tier it holds: no flicker
	var t: int = civ.tier(node)
	p["popf"] = float(civ.TIER_POP[t]) * 0.9
	p["housing"] = 1000.0
	var tier_before := t
	_run(hub, 100, 40)
	assert_int(civ.tier(node)).is_equal(tier_before)


func test_cut_off_mining_town_shrinks_and_a_connected_one_does_not() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var mines: Array = []
	for n in civ.place_ids():
		if not (civ.place(n)["res"] as Array).is_empty():
			mines.append(n)
		civ.no_finds[n] = true
	assert_bool(mines.size() >= 2).is_true()
	var cut: String = mines[0]
	var free: String = mines[1]
	var pc0: int = civ.population(cut)
	var pf0: int = civ.population(free)
	assert_int(civ.isolate(cut, 99999)).is_greater(0)
	_run(hub, 1, 450)
	assert_bool(civ.pressures(cut)["cut_off"]).is_true()
	assert_int(civ.population(cut)).is_less(int(pc0 * 0.9))
	assert_int(civ.population(free)).is_greater(int(pf0 * 0.8))


func test_exhausted_deposit_removes_the_mine_jobs_and_is_reported() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var stl: RefCounted = hub.mod("settlements")
	var mine := ""
	for n in civ.place_ids():
		civ.no_finds[n] = true
		if mine == "" and not (civ.place(n)["res"] as Array).is_empty():
			mine = n
	var dep: Dictionary = civ.place(mine)["res"][0]
	var chains_before: int = stl.chains(int(mine.substr(1))).get("mine", 0)
	dep["reserve"] = 40.0
	var jobs_before: float = civ.pressures(mine)["jobs"]
	_run(hub, 1, 30)
	assert_float(dep["reserve"]).is_equal(0.0)
	assert_bool(bool(dep["dev"])).is_false()
	assert_int(stl.chains(int(mine.substr(1))).get("mine", 0)).is_less(maxi(chains_before, 1))
	assert_float(civ.pressures(mine)["jobs"]).is_less(jobs_before)
	assert_bool(civ.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "depleted")).is_true()


func test_dying_camp_becomes_a_ruin_and_stays_as_a_landmark() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var node := _camp(hub)
	civ.place(node)["popf"] = 4.0
	civ.place(node)["housing"] = 4.0
	civ.place(node)["jobs"] = 1.0
	_run(hub, 1, 90)
	assert_bool(civ.is_ruin(node)).is_true()
	assert_str(civ.tier_name(node)).is_equal("ruin")
	assert_int(civ.population(node)).is_equal(0)
	assert_bool(civ.ruins().any(func(r: Dictionary) -> bool: return r["node"] == node)).is_true()
	assert_bool(civ.news_events().any(func(e: Dictionary) -> bool: return e["kind"] == "ruin")).is_true()


func test_route_loss_and_failing_stones_lower_attraction() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	civ.no_finds["s0"] = true
	_run(hub, 1, 8)
	var a0: float = civ.pressures("s0")["attraction"]
	# the stones around Ashford go dark
	for s: Dictionary in (civ.runestones as RARunestoneNetwork).stones:
		if s["pos"].distance_to(WorldGen.settlements[0]["pos"]) < 400.0:
			s["condition"] = 0.0
	_run(hub, 9, 10)
	assert_float(civ.pressures("s0")["safety"]).is_less(0.3)
	assert_float(civ.pressures("s0")["attraction"]).is_less(a0)


# ------------------------------------------------------------------ NPC development projects as staged construction sites

func test_projects_are_queued_by_need_and_run_as_staged_npc_sites() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var cons: RefCounted = hub.mod("construction")
	var node := _camp(hub)
	civ.discover(node, "iron", 0.85, 1)
	var built_before: int = cons.count_built("timber_house")
	var seen_stages := {}
	for d in range(1, 400):
		_tick(hub, d)
		for s: Dictionary in cons.npc_sites(node):
			seen_stages[cons.site_info(int(s["id"]))["stage"]] = true
	var sites: Array = cons.npc_sites(node)
	assert_array(sites).is_not_empty()
	assert_bool(civ.projects(node).any(func(pr: Dictionary) -> bool: return pr["state"] == "done")).is_true()
	assert_bool(seen_stages.has("foundation") or seen_stages.has("frame") or seen_stages.has("walls")).is_true()
	# the player's unlocks, upkeep and levels never see them
	assert_int(cons.count_built("timber_house")).is_equal(built_before)
	assert_int(cons.tier_built(1)).is_equal(0)
	for s: Dictionary in sites:
		assert_bool(bool(s["npc"])).is_true()
		assert_int(int(s["holding"])).is_equal(0)


func test_npc_site_progress_is_a_function_of_the_day_and_finishes() -> void:
	var hub := _mk()
	var cons: RefCounted = hub.mod("construction")
	var id: int = cons.npc_place("hut", Vector2(10, 10), 0.0, 10.0, "test", "s0")
	assert_int(id).is_greater(0)
	assert_str(cons.npc_set_progress(id, 0.5)).is_equal("walls")
	cons.npc_set_progress(id, 0.2)                                 # never backwards
	assert_float(cons.site_info(id)["pct"]).is_equal_approx(0.5, 0.001)
	cons.advance(14, {})                                           # the crew loop leaves NPC sites alone
	assert_float(cons.site_info(id)["pct"]).is_equal_approx(0.5, 0.001)
	cons.npc_finish(id)
	assert_str(cons.site_info(id)["state"]).is_equal("done")
	assert_int(cons.npc_prune(0)).is_equal(1)
	assert_bool(cons.sites.has(id)).is_false()


# ------------------------------------------------------------------ news, digest, economy hook

func test_news_events_and_digest() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var node := _camp(hub)
	civ.discover(node, "iron", 0.8, 2)
	var lines: Array = civ.catch_up(120, _ctx())
	assert_bool(lines is Array).is_true()
	var evs: Array = civ.news_events()
	assert_array(evs).is_not_empty()
	for e: Dictionary in evs:
		for k in ["id", "day", "kind", "node", "name", "text"]:
			assert_bool(e.has(k)).is_true()
	assert_int(civ.news_since(int(evs[0]["id"])).size()).is_equal(evs.size() - 1)
	assert_int(lines.size()).is_less_equal(8)


func test_economy_price_multiplier_follows_boom_and_isolation() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	var life := FakeLife.new()
	civ.discover("s5", "iron", 0.9, 1)
	civ.isolate("s6", 9999)
	civ.place("s6")["cut"] = 90.0
	civ._day = 2
	civ._push_prices(_ctx(false, life))
	assert_float(float(life.economy.civ_price_mult.get(5, 1.0))).is_greater(1.05)
	assert_float(float(life.economy.civ_price_mult.get(6, 1.0))).is_greater(1.1)
	assert_bool(life.economy.civ_price_mult.has(0)).is_false()


# ------------------------------------------------------------------ determinism, catch_up, save

func test_same_seed_same_chronicle() -> void:
	var a := _mk()
	var b := _mk()
	for h: RefCounted in [a, b]:
		_camp(h)
		h.mod("civilization").discover("c1", "iron", 0.8, 3)
		_run(h, 1, 240)
	assert_str(_norm(a.mod("civilization").serialize())).is_equal(_norm(b.mod("civilization").serialize()))
	assert_str(_norm(a.mod("migration").serialize())).is_equal(_norm(b.mod("migration").serialize()))


func test_chunked_day_tick_equals_direct_tick() -> void:
	var a := _mk()
	var b := _mk()
	for h: RefCounted in [a, b]:
		_camp(h)
		h.mod("civilization").discover("c1", "iron", 0.8, 3)
	for d in range(1, 40):
		a.mod("civilization").tick_day(d, _ctx())
		for c: Callable in b.mod("civilization").tick_day_chunks(d, _ctx()):
			c.call()
	assert_str(_norm(a.mod("civilization").serialize())).is_equal(_norm(b.mod("civilization").serialize()))


func test_catch_up_is_close_to_day_by_day() -> void:
	var a := _mk()
	var b := _mk()
	var na := _camp(a)
	var nb := _camp(b)
	for h: RefCounted in [a, b]:
		for n in h.mod("civilization").place_ids():
			h.mod("civilization").no_finds[n] = true
		h.mod("civilization").discover("c1", "iron", 0.8, 1)
	_run(a, 1, 150)
	# b sleeps the same 150 days through catch_up (everything it depends on, in hub order)
	for k: String in ["settlements", "camps", "civilization", "migration", "construction"]:
		b.mod(k).catch_up(150, _ctx())
	var ca: RefCounted = a.mod("civilization")
	var cb: RefCounted = b.mod("civilization")
	assert_float(float(cb.population(nb)) / maxf(1.0, float(ca.population(na)))).is_between(0.5, 2.0)
	assert_float(float(_pop_sum(cb)) / float(_pop_sum(ca))).is_between(0.85, 1.15)
	var tier_gap := 0
	for n in ca.place_ids():
		if cb.has_place(n):
			tier_gap += absi(ca.tier(n) - cb.tier(n))
	assert_int(tier_gap).is_less_equal(4)
	assert_bool(cb.deposits(nb).size() == ca.deposits(na).size()).is_true()


func test_catch_up_is_not_a_loop_over_days() -> void:
	var hub := _mk()
	var civ: RefCounted = hub.mod("civilization")
	civ.catch_up(2, _ctx())                                 # warm caches
	var t0 := Time.get_ticks_usec()
	civ.catch_up(120, _ctx())
	var short_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	civ.catch_up(3650, _ctx())
	var long_us := Time.get_ticks_usec() - t0
	prints("civ catch_up us: 120 days", short_us, " 3650 days", long_us)
	# thirty times the days costs about what a dozen steps cost, not thirty times more (a noisy CI gets slack)
	assert_int(long_us).is_less(maxi(6 * short_us, 150000))
	assert_int(civ.place_ids().size()).is_greater_equal(WorldGen.settlements.size())


func test_save_round_trip_and_continue() -> void:
	var a := _mk()
	_camp(a)
	a.mod("civilization").discover("c1", "iron", 0.8, 3)
	_run(a, 1, 200)
	var saved: Variant = JSON.parse_string(JSON.stringify(a.serialize()))
	var b := _mk()
	b.deserialize(saved)
	assert_str(_norm(b.mod("civilization").serialize())).is_equal(_norm(a.mod("civilization").serialize()))
	assert_str(_norm(b.mod("migration").serialize())).is_equal(_norm(a.mod("migration").serialize()))
	# both continue from the same JSON-rounded state (a float survives a save to its 15th digit only)
	var net: Variant = JSON.parse_string(JSON.stringify(a.mod("civilization").runestones.serialize()))
	a.deserialize(saved)
	for h: RefCounted in [a, b]:
		var rs2 := RARunestoneNetwork.new()
		rs2.deserialize(net)
		h.mod("civilization").runestones = rs2
	_run(a, 201, 30)
	_run(b, 201, 30)
	assert_int(_pop_sum(b.mod("civilization"))).is_equal(_pop_sum(a.mod("civilization")))
	assert_int(b.mod("civilization").tier("c1")).is_equal(a.mod("civilization").tier("c1"))


func test_two_year_save_stays_small() -> void:
	var hub := _mk()
	_camp(hub)
	hub.mod("civilization").discover("c1", "iron", 0.9, 3)
	_run(hub, 1, 730)
	var bytes: int = JSON.stringify(hub.mod("civilization").serialize()).length() + JSON.stringify(hub.mod("migration").serialize()).length()
	assert_int(bytes).is_less(150000)
	# construction keeps only a bounded number of finished NPC buildings
	assert_int(hub.mod("construction").npc_sites().size()).is_less_equal(hub.mod("civilization").KEEP_DONE_SITES + 12)


# ------------------------------------------------------------------ cost

func test_each_pump_job_is_cheap() -> void:
	var hub := _mk()
	_camp(hub)
	hub.mod("civilization").discover("c1", "iron", 0.9, 1)
	_run(hub, 1, 60)
	var times: Array = []
	for d in range(61, 181):
		var ctx := _ctx()
		hub.mod("civilization").runestones.tick_day(d)
		for k: String in ["settlements", "camps"]:
			hub.mod(k).tick_day(d, ctx)
		for k: String in ["civilization", "migration"]:
			for c: Callable in hub.mod(k).tick_day_chunks(d, ctx):
				var t0 := Time.get_ticks_usec()
				c.call()
				times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var median: int = times[times.size() / 2]
	var p95: int = times[int(times.size() * 0.95)]
	prints("civ/migration pump job us: median", median, "p95", p95, "max", times[-1], "jobs", times.size())
	assert_int(median).is_less(600)       # design budget is 0.6 ms per job; CI is shared and slow
	assert_int(p95).is_less(3000)
