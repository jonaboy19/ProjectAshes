extends GdUnitTestSuite
## NPC perception (scripts/population/perception.gd): vision table, analytic light and its 4 Hz cache, the alert
## scalar (classes, decay, one-step drops, grace), hearing with occlusion classes, determinism, and cost.

const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const Cls := Perception.Cls

const NPC := Vector2(0, 0)
const FACING := Vector2(0, 1)       # looking along +z


func before_test() -> void:
	NpcWorld.reset()
	Perception.reset()


func _at(d: float) -> Vector2:
	return Vector2(0, d)


# ---------------------------------------------------------------- vision table
func test_vision_falls_with_distance_and_needs_the_cone() -> void:
	var near := Perception.vis(NPC, FACING, _at(4.0), 1.0)
	var mid := Perception.vis(NPC, FACING, _at(14.0), 1.0)
	var far := Perception.vis(NPC, FACING, _at(30.0), 1.0)
	assert_float(near).is_greater(mid)
	assert_float(mid).is_greater(far)
	assert_float(far).is_equal(0.0)
	# Behind the observer nothing is seen; the edge of the cone is partial.
	assert_float(Perception.vis(NPC, FACING, _at(-4.0), 1.0)).is_equal(0.0)
	var edge := Perception.vis(NPC, FACING, Vector2(sin(deg_to_rad(90.0)), cos(deg_to_rad(90.0))) * 4.0, 1.0)
	assert_float(edge).is_greater(0.0)
	assert_float(edge).is_less(near)


func test_light_and_stance_are_the_stealth_levers() -> void:
	var lit := Perception.vis(NPC, FACING, _at(10.0), 1.0)
	var dim := Perception.vis(NPC, FACING, _at(10.0), 0.2)
	assert_float(lit).is_greater(dim)
	var walk := Perception.vis(NPC, FACING, _at(8.0), 0.8, Perception.STANCE_WALK)
	var crouch := Perception.vis(NPC, FACING, _at(8.0), 0.8, Perception.STANCE_CROUCH)
	var run := Perception.vis(NPC, FACING, _at(8.0), 0.8, Perception.STANCE_RUN)
	assert_float(crouch).is_less(walk)
	assert_float(run).is_greater(walk)
	# Still and dark: the range collapses to 8 m (Amnesia-style rule).
	assert_float(Perception.vis(NPC, FACING, _at(10.0), 0.25, 1.0, true)).is_equal(0.0)
	# Guards see further than drunks.
	var guard := Perception.vis(NPC, FACING, _at(24.0), 1.0, 1.0, false, 1.3)
	var drunk := Perception.vis(NPC, FACING, _at(24.0), 1.0, 1.0, false, 0.5)
	assert_float(guard).is_greater(drunk)


# ---------------------------------------------------------------- light
func test_light_by_hour_lamps_and_lantern() -> void:
	Perception.set_environment(13.0)
	var noon := Perception.light_uncached(Vector2(50, 50))
	Perception.set_environment(1.0)
	var night := Perception.light_uncached(Vector2(50, 50))
	assert_float(noon).is_greater(0.9)
	assert_float(night).is_less(0.25)
	Perception.register_light(Vector2(50, 52), 8.0, 0.6)
	var lamp := Perception.light_uncached(Vector2(50, 50))
	assert_float(lamp).is_greater(night + 0.2)
	# Far from the lamp it is dark again; the lantern lights the player anywhere.
	assert_float(Perception.light_uncached(Vector2(200, 200))).is_less(0.25)
	Perception.set_environment(1.0, 0.0, false, true)
	assert_float(Perception.light_uncached(Vector2(200, 200))).is_greater(0.35)
	Perception.set_environment(13.0, 1.0)
	assert_float(Perception.light_uncached(Vector2(0, 0))).is_less(noon)


