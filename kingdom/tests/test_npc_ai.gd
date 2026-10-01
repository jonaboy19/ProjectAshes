extends GdUnitTestSuite
## Near-NPC AI: what the utility brain chooses in given situations (purpose and reactions), short-term
## avoidance memory, the shared awareness (incidents, fields, carts), smart object filters and the cost of
## 24 brains (scripts/population/utility_brain.gd, npc_world.gd).

const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Act := UtilityBrain.Act


func before_test() -> void:
	NpcWorld.reset()


func _winner(hour: float, over: Dictionary = {}, traits: Dictionary = {}) -> String:
	return UtilityBrain.NAMES[UtilityBrain.best(UtilityBrain.make_context(hour, over, traits))]


# ---------------------------------------------------------------- purpose
func test_defaults_never_trigger_the_new_acts() -> void:
	# The original contexts (no trigger inputs) must behave exactly as before.
	for hour: float in [3.0, 7.5, 10.0, 12.5, 17.5, 20.0, 23.0]:
		var w := _winner(hour)
		assert_bool(w in ["sit", "play", "patrol", "hide", "protest", "alarm", "firefight", "chore"]).is_false()


func test_winded_people_sit_when_a_bench_is_free() -> void:
	var over := {"winded": 0.85, "seat": 1.0, "sched_market": 1.0, "sched_work": 0.0, "hungry": 0.1, "lonely": 0.1}
	assert_str(_winner(14.0, over)).is_equal("sit")
	over["seat"] = 0.0
	assert_str(_winner(14.0, over)).is_not_equal("sit")
	# Working people keep working; the night belongs to bed.
	assert_str(_winner(10.0, {"winded": 0.6, "seat": 1.0, "sched_work": 1.0})).is_equal("work")
	assert_str(_winner(23.5, {"winded": 0.9, "seat": 1.0, "tired": 0.8, "rest": 0.2})).is_equal("sleep")


func test_children_play_and_do_not_work() -> void:
	var kid := {"child": 1.0, "play_spot": 1.0, "sched_work": 1.0}
	assert_str(_winner(11.0, kid)).is_equal("play")
	assert_float(UtilityBrain.score(Act.WORK, UtilityBrain.make_context(11.0, kid))).is_equal(0.0)
	# No play patch, nothing to do: they do not turn into workers either.
	assert_str(_winner(11.0, {"child": 1.0, "play_spot": 0.0, "sched_work": 1.0})).is_not_equal("work")


func test_guards_alternate_between_patrol_and_standing_post() -> void:
	var on_post := {"guard": 1.0, "sched_work": 1.0, "patrol_turn": 0.0}
	var on_patrol := {"guard": 1.0, "sched_work": 1.0, "patrol_turn": 1.0}
	assert_str(_winner(11.0, on_post)).is_equal("work")
	assert_str(_winner(11.0, on_patrol)).is_equal("patrol")
	# Nobody else patrols.
	assert_float(UtilityBrain.score(Act.PATROL, UtilityBrain.make_context(11.0, {"sched_work": 1.0, "patrol_turn": 1.0}))).is_equal(0.0)


func test_church_at_service_time_only_for_the_pious() -> void:
	var devout := {"faithless": 0.8, "sched_work": 0.0}
	var at_mass := UtilityBrain.score(Act.PRAY, UtilityBrain.make_context(8.75, devout, {"pious": 0.9}))
	var at_noon := UtilityBrain.score(Act.PRAY, UtilityBrain.make_context(12.0, devout, {"pious": 0.9}))
	assert_float(at_mass).is_greater(at_noon)
	var sceptic := UtilityBrain.score(Act.PRAY, UtilityBrain.make_context(8.75, devout, {"pious": 0.1}))
	assert_float(at_mass).is_greater(sceptic * 3.0)


