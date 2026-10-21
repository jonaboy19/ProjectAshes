extends GdUnitTestSuite
## MW-37..41 Reactive Presence: stimuli from body behaviour, observer limits, staged response, reaction contract, perf.

const Presence := preload("res://scripts/population/presence.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const Adapter := preload("res://scripts/population/reaction_adapter.gd")
const F := Presence

var p: Presence

func before_test() -> void:
	p = Presence.new()
	p.stagger = 1

## Advance `secs` of game time in 250 ms ticks. `step` (optional) Callable(now_ms) moves bodies first.
func _run(secs: float, start_ms: int, step := Callable()) -> int:
	var now := start_ms
	var end := start_ms + int(secs * 1000.0)
	while now < end:
		now += 250
		if step.is_valid():
			step.call(now)
		p.tick(now)
	return now

func _staring(subject_head := Vector2(0, -1)) -> void:
	p.set_body(0, Vector2(0, 6), Vector2(0, -1), Vector2.ZERO, subject_head)

func _kinds(slot: int, upto := 20) -> Array:
	var out: Array = []
	for i in upto:
		var r: Array = p.requests.pop(slot)
		if r.is_empty():
			break
		out.append(r[0])
	return out

func test_stare_tolerance_differs_per_npc() -> void:
	p.set_body(1, Vector2(-1, 0), Vector2(0, 1))
	p.set_body(2, Vector2(1, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0})
	p.make_observer(2, {"tolerance": 1.0})
	_staring()
	_run(14.0, 0)
	assert_int(p.stage_of(1, 0)).is_equal(Presence.Stage.DECIDE)
	assert_bool(p.stage_of(2, 0) < Presence.Stage.DECIDE).is_true()
	assert_int(p.stage_of(2, 0)).is_greater(0)   # the patient one still noticed

func test_facing_away_never_reacts() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0})
	_staring(Vector2(0, 1))                      # subject head turned away
	_run(60.0, 0)
	assert_int(p.stage_of(1, 0)).is_equal(0)
	assert_int(p.requests.pending_count(p.slot_of(1))).is_equal(0)
	# observer looking away cannot see the stare either
	p.set_body(1, Vector2(0, 0), Vector2(0, -1))
	_staring()
	_run(60.0, 100000)
	assert_int(p.stage_of(1, 0)).is_equal(0)
	assert_int(p.requests.pending_count(p.slot_of(1))).is_equal(0)

func test_follow_detection_stages() -> void:
	p.make_observer(1, {"tolerance": 0.0})
	var v := Vector2(1.4, 0)
	var seen: Array = []
	var step := func(now: int) -> void:
		var t := now / 1000.0
		p.set_body(1, Vector2(t * 1.4, 0), Vector2(1, 0), v)
		p.set_body(0, Vector2(t * 1.4 - 4.0, 0), Vector2(1, 0), v)
		var st := p.stage_of(1, 0)
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
	_run(40.0, 0, step)
	assert_array(seen).contains([1, 2, 3, 4])
	var ks := _kinds(p.slot_of(1))
	assert_bool(ks.has(RR.Kind.GLANCE)).is_true()
	assert_bool(ks.has(RR.Kind.STEP_ASIDE)).is_true()      # the "test": let them pass
	# before the decision everything keeps the current activity
	for k in ks.slice(0, ks.size() - 1):
		assert_bool(RR.KEEPS_ACTIVITY[k]).is_true()
	# a walker going the other way is no follower
	p.clear()
	p.make_observer(1, {"tolerance": 0.0})
	var away := func(now: int) -> void:
		var t := now / 1000.0
		p.set_body(1, Vector2(t * 1.4, 0), Vector2(1, 0), v)
		p.set_body(0, Vector2(-t * 1.4 - 4.0, 0), Vector2(-1, 0), -v)
	_run(30.0, 0, away)
	assert_int(p.stage_of(1, 0)).is_equal(0)