func test_light_is_cached_at_4hz() -> void:
	Perception.set_environment(13.0)
	var p := Vector2(10, 10)
	Perception.light_at(p, 1000)
	var evals := Perception.light_evals
	for t in range(1001, 1240, 20):
		Perception.light_at(p + Vector2(0.1, 0), t)
	assert_int(Perception.light_evals).is_equal(evals)
	Perception.light_at(p, 1300)
	assert_int(Perception.light_evals).is_equal(evals + 1)


# ---------------------------------------------------------------- alert scalar
func _run(distance: float, light: float, stance: float, seconds: float, factor := 1.0, slot := 0) -> float:
	## Seconds until the class first reaches NOTICE (INF when never).
	var t := 0.0
	var ms := 0
	while t < seconds:
		var v := Perception.vis(NPC, FACING, _at(distance), light, stance)
		Perception.update(slot, v, factor, _at(distance), ms, 0.3)
		if Perception.class_of(slot) >= Cls.NOTICE:
			return t
		t += 0.3
		ms += 300
	return INF


func test_crouched_in_shadow_is_never_noticed_but_a_lit_runner_is_quick() -> void:
	var slot := Perception.bind(1)
	assert_float(_run(10.0, 0.2, Perception.STANCE_CROUCH, 20.0, 1.0, slot)).is_equal(INF)
	Perception.unbind(1)
	slot = Perception.bind(2)
	var t := _run(10.0, 0.5, Perception.STANCE_RUN, 5.0, 1.0, slot)
	assert_float(t).is_less(1.5)


func test_ordinary_passer_by_never_gets_past_notice_and_civilians_cap_below_alarm() -> void:
	var slot := Perception.bind(3)
	for i in 200:
		Perception.update(slot, 1.0, Perception.SUSP_PLAIN, _at(3.0), i * 300, 0.3)
	assert_int(Perception.class_of(slot)).is_less(Cls.NOTICE)
	# A wanted man in plain view: civilians reach suspicious, guards reach alarmed.
	var civ := Perception.bind(4, 1.0, false)
	var grd := Perception.bind(5, 1.3, true)
	for i in 200:
		Perception.update(civ, 1.0, 1.0, _at(3.0), i * 300, 0.3)
		Perception.update(grd, 1.0, 1.0, _at(3.0), i * 300, 0.3)
	assert_int(Perception.class_of(civ)).is_equal(Cls.SUSPICIOUS)
	assert_int(Perception.class_of(grd)).is_equal(Cls.ALARMED)


func test_classes_decay_one_step_at_a_time() -> void:
	var slot := Perception.bind(6)
	Perception.stimulate(slot, 25.0, _at(5.0), 0, 0)
	assert_int(Perception.class_of(slot)).is_equal(Cls.ALARMED)
	# Calm: the scalar falls fast but the class only one step per DROP_GAP_MS.
	var seen: Array = []
	var ms := 0
	for i in 400:
		ms += 300
		Perception.update(slot, 0.0, 1.0, Vector2.INF, ms, 0.3)
		var c := Perception.class_of(slot)
		if seen.is_empty() or seen[-1] != c:
			seen.append(c)
	assert_array(seen).is_equal([Cls.ALARMED, Cls.SEARCHING, Cls.SUSPICIOUS, Cls.NOTICE, Cls.CALM])


func test_grace_ignores_a_repeat_of_the_same_source_and_ring_remembers_ids() -> void:
	var slot := Perception.bind(7)
	assert_bool(Perception.stimulate(slot, 2.0, _at(3.0), 41, 1000)).is_true()
	assert_bool(Perception.stimulate(slot, 2.0, _at(3.0), 41, 1500)).is_false()
	assert_float(Perception.alert[slot]).is_equal(2.0)
	# After the grace window the same source counts again; a different one counts at once.
	assert_bool(Perception.stimulate(slot, 2.0, _at(3.0), 41, 1000 + Perception.GRACE_MS + 1)).is_true()
	assert_bool(Perception.stimulate(slot, 2.0, _at(3.0), 42, 1000 + Perception.GRACE_MS + 2)).is_true()
	assert_bool(Perception.knows(slot, 41)).is_true()
	assert_bool(Perception.knows(slot, 99)).is_false()


