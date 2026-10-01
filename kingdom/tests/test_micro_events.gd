extends GdUnitTestSuite
## Street micro-events (scripts/population/micro_events.gd, micro_catalog.gd): the pool, the weights by time of
## day, district, weather and the state of the town, cooldowns, determinism and the actor budget.

const MicroEvents := preload("res://scripts/population/micro_events.gd")
const Catalog := preload("res://scripts/population/micro_catalog.gd")
const MicroScene := preload("res://scripts/population/micro_scene.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const Schedule := preload("res://scripts/population/schedule.gd")

const TEMPLATES := ["vehicle", "walkers", "vignette", "chase", "eject", "kids", "procession", "shutters", "lamp", "gate", "fire", "broken_cart", "carry"]
const DISTRICTS := ["market", "craft", "poor", "admin", "inn", "military"]


func _ctx(hour: float, district := "market", over: Dictionary = {}, rain := false, mood: Dictionary = {}, kind := "town", day := 3) -> Dictionary:
	return MicroEvents.make_context(hour, day, district, rain, mood, kind, over)


func _w(id: String, ctx: Dictionary) -> float:
	return MicroEvents.weight_of(MicroEvents.entry_of(id), ctx)


# ---------------------------------------------------------------- the pool
func test_pool_has_at_least_fifty_distinct_scenes() -> void:
	assert_int(Catalog.POOL.size()).is_greater_equal(50)
	var seen := {}
	for e: Dictionary in Catalog.POOL:
		assert_bool(seen.has(e["id"])).is_false()
		seen[e["id"]] = true


func test_every_entry_is_well_formed() -> void:
	for e: Dictionary in Catalog.POOL:
		var id := String(e["id"])
		assert_bool(TEMPLATES.has(String(e["tpl"]))).override_failure_message("%s: unknown template" % id).is_true()
		assert_float(float(e["w"])).override_failure_message("%s: weight" % id).is_greater(0.0)
		assert_float(float(e["cd"])).override_failure_message("%s: cooldown" % id).is_greater(0.0)
		var dur: Array = e["dur"]
		assert_bool(float(dur[0]) > 0.0 and float(dur[1]) >= float(dur[0])).override_failure_message("%s: dur" % id).is_true()
		for d: String in (e.get("dw", {}) as Dictionary):
			assert_bool(d == "*" or DISTRICTS.has(d)).override_failure_message("%s: district %s" % [id, d]).is_true()
		for f: String in (e.get("mods", {}) as Dictionary):
			assert_bool(_ctx(12.0).has(f)).override_failure_message("%s: unknown flag %s" % [id, f]).is_true()
		var when: Dictionary = e.get("when", {})
		for f: String in when.get("need", []) + when.get("not", []):
			assert_bool(_ctx(12.0).has(f)).override_failure_message("%s: unknown flag %s" % [id, f]).is_true()


func test_every_hour_of_the_day_has_something_to_run() -> void:
	for h in 24:
		var ctx := _ctx(float(h) + 0.5, "market")
		assert_int(MicroEvents.weights(ctx).size()).override_failure_message("nothing at %d:30" % h).is_greater_equal(1)


# ---------------------------------------------------------------- weights: time, district, weather, state
func test_time_of_day_gates_scenes() -> void:
	assert_float(_w("street_performer", _ctx(14.0))).is_greater(0.0)
	assert_float(_w("street_performer", _ctx(3.0))).is_equal(0.0)
	assert_float(_w("market_closing", _ctx(18.7))).is_greater(_w("market_closing", _ctx(17.6)))
	assert_float(_w("market_closing", _ctx(11.0))).is_equal(0.0)
	assert_float(_w("lamp_lighter", _ctx(18.4))).is_greater(0.0)
	assert_float(_w("lamp_lighter", _ctx(12.0))).is_equal(0.0)
	assert_float(_w("gates_closing", _ctx(21.2, "military"))).is_greater(0.0)
	assert_float(_w("gates_opening", _ctx(5.9, "military"))).is_greater(0.0)
	assert_float(_w("gates_closing", _ctx(9.0, "military"))).is_equal(0.0)
	# the night watch wraps midnight
	assert_float(_w("night_watch_rounds", _ctx(23.5))).is_greater(0.0)
	assert_float(_w("night_watch_rounds", _ctx(2.0))).is_greater(0.0)
	assert_float(_w("night_watch_rounds", _ctx(12.0))).is_equal(0.0)
	assert_float(_w("drunk_ejected", _ctx(23.0, "inn"))).is_greater(0.0)
	assert_float(_w("drunk_ejected", _ctx(10.0, "inn"))).is_equal(0.0)


func test_in_hours_wraps_midnight() -> void:
	assert_bool(MicroEvents.in_hours(23.0, [21, 5])).is_true()
	assert_bool(MicroEvents.in_hours(2.0, [21, 5])).is_true()
	assert_bool(MicroEvents.in_hours(12.0, [21, 5])).is_false()
	assert_bool(MicroEvents.in_hours(12.0, [8, 17])).is_true()
	assert_bool(MicroEvents.in_hours(17.0, [8, 17])).is_false()


func test_district_changes_the_odds() -> void:
	assert_float(_w("street_performer", _ctx(15.0, "market"))).is_greater(_w("street_performer", _ctx(15.0, "poor")) * 3.0)
	assert_float(_w("training_drills", _ctx(10.0, "military"))).is_greater(_w("training_drills", _ctx(10.0, "market")) * 5.0)
	assert_float(_w("laundry_day", _ctx(10.0, "poor", {}, false, {}, "town", 9))).is_greater(_w("laundry_day", _ctx(10.0, "admin", {}, false, {}, "town", 9)))
	assert_float(_w("noble_carriage", _ctx(12.0, "admin"))).is_greater(_w("noble_carriage", _ctx(12.0, "poor")) * 4.0)
	assert_float(_w("drunk_ejected", _ctx(21.0, "inn"))).is_greater(_w("drunk_ejected", _ctx(21.0, "craft")) * 10.0)


func test_weather_gates_outdoor_scenes() -> void:
	assert_float(_w("children_chasing", _ctx(11.0, "poor"))).is_greater(0.0)
	assert_float(_w("children_chasing", _ctx(11.0, "poor", {}, true))).is_equal(0.0)
	# laundry is a dry Wednesday-ish job: day % 7 == 2 and no rain
	assert_float(_w("laundry_day", _ctx(10.0, "poor", {}, false, {}, "town", 9))).is_greater(0.0)
	assert_float(_w("laundry_day", _ctx(10.0, "poor", {}, true, {}, "town", 9))).is_equal(0.0)
	assert_float(_w("laundry_day", _ctx(10.0, "poor", {}, false, {}, "town", 10))).is_equal(0.0)
	# a busker thins out in the rain without disappearing
	var dry := _w("street_performer", _ctx(15.0))
	var wet := _w("street_performer", _ctx(15.0, "market", {}, true))
	assert_float(wet).is_less(dry * 0.3)
	assert_float(wet).is_greater(0.0)


func test_town_state_switches_scenes_on() -> void:
	var calm := _ctx(12.0)
	assert_float(_w("recruiters_calling", calm)).is_equal(0.0)
	assert_float(_w("recruiters_calling", _ctx(12.0, "market", {}, false, {"war": 0.9}))).is_greater(0.0)
	assert_float(_w("grain_relief_wagon", calm)).is_equal(0.0)
	assert_float(_w("grain_relief_wagon", _ctx(12.0, "market", {}, false, {"scarcity": 0.8}))).is_greater(0.0)
	assert_float(_w("monster_alarm", calm)).is_equal(0.0)
	assert_float(_w("monster_alarm", _ctx(12.0, "market", {}, false, {"monster": 1.0}))).is_greater(0.0)
	assert_float(_w("festival_dancers", calm)).is_equal(0.0)
	assert_float(_w("festival_dancers", _ctx(15.0, "market", {}, false, {"festival": "midsummer"}))).is_greater(0.0)
	assert_float(_w("healer_rounds", calm)).is_equal(0.0)
	assert_float(_w("healer_rounds", _ctx(12.0, "poor", {}, false, {"plague": true}))).is_greater(0.0)
	assert_float(_w("curfew_straggler", _ctx(22.0, "inn"))).is_equal(0.0)
	assert_float(_w("curfew_straggler", _ctx(22.0, "inn", {}, false, {"curfew": true}))).is_greater(0.0)
	assert_float(_w("small_fire", calm) * 20.0).is_less(_w("small_fire", _ctx(12.0, "poor", {}, false, {"fire": true})))
	assert_float(_w("market_opening", calm)).is_equal(0.0)
	assert_float(_w("market_opening", _ctx(7.8, "market", {"shutters_down": true}))).is_greater(0.0)


func test_mourning_makes_funerals_likely_and_festivals_exclude_them() -> void:
	var base := _w("funeral_procession", _ctx(11.0, "admin"))
	var mourn := _w("funeral_procession", _ctx(11.0, "admin", {}, false, {"mourning": 1.0}))
	assert_float(mourn).is_greater(base * 5.0)
	assert_float(_w("funeral_procession", _ctx(11.0, "admin", {}, false, {"festival": "harvest"}))).is_equal(0.0)
	assert_float(_w("wedding_procession", _ctx(12.0, "admin", {}, false, {"festival": "harvest"}))).is_greater(_w("wedding_procession", _ctx(12.0, "admin")))
	assert_float(_w("wedding_procession", _ctx(12.0, "admin", {}, false, {"mourning": 1.0}))).is_equal(0.0)


func test_settlement_kind_gates_noble_and_crier() -> void:
	assert_float(_w("noble_carriage", _ctx(12.0, "admin", {}, false, {}, "village"))).is_equal(0.0)
	assert_float(_w("town_crier", _ctx(12.0, "admin", {}, false, {}, "village"))).is_equal(0.0)
	assert_float(_w("noble_carriage", _ctx(12.0, "admin", {}, false, {}, "town"))).is_greater(0.0)
	assert_float(_w("cattle_home", _ctx(17.5, "poor", {}, false, {}, "village"))).is_greater(0.0)
	assert_float(_w("cattle_home", _ctx(17.5, "poor", {}, false, {}, "town"))).is_equal(0.0)


# ---------------------------------------------------------------- picking, cooldowns, determinism
func test_pick_is_deterministic_for_a_seed() -> void:
	var ctx := _ctx(15.0, "market")
	for s in 40:
		assert_str(MicroEvents.pick(ctx, s, {}, 0)).is_equal(MicroEvents.pick(ctx, s, {}, 0))
	# and whole sequences repeat
	var a: Array = []
	var b: Array = []
	for s in 30:
		a.append(MicroEvents.pick(ctx, hash([1066, 3, 30, s]), {}, 0))
		b.append(MicroEvents.pick(ctx, hash([1066, 3, 30, s]), {}, 0))
	assert_array(a).is_equal(b)


func test_pick_varies_with_the_seed_and_follows_the_weights() -> void:
	var ctx := _ctx(15.0, "market")
	var counts := {}
	for s in 400:
		var id := MicroEvents.pick(ctx, s * 7919 + 13, {}, 0)
		counts[id] = int(counts.get(id, 0)) + 1
	assert_int(counts.size()).is_greater(8)
	# every pick was eligible
	var ws := MicroEvents.weights(ctx)
	for id: String in counts:
		assert_bool(ws.has(id)).is_true()
	# a heavy entry shows up more than a light one
	assert_int(int(counts.get("cart_through", 0))).is_greater(int(counts.get("noble_carriage", 0)))


func test_cooldown_blocks_a_scene_until_it_expires() -> void:
	var ctx := _ctx(15.0, "market")
	var ws := MicroEvents.weights(ctx)
	var only := "street_performer"
	var cd := {}
	for id: String in ws:
		if id != only:
			cd[id] = 10_000
	assert_str(MicroEvents.pick(ctx, 5, cd, 1000)).is_equal(only)
	cd[only] = 10_000
	assert_str(MicroEvents.pick(ctx, 5, cd, 1000)).is_equal("")           # everything is cooling down
	assert_str(MicroEvents.pick(ctx, 5, cd, 10_001)).is_not_equal("")      # expired
	# a cooldown never excludes an id it does not name
	for s in 60:
		assert_str(MicroEvents.pick(ctx, s, {"cart_through": 10_000}, 1000)).is_not_equal("cart_through")


func test_active_scenes_are_not_repeated() -> void:
	var ctx := _ctx(15.0, "market")
	for s in 60:
		assert_str(MicroEvents.pick(ctx, s, {}, 0, ["street_performer", "cart_through"])).is_not_equal("street_performer")


func test_nothing_to_pick_returns_empty() -> void:
	var cd := {}
	for e: Dictionary in Catalog.POOL:
		cd[e["id"]] = 99_999
	assert_str(MicroEvents.pick(_ctx(15.0), 1, cd, 0)).is_equal("")


# ---------------------------------------------------------------- budget
func test_budget_allows_at_most_two_scenes() -> void:
	assert_bool(MicroEvents.budget_allows(0, 0, 8, 24)).is_true()
	assert_bool(MicroEvents.budget_allows(1, 4, 8, 24)).is_true()
	assert_bool(MicroEvents.budget_allows(MicroEvents.MAX_ACTIVE, 0, 0, 24)).is_false()
	assert_int(MicroEvents.MAX_ACTIVE).is_equal(2)


func test_budget_caps_actors_by_tier_and_crowd() -> void:
	# LOW tier (5 full NPCs): one scene's cast already exceeds the allowance
	assert_bool(MicroEvents.budget_allows(0, 1, 2, 5)).is_false()
	assert_bool(MicroEvents.budget_allows(0, 0, 2, 5)).is_true()
	# a crowded street (24 villagers) leaves no room beyond the tier's NPC allowance + 6
	assert_bool(MicroEvents.budget_allows(0, 0, 24, 24)).is_true()
	assert_bool(MicroEvents.budget_allows(1, 8, 24, 24)).is_false()
	# never more than ACTOR_CAP_MAX alive
	assert_bool(MicroEvents.budget_allows(1, MicroEvents.ACTOR_CAP_MAX, 0, 99)).is_false()


func test_busy_streets_start_scenes_sooner() -> void:
	assert_float(MicroEvents.gap_seconds(1.0, 0.5)).is_less(MicroEvents.gap_seconds(0.1, 0.5))
	assert_float(MicroEvents.gap_seconds(0.0, 0.0)).is_greater_equal(MicroEvents.MIN_GAP * 0.7)
	assert_float(MicroEvents.gap_seconds(1.0, 1.0)).is_less_equal(MicroEvents.MAX_GAP * 1.3)


# ---------------------------------------------------------------- districts
func test_district_fallback_without_a_planned_district() -> void:
	var s := {"pos": Vector2.ZERO, "radius": 100.0, "plan": {"plaza_r": 15.0, "gates": [0.0, PI], "lots": [{"asset": "inn", "pos": Vector2(0, 50), "yaw": 0.0}],
		"landmarks": [{"asset": "temple", "pos": Vector2(0, -45), "yaw": 0.0}]}}
	assert_str(MicroEvents.district_of(s, Vector2(3, 3))).is_equal("market")
	assert_str(MicroEvents.district_of(s, Vector2(92, 0))).is_equal("military")
	assert_str(MicroEvents.district_of(s, Vector2(0, 52))).is_equal("inn")
	assert_str(MicroEvents.district_of(s, Vector2(0, -46))).is_equal("admin")
	assert_str(MicroEvents.district_of(s, Vector2(0, 80))).is_equal("poor")
	assert_str(MicroEvents.district_of(s, Vector2(500, 0))).is_equal("")


# ---------------------------------------------------------------- staging in a real town (no rendering: actors build lazily)
func _town(name: String) -> int:
	for t: Dictionary in WorldGen.settlements:
		if t["name"] == name:
			return int(t["id"])
	return -1


## Places a player might stand in: [position, facing] around the plaza, a gate, the inn, the temple and the drill yard.
func _vantage_points(sid: int) -> Array:
	var s: Dictionary = WorldGen.settlements[sid]
	var c: Vector2 = s["pos"]
	var plan: Dictionary = s["plan"]
	var graph := StreetGraph.for_settlement(sid) as StreetGraph
	var out: Array = [[c + Vector2(0, 20), Vector2(0, -1)], [c + Vector2(20, -6), Vector2(-1, 0)], [c + Vector2(-18, 8), Vector2(1, 0)]]
	var g := float(plan["gates"][0])
	var dir := Vector2(cos(g), sin(g))
	var gp := c + dir * (float(plan["wall_radius"]) - 3.5)
	out.append([gp - dir * 22.0, dir])
	if graph.inn_door != Vector2.INF:
		out.append([graph.inn_door + graph.inn_facing * 14.0, -graph.inn_facing])
	var pl := UtilityBrain.places(sid, graph)
	if pl["shrine"] != Vector2.INF:
		var face: Vector2 = -(pl["shrine_face"] as Vector2)
		out.append([(pl["shrine"] as Vector2) + face * 16.0, -face])
	var yard := Schedule.spot(s, Schedule.Phase.TRAIN, 0, 1)
	out.append([yard + (c - yard).normalized() * 16.0, (yard - c).normalized()])
	var places := NpcWorld.places_of(sid)
	var stalls: PackedVector2Array = places.get("stalls", PackedVector2Array())
	if not stalls.is_empty():
		out.append([stalls[0] + (c - stalls[0]).normalized() * -14.0, (c - stalls[0]).normalized()])
	return out


func test_every_scene_can_be_staged_in_a_real_town() -> void:
	var sid := _town("Thornfield")
	assert_int(sid).is_greater_equal(0)
	NpcWorld.reset()
	NpcWorld.ensure_spots(sid)
	var director: Node3D = MicroEvents.new()
	add_child(director)
	var spots := _vantage_points(sid)
	var failed: Array = []
	var staged := 0
	for e: Dictionary in Catalog.POOL:
		var ok := false
		for pf: Array in spots:
			var scene := MicroScene.new()
			director.add_child(scene)
			if scene.setup(e, sid, 11, pf[0], pf[1], director):
				ok = true
				staged += 1
				assert_bool(scene.anchor != Vector2.INF).override_failure_message("%s: no anchor" % e["id"]).is_true()
				assert_int(scene.actors.size() + scene.extras.size()).override_failure_message("%s: empty cast" % e["id"]).is_greater(0)
				scene.finish()
				break
			scene.free()
		if not ok:
			failed.append(e["id"])
	assert_array(failed).override_failure_message("scenes that could not be staged anywhere: %s" % str(failed)).is_empty()
	assert_int(staged).is_equal(Catalog.POOL.size())
	director.free()
	NpcWorld.reset()


func test_the_town_places_the_scenes_rely_on_exist() -> void:
	var sid := _town("Thornfield")
	NpcWorld.reset()
	NpcWorld.ensure_spots(sid)
	var places := NpcWorld.places_of(sid)
	assert_int((places["stalls"] as PackedVector2Array).size()).is_equal(12)
	assert_int((places["stall_yaw"] as PackedFloat32Array).size()).is_equal(12)
	assert_int((places["benches"] as PackedVector2Array).size()).is_greater(0)
	assert_int((places["patrol"] as PackedVector2Array).size()).is_greater(2)
	assert_bool(NpcWorld.bread_stall(sid).is_empty()).is_false()
	assert_int(NpcWorld.queue_spot(sid, 5).size()).is_equal(2)
	var graph := StreetGraph.for_settlement(sid) as StreetGraph
	var pl := UtilityBrain.places(sid, graph)
	assert_int((pl["eaves"] as PackedVector2Array).size()).is_greater(10)
	NpcWorld.reset()
