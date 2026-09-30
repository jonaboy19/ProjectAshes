extends GdUnitTestSuite
## Ward (scripts/region1/wardlines.gd): budget conservation, routing, cuts, glyphs,
## decay and repair, rumour events, determinism by seed, save/restore, network binding, cost.

const Ward := preload("res://scripts/region1/wardlines.gd")
const State := preload("res://scripts/region1/region1_state.gd")

## Two 6-stone roads, each hung on its own Elder Stone:
##   E0(id0) - A1..A6 (ids 1..6) along y = 0;   E1(id7) - B1..B6 (ids 8..13) along y = 600.
## The two roads are 600 m apart, so a player link A6-B6 (600 m) is legal (max_len 700).
func _mini(seed_value := 1, tweak := {}, slack := -1.0) -> Ward:
	var w := Ward.new()
	w.setup(seed_value)
	var c: Dictionary = w.cfg.duplicate(true)
	c["wear"]["failure_chance_per_day"] = 0.0
	c["crew"]["repairs_per_stone_day"] = 0.0
	for k in tweak:
		c[k] = tweak[k]
	if slack > 0.0:
		c["elder"]["slack"] = slack
	w.configure(c)
	var stones: Array = []
	stones.append({"pos": Vector2(0, 0), "radius": 240.0, "name": "E0 Elder Stone", "owner": 0})
	for k in 6:
		stones.append({"pos": Vector2(180.0 * (k + 1), 0), "radius": 110.0, "name": "A%d" % (k + 1),
			"road": "A", "road_name": "Aldermere", "owner": 0})
	stones.append({"pos": Vector2(0, 600), "radius": 240.0, "name": "E1 Elder Stone", "owner": 1})
	for k in 6:
		stones.append({"pos": Vector2(180.0 * (k + 1), 600), "radius": 110.0, "name": "B%d" % (k + 1),
			"road": "B", "road_name": "Briarford", "owner": 1})
	var lk: Array = []
	for k in 6:
		lk.append([k, k + 1])          # E0-A1, A1-A2, ...
		lk.append([7 + k, 8 + k])      # E1-B1, B1-B2, ...
	w.set_layout(stones, PackedInt32Array([0, 7]), lk)
	return w


func _run(w: Ward, days: float, step := 0.5) -> void:
	var t := 0.0
	while t < days - 1e-9:
		w.tick(minf(step, days - t))
		t += step


func _events(w: Ward, kind: String) -> Array:
	return w.event_log.filter(func(e: Dictionary) -> bool: return e["kind"] == kind)


# --- conservation ---------------------------------------------------------------------

func _assert_books(w: Ward) -> void:
	var r := w.budget_report()
	assert_float(r["drawn"]).is_equal_approx(float(r["delivered"]) + float(r["loss"]), 1e-6)
	assert_float(r["drawn"]).is_less_equal(float(r["supply"]) + 1e-6)
	for row in w.elder_status():
		assert_float(row["drawn"]).is_less_equal(float(row["budget"]) + 1e-6)
	assert_float(r["loss"]).is_greater_equal(-1e-9)


func test_routing_conserves_budget_mini() -> void:
	var w := _mini()
	_assert_books(w)
	assert_float(w.budget_report()["loss"]).is_greater(0.0)   # hops waste power
	w.carve(3, "ward")
	_assert_books(w)
	w.drain_elder(0, 0.6)
	_assert_books(w)
	var e0: Dictionary = w.elder_status()[0]
	assert_float(e0["drawn"]).is_equal_approx(float(e0["budget"]), 1e-6)   # a dry Elder spends everything
	w.add_link(6, 13)
	w.cut_link(3, 4)
	_assert_books(w)


func test_routing_conserves_budget_on_valencious_layout() -> void:
	for seed_value in [1, 2, 3]:
		var w := Ward.new().setup(seed_value) as Ward
		assert_int(w.stone_count()).is_greater(60)
		_assert_books(w)
		_run(w, 30.0)
		_assert_books(w)
		w.cut_link(w.links[10]["a"], w.links[10]["b"])
		w.carve(w.nearest_stone(Vector2(60, 60)), "ward")
		_assert_books(w)


func test_fresh_network_is_fully_fed_with_spare_power() -> void:
	var w := Ward.new().setup(1) as Ward
	for i in w.stone_count():
		assert_float(w.fed[i]).is_equal_approx(1.0, 1e-6)
	var r := w.budget_report()
	assert_float(r["unspent"]).is_greater(0.0)          # slack for upgrades
	assert_float(r["unmet"]).is_equal_approx(0.0, 1e-6)


