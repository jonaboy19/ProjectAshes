extends GdUnitTestSuite

const NpcWorld := preload("res://scripts/population/npc_world.gd")
var NO_CLIPS := PackedStringArray()
## NPC motion package M5: group_motion.gd. Rules G1-G4 and S7 of docs/plans/NPC_MOTION_RULES.md.


func after_test() -> void:
	ClipPicker.reset()


# --- G1: circle layout --------------------------------------------------------------------------

func test_g1_radius_formula() -> void:
	assert_float(GroupMotion.circle_radius(2)).is_equal_approx(1.05, 0.0001)
	assert_float(GroupMotion.circle_radius(5)).is_equal_approx(1.8, 0.0001)


func test_g1_slots_on_circle_no_overlap_open_side() -> void:
	var c := Vector2(10, -4)
	for n in range(2, 6):
		var open := Vector2(0.6, 0.8)
		var pts: Array[Vector2] = []
		for i in n:
			var p := GroupMotion.circle_slot(c, n, i, open)
			pts.append(p)
			assert_float(p.distance_to(c)).is_equal_approx(GroupMotion.circle_radius(n), 0.001)
		for i in n:
			for j in range(i + 1, n):
				assert_float(pts[i].distance_to(pts[j])).is_greater(1.75)
		# open side: nobody within 30% of the gap angle of the open direction
		var gap := TAU / float(n + 1)
		for p in pts:
			assert_float(absf(open.angle_to(p - c))).is_greater(gap * 0.5 - 0.001)


func test_g1_respace_on_join_and_leave() -> void:
	var c := Vector2.ZERO
	var open := Vector2(1, 0)
	var r3 := GroupMotion.circle_slot(c, 3, 0, open).length()
	var r4 := GroupMotion.circle_slot(c, 4, 0, open).length()
	assert_float(r4 - r3).is_equal_approx(GroupMotion.CIRCLE_PER, 0.001)
	assert_float(GroupMotion.circle_slot(c, 2, 0, open).length()).is_equal_approx(1.05, 0.001)


func test_g1_members_face_centre() -> void:
	var c := Vector2(3, 3)
	var p := GroupMotion.circle_slot(c, 3, 1, Vector2(0, 1))
	var f := Vector2(sin(GroupMotion.circle_yaw(c, p)), cos(GroupMotion.circle_yaw(c, p)))
	assert_float(f.dot((c - p).normalized())).is_equal_approx(1.0, 0.001)


func test_g1_turn_length_3_to_7_and_deterministic() -> void:
	for t in 200:
		var l := GroupMotion.turn_length(9, t)
		assert_float(l).is_between(3.0, 7.0)
		assert_float(l).is_equal(GroupMotion.turn_length(9, t))


func test_g1_token_fair_and_no_double_speaker() -> void:
	for n in range(2, 6):
		var counts: Array[int] = []
		counts.resize(n)
		var prev := -1
		for turn in n * 40:
			var s := GroupMotion.speaker_of(77, turn, n)
			assert_int(s).is_between(0, n - 1)
			assert_bool(s != prev).override_failure_message("n=%d turn %d repeats %d" % [n, turn, s]).is_true()
			prev = s
			counts[s] += 1
		if n == 2:
			continue
		for c in counts:
			assert_int(c).is_equal(40)   # every member exactly once per cycle


func test_g1_token_advances_with_time() -> void:
	var tk := GroupMotion.Token.new()
	tk.reset(5, 3, 100.0)
	var changes := 0
	var t := 100.0
	while t < 160.0:
		if tk.advance(t):
			changes += 1
		t += 0.25
	assert_int(tk.turn).is_between(8, 20)       # 60 s / 3..7 s
	assert_int(changes).is_equal(tk.turn)       # n >= 3 never repeats the speaker
	assert_float(tk.ends - tk.started).is_between(3.0, 7.0)


func test_g1_gaze_never_the_speaker_and_shifts() -> void:
	var seen := {}
	for k in 40:
		var g := GroupMotion.gaze_listener(3, 11, 4, 2, float(k) * 0.5)
		assert_int(g).is_between(0, 3)
		assert_int(g).is_not_equal(2)
		seen[g] = true
	assert_int(seen.size()).is_greater(1)


