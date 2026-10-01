extends GdUnitTestSuite
## Travel in the 12 x 12 km world (docs/design/REALM_PLAN.md "Travel and world size"): stamina on long runs, horse gallop
## limit, night camping, the coach between discovered waystations (gold and hours), and road events that are paced.

const TR := preload("res://scripts/world/travel_rules.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const Enc := preload("res://scripts/world/realm_encounters.gd")
const Mount := preload("res://scripts/actors/mount_controller.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")


# --- stamina -----------------------------------------------------------------------------------

func test_a_short_run_is_free_and_a_long_run_drains() -> void:
	assert_float(TR.run_drain(5.0)).is_equal(0.0)
	assert_float(TR.run_drain(TR.RUN_FREE_S)).is_equal(0.0)
	assert_float(TR.run_drain(TR.RUN_FREE_S + 1.0)).is_greater(0.0)
	# A full bar lasts about 11 s of drain: you cannot run across the map.
	assert_float(100.0 / TR.RUN_DRAIN).is_between(8.0, 16.0)


func test_winded_until_your_wind_is_back() -> void:
	assert_bool(TR.is_winded(0.0, false)).is_true()
	assert_bool(TR.is_winded(10.0, true)).is_true()
	assert_bool(TR.is_winded(TR.WINDED_RECOVER * 100.0 + 1.0, true)).is_false()
	assert_bool(TR.is_winded(10.0, false)).is_false()
	# A tired runner (cap 55) recovers at 70 % of what he has, not of a full bar he can never reach.
	assert_bool(TR.is_winded(30.0, true, 55.0)).is_true()
	assert_bool(TR.is_winded(0.7 * 55.0 - 0.1, true, 55.0)).is_true()
	assert_bool(TR.is_winded(0.7 * 55.0 + 0.1, true, 55.0)).is_false()


func test_sustained_running_averages_well_below_a_run() -> void:
	# Simulate 10 minutes of holding sprint with the player's own numbers: 28 stamina/s regen (x WINDED_REGEN when winded),
	# 0.6 s regen delay after a drain, _run_time falling 2/s while not running.
	var stamina := 100.0
	var run_time := 0.0
	var winded := false
	var metres := 0.0
	var dt := 0.05
	var delay := 0.0
	for i in int(600.0 / dt):
		var running := not winded
		delay -= dt
		if running:
			run_time += dt
			var drain := TR.run_drain(run_time)
			if drain > 0.0:
				stamina = maxf(stamina - drain * dt, 0.0)
				delay = 0.6
			metres += 6.5 * dt
		else:
			run_time = maxf(0.0, run_time - dt * 2.0)
			if delay <= 0.0:
				stamina = minf(stamina + 28.0 * dt * TR.WINDED_REGEN, 100.0)
			metres += 2.4 * dt
		winded = TR.is_winded(stamina, winded)
	var average := metres / 600.0
	assert_float(average).is_between(3.5, 5.0)
	assert_float(average).is_less(5.8)          # a canter is better than running


func test_a_horse_gallops_for_a_while_then_must_canter() -> void:
	var t := 0.0
	var allowed := true
	var steps := 0
	while allowed and steps < 400:
		var r := TR.gallop_step(t, true, 0.5, allowed)
		t = float(r[0])
		allowed = bool(r[1])
		steps += 1
	assert_bool(allowed).is_false()
	assert_float(float(steps) * 0.5).is_greater_equal(TR.GALLOP_FREE_S)
	assert_float(float(steps) * 0.5).is_less(TR.GALLOP_FREE_S + 2.0)
	# It recovers at a canter in GALLOP_REST_S seconds, and not before.
	var rest := 0.0
	while not allowed and rest < 60.0:
		var r2 := TR.gallop_step(t, false, 0.5, allowed)
		t = float(r2[0])
		allowed = bool(r2[1])
		rest += 0.5
	assert_bool(allowed).is_true()
	assert_float(rest).is_between(TR.GALLOP_REST_S - 1.0, TR.GALLOP_REST_S + 1.0)


func test_mount_controller_obeys_gallop_allowed() -> void:
	WorldGen.setup(1066)
	var horse := Node3D.new()
	var m := Mount.new(horse)
	auto_free(horse)
	m.gallop_allowed = false
	for i in 400:
		m.drive(0.05, Vector3(0, 0, 1), true, Vector3(10, 0, 10))
	assert_float(m.speed).is_less_equal(Mount.CANTER_SPEED + 0.01)
	m.gallop_allowed = true
	for i in 400:
		m.drive(0.05, Vector3(0, 0, 1), true, Vector3(10, 0, 10))
	assert_float(m.speed).is_greater(Mount.CANTER_SPEED + 1.0)


func test_a_horse_beats_a_runner_over_distance() -> void:
	# On foot you run 6.5 m/s for RUN_FREE_S + a full bar, then walk 2.4. A canter is 5.8 for free.
	var run_s := TR.RUN_FREE_S + 100.0 / TR.RUN_DRAIN
	var foot_10km := run_s * 6.5 + (10000.0 - run_s * 6.5) / 2.4
	var horse_10km := 10000.0 / Mount.CANTER_SPEED
	assert_float(horse_10km).is_less(foot_10km * 0.6)


# --- fast travel ----------------------------------------------------------------------------------

func test_fare_and_hours_grow_with_distance() -> void:
	assert_int(TR.fare(0.0)).is_equal(TR.FARE_BASE)
	assert_int(TR.fare(2000.0)).is_less(TR.fare(8000.0))
	assert_int(TR.fare(8000.0)).is_between(30, 80)
	assert_float(TR.coach_hours(8000.0)).is_greater(TR.coach_hours(2000.0))
	assert_float(TR.coach_hours(10000.0)).is_between(4.0, 12.0)


func test_a_ride_needs_a_waystation_and_the_fare() -> void:
	var sites: Array = [{"kind": "waystation", "name": "A Coach Inn", "pos": Vector2(100, 100)}, {"kind": "farm", "pos": Vector2(0, 0)}]
	assert_bool(TR.waystation_at(Vector2(0, 0), sites).is_empty()).is_true()
	assert_str(String(TR.waystation_at(Vector2(130, 100), sites)["name"])).is_equal("A Coach Inn")
	assert_str(TR.ride_block_reason({}, 10, 100)).contains("waystation")
	assert_str(TR.ride_block_reason(sites[0], 50, 20)).contains("fare")
	assert_str(TR.ride_block_reason(sites[0], 20, 20)).is_equal("")


func test_only_waystations_are_fast_travel_points() -> void:
	WorldGen.setup(1066)
	var d := Discovery.new()
	d.build_from_world()
	var n := 0
	for pl: Dictionary in d.places:
		if bool(pl["travel"]):
			n += 1
			assert_str(String(pl["kind"])).is_equal("waystation")
		if String(pl["category"]) == "settlement":
			assert_bool(bool(pl["travel"])).override_failure_message("%s is a settlement" % pl["name"]).is_false()
	assert_int(n).is_greater_equal(20)
	assert_int(d.travel_points().size()).is_equal(0)       # nothing discovered yet


# --- night camping ----------------------------------------------------------------------------

func test_camp_needs_a_kit_dusk_and_open_country() -> void:
	var none := TR.camp_kit({})
	var roll := TR.camp_kit({"bedroll": 1})
	var tent := TR.camp_kit({"bedroll": 1, "tent_kit": 1, "tinderbox": 1})
	assert_str(String(none["id"])).is_equal("")
	assert_str(String(tent["id"])).is_equal("tent_kit")
	assert_bool(bool(tent["fire"])).is_true()
	assert_str(TR.camp_block_reason(21, false, 9.0, false, none)).contains("nothing to sleep on")
	assert_str(TR.camp_block_reason(12, false, 9.0, false, roll)).contains("not dark")
	assert_str(TR.camp_block_reason(21, false, 1.0, false, roll)).contains("town")
	assert_str(TR.camp_block_reason(21, true, 9.0, false, roll)).contains("outside")
	assert_str(TR.camp_block_reason(21, false, 9.0, true, roll)).contains("enemies")
	assert_str(TR.camp_block_reason(23, false, 9.0, false, roll)).is_equal("")
	assert_str(TR.camp_block_reason(3, false, 9.0, false, roll)).is_equal("")


func test_better_kit_sleeps_better() -> void:
	var q_ground := TR.camp_quality(TR.camp_kit({}))
	var q_roll := TR.camp_quality(TR.camp_kit({"bedroll": 1}))
	var q_tent := TR.camp_quality(TR.camp_kit({"tent_kit": 1, "tinderbox": 1}))
	assert_float(q_ground).is_equal(TR.GROUND_QUALITY)
	assert_float(q_roll).is_greater(q_ground)
	assert_float(q_tent).is_greater(q_roll)
	assert_float(q_tent).is_less_equal(1.0)
	# The shop items the camp reads exist and carry the rest bonus.
	for id: String in TR.KIT_BONUS:
		assert_float(float(Crafting.item_info(id).get("rest_bonus", 0.0))).is_equal(float(TR.KIT_BONUS[id]))


func test_camp_risk_follows_danger_bandits_and_fire() -> void:
	var calm := TR.camp_risk({"danger": 0.0})
	var wild := TR.camp_risk({"danger": 60.0, "bandit_dist": 300.0, "road_dist": 20.0})
	assert_float(wild).is_greater(calm * 3.0)
	assert_float(TR.camp_risk({"danger": 60.0, "fire": true})).is_less(TR.camp_risk({"danger": 60.0}))
	assert_float(TR.camp_risk({"danger": 60.0, "tier": "kingdom"})).is_less(TR.camp_risk({"danger": 60.0}))
	assert_float(TR.camp_risk({"danger": 500.0, "bandit_dist": 1.0})).is_less_equal(0.6)


func test_camp_outcomes() -> void:
	var ctx := {"danger": 50.0, "species": "wolf", "bandit_dist": 5000.0}
	var hit := TR.camp_outcome(ctx, 0.0, 0.9)
	assert_str(String(hit["outcome"])).is_equal("ambush")
	assert_str(String(hit["foe"])).is_equal("beasts")
	assert_str(String(hit["species"])).is_equal("wolf")
	assert_int(int(hit["hours"])).is_between(2, 5)
	var raid := TR.camp_outcome({"danger": 5.0, "bandit_dist": 200.0}, 0.0, 0.9)
	assert_str(String(raid["foe"])).is_equal("bandits")
	assert_str(String(TR.camp_outcome({"danger": 5.0, "bandit_dist": 200.0}, 0.0, 0.1)["outcome"])).is_equal("thief")
	assert_str(String(TR.camp_outcome(ctx, 0.99, 0.5)["outcome"])).is_equal("safe")
	assert_str(String(TR.camp_outcome({"danger": 0.0}, TR.camp_risk({"danger": 0.0}) + 0.05, 0.5)["outcome"])).is_equal("visitor")
	assert_float(TR.night_hours(21.0)).is_equal_approx(9.5, 0.01)
	assert_float(TR.night_hours(6.0)).is_equal(1.0)


# --- road events ---------------------------------------------------------------------------------

func _enc() -> Node:
	WorldGen.setup(1066)
	var e: Node = Enc.new()
	e.hub_override = Hub.new()
	return auto_free(e)


## A point on the road between two settlements, far from both.
func _road_point() -> Vector2:
	var best := Vector2.INF
	var best_len := 0.0
	for r in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		if a.distance_to(b) > best_len:
			best_len = a.distance_to(b)
			best = a.lerp(b, 0.5)
	return best


func _ctx(over := {}) -> Dictionary:
	var c := {"pos": _road_point(), "abs_hour": 100, "day": 4, "hour": 14, "road_ok": 0, "last_pos": Vector2.INF,
		"road_info": {"dist": 5.0, "tier": "rural"}, "danger": {"total": 0.0, "sources": []}, "caravans": [], "bandit_dist": 5000.0,
		"near_town": false, "rolls": [0.0, 0.0, 0.4]}
	c.merge(over, true)
	return c


func test_road_weights_by_road_and_danger() -> void:
	var safe := TR.road_weights({"tier": "kingdom", "danger": 80.0, "hour": 12})
	assert_float(float(safe["ambush"])).is_equal(0.0)       # kingdom roads are patrolled
	var wild := TR.road_weights({"tier": "frontier", "danger": 70.0, "bandit_dist": 300.0, "hour": 12})
	assert_float(float(wild["ambush"])).is_greater(float(TR.road_weights({"tier": "frontier", "danger": 0.0, "hour": 12})["ambush"]) + 1.5)
	var night := TR.road_weights({"tier": "frontier", "danger": 70.0, "bandit_dist": 300.0, "hour": 23})
	assert_float(float(night["ambush"])).is_greater(float(wild["ambush"]))
	assert_float(float(TR.road_weights({"tier": "rural", "caravans": 2, "hour": 12})["caravan"])).is_greater(float(TR.road_weights({"tier": "rural", "hour": 12})["caravan"]))


func test_road_kind_pick_is_paced() -> void:
	var w := {"news": 1.0, "camp": 1.0, "caravan": 1.0, "ambush": 0.0}
	assert_str(TR.pick_road_kind(w, 0.9, 0.1)).is_equal("")          # most checks are quiet
	assert_str(TR.pick_road_kind(w, 0.0, 0.1)).is_equal("news")
	assert_str(TR.pick_road_kind(w, 0.0, 0.5)).is_equal("camp")
	assert_str(TR.pick_road_kind(w, 0.0, 0.99)).is_equal("caravan")
	assert_str(TR.pick_road_kind({"ambush": 0.0}, 0.0, 0.0)).is_equal("")
	# Over a 10 km road on foot (2 s ticks at 2.3 m/s) the chance per tick is small and the distance rule caps the number of
	# meetings: a handful, never a stream.
	var length := 10000.0
	var ticks := length / 2.3 / 2.0
	var by_distance := length / TR.ROAD_MIN_DIST
	var ticks_to_fire := 1.0 / (TR.ROAD_TICK_CHANCE * 2.5)             # a typical road: total weight about 2.5
	var per_event_m := TR.ROAD_MIN_DIST + ticks_to_fire * 2.0 * 2.3
	assert_float(length / per_event_m).is_between(3.0, 8.0)
	assert_float(minf(ticks * TR.ROAD_TICK_CHANCE * 2.5, by_distance)).is_less(9.0)


func test_a_road_event_fires_on_a_quiet_road_when_the_roll_allows() -> void:
	var e := _enc()
	var ev: Dictionary = e.road_event(_ctx())
	assert_str(String(ev["kind"])).is_equal("road")
	assert_str(String(ev["sub"])).is_equal("news")
	assert_str(String(ev["key"])).is_equal("road:4:14:news")
	assert_bool(e.road_event(_ctx({"rolls": [0.99, 0.0, 0.0]})).is_empty()).is_true()          # the gate roll says: quiet


func test_road_events_respect_cooldown_distance_and_place() -> void:
	var e := _enc()
	var here: Vector2 = _road_point()
	assert_bool(e.road_event(_ctx({"abs_hour": 100, "road_ok": 106})).is_empty()).is_true()    # cooldown
	assert_bool(e.road_event(_ctx({"abs_hour": 106, "road_ok": 106})).is_empty()).is_false()
	assert_bool(e.road_event(_ctx({"last_pos": here + Vector2(300, 0)})).is_empty()).is_true()  # too near the last one
	assert_bool(e.road_event(_ctx({"last_pos": here + Vector2(1500, 0)})).is_empty()).is_false()
	assert_bool(e.road_event(_ctx({"road_info": {"dist": 200.0, "tier": "rural"}})).is_empty()).is_true()   # off the road
	var town: Vector2 = WorldGen.settlements[0]["pos"]
	assert_bool(e.road_event(_ctx({"pos": town})).is_empty()).is_true()                         # never inside a settlement
	e.delivered["road:4:14:news"] = 4
	assert_bool(e.road_event(_ctx()).is_empty()).is_true()                                       # never twice


func test_dangerous_roads_ambush_from_territories_and_bandit_camps() -> void:
	var e := _enc()
	var beasts: Dictionary = e.road_event(_ctx({"road_info": {"dist": 5.0, "tier": "frontier"}, "danger": {"total": 60.0, "sources": [{"species": "wolf", "name": "Greywood pack"}]},
		"rolls": [0.0, 0.99, 0.2]}))
	assert_str(String(beasts["sub"])).is_equal("ambush")
	assert_str(String(beasts["foe"])).is_equal("beasts")
	assert_str(String(beasts["species"])).is_equal("wolf")
	var raid: Dictionary = e.road_event(_ctx({"road_info": {"dist": 5.0, "tier": "frontier"}, "bandit_dist": 300.0, "danger": {"total": 5.0, "sources": []},
		"rolls": [0.0, 0.99, 0.2]}))
	assert_str(String(raid["sub"])).is_equal("ambush")
	assert_str(String(raid["foe"])).is_equal("bandits")
	assert_int(int(raid["toll"])).is_between(15, 120)
	# A kingdom road is never ambushed: whatever the roll, the pick is not an ambush.
	for r in [0.0, 0.3, 0.6, 0.99]:
		var k: Dictionary = e.road_event(_ctx({"road_info": {"dist": 5.0, "tier": "kingdom"}, "bandit_dist": 100.0, "danger": {"total": 90.0, "sources": []}, "rolls": [0.0, r, 0.2]}))
		assert_bool(k.is_empty() or String(k["sub"]) != "ambush").is_true()


func test_caravans_come_from_the_enterprise_module() -> void:
	var e := _enc()
	var ev: Dictionary = e.road_event(_ctx({"caravans": [{"name": "Dunhallow Wagons", "dest": "Kingsreach"}], "rolls": [0.0, 0.99, 0.0]}))
	assert_str(String(ev["sub"])).is_equal("caravan")
	assert_str(String(ev["caravan"]["name"])).is_equal("Dunhallow Wagons")
	assert_bool(e.road_event(_ctx({"rolls": [0.0, 0.99, 0.0]})).is_empty()).is_false()           # still a generic merchant without one
	for sid in 3:
		assert_str(e._settlement_name(sid)).is_not_empty()


func test_caravan_stock_exists_and_costs_more_than_the_shop() -> void:
	var e := _enc()
	for id: String in Enc.CARAVAN_STOCK:
		var info: Dictionary = Crafting.item_info(id)
		assert_bool(info.is_empty()).override_failure_message("stock item %s unknown" % id).is_false()
		assert_int(e._stock_price(id)).is_greater_equal(int(info.get("price", 5)))
	assert_bool("bedroll" in Enc.CARAVAN_STOCK).is_true()


func test_road_event_pacing_survives_a_save() -> void:
	var e := _enc()
	e._road_ok = 321
	e._road_last = Vector2(10, 20)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(e.snapshot()))
	var e2 := _enc()
	e2.restore(snap)
	assert_int(e2._road_ok).is_equal(321)
	assert_vector(e2._road_last).is_equal(Vector2(10, 20))
	e2.restore({})
	assert_vector(e2._road_last).is_equal(Vector2.INF)


func test_the_bandit_camp_distance_reads_the_sites() -> void:
	WorldGen.setup(1066)
	for s in WorldGen.sites:
		if String(s["kind"]) == "bandit_camp":
			assert_float(Enc.bandit_distance(s["pos"])).is_less(1.0)
			return
	fail("no bandit camp in the world")


func test_using_a_bedroll_camps_and_never_uses_it_up() -> void:
	Life.give("bedroll", 1)
	var before := Life.count("bedroll")
	var msg := String(Life.equipment.consume(Life, "bedroll"))
	assert_str(msg).is_not_empty()
	assert_str(msg).is_not_equal("You can't use Bedroll.")      # camp_here answered (here: no player in the test world)
	assert_int(Life.count("bedroll")).is_equal(before)
	Life.take("bedroll", 1)
	assert_str(String(Life.equipment.consume(Life, "tent_kit"))).contains("no")       # none carried