# --- routing behaviour ----------------------------------------------------------------

func test_cutting_a_link_drops_coverage_on_that_road_only() -> void:
	var w := _mini()
	var a0: float = w.road_coverage("A")["min"]
	var twin := _mini()
	_run(twin, 8.0)
	assert_float(a0).is_greater(0.3)          # spacing 180 m vs radius 110 m: overlapping, thin between stones
	assert_bool(w.cut_link(3, 4)).is_true()          # A3 | A4
	_run(w, 8.0)
	var a1: Dictionary = w.road_coverage("A")
	assert_float(a1["min"]).is_less(0.05)                        # the far half went dark
	assert_float(w.road_coverage("B")["min"]).is_equal_approx(twin.road_coverage("B")["min"], 1e-9)   # the other road is untouched
	assert_float(a1["min"]).is_less(twin.road_coverage("A")["min"] - 0.25)
	assert_float(w.coverage_at(Vector2(180.0 * 5, 0))).is_less(0.05)      # right where A5 stands
	assert_float(w.coverage_at(Vector2(180.0 * 2, 0))).is_greater(0.6)    # the fed half still shines
	assert_int(w.stone_band(5)).is_equal(Ward.BAND_DARK)
	assert_int(w.stone_band(1)).is_equal(Ward.BAND_GLOWING)


func test_fade_takes_days_not_instants_and_mending_relights() -> void:
	var w := _mini()
	w.cut_link(3, 4)
	w.tick(0.25)
	assert_float(w.stone_strength(5)).is_greater(0.8)     # barely moved
	_run(w, 8.0)
	assert_float(w.stone_strength(5)).is_less(0.05)
	assert_bool(w.mend_link(3, 4)).is_true()
	_run(w, 6.0)
	assert_float(w.stone_strength(5)).is_greater(0.9)


func test_player_link_reroutes_power_from_the_other_elder() -> void:
	var w := _mini(1, {}, 2.5)                       # Elder 1 has plenty of spare power
	assert_bool(w.add_link(6, 13)["ok"]).is_true()        # A6 - B6, 600 m
	w.cut_link(3, 4)
	_run(w, 8.0)
	# A4..A6 are now fed by Elder 1 through the player link, at a lossy price.
	assert_int(w.supplier[6]).is_equal(1)
	assert_float(w.stone_strength(5)).is_greater(0.8)
	assert_float(w.fed[4]).is_greater(0.95)
	_assert_books(w)
	# With the default 25 percent slack the far Elder can only half-feed the detour.
	var tight := _mini()
	tight.add_link(6, 13)
	tight.cut_link(3, 4)
	_run(tight, 8.0)
	assert_float(tight.fed[4]).is_less(0.6)
	assert_float(tight.fed[6]).is_greater(0.9)   # the detour feeds its nearest stone first


func test_nearest_first_starvation_and_pinning() -> void:
	var w := _mini()
	w.drain_elder(0, 0.72)                 # Elder 0 keeps 28 percent of its budget
	w.tick(0.01)
	assert_float(w.fed[1]).is_equal_approx(1.0, 1e-6)      # nearest stone is served first
	assert_float(w.fed[6]).is_less(0.05)                    # the far end is starved
	var fed3 := w.fed[3]
	w.set_pinned(6, true)
	assert_float(w.fed[6]).is_greater(0.9)                  # a pinned stone jumps the queue
	assert_float(w.fed[3]).is_less(fed3)                    # at somebody else's expense
	_assert_books(w)


func test_link_rules() -> void:
	var w := _mini()
	assert_str(w.add_link(1, 1)["reason"]).is_equal("bad_stones")
	assert_str(w.add_link(1, 2)["reason"]).is_equal("exists")
	assert_str(w.add_link(1, 13)["reason"]).is_equal("too_far")
	assert_bool(w.add_link(6, 13)["ok"]).is_true()
	assert_bool(w.add_link(5, 12)["ok"]).is_true()
	assert_bool(w.add_link(4, 11)["ok"]).is_true()
	assert_bool(w.add_link(3, 10)["ok"]).is_true()
	# A3 now has 3 links (A2, A4, B3'), max is 4: two more are fine, a third is not.
	assert_bool(w.add_link(3, 9)["ok"]).is_true()
	assert_str(w.add_link(3, 8)["reason"]).is_equal("too_many_links")
	assert_bool(w.cut_link(1, 1)).is_false()


# --- glyphs ---------------------------------------------------------------------------

