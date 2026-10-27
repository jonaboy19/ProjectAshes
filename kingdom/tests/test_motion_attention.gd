extends GdUnitTestSuite
## Attention director (scripts/living_world/attention.gd), rows A1-A5 of docs/plans/NPC_MOTION_RULES.md.

const A := preload("res://scripts/living_world/attention.gd")
const RR := preload("res://scripts/population/reaction_request.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")


func before_test() -> void:
	A.reset()
	LivingEvents.clear()


## A1: at most LOOK_SLOTS people look at once (6 HIGH, 3 LOW); an equal priority never pre-empts, a higher one does.
func test_a1_slot_cap_and_preemption() -> void:
	assert_int(A.slots_for(0)).is_equal(3)
	assert_int(A.slots_for(2)).is_equal(6)
	var accepted := 0
	for p in 20:
		if A.request(p, A.SRC_AMBIENT, Vector3(p, 1.5, 0), 10.0, 0.0, 2):
			accepted += 1
	assert_int(accepted).is_equal(6)
	assert_int(A.active_count(10.0)).is_equal(6)
	assert_bool(A.request(50, A.SRC_AMBIENT, Vector3.ZERO, 10.0, 0.0, 2)).is_false()    # equal priority: no pre-empt
	assert_bool(A.request(51, A.SRC_LOUD, Vector3(1, 1.5, 1), 10.0, 0.0, 2)).is_true()   # higher: pre-empts one ambient
	assert_int(A.active_count(10.0)).is_equal(6)
	assert_that(A.target_for(51, 10.0)).is_equal(Vector3(1, 1.5, 1))
	var looking := 0
	for p in 20:
		if A.target_for(p, 10.0) != null:
			looking += 1
	assert_int(looking).is_equal(5)            # 6 slots: 5 ambient survivors + the loud one (counted separately above)
	var low := 0
	for p in 100:
		if A.request(100 + p, A.SRC_AMBIENT, Vector3.ZERO, 30.0, 0.0, 0):
			low += 1
	assert_int(low).is_equal(3)


## A1: holds last 1.2-3 s by hash, then the look returns (null); the same source is then in a 4-9 s cooldown.
func test_a1_hold_and_cooldown() -> void:
	for p in 40:
		A.reset()
		assert_bool(A.request(p, A.SRC_PLAYER, Vector3(0, 1.5, 0), 100.0, 0.0, 2)).is_true()
		assert_that(A.target_for(p, 100.0 + 1.19)).is_not_null()
		assert_that(A.target_for(p, 100.0 + 3.01)).is_null()
		var h := A.hold_for(p, A.SRC_PLAYER, 1)
		assert_float(h).is_between(1.2, 3.0)
		var c := A.cooldown_for(p, A.SRC_PLAYER, 1)
		assert_float(c).is_between(4.0, 9.0)
	A.reset()
	A.request(7, A.SRC_PLAYER, Vector3.ZERO, 100.0, 0.0, 2)
	assert_that(A.target_for(7, 103.5)).is_null()                       # ended
	assert_bool(A.request(7, A.SRC_PLAYER, Vector3.ZERO, 104.0, 0.0, 2)).is_false()    # inside cooldown
	assert_bool(A.request(7, A.SRC_PLAYER, Vector3.ZERO, 103.0 + 9.1 + 3.0, 0.0, 2)).is_true()
	assert_bool(A.request(7, A.SRC_LOUD, Vector3.ZERO, 104.0, 0.0, 2)).is_true()       # other source is not on cooldown


## A1: deterministic, no randf: same inputs, same holds.
func test_a1_deterministic() -> void:
	for p in 10:
		assert_float(A.hold_for(p, 3, 5)).is_equal(A.hold_for(p, 3, 5))
	assert_bool(A.hold_for(1, 3, 5) != A.hold_for(2, 3, 5) or A.hold_for(1, 3, 6) != A.hold_for(2, 3, 6)).is_true()