func test_slots_are_bounded_and_reused() -> void:
	for p in Perception.SLOTS:
		assert_int(Perception.bind(100 + p)).is_greater_equal(0)
	assert_int(Perception.bind(999)).is_equal(-1)
	Perception.unbind(100)
	assert_int(Perception.bind(999)).is_greater_equal(0)


func test_brain_inputs_map_classes_to_acts() -> void:
	var slot := Perception.bind(8)
	var inp := {}
	Perception.stimulate(slot, 7.0, _at(5.0), 0, 0)         # suspicious
	Perception.inputs(slot, inp, 0)
	assert_float(inp["a_susp"]).is_equal(1.0)
	var ctx := UtilityBrain.make_context(11.0, {"sched_work": 1.0}.merged(inp, true).merged({"nerve": 0.9}, true))
	assert_str(UtilityBrain.NAMES[UtilityBrain.best(ctx)]).is_equal("investigate")
	Perception.stimulate(slot, 4.0, _at(5.0), 1, 10)         # searching (11)
	Perception.inputs(slot, inp, 10)
	ctx = UtilityBrain.make_context(11.0, {"sched_work": 1.0}.merged(inp, true).merged({"nerve": 0.9}, true))
	assert_str(UtilityBrain.NAMES[UtilityBrain.best(ctx)]).is_equal("search")
	Perception.set_class_at_least(slot, Cls.NOTICE, _at(1.0), 20)
	var calm := UtilityBrain.make_context(11.0, {"sched_work": 1.0})
	assert_str(UtilityBrain.NAMES[UtilityBrain.best(calm)]).is_equal("work")
	# Timid people stare more than they investigate.
	var timid := UtilityBrain.make_context(11.0, {"sched_work": 1.0, "a_susp": 1.0, "nerve": 0.0})
	var bold := UtilityBrain.make_context(11.0, {"sched_work": 1.0, "a_susp": 1.0, "nerve": 1.0})
	assert_float(UtilityBrain.score(UtilityBrain.Act.INVESTIGATE, bold)).is_greater(UtilityBrain.score(UtilityBrain.Act.INVESTIGATE, timid))


# ---------------------------------------------------------------- hearing
func test_louder_and_nearer_sounds_alert_more_and_closed_doors_muffle() -> void:
	var src := Vector2(100, 100)
	Perception.emit_sound(Perception.Sound.BREAK_POTTERY, src, -1.0, "t", Perception.Occ.SAME_CELL)
	var near := float(Perception.hear(src + Vector2(3, 0), 0)[0])
	var far := float(Perception.hear(src + Vector2(14, 0), 0)[0])
	assert_float(near).is_greater(far)
	assert_float(far).is_greater(0.0)
	NpcWorld.clear_incidents()
	# Same sound, same listener 12 m away: open door > closed door > other building.
	var gains: Array = []
	for occ in [Perception.Occ.SAME_CELL, Perception.Occ.OPEN_DOOR, Perception.Occ.CLOSED_DOOR, Perception.Occ.OTHER_BUILDING]:
		NpcWorld.clear_incidents()
		Perception.emit_sound(Perception.Sound.BREAK_POTTERY, src, -1.0, "t", occ)
		gains.append(float(Perception.hear(src + Vector2(12, 0), 0)[0]))
	assert_float(gains[0]).is_greater_equal(gains[1])
	assert_float(gains[1]).is_greater(gains[2])
	assert_float(gains[2]).is_equal(0.0)      # 20 m x 0.35 = 7 m: not heard at 12 m
	assert_float(gains[3]).is_equal(0.0)