func test_chores_happen_in_the_morning_and_evening_near_home() -> void:
	var morning := UtilityBrain.score(Act.CHORE, UtilityBrain.make_context(7.5, {"chore_spot": 1.0, "sched_work": 0.0}))
	var noon := UtilityBrain.score(Act.CHORE, UtilityBrain.make_context(12.0, {"chore_spot": 1.0, "sched_work": 0.0}))
	var none := UtilityBrain.score(Act.CHORE, UtilityBrain.make_context(7.5, {"chore_spot": 0.0, "sched_work": 0.0}))
	assert_float(morning).is_greater(noon)
	assert_float(none).is_equal(0.0)


# ---------------------------------------------------------------- reactions
func test_drawn_weapon_makes_people_step_back_and_complain() -> void:
	assert_str(_winner(11.0, {"armed": 0.9, "sched_work": 1.0})).is_equal("protest")
	assert_str(_winner(11.0, {"armed": 0.1, "sched_work": 1.0})).is_equal("work")
	# A monster outranks the complaint.
	assert_str(_winner(11.0, {"armed": 0.9, "danger": 0.9})).is_equal("flee")


func test_witnessed_crime_sends_people_to_a_guard() -> void:
	assert_str(_winner(11.0, {"crime": 1.0, "sched_work": 1.0})).is_equal("alarm")
	assert_str(_winner(11.0, {"crime": 0.0, "sched_work": 1.0})).is_equal("work")
	# Guards respond too (their plan goes to the crime instead of to a guard).
	assert_str(_winner(11.0, {"crime": 1.0, "guard": 1.0, "sched_work": 1.0})).is_equal("alarm")


func test_hiding_after_a_scare_then_normal_life() -> void:
	assert_str(_winner(11.0, {"hide": 1.0, "sched_work": 1.0})).is_equal("hide")
	assert_str(_winner(11.0, {"hide": 0.0, "sched_work": 1.0})).is_equal("work")
	# Seeing the thing again beats hiding.
	assert_str(_winner(11.0, {"hide": 1.0, "danger": 0.95})).is_equal("flee")
	# Guards don't cower.
	assert_float(UtilityBrain.score(Act.HIDE, UtilityBrain.make_context(11.0, {"hide": 1.0, "guard": 1.0}))).is_equal(0.0)


func test_brave_people_fight_fires_cowards_watch() -> void:
	var brave := UtilityBrain.score(Act.FIREFIGHT, UtilityBrain.make_context(11.0, {"fire": 0.6, "brave": 1.0}))
	var timid := UtilityBrain.score(Act.FIREFIGHT, UtilityBrain.make_context(11.0, {"fire": 0.6, "brave": 0.1}))
	assert_float(brave).is_greater(timid * 2.0)
	assert_str(_winner(11.0, {"fire": 0.6, "brave": 1.0, "sched_work": 1.0})).is_equal("firefight")
	# Right next to the flames people run (danger input) rather than fetch water.
	assert_str(_winner(11.0, {"fire": 0.6, "brave": 1.0, "danger": 0.95})).is_equal("flee")


func test_rain_still_shelters_outdoor_workers() -> void:
	assert_str(_winner(10.0, {"sched_work": 1.0, "rain": 1.0, "rain_exposed": 1.0})).is_equal("shelter")


func test_gathering_around_a_spectacle() -> void:
	assert_str(_winner(15.0, {"spectacle": 1.0, "sched_work": 1.0}, {"sociable": 0.9})).is_equal("watch")


# ---------------------------------------------------------------- short-term memory
func test_danger_memory_is_avoided_then_forgotten() -> void:
	var b := UtilityBrain.new(31, 0)
	var spot := Vector2(100, 50)
	assert_bool(b.avoids(spot)).is_false()
	b.remember_danger(spot, 30.0)
	assert_bool(b.avoids(spot + Vector2(5, 0))).is_true()
	assert_bool(b.avoids(spot + Vector2(40, 0))).is_false()
	# Pushes away from the spot, harder the closer.
	var near := b.avoid_push(spot + Vector2(3, 0))
	var far := b.avoid_push(spot + Vector2(12, 0))
	assert_float(near.x).is_greater(0.0)
	assert_float(near.length()).is_greater(far.length())
	assert_bool(b.avoid_push(spot + Vector2(40, 0)) == Vector2.ZERO).is_true()
	# Expired entries no longer count.
	b.mem_until[0] = Time.get_ticks_msec() - 1
	b.mem_until[1] = 0
	b.mem_until[2] = 0
	assert_bool(b.avoids(spot)).is_false()