func test_drawn_weapon_in_tavern() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO, F.F_PUBLIC)
	p.make_observer(1, {"tolerance": 0.0, "persona": {"courage": 0.2}})
	p.set_body(0, Vector2(0, 5), Vector2(0, -1), Vector2.ZERO, Vector2.ZERO, F.F_DRAWN)
	_run(2.0, 0)
	assert_int(p.stage_of(1, 0)).is_equal(Presence.Stage.DECIDE)
	var ks := _kinds(p.slot_of(1))
	assert_int(ks[0]).is_equal(RR.Kind.FLINCH)
	assert_int(ks[-1]).is_equal(RR.Kind.FLEE)               # timid, no guard nearby
	# same weapon outdoors is only tense, not yet decided at the same moment
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0})
	p.set_body(0, Vector2(0, 5), Vector2(0, -1), Vector2.ZERO, Vector2.ZERO, F.F_DRAWN)
	_run(2.0, 0)
	assert_bool(p.stage_of(1, 0) < Presence.Stage.DECIDE).is_true()
	# a guard nearby changes the choice
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO, F.F_PUBLIC)
	p.make_observer(1, {"tolerance": 0.0, "guard_near": true})
	p.set_body(0, Vector2(0, 5), Vector2(0, -1), Vector2.ZERO, Vector2.ZERO, F.F_DRAWN)
	_run(2.0, 0)
	assert_int(_kinds(p.slot_of(1))[-1]).is_equal(RR.Kind.CALL_GUARD)

func test_de_escalation_apology_and_memory() -> void:
	p.make_observer(1, {"tolerance": 0.0})
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	_staring()
	var t1 := 0
	var now := 0
	while p.stage_of(1, 0) < Presence.Stage.DECIDE and now < 40000:
		now = _run(0.25, now)
	t1 = now
	assert_int(p.stage_of(1, 0)).is_equal(Presence.Stage.DECIDE)
	assert_int(p.memory_strikes(1, 0, now)).is_equal(1)
	_kinds(p.slot_of(1))
	# subject looks elsewhere / leaves: stages fall one at a time, then the NPC returns to work
	_staring(Vector2(0, 1))
	now = _run(25.0, now)
	assert_int(p.stage_of(1, 0)).is_equal(0)
	assert_int(p.tracked_count(1)).is_equal(0)
	assert_bool(_kinds(p.slot_of(1)).has(RR.Kind.RETURN_TO_WORK)).is_true()
	# memory: the second offence escalates sooner than the first did
	_staring()
	var start := now
	while p.stage_of(1, 0) < Presence.Stage.DECIDE and now < start + 40000:
		now = _run(0.25, now)
	assert_bool(now - start < t1).is_true()
	# an apology cools it at once
	p.apologise(0, 1, now)
	assert_bool(p.level_of(1, 0) < 0.5).is_true()
	assert_bool(_kinds(p.slot_of(1)).has(RR.Kind.RETURN_TO_WORK)).is_true()

func test_attention_budget_busy_and_two_target_cap() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0, "busy": 1.0})
	_staring()
	_run(60.0, 0)
	assert_int(p.tracked_count(1)).is_equal(0)                # a fully busy mind misses a stare
	p.set_body(0, Vector2(0, 5), Vector2(0, -1), Vector2.ZERO, Vector2.ZERO, F.F_DRAWN)
	p.set_body(1, Vector2(0, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO, F.F_PUBLIC)
	_run(3.0, 60000)
	assert_int(p.tracked_count(1)).is_equal(1)                # ...but not a drawn blade
	# at most two targets for a free mind
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 1.0})
	for i in range(10, 15):
		p.set_body(i, Vector2((i - 12) * 0.5, 5), Vector2(0, -1), Vector2.ZERO, Vector2(0, -1))
	_run(10.0, 0)
	assert_int(p.tracked_count(1)).is_equal(2)

func test_npc_to_npc_observation() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1), Vector2.ZERO, Vector2.ZERO, F.F_PUBLIC)
	p.make_observer(1, {"tolerance": 0.0})
	p.set_body(5, Vector2(0, 5), Vector2(0, -1), Vector2.ZERO, Vector2.ZERO, F.F_DRAWN)   # an NPC, not the player
	p.make_observer(5, {"tolerance": 0.0})
	_run(2.0, 0)
	assert_int(p.stage_of(1, 5)).is_equal(Presence.Stage.DECIDE)
	var r: Array = p.requests.pop(p.slot_of(1))
	assert_int(r[1]).is_equal(5)                              # target = the NPC
	# NPCs are watchable by NPCs: stare between two NPCs
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0})
	p.set_body(5, Vector2(0, 6), Vector2(0, -1))
	_run(10.0, 0)
	assert_int(p.stage_of(1, 5)).is_greater(0)