func test_footsteps_by_stance_and_kind_caps() -> void:
	var src := Vector2(0, 0)
	Perception.emit_sound(Perception.Sound.FOOTSTEP_CROUCH, src)
	assert_float(float(Perception.hear(Vector2(5, 0), 0)[0])).is_equal(0.0)     # 3 m loud: not heard at 5 m
	NpcWorld.clear_incidents()
	Perception.emit_sound(Perception.Sound.FOOTSTEP_RUN, src)
	assert_float(float(Perception.hear(Vector2(5, 0), 0)[0])).is_greater(0.0)
	NpcWorld.clear_incidents()
	Perception.emit_sound(Perception.Sound.SCREAM, src)
	var g := float(Perception.hear(Vector2(1, 0), 0)[0])
	assert_float(g).is_greater(5.0)
	assert_float(g).is_less_equal(float(Perception.SOUND_CAP[Perception.Sound.SCREAM]))


func test_listen_applies_once_per_event_and_marks_heard() -> void:
	var slot := Perception.bind(9)
	Perception.emit_sound(Perception.Sound.CLASH, Vector2(5, 0))
	assert_float(Perception.listen(slot, Vector2.ZERO, 1000)).is_greater(0.0)
	var a := Perception.alert[slot]
	assert_float(Perception.listen(slot, Vector2.ZERO, 1200)).is_equal(0.0)      # same event, in grace
	assert_float(Perception.alert[slot]).is_equal(a)
	var inp := {}
	Perception.inputs(slot, inp, 1500)
	assert_float(inp["heard"]).is_equal(1.0)
	# The apparent origin is fuzzed deterministically and stays close.
	var h1: Array = Perception.hear(Vector2.ZERO, slot)
	var h2: Array = Perception.hear(Vector2.ZERO, slot)
	assert_vector(h1[1]).is_equal(h2[1])
	assert_float((h1[1] as Vector2).distance_to(Vector2(5, 0))).is_less(2.0)


func test_determinism_same_inputs_same_alert_sequence() -> void:
	var seqs: Array = []
	for run in 2:
		Perception.reset()
		var slot := Perception.bind(11)
		var out: Array = []
		for i in 60:
			var v := Perception.vis(NPC, FACING, _at(6.0 + float(i % 7)), 0.6, 1.0)
			Perception.update(slot, v if i % 3 != 0 else 0.0, 0.8, _at(7.0), i * 300, 0.3)
			out.append(snappedf(Perception.alert[slot], 0.0001))
		seqs.append(out)
	assert_array(seqs[0]).is_equal(seqs[1])


# ---------------------------------------------------------------- cost
func test_cost_of_24_npcs_is_within_budget() -> void:
	Perception.set_environment(1.0)
	for i in 6:
		Perception.register_light(Vector2(float(i) * 9.0, 4.0), 8.0, 0.6)
	var slots: Array = []
	for p in 24:
		slots.append(Perception.bind(500 + p, 1.0, p % 8 == 0))
	var pp := Vector2(20, 20)
	var rounds := 200
	var t0 := Time.get_ticks_usec()
	for r in rounds:
		var now := r * 300
		for p in 24:
			var here := Vector2(float(p) * 1.7, float(p % 5) * 3.0)
			var v := Perception.vis(here, FACING, pp, Perception.light_at(pp, now), 1.0, false, 1.0)
			Perception.update(slots[p], v, 0.5, pp, now, 0.3)
			Perception.listen(slots[p], here, now)
	var usec_per_round := float(Time.get_ticks_usec() - t0) / float(rounds)
	# A round is every NPC thinking once; they think every 0.3 s = 18 frames, so per frame it is round / 18.
	var per_frame_ms := usec_per_round / 1000.0 / 18.0
	print("PERF perception: %.1f us per 24-NPC round, %.4f ms/frame average" % [usec_per_round, per_frame_ms])
	assert_float(per_frame_ms).is_less(0.5)
	assert_float(usec_per_round / 1000.0).is_less(5.0)     # even all in one frame, loose for slow CI