func test_ward_glyph_widens_and_costs_more_power() -> void:
	var w := _mini()
	var probe := Vector2(540.0, 100.0)                  # 100 m beside A3: the plain bubble (110 m) barely reaches
	var before := w.coverage_at(probe)
	var drawn0: float = w.budget_report()["drawn"]
	var power0 := w.elder_power[0]
	var res := w.carve(3, "ward")
	assert_bool(res["ok"]).is_true()
	assert_float(w.elder_power[0]).is_less(power0)                       # the carving spent a breath
	assert_float(w.coverage_at(probe)).is_greater(before + 0.4)
	assert_float(w.budget_report()["drawn"]).is_greater(drawn0)           # and the stone is hungrier
	assert_str(w.glyph_name(3)).is_equal("ward")


func test_lure_makes_a_gap_and_is_cheap() -> void:
	var w := _mini()
	var drawn0: float = w.budget_report()["drawn"]
	assert_bool(w.carve(3, "lure")["ok"]).is_true()
	_run(w, 1.0)
	assert_float(w.coverage_at(w.st_pos[3])).is_less(0.1)                 # no ward at a lure
	assert_float(w.budget_report()["drawn"]).is_less(drawn0)
	var pts := w.lure_points()
	assert_int(pts.size()).is_equal(1)
	assert_int(pts[0]["id"]).is_equal(3)


func test_alarm_rings_only_near_and_off_cooldown() -> void:
	var w := _mini()
	w.carve(2, "alarm")
	assert_int(w.notify_threat(Vector2(360, 300))).is_equal(1)
	assert_int(w.notify_threat(Vector2(360, 300))).is_equal(0)            # cooldown
	w.tick(0.5)
	assert_int(w.notify_threat(Vector2(3000, 3000))).is_equal(0)          # out of earshot
	assert_int(_events(w, "alarm").size()).is_equal(1)


func test_bless_boosts_yield_near_the_stone() -> void:
	var w := _mini()
	assert_float(w.bless_at(w.st_pos[4])).is_equal_approx(1.0, 1e-9)
	w.carve(4, "bless")
	assert_float(w.bless_at(w.st_pos[4])).is_greater(1.15)
	assert_float(w.bless_at(Vector2(0, 3000))).is_equal_approx(1.0, 1e-9)


func test_carve_rules() -> void:
	var w := _mini()
	assert_str(w.carve(0, "ward")["reason"]).is_equal("elder_stone")
	assert_str(w.carve(3, "nonsense")["reason"]).is_equal("unknown_glyph")
	w.cut_link(3, 4)
	_run(w, 8.0)
	assert_str(w.carve(5, "ward")["reason"]).is_equal("too_dim")          # no spark left
	w.drain_elder(0, 0.99)
	assert_str(w.carve(1, "ward")["reason"]).is_equal("elder_spent")


# --- wear ----------------------------------------------------------------------------

func test_decay_neglect_and_repair() -> void:
	var w := _mini()
	_run(w, 10.0)
	var c10 := w.condition[3]
	assert_float(c10).is_less(1.0)
	_run(w, 30.0)                                   # past neglect_after_days: decay speeds up
	var c40 := w.condition[3]
	var slow: float = 40.0 * float(w.cfg["wear"]["decay_per_day"])
	assert_float(1.0 - c40).is_greater(slow)
	w.repair(3)
	assert_float(w.condition[3]).is_greater(c40 + 0.1)
	assert_float(w.last_repair[3]).is_equal_approx(w.day_f, 1e-6)
	_run(w, 5.0)
	assert_float(1.0 - w.condition[3]).is_less(1.0 - c40)   # neglect counter restarted


func test_crews_repair_the_weakest_fed_stone() -> void:
	var w := _mini(1, {})
	var c: Dictionary = w.cfg.duplicate(true)
	c["crew"]["repairs_per_stone_day"] = 0.2                # 14 stones -> 2.8 repairs a day
	w.configure(c)
	w.damage_stone(4, 0.6)
	_run(w, 3.0)
	assert_float(w.condition[4]).is_greater(0.7)


func test_random_failures_are_seeded_and_step_independent() -> void:
	var c := {}
	var a := _mini(4, c)
	var cf: Dictionary = a.cfg.duplicate(true)
	cf["wear"]["failure_chance_per_day"] = 0.2
	a.configure(cf)
	var b := _mini(4, c)
	b.configure(cf)
	_run(a, 20.0, 0.5)
	_run(b, 20.0, 1.0)
	assert_int(_events(a, "stone_failed").size()).is_equal(_events(b, "stone_failed").size())
	assert_int(_events(a, "stone_failed").size()).is_greater(0)