func test_memory_keeps_three_and_refreshes_repeats() -> void:
	var b := UtilityBrain.new(32, 0)
	b.remember_danger(Vector2(0, 0))
	b.remember_danger(Vector2(100, 0))
	b.remember_danger(Vector2(200, 0))
	b.remember_danger(Vector2(201, 1))         # repeat: refreshes the third, frees nothing else
	assert_bool(b.avoids(Vector2(0, 0))).is_true()
	assert_bool(b.avoids(Vector2(100, 0))).is_true()
	b.remember_danger(Vector2(300, 0))         # a fourth overwrites the oldest
	var kept := 0
	for x: float in [0.0, 100.0, 200.0, 300.0]:
		if b.avoids(Vector2(x, 0)):
			kept += 1
	assert_int(kept).is_equal(3)


func test_smart_object_search_skips_remembered_danger() -> void:
	var so := SmartObjects.new()
	var near_id := so.add("bench", Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	var far_id := so.add("bench", Transform3D(Basis.IDENTITY, Vector3(40, 0, 0)))
	var filter := {"act": "rest"}
	assert_int(int(so.find(Vector3.ZERO, filter, 80.0)[0])).is_equal(near_id)
	var avoid := PackedVector2Array([Vector2(12, 0)])
	assert_int(int(so.find(Vector3.ZERO, filter, 80.0, -1, avoid, 16.0)[0])).is_equal(far_id)
	var all_bad := PackedVector2Array([Vector2(12, 0), Vector2(40, 0)])
	assert_bool(so.find(Vector3.ZERO, filter, 80.0, -1, all_bad, 16.0).is_empty()).is_true()
	# Musicians' spots are kept for those who play.
	var mus := so.add("musician_spot", Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)))
	assert_int(int(so.find(Vector3.ZERO, {"act": "inn", "not_tags": ["music"]}, 80.0).size())).is_equal(0)
	assert_int(int(so.find(Vector3.ZERO, {"act": "inn"}, 80.0)[0])).is_equal(mus)


# ---------------------------------------------------------------- shared awareness
func test_incidents_fires_and_dousing() -> void:
	var at := Vector2(20, 20)
	var slot := NpcWorld.report(NpcWorld.Kind.FIRE, at, 25.0, 30.0)
	assert_bool(NpcWorld.incident_alive(slot)).is_true()
	assert_float(NpcWorld.fire_danger(at + Vector2(2, 0))).is_greater(0.8)
	assert_float(NpcWorld.fire_danger(at + Vector2(30, 0))).is_equal(0.0)
	# Further away it is an invitation to fetch water, not a reason to run.
	assert_float(NpcWorld.fire_interest(at + Vector2(2, 0))).is_equal(0.0)
	assert_float(NpcWorld.fire_interest(at + Vector2(20, 0))).is_greater(0.2)
	# A repeat report refreshes the same incident.
	assert_int(NpcWorld.report(NpcWorld.Kind.FIRE, at + Vector2(1, 0), 25.0, 30.0)).is_equal(slot)
	for i in 14:
		NpcWorld.douse(slot, 0.08)
	assert_bool(NpcWorld.incident_alive(slot)).is_false()
	assert_float(NpcWorld.fire_interest(at + Vector2(20, 0))).is_equal(0.0)


func test_screams_and_crimes_are_heard_with_distance() -> void:
	NpcWorld.report(NpcWorld.Kind.SCREAM, Vector2(0, 0), 28.0, 10.0, 1.0)
	assert_float(NpcWorld.alarm_at(Vector2(4, 0), NpcWorld.Kind.SCREAM)).is_greater(0.8)
	assert_float(NpcWorld.alarm_at(Vector2(20, 0), NpcWorld.Kind.SCREAM)).is_between(0.1, 0.5)
	assert_float(NpcWorld.alarm_at(Vector2(40, 0), NpcWorld.Kind.SCREAM)).is_equal(0.0)
	assert_float(NpcWorld.alarm_at(Vector2(4, 0), NpcWorld.Kind.FIRE)).is_equal(0.0)