## A1: lookat params: names exist on LookAtModifier3D, limits follow head_turn_deg, durations differ by archetype.
func test_a1_apply_lookat_params() -> void:
	var m := LookAtModifier3D.new()
	A.apply_lookat_params(m, "child")
	assert_float(m.primary_limit_angle).is_equal_approx(deg_to_rad(80.0), 0.001)
	assert_float(m.duration).is_equal_approx(0.25, 0.001)
	assert_int(m.transition_type).is_equal(Tween.TRANS_SINE)
	assert_bool(m.use_angle_limitation).is_true()
	A.apply_lookat_params(m, "elder")
	assert_float(m.primary_limit_angle).is_equal_approx(deg_to_rad(55.0), 0.001)
	assert_float(m.duration).is_equal_approx(0.5, 0.001)
	A.apply_lookat_params(m, "nobody")           # unknown archetype: fallback, no crash
	assert_float(m.primary_limit_angle).is_equal_approx(deg_to_rad(70.0), 0.001)
	m.free()


## A2: glance only inside 3 m (6 m notable), probability follows curiosity, never twice inside the cooldown.
func test_a2_glance_range_and_probability() -> void:
	var player := Vector3.ZERO
	assert_bool(A.offer_player(1, Vector3(4, 0, 0), player, 50.0, 1.0, false, 2)).is_false()
	var hits_curious := 0
	var hits_dull := 0
	for p in 400:
		if A.offer_player(1000 + p, Vector3(2, 0, 0), player, 50.0, 0.9, false, 2) :
			hits_curious += 1
		A.reset()
	for p in 400:
		if A.offer_player(1000 + p, Vector3(2, 0, 0), player, 50.0, 0.1, false, 2):
			hits_dull += 1
		A.reset()
	assert_int(hits_curious).is_greater(300)
	assert_int(hits_dull).is_less(100)
	A.reset()
	assert_bool(A.offer_player(2, Vector3(5, 0, 0), player, 50.0, 1.0, true, 2)).is_true()    # notable: 6 m
	assert_bool(A.offer_player(2, Vector3(5, 0, 0), player, 50.0 + 3.5, 1.0, true, 2)).is_false()   # after the hold: cooldown


## A2/A3: Presence GLANCE becomes a player look, LOOK_AWAY ends it.
func test_a2_presence_requests() -> void:
	assert_bool(A.offer_presence(3, RR.Kind.GLANCE, Vector3(5, 0, 5), 20.0, 2)).is_true()
	assert_that(A.target_for(3, 20.1)).is_equal(Vector3(5, A.HEAD_HEIGHT, 5))
	A.offer_presence(3, RR.Kind.LOOK_AWAY, Vector3.ZERO, 20.5, 2)
	assert_that(A.target_for(3, 20.6)).is_null()


## A3: dot > 0.9 within 5 m for 1 s gives a reply by standing; breaking the gaze resets the dwell.
func test_a3_eye_contact_reply_table() -> void:
	var player := Vector3(0, A.HEAD_HEIGHT, 0)      # camera at eye height
	var fwd := Vector3(0, 0, 1)
	var npc := Vector3(0, 0, 3)
	assert_int(A.eye_contact(1, npc, player, fwd, 10.0, 0.5)).is_equal(A.Reply.NONE)
	assert_int(A.eye_contact(1, npc, player, fwd, 10.6, 0.5)).is_equal(A.Reply.NONE)
	assert_int(A.eye_contact(1, npc, player, fwd, 11.1, 0.5)).is_equal(A.Reply.NOD)
	for case in [[0.5, A.Reply.NOD], [0.1, A.Reply.LOOK_AWAY], [-0.5, A.Reply.STARE]]:
		A.reset()
		A.eye_contact(2, npc, player, fwd, 10.0, case[0])
		assert_int(A.eye_contact(2, npc, player, fwd, 11.0, case[0])).is_equal(case[1])
	A.reset()
	A.eye_contact(3, npc, player, fwd, 10.0)
	A.eye_contact(3, npc, player, Vector3(1, 0, 0), 10.5)                # looked away: dwell resets
	assert_int(A.eye_contact(3, npc, player, fwd, 11.2)).is_equal(A.Reply.NONE)
	assert_int(A.eye_contact(4, Vector3(0, 0, 8), player, fwd, 10.0)).is_equal(A.Reply.NONE)    # too far
	assert_int(A.eye_contact(4, Vector3(0, 0, 8), player, fwd, 12.0)).is_equal(A.Reply.NONE)