# --- rumours --------------------------------------------------------------------------

func test_rumours_on_change_only() -> void:
	var w := _mini()
	assert_int(w.rumours().size()).is_equal(0)
	w.cut_link(3, 4)
	assert_int(_events(w, "link_cut").size()).is_equal(1)
	_run(w, 8.0)
	var rum := _events(w, "road_rumour")
	assert_int(rum.size()).is_greater(0)
	assert_str(rum[rum.size() - 1]["data"]["rumour"]).contains("Aldermere")
	assert_int(_events(w, "stone_dark").size()).is_equal(3)              # A4, A5, A6
	assert_int(w.rumours().size()).is_equal(1)
	assert_str(w.rumours()[0]).contains("3 stones")
	var n_events := w.event_log.size()
	_run(w, 3.0)
	assert_int(w.event_log.size()).is_equal(n_events)                    # a stable state is silent
	w.mend_link(3, 4)
	_run(w, 8.0)
	assert_int(_events(w, "road_clear").size()).is_equal(1)
	assert_int(w.rumours().size()).is_equal(0)


func test_elder_strain_event() -> void:
	var w := _mini()
	w.drain_elder(0, 0.72)
	w.tick(0.1)
	assert_int(_events(w, "elder_strained").size()).is_equal(1)
	_run(w, 12.0)                                    # power recovers
	assert_int(_events(w, "elder_calm").size()).is_equal(1)


# --- determinism and saves ------------------------------------------------------------

func _scenario(seed_value: int) -> Ward:
	var w := Ward.new().setup(seed_value) as Ward
	_run(w, 12.0)
	w.cut_link(w.links[5]["a"], w.links[5]["b"])
	w.carve(w.nearest_stone(Vector2(20, 20)), "bless")
	_run(w, 25.0)
	return w


func test_same_seed_same_state() -> void:
	assert_str(_scenario(9).digest()).is_equal(_scenario(9).digest())


func test_different_seed_different_state() -> void:
	assert_str(_scenario(9).digest()).is_not_equal(_scenario(10).digest())


func test_save_restore_roundtrip_continues_identically() -> void:
	var a := _scenario(3)
	a.set_pinned(7, true)
	a.add_link(a.nearest_stone(Vector2(0, 0)), a.nearest_stone(Vector2(300, 100)))
	var text := JSON.stringify(a.serialize())
	var b := Ward.new()
	b.setup(3)
	b.deserialize(JSON.parse_string(text))
	assert_str(b.digest()).is_equal(a.digest())
	_run(a, 10.0)
	_run(b, 10.0)
	assert_str(b.digest()).is_equal(a.digest())
	assert_float(b.coverage_at(Vector2(100, 40))).is_equal_approx(a.coverage_at(Vector2(100, 40)), 1e-9)
	assert_int(b.links.size()).is_equal(a.links.size())


func test_restore_through_region1_state_and_empty_reset() -> void:
	State.clear()
	var a := _scenario(5)
	State.register_sim(a)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(State.snapshot()))
	var before := a.digest()
	_run(a, 10.0)
	assert_str(a.digest()).is_not_equal(before)
	State.restore(snap)
	assert_str(a.digest()).is_equal(before)
	State.restore({})                               # module missing from a save = defaults
	assert_int(a.stone_count()).is_greater(60)
	assert_int(a.glyph.count(Ward.G_BLESS)).is_equal(0)
	State.clear()


# --- network binding and hook H3 -------------------------------------------------------

func test_bind_network_matches_the_old_coverage_when_fresh() -> void:
	var net := RARunestoneNetwork.new()
	for k in 6:
		var ang := TAU * k / 6.0
		net.add_stone(Vector2(cos(ang), sin(ang)) * 80.0, 90.0, 0, "Ring %d" % k)
	for k in 8:
		var s := net.add_stone(Vector2(200.0 + 180.0 * k, 0), 110.0, 0, "Oakvale Road Stone %d" % (k + 1))
		s["road"] = true
		s["road_to"] = "Oakvale"
	var w := Ward.new().setup(1) as Ward
	w.bind_network(net, PackedInt32Array([0, 13]))
	assert_str(w.layout_source).is_equal("network")
	assert_int(w.stone_count()).is_equal(14)
	for p in [Vector2(0, 0), Vector2(250, 20), Vector2(700, 30), Vector2(1400, 0), Vector2(-90, 10)]:
		assert_float(w.coverage_at(p)).is_equal_approx(net.coverage(p), 1e-6)
	assert_bool(w.coverage_callable().is_valid()).is_true()
	assert_float(w.coverage_callable().call(Vector2(250, 20))).is_equal_approx(w.coverage_at(Vector2(250, 20)), 1e-9)
	# the road is one chain: a dead stone in the middle shows in the shared rumour voice
	net.damage(5, 1.0)
	w.condition[5] = 0.0
	w.push_to_network(net)
	assert_float(net.stones[5]["condition"]).is_equal_approx(0.0, 1e-9)