func test_incident_store_never_grows_past_its_slots() -> void:
	for i in 100:
		NpcWorld.report(NpcWorld.Kind.FIGHT, Vector2(float(i) * 50.0, 0), 10.0, 20.0)
	var alive := 0
	for i in NpcWorld.SLOTS:
		if NpcWorld.incident_alive(i):
			alive += 1
	assert_int(alive).is_equal(NpcWorld.SLOTS)


func test_fields_push_non_farmers_out() -> void:
	NpcWorld.register_field(3, Vector2(100, 100), 0.0, Vector2(10, 10))
	assert_bool(NpcWorld.in_field(3, Vector2(105, 100))).is_true()
	assert_bool(NpcWorld.in_field(3, Vector2(130, 100))).is_false()
	assert_bool(NpcWorld.in_field(4, Vector2(105, 100))).is_false()
	var push := NpcWorld.field_push(3, Vector2(108, 100))
	assert_float(push.x).is_greater(0.0)      # out across the nearer (east) edge
	var out := NpcWorld.out_of_fields(3, Vector2(104, 100))
	assert_bool(NpcWorld.in_field(3, out, 0.4)).is_false()
	assert_bool(NpcWorld.field_push(3, Vector2(200, 200)) == Vector2.ZERO).is_true()


func test_people_step_aside_for_an_oncoming_cart() -> void:
	NpcWorld._mover_n = 0
	NpcWorld._push_mover(Vector2(0, 0), Vector2(3, 0))       # a cart rolling east
	var in_path := NpcWorld.mover_push(Vector2(8, 0.3))
	assert_float(in_path.length()).is_greater(0.3)
	assert_float(absf(in_path.y)).is_greater(0.1)              # sideways, off its line
	assert_bool(NpcWorld.mover_push(Vector2(8, 9)) == Vector2.ZERO).is_true()    # well clear
	assert_bool(NpcWorld.mover_push(Vector2(-8, 0)) == Vector2.ZERO).is_true()   # behind it
	NpcWorld._mover_n = 0
	NpcWorld._push_mover(Vector2(0, 0), Vector2(0.1, 0))     # parked
	assert_bool(NpcWorld.mover_push(Vector2(1, 0)) == Vector2.ZERO).is_true()
	NpcWorld._mover_n = 0


func test_drawn_weapon_pressure_is_close_range_only() -> void:
	NpcWorld._player_pos = Vector2(0, 0)
	assert_float(NpcWorld.armed_pressure(Vector2(1, 0))).is_equal(0.0)   # sheathed
	NpcWorld.set_weapon_drawn(true)
	assert_float(NpcWorld.armed_pressure(Vector2(1.5, 0))).is_greater(0.95)
	assert_float(NpcWorld.armed_pressure(Vector2(5, 0))).is_between(0.1, 0.9)
	assert_float(NpcWorld.armed_pressure(Vector2(12, 0))).is_equal(0.0)
	NpcWorld.set_weapon_drawn(false)
	assert_float(NpcWorld.armed_pressure(Vector2(1.5, 0))).is_equal(0.0)


func test_lines_are_deterministic_and_categorised() -> void:
	assert_str(NpcWorld.line("flee", 12, 3)).is_equal(NpcWorld.line("flee", 12, 3))
	assert_str(NpcWorld.line("flee", 12, 3)).is_not_empty()
	assert_bool(NpcWorld.LINES["crime"].has(NpcWorld.line("crime", 7))).is_true()
	assert_str(NpcWorld.line("no_such_category", 1)).is_empty()


func test_decision_budget_slices_frames() -> void:
	var granted := 0
	for i in 20:
		if NpcWorld.take_decide_budget():
			granted += 1
	assert_int(granted).is_equal(NpcWorld.DECIDE_PER_FRAME)