func test_g1_clip_queries_return_clips_for_speaker_and_listener() -> void:
	var q := {}
	GroupMotion.fill_clip_query(q, true, "happy", 2, 4)
	assert_str(ClipPicker.pick(q, {"id": 1}, NO_CLIPS, NO_CLIPS)).is_not_empty()
	GroupMotion.fill_clip_query(q, false, "calm", 2, 4)
	assert_str(ClipPicker.pick(q, {"id": 2}, NO_CLIPS, NO_CLIPS)).is_not_empty()
	assert_str(q["verb"]).is_equal("listen")


func test_g1_nod_window() -> void:
	var on := 0
	for k in 1000:
		if GroupMotion.nod_now(12, float(k) * 0.05):
			on += 1
	assert_int(on).is_between(100, 320)    # 0.8 s of every 2.5..5.5 s


# --- G2: families ---------------------------------------------------------------------------------

func test_g2_slots_beside_parent() -> void:
	var p := Vector2(5, 5)
	var a := GroupMotion.family_slot(p, 0.0, 0, 2)
	var b := GroupMotion.family_slot(p, 0.0, 1, 2)
	assert_float(a.distance_to(p)).is_equal_approx(0.6, 0.001)
	assert_float(b.distance_to(p)).is_equal_approx(0.6, 0.001)
	assert_float(a.x * b.x).is_less(p.x * p.x)  # opposite sides
	assert_float((a - p).x * (b - p).x).is_less(0.0)


func test_g2_child_never_leaves_leash() -> void:
	var parent := Vector2.ZERO
	for child in 6:
		for k in 600:
			var t := float(k) * 0.3
			var yaw := sin(t * 0.05) * 3.0
			var p := GroupMotion.child_target(parent, yaw, 100 + child, child % 3, 3, t)
			assert_float(p.distance_to(parent)).is_less_equal(GroupMotion.LEASH + 0.0001)


func test_g2_leash_clamp_and_run_hysteresis() -> void:
	var c := GroupMotion.leash_clamp(Vector2(10, 0), Vector2.ZERO)
	assert_float(c.length()).is_equal_approx(3.0, 0.0001)
	assert_vector(GroupMotion.leash_clamp(Vector2(1, 1), Vector2.ZERO)).is_equal(Vector2(1, 1))
	assert_bool(GroupMotion.child_running(2.6, false)).is_true()
	assert_bool(GroupMotion.child_running(1.8, true)).is_true()     # keeps running until close
	assert_bool(GroupMotion.child_running(1.8, false)).is_false()
	assert_bool(GroupMotion.child_running(0.8, true)).is_false()


func test_g2_child_reunites_after_a_corner() -> void:
	var parent := Vector2.ZERO
	var child := Vector2(0, -2.8)
	# parent turns the corner and is suddenly 6 m from the child: the clamp target is within the leash of the parent
	parent = Vector2(6, 0)
	assert_float(GroupMotion.leash_clamp(child, parent).distance_to(parent)).is_less_equal(3.0001)


# --- G3: guard phase lock -------------------------------------------------------------------------

func test_g3_phase_error_wraps() -> void:
	assert_float(GroupMotion.phase_error(0.1, 0.9, 1.0)).is_equal_approx(-0.2, 0.0001)
	assert_float(GroupMotion.phase_error(0.9, 0.1, 1.0)).is_equal_approx(0.2, 0.0001)
	assert_float(GroupMotion.phase_error(0.5, 0.5, 1.0)).is_equal_approx(0.0, 0.0001)


func test_g3_hard_seek_only_for_large_error() -> void:
	assert_float(GroupMotion.phase_seek(0.2, 0.3, 1.2)).is_equal(-1.0)
	var s := GroupMotion.phase_seek(0.2, 0.9, 1.2)
	assert_float(s).is_equal_approx(0.2, 0.0001)


func test_g3_phase_never_drifts_under_005() -> void:
	# Follower runs 3% slow for 120 s of 60 fps ticks; the correction must hold the error under 0.05 s.
	var len := 1.1
	var lt := 0.0
	var ft := 0.4
	var worst := 0.0
	var dt := 1.0 / 60.0
	for i in 7200:
		lt = fposmod(lt + dt, len)
		var seek := GroupMotion.phase_seek(lt, ft, len)
		if seek >= 0.0:
			ft = seek
		ft = fposmod(ft + dt * 0.97 * GroupMotion.phase_rate(lt, ft, len), len)
		if i > 600:
			worst = maxf(worst, absf(GroupMotion.phase_error(lt, ft, len)))
	assert_float(worst).is_less(0.05)