# --- cost -----------------------------------------------------------------------------

func test_tick_and_coverage_cost() -> void:
	var w := Ward.new().setup(2) as Ward
	var t0 := Time.get_ticks_usec()
	for i in 200:
		w.tick(0.5)
	var tick_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	assert_float(tick_ms).is_less(2.0)
	var acc := 0.0
	var cov_us := 1e9
	for rep in 3:   # best of 3: a busy machine must not fail a cost test
		var t1 := Time.get_ticks_usec()
		for i in 2000:
			acc += w.coverage_at(Vector2(float(i % 50) * 40.0 - 900.0, float(i / 50) * 40.0 - 900.0))
		cov_us = minf(cov_us, float(Time.get_ticks_usec() - t1) / 2000.0)
	assert_float(cov_us).is_less(50.0)
	assert_float(acc).is_greater(0.0)
	var t2 := Time.get_ticks_usec()
	w.cut_link(w.links[7]["a"], w.links[7]["b"])
	var cut_ms := float(Time.get_ticks_usec() - t2) / 1000.0
	assert_float(cut_ms).is_less(30.0)          # a player edit re-routes the whole graph


func test_debug_image() -> void:
	var w := _scenario(1)
	var img := w.debug_image(128)
	assert_int(img.get_width()).is_equal(128)


func test_long_run_roundtrip_and_worst_tick() -> void:
	var w := Ward.new().setup(1) as Ward
	var times: Array = []
	for i in 300:
		var t := Time.get_ticks_usec()
		w.tick(0.5)
		times.append(float(Time.get_ticks_usec() - t) / 1000.0)
	times.sort()
	print("WARD tick ms: p50 %.3f p95 %.3f max %.3f" % [times[150], times[285], times[299]])
	assert_float(times[285]).is_less(5.0)      # p95; the 2 ms design budget has 2x headroom for a busy CI box
	var b := Ward.new()
	b.setup(1)
	b.deserialize(JSON.parse_string(JSON.stringify(w.serialize())))
	assert_str(b.digest()).is_equal(w.digest())
	for i in 40:
		w.tick(0.5)
		b.tick(0.5)
	assert_str(b.digest()).is_equal(w.digest())   # 150 days of wear and failures, then 20 more, identical


func test_flow_edges_are_thick_near_the_elder_and_follow_cuts() -> void:
	var w := _mini()
	var by_pair := {}
	for e in w.flow_edges():
		by_pair["%d-%d" % [e["a"], e["b"]]] = e["flow"]
	# E0-A1 carries everything road A needs, A5-A6 only A6's share
	assert_float(by_pair["0-1"]).is_greater(by_pair["1-2"])
	assert_float(by_pair["1-2"]).is_greater(by_pair["5-6"])
	assert_float(by_pair["0-1"]).is_less_equal(w.elder_status()[0]["drawn"] + 1e-9)
	assert_float(by_pair["0-1"]).is_equal_approx(float(w.elder_status()[0]["drawn"]) * 0.96, 0.02)
	w.cut_link(3, 4)
	var cut_flow := 0.0
	for e in w.flow_edges():
		if e["a"] == 3 and e["b"] == 4:
			cut_flow = e["flow"]
	assert_float(cut_flow).is_equal(0.0)


# --- world-map layer shows a carve -----------------------------------------------------

func test_map_layer_coverage_data_changes_after_a_carve() -> void:
	State.clear()
	var w := _mini()
	State.register_sim(w)
	var layer: Control = preload("res://scripts/region1/r1_map_layer.gd").new()
	var before: PackedFloat64Array = layer.coverage_data()
	assert_int(before.size()).is_equal(w.n * 3)
	assert_bool(w.carve(3, "ward")["ok"]).is_true()
	var after: PackedFloat64Array = layer.coverage_data()
	assert_float(after[3 * 3]).is_equal_approx(before[3 * 3] * 1.3, 0.01)       # bubble radius the map draws
	assert_float(after[3 * 3 + 2]).is_equal(float(Ward.G_WARD))                  # glyph (rim colour)
	assert_bool(after == before).is_false()
	layer.free()
	State.clear()