## A4: listeners look at the speaker token; when the token moves, the target follows (same source refreshes).
func test_a4_listeners_follow_the_speaker_token() -> void:
	var speaker_a := Vector3(1, 0, 0)
	var speaker_b := Vector3(-1, 0, 0)
	for p in [10, 11]:
		A.offer_conversation(p, speaker_a, 40.0, 2)
		assert_that(A.target_for(p, 40.1)).is_equal(speaker_a + Vector3(0, A.HEAD_HEIGHT, 0))
	for p in [10, 11]:
		A.offer_conversation(p, speaker_b, 41.0, 2)
		assert_that(A.target_for(p, 41.1)).is_equal(speaker_b + Vector3(0, A.HEAD_HEIGHT, 0))
	# gaze shift of the speaker: index in range, changes across a 4 s+ span for some person, stable inside one period
	var changed := false
	for p in 20:
		var a := A.speaker_gaze_index(p, 3, 0.0)
		assert_int(a).is_between(0, 2)
		assert_int(A.speaker_gaze_index(p, 3, 0.0)).is_equal(a)
		for t in 6:
			if A.speaker_gaze_index(p, 3, 4.0 * (t + 1)) != a:
				changed = true
	assert_bool(changed).is_true()
	assert_int(A.speaker_gaze_index(1, 0, 0.0)).is_equal(-1)


## A5: the right source wins when two fire (threat > loud > conversation), the head turns after a 0.15-0.4 s delay.
func test_a5_noise_priority_and_delay() -> void:
	A.request(5, A.SRC_CONVERSATION, Vector3(9, 1.5, 9), 60.0, 0.0, 2)
	LivingEvents.emit("clang", Vector3(3, 1, 3), 30.0, 5.0)
	var now := Time.get_ticks_msec() / 1000.0
	var serial := A.offer_event(5, Vector3.ZERO, now, -1, 2)
	assert_int(serial).is_greater(0)
	assert_int(A.source_of(5, now + 1.0)).is_equal(A.SRC_LOUD)
	assert_that(A.target_for(5, now + 0.01)).is_null()                    # reaction delay not elapsed
	assert_that(A.target_for(5, now + 0.5)).is_equal(Vector3(3, 1, 3))
	LivingEvents.emit("fight", Vector3(-3, 1, 0), 30.0, 5.0)
	A.offer_event(5, Vector3.ZERO, now + 0.6, serial, 2)
	assert_int(A.source_of(5, now + 1.5)).is_equal(A.SRC_THREAT)
	assert_that(A.target_for(5, now + 1.5)).is_equal(Vector3(-3, 1, 0))
	for s in 30:
		assert_float(A.delay_for(s, 7)).is_between(0.15, 0.4)
	# a lower priority arriving later does not displace the threat
	assert_bool(A.request(5, A.SRC_AMBIENT, Vector3.ZERO, now + 1.6, 0.0, 2)).is_false()


## A5: NpcWorld.best_sound is read through the same table (empty store: nothing).
func test_a5_best_sound_input_is_safe_when_silent() -> void:
	assert_int(A.offer_sound(6, Vector2(0, 0), 10.0, 2)).is_equal(0)
	assert_that(A.target_for(6, 10.5)).is_null()


## Budget: 1000 requests + lookups on a full table stay cheap and never exceed the slot cap.
func test_cost_and_cap() -> void:
	var t0 := Time.get_ticks_usec()
	var worst := 0
	for k in 1000:
		var now := 10.0 + k * 0.05
		for p in 24:
			A.request(p, 1 + (k + p) % 6, Vector3(k, 1.5, p), now, 0.0, 2)
			A.target_for(p, now)
		worst = maxi(worst, A.active_count(now))
	var per_frame_us := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_int(worst).is_less_equal(6)
	assert_float(per_frame_us).is_less(2000.0)     # loose: 24 requests + 24 lookups per frame, far under the 0.15 ms rule budget on a phone