func test_g3_pair_slots_and_leg_pause() -> void:
	var l := Vector2(2, 2)
	assert_float(GroupMotion.pair_slot(l, 0.0, 0).distance_to(l)).is_equal(0.0)
	assert_float(GroupMotion.pair_slot(l, 0.0, 1).distance_to(l)).is_equal_approx(0.9, 0.0001)
	assert_int(GroupMotion.leg_pause(5.0, 20.0, 4.0)).is_equal(0)
	assert_int(GroupMotion.leg_pause(21.0, 20.0, 4.0)).is_equal(1)
	assert_int(GroupMotion.leg_pause(24.5, 20.0, 4.0)).is_equal(0)   # next leg


# --- G4: child orbit ------------------------------------------------------------------------------

func test_g4_orbit_radius_2_to_5_round_moving_anchor() -> void:
	for child in 30:
		for k in 200:
			var t := float(k) * 0.4
			var anchor := Vector2(t * 1.2, sin(t) * 3.0)
			var r := GroupMotion.orbit_point(anchor, child, t).distance_to(anchor)
			assert_float(r).is_between(2.0, 5.0)


func test_g4_orbit_differs_per_child_and_is_deterministic() -> void:
	var a := GroupMotion.orbit_point(Vector2.ZERO, 1, 10.0)
	assert_vector(a).is_equal(GroupMotion.orbit_point(Vector2.ZERO, 1, 10.0))
	assert_vector(a).is_not_equal(GroupMotion.orbit_point(Vector2.ZERO, 2, 10.0))


func test_g4_push_out_keeps_children_off_adults() -> void:
	var p := GroupMotion.push_out(Vector2(0.2, 0), Vector2.ZERO)
	assert_float(p.length()).is_equal_approx(0.7, 0.0001)
	assert_vector(GroupMotion.push_out(Vector2(2, 0), Vector2.ZERO)).is_equal(Vector2(2, 0))
	assert_float(GroupMotion.push_out(Vector2.ZERO, Vector2.ZERO).length()).is_equal_approx(0.7, 0.0001)


# --- S7: generic queue ----------------------------------------------------------------------------

func test_s7_line_spot_matches_npc_world_maths() -> void:
	assert_float(GroupMotion.QUEUE_GAP).is_equal(NpcWorld.QUEUE_GAP)
	var yaw := 0.7
	var front := Vector2(sin(yaw), cos(yaw))
	var stall := Vector2(4, 9)
	for idx in 5:
		var side := Vector2(-front.y, front.x)
		var expect: Vector2 = stall + front * (1.7 + float(idx) * NpcWorld.QUEUE_GAP) + side * (float(idx) * 0.18)
		assert_vector(GroupMotion.line_spot(stall, front, idx)).is_equal_approx(expect, Vector2(0.0001, 0.0001))


func test_s7_declared_places_then_extension() -> void:
	var decl := [[0.0, 0.0, 2.6], [0.6, 0.0, 3.4]]
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10, 0, 10))
	var p0 := GroupMotion.queue_slot(xf, decl, 0)
	var p1 := GroupMotion.queue_slot(xf, decl, 1)
	var p2 := GroupMotion.queue_slot(xf, decl, 2)
	var p3 := GroupMotion.queue_slot(xf, decl, 3)
	var w0 := xf * Vector3(0, 0, 2.6)
	assert_vector(p0).is_equal_approx(Vector2(w0.x, w0.z), Vector2(0.001, 0.001))
	assert_float(p2.distance_to(p1)).is_equal_approx(GroupMotion.QUEUE_GAP, 0.001)
	assert_float(p3.distance_to(p2)).is_equal_approx(GroupMotion.QUEUE_GAP, 0.001)
	var all := [p0, p1, p2, p3]
	for i in 4:
		for j in range(i + 1, 4):
			assert_float((all[i] as Vector2).distance_to(all[j])).is_greater(0.7)


