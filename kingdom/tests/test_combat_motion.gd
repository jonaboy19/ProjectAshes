extends GdUnitTestSuite
## Root-motion attacks + motion warping (scripts/combat/combat_motion.gd): the body steps into a target and stops at
## the standoff by the contact frame, turns at a capped rate, never enters the victim, and plays the clip 1:1 without one.

const CM := preload("res://scripts/combat/combat_motion.gd")


## A synthetic attack: root moves `travel` m forward between 0.2 s and 0.6 s, clip 1.0 s long.
func _clip(travel: float) -> Animation:
	var a := Animation.new()
	a.length = 1.0
	var tr := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(tr, NodePath("Skeleton3D:root"))
	a.position_track_insert_key(tr, 0.0, Vector3.ZERO)
	a.position_track_insert_key(tr, 0.2, Vector3.ZERO)
	a.position_track_insert_key(tr, 0.6, Vector3(0, 0, travel))
	a.position_track_insert_key(tr, 1.0, Vector3(0, 0, travel))
	return a


## Simulate a body at the origin facing +Z with the target at `target`; returns [final pos, final yaw, motion].
func _run(anim: Animation, target: Vector3, hit := 0.6, seconds := 1.0, yaw := 0.0, moving := Vector3.ZERO) -> Array:
	var m := CM.new()
	m.begin(anim, 1.0, hit, 1.0, 1.2)
	var pos := Vector3.ZERO
	var dt := 1.0 / 60.0
	var tgt := target
	for i in int(seconds / dt):
		var r := m.step(dt, yaw, (tgt - pos) if tgt != Vector3.INF else Vector3.ZERO)
		pos += (r["vel"] as Vector3) * dt
		yaw = float(r["yaw"])
		tgt += moving * dt
	return [pos, yaw, m]


func test_profile_reads_root_track() -> void:
	var p := CM.profile(_clip(0.8))
	assert_int(p.size()).is_equal(31)
	assert_float(CM.forward_between(p, 0.0, 1.0)).is_equal_approx(0.8, 0.001)


func test_no_target_plays_clip_one_to_one() -> void:
	var r := _run(_clip(0.8), Vector3.INF)
	assert_float((r[0] as Vector3).z).is_equal_approx(0.8, 0.02)


func test_far_target_is_reached_at_standoff_by_contact() -> void:
	var r := _run(_clip(1.2), Vector3(0, 0, 3.0), 0.6, 0.6)
	assert_float(3.0 - (r[0] as Vector3).z).is_equal_approx(1.2, 0.05)   # scaled 1.2 -> 1.8 m


func test_near_target_shrinks_the_step() -> void:
	var r := _run(_clip(0.8), Vector3(0, 0, 1.5), 0.6, 0.6)
	assert_float((r[0] as Vector3).z).is_less(0.4)
	assert_float((r[0] as Vector3).z).is_greater(0.1)


func test_scale_is_clamped() -> void:
	assert_float(CM.warp_scale(0.5, 20.0)).is_equal(CM.MAX_SCALE)
	assert_float(CM.warp_scale(0.5, -3.0)).is_equal(CM.MIN_SCALE)
	assert_float(CM.warp_scale(0.0, 2.0)).is_equal(1.0)


func test_in_place_clip_gets_capped_added_step() -> void:
	var r := _run(_clip(0.0), Vector3(0, 0, 2.5), 0.6, 1.0)
	assert_float((r[0] as Vector3).z).is_equal_approx(CM.MAX_ADD, 0.06)
	var far := _run(_clip(0.0), Vector3(0, 0, 5.5), 0.6, 1.0)
	assert_float((far[0] as Vector3).z).is_less_equal(CM.MAX_ADD + 0.01)


func test_never_enters_the_victim() -> void:
	var r := _run(_clip(2.5), Vector3(0, 0, 1.0), 0.9, 1.0)
	assert_float((r[0] as Vector3).z).is_less_equal(maxf(1.0 - CM.MIN_GAP, 0.0) + 0.01)


func test_turn_is_rate_limited_and_converges() -> void:
	var y := CM.turn_step(0.0, PI * 0.5, 0.1)
	assert_float(y).is_equal_approx(0.9, 0.001)
	var r := _run(_clip(0.8), Vector3(3.0, 0, 0), 0.6, 0.6)
	assert_float(float(r[1])).is_equal_approx(PI * 0.5, 0.05)


func test_moving_target_is_tracked() -> void:
	var r := _run(_clip(1.6), Vector3(0, 0, 3.0), 0.6, 0.6, 0.0, Vector3(0, 0, 1.0))
	var tgt_end := 3.0 + 0.6
	assert_float(tgt_end - (r[0] as Vector3).z).is_equal_approx(1.2, 0.12)


func test_out_of_range_target_not_chased() -> void:
	var r := _run(_clip(0.8), Vector3(0, 0, 9.0), 0.6, 1.0)
	assert_float((r[0] as Vector3).z).is_equal_approx(0.8, 0.02)


func test_body_push_separates_only_when_overlapping() -> void:
	assert_vector(CM.body_push(Vector3.ZERO, Vector3(0, 0, 2.0))).is_equal(Vector3.ZERO)
	var p := CM.body_push(Vector3.ZERO, Vector3(0, 0, 0.5))
	assert_float(p.z).is_less(0.0)                     # pushed away from the other body
	assert_float(p.length()).is_equal_approx((CM.BODY_GAP - 0.5) * CM.PUSH_RATE, 0.001)
	assert_float(CM.body_push(Vector3.ZERO, Vector3.ZERO).length()).is_greater(0.0)   # exact overlap still resolves


func test_limit_approach_stops_closing_at_the_gap_but_keeps_sideways() -> void:
	var v := Vector3(0, 0, 4.0)
	assert_vector(CM.limit_approach(v, Vector3.ZERO, Vector3(0, 0, 3.0))).is_equal(v)
	assert_float(CM.limit_approach(v, Vector3.ZERO, Vector3(0, 0, CM.BODY_GAP)).z).is_equal_approx(0.0, 0.001)
	var side := CM.limit_approach(Vector3(2, 0, 4), Vector3.ZERO, Vector3(0, 0, CM.BODY_GAP))
	assert_float(side.x).is_equal_approx(2.0, 0.001)
	assert_vector(CM.limit_approach(Vector3(0, 0, -3), Vector3.ZERO, Vector3(0, 0, 0.5))).is_equal(Vector3(0, 0, -3))