func _age_chat_waiters(sid: int) -> void:
	for w: Dictionary in UtilityBrain._chat_wait.get(sid, []):
		w["since_ms"] = int(w["since_ms"]) - UtilityBrain.CHAT_MIN_WAIT_MS - 1


func test_three_can_chat_together() -> void:
	var a := auto_free(Node3D.new()) as Node3D
	var b := auto_free(Node3D.new()) as Node3D
	var c := auto_free(Node3D.new()) as Node3D
	UtilityBrain.register_body(910001, a)
	UtilityBrain.register_body(910002, b)
	UtilityBrain.register_body(910003, c)
	var sid := 77
	# Find a pair that stays open for a third (two in three do).
	UtilityBrain.chat_join(sid, 910001, Vector2(0, 0))
	_age_chat_waiters(sid)   # Codex: a waiter must have waited CHAT_MIN_WAIT_MS before pairing
	var second := UtilityBrain.chat_join(sid, 910002, Vector2(5, 0))
	assert_int(int(second[1])).is_equal(910001)
	_age_chat_waiters(sid)
	if UtilityBrain.chat_waiting(sid, 910003):
		var third := UtilityBrain.chat_join(sid, 910003, Vector2(9, 9))
		assert_int(int(third[1])).is_equal(910001)
		assert_float((third[0] as Vector2).distance_to(second[0])).is_greater(0.5)
	for p in [910001, 910002, 910003]:
		UtilityBrain.unregister_body(p)


# ---------------------------------------------------------------- cost
func test_24_brains_decide_cheaply() -> void:
	var brains: Array[UtilityBrain] = []
	for i in 24:
		var b := UtilityBrain.new(i, i % 6)
		b.seed_needs(11.0, 1)
		b.inp["child"] = 0.0
		b.inp["seat"] = 1.0
		b.inp["fire"] = 0.3
		b.inp["patrol_turn"] = float(i % 2)
		brains.append(b)
	var t0 := Time.get_ticks_usec()
	var decisions := 0
	for round_i in 50:
		for b in brains:
			var ctx := b.context(10.0 + float(round_i) * 0.1, 1, round_i % 10 == 0, 0.0, 0.0, false, 0.5, 1)
			b.decide(ctx, false)
			decisions += 1
	var per := float(Time.get_ticks_usec() - t0) / float(decisions)
	# A full decision (21 acts) stays well under a tenth of a millisecond; with the brain's 0.9 s cadence
	# 24 villagers spend well under 1 ms per second.
	assert_float(per).is_less(400.0)
	# A decision reuses its context dictionary: no allocation per decision.
	var b0 := brains[0]
	assert_bool(is_same(b0.context(10.0, 1, false, 0.0, 0.0, false, 0.5), b0.context(11.0, 1, false, 0.0, 0.0, false, 0.5))).is_true()


# ---------------------------------------------------------------- sensing pipeline (a hostile in plain sight scares)
func test_a_hostile_in_the_open_is_seen_and_feared() -> void:
	var viewer := CharacterBody3D.new()
	var beast := CharacterBody3D.new()
	beast.add_to_group("team1")
	beast.add_to_group("combatant")
	get_tree().root.add_child(viewer)
	get_tree().root.add_child(beast)
	viewer.global_position = Vector3(0, 0, 0)
	beast.global_position = Vector3(4, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var b := UtilityBrain.new(41, 0)
	UtilityBrain._sense_ms = -100000
	UtilityBrain._ray_window_ms = -100000
	var seen := 0
	var danger := 0.0
	for i in 5:
		var out := b.sense_threats(viewer, get_tree(), 1)
		var vis: PackedVector2Array = out.get("remembered", out["visible"])
		seen += vis.size()
		var d: Array = b.remembered_danger(Vector2(0, 0), vis, int(out.get("observed_ms", -1)))
		danger = maxf(danger, float(d[0]))
		await get_tree().physics_frame
	viewer.queue_free()
	beast.queue_free()
	assert_int(seen).is_greater(0)
	assert_float(danger).is_greater(0.7)