func test_s7_no_declaration_uses_bread_line() -> void:
	var xf := Transform3D(Basis.IDENTITY, Vector3(3, 0, 4))
	var p := GroupMotion.queue_slot(xf, [], 2)
	var expect := GroupMotion.line_spot(Vector2.ZERO, Vector2(0, 1), 2) + Vector2(3, 4)
	assert_vector(p).is_equal_approx(expect, Vector2(0.001, 0.001))


func test_s7_queue_yaw_faces_object() -> void:
	var xf := Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))
	var spot := GroupMotion.queue_slot(xf, [], 0)
	var yaw := GroupMotion.queue_yaw(xf, spot)
	assert_float(sin(yaw)).is_equal_approx(0.0, 0.01)
	assert_float(cos(yaw)).is_less(0.0)   # looks back toward the object at -z from the line


func test_s7_fifo_no_two_in_one_slot_and_shuffle() -> void:
	var q := GroupMotion.Queue.new()
	assert_int(q.join(11, 0.0, 100.0)).is_equal(0)
	assert_int(q.join(12, 1.0, 100.0)).is_equal(1)
	assert_int(q.join(13, 2.0, 100.0)).is_equal(2)
	assert_int(q.join(12, 3.0, 100.0)).is_equal(1)      # re-join keeps the place
	assert_int(q.count).is_equal(3)
	assert_int(q.pop_front()).is_equal(11)
	assert_int(q.index_of(12)).is_equal(0)
	assert_int(q.index_of(13)).is_equal(1)
	var seen := {}
	for i in q.count:
		assert_bool(seen.has(q.people[i])).is_false()
		seen[q.people[i]] = true


func test_s7_queue_full_and_leave() -> void:
	var q := GroupMotion.Queue.new(3)
	for i in 3:
		q.join(i, 0.0, 50.0)
	assert_int(q.join(99, 0.0, 50.0)).is_equal(-1)
	q.leave(1)
	assert_int(q.count).is_equal(2)
	assert_int(q.index_of(2)).is_equal(1)
	assert_int(q.join(99, 0.0, 50.0)).is_equal(2)


func test_s7_patience_give_up_in_order() -> void:
	var q := GroupMotion.Queue.new()
	q.join(1, 0.0, 30.0)
	q.join(2, 5.0, 10.0)
	q.join(3, 6.0, 90.0)
	assert_int(q.tick(14.0)).is_equal(0)
	assert_int(q.tick(16.0)).is_equal(1)          # person 2 (5 + 10)
	assert_int(q.gave_up[0]).is_equal(2)
	assert_int(q.index_of(3)).is_equal(1)         # shuffled forward
	assert_int(q.tick(31.0)).is_equal(1)
	assert_int(q.gave_up[0]).is_equal(1)
	assert_int(q.count).is_equal(1)


func test_s7_patience_varies_by_person_within_persona_band() -> void:
	var lo := 1e9
	var hi := 0.0
	for p in 200:
		var v := GroupMotion.patience_of(p, 60.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_float(lo).is_greater_equal(36.0 - 0.01)
	assert_float(hi).is_less_equal(84.0 + 0.01)
	assert_float(hi - lo).is_greater(20.0)


# --- cost -----------------------------------------------------------------------------------------

func test_cost_per_tick_paths() -> void:
	var q := GroupMotion.Queue.new()
	var tk := GroupMotion.Token.new()
	tk.reset(1, 5, 0.0)
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 20000:
		var t := float(i) * 0.05
		tk.advance(t)
		acc += GroupMotion.circle_slot(Vector2.ZERO, 5, i % 5, Vector2.RIGHT).x
		acc += GroupMotion.child_target(Vector2.ZERO, 0.3, i % 7, i % 3, 3, t).x
		acc += GroupMotion.orbit_point(Vector2.ZERO, i % 20, t).x
		acc += GroupMotion.phase_rate(t, t + 0.01, 1.1)
		q.join(i % 8, t, 5.0)
		q.tick(t)
	var us := float(Time.get_ticks_usec() - t0) / 20000.0
	assert_float(acc).is_not_equal(0.0)
	assert_float(us).is_less(60.0)    # a whole tick of every rule for one body of each kind
	prints("group_motion cost per iteration (usec):", us)