func test_status_dependent_choice() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0, "persona": {"courage": 0.8}})
	_staring()
	_run(14.0, 0)
	assert_int(_kinds(p.slot_of(1))[-1]).is_equal(RR.Kind.CONFRONT)   # commoner stared at by a commoner
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0, "persona": {"courage": 0.8}})
	p.describe_subject(0, {"title_rank": 5, "insignia": 1.0, "origin": "caldrenn", "gear_value": 0.9})
	_staring()
	_run(14.0, 0)
	assert_int(_kinds(p.slot_of(1))[-1]).is_equal(RR.Kind.LOOK_AWAY)  # same stare from a lord
	# enemy insignia (church kingdom does not honour Caldrenn titles)
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0, "kingdom": "solmarch", "persona": {"courage": 0.8}})
	p.describe_subject(0, {"title_rank": 3, "insignia": 1.0, "origin": "caldrenn"})
	p.set_body(0, Vector2(0, 6), Vector2(0, -1), Vector2.ZERO, Vector2(0, 1))
	_run(14.0, 0)
	assert_bool(p.stage_of(1, 0) >= Presence.Stage.DECIDE).is_true()

func test_discrete_events_and_visits() -> void:
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.5})
	p.set_body(0, Vector2(0, 0.6), Vector2(0, -1))
	assert_int(p.report(Presence.Stim.BUMP, 0, 1.0, 1000)).is_equal(1)
	assert_int(p.stage_of(1, 0)).is_equal(Presence.Stage.DECIDE)
	p.clear()
	p.set_body(1, Vector2(0, 0), Vector2(0, 1))
	p.make_observer(1, {"tolerance": 0.0})
	p.set_body(0, Vector2(0, 3), Vector2(0, -1))
	p.report(Presence.Stim.KINDNESS, 0, 1.0, 1000)
	assert_int(_kinds(p.slot_of(1))[-1]).is_equal(RR.Kind.WAVE)
	for i in 4:
		p.note_visit(1, 0, 2000 + i)
	assert_int(p.visits(1, 0)).is_equal(4)

func test_reaction_contract_and_adapter() -> void:
	assert_int(RR.NAMES.size()).is_equal(13)
	assert_int(RR.Kind.RETURN_TO_WORK).is_equal(12)           # enum frozen
	assert_bool(RR.can_preempt(RR.Kind.GLANCE, 1000, RR.Kind.LOOK_AWAY, 500)).is_false()   # equal priority waits
	assert_bool(RR.can_preempt(RR.Kind.GLANCE, 1000, RR.Kind.FLINCH, 500)).is_true()
	assert_bool(RR.can_preempt(RR.Kind.WARN, 1000, RR.Kind.GLANCE, 1500)).is_true()         # expired
	var q := RR.new()
	assert_bool(q.request(3, RR.Kind.GLANCE, 9, 0)).is_true()
	assert_bool(q.request(3, RR.Kind.STEP_BACK, 9, 100)).is_true()           # other layer coexists
	assert_int(q.current(3, RR.Layer.HEAD, 200)).is_equal(RR.Kind.GLANCE)
	assert_int(Adapter.look_target(q, 3, 200)).is_equal(9)
	assert_bool(q.request(3, RR.Kind.FLEE, 9, 300)).is_true()
	assert_bool(q.request(3, RR.Kind.CONFRONT, 9, 400)).is_false()          # flee is exclusive
	assert_bool(q.pausing_activity(3, 500)).is_true()
	var got: Array = []
	var n := Adapter.new().consume(q, 3, func(slot, kind, target, info): got.append([kind, info["keeps_activity"]]))
	assert_int(n).is_equal(3)
	assert_bool(got[0][1]).is_true()
	assert_bool(got[2][1]).is_false()

func test_perf_30_near_npcs_and_far_tier_free() -> void:
	var idle := Presence.new()
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		idle.tick(i * 100)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)    # nothing registered = near-zero
	var pr := Presence.new()
	for i in 30:
		pr.set_body(i + 1, Vector2((i % 6) * 2.0, (i / 6) * 2.0), Vector2(0, 1), Vector2(0.5, 0))
		pr.make_observer(i + 1, {"busy": 0.3, "persona": {"courage": 0.5}})
	pr.set_body(0, Vector2(5, 12), Vector2(0, -1), Vector2(0, -1), Vector2(0, -1), F.F_RUNNING)
	var worst := 0
	var total := 0
	for k in 200:
		var s := Time.get_ticks_usec()
		pr.tick(k * 100)
		var e := Time.get_ticks_usec() - s
		total += e
		worst = maxi(worst, e)
	print("presence 30 NPC: avg %d us, worst %d us per tick" % [total / 200, worst])
	assert_int(total / 200).is_less(1500)
	assert_int(worst).is_less(6000)
